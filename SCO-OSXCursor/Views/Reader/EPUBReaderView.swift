//
//  EPUBReaderView.swift
//  SCO-OSXCursor
//
//  A WKWebView-based reader for EPUB books. Renders one chapter at a time with
//  injected CSS for dark mode, user-controlled font size, and comfortable typography.
//

import SwiftUI
import WebKit
import os

enum EPUBTurnInput {
    case tap
    case key
    case swipe
    case control
}

/// What happens when a page turn runs off the end of a chapter.
///
/// Every input carries on into the neighbouring chapter, the way a page turn in
/// Books does: a chapter boundary is invisible to the reader, so stopping dead
/// at one reads as the book being broken. Turning back across a boundary lands
/// on the LAST page of the previous chapter, not its first.
enum EPUBTurnPolicy {
    static var tapCrossesChapter = true
    static var keyCrossesChapter = true
    static var swipeCrossesChapter = true

    static func crossesChapter(for input: EPUBTurnInput) -> Bool {
        switch input {
        case .tap: return tapCrossesChapter
        case .key: return keyCrossesChapter
        case .swipe: return swipeCrossesChapter
        case .control: return true   // the HUD's Previous/Next buttons
        }
    }
}

// MARK: - EPUB Reader View

struct EPUBReaderView: View {
    let comic: Comic

    @Binding var currentChapter: Int
    let totalChapters: Int
    @Binding var chapterProgress: Double
    @Binding var fontSize: Int         // in pt (12–56)

    var onClose: () -> Void
    var onShowSettings: () -> Void
    /// One-click theme cycle from the reader bar (Dark → Light → Sepia).
    var onCycleTheme: () -> Void
    /// Toggle between Page mode (Kindle-like) and Scroll mode for this book.
    var onTogglePageMode: () -> Void

    @State private var chapters: [EPUBChapter] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showControls = true
    @State private var autoHideTimer: Timer?
    @State private var showTableOfContents = false

    /// Observed so typography changes re-render the open chapter live
    @ObservedObject private var readerSettings = ReaderSettings.shared

    /// Active theme for this book (per-book override or global setting).
    private var theme: EPUBTheme {
        ReaderSettings.shared.effectiveEPUBTheme(for: comic)
    }

    var body: some View {
        ZStack {
            // Background — matches the reader's injected CSS
            Color(hex: theme.cssColors.background)
                .ignoresSafeArea()

            if isLoading {
                epubLoadingView
            } else if let error = errorMessage {
                epubErrorView(error)
            } else if !chapters.isEmpty {
                // Chapter web view
                EPUBWebView(
                    chapter: chapters[min(currentChapter, chapters.count - 1)],
                    fontSize: fontSize,
                    readingStyle: comic.readingStyle,
                    theme: theme,
                    fontFamily: readerSettings.epubFontFamily,
                    lineSpacing: readerSettings.epubLineSpacing,
                    margins: readerSettings.epubMargins,
                    restoreProgress: chapterProgress,
                    onTap: { handleTap() },
                    onNavigate: { delta in navigateChapter(by: delta, restoreProgress: delta < 0 ? 1 : 0) },
                    onProgressChanged: { progress in chapterProgress = progress },
                    onEscape: { handleEscape() },
                    onChapterLink: { url in navigateToChapterFile(url) }
                )
                .ignoresSafeArea()
            }

            // Controls overlay
            if showControls && !isLoading && errorMessage == nil {
                EPUBReaderControlsOverlay(
                    comic: comic,
                    currentChapter: $currentChapter,
                    totalChapters: totalChapters,
                    fontSize: $fontSize,
                    chapters: chapters,
                    showTableOfContents: $showTableOfContents,
                    theme: theme,
                    onClose: onClose,
                    onShowSettings: onShowSettings,
                    onCycleTheme: onCycleTheme,
                    onTogglePageMode: onTogglePageMode,
                    onPreviousChapter: { navigateChapter(by: -1, restoreProgress: 1) },
                    onNextChapter: { navigateChapter(by: 1, restoreProgress: 0) },
                    onUserInteraction: { resetAutoHideTimer() }
                )
                .transition(.opacity)
            }

            // Table of Contents drawer
            if showTableOfContents {
                EPUBTableOfContentsView(
                    chapters: chapters,
                    currentChapter: Binding(
                        get: { currentChapter },
                        set: { newChapter in
                            chapterProgress = 0
                            currentChapter = newChapter
                        }
                    ),
                    isPresented: $showTableOfContents
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(200)
            }
        }
        .task {
            await loadChapters()
        }
        .onChange(of: currentChapter) { _, _ in
            resetAutoHideTimer()
        }
        #if os(macOS)
        .onAppear {
            setupKeyboardHandling()
            installEscapeMonitor()
        }
        .onDisappear { removeEscapeMonitor() }
        #endif
    }

    /// Esc: dismiss the ToC drawer if it's open, otherwise close the reader.
    private func handleEscape() {
        if showTableOfContents {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showTableOfContents = false
            }
        } else {
            onClose()
        }
    }

