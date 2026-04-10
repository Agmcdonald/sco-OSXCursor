//
//  ReorganizeLibraryView.swift
//  SCO-OSXCursor
//
//  Created for Milestone 0: Home Library & Automatic File Sorting
//

import SwiftUI

// MARK: - ReorganizeLibraryView

/// Two-phase sheet: preview table → progress bar.
/// Presented from Settings when the user taps "Reorganize Library".
struct ReorganizeLibraryView: View {

    let libraryRoot: URL
    let comics: [Comic]

    @StateObject private var viewModel = ReorganizeViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            headerView

            Divider()
                .background(BorderColors.subtle)

            // ── Body ─────────────────────────────────────────────────────
            Group {
                switch viewModel.phase {
                case .preview:
                    loadingView
                case .ready:
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
        .frame(minWidth: 620, minHeight: 480)
        .task {
            await viewModel.buildPreview(comics: comics, libraryRoot: libraryRoot)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AccentColors.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Reorganize Library")
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)

                Text(libraryRoot.path)
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if viewModel.phase == .ready {
                statsChip(
                    label: "\(viewModel.movesNeeded.count) to move",
                    color: viewModel.movesNeeded.isEmpty ? AccentColors.success : AccentColors.primary
                )
                statsChip(
                    label: "\(viewModel.alreadyInPlace.count) in place",
                    color: AccentColors.success
                )
            }
        }
        .padding(Spacing.lg)
        .background(BackgroundColors.secondary)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(AccentColors.primary)
            Text("Calculating moves…")
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
        }
    }

    // MARK: - Preview Table

    private var previewContent: some View {
        Group {
            if viewModel.moves.isEmpty {
                emptyState(
                    icon: "checkmark.circle.fill",
                    title: "Nothing to reorganize",
                    subtitle: "All comics are already in the correct locations."
                )
            } else {
                previewTable
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Current Location")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundColor(TextColors.tertiary)
                        .frame(width: 24)
                    Text("New Location")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(BackgroundColors.elevated)

                Divider().background(BorderColors.subtle)

                ForEach(viewModel.moves) { preview in
                    moveRow(preview)
                    Divider()
                        .background(BorderColors.subtle)
                        .padding(.leading, Spacing.lg)
                }
            }
        }
    }

    @ViewBuilder
    private func moveRow(_ preview: ReorganizeViewModel.MovePreview) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            // Comic name
            HStack(spacing: Spacing.sm) {
                if preview.alreadyInPlace {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AccentColors.success)
                        .font(.system(size: 13))
                } else {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundColor(AccentColors.primary)
                        .font(.system(size: 13))
                }
                Text(preview.comic.displayName)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Current path
            Text(preview.currentPath.isEmpty ? preview.comic.filePath.path : preview.currentPath)
                .font(Typography.caption)
                .foregroundColor(preview.alreadyInPlace ? TextColors.tertiary : TextColors.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if preview.alreadyInPlace {
                Image(systemName: "equal")
                    .font(.system(size: 11))
                    .foregroundColor(AccentColors.success)
                    .frame(width: 24)
            } else {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundColor(AccentColors.primary)
                    .frame(width: 24)
            }

            // Destination path
            Text(preview.alreadyInPlace ? "Already organized ✓" : preview.destinationPath)
                .font(Typography.caption)
                .foregroundColor(preview.alreadyInPlace ? AccentColors.success : AccentColors.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(
            preview.alreadyInPlace
                ? Color.clear
                : AccentColors.primary.opacity(0.03)
        )
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.sm) {
                Text("Reorganizing…")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                Text("\(viewModel.completedCount) of \(viewModel.movesNeeded.count) moved")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
            }

            ProgressView(value: viewModel.progress)
                .tint(AccentColors.primary)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .frame(maxWidth: 400)

            if !viewModel.errors.isEmpty {
                failureList
            }
        }
        .padding(Spacing.xl)
    }

    // MARK: - Done View

    private var doneView: some View {
        VStack(spacing: Spacing.lg) {
            if viewModel.failedCount == 0 {
                emptyState(
                    icon: "checkmark.circle.fill",
                    title: "Reorganization Complete",
                    subtitle: "\(viewModel.completedCount) file\(viewModel.completedCount == 1 ? "" : "s") moved successfully."
                )
            } else {
                VStack(spacing: Spacing.lg) {
                    HStack(spacing: Spacing.lg) {
                        summaryChip(
                            icon: "checkmark.circle.fill",
                            label: "\(viewModel.completedCount) moved",
                            color: AccentColors.success
                        )
                        summaryChip(
                            icon: "exclamationmark.triangle.fill",
                            label: "\(viewModel.failedCount) failed",
                            color: AccentColors.error
                        )
                    }

                    Text("The following files could not be moved. Their original locations are unchanged.")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)

                    failureList
                }
                .padding(Spacing.xl)
            }
        }
    }

    private var failureList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(viewModel.errors) { err in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
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
            if viewModel.phase == .done {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .tint(AccentColors.primary)
            } else if viewModel.phase == .ready {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(TextColors.secondary)

                Spacer()

                if viewModel.movesNeeded.isEmpty {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(AccentColors.primary)
                } else {
                    Button {
                        Task {
                            await viewModel.executeReorganize(
                                libraryRoot: libraryRoot,
                                database: DatabaseManager.shared
                            )
                        }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "folder.badge.plus")
                            Text("Move \(viewModel.movesNeeded.count) File\(viewModel.movesNeeded.count == 1 ? "" : "s")")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AccentColors.primary)
                    .keyboardShortcut(.return)
                }
            } else {
                // Preview loading or running — no footer actions
                Spacer()
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

#Preview {
    ReorganizeLibraryView(
        libraryRoot: URL(fileURLWithPath: "/Users/demo/Comics"),
        comics: Comic.samples
    )
}
