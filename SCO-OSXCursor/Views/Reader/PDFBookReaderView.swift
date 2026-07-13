//
//  PDFBookReaderView.swift
//  SCO-OSXCursor
//
//  PDFKit-backed book reader for PDFs explicitly opted into book mode.
//

import PDFKit
import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum PDFTurnInput {
    case tap
    case key
    case swipe
    case control
}

struct PDFBookReaderView: View {
    let comic: Comic
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    @Binding var searchQuery: String

    var onClose: () -> Void
    var onShowSettings: () -> Void
    var onPageChanged: (Int, Int) -> Void
    var onReachedEnd: () -> Void

    @State private var document: PDFDocument?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showControls = true
    @State private var searchMatches: [PDFSelection] = []
    @State private var searchIndex = 0
    @State private var searchRevision = 0
    @State private var autoHideTask: Task<Void, Never>?
    @State private var securityScopedURL: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            } else if let errorMessage {
                VStack(spacing: 18) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 54))
                        .foregroundColor(.white.opacity(0.35))
                    Text("Unable to Open PDF")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Close", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
            } else if let document {
                PDFBookRepresentable(
                    document: document,
                    initialPage: currentPage,
                    searchRevision: searchRevision,
                    currentSearchSelection: currentSearchSelection,
                    onClose: onClose,
                    onPageChanged: onPageChanged,
                    onReachedEnd: onReachedEnd,
                    onCenterTap: toggleControls
                )
            }

            if showControls && !isLoading && errorMessage == nil {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .task {
            await loadDocument()
        }
        .onChange(of: searchQuery) { _, newValue in
            runSearch(newValue)
        }
        .onAppear {
            resetAutoHideTimer()
        }
        .onDisappear {
            autoHideTask?.cancel()
            stopSecurityAccess()
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PDFBookIconButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])

                Text(comic.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Text("\(min(currentPage + 1, max(totalPages, 1))) / \(max(totalPages, 1))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                Button(action: onShowSettings) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(PDFBookIconButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(.black.opacity(0.72))

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.7))

                TextField("Search PDF", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .submitLabel(.search)

                if !searchQuery.isEmpty {
                    Text(searchMatches.isEmpty ? "No matches" : "\(searchIndex + 1) of \(searchMatches.count)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))

                    Button(action: previousMatch) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(PDFBookIconButtonStyle(compact: true))
                    .disabled(searchMatches.isEmpty)

                    Button(action: nextMatch) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(PDFBookIconButtonStyle(compact: true))
                    .disabled(searchMatches.isEmpty)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.62))

            Spacer()
        }
        .onTapGesture {
            resetAutoHideTimer()
        }
    }

    private var currentSearchSelection: PDFSelection? {
        guard searchMatches.indices.contains(searchIndex) else { return nil }
        return searchMatches[searchIndex]
    }

    private func loadDocument() async {
        var fileURL = comic.resolvedURL
        var didStartAccess = false

        if let bookmarkData = comic.bookmarkData {
            var isStale = false
            #if os(macOS)
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                fileURL = resolved
                didStartAccess = resolved.startAccessingSecurityScopedResource()
            }
            #else
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                fileURL = resolved
                didStartAccess = resolved.startAccessingSecurityScopedResource()
            }
            #endif
        }

        let loaded = await Task.detached { PDFDocument(url: fileURL) }.value

        guard let loaded else {
            if didStartAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
            errorMessage = "PDFKit could not read this document."
            isLoading = false
            return
        }

        if didStartAccess {
            securityScopedURL = fileURL
        }
        document = loaded
        totalPages = max(loaded.pageCount, 1)
        currentPage = min(max(currentPage, 0), max(totalPages - 1, 0))
        isLoading = false
        onPageChanged(currentPage, totalPages)
        resetAutoHideTimer()
    }

    private func stopSecurityAccess() {
        if let securityScopedURL {
            securityScopedURL.stopAccessingSecurityScopedResource()
            self.securityScopedURL = nil
        }
    }

    private func runSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let document else {
            searchMatches = []
            searchIndex = 0
            searchRevision += 1
            return
        }

        searchMatches = document.findString(trimmed, withOptions: [.caseInsensitive, .diacriticInsensitive])
        searchIndex = 0
        searchRevision += 1
        resetAutoHideTimer()
    }

    private func nextMatch() {
        guard !searchMatches.isEmpty else { return }
        searchIndex = (searchIndex + 1) % searchMatches.count
        searchRevision += 1
        resetAutoHideTimer()
    }

    private func previousMatch() {
        guard !searchMatches.isEmpty else { return }
        searchIndex = (searchIndex + searchMatches.count - 1) % searchMatches.count
        searchRevision += 1
        resetAutoHideTimer()
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showControls.toggle()
        }
        if showControls {
            resetAutoHideTimer()
        }
    }

    private func resetAutoHideTimer() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showControls = false
            }
        }
    }
}

