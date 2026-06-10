//
//  LibraryListView.swift
//  SCO-OSXCursor
//
//  Row list for the library + ComicRowView, extracted from LibraryView
//  (Stage 4 split).
//

import SwiftUI

struct LibraryListView: View {
    let comics: [Comic]
    let isSelectionMode: Bool
    let selectedComics: Set<Comic.ID>
    let focusedComicID: Comic.ID?
    let actions: ComicCellActions
    let emptyState: LibraryEmptyStateView

    var body: some View {
        ScrollView {
            if comics.isEmpty {
                emptyState
            } else {
                VStack(spacing: Spacing.md) {
                    ForEach(comics) { comic in
                        HStack(spacing: 0) {
                            // Selection checkbox
                            if isSelectionMode {
                                SelectionCheckbox(isSelected: selectedComics.contains(comic.id))
                                    .padding(.trailing, Spacing.md)
                            }

                            ComicRowView(comic: comic)
                                .comicCellInteraction(
                                    comic: comic,
                                    isSelectionMode: isSelectionMode,
                                    isFocused: focusedComicID == comic.id,
                                    actions: actions
                                )
                        }
                    }
                }
                .padding(Spacing.xl)
            }
        }
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
