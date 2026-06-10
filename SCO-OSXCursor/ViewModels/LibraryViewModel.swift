import Combine
import Foundation
import SwiftUI

#if os(macOS)
    import AppKit
#endif

#if os(iOS)
    import UIKit
#endif

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var comics: [Comic] = []

    // ✅ Track which comics are currently being edited
    @Published var editingComicIDs: Set<UUID> = []

    // ✅ Track the comic currently being read to present in full screen
    @Published var readingComic: Comic?

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
                    print(
                        "[LibraryViewModel] ✅ Persisted refreshed bookmark for: \(updated.fileName)"
                    )
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
                print("[LibraryViewModel] ✅ Loaded \(fetchedComics.count) comics from database")
            }
        } catch {
            print("[LibraryViewModel] ❌ Failed to load comics: \(error)")
        }
    }

    // ✅ DB-only persistence (NO array update)
    func persistComic(_ comic: Comic) async throws {
        try await database.updateComic(comic)
        print("[LibraryViewModel] ✅ Persisted comic to database: \(comic.fileName)")
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
                print("[LibraryViewModel] ⚠️ Missing file flagged: \(comics[index].fileName)")
            } else {
                print("[LibraryViewModel] ✅ Cleared missing flag: \(comics[index].fileName)")
            }
        }

        if flaggedCount > 0 {
            print("[LibraryViewModel] ⚠️ \(flaggedCount) comics flagged as missing")
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
            print("[LibraryViewModel] ⚠️ Cover regeneration failed for \(comic.fileName)")
            return
        }

        // Downsample for storage
        let coverData: Data = await Task.detached(priority: .userInitiated) {
            PageImageCache.storageCoverData(from: rawCover) ?? rawCover
        }.value

        var updated = comic
        updated.coverImageData = coverData
        updateComic(updated)
        print("[LibraryViewModel] ✅ Cover regenerated for \(comic.fileName)")
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
                print("[LibraryViewModel] ✅ Synced progress (batched)")
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
                print("[LibraryViewModel] 📖 Restored progress (batched)")
            }
        }
    }

    // MARK: - Import Comics

    func importComics(from rawURLs: [URL]) async {
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

        let urls: [URL] = await Task.detached(priority: .userInitiated) {
            let validExtensions = ["cbz", "cbr", "pdf", "epub"]
            let fm = FileManager.default
            var files: [URL] = []
            for url in rawURLs {
                // Per-URL scope for the stat/enumeration (balanced; folder
                // scopes opened above remain active independently)
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    // Couldn't stat — if it looks like a comic file, let the
                    // import loop try it with its own security scope
                    if validExtensions.contains(url.pathExtension.lowercased()) {
                        files.append(url)
                    }
                    continue
                }
                if isDirectory.boolValue {
                    if let walker = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) {
                        for case let fileURL as URL in walker
                        where validExtensions.contains(fileURL.pathExtension.lowercased()) {
                            files.append(fileURL)
                        }
                    }
                } else {
                    files.append(url)
                }
            }
            return files.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                    == .orderedAscending
            }
        }.value

        let total = urls.count
        var imported = 0
        var newComics: [Comic] = []

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
                    print("[LibraryViewModel] ⚠️ Skipping unsupported file: \(fileName)")
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
                    issueNumber: filenameMetadata.number, volume: filenameMetadata.volume)

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
                    print(
                        "[LibraryViewModel] ⚠️ Could not read page count (CBR?): \(error.localizedDescription)"
                    )
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
                            print("[LibraryViewModel] 📝 Renamed: \(fileName) → \(newFileName)")
                        } else {
                            print(
                                "[LibraryViewModel] ⚠️ Skipped rename (target exists): \(newFileName)"
                            )
                        }
                    } catch {
                        print(
                            "[LibraryViewModel] ⚠️ Rename failed (continuing with original): \(error.localizedDescription)"
                        )
                    }
                }

                // Merge with existing comic if present
                let finalComic = Comic.merged(existing: existingComic, extracted: extractedComic)

                // Save to database
                try await database.saveComic(finalComic)

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

                print("[LibraryViewModel] ✅ Imported: \(extractedComic.fileName)")

            } catch {
                print("[LibraryViewModel] ❌ Failed to import \(url.lastPathComponent): \(error)")
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
            print("[LibraryViewModel] ✅ Import complete: \(imported)/\(total) comics imported")
        }

        // Sync progress after import
        syncProgressFromTracker()
    }

    // MARK: - Bundle Import

    /// Scans the app bundle for comic files and imports them if not already present
    func importBundledComics() async {
        print("[LibraryViewModel] 📦 Scanning for bundled comics...")

        let extensions = ["cbz", "pdf", "cbr", "epub"]
        var bundledURLs: [URL] = []

        for ext in extensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                bundledURLs.append(contentsOf: urls)
            }
        }

        guard !bundledURLs.isEmpty else {
            print("[LibraryViewModel] ℹ️ No bundled comics found")
            return
        }

        print(
            "[LibraryViewModel] ℹ️ Found \(bundledURLs.count) bundled comics: \(bundledURLs.map { $0.lastPathComponent })"
        )

        // Filter out comics that already exist based on filename
        let existingFilenames = Set(comics.map { $0.fileName.lowercased() })
        let toImport = bundledURLs.filter {
            !existingFilenames.contains($0.lastPathComponent.lowercased())
        }

        if !toImport.isEmpty {
            print("[LibraryViewModel] 📥 Importing \(toImport.count) new bundled comics...")
            await importComics(from: toImport)
        } else {
            print("[LibraryViewModel] ✅ All bundled comics already imported")
        }
    }

    // MARK: - Mark as Read

    func markAsRead(_ comicsToMark: [Comic]) {
        print("[LibraryViewModel] 📖 Marking \(comicsToMark.count) comics as read")
        for comic in comicsToMark {
            var updatedComic = comic
            updatedComic.status = .completed
            if updatedComic.totalPages > 0 {
                updatedComic.currentPage = updatedComic.totalPages - 1
            }
            updateComic(updatedComic)
        }
    }

    // MARK: - Delete Comics

    func deleteComics(_ comics: [Comic]) {
        // TODO: Implement delete logic
        // This is a placeholder - needs full implementation
        print("[LibraryViewModel] ⚠️ deleteComics(_:) needs implementation")

        for comic in comics {
            // Log deletion before removing
            Task { await logActivity(.deleted, comic: comic, old: comic.fileName) }
            if let index = self.comics.firstIndex(where: { $0.id == comic.id }) {
                self.comics.remove(at: index)
            }
            // TODO: Delete from database
            Task {
                // await database.deleteComic(comic)
            }
        }
    }

    // MARK: - Bulk Edit

    /// Apply non-nil fields to all library comics in `ids`, persist, and
    /// teach the learning system the resulting associations.
    func bulkEdit(ids: Set<UUID>, values: BulkEditValues) {
        for index in comics.indices where ids.contains(comics[index].id) {
            var comic = comics[index]
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
            SeriesKnowledge.shared.recordImport(
                series: comic.series, publisher: comic.publisher,
                bookFormat: comic.bookFormat)
        }
        print("[LibraryViewModel] ✏️ Bulk-edited \(ids.count) comics")
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
                            print("[LibraryViewModel] ⚡ Pre-fetch complete for: \(comic.fileName)")
                        }
                    }
                } catch {
                    print("[LibraryViewModel] ⚠️ Pre-fetch failed for \(comic.fileName): \(error)")
                }
            }
        }

        /// Consume (and clear) the pre-fetched comic book, returning it if it matches.
        func consumePrefetchedComicBook(for comicID: UUID) -> ComicBook? {
            guard prefetchedForComicID == comicID, let book = prefetchedComicBook else { return nil }
            prefetchedComicBook = nil
            prefetchedForComicID = nil
            print("[LibraryViewModel] ✅ Consumed pre-fetched comic — skipping load spinner")
            return book
        }
    #endif

    // MARK: - Knowledge Base Integration

    private func checkAndAutoPopulateKnowledge(comic: Comic) {
        Task {
            // Auto-add Series
            if let series = comic.series, !series.isEmpty {
                let entry = KnowledgeEntry(type: .series, name: series)
                try? await database.saveKnowledgeEntry(entry)
            }

            // Auto-add Publisher
            if let publisher = comic.publisher, !publisher.isEmpty {
                // Optional: Add to knowledge base
                let entry = KnowledgeEntry(type: .publisher, name: publisher)
                try? await database.saveKnowledgeEntry(entry)
            }
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
                print("[LibraryViewModel] ⚠️ Unsupported file type from Organize: \(fileName)")
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
                print(
                    "[LibraryViewModel] ⚠️ Could not read page count (CBR?): \(error.localizedDescription)"
                )
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

            print("[LibraryViewModel] ✅ Imported from Organize: \(fileName)")
        } catch {
            print(
                "[LibraryViewModel] ❌ Failed to import from Organize \(fileURL.lastPathComponent): \(error)"
            )
        }

        await MainActor.run {
            isImporting = false
            importProgress = 0.0
        }

        syncProgressFromTracker()
    }
}
