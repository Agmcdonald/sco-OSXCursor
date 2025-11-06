//
//  ContentView.swift
//  SCO-OSXCursor
//
//  Created by Andrew McDonald on 11/5/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .library
    
    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case library = "Library"
        case organize = "Organize"
        case learning = "Learning"
        case knowledge = "Knowledge"
        case maintenance = "Maintenance"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .dashboard: return "chart.bar"
            case .library: return "books.vertical"
            case .organize: return "folder.badge.gearshape"
            case .learning: return "brain.head.profile"
            case .knowledge: return "book.closed"
            case .maintenance: return "wrench.and.screwdriver"
            case .settings: return "gear"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(selectedTab: $selectedTab)
                .frame(width: Layout.sidebarWidth)
        } detail: {
            // Main content
            selectedView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    @ViewBuilder
    private func selectedView() -> some View {
        switch selectedTab {
        case .dashboard:
            PlaceholderView(
                title: "Dashboard",
                subtitle: "Overview and statistics will appear here",
                icon: "chart.bar"
            )
        case .library:
            LibraryView()
        case .organize:
            OrganizeView()
        case .learning:
            PlaceholderView(
                title: "Learning",
                subtitle: "Smart organization patterns will appear here",
                icon: "brain.head.profile"
            )
        case .knowledge:
            PlaceholderView(
                title: "Knowledge",
                subtitle: "Publisher mappings and metadata will appear here",
                icon: "book.closed"
            )
        case .maintenance:
            PlaceholderView(
                title: "Maintenance",
                subtitle: "Database and file maintenance tools will appear here",
                icon: "wrench.and.screwdriver"
            )
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @Binding var selectedTab: ContentView.Tab
    
    var body: some View {
        VStack(spacing: 0) {
            // Top section: App logo/title
            VStack(spacing: 12) {
                Text("Super Comic")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                
                Text("Organizer")
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)
            }
            .padding(.vertical, Spacing.xxl)
            
            Divider()
                .background(BorderColors.subtle)
            
            // Navigation items
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                        SidebarItem(
                            icon: tab.icon,
                            title: tab.rawValue,
                            isSelected: selectedTab == tab
                        )
                        .onTapGesture {
                            selectedTab = tab
                        }
                    }
                }
                .padding(.vertical, Spacing.md)
            }
            
            Spacer()
            
            // Bottom section: Theme toggle
            Divider()
                .background(BorderColors.subtle)
            
            HStack {
                Image(systemName: "moon.fill")
                    .font(.system(size: 14))
                Text("Dark Mode")
                    .font(Typography.bodySmall)
                Spacer()
                Text("On")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.tertiary)
            }
            .foregroundColor(TextColors.secondary)
            .padding(Spacing.lg)
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
        .background(isSelected ? AccentColors.primary.opacity(0.12) : Color.clear)
        .foregroundColor(isSelected ? AccentColors.primary : TextColors.secondary)
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
