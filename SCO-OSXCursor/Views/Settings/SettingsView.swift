//
//  SettingsView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI
import UniformTypeIdentifiers
import os

#if os(iOS)
    import UIKit
#endif

#if os(macOS)
    import AppKit
#endif

@MainActor
struct SettingsView: View {
    @ObservedObject private var readerSettings = ReaderSettings.shared
    // The app-wide instance injected at the root (SCO_OSXCursorApp). Using
    // the shared instance — not a private copy — is what makes the theme
    // picker (and every other setting) take effect immediately: the root
    // WindowGroup reads `settings.theme` from this same object.
    @EnvironmentObject private var viewModel: SettingsViewModel

    @Environment(\.openURL) private var openURL

    @State private var showingPathPicker = false
    @State private var showingResetConfirmation = false
    @State private var showingBrandingSheet = false
    @State private var showingReorganizeSheet = false
    @State private var showingRelocateSheet = false
    @State private var homeLibraryStatus: SettingsViewModel.HomeLibraryStatus = .notSet
    @State private var allComicsForReorganize: [Comic] = []
    @State private var allComicsForRelocate: [Comic] = []

    // Publishers from the library (deduped) for the branding tool
    @State private var libraryPublishers: [String] = []

    // Feedback
    @State private var didCopyEmail = false

    // Feature hints reset (Appearance section)
    @State private var didResetHints = false

    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("showMetadataTags") private var showMetadataTags = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Appearance Settings Section
                settingsSection(title: "Appearance", icon: "paintbrush.fill") {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Picker("App Theme", selection: viewModel.theme) {
                            ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
                                Text(theme.displayName).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Choose between Light, Dark, or follow your System settings.")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                            
                        Divider()
                            .background(BorderColors.subtle)
                            .padding(.vertical, Spacing.xs)
                            
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Show Welcome Screen")
                                    .font(Typography.h3)
                                    .foregroundColor(TextColors.primary)
                                
                                Text("Display the welcome sheet the next time the app starts")
                                    .font(Typography.bodySmall)
                                    .foregroundColor(TextColors.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { !hasSeenWelcome },
                                set: { hasSeenWelcome = !$0 }
                            ))
                            .labelsHidden()
                        }

                        Divider()
                            .background(BorderColors.subtle)
                            .padding(.vertical, Spacing.xs)

                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Show Feature Hints Again")
                                    .font(Typography.h3)
                                    .foregroundColor(TextColors.primary)

