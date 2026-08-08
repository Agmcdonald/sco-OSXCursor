//
//  ZoomableCanvas.swift
//  SCO-OSXCursor
//
//  Panels-style zoom/pan engine shared by single-page and spread reading.
//
//  Behaviors (matched to the Panels reference videos):
//  - Pinch zooms around the pinch point: the content under the fingers stays
//    under the fingers, so no follow-up pan is needed.
//  - The zoom canvas is the full viewport — in spread mode both pages scale
//    together as one surface and the art crosses the center gutter.
//  - Scale is free during the gesture (soft rubber-band past the limits) and
//    springs to the clamped range on release.
//

import Combine
import SwiftUI
import os

// MARK: - Zoom Math (pure, unit-testable)

enum ReaderZoomMath {
    static let minScale: CGFloat = 1.0
    static let maxScale: CGFloat = 4.0
    /// Scales below this settle back to exactly 1.0 (prevents tiny lingering zooms)
    static let snapToFitBelow: CGFloat = 1.02

    /// Converts a gesture's `UnitPoint` anchor into center-origin view coordinates
    /// (the space `offset(_:)` works in).
    static func anchorPoint(startAnchor: UnitPoint, viewSize: CGSize) -> CGPoint {
        CGPoint(
            x: (startAnchor.x - 0.5) * viewSize.width,
            y: (startAnchor.y - 0.5) * viewSize.height
        )
    }

    /// Offset that keeps the content point currently shown at `anchor` fixed on
    /// screen while the scale changes from `fromScale` to `toScale`.
    ///
    /// Screen transform: p_screen = p_content * scale + offset. The content
    /// point under the anchor is c = (a - o0)/s0; keeping it pinned at `a`
    /// requires o = a - c * s.
    static func anchoredOffset(
        anchor: CGPoint,
        fromScale: CGFloat,
        toScale: CGFloat,
        committedOffset: CGSize
    ) -> CGSize {
        guard fromScale != 0 else { return committedOffset }
        let cx = (anchor.x - committedOffset.width) / fromScale
        let cy = (anchor.y - committedOffset.height) / fromScale
        return CGSize(
            width: anchor.x - cx * toScale,
            height: anchor.y - cy * toScale
        )
    }

    /// Soft-limits a raw gesture scale so pinching past the bounds moves the
    /// content with diminishing effect instead of hard-stopping (Panels feel).
    static func rubberBandScale(
        _ raw: CGFloat, min minS: CGFloat = minScale, max maxS: CGFloat = maxScale
    ) -> CGFloat {
        guard raw > 0 else { return minS }
        if raw < minS { return minS * pow(raw / minS, 0.55) }
        if raw > maxS { return maxS * pow(raw / maxS, 0.55) }
        return raw
    }

    /// Final scale after the pinch ends: clamped, with near-fit snapping to fit.
    static func settledScale(
        _ raw: CGFloat, min minS: CGFloat = minScale, max maxS: CGFloat = maxScale
    ) -> CGFloat {
        let clamped = Swift.min(Swift.max(raw, minS), maxS)
        return clamped < snapToFitBelow ? minS : clamped
    }

