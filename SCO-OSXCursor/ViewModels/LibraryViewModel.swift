import Combine
import Foundation
import SwiftUI
import os

#if os(macOS)
    import AppKit
#endif

#if os(iOS)
    import UIKit
#endif

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var comics: [Comic] = []

    // Folders (collections) — a virtual organizational layer.
    @Published var folders: [Folder] = []
    /// folderID → set of comic IDs in that folder.
    @Published var folderMembership: [UUID: Set<UUID>] = [:]

    // ✅ Track which comics are currently being edited
    @Published var editingComicIDs: Set<UUID> = []

    // ✅ Track the comic currently being read to present in full screen
    @Published var readingComic: Comic?

    /// Display-order snapshot of the list the current book was opened from
    /// (library grid/list, folder, search results). Captured by LibraryView in
    /// openReader(); drives the "next issue" suggestion so it follows whatever
    /// sort order the user was browsing in. Nil when opened from elsewhere
    /// (e.g. the Dashboard) — nextComic(after:) then falls back to the whole
    /// library in the current sort order.
    var readingOrderIDs: [UUID]?

    // ✅ Pre-fetched comic data for instant reader launch (iOS only)
    #if os(iOS)
        @Published var prefetchedComicBook: ComicBook?
        private(set) var prefetchedForComicID: UUID?
        private var prefetchTask: Task<Void, Never>?
    #endif

    // Import tracking
    @Published var isImporting: Bool = false
    @Published var importProgress: Double = 0.0

    private let database: DatabaseManager
    private let progressTracker = ReadingProgressTracker.shared
    private var cancellables = Set<AnyCancellable>()

    init(database: DatabaseManager) {
        self.database = database
        // Load comics from database on initialization
        Task {
            await loadComics()
            // Load user folders + membership for the library scope bar
            await loadFolders()
            // Warm the learning system so staging/import matching is instant
            await SeriesKnowledge.shared.loadIfNeeded()
            // If library is empty, automatically import bundled samples
            if comics.isEmpty {
                await importBundledComics()
            }
            // Check for missing files on launch
            await checkMissingFiles()
        }

        // Listen for refreshed security-scoped bookmarks from ReaderViewModel
        // and persist them so subsequent opens don't need to re-create them.
        NotificationCenter.default
            .publisher(for: ReaderViewModel.bookmarkRefreshedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                    let comicID = notification.userInfo?["comicID"] as? UUID,
                    let bookmarkData = notification.userInfo?["bookmarkData"] as? Data
                else { return }

                guard let index = self.comics.firstIndex(where: { $0.id == comicID }) else {
                    return
                }
                var updated = self.comics[index]
                updated.bookmarkData = bookmarkData
                self.comics[index] = updated
                Task {
                    try? await self.database.saveComic(updated)
                    AppLog.library.info("[LibraryViewModel] ✅ Persisted refreshed bookmark for: \(updated.fileName)")
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load Comics

    func loadComics() async {
        do {
            let fetchedComics = try await database.fetchAllComics()
            await MainActor.run {
                self.comics = fetchedComics
                AppLog.library.info("[LibraryViewModel] ✅ Loaded \(fetchedComics.count) comics from database")
            }
            // One-time Knowledge Base repair for books imported before creator
            // sync existed (e.g. ComicVine-enriched imports wrote creators to
            // metadata but not the KB). Guarded internally so it only does work
            // once; runs in the background so it never delays the library load.
            Task { await database.backfillKnowledgeIfNeeded() }
        } catch {
            AppLog.library.error("[LibraryViewModel] ❌ Failed to load comics: \(error)")
        }
    }

    // MARK: - Next Issue Suggestion

    /// The book that comes after `comicID` in the order the user is browsing.
    ///
    /// Preferred source is `readingOrderIDs` — the exact filtered/sorted list
    /// the book was opened from (so folder scope, filters and search are all
    /// respected). Falls back to the whole library sorted by the persisted
    /// library sort option. Returns nil when the book is the last one.
    func nextComic(after comicID: UUID) -> Comic? {
        // 1. Exact display order captured when the book was opened
        if let order = readingOrderIDs, let index = order.firstIndex(of: comicID) {
            for nextID in order.dropFirst(index + 1) {
                // Skip entries deleted since the order was captured
                if let next = comics.first(where: { $0.id == nextID }) {
                    return next
                }
            }
            return nil
        }

        // 2. Fallback: whole library in the current sort order
        let storedSort = UserDefaults.standard.string(forKey: "librarySortOption")
        let sort = storedSort.flatMap(LibrarySortOption.init(rawValue:)) ?? .dateAdded
        let ordered = LibraryQuery.apply(
            to: comics,
            searchText: "",
            filters: LibraryFilters(),
            sort: sort
        )
        guard let index = ordered.firstIndex(where: { $0.id == comicID }),
            index + 1 < ordered.count
        else { return nil }
        return ordered[index + 1]
    }

    // ✅ DB-only persistence (NO array update)
    func persistComic(_ comic: Comic) async throws {
        try await database.updateComic(comic)
        AppLog.library.info("[LibraryViewModel] ✅ Persisted comic to database: \(comic.fileName)")
    }

    // (Optional) Keep ONLY for non-editor callers
    func updateComic(_ comic: Comic) {
        guard let index = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        let old = comics[index]
        comics[index] = comic
        Task {
            try? await persistComic(comic)
            // Log changed fields
            if old.title != comic.title {
                await logActivity(.titleChanged, comic: comic, old: old.title, new: comic.title)
            }
            if old.series != comic.series {
                await logActivity(.seriesChanged, comic: comic, old: old.series, new: comic.series)
            }
            if old.issueNumber != comic.issueNumber {
                await logActivity(
                    .issueChanged, comic: comic, old: old.issueNumber, new: comic.issueNumber)
            }
            if old.publisher != comic.publisher {
                await logActivity(
                    .publisherChanged, comic: comic, old: old.publisher, new: comic.publisher)
            }
            if old.writer != comic.writer {
                await logActivity(.writerChanged, comic: comic, old: old.writer, new: comic.writer)
            }
            if old.artist != comic.artist {
                await logActivity(.artistChanged, comic: comic, old: old.artist, new: comic.artist)
            }
            if old.year != comic.year {
                await logActivity(
                    .yearChanged, comic: comic, old: old.year.map { String($0) },
                    new: comic.year.map { String($0) })
            }
            if old.status != comic.status {
                await logActivity(
                    .statusChanged, comic: comic, old: old.status.rawValue,
                    new: comic.status.rawValue)
            }
            if old.rating != comic.rating {
                await logActivity(
                    .ratingChanged, comic: comic, old: old.rating.map { String($0) },
                    new: comic.rating.map { String($0) })
            }
            if old.isFavorite != comic.isFavorite {
                await logActivity(
                    .favoriteToggled, comic: comic, old: String(old.isFavorite),
                    new: String(comic.isFavorite))
            }
            if old.fileName != comic.fileName {
                await logActivity(.renamed, comic: comic, old: old.fileName, new: comic.fileName)
            }

            // Auto-relocate file if publisher or series changed and a home library is set
            let publisherChanged = old.publisher != comic.publisher
            let seriesChanged    = old.series    != comic.series
            if (publisherChanged || seriesChanged),
               AppSettings.load().autoSortIntoLibrary,
               let libraryRoot = SettingsViewModel().resolveHomeLibraryURL()
            {
                let updated = await LibraryRelocator.shared.handleMetadataChange(
                    old: old,
                    new: comic,
                    libraryRoot: libraryRoot,
                    database: database
                )
                await MainActor.run {
                    if let idx = comics.firstIndex(where: { $0.id == updated.id }) {
                        comics[idx] = updated
                    }
                }
            } else if old.year != comic.year || old.issueNumber != comic.issueNumber
                || old.volume != comic.volume || old.bookFormat != comic.bookFormat
            {
                // Year/issue/volume/format affect the clean FILENAME (and the
                // year-based folder structure) — re-file in-library books
                await resortAfterEdit(comic.id)
            }

            // Drop autocomplete suggestions the correction just orphaned
            if publisherChanged {
                pruneKnowledgeIfOrphaned(type: .publisher, name: old.publisher)
            }
            if seriesChanged {
                pruneKnowledgeIfOrphaned(type: .series, name: old.series)
            }
        }
    }

    // MARK: - Activity Logging

    func logActivity(
        _ action: ActivityEvent.ActionType, comic: Comic? = nil, old: String? = nil,
        new: String? = nil
    ) async {
        let event = ActivityEvent(
            comicId: comic?.id.uuidString,
            action: action,
            oldValue: old,
            newValue: new ?? comic?.displayName
        )
        await database.logActivity(event)
    }

    // MARK: - Reading List

    func toggleReadingList(_ comic: Comic) {
        var updated = comic
        updated.isOnReadingList = !comic.isOnReadingList
        updateComic(updated)
    }

    // MARK: - Missing File Detection

    /// On launch, check every comic's stored path still exists on disk.
    /// Uses the comic's security-scoped bookmark (if present) to gain temporary
    /// sandbox access before checking, avoiding false-positive missing flags on
    /// iCloud/Downloads files that exist but aren't accessible without access start.
    func checkMissingFiles() async {
        // Snapshot what the scan needs, then do all bookmark resolution and
        // disk probing OFF the main actor — this previously blocked the UI
        // at launch for the whole library.
        struct Probe: Sendable {
            let id: UUID
            let bookmarkData: Data?
            let path: String
            let needsAttention: Bool
        }
        let bundlePath = Bundle.main.bundlePath
        let probes: [Probe] = comics
            .filter { !$0.filePath.path.hasPrefix(bundlePath) }
            .map {
                Probe(
                    id: $0.id, bookmarkData: $0.bookmarkData,
                    path: $0.filePath.path, needsAttention: $0.needsAttention)
            }

        // (id, nowMissing) for every comic whose flag should change
        let changes: [(UUID, Bool)] = await Task.detached(priority: .utility) {
            let fm = FileManager.default
            var result: [(UUID, Bool)] = []

            for probe in probes {
                var bookmarkURL: URL? = nil
                if let bookmarkData = probe.bookmarkData {
                    var stale = false
                    #if os(macOS)
                        bookmarkURL = try? URL(
                            resolvingBookmarkData: bookmarkData,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &stale
                        )
                    #else
                        bookmarkURL = try? URL(
                            resolvingBookmarkData: bookmarkData,
                            options: [],
                            relativeTo: nil,
                            bookmarkDataIsStale: &stale
                        )
                    #endif
                }
                let accessing = bookmarkURL?.startAccessingSecurityScopedResource() ?? false

                // Bookmark-resolved URL wins (file may have moved externally)
                let checkPath = bookmarkURL?.path ?? probe.path
                let exists = fm.fileExists(atPath: checkPath)

                if accessing { bookmarkURL?.stopAccessingSecurityScopedResource() }

                if !exists && !probe.needsAttention {
                    result.append((probe.id, true))
                } else if exists && probe.needsAttention {
                    result.append((probe.id, false))
                }
            }
            return result
        }.value

        var flaggedCount = 0
        for (id, missing) in changes {
            guard let index = comics.firstIndex(where: { $0.id == id }) else { continue }
            comics[index].needsAttention = missing
            try? await database.updateComic(comics[index])
            if missing {
                flaggedCount += 1
                AppLog.library.error("[LibraryViewModel] ⚠️ Missing file flagged: \(comics[index].fileName)")
            } else {
                AppLog.library.error("[LibraryViewModel] ✅ Cleared missing flag: \(comics[index].fileName)")
            }
        }

        if flaggedCount > 0 {
            AppLog.library.error("[LibraryViewModel] ⚠️ \(flaggedCount) comics flagged as missing")
        }
    }

    // MARK: - Cover Regeneration

    func regenerateCovers(for comics: [Comic]) {
        Task { @MainActor in
            for comic in comics {
                await regenerateCoverSingle(comic)
            }
        }
    }

    private func regenerateCoverSingle(_ comic: Comic) async {
        // Resolve file URL (honour security-scoped bookmark if present)
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

        let reader: ComicReaderProtocol
        switch comic.fileType {
        case .pdf: reader = PDFReader()
        case .cbr: reader = CBRReader()
        case .epub: reader = EPUBReader()
        default: reader = CBZReader()
        }

        guard let rawCover = try? await reader.extractCover(from: fileURL) else {
            AppLog.library.error("[LibraryViewModel] ⚠️ Cover regeneration failed for \(comic.fileName)")
            return
        }

        // Downsample for storage
        let coverData: Data = await Task.detached(priority: .userInitiated) {
            PageImageCache.storageCoverData(from: rawCover) ?? rawCover
        }.value

        var updated = comic
        updated.coverImageData = coverData
        updateComic(updated)
        AppLog.library.info("[LibraryViewModel] ✅ Cover regenerated for \(comic.fileName)")
    }

    // ✅ Background read + single publish
    func syncProgressFromTracker() {
        Task.detached(priority: .utility) { [progressTracker] in
            let allProgress = progressTracker.loadAllProgress()

            await MainActor.run {
                guard !allProgress.isEmpty else { return }

                var updated = self.comics

                for i in updated.indices {
                    let id = updated[i].id
                    if self.editingComicIDs.contains(id) { continue }

                    if let p = allProgress[id] {
                        updated[i].currentPage = p.currentPage
                        updated[i].status = p.status
                        updated[i].lastReadDate = p.lastReadDate
                    }
                }

                self.comics = updated
                AppLog.library.info("[LibraryViewModel] ✅ Synced progress (batched)")
            }
        }
    }

    // ✅ Same safe pattern
    private func restoreReadingProgress() {
        Task.detached(priority: .utility) { [progressTracker] in
            let allProgress = progressTracker.loadAllProgress()

            await MainActor.run {
                guard !allProgress.isEmpty else { return }

                var updated = self.comics

                for i in updated.indices {
                    let id = updated[i].id
                    if self.editingComicIDs.contains(id) { continue }

                    if let p = allProgress[id] {
                        updated[i].currentPage = p.currentPage
                        updated[i].status = p.status
                        updated[i].lastReadDate = p.lastReadDate
                    }
                }

                self.comics = updated
                AppLog.library.debug("[LibraryViewModel] 📖 Restored progress (batched)")
            }
        }
    }

    // MARK: - Import Comics

    /// Imports the given files/folders and returns the IDs of the books that
    /// were added (used by callers that want to file them into a folder).
    @discardableResult
    func importComics(from rawURLs: [URL]) async -> [UUID] {
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
        }

        // Learned knowledge participates in matching below
        await SeriesKnowledge.shared.loadIfNeeded()

        // Expand folders into their contained comic files (recursive).
        //
        // IMPORTANT (iOS sandbox): security-scoped access must be started
        // BEFORE any file-system call — even fileExists() returns false on an
        // unscoped picker URL. Folder scopes stay open until the import loop
        // finishes so child files remain readable.
        var scopedFolders: [URL] = []
        for url in rawURLs {
            let accessing = url.startAccessingSecurityScopedResource()
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path, isDirectory: &isDirectory)
            if accessing && exists && isDirectory.boolValue {
                scopedFolders.append(url)  // keep scope open for enumeration + import
            } else if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        defer {
            for folder in scopedFolders {
                folder.stopAccessingSecurityScopedResource()
            }
        }

        // (Synchronous helper — DirectoryEnumerator iteration is unavailable
        // in async contexts under Swift 6.)
        let urls: [URL] = await Task.detached(priority: .userInitiated) {
            OrganizeViewModel.expandComicFileURLs(
                rawURLs, validExtensions: ["cbz", "cbr", "pdf", "epub"])
        }.value

        let total = urls.count
        var imported = 0
        var newComics: [Comic] = []

        // Home-library auto-sort: Quick Add files books into the canonical
        // hierarchy just like Organize does. Books without a publisher land
        // in "Unknown Publisher/<Series>/" awaiting user correction (editing
        // the publisher later re-files them via resortAfterEdit).
        let libraryRoot: URL? =
            AppSettings.load().autoSortIntoLibrary
            ? SettingsViewModel().resolveHomeLibraryURL()
            : nil

        for (index, url) in urls.enumerated() {
            do {
                // Start accessing security-scoped resource
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                // Get file info
                let fileName = url.lastPathComponent
                let fileExtension = url.pathExtension.lowercased()

                guard let fileType = Comic.FileType(rawValue: fileExtension) else {
                    AppLog.library.error("[LibraryViewModel] ⚠️ Skipping unsupported file: \(fileName)")
                    continue
                }

                // Create bookmark for persistent access
                #if os(macOS)
                    let bookmarkData = try? url.bookmarkData(
                        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                #else
                    // .minimalBookmark creates a resolvable bookmark on iOS/iPadOS.
                    // Empty options [] produce a non-resolvable bookmark — do NOT use [].
                    let bookmarkData = try? url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                #endif

                // Generate stable ID
                // For bundled comics, use filename (path changes on iOS).
                // For user comics, use standardized path.
                let isBundled = url.path.contains(Bundle.main.bundlePath)
                let stablePath = isBundled ? url.lastPathComponent : url.standardizedFileURL.path
                let pathData = stablePath.data(using: .utf8) ?? Data()

                let pathHash = pathData.withUnsafeBytes { bytes in
                    var hash: UInt64 = 5381
                    let buffer = UnsafeRawBufferPointer(bytes)
                    for byte in buffer {
                        hash = ((hash << 5) &+ hash) &+ UInt64(byte)
                    }
                    return hash
                }

                // Convert hash to UUID (using first 16 bytes of hash repeated)
                let hashBytes = withUnsafeBytes(of: pathHash) { Data($0) }
                let uuidBytes = Data((0..<16).map { hashBytes[$0 % hashBytes.count] })
                let comicID = UUID(uuid: uuidBytes.withUnsafeBytes { $0.load(as: uuid_t.self) })

                // Check if comic already exists
                let existingComic = try? await database.fetchComic(id: comicID)
                let finalID = existingComic?.id ?? comicID

                // Parse metadata from filename
                let filenameMetadata = MetadataParser.parseFromFilename(fileName)

                // Enrich from learned series knowledge + folder-name hints
                // (quick add bypasses Organize, so the learning system fills
                // gaps here directly)
                var series = filenameMetadata.series
                var publisher = filenameMetadata.publisher
                var bookFormat = Comic.BookFormat.detect(
                    issueNumber: filenameMetadata.number, volume: filenameMetadata.volume,
                    fileType: fileType)

                let hints = SeriesKnowledge.shared.folderHints(for: url)
                if (series ?? "").isEmpty, let folderSeries = hints.series {
                    series = folderSeries
                }
                if let match = SeriesKnowledge.shared.match(series: series) {
                    series = match.canonicalSeries
                    if publisher == nil { publisher = match.publisher }
                    if bookFormat == .issue, match.bookFormat != .issue,
                        filenameMetadata.number == nil
                    {
                        bookFormat = match.bookFormat
                    }
                }
                if publisher == nil {
                    publisher = hints.publisher
                        ?? PublisherDetector.detectFromCharacters(series)
                }

                // Get reader for file type
                let reader: ComicReaderProtocol
                switch fileType {
                case .pdf: reader = PDFReader()
                case .cbr: reader = CBRReader()
                case .epub: reader = EPUBReader()
                default: reader = CBZReader()
                }

                // Get page count — non-fatal, CBR (RAR) files will fail with ZIPFoundation
                var pageCount = 0
                do {
                    pageCount = try await reader.getPageCount(from: url)
                } catch {
                    AppLog.library.error("[LibraryViewModel] ⚠️ Could not read page count (CBR?): \(error.localizedDescription)")
                }

                // Extract cover image, downsampled for storage (~100 KB JPEG
                // instead of a multi-MB full-resolution scan in the database)
                let rawCover = try? await reader.extractCover(from: url)
                let coverData: Data? = await Task.detached(priority: .userInitiated) {
                    rawCover.flatMap { PageImageCache.storageCoverData(from: $0) } ?? rawCover
                }.value

                // Get file size
                let fileSize =
                    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
                    ?? 0

                // Create extracted comic from filename metadata
                var extractedComic = Comic(
                    id: finalID,
                    filePath: url,
                    fileName: fileName,
                    bookmarkData: bookmarkData,
                    title: filenameMetadata.title,
                    publisher: publisher,
                    series: series,
                    issueNumber: filenameMetadata.number,
                    volume: filenameMetadata.volume,
                    year: filenameMetadata.year,
                    bookFormat: bookFormat,
                    writer: filenameMetadata.writer,
                    artist: filenameMetadata.penciller,
                    coverArtist: filenameMetadata.coverArtist,
                    summary: filenameMetadata.summary,
                    coverImageData: coverData,
                    status: .unread,
                    currentPage: 0,
                    totalPages: pageCount,
                    fileSize: fileSize,
                    fileType: fileType
                )

                // Rename file on disk if the clean name is different (skip bundled comics)
                let isBundledFile = url.path.contains(Bundle.main.bundlePath)
                let newFileName = extractedComic.cleanFileName
                if !isBundledFile && newFileName != fileName {
                    let newURL = url.deletingLastPathComponent().appendingPathComponent(newFileName)
                    do {
                        // Avoid overwriting an existing file with the same clean name
                        if !FileManager.default.fileExists(atPath: newURL.path) {
                            // Ensure destination directory exists before moving
                            try? FileManager.default.createDirectory(
                                at: newURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true,
                                attributes: nil
                            )
                            try FileManager.default.moveItem(at: url, to: newURL)
                            extractedComic.filePath = newURL
                            extractedComic.fileName = newFileName
                            // Create new bookmark for the renamed file
                            #if os(macOS)
                                extractedComic.bookmarkData = try? newURL.bookmarkData(
                                    options: [
                                        .withSecurityScope, .securityScopeAllowOnlyReadAccess,
                                    ],
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil
                                )
                            #else
                                extractedComic.bookmarkData = try? newURL.bookmarkData(
                                    options: .minimalBookmark,
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil
                                )
                            #endif
                            AppLog.library.debug("[LibraryViewModel] 📝 Renamed: \(fileName) → \(newFileName)")
                        } else {
                            AppLog.library.error("[LibraryViewModel] ⚠️ Skipped rename (target exists): \(newFileName)")
                        }
                    } catch {
                        AppLog.library.error("[LibraryViewModel] ⚠️ Rename failed (continuing with original): \(error.localizedDescription)")
                    }
                }

                // Merge with existing comic if present
                var finalComic = Comic.merged(existing: existingComic, extracted: extractedComic)

                // Save to database
                try await database.saveComic(finalComic)

                // Sort into the home library. Non-fatal: on failure the book
                // stays where it is (imported in place, like before).
                if let libraryRoot, !isBundledFile {
                    do {
                        let moved = try await LibraryFileService.shared.moveToLibrary(
                            finalComic, libraryRoot: libraryRoot, database: database)
                        if moved.filePath != finalComic.filePath {
                            await logActivity(.fileMoved, comic: moved, new: moved.fileName)
                        }
                        finalComic = moved
                    } catch {
                        AppLog.library.error(
                            "[LibraryViewModel] ⚠️ Library sort failed for \(finalComic.fileName): \(error.localizedDescription)"
                        )
                    }
                }

                // Auto-populate Knowledge Base with Series/Publisher
                checkAndAutoPopulateKnowledge(comic: finalComic)

                // Log import activity
                await logActivity(.imported, comic: finalComic, new: finalComic.fileName)

                // Add to new comics list
                newComics.append(finalComic)
                imported += 1

                // Teach the learning system this series → publisher/format link
                SeriesKnowledge.shared.recordImport(
                    series: finalComic.series,
                    publisher: finalComic.publisher,
                    bookFormat: finalComic.bookFormat
                )

                AppLog.library.info("[LibraryViewModel] ✅ Imported: \(extractedComic.fileName)")

            } catch {
                AppLog.library.error("[LibraryViewModel] ❌ Failed to import \(url.lastPathComponent): \(error)")
            }

            // Update progress
            await MainActor.run {
                importProgress = Double(index + 1) / Double(total)
            }
        }

        // Update comics array
        await MainActor.run {
            for comic in newComics {
                if let index = comics.firstIndex(where: { $0.id == comic.id }) {
                    comics[index] = comic
                } else {
                    comics.append(comic)
                }
            }

            isImporting = false
            importProgress = 0.0
            AppLog.library.info("[LibraryViewModel] ✅ Import complete: \(imported)/\(total) comics imported")
        }

        // Sync progress after import
        syncProgressFromTracker()

        return newComics.map(\.id)
    }

    // MARK: - Device Transfer (.scobook)

    /// Inserts a book received from another device (see BookPackageImporter).
    /// The comic arrives fully formed from the transfer manifest — metadata,
    /// reading progress, flags, and per-book reader prefs — so no filename
    /// parsing or ComicVine fetch happens here.
    func addTransferredComic(_ comic: Comic) async {
        do {
            AppLog.library.info("[LibraryViewModel] ⏱ transfer: saving comic…")
            try await database.saveComic(comic)
            AppLog.library.info("[LibraryViewModel] ⏱ transfer: saved, updating list…")
            if let index = comics.firstIndex(where: { $0.id == comic.id }) {
                comics[index] = comic
            } else {
                comics.append(comic)
            }
            AppLog.library.info("[LibraryViewModel] ⏱ transfer: logging activity…")
            await logActivity(.imported, comic: comic, new: comic.fileName)
            AppLog.library.info("[LibraryViewModel] ⏱ transfer: activity logged")
            // Teach the learning system, same as a normal import
            SeriesKnowledge.shared.recordImport(
                series: comic.series,
                publisher: comic.publisher,
                bookFormat: comic.bookFormat
            )
            checkAndAutoPopulateKnowledge(comic: comic)
            AppLog.library.info(
                "[LibraryViewModel] ✅ Received via transfer: \(comic.fileName)")
        } catch {
            AppLog.library.error(
                "[LibraryViewModel] ❌ Failed to save transferred comic: \(error)")
        }
    }

    // MARK: - Bundle Import

    /// Sample books that used to ship with the app but have been retired.
    /// Their library records are removed on launch so users aren't left
    /// with entries pointing at files that no longer exist in the bundle.
    /// (Lowercased filenames; user copies outside the bundle are untouched.)
    private static let retiredSampleFiles: Set<String> = [
        "x-men infinity comic 011 (2026) (digital) (marika-empire).cbz",
        "the_avenger_01 (1955).cbr",
    ]

    /// Scans the app bundle for comic files and imports them if not already present
    func importBundledComics() async {
        AppLog.library.debug("[LibraryViewModel] 📦 Scanning for bundled comics...")

        // Clean up retired samples first: records whose filename matches a
        // retired bundle sample AND whose file is gone (or still points into
        // an app bundle) are deleted outright.
        let retired = comics.filter { comic in
            guard Self.retiredSampleFiles.contains(comic.fileName.lowercased()) else {
                return false
            }
            let inBundle = comic.filePath.path.contains(".app/")
            let fileGone = !FileManager.default.fileExists(atPath: comic.filePath.path)
            return inBundle || fileGone
        }
        if !retired.isEmpty {
            AppLog.library.info(
                "[LibraryViewModel] 🗑️ Removing \(retired.count) retired sample book(s): \(retired.map(\.fileName))"
            )
            await deleteComicsFromApp(retired)
        }

        let extensions = ["cbz", "pdf", "cbr", "epub"]
        var bundledURLs: [URL] = []

        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                bundledURLs.append(contentsOf: urls)
            }
        }

        guard !bundledURLs.isEmpty else {
            AppLog.library.debug("[LibraryViewModel] ℹ️ No bundled comics found")
            return
        }

        AppLog.library.debug("[LibraryViewModel] ℹ️ Found \(bundledURLs.count) bundled comics: \(bundledURLs.map { $0.lastPathComponent })")

        // Filter out comics that already exist based on filename
        let existingFilenames = Set(comics.map { $0.fileName.lowercased() })
        let toImport = bundledURLs.filter {
            !existingFilenames.contains($0.lastPathComponent.lowercased())
        }

        if !toImport.isEmpty {
            AppLog.library.debug("[LibraryViewModel] 📥 Importing \(toImport.count) new bundled comics...")
            await importComics(from: toImport)
        } else {
            AppLog.library.info("[LibraryViewModel] ✅ All bundled comics already imported")
        }
    }

    // MARK: - Mark as Read

    func markAsRead(_ comicsToMark: [Comic]) {
        AppLog.library.debug("[LibraryViewModel] 📖 Marking \(comicsToMark.count) comics as read")
        for comic in comicsToMark {
            var updatedComic = comic
            updatedComic.status = .completed
            if updatedComic.totalPages > 0 {
                updatedComic.currentPage = updatedComic.totalPages - 1
            }
            updateComic(updatedComic)
        }
    }

    /// Mark books unread and reset their reading progress ("start over").
    /// Clears status, current page, and last-read date; per-book reader
    /// preferences (zoom, transition, etc.) are left untouched.
    func markAsUnread(_ comicsToReset: [Comic]) {
        AppLog.library.debug("[LibraryViewModel] 🔄 Resetting progress on \(comicsToReset.count) comics")
        for comic in comicsToReset {
            var updatedComic = comic
            updatedComic.status = .unread
            updatedComic.currentPage = 0
            updatedComic.lastReadDate = nil
            updateComic(updatedComic)
        }
    }

    // MARK: - Delete Comics

    /// Remove books from the app (database + library list). Files on disk are
    /// left untouched. Folder-membership rows cascade away in the database.
    func deleteComics(_ comics: [Comic]) {
        Task { await deleteComicsFromApp(comics) }
    }

    /// Async core: delete from the database and the in-memory list.
    func deleteComicsFromApp(_ toDelete: [Comic]) async {
        guard !toDelete.isEmpty else { return }
        for comic in toDelete {
            await logActivity(.deleted, comic: comic, old: comic.fileName)
            do {
                try await database.deleteComic(withID: comic.id)
            } catch {
                AppLog.library.error(
                    "[LibraryViewModel] ❌ Failed to delete \(comic.fileName) from database: \(error)"
                )
            }
        }
        let ids = Set(toDelete.map(\.id))
        comics.removeAll { ids.contains($0.id) }
        // Refresh folder counts (membership rows cascaded in the database).
        await loadFolders()
        AppLog.library.info(
            "[LibraryViewModel] 🗑️ Removed \(toDelete.count) book(s) from the app")
    }

    /// Delete the underlying files from disk (best-effort, skipping bundled
    /// samples), then remove the books from the app.
    func deleteComicsFromDevice(_ toDelete: [Comic]) async {
        guard !toDelete.isEmpty else { return }
        for comic in toDelete {
            if Comic.isBundled(comic) {
                AppLog.library.error(
                    "[LibraryViewModel] ℹ️ Skipping on-disk delete of bundled sample: \(comic.fileName)"
                )
                continue
            }
            deleteFileOnDisk(for: comic)
        }
        await deleteComicsFromApp(toDelete)
    }

    /// Remove a single comic's file from disk, honouring its security-scoped
    /// bookmark. Failures are logged but don't block app removal.
    private func deleteFileOnDisk(for comic: Comic) {
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
                    didStartAccess = resolved.startAccessingSecurityScopedResource()
                }
            #endif
        }
        defer { if didStartAccess { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            try FileManager.default.removeItem(at: fileURL)
            AppLog.library.info(
                "[LibraryViewModel] 🗑️ Deleted file from disk: \(comic.fileName)")
        } catch {
            AppLog.library.error(
                "[LibraryViewModel] ⚠️ Could not delete file \(comic.fileName): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Relink (Locate File)

    /// Re-point a missing/moved book at a file the user selected, minting a
    /// fresh security-scoped bookmark and clearing the needs-attention flag.
    func relinkComic(_ comic: Comic, to url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else {
            AppLog.library.error(
                "[LibraryViewModel] ⚠️ Relink target missing: \(url.path)")
            return
        }

        #if os(macOS)
            let bookmarkData = try? url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        #else
            let bookmarkData = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        #endif

        var updated = comic
        updated.filePath = url
        updated.fileName = url.lastPathComponent
        updated.bookmarkData = bookmarkData
        updated.needsAttention = false
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size]
            as? Int64
        {
            updated.fileSize = size
        }
        updated.dateModified = Date()

        if let index = comics.firstIndex(where: { $0.id == comic.id }) {
            comics[index] = updated
        }
        do {
            try await database.updateComic(updated)
            AppLog.library.info("[LibraryViewModel] 🔗 Relinked \(updated.fileName)")
        } catch {
            AppLog.library.error(
                "[LibraryViewModel] ❌ Failed to persist relink: \(error)")
        }
    }

    // MARK: - Knowledge Pruning

    /// After a correction, remove a publisher/series suggestion that no book
    /// uses anymore — so misspellings like "Malibu Malibu Comics Entertainment"
    /// stop appearing in autocomplete once they're fixed everywhere.
    func pruneKnowledgeIfOrphaned(type: KnowledgeEntry.EntryType, name: String?) {
        guard let name, !name.isEmpty else { return }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let stillUsed: Bool
        switch type {
        case .publisher:
            stillUsed = comics.contains {
                ($0.publisher ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == normalized
            }
        case .series:
            stillUsed = comics.contains {
                ($0.series ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == normalized
            }
        default:
            return
        }
        guard !stillUsed else { return }

        Task {
            try? await database.deleteKnowledgeEntry(type: type, name: name)
            AppLog.library.debug("[LibraryViewModel] 🧹 Pruned orphaned \(type.rawValue) suggestion: \(name)")
        }
    }

    /// Bulk sweep for the Maintenance tab: removes every publisher/series
    /// knowledge entry that no book in the library uses anymore. The per-edit
    /// `pruneKnowledgeIfOrphaned` handles the common case reactively; this
    /// catches anything that slipped through (bulk deletes, old data).
    /// Returns the number of entries removed.
    func pruneOrphanedKnowledge() async -> Int {
        func normalize(_ s: String?) -> String? {
            guard let s else { return nil }
            let n = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return n.isEmpty ? nil : n
        }
        let usedPublishers = Set(comics.compactMap { normalize($0.publisher) })
        let usedSeries = Set(comics.compactMap { normalize($0.series) })

        var removed = 0
        for type in [KnowledgeEntry.EntryType.publisher, .series] {
            guard let entries = try? await database.fetchKnowledgeEntries(type: type) else {
                continue
            }
            let used = (type == .publisher) ? usedPublishers : usedSeries
            for entry in entries where !used.contains(entry.normalizedName) {
                if (try? await database.deleteKnowledgeEntry(entry)) != nil {
                    removed += 1
                    AppLog.library.debug(
                        "[LibraryViewModel] 🧹 Pruned orphaned \(type.rawValue): \(entry.name)")
                }
            }
        }
        return removed
    }

    // MARK: - Re-sort After Edits

    /// After metadata changes, move the file to its correct library location
    /// (publisher/series folder + clean name) when auto-sort is enabled and
    /// the file already lives inside the home library. Empty source folders
    /// (e.g. a misspelled publisher) are cleaned up by the move.
    func resortAfterEdit(_ comicID: UUID) async {
        let settings = AppSettings.load()
        guard settings.autoSortIntoLibrary,
            let libraryRoot = SettingsViewModel().resolveHomeLibraryURL(),
            let index = comics.firstIndex(where: { $0.id == comicID })
        else { return }

        let comic = comics[index]

        // Only manage files that already live inside the library root —
        // books elsewhere (external folders, iCloud) are left where they are.
        let rootPath = libraryRoot.standardizedFileURL.path
        guard comic.filePath.standardizedFileURL.path.hasPrefix(rootPath + "/") else { return }

        do {
            // moveToLibrary no-ops when the file is already in the right
            // place, renames + moves otherwise, refreshes the bookmark, and
            // removes now-empty source folders.
            let moved = try await LibraryFileService.shared.moveToLibrary(
                comic, libraryRoot: libraryRoot, database: database)
            guard moved.filePath != comic.filePath else { return }

            if let i = comics.firstIndex(where: { $0.id == moved.id }) {
                comics[i] = moved
            }
            await logActivity(.fileMoved, comic: moved, new: moved.fileName)
        } catch {
            AppLog.library.error("[LibraryViewModel] ⚠️ Re-sort after edit failed for \(comic.fileName): \(error)")
        }
    }

    // MARK: - Bulk Edit

    /// Apply non-nil fields to all library comics in `ids`, persist, and
    /// teach the learning system the resulting associations.
    func bulkEdit(ids: Set<UUID>, values: BulkEditValues) {
        // Track replaced names so orphaned suggestions can be pruned after
        var replacedPublishers = Set<String>()
        var replacedSeries = Set<String>()

        for index in comics.indices where ids.contains(comics[index].id) {
            var comic = comics[index]
            if values.publisher != nil, let oldPublisher = comic.publisher,
                oldPublisher != values.publisher
            {
                replacedPublishers.insert(oldPublisher)
            }
            if values.series != nil, let oldSeries = comic.series, oldSeries != values.series {
                replacedSeries.insert(oldSeries)
            }
            if let series = values.series { comic.series = series }
            if let publisher = values.publisher { comic.publisher = publisher }
            if let year = values.year { comic.year = year }
            if let volume = values.volume { comic.volume = volume }
            if let bookFormat = values.bookFormat { comic.bookFormat = bookFormat }
            if let title = values.title { comic.title = title }
            if let writer = values.writer { comic.writer = writer }
            if let artist = values.artist { comic.artist = artist }
            if let coverArtist = values.coverArtist { comic.coverArtist = coverArtist }
            if let colorist = values.colorist { comic.colorist = colorist }
            if let inker = values.inker { comic.inker = inker }
            if let editor = values.editor { comic.editor = editor }
            if let summary = values.summary { comic.summary = summary }
            if let contentRating = values.contentRating { comic.contentRating = contentRating }
            comic.dateModified = Date()
            comics[index] = comic

            Task { try? await persistComic(comic) }
            // Update associations without inflating the import counter
            SeriesKnowledge.shared.recordImport(
                series: comic.series, publisher: comic.publisher,
                bookFormat: comic.bookFormat, countsAsImport: false)
        }
        AppLog.library.debug("[LibraryViewModel] ✏️ Bulk-edited \(ids.count) comics")

        // Drop autocomplete suggestions the correction just orphaned
        for publisher in replacedPublishers {
            pruneKnowledgeIfOrphaned(type: .publisher, name: publisher)
        }
        for series in replacedSeries {
            pruneKnowledgeIfOrphaned(type: .series, name: series)
        }

        // Re-file edited books whose folder or clean filename changed
        // (sequentially — concurrent moves could race on folder cleanup)
        let affectsLocation =
            values.series != nil || values.publisher != nil || values.year != nil
            || values.volume != nil || values.bookFormat != nil
        if affectsLocation {
            Task {
                for id in ids {
                    await resortAfterEdit(id)
                }
            }
        }
    }

    // MARK: - Pre-fetching (iOS only)

    #if os(iOS)
        /// Begin loading a comic in the background so the reader can open without a spinner.
        /// Call this just before setting `readingComic` — the head start is usually enough
        /// for small-to-medium CBZ files to be fully in memory by the time the view appears.
        func prefetchComic(_ comic: Comic) {
            // Cancel any in-flight pre-fetch for a different comic
            if prefetchedForComicID != comic.id {
                prefetchTask?.cancel()
                prefetchedComicBook = nil
                prefetchedForComicID = nil
            }

            // Don't re-fetch if we already have this comic ready
            if prefetchedForComicID == comic.id, prefetchedComicBook != nil { return }

            prefetchedForComicID = comic.id

            prefetchTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }

                // Resolve file URL
                var fileURL: URL
                var didStartAccess = false
                if let bookmarkData = comic.bookmarkData {
                    var isStale = false
                    if let resolved = try? URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withoutUI,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    ) {
                        fileURL = resolved
                        didStartAccess = resolved.startAccessingSecurityScopedResource()
                    } else {
                        fileURL = comic.resolvedURL
                    }
                } else {
                    // Bundled or plain URL
                    fileURL = comic.resolvedURL
                }

                defer {
                    // Pre-fetch only needs access during loading; ReaderViewModel manages its own
                    if didStartAccess { fileURL.stopAccessingSecurityScopedResource() }
                }

                let reader: ComicReaderProtocol
                switch comic.fileType {
                case .pdf: reader = PDFReader()
                case .cbr: reader = CBRReader()
                default:   reader = CBZReader()
                }

                guard !Task.isCancelled else { return }

                do {
                    let comicBook = try await reader.loadComic(from: fileURL)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        // Only store if the ID still matches (user hasn't changed selection)
                        if self.prefetchedForComicID == comic.id {
                            self.prefetchedComicBook = comicBook
                            AppLog.library.info("[LibraryViewModel] ⚡ Pre-fetch complete for: \(comic.fileName)")
                        }
                    }
                } catch {
                    AppLog.library.error("[LibraryViewModel] ⚠️ Pre-fetch failed for \(comic.fileName): \(error)")
                }
            }
        }

        /// Consume (and clear) the pre-fetched comic book, returning it if it matches.
        func consumePrefetchedComicBook(for comicID: UUID) -> ComicBook? {
            guard prefetchedForComicID == comicID, let book = prefetchedComicBook else { return nil }
            prefetchedComicBook = nil
            prefetchedForComicID = nil
            AppLog.library.info("[LibraryViewModel] ✅ Consumed pre-fetched comic — skipping load spinner")
            return book
        }
    #endif

    // MARK: - Knowledge Base Integration

    private func checkAndAutoPopulateKnowledge(comic: Comic) {
        // Sync series, publisher AND every creator credit through the shared
        // helper. Previously this only wrote series + publisher, so creators
        // enriched from ComicVine reached the comic's metadata but never the
        // Knowledge Base (see DatabaseManager.syncKnowledge).
        Task {
            await database.syncKnowledge(from: comic)
        }
    }

    // MARK: - Staged Comic Import (Organize Workflow)

    /// Import a comic from the Organize staging area directly.
    /// Uses the StagedComic's metadata instead of re-parsing from filename,
    /// and uses the originalURL for security-scoped access.
    func importStagedComic(
        series: String, issueNumber: String?, volume: Int?, year: Int?,
        bookFormat: Comic.BookFormat = .issue,
        publisher: String?, title: String?, writer: String?, artist: String?,
        coverArtist: String?, colorist: String?, inker: String?, editor: String?,
        summary: String?, originalURL: URL, fileURL: URL
    ) async {
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
        }

        do {
            // Use the ORIGINAL url for security scope (it has the open-panel grant)
            let accessing = originalURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { originalURL.stopAccessingSecurityScopedResource() }
            }

            let fileName = fileURL.lastPathComponent
            let fileExtension = fileURL.pathExtension.lowercased()

            guard let fileType = Comic.FileType(rawValue: fileExtension) else {
                AppLog.library.error("[LibraryViewModel] ⚠️ Unsupported file type from Organize: \(fileName)")
                await MainActor.run { isImporting = false }
                return
            }

            // Create bookmark for persistent access on the final file
            #if os(macOS)
                let bookmarkData = try? fileURL.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            #else
                // .minimalBookmark creates a resolvable bookmark on iOS/iPadOS.
                // Empty options [] produce a non-resolvable bookmark — do NOT use [].
                let bookmarkData = try? fileURL.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            #endif

            // Generate stable ID from the ORIGINAL path (consistent identity)
            let stablePath = originalURL.standardizedFileURL.path
            let pathData = stablePath.data(using: .utf8) ?? Data()
            let pathHash = pathData.withUnsafeBytes { bytes in
                var hash: UInt64 = 5381
                let buffer = UnsafeRawBufferPointer(bytes)
                for byte in buffer {
                    hash = ((hash << 5) &+ hash) &+ UInt64(byte)
                }
                return hash
            }
            let hashBytes = withUnsafeBytes(of: pathHash) { Data($0) }
            let uuidBytes = Data((0..<16).map { hashBytes[$0 % hashBytes.count] })
            let comicID = UUID(uuid: uuidBytes.withUnsafeBytes { $0.load(as: uuid_t.self) })

            // Check if comic already exists
            let existingComic = try? await database.fetchComic(id: comicID)
            let finalID = existingComic?.id ?? comicID

            // Get reader for file type
            let reader: ComicReaderProtocol
            switch fileType {
            case .pdf: reader = PDFReader()
            case .cbr: reader = CBRReader()
            default: reader = CBZReader()
            }

            // Get page count — non-fatal, as CBR (RAR) files will fail with ZIPFoundation
            var pageCount = 0
            do {
                pageCount = try await reader.getPageCount(from: fileURL)
            } catch {
                AppLog.library.error("[LibraryViewModel] ⚠️ Could not read page count (CBR?): \(error.localizedDescription)")
            }

            // Extract cover image — also non-fatal; downsampled for storage
            let rawCover = try? await reader.extractCover(from: fileURL)
            let coverData: Data? = await Task.detached(priority: .userInitiated) {
                rawCover.flatMap { PageImageCache.storageCoverData(from: $0) } ?? rawCover
            }.value

            // Get file size
            let fileSize =
                (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64)
                ?? 0

            // Build Comic directly from the staged metadata
            let newComic = Comic(
                id: finalID,
                filePath: fileURL,
                fileName: fileName,
                bookmarkData: bookmarkData,
                title: title,
                publisher: publisher,
                series: series.isEmpty ? nil : series,
                issueNumber: issueNumber,
                volume: volume,
                year: year,
                bookFormat: bookFormat,
                writer: writer,
                artist: artist,
                coverArtist: coverArtist,
                colorist: colorist,
                inker: inker,
                editor: editor,
                summary: summary,
                coverImageData: coverData,
                status: .unread,
                currentPage: 0,
                totalPages: pageCount,
                fileSize: fileSize,
                fileType: fileType
            )

            // Merge with existing comic if present
            let finalComic = Comic.merged(existing: existingComic, extracted: newComic)

            // Save to database
            try await database.saveComic(finalComic)

            // Auto-populate Knowledge Base
            checkAndAutoPopulateKnowledge(comic: finalComic)

            // Update comics array
            await MainActor.run {
                if let index = comics.firstIndex(where: { $0.id == finalComic.id }) {
                    comics[index] = finalComic
                } else {
                    comics.append(finalComic)
                }
            }

            AppLog.library.info("[LibraryViewModel] ✅ Imported from Organize: \(fileName)")
        } catch {
            AppLog.library.error("[LibraryViewModel] ❌ Failed to import from Organize \(fileURL.lastPathComponent): \(error)")
        }

        await MainActor.run {
            isImporting = false
            importProgress = 0.0
        }

        syncProgressFromTracker()
    }
}

