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
        print("    [PDFReader] loadPage() - Loading page \(index + 1)")
        
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
        
        print("    [PDFReader] ✅ Loaded page \(index + 1) (\(imageData.count) bytes)")
        
        return ComicPage(
            pageNumber: index + 1,
            imageData: imageData,
            fileName: "Page \(index + 1)"
        )
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
    
    /// Render PDF page to image data
    private func renderPageToImageData(_ page: PDFPage) -> Data {
        let pageBounds = page.bounds(for: .mediaBox)
        let rotation = page.rotation
        
        print("    [PDFReader] Page rotation: \(rotation)°")
        print("    [PDFReader] Page bounds: \(pageBounds)")
        
        #if os(macOS)
        // macOS rendering
        let scale: CGFloat = 2.0 // Fixed 2x for performance
        let scaledSize = CGSize(
            width: pageBounds.width * scale,
            height: pageBounds.height * scale
        )
        
        let image = NSImage(size: scaledSize)
        image.lockFocus()
        
        // Set up context
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            
            // White background
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            // Scale and render
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            
            context.restoreGState()
        }
        
        image.unlockFocus()
        
        // Convert to PNG data
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapImage.representation(using: .png, properties: [:]) {
            return pngData
        }
        
        return Data()
        
        #else
        // iOS/iPadOS rendering
        let scale: CGFloat = 2.0 // Fixed 2x for performance (not device scale)
        
        let scaledSize = CGSize(
            width: pageBounds.width * scale,
            height: pageBounds.height * scale
        )
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { context in
            // White background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            // Save state
            context.cgContext.saveGState()
            
            // iOS PDFKit renders some PDFs upside down (macOS handles this automatically)
            // Flip vertically only (not horizontally) to fix upside-down landscape PDFs
            if pageBounds.width > pageBounds.height {
                // Landscape page - flip vertically only
                print("    [PDFReader] Landscape page detected, flipping vertically")
                // Translate to bottom, scale Y by -1, translate back
                context.cgContext.translateBy(x: 0, y: scaledSize.height)
                context.cgContext.scaleBy(x: 1.0, y: -1.0)
            }
            
            // Scale and render
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            
            context.cgContext.restoreGState()
        }
        
        return image.pngData() ?? Data()
        #endif
    }
    
    /// Extract metadata from PDF document
    private func extractMetadata(from document: PDFDocument) -> ComicMetadata? {
        guard let attributes = document.documentAttributes else {
            return nil
        }
        
        var metadata = ComicMetadata()
        
        // Extract standard PDF metadata
        if let title = attributes[PDFDocumentAttribute.titleAttribute] as? String {
            metadata.title = title
        }
        
        if let author = attributes[PDFDocumentAttribute.authorAttribute] as? String {
            metadata.writer = author
        }
        
        if let subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String {
            metadata.summary = subject
        }
        
        // Extract creation date
        if let creationDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: creationDate)
            metadata.year = components.year
            metadata.month = components.month
        }
        
        // Page count
        metadata.pageCount = document.pageCount
        
        // Return nil if no useful metadata was found
        if metadata.title == nil && metadata.writer == nil && metadata.summary == nil {
            return nil
        }
        
        return metadata
    }
}

