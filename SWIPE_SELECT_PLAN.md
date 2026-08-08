# Swipe-to-Multi-Select Design Plan

Status: design only. No production code is part of this change.

## Current implementation (verified 2026-08-07)

- `LibraryView` owns selection: `isSelectionMode`, `selectedComics: Set<Comic.ID>`, and `selectionAnchorID` at `LibraryView.swift:74-78`. `cellActions` forwards cell selection to `handleSelectionTap(_:)` at lines 410-421. `handleSelectionTap(_:)` toggles a plain tap and supports macOS shift-range selection at lines 1213-1225; `selectRange(to:)` unions a flattened range at lines 1227-1243.
- The grid is `ScrollViewReader` -> vertical `ScrollView` -> `LazyVGrid` with one adaptive `GridItem`, at `LibraryGridView.swift:31-44`. `ForEach(comics)` builds the cells at lines 45-76. `LibraryGridView` currently receives `selectedComics` by value (lines 18-19), so it cannot paint selection yet.
- A grid cell is the `ZStack` at `LibraryGridView.swift:46-60`. `ComicCardView` itself is the full cover/title/metadata card: its root `VStack` starts at `ComicCardView.swift:18`, and padding, background, rounded clipping, and bounded hit shape are at lines 83-90. The selection fill belongs on this full outer card surface, not `coverView`.
- Cell taps live in `ComicCellInteraction.body(content:)` at `ComicCellModifiers.swift:119-160` and call `actions.handleSelectionTap` in selection mode. `SelectionCheckbox` is at lines 442-462 and already switches between outlined and filled states.
- `LibrarySelectionBar` owns the existing bulk controls and binds `selectedComics` at `LibrarySelectionBar.swift:12-17`, but it is currently constructed by `LibraryHeaderView.selectionBar` at `LibraryHeaderView.swift:252-274`; the file comment explicitly describes it as header-resident. This differs from Panels' pinned floating bottom bar.
- `LibraryView.browseLayout` is already split out to limit type-checking (`LibraryView.swift:517-660`). The grid call is lines 618-627. New gesture logic must remain in small grid-specific types rather than expanding `LibraryView.body`.
- The only pre-existing dirty file observed was Xcode's `UserInterfaceState.xcuserstate`; implementation must not touch or revert it.

## Recommendation

Use one pure-SwiftUI implementation on iOS/iPadOS and macOS: a high-priority `DragGesture`, visible-cell frame preferences in a named viewport coordinate space, `ScrollPosition`-based edge scrolling, and the existing `LazyVGrid`.

### Why this architecture

`DragGesture` must be attached above the cells (to the scroll viewport/grid container), enabled only in selection mode, and installed with `highPriorityGesture`. A 6-point minimum distance preserves ordinary tap selection while making the selection recognizer defeat the `ScrollView` pan once a drag is recognized. Set `isSelectionDragActive` on the first `onChanged`, apply `scrollDisabled(isSelectionDragActive)`, and clear it on end/cancellation. Normal scrolling remains available when not actively painting; during painting, the only movement is controlled auto-scroll. Verify this arbitration early on hardware because changing `scrollDisabled` during recognition is the highest-risk assumption.

Each realized cell reports `[Comic.ID: CGRect]` through `ComicFramePreferenceKey`, using a named coordinate space whose origin is the visible scroll viewport. At each meaningful pointer update, scan the realized rects to find the containing cell: this is O(visible cells), normally tens of rectangles, never O(all comics). Precompute `[Comic.ID: Int]` whenever `comics` changes; after hit-testing, endpoint-to-index lookup is O(1). Geometry-derived row/column math is rejected because adaptive columns and real cell frames/aspect/layout can differ. Rect preferences make the full-card hit target correct even for the smaller "Blade Forger 001" case.

The first hit cell becomes `dragAnchorID` and is also the first cell acted upon. Track `lastIndex` (the most recently traversed flattened index) and a per-gesture `visitedIDs: Set<Comic.ID>`. When the pointer enters a different cell at `currentIndex`, walk the inclusive flattened span between `lastIndex` and `currentIndex` — the newly traversed segment, not the whole span back to the anchor — and act on each ID in that span that is not already in `visitedIDs`. This produces row wrapping by construction and correctly fills cells skipped when a fast drag jumps several indices between touch events. Then set `lastIndex = currentIndex`. Do not mutate selection while the pointer remains in the same cell. Keep the last pointer location even when it lies in spacing or an edge hot zone; after auto-scroll reveals new frames, re-hit-test that stored location so painting continues without another finger event.

