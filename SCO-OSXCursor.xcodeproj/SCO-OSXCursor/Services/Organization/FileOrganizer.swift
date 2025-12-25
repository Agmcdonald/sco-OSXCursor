//
//  FileOrganizer.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/7/25.
//

import Foundation

// MARK: - File Organizer Service
final class FileOrganizer {
    static let shared = FileOrganizer()
    
    private let fileManager = FileManager.default
    private let databaseManager = DatabaseManager.shared
    
    private init() {}
    
    // MARK: - Organization Configuration
    
    /// Organization pattern for building destination paths
    enum OrganizationPattern {
        case publisherSeriesYear      // Publisher/Series/Year
        case publisherSeries          // Publisher/Series
        case seriesYear               // Series/Year
        case flat                     // All files in root
        case custom(String)           // Custom pattern (e.g., "Publisher/Series/Volume")
    }
    
    /// Conflict resolution strategy
    enum ConflictResolution {
        case skip                    // Skip if destination exists
        case overwrite               // Overwrite existing file
        case rename                  // Rename with number suffix (e.g., file (1).cbz)
        case ask                     // Ask user (not implemented in service layer)
    }
    
    // MARK: - Path Building
    
    /// Build destination path for a comic based on organization pattern
    /// - Parameters:
    ///   - comic: The comic to organize
    ///   - basePath: Base directory for organization
    ///   - pattern: Organization pattern to use
    /// - Returns: Destination URL for the file
    func buildDestinationPath(
        for comic: Comic,
        basePath: URL,
        pattern: OrganizationPattern
    ) throws -> URL {
        var components: [String] = []
        
        switch pattern {
        case .publisherSeriesYear:
            if let publisher = comic.publisher, !publisher.isEmpty {
                components.append(sanitizeFileName(publisher))
            }
            if let series = comic.series, !series.isEmpty {
                components.append(sanitizeFileName(series))
            }
            if let year = comic.year, year > 0 {
                components.append(String(year))
            }
            
        case .publisherSeries:
            if let publisher = comic.publisher, !publisher.isEmpty {
                components.append(sanitizeFileName(publisher))
            }
            if let series = comic.series, !series.isEmpty {
                components.append(sanitizeFileName(series))
            }
            
        case .seriesYear:
            if let series = comic.series, !series.isEmpty {
                components.append(sanitizeFileName(series))
            }
            if let year = comic.year, year > 0 {
                components.append(String(year))
            }
            
        case .flat:
            // No subdirectories
            break
            
        case .custom(let customPattern):
            components = buildCustomPath(comic: comic, pattern: customPattern)
        }
        
        // Build full path
        var destination = basePath
        for component in components {
            destination = destination.appendingPathComponent(component)
        }
        
        // Add filename
        let fileName = buildFileName(for: comic)
        destination = destination.appendingPathComponent(fileName)
        
        return destination
    }
    
    /// Build custom path from pattern string
    /// Supports placeholders: {Publisher}, {Series}, {Year}, {Volume}, {Issue}
    private func buildCustomPath(comic: Comic, pattern: String) -> [String] {
        var components: [String] = []
        let parts = pattern.split(separator: "/")
        
        for part in parts {
            let placeholder = String(part)
            var value: String?
            
            switch placeholder {
            case "{Publisher}":
                value = comic.publisher
            case "{Series}":
                value = comic.series
            case "{Year}":
                value = comic.year.map { String($0) }
            case "{Volume}":
                value = comic.volume.map { String($0) }
            case "{Issue}":
                value = comic.issueNumber
            default:
                value = placeholder
            }
            
            if let value = value, !value.isEmpty {
                components.append(sanitizeFileName(value))
            }
        }
        
        return components
    }
    
