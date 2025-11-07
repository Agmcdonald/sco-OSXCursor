//
//  ComicReaderProtocol.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import SwiftUI

// MARK: - Comic Reader Protocol
protocol ComicReaderProtocol {
    /// Load a comic from a file URL
    func loadComic(from url: URL) async throws -> ComicBook
    
    /// Extract cover image from comic
    func extractCover(from url: URL) async throws -> Data
    
    /// Get page count without loading entire comic
    func getPageCount(from url: URL) async throws -> Int
    
    /// Load a specific page (for lazy loading PDFs)
    func loadPage(at index: Int, from url: URL) async throws -> ComicPage
}

// MARK: - Comic Book Structure
struct ComicBook {
    let id: UUID
    let sourceURL: URL
    let pages: [ComicPage]
    let metadata: ComicMetadata?
    let totalPages: Int
    let isLazyLoaded: Bool  // True for PDFs that load pages on-demand
    
    init(sourceURL: URL, pages: [ComicPage], metadata: ComicMetadata? = nil, isLazyLoaded: Bool = false) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.pages = pages
        self.metadata = metadata
        self.totalPages = pages.count
        self.isLazyLoaded = isLazyLoaded
    }
    
    /// Create a lazy-loaded comic book (for PDFs)
    init(sourceURL: URL, totalPages: Int, initialPages: [ComicPage], metadata: ComicMetadata? = nil) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.pages = initialPages
        self.metadata = metadata
        self.totalPages = totalPages
        self.isLazyLoaded = true
    }
}

// MARK: - Comic Page
struct ComicPage: Identifiable {
    let id = UUID()
    let pageNumber: Int
    let imageData: Data
    let fileName: String
    
    #if os(macOS)
    var image: NSImage? {
        NSImage(data: imageData)
    }
    #else
    var image: UIImage? {
        UIImage(data: imageData)
    }
    #endif
}

// MARK: - Comic Metadata
// Note: ComicMetadata is now defined in Services/Metadata/ComicMetadata.swift
// for a more comprehensive metadata model supporting ComicInfo.xml standard

// MARK: - Comic Reader Errors
enum ComicReaderError: LocalizedError {
    case fileNotFound
    case accessDenied
    case invalidFormat
    case corruptedFile
    case noImages
    case extractionFailed
    case metadataParsingFailed
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Comic file not found"
        case .accessDenied:
            return "Access denied. Please grant permission to read this file."
        case .invalidFormat:
            return "Invalid or unsupported comic file format"
        case .corruptedFile:
            return "Comic file is corrupted or incomplete"
        case .noImages:
            return "No images found in comic file"
        case .extractionFailed:
            return "Failed to extract comic contents"
        case .metadataParsingFailed:
            return "Failed to parse comic metadata"
        }
    }
}

