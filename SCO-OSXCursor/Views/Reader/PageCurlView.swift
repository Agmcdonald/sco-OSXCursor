//
//  PageCurlView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//
//  Apple Books-style interactive page curl.
//
//  Gesture ownership in curl mode:
//  - UIPageViewController's PAN gives the finger-tracked curl (drag the page
//    the whole way, release to complete or cancel). The hosted ComicPageView
//    stands down its own drag gesture while unzoomed (isCurlMode) so the pan
//    actually receives the touch.
//  - UIPageViewController's TAP is disabled: edge taps are handled by the
//    global tap overlay in ComicReaderView (15% zones), which turns the page
//    via the currentPage binding → setViewControllers(animated: true), i.e.
//    an animated curl. Keeping both enabled double-fired edge taps.
//  - Pinch zoom is two-finger so it coexists with the one-finger curl pan.
//    While zoomed, the page view re-engages its drag for panning and the
//    curl pan is disabled (onZoomStateChanged) until zoomed back out.

#if os(iOS)
import UIKit
import SwiftUI

struct PageCurlView: UIViewControllerRepresentable {
    let pages: [ComicPage]
    @Binding var currentPage: Int
    /// Manga/RTL: the story advances when the finger drags left-to-right
    /// (curl from the left edge), so neighbor lookups and animation
    /// directions are mirrored. `currentPage` stays in reading order.
    var isRTL: Bool = false
    /// Per-book zoom memory — pages open at this scale
    var initialScale: CGFloat = 1.0

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal
        )
        pageVC.delegate = context.coordinator
        pageVC.dataSource = context.coordinator

        for recognizer in pageVC.gestureRecognizers {
            // Let the SwiftUI tap overlay coexist with the curl gestures
            recognizer.cancelsTouchesInView = false
            // Edge taps are the overlay's job — disable the built-in tap so
            // a single tap doesn't turn the page twice
            if let tap = recognizer as? UITapGestureRecognizer {
                tap.isEnabled = false
            }
            // Keep a handle on the pan so we can disable it while zoomed
            if let pan = recognizer as? UIPanGestureRecognizer {
                context.coordinator.panRecognizer = pan
            }
        }

        if let firstVC = context.coordinator.viewController(for: currentPage) {
            context.coordinator.lastLoadSignature = context.coordinator.loadSignature(around: currentPage)
            context.coordinator.lastAppliedInitialScale = initialScale
            pageVC.setViewControllers([firstVC], direction: .forward, animated: false)
        }

        return pageVC
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        // Keep the coordinator's parent fresh — the struct is copied on every
        // SwiftUI update, so without this the coordinator would forever hold
        // the ORIGINAL pages array (placeholders that never fill in).
        let coordinator = context.coordinator
        coordinator.parent = self

        guard let currentVC = pageVC.viewControllers?.first as? PageHostingController,
              currentVC.index >= 0, currentVC.index < coordinator.pages.count
        else { return }
        let currentIndex = currentVC.index

        if currentIndex == currentPage {
            // Same page — swap in fresh VCs when page data has lazy-loaded
            // (flushes stale spinner neighbors) or when the remembered zoom
            // changed while unzoomed (cached VCs hold the old initial scale).
            // Never flush mid-zoom: it would reset the user's pan position.
            let signature = coordinator.loadSignature(around: currentIndex)
            let signatureChanged = signature != coordinator.lastLoadSignature
            let scaleChanged = coordinator.lastAppliedInitialScale != initialScale && !coordinator.isZoomed
            if signatureChanged || scaleChanged,
               coordinator.isSafeToReset,
               let newVC = coordinator.viewController(for: currentIndex)
            {
                coordinator.lastLoadSignature = signature
                coordinator.lastAppliedInitialScale = initialScale
                // Fresh VCs start at the remembered scale; pan state resyncs
                // via onZoomStateChanged from the new page view
                coordinator.setZoomed(false)
                pageVC.setViewControllers([newVC], direction: .forward, animated: false)
            }
            return
        }

        // Programmatic turn (tap zones, slider, thumbnails) — animated curl.
        // Re-entrancy-guarded so the jumped-to page's lazy load can't restart
        // the animation and revert the jump.
        coordinator.jump(to: currentPage, on: pageVC)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIPageViewControllerDelegate, UIPageViewControllerDataSource {
        var parent: PageCurlView?  // Struct is copied by value, no retain cycle risk
        var pages: [ComicPage] { parent?.pages ?? [] }
        var isRTL: Bool { parent?.isRTL ?? false }
        var initialScale: CGFloat { parent?.initialScale ?? 1.0 }

        weak var panRecognizer: UIPanGestureRecognizer?
        private(set) var isZoomed = false
        private var isTransitioning = false
        /// True while an animated PROGRAMMATIC turn (tap zone, slider, thumbnail)
        /// is in flight. `setViewControllers(animated:)` is async, and the
        /// jumped-to page's lazy load fires @Published changes that re-invoke
        /// updateUIViewController mid-animation; without this guard each re-entry
        /// starts another overlapping curl and UIPageViewController snaps back.
        private var isProgrammaticTurning = false
        /// isLoaded states of (prev, current, next) at last VC reset —
        /// changes mean cached neighbor VCs may be stale
        var lastLoadSignature: [Bool] = []
        /// initialScale at the last VC reset — zoom-memory staleness check
        var lastAppliedInitialScale: CGFloat = 1.0

        init(_ parent: PageCurlView) {
            self.parent = parent
        }

        /// Don't tear down view controllers while a user curl OR an animated
        /// programmatic turn is in flight
        var isSafeToReset: Bool {
            guard !isTransitioning, !isProgrammaticTurning else { return false }
            if let pan = panRecognizer, pan.state == .began || pan.state == .changed {
                return false
            }
            return true
        }

        /// Animate a programmatic jump to `target`, guarding against the
        /// re-entrancy that made thumbnail/slider jumps revert. Chases the
        /// latest target if more jumps land during the animation.
        func jump(to target: Int, on pageVC: UIPageViewController) {
            guard !isProgrammaticTurning, isSafeToReset,
                  let currentVC = pageVC.viewControllers?.first as? PageHostingController
            else { return }
            let displayed = currentVC.index
            guard displayed != target,
                  let newVC = viewController(for: target) else { return }

            let advancing = target > displayed
            let direction: UIPageViewController.NavigationDirection =
                (advancing != isRTL) ? .forward : .reverse
            lastLoadSignature = loadSignature(around: target)
            lastAppliedInitialScale = initialScale
            setZoomed(false)
            isProgrammaticTurning = true
            pageVC.setViewControllers([newVC], direction: direction, animated: true) {
                [weak self, weak pageVC] _ in
                guard let self, let pageVC else { return }
                self.isProgrammaticTurning = false
                // More jumps may have queued while animating — chase the latest.
                if let latest = self.parent?.currentPage, latest != target {
                    self.jump(to: latest, on: pageVC)
                }
            }
        }

        /// isLoaded for prev/current/next — cheap staleness check
        func loadSignature(around index: Int) -> [Bool] {
            [index - 1, index, index + 1].compactMap { i in
                (i >= 0 && i < pages.count) ? pages[i].isLoaded : nil
            }
        }

        /// Called by the hosted ComicPageView when zoom crosses 1.01:
        /// zoomed pages pan with the finger, so the curl pan must yield
        func setZoomed(_ zoomed: Bool) {
            guard zoomed != isZoomed else { return }
            isZoomed = zoomed
            panRecognizer?.isEnabled = !zoomed
        }

        /// Zoomed swipe-at-edge turns — drives the binding, which animates
        /// the curl via updateUIViewController. Delta is in GESTURE terms
        /// (swipe left = +1); RTL inverts it to reading order, matching
        /// ReaderViewModel.turn(by:).
        func requestTurn(_ delta: Int) {
            guard let parent = parent else { return }
            let target = parent.currentPage + (isRTL ? -delta : delta)
            guard target >= 0 && target < pages.count else { return }
            parent.currentPage = target
        }

        func viewController(for index: Int) -> UIViewController? {
            guard index >= 0 && index < pages.count else { return nil }
            return PageHostingController(page: pages[index], index: index, coordinator: self)
        }

        // "Before" = the page revealed by a left-to-right drag. In RTL
        // that's the NEXT page in reading order; LTR it's the previous.

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let hostingVC = viewController as? PageHostingController else { return nil }
            return self.viewController(for: hostingVC.index + (isRTL ? 1 : -1))
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let hostingVC = viewController as? PageHostingController else { return nil }
            return self.viewController(for: hostingVC.index + (isRTL ? -1 : 1))
        }

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isTransitioning = true
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            isTransitioning = false
            // Ignore writebacks fired during a programmatic jump — its completion
            // handler owns the final state; a stale index here would revert it.
            guard !isProgrammaticTurning else { return }
            guard completed,
                  let currentVC = pageViewController.viewControllers?.first as? PageHostingController,
                  let parent = parent else { return }

            lastLoadSignature = loadSignature(around: currentVC.index)
            parent.currentPage = currentVC.index
        }
    }

    class PageHostingController: UIHostingController<ComicPageView> {
        let page: ComicPage
        let index: Int

        init(page: ComicPage, index: Int, coordinator: Coordinator) {
            self.page = page
            self.index = index
            super.init(rootView: ComicPageView(
                page: page,
                onSwipeLeft: { [weak coordinator] in coordinator?.requestTurn(+1) },
                onSwipeRight: { [weak coordinator] in coordinator?.requestTurn(-1) },
                nativePagerMode: true,
                onZoomStateChanged: { [weak coordinator] zoomed in
                    coordinator?.setZoomed(zoomed)
                },
                initialScale: coordinator.initialScale
            ))
            view.backgroundColor = .black
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) not implemented")
        }
    }
}

