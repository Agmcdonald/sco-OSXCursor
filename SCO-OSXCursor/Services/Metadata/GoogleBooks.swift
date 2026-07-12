//
//  GoogleBooks.swift
//  SCO-OSXCursor
//
//  Google Books as a second metadata source for EPUB ebooks. Open Library's
//  coverage of self-published and digital-first titles is thin; Google Books
//  fills that gap. No API key required for volume search — requests are
//  attributed per-IP with a generous anonymous quota. Everything (title,
//  authors, publisher, date, description, ISBNs) comes back in the ONE
//  search response, so a Google Books match never needs a follow-up call.
//
//  The ebook fetch flow (OpenLibrary.swift) tries Open Library first and
//  falls through to Google Books automatically; suggestion candidates are
//  pooled from both sources.
//

import Combine
import Foundation

// MARK: - Hourly Quota Tracker

/// Rolling-hour call counter for Google Books, persisted like the others.
/// Independent budget with the same self-imposed 200/hour ceiling.
@MainActor
final class GoogleBooksQuota: ObservableObject {
    static let shared = GoogleBooksQuota()
    static let hourlyLimit = 200

    @Published private(set) var callTimestamps: [Date] = []

    private let defaultsKey = "googleBooksCallTimestamps"

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

    /// Refund a slot claimed for a request that never reached the server.
    func refundLastCall() {
        prune()
        if !callTimestamps.isEmpty {
            callTimestamps.removeLast()
            save()
        }
    }

    var callsInLastHour: Int {
        callTimestamps.filter { $0 > Date().addingTimeInterval(-3600) }.count
    }

    var nextReset: Date? {
        callTimestamps
            .filter { $0 > Date().addingTimeInterval(-3600) }
            .min()?
            .addingTimeInterval(3600)
    }

    private func prune() {
        callTimestamps = callTimestamps.suffix(400).filter {
            $0 > Date().addingTimeInterval(-2 * 3600)
        }
    }

    private func save() {
        UserDefaults.standard.set(
            callTimestamps.map { $0.timeIntervalSince1970 }, forKey: defaultsKey)
    }
}

// MARK: - Request throttle

/// Serializes Google Books requests with polite ~1/sec spacing.
actor GBThrottle {
    static let shared = GBThrottle()
    private let minInterval: TimeInterval = 1.0
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

struct GBVolumesResponse: Decodable {
    let totalItems: Int?
    let items: [GBVolume]?
}

struct GBVolume: Decodable {
    let id: String?
    let volumeInfo: GBVolumeInfo?
}

struct GBVolumeInfo: Decodable {
    let title: String?
    let subtitle: String?
    let authors: [String]?
    let publisher: String?
    let publishedDate: String?  // "2021", "2021-03", or "2021-03-05"
    let description: String?
    let industryIdentifiers: [GBIdentifier]?

    /// 4-digit year from the (variously formatted) published date.
    var year: Int? {
        guard let publishedDate, publishedDate.count >= 4 else { return nil }
        return Int(publishedDate.prefix(4))
    }

    /// Best ISBN on the volume, preferring ISBN-13.
    var isbn: String? {
        let ids = industryIdentifiers ?? []
        let preferred = ids.first { $0.type == "ISBN_13" } ?? ids.first { $0.type == "ISBN_10" }
        return preferred?.identifier.flatMap(ISBNUtil.normalize)
    }
}

struct GBIdentifier: Decodable {
    let type: String?
    let identifier: String?
}

// MARK: - API Client

final class GoogleBooksService {
    static let shared = GoogleBooksService()

    private let userAgent = "SuperComicOrganizer/1.0 (andrewmnj@gmail.com)"

    enum GBError: LocalizedError {
        case quotaExceeded(retryAfter: Date)
        case badURL
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .quotaExceeded(let retryAfter):
                let time = retryAfter.formatted(date: .omitted, time: .shortened)
                return "Google Books hourly budget reached. Next slot frees at \(time)."
            case .badURL: return "Could not build the request URL."
            case .http(let code): return "Google Books returned HTTP \(code)."
            }
        }
    }

    private func requestData(_ url: URL) async throws -> Data {
        let deferredUntil: Date? = await MainActor.run {
            let quota = GoogleBooksQuota.shared
            if quota.callsInLastHour >= GoogleBooksQuota.hourlyLimit {
                return quota.nextReset ?? Date().addingTimeInterval(3600)
            }
            return nil
        }
        if let retryAfter = deferredUntil {
            throw GBError.quotaExceeded(retryAfter: retryAfter)
        }

        await GBThrottle.shared.wait()
        await MainActor.run { GoogleBooksQuota.shared.recordCall() }
        AppLog.metadata.info("[GoogleBooks] → \(url.path)")

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // Google's own daily/anonymous limit surfaces as 429 — map it
                // to the same deferred-quota shape so batches reschedule.
                if http.statusCode == 429 {
                    throw GBError.quotaExceeded(retryAfter: Date().addingTimeInterval(3600))
                }
                throw GBError.http(http.statusCode)
            }
            return data
        } catch let error as GBError {
            throw error
        } catch {
            await MainActor.run { GoogleBooksQuota.shared.refundLastCall() }
            throw error
        }
    }

    private func volumes(query: String, limit: Int) async throws -> [GBVolume] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(limit)),
            URLQueryItem(name: "printType", value: "books"),
        ]
        guard let url = components.url else { throw GBError.badURL }
        let data = try await requestData(url)
        return try JSONDecoder().decode(GBVolumesResponse.self, from: data).items ?? []
    }

    /// Exact ISBN lookup. One call returns full volume info incl. description.
    func lookupByISBN(_ isbn: String) async throws -> GBVolumeInfo? {
        try await volumes(query: "isbn:\(isbn)", limit: 1).first?.volumeInfo
    }

    /// Fuzzy title (+ optional author) search.
    func search(title: String, author: String?) async throws -> [GBVolumeInfo] {
        var query = "intitle:\"\(title)\""
        if let author, !author.isEmpty {
            query += " inauthor:\"\(author)\""
        }
        return try await volumes(query: query, limit: 5).compactMap(\.volumeInfo)
    }
}
