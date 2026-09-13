//
//  TrashService.swift
//  SCO-OSXCursor
//
//  Orchestrates the Trash: snapshots a book (catalog row + folder
//  memberships), optionally takes its file into the Trash directory, and
//  restores/purges/sweeps. File mechanics live in TrashFileStore; manifest
//  rows in DatabaseManager. See the trash-restore design spec.
//

import Foundation

#if canImport(ImageIO)
    import CoreGraphics
    import ImageIO
#endif

@MainActor
final class TrashService {
    static let shared = TrashService()

    private let fileStore: TrashFileStore
    private let database: DatabaseManager

    init(
        fileStore: TrashFileStore = TrashFileStore(directory: TrashFileStore.defaultDirectory()),
        database: DatabaseManager = .shared
    ) {
        self.fileStore = fileStore
        self.database = database
    }

    // MARK: - Trash

    struct TrashOutcome {
        var trashed = 0
        var fileProblems = 0
    }

    /// Snapshot each comic (with its folder memberships), optionally take its
    /// file, write the manifest row, then delete the catalog row. One book's
    /// failure never aborts the batch.
    func trash(
        _ comics: [Comic], deleteFiles: Bool,
        folderIDs: (Comic) -> [UUID]
    ) async -> TrashOutcome {
        var outcome = TrashOutcome()
        for comic in comics {
            let snapshot = TrashSnapshot(comic: comic, folderIDs: folderIDs(comic))
            guard let snapshotJSON = snapshot.encoded() else {
                AppLog.trash.error(
                    "[Trash] ⚠️ Snapshot failed for \(comic.fileName) — skipping trash, book NOT deleted"
                )
                continue
            }

            let entryID = UUID()
            var kind: TrashKind = .catalog
            var storedName: String?
            var fileSize: Int64 = 0

            if deleteFiles && !Comic.isBundled(comic) {
                do {
                    let taken = try takeFileResolvingBookmark(for: comic, entryID: entryID)
                    storedName = taken.storedName
                    fileSize = taken.fileSize
                    kind = .file
                } catch {
                    // File locked/missing: still trash the catalog row so the
                    // entry is restorable; report the file problem.
                    AppLog.trash.error(
                        "[Trash] ⚠️ Could not take file for \(comic.fileName): \(error.localizedDescription)"
                    )
                    outcome.fileProblems += 1
                }
            }

            let entry = TrashEntry(
                id: entryID,
                comicSnapshot: snapshotJSON,
                originalPath: comic.filePath.path,
                bookmarkData: comic.bookmarkData,
                trashedFileName: storedName,
                fileSize: fileSize,
                deletedAt: Date(),
                kind: kind,
                displayTitle: comic.displayTitle,
                coverThumb: TrashService.thumbnail(from: comic.coverImageData)
            )

            var manifestRowWritten = false
            do {
                try await database.insertTrashEntry(entry)
                manifestRowWritten = true
                try await database.deleteComic(withID: comic.id)
                outcome.trashed += 1
            } catch {
                AppLog.trash.error(
                    "[Trash] ⚠️ Manifest/delete failed for \(comic.fileName): \(error.localizedDescription)"
                )
                // Roll back to "nothing happened": the book is still in the
                // catalog, so a manifest row would be a ghost duplicate and a
                // taken file would be unreachable from the library.
                if manifestRowWritten {
                    try? await database.deleteTrashEntry(withID: entryID)
                }
                if let storedName {
                    _ = try? fileStore.restoreFile(
                        storedName: storedName, toOriginalPath: comic.filePath.path)
                }
            }
        }
        return outcome
    }