    #if os(macOS)
    // Esc must work whether or not the controls overlay is on screen, and
    // even while the WKWebView has keyboard focus. The overlay's close
    // button (and its shortcut) only exist while the overlay is visible, so
    // Esc otherwise fell through unhandled — closing nothing and triggering
    // the system beep. A local NSEvent monitor sees the key first and
    // consumes it (return nil = no beep).
    private func installEscapeMonitor() {
        guard EPUBEscapeMonitor.shared.monitor == nil else { return }
        AppLog.reader.debug("[EPUBReaderView] Esc monitor installed")
        EPUBEscapeMonitor.shared.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }  // 53 = Esc
            // Let sheets (Reader Settings) keep their own Esc-to-cancel.
            if NSApp.keyWindow?.isSheet == true { return event }
            AppLog.reader.debug("[EPUBReaderView] Esc consumed by monitor")
            Task { @MainActor in handleEscape() }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = EPUBEscapeMonitor.shared.monitor {
            NSEvent.removeMonitor(monitor)
            EPUBEscapeMonitor.shared.monitor = nil
        }
    }
    #endif

    // MARK: - Chapter Loading

    private func loadChapters() async {
        guard comic.fileType == .epub else {
            errorMessage = "Not a valid EPUB file."
            isLoading = false
            return
        }

        // Resolve the file URL
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
                // Required for books imported "in place" from Files/iCloud —
                // the file lives outside the sandbox and reads block or fail
                // without an active security scope.
                didStartAccess = resolved.startAccessingSecurityScopedResource()
            }
            #endif
        }
        defer { if didStartAccess { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let reader = EPUBReader()
            let loaded = try reader.loadChapters(from: fileURL)
            await MainActor.run {
                self.chapters = loaded
                self.isLoading = false
                self.resetAutoHideTimer()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Navigation

    private func navigateChapter(by delta: Int, restoreProgress: Double = 0) {
        let newIndex = currentChapter + delta
        guard newIndex >= 0 && newIndex < totalChapters else { return }
        chapterProgress = min(max(restoreProgress, 0), 1)
        withAnimation(.easeInOut(duration: 0.2)) {
            currentChapter = newIndex
        }
        resetAutoHideTimer()
    }

    /// In-book link (e.g. a ToC page) → jump to that chapter. Returns false
    /// if the URL doesn't match a chapter file (caller decides what to do).
    /// Fragments land at the chapter top for now.
    private func navigateToChapterFile(_ url: URL) -> Bool {
        let targetPath = url.standardizedFileURL.path
        guard let index = chapters.firstIndex(where: {
            $0.fileURL.standardizedFileURL.path == targetPath
        }) else { return false }

        if index != currentChapter {
            chapterProgress = 0
            withAnimation(.easeInOut(duration: 0.2)) {
                currentChapter = index
            }
        }
        resetAutoHideTimer()
        return true
    }

    // MARK: - Controls Visibility

    private func handleTap() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showControls.toggle()
        }
        if showControls { resetAutoHideTimer() }
    }

    private func resetAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            Task { @MainActor in
                guard !self.showTableOfContents else {
                    self.resetAutoHideTimer()
                    return
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.showControls = false
                }
            }
        }
    }

    // MARK: - Keyboard (macOS)

    #if os(macOS)
    private func setupKeyboardHandling() {
        resetAutoHideTimer()
    }
    #endif

    // MARK: - Loading / Error Views

    private var epubLoadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(hex: "#9B8FE8"))
            Text("Opening book…")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    private func epubErrorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text("Unable to Open Book")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Close") { onClose() }
                .buttonStyle(EPUBPillButtonStyle(color: Color(hex: "#9B8FE8")))
        }
    }
}

// MARK: - WKWebView Wrapper

#if os(macOS)
/// Holds the reader's Esc key monitor — a class so the SwiftUI view struct
/// can install/remove it from onAppear/onDisappear without state plumbing.
@MainActor
private final class EPUBEscapeMonitor {
    static let shared = EPUBEscapeMonitor()
    var monitor: Any?
}
#endif

// MARK: - WKWebView Wrapper

/// Shared logic for both platform variants of EPUBWebView.
private struct EPUBWebViewHelper {
    let chapter: EPUBChapter
    let fontSize: Int
    let readingStyle: String?
    let theme: EPUBTheme
    let fontFamily: EPUBFontFamily
    let lineSpacing: EPUBLineSpacing
    let margins: EPUBMargins
    let restoreProgress: Double

    func makeWebView(coordinator: EPUBWebView.Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(coordinator, name: "epubNavigation")

        // macOS has no UIScrollView and therefore no native paging. The
        // subclass maps a trackpad two-finger horizontal swipe onto the same
        // guarded turn function the keys and click zones use.
        #if os(macOS)
        let webView = EPUBTrackpadWebView(frame: .zero, configuration: config)
        webView.turnCoordinator = coordinator
        #else
        let webView = WKWebView(frame: .zero, configuration: config)
        #endif
        webView.navigationDelegate = coordinator
        coordinator.webView = webView

        // NOTE: tap ZONES are detected by injected JS (a native tap recognizer
        // on WKWebView cancels the touches WebKit needs to complete link
        // clicks, which made in-book links dead). But the JS only *reports*
        // the tap — every page turn is executed by the Swift turn function.
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Don't rubber-band vertically when content fits (paged mode) — the
        // bounce otherwise claims vertical drags meant for swipe-to-dismiss
        webView.scrollView.alwaysBounceVertical = false

        // Native paging: the scroll view — not JavaScript — turns pages, so
        // drags are interactive, cancellable and momentum-correct for free.
        // The delegate reports where the pager settled and whether the reader
        // dragged past a chapter edge.
        webView.scrollView.delegate = coordinator
        // Safe-area insets would otherwise shift contentInset and push every
        // paging boundary off by the inset amount on notched devices.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.decelerationRate = .fast
        webView.scrollView.showsHorizontalScrollIndicator = false
        #endif

        loadContent(into: webView, coordinator: coordinator)
        return webView
    }

    /// Identifies the content this helper would render — used to skip
    /// redundant reloads. updateNSView/updateUIView fire on EVERY SwiftUI
    /// state change (e.g. toggling the controls overlay), and reloading the
    /// chapter each time reset the scroll position and dropped keyboard
    /// focus, which is why arrow keys "stopped working" mid-book.
    var loadKey: String {
        "\(chapter.index)|\(chapter.fileURL.path)|\(fontSize)|\(readingStyle ?? "")|\(theme.rawValue)|\(fontFamily.rawValue)|\(lineSpacing.rawValue)|\(margins.rawValue)|\(ReaderSettings.shared.tapZoneWidth.rawValue)"
    }

