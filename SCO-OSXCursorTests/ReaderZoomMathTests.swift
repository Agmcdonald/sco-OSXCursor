//
//  ReaderZoomMathTests.swift
//  SCO-OSXCursorTests
//
//  Tests for the Panels-style zoom/pager math: pinch-anchored zooming (the
//  content under the fingers stays under the fingers), rubber-band scale
//  limits, settle clamping, pan bounds, and the interactive pager's
//  commit-vs-bounce decision.
//

import CoreGraphics
import SwiftUI
import Testing

@testable import SCO_OSXCursor

struct ReaderZoomMathTests {

    // MARK: - Anchored zoom

    /// The invariant that makes zoom feel like Panels: the content point under
    /// the pinch stays fixed on screen as the scale changes.
    @Test func pinchPointStaysFixedWhileZoomingIn() {
        let viewSize = CGSize(width: 800, height: 1200)
        // Pinch in the lower-right area (like zooming the crate on page 3)
        let anchor = ReaderZoomMath.anchorPoint(
            startAnchor: UnitPoint(x: 0.8, y: 0.7), viewSize: viewSize)

        let fromScale: CGFloat = 1.0
        let committed = CGSize.zero
        let toScale: CGFloat = 2.5
        let offset = ReaderZoomMath.anchoredOffset(
            anchor: anchor, fromScale: fromScale, toScale: toScale, committedOffset: committed)

        // Content point that was under the anchor before the pinch…
        let cx = (anchor.x - committed.width) / fromScale
        let cy = (anchor.y - committed.height) / fromScale
        // …must still project to the anchor afterward
        #expect(abs(cx * toScale + offset.width - anchor.x) < 0.001)
        #expect(abs(cy * toScale + offset.height - anchor.y) < 0.001)
    }

    @Test func centerPinchFromFitStaysCentered() {
        let viewSize = CGSize(width: 800, height: 1200)
        let anchor = ReaderZoomMath.anchorPoint(startAnchor: .center, viewSize: viewSize)
        let offset = ReaderZoomMath.anchoredOffset(
            anchor: anchor, fromScale: 1, toScale: 3, committedOffset: .zero)
        #expect(abs(offset.width) < 0.001)
        #expect(abs(offset.height) < 0.001)
    }

    /// A second pinch at a different spot, starting from an already-zoomed
    /// committed state, keeps ITS pinch point fixed too.
    @Test func sequentialPinchesEachKeepTheirAnchorFixed() {
        let viewSize = CGSize(width: 800, height: 1200)

        // First pinch: 1x → 2x anchored top-left-ish
        let anchorA = ReaderZoomMath.anchorPoint(
            startAnchor: UnitPoint(x: 0.25, y: 0.2), viewSize: viewSize)
        let offsetA = ReaderZoomMath.anchoredOffset(
            anchor: anchorA, fromScale: 1, toScale: 2, committedOffset: .zero)

        // Second pinch: 2x → 3.5x anchored bottom-right-ish
        let anchorB = ReaderZoomMath.anchorPoint(
            startAnchor: UnitPoint(x: 0.9, y: 0.85), viewSize: viewSize)
        let offsetB = ReaderZoomMath.anchoredOffset(
            anchor: anchorB, fromScale: 2, toScale: 3.5, committedOffset: offsetA)

        let cx = (anchorB.x - offsetA.width) / 2
        let cy = (anchorB.y - offsetA.height) / 2
        #expect(abs(cx * 3.5 + offsetB.width - anchorB.x) < 0.001)
        #expect(abs(cy * 3.5 + offsetB.height - anchorB.y) < 0.001)
    }

    @Test func anchorPointConvertsUnitPointToCenterOriginCoordinates() {
        let viewSize = CGSize(width: 1000, height: 600)
        let center = ReaderZoomMath.anchorPoint(startAnchor: .center, viewSize: viewSize)
        #expect(center == .zero)
        let topLeading = ReaderZoomMath.anchorPoint(startAnchor: .topLeading, viewSize: viewSize)
        #expect(topLeading == CGPoint(x: -500, y: -300))
    }

    // MARK: - Rubber band + settle

