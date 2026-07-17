# Super Comic Organizer — Android Port Plan

**Approach:** Full native rewrite in Kotlin + Jetpack Compose
**Targets:** Phones, tablets, foldables, ChromeOS, and Android 16 desktop windowing / connected displays
**Status:** Planning (July 2026)
**Reference codebase:** `SCO-OSXCursor/` — 99 Swift files, ~41.7K LOC, MVVM (SwiftUI + GRDB)

---

## 1. Goals & Scope

Recreate SCO's full feature set on Android as a first-class native app:

- Import CBZ/CBR/PDF/EPUB, parse filenames + ComicInfo.xml, extract covers
- Organize files into a structured "home library" folder hierarchy
- Learning/knowledge system trained by user corrections
- Online metadata enrichment (ComicVine, Google Books, Open Library, Hardcover)
- Full reader (page/spread/scroll, zoom, manga RTL, EPUB themes)
- Dashboard/stats, duplicate & missing-file detection, virtual folders
- Cross-device book transfer via the existing `.scobook` package format

**One APK/AAB, adaptive UI.** Android 16 QPR3 (GA March 2026) made desktop windowing and connected-display sessions standard on Pixel and Samsung devices — a phone plugged into a monitor gets a taskbar and freely resizable windows. Building resizable, keyboard/mouse-friendly, adaptive layouts from day one covers "Android desktop" without a separate target.

## 2. Tech Stack

| Concern | macOS app | Android choice |
|---|---|---|
| Language | Swift | Kotlin |
| UI | SwiftUI | Jetpack Compose + Material 3 Adaptive |
| Architecture | MVVM (`ObservableObject`) | MVVM (`ViewModel` + `StateFlow`) |
| DI | Singletons | Hilt (or Koin) |
| Database | GRDB (SQLite) | Room (SQLite) |
| Settings | UserDefaults + Codable JSON | DataStore (Proto or Preferences) |
| Images | NSImage/ImageIO + NSCache | Coil 3 + BitmapFactory `inSampleSize`, LRU + disk cache |
| Networking | URLSession + Codable | Retrofit/OkHttp (or Ktor) + kotlinx.serialization |
| ZIP (CBZ/EPUB/.scobook) | ZIPFoundation | `java.util.zip` / Okio |
| RAR (CBR) | Unrar.swift | libarchive Android wrapper (RAR5) — see §5 |
| PDF | PDFKit | `PdfRenderer` (built-in) or `androidx.pdf` — see §5 |
| Background work | ad hoc async | WorkManager + coroutines |
| Logging | os.Logger | Timber |

## 3. Architecture Mapping

The macOS layering ports directly. Suggested Gradle modules:

```
:app                  — entry point, navigation, DI wiring
:core:model           — Comic, Folder, KnowledgeEntry, StagedComic, enums (pure Kotlin)
:core:database        — Room schema, DAOs, migrations
:core:metadata        — MetadataParser, ComicInfo.xml, PublisherDetector, confidence scoring
:core:providers       — ComicVine, GoogleBooks, OpenLibrary, Hardcover clients + quota tracker
:core:learning        — OrganizationLearner, SeriesKnowledge, correction history
:core:organization    — FileOrganizer path computation, LibraryFileService (SAF-backed)
:core:reader          — ComicReader interface + CBZ/CBR/PDF/EPUB readers, PageImageCache
:core:transfer        — .scobook exporter/importer, TransferManifest
:feature:library      — grid/list/publisher-shelf browsing
:feature:reader       — reader UI
:feature:organize     — staging/import flow
:feature:dashboard    — stats, activity feed
:feature:knowledge    — knowledge base management
:feature:settings     — settings, maintenance, onboarding
```

**Highly portable (mechanical Kotlin rewrite):** MetadataParser, PublisherDetector, learning system, folder-structure path computation, Comic merge/dedup logic, all four metadata API clients, ComicVine quota tracker, `.scobook` format. These are pure logic with no Apple dependencies — port them first, with unit tests mirroring the Swift tests.

**Needs redesign:** file access (§4), image pipeline, PDF/RAR decoding, transfer transport (§7).

