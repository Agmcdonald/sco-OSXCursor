//
//  LibraryPublisherBrowseView.swift
//  SCO-OSXCursor
//
//  Publisher → series → issues hierarchy browse, extracted from LibraryView
//  (Stage 4 split). Owns its own expand/collapse state.
//

import SwiftUI

struct LibraryPublisherBrowseView: View {
    let publisherGroups: [PublisherGroup]
    let isSelectionMode: Bool
    let selectedComics: Set<Comic.ID>
    let focusedComicID: Comic.ID?
    /// Target cover width for the inline series grids (scaled down from the
    /// main grid's cover size so nested grids feel subordinate).
    let coverSize: Double
    let actions: ComicCellActions
    let emptyState: LibraryEmptyStateView

    // Publisher/Series expand state
    @State private var expandedPublishers: Set<String> = []
    @State private var expandedSeries: Set<String> = []

    var body: some View {
        ScrollView {
            if publisherGroups.isEmpty {
                emptyState
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
                if let firstComic = group.comics.first,
                    let coverData = firstComic.coverImageData,
                    let cover = PageImageCache.shared.coverImage(
                        from: coverData, cacheKey: firstComic.id.uuidString)
                {
                    #if os(macOS)
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    #else
                        Image(uiImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
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
                columns: [
                    GridItem(
                        .adaptive(minimum: coverSize, maximum: coverSize * 1.35),
                        spacing: Spacing.lg
                    )
                ],
                spacing: Spacing.lg
            ) {
                ForEach(group.comics) { comic in
                    ZStack(alignment: .topLeading) {
                        ComicCardView(comic: comic)
                            .comicCellInteraction(
                                comic: comic,
                                isSelectionMode: isSelectionMode,
                                isFocused: focusedComicID == comic.id,
                                showsRegenerate: false,
                                actions: actions
                            )

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
}
