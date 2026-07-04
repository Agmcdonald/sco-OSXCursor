//
//  PremadePublisherLogoLibrary.swift
//  SCO-OSXCursor
//
//  Bundled 230×100 publisher banner artwork (Resources/PublisherLogos).
//  Logos are never auto-assigned — they are only shown when the user
//  explicitly opens the premade library from the banner tile menu.
//

import SwiftUI
import UniformTypeIdentifiers
import os

#if os(macOS)
    import AppKit
#endif

// MARK: - Model

struct PremadePublisherLogo: Identifiable {
    let id: String  // file name without extension, e.g. "Publisher_DCComics"
    let url: URL
    let displayName: String  // e.g. "DC Comics"
}

// MARK: - Library

enum PremadePublisherLogoLibrary {
    private static let filePrefix = "Publisher_"
    private static let templateBaseName = "Publisher_Template"

    /// All bundled premade logos, excluding the blank template, sorted by name.
    static func allLogos() -> [PremadePublisherLogo] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: nil) ?? []
        return
            urls
            .filter { $0.lastPathComponent.hasPrefix(filePrefix) }
            .filter { $0.deletingPathExtension().lastPathComponent != templateBaseName }
            .map { url in
                let base = url.deletingPathExtension().lastPathComponent
                let raw = String(base.dropFirst(filePrefix.count))
                return PremadePublisherLogo(id: base, url: url, displayName: humanize(raw))
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// The bundled blank 230×100 template users can edit in their own software.
    static var templateURL: URL? {
        Bundle.main.url(forResource: templateBaseName, withExtension: "jpg")
    }

    /// "DCComics" -> "DC Comics", "OniPress" -> "Oni Press", "IDWPublishing" -> "IDW Publishing"
    static func humanize(_ name: String) -> String {
        var result = ""
        let chars = Array(name)
        for (i, c) in chars.enumerated() {
            if i > 0, c.isUppercase {
                let prev = chars[i - 1]
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                // Break before an uppercase that follows lowercase, or ends an acronym run.
                if prev.isLowercase || prev.isNumber || (prev.isUppercase && (next?.isLowercase ?? false)) {
                    result.append(" ")
                }
            }
            result.append(c)
        }
        return result
    }

    #if os(macOS)
        /// Prompt the user to save a copy of the blank banner template.
        @MainActor
        static func exportTemplate() {
            guard let source = templateURL else {
                AppLog.library.error("[PremadePublisherLogoLibrary] Template missing from bundle")
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.jpeg]
            panel.nameFieldStringValue = "Publisher_Template.jpg"
            panel.title = "Save Banner Template"
            panel.message = "Save the blank 230×100 banner template to edit in your own image software."
            panel.begin { response in
                guard response == .OK, let destination = panel.url else { return }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: source, to: destination)
                } catch {
                    AppLog.library.error(
                        "[PremadePublisherLogoLibrary] Template export failed: \(error)")
                }
            }
        }
    #endif
}

// MARK: - Picker Sheet

/// A grid of the bundled premade logos. Only presented when the user explicitly
/// asks to browse the library — nothing is ever assigned automatically.
@MainActor
struct PremadeLogoPickerSheet: View {
    let publisherName: String
    /// Called with the selected logo's image data. Caller persists it.
    let onSelect: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var logos: [PremadePublisherLogo] = []

    private let tileWidth: CGFloat = 230
    private let tileHeight: CGFloat = 100

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Premade Publisher Logos")
                        .font(.headline)
                        .foregroundColor(TextColors.primary)
                    Text("Choose a banner for “\(publisherName)”")
                        .font(.subheadline)
                        .foregroundColor(TextColors.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            if logos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28))
                        .foregroundColor(TextColors.tertiary)
                    Text("No premade logos found in this build.")
                        .font(.subheadline)
                        .foregroundColor(TextColors.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(logos) { logo in
                            logoTile(logo)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 540, height: 480)
        .background(BackgroundColors.primary)
        .task { logos = PremadePublisherLogoLibrary.allLogos() }
    }

    @ViewBuilder
    private func logoTile(_ logo: PremadePublisherLogo) -> some View {
        Button {
            if let data = try? Data(contentsOf: logo.url) {
                onSelect(data)
                dismiss()
            } else {
                AppLog.library.error(
                    "[PremadeLogoPickerSheet] Failed to read logo data: \(logo.id)")
            }
        } label: {
            VStack(spacing: 6) {
                Group {
                    #if os(macOS)
                        if let image = NSImage(contentsOf: logo.url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(BackgroundColors.elevated)
                        }
                    #else
                        if let data = try? Data(contentsOf: logo.url),
                            let image = UIImage(data: data)
                        {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(BackgroundColors.elevated)
                        }
                    #endif
                }
                .frame(width: tileWidth, height: tileHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(BorderColors.subtle, lineWidth: 1)
                )

                Text(logo.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(TextColors.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Use this banner for \(publisherName)")
    }
}

#if DEBUG
    #Preview("Premade Logo Picker") {
        PremadeLogoPickerSheet(publisherName: "DC Comics") { _ in }
    }
#endif
