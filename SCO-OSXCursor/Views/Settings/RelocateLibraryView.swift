//
//  RelocateLibraryView.swift
//  SCO-OSXCursor
//
//  Created for Milestone 0: Home Library & Automatic File Sorting
//

import SwiftUI

// MARK: - RelocateLibraryView

/// Sheet presented from Settings when the home library folder can no longer be
/// resolved (volume not mounted, folder migrated to a new drive, etc.).
///
/// This tool **only rewrites database path records** — it does not move any
/// files. The user must have already moved the library folder to its new
/// location before running this tool.
struct RelocateLibraryView: View {

    let oldRoot: URL
    let comics: [Comic]
    @StateObject var settingsViewModel: SettingsViewModel

    @StateObject private var viewModel = RelocateLibraryViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showingFolderPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            headerView

            Divider()
                .background(BorderColors.subtle)

            // ── Body ─────────────────────────────────────────────────────
            Group {
                switch viewModel.phase {
                case .idle:
                    idleView
                case .preview:
                    previewContent
                case .running:
                    progressView
                case .done:
                    doneView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
                .background(BorderColors.subtle)

            // ── Footer ───────────────────────────────────────────────────
            footerView
        }
        .background(BackgroundColors.primary)
        .frame(minWidth: 640, minHeight: 500)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.newRootURL = url
                viewModel.buildPreview(oldRoot: oldRoot, newRoot: url, comics: comics)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AccentColors.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Relocate Library")
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)

