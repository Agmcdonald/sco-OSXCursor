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
                    let taken = try await takeFileResolvingBookmark(
                        bookmarkData: comic.bookmarkData,
                        originalURL: comic.filePath,
                        entryID: entryID)
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
                coverThumb: await TrashService.thumbnailOffMain(from: comic.displayCoverData)
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
                //
                // Put the file back FIRST, and drop the manifest row only if
                // that worked. The other order can lose the file outright: if
                // the row is deleted and the put-back then fails, nothing in
                // the database references the file sitting in the Trash
                // directory and no UI can ever reach it. A ghost row the user
                // can see and act on is the better failure.
                var filePutBack = true
                if let storedName {
                    let destination = try? await restoreFileOffMain(
                        storedName: storedName, toOriginalPath: comic.filePath.path)
                    // A missing/uncreatable parent reports rather than throws,
                    // so nil *and* .failedParentMissing mean "still in trash".
                    filePutBack = destination != nil && destination != .failedParentMissing
                    if !filePutBack && manifestRowWritten {
                        AppLog.trash.error(
                            "[Trash] ⚠️ Rollback could not put \(comic.fileName) back; keeping its manifest row so the file stays reachable"
                        )
                    } else if !filePutBack {
                        // Double failure: the *insert* is what threw, so there
                        // is no manifest row to keep. Without one the file sits
                        // in the Trash directory with nothing in the database
                        // pointing at it — invisible to every UI and counted
                        // forever by totalSize(). Retry the insert once so the
                        // entry appears in the Trash list and the file stays
                        // restorable. (The book is still in the catalog, so this
                        // row is a visible ghost — the lesser failure, per the
                        // ordering rationale above.)
                        do {
                            try await database.insertTrashEntry(entry)
                            manifestRowWritten = true
                            AppLog.trash.error(
                                "[Trash] ⚠️ Rollback could not put \(comic.fileName) back; re-wrote its manifest row so the file stays reachable from the Trash"
                            )
                        } catch {
                            AppLog.trash.error(
                                "[Trash] ⚠️ Rollback could not put \(comic.fileName) back and the manifest row could not be written (\(error.localizedDescription)) — the file remains in the Trash directory WITHOUT a manifest row and will not appear in the Trash list"
                            )
                        }
                    }
                }
                if manifestRowWritten && filePutBack {
                    try? await database.deleteTrashEntry(withID: entryID)
                }
            }
        }
        return outcome
    }

    /// Resolve a security-scoped bookmark (falling back to the plain path when
    /// there is none, or it no longer resolves), hold access for exactly the
    /// duration of the take, and hand the stored file back.
    ///
    /// Takes the bookmark blob and URL rather than a `Comic` so both callers —
    /// the trash batch (a live comic) and escalation (a manifest row whose
    /// comic is long gone) — share one implementation.
    ///
    /// Runs off the main actor: a take is a `moveItem` that silently becomes a
    /// full copy across volumes, so a large "delete files" batch would otherwise
    /// block the UI for as long as the copy takes. Only value types cross into
    /// the detached task (the bookmark blob, the URL, the entry id) — never the
    /// `Comic` itself.
    ///
    /// The scope release lives in this helper rather than in the batch loop on
    /// purpose: Swift's `defer` fires when the *enclosing function* returns, so
    /// a `defer` written inside `trash(_:deleteFiles:folderIDs:)` would hold
    /// every book's security scope open until the whole batch finished.
    private func takeFileResolvingBookmark(
        bookmarkData: Data?, originalURL: URL, entryID: UUID
    ) async throws -> (
        storedName: String, fileSize: Int64
    ) {
        let store = fileStore
        return try await Task.detached(priority: .utility) {
            var fileURL = originalURL
            var didStartAccess = false
            if let bookmarkData {
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

            return try store.takeFile(at: fileURL, entryID: entryID)
        }.value
    }

    /// `TrashFileStore.restoreFile` off the main actor — same reasoning as the
    /// take: the move can be a cross-volume copy of a multi-gigabyte file.
    private func restoreFileOffMain(storedName: String, toOriginalPath originalPath: String)
        async throws -> TrashFileStore.RestoreDestination
    {
        let store = fileStore
        return try await Task.detached(priority: .utility) {
            try store.restoreFile(storedName: storedName, toOriginalPath: originalPath)
        }.value
    }

    /// `TrashFileStore.purgeFile` off the main actor.
    private func purgeFileOffMain(_ storedName: String?) async {
        guard let storedName else { return }
        let store = fileStore
        await Task.detached(priority: .utility) {
            store.purgeFile(storedName)
        }.value
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
                switch try await restoreFileOffMain(
                    storedName: storedName, toOriginalPath: entry.originalPath)
                {
                case .originalPath(let url):
                    comic.filePath = url
                    outcome = .originalPath
                case .renamed(let url):
                    comic.filePath = url
                    comic.fileName = url.lastPathComponent
                    // The saved bookmark still points at the original path,
                    // which is occupied by a DIFFERENT file now — resolving it
                    // later would silently open the wrong book. Drop it; the
                    // app mints a fresh bookmark the next time this file is
                    // opened. (.homeLibrary gets a fresh one from the caller;
                    // .originalPath's bookmark still resolves correctly.)
                    comic.bookmarkData = nil
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
            await purgeFileOffMain(orphanedStoredName)
            AppLog.trash.info("[Trash] ♻️ Restored \(entry.displayTitle)")
            return outcome
        } catch {
            // The file has already left the Trash directory, so the manifest
            // row is now a lie: every retry would fail at the move with "the
            // file isn't there". Rewrite the row to describe what is actually
            // true — the file is safe on disk at comic.filePath, only the
            // catalog half is still missing — so a retry restores cleanly.
            await purgeFileOffMain(orphanedStoredName)
            await downgradeEntryToCatalogOnly(
                entry, comic: comic, folderIDs: snapshot.folderIDs)
            return .failed(
                "The book's catalog entry couldn't be restored: \(error.localizedDescription)")
        }
    }

    /// Rewrite a manifest row as catalog-only after its file was successfully
    /// moved out of the Trash but the catalog write failed. The snapshot is
    /// re-encoded from the mutated comic so `filePath`/`fileName` point at where
    /// the file actually landed. `insertTrashEntry` upserts (GRDB `save`), so
    /// this replaces the row in place, keeping its id and `deletedAt`.
    private func downgradeEntryToCatalogOnly(
        _ entry: TrashEntry, comic: Comic, folderIDs: [UUID]
    ) async {
        // Nothing moved for a catalog-only entry — its row is still accurate.
        guard entry.trashedFileName != nil else { return }
        guard let snapshotJSON = TrashSnapshot(comic: comic, folderIDs: folderIDs).encoded() else {
            AppLog.trash.error(
                "[Trash] ⚠️ Couldn't re-encode snapshot for \(entry.displayTitle); manifest row still points at a file that has left the Trash"
            )
            return
        }
        let downgraded = TrashEntry(
            id: entry.id,
            comicSnapshot: snapshotJSON,
            originalPath: comic.filePath.path,
            bookmarkData: comic.bookmarkData,
            trashedFileName: nil,
            fileSize: 0,
            deletedAt: entry.deletedAt,
            kind: .catalog,
            displayTitle: entry.displayTitle,
            coverThumb: entry.coverThumb
        )
        do {
            try await database.insertTrashEntry(downgraded)
            AppLog.trash.info(
                "[Trash] ⬇️ Downgraded \(entry.displayTitle) to catalog-only — its file is back on disk at \(comic.filePath.path)"
            )
        } catch {
            AppLog.trash.error(
                "[Trash] ⚠️ Downgrade failed for \(entry.displayTitle): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Escalate (catalog-only → file in Trash)

    /// What `escalateToDeviceDelete` did. Richer than a Bool so the UI can tell
    /// "nothing to do" (the file is already in the Trash) apart from "the file
    /// is missing or locked", which is the case a status line must explain.
    enum EscalateOutcome: Equatable {
        /// The file is now in the Trash directory and the manifest row says so.
        case escalated
        /// The entry's file was never left on disk — nothing to take.
        case notApplicable
        /// The file couldn't be taken (moved, deleted, locked, unreadable) or
        /// the manifest couldn't be updated. The entry is unchanged.
        case failed(String)
    }

    /// Turn a catalog-only entry ("removed from library, file kept on disk")
    /// into a full file entry by taking its file into the Trash directory.
    ///
    /// The row is updated in place — same id, same `deletedAt` (so the purge
    /// clock does not restart), same snapshot and cover thumb — and the book
    /// stays fully restorable, now with its file coming back too. A missing or
    /// unreadable file leaves the entry exactly as it was.
    func escalateToDeviceDelete(_ entry: TrashEntry) async -> EscalateOutcome {
        guard entry.canEscalateToDeviceDelete else { return .notApplicable }

        // Bundled samples never had their file taken (trash() skips them the
        // same way) — the file lives inside the app bundle, which the sandbox
        // will refuse to modify. Refuse politely instead of surfacing a raw
        // FileManager error after a scary confirmation.
        if let snapshot = TrashSnapshot.decode(entry.comicSnapshot),
           Comic.isBundled(snapshot.comic) {
            return .failed("This is a bundled sample — its file is part of the app and can't be deleted.")
        }

        let taken: (storedName: String, fileSize: Int64)
        do {
            taken = try await takeFileResolvingBookmark(
                bookmarkData: entry.bookmarkData,
                originalURL: URL(fileURLWithPath: entry.originalPath),
                entryID: entry.id)
        } catch {
            AppLog.trash.error(
                "[Trash] ⚠️ Escalate could not take the file for \(entry.displayTitle): \(error.localizedDescription)"
            )
            return .failed(error.localizedDescription)
        }

        do {
            try await database.insertTrashEntry(
                entry.escalated(storedName: taken.storedName, fileSize: taken.fileSize))
            AppLog.trash.info(
                "[Trash] 📥 Escalated \(entry.displayTitle) to a device delete — its file is now in the Trash"
            )
            return .escalated
        } catch {
            // The file has moved but the row still says "catalog, no stored
            // file", so nothing in the database points at it: it would be
            // invisible to every UI and counted by totalSize() forever. Put it
            // back where it came from; only if that fails do we retry the row
            // update, so the file stays reachable from the Trash list.
            let putBack = try? await restoreFileOffMain(
                storedName: taken.storedName, toOriginalPath: entry.originalPath)
            if putBack != nil && putBack != .failedParentMissing {
                AppLog.trash.error(
                    "[Trash] ⚠️ Escalate failed for \(entry.displayTitle) (\(error.localizedDescription)); its file was put back"
                )
                return .failed(error.localizedDescription)
            }
            do {
                try await database.insertTrashEntry(
                    entry.escalated(storedName: taken.storedName, fileSize: taken.fileSize))
                AppLog.trash.error(
                    "[Trash] ⚠️ Escalate couldn't put \(entry.displayTitle)'s file back; re-wrote its manifest row so the file stays reachable from the Trash"
                )
                return .escalated
            } catch {
                AppLog.trash.error(
                    "[Trash] ⚠️ Escalate couldn't put \(entry.displayTitle)'s file back and the manifest row could not be written (\(error.localizedDescription)) — the file sits in the Trash directory WITHOUT a manifest row"
                )
                return .failed(error.localizedDescription)
            }
        }
    }

    /// Bulk escalate with per-entry failure isolation — one missing file never
    /// stops the rest. `notApplicable` entries are skipped silently (the UI
    /// only ever offers this for catalog-kind rows).
    func escalateAll(_ entries: [TrashEntry]) async -> (escalated: Int, failed: Int) {
        var escalated = 0
        var failed = 0
        for entry in entries {
            switch await escalateToDeviceDelete(entry) {
            case .escalated: escalated += 1
            case .failed: failed += 1
            case .notApplicable: break
            }
        }
        return (escalated, failed)
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

    /// `thumbnail(from:)` off the main actor — it fully decodes the cover, which
    /// on a large batch is a visible stall. Only the cover bytes cross over.
    private static func thumbnailOffMain(from coverData: Data?) async -> Data? {
        guard let coverData else { return nil }
        return await Task.detached(priority: .utility) {
            thumbnail(from: coverData)
        }.value
    }

    /// Downscale cover data to a small JPEG for the trash list (~120pt @2x).
    ///
    /// `nonisolated` because it touches nothing but its argument: that lets the
    /// detached task above run it off the main actor.
    nonisolated static func thumbnail(from coverData: Data?) -> Data? {
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
