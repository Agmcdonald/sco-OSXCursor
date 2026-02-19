//
//  DatabaseManager.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/7/25.
//

import Foundation
import GRDB

// MARK: - Database Manager
final class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?

    private init() {
        setupDatabase()
    }

    // MARK: - Setup

    private func setupDatabase() {
        do {
            let dbPath = try getDatabasePath()
            print("[DatabaseManager] 📁 Database path: \(dbPath.path)")

            dbQueue = try DatabaseQueue(path: dbPath.path)
            try migrator.migrate(dbQueue!)

            print("[DatabaseManager] ✅ Database initialized successfully")

            // Log table info
            try logDatabaseInfo()

        } catch {
            print("[DatabaseManager] ❌ Database setup error: \(error)")
        }
    }

    private func getDatabasePath() throws -> URL {
        let fileManager = FileManager.default

        // Get Application Support directory
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        // Create app folder
        let appFolder = appSupport.appendingPathComponent("SuperComicOrganizer")
        try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)

        return appFolder.appendingPathComponent("comics.db")
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Version 1: Initial schema
        migrator.registerMigration("v1_initial_schema") { db in
            print("[DatabaseManager] 🔄 Running migration: v1_initial_schema")

            try self.createComicsTable(db)
            try self.createPublisherMappingsTable(db)
            try self.createActivityLogTable(db)
            try self.createIndexes(db)

            print("[DatabaseManager] ✅ Migration v1_initial_schema complete")
        }

        // Version 2: Add preferred_transition column to comics table
        migrator.registerMigration("v2_add_preferred_transition") { db in
            print("[DatabaseManager] 🔄 Running migration: v2_add_preferred_transition")

            // Add column if it doesn't exist
            // GRDB will handle the case where column already exists gracefully
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "preferred_transition", .text)
                    }
                    print("[DatabaseManager] ✅ Added preferred_transition column")
                } catch {
                    // Column might already exist, which is fine
                    print(
                        "[DatabaseManager] ℹ️ preferred_transition column may already exist: \(error.localizedDescription)"
                    )
                }
            }

            print("[DatabaseManager] ✅ Migration v2_add_preferred_transition complete")
        }

        // Version 3: Add metadata_knowledge table
        migrator.registerMigration("v3_knowledge_schema") { db in
            print("[DatabaseManager] 🔄 Running migration: v3_knowledge_schema")

            try db.create(table: "metadata_knowledge") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull()  // "series", "writer", "artist"
                t.column("name", .text).notNull()
                t.column("normalized_name", .text).notNull()
                t.column("created_at", .datetime).notNull()

                // Unique constraint on (type, normalized_name)
                t.uniqueKey(["type", "normalized_name"])
            }

            // Index for fast searching by type and name pattern
            try db.create(
                index: "idx_knowledge_type_name", on: "metadata_knowledge",
                columns: ["type", "name"])

            print("[DatabaseManager] ✅ Migration v3_knowledge_schema complete")
        }

        return migrator
    }

    // MARK: - Table Creation

    private func createComicsTable(_ db: Database) throws {
        try db.create(table: "comics") { t in
            t.column("id", .text).primaryKey()
            t.column("file_path", .text).notNull()
            t.column("file_name", .text).notNull()
            t.column("bookmark_data", .blob)  // Security-scoped bookmark

            // Metadata
            t.column("title", .text)
            t.column("publisher", .text)
            t.column("series", .text)
            t.column("issue_number", .text)
            t.column("volume", .integer)
            t.column("year", .integer)
            t.column("writer", .text)
            t.column("artist", .text)
            t.column("cover_artist", .text)
            t.column("summary", .text)

            // Cover & Visual
            t.column("cover_image_data", .blob)

            // Status & Progress
            t.column("status", .text).notNull()
            t.column("current_page", .integer).notNull().defaults(to: 0)
            t.column("total_pages", .integer).notNull().defaults(to: 0)
            t.column("last_read_date", .datetime)

            // Organization
            t.column("tags", .text)  // JSON array
            t.column("rating", .integer)
            t.column("is_favorite", .boolean).notNull().defaults(to: false)
            t.column("preferred_transition", .text)

            // File Info
            t.column("file_size", .integer).notNull()
            t.column("file_type", .text).notNull()

            // Timestamps
            t.column("date_added", .datetime).notNull()
            t.column("date_modified", .datetime).notNull()
        }

        print("[DatabaseManager] ✅ Created comics table")
    }

    private func createPublisherMappingsTable(_ db: Database) throws {
        try db.create(table: "publisher_mappings") { t in
            t.column("id", .text).primaryKey()
            t.column("publisher_name", .text).notNull().unique()
            t.column("aliases", .text).notNull()  // JSON array
            t.column("keywords", .text).notNull()  // JSON array
            t.column("folder_name", .text).notNull()
            t.column("times_used", .integer).notNull().defaults(to: 0)
            t.column("confidence", .double).notNull().defaults(to: 0.5)
            t.column("user_confirmed", .boolean).notNull().defaults(to: false)
            t.column("last_used", .datetime)
        }

        print("[DatabaseManager] ✅ Created publisher_mappings table")
    }

    private func createActivityLogTable(_ db: Database) throws {
        try db.create(table: "activity_log") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("comic_id", .text)
            t.column("action", .text).notNull()
            t.column("old_value", .text)
            t.column("new_value", .text)
            t.column("timestamp", .datetime).notNull()
            t.column("user_confirmed", .boolean).notNull().defaults(to: false)
        }

        print("[DatabaseManager] ✅ Created activity_log table")
    }

    private func createIndexes(_ db: Database) throws {
        // Comics indexes for fast searching/filtering
        try db.create(index: "idx_comics_publisher", on: "comics", columns: ["publisher"])
        try db.create(index: "idx_comics_series", on: "comics", columns: ["series"])
        try db.create(index: "idx_comics_status", on: "comics", columns: ["status"])
        try db.create(index: "idx_comics_year", on: "comics", columns: ["year"])
        try db.create(index: "idx_comics_date_added", on: "comics", columns: ["date_added"])

        // Activity log index for querying by comic
        try db.create(index: "idx_activity_comic", on: "activity_log", columns: ["comic_id"])
        try db.create(index: "idx_activity_timestamp", on: "activity_log", columns: ["timestamp"])

        print("[DatabaseManager] ✅ Created indexes")
    }

    // MARK: - Database Info

    private func logDatabaseInfo() throws {
        guard let dbQueue = dbQueue else { return }

        try dbQueue.read { db in
            let tables = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            print("[DatabaseManager] 📊 Tables: \(tables.joined(separator: ", "))")

            // Get comics count
            let comicsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM comics") ?? 0
            print("[DatabaseManager] 📚 Comics in database: \(comicsCount)")
        }
    }

    // MARK: - CRUD Operations

    /// Save or update a comic in the database
    func saveComic(_ comic: Comic) async throws {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        try await dbQueue.write { db in
            try comic.save(db)
            print("[DatabaseManager] ✅ Saved comic: \(comic.fileName)")
        }
    }

    /// Fetch all comics from database
    func fetchAllComics() async throws -> [Comic] {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await dbQueue.read { db in
            let comics = try Comic.fetchAll(db)
            print("[DatabaseManager] 📚 Fetched \(comics.count) comics from database")
            return comics
        }
    }

    /// Fetch comics with specific status
    func fetchComics(with status: Comic.Status) async throws -> [Comic] {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await dbQueue.read { db in
            try Comic
                .filter(Column("status") == status.rawValue)
                .fetchAll(db)
        }
    }

    /// Update existing comic
    func updateComic(_ comic: Comic) async throws {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        try await dbQueue.write { db in
            try comic.update(db)
            print("[DatabaseManager] ✅ Updated comic: \(comic.fileName)")
        }
    }

    /// Delete comic from database
    func deleteComic(withID id: UUID) async throws {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        try await dbQueue.write { db in
            try Comic.deleteOne(db, key: id.uuidString)
            print("[DatabaseManager] 🗑️ Deleted comic with ID: \(id)")
        }
    }

    /// Search comics by title, publisher, or series
    func searchComics(query: String) async throws -> [Comic] {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await dbQueue.read { db in
            let pattern = "%\(query)%"
            return
                try Comic
                .filter(
                    Column("title").like(pattern) || Column("publisher").like(pattern)
                        || Column("series").like(pattern) || Column("file_name").like(pattern)
                )
                .fetchAll(db)
        }
    }

    /// Check if comic exists in database
    func comicExists(withID id: UUID) async throws -> Bool {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await dbQueue.read { db in
            try Comic.exists(db, key: id.uuidString)
        }
    }

    /// Fetch a single comic by ID from the database
    func fetchComic(id: UUID) async throws -> Comic? {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await dbQueue.read { db in
            try Comic.fetchOne(db, key: id.uuidString)
        }
    }

    /// Get count of all comics
    func getComicCount() async throws -> Int {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await dbQueue.read { db in
            try Comic.fetchCount(db)
        }
    }
}

