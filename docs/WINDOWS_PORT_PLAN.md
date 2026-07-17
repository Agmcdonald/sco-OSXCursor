# Super Comic Organizer — Windows Native Port Plan

**Approach:** Native Windows rewrite in C#/.NET with WinUI (Windows App SDK)
**Targets:** Windows 11 (primary), Windows 10 21H2+ desktops and laptops
**Status:** Planning (July 2026)
**Reference codebase:** `SCO-OSXCursor/` — 99 Swift files, ~41.7K LOC, MVVM (SwiftUI + GRDB)

---

## 1. Stack Decision

**Recommended: WinUI (Windows App SDK) + C#/.NET.** At Build 2026 Microsoft explicitly recommitted to WinUI as *the* modern UI framework for Windows and the Windows App SDK as the platform under it, with no replacement planned (they've even dropped the "3" from the branding). It gives native Fluent look, first-class dark mode, modern controls, and MSIX packaging.

Alternatives considered:

- **WPF** — battle-tested and also Microsoft-recommended, but dated visuals and no forward investment story. Fallback if WinUI tooling friction becomes a problem.
- **Avalonia** — cross-platform (could later cover Linux), good but non-native look and a smaller ecosystem. Only worth it if Linux becomes a target.
- **Compose Multiplatform desktop** — viable, but the premise of this doc is a *native* Windows app distinct from the Android codebase.

MVVM carries over directly: SwiftUI `ObservableObject` ViewModels → `CommunityToolkit.Mvvm` (`ObservableObject`, `[ObservableProperty]`, `[RelayCommand]`). XAML data binding replaces SwiftUI's state-driven rendering; the ViewModel layer ports almost concept-for-concept.

## 2. Tech Stack Mapping

| Concern | macOS app | Windows choice |
|---|---|---|
| Language | Swift | C# (.NET, latest LTS) |
| UI | SwiftUI | WinUI + XAML, Fluent design |
| Architecture | MVVM | MVVM — CommunityToolkit.Mvvm |
| DI | Singletons | Microsoft.Extensions.DependencyInjection |
| Database | GRDB (SQLite) | Microsoft.Data.Sqlite + Dapper (thin, keeps raw-SQL control like GRDB) |
| Settings | UserDefaults | `ApplicationData.LocalSettings` + JSON file |
| Images | NSImage/ImageIO + NSCache | SoftwareBitmap / SkiaSharp decode-with-downsample + MemoryCache |
| Networking | URLSession + Codable | HttpClient + System.Text.Json |
| ZIP (CBZ/EPUB/.scobook) | ZIPFoundation | System.IO.Compression (`ZipArchive`) |
| RAR (CBR) | Unrar.swift | **SharpCompress** (pure .NET, reads RAR4 + RAR5) |
| PDF | PDFKit | **Windows.Data.Pdf** (built-in) — see §4 |
| Logging | os.Logger | Microsoft.Extensions.Logging + Serilog file sink |
| Packaging | .app / App Store | MSIX (Microsoft Store) + optional sideload installer |

Suggested solution layout (mirrors the Android module plan so the two ports stay conceptually aligned):

```
Sco.Core           — models, parser, publisher detection, learning, organization logic (no UI deps)
Sco.Data           — SQLite schema, repositories, migrations
Sco.Readers        — IComicReader + Cbz/Cbr/Pdf/Epub readers, page cache
Sco.Providers      — ComicVine, GoogleBooks, OpenLibrary, Hardcover + quota tracker
Sco.Transfer       — .scobook exporter/importer
Sco.App            — WinUI app: views, viewmodels, navigation, DI
Sco.Core.Tests     — ported unit tests (parser, learning, merge, paths)
```

## 3. File Access — Simpler Than macOS

This is where Windows is *easier* than the Mac original: MSIX-packaged desktop apps run full trust and read the file system with normal paths — no sandbox, no bookmarks, no special capability needed.

- **Drop security-scoped bookmarks entirely.** `bookmark_data` blob → plain absolute `file_path` (already a column). Add a stable-identity fallback (volume serial + file ID via `GetFileInformationByHandle`) to survive renames, replacing what bookmarks did on macOS.
- Library root: standard `FolderPicker`; persist path in settings (plus `StorageApplicationPermissions.FutureAccessList` for pickers-granted items if we ever ship sandboxed).
- Import: `FileOpenPicker` (multi-select), **drag-and-drop from Explorer** (first-class in WinUI: `DragOver`/`Drop`), and Open With / file-type associations for `.cbz .cbr .pdf .epub .scobook` declared in the MSIX manifest.
- "Reveal in Finder" → "Show in Explorer" (`explorer.exe /select,`).
- Missing/duplicate detection: direct `Directory.EnumerateFiles` — fast, no SAF-style friction.

## 4. Format Readers

Same `IComicReader` interface (LoadComic / ExtractCover / GetPageCount / LoadPage) and windowed prefetch model.

- **CBZ:** `ZipArchive` — direct port; natural-sort entries, skip `__MACOSX`.
- **CBR:** **SharpCompress** — pure managed, extracts RAR4 and RAR5 (RAR is sequential-extract; cache pages aggressively, same as macOS CBR path).
- **PDF:** **Windows.Data.Pdf** (`PdfDocument.RenderToStreamAsync`) is built into Windows and matches the app's render-page-to-image model. If fidelity or performance disappoints, fall back to **PDFium** via `Docnet.Core` or `PDFtoImage`. Keep "read as book" mode.
- **EPUB:** port the custom reader (OPF/spine/TOC parsing is pure logic → `Sco.Core`); render chapters in **WebView2** with injected theme CSS. WebView2 is ubiquitous on Win11. Keep the `epub_*` locator/theme/font schema for cross-device progress compatibility.
- **Page cache:** SkiaSharp decode with target-size downsampling; in-memory LRU keyed by (book, page, scale) + on-disk thumbnail cache in `LocalCache`.

