//
//  CBZMerger.swift
//  SCO-OSXCursor
//
//  Combines several CBZ archives into one larger CBZ ("Merge into CBZ…") —
//  the companion to merging a stack of PDFs: same idea, sources that are
//  already ZIP-based comic archives.
//
//  Page order is the contract. Each source is read in the same natural
//  order the reader uses (CBZReader.sortedImageEntries), and pages are
//  re-named to a single continuous sequence so the merged book reads
//  front-to-back in SCO and in every other reader that sorts entries by
//  path. Original page names are deliberately NOT kept: two parts that
//  both call their first page "001.jpg" would interleave.
//
//  The naming, the compression choices, and the assemble-verify-move
//  contract are deliberately the same as PDFToCBZConverter's: P00001.jpg,
//  P00002.png, … A CBZ this app produced should look the same inside
//  whether conversion or merging made it.
//
//  Safety contract: nothing is written over. The merged archive is built in
//  a temp folder on the destination's volume, verified there, and only then
//  moved into place — and the move refuses a destination that already
//  exists. Source files are opened read-only and never modified; removing
//  them afterwards is the caller's decision (LibraryViewModel routes it
//  through the Trash), never this type's.
//
//  Pages are stored uncompressed (.none). JPEG/PNG/WebP payloads are
//  already compressed, so deflating them again costs minutes on a big
//  merge and saves close to nothing. ComicInfo.xml is deflated — it's text.
//
//  The caller is responsible for security-scoped access to every source URL
//  and to the destination folder, mirroring how CBZReader and
//  CBZMetadataEmbedder are driven.
//

import Foundation
import ZIPFoundation
import os

// MARK: - Inputs & Outputs

/// One part of a merge, in final reading order.
///
/// Not `Sendable`: `Comic` isn't, and the merge is handed to a single
/// detached task rather than shared across several.
struct CBZMergeSource {
    /// The library record — used for labels, logging, and error messages.
    let comic: Comic
    /// The resolved, access-started file URL to read pages from.
    let url: URL

    init(comic: Comic, url: URL) {
        self.comic = comic
        self.url = url
    }
}

struct CBZMergeOutcome: Sendable {
    /// Where the merged archive landed.
    let url: URL
    /// Pages in the merged file (the sum of every part's pages).
    let pageCount: Int
    /// How many source archives went in.
    let sourceCount: Int
}

enum CBZMergeError: LocalizedError {
    case notEnoughSources
    case sourceMissing(String)
    case sourceUnreadable(name: String, reason: String)
    case sourceHasNoPages(String)
    case destinationExists(String)
    case verificationFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notEnoughSources:
            return "Pick at least two CBZ files to merge."
        case .sourceMissing(let name):
            return "“\(name)” could not be found on disk."
        case .sourceUnreadable(let name, let reason):
            return "“\(name)” could not be read: \(reason)"
        case .sourceHasNoPages(let name):
            return "“\(name)” contains no page images."
        case .destinationExists(let name):
            return "“\(name)” already exists. Choose a different name."
        case .verificationFailed:
            return
                "The merged archive failed verification and was discarded. Your original files were not changed."
        case .cancelled:
            return "The merge was cancelled."
        }
    }
}

// MARK: - Merger

final class CBZMerger {

