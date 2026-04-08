//
//  ComicDetailView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//

import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

// MARK: - Comic Detail View
@MainActor
struct ComicDetailView: View {
    let comic: Comic
    let onSave: (Comic) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    @StateObject private var knowledgeViewModel = KnowledgeViewModel()

    // The authoritative edited copy — only updated when Save is pressed.
    @State private var editedComic: Comic

    // MARK: - Draft (local) state for every editable field
    // Bound directly to the TextFields so re-renders of the parent struct
    // cannot overwrite in-progress keystrokes.
    @State private var draftTitle: String
    @State private var draftPublisher: String
    @State private var draftSeries: String
    @State private var draftIssueNumber: String
    @State private var draftVolume: String  // stored as String; converted to Int? on save
    @State private var draftYear: String  // stored as String; converted to Int? on save
    @State private var draftContentRating: Comic.ContentRating
    @State private var draftWriter: String
    @State private var draftArtist: String
    @State private var draftCoverArtist: String
    @State private var draftColorist: String
    @State private var draftInker: String
    @State private var draftEditor: String
    @State private var draftSummary: String
    @State private var draftRating: Int

    @State private var showingSaveConfirmation = false
    @State private var saveError: String?

    // Track focus to force-commit TextEditor on macOS before saving
    enum Field: Hashable {
        case title, publisher, series, issue, volume, year, writer, artist, coverArtist, colorist,
            inker, editor, summary
    }

    @FocusState private var focusedField: Field?

    init(comic: Comic, onSave: @escaping (Comic) async throws -> Void) {
        self.comic = comic
        self.onSave = onSave

        _editedComic = State(initialValue: comic)

        // Populate drafts from the comic's current values.
        // Using empty string instead of nil so TextFields stay stable.
        _draftTitle = State(initialValue: comic.title ?? "")
        _draftPublisher = State(initialValue: comic.publisher ?? "")
        _draftSeries = State(initialValue: comic.series ?? "")
        _draftIssueNumber = State(initialValue: comic.issueNumber ?? "")
        _draftVolume = State(initialValue: comic.volume.map { String($0) } ?? "")
        _draftYear = State(initialValue: comic.year.map { String($0) } ?? "")
        _draftContentRating = State(initialValue: comic.contentRating)
        _draftWriter = State(initialValue: comic.writer ?? "")
        _draftArtist = State(initialValue: comic.artist ?? "")
        _draftCoverArtist = State(initialValue: comic.coverArtist ?? "")
        _draftColorist = State(initialValue: comic.colorist ?? "")
        _draftInker = State(initialValue: comic.inker ?? "")
        _draftEditor = State(initialValue: comic.editor ?? "")
        _draftSummary = State(initialValue: comic.summary ?? "")
        _draftRating = State(initialValue: comic.rating ?? 0)
    }

    // MARK: - hasChanges
    // Compare each draft against the original `comic` constant (not editedComic).
    var hasChanges: Bool {
        draftTitle != (comic.title ?? "") || draftPublisher != (comic.publisher ?? "")
            || draftSeries != (comic.series ?? "") || draftIssueNumber != (comic.issueNumber ?? "")
            || draftVolume != (comic.volume.map { String($0) } ?? "")
            || draftYear != (comic.year.map { String($0) } ?? "")
            || draftContentRating != comic.contentRating
            || draftWriter != (comic.writer ?? "") || draftArtist != (comic.artist ?? "")
            || draftCoverArtist != (comic.coverArtist ?? "")
            || draftColorist != (comic.colorist ?? "") || draftInker != (comic.inker ?? "")
            || draftEditor != (comic.editor ?? "") || draftSummary != (comic.summary ?? "")
            || draftRating != (comic.rating ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Header
                    headerView

                    Divider()
                        .background(BorderColors.subtle)

                    // Metadata Fields
                    metadataFields

                    // Save Button
                    saveButton
                }
                .padding(Spacing.xl)
                // CRITICAL: Force the content to report a real minimum size on macOS
                #if os(macOS)
                    .frame(minWidth: 550, maxWidth: 750, minHeight: 650)
                #endif
            }
            .background(BackgroundColors.primary)
            .navigationTitle("Edit Comic")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
            // Prefer min/ideal sizing over hard width/height (plays nicer with macOS sheets)
            .frame(
                minWidth: 650,
                idealWidth: 700,
                minHeight: 750,
                idealHeight: 800
            )
        #else
            .presentationDragIndicator(.visible)
        #endif
        .alert(
            "Save Failed",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK") {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: Spacing.lg) {
            // Cover Image
            if let coverData = editedComic.coverImageData {
                #if os(macOS)
                    if let nsImage = NSImage(data: coverData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                #else
                    if let uiImage = UIImage(data: coverData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                #endif
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(BackgroundColors.elevated)
                    .frame(width: 120, height: 180)
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: 40))
                            .foregroundColor(TextColors.tertiary)
                    )
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Display title built from current draft values so it updates as the user types
                Text(displayTitleFromDrafts)
                    .font(Typography.h1)
                    .foregroundColor(TextColors.primary)

                Text(editedComic.cleanFileName)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.tertiary)