## 5. Database

Same plan as the Android port: reproduce the GRDB schema 1:1 in SQLite (`comics`, `folders`/`comic_folders`, `series_knowledge`, `correction_history`, `metadata_knowledge`, `publisher_mappings`, `publisher_banners`, `activity_log`), collapse the 27 migrations into a v1 baseline, keep UUID text ids and JSON text columns.

- Dapper over EF Core: the macOS app already thinks in hand-written SQL + record mapping (GRDB style); Dapper is the closest translation and avoids EF migration/ORM impedance.
- **Mac import:** read a `comics.db` backup directly (validate `SQLite format 3` header, same as the Mac backup/restore code), remap bookmark-based rows to a user-chosen library root, keep covers/knowledge/progress.

## 6. UI Structure

Fluent equivalents of the Mac app's shell:

- **Shell:** `NavigationView` (left pane) → Dashboard, Library, Organize, Knowledge, Settings — closely mirrors the Mac sidebar.
- **Library:** `GridView` (covers) / `ListView` (details) / publisher-shelf as grouped `ItemsRepeater`; split view with detail pane on wide windows.
- **Reader:** borderless full-window mode, `FlipView` or custom virtualized canvas for pages, `ScrollViewer` zoom, spread mode, RTL manga order, thumbnail strip (position preference preserved).
- **Keyboard/mouse first:** full accelerators (arrows/space paging, Ctrl+F search, Ctrl+O import), mouse-wheel zoom with Ctrl, context menus everywhere — desktop users expect this and the Mac app already has the interaction model.
- **Dashboard:** charts via LiveCharts2 or custom Win2D/SkiaSharp.
- Port `DesignSystem.swift` tokens into XAML resource dictionaries (colors, type ramp, spacing).

## 7. Metadata Providers & Learning

Straight ports into `Sco.Providers` / `Sco.Core`:

- ComicVine REST (user key, custom User-Agent, rolling-hour quota tracker persisted to settings), Google Books, Open Library, Hardcover GraphQL. Same comic-vs-ebook provider selection, cache-onto-record policy, ambiguous-match picker dialog.
- Learning/knowledge system and filename parser are pure logic — port with their unit tests first; they define correctness for everything downstream.

## 8. Transfer

- `.scobook` format unchanged; MSIX file association makes double-click import work.
- Send: standard save/share (`DataTransferManager` share sheet, or just Save As). No AirDrop equivalent; Mac↔Windows moves via cloud/USB/network share.
- Later (shared with Android plan): in-app local-network transfer (mDNS discovery + HTTP) that all three platforms speak.

## 9. Distribution

- **MSIX + Microsoft Store** (primary): auto-updates, clean install/uninstall, file associations.
- **Sideload path** (secondary): signed MSIX or a WiX/Inno installer for users avoiding the Store.
- Code-signing cert required either way; Store handles signing if distributed there.

## 10. Phases

| Phase | Deliverable | Notes |
|---|---|---|
| 0 | Solution scaffold | Projects, DI, CI, SQLite schema, XAML design tokens |
| 1 | Core domain | Models, parser, publisher detection, learning — **ported unit tests green** |
| 2 | File layer + readers | Library root, CBZ + PDF readers, covers, page cache |
| 3 | Library UI | Import (picker/drag-drop/associations), organize/staging flow, browsing, detail |
| 4 | Reader | Paging, zoom, spreads, RTL, progress; CBR via SharpCompress |
| 5 | EPUB + online metadata | WebView2 EPUB reader + themes; four providers + quota + picker |
| 6 | Knowledge, dashboard, maintenance | Knowledge UI, stats, dup/missing detection, reorganize/relocate |
| 7 | Transfer + Mac import | `.scobook` associations, comics.db import |
| 8 | Polish + release | Fluent polish, onboarding/help, MSIX, Store submission |

## 11. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| WinUI rough edges (tooling, control gaps) | Medium | Microsoft recommitted at Build 2026 and is actively stabilizing; WPF is the escape hatch |
| Windows.Data.Pdf fidelity/perf | Medium | PDFium fallback (Docnet.Core / PDFtoImage) behind the same IComicReader |
| SharpCompress RAR edge cases | Low–Med | Test against a corpus of real-world CBRs incl. RAR5; native unrar.dll P/Invoke as last resort |
| WebView2-based EPUB complexity | Medium | Same approach as planned Android WebView reader; share theme CSS assets |
| Store certification friction | Low | Standard reader category; no restricted capabilities needed |

## 12. Cross-Platform Compatibility Contract

Same contract as the Android plan (`docs/ANDROID_PORT_PLAN.md` §12): freeze the SQLite schema semantics, `.scobook` manifest, filename-parsing/confidence rules, and folder-structure path computation as a shared spec (`docs/SCO_CORE_SPEC.md`) so Mac, Android, and Windows libraries stay mutually intelligible. Windows should additionally match the Mac app's backup file format so backups restore across platforms.
