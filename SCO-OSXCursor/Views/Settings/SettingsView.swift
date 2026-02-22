//
//  SettingsView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @ObservedObject private var readerSettings = ReaderSettings.shared
    @StateObject private var viewModel = SettingsViewModel()

    @State private var showingPathPicker = false
    @State private var showingResetConfirmation = false
    @State private var showingBrandingSheet = false

    // Publishers from the library (deduped) for the branding tool
    @State private var libraryPublishers: [String] = []

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
                    }
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

                // Reader Settings Section

                // Organization Settings Section
                settingsSection(title: "Organization", icon: "folder.badge.gearshape") {
                    organizationSettings
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
            }
        } message: {
            Text(
                "This will reset all organization settings to their default values. This action cannot be undone."
            )
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

            // Root Library Path
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Root Library Path")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Text("Base folder where comics will be organized")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                HStack(spacing: Spacing.md) {
                    Text(viewModel.settings.rootLibraryPath?.path ?? "Not set")
                        .font(Typography.body)
                        .foregroundColor(
                            viewModel.settings.rootLibraryPath != nil
                                ? TextColors.primary : TextColors.tertiary
                        )
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: { showingPathPicker = true }) {
                        Text("Choose Folder")
                            .font(Typography.button)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    if viewModel.settings.rootLibraryPath != nil {
                        Button(action: { viewModel.settings.rootLibraryPath = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(TextColors.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Auto-Organize Toggle
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Auto-Organize")
                            .font(Typography.h3)
                            .foregroundColor(TextColors.primary)

                        Text("Automatically organize comics into folders when imported")
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: viewModel.autoOrganize)
                        .labelsHidden()
                }
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
                Button(action: {
                    Task {
                        await OrganizationLearner.shared.clearAllPatterns()
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Learned Patterns")
                            .font(Typography.button)
                    }
                    .foregroundColor(AccentColors.error)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.sm)
                    .background(AccentColors.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AccentColors.error.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.sm)
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
                viewModel.settings.rootLibraryPath = url
            }
        case .failure(let error):
            print("Failed to select path: \(error.localizedDescription)")
        }
    }
}

#Preview {
    SettingsView()
}