## 4. File Access — the Biggest Architectural Change

macOS uses security-scoped bookmarks (a `bookmark_data` blob per comic, 16 files touch this). Android has no equivalent; the replacement is the **Storage Access Framework (SAF)**.

**Design:**

- User picks a **library root** once via `ACTION_OPEN_DOCUMENT_TREE`; persist with `takePersistableUriPermission`. All organized files live under this tree via `DocumentFile`.
- The `bookmark_data` column becomes a **`content_uri` (text)** column. `file_path` remains as the logical/display path.
- Import accepts `ACTION_OPEN_DOCUMENT` (multi-select), share intents (`ACTION_SEND`/`SEND_MULTIPLE`), and drag-and-drop (`DragAndDropTarget` in Compose — works from Files app in split-screen/desktop windowing).
- **Random access problem:** archive readers need seekable access, but SAF gives streams. Solutions per format:
  - ZIP/CBZ/EPUB: `ParcelFileDescriptor` from `ContentResolver` → `FileChannel` for true random access when the provider supports it; fall back to streaming index scan.
  - PDF: `PdfRenderer` takes a seekable `ParcelFileDescriptor` directly.
  - RAR: libarchive reads streams sequentially; cache extracted pages aggressively.
- Do **not** use `MANAGE_EXTERNAL_STORAGE` — Play Store policy makes approval unlikely for this category. SAF is sufficient.
- Duplicate/missing-file detection: re-enumerate the library tree via `DocumentFile`/`DocumentsContract` queries (batch queries; `DocumentFile.listFiles()` is slow — use `ContentResolver.query` on children URIs directly).

**Risk:** SAF throughput on huge libraries (1000s of files). Mitigate by caching the tree structure in Room and reconciling lazily.

## 5. Format Readers

Same `ComicReader` interface as macOS (`loadComic / extractCover / getPageCount / loadPage`), windowed prefetch (~3 pages eager, then prefetch window).

- **CBZ:** `ZipFile` over a `FileChannel` (via PFD), natural-sort image entries, skip `__MACOSX` — direct port.
- **CBR:** junrar is JVM-pure but **does not support RAR5**, which is common in the wild. Use a **libarchive NDK wrapper** (e.g. `me.zhanghai.android.libarchive`, used by Material Files) which handles RAR4 + RAR5. Keep junrar as a fallback only if the native dependency proves problematic.
- **PDF:** built-in `android.graphics.pdf.PdfRenderer` renders pages to bitmaps — matches the macOS approach (PDFKit → images). `androidx.pdf` (with `pdf-compose`) is still alpha as of July 2026; watch it, but don't depend on it for v1. Preserve the "read as book" mode flag.
- **EPUB:** the macOS reader is custom (OPF/spine/TOC/themes). Two options:
  1. Port the custom reader; render chapters in a `WebView` with injected CSS themes (recommended — keeps feature parity: themes, fonts, locator-based progress).
  2. Adopt **Readium Kotlin Toolkit** (mature, but different progress/locator model than the existing `epub_*` columns).
- **Page cache:** decode with `inSampleSize` downsampling sized to the display; memory LRU + disk thumbnail cache (Coil handles most of this).

## 6. Database

Port the GRDB schema to **Room** nearly 1:1 — same tables: `comics` (~50 cols), `folders` + `comic_folders`, `series_knowledge`, `correction_history`, `metadata_knowledge`, `publisher_mappings`, `publisher_banners`, `activity_log`.

Changes:

- `bookmark_data` blob → `content_uri` text (§4).
- Collapse the 27 macOS migrations into a single v1 schema; start Android's own migration history from there.
- Keep UUID-as-text primary keys and JSON-in-text columns (tags, story_arcs, metadata_candidates) for cross-platform compatibility.
- **Library import:** since both apps are plain SQLite, ship a "import from Mac backup" path that reads a `comics.db` backup file, maps bookmark rows to unresolved entries, and prompts the user to relocate the library root. Cover blobs, knowledge, and reading progress come across for free.

## 7. Transfer (replacing AirDrop)

The `.scobook` format (zip: manifest.json + book + cover) is fully portable — keep it unchanged.

