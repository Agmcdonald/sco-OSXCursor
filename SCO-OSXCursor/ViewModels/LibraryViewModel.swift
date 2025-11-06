//
//  LibraryViewModel.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Library ViewModel
@MainActor
class LibraryViewModel: ObservableObject {
    @Published var comics: [Comic] = []
    @Published var isImporting: Bool = false
    @Published var importProgress: Double = 0.0
    @Published var importError: String?
    
    private let cbzReader = CBZReader()
    private let pdfReader = PDFReader()
    
    init() {
        // Start with sample data
        self.comics = Comic.samples
        
        // Add bundled test comic if available
        loadBundledTestComic()
    }
    
    // MARK: - Load Bundled Test Comic
    private func loadBundledTestComic() {
        if let bundleURL = Bundle.main.url(forResource: "Billy_Bunny_01", withExtension: "cbz") {
            Task {
                do {
                    let testComic = try await importComic(from: bundleURL)
                    // Add to beginning of list
                    comics.insert(testComic, at: 0)
                } catch {
                    print("Failed to load bundled test comic: \(error)")
                }
            }
        }
    }
    
    // MARK: - Import Comics
    func importComics(from urls: [URL]) async {
        isImporting = true
        importError = nil
        importProgress = 0.0
        
        var newComics: [Comic] = []
        let total = Double(urls.count)
        
        for (index, url) in urls.enumerated() {
            do {
                // Import single comic
                let comic = try await importComic(from: url)
                newComics.append(comic)
                
                // Update progress
                importProgress = Double(index + 1) / total
                
            } catch {
                print("Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
                // Continue with other files
            }
        }
        
        // Add to comics array
        if !newComics.isEmpty {
            comics.append(contentsOf: newComics)
            print("Successfully imported \(newComics.count) comics")
        }
        
        isImporting = false
        importProgress = 0.0
    }
    
    // MARK: - Import Single Comic
    private func importComic(from url: URL) async throws -> Comic {
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // NOTE: We store the original URL. On macOS, when selecting files via fileImporter
        // or drag & drop, the URLs already have persistent access granted by the system.
        // Additional bookmarking is only needed for files accessed via NSOpenPanel.
        let bookmarkedURL = url
        
        // Determine file type
        let fileExtension = url.pathExtension.lowercased()
        guard let fileType = Comic.FileType(rawValue: fileExtension) else {
            throw ComicReaderError.invalidFormat
        }
        
        // Select appropriate reader
        let reader: ComicReaderProtocol
        switch fileType {
        case .cbz:
            reader = cbzReader
        case .pdf:
            reader = pdfReader
        case .cbr:
            throw ComicReaderError.invalidFormat // Not yet supported
        }
        
        // Extract cover
        let coverData = try await reader.extractCover(from: url)
        
        // Get page count
        let pageCount = try await reader.getPageCount(from: url)
        
        // Get file size
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        
        // Create comic object with bookmarked URL for persistent access
        let comic = Comic(
            filePath: bookmarkedURL,
            fileName: url.lastPathComponent,
            coverImageData: coverData,
            status: .unread,
            currentPage: 0,
            totalPages: pageCount,
            fileSize: fileSize,
            fileType: fileType
        )
        
        return comic
    }
    
    // MARK: - Delete Comics
    func deleteComics(_ comicsToDelete: [Comic]) {
        comics.removeAll { comic in
            comicsToDelete.contains { $0.id == comic.id }
        }
    }
    
    // MARK: - Update Comic
    func updateComic(_ comic: Comic) {
        if let index = comics.firstIndex(where: { $0.id == comic.id }) {
            comics[index] = comic
        }
    }
}

