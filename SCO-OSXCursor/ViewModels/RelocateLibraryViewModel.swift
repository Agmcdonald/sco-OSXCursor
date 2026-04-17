//
//  RelocateLibraryViewModel.swift
//  SCO-OSXCursor
//
//  Created for Milestone 0: Home Library & Automatic File Sorting
//

import Combine
import Foundation
import SwiftUI

// MARK: - RelocateLibraryViewModel

/// Drives the Relocate Library sheet.
///
/// This tool handles drive migrations — when the entire library folder has been
/// moved to a new location and every DB path record must have its prefix swapped.
///
/// **No physical file operations are performed.** The files must already exist
/// at the new location. This ViewModel only rewrites database records.
@MainActor
final class RelocateLibraryViewModel: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle       // Waiting for new root selection
        case preview    // Showing before/after table
        case running    // Executing the remap
        case done       // Completed
    }

    // MARK: - Path Preview

    struct PathPreview: Identifiable {
        let id: UUID
        let comic: Comic
        let oldRelativePath: String
        let newAbsolutePath: String
        /// Whether the file actually exists at the new location.
        let existsAtNewPath: Bool
    }

    struct RemapError: Identifiable {
        let id = UUID()
        let comicName: String
        let reason: String
    }

    // MARK: - Published State

    @Published var phase: Phase = .idle
    @Published var newRootURL: URL? = nil
    @Published var previews: [PathPreview] = []
    @Published var progress: Double = 0
    @Published var remappedCount: Int = 0
    @Published var notFoundCount: Int = 0
    @Published var skippedCount: Int = 0   // comics not under old root
    @Published var errors: [RemapError] = []
    @Published var showingFolderPicker = false

    // MARK: - Computed

    var affectedPreviews: [PathPreview]    { previews.filter {  $0.existsAtNewPath } }
    var missingPreviews:  [PathPreview]    { previews.filter { !$0.existsAtNewPath } }
    var totalToRemap:     Int              { affectedPreviews.count }

    // MARK: - Build Preview

    /// Computes where each comic's file *would* be under `newRoot`
    /// and whether it actually exists there on disk.
    func buildPreview(oldRoot: URL, newRoot: URL, comics: [Comic]) {
        phase = .preview
        previews = []

        let fm = FileManager.default
        let oldPath = oldRoot.standardizedFileURL.path
        let newPath = newRoot.standardizedFileURL.path

        var result: [PathPreview] = []

        for comic in comics {
            let comicPath = comic.filePath.standardizedFileURL.path

            // Only include comics whose path starts with the old root
            guard comicPath.hasPrefix(oldPath) else {
                skippedCount += 1
                continue
            }

            // Compute new absolute path by swapping the prefix
            let relative      = String(comicPath.dropFirst(oldPath.count))
            let relativeClean = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
            let newAbsolute   = "\(newPath)/\(relativeClean)"
            let newURL        = URL(fileURLWithPath: newAbsolute)

            let exists = fm.fileExists(atPath: newURL.path)

            result.append(PathPreview(
                id: comic.id,
                comic: comic,
                oldRelativePath: relativeClean,
                newAbsolutePath: newAbsolute,
                existsAtNewPath: exists
            ))
        }

        // Sort: exists-at-new-path first, then missing
        previews = result.sorted {
            if $0.existsAtNewPath != $1.existsAtNewPath { return $0.existsAtNewPath }
            return $0.comic.displayName < $1.comic.displayName
        }
    }

    // MARK: - Execute Remap

    /// Rewrites DB path records for all affected comics and updates Settings.
    ///
    /// Only comics whose file physically exists at the new path are remapped.
    /// Comics that don't exist at the new path are flagged `needsAttention`.
    func executeRemap(
        oldRoot: URL,
        newRoot: URL,
        settingsViewModel: SettingsViewModel,
        database: DatabaseManager
    ) async {
        phase = .running
        progress = 0
        remappedCount = 0
        notFoundCount = 0
        errors = []

        let fm = FileManager.default
        let total = Double(previews.count)
        guard total > 0 else {
            // Nothing to do — just update Settings with the new root
            settingsViewModel.setHomeLibraryFolder(newRoot)
            phase = .done
            return
        }

        for (i, preview) in previews.enumerated() {
            let newURL = URL(fileURLWithPath: preview.newAbsolutePath)

            if !preview.existsAtNewPath {
                // File not at new location — flag it
                var flagged = preview.comic
                flagged.needsAttention = true
                try? await database.updateComic(flagged)
                notFoundCount += 1
            } else {
                // Refresh security-scoped bookmark for the new path
                var updated = preview.comic
                updated.filePath = newURL
                updated.fileName = newURL.lastPathComponent
                updated.needsAttention = false

                #if os(macOS)
                updated.bookmarkData = try? newURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                #else
                updated.bookmarkData = try? newURL.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                #endif

                do {
                    try await database.updateComic(updated)
                    remappedCount += 1
                    print("[RelocateLibraryViewModel] ✅ Remapped: \(preview.comic.fileName)")
                } catch {
                    notFoundCount += 1
                    errors.append(RemapError(
                        comicName: preview.comic.displayName,
                        reason: error.localizedDescription
                    ))
                    print("[RelocateLibraryViewModel] ❌ Failed to remap \(preview.comic.fileName): \(error)")
                }
            }

            progress = Double(i + 1) / total
        }

        // Update Settings to point at the new root
        settingsViewModel.setHomeLibraryFolder(newRoot)

        print("[RelocateLibraryViewModel] ✅ Remap complete — \(remappedCount) remapped, \(notFoundCount) not found")
        phase = .done
    }

    // MARK: - Reset

    func reset() {
        phase = .idle
        newRootURL = nil
        previews = []
        progress = 0
        remappedCount = 0
        notFoundCount = 0
        skippedCount = 0
        errors = []
    }
}
