//
//  BulkEditSheet.swift
//  SCO-OSXCursor
//
//  Shared bulk-edit form: set Series / Publisher / Year / Format on many
//  books at once. Used from the Organize staging list (checked items) and
//  the Library selection mode. Empty fields are left unchanged.
//

import SwiftUI

struct BulkEditSheet: View {
    let itemCount: Int
    /// Called with the fields to apply; nil/empty means "leave unchanged"
    let onApply: (_ series: String?, _ publisher: String?, _ year: Int?, _ format: Comic.BookFormat?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var series = ""
    @State private var publisher = ""
    @State private var yearText = ""
    @State private var changeFormat = false
    @State private var format: Comic.BookFormat = .issue

    private var parsedYear: Int? {
        guard let year = Int(yearText.trimmingCharacters(in: .whitespaces)),
            (1900...2100).contains(year)
        else { return nil }
        return year
    }

    private var hasChanges: Bool {
        !series.trimmingCharacters(in: .whitespaces).isEmpty
            || !publisher.trimmingCharacters(in: .whitespaces).isEmpty
            || parsedYear != nil
            || changeFormat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Bulk Edit")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                Text("Applies to \(itemCount) selected book\(itemCount == 1 ? "" : "s"). Empty fields are left unchanged.")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
            }

            Divider()

            // Fields
            VStack(alignment: .leading, spacing: Spacing.md) {
                field("Series") {
                    TextField("Leave unchanged", text: $series)
                        .textFieldStyle(.roundedBorder)
                }

                field("Publisher") {
                    TextField("Leave unchanged", text: $publisher)
                        .textFieldStyle(.roundedBorder)
                }

                field("Year") {
                    TextField("Leave unchanged", text: $yearText)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                            .keyboardType(.numberPad)
                        #endif
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Toggle("Change format", isOn: $changeFormat)
                        .font(Typography.caption)
                    if changeFormat {
                        Picker("Format", selection: $format) {
                            ForEach(Comic.BookFormat.allCases, id: \.self) { f in
                                Text(f.displayName).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }

            if !yearText.isEmpty && parsedYear == nil {
                Text("Year must be a number between 1900 and 2100")
                    .font(Typography.caption)
                    .foregroundColor(.red)
            }

            Spacer(minLength: 0)

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply to \(itemCount)") {
                    let trimmedSeries = series.trimmingCharacters(in: .whitespaces)
                    let trimmedPublisher = publisher.trimmingCharacters(in: .whitespaces)
                    onApply(
                        trimmedSeries.isEmpty ? nil : trimmedSeries,
                        trimmedPublisher.isEmpty ? nil : trimmedPublisher,
                        parsedYear,
                        changeFormat ? format : nil
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 380, idealWidth: 420, minHeight: 360)
    }

    @ViewBuilder
    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
            content()
        }
    }
}
