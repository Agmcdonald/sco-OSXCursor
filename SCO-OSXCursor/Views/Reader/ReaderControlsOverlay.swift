//
//  ReaderControlsOverlay.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

// MARK: - Reader Controls Overlay
@MainActor
struct ReaderControlsOverlay: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let onClose: () -> Void
    @Binding var controlsVisible: Bool
    @Binding var showingMenu: Bool
    @Binding var isBackgroundLoading: Bool  // Show loading indicator
    @Binding var isFullScreen: Bool  // Fullscreen mode
    @Binding var isSpreadMode: Bool  // Two-page spread mode
    let onUserInteraction: () -> Void  // Called when user interacts
    
    var body: some View {
        ZStack {
            // Tap area to toggle controls (entire screen except control areas)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        controlsVisible.toggle()
                    }
                    onUserInteraction()
                }
            
            VStack(spacing: 0) {
                // Top bar
                if controlsVisible {
                    topBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                // Bottom bar
                if controlsVisible {
                    bottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: Spacing.lg) {
            // Close button
            Button(action: {
                onClose()
                onUserInteraction()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help("Close Reader (Esc)")
            #endif
            
            Spacer()
            
            // Page counter with loading indicator
            HStack(spacing: Spacing.sm) {
                Text("Page \(currentPage + 1) of \(totalPages)")
                    .font(Typography.body)
                    .foregroundColor(.white)
                
                // Loading badge (only for PDFs during background loading)
                if isBackgroundLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                        
                        Text("Loading pages...")
                            .font(Typography.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 6)
                    .background(AccentColors.primary.opacity(0.8))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(Color.black.opacity(0.5))
            .clipShape(Capsule())
            
            Spacer()
            
            // Spread mode toggle button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isSpreadMode.toggle()
                }
                onUserInteraction()
            }) {
                Image(systemName: isSpreadMode ? "rectangle.split.2x1" : "rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help(isSpreadMode ? "Switch to Single Page" : "Switch to Two-Page Spread")
            #endif
            
            // Fullscreen toggle button (iOS only - macOS uses sheets which can't enter native fullscreen)
            #if os(iOS)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isFullScreen.toggle()
                }
                onUserInteraction()
            }) {
                Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            #endif
            
            // Menu button
            Button(action: {
                #if os(iOS)
                withAnimation {
                    showingMenu.toggle()
                    controlsVisible = false
                }
                #endif
                onUserInteraction()
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.7), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }
    
    // MARK: - Bottom Bar
    private var bottomBar: some View {
        VStack(spacing: Spacing.md) {
            // Page slider
            HStack(spacing: Spacing.lg) {
                // Previous button
                Button(action: previousPage) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(currentPage > 0 ? .white : .white.opacity(0.3))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(currentPage == 0)
                #if os(macOS)
                .help("Previous Page (←)")
                #endif
                
                // Slider
                if totalPages > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(currentPage) },
                            set: { currentPage = Int($0) }
                        ),
                        in: 0...Double(max(totalPages - 1, 0)),
                        step: 1
                    )
                    .tint(AccentColors.primary)
                }
                
                // Next button
                Button(action: nextPage) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(currentPage < totalPages - 1 ? .white : .white.opacity(0.3))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(currentPage >= totalPages - 1)
                #if os(macOS)
                .help("Next Page (→)")
                #endif
            }
            .padding(.horizontal, Spacing.xl)
        }
        .padding(.vertical, Spacing.lg)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
    
    // MARK: - Actions
    private func previousPage() {
        guard currentPage > 0 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            if isSpreadMode {
                // In spread mode, jump to previous spread (usually 2 pages back)
                currentPage = max(0, currentPage - 2)
            } else {
                // Single page mode - go back one page
                currentPage -= 1
            }
        }
        onUserInteraction()
    }
    
    private func nextPage() {
        guard currentPage < totalPages - 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            if isSpreadMode {
                // In spread mode, jump to next spread (usually 2 pages forward)
                currentPage = min(totalPages - 1, currentPage + 2)
            } else {
                // Single page mode - go forward one page
                currentPage += 1
            }
        }
        onUserInteraction()
    }
}

// MARK: - Menu Navigation Item
struct MenuNavItem: View {
    let icon: String
    let title: String
    var color: Color = TextColors.primary
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                    .frame(width: 24)
                
                Text(title)
                    .font(Typography.body)
                    .foregroundColor(color)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(TextColors.tertiary)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .background(Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State private var currentPage = 5
        @State private var controlsVisible = true
        @State private var showingMenu = false
        @State private var isBackgroundLoading = true
        @State private var isFullScreen = false
        @State private var isSpreadMode = false
        
        var body: some View {
            ZStack {
                Color.blue.ignoresSafeArea()
                
                ReaderControlsOverlay(
                    currentPage: $currentPage,
                    totalPages: 32,
                    onClose: { print("Close tapped") },
                    controlsVisible: $controlsVisible,
                    showingMenu: $showingMenu,
                    isBackgroundLoading: $isBackgroundLoading,
                    isFullScreen: $isFullScreen,
                    isSpreadMode: $isSpreadMode,
                    onUserInteraction: { print("User interacted") }
                )
            }
        }
    }
    
    return PreviewWrapper()
}

