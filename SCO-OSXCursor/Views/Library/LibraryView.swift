//
//  LibraryView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI
import UniformTypeIdentifiers

// Custom UTType for CBR
extension UTType {
    static var cbr: UTType {
        UTType(exportedAs: "com.rarlab.rar-archive")
    }

    // epub is a well-known public UTType — use the system identifier
    static var epub: UTType {
        UTType(importedAs: "org.idpf.epub-container")
    }
}

// Wrapper to make UUID work with .sheet(item:)
private struct ComicID: Identifiable {
    let id: UUID
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

    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @State private var selectedComic: Comic?
    @State private var hasLoaded = false
    @AppStorage("librarySortOption") private var sortOption: SortOption = .dateAdded
    @State private var filterStatus: Comic.Status? = nil
    @State private var filterPublisher: String? = nil
    @State private var filterSeries: String? = nil
    @State private var filterYear: Int? = nil
    @State private var filterReadingList: Bool = false
    @State private var showingFilters = false
    @State private var isSelectionMode = false
    @State private var selectedComics: Set<Comic.ID> = []
    @State private var showingBulkEdit = false
    /// Anchor for shift-click / "Select Range to Here" range selection
    @State private var selectionAnchorID: Comic.ID?
    @State private var showingFilePicker = false
    @State private var importedFileURLs: [URL] = []
    @State private var isDropTargeted = false
    @State private var showingDeleteConfirmation = false
    @State private var editingComicID: ComicID?
    @State private var focusedComic: Comic?
    @State private var isInspectorPresented = false

    enum ViewMode {
        case grid, list, publisher
    }

    enum SortOption: String, CaseIterable {
        case title = "Title (A-Z)"
        case dateAdded = "Date Added"
        case dateModified = "Recently Modified"
        case publisher = "Publisher"
        case year = "Publication Year"
        case rating = "Rating"
        case fileSize = "File Size"

        var icon: String {
            switch self {
            case .title: return "textformat"
            case .dateAdded: return "calendar.badge.plus"
            case .dateModified: return "calendar.badge.clock"
            case .publisher: return "building.2"
            case .year: return "calendar"
            case .rating: return "star"
            case .fileSize: return "externaldrive"
            }
        }
    }

