//
//  OrganizeViewModel.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 2/15/26.
//

import Combine
import Foundation
import SwiftUI

/// ViewModel for the Organize (Staging) workflow.
/// Manages temporary `StagedComic` objects before they are committed to the Library.
@MainActor
final class OrganizeViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var stagedComics: [StagedComic] = []
    @Published var selectedComicID: UUID?
    @Published var checkedComicIDs: Set<UUID> = []

    // Processing State
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0.0

    // Dependencies
    private let libraryViewModel: LibraryViewModel

    init(libraryViewModel: LibraryViewModel) {
        self.libraryViewModel = libraryViewModel
    }

    // MARK: - Computed Properties

    var selectedComic: StagedComic? {
        guard let id = selectedComicID else { return nil }
        return stagedComics.first(where: { $0.id == id })
    }

    // MARK: - File Actions

    /// Add files to the staging area from URLs (e.g. Drag & Drop or Open Panel)
    func addFiles(_ urls: [URL]) async {
        isProcessing = true
        processingProgress = 0.0

        var newComics: [StagedComic] = []
        let validExtensions = ["cbz", "cbr", "pdf"]

        for (index, url) in urls.enumerated() {
            // Filter by extension
            let ext = url.pathExtension.lowercased()
            if validExtensions.contains(ext) {
                // Create StagedComic (automatically parses metadata on init)
                let comic = StagedComic(url: url)
                newComics.append(comic)
            }

            // Update progress
            processingProgress = Double(index + 1) / Double(urls.count)
        }

        // Append to list
        stagedComics.append(contentsOf: newComics)

        // Auto-select first new item if nothing selected
        if selectedComicID == nil, let first = newComics.first {
            selectedComicID = first.id
        }

        isProcessing = false
        print("[OrganizeViewModel] Added \(newComics.count) files to staging.")
    }

    // MARK: - Selection Actions

    func toggleCheck(for comicID: UUID) {
        if checkedComicIDs.contains(comicID) {
            checkedComicIDs.remove(comicID)
        } else {
            checkedComicIDs.insert(comicID)
        }
    }

    // MARK: - Metadata Updates

    /// Update metadata for a staged comic
    func updateMetadata(
        id: UUID, series: String, issue: String, year: Int, publisher: String, volume: Int?,
        title: String?, writer: String?, artist: String?, coverArtist: String?, colorist: String?,
        inker: String?, editor: String?, summary: String?
    ) {
        guard let index = stagedComics.firstIndex(where: { $0.id == id }) else { return }

        var comic = stagedComics[index]
        comic.series = series
        comic.issueNumber = issue
        comic.year = year
        comic.publisher = publisher
        comic.volume = volume
        comic.title = title
        comic.writer = writer
        comic.artist = artist
        comic.coverArtist = coverArtist
        comic.colorist = colorist
        comic.inker = inker
        comic.editor = editor
        comic.summary = summary

        // Re-evaluate status
        if !series.isEmpty && !issue.isEmpty {
            comic.status = .ready
        }

        stagedComics[index] = comic
    }

    // MARK: - Confirm / Commit

    /// Confirm match for a single staged comic: Rename file & Add to Library
    /// Note: We look up the CURRENT comic from stagedComics (not the passed-in parameter)
    /// because StagedComic is a struct — the parameter may be a stale copy from view init.
    func confirmMatch(_ comic: StagedComic) async {
        guard let index = stagedComics.firstIndex(where: { $0.id == comic.id }) else { return }

        // Use the CURRENT version from the array (reflects user edits via updateMetadata)
        let current = stagedComics[index]
        let originalURL = current.originalURL
        var finalURL = originalURL

        // 1. Rename file on disk to match the confirmed metadata
        let newFileName = current.proposedFileName
        if newFileName != originalURL.lastPathComponent {
            let newURL = originalURL.deletingLastPathComponent().appendingPathComponent(newFileName)

            // Security-scoped access for rename (balanced start/stop)
            let accessingSource = originalURL.startAccessingSecurityScopedResource()
            let destFolderURL = newURL.deletingLastPathComponent()
            let accessingDest = destFolderURL.startAccessingSecurityScopedResource()

            defer {
                if accessingSource { originalURL.stopAccessingSecurityScopedResource() }
                if accessingDest { destFolderURL.stopAccessingSecurityScopedResource() }
            }

            do {
                if !FileManager.default.fileExists(atPath: newURL.path) {
                    try FileManager.default.moveItem(at: originalURL, to: newURL)
                    finalURL = newURL
                    print(
                        "[OrganizeViewModel] 📝 Renamed staged file: \(originalURL.lastPathComponent) → \(newFileName)"
                    )
                } else {
                    print(
                        "[OrganizeViewModel] ⚠️ Target file exists, skipping rename: \(newFileName)")
                }
            } catch {
                print("[OrganizeViewModel] ❌ Rename failed: \(error)")
            }
        }

        // 2. Import into Library using staged metadata directly
        //    This preserves the user-entered publisher/series and uses the
        //    original URL's security scope for file access.
        await libraryViewModel.importStagedComic(
            series: current.series,
            issueNumber: current.issueNumber,
            volume: current.volume,
            year: current.year,
            publisher: current.publisher,
            title: current.title,
            writer: current.writer,
            artist: current.artist,
            coverArtist: current.coverArtist,
            colorist: current.colorist,
            inker: current.inker,
            editor: current.editor,
            summary: current.summary,
            originalURL: originalURL,
            fileURL: finalURL
        )

        // 3. Remove from staging
        if let idx = stagedComics.firstIndex(where: { $0.id == current.id }) {
            stagedComics.remove(at: idx)
        }

        // 4. Select next available
        if let next = stagedComics.first {
            selectedComicID = next.id
        } else {
            selectedComicID = nil
        }
    }

    /// Confirm all comics with "Ready" status at once
    func confirmAllReady() async {
        let readyComics = stagedComics.filter { $0.status == .ready }
        for comic in readyComics {
            await confirmMatch(comic)
        }
    }
}