                if hasChanges {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 12))
                        Text("Unsaved changes")
                            .font(Typography.caption)
                    }
                    .foregroundColor(AccentColors.warning)
                    .padding(.top, Spacing.xs)
                }
            }

            Spacer()
        }
    }

    // Live preview of the display title using the current draft values
    private var displayTitleFromDrafts: String {
        let base =
            draftSeries.isEmpty
            ? (draftTitle.isEmpty ? editedComic.fileName : draftTitle) : draftSeries
        var result = base
        if !draftIssueNumber.isEmpty {
            if draftIssueNumber.prefix(1).allSatisfy(\.isNumber) {
                result += " #\(draftIssueNumber)"
            } else {
                result += " \(draftIssueNumber)"
            }
        }
        if !draftYear.isEmpty {
            result += " (\(draftYear))"
        }
        return result
    }

    // MARK: - Metadata Fields

    private var metadataFields: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Core Metadata Section
            metadataSection(title: "Core Information", icon: "info.circle") {
                metadataField(
                    label: "Series", text: $draftSeries, field: .series,
                    knowledgeType: .series)
                metadataField(
                    label: "Publisher", text: $draftPublisher, field: .publisher,
                    isPublisher: true, knowledgeType: .publisher)
                metadataField(label: "Storyline Title", text: $draftTitle, field: .title)
                metadataField(label: "Issue Number", text: $draftIssueNumber, field: .issue)

                HStack {
                    metadataNumericField(label: "Volume", value: $draftVolume, field: .volume)
                    metadataNumericField(label: "Year", value: $draftYear, field: .year)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Content Rating")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                    
                    Picker("Content Rating", selection: $draftContentRating) {
                        ForEach(Comic.ContentRating.allCases, id: \.self) { rating in
                            Text(rating.label).tag(rating)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, Spacing.xs)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("User Rating")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                    
                    HStack(spacing: Spacing.sm) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: {
                                draftRating = (draftRating == star) ? 0 : star
                            }) {
                                Image(systemName: star <= draftRating ? "star.fill" : "star")
                                    .foregroundColor(star <= draftRating ? AccentColors.warning : TextColors.tertiary)
                                    .font(.system(size: 20))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
            }

            // Credits Section
            metadataSection(title: "Credits", icon: "person.2.fill") {
                metadataField(
                    label: "Writer", text: $draftWriter, field: .writer,
                    knowledgeType: .writer)
                metadataField(
                    label: "Artist", text: $draftArtist, field: .artist,
                    knowledgeType: .artist)
                metadataField(
                    label: "Cover Artist", text: $draftCoverArtist, field: .coverArtist,
                    knowledgeType: .coverArtist)
                metadataField(
                    label: "Colorist", text: $draftColorist, field: .colorist,
                    knowledgeType: .colorist)
                metadataField(
                    label: "Inker", text: $draftInker, field: .inker, knowledgeType: .inker)
                metadataField(
                    label: "Editor", text: $draftEditor, field: .editor,
                    knowledgeType: .editor)
            }

            // Summary Section
            metadataSection(title: "Summary", icon: "text.alignleft") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Summary")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)

                    TextEditor(text: $draftSummary)
                        .focused($focusedField, equals: .summary)
                        .font(Typography.body)
                        .foregroundColor(TextColors.primary)
                        .frame(minHeight: 100)
                        .padding(Spacing.sm)
                        .background(BackgroundColors.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(BorderColors.subtle, lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - Metadata Section

    private func metadataSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(AccentColors.primary)

                Text(title)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
            }

            content()
        }
        .padding(Spacing.lg)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Metadata Field (String draft binding)

    /// Text field bound to a `String` draft variable (optional fields stored as empty string).
    private func metadataField(
        label: String,
        text: Binding<String>,
        field: Field,
        isPublisher: Bool = false,
        knowledgeType: KnowledgeEntry.EntryType? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)

            if let knowledgeType = knowledgeType {
                AutocompleteTextField(
                    title: label,
                    text: text,  // bound directly to the draft String — no wrapping needed
                    fetchSuggestions: { query in
                        await knowledgeViewModel.getSuggestions(
                            for: knowledgeType.rawValue, query: query)
                    }
                )
                .focused($focusedField, equals: field)
                .autocorrectionDisabled()
                #if os(iOS)
                    .autocapitalization(.words)
                #endif
            } else {
                TextField(label, text: text)
                    .focused($focusedField, equals: field)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                    .padding(Spacing.md)
                    .background(BackgroundColors.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(BorderColors.subtle, lineWidth: 1)
                    )
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .autocapitalization(.words)
                    #endif
            }

            // Publisher color indicator
            if isPublisher, !text.wrappedValue.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(PublisherDetector.color(for: text.wrappedValue))
                        .frame(width: 8, height: 8)
                    Text(
                        "Normalized: \(PublisherDetector.normalize(text.wrappedValue) ?? text.wrappedValue)"
                    )
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    // MARK: - Numeric Field (Volume / Year)

    /// Text field for numeric values (Volume, Year) — bound to a String draft, validated on save.
    private func metadataNumericField(label: String, value: Binding<String>, field: Field)
        -> some View
    {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)

            TextField(label, text: value)
                .focused($focusedField, equals: field)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundColor(TextColors.primary)
                .padding(Spacing.md)
                .background(BackgroundColors.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BorderColors.subtle, lineWidth: 1)
                )
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: {
            // Clear focus so any in-flight TextEditor changes are committed
            focusedField = nil

            Task {
                // Small pause lets the run-loop process the focus change
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 s

                do {
                    try await saveChanges()
                } catch {
                    saveError = error.localizedDescription
                }
            }
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save Changes")
                    .font(Typography.button)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
            .background(AccentColors.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func saveChanges() async throws {
        // Commit all draft values → editedComic before persisting
        editedComic.title = draftTitle.nilIfEmpty
        editedComic.publisher = draftPublisher.nilIfEmpty
        editedComic.series = draftSeries.nilIfEmpty
        editedComic.issueNumber = draftIssueNumber.nilIfEmpty
        editedComic.volume = Int(draftVolume)  // nil if draftVolume is empty / non-numeric
        editedComic.year = Int(draftYear)
        editedComic.contentRating = draftContentRating
        editedComic.writer = draftWriter.nilIfEmpty
        editedComic.artist = draftArtist.nilIfEmpty
        editedComic.coverArtist = draftCoverArtist.nilIfEmpty
        editedComic.colorist = draftColorist.nilIfEmpty
        editedComic.inker = draftInker.nilIfEmpty
        editedComic.editor = draftEditor.nilIfEmpty
        editedComic.summary = draftSummary.nilIfEmpty
        editedComic.rating = draftRating > 0 ? draftRating : nil

        print("[ComicDetailView] 💾 Saving changes...")
        print("[ComicDetailView]    Title: '\(editedComic.title ?? "nil")'")
        print("[ComicDetailView]    Publisher: '\(editedComic.publisher ?? "nil")'")
        print("[ComicDetailView]    Series: '\(editedComic.series ?? "nil")'")

        // Auto-add new values to the Knowledge Base
        let fieldsToCheck: [(String?, KnowledgeEntry.EntryType)] = [
            (editedComic.series, .series),
            (editedComic.publisher, .publisher),
            (editedComic.writer, .writer),
            (editedComic.artist, .artist),
            (editedComic.coverArtist, .coverArtist),
            (editedComic.colorist, .colorist),
            (editedComic.inker, .inker),
            (editedComic.editor, .editor),
        ]

        for (value, type) in fieldsToCheck {
            if let name = value, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let exists = try? await DatabaseManager.shared.knowledgeEntryExists(
                    type: type, name: name)
                if exists == false {
                    let newEntry = KnowledgeEntry(type: type, name: name)
                    try? await DatabaseManager.shared.saveKnowledgeEntry(newEntry)
                    print(
                        "[ComicDetailView] ➕ Auto-added '\(name)' to \(type.pluralName) Knowledge Base"
                    )
                }
            }
        }

        // Stamp modification date
        var finalComic = editedComic
        finalComic.dateModified = Date()

        print("[ComicDetailView]    Calling onSave closure...")
        try await onSave(finalComic)
        print("[ComicDetailView]    ✅ Save completed successfully")

        // Learn from corrections if publisher or series changed
        let publisherChanged = finalComic.publisher != comic.publisher
        let seriesChanged = finalComic.series != comic.series

        if publisherChanged || seriesChanged {
            Task {
                await OrganizationLearner.shared.learnFromCorrection(
                    comic: finalComic,
                    originalPublisher: comic.publisher,
                    correctedPublisher: finalComic.publisher,
                    originalSeries: comic.series,
                    correctedSeries: finalComic.series
                )
                print("[ComicDetailView] ✅ Learned from correction")
            }
        }

        dismiss()
    }
}

// MARK: - String helper
extension String {
    /// Returns nil if the string is empty (after trimming), otherwise the trimmed value.
    fileprivate var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    ComicDetailView(comic: Comic.sample()) { _ in }
        .environmentObject(LibraryViewModel(database: DatabaseManager.shared))
}