Drag painting toggles per cell: a traversed cell that is unselected becomes selected, and a traversed cell that is already selected becomes deselected. This is a product decision from the repository owner (2026-08-07), taken over the additive-only reading of the recording. The recording is genuinely silent on the reverse case — its drag never crosses an already-selected card — so it is not evidence against toggling, and iOS Photos sets the platform precedent.

Each cell flips **at most once per gesture**, enforced by `visitedIDs`. Without that guard, sub-cell pointer jitter across a shared boundary re-enters the same cell repeatedly and strobes it on and off. The accepted cost is that backtracking along the drag path does not undo the paint; revisiting a cell in the same gesture is inert. If undo-by-backtracking is wanted later, it requires replacing `visitedIDs` with an ordered path history plus per-cell entry state, and should be specified separately rather than bolted on.

Because a drag can now remove selection, it can also empty a selection that predates the gesture. Selection-mode chrome must therefore tolerate reaching zero selected mid-drag: bulk actions disable rather than the bar disappearing, and selection mode does not auto-exit at zero during an active drag. Existing tap toggling and macOS shift-click remain unchanged.

On macOS, selection mode uses the same click-drag paint model. A desktop rubber-band marquee would select by rectangle intersection, contradict the observed flattened wrapped range and require a second interaction/state path. Keep normal click toggle and shift-click behavior intact.

### Edge auto-scroll

Use a single pure-SwiftUI mechanism: bind the `ScrollView` to `@State private var scrollPosition = ScrollPosition()` with `.scrollPosition($scrollPosition)`. While a selection drag is active, a cancellable main-actor task ticks once per display refresh (target 120 Hz; coalescing naturally on 60 Hz displays). The stored pointer's penetration into 72-point top/bottom hot zones maps continuously to signed velocity, with a small dead band and a capped maximum near 900 points/second. Each tick calls `scrollPosition.scrollBy(y:)` by velocity times elapsed time, then re-hit-tests the stored pointer against updated preferences. Stop the task immediately on gesture end, selection-mode exit, disappearance, or when no further scrolling occurs. The bottom hot zone is measured above the bottom action bar/safe-area inset, not underneath it.

This is continuous point scrolling; do not use repeated `ScrollViewReader.scrollTo(id:)`, which produces discrete jumps and poor 120 Hz behavior. Keep the existing reader/proxy only for `focusedComicID` jumps unless later testing shows it can be replaced safely.

### Why not UIKit or UICollectionView

- A `UIPanGestureRecognizer` bridge can provide explicit failure/cancellation relationships with `UIScrollView`, and direct `contentOffset` control is mature. Its costs here are UIKit-only code, coordinate conversion, forwarding taps/context menus/accessibility, recognizer lifecycle bugs, and a separate AppKit/macOS design.
- `UICollectionView` multiple-selection delegates and native edge scrolling are attractive in a UIKit-first grid. Here they require replacing `LazyVGrid`, hosting existing SwiftUI cards, reconnecting focus/context menus/drop handling, and maintaining another macOS implementation. That is disproportionate to one gesture.
- Therefore start pure SwiftUI. Treat failed hardware gesture arbitration or unsmooth `ScrollPosition` scrolling as explicit exit criteria for a narrowly scoped iOS recognizer bridge—not as parallel production architecture in stage one.

## State and type boundaries

Keep durable selection in `LibraryView.selectedComics`. Add one narrow callback to `LibraryGridView`, `onPaintSelection: (_ add: Set<Comic.ID>, _ remove: Set<Comic.ID>) -> Void`, wired to a small `LibraryView` helper that applies `formUnion(add)` then `subtract(remove)` in a single write. A union-only callback is insufficient now that a drag can deselect. Do not copy durable selection into the gesture engine.

