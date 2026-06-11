//
//  LibraryFileService.swift
//  SCO-OSXCursor
//
//  Created for Milestone 0: Home Library & Automatic File Sorting
//

import Foundation
import os

// MARK: - LibraryFileService

/// Handles the physical movement of comic files into the canonical home library
/// folder hierarchy and keeps database records in sync.
///
/// **Safety contract**: Every operation either fully succeeds (file at new path,
/// DB updated) or fully rolls back (file untouched, DB unchanged).
/// Files are **never** deleted by any code path in this service.
final class LibraryFileService {

    static let shared = LibraryFileService()
    private init() {}

    // MARK: - Destination URL

    /// Computes the canonical destination URL for a comic inside the given library root,
    /// honouring the current `folderStructure` setting.
    ///
    /// - Parameters:
    ///   - comic: The comic whose metadata determines the path.
    ///   - libraryRoot: The root directory of the home library.
    ///   - folderStructure: The folder-hierarchy convention to apply.
    /// - Returns: The full URL where the comic file *should* live.
    func destinationURL(
        for comic: Comic,
        in libraryRoot: URL,
        folderStructure: AppSettings.FolderStructure = AppSettings.load().folderStructure
    ) -> URL {
        let publisher = sanitizeFolderName(comic.publisher ?? "Unknown Publisher")
            .nonEmpty ?? "Unknown Publisher"
        let series = sanitizeFolderName(comic.series ?? comic.displayName)
            .nonEmpty ?? "Unsorted"
        // Use cleaned filename (mirrors StagedComic.proposedFileName format)
        // This ensures the rename always happens as part of the library sort move,
        // even when the staging rename failed (e.g. iCloud source directories).
        let fileName = cleanedFileName(for: comic)

        switch folderStructure {
        case .publisherSeriesIssue, .publisherSeries:
            return libraryRoot
                .appendingPathComponent(publisher, isDirectory: true)
                .appendingPathComponent(series, isDirectory: true)
                .appendingPathComponent(fileName)

        case .seriesIssue:
            return libraryRoot
                .appendingPathComponent(series, isDirectory: true)
                .appendingPathComponent(fileName)

        case .flat:
            return libraryRoot.appendingPathComponent(fileName)

        case .yearPublisherSeries:
            let yearStr = comic.year.map { String($0) } ?? "Unknown Year"
            return libraryRoot
                .appendingPathComponent(sanitizeFolderName(yearStr).nonEmpty ?? yearStr, isDirectory: true)
                .appendingPathComponent(publisher, isDirectory: true)
                .appendingPathComponent(series, isDirectory: true)
                .appendingPathComponent(fileName)

        case .custom:
            // Fall back to publisher/series for the custom case; custom naming
            // applies to file names, not the folder hierarchy.
            return libraryRoot
                .appendingPathComponent(publisher, isDirectory: true)
                .appendingPathComponent(series, isDirectory: true)
                .appendingPathComponent(fileName)
        }
    }

    // MARK: - Move to Library

    /// Atomically moves `comic.filePath` → `destinationURL`, creates intermediate
    /// directories, refreshes the security-scoped bookmark, updates the DB record,
    /// and cleans up any now-empty source parent folders.
    ///
    /// On *any* failure the file is untouched and the DB is not updated.
    ///
    /// - Returns: Updated `Comic` with new `filePath` and `bookmarkData`.\
    @discardableResult
    func moveToLibrary(
        _ comic: Comic,
        libraryRoot: URL,
        database: DatabaseManager
    ) async throws -> Comic {
        let fm = FileManager.default
        let source = comic.filePath
        let settings = AppSettings.load()

        // ── Start security-scoped access for the library root ──
        // The library root was chosen via NSOpenPanel / fileImporter and stored as a
        // security-scoped bookmark. We MUST call startAccessingSecurityScopedResource()
        // before any file-system operations, otherwise the sandbox blocks them.
        let libraryAccessing = libraryRoot.startAccessingSecurityScopedResource()
        defer {
            if libraryAccessing {
                libraryRoot.stopAccessingSecurityScopedResource()
            }
        }

        // ── Optionally start access on the source file using its bookmark ──
        // This is needed when the source lives outside the library (e.g. iCloud, Downloads)
        // and only has file-level (not directory-level) sandbox access.
        var sourceBookmarkURL: URL? = nil
        if let bookmarkData = comic.bookmarkData {
            var stale = false
            #if os(macOS)
            sourceBookmarkURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            #else
            sourceBookmarkURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            #endif
        }
        let sourceAccessing = sourceBookmarkURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if sourceAccessing { sourceBookmarkURL?.stopAccessingSecurityScopedResource() }
        }

