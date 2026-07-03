//
//  TransferExportSheet.swift
//  SCO-OSXCursor
//
//  "Send to Device…" — packages the chosen book(s) into `.scobook` transfer
//  files with a determinate progress bar (zipping a large CBZ takes a
//  moment), then hands them to the system share sheet. AirDrop shows its
//  own transfer progress on both devices, so the in-app bar only covers the
//  packaging stage.
//
//  Cross-platform on purpose: exposing this on iPad later (iPad→Mac) is
//  just a menu item — the sheet already works there.
//

import SwiftUI

// MARK: - Request Wrapper

/// Wraps a send request so it can drive `.sheet(item:)`.
struct TransferExportRequest: Identifiable {
    let id = UUID()
    let comics: [Comic]
}

// MARK: - Export Sheet

struct TransferExportSheet: View {
    let comics: [Comic]
    let onDone: () -> Void

    private enum Phase {
        case building
        case ready([URL])
        case failed(String)
    }

    @State private var phase: Phase = .building
    @State private var progress: Double = 0
    @State private var currentName: String = ""
    @State private var buildTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().background(BorderColors.subtle)

            Group {
                switch phase {
                case .building:
                    buildingView
                case .ready(let urls):
                    readyView(urls)
                case .failed(let message):
                    failedView(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.xl)
        }
        #if os(macOS)
            .frame(width: 420, height: 300)
        #endif
        .background(BackgroundColors.primary)
        .onAppear { startBuilding() }
        .onDisappear { buildTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Send to Device")
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
                Text(subtitle)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
            }
            Spacer()
            Button {
                buildTask?.cancel()
                onDone()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(TextColors.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(Spacing.lg)
    }

    private var subtitle: String {
        if comics.count == 1, let comic = comics.first {
            return
                "“\(comic.displayTitle)” travels with its metadata, reading progress, and settings."
        }
        return
            "\(comics.count) books travel with their metadata, reading progress, and settings."
    }

    // MARK: - Phases

    private var buildingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView(value: progress) {
                Text("Packaging\(currentName.isEmpty ? "…" : " “\(currentName)”…")")
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(1)
            }
            .progressViewStyle(.linear)
            .tint(AccentColors.primary)

            Text("\(Int(progress * 100))%")
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
        }
    }

    private func readyView(_ urls: [URL]) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(AccentColors.success)

            Text(
                urls.count == 1
                    ? "Package ready to send."
                    : "\(urls.count) packages ready to send."
            )
            .font(Typography.body)
            .foregroundColor(TextColors.primary)

            ShareLink(items: urls) {
                Label("Send…", systemImage: "square.and.arrow.up")
                    .font(Typography.button)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(AccentColors.primary)

            Text("Choose AirDrop in the share menu to send straight to your iPad.")
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(AccentColors.warning)

            Text(message)
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
                .multilineTextAlignment(.center)

            Button("Close") { onDone() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Packaging

    private func startBuilding() {
        guard buildTask == nil else { return }
        let toExport = comics
        buildTask = Task {
            // Fresh per-export folder inside tmp; stale ones from earlier
            // sessions are swept first so pending AirDrops never break.
            let exportDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SCOTransfer", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            Self.sweepStaleExports()

            do {
                try FileManager.default.createDirectory(
                    at: exportDir, withIntermediateDirectories: true)

                var urls: [URL] = []
                let count = Double(toExport.count)

                for (index, comic) in toExport.enumerated() {
                    if Task.isCancelled { return }
                    await MainActor.run { currentName = comic.displayTitle }
                    let done = Double(index)

                    let url = try await Task.detached(priority: .userInitiated) {
                        try BookPackageExporter.export(comic, to: exportDir) { fraction in
                            Task { @MainActor in
                                progress = (done + fraction) / count
                            }
                        }
                    }.value
                    urls.append(url)
                }

                if Task.isCancelled { return }
                await MainActor.run {
                    progress = 1.0
                    phase = .ready(urls)
                }
            } catch {
                await MainActor.run { phase = .failed(error.localizedDescription) }
            }
        }
    }

    /// Removes export folders older than a day (left over from sessions
    /// where the share sheet needed the file after this sheet closed).
    private static func sweepStaleExports() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "SCOTransfer", isDirectory: true)
        guard
            let children = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for child in children {
            let modified =
                (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? fm.removeItem(at: child)
            }
        }
    }
}
