# Custom Book Cover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user set their own image as a book's cover (database-only), with the extracted first-page cover preserved underneath so removal is instant.

**Architecture:** A new `custom_cover_image_data` blob column beside the existing `cover_image_data` on the `comics` table. A computed `Comic.displayCoverData` (`customCoverImageData ?? coverImageData`) is adopted by every cover render site. All existing cover writers (regenerate, rescan merge, transfer import) keep writing the extracted column, so the custom cover is protected structurally. Spec: `docs/superpowers/specs/2026-09-14-custom-book-cover-design.md`.

**Tech Stack:** Swift / SwiftUI (multiplatform macOS + iOS single target), GRDB 7 (struct `Comic`, hand-written `Columns`/`encode`/`init(row:)`), Swift Testing (`@Suite`/`@Test`/`#expect`) in target `SCO-OSXCursorTests`.

## Global Constraints

- The Xcode project uses **file-system-synchronized groups** — creating a file on disk under `SCO-OSXCursor/` or `SCO-OSXCursorTests/` adds it to the target automatically; never edit `project.pbxproj`.
- Build gate for every task: `xcodebuild build -project SCO-OSXCursor.xcodeproj -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet 2>&1 | tail -5` → must end with `** BUILD SUCCEEDED **` (warnings tolerated, errors not).
- Test command: `xcodebuild test -project SCO-OSXCursor.xcodeproj -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/CustomCoverTests -quiet 2>&1 | tail -20`.
- **SwiftUI honors only ONE `.fileImporter` per view** (documented at `SCO-OSXCursor/Views/Library/LibraryView.swift:717`). Every new importer in `LibraryView` goes on its own `Color.clear` background view; the one in `ComicDetailView` attaches to the cover-thumb subview.
- Custom cover bytes are ALWAYS normalized through `PageImageCache.storageCoverData(from:)` (800px-max JPEG) before persisting.
- Menu vocabulary mirrors the folder cover menu (`LibraryFolderGridView.swift:189-213`): "Choose Picture…" (macOS), "Choose from Photos…" / "Choose from Files…" (iOS).
- `customCoverImageData` is deliberately NOT a `Comic.init` parameter — every constructor yields "no custom cover"; only explicit user action sets it. Consequence: any code that rebuilds a `Comic` via `init` from an existing one must carry the field over explicitly (today only `Comic.merged`).
- All `Comic` line numbers below are pre-change positions; apply edits top-to-bottom within a file.
- Working branch: `claude/comicinfo-xml-cbz-g74p8p`. Commit after every task with the attribution trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Comic model — field, `displayCoverData`, merge preservation

**Files:**
- Modify: `SCO-OSXCursor/Models/Comic.swift:42-43`
- Modify: `SCO-OSXCursor/Models/Comic+Merge.swift:88-134`
- Test (create): `SCO-OSXCursorTests/CustomCoverTests.swift`

**Interfaces:**
- Consumes: existing `Comic` struct (memberwise-style init, synthesized Codable), `Comic.merged(existing:extracted:)`.
- Produces: `var customCoverImageData: Data?` (stored, defaults nil, not an init param) and `var displayCoverData: Data? { customCoverImageData ?? coverImageData }` on `Comic`. Every later task uses exactly these names.

- [ ] **Step 1: Write the failing tests**

Create `SCO-OSXCursorTests/CustomCoverTests.swift`:

