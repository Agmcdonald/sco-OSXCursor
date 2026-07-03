//
//  ReaderViewModel.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Combine
import Foundation
import SwiftUI
import os

#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Page Spread Model
struct PageSpread: Identifiable {
    let id: String
    let leftPage: ComicPage
    let rightPage: ComicPage?  // nil for single pages or last odd page
    let spreadIndex: Int

    var isSinglePage: Bool {
        rightPage == nil
    }
}

// MARK: - Reader ViewModel
@MainActor
class ReaderViewModel: ObservableObject {
    @Published var comicBook: ComicBook?
    @Published var currentPage: Int = 0
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var loadedPages: [Int: ComicPage] = [:]  // For lazy-loaded pages - published to update UI
    @Published var isBackgroundLoading: Bool = false  // True while the CURRENT page is still loading
    /// Aspect ratios (height/width) of pages we've seen, kept across eviction.
    /// Stabilizes vertical-scroll layout and spread pairing for unloaded pages.
    @Published private(set) var pageAspects: [Int: CGFloat] = [:]
    /// Bumped whenever a new filmstrip/grid thumbnail becomes available.
    @Published private(set) var thumbnailVersion: Int = 0
    private var thumbnailRequestsInFlight: Set<Int> = []
    @Published var isSpreadMode: Bool = false  // Two-page spread view
    @Published var readingStyle: ReadingStyle = .standard  // Current effective reading style
    @Published private(set) var isAnimatingTurn: Bool = false
    @Published private(set) var lastInteractionAt: Date = .distantPast

    // MARK: Next Issue Suggestion
    /// True while the end-of-book "Up Next" preview is showing. Set when the
    /// user tries to turn forward past the last page (and a next book exists);
    /// a second forward turn requests advancing into that book.
    @Published var showNextIssuePreview: Bool = false
    /// One-shot signal: the user advanced "into" the suggested next book.
    /// ComicReaderView observes this and swaps the reading comic.
    @Published var advanceToNextIssueRequested: Bool = false
    /// Set by ComicReaderView once the next book (per library sort order) is
    /// known. When false, forward turns past the end stay inert as before.
    var hasNextIssue: Bool = false

    // Computed style helpers
    var isVerticalScroll: Bool { readingStyle == .verticalScroll }
    var isMangaRTL: Bool { readingStyle == .mangaRTL }

    private let cbzReader = CBZReader()
    private let pdfReader = PDFReader()
    private let cbrReader = CBRReader()
    private var resolvedURL: URL?
    private var currentComic: Comic?  // Keep reference for lazy loading
    private var isLazyLoaded = false  // Track if current comic uses lazy loading
    private var backgroundLoadTask: Task<Void, Never>?  // Background loading task
    private let progressTracker = ReadingProgressTracker.shared
    private var lastTurnAt: Date = .distantPast
    private let turnCooldown: TimeInterval = 0.18

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

    // MARK: - Notifications
    static let bookmarkRefreshedNotification = Notification.Name("ReaderViewModelBookmarkRefreshed")

    // MARK: - Prefetch Window Tuning
    /// Pages loaded ahead of the current page (reading direction)
    private let prefetchAhead = 6
    /// Pages kept loaded behind the current page
    private let prefetchBehind = 2
    /// Pages retained in memory on either side of the current page before eviction
    private let retainRadius = 12

    init() {
        // Observe page changes and save progress
        $currentPage
            .dropFirst()  // Skip initial value
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)  // Wait 0.5s after page change
            .sink { [weak self] newPage in
                self?.saveCurrentProgress()
            }
            .store(in: &cancellables)

