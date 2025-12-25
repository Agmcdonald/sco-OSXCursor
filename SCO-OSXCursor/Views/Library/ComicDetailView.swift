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
    @Binding var comic: Comic
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var libraryViewModel: LibraryViewModel
    
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
    @State private var originalSummary: String?
    @State private var showingSaveConfirmation = false
    @State private var hasInitialized = false
    @State private var saveError: String?
    
    init(comic: Binding<Comic>) {
        self._comic = comic
        let initialComic = comic.wrappedValue
        self._editedComic = State(initialValue: initialComic)
        self._originalTitle = State(initialValue: initialComic.title)
        self._originalPublisher = State(initialValue: initialComic.publisher)
        self._originalSeries = State(initialValue: initialComic.series)
        self._originalIssueNumber = State(initialValue: initialComic.issueNumber)
        self._originalVolume = State(initialValue: initialComic.volume)
        self._originalYear = State(initialValue: initialComic.year)
        self._originalWriter = State(initialValue: initialComic.writer)
        self._originalArtist = State(initialValue: initialComic.artist)
        self._originalCoverArtist = State(initialValue: initialComic.coverArtist)
        self._originalSummary = State(initialValue: initialComic.summary)
    }
    
    // Initialize originals from binding when comic ID changes (for sheet reuse)
    private func initializeFromBinding() {
        let bindingComic = comic  // @Binding property is already unwrapped
        editedComic = bindingComic
        originalTitle = bindingComic.title
        originalPublisher = bindingComic.publisher
        originalSeries = bindingComic.series
        originalIssueNumber = bindingComic.issueNumber
        originalVolume = bindingComic.volume
        originalYear = bindingComic.year
        originalWriter = bindingComic.writer
        originalArtist = bindingComic.artist
        originalCoverArtist = bindingComic.coverArtist
        originalSummary = bindingComic.summary
        hasInitialized = true
    }
    
    var hasChanges: Bool {
        // Compare only against original state values (never against the live binding)
        editedComic.title != originalTitle ||
        editedComic.publisher != originalPublisher ||
        editedComic.series != originalSeries ||
        editedComic.issueNumber != originalIssueNumber ||
        editedComic.volume != originalVolume ||
        editedComic.year != originalYear ||
        editedComic.writer != originalWriter ||
        editedComic.artist != originalArtist ||
        editedComic.coverArtist != originalCoverArtist ||
        editedComic.summary != originalSummary
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onChange(of: comic.id) { oldID, newID in
            // If the comic ID changes (different comic selected), reinitialize
            print("[ComicDetailView] 🔄 Comic ID changed from \(oldID) to \(newID) - reinitializing")
            hasInitialized = false
            initializeFromBinding()
        }
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
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
                
                Text(editedComic.fileName)
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
                metadataField(label: "Title", text: $editedComic.title)
                metadataField(label: "Publisher", text: $editedComic.publisher, isPublisher: true)
                metadataField(label: "Series", text: $editedComic.series)
                metadataField(label: "Issue Number", text: $editedComic.issueNumber)
                
                HStack {
                    metadataField(label: "Volume", value: Binding(
                        get: { editedComic.volume.map { String($0) } ?? "" },
                        set: { editedComic.volume = Int($0) }
                    ))
                    
                    metadataField(label: "Year", value: Binding(
                        get: { editedComic.year.map { String($0) } ?? "" },
                        set: { editedComic.year = Int($0) }
                    ))
                }
            }
            
            // Credits Section
            metadataSection(title: "Credits", icon: "person.2.fill") {
                metadataField(label: "Writer", text: $editedComic.writer)
                metadataField(label: "Artist", text: $editedComic.artist)
                metadataField(label: "Cover Artist", text: $editedComic.coverArtist)
            }
            
            // Summary Section
            metadataSection(title: "Summary", icon: "text.alignleft") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Summary")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                    
                    TextEditor(text: Binding(
                        get: { editedComic.summary ?? "" },
                        set: { editedComic.summary = $0.isEmpty ? nil : $0 }
                    ))
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
    
    private func metadataField(label: String, text: Binding<String?>, isPublisher: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
            
            TextField(label, text: Binding(
                get: { text.wrappedValue ?? "" },
                set: { text.wrappedValue = $0.isEmpty ? nil : $0 }
            ))
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
    
    private func metadataField(label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
            
            TextField(label, text: value)
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
            Task {
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
            .background(hasChanges ? AccentColors.primary : AccentColors.primary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!hasChanges)
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
        
        // Create final version with updated dateModified
        var finalComic = editedComic
        finalComic.dateModified = Date()
        
        // Update the binding (which updates the viewModel's array)
        print("[ComicDetailView]    Updating binding...")
        comic = finalComic
        
        // Persist to database via viewModel (DB-only, array already updated by binding)
        print("[ComicDetailView]    Calling viewModel.persistComic()...")
        try await libraryViewModel.persistComic(finalComic)
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
    ComicDetailView(comic: .constant(Comic.sample()))
        .environmentObject(LibraryViewModel(database: DatabaseManager.shared))
}

