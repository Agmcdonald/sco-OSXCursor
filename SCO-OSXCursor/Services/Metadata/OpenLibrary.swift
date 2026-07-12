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
import SwiftUI

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

enum BookSearchTitle {
    /// Filename-derived titles carry junk that poisons title search —
    /// "The Sixth Faction{Veronica Roth}{115848639} libgen.li.epub" or
    /// "The Dead Planet … (Brandon Q. Morris) (z-library.sk, 1lib.sk)".
    /// Strip file extensions, every (…)/[…]/{…} group, pirate-site domain
    /// tokens, and collapse the leftovers.
    static func clean(_ raw: String) -> String {
        var s = raw
        // File extensions anywhere in the string (".epub.epub" happens)
        s = s.replacingOccurrences(
            of: #"(?i)\.(epub|cbz|cbr|pdf|mobi|azw3?)\b"#, with: "",
            options: .regularExpression)
        // Parenthetical / bracketed / curly groups
        s = s.replacingOccurrences(
            of: #"\s*[\(\[\{][^\)\]\}]*[\)\]\}]"#, with: "",
            options: .regularExpression)
        // Domain-ish tokens (libgen.li, z-lib.sk, 1lib.sk, annas-archive.org…)
        s = s.replacingOccurrences(
            of: #"(?i)\b[\w\-]+\.(?:li|sk|is|rs|se|org|com|net|info|io|cc)\b"#, with: "",
            options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n-–—_.,"))
        // If stripping ate everything, keep the raw input.
        return s.isEmpty ? raw : s
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

struct OLSearchResponse: Decodable { let docs: [OLSearchDoc] }

/// A work-level search hit. `title` is Open Library's canonical work title
/// ("Frankenstein or The Modern Prometheus"), which is what we apply —
/// much cleaner than filename-derived titles.
struct OLSearchDoc: Decodable {
    let key: String?  // e.g. "/works/OL450063W"
    let title: String?
    let author_name: [String]?
    let first_publish_year: Int?
    let isbn: [String]?
    let publisher: [String]?
}

/// Work record — fetched for the description (search results don't carry one).
struct OLWork: Decodable {
    let title: String?
    let description: String?

    private enum CodingKeys: String, CodingKey { case title, description }
    private struct TypedText: Decodable { let value: String? }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try? container.decode(String.self, forKey: .title)
        // description is either a bare string or {"type": …, "value": …}
        if let plain = try? container.decode(String.self, forKey: .description) {
            description = plain
        } else if let typed = try? container.decode(TypedText.self, forKey: .description) {
            description = typed.value
        } else {
            description = nil
        }
    }
}

// MARK: - Match candidates (suggestions picker)

/// A stored Open Library suggestion, offered when no match clears the
/// confidence bar — same pattern as ComicVine's CVCandidate. Persisted as
/// JSON in `metadataCandidates` (EPUBs never show the ComicVine picker, so
/// the field is unambiguous per file type).
struct OLCandidate: Codable, Identifiable {
    let id: String  // OL work key ("/works/OL450063W") or "gb:…" for Google Books
    let title: String
    let authors: String?
    let year: Int?
    let publisher: String?
    let isbn: String?
    /// "googleBooks" for Google Books hits; nil/anything else = Open Library.
    var source: String?
    /// Google Books search results carry the description inline, so applying
    /// one of those candidates needs no follow-up network call.
    var summary: String?

    var isGoogleBooks: Bool { source == "googleBooks" }
    var sourceLabel: String { isGoogleBooks ? "Google Books" : "Open Library" }

    static func encodeList(_ list: [OLCandidate]) -> String? {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decodeList(_ json: String?) -> [OLCandidate] {
        guard let json = json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([OLCandidate].self, from: data)) ?? []
    }
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

    private static let searchFields = "key,title,author_name,first_publish_year,isbn,publisher"

    /// Exact ISBN lookup, resolved at the WORK level so the title comes back
    /// canonical and the work key is available for the description fetch.
    func lookupByISBN(_ isbn: String) async throws -> OLSearchDoc? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "isbn:\(isbn)"),
            URLQueryItem(name: "fields", value: Self.searchFields),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components.url else { throw OLError.badURL }
        let data = try await requestData(url)
        return try JSONDecoder().decode(OLSearchResponse.self, from: data).docs.first
    }