        // Compute destination, then resolve any name conflict
        var destination = destinationURL(for: comic, in: libraryRoot, folderStructure: settings.folderStructure)

        // If the file is already in the right place, skip the move
        if source.standardizedFileURL == destination.standardizedFileURL {
            AppLog.files.info("[LibraryFileService] ✅ Already in place: \(comic.fileName)")
            return comic
        }

        // Resolve conflict: never overwrite an existing file
        destination = resolveConflict(at: destination)

        // Create intermediate directories (requires library root security access)
        let destFolder = destination.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: destFolder, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw LibraryFileError.cannotCreateDirectory(destFolder, underlying: error)
        }

        // Perform the move (atomic on same volume; copy+verify+delete cross-volume)
        if isCrossVolume(from: source, to: destination) {
            try crossVolumeMove(from: source, to: destination)
        } else {
            try fm.moveItem(at: source, to: destination)
        }

        // Refresh security-scoped bookmark for the new location (read-write)
        let newBookmark = makeBookmark(for: destination)

        // Build updated comic
        var updated = comic
        updated.filePath = destination
        updated.fileName = destination.lastPathComponent
        updated.bookmarkData = newBookmark
        updated.needsAttention = false
        updated.dateModified = Date()

        // Persist to DB ONLY after successful move
        try await database.updateComic(updated)

        // Clean up empty source parent folders (stops at libraryRoot)
        removeEmptyFolders(from: source.deletingLastPathComponent(), stoppingAt: libraryRoot)

        let relative = relativeDescription(of: destination, relativeTo: libraryRoot)
        AppLog.files.info("[LibraryFileService] ✅ Moved \(comic.fileName) → \(relative)")

        return updated
    }

    // MARK: - Clean Filename Generation

    /// Generates a clean, canonical filename for a comic using the same convention as
    /// the staging area's `proposedFileName` — `{Series} [V{vol}] [#{issue}] [({year})].{ext}`.
    ///
    /// Falls back to the original `comic.fileName` if there isn't enough metadata to
    /// build a meaningful name (e.g. series is empty).
    func cleanedFileName(for comic: Comic) -> String {
        let ext = (comic.fileName as NSString).pathExtension

        // Need at minimum a series name
        guard let rawSeries = comic.series, !rawSeries.trimmingCharacters(in: .whitespaces).isEmpty else {
            return comic.fileName
        }

        var parts: [String] = [rawSeries]

        if let vol = comic.volume {
            parts.append("V\(vol)")
        }

        if let issue = comic.issueNumber, !issue.isEmpty {
            parts.append("#\(issue)")
        }

        if let year = comic.year {
            parts.append("(\(year))")
        }

        let base = parts.joined(separator: " ")
        // Sanitize the full base (handles any leftover illegal characters in metadata)
        let sanitized = sanitizeFolderName(base).nonEmpty ?? base
        return ext.isEmpty ? sanitized : "\(sanitized).\(ext)"
    }

    // MARK: - Folder Name Sanitization

    /// Strips characters that are illegal in HFS+/APFS folder names,
    /// collapses whitespace, and truncates to 255 bytes.
    func sanitizeFolderName(_ name: String) -> String {
        // Characters illegal on macOS
        let illegal = CharacterSet(charactersIn: "/:\\*?\"<>|")
        var result = name
            .components(separatedBy: illegal)
            .joined(separator: " ")

        // Collapse multiple whitespace into single space
        let whitespaceRegex = try? NSRegularExpression(pattern: "\\s+")
        result = whitespaceRegex?.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: " "
        ) ?? result

        // Trim leading/trailing whitespace and dots
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Truncate to 255 UTF-8 bytes (HFS+ limit per component)
        if let data = result.data(using: .utf8), data.count > 255 {
            var truncated = data.prefix(255)
            // Step back until we have valid UTF-8
            while String(data: truncated, encoding: .utf8) == nil {
                truncated = truncated.dropLast()
            }
            result = String(data: truncated, encoding: .utf8) ?? result
        }

        return result
    }

    // MARK: - Conflict Resolution

    /// If a file already exists at `url`, appends " (2)", " (3)", etc. until a
    /// free slot is found. **Never overwrites or deletes the existing file.**
    func resolveConflict(at url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }

        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent

        var counter = 2
        while counter < 1000 {
            let candidate: URL
            if ext.isEmpty {
                candidate = dir.appendingPathComponent("\(base) (\(counter))")
            } else {
                candidate = dir.appendingPathComponent("\(base) (\(counter)).\(ext)")
            }
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
        // Extreme fallback: UUID suffix
        let uuid = UUID().uuidString.prefix(8)
        if ext.isEmpty {
            return dir.appendingPathComponent("\(base) \(uuid)")
        }
        return dir.appendingPathComponent("\(base) \(uuid).\(ext)")
    }

    // MARK: - Empty Folder Cleanup

    /// Recursively removes `url` and its ancestors if they are empty,
    /// stopping before (and never touching) `root`.
    func removeEmptyFolders(from url: URL, stoppingAt root: URL) {
        let fm = FileManager.default
        var current = url.standardizedFileURL
        let stop = root.standardizedFileURL

        while current != stop && current.path.hasPrefix(stop.path) {
            guard let contents = try? fm.contentsOfDirectory(atPath: current.path),
                  contents.filter({ !$0.hasPrefix(".") }).isEmpty else {
                break  // Not empty; stop climbing
            }
            do {
                try fm.removeItem(at: current)
                AppLog.files.debug("[LibraryFileService] 🗑️ Removed empty folder: \(current.lastPathComponent)")
            } catch {
                AppLog.files.error("[LibraryFileService] ⚠️ Could not remove folder \(current.lastPathComponent): \(error)")
                break
            }
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }

    // MARK: - Private Helpers

    private func makeBookmark(for url: URL) -> Data? {
        #if os(macOS)
        // Read-write bookmark — the app needs to read AND re-sort moved files
        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    private func isCrossVolume(from source: URL, to destination: URL) -> Bool {
        // Compare volume identifiers to detect cross-volume moves
        let srcVol = try? source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        // Destination may not exist yet; walk up to first existing ancestor
        var ancestor = destination.deletingLastPathComponent()
        let fm = FileManager.default
        while !ancestor.path.isEmpty && !fm.fileExists(atPath: ancestor.path) {
            let parent = ancestor.deletingLastPathComponent()
            if parent.path == ancestor.path { break }
            ancestor = parent
        }
        let dstVol = try? ancestor.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        // If we can't tell, assume same volume (safer—moveItem will fail if wrong)
        guard let s = srcVol, let d = dstVol else { return false }
        return !s.isEqual(d)
    }

    /// Copy → verify → delete for cross-volume moves.
    /// If any step fails the delete is skipped so the source is always preserved.
    private func crossVolumeMove(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        // Copy
        try fm.copyItem(at: source, to: destination)
        // Verify: sizes match
        let srcSize = (try? fm.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? -1
        let dstSize = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? -2
        guard srcSize == dstSize && srcSize >= 0 else {
            // Verification failed: remove the incomplete copy, leave source intact
            try? fm.removeItem(at: destination)
            throw LibraryFileError.crossVolumeCopyVerificationFailed
        }
        // Delete original
        try fm.removeItem(at: source)
        AppLog.files.info("[LibraryFileService] ✅ Cross-volume move verified: \(source.lastPathComponent)")
    }

    private func relativeDescription(of url: URL, relativeTo root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath.hasPrefix(rootPath) {
            return String(urlPath.dropFirst(rootPath.count + 1))
        }
        return url.path
    }
}

// MARK: - LibraryFileError

enum LibraryFileError: LocalizedError {
    case crossVolumeCopyVerificationFailed
    case noHomeLibrarySet
    case cannotCreateDirectory(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .crossVolumeCopyVerificationFailed:
            return "Cross-volume copy verification failed. The source file was not modified."
        case .noHomeLibrarySet:
            return "No home library folder has been set. Please choose one in Settings."
        case .cannotCreateDirectory(let url, let underlying):
            return "Could not create folder \"\(url.lastPathComponent)\": \(underlying.localizedDescription). Make sure the app has permission to write to the home library folder."
        }
    }
}

// MARK: - String Helper

private extension String {
    /// Returns `self` if non-empty, otherwise `nil`.
    var nonEmpty: String? { isEmpty ? nil : self }
}
