//
//  BatchPublisherBrandingView.swift
//  SCO-OSXCursor
//

import Combine
import SwiftUI
import UniformTypeIdentifiers
import os

// MARK: - ViewModel

@MainActor
final class BatchPublisherBrandingViewModel: ObservableObject {
    @Published var entries: [(name: String, imageData: Data?)] = []
    @Published var isLoading = false
    @Published var statusMessage: String? = nil
    @Published var showingFolderPicker = false
    @Published var showingResetConfirmation = false

    /// Publishers discovered from the comics library (deduped, sorted).
    var allLibraryPublishers: [String] = []

    func load(libraryPublishers: [String]) async {
        isLoading = true
        allLibraryPublishers = libraryPublishers

        do {
            // Merge DB entries with library publisher list so every known
            // publisher always appears (even those with no banner row yet).
            var dbEntries = try await DatabaseManager.shared.fetchAllPublisherBanners()
            let dbNames = Set(dbEntries.map { $0.name })
            for pub in libraryPublishers where !dbNames.contains(pub) {
                dbEntries.append((name: pub, imageData: nil))
            }
            entries = dbEntries.sorted { $0.name < $1.name }
        } catch {
            statusMessage = "Failed to load banners: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func clearBanner(for name: String) async {
        do {
            try await DatabaseManager.shared.clearPublisherBanner(name: name)
            if let idx = entries.firstIndex(where: { $0.name == name }) {
                entries[idx] = (name: name, imageData: nil)
            }
        } catch {
            statusMessage = "Failed to clear banner: \(error.localizedDescription)"
        }
    }

    func clearAllBanners() async {
        do {
            try await DatabaseManager.shared.clearAllPublisherBanners()
            entries = entries.map { (name: $0.name, imageData: nil) }
            statusMessage = "All banners reset."
        } catch {
            statusMessage = "Failed to reset banners: \(error.localizedDescription)"
        }
    }

    /// Bulk-import images from a folder. Matches filenames (case-insensitive,
    /// without extension) to publisher names.
    func bulkImport(from folderURL: URL) async {
        guard folderURL.startAccessingSecurityScopedResource() else {
            statusMessage = "Permission denied for selected folder."
            return
        }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        isLoading = true
        statusMessage = nil

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "tiff", "heic"]
        let fm = FileManager.default

        guard
            let contents = try? fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            statusMessage = "Could not read folder contents."
            isLoading = false
            return
        }

        let imageFiles = contents.filter {
            imageExtensions.contains($0.pathExtension.lowercased())
        }

        // Ensure we explicitly have all publishers loaded from the database
        // before we attempt to match against them
        let comics = (try? await DatabaseManager.shared.fetchAllComics()) ?? []
        let dbPublishers = Set(comics.compactMap { $0.publisher })
        let dbBanners = (try? await DatabaseManager.shared.fetchAllPublisherBanners()) ?? []
        let allKnownPublishers = Array(dbPublishers.union(dbBanners.map { $0.name })).sorted()

        let candidates = allKnownPublishers.isEmpty ? entries.map { $0.name } : allKnownPublishers

        var matched = 0
        for fileURL in imageFiles {
            let stem = fileURL.deletingPathExtension().lastPathComponent
            AppLog.app.debug("[BatchPublisherBranding] Checking file: \(fileURL.lastPathComponent)")

            // Find the best-matching publisher (exact first, then prefix)
            guard let publisher = bestMatch(stem: stem, candidates: candidates) else {
                AppLog.app.debug("[BatchPublisherBranding] No matching publisher for stem: '\(stem)'")
                continue
            }
            AppLog.app.debug("[BatchPublisherBranding] Matched file \(fileURL.lastPathComponent) to publisher: \(publisher)")

            guard let data = try? Data(contentsOf: fileURL) else {
                AppLog.app.error("[BatchPublisherBranding] Failed to read data from \(fileURL.lastPathComponent)")
                continue
            }

            do {
                try await DatabaseManager.shared.savePublisherBanner(name: publisher, data: data)
                if let idx = entries.firstIndex(where: { $0.name == publisher }) {
                    entries[idx] = (name: publisher, imageData: data)
                }
                matched += 1
                AppLog.app.info("[BatchPublisherBranding] Successfully saved banner for \(publisher)")
            } catch {
                AppLog.app.error("[BatchPublisherBranding] Failed to save banner for \(publisher): \(error)")
            }
        }

