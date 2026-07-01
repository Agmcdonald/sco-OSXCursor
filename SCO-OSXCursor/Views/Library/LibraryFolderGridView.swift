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
    /// The single member book chosen to represent a folder, if any (and still
    /// present in the library). nil when the folder uses a picture or collage.
    let coverComic: (Folder) -> Comic?
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
    /// Cover actions (right-click "Set Cover" submenu).
    let onChoosePicture: (Folder) -> Void
    /// Pick a cover from the Photos library (iPad/iPhone only).
    let onChoosePhoto: (Folder) -> Void
    let onPickBook: (Folder) -> Void
    let onResetCover: (Folder) -> Void

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
                        previewComics: previewComics(folder.id),
                        coverComic: coverComic(folder)
                    )
                    .onTapGesture { onOpen(folder) }
                    .contextMenu {
                        Button { onOpen(folder) } label: {
                            Label("Open", systemImage: "folder")
                        }
                        Button { onRename(folder) } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Menu {
                            #if os(iOS)
                                Button { onChoosePhoto(folder) } label: {
                                    Label("Choose from Photos…", systemImage: "photo.stack")
                                }
                                Button { onChoosePicture(folder) } label: {
                                    Label("Choose from Files…", systemImage: "folder")
                                }
                            #else
                                Button { onChoosePicture(folder) } label: {
                                    Label("Choose Picture…", systemImage: "photo")
                                }
                            #endif
                            Button { onPickBook(folder) } label: {
                                Label("Pick a Book…", systemImage: "book.closed")
                            }
                            if folder.coverImageData != nil || folder.coverComicID != nil {
                                Divider()
                                Button { onResetCover(folder) } label: {
                                    Label("Use Book Collage", systemImage: "square.grid.2x2")
                                }
                            }
                        } label: {
                            Label("Set Cover", systemImage: "photo.on.rectangle.angled")
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
    /// The chosen representative book, if the folder uses one and it still exists.
    var coverComic: Comic? = nil

    var body: some View {
        FolderCardShell(title: folder.name, bookCount: bookCount) {
            cover
        }
    }

    /// Cover precedence: custom picture → chosen book → default 2×2 collage.
    @ViewBuilder
    private var cover: some View {
        switch folder.coverStyle {
        case .picture:
            SingleImageCover(
                imageData: folder.coverImageData,
                cacheKey: "folder-\(folder.id.uuidString)",
                placeholderSystemImage: "folder"
            )
        case .book:
            // Use the resolved book cover; if the book was removed, fall back to
            // the collage so the card is never blank.
            if let comic = coverComic, comic.coverImageData != nil {
                SingleImageCover(
                    imageData: comic.coverImageData,
                    cacheKey: comic.id.uuidString,
                    placeholderSystemImage: "folder"
                )
            } else {
                CoverCollage(previewComics: previewComics, placeholderSystemImage: "folder")
            }
        case .collage:
            CoverCollage(previewComics: previewComics, placeholderSystemImage: "folder")
        }
    }
}

// MARK: - Single Image Cover (picture or chosen book)

/// Fills the 2:3 cover area with a single image (cropped), matching how book
/// covers fill cells in the collage. Used for custom folder pictures and for a
/// folder's chosen representative book.
@MainActor
struct SingleImageCover: View {
    let imageData: Data?
    let cacheKey: String
    var placeholderSystemImage: String = "folder"

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [BackgroundColors.secondary, BackgroundColors.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let data = imageData,
                    let image = PageImageCache.shared.coverImage(from: data, cacheKey: cacheKey)
                {
                    #if os(macOS)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    #else
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    #endif
                } else {
                    Image(systemName: placeholderSystemImage)
                        .font(.system(size: 40))
                        .foregroundColor(TextColors.tertiary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
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

// MARK: - Cover Book Picker

/// Sheet for choosing a single member book to represent a folder. Shows the
/// folder's books as a cover grid; tapping one assigns it and closes.
@MainActor
struct FolderCoverBookPicker: View {
    let folderName: String
    let books: [Comic]
    let selectedID: UUID?
    let onSelect: (Comic) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose Cover Book")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    Text(folderName)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Spacing.lg)

            Divider()

            if books.isEmpty {
                Spacer()
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 36))
                        .foregroundColor(TextColors.tertiary)
                    Text("This folder has no books yet.")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 110, maximum: 150), spacing: Spacing.lg)
                        ],
                        spacing: Spacing.lg
                    ) {
                        ForEach(books) { comic in
                            Button { onSelect(comic) } label: {
                                coverCell(comic)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(BackgroundColors.primary)
    }

    @ViewBuilder
    private func coverCell(_ comic: Comic) -> some View {
        let isSelected = comic.id == selectedID
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SingleImageCover(
                imageData: comic.coverImageData,
                cacheKey: comic.id.uuidString,
                placeholderSystemImage: "book.closed"
            )
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? AccentColors.primary : BorderColors.subtle,
                        lineWidth: isSelected ? 3 : 1)
            )

            Text(comic.displayName)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