```swift
//
//  CustomCoverTests.swift
//  SCO-OSXCursorTests
//
//  Custom book covers: display precedence, Codable round-trip, and
//  rescan-merge preservation.
//

import Foundation
import Testing

#if os(macOS)
    import AppKit
#endif

@testable import SCO_OSXCursor

@Suite struct CustomCoverTests {

    private func makeComic() -> Comic {
        Comic(
            filePath: URL(fileURLWithPath: "/tmp/lib/Webtoon/Strip #001.cbz"),
            fileName: "Strip #001.cbz",
            coverImageData: Data([0x01, 0x02])
        )
    }

    @Test func displayCoverPrefersCustomAndRestoresExtracted() {
        var c = makeComic()
        #expect(c.displayCoverData == Data([0x01, 0x02]))
        c.customCoverImageData = Data([0x0A, 0x0B])
        #expect(c.displayCoverData == Data([0x0A, 0x0B]))
        c.customCoverImageData = nil
        #expect(c.displayCoverData == Data([0x01, 0x02]))
    }

    @Test func displayCoverNilWhenBothAbsent() {
        var c = makeComic()
        c.coverImageData = nil
        #expect(c.displayCoverData == nil)
    }

    @Test func codableRoundTripKeepsCustomCover() throws {
        var c = makeComic()
        c.customCoverImageData = Data([0x0A, 0x0B])
        let decoded = try JSONDecoder().decode(Comic.self, from: JSONEncoder().encode(c))
        #expect(decoded.customCoverImageData == Data([0x0A, 0x0B]))
    }

    // Trash snapshots and .scobook manifests written before this feature
    // have no customCoverImageData key — they must decode to nil, not throw.
    @Test func decodingSnapshotWithoutFieldYieldsNil() throws {
        let decoded = try JSONDecoder().decode(
            Comic.self, from: JSONEncoder().encode(makeComic()))
        #expect(decoded.customCoverImageData == nil)
    }

    @Test func rescanMergePreservesCustomCover() {
        var existing = makeComic()
        existing.customCoverImageData = Data([0x0A, 0x0B])
        var extracted = makeComic()
        extracted.coverImageData = Data([0x03, 0x04])  // fresh first-page extraction
        let merged = Comic.merged(existing: existing, extracted: extracted)
        #expect(merged.customCoverImageData == Data([0x0A, 0x0B]))
        #expect(merged.coverImageData == Data([0x03, 0x04]))
        #expect(merged.displayCoverData == Data([0x0A, 0x0B]))
    }

    // The webcomic case: normalization must cap the long side at 800 px, so
    // a picked image never bloats the DB (and the sliver problem the custom
    // cover exists to fix stays fixed for the stored bytes).
    #if os(macOS)
        @Test func storageNormalizationCapsTallStrips() throws {
            let size = NSSize(width: 200, height: 4000)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.red.setFill()
            NSRect(origin: .zero, size: size).fill()
            image.unlockFocus()
            let raw = try #require(PageImageCache.jpegData(from: image, quality: 0.9))
            let stored = try #require(PageImageCache.storageCoverData(from: raw))
            let rep = try #require(NSBitmapImageRep(data: stored))
            #expect(max(rep.pixelsWide, rep.pixelsHigh) <= 800)
        }
    #endif
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command from Global Constraints.
Expected: **compile failure** — `value of type 'Comic' has no member 'customCoverImageData'` (in Swift, a missing member is the "failing test" state).

- [ ] **Step 3: Add the field and computed property**

In `SCO-OSXCursor/Models/Comic.swift`, replace lines 42-43:

```swift
    // MARK: - Cover & Visual
    var coverImageData: Data?
```

with:

```swift
    // MARK: - Cover & Visual
    var coverImageData: Data?
    /// User-picked cover picture. Overrides the extracted first-page cover
    /// everywhere covers render; the extracted bytes stay untouched
    /// underneath, so removing the custom picture restores them instantly.
    /// Deliberately NOT an init parameter — every constructor produces
    /// "no custom cover"; only explicit user action sets it.
    var customCoverImageData: Data? = nil

    /// The cover to render: the custom picture when set, else the extracted
    /// first-page cover. Display sites use this, never `coverImageData`.
    var displayCoverData: Data? { customCoverImageData ?? coverImageData }