        statusMessage =
            matched == 0
            ? "No matching publishers found in that folder."
            : "Imported \(matched) banner\(matched == 1 ? "" : "s") successfully."
        isLoading = false
    }

    /// Returns the best matching publisher name for a filename stem against a list of candidates.
    private func bestMatch(stem: String, candidates: [String]) -> String? {
        let normalised = stem.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. Exact match
        if let exact = candidates.first(where: { $0.lowercased() == normalised }) {
            return exact
        }
        // 2. Publisher name contained in stem
        if let contained = candidates.first(where: { normalised.contains($0.lowercased()) }) {
            return contained
        }
        // 3. Stem contained in publisher name
        if let reverse = candidates.first(where: { $0.lowercased().contains(normalised) }) {
            return reverse
        }
        return nil
    }
}

// MARK: - View

@MainActor
struct BatchPublisherBrandingView: View {
    /// Comics library publishers (deduped) passed in from LibraryViewModel.
    let libraryPublishers: [String]

    @StateObject private var viewModel = BatchPublisherBrandingViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publisher Branding")
                        .font(Typography.h2)
                        .foregroundColor(TextColors.primary)
                    Text("Assign 230×100 banner images to your publishers")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(TextColors.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.xl)

            Divider().background(BorderColors.subtle)

            // Toolbar
            HStack(spacing: Spacing.md) {
                // Bulk Import
                Button {
                    viewModel.showingFolderPicker = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "folder.badge.plus")
                        Text("Bulk Import")
                            .font(Typography.button)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(AccentColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(
                    "Select a folder. Images whose filenames match publisher names are auto-assigned."
                )

                // Reset All
                Button {
                    viewModel.showingResetConfirmation = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset All Banners")
                            .font(Typography.button)
                    }
                    .foregroundColor(AccentColors.error)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(AccentColors.error.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AccentColors.error.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Download Template
                #if os(macOS)
                    Button {
                        PremadePublisherLogoLibrary.exportTemplate()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Download Template")
                                .font(Typography.button)
                        }
                        .foregroundColor(TextColors.primary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(BackgroundColors.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(BorderColors.subtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(
                        "Save a blank 230×100 banner template to edit in your own image software."
                    )
                #endif

                Spacer()

                // Status message
                if let msg = viewModel.statusMessage {
                    Text(msg)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .background(BackgroundColors.secondary)

            Divider().background(BorderColors.subtle)

            // Publisher list
            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading publishers…")
                    .foregroundColor(TextColors.secondary)
                Spacer()
            } else if viewModel.entries.isEmpty {
                Spacer()
                VStack(spacing: Spacing.md) {
                    Image(systemName: "building.2")
                        .font(.system(size: 48))
                        .foregroundColor(TextColors.tertiary)
                    Text("No publishers found in your library.")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.entries, id: \.name) { entry in
                            publisherRow(entry)
                            Divider().background(BorderColors.subtle)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .background(BackgroundColors.primary)
        .frame(minWidth: 600, minHeight: 480)
        .task {
            await viewModel.load(libraryPublishers: libraryPublishers)
        }
        .fileImporter(
            isPresented: $viewModel.showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await viewModel.bulkImport(from: url) }
            }
        }
        .confirmationDialog(
            "Reset All Banners",
            isPresented: $viewModel.showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                Task { await viewModel.clearAllBanners() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all publisher banner images. This action cannot be undone.")
        }
    }

    // MARK: - Publisher Row

    @ViewBuilder
    private func publisherRow(_ entry: (name: String, imageData: Data?)) -> some View {
        HStack(spacing: Spacing.lg) {
            // Banner slot (reuse PublisherBannerView for consistent UX)
            PublisherBannerView(publisherName: entry.name, allowEditing: true)

            // Publisher name
            Text(entry.name)
                .font(Typography.body)
                .foregroundColor(TextColors.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Status indicator
            if entry.imageData != nil {
                Label("Custom", systemImage: "checkmark.circle.fill")
                    .font(Typography.caption)
                    .foregroundColor(AccentColors.success)
            } else {
                Label("Default", systemImage: "circle")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
            }

            // Clear button (only if has data)
            Button {
                Task { await viewModel.clearBanner(for: entry.name) }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundColor(
                        entry.imageData != nil
                            ? AccentColors.error : TextColors.tertiary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(entry.imageData == nil)
            .help("Clear this publisher's banner")
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }
}

#Preview {
    BatchPublisherBrandingView(libraryPublishers: ["DC Comics", "Marvel Comics", "Image"])
}
