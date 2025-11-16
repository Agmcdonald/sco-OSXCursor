//
//  ComicPageView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

// MARK: - Comic Page View
@MainActor
struct ComicPageView: View {
    let page: ComicPage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @GestureState private var isDragging = false
    @State private var hasReportedDragStart = false
    @State private var hasReportedPinchStart = false
    
    // Swipe callbacks provided by parent
    var onSwipeLeft: () -> Void = {}
    var onSwipeRight: () -> Void = {}
    
    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}
    
    // Tunables
    private let baseSwipeThreshold: CGFloat = 50
    private let maxVerticalRatio: CGFloat = 0.5  // Vertical drift must be < 50% of horizontal distance
    
    // MARK: - Debug Logging
    
    @inline(__always) private func debugLog(_ msg: @autoclosure () -> String) {
        #if DEBUG
        print(msg())
        #endif
    }
    
    private let platform: String = {
        #if os(iOS)
        return "📱 iOS"
        #elseif os(macOS)
        return "💻 macOS"
        #else
        return "❓ Unknown"
        #endif
    }()
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Page image with zoom and pan
                if let image = page.image {
                    let platformImage: Image = {
                        #if os(macOS)
                        return Image(nsImage: image)
                        #else
                        return Image(uiImage: image)
                        #endif
                    }()
                    
                    platformImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .contentShape(Rectangle())  // Ensures taps work on transparent areas
                        .scaleEffect(scale)
                        .offset(offset)
                        .clipped()
                        .highPriorityGesture(unifiedDragGesture(geo: geo))  // High priority so it wins over overlay
                        .simultaneousGesture(magnificationGesture(geo: geo))
                        .onTapGesture(count: 2, perform: handleDoubleTap)
                        .accessibilityLabel(Text("Page \(page.pageNumber)"))
                        .accessibilityAddTraits(.isImage)
                        .onAppear {
                            debugLog("\n========== NEW SESSION (\(platform)) Page \(page.pageNumber) ==========")
                            debugLog("[\(platform)][ComicPageView] 🎬 Appeared for page \(page.pageNumber)")
                            debugLog("[\(platform)][ComicPageView] ✅ Gestures attached: magnify✅ unified✅ doubleTap✅")
                            debugLog("[\(platform)][ComicPageView] 📐 geo.size=\(geo.size.width)x\(geo.size.height)")
                        }
                } else {
                    // Fallback if image can't be loaded
                    VStack(spacing: Spacing.lg) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Loading page \(page.pageNumber)...")
                            .font(Typography.body)
                            .foregroundColor(TextColors.secondary)
                            .padding(.top, Spacing.md)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: page.id) { _ in
            // Reset zoom when page changes
            withAnimation(.easeInOut(duration: 0.3)) {
                scale = 1.0
                offset = .zero
            }
            lastScale = 1.0
            lastOffset = .zero
            hasReportedDragStart = false
            hasReportedPinchStart = false
            debugLog("[\(platform)][ComicPageView] 🔄 Page reset: scale→1.0, offset→.zero")
        }
    }
    
    // MARK: - Gestures
    
    /// Unified drag gesture: pan when zoomed, swipe when not
    private func unifiedDragGesture(geo: GeometryProxy) -> some Gesture {
        // Adaptive threshold: larger on iPad for better feel
        #if os(iOS)
        let swipeMinDistance = max(50, geo.size.width * 0.06) // ~50-80pt on large iPads
        #else
        let swipeMinDistance: CGFloat = 50
        #endif
        
        return DragGesture(minimumDistance: swipeMinDistance)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                // Report drag start to container (only once per gesture)
                if !hasReportedDragStart && (value.translation.width != 0 || value.translation.height != 0) {
                    hasReportedDragStart = true
                    onBeginDragging()
                }
                
                // When zoomed, this gesture pans the page, not turns pages
                if scale > 1.01 {
                    // PAN only while zoomed (with epsilon for jitter)
                    let newOffset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    offset = clamped(offset: newOffset, in: geo, scale: scale)
                }
            }
            .onEnded { value in
                // Report drag end to container (with cooldown)
                hasReportedDragStart = false
                onEndDragging()
                debugLog("[\(platform)][ComicPageView] 📍 Drag ended: scale=\(scale), dx=\(value.translation.width), dy=\(value.translation.height)")
                
                // If zoomed, finish pan and return (no page turn)
                if scale > 1.01 {
                    debugLog("[\(platform)][ComicPageView] → Finishing pan (zoomed)")
                    let finalOffset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    lastOffset = clamped(offset: finalOffset, in: geo, scale: scale)
                    return
                }
                
                #if os(iOS)
                // SWIPE only when not zoomed (iOS only)
                let dx = value.translation.width
                let dy = value.translation.height
                
                // Adaptive threshold: larger on iPad (14% vs 12%)
                #if os(iOS)
                let baseMultiplier: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 0.14 : 0.12
                #else
                let baseMultiplier: CGFloat = 0.12
                #endif
                let base = geo.size.width * baseMultiplier
                let threshold = max(baseSwipeThreshold, base)
                
                // Calculate ratio: vertical drift relative to horizontal distance
                // ratio = |dy| / |dx| - lower ratio means more horizontal
                let ratio = abs(dy) / max(abs(dx), 1)
                
                debugLog("[\(platform)][ComicPageView] 🔍 Swipe check: dx=\(dx), threshold=\(threshold), dy=\(dy), ratio=\(String(format: "%.3f", ratio))")
                
                // Must be mostly horizontal (ratio-based check accounts for natural drift over long distances)
                guard ratio < maxVerticalRatio else {
                    debugLog("[\(platform)][ComicPageView] ❌ Too diagonal: ratio=\(String(format: "%.3f", ratio)) >= \(maxVerticalRatio)")
                    return
                }
                
                // Check threshold
                if dx <= -threshold {
                    debugLog("[\(platform)][ComicPageView] ⬅️ SWIPE LEFT accepted: dx=\(dx), ratio=\(String(format: "%.3f", ratio))")
                    onSwipeLeft()
                } else if dx >= threshold {
                    debugLog("[\(platform)][ComicPageView] ➡️ SWIPE RIGHT accepted: dx=\(dx), ratio=\(String(format: "%.3f", ratio))")
                    onSwipeRight()
                } else {
                    debugLog("[\(platform)][ComicPageView] ❌ Below threshold: |dx|=\(abs(dx)) < threshold=\(threshold)")
                }
                #else
                debugLog("[\(platform)][ComicPageView] ⚠️ iOS guard blocked swipe (macOS build)")
                #endif
            }
    }
    
    /// Magnification gesture with clamping and scale snapping
    private func magnificationGesture(geo: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                // Report pinch start to container (only once per gesture)
                if !hasReportedPinchStart {
                    hasReportedPinchStart = true
                    onBeginPinching()
                }
                
                let newScale = lastScale * magnification
                scale = min(max(newScale, 1.0), 4.0)  // 1x to 4x zoom
                if scale > 1.0 {
                    offset = clamped(offset: offset, in: geo, scale: scale)
                }
            }
            .onEnded { magnification in
                // Report pinch end to container (with cooldown)
                hasReportedPinchStart = false
                onEndPinching()
                let newScale = lastScale * magnification
                var finalScale = min(max(newScale, 1.0), 4.0)
                
                // Snap back if barely zoomed (prevents tiny lingering zooms)
                if finalScale < 1.02 {
                    finalScale = 1.0
                }
                
                withAnimation(.easeOut) {
                    scale = finalScale
                }
                
                lastScale = scale
                debugLog("[\(platform)][ComicPageView] ✅ Magnification ended: final scale=\(scale)")
                
                // Reset all state when returning to 1.0
                if scale == 1.0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        offset = .zero
                    }
                    lastOffset = .zero
                } else {
                    lastOffset = clamped(offset: offset, in: geo, scale: scale)
                }
            }
    }
    
    // MARK: - Helpers
    
    /// Clamp offset to prevent panning beyond bounds (respects current scale)
    private func clamped(offset: CGSize, in geo: GeometryProxy, scale: CGFloat) -> CGSize {
        let w = geo.size.width, h = geo.size.height
        let maxX = max(0, (scale - 1) * w / 2)
        let maxY = max(0, (scale - 1) * h / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
    
    /// Handle double-tap to toggle zoom
    private func handleDoubleTap() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if scale > 1.0 {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.0
                lastScale = 2.0
            }
        }
    }
}

// MARK: - Preview
#Preview {
    let sampleImageData: Data = {
        #if os(macOS)
        let size = CGSize(width: 400, height: 600)
        let image = NSImage(size: size)
        image.lockFocus()
        
        let gradient = NSGradient(colors: [NSColor.blue, NSColor.purple])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        
        let text = "Sample Comic Page"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
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
            let colors = [UIColor.blue.cgColor, UIColor.purple.cgColor]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0.0, 1.0]
            )!
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            
            let text = "Sample Comic Page"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
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
    }()
    
    let samplePage = ComicPage(
        pageNumber: 1,
        imageData: sampleImageData,
        fileName: "sample_page.jpg"
    )
    
    return ComicPageView(page: samplePage)
}
