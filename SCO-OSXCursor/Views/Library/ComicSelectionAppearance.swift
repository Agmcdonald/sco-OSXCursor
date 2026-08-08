//
//  ComicSelectionAppearance.swift
//  SCO-OSXCursor
//
//  Selection-mode appearance for a full comic cell (Stage 1 of the
//  swipe-to-multi-select plan — see SWIPE_SELECT_PLAN.md).
//
//  The wash covers the WHOLE card — cover, title and metadata footer — not
//  just the cover image, so a painted cell reads as one solid block the way
//  it does in Panels. It is applied as an overlay and never changes the
//  card's frame, padding or intrinsic height, so entering selection mode
//  cannot reflow the grid.
//

import SwiftUI

// MARK: - Tint

/// Single swap point for the selection wash colour.
///
/// Panels uses gold because gold is its brand accent; ours is the app accent
/// (`AccentColors.primary`, blue) so selection matches hover, focus and every
/// other selected state in the app. Change these two values to restyle every
/// selected cell at once.
enum ComicSelectionTint {
    static let fill = AccentColors.primary.opacity(0.18)
    static let border = AccentColors.primary

    /// Cards that are not selected recede slightly while selection mode is
    /// active, so the painted ones carry the eye.
    static let unselectedOpacity: Double = 0.82

    /// Matches the card's own corner radius in ComicCardView.
    static let cornerRadius: CGFloat = 12
}

// MARK: - Appearance Modifier

/// Dims an unselected card and washes a selected one, with a spring on the
/// state change. Both directions animate: a drag can now deselect, and an
/// instant un-fill next to an animated fill reads as a glitch.
struct ComicSelectionAppearance: ViewModifier {
    let isSelectionMode: Bool
    let isSelected: Bool
    /// Extra delay used by the drag-paint stagger (Stage 3). Zero for taps.
    var animationDelay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isSelectionMode && !isSelected ? ComicSelectionTint.unselectedOpacity : 1)
            .overlay {
                RoundedRectangle(cornerRadius: ComicSelectionTint.cornerRadius)
                    .fill(ComicSelectionTint.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: ComicSelectionTint.cornerRadius)
                            .strokeBorder(ComicSelectionTint.border, lineWidth: 2)
                    )
                    .opacity(isSelected ? 1 : 0)
                    // Scaling the overlay rather than the card gives the pop
                    // without touching layout or the card's hit shape.
                    .scaleEffect(isSelected ? 1 : 0.96)
                    // The wash is decoration; the card underneath stays
                    // tappable and keeps its own contentShape.
                    .allowsHitTesting(false)
            }
            .animation(selectionAnimation, value: isSelected)
            .animation(selectionAnimation, value: isSelectionMode)
    }

    private var selectionAnimation: Animation {
        guard !reduceMotion else {
            return .easeOut(duration: 0.12).delay(animationDelay)
        }
        return .spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0.08)
            .delay(animationDelay)
    }
}

extension View {
    /// Applies selection-mode dimming and the full-card selection wash.
    func comicSelectionAppearance(
        isSelectionMode: Bool,
        isSelected: Bool,
        animationDelay: Double = 0
    ) -> some View {
        modifier(
            ComicSelectionAppearance(
                isSelectionMode: isSelectionMode,
                isSelected: isSelected,
                animationDelay: animationDelay
            )
        )
    }
}