    /// Builds one CBZ from `sources`, in the order given.
    ///
    /// - Parameters:
    ///   - sources: Two or more CBZ parts, already in reading order.
    ///   - destination: The `.cbz` file to create. Must not exist.
    ///   - metadata: Book record whose fields are written into the merged
    ///     archive as a fresh ComicInfo.xml (its `totalPages` is ignored —
    ///     the real merged page count is used). Pass nil to write no
    ///     ComicInfo.xml at all.
    ///   - progress: Called with 0…1 as pages are written, on whichever
    ///     thread the merge runs on — hop to the main actor yourself
    ///     (BookPackageExporter's progress works the same way).
    /// - Returns: Where the file landed and what went into it.
    @discardableResult
    func merge(
        sources: [CBZMergeSource],
        into destination: URL,
        metadata: Comic?,
        progress: ((Double) -> Void)? = nil
    ) throws -> CBZMergeOutcome {
        guard sources.count >= 2 else { throw CBZMergeError.notEnoughSources }

        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else {
            throw CBZMergeError.destinationExists(destination.lastPathComponent)
        }
        for source in sources where !fm.fileExists(atPath: source.url.path) {
            throw CBZMergeError.sourceMissing(source.comic.fileName)
        }

        // ── Pass 1: list every part's pages (central directory only, so
        // this is cheap) to get a total for the progress bar and to fail
        // fast on an unreadable or empty part before writing anything.
        var plan: [(source: CBZMergeSource, entries: [Entry])] = []
        for source in sources {
            let entries: [Entry]
            do {
                let archive = try Archive(url: source.url, accessMode: .read)
                entries = try CBZReader.sortedImageEntries(from: archive)
            } catch {
                throw CBZMergeError.sourceUnreadable(
                    name: source.comic.fileName, reason: error.localizedDescription)
            }
            guard !entries.isEmpty else {
                throw CBZMergeError.sourceHasNoPages(source.comic.fileName)
            }
            plan.append((source, entries))
        }

        let totalPages = plan.reduce(0) { $0 + $1.entries.count }

        // ── Build in a temp folder on the destination's volume, so the
        // final step is a same-volume move rather than a copy.
        let tempDir = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destination, create: true)
        defer { try? fm.removeItem(at: tempDir) }
        let tempURL = tempDir.appendingPathComponent(destination.lastPathComponent)

        let output = try Archive(url: tempURL, accessMode: .create)

        /// What we wrote, to verify against once the archive is closed.
        var written: [(path: String, size: Int)] = []
        var firstPageBytes: Data?
        var lastPageBytes: Data?
        var pageNumber = 0

        for (source, entries) in plan {
            // Re-open per part; the read handle is only needed while its
            // pages are being copied.
            let input: Archive
            do {
                input = try Archive(url: source.url, accessMode: .read)
            } catch {
                throw CBZMergeError.sourceUnreadable(
                    name: source.comic.fileName, reason: error.localizedDescription)
            }

            for entry in entries {
                if Task.isCancelled { throw CBZMergeError.cancelled }

                // Re-resolve the entry in this handle by path: the plan's
                // Entry values came from a different Archive instance.
                guard let live = input[entry.path] else {
                    throw CBZMergeError.sourceUnreadable(
                        name: source.comic.fileName,
                        reason: "page \(entry.path) disappeared while merging")
                }

                var data = Data()
                do {
                    _ = try input.extract(live) { data.append($0) }
                } catch {
                    throw CBZMergeError.sourceUnreadable(
                        name: source.comic.fileName, reason: error.localizedDescription)
                }

                pageNumber += 1
                let path = Self.pageName(number: pageNumber, like: entry.path)
                try output.addEntry(
                    with: path, type: .file,
                    uncompressedSize: Int64(data.count),
                    compressionMethod: .none
                ) { position, size in
                    let start = Int(position)
                    return data.subdata(in: start..<start + size)
                }
                written.append((path, data.count))

                if pageNumber == 1 { firstPageBytes = data }
                if pageNumber == totalPages { lastPageBytes = data }

                progress?(Double(pageNumber) / Double(totalPages))
            }
        }

        // ── ComicInfo.xml for the merged book.
        //
        // Written from scratch (no `mergingExisting:`) on purpose. Carrying
        // a part's existing XML through would carry its <Pages> block too —
        // per-page hashes and bookmarks describing a completely different
        // set of pages — and its PageCount, Number and Summary belong to
        // that one issue, not to the collection.
        if let metadata {
            var record = metadata
            record.totalPages = totalPages
            let xml = ComicInfoWriter.xmlData(for: record)
            try output.addEntry(
                with: CBZMetadataEmbedder.entryPath, type: .file,
                uncompressedSize: Int64(xml.count),
                compressionMethod: .deflate
            ) { position, size in
                let start = Int(position)
                return xml.subdata(in: start..<start + size)
            }
        }

