//
//  LibraryRelocator.swift
//  SCO-OSXCursor
//
//  Created for Milestone 0: Home Library & Automatic File Sorting
//

import Foundation
import os

// MARK: - LibraryRelocator

/// Watches for comic metadata changes and triggers a file move whenever
/// the publisher or series title changes — keeping the on-disk organisation
/// in sync with the library's canonical folder hierarchy.
///
/// Called by `LibraryViewModel.updateComic` when a diff is detected.
final class LibraryRelocator {

    static let shared = LibraryRelocator()
    private init() {}

    // MARK: - Metadata Change Handler

    /// Compare `old` and `new`; if the publisher or series changed, move the file
    /// to the new canonical location inside `libraryRoot`.
    ///
    /// - On **success**: returns the updated comic with the new path.
    /// - On **failure**: returns `new` with `needsAttention = true` (file untouched).
    @discardableResult
    func handleMetadataChange(
        old: Comic,
        new: Comic,
        libraryRoot: URL,
        database: DatabaseManager
    ) async -> Comic {
        // Only react when publisher or series actually changed
        let publisherChanged = old.publisher != new.publisher
        let seriesChanged = old.series != new.series

        guard publisherChanged || seriesChanged else {
            return new
        }

        // Compute where the file should go under the new metadata
        let service = LibraryFileService.shared
        let settings = AppSettings.load()
        let newDestination = service.destinationURL(for: new, in: libraryRoot, folderStructure: settings.folderStructure)

        // If the file is already at the correct destination, nothing to do
        if new.filePath.standardizedFileURL == newDestination.standardizedFileURL {
            return new
        }

        // Attempt the move
        do {
            let movedComic = try await service.moveToLibrary(new, libraryRoot: libraryRoot, database: database)

            // Log success
            await database.logActivity(
                ActivityEvent(
                    comicId: movedComic.id.uuidString,
                    action: .fileMoved,
                    oldValue: old.filePath.path,
                    newValue: movedComic.filePath.path
                )
            )

            AppLog.files.info("[LibraryRelocator] ✅ Relocated \(movedComic.fileName) after metadata change")
            return movedComic

        } catch {
            // Move failed — flag the comic so the user can act manually
            var flagged = new
            flagged.needsAttention = true
            try? await database.updateComic(flagged)

            // Log failure
            await database.logActivity(
                ActivityEvent(
                    comicId: new.id.uuidString,
                    action: .fileMoveFailed,
                    oldValue: new.filePath.path,
                    newValue: "Move failed: \(error.localizedDescription)"
                )
            )

            AppLog.files.error("[LibraryRelocator] ❌ Move failed for \(new.fileName): \(error)")
            return flagged
        }
    }

    // MARK: - Destination Preview

    /// Returns the would-be destination path string for a given comic + library root,
    /// used by `ReorganizeViewModel` to build the preview table.
    func previewDestination(for comic: Comic, libraryRoot: URL) -> URL {
        let settings = AppSettings.load()
        return LibraryFileService.shared.destinationURL(
            for: comic,
            in: libraryRoot,
            folderStructure: settings.folderStructure
        )
    }
}
