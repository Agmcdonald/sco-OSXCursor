//
//  VerticalScrollReaderView.swift
//  SCO-OSXCursor
//
//  Continuous vertical-strip reader, optimised for webtoons and
//  vertical-scroll comics. All pages are stacked in a single lazy
//  vertical scroll view.
//
//  Positioning uses `.scrollPosition(id:)` + `.scrollTargetLayout()`:
//  the saved reading position is applied during the FIRST layout pass
//  (no post-hoc scrollTo racing lazy cell creation — the old approach
//  silently failed on long books, opening an 877-page PDF at page 1),
//  and the same binding both drives programmatic jumps (HUD slider,
//  thumbnails, restore) and reports the page the user scrolled to.
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

    /// The page id (`ComicPage.id`) anchored at the top of the viewport.
    /// Seeded from the saved reading position so the strip opens there.
    @State private var scrolledID: String?
    // Track which half of the page is currently targeted (0 = top, 1 = middle)
    @State private var currentSubPage: Int = 0
    // Column width at the moment a pinch began; nil = no pinch in flight
    @State private var pinchBaseZoom: Double? = nil

    init(
        pages: [ComicPage],
        currentPage: Binding<Int>,
        zoomScale: Binding<Double>,
        pageAspects: [Int: CGFloat] = [:],
        onBeginDragging: @escaping () -> Void = {},
        onEndDragging: @escaping () -> Void = {},
        onBeginPinching: @escaping () -> Void = {},
        onEndPinching: @escaping () -> Void = {}
    ) {
        self.pages = pages
        self._currentPage = currentPage
        self._zoomScale = zoomScale
        self.pageAspects = pageAspects
        self.onBeginDragging = onBeginDragging
        self.onEndDragging = onEndDragging
        self.onBeginPinching = onBeginPinching
        self.onEndPinching = onEndPinching
        // Anchor the strip to the saved page on the very first layout
        let start = currentPage.wrappedValue
        self._scrolledID = State(
            initialValue: pages.indices.contains(start) ? pages[start].id : nil)
    }

    /// `ComicPage.id` for a page index (stable "page-N" form, N = index + 1).
    private func pageID(at index: Int) -> String? {
        pages.indices.contains(index) ? pages[index].id : nil
    }

    /// Inverse of `pageID(at:)` — page index for a scroll-position id.
    private func pageIndex(for id: String?) -> Int? {
        guard let id, id.hasPrefix("page-"), let number = Int(id.dropFirst(5)) else {
            return nil
        }
        let index = number - 1
        return pages.indices.contains(index) ? index : nil
    }

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
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrolledID, anchor: .top)
                // HUD slider, thumbnail grid, or a late progress restore moved
                // the page — drive the strip there
                .onChange(of: currentPage) { _, newPage in
                    guard let target = pageID(at: newPage), target != scrolledID else { return }
                    currentSubPage = 0
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrolledID = target
                    }
                }
                // Natural scrolling — keep currentPage (and persisted
                // progress) in sync with what's at the top of the viewport
                .onChange(of: scrolledID) { _, newID in
                    guard let index = pageIndex(for: newID), index != currentPage else { return }
                    currentPage = index
                    currentSubPage = 0
                }
                .onAppear {
                    // Safety net: if the view first rendered before pages were
                    // available, seed the anchor as soon as we can
                    if scrolledID == nil {
                        scrolledID = pageID(at: currentPage)
                    }
                }
                .onChange(of: pages.count) {
                    if scrolledID == nil {
                        scrolledID = pageID(at: currentPage)
                    }
                }
                // Pinch (trackpad on Mac, two fingers on iPad) adjusts the
                // column width — same value the HUD slider drives, so the two
                // stay in sync and the result is persisted per book upstream.
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if pinchBaseZoom == nil {
                                pinchBaseZoom = zoomScale
                                onBeginPinching()
                            }
                            let proposed = (pinchBaseZoom ?? zoomScale) * Double(value)
                            zoomScale = min(max(proposed, 0.3), 1.0)
                        }
                        .onEnded { _ in
                            // Snap to the slider's 0.05 step grid for consistency
                            zoomScale = min(max((zoomScale / 0.05).rounded() * 0.05, 0.3), 1.0)
                            pinchBaseZoom = nil
                            onEndPinching()
                        }
                )
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
                                scrolledID = pageID(at: currentPage)
                            }
                        } else {
                            if currentSubPage == 1 {
                                currentSubPage = 0
                                scrolledID = pageID(at: currentPage)
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