```

- [ ] **Step 4: Preserve the custom cover through rescan merges**

In `SCO-OSXCursor/Models/Comic+Merge.swift`, the second (existing-comic) branch: change line 88 `return Comic(` to `var merged = Comic(`, and replace the closing of that call (line 134, `        )` followed by `    }`) with:

```swift
        )
        // The custom cover isn't an init parameter (see Comic.swift), so a
        // rebuilt merge result must carry it over or a rescan would drop it.
        merged.customCoverImageData = existing.customCoverImageData
        return merged
    }
```

(The first branch — `guard let existing else` — needs nothing: a brand-new import has no custom cover.)

- [ ] **Step 5: Run tests to verify they pass**

Run the test command. Expected: 6 tests pass (`Test run with 6 tests passed`).

- [ ] **Step 6: Commit**

```bash
git add SCO-OSXCursor/Models/Comic.swift SCO-OSXCursor/Models/Comic+Merge.swift SCO-OSXCursorTests/CustomCoverTests.swift
git commit -m "feat(model): custom cover field with display precedence

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: GRDB persistence + v34 migration

**Files:**
- Modify: `SCO-OSXCursor/Models/Comic.swift:770,833,978` (persistence extension)
- Modify: `SCO-OSXCursor/Services/Database/DatabaseManager.swift:762` (after the v33 block)

**Interfaces:**
- Consumes: `Comic.customCoverImageData` from Task 1.
- Produces: column `custom_cover_image_data` (BLOB, nullable) on table `comics`, round-tripped by `Comic.encode(to:)` / `Comic.init(row:)`.

- [ ] **Step 1: Add the column constant**

In `SCO-OSXCursor/Models/Comic.swift`, after line 770 (`static let coverImageData = Column("cover_image_data")`), add:

```swift
        static let customCoverImageData = Column("custom_cover_image_data")
```

- [ ] **Step 2: Encode it**

After line 833 (`container[Columns.coverImageData] = coverImageData`), add:

```swift
        container[Columns.customCoverImageData] = customCoverImageData
```

- [ ] **Step 3: Decode it**

`Comic.init(row:)` funnels through `self.init(...)` (ends line 978), which can't take the new field. Immediately after that call's closing `)`, add:

```swift
        // Not an init parameter (see the property's doc comment) — read it
        // off the row after the memberwise pass.
        customCoverImageData = row["custom_cover_image_data"]
```

- [ ] **Step 4: Register the migration**

In `SCO-OSXCursor/Services/Database/DatabaseManager.swift`, after the `v33_trash_entries` block (its closing `}` is line 762), before `return migrator`, add:

```swift
        // Version 34: user-picked custom book covers. Lives beside the
        // extracted cover so regenerate/rescan/transfer keep writing
        // cover_image_data without ever touching the user's choice.
        migrator.registerMigration("v34_custom_cover") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v34_custom_cover")
            do {
                try db.alter(table: "comics") { t in
                    t.add(column: "custom_cover_image_data", .blob)
                }
                AppLog.database.info("[DatabaseManager] ✅ Added custom_cover_image_data column")
            } catch {
                AppLog.database.error("[DatabaseManager] ℹ️ custom_cover_image_data column may already exist: \(error.localizedDescription)")
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v34_custom_cover complete")
        }
```

(Fresh installs run v1→v34 in order, so `createComicsTable` needs no change; the do/catch mirrors the v32 pattern.)

- [ ] **Step 5: Build**

