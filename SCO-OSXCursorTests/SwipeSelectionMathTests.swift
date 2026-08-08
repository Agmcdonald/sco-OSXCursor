//
//  SwipeSelectionMathTests.swift
//  SCO-OSXCursorTests
//
//  Stage 2 tests for the drag-to-paint selection math
//  (SWIPE_SELECT_PLAN.md): hit-testing against real cell rects, traversal
//  spans in flattened order, toggle deltas, and the edge-scroll curves.
//
//  Everything here is pure — no gesture, no simulator. The gesture half
//  (scroll arbitration, auto-scroll feel) stays hardware-verified.
//

import CoreGraphics
import Foundation
import Testing

@testable import SCO_OSXCursor

// MARK: - Fixtures

/// Stable IDs so failures print recognizably.
private let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
private let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
private let idC = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000000")!
private let idD = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000000")!

/// Two-column layout with a gap, like the real grid:
/// A(0,0 200×300)  gap 20pt  B(220,0 200×300)
/// C(0,320 200×300)          D(220,320 100×150)  ← the small uneven cell
private let frames: [Comic.ID: CGRect] = [
    idA: CGRect(x: 0, y: 0, width: 200, height: 300),
    idB: CGRect(x: 220, y: 0, width: 200, height: 300),
    idC: CGRect(x: 0, y: 320, width: 200, height: 300),
    idD: CGRect(x: 220, y: 320, width: 100, height: 150),
]

private let indexByID: [Comic.ID: Int] = [idA: 0, idB: 1, idC: 2, idD: 3]

// MARK: - Hit Testing

struct SwipeHitTestTests {

    @Test func pointInsideCellHitsIt() {
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 100, y: 150), frames: frames, indexByID: indexByID) == idA)
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 300, y: 150), frames: frames, indexByID: indexByID) == idB)
    }

    @Test func pointInGapBetweenCellsHitsNothing() {
        // x 200..<220 is the column gap; a drag crossing it must not
        // select either neighbor.
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 210, y: 150), frames: frames, indexByID: indexByID) == nil)
        // Row gap (y 300..<320) likewise.
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 100, y: 310), frames: frames, indexByID: indexByID) == nil)
    }

    @Test func leadingEdgeBelongsToTheCell_trailingEdgeDoesNot() {
        // CGRect.contains includes minX/minY, excludes maxX/maxY — one
        // boundary owner, never two.
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 0, y: 0), frames: frames, indexByID: indexByID) == idA)
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 200, y: 0), frames: frames, indexByID: indexByID) == nil)
    }

    @Test func smallUnevenCellWinsInsideItsOwnFrame() {
        // The Blade Forger case: D is half the size of its neighbors but
        // still owns its own area.
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 270, y: 400), frames: frames, indexByID: indexByID) == idD)
    }

    @Test func overlapTieBreaksToSmallerRect() {
        // Mid-animation two reported rects can overlap; the smaller
        // (more specific) one wins deterministically.
        var overlapping = frames
        overlapping[idB] = CGRect(x: 150, y: 0, width: 400, height: 600)  // sloppy big rect
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 180, y: 150), frames: overlapping, indexByID: indexByID) == idA)
    }

    @Test func equalOverlapTieBreaksToLowerDisplayIndex() {
        let same = CGRect(x: 0, y: 0, width: 200, height: 300)
        let stacked: [Comic.ID: CGRect] = [idB: same, idA: same]
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 100, y: 100), frames: stacked, indexByID: indexByID) == idA)
    }

    @Test func emptyFramesHitNothing() {
        #expect(
            SwipeSelectionMath.hitComic(
                at: CGPoint(x: 100, y: 100), frames: [:], indexByID: indexByID) == nil)
    }
}

// MARK: - Traversal Spans

struct SwipeTraversalTests {

    @Test func forwardJumpCoversSkippedIndicesInOrder() {
        #expect(SwipeSelectionMath.traversedIndices(from: 3, to: 9) == [4, 5, 6, 7, 8, 9])
    }

    @Test func backwardJumpCoversSkippedIndicesInTravelOrder() {
        // Reverse order matters: the stagger ripple follows the finger.
        #expect(SwipeSelectionMath.traversedIndices(from: 9, to: 3) == [8, 7, 6, 5, 4, 3])
    }

    @Test func adjacentStepIsJustTheNewIndex() {
        #expect(SwipeSelectionMath.traversedIndices(from: 4, to: 5) == [5])
        #expect(SwipeSelectionMath.traversedIndices(from: 5, to: 4) == [4])
    }

    @Test func sameIndexIsEmpty() {
        // The jitter guard: staying on one cell must produce no work.
        #expect(SwipeSelectionMath.traversedIndices(from: 7, to: 7).isEmpty)
    }

    @Test func rowWrapIsJustFlattenedIndices() {
        // End of a 4-column row (index 3) into the next row (index 4):
        // wrapping needs no special case in flattened order.
        #expect(SwipeSelectionMath.traversedIndices(from: 3, to: 4) == [4])
    }
}

// MARK: - Toggle Semantics

struct SwipeToggleDeltaTests {

    @Test func unselectedSpanSelects() {
        let delta = SwipeSelectionMath.toggleDelta(
            traversed: [idA, idB, idC], visited: [], selected: [])
        #expect(delta.add == [idA, idB, idC])
        #expect(delta.remove.isEmpty)
        #expect(delta.ordered == [idA, idB, idC])
    }

