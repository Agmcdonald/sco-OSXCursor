//
//  ComicPageView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Combine
import SwiftUI
import os

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
    // Double-tap-to-unzoom detection (zoomed taps only)
    @State private var lastZoomedTapDate: Date? = nil
    @State private var pendingToggleWorkItem: DispatchWorkItem? = nil

    /// Two zoomed taps within this window = double tap → zoom out
    private let doubleTapWindow: TimeInterval = 0.3

    // Swipe callbacks provided by parent
    var onSwipeLeft: () -> Void = {}
    var onSwipeRight: () -> Void = {}

    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}

    /// Curl mode (iOS): UIPageViewController owns the page-turn pan gesture,
    /// so our drag gesture must stand down while unzoomed — otherwise it
    /// claims the touch and the interactive curl never tracks the finger.
    /// While zoomed (scale > 1.01) the drag re-engages for panning and the
    /// host disables the curl pan via `onZoomStateChanged`.
    var isCurlMode: Bool = false
    /// Reports zoom state crossings so the curl host can toggle its pan gesture.
    var onZoomStateChanged: (Bool) -> Void = { _ in }

    /// Per-book zoom memory: the scale this page starts at (and returns to on
    /// page change). 1.0 = no remembered zoom.
    var initialScale: CGFloat = 1.0

    /// Mask for the unified drag gesture: detached in curl mode while unzoomed.
    private var dragGestureMask: GestureMask {
        (isCurlMode && scale <= 1.01) ? .none : .all
    }

    // MARK: - FIXED GESTURE CONSTANTS

    /// Minimum horizontal distance for swipe recognition (points)
    /// FIXED: Absolute value instead of percentage-based (80pt vs 14% of width)
    private let swipeThreshold: CGFloat = 80

    /// Maximum vertical-to-horizontal ratio for swipe (0.75 = 75% vertical drift allowed)
    /// FIXED: More lenient than old 0.5 ratio
    private let maxDiagonalRatio: CGFloat = 0.75

    /// Edge width for tap zones in landscape orientation (points)
    private let landscapeEdgeWidth: CGFloat = 150

    /// Edge width for tap zones in portrait orientation (points)
    private let portraitEdgeWidth: CGFloat = 100

    // MARK: - Debug Logging

    @inline(__always) private func debugLog(_ msg: @autoclosure () -> String) {
        #if DEBUG
            AppLog.reader.debug("\(msg())")
        #endif
    }

    #if DEBUG
        private func logSwipe(dx: CGFloat, dy: CGFloat) {
            let angle = Int(atan2(dy, dx) * 180 / .pi)
            let normalizedAngle = (angle + 360) % 360
            let isHorizontal = abs(dx) > abs(dy)
            AppLog.reader.debug("[Swipe] dx=\(Int(dx)) dy=\(Int(dy)) angle=\(normalizedAngle)° horizontal:\(isHorizontal)")
        }
    #endif

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
                        .highPriorityGesture(unifiedDragGesture(geo: geo), including: dragGestureMask)  // High priority so it wins over overlay; stands down in curl mode while unzoomed
                        .simultaneousGesture(magnificationGesture(geo: geo))
                        .onReceive(NotificationCenter.default.publisher(for: .scoToggleZoom)) { _ in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if scale == 1.0 {
                                    scale = 2.0
                                    lastScale = 2.0
                                    offset = .zero
                                } else {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                }
                            }
                            // NOTE: deliberately NOT posting scoZoomScaleSettled
                            // here — this notification reaches every live page
                            // view (incl. curl-cached neighbors at other
                            // scales), so posting would save racing, conflicting
                            // values. Pinch + double-tap own the zoom memory.
                        }
                        .accessibilityLabel(Text("Page \(page.pageNumber)"))
                        .accessibilityAddTraits(.isImage)
                        .onAppear {
                            debugLog(
                                "\n========== NEW SESSION (\(platform)) Page \(page.pageNumber) =========="
                            )
                            debugLog(
                                "[\(platform)][ComicPageView] 🎬 Appeared for page \(page.pageNumber)"
                            )
                            debugLog(
                                "[\(platform)][ComicPageView] ✅ Gestures attached: magnify✅ unified✅ zoomNotification✅"
                            )
                            debugLog(
                                "[\(platform)][ComicPageView] 📐 geo.size=\(geo.size.width)x\(geo.size.height)"
                            )
                        }
                } else {
                    // Fallback while the page loads — keep the swipe gesture
                    // attached so page turns still work on unloaded pages
                    VStack(spacing: Spacing.lg) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("Loading page \(page.pageNumber)...")
                            .font(Typography.body)
                            .foregroundColor(TextColors.secondary)
                            .padding(.top, Spacing.md)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(unifiedDragGesture(geo: geo), including: dragGestureMask)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Apply the book's remembered zoom (no animation — the page
            // should simply open at its zoom level)
            if initialScale > 1.01 && scale == 1.0 {
                scale = initialScale
                lastScale = initialScale
            }
        }
        .onChange(of: page.id) {
            // Reset zoom to the book's remembered level when pages change
            withAnimation(.easeInOut(duration: 0.3)) {
                scale = max(1.0, initialScale)
                offset = .zero
            }
            lastScale = max(1.0, initialScale)
            lastOffset = .zero
            hasReportedDragStart = false
            hasReportedPinchStart = false
            // Don't let a pending zoomed-tap toggle fire after the page turned
            pendingToggleWorkItem?.cancel()
            pendingToggleWorkItem = nil
            lastZoomedTapDate = nil
            debugLog("[\(platform)][ComicPageView] 🔄 Page reset: scale→1.0, offset→.zero")
        }
        .onChange(of: scale) { _, newScale in
            let zoomed = newScale > 1.01
            // Curl host uses this to disable the curl pan while zoomed
            onZoomStateChanged(zoomed)
            // Reader container uses this to suspend swipe-down-to-dismiss
            NotificationCenter.default.post(
                name: .scoZoomStateChanged, object: nil, userInfo: ["zoomed": zoomed]
            )
        }
    }

    // MARK: - Gestures

    /// FIXED: Unified drag gesture handles swipes, taps, and panning
    /// Changes from old version:
    /// 1. Absolute swipe threshold (80pt) instead of percentage (14%)
    /// 2. More lenient diagonal tolerance (0.75 vs 0.5)
    /// 3. Fixed tap zones (100/150pt) instead of percentage (25%)
    /// 4. Only toggle controls in center zone, not on every tap
    private func unifiedDragGesture(geo: GeometryProxy) -> some Gesture {
        return DragGesture(minimumDistance: 0)  // Detect taps too
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                // Report drag start to container (only once per gesture)
                if !hasReportedDragStart
                    && (value.translation.width != 0 || value.translation.height != 0)
                {
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
                let dx = value.translation.width
                let dy = value.translation.height

                #if DEBUG
                    logSwipe(dx: dx, dy: dy)
                #endif

                // Report drag end to container
                hasReportedDragStart = false
                onEndDragging()
                debugLog(
                    "[\(platform)][ComicPageView] 📍 Drag ended: scale=\(scale), dx=\(dx), dy=\(dy)")

                // Compute distance once — used both by the zoom guard and iOS swipe fallback below
                let distance = hypot(dx, dy)

                // If zoomed, finish pan and return — UNLESS the pan was already
                // at the horizontal limit and this is a fresh swipe in the same
                // direction: then turn the page (Books/Panels behavior)
                if scale > 1.01 {
                    let maxX = max(0, (scale - 1) * geo.size.width / 2)
                    let isHorizontal = abs(dx) > abs(dy)
                    if isHorizontal && abs(dx) >= swipeThreshold {
                        if dx < 0 && lastOffset.width <= -maxX + 1 {
                            debugLog("[\(platform)][ComicPageView] ⬅️ Zoomed swipe at right edge → next page")
                            onSwipeLeft()
                            return
                        }
                        if dx > 0 && lastOffset.width >= maxX - 1 {
                            debugLog("[\(platform)][ComicPageView] ➡️ Zoomed swipe at left edge → previous page")
                            onSwipeRight()
                            return
                        }
                    }

                    debugLog("[\(platform)][ComicPageView] → Finishing pan (zoomed)")
                    let finalOffset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    lastOffset = clamped(offset: finalOffset, in: geo, scale: scale)

                    // When zoomed, a tiny movement is a tap. A quick second tap
                    // zooms back out (Books-style); a lone tap toggles controls
                    // after a short window so the double tap can preempt it.
                    if distance < 5 {
                        let now = Date()
                        if let last = lastZoomedTapDate, now.timeIntervalSince(last) < doubleTapWindow {
                            // Double tap → zoom out
                            debugLog("[\(platform)][ComicPageView] 👆👆 Double tap while zoomed → zoom out")
                            lastZoomedTapDate = nil
                            pendingToggleWorkItem?.cancel()
                            pendingToggleWorkItem = nil
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scale = 1.0
                                offset = .zero
                            }
                            lastScale = 1.0
                            lastOffset = .zero
                            // Deliberate zoom-out — clear the book's zoom memory
                            NotificationCenter.default.post(
                                name: .scoZoomScaleSettled, object: nil, userInfo: ["scale": CGFloat(1.0)]
                            )
                        } else {
                            // Possible single tap — toggle controls unless a
                            // second tap lands inside the window
                            debugLog("[\(platform)][ComicPageView] 👆 Tap while zoomed → toggle controls (debounced)")
                            lastZoomedTapDate = now
                            pendingToggleWorkItem?.cancel()
                            let work = DispatchWorkItem {
                                NotificationCenter.default.post(name: .scoToggleControls, object: nil)
                            }
                            pendingToggleWorkItem = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
                        }
                    }
                    return
                }

                #if os(iOS)
                    // NOTE: Pure taps are now handled globally by SpreadView's hit-zone
                    // overlay (full spread width). ComicPageView only handles swipes here.
                    // `distance` is declared above, before the zoom guard.

                    // Try swipe detection (taps fall through to SpreadView's overlay)
                    let isHorizontal = abs(dx) > abs(dy)

                    if isHorizontal && abs(dx) >= swipeThreshold {
                        let ratio = abs(dy) / abs(dx)

                        debugLog(
                            "[\(platform)][ComicPageView] 🔍 Swipe check: dx=\(dx), threshold=\(swipeThreshold), dy=\(dy), ratio=\(String(format: "%.3f", ratio))"
                        )

                        guard ratio < maxDiagonalRatio else {
                            debugLog(
                                "[\(platform)][ComicPageView] ❌ Too diagonal: ratio=\(String(format: "%.3f", ratio)) >= \(maxDiagonalRatio)"
                            )
                            // Diagonal gesture rejected — let SpreadView's overlay handle it
                            return
                        }

                        // Valid horizontal swipe!
                        if dx < 0 {
                            debugLog(
                                "[\(platform)][ComicPageView] ⬅️ SWIPE LEFT accepted: dx=\(dx), ratio=\(String(format: "%.3f", ratio))"
                            )
                            onSwipeLeft()
                        } else {
                            debugLog(
                                "[\(platform)][ComicPageView] ➡️ SWIPE RIGHT accepted: dx=\(dx), ratio=\(String(format: "%.3f", ratio))"
                            )
                            onSwipeRight()
                        }
                        return
                    }

                    // Short movement but not a qualifying swipe — let SpreadView handle it
                    if distance < swipeThreshold {
                        debugLog(
                            "[\(platform)][ComicPageView] ℹ️ Short drag (\(Int(distance))pt) — deferring to SpreadView overlay"
                        )
                    } else {
                        debugLog(
                            "[\(platform)][ComicPageView] ❌ Below swipe threshold: |dx|=\(abs(dx)) < \(swipeThreshold)"
                        )
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

                // Per-book zoom memory: a deliberate pinch settles the zoom
                NotificationCenter.default.post(
                    name: .scoZoomScaleSettled, object: nil, userInfo: ["scale": scale]
                )

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
        let w = geo.size.width
        let h = geo.size.height
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
                .foregroundColor: NSColor.white,
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
                    .foregroundColor: UIColor.white,
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