    func loadContent(into webView: WKWebView, coordinator: EPUBWebView.Coordinator) {
        guard coordinator.lastLoadKey != loadKey else { return }
        coordinator.lastLoadKey = loadKey

        // Same chapter, different rendering (font size, theme, margins…):
        // restore the reader's place after the re-render, like iBooks.
        // A different chapter starts at the top.
        if coordinator.lastChapterPath == chapter.fileURL.path {
            // Same chapter re-rendered (font, theme, margins): keep the place.
            let fraction = coordinator.lastScrollFraction
            coordinator.prepareForNewDocument(restoringFraction: fraction)
            coordinator.pendingRestoreFraction = fraction
        } else {
            coordinator.prepareForNewDocument(restoringFraction: restoreProgress)
            coordinator.pendingRestoreFraction = restoreProgress > 0.001 ? restoreProgress : nil
        }
        coordinator.lastChapterPath = chapter.fileURL.path

        // Both platforms need this: the turn function only moves BETWEEN pages
        // when it knows the chapter is paginated. Leave it false on macOS and
        // every arrow key looks like a chapter-boundary turn instead of a page
        // turn — the Mac would jump whole chapters one keypress at a time.
        let style = ReadingStyle(rawValue: readingStyle ?? "") ?? .standard
        let paged = (style == .standard || style == .mangaRTL)
        coordinator.isHorizontalPaged = paged

        #if os(iOS)
        webView.scrollView.isScrollEnabled = true
        // Native paging settles on exact viewport-width boundaries — that is
        // what makes the drag interactive, cancellable and momentum-correct.
        // It only works because the injected CSS lets the COLUMNS overflow the
        // document (not an inner body scroller) and the layout spacer pins the
        // scrollable width to a whole number of pages.
        webView.scrollView.isPagingEnabled = paged
        // Without this a one-page chapter has zero scrollable distance, so the
        // reader could never swipe out of it into the next chapter.
        webView.scrollView.alwaysBounceHorizontal = paged
        webView.scrollView.isDirectionalLockEnabled = paged
        webView.scrollView.decelerationRate = paged ? .fast : .normal
        webView.scrollView.showsHorizontalScrollIndicator = !paged
        #endif

        guard let rawHTML = try? chapter.htmlContent() else { return }
        let styledHTML = injectStyles(into: rawHTML)
        
        // Write the styled HTML to a sibling file to allow WKWebView local read access
        let styledFileName = "sco_styled_" + chapter.fileURL.lastPathComponent
        let styledURL = chapter.baseURL.appendingPathComponent(styledFileName)
        
        do {
            try styledHTML.write(to: styledURL, atomically: true, encoding: .utf8)
            // Allow read access to the entire temp directory so all epub assets are accessible
            webView.loadFileURL(styledURL, allowingReadAccessTo: FileManager.default.temporaryDirectory)
        } catch {
            AppLog.reader.error("[EPUBReaderView] Failed to write styled HTML: \(error)")
            // Fallback to loadHTMLString (often blocks images/css on modern OS)
            webView.loadHTMLString(styledHTML, baseURL: chapter.baseURL)
        }
    }