    /// Clamp a pan offset so the scaled content can't be dragged fully off screen.
    static func clampedOffset(_ offset: CGSize, viewSize: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(0, (scale - 1) * viewSize.width / 2)
        let maxY = max(0, (scale - 1) * viewSize.height / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    /// Pager settle decision after a horizontal scrub.
    /// Returns the *visual* step: +1 = advance to the page on the visual right
    /// (finger moved left), -1 = the visual left neighbor, 0 = settle back.
    ///
    /// Tuned light: a page turn should feel like a flick, not a haul — commit
    /// on a 15%-of-width stroke, or any modest fling (25% predicted travel)
    /// that agrees with the stroke direction.
    ///
    /// `positionX` is the strip's offset at release. Strokes chain (a drag can
    /// carry the page across in stages), so the strip may already be far from
    /// rest when a stroke ends: anything parked past halfway commits by
    /// position, and a stroke pulling BACK toward rest never re-commits
    /// outward. Defaults to `dragX` (single stroke from rest).
    static func pagerSettleStep(
        dragX: CGFloat, predictedDragX: CGFloat, viewportWidth: CGFloat,
        positionX: CGFloat? = nil
    ) -> Int {
        guard viewportWidth > 0 else { return 0 }
        let position = positionX ?? dragX
        let strokeThreshold = viewportWidth * 0.15
        let flingThreshold = viewportWidth * 0.25

        // Where the strip would land with the (damped) momentum tail
        let projected = position + (predictedDragX - dragX) * 0.4
        if projected <= -viewportWidth * 0.5 { return +1 }
        if projected >= viewportWidth * 0.5 { return -1 }

        // Light stroke-commit from near rest — only when the stroke moves
        // outward (same direction the strip is already displaced)
        let movingOutward = position == 0 || (dragX < 0) == (position < 0)
        if movingOutward {
            if abs(dragX) >= strokeThreshold { return dragX < 0 ? +1 : -1 }
            // A fling only counts when it agrees with the stroke direction
            if abs(predictedDragX) >= flingThreshold && predictedDragX * dragX > 0 {
                return dragX < 0 ? +1 : -1
            }
        }
        return 0
    }
}

// MARK: - Zoomable Canvas

/// Full-viewport zoom/pan/gesture surface for reader content. Wraps a single
/// page or a whole spread — whatever it wraps scales as one canvas.
///
/// Also owns the reader's unified drag gesture: pans while zoomed (with
/// edge-swipe page turns), and while unzoomed reports live horizontal scrub
/// motion to the interactive pager via `onScrubChanged`/`onScrubEnded` (or
/// falls back to classic swipe classification when no scrub handlers are set,
/// e.g. in curl mode).
@MainActor
struct ZoomableCanvas<Content: View>: View {
    /// Identity that resets zoom state when it changes (page/spread id)
    let resetID: AnyHashable

    var onSwipeLeft: () -> Void = {}
    var onSwipeRight: () -> Void = {}

    // Gesture state callbacks for the container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}

    /// Native pager mode (iOS): a UIKit pager (curl or slide scroll) owns the
    /// page-turn pan; our drag stands down while unzoomed (see ComicPageView).
    var nativePagerMode: Bool = false
    var onZoomStateChanged: (Bool) -> Void = { _ in }

    /// Per-book zoom memory: the scale this canvas starts at.
    var initialScale: CGFloat = 1.0

    /// Only the active (currently displayed) canvas posts reader-wide
    /// notifications and responds to zoom commands — pager neighbors stay mute.
    var isActive: Bool = true

    /// Live unzoomed horizontal drag, for the interactive pager (dx from gesture start).
    var onScrubChanged: ((CGFloat) -> Void)? = nil
    /// End of an unzoomed drag: (dx, predicted dx). When set, the pager owns
    /// the page-turn decision and classic swipe classification is skipped.
    var onScrubEnded: ((CGFloat, CGFloat) -> Void)? = nil

    @ViewBuilder var content: () -> Content

    // MARK: Zoom state

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var hasReportedDragStart = false
    @State private var hasReportedPinchStart = false
    /// Pinch anchor in center-origin view coordinates, captured at pinch start
    @State private var pinchAnchor: CGPoint = .zero
    // Double-tap-to-unzoom detection (zoomed taps only)
    @State private var lastZoomedTapDate: Date? = nil
    @State private var pendingToggleWorkItem: DispatchWorkItem? = nil

    /// Two zoomed taps within this window = double tap → zoom out
    private let doubleTapWindow: TimeInterval = 0.3
    /// Minimum horizontal distance for swipe recognition (points)
    private let swipeThreshold: CGFloat = 80
    /// Maximum vertical-to-horizontal ratio for swipe classification
    private let maxDiagonalRatio: CGFloat = 0.75

    /// Mask for the unified drag gesture: detached in native pager mode while
    /// unzoomed.
    private var dragGestureMask: GestureMask {
        (nativePagerMode && scale <= 1.01) ? .none : .all
    }

    @inline(__always) private func debugLog(_ msg: @autoclosure () -> String) {
        #if DEBUG
            AppLog.reader.debug("\(msg())")
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

                content()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .scaleEffect(scale)
                    .offset(offset)
                    .highPriorityGesture(unifiedDragGesture(geo: geo), including: dragGestureMask)
                    .simultaneousGesture(magnificationGesture(geo: geo))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .onReceive(NotificationCenter.default.publisher(for: .scoToggleZoom)) { _ in
            guard isActive else { return }
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
            // Deliberately NOT posting scoZoomScaleSettled here — pinch and
            // double-tap own the zoom memory (see original ComicPageView note).
        }
        .onAppear {
            // Apply the book's remembered zoom (no animation — the page
            // should simply open at its zoom level)
            if initialScale > 1.01 && scale == 1.0 {
                scale = initialScale
                lastScale = initialScale
            }
        }
        .onChange(of: resetID) {
            // Reset zoom to the book's remembered level when pages change
            withAnimation(.easeInOut(duration: 0.3)) {
                scale = max(1.0, initialScale)
                offset = .zero
            }
            lastScale = max(1.0, initialScale)
            lastOffset = .zero
            hasReportedDragStart = false
            hasReportedPinchStart = false
            pendingToggleWorkItem?.cancel()
            pendingToggleWorkItem = nil
            lastZoomedTapDate = nil
            debugLog("[\(platform)][ZoomableCanvas] 🔄 Reset: scale→\(max(1.0, initialScale)), offset→.zero")
        }
        .onChange(of: scale) { _, newScale in
            let zoomed = newScale > 1.01
            // Curl host uses this to disable the curl pan while zoomed
            onZoomStateChanged(zoomed)
            guard isActive else { return }
            // Reader container uses this to suspend swipe-down-to-dismiss
            NotificationCenter.default.post(
                name: .scoZoomStateChanged, object: nil, userInfo: ["zoomed": zoomed]
            )
        }
    }

    // MARK: - Unified drag: pan (zoomed) / pager scrub or swipe (unzoomed) / taps

    private func unifiedDragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !hasReportedDragStart
                    && (value.translation.width != 0 || value.translation.height != 0)
                {
                    hasReportedDragStart = true
                    onBeginDragging()
                }

                if scale > 1.01 {
                    // PAN while zoomed
                    let newOffset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    offset = ReaderZoomMath.clampedOffset(newOffset, viewSize: geo.size, scale: scale)
                } else if let onScrubChanged {
                    // Unzoomed: drive the interactive pager 1:1 with the finger
                    onScrubChanged(value.translation.width)
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height

                hasReportedDragStart = false
                onEndDragging()
                debugLog("[\(platform)][ZoomableCanvas] 📍 Drag ended: scale=\(scale), dx=\(dx), dy=\(dy)")

                let distance = hypot(dx, dy)

                // If zoomed, finish pan — UNLESS the pan was already at the
                // horizontal limit and this is a fresh swipe in the same
                // direction: then turn the page (Books/Panels behavior)
                if scale > 1.01 {
                    let maxX = max(0, (scale - 1) * geo.size.width / 2)
                    let isHorizontal = abs(dx) > abs(dy)
                    if isHorizontal && abs(dx) >= swipeThreshold {
                        if dx < 0 && lastOffset.width <= -maxX + 1 {
                            debugLog("[\(platform)][ZoomableCanvas] ⬅️ Zoomed swipe at right edge → next page")
                            onSwipeLeft()
                            return
                        }
                        if dx > 0 && lastOffset.width >= maxX - 1 {
                            debugLog("[\(platform)][ZoomableCanvas] ➡️ Zoomed swipe at left edge → previous page")
                            onSwipeRight()
                            return
                        }
                    }

                    let finalOffset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    lastOffset = ReaderZoomMath.clampedOffset(finalOffset, viewSize: geo.size, scale: scale)

                    // When zoomed, a tiny movement is a tap. A quick second tap
                    // zooms back out; a lone tap toggles controls after a short
                    // window so the double tap can preempt it.
                    if distance < 5 {
                        handleZoomedTap()
                    }
                    return
                }

                // Unzoomed with a pager attached: the pager decides the turn
                if let onScrubEnded {
                    onScrubEnded(dx, value.predictedEndTranslation.width)
                    return
                }

                #if os(iOS)
                    // Classic swipe classification (curl and non-slide transitions).
                    // Pure taps are handled globally by the reader's hit-zone overlay.
                    let isHorizontal = abs(dx) > abs(dy)

                    if isHorizontal && abs(dx) >= swipeThreshold {
                        let ratio = abs(dy) / abs(dx)
                        guard ratio < maxDiagonalRatio else {
                            debugLog("[\(platform)][ZoomableCanvas] ❌ Too diagonal (ratio \(String(format: "%.3f", ratio)))")
                            return
                        }
                        if dx < 0 {
                            debugLog("[\(platform)][ZoomableCanvas] ⬅️ SWIPE LEFT accepted")
                            onSwipeLeft()
                        } else {
                            debugLog("[\(platform)][ZoomableCanvas] ➡️ SWIPE RIGHT accepted")
                            onSwipeRight()
                        }
                        return
                    }

                    if distance < swipeThreshold {
                        debugLog("[\(platform)][ZoomableCanvas] ℹ️ Short drag (\(Int(distance))pt) — deferring to tap overlay")
                    }
                #endif
            }
    }

    private func handleZoomedTap() {
        let now = Date()
        if let last = lastZoomedTapDate, now.timeIntervalSince(last) < doubleTapWindow {
            debugLog("[\(platform)][ZoomableCanvas] 👆👆 Double tap while zoomed → zoom out")
            lastZoomedTapDate = nil
            pendingToggleWorkItem?.cancel()
            pendingToggleWorkItem = nil
            withAnimation(.easeInOut(duration: 0.3)) {
                scale = 1.0
                offset = .zero
            }
            lastScale = 1.0
            lastOffset = .zero
            if isActive {
                // Deliberate zoom-out — clear the book's zoom memory
                NotificationCenter.default.post(
                    name: .scoZoomScaleSettled, object: nil, userInfo: ["scale": CGFloat(1.0)]
                )
            }
        } else {
            debugLog("[\(platform)][ZoomableCanvas] 👆 Tap while zoomed → toggle controls (debounced)")
            lastZoomedTapDate = now
            pendingToggleWorkItem?.cancel()
            let work = DispatchWorkItem {
                NotificationCenter.default.post(name: .scoToggleControls, object: nil)
            }
            pendingToggleWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
        }
    }

    // MARK: - Pinch: anchored at the pinch point, free during gesture

    private func magnificationGesture(geo: GeometryProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !hasReportedPinchStart {
                    hasReportedPinchStart = true
                    onBeginPinching()
                    // Anchor where the fingers went down — the content point
                    // there stays under the fingers for the whole gesture
                    pinchAnchor = ReaderZoomMath.anchorPoint(
                        startAnchor: value.startAnchor, viewSize: geo.size
                    )
                }

                let raw = lastScale * value.magnification
                let newScale = ReaderZoomMath.rubberBandScale(raw)
                scale = newScale
                // Free movement during the gesture (no clamping) — Panels feel
                offset = ReaderZoomMath.anchoredOffset(
                    anchor: pinchAnchor,
                    fromScale: lastScale,
                    toScale: newScale,
                    committedOffset: lastOffset
                )
            }
            .onEnded { value in
                hasReportedPinchStart = false
                onEndPinching()

                let raw = lastScale * value.magnification
                let finalScale = ReaderZoomMath.settledScale(raw)
                let anchoredFinal = ReaderZoomMath.anchoredOffset(
                    anchor: pinchAnchor,
                    fromScale: lastScale,
                    toScale: finalScale,
                    committedOffset: lastOffset
                )
                let finalOffset =
                    finalScale <= 1.0
                    ? .zero
                    : ReaderZoomMath.clampedOffset(anchoredFinal, viewSize: geo.size, scale: finalScale)

                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    scale = finalScale
                    offset = finalOffset
                }
                lastScale = finalScale
                lastOffset = finalOffset

                debugLog("[\(platform)][ZoomableCanvas] ✅ Pinch ended: final scale=\(finalScale)")

                if isActive {
                    // Per-book zoom memory: a deliberate pinch settles the zoom
                    NotificationCenter.default.post(
                        name: .scoZoomScaleSettled, object: nil, userInfo: ["scale": finalScale]
                    )
                }
            }
    }
}
