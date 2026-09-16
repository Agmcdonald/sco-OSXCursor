# PDF → CBZ Conversion — Design

**Date:** 2026-09-16
**Status:** Approved

## Purpose

Let users convert PDF comics into CBZ files — automatically during Organize (optional switch), by merging several PDFs into one CBZ, or after the fact from the library. Converted originals are preserved in a mirrored `Converted PDFs/` folder inside the library root so the user can delete them at leisure. Quick Add is unchanged and continues to import PDFs natively.

## Decisions (settled during brainstorming)

1. **Quality strategy: smart hybrid.** Lossless extraction of embedded full-page JPEGs where possible; PDFKit re-render fallback otherwise. No user-facing DPI/quality knobs in v1.
2. **Merging: explicit selection** of 2+ staged PDFs in Organize. Auto-group-by-series is a future enhancement (see Later).
3. **Converted originals live inside the library root:** `<LibraryRoot>/Converted PDFs/<Publisher>/<Series>/…`.
4. **Same treatment for all conversion paths:** organize-time sources (e.g. from Downloads) also move to `Converted PDFs/` after success.
5. **Progress UI matches each context:** Organize reuses its processing bar with a live per-page label; post-hoc uses a Reorganize-style preview/run/done sheet.

## 1. Core service — `PDFToCBZConverter`

New service in `SCO-OSXCursor/Services/Conversion/PDFToCBZConverter.swift`.

**Input:** one or more PDF URLs in order, plus the metadata source (`Comic` or staged metadata). **Output:** one verified CBZ at a destination URL.

Per page, smart hybrid:

- **Lossless path:** inspect the page via Core Graphics (`CGPDFPage` dictionary → `Resources` → `XObject`). If the page consists of exactly one image XObject with `DCTDecode` (JPEG) encoding and no meaningful text content, copy the embedded JPEG bytes directly into the archive — no decode/re-encode.
- **Render fallback:** everything else (text pages, vector pages, multi-image pages, JPX/Flate-encoded images) goes through the existing `PDFReader.renderPageToImageData` path (PDFKit `thumbnail(of:for:.mediaBox)` at 2× scale, long side capped at 8000 px, JPEG q0.85 on white).

Archive writing (ZIPFoundation):

- Entries named `P00001.jpg`, `P00002.jpg`, … — continuous numbering across merged source PDFs.
- `compressionMethod: .none` for JPEG payloads (already compressed), streamed via the `addEntry` provider closure as pages are produced — never the whole book in memory (pattern: `BookPackageExporter`).
- `ComicInfo.xml` from `ComicInfoWriter.xmlData(for: comic, mergingExisting: nil)`, deflated.
- **Safety contract** (pattern: `CBZMetadataEmbedder`): build in a temp dir on the destination volume (`.itemReplacementDirectory`); verify by re-opening the finished archive (image entry count == expected page count, ComicInfo entry readable); then move into final place with `LibraryFileService.resolveConflict` semantics — never overwrite. The source PDF is not touched until the CBZ is verified.

**Progress callback:** `(bookIndex: Int, pageIndex: Int, pageCount: Int)` — drives both UIs.

**Naming:** `LibraryFileService.cleanedFileName(for:)` currently preserves the source extension; it gains an extension-override parameter (or the converter passes an already-adjusted name) so converted output is always `….cbz`.

## 2. Originals — one rule everywhere

After a verified conversion (and, for library books, after the DB update), source PDF(s) move to `<LibraryRoot>/Converted PDFs/<mirrored path>/`:

- **Library book:** mirrored path = the book's current path relative to the library root (preserves whatever structure it was filed under).
- **Organize-time source:** mirrored path = the same `LibraryFileService.destinationURL` relative path that placed the CBZ (Publisher/Series per the folder-structure setting).

Name conflicts get " (2)" suffixes (`resolveConflict`). Cross-volume moves reuse the copy-verify-delete logic from `LibraryFileService`. The `Converted PDFs` folder name is a reserved constant and is excluded wherever the app enumerates publisher folders under the root (Reorganize/Relocate previews, empty-folder cleanup stops at it).

## 3. Organize flow

