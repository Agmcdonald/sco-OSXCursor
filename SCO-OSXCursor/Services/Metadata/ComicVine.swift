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
    func searchVolumes(_ name: String) async throws -> [CVVolumeResult] {
        try await request(
            path: "search/",
            query: [
                URLQueryItem(name: "resources", value: "volume"),
                URLQueryItem(name: "query", value: name),
                URLQueryItem(name: "limit", value: "10"),
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
    @MainActor
    func fetchComicVineMetadata(for comic: Comic, force: Bool) async -> ComicVineFetchOutcome {
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

            if confident {
                return await applyVolume(best.volume, to: comic)
            }

            // Ambiguous — store the top candidates for the user to resolve
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

        var summary: String {
            if noKey { return "Add a ComicVine API key in Settings first." }
            var parts: [String] = []
            if updated > 0 { parts.append("\(updated) updated") }
            if needChoice > 0 { parts.append("\(needChoice) need a match choice") }
            if noMatch > 0 { parts.append("\(noMatch) no match") }
            if skipped > 0 { parts.append("\(skipped) already fetched") }
            if failed > 0 { parts.append("\(failed) failed") }
            return parts.isEmpty ? "Nothing to fetch." : parts.joined(separator: ", ") + "."
        }
    }

    @MainActor
    func fetchComicVineMetadataBatch(for comics: [Comic]) async -> BatchResult {
        var result = BatchResult()
        guard ComicVineConfig.hasKey else {
            result.noKey = true
            return result
        }
        for comic in comics {
            // Re-read the latest copy in case an earlier book in the loop
            // changed the array.
            let latest = self.comics.first(where: { $0.id == comic.id }) ?? comic
            let outcome = await fetchComicVineMetadata(for: latest, force: false)
            switch outcome {
            case .updated: result.updated += 1
            case .needsChoice: result.needChoice += 1
            case .alreadyFetched: result.skipped += 1
            case .noMatches: result.noMatch += 1
            case .failed: result.failed += 1
            case .noKey: result.noKey = true
            }
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
        updated.dateModified = Date()
        updateComic(updated)
        return .updated
    }
}

// MARK: - Matching helpers

enum ComicVineMatcher {

    /// 0…1ish similarity score between a search result and the book.
    static func score(_ volume: CVVolumeResult, against comic: Comic, query: String) -> Double {
        var score = nameSimilarity(volume.name ?? "", query)

        if let comicYear = comic.year,
           let volumeYear = volume.startYear.flatMap({ Int($0) }) {
            let diff = abs(comicYear - volumeYear)
            if diff == 0 { score += 0.2 }
            else if diff <= 2 { score += 0.1 }
            else if diff > 15 { score -= 0.1 }
        }

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
                List {
                    ForEach(candidates) { candidate in
                        Button {
                            apply(candidate)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.name)
                                    .font(Typography.body)
                                    .foregroundColor(TextColors.primary)
                                Text(candidateSubtitle(candidate))
                                    .font(Typography.caption)
                                    .foregroundColor(TextColors.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isApplying)
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #else
                .listStyle(.insetGrouped)
                #endif
            }

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

    private func candidateSubtitle(_ candidate: CVCandidate) -> String {
        var parts: [String] = []
        if let year = candidate.startYear { parts.append(String(year)) }
        if let publisher = candidate.publisher { parts.append(publisher) }
        if let count = candidate.issueCount { parts.append("\(count) issues") }
        return parts.isEmpty ? "ComicVine volume #\(candidate.id)" : parts.joined(separator: " • ")
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
}
