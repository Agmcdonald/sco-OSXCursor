//
//  LibraryGridView.swift
//  SCO-OSXCursor
//
//  Cover grid for the library, extracted from LibraryView (Stage 4 split).
//
//  Grid sizing & alignment (Andrew, June 9): the cover size is user-
//  adjustable via a slider in the header. Columns derive from that size, so
//  every cell in a row has the same width, and ComicCardView reserves a
//  fixed-height info area — covers sit in level rows regardless of title
//  length, with consistent row spacing at every size.
//

import SwiftUI

struct LibraryGridView: View {
    let comics: [Comic]
    let isSelectionMode: Bool
    let selectedComics: Set<Comic.ID>
    let focusedComicID: Comic.ID?
    /// Target cover width in points (user-adjustable, see LibraryCoverSize).
    let coverSize: Double
    let actions: ComicCellActions
    /// Empty state supplied by the coordinator (needs library-wide context).
    let emptyState: LibraryEmptyStateView

    var body: some View {
        ScrollView {
            if comics.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: coverSize, maximum: coverSize * 1.35),
                            spacing: Spacing.xl
                        )
                    ],
                    spacing: Spacing.xxl
                ) {
                    ForEach(comics) { comic in
                        ZStack(alignment: .topLeading) {
                            ComicCardView(comic: comic)
                                .comicCellInteraction(
                                    comic: comic,
                                    isSelectionMode: isSelectionMode,
                                    isFocused: focusedComicID == comic.id,
                                    actions: actions
                                )

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
    }
}