        // Keep a window of pages loaded around the reading position
        $currentPage
            .removeDuplicates()
            .sink { [weak self] newPage in
                self?.schedulePrefetch(around: newPage)
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
        AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] [\(timestamp)] [ReaderViewModel] resolveFileURL() ENTRY")
        AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Comic: \(comic.fileName)")
        AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] FilePath: \(comic.resolvedURL.path)")
        AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Has bookmark: \(comic.bookmarkData != nil)")

        // Use Comic helper for clean detection
        let isBundled = Comic.isBundled(comic)
        #if DEBUG
            AppLog.reader.debug("[Reader][Attempt #\(currentAttempt)] Is bundled: \(isBundled)")
        #endif

        if isBundled {
            let fileName = comic.fileName
            let fileExtension = comic.fileType.rawValue

            // Extract base name safely using NSString (handles multiple periods correctly)
            let baseName = (fileName as NSString).deletingPathExtension

            // Try to find the file in the bundle
            if let bundleURL = Bundle.main.url(forResource: baseName, withExtension: fileExtension)
            {
                #if DEBUG
                    AppLog.reader.debug("[Reader][Attempt #\(currentAttempt)] 📦 Re-resolved: \(fileName)")
                    AppLog.reader.debug("[Reader][Attempt #\(currentAttempt)] Bundle URL: \(bundleURL.path)")
                #endif

                // Validate the file actually exists (catches Xcode bundle-copy bugs)
                if FileManager.default.fileExists(atPath: bundleURL.path) {
                    return bundleURL
                } else {
                    AppLog.reader.error("[Reader][Attempt #\(currentAttempt)] ⚠️ Bundle URL exists but file missing: \(bundleURL.path)")
                    throw ComicReaderError.fileNotFound
                }
            } else {
                AppLog.reader.error("[Reader][Attempt #\(currentAttempt)] ⚠️ Could not locate bundled comic \(fileName).")
                AppLog.reader.error("[Reader] ⚠️ Falling back to user documents – likely stale reference or missing asset.")
                throw ComicReaderError.fileNotFound
            }
        }

        #if os(macOS)
            // On macOS, try to resolve security bookmark if available
            if let bookmarkData = comic.bookmarkData {
                AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Attempting to resolve bookmark (\(bookmarkData.count) bytes)")
                var isStale = false
                do {
                    let resolvedURL = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )

                    AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Bookmark resolved. Is stale: \(isStale)")

                    if isStale {
                        AppLog.reader.error("[ATTEMPT #\(currentAttempt)] ⚠️ Bookmark is stale for: \(comic.fileName) — attempting refresh")
                        // Try to access the URL and issue a fresh bookmark
                        return try refreshAndReturnURL(staleURL: resolvedURL, comic: comic)
                    }

                    // Start accessing the security-scoped resource
                    AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Attempting to start security-scoped access...")
                    guard resolvedURL.startAccessingSecurityScopedResource() else {
                        AppLog.reader.error("[ATTEMPT #\(currentAttempt)] ❌ Failed to start accessing security-scoped resource for: \(comic.fileName)")
                        throw ComicReaderError.accessDenied
                    }

                    AppLog.reader.info("[ATTEMPT #\(currentAttempt)] ✅ Resolved bookmark and started access for: \(comic.fileName)")
                    return resolvedURL
                } catch let err as ComicReaderError {
                    throw err
                } catch {
                    AppLog.reader.error("[ATTEMPT #\(currentAttempt)] ⚠️ Failed to resolve bookmark for \(comic.fileName): \(error)")
                    AppLog.reader.debug("[ATTEMPT #\(currentAttempt)]    Attempting fallback to raw URL")
                    return try refreshAndReturnURL(staleURL: comic.resolvedURL, comic: comic)
                }
            } else {
                AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] No bookmark data — attempting to create one")
                return try refreshAndReturnURL(staleURL: comic.resolvedURL, comic: comic)
            }
        #else
            // iOS / iPadOS: resolve bookmark and start security-scoped access
            if let bookmarkData = comic.bookmarkData {
                AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] [iOS] Attempting to resolve bookmark (\(bookmarkData.count) bytes)")
                var isStale = false
                do {
                    let resolvedURL = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withoutUI,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] [iOS] Bookmark resolved. Is stale: \(isStale)")

                    let started = resolvedURL.startAccessingSecurityScopedResource()
                    AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] [iOS] Security access started: \(started)")
                    if started {
                        cleanupURL = resolvedURL
                    }

                    if isStale {
                        // Refresh bookmark and notify LibraryViewModel to persist it
                        if let freshBookmark = try? resolvedURL.bookmarkData(
                            options: .minimalBookmark,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil)
                        {
                            NotificationCenter.default.post(
                                name: Self.bookmarkRefreshedNotification,
                                object: nil,
                                userInfo: ["comicID": comic.id, "bookmarkData": freshBookmark]
                            )
                        }
                    }

                    return resolvedURL
                } catch {
                    AppLog.reader.error("[ATTEMPT #\(currentAttempt)] [iOS] Failed to resolve bookmark: \(error). Falling back to raw URL.")
                }
            }

            // iOS fallback: raw URL (works for bundled files; handled above for non-bundled)
            AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] [iOS] Using original URL (no bookmark / fallback)")
            return comic.resolvedURL
        #endif
    }

    /// Attempts to access `staleURL`, creates a fresh security-scoped bookmark,
    /// notifies LibraryViewModel to persist it, and starts access.
    #if os(macOS)
        private func refreshAndReturnURL(staleURL: URL, comic: Comic) throws -> URL {
            // Check the file is reachable at all
            guard FileManager.default.fileExists(atPath: staleURL.path) else {
                AppLog.reader.error("[ATTEMPT #\(currentAttempt)] ❌ File not accessible at \(staleURL.path) — throwing accessDenied")
                throw ComicReaderError.accessDenied
            }

            // Try to create a fresh bookmark
            do {
                let freshBookmark = try staleURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                AppLog.reader.info("[ATTEMPT #\(currentAttempt)] ✅ Created fresh bookmark (\(freshBookmark.count) bytes)")

                // Notify LibraryViewModel to persist the refreshed bookmark
                NotificationCenter.default.post(
                    name: Self.bookmarkRefreshedNotification,
                    object: nil,
                    userInfo: ["comicID": comic.id, "bookmarkData": freshBookmark]
                )

                // Start access using the stale URL (which still points to the right file)
                guard staleURL.startAccessingSecurityScopedResource() else {
                    throw ComicReaderError.accessDenied
                }
                cleanupURL = staleURL
                return staleURL
            } catch let err as ComicReaderError {
                throw err
            } catch {
                AppLog.reader.error("[ATTEMPT #\(currentAttempt)] ⚠️ Could not create fresh bookmark: \(error). Trying raw access.")
                // Final fallback: use the URL as-is (may work for iCloud Drive files)
                guard staleURL.startAccessingSecurityScopedResource() else {
                    throw ComicReaderError.accessDenied
                }
                return staleURL
            }
        }
    #endif

    // Placeholder close brace removed — resolveFileURL ends before this.

    // MARK: - Load Comic (Fast - metadata only)
    func loadComic(from comic: Comic) async {
        // Increment attempt counter
        Self.attemptCounter += 1
        currentAttempt = Self.attemptCounter

        let startTime = Date().timeIntervalSince1970
        AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] [\(startTime)] [ReaderViewModel] loadComic() ENTRY")
        AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Comic: \(comic.fileName)")
        AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] File type: \(comic.fileType.rawValue)")

        isLoading = true
        errorMessage = nil
        loadingProgress = 0.0

        do {
            // Resolve the file URL from bookmark (critical for security access!)
            AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] [\(Date().timeIntervalSince1970)] Calling resolveFileURL()...")
            let fileURL = try resolveFileURL(from: comic)
            AppLog.reader.info("[ATTEMPT #\(currentAttempt)] [\(Date().timeIntervalSince1970)] resolveFileURL() SUCCESS")
            AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Resolved URL: \(fileURL.path)")
            resolvedURL = fileURL

            let reader: ComicReaderProtocol

            // Select appropriate reader based on file type
            AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Selecting reader for type: \(comic.fileType.rawValue)")
            switch comic.fileType {
            case .cbz:
                reader = cbzReader
                AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Using CBZReader")
            case .pdf:
                reader = pdfReader
                AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Using PDFReader")
            case .cbr:
                reader = cbrReader
                AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] Using CBRReader")
            case .epub:
                // EPUBs are handled by EPUBContentView, not ReaderViewModel
                AppLog.reader.error("[ATTEMPT #\(currentAttempt)] ⚠️ EPUB reached ReaderViewModel — not supported")
                throw ComicReaderError.invalidFormat
            }

            // Open the book — readers extract only the first few pages eagerly,
            // so this returns quickly even for very large archives.
            loadingProgress = 0.2
            let fullComic = try await reader.loadComic(from: fileURL)
            #if DEBUG
                AppLog.reader.info("[ATTEMPT #\(currentAttempt)] reader.loadComic() SUCCESS — \(fullComic.totalPages) pages")
            #endif

            loadingProgress = 1.0

            // Update UI
            comicBook = fullComic
            isLazyLoaded = fullComic.isLazyLoaded
            currentComic = comic

            // Apply effective reading style for this book
            readingStyle = ReaderSettings.shared.effectiveReadingStyle(for: comic)
            // Vertical scroll mode is inherently single-page display
            if readingStyle == .verticalScroll {
                isSpreadMode = false
            }

            // Store for cleanup (deinit can't access MainActor properties)
            cleanupURL = fileURL
            cleanupComicID = comic.id
            cleanupTotalPages = fullComic.totalPages

            // For lazy-loaded comics, populate initial pages
            if fullComic.isLazyLoaded {
                for page in fullComic.pages {
                    loadedPages[page.pageNumber - 1] = page
                    recordPageMetadata(page, at: page.pageNumber - 1)
                }
            }

            // Start from saved progress or beginning
            if let savedProgress = progressTracker.loadProgress(for: comic.id) {
                currentPage = savedProgress.currentPage
            } else {
                currentPage = comic.currentPage
            }

            // Begin loading the window of pages around the reading position
            schedulePrefetch(around: currentPage)

            let endTime = Date().timeIntervalSince1970
            AppLog.reader.info("[ATTEMPT #\(currentAttempt)] [\(endTime)] ✅ loadComic() SUCCESS - Total time: \(String(format: "%.3f", endTime - startTime))s")

        } catch let error as ComicReaderError {
            AppLog.reader.error("[ATTEMPT #\(currentAttempt)] ❌ ComicReaderError: \(error.errorDescription ?? "Unknown")")
            errorMessage = error.errorDescription
        } catch {
            AppLog.reader.error("[ATTEMPT #\(currentAttempt)] ❌ Unexpected error: \(error.localizedDescription)")
            AppLog.reader.error("[ATTEMPT #\(currentAttempt)] Error type: \(type(of: error))")
            AppLog.reader.error("[ATTEMPT #\(currentAttempt)] Error details: \(error)")
            errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
        }

        isLoading = false
        loadingProgress = 0.0

        let endTime = Date().timeIntervalSince1970
        AppLog.reader.debug("[ATTEMPT #\(currentAttempt)] [\(endTime)] loadComic() EXIT - Total time: \(String(format: "%.3f", endTime - startTime))s")
    }

    // MARK: - Accept Pre-fetched Comic (iOS fast-path)

    /// Injects an already-loaded ComicBook directly, skipping the loading spinner entirely.
    /// Called by ComicReaderView when LibraryViewModel has a pre-fetched result ready.
    #if os(iOS)
        func acceptPrefetched(_ comicBook: ComicBook, for comic: Comic) {
            isLoading = false
            errorMessage = nil
            loadingProgress = 1.0

            self.comicBook = comicBook
            isLazyLoaded = comicBook.isLazyLoaded
            currentComic = comic
            cleanupComicID = comic.id
            cleanupTotalPages = comicBook.totalPages

            // Apply effective reading style
            readingStyle = ReaderSettings.shared.effectiveReadingStyle(for: comic)
            if readingStyle == .verticalScroll {
                isSpreadMode = false
            }

            // Populate lazy-loaded pages cache if needed
            if comicBook.isLazyLoaded {
                for page in comicBook.pages {
                    loadedPages[page.pageNumber - 1] = page
                    recordPageMetadata(page, at: page.pageNumber - 1)
                }
            }

            // Resolve our own security-scoped access for lazy page loads.
            // (LibraryViewModel's prefetch released its access when it finished,
            // so without this, on-demand page loads would fail for user files.)
            if let url = try? resolveFileURL(from: comic) {
                resolvedURL = url
                cleanupURL = url
            } else {
                resolvedURL = comicBook.sourceURL
            }

            // Restore saved progress
            if let savedProgress = progressTracker.loadProgress(for: comic.id) {
                currentPage = savedProgress.currentPage
            } else {
                currentPage = comic.currentPage
            }

            // Begin loading the window of pages around the reading position
            schedulePrefetch(around: currentPage)

            #if DEBUG
                AppLog.reader.debug("[ReaderViewModel] ⚡ Accepted pre-fetched comic — no spinner shown")
            #endif
        }
    #endif

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

        // Stop accessing security-scoped resource when done (using stored URL).
        // Applies to both macOS and iOS — each platform starts access in resolveFileURL.
        if let url = cleanupURL {
            url.stopAccessingSecurityScopedResource()
            AppLog.reader.debug("🧹 Released security access for: \(url.lastPathComponent)")
        }
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
        } else {
            requestForwardPastEnd()
        }
    }

    // MARK: - Next Issue Suggestion Handling

    /// Called whenever the user tries to read FORWARD while already on the
    /// last page. First attempt reveals the "Up Next" preview; a second one
    /// advances into the suggested book (like turning one more page).
    func requestForwardPastEnd() {
        guard hasNextIssue else { return }
        if showNextIssuePreview {
            advanceToNextIssueRequested = true
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                showNextIssuePreview = true
            }
        }
        lastInteractionAt = Date()
    }

    /// Hide the preview (backward turn, tap outside, Escape).
    func dismissNextIssuePreview() {
        guard showNextIssuePreview else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            showNextIssuePreview = false
        }
    }

    // MARK: - In-Place Book Switch (Next Issue)

    /// Reset all per-book state so another book can load into this SAME
    /// reader instance. Keeps the reader presented — swapping the library's
    /// readingComic instead would dismiss + re-present the fullScreenCover.
    private func tearDownCurrentBook() {
        // Persist progress for the outgoing book before clearing references
        saveCurrentProgress()

        backgroundLoadTask?.cancel()
        backgroundLoadTask = nil

        if let url = cleanupURL {
            url.stopAccessingSecurityScopedResource()
            AppLog.reader.debug("🧹 Released security access (book switch): \(url.lastPathComponent)")
        }
        cleanupURL = nil
        cleanupComicID = nil
        cleanupCurrentPage = 0
        cleanupTotalPages = 0

        resolvedURL = nil
        comicBook = nil
        currentComic = nil
        isLazyLoaded = false
        loadedPages.removeAll()
        pageAspects.removeAll()
        thumbnailRequestsInFlight.removeAll()
        errorMessage = nil
        currentPage = 0

        showNextIssuePreview = false
        advanceToNextIssueRequested = false
        hasNextIssue = false
    }

    /// Switch this reader to another book without tearing down the view.
    func switchToComic(_ comic: Comic) async {
        tearDownCurrentBook()
        await loadComic(from: comic)
    }

    #if os(iOS)
        /// Fast-path switch using an already pre-fetched ComicBook (no spinner).
        func switchToPrefetched(_ comicBook: ComicBook, for comic: Comic) {
            tearDownCurrentBook()
            acceptPrefetched(comicBook, for: comic)
        }
    #endif

    func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
        }
    }

    /// Centralized, debounced page turn.
    /// `steps`: +1 for next, -1 for previous (in spread mode, each logical step = 2 pages).
    /// In Manga/RTL mode the direction is inverted so "next" goes to a lower page number.
    func turn(by steps: Int) {
        guard steps != 0 else { return }
        guard let comic = comicBook else { return }
        // Note: background prefetching must NOT block page turns — unloaded
        // pages show a spinner and fill in via ensurePageLoaded.
        guard !isLoading else { return }
        guard !isAnimatingTurn else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTurnAt) > turnCooldown else { return }

        // In Manga/RTL mode, invert the step direction
        let effectiveSteps = isMangaRTL ? -steps : steps

        // While the "Up Next" preview is visible it owns page turns:
        // forward advances into the next book, backward dismisses it.
        if showNextIssuePreview {
            lastTurnAt = now
            lastInteractionAt = now
            if effectiveSteps > 0 {
                requestForwardPastEnd()
            } else {
                dismissNextIssuePreview()
            }
            return
        }

        // In spread mode the last spread can show TWO pages with currentPage
        // on its LEFT one: a plain forward turn would only move currentPage to
        // the right page of the same visible spread — nothing changes on
        // screen. Treat any forward turn starting on the last spread as
        // reaching past the end.
        if effectiveSteps > 0, isSpreadMode,
            let lastSpread = pageSpreads.last,
            currentPage >= lastSpread.leftPage.pageNumber - 1
        {
            lastTurnAt = now
            lastInteractionAt = now
            // Land on the true last page (same visible spread) so completion
            // tracking still fires, then surface the suggestion.
            if currentPage < comic.totalPages - 1 {
                currentPage = comic.totalPages - 1
            }
            requestForwardPastEnd()
            return
        }

        // In spread mode, each logical step equals 2 pages
        let pageDelta = isSpreadMode ? (effectiveSteps * 2) : effectiveSteps
        let totalPages = comic.totalPages
        let target = clamp(currentPage + pageDelta, lower: 0, upper: max(0, totalPages - 1))
        guard target != currentPage else {
            // Forward turn while already on the last page → suggest next issue
            if effectiveSteps > 0 && currentPage >= totalPages - 1 {
                lastTurnAt = now
                requestForwardPastEnd()
            }
            return
        }

        isAnimatingTurn = true
        lastTurnAt = now
        lastInteractionAt = now

        currentPage = target
        pageTurnHaptic()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(turnCooldown * 1_000_000_000))
            isAnimatingTurn = false
        }

        #if DEBUG
            AppLog.reader.debug("[ReaderViewModel] turn(by: \(steps)) -> page \(target) (spread:\(isSpreadMode), rtl:\(isMangaRTL))")
        #endif
    }
    
    /// Triggered by arrow keys during vertical scroll mode to do a half-page jump
    func verticalScrollHalf(forward: Bool) {
        NotificationCenter.default.post(
            name: NSNotification.Name("VerticalScrollHalfNotification"),
            object: nil,
            userInfo: ["forward": forward]
        )
    }

    // MARK: - Lazy Loading Support (Windowed Prefetch)
    //
    // Instead of loading every page of the book into memory in the background
    // (which cost hundreds of MB for large books and competed with foreground
    // page turns), we keep a sliding window of pages loaded around the current
    // reading position. Pages far outside the window are evicted; decoded
    // bitmaps are cached separately in PageImageCache (cost-capped, auto-purged
    // under memory pressure).

    /// Reader instance for a given file type
    private func reader(for fileType: Comic.FileType) -> ComicReaderProtocol {
        switch fileType {
        case .pdf: return pdfReader
        case .cbr: return cbrReader
        default: return cbzReader  // .cbz (.epub never reaches ReaderViewModel)
        }
    }

    /// Load the window of pages around `index` and evict pages far outside it.
    private func schedulePrefetch(around index: Int) {
        guard isLazyLoaded,
            let book = comicBook,
            let fileURL = resolvedURL,
            let comic = currentComic
        else { return }

        let total = book.totalPages
        guard total > 0 else { return }
        let center = max(0, min(index, total - 1))

        // Vertical scroll keeps a larger window — many pages are visible at
        // once and fast fling-scrolling outruns a small one.
        let ahead = isVerticalScroll ? 10 : prefetchAhead
        let behind = isVerticalScroll ? 4 : prefetchBehind
        let retain = isVerticalScroll ? 24 : retainRadius

        // 1. Evict pages outside the retain window.
        //    (allPages falls back to the book's eager initial pages for low
        //    indices, and PageImageCache keeps decoded bitmaps independently.)
        let keepLower = max(0, center - retain)
        let keepUpper = min(total - 1, center + retain)
        for key in loadedPages.keys where key < keepLower || key > keepUpper {
            loadedPages.removeValue(forKey: key)
        }

        // 2. Build the fetch list: current page first, then ahead, then behind.
        let aheadRange = (center...min(total - 1, center + ahead))
        let behindRange = stride(from: center - 1, through: max(0, center - behind), by: -1)
        var targets: [Int] = []
        for i in aheadRange where loadedPages[i] == nil { targets.append(i) }
        for i in behindRange where loadedPages[i] == nil { targets.append(i) }

        guard !targets.isEmpty else { return }

        // 3. Replace any in-flight prefetch with one for the new window.
        //    The "Loading pages..." indicator only shows when the page the
        //    user is LOOKING AT is missing — silent prefetch otherwise.
        backgroundLoadTask?.cancel()
        if loadedPages[center] == nil {
            isBackgroundLoading = true
        }
        let fileType = comic.fileType

        backgroundLoadTask = Task { [weak self] in
            for pageIndex in targets {
                guard !Task.isCancelled else { return }
                await self?.loadPageIfNeeded(pageIndex, fileURL: fileURL, fileType: fileType)
            }
            await MainActor.run { [weak self] in
                self?.isBackgroundLoading = false
            }
        }
    }

    /// Load a single page into the window cache (no-op if already present),
    /// then warm its decoded bitmap off the main thread.
    private func loadPageIfNeeded(_ pageIndex: Int, fileURL: URL, fileType: Comic.FileType) async {
        guard loadedPages[pageIndex] == nil else { return }

        do {
            let page = try await reader(for: fileType).loadPage(at: pageIndex, from: fileURL)
            guard !Task.isCancelled else { return }
            loadedPages[pageIndex] = page
            recordPageMetadata(page, at: pageIndex)

            // The page the user is looking at just arrived — drop the indicator
            if pageIndex == currentPage {
                isBackgroundLoading = false
            }

            // Pre-decode off-main so the first render of this page is instant,
            // and bank a filmstrip thumbnail while we still have the bytes.
            let bookPath = fileURL.path
            Task.detached(priority: .utility) { [weak self] in
                PageImageCache.shared.warm(page)
                guard
                    PageImageCache.shared.cachedThumbnail(
                        bookPath: bookPath, pageIndex: pageIndex) == nil,
                    let thumb = PageImageCache.shared.makeThumbnail(from: page.imageData)
                else { return }
                PageImageCache.shared.storeThumbnail(
                    thumb, bookPath: bookPath, pageIndex: pageIndex)
                // Bind strongly before crossing into the MainActor closure
                guard let self else { return }
                await MainActor.run { self.thumbnailVersion += 1 }
            }
        } catch {
            #if DEBUG
                AppLog.reader.error("[ReaderViewModel] ⚠️ Prefetch failed for page \(pageIndex + 1): \(error)")
            #endif
        }
    }

    /// Remember lightweight page facts (aspect ratio) that survive eviction.
    private func recordPageMetadata(_ page: ComicPage, at pageIndex: Int) {
        guard pageAspects[pageIndex] == nil,
            let size = page.pixelSize, size.width > 0
        else { return }
        pageAspects[pageIndex] = size.height / size.width
    }

    // MARK: - Filmstrip / Grid Thumbnails (demand-loaded)
    //
    // Thumbnails are independent of the reading window: any page's thumbnail
    // can be requested (e.g. by a visible filmstrip cell), is generated once
    // from the archive in the background, and stays cached after the page's
    // raw data is evicted.

    /// Cached thumbnail for a page, if one has been generated.
    func cachedThumbnail(at pageIndex: Int) -> PlatformImage? {
        guard let url = resolvedURL else { return nil }
        return PageImageCache.shared.cachedThumbnail(bookPath: url.path, pageIndex: pageIndex)
    }

    /// Request thumbnail generation for a page (no-op if cached or in flight).
    func requestThumbnail(at pageIndex: Int) {
        guard let url = resolvedURL, let comic = currentComic, isLazyLoaded else { return }
        guard !thumbnailRequestsInFlight.contains(pageIndex) else { return }
        guard PageImageCache.shared.cachedThumbnail(bookPath: url.path, pageIndex: pageIndex) == nil
        else { return }

        thumbnailRequestsInFlight.insert(pageIndex)
        let fileType = comic.fileType
        let bookPath = url.path

        Task { [weak self] in
            // Fast path: a thumbnail persisted from a previous session (or
            // evicted from memory) reloads from disk without re-extracting the
            // page from the archive. `diskThumbnail` promotes it back into the
            // in-memory grid cache, so the next render picks it up.
            let onDisk = await Task.detached(priority: .utility) {
                PageImageCache.shared.diskThumbnail(bookPath: bookPath, pageIndex: pageIndex)
            }.value
            if onDisk != nil {
                await MainActor.run {
                    self?.thumbnailRequestsInFlight.remove(pageIndex)
                    self?.thumbnailVersion += 1
                }
                return
            }

            // If the page data is already in the window, use it; otherwise
            // extract just this page from the archive.
            var data: Data? = await MainActor.run { self?.loadedPages[pageIndex]?.imageData }
            if data == nil || data?.isEmpty == true {
                data = try? await self?.reader(for: fileType)
                    .loadPage(at: pageIndex, from: url).imageData
            }

            if let data, !data.isEmpty {
                let thumb = await Task.detached(priority: .utility) {
                    PageImageCache.shared.makeThumbnail(from: data)
                }.value
                if let thumb {
                    PageImageCache.shared.storeThumbnail(
                        thumb, bookPath: bookPath, pageIndex: pageIndex)
                }
            }

            await MainActor.run {
                self?.thumbnailRequestsInFlight.remove(pageIndex)
                self?.thumbnailVersion += 1
            }
        }
    }

    /// Called when page changes (via swipe or button)
    func onPageChanged(to pageIndex: Int) async {
        guard isLazyLoaded else { return }

        // If page isn't loaded yet, fetch it immediately (the prefetch window
        // normally stays ahead of the reader, so this is a rare fallback)
        if loadedPages[pageIndex] == nil {
            await ensurePageLoaded(pageIndex)
        }
    }

    private func ensurePageLoaded(_ pageIndex: Int) async {
        guard loadedPages[pageIndex] == nil else { return }

        guard let comic = currentComic,
            let fileURL = resolvedURL
        else {
            #if DEBUG
                AppLog.reader.error("[ReaderViewModel] ⚠️ Missing comic or URL for lazy loading")
            #endif
            return
        }

        await loadPageIfNeeded(pageIndex, fileURL: fileURL, fileType: comic.fileType)
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

    /// Page spreads for two-page view mode
    var pageSpreads: [PageSpread] {
        let pages = allPages
        guard !pages.isEmpty else { return [] }

        var spreads: [PageSpread] = []

        // First page (cover) is always alone
        if isWidePageAtIndex(0, in: pages) {
            // Wide cover - show alone
            spreads.append(
                PageSpread(id: "spread-0", leftPage: pages[0], rightPage: nil, spreadIndex: 0))
        } else {
            spreads.append(
                PageSpread(id: "spread-0", leftPage: pages[0], rightPage: nil, spreadIndex: 0))
        }

        // Pair remaining pages
        var currentIndex = 1
        var spreadIndex = 1
        while currentIndex < pages.count {
            let leftPage = pages[currentIndex]

            // Check if this is a wide page (double-page spread in the comic itself)
            if isWidePageAtIndex(currentIndex, in: pages) {
                // Wide page - show alone
                spreads.append(
                    PageSpread(
                        id: "spread-\(spreadIndex)", leftPage: leftPage, rightPage: nil,
                        spreadIndex: spreadIndex))
                currentIndex += 1
            } else {
                // Normal page - pair with next page if available
                let rightPage = (currentIndex + 1 < pages.count) ? pages[currentIndex + 1] : nil
                spreads.append(
                    PageSpread(
                        id: "spread-\(spreadIndex)", leftPage: leftPage, rightPage: rightPage,
                        spreadIndex: spreadIndex))
                currentIndex += rightPage != nil ? 2 : 1
            }

            spreadIndex += 1
        }

        return spreads
    }

    /// Check if a page is wide (likely a double-page spread).
    /// Uses remembered aspect ratios (stable across page-data eviction) so
    /// spread pairing doesn't shift as pages load and unload; falls back to a
    /// header-only pixel-size read for pages we haven't recorded yet.
    private func isWidePageAtIndex(_ index: Int, in pages: [ComicPage]) -> Bool {
        guard index < pages.count else { return false }

        if let aspect = pageAspects[index] {
            // aspect = height/width; wide spread when width/height > 1.5
            return aspect > 0 && (1.0 / aspect) > 1.5
        }

        guard let size = pages[index].pixelSize, size.height > 0 else { return false }
        return (size.width / size.height) > 1.5
    }

    private func createPlaceholderPage(pageNumber: Int) -> ComicPage {
        // Create a simple placeholder image
        let placeholderData = Data()  // Empty for now
        return ComicPage(
            pageNumber: pageNumber, imageData: placeholderData, fileName: "Page \(pageNumber)")
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

// MARK: - Helper Functions
extension ReaderViewModel {
    private func clamp<T: Comparable>(_ x: T, lower: T, upper: T) -> T {
        min(max(x, lower), upper)
    }

    private func pageTurnHaptic() {
        #if os(iOS)
            #if DEBUG
                AppLog.reader.debug("🔊 [Haptic] Firing haptic feedback")
            #endif
            let g = UIImpactFeedbackGenerator(style: .light)
            g.prepare()
            g.impactOccurred()
        #else
            #if DEBUG
                AppLog.reader.error("⚠️ [Haptic] Skipped (not iOS)")
            #endif
        #endif
    }
}