- New setting under UserDefaults key `"convertPDFsOnOrganize"` (default **off**), stored the same way as `autoEmbedComicInfo` — its own key, not an `AppSettings` Codable field, which would invalidate previously saved settings on decode (see LibraryViewModel.swift:605). Toggle lives in the Organization section of `SettingsView`.
- When on, `OrganizeViewModel.confirmMatch` for a PDF becomes: rename in place → **convert to CBZ in the same folder** → import the **CBZ** into the library via `importStagedComic` (so the path-derived stable UUID is computed from the CBZ path from the start) → auto-sort via `moveToLibrary` as usual → move the original PDF to `Converted PDFs/`.
- Progress: the existing `isProcessing`/`processingProgress` bar gains a live status label, e.g. *"Converting Batman 012.pdf — page 14 of 32"*.
- **Failure fallback:** if conversion fails, the PDF imports natively exactly as today; the staged item completes with a visible warning and the batch continues.

### Merge into one CBZ

- User selects 2+ staged PDFs → "Merge into one CBZ" action.
- A sheet lists the files in current order (drag to reorder); metadata prefilled from the first file, editable.
- Confirm collapses the selection into one staged item flagged as a pending merge. On confirm-match it converts all sources in listed order into a single CBZ (continuous page numbering); all source PDFs move to `Converted PDFs/`.
- Merge is available regardless of the auto-convert toggle (merging implies conversion).

## 4. Quick Add

Unchanged. PDFs import natively.

## 5. Post-hoc conversion (library)

- **Entry points:** context menu "Convert to CBZ…" on any PDF book; batch action in the selection bottom bar for selections containing PDFs (non-PDFs skipped and reported).
- **UI:** Reorganize-style sheet (`enum Phase { preview, running, done }`):
  - *Preview:* each book with page count and current file size.
  - *Running:* per-book progress with per-page detail; one failure never halts the batch.
  - *Done:* converted/failed counts and a per-item error list.
- **Per successful book:** CBZ written beside the PDF → **`Comic.id` kept**, record updated in place: `filePath`, `fileName`, `fileType` (.pdf → .cbz), `fileSize`, `bookmarkData`, `dateModified`, `totalPages` (if page count changed), `pdfReadsAsBook` cleared → `ActivityEvent` logged with new kind `.converted` → original PDF moved to `Converted PDFs/`.
- The record update mirrors the tail of `LibraryFileService.moveToLibrary` (DB updated only after the file operation succeeds).
- Books stored outside the home library root convert INTO the library (the CBZ is written to the book's `destinationURL` folder under the root) — file-scoped bookmarks don't grant directory writes, so writing beside the PDF is impossible under the sandbox. With no home library set, in-place conversion is attempted and a permission failure reports guidance to set one.

## 6. Error handling

- Source PDFs are never deleted — only moved, and only after the CBZ is verified **and** (for library books) the DB record is updated.
- If the DB update fails after a CBZ is written, the CBZ is removed and the PDF stays; the library never points at a missing file.
- Encrypted, corrupt, or zero-page PDFs fail that one item with a readable message; the batch continues.
- Cloud-synced locations (iCloud/Dropbox/GDrive/OneDrive) reuse the existing `isCloudDriveURL` refusal with the same user messaging.
- All file operations run inside the existing security-scope patterns (`beginHomeLibraryScope`, per-file bookmarks).

## 7. Testing

Unit tests in `SCO-OSXCursorTests` (style of `ComicInfoWriterTests`), with fixture PDFs generated in-test via PDFKit (one image-only page, one text page, one multi-page mix):

- Lossless path chosen for single-JPEG pages; render fallback for text/vector pages.
- Page ordering and continuous numbering across merged source files.
- ComicInfo.xml present and matches the source metadata.
- Output naming/extension (`cleanedFileName` emits `.cbz` after conversion).
- Verify-before-move: a corrupted mid-write archive never replaces or moves the source.
- Mirrored `Converted PDFs/` path computation for both library books and organize-time sources, including conflict suffixes.

## Later (explicitly out of scope for v1)

- **Auto-group-by-series merge** in Organize (toggle that merges staged PDFs sharing a detected series into one CBZ per series).
- User-facing DPI/quality settings.
- CBR/EPUB → CBZ conversion.
