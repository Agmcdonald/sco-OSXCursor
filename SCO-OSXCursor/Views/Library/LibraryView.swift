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

    // Missing-file recovery (Locate File…)
    @State private var relinkComicID: ComicID?
    @State private var showingRelinkPicker = false

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
            restrictTo: folderRestriction
        )
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

    /// Folders sorted per the shared sort menu (folder view).
    var sortedFolders: [Folder] {
        LibraryQuery.sortFolders(
            viewModel.folders,
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
            folders: viewModel.folders,
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
            requestNewFolderForComic: { comic in
                newFolderContext = .comic(comic)
                newFolderName = ""
                showingNewFolderAlert = true
            },
            requestNewFolderForSelection: {
                newFolderContext = .selection
                newFolderName = ""
                showingNewFolderAlert = true
            },
            revealInFolder: { folderID in
                searchText = ""
                scope = .folder(folderID)
            }
        )
    }

    private var emptyState: LibraryEmptyStateView {
        LibraryEmptyStateView(
            isLibraryEmpty: viewModel.comics.isEmpty,
            canClearFilters: filters.status != nil || filters.publisher != nil
                || !searchText.isEmpty,
            onAddComics: { showingFilePicker = true },
            onClearFilters: {
                filters.status = nil
                filters.publisher = nil
                searchText = ""
            }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            LibraryHeaderView(
                viewMode: $viewMode,
                searchText: $searchText,
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
                    newFolderName = ""
                    showingNewFolderAlert = true
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
                        newFolderName = ""
                        showingNewFolderAlert = true
                    }
                )

                Divider()
                    .background(BorderColors.subtle)
            }

            // Content
            switch viewMode {
            case .grid:
                LibraryGridView(
                    comics: filteredAndSortedComics,
                    isSelectionMode: isSelectionMode,
                    selectedComics: selectedComics,
                    focusedComicID: focusedComic?.id,
                    coverSize: coverSize,
                    actions: cellActions,
                    emptyState: emptyState
                )
                .modifier(FileDropTarget(isTargeted: $isDropTargeted, onDrop: handleDrop))
            case .list:
                LibraryListView(
                    comics: filteredAndSortedComics,
                    isSelectionMode: isSelectionMode,
                    selectedComics: selectedComics,
                    focusedComicID: focusedComic?.id,
                    actions: cellActions,
                    emptyState: emptyState
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
                LibraryFolderGridView(
                    folders: sortedFolders,
                    count: { viewModel.folderCount($0) },
                    previewComics: { previewComics(in: $0) },
                    coverSize: coverSize,
                    totalCount: viewModel.comics.count,
                    unfiledCount: viewModel.unfiledCount,
                    unfiledPreview: unfiledPreviewComics(),
                    onOpenAll: {
                        searchText = ""
                        scope = .all
                        viewMode = .grid
                    },
                    onOpenUnfiled: {
                        searchText = ""
                        scope = .unfiled
                        viewMode = .grid
                    },
                    onOpen: { folder in
                        searchText = ""
                        scope = .folder(folder.id)
                        viewMode = .grid
                    },
                    onRename: { folder in
                        folderPendingRename = folder
                        renameFolderName = folder.name
                    },
                    onDelete: { folder in
                        folderPendingDelete = folder
                    },
                    onNewFolder: {
                        newFolderContext = .empty
                        newFolderName = ""
                        showingNewFolderAlert = true
                    }
                )
            }
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
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [
                .folder, .zip, .pdf, .cbr, .epub, UTType(filenameExtension: "cbr")!,
                UTType(filenameExtension: "epub") ?? .data,
            ],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        // Locate File… — re-link a single missing/moved book
        .fileImporter(
            isPresented: $showingRelinkPicker,
            allowedContentTypes: [
                .zip, .pdf, .cbr, .epub,
                UTType(filenameExtension: "cbz") ?? .data,
            ],
            allowsMultipleSelection: false
        ) { result in
            handleRelink(result)
        }
        .sheet(isPresented: $showingBulkEdit) {
            BulkEditSheet(itemCount: selectedComics.count) { values in
                viewModel.bulkEdit(ids: selectedComics, values: values)
                isSelectionMode = false
                selectedComics.removeAll()
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
        // ComicVine match picker for an ambiguous no-sheet fetch
        .sheet(item: $pendingPickerComicID) { wrapper in
            if let comic = viewModel.comics.first(where: { $0.id == wrapper.id }) {
                ComicVineMatchPicker(comic: comic, viewModel: viewModel)
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
        .onChange(of: focusedComic) { _, _ in
            // Selection alone no longer opens the inspector —
            // the user must tap the Info (ⓘ) button explicitly.
        }
        .onChange(of: viewModel.comics) { _, newComics in
            if let focused = focusedComic,
                let updated = newComics.first(where: { $0.id == focused.id })
            {
                // Must update focusedComic because Comic's Equatable only checks ID
                focusedComic = updated
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
            // Only act when no sheet / overlay is capturing keyboard input
            guard editingComicID == nil, !showingFilters else { return .ignored }
            if let comic = focusedComic, !isSelectionMode {
                openReader(for: comic)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            guard editingComicID == nil, !showingFilters else { return .ignored }
            if let comic = focusedComic, !isSelectionMode {
                openReader(for: comic)
                return .handled
            }
            return .ignored
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
        Task {
            guard let folder = await viewModel.createFolder(named: name) else { return }
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
    /// search is ambiguous, opens the match picker.
    private func fetchMetadataSingle(_ comic: Comic) {
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

    /// Selection-bar batch fetch across every selected book.
    private func fetchMetadataForSelected() {
        guard !selectedComics.isEmpty, !isBatchFetching else { return }
        let comics = viewModel.comics.filter { selectedComics.contains($0.id) }
        isBatchFetching = true
        let total = comics.count
        flashComicVineStatus("Fetching metadata for \(total) book\(total == 1 ? "" : "s")…")
        Task {
            let result = await viewModel.fetchComicVineMetadataBatch(for: comics) { done, total in
                comicVineStatus = "Fetching metadata… \(done) of \(total)"
            }
            isBatchFetching = false
            flashComicVineStatus(result.summary)
            // Surface the review queue for any books that need a decision.
            if !result.pendingReviewIDs.isEmpty {
                batchReviewIDs = result.pendingReviewIDs
                showingBatchReview = true
            }
        }
    }

    // MARK: - Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Process files asynchronously
            Task {
                await viewModel.importComics(from: urls)
            }
        case .failure(let error):
            AppLog.library.error("File import failed: \(error.localizedDescription)")
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

                        let fileExtension = url.pathExtension.lowercased()
                        if fileExtension == "cbz" || fileExtension == "pdf"
                            || fileExtension == "zip"
                        {
                            // Get bookmark data for persistent access
                            urls.append(url)
                        }
                    }
                }
            }

            // Wait for all loads to complete, then import
            group.notify(queue: .main) {
                if !urls.isEmpty {
                    AppLog.library.debug("Importing \(urls.count) dropped files")
                    Task {
                        await viewModel.importComics(from: urls)
                    }
                }
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
                                let fileExtension = url.pathExtension.lowercased()
                                if fileExtension == "cbz" || fileExtension == "pdf"
                                    || fileExtension == "zip"
                                {
                                    urls.append(url)
                                }
                            }
                        } catch {
                            AppLog.library.error("Failed to load dropped item: \(error)")
                        }
                    }
                }

                if !urls.isEmpty {
                    await viewModel.importComics(from: urls)
                }
            }

            return true
        #endif
    }
}

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
}
