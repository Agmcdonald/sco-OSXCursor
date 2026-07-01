//
//  ComicVine.swift
//  SCO-OSXCursor
//
//  ComicVine metadata integration: API client, hourly quota tracker,
//  match scoring, fetch flow, and the ambiguous-match picker sheet.
//
//  API notes (comicvine.gamespot.com/api):
//  - Auth: user-supplied api_key query parameter (free account).
//  - Limit: 200 requests per resource per hour, plus velocity detection —
//    responses must be cached, which is why fetch state lives on the Comic
//    record and a book is never re-fetched unless the user forces it.
//  - A custom User-Agent is required; default agents are rejected.
//

import Foundation
import Combine
import SwiftUI
import os

// MARK: - Configuration

enum ComicVineConfig {
    static let apiKeyDefaultsKey = "comicVineAPIKey"

    static var apiKey: String {
        (UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasKey: Bool { !apiKey.isEmpty }
}

// MARK: - Hourly Quota Tracker

/// Rolling-hour call counter, persisted so the dashboard number survives
/// relaunches. ComicVine allows 200 requests/resource/hour; we count every
/// request against one shared budget (conservative, simpler to reason about).
@MainActor
final class ComicVineQuota: ObservableObject {
    static let shared = ComicVineQuota()
    static let hourlyLimit = 200

    @Published private(set) var callTimestamps: [Date] = []

    private let defaultsKey = "comicVineCallTimestamps"

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

    /// Calls made in the trailing 60 minutes
    var callsInLastHour: Int {
        callTimestamps.filter { $0 > Date().addingTimeInterval(-3600) }.count
    }

    /// When the OLDEST call in the window ages out — i.e. when budget starts
    /// coming back. Nil when no calls in the window.
    var nextReset: Date? {
        callTimestamps
            .filter { $0 > Date().addingTimeInterval(-3600) }
            .min()?
            .addingTimeInterval(3600)
    }

    private func prune() {
        // Keep a little history beyond the hour for clock skew, cap size
        callTimestamps = callTimestamps.suffix(400).filter {
            $0 > Date().addingTimeInterval(-2 * 3600)
        }
    }

    private func save() {
        UserDefaults.standard.set(callTimestamps.map { $0.timeIntervalSince1970 }, forKey: defaultsKey)
    }
}

// MARK: - DTOs

struct CVResponse<T: Decodable>: Decodable {
    let statusCode: Int
    let error: String
    let results: T

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case error, results
    }
}

struct CVPublisher: Decodable {
    let name: String?
}

struct CVVolumeResult: Decodable {
    let id: Int
    let name: String?
    let startYear: String?
    let publisher: CVPublisher?
    let countOfIssues: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, publisher
        case startYear = "start_year"
        case countOfIssues = "count_of_issues"
    }
}

struct CVIssueResult: Decodable {
    let id: Int
    let name: String?
    let issueNumber: String?
    let coverDate: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case issueNumber = "issue_number"
        case coverDate = "cover_date"
    }
}

struct CVPersonCredit: Decodable {
    let name: String?
    let role: String?
}

struct CVIssueDetail: Decodable {
    let id: Int
    let name: String?
    let description: String?
    let coverDate: String?
    let personCredits: [CVPersonCredit]?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case coverDate = "cover_date"
        case personCredits = "person_credits"
    }
}

/// Minimal projection of an issue used to resolve its parent volume ID when
/// the user pastes an *issue* link instead of a volume link.
struct CVIssueVolumeRef: Decodable {
    struct VolumeRef: Decodable { let id: Int }
    let volume: VolumeRef?
}

/// Stored on the Comic record (JSON) when a search is ambiguous, so the
/// user can resolve it now or any time later without another API call.
struct CVCandidate: Codable, Identifiable, Hashable {
    let id: Int          // ComicVine volume ID
    let name: String
    let startYear: Int?
    let publisher: String?
    let issueCount: Int?

    static func encodeList(_ list: [CVCandidate]) -> String? {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decodeList(_ json: String?) -> [CVCandidate] {
        guard let json = json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([CVCandidate].self, from: data)) ?? []
    }
}

// MARK: - Request throttle

