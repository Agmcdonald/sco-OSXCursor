//
//  BulkEditSheet.swift
//  SCO-OSXCursor
//
//  Shared bulk-edit form: apply any metadata field to many books at once.
//  Used from the Organize staging list (checked items) and the Library
//  selection mode. Empty fields are always left unchanged.
//

import SwiftUI

// MARK: - Bulk Edit Values
/// Fields to apply in a bulk edit. nil = leave unchanged.
struct BulkEditValues {
    var series: String?
    var publisher: String?
    var year: Int?
    var volume: Int?
    var bookFormat: Comic.BookFormat?
    var title: String?
    var writer: String?
    var artist: String?
    var coverArtist: String?
    var colorist: String?
    var inker: String?
    var editor: String?
    var summary: String?
    var contentRating: Comic.ContentRating?

    var isEmpty: Bool {
        series == nil && publisher == nil && year == nil && volume == nil
            && bookFormat == nil && title == nil && writer == nil && artist == nil
            && coverArtist == nil && colorist == nil && inker == nil && editor == nil
            && summary == nil && contentRating == nil
    }
}

// MARK: - Bulk Edit Sheet
struct BulkEditSheet: View {
    let itemCount: Int
    /// Set false when content rating doesn't apply (staged comics)
    var showsContentRating: Bool = true
    let onApply: (BulkEditValues) -> Void

    @Environment(\.dismiss) private var dismiss

    // Core fields
    @State private var series = ""
    @State private var publisher = ""
    @State private var yearText = ""
    @State private var volumeText = ""
    @State private var changeFormat = false
    @State private var format: Comic.BookFormat = .issue

    // Credits & details
    @State private var title = ""
    @State private var writer = ""
    @State private var artist = ""
    @State private var coverArtist = ""
    @State private var colorist = ""
    @State private var inker = ""
    @State private var editor = ""
    @State private var summary = ""
    @State private var changeContentRating = false
    @State private var contentRating: Comic.ContentRating = .allAges
    @State private var creditsExpanded = false

    // MARK: Parsing

    private var parsedYear: Int? {
        guard let year = Int(yearText.trimmingCharacters(in: .whitespaces)),
            (1900...2100).contains(year)
        else { return nil }
        return year
    }

    private var parsedVolume: Int? {
        guard let volume = Int(volumeText.trimmingCharacters(in: .whitespaces)), volume > 0
        else { return nil }
        return volume
    }

    private func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var values: BulkEditValues {
        BulkEditValues(
            series: cleaned(series),
            publisher: cleaned(publisher),
            year: parsedYear,
            volume: parsedVolume,
            bookFormat: changeFormat ? format : nil,
            title: cleaned(title),
            writer: cleaned(writer),
            artist: cleaned(artist),
            coverArtist: cleaned(coverArtist),
            colorist: cleaned(colorist),
            inker: cleaned(inker),
            editor: cleaned(editor),
            summary: cleaned(summary),
            contentRating: (showsContentRating && changeContentRating) ? contentRating : nil
        )
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Bulk Edit")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                Text(
                    "Applies to \(itemCount) selected book\(itemCount == 1 ? "" : "s"). Empty fields are left unchanged."
                )
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
            }
            .padding(Spacing.xl)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    field("Series") {
                        TextField("Leave unchanged", text: $series)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("Publisher") {
                        TextField("Leave unchanged", text: $publisher)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: Spacing.md) {
                        field("Year") {
                            TextField("Unchanged", text: $yearText)
                                .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                    .keyboardType(.numberPad)
                                #endif
                        }
                        field("Volume") {
                            TextField("Unchanged", text: $volumeText)
                                .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                    .keyboardType(.numberPad)
                                #endif
                        }
                    }

                    if !yearText.isEmpty && parsedYear == nil {
                        Text("Year must be a number between 1900 and 2100")
                            .font(Typography.caption)
                            .foregroundColor(.red)
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

                    if showsContentRating {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Toggle("Change content rating", isOn: $changeContentRating)
                                .font(Typography.caption)
                            if changeContentRating {
                                Picker("Content Rating", selection: $contentRating) {
                                    ForEach(Comic.ContentRating.allCases, id: \.self) { rating in
                                        Text(rating.label).tag(rating)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }
                    }

                    DisclosureGroup("Credits & Details", isExpanded: $creditsExpanded) {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            field("Storyline Title") {
                                TextField("Leave unchanged", text: $title)
                                    .textFieldStyle(.roundedBorder)
                            }
                            field("Writer") {
                                TextField("Leave unchanged", text: $writer)
                                    .textFieldStyle(.roundedBorder)
                            }
                            field("Artist") {
                                TextField("Leave unchanged", text: $artist)
                                    .textFieldStyle(.roundedBorder)
                            }
                            field("Cover Artist") {
                                TextField("Leave unchanged", text: $coverArtist)
                                    .textFieldStyle(.roundedBorder)
                            }
                            field("Colorist") {
                                TextField("Leave unchanged", text: $colorist)
                                    .textFieldStyle(.roundedBorder)
                            }
                            field("Inker") {
                                TextField("Leave unchanged", text: $inker)
                                    .textFieldStyle(.roundedBorder)
                            }
                            field("Editor") {
                                TextField("Leave unchanged", text: $editor)
                                    .textFieldStyle(.roundedBorder)
                            }
                            field("Summary") {
                                TextField("Leave unchanged", text: $summary, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(3...6)
                            }
                        }
                        .padding(.top, Spacing.sm)
                    }
                    .font(Typography.bodySmall)
                }
                .padding(Spacing.xl)
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply to \(itemCount)") {
                    onApply(values)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(values.isEmpty)
            }
            .padding(Spacing.xl)
        }
        .frame(minWidth: 400, idealWidth: 460, minHeight: 460, idealHeight: 560)
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
