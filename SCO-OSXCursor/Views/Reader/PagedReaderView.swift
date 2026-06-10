//
//  PagedReaderView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

// MARK: - Paged Reader View
@MainActor
struct PagedReaderView: View {
    let pages: [ComicPage]
    @Binding var currentPage: Int
    var comic: Comic? = nil  // For per-book transition settings
    @ObservedObject private var settings = ReaderSettings.shared
    var viewModel: ReaderViewModel? = nil  // For debounced turns
    
    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}
    
    @State private var transitionDirection: Edge = .trailing
    /// The page actually rendered. Updated inside withAnimation AFTER the
    /// transition direction is set, so insert/remove transitions fire with
    /// the right direction — binding identity straight to currentPage (with
    /// .animation(nil) on the view) made page changes swap instantly.
    @State private var displayedIndex: Int = 0

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
                    // Apple Books-style page curl via UIPageViewController
                    PageCurlView(pages: pages, currentPage: $currentPage)
                        .background(Color.black)
                        .ignoresSafeArea()
                } else {
                    standardPageView
                }
            #else
                standardPageView
            #endif
        }
    }
    
    private var standardPageView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // GUARD: Prevent crash if pages array is empty during reload
            if pages.isEmpty {
                Color.clear.ignoresSafeArea()
            } else {
                let safeIndex = min(max(displayedIndex, 0), pages.count - 1)

                ComicPageView(
                    page: pages[safeIndex],
                    onSwipeLeft: {
                        if let viewModel = viewModel {
                            viewModel.turn(by: +1)
                        } else {
                            // Fallback for compatibility
                            guard currentPage < pages.count - 1 else { return }
                            currentPage += 1
                        }
                    },
                    onSwipeRight: {
                        if let viewModel = viewModel {
                            viewModel.turn(by: -1)
                        } else {
                            // Fallback for compatibility
                            guard currentPage > 0 else { return }
                            currentPage -= 1
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
            displayedIndex = currentPage
        }
        .onChange(of: currentPage) { oldValue, newValue in
            // Required for macOS 26/iOS 20 - prevents double-fire
            guard newValue != oldValue else {
                debugLog("[\(platform)][PagedReaderView] ⚠️ Double-fire guard triggered")
                return
            }

            debugLog("[\(platform)][PagedReaderView] 📄 Page changed: \(oldValue) → \(newValue)")

            // 1. Set the direction FIRST (unanimated)…
            transitionDirection = newValue > oldValue ? .trailing : .leading

            // 2. …then swap the displayed page inside the animation, so the
            //    outgoing page slides out while the incoming page slides in.
            withAnimation(effectiveTransition.animation()) {
                displayedIndex = newValue
            }
        }
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State private var currentPage = 0
        
        var body: some View {
            PagedReaderView(
                pages: [
                    ComicPage(pageNumber: 1, imageData: createSampleImage(color: .blue, text: "Page 1"), fileName: "page1.jpg"),
                    ComicPage(pageNumber: 2, imageData: createSampleImage(color: .green, text: "Page 2"), fileName: "page2.jpg"),
                    ComicPage(pageNumber: 3, imageData: createSampleImage(color: .red, text: "Page 3"), fileName: "page3.jpg"),
                    ComicPage(pageNumber: 4, imageData: createSampleImage(color: .orange, text: "Page 4"), fileName: "page4.jpg"),
                ],
                currentPage: $currentPage
            )
        }
        
        func createSampleImage(color: Color, text: String) -> Data {
            #if os(macOS)
            let size = CGSize(width: 400, height: 600)
            let image = NSImage(size: size)
            image.lockFocus()
            
            // Background color
            NSColor(color).setFill()
            NSRect(origin: .zero, size: size).fill()
            
            // Text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 32),
                .foregroundColor: NSColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = NSRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
            
            image.unlockFocus()
            return image.tiffRepresentation ?? Data()
            #else
            let size = CGSize(width: 400, height: 600)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                // Background color
                UIColor(color).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                
                // Text
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 32),
                    .foregroundColor: UIColor.white
                ]
                let textSize = text.size(withAttributes: attributes)
                let textRect = CGRect(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                text.draw(in: textRect, withAttributes: attributes)
            }
            return image.pngData() ?? Data()
            #endif
        }
    }
    
    return PreviewWrapper()
}

