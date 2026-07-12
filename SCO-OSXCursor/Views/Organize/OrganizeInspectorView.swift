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
    @State private var showingCoverZoom = false

    // ComicVine fetch (staging)
    @State private var isFetchingCV = false
    @State private var cvCandidates: [CVCandidate] = []
    @State private var showingCVPicker = false
    @State private var cvMessage: String?

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

                // Ready/Pending explainer — tells the user exactly which
                // fields still stand between this book and "Ready".
                readyChecklist

                // Cover preview — extracted lazily for the selected file only,
                // so staging stays fast. Click to enlarge.
                coverPreview

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
                        fieldLabel("Series")
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
                            fieldLabel("Issue")
                            TextField("001", text: $issueNumber)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        // Volume
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Volume")
                            TextField("1", value: $volume, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        // Year
                        VStack(alignment: .leading, spacing: 4) {
                            fieldLabel("Year")
                            TextField("YYYY", value: $year, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }

                    // Publisher
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Publisher")
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
                HStack(spacing: 12) {
                    // Look the book up and fill the fields above for review
                    // BEFORE it gets imported. eBooks use the book sources
                    // (Open Library / Google Books / Hardcover); comics use
                    // ComicVine.
                    Button(action: fetchFromComicVine) {
                        HStack(spacing: 4) {
                            if isFetchingCV {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(bookFormat == .ebook ? "Fetch Book Metadata" : "Fetch from ComicVine")
                        }
                    }
                    .disabled(isFetchingCV)
                    .help(
                        bookFormat == .ebook
                            ? "Looks this book up on Open Library, Google Books, and Hardcover — no API key needed."
                            : "Looks this comic up on ComicVine (API key required, set in Settings).")

                    Button("Import to Library") {
                        Task {
                            update()
                            await viewModel.confirmMatch(comic)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canImport || isFetchingCV)
                }
                .frame(maxWidth: .infinity)

                if let cvMessage {
                    Text(cvMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }

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
        .featureHint(
            id: "organizeDetails",
            icon: "checkmark.circle",
            title: "Review, then import",
            message: "Check the detected details — fields marked in orange decide whether a book is Ready or Pending. Fetch from ComicVine fills them for you. Import books one at a time here, or all at once with Apply All Ready."
        )
        .sheet(isPresented: $showingCoverZoom) {
            CoverZoomView(
                coverData: viewModel.selectedCoverData,
                cacheKey: comic.id.uuidString
            ) {
                showingCoverZoom = false
            }
        }
        .sheet(isPresented: $showingCVPicker) {
            StagingMatchPickerSheet(
                fileName: comic.originalFileName,
                candidates: cvCandidates,
                onPick: { candidate in
                    showingCVPicker = false
                    isFetchingCV = true
                    Task {
                        let outcome = await viewModel.applyComicVineCandidate(
                            candidate, to: comic.id)
                        isFetchingCV = false
                        handleCVOutcome(outcome)
                    }
                },
                onCancel: { showingCVPicker = false }
            )
        }
    }

    // MARK: - ComicVine Fetch

    private func fetchFromComicVine() {
        update()  // Search with the user's current edits, not the stale parse
        isFetchingCV = true
        cvMessage = nil
        Task {
            // Routed by format: eBooks -> book sources, comics -> ComicVine.
            let outcome = await viewModel.fetchMetadata(for: comic.id)
            isFetchingCV = false
            handleCVOutcome(outcome)
        }
    }

    private func handleCVOutcome(_ outcome: OrganizeViewModel.StagingCVOutcome) {
        switch outcome {
        case .applied(let merged):
            applyFetched(merged)
            cvMessage = "Details loaded — review the fields, then import."
        case .needsChoice(let candidates):
            cvCandidates = candidates
            showingCVPicker = true
        case .noKey:
            cvMessage = "Add a ComicVine API key in Settings first."
        case .noMatches:
            cvMessage =
                bookFormat == .ebook
                ? "No confident match — you can import and use Search Matches from the Library."
                : "No ComicVine matches found for this series."
        case .failed(let message):
            cvMessage = message
        }
    }

    /// Push fetched metadata into the editable fields so the user can review
    /// and adjust everything before importing.
    private func applyFetched(_ merged: StagedComic) {
        series = merged.series
        issueNumber = merged.issueNumber ?? ""
        year = merged.year ?? 0
        publisher = merged.publisher ?? ""
        volume = merged.volume
        bookFormat = merged.bookFormat
        title = merged.title ?? ""
        writer = merged.writer ?? ""
        artist = merged.artist ?? ""
        coverArtist = merged.coverArtist ?? ""
        colorist = merged.colorist ?? ""
        inker = merged.inker ?? ""
        editor = merged.editor ?? ""
        summary = merged.summary ?? ""
        isAdditionalMetadataExpanded = true
        update()
    }

    // MARK: - Cover Preview

    private var coverPreview: some View {
        HStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))

                if let data = viewModel.selectedCoverData,
                    let image = PageImageCache.shared.coverImage(
                        from: data, cacheKey: comic.id.uuidString)
                {
                    #if os(macOS)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    #else
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    #endif
                } else if viewModel.isLoadingCover {
                    ProgressView()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                        Text("No cover")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .frame(width: 220, height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .shadow(radius: 3)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                if viewModel.selectedCoverData != nil { showingCoverZoom = true }
            }
            .help("Click to enlarge")
            Spacer()
        }
    }

    // MARK: - Ready Checklist
    //
    // Mirrors StagedComic.reevaluate(userEdited:) — the format-aware rules
    // that decide Ready (High confidence) vs Pending. Keep the two in sync.

    /// Fields still missing before this book reaches "Ready".
    private var missingForReady: [String] {
        var missing: [String] = []
        if series.isEmpty { missing.append("Series") }
        switch bookFormat {
        case .issue:
            if issueNumber.isEmpty { missing.append("Issue") }
            if year <= 0 { missing.append("Year") }
            if publisher.isEmpty { missing.append("Publisher") }
        case .oneShot:
            if year <= 0 { missing.append("Year") }
            if publisher.isEmpty { missing.append("Publisher") }
        case .volume:
            if volume == nil { missing.append("Volume") }
            if year <= 0 { missing.append("Year") }
            if publisher.isEmpty { missing.append("Publisher") }
        case .ebook:
            if year <= 0 && publisher.isEmpty { missing.append("Year or Publisher") }
        }
        return missing
    }

    /// Whether a given field label should carry the "needed for Ready" marker.
    private func fieldNeedsAttention(_ field: String) -> Bool {
        if missingForReady.contains(field) { return true }
        // Ebooks accept either Year OR Publisher — flag both while neither is set
        if missingForReady.contains("Year or Publisher"),
            field == "Year" || field == "Publisher"
        {
            return true
        }
        return false
    }

    /// Field caption that grows an orange "needed for Ready" marker while
    /// the field is empty and required for Ready status.
    private func fieldLabel(_ name: String) -> some View {
        HStack(spacing: 5) {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            if fieldNeedsAttention(name) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                    Text("needed for Ready")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .help("Optional for import, but the book stays Pending until this is filled")
            }
        }
    }

    /// Green "all set" / orange "still missing …" callout under the header.
    @ViewBuilder
    private var readyChecklist: some View {
        if missingForReady.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("All key fields filled — this book is Ready to import.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pending — still missing: \(missingForReady.joined(separator: ", "))")
                        .font(.caption.weight(.semibold))
                    Text("These aren't required to import, but the book stays Pending until they're filled. Fetch from ComicVine can fill them automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Format-aware import gate: issues need an issue number, one-shots a
    /// year, volumes a volume number. A series is required, but the publisher
    /// is optional — you can approve a book whose publisher you don't know yet
    /// (it imports under "Unknown Publisher" and stays "Pending" in staging).
    private var canImport: Bool {
        guard !series.isEmpty else { return false }
        switch bookFormat {
        case .issue: return !issueNumber.isEmpty
        case .oneShot: return year > 0
        case .volume: return volume != nil
        case .ebook: return true
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

// MARK: - Cover Zoom

/// Enlarged cover shown when the inspector's cover is clicked.
struct CoverZoomView: View {
    let coverData: Data?
    let cacheKey: String
    let onClose: () -> Void

    var body: some View {
        VStack {
            if let data = coverData,
                let image = PageImageCache.shared.coverImage(from: data, cacheKey: cacheKey)
            {
                #if os(macOS)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                #else
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                #endif
            } else {
                Text("No cover available")
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BackgroundColors.primary)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(12)
            .keyboardShortcut(.cancelAction)
        }
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
        #if os(macOS)
            .frame(width: 640, height: 900)
        #endif
    }
}

// MARK: - ComicVine Match Picker (staging)

/// Candidate chooser shown when a staging ComicVine search is ambiguous.
/// Picking a volume fills the inspector fields for review — nothing is
/// imported to the library until the user confirms.
struct StagingMatchPickerSheet: View {
    let fileName: String
    let candidates: [CVCandidate]
    let onPick: (CVCandidate) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose the Right Match")
                        .font(.title3)
                    Text(fileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            List(candidates) { candidate in
                Button {
                    onPick(candidate)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.name)
                            .foregroundColor(.primary)
                        Text(subtitle(for: candidate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            #if os(macOS)
                .listStyle(.inset)
            #endif
        }
        #if os(macOS)
            .frame(width: 420, height: 380)
        #endif
    }

    private func subtitle(for candidate: CVCandidate) -> String {
        var parts: [String] = []
        if let year = candidate.startYear { parts.append(String(year)) }
        if let publisher = candidate.publisher, !publisher.isEmpty { parts.append(publisher) }
        if let count = candidate.issueCount { parts.append("\(count) issues") }
        return parts.isEmpty ? "ComicVine volume \(candidate.id)" : parts.joined(separator: " · ")
    }
}
