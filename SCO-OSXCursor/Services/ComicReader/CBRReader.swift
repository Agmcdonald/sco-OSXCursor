//
//  CBRReader.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 2/15/26.
//

import Foundation
import Unrar

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

    private func _loadComic(from url: URL) throws -> ComicBook {
        let startTime = Date().timeIntervalSince1970
        print("    [CBRReader] loadComic() ENTRY at \(startTime)")
        print("    [CBRReader] URL: \(url.path)")

        // Verify file exists (security access is already held by ReaderViewModel)
        print("    [CBRReader] Checking if file exists...")
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        print("    [CBRReader] File exists: \(fileExists)")

        guard fileExists else {
            print("    [CBRReader] ❌ ERROR: File not found")
            throw ComicReaderError.fileNotFound
        }

        // Get file attributes
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("    [CBRReader] File size: \(fileSize) bytes")
        } catch {
            print("    [CBRReader] ⚠️ Could not get file attributes: \(error)")
        }

        // Open RAR archive
        print("    [CBRReader] Attempting to open RAR archive...")
        let archive: Archive
        do {
            archive = try Archive(fileURL: url)
        } catch {
            print("    [CBRReader] ❌ Failed to open RAR archive: \(error)")
            throw ComicReaderError.invalidFormat
        }
        print("    [CBRReader] ✅ Archive opened successfully")

        // Get image entries
        print("    [CBRReader] Extracting image entries...")
        let entries: [Entry]
        do {
            entries = try archive.entries()
        } catch {
            print("    [CBRReader] ❌ Failed to list entries: \(error)")
            throw ComicReaderError.extractionFailed
        }

        let imageEntries = entries.filter { entry in
            let pathExtension = (entry.fileName as NSString).pathExtension.lowercased()
            return imageExtensions.contains(pathExtension) && !entry.fileName.hasPrefix("__MACOSX")
        }
        print("    [CBRReader] Found \(imageEntries.count) image entries")

        guard !imageEntries.isEmpty else {
            print("    [CBRReader] ❌ ERROR: No images found in archive")
            throw ComicReaderError.noImages
        }

        // Sort entries naturally (1, 2, 3, 10, 11, not 1, 10, 11, 2, 3)
        print("    [CBRReader] Sorting entries naturally...")
        let sortedEntries = imageEntries.sorted { entry1, entry2 in
            entry1.fileName.localizedStandardCompare(entry2.fileName) == .orderedAscending
        }
        print("    [CBRReader] First entry: \(sortedEntries.first?.fileName ?? "none")")

        // Extract images
        print("    [CBRReader] Extracting \(sortedEntries.count) pages...")
        var pages: [ComicPage] = []
        for (index, entry) in sortedEntries.enumerated() {
            do {
                let imageData = try archive.extract(entry)

                let page = ComicPage(
                    pageNumber: index + 1,
                    imageData: imageData,
                    fileName: entry.fileName
                )
                pages.append(page)

                if index == 0 {
                    print("    [CBRReader] ✅ Extracted first page (\(imageData.count) bytes)")
                }
            } catch {
                print("    [CBRReader] ⚠️ Failed to extract page \(entry.fileName): \(error)")
                // Continue with other pages
                continue
            }
        }

        print("    [CBRReader] Successfully extracted \(pages.count) pages")

        guard !pages.isEmpty else {
            print("    [CBRReader] ❌ ERROR: No pages extracted")
            throw ComicReaderError.extractionFailed
        }

        let endTime = Date().timeIntervalSince1970
        print(
            "    [CBRReader] ✅ loadComic() SUCCESS - Time: \(String(format: "%.3f", endTime - startTime))s"
        )

        return ComicBook(sourceURL: url, pages: pages, metadata: nil)
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
        let entries = try archive.entries()

        let imageEntries = entries.filter { entry in
            let pathExtension = (entry.fileName as NSString).pathExtension.lowercased()
            return imageExtensions.contains(pathExtension) && !entry.fileName.hasPrefix("__MACOSX")
        }

        guard !imageEntries.isEmpty else {
            throw ComicReaderError.noImages
        }

        // Sort and get first image
        let sortedEntries = imageEntries.sorted { entry1, entry2 in
            entry1.fileName.localizedStandardCompare(entry2.fileName) == .orderedAscending
        }

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
        let entries = try archive.entries()

        let imageEntries = entries.filter { entry in
            let pathExtension = (entry.fileName as NSString).pathExtension.lowercased()
            return imageExtensions.contains(pathExtension) && !entry.fileName.hasPrefix("__MACOSX")
        }
        return imageEntries.count
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
        let entries = try archive.entries()

        let imageEntries = entries.filter { entry in
            let pathExtension = (entry.fileName as NSString).pathExtension.lowercased()
            return imageExtensions.contains(pathExtension) && !entry.fileName.hasPrefix("__MACOSX")
        }

        let sortedEntries = imageEntries.sorted { entry1, entry2 in
            entry1.fileName.localizedStandardCompare(entry2.fileName) == .orderedAscending
        }

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
}
