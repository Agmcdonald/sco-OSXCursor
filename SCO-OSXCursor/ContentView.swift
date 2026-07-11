//
//  ContentView.swift
//  SCO-OSXCursor
//
//  Created by Andrew McDonald on 11/5/25.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var organizeViewModel: OrganizeViewModel
    @State private var selectedTab: Tab = .library
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    #if os(iOS)
        /// Compact width = iPhone (and non-Max iPhone landscape) — drives the
        /// tab-bar layout. Regular width (iPad) keeps the split view.
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // Incoming .scobook transfer package (AirDrop / Files / double-click /
    // drag-and-drop onto Library or Organize). Shared so every entry point
    // queues into the same slot instead of racing each other — see
    // IncomingTransferCoordinator for why this isn't just @State here.
    @StateObject private var incomingTransferCoordinator = IncomingTransferCoordinator()

    init() {
        let libVM = LibraryViewModel(database: DatabaseManager.shared)
        _libraryViewModel = StateObject(wrappedValue: libVM)
        _organizeViewModel = StateObject(wrappedValue: OrganizeViewModel(libraryViewModel: libVM))
    }

    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case library = "Library"
        case organize = "Organize"
        case learning = "Learning"
        case knowledge = "Knowledge"
        case maintenance = "Maintenance"
        case userManual = "User Manual"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .dashboard: return "chart.bar"
            case .library: return "books.vertical"
            case .organize: return "folder.badge.gearshape"
            case .learning: return "brain.head.profile"
            case .knowledge: return "book.closed"
            case .maintenance: return "wrench.and.screwdriver"
            case .userManual: return "questionmark.circle"
            case .settings: return "gear"
            }
        }
    }

    /// Chooses the layout for the current platform / size class: iPhone
    /// (compact width) gets a bottom tab bar; iPad regular width and macOS
    /// keep the sidebar split view.
    @ViewBuilder
    private var mainLayout: some View {
        #if os(iOS)
            if horizontalSizeClass == .compact {
                compactTabLayout
            } else {
                splitLayout
            }
        #else
            splitLayout
        #endif
    }

    #if os(iOS)
        /// iPhone: standard bottom tab bar. The first four tabs are shown
        /// directly; the rest (Knowledge, Maintenance, User Manual, Settings)
        /// land in the system "More" tab automatically.
        private var compactTabLayout: some View {
            TabView(selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    detailView(for: tab)
                        .tabItem { Label(tab.rawValue, systemImage: tab.icon) }
                        .tag(tab)
                }
            }
        }
    #endif

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            SidebarView(selectedTab: $selectedTab)
                .environmentObject(settingsViewModel)
                .frame(width: AppLayout.sidebarWidth)
                #if os(iOS)
                // Remove the SYSTEM sidebar toggle at its source (the sidebar
                // column). Removing it only from the detail column (below) was
                // unreliable: it worked in Library (whose .inspector changes
                // toolbar resolution) but on every other tab the system toggle
                // survived next to our custom recall button — a duplicate.
                .toolbar(removing: .sidebarToggle)
                // Replace it with our own collapse button so the open sidebar
                // can still be dismissed, matching the recall button's style.
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                columnVisibility = .detailOnly
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 17, weight: .medium))
                        }
                    }
                }
                #endif
        } detail: {
            // Main content
            detailView(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(iOS)
                // Sidebar-recall button in the navigation bar zone (above content) —
                // only visible on iPad when the sidebar is hidden.
                // The system toggle is removed at the sidebar column (above);
                // removing it here too is belt-and-suspenders for the detail
                // bar so ours is never duplicated.
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if columnVisibility != .all {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    columnVisibility = .all
                                }
                            } label: {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 17, weight: .medium))
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: columnVisibility)
                #endif
        }
        .navigationSplitViewStyle(.balanced)
    }

    var body: some View {
        mainLayout
        .sheet(isPresented: Binding(
            get: { !hasSeenWelcome },
            set: { _ in hasSeenWelcome = true }
        )) {
            WelcomeSheet(hasSeenWelcome: $hasSeenWelcome)
                .environmentObject(settingsViewModel)
        }
        // ── Device transfer: receive a .scobook package ──
        // AirDrop "Open in Super Comic Organizer", the Files app, and macOS
        // double-click all land here via the document type in Info.plist.
        // (Drag-and-drop onto Library/Organize feeds the same coordinator
        // directly, without going through onOpenURL.)
        .onOpenURL { url in
            incomingTransferCoordinator.enqueue(url)
        }
        .sheet(
            item: $incomingTransferCoordinator.incomingPackage,
            onDismiss: {
                // Fires only after UIKit fully tears the sheet down — the
                // safe moment to present the next queued package. Also
                // covers interactive swipe-dismiss, where onDone never runs.
                incomingTransferCoordinator.presentNextQueued()
            }
        ) { package in
            TransferReceiveSheet(package: package, viewModel: libraryViewModel) {
                incomingTransferCoordinator.packageSheetDismissed()
            }
        }
        .alert(
            "Couldn't Open Book Package",
            isPresented: Binding(
                get: { incomingTransferCoordinator.incomingTransferError != nil },
                set: { if !$0 { incomingTransferCoordinator.incomingTransferError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { incomingTransferCoordinator.incomingTransferError = nil }
        } message: {
            Text(incomingTransferCoordinator.incomingTransferError ?? "")
        }
        #if os(iOS)
            // iOS/iPadOS: true full-screen cover — hides system chrome completely
            .fullScreenCover(item: $libraryViewModel.readingComic) { comic in
                // .id(comic.id) forces a full reader rebuild when the book is
                // swapped in place (e.g. advancing via the "Up Next" preview)
                if comic.fileType == .epub {
                    EPUBContentView(comic: comic)
                        .id(comic.id)
                        .environmentObject(libraryViewModel)
                        .ignoresSafeArea()
                        .statusBarHidden(true)
                        .persistentSystemOverlays(.hidden)
                        .featureHint(
                            id: "readerEpub",
                            icon: "textformat",
                            title: "Reading an eBook",
                            message: "Tap the center of the page to show the controls. Adjust text size from the reader bar; font, spacing, and margins live in Settings → Ebook Typography."
                        )
                } else {
                    ComicReaderView(comic: comic)
                        .id(comic.id)
                        .environmentObject(libraryViewModel)
                        .ignoresSafeArea()                          // Art fills the entire glass
                        .statusBarHidden(true)                      // Always hide clock/battery
                        .persistentSystemOverlays(.hidden)          // Always hide home bar
                        .featureHint(
                            id: "readerComic",
                            icon: "book.pages",
                            title: "Welcome to the reader",
                            message: "Tap the screen edges to turn pages and the center to show controls. Reading style — single page, spread, manga, or vertical scroll — can be changed from the controls."
                        )
                }
            }
        #else
            // macOS: the window's NSToolbar floats ABOVE our SwiftUI overlay
            // and silently swallows clicks across the whole top band — the
            // reader's Close/Settings/ToC buttons never received them. Hide
            // the toolbar while a book is open.
            .toolbar(libraryViewModel.readingComic != nil ? .hidden : .automatic, for: .windowToolbar)
            // macOS: overlay on top of the split view
            .overlay {
                if let comic = libraryViewModel.readingComic {
                    // .id(comic.id) forces a full reader rebuild when the book
                    // is swapped in place (advancing via the "Up Next" preview)
                    Group {
                        if comic.fileType == .epub {
                            EPUBContentView(comic: comic)
                                .id(comic.id)
                                .environmentObject(libraryViewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .featureHint(
                                    id: "readerEpub",
                                    icon: "textformat",
                                    title: "Reading an eBook",
                                    message: "Click the center of the page to show the controls. Adjust text size from the reader bar; font, spacing, and margins live in Settings → Ebook Typography."
                                )
                                .transition(.opacity)
                                .zIndex(100)
                        } else {
                            ComicReaderView(comic: comic)
                                .id(comic.id)
                                .environmentObject(libraryViewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .featureHint(
                                    id: "readerComic",
                                    icon: "book.pages",
                                    title: "Welcome to the reader",
                                    message: "Use the arrow keys or click the page edges to turn pages, and click the center to show controls. Reading style — single page, spread, manga, or vertical scroll — can be changed from the controls."
                                )
                                .transition(.opacity)
                                .zIndex(100)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: libraryViewModel.readingComic == nil)
            .onChange(of: libraryViewModel.readingComic) { _, newComic in
                if newComic == nil {
                    // Reader was dismissed — bring the main window back into focus
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.first { $0.isKeyWindow || $0.canBecomeKey }?
                        .makeKeyAndOrderFront(nil)
                    }
                }
            }
        #endif
    }

    @ViewBuilder
    private func detailView(for tab: Tab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView(
                libraryViewModel: libraryViewModel,
                onOpenKnowledge: { selectedTab = .knowledge },
                onOpenMaintenance: { selectedTab = .maintenance }
            )
            .featureHint(
                id: "dashboard",
                icon: "chart.bar",
                title: "Your collection at a glance",
                message: "The Dashboard tracks reading progress, collection stats, and recent activity. It fills in as you import and read books."
            )
        case .library:
            LibraryView(
                viewModel: libraryViewModel,
                columnVisibility: $columnVisibility,
                onAddComicsOrganize: {
                    selectedTab = .organize
                }
            )
            .environmentObject(incomingTransferCoordinator)
            .featureHint(
                id: "library",
                icon: "books.vertical",
                title: "This is your Library",
                message: "Every book you add lives here. Click a cover to start reading, or use Quick Add to import CBZ, CBR, PDF, and EPUB files — whole folders work too."
            )
        case .organize:
            OrganizeView(
                viewModel: organizeViewModel,
                onOpenSettings: { selectedTab = .settings }
            )
            .environmentObject(incomingTransferCoordinator)
                .featureHint(
                    id: "organize",
                    icon: "folder.badge.gearshape",
                    title: "Sort new books into place",
                    message: "Drop files or folders here. Series, issue, and publisher are detected automatically — review each match, then confirm to move books into your home library folder."
                )
        case .learning:
            LearningView(libraryViewModel: libraryViewModel)
                .featureHint(
                    id: "learning",
                    icon: "brain.head.profile",
                    title: "The app learns as you go",
                    message: "Each import teaches the app your naming patterns, so future matches get more accurate. You can review and manage what it has learned here."
                )
        case .knowledge:
            KnowledgeView(libraryViewModel: libraryViewModel)
                .featureHint(
                    id: "knowledge",
                    icon: "book.closed",
                    title: "Explore your collection's knowledge",
                    message: "Browse publishers, series, and creators gathered from your collection and ComicVine metadata."
                )
        case .maintenance:
            MaintenanceView(libraryViewModel: libraryViewModel)
                .featureHint(
                    id: "maintenance",
                    icon: "wrench.and.screwdriver",
                    title: "Housekeeping tools",
                    message: "Rebuild thumbnails, clean up the database, fix broken file links, and clear learned patterns when you need a fresh start."
                )
        case .userManual:
            UserManualView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Welcome Sheet
struct WelcomeSheet: View {
    @Binding var hasSeenWelcome: Bool
    @EnvironmentObject private var settingsViewModel: SettingsViewModel

    /// 0 = feature highlights, 1 = choose home library folder
    @State private var step = 0
    @State private var showingFolderPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                #if os(macOS)
                    if let logo = NSImage(named: "logo_SCO") {
                        Image(nsImage: logo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 160)
                    }
                #else
                    if let logo = UIImage(named: "logo_SCO") {
                        Image(uiImage: logo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 160)
                    }
                #endif

                if step == 0 {
                    featuresStep
                } else {
                    homeFolderStep
                }
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
            .frame(width: 640, height: 660)
        #endif
        .background(BackgroundColors.primary)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                settingsViewModel.setHomeLibraryFolder(url)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    // MARK: Step 1 — feature highlights

    private var featuresStep: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("Welcome to Super Comic Organizer")
                    .font(Typography.h1)
                    .multilineTextAlignment(.center)

                Text("Organize, read, and track your comic collection — here's what you can do.")
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }

            VStack(alignment: .leading, spacing: Spacing.lg) {
                WelcomeHighlight(
                    icon: "plus.rectangle.on.folder",
                    title: "Import in seconds",
                    text: "Use Quick Add to bring in CBZ, CBR, PDF, or EPUB files — or whole folders at once."
                )
                WelcomeHighlight(
                    icon: "sparkle.magnifyingglass",
                    title: "Auto-organized",
                    text: "Series, publisher, and issue are detected automatically, with optional ComicVine lookups."
                )
                WelcomeHighlight(
                    icon: "folder",
                    title: "Make collections",
                    text: "Group books into folders, then browse and sort them in the Folder view."
                )
                WelcomeHighlight(
                    icon: "book.pages",
                    title: "Read your way",
                    text: "A gesture-driven reader with single-page, two-page spread, manga, and vertical-scroll styles."
                )
            }
            .frame(maxWidth: 440, alignment: .leading)

            Button("Continue") {
                step = 1
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, Spacing.sm)
            .tint(AccentColors.primary)

            Text("Need a hand later? Open the User Manual or send feedback from Settings.")
                .font(Typography.caption)
                .foregroundColor(TextColors.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Step 2 — choose home library folder

    private var homeFolderStep: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("Choose a Home for Your Books")
                    .font(Typography.h1)
                    .multilineTextAlignment(.center)

                Text("Pick the folder where your books will be stored. When you confirm imports, files are moved here and organized by publisher and series.")
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                // Current selection / picker
                HStack(spacing: Spacing.md) {
                    Image(systemName: settingsViewModel.settings.rootLibraryPath == nil
                        ? "folder.badge.questionmark" : "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(settingsViewModel.settings.rootLibraryPath == nil
                            ? TextColors.tertiary : AccentColors.success)

                    Text(settingsViewModel.settings.rootLibraryPath?.path ?? "No folder selected")
                        .font(Typography.body)
                        .foregroundColor(settingsViewModel.settings.rootLibraryPath == nil
                            ? TextColors.tertiary : TextColors.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(settingsViewModel.settings.rootLibraryPath == nil
                        ? "Choose Folder…" : "Change…") {
                        showingFolderPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AccentColors.primary)
                }
                .padding(Spacing.md)
                .background(BackgroundColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Cloud & network drive warning (same constraint as Settings)
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AccentColors.warning)
                        .font(.system(size: 13, weight: .semibold))
                    Text("Choose a local folder on your Mac's internal drive (like Documents). Cloud and network drives — iCloud, Dropbox, Google Drive, NAS — can't be used due to macOS sandbox restrictions.")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.sm)
                .background(AccentColors.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: 480)

            VStack(spacing: Spacing.sm) {
                Button(settingsViewModel.settings.rootLibraryPath == nil
                    ? "Skip for Now" : "Get Started") {
                    hasSeenWelcome = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AccentColors.primary)

                Text("You can set or change this anytime in Settings → Organization.")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Welcome Highlight Row

private struct WelcomeHighlight: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(AccentColors.primary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                Text(text)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @Binding var selectedTab: ContentView.Tab

    // Fallback text if logo not found
    private var fallbackText: some View {
        VStack(spacing: 12) {
            Text("Super Comic")
                .font(Typography.h3)
                .foregroundColor(TextColors.primary)

            Text("Organizer")
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
        }
        .padding(.vertical, Spacing.xxl)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top section: App logo
            // (logo_SCO.png is trimmed to the artwork — no transparent
            // canvas — so "fit" fills the frame with visible logo.)
            #if os(macOS)
                if let logo = NSImage(named: "logo_SCO") {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 90)
                        .padding(.vertical, Spacing.md)
                        .padding(.horizontal, Spacing.md)
                } else {
                    fallbackText
                }
            #else
                if let logo = UIImage(named: "logo_SCO") {
                    Image(uiImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 120)
                        .padding(.vertical, Spacing.xl)
                        .padding(.horizontal, Spacing.lg)
                } else {
                    fallbackText
                }
            #endif

            Divider()
                .background(BorderColors.subtle)

            // Navigation items
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(
                        ContentView.Tab.allCases.filter { $0 != .settings && $0 != .userManual },
                        id: \.self
                    ) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            SidebarItem(
                                icon: tab.icon,
                                title: tab.rawValue,
                                isSelected: selectedTab == tab
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Spacing.md)
            }

            Spacer()

            // Bottom section: Settings, User Manual, Theme toggle
            Divider()
                .background(BorderColors.subtle)

            VStack(spacing: 4) {
                Button {
                    selectedTab = .settings
                } label: {
                    SidebarItem(
                        icon: ContentView.Tab.settings.icon,
                        title: ContentView.Tab.settings.rawValue,
                        isSelected: selectedTab == .settings
                    )
                }
                .buttonStyle(.plain)

                #if os(iOS)
                    Button {
                        selectedTab = .userManual
                    } label: {
                        SidebarItem(
                            icon: ContentView.Tab.userManual.icon,
                            title: ContentView.Tab.userManual.rawValue,
                            isSelected: selectedTab == .userManual
                        )
                    }
                    .buttonStyle(.plain)
                #endif
            }
            .padding(.vertical, Spacing.sm)

            Divider()
                .background(BorderColors.subtle)

            Button(action: {
                // Cycle theme: Light -> Dark -> System
                let current = settingsViewModel.settings.theme
                let next: AppSettings.Theme
                switch current {
                case .light: next = .dark
                case .dark: next = .auto
                case .auto: next = .light
                }
                settingsViewModel.settings.theme = next
            }) {
                HStack {
                    Image(
                        systemName: settingsViewModel.settings.theme == .light
                            ? "sun.max.fill"
                            : (settingsViewModel.settings.theme == .dark
                                ? "moon.fill" : "desktopcomputer")
                    )
                    .font(.system(size: 14))
                    Text("Appearance")
                        .font(Typography.bodySmall)
                    Spacer()
                    Text(settingsViewModel.settings.theme.displayName)
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.tertiary)
                }
                .foregroundColor(TextColors.secondary)
                .padding(Spacing.lg)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BackgroundColors.sidebar)
    }
}

// MARK: - Sidebar Item
struct SidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 18, height: 18)

            Text(title)
                .font(Typography.navigation)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AccentColors.primary.opacity(0.12) : Color.clear)
        .foregroundColor(isSelected ? AccentColors.primary : TextColors.secondary)
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
    }
}

// MARK: - Placeholder View
struct PlaceholderView: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(TextColors.tertiary)

            Text(title)
                .font(Typography.h1)
                .foregroundColor(TextColors.primary)

            Text(subtitle)
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BackgroundColors.primary)
    }
}

#Preview {
    ContentView()
}
