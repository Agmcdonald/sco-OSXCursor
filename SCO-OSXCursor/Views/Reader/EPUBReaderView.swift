//
//  EPUBReaderView.swift
//  SCO-OSXCursor
//
//  A WKWebView-based reader for EPUB books. Renders one chapter at a time with
//  injected CSS for theming, user-controlled font size, and comfortable typography.
//

import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

// MARK: - EPUB Reader View

struct EPUBReaderView: View {
    let comic: Comic

    @Binding var currentChapter: Int
    @Binding var totalChapters: Int
    @Binding var fontSize: Int         // in pt (12–28)

    var onClose: () -> Void
    var onShowSettings: () -> Void

    @State private var chapters: [EPUBChapter] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showControls = true
    @State private var autoHideTimer: Timer?
    @State private var showTableOfContents = false
    @ObservedObject private var settings = ReaderSettings.shared

    private var currentTheme: EPUBTheme {
        settings.effectiveEPUBTheme(for: comic)
    }

    private var currentReadingStyle: ReadingStyle {
        settings.effectiveReadingStyle(for: comic)
    }

    var body: some View {
        ZStack {
            // Background colour matches the active theme
            Color(hex: currentTheme.cssColors.background)
                .ignoresSafeArea()

            if isLoading {
                epubLoadingView
            } else if let error = errorMessage {
                epubErrorView(error)
            } else if !chapters.isEmpty {
                EPUBWebView(
                    chapter: chapters[min(currentChapter, chapters.count - 1)],
                    fontSize: fontSize,
                    readingStyle: currentReadingStyle.rawValue,
                    theme: currentTheme,
                    onTap: { handleTap() },
                    onNavigate: { delta in navigateChapter(by: delta) }
                )
                .ignoresSafeArea()
                .zIndex(0)
            }

            if showControls && !isLoading && errorMessage == nil {
                EPUBReaderControlsOverlay(
                    comic: comic,
                    currentChapter: $currentChapter,
                    totalChapters: totalChapters,
                    fontSize: $fontSize,
                    chapters: chapters,
                    showTableOfContents: $showTableOfContents,
                    onClose: onClose,
                    onShowSettings: onShowSettings,
                    onPreviousChapter: { navigateChapter(by: -1) },
                    onNextChapter: { navigateChapter(by: 1) },
                    onUserInteraction: { resetAutoHideTimer() }
                )
                .transition(.opacity)
                .zIndex(100)
            }

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
        .onAppear { resetAutoHideTimer() }
        #endif
    }

    // MARK: - Chapter Loading

    private func loadChapters() async {
        guard comic.fileType == .epub else {
            errorMessage = "Not a valid EPUB file."
            isLoading = false
            return
        }

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

        do {
            let reader = EPUBReader()
            let loaded = try reader.loadChapters(from: fileURL)
            // Stop security access after extraction completes (files are now in temp dir)
            if didStartAccess { fileURL.stopAccessingSecurityScopedResource() }
            await MainActor.run {
                self.chapters = loaded
                self.isLoading = false
                self.resetAutoHideTimer()
                let boundedChapter = loaded.isEmpty ? 0 : min(max(self.currentChapter, 0), loaded.count - 1)
                DispatchQueue.main.async {
                    self.totalChapters = loaded.count
                    if !loaded.isEmpty {
                        self.currentChapter = boundedChapter
                    }
                }
            }
        } catch {
            if didStartAccess { fileURL.stopAccessingSecurityScopedResource() }
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Navigation

    private func navigateChapter(by delta: Int) {
        let newIndex = currentChapter + delta
        // Use chapters.count once loaded; fall back to totalChapters before load
        let bound = chapters.isEmpty ? totalChapters : chapters.count
        guard newIndex >= 0 && newIndex < bound else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentChapter = newIndex
        }
        resetAutoHideTimer()
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

/// Shared logic for both platform variants of EPUBWebView.
private struct EPUBWebViewHelper {
    let chapter: EPUBChapter
    let fontSize: Int
    let readingStyle: String?
    let theme: EPUBTheme

    func makeWebView(coordinator: EPUBWebView.Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(coordinator, name: "epubNavigation")
        config.userContentController.addUserScript(WKUserScript(
            source: Self.readerBootstrapJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        #if os(macOS)
        let webView = EPUBWKWebView(frame: .zero, configuration: config)
        webView.epubCoordinator = coordinator
        coordinator.webView = webView
        #else
        let webView = WKWebView(frame: .zero, configuration: config)
        #endif
        webView.navigationDelegate = coordinator

        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        coordinator.startKeyboardMonitoring()
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(EPUBWebView.Coordinator.handleTap))
        webView.addGestureRecognizer(tap)
        #endif

        loadContent(into: webView, tracking: coordinator)
        return webView
    }

    func loadContent(into webView: WKWebView, tracking coordinator: EPUBWebView.Coordinator? = nil) {
        webView.loadFileURL(chapter.fileURL, allowingReadAccessTo: FileManager.default.temporaryDirectory)

        // Record what we just loaded so updateNSView/updateUIView can skip unnecessary reloads
        if let coord = coordinator {
            coord.loadedChapterID = chapter.id
            coord.loadedFontSize = fontSize
            coord.loadedReadingStyle = readingStyle
            coord.loadedTheme = theme
            coord.pendingStyleJavaScript = styleApplicationJavaScript()
        }
    }

    // MARK: - Style Injection

    func styleApplicationJavaScript() -> String {
        let styleStr = ReadingStyle(rawValue: readingStyle ?? "") ?? .verticalScroll
        let config: [String: Any] = [
            "css": readerCSS(),
            "textColor": theme.cssColors.text,
            "fontSize": fontSize,
            "isHorizontal": styleStr == .standard || styleStr == .mangaRTL
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: config),
            let json = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return "window.__scoApplyEPUBReaderStyles && window.__scoApplyEPUBReaderStyles(\(json));"
    }

    private func readerCSS() -> String {
        let styleStr = ReadingStyle(rawValue: readingStyle ?? "") ?? .verticalScroll
        let isHorizontal = styleStr == .standard || styleStr == .mangaRTL

        let layoutCSS: String
        if isHorizontal {
            layoutCSS = """
            html, body {
                height: 100vh !important;
                width: 100vw !important;
                overflow-y: hidden !important;
                overflow-x: auto !important;
                margin: 0 !important;
                padding: 0 !important;
            }
            body {
                column-width: calc(100vw - 40px) !important;
                column-gap: 40px !important;
                column-fill: auto !important;
                box-sizing: border-box !important;
                padding: 20px !important;
            }
            img {
                max-width: 100% !important;
                max-height: 100vh !important;
                object-fit: contain !important;
            }
            """
        } else {
            layoutCSS = """
            html {
                height: auto !important;
                margin: 0 !important;
                min-height: 100% !important;
                overflow-x: hidden !important;
                overflow-y: auto !important;
                padding: 0 !important;
            }
            body {
                height: auto !important;
                max-width: 680px !important;
                margin: 0 auto !important;
                overflow: visible !important;
                padding: 32px 24px 64px !important;
                box-sizing: border-box !important;
            }
            img {
                max-width: 100% !important;
                height: auto !important;
            }
            """
        }

        let colors = theme.cssColors
        let codeBackground = theme == .dark ? "#2C2C34" : (theme == .sepia ? "#EDE3C8" : "#F0F0F0")

        return """
        :root { color-scheme: \(theme == .dark ? "dark" : "light"); }
        * { box-sizing: border-box; }
        html, body {
            background-color: \(colors.background) !important;
            color: \(colors.text) !important;
            font-family: -apple-system, 'Georgia', serif !important;
            font-size: \(fontSize)px !important;
            line-height: 1.75 !important;
        }
        \(layoutCSS)
        body, body p, body li, body div, body span, body section, body article,
        body main, body header, body footer, body aside, body nav, body details,
        body summary, body td, body th, body dd, body dt, body figcaption,
        body blockquote, body q, body cite,
        body em, body strong, body b, body i, body small, body sup, body sub,
        body label, body caption {
            color: \(colors.text) !important;
            font-size: \(fontSize)px !important;
            line-height: 1.75 !important;
        }
        body [class], body [id] {
            color: \(colors.text) !important;
        }
        h1, h2, h3, h4, h5, h6 {
            color: \(colors.accent) !important;
            font-weight: 600;
            line-height: 1.35 !important;
            margin-top: 1.5em;
            margin-bottom: 0.5em;
        }
        /* Links must keep the accent colour even when they carry a class/id —
           the body [class]/[id] catch-all above (specificity 0,1,1) would otherwise
           beat a plain `a` rule, flattening TOC/cross-reference links into body text. */
        a, a [class], a [id] { color: \(colors.accent) !important; }
        body a[class], body a[id] { color: \(colors.accent) !important; }
        img { border-radius: 6px; }
        blockquote {
            border-left: 3px solid \(colors.accent);
            margin-left: 0; padding-left: 16px;
            font-style: italic; opacity: 0.85;
        }
        code, pre { background: \(codeBackground) !important; border-radius: 4px; padding: 2px 6px; }
        pre { padding: 12px; }
        """
    }

    private static let readerBootstrapJavaScript = """
    (function() {
        if (window.__scoEPUBReaderBootstrapped) { return; }
        window.__scoEPUBReaderBootstrapped = true;

        var textSelector = 'body, h1, h2, h3, h4, h5, h6, p, li, div, span, section, article, main, header, footer, aside, nav, details, summary, td, th, dd, dt, figcaption, blockquote, q, cite, em, strong, b, i, small, sup, sub, label, caption';
        var mediaTags = { IMG: true, VIDEO: true, CANVAS: true, SVG: true, PATH: true };

        window.__scoApplyEPUBReaderStyles = function(config) {
            if (!config) { return; }
            var root = document.head || document.documentElement;
            if (!root) { return; }

            var style = document.getElementById('sco-reader-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'sco-reader-style';
                root.appendChild(style);
            }
            style.textContent = config.css || '';

            document.querySelectorAll('[style]').forEach(function(el) {
                if (mediaTags[el.tagName]) { return; }
                el.style.removeProperty('color');
                el.style.removeProperty('background-color');
                el.style.removeProperty('background');
                el.style.removeProperty('font-size');
            });

            document.querySelectorAll(textSelector).forEach(function(el) {
                if (mediaTags[el.tagName]) { return; }
                el.style.setProperty('color', config.textColor, 'important');
                el.style.setProperty('font-size', config.fontSize + 'px', 'important');
                el.style.setProperty('line-height', '1.75', 'important');
                if (el.tagName !== 'BODY') {
                    el.style.removeProperty('background-color');
                    el.style.removeProperty('background');
                }
            });

            if (document.body) {
                document.body.setAttribute('tabindex', '-1');
            }
            try {
                window.focus();
                if (document.body && document.body.focus) {
                    document.body.focus({ preventScroll: true });
                }
            } catch (_) {}
        };
    })();
    """
}

/// Platform-aware WKWebView representable for EPUB chapter rendering.
struct EPUBWebView {
    let chapter: EPUBChapter
    let fontSize: Int
    let readingStyle: String?
    let theme: EPUBTheme
    var onTap: () -> Void
    var onNavigate: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap, onNavigate: onNavigate) }

    // MARK: - Coordinator (shared)

    /// Tracks what was last loaded so updateNSView/updateUIView can skip unnecessary reloads.
    /// Without this guard, every SwiftUI re-render (e.g. controls auto-hide timer) reloads the page.
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onTap: () -> Void
        var onNavigate: (Int) -> Void
        weak var webView: WKWebView?

        var loadedChapterID: UUID?
        var loadedFontSize: Int = 0
        var loadedReadingStyle: String?
        var loadedTheme: EPUBTheme?
        var pendingStyleJavaScript: String?

        #if os(macOS)
        private var keyMonitor: Any?
        #endif

        init(onTap: @escaping () -> Void, onNavigate: @escaping (Int) -> Void) {
            self.onTap = onTap
            self.onNavigate = onNavigate
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "epubNavigation", let action = message.body as? String {
                if action == "nextChapter" { onNavigate(1) }
                else if action == "prevChapter" { onNavigate(-1) }
            }
        }

        #if os(macOS)
        deinit {
            stopKeyboardMonitoring()
        }

        func startKeyboardMonitoring() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let webView = self.webView, webView.window?.isKeyWindow == true else {
                    return event
                }
                switch event.keyCode {
                case 123:
                    self.pageTap(direction: -1, webView: webView)
                    return nil
                case 124:
                    self.pageTap(direction: 1, webView: webView)
                    return nil
                case 126:
                    self.scrollVertical(direction: -1, webView: webView)
                    return nil
                case 125, 49:
                    self.scrollVertical(direction: 1, webView: webView)
                    return nil
                default:
                    return event
                }
            }
        }

        func stopKeyboardMonitoring() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        @objc func handleTap(_ recognizer: NSGestureRecognizer) {
            guard recognizer.state == .ended, let webView = recognizer.view as? WKWebView else { return }
            let location = recognizer.location(in: webView)
            handleTap(atX: location.x, width: webView.bounds.width, webView: webView)
        }
        #else
        @objc func handleTap(_ recognizer: UIGestureRecognizer) {
            guard recognizer.state == .ended, let webView = recognizer.view as? WKWebView else { return }
            let location = recognizer.location(in: webView)
            handleTap(atX: location.x, width: webView.bounds.width, webView: webView)
        }
        #endif

        func handleTap(atX x: CGFloat, width: CGFloat, webView: WKWebView) {
            guard width > 0 else {
                onTap()
                return
            }

            let third = width / 3
            if x < third {
                pageTap(direction: -1, webView: webView)
            } else if x > third * 2 {
                pageTap(direction: 1, webView: webView)
            } else {
                onTap()
            }
        }

        private func pageTap(direction: Int, webView: WKWebView) {
            let isHorizontal = loadedReadingStyle == ReadingStyle.standard.rawValue
                || loadedReadingStyle == ReadingStyle.mangaRTL.rawValue
            let js: String
            if isHorizontal {
                js = horizontalPageJavaScript(direction: direction)
            } else {
                js = direction > 0 ? """
                (function() {
                    const scroller = (function() {
                        const candidates = [document.scrollingElement, document.documentElement, document.body]
                            .filter(Boolean);
                        return candidates.reduce(function(best, el) {
                            const bestRange = best ? Math.max(0, best.scrollHeight - best.clientHeight) : -1;
                            const range = Math.max(0, el.scrollHeight - el.clientHeight);
                            return range > bestRange ? el : best;
                        }, null) || document.documentElement || document.body;
                    })();
                    const scrollTop = scroller ? scroller.scrollTop : window.scrollY;
                    const clientHeight = scroller ? scroller.clientHeight : window.innerHeight;
                    const scrollHeight = Math.max(
                        scroller ? scroller.scrollHeight : 0,
                        document.documentElement ? document.documentElement.scrollHeight : 0,
                        document.body ? document.body.scrollHeight : 0
                    );
                    const scrollAmt = Math.floor(clientHeight * 0.85);
                    const atBottom = scrollTop + clientHeight >= scrollHeight - 10;
                    if (atBottom) {
                        window.webkit.messageHandlers.epubNavigation.postMessage('nextChapter');
                    } else if (scroller) {
                        scroller.scrollBy({ top: scrollAmt, behavior: 'smooth' });
                    } else {
                        window.scrollBy({ top: scrollAmt, behavior: 'smooth' });
                    }
                })();
                """ : """
                (function() {
                    const scroller = (function() {
                        const candidates = [document.scrollingElement, document.documentElement, document.body]
                            .filter(Boolean);
                        return candidates.reduce(function(best, el) {
                            const bestRange = best ? Math.max(0, best.scrollHeight - best.clientHeight) : -1;
                            const range = Math.max(0, el.scrollHeight - el.clientHeight);
                            return range > bestRange ? el : best;
                        }, null) || document.documentElement || document.body;
                    })();
                    const scrollTop = scroller ? scroller.scrollTop : window.scrollY;
                    const clientHeight = scroller ? scroller.clientHeight : window.innerHeight;
                    const scrollAmt = Math.floor(clientHeight * 0.85);
                    const atTop = scrollTop <= 10;
                    if (atTop) {
                        window.webkit.messageHandlers.epubNavigation.postMessage('prevChapter');
                    } else if (scroller) {
                        scroller.scrollBy({ top: -scrollAmt, behavior: 'smooth' });
                    } else {
                        window.scrollBy({ top: -scrollAmt, behavior: 'smooth' });
                    }
                })();
                """
            }
            webView.evaluateJavaScript(js)
        }

        private func scrollVertical(direction: Int, webView: WKWebView) {
            let isHorizontal = loadedReadingStyle == ReadingStyle.standard.rawValue
                || loadedReadingStyle == ReadingStyle.mangaRTL.rawValue
            let js: String
            if isHorizontal {
                js = horizontalPageJavaScript(direction: direction)
            } else {
                js = direction > 0 ? """
                (function() {
                    const scroller = (function() {
                        const candidates = [document.scrollingElement, document.documentElement, document.body]
                            .filter(Boolean);
                        return candidates.reduce(function(best, el) {
                            const bestRange = best ? Math.max(0, best.scrollHeight - best.clientHeight) : -1;
                            const range = Math.max(0, el.scrollHeight - el.clientHeight);
                            return range > bestRange ? el : best;
                        }, null) || document.documentElement || document.body;
                    })();
                    const scrollTop = scroller ? scroller.scrollTop : window.scrollY;
                    const clientHeight = scroller ? scroller.clientHeight : window.innerHeight;
                    const scrollHeight = Math.max(
                        scroller ? scroller.scrollHeight : 0,
                        document.documentElement ? document.documentElement.scrollHeight : 0,
                        document.body ? document.body.scrollHeight : 0
                    );
                    const scrollAmt = Math.floor(clientHeight * 0.85);
                    const atBottom = scrollTop + clientHeight >= scrollHeight - 10;
                    if (atBottom) {
                        window.webkit.messageHandlers.epubNavigation.postMessage('nextChapter');
                    } else if (scroller) {
                        scroller.scrollBy({ top: scrollAmt, behavior: 'smooth' });
                    } else {
                        window.scrollBy({ top: scrollAmt, behavior: 'smooth' });
                    }
                })();
                """ : """
                (function() {
                    const scroller = (function() {
                        const candidates = [document.scrollingElement, document.documentElement, document.body]
                            .filter(Boolean);
                        return candidates.reduce(function(best, el) {
                            const bestRange = best ? Math.max(0, best.scrollHeight - best.clientHeight) : -1;
                            const range = Math.max(0, el.scrollHeight - el.clientHeight);
                            return range > bestRange ? el : best;
                        }, null) || document.documentElement || document.body;
                    })();
                    const scrollTop = scroller ? scroller.scrollTop : window.scrollY;
                    const clientHeight = scroller ? scroller.clientHeight : window.innerHeight;
                    const scrollAmt = Math.floor(clientHeight * 0.85);
                    const atTop = scrollTop <= 10;
                    if (atTop) {
                        window.webkit.messageHandlers.epubNavigation.postMessage('prevChapter');
                    } else if (scroller) {
                        scroller.scrollBy({ top: -scrollAmt, behavior: 'smooth' });
                    } else {
                        window.scrollBy({ top: -scrollAmt, behavior: 'smooth' });
                    }
                })();
                """
            }
            webView.evaluateJavaScript(js)
        }

        private func horizontalPageJavaScript(direction: Int) -> String {
            let action = direction > 0 ? "next" : "prev"
            return """
            (function() {
                const scroller = (function() {
                    const candidates = [document.scrollingElement, document.documentElement, document.body]
                        .filter(Boolean);
                    return candidates.reduce(function(best, el) {
                        const bestRange = best ? Math.max(0, best.scrollWidth - best.clientWidth) : -1;
                        const range = Math.max(0, el.scrollWidth - el.clientWidth);
                        return range > bestRange ? el : best;
                    }, null) || document.scrollingElement || document.documentElement || document.body;
                })();
                if (!scroller) { return; }

                const scrollLeft = scroller.scrollLeft;
                const clientWidth = scroller.clientWidth || window.innerWidth;
                const scrollWidth = scroller.scrollWidth;
                const maxScroll = Math.max(0, scrollWidth - clientWidth);
                const pageStride = Math.max(1, clientWidth);
                const currentPage = Math.round(scrollLeft / pageStride);
                const pageCount = Math.max(1, Math.ceil(scrollWidth / pageStride));

                if ("\(action)" === "next") {
                    if (scrollLeft >= maxScroll - 2 || currentPage >= pageCount - 1) {
                        window.webkit.messageHandlers.epubNavigation.postMessage('nextChapter');
                    } else {
                        const target = Math.min(maxScroll, (currentPage + 1) * pageStride);
                        scroller.scrollLeft = target;
                    }
                } else {
                    if (scrollLeft <= 2 || currentPage <= 0) {
                        window.webkit.messageHandlers.epubNavigation.postMessage('prevChapter');
                    } else {
                        const target = Math.max(0, (currentPage - 1) * pageStride);
                        scroller.scrollLeft = target;
                    }
                }
            })();
            """
        }

        func applyPendingStyles(to webView: WKWebView) {
            guard let pendingStyleJavaScript, !pendingStyleJavaScript.isEmpty else { return }
            webView.evaluateJavaScript(pendingStyleJavaScript)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            applyPendingStyles(to: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            // Allow same-document fragment links (footnotes/endnotes) without leaving
            // the styled reader document. Cross-file EPUB links are blocked here
            // because WKWebView would otherwise load raw chapter HTML outside SwiftUI
            // chapter state and without the injected reader CSS.
            if url.fragment != nil,
               let currentURL = webView.url,
               url.removingFragment() == currentURL.removingFragment() {
                decisionHandler(.allow)
                return
            }
            // Block all other activated links (external URLs)
            decisionHandler(.cancel)
        }
    }
}

private extension URL {
    func removingFragment() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.fragment = nil
        return components.url ?? self
    }
}

