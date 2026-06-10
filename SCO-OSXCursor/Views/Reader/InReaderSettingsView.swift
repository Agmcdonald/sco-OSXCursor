//
//  InReaderSettingsView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//

import SwiftUI

@MainActor
struct InReaderSettingsView: View {
    @Binding var comic: Comic
    @Binding var isPresented: Bool
    @ObservedObject private var settings = ReaderSettings.shared
    let onComicUpdated: (Comic) -> Void  // Callback to save changes

    // Reading Style state
    @State private var selectedStyle: ReadingStyle?
    @State private var useDefaultStyle: Bool = true

    // Transition state (existing)
    @State private var selectedTransition: PageTransition?
    @State private var useDefault: Bool = true

    // EPUB Theme state
    @State private var selectedTheme: EPUBTheme?
    @State private var useDefaultTheme: Bool = true

    var body: some View {
        #if os(macOS)
            // NavigationView inside a macOS sheet collapses to a toolbar-only
            // pill (the "empty white sheet" bug) — use an explicit layout.
            VStack(spacing: 0) {
                HStack {
                    Text("Reader Settings")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    Spacer()
                    Button("Cancel") {
                        isPresented = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        saveChanges()
                        isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding(Spacing.lg)

                Divider()

                settingsForm
                    .formStyle(.grouped)
            }
            .frame(minWidth: 540, idealWidth: 580, minHeight: 540, idealHeight: 660)
            .onAppear { loadState() }
        #else
            NavigationView {
                settingsForm
                    .navigationTitle("Reader Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isPresented = false
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                saveChanges()
                                isPresented = false
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
            .onAppear { loadState() }
        #endif
    }

    private var settingsForm: some View {
            Form {
                // MARK: - Reading Style Section
                Section {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // "Use app default" toggle
                        Toggle("Use App Default", isOn: $useDefaultStyle)
                            .tint(AccentColors.primary)
                            .onChange(of: useDefaultStyle) { _, newValue in
                                if newValue {
                                    selectedStyle = nil
                                } else {
                                    selectedStyle = settings.effectiveReadingStyle(for: comic)
                                }
                            }

                        if !useDefaultStyle {
                            // Style picker cards
                            HStack(spacing: Spacing.md) {
                                ForEach(ReadingStyle.allCases, id: \.self) { style in
                                    ReadingStyleCard(
                                        style: style,
                                        isSelected: (selectedStyle ?? settings.defaultReadingStyle) == style
                                    ) {
                                        selectedStyle = style
                                    }
                                }
                            }
                            .padding(.top, Spacing.xs)
                        }

                        // Description of the effective style
                        let effective = useDefaultStyle
                            ? settings.defaultReadingStyle
                            : (selectedStyle ?? settings.defaultReadingStyle)
                        Text(effective.description)
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                            .padding(.top, Spacing.xs)
                    }
                    .padding(.vertical, Spacing.sm)
                } header: {
                    Text("Reading Style")
                } footer: {
                    Text("Custom reading styles only apply to this book. Other books use the app default.")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }

                // MARK: - EPUB Theme Section
                if comic.fileType == .epub {
                    Section {
                        Toggle("Use App Default", isOn: $useDefaultTheme)
                            .tint(AccentColors.primary)
                            .onChange(of: useDefaultTheme) { _, newValue in
                                if newValue {
                                    selectedTheme = nil
                                } else {
                                    selectedTheme = settings.effectiveEPUBTheme(for: comic)
                                }
                            }

                        if !useDefaultTheme {
                            HStack(spacing: Spacing.md) {
                                ForEach(EPUBTheme.allCases, id: \.self) { theme in
                                    EPUBThemeCard(
                                        theme: theme,
                                        isSelected: (selectedTheme ?? settings.defaultEPUBTheme) == theme
                                    ) {
                                        selectedTheme = theme
                                    }
                                }
                            }
                            .padding(.top, Spacing.xs)
                        }
                    } header: {
                        Text("Theme")
                    } footer: {
                        Text("Overrides book background and font colors. Custom themes only apply to this book.")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                    }
                }

                // MARK: - Page Transition Section
                Section {
                    // Current setting info
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Current Transition")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)

                        HStack(spacing: Spacing.md) {
                            Image(systemName: effectiveTransition.icon)
                                .font(.system(size: 24))
                                .foregroundColor(AccentColors.primary)
                                .frame(width: 40, height: 40)
                                .background(AccentColors.primary.opacity(0.15))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(effectiveTransition.rawValue)
                                    .font(Typography.body)
                                    .foregroundColor(TextColors.primary)

                                Text(useDefault ? "Using app default" : "Custom for this book")
                                    .font(Typography.caption)
                                    .foregroundColor(TextColors.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                } header: {
                    Text("Active Transition")
                }

                Section {
                    // Use default toggle
                    Toggle("Use App Default", isOn: $useDefault)
                        .tint(AccentColors.primary)
                        .onChange(of: useDefault) { _, newValue in
                            if newValue {
                                selectedTransition = nil
                            } else {
                                selectedTransition = settings.effectiveTransition(for: comic)
                            }
                        }

                    if !useDefault {
                        // Transition picker
                        Picker("Page Transition", selection: Binding(
                            get: { selectedTransition ?? settings.pageTransition },
                            set: { selectedTransition = $0 }
                        )) {
                            ForEach(
                                PageTransition.allCases.filter { $0.isAvailableOnCurrentPlatform },
                                id: \.self
                            ) { transition in
                                Label(transition.rawValue, systemImage: transition.icon)
                                    .tag(transition)
                            }
                        }
                        #if os(macOS)
                        .pickerStyle(.menu)
                        #endif
                    }
                } header: {
                    Text("Transition Settings")
                } footer: {
                    Text("Custom transitions only apply to this book. Other books will use the app default.")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }

                Section {
                    HStack(spacing: Spacing.lg) {
                        ForEach(
                            PageTransition.allCases.filter { $0.isAvailableOnCurrentPlatform }.prefix(5),
                            id: \.self
                        ) { transition in
                            TransitionPreviewCard(transition: transition)
                        }
                    }
                } header: {
                    Text("Transition Preview")
                }
            }
    }

    private func loadState() {
        // Load reading style setting
        if let styleString = comic.readingStyle,
            let style = ReadingStyle(rawValue: styleString)
        {
            useDefaultStyle = false
            selectedStyle = style
        } else {
            useDefaultStyle = true
            selectedStyle = nil
        }

        // Load transition setting
        if let preferredString = comic.preferredTransition,
            let preferred = PageTransition(rawValue: preferredString)
        {
            useDefault = false
            selectedTransition = preferred
        } else {
            useDefault = true
            selectedTransition = nil
        }

        // Load EPUB theme setting
        if comic.fileType == .epub {
            if let themeString = comic.epubTheme,
                let theme = EPUBTheme(rawValue: themeString)
            {
                useDefaultTheme = false
                selectedTheme = theme
            } else {
                useDefaultTheme = true
                selectedTheme = nil
            }
        }
    }

    private var effectiveTransition: PageTransition {
        if useDefault {
            return settings.pageTransition
        } else {
            return selectedTransition ?? settings.pageTransition
        }
    }

    private func saveChanges() {
        var updatedComic = comic

        // Save reading style
        updatedComic.readingStyle = useDefaultStyle ? nil : selectedStyle?.rawValue

        // Save transition
        updatedComic.preferredTransition = useDefault ? nil : selectedTransition?.rawValue

        // Save theme
        if comic.fileType == .epub {
            updatedComic.epubTheme = useDefaultTheme ? nil : selectedTheme?.rawValue
        }

        updatedComic.dateModified = Date()
        comic = updatedComic
        onComicUpdated(updatedComic)
    }
}

// MARK: - Reading Style Card

struct ReadingStyleCard: View {
    let style: ReadingStyle
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AccentColors.primary.opacity(0.15) : BackgroundColors.elevated)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isSelected ? AccentColors.primary : BorderColors.subtle,
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )

                    Image(systemName: style.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(isSelected ? AccentColors.primary : TextColors.secondary)
                }
                .animation(.easeInOut(duration: 0.15), value: isSelected)

                Text(style.displayName)
                    .font(Typography.caption)
                    .foregroundColor(isSelected ? AccentColors.primary : TextColors.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transition Preview Card
struct TransitionPreviewCard: View {
    let transition: PageTransition

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: transition.icon)
                .font(.system(size: 20))
                .foregroundColor(AccentColors.primary)
                .frame(width: 60, height: 60)
                .background(BackgroundColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(BorderColors.subtle, lineWidth: 1)
                )

            Text(transition.rawValue)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - EPUB Theme Card
struct EPUBThemeCard: View {
    let theme: EPUBTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color(hex: theme.cssColors.background))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    isSelected ? AccentColors.primary : BorderColors.subtle,
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )

                    Image(systemName: theme.icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Color(hex: theme.cssColors.text))
                }
                .animation(.easeInOut(duration: 0.15), value: isSelected)

                Text(theme.displayName)
                    .font(Typography.caption)
                    .foregroundColor(isSelected ? AccentColors.primary : TextColors.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(.plain)
    }
}
