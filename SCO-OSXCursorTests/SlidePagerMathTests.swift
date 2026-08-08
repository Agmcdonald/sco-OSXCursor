//
//  SlidePagerMathTests.swift
//  SCO-OSXCursorTests
//
//  Tests for the native slide pager's index math: visual-neighbor lookup
//  with Manga/RTL mirroring, and the boundary over-swipe classification
//  that surfaces "Up Next" past the end of the book.
//

#if os(iOS)

    import CoreGraphics
    import Testing

    @testable import SCO_OSXCursor

    struct SlidePagerMathTests {

        // MARK: - Neighbor lookup (visual → logical)

        @Test func ltrVisualRightIsNextPage() {
            #expect(
                SlidePagerMath.neighborIndex(from: 3, visualStep: +1, isRTL: false, count: 10) == 4)
        }

        @Test func ltrVisualLeftIsPreviousPage() {
            #expect(
                SlidePagerMath.neighborIndex(from: 3, visualStep: -1, isRTL: false, count: 10) == 2)
        }

        /// Manga: the next reading page sits to the visual LEFT
        @Test func rtlVisualLeftIsNextPage() {
            #expect(
                SlidePagerMath.neighborIndex(from: 3, visualStep: -1, isRTL: true, count: 10) == 4)
        }

        @Test func rtlVisualRightIsPreviousPage() {
            #expect(
                SlidePagerMath.neighborIndex(from: 3, visualStep: +1, isRTL: true, count: 10) == 2)
        }

        @Test func firstPageHasNoVisualLeftNeighborLTR() {
            #expect(
                SlidePagerMath.neighborIndex(from: 0, visualStep: -1, isRTL: false, count: 10) == nil)
        }

        @Test func lastPageHasNoVisualRightNeighborLTR() {
            #expect(
                SlidePagerMath.neighborIndex(from: 9, visualStep: +1, isRTL: false, count: 10) == nil)
        }

        /// Manga: the END of the book is off the visual LEFT edge
        @Test func rtlLastPageHasNoVisualLeftNeighbor() {
            #expect(
                SlidePagerMath.neighborIndex(from: 9, visualStep: -1, isRTL: true, count: 10) == nil)
        }

        // MARK: - Boundary over-swipe (Up Next at the end of the book)

        /// Swiping left on the last LTR page has no neighbor — reports +1 so
        /// the view model can surface the next issue
        @Test func overswipePastLastPageReportsForwardTurn() {
            let step = SlidePagerMath.boundaryOverswipeStep(
                dx: -120, dy: 10, index: 9, count: 10, isRTL: false)
            #expect(step == +1)
        }

        /// Swiping right on the first page reports a backward turn (bounce +
        /// report, matching InteractivePagerReader's boundary behavior)
        @Test func overswipeBeforeFirstPageReportsBackwardTurn() {
            let step = SlidePagerMath.boundaryOverswipeStep(
                dx: 120, dy: -5, index: 0, count: 10, isRTL: false)
            #expect(step == -1)
        }

        /// Manga: at the last page the end is past the visual LEFT edge, so a
        /// RIGHTWARD swipe is the over-swipe (gesture step -1; the view model
        /// inverts RTL and lands forward-past-end)
        @Test func rtlOverswipePastLastPageIsRightwardSwipe() {
            let step = SlidePagerMath.boundaryOverswipeStep(
                dx: 120, dy: 0, index: 9, count: 10, isRTL: true)
            #expect(step == -1)
        }

        /// Interior pages always have a neighbor — the native scroll handles
        /// the swipe and no boundary turn is reported
        @Test func interiorSwipeIsNotABoundaryTurn() {
            let step = SlidePagerMath.boundaryOverswipeStep(
                dx: -200, dy: 0, index: 5, count: 10, isRTL: false)
            #expect(step == nil)
        }

        /// Below the 80pt swipe threshold nothing fires
        @Test func shortSwipeAtBoundaryIsIgnored() {
            let step = SlidePagerMath.boundaryOverswipeStep(
                dx: -60, dy: 0, index: 9, count: 10, isRTL: false)
            #expect(step == nil)
        }

        /// Mostly-vertical drags (scroll/dismiss gestures) never classify
        @Test func verticalDragAtBoundaryIsIgnored() {
            let step = SlidePagerMath.boundaryOverswipeStep(
                dx: -90, dy: -140, index: 9, count: 10, isRTL: false)
            #expect(step == nil)
        }

        /// Backward swipe on the last page has a neighbor — native scroll
        /// handles it, no report
        @Test func backwardSwipeOnLastPageIsNotABoundaryTurn() {
            let step = SlidePagerMath.boundaryOverswipeStep(
                dx: 120, dy: 0, index: 9, count: 10, isRTL: false)
            #expect(step == nil)
        }
    }

#endif
