# Design — Mac → iPad Book Transfer (.scobook)

*July 3, 2026. Answers question #6 from FEATURE_PLAN_folders_ipad-info_qol_2026-06.md. Decisions confirmed with Andrew; ready to implement.*

> **Status: IMPLEMENTED (July 3, 2026).** New files: `Services/Transfer/TransferManifest.swift`, `BookPackageExporter.swift`, `BookPackageImporter.swift`, `Views/Library/TransferExportSheet.swift`, `TransferReceiveSheet.swift`. Modified: `LibraryViewModel` (+`addTransferredComic`), `ComicCellModifiers` (Send to Device… menu item), `LibraryView`/`LibraryHeaderView`/`LibrarySelectionBar` (send wiring), `ContentView` (`onOpenURL` receive flow), `Info.plist` (scobook UTType + document type). Uses ZIPFoundation (already a dependency); book entry stored uncompressed with SHA-256 computed in the same streaming pass. Needs a device test: Mac → AirDrop → iPad "Open in SCO".

## Decisions (confirmed)

1. **Transport:** `.scobook` package via share sheet / AirDrop. In-app Wi-Fi transfer (Multipeer) deferred; same package format would power it later.
2. **Duplicates:** if receiving device already has the book (UUID or file-hash match), ask the user — "Update progress & metadata" vs "Keep existing copy."
3. **Receive path built on both platforms.** Send UI exposed on Mac only for v1. iPad→Mac later = add a Send button on iPad, nothing else.
4. **iPad storage:** received books copied into the app container (app's own library directory). No security-scoped bookmark fragility.
5. **Progress indication:** in-app progress bar during package export (Mac) and import/unpack (iPad); the AirDrop leg shows the system's native progress UI on both devices.

## Package format

`SeriesName #12.scobook` — a zip containing:

- `book.<ext>` — the original file, untouched (cbz/cbr/pdf/epub)
- `manifest.json`:
  - `formatVersion` (int, start at 1), `appVersion`, `sentFrom` (platform)
  - `comicID` (UUID — preserved across devices, enables dedup)
  - `fileSHA256`, `originalFileName`, `fileSize`, `fileType`
  - **Metadata:** title, series, issueNumber, volume, year, publisher, writer, artist, coverArtist, colorist, inker, editor, summary, tags, rating, contentRating, bookFormat, comicVineVolumeID, comicVineIssueID, metadataFetchedAt
  - **Progress:** status, currentPage, totalPages, lastReadDate
  - **Flags:** isFavorite, isOnReadingList
  - **Reader prefs (per-book):** preferredTransition, readingStyle, epubFontSize, epubTheme, zoomScale, thumbnailBarPosition
  - `coverImage` (base64 PNG, or as a separate `cover.png` entry in the zip — prefer the latter to keep the manifest small)

**Excluded on purpose:** filePath, bookmarkData, folder membership (folders are device-local; receiver offers placement), needsAttention, metadataCandidates, metadataBackup, dateAdded (receiver sets its own; original recorded in manifest as `sentDateAdded` for reference).

## Send flow (Mac, v1)

1. Context menu on a comic (and bulk selection bar): **"Send to Device…"**
2. Export: stream-zip book file + manifest to a temp `.scobook`, with a determinate progress bar (large cbz files take seconds).
3. Hand the file to `NSSharingServicePicker` (share sheet → AirDrop). System UI owns transfer progress.
4. Clean up temp file after the picker completes.

New code: `Services/Transfer/BookPackageExporter.swift`, `TransferManifest.swift` (Codable, versioned), menu wiring in `ComicCellModifiers` + `LibrarySelectionBar`.

## Receive flow (both platforms; iPad is the v1 target)

1. Register `.scobook` UTType (exported type, conforms to `com.pkware.zip-archive`) + document type in Info.plist so "Open in SuperComicOrganizer" appears after AirDrop / from Files.
2. On open: unpack to temp, validate `formatVersion` and `fileSHA256`.
3. **Dedup check:** existing comic with same UUID, else same fileSHA256/size. If found → sheet: "Update progress & metadata" (applies manifest fields to existing row, file untouched) or "Keep existing copy" (discard).
4. If new → confirmation sheet: cover + display title + **folder placement** (existing folders / New Folder… / just Library — reuse the folders feature picker).
5. Copy book file into the local library (iPad: app container Documents/library, honoring `AppSettings.folderStructure`; Mac: normal `LibraryFileService.moveToLibrary()` path). Progress bar during unpack/copy.
6. Insert `Comic` row with manifest fields verbatim. **Skip** filename parsing and ComicVine fetch — manifest is authoritative and `metadataFetchedAt` is preserved, so the existing re-fetch gate does the right thing.

New code: `BookPackageImporter.swift`, `TransferReceiveSheet.swift`, `.onOpenURL` handling in `SCO_OSXCursorApp`, Info.plist UTType declarations.

## Explicitly out of scope (v1)

- iPad Send button (trivial to add later; receive path already shared)
- In-app device-to-device transfer (Multipeer) — future transport over the same format
- Ongoing/live sync of progress after transfer — a future "progress-only" manifest (same format, no book file) is the natural path if wanted
- Transferring folder structures

## Effort

Package format + Mac export + share sheet: ~1–2 days. UTType registration + receive/import flow + folder sheet: ~2–3 days. Dedup prompt: ~1 day. **~1 week total.**
