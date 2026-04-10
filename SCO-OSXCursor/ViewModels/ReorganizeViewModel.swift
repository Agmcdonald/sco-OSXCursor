//
//  ReorganizeViewModel.swift
//  SCO-OSXCursor
//
//  Created for Milestone 0: Home Library & Automatic File Sorting
//

import Combine
import Foundation
import SwiftUI

// MARK: - ReorganizeViewModel

@MainActor
final class ReorganizeViewModel: ObservableObject {

    // MARK: - Phase

    enum Phase {
        case preview    // building preview table
        case ready      // preview complete, awaiting user confirmation
        case running    // executing moves
        case done       // all moves attempted
    }

    // MARK: - Move Preview

    struct MovePreview: Identifiable {
        let id: UUID
        let comic: Comic
        let currentPath: String
        let destinationPath: String
        let alreadyInPlace: Bool
    }

    struct MoveError: Identifiable {
        let id = UUID()
        let comicName: String
        let reason: String
    }

    // MARK: - Published State

    @Published var phase: Phase = .preview
    @Published var moves: [MovePreview] = []
    @Published var progress: Double = 0
    @Published var completedCount: Int = 0
    @Published var failedCount: Int = 0
    @Published var errors: [MoveError] = []
    @Published var isLoadingPreview: Bool = false

    // MARK: - Computed

    var movesNeeded: [MovePreview] { moves.filter { !$0.alreadyInPlace } }
    var alreadyInPlace: [MovePreview] { moves.filter { $0.alreadyInPlace } }

    // MARK: - Build Preview

    /// Computes where each comic *should* live and compares to where it currently is.
    /// Populates `moves` and transitions to `.ready`.
    func buildPreview(comics: [Comic], libraryRoot: URL) async {
        isLoadingPreview = true
        phase = .preview

        let relocator = LibraryRelocator.shared
        var result: [MovePreview] = []

        for comic in comics {
            let destination = relocator.previewDestination(for: comic, libraryRoot: libraryRoot)
            let alreadyThere = comic.filePath.standardizedFileURL == destination.standardizedFileURL

            result.append(MovePreview(
                id: comic.id,
                comic: comic,
                currentPath: relativePath(of: comic.filePath, from: libraryRoot),
                destinationPath: relativePath(of: destination, from: libraryRoot),
                alreadyInPlace: alreadyThere
            ))
        }

        // Sort: needs-move first, then alphabetically
        moves = result.sorted {
            if $0.alreadyInPlace != $1.alreadyInPlace { return !$0.alreadyInPlace }
            return $0.comic.displayName < $1.comic.displayName
        }

        isLoadingPreview = false
        phase = .ready
    }

    // MARK: - Execute

    /// Performs all pending moves sequentially, updating progress as it goes.
    func executeReorganize(libraryRoot: URL, database: DatabaseManager) async {
        phase = .running
        progress = 0
        completedCount = 0
        failedCount = 0
        errors = []

        let pending = movesNeeded
        let total = Double(pending.count)
        guard total > 0 else {
            phase = .done
            return
        }

        let service = LibraryFileService.shared

        for (i, preview) in pending.enumerated() {
            do {
                _ = try await service.moveToLibrary(
                    preview.comic,
                    libraryRoot: libraryRoot,
                    database: database
                )
                completedCount += 1
            } catch {
                failedCount += 1
                errors.append(MoveError(
                    comicName: preview.comic.displayName,
                    reason: error.localizedDescription
                ))
            }

            progress = Double(i + 1) / total
        }

        phase = .done
    }

    // MARK: - Helpers

    private func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let urlPath  = url.standardizedFileURL.path
        if urlPath.hasPrefix(rootPath) {
            return String(urlPath.dropFirst(rootPath.count + 1))
        }
        return url.path
    }
}
