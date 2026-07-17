//
//  ComicCellModifiers.swift
//  SCO-OSXCursor
//
//  Shared per-comic cell behavior (focus ring, tap gestures, context menu,
//  selection checkbox), extracted from LibraryView (Stage 4 split). The grid,
//  list, and publisher views all repeated this verbatim — now it lives once.
//

import SwiftUI

// MARK: - Cell Actions

/// Closures a comic cell needs from the library coordinator.
struct ComicCellActions {
    let openReader: (Comic) -> Void
    let editComic: (Comic) -> Void
    let markAsRead: (Comic) -> Void
    let toggleReadingList: (Comic) -> Void
    let regenerateCover: (Comic) -> Void
    let delete: (Comic) -> Void
    let selectRange: (Comic) -> Void
    let handleSelectionTap: (Comic) -> Void
    let focus: (Comic) -> Void
    /// Fetch ComicVine metadata directly (no edit sheet) — fills and saves.
    var fetchMetadata: (Comic) -> Void = { _ in }
    /// Undo the last applied ComicVine fetch (shown only when a pre-fetch
    /// snapshot exists on the record).
    var revertMetadataFetch: (Comic) -> Void = { _ in }
    /// Mark unread / reset reading progress ("start over").
    var markAsUnread: (Comic) -> Void = { _ in }
    /// Show the read-only Info panel (inspector on macOS, half-sheet on iPad).
    var showInfo: (Comic) -> Void = { _ in }
    /// Re-link a missing/moved file (shown only when the book needs attention).
    var relink: (Comic) -> Void = { _ in }
    /// Package this book as a .scobook and hand it to the share sheet.
    /// Offered on every platform — transfer runs Mac → iPad and
    /// iPad/iPhone → Mac.
    var sendToDevice: (Comic) -> Void = { _ in }
    /// Toggle the opt-in PDFKit book reader for a single PDF.
    var togglePDFReadAsBook: (Comic) -> Void = { _ in }

    // MARK: Folders
    /// All user folders (for the "Add to Folder" submenu).
    var folders: [Folder] = []
    /// Display name for a folder in menus — full path for nested folders
    /// ("Marvel › Events"), plain name for top-level ones.
    var folderDisplayName: (Folder) -> String = { $0.name }
    /// Folders a given comic currently belongs to (drives checkmarks + reveal).
    var foldersContaining: (Comic) -> [Folder] = { _ in [] }
    /// Add a single comic to a folder.
    var addToFolder: (Comic, UUID) -> Void = { _, _ in }
    /// Remove a single comic from a folder.
    var removeFromFolder: (Comic, UUID) -> Void = { _, _ in }
    /// Add the whole current selection to a folder (selection mode).
    var addSelectionToFolder: (UUID) -> Void = { _ in }
    /// Prompt for a new folder name, then add this comic to it.
    var requestNewFolderForComic: (Comic) -> Void = { _ in }
    /// Prompt for a new folder name, then add the current selection to it.
    var requestNewFolderForSelection: () -> Void = {}
    /// Navigate the library scope to a folder containing this comic, then
    /// focus + scroll to the book so it's highlighted where it lives.
    var revealInFolder: (UUID, Comic) -> Void = { _, _ in }
}

// MARK: - Folder Chip Badge

/// Small "lives in: <folder>" capsule shown on cells while searching. Tapping
/// it jumps the library scope to that folder and highlights the book — search
/// finds it, the chip takes you to where it lives.
struct FolderChipBadge: View {
    let folder: Folder
    /// Extra folders beyond the first (shown as "+n").
    var extraCount: Int = 0
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Image(systemName: folder.icon ?? "folder")
                    .font(.system(size: 9, weight: .semibold))
                Text(extraCount > 0 ? "\(folder.name) +\(extraCount)" : folder.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Reveal in \(folder.name)")
    }
}

// MARK: - Cell Interaction Modifier

