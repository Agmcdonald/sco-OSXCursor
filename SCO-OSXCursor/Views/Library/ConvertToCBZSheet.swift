//
//  ConvertToCBZSheet.swift
//  SCO-OSXCursor
//
//  Preview → run → done sheet for converting library PDFs to CBZ.
//

import SwiftUI

struct ConvertToCBZSheet: View {
    @StateObject private var viewModel: ConvertToCBZViewModel
    let library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    init(selection: [Comic], library: LibraryViewModel) {
        _viewModel = StateObject(wrappedValue: ConvertToCBZViewModel(selection: selection))
        self.library = library
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Convert to CBZ")
                .font(Typography.h2)
                .foregroundColor(TextColors.primary)

            switch viewModel.phase {
            case .ready: readyView
            case .running: runningView
            case .done: doneView
            }
        }
        .padding(Spacing.xl)
        // Fixed minimum sizes are for the macOS sheet window. On iOS the
        // sheet is screen-sized — forcing 480pt clipped portrait iPhones.
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }

    // MARK: - Ready (preview)

    private var readyView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(
                "Each PDF becomes a CBZ — written next to the PDF, or filed into your home library when the PDF lives outside it. Scanned pages keep their original image quality, and the book's entry keeps its reading progress, lists, and folders. Afterwards the original PDF is filed under \"Converted PDFs\" in your home library, so you can delete it whenever you like."
            )
            .font(Typography.bodySmall)
            .foregroundColor(TextColors.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if viewModel.skippedCount > 0 {
                Text("\(viewModel.skippedCount) selected item(s) will be skipped — only PDF books can be converted (books marked as eBooks, bundled samples, and books with missing files are excluded).")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
            }

            List(viewModel.candidates) { comic in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comic.displayTitle).font(Typography.body)
                        Text(comic.fileName)
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                    }
                    Spacer()
                    if comic.totalPages > 0 {
                        Text("\(comic.totalPages) pages")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                    }
                    Text(ByteCountFormatter.string(
                        fromByteCount: comic.fileSize, countStyle: .file))
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                }
            }
            .frame(minHeight: 140)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Convert \(viewModel.candidates.count) Book\(viewModel.candidates.count == 1 ? "" : "s")") {
                    Task { await viewModel.run(library: library) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.candidates.isEmpty)
            }
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ProgressView(value: viewModel.progress)
            Text(viewModel.statusLine)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
            Text("\(viewModel.completedCount + viewModel.failedCount) of \(viewModel.candidates.count)")
                .font(Typography.caption)
                .foregroundColor(TextColors.tertiary)
            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(
                "\(viewModel.completedCount) converted, \(viewModel.failedCount) failed",
                systemImage: viewModel.failedCount == 0
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(Typography.h3)
            .foregroundColor(viewModel.failedCount == 0 ? .green : .orange)

            if !viewModel.errors.isEmpty || !viewModel.warnings.isEmpty {
                List {
                    ForEach(viewModel.errors) { error in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error.name).font(Typography.body)
                            Text(error.reason)
                                .font(Typography.caption)
                                .foregroundColor(.red)
                        }
                    }
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(Typography.caption)
                            .foregroundColor(.orange)
                    }
                }
                .frame(minHeight: 120)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
