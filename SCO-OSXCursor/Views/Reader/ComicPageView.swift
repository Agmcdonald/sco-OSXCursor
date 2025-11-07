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
    
    // Reset zoom when page changes
    private let pageID: UUID
    
    init(page: ComicPage) {
        self.page = page
        self.pageID = page.id
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()
                
                // Page image with zoom and pan
                if let image = page.image {
                    #if os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnificationGesture)
                        .gesture(dragGesture)
                        .onTapGesture(count: 2) {
                            handleDoubleTap()
                        }
                    #else
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnificationGesture)
                        .gesture(dragGesture)
                        .onTapGesture(count: 2) {
                            handleDoubleTap()
                        }
                    #endif
                } else {
                    // Fallback if image can't be loaded or is loading
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
        .onChange(of: pageID) { _ in
            // Reset zoom when page changes
            withAnimation(.easeInOut(duration: 0.3)) {
                scale = 1.0
                offset = .zero
            }
            lastScale = 1.0
            lastOffset = .zero
        }
    }
    
    // MARK: - Gestures
    
    /// Pinch to zoom gesture
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = lastScale * value
                // Limit zoom between 1x and 5x
                scale = min(max(newScale, 1.0), 5.0)
            }
            .onEnded { value in
                let newScale = lastScale * value
                scale = min(max(newScale, 1.0), 5.0)
                lastScale = scale
                
                // If zoomed out to minimum, reset offset
                if scale == 1.0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        offset = .zero
                    }
                    lastOffset = .zero
                }
            }
    }
    
    /// Drag to pan gesture (only when zoomed)
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only allow panning when zoomed in
                guard scale > 1.0 else { return }
                
                let newOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                
                offset = newOffset
            }
            .onEnded { value in
                guard scale > 1.0 else { return }
                
                lastOffset = offset
            }
    }
    
    // MARK: - Actions
    
    /// Handle double-tap to toggle zoom
    private func handleDoubleTap() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if scale > 1.0 {
                // Zoom out to fit
                scale = 1.0
                offset = .zero
                lastScale = 1.0
                lastOffset = .zero
            } else {
                // Zoom in to 2x
                scale = 2.0
                lastScale = 2.0
            }
        }
    }
}

// MARK: - Preview
#Preview {
    // Create a sample page for preview
    let sampleImageData: Data = {
        #if os(macOS)
        let size = CGSize(width: 400, height: 600)
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Draw gradient background
        let gradient = NSGradient(
            colors: [NSColor.blue, NSColor.purple]
        )
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        
        // Draw text
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
            // Draw gradient background
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
            
            // Draw text
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

