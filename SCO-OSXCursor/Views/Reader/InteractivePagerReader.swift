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
    /// True while animating toward a neighbor — ignore new scrubs until settled
    @State private var isSettling = false

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
            // Index committed (pager turn, scrubber jump, keys, zoomed edge
            // swipe): the strip re-centers on the new item without animation —
            // after a pager-committed settle this lands on identical pixels.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                dragX = 0
            }
            isSettling = false
        }
        .onChange(of: items.count) {
            dragX = 0
            isSettling = false
        }
    }

    private func scrubChanged(_ dx: CGFloat, width: CGFloat) {
        guard !isSettling else { return }
        let visualStep = dx < 0 ? +1 : -1
        if neighborIndex(visualStep: visualStep) == nil {
            // No page in that direction — rubber-band
            dragX = dx * 0.25
        } else {
            dragX = dx
        }
    }

    private func scrubEnded(_ dx: CGFloat, predicted: CGFloat, width: CGFloat) {
        guard !isSettling else { return }
        let step = ReaderZoomMath.pagerSettleStep(
            dragX: dx, predictedDragX: predicted, viewportWidth: width
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

        isSettling = true
        let indexBefore = index
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            dragX = -CGFloat(step) * (width + gutter)
        } completion: {
            onTurn(step)
            // turn(by:) commits synchronously when accepted → onChange(of:
            // index) has reset the strip. If it was rejected (cooldown,
            // boundary), spring back.
            if index == indexBefore {
                debugLog("[InteractivePagerReader] Turn rejected — bouncing back")
                isSettling = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    dragX = 0
                }
            }
        }
    }
}
