//
//  OrganizeViewModel.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 2/15/26.
//

import Combine
import Foundation
import SwiftUI
import os

/// ViewModel for the Organize (Staging) workflow.
/// Manages temporary `StagedComic` objects before they are committed to the Library.
@MainActor
final class OrganizeViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var stagedComics: [StagedComic] = []
    @Published var selectedComicID: UUID?
    @Published var checkedComicIDs: Set<UUID> = []

    // Processing State
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0.0
    /// Path description shown after a successful library sort (e.g. "Marvel/X-Men/")
    @Published var lastMoveDestination: String?

    // Dependencies
    private let libraryViewModel: LibraryViewModel

    /// Security-scoped folders the user dropped/selected. Their scope must stay
    /// open while staged files inside them are read, renamed and imported.
    private var activeScopedFolders: [URL] = []

    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }

    deinit {
        for url in activeScopedFolders {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Computed Properties

    var selectedComic: StagedComic? {
        guard let id = selectedComicID else { return nil }
        return stagedComics.first(where: { $0.id == id })
    }

    // MARK: - File Actions

    /// Add files OR folders to the staging area (Drag & Drop or Open Panel).
    /// Folders are scanned recursively for supported comic files.
    func addFiles(_ urls: [URL]) async {
        isProcessing = true
        processingProgress = 0.0

        let validExtensions = ["cbz", "cbr", "pdf", "epub"]

        // Separate folders from files; keep folder security scopes open for
        // the rest of the staging session so their children stay readable.
        //
        // IMPORTANT (iOS sandbox): start security-scoped access BEFORE any
        // file-system call — even fileExists() returns false on an unscoped
        // picker URL.
        var scopedFolders: [URL] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path, isDirectory: &isDirectory)
            if accessing && exists && isDirectory.boolValue {
                scopedFolders.append(url)
            } else if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        activeScopedFolders.append(contentsOf: scopedFolders)

        // Expand folders recursively off the main thread.
        // (Synchronous helper — DirectoryEnumerator iteration is unavailable
        // in async contexts under Swift 6.)
        let fileURLs: [URL] = await Task.detached(priority: .userInitiated) {
            Self.expandComicFileURLs(urls, validExtensions: validExtensions)
        }.value

        // Make sure learned knowledge is available before matching
        await SeriesKnowledge.shared.loadIfNeeded()

        var newComics: [StagedComic] = []
        for (index, url) in fileURLs.enumerated() {
            // Create StagedComic (parses the filename on init)
            var staged = StagedComic(url: url)
            // Enrich from learned series knowledge + folder-name hints
            applyKnowledge(to: &staged)
            newComics.append(staged)
            processingProgress = Double(index + 1) / Double(fileURLs.count)
        }

        // Append to list
        stagedComics.append(contentsOf: newComics)

        // Auto-select first new item if nothing selected
        if selectedComicID == nil, let first = newComics.first {
            selectedComicID = first.id
        }

        isProcessing = false
        AppLog.organize.debug("[OrganizeViewModel] Added \(newComics.count) files to staging.")

        // Enrich from embedded ComicInfo.xml in the background — embedded
        // metadata beats filename guessing and raises auto-match confidence.
        enrichFromEmbeddedMetadata(newComics)
    }

    /// Recursively expand file/folder URLs into the comic files they contain.
    /// Synchronous on purpose: FileManager.DirectoryEnumerator can't be
    /// iterated from async contexts in the Swift 6 language mode.
    nonisolated static func expandComicFileURLs(
        _ urls: [URL], validExtensions: [String]
    ) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default

        for url in urls {
            // Per-URL scope for the stat/enumeration (balanced; folder
            // scopes opened by the caller remain active independently)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                // Couldn't stat — if it looks like a comic file, keep it;
                // downstream file ops use their own scopes
                if validExtensions.contains(url.pathExtension.lowercased()) {
                    result.append(url)
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
                        result.append(fileURL)
                    }
                }
            } else if validExtensions.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }

        return result.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                == .orderedAscending
        }
    }

    // MARK: - Learned Knowledge Application

    /// Fill gaps in a staged comic from learned series knowledge and the
    /// folder structure it came from, then re-evaluate its confidence.
    private func applyKnowledge(to comic: inout StagedComic) {
        let knowledge = SeriesKnowledge.shared
        let hints = knowledge.folderHints(for: comic.originalURL)

        // Filename gave no series → fall back to the folder name
        if comic.series.isEmpty, let folderSeries = hints.series {
            comic.series = folderSeries
        }

        // Known series (or learned alias) → canonical name, publisher, format
        if let match = knowledge.match(series: comic.series) {
            comic.series = match.canonicalSeries
            if comic.publisher == nil {
                comic.publisher = match.publisher
            }
            if comic.bookFormat == .issue, match.bookFormat != .issue,
                comic.issueNumber == nil
            {
                comic.bookFormat = match.bookFormat
            }
        }

        // Publisher fallbacks: folder name, then character heuristics
        if comic.publisher == nil {
            comic.publisher = hints.publisher
        }
        if comic.publisher == nil {
            comic.publisher = PublisherDetector.detectFromCharacters(comic.series)
        }

        comic.reevaluate(userEdited: false)
    }

    // MARK: - Embedded Metadata Enrichment

    /// Read ComicInfo.xml from staged CBZ/CBR files in the background and
    /// merge it into any fields the filename parse couldn't fill.
    /// Runs serially so a large folder drop doesn't open hundreds of archives
    /// at once; each row updates in the UI as its metadata arrives.
    private func enrichFromEmbeddedMetadata(_ comics: [StagedComic]) {
        let targets: [(id: UUID, url: URL, ext: String)] = comics.compactMap { staged in
            let ext = staged.originalURL.pathExtension.lowercased()
            guard ext == "cbz" || ext == "cbr" else { return nil }
            return (staged.id, staged.originalURL, ext)
        }
        guard !targets.isEmpty else { return }

        Task { [weak self] in
            for target in targets {
                let metadata: ComicMetadata?
                switch target.ext {
                case "cbz": metadata = try? await CBZReader().extractComicInfo(from: target.url)
                case "cbr": metadata = try? await CBRReader().extractComicInfo(from: target.url)
                default: metadata = nil
                }
                if let metadata {
                    self?.applyEmbeddedMetadata(metadata, to: target.id)
                }
            }
        }
    }

    private func applyEmbeddedMetadata(_ m: ComicMetadata, to id: UUID) {
        guard let index = stagedComics.firstIndex(where: { $0.id == id }) else { return }
        var comic = stagedComics[index]

        // Fill only the fields the filename parse left empty — user edits and
        // confident filename results are never overwritten.
        if comic.series.isEmpty, let series = m.series { comic.series = series }
        if comic.issueNumber == nil { comic.issueNumber = m.number }
        if comic.year == nil { comic.year = m.year }
        if comic.publisher == nil { comic.publisher = m.publisher }
        if comic.volume == nil { comic.volume = m.volume }
        if comic.title == nil { comic.title = m.title }
        if comic.writer == nil { comic.writer = m.writer }
        if comic.artist == nil { comic.artist = m.penciller }
        if comic.coverArtist == nil { comic.coverArtist = m.coverArtist }
        if comic.colorist == nil { comic.colorist = m.colorist }
        if comic.inker == nil { comic.inker = m.inker }
        if comic.editor == nil { comic.editor = m.editor }
        if comic.summary == nil { comic.summary = m.summary }

        // Embedded metadata may reveal the real format (e.g. an issue number
        // appeared, or a volume number for a collected edition)
        comic.bookFormat = Comic.BookFormat.detect(
            issueNumber: comic.issueNumber, volume: comic.volume,
            fileType: Comic.FileType(
                rawValue: comic.originalURL.pathExtension.lowercased()))

        // Re-evaluate confidence with the enriched fields
        comic.reevaluate(userEdited: false)

        stagedComics[index] = comic
    }

    // MARK: - Selection Actions

    func toggleCheck(for comicID: UUID) {
        if checkedComicIDs.contains(comicID) {
            checkedComicIDs.remove(comicID)
        } else {
            checkedComicIDs.insert(comicID)
        }
    }

    // MARK: - Metadata Updates

    /// Update metadata for a staged comic
    func updateMetadata(
        id: UUID, series: String, issue: String, year: Int, publisher: String, volume: Int?,
        bookFormat: Comic.BookFormat,
        title: String?, writer: String?, artist: String?, coverArtist: String?, colorist: String?,
        inker: String?, editor: String?, summary: String?
    ) {
        guard let index = stagedComics.firstIndex(where: { $0.id == id }) else { return }

        var comic = stagedComics[index]
        comic.series = series
        comic.issueNumber = issue.isEmpty ? nil : issue
        comic.year = year > 0 ? year : nil
        comic.publisher = publisher.isEmpty ? nil : publisher
        comic.volume = volume
        comic.bookFormat = bookFormat
        comic.title = title
        comic.writer = writer
        comic.artist = artist
        comic.coverArtist = coverArtist
        comic.colorist = colorist
        comic.inker = inker
        comic.editor = editor
        comic.summary = summary

        // Re-evaluate status with format-aware rules
        comic.reevaluate(userEdited: true)

        stagedComics[index] = comic
    }

    // MARK: - Bulk Edit

    /// Apply non-nil fields to all staged comics in `ids`, then re-evaluate
    /// their readiness. Used by the bulk-edit sheet on checked items.
    func bulkUpdate(ids: Set<UUID>, values: BulkEditValues) {
        for index in stagedComics.indices where ids.contains(stagedComics[index].id) {
            var comic = stagedComics[index]
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
            comic.reevaluate(userEdited: true)
            stagedComics[index] = comic
        }
        AppLog.organize.debug("[OrganizeViewModel] ✏️ Bulk-updated \(ids.count) staged comics")
    }

    /// Check or uncheck every staged comic (quick selection for bulk edit)
    func setAllChecked(_ checked: Bool) {
        checkedComicIDs = checked ? Set(stagedComics.map(\.id)) : []
    }

    // MARK: - Confirm / Commit

    /// Confirm match for a single staged comic: Rename file & Add to Library
    /// Note: We look up the CURRENT comic from stagedComics (not the passed-in parameter)
    /// because StagedComic is a struct — the parameter may be a stale copy from view init.
    func confirmMatch(_ comic: StagedComic) async {
        guard let index = stagedComics.firstIndex(where: { $0.id == comic.id }) else { return }

        // Use the CURRENT version from the array (reflects user edits via updateMetadata)
        let current = stagedComics[index]
        let originalURL = current.originalURL
        var finalURL = originalURL

        // 1. Rename file on disk to match the confirmed metadata.
        //    File I/O runs off the main thread — renaming dozens of staged
        //    files previously blocked the UI for the whole batch.
        let newFileName = current.proposedFileName
        if newFileName != originalURL.lastPathComponent {
            let renamedURL: URL? = await Task.detached(priority: .userInitiated) {
                let newURL = originalURL.deletingLastPathComponent()
                    .appendingPathComponent(newFileName)

                // Security-scoped access for rename (balanced start/stop)
                let accessingSource = originalURL.startAccessingSecurityScopedResource()
                let destFolderURL = newURL.deletingLastPathComponent()
                let accessingDest = destFolderURL.startAccessingSecurityScopedResource()

                defer {
                    if accessingSource { originalURL.stopAccessingSecurityScopedResource() }
                    if accessingDest { destFolderURL.stopAccessingSecurityScopedResource() }
                }

                do {
                    if !FileManager.default.fileExists(atPath: newURL.path) {
                        try FileManager.default.moveItem(at: originalURL, to: newURL)
                        return newURL
                    } else {
                        AppLog.organize.error("[OrganizeViewModel] ⚠️ Target file exists, skipping rename: \(newFileName)")
                        return nil
                    }
                } catch {
                    AppLog.organize.error("[OrganizeViewModel] ❌ Rename failed: \(error)")
                    return nil
                }
            }.value

            if let renamedURL {
                finalURL = renamedURL
                AppLog.organize.debug("[OrganizeViewModel] 📝 Renamed staged file: \(originalURL.lastPathComponent) → \(newFileName)")
            }
        }

        // 2. Import into Library using staged metadata directly
        //    This preserves the user-entered publisher/series and uses the
        //    original URL's security scope for file access.
        await libraryViewModel.importStagedComic(
            series: current.series,
            issueNumber: current.issueNumber,
            volume: current.volume,
            year: current.year,
            bookFormat: current.bookFormat,
            publisher: current.publisher,
            title: current.title,
            writer: current.writer,
            artist: current.artist,
            coverArtist: current.coverArtist,
            colorist: current.colorist,
            inker: current.inker,
            editor: current.editor,
            summary: current.summary,
            originalURL: originalURL,
            fileURL: finalURL
        )

        // 3. Auto-sort into home library (if enabled)
        let settings = AppSettings.load()
        if settings.autoSortIntoLibrary,
           let libraryRoot = SettingsViewModel().resolveHomeLibraryURL(),
           let importedComic = libraryViewModel.comics.first(where: {
               $0.fileName == current.proposedFileName
                   || $0.filePath == finalURL
           })
        {
            do {
                let movedComic = try await LibraryFileService.shared.moveToLibrary(
                    importedComic,
                    libraryRoot: libraryRoot,
                    database: DatabaseManager.shared
                )
                // Update in-memory library array
                if let idx = libraryViewModel.comics.firstIndex(where: { $0.id == movedComic.id }) {
                    libraryViewModel.comics[idx] = movedComic
                }
                // Show destination in UI
                let rootPath = libraryRoot.standardizedFileURL.path
                let destPath = movedComic.filePath.standardizedFileURL.path
                let rel = destPath.hasPrefix(rootPath)
                    ? String(destPath.dropFirst(rootPath.count + 1))
                    : destPath
                lastMoveDestination = (rel as NSString).deletingLastPathComponent
                await libraryViewModel.logActivity(.fileMoved, comic: movedComic, new: rel)
            } catch {
                AppLog.organize.error("[OrganizeViewModel] ⚠️ Auto-sort failed: \(error)")
                lastMoveDestination = nil
            }
        } else {
            lastMoveDestination = nil
        }

        // 3. LEARN from this confirmation:
        //    - remember the series → publisher/format association
        //    - if the user corrected what the filename parse produced, store
        //      the original as an alias so next time it matches automatically
        let originalParse = MetadataParser.parseFromFilename(current.originalFileName)
        SeriesKnowledge.shared.recordImport(
            series: current.series,
            publisher: current.publisher,
            bookFormat: current.bookFormat
        )
        SeriesKnowledge.shared.recordCorrection(
            originalSeries: originalParse.series,
            correctedSeries: current.series,
            originalPublisher: originalParse.publisher,
            correctedPublisher: current.publisher,
            filename: current.originalFileName
        )

        // 4. Remove from staging
        if let idx = stagedComics.firstIndex(where: { $0.id == current.id }) {
            stagedComics.remove(at: idx)
        }

        // 4. Select next available
        if let next = stagedComics.first {
            selectedComicID = next.id
        } else {
            selectedComicID = nil
        }
    }

    /// Number of staged comics currently ready to apply.
    var readyCount: Int {
        stagedComics.filter { $0.status == .ready }.count
    }

    /// User folders for the "place into a folder" prompt, sorted alphabetically.
    var availableFolders: [Folder] {
        libraryViewModel.folders.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Confirm all comics with "Ready" status at once, with batch progress.
    /// Optionally files every newly imported book into a folder.
    func confirmAllReady(folderChoice: ImportFolderChoice = .none) async {
        let readyComics = stagedComics.filter { $0.status == .ready }
        guard !readyComics.isEmpty else { return }

        // Snapshot existing library IDs so we can tell which books are new.
        let beforeIDs = Set(libraryViewModel.comics.map(\.id))

        isProcessing = true
        processingProgress = 0.0

        for (index, comic) in readyComics.enumerated() {
            await confirmMatch(comic)
            processingProgress = Double(index + 1) / Double(readyComics.count)
        }

        isProcessing = false

        // Resolve the folder choice and file the newly imported books into it.
        let targetFolderID: UUID?
        switch folderChoice {
        case .none:
            targetFolderID = nil
        case .existing(let id):
            targetFolderID = id
        case .new(let name):
            targetFolderID = await libraryViewModel.createFolder(named: name)?.id
        }

        if let targetFolderID {
            let newIDs = libraryViewModel.comics.map(\.id).filter { !beforeIDs.contains($0) }
            await libraryViewModel.addComics(newIDs, toFolder: targetFolderID)
        }
    }
}
