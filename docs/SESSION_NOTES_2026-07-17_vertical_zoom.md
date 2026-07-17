# Session Notes — Vertical Scroll Fixes & Zoom Memory (July 17, 2026)

## 1. Vertical reading position now saves reliably

Two combined bugs were losing the reading position in vertical scroll mode:

- **Save side:** the progress tracker write was debounced (0.5s after `currentPage` stabilizes). Continuous vertical scrolling kept resetting the timer, so exiting mid-scroll synced the library from a stale tracker. Fix: `ReaderViewModel.flushProgress()` called from `ComicReaderView.onDisappear` *before* `syncProgressFromTracker()`, and `cleanupCurrentPage` now mirrors every page change (not just debounced saves) so the `deinit` fallback is accurate.
- **Restore side:** on open, the vertical strip's top cells fired `onAppear` before the scroll-to-saved-page ran, clobbering the restored `currentPage` with 0 (which then got persisted). Fix: `hasAnchored` gate in `VerticalScrollReaderView` — cell appearances are ignored until the initial anchor scroll settles (with one re-anchor pass at +300ms for lazy cell sizing).

## 2. Vertical zoom memory (per book + per folder) — migration v29

- `comics.vertical_zoom_scale` (Double?, 0.3…1.0) — per-book remembered column width.
- `folders.vertical_zoom_scale` (Double?) — folder default.
- Resolution order (mirrors folder reading style): **book memory → folder default → 0.5**. If a book is in multiple folders with zooms, the most recently modified folder wins.
- `ReaderSettings.effectiveVerticalZoom(for:)` + `folderVerticalZoomResolver` installed by `LibraryViewModel` (same pattern as `folderReadingStyleResolver`).
- `ComicReaderView` restores the effective zoom in `init` and on next-issue advance; persists changes debounced 0.6s. Programmatic restores that merely match the effective default are not written as book memory, so unzoomed books keep following their folder.
- Folder UI: folder card context menu → **Set Vertical Zoom…** → `FolderVerticalZoomSheet` with a live preview (a member book's cover at the chosen width on reader-black), 30–100% slider, "Use app default" toggle. Item-based `.sheet` + self-`dismiss()` (isPresented + inner `if let` made Cancel flaky on iPhone). `minWidth` is macOS-only; iOS uses a 620pt detent.
- **Pinch-to-zoom** in vertical mode (`MagnificationGesture` in `VerticalScrollReaderView`): trackpad on Mac, two fingers on iPad/iPhone; snaps to the slider's 0.05 grid; feeds the same per-book memory.
- `.scobook` transfer manifest now carries `verticalZoomScale` (optional → backward compatible).
- User manual updated: Folders section ("Per-Folder Reading Style & Vertical Zoom") and Reader section ("Vertical Scroll Zoom — Remembered Per Book").

## Files touched

`VerticalScrollReaderView.swift`, `ComicReaderView.swift`, `ReaderViewModel.swift`, `ReaderSettings.swift`, `Comic.swift`, `Folder.swift`, `DatabaseManager.swift` (v29), `LibraryViewModel.swift`, `LibraryView.swift`, `LibraryFolderGridView.swift`, `TransferManifest.swift`, `UserManualView.swift`.

## Next up (agreed order)

1. OrganizationLearner DB persistence (three TODO stubs)
2. Search → navigate-to-folder badge
3. Nested folders UI
4. Manual reading order within a folder