The gesture engine needs to read each traversed cell's current selected state to decide its flip direction, but must not own selection. Pass the current `selectedComics` into `LibraryGridView` as a read-only value (it is already passed by value today) and resolve flip direction at traversal time against that value plus the pending in-gesture delta, so a cell flipped earlier in the same drag is not re-read stale. Alternatively resolve direction inside the `LibraryView` helper and keep the grid emitting raw traversed IDs — decide in Stage 3 and record which, because it determines whether the grid needs the selection set at all.

Put transient interaction state in a new grid-local helper (suggested `LibraryGridSwipeSelection.swift`): `ComicFramePreferenceKey`, `SwipeSelectionState` (`anchorID`, `currentID`, `lastIndex`, `visitedIDs`, `lastLocation`, `isActive`), visible frames, ID/index lookup, traversed-span calculation, and the edge-scroll driver. Clear `visitedIDs` and `lastIndex` on every gesture start and end. This keeps `LibraryGridView.body` and especially `LibraryView.body` small.

## Visual and animation specification

In selection mode, dim every full card slightly (target opacity 0.82; validate against the recording) and always show its top-right check badge. For selected cells, draw a rounded gold fill across the entire card (`AccentColors.primary` or the app's existing gold token at roughly 0.18 opacity), a 2-point gold border, and the filled checkbox. Reuse the card's 12-point corner radius and do not alter its frame, padding, or intrinsic height.

Animate a cell on any change of its selected state with `.spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0.08)`. Both directions animate now that a drag can deselect; an instant un-fill against an animated fill reads as a glitch. Deselection runs the same spring in reverse (fill opacity to zero, scale 1.0 -> 0.985) rather than a distinct removal animation, so painting back and forth stays visually symmetrical.

When one pointer update flips multiple flattened indices, assign those IDs an order within that batch and delay them by `min(order * 0.015, 0.12)` seconds. This reproduces the partial, springy wave without delays growing with library distance. Order the batch along the direction of travel — ascending when the drag moves forward through the flattened order, descending when it moves backward — so the ripple always trails the finger instead of jumping ahead of it. Animate fill opacity and a restrained 0.985 -> 1.0 scale; do not animate grid layout. Respect Reduce Motion by using an immediate/ease-out opacity change with no scale or stagger. Remove transient animation-order entries after completion so hundreds of IDs do not accumulate gesture-only state.

## Staged implementation plan

### Stage 1 — Visual selection parity and chrome

- `ComicCardView.swift`: add explicit `isSelectionMode`/`isSelected` visual inputs or a small `comicSelectionAppearance` modifier around the root card; apply dimming and the full-card gold overlay without changing layout.
- `ComicCellModifiers.swift`: update `SelectionCheckbox.body` transitions and add the Reduce Motion-aware selection appearance helper if it is shared by list/publisher views. Decide explicitly that gold full-card paint applies to the main grid only; do not accidentally change list rows or publisher grids.
- `LibraryGridView.swift`: pass selection flags at the full cell boundary and place the badge at top-right (the current `ZStack(alignment: .topLeading)` conflicts with the observed corner).
- `LibraryHeaderView.swift`, `LibrarySelectionBar.swift`, and `LibraryView.browseLayout`: split compact top selection controls (Select All / Done) from bulk actions, host bulk actions in a `.safeAreaInset(edge: .bottom)` or bottom overlay outside the scrolling content, and keep it pinned while the grid scrolls. Preserve existing actions, grouping lower-frequency actions under More where needed. Ensure the existing status-toast bottom overlay at `LibraryView.swift:951-963` is vertically offset/stacked rather than obscuring the bar.
- Verify selection-mode entry/exit, all-card dimming, full uneven-cell coverage, badge corner, pinned bar, safe areas, keyboard, and iPad orientations before gestures.

### Stage 2 — Geometry and pure selection calculation

- Add `LibraryGridSwipeSelection.swift` with `ComicFramePreferenceKey`, a named coordinate-space identifier, `SwipeSelectionState`, and pure helpers `hitComic(at:in:)`, `traversedIDs(from:through:indexByID:comics:)` (the newly crossed span between two indices, exclusive of the origin index), and `applyToggle(traversed:visited:selected:) -> (add: Set, remove: Set)`.
- `LibraryGridView.swift`: report each realized outer cell frame using an anchor/geometry preference, reduce frames by ID, read them once at the grid/viewport boundary, and build `indexByID` from display-order `comics` only when that array changes.
- Unit-test containment at boundaries, gaps, non-uniform frames, forward/backward traversal, row wrapping, missing IDs, filtering/reordering, and duplicate preference reduction. State the deterministic overlap tie-break (smallest containing rect, then lower display index).
- Unit-test toggle semantics specifically: an unselected span selects; a pre-selected span deselects; a mixed span flips each cell independently; a cell already in `visitedIDs` is inert on re-entry; a fast jump across several indices flips every intermediate cell exactly once; and reversing direction mid-drag does not re-flip previously visited cells.

### Stage 3 — Gesture arbitration and painting

- `LibraryGridView.swift`: conditionally install `highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named(...)))`; call small `begin/update/endSwipeSelection` helpers rather than expanding `body`; apply `scrollDisabled` only while active.
- `LibraryView.swift`: add `paintSelection(add:remove:)` next to `toggleSelection(for:)` and pass it into the grid. Apply both sets in one write so the view updates once per traversal, not twice. Reset transient drag state when selection mode exits or `comics` changes. Keep `handleSelectionTap(_:)` and `selectRange(to:)` behavior unchanged.
- Record in code which side resolves flip direction (grid vs. `LibraryView` helper), per the State and type boundaries section.
- Coalesce events by current cell ID. Batch a newly traversed span into one add/remove pair and one animation-order update, avoiding a full selection-set write at every display sample.
- Handle the drag emptying the selection: bulk actions disable at zero, the bar stays put, and selection mode does not auto-exit mid-drag.
- Hardware-test: tap still toggles, context menus still work, vertical drag never scrolls normally after recognition, diagonal/reversing drags remain stable, deselect-by-drag works starting from a pre-selected card, jitter across a cell boundary does not strobe, selection-mode exit cancels cleanly, and VoiceOver/keyboard behavior is unchanged.

### Stage 4 — Continuous edge auto-scroll

- `LibraryGridSwipeSelection.swift`: add the cancellable display-refresh task and pure `edgeVelocity(location:viewport:barInset:)` curve.
- `LibraryGridView.swift`: bind `ScrollPosition`, measure viewport/action-bar exclusion, store the latest pointer location, call `scrollBy(y:)`, and re-run hit-testing after preference/layout updates. Retain the existing `ScrollViewReader` focus jumps.
- Test top and bottom boundaries, 60/120 Hz devices, variable frame sizes, long libraries, safe-area/action-bar exclusion, pointer leaving/re-entering the hot zone, cancellation, and filtered data changing mid-drag.

### Stage 5 — Performance, accessibility, and regression gate

- Profile a library with hundreds/thousands of comics. The hot path must be O(visible frames) containment plus O(1) endpoint lookup; no per-frame scan of `comics`, image decoding, geometry mutation, or layout animation.
- Add signposts/counters temporarily to confirm selection writes occur only on cell transitions, that each traversed cell is written at most once per gesture, and the edge task is absent while idle.
- Run macOS and iOS builds/tests. Manually compare a frame-stepped capture for flattened row wrapping, capped 15 ms stagger, full-card gold fill, continuous edge painting, and pinned action bar.
- Re-test focus scrolling, file drop, search/filter/sort changes, list and publisher modes, shift-click, context-menu Select Book/Select Range, selection actions, Reduce Motion, VoiceOver, and the known macOS layout hazard. Do not introduce `.fixedSize(vertical: true)` or other intrinsic-height forcing into this path.

## Acceptance criteria

Selection-mode chrome matches the seven observed behaviors; a drag flips every traversed cell across uneven cells in flattened wrapped order, selecting unselected cells and deselecting selected ones, exactly once per cell per gesture; boundary jitter does not strobe a cell; ordinary scrolling cannot steal an active selection drag; edge scrolling is continuous and keeps painting; selection changes and animation remain smooth in both directions at 60/120 Hz with hundreds of items; the action bar stays pinned and survives the selection reaching zero mid-drag; macOS uses the same paint interaction while retaining tap/shift-click; and existing non-grid modes and selection actions regress neither behavior nor layout.
