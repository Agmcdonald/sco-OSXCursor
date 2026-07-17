//
//  ComicReaderView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI
import os

#if os(macOS)
    import AppKit
#endif

// MARK: - Keyboard Monitor (macOS)
#if os(macOS)
    class KeyboardMonitor {
        private var monitor: Any?
        var onLeftArrow: (() -> Void)?
        var onRightArrow: (() -> Void)?
        var onUpArrow: (() -> Void)?
        var onDownArrow: (() -> Void)?
        var onEscape: (() -> Void)?
        var onSpace: (() -> Void)?

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }

                switch event.keyCode {
                case 123:  // Left arrow
                    self.onLeftArrow?()
                    return nil
                case 124:  // Right arrow
                    self.onRightArrow?()
                    return nil
                case 126:  // Up arrow
                    self.onUpArrow?()
                    return nil
                case 125:  // Down arrow
                    self.onDownArrow?()
                    return nil
                case 53:  // Escape
                    self.onEscape?()
                    return nil
                case 49:  // Space bar
                    self.onSpace?()
                    return nil
                default:
                    return event  // Pass through other keys
                }
            }
        }

        func stop() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            stop()
        }
    }
#endif

// MARK: - Comic Reader View
@MainActor
struct ComicReaderView: View {
    let comic: Comic
    // NOTE: dismiss() must ONLY be called on iOS — on macOS the reader lives in
    // a .overlay on ContentView's main window, so calling dismiss() closes the
    // *entire* NSWindow. On macOS, setting readingComic = nil is sufficient.
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var libraryViewModel: LibraryViewModel  // To update progress
    @StateObject private var viewModel = ReaderViewModel()
    @State private var controlsVisible = true
    @State private var showingMenu = false
    @State private var showingThumbnails = false
    @State private var showingReaderSettings = false
    @State private var autoHideTimer: Timer?
    @State private var isFullScreen = false  // Only functional on iPad
    @State private var currentComic: Comic  // Mutable copy for settings changes
    @State private var isDragging = false
    @State private var isPinching = false
    /// The book that follows this one in the library's current sort order —
    /// suggested by the end-of-book "Up Next" preview. Nil = last book.
    @State private var nextComic: Comic?
    @State private var gestureCooldownTask: Task<Void, Never>?
    /// Fraction of screen width for pages in vertical-scroll mode (0.3…1.0).
    /// Tick 4 of 15 on the 0.3…1.0 / 0.05-step slider = 0.5, matching a comfortable reading size.
    @State private var verticalZoomScale: Double = 0.5
    /// Debounces persisting vertical-zoom changes (slider drags / pinch fire rapidly).
    @State private var verticalZoomSaveTask: Task<Void, Never>? = nil
    /// True while the user is actively scrolling the HUD thumbnail strip/rail
    /// (including momentum/deceleration). The auto-hide countdown is suspended
    /// until this returns to false, so the controls never vanish mid-scroll.
    @State private var hudInteractionActive = false
    private let tapCooldown: TimeInterval = 0.22
    #if os(macOS)
        @State private var keyboardMonitor: KeyboardMonitor? = nil
        @State private var showLocateFilePrompt = false
    #endif
    #if os(iOS)
        // Tracks whether the user has manually overridden the auto-orientation layout.
        // When true, device rotation won't fight their chosen spread mode.
        @State private var isManualLayoutOverride = false
        // Swipe-down-to-dismiss gesture state
        @State private var dragOffset: CGFloat = 0
        @State private var dismissDragActive = false
        // While a page is zoomed, vertical drags PAN the page — the dismiss
        // gesture must stand down or it closes the book mid-pan
        @State private var isPageZoomed = false
        // Tap-zone hint overlay — flashes the current zones after the user
        // changes the width setting
        @ObservedObject private var readerSettings = ReaderSettings.shared
        @State private var showTapZoneHint = false
        @State private var tapZoneHintWorkItem: DispatchWorkItem? = nil
        @State private var tapZoneChangedWhileSheetOpen = false
    #endif

    init(comic: Comic) {
        self.comic = comic
        _currentComic = State(initialValue: comic)
        // Restore remembered vertical-scroll zoom (book memory → folder
        // default → global 0.5) so reopening a book keeps its width.
        _verticalZoomScale = State(
            initialValue: ReaderSettings.shared.effectiveVerticalZoom(for: comic))
    }

    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()

