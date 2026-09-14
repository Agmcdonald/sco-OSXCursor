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

        // ── Atomic swap ──
        _ = try fm.replaceItemAt(url, withItemAt: tempURL)
        AppLog.files.info("[CBZEmbed] ✅ Wrote ComicInfo.xml into \(comic.fileName)")
        return .written
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
