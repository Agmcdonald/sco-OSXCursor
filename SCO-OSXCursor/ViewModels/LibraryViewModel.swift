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
    private let progressTracker = ReadingProgressTracker.shared
    private let database = DatabaseManager.shared
    
    init() {
        // Start with empty library
        self.comics = []
        
        // Load comics from database and bundled test comics
        loadComicsFromDatabase()
    }
    
    // MARK: - Load from Database
    private func loadComicsFromDatabase() {
        Task {
            do {
                // Load all comics from database
                let dbComics = try await database.fetchAllComics()
                
                await MainActor.run {
                    self.comics = dbComics
                    print("[LibraryViewModel] 📚 Loaded \(dbComics.count) comics from database")
                }
                
                // Load bundled test comics
                await loadBundledTestComic()
                
                // Restore reading progress after all comics are loaded
                await MainActor.run {
                    restoreReadingProgress()
                }
                
            } catch {
                print("[LibraryViewModel] ⚠️ Failed to load from database: \(error)")
                
                // Fallback: load bundled comics
                await loadBundledTestComic()
                await MainActor.run {
                    restoreReadingProgress()
                }
            }
        }
    }
    
    // MARK: - Restore Progress
    private func restoreReadingProgress() {
        let allProgress = progressTracker.loadAllProgress()
        
        guard !allProgress.isEmpty else {
            print("[LibraryViewModel] No saved progress to restore")
            return
        }
        
        print("[LibraryViewModel] 📖 Restoring progress for \(allProgress.count) comics")
        
        // Force UI update
        objectWillChange.send()
        
        // Update comics with saved progress
        for index in comics.indices {
            if let progress = allProgress[comics[index].id] {
                comics[index].currentPage = progress.currentPage
                comics[index].status = progress.status
                comics[index].lastReadDate = progress.lastReadDate
                print("[LibraryViewModel] ✅ Restored \(comics[index].fileName): Page \(progress.currentPage + 1), Status: \(progress.status.rawValue)")
            }
        }
    }
    
    // MARK: - Load Bundled Test Comics
    private func loadBundledTestComic() async {
        // List of bundled test comics
        let testFiles = [
            ("Billy_Bunny_01", "cbz"),
            ("theprivateeye_01enr00", "pdf")
        ]
        
        for (name, ext) in testFiles {
            if let bundleURL = Bundle.main.url(forResource: name, withExtension: ext) {
                do {
                    let testComic = try await importComic(from: bundleURL)
                    
                    // Check if already in database
                    let exists = try await database.comicExists(withID: testComic.id)
                    
                    if !exists {
                        // Save to database
                        try await database.saveComic(testComic)
                        
                        await MainActor.run {
                            // Add to array if not already present
                            if !comics.contains(where: { $0.id == testComic.id }) {
                                comics.insert(testComic, at: 0)
                            }
                        }
                        
                        print("📦 Loaded and saved bundled test comic: \(name).\(ext)")
                    } else {
                        print("📦 Bundled test comic already in database: \(name).\(ext)")
                    }
                } catch {
                    print("⚠️ Failed to load bundled test comic \(name).\(ext): \(error)")
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
        
        // Save to database and add to comics array
        if !newComics.isEmpty {
            // Save to database
            for comic in newComics {
                do {
                    try await database.saveComic(comic)
                } catch {
                    print("⚠️ Failed to save comic to database: \(comic.fileName)")
                }
            }
            
            comics.append(contentsOf: newComics)
            print("Successfully imported \(newComics.count) comics")
            
            // Restore any saved progress for newly imported comics
            syncProgressFromTracker()
        }
        
        isImporting = false
        importProgress = 0.0
    }
    
    // MARK: - Import Single Comic
    private func importComic(from url: URL) async throws -> Comic {
        // Determine if this is a bundled resource
        let isBundled = url.path.contains(Bundle.main.bundlePath)
        
        // For bundled resources, create deterministic ID from filename
        // This ensures same comic has same ID across app restarts
        let comicID: UUID
        if isBundled {
            // Create truly deterministic UUID from filename
            // Using simple character code sum (not Swift's hashValue which is randomized)
            let filename = url.lastPathComponent
            
            var hash: UInt32 = 0
            for char in filename.unicodeScalars {
                hash = hash &* 31 &+ UInt32(char.value)
            }
            
            // Convert to UUID string (deterministic)
            let uuidString = String(format: "%08x-0000-0000-0000-%012x", 
                                   hash, 
                                   UInt64(filename.count))
            comicID = UUID(uuidString: uuidString) ?? UUID()
            print("📦 Using deterministic ID for bundled comic '\(filename)': \(comicID)")
        } else {
            comicID = UUID()
        }
        
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
        
        // Extract metadata from the file
        print("[LibraryViewModel] 📖 Extracting metadata from \(url.lastPathComponent)...")
        let comicBook = try await reader.loadComic(from: url)
        let extractedMetadata = comicBook.metadata
        
        // Parse metadata from filename as fallback
        let filenameMetadata = MetadataParser.parseFromFilename(url.lastPathComponent)
        
        // Merge metadata (file metadata takes priority over filename)
        var mergedMetadata = MetadataParser.merge(
            comicInfo: extractedMetadata,
            pdf: nil,  // PDF metadata already in extractedMetadata
            filename: filenameMetadata
        )
        
        // Enhance publisher detection and normalization
        if let extractedPublisher = PublisherDetector.extract(from: mergedMetadata) {
            mergedMetadata.publisher = extractedPublisher
            print("[LibraryViewModel] 🔍 Detected publisher: \(extractedPublisher)")
        } else if let rawPublisher = mergedMetadata.publisher {
            // Normalize existing publisher
            mergedMetadata.publisher = PublisherDetector.normalize(rawPublisher)
        }
        
        print("[LibraryViewModel] ✅ Metadata extracted:")
        print("   Title: \(mergedMetadata.title ?? "none")")
        print("   Series: \(mergedMetadata.series ?? "none")")
        print("   Issue: \(mergedMetadata.number ?? "none")")
        print("   Publisher: \(mergedMetadata.publisher ?? "none")")
        print("   Year: \(mergedMetadata.year.map { String($0) } ?? "none")")
        print("   Writer: \(mergedMetadata.writer ?? "none")")
        
        // ALWAYS stop accessing after import - bookmark will restore access later
        if accessing {
            url.stopAccessingSecurityScopedResource()
            print("🔒 Stopped security access after import: \(url.lastPathComponent)")
        }
        
        // Create comic object with bookmark and extracted metadata
        let comic = Comic(
            id: comicID,  // Use deterministic ID for bundled comics
            filePath: url,
            fileName: url.lastPathComponent,
            bookmarkData: bookmarkData,
            title: mergedMetadata.title,
            publisher: mergedMetadata.publisher,
            series: mergedMetadata.series,
            issueNumber: mergedMetadata.number,
            volume: mergedMetadata.volume,
            year: mergedMetadata.year,
            writer: mergedMetadata.writer,
            artist: mergedMetadata.penciller,
            coverArtist: mergedMetadata.coverArtist,
            summary: mergedMetadata.summary,
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
        Task {
            // Delete from database
            for comic in comicsToDelete {
                do {
                    try await database.deleteComic(withID: comic.id)
                    print("[LibraryViewModel] 🗑️ Deleted from database: \(comic.fileName)")
                } catch {
                    print("[LibraryViewModel] ⚠️ Failed to delete from database: \(comic.fileName)")
                }
            }
            
            // Remove from array
            await MainActor.run {
                comics.removeAll { comic in
                    comicsToDelete.contains { $0.id == comic.id }
                }
            }
        }
    }
    
    // MARK: - Update Comic
    func updateComic(_ comic: Comic) {
        if let index = comics.firstIndex(where: { $0.id == comic.id }) {
            // Force SwiftUI to detect the change by triggering objectWillChange
            objectWillChange.send()
            
            comics[index] = comic
            
            // Update in database
            Task {
                do {
                    try await database.updateComic(comic)
                } catch {
                    print("[LibraryViewModel] ⚠️ Failed to update comic in database: \(error)")
                }
            }
            
            // Also update reading progress if the comic has been read
            if comic.currentPage > 0 {
                progressTracker.updatePage(
                    for: comic.id,
                    currentPage: comic.currentPage,
                    totalPages: comic.totalPages
                )
            }
            
            print("[LibraryViewModel] ✅ Updated comic '\(comic.fileName)': Page \(comic.currentPage + 1)/\(comic.totalPages), Status: \(comic.status.rawValue)")
        }
    }
    
    /// Sync progress from tracker to all comics (call after importing new comics)
    func syncProgressFromTracker() {
        let allProgress = progressTracker.loadAllProgress()
        
        // Force UI update
        objectWillChange.send()
        
        for index in comics.indices {
            if let progress = allProgress[comics[index].id] {
                comics[index].currentPage = progress.currentPage
                comics[index].status = progress.status
                comics[index].lastReadDate = progress.lastReadDate
                print("[LibraryViewModel] ✅ Synced progress for '\(comics[index].fileName)': Page \(progress.currentPage + 1)")
            }
        }
    }
}