    private func injectStyles(into html: String) -> String {
        // Books default to PAGE mode (Kindle-like: text fills the screen,
        // edge taps turn one page). Vertical scroll remains a per-book
        // choice via the HUD toggle.
        let styleStr = ReadingStyle(rawValue: readingStyle ?? "") ?? .standard
        let isHorizontal = styleStr == .standard || styleStr == .mangaRTL
        
        // Margin presets (defaults reproduce the original hard-coded layout)
        let hPad = margins.horizontalPadding
        let vPad = margins.verticalPadding
        let maxWidth = margins.maxTextWidth

        // Page mode. The DOCUMENT must be the horizontal scroller: only then
        // does the WKWebView's scroll view get a contentSize wider than its
        // bounds, which is what native paging pages. Giving `body` its own
        // overflow-x (as this did before) made BODY the scroll container — the
        // document never scrolled, window.scrollX stayed pinned at 0, and a
        // paging scroll view would have had nothing to page.
        //
        // The column pitch is exactly one viewport: (100vw - 2·hPad) of column
        // plus 2·hPad of gap. So page N begins at exactly N · 100vw, and the
        // pager's viewport-width snapping lands each page perfectly.
        let layoutCSS = isHorizontal ? """
        html {
            height: 100vh !important;
            width: 100% !important;
            margin: 0 !important;
            padding: 0 !important;
            overflow-x: auto !important;
            overflow-y: hidden !important;
        }
        body {
            height: 100vh !important;
            width: auto !important;
            margin: 0 !important;
            /* Vertical padding grows by the safe-area insets so text clears
               the notch/Dynamic Island (the reader ignores the safe area).
               Horizontal padding must stay fixed — the column pitch math
               depends on it. */
            padding: calc(\(hPad)px + env(safe-area-inset-top, 0px)) \(hPad)px calc(\(hPad)px + env(safe-area-inset-bottom, 0px)) \(hPad)px !important;
            box-sizing: border-box !important;
            overflow: visible !important;
            column-width: calc(100vw - \(hPad * 2)px) !important;
            column-gap: \(hPad * 2)px !important;
            column-fill: auto !important;
        }
        img {
            max-width: 100% !important;
            max-height: calc(100vh - \(hPad * 2)px - env(safe-area-inset-top, 0px) - env(safe-area-inset-bottom, 0px)) !important;
            object-fit: contain !important;
        }
        """ : """
        html, body {
            margin: 0 auto !important;
            padding: 0 !important;
        }
        body {
            padding: calc(32px + env(safe-area-inset-top, 0px)) \(vPad)px calc(64px + env(safe-area-inset-bottom, 0px)) \(vPad)px !important;
            max-width: \(maxWidth)px;
        }
        """

        // JS to handle keyboard pagination and chapter navigation.
        // Escape is also handled here because the WKWebView holds keyboard
        // focus while reading — without this the key fell through unhandled
        // (system beep) unless the controls overlay happened to be visible.
        // scoPageForward/scoPageBackward are shared by the arrow keys AND the
        // native edge-tap zones (evaluated from the tap coordinator), so both
        // input methods page identically.
        // NOTE: every injected <script> is wrapped in CDATA guards. EPUB
        // chapters are often XHTML (strict XML), where raw `&&` or `<` in
        // script text is a fatal parse error (`xmlParseEntityRef: no name`)
        // that blanks the whole page. The `//` prefixes keep the guards
        // valid as plain-HTML JS comments too.
        let js = isHorizontal ? """
        <script>
        //<![CDATA[
        // Page mode: real finger drags are owned by the native scroll view.
        // This script never turns a page — it only measures the document and
        // reports intent (tap zone, key, position) to Swift, which performs
        // every turn through one guarded path. That is what makes a single
        // gesture produce exactly one turn.
        window.scoPages = 1;
        window.scoPageWidth = 0;
        // Nothing may report a position before the document has been measured:
        // until then a chapter looks like a single page, which would report the
        // reader as being at its END.
        window.scoLaidOut = false;

        // A scroll container's scrollWidth EXCLUDES its own trailing padding,
        // so the document is short by exactly one horizontal margin and the
        // LAST page can never be scrolled fully into view — it lands offset by
        // that margin. This spacer, parked outside the column flow, pins the
        // scrollable width to a whole number of viewport-width pages, so every
        // page boundary (the last one included) is an exact multiple of the
        // viewport and the pager settles on it precisely.
        window.scoLayout = function() {
            var doc = document.documentElement;
            var w = window.innerWidth;
            if (w <= 0) { return; }
            var spacer = document.getElementById('sco-page-spacer');
            if (spacer) { spacer.style.left = '0px'; }
            var natural = Math.max(doc.scrollWidth, w);
            var pages = Math.max(1, Math.ceil((natural - 2) / w));
            if (!spacer) {
                spacer = document.createElement('div');
                spacer.id = 'sco-page-spacer';
                spacer.setAttribute('aria-hidden', 'true');
                spacer.style.cssText = 'position:absolute;top:0;width:1px;height:1px;visibility:hidden;pointer-events:none;';
                doc.appendChild(spacer);
            }
            spacer.style.left = (pages * w - 1) + 'px';
            window.scoPages = pages;
            window.scoPageWidth = w;
            window.scoLaidOut = true;
        };

        // Page metrics come from the measured layout, never from scrollWidth:
        // with the spacer in place the real scrollable area is wider than the
        // scrollWidth WebKit reports, so scrollWidth would under-count.
        window.scoMaxScroll = function() {
            return Math.max(0, (window.scoPages - 1) * window.scoPageWidth);
        };
        window.scoReportFraction = function() {
            if (!window.scoLaidOut) { return; }
            var maxX = window.scoMaxScroll();
            // A chapter that fits on one page has no scrollable distance, so
            // there is no fraction to measure — but the reader can see all of
            // it, so it is FINISHED, not 0% read. Reporting 0 here would mean a
            // one-page final chapter could never complete the book.
            var fraction = maxX > 0 ? (window.scrollX / maxX) : 1;
            fraction = Math.max(0, Math.min(1, fraction));
            // Where the reader IS, as opposed to how much they've FINISHED —
            // the two differ for a one-page chapter, which is 100% read but
            // sits at position 0. Cached every scroll so a resize can restore
            // the passage: by the time the resize event fires the columns have
            // already reflowed, so the position can no longer be measured.
            window.scoLastPosition = maxX > 0 ? Math.max(0, Math.min(1, window.scrollX / maxX)) : 0;
            var page = window.scoPageWidth > 0 ? Math.round(window.scrollX / window.scoPageWidth) : 0;
            page = Math.max(0, Math.min(window.scoPages - 1, page));
            window.webkit.messageHandlers.epubNavigation.postMessage(
                'pos:' + fraction + ',' + page + ',' + window.scoPages);
        };
        window.scoScrollToPage = function(page) {
            var w = window.scoPageWidth;
            var target = Math.max(0, Math.min(window.scoMaxScroll(), page * w));
            window.scrollTo(target, 0);
            window.scoReportFraction();
        };
        window.scoScrollToFraction = function(fraction) {
            var w = window.scoPageWidth;
            if (w <= 0) { return; }
            var page = Math.round((fraction * window.scoMaxScroll()) / w);
            window.scoScrollToPage(page);
        };

        document.addEventListener('keydown', function(e) {
            if (e.key === 'ArrowRight') {
                window.webkit.messageHandlers.epubNavigation.postMessage('keyForward');
                e.preventDefault();
            } else if (e.key === 'ArrowLeft') {
                window.webkit.messageHandlers.epubNavigation.postMessage('keyBackward');
                e.preventDefault();
            } else if (e.key === 'Escape') {
                window.webkit.messageHandlers.epubNavigation.postMessage('closeReader');
                e.preventDefault();
            }
        });

        var scoTicking = false;
        window.addEventListener('scroll', function() {
            if (scoTicking) { return; }
            scoTicking = true;
            requestAnimationFrame(function() {
                scoTicking = false;
                window.scoReportFraction();
            });
        }, { passive: true });

        // Rotation / window resize / split view: re-measure, then land the
        // reader back on a whole page at the same passage.
        window.addEventListener('resize', function() {
            // Use the position cached from the last scroll, NOT a fresh
            // measurement: scrollX has already been remapped onto the reflowed
            // columns, while scoPages/scoPageWidth still describe the old
            // layout, so measuring here divides a new offset by an old maximum
            // and lands the reader somewhere arbitrary.
            var before = typeof window.scoLastPosition === 'number' ? window.scoLastPosition : 0;
            window.scoLayout();
            window.scoScrollToFraction(Math.max(0, Math.min(1, before)));
        });

        window.onload = function() {
            window.focus();
            document.body.focus();
            window.scoLayout();
            window.scoReportFraction();
        };
        //]]>
        </script>
        """ : """
        <script>
        //<![CDATA[
        // Vertical scroll: edge taps advance by ONE SCREENFUL (with a small
        // overlap for reading continuity), not a whole chapter — chapters
        // only change at the very top/bottom of the content.
        window.scoPageForward = function() {
            var remaining = document.documentElement.scrollHeight - (window.scrollY + window.innerHeight);
            if (remaining <= 10) {
                window.webkit.messageHandlers.epubNavigation.postMessage('nextChapter');
            } else {
                window.scrollBy({ top: window.innerHeight * 0.9, behavior: 'smooth' });
            }
        };
        window.scoPageBackward = function() {
            if (window.scrollY <= 10) {
                window.webkit.messageHandlers.epubNavigation.postMessage('prevChapter');
            } else {
                window.scrollBy({ top: -window.innerHeight * 0.9, behavior: 'smooth' });
            }
        };
        document.addEventListener('keydown', function(e) {
            if (e.key === 'ArrowRight') {
                window.scoPageForward();
                e.preventDefault();
            } else if (e.key === 'ArrowLeft') {
                window.scoPageBackward();
                e.preventDefault();
            } else if (e.key === 'Escape') {
                window.webkit.messageHandlers.epubNavigation.postMessage('closeReader');
                e.preventDefault();
            }
        });
        window.scoReportFraction = function() {
            var maxY = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
            // As in page mode: a chapter shorter than the screen has nothing to
            // scroll, and the reader has already seen all of it.
            var fraction = maxY > 0 ? (window.scrollY / maxY) : 1;
            window.webkit.messageHandlers.epubNavigation.postMessage('frac:' + Math.max(0, Math.min(1, fraction)));
        };
        window.onload = function() { window.focus(); document.body.focus(); window.scoReportFraction(); };
        window.addEventListener('scroll', function() {
            window.scoReportFraction();
        }, { passive: true });
        //]]>
        </script>
        """

        // Tap/click zones, handled in-page so they can't interfere with link
        // clicks (native recognizers cancelled WebKit's touch processing and
        // killed in-book links). Links pass through to the navigation policy;
        // edge taps page; center taps toggle the controls overlay.
        let tapZoneFraction = ReaderSettings.shared.tapZoneWidth.fraction
        let backwardTapAction = isHorizontal
            ? "window.webkit.messageHandlers.epubNavigation.postMessage('tapBackward');"
            : "window.scoPageBackward && window.scoPageBackward();"
        let forwardTapAction = isHorizontal
            ? "window.webkit.messageHandlers.epubNavigation.postMessage('tapForward');"
            : "window.scoPageForward && window.scoPageForward();"
        let tapZonesJS = """
        <script>
        //<![CDATA[
        document.addEventListener('click', function(e) {
            // Let real link clicks through untouched
            if (e.target && e.target.closest && e.target.closest('a[href]')) { return; }
            // Finishing a text selection ends in a click, usually somewhere in
            // an edge zone. Paging on it would throw the reader off the very
            // passage they just selected.
            var sel = window.getSelection && window.getSelection();
            if (sel && !sel.isCollapsed && String(sel).length > 0) { return; }
            var f = \(tapZoneFraction);
            var x = e.clientX, w = window.innerWidth;
            if (x < w * f) {
                \(backwardTapAction)
            } else if (x > w * (1 - f)) {
                \(forwardTapAction)
            } else {
                window.webkit.messageHandlers.epubNavigation.postMessage('toggleControls');
            }
        });
        //]]>
        </script>
        """

        let colors = theme.cssColors
        let stripInlineColorsJS = """
        <script>
        //<![CDATA[
        document.addEventListener("DOMContentLoaded", function() {
            document.querySelectorAll('*').forEach(el => {
                el.style.setProperty('color', '\(colors.text)', 'important');
                el.style.setProperty('background-color', 'transparent', 'important');
            });
        });
        //]]>
        </script>
        """

        // Without a viewport meta, iOS lays the page out at DESKTOP width
        // and scales it down — fonts render far smaller than their pt size,
        // and 100vh/100vw columns don't match the real screen (enlarged
        // text overflowed the column bottom instead of flowing to the next
        // page). device-width + text-size-adjust:100% fixes both.
        let viewportMeta = """
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover" />
        """

        let css = """
        <style>
        :root { color-scheme: \(theme == .dark ? "dark" : "light"); }
        * { box-sizing: border-box; }
        html, body {
            background-color: \(colors.background) !important;
            color: \(colors.text) !important;
            font-family: \(fontFamily.cssFontFamily) !important;
            font-size: \(fontSize)px !important;
            line-height: \(lineSpacing.value) !important;
            -webkit-text-size-adjust: 100% !important;
        }
        \(layoutCSS)
        p, li, div, span, td, th { font-size: inherit !important; color: \(colors.text) !important; }
        h1, h2, h3, h4, h5, h6 { color: \(colors.text) !important; font-weight: 600; margin-top: 1.5em; margin-bottom: 0.5em; }
        a { color: \(colors.accent) !important; }
        img { border-radius: 8px; }
        blockquote {
            border-left: 3px solid \(colors.accent);
            margin-left: 0; padding-left: 16px;
            color: \(colors.text) !important; font-style: italic; opacity: 0.8;
        }
        code, pre { background: \(theme == .dark ? "#2C2C34" : "#F0F0F0") !important; color: \(colors.text) !important; border-radius: 4px; padding: 2px 6px; }
        pre { padding: 12px; }
        </style>
        """
        
        let headInjection = "\(viewportMeta)\n\(css)\n\(js)\n\(tapZonesJS)\n\(stripInlineColorsJS)"

        // The charset meta must be the FIRST element of <head>: the styled file
        // is loaded via loadFileURL, and without an early charset declaration
        // WebKit's HTML parser falls back to Latin-1 and garbles UTF-8 books.
        return EPUBHeadCharsetInjector.inject(headInjection, into: html)
    }
}