    /// Fuzzy title (+ optional author) search. Returns the top candidates.
    func search(title: String, author: String?) async throws -> [OLSearchDoc] {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "fields", value: Self.searchFields),
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

    /// Work record fetch — carries the description/summary that search
    /// results omit. `key` is a work key like "/works/OL450063W".
    func work(key: String) async throws -> OLWork {
        guard key.hasPrefix("/works/"),
            let url = URL(string: "https://openlibrary.org\(key).json")
        else { throw OLError.badURL }
        let data = try await requestData(url)
        return try JSONDecoder().decode(OLWork.self, from: data)
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
    case needsChoice
    case alreadyFetched
    case noMatches
    case notEbook
    case quotaDeferred(Date)
    case failed(String)
}

extension LibraryViewModel {

    /// Fuzzy-match confidence a search hit must clear to be auto-applied.
    private static let openLibraryConfidenceThreshold = 0.7

    /// One scored hit from either book source, in a shape the shared
    /// ranking/candidate code can handle.
    private enum BookHit {
        case openLibrary(OLSearchDoc, score: Double)
        case googleBooks(GBVolumeInfo, score: Double)

        var score: Double {
            switch self {
            case .openLibrary(_, let s), .googleBooks(_, let s): return s
            }
        }
    }

    /// Fetch book metadata for one EPUB — Open Library first, Google Books
    /// as the automatic fallback (its coverage of self-published and
    /// digital-first titles is much stronger).
    /// - ISBN first (read from the book's OPF metadata): exact match.
    /// - Fallback: fuzzy title/author search against BOTH sources, ranked
    ///   together; suggestions from both pool into the match picker.
    /// - Fields fill only when empty (user edits are never clobbered); the
    ///   canonical title replaces; the pre-fetch snapshot is stored for undo.
    @MainActor
    func fetchOpenLibraryMetadata(for comic: Comic, force: Bool) async -> OpenLibraryFetchOutcome {
        guard comic.fileType == .epub else { return .notEbook }
        if !force, comic.metadataFetchedAt != nil { return .alreadyFetched }
        if !force, !OLCandidate.decodeList(comic.metadataCandidates).isEmpty {
            return .needsChoice
        }

        // Identity from the file's own OPF metadata — best available signal.
        let embedded = embeddedEPUBMetadata(for: comic)
        let isbn = comic.isbn ?? embedded?.isbn

        // When a source is over budget we note the earliest retry time and
        // keep going with the other source; only if NOTHING produced a result
        // does the fetch report the deferral.
        var deferredUntil: Date?
        func noteDeferral(_ date: Date) {
            deferredUntil = min(deferredUntil ?? date, date)
        }

        // 1. ISBN path (exact) — Open Library, then Google Books.
        if let isbn {
            do {
                if let doc = try await OpenLibraryService.shared.lookupByISBN(isbn) {
                    await apply(doc: doc, isbn: isbn, to: comic)
                    return .updated
                }
            } catch OpenLibraryService.OLError.quotaExceeded(let retryAfter) {
                noteDeferral(retryAfter)
            } catch {
                AppLog.metadata.error("[OpenLibrary] ISBN lookup failed: \(error.localizedDescription)")
            }
            do {
                if let info = try await GoogleBooksService.shared.lookupByISBN(isbn) {
                    apply(volume: info, isbn: isbn, to: comic)
                    return .updated
                }
            } catch GoogleBooksService.GBError.quotaExceeded(let retryAfter) {
                noteDeferral(retryAfter)
            } catch {
                AppLog.metadata.error("[GoogleBooks] ISBN lookup failed: \(error.localizedDescription)")
            }
        }

        // 2. Fuzzy fallback by title (+ author when known), both sources.
        // Clean filename junk (extensions, {…}(…)[…] groups, domains) first.
        let title = BookSearchTitle.clean(
            embedded?.title ?? comic.title ?? comic.series
                ?? (comic.fileName as NSString).deletingPathExtension)
        let author = embedded?.writer ?? comic.writer
        guard !title.isEmpty else { return .noMatches }

        let (hits, searchDeferral) = await searchBookSources(title: title, author: author)
        if let searchDeferral { noteDeferral(searchDeferral) }
        let ranked = hits.sorted { $0.score > $1.score }

        guard let best = ranked.first else {
            if let deferredUntil { return .quotaDeferred(deferredUntil) }
            return .noMatches
        }

        if best.score >= Self.openLibraryConfidenceThreshold {
            switch best {
            case .openLibrary(let doc, _):
                await apply(doc: doc, isbn: nil, to: comic)
            case .googleBooks(let info, _):
                apply(volume: info, isbn: nil, to: comic)
            }
            return .updated
        }

        // Not confident enough to auto-apply — store the top hits from both
        // sources as suggestions for the user (zero extra API cost).
        let candidates = ranked.prefix(5).compactMap(candidate(from:))
        guard !candidates.isEmpty else {
            if let deferredUntil { return .quotaDeferred(deferredUntil) }
            return .noMatches
        }
        var updated = comics.first(where: { $0.id == comic.id }) ?? comic
        updated.metadataCandidates = OLCandidate.encodeList(Array(candidates))
        updated.dateModified = Date()
        updateComic(updated)
        return .needsChoice
    }