// MARK: - Spread Curl View (two-page, spine at center — Apple Books landscape)
//
// UIPageViewController with spineLocation .mid shows two view controllers at
// once and curls them as a bound book: the back of the curling page is the
// next page (isDoubleSided is mandatory for .mid). Each half-spread page gets
// its own "slot": slot = spreadIndex * 2 + (0 = left | 1 = right). Spreads
// with no right page (e.g. a cover) get a black filler slot so pairs stay
// aligned. Gesture ownership matches PageCurlView: native pan = interactive
// curl, native tap disabled (zone taps come through the binding), pinch zoom
// disables the curl pan while zoomed.

struct SpreadCurlView: UIViewControllerRepresentable {
    let spreads: [PageSpread]
    @Binding var currentSpreadIndex: Int
    /// Manga/RTL: mirrored drags and animation direction (see PageCurlView)
    var isRTL: Bool = false
    /// Per-book zoom memory — pages open at this scale
    var initialScale: CGFloat = 1.0

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.mid.rawValue)]
        )
        pageVC.isDoubleSided = true
        pageVC.delegate = context.coordinator
        pageVC.dataSource = context.coordinator

        for recognizer in pageVC.gestureRecognizers {
            recognizer.cancelsTouchesInView = false
            if let tap = recognizer as? UITapGestureRecognizer {
                tap.isEnabled = false
            }
            if let pan = recognizer as? UIPanGestureRecognizer {
                context.coordinator.panRecognizer = pan
            }
        }

        if let pair = context.coordinator.viewControllerPair(forSpread: currentSpreadIndex) {
            context.coordinator.lastLoadSignature = context.coordinator.loadSignature(around: currentSpreadIndex)
            context.coordinator.lastAppliedInitialScale = initialScale
            pageVC.setViewControllers(pair, direction: .forward, animated: false)
        }

        return pageVC
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        guard let firstSlot = (pageVC.viewControllers?.first as? SpreadCurlSlot)?.slotIndex,
              !coordinator.spreads.isEmpty
        else { return }
        let displayedSpread = firstSlot / 2

        if displayedSpread == currentSpreadIndex {
            // Same spread — flush stale VCs on lazy-load or on a remembered-
            // zoom change while unzoomed (see PageCurlView for rationale)
            let signature = coordinator.loadSignature(around: displayedSpread)
            let signatureChanged = signature != coordinator.lastLoadSignature
            let scaleChanged = coordinator.lastAppliedInitialScale != initialScale && !coordinator.isZoomed
            if signatureChanged || scaleChanged,
               coordinator.isSafeToReset,
               let pair = coordinator.viewControllerPair(forSpread: displayedSpread)
            {
                coordinator.lastLoadSignature = signature
                coordinator.lastAppliedInitialScale = initialScale
                coordinator.setZoomed(false)
                pageVC.setViewControllers(pair, direction: .forward, animated: false)
            }
            return
        }

        // Programmatic turn (tap zones, slider, thumbnails) — animated curl.
        // Re-entrancy-guarded so the jumped-to spread's lazy load can't restart
        // the animation and revert the jump.
        coordinator.jump(to: currentSpreadIndex, on: pageVC)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIPageViewControllerDelegate, UIPageViewControllerDataSource {
        var parent: SpreadCurlView?
        var spreads: [PageSpread] { parent?.spreads ?? [] }
        var isRTL: Bool { parent?.isRTL ?? false }
        var initialScale: CGFloat { parent?.initialScale ?? 1.0 }

        weak var panRecognizer: UIPanGestureRecognizer?
        private(set) var isZoomed = false
        private var isTransitioning = false
        /// True while an animated PROGRAMMATIC spread turn is in flight — see
        /// PageCurlView.Coordinator for the re-entrancy rationale.
        private var isProgrammaticTurning = false
        var lastLoadSignature: [Bool] = []
        /// initialScale at the last VC reset — zoom-memory staleness check
        var lastAppliedInitialScale: CGFloat = 1.0

        init(_ parent: SpreadCurlView) {
            self.parent = parent
        }

        var isSafeToReset: Bool {
            guard !isTransitioning, !isProgrammaticTurning else { return false }
            if let pan = panRecognizer, pan.state == .began || pan.state == .changed {
                return false
            }
            return true
        }

        /// Animate a programmatic jump to `target` spread, guarded against the
        /// re-entrancy that made thumbnail/slider jumps revert.
        func jump(to target: Int, on pageVC: UIPageViewController) {
            guard !isProgrammaticTurning, isSafeToReset,
                  let firstSlot = (pageVC.viewControllers?.first as? SpreadCurlSlot)?.slotIndex
            else { return }
            let displayed = firstSlot / 2
            guard displayed != target,
                  let pair = viewControllerPair(forSpread: target) else { return }

            let advancing = target > displayed
            let direction: UIPageViewController.NavigationDirection =
                (advancing != isRTL) ? .forward : .reverse
            lastLoadSignature = loadSignature(around: target)
            lastAppliedInitialScale = initialScale
            setZoomed(false)
            isProgrammaticTurning = true
            pageVC.setViewControllers(pair, direction: direction, animated: true) {
                [weak self, weak pageVC] _ in
                guard let self, let pageVC else { return }
                self.isProgrammaticTurning = false
                if let latest = self.parent?.currentSpreadIndex, latest != target {
                    self.jump(to: latest, on: pageVC)
                }
            }
        }

        /// isLoaded for every page in spreads idx-1...idx+1
        func loadSignature(around spreadIndex: Int) -> [Bool] {
            (spreadIndex - 1...spreadIndex + 1).flatMap { i -> [Bool] in
                guard i >= 0 && i < spreads.count else { return [] }
                let spread = spreads[i]
                var sig = [spread.leftPage.isLoaded]
                if let right = spread.rightPage { sig.append(right.isLoaded) }
                return sig
            }
        }

        func setZoomed(_ zoomed: Bool) {
            guard zoomed != isZoomed else { return }
            isZoomed = zoomed
            panRecognizer?.isEnabled = !zoomed
        }

        /// Zoomed swipe-at-edge turns — one delta = one spread. Delta is in
        /// GESTURE terms (swipe left = +1); RTL inverts to reading order.
        func requestTurn(_ delta: Int) {
            guard let parent = parent else { return }
            let target = parent.currentSpreadIndex + (isRTL ? -delta : delta)
            guard target >= 0 && target < spreads.count else { return }
            parent.currentSpreadIndex = target
        }

        // MARK: Slots

        private var slotCount: Int { spreads.count * 2 }

        /// Page for a slot, or nil for filler (missing right page)
        private func page(atSlot slot: Int) -> ComicPage? {
            let spreadIndex = slot / 2
            guard spreadIndex >= 0 && spreadIndex < spreads.count else { return nil }
            return slot % 2 == 0 ? spreads[spreadIndex].leftPage : spreads[spreadIndex].rightPage
        }

        private func viewController(forSlot slot: Int) -> UIViewController? {
            guard slot >= 0 && slot < slotCount else { return nil }
            if let page = page(atSlot: slot) {
                return SpreadPageHostingController(page: page, slotIndex: slot, coordinator: self)
            }
            return SpreadFillerViewController(slotIndex: slot)
        }

        func viewControllerPair(forSpread spreadIndex: Int) -> [UIViewController]? {
            guard spreadIndex >= 0 && spreadIndex < spreads.count,
                  let left = viewController(forSlot: spreadIndex * 2),
                  let right = viewController(forSlot: spreadIndex * 2 + 1)
            else { return nil }
            return [left, right]
        }

        // MARK: UIPageViewControllerDataSource

        // "Before" = revealed by a left-to-right drag → next slot in RTL

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let slot = (viewController as? SpreadCurlSlot)?.slotIndex else { return nil }
            return self.viewController(forSlot: slot + (isRTL ? 1 : -1))
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let slot = (viewController as? SpreadCurlSlot)?.slotIndex else { return nil }
            return self.viewController(forSlot: slot + (isRTL ? -1 : 1))
        }

        // MARK: UIPageViewControllerDelegate

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isTransitioning = true
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            isTransitioning = false
            // Ignore writebacks fired during a programmatic jump — its completion
            // handler owns the final state; a stale index here would revert it.
            guard !isProgrammaticTurning else { return }
            guard completed,
                  let slot = (pageViewController.viewControllers?.first as? SpreadCurlSlot)?.slotIndex,
                  let parent = parent else { return }

            let newSpread = slot / 2
            lastLoadSignature = loadSignature(around: newSpread)
            parent.currentSpreadIndex = newSpread
        }

        func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
            // Spread curl only exists in landscape (the SwiftUI layer swaps to
            // single-page on rotation), but answer defensively
            if let pair = viewControllerPair(forSpread: parent?.currentSpreadIndex ?? 0) {
                pageViewController.setViewControllers(pair, direction: .forward, animated: false)
            }
            pageViewController.isDoubleSided = true
            return .mid
        }
    }

    class SpreadPageHostingController: UIHostingController<ComicPageView>, SpreadCurlSlot {
        let slotIndex: Int

        init(page: ComicPage, slotIndex: Int, coordinator: Coordinator) {
            self.slotIndex = slotIndex
            super.init(rootView: ComicPageView(
                page: page,
                onSwipeLeft: { [weak coordinator] in coordinator?.requestTurn(+1) },
                onSwipeRight: { [weak coordinator] in coordinator?.requestTurn(-1) },
                nativePagerMode: true,
                onZoomStateChanged: { [weak coordinator] zoomed in
                    coordinator?.setZoomed(zoomed)
                },
                initialScale: coordinator.initialScale
            ))
            view.backgroundColor = .black
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) not implemented")
        }
    }

    /// Black placeholder for the empty half of a single-page spread
    class SpreadFillerViewController: UIViewController, SpreadCurlSlot {
        let slotIndex: Int

        init(slotIndex: Int) {
            self.slotIndex = slotIndex
            super.init(nibName: nil, bundle: nil)
            view.backgroundColor = .black
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) not implemented")
        }
    }
}

/// Lets the coordinator read a slot index off either page or filler VCs
protocol SpreadCurlSlot: UIViewController {
    var slotIndex: Int { get }
}
#endif