/// Platform-aware WKWebView representable for EPUB chapter rendering.
/// The Coordinator type is defined once below and used by both platform variants.
struct EPUBWebView {
    let chapter: EPUBChapter
    let fontSize: Int
    let readingStyle: String?
    let theme: EPUBTheme
    let fontFamily: EPUBFontFamily
    let lineSpacing: EPUBLineSpacing
    let margins: EPUBMargins
    let restoreProgress: Double
    var onTap: () -> Void
    var onNavigate: (Int) -> Void
    var onProgressChanged: (Double) -> Void
    /// Esc pressed while the page has keyboard focus (sent from injected JS).
    var onEscape: () -> Void
    /// In-book link to another chapter file — return true if handled.
    var onChapterLink: (URL) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onNavigate: onNavigate,
            onProgressChanged: onProgressChanged,
            onEscape: onEscape,
            onChapterLink: onChapterLink
        )
    }

    // MARK: - Coordinator (shared)
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onTap: () -> Void
        let onNavigate: (Int) -> Void
        let onProgressChanged: (Double) -> Void
        let onEscape: () -> Void
        let onChapterLink: (URL) -> Bool
        weak var webView: WKWebView?
        /// What's currently loaded — lets updateNSView/updateUIView skip
        /// reloads when nothing the page depends on actually changed.
        var lastLoadKey: String?
        /// Reading position within the current chapter (0…1), reported by
        /// the injected scroll listener.
        var lastScrollFraction: Double = 0
        /// Coalesces scroll reports. The fraction updates on every scroll
        /// callback, but it only reaches SwiftUI (and the database) once the
        /// reader has settled — see storeProgress(_:).
        private var progressFlushTimer: Timer?
        /// Which chapter the fraction belongs to.
        var lastChapterPath: String?
        /// Set before a same-chapter re-render (font size/theme change);
        /// consumed in didFinish to put the reader back where they were.
        var pendingRestoreFraction: Double?
        /// Shared by every input path, so one gesture is always one turn.
        var isTurnInFlight = false
        var isHorizontalPaged = false
        /// Page geometry as the page last measured it. Page mode decides turns
        /// against these, so no turn has to wait on an async JS round-trip.
        var pageIndex = 0
        var pageCount = 1
        #if os(iOS)
        var dragStartOffsetX: CGFloat = 0
        var pendingBoundarySwipeDelta: Int?
        /// Ignores the synthesized click WebKit fires at the end of a drag.
        var suppressTapUntil: Date?
        #endif

        init(
            onTap: @escaping () -> Void,
            onNavigate: @escaping (Int) -> Void,
            onProgressChanged: @escaping (Double) -> Void,
            onEscape: @escaping () -> Void,
            onChapterLink: @escaping (URL) -> Bool
        ) {
            self.onTap = onTap
            self.onNavigate = onNavigate
            self.onProgressChanged = onProgressChanged
            self.onEscape = onEscape
            self.onChapterLink = onChapterLink
        }


        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "epubNavigation", let action = message.body as? String {
                if action == "nextChapter" {
                    onNavigate(1)
                } else if action == "prevChapter" {
                    onNavigate(-1)
                } else if action == "tapForward" {
                    turn(delta: 1, input: .tap)
                } else if action == "tapBackward" {
                    turn(delta: -1, input: .tap)
                } else if action == "keyForward" {
                    turn(delta: 1, input: .key)
                } else if action == "keyBackward" {
                    turn(delta: -1, input: .key)
                } else if action == "closeReader" {
                    onEscape()
                } else if action == "toggleControls" {
                    onTap()
                } else if action.hasPrefix("frac:"), let value = Double(action.dropFirst(5)) {
                    storeProgress(value)
                } else if action.hasPrefix("pos:") {
                    // "pos:<fraction>,<page>,<pageCount>" — page mode reports
                    // the measured geometry along with the position, so every
                    // turn decision can be made synchronously in Swift.
                    let parts = action.dropFirst(4).split(separator: ",")
                    if parts.count == 3, let fraction = Double(parts[0]),
                       let page = Int(parts[1]), let pages = Int(parts[2]) {
                        pageIndex = page
                        pageCount = max(pages, 1)
                        storeProgress(fraction)
                    }
                }
            }
        }

        /// Records where the reader is, without telling anyone yet.
        ///
        /// Scroll callbacks arrive at display rate. Pushing each one into the
        /// `chapterProgress` binding re-runs the reader's body and — because
        /// EPUBContentView persists on every progress change — issues a
        /// database write, all while the user's finger is still on the glass.
        /// Only a settled position is worth persisting, so the fraction is
        /// stored cheaply here and flushed on settle (or after a short lull,
        /// which is what catches vertical-scroll mode: there the scroll
        /// reports come from JavaScript, so there is no settle callback).
        private func storeProgress(_ value: Double) {
            lastScrollFraction = min(max(value, 0), 1)

            progressFlushTimer?.invalidate()
            progressFlushTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.flushProgress()
                }
            }
        }

        /// Pushes the settled position to SwiftUI, which persists it.
        func flushProgress() {
            progressFlushTimer?.invalidate()
            progressFlushTimer = nil
            onProgressChanged(lastScrollFraction)
        }

        /// A new chapter is loading. Drop the pending flush: it carries the
        /// OLD chapter's position, and firing it after the switch would write
        /// that position against the new chapter — landing the reader at the
        /// end of a chapter they never read, and (if it's the last one)
        /// completing the book outright.
        func prepareForNewDocument(restoringFraction fraction: Double) {
            progressFlushTimer?.invalidate()
            progressFlushTimer = nil
            lastScrollFraction = fraction
            pageIndex = 0
            pageCount = 1
            isTurnInFlight = false
        }

        /// THE turn function. Taps, arrow keys, trackpad swipes and a finger
        /// swipe that settles past a chapter edge all land here, and the
        /// in-flight flag means one gesture can never produce two turns.
        ///
        /// Page moves inside a chapter are INSTANT offsets. Smooth/animated
        /// scrolling is what broke the previous attempt at native paging: the
        /// pager cancels an in-flight smooth scroll, so the two fight.
        func turn(delta: Int, input: EPUBTurnInput) {
            guard !isTurnInFlight, delta != 0 else { return }
            #if os(iOS)
            // A drag ends with a synthesized click. Without this window that
            // click would be read as an edge tap and turn a second page.
            if input == .tap, let suppressTapUntil, Date() < suppressTapUntil {
                return
            }
            #endif

            let target = pageIndex + delta
            if isHorizontalPaged, target >= 0, target < pageCount {
                isTurnInFlight = true
                scroll(toPage: target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    self?.isTurnInFlight = false
                }
                return
            }

            // At a chapter edge. navigateChapter bounds-checks, so running off
            // the front or back of the BOOK is a no-op rather than a wrap.
            guard EPUBTurnPolicy.crossesChapter(for: input) else {
                onTap()
                return
            }
            isTurnInFlight = true
            onNavigate(delta)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.isTurnInFlight = false
            }
        }

        /// Instant, page-aligned jump. On iOS this drives the paging scroll
        /// view directly so its own idea of the current page stays in sync.
        private func scroll(toPage page: Int) {
            pageIndex = page
            #if os(iOS)
            if let scrollView = webView?.scrollView, isHorizontalPaged {
                let width = scrollView.bounds.width
                let maxX = max(scrollView.contentSize.width - width, 0)
                let x = min(max(CGFloat(page) * width, 0), maxX)
                scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: false)
                flushProgress()
                return
            }
            #endif
            webView?.evaluateJavaScript("window.scoScrollToPage && window.scoScrollToPage(\(page));")
        }

        private func restoreProgress(in webView: WKWebView, fraction: Double) {
            let clamped = min(max(fraction, 0), 1)
            // The page geometry is only knowable after layout, so measure
            // first, then land on the nearest whole page (page mode) or the
            // matching offset (scroll mode).
            let js = """
            requestAnimationFrame(function() {
                if (window.scoLayout) {
                    window.scoLayout();
                    window.scoScrollToFraction(\(clamped));
                    return;
                }
                var doc = document.documentElement;
                var maxY = Math.max(0, doc.scrollHeight - window.innerHeight);
                window.scrollTo(0, \(clamped) * maxY);
                var f = maxY > 0 ? (window.scrollY / maxY) : 0;
                window.webkit.messageHandlers.epubNavigation.postMessage('frac:' + Math.max(0, Math.min(1, f)));
            });
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Non-click navigation (our own loadFileURL, redirects) — allow
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.isFileURL {
                // In-book link: if it maps to a chapter, navigate via SwiftUI
                // (which loads the STYLED copy — allowing the raw navigation
                // would render the chapter without injected styles)
                if onChapterLink(url) {
                    decisionHandler(.cancel)
                    return
                }
                // Same-document anchor (#fragment) — allow the jump
                if url.fragment != nil,
                   url.standardizedFileURL.deletingLastPathComponent() ==
                   webView.url?.standardizedFileURL.deletingLastPathComponent()
                {
                    decisionHandler(.allow)
                    return
                }
                // Unknown file target — don't navigate away from the book
                decisionHandler(.cancel)
            } else {
                // External link — open in the system browser, keep the book
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            #if os(macOS)
            // Give the page keyboard focus as soon as it loads, so the
            // arrow-key handlers in the injected JS work immediately —
            // previously the user had to click the page first, and until
            // then every arrow press fell through and beeped.
            DispatchQueue.main.async {
                webView.window?.makeFirstResponder(webView)
            }
            #endif

            // Same-chapter re-render (font size/theme change) — put the
            // reader back where they were, page-aligned in page mode.
            if let fraction = pendingRestoreFraction, fraction > 0.001 {
                pendingRestoreFraction = nil
                restoreProgress(in: webView, fraction: fraction)
            } else {
                restoreProgress(in: webView, fraction: 0)
            }
        }
    }
}

#if os(iOS)
extension EPUBWebView.Coordinator: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard isHorizontalPaged else { return }
        dragStartOffsetX = scrollView.contentOffset.x
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isHorizontalPaged else { return }
        reportHorizontalProgress(scrollView)
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard isHorizontalPaged else { return }
        let width = max(scrollView.bounds.width, 1)
        let maxX = max(0, scrollView.contentSize.width - width)
        let snapped = round(targetContentOffset.pointee.x / width) * width
        targetContentOffset.pointee.x = min(max(snapped, 0), maxX)
        targetContentOffset.pointee.y = 0

        let nearStart = dragStartOffsetX <= 2
        let nearEnd = dragStartOffsetX >= maxX - 2
        if nearStart && velocity.x < -0.25 {
            pendingBoundarySwipeDelta = -1
        } else if nearEnd && velocity.x > 0.25 {
            pendingBoundarySwipeDelta = 1
        } else {
            pendingBoundarySwipeDelta = nil
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        suppressTapUntil = Date().addingTimeInterval(0.35)
        guard !decelerate else { return }
        finishNativeSwipeIfNeeded(scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishNativeSwipeIfNeeded(scrollView)
    }

    private func finishNativeSwipeIfNeeded(_ scrollView: UIScrollView) {
        let width = max(scrollView.bounds.width, 1)
        let maxX = max(0, scrollView.contentSize.width - width)
        let snapped = min(max(round(scrollView.contentOffset.x / width) * width, 0), maxX)
        if abs(snapped - scrollView.contentOffset.x) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: snapped, y: 0), animated: false)
        }
        reportHorizontalProgress(scrollView)
        // The pager has settled — this position is real, persist it now
        // rather than waiting out the coalescing lull.
        flushProgress()

        guard let delta = pendingBoundarySwipeDelta else { return }
        pendingBoundarySwipeDelta = nil
        turn(delta: delta, input: .swipe)
    }

    private func reportHorizontalProgress(_ scrollView: UIScrollView) {
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let fraction = maxX > 0 ? Double(min(max(scrollView.contentOffset.x / maxX, 0), 1)) : 0
        storeProgress(fraction)
    }
}
#endif

#if os(macOS)
// MARK: - Trackpad paging (macOS)

/// `isPagingEnabled` is a UIScrollView idea and has no NSScrollView equivalent,
/// so the Mac can't have the interactive rubber-banding turn. What it can have
/// is the gesture: a two-finger horizontal swipe becomes one discrete page
/// turn, through the same guarded turn function the keys and click zones use.
final class EPUBTrackpadWebView: WKWebView {
    weak var turnCoordinator: EPUBWebView.Coordinator?

    private var gestureDeltaX: CGFloat = 0
    private var gestureDidTurn = false
    private var isHorizontalGesture = false

    /// Roughly a deliberate flick rather than a stray thumb.
    private let threshold: CGFloat = 40

    override func scrollWheel(with event: NSEvent) {
        guard let coordinator = turnCoordinator, coordinator.isHorizontalPaged,
              event.hasPreciseScrollingDeltas
        else {
            super.scrollWheel(with: event)
            return
        }

        switch event.phase {
        case .began:
            gestureDeltaX = 0
            gestureDidTurn = false
            isHorizontalGesture = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        case .changed:
            guard isHorizontalGesture else { break }
            gestureDeltaX += event.scrollingDeltaX
            if !gestureDidTurn, abs(gestureDeltaX) > threshold {
                gestureDidTurn = true
                // Swiping the content leftwards (negative delta) goes forward,
                // matching the direction of a page turn on iOS.
                coordinator.turn(delta: gestureDeltaX < 0 ? 1 : -1, input: .swipe)
            }
        default:
            break
        }

        // The gesture isn't over when the fingers lift: momentum events keep
        // arriving with an empty phase. They stay ours until the momentum ends,
        // otherwise WebKit would scroll the columns off their page grid on the
        // way out — one flick would turn a page AND leave the text mid-page.
        let gestureFinished = event.phase == .ended || event.phase == .cancelled
        let momentumFinished = event.momentumPhase == .ended || event.momentumPhase == .cancelled

        if !isHorizontalGesture {
            super.scrollWheel(with: event)
        }

        if isHorizontalGesture, gestureFinished, event.momentumPhase == [] {
            // Flick with no momentum to follow — done.
            resetGesture()
        } else if momentumFinished {
            resetGesture()
        }
    }

    private func resetGesture() {
        gestureDeltaX = 0
        gestureDidTurn = false
        isHorizontalGesture = false
    }
}

extension EPUBWebView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    func makeNSView(context: Context) -> WKWebView {
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme,
                          fontFamily: fontFamily, lineSpacing: lineSpacing, margins: margins, restoreProgress: restoreProgress)
            .makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme,
                          fontFamily: fontFamily, lineSpacing: lineSpacing, margins: margins, restoreProgress: restoreProgress)
            .loadContent(into: webView, coordinator: context.coordinator)
    }
}
#else
extension EPUBWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    func makeUIView(context: Context) -> WKWebView {
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme,
                          fontFamily: fontFamily, lineSpacing: lineSpacing, margins: margins, restoreProgress: restoreProgress)
            .makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme,
                          fontFamily: fontFamily, lineSpacing: lineSpacing, margins: margins, restoreProgress: restoreProgress)
            .loadContent(into: webView, coordinator: context.coordinator)
    }
}
#endif



// MARK: - Table of Contents

struct EPUBTableOfContentsView: View {
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var isPresented: Bool

    /// macOS: keep the drawer header (and its close button) below the
    /// window's title-bar drag region, which swallows clicks.
    private var drawerTopPadding: CGFloat {
        #if os(macOS)
        return 38
        #else
        return 0
        #endif
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Dismiss overlay
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }

            // Drawer panel
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Contents")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { withAnimation { isPresented = false } }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.top, drawerTopPadding)
                .background(Color(hex: "#26262E"))

                Divider().background(Color.white.opacity(0.08))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(chapters) { chapter in
                            Button(action: {
                                withAnimation {
                                    currentChapter = chapter.index
                                    isPresented = false
                                }
                            }) {
                                HStack(spacing: 12) {
                                    if chapter.index == currentChapter {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color(hex: "#9B8FE8"))
                                            .frame(width: 3, height: 20)
                                    } else {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.clear)
                                            .frame(width: 3, height: 20)
                                    }

                                    Text(chapter.title)
                                        .font(.system(size: 14))
                                        .foregroundColor(chapter.index == currentChapter
                                            ? Color(hex: "#9B8FE8") : .white.opacity(0.8))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(chapter.index == currentChapter
                                    ? Color(hex: "#9B8FE8").opacity(0.1)
                                    : Color.clear)
                            }
                            .buttonStyle(.plain)

                            Divider().background(Color.white.opacity(0.05))
                        }
                    }
                }
            }
            .frame(width: 300)
            .background(Color(hex: "#1E1E26"))
            .ignoresSafeArea(edges: .vertical)
        }
    }
}

// MARK: - Button Style

struct EPUBPillButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1.0))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