    /// Fuzzy title/author search against Open Library AND Google Books,
    /// scored against the given title. A source that's over budget or errors
    /// is skipped; the earliest retry time (if any) is returned alongside.
    @MainActor
    private func searchBookSources(
        title: String, author: String?
    ) async -> (hits: [BookHit], deferredUntil: Date?) {
        var hits: [BookHit] = []
        var deferredUntil: Date?

        do {
            let docs = try await OpenLibraryService.shared.search(title: title, author: author)
            hits += docs.compactMap { doc -> BookHit? in
                guard let candidate = doc.title else { return nil }
                var score = ComicVineMatcher.nameSimilarity(title, candidate)
                if let author, let names = doc.author_name,
                    names.contains(where: { ComicVineMatcher.nameSimilarity(author, $0) > 0.8 })
                {
                    score = min(1.0, score + 0.1)  // small boost for author agreement
                }
                return .openLibrary(doc, score: score)
            }
        } catch OpenLibraryService.OLError.quotaExceeded(let retryAfter) {
            deferredUntil = retryAfter
        } catch {
            AppLog.metadata.error("[OpenLibrary] Search failed: \(error.localizedDescription)")
        }

        do {
            let volumes = try await GoogleBooksService.shared.search(title: title, author: author)
            hits += volumes.compactMap { info -> BookHit? in
                guard let candidate = info.title else { return nil }
                var score = ComicVineMatcher.nameSimilarity(title, candidate)
                if let author, let names = info.authors,
                    names.contains(where: { ComicVineMatcher.nameSimilarity(author, $0) > 0.8 })
                {
                    score = min(1.0, score + 0.1)
                }
                return .googleBooks(info, score: score)
            }
        } catch GoogleBooksService.GBError.quotaExceeded(let retryAfter) {
            deferredUntil = min(deferredUntil ?? retryAfter, retryAfter)
        } catch {
            AppLog.metadata.error("[GoogleBooks] Search failed: \(error.localizedDescription)")
        }

        return (hits, deferredUntil)
    }

