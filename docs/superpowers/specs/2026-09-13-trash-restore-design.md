# Trash & Restore — Design

**Date:** 2026-09-13
**Status:** Approved for planning

Give every user-intent delete in SCO a recovery path. Both kinds of delete
become trash operations: "Remove from App" (catalog row deleted, file kept)
and "Delete Files from Device" (file deleted too). One Trash surface in the
Maintenance tab lists everything, restores anything, and auto-purges on a
user-set retention clock. This is step 1 of the CLU coverage build order —
the prerequisite for any future feature that writes to user files.

## Why

Today `LibraryViewModel.deleteComicsFromDevice` → `deleteFileOnDisk` calls
`FileManager.removeItem` — permanent, reached from folder deletion's
"Delete Files from Device" and Dashboard Health's per-book delete.
`deleteComicsFromApp` permanently discards the catalog row (metadata,
progress, tags). The in-app manual currently says "cannot be undone" in
three places. After this feature, nothing a user deletes is gone until
retention (or an explicit purge) says so.

## Decisions (user-approved)

1. **Scope:** both delete kinds are recoverable, in one unified Trash.
2. **Mechanics:** app-managed trash folder + database manifest (CLU model),
   identical on macOS and iOS. NOT the system Trash.
3. **Retention:** picker with 7 / 30 / 90 days / Never, default 30; sweep
   on app launch; "Empty Trash" and per-entry "Delete Now" for manual purge.
4. **UI:** a Trash section in the Maintenance tab. No Library scope entry.

## Architecture

New service file `SCO-OSXCursor/Services/TrashService.swift` (one file per
service, house style) plus a `TrashEntry` model, a DB table, view-model
rewiring, and a Maintenance section.

### Storage

- **Trash directory:** `<Application Support>/SuperComicOrganizer/Trash/`
  (sibling of `comics.db`; created lazily). Trashed files are stored as
  `<entry-uuid>.<original-extension>`.
- **Manifest table `trash_entries`** (migration `v33_trash_entries`,
  registered after `v32_metron_metadata`):

| Column | Type | Meaning |
|---|---|---|
| `id` | TEXT PK | entry UUID |
| `comic_snapshot` | TEXT | full JSON snapshot (see below) |
| `original_path` | TEXT | file's path at deletion time |
| `bookmark_data` | BLOB nullable | original security-scoped bookmark |
| `trashed_file_name` | TEXT nullable | name inside Trash/; NULL = file was never taken (remove-from-app) |
| `file_size` | INTEGER | bytes (0 when file not taken) |
| `deleted_at` | DATETIME | when trashed |
| `kind` | TEXT | `"file"` or `"catalog"` |
| `display_title` | TEXT | denormalized for the list row |
| `cover_thumb` | BLOB nullable | small JPEG for the list row |

### Snapshot

`TrashSnapshot` (Codable) captures the complete `Comic` (every stored
property, including reading state, tags, storyArcs, characters, teams,
metadata IDs and backups, cover image data) **plus** `folderIDs: [UUID]`
(memberships, captured before the cascade delete removes them). Encoding
uses JSONEncoder with data-friendly strategies; the snapshot is the
restore source of truth. `cover_thumb` is a downscaled (~120pt) JPEG copy
so the Trash list never decodes the full snapshot for display.

### TrashService API (all `async throws` where they touch disk/DB)

- `trash(_ comics: [Comic], deleteFiles: Bool) async -> TrashResult` —
  per comic: capture snapshot + folder IDs; if `deleteFiles` and not a
  bundled sample, resolve the security-scoped bookmark (same pattern as
  today's `deleteFileOnDisk`) and `moveItem` the file into Trash/
  (`copyItem`+`removeItem` fallback for cross-volume moves); insert the
  manifest row; then delete the comic row (existing DB path). Failures on
  one book don't abort the batch; the result carries per-book outcomes.
- `restore(_ entry: TrashEntry) async throws -> RestoreOutcome` — decode
  snapshot; if `trashed_file_name` != nil, move the file back to
  `original_path` (creating intermediate directories). If the destination
  is occupied, append ` (restored)` before the extension; if the volume/
  parent is unreachable, file into the home library via the existing
  `LibraryFileService` path and record the new location. Re-insert the
  Comic row with its ORIGINAL UUID and (when the file moved) a refreshed
  path + newly minted bookmark. Re-create folder-membership rows for
  folder IDs that still exist. Delete the manifest row. Outcome reports
  where the file landed (`originalPath` / `renamed` / `homeLibrary` /
  `catalogOnly`).
- `purge(_ entry: TrashEntry) async` — remove trashed file (if any) +
  manifest row. Permanent.
- `purgeAll() async`, `sweepExpired(retentionDays: Int?) async -> Int` —
  callers map the stored `trashRetentionDays` value 0 (Never) to `nil`;
  sweep runs on app launch (fire-and-forget task from the app init or
  first Library load); `nil` retention = Never = no-op.
- `entries() async -> [TrashEntry]`, `totalSize` for the header.

### Retention setting

UserDefaults key `trashRetentionDays` (Int; 7/30/90; 0 = Never), default
30, surfaced as a segmented picker in the Trash section. Sweep reads it.

## View-model rewiring

`deleteComicsFromApp` and `deleteComicsFromDevice` keep their names and
signatures but route through `TrashService.trash(_:deleteFiles:)`. A
`bypassTrash: Bool = false` parameter (or a separate internal
`hardDeleteComicsFromApp`) preserves true deletion for internal callers:

- retired-sample cleanup (`LibraryViewModel` ~line 871) — bypasses.
- Organize/transfer/temp-file `removeItem` calls — untouched (not user
  deletes; they never went through these methods anyway).
- Bundled samples: file never taken (existing skip), but remove-from-app
  still snapshots so the catalog entry is restorable.

`deleteFileOnDisk` is replaced by the service's move-to-trash (the
bookmark-resolution logic moves with it).

