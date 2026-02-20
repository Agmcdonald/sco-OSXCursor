import SwiftUI

struct DashboardReadingView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    @State private var selectedSubTab: SubTab = .readingList
    @State private var searchText: String = ""
    @State private var showCompleted: Bool = false

    enum SubTab: String, CaseIterable {
        case readingList  = "Reading List"
        case recentlyRead = "Recently Read"
    }

    // MARK: - Computed Lists

    /// Comics explicitly added to the reading list via context menu
    private var readingListComics: [Comic] {
        libraryViewModel.comics
            .filter { $0.isOnReadingList }
            .sorted { ($0.lastReadDate ?? $0.dateAdded) > ($1.lastReadDate ?? $1.dateAdded) }
    }

    /// Last 15 comics the user actually opened
    private var recentlyRead: [Comic] {
        libraryViewModel.comics
            .filter { $0.lastReadDate != nil }
            .sorted { $0.lastReadDate! > $1.lastReadDate! }
            .prefix(15)
            .map { $0 }
    }

    private var readingListFiltered: [Comic] {
        let base = showCompleted ? readingListComics : readingListComics.filter { $0.status != .completed }
        if searchText.isEmpty { return base }
        return base.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    private var recentlyReadFiltered: [Comic] {
        if searchText.isEmpty { return recentlyRead }
        return recentlyRead.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            DashboardSectionCard(
                title: "Reading & Recently Read",
                subtitle: "Track comics you want to read and rate the ones you've finished"
            ) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Key metrics row
                        HStack(spacing: Spacing.xl) {
                            ReadingMetric(
                                value: "\(readingListComics.count)",
                                label: "On List",
                                color: AccentColors.primary
                            )
                            ReadingMetric(
                                value: "\(readingListComics.filter { $0.status == .completed }.count)",
                                label: "Completed",
                                color: .green
                            )
                            ReadingMetric(
                                value: "\(recentlyRead.filter { Calendar.current.isDateInLastWeek($0.lastReadDate ?? .distantPast) }.count)",
                                label: "This Week",
                                color: .orange
                            )
                        }

                        // Sub-tab selector — full-width hit targets
                        HStack(spacing: 0) {
                            ForEach(SubTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue)
                                    .font(Typography.bodySmall)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Spacing.sm)
                                    .background(
                                        selectedSubTab == tab
                                            ? AccentColors.primary : Color.clear
                                    )
                                    .foregroundColor(
                                        selectedSubTab == tab ? .white : TextColors.secondary
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedSubTab = tab }
                            }
                        }
                        .padding(3)
                        .background(BackgroundColors.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        // Search + filter bar
                        HStack {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(TextColors.tertiary)
                                TextField(
                                    selectedSubTab == .readingList
                                        ? "Search reading list…" : "Search recently read…",
                                    text: $searchText
                                )
                                .textFieldStyle(.plain)
                                .font(Typography.bodySmall)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(BackgroundColors.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            if selectedSubTab == .readingList {
                                Toggle("Show completed", isOn: $showCompleted)
                                    .toggleStyle(.checkbox)
                                    .font(Typography.caption)
                                    .foregroundColor(TextColors.secondary)
                            }
                        }

                        // List content
                        let items = selectedSubTab == .readingList
                            ? readingListFiltered : recentlyReadFiltered

                        if items.isEmpty {
                            VStack(spacing: Spacing.sm) {
                                Image(systemName: selectedSubTab == .readingList ? "bookmark.slash" : "book.closed")
                                    .font(.system(size: 36))
                                    .foregroundColor(TextColors.tertiary)

                                if selectedSubTab == .readingList {
                                    Text("Your reading list is empty")
                                        .font(Typography.bodySmall)
                                        .foregroundColor(TextColors.secondary)
                                    Text("Right-click any comic in your Library and choose Add to Reading List")
                                        .font(Typography.caption)
                                        .foregroundColor(TextColors.tertiary)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("No recently read comics")
                                        .font(Typography.bodySmall)
                                        .foregroundColor(TextColors.secondary)
                                    Text("Start reading a comic to see your history here")
                                        .font(Typography.caption)
                                        .foregroundColor(TextColors.tertiary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xl)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(items) { comic in
                                    ReadingListRow(
                                        comic: comic,
                                        onRemove: selectedSubTab == .readingList
                                            ? { libraryViewModel.toggleReadingList(comic) }
                                            : nil
                                    )
                                    if comic.id != items.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("\(readingListComics.filter { $0.status != .completed }.count)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(TextColors.primary)
                        Text("to read")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Helper Views

struct ReadingMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReadingListRow: View {
    let comic: Comic
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Cover thumbnail placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(BackgroundColors.secondary)
                .frame(width: 32, height: 44)
                .overlay(
                    Image(systemName: "book.closed")
                        .font(.system(size: 14))
                        .foregroundColor(TextColors.tertiary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(comic.displayName)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(1)
                if let series = comic.series, !series.isEmpty, series != comic.displayName {
                    Text(series)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Progress bar for in-progress comics
            if comic.totalPages > 0 && comic.currentPage > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: comic.progress)
                        .progressViewStyle(.linear)
                        .tint(AccentColors.primary)
                        .frame(width: 60)
                    Text(comic.progressPercentage)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }
            }

            // Status badge
            Text(comic.status.rawValue)
                .font(Typography.caption)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
                .background(comic.status.color.opacity(0.15))
                .foregroundColor(comic.status.color)
                .clipShape(Capsule())

            // Remove button (reading list only)
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AccentColors.primary)
                }
                .buttonStyle(.plain)
                .help("Remove from Reading List")
            }
        }
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .contextMenu {
            if let onRemove = onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove from Reading List", systemImage: "bookmark.slash")
                }
            }
        }
    }
}

// MARK: - Calendar extension helper

extension Calendar {
    fileprivate func isDateInLastWeek(_ date: Date) -> Bool {
        guard let weekAgo = self.date(byAdding: .day, value: -7, to: Date()) else { return false }
        return date > weekAgo
    }
}
