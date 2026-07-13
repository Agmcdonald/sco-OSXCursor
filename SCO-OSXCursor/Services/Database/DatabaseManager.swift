//
//  DatabaseManager.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/7/25.
//

import Foundation
import GRDB
import os

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
            AppLog.database.debug("[DatabaseManager] 📁 Database path: \(dbPath.path)")

            dbQueue = try DatabaseQueue(path: dbPath.path)
            try migrator.migrate(dbQueue!)

            AppLog.database.info("[DatabaseManager] ✅ Database initialized successfully")

            // Log table info
            try logDatabaseInfo()

        } catch {
            AppLog.database.error("[DatabaseManager] ❌ Database setup error: \(error)")
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
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v1_initial_schema")

            try self.createComicsTable(db)
            try self.createPublisherMappingsTable(db)
            try self.createActivityLogTable(db)
            try self.createIndexes(db)

            AppLog.database.info("[DatabaseManager] ✅ Migration v1_initial_schema complete")
        }

        // Version 2: Add preferred_transition column to comics table
        migrator.registerMigration("v2_add_preferred_transition") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v2_add_preferred_transition")

            // Add column if it doesn't exist
            // GRDB will handle the case where column already exists gracefully
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "preferred_transition", .text)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added preferred_transition column")
                } catch {
                    // Column might already exist, which is fine
                    AppLog.database.error("[DatabaseManager] ℹ️ preferred_transition column may already exist: \(error.localizedDescription)")
                }
            }

            AppLog.database.info("[DatabaseManager] ✅ Migration v2_add_preferred_transition complete")
        }

        // Version 3: Add metadata_knowledge table
        migrator.registerMigration("v3_knowledge_schema") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v3_knowledge_schema")

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

            AppLog.database.info("[DatabaseManager] ✅ Migration v3_knowledge_schema complete")
        }

        migrator.registerMigration("v4_reading_list") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v4_reading_list")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "is_on_reading_list", .boolean).notNull().defaults(to: false)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added is_on_reading_list column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ is_on_reading_list column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v4_reading_list complete")
        }

        // Version 5: Expand Creator Metadata
        migrator.registerMigration("v5_expand_creators") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v5_expand_creators")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "colorist", .text)
                        t.add(column: "inker", .text)
                        t.add(column: "editor", .text)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added colorist, inker, and editor columns")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ creator columns may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v5_expand_creators complete")
        }

        // Version 6: Publisher banner images
        migrator.registerMigration("v6_publisher_banners") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v6_publisher_banners")
            if try db.tableExists("publisher_mappings") {
                do {
                    try db.alter(table: "publisher_mappings") { t in
                        t.add(column: "image_data", .blob)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added image_data column to publisher_mappings")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ image_data column may already exist: \(error)")
                }
            } else {
                // publisher_mappings may not exist on all devices; create it now
                try db.create(table: "publisher_banners", ifNotExists: true) { t in
                    t.column("publisher_name", .text).primaryKey()
                    t.column("image_data", .blob)
                }
                AppLog.database.info("[DatabaseManager] ✅ Created publisher_banners fallback table")
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v6_publisher_banners complete")
        }

        // Version 7: Content Ratings
        migrator.registerMigration("v7_content_ratings") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v7_content_ratings")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "content_rating", .integer).notNull().defaults(to: 0)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added content_rating column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ content_rating column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v7_content_ratings complete")
        }

        // Version 8: Home Library — needs_attention flag
        migrator.registerMigration("v8_needs_attention") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v8_needs_attention")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "needs_attention", .boolean).notNull().defaults(to: false)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added needs_attention column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ needs_attention column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v8_needs_attention complete")
        }

        // Version 9: Reading Style — per-book reading style preference
        migrator.registerMigration("v9_reading_style") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v9_reading_style")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "reading_style", .text)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added reading_style column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ reading_style column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v9_reading_style complete")
        }

        // Version 10: EPUB support — per-book font size preference
        migrator.registerMigration("v10_epub_support") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v10_epub_support")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "epub_font_size", .integer)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added epub_font_size column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ epub_font_size column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v10_epub_support complete")
        }

        migrator.registerMigration("v11_book_format") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v11_book_format")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "book_format", .text).notNull().defaults(to: "issue")
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added book_format column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ book_format column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v11_book_format complete")
        }

        // Version 12: Learning system — series knowledge + correction history
        migrator.registerMigration("v12_series_knowledge") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v12_series_knowledge")

            try db.create(table: "series_knowledge", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("series_name", .text).notNull()
                t.column("normalized_name", .text).notNull().unique()
                t.column("publisher", .text)
                t.column("book_format", .text).notNull().defaults(to: "issue")
                t.column("aliases", .text).notNull().defaults(to: "[]")
                t.column("use_count", .integer).notNull().defaults(to: 1)
                t.column("last_used", .datetime).notNull()
            }

            try db.create(table: "correction_history", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("original_series", .text)
                t.column("corrected_series", .text)
                t.column("original_publisher", .text)
                t.column("corrected_publisher", .text)
                t.column("source_filename", .text)
                t.column("created_at", .datetime).notNull()
            }

            // Seed from the existing library so the learning system starts
            // with everything already imported
            if try db.tableExists("comics") {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO series_knowledge
                            (series_name, normalized_name, publisher, book_format,
                             aliases, use_count, last_used)
                        SELECT series, LOWER(TRIM(series)), MAX(publisher), 'issue',
                               '[]', COUNT(*), datetime('now')
                        FROM comics
                        WHERE series IS NOT NULL AND TRIM(series) <> ''
                        GROUP BY LOWER(TRIM(series))
                        """)
                AppLog.database.info("[DatabaseManager] ✅ Seeded series_knowledge from existing library")
            }

            AppLog.database.info("[DatabaseManager] ✅ Migration v12_series_knowledge complete")
        }

        // Version 13: EPUBs are prose ebooks, not comic issues
        migrator.registerMigration("v13_ebook_format") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v13_ebook_format")
            if try db.tableExists("comics"), try db.tableHasColumn("comics", named: "book_format") {
                try db.execute(
                    sql: "UPDATE comics SET book_format = 'ebook' WHERE file_type = 'epub'")
                AppLog.database.info("[DatabaseManager] ✅ Reclassified EPUB books as eBook format")
            }
            if try db.tableExists("series_knowledge") {
                // Fix learned entries created from EPUB imports
                try db.execute(
                    sql: """
                        UPDATE series_knowledge SET book_format = 'ebook'
                        WHERE normalized_name IN (
                            SELECT DISTINCT LOWER(TRIM(series)) FROM comics
                            WHERE file_type = 'epub' AND series IS NOT NULL
                        )
                        """)
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v13_ebook_format complete")
        }

        // Version 14: per-book EPUB theme — the Comic model and the Reader
        // Settings sheet have had epubTheme since v10-era, but the column was
        // never added, so theme overrides silently vanished on relaunch.
        migrator.registerMigration("v14_epub_theme") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v14_epub_theme")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "epub_theme", .text)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added epub_theme column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ epub_theme column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v14_epub_theme complete")
        }

        // Version 15: per-book zoom memory — remembered pinch-zoom scale,
        // reapplied on every page and on reopen. NULL = no zoom (1×).
        migrator.registerMigration("v15_zoom_scale") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v15_zoom_scale")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "zoom_scale", .double)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added zoom_scale column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ zoom_scale column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v15_zoom_scale complete")
        }

        // Version 16: ComicVine metadata — matched volume/issue ids, the
        // last-fetched timestamp (so a book is never auto re-fetched), and a
        // JSON blob of candidate matches for ambiguous searches.
        migrator.registerMigration("v16_comicvine_metadata") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v16_comicvine_metadata")
            if try db.tableExists("comics") {
                let columns: [(String, Database.ColumnType)] = [
                    ("comicvine_volume_id", .integer),
                    ("comicvine_issue_id", .integer),
                    ("metadata_fetched_at", .datetime),
                    ("metadata_candidates", .text),
                ]
                for (name, type) in columns {
                    do {
                        try db.alter(table: "comics") { t in t.add(column: name, type) }
                        AppLog.database.info("[DatabaseManager] ✅ Added \(name) column")
                    } catch {
                        AppLog.database.error("[DatabaseManager] ℹ️ \(name) column may already exist: \(error.localizedDescription)")
                    }
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v16_comicvine_metadata complete")
        }

        // Version 17: Split combined creator credits in the Knowledge Base.
        // ComicVine imports joined multiple people into one field ("A, B & C")
        // which were stored as a single knowledge entry. Split those into one
        // entry per person and remove the combined rows. Series/publisher are
        // left untouched.
        migrator.registerMigration("v17_split_creator_credits") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v17_split_creator_credits")
            guard try db.tableExists("metadata_knowledge") else {
                AppLog.database.info("[DatabaseManager] ℹ️ metadata_knowledge missing — skipping v17")
                return
            }

            let creatorTypes = KnowledgeEntry.EntryType.allCases
                .filter { $0.isCreatorType }
                .map { $0.rawValue }

            var splitCount = 0
            for type in creatorTypes {
                // Snapshot rows first so we don't mutate while iterating.
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT id, name, created_at FROM metadata_knowledge WHERE type = ?",
                    arguments: [type])

                for row in rows {
                    let id: Int64 = row["id"]
                    let name: String = row["name"]
                    let createdAt: String? = row["created_at"]
                    let parts = KnowledgeEntry.splitCreditNames(name)

                    // Nothing to fix if it's already a single clean name.
                    guard parts.count > 1 || (parts.count == 1 && parts[0] != name) else { continue }

                    for part in parts {
                        let normalized = part.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                        try db.execute(
                            sql: """
                                INSERT OR IGNORE INTO metadata_knowledge
                                    (type, name, normalized_name, created_at)
                                VALUES (?, ?, ?, ?)
                                """,
                            arguments: [type, part, normalized, createdAt])
                    }

                    // Remove the combined row (unless a single part maps back to it,
                    // in which case the INSERT OR IGNORE above already kept it).
                    if !(parts.count == 1 && parts[0] == name) {
                        try db.execute(
                            sql: "DELETE FROM metadata_knowledge WHERE id = ?",
                            arguments: [id])
                    }
                    splitCount += 1
                }
            }

            AppLog.database.info(
                "[DatabaseManager] ✅ Migration v17_split_creator_credits complete — \(splitCount) combined entries split")
        }

        // Version 18: Default page transition to "None" for all books.
        // Clears every per-book transition override so all existing books fall
        // through to the (now "None") global default. New per-book preferences
        // set afterwards are still respected.
        migrator.registerMigration("v18_default_transition_none") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v18_default_transition_none")
            if try db.tableExists("comics") {
                let cleared = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM comics WHERE preferred_transition IS NOT NULL") ?? 0
                try db.execute(sql: "UPDATE comics SET preferred_transition = NULL")
                AppLog.database.info(
                    "[DatabaseManager] ✅ Migration v18_default_transition_none complete — cleared \(cleared) per-book overrides")
            }
        }

        // Version 19: Per-book thumbnail-bar position override (vertical books).
        // Lets a vertical-scroll book remember a Bottom/Left/Right thumbnail rail
        // independently of the global default.
        migrator.registerMigration("v19_thumbnail_bar_position") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v19_thumbnail_bar_position")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "thumbnail_bar_position", .text)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added thumbnail_bar_position column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ thumbnail_bar_position column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v19_thumbnail_bar_position complete")
        }

        // Version 20: Folders (collections). A *virtual* organizational layer —
        // membership lives in the comic_folders junction table and never moves
        // files on disk. Many-to-many: a book can live in any number of folders.
        migrator.registerMigration("v20_folders") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v20_folders")

            try db.create(table: "folders", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                // Self-reference enables future nesting; flat in the v1 UI.
                t.column("parent_id", .text).references("folders", onDelete: .cascade)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("color", .text)
                t.column("icon", .text)
                t.column("created_at", .datetime).notNull()
                t.column("date_modified", .datetime).notNull()
            }

            try db.create(table: "comic_folders", ifNotExists: true) { t in
                t.column("comic_id", .text).notNull()
                    .references("comics", onDelete: .cascade)
                t.column("folder_id", .text).notNull()
                    .references("folders", onDelete: .cascade)
                t.column("added_at", .datetime).notNull()
                t.primaryKey(["comic_id", "folder_id"])
            }

            try db.create(
                index: "idx_comic_folders_folder", on: "comic_folders",
                columns: ["folder_id"])
            try db.create(
                index: "idx_comic_folders_comic", on: "comic_folders",
                columns: ["comic_id"])

            AppLog.database.info("[DatabaseManager] ✅ Migration v20_folders complete")
        }

        // Version 21: Folder covers. Lets a folder be illustrated by a custom
        // picture (cover_image_data) or a single chosen member book
        // (cover_comic_id). When both are nil the card keeps the default 2×2
        // collage of recent members.
        migrator.registerMigration("v21_folder_cover") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v21_folder_cover")
            if try db.tableExists("folders") {
                let columns = try db.columns(in: "folders").map(\.name)
                try db.alter(table: "folders") { t in
                    if !columns.contains("cover_image_data") {
                        t.add(column: "cover_image_data", .blob)
                    }
                    if !columns.contains("cover_comic_id") {
                        t.add(column: "cover_comic_id", .text)
                    }
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v21_folder_cover complete")
        }

        // Version 22: ComicVine fetch undo. Stores a JSON snapshot of the
        // metadata fields as they were just before the last fetch was applied,
        // so a wrong match can be reverted (metadata_fetched_at gates
        // re-fetching, so users need an escape hatch).
        migrator.registerMigration("v22_metadata_backup") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v22_metadata_backup")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "metadata_backup", .text)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added metadata_backup column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ metadata_backup column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v22_metadata_backup complete")
        }

        migrator.registerMigration("v23_story_arcs") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v23_story_arcs")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "story_arcs", .blob)  // JSON [String], like tags
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added story_arcs column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ story_arcs column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v23_story_arcs complete")
        }

        migrator.registerMigration("v24_isbn") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v24_isbn")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "isbn", .text)  // Ebooks only (Open Library)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added isbn column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ isbn column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v24_isbn complete")
        }

        migrator.registerMigration("v25_metadata_source") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v25_metadata_source")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "metadata_source", .text)
                    }
                    // Everything fetched before this migration came from
                    // ComicVine (the only provider that existed).
                    try db.execute(
                        sql: """
                            UPDATE comics SET metadata_source = 'ComicVine'
                            WHERE metadata_fetched_at IS NOT NULL
                               OR comicvine_volume_id IS NOT NULL
                            """)
                    AppLog.database.info("[DatabaseManager] ✅ Added metadata_source column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ metadata_source column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v25_metadata_source complete")
        }

        migrator.registerMigration("v26_epub_locator") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v26_epub_locator")
            if try db.tableExists("comics") {
                let columns: [(String, Database.ColumnType)] = [
                    ("epub_chapter_index", .integer),
                    ("epub_chapter_progress", .double),
                    ("epub_locator_fragment", .text),
                    ("epub_locator_element", .text),
                    ("epub_locator_progress", .double),
                ]
                for (name, type) in columns {
                    do {
                        try db.alter(table: "comics") { t in
                            t.add(column: name, type)
                        }
                        AppLog.database.info("[DatabaseManager] ✅ Added \(name) column")
                    } catch {
                        AppLog.database.error("[DatabaseManager] ℹ️ \(name) column may already exist: \(error.localizedDescription)")
                    }
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v26_epub_locator complete")
        }

        migrator.registerMigration("v27_pdf_book_reader") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v27_pdf_book_reader")
            if try db.tableExists("comics") {
                do {
                    try db.alter(table: "comics") { t in
                        t.add(column: "pdf_reads_as_book", .boolean).defaults(to: false)
                    }
                    AppLog.database.info("[DatabaseManager] ✅ Added pdf_reads_as_book column")
                } catch {
                    AppLog.database.error("[DatabaseManager] ℹ️ pdf_reads_as_book column may already exist: \(error.localizedDescription)")
                }
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v27_pdf_book_reader complete")
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
            t.column("colorist", .text)
            t.column("inker", .text)
            t.column("editor", .text)
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
            t.column("content_rating", .integer).notNull().defaults(to: 0)
            t.column("is_favorite", .boolean).notNull().defaults(to: false)
            t.column("preferred_transition", .text)

            // File Info
            t.column("file_size", .integer).notNull()
            t.column("file_type", .text).notNull()

            // Timestamps
            t.column("date_added", .datetime).notNull()
            t.column("date_modified", .datetime).notNull()
        }

        AppLog.database.info("[DatabaseManager] ✅ Created comics table")
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

        AppLog.database.info("[DatabaseManager] ✅ Created publisher_mappings table")
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

        AppLog.database.info("[DatabaseManager] ✅ Created activity_log table")
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

        AppLog.database.info("[DatabaseManager] ✅ Created indexes")
    }

    // MARK: - Database Info

    private func logDatabaseInfo() throws {
        guard let dbQueue = dbQueue else { return }

        try dbQueue.read { db in
            let tables = try String.fetchAll(
                db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            AppLog.database.debug("[DatabaseManager] 📊 Tables: \(tables.joined(separator: ", "))")

            // Get comics count
            let comicsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM comics") ?? 0
            AppLog.database.debug("[DatabaseManager] 📚 Comics in database: \(comicsCount)")
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
            AppLog.database.info("[DatabaseManager] ✅ Saved comic: \(comic.fileName)")
        }
    }

    /// Fetch all comics from database
    func fetchAllComics() async throws -> [Comic] {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await dbQueue.read { db in
            let comics = try Comic.fetchAll(db)
            AppLog.database.debug("[DatabaseManager] 📚 Fetched \(comics.count) comics from database")
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

    /// Fetch comics with specific content rating
    func fetchComics(withContentRating rating: Comic.ContentRating) async throws -> [Comic] {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        return try await dbQueue.read { db in
            try Comic
                .filter(Column("content_rating") == rating.rawValue)
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
            AppLog.database.info("[DatabaseManager] ✅ Updated comic: \(comic.fileName)")
        }
    }

    /// Delete comic from database
    func deleteComic(withID id: UUID) async throws {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }

        try await dbQueue.write { db in
            try Comic.deleteOne(db, key: id.uuidString)
            AppLog.database.info("[DatabaseManager] 🗑️ Deleted comic with ID: \(id)")
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

    /// A consistent snapshot of the catalog as bytes, for the backup/export
    /// feature. Reading inside `read` serializes against any in-flight write on
    /// the (serialized) queue, so the on-disk file is quiescent when copied.
    func makeBackupData() async throws -> Data {
        guard let dbQueue = dbQueue else {
            throw DatabaseError.notInitialized
        }
        let path = try getDatabasePath()
        return try await dbQueue.read { _ in
            try Data(contentsOf: path)
        }
    }

    /// Replaces the live database with a backup snapshot previously produced
    /// by `makeBackupData()`, then re-runs migrations and reopens the
    /// connection. Callers must reload any in-memory state afterwards
    /// (e.g. `LibraryViewModel.loadComics()`).
    func restoreFromBackup(_ data: Data) async throws {
        // Cheap sanity check before touching the live file: every SQLite
        // database starts with this 16-byte header string.
        let magic = Data("SQLite format 3\0".utf8)
        guard data.count > magic.count, data.prefix(magic.count) == magic else {
            throw DatabaseError.invalidBackupFile
        }

        let path = try getDatabasePath()

        // Close the current connection so the file can be swapped safely.
        dbQueue = nil

        do {
            try data.write(to: path, options: .atomic)
            // Remove stale sidecar files left over from the previous database.
            let fm = FileManager.default
            try? fm.removeItem(atPath: path.path + "-wal")
            try? fm.removeItem(atPath: path.path + "-shm")

            let newQueue = try DatabaseQueue(path: path.path)
            try migrator.migrate(newQueue)
            dbQueue = newQueue
            AppLog.database.info("[DatabaseManager] ✅ Restored database from backup")
        } catch {
            // Best effort: reopen whatever is on disk so the app keeps working.
            dbQueue = try? DatabaseQueue(path: path.path)
            AppLog.database.error("[DatabaseManager] ❌ Restore failed: \(error)")
            throw error
        }
    }
}

// MARK: - Maintenance

extension DatabaseManager {
    /// Size in bytes of the database file on disk.
    func databaseFileSizeBytes() throws -> Int64 {
        let path = try getDatabasePath()
        let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
        return (attrs[.size] as? Int64) ?? 0
    }

    /// Runs SQLite's built-in integrity check. Returns "ok" when the file is
    /// healthy, otherwise a description of the corruption found.
    func integrityCheck() async throws -> String {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        return try await dbQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? "unknown"
        }
    }

    /// Rebuilds all indexes and reclaims free space (REINDEX + VACUUM).
    /// VACUUM cannot run inside a transaction, so this uses the
    /// no-transaction write entry point on a background task.
    func optimizeDatabase() async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        try await Task.detached(priority: .utility) {
            try dbQueue.writeWithoutTransaction { db in
                try db.execute(sql: "REINDEX")
                try db.execute(sql: "VACUUM")
            }
        }.value
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

    /// Populate the Knowledge Base from a comic's metadata — series, publisher,
    /// and every creator credit (each split into individual people). This is the
    /// single source of truth for comic → KB sync, shared by the manual inspector
    /// save and every automated import path (including ComicVine enrichment), so
    /// the two can never drift apart again. Idempotent: duplicate names are
    /// ignored via the table's UNIQUE(type, normalized_name) constraint.
    func syncKnowledge(from comic: Comic) async {
        let fields: [(String?, KnowledgeEntry.EntryType)] = [
            (comic.series, .series),
            (comic.publisher, .publisher),
            (comic.writer, .writer),
            (comic.artist, .artist),
            (comic.coverArtist, .coverArtist),
            (comic.colorist, .colorist),
            (comic.inker, .inker),
            (comic.editor, .editor),
        ]
        for (value, type) in fields {
            // Creator credits can list several people in one field
            // ("Claire Roe, J. Bone & Nicola Scott") — store one entry per
            // person. Series/publisher are single values and stay intact.
            let names = type.isCreatorType
                ? KnowledgeEntry.splitCreditNames(value)
                : [value?.trimmingCharacters(in: .whitespacesAndNewlines)]
                    .compactMap { $0 }.filter { !$0.isEmpty }
            for name in names {
                try? await saveKnowledgeEntry(KnowledgeEntry(type: type, name: name))
            }
        }
    }

    /// One-time repair for libraries built before comic → KB creator sync
    /// existed. Older import paths (notably ComicVine enrichment) wrote creator
    /// credits into comic metadata but never into the Knowledge Base, so the KB
    /// was missing writers/artists/etc. for imported books. Re-sync every comic
    /// once. Idempotent and guarded by a UserDefaults flag, so it runs at most
    /// once per install and is a cheap no-op on every launch thereafter.
    func backfillKnowledgeIfNeeded() async {
        let key = "didBackfillKnowledgeCreatorsV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard let comics = try? await fetchAllComics() else { return }
        for comic in comics {
            await syncKnowledge(from: comic)
        }
        UserDefaults.standard.set(true, forKey: key)
        AppLog.database.info(
            "[DatabaseManager] ✅ Knowledge Base creator backfill complete (\(comics.count) comics)")
    }

    /// Delete a knowledge entry
    func deleteKnowledgeEntry(_ entry: KnowledgeEntry) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }

        try await dbQueue.write { db in
            _ = try entry.delete(db)
        }
    }

    /// Check if a knowledge entry exists
    /// Delete a knowledge entry by type + name (used to prune suggestions
    /// that no longer match any book, e.g. a misspelled publisher).
    func deleteKnowledgeEntry(type: KnowledgeEntry.EntryType, name: String) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        _ = try await dbQueue.write { db in
            try KnowledgeEntry
                .filter(KnowledgeEntry.Columns.type == type.rawValue)
                .filter(KnowledgeEntry.Columns.normalizedName == normalized)
                .deleteAll(db)
        }
    }

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

// MARK: - Publisher Banner CRUD

extension DatabaseManager {
    /// Upsert a banner image for a named publisher.
    func savePublisherBanner(name: String, data: Data) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        try await dbQueue.write { db in
            // Try publisher_mappings first; fall back to stand-alone table
            if try db.tableExists("publisher_mappings") {
                if try db.tableHasColumn("publisher_mappings", named: "image_data") {
                    let existing = try Row.fetchOne(
                        db,
                        sql:
                            "SELECT publisher_name FROM publisher_mappings WHERE publisher_name = ?",
                        arguments: [name])
                    if existing != nil {
                        try db.execute(
                            sql:
                                "UPDATE publisher_mappings SET image_data = ? WHERE publisher_name = ?",
                            arguments: [data, name])
                    } else {
                        let id = UUID().uuidString
                        let insertSQL =
                            "INSERT INTO publisher_mappings"
                            + " (id, publisher_name, aliases, keywords, folder_name, times_used,"
                            + "  confidence, user_confirmed, image_data)"
                            + " VALUES (?, ?, '[]', '[]', ?, 0, 0.5, 0, ?)"
                        try db.execute(sql: insertSQL, arguments: [id, name, name, data])
                    }
                    return
                }
            }
            // Fallback table
            try db.execute(
                sql:
                    "INSERT OR REPLACE INTO publisher_banners (publisher_name, image_data) VALUES (?, ?)",
                arguments: [name, data])
        }
    }

    /// Load the banner image for a named publisher, returns nil if none set.
    func loadPublisherBanner(name: String) async throws -> Data? {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        return try await dbQueue.read { db in
            if try db.tableExists("publisher_mappings"),
                try db.tableHasColumn("publisher_mappings", named: "image_data")
            {
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT image_data FROM publisher_mappings WHERE publisher_name = ?",
                    arguments: [name])
                return row?["image_data"] as Data?
            }
            let row = try Row.fetchOne(
                db,
                sql: "SELECT image_data FROM publisher_banners WHERE publisher_name = ?",
                arguments: [name])
            return row?["image_data"] as Data?
        }
    }

    /// Remove the banner image for a single publisher.
    func clearPublisherBanner(name: String) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        try await dbQueue.write { db in
            if try db.tableExists("publisher_mappings"),
                try db.tableHasColumn("publisher_mappings", named: "image_data")
            {
                try db.execute(
                    sql: "UPDATE publisher_mappings SET image_data = NULL WHERE publisher_name = ?",
                    arguments: [name])
                return
            }
            try db.execute(
                sql: "UPDATE publisher_banners SET image_data = NULL WHERE publisher_name = ?",
                arguments: [name])
        }
    }

    /// Remove all publisher banner images.
    func clearAllPublisherBanners() async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        try await dbQueue.write { db in
            if try db.tableExists("publisher_mappings"),
                try db.tableHasColumn("publisher_mappings", named: "image_data")
            {
                try db.execute(sql: "UPDATE publisher_mappings SET image_data = NULL")
                return
            }
            try db.execute(sql: "DELETE FROM publisher_banners")
        }
    }

    /// Fetch all (publisherName, imageData?) rows from the banner store.
    func fetchAllPublisherBanners() async throws -> [(name: String, imageData: Data?)] {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        return try await dbQueue.read { db in
            if try db.tableExists("publisher_mappings"),
                try db.tableHasColumn("publisher_mappings", named: "image_data")
            {
                let rows = try Row.fetchAll(
                    db,
                    sql:
                        "SELECT publisher_name, image_data FROM publisher_mappings ORDER BY publisher_name"
                )
                return rows.map {
                    (name: $0["publisher_name"] as String, imageData: $0["image_data"] as Data?)
                }
            }
            let rows = try Row.fetchAll(
                db,
                sql:
                    "SELECT publisher_name, image_data FROM publisher_banners ORDER BY publisher_name"
            )
            return rows.map {
                (name: $0["publisher_name"] as String, imageData: $0["image_data"] as Data?)
            }
        }
    }
}

// MARK: - Series Knowledge (Learning System)

extension DatabaseManager {

    func fetchAllSeriesKnowledge() async throws -> [SeriesKnowledgeRecord] {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        return try await dbQueue.read { db in
            try SeriesKnowledgeRecord
                .order(Column("use_count").desc)
                .fetchAll(db)
        }
    }

    /// Insert or update by normalized series name (the unique key).
    func upsertSeriesKnowledge(_ record: SeriesKnowledgeRecord) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        let aliasesJSON =
            (try? JSONEncoder().encode(record.aliases))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO series_knowledge
                        (series_name, normalized_name, publisher, book_format,
                         aliases, use_count, last_used)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(normalized_name) DO UPDATE SET
                        series_name = excluded.series_name,
                        publisher = COALESCE(excluded.publisher, series_knowledge.publisher),
                        book_format = excluded.book_format,
                        aliases = excluded.aliases,
                        use_count = excluded.use_count,
                        last_used = excluded.last_used
                    """,
                arguments: [
                    record.seriesName, record.normalizedName, record.publisher,
                    record.bookFormat.rawValue, aliasesJSON, record.useCount, record.lastUsed,
                ])
        }
    }

    func deleteSeriesKnowledge(normalizedName: String) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        _ = try await dbQueue.write { db in
            try SeriesKnowledgeRecord
                .filter(Column("normalized_name") == normalizedName)
                .deleteAll(db)
        }
    }

    func logCorrection(_ record: CorrectionRecord) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        try await dbQueue.write { db in
            try record.insert(db)
        }
    }

    func fetchRecentCorrections(limit: Int = 100) async throws -> [CorrectionRecord] {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        return try await dbQueue.read { db in
            try CorrectionRecord
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}

// MARK: - Database Helpers

extension Database {
    /// Returns true if `table` contains a column named `name`.
    func tableHasColumn(_ table: String, named name: String) throws -> Bool {
        let columns = try self.columns(in: table)
        return columns.contains { $0.name == name }
    }
}

// End of DatabaseManager

// MARK: - Activity Log CRUD

extension DatabaseManager {
    /// Insert a new activity event (fire-and-forget friendly)
    func logActivity(_ event: ActivityEvent) async {
        guard let dbQueue = dbQueue else { return }
        do {
            try await dbQueue.write { db in
                try event.insert(db)
            }
        } catch {
            AppLog.database.error("[DatabaseManager] ⚠️ Failed to log activity: \(error)")
        }
    }

    /// Fetch the most recent N activity events, newest first
    func fetchRecentActivity(limit: Int = 50) async throws -> [ActivityEvent] {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }

        return try await dbQueue.read { db in
            try ActivityEvent
                .order(ActivityEvent.Columns.timestamp.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Delete all activity events older than a given date
    func pruneActivity(olderThan date: Date) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }

        _ = try await dbQueue.write { db in
            try ActivityEvent
                .filter(ActivityEvent.Columns.timestamp < date)
                .deleteAll(db)
        }
    }
}

// MARK: - Folder CRUD (Collections)

extension DatabaseManager {
    /// All folders, ordered by manual sort order then name.
    func fetchFolders() async throws -> [Folder] {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        return try await dbQueue.read { db in
            try Folder
                .order(Folder.Columns.sortOrder, Folder.Columns.name)
                .fetchAll(db)
        }
    }

    /// Insert or update a folder (keyed on its UUID primary key).
    func saveFolder(_ folder: Folder) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        try await dbQueue.write { db in
            try folder.save(db)
            AppLog.database.info("[DatabaseManager] ✅ Saved folder: \(folder.name)")
        }
    }

    /// Delete a folder. Membership rows cascade via the foreign key, but we
    /// also delete them explicitly in case cascade is unavailable.
    func deleteFolder(id: UUID) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM comic_folders WHERE folder_id = ?",
                arguments: [id.uuidString])
            try Folder.deleteOne(db, key: id.uuidString)
            AppLog.database.info("[DatabaseManager] 🗑️ Deleted folder: \(id)")
        }
    }

    /// Add comics to a folder (idempotent — duplicates are ignored).
    func addComics(_ comicIDs: [UUID], toFolder folderID: UUID) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        guard !comicIDs.isEmpty else { return }
        let now = Date()
        try await dbQueue.write { db in
            for cid in comicIDs {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO comic_folders (comic_id, folder_id, added_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [cid.uuidString, folderID.uuidString, now])
            }
        }
    }

    /// Remove comics from a folder.
    func removeComics(_ comicIDs: [UUID], fromFolder folderID: UUID) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        guard !comicIDs.isEmpty else { return }
        try await dbQueue.write { db in
            for cid in comicIDs {
                try db.execute(
                    sql: "DELETE FROM comic_folders WHERE comic_id = ? AND folder_id = ?",
                    arguments: [cid.uuidString, folderID.uuidString])
            }
        }
    }

    /// Full membership map: folderID → set of comic IDs in that folder.
    func fetchFolderMembership() async throws -> [UUID: Set<UUID>] {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        return try await dbQueue.read { db in
            let rows = try Row.fetchAll(
                db, sql: "SELECT comic_id, folder_id FROM comic_folders")
            var map: [UUID: Set<UUID>] = [:]
            for row in rows {
                guard let cidStr: String = row["comic_id"],
                    let cid = UUID(uuidString: cidStr),
                    let fidStr: String = row["folder_id"],
                    let fid = UUID(uuidString: fidStr)
                else { continue }
                map[fid, default: []].insert(cid)
            }
            return map
        }
    }
}

// MARK: - Database Errors
enum DatabaseError: LocalizedError {

    case notInitialized
    case saveFailed
    case fetchFailed
    case updateFailed
    case deleteFailed
    case invalidBackupFile

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
        case .invalidBackupFile:
            return "That file doesn't look like a library backup (not a SQLite database)"
        }
    }
}
