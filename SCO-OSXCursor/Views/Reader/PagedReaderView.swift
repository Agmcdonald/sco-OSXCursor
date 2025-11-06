//
//  PagedReaderView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

// MARK: - Paged Reader View
struct PagedReaderView: View {
    let pages: [ComicPage]
    @Binding var currentPage: Int
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                // Pages with swipe gesture
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        ComicPageView(page: page)
                            .tag(index)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))
                #endif
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

