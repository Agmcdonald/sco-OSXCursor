//
//  BookPackageImporter.swift
//  SCO-OSXCursor
//
//  Receives `.scobook` transfer packages (see TransferManifest.swift).
//  Receive pipeline:
//
//      peek()             — read manifest + cover only (fast, drives the sheet)
//      findDuplicate()    — same UUID, or same size + filename, in the library
//      resolveReceiveRoot()— where received books live on this platform
//      importNewBook()    — extract (SHA-256 verified) → file into the library
//                           structure → materialize the Comic
//
//  On iPad/iPhone received books are copied into the app's own container
//  (Documents/Library) — no security-scoped-bookmark fragility. On the Mac
//  they go into the configured home library (honoring the folder-structure
//  setting), falling back to Application Support when none is set.
//
//  The receive path is platform-shared on purpose: the Mac can accept
//  packages too, so enabling iPad→Mac later is only a Send button.
//

import CryptoKit
import Foundation
import ZIPFoundation

// MARK: - Incoming Package

/// A parsed-but-not-yet-imported `.scobook` package.
struct IncomingBookPackage: Identifiable {
    let id = UUID()
    let packageURL: URL
    /// True when the package arrived via the iOS "Open in…" Inbox or a temp
    /// location — safe (and polite) to delete after a successful import.
    let isTransient: Bool
    let manifest: TransferManifest
    let coverData: Data?
}

// MARK: - Errors

enum BookPackageImportError: LocalizedError {
    case unreadablePackage
    case missingManifest
    case unsupportedVersion(Int)
    case missingBookEntry(String)
    case checksumMismatch
    case noWritableDestination

    var errorDescription: String? {
        switch self {
        case .unreadablePackage:
            return "This doesn't look like a valid book package."
        case .missingManifest:
            return "The package is missing its manifest and can't be imported."
        case .unsupportedVersion(let version):
            return
                "This package was made by a newer version of Super Comic Organizer (format v\(version)). Update this app to receive it."
        case .missingBookEntry(let path):
            return "The package is missing its book file (\(path))."
        case .checksumMismatch:
            return
                "The book file failed verification — the package may be corrupted. Try sending it again."
        case .noWritableDestination:
            return "Couldn't find a writable library location for the received book."
        }
    }
}

// MARK: - Importer

final class BookPackageImporter {

    private static let chunkSize = 1 << 20  // 1 MB

    // MARK: - Peek (manifest + cover only)

    /// Reads just the manifest and cover out of a package — cheap enough to
    /// run the moment the file arrives, before showing the receive sheet.
    static func peek(at url: URL) throws -> IncomingBookPackage {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw BookPackageImportError.unreadablePackage
        }

        guard let manifestEntry = archive[BookPackage.manifestEntryPath] else {
            throw BookPackageImportError.missingManifest
        }
        var manifestData = Data()
        _ = try archive.extract(manifestEntry, skipCRC32: true) { chunk in
            manifestData.append(chunk)
        }
        guard let manifest = try? BookPackage.jsonDecoder().decode(
            TransferManifest.self, from: manifestData)
        else {
            throw BookPackageImportError.missingManifest
        }
        guard manifest.formatVersion <= TransferManifest.currentFormatVersion else {
            throw BookPackageImportError.unsupportedVersion(manifest.formatVersion)
        }

        var coverData: Data?
        if manifest.hasCover, let coverEntry = archive[BookPackage.coverEntryPath] {
            var data = Data()
            _ = try? archive.extract(coverEntry, skipCRC32: true) { chunk in
                data.append(chunk)
            }
            coverData = data.isEmpty ? nil : data
        }

