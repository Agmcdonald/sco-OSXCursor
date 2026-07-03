//
//  BookPackageExporter.swift
//  SCO-OSXCursor
//
//  Builds `.scobook` transfer packages (zip: manifest.json + book/<file> +
//  cover). The book file is streamed into the archive in chunks — never
//  loaded into memory — and its SHA-256 is computed in the same pass, so a
//  500 MB CBZ costs one read. The book entry is stored uncompressed
//  (CBZ/CBR/PDF/EPUB are already compressed; re-deflating is pure waste).
//
//  Synchronous & thread-safe: call from a background task and forward
//  `onProgress` (0.0–1.0) to the UI on the main actor.
//

import CryptoKit
import Foundation
import ZIPFoundation

// MARK: - Errors

enum BookPackageExportError: LocalizedError {
    case sourceFileMissing(String)
    case cannotCreatePackage(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .sourceFileMissing(let name):
            return
                "Can't package “\(name)” because its file is missing. Use Locate File… to re-link it first."
        case .cannotCreatePackage(let underlying):
            return "Couldn't create the transfer package: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Exporter

final class BookPackageExporter {

    private static let chunkSize = 1 << 20  // 1 MB

    /// Builds `<Display Title>.scobook` inside `directory` and returns its URL.
    ///
    /// - Parameters:
    ///   - comic: The book to package (file + transferable record fields).
    ///   - directory: Destination directory (must exist and be writable —
    ///     typically a per-export temp folder).
    ///   - onProgress: Called with 0.0–1.0 as the book file streams in.
    static func export(
        _ comic: Comic,
        to directory: URL,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) throws -> URL {
        let fm = FileManager.default

        // ── Resolve the source file (bookmark first, path fallback) ──
        var sourceURL = comic.resolvedURL
        var stale = false
        if let bookmarkData = comic.bookmarkData {
            #if os(macOS)
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    sourceURL = resolved
                }
            #else
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ) {
                    sourceURL = resolved
                }
            #endif
        }

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        guard fm.fileExists(atPath: sourceURL.path) else {
            throw BookPackageExportError.sourceFileMissing(comic.fileName)
        }

        let fileSize =
            (try? fm.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64)
            ?? comic.fileSize

        // ── Package URL: "<Display Title>.scobook", conflict-safe ──
        let service = LibraryFileService.shared
        let baseName =
            service.sanitizeFolderName(comic.displayTitle)
            .isEmpty ? comic.fileName : service.sanitizeFolderName(comic.displayTitle)
        var packageURL = directory.appendingPathComponent(
            "\(baseName).\(BookPackage.fileExtension)")
        packageURL = service.resolveConflict(at: packageURL)

        do {
            let archive = try Archive(url: packageURL, accessMode: .create)

            // ── 1. Stream the book file in, hashing as we go (0.0 → 0.95) ──
            let handle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? handle.close() }
            var hasher = SHA256()

            try archive.addEntry(
                with: comic.bookEntryPathInPackage,
                type: .file,
                uncompressedSize: fileSize,
                compressionMethod: .none,
                bufferSize: chunkSize
            ) { position, size in
                try handle.seek(toOffset: UInt64(position))
                let data = handle.readData(ofLength: size)
                hasher.update(data: data)
                if fileSize > 0 {
                    onProgress(min(0.95, Double(position + Int64(data.count)) / Double(fileSize) * 0.95))
                }
                return data
            }

            let digest = hasher.finalize()
            let sha256 = digest.map { String(format: "%02x", $0) }.joined()

            // ── 2. Cover (raw bytes, already a small downsampled JPEG) ──
            if let coverData = comic.coverImageData {
                try addDataEntry(coverData, at: BookPackage.coverEntryPath, to: archive)
            }

            // ── 3. Manifest (written last — it needs the hash) ──
            let manifest = TransferManifest(
                comic: comic, fileSHA256: sha256, actualFileSize: fileSize)
            let manifestData = try BookPackage.jsonEncoder().encode(manifest)
            try addDataEntry(
                manifestData, at: BookPackage.manifestEntryPath, to: archive,
                compressionMethod: .deflate)

            onProgress(1.0)
            AppLog.files.info(
                "[BookPackageExporter] ✅ Packaged \(comic.fileName) → \(packageURL.lastPathComponent)"
            )
            return packageURL

        } catch let error as BookPackageExportError {
            try? fm.removeItem(at: packageURL)
            throw error
        } catch {
            // Never leave a half-written package behind
            try? fm.removeItem(at: packageURL)
            throw BookPackageExportError.cannotCreatePackage(underlying: error)
        }
    }

    // MARK: - Helpers

    /// Adds an in-memory blob as a zip entry.
    private static func addDataEntry(
        _ data: Data,
        at path: String,
        to archive: Archive,
        compressionMethod: CompressionMethod = .none
    ) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: compressionMethod
        ) { position, size in
            let start = Int(position)
            return data.subdata(in: start..<start + size)
        }
    }
}

// MARK: - Comic Helper

extension Comic {
    /// Zip entry path this book occupies inside its transfer package.
    var bookEntryPathInPackage: String {
        BookPackage.bookEntryPath(for: fileName)
    }
}
