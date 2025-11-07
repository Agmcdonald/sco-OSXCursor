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
    @EnvironmentObject var libraryViewModel: LibraryViewModel  // To update progress
    @StateObject private var viewModel = ReaderViewModel()
    @State private var controlsVisible = true
    @State private var showingMenu = false
    
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
            
            // Always show close button on iPad (even during loading/error)
            #if os(iOS)
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(Spacing.lg)
                    
                    Spacer()
                }
                Spacer()
            }
            .zIndex(999) // Keep on top
            #endif
        }
        .task {
            print("📖 [ComicReaderView] .task triggered - about to load comic")
            print("📖 [ComicReaderView] Comic: \(comic.fileName)")
            await viewModel.loadComic(from: comic)
            print("📖 [ComicReaderView] loadComic() returned")
        }
        .onChange(of: viewModel.currentPage) { oldValue, newValue in
            print("📖 [ComicReaderView] Page changed: \(oldValue + 1) → \(newValue + 1)")
            Task {
                await viewModel.onPageChanged(to: newValue)
                
                // Update the comic in library with new progress
                var updatedComic = comic
                updatedComic.currentPage = newValue
                
                // Update status based on progress
                if let totalPages = viewModel.comicBook?.totalPages {
                    if newValue >= totalPages - 1 {
                        updatedComic.status = .completed
                    } else if newValue > 0 {
                        updatedComic.status = .reading
                    }
                }
                updatedComic.lastReadDate = Date()
                
                await MainActor.run {
                    libraryViewModel.updateComic(updatedComic)
                }
            }
        }
        .onDisappear {
            // Final sync when reader closes
            libraryViewModel.syncProgressFromTracker()
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
            // Paged reader (uses viewModel.allPages for lazy loading support)
            PagedReaderView(
                pages: viewModel.allPages,
                currentPage: $viewModel.currentPage
            )
            
            // Controls overlay
            ReaderControlsOverlay(
                currentPage: $viewModel.currentPage,
                totalPages: comicBook.totalPages,
                onClose: {
                    dismiss()
                },
                controlsVisible: $controlsVisible,
                showingMenu: $showingMenu,
                isBackgroundLoading: $viewModel.isBackgroundLoading
            )
            
            // Navigation menu (iPad only)
            #if os(iOS)
            if showingMenu {
                navigationMenuOverlay
            }
            #endif
        }
    }
    
    // MARK: - Navigation Menu Overlay (iPad)
    #if os(iOS)
    private var navigationMenuOverlay: some View {
        ZStack {
            // Dismiss area
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        showingMenu = false
                    }
                }
            
            // Menu panel
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Navigate To")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.xl)
                    
                    Divider()
                        .background(BorderColors.subtle)
                        .padding(.vertical, Spacing.md)
                    
                    // Menu items
                    MenuNavItem(icon: "xmark.circle.fill", title: "Close Reader", color: AccentColors.error) {
                        showingMenu = false
                        dismiss()
                    }
                    
                    MenuNavItem(icon: "books.vertical", title: "Library") {
                        showingMenu = false
                        dismiss()
                    }
                    
                    MenuNavItem(icon: "folder.badge.gearshape", title: "Organize") {
                        showingMenu = false
                        dismiss()
                    }
                    
                    MenuNavItem(icon: "gear", title: "Settings") {
                        showingMenu = false
                        dismiss()
                    }
                    
                    Divider()
                        .background(BorderColors.subtle)
                        .padding(.vertical, Spacing.md)
                    
                    Button(action: {
                        withAnimation {
                            showingMenu = false
                        }
                    }) {
                        Text("Cancel")
                            .font(Typography.button)
                            .foregroundColor(TextColors.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xl)
                }
                .background(BackgroundColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(Spacing.xl)
            }
        }
    }
    #endif
    
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
        ZStack {
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
            
            // Always show close button in top-left (especially for iPad)
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(Spacing.lg)
                    
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ComicReaderView(comic: Comic.sample())
}