Run the build gate. Expected: `** BUILD SUCCEEDED **`. Also run the full Task 1 test command again — still 6 passing (encode/decode round-trip through a live DB is verified manually at the end of Task 5; unit tests can't reach the singleton `DatabaseManager`).

- [ ] **Step 6: Commit**

```bash
git add SCO-OSXCursor/Models/Comic.swift SCO-OSXCursor/Services/Database/DatabaseManager.swift
git commit -m "feat(db): persist custom cover in v34 migration

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: ViewModel actions + activity event

**Files:**
- Modify: `SCO-OSXCursor/Models/ActivityEvent.swift:33,55,77` (three switch sites)
- Modify: `SCO-OSXCursor/ViewModels/LibraryViewModel.swift:443` (after `regenerateCoverSingle`)

**Interfaces:**
- Consumes: `Comic.customCoverImageData`, `PageImageCache.storageCoverData(from:)` (`ComicReaderProtocol.swift:280`), existing `updateComic(_:)` and `logActivity(_:comic:old:new:)` (`LibraryViewModel.swift:273`).
- Produces: `@discardableResult func setCustomCover(for comic: Comic, imageData rawData: Data) -> Bool` and `func clearCustomCover(for comic: Comic)` on `LibraryViewModel`; `ActivityEvent.ActionType.coverChanged`. Tasks 5–6 call exactly these.

- [ ] **Step 1: Add the activity case**

In `SCO-OSXCursor/Models/ActivityEvent.swift`:
- After line 33 (`case favoriteToggled = "favorite_toggled"`) add:

```swift
        case coverChanged = "cover_changed"
```

- In `displayName` after line 55 (`case .favoriteToggled: return "Favorite Toggled"`) add:

```swift
            case .coverChanged: return "Cover Updated"
```

- In `icon` after line 77 (`case .favoriteToggled: return "heart.fill"`) add:

```swift
            case .coverChanged: return "photo.fill"
```

(`color` has a `default: return "primary"` — no change needed. The compiler enforces exhaustiveness on the other two switches, so a missed site is a build error.)

- [ ] **Step 2: Add the ViewModel actions**

In `SCO-OSXCursor/ViewModels/LibraryViewModel.swift`, after `regenerateCoverSingle`'s closing `}` (line 443), add:

```swift
    // MARK: - Custom book covers

    /// Assign a user-picked picture as the book's cover. Bytes are
    /// downsampled to a storage-friendly JPEG (max 800 px) before saving.
    /// The extracted first-page cover is kept untouched underneath, so
    /// removing the custom picture restores it instantly.
    /// Returns false when the bytes can't be decoded as an image.
    @discardableResult
    func setCustomCover(for comic: Comic, imageData rawData: Data) -> Bool {
        guard let normalized = PageImageCache.storageCoverData(from: rawData) else {
            AppLog.library.error(
                "[LibraryViewModel] ❌ Could not decode custom cover image for \(comic.fileName)")
            return false
        }
        var updated = comic
        updated.customCoverImageData = normalized
        updated.dateModified = Date()
        updateComic(updated)
        Task { await logActivity(.coverChanged, comic: updated, old: nil, new: "Custom picture") }
        AppLog.library.info("[LibraryViewModel] ✅ Custom cover set for \(comic.fileName)")
        return true
    }

    /// Remove the custom picture; the extracted first-page cover shows again.
    func clearCustomCover(for comic: Comic) {
        guard comic.customCoverImageData != nil else { return }
        var updated = comic
        updated.customCoverImageData = nil
        updated.dateModified = Date()
        updateComic(updated)
        Task { await logActivity(.coverChanged, comic: updated, old: "Custom picture", new: "Extracted cover") }
    }
