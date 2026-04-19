//
//  UserManualView.swift
//  SCO-OSXCursor
//
//  Created by SCO Assistant
//

import SwiftUI

@MainActor
struct UserManualView: View {
    @State private var searchText = ""
    
    let shortcuts = [
        ("Next Page", "→"),
        ("Previous Page", "←"),
        ("Show Controls", "↑"),
        ("Hide Controls", "↓"),
        ("Toggle Controls", "Space"),
        ("Close/Exit", "Esc")
    ]
    
    var filteredShortcuts: [(String, String)] {
        if searchText.isEmpty { return shortcuts }
        return shortcuts.filter { $0.0.localizedCaseInsensitiveContains(searchText) || $0.1.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {

                // Header
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("User Manual")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(TextColors.primary)
                    Text("Learn how to use Super Comic Organizer")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                }
                .padding(.bottom, Spacing.md)

                // 1. Library Section
                ManualSection(
                    title: "Library & Organization",
                    icon: "books.vertical",
                    description: "Your digital comic collection, organized automatically."
                ) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        FeatureRow(
                            icon: "magnifyingglass",
                            title: "Smart Search & Filtering",
                            description:
                                "Find comics instantly using the search bar, filter by Publisher, Series, and Year, or isolate books you 'Want to Read'. Use the View options to switch between Grid, List, and Publisher workflows."
                        )

                        FeatureRow(
                            icon: "slider.horizontal.3",
                            title: "Dynamic Cover Grid",
                            description:
                                "Adjust the size of the covers in your library using the zoom slider. Scale up for large artwork, or zoom out for a dense, easy-to-browse layout while keeping all metadata readable."
                        )

                        FeatureRow(
                            icon: "folder.badge.gearshape",
                            title: "Auto-Organization",
                            description:
                                "When importing comics (.cbz, .cbr, .pdf), SCO uses advanced pattern matching to detect the Publisher, Series, and Issue number. Turn on Auto-Organize in Settings to have files automatically sorted into nested folders."
                        )

                        FeatureRow(
                            icon: "house.and.flag",
                            title: "Home Library Folder",
                            description:
                                "Set a Home Library folder in Settings → Home Library to have every confirmed comic automatically moved into a Publisher/Series/ folder structure. The file is also renamed to a clean format (e.g. \"Batman #001 (2025).cbz\") as part of the move."
                        )

                        FeatureRow(
                            icon: "folder.arrow.turn.up.right",
                            title: "Relocating Your Library",
                            description:
                                "If you ever need to move your comic library to a new drive or folder, use the 'Relocate Library' tool in Settings to bulk-update your file paths quickly without losing your database."
                        )

                        // Cloud & Network Drive warning callout
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AccentColors.warning)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Important: Avoid Cloud & Network Drives")
                                    .font(Typography.bodySmall.weight(.semibold))
                                    .foregroundColor(AccentColors.warning)
                                Text("Due to macOS App Sandbox restrictions, SCO cannot create folders or move files inside iCloud Drive, Google Drive, Dropbox, OneDrive, or Network/NAS drives. If your Home Library is set to one of these locations, auto-sorting will silently fail.\n\nChoose a purely local folder instead — Downloads, Documents, or a dedicated folder on your Mac's internal drive all work perfectly.")
                                    .font(Typography.caption)
                                    .foregroundColor(TextColors.secondary)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(Spacing.md)
                        .background(AccentColors.warning.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AccentColors.warning.opacity(0.3), lineWidth: 1)
                        )