    /// Resolve the comic's security-scoped bookmark, hold access for exactly
    /// the duration of the take, and hand the stored file back.
    ///
    /// The scope release lives in this helper rather than in the batch loop on
    /// purpose: Swift's `defer` fires when the *enclosing function* returns, so
    /// a `defer` written inside `trash(_:deleteFiles:folderIDs:)` would hold
    /// every book's security scope open until the whole batch finished.
    private func takeFileResolvingBookmark(for comic: Comic, entryID: UUID) throws -> (
        storedName: String, fileSize: Int64
    ) {
        var fileURL = comic.filePath
        var didStartAccess = false
        if let bookmarkData = comic.bookmarkData {
            var isStale = false
            #if os(macOS)
                let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale)
            #else
                let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale)
            #endif
            if let resolved {
                fileURL = resolved
                didStartAccess = resolved.startAccessingSecurityScopedResource()
            }
        }
        defer { if didStartAccess { fileURL.stopAccessingSecurityScopedResource() } }

        return try fileStore.takeFile(at: fileURL, entryID: entryID)
    }

    // MARK: - Restore

    enum RestoreOutcome {
        case originalPath
        case renamed
        case homeLibrary
        case catalogOnly
        case failed(String)
    }

    /// Put a trashed book back: move its file out of the Trash directory (with
    /// fallbacks), re-save the catalog row, recreate surviving folder
    /// memberships, then drop the manifest row.
    ///
    /// `fileIntoHomeLibrary` is the caller's escape hatch for the case where the
    /// original location can't take the file back; it keeps LibraryFileService
    /// knowledge out of this class.
    func restore(
        _ entry: TrashEntry,
        fileIntoHomeLibrary: (URL, Comic) async -> (URL, Data?)?
    ) async -> RestoreOutcome {
        guard let snapshot = TrashSnapshot.decode(entry.comicSnapshot) else {
            return .failed("This trash entry's snapshot can't be read.")
        }
        var comic = snapshot.comic
        var outcome: RestoreOutcome = .catalogOnly
        // Set only when the file was re-filed elsewhere and a copy may still be
        // sitting in the Trash directory under its stored name.
        var orphanedStoredName: String?

        if let storedName = entry.trashedFileName {
            do {
                switch try fileStore.restoreFile(
                    storedName: storedName, toOriginalPath: entry.originalPath)
                {
                case .originalPath(let url):
                    comic.filePath = url
                    outcome = .originalPath
                case .renamed(let url):
                    comic.filePath = url
                    comic.fileName = url.lastPathComponent
                    outcome = .renamed
                case .failedParentMissing:
                    // A merely-deleted original folder is not this case: the
                    // store recreates a missing parent directory and restores
                    // into it. This fires only when the parent can't be created
                    // at all (an unwritable or detached volume, or a file now
                    // sitting where the folder used to be), so the file has to
                    // be re-filed into the home library instead.
                    //
                    // storedFileURL is only ever handed a name that takeFile
                    // wrote and the manifest recorded — never an unvalidated
                    // string from elsewhere.
                    let stored = fileStore.storedFileURL(storedName)
                    if let (newURL, bookmark) = await fileIntoHomeLibrary(stored, comic) {
                        comic.filePath = newURL
                        comic.fileName = newURL.lastPathComponent
                        comic.bookmarkData = bookmark
                        outcome = .homeLibrary
                        // If the caller copied rather than moved, the trash copy
                        // is now dead weight that totalSize() would count
                        // forever. Only clean it up once we know the library
                        // holds a file at a different path.
                        if newURL.standardizedFileURL != stored.standardizedFileURL {
                            orphanedStoredName = storedName
                        }
                    } else {
                        return .failed(
                            "The original folder is gone and the file couldn't be re-filed into the library."
                        )
                    }
                }
            } catch {
                return .failed(
                    "Couldn't move the file out of the Trash: \(error.localizedDescription)")
            }
        }

        do {
            comic.needsAttention = false
            try await database.saveComic(comic)
            for folderID in snapshot.folderIDs
            where (try? await database.folderExists(id: folderID)) == true {
                try? await database.addComics([comic.id], toFolder: folderID)
            }
            try await database.deleteTrashEntry(withID: entry.id)
            fileStore.purgeFile(orphanedStoredName)
            AppLog.trash.info("[Trash] ♻️ Restored \(entry.displayTitle)")
            return outcome
        } catch {
            return .failed(
                "The book's catalog entry couldn't be restored: \(error.localizedDescription)")
        }
    }

    // MARK: - Purge / sweep

    func purge(_ entry: TrashEntry) async {
        fileStore.purgeFile(entry.trashedFileName)
        try? await database.deleteTrashEntry(withID: entry.id)
        AppLog.trash.info("[Trash] 🔥 Purged \(entry.displayTitle)")
    }

    func purgeAll() async {
        for entry in await entries() {
            await purge(entry)
        }
    }

    /// Returns the number purged. `retentionDays` nil = Never = no-op.
    @discardableResult
    func sweepExpired(retentionDays: Int?) async -> Int {
        guard retentionDays != nil else { return 0 }
        let expired = TrashRetention.expired(await entries(), retentionDays: retentionDays)
        for entry in expired {
            await purge(entry)
        }
        if !expired.isEmpty {
            AppLog.trash.info(
                "[Trash] 🧹 Sweep purged \(expired.count) expired entr\(expired.count == 1 ? "y" : "ies")"
            )
        }
        return expired.count
    }

    func entries() async -> [TrashEntry] {
        (try? await database.fetchTrashEntries()) ?? []
    }

    func totalSize() -> Int64 {
        fileStore.totalSize()
    }

    // MARK: - Thumbnail

    /// Downscale cover data to a small JPEG for the trash list (~120pt @2x).
    static func thumbnail(from coverData: Data?) -> Data? {
        guard let coverData else { return nil }
        #if canImport(ImageIO)
            guard let src = CGImageSourceCreateWithData(coverData as CFData, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
            else { return nil }
            let out = NSMutableData()
            guard
                let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(
                dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return out as Data
        #else
            return coverData
        #endif
    }
}