// MARK: - Folders (Collections)

extension LibraryViewModel {

    /// Reload folders and the full membership map from the database.
    func loadFolders() async {
        do {
            let fetchedFolders = try await database.fetchFolders()
            let membership = try await database.fetchFolderMembership()
            self.folders = fetchedFolders
            self.folderMembership = membership
            AppLog.library.info(
                "[LibraryViewModel] ✅ Loaded \(fetchedFolders.count) folders")
        } catch {
            AppLog.library.error("[LibraryViewModel] ❌ Failed to load folders: \(error)")
        }
    }

    /// Create a folder; returns it so callers can immediately add books.
    @discardableResult
    func createFolder(named name: String) async -> Folder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (folders.map(\.sortOrder).max() ?? 0) + 1
        let folder = Folder(name: trimmed, sortOrder: nextOrder)
        do {
            try await database.saveFolder(folder)
            await loadFolders()
            return folder
        } catch {
            AppLog.library.error("[LibraryViewModel] ❌ Failed to create folder: \(error)")
            return nil
        }
    }

    func renameFolder(_ folder: Folder, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        var updated = folder
        updated.name = trimmed
        updated.dateModified = Date()
        do {
            try await database.saveFolder(updated)
            await loadFolders()
        } catch {
            AppLog.library.error("[LibraryViewModel] ❌ Failed to rename folder: \(error)")
        }
    }

    func deleteFolder(_ folder: Folder) async {
        do {
            try await database.deleteFolder(id: folder.id)
            await loadFolders()
        } catch {
            AppLog.library.error("[LibraryViewModel] ❌ Failed to delete folder: \(error)")
        }
    }

    // MARK: Folder covers

    /// Assign a custom cover picture to a folder. Raw image bytes are
    /// downsampled to a storage-friendly JPEG (max 800 px) before saving, and
    /// any previously chosen representative book is cleared so the picture
    /// takes effect immediately.
    func setFolderCover(_ folder: Folder, imageData rawData: Data) async {
        let normalized = PageImageCache.storageCoverData(from: rawData) ?? rawData
        var updated = folder
        updated.coverImageData = normalized
        updated.coverComicID = nil
        updated.dateModified = Date()
        await persistFolderCoverChange(updated)
    }

    /// Choose a single member book to represent the folder. Clears any custom
    /// picture so the book cover is used.
    func setFolderCover(_ folder: Folder, comicID: UUID) async {
        var updated = folder
        updated.coverComicID = comicID
        updated.coverImageData = nil
        updated.dateModified = Date()
        await persistFolderCoverChange(updated)
    }

    /// Reset a folder to the default 2×2 collage of recent member covers.
    func clearFolderCover(_ folder: Folder) async {
        guard folder.coverImageData != nil || folder.coverComicID != nil else { return }
        var updated = folder
        updated.coverImageData = nil
        updated.coverComicID = nil
        updated.dateModified = Date()
        await persistFolderCoverChange(updated)
    }

    private func persistFolderCoverChange(_ folder: Folder) async {
        do {
            try await database.saveFolder(folder)
            await loadFolders()
        } catch {
            AppLog.library.error("[LibraryViewModel] ❌ Failed to update folder cover: \(error)")
        }
    }

    func addComics(_ ids: [UUID], toFolder folderID: UUID) async {
        guard !ids.isEmpty else { return }
        do {
            try await database.addComics(ids, toFolder: folderID)
            await loadFolders()
        } catch {
            AppLog.library.error("[LibraryViewModel] ❌ Failed to add to folder: \(error)")
        }
    }

    func removeComics(_ ids: [UUID], fromFolder folderID: UUID) async {
        guard !ids.isEmpty else { return }
        do {
            try await database.removeComics(ids, fromFolder: folderID)
            await loadFolders()
        } catch {
            AppLog.library.error("[LibraryViewModel] ❌ Failed to remove from folder: \(error)")
        }
    }

    // MARK: Synchronous view helpers

    /// Comic IDs in a folder (empty if unknown).
    func comicIDs(inFolder folderID: UUID) -> Set<UUID> {
        folderMembership[folderID] ?? []
    }

    /// Number of books in a folder.
    func folderCount(_ folderID: UUID) -> Int {
        folderMembership[folderID]?.count ?? 0
    }

    /// Folders that contain a given comic, in display order.
    func folders(containing comicID: UUID) -> [Folder] {
        folders.filter { folderMembership[$0.id]?.contains(comicID) == true }
    }

    /// Whether a comic is in a folder.
    func isComic(_ comicID: UUID, inFolder folderID: UUID) -> Bool {
        folderMembership[folderID]?.contains(comicID) == true
    }

    /// IDs of comics that belong to no folder.
    func unfiledComicIDs() -> Set<UUID> {
        let filed = folderMembership.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        return Set(comics.map(\.id)).subtracting(filed)
    }

    /// Number of books not in any folder.
    var unfiledCount: Int {
        unfiledComicIDs().count
    }
}
