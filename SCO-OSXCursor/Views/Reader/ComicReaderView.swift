//
//  ComicReaderView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

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
    @State private var gestureCooldownTask: Task<Void, Never>?
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
    #endif

    init(comic: Comic) {
        self.comic = comic
        _currentComic = State(initialValue: comic)
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
            print("📖 [ComicReaderView] .task triggered - about to load comic")
            print("📖 [ComicReaderView] Comic: \(comic.fileName)")

            #if os(iOS)
                // Fast-path: if LibraryViewModel pre-fetched this comic, skip the spinner
                if let prefetched = libraryViewModel.consumePrefetchedComicBook(for: comic.id) {
                    viewModel.acceptPrefetched(prefetched, for: comic)
                    print("📖 [ComicReaderView] ⚡ Using pre-fetched data — skipped spinner")
                } else {
                    await viewModel.loadComic(from: comic)
                    print("📖 [ComicReaderView] loadComic() returned")
                }
            #else
                await viewModel.loadComic(from: comic)
                print("📖 [ComicReaderView] loadComic() returned")
            #endif

            // Start auto-hide timer when reader loads
            resetAutoHideTimer()
        }
        .onChange(of: viewModel.currentPage) { oldValue, newValue in
            print("📖 [ComicReaderView] Page changed: \(oldValue + 1) → \(newValue + 1)")
            Task {
                await viewModel.onPageChanged(to: newValue)

                // Update the comic in library with new progress
                var updatedComic = comic
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
            // Final sync when reader closes
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
                            print("📐 [ComicReaderView] Initial orientation: \(isLandscape ? "landscape (spread)" : "portrait (single)")")
                        }
                        .onChange(of: geo.size) { _, newSize in
                            guard !isManualLayoutOverride else {
                                print("📐 [ComicReaderView] Rotation ignored — manual override active")
                                return
                            }
                            let isLandscape = newSize.width > newSize.height
                            withAnimation(.easeInOut(duration: 0.3)) {
                                viewModel.isSpreadMode = isLandscape
                            }
                            print("📐 [ComicReaderView] Rotated — spread: \(isLandscape)")
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
            // Reader content (single or two-page spread)
            Group {
                if viewModel.isSpreadMode {
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
                comicTitle: comic.displayTitle,
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
                onUserInteraction: {
                    resetAutoHideTimer()
                },
                onUserToggledSpread: {
                    #if os(iOS)
                        // Lock in the user's manual choice; orientation changes won't override it
                        isManualLayoutOverride = true
                        print("📐 [ComicReaderView] Manual spread override enabled")
                    #endif
                }
            )

            // Thumbnail grid overlay
            if showingThumbnails {
                ThumbnailGridView(
                    pages: viewModel.allPages,
                    currentPage: $viewModel.currentPage,
                    isPresented: $showingThumbnails
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(1000)
            }

            // Navigation menu (iPad only)
            #if os(iOS)
                if showingMenu {
                    navigationMenuOverlay
                }
            #endif
        }
        .sheet(isPresented: $showingReaderSettings) {
            InReaderSettingsView(
                comic: $currentComic,
                isPresented: $showingReaderSettings,
                onComicUpdated: { updatedComic in
                    libraryViewModel.updateComic(updatedComic)
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
        private func handleGlobalTap(at location: CGPoint) {
            let screenWidth = UIScreen.main.bounds.width
            guard screenWidth > 0 else { return }
            let percent = location.x / screenWidth

            #if DEBUG
                print(
                    "👆 [ComicReaderView] Global tap x=\(Int(location.x))/\(Int(screenWidth)) (\(String(format: "%.0f", percent * 100))%)"
                )
            #endif

            let outerZone: CGFloat = 0.15

            switch percent {
            case ..<outerZone:
                #if DEBUG
                    print("⬅️ [ComicReaderView] Left zone → previous page")
                #endif
                viewModel.turn(by: -1)

            case (1.0 - outerZone)...:
                #if DEBUG
                    print("➡️ [ComicReaderView] Right zone → next page")
                #endif
                viewModel.turn(by: +1)

            default:
                #if DEBUG
                    print("🎛️ [ComicReaderView] Centre zone → toggle controls")
                #endif
                NotificationCenter.default.post(name: .scoToggleControls, object: nil)
            }
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
                // Only hide if we aren't hovering or menus aren't open
                if !showingMenu && !showingThumbnails && !showingReaderSettings {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        controlsVisible = false
                    }
                } else {
                    // If a menu is open, just reset the timer to check again later
                    resetAutoHideTimer()
                }
            }
        }
    }

    /// Cancel the auto-hide timer
    private func cancelAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    /// Handle tap to toggle controls visibility
    private func handleTapToToggleControls() {
        #if DEBUG
            print("🟨 [ComicReaderView] handleTapToToggleControls() CALLED")
            print(
                "🟨 [Tap] Toggle controls | Δt=\(Date().timeIntervalSince(viewModel.lastInteractionAt))"
            )
        #endif
        guard Date().timeIntervalSince(viewModel.lastInteractionAt) > tapCooldown else {
            #if DEBUG
                print("❌ [Tap] Blocked by cooldown")
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
                print("[ComicReaderView] ❌ Could not create bookmark from located file: \(error)")
            }
        }

        // MARK: - Keyboard Navigation

        /// Setup keyboard event monitoring
        private func setupKeyboardMonitoring() {
            let monitor = KeyboardMonitor()

            monitor.onLeftArrow = { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                guard viewModel.currentPage > 0 else { return }

                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if viewModel.isSpreadMode {
                            viewModel.currentPage = max(0, viewModel.currentPage - 2)
                        } else {
                            viewModel.currentPage -= 1
                        }
                    }
                    // NOTE: Specifically NOT calling resetAutoHideTimer() or showControls()
                    // as arrows represent "passive" reading navigation.
                }
            }

            monitor.onRightArrow = { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                guard let totalPages = viewModel.comicBook?.totalPages else { return }
                guard viewModel.currentPage < totalPages - 1 else { return }

                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if viewModel.isSpreadMode {
                            viewModel.currentPage = min(totalPages - 1, viewModel.currentPage + 2)
                        } else {
                            viewModel.currentPage += 1
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
