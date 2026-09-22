//
//  LibraryViewModel+MergeCBZ.swift
//  SCO-OSXCursor
//
//  Orchestration for "Merge into CBZ…": resolve the selected books' files,
//  run CBZMerger over them, bring the result into the library, and — only
//  if the user asked — send the parts to the Trash.
//
//  Lives in its own file rather than in LibraryViewModel: that file is
//  already 2,200 lines and this flow is self-contained.
//

import Foundation
import os

extension LibraryViewModel {

    // MARK: - Spec & Report

    /// What the merge sheet collected from the user.
    struct CBZMergeSpec {
        /// Book title for the merged file (also the basis of its file name).
        var title: String = ""
        var series: String = ""
        var publisher: String = ""
        var year: Int?
        /// Volume number of the collected edition, when the user knows it.
        var volume: Int?
        /// Where to write the merged file. Nil means "beside the first part".
        /// A folder the user picked through the file importer arrives here
        /// with its security scope NOT yet started — this code starts it.
        var destinationFolder: URL?
        /// Move the original files and their catalog rows to SCO's Trash
        /// once the merge has verified. Off by default; restorable either way.
        var trashOriginals: Bool = false

        /// File-name stem: the title, falling back to the series.
        var fileNameBase: String {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty { return trimmedTitle }
            let trimmedSeries = series.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedSeries.isEmpty ? "Merged Comic" : trimmedSeries
        }
    }

    /// Outcome of a completed merge.
    struct CBZMergeReport {
        let url: URL
        let pageCount: Int
        let sourceCount: Int
        /// The merged book's library ID, when the import took.
        let importedID: UUID?
        /// How many parts went to the Trash afterwards.
        let trashedOriginals: Int

        var message: String {
            var text =
                "Merged \(sourceCount) files into “\(url.lastPathComponent)” (\(pageCount) pages)."
            if trashedOriginals > 0 {
                text +=
                    " \(trashedOriginals) original\(trashedOriginals == 1 ? "" : "s") moved to the Trash."
            }
            if importedID == nil {
                text += " The file was written but could not be added to the library — add it manually."
            }
            return text
        }
    }

    /// Books from a selection that a CBZ merge can actually take: CBZ files
    /// whose file is present. Order is preserved, so callers can hand the
    /// user's chosen order straight through.
    static func mergeableCBZs(from comics: [Comic]) -> [Comic] {
        comics.filter { $0.fileType == .cbz && !$0.needsAttention }
    }

    // MARK: - Merge

    /// Merges `ordered` into one CBZ, adds it to the library, and optionally
    /// trashes the parts.
    ///
    /// - Parameters:
    ///   - ordered: The parts in reading order. Two or more CBZ books.
    ///   - spec: Output name, metadata, destination, and the trash choice.
    ///   - progress: 0…1 for the archive-building stage. Called from the
    ///     merge's background task, so hop to the main actor in the closure
    ///     if it touches view state (see MergeCBZSheet).
    func mergeIntoCBZ(
        _ ordered: [Comic],
        spec: CBZMergeSpec,
        progress: ((Double) -> Void)? = nil
    ) async -> Result<CBZMergeReport, Error> {
        let parts = Self.mergeableCBZs(from: ordered)
        guard parts.count >= 2 else {
            return .failure(CBZMergeError.notEnoughSources)
        }

        // The merged file is written into the library (or beside a part that
        // usually lives there), so hold the home-library root's scope for
        // the whole operation — same rule as embedComicInfo and
        // LibraryFileService.moveToLibrary.
        let scopedLibraryRoot = beginHomeLibraryScope()
        defer { scopedLibraryRoot?.stopAccessingSecurityScopedResource() }

        // ── Resolve every part's file, keeping access open for the merge.
        var sources: [CBZMergeSource] = []
        var scopedSources: [URL] = []
        defer { scopedSources.forEach { $0.stopAccessingSecurityScopedResource() } }

        for comic in parts {
            let (url, didStart) = Self.accessibleURL(for: comic)
            if didStart { scopedSources.append(url) }
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failure(CBZMergeError.sourceMissing(comic.fileName))
            }
            sources.append(CBZMergeSource(comic: comic, url: url))
        }

        // ── Destination folder: the user's pick, else the home library
        // root, else beside the first part. The library root is preferred
        // over the part's own folder because a book imported in place from
        // outside the library carries a FILE-scoped sandbox grant — the file
        // is readable, but creating a sibling next to it is not allowed
        // (the same limit CBZMetadataEmbedder documents for renames).
        var scopedDestination: URL?
        defer { scopedDestination?.stopAccessingSecurityScopedResource() }

        let folder: URL
        if let picked = spec.destinationFolder {
            if picked.startAccessingSecurityScopedResource() { scopedDestination = picked }
            folder = picked
        } else if let root = scopedLibraryRoot {
            folder = root
        } else {
            folder = sources[0].url.deletingLastPathComponent()
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            AppLog.files.error(
                "[Merge] ⚠️ Destination folder unusable (\(folder.path)): \(error.localizedDescription)"
            )
        }