    @Test func selectedSpanDeselects() {
        let delta = SwipeSelectionMath.toggleDelta(
            traversed: [idA, idB], visited: [], selected: [idA, idB, idC])
        #expect(delta.add.isEmpty)
        #expect(delta.remove == [idA, idB])
    }

    @Test func mixedSpanFlipsEachCellIndependently() {
        // The easy-to-get-wrong case: NOT "whole span follows the first
        // cell" — each card flips on its own state.
        let delta = SwipeSelectionMath.toggleDelta(
            traversed: [idA, idB, idC, idD], visited: [], selected: [idB, idD])
        #expect(delta.add == [idA, idC])
        #expect(delta.remove == [idB, idD])
    }

    @Test func visitedCellsAreInertOnReentry() {
        // Zigzag back over a card flipped earlier this gesture: nothing.
        let delta = SwipeSelectionMath.toggleDelta(
            traversed: [idA, idB], visited: [idA], selected: [])
        #expect(delta.add == [idB])
        #expect(delta.ordered == [idB])
    }

    @Test func fullyVisitedSpanIsEmpty() {
        let delta = SwipeSelectionMath.toggleDelta(
            traversed: [idA, idB], visited: [idA, idB], selected: [])
        #expect(delta.isEmpty)
    }

    @Test func duplicateInOneBatchFlipsOnce() {
        // A single event batch can't legitimately repeat an ID, but if it
        // ever does, the flip must not double.
        let delta = SwipeSelectionMath.toggleDelta(
            traversed: [idA, idA, idB], visited: [], selected: [])
        #expect(delta.ordered == [idA, idB])
        #expect(delta.add == [idA, idB])
    }

    @Test func orderedFollowsTravelOrderForStagger() {
        let delta = SwipeSelectionMath.toggleDelta(
            traversed: [idC, idB, idA], visited: [], selected: [])
        #expect(delta.ordered == [idC, idB, idA])
    }

    @Test func addAndRemoveNeverOverlap() {
        let delta = SwipeSelectionMath.toggleDelta(
            traversed: [idA, idB, idC, idD], visited: [], selected: [idB])
        #expect(delta.add.intersection(delta.remove).isEmpty)
    }
}

// MARK: - Edge Auto-Scroll Curves

struct SwipeEdgeScrollTests {

    /// 800pt viewport, no insets.
    private let metrics = SwipeScrollMetrics(
        offsetY: 0, contentHeight: 5000, containerHeight: 800, topInset: 0, bottomInset: 0)

    @Test func midViewportHasNoVelocity() {
        #expect(SwipeEdgeScroll.velocity(forPointerY: 400, metrics: metrics) == 0)
    }

    @Test func deadBandAtZoneEntryIsInert() {
        // Just inside the 72pt bottom zone (y > 728) but within the 8pt
        // dead band — painting the outermost row must not creep the grid.
        #expect(SwipeEdgeScroll.velocity(forPointerY: 730, metrics: metrics) == 0)
    }

    @Test func velocityRampsWithPenetration() {
        let shallow = SwipeEdgeScroll.velocity(forPointerY: 750, metrics: metrics)
        let deep = SwipeEdgeScroll.velocity(forPointerY: 795, metrics: metrics)
        #expect(shallow > 0)
        #expect(deep > shallow)
        #expect(deep <= SwipeEdgeScroll.maxVelocity)
    }

    @Test func topZoneScrollsUp() {
        #expect(SwipeEdgeScroll.velocity(forPointerY: 10, metrics: metrics) < 0)
    }

    @Test func bottomInsetShiftsTheZoneAboveTheActionBar() {
        // With an 80pt bar inset, y=750 sits in the (shifted) zone's
        // deeper region than without the inset.
        let withBar = SwipeScrollMetrics(
            offsetY: 0, contentHeight: 5000, containerHeight: 800,
            topInset: 0, bottomInset: 80)
        let v = SwipeEdgeScroll.velocity(forPointerY: 700, metrics: withBar)
        #expect(v > 0)
        // Same point without the bar is not even in the zone.
        #expect(SwipeEdgeScroll.velocity(forPointerY: 700, metrics: metrics) == 0)
    }

    @Test func offsetRangeClampsToContent() {
        let m = SwipeScrollMetrics(
            offsetY: 0, contentHeight: 5000, containerHeight: 800,
            topInset: 0, bottomInset: 80)
        #expect(m.minOffsetY == 0)
        let expected: CGFloat = 5000 - 800 + 80
        #expect(m.maxOffsetY == expected)
    }

    @Test func shortContentNeverScrollsNegativeRange() {
        // Fewer books than fit on screen: max must clamp to min, not
        // go negative.
        let short = SwipeScrollMetrics(
            offsetY: 0, contentHeight: 400, containerHeight: 800,
            topInset: 0, bottomInset: 0)
        #expect(short.maxOffsetY == short.minOffsetY)
    }

    @Test func dwellMultiplierRampsAfterDelayAndCaps() {
        #expect(SwipeEdgeScroll.dwellMultiplier(elapsed: 0) == 1)
        #expect(SwipeEdgeScroll.dwellMultiplier(elapsed: 0.5) == 1)
        let mid = SwipeEdgeScroll.dwellMultiplier(elapsed: 1.9)  // halfway through ramp
        #expect(mid > 1)
        #expect(mid < SwipeEdgeScroll.dwellMaxMultiplier)
        #expect(
            SwipeEdgeScroll.dwellMultiplier(elapsed: 60)
                == SwipeEdgeScroll.dwellMaxMultiplier)
    }
}
