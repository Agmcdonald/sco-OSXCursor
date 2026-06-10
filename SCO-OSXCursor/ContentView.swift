//
//  ContentView.swift
//  SCO-OSXCursor
//
//  Created by Andrew McDonald on 11/5/25.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @StateObject private var organizeViewModel: OrganizeViewModel
    @State private var selectedTab: Tab = .library
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

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

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            SidebarView(selectedTab: $selectedTab)
                .environmentObject(settingsViewModel)
                .frame(width: AppLayout.sidebarWidth)
        } detail: {
            // Main content
            selectedView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(iOS)
                // Sidebar-recall button in the navigation bar zone (above content) —
                // only visible on iPad when the sidebar is hidden.
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
        .sheet(isPresented: Binding(
            get: { !hasSeenWelcome },
            set: { _ in hasSeenWelcome = true }
        )) {
            WelcomeSheet(hasSeenWelcome: $hasSeenWelcome)
        }
        #if os(iOS)
            // iOS/iPadOS: true full-screen cover — hides system chrome completely
            .fullScreenCover(item: $libraryViewModel.readingComic) { comic in
                if comic.fileType == .epub {
                    EPUBContentView(comic: comic)
                        .environmentObject(libraryViewModel)
                        .ignoresSafeArea()
                        .statusBarHidden(true)
                        .persistentSystemOverlays(.hidden)
                } else {
                    ComicReaderView(comic: comic)
                        .environmentObject(libraryViewModel)
                        .ignoresSafeArea()                          // Art fills the entire glass
                        .statusBarHidden(true)                      // Always hide clock/battery
                        .persistentSystemOverlays(.hidden)          // Always hide home bar
                }
            }
        #else
            // macOS: overlay on top of the split view
            .overlay {
                if let comic = libraryViewModel.readingComic {
                    Group {
                        if comic.fileType == .epub {
                            EPUBContentView(comic: comic)
                                .environmentObject(libraryViewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(.opacity)
                                .zIndex(100)
                        } else {
                            ComicReaderView(comic: comic)
                                .environmentObject(libraryViewModel)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private func selectedView() -> some View {
        switch selectedTab {
        case .dashboard:
            DashboardView(libraryViewModel: libraryViewModel)
        case .library:
            LibraryView(
                viewModel: libraryViewModel,
                columnVisibility: $columnVisibility,
                onAddComicsOrganize: {
                    selectedTab = .organize
                }
            )
        case .organize:
            OrganizeView(viewModel: organizeViewModel)
        case .learning:
            LearningView()
        case .knowledge:
            KnowledgeView()
        case .maintenance:
            PlaceholderView(
                title: "Maintenance",
                subtitle: "Database and file maintenance tools will appear here in future update",
                icon: "wrench.and.screwdriver"
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
    
    var body: some View {
        VStack(spacing: Spacing.xl) {
            #if os(macOS)
                if let logo = NSImage(named: "logo_SCO") {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 250)
                }
            #else
                if let logo = UIImage(named: "logo_SCO") {
                    Image(uiImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 250)
                }
            #endif
            
            Text("Welcome to SCO!")
                .font(Typography.h1)
                .multilineTextAlignment(.center)
            
            Text("Your ultimate digital comic library. Organize, read, and track your comic collection seamlessly.")
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            
            Button("Get Started") {
                hasSeenWelcome = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, Spacing.lg)
            .tint(AccentColors.primary)
        }
        .padding(Spacing.xxl)
        .frame(width: 600, height: 500)
        .background(BackgroundColors.primary)
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
            #if os(macOS)
                if let logo = NSImage(named: "logo_SCO") {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xxl)
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