```

Note: if `logActivity`'s parameter labels differ from `old:`/`new:` (check the definition at line 273), match the definition — the call sites at lines 183-223 show the exact labels in use.

- [ ] **Step 3: Build**

Run the build gate. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add SCO-OSXCursor/Models/ActivityEvent.swift SCO-OSXCursor/ViewModels/LibraryViewModel.swift
git commit -m "feat(library): set/clear custom cover actions with activity log

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Adopt `displayCoverData` at every render site

**Files (modify only — each edit swaps `coverImageData` → `displayCoverData` on the named expression):**

| File:line | Expression to change |
|---|---|
| `SCO-OSXCursor/Views/Library/ComicCardView.swift:112` | `comic.coverImageData` |
| `SCO-OSXCursor/Views/Library/LibraryListView.swift:95` | `comic.coverImageData` |
| `SCO-OSXCursor/Views/Library/ComicCellModifiers.swift:520` | `comic.coverImageData` (iPad zoom preview) |
| `SCO-OSXCursor/Views/Library/ComicInspectorView.swift:53` | `comic.coverImageData` |
| `SCO-OSXCursor/Views/Library/ComicDetailView.swift:569` | `editedComic.coverImageData` |
| `SCO-OSXCursor/Views/Library/LibraryPublisherBrowseView.swift:187` | `firstComic.coverImageData` |
| `SCO-OSXCursor/Views/Library/LibraryFolderGridView.swift:313` | `previewComics[index].coverImageData` (collage) |
| `SCO-OSXCursor/Views/Library/LibraryFolderGridView.swift:422,424` | `comic.coverImageData` (representative book, both the `!= nil` check and `imageData:`) |
| `SCO-OSXCursor/Views/Library/LibraryFolderGridView.swift:624,900` | `comic.coverImageData` |
| `SCO-OSXCursor/Views/Library/LibraryView.swift:823,826` | `$0.coverImageData != nil` and `sample?.coverImageData` (folder sample) |
| `SCO-OSXCursor/Views/Dashboard/DashboardReadingView.swift:327` | `comic.coverImageData` |
| `SCO-OSXCursor/Views/Dashboard/DashboardHealthView.swift:182` | `$0.coverImageData == nil` → `$0.displayCoverData == nil` (a custom cover counts as having a cover) |
| `SCO-OSXCursor/Views/Dashboard/DashboardHealthView.swift:515` | `comic.coverImageData` |
| `SCO-OSXCursor/Views/Knowledge/KnowledgeDetailView.swift:299` | `comic.coverImageData` |
| `SCO-OSXCursor/Views/Reader/NextIssuePreviewOverlay.swift:22` | `comic.coverImageData` |
| `SCO-OSXCursor/Services/TrashService.swift:91` | `comic.coverImageData` (trash thumb should match what the user saw) |
| `SCO-OSXCursor/Services/Transfer/BookPackageExporter.swift:129` | `comic.coverImageData` (exported .scobook carries the cover the user actually sees) |

**Do NOT touch** (they correctly write/read the *extracted* column): `LibraryViewModel.swift:440,877,1823`, `Comic+Merge.swift`, `TransferManifest.swift:180,296,392`, all `Folder` cover code, `TrashServiceTests.swift`.

**Interfaces:**
- Consumes: `Comic.displayCoverData` from Task 1.
- Produces: nothing new — behavior-only change. (`LibraryFolderGridView:205` stays `folder.coverImageData` — that's a `Folder`, not a `Comic`.)

- [ ] **Step 1: Apply every substitution in the table**

Each is a one-token rename inside an existing expression; the grep

```bash
grep -rn "coverImageData" --include="*.swift" SCO-OSXCursor/Views SCO-OSXCursor/Services/TrashService.swift SCO-OSXCursor/Services/Transfer/BookPackageExporter.swift
```

must afterwards show **no `Comic`-typed `coverImageData` reads left in Views** — remaining hits are `Folder.coverImageData` (folder grid/`LibraryView` folder menus) and the write sites listed above.

- [ ] **Step 2: Build and test**

Run the build gate (expect `** BUILD SUCCEEDED **`) and the full existing test suite:

```bash
xcodebuild test -project SCO-OSXCursor.xcodeproj -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add -A SCO-OSXCursor/Views SCO-OSXCursor/Services
git commit -m "feat(ui): render displayCoverData so custom covers show everywhere

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Context-menu "Cover" submenu + LibraryView picker plumbing

**Files:**
- Modify: `SCO-OSXCursor/Views/Library/ComicCellModifiers.swift:44,293-297`
- Modify: `SCO-OSXCursor/Views/Library/LibraryView.swift:100,448,765,1177,1713`

