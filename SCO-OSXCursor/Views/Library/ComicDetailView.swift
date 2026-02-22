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

    @State private var editedComic: Comic
    @State private var originalTitle: String?
    @State private var originalPublisher: String?
    @State private var originalSeries: String?
    @State private var originalIssueNumber: String?
    @State private var originalVolume: Int?
    @State private var originalYear: Int?
    @State private var originalWriter: String?
    @State private var originalArtist: String?
    @State private var originalCoverArtist: String?
    @State private var originalColorist: String?
    @State private var originalInker: String?
    @State private var originalEditor: String?
    @State private var originalSummary: String?
    @State private var showingSaveConfirmation = false
    @State private var hasInitialized = false
    @State private var saveError: String?

    // Track focus to force commit changes before saving
    enum Field: Hashable {
        case title, publisher, series, issue, volume, year, writer, artist, coverArtist, colorist,
            inker, editor, summary
    }

    @FocusState private var focusedField: Field?

    init(comic: Comic, onSave: @escaping (Comic) async throws -> Void) {
        self.comic = comic
        self.onSave = onSave

        self._editedComic = State(initialValue: comic)
        self._originalTitle = State(initialValue: comic.title)
        self._originalPublisher = State(initialValue: comic.publisher)
        self._originalSeries = State(initialValue: comic.series)
        self._originalIssueNumber = State(initialValue: comic.issueNumber)
        self._originalVolume = State(initialValue: comic.volume)
        self._originalYear = State(initialValue: comic.year)
        self._originalWriter = State(initialValue: comic.writer)
        self._originalArtist = State(initialValue: comic.artist)
        self._originalCoverArtist = State(initialValue: comic.coverArtist)
        self._originalColorist = State(initialValue: comic.colorist)
        self._originalInker = State(initialValue: comic.inker)
        self._originalEditor = State(initialValue: comic.editor)
        self._originalSummary = State(initialValue: comic.summary)
    }

    var hasChanges: Bool {
        // Compare only against original state values (never against the live binding)
        editedComic.title != originalTitle || editedComic.publisher != originalPublisher
            || editedComic.series != originalSeries
            || editedComic.issueNumber != originalIssueNumber
            || editedComic.volume != originalVolume || editedComic.year != originalYear
            || editedComic.writer != originalWriter || editedComic.artist != originalArtist
            || editedComic.coverArtist != originalCoverArtist
            || editedComic.colorist != originalColorist
            || editedComic.inker != originalInker
            || editedComic.editor != originalEditor
            || editedComic.summary != originalSummary
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
                Text(editedComic.displayTitle)
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

    // MARK: - Metadata Fields

    private var metadataFields: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Core Metadata Section
            metadataSection(title: "Core Information", icon: "info.circle") {
                metadataField(
                    label: "Series", text: $editedComic.series, field: .series,
                    knowledgeType: .series)
                metadataField(
                    label: "Publisher", text: $editedComic.publisher, field: .publisher,
                    isPublisher: true, knowledgeType: .publisher)
                metadataField(label: "Storyline Title", text: $editedComic.title, field: .title)
                metadataField(label: "Issue Number", text: $editedComic.issueNumber, field: .issue)

                HStack {
                    metadataField(
                        label: "Volume",
                        value: Binding(
                            get: { editedComic.volume.map { String($0) } ?? "" },
                            set: { editedComic.volume = Int($0) }
                        ),
                        field: .volume
                    )

                    metadataField(
                        label: "Year",
                        value: Binding(
                            get: { editedComic.year.map { String($0) } ?? "" },
                            set: { editedComic.year = Int($0) }
                        ),
                        field: .year
                    )
                }
            }

            // Credits Section
            metadataSection(title: "Credits", icon: "person.2.fill") {
                metadataField(
                    label: "Writer", text: $editedComic.writer, field: .writer,
                    knowledgeType: .writer)
                metadataField(
                    label: "Artist", text: $editedComic.artist, field: .artist,
                    knowledgeType: .artist)
                metadataField(
                    label: "Cover Artist", text: $editedComic.coverArtist, field: .coverArtist,
                    knowledgeType: .coverArtist)
                metadataField(
                    label: "Colorist", text: $editedComic.colorist, field: .colorist,
                    knowledgeType: .colorist)
                metadataField(
                    label: "Inker", text: $editedComic.inker, field: .inker, knowledgeType: .inker)
                metadataField(
                    label: "Editor", text: $editedComic.editor, field: .editor,
                    knowledgeType: .editor)
            }

            // Summary Section
            metadataSection(title: "Summary", icon: "text.alignleft") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Summary")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)

                    TextEditor(
                        text: Binding(
                            get: { editedComic.summary ?? "" },
                            set: { editedComic.summary = $0.isEmpty ? nil : $0 }
                        )
                    )
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

    // MARK: - Metadata Field

    private func metadataField(
        label: String, text: Binding<String?>, field: Field, isPublisher: Bool = false,
        knowledgeType: KnowledgeEntry.EntryType? = nil
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)

            if let knowledgeType = knowledgeType {
                AutocompleteTextField(
                    title: label,
                    text: Binding(
                        get: { text.wrappedValue ?? "" },
                        set: { text.wrappedValue = $0.isEmpty ? nil : $0 }
                    ),
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
                TextField(
                    label,
                    text: Binding(
                        get: { text.wrappedValue ?? "" },
                        set: { text.wrappedValue = $0.isEmpty ? nil : $0 }
                    )
                )
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

            // Show publisher color indicator if publisher field
            if isPublisher, let publisher = text.wrappedValue, !publisher.isEmpty {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(PublisherDetector.color(for: publisher))
                        .frame(width: 8, height: 8)
                    Text("Normalized: \(PublisherDetector.normalize(publisher) ?? publisher)")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private func metadataField(label: String, value: Binding<String>, field: Field) -> some View {
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
            // Force focus to clear to ensure all bindings update before saving
            focusedField = nil

            Task {
                // Wait a split second for the runloop to process the focus change
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s

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
            .background(AccentColors.primary)  // Always bold/active
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        // .disabled(!hasChanges) // Disabled check removed to allow forced saves
    }

    // MARK: - Actions

    private func saveChanges() async throws {
        print("[ComicDetailView] 💾 Saving changes...")
        print("[ComicDetailView]    Title: '\(editedComic.title ?? "nil")'")
        print("[ComicDetailView]    Publisher: '\(editedComic.publisher ?? "nil")'")
        print("[ComicDetailView]    Series: '\(editedComic.series ?? "nil")'")

        // Check if publisher or series was corrected
        let publisherChanged = editedComic.publisher != originalPublisher
        let seriesChanged = editedComic.series != originalSeries

        // Handle Auto-Add to Knowledge Base
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
                // Check if it exists, if not, add it
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

        // Create final version with updated dateModified
        var finalComic = editedComic
        finalComic.dateModified = Date()

        // Update the binding (which updates the viewModel's array)
        print("[ComicDetailView]    Calling onSave closure...")
        try await onSave(finalComic)
        print("[ComicDetailView]    ✅ Save completed successfully")

        // Learn from correction if publisher or series changed
        if publisherChanged || seriesChanged {
            Task {
                await OrganizationLearner.shared.learnFromCorrection(
                    comic: finalComic,
                    originalPublisher: originalPublisher,
                    correctedPublisher: editedComic.publisher,
                    originalSeries: originalSeries,
                    correctedSeries: editedComic.series
                )
                print("[ComicDetailView] ✅ Learned from correction")
            }
        }

        dismiss()
    }
}

#Preview {
    ComicDetailView(comic: Comic.sample()) { _ in }
        .environmentObject(LibraryViewModel(database: DatabaseManager.shared))
}
