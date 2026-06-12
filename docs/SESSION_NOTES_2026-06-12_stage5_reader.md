# Session Writeup — June 12, 2026 (Stage 5: reader polish)

One commit, 10 source files + docs. Three Stage 5 items landed — page-curl
refinement, tap-zone tuning, and per-book zoom memory — all tested on-device
by Andrew through the session.

---

## Page curl: Apple Books parity (iOS/iPadOS)

**The original sin:** in curl mode the hosted `ComicPageView` attached a
`highPriorityGesture` drag with `minimumDistance: 0`, which claimed every
touch before `UIPageViewController`'s pan could track — so the interactive
finger-followed curl never worked. Fixes, in layers:

- **Finger-tracked curl**: new `isCurlMode` on `ComicPageView` detaches its
  drag gesture (GestureMask `.none`) while unzoomed, leaving the native pan
  free. Drag a page the whole way; release to commit or cancel.
- **Tap-to-turn without double-fires**: the built-in tap recognizer is
  disabled; the global 15%-edge zone overlay drives turns through the
  `currentPage` binding → animated `setViewControllers` curl.
- **Spread curl** (`SpreadCurlView`): landscape two-page spreads curl as a
  bound book — `spineLocation: .mid`, `isDoubleSided`, the back of the
  curling page is the next page. Half-spread "slots" (`spread*2 + side`)
  with black filler VCs for coverless halves keep pairs aligned.
- **Zoom coexistence**: pinch (two-finger) never fought the curl; while
  zoomed the page's drag re-engages for panning and the curl pan disables
  via `onZoomStateChanged`, restored on zoom-out or page turn.
- **Zoomed navigation**: swipe again at a horizontal pan limit to turn the
  page (Books/Panels behavior), wired through coordinator `requestTurn` in
  curl mode; works in every mode.
- **Swipe-down dismiss fix**: the reader's dismiss gesture ran simultaneous
  with zoom panning, closing the book mid-pan (down only — up never matched
  `translation.height > 0`). New `scoZoomStateChanged` notification suspends
  dismiss while zoomed.
- **Double-tap zoom-out**: zoomed taps now debounce 300 ms — single tap
  toggles controls, quick second tap zooms back to 1×. The global overlay
  defers zoomed center taps to the page so the two paths can't cancel each
  other out (they previously double-fired).
- **Stale-spinner flush**: a prev/current/next `isLoaded` signature swaps in
  fresh VCs when lazy-loaded data arrives; guarded so it never fires mid-curl
  (`isSafeToReset`: transition flag + pan state).
- **RTL (manga) mirroring**: dataSource neighbor lookups, programmatic
  animation side, and zoomed-swipe deltas all mirror when
  `viewModel.isMangaRTL`. Tap zones already flipped — `turn(by:)` inverts
  steps in RTL — which the session confirmed rather than re-implemented.

## Tap zones: adjustable width + visual hint

- `TapZoneWidth` (Narrow 10% / Medium 15% / Wide 30% per side) on
  `ReaderSettings`, persisted app-wide; segmented picker in the Reader
  Settings sheet (iOS-only section). `handleGlobalTap` reads it live.
- **Zone hint overlay**: changing the width flashes translucent bands over
  the live zones (chevrons + RTL-aware Previous/Next labels, center
  "Controls" hint) — once on change, again when the sheet closes, fading
  2.5 s after the last trigger. Hit-testing disabled throughout.

## Per-book zoom memory

- Migration `v15_zoom_scale` adds `zoom_scale` (REAL, NULL = 1×); Comic
  gains `zoomScale: Double?` through encode/decode, epub_theme-style.
- **Save**: deliberate settles only — pinch end and double-tap post
  `scoZoomScaleSettled`; `ComicReaderView` persists via `updateComic`.
  Zooming back to 1× clears the memory. The zoom-toggle button deliberately
  does NOT save: its notification reaches every live page view (including
  curl-cached neighbors at other scales) and would race conflicting values.
- **Reapply**: pages open at the remembered scale on page turns, book
  reopen, and across single-page, spread, and both curl modes
  (`initialScale` threaded through every host).
- **Curl interaction**: cached VCs flush when the remembered zoom changes,
  but never mid-zoom (would reset the user's pan); pages opening zoomed
  keep the curl pan disabled — turns by tap or edge-swipe, as designed.
- Vertical-scroll mode keeps its separate zoom mechanism for now.

## Backlog added (June 12, not current-stage)

Reader settings on the main Settings page (app defaults); genre field
(western / vertical / manga / ebook) with genre → reader-style/transition
presets; pick-a-page-as-cover (shared with future longbox covers); Amazon
books API as a metadata source; flush page edges in vertical scroll (gaps
read as black lines through continuous webtoon art).

## Verification

Andrew tested on-device through the session: interactive curl single-page
and spread, edge taps, RTL behavior, pinch/pan while zoomed (incl. the
dismiss-gesture regression video), double-tap zoom-out, tap-zone widths +
hint overlay, zoom memory across turns and relaunch.

## Stage 5 status

Done: transitions retune (June 10), page-curl refinement, tap-zone tuning,
per-book zoom memory. Remaining: EPUB typography controls.
