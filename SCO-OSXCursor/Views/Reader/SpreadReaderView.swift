//
//  SpreadReaderView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/8/25.
//

import SwiftUI
import os

// MARK: - Spread Reader View (Two-Page Display)
@MainActor
struct SpreadReaderView: View {
    let spreads: [PageSpread]
    @Binding var currentSpreadIndex: Int
    var comic: Comic? = nil  // For per-book transition settings
    @ObservedObject private var settings = ReaderSettings.shared
    var viewModel: ReaderViewModel? = nil  // For debounced turns

    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}

    @State private var transitionDirection: Edge = .trailing
    /// The spread actually rendered — swapped inside withAnimation after the
    /// direction is set (see PagedReaderView.displayedIndex for rationale)
    @State private var displayedIndex: Int = 0

    // Computed effective transition (per-book or global default)
    private var effectiveTransition: PageTransition {
        settings.effectiveTransition(for: comic)
    }

    // MARK: - Debug Logging

    @inline(__always) private func debugLog(_ msg: @autoclosure () -> String) {
        #if DEBUG
            AppLog.reader.debug("\(msg())")
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
            standardSpreadView
        }
    }

    private var standardSpreadView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // GUARD: Prevent crash if spreads array is empty
            if spreads.isEmpty {
                Color.clear.ignoresSafeArea()
            } else {
                let safeIndex = min(max(displayedIndex, 0), spreads.count - 1)

                SpreadView(
                    spread: spreads[safeIndex],
                    onSwipeLeft: {
                        if let viewModel = viewModel {
                            viewModel.turn(by: +1)  // +1 spread = +2 pages (VM handles conversion)
                        } else {
                            // Fallback for compatibility
                            guard currentSpreadIndex < spreads.count - 1 else { return }
                            currentSpreadIndex += 1
                        }
                    },
                    onSwipeRight: {
                        if let viewModel = viewModel {
                            viewModel.turn(by: -1)  // -1 spread = -2 pages (VM handles conversion)
                        } else {
                            // Fallback for compatibility
                            guard currentSpreadIndex > 0 else { return }
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
                .transition(effectiveTransition.transition(for: transitionDirection))
            }
        }
        .clipped()
        .onAppear {
            displayedIndex = currentSpreadIndex
        }
        .onChange(of: currentSpreadIndex) { oldValue, newValue in
            // Required for macOS 26/iOS 20
            guard newValue != oldValue else {
                debugLog("[\(platform)][SpreadReaderView] ⚠️ Double-fire guard triggered")
                return
            }

            debugLog("[\(platform)][SpreadReaderView] 📄 Spread changed: \(oldValue) → \(newValue)")

            // 1. Direction FIRST (unanimated)…
            transitionDirection = newValue > oldValue ? .trailing : .leading

            // 2. …then swap the displayed spread inside the animation so the
            //    outgoing spread slides out while the incoming slides in.
            withAnimation(effectiveTransition.animation()) {
                displayedIndex = newValue
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
    var onSwipeLeft: () -> Void = {}  // Next page/spread
    var onSwipeRight: () -> Void = {}  // Previous page/spread

    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}

    // MARK: - Debug Logging

    @inline(__always) private func debugLog(_ msg: @autoclosure () -> String) {
        #if DEBUG
            AppLog.reader.debug("\(msg())")
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
            ZStack {
                // Page content
                if spread.isSinglePage {
                    // Single page — center it; tap handling is still global below
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
                    // Two pages side by side
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

            }  // ZStack
        }  // GeometryReader
        .onAppear {
            debugLog("[\(platform)][SpreadView] 🎬 Appeared")
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
                ),
            ]

            return SpreadReaderView(
                spreads: sampleSpreads,
                currentSpreadIndex: $currentSpread
            )
        }
    }

    return PreviewWrapper()
}