        let destination = CBZMerger.availableURL(in: folder, baseName: spec.fileNameBase)

        // ── Metadata for the merged archive's ComicInfo.xml. Creator
        // credits ride along from the first part (the sheet prefills them
        // from there, so what the user saw is what gets written).
        let first = sources[0].comic
        let template = Comic(
            filePath: destination,
            fileName: destination.lastPathComponent,
            title: spec.title.isEmpty ? nil : spec.title,
            publisher: spec.publisher.isEmpty ? nil : spec.publisher,
            series: spec.series.isEmpty ? nil : spec.series,
            issueNumber: nil,
            volume: spec.volume,
            year: spec.year,
            bookFormat: .volume,
            writer: first.writer,
            artist: first.artist,
            coverArtist: first.coverArtist,
            colorist: first.colorist,
            inker: first.inker,
            editor: first.editor,
            fileType: .cbz
        )

        // ── Build it. Detached so a multi-gigabyte merge never blocks the
        // main actor; progress hops back for the bar.
        let outcome: CBZMergeOutcome
        let resolved = sources
        do {
            outcome = try await Task.detached(priority: .userInitiated) {
                try CBZMerger().merge(
                    sources: resolved, into: destination, metadata: template,
                    progress: progress)
            }.value
        } catch {
            AppLog.files.error("[Merge] ❌ Merge failed: \(error.localizedDescription)")
            return .failure(Self.mergeFailureHint(error, wroteInto: folder))
        }

        // ── Bring it into the library. Import does the real work (cover,
        // page count, bookmark, auto-sort), then the user's chosen fields
        // are stamped over whatever the file name happened to parse to.
        let importedIDs = await importComics(from: [outcome.url])
        let importedID = importedIDs.first

        if let importedID, var record = comics.first(where: { $0.id == importedID }) {
            record.title = spec.title.isEmpty ? record.title : spec.title
            record.series = spec.series.isEmpty ? record.series : spec.series
            record.publisher = spec.publisher.isEmpty ? record.publisher : spec.publisher
            record.year = spec.year ?? record.year
            record.volume = spec.volume ?? record.volume
            record.issueNumber = nil
            record.bookFormat = .volume
            record.writer = record.writer ?? first.writer
            record.artist = record.artist ?? first.artist
            updateComic(record)
        }

        // ── Only now, with a verified file that the library knows about,
        // offer to clear the parts away. They go to SCO's Trash (files and
        // rows), so a bad merge is undoable from Maintenance.
        var trashed = 0
        if spec.trashOriginals {
            await deleteComicsFromDevice(parts)
            trashed = parts.count
        }

        let report = CBZMergeReport(
            url: outcome.url,
            pageCount: outcome.pageCount,
            sourceCount: outcome.sourceCount,
            importedID: importedID,
            trashedOriginals: trashed
        )
        await logActivity(
            .imported,
            comic: importedID.flatMap { id in comics.first(where: { $0.id == id }) },
            old: parts.map(\.fileName).joined(separator: ", "),
            new: "Merged \(parts.count) CBZ files → \(outcome.url.lastPathComponent)")
        AppLog.files.info("[Merge] ✅ \(report.message)")
        return .success(report)
    }

    // MARK: - Helpers

    /// Resolves a book's file through its security-scoped bookmark when it
    /// has one, and reports whether access was started (the caller must
    /// stop it). Falls back to the stored path.
    ///
    /// Mirrors the resolution embedComicInfo does inline; kept here so the
    /// merge doesn't have to reach into that loop.
    static func accessibleURL(for comic: Comic) -> (url: URL, didStartAccess: Bool) {
        guard let bookmarkData = comic.bookmarkData else { return (comic.filePath, false) }
        var isStale = false
        #if os(macOS)
            let options: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
            let options: URL.BookmarkResolutionOptions = []
        #endif
        guard
            let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else { return (comic.filePath, false) }
        return (resolved, resolved.startAccessingSecurityScopedResource())
    }

    /// Turns a sandbox write refusal into advice the user can act on. Every
    /// other failure is passed through untouched.
    private static func mergeFailureHint(_ error: Error, wroteInto folder: URL) -> Error {
        let nsError = error as NSError
        let isWriteDenied =
            nsError.domain == NSCocoaErrorDomain
            && (nsError.code == CocoaError.fileWriteNoPermission.rawValue
                || nsError.code == CocoaError.fileWriteFileExists.rawValue)
        guard isWriteDenied else { return error }
        return CBZMergeWriteDeniedError(folderName: folder.lastPathComponent)
    }
}

/// Raised when the merged archive can't be written where it was aimed —
/// almost always a folder SCO has no write grant for.
struct CBZMergeWriteDeniedError: LocalizedError {
    let folderName: String

    var errorDescription: String? {
        "SCO can't write into “\(folderName)”. Choose another folder for the merged file, or set a Home Library in Settings."
    }
}
