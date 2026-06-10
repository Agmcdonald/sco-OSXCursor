//
//  LibraryEmptyStateView.swift
//  SCO-OSXCursor
//
//  Empty state for the library content area, extracted from LibraryView
//  (Stage 4 split). Shown both when the library has no comics at all and
//  when the current filters/search match nothing.
//

import SwiftUI

struct LibraryEmptyStateView: View {
    /// True when the whole library is empty (first-run), false when only
    /// the current filter/search results are empty.
    let isLibraryEmpty: Bool
    /// Whether any filter or search text could be cleared.
    let canClearFilters: Bool
    let onAddComics: () -> Void
    let onClearFilters: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: isLibraryEmpty ? "tray" : "books.vertical")
                .font(.system(size: 64))
                .foregroundColor(TextColors.tertiary)

            Text(isLibraryEmpty ? "No Comics Yet" : "No Comics Found")
                .font(Typography.h2)
                .foregroundColor(TextColors.primary)

            if isLibraryEmpty {
                // First time user
                Text("Add comics to get started")
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)

                Text("Drag and drop CBZ or PDF files here, or click Add Comics")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button(action: onAddComics) {
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

                if canClearFilters {
                    Button(action: onClearFilters) {
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
}
