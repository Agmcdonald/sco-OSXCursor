//
//  MergePDFsSheet.swift
//  SCO-OSXCursor
//
//  Order-and-confirm sheet for merging checked staged PDFs into one CBZ.
//  Metadata comes from the first file (editable afterwards in the
//  inspector, like any staged item).
//

import SwiftUI

struct MergePDFsSheet: View {
    let candidates: [StagedComic]
    let onMerge: ([StagedComic]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var ordered: [StagedComic] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Merge into One CBZ")
                .font(Typography.h2)
                .foregroundColor(TextColors.primary)

            Text(
                "These PDFs become a single CBZ, pages in the order below (drag to reorder). Metadata starts from the first file — edit it in the inspector before confirming. The original PDFs are filed under \"Converted PDFs\" after a successful convert."
            )
            .font(Typography.bodySmall)
            .foregroundColor(TextColors.secondary)
            .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(ordered) { staged in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(TextColors.tertiary)
                        Text(staged.originalFileName)
                            .font(Typography.body)
                        Spacer()
                        Text(ByteCountFormatter.string(
                            fromByteCount: staged.fileSize, countStyle: .file))
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                    }
                }
                .onMove { from, to in
                    ordered.move(fromOffsets: from, toOffset: to)
                }
            }
            .frame(minHeight: 160)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Merge \(ordered.count) PDFs") {
                    onMerge(ordered)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(ordered.count < 2)
            }
        }
        .padding(Spacing.xl)
        // Fixed minimum sizes are for the macOS sheet window; iOS sheets
        // are screen-sized and a forced width clips portrait iPhones.
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 340)
        #endif
        .onAppear { ordered = candidates }
    }
}