                                Text(didResetHints
                                    ? "Hints re-armed — they'll appear as you revisit each area"
                                    : "Replay the one-time tips that introduce each area of the app")
                                    .font(Typography.bodySmall)
                                    .foregroundColor(TextColors.secondary)
                            }

                            Spacer()

                            Button(didResetHints ? "Done" : "Reset") {
                                FeatureHintStore.resetAll()
                                didResetHints = true
                            }
                            .disabled(didResetHints)
                        }

                        Divider()
                            .background(BorderColors.subtle)
                            .padding(.vertical, Spacing.xs)

                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Show Metadata Status Tags")
                                    .font(Typography.h3)
                                    .foregroundColor(TextColors.primary)

                                Text("Display the green / amber / red bubble on each book showing how complete its metadata is")
                                    .font(Typography.bodySmall)
                                    .foregroundColor(TextColors.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $showMetadataTags)
                                .labelsHidden()
                        }
                    }
                }

                // Organization Settings Section
                settingsSection(title: "Organization", icon: "folder.badge.gearshape") {
                    organizationSettings
                }

                // Reader Settings Section
                settingsSection(title: "Reader", icon: "book.fill") {
                    readerDefaultsSettings
                }

                // Ebook Typography Section
                settingsSection(title: "Ebook Typography", icon: "textformat") {
                    ebookTypographySettings
                }

                // Publisher Branding Section
                settingsSection(title: "Publisher Branding", icon: "building.2") {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(
                            "Assign custom 230 x 100 banner images to each publisher. These appear in Publisher View."
                        )
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)

                        Button {
                            Task {
                                // Fetch deduped publishers before opening sheet
                                let comics =
                                    (try? await DatabaseManager.shared.fetchAllComics()) ?? []
                                libraryPublishers = Array(Set(comics.compactMap { $0.publisher }))
                                    .sorted()
                                showingBrandingSheet = true
                            }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "photo.badge.plus")
                                Text("Manage Publisher Banners")
                                    .font(Typography.button)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // ComicVine Metadata Section
                settingsSection(title: "ComicVine Metadata", icon: "network") {
                    comicVineSettings
                }

                // Feedback & Support Section
                settingsSection(title: "Feedback & Support", icon: "envelope") {
                    feedbackSettings
                }
            }
            .padding(Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BackgroundColors.primary)
        #if os(macOS)
            .frame(minWidth: 600, minHeight: 600)
        #endif
        .sheet(isPresented: $showingBrandingSheet) {
            BatchPublisherBrandingView(libraryPublishers: libraryPublishers)
        }
        .sheet(isPresented: $showingReorganizeSheet) {
            if let libraryRoot = viewModel.resolveHomeLibraryURL() {
                ReorganizeLibraryView(
                    libraryRoot: libraryRoot,
                    comics: allComicsForReorganize
                )
            }
        }
        .sheet(isPresented: $showingRelocateSheet) {
            // Use storedHomeLibraryURL() as old root — resolveHomeLibraryURL() may
            // return nil when the bookmark is stale (which is exactly when this sheet
            // is needed). Fall back to it if somehow resolve succeeds.
            if let oldRoot = viewModel.storedHomeLibraryURL() ?? viewModel.resolveHomeLibraryURL() {
                RelocateLibraryView(
                    oldRoot: oldRoot,
                    comics: allComicsForRelocate,
                    settingsViewModel: viewModel
                )
            }
        }
        .onChange(of: showingRelocateSheet) { _, isShowing in
            // Refresh status badge after the relocate sheet closes
            if !isShowing {
                homeLibraryStatus = viewModel.homeLibraryStatus()
            }
        }
        .fileImporter(
            isPresented: $showingPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handlePathSelection(result)
        }
        .alert("Reset to Defaults", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                viewModel.resetToDefaults()
                homeLibraryStatus = viewModel.homeLibraryStatus()
            }
        } message: {
            Text(
                "This will reset all organization settings to their default values. This action cannot be undone."
            )
        }
        .onAppear {
            homeLibraryStatus = viewModel.homeLibraryStatus()
        }
    }

    // MARK: - Reader Defaults
    //
    // App-wide defaults. Individual books can still override transition,
    // reading style, and EPUB theme from the in-reader settings sheet —
    // those overrides always win over these defaults.

    private var readerDefaultsSettings: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Default page transition
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Default Page Transition")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Text("Used by books without a custom transition")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                Picker("", selection: $readerSettings.pageTransition) {
                    ForEach(
                        PageTransition.allCases.filter { $0.isAvailableOnCurrentPlatform },
                        id: \.self
                    ) { transition in
                        Label(transition.rawValue, systemImage: transition.icon)
                            .tag(transition)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Default reading style
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Default Reading Style")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Text(readerSettings.defaultReadingStyle.description)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                Picker("", selection: $readerSettings.defaultReadingStyle) {
                    ForEach(ReadingStyle.allCases, id: \.self) { style in
                        Label(style.displayName, systemImage: style.icon)
                            .tag(style)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Default EPUB theme
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Default eBook Theme")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Text("Used by EPUBs without a custom theme")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                Picker("", selection: $readerSettings.defaultEPUBTheme) {
                    ForEach(EPUBTheme.allCases, id: \.self) { theme in
                        Label(theme.displayName, systemImage: theme.icon)
                            .tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            #if os(iOS)
                // Tap-zone width (touch only)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Tap Zone Width")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)

                    Text("How much of each screen edge turns the page when tapped (\(readerSettings.tapZoneWidth.description)); the middle toggles controls")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)

                    Picker("", selection: $readerSettings.tapZoneWidth) {
                        ForEach(TapZoneWidth.allCases, id: \.self) { width in
                            Text(width.rawValue).tag(width)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(Spacing.md)
                .background(BackgroundColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            #endif
        }
    }

    // MARK: - Ebook Typography Settings
    //
    // Applies to all EPUBs; font size stays per-book and is adjusted from
    // the reader bar.

    private var ebookTypographySettings: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Font, line spacing, and margins for all eBooks. Text size is adjusted per book from the reader bar.")
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)

            // Live preview — re-renders as the pickers below change
            typographyPreview

            HStack {
                Text("Font")
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                Spacer()
                Picker("", selection: $readerSettings.epubFontFamily) {
                    ForEach(EPUBFontFamily.allCases, id: \.self) { family in
                        Text(family.displayName).tag(family)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Line Spacing")
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                Picker("", selection: $readerSettings.epubLineSpacing) {
                    ForEach(EPUBLineSpacing.allCases, id: \.self) { spacing in
                        Text(spacing.displayName).tag(spacing)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, Spacing.xs)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Margins")
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                Picker("", selection: $readerSettings.epubMargins) {
                    ForEach(EPUBMargins.allCases, id: \.self) { margin in
                        Text(margin.displayName).tag(margin)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.md)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - ComicVine Settings

    @AppStorage(ComicVineConfig.apiKeyDefaultsKey) private var comicVineAPIKey: String = ""
    @AppStorage("autoApplyConfidentMatches") private var autoApplyConfidentMatches = true
    @AppStorage("singleTapConfirmMatch") private var singleTapConfirmMatch = false
    @ObservedObject private var comicVineQuota = ComicVineQuota.shared

    private var comicVineSettings: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Pull publisher, creators, summary, and cover dates for your comics from ComicVine. Free for personal use — get a key by signing in at comicvine.gamespot.com/api.")
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("API Key")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                SecureField("Paste your ComicVine API key", text: $comicVineAPIKey)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                    .padding(Spacing.md)
                    .background(BackgroundColors.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(BorderColors.subtle, lineWidth: 1)
                    )
                    #if os(iOS)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    #endif

                HStack(spacing: Spacing.xs) {
                    Image(systemName: comicVineAPIKey.isEmpty ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text(comicVineAPIKey.isEmpty ? "No key set — fetching is disabled" : "Key saved")
                        .font(Typography.caption)
                }
                .foregroundColor(comicVineAPIKey.isEmpty ? TextColors.tertiary : AccentColors.success)
            }

            Divider()
                .background(BorderColors.subtle)
                .padding(.vertical, Spacing.xs)

            // Live quota readout (mirrors the dashboard widget)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("API Calls This Hour")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    Spacer()
                    Text("\(comicVineQuota.callsInLastHour) / \(ComicVineQuota.hourlyLimit)")
                        .font(Typography.body)
                        .foregroundColor(AccentColors.primary)
                }

                ProgressView(
                    value: Double(min(comicVineQuota.callsInLastHour, ComicVineQuota.hourlyLimit)),
                    total: Double(ComicVineQuota.hourlyLimit)
                )
                .tint(comicVineQuota.callsInLastHour >= ComicVineQuota.hourlyLimit ? AccentColors.error : AccentColors.primary)

                if let reset = comicVineQuota.nextReset {
                    Text("Budget starts replenishing \(reset.formatted(date: .omitted, time: .shortened))")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                } else {
                    Text("Limited to ~1 request/second and 200 calls per hour per ComicVine's terms.")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }
            }

            Divider()
                .background(BorderColors.subtle)
                .padding(.vertical, Spacing.xs)

            // Batch match-review behavior
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Auto-Apply Confident Matches")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)

                    Text("When fetching metadata for several books at once, apply high-confidence matches automatically and only stop to review the uncertain ones. Turn off to review every book before anything is saved.")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $autoApplyConfidentMatches)
                    .labelsHidden()
            }

            Divider()
                .background(BorderColors.subtle)
                .padding(.vertical, Spacing.xs)

            // Match-picker tap behavior
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Single-Tap to Confirm Match")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)

                    Text("In the match picker, confirm a result with one tap. Off (default) is a two-step tap: the first tap highlights a result and a second tap confirms it, so you can see your choice before it’s applied.")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $singleTapConfirmMatch)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Typography Preview

    /// Sample paragraph rendered with the chosen eBook typography, in the
    /// default eBook theme's colors — a small stand-in for a real page.
    private var typographyPreview: some View {
        let colors = readerSettings.defaultEPUBTheme.cssColors
        let size: CGFloat = 16
        // CSS line-height is a multiplier of font size; SwiftUI lineSpacing
        // is EXTRA space between lines, so subtract an approximate natural
        // leading (~0.2 em) from the multiplier
        let extraLeading = max(0, size * (readerSettings.epubLineSpacing.value - 1.2))

        return Text("She opened the book to its first page, and the quiet room filled with somewhere else entirely — salt air, distant bells, a road she had never walked.")
            .font(previewFont(size: size))
            .lineSpacing(extraLeading)
            .foregroundColor(Color(hex: colors.text))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
            .padding(.horizontal, CGFloat(readerSettings.epubMargins.verticalPadding))
            .background(Color(hex: colors.background))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(BorderColors.subtle, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.2), value: readerSettings.epubFontFamily)
            .animation(.easeInOut(duration: 0.2), value: readerSettings.epubLineSpacing)
            .animation(.easeInOut(duration: 0.2), value: readerSettings.epubMargins)
            .animation(.easeInOut(duration: 0.2), value: readerSettings.defaultEPUBTheme)
    }

    /// SwiftUI stand-ins for the CSS font stacks used in the reader
    private func previewFont(size: CGFloat) -> Font {
        switch readerSettings.epubFontFamily {
        case .system: return .system(size: size)
        case .newYork: return .system(size: size, design: .serif)  // New York
        case .georgia: return .custom("Georgia", size: size)
        case .palatino: return .custom("Palatino", size: size)
        case .charter: return .custom("Charter", size: size)
        }
    }

    // MARK: - Organization Settings

    private var organizationSettings: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Folder Structure Picker
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Folder Structure")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Text("Choose how comics are organized into folders")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                Picker("", selection: viewModel.folderStructure) {
                    ForEach(AppSettings.FolderStructure.allCases, id: \.self) { structure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(structure.displayName)
                                .font(Typography.body)
                            Text(structure.description)
                                .font(Typography.caption)
                                .foregroundColor(TextColors.tertiary)
                        }
                        .tag(structure)
                    }
                }
                #if os(macOS)
                    .pickerStyle(.menu)
                #else
                    .pickerStyle(.menu)
                #endif

                // Example path
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundColor(TextColors.tertiary)
                    Text(
                        "Example: \(viewModel.examplePath(for: viewModel.settings.folderStructure))"
                    )
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
                }
                .padding(.top, Spacing.xs)
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Naming Pattern Editor
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Naming Pattern")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Text("Pattern used for naming comic files")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                TextField("Naming Pattern", text: viewModel.namingPattern)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                    .padding(Spacing.md)
                    .background(BackgroundColors.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                viewModel.validateNamingPattern(viewModel.settings.namingPattern)
                                    ? BorderColors.subtle : AccentColors.error, lineWidth: 1)
                    )

                // Available variables helper text
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Available variables:")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                    Text(
                        "{publisher}, {series}, {issue}, {year}, {title}, {volume}, {writer}, {artist}"
                    )
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
                }
                .padding(.horizontal, Spacing.sm)

                // Preview
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                        .foregroundColor(TextColors.tertiary)
                    Text("Preview: \(viewModel.previewNamingPattern())")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }
                .padding(.top, Spacing.xs)
                .padding(.horizontal, Spacing.sm)
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Root Library Path → expanded Home Library section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Home Library Folder")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Text("Comics confirmed in Organize are automatically moved into this folder, organized by publisher and series.")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                // Path display + chooser
                HStack(spacing: Spacing.md) {
                    Text(viewModel.settings.rootLibraryPath?.path ?? "Not set")
                        .font(Typography.body)
                        .foregroundColor(
                            viewModel.settings.rootLibraryPath != nil
                                ? TextColors.primary : TextColors.tertiary
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: { showingPathPicker = true }) {
                        Text(viewModel.settings.rootLibraryPath == nil ? "Choose Folder" : "Change")
                            .font(Typography.button)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    if viewModel.settings.rootLibraryPath != nil {
                        Button(action: {
                            viewModel.settings.rootLibraryPath = nil
                            viewModel.settings.homeLibraryBookmark = nil
                            homeLibraryStatus = .notSet
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(TextColors.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Validation badge
                if viewModel.settings.rootLibraryPath != nil {
                    homeLibraryStatusBadge
                        .padding(.top, 2)

                    // ── Relocate Library button ────────────────────────
                    // Shown only when the library folder can no longer be resolved
                    // (e.g. after a drive migration). Hidden when accessible.
                    if homeLibraryStatus == .notFound || homeLibraryStatus == .volumeNotMounted {
                        Button {
                            Task {
                                let comics = (try? await DatabaseManager.shared.fetchAllComics()) ?? []
                                allComicsForRelocate = comics
                                showingRelocateSheet = true
                            }
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder.badge.questionmark")
                                Text("Relocate Library…")
                                    .font(Typography.button)
                            }
                            .foregroundColor(AccentColors.warning)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.warning.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AccentColors.warning.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Spacing.xs)
                    }
                }

                // Cloud & Network Drive warning note
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AccentColors.warning)
                        .font(.system(size: 13, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avoid Cloud & Network Drives")
                            .font(Typography.bodySmall.weight(.semibold))
                            .foregroundColor(AccentColors.warning)
                        Text("Due to macOS sandbox restrictions, the app cannot create folders or move files inside iCloud Drive, Google Drive, Dropbox, OneDrive, or Network/NAS drives. Choose a purely local folder on your Mac's internal drive (like Downloads or Documents).")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Spacing.sm)
                .background(AccentColors.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AccentColors.warning.opacity(0.3), lineWidth: 1)
                )
                .padding(.top, Spacing.xs)
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Auto-sort toggle
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Auto-Sort into Library")
                            .font(Typography.h3)
                            .foregroundColor(TextColors.primary)

                        Text("Move files into the home library folder after each import is confirmed")
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: viewModel.autoSortIntoLibrary)
                        .labelsHidden()
                        .disabled(viewModel.settings.rootLibraryPath == nil)
                }
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(viewModel.settings.rootLibraryPath == nil ? 0.4 : 1)

            // Reorganize button
            if viewModel.settings.rootLibraryPath != nil && homeLibraryStatus == .accessible {
                Button {
                    Task {
                        let comics = (try? await DatabaseManager.shared.fetchAllComics()) ?? []
                        allComicsForReorganize = comics
                        showingReorganizeSheet = true
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Reorganize Existing Library…")
                            .font(Typography.button)
                    }
                    .foregroundColor(AccentColors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(AccentColors.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AccentColors.primary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            // Confidence Threshold
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Confidence Threshold")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)

                    Spacer()

                    Text("\(Int(viewModel.settings.confidenceThreshold * 100))%")
                        .font(Typography.body)
                        .foregroundColor(AccentColors.primary)
                }

                Text("Minimum confidence required for automatic organization decisions")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                Slider(value: viewModel.confidenceThreshold, in: 0.0...1.0, step: 0.1)
                    .tint(AccentColors.primary)
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Enable Learning Toggle
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Adaptive Learning")
                            .font(Typography.h3)
                            .foregroundColor(TextColors.primary)

                        Text("Learn naming patterns from imported books to improve organization")
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: viewModel.enableLearning)
                        .labelsHidden()
                }
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Learning Status
            if viewModel.enableLearning.wrappedValue {
                learningStatusView
            }

            // Reset to Defaults Button
            Button(action: { showingResetConfirmation = true }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Defaults")
                        .font(Typography.button)
                }
                .foregroundColor(AccentColors.error)
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
                .background(AccentColors.error.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AccentColors.error.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Feedback & Support

    private static let feedbackEmail = "info@rapturepress.com"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var systemInfo: String {
        #if os(iOS)
            let device = UIDevice.current
            return "\(device.systemName) \(device.systemVersion) (\(device.model))"
        #else
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    /// Pre-addressed mail to the beta feedback inbox, with diagnostics in the body.
    private func feedbackMailURL() -> URL? {
        let subject = "SCO Beta Feedback (v\(appVersion))"
        let body = """
            Tell us what's working well, what's broken, or any ideas you have:




            ——— Please keep the details below to help us debug ———
            App: Super Comic Organizer
            Version: \(appVersion) (build \(buildNumber))
            System: \(systemInfo)
            """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    /// Open the pre-addressed email. On macOS we go through NSWorkspace (the
    /// canonical mailto opener) rather than the SwiftUI openURL action, which
    /// could route the link to the wrong handler.
    private func openFeedbackMail() {
        guard let url = feedbackMailURL() else { return }
        #if os(macOS)
            NSWorkspace.shared.open(url)
        #else
            openURL(url)
        #endif
    }

    private func copyFeedbackEmail() {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.feedbackEmail, forType: .string)
        #else
            UIPasteboard.general.string = Self.feedbackEmail
        #endif
        didCopyEmail = true
    }

    private var feedbackSettings: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(
                "We're in beta and your feedback shapes the app. Tell us about bugs, confusing bits, or features you'd love — it all helps."
            )
            .font(Typography.bodySmall)
            .foregroundColor(TextColors.secondary)

            Button {
                openFeedbackMail()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "paperplane.fill")
                    Text("Send Feedback")
                        .font(Typography.button)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(AccentColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Fallback: if no mail client is set up, copy the address instead.
            HStack(spacing: Spacing.sm) {
                Text(Self.feedbackEmail)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(TextColors.secondary)
                    .textSelection(.enabled)
                Spacer()
                Button(action: copyFeedbackEmail) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: didCopyEmail ? "checkmark" : "doc.on.doc")
                        Text(didCopyEmail ? "Copied" : "Copy")
                            .font(Typography.bodySmall)
                    }
                    .foregroundColor(AccentColors.primary)
                }
                .buttonStyle(.plain)
            }

            Text(
                "Send Feedback opens your email app. Your app version and system details are added automatically so we can reproduce issues. No mail app set up? Copy the address and write us from anywhere."
            )
            .font(Typography.caption)
            .foregroundColor(TextColors.tertiary)

            Divider()
                .background(BorderColors.subtle)
                .padding(.vertical, Spacing.xs)

            HStack {
                Text("Version")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
                Spacer()
                Text("\(appVersion) (\(buildNumber))")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(TextColors.tertiary)
            }
        }
    }

    // MARK: - Helper Views

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(AccentColors.primary)

                Text(title)
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
            }

            content()
        }
        .padding(Spacing.lg)
        .background(BackgroundColors.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Learning Status View

    private var learningStatusView: some View {
        let patternCount = OrganizationLearner.shared.getPatternCount()

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Learning Status")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Spacer()

                Text("\(patternCount) pattern\(patternCount == 1 ? "" : "s") learned")
                    .font(Typography.bodySmall)
                    .foregroundColor(AccentColors.primary)
            }

            if patternCount > 0 {
                let publishers = OrganizationLearner.shared.getPublishersWithPatterns()
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Publishers with learned patterns:")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)

                    // Show first 5 publishers, or all if less than 5
                    let displayPublishers = publishers.prefix(5)
                    ForEach(Array(displayPublishers), id: \.self) { publisher in
                        HStack(spacing: Spacing.xs) {
                            Circle()
                                .fill(PublisherDetector.color(for: publisher))
                                .frame(width: 8, height: 8)
                            Text(publisher)
                                .font(Typography.caption)
                                .foregroundColor(TextColors.secondary)
                        }
                    }

                    if publishers.count > 5 {
                        Text("+ \(publishers.count - 5) more")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                    }
                }
                .padding(.top, Spacing.xs)
            } else {
                Text("No patterns learned yet. Import comics to start learning.")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.tertiary)
                    .padding(.top, Spacing.xs)
            }

            if patternCount > 0 {
                Text("You can clear learned patterns from the Maintenance tab.")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.md)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func handlePathSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.setHomeLibraryFolder(url)
                homeLibraryStatus = viewModel.homeLibraryStatus()
            }
        case .failure(let error):
            AppLog.app.error("Failed to select path: \(error.localizedDescription)")
        }
    }

    // MARK: - Home Library Status Badge

    @ViewBuilder
    private var homeLibraryStatusBadge: some View {
        let (icon, label, color): (String, String, Color) = {
            switch homeLibraryStatus {
            case .notSet:
                return ("questionmark.circle", "No library set", TextColors.tertiary)
            case .accessible:
                return ("checkmark.circle.fill", "Accessible and writable", AccentColors.success)
            case .notFound:
                return ("exclamationmark.triangle.fill", "Folder not found", AccentColors.error)
            case .volumeNotMounted:
                return ("externaldrive.badge.exclamationmark", "Volume not mounted", AccentColors.warning)
            case .notWritable:
                return ("lock.fill", "Folder is read-only", AccentColors.error)
            }
        }()

        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(label)
                .font(Typography.caption)
        }
        .foregroundColor(color)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
}
