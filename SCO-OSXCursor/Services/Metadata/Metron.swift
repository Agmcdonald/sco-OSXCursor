//
//  Metron.swift
//  SCO-OSXCursor
//
//  Metron (metron.cloud) metadata integration: provider setting, config,
//  daily quota tracker, throttle, DTOs, API client, link parser, and the
//  fetch fill logic. Mirrors the structure of ComicVine.swift.
//
//  API notes (metron.cloud/api):
//  - Auth: HTTP Basic with the user's free Metron account credentials.
//  - Limits: 20 requests/minute + 5,000 requests/day — we self-throttle
//    to ~1 request / 3.1s and track a rolling daily budget.
//  - DRF-style pagination ({count, next, results}); we read page 1 only.
//  - Cover image URLs are decoded but never downloaded (out of scope).
//

import Foundation
import Combine
import SwiftUI
import os

// MARK: - Provider setting

/// Which provider comic (non-ebook) fetches use. Ebook routing is separate.
enum ComicSource: String, CaseIterable, Identifiable {
    case comicVine = "ComicVine"
    case metron = "Metron"

    static let defaultsKey = "comicMetadataProvider"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// The user's chosen source; ComicVine when unset (pre-Metron behavior).
    static var current: ComicSource {
        ComicSource(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .comicVine
    }
}

// MARK: - Configuration

enum MetronConfig {
    static let usernameDefaultsKey = "metronUsername"
    static let passwordDefaultsKey = "metronPassword"