    var filteredAndSortedComics: [Comic] {
        var result = viewModel.comics

        // Apply search filter - searches across all metadata fields
        if !searchText.isEmpty {
            result = result.filter { comic in
                comic.displayTitle.localizedCaseInsensitiveContains(searchText)
                    || comic.fileName.localizedCaseInsensitiveContains(searchText)
                    || comic.title?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.publisher?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.series?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.writer?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.artist?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.coverArtist?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.summary?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.issueNumber?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.tags.contains(where: {
                        $0.localizedCaseInsensitiveContains(searchText)
                    })
            }
        }

        // Apply status filter
        if let status = filterStatus {
            result = result.filter { $0.status == status }
        }

        // Apply reading list filter
        if filterReadingList {
            result = result.filter { $0.isOnReadingList }
        }

        // Apply publisher filter
        if let publisher = filterPublisher {
            result = result.filter { $0.publisher == publisher }
        }

        // Apply series filter
        if let series = filterSeries {
            result = result.filter { $0.series == series }
        }

        // Apply year filter
        if let year = filterYear {
            result = result.filter { $0.year == year }
        }

        // Apply sorting
        switch sortOption {
        case .title:
            result.sort {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
        case .dateAdded:
            result.sort { $0.dateAdded > $1.dateAdded }
        case .dateModified:
            result.sort { $0.dateModified > $1.dateModified }
        case .publisher:
            result.sort { ($0.publisher ?? "") < ($1.publisher ?? "") }
        case .year:
            result.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .rating:
            result.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .fileSize:
            result.sort { $0.fileSize > $1.fileSize }
        }

        return result
    }

    // MARK: - Publisher Hierarchy

    struct SeriesGroup: Identifiable {
        let id: String  // "Publisher::Series"
        let series: String
        let comics: [Comic]
        var yearRange: String {
            let years = comics.compactMap { $0.year }.sorted()
            guard !years.isEmpty else { return "" }
            if years.first == years.last { return String(years.first!) }
            return "\(years.first!)-\(years.last!)"
        }
    }

    struct PublisherGroup: Identifiable {
        let id: String  // publisher name
        let publisher: String
        let seriesGroups: [SeriesGroup]
        var totalComics: Int { seriesGroups.reduce(0) { $0 + $1.comics.count } }
        var yearRange: String {
            let years = seriesGroups.flatMap { $0.comics }.compactMap { $0.year }.sorted()
            guard !years.isEmpty else { return "" }
            if years.first == years.last { return String(years.first!) }
            return "\(years.first!)-\(years.last!)"
        }
    }

    var publisherGroups: [PublisherGroup] {
        let comics = filteredAndSortedComics
        let grouped = Dictionary(grouping: comics) { $0.publisher ?? "Unknown Publisher" }
        return
            grouped
            .map { (pub, pubComics) -> PublisherGroup in
                let seriesGrouped = Dictionary(grouping: pubComics) {
                    $0.series ?? "Unknown Series"
                }
                let seriesGroups =
                    seriesGrouped
                    .map { (ser, serComics) -> SeriesGroup in
                        SeriesGroup(
                            id: "\(pub)::\(ser)",
                            series: ser,
                            comics: serComics.sorted {
                                ($0.issueNumber ?? "").localizedStandardCompare(
                                    $1.issueNumber ?? "") == .orderedAscending
                            }
                        )
                    }
                    .sorted { $0.series.localizedStandardCompare($1.series) == .orderedAscending }
                return PublisherGroup(id: pub, publisher: pub, seriesGroups: seriesGroups)
            }
            .sorted { $0.publisher.localizedStandardCompare($1.publisher) == .orderedAscending }
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

    var hasActiveFilters: Bool {
        filterStatus != nil || filterPublisher != nil || filterSeries != nil || filterYear != nil || filterReadingList
    }

    // Publisher/Series expand state
    @State private var expandedPublishers: Set<String> = []
    @State private var expandedSeries: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView

            Divider()
                .background(BorderColors.subtle)

            // Content
            if viewMode == .grid {
                gridView
            } else if viewMode == .list {
                listView
            } else {
                publisherView
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
            allowedContentTypes: [.folder, .zip, .pdf, .cbr, .epub, UTType(filenameExtension: "cbr")!, UTType(filenameExtension: "epub") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingBulkEdit) {
            BulkEditSheet(itemCount: selectedComics.count) { values in
                viewModel.bulkEdit(ids: selectedComics, values: values)
                isSelectionMode = false
                selectedComics.removeAll()
            }
        }
        .alert("Delete Comics", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedComics()
            }
        } message: {
            Text(
                "Are you sure you want to delete \(selectedComics.count) comic\(selectedComics.count == 1 ? "" : "s")? This action cannot be undone."
            )
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
        .onChange(of: focusedComic) { _, _ in
            // Selection alone no longer opens the inspector —
            // the user must tap the Info (ⓘ) button explicitly.
        }
        .onChange(of: viewModel.comics) { _, newComics in
            if let focused = focusedComic,
               let updated = newComics.first(where: { $0.id == focused.id }) {
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
                ComicInspectorView(comic: comic, onDismiss: {
                    isInspectorPresented = false
                })
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

    // MARK: - Toolbar Components

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(TextColors.tertiary)

            TextField("Search comics, series, publisher...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundColor(TextColors.primary)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(TextColors.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help("Search comics, series, and publishers")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button(action: { sortOption = option }) {
                    Label {
                        Text(option.rawValue)
                    } icon: {
                        Image(systemName: sortOption == option ? "checkmark" : option.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: sortOption.icon)
                Text(sortOption.rawValue)
                    .font(Typography.bodySmall)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .foregroundColor(TextColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 180)
        .help("Sort your library")
    }

    private var filtersButton: some View {
        Button(action: { showingFilters.toggle() }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text("Filters")
                    .font(Typography.bodySmall)
                if hasActiveFilters {
                    Circle()
                        .fill(AccentColors.primary)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundColor(showingFilters ? AccentColors.primary : TextColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                showingFilters ? AccentColors.primary.opacity(0.12) : BackgroundColors.elevated
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Filter your library")
    }

    private var selectButton: some View {
        Button(action: { isSelectionMode = true }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.circle")
                Text("Select")
                    .font(Typography.bodySmall)
            }
            .foregroundColor(TextColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Select multiple comics for bulk editing or deletion")
    }

    private var viewModeToggle: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: { viewMode = .grid }) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16))
                    .foregroundColor(
                        viewMode == .grid ? AccentColors.primary : TextColors.secondary
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        viewMode == .grid ? AccentColors.primary.opacity(0.12) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Grid View")

            Button(action: { viewMode = .list }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16))
                    .foregroundColor(
                        viewMode == .list ? AccentColors.primary : TextColors.secondary
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        viewMode == .list ? AccentColors.primary.opacity(0.12) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("List View")

            Button(action: { viewMode = .publisher }) {
                Image(systemName: "building.2")
                    .font(.system(size: 16))
                    .foregroundColor(
                        viewMode == .publisher ? AccentColors.primary : TextColors.secondary
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        viewMode == .publisher ? AccentColors.primary.opacity(0.12) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Publisher View")
        }
    }

    private var moreMenu: some View {
        Menu {
            // Sort section
            Section("Sort By") {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button(action: { sortOption = option }) {
                        Label(
                            option.rawValue,
                            systemImage: sortOption == option ? "checkmark" : option.icon)
                    }
                }
            }

            // Actions section
            Section {
                Button(action: { showingFilters.toggle() }) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    if hasActiveFilters {
                        Text("•").foregroundColor(AccentColors.primary)
                    }
                }

                if !isSelectionMode {
                    Button(action: { isSelectionMode = true }) {
                        Label("Select Comics", systemImage: "checkmark.circle")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .foregroundColor(TextColors.secondary)
                .frame(width: 44, height: 44)
                .background(BackgroundColors.elevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Library")
                        .font(Typography.h1)
                        .foregroundColor(TextColors.primary)

                    if viewMode == .publisher {
                        let pg = publisherGroups
                        Text(
                            "\(pg.count) publisher\(pg.count == 1 ? "" : "s") • \(filteredAndSortedComics.count) comics"
                        )
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                    } else {
                        Text("Browse your collection of \(filteredAndSortedComics.count) comics")
                            .font(Typography.body)
                            .foregroundColor(TextColors.secondary)
                    }
                }

                Spacer()

                // Selection mode controls
                if isSelectionMode {
                    HStack(spacing: Spacing.md) {
                        Text("\(selectedComics.count) selected")
                            .font(Typography.body)
                            .foregroundColor(TextColors.secondary)

                        // Select All / Deselect All — operates on the current
                        // filter/search results, so "search a series → Select
                        // All → Edit Fields" fixes hundreds in three clicks
                        Button(action: {
                            let visibleIDs = Set(filteredAndSortedComics.map(\.id))
                            if selectedComics.count < visibleIDs.count {
                                selectedComics = visibleIDs
                            } else {
                                selectedComics.removeAll()
                            }
                        }) {
                            Text(
                                selectedComics.count < filteredAndSortedComics.count
                                    ? "Select All" : "Deselect All"
                            )
                            .font(Typography.bodySmall)
                            .foregroundColor(AccentColors.primary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.primary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        // Mark as Read button
                        Button(action: {
                            if !selectedComics.isEmpty {
                                markAsReadSelectedComics()
                            }
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "checkmark.circle")
                                Text("Mark as Read")
                                    .font(Typography.bodySmall)
                            }
                            .foregroundColor(
                                selectedComics.isEmpty ? TextColors.tertiary : AccentColors.primary
                            )
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                selectedComics.isEmpty
                                    ? BackgroundColors.elevated : AccentColors.primary.opacity(0.1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedComics.isEmpty)

                        // Bulk Edit button — set series/publisher/year/format
                        // on every selected book at once
                        Button(action: {
                            if !selectedComics.isEmpty {
                                showingBulkEdit = true
                            }
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "square.and.pencil")
                                Text("Edit Fields")
                                    .font(Typography.bodySmall)
                            }
                            .foregroundColor(
                                selectedComics.isEmpty ? TextColors.tertiary : AccentColors.primary
                            )
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                selectedComics.isEmpty
                                    ? BackgroundColors.elevated : AccentColors.primary.opacity(0.1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedComics.isEmpty)

                        // Add to Reading List button
                        Button(action: {
                            if !selectedComics.isEmpty {
                                addSelectedToReadingList()
                            }
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image("ReadingListIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                Text("Add to List")
                                    .font(Typography.bodySmall)
                            }
                            .foregroundColor(
                                selectedComics.isEmpty ? TextColors.tertiary : AccentColors.primary
                            )
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                selectedComics.isEmpty
                                    ? BackgroundColors.elevated : AccentColors.primary.opacity(0.1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedComics.isEmpty)

                        // Regenerate Cover button
                        Button(action: {
                            if !selectedComics.isEmpty {
                                regenerateCoversForSelected()
                            }
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "arrow.clockwise.circle")
                                Text("Regenerate Cover")
                                    .font(Typography.bodySmall)
                            }
                            .foregroundColor(
                                selectedComics.isEmpty ? TextColors.tertiary : TextColors.primary
                            )
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                selectedComics.isEmpty
                                    ? BackgroundColors.elevated : BackgroundColors.elevated
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedComics.isEmpty)

                        // Delete button
                        Button(action: {
                            if !selectedComics.isEmpty {
                                showingDeleteConfirmation = true
                            }
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "trash")
                                Text("Delete")
                                    .font(Typography.bodySmall)
                            }
                            .foregroundColor(selectedComics.isEmpty ? TextColors.tertiary : .red)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                selectedComics.isEmpty
                                    ? BackgroundColors.elevated : Color.red.opacity(0.1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedComics.isEmpty)

                        Button("Cancel") {
                            isSelectionMode = false
                            selectedComics.removeAll()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(TextColors.secondary)
                    }
                } else {
                    HStack(spacing: Spacing.md) {
                        // Quick Add button
                        Button(action: {
                            showingFilePicker = true
                        }) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "plus")
                                Text("Quick Add")
                                    .font(Typography.button)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        // Add Comics (Organize) button — macOS only: it routes
                        // to the Organize tab, which doesn't exist on iPad
                        // (Quick Add is the iPad import path).
                        #if os(macOS)
                        Button(action: {
                            onAddComicsOrganize?()
                        }) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder.badge.plus")
                                Text("Add Comics")
                                    .font(Typography.button)
                            }
                            .foregroundColor(AccentColors.primary)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.primary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                }
            }

            // Search and toolbar
            HStack(spacing: Spacing.md) {
                // Search bar
                searchBar
                    .frame(maxWidth: .infinity)

                #if os(macOS)
                    // macOS: Show all controls (plenty of space)
                    sortMenu
                    filtersButton
                    if !isSelectionMode {
                        selectButton
                    }
                    // Info (ⓘ) button — enabled when a comic is focused
                    Button(action: {
                        if focusedComic != nil {
                            isInspectorPresented.toggle()
                        }
                    }) {
                        Image(systemName: isInspectorPresented ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 16))
                            .foregroundColor(
                                focusedComic != nil ? AccentColors.primary : TextColors.tertiary
                            )
                            .frame(width: 32, height: 32)
                            .background(
                                isInspectorPresented ? AccentColors.primary.opacity(0.12) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(focusedComic == nil)
                    .help(focusedComic == nil ? "Select a comic to view info" : (isInspectorPresented ? "Hide Info" : "Show Info"))
                    viewModeToggle
                #else
                    // iPad/iOS: Compact "More" menu
                    moreMenu
                    viewModeToggle
                #endif
            }

            // Active filter badges (always visible when filters applied)
            if hasActiveFilters && !showingFilters {
                activeFilterBadges
            }

            // Filter panel (shown when filters button is clicked)
            if showingFilters {
                filterView
            }
        }
        .padding(Spacing.xl)
    }

    // MARK: - Active Filter Badges
    private var activeFilterBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                if let status = filterStatus {
                    FilterBadge(
                        title: "Status: \(status.displayLabel)",
                        icon: status.icon,
                        onRemove: { filterStatus = nil }
                    )
                }

                if filterReadingList {
                    FilterBadge(
                        title: "Want to Read",
                        icon: "bookmark.fill",
                        onRemove: { filterReadingList = false }
                    )
                }

                if let publisher = filterPublisher {
                    FilterBadge(
                        title: "Publisher: \(publisher)",
                        icon: "building.2",
                        onRemove: { filterPublisher = nil }
                    )
                }

                if let series = filterSeries {
                    FilterBadge(
                        title: "Series: \(series)",
                        icon: "books.vertical",
                        onRemove: { filterSeries = nil }
                    )
                }

                if let year = filterYear {
                    FilterBadge(
                        title: "Year: \(String(year))",
                        icon: "calendar",
                        onRemove: { filterYear = nil }
                    )
                }

                // Clear all button
                Button(action: {
                    filterStatus = nil
                    filterPublisher = nil
                    filterSeries = nil
                    filterYear = nil
                    filterReadingList = false
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Clear All")
                            .font(Typography.caption)
                    }
                    .foregroundColor(TextColors.tertiary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(BackgroundColors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Filter View
    private var filterView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Filters")
                .font(Typography.h3)
                .foregroundColor(TextColors.primary)

            // Status filter
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Status")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                HStack(spacing: Spacing.sm) {
                    FilterChip(
                        title: "All",
                        isSelected: filterStatus == nil && !filterReadingList,
                        action: { filterStatus = nil; filterReadingList = false }
                    )

                    ForEach(Comic.Status.allCases, id: \.self) { status in
                        FilterChip(
                            title: status.displayLabel,
                            icon: status.icon,
                            color: status.color,
                            isSelected: filterStatus == status,
                            action: { filterStatus = status; filterReadingList = false }
                        )
                    }

                    // Reading list chip
                    FilterChip(
                        title: "Want to Read",
                        icon: "bookmark.fill",
                        color: AccentColors.primary,
                        isSelected: filterReadingList,
                        action: { filterReadingList = true; filterStatus = nil }
                    )
                }
            }

            // Publisher filter
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Publisher")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        FilterChip(
                            title: "All",
                            isSelected: filterPublisher == nil,
                            action: { filterPublisher = nil }
                        )

                        ForEach(publishers, id: \.self) { publisher in
                            FilterChip(
                                title: publisher,
                                isSelected: filterPublisher == publisher,
                                action: { filterPublisher = publisher }
                            )
                        }
                    }
                }
            }

            // Series filter
            if !series.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Series")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            FilterChip(
                                title: "All",
                                isSelected: filterSeries == nil,
                                action: { filterSeries = nil }
                            )

                            ForEach(series, id: \.self) { seriesName in
                                FilterChip(
                                    title: seriesName,
                                    isSelected: filterSeries == seriesName,
                                    action: { filterSeries = seriesName }
                                )
                            }
                        }
                    }
                }
            }

            // Year filter
            if !years.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Year")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            FilterChip(
                                title: "All",
                                isSelected: filterYear == nil,
                                action: { filterYear = nil }
                            )

                            ForEach(years, id: \.self) { year in
                                FilterChip(
                                    title: String(year),
                                    isSelected: filterYear == year,
                                    action: { filterYear = year }
                                )
                            }
                        }
                    }
                }
            }

            // Clear all filters
            if hasActiveFilters {
                Button(action: {
                    filterStatus = nil
                    filterPublisher = nil
                    filterSeries = nil
                    filterYear = nil
                    filterReadingList = false
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Clear All Filters")
                            .font(Typography.bodySmall)
                    }
                    .foregroundColor(TextColors.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.lg)
        .background(BackgroundColors.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Grid View
    private var gridView: some View {
        ScrollView {
            if filteredAndSortedComics.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: Spacing.xl)
                    ],
                    spacing: Spacing.xxl
                ) {
                    ForEach(filteredAndSortedComics) { comic in
                        ZStack(alignment: .topLeading) {
                            ComicCardView(comic: comic)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(focusedComic?.id == comic.id ? AccentColors.primary : Color.clear, lineWidth: 3)
                                )
                                #if os(macOS)
                                .onTapGesture(count: 2) {
                                    if !isSelectionMode {
                                        openReader(for: comic)
                                    }
                                }
                                .onTapGesture(count: 1) {
                                    if isSelectionMode {
                                        handleSelectionTap(comic)
                                    } else {
                                        focusedComic = comic
                                    }
                                }
                                #else
                                .onTapGesture {
                                    if isSelectionMode {
                                        handleSelectionTap(comic)
                                    } else {
                                        openReader(for: comic)
                                    }
                                }
                                #endif
                                .contextMenu {
                                    // Range selection without a keyboard (iPad):
                                    // tap one book, long-press another, select the span
                                    if isSelectionMode {
                                        Button(action: { selectRange(to: comic) }) {
                                            Label("Select Range to Here", systemImage: "checklist")
                                        }
                                    }

                                    Button(action: { openReader(for: comic) }) {
                                        Label("Read", systemImage: "book.fill")
                                    }

                                    Button(action: { editComic(comic) }) {
                                        Label("Edit Metadata", systemImage: "pencil")
                                    }

                                    Button(action: { viewModel.markAsRead([comic]) }) {
                                        Label("Mark as Read", systemImage: "checkmark.circle")
                                    }

                                    Button(action: { viewModel.toggleReadingList(comic) }) {
                                        Label(
                                            comic.isOnReadingList
                                                ? "Remove from Reading List"
                                                : "Add to Reading List",
                                            systemImage: comic.isOnReadingList
                                                ? "bookmark.slash" : "bookmark"
                                        )
                                    }

                                    Button(action: { viewModel.regenerateCovers(for: [comic]) }) {
                                        Label(
                                            "Regenerate Cover",
                                            systemImage: "arrow.clockwise.circle")
                                    }

                                    Divider()

                                    Button(
                                        role: .destructive,
                                        action: {
                                            viewModel.deleteComics([comic])
                                        }
                                    ) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }

                            // Selection checkbox
                            if isSelectionMode {
                                SelectionCheckbox(isSelected: selectedComics.contains(comic.id))
                                    .padding(Spacing.sm)
                            }
                        }
                    }
                }
                .padding(Spacing.xl)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay(
            // Drop zone indicator
            Group {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            AccentColors.primary, style: StrokeStyle(lineWidth: 3, dash: [10, 5])
                        )
                        .background(AccentColors.primary.opacity(0.1))
                        .padding(Spacing.xl)
                }
            }
        )
    }

    // MARK: - List View
    private var listView: some View {
        ScrollView {
            if filteredAndSortedComics.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(filteredAndSortedComics) { comic in
                        HStack(spacing: 0) {
                            // Selection checkbox
                            if isSelectionMode {
                                SelectionCheckbox(isSelected: selectedComics.contains(comic.id))
                                    .padding(.trailing, Spacing.md)
                            }

                            ComicRowView(comic: comic)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(focusedComic?.id == comic.id ? AccentColors.primary : Color.clear, lineWidth: 3)
                                )
                                #if os(macOS)
                                .onTapGesture(count: 2) {
                                    if !isSelectionMode {
                                        openReader(for: comic)
                                    }
                                }
                                .onTapGesture(count: 1) {
                                    if isSelectionMode {
                                        handleSelectionTap(comic)
                                    } else {
                                        focusedComic = comic
                                    }
                                }
                                #else
                                .onTapGesture {
                                    if isSelectionMode {
                                        handleSelectionTap(comic)
                                    } else {
                                        openReader(for: comic)
                                    }
                                }
                                #endif
                                .contextMenu {
                                    // Range selection without a keyboard (iPad):
                                    // tap one book, long-press another, select the span
                                    if isSelectionMode {
                                        Button(action: { selectRange(to: comic) }) {
                                            Label("Select Range to Here", systemImage: "checklist")
                                        }
                                    }

                                    Button(action: { openReader(for: comic) }) {
                                        Label("Read", systemImage: "book.fill")
                                    }

                                    Button(action: { editComic(comic) }) {
                                        Label("Edit Metadata", systemImage: "pencil")
                                    }

                                    Button(action: { viewModel.markAsRead([comic]) }) {
                                        Label("Mark as Read", systemImage: "checkmark.circle")
                                    }

                                    Button(action: { viewModel.toggleReadingList(comic) }) {
                                        Label(
                                            comic.isOnReadingList
                                                ? "Remove from Reading List"
                                                : "Add to Reading List",
                                            systemImage: comic.isOnReadingList
                                                ? "bookmark.slash" : "bookmark"
                                        )
                                    }

                                    Button(action: { viewModel.regenerateCovers(for: [comic]) }) {
                                        Label(
                                            "Regenerate Cover",
                                            systemImage: "arrow.clockwise.circle")
                                    }

                                    Divider()

                                    Button(
                                        role: .destructive,
                                        action: {
                                            viewModel.deleteComics([comic])
                                        }
                                    ) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .padding(Spacing.xl)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .overlay(
            // Drop zone indicator
            Group {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            AccentColors.primary, style: StrokeStyle(lineWidth: 3, dash: [10, 5])
                        )
                        .background(AccentColors.primary.opacity(0.1))
                        .padding(Spacing.xl)
                }
            }
        )
    }

    // MARK: - Publisher View

    private var publisherView: some View {
        ScrollView {
            if filteredAndSortedComics.isEmpty {
                emptyStateView
            } else {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(publisherGroups) { publisher in
                        publisherSection(publisher)
                    }
                }
                .padding(Spacing.xl)
            }
        }
    }

    @ViewBuilder
    private func publisherSection(_ group: PublisherGroup) -> some View {
        let isExpanded = expandedPublishers.contains(group.id)
        // Publisher header row
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                if isExpanded {
                    expandedPublishers.remove(group.id)
                } else {
                    expandedPublishers.insert(group.id)
                }
            }
        } label: {
            HStack(spacing: Spacing.md) {
                // Chevron
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TextColors.tertiary)
                    .frame(width: 16, height: 16)

                // Publisher colour dot + banner image
                Circle()
                    .fill(publisherColor(for: group.publisher))
                    .frame(width: 10, height: 10)

                PublisherBannerView(publisherName: group.publisher)

                // Name + subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.publisher)
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    HStack(spacing: Spacing.xs) {
                        Text("\(group.seriesGroups.count) series")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                        if !group.yearRange.isEmpty {
                            Text("•")
                                .font(Typography.caption)
                                .foregroundColor(TextColors.tertiary)
                            Text(group.yearRange)
                                .font(Typography.caption)
                                .foregroundColor(TextColors.secondary)
                        }
                    }
                }

                Spacer()

                // Issue count badge
                Text("\(group.totalComics) \(group.totalComics == 1 ? "issue" : "issues")")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 4)
                    .background(BackgroundColors.elevated)
                    .clipShape(Capsule())
            }
            .padding(.vertical, Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider().background(BorderColors.subtle)

        // Series rows (shown when publisher expanded)
        if isExpanded {
            ForEach(group.seriesGroups) { seriesGroup in
                seriesSection(seriesGroup, publisherID: group.id)
            }
        }
    }

    @ViewBuilder
    private func seriesSection(_ group: SeriesGroup, publisherID: String) -> some View {
        let isExpanded = expandedSeries.contains(group.id)
        // Series row
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                if isExpanded {
                    expandedSeries.remove(group.id)
                } else {
                    expandedSeries.insert(group.id)
                }
            }
        } label: {
            HStack(spacing: Spacing.md) {
                // Indent spacer
                Color.clear.frame(width: 16)

                // Chevron
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TextColors.tertiary)
                    .frame(width: 14, height: 14)

                // Thumbnail of first cover
                if let coverData = group.comics.first?.coverImageData {
                    #if os(macOS)
                        if let nsImg = NSImage(data: coverData) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 32, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    #else
                        if let uiImg = UIImage(data: coverData) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 32, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BackgroundColors.elevated)
                        .frame(width: 32, height: 48)
                        .overlay(
                            Image(systemName: "book.closed")
                                .font(.system(size: 14))
                                .foregroundColor(TextColors.tertiary)
                        )
                }

                // Title + subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.series)
                        .font(Typography.body)
                        .foregroundColor(TextColors.primary)
                    HStack(spacing: Spacing.xs) {
                        Text(
                            "\(group.comics.count) \(group.comics.count == 1 ? "issue" : "issues")"
                        )
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        if !group.yearRange.isEmpty {
                            Text("•")
                                .font(Typography.caption)
                                .foregroundColor(TextColors.tertiary)
                            Text(group.yearRange)
                                .font(Typography.caption)
                                .foregroundColor(TextColors.secondary)
                        }
                    }
                }

                Spacer()

                Text("\(group.comics.count) \(group.comics.count == 1 ? "issue" : "issues")")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 4)
                    .background(BackgroundColors.secondary)
                    .clipShape(Capsule())
            }
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, Spacing.xl)

        Divider().background(BorderColors.subtle).padding(.leading, Spacing.xxl)

        // Inline cover grid (shown when series expanded)
        if isExpanded {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: Spacing.lg)],
                spacing: Spacing.lg
            ) {
                ForEach(group.comics) { comic in
                    ZStack(alignment: .topLeading) {
                        ComicCardView(comic: comic)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(focusedComic?.id == comic.id ? AccentColors.primary : Color.clear, lineWidth: 3)
                                )
                                #if os(macOS)
                                .onTapGesture(count: 2) {
                                    if !isSelectionMode {
                                        openReader(for: comic)
                                    }
                                }
                                .onTapGesture(count: 1) {
                                    if isSelectionMode {
                                        handleSelectionTap(comic)
                                    } else {
                                        focusedComic = comic
                                    }
                                }
                                #else
                                .onTapGesture {
                                    if isSelectionMode {
                                        handleSelectionTap(comic)
                                    } else {
                                        openReader(for: comic)
                                    }
                                }
                                #endif
                            .contextMenu {
                                // Range selection without a keyboard (iPad)
                                if isSelectionMode {
                                    Button(action: { selectRange(to: comic) }) {
                                        Label("Select Range to Here", systemImage: "checklist")
                                    }
                                }

                                Button(action: { openReader(for: comic) }) {
                                    Label("Read", systemImage: "book.fill")
                                }
                                Button(action: { editComic(comic) }) {
                                    Label("Edit Metadata", systemImage: "pencil")
                                }
                                Button(action: { viewModel.markAsRead([comic]) }) {
                                    Label("Mark as Read", systemImage: "checkmark.circle")
                                }
                                Button(action: { viewModel.toggleReadingList(comic) }) {
                                    Label(
                                        comic.isOnReadingList
                                            ? "Remove from Reading List" : "Add to Reading List",
                                        systemImage: comic.isOnReadingList
                                            ? "bookmark.slash" : "bookmark"
                                    )
                                }
                                Divider()
                                Button(
                                    role: .destructive, action: { viewModel.deleteComics([comic]) }
                                ) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                        if isSelectionMode {
                            SelectionCheckbox(isSelected: selectedComics.contains(comic.id))
                                .padding(Spacing.sm)
                        }
                    }
                }
            }
            .padding(.leading, Spacing.xxl)
            .padding(.vertical, Spacing.md)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Returns the publisher accent color (same logic as Comic.publisherColor but by name string)
    private func publisherColor(for publisher: String) -> Color {
        let colors: [Color] = [
            Color(red: 0.0, green: 0.478, blue: 1.0),  // DC blue
            Color(red: 0.9, green: 0.1, blue: 0.1),  // Marvel red
            Color(red: 0.2, green: 0.7, blue: 0.3),  // Image green
            Color(red: 0.9, green: 0.6, blue: 0.1),  // Amber
            Color(red: 0.6, green: 0.2, blue: 0.8),  // Purple
            Color(red: 0.1, green: 0.7, blue: 0.8),  // Teal
        ]
        let hash = abs(publisher.hashValue)
        return colors[hash % colors.count]
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: viewModel.comics.isEmpty ? "tray" : "books.vertical")
                .font(.system(size: 64))
                .foregroundColor(TextColors.tertiary)

            Text(viewModel.comics.isEmpty ? "No Comics Yet" : "No Comics Found")
                .font(Typography.h2)
                .foregroundColor(TextColors.primary)

            if viewModel.comics.isEmpty {
                // First time user
                Text("Add comics to get started")
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)

                Text("Drag and drop CBZ or PDF files here, or click Add Comics")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button(action: { showingFilePicker = true }) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "plus")
                        Text("Add Comics")
                            .font(Typography.button)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.md)
                    .background(AccentColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                // Filtered results are empty
                Text("Try adjusting your filters or search terms")
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)

                if filterStatus != nil || filterPublisher != nil || !searchText.isEmpty {
                    Button(action: {
                        filterStatus = nil
                        filterPublisher = nil
                        searchText = ""
                    }) {
                        Text("Clear All Filters")
                            .font(Typography.button)
                            .foregroundColor(AccentColors.primary)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.primary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    // MARK: - Helper Methods
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

    private func deleteSelectedComics() {
        // Get the comic objects to delete
        let comicsToDelete = viewModel.comics.filter { selectedComics.contains($0.id) }

        print("\n🗑️ [LibraryView] Deleting \(comicsToDelete.count) comics:")
        for comic in comicsToDelete {
            print("   - \(comic.fileName)")
        }

        // Delete them
        viewModel.deleteComics(comicsToDelete)

        // Reset selection mode
        selectedComics.removeAll()
        isSelectionMode = false
    }

    private func openReader(for comic: Comic) {
        print("\n🎯 [LibraryView] User tapped comic: \(comic.fileName)")
        print("🎯 [LibraryView] File type: \(comic.fileType.rawValue)")
        print("🎯 [LibraryView] Has bookmark: \(comic.bookmarkData != nil)")

        #if os(iOS)
            // Start pre-fetching immediately so the reader has a head start.
            // The reader will consume this data and skip its loading spinner.
            viewModel.prefetchComic(comic)
            print("🎯 [LibraryView] ⚡ Pre-fetch triggered — opening reader")

            // Give the CPU a 200ms head start to decompress (especially helpful for CBR).
            // This usually eliminates the visible spinner entirely for most file sizes.
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    print("🎯 [LibraryView] Setting viewModel.readingComic after 200ms head start")
                    viewModel.readingComic = comic
                }
            }
        #else
            print("🎯 [LibraryView] Setting viewModel.readingComic (triggers full screen reader)")
            viewModel.readingComic = comic
        #endif
    }

    private func editComic(_ comic: Comic) {
        print("[LibraryView] 📝 Opening editor for: \(comic.fileName)")
        editingComicID = ComicID(id: comic.id)
    }

    /// Creates a binding to a comic in the viewModel's array by ID.
    /// This avoids timing issues with `.sheet(isPresented:)` and stays safe if the list reorders.
    /// Note: The binding's setter only updates the array. Persistence is handled by saveChanges() in ComicDetailView.
    private func bindingForComic(_ id: UUID) -> Binding<Comic>? {
        guard viewModel.comics.contains(where: { $0.id == id }) else {
            print("[LibraryView] ⚠️ Could not find comic with ID: \(id)")
            return nil
        }

        return Binding(
            get: {
                // Always get the latest value from the array
                // This getter is called frequently by SwiftUI during view evaluation
                // Force unwrap is safe due to the contains() guard in bindingForComic()
                viewModel.comics.first(where: { $0.id == id })!
            },
            set: { updatedComic in
                guard let idx = viewModel.comics.firstIndex(where: { $0.id == id }) else {
                    print("[LibraryView] ⚠️ Comic disappeared during edit: \(id)")
                    return
                }
                print("[LibraryView] 🔄 Binding setter called - updating array at index \(idx)")
                print("[LibraryView]    Title: '\(updatedComic.title ?? "nil")'")
                print("[LibraryView]    Publisher: '\(updatedComic.publisher ?? "nil")'")
                // Only update the array here - persistence happens in saveChanges()
                // @Published will automatically trigger objectWillChange
                viewModel.comics[idx] = updatedComic
                print("[LibraryView]    ✅ Array updated successfully")
            }
        )
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importedFileURLs = urls
            // Process files asynchronously
            Task {
                await viewModel.importComics(from: urls)
            }
        case .failure(let error):
            print("File import failed: \(error.localizedDescription)")
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
                        print("Error loading item: \(error)")
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
                    print("Importing \(urls.count) dropped files")
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
                            print("Failed to load dropped item: \(error)")
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

// MARK: - Comic Row View
struct ComicRowView: View {
    let comic: Comic
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.lg) {
            // Cover image
            ZStack {
                if let coverData = comic.coverImageData {
                    #if os(macOS)
                        if let nsImage = NSImage(data: coverData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            placeholderThumbnail
                        }
                    #else
                        if let uiImage = UIImage(data: coverData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            placeholderThumbnail
                        }
                    #endif
                } else {
                    placeholderThumbnail
                }
            }

            // Comic info
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(comic.displayTitle)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(1)

                if let publisher = comic.publisher {
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(comic.publisherColor)
                            .frame(width: 8, height: 8)

                        Text(publisher)
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.secondary)
                    }
                }

                HStack(spacing: Spacing.md) {
                    // Status badge
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: comic.status.icon)
                            .font(.system(size: 10))
                        Text(comic.status.rawValue)
                            .font(Typography.label)
                    }
                    .foregroundColor(comic.status.color)

                    // Progress
                    if comic.totalPages > 0 {
                        Text("\(comic.currentPage)/\(comic.totalPages) pages")
                            .font(Typography.label)
                            .foregroundColor(TextColors.tertiary)
                    }

                    // File size
                    Text(comic.fileSizeFormatted)
                        .font(Typography.label)
                        .foregroundColor(TextColors.tertiary)
                }
            }

            Spacer()

            // Actions
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(TextColors.tertiary)
        }
        .padding(Spacing.lg)
        .background(isHovered ? BackgroundColors.secondary : BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? BorderColors.regular : BorderColors.subtle, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Placeholder Thumbnail
    private var placeholderThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [BackgroundColors.secondary, BackgroundColors.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: comic.fileType.icon)
                .font(.system(size: 24))
                .foregroundColor(TextColors.tertiary)
        }
        .frame(width: 60, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Selection Checkbox
struct SelectionCheckbox: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? AccentColors.primary : BackgroundColors.elevated)
                .frame(width: 28, height: 28)

            Circle()
                .stroke(isSelected ? AccentColors.primary : BorderColors.regular, lineWidth: 2)
                .frame(width: 28, height: 28)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    var icon: String? = nil
    var color: Color? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }

                Text(title)
                    .font(Typography.bodySmall)
            }
            .foregroundColor(isSelected ? (color ?? AccentColors.primary) : TextColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                isSelected
                    ? (color ?? AccentColors.primary).opacity(0.12) : BackgroundColors.elevated
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? (color ?? AccentColors.primary) : BorderColors.subtle,
                        lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Badge
struct FilterBadge: View {
    let title: String
    var icon: String? = nil
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
            }

            Text(title)
                .font(Typography.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(TextColors.tertiary)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(TextColors.primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(AccentColors.primary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AccentColors.primary.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    LibraryView(viewModel: LibraryViewModel(database: DatabaseManager.shared))
}
