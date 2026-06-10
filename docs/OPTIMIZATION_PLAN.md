# Optimization Plan — June 2026

Branch: `claude/optimization-pass`. Staged work; Andrew builds and smoke-tests in Xcode between stages.

## Findings (summary)

The architecture is sound (MVVM, GRDB/SQLite, security-scoped bookmarks, background extraction via `Task.detached`). The problems are in *how* hot paths work, plus one large functional gap.

1. **Reader loads entire books into memory.** `CBZReader._loadComic` (and CBR equivalent) extracts every page's full image data before the book opens. A 300 MB CBZ costs 300 MB+ RAM and a long open delay. `ComicPage.image` also re-decodes `NSImage`/`UIImage` from raw `Data` on every SwiftUI render. No downsampling anywhere.
2. **Import is serial and main-thread-bound.** `OrganizeViewModel.confirmMatch` does file renames/moves with `FileManager` on the MainActor; `confirmAllReady` awaits each comic one at a time. Staging never reads `ComicInfo.xml` — filename parse only.
3. **The learning system doesn't persist or participate.** `OrganizationLearner.saveLearnedPattern` / `loadLearnedPatterns` are TODO stubs (in-memory only, lost on quit); corrections only `print()`. The Knowledge database is never consulted during import, so the app never gets smarter.
4. **Code health.** `LibraryView.swift` is 2,005 lines; `LibraryViewModel` 918. Near-zero test coverage. Heavy `print()` logging in per-page hot loops. ~9 stale status .md files in repo root.
5. **Library scale (1k–10k target).** Full-res covers feed the grid; filters recompute per render; missing-file checks block the main thread.

## Stage 1 — Reader performance (top pain point)

- Replace eager full-book extraction with lazy page loading: `ComicBook` holds page descriptors (archive entry refs), not data. A per-book `PageProvider` actor opens the archive once and extracts pages on demand.
- LRU page cache (current page ±3 decoded, byte-cost capped) with directional prefetch; flush on iPad memory warnings.
- Decode at display resolution via ImageIO (`CGImageSourceCreateThumbnailAtIndex`) instead of full-res `NSImage(data:)` per render; cache decoded images.
- Strip per-page `print()` calls from hot loops (replace with `os.Logger` at debug level).
- Files: CBZReader, CBRReader, PDFReader, EPUBReader, ComicReaderProtocol, ReaderViewModel, ComicPageView, paged/spread/vertical reader views.

## Stage 2 — Import/organize pipeline (second pain point)

- Move renames, moves, and cover extraction off the MainActor; batch `confirmAllReady` with a single progress pass.
- Read `ComicInfo.xml` in the background during staging — embedded metadata beats filename guessing and raises auto-match confidence.
- Downsample covers at import (max ~800 px) before storing; feed the library grid downsampled thumbnails.
- Run missing-file integrity checks off the main thread.
- Verify folder drops enumerate recursively (incl. .epub once Stage 5 routing is confirmed).

## Stage 3 — Learning system (the app's core promise)

- New GRDB tables: `series_aliases` (alias → canonical series + publisher, confidence, use count), `learned_patterns`, `correction_history`.
- Implement `OrganizationLearner` persistence (replace the TODO stubs).
- Consult knowledge during staging: after the filename parse, look up aliases and prior series → fill publisher/series, boost confidence; an exact prior-series match auto-promotes to Ready.
- Capture corrections automatically at `confirmMatch`: diff the initial parse against the user-confirmed values and store the mapping. Next file from the same series imports clean.
- Surface learned aliases in the Knowledge view (editable/deletable).

## Stage 4 — Code health

- Split `LibraryView.swift` into focused components; slim `LibraryViewModel`.
- Unit tests for `MetadataParser`, `PublisherDetector`, `OrganizationLearner`, `StagedComic.proposedFileName`.
- Replace remaining `print()` with `os.Logger`.
- Archive stale root-level status .md files into `docs/archive/`.

## Stage 5 — Reader polish (Panels / Apple Books parity)

Defined together after Stages 1–2 are testable on device: tap zones, double-tap zoom behavior, page-turn feel, per-book zoom memory, EPUB typography controls. Polish lands best on top of the new lazy-loading foundation.

Noted from Stage 1 testing (Andrew, June 9): fade and zoom transitions feel too fast; "slide" appears to swap instantly rather than sliding the old page out while the new page slides in (should feel closer to Panels). Tune durations and make slide a true push transition.

## Verification per stage

Each stage ends with: build on macOS + iPad simulator, a short manual smoke checklist from me, and a commit. Nothing merges to `main` until you've tested.