/// Focus ring + platform tap gestures + context menu for a comic cell.
struct ComicCellInteraction: ViewModifier {
    let comic: Comic
    let isSelectionMode: Bool
    let isFocused: Bool
    /// The publisher view's inline grid omits the Regenerate Cover item.
    var showsRegenerate: Bool = true
    let actions: ComicCellActions

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isFocused ? AccentColors.primary : Color.clear, lineWidth: 3)
            )
            #if os(macOS)
            .onTapGesture(count: 2) {
                if !isSelectionMode {
                    actions.openReader(comic)
                }
            }
            .onTapGesture(count: 1) {
                if isSelectionMode {
                    actions.handleSelectionTap(comic)
                } else {
                    actions.focus(comic)
                }
            }
            #else
            .onTapGesture {
                if isSelectionMode {
                    actions.handleSelectionTap(comic)
                } else {
                    actions.openReader(comic)
                }
            }
            #endif
            // iPad: long-press shows a large zoomed cover above the menu.
            // macOS context menus don't support previews, so use the plain form.
            #if os(iOS)
            .contextMenu {
                menuContent
            } preview: {
                ComicCoverPreview(comic: comic)
            }
            #else
            .contextMenu {
                menuContent
            }
            #endif
    }

    // MARK: - Menu Content

    @ViewBuilder
    private var menuContent: some View {
        // Range selection without a keyboard (iPad):
        // tap one book, long-press another, select the span
        if isSelectionMode {
            Button(action: { actions.selectRange(comic) }) {
                Label("Select Range to Here", systemImage: "checklist")
            }
        }

        // Recovery for a missing/moved file.
        if comic.needsAttention {
            Button(action: { actions.relink(comic) }) {
                Label("Locate File…", systemImage: "folder.badge.questionmark")
            }
            Divider()
        }

        Button(action: { actions.openReader(comic) }) {
            Label("Read", systemImage: "book.fill")
        }

        if comic.fileType == .pdf {
            Button(action: { actions.togglePDFReadAsBook(comic) }) {
                Label(
                    comic.pdfReadsAsBook ? "Open PDF as Comic" : "Open PDF as Book",
                    systemImage: comic.pdfReadsAsBook ? "rectangle.stack" : "doc.richtext"
                )
            }
        }

        Button(action: { actions.showInfo(comic) }) {
            Label("Show Info", systemImage: "info.circle")
        }

        Button(action: { actions.editComic(comic) }) {
            Label("Edit Metadata", systemImage: "pencil")
        }

        // EPUB books fetch from Open Library / Google Books; comics from
        // ComicVine. Same action — LibraryView routes by file type.
        Button(action: { actions.fetchMetadata(comic) }) {
            if comic.isEbook {
                Label("Fetch Book Metadata", systemImage: "books.vertical")
            } else {
                Label("Fetch from ComicVine", systemImage: "network")
            }
        }

        // Escape hatch for a wrong match — only offered while a pre-fetch
        // snapshot is stored on the record.
        if comic.metadataBackup != nil {
            Button(action: { actions.revertMetadataFetch(comic) }) {
                Label(
                    comic.isEbook ? "Revert Metadata Fetch" : "Revert ComicVine Fetch",
                    systemImage: "arrow.uturn.backward")
            }
        }

        Button(action: { actions.markAsRead(comic) }) {
            Label("Mark as Read", systemImage: "checkmark.circle")
        }

        // "Start over" — only meaningful once there's some reading state.
        if comic.status != .unread || comic.currentPage > 0 || comic.lastReadDate != nil {
            Button(action: { actions.markAsUnread(comic) }) {
                Label("Mark as Unread", systemImage: "book.closed")
            }
        }

        Button(action: { actions.toggleReadingList(comic) }) {
            Label(
                comic.isOnReadingList
                    ? "Remove from Reading List"
                    : "Add to Reading List",
                systemImage: comic.isOnReadingList
                    ? "bookmark.slash" : "bookmark"
            )
        }

        if showsRegenerate {
            Button(action: { actions.regenerateCover(comic) }) {
                Label("Regenerate Cover", systemImage: "arrow.clockwise.circle")
            }
        }

        // Transfer runs both ways: Mac → iPad and iPad/iPhone → Mac. A book
        // that needs attention has no readable file to package.
        if !comic.needsAttention {
            Button(action: { actions.sendToDevice(comic) }) {
                Label("Send to Device…", systemImage: "ipad.and.arrow.forward")
            }
        }

        Divider()

        folderMenu

        Divider()

        Button(role: .destructive, action: { actions.delete(comic) }) {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Folder Submenu

    @ViewBuilder
    private var folderMenu: some View {
        if isSelectionMode {
            // Bulk: add every selected book to a folder.
            Menu {
                ForEach(actions.folders) { folder in
                    Button {
                        actions.addSelectionToFolder(folder.id)
                    } label: {
                        Label(folder.name, systemImage: folder.icon ?? "folder")
                    }
                }
                if !actions.folders.isEmpty { Divider() }
                Button {
                    actions.requestNewFolderForSelection()
                } label: {
                    Label("New Folder…", systemImage: "plus")
                }
            } label: {
                Label("Add Selected to Folder", systemImage: "folder.badge.plus")
            }
        } else {
            let containing = actions.foldersContaining(comic)

            // Add to / remove from a folder. A checkmark marks current membership.
            Menu {
                ForEach(actions.folders) { folder in
                    let isIn = containing.contains(where: { $0.id == folder.id })
                    Button {
                        if isIn {
                            actions.removeFromFolder(comic, folder.id)
                        } else {
                            actions.addToFolder(comic, folder.id)
                        }
                    } label: {
                        Label(
                            actions.folderDisplayName(folder),
                            systemImage: isIn ? "checkmark" : (folder.icon ?? "folder"))
                    }
                }
                if !actions.folders.isEmpty { Divider() }
                Button {
                    actions.requestNewFolderForComic(comic)
                } label: {
                    Label("New Folder…", systemImage: "plus")
                }
            } label: {
                Label("Add to Folder", systemImage: "folder.badge.plus")
            }

            // Jump the library scope to a folder this book lives in.
            if !containing.isEmpty {
                Menu {
                    ForEach(containing) { folder in
                        Button {
                            actions.revealInFolder(folder.id, comic)
                        } label: {
                            Label(
                                actions.folderDisplayName(folder),
                                systemImage: folder.icon ?? "folder")
                        }
                    }
                } label: {
                    Label("Reveal in Folder", systemImage: "folder")
                }
            }
        }
    }
}

extension View {
    func comicCellInteraction(
        comic: Comic,
        isSelectionMode: Bool,
        isFocused: Bool,
        showsRegenerate: Bool = true,
        actions: ComicCellActions
    ) -> some View {
        modifier(
            ComicCellInteraction(
                comic: comic,
                isSelectionMode: isSelectionMode,
                isFocused: isFocused,
                showsRegenerate: showsRegenerate,
                actions: actions
            ))
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

// MARK: - Context Menu Preview (iPad)

#if os(iOS)
    /// The large, zoomed cover shown above the context menu when a book is
    /// long-pressed on iPad. Sized to its content so iOS lays out a tall,
    /// poster-style preview platter.
    @MainActor
    struct ComicCoverPreview: View {
        let comic: Comic

        var body: some View {
            VStack(spacing: 0) {
                if let data = comic.coverImageData,
                    let image = PageImageCache.shared.coverImage(
                        from: data, cacheKey: comic.id.uuidString)
                {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(BackgroundColors.secondary)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .overlay(
                            Image(systemName: "book.closed")
                                .font(.system(size: 48))
                                .foregroundColor(TextColors.tertiary)
                        )
                }

                Text(comic.displayName)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 391)
            .background(BackgroundColors.elevated)
        }
    }
#endif
