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
    @Published var loadedPages: [Int: ComicPage] = [:]  // For lazy-loaded pages - published to update UI
    @Published var isBackgroundLoading: Bool = false  // True while pages load in background
    
    private let cbzReader = CBZReader()
    private let pdfReader = PDFReader()
    private var resolvedURL: URL?
    private var currentComic: Comic?  // Keep reference for lazy loading
    private var isLazyLoaded = false  // Track if current comic uses lazy loading
    private var backgroundLoadTask: Task<Void, Never>?  // Background loading task
    private let progressTracker = ReadingProgressTracker.shared
    
    // Store values for cleanup (non-MainActor isolated)
    private var cleanupURL: URL?
    private var cleanupComicID: UUID?
    private var cleanupCurrentPage: Int = 0
    private var cleanupTotalPages: Int = 0
    
    // Diagnostic logging
    private static var attemptCounter = 0
    private var currentAttempt = 0
    
    // Page change observation for progress tracking
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Observe page changes and save progress
        $currentPage
            .dropFirst() // Skip initial value
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main) // Wait 0.5s after page change
            .sink { [weak self] newPage in
                self?.saveCurrentProgress()
            }
            .store(in: &cancellables)
    }
    
    /// Save current reading progress
    private func saveCurrentProgress() {
        guard let comic = currentComic, let comicBook = comicBook else { return }
        
        progressTracker.updatePage(
            for: comic.id,
            currentPage: currentPage,
            totalPages: comicBook.totalPages
        )
        
        // Also store for cleanup
        cleanupCurrentPage = currentPage
    }
    
    // MARK: - Resolve Bookmark
    private func resolveFileURL(from comic: Comic) throws -> URL {
        let timestamp = Date().timeIntervalSince1970
        print("\n[ATTEMPT #\(currentAttempt)] [\(timestamp)] [ReaderViewModel] resolveFileURL() ENTRY")
        print("[ATTEMPT #\(currentAttempt)] Comic: \(comic.fileName)")
        print("[ATTEMPT #\(currentAttempt)] FilePath: \(comic.filePath.path)")
        print("[ATTEMPT #\(currentAttempt)] Has bookmark: \(comic.bookmarkData != nil)")
        
        // Use Comic helper for clean detection
        let isBundled = Comic.isBundled(comic)
        #if DEBUG
        print("[Reader][Attempt #\(currentAttempt)] Is bundled: \(isBundled)")
        #endif
        
        if isBundled {
            let fileName = comic.fileName
            let fileExtension = comic.fileType.rawValue
            
            // Extract base name safely using NSString (handles multiple periods correctly)
            let baseName = (fileName as NSString).deletingPathExtension
            
            // Try to find the file in the bundle
            if let bundleURL = Bundle.main.url(forResource: baseName, withExtension: fileExtension) {
                #if DEBUG
                print("[Reader][Attempt #\(currentAttempt)] 📦 Re-resolved: \(fileName)")
                print("[Reader][Attempt #\(currentAttempt)] Bundle URL: \(bundleURL.path)")
                #endif
                
                // Validate the file actually exists (catches Xcode bundle-copy bugs)
                if FileManager.default.fileExists(atPath: bundleURL.path) {
                    return bundleURL
                } else {
                    print("[Reader][Attempt #\(currentAttempt)] ⚠️ Bundle URL exists but file missing: \(bundleURL.path)")
                    throw ComicReaderError.fileNotFound
                }
            } else {
                print("[Reader][Attempt #\(currentAttempt)] ⚠️ Could not locate bundled comic \(fileName).")
                print("[Reader] ⚠️ Falling back to user documents – likely stale reference or missing asset.")
                throw ComicReaderError.fileNotFound
            }
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
            isLazyLoaded = fullComic.isLazyLoaded
            currentComic = comic
            
            // Store for cleanup (deinit can't access MainActor properties)
            cleanupURL = fileURL
            cleanupComicID = comic.id
            cleanupTotalPages = fullComic.totalPages
            
            // For lazy-loaded comics, populate initial pages
            if fullComic.isLazyLoaded {
                for page in fullComic.pages {
                    loadedPages[page.pageNumber - 1] = page
                }
                print("[ATTEMPT #\(currentAttempt)] Lazy-loaded comic: \(loadedPages.count) pages cached, \(fullComic.totalPages) total")
                
                // Start background loading of ALL remaining pages
                startBackgroundLoading(fileURL: fileURL, totalPages: fullComic.totalPages, fileType: comic.fileType)
            }
            
            // Start from saved progress or beginning
            if let savedProgress = progressTracker.loadProgress(for: comic.id) {
                currentPage = savedProgress.currentPage
                print("[ATTEMPT #\(currentAttempt)] 📖 Restored saved progress: Page \(savedProgress.currentPage + 1)")
            } else {
                currentPage = comic.currentPage
            }
            
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
        // Save reading progress before closing (using stored values, not MainActor properties)
        if let comicID = cleanupComicID, cleanupTotalPages > 0 {
            progressTracker.updatePage(
                for: comicID,
                currentPage: cleanupCurrentPage,
                totalPages: cleanupTotalPages
            )
        }
        
        // Cancel background loading task
        backgroundLoadTask?.cancel()
        
        // Stop accessing security-scoped resource when done (using stored URL)
        #if os(macOS)
        if let url = cleanupURL {
            url.stopAccessingSecurityScopedResource()
            print("🧹 Released security access for: \(url.lastPathComponent)")
        }
        #endif
    }
    
    // MARK: - Navigation
    func goToPage(_ page: Int) {
        guard let comic = comicBook else { return }
        let newPage = max(0, min(page, comic.totalPages - 1))
        currentPage = newPage
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
    
    // MARK: - Lazy Loading Support
    
    /// Start background loading of all remaining pages
    private func startBackgroundLoading(fileURL: URL, totalPages: Int, fileType: Comic.FileType) {
        print("[ReaderViewModel] 🚀 Starting background loading of remaining \(totalPages - loadedPages.count) pages")
        
        // Set loading state
        isBackgroundLoading = true
        
        // Cancel any existing task
        backgroundLoadTask?.cancel()
        
        // Start new background task
        backgroundLoadTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            // Load pages sequentially in background
            for pageIndex in 0..<totalPages {
                // Check if task was cancelled
                if Task.isCancelled {
                    print("[ReaderViewModel] ⚠️ Background loading cancelled")
                    return
                }
                
                // Skip if already loaded
                await MainActor.run {
                    if self.loadedPages[pageIndex] != nil {
                        return
                    }
                }
                
                // Load this page
                do {
                    let reader: ComicReaderProtocol = fileType == .pdf ? await self.pdfReader : await self.cbzReader
                    let page = try await reader.loadPage(at: pageIndex, from: fileURL)
                    
                    // Update on main actor
                    await MainActor.run {
                        self.loadedPages[pageIndex] = page
                        
                        // Log progress every 5 pages
                        if (pageIndex + 1) % 5 == 0 {
                            print("[ReaderViewModel] 📦 Background loaded \(self.loadedPages.count)/\(totalPages) pages")
                        }
                    }
                } catch {
                    print("[ReaderViewModel] ⚠️ Background load failed for page \(pageIndex + 1): \(error)")
                    // Continue with next page
                }
            }
            
            await MainActor.run {
                print("[ReaderViewModel] ✅ Background loading complete! All \(totalPages) pages loaded")
                self.isBackgroundLoading = false
            }
        }
    }
    
    /// Called when page changes (via swipe or button)
    func onPageChanged(to pageIndex: Int) async {
        print("[ReaderViewModel] 📄 onPageChanged to page \(pageIndex + 1)")
        guard isLazyLoaded else { return }
        
        // If page isn't loaded yet, wait for it (shouldn't happen often with background loading)
        if loadedPages[pageIndex] == nil {
            print("[ReaderViewModel] ⏳ Waiting for page \(pageIndex + 1) to load...")
            await ensurePageLoaded(pageIndex)
        }
    }
    
    private func ensurePageLoaded(_ pageIndex: Int) async {
        print("[ReaderViewModel] 🔍 ensurePageLoaded(\(pageIndex + 1)) called")
        
        // Check if page is already loaded
        guard loadedPages[pageIndex] == nil else {
            print("[ReaderViewModel] Page \(pageIndex + 1) already loaded")
            return
        }
        
        guard let comic = currentComic,
              let fileURL = resolvedURL else {
            print("[ReaderViewModel] ⚠️ Missing comic or URL for lazy loading")
            return
        }
        
        print("[ReaderViewModel] Loading page \(pageIndex + 1) in background...")
        
        do {
            let reader: ComicReaderProtocol = comic.fileType == .pdf ? pdfReader : cbzReader
            let page = try await reader.loadPage(at: pageIndex, from: fileURL)
            loadedPages[pageIndex] = page
            print("[ReaderViewModel] ✅ Page \(pageIndex + 1) loaded successfully")
        } catch {
            print("[ReaderViewModel] ❌ Failed to load page \(pageIndex + 1): \(error)")
        }
    }
    
    
    // MARK: - Page Access (for Lazy Loading)
    /// Get all pages, merging lazy-loaded pages from cache
    var allPages: [ComicPage] {
        guard let comic = comicBook else { return [] }
        
        if !isLazyLoaded {
            // Not lazy-loaded, return all pages directly
            return comic.pages
        }
        
        // For lazy-loaded comics, merge initial pages with loaded pages
        var result: [ComicPage] = []
        for pageIndex in 0..<comic.totalPages {
            if let loadedPage = loadedPages[pageIndex] {
                result.append(loadedPage)
            } else if pageIndex < comic.pages.count {
                // Use initial page if available
                result.append(comic.pages[pageIndex])
            } else {
                // Create placeholder for unloaded page
                result.append(createPlaceholderPage(pageNumber: pageIndex + 1))
            }
        }
        return result
    }
    
    private func createPlaceholderPage(pageNumber: Int) -> ComicPage {
        // Create a simple placeholder image
        let placeholderData = Data()  // Empty for now
        return ComicPage(pageNumber: pageNumber, imageData: placeholderData, fileName: "Page \(pageNumber)")
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

