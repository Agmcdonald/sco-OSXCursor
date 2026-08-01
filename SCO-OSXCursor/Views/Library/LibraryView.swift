//
//  LibraryView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//
//  Stage 4 split (June 2026): LibraryView is now a slim coordinator that
//  owns the browsing state and composes focused components:
//    LibraryModels            — view mode / sort / filters / query pipeline
//    LibraryHeaderView        — title row, search + toolbar, filter panel
//    LibrarySelectionBar      — selection-mode actions (in the header)
//    LibraryGridView          — cover grid with adjustable cover size
//    LibraryListView          — row list (+ ComicRowView)
//    LibraryPublisherBrowseView — publisher → series → issues hierarchy
//    LibraryEmptyStateView    — first-run / no-results states
//    ComicCellModifiers       — shared tap/context-menu/checkbox behavior
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
    import PhotosUI
#endif
import os

// Wrapper to make UUID work with .sheet(item:)
private struct ComicID: Identifiable {
    let id: UUID
}

/// What a "New Folder…" prompt should do once the folder is created.
private enum NewFolderContext {
    case empty            // just create the folder (folder bar "+")
    case comic(Comic)     // create, then add this single comic
    case selection        // create, then add the current selection
}

@MainActor
struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Binding var columnVisibility: NavigationSplitViewVisibility
    var onAddComicsOrganize: (() -> Void)?
    /// Routes dropped `.scobook` transfer packages into the shared receive
    /// flow (folder choice / duplicate check) instead of the plain comic
    /// importer, which doesn't understand the package format.
    @EnvironmentObject private var incomingTransferCoordinator: IncomingTransferCoordinator

    init(
        viewModel: LibraryViewModel,
        columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.all),
        onAddComicsOrganize: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self._columnVisibility = columnVisibility
        self.onAddComicsOrganize = onAddComicsOrganize
    }

    // MARK: - State

    @State private var searchText = ""
    /// True while the header search field has keyboard focus — used to keep
    /// the Space/Return "open reader" shortcuts from stealing keystrokes.
    @FocusState private var isSearchFieldFocused: Bool
    /// Focus target for the browse area so key presses still land in this
    /// view once the search field is blurred (e.g. after clicking a card).
    @FocusState private var isBrowseAreaFocused: Bool
    @State private var viewMode: LibraryViewMode = .grid
    @State private var hasLoaded = false
    @AppStorage("librarySortOption") private var sortOption: LibrarySortOption = .dateAdded
    /// User-adjustable cover width for the grid (slider in the header).
    @AppStorage("libraryCoverSize") private var coverSize: Double = LibraryCoverSize.default
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false
    @State private var isSelectionMode = false
    @State private var selectedComics: Set<Comic.ID> = []
    @State private var showingBulkEdit = false
    /// Anchor for shift-click / "Select Range to Here" range selection
    @State private var selectionAnchorID: Comic.ID?
    @State private var showingFilePicker = false
    @State private var isDropTargeted = false
    @State private var showingDeleteConfirmation = false
    /// Comics queued for the delete confirmation (single book or a selection).
    @State private var comicsPendingDelete: [Comic] = []
    @State private var editingComicID: ComicID?
    @State private var focusedComic: Comic?
    @State private var isInspectorPresented = false

    // MARK: Folders
    /// What the grid is scoped to: all books, unfiled, or one folder.
    @State private var scope: LibraryScope = .all
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var newFolderContext: NewFolderContext = .empty
    @State private var folderPendingRename: Folder?
    @State private var renameFolderName = ""
    /// Folder awaiting the three-option delete confirmation.
    @State private var folderPendingDelete: Folder?
    /// Folder awaiting a custom cover picture (drives the image file importer).
    @State private var folderPendingCoverPicture: Folder?
    @State private var showingFolderCoverPicker = false
    /// Folder whose representative book is being chosen (drives the picker sheet).
    @State private var folderPendingBookPick: Folder?
    @State private var folderPendingVerticalZoom: Folder?
    /// Folder whose books are being hand-reordered (drives the reorder sheet).
    @State private var folderPendingReorder: Folder?
    /// Nesting level shown in the Folders view (nil = top level).
    @State private var folderGridParent: Folder?
    /// Parent for the folder being created via the new-folder alert
    /// (nil = top level; captured when the alert is opened).
    @State private var newFolderParentID: UUID?
    #if os(iOS)
        /// Folder awaiting a cover from the Photos library (iPad/iPhone).
        @State private var folderPendingCoverPhoto: Folder?
        @State private var showingPhotoPicker = false
        @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    // Missing-file recovery (Locate File…)
    @State private var relinkComicID: ComicID?
    @State private var showingRelinkPicker = false
    // Import paused while the user decides on a home library folder
    @State private var showingHomeLibraryPrompt = false
    @State private var pendingImportURLs: [URL] = []

    // Mac → iPad transfer: books queued for "Send to Device…" packaging
    @State private var transferExportRequest: TransferExportRequest?

    // iPad: read-only Info panel presented as a half-sheet (macOS uses .inspector)
    #if os(iOS)
        @State private var infoSheetComicID: ComicID?
    #endif

    // ComicVine fetch (no-sheet single + batch)
    @State private var pendingPickerComicID: ComicID?
    @State private var comicVineStatus: String?
    @State private var isBatchFetching = false
    // Batch match review queue
    @State private var batchReviewIDs: [Comic.ID] = []
    @State private var showingBatchReview = false

    // MARK: - Derived Data

    /// Folder scope for the grid. Active searches deliberately span the whole
    /// library (we clear the folder when the user starts typing), so this is
    /// nil while searching.
    private var folderRestriction: Set<UUID>? {
        guard searchText.isEmpty else { return nil }
        switch scope {
        case .all:
            return nil
        case .unfiled:
            return viewModel.unfiledComicIDs()
        case .folder(let id):
            return viewModel.comicIDs(inFolder: id)
        }
    }

    var filteredAndSortedComics: [Comic] {
        LibraryQuery.apply(
            to: viewModel.comics,
            searchText: searchText,
            filters: filters,
            sort: sortOption,
            restrictTo: folderRestriction,
            folderOrderIndex: currentFolderOrderIndex
        )
    }

    /// Position lookup for the "Folder Order" sort — only meaningful while
    /// scoped to a folder.
    private var currentFolderOrderIndex: [UUID: Int]? {
        guard case let .folder(id) = scope,
            let ordered = viewModel.folderOrder[id]
        else { return nil }
        return Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })
    }

    var publisherGroups: [PublisherGroup] {
        LibraryQuery.publisherGroups(from: filteredAndSortedComics)
    }

    var publishers: [String] {
        Array(Set(viewModel.comics.compactMap { $0.publisher })).sorted()
    }

    var series: [String] {
        Array(Set(viewModel.comics.compactMap { $0.series })).sorted()
    }

    var years: [Int] {
        Array(Set(viewModel.comics.compactMap { $0.year })).sorted(by: >)
    }

    /// Folders sorted per the shared sort menu (folder view) — only the
    /// current nesting level (top level, or children of folderGridParent).
    var sortedFolders: [Folder] {
        LibraryQuery.sortFolders(
            viewModel.childFolders(of: folderGridParent?.id),
            by: sortOption,
            count: { viewModel.folderCount($0) }
        )
    }

    /// Up to four member comics for a folder card's cover collage.
    private func previewComics(in folderID: UUID) -> [Comic] {
        let ids = viewModel.comicIDs(inFolder: folderID)
        return
            viewModel.comics
            .filter { ids.contains($0.id) }
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(4)
            .map { $0 }
    }

    /// The book a folder has chosen to represent it, if any and still present.
    private func coverComic(for folder: Folder) -> Comic? {
        guard let id = folder.coverComicID else { return nil }
        return viewModel.comics.first(where: { $0.id == id })
    }

    /// Member comics of a folder (for the cover book picker), most-recent first.
    private func memberComics(in folderID: UUID) -> [Comic] {
        let ids = viewModel.comicIDs(inFolder: folderID)
        return
            viewModel.comics
            .filter { ids.contains($0.id) }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    // MARK: - Folder Grid (extracted)
    //
    // Built as its own property with named handlers: the previous inline
    // 28-argument call with multi-line closures made the compiler unable to
    // type-check the body "in reasonable time".

    private var folderGridView: some View {
        LibraryFolderGridView(
            folders: sortedFolders,
            count: viewModel.folderCount,
            previewComics: previewComics(in:),
            coverComic: coverComic(for:),
            coverSize: coverSize,
            totalCount: viewModel.comics.count,
            unfiledCount: viewModel.unfiledCount,
            unfiledPreview: unfiledPreviewComics(),
            onOpenAll: openAllScope,
            onOpenUnfiled: openUnfiledScope,
            onOpen: openFolderCard(_:),
            onRename: beginRenameFolder(_:),
            onDelete: { folderPendingDelete = $0 },
            onNewFolder: beginNewFolderAtCurrentLevel,
            onChoosePicture: beginChooseFolderPicture(_:),
            onChoosePhoto: beginChooseFolderPhoto(_:),
            onPickBook: { folderPendingBookPick = $0 },
            onResetCover: clearFolderCoverAction(_:),
            onSetReadingStyle: setFolderReadingStyleAction(_:_:),
            onSetVerticalZoom: { folderPendingVerticalZoom = $0 },
            parentFolder: folderGridParent,
            subfolderCount: viewModel.subfolderCount(_:),
            onOpenBooks: openFolderBooks(_:),
            onNewSubfolder: beginNewSubfolder(in:),
            moveTargets: folderMoveTargets(for:),
            onMove: moveFolderAction(_:_:),
            onBack: folderGridGoBack,
            onReorderBooks: { folderPendingReorder = $0 }
        )
    }

    private func openAllScope() {
        searchText = ""
        scope = .all
        viewMode = .grid
    }

    private func openUnfiledScope() {
        searchText = ""
        scope = .unfiled
        viewMode = .grid
    }

    /// Open a folder's books (scope the book grid to it).
    private func openFolderBooks(_ folder: Folder) {
        searchText = ""
        scope = .folder(folder.id)
        viewMode = .grid
    }

    /// Card tap: folders with children drill deeper in the Folders view;
    /// leaf folders open their books directly.
    private func openFolderCard(_ folder: Folder) {
        if viewModel.subfolderCount(folder.id) > 0 {
            folderGridParent = folder
        } else {
            openFolderBooks(folder)
        }
    }

    private func beginRenameFolder(_ folder: Folder) {
        folderPendingRename = folder
        renameFolderName = folder.name
    }

    private func beginNewFolderAtCurrentLevel() {
        newFolderContext = .empty
        newFolderParentID = folderGridParent?.id
        newFolderName = ""
        showingNewFolderAlert = true
    }

    private func beginNewSubfolder(in folder: Folder) {
        newFolderContext = .empty
        newFolderParentID = folder.id
        newFolderName = ""
        showingNewFolderAlert = true
    }

    private func beginChooseFolderPicture(_ folder: Folder) {
        folderPendingCoverPicture = folder
        showingFolderCoverPicker = true
    }

    private func beginChooseFolderPhoto(_ folder: Folder) {
        #if os(iOS)
            folderPendingCoverPhoto = folder
            showingPhotoPicker = true
        #endif
    }

    private func clearFolderCoverAction(_ folder: Folder) {
        Task { await viewModel.clearFolderCover(folder) }
    }

    private func setFolderReadingStyleAction(_ folder: Folder, _ style: ReadingStyle?) {
        Task { await viewModel.setFolderReadingStyle(folder, style: style) }
    }

    private func moveFolderAction(_ folder: Folder, _ newParentID: UUID?) {
        Task { await viewModel.moveFolder(folder, toParent: newParentID) }
    }

    /// Valid "Move To" destinations: anywhere except itself, its descendants,
    /// and its current parent (already there). Sorted by full path.
    private func folderMoveTargets(for folder: Folder) -> [Folder] {
        let blocked = viewModel.descendantIDs(of: folder.id)
        return viewModel.folders
            .filter {
                $0.id != folder.id && !blocked.contains($0.id) && $0.id != folder.parentID
            }
            .sorted {
                viewModel.folderPathName($0)
                    .localizedStandardCompare(viewModel.folderPathName($1)) == .orderedAscending
            }
    }

    /// Go up one level in the Folders view: to the parent's parent, or top.
    private func folderGridGoBack() {
        if let parent = folderGridParent, let grandParentID = parent.parentID {
            folderGridParent = viewModel.folders.first(where: { $0.id == grandParentID })
        } else {
            folderGridParent = nil
        }
    }

    /// Member books in the folder's manual order (hand-ordered first, then
    /// never-ordered by date added) — seed list for the reorder sheet.
    private func orderedMemberComics(in folderID: UUID) -> [Comic] {
        let members = memberComics(in: folderID)
        guard let ordered = viewModel.folderOrder[folderID] else { return members }
        let index = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })
        return members.sorted {
            let a = index[$0.id] ?? Int.max
            let b = index[$1.id] ?? Int.max
            if a != b { return a < b }
            return $0.dateAdded < $1.dateAdded
        }
    }

    /// Up to four unfiled comics for the "Unfiled" card's collage.
    private func unfiledPreviewComics() -> [Comic] {
        let ids = viewModel.unfiledComicIDs()
        return
            viewModel.comics
            .filter { ids.contains($0.id) }
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(4)
            .map { $0 }
    }

    /// Display name of the current scope (for the subtitle); nil for All Books.
    private var scopeName: String? {
        switch scope {
        case .all:
            return nil
        case .unfiled:
            return "Unfiled"
        case .folder(let id):
            return viewModel.folders.first(where: { $0.id == id })?.name
        }
    }

    /// The folder the library is scoped to — drives the direct
    /// "Remove from '<name>'" shortcuts. nil for All Books / Unfiled.
    private var currentScopeFolder: Folder? {
        guard case .folder(let id) = scope else { return nil }
        return viewModel.folders.first(where: { $0.id == id })
    }

    /// Closures handed to every comic cell (grid, list, publisher grids).
    private var cellActions: ComicCellActions {
        ComicCellActions(
            openReader: { openReader(for: $0) },
            editComic: { editComic($0) },
            markAsRead: { viewModel.markAsRead([$0]) },
            toggleReadingList: { viewModel.toggleReadingList($0) },
            regenerateCover: { viewModel.regenerateCovers(for: [$0]) },
            delete: { requestDelete([$0]) },
            selectRange: { selectRange(to: $0) },
            handleSelectionTap: { handleSelectionTap($0) },
            focus: { focusedComic = $0 },
            fetchMetadata: { fetchMetadataSingle($0) },
            revertMetadataFetch: { revertMetadataSingle($0) },
            markAsUnread: { viewModel.markAsUnread([$0]) },
            showInfo: { comic in
                #if os(macOS)
                    focusedComic = comic
                    isInspectorPresented = true
                #else
                    infoSheetComicID = ComicID(id: comic.id)
                #endif
            },
            relink: { comic in
                relinkComicID = ComicID(id: comic.id)
                showingRelinkPicker = true
            },
            sendToDevice: { comic in
                transferExportRequest = TransferExportRequest(comics: [comic])
            },
            togglePDFReadAsBook: { comic in
                var updated = comic
                updated.pdfReadsAsBook.toggle()
                updated.dateModified = Date()
                viewModel.updateComic(updated)
            },
            folders: viewModel.folders,
            folderDisplayName: { viewModel.folderPathName($0) },
            foldersContaining: { viewModel.folders(containing: $0.id) },
            addToFolder: { comic, folderID in
                Task { await viewModel.addComics([comic.id], toFolder: folderID) }
            },
            removeFromFolder: { comic, folderID in
                Task { await viewModel.removeComics([comic.id], fromFolder: folderID) }
            },
            addSelectionToFolder: { folderID in
                let ids = Array(selectedComics)
                Task {
                    await viewModel.addComics(ids, toFolder: folderID)
                    selectedComics.removeAll()
                    isSelectionMode = false
                }
            },
            removeSelectionFromFolder: { folderID in
                let ids = Array(selectedComics)
                Task {
                    await viewModel.removeComics(ids, fromFolder: folderID)
                    selectedComics.removeAll()
                    isSelectionMode = false
                }
            },
            foldersContainingSelection: { viewModel.folders(containingAnyOf: selectedComics) },
            currentFolder: currentScopeFolder,
            requestNewFolderForComic: { comic in
                newFolderContext = .comic(comic)
                newFolderParentID = nil
                newFolderName = ""
                showingNewFolderAlert = true
            },
            requestNewFolderForSelection: {
                newFolderContext = .selection
                newFolderParentID = nil
                newFolderName = ""
                showingNewFolderAlert = true
            },
            revealInFolder: { folderID, comic in
                searchText = ""
                scope = .folder(folderID)
                // Highlight the book where it lives — the grid/list scrolls
                // to the focused comic once the new scope's list contains it.
                focusedComic = comic
            },
            selectBook: { comic in
                isSelectionMode = true
                selectedComics.insert(comic.id)
            }
        )
    }

    private var emptyState: LibraryEmptyStateView {
        LibraryEmptyStateView(
            isLibraryEmpty: viewModel.comics.isEmpty,
            canClearFilters: filters.hasActive || !searchText.isEmpty,
            onAddComics: { showingFilePicker = true },
            onClearFilters: {
                filters.clear()
                searchText = ""
            }
        )
    }

    // MARK: - Body

    var body: some View {
        withRemainingChrome
    }

    /// Stage 1 of the body: the browse layout (header, scope bar, grid/list/
    /// publisher/folder views) plus frame, drop targets, and file importers.
    private var browseLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            LibraryHeaderView(
                viewMode: $viewMode,
                searchText: $searchText,
                searchFieldFocus: $isSearchFieldFocused,
                sortOption: $sortOption,
                filters: $filters,
                showingFilters: $showingFilters,
                coverSize: $coverSize,
                isSelectionMode: $isSelectionMode,
                selectedComics: $selectedComics,
                isInspectorPresented: $isInspectorPresented,
                hasFocusedComic: focusedComic != nil,
                visibleComicIDs: filteredAndSortedComics.map(\.id),
                visibleComicsCount: filteredAndSortedComics.count,
                publisherCount: viewMode == .publisher ? publisherGroups.count : 0,
                publishers: publishers,
                series: series,
                years: years,
                currentFolderName: scopeName,
                totalLibraryCount: viewModel.comics.count,
                folderViewCount: viewModel.folders.count,
                onQuickAdd: { showingFilePicker = true },
                onAddComicsOrganize: onAddComicsOrganize,
                onMarkAsRead: markAsReadSelectedComics,
                onMarkAsUnread: markAsUnreadSelectedComics,
                onEditFields: { showingBulkEdit = true },
                onAddToList: addSelectedToReadingList,
                onRegenerateCovers: regenerateCoversForSelected,
                onFetchMetadata: fetchMetadataForSelected,
                onDelete: {
                    requestDelete(viewModel.comics.filter { selectedComics.contains($0.id) })
                },
                isFetchingMetadata: isBatchFetching,
                folders: viewModel.folders,
                onAddToFolder: { folderID in
                    let ids = Array(selectedComics)
                    Task {
                        await viewModel.addComics(ids, toFolder: folderID)
                        selectedComics.removeAll()
                        isSelectionMode = false
                    }
                },
                onNewFolderForSelection: {
                    newFolderContext = .selection
                    newFolderParentID = nil
                    newFolderName = ""
                    showingNewFolderAlert = true
                },
                removalFoldersForSelection: {
                    viewModel.folders(containingAnyOf: selectedComics)
                },
                onRemoveFromFolder: { folderID in
                    let ids = Array(selectedComics)
                    Task {
                        await viewModel.removeComics(ids, fromFolder: folderID)
                        selectedComics.removeAll()
                        isSelectionMode = false
                    }
                },
                onSendToDevice: {
                    let selected = viewModel.comics.filter { selectedComics.contains($0.id) }
                    guard !selected.isEmpty else { return }
                    transferExportRequest = TransferExportRequest(comics: selected)
                }
            )

            Divider()
                .background(BorderColors.subtle)

            // Folder scope bar (hidden in folder view — the cards are the bar)
            if viewMode != .folders {
                FolderBarView(
                    folders: viewModel.folders,
                    scope: $scope,
                    folderCount: { viewModel.folderCount($0) },
                    totalCount: viewModel.comics.count,
                    unfiledCount: viewModel.unfiledCount,
                    onNewFolder: {
                        newFolderContext = .empty
                        newFolderParentID = nil
                        newFolderName = ""
                        showingNewFolderAlert = true
                    },
                    folderPathName: { viewModel.folderPathName($0) }
                )

                Divider()
                    .background(BorderColors.subtle)
            }

            // Content
            // Focusable so keyboard events (Space/Return open reader) still
            // have a landing spot once the search field gives up focus.
            Group {
                switch viewMode {
                case .grid:
                LibraryGridView(
                    comics: filteredAndSortedComics,
                    isSelectionMode: isSelectionMode,
                    selectedComics: selectedComics,
                    focusedComicID: focusedComic?.id,
                    coverSize: coverSize,
                    actions: cellActions,
                    emptyState: emptyState,
                    showsFolderBadges: !searchText.isEmpty
                )
                .modifier(FileDropTarget(isTargeted: $isDropTargeted, onDrop: handleDrop))
            case .list:
                LibraryListView(
                    comics: filteredAndSortedComics,
                    isSelectionMode: isSelectionMode,
                    selectedComics: selectedComics,
                    focusedComicID: focusedComic?.id,
                    actions: cellActions,
                    emptyState: emptyState,
                    showsFolderBadges: !searchText.isEmpty
                )
                .modifier(FileDropTarget(isTargeted: $isDropTargeted, onDrop: handleDrop))
            case .publisher:
                LibraryPublisherBrowseView(
                    publisherGroups: publisherGroups,
                    isSelectionMode: isSelectionMode,
                    selectedComics: selectedComics,
                    focusedComicID: focusedComic?.id,
                    // Inline series grids read better slightly smaller than
                    // the main grid (they're nested under a header row).
                    coverSize: coverSize * 0.8,
                    actions: cellActions,
                    emptyState: emptyState
                )
            case .folders:
                folderGridView
                }
            }
            // Focusable so keyboard events (Space/Return open reader) still
            // have a landing spot once the search field gives up focus.
            .focusable()
            .focusEffectDisabled()
            .focused($isBrowseAreaFocused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BackgroundColors.primary)
        .overlay(
            // Import progress overlay
            Group {
                if viewModel.isImporting {
                    importProgressOverlay
                }
            }
        )
        // NOTE: SwiftUI only honors ONE .fileImporter per view. Chaining
        // several on the same view silently breaks all but one (this is what
        // broke Quick Add when the folder-cover picker was added). Each
        // importer therefore lives on its own invisible background view.
        .background(
            Color.clear.fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [
                    .folder, .zip, .pdf, .cbr, .epub, UTType(filenameExtension: "cbr")!,
                    UTType(filenameExtension: "epub") ?? .data,
                ],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
        )
        // Offer to set a home library before the first sorted import
        .modifier(
            HomeLibrarySetupPrompt(
                isPresented: $showingHomeLibraryPrompt,
                pendingURLs: $pendingImportURLs,
                onImport: { urls in
                    Task { await viewModel.importComics(from: urls) }
                }
            )
        )
        // Locate File… — re-link a single missing/moved book
        .background(
            Color.clear.fileImporter(
                isPresented: $showingRelinkPicker,
                allowedContentTypes: [
                    .zip, .pdf, .cbr, .epub,
                    UTType(filenameExtension: "cbz") ?? .data,
                ],
                allowsMultipleSelection: false
            ) { result in
                handleRelink(result)
            }
        )
        // Choose a custom cover picture for a folder
        .background(
            Color.clear.fileImporter(
                isPresented: $showingFolderCoverPicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleFolderCoverImport(result)
            }
        )
        // iPad/iPhone: choose a folder cover from the Photos library.
        // Isolated in a ViewModifier so the main body stays type-checkable.
        #if os(iOS)
            .modifier(
                FolderCoverPhotoPickerModifier(
                    isPresented: $showingPhotoPicker,
                    selection: $selectedPhotoItem,
                    onPick: { handleFolderCoverPhoto($0) }
                )
            )
        #endif
    }

    /// Stage 2 of the body: folder-related sheets, alerts, and dialogs.
    /// (The body is split into stages — one giant modifier chain stopped
    /// type-checking in reasonable time.)
    private var withFolderSheets: some View {
        browseLayout
        // Pick a single member book to represent a folder
        .sheet(
            isPresented: Binding(
                get: { folderPendingBookPick != nil },
                set: { if !$0 { folderPendingBookPick = nil } }
            )
        ) {
            if let folder = folderPendingBookPick {
                FolderCoverBookPicker(
                    folderName: folder.name,
                    books: memberComics(in: folder.id),
                    selectedID: folder.coverComicID,
                    onSelect: { comic in
                        Task { await viewModel.setFolderCover(folder, comicID: comic.id) }
                        folderPendingBookPick = nil
                    },
                    onCancel: { folderPendingBookPick = nil }
                )
            }
        }
        // Hand-arrange the reading order of a folder's books
        .sheet(item: $folderPendingReorder) { folder in
            FolderReorderSheet(
                folderName: folder.name,
                books: orderedMemberComics(in: folder.id),
                onSave: { orderedIDs in
                    Task { await viewModel.setFolderOrder(folder.id, orderedComicIDs: orderedIDs) }
                    // Make the result visible: viewing this folder with the
                    // Folder Order sort shows the arrangement just saved.
                    sortOption = .folderOrder
                },
                onCancel: {}
            )
        }
        // Folder-level vertical-scroll zoom, previewed with a member book.
        // Item-based sheet: content always has a real folder, and dismissal
        // clears the item automatically (isPresented + inner `if let` left the
        // Cancel path flaky on iPhone).
        .sheet(item: $folderPendingVerticalZoom) { folder in
            let sample = memberComics(in: folder.id).first(where: { $0.coverImageData != nil })
            FolderVerticalZoomSheet(
                folderName: folder.name,
                sampleImageData: sample?.coverImageData,
                sampleCacheKey: sample?.id.uuidString ?? "folder-zoom-sample",
                initialZoom: folder.verticalZoomScale,
                onSave: { zoom in
                    Task { await viewModel.setFolderVerticalZoom(folder, zoom: zoom) }
                },
                onCancel: {}
            )
        }
        .sheet(isPresented: $showingBulkEdit) {
            BulkEditSheet(itemCount: selectedComics.count) { values in
                viewModel.bulkEdit(ids: selectedComics, values: values)
                isSelectionMode = false
                selectedComics.removeAll()
            }
        }
        // Mac → iPad transfer: package the book(s) then hand to the share sheet
        .sheet(item: $transferExportRequest) { request in
            TransferExportSheet(comics: request.comics) {
                transferExportRequest = nil
                if isSelectionMode {
                    selectedComics.removeAll()
                    isSelectionMode = false
                }
            }
        }
        .alert("Delete from Library", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { comicsPendingDelete = [] }
            Button("Delete", role: .destructive) {
                performPendingDelete()
            }
        } message: {
            if comicsPendingDelete.count == 1, let comic = comicsPendingDelete.first {
                Text(
                    "Remove “\(comic.displayName)” from your library? The file on your drive is not deleted."
                )
            } else {
                Text(
                    "Remove \(comicsPendingDelete.count) comics from your library? The files on your drive are not deleted."
                )
            }
        }
        // New folder prompt (folder bar "+", or "New Folder…" from a menu)
        .alert("New Folder", isPresented: $showingNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { createFolderFromAlert() }
        } message: {
            Text("Name your new folder.")
        }
        // Rename folder prompt
        .alert(
            "Rename Folder",
            isPresented: Binding(
                get: { folderPendingRename != nil },
                set: { if !$0 { folderPendingRename = nil } }
            )
        ) {
            TextField("Folder name", text: $renameFolderName)
            Button("Cancel", role: .cancel) { folderPendingRename = nil }
            Button("Save") {
                if let folder = folderPendingRename {
                    let newName = renameFolderName
                    Task { await viewModel.renameFolder(folder, to: newName) }
                }
                folderPendingRename = nil
            }
        }
        // Three-option folder delete
        .confirmationDialog(
            folderPendingDelete.map { "Delete “\($0.name)”?" } ?? "Delete Folder?",
            isPresented: Binding(
                get: { folderPendingDelete != nil },
                set: { if !$0 { folderPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: folderPendingDelete
        ) { folder in
            deleteFolderButtons(for: folder)
        } message: { folder in
            let n = viewModel.folderCount(folder.id)
            if n == 0 {
                Text("This folder is empty — deleting it won't affect any books.")
            } else {
                Text(
                    "“\(folder.name)” contains \(n) book\(n == 1 ? "" : "s"). Choose what to remove. Deleting files from your device cannot be undone."
                )
            }
        }
    }

    /// Stage 3 of the body: remaining sheets, overlays, and state observers.
    private var withRemainingChrome: some View {
        withFolderSheets
        // iPad: read-only Info panel (long-press → Show Info). macOS uses the
        // side inspector; this half-sheet gives iPad the same metadata view.
        #if os(iOS)
        .sheet(item: $infoSheetComicID) { wrapper in
            if let comic = viewModel.comics.first(where: { $0.id == wrapper.id }) {
                ComicInspectorView(comic: comic) {
                    infoSheetComicID = nil
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        #endif
        // Searching deliberately spans the whole library — drop the folder
        // scope the moment the user starts typing so results aren't hidden.
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty && scope != .all {
                scope = .all
            }
        }
        .onAppear {
            // Only load once per view lifecycle — prevents re-fetch flash when
            // returning from the reader overlay or switching tabs.
            guard !hasLoaded else { return }
            hasLoaded = true
            if viewModel.comics.isEmpty {
                Task {
                    await viewModel.loadComics()
                }
            }
        }
        .sheet(item: $editingComicID) { comicIDWrapper in
            if let comic = viewModel.comics.first(where: { $0.id == comicIDWrapper.id }) {
                ComicDetailView(comic: comic) { updatedComic in
                    viewModel.updateComic(updatedComic)
                }
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.editingComicIDs.insert(comicIDWrapper.id)
                }
                .onDisappear {
                    viewModel.editingComicIDs.remove(comicIDWrapper.id)
                }
            } else {
                // Fallback view if comic can't be found
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(TextColors.tertiary)
                    Text("Could not load comic for editing")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                    Button("Close") {
                        editingComicID = nil
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 400, height: 200)
                .padding()
            }
        }
        // Match picker for an ambiguous no-sheet fetch (source by file type)
        .sheet(item: $pendingPickerComicID) { wrapper in
            if let comic = viewModel.comics.first(where: { $0.id == wrapper.id }) {
                if comic.isEbook {
                    OpenLibraryMatchPicker(comic: comic, viewModel: viewModel)
                } else {
                    ComicVineMatchPicker(comic: comic, viewModel: viewModel)
                }
            }
        }
        // Batch match review queue (after a multi-book fetch)
        .sheet(isPresented: $showingBatchReview) {
            ComicVineBatchReviewView(comicIDs: batchReviewIDs, viewModel: viewModel)
        }
        // Transient ComicVine fetch status (auto-dismisses)
        .overlay(alignment: .bottom) {
            if let status = comicVineStatus {
                Text(status)
                    .font(Typography.bodySmall)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.bottom, Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: focusedComic) { oldValue, newValue in
            // Selection alone no longer opens the inspector —
            // the user must tap the Info (ⓘ) button explicitly.
            //
            // When the user focuses a *different* comic (e.g. clicks a card),
            // release keyboard focus from the search field so the Space/Return
            // "open reader" shortcuts work again. Guarded by an ID comparison
            // so refreshes of the same comic don't blur the field mid-search.
            if let newValue, oldValue?.id != newValue.id {
                isSearchFieldFocused = false
                isBrowseAreaFocused = true
            }
        }
        .onChange(of: viewModel.comics) { _, newComics in
            if let focused = focusedComic,
                let updated = newComics.first(where: { $0.id == focused.id })
            {
                // Must update focusedComic because Comic's Equatable only checks ID
                focusedComic = updated
            }
        }
        .onChange(of: viewModel.folders) { _, newFolders in
            // Keep the Folders-view nesting level valid: refresh the parent
            // copy after edits, and pop to top if it was deleted.
            if let parent = folderGridParent {
                folderGridParent = newFolders.first(where: { $0.id == parent.id })
            }
        }
        .onChange(of: isInspectorPresented) { _, newValue in
            if !newValue {
                // Inspector closed — restore sidebar but keep the comic focused
                // so the user can re-summon the inspector without re-clicking.
                columnVisibility = .all
            } else {
                // Inspector opening — collapse left sidebar for more room
                columnVisibility = .detailOnly
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            if let comic = focusedComic {
                ComicInspectorView(
                    comic: comic,
                    onDismiss: {
                        isInspectorPresented = false
                    }
                )
                .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
            } else {
                Text("No Comic Selected")
                    .foregroundColor(TextColors.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BackgroundColors.secondary)
            }
        }
        .onKeyPress(.space) {
            // Only act when no sheet / overlay / text field is capturing keyboard input
            guard editingComicID == nil, !showingFilters, !isSearchFieldFocused else { return .ignored }
            if let comic = focusedComic, !isSelectionMode {
                openReader(for: comic)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            guard editingComicID == nil, !showingFilters, !isSearchFieldFocused else { return .ignored }
            if let comic = focusedComic, !isSelectionMode {
                openReader(for: comic)
                return .handled
            }
            return .ignored
        }
        // ⌘E → edit metadata, ⌘I → info panel for the highlighted book
        .onKeyPress(phases: .down) { press in
            guard editingComicID == nil, !showingFilters, !isSearchFieldFocused else {
                return .ignored
            }
            guard press.modifiers.contains(.command), let comic = focusedComic else {
                return .ignored
            }
            switch press.characters.lowercased() {
            case "e":
                editComic(comic)
                return .handled
            case "i":
                #if os(macOS)
                    isInspectorPresented.toggle()
                #else
                    infoSheetComicID = ComicID(id: comic.id)
                #endif
                return .handled
            default:
                return .ignored
            }
        }
    }

    // MARK: - Import Progress Overlay

    private var importProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                ProgressView(value: viewModel.importProgress) {
                    Text("Importing Comics...")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                }
                .progressViewStyle(.linear)
                .tint(AccentColors.primary)
                .frame(width: 300)

                Text("\(Int(viewModel.importProgress * 100))%")
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)
            }
            .padding(Spacing.xxl)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }

    // MARK: - Relink Helper

    private func handleRelink(_ result: Result<[URL], Error>) {
        defer { relinkComicID = nil }
        guard case .success(let urls) = result, let url = urls.first,
            let wrapper = relinkComicID,
            let comic = viewModel.comics.first(where: { $0.id == wrapper.id })
        else { return }
        Task { await viewModel.relinkComic(comic, to: url) }
    }

    /// Read the picked image file and assign it as the folder's custom cover.
    private func handleFolderCoverImport(_ result: Result<[URL], Error>) {
        let folder = folderPendingCoverPicture
        defer { folderPendingCoverPicture = nil }
        guard case .success(let urls) = result, let url = urls.first,
            let folder = folder
        else { return }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            AppLog.library.error("[LibraryView] ❌ Could not read folder cover image")
            return
        }
        Task { await viewModel.setFolderCover(folder, imageData: data) }
    }

    #if os(iOS)
        /// Load the chosen Photos-library item and assign it as the folder cover.
        private func handleFolderCoverPhoto(_ item: PhotosPickerItem) {
            let folder = folderPendingCoverPhoto
            folderPendingCoverPhoto = nil
            selectedPhotoItem = nil
            Task {
                guard let folder,
                    let data = (try? await item.loadTransferable(type: Data.self)) ?? nil
                else { return }
                await viewModel.setFolderCover(folder, imageData: data)
            }
        }
    #endif

    // MARK: - Folder Helpers

    /// Member comics of a folder, in library order.
    private func membersOf(_ folder: Folder) -> [Comic] {
        let ids = viewModel.comicIDs(inFolder: folder.id)
        return viewModel.comics.filter { ids.contains($0.id) }
    }

    /// The three destructive choices for deleting a folder.
    @ViewBuilder
    private func deleteFolderButtons(for folder: Folder) -> some View {
        let n = viewModel.folderCount(folder.id)

        Button("Delete Folder Only", role: .destructive) {
            if scope == .folder(folder.id) { scope = .all }
            Task { await viewModel.deleteFolder(folder) }
        }

        if n > 0 {
            Button(
                "Delete Folder & Remove \(n) Book\(n == 1 ? "" : "s") from App",
                role: .destructive
            ) {
                if scope == .folder(folder.id) { scope = .all }
                let members = membersOf(folder)
                Task {
                    await viewModel.deleteComicsFromApp(members)
                    await viewModel.deleteFolder(folder)
                }
            }

            Button(
                "Delete Folder & Delete \(n) File\(n == 1 ? "" : "s") from Device",
                role: .destructive
            ) {
                if scope == .folder(folder.id) { scope = .all }
                let members = membersOf(folder)
                Task {
                    await viewModel.deleteComicsFromDevice(members)
                    await viewModel.deleteFolder(folder)
                }
            }
        }

        Button("Cancel", role: .cancel) {}
    }

    /// Create the folder named in the new-folder alert, then apply whatever the
    /// prompt was for (nothing / a single comic / the current selection).
    private func createFolderFromAlert() {
        let context = newFolderContext
        let name = newFolderName
        let parentID = newFolderParentID
        newFolderParentID = nil
        Task {
            guard let folder = await viewModel.createFolder(named: name, parentID: parentID)
            else { return }
            switch context {
            case .empty:
                break
            case .comic(let comic):
                await viewModel.addComics([comic.id], toFolder: folder.id)
            case .selection:
                let ids = Array(selectedComics)
                await viewModel.addComics(ids, toFolder: folder.id)
                selectedComics.removeAll()
                isSelectionMode = false
            }
        }
    }

    // MARK: - Selection Helpers

    private func toggleSelection(for id: Comic.ID) {
        if selectedComics.contains(id) {
            selectedComics.remove(id)
        } else {
            selectedComics.insert(id)
        }
    }

    /// Selection-mode tap with shift-click range support (macOS).
    /// Plain click toggles and sets the anchor; shift-click selects everything
    /// between the anchor and the clicked book in the current display order.
    private func handleSelectionTap(_ comic: Comic) {
        #if os(macOS)
            if NSEvent.modifierFlags.contains(.shift) {
                selectRange(to: comic)
                return
            }
        #endif
        toggleSelection(for: comic.id)
        selectionAnchorID = comic.id
    }

    /// Select every book between the last anchor and `comic` (inclusive),
    /// in the current filter/sort order. Used by shift-click (macOS) and the
    /// "Select Range to Here" context-menu action (iPad).
    private func selectRange(to comic: Comic) {
        let ordered = filteredAndSortedComics
        guard let anchorID = selectionAnchorID,
            let anchorIndex = ordered.firstIndex(where: { $0.id == anchorID }),
            let targetIndex = ordered.firstIndex(where: { $0.id == comic.id })
        else {
            toggleSelection(for: comic.id)
            selectionAnchorID = comic.id
            return
        }
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedComics.formUnion(ordered[range].map(\.id))
        // Keep the anchor — repeated shift-clicks extend from the same origin
    }

    private func markAsReadSelectedComics() {
        let comicsToMark = viewModel.comics.filter { selectedComics.contains($0.id) }
        viewModel.markAsRead(comicsToMark)
        selectedComics.removeAll()
        isSelectionMode = false
    }

    private func markAsUnreadSelectedComics() {
        let comicsToReset = viewModel.comics.filter { selectedComics.contains($0.id) }
        viewModel.markAsUnread(comicsToReset)
        selectedComics.removeAll()
        isSelectionMode = false
    }

    private func addSelectedToReadingList() {
        let comics = viewModel.comics.filter { selectedComics.contains($0.id) }
        for comic in comics {
            if !comic.isOnReadingList {
                viewModel.toggleReadingList(comic)
            }
        }
        selectedComics.removeAll()
        isSelectionMode = false
    }

    private func regenerateCoversForSelected() {
        let comics = viewModel.comics.filter { selectedComics.contains($0.id) }
        viewModel.regenerateCovers(for: comics)
        selectedComics.removeAll()
        isSelectionMode = false
    }

    /// Queue comics for deletion and show the shared confirmation. Used by both
    /// the single-book context menu and the selection toolbar.
    private func requestDelete(_ comics: [Comic]) {
        guard !comics.isEmpty else { return }
        comicsPendingDelete = comics
        showingDeleteConfirmation = true
    }

    /// Delete the queued comics (after confirmation) and tidy up selection.
    private func performPendingDelete() {
        let toDelete = comicsPendingDelete
        comicsPendingDelete = []
        guard !toDelete.isEmpty else { return }

        AppLog.library.debug("🗑️ [LibraryView] Deleting \(toDelete.count) comic(s)")
        viewModel.deleteComics(toDelete)

        if isSelectionMode {
            selectedComics.removeAll()
            isSelectionMode = false
        }
    }

    // MARK: - Open / Edit

    private func openReader(for comic: Comic) {
        AppLog.library.debug("🎯 [LibraryView] User tapped comic: \(comic.fileName)")
        AppLog.library.debug("🎯 [LibraryView] File type: \(comic.fileType.rawValue)")
        AppLog.library.debug("🎯 [LibraryView] Has bookmark: \(comic.bookmarkData != nil)")

        // Snapshot the current display order (sort + filters + folder scope)
        // so the reader's "Up Next" suggestion follows what the user sees.
        viewModel.readingOrderIDs = filteredAndSortedComics.map(\.id)

        #if os(iOS)
            // Start pre-fetching immediately so the reader has a head start.
            // The reader will consume this data and skip its loading spinner.
            viewModel.prefetchComic(comic)
            AppLog.library.debug("🎯 [LibraryView] ⚡ Pre-fetch triggered — opening reader")

            // Give the CPU a 200ms head start to decompress (especially helpful for CBR).
            // This usually eliminates the visible spinner entirely for most file sizes.
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    AppLog.library.debug("🎯 [LibraryView] Setting viewModel.readingComic after 200ms head start")
                    viewModel.readingComic = comic
                }
            }
        #else
            AppLog.library.debug("🎯 [LibraryView] Setting viewModel.readingComic (triggers full screen reader)")
            viewModel.readingComic = comic
        #endif
    }

    private func editComic(_ comic: Comic) {
        AppLog.library.debug("[LibraryView] 📝 Opening editor for: \(comic.fileName)")
        editingComicID = ComicID(id: comic.id)
    }

    // MARK: - ComicVine Fetch (no edit sheet)

    /// Show a status message that auto-dismisses after a few seconds.
    private func flashComicVineStatus(_ message: String) {
        withAnimation { comicVineStatus = message }
        let token = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if comicVineStatus == token {
                withAnimation { comicVineStatus = nil }
            }
        }
    }

    /// Context-menu fetch on a single book: fills and saves directly. If the
    /// search is ambiguous, opens the match picker. EPUB books route to
    /// Open Library / Google Books; everything else to ComicVine.
    private func fetchMetadataSingle(_ comic: Comic) {
        if comic.isEbook {
            fetchBookMetadataSingle(comic)
            return
        }
        Task {
            let outcome = await viewModel.fetchComicVineMetadata(for: comic, force: false)
            switch outcome {
            case .updated:
                flashComicVineStatus("\(comic.displayTitle): metadata updated.")
            case .needsChoice:
                pendingPickerComicID = ComicID(id: comic.id)
            case .alreadyFetched:
                // Explicit single action → user likely wants a refresh
                let forced = await viewModel.fetchComicVineMetadata(for: comic, force: true)
                if case .needsChoice = forced {
                    pendingPickerComicID = ComicID(id: comic.id)
                } else {
                    flashComicVineStatus("\(comic.displayTitle): metadata refreshed.")
                }
            case .noKey:
                flashComicVineStatus("Add a ComicVine API key in Settings first.")
            case .noMatches:
                flashComicVineStatus("\(comic.displayTitle): no ComicVine match found.")
            case .failed(let reason):
                flashComicVineStatus("Fetch failed: \(reason)")
            }
        }
    }

    /// Context-menu fetch for an EPUB book (Open Library + Google Books).
    private func fetchBookMetadataSingle(_ comic: Comic) {
        Task {
            let outcome = await viewModel.fetchOpenLibraryMetadata(for: comic, force: false)
            switch outcome {
            case .updated:
                flashComicVineStatus("\(comic.displayTitle): metadata updated.")
            case .needsChoice:
                pendingPickerComicID = ComicID(id: comic.id)
            case .alreadyFetched:
                // Explicit single action → user likely wants a refresh
                let forced = await viewModel.fetchOpenLibraryMetadata(for: comic, force: true)
                if case .needsChoice = forced {
                    pendingPickerComicID = ComicID(id: comic.id)
                } else {
                    flashComicVineStatus("\(comic.displayTitle): metadata refreshed.")
                }
            case .noMatches:
                // Still useful: open the picker so the user can search manually.
                pendingPickerComicID = ComicID(id: comic.id)
                flashComicVineStatus("\(comic.displayTitle): no automatic match — search manually.")
            case .notEbook:
                flashComicVineStatus("\(comic.displayTitle): book lookup only covers items classified as books.")
            case .quotaDeferred(let retryAfter):
                let time = retryAfter.formatted(date: .omitted, time: .shortened)
                flashComicVineStatus("Lookup budget reached — try again after \(time).")
            case .failed(let reason):
                flashComicVineStatus("Fetch failed: \(reason)")
            }
        }
    }

    /// Undo the last ComicVine fetch on one book (context menu).
    private func revertMetadataSingle(_ comic: Comic) {
        if viewModel.revertComicVineFetch(for: comic) {
            flashComicVineStatus("\(comic.displayTitle): reverted to pre-fetch metadata.")
        } else {
            flashComicVineStatus("\(comic.displayTitle): nothing to revert.")
        }
    }

    /// Selection-bar batch fetch across every selected book. Routes each
    /// file to the provider that supports it: EPUB books go to Open Library
    /// (no key needed), everything else to ComicVine.
    private func fetchMetadataForSelected() {
        guard !selectedComics.isEmpty, !isBatchFetching else { return }
        let comics = viewModel.comics.filter { selectedComics.contains($0.id) }
        let epubs = comics.filter { $0.isEbook }
        let issues = comics.filter { !$0.isEbook }
        isBatchFetching = true
        let total = comics.count
        flashComicVineStatus("Fetching metadata for \(total) book\(total == 1 ? "" : "s")…")
        Task {
            var summaries: [String] = []

            if !issues.isEmpty {
                let result = await viewModel.fetchComicVineMetadataBatch(for: issues) { done, total in
                    comicVineStatus = "Fetching comic metadata… \(done) of \(total)"
                }
                summaries.append(
                    epubs.isEmpty ? result.summary : "Comics: \(result.summary)")
                // Surface the review queue for any books that need a decision.
                if !result.pendingReviewIDs.isEmpty {
                    batchReviewIDs = result.pendingReviewIDs
                    showingBatchReview = true
                }
            }

            if !epubs.isEmpty {
                let result = await viewModel.fetchOpenLibraryMetadataBatch(for: epubs) { message in
                    comicVineStatus = message
                }
                summaries.append(
                    issues.isEmpty ? result.summary : "Books: \(result.summary)")
            }

            isBatchFetching = false
            flashComicVineStatus(summaries.joined(separator: " "))
        }
    }

    // MARK: - Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Quick Add imports straight away and auto-sorts into the home
            // library. (Per-folder placement is offered on the Organize
            // "Add Comics" flow instead.)
            startImport(urls)
        case .failure(let error):
            AppLog.library.error("File import failed: \(error.localizedDescription)")
        }
    }

    /// Imports immediately, or pauses to offer setting a home library first
    /// (auto-sort on, no library folder chosen yet).
    private func startImport(_ urls: [URL]) {
        if HomeLibrarySetupPrompt.needsPrompt {
            pendingImportURLs = urls
            showingHomeLibraryPrompt = true
        } else {
            Task { await viewModel.importComics(from: urls) }
        }
    }

    /// Splits dropped URLs into plain comic files (imported straight into the
    /// Library, as before) and `.scobook` transfer packages (routed to the
    /// shared receive flow — they carry their own manifest/folder-choice/
    /// duplicate-check and aren't something the comic importer understands).
    private func routeDroppedURLs(_ urls: [URL]) {
        var comicURLs: [URL] = []
        var scobookURLs: [URL] = []
        for url in urls {
            let fileExtension = url.pathExtension.lowercased()
            if fileExtension == BookPackage.fileExtension {
                scobookURLs.append(url)
            } else if fileExtension == "cbz" || fileExtension == "pdf" || fileExtension == "zip" {
                comicURLs.append(url)
            }
        }

        if !scobookURLs.isEmpty {
            incomingTransferCoordinator.enqueue(urls: scobookURLs)
        }
        if !comicURLs.isEmpty {
            AppLog.library.debug("Importing \(comicURLs.count) dropped files")
            startImport(comicURLs)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        #if os(macOS)
            // macOS drag & drop handling
            let group = DispatchGroup()
            var urls: [URL] = []

            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) {
                    (urlData, error) in
                    defer { group.leave() }

                    if let error = error {
                        AppLog.library.error("Error loading item: \(error)")
                        return
                    }

                    if let urlData = urlData as? Data,
                        let urlString = String(data: urlData, encoding: .utf8),
                        let url = URL(string: urlString)
                    {
                        urls.append(url)
                    }
                }
            }

            // Wait for all loads to complete, then route
            group.notify(queue: .main) {
                routeDroppedURLs(urls)
            }

            return true
        #else
            // iOS drag & drop - simpler
            Task {
                var urls: [URL] = []

                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                        do {
                            if let url = try await provider.loadItem(
                                forTypeIdentifier: "public.file-url", options: nil) as? URL
                            {
                                urls.append(url)
                            }
                        } catch {
                            AppLog.library.error("Failed to load dropped item: \(error)")
                        }
                    }
                }

                routeDroppedURLs(urls)
            }

            return true
        #endif
    }
}

