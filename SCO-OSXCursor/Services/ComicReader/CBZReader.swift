//
//  CBZReader.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import ZIPFoundation
import os

// MARK: - CBZ Reader
//
// Lazy-loading: `loadComic` opens the archive, lists/sorts entries, and extracts
// only the first few pages so the reader opens immediately. Remaining pages are
// extracted on demand via `loadPage(at:)`, driven by ReaderViewModel's
// windowed prefetcher. This keeps memory proportional to the read window
// instead of the whole book (previously a 300 MB CBZ cost 300+ MB of RAM
// before the first page appeared).
class CBZReader: ComicReaderProtocol {

    /// Number of pages extracted eagerly so the reader can render instantly.
    private let initialPageCount = 3

    // MARK: - Load Comic
    func loadComic(from url: URL) async throws -> ComicBook {
        return try await Task.detached {
            try self._loadComic(from: url)
        }.value
    }

    private func _loadComic(from url: URL) throws -> ComicBook {
        // Check if bundled resource
        let isBundled = url.path.contains(Bundle.main.bundlePath)

        // Only start security access for user files.
        // Note: access is kept open during reading; ReaderViewModel's deinit
        // releases it via cleanupURL.
        if !isBundled {
            _ = url.startAccessingSecurityScopedResource()
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }

        // Open archive and list pages
        let archive = try Archive(url: url, accessMode: .read)
        let sortedEntries = try sortedImageEntries(from: archive)

        guard !sortedEntries.isEmpty else {
            throw ComicReaderError.noImages
        }

        // Extract only the initial window of pages
        var initialPages: [ComicPage] = []
        for (index, entry) in sortedEntries.prefix(initialPageCount).enumerated() {
            do {
                var imageData = Data()
                _ = try archive.extract(entry) { data in
                    imageData.append(data)
                }
                initialPages.append(
                    ComicPage(
                        pageNumber: index + 1,
                        imageData: imageData,
                        fileName: entry.path
                    ))
            } catch {
                #if DEBUG
                    AppLog.reader.error("[CBZReader] ⚠️ Failed to extract page \(entry.path): \(error)")
                #endif
                continue
            }
        }

        guard !initialPages.isEmpty else {
            throw ComicReaderError.extractionFailed
        }

        // Try to extract metadata (ComicInfo.xml)
        let metadata = try? extractMetadata(from: archive)

        #if DEBUG
            AppLog.reader.info("[CBZReader] ✅ Opened \(url.lastPathComponent): \(sortedEntries.count) pages (\(initialPages.count) eager)")
        #endif

        return ComicBook(
            sourceURL: url,
            totalPages: sortedEntries.count,
            initialPages: initialPages,
            metadata: metadata
        )
    }

    // MARK: - Load Single Page (lazy loading)
    func loadPage(at index: Int, from url: URL) async throws -> ComicPage {
        return try await Task.detached {
            try self._loadPage(at: index, from: url)
        }.value
    }

    private func _loadPage(at index: Int, from url: URL) throws -> ComicPage {
        // Security access is already held by ReaderViewModel while reading.
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }

        // Re-opening the archive per page is cheap for ZIP (central directory
        // read only) and keeps this method safe to call from concurrent tasks.
        let archive = try Archive(url: url, accessMode: .read)
        let sortedEntries = try sortedImageEntries(from: archive)

        guard index >= 0 && index < sortedEntries.count else {
            throw ComicReaderError.extractionFailed
        }

        let entry = sortedEntries[index]
        var imageData = Data()
        _ = try archive.extract(entry) { data in
            imageData.append(data)
        }

        return ComicPage(
            pageNumber: index + 1,
            imageData: imageData,
            fileName: entry.path
        )
    }

    // MARK: - Extract ComicInfo.xml only (no page extraction)
    /// Lightweight metadata read used during import staging — opens the
    /// archive's central directory and pulls just ComicInfo.xml.
    func extractComicInfo(from url: URL) async throws -> ComicMetadata? {
        return try await Task.detached {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ComicReaderError.fileNotFound
            }
            let archive = try Archive(url: url, accessMode: .read)
            return try self.extractMetadata(from: archive)
        }.value
    }

    // MARK: - Extract Cover
    func extractCover(from url: URL) async throws -> Data {
        return try await Task.detached {
            try self._extractCover(from: url)
        }.value
    }

    private func _extractCover(from url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }

        let archive = try Archive(url: url, accessMode: .read)
        let sortedEntries = try sortedImageEntries(from: archive)

        guard let firstEntry = sortedEntries.first else {
            throw ComicReaderError.noImages
        }

        var coverData = Data()
        _ = try archive.extract(firstEntry) { data in
            coverData.append(data)
        }

        return coverData
    }

    // MARK: - Get Page Count
    func getPageCount(from url: URL) async throws -> Int {
        return try await Task.detached {
            try self._getPageCount(from: url)
        }.value
    }

    private func _getPageCount(from url: URL) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }

        let archive = try Archive(url: url, accessMode: .read)
        return try sortedImageEntries(from: archive).count
    }

    // MARK: - Helper Methods

    /// All image entries from the archive, naturally sorted (1, 2, 10 — not 1, 10, 2).
    private func sortedImageEntries(from archive: Archive) throws -> [Entry] {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]

        let imageEntries = archive.filter { entry in
            let pathExtension = (entry.path as NSString).pathExtension.lowercased()
            return imageExtensions.contains(pathExtension) && !entry.path.hasPrefix("__MACOSX")
        }

        return imageEntries.sorted { entry1, entry2 in
            entry1.path.localizedStandardCompare(entry2.path) == .orderedAscending
        }
    }

    /// Extract ComicInfo.xml metadata
    private func extractMetadata(from archive: Archive) throws -> ComicMetadata? {
        guard let metadataEntry = archive["ComicInfo.xml"] else {
            return nil
        }

        var metadataData = Data()
        _ = try archive.extract(metadataEntry) { data in
            metadataData.append(data)
        }

        guard let metadata = MetadataParser.parseComicInfo(from: metadataData) else {
            return nil
        }

        #if DEBUG
            AppLog.reader.info("[CBZReader] ✅ Parsed ComicInfo.xml: \(metadata.displayTitle ?? "Unknown")")
        #endif
        return metadata
    }
}
