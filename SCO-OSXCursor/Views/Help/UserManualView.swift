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
                            icon: "checkmark.bubble.fill",
                            title: "Metadata Status Tags",
                            description:
                                "A small speech-bubble tag next to each book shows how complete its metadata is at a glance. Books that have never had a metadata lookup show no tag at all. You can turn these tags off entirely in Settings → Appearance."
                        )

                        // Metadata status legend
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            MetadataDotLegendRow(
                                assetName: "MetaComplete",
                                label: "Green check — Complete",
                                detail: "Series, publisher, issue #, year, writer, artist, cover artist, and colorist are all filled."
                            )
                            MetadataDotLegendRow(
                                assetName: "MetaPartial",
                                label: "Yellow ! — Partial",
                                detail: "Some fields are filled, but not the full set (includes books with only series & publisher)."
                            )
                            MetadataDotLegendRow(
                                assetName: "MetaFailed",
                                label: "Red ✕ — Lookup failed",
                                detail: "A metadata search was attempted but came back empty."
                            )
                            MetadataDotLegendRow(
                                assetName: nil,
                                label: "No tag — Not attempted",
                                detail: "No metadata lookup has been run yet and nothing is filled in."
                            )
                        }
                        .padding(Spacing.md)
                        .background(BackgroundColors.secondary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(BorderColors.subtle, lineWidth: 1)
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
                            icon: "checklist",
                            title: "Selecting Many Books at Once",
                            description:
                                "Enter selection mode with the Select button. 'Select All' grabs everything matching your current search or filter — search a series first to target it precisely. On Mac, shift-click selects every book between your last click and the new one. On iPad, tap one book, then long-press another and choose 'Select Range to Here'."
                        )

                        FeatureRow(
                            icon: "square.and.pencil",
                            title: "Bulk Editing",
                            description:
                                "With books selected, press 'Edit Fields' to change any metadata — series, publisher, year, format, credits, summary — on all of them at once. Fields you leave empty are untouched. In Organize, check staged files and use 'Edit Checked' the same way."
                        )

                        FeatureRow(
                            icon: "trash",
                            title: "Deleting Books & Files",
                            description:
                                "Deleting a book (from its right-click/long-press menu, or 'Delete' in the selection toolbar) removes it from your SCO library but leaves the original file untouched on your drive. To delete the underlying files from your device too, use a folder: gather the books into a folder, then choose 'Delete Folder' → 'Delete Files from Device'. Deleting files from your device is permanent and cannot be undone."
                        )

                        FeatureRow(
                            icon: "folder.badge.questionmark",
                            title: "Fixing Missing Files",
                            description:
                                "If a comic's file gets moved or renamed outside the app, the book is flagged with a ⚠ badge. Right-click (or long-press) it and choose 'Locate File…', then pick the file in its new location — the book re-links to it and the warning clears. This is handy when iCloud, an external drive, or a reorganization moves things around."
                        )

                        FeatureRow(
                            icon: "arrow.triangle.branch",
                            title: "Corrections Re-File Your Books",
                            description:
                                "When you correct a publisher, series, year, or format, books inside your Home Library are automatically moved to the right folder and renamed — and folders left empty by the move (like a misspelled publisher) are cleaned up."
                        )

                        FeatureRow(
                            icon: "externaldrive",
                            title: "Sort by File Size",
                            description:
                                "The sort menu includes File Size (largest first) — perfect for finding which books are taking up the most disk space."
                        )
                    }
                }

                // 1a2. Folders & Collections
                ManualSection(
                    title: "Folders & Collections",
                    icon: "folder",
                    description: "Group books into your own collections — without moving any files."
                ) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        FeatureRow(
                            icon: "folder.badge.plus",
                            title: "Create Folders & Add Books",
                            description:
                                "Folders are your own collections (like \"Marvel Events\" or \"Currently Reading\"). Make one from the scope bar's Folders ▾ menu or the New Folder card in Folder view. To add books, right-click (or long-press) a book and choose 'Add to Folder', or enter Select mode, pick several, and use 'Add to Folder' in the toolbar. A book can live in as many folders as you like, and folders never move or rename your files — they're purely organizational."
                        )

                        FeatureRow(
                            icon: "rectangle.3.group",
                            title: "The Scope Bar",
                            description:
                                "Below the search bar, three quick scopes keep things tidy: 'All Books' shows your whole library, 'Unfiled' shows books that aren't in any folder yet, and the 'Folders ▾' dropdown lists every collection alphabetically with its count. Pick one to filter the grid to it."
                        )

                        FeatureRow(
                            icon: "folder",
                            title: "Folder View",
                            description:
                                "The folder icon in the View toggle opens a grid of collection cards, each with a cover collage and book count, plus 'All Books' and 'Unfiled' cards. Folder view honours the Sort menu, so you can order collections by name, date created, recently modified, or book count. Tap a card to open that collection; right-click (or long-press) a card to Rename it, Set its Cover, or Delete it."
                        )

                        FeatureRow(
                            icon: "photo.on.rectangle.angled",
                            title: "Customizing a Folder's Cover",
                            description:
                                "By default a folder card shows a 2×2 collage of its four most recent covers. To give a collection its own look, right-click (or long-press) its card and open 'Set Cover'. On iPad you can pick 'Choose from Photos…' to use a shot from your photo library or 'Choose from Files…' for an image saved in Files; on Mac, 'Choose Picture…' opens any image on your drive. Either way, or choose 'Pick a Book…' to let one member book's cover represent the whole folder. Pick 'Use Book Collage' anytime to return to the default four-book look. A custom cover only changes how the card looks — it never moves or alters your files."
                        )

                        FeatureRow(
                            icon: "trash",
                            title: "Deleting a Folder",
                            description:
                                "Choosing 'Delete Folder' on a collection gives you three choices: 'Delete Folder Only' removes just the collection and leaves every book in your library; 'Remove Books from App' also removes those books from SCO but leaves the files on your drive; and 'Delete Files from Device' permanently deletes the underlying comic files too. The last option cannot be undone."
                        )

                        FeatureRow(
                            icon: "magnifyingglass",
                            title: "Search Always Finds Everything",
                            description:
                                "Searching always looks across your entire library, even while a folder is selected — so a book is never hidden by your current scope. Use 'Reveal in Folder' from a book's menu to jump straight to a collection it belongs to."
                        )
                    }
                }

                // 1b. Importing Section
                ManualSection(
                    title: "Importing Comics",
                    icon: "square.and.arrow.down",
                    description: "From messy filenames to a clean, organized library."
                ) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        FeatureRow(
                            icon: "plus",
                            title: "Quick Add (Mac & iPad)",
                            description:
                                "Quick Add imports files straight into the library. It accepts folders too: on iPad, navigate INTO a folder in the Files picker and tap 'Open' — every comic inside (including subfolders) is imported."
                        )

                        FeatureRow(
                            icon: "folder.badge.plus",
                            title: "Import Straight into a Folder",
                            description:
                                "Quick Add always imports instantly. When you stage files in Organize and press 'Apply All Ready' with more than one book, SCO asks if you'd like to group them — create a new folder, add them to an existing one, or just import to the library. Applying a single book skips the question."
                        )

                        FeatureRow(
                            icon: "folder.badge.plus",
                            title: "Organize & Scan Folder (Mac)",
                            description:
                                "The Organize tab stages files before import so you can review what was detected. 'Scan Folder…' pulls in an entire folder tree. Files with embedded ComicInfo.xml fill in automatically; the rest are parsed from their filenames and folder names."
                        )

                        FeatureRow(
                            icon: "number",
                            title: "Book Formats: Issue, One-Shot, Volume",
                            description:
                                "Every book has a format. Issues need an issue number ('Series #012 (1994)'). One-shots and graphic novels don't — they're named 'Series (Year)'. Collected editions and manga become Volumes ('Series Vol. 03 (Year)'). The format is auto-detected and can be changed with the picker in Organize's File Details."
                        )

                        FeatureRow(
                            icon: "checkmark.circle.fill",
                            title: "Ready vs. Pending",
                            description:
                                "Books the app is confident about are marked Ready and can be imported in one batch with 'Apply All Ready'. Pending books just need a missing field — fill it in the inspector, or check several and bulk-edit them."
                        )
                    }
                }

                // 1c. Knowledge & Learning
                ManualSection(
                    title: "Knowledge & Learning",
                    icon: "brain.head.profile",
                    description: "The app gets smarter with every book you confirm."
                ) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        FeatureRow(
                            icon: "graduationcap",
                            title: "It Learns From Corrections",
                            description:
                                "Confirming an import teaches the app that series' publisher and format. If you correct a parsed name (say 'ASM' to 'Amazing Spider-Man'), the old name becomes an alias — the next file with that name identifies itself automatically. Folder names help too: a file inside 'Marvel Comics/Amazing Spider-Man/' inherits both."
                        )

                        FeatureRow(
                            icon: "brain.head.profile",
                            title: "The Learning Tab",
                            description:
                                "See everything the app has learned: each known series with its publisher, format, aliases, and how many books you own — plus the history of your corrections. Right-click a series and 'Forget This Series' if it learned something wrong."
                        )

                        FeatureRow(
                            icon: "book.closed",
                            title: "Knowledge Base Deep-Dive",
                            description:
                                "In the Knowledge tab, select any series, publisher, writer, or artist to see live stats from your library: book counts, year ranges, contributors, disk usage, and every related book. Pick a writer to see everything they've worked on."
                        )

                        FeatureRow(
                            icon: "sparkles",
                            title: "Suggestions Stay Clean",
                            description:
                                "Autocomplete suggestions come from your library. When a correction leaves an old name (like a misspelled publisher) with no books, it's removed from suggestions automatically. You can also delete any entry manually in the Knowledge tab."
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
                                "Enjoy your comics exactly how they were meant to be read. Set per-book Reading Styles including Standard, Manga (Right-to-Left), and Vertical Scroll — on Mac via the Presets menu in the reader's top bar, on iPad via the '…' menu."
                        )

                        FeatureRow(
                            icon: "hand.draw",
                            title: "Closing the Reader (iPad)",
                            description:
                                "Swipe down to close the book. In Vertical Scroll mode, swiping down scrolls backward through the strip instead — pull down from the very top edge of the screen to close, or use the X button."
                        )

                        FeatureRow(
                            icon: "square.grid.3x3",
                            title: "All Pages Grid",
                            description:
                                "Open the grid icon in the reader's top bar to see thumbnails of every page and jump anywhere instantly. Thumbnails load on demand, so even very large books open the grid without delay."
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
                            icon: "info.circle",
                            title: "Viewing a Book's Info",
                            description:
                                "To see everything known about a book without editing it, choose 'Show Info' from its right-click/long-press menu — on Mac you can also use the ⓘ button in the toolbar after selecting a book. The Info panel shows the cover, all filled-in metadata (series, creators, summary, tags, rating), where the metadata came from (ComicVine or entered manually), and file details. On iPad it slides up as a sheet you can drag to full height."
                        )

                        FeatureRow(
                            icon: "pencil",
                            title: "Editing Metadata",
                            description:
                                "Right-click (or long-press) a comic and select 'Edit Metadata'. Changes are kept as a 'draft' until you press Save. This updates the internal database and renames the file if Auto-Organize is on."
                        )

                        FeatureRow(
                            icon: "sparkle.magnifyingglass",
                            title: "Fetching from ComicVine",
                            description:
                                "Add a ComicVine API key in Settings, then right-click a book (or select several and use 'Fetch Metadata') to pull publisher, creators, summary, and cover dates automatically."
                        )

                        FeatureRow(
                            icon: "checklist",
                            title: "Reviewing Batch Matches",
                            description:
                                "When you fetch metadata for several books across different series, SCO can stop and let you confirm each match before saving. By default it auto-applies high-confidence matches and only opens the review queue for the uncertain ones — step through them with Confirm, Choose a different match, or Skip. Turn off 'Auto-Apply Confident Matches' in Settings → ComicVine Metadata to review every book instead."
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

                // 4b. Backups & Feedback
                ManualSection(
                    title: "Backups & Feedback",
                    icon: "lifepreserver",
                    description: "Protect your catalog and help shape the app."
                ) {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        FeatureRow(
                            icon: "externaldrive.badge.timemachine",
                            title: "Back Up Your Library",
                            description:
                                "In Settings → Library Backup, tap 'Back Up Library Catalog…' to save a copy of all your books' metadata, reading progress, folders, and learned data. Keep it somewhere safe like iCloud Drive. The backup is your catalog, not the comic files themselves, so it's a small, quick safety net."
                        )

                        FeatureRow(
                            icon: "paperplane.fill",
                            title: "Send Feedback",
                            description:
                                "We're in beta and your input matters. Settings → Feedback & Support → 'Send Feedback' opens an email to our team with your app version and system details attached automatically, so we can reproduce and fix issues quickly. No mail app set up? Copy the address and write from anywhere."
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

private struct MetadataDotLegendRow: View {
    let assetName: String?
    let label: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Group {
                if let assetName {
                    Image(assetName)
                        .resizable()
                        .scaledToFit()
                } else {
                    // "No tag" state — show a faint dashed placeholder
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .foregroundColor(TextColors.tertiary)
                }
            }
            .frame(width: 18, height: 18)
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.bodySmall.weight(.semibold))
                    .foregroundColor(TextColors.primary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
