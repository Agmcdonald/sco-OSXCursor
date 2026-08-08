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
    /// True while a search is active: cells show a folder chip so results can
    /// jump to (and highlight in) the collection a book lives in.
    var showsFolderBadges: Bool = false
    /// Drag-to-paint selection delta: (select these, deselect these) in one
    /// write. The grid never owns durable selection — see SWIPE_SELECT_PLAN.md.
    var onPaintSelection: (Set<Comic.ID>, Set<Comic.ID>) -> Void = { _, _ in }

    // MARK: Swipe-selection state (transient, per gesture)

    @State private var swipe = SwipeSelectionState()
    /// Realized cell frames in the grid coordinate space (selection mode only).
    @State private var cellFrames: [Comic.ID: CGRect] = [:]
    /// Per-cell animation delay for the staggered paint ripple.
    @State private var paintDelays: [Comic.ID: Double] = [:]

    // MARK: Edge auto-scroll (Stage 4)

    @State private var scrollPosition = ScrollPosition()
    @State private var scrollMetrics = SwipeScrollMetrics()
    /// Display-cadence task driving the edge scroll while a paint drag sits
    /// in a hot zone. nil whenever no scrolling is happening.
    @State private var edgeScrollTask: Task<Void, Never>?

    private var indexByID: [Comic.ID: Int] {
        Dictionary(
            uniqueKeysWithValues: comics.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    /// Top-right corner content. Selection mode wins the corner; the search
    /// folder chip only shows outside it.
    @ViewBuilder
    private func cornerBadge(for comic: Comic) -> some View {
        if isSelectionMode {
            SelectionCheckbox(isSelected: selectedComics.contains(comic.id))
                .padding(Spacing.sm)
        } else if showsFolderBadges,
            let first = actions.foldersContaining(comic).first
        {
            FolderChipBadge(
                folder: first,
                extraCount: actions.foldersContaining(comic).count - 1
            ) {
                actions.revealInFolder(first.id, comic)
            }
            .padding(Spacing.sm)
        }
    }

    // MARK: - Drag-to-paint gesture (Stage 3, SWIPE_SELECT_PLAN.md)

    /// Runs alongside the ScrollView's pan. A drag that starts on a card
    /// and moves predominantly horizontally engages painting (and disables
    /// scrolling for its duration); a predominantly vertical start is ceded
    /// to the ScrollView so the grid stays scrollable in selection mode.
    /// Once engaged, movement in any direction paints, wrapping rows in
    /// flattened order.
    private var paintGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(SwipeSelectionSpace.name))
            .onChanged(handlePaintChange)
            .onEnded { _ in
                stopEdgeScroll()
                swipe.reset()
            }
    }

    // MARK: Edge auto-scroll driver

    /// Starts/stops the drive task from the latest pointer position. Runs
    /// on every drag change; the task itself re-evaluates velocity each tick
    /// so a finger holding still deep in the zone accelerates nothing new.
    private func updateEdgeScroll() {
        guard let location = swipe.lastLocation,
            SwipeEdgeScroll.velocity(forPointerY: location.y, metrics: scrollMetrics) != 0
        else {
            stopEdgeScroll()
            return
        }
        guard edgeScrollTask == nil else { return }

        edgeScrollTask = Task { @MainActor in
            // ~120Hz tick; coalesces harmlessly on 60Hz displays.
            let tick: Duration = .milliseconds(8)
            // Dwell clock starts at zone entry; leaving the zone ends the
            // task, so re-entry starts a fresh clock (that reset is the
            // "ease back up to slow down" behavior).
            let zoneEntry = Date.now
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard swipe.isPainting, let pointer = swipe.lastLocation else { break }
                let baseVelocity = SwipeEdgeScroll.velocity(
                    forPointerY: pointer.y, metrics: scrollMetrics)
                guard baseVelocity != 0 else { break }
                let velocity =
                    baseVelocity
                    * SwipeEdgeScroll.dwellMultiplier(
                        elapsed: Date.now.timeIntervalSince(zoneEntry))

                let target = min(
                    max(scrollMetrics.offsetY + velocity * 0.008, scrollMetrics.minOffsetY),
                    scrollMetrics.maxOffsetY
                )
                // At either end of the content there is nothing left to
                // reveal — stop instead of ticking in place.
                guard abs(target - scrollMetrics.offsetY) > 0.1 else { break }
                scrollPosition.scrollTo(point: CGPoint(x: 0, y: target))
                // The finger is stationary but the cells moved beneath it:
                // frames refresh via the preference, so re-paint here.
                paint(at: pointer)
            }
            edgeScrollTask = nil
        }
    }

    private func stopEdgeScroll() {
        edgeScrollTask?.cancel()
        edgeScrollTask = nil
    }

    private func handlePaintChange(_ value: DragGesture.Value) {
        switch swipe.phase {
        case .declined:
            return
        case .undecided:
            engagePaintIfEligible(value)
        case .painting:
            swipe.lastLocation = value.location
            paint(at: value.location)
            updateEdgeScroll()
        }
    }

    private func engagePaintIfEligible(_ value: DragGesture.Value) {
        // Off-card start (grid padding / gaps) → this drag scrolls.
        guard
            let startID = SwipeSelectionMath.hitComic(
                at: value.startLocation, frames: cellFrames, indexByID: indexByID)
        else {
            swipe.phase = .declined
            return
        }
        // Direction check on the first ~6pt of travel.
        guard abs(value.translation.width) >= abs(value.translation.height) else {
            swipe.phase = .declined
            return
        }
        paintDelays = [:]  // previous gesture's stagger is done by now
        swipe.phase = .painting
        flip([startID])
        swipe.lastIndex = indexByID[startID]
        // A fast first event can already be past the anchor cell.
        paint(at: value.location)
    }

    private func paint(at location: CGPoint) {
        guard
            let currentID = SwipeSelectionMath.hitComic(
                at: location, frames: cellFrames, indexByID: indexByID),
            let currentIndex = indexByID[currentID],
            let lastIndex = swipe.lastIndex,
            currentIndex != lastIndex
        else { return }

        let span = SwipeSelectionMath.traversedIndices(from: lastIndex, to: currentIndex)
        let ids = span.compactMap { comics.indices.contains($0) ? comics[$0].id : nil }
        flip(ids)
        swipe.lastIndex = currentIndex
    }

    /// Toggles each not-yet-visited cell once, in travel order, staggering
    /// the batch 15ms per cell (capped 120ms) so a fast sweep ripples
    /// behind the finger instead of flipping as one block.
    private func flip(_ orderedIDs: [Comic.ID]) {
        let delta = SwipeSelectionMath.toggleDelta(
            traversed: orderedIDs, visited: swipe.visited, selected: selectedComics)
        guard !delta.isEmpty else { return }
        for (order, id) in delta.ordered.enumerated() {
            swipe.visited.insert(id)
            paintDelays[id] = min(Double(order) * 0.015, 0.12)
        }
        onPaintSelection(delta.add, delta.remove)
    }

    var body: some View {
        ScrollViewReader { proxy in
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
                            ComicCardView(comic: comic)
                                .comicSelectionAppearance(
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedComics.contains(comic.id),
                                    animationDelay: paintDelays[comic.id] ?? 0
                                )
                                .comicCellInteraction(
                                    comic: comic,
                                    isSelectionMode: isSelectionMode,
                                    isFocused: focusedComicID == comic.id,
                                    actions: actions
                                )
                                // Top-right corner is shared: the selection
                                // badge owns it while selecting, the folder
                                // chip otherwise. They never coexist — the
                                // chip navigates on tap, which would fight
                                // selection, so it steps aside.
                                .overlay(alignment: .topTrailing) {
                                    cornerBadge(for: comic)
                                }
                                // Report the full cell frame for drag
                                // hit-testing. Only while selecting: outside
                                // selection mode the preference tree stays
                                // empty so scrolling pays nothing.
                                .background {
                                    if isSelectionMode {
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: ComicFramePreferenceKey.self,
                                                value: [
                                                    comic.id: geo.frame(
                                                        in: .named(SwipeSelectionSpace.name))
                                                ]
                                            )
                                        }
                                    }
                                }
                                .id(comic.id)
                        }
                    }
                    .padding(Spacing.xl)
                }
            }
            .coordinateSpace(name: SwipeSelectionSpace.name)
            .onPreferenceChange(ComicFramePreferenceKey.self) { cellFrames = $0 }
            .scrollDisabled(swipe.isPainting)
            .simultaneousGesture(paintGesture, isEnabled: isSelectionMode)
            // Write-only position binding for the edge auto-scroll ticks;
            // the ScrollViewReader proxy above still owns focus jumps.
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: SwipeScrollMetrics.self) { geo in
                SwipeScrollMetrics(
                    offsetY: geo.contentOffset.y,
                    contentHeight: geo.contentSize.height,
                    containerHeight: geo.containerSize.height,
                    topInset: geo.contentInsets.top,
                    bottomInset: geo.contentInsets.bottom
                )
            } action: { _, new in
                scrollMetrics = new
            }
            .onChange(of: isSelectionMode) { _, active in
                if !active {
                    stopEdgeScroll()
                    swipe.reset()
                    cellFrames = [:]
                    paintDelays = [:]
                }
            }
            .onDisappear(perform: stopEdgeScroll)
            // Bring the focused book into view — e.g. after "Reveal in Folder"
            // or a search chip jump switches the scope and focuses the result.
            .onChange(of: focusedComicID) { _, newID in
                guard let newID, comics.contains(where: { $0.id == newID }) else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .onChange(of: comics) { _, newComics in
                // The scope often changes in the same update that sets focus;
                // re-scroll once the new comic list actually contains it.
                guard let focusedComicID,
                    newComics.contains(where: { $0.id == focusedComicID })
                else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(focusedComicID, anchor: .center)
                }
            }
        }
    }
}
