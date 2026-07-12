//
//  OpenLibrary.swift
//  SCO-OSXCursor
//
//  Open Library metadata provider for EPUB ebooks. No API key required.
//
//  Flow: ISBN first (exact, high confidence — read from the EPUB's OPF
//  metadata), then a fuzzy title/author search fallback. Every request is
//  throttled to ~1/sec and counted against a self-imposed 200-calls/hour
//  budget (mirroring ComicVine's, tracked separately). When the budget is
//  exhausted, requests are DEFERRED to the next rolling window — never
//  silently dropped. Fetched fields fill only empty slots, the pre-fetch
//  snapshot is stored for undo (same CVMetadataSnapshot the ComicVine flow
//  uses), and CBZ/CBR comics are filtered out before any network call.
//

import Combine
import Foundation

// MARK: - ISBN helpers

enum ISBNUtil {
    /// Strips hyphens/prefixes ("urn:isbn:978-1…" → "9781…"). Returns nil
    /// unless the remainder is a plausible ISBN-10 or ISBN-13.
    static func normalize(_ raw: String) -> String? {
        let cleaned = raw
            .filter { $0.isNumber || $0 == "X" || $0 == "x" }
            .uppercased()
        guard cleaned.count == 10 || cleaned.count == 13 else { return nil }
        // ISBN-10 may end in X; X anywhere else means this wasn't an ISBN.
        if let xIndex = cleaned.firstIndex(of: "X"),
            xIndex != cleaned.index(before: cleaned.endIndex) || cleaned.count == 13
        {
            return nil
        }
        return cleaned
    }
}

// MARK: - Hourly Quota Tracker

/// Rolling-hour call counter for Open Library, persisted like ComicVine's.
/// Open Library publishes no hard cap but asks clients to be gentle; we
/// self-impose the same 200/hour ceiling as ComicVine (independent budget).
@MainActor
final class OpenLibraryQuota: ObservableObject {
    static let shared = OpenLibraryQuota()
    static let hourlyLimit = 200

    @Published private(set) var callTimestamps: [Date] = []

    private let defaultsKey = "openLibraryCallTimestamps"

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

