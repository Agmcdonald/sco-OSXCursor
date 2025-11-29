//
//  CBZReader.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import ZIPFoundation

// MARK: - CBZ Reader
class CBZReader: ComicReaderProtocol {
    
    // MARK: - Load Comic
    func loadComic(from url: URL) async throws -> ComicBook {
        let startTime = Date().timeIntervalSince1970
        print("    [CBZReader] loadComic() ENTRY at \(startTime)")
        print("    [CBZReader] URL: \(url.path)")
        
        // Check if bundled resource
        let isBundled = url.path.contains(Bundle.main.bundlePath)
        print("    [CBZReader] Is bundled: \(isBundled)")
        
        // Only start security access for user files
        var accessing = false
        if !isBundled {
            print("    [CBZReader] Attempting to start security-scoped access...")
            accessing = url.startAccessingSecurityScopedResource()
            print("    [CBZReader] Security access started: \(accessing)")
        } else {
            print("    [CBZReader] Skipping security access for bundled resource")
        }
        
        // Note: We keep access open during reading. The ReaderViewModel will release it.
        
        // Verify file exists
        print("    [CBZReader] Checking if file exists...")
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        print("    [CBZReader] File exists: \(fileExists)")
        
        guard fileExists else {
            print("    [CBZReader] ❌ ERROR: File not found")
            throw ComicReaderError.fileNotFound
        }
        
        // Get file attributes
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("    [CBZReader] File size: \(fileSize) bytes")
        } catch {
            print("    [CBZReader] ⚠️ Could not get file attributes: \(error)")
        }
        
        // Open archive
        print("    [CBZReader] Attempting to open ZIP archive...")
        guard let archive = Archive(url: url, accessMode: .read) else {
            print("    [CBZReader] ❌ ERROR: Failed to open archive")
            throw ComicReaderError.invalidFormat
        }
        print("    [CBZReader] ✅ Archive opened successfully")
        
        // Extract image entries
        print("    [CBZReader] Extracting image entries...")
        let imageEntries = try getImageEntries(from: archive)
        print("    [CBZReader] Found \(imageEntries.count) image entries")
        
        guard !imageEntries.isEmpty else {
            print("    [CBZReader] ❌ ERROR: No images found in archive")
            throw ComicReaderError.noImages
        }
        
        // Sort entries naturally (1, 2, 3, 10, 11, not 1, 10, 11, 2, 3)
        print("    [CBZReader] Sorting entries naturally...")
        let sortedEntries = imageEntries.sorted { entry1, entry2 in
            entry1.path.localizedStandardCompare(entry2.path) == .orderedAscending
        }
        print("    [CBZReader] First entry: \(sortedEntries.first?.path ?? "none")")
        
        // Extract images
        print("    [CBZReader] Extracting \(sortedEntries.count) pages...")
        var pages: [ComicPage] = []
        for (index, entry) in sortedEntries.enumerated() {
            do {
                var imageData = Data()
                _ = try archive.extract(entry) { data in
                    imageData.append(data)
                }
                
                let page = ComicPage(
                    pageNumber: index + 1,
                    imageData: imageData,
                    fileName: entry.path
                )
                pages.append(page)
                
                if index == 0 {
                    print("    [CBZReader] ✅ Extracted first page (\(imageData.count) bytes)")
                }
            } catch {
                print("    [CBZReader] ⚠️ Failed to extract page \(entry.path): \(error)")
                // Continue with other pages
                continue
            }
        }
        
        print("    [CBZReader] Successfully extracted \(pages.count) pages")
        
        guard !pages.isEmpty else {
            print("    [CBZReader] ❌ ERROR: No pages extracted")
            throw ComicReaderError.extractionFailed
        }
        
        // Try to extract metadata
        print("    [CBZReader] Extracting metadata...")
        let metadata = try? extractMetadata(from: archive)
        print("    [CBZReader] Metadata: \(metadata != nil ? "found" : "not found")")
        
        let endTime = Date().timeIntervalSince1970
        print("    [CBZReader] ✅ loadComic() SUCCESS - Time: \(String(format: "%.3f", endTime - startTime))s")
        
        return ComicBook(sourceURL: url, pages: pages, metadata: metadata)
    }
    
    // MARK: - Extract Cover
    func extractCover(from url: URL) async throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }
        
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ComicReaderError.invalidFormat
        }
        
        let imageEntries = try getImageEntries(from: archive)
        
        guard !imageEntries.isEmpty else {
            throw ComicReaderError.noImages
        }
        
        // Sort and get first image
        let sortedEntries = imageEntries.sorted { entry1, entry2 in
            entry1.path.localizedStandardCompare(entry2.path) == .orderedAscending
        }
        
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
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }
        
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ComicReaderError.invalidFormat
        }
        
        let imageEntries = try getImageEntries(from: archive)
        return imageEntries.count
    }
    
    // MARK: - Load Single Page (Not Used for CBZ - Already Fast)
    func loadPage(at index: Int, from url: URL) async throws -> ComicPage {
        // CBZ loading is already fast (< 1 second for full archive)
        // Lazy loading not needed, but implement for protocol conformance
        throw ComicReaderError.extractionFailed
    }
    
    // MARK: - Helper Methods
    
    /// Get all image entries from archive
    private func getImageEntries(from archive: Archive) throws -> [Entry] {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]
        
        let imageEntries = archive.filter { entry in
            let pathExtension = (entry.path as NSString).pathExtension.lowercased()
            return imageExtensions.contains(pathExtension) && !entry.path.hasPrefix("__MACOSX")
        }
        
        return Array(imageEntries)
    }
    
    /// Extract ComicInfo.xml metadata
    private func extractMetadata(from archive: Archive) throws -> ComicMetadata? {
        // Look for ComicInfo.xml
        guard let metadataEntry = archive["ComicInfo.xml"] else {
            print("    [CBZReader] No ComicInfo.xml found in archive")
            return nil
        }
        
        var metadataData = Data()
        _ = try archive.extract(metadataEntry) { data in
            metadataData.append(data)
        }
        
        print("    [CBZReader] Found ComicInfo.xml (\(metadataData.count) bytes)")
        
        // Parse using MetadataParser
        guard let metadata = MetadataParser.parseComicInfo(from: metadataData) else {
            print("    [CBZReader] Failed to parse ComicInfo.xml")
            return nil
        }
        
        print("    [CBZReader] ✅ Parsed metadata: \(metadata.displayTitle ?? "Unknown")")
        return metadata
    }
}

