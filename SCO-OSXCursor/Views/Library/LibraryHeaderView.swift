//
//  LibraryHeaderView.swift
//  SCO-OSXCursor
//
//  Library header: title row (with selection bar / add buttons), search +
//  toolbar row (sort, filters, select, cover-size slider, view toggle),
//  active-filter badges, and the filter panel. Extracted from LibraryView
//  (Stage 4 split).
//

import SwiftUI

struct LibraryHeaderView: View {
    // View state
    @Binding var viewMode: LibraryViewMode
    @Binding var searchText: String
    /// Focus for the search field, owned by LibraryView so its key shortcuts
    /// (Space/Return open reader) can stand down while the user is typing.
    var searchFieldFocus: FocusState<Bool>.Binding
    @Binding var sortOption: LibrarySortOption
    @Binding var filters: LibraryFilters
    @Binding var showingFilters: Bool
    @Binding var coverSize: Double

    // Selection state
    @Binding var isSelectionMode: Bool
    @Binding var selectedComics: Set<Comic.ID>

    // Inspector (macOS)
    @Binding var isInspectorPresented: Bool
    let hasFocusedComic: Bool

    // Data for subtitle, select-all, and the filter panel
    let visibleComicIDs: [Comic.ID]
    let visibleComicsCount: Int
    let publisherCount: Int
    let publishers: [String]
    let series: [String]
    let years: [Int]

    // Folder scope subtitle (option B)
    let currentFolderName: String?
    let totalLibraryCount: Int
    let folderViewCount: Int

    // Actions
    let onQuickAdd: () -> Void
    let onAddComicsOrganize: (() -> Void)?
    let onMarkAsRead: () -> Void
    var onMarkAsUnread: () -> Void = {}
    let onEditFields: () -> Void
    let onAddToList: () -> Void
    let onRegenerateCovers: () -> Void
    let onFetchMetadata: () -> Void
    let onDelete: () -> Void
    var isFetchingMetadata: Bool = false

    // Folders (bulk move from the selection bar)
    var folders: [Folder] = []
    var onAddToFolder: (UUID) -> Void = { _ in }
    var onNewFolderForSelection: () -> Void = {}
    /// Package the selection as .scobook files for AirDrop (macOS-only in v1).
    var onSendToDevice: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            titleRow

