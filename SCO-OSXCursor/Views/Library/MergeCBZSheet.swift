//
//  MergeCBZSheet.swift
//  SCO-OSXCursor
//
//  "Merge into CBZ…" — combines the selected CBZ books into one larger CBZ.
//  The sheet exists because page ORDER is the whole point of a merge and
//  only the user knows it: the list is reorderable, with a natural-order
//  sort for the common case where the file names already say it.
//
//  Non-CBZ picks in the selection aren't silently dropped — they're listed
//  as left out, so nobody discovers a missing issue after the fact.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Request Wrapper

/// Wraps a merge request so it can drive `.sheet(item:)`.
struct CBZMergeRequest: Identifiable {
    let id = UUID()
    /// Everything the user had selected — the sheet splits it into
    /// mergeable parts and left-out books itself.
    let comics: [Comic]
}

// MARK: - Sheet

@MainActor
struct MergeCBZSheet: View {
    @ObservedObject var viewModel: LibraryViewModel

    let comics: [Comic]
    /// Called when the sheet is done; the message (if any) goes to the
    /// library's status toast.
    let onDone: (String?) -> Void

    private enum Phase {
        case configure
        case merging
        case done(LibraryViewModel.CBZMergeReport)
        case failed(String)
    }

    @State private var phase: Phase = .configure
    @State private var parts: [Comic] = []
    @State private var spec = LibraryViewModel.CBZMergeSpec()
    @State private var yearText: String = ""
    @State private var volumeText: String = ""
    @State private var progress: Double = 0
    @State private var showingFolderPicker = false
    @State private var mergeTask: Task<Void, Never>?

    /// Selected books a CBZ merge can't take (PDF, CBR, EPUB, or a file
    /// that's gone missing).
    private var leftOut: [Comic] {
        let mergeableIDs = Set(LibraryViewModel.mergeableCBZs(from: comics).map(\.id))
        return comics.filter { !mergeableIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(BorderColors.subtle)

            Group {
                switch phase {
                case .configure: configureView
                case .merging: mergingView
                case .done(let report): doneView(report)
                case .failed(let message): failedView(message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
            .frame(width: 540, height: 620)
        #endif
        .background(BackgroundColors.primary)
        .onAppear(perform: prefill)
        .onDisappear { mergeTask?.cancel() }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let folder) = result { spec.destinationFolder = folder }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Merge into CBZ")
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
                Text(subtitle)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
            }
            Spacer()
            Button {
                mergeTask?.cancel()
                onDone(nil)
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
        switch phase {
        case .merging:
            return "Copying pages — your original files aren't changed."
        case .done, .failed:
            return "Originals are only removed when you ask for it."
        case .configure:
            return
                "\(parts.count) CBZ file\(parts.count == 1 ? "" : "s") become one book, in the order below."
        }
    }

    // MARK: - Configure

    private var configureView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                partsSection
                if !leftOut.isEmpty { leftOutSection }
                metadataSection
                destinationSection
                originalsSection
            }
            .padding(Spacing.lg)
        }
        .safeAreaInset(edge: .bottom) { mergeBar }
    }

