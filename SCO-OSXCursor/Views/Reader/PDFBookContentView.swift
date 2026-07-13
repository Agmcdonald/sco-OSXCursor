//
//  PDFBookContentView.swift
//  SCO-OSXCursor
//
//  Top-level container for opt-in PDF book reading. Default PDFs still use
//  ComicReaderView/PDFReader unless Comic.pdfReadsAsBook is true.
//

import SwiftUI

@MainActor
struct PDFBookContentView: View {
    let initialComic: Comic
    @State private var localComic: Comic
    @State private var currentPage: Int
    @State private var totalPages: Int
    @State private var searchQuery: String = ""
    @State private var didReachEnd = false
    @State private var showSettings = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var libraryViewModel: LibraryViewModel

    #if os(iOS)
        @State private var dragOffset: CGFloat = 0
        @State private var dismissDragActive = false
    #endif

    init(comic: Comic) {
        self.initialComic = comic
        _localComic = State(initialValue: comic)
        _currentPage = State(initialValue: max(0, comic.currentPage))
        _totalPages = State(initialValue: max(comic.totalPages, 1))
    }

    var body: some View {
        PDFBookReaderView(
            comic: localComic,
            currentPage: $currentPage,
            totalPages: $totalPages,
            searchQuery: $searchQuery,
            onClose: closeReader,
            onShowSettings: { showSettings = true },
            onPageChanged: { page, total in
                currentPage = page
                totalPages = max(total, 1)
                persistProgress(page: page, total: total)
            },
            onReachedEnd: {
                didReachEnd = true
                persistProgress(page: currentPage, total: totalPages, force: true)
            }
        )
        #if os(iOS)
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
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    guard value.startLocation.y < 120,
                          value.translation.height > 0,
                          value.translation.height > abs(value.translation.width) * 1.2
                    else { return }
                    dismissDragActive = true
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    guard dismissDragActive else { return }
                    dismissDragActive = false
                    let shouldDismiss = dragOffset > 130 || value.predictedEndTranslation.height > 400
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
                    localComic = updatedComic
                    libraryViewModel.updateComic(updatedComic)
                }
            )
        }
        .onDisappear {
            persistProgress(page: currentPage, total: totalPages, force: true)
        }
    }

    private func closeReader() {
        persistProgress(page: currentPage, total: totalPages, force: true)
        libraryViewModel.readingComic = nil
        #if os(iOS)
        dismiss()
        #endif
    }

    private func persistProgress(page: Int, total: Int, force: Bool = false) {
        guard force || page != localComic.currentPage || total != localComic.totalPages || didReachEnd else {
            return
        }
        guard let index = libraryViewModel.comics.firstIndex(where: { $0.id == localComic.id }) else {
            return
        }

        var updated = libraryViewModel.comics[index]
        updated.currentPage = min(max(page, 0), max(total - 1, 0))
        updated.totalPages = max(total, updated.totalPages)
        updated.lastReadDate = Date()
        if didReachEnd {
            updated.status = .completed
        } else if updated.currentPage > 0 {
            updated.status = .reading
        }

        localComic = updated
        libraryViewModel.updateComic(updated)
    }
}
