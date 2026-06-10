//
//  PDFReader.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import PDFKit

// MARK: - PDF Reader
class PDFReader: ComicReaderProtocol {
    
    // MARK: - Load Comic (with Lazy Loading)
    func loadComic(from url: URL) async throws -> ComicBook {
        return try await Task.detached {
            try self._loadComic(from: url)
        }.value
    }

    private func _loadComic(from url: URL) throws -> ComicBook {
        let startTime = Date().timeIntervalSince1970
        print("    [PDFReader] loadComic() ENTRY at \(startTime)")
        print("    [PDFReader] URL: \(url.path)")
        
        // Check if bundled resource
        let isBundled = url.path.contains(Bundle.main.bundlePath)
        print("    [PDFReader] Is bundled: \(isBundled)")
        
        // Only start security access for user files
        var accessing = false
        if !isBundled {
            print("    [PDFReader] Attempting to start security-scoped access...")
            accessing = url.startAccessingSecurityScopedResource()
            print("    [PDFReader] Security access started: \(accessing)")
        } else {
            print("    [PDFReader] Skipping security access for bundled resource")
        }
        
        // Note: We keep access open during reading. The ReaderViewModel will release it.
        
        // Verify file exists
        print("    [PDFReader] Checking if file exists...")
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        print("    [PDFReader] File exists: \(fileExists)")
        
        guard fileExists else {
            print("    [PDFReader] ❌ ERROR: File not found")
            throw ComicReaderError.fileNotFound
        }
        
        // Get file attributes
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("    [PDFReader] File size: \(fileSize) bytes")
        } catch {
            print("    [PDFReader] ⚠️ Could not get file attributes: \(error)")
        }
        
        // Load PDF document
        print("    [PDFReader] Attempting to load PDFDocument...")
        guard let pdfDocument = PDFDocument(url: url) else {
            print("    [PDFReader] ❌ ERROR: Failed to load PDF document")
            throw ComicReaderError.invalidFormat
        }
        print("    [PDFReader] ✅ PDFDocument loaded successfully")
        
        // Get page count
        let pageCount = pdfDocument.pageCount
        print("    [PDFReader] Page count: \(pageCount)")
        
        guard pageCount > 0 else {
            print("    [PDFReader] ❌ ERROR: No pages in PDF")
            throw ComicReaderError.noImages
        }
        
        // For PDFs, use lazy loading: load only first 3 pages initially
        print("    [PDFReader] 🚀 Using LAZY LOADING - loading first 3 pages only")
        var initialPages: [ComicPage] = []
        let pagesToLoad = min(3, pageCount)
        
        for pageIndex in 0..<pagesToLoad {
            guard let pdfPage = pdfDocument.page(at: pageIndex) else {
                continue
            }
            
            // Render page to image
            let imageData = renderPageToImageData(pdfPage)
            
            let page = ComicPage(
                pageNumber: pageIndex + 1,
                imageData: imageData,
                fileName: "Page \(pageIndex + 1)"
            )
            initialPages.append(page)
            
            if pageIndex == 0 {
                print("    [PDFReader] ✅ Rendered first page (\(imageData.count) bytes)")
            }
        }
        
        print("    [PDFReader] Successfully rendered \(initialPages.count) initial pages")
        
        guard !initialPages.isEmpty else {
            print("    [PDFReader] ❌ ERROR: No pages rendered")
            throw ComicReaderError.extractionFailed
        }
        
        // Extract metadata
        print("    [PDFReader] Extracting metadata...")
        let metadata = extractMetadata(from: pdfDocument)
        print("    [PDFReader] Metadata: \(metadata != nil ? "found" : "not found")")
        
        let endTime = Date().timeIntervalSince1970
        print("    [PDFReader] ✅ loadComic() SUCCESS - Time: \(String(format: "%.3f", endTime - startTime))s")
        print("    [PDFReader] (Remaining \(pageCount - initialPages.count) pages will load on-demand)")
        
