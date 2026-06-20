//
//  VerticalScrollReaderView.swift
//  SCO-OSXCursor
//
//  Continuous vertical-strip reader, optimised for webtoons and
//  vertical-scroll comics. All pages are stacked in a single lazy
//  vertical scroll view. The HUD slider anchors the view to any page;
//  each page reports its appearance to keep currentPage in sync.
//

import SwiftUI

// MARK: - Vertical Scroll Reader View

@MainActor
struct VerticalScrollReaderView: View {
    let pages: [ComicPage]
    @Binding var currentPage: Int
    /// Column width as a fraction of the available screen width (0.3 … 1.0).
    /// 0.7 closely matches the comfortable proportions of standard single-page mode.
    @Binding var zoomScale: Double
    /// Known aspect ratios (height/width) per page index — keeps placeholder
    /// cells at their real height so the scroll position doesn't jump when
    /// pages load in or are evicted.
    var pageAspects: [Int: CGFloat] = [:]

    // Gesture state callbacks for container tap guard
    var onBeginDragging: () -> Void = {}
    var onEndDragging: () -> Void = {}
    var onBeginPinching: () -> Void = {}
    var onEndPinching: () -> Void = {}

    // Track which page the scroll view most recently made fully visible
    @State private var visiblePage: Int = 0
    // Track which half of the page is currently targeted (0 = top, 1 = middle)
    @State private var currentSubPage: Int = 0
    // Debounce rapid currentPage changes triggered by the HUD slider
    @State private var scrollTask: Task<Void, Never>? = nil

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            let columnWidth = geometry.size.width * zoomScale
                            
                            ZStack {
                                pageCell(page: page, index: index, columnWidth: columnWidth)
                                
                                // Invisible anchor points for half-page scrolling
                                VStack(spacing: 0) {
                                    Color.clear.frame(height: 1).id("page_\(index)_0")
                                    Spacer()
                                    Color.clear.frame(height: 1).id("page_\(index)_1")
                                    Spacer()
                                }
                            }
                            .frame(maxWidth: .infinity)  // Centre within the scroll view
                            .id("page_\(index)")
                            // Track when a page enters the viewport
                            .onAppear {
                                // Update the visible page tracker bidirectionally
                                visiblePage = index
                                if currentPage != index {
                                    currentPage = index
                                    currentSubPage = 0
                                }
                            }
                        }
                    }
                }
                // When the HUD slider or external code changes currentPage, scroll to it
                .onChange(of: currentPage) { _, newPage in
                    // If the page change came from natural scrolling (onAppear), don't snap
                    guard newPage != visiblePage else { return }
                    
                    scrollTask?.cancel()
                    scrollTask = Task {
                        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms debounce
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("page_\(newPage)", anchor: .top)
                        }
                        visiblePage = newPage
                    }
                }
                .onAppear {
                    // Jump to the starting page without animation
                    proxy.scrollTo("page_\(currentPage)", anchor: .top)
                    visiblePage = currentPage
                    currentSubPage = 0
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VerticalScrollHalfNotification"))) { notification in
                    guard let forward = notification.userInfo?["forward"] as? Bool else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if forward {
                            if currentSubPage == 0 {
                                currentSubPage = 1
                                proxy.scrollTo("page_\(currentPage)_1", anchor: .top)
                            } else {
                                currentSubPage = 0
                                if currentPage < pages.count - 1 {
                                    currentPage += 1
                                }
                                proxy.scrollTo("page_\(currentPage)_0", anchor: .top)
                            }
                        } else {
                            if currentSubPage == 1 {
                                currentSubPage = 0
                                proxy.scrollTo("page_\(currentPage)_0", anchor: .top)
                            } else {
                                currentSubPage = 1
                                if currentPage > 0 {
                                    currentPage -= 1
                                }
                                proxy.scrollTo("page_\(currentPage)_1", anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - Page Cell

    @ViewBuilder
    private func pageCell(page: ComicPage, index: Int, columnWidth: CGFloat) -> some View {
        // Use the remembered aspect ratio when available so placeholder and
        // loaded cells have the SAME height — otherwise the strip reflows and
        // the scroll position jumps as pages stream in.
        let knownAspect = pageAspects[index]

        // NO vertical padding and whole-point heights: webtoon strips are one
        // continuous drawing, so any gap (or sub-pixel fractional height)
        // renders as a black/hairline seam cutting through the artwork.
        Group {
            if let image = page.image {
                let imageAspect = image.size.width > 0
                    ? image.size.height / image.size.width
                    : 1.5
                let aspectRatio = knownAspect ?? imageAspect
                let cellHeight = (columnWidth * aspectRatio).rounded()

                #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: columnWidth, height: cellHeight)
                    .clipped()
                #else
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: columnWidth, height: cellHeight)
                    .clipped()
                #endif
            } else {
                // Placeholder for loading pages — sized with the real aspect
                // ratio when we know it
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: columnWidth, height: (columnWidth * (knownAspect ?? 1.5)).rounded())
                    .overlay(
                        ProgressView()
                            .tint(.white.opacity(0.4))
                    )
            }
        }
    }
}
