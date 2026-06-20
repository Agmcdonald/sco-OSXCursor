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
            .contextMenu {
                // Range selection without a keyboard (iPad):
                // tap one book, long-press another, select the span
                if isSelectionMode {
                    Button(action: { actions.selectRange(comic) }) {
                        Label("Select Range to Here", systemImage: "checklist")
                    }
                }

                Button(action: { actions.openReader(comic) }) {
                    Label("Read", systemImage: "book.fill")
                }

                Button(action: { actions.editComic(comic) }) {
                    Label("Edit Metadata", systemImage: "pencil")
                }

                Button(action: { actions.fetchMetadata(comic) }) {
                    Label("Fetch from ComicVine", systemImage: "network")
                }

                Button(action: { actions.markAsRead(comic) }) {
                    Label("Mark as Read", systemImage: "checkmark.circle")
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

                Divider()

                Button(role: .destructive, action: { actions.delete(comic) }) {
                    Label("Delete", systemImage: "trash")
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