        // Return lazy-loaded comic book
        return ComicBook(sourceURL: url, totalPages: pageCount, initialPages: initialPages, metadata: metadata)
    }
    
    // MARK: - Load Single Page (for Lazy Loading)
    func loadPage(at index: Int, from url: URL) async throws -> ComicPage {
        return try await Task.detached {
            try self._loadPage(at: index, from: url)
        }.value
    }

    private func _loadPage(at index: Int, from url: URL) throws -> ComicPage {
        // Load PDF document
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ComicReaderError.invalidFormat
        }
        
        // Get the specific page
        guard let pdfPage = pdfDocument.page(at: index) else {
            throw ComicReaderError.noImages
        }
        
        // Render to image
        let imageData = renderPageToImageData(pdfPage)

        return ComicPage(
            pageNumber: index + 1,
            imageData: imageData,
            fileName: "Page \(index + 1)"
        )
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
        
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ComicReaderError.invalidFormat
        }
        
        guard pdfDocument.pageCount > 0 else {
            throw ComicReaderError.noImages
        }
        
        guard let firstPage = pdfDocument.page(at: 0) else {
            throw ComicReaderError.noImages
        }
        
        return renderPageToImageData(firstPage)
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
        
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ComicReaderError.invalidFormat
        }
        
        return pdfDocument.pageCount
    }
    
    // MARK: - Helper Methods
    
    /// Render PDF page to image data.
    ///
    /// Uses PDFKit's `thumbnail(of:for:)`, which respects the page's /Rotate
    /// entry and renders right-side-up on BOTH platforms. (The previous manual
    /// Core Graphics path flipped EVERY landscape page on iOS as a workaround,
    /// which turned correctly-oriented pages upside down.)
    /// Encodes as JPEG (quality 0.85) — ~10x smaller and faster than PNG.
    private func renderPageToImageData(_ page: PDFPage) -> Data {
        let pageBounds = page.bounds(for: .mediaBox)
        let rotation = abs(page.rotation % 360)

        // Account for page rotation when computing the target pixel size
        let baseSize = (rotation == 90 || rotation == 270)
            ? CGSize(width: pageBounds.height, height: pageBounds.width)
            : pageBounds.size

        let scale: CGFloat = 2.0
        var targetSize = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)

        // Cap the long side — very tall pages (webtoon-style PDFs) would
        // otherwise produce enormous bitmaps
        let maxLongSide: CGFloat = 8000
        let longSide = max(targetSize.width, targetSize.height)
        if longSide > maxLongSide {
            let factor = maxLongSide / longSide
            targetSize = CGSize(
                width: targetSize.width * factor, height: targetSize.height * factor)
        }

        let rendered = page.thumbnail(of: targetSize, for: .mediaBox)

        // Composite onto white before JPEG encoding (JPEG has no alpha —
        // transparent PDF backgrounds would otherwise turn black)
        #if os(macOS)
        let composited = NSImage(size: rendered.size)
        composited.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: rendered.size).fill()
        rendered.draw(
            in: NSRect(origin: .zero, size: rendered.size),
            from: .zero, operation: .sourceOver, fraction: 1.0)
        composited.unlockFocus()

        if let tiffData = composited.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmapImage.representation(
               using: .jpeg, properties: [.compressionFactor: 0.85]) {
            return jpegData
        }
        return Data()

        #else
        let renderer = UIGraphicsImageRenderer(size: rendered.size)
        let composited = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: rendered.size))
            rendered.draw(in: CGRect(origin: .zero, size: rendered.size))
        }
        return composited.jpegData(compressionQuality: 0.85) ?? Data()
        #endif
    }
    
    /// Extract metadata from PDF document
    private func extractMetadata(from document: PDFDocument) -> ComicMetadata? {
        guard let attributes = document.documentAttributes else {
            print("    [PDFReader] No document attributes found")
            return nil
        }
        
        var metadata = ComicMetadata()
        
        // Extract standard PDF metadata
        if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
            metadata.title = title
            print("    [PDFReader] Found title: \(title)")
        }
        
        if let author = attributes[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty {
            metadata.writer = author
            print("    [PDFReader] Found author: \(author)")
        }
        
        if let subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String, !subject.isEmpty {
            metadata.summary = subject
            print("    [PDFReader] Found subject: \(subject)")
        }
        
        if let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] as? [String], !keywords.isEmpty {
            metadata.genre = keywords.joined(separator: ", ")
            print("    [PDFReader] Found keywords: \(keywords)")
        }
        
        if let creator = attributes[PDFDocumentAttribute.creatorAttribute] as? String, !creator.isEmpty {
            metadata.notes = "Created with: \(creator)"
        }
        
        if let producer = attributes[PDFDocumentAttribute.producerAttribute] as? String, !producer.isEmpty {
            metadata.scanInformation = producer
        }
        
        // Extract creation date
        if let creationDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day], from: creationDate)
            metadata.year = components.year
            metadata.month = components.month
            metadata.day = components.day
            print("    [PDFReader] Found creation date: \(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)")
        }
        
        // Page count
        metadata.pageCount = document.pageCount
        print("    [PDFReader] Page count: \(document.pageCount)")
        
        // Return nil if no useful metadata was found
        if metadata.title == nil && metadata.writer == nil && metadata.summary == nil && metadata.year == nil {
            print("    [PDFReader] No useful metadata found")
            return nil
        }
        
        print("    [PDFReader] ✅ Extracted metadata: \(metadata.displayTitle ?? "Unknown")")
        return metadata
    }
}

