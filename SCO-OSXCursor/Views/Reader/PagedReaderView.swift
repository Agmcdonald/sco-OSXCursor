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
                PageCurlView(pages: pages, currentPage: $currentPage)
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
                let safeIndex = min(max(currentPage, 0), pages.count - 1)
                
                ComicPageView(
                    page: pages[safeIndex],
                    onSwipeLeft: {
                        debugLog("[\(platform)][PagedReaderView] ⬅️ onSwipeLeft called! currentPage=\(currentPage), count=\(pages.count)")
                        guard currentPage < pages.count - 1 else {
                            debugLog("[\(platform)][PagedReaderView] ❌ Already at last page")
                            return
                        }
                        debugLog("[\(platform)][PagedReaderView] → Navigating to page \(currentPage + 1)")
                        withAnimation(effectiveTransition.animation()) {
                            currentPage += 1
                        }
                    },
                    onSwipeRight: {
                        debugLog("[\(platform)][PagedReaderView] ➡️ onSwipeRight called! currentPage=\(currentPage)")
                        guard currentPage > 0 else {
                            debugLog("[\(platform)][PagedReaderView] ❌ Already at first page")
                            return
                        }
                        debugLog("[\(platform)][PagedReaderView] → Navigating to page \(currentPage - 1)")
                        withAnimation(effectiveTransition.animation()) {
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
                .zIndex(Double(safeIndex))
                .clipped()
                .transition(effectiveTransition.transition(for: transitionDirection))
                .animation(nil, value: currentPage)
            }
        }
        .onChange(of: currentPage) { oldValue, newValue in
            // Required for macOS 26/iOS 20 - prevents double-fire
            guard newValue != oldValue else {
                debugLog("[\(platform)][PagedReaderView] ⚠️ Double-fire guard triggered")
                return
            }
            
            let transition = effectiveTransition
            debugLog("[\(platform)][PagedReaderView] 📄 Page changed: \(oldValue) → \(newValue)")
            debugLog("[\(platform)][PagedReaderView] 🎬 Transition: \(transition.rawValue)")
            debugLog("[\(platform)][PagedReaderView] ⏱️ Animation: \(transition.animation())")
            
            transitionDirection = newValue > oldValue ? .trailing : .leading
            
            withTransaction(Transaction(animation: effectiveTransition.animation())) {
                withAnimation(effectiveTransition.animation()) {
                    _ = newValue
                }
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