// MARK: - Folder Cover Photo Picker (iOS)

#if os(iOS)
    /// Presents the Photos library picker for choosing a folder cover. Kept in
    /// its own ViewModifier so the (very long) LibraryView body modifier chain
    /// stays within the Swift type-checker's time budget.
    private struct FolderCoverPhotoPickerModifier: ViewModifier {
        @Binding var isPresented: Bool
        @Binding var selection: PhotosPickerItem?
        let onPick: (PhotosPickerItem) -> Void

        func body(content: Content) -> some View {
            content
                .photosPicker(
                    isPresented: $isPresented,
                    selection: $selection,
                    matching: .images
                )
                .onChange(of: selection) { _, newItem in
                    guard let newItem else { return }
                    onPick(newItem)
                }
        }
    }
#endif

// MARK: - File Drop Target

/// Drop handling + dashed drop-zone indicator shared by the grid and list.
private struct FileDropTarget: ViewModifier {
    @Binding var isTargeted: Bool
    let onDrop: ([NSItemProvider]) -> Bool

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                onDrop(providers)
            }
            .overlay(
                // Drop zone indicator
                Group {
                    if isTargeted {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                AccentColors.primary,
                                style: StrokeStyle(lineWidth: 3, dash: [10, 5])
                            )
                            .background(AccentColors.primary.opacity(0.1))
                            .padding(Spacing.xl)
                    }
                }
            )
    }
}

#Preview {
    LibraryView(viewModel: LibraryViewModel(database: DatabaseManager.shared))
        .environmentObject(IncomingTransferCoordinator())
}
