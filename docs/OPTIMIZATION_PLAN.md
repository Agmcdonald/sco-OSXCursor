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

## Stage 3 — Learning system (the app's core promise) — DONE

Implemented (June 10):

- New tables (migration v12): `series_knowledge` (canonical series → publisher,
  book format, aliases, use count) and `correction_history`. Seeded from the
  existing library on first run.
- `SeriesKnowledge` service: in-memory cache + DB mirror; exact and alias
  matching; folder-name hints (publisher via exact match against built-in +
  learned publishers; series via parent folder).
- Staging and quick-add both consult knowledge after the filename parse:
  alias → canonical series, publisher filled, volume-format remembered,
  character-map fallback. Confidence re-evaluated with the enriched fields.
- Every confirmed import calls `recordImport`; differences between the
  original parse and the confirmed values become aliases + correction rows.
  Metadata-editor corrections (`OrganizationLearner.learnFromCorrection`)
  forward into the same store.
- Learning tab is now a real view: learned series (searchable, with aliases
  and use counts, context-menu Forget) + recent corrections.

## Stage 4 — Code health

- Split `LibraryView.swift` into focused components; slim `LibraryViewModel`.
- Unit tests for `MetadataParser`, `PublisherDetector`, `OrganizationLearner`, `StagedComic.proposedFileName`.
- Replace remaining `print()` with `os.Logger`.
- Archive stale root-level status .md files into `docs/archive/`.

## Stage 5 — Reader polish (Panels / Apple Books parity)

Defined together after Stages 1–2 are testable on device: tap zones, double-tap zoom behavior, page-turn feel, per-book zoom memory, EPUB typography controls. Polish lands best on top of the new lazy-loading foundation.

Noted from Stage 1 testing (Andrew, June 9): fade and zoom transitions feel too fast; "slide" appears to swap instantly rather than sliding the old page out while the new page slides in (should feel closer to Panels). Tune durations and make slide a true push transition.

## Backlog (from Stage 2 testing, June 9)

- **Book format** (DONE in Stage 2.2): issue / one-shot / volume field with
  auto-detection; one-shots named `Series (Year)`, volumes `Series Vol. NN (Year)`.
- **Folder-context parsing**: most files have no ComicInfo.xml — when importing
  from folders, use parent folder names (publisher/series) as parsing hints.
  Fold into Stage 3 alongside knowledge-base matching.
- **Longbox / folder browse view**: a shelf-style browse of the library by
  publisher → series boxes, iPad first, then Mac.
- **Library grid sizing & alignment** (Andrew, June 9): user-adjustable cover
  size (e.g. 4-across), and uniform card heights — covers aligned in level
  rows regardless of title length, titles below, consistent row spacing at
  every size.
- **Mac ↔ iPad transfer**: send books (with their metadata) between devices;
  pairs with the long-term "remote access to your own library" vision. iPad
  stays the lighter reading/metadata app; Mac owns file organization.

## Verification per stage

Each stage ends with: build on macOS + iPad simulator, a short manual smoke checklist from me, and a commit. Nothing merges to `main` until you've tested.