            if viewModel.isLoading {
                // Loading state
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                // Error state
                errorView(errorMessage)
            } else if let comicBook = viewModel.comicBook {
                // Reader
                readerView(comicBook)
            }

        }
        #if os(iOS)
        // Swipe-down drag handle pill — fades in as user starts pulling down
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .opacity(Double(min(dragOffset / 40.0, 1.0)))
                .allowsHitTesting(false)
        }
        // Drag visual: follow finger downward only
        .offset(y: max(0, dragOffset))
        // Slight scale-down as a depth cue while dragging
        .scaleEffect(dragOffset > 0 ? max(0.92, 1.0 - dragOffset / 1800.0) : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    // Never hijack drags while an overlay (All Pages grid, menu)
                    // is open — its scroll view needs vertical drags.
                    guard !showingThumbnails, !showingMenu else { return }
                    // Zoomed pages own vertical drags (panning) — don't dismiss
                    guard !isPageZoomed, !isPinching else { return }
                    // In vertical-scroll mode, downward drags SCROLL BACKWARD —
                    // only allow dismissal when the pull starts near the top edge.
                    if viewModel.isVerticalScroll {
                        guard value.startLocation.y < 120 else { return }
                    }
                    // Only activate when gesture is clearly vertical downward
                    guard value.translation.height > 0,
                          value.translation.height > abs(value.translation.width) * 1.2
                    else { return }
                    dismissDragActive = true
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    guard dismissDragActive else { return }
                    dismissDragActive = false

                    let predictedEnd = value.predictedEndTranslation.height
                    let shouldDismiss = dragOffset > 130 || predictedEnd > 400

                    if shouldDismiss {
                        // Slide off screen, then close the cover
                        withAnimation(.easeIn(duration: 0.22)) {
                            dragOffset = 900
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            libraryViewModel.readingComic = nil
                            dragOffset = 0
                        }
                    } else {
                        // Snap back with a spring
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        #endif
        .task {
            AppLog.reader.debug("📖 [ComicReaderView] .task triggered - about to load comic")
            AppLog.reader.debug("📖 [ComicReaderView] Comic: \(comic.fileName)")

            #if os(iOS)
                // Fast-path: if LibraryViewModel pre-fetched this comic, skip the spinner
                if let prefetched = libraryViewModel.consumePrefetchedComicBook(for: comic.id) {
                    viewModel.acceptPrefetched(prefetched, for: comic)
                    AppLog.reader.debug("📖 [ComicReaderView] ⚡ Using pre-fetched data — skipped spinner")
                } else {
                    await viewModel.loadComic(from: comic)
                    AppLog.reader.debug("📖 [ComicReaderView] loadComic() returned")
                }
            #else
                await viewModel.loadComic(from: comic)
                AppLog.reader.debug("📖 [ComicReaderView] loadComic() returned")
            #endif

            // Start auto-hide timer when reader loads
            resetAutoHideTimer()

            // Resolve the "Up Next" suggestion (next book in the library's
            // current sort order / the list this book was opened from)
            nextComic = libraryViewModel.nextComic(after: comic.id)
            viewModel.hasNextIssue = nextComic != nil
            if let next = nextComic {
                AppLog.reader.debug("📖 [ComicReaderView] Up Next resolved: \(next.fileName)")
            }
        }
        // The user advanced forward past the "Up Next" preview — swap books
        .onChange(of: viewModel.advanceToNextIssueRequested) { _, requested in
            if requested { advanceToNextIssue() }
        }
        // Give iOS a decoding head start as soon as the preview appears
        .onChange(of: viewModel.showNextIssuePreview) { _, showing in
            #if os(iOS)
                if showing, let next = nextComic {
                    libraryViewModel.prefetchComic(next)
                }
            #endif
        }
        .onChange(of: viewModel.currentPage) { oldValue, newValue in
            AppLog.reader.debug("📖 [ComicReaderView] Page changed: \(oldValue + 1) → \(newValue + 1)")
            Task {
                await viewModel.onPageChanged(to: newValue)

                // Update the comic in library with new progress
                // Use currentComic (not the original `comic` let) so per-book settings
                // like readingStyle are preserved when saving progress.
                var updatedComic = currentComic
                updatedComic.currentPage = newValue

                // Update status based on progress
                if let totalPages = viewModel.comicBook?.totalPages {
                    if newValue >= totalPages - 1 {
                        updatedComic.status = .completed
                    } else if newValue > 0 {
                        updatedComic.status = .reading
                    }
                }
                updatedComic.lastReadDate = Date()

                await MainActor.run {
                    libraryViewModel.updateComic(updatedComic)
                }
            }
        }
        .onDisappear {
            // Flush the debounced progress save FIRST so the tracker holds the
            // true final position (continuous vertical scrolling can keep the
            // 0.5s debounce from ever firing), then sync the library from it.
            viewModel.flushProgress()
            libraryViewModel.syncProgressFromTracker()
        }
        #if os(macOS)
            .navigationBarBackButtonHidden(true)
            .focusable()
            .onAppear {
                setupKeyboardMonitoring()
            }
            .onDisappear {
                removeKeyboardMonitoring()
            }
        #else
            .navigationBarHidden(true)
            // Use a zero-size GeometryReader to observe real screen dimensions.
            // horizontalSizeClass is .regular on iPad in BOTH portrait and landscape,
            // so aspect-ratio is the only reliable orientation signal.
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            guard !isManualLayoutOverride else { return }
                            let isLandscape = geo.size.width > geo.size.height
                            viewModel.isSpreadMode = isLandscape
                            AppLog.reader.debug("📐 [ComicReaderView] Initial orientation: \(isLandscape ? "landscape (spread)" : "portrait (single)")")
                        }
                        .onChange(of: geo.size) { _, newSize in
                            guard !isManualLayoutOverride else {
                                AppLog.reader.debug("📐 [ComicReaderView] Rotation ignored — manual override active")
                                return
                            }
                            let isLandscape = newSize.width > newSize.height
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.isSpreadMode = isLandscape
                            }
                            AppLog.reader.debug("📐 [ComicReaderView] Rotated — spread: \(isLandscape)")
                        }
                }
            )
            .onDisappear {
                // Clear override so the next comic follows automatic orientation
                isManualLayoutOverride = false
            }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .scoToggleControls)) { _ in
            handleTapToToggleControls()
        }
        // Per-book vertical-scroll zoom memory: persist width changes made via
        // the HUD slider or pinch. Debounced; skipped when the value merely
        // matches the book's effective default (e.g. programmatic restores),
        // so a book without its own memory keeps following its folder default.
        .onChange(of: verticalZoomScale) { _, newValue in
            guard viewModel.isVerticalScroll else { return }
            verticalZoomSaveTask?.cancel()
            verticalZoomSaveTask = Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                guard currentComic.verticalZoomScale != newValue,
                    newValue != ReaderSettings.shared.effectiveVerticalZoom(for: currentComic)
                else { return }
                currentComic.verticalZoomScale = newValue
                currentComic.dateModified = Date()
                libraryViewModel.updateComic(currentComic)
                AppLog.reader.debug(
                    "🔍 [ComicReaderView] Saved vertical zoom memory: \(String(format: "%.2f", newValue))")
            }
        }
        // Per-book zoom memory: persist deliberate zoom changes
        .onReceive(NotificationCenter.default.publisher(for: .scoZoomScaleSettled)) { note in
            guard let scale = note.userInfo?["scale"] as? CGFloat else { return }
            let newValue: Double? = scale > 1.01 ? Double(scale) : nil
            guard currentComic.zoomScale != newValue else { return }
            currentComic.zoomScale = newValue
            currentComic.dateModified = Date()
            libraryViewModel.updateComic(currentComic)
            AppLog.reader.debug("🔍 [ComicReaderView] Saved zoom memory: \(newValue.map { String(format: "%.2f", $0) } ?? "cleared")")
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .scoZoomStateChanged)) { note in
            if let zoomed = note.userInfo?["zoomed"] as? Bool {
                isPageZoomed = zoomed
            }
        }
        // A zoomed page can be discarded by a turn without ever reporting
        // zoom-out (curl mode recreates page VCs) — clear the flag on turns
        .onChange(of: viewModel.currentPage) { _, _ in
            isPageZoomed = false
        }
        // Flash the tap-zone hint when the width setting changes, and again
        // when the settings sheet closes (so it's seen over the page itself)
        .onChange(of: readerSettings.tapZoneWidth) { _, _ in
            if showingReaderSettings { tapZoneChangedWhileSheetOpen = true }
            flashTapZoneHint()
        }
        .onChange(of: showingReaderSettings) { _, isShowing in
            if !isShowing && tapZoneChangedWhileSheetOpen {
                tapZoneChangedWhileSheetOpen = false
                flashTapZoneHint()
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .scoOpenReaderSettings)) { _ in
            showingReaderSettings = true
        }
        #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(_):
                    // Mouse is moving or present - ensure controls show and timer resets
                    if !controlsVisible {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            controlsVisible = true
                        }
                    }
                    resetAutoHideTimer()
                case .ended:
                    // Mouse left the view - let timer finish or hide early if desired
                    break
                }
            }
        #endif
    }

    // MARK: - Reader View
    private func readerView(_ comicBook: ComicBook) -> some View {
        ZStack {
            // Reader content — branch on reading style
            Group {
                if viewModel.isVerticalScroll {
                    // ── Vertical scroll (webtoon) mode ──────────────────────
                    VerticalScrollReaderView(
                        pages: viewModel.allPages,
                        currentPage: $viewModel.currentPage,
                        zoomScale: $verticalZoomScale,
                        pageAspects: viewModel.pageAspects,
                        onBeginDragging: beginDragging,
                        onEndDragging: endDragging,
                        onBeginPinching: beginPinching,
                        onEndPinching: endPinching
                    )
                } else if viewModel.isSpreadMode {
                    // ── Two-page spread (standard or RTL) ───────────────────
                    SpreadReaderView(
                        spreads: viewModel.pageSpreads,
                        currentSpreadIndex: Binding(
                            get: { spreadIndexForPage(viewModel.currentPage) },
                            set: { newSpreadIndex in
                                viewModel.currentPage = pageForSpreadIndex(newSpreadIndex)
                            }
                        ),
                        comic: currentComic,
                        viewModel: viewModel,
                        onBeginDragging: beginDragging,
                        onEndDragging: endDragging,
                        onBeginPinching: beginPinching,
                        onEndPinching: endPinching
                    )
                } else {
                    // ── Single-page (standard or RTL) ────────────────────────
                    PagedReaderView(
                        pages: viewModel.allPages,
                        currentPage: $viewModel.currentPage,
                        comic: currentComic,
                        viewModel: viewModel,
                        onBeginDragging: beginDragging,
                        onEndDragging: endDragging,
                        onBeginPinching: beginPinching,
                        onEndPinching: endPinching
                    )
                }
            }
            // MARK: Unified Global Tap Overlay
            //
            // A simultaneousGesture ensures this tap handler COEXISTS with
            // DragGesture swipes in ComicPageView — neither cancels the other.
            //
            // We use DragGesture(minimumDistance: 0) because TapGesture doesn't
            // expose the tap location. A movement < 10pt is classified as a tap.
            //
            // This single overlay covers both single-page and spread modes,
            // eliminating the "deference gap" (missing receiver in single-page mode)
            // and the "lockdown" (overlay blocking swipes in dual-page mode).
            #if os(iOS)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            let distance = hypot(dx, dy)

                            // Only classify as a tap if movement is tiny
                            guard distance < 10 else { return }

                            // Don't act during active drag / pinch (cooldown state)
                            guard !isDragging && !isPinching else { return }

                            handleGlobalTap(at: value.startLocation)
                        }
                )
            #endif

            // Controls overlay
            ReaderControlsOverlay(
                currentPage: $viewModel.currentPage,
                totalPages: comicBook.totalPages,
                comicTitle: currentComic.displayTitle,  // follows in-place book switches
                pages: viewModel.allPages,
                onClose: {
                    libraryViewModel.readingComic = nil
                },
                controlsVisible: $controlsVisible,
                showingMenu: $showingMenu,
                showingThumbnails: $showingThumbnails,
                isBackgroundLoading: $viewModel.isBackgroundLoading,
                isFullScreen: $isFullScreen,
                isSpreadMode: $viewModel.isSpreadMode,
                isRTL: viewModel.isMangaRTL,
                isVerticalScroll: viewModel.isVerticalScroll,
                thumbnailBarPosition: ReaderSettings.shared.effectiveThumbnailBarPosition(for: currentComic),
                onCycleThumbnailBarPosition: { cycleThumbnailBarPosition() },
                onThumbnailScrollActiveChanged: { active in setHudInteractionActive(active) },
                verticalZoomScale: $verticalZoomScale,
                readingStyle: $viewModel.readingStyle,
                currentComic: $currentComic,
                onUserInteraction: {
                    resetAutoHideTimer()
                },
                onUserToggledSpread: {
                    #if os(iOS)
                        // Lock in the user's manual choice; orientation changes won't override it
                        isManualLayoutOverride = true
                        AppLog.reader.debug("📐 [ComicReaderView] Manual spread override enabled")
                    #endif
                },
                onComicUpdated: { updatedComic in
                    libraryViewModel.updateComic(updatedComic)
                    // Immediately apply any reading style change from the Presets menu
                    let newStyle = ReaderSettings.shared.effectiveReadingStyle(for: updatedComic)
                    if viewModel.readingStyle != newStyle {
                        viewModel.readingStyle = newStyle
                        if newStyle == .verticalScroll {
                            viewModel.isSpreadMode = false
                        }
                    }
                },
                thumbnailForPage: { viewModel.cachedThumbnail(at: $0) },
                requestThumbnail: { viewModel.requestThumbnail(at: $0) }
            )
            // If the controls hide while the strip is mid-scroll, the scroll view
            // leaves the hierarchy without a final .idle phase — clear the flag so
            // the auto-hide can't get wedged "active" forever.
            .onChange(of: controlsVisible) { _, visible in
                if !visible { hudInteractionActive = false }
            }

            // Thumbnail grid overlay
            if showingThumbnails {
                ThumbnailGridView(
                    pages: viewModel.allPages,
                    currentPage: $viewModel.currentPage,
                    isPresented: $showingThumbnails,
                    isRTL: viewModel.isMangaRTL,
                    thumbnailForPage: { viewModel.cachedThumbnail(at: $0) },
                    requestThumbnail: { viewModel.requestThumbnail(at: $0) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(1000)
            }

            // End-of-book "Up Next" preview — slides in from the reading
            // direction like one more page; forward again advances into it.
            if viewModel.showNextIssuePreview, let next = nextComic {
                NextIssuePreviewOverlay(
                    comic: next,
                    isRTL: viewModel.isMangaRTL,
                    onStart: { advanceToNextIssue() },
                    onDismiss: { viewModel.dismissNextIssuePreview() }
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: viewModel.isMangaRTL ? .leading : .trailing)
                            .combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .zIndex(1200)
            }

            // Navigation menu (iPad only)
            #if os(iOS)
                if showingMenu {
                    navigationMenuOverlay
                }

                // Tap-zone hint — flashes after the zone-width setting changes
                if showTapZoneHint {
                    tapZoneHintOverlay
                        .transition(.opacity)
                        .zIndex(1500)
                }
            #endif

            // Hidden Keyboard Shortcuts
            Group {
                // In vertical scroll mode, left/right arrows scroll half a page; otherwise turn pages
                Button("") {
                    if viewModel.isVerticalScroll { viewModel.verticalScrollHalf(forward: false) }
                    else { viewModel.turn(by: -1) }
                }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") {
                    if viewModel.isVerticalScroll { viewModel.verticalScrollHalf(forward: true) }
                    else { viewModel.turn(by: 1) }
                }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { showControls() }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { withAnimation { controlsVisible = false } }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { handleTapToToggleControls() }.keyboardShortcut(.space, modifiers: [])
                Button("") {
                    if viewModel.showNextIssuePreview {
                        viewModel.dismissNextIssuePreview()
                    } else {
                        libraryViewModel.readingComic = nil
                        dismiss()
                    }
                }.keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .sheet(isPresented: $showingReaderSettings) {
            InReaderSettingsView(
                comic: $currentComic,
                isPresented: $showingReaderSettings,
                onComicUpdated: { updatedComic in
                    libraryViewModel.updateComic(updatedComic)
                    // Re-apply reading style immediately
                    let newStyle = ReaderSettings.shared.effectiveReadingStyle(for: updatedComic)
                    viewModel.readingStyle = newStyle
                    if newStyle == .verticalScroll {
                        viewModel.isSpreadMode = false
                    }
                }
            )
        }
    }

    // MARK: - Global Tap Handler (iOS)
    //
    // Zones are computed from the full screen width so the spine area in dual-page
    // mode always falls in the "centre = toggle controls" zone.
    //
    //   Left  0–15%  → Previous page
    //   Right 85–100% → Next page
    //   Centre 15–85% → Toggle controls / HUD
    #if os(iOS)
        /// Full screen width via the active window scene. iOS 26 deprecated
        /// `UIScreen.main`; tap zones are measured in global coordinates, so we
        /// need the screen width (not the container's) to map a tap to a zone.
        private var activeScreenWidth: CGFloat {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first
            return scene?.screen.bounds.width ?? 0
        }

        private func handleGlobalTap(at location: CGPoint) {
            let screenWidth = activeScreenWidth
            guard screenWidth > 0 else { return }
            let percent = location.x / screenWidth

            #if DEBUG
                AppLog.reader.debug("👆 [ComicReaderView] Global tap x=\(Int(location.x))/\(Int(screenWidth)) (\(String(format: "%.0f", percent * 100))%)")
            #endif

            let outerZone: CGFloat = ReaderSettings.shared.tapZoneWidth.fraction

            switch percent {
            case ..<outerZone:
                #if DEBUG
                    AppLog.reader.debug("⬅️ [ComicReaderView] Left zone → previous page")
                #endif
                viewModel.turn(by: -1)

            case (1.0 - outerZone)...:
                #if DEBUG
                    AppLog.reader.debug("➡️ [ComicReaderView] Right zone → next page")
                #endif
                viewModel.turn(by: +1)

            default:
                // While zoomed, ComicPageView owns center taps (debounced
                // toggle + double-tap-to-unzoom) — don't double-fire here
                guard !isPageZoomed else {
                    #if DEBUG
                        AppLog.reader.debug("🎛️ [ComicReaderView] Centre zone (zoomed) → deferred to page")
                    #endif
                    return
                }
                #if DEBUG
                    AppLog.reader.debug("🎛️ [ComicReaderView] Centre zone → toggle controls")
                #endif
                NotificationCenter.default.post(name: .scoToggleControls, object: nil)
            }
        }
    #endif

    // MARK: - Tap Zone Hint (iOS)
    #if os(iOS)
        /// Translucent bands over the live tap zones, with RTL-aware labels.
        /// Purely visual — never intercepts touches.
        private var tapZoneHintOverlay: some View {
            GeometryReader { geo in
                let zoneWidth = geo.size.width * readerSettings.tapZoneWidth.fraction
                let isRTL = viewModel.isMangaRTL

                HStack(spacing: 0) {
                    tapZoneBand(
                        width: zoneWidth,
                        systemImage: "chevron.left",
                        label: isRTL ? "Next" : "Previous"
                    )

                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 22, weight: .medium))
                        Text("Controls")
                            .font(Typography.caption)
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    tapZoneBand(
                        width: zoneWidth,
                        systemImage: "chevron.right",
                        label: isRTL ? "Previous" : "Next"
                    )
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }

        private func tapZoneBand(width: CGFloat, systemImage: String, label: String) -> some View {
            VStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                Text(label)
                    .font(Typography.caption)
            }
            .foregroundColor(.white)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(AccentColors.primary.opacity(0.30))
        }

        /// Show the hint and (re)start the auto-hide timer
        private func flashTapZoneHint() {
            withAnimation(.easeInOut(duration: 0.25)) {
                showTapZoneHint = true
            }
            tapZoneHintWorkItem?.cancel()
            let work = DispatchWorkItem {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showTapZoneHint = false
                }
            }
            tapZoneHintWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }
    #endif

    // MARK: - Navigation Menu Overlay (iPad)
    #if os(iOS)
        private var navigationMenuOverlay: some View {
            ZStack {
                // Dismiss area
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showingMenu = false
                        }
                    }

                // Menu panel
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Navigate To")
                            .font(Typography.h3)
                            .foregroundColor(TextColors.primary)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.top, Spacing.xl)

                        Divider()
                            .background(BorderColors.subtle)
                            .padding(.vertical, Spacing.md)

                        // Menu items
                        MenuNavItem(
                            icon: "xmark.circle.fill", title: "Close Reader",
                            color: AccentColors.error
                        ) {
                            showingMenu = false
                            libraryViewModel.readingComic = nil
                            dismiss()
                        }

                        MenuNavItem(icon: "books.vertical", title: "Library") {
                            showingMenu = false
                            libraryViewModel.readingComic = nil
                            dismiss()
                        }

                        MenuNavItem(icon: "folder.badge.gearshape", title: "Organize") {
                            showingMenu = false
                            libraryViewModel.readingComic = nil
                            dismiss()
                        }

                        Divider()
                            .background(BorderColors.subtle)
                            .padding(.vertical, Spacing.sm)

                        MenuNavItem(
                            icon: "slider.horizontal.3", title: "Reader Settings",
                            color: AccentColors.primary
                        ) {
                            showingMenu = false
                            showingReaderSettings = true
                        }

                        MenuNavItem(icon: "gear", title: "App Settings") {
                            showingMenu = false
                            libraryViewModel.readingComic = nil
                            dismiss()
                        }

                        Divider()
                            .background(BorderColors.subtle)
                            .padding(.vertical, Spacing.md)

                        Button(action: {
                            withAnimation {
                                showingMenu = false
                            }
                        }) {
                            Text("Cancel")
                                .font(Typography.button)
                                .foregroundColor(TextColors.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.bottom, Spacing.xl)
                    }
                    .background(BackgroundColors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(Spacing.xl)
                }
            }
        }
    #endif

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Loading comic...")
                .font(Typography.body)
                .foregroundColor(.white)
        }
    }

    // MARK: - Error View
    private func errorView(_ message: String) -> some View {
        ZStack {
            VStack(spacing: Spacing.xxl) {
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 64))
                        .foregroundColor(AccentColors.error)

                    Text("Unable to Load Comic")
                        .font(Typography.h2)
                        .foregroundColor(.white)

                    Text(message)
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                }

                Button(action: {
                    libraryViewModel.readingComic = nil
                    dismiss()
                }) {
                    Text("Close")
                        .font(Typography.button)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.md)
                        .background(AccentColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                // Locate File button (macOS only) — lets the user re-grant sandbox access
                #if os(macOS)
                    Button(action: {
                        locateFile()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.questionmark")
                            Text("Locate File")
                        }
                        .font(Typography.button)
                        .foregroundColor(TextColors.secondary)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.md)
                        .background(BackgroundColors.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                #endif
            }

            // Always show close button in top-left (especially for iPad)
            VStack {
                HStack {
                    Button(action: {
                        libraryViewModel.readingComic = nil
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(Spacing.lg)

                    Spacer()
                }
                Spacer()
            }
        }
    }

    // MARK: - Helper Methods

    /// Advance into the suggested next book IN PLACE — the same reader
    /// instance tears down the finished book and loads the next one, so the
    /// fullScreenCover / overlay never dismisses and re-presents.
    private func advanceToNextIssue() {
        guard let next = nextComic else { return }
        viewModel.advanceToNextIssueRequested = false
        viewModel.dismissNextIssuePreview()
        AppLog.reader.info("📖 [ComicReaderView] ➡️ Advancing into next issue: \(next.fileName)")

        // EPUBs need a different reader view — swap via the library instead
        if next.fileType == .epub {
            libraryViewModel.readingComic = next
            return
        }

        currentComic = next
        nextComic = nil
        viewModel.hasNextIssue = false
        // The next book carries its own vertical-zoom memory (or folder/global default)
        verticalZoomScale = ReaderSettings.shared.effectiveVerticalZoom(for: next)

        Task {
            #if os(iOS)
                // Use the pre-fetched book (kicked off when the preview
                // appeared) to skip the loading spinner entirely.
                if let prefetched = libraryViewModel.consumePrefetchedComicBook(for: next.id) {
                    viewModel.switchToPrefetched(prefetched, for: next)
                } else {
                    await viewModel.switchToComic(next)
                }
            #else
                await viewModel.switchToComic(next)
            #endif

            // Line up the book after this one
            nextComic = libraryViewModel.nextComic(after: next.id)
            viewModel.hasNextIssue = nextComic != nil
            resetAutoHideTimer()
        }
    }

    /// Show controls and ensure timer is running
    private func showControls() {
        if !controlsVisible {
            withAnimation(.easeInOut(duration: 0.3)) {
                controlsVisible = true
            }
        }
        resetAutoHideTimer()
    }

    /// Reset the auto-hide timer - hides controls after 3 seconds of inactivity
    private func resetAutoHideTimer() {
        autoHideTimer?.invalidate()

        // Start new timer - auto-hide after 3 seconds on both iOS and macOS
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [self] _ in
            Task { @MainActor in
                // Only hide once the user is fully idle: no open menu/sheet AND
                // no active thumbnail scroll (finger down or momentum in motion).
                if !showingMenu && !showingThumbnails && !showingReaderSettings
                    && !hudInteractionActive {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        controlsVisible = false
                    }
                } else {
                    // Still busy — re-check after another interval instead of hiding
                    resetAutoHideTimer()
                }
            }
        }
    }

    /// Called by the controls overlay as the thumbnail strip/rail scroll phase
    /// changes. While interaction is active the pending auto-hide is cancelled;
    /// when it ends, a fresh full-length countdown begins.
    private func setHudInteractionActive(_ active: Bool) {
        guard hudInteractionActive != active else { return }
        hudInteractionActive = active
        if active {
            // Suspend the countdown until motion stops.
            autoHideTimer?.invalidate()
        } else if controlsVisible {
            // Motion stopped — start the clean 3-second countdown now.
            resetAutoHideTimer()
        }
    }

    /// Cycle the thumbnail-bar position (Bottom → Left → Right) for this book and
    /// persist it as a per-book override.
    private func cycleThumbnailBarPosition() {
        let current = ReaderSettings.shared.effectiveThumbnailBarPosition(for: currentComic)
        let next = current.next
        var updated = currentComic
        updated.thumbnailBarPosition = next.rawValue
        updated.dateModified = Date()
        currentComic = updated
        libraryViewModel.updateComic(updated)
        resetAutoHideTimer()
    }

    /// Cancel the auto-hide timer
    private func cancelAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    /// Handle tap to toggle controls visibility
    private func handleTapToToggleControls() {
        #if DEBUG
            AppLog.reader.debug("🟨 [ComicReaderView] handleTapToToggleControls() CALLED")
            AppLog.reader.debug("🟨 [Tap] Toggle controls | Δt=\(Date().timeIntervalSince(viewModel.lastInteractionAt))")
        #endif
        guard Date().timeIntervalSince(viewModel.lastInteractionAt) > tapCooldown else {
            #if DEBUG
                AppLog.reader.error("❌ [Tap] Blocked by cooldown")
            #endif
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            resetAutoHideTimer()
        }
    }

    // MARK: - Gesture State Management

    /// Begin dragging state (called by page gestures)
    private func beginDragging() {
        gestureCooldownTask?.cancel()
        isDragging = true
    }

    /// End dragging state with cooldown (200ms)
    private func endDragging() {
        gestureCooldownTask?.cancel()
        gestureCooldownTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
            if !Task.isCancelled {
                isDragging = false
            }
        }
    }

    /// Begin pinching state (called by page gestures)
    private func beginPinching() {
        gestureCooldownTask?.cancel()
        isPinching = true
    }

    /// End pinching state with cooldown (200ms)
    private func endPinching() {
        gestureCooldownTask?.cancel()
        gestureCooldownTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
            if !Task.isCancelled {
                isPinching = false
            }
        }
    }

    // MARK: - Spread Mode Helpers

    /// Convert page index to spread index
    private func spreadIndexForPage(_ pageIndex: Int) -> Int {
        let spreads = viewModel.pageSpreads

        // Find which spread contains this page
        for (index, spread) in spreads.enumerated() {
            if spread.leftPage.pageNumber - 1 == pageIndex {
                return index
            }
            if let rightPage = spread.rightPage, rightPage.pageNumber - 1 == pageIndex {
                return index
            }
        }

        return 0  // Fallback to first spread
    }

    /// Convert spread index to page index (returns left page of spread)
    private func pageForSpreadIndex(_ spreadIndex: Int) -> Int {
        let spreads = viewModel.pageSpreads
        guard spreadIndex < spreads.count else { return 0 }

        return spreads[spreadIndex].leftPage.pageNumber - 1
    }

    #if os(macOS)
        // MARK: - Locate File (sandbox recovery)

        /// Opens an NSOpenPanel so the user can re-grant sandbox access to a
        /// comic that couldn't be opened (e.g., iCloud file with an expired bookmark).
        /// On success, creates a fresh bookmark, notifies LibraryViewModel to
        /// persist it, then retries loading the comic.
        private func locateFile() {
            let panel = NSOpenPanel()
            panel.title = "Locate \"\(currentComic.fileName)\""
            panel.message = "The file could not be accessed. Please locate it to re-grant access."
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = []  // allow any file type

            // Pre-navigate to the file's parent directory if possible
            let parentDir = currentComic.resolvedURL.deletingLastPathComponent()
            panel.directoryURL = parentDir

            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

            // Create a fresh security-scoped bookmark
            do {
                let bookmark = try selectedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                // Persist via LibraryViewModel notification channel
                NotificationCenter.default.post(
                    name: ReaderViewModel.bookmarkRefreshedNotification,
                    object: nil,
                    userInfo: ["comicID": currentComic.id, "bookmarkData": bookmark]
                )
                // Retry loading
                Task {
                    await viewModel.loadComic(from: currentComic)
                }
            } catch {
                AppLog.reader.error("[ComicReaderView] ❌ Could not create bookmark from located file: \(error)")
            }
        }

        // MARK: - Keyboard Navigation

        /// Setup keyboard event monitoring
        private func setupKeyboardMonitoring() {
            let monitor = KeyboardMonitor()

            monitor.onLeftArrow = { [weak viewModel] in
                guard let viewModel = viewModel else { return }

                Task { @MainActor in
                    // Left = backward: dismiss the "Up Next" preview if showing
                    if viewModel.showNextIssuePreview {
                        viewModel.dismissNextIssuePreview()
                        return
                    }
                    if viewModel.isVerticalScroll {
                        // In vertical scroll mode, left arrow scrolls up half a page
                        viewModel.verticalScrollHalf(forward: false)
                    } else {
                        guard viewModel.currentPage > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if viewModel.isSpreadMode {
                                viewModel.currentPage = max(0, viewModel.currentPage - 2)
                            } else {
                                viewModel.currentPage -= 1
                            }
                        }
                    }
                    // NOTE: Specifically NOT calling resetAutoHideTimer() or showControls()
                    // as arrows represent "passive" reading navigation.
                }
            }

            monitor.onRightArrow = { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                guard let totalPages = viewModel.comicBook?.totalPages else { return }

                Task { @MainActor in
                    if viewModel.isVerticalScroll {
                        // In vertical scroll mode, right arrow scrolls down half a page
                        viewModel.verticalScrollHalf(forward: true)
                    } else {
                        guard viewModel.currentPage < totalPages - 1 else {
                            // Already on the last page → show/advance "Up Next"
                            viewModel.requestForwardPastEnd()
                            return
                        }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if viewModel.isSpreadMode {
                                viewModel.currentPage = min(totalPages - 1, viewModel.currentPage + 2)
                            } else {
                                viewModel.currentPage += 1
                            }
                        }
                    }
                    // NOTE: Specifically NOT calling resetAutoHideTimer() or showControls()
                    // as arrows represent "passive" reading navigation.
                }
            }

            monitor.onUpArrow = { [self] in
                Task { @MainActor in
                    showControls()
                }
            }

            monitor.onDownArrow = { [self] in
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        controlsVisible = false
                    }
                }
            }

            monitor.onEscape = { [self] in
                Task { @MainActor in
                    // Escape closes the "Up Next" preview before the reader
                    if viewModel.showNextIssuePreview {
                        viewModel.dismissNextIssuePreview()
                        return
                    }
                    libraryViewModel.readingComic = nil
                }
            }

            monitor.onSpace = { [self] in
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        controlsVisible.toggle()
                    }
                    if controlsVisible {
                        resetAutoHideTimer()
                    }
                }
            }

            monitor.start()
            keyboardMonitor = monitor
        }

        /// Remove keyboard event monitoring
        private func removeKeyboardMonitoring() {
            keyboardMonitor?.stop()
        }
    #endif
}

// MARK: - Preview
#Preview {
    ComicReaderView(comic: Comic.sample())
}
