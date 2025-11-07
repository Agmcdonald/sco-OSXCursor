//
//  ReaderViewModel.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Reader ViewModel
@MainActor
class ReaderViewModel: ObservableObject {
    @Published var comicBook: ComicBook?
    @Published var currentPage: Int = 0
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var errorMessage: String?
    
    private let cbzReader = CBZReader()
    private let pdfReader = PDFReader()
    private var loadedPages: [Int: ComicPage] = [:]
    private var resolvedURL: URL?
    
    // Diagnostic logging
    private static var attemptCounter = 0
    private var currentAttempt = 0
    
    // MARK: - Resolve Bookmark
    private func resolveFileURL(from comic: Comic) throws -> URL {
        let timestamp = Date().timeIntervalSince1970
        print("\n[ATTEMPT #\(currentAttempt)] [\(timestamp)] [ReaderViewModel] resolveFileURL() ENTRY")
        print("[ATTEMPT #\(currentAttempt)] Comic: \(comic.fileName)")
        print("[ATTEMPT #\(currentAttempt)] FilePath: \(comic.filePath.path)")
        print("[ATTEMPT #\(currentAttempt)] Has bookmark: \(comic.bookmarkData != nil)")
        
        // Check if this is a bundled resource
        let isBundled = comic.filePath.path.contains(Bundle.main.bundlePath)
        print("[ATTEMPT #\(currentAttempt)] Is bundled: \(isBundled)")
        
        if isBundled {
            // Bundled resources don't need security access - just use the URL
            print("[ATTEMPT #\(currentAttempt)] 📦 Using bundled resource directly: \(comic.fileName)")
            print("[ATTEMPT #\(currentAttempt)] File exists: \(FileManager.default.fileExists(atPath: comic.filePath.path))")
            return comic.filePath
        }
        
        #if os(macOS)
        // On macOS, try to resolve security bookmark if available
        if let bookmarkData = comic.bookmarkData {
            print("[ATTEMPT #\(currentAttempt)] Attempting to resolve bookmark (\(bookmarkData.count) bytes)")
            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                print("[ATTEMPT #\(currentAttempt)] Bookmark resolved. Is stale: \(isStale)")
                
                if isStale {
                    print("[ATTEMPT #\(currentAttempt)] ⚠️ Bookmark is stale for: \(comic.fileName)")
                    // TODO: In future, refresh the bookmark
                    // For now, try the original URL
                    return comic.filePath
                }
                
                // Start accessing the security-scoped resource
                print("[ATTEMPT #\(currentAttempt)] Attempting to start security-scoped access...")
                guard resolvedURL.startAccessingSecurityScopedResource() else {
                    print("[ATTEMPT #\(currentAttempt)] ❌ Failed to start accessing security-scoped resource for: \(comic.fileName)")
                    throw ComicReaderError.accessDenied
                }
                
                print("[ATTEMPT #\(currentAttempt)] ✅ Resolved bookmark and started access for: \(comic.fileName)")
                return resolvedURL
            } catch {
                print("[ATTEMPT #\(currentAttempt)] ⚠️ Failed to resolve bookmark for \(comic.fileName): \(error)")
                print("[ATTEMPT #\(currentAttempt)]    Error type: \(type(of: error))")
                print("[ATTEMPT #\(currentAttempt)]    Falling back to original URL")
                // Fall back to original URL
                return comic.filePath
            }
        } else {
            print("[ATTEMPT #\(currentAttempt)] No bookmark data available")
        }
        #endif
        
