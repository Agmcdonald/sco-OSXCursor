//
//  SeriesKnowledgeRecord.swift
//  SCO-OSXCursor
//
//  Stage 3 (learning system): one row per known series — what the app has
//  learned about it from imports and user corrections. This is the memory
//  that makes future imports of the same series identify automatically.
//

import Foundation
import GRDB

// MARK: - Series Knowledge Record
struct SeriesKnowledgeRecord: Identifiable, Codable, Equatable {
    var id: Int64?
    /// Canonical display name ("Amazing Spider-Man")
    var seriesName: String
    /// Lowercased/trimmed key — unique per series
    var normalizedName: String
    /// Publisher this series belongs to, once known
    var publisher: String?
    /// How this series is published (issues, one-shot, collected volumes)
    var bookFormat: Comic.BookFormat
    /// Normalized alternative names learned from corrections ("asm", "amazing spiderman")
    var aliases: [String]
    /// How many books of this series have been imported
    var useCount: Int
    var lastUsed: Date

    init(
        id: Int64? = nil,
        seriesName: String,
        publisher: String? = nil,
        bookFormat: Comic.BookFormat = .issue,
        aliases: [String] = [],
        useCount: Int = 1,
        lastUsed: Date = Date()
    ) {
        self.id = id
        self.seriesName = seriesName
        self.normalizedName = Self.normalize(seriesName)
        self.publisher = publisher
        self.bookFormat = bookFormat
        self.aliases = aliases
        self.useCount = useCount
        self.lastUsed = lastUsed
    }

    /// Normalization used for all matching keys
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - GRDB Conformance
extension SeriesKnowledgeRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "series_knowledge"

    enum Columns {
        static let id = Column("id")
        static let seriesName = Column("series_name")
        static let normalizedName = Column("normalized_name")
        static let publisher = Column("publisher")
        static let bookFormat = Column("book_format")
        static let aliases = Column("aliases")
        static let useCount = Column("use_count")
        static let lastUsed = Column("last_used")
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.seriesName] = seriesName
        container[Columns.normalizedName] = normalizedName
        container[Columns.publisher] = publisher
        container[Columns.bookFormat] = bookFormat.rawValue
        container[Columns.aliases] =
            (try? JSONEncoder().encode(aliases)).flatMap { String(data: $0, encoding: .utf8) }
            ?? "[]"
        container[Columns.useCount] = useCount
        container[Columns.lastUsed] = lastUsed
    }

    init(row: Row) throws {
        self.id = row["id"]
        self.seriesName = row["series_name"]
        self.normalizedName = row["normalized_name"]
        self.publisher = row["publisher"]
        self.bookFormat =
            Comic.BookFormat(rawValue: row["book_format"] ?? "issue") ?? .issue
        let aliasesJSON: String = row["aliases"] ?? "[]"
        self.aliases =
            (try? JSONDecoder().decode([String].self, from: Data(aliasesJSON.utf8))) ?? []
        self.useCount = row["use_count"] ?? 1
        self.lastUsed = row["last_used"] ?? Date()
    }
}

// MARK: - Correction Record
/// One row per user correction — the audit trail the learning system feeds on.
struct CorrectionRecord: Identifiable, Codable, Equatable {
    var id: Int64?
    var originalSeries: String?
    var correctedSeries: String?
    var originalPublisher: String?
    var correctedPublisher: String?
    var sourceFileName: String?
    var createdAt: Date

    init(
        id: Int64? = nil,
        originalSeries: String? = nil,
        correctedSeries: String? = nil,
        originalPublisher: String? = nil,
        correctedPublisher: String? = nil,
        sourceFileName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.originalSeries = originalSeries
        self.correctedSeries = correctedSeries
        self.originalPublisher = originalPublisher
        self.correctedPublisher = correctedPublisher
        self.sourceFileName = sourceFileName
        self.createdAt = createdAt
    }
}

extension CorrectionRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "correction_history"

    func encode(to container: inout PersistenceContainer) {
        container[Column("id")] = id
        container[Column("original_series")] = originalSeries
        container[Column("corrected_series")] = correctedSeries
        container[Column("original_publisher")] = originalPublisher
        container[Column("corrected_publisher")] = correctedPublisher
        container[Column("source_filename")] = sourceFileName
        container[Column("created_at")] = createdAt
    }

    init(row: Row) throws {
        self.id = row["id"]
        self.originalSeries = row["original_series"]
        self.correctedSeries = row["corrected_series"]
        self.originalPublisher = row["original_publisher"]
        self.correctedPublisher = row["corrected_publisher"]
        self.sourceFileName = row["source_filename"]
        self.createdAt = row["created_at"] ?? Date()
    }
}