/// Serializes ComicVine requests and enforces a minimum spacing between them.
/// ComicVine runs velocity detection and returns HTTP 403 for bursts, so we
/// keep to ~1 request/second regardless of how many fetches are queued.
actor CVThrottle {
    static let shared = CVThrottle()
    private let minInterval: TimeInterval = 1.1
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

// MARK: - API Client

final class ComicVineService {
    static let shared = ComicVineService()

    private let baseURL = "https://comicvine.gamespot.com/api"
    private let userAgent = "SuperComicOrganizer/1.0 (personal library app)"

    enum CVError: LocalizedError {
        case noAPIKey
        case badURL
        case http(Int)
        case api(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No ComicVine API key configured."
            case .badURL: return "Could not build the request URL."
            case .http(let code): return "ComicVine returned HTTP \(code)."
            case .api(let message): return message
            }
        }
    }

    private func request<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        guard ComicVineConfig.hasKey else { throw CVError.noAPIKey }

        var components = URLComponents(string: "\(baseURL)/\(path)")
        var items = query
        items.append(URLQueryItem(name: "api_key", value: ComicVineConfig.apiKey))
        items.append(URLQueryItem(name: "format", value: "json"))
        components?.queryItems = items
        guard let url = components?.url else { throw CVError.badURL }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        // Space out requests (velocity throttle) before counting/sending
        await CVThrottle.shared.wait()
        await MainActor.run { ComicVineQuota.shared.recordCall() }
        AppLog.metadata.info("[ComicVine] → \(path)")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CVError.http(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(CVResponse<T>.self, from: data)
        guard decoded.statusCode == 1 else { throw CVError.api(decoded.error) }
        return decoded.results
    }

    /// Search volumes (series) by name. 1 API call.
    ///
    /// Uses a wide limit because ComicVine's relevance ranking buries small or
    /// brand-new series behind long-running ones with the same name (e.g. a
    /// 2026 "Iron Man" lands far below the 1968 run). Pulling more rows lets the
    /// local matcher sort by year/publisher rather than trusting that ranking.
    /// It's still a single request — only the response is larger.
    func searchVolumes(_ name: String) async throws -> [CVVolumeResult] {
        try await request(
            path: "search/",
            query: [
                URLQueryItem(name: "resources", value: "volume"),
                URLQueryItem(name: "query", value: name),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "field_list", value: "id,name,start_year,publisher,count_of_issues"),
            ]
        )
    }

    /// Issues of a volume, optionally filtered to one issue number. 1 API call.
    func issues(volumeID: Int, issueNumber: String?) async throws -> [CVIssueResult] {
        var filter = "volume:\(volumeID)"
        if let issueNumber = issueNumber, !issueNumber.isEmpty {
            filter += ",issue_number:\(issueNumber)"
        }
        return try await request(
            path: "issues/",
            query: [
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "limit", value: "5"),
                URLQueryItem(name: "field_list", value: "id,name,issue_number,cover_date,description"),
            ]
        )
    }

    /// All issues of a volume (for local issue-number matching when the
    /// filtered lookup comes back empty). 1 API call.
    func issuesForVolume(volumeID: Int, limit: Int = 100) async throws -> [CVIssueResult] {
        try await request(
            path: "issues/",
            query: [
                URLQueryItem(name: "filter", value: "volume:\(volumeID)"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: "issue_number:asc"),
                URLQueryItem(name: "field_list", value: "id,name,issue_number,cover_date,description"),
            ]
        )
    }

    /// Full issue details (creator credits). 1 API call.
    func issueDetail(id: Int) async throws -> CVIssueDetail {
        try await request(
            path: "issue/4000-\(id)/",
            query: [
                URLQueryItem(name: "field_list", value: "id,name,description,cover_date,person_credits"),
            ]
        )
    }

    /// Fetch one volume directly by its ComicVine volume ID. 1 API call.
    /// Used by the "paste a ComicVine link" override so a known volume can be
    /// matched without relying on search ranking (which buries small/new series).
    func volume(id: Int) async throws -> CVVolumeResult {
        try await request(
            path: "volume/4050-\(id)/",
            query: [
                URLQueryItem(name: "field_list", value: "id,name,start_year,publisher,count_of_issues"),
            ]
        )
    }

    /// Resolve the parent volume ID for an issue, so a pasted *issue* link can
    /// be turned into a volume match. 1 API call.
    func volumeID(forIssueID id: Int) async throws -> Int? {
        let ref: CVIssueVolumeRef = try await request(
            path: "issue/4000-\(id)/",
            query: [
                URLQueryItem(name: "field_list", value: "volume"),
            ]
        )
        return ref.volume?.id
    }
}

