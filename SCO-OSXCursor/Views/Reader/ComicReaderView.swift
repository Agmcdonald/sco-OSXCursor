//
//  ComicReaderView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Keyboard Monitor (macOS)
#if os(macOS)
class KeyboardMonitor {
    private var monitor: Any?
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onEscape: (() -> Void)?
    
    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            switch event.keyCode {
            case 123:  // Left arrow
                self.onLeftArrow?()
                return nil  // Consume the event
            case 124:  // Right arrow
                self.onRightArrow?()
                return nil  // Consume the event
            case 53:   // Escape
                self.onEscape?()
                return nil  // Consume the event
            default:
                return event  // Pass through other keys
            }
        }
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    
    deinit {
        stop()
    }
}
#endif

// MARK: - Comic Reader View
@MainActor
struct ComicReaderView: View {
    let comic: Comic
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var libraryViewModel: LibraryViewModel  // To update progress
    @StateObject private var viewModel = ReaderViewModel()
    @State private var controlsVisible = true
    @State private var showingMenu = false
    @State private var showingThumbnails = false
    @State private var autoHideTimer: Timer?
    @State private var isFullScreen = false  // Only functional on iPad
    #if os(macOS)
    @State private var keyboardMonitor: KeyboardMonitor? = nil
    #endif
    
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
            
            // Close button on iPad (hides/shows with controls)
            #if os(iOS)
            if controlsVisible {
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            #endif
        }
        .task {
            print("📖 [ComicReaderView] .task triggered - about to load comic")
            print("📖 [ComicReaderView] Comic: \(comic.fileName)")
            await viewModel.loadComic(from: comic)
            print("📖 [ComicReaderView] loadComic() returned")
            
            // Start auto-hide timer when reader loads
            resetAutoHideTimer()
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
        .focusable()
        .onAppear {
            setupKeyboardMonitoring()
        }
        .onDisappear {
            removeKeyboardMonitoring()
        }
        #else
        .statusBar(hidden: !controlsVisible)
        .navigationBarHidden(true)
        #endif
    }
    
    // MARK: - Reader View
    private func readerView(_ comicBook: ComicBook) -> some View {
        ZStack {
            // Reader mode: single-page or two-page spread
            if viewModel.isSpreadMode {
                SpreadReaderView(
                    spreads: viewModel.pageSpreads,
                    currentSpreadIndex: Binding(
                        get: { spreadIndexForPage(viewModel.currentPage) },
                        set: { newSpreadIndex in
                            viewModel.currentPage = pageForSpreadIndex(newSpreadIndex)
                        }
                    )
                )
            } else {
                PagedReaderView(
                    pages: viewModel.allPages,
                    currentPage: $viewModel.currentPage
                )
            }
            
            // Controls overlay
            ReaderControlsOverlay(
                currentPage: $viewModel.currentPage,
                totalPages: comicBook.totalPages,
                comicTitle: comic.displayTitle,
                pages: viewModel.allPages,
                onClose: {
                    dismiss()
                },
                controlsVisible: $controlsVisible,
                showingMenu: $showingMenu,
                showingThumbnails: $showingThumbnails,
                isBackgroundLoading: $viewModel.isBackgroundLoading,
                isFullScreen: $isFullScreen,
                isSpreadMode: $viewModel.isSpreadMode,
                onUserInteraction: {
                    resetAutoHideTimer()
                }
            )
            
            // Thumbnail grid overlay
            if showingThumbnails {
                ThumbnailGridView(
                    pages: viewModel.allPages,
                    currentPage: $viewModel.currentPage,
                    isPresented: $showingThumbnails
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(1000)
            }
            
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
    
    // MARK: - Helper Methods
    
    /// Reset the auto-hide timer - hides controls after 3 seconds of inactivity
    private func resetAutoHideTimer() {
        #if os(iOS)
        // iPad: auto-hide controls after inactivity (swipe/tap navigation)
        autoHideTimer?.invalidate()
        
        // Don't restart timer if controls are already hidden
        if !controlsVisible {
            return
        }
        
        // Start new timer
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                controlsVisible = false
            }
        }
        #else
        // macOS: controls stay visible (users need buttons, can't swipe)
        // No auto-hide timer needed
        #endif
    }
    
    /// Cancel the auto-hide timer
    private func cancelAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }
    
    // MARK: - Spread Mode Helpers
    
    /// Convert page index to spread index
    private func spreadIndexForPage(_ pageIndex: Int) -> Int {
        let spreads = viewModel.pageSpreads
        
        // Find which spread contains this page
        for (index, spread) in spreads.enumerated() {
            if spread.leftPage.pageNumber - 1 == pageIndex {
                return index
            }
            if let rightPage = spread.rightPage, rightPage.pageNumber - 1 == pageIndex {
                return index
            }
        }
        
        return 0  // Fallback to first spread
    }
    
    /// Convert spread index to page index (returns left page of spread)
    private func pageForSpreadIndex(_ spreadIndex: Int) -> Int {
        let spreads = viewModel.pageSpreads
        guard spreadIndex < spreads.count else { return 0 }
        
        return spreads[spreadIndex].leftPage.pageNumber - 1
    }
    
    #if os(macOS)
    // MARK: - Keyboard Navigation
    
    /// Setup keyboard event monitoring
    private func setupKeyboardMonitoring() {
        let monitor = KeyboardMonitor()
        
        monitor.onLeftArrow = { [weak viewModel] in
            guard let viewModel = viewModel else { return }
            guard viewModel.currentPage > 0 else { return }
            
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    if viewModel.isSpreadMode {
                        viewModel.currentPage = max(0, viewModel.currentPage - 2)
                    } else {
                        viewModel.currentPage -= 1
                    }
                }
            }
        }
        
        monitor.onRightArrow = { [weak viewModel] in
            guard let viewModel = viewModel else { return }
            guard let totalPages = viewModel.comicBook?.totalPages else { return }
            guard viewModel.currentPage < totalPages - 1 else { return }
            
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    if viewModel.isSpreadMode {
                        viewModel.currentPage = min(totalPages - 1, viewModel.currentPage + 2)
                    } else {
                        viewModel.currentPage += 1
                    }
                }
            }
        }
        
        monitor.onEscape = { [dismiss] in
            Task { @MainActor in
                dismiss()
            }
        }
        
        monitor.start()
        keyboardMonitor = monitor
    }
    
    /// Remove keyboard event monitoring
    private func removeKeyboardMonitoring() {
        keyboardMonitor?.stop()
    }
    #endif
}

// MARK: - Preview
#Preview {
    ComicReaderView(comic: Comic.sample())
}