    private var partsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Reading Order")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                Spacer()
                Button {
                    parts.sort {
                        $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
                    }
                } label: {
                    Label("Sort by File Name", systemImage: "arrow.up.arrow.down")
                        .font(Typography.bodySmall)
                }
                .buttonStyle(.plain)
                .foregroundColor(AccentColors.primary)
                .help("Order the parts the way their file names sort (1, 2, 10 — not 1, 10, 2).")
            }

            VStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.element.id) { index, comic in
                    partRow(index: index, comic: comic)
                    if index < parts.count - 1 {
                        Divider().background(BorderColors.subtle)
                    }
                }
            }
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func partRow(index: Int, comic: Comic) -> some View {
        HStack(spacing: Spacing.md) {
            Text("\(index + 1)")
                .font(Typography.caption)
                .foregroundColor(TextColors.tertiary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(comic.displayTitle)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(1)
                Text(comic.fileName)
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                move(from: index, to: index - 1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .foregroundColor(index == 0 ? TextColors.tertiary : AccentColors.primary)
            .disabled(index == 0)
            .help("Move earlier")

            Button {
                move(from: index, to: index + 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .foregroundColor(
                index == parts.count - 1 ? TextColors.tertiary : AccentColors.primary)
            .disabled(index == parts.count - 1)
            .help("Move later")

            Button {
                parts.removeAll { $0.id == comic.id }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundColor(parts.count > 2 ? TextColors.secondary : TextColors.tertiary)
            .disabled(parts.count <= 2)
            .help("Leave this book out of the merge")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var leftOutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label(
                "\(leftOut.count) selected book\(leftOut.count == 1 ? "" : "s") left out",
                systemImage: "exclamationmark.triangle"
            )
            .font(Typography.bodySmall)
            .foregroundColor(AccentColors.warning)

            Text(
                "Merging reads CBZ archives. "
                    + leftOut.map(\.fileName).joined(separator: ", ")
            )
            .font(Typography.caption)
            .foregroundColor(TextColors.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(AccentColors.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Merged Book")
                .font(Typography.h3)
                .foregroundColor(TextColors.primary)

            field("Title", text: $spec.title, prompt: "Saga Vol. 1")
            field("Series", text: $spec.series, prompt: "Saga")
            field("Publisher", text: $spec.publisher, prompt: "Image Comics")

            HStack(spacing: Spacing.md) {
                field("Year", text: $yearText, prompt: "2012")
                field("Volume", text: $volumeText, prompt: "1")
            }

            Text("Saved as “\(fileNamePreview)” and written into the archive as ComicInfo.xml.")
                .font(Typography.caption)
                .foregroundColor(TextColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Destination")
                .font(Typography.h3)
                .foregroundColor(TextColors.primary)

            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.destinationFolder?.lastPathComponent ?? "Home Library")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.primary)
                        .lineLimit(1)
                    Text(
                        spec.destinationFolder == nil
                            ? "The merged file lands in your library folder, then files itself like any import."
                            : spec.destinationFolder?.path ?? ""
                    )
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
                    .lineLimit(2)
                }
                Spacer()
                if spec.destinationFolder != nil {
                    Button("Reset") { spec.destinationFolder = nil }
                        .buttonStyle(.plain)
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                }
                Button("Choose…") { showingFolderPicker = true }
                    .buttonStyle(.bordered)
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var originalsSection: some View {
        Toggle(isOn: $spec.trashOriginals) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Move the original files to the Trash")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.primary)
                Text(
                    "Runs only after the merged archive verifies. Restorable from Maintenance → Trash."
                )
                .font(Typography.caption)
                .foregroundColor(TextColors.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(AccentColors.primary)
    }

    private var mergeBar: some View {
        HStack(spacing: Spacing.md) {
            Spacer()
            Button("Cancel") { onDone(nil) }
                .buttonStyle(.bordered)
            Button {
                startMerge()
            } label: {
                Text(parts.count >= 2 ? "Merge \(parts.count) Files" : "Merge")
                    .font(Typography.button)
            }
            .buttonStyle(.borderedProminent)
            .tint(AccentColors.primary)
            .disabled(parts.count < 2)
        }
        .padding(Spacing.lg)
        .background(.ultraThinMaterial)
    }

    // MARK: - Progress / Result

    private var mergingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView(value: progress) {
                Text("Merging \(parts.count) files…")
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
            }
            .progressViewStyle(.linear)
            .tint(AccentColors.primary)

            Text("\(Int(progress * 100))%")
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)

            Button("Cancel") {
                mergeTask?.cancel()
            }
            .buttonStyle(.bordered)
        }
        .padding(Spacing.xl)
    }

    private func doneView(_ report: LibraryViewModel.CBZMergeReport) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(AccentColors.success)

            Text("“\(report.url.lastPathComponent)” — \(report.pageCount) pages")
                .font(Typography.body)
                .foregroundColor(TextColors.primary)
                .multilineTextAlignment(.center)

            Text(report.message)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
                .multilineTextAlignment(.center)

            Button("Done") { onDone(report.message) }
                .buttonStyle(.borderedProminent)
                .tint(AccentColors.primary)
        }
        .padding(Spacing.xl)
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

            HStack(spacing: Spacing.md) {
                Button("Back") { phase = .configure }
                    .buttonStyle(.bordered)
                Button("Close") { onDone(nil) }
                    .buttonStyle(.borderedProminent)
                    .tint(AccentColors.primary)
            }
        }
        .padding(Spacing.xl)
    }

    // MARK: - Chrome

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(Typography.bodySmall)
        }
    }

    // MARK: - Behaviour

    /// Seeds the order from the selection (file-name order, the order the
    /// parts are meant to read in far more often than not) and the metadata
    /// from the first part, which is where a collection's identity lives.
    private func prefill() {
        guard parts.isEmpty else { return }
        parts = LibraryViewModel.mergeableCBZs(from: comics)
            .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }

        guard let first = parts.first else { return }
        spec.series = first.series ?? ""
        spec.publisher = first.publisher ?? ""
        // "Saga" + 12 issues reads as a collected volume, so the title is
        // seeded from the series, not from issue #1's own title.
        spec.title = first.series ?? first.displayName
        if let year = parts.compactMap(\.year).min() { yearText = String(year) }
    }

    private var fileNamePreview: String {
        CBZMerger.sanitizedFileName(spec.fileNameBase) + ".cbz"
    }

    private func move(from index: Int, to target: Int) {
        guard parts.indices.contains(index), parts.indices.contains(target) else { return }
        let comic = parts.remove(at: index)
        parts.insert(comic, at: target)
    }

    private func startMerge() {
        guard parts.count >= 2, mergeTask == nil else { return }
        spec.year = Int(yearText.trimmingCharacters(in: .whitespaces))
        spec.volume = Int(volumeText.trimmingCharacters(in: .whitespaces))
        progress = 0
        phase = .merging

        let ordered = parts
        let request = spec
        mergeTask = Task {
            let result = await viewModel.mergeIntoCBZ(ordered, spec: request) { fraction in
                // The merge reports from its own task; the bar is view state.
                Task { @MainActor in progress = fraction }
            }
            mergeTask = nil
            switch result {
            case .success(let report):
                // A merge that finished before the cancel landed still made
                // a real file and a real library row — report it rather
                // than dropping the user back into the form.
                phase = .done(report)
            case .failure(let error):
                phase = Task.isCancelled ? .configure : .failed(error.localizedDescription)
            }
        }
    }
}