// MARK: - Fetch Flow

enum ComicVineFetchOutcome {
    case updated
    case needsChoice
    case alreadyFetched
    case noKey
    case noMatches
    case failed(String)
}

extension LibraryViewModel {

    /// Fetch ComicVine metadata for one book.
    /// - Never re-fetches a book that already has results (`metadataFetchedAt`)
    ///   unless `force` — API responses must be cached per ComicVine's terms,
    ///   and it protects the 200-calls/hour budget.
    /// - Ambiguous searches store candidates on the record for the user to
    ///   resolve via the match picker (now or later) at zero extra API cost.
    /// - Parameter autoApplyConfident: when `true` (default), a high-confidence
    ///   match is applied immediately. When `false`, even a confident match is
    ///   stored as a candidate (best first) and returned as `.needsChoice` so
    ///   the caller can ask the user to confirm it. Used by batch review.
    @MainActor
    func fetchComicVineMetadata(
        for comic: Comic,
        force: Bool,
        autoApplyConfident: Bool = true
    ) async -> ComicVineFetchOutcome {
        guard ComicVineConfig.hasKey else { return .noKey }
        if !force, comic.metadataFetchedAt != nil { return .alreadyFetched }
        if !force, comic.metadataCandidates != nil { return .needsChoice }

        let query = comic.series
            ?? comic.title
            ?? (comic.fileName as NSString).deletingPathExtension

        do {
            let volumes = try await ComicVineService.shared.searchVolumes(query)
            guard !volumes.isEmpty else { return .noMatches }

            let scored = volumes
                .map { (volume: $0, score: ComicVineMatcher.score($0, against: comic, query: query)) }
                .sorted { $0.score > $1.score }

            let best = scored[0]
            let second = scored.count > 1 ? scored[1].score : 0
            let confident = scored.count == 1 || (best.score >= 0.75 && best.score - second >= 0.2)

            if confident && autoApplyConfident {
                return await applyVolume(best.volume, to: comic)
            }

            // Either ambiguous, or a confident match the caller wants confirmed:
            // store the top candidates (best first) for the user to resolve.
            let candidates = scored.prefix(5).map { item in
                CVCandidate(
                    id: item.volume.id,
                    name: item.volume.name ?? "Unknown",
                    startYear: item.volume.startYear.flatMap { Int($0) },
                    publisher: item.volume.publisher?.name,
                    issueCount: item.volume.countOfIssues
                )
            }
            var updated = comic
            updated.metadataCandidates = CVCandidate.encodeList(Array(candidates))
            updated.dateModified = Date()
            updateComic(updated)
            return .needsChoice
        } catch {
            AppLog.metadata.error("[ComicVine] Fetch failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Batch fetch over several books (selection). Skips already-fetched
    /// books, throttled by the API client. Ambiguous books keep their stored
    /// candidates so they can be resolved later from Edit → Choose Match.
    struct BatchResult {
        var updated = 0
        var needChoice = 0
        var noMatch = 0
        var failed = 0
        var skipped = 0
        var noKey = false
        /// Books with stored candidates that the user should review/confirm,
        /// in the order they were fetched. Drives the batch review sheet.
        var pendingReviewIDs: [Comic.ID] = []

        var summary: String {
            if noKey { return "Add a ComicVine API key in Settings first." }
            var parts: [String] = []
            if updated > 0 { parts.append("\(updated) updated") }
            if needChoice > 0 { parts.append("\(needChoice) to review") }
            if noMatch > 0 { parts.append("\(noMatch) no match") }
            if skipped > 0 { parts.append("\(skipped) already fetched") }
            if failed > 0 { parts.append("\(failed) failed") }
            return parts.isEmpty ? "Nothing to fetch." : parts.joined(separator: ", ") + "."
        }
    }

    /// Batch fetch over several books (selection), throttled by the API client.
    /// Honors the "Auto-Apply Confident Matches" setting: when off, every book is
    /// routed to the review queue; when on, only ambiguous books are.
    /// - Parameter onProgress: called on the main actor after each book with
    ///   (completed, total) so the caller can show progress.
    @MainActor
    func fetchComicVineMetadataBatch(
        for comics: [Comic],
        onProgress: @MainActor (Int, Int) -> Void = { _, _ in }
    ) async -> BatchResult {
        var result = BatchResult()
        guard ComicVineConfig.hasKey else {
            result.noKey = true
            return result
        }
        let autoApply = UserDefaults.standard.object(forKey: "autoApplyConfidentMatches") as? Bool ?? true
        let total = comics.count
        for (index, comic) in comics.enumerated() {
            // Re-read the latest copy in case an earlier book in the loop
            // changed the array.
            let latest = self.comics.first(where: { $0.id == comic.id }) ?? comic
            let outcome = await fetchComicVineMetadata(
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
            }
            onProgress(index + 1, total)
        }
        return result
    }

    /// User picked a candidate from the match sheet.
    @MainActor
    func applyComicVineCandidate(_ candidate: CVCandidate, to comic: Comic) async -> ComicVineFetchOutcome {
        let volume = CVVolumeResult(
            id: candidate.id,
            name: candidate.name,
            startYear: candidate.startYear.map(String.init),
            publisher: CVPublisher(name: candidate.publisher),
            countOfIssues: candidate.issueCount
        )
        return await applyVolume(volume, to: comic)
    }

    /// Apply a match from a pasted ComicVine link, slug, or numeric ID.
    /// Bypasses search ranking entirely: a volume link is fetched directly; an
    /// issue link is resolved to its parent volume first. The existing
    /// `applyVolume` path then fills issue-level fields from `comic.issueNumber`.
    @MainActor
    func applyComicVineLink(_ raw: String, to comic: Comic) async -> ComicVineFetchOutcome {
        guard ComicVineConfig.hasKey else { return .noKey }
        guard let ref = CVLinkParser.parse(raw) else {
            return .failed("That doesn't look like a ComicVine link or ID.")
        }
        do {
            let volumeID: Int
            switch ref {
            case .volume(let id):
                volumeID = id
            case .issue(let id):
                guard let resolved = try await ComicVineService.shared.volumeID(forIssueID: id) else {
                    return .failed("Couldn't find the series for that issue link.")
                }
                volumeID = resolved
            }
            let volume = try await ComicVineService.shared.volume(id: volumeID)
            return await applyVolume(volume, to: comic)
        } catch {
            AppLog.metadata.error("[ComicVine] Link match failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// User rejected all candidates — clear them so the menu stops offering.
    @MainActor
    func clearComicVineCandidates(for comic: Comic) {
        var updated = comic
        updated.metadataCandidates = nil
        updated.dateModified = Date()
        updateComic(updated)
    }

    @MainActor
    private func applyVolume(_ volume: CVVolumeResult, to comic: Comic) async -> ComicVineFetchOutcome {
        var updated = await ComicVineFetcher.fill(comic, from: volume)
        updated.dateModified = Date()
        updateComic(updated)
        return .updated
    }
}

// MARK: - Shared fetch core

/// Fills a `Comic`'s metadata from a ComicVine volume (and its issue +
/// creator credits when the issue number is known). Pure — no persistence —
/// so both the Library fetch and the Organize staging fetch can share it.
enum ComicVineFetcher {
    static func fill(_ comic: Comic, from volume: CVVolumeResult) async -> Comic {
        var updated = comic

        // Volume-level fields: series is canonical from ComicVine; the rest
        // fill only when missing so user edits are never clobbered
        if let name = volume.name, !name.isEmpty { updated.series = name }
        if updated.publisher == nil || updated.publisher?.isEmpty == true {
            updated.publisher = volume.publisher?.name
        }
        if updated.year == nil {
            updated.year = volume.startYear.flatMap { Int($0) }
        }
        updated.comicVineVolumeID = volume.id

        // Issue-level fields when we know the issue number (2–3 calls max)
        if let issueNumber = ComicVineMatcher.normalizedIssueNumber(comic.issueNumber) {
            do {
                var issues = try await ComicVineService.shared.issues(
                    volumeID: volume.id, issueNumber: issueNumber
                )
                // Fallback: the filtered lookup can miss when ComicVine stores
                // the issue number in an unexpected format — list the volume's
                // issues and match locally on the normalized number.
                if issues.isEmpty {
                    let all = try await ComicVineService.shared.issuesForVolume(volumeID: volume.id)
                    if let match = all.first(where: {
                        ComicVineMatcher.normalizedIssueNumber($0.issueNumber) == issueNumber
                    }) {
                        issues = [match]
                    }
                }
                if let issue = issues.first {
                    updated.comicVineIssueID = issue.id
                    if updated.title == nil || updated.title?.isEmpty == true {
                        updated.title = issue.name
                    }
                    if updated.summary == nil || updated.summary?.isEmpty == true {
                        updated.summary = ComicVineMatcher.stripHTML(issue.description)
                    }
                    if updated.year == nil, let coverDate = issue.coverDate, coverDate.count >= 4 {
                        updated.year = Int(coverDate.prefix(4))
                    }

                    // Creators
                    if let detail = try? await ComicVineService.shared.issueDetail(id: issue.id),
                       let credits = detail.personCredits {
                        ComicVineMatcher.applyCredits(credits, to: &updated)
                        if updated.summary == nil || updated.summary?.isEmpty == true {
                            updated.summary = ComicVineMatcher.stripHTML(detail.description)
                        }
                    }
                    AppLog.metadata.info("[ComicVine] Issue #\(issueNumber) matched (id \(issue.id)) for volume \(volume.id) — writer:\(updated.writer ?? "–") artist:\(updated.artist ?? "–")")
                } else {
                    AppLog.metadata.info("[ComicVine] No issue #\(issueNumber) found in volume \(volume.id)")
                }
            } catch {
                // Volume data still worth keeping; log and continue
                AppLog.metadata.error("[ComicVine] Issue lookup failed: \(error.localizedDescription)")
            }
        }

        updated.metadataFetchedAt = Date()
        updated.metadataCandidates = nil
        return updated
    }
}

// MARK: - Link / ID parsing

/// A reference parsed out of a pasted ComicVine link or ID.
enum CVReference: Equatable {
    case volume(Int)   // 4050-<id>
    case issue(Int)    // 4000-<id>
}

/// Extracts a ComicVine volume/issue reference from whatever the user pastes:
/// a full URL, the bare "4050-170313" slug, or a plain numeric ID.
///
/// ComicVine encodes a type prefix in the slug — 4050 = volume, 4000 = issue.
/// A bare number is treated as a volume ID (the common case for this override).
enum CVLinkParser {
    static func parse(_ raw: String) -> CVReference? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Look for a "<4-digit-prefix>-<id>" token anywhere in the string.
        if let range = trimmed.range(of: #"\d{4}-\d+"#, options: .regularExpression) {
            let parts = trimmed[range].split(separator: "-")
            if parts.count == 2, let prefix = Int(parts[0]), let id = Int(parts[1]) {
                switch prefix {
                case 4050: return .volume(id)
                case 4000: return .issue(id)
                default:   return nil   // some other resource type — not matchable here
                }
            }
        }

        // Bare numeric input → assume a volume ID.
        if let id = Int(trimmed) { return .volume(id) }
        return nil
    }
}

// MARK: - Matching helpers

enum ComicVineMatcher {

    /// 0…1ish similarity score between a search result and the book.
    ///
    /// Among volumes that share a name (e.g. the many "Iron Man" series), the
    /// name component is a wash, so year is the primary discriminator: a book
    /// tagged "(2026)" almost always belongs to the volume that *started* in
    /// 2026, and a volume that began many years earlier is almost certainly the
    /// wrong one. Year is weighted heavily for that reason.
    static func score(_ volume: CVVolumeResult, against comic: Comic, query: String) -> Double {
        var score = nameSimilarity(volume.name ?? "", query)

        score += yearScore(
            comicYear: comic.year,
            volumeYear: volume.startYear.flatMap { Int($0) }
        )

        if let comicPublisher = comic.publisher?.lowercased(),
           let volumePublisher = volume.publisher?.name?.lowercased(),
           !comicPublisher.isEmpty {
            if comicPublisher == volumePublisher { score += 0.15 }
            else if volumePublisher.contains(comicPublisher) || comicPublisher.contains(volumePublisher) {
                score += 0.08
            }
        }

        return score
    }

    /// Strong, graduated year agreement. Returns 0 when either year is unknown
    /// so books without a year fall back to name/publisher matching unchanged.
    /// An exact match outweighs a publisher match; a gap of many years applies a
    /// penalty large enough to sink an otherwise same-name, same-publisher hit.
    static func yearScore(comicYear: Int?, volumeYear: Int?) -> Double {
        guard let comicYear, let volumeYear else { return 0 }
        switch abs(comicYear - volumeYear) {
        case 0:      return  0.35
        case 1:      return  0.15
        case 2...3:  return  0.05
        case 4...10: return -0.15
        default:     return -0.35   // >10 years apart — different volume
        }
    }

    static func nameSimilarity(_ a: String, _ b: String) -> Double {
        let na = normalize(a), nb = normalize(b)
        if na == nb { return 0.7 }
        if na.contains(nb) || nb.contains(na) { return 0.5 }
        let ta = Set(na.split(separator: " ")), tb = Set(nb.split(separator: " "))
        guard !ta.isEmpty && !tb.isEmpty else { return 0 }
        let overlap = Double(ta.intersection(tb).count)
        return 0.6 * overlap / Double(max(ta.count, tb.count))
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "the ", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }

    /// "007" → "7"; non-numeric issue numbers pass through unchanged.
    static func normalizedIssueNumber(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let n = Int(raw) { return String(n) }
        return raw
    }

    /// ComicVine descriptions are HTML — reduce to plain text.
    static func stripHTML(_ html: String?) -> String? {
        guard var text = html, !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Fill creator fields that are currently empty.
    static func applyCredits(_ credits: [CVPersonCredit], to comic: inout Comic) {
        func names(for role: String) -> String? {
            let matches = credits
                .filter { ($0.role ?? "").lowercased().contains(role) }
                .compactMap { $0.name }
            return matches.isEmpty ? nil : matches.joined(separator: ", ")
        }
        if comic.writer?.isEmpty != false { comic.writer = names(for: "writer") }
        if comic.artist?.isEmpty != false {
            comic.artist = names(for: "penciler") ?? names(for: "artist")
        }
        if comic.coverArtist?.isEmpty != false { comic.coverArtist = names(for: "cover") }
        if comic.colorist?.isEmpty != false { comic.colorist = names(for: "colorist") }
        if comic.inker?.isEmpty != false { comic.inker = names(for: "inker") }
        if comic.editor?.isEmpty != false { comic.editor = names(for: "editor") }
    }
}

// MARK: - Match Picker Sheet

/// Lets the user resolve an ambiguous ComicVine search — shown right after a
/// fetch, or any time later via the cell context menu. Picking a candidate
/// costs at most 2 API calls (issue + credits); the list itself is free
/// (stored from the original search).
struct ComicVineMatchPicker: View {
    let comic: Comic
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isApplying = false
    @State private var linkText = ""
    @State private var linkError: String?
    /// Which candidate is highlighted but not yet confirmed (two-step select).
    @State private var selectedCandidateID: CVCandidate.ID?

    /// When on, a single tap confirms a match immediately. When off (default),
    /// the first tap highlights the row and a second tap on it confirms.
    @AppStorage("singleTapConfirmMatch") private var singleTapConfirm = false

    private var candidates: [CVCandidate] {
        CVCandidate.decodeList(comic.metadataCandidates)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose the Right Match")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    Text(comic.displayTitle)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Spacing.lg)

            Divider()

            if candidates.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(TextColors.tertiary)
                    Text("No pending matches for this book.")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Tells the user how confirming works (hidden when single-tap is on).
                if !singleTapConfirm {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 12))
                        Text(selectionHint)
                            .font(Typography.caption)
                    }
                    .foregroundColor(TextColors.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
                }

                List {
                    ForEach(candidates) { candidate in
                        let isSelected = selectedCandidateID == candidate.id
                        Button {
                            handleTap(candidate)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.name)
                                        .font(Typography.body)
                                        .foregroundColor(TextColors.primary)
                                    Text(candidateSubtitle(candidate))
                                        .font(Typography.caption)
                                        .foregroundColor(TextColors.secondary)
                                }
                                Spacer(minLength: 0)
                                // Checkmark appears on the highlighted (pending) row.
                                if isSelected && !singleTapConfirm {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(AccentColors.primary)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isApplying)
                        .listRowBackground(
                            isSelected && !singleTapConfirm
                                ? AccentColors.primary.opacity(0.15)
                                : Color.clear
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: selectedCandidateID)
                #if os(macOS)
                .listStyle(.inset)
                #else
                .listStyle(.insetGrouped)
                #endif
            }

            Divider()

            linkSection

            Divider()

            HStack {
                Button("None of These") {
                    viewModel.clearComicVineCandidates(for: comic)
                    dismiss()
                }
                .foregroundColor(AccentColors.error)
                Spacer()
                if isApplying {
                    ProgressView().scaleEffect(0.7)
                    Text("Fetching details…")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(minWidth: 420, minHeight: 380)
    }

    /// Manual override: paste a ComicVine volume/issue link (or ID) to match a
    /// series that search ranking didn't surface.
    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("None match? Paste a ComicVine link")
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
            HStack(spacing: Spacing.sm) {
                TextField("comicvine.gamespot.com/…/4050-170313/", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.caption)
                    .disabled(isApplying)
                    .onSubmit { applyLink() }
                Button("Use Link", action: applyLink)
                    .disabled(isApplying || linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let linkError {
                Text(linkError)
                    .font(Typography.caption)
                    .foregroundColor(AccentColors.error)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private func candidateSubtitle(_ candidate: CVCandidate) -> String {
        var parts: [String] = []
        if let year = candidate.startYear { parts.append(String(year)) }
        if let publisher = candidate.publisher { parts.append(publisher) }
        if let count = candidate.issueCount { parts.append("\(count) issues") }
        return parts.isEmpty ? "ComicVine volume #\(candidate.id)" : parts.joined(separator: " • ")
    }

    /// Contextual instruction shown above the list in two-step mode.
    private var selectionHint: String {
        if let id = selectedCandidateID,
           let selected = candidates.first(where: { $0.id == id }) {
            return "Tap “\(selected.name)” again to confirm, or pick another."
        }
        return "Tap to select a match, then tap again to confirm."
    }

    /// Two-step (default) vs single-tap confirm, per the user's setting.
    private func handleTap(_ candidate: CVCandidate) {
        guard !isApplying else { return }
        if singleTapConfirm || selectedCandidateID == candidate.id {
            apply(candidate)
        } else {
            selectedCandidateID = candidate.id
        }
    }

    private func apply(_ candidate: CVCandidate) {
        guard !isApplying else { return }
        isApplying = true
        Task {
            _ = await viewModel.applyComicVineCandidate(candidate, to: comic)
            isApplying = false
            dismiss()
        }
    }

    private func applyLink() {
        let raw = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isApplying, !raw.isEmpty else { return }
        linkError = nil
        isApplying = true
        Task {
            let outcome = await viewModel.applyComicVineLink(raw, to: comic)
            isApplying = false
            switch outcome {
            case .updated:
                dismiss()
            case .failed(let message):
                linkError = message
            case .noKey:
                linkError = "Add a ComicVine API key in Settings first."
            default:
                dismiss()
            }
        }
    }
}

// MARK: - Batch Match Review Sheet

/// Steps through every book that needs a match decision after a batch fetch,
/// one at a time, so the user can confirm or change each match before anything
/// extra is written. Confident matches that were auto-applied never appear here;
/// when "Auto-Apply Confident Matches" is off, every book is routed through.
struct ComicVineBatchReviewView: View {
    /// IDs of the books queued for review, in fetch order.
    let comicIDs: [Comic.ID]
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var isApplying = false
    /// Highlighted-but-unconfirmed candidate for the current book (two-step select).
    @State private var selectedCandidateID: CVCandidate.ID?

    @AppStorage("singleTapConfirmMatch") private var singleTapConfirm = false

    private var currentComic: Comic? {
        guard index >= 0, index < comicIDs.count else { return nil }
        return viewModel.comics.first(where: { $0.id == comicIDs[index] })
    }

    private var candidates: [CVCandidate] {
        CVCandidate.decodeList(currentComic?.metadataCandidates)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let comic = currentComic {
                lookingForBar(for: comic)
                Divider()

                if candidates.isEmpty {
                    emptyState
                } else {
                    candidateList
                }
            } else {
                emptyState
            }

            Divider()

            footer
        }
        .frame(minWidth: 460, minHeight: 460)
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Matches")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    Text("Book \(min(index + 1, comicIDs.count)) of \(comicIDs.count)")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ProgressView(
                value: Double(min(index, comicIDs.count)),
                total: Double(max(comicIDs.count, 1))
            )
            .tint(AccentColors.primary)
        }
        .padding(Spacing.lg)
    }

    private func lookingForBar(for comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(comic.displayTitle)
                .font(Typography.body)
                .foregroundColor(TextColors.primary)
                .lineLimit(1)
            Text("Looking for: \(lookingForDescription(comic))")
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private var candidateList: some View {
        VStack(spacing: 0) {
            if !singleTapConfirm {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 12))
                    Text(selectionHint)
                        .font(Typography.caption)
                }
                .foregroundColor(TextColors.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
            }

            List {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { offset, candidate in
                    let isSelected = selectedCandidateID == candidate.id
                    Button {
                        handleTap(candidate)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.name)
                                    .font(Typography.body)
                                    .foregroundColor(TextColors.primary)
                                Text(candidateSubtitle(candidate))
                                    .font(Typography.caption)
                                    .foregroundColor(TextColors.secondary)
                            }
                            Spacer()
                            if isSelected && !singleTapConfirm {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(AccentColors.primary)
                                    .transition(.scale.combined(with: .opacity))
                            } else if offset == 0 {
                                Text("Best match")
                                    .font(Typography.caption)
                                    .foregroundColor(AccentColors.success)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)
                    .listRowBackground(
                        isSelected && !singleTapConfirm
                            ? AccentColors.primary.opacity(0.15)
                            : Color.clear
                    )
                }
            }
            .animation(.easeInOut(duration: 0.15), value: selectedCandidateID)
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
        }
    }

    /// Contextual instruction shown above the list in two-step mode.
    private var selectionHint: String {
        if let id = selectedCandidateID,
           let selected = candidates.first(where: { $0.id == id }) {
            return "Tap “\(selected.name)” again to confirm, or pick another."
        }
        return "Tap to select a match, then tap again to confirm."
    }

    /// Two-step (default) vs single-tap confirm, per the user's setting.
    private func handleTap(_ candidate: CVCandidate) {
        guard !isApplying else { return }
        if singleTapConfirm || selectedCandidateID == candidate.id {
            apply(candidate)
        } else {
            selectedCandidateID = candidate.id
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(TextColors.tertiary)
            Text("No candidates for this book.")
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: Spacing.md) {
            Button("None of These") {
                if let comic = currentComic {
                    viewModel.clearComicVineCandidates(for: comic)
                }
                advance()
            }
            .foregroundColor(AccentColors.error)
            .disabled(isApplying || currentComic == nil)

            Spacer()

            if isApplying {
                ProgressView().scaleEffect(0.7)
                Text("Fetching details…")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
            }

            Button("Skip") { advance() }
                .disabled(isApplying)

            if index + 1 >= comicIDs.count {
                Button("Finish") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplying)
            } else {
                Button("Skip All") { dismiss() }
                    .disabled(isApplying)
            }
        }
        .padding(Spacing.lg)
    }

    // MARK: Helpers

    private func lookingForDescription(_ comic: Comic) -> String {
        var parts: [String] = []
        if let series = comic.series, !series.isEmpty { parts.append(series) }
        if let issue = comic.issueNumber, !issue.isEmpty { parts.append("#\(issue)") }
        if let year = comic.year { parts.append("(\(year))") }
        if parts.isEmpty { return (comic.fileName as NSString).deletingPathExtension }
        return parts.joined(separator: " ")
    }

    private func candidateSubtitle(_ candidate: CVCandidate) -> String {
        var parts: [String] = []
        if let year = candidate.startYear { parts.append(String(year)) }
        if let publisher = candidate.publisher { parts.append(publisher) }
        if let count = candidate.issueCount { parts.append("\(count) issues") }
        return parts.isEmpty ? "ComicVine volume #\(candidate.id)" : parts.joined(separator: " • ")
    }

    private func apply(_ candidate: CVCandidate) {
        guard !isApplying, let comic = currentComic else { return }
        isApplying = true
        Task {
            _ = await viewModel.applyComicVineCandidate(candidate, to: comic)
            isApplying = false
            advance()
        }
    }

    /// Move to the next book, or dismiss when the queue is exhausted.
    private func advance() {
        // Clear any pending highlight so it doesn't carry to the next book.
        selectedCandidateID = nil
        if index + 1 < comicIDs.count {
            index += 1
        } else {
            dismiss()
        }
    }
}
