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

## Stage 4 — Code health — PARTIALLY DONE (June 10)

Done: warning sweep (Swift-6 async-iterator errors, deprecated onChange,
Text '+', discarded results, unused vars), BookFormat/StagedComic/
SeriesKnowledgeRecord unit tests added, 11 stale status docs archived to
docs/archive.

DONE (June 10, second pass): LibraryView.swift split — 2,141 lines down to
a ~550-line coordinator plus focused components in Views/Library/:
LibraryModels (view mode/sort/filters + testable LibraryQuery pipeline),
LibraryHeaderView, LibrarySelectionBar, LibraryGridView, LibraryListView,
LibraryPublisherBrowseView, LibraryEmptyStateView, LibraryFilterPanel,
ComicCellModifiers (shared tap/context-menu behavior, was repeated 3×).
Dead code dropped: unused selectedComic/importedFileURLs state,
bindingForComic. Shipped alongside (same surface): cover-size slider in
the header (120–260pt, persisted) and uniform card heights — fixed 2-line
title slot + one metadata line, progress bar moved onto the cover's bottom
edge — so covers sit in level rows at every size. Verified: built & ran on
iPad simulator and macOS; grid/list/publisher views and selection mode
smoke-tested on macOS.

DONE (June 10, third pass) — Stage 4 complete:
- EPUB "dead CSS" root-caused: every interpolation in injectStyles was
  double-escaped (`\\(...)`), so the theme/typography CSS, keyboard-nav JS,
  and even the head injection itself were inert literal text. Unescaped;
  color-scheme now follows the theme; reader backdrop matches the active
  theme instead of hard-coded dark. Verified on macOS: themed rendering,
  arrow-key chapter nav, controls overlay.
- print() → os.Logger: all ~290 call sites migrated to AppLog
  (Utilities/AppLog.swift), categorized loggers (Database, Library, Reader,
  Organize, Metadata, Learning, Files, App) with debug/info/error levels.
  AppLogger wraps os.Logger taking plain String so existing interpolations
  (e.g. \(error)) keep working. Only remaining prints are #Preview stubs.

## Stage 4 — original scope

- Split `LibraryView.swift` into focused components; slim `LibraryViewModel`.
- Unit tests for `MetadataParser`, `PublisherDetector`, `OrganizationLearner`, `StagedComic.proposedFileName`.
- Replace remaining `print()` with `os.Logger`.
- Archive stale root-level status .md files into `docs/archive/`.

## Stage 5 — Reader polish (Panels / Apple Books parity)

Defined together after Stages 1–2 are testable on device: tap zones, double-tap zoom behavior, page-turn feel, per-book zoom memory, EPUB typography controls. Polish lands best on top of the new lazy-loading foundation.

Noted from Stage 1 testing (Andrew, June 9): fade and zoom transitions feel too fast; "slide" appears to swap instantly rather than sliding the old page out while the new page slides in (should feel closer to Panels). Tune durations and make slide a true push transition.

DONE (June 10): slide is a true spring push (the .animation(nil) on the
transitioning view was suppressing it); fade/zoom retimed to 0.35s; zoom
made asymmetric (incoming grows, outgoing expands+fades).

DONE (June 12): page-curl refinement — interactive Books-style curl (finger-
tracked, tap-to-turn, spread curl with center spine, RTL mirroring, zoom
coexistence, swipe-down-dismiss fix, double-tap zoom-out); tap-zone tuning —
adjustable width (Narrow/Medium/Wide) with a flash-on-change zone overlay;
per-book zoom memory — zoom_scale column (v15), saved on pinch/double-tap
settle, reapplied across pages, reopen, and all reader modes.

Remaining Stage 5 candidate: EPUB typography controls — define on-device.

## Backlog (from Stage 2 testing, June 9)

- **Book format** (DONE in Stage 2.2): issue / one-shot / volume field with
  auto-detection; one-shots named `Series (Year)`, volumes `Series Vol. NN (Year)`.
- **Folder-context parsing**: most files have no ComicInfo.xml — when importing
  from folders, use parent folder names (publisher/series) as parsing hints.
  Fold into Stage 3 alongside knowledge-base matching.
- **Longbox / folder browse view**: a shelf-style browse of the library by
  publisher → series boxes, iPad first, then Mac.
- **Marquee (rubber-band) drag selection** in the library grid, Finder-style.
  Shift-click ranges + Select All shipped June 10; a drag marquee needs
  per-cell geometry tracking in the scrolling grid — revisit later.
- **Library grid sizing & alignment** (Andrew, June 9) — DONE June 10:
  cover-size slider in the header (persisted per device) and uniform card
  heights — covers aligned in level rows regardless of title length, titles
  below, consistent row spacing at every size.
- **Mac ↔ iPad transfer**: send books (with their metadata) between devices;
  pairs with the long-term "remote access to your own library" vision. iPad
  stays the lighter reading/metadata app; Mac owns file organization.

## Backlog (added June 12, Andrew — nice-to-haves, not current-stage work)

- **Reader settings in the app Settings page**: set the app-default reader
  settings (transition, reading style, tap-zone width, etc.) from the main
  Settings screen, not only from the in-reader sheet.
- **Genre field on books**: e.g. western, vertical/webtoon, manga/manhwa,
  ebook/novel — plus the ability to associate a genre with a default reader
  style and transition (genre → reader-settings preset).
- **Pick a page as cover**: choose any page of a book to act as its cover;
  the same mechanism should drive the cover image of the future
  longbox/folder browse feature.
- **Amazon books API**: investigate pulling ebook and comic metadata from
  Amazon's API as an additional metadata source alongside the existing
  matching pipeline.
- **Flush pages in vertical scroll**: remove the gap between pages in
  vertical-scroll (webtoon) mode so they sit flush. Webtoons are drawn as one
  continuous strip, so any spacing shows as black lines cutting through
  artwork mid-image.

## Verification per stage

Each stage ends with: build on macOS + iPad simulator, a short manual smoke checklist from me, and a commit. Nothing merges to `main` until you've tested.
