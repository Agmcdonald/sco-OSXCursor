//
//  LibraryViewModel+ConvertPDF.swift
//  SCO-OSXCursor
//
//  Post-hoc PDF → CBZ conversion for books already in the library.
//
//  Per book: write the CBZ beside the PDF (verified, conflict-safe) →
//  update the SAME record in place (id kept; the import path's UUIDs are
//  path-derived, so re-importing would fork identity) → log activity →
//  file the original under "<Library>/Converted PDFs/…". The PDF is
//  never deleted; if the DB update fails the CBZ is removed so the
//  library never points at a file that isn't there.
//

import Foundation

extension LibraryViewModel {

    struct ConvertedBook {
        let comic: Comic
        /// Where the original PDF was filed, when archiving succeeded.
        let archivedOriginalURL: URL?
        /// Non-fatal problem to surface (original couldn't be archived, …).
        let warning: String?
    }

    /// Where a book's converted CBZ should be written.
    ///
    /// Beside the PDF when it already lives in the home library (or no
    /// library is set). A book OUTSIDE the library converts straight into
    /// its `destinationURL` folder under the root: a file-scoped bookmark
    /// grants no write access to the PDF's containing directory, so
    /// writing a sibling there is impossible under the sandbox — and the
    /// library is where the book belongs anyway.
    nonisolated static func conversionDestination(
        source: URL, comic: Comic, libraryRoot: URL?,
        folderStructure: AppSettings.FolderStructure = AppSettings.load().folderStructure
    ) -> (directory: URL, baseName: String) {
        let sourceDirectory = source.deletingLastPathComponent()
        if let root = libraryRoot,
            ConvertedPDFArchiver.relativePath(of: sourceDirectory, under: root) == nil
        {
            let destination = LibraryFileService.shared.destinationURL(
                for: comic, in: root, folderStructure: folderStructure)
            return (
                destination.deletingLastPathComponent(),
                destination.deletingPathExtension().lastPathComponent
            )
        }
        return (sourceDirectory, source.deletingPathExtension().lastPathComponent)
    }

    func convertPDFToCBZ(
        _ comic: Comic,
        pageProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> ConvertedBook {
        guard comic.fileType == .pdf, !Comic.isBundled(comic), !comic.needsAttention else {
            throw PDFConversionError.cannotOpen(comic.fileName)
        }

        // ── Resolve the file (bookmark first) — same as embedComicInfo ──
        var fileURL = comic.filePath
        var didStartAccess = false
        if let bookmarkData = comic.bookmarkData {
            var isStale = false
            #if os(macOS)
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData, options: .withSecurityScope,
                    relativeTo: nil, bookmarkDataIsStale: &isStale)
                {
                    fileURL = resolved
                    didStartAccess = resolved.startAccessingSecurityScopedResource()
                }
            #else
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData, options: [],
                    relativeTo: nil, bookmarkDataIsStale: &isStale)
                {
                    fileURL = resolved
                    didStartAccess = resolved.startAccessingSecurityScopedResource()
                }
            #endif
        }
        defer { if didStartAccess { fileURL.stopAccessingSecurityScopedResource() } }

        // Conversions rewrite files under the home library root — hold
        // its scope for the whole operation (same rule as embedComicInfo).
        let scopedLibraryRoot = beginHomeLibraryScope()
        defer { scopedLibraryRoot?.stopAccessingSecurityScopedResource() }

        let sourceURL = fileURL
        let plan = Self.conversionDestination(
            source: sourceURL, comic: comic, libraryRoot: scopedLibraryRoot)
        let directory = plan.directory
        let baseName = plan.baseName
        let metadata = comic
        let progress = pageProgress ?? { _, _ in }

        let result: PDFToCBZConverter.ConversionResult
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try PDFToCBZConverter.convert(
                    sources: [sourceURL], metadata: metadata,
                    destinationDirectory: directory, baseFileName: baseName,
                    onPageProgress: progress)
            }.value
        } catch {
            // A sandbox write-permission failure is opaque on its own —
            // translate it into something actionable. Any other failure
            // (encrypted/zero-page PDFs, etc.) keeps its real message even
            // when the source happens to live on a cloud drive.
            if Self.isWritePermissionError(error) {
                // Out-of-library books now convert INTO the library, so a
                // write-permission failure here means either no home
                // library is set (nowhere writable for the CBZ — a
                // file-scoped bookmark grants no directory writes)…
                if scopedLibraryRoot == nil,
                    SettingsViewModel().resolveHomeLibraryURL() == nil
                {
                    throw PDFConversionError.notWritable(sourceURL.lastPathComponent)
                }
                // …or a cloud-synced location the sandbox refuses —
                // translate it, same as LibraryFileService.moveToLibrary.
                if LibraryFileService.isCloudDriveURL(sourceURL)
                    || scopedLibraryRoot.map(LibraryFileService.isCloudDriveURL) == true
                {
                    throw LibraryFileError.cloudDriveSource(sourceURL)
                }
            }
            throw error
        }

        // ── Update the record in place (same id) ──
        var updated = comic
        updated.filePath = result.cbzURL
        updated.fileName = result.cbzURL.lastPathComponent
        updated.fileType = .cbz
        updated.totalPages = result.pageCount
        updated.pdfReadsAsBook = false
        updated.dateModified = Date()
        if let size = try? FileManager.default
            .attributesOfItem(atPath: result.cbzURL.path)[.size] as? Int64
        {
            updated.fileSize = size
        }
        #if os(macOS)
            updated.bookmarkData = try? result.cbzURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
            updated.bookmarkData = try? result.cbzURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif

        do {
            try await persistComic(updated)
        } catch {
            // Never leave the record pointing at nothing: drop the CBZ,
            // the record still points at the untouched PDF.
            try? FileManager.default.removeItem(at: result.cbzURL)
            throw error
        }
        if let index = comics.firstIndex(where: { $0.id == updated.id }) {
            comics[index] = updated
        }
        await logActivity(.converted, comic: updated, old: comic.fileName, new: updated.fileName)

        // ── File the original PDF (non-fatal on failure) ──
        var archivedURL: URL?
        var warning: String?
        if let libraryRoot = scopedLibraryRoot ?? SettingsViewModel().resolveHomeLibraryURL() {
            do {
                let subpath = ConvertedPDFArchiver.mirrorSubpath(
                    for: comic, libraryRoot: libraryRoot)
                archivedURL = try ConvertedPDFArchiver.archiveOriginal(
                    sourceURL, libraryRoot: libraryRoot, mirrorSubpath: subpath)
            } catch {
                warning =
                    "\(comic.displayTitle): converted, but the original PDF couldn't be moved to Converted PDFs (\(error.localizedDescription)). It stays where it was."
            }
        } else {
            warning =
                "\(comic.displayTitle): converted. No home library is set, so the original PDF stays where it was."
        }

        return ConvertedBook(comic: updated, archivedOriginalURL: archivedURL, warning: warning)
    }

    /// Whether `error` is a sandbox write-permission failure: a Cocoa
    /// "no write permission" error, or the POSIX EACCES it sometimes
    /// surfaces as instead.
    fileprivate static func isWritePermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileWriteNoPermission.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 13 /* EACCES */ {
            return true
        }
        return false
    }
}
