//
//  SpreadReaderView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/8/25.
//

import SwiftUI

// MARK: - Spread Reader View (Two-Page Display)
@MainActor
struct SpreadReaderView: View {
    let spreads: [PageSpread]
    @Binding var currentSpreadIndex: Int
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()
                
                // Spread pages with TabView
                TabView(selection: $currentSpreadIndex) {
                    ForEach(spreads) { spread in
                        SpreadView(spread: spread)
                            .tag(spread.spreadIndex)
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

// MARK: - Single Spread View
@MainActor
struct SpreadView: View {
    let spread: PageSpread
    
    var body: some View {
        GeometryReader { geometry in
            if spread.isSinglePage {
                // Single page - center it
                ComicPageView(page: spread.leftPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Two pages side by side
                HStack(spacing: 0) {
                    ComicPageView(page: spread.leftPage)
                        .frame(width: geometry.size.width / 2)
                    
                    if let rightPage = spread.rightPage {
                        ComicPageView(page: rightPage)
                            .frame(width: geometry.size.width / 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                )
            ]
            
            return SpreadReaderView(
                spreads: sampleSpreads,
                currentSpreadIndex: $currentSpread
            )
        }
    }
    
    return PreviewWrapper()
}

