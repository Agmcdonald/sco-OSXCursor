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
    @Binding var fontSize: Int         // in pt (12–28)

    var onClose: () -> Void
    var onShowSettings: () -> Void
    /// One-click theme cycle from the reader bar (Dark → Light → Sepia).
    var onCycleTheme: () -> Void

    @State private var chapters: [EPUBChapter] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showControls = true
    @State private var autoHideTimer: Timer?
    @State private var showTableOfContents = false

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
                    onTap: { handleTap() },
                    onNavigate: { delta in navigateChapter(by: delta) },
                    onEscape: { handleEscape() }
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

    func makeWebView(coordinator: EPUBWebView.Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(coordinator, name: "epubNavigation")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator

        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        let click = NSClickGestureRecognizer(target: coordinator, action: #selector(EPUBWebView.Coordinator.handleTap))
        webView.addGestureRecognizer(click)
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(EPUBWebView.Coordinator.handleTap))
        webView.addGestureRecognizer(tap)
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
        "\(chapter.index)|\(chapter.fileURL.path)|\(fontSize)|\(readingStyle ?? "")|\(theme.rawValue)"
    }

    func loadContent(into webView: WKWebView, coordinator: EPUBWebView.Coordinator) {
        guard coordinator.lastLoadKey != loadKey else { return }
        coordinator.lastLoadKey = loadKey
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
        let styleStr = ReadingStyle(rawValue: readingStyle ?? "") ?? .verticalScroll
        let isHorizontal = styleStr == .standard || styleStr == .mangaRTL
        
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
        """ : """
        html, body {
            margin: 0 auto !important;
            padding: 0 !important;
        }
        body {
            padding: 32px 24px 64px 24px !important;
            max-width: 680px;
        }
        """

        // JS to handle keyboard pagination and chapter navigation.
        // Escape is also handled here because the WKWebView holds keyboard
        // focus while reading — without this the key fell through unhandled
        // (system beep) unless the controls overlay happened to be visible.
        let js = isHorizontal ? """
        <script>
        document.addEventListener('keydown', function(e) {
            const scrollAmt = window.innerWidth;
            if (e.key === 'ArrowRight') {
                if (window.scrollX + window.innerWidth >= document.documentElement.scrollWidth - 10) {
                    window.webkit.messageHandlers.epubNavigation.postMessage('nextChapter');
                } else {
                    window.scrollBy({ left: scrollAmt, behavior: 'smooth' });
                }
                e.preventDefault();
            } else if (e.key === 'ArrowLeft') {
                if (window.scrollX <= 0) {
                    window.webkit.messageHandlers.epubNavigation.postMessage('prevChapter');
                } else {
                    window.scrollBy({ left: -scrollAmt, behavior: 'smooth' });
                }
                e.preventDefault();
            } else if (e.key === 'Escape') {
                window.webkit.messageHandlers.epubNavigation.postMessage('closeReader');
                e.preventDefault();
            }
        });
        // Auto-focus body so keys are caught immediately
        window.onload = function() { window.focus(); document.body.focus(); };
        </script>
        """ : """
        <script>
        document.addEventListener('keydown', function(e) {
            if (e.key === 'ArrowRight') {
                window.webkit.messageHandlers.epubNavigation.postMessage('nextChapter');
                e.preventDefault();
            } else if (e.key === 'ArrowLeft') {
                window.webkit.messageHandlers.epubNavigation.postMessage('prevChapter');
                e.preventDefault();
            } else if (e.key === 'Escape') {
                window.webkit.messageHandlers.epubNavigation.postMessage('closeReader');
                e.preventDefault();
            }
        });
        window.onload = function() { window.focus(); document.body.focus(); };
        </script>
        """
        
        let colors = theme.cssColors
        let stripInlineColorsJS = """
        <script>
        document.addEventListener("DOMContentLoaded", function() {
            document.querySelectorAll('*').forEach(el => {
                el.style.setProperty('color', '\(colors.text)', 'important');
                el.style.setProperty('background-color', 'transparent', 'important');
            });
        });
        </script>
        """

        let css = """
        <style>
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
        
        let headInjection = "\(css)\n\(js)\n\(stripInlineColorsJS)"
        
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
    var onTap: () -> Void
    var onNavigate: (Int) -> Void
    /// Esc pressed while the page has keyboard focus (sent from injected JS).
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onNavigate: onNavigate, onEscape: onEscape)
    }

    // MARK: - Coordinator (shared)
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onTap: () -> Void
        let onNavigate: (Int) -> Void
        let onEscape: () -> Void
        /// What's currently loaded — lets updateNSView/updateUIView skip
        /// reloads when nothing the page depends on actually changed.
        var lastLoadKey: String?

        init(
            onTap: @escaping () -> Void,
            onNavigate: @escaping (Int) -> Void,
            onEscape: @escaping () -> Void
        ) {
            self.onTap = onTap
            self.onNavigate = onNavigate
            self.onEscape = onEscape
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "epubNavigation", let action = message.body as? String {
                if action == "nextChapter" {
                    onNavigate(1)
                } else if action == "prevChapter" {
                    onNavigate(-1)
                } else if action == "closeReader" {
                    onEscape()
                }
            }
        }

        #if os(macOS)
        @objc func handleTap(_ recognizer: NSGestureRecognizer) { onTap() }
        #else
        @objc func handleTap(_ recognizer: UIGestureRecognizer) { onTap() }
        #endif

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
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
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme)
            .makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme)
            .loadContent(into: webView, coordinator: context.coordinator)
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
        EPUBWebViewHelper(chapter: chapter, fontSize: fontSize, readingStyle: readingStyle, theme: theme)
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

