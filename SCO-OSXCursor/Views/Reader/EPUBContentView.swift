//
//  EPUBContentView.swift
//  SCO-OSXCursor
//
//  Top-level container for the EPUB reader. Bridges LibraryViewModel progress
//  tracking (currentPage = chapter index, totalPages = chapter count) with the
//  EPUBReaderView. Persists font size changes back to the Comic record.
//

import SwiftUI

@MainActor
struct EPUBContentView: View {
    let initialComic: Comic
    @State private var localComic: Comic
    @State private var showSettings = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var libraryViewModel: LibraryViewModel

    // Chapter state (mirrors currentPage/totalPages in the Comic record)
    @State private var currentChapter: Int
    @State private var totalChapters: Int
    @State private var chapterProgress: Double
    @State private var lastPersistedChapter: Int
    @State private var lastPersistedProgress: Double
    @State private var fontSize: Int

    #if os(iOS)
        // Swipe-down-to-dismiss gesture state (parity with ComicReaderView)
        @State private var dragOffset: CGFloat = 0
        @State private var dismissDragActive = false
    #endif

    init(comic: Comic) {
        self.initialComic = comic
        _localComic = State(initialValue: comic)
        _currentChapter = State(initialValue: comic.currentPage)
        _totalChapters = State(initialValue: max(comic.totalPages, 1))
        _chapterProgress = State(initialValue: comic.epubChapterIndex == comic.currentPage ? (comic.epubChapterProgress ?? 0) : 0)
        _lastPersistedChapter = State(initialValue: comic.epubChapterIndex ?? comic.currentPage)
        _lastPersistedProgress = State(initialValue: comic.epubChapterProgress ?? 0)
        _fontSize = State(initialValue: comic.epubFontSize ?? 17)
    }

    var body: some View {
        EPUBReaderView(
            comic: localComic,
            currentChapter: $currentChapter,
            totalChapters: totalChapters,
            chapterProgress: $chapterProgress,
            fontSize: $fontSize,
            onClose: closeReader,
            onShowSettings: { showSettings = true },
            onCycleTheme: cycleTheme,
            onTogglePageMode: togglePageMode
        )
        #if os(iOS)
        // Swipe-down drag handle pill — fades in as the user pulls down
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .opacity(Double(min(dragOffset / 40.0, 1.0)))
                .allowsHitTesting(false)
        }
        .offset(y: max(0, dragOffset))
        .scaleEffect(dragOffset > 0 ? max(0.92, 1.0 - dragOffset / 1800.0) : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    // In vertical-scroll style the page itself scrolls
                    // vertically — only dismiss when the pull starts near
                    // the top edge (same rule as the comic reader).
                    // Books default to Page mode.
                    let style = ReadingStyle(rawValue: localComic.readingStyle ?? "") ?? .standard
                    if style == .verticalScroll {
                        guard value.startLocation.y < 120 else { return }
                    }
                    guard value.translation.height > 0,
                          value.translation.height > abs(value.translation.width) * 1.2
                    else { return }
                    dismissDragActive = true
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    guard dismissDragActive else { return }
                    dismissDragActive = false

                    let predictedEnd = value.predictedEndTranslation.height
                    let shouldDismiss = dragOffset > 130 || predictedEnd > 400

                    if shouldDismiss {
                        withAnimation(.easeIn(duration: 0.22)) {
                            dragOffset = 900
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            closeReader()
                            dragOffset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        #endif
        .sheet(isPresented: $showSettings) {
            InReaderSettingsView(
                comic: $localComic,
                isPresented: $showSettings,
                onComicUpdated: { updatedComic in
                    libraryViewModel.updateComic(updatedComic)
                }
            )
        }
        .onChange(of: currentChapter) { _, newChapter in
            persistProgress(chapter: newChapter, progress: chapterProgress, force: true)
        }
        .onChange(of: chapterProgress) { _, newProgress in
            persistProgress(chapter: currentChapter, progress: newProgress)
        }
        .onChange(of: fontSize) { _, newSize in
            persistFontSize(newSize)
        }
    }

    // MARK: - Close

    private func closeReader() {
        // Final progress sync
        persistProgress(chapter: currentChapter, progress: chapterProgress, force: true)
        persistFontSize(fontSize)
        libraryViewModel.readingComic = nil
        #if os(iOS)
        dismiss()
        #endif
    }

    // MARK: - Persistence

    private func persistProgress(chapter: Int, progress: Double, force: Bool = false) {
        guard let index = libraryViewModel.comics.firstIndex(where: { $0.id == localComic.id }) else { return }
        let clampedProgress = min(max(progress, 0), 1)
        let shouldPersist = force
            || chapter != lastPersistedChapter
            || abs(clampedProgress - lastPersistedProgress) >= 0.01
            || clampedProgress >= 0.995
        guard shouldPersist else { return }

        var updated = libraryViewModel.comics[index]
        updated.currentPage = chapter
        updated.epubChapterIndex = chapter
        updated.epubChapterProgress = clampedProgress
        updated.epubLocatorProgress = overallProgress(chapter: chapter, progress: updated.epubChapterProgress ?? 0)
        updated.lastReadDate = Date()

        if totalChapters > 0 {
            if chapter >= totalChapters - 1 && progress >= 0.995 {
                updated.status = .completed
            } else if chapter > 0 || progress > 0.001 {
                updated.status = .reading
            }
        }

        localComic = updated
        lastPersistedChapter = chapter
        lastPersistedProgress = clampedProgress
        libraryViewModel.updateComic(updated)
    }

    private func overallProgress(chapter: Int, progress: Double) -> Double {
        guard totalChapters > 0 else { return 0 }
        let clampedProgress = min(max(progress, 0), 1)
        return min(max((Double(chapter) + clampedProgress) / Double(totalChapters), 0), 1)
    }

    // MARK: - Theme

    /// One-click cycle Dark → Light → Sepia, saved as this book's override
    /// (same field the Reader Settings sheet writes, so the two stay in sync).
    private func cycleTheme() {
        let current = ReaderSettings.shared.effectiveEPUBTheme(for: localComic)
        let all = EPUBTheme.allCases
        let next = all[((all.firstIndex(of: current) ?? 0) + 1) % all.count]

        localComic.epubTheme = next.rawValue

        guard let index = libraryViewModel.comics.firstIndex(where: { $0.id == localComic.id }) else { return }
        var updated = libraryViewModel.comics[index]
        updated.epubTheme = next.rawValue
        libraryViewModel.updateComic(updated)
    }

    /// Page mode (Kindle-like) ↔ Scroll mode, saved as this book's
    /// reading-style override (books default to Page mode).
    private func togglePageMode() {
        let current = ReadingStyle(rawValue: localComic.readingStyle ?? "") ?? .standard
        let next: ReadingStyle = current == .verticalScroll ? .standard : .verticalScroll
        localComic.readingStyle = next.rawValue

        guard let index = libraryViewModel.comics.firstIndex(where: { $0.id == localComic.id }) else { return }
        var updated = libraryViewModel.comics[index]
        updated.readingStyle = next.rawValue
        libraryViewModel.updateComic(updated)
    }

    private func persistFontSize(_ size: Int) {
        guard let index = libraryViewModel.comics.firstIndex(where: { $0.id == localComic.id }) else { return }
        var updated = libraryViewModel.comics[index]
        updated.epubFontSize = size
        libraryViewModel.updateComic(updated)
    }
}