private struct PDFBookIconButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
            .background(Color.white.opacity(configuration.isPressed ? 0.22 : 0.12))
            .clipShape(Circle())
    }
}

#if os(iOS)
private typealias PlatformViewRepresentable = UIViewRepresentable
#else
private typealias PlatformViewRepresentable = NSViewRepresentable
#endif

private struct PDFBookRepresentable: PlatformViewRepresentable {
    let document: PDFDocument
    let initialPage: Int
    let searchRevision: Int
    let currentSearchSelection: PDFSelection?
    var onClose: () -> Void
    var onPageChanged: (Int, Int) -> Void
    var onReachedEnd: () -> Void
    var onCenterTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onClose: onClose,
            onPageChanged: onPageChanged,
            onReachedEnd: onReachedEnd,
            onCenterTap: onCenterTap
        )
    }

    #if os(iOS)
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black

        let view = makePDFView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor)
        ])
        addTapAndPanRecognizers(to: view, coordinator: context.coordinator)

        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let view = container.subviews.compactMap({ $0 as? PDFBookPlatformView }).first else { return }
        updatePDFView(view, context: context)
    }

    private func addTapAndPanRecognizers(to view: PDFBookPlatformView, coordinator: Coordinator) {
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTapGesture(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = coordinator
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePanGesture(_:)))
        pan.cancelsTouchesInView = false
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)
    }
    #else
    func makeNSView(context: Context) -> PDFBookPlatformView {
        let view = makePDFView(context: context)
        context.coordinator.installKeyMonitor()
        return view
    }

    func updateNSView(_ view: PDFBookPlatformView, context: Context) {
        updatePDFView(view, context: context)
    }

    static func dismantleNSView(_ nsView: PDFBookPlatformView, coordinator: Coordinator) {
        coordinator.removeKeyMonitor()
    }
    #endif

    private func makePDFView(context: Context) -> PDFBookPlatformView {
        let view = PDFBookPlatformView()
        view.turnCoordinator = context.coordinator
        context.coordinator.pdfView = view

        view.document = document
        view.delegate = context.coordinator
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.autoScales = true
        view.displaysPageBreaks = false
        view.backgroundColor = .black
        #if os(iOS)
        view.usePageViewController(true, withViewOptions: nil)
        #endif

        context.coordinator.installPageObserver(for: view)
        context.coordinator.restorePage(initialPage)
        context.coordinator.reportPage()
        return view
    }

    private func updatePDFView(_ view: PDFBookPlatformView, context: Context) {
        if view.document !== document {
            view.document = document
            view.delegate = context.coordinator
            context.coordinator.installPageObserver(for: view)
            context.coordinator.restorePage(initialPage)
            context.coordinator.reportPage()
        }

        if context.coordinator.lastSearchRevision != searchRevision {
            context.coordinator.lastSearchRevision = searchRevision
            context.coordinator.showSearchSelection(currentSearchSelection)
        }
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var pageIndex = 0
        var pageCount = 0
        var isTurnInFlight = false
        var suppressTapUntil: Date?
        var lastSearchRevision = -1
	    private var pageObserver: NSObjectProtocol?

	    private let onClose: () -> Void
	    private let onPageChanged: (Int, Int) -> Void
	    private let onReachedEnd: () -> Void
	    private let onCenterTap: () -> Void

	    init(
	        onClose: @escaping () -> Void,
		onPageChanged: @escaping (Int, Int) -> Void,
		onReachedEnd: @escaping () -> Void,
		onCenterTap: @escaping () -> Void
	    ) {
	        self.onClose = onClose
		self.onPageChanged = onPageChanged
		self.onReachedEnd = onReachedEnd
		self.onCenterTap = onCenterTap
        }

	    deinit {
		if let pageObserver {
		    NotificationCenter.default.removeObserver(pageObserver)
		}
	        #if os(macOS)
	        removeKeyMonitor()
	        #endif
	    }

        func installPageObserver(for view: PDFView) {
            if let pageObserver {
                NotificationCenter.default.removeObserver(pageObserver)
            }
            pageObserver = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self] _ in
                self?.reportPage()
                self?.clearTurnFlagSoon()
            }
        }

        func restorePage(_ index: Int) {
            guard let document = pdfView?.document, document.pageCount > 0 else { return }
            let target = min(max(index, 0), document.pageCount - 1)
            if let page = document.page(at: target) {
                pdfView?.go(to: page)
            }
            reportPage()
        }

        func reportPage() {
            guard let view = pdfView, let document = view.document else { return }
            pageCount = document.pageCount
            if let page = view.currentPage {
                pageIndex = max(0, document.index(for: page))
            } else {
                pageIndex = 0
            }
            onPageChanged(pageIndex, pageCount)
        }

        func showSearchSelection(_ selection: PDFSelection?) {
            guard let view = pdfView else { return }
            view.setCurrentSelection(selection, animate: true)
            if let selection {
                view.go(to: selection)
                suppressTapUntil = Date().addingTimeInterval(0.35)
                reportPage()
            }
        }

        func handleTap(at point: CGPoint, in bounds: CGRect) {
            guard bounds.width > 0 else { return }
            if let suppressTapUntil, Date() < suppressTapUntil { return }
            if hasActiveSelection() {
                pdfView?.clearSelection()
                suppressTapUntil = Date().addingTimeInterval(0.35)
                return
            }
            if hasLinkAnnotation(at: point) {
                return
            }

            let fraction = ReaderSettings.shared.tapZoneWidth.fraction
            if point.x < bounds.width * fraction {
                turn(delta: -1, input: .tap)
            } else if point.x > bounds.width * (1 - fraction) {
                turn(delta: 1, input: .tap)
            } else {
                onCenterTap()
            }
        }

        func turn(delta: Int, input: PDFTurnInput) {
            guard delta != 0, !isTurnInFlight else { return }
            if input == .tap, let suppressTapUntil, Date() < suppressTapUntil {
                return
            }
            if input == .tap, hasActiveSelection() {
                return
            }

            guard let document = pdfView?.document, document.pageCount > 0 else { return }
            pageCount = document.pageCount
            if let page = pdfView?.currentPage {
                pageIndex = max(0, document.index(for: page))
            }

            let target = pageIndex + delta
            guard target >= 0 && target < pageCount else {
                if delta > 0 && pageIndex == pageCount - 1 {
                    onReachedEnd()
                }
                return
            }
            guard let page = document.page(at: target) else { return }

            isTurnInFlight = true
            pdfView?.go(to: page)
            reportPage()
            clearTurnFlagSoon()
        }

        func suppressTapAfterDrag() {
            suppressTapUntil = Date().addingTimeInterval(0.35)
        }

        private func hasActiveSelection() -> Bool {
            guard let selection = pdfView?.currentSelection else { return false }
            return !(selection.string ?? "").isEmpty
        }

        private func hasLinkAnnotation(at point: CGPoint) -> Bool {
            guard let view = pdfView,
                  let page = view.page(for: point, nearest: true)
            else { return false }
            let pagePoint = view.convert(point, to: page)
            return page.annotation(at: pagePoint)?.action != nil
        }

        private func clearTurnFlagSoon() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.isTurnInFlight = false
            }
        }

	        #if os(iOS)
	        @objc func handleTapGesture(_ gesture: UITapGestureRecognizer) {
	            guard gesture.state == .ended, let view = gesture.view else { return }
	            handleTap(at: gesture.location(in: view), in: view.bounds)
	        }

	        @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
	            switch gesture.state {
	            case .changed, .ended, .cancelled, .failed:
	                suppressTapAfterDrag()
	            default:
	                break
	            }
	        }
	        #else
	        private var keyMonitor: Any?

	        func installKeyMonitor() {
	            guard keyMonitor == nil else { return }
	            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
	                guard let self else { return event }
	                if NSApp.keyWindow?.isSheet == true { return event }
	                if event.keyCode == 53 {
	                    Task { @MainActor in self.onClose() }
	                    return nil
	                }
	                if NSApp.keyWindow?.firstResponder is NSText { return event }

	                switch event.keyCode {
	                case 123, 126:
	                    self.turn(delta: -1, input: .key)
	                    return nil
	                case 124, 125, 49:
	                    self.turn(delta: 1, input: .key)
	                    return nil
	                default:
	                    return event
	                }
	            }
	        }

	        func removeKeyMonitor() {
	            if let monitor = keyMonitor {
	                NSEvent.removeMonitor(monitor)
	                keyMonitor = nil
	            }
	        }
	        #endif
	    }
	}

