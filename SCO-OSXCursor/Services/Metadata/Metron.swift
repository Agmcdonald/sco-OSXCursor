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

/// Issue LIST row (`issue/?series=<id>&number=<n>`).
struct MTIssueResult: Decodable {
    let id: Int
    let number: String?
    let issueName: String?      // "Superman (2016) #6"
    let coverDate: String?      // "2016-11-01"
    let storeDate: String?

    enum CodingKeys: String, CodingKey {
        case id, number
        case issueName = "issue"
        case coverDate = "cover_date"
        case storeDate = "store_date"
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

    /// Issues of a series, optionally filtered to one issue number. 1 call.
    func issues(seriesID: Int, issueNumber: String?) async throws -> [MTIssueResult] {
        var query = [URLQueryItem(name: "series", value: String(seriesID))]
        if let issueNumber, !issueNumber.isEmpty {
            query.append(URLQueryItem(name: "number", value: issueNumber))
        }
        let page: MTPage<MTIssueResult> = try await request(path: "issue/", query: query)
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
