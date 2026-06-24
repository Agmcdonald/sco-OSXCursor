# Implementation Research — Folders, iPad Info Panel, Beta QOL

*Drafted June 23, 2026 while you slept. Grounded in the actual codebase (GRDB schema, `LibraryView`, `ComicCellModifiers`, `ComicInspectorView`, `ReaderControlsOverlay`). Read the three feature sections, then the **Questions for you** at the bottom — answer those and I can start building.*

---

## 1. Folders (Collections)

### The core data decision (this is the one real question)

Your `Comic` is a value-type struct persisted in the `comics` table via sequential GRDB migrations (you're at `v19_thumbnail_bar_position`; folders would be **v20**). There are two ways to model folders, and the choice shapes everything:

**Option A — One-to-one (`folder_id` column on `comics`).** A book lives in exactly one folder, like the macOS Finder. Simplest to build: add a nullable `folder_id` column, a `folders` table, done. The downside is a book can't be in two places (e.g. both "Reading Now" and "Marvel Event 2024").

**Option B — Many-to-many (junction table).** A `folders` table plus a `comic_folders` link table (`comic_id`, `folder_id`). A book can sit in any number of folders, and "outside of folders" just means it has no rows in the link table. This matches how Music/Photos "albums" work, and it plays nicely with your existing favorites/reading-list flags (which are essentially built-in smart folders already).

My recommendation is **Option B**. It's only marginally more work, and it avoids a painful migration later when a beta tester inevitably asks "why can't this book be in two collections?" It also lets you keep folders purely *organizational* (a view layer) without touching the actual files on disk — important, because you have a whole `LibraryFileService` / `LibraryRelocator` system that physically organizes files by publisher/series. Folders should be a **virtual layer on top**, not a second physical reorganization scheme. (Confirm this assumption — see questions.)

### Schema (migration v20)

```swift
migrator.registerMigration("v20_folders") { db in
    try db.create(table: "folders") { t in
        t.column("id", .text).primaryKey()
        t.column("name", .text).notNull()
        t.column("parent_id", .text).references("folders", onDelete: .cascade) // nil = top level; enables nesting
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("color", .text)          // optional accent, ties into DesignSystem
        t.column("icon", .text)           // optional SF Symbol name
        t.column("created_at", .datetime).notNull()
        t.column("date_modified", .datetime).notNull()
    }
    try db.create(table: "comic_folders") { t in
        t.column("comic_id", .text).notNull().references("comics", onDelete: .cascade)
        t.column("folder_id", .text).notNull().references("folders", onDelete: .cascade)
        t.column("added_at", .datetime).notNull()
        t.primaryKey(["comic_id", "folder_id"])
    }
}
```

The `parent_id` column gives you nested folders for free if you want them later; you don't have to expose nesting in the UI on day one.

### New code surface

- **`Models/Folder.swift`** — a `Folder` struct mirroring the `Comic` pattern (Identifiable, Codable, GRDB `FetchableRecord`/`PersistableRecord`).
- **`ViewModels/FolderViewModel.swift`** (or fold into `LibraryViewModel`) — load folders, create/rename/delete, add/remove comics, reorder. `LibraryViewModel` already owns `viewModel.comics`; it should also own `folders` and a `currentFolderID` filter so the grid can be scoped.
- **`Services/Database/DatabaseManager.swift`** — CRUD: `fetchFolders()`, `saveFolder()`, `deleteFolder()`, `addComics(_:toFolder:)`, `removeComics(_:fromFolder:)`, `folderIDs(forComic:)`.
- **Views** — `FolderSidebarSection` (folder list in the existing `SidebarView`), and a `FolderGridView` or just a scoping filter on the existing `LibraryGridView`.

### Navigation — the "find books inside AND outside folders" requirement

This is the part you flagged, and it's the right thing to worry about. The clean model:

1. **Folders are a filter/scope, not a separate library.** Every book always exists in the one true library grid. A folder is just a saved filter that says "show me the books with a link row to folder X." This means your existing search, sort, and filter pipeline (`LibraryQuery.apply` in `LibraryModels.swift`) keeps working unchanged inside a folder.

2. **Search should always span the whole library, even when you're inside a folder.** When a search result is a book that lives outside the current folder (or in a different one), tapping it should *navigate to where it lives* — exactly what you described. Concretely: search results show a small folder-chip badge ("in: Marvel Events" or "Library") and tapping sets `currentFolderID` to that book's folder and scrolls/focuses it. You already have `focusedComic` + a focus ring in `ComicCellModifiers`, so "take me to the book and highlight it" is a small extension of existing behavior.

3. **A breadcrumb / scope header.** Reuse `LibraryHeaderView`. When `currentFolderID != nil`, show `All Books › Marvel Events` with the folder name tappable to pop back out. On iPad this also gives you a clear back affordance.

### Putting books *into* folders

You already have everything needed:

- **Context menu** (`ComicCellModifiers.swift`) — add an `"Add to Folder ▸"` submenu listing folders + "New Folder…". This works on both platforms and is the primary path on iPad.
- **Selection mode + bulk** — you have `isSelectionMode`, `selectedComics`, and `BulkEditSheet`. Add "Add Selected to Folder" to `LibrarySelectionBar`. This is the fast way to fill a folder.
- **Drag and drop** — macOS-first nicety: drag a cover onto a sidebar folder. Lower priority; the context menu covers the need.

### Effort estimate

Schema + model + DB CRUD is a day. ViewModel + sidebar + scoping filter + context-menu/bulk add is 2–3 days. Search-navigates-to-folder polish is another day. Call it **~1 week** for a solid v1, less if you skip nesting and drag-drop initially.

---

## 2. iPad Info Panel

### What exists today

On macOS the info panel is a real SwiftUI `.inspector(isPresented:)` column (`LibraryView.swift` line ~328) rendering `ComicInspectorView`, triggered by the toolbar button. `ComicInspectorView` already renders the cover + all the filled metadata fields (`InspectorField`), and already has `#if os(macOS)`/`#else` branches for `NSImage`/`UIImage` — so **the panel itself already works on iPad**; iPad just has no way to *summon* it. That's good news: you mostly need triggers, not a new panel.

> On metadata showing up: `ComicInspectorView` already displays the filled-in metadata. If any fields you care about (tags, rating, ComicVine credits, content rating) aren't shown, that's a quick addition to the existing field list rather than new infrastructure. Tell me which fields feel missing.

### The iPad trigger you described (long-press → zoomed cover + info)

SwiftUI gives you this almost for free with the **`.contextMenu(menuItems:preview:)`** variant. Your iPad cells already use `.contextMenu` (in `ComicCellModifiers`). Switching to the preview-bearing initializer means a long-press shows a **large, zoomed rendering of the cover** floating above the blurred library, with the menu beneath it — which is exactly the "bigger zoomed-in version of the cover" you asked for, and it's the native iOS idiom users already expect.

```swift
.contextMenu {
    Button { actions.showInfo(comic) } label: { Label("Show Info", systemImage: "info.circle") }
    // ... existing Read / Edit / Mark Read / etc.
} preview: {
    ComicCoverPreview(comic: comic)   // large cover + title; ~70% screen width
}
```

Then add **"Show Info"** to that menu, wired to present `ComicInspectorView`. On iPad, present it as a **sheet** (`.sheet` with `.presentationDetents([.medium, .large])`) rather than the side inspector — the half-sheet that you can drag up to full is the right iPad pattern and reuses the panel you already have. You already use the `ComicID`-wrapped `.sheet(item:)` pattern in `LibraryView`, so this slots in cleanly.

So the iPad info flow becomes: **long-press → zoomed cover preview + menu → "Show Info" → metadata half-sheet.** Native, discoverable, no custom gesture code.

### Metadata while reading

Your `ReaderControlsOverlay` already has a top bar of buttons (close, thumbnail grid, spread, fullscreen, and an **ellipsis "…" menu** at line ~253) plus the bottom page-nav. Two clean options, and they're not mutually exclusive:

**Option A — Info in the existing overlay (lowest effort, recommended first).** Add an `info.circle` button to the top bar, or an "Info" item to the ellipsis menu. Tapping slides up a **semi-transparent metadata panel from the bottom** — your own instinct, and the right one. Because the reader overlay already auto-hides, the info panel rides the same show/hide state; when you tap to dismiss controls, info goes with it. Make it a `.thinMaterial` / `.ultraThinMaterial` background so the page stays partly visible behind it, like you described.

**Option B — Swipe/expand from the title.** A panel that expands down from the book title at the top. More custom gesture work, more delight, but more risk. I'd ship A for beta and consider B later if testers want it.

Concretely for A: a `ReaderInfoPanel` view bound to a `@State showingInfo` in the reader, presented as a bottom `.safeAreaInset` or an overlay with `.transition(.move(edge: .bottom))` and `.background(.ultraThinMaterial)`. It shows the same fields as `ComicInspectorView` (you could extract a shared `ComicMetadataList` subview so the inspector, the iPad sheet, and the reader panel all render identical field rows — worth doing to avoid three copies drifting apart).

### Effort estimate

Preview-enabled context menu + "Show Info" sheet on iPad: **~1 day.** Reader bottom info panel: **~1 day.** Extracting a shared `ComicMetadataList`: a couple hours and pays for itself.

---

## 3. Quality-of-life ideas before TestFlight beta

You're shipping to "the masses," so the highest-leverage QOL work is the stuff that prevents bad first impressions and bad reviews. Grouped by priority.

### Tier 1 — do before beta (these protect the launch)

- **First-run / empty-library experience.** You have `LibraryEmptyStateView` and a `WelcomeSheet`. Make sure a brand-new user with zero books lands somewhere that *tells them what to do first* (point at an import folder, or drop files). The #1 cause of beta churn is "I opened it and didn't know what to do."
- **Crash & error visibility.** Beta testers won't send you logs. Wire up lightweight crash reporting (TestFlight gives you crashes automatically, but consider something like Sentry or at least make `AppLog` exportable from Settings — "Export Diagnostics" button that zips logs). You already have `AppLog`; surfacing it is cheap.
- **Graceful handling of `needsAttention` / missing files.** You already track `needsAttention` when a file move fails or a file is missing. Make sure the UI clearly shows these and offers a "locate file" recovery, because security-scoped bookmarks (`bookmarkData`) on iOS/iPadOS break in ways that confuse users when iCloud or external drives are involved.
- **"What's New" / feedback loop.** A simple in-app "Send Feedback" button (mailto or a form) so testers report without leaving the app. TestFlight has built-in feedback, but an in-app nudge dramatically increases response rate.
- **iCloud / sync expectations set clearly.** If reading progress and library *don't* sync across a user's iPad and Mac yet, say so somewhere, because people will assume it does and report it as a bug. (See questions — is sync in scope?)

### Tier 2 — high delight, moderate effort

- **Reading streaks / "Continue Reading" shelf.** You already track `lastReadDate`, `currentPage`, `totalPages`, `status`. A "Continue Reading" row at the top of the library (books with progress > 0 and < 100%) is mostly a query you already can run, and it's the single most-loved feature in reader apps.
- **Smart folders / saved filters.** Since folders are landing as a filter layer (section 1), a "smart folder" is just a *saved* filter (e.g. "Unread Marvel from the 80s"). Tiny incremental work, big perceived value. Your `favorites` and `reading list` are already proto-smart-folders.
- **Sort within folders + manual ordering.** Let users hand-order a folder (`sort_order` is in the v20 schema above). Reading-order matters a lot for comic events/runs.
- **Bulk metadata from ComicVine with progress + undo.** You have batch ComicVine fetch and a review queue. Make sure there's an undo / "revert this fetch" since `metadataFetchedAt` gates re-fetching — a tester who fetches wrong data needs an escape hatch.
- **Per-book "mark unread / reset progress."** Small, frequently wanted, prevents "how do I start over" tickets.

### Tier 3 — nice, post-beta candidates

- **Reading stats / year-in-review.** You have a Dashboard with insights already; "books read this month," pages read, busiest day. Cheap dopamine.
- **Cover customization** — pick a different page as the cover. You generate covers (`regenerateCover`); letting users choose the source page is a natural extension.
- **Series auto-grouping & "next issue" suggestions.** You have series metadata and a knowledge base; "you're on issue #4, read #5 next" is a strong retention hook.
- **Accessibility pass** — Dynamic Type, VoiceOver labels on cells, reduce-motion respect on page transitions. Apple reviewers and a chunk of users will notice. Worth a dedicated half-day before public release.
- **Haptics on iPad** for page turns / long-press — small, makes the app feel finished.
- **Export / backup the library DB.** A "back up my catalog" button buys enormous goodwill if anything ever corrupts; cheap given GRDB is a single file.

### My top 5 if you only do five before beta

1. Rock-solid first-run/empty state (don't lose people in the first 60 seconds).
2. In-app feedback button + exportable diagnostics.
3. "Continue Reading" shelf (uses data you already have).
4. Clear handling/recovery for missing-file / `needsAttention` books.
5. Library backup/export (insurance against the one corruption bug that tanks your rating).

---

## Questions for you (answer these and I'll start building)

1. **Folder model:** OK to go many-to-many (a book can live in multiple folders), with folders as a *virtual* layer that never moves files on disk? Or do you specifically want one-folder-per-book, or folders that physically reorganize files? *(This is the one that blocks everything in section 1.)*

2. **Nested folders:** Want folders-inside-folders in v1, or flat for now? (Schema supports nesting either way; this is just about UI scope.)

3. **iPad info panel presentation:** Half-sheet you can drag to full (my recommendation) vs. a full-screen cover, when summoned via long-press?

4. **Metadata-while-reading:** Start with the bottom semi-transparent panel (Option A, lowest risk) for beta, and revisit the slide-from-title idea later? Or do you want the fancier version up front?

5. **Missing metadata fields:** Are there specific fields not currently showing in the info panel that you want surfaced (tags? rating? ComicVine credits? content rating?), or does the existing `ComicInspectorView` field set cover it?

6. **Sync:** Is cross-device sync (iPad ↔ Mac library + reading progress) in scope for beta, or explicitly out? This changes how I'd advise framing things to testers.

7. **Beta QOL priority:** Of the Tier-1 list, anything you consider out of scope, and anything from Tier 2/3 you want pulled forward?

8. **Build order:** I'd suggest folders first (biggest structural change, best to land while the codebase is fresh in mind), then iPad info, then QOL. Agree, or is iPad info more urgent for your testers?
