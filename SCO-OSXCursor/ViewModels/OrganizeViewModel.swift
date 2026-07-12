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
    @Published var selectedComicID: UUID? {
        didSet {
            guard oldValue != selectedComicID else { return }
            loadCoverForSelection()
        }
    }
    @Published var checkedComicIDs: Set<UUID> = []

    // MARK: - Cover Preview (lazy, on-demand)

    /// Downsampled cover bytes for the currently selected staged comic.
    @Published private(set) var selectedCoverData: Data?
    @Published private(set) var isLoadingCover = false

    /// Cover bytes cached by staged-comic id (bounded; covers are small JPEGs).
    private let coverCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        // Large enough to hold a full staging batch of downsampled (~100 KB)
        // covers; NSCache still evicts under memory pressure.
        cache.countLimit = 400
        return cache
    }()
    private var coverTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?

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

        // Pre-extract covers in the background so selecting a file shows its
        // cover instantly instead of spinning behind the enrichment pass
        // (CBR/RAR extraction is too slow to run lazily during a big batch).
        warmCovers(for: newComics)
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

    /// Number of checked staged comics.
    var checkedCount: Int { checkedComicIDs.count }

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

    // MARK: - Cover Preview

    /// Load (or reuse a cached) cover for the selected staged comic. Extraction
    /// runs off the main thread, is cancelled when the selection changes, and
    /// is debounced so flying through the list with arrow keys doesn't thrash.
    func loadCoverForSelection() {
        coverTask?.cancel()
        guard let id = selectedComicID,
            let comic = stagedComics.first(where: { $0.id == id })
        else {
            selectedCoverData = nil
            isLoadingCover = false
            return
        }

        // Cache hit → show instantly.
        if let cached = coverCache.object(forKey: id.uuidString as NSString) {
            selectedCoverData = cached as Data
            isLoadingCover = false
            prefetchNeighbors(of: id)
            return
        }

        selectedCoverData = nil
        isLoadingCover = true
        let targetID = id
        let url = comic.originalURL
        coverTask = Task { [weak self] in
            // Debounce rapid selection changes.
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            // The background warm pass may have cached it during the debounce.
            if let self,
                let cached = self.coverCache.object(forKey: targetID.uuidString as NSString)
            {
                if self.selectedComicID == targetID {
                    self.selectedCoverData = cached as Data
                    self.isLoadingCover = false
                }
                self.prefetchNeighbors(of: targetID)
                return
            }
            let data = await OrganizeViewModel.extractCoverData(from: url)
            if Task.isCancelled { return }
            guard let self else { return }
            if let data {
                self.coverCache.setObject(data as NSData, forKey: targetID.uuidString as NSString)
            }
            if self.selectedComicID == targetID {
                self.selectedCoverData = data
                self.isLoadingCover = false
            }
            self.prefetchNeighbors(of: targetID)
        }
    }

    /// Pre-extract covers for a batch of newly staged comics (low priority,
    /// serial). Once cached, selecting an item shows its cover instantly —
    /// without this, lazy per-selection extraction competes with the embedded-
    /// metadata pass and CBR covers can spin until after import.
    private func warmCovers(for comics: [StagedComic]) {
        let work = comics.map { (id: $0.id, url: $0.originalURL) }
        Task(priority: .utility) { [weak self] in
            for item in work {
                guard let self, !Task.isCancelled else { return }
                // Still staged? (user may have cleared/imported the batch)
                guard self.stagedComics.contains(where: { $0.id == item.id }) else { continue }
                // Already cached, or being loaded right now by the selection task
                if self.coverCache.object(forKey: item.id.uuidString as NSString) != nil {
                    continue
                }
                if self.selectedComicID == item.id, self.isLoadingCover { continue }

                let data = await OrganizeViewModel.extractCoverData(from: item.url)
                guard let data else { continue }
                self.coverCache.setObject(data as NSData, forKey: item.id.uuidString as NSString)

                // If the user is currently looking at this file, show it.
                if self.selectedComicID == item.id, self.selectedCoverData == nil {
                    self.selectedCoverData = data
                    self.isLoadingCover = false
                }
            }
        }
    }

    /// Warm the covers for the items immediately before/after the selection so
    /// arrowing through the list feels instant.
    private func prefetchNeighbors(of id: UUID) {
        prefetchTask?.cancel()
        guard let idx = stagedComics.firstIndex(where: { $0.id == id }) else { return }
        let candidates =
            [idx + 1, idx - 1]
            .filter { $0 >= 0 && $0 < stagedComics.count }
            .map { stagedComics[$0] }
            .filter { coverCache.object(forKey: $0.id.uuidString as NSString) == nil }
        guard !candidates.isEmpty else { return }

        let work = candidates.map { (id: $0.id, url: $0.originalURL) }
        prefetchTask = Task { [weak self] in
            for item in work {
                if Task.isCancelled { return }
                let data = await OrganizeViewModel.extractCoverData(from: item.url)
                if Task.isCancelled { return }
                if let data {
                    self?.coverCache.setObject(
                        data as NSData, forKey: item.id.uuidString as NSString)
                }
            }
        }
    }

    /// Extract a small cover JPEG from a comic file. Runs off the main actor;
    /// returns Sendable `Data` so nothing non-Sendable crosses actor bounds.
    nonisolated static func extractCoverData(from url: URL) async -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let reader: ComicReaderProtocol
        switch url.pathExtension.lowercased() {
        case "pdf": reader = PDFReader()
        case "cbr": reader = CBRReader()
        case "epub": reader = EPUBReader()
        default: reader = CBZReader()
        }

        guard let raw = try? await reader.extractCover(from: url) else { return nil }
        // Downsample to a small JPEG (~800 px) for cheap transfer + display.
        return PageImageCache.storageCoverData(from: raw) ?? raw
    }

    // MARK: - ComicVine Fetch (staging)

    /// Outcome of a ComicVine fetch for a staged file. `.applied` carries the
    /// merged staged comic so the inspector can refresh its fields for review
    /// BEFORE the book is imported to the library.
    enum StagingCVOutcome {
        case applied(StagedComic)
        case needsChoice([CVCandidate])
        case noKey
        case noMatches
        case failed(String)
    }

    /// Search ComicVine for a staged file. A confident match is applied to the
    /// staged metadata immediately (nothing touches the library); an ambiguous
    /// search returns candidates for the user to pick from.
    func fetchComicVine(for id: UUID) async -> StagingCVOutcome {
        guard ComicVineConfig.hasKey else { return .noKey }
        guard let staged = stagedComics.first(where: { $0.id == id }) else {
            return .failed("File is no longer staged.")
        }

        let query =
            staged.series.isEmpty
            ? (staged.originalFileName as NSString).deletingPathExtension
            : staged.series

        do {
            let volumes = try await ComicVineService.shared.searchVolumes(query)
            guard !volumes.isEmpty else { return .noMatches }

            let proxy = cvProxy(for: staged)
            let scored = volumes
                .map { (volume: $0, score: ComicVineMatcher.score($0, against: proxy, query: query)) }
                .sorted { $0.score > $1.score }

            let best = scored[0]
            let second = scored.count > 1 ? scored[1].score : 0
            let confident = scored.count == 1 || (best.score >= 0.75 && best.score - second >= 0.2)

            guard confident else {
                let candidates = scored.prefix(5).map { item in
                    CVCandidate(
                        id: item.volume.id,
                        name: item.volume.name ?? "Unknown",
                        startYear: item.volume.startYear.flatMap { Int($0) },
                        publisher: item.volume.publisher?.name,
                        issueCount: item.volume.countOfIssues
                    )
                }
                return .needsChoice(Array(candidates))
            }

            let filled = await ComicVineFetcher.fill(proxy, from: best.volume)
            guard let merged = mergeCVResult(filled, into: id) else {
                return .failed("File is no longer staged.")
            }
            return .applied(merged)
        } catch {
            AppLog.organize.error("[OrganizeViewModel] ComicVine fetch failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// Routes a staged file to the right provider by its format: eBooks go
    /// to the book sources (Open Library / Google Books / Hardcover — no key
    /// needed), everything else to ComicVine.
    func fetchMetadata(for id: UUID) async -> StagingCVOutcome {
        if stagedComics.first(where: { $0.id == id })?.bookFormat == .ebook {
            return await fetchBookSources(for: id)
        }
        return await fetchComicVine(for: id)
    }

    /// Book-source fetch for a staged eBook. ISBN first (from the EPUB's own
    /// OPF metadata), then a fuzzy title/author search across every signed-in
    /// source; a confident best match is applied to the staged fields.
    func fetchBookSources(for id: UUID) async -> StagingCVOutcome {
        guard let staged = stagedComics.first(where: { $0.id == id }) else {
            return .failed("File is no longer staged.")
        }

        // Identity from the EPUB's embedded metadata when available.
        var embedded: ComicMetadata?
        if staged.originalURL.pathExtension.lowercased() == "epub" {
            embedded = try? EPUBReader().extractMetadata(from: staged.originalURL)
        }
        let isbn = embedded?.isbn
        let title = BookSearchTitle.clean(
            embedded?.title
                ?? (staged.title?.isEmpty == false ? staged.title! : nil)
                ?? (staged.series.isEmpty ? nil : staged.series)
                ?? (staged.originalFileName as NSString).deletingPathExtension)
        let author = embedded?.writer ?? staged.writer

        let proxy = cvProxy(for: staged)

        /// Fill-only-when-missing merge (title replaces — it's canonical).
        func filled(
            title: String?, authors: String?, publisher: String?,
            summary: String?, year: Int?
        ) -> Comic {
            var c = proxy
            if let title, !title.isEmpty { c.title = title }
            if c.writer?.isEmpty != false, let authors, !authors.isEmpty { c.writer = authors }
            if c.publisher?.isEmpty != false, let publisher, !publisher.isEmpty {
                c.publisher = publisher
            }
            if c.summary?.isEmpty != false, let summary, !summary.isEmpty { c.summary = summary }
            if c.year == nil { c.year = year }
            return c
        }

        func applied(_ comic: Comic) -> StagingCVOutcome {
            guard let merged = mergeCVResult(comic, into: id) else {
                return .failed("File is no longer staged.")
            }
            return .applied(merged)
        }

        // 1. Exact ISBN, source by source.
        if let isbn {
            if let doc = try? await OpenLibraryService.shared.lookupByISBN(isbn) {
                var description: String?
                if let key = doc.key {
                    description = (try? await OpenLibraryService.shared.work(key: key))?.description
                }
                return applied(
                    filled(
                        title: doc.title,
                        authors: doc.author_name?.joined(separator: ", "),
                        publisher: doc.publisher?.first,
                        summary: description,
                        year: doc.first_publish_year))
            }
            if let info = try? await GoogleBooksService.shared.lookupByISBN(isbn) {
                return applied(
                    filled(
                        title: info.title, authors: info.authors?.joined(separator: ", "),
                        publisher: info.publisher, summary: info.description, year: info.year))
            }
            if HardcoverConfig.hasToken,
                let doc = try? await HardcoverService.shared.lookupByISBN(isbn)
            {
                return applied(
                    filled(
                        title: doc.title, authors: doc.authorNames.joined(separator: ", "),
                        publisher: nil, summary: doc.description, year: doc.releaseYear))
            }
        }

        // 2. Fuzzy title/author across the signed-in sources, ranked together.
        guard !title.isEmpty else { return .noMatches }
        var best: (comic: Comic, score: Double)?
        func consider(_ names: [String]?, _ baseScore: Double, _ make: () -> Comic) {
            var score = baseScore
            if let author, let names,
                names.contains(where: { ComicVineMatcher.nameSimilarity(author, $0) > 0.8 })
            {
                score = min(1.0, score + 0.1)
            }
            if best == nil || score > best!.score {
                best = (make(), score)
            }
        }

        if let docs = try? await OpenLibraryService.shared.search(title: title, author: author) {
            for doc in docs {
                guard let t = doc.title else { continue }
                consider(doc.author_name, ComicVineMatcher.nameSimilarity(title, t)) {
                    filled(
                        title: t, authors: doc.author_name?.joined(separator: ", "),
                        publisher: doc.publisher?.first, summary: nil,
                        year: doc.first_publish_year)
                }
            }
        }
        if let volumes = try? await GoogleBooksService.shared.search(title: title, author: author) {
            for info in volumes {
                guard let t = info.title else { continue }
                consider(info.authors, ComicVineMatcher.nameSimilarity(title, t)) {
                    filled(
                        title: t, authors: info.authors?.joined(separator: ", "),
                        publisher: info.publisher, summary: info.description, year: info.year)
                }
            }
        }
        if HardcoverConfig.hasToken,
            let docs = try? await HardcoverService.shared.search(title: title, author: author)
        {
            for doc in docs {
                guard let t = doc.title else { continue }
                consider(doc.authorNames, ComicVineMatcher.nameSimilarity(title, t)) {
                    filled(
                        title: t, authors: doc.authorNames.joined(separator: ", "),
                        publisher: nil, summary: doc.description, year: doc.releaseYear)
                }
            }
        }

        guard let winner = best, winner.score >= 0.7 else { return .noMatches }
        return applied(winner.comic)
    }

    // Batch fetch (checked items)
    @Published private(set) var isBatchFetchingCV = false
    @Published private(set) var batchCVDone = 0
    @Published private(set) var batchCVTotal = 0
    @Published var batchCVSummary: String?
    /// Bumped when staged metadata changes outside the inspector's own edits
    /// (e.g. a batch fetch) so the inspector rebuilds with the new values.
    @Published private(set) var metadataRevision = 0

    /// Fetch metadata for every CHECKED staged file, routed by format:
    /// eBooks use the book sources, everything else uses ComicVine.
    /// Confident matches are applied to the staged metadata; ambiguous ones
    /// are left untouched for the per-file Fetch button.
    func fetchComicVineForChecked() async {
        guard !isBatchFetchingCV else { return }
        let items = stagedComics.filter { checkedComicIDs.contains($0.id) }
        guard !items.isEmpty else { return }

        // Only block outright when EVERY checked file would need the
        // (missing) ComicVine key — eBooks fetch without one.
        let comicsNeedKey = items.contains { $0.bookFormat != .ebook }
        if comicsNeedKey, !ComicVineConfig.hasKey, items.allSatisfy({ $0.bookFormat != .ebook }) {
            batchCVSummary = "Add a ComicVine API key in Settings first."
            return
        }

        isBatchFetchingCV = true
        batchCVSummary = nil
        batchCVDone = 0
        batchCVTotal = items.count

        var applied = 0
        var ambiguous = 0
        var noMatch = 0
        var failed = 0
        var noKey = 0
        for item in items {
            switch await fetchMetadata(for: item.id) {
            case .applied: applied += 1
            case .needsChoice: ambiguous += 1
            case .noMatches: noMatch += 1
            case .noKey: noKey += 1
            case .failed: failed += 1
            }
            batchCVDone += 1
        }

        metadataRevision += 1  // Refresh the inspector with fetched values
        isBatchFetchingCV = false

        var parts: [String] = []
        if applied > 0 { parts.append("\(applied) updated") }
        if ambiguous > 0 { parts.append("\(ambiguous) ambiguous — fetch individually to pick a match") }
        if noMatch > 0 { parts.append("\(noMatch) no match") }
        if failed > 0 { parts.append("\(failed) failed") }
        if noKey > 0 { parts.append("\(noKey) skipped (comics need a ComicVine key)") }
        batchCVSummary = parts.isEmpty ? "Nothing fetched." : parts.joined(separator: ", ") + "."
    }

    /// Apply a candidate the user picked from the staging match sheet.
    func applyComicVineCandidate(_ candidate: CVCandidate, to id: UUID) async -> StagingCVOutcome {
        guard let staged = stagedComics.first(where: { $0.id == id }) else {
            return .failed("File is no longer staged.")
        }
        let volume = CVVolumeResult(
            id: candidate.id,
            name: candidate.name,
            startYear: candidate.startYear.map(String.init),
            publisher: CVPublisher(name: candidate.publisher),
            countOfIssues: candidate.issueCount
        )
        let filled = await ComicVineFetcher.fill(cvProxy(for: staged), from: volume)
        guard let merged = mergeCVResult(filled, into: id) else {
            return .failed("File is no longer staged.")
        }
        return .applied(merged)
    }

    /// Temporary `Comic` mirroring a staged file so the shared ComicVine
    /// scorer/filler can operate on it. Never persisted.
    private func cvProxy(for staged: StagedComic) -> Comic {
        Comic(
            filePath: staged.originalURL,
            fileName: staged.originalFileName,
            title: staged.title,
            publisher: staged.publisher,
            series: staged.series.isEmpty ? nil : staged.series,
            issueNumber: staged.issueNumber,
            volume: staged.volume,
            year: staged.year,
            bookFormat: staged.bookFormat,
            writer: staged.writer,
            artist: staged.artist,
            coverArtist: staged.coverArtist,
            colorist: staged.colorist,
            inker: staged.inker,
            editor: staged.editor,
            summary: staged.summary
        )
    }

    /// Copy fetched fields back onto the staged comic. `filled` preserved the
    /// user's existing values (fill-only-when-missing), so a straight copy is
    /// safe; series is canonical from ComicVine.
    private func mergeCVResult(_ filled: Comic, into id: UUID) -> StagedComic? {
        guard let index = stagedComics.firstIndex(where: { $0.id == id }) else { return nil }
        var comic = stagedComics[index]
        if let series = filled.series, !series.isEmpty { comic.series = series }
        comic.publisher = filled.publisher
        comic.year = filled.year
        comic.title = filled.title
        comic.writer = filled.writer
        comic.artist = filled.artist
        comic.coverArtist = filled.coverArtist
        comic.colorist = filled.colorist
        comic.inker = filled.inker
        comic.editor = filled.editor
        comic.summary = filled.summary
        comic.reevaluate(userEdited: false)
        stagedComics[index] = comic
        return comic
    }

    /// Import the currently checked staged comics (regardless of Ready state —
    /// the user picked them deliberately) and file them into a folder.
    func confirmChecked(folderChoice: ImportFolderChoice = .none) async {
        let checked = stagedComics.filter { checkedComicIDs.contains($0.id) && !$0.series.isEmpty }
        guard !checked.isEmpty else { return }

        let beforeIDs = Set(libraryViewModel.comics.map(\.id))

        isProcessing = true
        processingProgress = 0.0

        for (index, comic) in checked.enumerated() {
            await confirmMatch(comic)
            processingProgress = Double(index + 1) / Double(checked.count)
        }

        isProcessing = false
        checkedComicIDs.removeAll()

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
