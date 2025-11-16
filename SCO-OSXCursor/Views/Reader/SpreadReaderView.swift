//
//  SpreadReaderView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/8/25.
//

import SwiftUI

// MARK: - Spread Reader View (Two-Page Display)
@MainActor
struct SpreadReaderView: View {
    let spreads: [PageSpread]
    @Binding var currentSpreadIndex: Int
    var comic: Comic? = nil  // For per-book transition settings
    @ObservedObject private var settings = ReaderSettings.shared
    
    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}
    
    @State private var transitionDirection: Edge = .trailing
    
    // Computed effective transition (per-book or global default)
    private var effectiveTransition: PageTransition {
        settings.effectiveTransition(for: comic)
    }
    
    // MARK: - Debug Logging
    
    @inline(__always) private func debugLog(_ msg: @autoclosure () -> String) {
        #if DEBUG
        print(msg())
        #endif
    }
    
    private let platform: String = {
        #if os(iOS)
        return "📱 iOS"
        #else
        return "💻 macOS"
        #endif
    }()
    
    var body: some View {
        GeometryReader { geometry in
            #if os(iOS)
            if effectiveTransition == .curl {
                // Page Curl doesn't support spreads - fall back to standard view
                let _ = debugLog("[\(platform)][SpreadReaderView] ⚠️ PageCurl disabled in spread mode — using standard view.")
                standardSpreadView
            } else {
                standardSpreadView
            }
            #else
            standardSpreadView
            #endif
        }
    }
    
    private var standardSpreadView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // GUARD: Prevent crash if spreads array is empty
            if spreads.isEmpty {
                Color.clear.ignoresSafeArea()
            } else {
                let safeIndex = min(max(currentSpreadIndex, 0), spreads.count - 1)
                
                SpreadView(
                    spread: spreads[safeIndex],
                    onSwipeLeft: {
                        debugLog("[\(platform)][SpreadReaderView] ⬅️ onSwipeLeft called! spread=\(currentSpreadIndex)")
                        guard currentSpreadIndex < spreads.count - 1 else {
                            debugLog("[\(platform)][SpreadReaderView] ❌ Already at last spread")
                            return
                        }
                        debugLog("[\(platform)][SpreadReaderView] → Navigating to spread \(currentSpreadIndex + 1)")
                        withAnimation(effectiveTransition.animation()) {
                            currentSpreadIndex += 1
                        }
                    },
                    onSwipeRight: {
                        debugLog("[\(platform)][SpreadReaderView] ➡️ onSwipeRight called! spread=\(currentSpreadIndex)")
                        guard currentSpreadIndex > 0 else {
                            debugLog("[\(platform)][SpreadReaderView] ❌ Already at first spread")
                            return
                        }
                        debugLog("[\(platform)][SpreadReaderView] → Navigating to spread \(currentSpreadIndex - 1)")
                        withAnimation(effectiveTransition.animation()) {
                            currentSpreadIndex -= 1
                        }
                    },
                    onBeginDragging: onBeginDragging,
                    onEndDragging: onEndDragging,
                    onBeginPinching: onBeginPinching,
                    onEndPinching: onEndPinching
                )
                .background(Color.black)
                .id(safeIndex)
                .zIndex(Double(safeIndex))
                .clipped()
                .transition(effectiveTransition.transition(for: transitionDirection))
                .animation(nil, value: safeIndex)
            }
        }
        .onChange(of: currentSpreadIndex) { oldValue, newValue in
            // Required for macOS 26/iOS 20
            guard newValue != oldValue else {
                debugLog("[\(platform)][SpreadReaderView] ⚠️ Double-fire guard triggered")
                return
            }
            
            let transition = effectiveTransition
            debugLog("[\(platform)][SpreadReaderView] 📄 Spread changed: \(oldValue) → \(newValue)")
            debugLog("[\(platform)][SpreadReaderView] 🎬 Transition: \(transition.rawValue)")
            debugLog("[\(platform)][SpreadReaderView] ⏱️ Animation: \(transition.animation())")
            
            // Async to prevent desync during rapid keyboard navigation
            withAnimation(effectiveTransition.animation()) {
                DispatchQueue.main.async {
                    transitionDirection = newValue > oldValue ? .trailing : .leading
                }
            }
        }
    }
    
    private var flattenedPages: [ComicPage] {
        spreads.flatMap { spread in
            [spread.leftPage] + (spread.rightPage.map { [$0] } ?? [])
        }
    }
    
    private func spreadToPageIndex(_ spreadIndex: Int) -> Int {
        guard spreadIndex < spreads.count else { return 0 }
        return spreads[spreadIndex].leftPage.pageNumber - 1
    }
    
    private func pageToSpreadIndex(_ pageIndex: Int) -> Int {
        for (index, spread) in spreads.enumerated() {
            if spread.leftPage.pageNumber - 1 == pageIndex {
                return index
            }
        }
        return 0
    }
}

