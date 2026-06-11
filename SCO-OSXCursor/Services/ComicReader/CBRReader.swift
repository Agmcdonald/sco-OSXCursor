//
//  CBRReader.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 2/15/26.
//

import Foundation
import Unrar
import os

// MARK: - CBR Reader (RAR Archive)
//
// NOTE: Security-scoped resource access is managed centrally by ReaderViewModel
// (via resolveFileURL). CBRReader MUST NOT call startAccessingSecurityScopedResource /
// stopAccessingSecurityScopedResource itself — doing so would cause double-start,
// prematurely end access via defer, and produce "Operation not permitted" errors on
// subsequent page reads (manifesting as Unrar.UnrarError error 2 / badArchive).
//
class CBRReader: ComicReaderProtocol {

    private let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]

    // MARK: - Load Comic
    func loadComic(from url: URL) async throws -> ComicBook {
        return try await Task.detached {
            try self._loadComic(from: url)
        }.value
    }

    /// Number of pages extracted eagerly so the reader can render instantly.
    /// Remaining pages load on demand via `loadPage(at:)` (windowed prefetch).
    private let initialPageCount = 3

    private func _loadComic(from url: URL) throws -> ComicBook {
        // Verify file exists (security access is already held by ReaderViewModel)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }

        // Open RAR archive
        let archive: Archive
        do {
            archive = try Archive(fileURL: url)
        } catch {
            #if DEBUG
                AppLog.reader.error("[CBRReader] ❌ Failed to open RAR archive: \(error)")
            #endif
            throw ComicReaderError.invalidFormat
        }

        let sortedEntries = try sortedImageEntries(from: archive)

        guard !sortedEntries.isEmpty else {
            throw ComicReaderError.noImages
        }

        // Extract only the initial window of pages — the rest stream in lazily
        var initialPages: [ComicPage] = []
        for (index, entry) in sortedEntries.prefix(initialPageCount).enumerated() {
            do {
                let imageData = try archive.extract(entry)
                initialPages.append(
                    ComicPage(
                        pageNumber: index + 1,
                        imageData: imageData,
                        fileName: entry.fileName
                    ))
            } catch {
                #if DEBUG
                    AppLog.reader.error("[CBRReader] ⚠️ Failed to extract page \(entry.fileName): \(error)")
                #endif
                continue
            }
        }

        guard !initialPages.isEmpty else {
            throw ComicReaderError.extractionFailed
        }

        #if DEBUG
            AppLog.reader.info("[CBRReader] ✅ Opened \(url.lastPathComponent): \(sortedEntries.count) pages (\(initialPages.count) eager)")
        #endif

        return ComicBook(
            sourceURL: url,
            totalPages: sortedEntries.count,
            initialPages: initialPages,
            metadata: nil
        )
    }

    // MARK: - Extract ComicInfo.xml only (no page extraction)
    /// Lightweight metadata read used during import staging.
    func extractComicInfo(from url: URL) async throws -> ComicMetadata? {
        return try await Task.detached {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ComicReaderError.fileNotFound
            }
            let archive = try Archive(fileURL: url)
            let entries = try archive.entries()
            guard
                let infoEntry = entries.first(where: {
                    ($0.fileName as NSString).lastPathComponent.lowercased() == "comicinfo.xml"
                })
            else { return nil }
            let data = try archive.extract(infoEntry)
            return MetadataParser.parseComicInfo(from: data)
        }.value
    }

    // MARK: - Extract Cover
    func extractCover(from url: URL) async throws -> Data {
        return try await Task.detached {
            try self._extractCover(from: url)
        }.value
    }

    private func _extractCover(from url: URL) throws -> Data {
        // Note: For cover extraction during import, CBRReader may be called
        // without an active security scope. We start/stop access here ONLY
        // for this import-time use case (not during reading).
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }

        let archive = try Archive(fileURL: url)
        let sortedEntries = try sortedImageEntries(from: archive)

        guard let firstEntry = sortedEntries.first else {
            throw ComicReaderError.noImages
        }

        let coverData = try archive.extract(firstEntry)
        return coverData
    }

    // MARK: - Get Page Count
    func getPageCount(from url: URL) async throws -> Int {
        return try await Task.detached {
            try self._getPageCount(from: url)
        }.value
    }

    private func _getPageCount(from url: URL) throws -> Int {
        // Security access is already held by ReaderViewModel when reading.
        // For import-time calls, the URL is already user-selected so accessible.
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }

        let archive = try Archive(fileURL: url)
        return try sortedImageEntries(from: archive).count
    }

    // MARK: - Load Single Page
    func loadPage(at index: Int, from url: URL) async throws -> ComicPage {
        return try await Task.detached {
            try self._loadPage(at: index, from: url)
        }.value
    }

    private func _loadPage(at index: Int, from url: URL) throws -> ComicPage {
        // Security access is already held by ReaderViewModel.
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }

        let archive = try Archive(fileURL: url)
        let sortedEntries = try sortedImageEntries(from: archive)

        guard index >= 0 && index < sortedEntries.count else {
            throw ComicReaderError.extractionFailed
        }

        let entry = sortedEntries[index]
        let imageData = try archive.extract(entry)

        return ComicPage(
            pageNumber: index + 1,
            imageData: imageData,
            fileName: entry.fileName
        )
    }

    // MARK: - Helper Methods

    /// All image entries from the archive, naturally sorted (1, 2, 10 — not 1, 10, 2).
    private func sortedImageEntries(from archive: Archive) throws -> [Entry] {
        let entries: [Entry]
        do {
            entries = try archive.entries()
        } catch {
            throw ComicReaderError.extractionFailed
        }

        let imageEntries = entries.filter { entry in
            let pathExtension = (entry.fileName as NSString).pathExtension.lowercased()
            return imageExtensions.contains(pathExtension) && !entry.fileName.hasPrefix("__MACOSX")
        }

        return imageEntries.sorted { entry1, entry2 in
            entry1.fileName.localizedStandardCompare(entry2.fileName) == .orderedAscending
        }
    }
}