        if Task.isCancelled { throw CBZMergeError.cancelled }

        // ── Verify the finished archive before it becomes a real file.
        //
        // Every page is checked for presence and uncompressed size (catches
        // a truncated or dropped entry anywhere in the sequence); the first
        // and last pages are additionally compared byte-for-byte. A full
        // byte comparison of every page would double the I/O of a merge
        // that can run to gigabytes, and size + order is what a bad write
        // gets wrong.
        let check = try Archive(url: tempURL, accessMode: .read)
        let verifiedPages = try CBZReader.sortedImageEntries(from: check)
        guard verifiedPages.count == totalPages,
            verifiedPages.map(\.path) == written.map({ $0.path })
        else { throw CBZMergeError.verificationFailed }

        for (index, expected) in written.enumerated() {
            // `Int(_:)` rather than a typed comparison: ZIPFoundation has
            // changed the width of this property across versions.
            guard Int(verifiedPages[index].uncompressedSize) == expected.size else {
                throw CBZMergeError.verificationFailed
            }
        }
        try Self.verifyBytes(firstPageBytes, at: written.first?.path, in: check)
        try Self.verifyBytes(lastPageBytes, at: written.last?.path, in: check)
        if metadata != nil, CBZMetadataEmbedder.comicInfoEntry(in: check) == nil {
            throw CBZMergeError.verificationFailed
        }

        // ── Move the verified archive into place. `moveItem` fails rather
        // than overwriting, which is the behaviour we want on the last
        // possible race with something else creating that name.
        do {
            try fm.moveItem(at: tempURL, to: destination)
        } catch {
            if fm.fileExists(atPath: destination.path) {
                throw CBZMergeError.destinationExists(destination.lastPathComponent)
            }
            throw error
        }

        AppLog.files.info(
            "[CBZMerge] ✅ Merged \(sources.count) files (\(totalPages) pages) into \(destination.lastPathComponent)"
        )
        return CBZMergeOutcome(
            url: destination, pageCount: totalPages, sourceCount: sources.count)
    }

    // MARK: - Helpers

    /// Flat page name in PDFToCBZConverter's `P%05d` sequence, keeping the
    /// source page's own file extension — readers pick the decoder from it,
    /// so a PNG page must not be renamed to .jpg (the converter's pages are
    /// always JPEG, hence its hard-coded extension).
    static func pageName(number: Int, like originalPath: String) -> String {
        let ext = (originalPath as NSString).pathExtension.lowercased()
        let stem = String(format: "P%05d", number)
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// Byte-compares one written page against what the closed archive reads
    /// back. No-op when either side is absent (a merge with no pages can't
    /// reach here — `sources.count >= 2` and the empty-part guard precede it).
    private static func verifyBytes(_ expected: Data?, at path: String?, in archive: Archive) throws
    {
        guard let expected, let path, let entry = archive[path] else { return }
        var roundTrip = Data()
        _ = try archive.extract(entry) { roundTrip.append($0) }
        guard roundTrip == expected else { throw CBZMergeError.verificationFailed }
    }

    /// A free `.cbz` URL inside `folder` for `baseName`. Collisions are
    /// resolved by LibraryFileService — the same "Name (2).cbz" shape every
    /// other file SCO writes gets, PDF conversions included.
    static func availableURL(in folder: URL, baseName: String) -> URL {
        let stem = sanitizedFileName(baseName)
        let candidate = folder.appendingPathComponent("\(stem).cbz")
        return LibraryFileService.shared.resolveConflict(at: candidate)
    }

    /// File-name stem with illegal characters stripped, falling back to a
    /// generic name when nothing usable is left. Delegates the stripping to
    /// LibraryFileService so a merged book's name is cleaned by the same
    /// rules as an organized or converted one.
    static func sanitizedFileName(_ raw: String) -> String {
        let cleaned = LibraryFileService.shared.sanitizeFolderName(raw)
        return cleaned.isEmpty ? "Merged Comic" : cleaned
    }
}