                        FeatureRow(
                            icon: "brain.head.profile",
                            title: "Adaptive Learning",
                            description:
                                "The app learns from your manual edits! If you correct a comic's metadata, SCO recognizes the filename pattern and uses it to automatically match future imports from the same series."
                        )
                    }
                }

                // 2. Reading Section
                ManualSection(
                    title: "Reading Experience",
                    icon: "book.pages",
                    description: "A seamless, gesture-driven comic reader."
                ) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {

                        // Mockup of the Reader Tap Zones
                        ReaderZonesMockup()
                            .padding(.vertical, Spacing.md)

                        FeatureRow(
                            icon: "hand.tap",
                            title: "Navigation & Menus",
                            description:
                                "Tap the left edge (15%) to go to the previous page. Tap the right edge (15%) to go to the next page. Tap anywhere in the center (70%) to toggle the reading controls and menu."
                        )

                        FeatureRow(
                            icon: "arrow.left.and.right",
                            title: "Swiping & Zooming",
                            description:
                                "You can also swipe left or right to turn pages. Pinch to zoom into panels. When zoomed in, edge taps are disabled so you can pan around safely—just swipe to navigate."
                        )

                        FeatureRow(
                            icon: "rectangle.split.2x1",
                            title: "Two-Page Spreads",
                            description:
                                "The reader automatically detects two-page spreads. On iPad, turning your device to landscape mode activates Dual-Page mode automatically (adjustable in settings)."
                        )

                        FeatureRow(
                            icon: "text.book.closed",
                            title: "Reading Styles",
                            description:
                                "Enjoy your comics exactly how they were meant to be read. Set per-book Reading Styles including Standard, Manga (Right-to-Left), and Vertical Scroll directly from the Reader Settings via the gear icon."
                        )
                    }
                }

                // 3. Metadata & Publishing
                ManualSection(
                    title: "Metadata & Customization",
                    icon: "tag",
                    description: "Perfect your comic's underlying data."
                ) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        FeatureRow(
                            icon: "pencil",
                            title: "Editing Metadata",
                            description:
                                "Right-click (or long-press) a comic and select 'Edit Metadata'. Changes are kept as a 'draft' until you press Save. This updates the internal database and renames the file if Auto-Organize is on."
                        )

                        FeatureRow(
                            icon: "photo.artframe",
                            title: "Publisher Banners",
                            description:
                                "In the Publisher view, you can click the pencil icon on a publisher's banner to upload a custom 230x100 branding image. Use the 'Manage Publisher Banners' option in Settings for bulk edits."
                        )

                        FeatureRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Regenerating Covers",
                            description:
                                "If a cover is missing or corrupted, select 'Regenerate Cover' from the right-click menu to safely extract a new high-quality thumbnail from the archive."
                        )
                    }
                }

                // 4. Dashboard & Tracking
                ManualSection(
                    title: "Dashboard Tracking",
                    icon: "chart.bar",
                    description: "Keep track of your reading habits."
                ) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        FeatureRow(
                            icon: "calendar.badge.clock",
                            title: "Reading Heatmap",
                            description:
                                "The Dashboard tracks your daily reading activity throughout the year. See your streaks, total pages read, and books finished."
                        )

                        FeatureRow(
                            icon: "list.star",
                            title: "Want to Read & Currently Reading",
                            description:
                                "Add comics to your 'Want to Read' list (from the selection toolbar or context menu) to keep them accessible at the top of the Library and Dashboard. Track the books you've started in the 'Currently Reading' section."
                        )
                    }
                }

                // 5. Shortcuts
                ManualSection(
                    title: "Keyboard Shortcuts",
                    icon: "keyboard",
                    description: "Navigate quickly with keyboard shortcuts."
                ) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        TextField("Search shortcuts...", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .padding(.bottom, Spacing.sm)
                        
                        ForEach(filteredShortcuts, id: \.0) { shortcut in
                            HStack {
                                Text(shortcut.0)
                                    .font(Typography.body)
                                    .foregroundColor(TextColors.primary)
                                Spacer()
                                Text(shortcut.1)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            Divider()
                        }
                    }
                }
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: 800)  // Constrain width for readability
        }
        .background(BackgroundColors.primary)
    }
}

// MARK: - Helper Components

private struct ManualSection<Content: View>: View {
    let title: String
    let icon: String
    let description: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(AccentColors.primary)
                Text(title)
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
            }

            Text(description)
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
                .padding(.bottom, Spacing.sm)

            content()
        }
        .padding(Spacing.xl)
        .background(BackgroundColors.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .fill(AccentColors.primary.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AccentColors.primary)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                Text(description)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
                    .lineSpacing(4)
            }
        }
    }
}

// MARK: - Visual Mockups

private struct ReaderZonesMockup: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text("Tap Zones Diagram")
                .font(Typography.caption)
                .foregroundColor(TextColors.tertiary)

            HStack(spacing: 0) {
                // Left Zone
                ZStack {
                    Rectangle()
                        .fill(Color.blue.opacity(0.1))
                    VStack {
                        Image(systemName: "arrow.left")
                        Text("15%")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.blue)
                }
                .frame(width: 50)

                // Center Zone
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.05))
                    VStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text("70% Center Area")
                            .font(.system(size: 12, weight: .medium))
                        Text("Toggles Menus")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(TextColors.secondary)
                }

                // Right Zone
                ZStack {
                    Rectangle()
                        .fill(Color.blue.opacity(0.1))
                    VStack {
                        Image(systemName: "arrow.right")
                        Text("15%")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.blue)
                }
                .frame(width: 50)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(BorderColors.subtle, lineWidth: 1)
            )
        }
    }
}

#Preview {
    UserManualView()
}
