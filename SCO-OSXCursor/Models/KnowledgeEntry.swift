//
//  KnowledgeEntry.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/15/25.
//

import Foundation
import GRDB

// MARK: - Knowledge Entry Model
struct KnowledgeEntry: Identifiable, Codable, Equatable {
    var id: Int64?
    var type: EntryType
    var name: String
    var normalizedName: String
    var createdAt: Date

    init(id: Int64? = nil, type: EntryType, name: String, createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.name = name
        self.normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.createdAt = createdAt
    }
}

// MARK: - Entry Type Enum
extension KnowledgeEntry {
    enum EntryType: String, Codable, CaseIterable {
        case series = "series"
        case publisher = "publisher"
        case writer = "writer"
        case artist = "artist"
        case coverArtist = "cover_artist"
        case colorist = "colorist"
        case inker = "inker"
        case editor = "editor"

        var displayName: String {
            switch self {
            case .coverArtist: return "Cover Artist"
            default: return rawValue.capitalized
            }
        }

        var pluralName: String {
            switch self {
            case .series: return "Series"
            case .publisher: return "Publishers"
            case .writer: return "Writers"
            case .artist: return "Artists"
            case .coverArtist: return "Cover Artists"
            case .colorist: return "Colorists"
            case .inker: return "Inkers"
            case .editor: return "Editors"
            }
        }
    }
}

// MARK: - GRDB Conformance
extension KnowledgeEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "metadata_knowledge"

    enum Columns {
        static let id = Column("id")
        static let type = Column("type")
        static let name = Column("name")
        static let normalizedName = Column("normalized_name")
        static let createdAt = Column("created_at")
    }

    // Custom encoding
    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.type] = type.rawValue
        container[Columns.name] = name
        container[Columns.normalizedName] = normalizedName
        container[Columns.createdAt] = createdAt
    }

    // Custom decoding called by FetchableRecord
    init(row: Row) throws {
        let typeString: String = row["type"]
        guard let type = EntryType(rawValue: typeString) else {
            throw DatabaseError.fetchFailed  // Or a specialized error
        }

        self.id = row["id"]
        self.type = type
        self.name = row["name"]
        self.normalizedName = row["normalized_name"]
        self.createdAt = row["created_at"]
    }
}
