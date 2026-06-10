//
//  OrganizeInspectorView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 2/15/26.
//

import Foundation
import SwiftUI

struct OrganizeInspectorView: View {
    @ObservedObject var viewModel: OrganizeViewModel
    @StateObject private var knowledgeViewModel = KnowledgeViewModel()

    // Local state for editing
    @State private var series: String
    @State private var issueNumber: String
    @State private var year: Int
    @State private var publisher: String
    @State private var volume: Int?
    @State private var bookFormat: Comic.BookFormat

    // Optional additional metadata
    @State private var title: String
    @State private var writer: String
    @State private var artist: String
    @State private var coverArtist: String
    @State private var colorist: String
    @State private var inker: String
    @State private var editor: String
    @State private var summary: String
    @State private var isAdditionalMetadataExpanded: Bool = false

    let comic: StagedComic

    init(comic: StagedComic, viewModel: OrganizeViewModel) {
        self.comic = comic
        self.viewModel = viewModel

        // Init state from comic
        _series = State(initialValue: comic.series)
        _issueNumber = State(initialValue: comic.issueNumber ?? "")
        _year = State(initialValue: comic.year ?? 0)
        _publisher = State(initialValue: comic.publisher ?? "")
        _volume = State(initialValue: comic.volume)
        _bookFormat = State(initialValue: comic.bookFormat)
        _title = State(initialValue: comic.title ?? "")
        _writer = State(initialValue: comic.writer ?? "")
        _artist = State(initialValue: comic.artist ?? "")
        _coverArtist = State(initialValue: comic.coverArtist ?? "")
        _colorist = State(initialValue: comic.colorist ?? "")
        _inker = State(initialValue: comic.inker ?? "")
        _editor = State(initialValue: comic.editor ?? "")
        _summary = State(initialValue: comic.summary ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {  // Spacing.lg -> 16
                // Header
                HStack {
                    Text("File Details")
                        .font(.title3)  // Typography.h3 -> .title3
                    Spacer()

                    // Confidence Badge
                    Text(comic.confidence.rawValue)
                        .font(.caption)  // Typography.caption -> .caption
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(comic.confidence.color.opacity(0.2))
                        .foregroundColor(comic.confidence.color)
                        .cornerRadius(4)
                }

                Text(comic.originalFileName)
                    .font(.caption)  // Typography.caption -> .caption
                    .foregroundColor(.secondary)  // TextColors.tertiary -> .secondary

                Divider()

                // Form Fields
                Group {
                    // Book Format — issue, one-shot/OGN, or collected volume.
                    // Determines which fields are required and the clean name.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Format")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Format", selection: $bookFormat) {
                            ForEach(Comic.BookFormat.allCases, id: \.self) { format in
                                Text(format.displayName).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Series
                    VStack(alignment: .leading, spacing: 4) {  // Spacing.xs -> 4
                        Text("Series")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        AutocompleteTextField(
                            title: "Series Name",
                            text: $series,
                            fetchSuggestions: { query in
                                await knowledgeViewModel.getSuggestions(for: "series", query: query)
                            }
                        )
                        .zIndex(2)
                    }

                    HStack(spacing: 12) {  // Spacing.md -> 12
                        // Issue
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Issue")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("001", text: $issueNumber)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        // Volume
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Volume")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("1", value: $volume, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        // Year
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Year")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("YYYY", value: $year, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }

                    // Publisher
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Publisher")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        AutocompleteTextField(
                            title: "Unknown Publisher",
                            text: $publisher,
                            fetchSuggestions: { query in
                                await knowledgeViewModel.getSuggestions(
                                    for: "publisher", query: query)
                            }
                        )
                        .zIndex(1)
                    }
                }
                .onChange(of: series) { _, _ in update() }
                .onChange(of: issueNumber) { _, _ in update() }
                .onChange(of: year) { _, _ in update() }
                .onChange(of: publisher) { _, _ in update() }
                .onChange(of: volume) { _, _ in update() }
                .onChange(of: bookFormat) { _, _ in update() }

                DisclosureGroup("Additional Metadata", isExpanded: $isAdditionalMetadataExpanded) {
                    Group {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Storyline Title")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Optional", text: $title)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Writer")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            AutocompleteTextField(
                                title: "Optional",
                                text: $writer,
                                fetchSuggestions: { query in
                                    await knowledgeViewModel.getSuggestions(
                                        for: "writer", query: query)
                                }
                            )
                            .zIndex(8)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Artist")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            AutocompleteTextField(
                                title: "Optional",
                                text: $artist,
                                fetchSuggestions: { query in
                                    await knowledgeViewModel.getSuggestions(
                                        for: "artist", query: query)
                                }
                            )
                            .zIndex(7)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cover Artist")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            AutocompleteTextField(
                                title: "Optional",
                                text: $coverArtist,
                                fetchSuggestions: { query in
                                    await knowledgeViewModel.getSuggestions(
                                        for: "coverArtist", query: query)
                                }
                            )
                            .zIndex(6)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Colorist")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            AutocompleteTextField(
                                title: "Optional",
                                text: $colorist,
                                fetchSuggestions: { query in
                                    await knowledgeViewModel.getSuggestions(
                                        for: "colorist", query: query)
                                }
                            )
                            .zIndex(5)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Inker")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            AutocompleteTextField(
                                title: "Optional",
                                text: $inker,
                                fetchSuggestions: { query in
                                    await knowledgeViewModel.getSuggestions(
                                        for: "inker", query: query)
                                }
                            )
                            .zIndex(4)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Editor")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            AutocompleteTextField(
                                title: "Optional",
                                text: $editor,
                                fetchSuggestions: { query in
                                    await knowledgeViewModel.getSuggestions(
                                        for: "editor", query: query)
                                }
                            )
                            .zIndex(3)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if #available(macOS 13.0, iOS 16.0, *) {
                                TextField("Optional summary", text: $summary, axis: .vertical)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .lineLimit(4...8)
                            } else {
                                TextEditor(text: $summary)
                                    .frame(minHeight: 80)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
                .onChange(of: title) { _, _ in update() }
                .onChange(of: writer) { _, _ in update() }
                .onChange(of: artist) { _, _ in update() }
                .onChange(of: coverArtist) { _, _ in update() }
                .onChange(of: colorist) { _, _ in update() }
                .onChange(of: inker) { _, _ in update() }
                .onChange(of: editor) { _, _ in update() }
                .onChange(of: summary) { _, _ in update() }

                Divider()

                // Actions
                HStack {
                    Button("Import to Library") {
                        Task {
                            update()
                            await viewModel.confirmMatch(comic)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canImport)
                }
                .frame(maxWidth: .infinity)

            }
            .padding()
        }
        #if os(macOS)
            .background(Color(NSColor.textBackgroundColor))  // Approximate BackgroundColors.secondary
        #else
            .background(Color(.systemBackground))
        #endif
        .onAppear {
            // Sync auto-parsed metadata back to viewModel so confirmMatch reads current values
            update()
        }
    }

    /// Format-aware import gate: issues need an issue number, one-shots a
    /// year, volumes a volume number. Publisher is always required so the
    /// file can be sorted into the library structure.
    private var canImport: Bool {
        guard !series.isEmpty, !publisher.isEmpty else { return false }
        switch bookFormat {
        case .issue: return !issueNumber.isEmpty
        case .oneShot: return year > 0
        case .volume: return volume != nil
        }
    }

    private func update() {
        Task { @MainActor in
            viewModel.updateMetadata(
                id: comic.id,
                series: series,
                issue: issueNumber,
                year: year,
                publisher: publisher,
                volume: volume,
                bookFormat: bookFormat,
                title: title.isEmpty ? nil : title,
                writer: writer.isEmpty ? nil : writer,
                artist: artist.isEmpty ? nil : artist,
                coverArtist: coverArtist.isEmpty ? nil : coverArtist,
                colorist: colorist.isEmpty ? nil : colorist,
                inker: inker.isEmpty ? nil : inker,
                editor: editor.isEmpty ? nil : editor,
                summary: summary.isEmpty ? nil : summary
            )
        }
    }
}