#if os(macOS)
private final class EPUBWKWebView: WKWebView {
    weak var epubCoordinator: EPUBWebView.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        let topControlsHeight: CGFloat = 120
        let bottomControlsHeight: CGFloat = 170
        let isInTopControls = isFlipped
            ? point.y <= topControlsHeight
            : point.y >= bounds.height - topControlsHeight
        let isInBottomControls = isFlipped
            ? point.y >= bounds.height - bottomControlsHeight
            : point.y <= bottomControlsHeight
        if isInTopControls || isInBottomControls {
            return nil
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        epubCoordinator?.handleTap(atX: location.x, width: bounds.width, webView: self)
    }
}

extension EPUBWebView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    func makeNSView(context: Context) -> WKWebView {
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme)
            .makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        applyUpdate(to: webView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "epubNavigation")
        coordinator.stopKeyboardMonitoring()
    }
}
#else
extension EPUBWebView: UIViewRepresentable {
    typealias UIViewType = WKWebView

    func makeUIView(context: Context) -> WKWebView {
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme)
            .makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        applyUpdate(to: webView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "epubNavigation")
    }
}
#endif

private extension EPUBWebView {
    /// Called by both platform update methods. Skips the reload entirely when nothing
    /// meaningful changed (prevents flickering whenever SwiftUI re-renders the parent,
    /// e.g. when the controls auto-hide timer fires). For font-only changes, patches
    /// the live DOM via JS rather than reloading the full page.
    func applyUpdate(to webView: WKWebView, coordinator: Coordinator) {
        coordinator.onTap = onTap
        coordinator.onNavigate = onNavigate

        let chapterChanged = chapter.id != coordinator.loadedChapterID
        let themeChanged   = theme != coordinator.loadedTheme
        let fontChanged    = fontSize != coordinator.loadedFontSize
        let readingStyleChanged = readingStyle != coordinator.loadedReadingStyle

        guard chapterChanged || themeChanged || fontChanged || readingStyleChanged else { return }

        if !chapterChanged && !themeChanged && !readingStyleChanged && fontChanged {
            let helper = EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme)
            coordinator.pendingStyleJavaScript = helper.styleApplicationJavaScript()
            coordinator.applyPendingStyles(to: webView)
            coordinator.loadedFontSize = fontSize
            return
        }

        if !chapterChanged {
            let helper = EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme)
            coordinator.pendingStyleJavaScript = helper.styleApplicationJavaScript()
            coordinator.applyPendingStyles(to: webView)
            coordinator.loadedFontSize = fontSize
            coordinator.loadedReadingStyle = readingStyle
            coordinator.loadedTheme = theme
            return
        }

        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme)
            .loadContent(into: webView, tracking: coordinator)
    }
}


// MARK: - Table of Contents

struct EPUBTableOfContentsView: View {
    let chapters: [EPUBChapter]
    @Binding var currentChapter: Int
    @Binding var isPresented: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isPresented = false } }

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
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(chapter.index == currentChapter ? Color(hex: "#9B8FE8") : Color.clear)
                                        .frame(width: 3, height: 20)

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