                Text("Remap database records after moving your library to a new location")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
            }

            Spacer()

            // Phase chip
            if viewModel.phase == .preview {
                if viewModel.totalToRemap > 0 {
                    statsChip(
                        label: "\(viewModel.totalToRemap) to remap",
                        color: AccentColors.primary
                    )
                }
                if !viewModel.missingPreviews.isEmpty {
                    statsChip(
                        label: "\(viewModel.missingPreviews.count) not found",
                        color: AccentColors.warning
                    )
                }
            }
        }
        .padding(Spacing.lg)
        .background(BackgroundColors.secondary)
    }

    // MARK: - Idle (pick new location)

    private var idleView: some View {
        VStack(spacing: Spacing.xl) {
            // How-it-works note
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(AccentColors.primary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("How this works")
                        .font(Typography.bodySmall.weight(.semibold))
                        .foregroundColor(TextColors.primary)
                    Text("This tool updates the file paths stored in the database. It does not move any files — your library must already be at its new location before you continue.")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            .padding(Spacing.md)
            .background(AccentColors.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AccentColors.primary.opacity(0.2), lineWidth: 1)
            )

            // Old root display
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Previous Library Location", systemImage: "folder.badge.minus")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
                Text(oldRoot.path)
                    .font(Typography.bodySmall)
                    .foregroundColor(AccentColors.error)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AccentColors.error.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AccentColors.error.opacity(0.2), lineWidth: 1)
            )

            // Choose new location
            Button {
                showingFolderPicker = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "folder.badge.plus")
                    Text("Choose New Library Location…")
                        .font(Typography.button)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(AccentColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 480)
    }

    // MARK: - Preview Table

    private var previewContent: some View {
        Group {
            if viewModel.previews.isEmpty {
                emptyState(
                    icon: "checkmark.circle.fill",
                    title: "No matching records",
                    subtitle: "None of the comics in your library have paths under the previous location."
                )
            } else {
                VStack(spacing: 0) {
                    // New root banner
                    if let newRoot = viewModel.newRootURL {
                        HStack(spacing: Spacing.sm) {
                            Label("New Location", systemImage: "folder.badge.checkmark")
                                .font(Typography.caption)
                                .foregroundColor(AccentColors.success)
                            Text(newRoot.path)
                                .font(Typography.caption)
                                .foregroundColor(TextColors.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AccentColors.success.opacity(0.06))

                        Divider().background(BorderColors.subtle)
                    }

                    // Missing-files warning
                    if !viewModel.missingPreviews.isEmpty {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AccentColors.warning)
                                .font(.system(size: 12))
                            Text("\(viewModel.missingPreviews.count) file\(viewModel.missingPreviews.count == 1 ? "" : "s") not found at the new location. These will be flagged as "Needs Attention" and left untouched.")
                                .font(Typography.caption)
                                .foregroundColor(TextColors.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AccentColors.warning.opacity(0.08))

                        Divider().background(BorderColors.subtle)
                    }

                    previewTable
                }
            }
        }
    }

    private var previewTable: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Column headers
                HStack {
                    Text("Comic")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                        .frame(width: 160, alignment: .leading)
                    Text("Previous Path")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundColor(TextColors.tertiary)
                        .frame(width: 24)
                    Text("New Path")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(BackgroundColors.elevated)

                Divider().background(BorderColors.subtle)

                ForEach(viewModel.previews) { preview in
                    previewRow(preview)
                    Divider()
                        .background(BorderColors.subtle)
                        .padding(.leading, Spacing.lg)
                }
            }
        }
    }

    @ViewBuilder
    private func previewRow(_ preview: RelocateLibraryViewModel.PathPreview) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            // Status icon + name
            HStack(spacing: Spacing.xs) {
                Image(systemName: preview.existsAtNewPath
                      ? "arrow.triangle.swap"
                      : "exclamationmark.triangle.fill")
                    .foregroundColor(preview.existsAtNewPath
                                     ? AccentColors.primary
                                     : AccentColors.warning)
                    .font(.system(size: 12))
                Text(preview.comic.displayName)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(2)
            }
            .frame(width: 160, alignment: .leading)

            // Old relative path
            Text(preview.oldRelativePath)
                .font(Typography.caption)
                .foregroundColor(preview.existsAtNewPath
                                 ? TextColors.secondary
                                 : AccentColors.warning.opacity(0.7))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: preview.existsAtNewPath ? "arrow.right" : "xmark")
                .font(.system(size: 11))
                .foregroundColor(preview.existsAtNewPath
                                 ? AccentColors.primary
                                 : AccentColors.warning)
                .frame(width: 24)

            // New absolute path (show just the relative portion for readability)
            Text(preview.existsAtNewPath
                 ? preview.oldRelativePath   // same relative path, new root
                 : "Not found at new location")
                .font(Typography.caption)
                .foregroundColor(preview.existsAtNewPath
                                 ? AccentColors.primary
                                 : AccentColors.warning)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(
            preview.existsAtNewPath
                ? AccentColors.primary.opacity(0.03)
                : AccentColors.warning.opacity(0.04)
        )
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("Remapping Records…")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                Text("\(viewModel.remappedCount) of \(viewModel.totalToRemap) updated")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
            }

            ProgressView(value: viewModel.progress)
                .tint(AccentColors.primary)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .frame(maxWidth: 400)
        }
        .padding(Spacing.xl)
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: Spacing.lg) {
            if viewModel.notFoundCount == 0 && viewModel.errors.isEmpty {
                emptyState(
                    icon: "checkmark.circle.fill",
                    title: "Library Relocated",
                    subtitle: "\(viewModel.remappedCount) record\(viewModel.remappedCount == 1 ? "" : "s") updated successfully."
                )
            } else {
                VStack(spacing: Spacing.lg) {
                    HStack(spacing: Spacing.lg) {
                        summaryChip(
                            icon: "checkmark.circle.fill",
                            label: "\(viewModel.remappedCount) remapped",
                            color: AccentColors.success
                        )
                        if viewModel.notFoundCount > 0 {
                            summaryChip(
                                icon: "exclamationmark.triangle.fill",
                                label: "\(viewModel.notFoundCount) not found",
                                color: AccentColors.warning
                            )
                        }
                        if !viewModel.errors.isEmpty {
                            summaryChip(
                                icon: "xmark.circle.fill",
                                label: "\(viewModel.errors.count) error\(viewModel.errors.count == 1 ? "" : "s")",
                                color: AccentColors.error
                            )
                        }
                    }

                    if viewModel.notFoundCount > 0 {
                        Text("Comics not found at the new location have been flagged as \"Needs Attention\". Their original paths remain unchanged in the database.")
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                    }

                    if !viewModel.errors.isEmpty {
                        errorList
                    }
                }
                .padding(Spacing.xl)
            }
        }
    }

    private var errorList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(viewModel.errors) { err in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AccentColors.error)
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(err.comicName)
                                .font(Typography.bodySmall)
                                .foregroundColor(TextColors.primary)
                            Text(err.reason)
                                .font(Typography.caption)
                                .foregroundColor(TextColors.secondary)
                        }
                    }
                    .padding(Spacing.sm)
                    .background(AccentColors.error.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            switch viewModel.phase {
            case .idle:
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(TextColors.secondary)
                Spacer()

            case .preview:
                Button("Back") { viewModel.reset() }
                    .buttonStyle(.plain)
                    .foregroundColor(TextColors.secondary)
                Spacer()
                if viewModel.totalToRemap == 0 {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(AccentColors.primary)
                } else {
                    Button {
                        guard let newRoot = viewModel.newRootURL else { return }
                        Task {
                            await viewModel.executeRemap(
                                oldRoot: oldRoot,
                                newRoot: newRoot,
                                settingsViewModel: settingsViewModel,
                                database: DatabaseManager.shared
                            )
                        }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "arrow.triangle.swap")
                            Text("Remap \(viewModel.totalToRemap) Record\(viewModel.totalToRemap == 1 ? "" : "s")")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AccentColors.primary)
                    .keyboardShortcut(.return)
                }

            case .running:
                Spacer() // no actions while running

            case .done:
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(AccentColors.primary)
                    .keyboardShortcut(.return)
            }
        }
        .padding(Spacing.lg)
        .background(BackgroundColors.secondary)
    }

    // MARK: - Subcomponents

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AccentColors.success)
            Text(title)
                .font(Typography.h2)
                .foregroundColor(TextColors.primary)
            Text(subtitle)
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }

    private func statsChip(label: String, color: Color) -> some View {
        Text(label)
            .font(Typography.caption)
            .foregroundColor(color)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func summaryChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
            Text(label)
        }
        .font(Typography.body)
        .foregroundColor(color)
        .padding(Spacing.md)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
