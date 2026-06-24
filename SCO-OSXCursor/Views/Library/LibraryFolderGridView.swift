//
//  LibraryFolderGridView.swift
//  SCO-OSXCursor
//
//  The "Folders" library view mode: a grid of collection cards. Two special
//  cards lead the grid — "All Books" (the whole library) and "Unfiled" (books
//  in no folder) — so loose books are always reachable from here. Each folder
//  card shows a 2×2 collage of member covers, its name, and a book count, and
//  honours the shared sort menu (LibraryQuery.sortFolders). Tapping a card
//  drills into that scope in the grid view; a trailing card creates a folder.
//

import SwiftUI

struct LibraryFolderGridView: View {
    /// Already sorted by the coordinator.
    let folders: [Folder]
    let count: (UUID) -> Int
    /// Up to four member comics for a folder's cover collage.
    let previewComics: (UUID) -> [Comic]
    /// Target card width in points (shares the library cover-size slider).
    let coverSize: Double

    // Special scopes
    let totalCount: Int
    let unfiledCount: Int
    let unfiledPreview: [Comic]
    let onOpenAll: () -> Void
    let onOpenUnfiled: () -> Void

    let onOpen: (Folder) -> Void
    let onRename: (Folder) -> Void
    let onDelete: (Folder) -> Void
    let onNewFolder: () -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: coverSize, maximum: coverSize * 1.35),
                        spacing: Spacing.xl
                    )
                ],
                spacing: Spacing.xxl
            ) {
                // Whole library
                SpecialFolderCardView(
                    title: "All Books",
                    systemImage: "books.vertical.fill",
                    bookCount: totalCount,
                    previewComics: []
                )
                .onTapGesture { onOpenAll() }

                // Books in no folder
                SpecialFolderCardView(
                    title: "Unfiled",
                    systemImage: "tray.fill",
                    bookCount: unfiledCount,
                    previewComics: unfiledPreview
                )
                .onTapGesture { onOpenUnfiled() }

                // Folders
                ForEach(folders) { folder in
                    FolderCardView(
                        folder: folder,
                        bookCount: count(folder.id),
                        previewComics: previewComics(folder.id)
                    )
                    .onTapGesture { onOpen(folder) }
                    .contextMenu {
                        Button { onOpen(folder) } label: {
                            Label("Open", systemImage: "folder")
                        }
                        Button { onRename(folder) } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) { onDelete(folder) } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    }
                }

                // New folder card
                NewFolderCardView()
                    .onTapGesture { onNewFolder() }
            }
            .padding(Spacing.xl)
        }
    }
}

// MARK: - Cover Collage (shared)

@MainActor
struct CoverCollage: View {
    let previewComics: [Comic]
    var placeholderSystemImage: String = "folder"

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 3
            let cellW = (geo.size.width - spacing) / 2
            let cellH = (geo.size.height - spacing) / 2

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [BackgroundColors.secondary, BackgroundColors.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if previewComics.isEmpty {
                    Image(systemName: placeholderSystemImage)
                        .font(.system(size: 40))
                        .foregroundColor(TextColors.tertiary)
                } else {
                    VStack(spacing: spacing) {
                        HStack(spacing: spacing) {
                            cell(at: 0, width: cellW, height: cellH)
                            cell(at: 1, width: cellW, height: cellH)
                        }
                        HStack(spacing: spacing) {
                            cell(at: 2, width: cellW, height: cellH)
                            cell(at: 3, width: cellW, height: cellH)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    @ViewBuilder
    private func cell(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        if index < previewComics.count,
            let data = previewComics[index].coverImageData,
            let image = PageImageCache.shared.coverImage(
                from: data, cacheKey: previewComics[index].id.uuidString)
        {
            #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            #else
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            #endif
        } else {
            Rectangle()
                .fill(BackgroundColors.secondary)
                .frame(width: width, height: height)
        }
    }
}

// MARK: - Card chrome (shared)

/// Common card layout: a cover area on top, then a fixed-height title + count
/// block so every card in a row is the same height.
private struct FolderCardShell<Cover: View>: View {
    let title: String
    let bookCount: Int
    @ViewBuilder let cover: () -> Cover

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            cover()
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: 44, alignment: .topLeading)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 11))
                        .foregroundColor(TextColors.tertiary)
                    Text("\(bookCount) book\(bookCount == 1 ? "" : "s")")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 16)
            }
        }
        .padding(Spacing.md)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHovered ? AccentColors.primary : BorderColors.subtle,
                    lineWidth: isHovered ? 2 : 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Folder Card

@MainActor
struct FolderCardView: View {
    let folder: Folder
    let bookCount: Int
    let previewComics: [Comic]

    var body: some View {
        FolderCardShell(title: folder.name, bookCount: bookCount) {
            CoverCollage(previewComics: previewComics, placeholderSystemImage: "folder")
        }
    }
}

// MARK: - Special Scope Card (All Books / Unfiled)

@MainActor
struct SpecialFolderCardView: View {
    let title: String
    let systemImage: String
    let bookCount: Int
    let previewComics: [Comic]

    var body: some View {
        FolderCardShell(title: title, bookCount: bookCount) {
            CoverCollage(previewComics: previewComics, placeholderSystemImage: systemImage)
        }
    }
}

// MARK: - New Folder Card

struct NewFolderCardView: View {
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AccentColors.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                AccentColors.primary.opacity(0.4),
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    )
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 34, weight: .light))
                    Text("New Folder")
                        .font(Typography.bodySmall)
                }
                .foregroundColor(AccentColors.primary)
            }
            .aspectRatio(2 / 3, contentMode: .fit)

            // Spacer block matching the card info area so heights line up.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(" ")
                    .font(Typography.h3)
                    .frame(height: 44)
                Text(" ")
                    .font(Typography.caption)
                    .frame(height: 16)
            }
        }
        .padding(Spacing.md)
        .background(BackgroundColors.elevated.opacity(isHovered ? 1 : 0.0))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