**Interfaces:**
- Consumes: `viewModel.setCustomCover(for:imageData:) -> Bool`, `viewModel.clearCustomCover(for:)` (Task 3); `comic.customCoverImageData` (Task 1).
- Produces: `ComicCellActions.setCustomCover`, `.setCustomCoverFromPhotos`, `.removeCustomCover` — all `(Comic) -> Void` with `{ _ in }` defaults, declared (and wired) in this order immediately after `embedMetadata`.

- [ ] **Step 1: Extend `ComicCellActions`**

In `SCO-OSXCursor/Views/Library/ComicCellModifiers.swift`, after line 44 (`var embedMetadata: (Comic) -> Void = { _ in }`), add:

```swift
    /// Open the image file picker to set a user-chosen cover picture.
    var setCustomCover: (Comic) -> Void = { _ in }
    /// iOS only: pick the custom cover from the Photos library.
    var setCustomCoverFromPhotos: (Comic) -> Void = { _ in }
    /// Drop the custom picture; the extracted first-page cover returns.
    var removeCustomCover: (Comic) -> Void = { _ in }
```

- [ ] **Step 2: Replace the flat Regenerate item with a Cover submenu**

Replace lines 293-297:

```swift
        if showsRegenerate {
            Button(action: { actions.regenerateCover(comic) }) {
                Label("Regenerate Cover", systemImage: "arrow.clockwise.circle")
            }
        }
```

with (vocabulary mirrors the folder Set Cover menu):

```swift
        Menu {
            #if os(iOS)
                Button(action: { actions.setCustomCoverFromPhotos(comic) }) {
                    Label("Choose from Photos…", systemImage: "photo.stack")
                }
                Button(action: { actions.setCustomCover(comic) }) {
                    Label("Choose from Files…", systemImage: "folder")
                }
            #else
                Button(action: { actions.setCustomCover(comic) }) {
                    Label("Choose Picture…", systemImage: "photo")
                }
            #endif
            if showsRegenerate {
                Button(action: { actions.regenerateCover(comic) }) {
                    Label("Regenerate Cover", systemImage: "arrow.clockwise.circle")
                }
            }
            if comic.customCoverImageData != nil {
                Divider()
                Button(action: { actions.removeCustomCover(comic) }) {
                    Label("Remove Custom Cover", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Cover", systemImage: "photo.on.rectangle.angled")
        }
```

(Note: the submenu now appears even where `showsRegenerate` is false — `LibraryPublisherBrowseView.swift:273` — which is intended: those cells can still take a custom picture.)

- [ ] **Step 3: LibraryView state**

In `SCO-OSXCursor/Views/Library/LibraryView.swift`, after line 100 (`@State private var showingFolderCoverPicker = false`), add:

```swift
    /// Book awaiting a custom cover picture (drives the image file importer).
    @State private var comicPendingCoverPicture: Comic?
    @State private var showingComicCoverPicker = false
    /// "Couldn't read that image." feedback for a failed cover pick.
    @State private var coverImportErrorMessage: String?
```

Inside the existing `#if os(iOS)` state block (after line 115, `@State private var selectedPhotoItem: PhotosPickerItem?`), add:

```swift
        /// Book awaiting a cover from the Photos library (iPad/iPhone).
        @State private var comicPendingCoverPhoto: Comic?
        @State private var showingComicCoverPhotoPicker = false
        @State private var selectedComicCoverPhotoItem: PhotosPickerItem?
```

- [ ] **Step 4: Wire `cellActions`**

In the `cellActions` builder, after line 448 (`embedMetadata: { embedMetadataSingle($0) },`) — order must match the struct's declaration order — add:

```swift
            setCustomCover: { comic in
                comicPendingCoverPicture = comic
                showingComicCoverPicker = true
            },
            setCustomCoverFromPhotos: { comic in
                #if os(iOS)
                    comicPendingCoverPhoto = comic
                    showingComicCoverPhotoPicker = true
                #else
                    _ = comic
                #endif
            },
            removeCustomCover: { viewModel.clearCustomCover(for: $0) },
```

- [ ] **Step 5: The book-cover file importer (own background view) + error alert**