    /// A request was claimed but never reached the server (network failure
    /// before send) — give the slot back so failures don't burn budget.
    func refundLastCall() {
        prune()
        if !callTimestamps.isEmpty {
            callTimestamps.removeLast()
            save()
        }
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

/// Serializes Open Library requests with polite ~1/sec spacing.
actor OLThrottle {
    static let shared = OLThrottle()
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

struct OLBookData: Decodable {
    let title: String?
    let subtitle: String?
    let authors: [OLNamed]?
    let publishers: [OLNamed]?
    let publish_date: String?
    let number_of_pages: Int?
}

struct OLNamed: Decodable { let name: String? }

struct OLSearchResponse: Decodable { let docs: [OLSearchDoc] }

struct OLSearchDoc: Decodable {
    let key: String?
    let title: String?
    let author_name: [String]?
    let first_publish_year: Int?
    let isbn: [String]?
    let publisher: [String]?
}

// MARK: - API Client

final class OpenLibraryService {
    static let shared = OpenLibraryService()

    private let userAgent = "SuperComicOrganizer/1.0 (andrewmnj@gmail.com)"

    enum OLError: LocalizedError {
        case quotaExceeded(retryAfter: Date)
        case badURL
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .quotaExceeded(let retryAfter):
                let time = retryAfter.formatted(date: .omitted, time: .shortened)
                return "Open Library hourly budget reached. Next slot frees at \(time)."
            case .badURL: return "Could not build the request URL."
            case .http(let code): return "Open Library returned HTTP \(code)."
            }
        }
    }

    private func requestData(_ url: URL) async throws -> Data {
        // Claim a budget slot BEFORE the call; defer (throw) when exhausted.
        let decision: Date? = await MainActor.run {
            let quota = OpenLibraryQuota.shared
            if quota.callsInLastHour >= OpenLibraryQuota.hourlyLimit {
                return quota.nextReset ?? Date().addingTimeInterval(3600)
            }
            return nil
        }
        if let retryAfter = decision {
            throw OLError.quotaExceeded(retryAfter: retryAfter)
        }

        await OLThrottle.shared.wait()
        await MainActor.run { OpenLibraryQuota.shared.recordCall() }
        AppLog.metadata.info("[OpenLibrary] → \(url.path)")

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw OLError.http(http.statusCode)
            }
            return data
        } catch let error as OLError {
            throw error
        } catch {
            // Claimed a slot but nothing reached the server — refund it.
            await MainActor.run { OpenLibraryQuota.shared.refundLastCall() }
            throw error
        }
    }

    /// Exact ISBN lookup. One call returns flattened author/publisher names.
    func lookupByISBN(_ isbn: String) async throws -> OLBookData? {
        var components = URLComponents(string: "https://openlibrary.org/api/books")!
        components.queryItems = [
            URLQueryItem(name: "bibkeys", value: "ISBN:\(isbn)"),
            URLQueryItem(name: "jscmd", value: "data"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else { throw OLError.badURL }
        let data = try await requestData(url)
        let decoded = try JSONDecoder().decode([String: OLBookData].self, from: data)
        return decoded["ISBN:\(isbn)"]
    }

    /// Fuzzy title (+ optional author) search. Returns the top candidates.
    func search(title: String, author: String?) async throws -> [OLSearchDoc] {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(
                name: "fields",
                value: "key,title,author_name,first_publish_year,isbn,publisher"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        if let author, !author.isEmpty {
            items.append(URLQueryItem(name: "author", value: author))
        }
        components.queryItems = items
        guard let url = components.url else { throw OLError.badURL }
        let data = try await requestData(url)
        return try JSONDecoder().decode(OLSearchResponse.self, from: data).docs
    }

    /// Pulls a 4-digit year out of strings like "2003", "March 2003", "c1998".
    static func year(from publishDate: String?) -> Int? {
        guard let publishDate else { return nil }
        return publishDate.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .filter { (1400...2100).contains($0) }
            .last
    }
}

// MARK: - Fetch Flow

enum OpenLibraryFetchOutcome {
    case updated
    case alreadyFetched
    case noMatches
    case notEbook
    case quotaDeferred(Date)
    case failed(String)
}

extension LibraryViewModel {

    /// Fuzzy-match confidence a search hit must clear to be auto-applied.
    private static let openLibraryConfidenceThreshold = 0.7

    /// Fetch Open Library metadata for one EPUB.
    /// - ISBN first (read from the book's OPF metadata): exact match.
    /// - Fallback: fuzzy title/author search scored against the book.
    /// - Fields fill only when empty (user edits are never clobbered); the
    ///   pre-fetch snapshot is stored for undo, same as a ComicVine fetch.
    @MainActor
    func fetchOpenLibraryMetadata(for comic: Comic, force: Bool) async -> OpenLibraryFetchOutcome {
        guard comic.fileType == .epub else { return .notEbook }
        if !force, comic.metadataFetchedAt != nil { return .alreadyFetched }

        // Identity from the file's own OPF metadata — best available signal.
        let embedded = embeddedEPUBMetadata(for: comic)
        let isbn = comic.isbn ?? embedded?.isbn

        do {
            // 1. ISBN path (exact).
            if let isbn {
                if let book = try await OpenLibraryService.shared.lookupByISBN(isbn) {
                    apply(book: book, isbn: isbn, to: comic)
                    return .updated
                }
            }

            // 2. Fuzzy fallback by title (+ author when known).
            let title = embedded?.title ?? comic.title ?? comic.series
                ?? (comic.fileName as NSString).deletingPathExtension
            let author = embedded?.writer ?? comic.writer
            guard !title.isEmpty else { return .noMatches }

            let docs = try await OpenLibraryService.shared.search(title: title, author: author)
            let scored = docs.compactMap { doc -> (OLSearchDoc, Double)? in
                guard let candidate = doc.title else { return nil }
                var score = ComicVineMatcher.nameSimilarity(title, candidate)
                if let author, let names = doc.author_name,
                    names.contains(where: { ComicVineMatcher.nameSimilarity(author, $0) > 0.8 })
                {
                    score = min(1.0, score + 0.1)  // small boost for author agreement
                }
                return (doc, score)
            }
            guard let best = scored.max(by: { $0.1 < $1.1 }),
                best.1 >= Self.openLibraryConfidenceThreshold
            else {
                return .noMatches
            }
            apply(doc: best.0, to: comic)
            return .updated
        } catch OpenLibraryService.OLError.quotaExceeded(let retryAfter) {
            return .quotaDeferred(retryAfter)
        } catch {
            AppLog.metadata.error("[OpenLibrary] Fetch failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: Batch (defer-over-drop)

    struct OpenLibraryBatchResult {
        var updated = 0
        var noMatch = 0
        var skipped = 0
        var failed = 0
        var deferredRuns = 0

        var summary: String {
            var parts: [String] = []
            if updated > 0 { parts.append("\(updated) updated") }
            if noMatch > 0 { parts.append("\(noMatch) no match") }
            if skipped > 0 { parts.append("\(skipped) already fetched") }
            if failed > 0 { parts.append("\(failed) failed") }
            return parts.isEmpty
                ? "Nothing to fetch."
                : parts.joined(separator: ", ") + "."
        }
    }

    /// Batch fetch over the EPUBs in a selection. Books the hourly budget
    /// can't cover are DEFERRED to the next rolling window (the task sleeps
    /// and resumes), never dropped — matching the spec's defer-over-drop rule.
    @MainActor
    func fetchOpenLibraryMetadataBatch(
        for comics: [Comic],
        onProgress: @MainActor (String) -> Void = { _ in }
    ) async -> OpenLibraryBatchResult {
        var result = OpenLibraryBatchResult()
        var queue = comics.filter { $0.fileType == .epub }
        let total = queue.count
        var done = 0

        while !queue.isEmpty {
            let comic = queue.removeFirst()
            // Re-read the latest copy in case an earlier book changed the array.
            let latest = self.comics.first(where: { $0.id == comic.id }) ?? comic
            let outcome = await fetchOpenLibraryMetadata(for: latest, force: false)
            switch outcome {
            case .updated: result.updated += 1
            case .noMatches: result.noMatch += 1
            case .alreadyFetched, .notEbook: result.skipped += 1
            case .failed: result.failed += 1
            case .quotaDeferred(let retryAfter):
                // Put the book back and sleep out the window — defer, don't drop.
                queue.insert(comic, at: 0)
                result.deferredRuns += 1
                let time = retryAfter.formatted(date: .omitted, time: .shortened)
                onProgress("Open Library budget reached — \(queue.count) book\(queue.count == 1 ? "" : "s") waiting until \(time)…")
                let wait = max(1, retryAfter.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                continue
            }
            done += 1
            onProgress("Fetching book metadata… \(done) of \(total)")
        }
        return result
    }

    // MARK: Apply + helpers

    /// ISBN hit: exact match, so the title may also fill (when empty).
    @MainActor
    private func apply(book: OLBookData, isbn: String, to comic: Comic) {
        var updated = snapshotted(comic)
        fillIfEmpty(&updated.title, with: book.title)
        fillIfEmpty(&updated.writer, with: book.authors?.compactMap(\.name).joined(separator: ", "))
        fillIfEmpty(&updated.publisher, with: book.publishers?.compactMap(\.name).first)
        if updated.year == nil { updated.year = OpenLibraryService.year(from: book.publish_date) }
        updated.isbn = isbn
        finalize(&updated)
    }

    @MainActor
    private func apply(doc: OLSearchDoc, to comic: Comic) {
        var updated = snapshotted(comic)
        fillIfEmpty(&updated.title, with: doc.title)
        fillIfEmpty(&updated.writer, with: doc.author_name?.joined(separator: ", "))
        fillIfEmpty(&updated.publisher, with: doc.publisher?.first)
        if updated.year == nil { updated.year = doc.first_publish_year }
        if updated.isbn == nil { updated.isbn = doc.isbn?.first.flatMap(ISBNUtil.normalize) }
        finalize(&updated)
    }

    /// Freshest copy of the book with the pre-fetch snapshot stored for undo.
    @MainActor
    private func snapshotted(_ comic: Comic) -> Comic {
        let current = comics.first(where: { $0.id == comic.id }) ?? comic
        var updated = current
        updated.metadataBackup = CVMetadataSnapshot(of: current).encoded()
        return updated
    }

    @MainActor
    private func finalize(_ comic: inout Comic) {
        comic.metadataFetchedAt = Date()
        comic.dateModified = Date()
        updateComic(comic)
    }

    private func fillIfEmpty(_ field: inout String?, with value: String?) {
        guard field == nil || field?.isEmpty == true else { return }
        guard let value, !value.isEmpty else { return }
        field = value
    }

    /// Reads the EPUB's own OPF metadata (title/author/ISBN), resolving the
    /// security-scoped bookmark the same way cover regeneration does.
    /// Also persists a newly discovered ISBN onto the record.
    @MainActor
    private func embeddedEPUBMetadata(for comic: Comic) -> ComicMetadata? {
        var fileURL = comic.filePath
        var didStartAccess = false
        if let bookmarkData = comic.bookmarkData {
            var isStale = false
            #if os(macOS)
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    fileURL = resolved
                    didStartAccess = resolved.startAccessingSecurityScopedResource()
                }
            #else
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    fileURL = resolved
                }
            #endif
        }
        defer { if didStartAccess { fileURL.stopAccessingSecurityScopedResource() } }

        guard let metadata = try? EPUBReader().extractMetadata(from: fileURL) else {
            return nil
        }
        // Remember the ISBN so future fetches skip the file extraction.
        if comic.isbn == nil, let isbn = metadata.isbn {
            var updated = comics.first(where: { $0.id == comic.id }) ?? comic
            updated.isbn = isbn
            updateComic(updated)
        }
        return metadata
    }
}
