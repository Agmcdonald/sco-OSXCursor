//
//  PublisherBannerView.swift
//  SCO-OSXCursor
//

import SwiftUI
import UniformTypeIdentifiers
import os

#if os(macOS)
    import AppKit
#endif

/// A 230×100 landscape banner slot for a named publisher.
/// Tapping an unset banner opens a file picker; the chosen image is persisted
/// to `DatabaseManager` and displayed going forward.
@MainActor
struct PublisherBannerView: View {
    let publisherName: String
    /// If true the user can tap to change the image (Library view use-case).
    var allowEditing: Bool = true

    @State private var imageData: Data? = nil
    @State private var showingPicker = false
    @State private var isLoading = true
    @State private var isHovered = false

    // Fixed display size
    // Fixed display size
    private let bannerWidth: CGFloat = 230
    private let bannerHeight: CGFloat = 100

    var body: some View {
        Button {
            guard allowEditing else { return }
            #if os(macOS)
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        Task { @MainActor in
                            guard url.startAccessingSecurityScopedResource() else { return }
                            defer { url.stopAccessingSecurityScopedResource() }
                            if let data = try? Data(contentsOf: url) {
                                try? await DatabaseManager.shared.savePublisherBanner(
                                    name: publisherName, data: data)
                                self.imageData = data
                            }
                        }
                    }
                }
            #else
                showingPicker = true
            #endif
        } label: {
            ZStack {
                if let data = imageData {
                    // Loaded banner
                    #if os(macOS)
                        if let nsImg = NSImage(data: data) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: bannerWidth, height: bannerHeight)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .overlay(
                                    // Edit hint on hover
                                    Group {
                                        if isHovered && allowEditing {
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(Color.black.opacity(0.45))
                                            Image(systemName: "pencil")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                )
                        }
                    #else
                        if let uiImg = UIImage(data: data) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: bannerWidth, height: bannerHeight)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    #endif
                } else if !isLoading {
                    // Placeholder
                    placeholderView
                } else {
                    // Loading shimmer
                    RoundedRectangle(cornerRadius: 5)
                        .fill(BackgroundColors.elevated)
                        .frame(width: bannerWidth, height: bannerHeight)
                }
            }
            .frame(width: bannerWidth, height: bannerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .task {
            await loadBanner()
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handlePickerResult(result)
        }
        .onDrop(of: [.image], isTargeted: nil) { providers in
            guard allowEditing else { return false }
            guard let provider = providers.first else { return false }

            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
                data, error in
                if let data = data {
                    Task { @MainActor in
                        try? await DatabaseManager.shared.savePublisherBanner(
                            name: publisherName, data: data)
                        self.imageData = data
                    }
                } else if let error = error {
                    AppLog.library.error("[PublisherBannerView] Drop error: \(error)")
                }
            }
            return true
        }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
            .foregroundColor(BorderColors.subtle)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isHovered && allowEditing
                            ? AccentColors.primary.opacity(0.06)
                            : BackgroundColors.elevated)
            )
            .frame(width: bannerWidth, height: bannerHeight)
            .overlay(
                VStack(spacing: 3) {
                    Image(systemName: "photo")
                        .font(.system(size: 13))
                        .foregroundColor(
                            isHovered && allowEditing
                                ? AccentColors.primary
                                : TextColors.tertiary)
                    if allowEditing {
                        Text("230×100")
                            .font(.system(size: 11))
                            .foregroundColor(TextColors.tertiary)
                    }
                }
            )
            .help(
                allowEditing
                    ? "Click or Drag & Drop to set a 230×100 custom publisher banner image"
                    : "No custom banner set")
    }

    // MARK: - Helpers

    private func loadBanner() async {
        isLoading = true
        imageData = try? await DatabaseManager.shared.loadPublisherBanner(name: publisherName)
        isLoading = false
    }

    private func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    try? await DatabaseManager.shared.savePublisherBanner(
                        name: publisherName, data: data)
                    imageData = data
                }
            }
        case .failure(let error):
            AppLog.library.error("[PublisherBannerView] Picker error: \(error)")
        }
    }
}

// MARK: - Batch-settable variant (for the admin tool)

extension PublisherBannerView {
    /// Apply external image data directly (bypassing picker). Used by the batch import tool.
    func applyData(_ data: Data) {
        // Cannot modify @State from outside; the Batch tool handles saving itself.
        _ = data
    }
}

#if DEBUG
    #Preview("Set") {
        PublisherBannerView(publisherName: "DC Comics")
            .padding()
            .background(BackgroundColors.primary)
    }
#endif
