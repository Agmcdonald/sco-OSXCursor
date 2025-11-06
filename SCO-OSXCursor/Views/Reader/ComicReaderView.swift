//
//  ComicReaderView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

// MARK: - Comic Reader View
struct ComicReaderView: View {
    let comic: Comic
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ReaderViewModel()
    @State private var controlsVisible = true
    
    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                // Loading state
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                // Error state
                errorView(errorMessage)
            } else if let comicBook = viewModel.comicBook {
                // Reader
                readerView(comicBook)
            }
        }
        .task {
            await viewModel.loadComic(from: comic)
        }
        .preferredColorScheme(.dark)
        #if os(macOS)
        .navigationBarBackButtonHidden(true)
        #else
        .statusBar(hidden: !controlsVisible)
        .navigationBarHidden(true)
        #endif
    }
    
    // MARK: - Reader View
    private func readerView(_ comicBook: ComicBook) -> some View {
        ZStack {
            // Paged reader
            PagedReaderView(
                pages: comicBook.pages,
                currentPage: $viewModel.currentPage
            )
            
            // Controls overlay
            ReaderControlsOverlay(
                currentPage: $viewModel.currentPage,
                totalPages: comicBook.totalPages,
                onClose: {
                    dismiss()
                },
                controlsVisible: $controlsVisible
            )
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Loading comic...")
                .font(Typography.body)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Error View
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.xxl) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 64))
                    .foregroundColor(AccentColors.error)
                
                Text("Unable to Load Comic")
                    .font(Typography.h2)
                    .foregroundColor(.white)
                
                Text(message)
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }
            
            Button(action: { dismiss() }) {
                Text("Close")
                    .font(Typography.button)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.md)
                    .background(AccentColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Preview
#Preview {
    ComicReaderView(comic: Comic.sample())
}