    /// Build standardized filename for a comic
    func buildFileName(for comic: Comic) -> String {
        var parts: [String] = []
        
        // Add series if available
        if let series = comic.series, !series.isEmpty {
            parts.append(sanitizeFileName(series))
        }
        
        // Add issue number or volume
        if let issueNumber = comic.issueNumber, !issueNumber.isEmpty {
            parts.append("#\(issueNumber)")
        } else if let volume = comic.volume, volume > 0 {
            parts.append("v\(volume)")
        }
        
        // Add year if available
        if let year = comic.year, year > 0 {
            parts.append("(\(year))")
        }
        
        // Fallback to title if no series
        if parts.isEmpty, let title = comic.title, !title.isEmpty {
            parts.append(sanitizeFileName(title))
        }
        
        // If still empty, use original filename
        if parts.isEmpty {
            return comic.fileName
        }
        
        // Get file extension from original filename
        let fileExtension = (comic.fileName as NSString).pathExtension
        let baseName = parts.joined(separator: " ")
        
        return fileExtension.isEmpty ? baseName : "\(baseName).\(fileExtension)"
    }
    
    /// Sanitize filename to remove invalid characters
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:?*<>|\"")
        let sanitized = name.components(separatedBy: invalidChars).joined(separator: "_")
        
        // Remove leading/trailing spaces and dots
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
    
    // MARK: - File Operations
    
    /// Organize a comic file (move and rename)
    /// - Parameters:
    ///   - comic: The comic to organize
    ///   - destinationBase: Base directory for organization
    ///   - pattern: Organization pattern
    ///   - conflictResolution: How to handle conflicts
    /// - Returns: Result with new file path or error
    func organizeComic(
        _ comic: Comic,
        destinationBase: URL,
        pattern: OrganizationPattern,
        conflictResolution: ConflictResolution = .rename
    ) async throws -> URL {
        // Build destination path
        var destination = try buildDestinationPath(
            for: comic,
            basePath: destinationBase,
            pattern: pattern
        )
        
        // Handle conflicts
        destination = try resolveConflict(
            at: destination,
            resolution: conflictResolution
        )
        
        // Ensure destination directory exists
        let destinationDir = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true
        )
        
        // Get source URL from comic
        guard let sourceURL = getSourceURL(for: comic) else {
            throw FileOrganizerError.sourceNotFound
        }
        
        // Move file
        try fileManager.moveItem(at: sourceURL, to: destination)
        
        print("[FileOrganizer] ✅ Moved: \(comic.fileName) -> \(destination.lastPathComponent)")
        
        // Update database
        try await updateComicInDatabase(comic, newPath: destination)
        
        return destination
    }
    
    /// Rename a comic file in place
    /// - Parameters:
    ///   - comic: The comic to rename
    ///   - newName: New filename (without extension, will be preserved)
    /// - Returns: New file URL
    func renameComic(_ comic: Comic, newName: String) async throws -> URL {
        guard let sourceURL = getSourceURL(for: comic) else {
            throw FileOrganizerError.sourceNotFound
        }
        
        let fileExtension = sourceURL.pathExtension
        let sanitizedNewName = sanitizeFileName(newName)
        let newFileName = fileExtension.isEmpty 
            ? sanitizedNewName 
            : "\(sanitizedNewName).\(fileExtension)"
        
        let destination = sourceURL.deletingLastPathComponent()
            .appendingPathComponent(newFileName)
        
        // Check if destination exists
        if fileManager.fileExists(atPath: destination.path) {
            throw FileOrganizerError.destinationExists
        }
        
        // Rename file
        try fileManager.moveItem(at: sourceURL, to: destination)
        
        print("[FileOrganizer] ✅ Renamed: \(comic.fileName) -> \(newFileName)")
        
        // Update database
        try await updateComicInDatabase(comic, newPath: destination)
        
        return destination
    }
    
    /// Move a comic file to a new location
    /// - Parameters:
    ///   - comic: The comic to move
    ///   - destination: Destination URL
    ///   - conflictResolution: How to handle conflicts
    /// - Returns: Final destination URL
    func moveComic(
        _ comic: Comic,
        to destination: URL,
        conflictResolution: ConflictResolution = .rename
    ) async throws -> URL {
        guard let sourceURL = getSourceURL(for: comic) else {
            throw FileOrganizerError.sourceNotFound
        }
        
        // Ensure destination directory exists
        let destinationDir = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: destinationDir,
            withIntermediateDirectories: true
        )
        
        // Resolve conflicts
        var finalDestination = destination
        finalDestination = try resolveConflict(
            at: finalDestination,
            resolution: conflictResolution
        )
        
        // Move file
        try fileManager.moveItem(at: sourceURL, to: finalDestination)
        
        print("[FileOrganizer] ✅ Moved: \(comic.fileName) -> \(finalDestination.path)")
        
        // Update database
        try await updateComicInDatabase(comic, newPath: finalDestination)
        
        return finalDestination
    }
    
    // MARK: - Conflict Resolution
    
    /// Resolve file conflicts at destination
    private func resolveConflict(
        at destination: URL,
        resolution: ConflictResolution
    ) throws -> URL {
        guard fileManager.fileExists(atPath: destination.path) else {
            return destination
        }
        
        switch resolution {
        case .skip:
            throw FileOrganizerError.destinationExists
            
        case .overwrite:
            // Remove existing file
            try fileManager.removeItem(at: destination)
            return destination
            
        case .rename:
            // Find available name with number suffix
            return try findAvailableName(for: destination)
            
        case .ask:
            // This would typically be handled at UI layer
            throw FileOrganizerError.destinationExists
        }
    }
    
    /// Find available filename by appending number suffix
    private func findAvailableName(for url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension
        
        var counter = 1
        var candidate: URL
        
        repeat {
            let newFileName = fileExtension.isEmpty
                ? "\(fileName) (\(counter))"
                : "\(fileName) (\(counter)).\(fileExtension)"
            
            candidate = directory.appendingPathComponent(newFileName)
            counter += 1
            
            // Safety check to prevent infinite loop
            if counter > 1000 {
                throw FileOrganizerError.tooManyRenames
            }
        } while fileManager.fileExists(atPath: candidate.path)
        
        return candidate
    }
    
    // MARK: - Database Updates
    
    /// Update comic in database after file operation
    private func updateComicInDatabase(_ comic: Comic, newPath: URL) async throws {
        // Update file_path and file_name
        comic.filePath = newPath.path
        comic.fileName = newPath.lastPathComponent
        comic.dateModified = Date()
        
        // Update in database
        try await databaseManager.updateComic(comic)
        
        print("[FileOrganizer] ✅ Updated database for: \(comic.fileName)")
    }
    
    // MARK: - Helper Methods
    
    /// Get source URL from comic, handling security-scoped bookmarks
    private func getSourceURL(for comic: Comic) -> URL? {
        // First try to resolve from bookmark if available
        if let bookmarkData = comic.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if !isStale {
                    // Start accessing security-scoped resource
                    _ = url.startAccessingSecurityScopedResource()
                    return url
                }
            }
        }
        
        // Fallback to file_path (which is a URL)
        if !comic.filePath.path.isEmpty {
            return comic.filePath
        }
        
        return nil
    }
    
    /// Batch organize multiple comics
    func organizeComics(
        _ comics: [Comic],
        destinationBase: URL,
        pattern: OrganizationPattern,
        conflictResolution: ConflictResolution = .rename
    ) async throws -> [Comic: URL] {
        var results: [Comic: URL] = [:]
        var errors: [Comic: Error] = [:]
        
        for comic in comics {
            do {
                let destination = try await organizeComic(
                    comic,
                    destinationBase: destinationBase,
                    pattern: pattern,
                    conflictResolution: conflictResolution
                )
                results[comic] = destination
            } catch {
                errors[comic] = error
                print("[FileOrganizer] ❌ Failed to organize \(comic.fileName): \(error)")
            }
        }
        
        if !errors.isEmpty {
            print("[FileOrganizer] ⚠️ Completed with \(errors.count) errors out of \(comics.count) comics")
        }
        
        return results
    }
}

// MARK: - File Organizer Errors
enum FileOrganizerError: LocalizedError {
    case sourceNotFound
    case destinationExists
    case invalidPath
    case moveFailed
    case tooManyRenames
    case databaseUpdateFailed
    
    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "Source file not found"
        case .destinationExists:
            return "Destination file already exists"
        case .invalidPath:
            return "Invalid file path"
        case .moveFailed:
            return "Failed to move file"
        case .tooManyRenames:
            return "Too many rename attempts"
        case .databaseUpdateFailed:
            return "Failed to update database"
        }
    }
}

