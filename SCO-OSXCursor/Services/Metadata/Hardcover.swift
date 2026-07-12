//
//  Hardcover.swift
//  SCO-OSXCursor
//
//  Hardcover.app as a third metadata source for EPUB ebooks. Hardcover's
//  community catalog covers indie and digital-first titles that Open
//  Library and Google Books miss (e.g. the Marchenko Logfiles series).
//
//  The API is GraphQL with a personal bearer token (free account —
//  hardcover.app/account/api), rate-limited to 60 requests/minute. One
//  book search returns title, authors, description, ISBNs, and release
//  year, so a Hardcover match never needs a follow-up call. Only queried
//  when the user has added their token in Settings.
//

import Foundation

// MARK: - Configuration

enum HardcoverConfig {
    static let tokenDefaultsKey = "hardcoverAPIToken"

    /// The user's personal API token from hardcover.app/account/api.
    /// Tokens on that page are shown with a "Bearer " prefix; accept both.
    static var token: String {
        (UserDefaults.standard.string(forKey: tokenDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasToken: Bool { !token.isEmpty }

    /// Value for the `authorization` header, normalized to "Bearer …".
    static var authorizationValue: String {
        let raw = token
        return raw.lowercased().hasPrefix("bearer ") ? raw : "Bearer \(raw)"
    }
}

// MARK: - Request throttle

/// Hardcover allows 60 requests/minute — ~1.1s spacing keeps us safely under.
actor HCThrottle {
    static let shared = HCThrottle()
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

// MARK: - Result document

/// One book hit from Hardcover's Typesense-backed search.
struct HCBookDoc {
    let id: String
    let title: String?
    let authorNames: [String]
    let description: String?
    let releaseYear: Int?
    let isbns: [String]

    /// Best ISBN on the record, preferring ISBN-13.
    var isbn: String? {
        let normalized = isbns.compactMap(ISBNUtil.normalize)
        return normalized.first { $0.count == 13 } ?? normalized.first
    }
}

// MARK: - API Client

final class HardcoverService {
    static let shared = HardcoverService()

    private let endpoint = URL(string: "https://api.hardcover.app/v1/graphql")!
    private let userAgent = "SuperComicOrganizer/1.0 (andrewmnj@gmail.com)"

    enum HCError: LocalizedError {
        case noToken
        case badToken
        case quotaExceeded(retryAfter: Date)
        case http(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noToken:
                return "No Hardcover API token configured."
            case .badToken:
                return "Hardcover token invalid or expired — check Settings."
            case .quotaExceeded(let retryAfter):
                let time = retryAfter.formatted(date: .omitted, time: .shortened)
                return "Hardcover rate limit reached. Try again after \(time)."
            case .http(let code):
                return "Hardcover returned HTTP \(code)."
            case .badResponse:
                return "Hardcover returned an unexpected response."
            }
        }
    }

    /// Book search. Hardcover's default book search already covers title,
    /// ISBNs, series, and author names, so ISBN lookups use the same call.
    func searchBooks(query: String) async throws -> [HCBookDoc] {
        guard HardcoverConfig.hasToken else { throw HCError.noToken }

        let graphQL = """
            query SearchBooks($q: String!) {
              search(query: $q, query_type: "Book", per_page: 5, page: 1) {
                results
              }
            }
            """
        let body: [String: Any] = ["query": graphQL, "variables": ["q": query]]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(HardcoverConfig.authorizationValue, forHTTPHeaderField: "authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        await HCThrottle.shared.wait()
        AppLog.metadata.info("[Hardcover] → search \"\(query)\"")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 401: throw HCError.badToken
            case 429: throw HCError.quotaExceeded(retryAfter: Date().addingTimeInterval(120))
            default: throw HCError.http(http.statusCode)
            }
        }

        // search.results is a raw Typesense JSON blob — walk it manually.
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = root["data"] as? [String: Any],
            let search = dataObj["search"] as? [String: Any],
            let results = search["results"] as? [String: Any],
            let hits = results["hits"] as? [[String: Any]]
        else {
            // A token problem can also surface as {"error": …} with HTTP 200.
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                root["error"] != nil
            {
                throw HCError.badToken
            }
            throw HCError.badResponse
        }

        return hits.compactMap { hit -> HCBookDoc? in
            guard let doc = hit["document"] as? [String: Any] else { return nil }
            let id =
                (doc["id"] as? String)
                ?? (doc["id"] as? Int).map(String.init)
                ?? UUID().uuidString
            return HCBookDoc(
                id: id,
                title: doc["title"] as? String,
                authorNames: doc["author_names"] as? [String] ?? [],
                description: doc["description"] as? String,
                releaseYear: doc["release_year"] as? Int,
                isbns: doc["isbns"] as? [String] ?? []
            )
        }
    }

    /// Exact ISBN lookup — ISBNs are a zero-typo search field, so querying
    /// the bare ISBN returns the edition's book; verify before trusting.
    func lookupByISBN(_ isbn: String) async throws -> HCBookDoc? {
        let docs = try await searchBooks(query: isbn)
        return docs.first { doc in
            doc.isbns.compactMap(ISBNUtil.normalize).contains(isbn)
        }
    }

    /// Fuzzy title (+ optional author) search. Typesense searches title and
    /// author_names together, so the terms just get combined.
    func search(title: String, author: String?) async throws -> [HCBookDoc] {
        var query = title
        if let author, !author.isEmpty { query += " \(author)" }
        return try await searchBooks(query: query)
    }
}
