import Combine
import Foundation
import SwiftUI

#if os(macOS)
    import AppKit
#endif

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var comics: [Comic] = []

    // ✅ Track which comics are currently being edited
    @Published var editingComicIDs: Set<UUID> = []

    // ✅ Track the comic currently being read to present in full screen
    @Published var readingComic: Comic?

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
            // If library is empty, automatically import bundled samples
            if comics.isEmpty {
                await importBundledComics()
            }
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
        default: reader = CBZReader()
        }

        guard let coverData = try? await reader.extractCover(from: fileURL) else {
            print("[LibraryViewModel] ⚠️ Cover regeneration failed for \(comic.fileName)")
            return
        }

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

    func importComics(from urls: [URL]) async {
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
        }

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
                    let bookmarkData = try? url.bookmarkData(
                        options: [],
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

                // Get reader for file type
                let reader: ComicReaderProtocol
                switch fileType {
                case .pdf: reader = PDFReader()
                case .cbr: reader = CBRReader()
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

                // Extract cover image
                let coverData = try? await reader.extractCover(from: url)

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
                    publisher: filenameMetadata.publisher,
                    series: filenameMetadata.series,
                    issueNumber: filenameMetadata.number,
                    volume: filenameMetadata.volume,
                    year: filenameMetadata.year,
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

        let extensions = ["cbz", "pdf", "cbr"]
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
                let bookmarkData = try? fileURL.bookmarkData(
                    options: [],
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

            // Extract cover image — also non-fatal
            let coverData = try? await reader.extractCover(from: fileURL)

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
