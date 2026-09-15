# Custom Book Cover — Design

**Date:** 2026-09-14
**Status:** Approved for planning

## Purpose

Let the user set their own image as a book's cover. Primary motivation: webcomic
CBZs, whose first pages (often very tall vertical strips) make poor covers — the
existing 800px-max-dimension downsample turns a 1600×20000 strip into a sliver.
A user-supplied image sidesteps this entirely.

## Scope decisions (locked)

- **Storage: database only.** The custom cover is not written into the CBZ/CBR/
  PDF/EPUB file. An "embed cover into file" action may follow later; nothing in
  this design blocks it.
- **Entry points (macOS):** book context menu, edit-metadata sheet cover thumb
  (hover pencil), and drag-and-drop of an image onto that thumb.
- **iOS/iPadOS:** supported — *Choose from Photos…* and *Choose from Files…*,
  mirroring the existing folder-cover flow.
- **Out of scope:** picking a page from inside the book as the cover ("Use
  Page…"), bulk custom covers for multi-selection, embedding into the archive.

## Architecture — separate column (Approach A)

The custom cover lives in its own blob column beside the extracted one. The
extracted first-page cover is never touched.

- `Comic.customCoverImageData: Data?` — new field on the `Comic` struct
  (`Models/Comic.swift`), GRDB column `custom_cover_image_data` (Columns enum,
  encode, decode — same pattern as `coverImageData` at lines 43/770/833/937).
- Migration `v34_custom_cover` in
  `Services/Database/DatabaseManager.swift` (current head is
  `v33_trash_entries`): `ALTER TABLE … ADD COLUMN custom_cover_image_data BLOB`.
- Computed property on `Comic`:
  `var displayCoverData: Data? { customCoverImageData ?? coverImageData }`.
  All cover render sites switch from `coverImageData` to `displayCoverData`.

**Why this shape wins:** the three code paths that overwrite covers today —
`regenerateCoverSingle` (`LibraryViewModel.swift:389-442`), rescan merge
(`Comic+Merge.swift:76`), and `.scobook` import (`TransferManifest.swift:392`)
— all write only `coverImageData`. With a separate column the custom cover is
protected structurally; no guard code is added to any of them, and no future
extracted-cover writer can silently destroy a custom cover. "Remove Custom
Cover" is a nil-out of the column: instant, and works even when the source file
is offline or the sandbox grant is stale.

**Cost accepted:** both blobs are stored for a custom-covered book
(~100–300 KB extra each); render sites are touched once to adopt
`displayCoverData`.

### Byte handling and cache

- Incoming images are normalized via the existing
  `PageImageCache.storageCoverData(from:)` (`ComicReaderProtocol.swift:280`) —
  downsample to 800px max dimension, JPEG q0.85 — before persisting.
- No cache-invalidation plumbing: `coverImage(from:cacheKey:)` keys embed
  `data.count`, so changed bytes re-decode naturally. Render sites already pass
  the data they hold, so switching which data they pass is sufficient.

## Components

### 1. ViewModel actions (`ViewModels/LibraryViewModel.swift`)

Modeled on `setFolderCover(_:imageData:)` / `clearFolderCover(_:)`
(lines ~2008–2035):

- `setCustomCover(for comic: Comic, imageData: Data)` — normalize via
  `storageCoverData`, set `customCoverImageData`, persist, log an
  `ActivityEvent` ("Set custom cover").
- `clearCustomCover(for comic: Comic)` — nil the field, persist, log
  ("Removed custom cover"). Exposed only when `customCoverImageData != nil`.

Custom-cover changes do **not** trigger the ComicInfo auto-embed pipeline
(`comicInfoFieldsChanged` doesn't include cover fields — unchanged).

### 2. Context menu (`Views/Library/ComicCellModifiers.swift`)

The existing flat `Regenerate Cover` item (line ~292) becomes a
`Menu("Cover")`, vocabulary mirroring the folder menu
(`LibraryFolderGridView.swift:189-213`):

- macOS: *Choose Picture…*
- iOS: *Choose from Photos…*, *Choose from Files…*
- *Regenerate Cover* (existing behavior, re-extracts page 1 into
  `coverImageData`; unchanged, still visible regardless of custom state)
- Divider, then *Remove Custom Cover* — only when `customCoverImageData != nil`.

Wiring: add `setCustomCover: (Comic) -> Void` (opens picker) and
`removeCustomCover: (Comic) -> Void` to `ComicCellActions` (line ~15),
connected in `Views/Library/LibraryView.swift` (~line 419) beside
`regenerateCover`.

### 3. Picker plumbing (`Views/Library/LibraryView.swift`)

Copies the folder-cover flow:

- `@State var comicPendingCoverPicture: Comic?` + `showingComicCoverPicker`;
  iOS adds `comicPendingCoverPhoto` + `PhotosPickerItem` state.
- macOS `.fileImporter(allowedContentTypes: [.image])` → handler reads the URL
  inside `startAccessingSecurityScopedResource()` / `defer stop` (one-shot
  read; no persistent bookmark needed) → `setCustomCover`.
- **Constraint:** only one `.fileImporter` per view is honored (documented at
  `LibraryView.swift:717`). The new importer follows the established
  `Color.clear.fileImporter(...)` background-ZStack workaround (see lines
  722/745/758) so Quick Add and folder-cover importers keep working.
- iOS: a modifier parallel to `FolderCoverPhotoPickerModifier`
  (`LibraryView.swift:1713`) for PhotosPicker, plus the Files path through the
  same fileImporter pattern.

### 4. Edit-metadata sheet (`Views/Library/ComicDetailView.swift`, headerView ~581)

The 120×180 cover thumb gains, per the `PublisherBannerView` template
(lines 87–142, 211):

- Hover pencil overlay (macOS) / tap affordance (iOS) opening the same picker.
- `.onDrop(of: [.image])` using
  `loadDataRepresentation(forTypeIdentifier: UTType.image.identifier)` →
  `setCustomCover`.
- The thumb renders `displayCoverData` like everywhere else.

### 5. Render-site adoption (mechanical)

Switch `comic.coverImageData` → `comic.displayCoverData` at:
`ComicCardView.swift:112`, `ComicCellModifiers.swift:520` (zoom preview),
`ComicDetailView.swift:569`, `ComicInspectorView.swift:51-66`,
`LibraryListView.swift`, `LibraryFolderGridView.swift:313/750` (collage),
`LibraryPublisherBrowseView.swift:187`, `DashboardReadingView.swift:325`,
`NextIssuePreviewOverlay.swift:21`.

`DashboardHealthView.swift:182` missing-cover count uses
`displayCoverData == nil` so a custom cover counts as having a cover.

## Data flow

1. User picks/drops an image → raw `Data` read once (no bookmark kept).
2. `setCustomCover` → `storageCoverData` normalize → assign
   `customCoverImageData` → `persistComic` → activity log.
3. Views re-render via `displayCoverData`; cache re-decodes because the byte
   count changed.
4. *Remove Custom Cover* → nil column → extracted cover reappears instantly.

## Error handling

- Unreadable/undecodable image (`storageCoverData` returns nil): surface the
  existing alert pattern used by folder-cover import ("Couldn't read that
  image"); nothing is persisted.
- File-importer cancel: no-op.
- Oversized images are inherently handled by the 800px normalize.

## Testing

- Model/GRDB round-trip: `customCoverImageData` encodes/decodes;
  v34 migration runs on a v33 fixture.
- Precedence: `displayCoverData` returns custom when present, extracted
  otherwise, nil when both absent.
- Protection: `regenerateCoverSingle`, `Comic.merged`, and transfer import
  leave `customCoverImageData` untouched (regression tests).
- Normalization: a tall strip input comes out ≤800px max dimension.
- Manual: context menu on macOS, Photos/Files pickers on iOS, drag-drop on the
  edit sheet, remove-and-restore, health-check count.

## Future (explicitly deferred)

- *Embed cover into file*: write the custom image as the first archive entry
  (and/or ComicInfo `<Pages>` cover annotation) via the `CBZMetadataEmbedder`
  machinery. The DB-first design keeps the custom bytes available for this.
- "Use Page…" in-book page picker.