// MARK: - Knowledge CRUD

extension DatabaseManager {
    /// Fetch all knowledge entries of a specific type
    func fetchKnowledgeEntries(type: KnowledgeEntry.EntryType) async throws -> [KnowledgeEntry] {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }

        return try await dbQueue.read { db in
            try KnowledgeEntry
                .filter(Column("type") == type.rawValue)
                .order(Column("name"))
                .fetchAll(db)
        }
    }

    /// Save a knowledge entry (ignores if duplicate exists)
    func saveKnowledgeEntry(_ entry: KnowledgeEntry) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }

        try await dbQueue.write { db in
            try entry.insert(db, onConflict: .ignore)
        }
    }

    /// Delete a knowledge entry
    func deleteKnowledgeEntry(_ entry: KnowledgeEntry) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }

        try await dbQueue.write { db in
            try entry.delete(db)
        }
    }

    /// Check if a knowledge entry exists
    func knowledgeEntryExists(type: KnowledgeEntry.EntryType, name: String) async throws -> Bool {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }

        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return try await dbQueue.read { db in
            try KnowledgeEntry
                .filter(Column("type") == type.rawValue && Column("normalized_name") == normalized)
                .fetchCount(db) > 0
        }
    }

    /// Search knowledge entries for autocomplete
    func searchKnowledge(type: KnowledgeEntry.EntryType, query: String) async throws -> [String] {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }

        return try await dbQueue.read { db in
            let pattern = "%\(query)%"
            let entries =
                try KnowledgeEntry
                .filter(Column("type") == type.rawValue && Column("name").like(pattern))
                .order(Column("name"))
                .limit(10)
                .fetchAll(db)
            return entries.map { $0.name }
        }
    }
}

// End of DatabaseManager

// MARK: - Database Errors
enum DatabaseError: LocalizedError {

    case notInitialized
    case saveFailed
    case fetchFailed
    case updateFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database not initialized"
        case .saveFailed:
            return "Failed to save to database"
        case .fetchFailed:
            return "Failed to fetch from database"
        case .updateFailed:
            return "Failed to update database"
        case .deleteFailed:
            return "Failed to delete from database"
        }
    }
}
