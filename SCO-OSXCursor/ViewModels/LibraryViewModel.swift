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
        // Start with empty library - we'll load bundled test comics
        self.comics = []
        
        // Load bundled test comics if available
        loadBundledTestComic()
    }
    
    // MARK: - Load Bundled Test Comics
    private func loadBundledTestComic() {
        // List of bundled test comics
        let testFiles = [
            ("Billy_Bunny_01", "cbz"),
            ("theprivateeye_01enr00", "cbz"),
            ("theprivateeye_01enr00", "pdf")
        ]
        
        Task {
            for (name, ext) in testFiles {
                if let bundleURL = Bundle.main.url(forResource: name, withExtension: ext) {
                    do {
                        let testComic = try await importComic(from: bundleURL)
                        // Add to beginning of list
                        comics.insert(testComic, at: 0)
                        print("📦 Loaded bundled test comic: \(name).\(ext)")
                    } catch {
                        print("⚠️ Failed to load bundled test comic \(name).\(ext): \(error)")
                    }
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
        // Determine if this is a bundled resource
        let isBundled = url.path.contains(Bundle.main.bundlePath)
        
        // Only start security-scoped access for user files (not bundled resources)
        var accessing = false
        if !isBundled {
            accessing = url.startAccessingSecurityScopedResource()
        } else {
            print("📦 Bundled resource, skipping security access: \(url.lastPathComponent)")
        }
        
        // Create security bookmark for persistent access (skip for bundled resources)
        var bookmarkData: Data?
        if !isBundled {
            #if os(macOS)
            // On macOS, create security-scoped bookmark for persistent access
            do {
                bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                print("✅ Created security bookmark for: \(url.lastPathComponent)")
            } catch {
                print("⚠️ Failed to create bookmark for \(url.lastPathComponent): \(error)")
                // Continue anyway - file may still be accessible
            }
            #endif
        }
        
        // Determine file type
        let fileExtension = url.pathExtension.lowercased()
        guard let fileType = Comic.FileType(rawValue: fileExtension) else {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
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
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            throw ComicReaderError.invalidFormat // Not yet supported
        }
        
        // Extract cover and metadata while we have access
        let coverData = try await reader.extractCover(from: url)
        let pageCount = try await reader.getPageCount(from: url)
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        
        // ALWAYS stop accessing after import - bookmark will restore access later
        if accessing {
            url.stopAccessingSecurityScopedResource()
            print("🔒 Stopped security access after import: \(url.lastPathComponent)")
        }
        
        // Create comic object with bookmark for persistent access
        let comic = Comic(
            filePath: url,
            fileName: url.lastPathComponent,
            bookmarkData: bookmarkData,
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

