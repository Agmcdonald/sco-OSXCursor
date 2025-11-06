//
//  ReaderControlsOverlay.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

// MARK: - Reader Controls Overlay
struct ReaderControlsOverlay: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let onClose: () -> Void
    @Binding var controlsVisible: Bool
    @Binding var showingMenu: Bool
    
    var body: some View {
        ZStack {
            // Tap area to toggle controls (entire screen except control areas)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        controlsVisible.toggle()
                    }
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
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Page counter
            Text("Page \(currentPage + 1) of \(totalPages)")
                .font(Typography.body)
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
            
            Spacer()
            
            // Menu button
            Button(action: {
                #if os(iOS)
                withAnimation {
                    showingMenu.toggle()
                    controlsVisible = false
                }
                #endif
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
            currentPage -= 1
        }
    }
    
    private func nextPage() {
        guard currentPage < totalPages - 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage += 1
        }
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
        
        var body: some View {
            ZStack {
                Color.blue.ignoresSafeArea()
                
                ReaderControlsOverlay(
                    currentPage: $currentPage,
                    totalPages: 32,
                    onClose: { print("Close tapped") },
                    controlsVisible: $controlsVisible,
                    showingMenu: $showingMenu
                )
            }
        }
    }
    
    return PreviewWrapper()
}

