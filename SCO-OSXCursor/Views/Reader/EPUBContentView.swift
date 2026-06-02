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
    @State private var fontSize: Int

    init(comic: Comic) {
        self.initialComic = comic
        _localComic = State(initialValue: comic)
        _currentChapter = State(initialValue: comic.currentPage)
        _totalChapters = State(initialValue: max(comic.totalPages, 1))
        _fontSize = State(initialValue: comic.epubFontSize ?? 17)
    }

    var body: some View {
        EPUBReaderView(
            comic: localComic,
            currentChapter: $currentChapter,
            totalChapters: $totalChapters,
            fontSize: $fontSize,
            onClose: closeReader,
            onShowSettings: { showSettings = true }
        )
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
            persistProgress(chapter: newChapter)
        }
        .onChange(of: fontSize) { _, newSize in
            persistFontSize(newSize)
        }
    }

    // MARK: - Close

    private func closeReader() {
        // Final progress sync
        persistProgress(chapter: currentChapter)
        persistFontSize(fontSize)
        libraryViewModel.readingComic = nil
        #if os(iOS)
        dismiss()
        #endif
    }

    // MARK: - Persistence

    private func persistProgress(chapter: Int) {
        guard let index = libraryViewModel.comics.firstIndex(where: { $0.id == localComic.id }) else { return }
        var updated = libraryViewModel.comics[index]
        updated.currentPage = chapter
        updated.lastReadDate = Date()

        if totalChapters > 0 {
            if chapter >= totalChapters - 1 {
                updated.status = .completed
            } else if chapter > 0 {
                updated.status = .reading
            }
        }

        libraryViewModel.updateComic(updated)
    }

    private func persistFontSize(_ size: Int) {
        guard let index = libraryViewModel.comics.firstIndex(where: { $0.id == localComic.id }) else { return }
        var updated = libraryViewModel.comics[index]
        updated.epubFontSize = size
        libraryViewModel.updateComic(updated)
    }
}