    static var username: String {
        (UserDefaults.standard.string(forKey: usernameDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var password: String {
        (UserDefaults.standard.string(forKey: passwordDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasCredentials: Bool { !username.isEmpty && !password.isEmpty }

    /// "Basic <base64(user:pass)>" for the Authorization header.
    static var authorizationValue: String {
        let raw = "\(username):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}

// MARK: - Daily Quota Tracker

/// Rolling-24h call counter, persisted so the readout survives relaunches.
/// Metron allows 5,000 requests/day (more for donors); a rolling window is
/// conservative vs. the server's fixed daily reset.
@MainActor
final class MetronQuota: ObservableObject {
    static let shared = MetronQuota()
    static let dailyLimit = 5000

    @Published private(set) var callTimestamps: [Date] = []

    private let defaultsKey = "metronCallTimestamps"
    private static let day: TimeInterval = 24 * 3600

    private init() {
        if let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Double] {
            callTimestamps = stored.map { Date(timeIntervalSince1970: $0) }
        }
        prune()
    }

    func recordCall() {
        prune()
        callTimestamps.append(Date())
        save()
    }

    /// Calls made in the trailing 24 hours.
    var callsInLastDay: Int {
        callTimestamps.filter { $0 > Date().addingTimeInterval(-Self.day) }.count
    }

    /// When the OLDEST call in the window ages out — when budget returns.
    var nextReset: Date? {
        callTimestamps
            .filter { $0 > Date().addingTimeInterval(-Self.day) }
            .min()?
            .addingTimeInterval(Self.day)
    }

    private func prune() {
        // Keep a little history beyond the day for clock skew, cap size.
        callTimestamps = callTimestamps.suffix(6000).filter {
            $0 > Date().addingTimeInterval(-2 * Self.day)
        }
    }

    private func save() {
        UserDefaults.standard.set(callTimestamps.map { $0.timeIntervalSince1970 }, forKey: defaultsKey)
    }
}

// MARK: - Request throttle

/// Metron allows 20 requests/minute — 3.1s spacing keeps us safely under.
actor MetronThrottle {
    static let shared = MetronThrottle()
    private let minInterval: TimeInterval = 3.1
    private var lastRequest: Date = .distantPast

    func wait() async {
        let now = Date()
        let earliest = lastRequest.addingTimeInterval(minInterval)
        if earliest > now {
            let delay = earliest.timeIntervalSince(now)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequest = Date()
    }
}

// MARK: - DTOs

/// DRF page envelope. We only ever read the first page.
struct MTPage<T: Decodable>: Decodable {
    let count: Int
    let results: [T]
}

struct MTGenericItem: Decodable {
    let id: Int
    let name: String
}

/// Series LIST row (`series/?name=…`). The display name arrives in the
/// JSON key "series" (detail responses use "name" — see MTSeriesDetail).
struct MTSeriesResult: Decodable {
    let id: Int
    let series: String?
    let yearBegan: Int?
    let yearEnd: Int?
    let volume: Int?
    let issueCount: Int?
    let publisher: MTGenericItem?

    enum CodingKeys: String, CodingKey {
        case id, series, volume, publisher
        case yearBegan = "year_began"
        case yearEnd = "year_end"
        case issueCount = "issue_count"
    }
}

/// Series DETAIL (`series/<id>/`).
struct MTSeriesDetail: Decodable {
    let id: Int
    let name: String?
    let yearBegan: Int?
    let volume: Int?
    let issueCount: Int?
    let publisher: MTGenericItem?

    enum CodingKeys: String, CodingKey {
        case id, name, volume, publisher
        case yearBegan = "year_began"
        case issueCount = "issue_count"
    }
}

/// Common projection of a Metron series used by scoring, candidates, and
/// the fill path, regardless of whether it came from a list or detail call.
struct MTSeriesRef {
    let id: Int
    let name: String?
    let yearBegan: Int?
    let publisher: String?
    let issueCount: Int?

    init(listRow: MTSeriesResult) {
        id = listRow.id
        name = listRow.series
        yearBegan = listRow.yearBegan
        publisher = listRow.publisher?.name
        issueCount = listRow.issueCount
    }

    init(detail: MTSeriesDetail) {
        id = detail.id
        name = detail.name
        yearBegan = detail.yearBegan
        publisher = detail.publisher?.name
        issueCount = detail.issueCount
    }

    init(id: Int, name: String?, yearBegan: Int?, publisher: String?, issueCount: Int?) {
        self.id = id
        self.name = name
        self.yearBegan = yearBegan
        self.publisher = publisher
        self.issueCount = issueCount
    }
}

/// The `series` object embedded in an issue list row. Decoded so the
/// caller can sanity-check that the rows really belong to the series it
/// asked for (a mis-named filter param used to return the whole database).
struct MTIssueSeriesInfo: Decodable {
    let name: String?
}

/// Issue LIST row (`issue/?series_id=<id>&number=<n>`).
struct MTIssueResult: Decodable {
    let id: Int
    let number: String?
    let issueName: String?      // "Superman (2016) #6"
    let coverDate: String?      // "2016-11-01"
    let storeDate: String?
    let series: MTIssueSeriesInfo?

    enum CodingKeys: String, CodingKey {
        case id, number, series
        case issueName = "issue"
        case coverDate = "cover_date"
        case storeDate = "store_date"
    }

    init(
        id: Int, number: String?, issueName: String?,
        coverDate: String?, storeDate: String?,
        series: MTIssueSeriesInfo? = nil
    ) {
        self.id = id
        self.number = number
        self.issueName = issueName
        self.coverDate = coverDate
        self.storeDate = storeDate
        self.series = series
    }
}

struct MTCredit: Decodable {
    let creator: String?
    let roles: [MTGenericItem]

    enum CodingKeys: String, CodingKey {
        case creator
        case roles = "role"
    }
}

/// Issue DETAIL (`issue/<id>/`). `image` is decoded for future use but
/// never downloaded (covers are out of scope by design).
struct MTIssueDetail: Decodable {
    let id: Int
    let number: String?
    let collectionTitle: String?   // JSON "title" — TPB/collection title
    let storyTitles: [String]?     // JSON "name" — per-issue story titles
    let coverDate: String?
    let storeDate: String?
    let desc: String?
    let image: String?
    let credits: [MTCredit]?
    let arcs: [MTGenericItem]?
    let characters: [MTGenericItem]?
    let teams: [MTGenericItem]?

    enum CodingKeys: String, CodingKey {
        case id, number, desc, image, credits, arcs, characters, teams
        case collectionTitle = "title"
        case storyTitles = "name"
        case coverDate = "cover_date"
        case storeDate = "store_date"
    }
}

/// Minimal projection to resolve an issue's parent series ID.
struct MTIssueSeriesRef: Decodable {
    struct SeriesRef: Decodable { let id: Int }
    let series: SeriesRef?
}

// MARK: - Date helpers

enum MetronDates {
    /// Metron dates are plain "yyyy-MM-dd" strings.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return formatter.date(from: s)
    }

    static func year(from s: String?) -> Int? {
        guard let s, s.count >= 4, let year = Int(s.prefix(4)) else { return nil }
        return year
    }

    /// Metron dates are calendar days pinned to UTC midnight, so they must be
    /// rendered in UTC too — local formatting slides them a day west of UTC.
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = .autoupdatingCurrent
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// The calendar day of `date` as stored, formatted for the user's locale.
    static func display(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }
}

// MARK: - API Client

final class MetronService {
    static let shared = MetronService()

    private let baseURL = "https://metron.cloud/api"
    private let userAgent = "SuperComicOrganizer/1.0 (personal library app)"

    enum MTError: LocalizedError {
        case noCredentials
        case badURL
        case unauthorized
        case rateLimited(retryAfter: Date?)
        case http(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "No Metron username/password configured."
            case .badURL:
                return "Could not build the request URL."
            case .unauthorized:
                return "Metron sign-in failed — check username/password in Settings."
            case .rateLimited(let retryAfter):
                if let retryAfter {
                    let time = retryAfter.formatted(date: .omitted, time: .shortened)
                    return "Metron rate limit reached. Try again after \(time)."
                }
                return "Metron rate limit reached. Try again shortly."
            case .http(let code):
                return "Metron returned HTTP \(code)."
            case .badResponse:
                return "Metron returned an unexpected response."
            }
        }
    }

    private func request<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        guard MetronConfig.hasCredentials else { throw MTError.noCredentials }

        var components = URLComponents(string: "\(baseURL)/\(path)")
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw MTError.badURL }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(MetronConfig.authorizationValue, forHTTPHeaderField: "Authorization")

        await MetronThrottle.shared.wait()
        await MainActor.run { MetronQuota.shared.recordCall() }
        AppLog.metadata.info("[Metron] → \(path)")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200: break
            case 401, 403: throw MTError.unauthorized
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init)
                    .map { Date().addingTimeInterval($0) }
                throw MTError.rateLimited(retryAfter: retryAfter)
            default: throw MTError.http(http.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            AppLog.metadata.error("[Metron] Decode failed for \(path): \(error.localizedDescription)")
            throw MTError.badResponse
        }
    }

    /// Search series by name. 1 API call.
    func searchSeries(_ name: String) async throws -> [MTSeriesResult] {
        let page: MTPage<MTSeriesResult> = try await request(
            path: "series/",
            query: [URLQueryItem(name: "name", value: name)]
        )
        return page.results
    }

    /// Query items for the issue list endpoint.
    ///
    /// Metron's `IssueFilter` names the series filter `series_id`
    /// (`NumberFilter(field_name="series__id")`) — django-filter silently
    /// DROPS unknown params, so the older `series=<id>` spelling returned
    /// page 1 of every issue with that number in the whole database and the
    /// fill applied a stranger's credits. Pure + static so it can be tested
    /// without touching the network.
    static func issueQuery(seriesID: Int, issueNumber: String?) -> [URLQueryItem] {
        var query = [URLQueryItem(name: "series_id", value: String(seriesID))]
        if let issueNumber, !issueNumber.isEmpty {
            query.append(URLQueryItem(name: "number", value: issueNumber))
        }
        return query
    }

    /// Issues of a series, optionally filtered to one issue number. 1 call.
    func issues(seriesID: Int, issueNumber: String?) async throws -> [MTIssueResult] {
        let page: MTPage<MTIssueResult> = try await request(
            path: "issue/",
            query: Self.issueQuery(seriesID: seriesID, issueNumber: issueNumber)
        )
        return page.results
    }

    /// First page of a series' issues (for local number matching when the
    /// filtered lookup comes back empty). 1 API call.
    func issuesForSeries(seriesID: Int) async throws -> [MTIssueResult] {
        try await issues(seriesID: seriesID, issueNumber: nil)
    }

    /// Full issue details (credits, arcs, characters, teams). 1 API call.
    func issueDetail(id: Int) async throws -> MTIssueDetail {
        try await request(path: "issue/\(id)/")
    }

    /// One series by ID (pasted-link override). 1 API call.
    func seriesDetail(id: Int) async throws -> MTSeriesDetail {
        try await request(path: "series/\(id)/")
    }

    /// Resolve an issue ID to its parent series ID. 1 API call.
    func seriesID(forIssueID id: Int) async throws -> Int? {
        let ref: MTIssueSeriesRef = try await request(path: "issue/\(id)/")
        return ref.series?.id
    }
}

// MARK: - Link / ID parsing

/// A reference parsed from a pasted metron.cloud link or ID.
enum MTReference: Equatable {
    case series(Int)
    case issue(Int)
}

/// Extracts a Metron series/issue reference from a pasted URL or number.
/// Metron's public site uses slug URLs (no numeric ID), so only API-style
/// numeric URLs and bare IDs are accepted; slugs are rejected so the UI
/// can explain what to paste instead.
enum MTLinkParser {
    static func parse(_ raw: String) -> MTReference? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // "series/<digits>" or "issue/<digits>" anywhere in the string. The
        // lookahead requires a path/query/fragment boundary (or end of input)
        // after the digits, so digit-leading slugs like "series/2000-ad-1977/"
        // are rejected rather than yielding a wrong ID.
        if let range = trimmed.range(of: #"(series|issue)/(\d+)(?=/|$|[?#])"#, options: .regularExpression) {
            let token = trimmed[range]
            let parts = token.split(separator: "/")
            if parts.count == 2, let id = Int(parts[1]) {
                return parts[0] == "series" ? .series(id) : .issue(id)
            }
        }

        // Bare numeric input → assume a series ID.
        if let id = Int(trimmed) { return .series(id) }
        return nil
    }
}

// MARK: - Matching

enum MetronMatcher {
    /// Same scoring math as ComicVine — one shared core.
    static func score(_ ref: MTSeriesRef, against comic: Comic, query: String) -> Double {
        ComicVineMatcher.score(
            name: ref.name, startYear: ref.yearBegan, publisher: ref.publisher,
            against: comic, query: query
        )
    }
}

// MARK: - Shared fetch core

/// Fills a `Comic` from Metron data. The two `apply*` functions are pure
/// (no persistence, no network) so they're unit-testable; `fill`
/// orchestrates the network calls, mirroring `ComicVineFetcher.fill`.
enum MetronFetcher {

    /// Series-level fields: series name canonical; publisher/year fill
    /// blanks only; records the Metron series ID.
    static func applySeries(_ ref: MTSeriesRef, to comic: Comic) -> Comic {
        var updated = comic
        if let name = ref.name, !name.isEmpty { updated.series = name }
        if updated.publisher == nil || updated.publisher?.isEmpty == true {
            updated.publisher = ref.publisher
        }
        if updated.year == nil {
            updated.year = ref.yearBegan
        }
        updated.metronSeriesID = ref.id
        return updated
    }

    /// Issue-level fields from a list row + optional detail. Blank-fill
    /// scalars; replace-but-never-wipe arcs/characters/teams.
    static func applyIssue(list: MTIssueResult, detail: MTIssueDetail?, to comic: Comic) -> Comic {
        var updated = comic
        updated.metronIssueID = list.id

        if updated.year == nil {
            updated.year = MetronDates.year(from: list.coverDate ?? detail?.coverDate)
        }
        if updated.storeDate == nil {
            updated.storeDate = MetronDates.parse(list.storeDate ?? detail?.storeDate)
        }

        guard let detail else { return updated }

        if updated.title == nil || updated.title?.isEmpty == true {
            let storyTitle = detail.storyTitles?.first(where: { !$0.isEmpty })
            let collection = (detail.collectionTitle?.isEmpty == false) ? detail.collectionTitle : nil
            updated.title = storyTitle ?? collection
        }
        if updated.summary == nil || updated.summary?.isEmpty == true {
            updated.summary = ComicVineMatcher.stripHTML(detail.desc)
        }

        // Credits: adapt Metron's structured roles to the shared role-name
        // matcher (one CVPersonCredit per creator-role pair).
        if let credits = detail.credits {
            let flat = credits.flatMap { credit in
                credit.roles.map { CVPersonCredit(name: credit.creator, role: $0.name) }
            }
            ComicVineMatcher.applyCredits(flat, to: &updated)
        }

        // Metron authoritative when non-empty; never wipe with empty.
        let arcNames = (detail.arcs ?? []).map(\.name).filter { !$0.isEmpty }
        if !arcNames.isEmpty { updated.storyArcs = arcNames }
        let characterNames = (detail.characters ?? []).map(\.name).filter { !$0.isEmpty }
        if !characterNames.isEmpty { updated.characters = characterNames }
        let teamNames = (detail.teams ?? []).map(\.name).filter { !$0.isEmpty }
        if !teamNames.isEmpty { updated.teams = teamNames }

        return updated
    }

    /// Full fill: series fields, then (when the issue number is known)
    /// issue list + detail. 1–3 API calls. Marks the comic fetched.
    static func fill(_ comic: Comic, from ref: MTSeriesRef) async -> Comic {
        var updated = applySeries(ref, to: comic)

        if let issueNumber = ComicVineMatcher.normalizedIssueNumber(comic.issueNumber) {
            do {
                var issues = try await MetronService.shared.issues(
                    seriesID: ref.id, issueNumber: issueNumber
                )
                // Fallback: list the series' issues and match the
                // normalized number locally (mirrors the ComicVine path).
                if issues.isEmpty {
                    let all = try await MetronService.shared.issuesForSeries(seriesID: ref.id)
                    if let match = all.first(where: {
                        ComicVineMatcher.normalizedIssueNumber($0.number) == issueNumber
                    }) {
                        issues = [match]
                    }
                }
                if let issue = issues.first {
                    let detail = try? await MetronService.shared.issueDetail(id: issue.id)
                    updated = applyIssue(list: issue, detail: detail, to: updated)
                    AppLog.metadata.info("[Metron] Issue #\(issueNumber) matched (id \(issue.id)) for series \(ref.id) — writer:\(updated.writer ?? "–") artist:\(updated.artist ?? "–")")
                } else {
                    AppLog.metadata.info("[Metron] No issue #\(issueNumber) found in series \(ref.id)")
                }
            } catch {
                // Series data still worth keeping; log and continue.
                AppLog.metadata.error("[Metron] Issue lookup failed: \(error.localizedDescription)")
            }
        }

        updated.metadataFetchedAt = Date()
        updated.metadataCandidates = nil
        return updated
    }
}

// MARK: - Fetch Flow

extension LibraryViewModel {

    /// Route a comic fetch to the user's chosen provider.
    @MainActor
    func fetchComicMetadata(
        for comic: Comic, force: Bool, autoApplyConfident: Bool = true
    ) async -> ComicVineFetchOutcome {
        switch ComicSource.current {
        case .comicVine:
            return await fetchComicVineMetadata(
                for: comic, force: force, autoApplyConfident: autoApplyConfident)
        case .metron:
            return await fetchMetronMetadata(
                for: comic, force: force, autoApplyConfident: autoApplyConfident)
        }
    }

    /// Fetch Metron metadata for one book. Mirrors fetchComicVineMetadata:
    /// never re-fetches unless forced, stores top-5 candidates (tagged
    /// "Metron") when ambiguous, honors autoApplyConfident.
    @MainActor
    func fetchMetronMetadata(
        for comic: Comic, force: Bool, autoApplyConfident: Bool = true
    ) async -> ComicVineFetchOutcome {
        guard MetronConfig.hasCredentials else { return .noKey }
        if !force, comic.metadataFetchedAt != nil { return .alreadyFetched }
        if !force, comic.metadataCandidates != nil { return .needsChoice }

        let query = comic.series
            ?? comic.title
            ?? (comic.fileName as NSString).deletingPathExtension

        do {
            let rows = try await MetronService.shared.searchSeries(query)
            guard !rows.isEmpty else { return .noMatches }

            let refs = rows.map(MTSeriesRef.init(listRow:))
            let scored = refs
                .map { (ref: $0, score: MetronMatcher.score($0, against: comic, query: query)) }
                .sorted { $0.score > $1.score }

            let best = scored[0]
            let second = scored.count > 1 ? scored[1].score : 0
            let confident = scored.count == 1 || (best.score >= 0.75 && best.score - second >= 0.2)

            if confident && autoApplyConfident {
                return await applyMetronSeries(best.ref, to: comic)
            }

            let candidates = scored.prefix(5).map { item in
                CVCandidate(
                    id: item.ref.id,
                    name: item.ref.name ?? "Unknown",
                    startYear: item.ref.yearBegan,
                    publisher: item.ref.publisher,
                    issueCount: item.ref.issueCount,
                    provider: "Metron"
                )
            }
            var updated = comic
            updated.metadataCandidates = CVCandidate.encodeList(Array(candidates))
            updated.dateModified = Date()
            updateComic(updated)
            return .needsChoice
        } catch let error as MetronService.MTError {
            if case .rateLimited(let retryAfter) = error {
                return .rateLimited(retryAfter: retryAfter)
            }
            // A rejected sign-in won't fix itself on the next book — surface it
            // as its own outcome so batch loops can stop immediately.
            if case .unauthorized = error {
                return .unauthorized
            }
            AppLog.metadata.error("[Metron] Fetch failed: \(error.localizedDescription)")
            return .failed(error.errorDescription ?? "Metron request failed.")
        } catch {
            AppLog.metadata.error("[Metron] Fetch failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Provider-routed batch fetch. Stops early when Metron rate-limits.
    @MainActor
    func fetchComicMetadataBatch(
        for comics: [Comic],
        onProgress: @MainActor (Int, Int) -> Void = { _, _ in }
    ) async -> BatchResult {
        guard ComicSource.current == .metron else {
            return await fetchComicVineMetadataBatch(for: comics, onProgress: onProgress)
        }

        var result = BatchResult()
        guard MetronConfig.hasCredentials else {
            result.noKey = true
            return result
        }
        let autoApply = UserDefaults.standard.object(forKey: "autoApplyConfidentMatches") as? Bool ?? true
        let total = comics.count
        for (index, comic) in comics.enumerated() {
            let latest = self.comics.first(where: { $0.id == comic.id }) ?? comic
            let outcome = await fetchMetronMetadata(
                for: latest, force: false, autoApplyConfident: autoApply
            )
            switch outcome {
            case .updated: result.updated += 1
            case .needsChoice:
                result.needChoice += 1
                result.pendingReviewIDs.append(latest.id)
            case .alreadyFetched: result.skipped += 1
            case .noMatches: result.noMatch += 1
            case .failed: result.failed += 1
            case .noKey: result.noKey = true
            case .rateLimited:
                // Budget gone — stop burning the queue; the rest stay unfetched.
                AppLog.metadata.error("[Metron] Rate limited — stopping batch with \(comics.count - index) books unattempted")
                result.failed += comics.count - index
                onProgress(total, total)
                return result
            case .unauthorized:
                // Bad credentials — every remaining book would 401 the same way.
                AppLog.metadata.error("[Metron] Sign-in rejected — stopping batch with \(comics.count - index) books unattempted")
                result.failed += comics.count - index
                result.noKey = false
                result.authFailed = true
                onProgress(total, total)
                return result
            }
            onProgress(index + 1, total)
        }
        return result
    }

    /// Apply a stored candidate through the provider that produced it.
    @MainActor
    func applyMetadataCandidate(_ candidate: CVCandidate, to comic: Comic) async -> ComicVineFetchOutcome {
        if candidate.isMetron {
            let ref = MTSeriesRef(
                id: candidate.id, name: candidate.name,
                yearBegan: candidate.startYear, publisher: candidate.publisher,
                issueCount: candidate.issueCount
            )
            return await applyMetronSeries(ref, to: comic)
        }
        return await applyComicVineCandidate(candidate, to: comic)
    }

    /// Apply a pasted metron.cloud link/ID (match-picker override).
    @MainActor
    func applyMetronLink(_ raw: String, to comic: Comic) async -> ComicVineFetchOutcome {
        guard MetronConfig.hasCredentials else { return .noKey }
        guard let ref = MTLinkParser.parse(raw) else {
            return .failed("Paste a numeric Metron ID or an api/series/<id> link — Metron's site URLs (slugs) don't carry the ID.")
        }
        do {
            let detail: MTSeriesDetail
            switch ref {
            case .series(let id):
                // A bare number is ambiguous — the parser assumes a series ID,
                // but users paste issue IDs too. Try series first; on a 404,
                // retry the same number as an issue ID (one extra request pair).
                do {
                    detail = try await MetronService.shared.seriesDetail(id: id)
                } catch MetronService.MTError.http(404) {
                    do {
                        guard let resolved = try await MetronService.shared.seriesID(forIssueID: id) else {
                            return .failed("No Metron series or issue found with ID \(id).")
                        }
                        detail = try await MetronService.shared.seriesDetail(id: resolved)
                    } catch MetronService.MTError.http {
                        // Neither a series nor an issue carries this ID.
                        return .failed("No Metron series or issue found with ID \(id).")
                    }
                    // rateLimited / unauthorized fall through to the outer catch.
                }
            case .issue(let id):
                guard let resolved = try await MetronService.shared.seriesID(forIssueID: id) else {
                    return .failed("Couldn't find the series for that issue.")
                }
                detail = try await MetronService.shared.seriesDetail(id: resolved)
            }
            return await applyMetronSeries(MTSeriesRef(detail: detail), to: comic)
        } catch {
            // Don't downgrade a 429 to a generic failure — the caller shows a
            // "try again after …" message for the rate-limited case.
            if let mtError = error as? MetronService.MTError {
                if case .rateLimited(let retryAfter) = mtError {
                    return .rateLimited(retryAfter: retryAfter)
                }
                if case .unauthorized = mtError {
                    return .unauthorized
                }
            }
            AppLog.metadata.error("[Metron] Link match failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Link override routed by the active provider (used by pickers when
    /// the pending candidates are provider-tagged; falls back to setting).
    @MainActor
    func applyProviderLink(_ raw: String, to comic: Comic) async -> ComicVineFetchOutcome {
        let pending = CVCandidate.decodeList(comic.metadataCandidates)
        let useMetron = pending.first?.isMetron ?? (ComicSource.current == .metron)
        return useMetron
            ? await applyMetronLink(raw, to: comic)
            : await applyComicVineLink(raw, to: comic)
    }

    @MainActor
    private func applyMetronSeries(_ ref: MTSeriesRef, to comic: Comic) async -> ComicVineFetchOutcome {
        let current = comics.first(where: { $0.id == comic.id }) ?? comic
        let snapshot = CVMetadataSnapshot(of: current)
        var updated = await MetronFetcher.fill(current, from: ref)
        updated.metadataBackup = snapshot.encoded()
        updated.metadataSource = "Metron"
        updated.dateModified = Date()
        updateComic(updated)
        return .updated
    }
}

// MARK: - Provider UI helpers

extension ComicSource {
    /// True when the active provider has usable credentials.
    var hasCredentials: Bool {
        switch self {
        case .comicVine: return ComicVineConfig.hasKey
        case .metron: return MetronConfig.hasCredentials
        }
    }

    /// "Add a ComicVine API key…" / "Add your Metron username…" hint.
    var credentialsHint: String {
        switch self {
        case .comicVine:
            return "Add a ComicVine API key in Settings first."
        case .metron:
            return "Add your Metron username and password in Settings first."
        }
    }
}
