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

        /// Whether this type names an individual person (a creator credit).
        /// Creator credits can list several people in one field ("A, B & C")
        /// and should be stored as one Knowledge entry per person. Series and
        /// publisher names are single values and must never be split (e.g.
        /// "Boom! Studios" or a series with a comma in its title).
        var isCreatorType: Bool {
            switch self {
            case .series, .publisher: return false
            case .writer, .artist, .coverArtist, .colorist, .inker, .editor: return true
            }
        }
    }
}

// MARK: - Credit Name Splitting
extension KnowledgeEntry {
    /// Separators ComicVine and ComicInfo.xml use to join multiple creators
    /// into one field. Kept in sync with the de-dupe logic in KnowledgeDetailView.
    private static let creditSeparators = CharacterSet(charactersIn: ",&;")

    /// Split a combined credit field ("Claire Roe, J. Bone & Nicola Scott")
    /// into individual, trimmed, de-duplicated names. Order is preserved and
    /// the first spelling/casing seen for a name wins. Returns `[value]` when
    /// there is nothing to split.
    static func splitCreditNames(_ value: String?) -> [String] {
        guard let value else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for part in value.components(separatedBy: creditSeparators) {
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if seen.insert(name.lowercased()).inserted {
                result.append(name)
            }
        }
        return result
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
