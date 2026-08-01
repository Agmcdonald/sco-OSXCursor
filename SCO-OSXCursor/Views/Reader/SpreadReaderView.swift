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
            #if os(iOS)
                if effectiveTransition == .curl {
                    // Apple Books-style spread curl — spine at center, the back
                    // of the curling page shows the next page
                    SpreadCurlView(
                        spreads: spreads,
                        currentSpreadIndex: $currentSpreadIndex,
                        isRTL: viewModel?.isMangaRTL ?? false,
                        initialScale: CGFloat(comic?.zoomScale ?? 1.0)
                    )
                    .background(Color.black)
                    .ignoresSafeArea()
                } else if effectiveTransition == .slide {
                    interactiveSlideView
                } else {
                    standardSpreadView
                }
            #else
                if effectiveTransition == .slide {
                    interactiveSlideView
                } else {
                    standardSpreadView
                }
            #endif
        }
    }

    // MARK: - Interactive slide (Panels-style contiguous pager)

    private var interactiveSlideView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !spreads.isEmpty {
                InteractivePagerReader(
                    items: spreads,
                    index: $currentSpreadIndex,
                    isRTL: viewModel?.isMangaRTL ?? false,
                    onTurn: { step in
                        if let viewModel {
                            viewModel.turn(by: step)  // 1 step = 1 spread (VM converts to 2 pages)
                        } else {
                            let target = currentSpreadIndex + step
                            guard spreads.indices.contains(target) else { return }
                            currentSpreadIndex = target
                        }
                    }
                ) { spread, isActive, scrubChanged, scrubEnded in
                    SpreadView(
                        spread: spread,
                        initialScale: CGFloat(comic?.zoomScale ?? 1.0),
                        onSwipeLeft: { viewModel?.turn(by: +1) },
                        onSwipeRight: { viewModel?.turn(by: -1) },
                        onBeginDragging: onBeginDragging,
                        onEndDragging: onEndDragging,
                        onBeginPinching: onBeginPinching,
                        onEndPinching: onEndPinching,
                        isActive: isActive,
                        onScrubChanged: scrubChanged,
                        onScrubEnded: scrubEnded
                    )
                }
            }
        }
    }

    // MARK: - Transition-based spread swap (fade / zoom / none)

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
                    initialScale: CGFloat(comic?.zoomScale ?? 1.0),
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
}

// MARK: - Single Spread View
//
// The whole spread renders inside ONE ZoomableCanvas: pinch zooms both pages
// together as a single surface (art crosses the center gutter) and fills the
// entire viewport — matching Panels, instead of each page zooming alone
// inside its own half-screen pane.
@MainActor
struct SpreadView: View {
    let spread: PageSpread
    /// Per-book zoom memory
    var initialScale: CGFloat = 1.0
    var onSwipeLeft: () -> Void = {}  // Next page/spread
    var onSwipeRight: () -> Void = {}  // Previous page/spread

    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}

    /// Pager wiring (see ZoomableCanvas)
    var isActive: Bool = true
    var onScrubChanged: ((CGFloat) -> Void)? = nil
    var onScrubEnded: ((CGFloat, CGFloat) -> Void)? = nil

    var body: some View {
        ZoomableCanvas(
            resetID: AnyHashable(spread.id),
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onBeginDragging: onBeginDragging,
            onEndDragging: onEndDragging,
            onBeginPinching: onBeginPinching,
            onEndPinching: onEndPinching,
            initialScale: initialScale,
            isActive: isActive,
            onScrubChanged: onScrubChanged,
            onScrubEnded: onScrubEnded
        ) {
            if spread.isSinglePage {
                ComicPageImage(page: spread.leftPage)
            } else {
                HStack(spacing: 0) {
                    ComicPageImage(page: spread.leftPage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let rightPage = spread.rightPage {
                        ComicPageImage(page: rightPage)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
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
