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
    /// User-chosen custom cover picture. When set, it takes precedence over
    /// `coverComicID` and the default 2×2 book collage.
    var coverImageData: Data?
    /// A single member book chosen to represent the folder. Used when there's
    /// no custom picture; falls back to the default collage if nil.
    var coverComicID: UUID?
    var createdAt: Date
    var dateModified: Date

    /// How the folder card should be illustrated. Precedence: custom picture →
    /// chosen book → default 2×2 collage of recent members.
    enum CoverStyle: Equatable {
        case picture
        case book(UUID)
        case collage
    }

    var coverStyle: CoverStyle {
        if coverImageData != nil { return .picture }
        if let id = coverComicID { return .book(id) }
        return .collage
    }

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        sortOrder: Int = 0,
        colorHex: String? = nil,
        icon: String? = nil,
        coverImageData: Data? = nil,
        coverComicID: UUID? = nil,
        createdAt: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.icon = icon
        self.coverImageData = coverImageData
        self.coverComicID = coverComicID
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
        static let coverImageData = Column("cover_image_data")
        static let coverComicID = Column("cover_comic_id")
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
        container[Columns.coverImageData] = coverImageData
        container[Columns.coverComicID] = coverComicID?.uuidString
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

        let coverComicIDString: String? = row["cover_comic_id"]
        let coverComicID = coverComicIDString.flatMap(UUID.init(uuidString:))

        self.init(
            id: id,
            name: name,
            parentID: parentID,
            sortOrder: sortOrder,
            colorHex: row["color"],
            icon: row["icon"],
            coverImageData: row["cover_image_data"],
            coverComicID: coverComicID,
            createdAt: createdAt,
            dateModified: dateModified
        )
    }
}