            // Search and toolbar
            HStack(spacing: Spacing.md) {
                // Search bar
                searchBar
                    .frame(maxWidth: .infinity)

                #if os(macOS)
                    // macOS: Show all controls (plenty of space)
                    sortMenu
                    // Filters / Select / Info don't apply to the folder view
                    if viewMode != .folders {
                        filtersButton
                        if !isSelectionMode {
                            selectButton
                        }
                    }
                    if viewMode == .grid || viewMode == .publisher || viewMode == .folders {
                        coverSizeSlider
                            .frame(width: 140)
                    }
                    // Info (ⓘ) button — enabled when a comic is focused
                    if viewMode != .folders {
                        Button(action: {
                            if hasFocusedComic {
                                isInspectorPresented.toggle()
                            }
                        }) {
                            Image(
                                systemName: isInspectorPresented
                                    ? "info.circle.fill" : "info.circle"
                            )
                            .font(.system(size: 16))
                            .foregroundColor(
                                hasFocusedComic ? AccentColors.primary : TextColors.tertiary
                            )
                            .frame(width: 32, height: 32)
                            .background(
                                isInspectorPresented
                                    ? AccentColors.primary.opacity(0.12) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasFocusedComic)
                        .help(
                            !hasFocusedComic
                                ? "Select a comic to view info"
                                : (isInspectorPresented ? "Hide Info" : "Show Info"))
                    }
                    viewModeToggle
                #else
                    // iPad/iOS: Filters get their own always-visible button —
                    // burying them in the "…" menu made a two-tap trip out of
                    // the most-used control. The rest stays in the More menu.
                    if viewMode != .folders {
                        compactFiltersButton
                    }
                    moreMenu
                    if viewMode == .grid || viewMode == .publisher || viewMode == .folders {
                        coverSizeSlider
                            .frame(width: 120)
                    }
                    viewModeToggle
                #endif
            }

            // Active filter badges (always visible when filters applied)
            if filters.hasActive && !showingFilters {
                LibraryFilterBadgesRow(filters: $filters)
            }

            // Filter panel (shown when filters button is clicked)
            if showingFilters {
                LibraryFilterPanel(
                    filters: $filters,
                    publishers: publishers,
                    series: series,
                    years: years
                )
            }
        }
        .padding(Spacing.xl)
    }

    // MARK: - Title Row

    private var titleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Library")
                    .font(Typography.h1)
                    .foregroundColor(TextColors.primary)

                if viewMode == .folders {
                    Text("\(folderViewCount) folder\(folderViewCount == 1 ? "" : "s")")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                } else if viewMode == .publisher {
                    Text(
                        "\(publisherCount) publisher\(publisherCount == 1 ? "" : "s") • \(visibleComicsCount) comics"
                    )
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)
                } else if let folderName = currentFolderName {
                    Text("\(visibleComicsCount) of \(totalLibraryCount) in \(folderName)")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                } else {
                    Text("Browse your collection of \(visibleComicsCount) comics")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                }
            }

            Spacer()

            // Selection mode controls
            if isSelectionMode {
                // iPad portrait: not enough width beside the title for all
                // controls — scroll horizontally instead of crushing labels
                #if os(iOS)
                    ScrollView(.horizontal, showsIndicators: false) {
                        selectionBar
                    }
                #else
                    selectionBar
                #endif
            } else {
                HStack(spacing: Spacing.md) {
                    // Quick Add button
                    Button(action: onQuickAdd) {
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
                                Text("Organize & Add Books")
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
    }

    private var selectionBar: some View {
        LibrarySelectionBar(
            selectedComics: $selectedComics,
            visibleComicIDs: visibleComicIDs,
            onMarkAsRead: onMarkAsRead,
            onMarkAsUnread: onMarkAsUnread,
            onEditFields: onEditFields,
            onAddToList: onAddToList,
            onRegenerateCovers: onRegenerateCovers,
            onFetchMetadata: onFetchMetadata,
            onDelete: onDelete,
            onCancel: {
                isSelectionMode = false
                selectedComics.removeAll()
            },
            isFetchingMetadata: isFetchingMetadata,
            folders: folders,
            onAddToFolder: onAddToFolder,
            onNewFolder: onNewFolderForSelection,
            onSendToDevice: onSendToDevice
        )
    }

    // MARK: - Toolbar Components

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(TextColors.tertiary)

            TextField("Search comics, series, publisher...", text: $searchText)
                .focused(searchFieldFocus)
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
            ForEach(LibrarySortOption.allCases, id: \.self) { option in
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
                if filters.hasActive {
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

    /// Cover size slider — drives the grid's column width, so dragging it
    /// smoothly rescales covers (rows stay level because every card shares
    /// the same fixed-height info area).
    private var coverSizeSlider: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "square.grid.4x3.fill")
                .font(.system(size: 11))
                .foregroundColor(TextColors.tertiary)

            Slider(
                value: $coverSize,
                in: LibraryCoverSize.minimum...LibraryCoverSize.maximum
            )

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 15))
                .foregroundColor(TextColors.tertiary)
        }
        .help("Adjust cover size")
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

            Button(action: { viewMode = .folders }) {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundColor(
                        viewMode == .folders ? AccentColors.primary : TextColors.secondary
                    )
                    .frame(width: 32, height: 32)
                    .background(
                        viewMode == .folders ? AccentColors.primary.opacity(0.12) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Folder View")
        }
    }

    /// iPad/iOS: one-tap filter toggle (was buried in the More menu).
    /// Fills and tints while the panel is open or any filter is active.
    private var compactFiltersButton: some View {
        Button(action: { withAnimation { showingFilters.toggle() } }) {
            Image(
                systemName: (showingFilters || filters.hasActive)
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .font(.system(size: 20))
            .foregroundColor(
                (showingFilters || filters.hasActive)
                    ? AccentColors.primary : TextColors.secondary
            )
            .frame(width: 44, height: 44)
            .background(
                showingFilters
                    ? AccentColors.primary.opacity(0.12) : BackgroundColors.elevated
            )
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Filters")
    }

    private var moreMenu: some View {
        Menu {
            // Sort section
            Section("Sort By") {
                ForEach(LibrarySortOption.allCases, id: \.self) { option in
                    Button(action: { sortOption = option }) {
                        Label(
                            option.rawValue,
                            systemImage: sortOption == option ? "checkmark" : option.icon)
                    }
                }
            }

            // Actions section (Filters moved to its own toolbar button)
            Section {
                if !isSelectionMode && viewMode != .folders {
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
}