After the folder-cover importer's `.background(...)` (closes line 765), add:

```swift
        // Choose a custom cover picture for a single book
        .background(
            Color.clear.fileImporter(
                isPresented: $showingComicCoverPicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleComicCoverImport(result)
            }
        )
        .alert(
            "Couldn't Set Cover",
            isPresented: Binding(
                get: { coverImportErrorMessage != nil },
                set: { if !$0 { coverImportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coverImportErrorMessage ?? "")
        }
```

- [ ] **Step 6: Import handlers**

After `handleFolderCoverImport` / `handleFolderCoverPhoto` (ends line 1192), add:

```swift
    /// Read the picked image file and assign it as the book's custom cover.
    private func handleComicCoverImport(_ result: Result<[URL], Error>) {
        let comic = comicPendingCoverPicture
        defer { comicPendingCoverPicture = nil }
        guard case .success(let urls) = result, let url = urls.first,
            let comic = comic
        else { return }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
            viewModel.setCustomCover(for: comic, imageData: data)
        else {
            AppLog.library.error("[LibraryView] ❌ Could not read custom cover image")
            coverImportErrorMessage = "Couldn't read that image."
            return
        }
    }

    #if os(iOS)
        /// Load the chosen Photos-library item and assign it as the book's cover.
        private func handleComicCoverPhoto(_ item: PhotosPickerItem) {
            let comic = comicPendingCoverPhoto
            comicPendingCoverPhoto = nil
            selectedComicCoverPhotoItem = nil
            Task {
                guard let comic,
                    let data = (try? await item.loadTransferable(type: Data.self)) ?? nil
                else { return }
                viewModel.setCustomCover(for: comic, imageData: data)
            }
        }
    #endif
```

- [ ] **Step 7: iOS Photos picker modifier**

Rename `FolderCoverPhotoPickerModifier` (line 1713) to `CoverPhotoPickerModifier` (it is folder-agnostic — bindings in, `PhotosPickerItem` out; update its doc comment to say it serves both folder and book covers, and update the single existing use site at line 770). Then, after that existing `.modifier(...)` inside the same `#if os(iOS)` block, add a second application:

```swift
            .modifier(
                CoverPhotoPickerModifier(
                    isPresented: $showingComicCoverPhotoPicker,
                    selection: $selectedComicCoverPhotoItem,
                    onPick: { handleComicCoverPhoto($0) }
                )
            )
```

- [ ] **Step 8: Build both platforms**

Run the macOS build gate (expect `** BUILD SUCCEEDED **`), then the iOS compile check:

```bash
xcodebuild build -project SCO-OSXCursor.xcodeproj -scheme SCO-OSXCursor -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Manual verification (macOS)**

Launch the app. Right-click a book → Cover → Choose Picture… → pick an image → the grid card updates immediately. Right-click again → Remove Custom Cover → original first-page cover returns instantly. Regenerate Cover on a custom-covered book → custom cover still shows (it only refreshed the hidden extracted one). Verify the DB column exists:

```bash
sqlite3 "$(find ~/Library/Containers -name '*.sqlite' -path '*SCO*' 2>/dev/null | head -1)" "PRAGMA table_info(comics);" | grep custom_cover
```

Expected: a `custom_cover_image_data|BLOB` row. (App logging is invisible to `log show` on this Mac — verify via DB, not logs.)

- [ ] **Step 10: Commit**

```bash
git add SCO-OSXCursor/Views/Library/ComicCellModifiers.swift SCO-OSXCursor/Views/Library/LibraryView.swift
git commit -m "feat(ui): Cover context submenu with custom picture pickers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Edit-sheet cover affordance (hover pencil, click, drop)

**Files:**
- Modify: `SCO-OSXCursor/Views/Library/ComicDetailView.swift:116-127,566-595` (+ state vars near line 49, import near line 10)