    /// Maps a scored hit to a storable/pickable candidate.
    private func candidate(from hit: BookHit) -> OLCandidate? {
        switch hit {
        case .openLibrary(let doc, _):
            guard let key = doc.key, let title = doc.title else { return nil }
            return OLCandidate(
                id: key,
                title: title,
                authors: doc.author_name?.joined(separator: ", "),
                year: doc.first_publish_year,
                publisher: doc.publisher?.first,
                isbn: doc.isbn?.first.flatMap(ISBNUtil.normalize)
            )
        case .googleBooks(let info, _):
            guard let title = info.title else { return nil }
            return OLCandidate(
                id: "gb:\(info.isbn ?? title)",
                title: title,
                authors: info.authors?.joined(separator: ", "),
                year: info.year,
                publisher: info.publisher,
                isbn: info.isbn,
                source: "googleBooks",
                summary: info.description
            )
        }
    }

    /// Manual search from the match picker: the user types a title (and
    /// optionally an author) and picks from the ranked results of both
    /// sources. Returns up to 8 candidates, best first.
    @MainActor
    func searchBookMatches(title: String, author: String?) async -> [OLCandidate] {
        let cleanTitle = BookSearchTitle.clean(title)
        guard !cleanTitle.isEmpty else { return [] }
        let trimmedAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines)
        let (hits, _) = await searchBookSources(
            title: cleanTitle,
            author: (trimmedAuthor?.isEmpty == false) ? trimmedAuthor : nil)
        return hits.sorted { $0.score > $1.score }
            .prefix(8)
            .compactMap(candidate(from:))
    }

    /// User picked a suggestion from the match sheet (either source).
    @MainActor
    func applyOpenLibraryCandidate(_ candidate: OLCandidate, to comic: Comic) async -> OpenLibraryFetchOutcome {
        if candidate.isGoogleBooks {
            // Google Books candidates carry everything inline — no network.
            let info = GBVolumeInfo(
                title: candidate.title,
                subtitle: nil,
                authors: candidate.authors.map { [$0] },
                publisher: candidate.publisher,
                publishedDate: candidate.year.map(String.init),
                description: candidate.summary,
                industryIdentifiers: nil
            )
            apply(volume: info, isbn: candidate.isbn, to: comic)
            return .updated
        }
        let doc = OLSearchDoc(
            key: candidate.id,
            title: candidate.title,
            author_name: candidate.authors.map { [$0] },
            first_publish_year: candidate.year,
            isbn: candidate.isbn.map { [$0] },
            publisher: candidate.publisher.map { [$0] }
        )
        await apply(doc: doc, isbn: nil, to: comic)
        return .updated
    }

    /// User rejected all Open Library suggestions — clear them.
    @MainActor
    func clearOpenLibraryCandidates(for comic: Comic) {
        var updated = comics.first(where: { $0.id == comic.id }) ?? comic
        updated.metadataCandidates = nil
        updated.dateModified = Date()
        updateComic(updated)
    }

    // MARK: Batch (defer-over-drop)

    struct OpenLibraryBatchResult {
        var updated = 0
        var needChoice = 0
        var noMatch = 0
        var skipped = 0
        var failed = 0
        var deferredRuns = 0