        // iOS "Open in…" copies arrive in Documents/Inbox; anything in a temp
        // directory is also ours to clean up. A user's own file (macOS
        // double-click, Files app copy) is never deleted.
        let path = url.standardizedFileURL.path
        let isTransient =
            path.contains("/Inbox/")
            || path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path)

        return IncomingBookPackage(
            packageURL: url,
            isTransient: isTransient,
            manifest: manifest,
            coverData: coverData
        )
    }

    // MARK: - Duplicate Detection

    /// Returns the library's existing copy of the incoming book, if any.
    /// Primary match: same UUID (the ID travels in the manifest). Fallback:
    /// same file size + same original filename (covers a book imported
    /// separately on both devices).
    static func findDuplicate(of manifest: TransferManifest, in comics: [Comic]) -> Comic? {
        if let byID = comics.first(where: { $0.id == manifest.comicID }) {
            return byID
        }
        return comics.first(where: {
            $0.fileSize == manifest.fileSize
                && $0.fileName.caseInsensitiveCompare(manifest.originalFileName) == .orderedSame
        })
    }

    // MARK: - Receive Root

    struct ReceiveRoot {
        let url: URL
        /// True when file operations under this root need
        /// `startAccessingSecurityScopedResource()` (macOS home library).
        let requiresSecurityScope: Bool
    }

    /// Where received books live on this platform. Creates the directory if
    /// needed. Must run on the main actor (reads settings on macOS).
    @MainActor
    static func resolveReceiveRoot() throws -> ReceiveRoot {
        let fm = FileManager.default

        #if os(iOS)
            // App container — reliable on iPad, no bookmark fragility,
            // included in device backups.
            guard
                let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            else {
                throw BookPackageImportError.noWritableDestination
            }
            let root = documents.appendingPathComponent("Library", isDirectory: true)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            return ReceiveRoot(url: root, requiresSecurityScope: false)
        #else
            // Home library when configured (received books join the normal
            // Publisher/Series structure) …
            if let homeLibrary = SettingsViewModel().resolveHomeLibraryURL() {
                return ReceiveRoot(url: homeLibrary, requiresSecurityScope: true)
            }
            // … otherwise a folder the sandbox always lets us write.
            guard
                let appSupport = fm.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first
            else {
                throw BookPackageImportError.noWritableDestination
            }
            let root =
                appSupport
                .appendingPathComponent("SuperComicOrganizer", isDirectory: true)
                .appendingPathComponent("Received Books", isDirectory: true)
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            return ReceiveRoot(url: root, requiresSecurityScope: false)
        #endif
    }

    // MARK: - Import (new book)

    /// Extracts the book (SHA-256 verified), files it into the receive root
    /// honoring the folder-structure setting, and returns the fully formed
    /// `Comic` ready to persist. Synchronous — run on a background task;
    /// `onProgress` reports 0.0–1.0.
    ///
    /// The caller persists the returned comic (`LibraryViewModel
    /// .addTransferredComic`) and applies any folder choice.
    static func importNewBook(
        package: IncomingBookPackage,
        receiveRoot: ReceiveRoot,
        folderStructure: AppSettings.FolderStructure,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) throws -> Comic {
        let fm = FileManager.default
        let manifest = package.manifest

        let packageAccessing = package.packageURL.startAccessingSecurityScopedResource()
        defer {
            if packageAccessing {
                package.packageURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let archive = try? Archive(url: package.packageURL, accessMode: .read) else {
            throw BookPackageImportError.unreadablePackage
        }
        guard let bookEntry = archive[manifest.bookEntryPath] else {
            throw BookPackageImportError.missingBookEntry(manifest.bookEntryPath)
        }

        // ── 1. Extract to temp, hashing as we go (0.0 → 0.85) ──
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("SCOTransfer-in-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let tempFile = tempDir.appendingPathComponent(manifest.originalFileName)
        fm.createFile(atPath: tempFile.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tempFile) else {
            throw BookPackageImportError.noWritableDestination
        }

        var hasher = SHA256()
        var bytesWritten: Int64 = 0
        let expectedBytes = max(bookEntry.uncompressedSize, 1)
        do {
            _ = try archive.extract(bookEntry, bufferSize: chunkSize) { chunk in
                try handle.write(contentsOf: chunk)
                hasher.update(data: chunk)
                bytesWritten += Int64(chunk.count)
                onProgress(min(0.85, Double(bytesWritten) / Double(expectedBytes) * 0.85))
            }
            try handle.close()
        } catch {
            try? handle.close()
            throw BookPackageImportError.unreadablePackage
        }

        // ── 2. Verify integrity against the manifest ──
        let sha256 = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard sha256.caseInsensitiveCompare(manifest.fileSHA256) == .orderedSame,
            bytesWritten == manifest.fileSize
        else {
            throw BookPackageImportError.checksumMismatch
        }
        onProgress(0.88)

        // ── 3. File into the library structure (0.88 → 0.98) ──
        let rootAccessing =
            receiveRoot.requiresSecurityScope
            && receiveRoot.url.startAccessingSecurityScopedResource()
        defer {
            if rootAccessing { receiveRoot.url.stopAccessingSecurityScopedResource() }
        }

        // A provisional comic drives destinationURL() so received books land
        // in the same Publisher/Series hierarchy as normal imports.
        let provisional = manifest.makeComic(
            filePath: tempFile,
            fileName: manifest.originalFileName,
            bookmarkData: nil,
            coverData: nil
        )
        let service = LibraryFileService.shared
        var destination = service.destinationURL(
            for: provisional, in: receiveRoot.url, folderStructure: folderStructure)
        destination = service.resolveConflict(at: destination)

        do {
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try fm.moveItem(at: tempFile, to: destination)
        } catch {
            throw LibraryFileError.cannotCreateDirectory(
                destination.deletingLastPathComponent(), underlying: error)
        }
        onProgress(0.98)

        // ── 4. Bookmark + final Comic ──
        #if os(macOS)
            let bookmark = try? destination.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        #else
            // .minimalBookmark creates a resolvable bookmark on iOS/iPadOS.
            let bookmark = try? destination.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        #endif

        let comic = manifest.makeComic(
            filePath: destination,
            fileName: destination.lastPathComponent,
            bookmarkData: bookmark,
            coverData: package.coverData
        )
        onProgress(1.0)
        AppLog.files.info(
            "[BookPackageImporter] ✅ Received \(comic.fileName) → \(destination.path)")
        return comic
    }

    // MARK: - Cleanup

    /// Deletes a transient package (iOS Inbox / temp copies) after import.
    static func cleanUp(_ package: IncomingBookPackage) {
        guard package.isTransient else { return }
        try? FileManager.default.removeItem(at: package.packageURL)
    }
}
