//
//  LibraryView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @State private var selectedComic: Comic?
    @State private var sortOption: SortOption = .dateAdded
    @State private var filterStatus: Comic.Status? = nil
    @State private var filterPublisher: String? = nil
    @State private var showingFilters = false
    @State private var isSelectionMode = false
    @State private var selectedComics: Set<Comic.ID> = []
    @State private var showingReader = false
    @State private var comicToRead: Comic?
    @State private var showingFilePicker = false
    @State private var importedFileURLs: [URL] = []
    @State private var isDropTargeted = false
    
    enum ViewMode {
        case grid, list
    }
    
    enum SortOption: String, CaseIterable {
        case title = "Title (A-Z)"
        case dateAdded = "Date Added"
        case dateModified = "Recently Modified"
        case publisher = "Publisher"
        case year = "Publication Year"
        case rating = "Rating"
        
        var icon: String {
            switch self {
            case .title: return "textformat"
            case .dateAdded: return "calendar.badge.plus"
            case .dateModified: return "calendar.badge.clock"
            case .publisher: return "building.2"
            case .year: return "calendar"
            case .rating: return "star"
            }
        }
    }
    
    var filteredAndSortedComics: [Comic] {
        var result = viewModel.comics
        
        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { comic in
                comic.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                comic.publisher?.localizedCaseInsensitiveContains(searchText) == true ||
                comic.series?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Apply status filter
        if let status = filterStatus {
            result = result.filter { $0.status == status }
        }
        
        // Apply publisher filter
        if let publisher = filterPublisher {
            result = result.filter { $0.publisher == publisher }
        }
        
        // Apply sorting
        switch sortOption {
        case .title:
            result.sort { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
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
        }
        
        return result
    }
    
    var publishers: [String] {
        Array(Set(viewModel.comics.compactMap { $0.publisher })).sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
            
            Divider()
                .background(BorderColors.subtle)
            
            // Content
            if viewMode == .grid {
                gridView
            } else {
                listView
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
        #if os(macOS)
        .sheet(isPresented: $showingReader) {
            if let comic = comicToRead {
                ComicReaderView(comic: comic)
                    .frame(minWidth: 1200, minHeight: 800)
            }
        }
        #else
        .fullScreenCover(isPresented: $showingReader) {
            if let comic = comicToRead {
                ComicReaderView(comic: comic)
            }
        }
        #endif
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.zip, .pdf],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
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
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Library")
                        .font(Typography.h1)
                        .foregroundColor(TextColors.primary)
                    
                    Text("Browse your collection of \(filteredAndSortedComics.count) comics")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                }
                
                Spacer()
                
                // Selection mode controls
                if isSelectionMode {
                    HStack(spacing: Spacing.md) {
                        Text("\(selectedComics.count) selected")
                            .font(Typography.body)
                            .foregroundColor(TextColors.secondary)
                        
                        Button("Cancel") {
                            isSelectionMode = false
                            selectedComics.removeAll()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(TextColors.secondary)
                    }
                } else {
                    // Add Comics button
                    Button(action: {
                        showingFilePicker = true
                    }) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "plus")
                            Text("Add Comics")
                                .font(Typography.button)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(AccentColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Search and toolbar
            HStack(spacing: Spacing.md) {
                // Search bar
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
                .frame(maxWidth: .infinity)
                
                // Sort menu
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
                
                // Filter button
                Button(action: { showingFilters.toggle() }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Filters")
                            .font(Typography.bodySmall)
                        if filterStatus != nil || filterPublisher != nil {
                            Circle()
                                .fill(AccentColors.primary)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .foregroundColor(showingFilters ? AccentColors.primary : TextColors.secondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(showingFilters ? AccentColors.primary.opacity(0.12) : BackgroundColors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                
                // Selection mode button
                if !isSelectionMode {
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
                }
                
                // View mode toggle
                HStack(spacing: Spacing.sm) {
                    Button(action: { viewMode = .grid }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 16))
                            .foregroundColor(viewMode == .grid ? AccentColors.primary : TextColors.secondary)
                            .frame(width: 32, height: 32)
                            .background(viewMode == .grid ? AccentColors.primary.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { viewMode = .list }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16))
                            .foregroundColor(viewMode == .list ? AccentColors.primary : TextColors.secondary)
                            .frame(width: 32, height: 32)
                            .background(viewMode == .list ? AccentColors.primary.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Filter chips (shown when filters are active)
            if showingFilters {
                filterView
            }
        }
        .padding(Spacing.xl)
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
                        isSelected: filterStatus == nil,
                        action: { filterStatus = nil }
                    )
                    
                    ForEach(Comic.Status.allCases, id: \.self) { status in
                        FilterChip(
                            title: status.rawValue,
                            icon: status.icon,
                            color: status.color,
                            isSelected: filterStatus == status,
                            action: { filterStatus = status }
                        )
                    }
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
            
            // Clear all filters
            if filterStatus != nil || filterPublisher != nil {
                Button(action: {
                    filterStatus = nil
                    filterPublisher = nil
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
                                .onTapGesture {
                                    if isSelectionMode {
                                        toggleSelection(for: comic.id)
                                    } else {
                                        openReader(for: comic)
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
                        .stroke(AccentColors.primary, style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
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
                                .onTapGesture {
                                    if isSelectionMode {
                                        toggleSelection(for: comic.id)
                                    } else {
                                        openReader(for: comic)
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
                        .stroke(AccentColors.primary, style: StrokeStyle(lineWidth: 3, dash: [10, 5]))
                        .background(AccentColors.primary.opacity(0.1))
                        .padding(Spacing.xl)
                }
            }
        )
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
    
    private func openReader(for comic: Comic) {
        print("\n🎯 [LibraryView] User tapped comic: \(comic.fileName)")
        print("🎯 [LibraryView] File type: \(comic.fileType.rawValue)")
        print("🎯 [LibraryView] Has bookmark: \(comic.bookmarkData != nil)")
        print("🎯 [LibraryView] Setting comicToRead and showingReader = true")
        comicToRead = comic
        showingReader = true
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
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (urlData, error) in
                defer { group.leave() }
                
                if let error = error {
                    print("Error loading item: \(error)")
                    return
                }
                
                if let urlData = urlData as? Data,
                   let urlString = String(data: urlData, encoding: .utf8),
                   let url = URL(string: urlString) {
                    
                    let fileExtension = url.pathExtension.lowercased()
                    if fileExtension == "cbz" || fileExtension == "pdf" || fileExtension == "zip" {
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
                        if let url = try await provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) as? URL {
                            let fileExtension = url.pathExtension.lowercased()
                            if fileExtension == "cbz" || fileExtension == "pdf" || fileExtension == "zip" {
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
                isSelected ?
                (color ?? AccentColors.primary).opacity(0.12) :
                BackgroundColors.elevated
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? (color ?? AccentColors.primary) : BorderColors.subtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LibraryView()
}