        // For iOS or files without bookmarks, just use the original URL
        print("[ATTEMPT #\(currentAttempt)] Using original URL (no bookmark)")
        return comic.filePath
    }
    
    // MARK: - Load Comic (Fast - metadata only)
    func loadComic(from comic: Comic) async {
        // Increment attempt counter
        Self.attemptCounter += 1
        currentAttempt = Self.attemptCounter
        
        let startTime = Date().timeIntervalSince1970
        print("\n" + String(repeating: "=", count: 80))
        print("[ATTEMPT #\(currentAttempt)] [\(startTime)] [ReaderViewModel] loadComic() ENTRY")
        print("[ATTEMPT #\(currentAttempt)] Comic: \(comic.fileName)")
        print("[ATTEMPT #\(currentAttempt)] File type: \(comic.fileType.rawValue)")
        print(String(repeating: "=", count: 80))
        
        isLoading = true
        errorMessage = nil
        loadingProgress = 0.0
        
        do {
            // Resolve the file URL from bookmark (critical for security access!)
            print("[ATTEMPT #\(currentAttempt)] [\(Date().timeIntervalSince1970)] Calling resolveFileURL()...")
            let fileURL = try resolveFileURL(from: comic)
            print("[ATTEMPT #\(currentAttempt)] [\(Date().timeIntervalSince1970)] resolveFileURL() SUCCESS")
            print("[ATTEMPT #\(currentAttempt)] Resolved URL: \(fileURL.path)")
            resolvedURL = fileURL
            
            let reader: ComicReaderProtocol
            
            // Select appropriate reader based on file type
            print("[ATTEMPT #\(currentAttempt)] Selecting reader for type: \(comic.fileType.rawValue)")
            switch comic.fileType {
            case .cbz:
                reader = cbzReader
                print("[ATTEMPT #\(currentAttempt)] Using CBZReader")
            case .pdf:
                reader = pdfReader
                print("[ATTEMPT #\(currentAttempt)] Using PDFReader")
            case .cbr:
                print("[ATTEMPT #\(currentAttempt)] ❌ CBR format not supported")
                // CBR not yet supported
                throw ComicReaderError.invalidFormat
            }
            
            // Quick load: Just get page count first
            print("[ATTEMPT #\(currentAttempt)] [\(Date().timeIntervalSince1970)] Calling getPageCount()...")
            loadingProgress = 0.1
            let pageCount = try await reader.getPageCount(from: fileURL)
            print("[ATTEMPT #\(currentAttempt)] [\(Date().timeIntervalSince1970)] getPageCount() SUCCESS: \(pageCount) pages")
            
            loadingProgress = 0.3
            
            // Load only the first page to show immediately
            print("[ATTEMPT #\(currentAttempt)] [\(Date().timeIntervalSince1970)] Calling reader.loadComic()...")
            let fullComic = try await reader.loadComic(from: fileURL)
            print("[ATTEMPT #\(currentAttempt)] [\(Date().timeIntervalSince1970)] reader.loadComic() SUCCESS")
            print("[ATTEMPT #\(currentAttempt)] Loaded \(fullComic.totalPages) pages")
            
            loadingProgress = 1.0
            
            // Update UI
            comicBook = fullComic
            
            // Start from saved progress or beginning
            currentPage = comic.currentPage
            
            let endTime = Date().timeIntervalSince1970
            print("[ATTEMPT #\(currentAttempt)] [\(endTime)] ✅ loadComic() SUCCESS - Total time: \(String(format: "%.3f", endTime - startTime))s")
            print(String(repeating: "=", count: 80) + "\n")
            
        } catch let error as ComicReaderError {
            print("[ATTEMPT #\(currentAttempt)] ❌ ComicReaderError: \(error.errorDescription ?? "Unknown")")
            errorMessage = error.errorDescription
        } catch {
            print("[ATTEMPT #\(currentAttempt)] ❌ Unexpected error: \(error.localizedDescription)")
            print("[ATTEMPT #\(currentAttempt)] Error type: \(type(of: error))")
            print("[ATTEMPT #\(currentAttempt)] Error details: \(error)")
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
        }
        
        isLoading = false
        loadingProgress = 0.0
        
        let endTime = Date().timeIntervalSince1970
        print("[ATTEMPT #\(currentAttempt)] [\(endTime)] loadComic() EXIT - Total time: \(String(format: "%.3f", endTime - startTime))s")
        print(String(repeating: "=", count: 80) + "\n")
    }
    
    // MARK: - Cleanup
    deinit {
        // Stop accessing security-scoped resource when done
        #if os(macOS)
        if let url = resolvedURL {
            url.stopAccessingSecurityScopedResource()
            print("[ATTEMPT #\(currentAttempt)] 🧹 Released security access for: \(url.lastPathComponent)")
        }
        #endif
    }
    
    // MARK: - Navigation
    func goToPage(_ page: Int) {
        guard let comic = comicBook else { return }
        currentPage = max(0, min(page, comic.totalPages - 1))
    }
    
    func nextPage() {
        guard let comic = comicBook else { return }
        if currentPage < comic.totalPages - 1 {
            currentPage += 1
        }
    }
    
    func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
        }
    }
    
    // MARK: - Progress
    var progress: Double {
        guard let comic = comicBook, comic.totalPages > 0 else { return 0.0 }
        return Double(currentPage + 1) / Double(comic.totalPages)
    }
    
    var progressPercentage: String {
        "\(Int(progress * 100))%"
    }
}

