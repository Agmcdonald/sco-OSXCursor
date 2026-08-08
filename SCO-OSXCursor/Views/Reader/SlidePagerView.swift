//
//  SlidePagerView.swift
//  SCO-OSXCursor
//
//  Native slide pager (iOS): UIPageViewController(.scroll) with an
//  inter-page gutter. A native UIScrollView owns the presentation position,
//  which is what gives the Panels feel — 1:1 finger tracking, flick
//  momentum, and jitter-free stop/reverse mid-slide. (The SwiftUI
//  InteractivePagerReader, still used on macOS, settles with a spring whose
//  model value lands before its pixels do, so a touch mid-settle jumped.)
//
//  Gesture ownership matches PageCurlView: the hosted page view stands down
//  its unzoomed drag (nativePagerMode) so the internal scroll view receives
//  the pan; while zoomed the cell re-engages its drag for panning and page
//  scrolling is disabled (onZoomStateChanged) until zoomed back out. Taps
//  stay with the global tap overlay in ComicReaderView.
//

#if os(iOS)
    import SwiftUI
    import UIKit

    // MARK: - Pure math (unit-testable)

    enum SlidePagerMath {
        /// Minimum horizontal distance for the boundary over-swipe (matches
        /// ZoomableCanvas.swipeThreshold)
        static let overswipeThreshold: CGFloat = 80

        /// Logical index one visual step away (+1 = visual right), or nil at
        /// a boundary. Manga/RTL flips reading order relative to visual order.
        static func neighborIndex(from index: Int, visualStep: Int, isRTL: Bool, count: Int) -> Int? {
            let candidate = index + (isRTL ? -visualStep : visualStep)
            return (0..<count).contains(candidate) ? candidate : nil
        }

        /// Classifies a swipe that ran off the end of the book. Returns the
        /// gesture step (+1 = swiped left) when the swipe is decisively
        /// horizontal, past threshold, and has NO neighbor in that direction —
        /// nil otherwise (the native scroll already handled it).
        static func boundaryOverswipeStep(
            dx: CGFloat, dy: CGFloat, index: Int, count: Int, isRTL: Bool
        ) -> Int? {
            guard abs(dx) > abs(dy), abs(dx) >= overswipeThreshold else { return nil }
            let gestureStep = dx < 0 ? +1 : -1
            guard
                neighborIndex(
                    from: index, visualStep: gestureStep, isRTL: isRTL, count: count) == nil
            else { return nil }
            return gestureStep
        }
    }

    // MARK: - Slide Pager Reader

    /// Generic native pager for the .slide transition — items are single pages
    /// (PagedReaderView) or whole spreads (SpreadReaderView).
    @MainActor
    struct SlidePagerReader<Item: Identifiable, Content: View>: View {
        let items: [Item]
        /// Logical index of the displayed item. User swipes write back on
        /// settle; external writes (scrubber, keys, tap zones) page over.
        @Binding var index: Int
        /// Manga/RTL: the *next* reading page sits to the visual LEFT.
        var isRTL: Bool = false
        /// Black spine gap between adjacent pages while sliding
        var gutter: CGFloat = 24
        /// Cheap staleness token computed around an index — when it changes
        /// (lazy page loads, zoom memory) the pager refreshes the displayed
        /// cell and drops its cached neighbors.
        var refreshSignature: (Int) -> String = { _ in "" }
        /// A decisive swipe past the first/last page, in gesture terms
        /// (+1 = swiped left). Routes to ReaderViewModel.turn so "Up Next"
        /// still surfaces at the end of the book.
        var onBoundaryTurn: (Int) -> Void = { _ in }
        /// Builds one item's view. `isActive` marks the displayed item; the
        /// zoom callback must be handed to the item's ZoomableCanvas so the
        /// pager can stop scrolling while zoomed.
        @ViewBuilder var content:
            (
                _ item: Item,
                _ isActive: Bool,
                _ onZoomChanged: @escaping (Bool) -> Void
            ) -> Content

        /// Mirrors the cells' zoom state so the boundary over-swipe stands
        /// down while zoomed (zoomed edge-swipes already report turns).
        @State private var isZoomed = false

        var body: some View {
            SlidePagerRepresentable(
                items: items,
                index: $index,
                isRTL: isRTL,
                gutter: gutter,
                refreshSignature: refreshSignature,
                onCellZoomChanged: { isZoomed = $0 },
                content: content
            )
            .simultaneousGesture(boundaryOverswipe)
        }

        /// The native scroll just bounces at the ends (no neighbor cell), so
        /// past-the-end swipes are classified here and reported as turns.
        private var boundaryOverswipe: some Gesture {
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard !isZoomed else { return }
                    guard
                        let step = SlidePagerMath.boundaryOverswipeStep(
                            dx: value.translation.width,
                            dy: value.translation.height,
                            index: index,
                            count: items.count,
                            isRTL: isRTL
                        )
                    else { return }
                    onBoundaryTurn(step)
                }
        }
    }

    // MARK: - Representable

    private struct SlidePagerRepresentable<Item: Identifiable, Content: View>:
        UIViewControllerRepresentable
    {
        let items: [Item]
        @Binding var index: Int
        let isRTL: Bool
        let gutter: CGFloat
        let refreshSignature: (Int) -> String
        let onCellZoomChanged: (Bool) -> Void
        let content: (Item, Bool, @escaping (Bool) -> Void) -> Content

        func makeUIViewController(context: Context) -> UIPageViewController {
            let pageVC = UIPageViewController(
                transitionStyle: .scroll,
                navigationOrientation: .horizontal,
                options: [.interPageSpacing: NSNumber(value: gutter)]
            )
            pageVC.delegate = context.coordinator
            pageVC.dataSource = context.coordinator
            pageVC.view.backgroundColor = .black

            // The .scroll style hosts its pan on an internal scroll view (the
            // top-level gestureRecognizers array is empty). Keep a handle for
            // zoom arbitration, and let the global tap overlay coexist.
            if let scrollView = pageVC.view.subviews.compactMap({ $0 as? UIScrollView }).first {
                context.coordinator.scrollView = scrollView
                scrollView.panGestureRecognizer.cancelsTouchesInView = false
            }

            if let firstVC = context.coordinator.hostingController(for: index) {
                context.coordinator.lastSignature = refreshSignature(index)
                pageVC.setViewControllers([firstVC], direction: .forward, animated: false)
            }
            return pageVC
        }

        func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
            // Keep the coordinator's parent fresh — the struct is copied on
            // every SwiftUI update (see PageCurlView for rationale).
            let coordinator = context.coordinator
            coordinator.parent = self

            guard !items.isEmpty else { return }
            let clamped = min(max(index, 0), items.count - 1)

            guard let currentVC = pageVC.viewControllers?.first as? SlideItemHost<Content>,
                currentVC.itemIndex < items.count
            else {
                // No cell yet (items were empty at creation) or the items
                // array was rebuilt shorter — install the current page fresh.
                if let vc = coordinator.hostingController(for: clamped) {
                    coordinator.lastSignature = refreshSignature(clamped)
                    pageVC.setViewControllers([vc], direction: .forward, animated: false)
                }
                return
            }
            let displayed = currentVC.itemIndex

            if displayed == index {
                // Same page — refresh the displayed cell in place when page
                // data lazy-loads or the remembered zoom changes, and drop the
                // stale neighbor cache (re-setting the same instance flushes
                // UIPageViewController's internal cache without a swap).
                let signature = refreshSignature(displayed)
                if signature != coordinator.lastSignature, coordinator.isSafeToReset,
                    let refreshed = coordinator.rootView(for: displayed, isActive: true)
                {
                    coordinator.lastSignature = signature
                    currentVC.rootView = refreshed
                    pageVC.setViewControllers([currentVC], direction: .forward, animated: false)
                }
                return
            }

            // Programmatic turn (tap zones, slider, thumbnails, keys)
            coordinator.jump(to: index, on: pageVC)
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, UIPageViewControllerDelegate, UIPageViewControllerDataSource {
            var parent: SlidePagerRepresentable?  // Struct is copied by value, no retain cycle risk
            var items: [Item] { parent?.items ?? [] }
            var isRTL: Bool { parent?.isRTL ?? false }

            weak var scrollView: UIScrollView?
            private(set) var isZoomed = false
            private var isTransitioning = false
            /// True while an animated PROGRAMMATIC turn is in flight — same
            /// re-entrancy hazard as PageCurlView.Coordinator.jump.
            private var isProgrammaticTurning = false
            /// refreshSignature at the last cell install — staleness check
            var lastSignature: String = ""

            init(_ parent: SlidePagerRepresentable) {
                self.parent = parent
            }

            /// Don't tear down cells while a user drag or an animated
            /// programmatic turn is in flight
            var isSafeToReset: Bool {
                guard !isTransitioning, !isProgrammaticTurning else { return false }
                if let scrollView,
                    scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
                {
                    return false
                }
                return true
            }

            func rootView(for itemIndex: Int, isActive: Bool) -> Content? {
                guard let parent, items.indices.contains(itemIndex) else { return nil }
                return parent.content(items[itemIndex], isActive) { [weak self] zoomed in
                    self?.setZoomed(zoomed)
                }
            }

            func hostingController(for itemIndex: Int) -> SlideItemHost<Content>? {
                guard
                    let root = rootView(
                        for: itemIndex, isActive: itemIndex == parent?.index)
                else { return nil }
                return SlideItemHost(rootView: root, itemIndex: itemIndex)
            }

            /// Called by a hosted cell when zoom crosses 1.01: zoomed pages
            /// pan with the finger, so page scrolling must yield. Uses
            /// isScrollEnabled — disabling the pan recognizer mid-touch would
            /// cancel its state.
            func setZoomed(_ zoomed: Bool) {
                guard zoomed != isZoomed else { return }
                isZoomed = zoomed
                scrollView?.isScrollEnabled = !zoomed
                parent?.onCellZoomChanged(zoomed)
            }

            /// Programmatic jump: adjacent pages animate a native slide; far
            /// jumps (slider scrubbing, thumbnails) swap instantly so the view
            /// never lags behind the control.
            func jump(to target: Int, on pageVC: UIPageViewController) {
                guard !isProgrammaticTurning, isSafeToReset,
                    let currentVC = pageVC.viewControllers?.first as? SlideItemHost<Content>
                else { return }
                let displayed = currentVC.itemIndex
                guard displayed != target,
                    let newVC = hostingController(for: target)
                else { return }

                lastSignature = parent?.refreshSignature(target) ?? ""

                guard abs(target - displayed) == 1 else {
                    pageVC.setViewControllers([newVC], direction: .forward, animated: false)
                    return
                }

                let advancing = target > displayed
                let direction: UIPageViewController.NavigationDirection =
                    (advancing != isRTL) ? .forward : .reverse
                isProgrammaticTurning = true
                pageVC.setViewControllers([newVC], direction: direction, animated: true) {
                    [weak self, weak pageVC] _ in
                    guard let self, let pageVC else { return }
                    // .scroll-style quirk: after an animated programmatic turn
                    // the internal cache can serve a stale neighbor — re-set
                    // the same instance non-animated to flush it.
                    DispatchQueue.main.async {
                        if let current = pageVC.viewControllers?.first {
                            pageVC.setViewControllers(
                                [current], direction: .forward, animated: false)
                        }
                        self.isProgrammaticTurning = false
                        // More jumps may have queued while animating — chase
                        // the latest.
                        if let latest = self.parent?.index, latest != target {
                            self.jump(to: latest, on: pageVC)
                        }
                    }
                }
            }

            // MARK: UIPageViewControllerDataSource

            // "Before" = the page revealed by a left-to-right drag: the visual
            // LEFT neighbor — in RTL that's the NEXT page in reading order.

            func pageViewController(
                _ pageViewController: UIPageViewController,
                viewControllerBefore viewController: UIViewController
            ) -> UIViewController? {
                guard let host = viewController as? SlideItemHost<Content>,
                    let neighbor = SlidePagerMath.neighborIndex(
                        from: host.itemIndex, visualStep: -1, isRTL: isRTL, count: items.count)
                else { return nil }
                return hostingController(for: neighbor)
            }

            func pageViewController(
                _ pageViewController: UIPageViewController,
                viewControllerAfter viewController: UIViewController
            ) -> UIViewController? {
                guard let host = viewController as? SlideItemHost<Content>,
                    let neighbor = SlidePagerMath.neighborIndex(
                        from: host.itemIndex, visualStep: +1, isRTL: isRTL, count: items.count)
                else { return nil }
                return hostingController(for: neighbor)
            }

            // MARK: UIPageViewControllerDelegate

            func pageViewController(
                _ pageViewController: UIPageViewController,
                willTransitionTo pendingViewControllers: [UIViewController]
            ) {
                isTransitioning = true
            }

            func pageViewController(
                _ pageViewController: UIPageViewController,
                didFinishAnimating finished: Bool,
                previousViewControllers: [UIViewController],
                transitionCompleted completed: Bool
            ) {
                isTransitioning = false
                // Ignore writebacks fired during a programmatic jump — its
                // completion handler owns the final state.
                guard !isProgrammaticTurning else { return }
                guard completed,
                    let host = pageViewController.viewControllers?.first as? SlideItemHost<Content>,
                    let parent
                else { return }

                let newIndex = host.itemIndex
                lastSignature = parent.refreshSignature(newIndex)
                // Promote the settled cell, demote the outgoing one — only
                // the displayed cell answers reader-wide zoom commands.
                if let promoted = rootView(for: newIndex, isActive: true) {
                    host.rootView = promoted
                }
                if let previous = previousViewControllers.first as? SlideItemHost<Content>,
                    let demoted = rootView(for: previous.itemIndex, isActive: false)
                {
                    previous.rootView = demoted
                }
                parent.index = newIndex
            }
        }
    }

    /// Hosts one item's SwiftUI view and remembers its logical index
    private final class SlideItemHost<Content: View>: UIHostingController<Content> {
        let itemIndex: Int

        init(rootView: Content, itemIndex: Int) {
            self.itemIndex = itemIndex
            super.init(rootView: rootView)
            view.backgroundColor = .black
        }

        @MainActor required dynamic init?(coder: NSCoder) {
            fatalError("init(coder:) not implemented")
        }
    }
#endif