        var summary: String {
            var parts: [String] = []
            if updated > 0 { parts.append("\(updated) updated") }
            if needChoice > 0 { parts.append("\(needChoice) to review") }
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
            case .needsChoice: result.needChoice += 1
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

    /// Applies a matched work to the book. The Open Library work title is
    /// canonical, so it REPLACES the (usually filename-derived) title — the
    /// pre-fetch snapshot still makes this fully undoable. Everything else
    /// fills only when empty. A second call fetches the work's description
    /// for the summary (non-fatal when missing or over budget).
    @MainActor
    private func apply(doc: OLSearchDoc, isbn: String?, to comic: Comic) async {
        // Summary lives on the work record, not in search results.
        var workDescription: String?
        if (comic.summary ?? "").isEmpty, let key = doc.key {
            workDescription = (try? await OpenLibraryService.shared.work(key: key))?.description
        }

        var updated = snapshotted(comic)
        if let title = doc.title, !title.isEmpty {
            updated.title = title  // canonical work title replaces filename junk
        }
        fillIfEmpty(&updated.writer, with: doc.author_name?.joined(separator: ", "))
        fillIfEmpty(&updated.publisher, with: doc.publisher?.first)
        fillIfEmpty(&updated.summary, with: workDescription)
        if updated.year == nil { updated.year = doc.first_publish_year }
        if let isbn {
            updated.isbn = isbn
        } else if updated.isbn == nil {
            updated.isbn = doc.isbn?.first.flatMap(ISBNUtil.normalize)
        }
        updated.metadataCandidates = nil  // a pick/apply resolves any pending choice
        finalize(&updated)
    }

    /// Applies a Google Books volume. Same rules as an Open Library match:
    /// canonical title replaces, everything else fills only when empty, and
    /// the description arrives inline (no follow-up call).
    @MainActor
    private func apply(volume info: GBVolumeInfo, isbn: String?, to comic: Comic) {
        var updated = snapshotted(comic)
        if let title = info.title, !title.isEmpty {
            updated.title = title
        }
        fillIfEmpty(&updated.writer, with: info.authors?.joined(separator: ", "))
        fillIfEmpty(&updated.publisher, with: info.publisher)
        fillIfEmpty(&updated.summary, with: info.description)
        if updated.year == nil { updated.year = info.year }
        if let isbn {
            updated.isbn = isbn
        } else if updated.isbn == nil {
            updated.isbn = info.isbn
        }
        updated.metadataCandidates = nil
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

    /// Apply a match from a pasted link or ID. Accepts, in order:
    /// - an Open Library work link or bare ID ("OL450063W")
    /// - an Amazon product link — the /dp/ ASIN of a PRINT edition is its
    ///   ISBN-10, which we look up on both sources (Kindle "B0…" ASINs
    ///   carry no ISBN and are rejected with an explanation)
    /// - a bare ISBN-10/13, with or without hyphens
    @MainActor
    func applyOpenLibraryLink(_ raw: String, to comic: Comic) async -> OpenLibraryFetchOutcome {
        // 1. Open Library work link / ID
        if let range = raw.range(of: #"OL\d+W"#, options: .regularExpression) {
            let key = "/works/\(raw[range])"
            do {
                let work = try await OpenLibraryService.shared.work(key: key)
                let doc = OLSearchDoc(
                    key: key,
                    title: work.title,
                    author_name: nil,
                    first_publish_year: nil,
                    isbn: nil,
                    publisher: nil
                )
                await apply(doc: doc, isbn: nil, to: comic)
                return .updated
            } catch OpenLibraryService.OLError.quotaExceeded(let retryAfter) {
                return .quotaDeferred(retryAfter)
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        // 2. Amazon product link → ASIN. Print-edition ASINs ARE ISBN-10s.
        if raw.range(of: #"(?i)amazon\.|amzn\."#, options: .regularExpression) != nil {
            guard
                let asinRange = raw.range(
                    of: #"(?i)(?<=/dp/|/gp/product/|/gp/aw/d/)[A-Z0-9]{10}"#,
                    options: .regularExpression)
            else {
                return .failed("Couldn't find a product ID in that Amazon link.")
            }
            let asin = String(raw[asinRange]).uppercased()
            // Amazon assigns "B…" ASINs to Kindle AND print-on-demand
            // editions; neither is an ISBN. Older/traditional print listings
            // use the ISBN-10 as the ASIN, which we can look up directly.
            guard let isbn = ISBNUtil.normalize(asin) else {
                return .failed(
                    "Amazon's ID for this edition (\(asin)) isn't an ISBN. On the Amazon page, check Product details for an ISBN-13 and paste that here instead.")
            }
            return await applyISBNLookup(isbn, to: comic)
        }

        // 3. Bare ISBN (10/13 digits, hyphens/spaces allowed)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^[\d\-\s]{9,17}[\dXx]$"#, options: .regularExpression) != nil,
            let isbn = ISBNUtil.normalize(trimmed)
        {
            return await applyISBNLookup(isbn, to: comic)
        }

        return .failed(
            "Paste an Open Library work link (OL…W), an Amazon book link, or an ISBN.")
    }

    /// Exact-ISBN lookup against both sources, applying the first hit.
    @MainActor
    private func applyISBNLookup(_ isbn: String, to comic: Comic) async -> OpenLibraryFetchOutcome {
        var deferredUntil: Date?
        do {
            if let doc = try await OpenLibraryService.shared.lookupByISBN(isbn) {
                await apply(doc: doc, isbn: isbn, to: comic)
                return .updated
            }
        } catch OpenLibraryService.OLError.quotaExceeded(let retryAfter) {
            deferredUntil = retryAfter
        } catch {
            AppLog.metadata.error("[OpenLibrary] ISBN link lookup failed: \(error.localizedDescription)")
        }
        do {
            if let info = try await GoogleBooksService.shared.lookupByISBN(isbn) {
                apply(volume: info, isbn: isbn, to: comic)
                return .updated
            }
        } catch GoogleBooksService.GBError.quotaExceeded(let retryAfter) {
            deferredUntil = min(deferredUntil ?? retryAfter, retryAfter)
        } catch {
            AppLog.metadata.error("[GoogleBooks] ISBN link lookup failed: \(error.localizedDescription)")
        }
        if let deferredUntil { return .quotaDeferred(deferredUntil) }
        return .failed(
            "No book found for ISBN \(isbn) on Open Library or Google Books. Recently or independently published books often aren't indexed yet — fill in the fields manually and Save.")
    }
}

// MARK: - Match Picker (suggestions sheet)

/// Suggestion sheet for EPUB books whose Open Library search wasn't confident
/// enough to auto-apply — the ebook counterpart of ComicVineMatchPicker.
struct OpenLibraryMatchPicker: View {
    let comic: Comic
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isApplying = false
    @State private var linkText = ""
    @State private var linkError: String?
    /// Which candidate is highlighted but not yet confirmed (two-step select).
    @State private var selectedCandidateID: OLCandidate.ID?

    // Manual search (ComicVine-style helper for books search can't place)
    @State private var searchTitle: String
    @State private var searchAuthor: String
    @State private var isSearching = false
    /// nil until the user runs a search; then it replaces the stored list.
    @State private var searchResults: [OLCandidate]?

    /// Same behaviour setting the ComicVine picker honours.
    @AppStorage("singleTapConfirmMatch") private var singleTapConfirm = false

    init(comic: Comic, viewModel: LibraryViewModel) {
        self.comic = comic
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._searchTitle = State(
            initialValue: BookSearchTitle.clean(
                comic.title ?? (comic.fileName as NSString).deletingPathExtension))
        self._searchAuthor = State(initialValue: comic.writer ?? "")
    }

    private var storedCandidates: [OLCandidate] {
        OLCandidate.decodeList(comic.metadataCandidates)
    }

    /// What the list shows: manual search results once a search has run,
    /// otherwise whatever the last fetch stored.
    private var candidates: [OLCandidate] {
        searchResults ?? storedCandidates
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

            searchSection

            Divider()

            if candidates.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: isSearching ? "hourglass" : "questionmark.circle")
                        .font(.system(size: 40))
                        .foregroundColor(TextColors.tertiary)
                    Text(
                        isSearching
                            ? "Searching Open Library and Google Books…"
                            : (searchResults != nil
                                ? "No results — try fewer words, or just the title."
                                : "No pending matches — search for the book above.")
                    )
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                                    Text(candidate.title)
                                        .font(Typography.body)
                                        .foregroundColor(TextColors.primary)
                                    Text(candidateSubtitle(candidate))
                                        .font(Typography.caption)
                                        .foregroundColor(TextColors.secondary)
                                }
                                Spacer(minLength: 0)
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
                    viewModel.clearOpenLibraryCandidates(for: comic)
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

    /// Manual search: edit the title/author and search both sources.
    /// Prefilled with the book's cleaned title so one click usually works.
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search Open Library and Google Books")
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
            HStack(spacing: Spacing.sm) {
                TextField("Title", text: $searchTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.caption)
                    .disabled(isSearching || isApplying)
                    .onSubmit { runSearch() }
                TextField("Author (optional)", text: $searchAuthor)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.caption)
                    .frame(maxWidth: 180)
                    .disabled(isSearching || isApplying)
                    .onSubmit { runSearch() }
                Button {
                    runSearch()
                } label: {
                    if isSearching {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Text("Search")
                    }
                }
                .disabled(
                    isSearching || isApplying
                        || searchTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private func runSearch() {
        let title = searchTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSearching, !isApplying, !title.isEmpty else { return }
        isSearching = true
        selectedCandidateID = nil
        Task {
            let results = await viewModel.searchBookMatches(title: title, author: searchAuthor)
            searchResults = results
            isSearching = false
        }
    }

    /// Manual override: paste an Open Library work link, an Amazon book
    /// link (print-edition ASINs are ISBN-10s), or a bare ISBN.
    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("None match? Paste an Open Library link, Amazon link, or ISBN")
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
            HStack(spacing: Spacing.sm) {
                TextField("openlibrary.org/works/… · amazon.com/dp/… · 978…", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .font(Typography.caption)
                    .disabled(isApplying)
                    .onSubmit { applyLink() }
                Button("Use Link", action: applyLink)
                    .disabled(
                        isApplying
                            || linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let linkError {
                Text(linkError)
                    .font(Typography.caption)
                    .foregroundColor(AccentColors.error)
                    .fixedSize(horizontal: false, vertical: true)  // wrap, don't truncate
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        // A stale error from the previous attempt is confusing once the
        // user edits the link — clear it as they type.
        .onChange(of: linkText) { _, _ in
            linkError = nil
        }
    }

    private func candidateSubtitle(_ candidate: OLCandidate) -> String {
        var parts: [String] = []
        if let authors = candidate.authors, !authors.isEmpty { parts.append(authors) }
        if let year = candidate.year { parts.append(String(year)) }
        if let publisher = candidate.publisher, !publisher.isEmpty { parts.append(publisher) }
        parts.append(candidate.sourceLabel)
        return parts.joined(separator: " • ")
    }

    private var selectionHint: String {
        if let id = selectedCandidateID,
            let selected = candidates.first(where: { $0.id == id })
        {
            return "Tap “\(selected.title)” again to confirm, or pick another."
        }
        return "Tap to select a match, then tap again to confirm."
    }

    private func handleTap(_ candidate: OLCandidate) {
        guard !isApplying else { return }
        if singleTapConfirm || selectedCandidateID == candidate.id {
            apply(candidate)
        } else {
            selectedCandidateID = candidate.id
        }
    }

    private func apply(_ candidate: OLCandidate) {
        guard !isApplying else { return }
        isApplying = true
        Task {
            _ = await viewModel.applyOpenLibraryCandidate(candidate, to: comic)
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
            let outcome = await viewModel.applyOpenLibraryLink(raw, to: comic)
            isApplying = false
            switch outcome {
            case .updated:
                dismiss()
            case .failed(let message):
                linkError = message
            case .quotaDeferred(let retryAfter):
                let time = retryAfter.formatted(date: .omitted, time: .shortened)
                linkError = "Hourly budget reached — try again after \(time)."
            default:
                dismiss()
            }
        }
    }
}