// MARK: - Single Spread View
@MainActor
struct SpreadView: View {
    let spread: PageSpread
    var onSwipeLeft: () -> Void = {}
    var onSwipeRight: () -> Void = {}
    
    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}
    
    // MARK: - Debug Logging
    
    @inline(__always) private func debugLog(_ msg: @autoclosure () -> String) {
        #if DEBUG
        print(msg())
        #endif
    }
    
    private let platform: String = {
        #if os(iOS)
        return "📱 iOS"
        #else
        return "💻 macOS"
        #endif
    }()
    
    var body: some View {
        GeometryReader { geometry in
            if spread.isSinglePage {
                // Single page - center it
                ComicPageView(
                    page: spread.leftPage,
                    onSwipeLeft: onSwipeLeft,
                    onSwipeRight: onSwipeRight,
                    onBeginDragging: onBeginDragging,
                    onEndDragging: onEndDragging,
                    onBeginPinching: onBeginPinching,
                    onEndPinching: onEndPinching
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Two pages side by side - swipe navigates between spreads
                HStack(spacing: 0) {
                    ComicPageView(
                        page: spread.leftPage,
                        onSwipeLeft: onSwipeLeft,
                        onSwipeRight: onSwipeRight,
                        onBeginDragging: onBeginDragging,
                        onEndDragging: onEndDragging,
                        onBeginPinching: onBeginPinching,
                        onEndPinching: onEndPinching
                    )
                    .frame(width: geometry.size.width / 2)
                    
                    if let rightPage = spread.rightPage {
                        ComicPageView(
                            page: rightPage,
                            onSwipeLeft: onSwipeLeft,
                            onSwipeRight: onSwipeRight,
                            onBeginDragging: onBeginDragging,
                            onEndDragging: onEndDragging,
                            onBeginPinching: onBeginPinching,
                            onEndPinching: onEndPinching
                        )
                        .frame(width: geometry.size.width / 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            debugLog("[\(platform)][SpreadView] 🎬 Appeared, passing callbacks to ComicPageView(s)")
        }
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State private var currentSpread = 0
        
        var body: some View {
            let sampleSpreads = [
                PageSpread(
                    id: "spread-0",
                    leftPage: ComicPage(pageNumber: 1, imageData: Data(), fileName: "page1.jpg"),
                    rightPage: nil,
                    spreadIndex: 0
                ),
                PageSpread(
                    id: "spread-1",
                    leftPage: ComicPage(pageNumber: 2, imageData: Data(), fileName: "page2.jpg"),
                    rightPage: ComicPage(pageNumber: 3, imageData: Data(), fileName: "page3.jpg"),
                    spreadIndex: 1
                )
            ]
            
            return SpreadReaderView(
                spreads: sampleSpreads,
                currentSpreadIndex: $currentSpread
            )
        }
    }
    
    return PreviewWrapper()
}

