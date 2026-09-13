//
//  TrashFileStore.swift
//  SCO-OSXCursor
//
//  File half of the Trash system: moving comic files into and out of the
//  app-managed Trash directory. Pure file operations, no database — the
//  directory URL is injected so tests run against a temp folder.
//

import Foundation

struct TrashFileStore {
    let directory: URL

    /// Production location: sibling of comics.db.
    static func defaultDirectory() -> URL {
        let appSupport =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return
            appSupport
            .appendingPathComponent("SuperComicOrganizer")
            .appendingPathComponent("Trash")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Stored names are `"<uuid>[.ext]"` by construction. A name carrying a path
    /// separator or a parent reference would let a corrupted/hand-edited manifest
    /// row reach outside the trash directory, so both callers reject it.
    private func isSafeStoredName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("..")
    }

    /// `attributesOfItem[.size]` is an `Any?` inside a throwing call — bound in
    /// two steps so the cast isn't a double optional. Missing/unreadable = 0.
    private func fileSize(atPath path: String) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attributes[.size] as? Int64
        else { return 0 }
        return size
    }

    // MARK: Take

    /// Move a file into the trash as "<entryID>.<ext>". Cross-volume moves
    /// fall back to copy + remove.
    func takeFile(at source: URL, entryID: UUID) throws -> (storedName: String, fileSize: Int64) {
        try ensureDirectory()
        let ext = source.pathExtension
        let storedName = ext.isEmpty ? entryID.uuidString : "\(entryID.uuidString).\(ext)"
        let destination = directory.appendingPathComponent(storedName)
        let size = fileSize(atPath: source.path)
        // If something is already stored under this name (the same entry taken
        // twice), it is not ours to clean up — it may be the user's only copy.
        let destinationPreexisted = FileManager.default.fileExists(atPath: destination.path)
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            // Cross-volume (or other move failure): copy then remove. Log the
            // move error rather than swallowing it — when the fallback succeeds
            // this is the only record of why the move didn't work.
            AppLog.trash.info(
                "[Trash] ↪️ Move failed for \(source.lastPathComponent), trying copy+remove: \(error.localizedDescription)"
            )
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                try FileManager.default.removeItem(at: source)
            } catch {
                // Anything that fails once the copy has started (the copy itself,
                // or the source removal) must not leave bytes in the trash
                // directory: the caller is throwing, so no manifest row will ever
                // reference them and totalSize() would count them forever. Only
                // ever remove a file this call put there.
                if !destinationPreexisted {
                    try? FileManager.default.removeItem(at: destination)
                }
                AppLog.trash.error(
                    "[Trash] ⚠️ Take failed for \(source.lastPathComponent), trash copy discarded: \(error.localizedDescription)"
                )
                throw error
            }
        }
        AppLog.trash.info(
            "[Trash] 📥 Took file into trash: \(source.lastPathComponent) → \(storedName)")
        return (storedName, size)
    }

    // MARK: Restore

    enum RestoreDestination: Equatable {
        case originalPath(URL)
        case renamed(URL)
        case failedParentMissing
    }

    /// Move a stored file back toward its original path. Never overwrites an
    /// existing file; never throws for a missing/uncreatable parent (reports
    /// it so the caller can fall back to home-library filing).
    func restoreFile(storedName: String, toOriginalPath originalPath: String) throws
        -> RestoreDestination
    {
        guard isSafeStoredName(storedName) else {
            AppLog.trash.error("[Trash] ⚠️ Refusing to restore unsafe stored name: \(storedName)")
            throw CocoaError(.fileNoSuchFile)
        }
        let stored = directory.appendingPathComponent(storedName)
        let target = URL(fileURLWithPath: originalPath)
        let parent = target.deletingLastPathComponent()

        var isDir: ObjCBool = false
        let parentExists = FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDir)
        if !parentExists {
            do {
                try FileManager.default.createDirectory(
                    at: parent, withIntermediateDirectories: true)
            } catch {
                return .failedParentMissing
            }
        } else if !isDir.boolValue {
            return .failedParentMissing
        }

        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.moveItem(at: stored, to: target)
            AppLog.trash.info("[Trash] ♻️ Restored to original path: \(target.lastPathComponent)")
            return .originalPath(target)
        }

        // Occupied → " (restored)" before the extension, then numbered.
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var candidate = parent.appendingPathComponent("\(base) (restored)")
        if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base) (restored \(n))")
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
            n += 1
        }
        try FileManager.default.moveItem(at: stored, to: candidate)
        AppLog.trash.info(
            "[Trash] ♻️ Restored beside occupied original: \(candidate.lastPathComponent)")
        return .renamed(candidate)
    }

    func storedFileURL(_ storedName: String) -> URL {
        directory.appendingPathComponent(storedName)
    }

    // MARK: Purge / size

    func purgeFile(_ storedName: String?) {
        guard let storedName else { return }
        guard isSafeStoredName(storedName) else {
            AppLog.trash.error("[Trash] ⚠️ Refusing to purge unsafe stored name: \(storedName)")
            return
        }
        let url = directory.appendingPathComponent(storedName)
        // Already gone is the idempotent case, not a failure worth logging.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            AppLog.trash.info("[Trash] 🔥 Purged trashed file: \(storedName)")
        } catch {
            AppLog.trash.error(
                "[Trash] ⚠️ Purge failed for \(storedName): \(error.localizedDescription)")
        }
    }

    func totalSize() -> Int64 {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return 0 }
        return names.reduce(Int64(0)) { sum, name in
            sum + fileSize(atPath: directory.appendingPathComponent(name).path)
        }
    }
}
