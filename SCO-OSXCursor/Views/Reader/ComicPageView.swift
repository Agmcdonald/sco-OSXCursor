//
//  ComicPageView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//
//  Single-page reader surface. Rendering is ComicPageImage; zoom, pan and
//  gesture handling live in ZoomableCanvas (shared with SpreadView so spreads
//  zoom as one canvas).
//

import SwiftUI
import os

// MARK: - Comic Page Image (rendering only, no gestures)

/// Renders one page image scaled to fit, or the loading fallback. Used by
/// ComicPageView (single page) and SpreadView (two pages on one canvas).
@MainActor
struct ComicPageImage: View {
    let page: ComicPage

    var body: some View {
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
                .accessibilityLabel(Text("Page \(page.pageNumber)"))
                .accessibilityAddTraits(.isImage)
        } else {
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
        }
    }
}

// MARK: - Comic Page View

@MainActor
struct ComicPageView: View {
    let page: ComicPage

    // Swipe callbacks provided by parent
    var onSwipeLeft: () -> Void = {}
    var onSwipeRight: () -> Void = {}

    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}

    /// Native pager mode (iOS): a UIKit pager (curl or slide scroll) owns the
    /// page-turn pan gesture, so our drag gesture must stand down while
    /// unzoomed — otherwise it claims the touch and the pager never tracks
    /// the finger. While zoomed (scale > 1.01) the drag re-engages for
    /// panning and the host disables its pan via `onZoomStateChanged`.
    var nativePagerMode: Bool = false
    /// Reports zoom state crossings so the pager host can yield its pan/scroll.
    var onZoomStateChanged: (Bool) -> Void = { _ in }

    /// Per-book zoom memory: the scale this page starts at (and returns to on
    /// page change). 1.0 = no remembered zoom.
    var initialScale: CGFloat = 1.0

    /// Only the displayed page posts reader-wide notifications (pager
    /// neighbors are alive off-screen and must stay mute).
    var isActive: Bool = true

    /// Interactive pager scrub handlers (see ZoomableCanvas). When set, the
    /// pager owns unzoomed horizontal drags and the page-turn decision.
    var onScrubChanged: ((CGFloat) -> Void)? = nil
    var onScrubEnded: ((CGFloat, CGFloat) -> Void)? = nil

    var body: some View {
        ZoomableCanvas(
            resetID: AnyHashable(page.id),
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onBeginDragging: onBeginDragging,
            onEndDragging: onEndDragging,
            onBeginPinching: onBeginPinching,
            onEndPinching: onEndPinching,
            nativePagerMode: nativePagerMode,
            onZoomStateChanged: onZoomStateChanged,
            initialScale: initialScale,
            isActive: isActive,
            onScrubChanged: onScrubChanged,
            onScrubEnded: onScrubEnded
        ) {
            ComicPageImage(page: page)
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