## UI — Maintenance tab "Trash" section

Follows the existing Maintenance section pattern (Database / Storage):

- Header: "Trash" + count and total size (e.g. "6 items · 312 MB").
- Rows: cover thumb, display title, kind label ("File in Trash" /
  "Removed from library — file kept on disk"), deleted date, days
  remaining under current retention ("Purges in 12 days" / "Kept until
  emptied" for Never). Per-row buttons: **Restore**, **Delete Now**
  (confirmation).
- Footer: **Empty Trash** (destructive confirmation naming count + size),
  retention segmented picker (7 / 30 / 90 days / Never) with one caption
  line, and a note that restore returns books to their library, folders,
  and reading progress.
- Empty state: "Trash is empty" + caption explaining what lands here.
- Restore/purge outcomes surface in the section via the same transient
  status-string pattern the other Maintenance sections use.

## Copy changes

- `UserManualView` (~lines 222, 308, 757): "cannot be undone" copy →
  deletes go to Trash in Maintenance, kept per the retention setting
  (default 30 days); Empty Trash / Delete Now are the permanent actions.
- Folder-delete dialog and Dashboard Health delete confirmation copy:
  "moves to Trash (kept 30 days)" phrasing, reading the live retention
  value where convenient, else "kept in Trash".
- Library selection delete confirmation (if any copy says permanent).

## Error handling

- Move-to-trash failure (file locked/missing): log, still remove from app
  with `kind = "catalog"` and `trashed_file_name = NULL` so the catalog
  entry remains restorable; per-book outcome reports the file problem.
- Restore failure (trash file missing — e.g. user dug into the container):
  keep the manifest row, surface an error status; offer Delete Now.
- Restoring a book whose file was meanwhile re-imported as a new catalog
  entry: restore proceeds anyway (original UUID never collides — its row
  was deleted); the existing duplicate-detection surfaces the twin.
- Sweep and purge failures log via `AppLog` (new `AppLog.trash` category
  or reuse `library`) and never crash the launch path.

## Testing

New `SCO-OSXCursorTests/TrashServiceTests.swift` (Swift Testing), using a
temp-directory trash root and an in-memory/temp GRDB database (follow
whatever pattern existing DB-adjacent tests use; if none exists, the
service takes its trash-directory URL and database as init parameters so
tests can inject temps — that injection seam is part of the design):

- snapshot round-trip: every Comic field + folderIDs survive encode/decode.
- trash(deleteFiles: true) moves the file and writes a correct manifest row.
- trash(deleteFiles: false) leaves the file and writes `kind = "catalog"`.
- restore returns file to original path; occupied path gets ` (restored)`
  suffix; missing parent falls back (assert outcome enum, not real
  home-library filing).
- retention math: sweepExpired purges only entries older than N days;
  0/Never purges nothing.
- purge removes file + row; purgeAll empties both.

## Out of scope

- Trash for internal/organize file operations (not user deletes).
- iCloud/cross-device trash sync.
- System Trash integration ("Put Back" in Finder).
- Size-capped trash (retention is time-based only).
- Undo toast in the Library (the status pill copy points at Maintenance).

## Addendum (2026-09-13, user-approved): escalate + multi-select

- **Escalate:** catalog-kind entries gain "Delete File from Device": resolve
  the entry's stored bookmark, take the file into the Trash directory under
  the entry's ID (same TrashFileStore.takeFile), update the entry in place
  (kind = file, trashedFileName, fileSize) keeping the ORIGINAL deletedAt so
  the purge clock doesn't reset. Missing/moved file → entry unchanged,
  status reports it. File-kind entries never show the action.
- **Multi-select in the Trash section:** per-row checkboxes + Select All /
  Clear; when the selection is non-empty the footer offers Restore Selected,
  Delete Files from Device (catalog-kind members only, count in the
  confirmation), and Delete Now Selected (destructive confirmation).
  Single-row buttons remain for the empty-selection state.
- Escalation runs under the home-library security scope with per-entry
  failure isolation, and escalated entries stay fully restorable.
