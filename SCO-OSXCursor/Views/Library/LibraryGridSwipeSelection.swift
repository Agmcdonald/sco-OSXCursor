//
//  LibraryGridSwipeSelection.swift
//  SCO-OSXCursor
//
//  Drag-to-paint selection for the library grid (Stages 2–3 of
//  SWIPE_SELECT_PLAN.md). Pure geometry + state; the gesture itself is
//  installed by LibraryGridView so this file stays unit-testable.
//
//  Semantics (product decision, 2026-08-07): the drag TOGGLES each cell it
//  crosses — unselected cells select, selected cells deselect — and each
//  cell flips at most once per gesture (visitedIDs guard), so finger jitter
//  on a cell boundary can't strobe it.
//
//  Engagement rule: a drag that starts on a card and moves predominantly
//  horizontally paints; a predominantly vertical first movement is left to
//  the ScrollView so the grid stays scrollable in selection mode. Once
//  painting engages, any direction paints (rows wrap in flattened order).
//

import SwiftUI

// MARK: - Cell Frame Preference

/// Realized cells report their frames (in the grid's named coordinate
/// space); hit-testing scans only these — O(visible), never O(library).
struct ComicFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Comic.ID: CGRect] { [:] }

    static func reduce(
        value: inout [Comic.ID: CGRect], nextValue: () -> [Comic.ID: CGRect]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Name of the grid's coordinate space; cell frames and drag locations are
/// both resolved in it so they can be compared directly.
enum SwipeSelectionSpace {
    static let name = "libraryGridSwipeSpace"
}

// MARK: - Gesture State

/// Transient per-gesture state. Lives in LibraryGridView as @State; reset
/// on every gesture end and whenever selection mode exits.
struct SwipeSelectionState {
    enum Phase {
        /// No decision yet — waiting for the first movement.
        case undecided
        /// This drag is painting; the ScrollView is disabled.
        case painting
        /// This drag was ceded to the ScrollView (vertical start or it
        /// began off-card); ignore the rest of it.
        case declined
    }

    var phase: Phase = .undecided
    /// Flattened index of the most recently traversed cell.
    var lastIndex: Int?
    /// Cells already flipped this gesture — inert on re-entry.
    var visited: Set<Comic.ID> = []
    /// Last pointer location in the grid coordinate space. Kept so edge
    /// auto-scroll can re-hit-test a stationary finger as new rows arrive.
    var lastLocation: CGPoint?

    var isPainting: Bool { phase == .painting }

    mutating func reset() {
        self = SwipeSelectionState()
    }
}

// MARK: - Edge Auto-Scroll (Stage 4)

/// Live scroll geometry captured via onScrollGeometryChange — everything the
/// edge-scroll driver needs to turn a pointer position into a velocity and a
/// clamped target offset.
struct SwipeScrollMetrics: Equatable {
    var offsetY: CGFloat = 0
    var contentHeight: CGFloat = 0
    var containerHeight: CGFloat = 0
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    /// Scrollable range of the content offset. `bottomInset` covers the
    /// pinned selection bar (a safeAreaInset), so the last row can scroll
    /// clear of it.
    var minOffsetY: CGFloat { -topInset }
    var maxOffsetY: CGFloat {
        max(minOffsetY, contentHeight - containerHeight + bottomInset)
    }
}

enum SwipeEdgeScroll {
    /// Hot-zone depth at each end of the viewport.
    static let zone: CGFloat = 72
    /// Ignore the first few points of penetration so painting the outermost
    /// visible row doesn't immediately creep the grid.
    static let deadBand: CGFloat = 8
    static let maxVelocity: CGFloat = 900  // points/second

    // Dwell acceleration (Andrew, Aug 7): holding in the zone speeds up over
    // time — the base ramp alone felt too slow for long sweeps. Backing the
    // finger out of the zone resets the bonus, so easing shallower is the
    // brake: penetration drops AND the dwell clock starts over.
    /// Seconds in the zone before the bonus starts growing.
    static let dwellDelay: TimeInterval = 0.8
    /// Seconds (after the delay) to reach full bonus.
    static let dwellRampDuration: TimeInterval = 2.2
    /// Velocity multiplier at full dwell.
    static let dwellMaxMultiplier: CGFloat = 2.5

    /// Multiplier for time spent continuously inside a hot zone: 1× for the
    /// first `dwellDelay` seconds, then ramping linearly to
    /// `dwellMaxMultiplier` over `dwellRampDuration`.
    static func dwellMultiplier(elapsed: TimeInterval) -> CGFloat {
        guard elapsed > dwellDelay else { return 1 }
        let progress = min((elapsed - dwellDelay) / dwellRampDuration, 1)
        return 1 + (dwellMaxMultiplier - 1) * CGFloat(progress)
    }

    /// Signed scroll velocity for a pointer at `y` in viewport space.
    /// Negative scrolls up. Zero outside the hot zones — the caller uses
    /// that to stop the drive task. Velocity ramps with penetration so the
    /// scroll accelerates as the finger nears the physical edge.
    static func velocity(forPointerY y: CGFloat, metrics: SwipeScrollMetrics) -> CGFloat {
        let topEdge = metrics.topInset + zone
        let bottomEdge = metrics.containerHeight - metrics.bottomInset - zone

        if y < topEdge {
            let penetration = min(topEdge - y - deadBand, zone)
            guard penetration > 0 else { return 0 }
            return -maxVelocity * (penetration / zone)
        }
        if y > bottomEdge {
            let penetration = min(y - bottomEdge - deadBand, zone)
            guard penetration > 0 else { return 0 }
            return maxVelocity * (penetration / zone)
        }
        return 0
    }
}

// MARK: - Pure Helpers

enum SwipeSelectionMath {

    /// The cell under `location`. Ties (overlapping reported rects during
    /// transitions) break deterministically: smallest area, then lowest
    /// display index.
    static func hitComic(
        at location: CGPoint,
        frames: [Comic.ID: CGRect],
        indexByID: [Comic.ID: Int]
    ) -> Comic.ID? {
        var bestID: Comic.ID?
        var bestArea: CGFloat = .greatestFiniteMagnitude
        var bestIndex: Int = .max
        for (id, rect) in frames where rect.contains(location) {
            let area: CGFloat = rect.width * rect.height
            let index: Int = indexByID[id] ?? .max
            let smaller: Bool = area < bestArea
            let tieBreak: Bool = area == bestArea && index < bestIndex
            if smaller || tieBreak {
                bestID = id
                bestArea = area
                bestIndex = index
            }
        }
        return bestID
    }

    /// Newly traversed flattened span when the finger moves from `lastIndex`
    /// to `currentIndex`: everything after `lastIndex` up to and including
    /// `currentIndex`, in travel order. Covers cells skipped by a fast drag.
    static func traversedIndices(from lastIndex: Int, to currentIndex: Int) -> [Int] {
        if currentIndex == lastIndex { return [] }
        if currentIndex > lastIndex {
            return Array((lastIndex + 1)...currentIndex)
        }
        return Array((currentIndex..<lastIndex).reversed())
    }

    /// What one traversal batch does to the selection under toggle
    /// semantics (each cell flips independently, at most once per gesture).
    struct ToggleDelta: Equatable {
        var add: Set<Comic.ID> = []
        var remove: Set<Comic.ID> = []
        /// Newly visited IDs in travel order — drives the stagger delays.
        var ordered: [Comic.ID] = []

        var isEmpty: Bool { ordered.isEmpty }
    }

    /// Partitions a traversed batch into select/deselect against the current
    /// selection, skipping cells already visited this gesture. Pure: the
    /// caller merges `ordered` into its visited set.
    static func toggleDelta(
        traversed orderedIDs: [Comic.ID],
        visited: Set<Comic.ID>,
        selected: Set<Comic.ID>
    ) -> ToggleDelta {
        var delta = ToggleDelta()
        for id in orderedIDs where !visited.contains(id) && !delta.ordered.contains(id) {
            delta.ordered.append(id)
            if selected.contains(id) {
                delta.remove.insert(id)
            } else {
                delta.add.insert(id)
            }
        }
        return delta
    }
}
