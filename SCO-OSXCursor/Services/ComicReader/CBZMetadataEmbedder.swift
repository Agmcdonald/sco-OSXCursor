//
//  CBZMetadataEmbedder.swift
//  SCO-OSXCursor
//
//  Writes a book's library metadata back into its CBZ as ComicInfo.xml
//  ("Save Metadata to File").
//
//  Safety contract: the original file is NEVER modified in place. The
//  archive is copied to a temp location on the same volume, the copy gets
//  the new ComicInfo.xml, the copy is re-opened and verified (entry reads
//  back byte-identical, page count unchanged), and only then is the
//  original atomically replaced. Any failure before the final swap leaves
//  the user's file untouched.
//
//  The caller is responsible for security-scoped access to the file's URL
//  (LibraryViewModel resolves the bookmark and holds the home-library
//  scope), mirroring how CBZReader is driven.
//

import Foundation
import ZIPFoundation
import os

// MARK: - Result & Errors

enum CBZEmbedResult {
    /// ComicInfo.xml was written and the file replaced.
    case written
    /// The archive already contains exactly this metadata — file untouched.
    case unchanged
}

enum CBZEmbedError: LocalizedError {
    case fileNotFound
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The comic file could not be found on disk."
        case .verificationFailed:
            return "The updated archive failed verification. The original file was not modified."
        }
    }
}

// MARK: - Embedder

final class CBZMetadataEmbedder {

    static let entryPath = "ComicInfo.xml"

    /// Embeds `comic`'s metadata into the CBZ at `url` as ComicInfo.xml,
    /// merging over (and replacing) any existing entry.
    func embed(_ comic: Comic, into url: URL) throws -> CBZEmbedResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw CBZEmbedError.fileNotFound
        }

        // ── Read the current state: existing ComicInfo.xml + page count ──
        let readArchive = try Archive(url: url, accessMode: .read)
        var existingXML: Data?
        if let entry = Self.comicInfoEntry(in: readArchive) {
            var data = Data()
            _ = try readArchive.extract(entry) { data.append($0) }
            existingXML = data
        }
        let imageCountBefore = Self.imageEntryCount(in: readArchive)

        // ── Build the merged XML; skip the rewrite when nothing changed ──
        let xml = ComicInfoWriter.xmlData(for: comic, mergingExisting: existingXML)
        if let existingXML, existingXML == xml {
            AppLog.files.info("[CBZEmbed] ✓ Already current: \(comic.fileName)")
            return .unchanged
        }

        // ── Work on a temp copy, same volume for an atomic final rename ──
        let tempDir = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: url, create: true)
        defer { try? fm.removeItem(at: tempDir) }
        let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
        try fm.copyItem(at: url, to: tempURL)

        let archive = try Archive(url: tempURL, accessMode: .update)
        if let stale = Self.comicInfoEntry(in: archive) {
            try archive.remove(stale)
        }
        try archive.addEntry(
            with: Self.entryPath, type: .file,
            uncompressedSize: Int64(xml.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            return xml.subdata(in: start..<start + size)
        }

        // ── Verify the copy before it replaces the user's file ──
        let check = try Archive(url: tempURL, accessMode: .read)
        guard Self.imageEntryCount(in: check) == imageCountBefore,
            let newEntry = Self.comicInfoEntry(in: check)
        else {
            throw CBZEmbedError.verificationFailed
        }
        var roundTrip = Data()
        _ = try check.extract(newEntry) { roundTrip.append($0) }
        guard roundTrip == xml else {
            throw CBZEmbedError.verificationFailed
        }

        // ── Swap the verified copy into place ──
        // Preferred: atomic replace (a rename inside the parent folder).
        // Books imported in place from OUTSIDE the home library carry a
        // file-scoped sandbox grant only — the file itself is writable, but
        // renaming within its parent folder is not, and replaceItemAt fails
        // with "You don't have permission to save the file … in the
        // folder …". Fall back to rewriting the file's CONTENTS through its
        // own file handle: not atomic, so keep a pristine backup and put it
        // back if the write or the re-verification fails.
        do {
            _ = try fm.replaceItemAt(url, withItemAt: tempURL)
        } catch let swapError {
            AppLog.files.info(
                "[CBZEmbed] ↪️ Atomic swap refused (\(swapError.localizedDescription)) — trying in-place rewrite: \(comic.fileName)")
            let backupURL = tempDir.appendingPathComponent("backup-" + url.lastPathComponent)
            try fm.copyItem(at: url, to: backupURL)
            do {
                try Self.overwriteContents(of: url, with: tempURL)

                // Re-verify on the destination itself before trusting it.
                let final = try Archive(url: url, accessMode: .read)
                guard Self.imageEntryCount(in: final) == imageCountBefore,
                    let finalEntry = Self.comicInfoEntry(in: final)
                else { throw CBZEmbedError.verificationFailed }
                var finalXML = Data()
                _ = try final.extract(finalEntry) { finalXML.append($0) }
                guard finalXML == xml else { throw CBZEmbedError.verificationFailed }
            } catch {
                // Best effort: put the original bytes back before surfacing.
                try? Self.overwriteContents(of: url, with: backupURL)
                AppLog.files.error(
                    "[CBZEmbed] ❌ In-place rewrite failed (\(error.localizedDescription)) after swap refusal: \(comic.fileName)")
                throw error
            }
            AppLog.files.info(
                "[CBZEmbed] ✅ Wrote ComicInfo.xml in place (file-scoped access): \(comic.fileName)")
            return .written
        }
        AppLog.files.info("[CBZEmbed] ✅ Wrote ComicInfo.xml into \(comic.fileName)")
        return .written
    }

    // MARK: - In-place Fallback

    /// Chunked overwrite of `destination`'s contents with `source`'s bytes,
    /// through the destination's own file handle (works with a file-scoped
    /// sandbox grant). NOT atomic — callers must verify afterwards and
    /// restore from a backup on failure.
    private static func overwriteContents(of destination: URL, with source: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.truncate(atOffset: 0)
        while let chunk = try input.read(upToCount: 4_194_304), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
    }

    // MARK: - Helpers

    /// The archive's ComicInfo entry — exact root path first, then any
    /// entry named comicinfo.xml regardless of case or folder (files in
    /// the wild carry both).
    static func comicInfoEntry(in archive: Archive) -> Entry? {
        if let exact = archive[entryPath] { return exact }
        return archive.first { entry in
            (entry.path as NSString).lastPathComponent.lowercased() == "comicinfo.xml"
        }
    }

    /// Page-image count, used to prove the rewrite lost nothing.
    private static func imageEntryCount(in archive: Archive) -> Int {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
        return archive.filter { entry in
            let pathExtension = (entry.path as NSString).pathExtension.lowercased()
            return imageExtensions.contains(pathExtension) && !entry.path.hasPrefix("__MACOSX")
        }.count
    }
}
