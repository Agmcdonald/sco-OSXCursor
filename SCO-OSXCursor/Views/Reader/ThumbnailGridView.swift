//
//  ThumbnailGridView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/8/25.
//

import SwiftUI

// MARK: - Thumbnail Grid View
@MainActor
struct ThumbnailGridView: View {
    let pages: [ComicPage]
    @Binding var currentPage: Int
    @Binding var isPresented: Bool
    
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 16)
    ]
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    // Tap outside to close
                    withAnimation {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("All Pages")
                        .font(Typography.h2)
                        .foregroundColor(TextColors.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.xl)
                
                Divider()
                    .background(BorderColors.subtle)
                
                // Thumbnail grid
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                                ThumbnailCell(
                                    page: page,
                                    pageNumber: index + 1,
                                    isCurrentPage: index == currentPage
                                )
                                .onTapGesture {
                                    withAnimation {
                                        currentPage = index
                                        isPresented = false
                                    }
                                }
                                .id(index)
                            }
                        }
                        .padding(Spacing.xl)
                    }
                    .onAppear {
                        // Scroll to current page when view appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(currentPage, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 800, maxHeight: .infinity)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
            .padding(Spacing.xxl)
        }
    }
}

// MARK: - Thumbnail Cell
@MainActor
struct ThumbnailCell: View {
    let page: ComicPage
    let pageNumber: Int
    let isCurrentPage: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail image
            ZStack {
                if let image = page.image {
                    #if os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    #else
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    #endif
                } else {
                    // Placeholder for unloaded pages
                    RoundedRectangle(cornerRadius: 8)
                        .fill(BackgroundColors.primary)
                        .frame(width: 100, height: 150)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        )
                }
                
                // Current page indicator
                if isCurrentPage {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(AccentColors.primary, lineWidth: 3)
                        .frame(width: 100, height: 150)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            
            // Page number
            Text("\(pageNumber)")
                .font(Typography.caption)
                .foregroundColor(isCurrentPage ? AccentColors.primary : TextColors.secondary)
                .fontWeight(isCurrentPage ? .bold : .regular)
        }
        .scaleEffect(isCurrentPage ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isCurrentPage)
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State private var currentPage = 5
        @State private var isPresented = true
        
        var body: some View {
            ZStack {
                Color.blue.ignoresSafeArea()
                
                ThumbnailGridView(
                    pages: (1...24).map { pageNum in
                        ComicPage(pageNumber: pageNum, imageData: Data(), fileName: "page\(pageNum).jpg")
                    },
                    currentPage: $currentPage,
                    isPresented: $isPresented
                )
            }
        }
    }
    
    return PreviewWrapper()
}