extension PDFBookRepresentable.Coordinator: PDFViewDelegate {
    func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}

#if os(iOS)
extension PDFBookRepresentable.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif

#if os(iOS)
private final class PDFBookPlatformView: PDFView {
    weak var turnCoordinator: PDFBookRepresentable.Coordinator?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }
}
#else
private final class PDFBookPlatformView: PDFView {
    weak var turnCoordinator: PDFBookRepresentable.Coordinator?
    private var mouseStart: CGPoint?
    private var gestureDeltaX: CGFloat = 0
    private var gestureDidTurn = false
    private var isHorizontalGesture = false
    private let swipeThreshold: CGFloat = 40

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        mouseStart = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let end = convert(event.locationInWindow, from: nil)
        super.mouseUp(with: event)
        guard let start = mouseStart else { return }
        let dx = end.x - start.x
        let dy = end.y - start.y
        if hypot(dx, dy) < 6 {
            turnCoordinator?.handleTap(at: end, in: bounds)
        } else {
            turnCoordinator?.suppressTapAfterDrag()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let coordinator = turnCoordinator, event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        switch event.phase {
        case .began:
            resetScrollGesture()
            isHorizontalGesture = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        case .changed:
            guard isHorizontalGesture else { break }
            coordinator.suppressTapAfterDrag()
            gestureDeltaX += event.scrollingDeltaX
            if !gestureDidTurn, abs(gestureDeltaX) > swipeThreshold {
                gestureDidTurn = true
                coordinator.turn(delta: gestureDeltaX < 0 ? 1 : -1, input: .swipe)
            }
        default:
            break
        }

        let gestureFinished = event.phase == .ended || event.phase == .cancelled
        let momentumFinished = event.momentumPhase == .ended || event.momentumPhase == .cancelled

        if !isHorizontalGesture {
            super.scrollWheel(with: event)
        }

        if isHorizontalGesture, gestureFinished, event.momentumPhase == [] {
            resetScrollGesture()
        } else if momentumFinished {
            resetScrollGesture()
        }
    }

    private func resetScrollGesture() {
        gestureDeltaX = 0
        gestureDidTurn = false
        isHorizontalGesture = false
    }
}
#endif