    @Test func rubberBandIsIdentityInsideLimits() {
        #expect(ReaderZoomMath.rubberBandScale(1.0) == 1.0)
        #expect(ReaderZoomMath.rubberBandScale(2.5) == 2.5)
        #expect(ReaderZoomMath.rubberBandScale(4.0) == 4.0)
    }

    @Test func rubberBandSoftensBeyondLimitsButStaysMonotonic() {
        // Below fit: still moves (under-zoom is visible mid-gesture) but less than raw
        let under = ReaderZoomMath.rubberBandScale(0.5)
        #expect(under < 1.0)
        #expect(under > 0.5)
        // Above max: exceeds the max but by less than the raw overshoot
        let over = ReaderZoomMath.rubberBandScale(6.0)
        #expect(over > 4.0)
        #expect(over < 6.0)
        // Monotonic through the boundary
        #expect(ReaderZoomMath.rubberBandScale(0.4) < ReaderZoomMath.rubberBandScale(0.6))
        #expect(ReaderZoomMath.rubberBandScale(4.5) < ReaderZoomMath.rubberBandScale(5.5))
    }

    @Test func settledScaleClampsAndSnapsToFit() {
        #expect(ReaderZoomMath.settledScale(0.6) == 1.0)  // under-zoom springs back to fit
        #expect(ReaderZoomMath.settledScale(1.01) == 1.0)  // near-fit snaps to fit
        #expect(ReaderZoomMath.settledScale(2.2) == 2.2)  // in-range passes through
        #expect(ReaderZoomMath.settledScale(7.0) == 4.0)  // overshoot clamps to max
    }

    // MARK: - Pan clamping

    @Test func clampedOffsetIsZeroAtFitScale() {
        let clamped = ReaderZoomMath.clampedOffset(
            CGSize(width: 300, height: -200), viewSize: CGSize(width: 800, height: 600), scale: 1.0)
        #expect(clamped == .zero)
    }

    @Test func clampedOffsetBoundsScaleWithZoom() {
        let viewSize = CGSize(width: 800, height: 600)
        // At 2x the content half-overhang is (2-1)*size/2
        let clamped = ReaderZoomMath.clampedOffset(
            CGSize(width: 9999, height: -9999), viewSize: viewSize, scale: 2.0)
        #expect(clamped.width == 400)
        #expect(clamped.height == -300)
        // In-bounds offsets pass through
        let inBounds = ReaderZoomMath.clampedOffset(
            CGSize(width: 100, height: 50), viewSize: viewSize, scale: 2.0)
        #expect(inBounds == CGSize(width: 100, height: 50))
    }

    // MARK: - Pager settle decision

    @Test func smallDragBouncesBack() {
        #expect(ReaderZoomMath.pagerSettleStep(dragX: -50, predictedDragX: -60, viewportWidth: 800) == 0)
        #expect(ReaderZoomMath.pagerSettleStep(dragX: 30, predictedDragX: 35, viewportWidth: 800) == 0)
    }

    @Test func dragPastQuarterWidthCommits() {
        // Finger left (dx<0) advances to the visual-right page
        #expect(ReaderZoomMath.pagerSettleStep(dragX: -250, predictedDragX: -250, viewportWidth: 800) == +1)
        // Finger right goes to the visual-left page
        #expect(ReaderZoomMath.pagerSettleStep(dragX: 250, predictedDragX: 250, viewportWidth: 800) == -1)
    }

    @Test func fastFlingCommitsEvenWithShortDrag() {
        #expect(ReaderZoomMath.pagerSettleStep(dragX: -60, predictedDragX: -500, viewportWidth: 800) == +1)
        #expect(ReaderZoomMath.pagerSettleStep(dragX: 60, predictedDragX: 500, viewportWidth: 800) == -1)
    }

    @Test func flingOpposingTheDragDoesNotCommit() {
        // Predicted travel disagrees with the actual drag direction → bounce
        #expect(ReaderZoomMath.pagerSettleStep(dragX: -60, predictedDragX: 500, viewportWidth: 800) == 0)
    }

    @Test func zeroWidthViewportNeverCommits() {
        #expect(ReaderZoomMath.pagerSettleStep(dragX: -250, predictedDragX: -500, viewportWidth: 0) == 0)
    }
}
