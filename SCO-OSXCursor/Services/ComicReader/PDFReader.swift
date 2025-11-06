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
    
    // MARK: - Load Comic
    func loadComic(from url: URL) async throws -> ComicBook {
        // Start accessing security-scoped resource
        // NOTE: Don't use defer - we need persistent access for the reader
        let accessing = url.startAccessingSecurityScopedResource()
        
        // We intentionally DON'T call stopAccessingSecurityScopedResource here
        // The Comic model will maintain the URL, and the reader needs access to it
        // The system will clean up when the app terminates or the URL is released
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ComicReaderError.fileNotFound
        }
        
        // Load PDF document
        guard let pdfDocument = PDFDocument(url: url) else {
            throw ComicReaderError.invalidFormat
        }
        
        // Get page count
        let pageCount = pdfDocument.pageCount
        
        guard pageCount > 0 else {
            throw ComicReaderError.noImages
        }
        
        // Extract all pages as images
        var pages: [ComicPage] = []
        
        for pageIndex in 0..<pageCount {
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
            pages.append(page)
        }
        
        guard !pages.isEmpty else {
            throw ComicReaderError.extractionFailed
        }
        
        // Extract metadata
        let metadata = extractMetadata(from: pdfDocument)
        
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
        
        #if os(macOS)
        // macOS rendering
        let scale: CGFloat = 2.0 // Retina resolution
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
        let scale: CGFloat = UIScreen.main.scale
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

