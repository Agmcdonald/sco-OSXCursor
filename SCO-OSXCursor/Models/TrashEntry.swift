//
//  TrashEntry.swift
//  SCO-OSXCursor
//
//  Manifest model for the app-managed Trash: a full catalog snapshot of a
//  deleted book (plus its folder memberships) and, when the file itself was
//  deleted, where it lives inside the Trash directory. See
//  docs/superpowers/specs/2026-09-13-trash-restore-design.md.
//

import Foundation
import GRDB

// MARK: - Snapshot

/// Everything needed to restore a deleted book: the complete Comic row and
/// the folders it belonged to (memberships are cascade-deleted with the row,
/// so they're captured here before deletion).
struct TrashSnapshot: Codable {
    var comic: Comic
    var folderIDs: [UUID]

    func encoded() -> String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode(_ json: String?) -> TrashSnapshot? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TrashSnapshot.self, from: data)
    }
}

// MARK: - Kind

enum TrashKind: String, Codable {
    case file  // the comic file was moved into the Trash directory
    case catalog  // only the catalog row was removed; file untouched on disk
}

// MARK: - Manifest record

struct TrashEntry: Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "trash_entries"

    var id: UUID
    var comicSnapshot: String
    var originalPath: String
    var bookmarkData: Data?
    var trashedFileName: String?
    var fileSize: Int64
    var deletedAt: Date
    var kind: TrashKind
    var displayTitle: String
    var coverThumb: Data?

    enum Columns {
        /// ⚠️ Persisted as `uuidString` TEXT (see `encode(to:)`). GRDB's UUID
        /// key overloads — `deleteOne(db, id:)` / `fetchOne(db, id:)` — encode a
        /// UUID as a 16-byte BLOB and will silently match nothing. Always
        /// address rows with `key: id.uuidString`.
        static let id = Column("id")
        static let comicSnapshot = Column("comic_snapshot")
        static let originalPath = Column("original_path")
        static let bookmarkData = Column("bookmark_data")
        static let trashedFileName = Column("trashed_file_name")
        static let fileSize = Column("file_size")
        static let deletedAt = Column("deleted_at")
        static let kind = Column("kind")
        static let displayTitle = Column("display_title")
        static let coverThumb = Column("cover_thumb")
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.comicSnapshot] = comicSnapshot
        container[Columns.originalPath] = originalPath
        container[Columns.bookmarkData] = bookmarkData
        container[Columns.trashedFileName] = trashedFileName
        container[Columns.fileSize] = fileSize
        container[Columns.deletedAt] = deletedAt
        container[Columns.kind] = kind.rawValue
        container[Columns.displayTitle] = displayTitle
        container[Columns.coverThumb] = coverThumb
    }

    init(
        id: UUID, comicSnapshot: String, originalPath: String,
        bookmarkData: Data?, trashedFileName: String?, fileSize: Int64,
        deletedAt: Date, kind: TrashKind, displayTitle: String, coverThumb: Data?
    ) {
        self.id = id
        self.comicSnapshot = comicSnapshot
        self.originalPath = originalPath
        self.bookmarkData = bookmarkData
        self.trashedFileName = trashedFileName
        self.fileSize = fileSize
        self.deletedAt = deletedAt
        self.kind = kind
        self.displayTitle = displayTitle
        self.coverThumb = coverThumb
    }

    init(row: Row) throws {
        guard
            let idString: String = row["id"],
            let id = UUID(uuidString: idString)
        else { throw DatabaseError.fetchFailed }
        self.id = id
        self.comicSnapshot = row["comic_snapshot"] ?? "{}"
        self.originalPath = row["original_path"] ?? ""
        self.bookmarkData = row["bookmark_data"]
        self.trashedFileName = row["trashed_file_name"]
        self.fileSize = row["file_size"] ?? 0
        self.deletedAt = row["deleted_at"] ?? Date()
        self.kind = TrashKind(rawValue: row["kind"] ?? "catalog") ?? .catalog
        self.displayTitle = row["display_title"] ?? "Unknown"
        self.coverThumb = row["cover_thumb"]
    }
}

// MARK: - Retention math

/// Pure retention arithmetic — unit-tested; no clock or store dependencies.
enum TrashRetention {
    /// Entries strictly older than `retentionDays` days. Nil = Never.
    static func expired(_ entries: [TrashEntry], retentionDays: Int?, now: Date = Date())
        -> [TrashEntry]
    {
        // A non-positive value is "Never" too: a negative one would put the
        // cutoff in the future and expire the entire trash.
        guard let retentionDays, retentionDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return entries.filter { $0.deletedAt < cutoff }
    }

    /// Stored `trashRetentionDays` (0 = Never) → API value.
    static func days(fromStoredValue v: Int) -> Int? {
        v <= 0 ? nil : v
    }

    /// Whole days until this entry purges under the given retention; nil = kept forever.
    static func daysRemaining(for entry: TrashEntry, retentionDays: Int?, now: Date = Date()) -> Int?
    {
        guard let retentionDays else { return nil }
        let purgeDate = entry.deletedAt.addingTimeInterval(Double(retentionDays) * 86_400)
        return max(0, Int(ceil(purgeDate.timeIntervalSince(now) / 86_400)))
    }
}