- **Receive:** register file-type association for `.scobook`; accept via share sheet and Open With.
- **Send:** Android share sheet (`ACTION_SEND` with `FileProvider` URI) → user picks Quick Share, email, Drive, etc. Quick Share is the closest AirDrop analog on Android.
- **Mac ↔ Android:** AirDrop and Quick Share don't interoperate. `.scobook` over any file channel (cloud, USB, local network) still works. A later phase could add an in-app local Wi-Fi transfer (NSD + HTTP) that both apps speak.

## 8. Adaptive UI (phone / tablet / foldable / desktop)

- **Navigation:** `NavigationSuiteScaffold` — bottom bar on phones, rail on tablets/desktop.
- **Library:** adaptive grid (`LazyVerticalGrid` with `WindowSizeClass`-driven columns); list-detail pane (`ListDetailPaneScaffold`) on expanded widths so tablets/desktop show library + detail side by side, like the Mac app.
- **Reader:** immersive, orientation-aware; spread mode auto-enables on landscape/expanded widths; RTL manga mode preserved.
- **Desktop windowing (Android 16):** declare `resizeableActivity=true`, handle configuration changes without state loss (Compose + ViewModel gives this nearly free), full keyboard shortcuts (arrow/space paging, cmd/ctrl-F search), hover states, right-click context menus (`ContextMenuArea`), mouse-wheel zoom.
- **ChromeOS** comes along for free with the above.
- **Dashboard:** re-implement charts in Compose (Vico or custom Canvas).

## 9. Metadata Providers

Straight ports: ComicVine (REST, user-supplied key, custom User-Agent, rolling-hour quota tracker → DataStore), Google Books, Open Library, Hardcover (GraphQL). Same provider-selection rule (comic vs prose ebook). Same "no auto re-fetch, cache onto record" policy and ambiguous-match picker UI.

## 10. Phases

| Phase | Deliverable | Notes |
|---|---|---|
| 0 | Project scaffold | Modules, CI, DI, Room schema, design tokens ported from `DesignSystem.swift` |
| 1 | Core domain | Models, parser, publisher detection, learning system — **with ported unit tests** |
| 2 | File layer + readers | SAF library root, CBZ/PDF readers, cover extraction, page cache |
| 3 | Library UI | Import (picker/share/drag-drop), staging/organize flow, grid/list browsing, detail view |
| 4 | Reader | Paging, zoom, spreads, RTL, progress tracking; CBR (libarchive) lands here |
| 5 | EPUB + online metadata | EPUB reader + themes; four providers + quota + match picker |
| 6 | Knowledge, dashboard, maintenance | Knowledge UI, stats, activity log, dup/missing detection, reorganize/relocate |
| 7 | Transfer + Mac import | `.scobook` send/receive, comics.db backup import |
| 8 | Polish + release | Desktop-windowing/keyboard polish, onboarding, help, Play listing, beta |

Phases 1–2 are the foundation and the highest-risk items (SAF, archives) — front-load them.

## 11. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| SAF performance on large libraries | High | Cache tree in Room; batch `DocumentsContract` queries; background reconciliation |
| RAR5 CBR files | High | libarchive NDK wrapper from day one, not junrar |
| PDF rendering fidelity vs PDFKit | Medium | `PdfRenderer` is solid for raster pages; evaluate `androidx.pdf` when stable |
| EPUB parity (themes, locators) | Medium | Port custom reader over adopting Readium; keep `epub_*` schema |
| Memory pressure on low-end phones | Medium | Strict downsampling, small prefetch window, Coil memory limits |
| Play policy (content ratings in library) | Low | App displays user-owned files; standard reader-category precedent |

## 12. Cross-Platform Compatibility Contract

To keep Mac, Android, and (planned) Windows versions interoperable, treat these as a frozen shared spec:

1. **SQLite schema** semantics (column names, JSON column formats, UUID text ids)
2. **`.scobook` manifest** format
3. **Filename parsing + confidence rules** and ComicInfo.xml handling
4. **Folder-structure path computation** (so a library organized on one platform is recognized by another)

Recommend extracting these into a `docs/SCO_CORE_SPEC.md` before either port starts.
