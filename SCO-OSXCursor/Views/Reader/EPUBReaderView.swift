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


// MARK: - EPUB Reader View

struct EPUBReaderView: View {
    let comic: Comic

    @Binding var currentChapter: Int
    let totalChapters: Int
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
                    onTap: { handleTap() },
                    onNavigate: { delta in navigateChapter(by: delta) },
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
                    onPreviousChapter: { navigateChapter(by: -1) },
                    onNextChapter: { navigateChapter(by: 1) },
                    onUserInteraction: { resetAutoHideTimer() }
                )
                .transition(.opacity)
            }

            // Table of Contents drawer
            if showTableOfContents {
                EPUBTableOfContentsView(
                    chapters: chapters,
                    currentChapter: $currentChapter,
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

    private func navigateChapter(by delta: Int) {
        let newIndex = currentChapter + delta
        guard newIndex >= 0 && newIndex < totalChapters else { return }
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

    func makeWebView(coordinator: EPUBWebView.Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(coordinator, name: "epubNavigation")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator

        // NOTE: taps/clicks are handled by injected JS (zone paging, controls
        // toggle, link passthrough) — native gesture recognizers on WKWebView
        // cancel the touches WebKit needs to complete link clicks, which made
        // in-book links dead while the recognizer was attached.
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Don't rubber-band vertically when content fits (paged mode) — the
        // bounce otherwise claims vertical drags meant for swipe-to-dismiss
        webView.scrollView.alwaysBounceVertical = false
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

        #if os(iOS)
        // Page mode: the scroll view is LOCKED — pages change as instant
        // jumps (no sliding), driven by taps and by swipe gestures the
        // injected JS detects. This mirrors the comic reader's
        // "no transition" feel and keeps pages perfectly aligned.
        let style = ReadingStyle(rawValue: readingStyle ?? "") ?? .standard
        let paged = (style == .standard || style == .mangaRTL)
        webView.scrollView.isPagingEnabled = false
        webView.scrollView.isScrollEnabled = !paged
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

        let layoutCSS = isHorizontal ? """
        html, body {
            height: 100vh !important;
            width: 100vw !important;
            overflow-y: hidden !important;
            overflow-x: auto !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        body {
            column-width: calc(100vw - \(hPad * 2)px) !important;
            column-gap: \(hPad * 2)px !important;
            column-fill: auto !important;
            box-sizing: border-box !important;
            padding: \(hPad)px !important;
        }
        img {
            max-width: 100% !important;
            max-height: 100vh !important;
            object-fit: contain !important;
        }
        """ : """
        html, body {
            margin: 0 auto !important;
            padding: 0 !important;
        }
        body {
            padding: 32px \(vPad)px 64px \(vPad)px !important;
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
        // Page mode: taps, swipes, and keys turn ONE page as an INSTANT
        // jump (like the comic reader's "no transition") — no sliding.
        // Taps never change chapters — at the first/last page they raise
        // the controls instead, where the Previous/Next buttons live.
        window.scoPageForward = function() {
            var w = window.innerWidth;
            var maxX = document.documentElement.scrollWidth - w;
            var target = (Math.round(window.scrollX / w) + 1) * w;
            if (target > maxX + 10) {
                window.webkit.messageHandlers.epubNavigation.postMessage('toggleControls');
            } else {
                window.scrollTo(target, 0);
            }
        };
        window.scoPageBackward = function() {
            var w = window.innerWidth;
            var page = Math.round(window.scrollX / w);
            if (page <= 0) {
                window.webkit.messageHandlers.epubNavigation.postMessage('toggleControls');
            } else {
                window.scrollTo((page - 1) * w, 0);
            }
        };
        // Swipe gestures (the scroll view itself is locked): a clear
        // horizontal swipe jumps a page, same as an edge tap.
        var scoTouchX = null, scoTouchY = null;
        document.addEventListener('touchstart', function(e) {
            if (e.touches.length === 1) {
                scoTouchX = e.touches[0].clientX;
                scoTouchY = e.touches[0].clientY;
            }
        }, { passive: true });
        document.addEventListener('touchend', function(e) {
            if (scoTouchX === null) { return; }
            var dx = e.changedTouches[0].clientX - scoTouchX;
            var dy = e.changedTouches[0].clientY - scoTouchY;
            scoTouchX = null;
            if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) {
                if (dx < 0) { window.scoPageForward(); } else { window.scoPageBackward(); }
            }
        }, { passive: true });
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
        // Auto-focus body so keys are caught immediately
        window.onload = function() { window.focus(); document.body.focus(); };
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
        window.onload = function() { window.focus(); document.body.focus(); };
        //]]>
        </script>
        """

        // Tap/click zones, handled in-page so they can't interfere with link
        // clicks (native recognizers cancelled WebKit's touch processing and
        // killed in-book links). Links pass through to the navigation policy;
        // edge taps page; center taps toggle the controls overlay.
        let tapZoneFraction = ReaderSettings.shared.tapZoneWidth.fraction
        let tapZonesJS = """
        <script>
        //<![CDATA[
        document.addEventListener('click', function(e) {
            // Let real link clicks through untouched
            if (e.target && e.target.closest && e.target.closest('a[href]')) { return; }
            var f = \(tapZoneFraction);
            var x = e.clientX, w = window.innerWidth;
            if (x < w * f) {
                window.scoPageBackward && window.scoPageBackward();
            } else if (x > w * (1 - f)) {
                window.scoPageForward && window.scoPageForward();
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
        
        let headInjection = "\(css)\n\(js)\n\(tapZonesJS)\n\(stripInlineColorsJS)"
        
        if let range = html.range(of: "</head>", options: .caseInsensitive) {
            return html.replacingCharacters(in: range, with: "\(headInjection)</head>")
        } else if let range = html.range(of: "<html>", options: .caseInsensitive) {
            return html.replacingCharacters(in: range, with: "<html><head>\(headInjection)</head>")
        } else {
            return "<html><head>\(headInjection)</head><body>\(html)</body></html>"
        }
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
    var onTap: () -> Void
    var onNavigate: (Int) -> Void
    /// Esc pressed while the page has keyboard focus (sent from injected JS).
    var onEscape: () -> Void
    /// In-book link to another chapter file — return true if handled.
    var onChapterLink: (URL) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onNavigate: onNavigate, onEscape: onEscape, onChapterLink: onChapterLink)
    }

    // MARK: - Coordinator (shared)
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onTap: () -> Void
        let onNavigate: (Int) -> Void
        let onEscape: () -> Void
        let onChapterLink: (URL) -> Bool
        /// What's currently loaded — lets updateNSView/updateUIView skip
        /// reloads when nothing the page depends on actually changed.
        var lastLoadKey: String?

        init(
            onTap: @escaping () -> Void,
            onNavigate: @escaping (Int) -> Void,
            onEscape: @escaping () -> Void,
            onChapterLink: @escaping (URL) -> Bool
        ) {
            self.onTap = onTap
            self.onNavigate = onNavigate
            self.onEscape = onEscape
            self.onChapterLink = onChapterLink
        }


        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "epubNavigation", let action = message.body as? String {
                if action == "nextChapter" {
                    onNavigate(1)
                } else if action == "prevChapter" {
                    onNavigate(-1)
                } else if action == "closeReader" {
                    onEscape()
                } else if action == "toggleControls" {
                    onTap()
                }
            }
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
        }
    }
}

#if os(macOS)
extension EPUBWebView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    func makeNSView(context: Context) -> WKWebView {
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme,
                          fontFamily: fontFamily, lineSpacing: lineSpacing, margins: margins)
            .makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme,
                          fontFamily: fontFamily, lineSpacing: lineSpacing, margins: margins)
            .loadContent(into: webView, coordinator: context.coordinator)
    }
}
#else
extension EPUBWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    func makeUIView(context: Context) -> WKWebView {
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme,
                          fontFamily: fontFamily, lineSpacing: lineSpacing, margins: margins)
            .makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme,
                          fontFamily: fontFamily, lineSpacing: lineSpacing, margins: margins)
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

