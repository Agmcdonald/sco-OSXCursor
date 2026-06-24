//
//  Folder.swift
//  SCO-OSXCursor
//
//  A user-created collection. Folders are a *virtual* organizational layer:
//  membership lives in the `comic_folders` junction table and never moves
//  files on disk. A book can belong to any number of folders, and a book in
//  no folder simply has no membership rows. `parentID` is reserved for future
//  nested folders — the v1 UI keeps folders flat.
//

import Foundation
import GRDB

// MARK: - Folder Model

struct Folder: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    /// Reserved for future nesting. Always nil in the flat v1 UI.
    var parentID: UUID?
    /// Manual ordering in the folder bar (lower = earlier).
    var sortOrder: Int
    /// Optional accent hex (e.g. "#3B82F6"); nil = default tint.
    var colorHex: String?
    /// Optional SF Symbol name; nil = "folder".
    var icon: String?
    var createdAt: Date
    var dateModified: Date

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        sortOrder: Int = 0,
        colorHex: String? = nil,
        icon: String? = nil,
        createdAt: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.icon = icon
        self.createdAt = createdAt
        self.dateModified = dateModified
    }
}

// MARK: - GRDB Persistence

extension Folder: FetchableRecord, PersistableRecord {
    static let databaseTableName = "folders"

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let parentID = Column("parent_id")
        static let sortOrder = Column("sort_order")
        static let color = Column("color")
        static let icon = Column("icon")
        static let createdAt = Column("created_at")
        static let dateModified = Column("date_modified")
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.name] = name
        container[Columns.parentID] = parentID?.uuidString
        container[Columns.sortOrder] = sortOrder
        container[Columns.color] = colorHex
        container[Columns.icon] = icon
        container[Columns.createdAt] = createdAt
        container[Columns.dateModified] = dateModified
    }

    init(row: Row) throws {
        guard let idString: String = row["id"],
            let id = UUID(uuidString: idString),
            let name: String = row["name"],
            let sortOrder: Int = row["sort_order"],
            let createdAt: Date = row["created_at"],
            let dateModified: Date = row["date_modified"]
        else {
            throw DatabaseError.fetchFailed
        }

        let parentIDString: String? = row["parent_id"]
        let parentID = parentIDString.flatMap(UUID.init(uuidString:))

        self.init(
            id: id,
            name: name,
            parentID: parentID,
            sortOrder: sortOrder,
            colorHex: row["color"],
            icon: row["icon"],
            createdAt: createdAt,
            dateModified: dateModified
        )
    }
}
