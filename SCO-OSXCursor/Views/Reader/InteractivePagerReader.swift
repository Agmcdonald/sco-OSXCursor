//
//  InteractivePagerReader.swift
//  SCO-OSXCursor
//
//  Panels-style interactive page slide: the current page and its neighbor are
//  laid out contiguously (small gutter) and track the finger 1:1, so both
//  pages are visible while moving — no blackout between pages.
//
//  The pager does NOT own a gesture of its own. The active page's
//  ZoomableCanvas reports unzoomed horizontal drags through the scrub
//  callbacks, preserving the reader's existing gesture arbitration (tap
//  overlay, pinch, zoomed pan). The pager just moves the strip and decides
//  commit vs bounce on release.
//

import SwiftUI
import os

@MainActor
struct InteractivePagerReader<Item: Identifiable, Content: View>: View {
    let items: [Item]
    /// Logical index of the displayed item. External writes (scrubber, keys,
    /// zoomed edge-swipe) swap content in place; pager-committed turns go
    /// through `onTurn` so the view model keeps ownership of the change.
    @Binding var index: Int
    /// Manga/RTL: the *next* reading page sits to the visual LEFT.
    var isRTL: Bool = false
    /// Black spine gap between adjacent pages while sliding
    var gutter: CGFloat = 24
    /// Commit a turn in visual terms: +1 = user swiped left (visual-right
    /// neighbor). Same convention as the classic onSwipeLeft/onSwipeRight.
    var onTurn: (Int) -> Void
    /// Builds one item's view. `isActive` marks the displayed item; the scrub
    /// closures must be handed to that item's ZoomableCanvas.
    @ViewBuilder var content:
        (
            _ item: Item,
            _ isActive: Bool,
            _ onScrubChanged: @escaping (CGFloat) -> Void,
            _ onScrubEnded: @escaping (CGFloat, CGFloat) -> Void
        ) -> Content

    /// Live strip displacement while the finger is down (or settling)
    @State private var dragX: CGFloat = 0
    /// Strip offset when the current stroke began — strokes chain, so a drag
    /// can carry the page across the screen in stages (scroll-view feel)
    @State private var strokeBase: CGFloat? = nil
    /// Set while a pager-committed index change is in flight so the external
    /// reset in onChange(of: index) leaves the remapped dragX alone
    @State private var suppressExternalReset = false

    @inline(__always) private func debugLog(_ msg: @autoclosure () -> String) {
        #if DEBUG
            AppLog.reader.debug("\(msg())")
        #endif
    }

    /// Logical index of the neighbor in a visual direction (+1 = visual right)
    private func neighborIndex(visualStep: Int) -> Int? {
        let logicalStep = isRTL ? -visualStep : visualStep
        let candidate = index + logicalStep
        return items.indices.contains(candidate) ? candidate : nil
    }

    /// Visible logical indices in visual left→right order
    private var visibleIndices: [Int] {
        var result: [Int] = []
        if let left = neighborIndex(visualStep: -1) { result.append(left) }
        result.append(index)
        if let right = neighborIndex(visualStep: +1) { result.append(right) }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let indices = visibleIndices
            let currentPosition = CGFloat(indices.firstIndex(of: index) ?? 0)

            HStack(spacing: gutter) {
                ForEach(indices, id: \.self) { i in
                    content(
                        items[i],
                        i == index,
                        { dx in scrubChanged(dx, width: width) },
                        { dx, predicted in scrubEnded(dx, predicted: predicted, width: width) }
                    )
                    .frame(width: width, height: geo.size.height)
                }
            }
            .offset(x: -currentPosition * (width + gutter) + dragX)
            .frame(width: width, height: geo.size.height, alignment: .leading)
            .clipped()
            .background(Color.black.ignoresSafeArea())
        }
        .onChange(of: index) {
            // Pager-committed turns already remapped dragX for pixel
            // continuity — leave it to finish its settle animation. External
            // jumps (scrubber, keys, zoomed edge swipe) swap in place.
            if suppressExternalReset {
                suppressExternalReset = false
            } else {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    dragX = 0
                }
                strokeBase = nil
            }
        }
        .onChange(of: items.count) {
            dragX = 0
            strokeBase = nil
        }
    }

    private func scrubChanged(_ dx: CGFloat, width: CGFloat) {
        // Strokes continue from wherever the strip currently sits, so
        // successive drags chain instead of snapping back to the start
        if strokeBase == nil { strokeBase = dragX }
        let base = strokeBase ?? 0
        let limit = width + gutter
        var proposed = base + dx

        let visualStep = proposed < 0 ? +1 : -1
        if neighborIndex(visualStep: visualStep) == nil {
            // No page in that direction — rubber-band around rest
            proposed *= 0.25
        } else if proposed < -limit {
            // Soft stop at the neighbor's rest position: a full-width drag
            // parks the next page on screen instead of overshooting into black
            proposed = -limit + (proposed + limit) * 0.2
        } else if proposed > limit {
            proposed = limit + (proposed - limit) * 0.2
        }
        dragX = proposed
    }

    private func scrubEnded(_ dx: CGFloat, predicted: CGFloat, width: CGFloat) {
        strokeBase = nil
        let step = ReaderZoomMath.pagerSettleStep(
            dragX: dx, predictedDragX: predicted, viewportWidth: width, positionX: dragX
        )

        guard step != 0 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                dragX = 0
            }
            return
        }

        guard neighborIndex(visualStep: step) != nil else {
            // Swipe past the end: bounce, but still report the turn so the
            // view model can surface "Up Next" at the end of the book.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                dragX = 0
            }
            onTurn(step)
            return
        }

        // Commit immediately and remap the strip offset so the new index
        // renders the same pixels (shifting one cell re-centers the strip on
        // the neighbor: dragX += step * cell width). The settle then animates
        // the short remainder, and a new stroke can begin at any time — no
        // locked-out dead zone while the animation plays.
        let original = dragX
        let indexBefore = index
        var t = Transaction()
        t.disablesAnimations = true
        suppressExternalReset = true
        withTransaction(t) {
            dragX = original + CGFloat(step) * (width + gutter)
        }
        onTurn(step)
        if index == indexBefore {
            // Rejected (cooldown, boundary) — restore and bounce back
            debugLog("[InteractivePagerReader] Turn rejected — bouncing back")
            suppressExternalReset = false
            withTransaction(t) {
                dragX = original
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                dragX = 0
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                dragX = 0
            }
        }
    }
}