**Interfaces:**
- Consumes: `editedComic.displayCoverData` / `.customCoverImageData` (Task 1), `PageImageCache.storageCoverData(from:)`. The change is staged on the `editedComic` draft — the existing `saveChanges()` (`finalComic = editedComic`, line 1140) persists it through `onSave` → `updateComic`; Cancel discards it.
- Produces: nothing consumed elsewhere.

- [ ] **Step 1: State + import**

Add `import UniformTypeIdentifiers` next to the file's existing imports if not present. Near the other `@State` vars (after line 49), add:

```swift
    @State private var isHoveringCover = false
    @State private var showingCoverPicker = false
```

- [ ] **Step 2: Count a staged cover as a change**

In `hasChanges` (lines 116-127), append to the expression:

```swift
            || editedComic.customCoverImageData != comic.customCoverImageData
```

- [ ] **Step 3: Extract the cover thumb into a click/drop target**

In `headerView` (line 566), replace the entire cover if/else (lines 568-595, from `// Cover Image` through the placeholder's closing `}`) with `coverThumb`, and add below `headerView`:

```swift
    // MARK: Cover thumb — click or drop an image to stage a custom cover

    private var coverThumb: some View {
        ZStack {
            if let coverData = editedComic.displayCoverData,
                let cover = PageImageCache.shared.coverImage(
                    from: coverData, cacheKey: editedComic.id.uuidString)
            {
                #if os(macOS)
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                #else
                    Image(uiImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                #endif
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(BackgroundColors.elevated)
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: 40))
                            .foregroundColor(TextColors.tertiary)
                    )
            }
            // Edit hint on hover (same affordance as PublisherBannerView)
            if isHoveringCover {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.45))
                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 120, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHoveringCover = $0 }
        .onTapGesture { showingCoverPicker = true }
        // Attached to this subview, not the sheet root — SwiftUI honors only
        // one .fileImporter per view (see LibraryView.swift:717).
        .fileImporter(
            isPresented: $showingCoverPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleCoverPick(result)
        }
        .onDrop(of: [.image], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { data, _ in
                guard let data else { return }
                Task { @MainActor in stageCustomCover(data) }
            }
            return true
        }
        .help("Click or drop an image to set a custom cover")
    }

    /// Normalize picked bytes and stage them on the draft — persisted when
    /// the user hits Save, discarded on Cancel.
    private func stageCustomCover(_ rawData: Data) {
        guard let normalized = PageImageCache.storageCoverData(from: rawData) else { return }
        editedComic.customCoverImageData = normalized
    }

    private func handleCoverPick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        stageCustomCover(data)
    }
```

(On iOS the tap opens the Files picker; Photos lives in the cell context menu from Task 5. Task 4 already switched line 569 to `displayCoverData` — this step restructures that same block, which is expected.)

- [ ] **Step 4: Build both platforms**

macOS build gate + the iOS compile check from Task 5 Step 8. Expected: both `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verification (macOS)**

Open a book's edit sheet: hovering the cover shows the dimmed pencil; clicking opens the image picker; picking shows the new cover immediately with "Unsaved changes" appearing; Cancel discards (reopen — old cover); repeat and Save persists (grid updates). Drag an image file from Finder onto the thumb — same staging behavior.

- [ ] **Step 6: Commit**

```bash
git add SCO-OSXCursor/Views/Library/ComicDetailView.swift
git commit -m "feat(ui): set custom cover from the edit sheet via click or drop

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] Full test suite: `xcodebuild test -project SCO-OSXCursor.xcodeproj -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet 2>&1 | tail -10` → all pass.
- [ ] Manual sweep (macOS app): custom cover shows in grid, list, publisher browse, folder collage, dashboard reading row, inspector, next-issue overlay; Dashboard health "missing cover" count treats a custom-covered book as covered; a tall webtoon CBZ gets a proper cover via Choose Picture…; Remove Custom Cover restores the strip-derived one.
- [ ] Use superpowers:finishing-a-development-branch to integrate.
