# Trash & Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every user-intent delete (remove-from-app AND delete-files-from-device) becomes recoverable via an app-managed Trash with a database manifest, a Maintenance-tab UI, and time-based auto-purge.

**Architecture:** Three layers with clean seams: `TrashSnapshot`/`TrashEntry` (pure Codable + GRDB record, migration v33), `TrashFileStore` (file moves in/out of the Trash directory, init-injected root URL so tests use temp dirs), and `TrashService` (composes DatabaseManager + TrashFileStore; trash/restore/purge/sweep). `LibraryViewModel`'s two delete functions keep their names but route through the service; internal cleanup deletes bypass. UI is one new section in MaintenanceView.

**Tech Stack:** Swift/SwiftUI (macOS + iOS one file set), GRDB 7 (`DatabaseQueue`), Swift Testing (`import Testing`), ImageIO for thumbnails. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-13-trash-restore-design.md`

## Global Constraints

- Trash directory: `<Application Support>/SuperComicOrganizer/Trash/` (sibling of `comics.db`), created lazily; trashed files stored as `<entry-uuid>.<original-extension>`.
- Manifest table exactly `trash_entries`, migration exactly `v33_trash_entries`, registered after `v32_metron_metadata` (DatabaseManager.swift ~line 720ff).
- `kind` column values exactly `"file"` and `"catalog"`.
- Retention: UserDefaults key exactly `trashRetentionDays` (Int: 7/30/90; **0 = Never**), default 30. Sweep callers map 0 → nil (Never = no-op).
- Restore re-inserts the Comic row with its ORIGINAL UUID; folder memberships recreated only for folders that still exist; restore destination order: original path → ` (restored)` suffix when occupied → home-library filing when parent unreachable → catalog-only.
- Batch trash never aborts on one book's failure; a move-to-trash file failure downgrades that entry to `kind = "catalog"` (file left where it is) and the entry stays restorable.
- Bundled samples (`Comic.isBundled`) never have files taken; remove-from-app still snapshots them.
- Internal deletes bypass trash: the retired-samples cleanup (LibraryViewModel ~line 871) and all organize/transfer/temp `removeItem` calls stay hard deletes.
- Copy rule: user-facing delete copy stops saying "cannot be undone" for trashed operations; Empty Trash / Delete Now are the permanent actions and keep destructive confirmation.
- Logging via a new `AppLog.trash` category (`AppLogger(category: "Trash")` in Utilities/AppLog.swift), lines prefixed `[Trash]`.
- Build: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet`. Tests: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet` (timeout 600000). All 152 existing tests must keep passing.
- Synchronized file groups: NEVER edit project.pbxproj. Never stage the pre-existing unrelated working-tree modifications (SCO-OSXCursor/ViewModels/LibraryViewModel.swift carries an unrelated uncommitted retiredSampleFiles edit — you WILL be editing this file in Task 4; commit ONLY your hunks via `git add -p`-style care is NOT available to agents, so instead: before starting Task 4, run `git stash push -- SCO-OSXCursor/ViewModels/LibraryViewModel.swift` is FORBIDDEN (user's edit); the accepted procedure is: make your edits, then `git add SCO-OSXCursor/ViewModels/LibraryViewModel.swift` IS allowed for Task 4 only, because the user's retiredSampleFiles hunk (three added sample filenames) rides along — call this out in the commit message body with "includes pre-existing retiredSampleFiles list addition". Never stage any .xcuserstate.)
- Commits: one per task, message ending `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: TrashSnapshot, TrashEntry record, migration v33, retention math

**Files:**
- Create: `SCO-OSXCursor/Models/TrashEntry.swift`
- Modify: `SCO-OSXCursor/Services/Database/DatabaseManager.swift` (register migration after `v32_metron_metadata`, ~line 745; add manifest CRUD near the folder CRUD ~line 1490)
- Modify: `SCO-OSXCursor/Utilities/AppLog.swift` (add `trash` category next to the existing statics)
- Test: `SCO-OSXCursorTests/TrashServiceTests.swift` (create)

**Interfaces:**
- Consumes: `Comic` (Codable), `AppLogger`.
- Produces (used by every later task):

```swift
struct TrashSnapshot: Codable {
    var comic: Comic
    var folderIDs: [UUID]
    func encoded() -> String?                       // JSON string
    static func decode(_ json: String?) -> TrashSnapshot?
}

enum TrashKind: String, Codable { case file, catalog }

struct TrashEntry: Identifiable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "trash_entries"
    var id: UUID
    var comicSnapshot: String        // TrashSnapshot JSON
    var originalPath: String
    var bookmarkData: Data?
    var trashedFileName: String?     // nil = file never taken
    var fileSize: Int64
    var deletedAt: Date
    var kind: TrashKind
    var displayTitle: String
    var coverThumb: Data?
    // CodingKeys map to snake_case columns: comic_snapshot, original_path,
    // bookmark_data, trashed_file_name, file_size, deleted_at, kind,
    // display_title, cover_thumb (id stored as uuidString TEXT via
    // explicit encode/init(row:) like Comic, OR use Codable columns —
    // follow Comic.swift's explicit encode(to container:)/init(row:) style).
}

enum TrashRetention {
    /// Entries older than `days` (nil = Never → always []).
    static func expired(_ entries: [TrashEntry], retentionDays: Int?, now: Date = Date()) -> [TrashEntry]
    /// Stored setting (0 = Never) → API value.
    static func days(fromStoredValue v: Int) -> Int?   // 0 → nil, else v
    /// Days remaining before purge for a row (nil = kept forever).
    static func daysRemaining(for entry: TrashEntry, retentionDays: Int?, now: Date = Date()) -> Int?
}
```

- DatabaseManager additions (exact signatures Tasks 3–5 call):

```swift
func insertTrashEntry(_ entry: TrashEntry) async throws
func fetchTrashEntries() async throws -> [TrashEntry]     // newest first (deleted_at DESC)
func deleteTrashEntry(withID id: UUID) async throws
func folderExists(id: UUID) async throws -> Bool
```

- [ ] **Step 1: Write the failing tests** — create `SCO-OSXCursorTests/TrashServiceTests.swift`:

```swift
//
//  TrashServiceTests.swift
//  SCO-OSXCursorTests
//
//  Trash & restore: snapshot round-trip, retention math, and the
//  TrashFileStore file operations (temp-directory harness).
//

import Foundation
import Testing

@testable import SCO_OSXCursor

// MARK: - Snapshot round-trip

@Suite struct TrashSnapshotTests {

    private func makeComic() -> Comic {
        var c = Comic(
            filePath: URL(fileURLWithPath: "/tmp/lib/DC Comics/Batman/Batman #001 (2020).cbz"),
            fileName: "Batman #001 (2020).cbz",
            title: "Their Dark Designs",
            publisher: "DC Comics",
            series: "Batman",
            issueNumber: "001",
            year: 2020,
            writer: "James Tynion IV",
            summary: "A new era begins."
        )
        c.tags = ["favorite-run"]
        c.rating = 4
        c.status = .reading
        c.currentPage = 12
        c.totalPages = 32
        c.storyArcs = ["Their Dark Designs"]
        c.characters = ["Batman", "Punchline"]
        c.teams = ["Bat-Family"]
        c.metronSeriesID = 99
        c.metadataSource = "Metron"
        c.coverImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        return c
    }

    @Test func roundTripsEveryFieldAndFolderIDs() throws {
        let comic = makeComic()
        let folderIDs = [UUID(), UUID()]
        let snapshot = TrashSnapshot(comic: comic, folderIDs: folderIDs)
        let decoded = TrashSnapshot.decode(snapshot.encoded())
        let d = try #require(decoded)
        #expect(d.folderIDs == folderIDs)
        #expect(d.comic.id == comic.id)
        #expect(d.comic.title == comic.title)
        #expect(d.comic.tags == comic.tags)
        #expect(d.comic.rating == comic.rating)
        #expect(d.comic.status == comic.status)
        #expect(d.comic.currentPage == comic.currentPage)
        #expect(d.comic.storyArcs == comic.storyArcs)
        #expect(d.comic.characters == comic.characters)
        #expect(d.comic.teams == comic.teams)
        #expect(d.comic.metronSeriesID == comic.metronSeriesID)
        #expect(d.comic.metadataSource == comic.metadataSource)
        #expect(d.comic.coverImageData == comic.coverImageData)
        #expect(d.comic.filePath == comic.filePath)
    }

    @Test func garbageDecodesToNil() {
        #expect(TrashSnapshot.decode("not json") == nil)
        #expect(TrashSnapshot.decode(nil) == nil)
    }
}

// MARK: - Retention math

@Suite struct TrashRetentionTests {

    private func entry(daysAgo: Int, now: Date) -> TrashEntry {
        TrashEntry(
            id: UUID(),
            comicSnapshot: "{}",
            originalPath: "/tmp/x.cbz",
            bookmarkData: nil,
            trashedFileName: nil,
            fileSize: 0,
            deletedAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!,
            kind: .catalog,
            displayTitle: "X",
            coverThumb: nil
        )
    }

    @Test func expiredSelectsOnlyOlderThanRetention() {
        let now = Date()
        let fresh = entry(daysAgo: 5, now: now)
        let stale = entry(daysAgo: 45, now: now)
        let edge = entry(daysAgo: 30, now: now)   // exactly at limit → NOT expired
        let out = TrashRetention.expired([fresh, stale, edge], retentionDays: 30, now: now)
        #expect(out.map(\.id) == [stale.id])
    }

    @Test func neverRetentionExpiresNothing() {
        let now = Date()
        let ancient = entry(daysAgo: 10_000, now: now)
        #expect(TrashRetention.expired([ancient], retentionDays: nil, now: now).isEmpty)
    }

    @Test func storedValueMapping() {
        #expect(TrashRetention.days(fromStoredValue: 0) == nil)
        #expect(TrashRetention.days(fromStoredValue: 30) == 30)
    }

    @Test func daysRemaining() {
        let now = Date()
        let e = entry(daysAgo: 12, now: now)
        #expect(TrashRetention.daysRemaining(for: e, retentionDays: 30, now: now) == 18)
        #expect(TrashRetention.daysRemaining(for: e, retentionDays: nil, now: now) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/TrashSnapshotTests -quiet`
Expected: BUILD FAILURE — `TrashSnapshot` undefined.

- [ ] **Step 3: Create `SCO-OSXCursor/Models/TrashEntry.swift`**

```swift
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
    case file       // the comic file was moved into the Trash directory
    case catalog    // only the catalog row was removed; file untouched on disk
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
    static func expired(_ entries: [TrashEntry], retentionDays: Int?, now: Date = Date()) -> [TrashEntry] {
        guard let retentionDays else { return [] }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return entries.filter { $0.deletedAt < cutoff }
    }

    /// Stored `trashRetentionDays` (0 = Never) → API value.
    static func days(fromStoredValue v: Int) -> Int? {
        v <= 0 ? nil : v
    }

    /// Whole days until this entry purges under the given retention; nil = kept forever.
    static func daysRemaining(for entry: TrashEntry, retentionDays: Int?, now: Date = Date()) -> Int? {
        guard let retentionDays else { return nil }
        let purgeDate = entry.deletedAt.addingTimeInterval(Double(retentionDays) * 86_400)
        return max(0, Int(ceil(purgeDate.timeIntervalSince(now) / 86_400)))
    }
}
```

Note: `DatabaseError.fetchFailed` already exists (used by `Comic.init(row:)`). If `Comic.init(row:)` throws a differently named error, mirror whatever it uses. `TrashEntry` is deliberately NOT Codable (Codable is only on the snapshot) — remove `Codable` from the interface block if the compiler is satisfied without it; the record protocols are what matter.

- [ ] **Step 4: Register migration v33** — in DatabaseManager.swift, immediately after the `v32_metron_metadata` block:

```swift
        migrator.registerMigration("v33_trash_entries") { db in
            AppLog.database.info("[DatabaseManager] 🔄 Running migration: v33_trash_entries")
            try db.create(table: "trash_entries", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("comic_snapshot", .text).notNull()
                t.column("original_path", .text).notNull()
                t.column("bookmark_data", .blob)
                t.column("trashed_file_name", .text)
                t.column("file_size", .integer).notNull().defaults(to: 0)
                t.column("deleted_at", .datetime).notNull()
                t.column("kind", .text).notNull()
                t.column("display_title", .text).notNull()
                t.column("cover_thumb", .blob)
            }
            AppLog.database.info("[DatabaseManager] ✅ Migration v33_trash_entries complete")
        }
```

- [ ] **Step 5: Add manifest CRUD to DatabaseManager** (next to the folder CRUD, ~line 1490):

```swift
    // MARK: - Trash Manifest

    func insertTrashEntry(_ entry: TrashEntry) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        try await dbQueue.write { db in
            try entry.save(db)
            AppLog.database.info("[DatabaseManager] 🗑️ Trash manifest row added: \(entry.displayTitle)")
        }
    }

    /// All trash entries, newest first.
    func fetchTrashEntries() async throws -> [TrashEntry] {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        return try await dbQueue.read { db in
            try TrashEntry
                .order(TrashEntry.Columns.deletedAt.desc)
                .fetchAll(db)
        }
    }

    func deleteTrashEntry(withID id: UUID) async throws {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        try await dbQueue.write { db in
            try TrashEntry.deleteOne(db, key: id.uuidString)
        }
    }

    /// Does a folder still exist? (Restore recreates memberships only for these.)
    func folderExists(id: UUID) async throws -> Bool {
        guard let dbQueue = dbQueue else { throw DatabaseError.notInitialized }
        return try await dbQueue.read { db in
            try Folder.exists(db, key: id.uuidString)
        }
    }
```

(If `Folder`'s primary key handling differs — check how `deleteFolder(id:)` addresses it at ~line 1493 — mirror that addressing.)

- [ ] **Step 6: Add the log category** — in `SCO-OSXCursor/Utilities/AppLog.swift`, next to the other statics:

```swift
    static let trash = AppLogger(category: "Trash")
```

- [ ] **Step 7: Run tests to verify pass**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: PASS (new suites + all 152 existing).

- [ ] **Step 8: Commit**

```bash
git add SCO-OSXCursor/Models/TrashEntry.swift SCO-OSXCursor/Services/Database/DatabaseManager.swift SCO-OSXCursor/Utilities/AppLog.swift SCO-OSXCursorTests/TrashServiceTests.swift
git commit -m "feat(trash): snapshot + manifest model, migration v33, retention math

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: TrashFileStore — file operations with a temp-dir test harness

**Files:**
- Create: `SCO-OSXCursor/Services/TrashFileStore.swift`
- Test: `SCO-OSXCursorTests/TrashServiceTests.swift` (append)

**Interfaces:**
- Consumes: Foundation only.
- Produces (Task 3 composes this):

```swift
struct TrashFileStore {
    let directory: URL                       // injected; production uses default below
    static func defaultDirectory() -> URL    // <App Support>/SuperComicOrganizer/Trash

    /// Move a file into the trash as "<entryID>.<ext>"; returns (storedName, fileSize).
    /// Cross-volume moves fall back to copy+remove.
    func takeFile(at source: URL, entryID: UUID) throws -> (storedName: String, fileSize: Int64)

    enum RestoreDestination: Equatable {
        case originalPath(URL)       // landed exactly where it was
        case renamed(URL)            // original occupied → " (restored)" suffix
        case failedParentMissing     // caller falls back to home-library filing
    }
    /// Move a stored file back toward originalPath. Never overwrites.
    func restoreFile(storedName: String, toOriginalPath originalPath: String) throws -> RestoreDestination

    /// Hand the stored file to the caller at a URL (for home-library fallback filing).
    func storedFileURL(_ storedName: String) -> URL

    func purgeFile(_ storedName: String?)     // best-effort remove; nil = no-op
    func totalSize() -> Int64                 // sum of file sizes in the directory
}
```

- [ ] **Step 1: Append the failing tests** to `TrashServiceTests.swift`:

```swift
// MARK: - TrashFileStore (temp-directory harness)

@Suite struct TrashFileStoreTests {

    /// Fresh temp root per test; cleaned up by the OS eventually, unique always.
    private func makeStore() throws -> (store: TrashFileStore, sandbox: URL) {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("trash-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let store = TrashFileStore(directory: sandbox.appendingPathComponent("Trash"))
        return (store, sandbox)
    }

    private func writeFile(_ name: String, in dir: URL, contents: String = "pages") throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    @Test func takeFileMovesIntoTrashUnderEntryID() throws {
        let (store, sandbox) = try makeStore()
        let source = try writeFile("Batman #001.cbz", in: sandbox.appendingPathComponent("lib"))
        let entryID = UUID()
        let result = try store.takeFile(at: source, entryID: entryID)
        #expect(result.storedName == "\(entryID.uuidString).cbz")
        #expect(result.fileSize == 5)  // "pages"
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: store.storedFileURL(result.storedName).path))
    }

    @Test func restoreReturnsToOriginalPath() throws {
        let (store, sandbox) = try makeStore()
        let source = try writeFile("X.cbz", in: sandbox.appendingPathComponent("lib"))
        let originalPath = source.path
        let entryID = UUID()
        let taken = try store.takeFile(at: source, entryID: entryID)

        let dest = try store.restoreFile(storedName: taken.storedName, toOriginalPath: originalPath)
        #expect(dest == .originalPath(URL(fileURLWithPath: originalPath)))
        #expect(FileManager.default.fileExists(atPath: originalPath))
    }

    @Test func restoreIntoOccupiedPathAppendsSuffix() throws {
        let (store, sandbox) = try makeStore()
        let lib = sandbox.appendingPathComponent("lib")
        let source = try writeFile("X.cbz", in: lib)
        let originalPath = source.path
        let taken = try store.takeFile(at: source, entryID: UUID())
        _ = try writeFile("X.cbz", in: lib, contents: "newcomer")   // occupy the spot

        let dest = try store.restoreFile(storedName: taken.storedName, toOriginalPath: originalPath)
        let expected = lib.appendingPathComponent("X (restored).cbz")
        #expect(dest == .renamed(expected))
        #expect(FileManager.default.fileExists(atPath: expected.path))
        // The occupier is untouched:
        #expect(try String(contentsOf: URL(fileURLWithPath: originalPath), encoding: .utf8) == "newcomer")
    }

    @Test func restoreWithMissingParentReportsFallback() throws {
        let (store, sandbox) = try makeStore()
        let source = try writeFile("X.cbz", in: sandbox.appendingPathComponent("lib"))
        let taken = try store.takeFile(at: source, entryID: UUID())

        // A parent that cannot be created (a FILE occupies the parent path).
        let blocker = try writeFile("blocker", in: sandbox)
        let impossible = blocker.appendingPathComponent("sub/X.cbz").path
        let dest = try store.restoreFile(storedName: taken.storedName, toOriginalPath: impossible)
        #expect(dest == .failedParentMissing)
        // File still safely in the trash:
        #expect(FileManager.default.fileExists(atPath: store.storedFileURL(taken.storedName).path))
    }

    @Test func purgeAndTotalSize() throws {
        let (store, sandbox) = try makeStore()
        let a = try writeFile("A.cbz", in: sandbox.appendingPathComponent("lib"), contents: "12345")
        let b = try writeFile("B.cbz", in: sandbox.appendingPathComponent("lib"), contents: "1234567890")
        let ta = try store.takeFile(at: a, entryID: UUID())
        let tb = try store.takeFile(at: b, entryID: UUID())
        #expect(store.totalSize() == 15)
        store.purgeFile(ta.storedName)
        #expect(store.totalSize() == 10)
        store.purgeFile(nil)   // no-op, no crash
        store.purgeFile(tb.storedName)
        #expect(store.totalSize() == 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/TrashFileStoreTests -quiet`
Expected: BUILD FAILURE — `TrashFileStore` undefined.

- [ ] **Step 3: Create `SCO-OSXCursor/Services/TrashFileStore.swift`**

```swift
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
        let appSupport = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("SuperComicOrganizer")
            .appendingPathComponent("Trash")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Take

    /// Move a file into the trash as "<entryID>.<ext>". Cross-volume moves
    /// fall back to copy + remove.
    func takeFile(at source: URL, entryID: UUID) throws -> (storedName: String, fileSize: Int64) {
        try ensureDirectory()
        let ext = source.pathExtension
        let storedName = ext.isEmpty ? entryID.uuidString : "\(entryID.uuidString).\(ext)"
        let destination = directory.appendingPathComponent(storedName)
        let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            // Cross-volume (or other move failure): copy then remove.
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.removeItem(at: source)
        }
        AppLog.trash.info("[Trash] 📥 Took file into trash: \(source.lastPathComponent) → \(storedName)")
        return (storedName, size ?? 0)
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
    func restoreFile(storedName: String, toOriginalPath originalPath: String) throws -> RestoreDestination {
        let stored = directory.appendingPathComponent(storedName)
        let target = URL(fileURLWithPath: originalPath)
        let parent = target.deletingLastPathComponent()

        var isDir: ObjCBool = false
        let parentExists = FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDir)
        if !parentExists {
            do {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
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
        if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext)! }
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base) (restored \(n))")
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext)! }
            n += 1
        }
        try FileManager.default.moveItem(at: stored, to: candidate)
        AppLog.trash.info("[Trash] ♻️ Restored beside occupied original: \(candidate.lastPathComponent)")
        return .renamed(candidate)
    }

    func storedFileURL(_ storedName: String) -> URL {
        directory.appendingPathComponent(storedName)
    }

    // MARK: Purge / size

    func purgeFile(_ storedName: String?) {
        guard let storedName else { return }
        let url = directory.appendingPathComponent(storedName)
        do {
            try FileManager.default.removeItem(at: url)
            AppLog.trash.info("[Trash] 🔥 Purged trashed file: \(storedName)")
        } catch {
            AppLog.trash.error("[Trash] ⚠️ Purge failed for \(storedName): \(error.localizedDescription)")
        }
    }

    func totalSize() -> Int64 {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        return names.reduce(Int64(0)) { sum, name in
            let path = directory.appendingPathComponent(name).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
            return sum + (size ?? 0)
        }
    }
}
```

(If the compiler complains about the double-optional `size ?? 0` casts, bind with `as? Int64 ?? 0` in two steps — keep the semantics.)

- [ ] **Step 4: Run tests to verify pass**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SCO-OSXCursor/Services/TrashFileStore.swift SCO-OSXCursorTests/TrashServiceTests.swift
git commit -m "feat(trash): TrashFileStore with temp-dir tested take/restore/purge

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: TrashService — trash, restore, purge, sweep

**Files:**
- Create: `SCO-OSXCursor/Services/TrashService.swift`
- Test: none new (DB-composing layer; pure halves covered by Tasks 1–2). Deliverable: compiles + all existing tests pass.

**Interfaces:**
- Consumes: `DatabaseManager.shared` (`saveComic`, `deleteComic(withID:)`, `addComics(_:toFolder:)`, `insertTrashEntry`, `fetchTrashEntries`, `deleteTrashEntry(withID:)`, `folderExists(id:)`), `TrashFileStore`, `TrashSnapshot`, `TrashEntry`, `TrashRetention`, `Comic.isBundled(_:)`, `LibraryViewModel.folders(containingAnyOf:)` is NOT used here — the view model passes folder IDs in (see signature).
- Produces (Tasks 4–5 call exactly these):

```swift
@MainActor
final class TrashService {
    static let shared = TrashService()
    init(fileStore: TrashFileStore = TrashFileStore(directory: TrashFileStore.defaultDirectory()),
         database: DatabaseManager = .shared)

    struct TrashOutcome { var trashed = 0; var fileProblems = 0 }
    /// folderIDs(for:) supplies each comic's memberships (captured pre-delete).
    func trash(_ comics: [Comic], deleteFiles: Bool,
               folderIDs: (Comic) -> [UUID]) async -> TrashOutcome

    enum RestoreOutcome { case originalPath, renamed, homeLibrary, catalogOnly, failed(String) }
    /// needsHomeLibraryFiling: caller-provided fallback that files a stored
    /// file into the home library and returns the new URL + bookmark (or nil
    /// on failure). Keeps LibraryFileService knowledge out of this class.
    func restore(_ entry: TrashEntry,
                 fileIntoHomeLibrary: (URL, Comic) async -> (URL, Data?)?) async -> RestoreOutcome

    func purge(_ entry: TrashEntry) async
    func purgeAll() async
    /// Returns number purged. retentionDays nil = Never = no-op.
    @discardableResult func sweepExpired(retentionDays: Int?) async -> Int
    func entries() async -> [TrashEntry]
    func totalSize() -> Int64
}
```

- [ ] **Step 1: Create `SCO-OSXCursor/Services/TrashService.swift`**

```swift
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
                AppLog.trash.error("[Trash] ⚠️ Snapshot failed for \(comic.fileName) — skipping trash, book NOT deleted")
                continue
            }

            let entryID = UUID()
            var kind: TrashKind = .catalog
            var storedName: String?
            var fileSize: Int64 = 0

            if deleteFiles && !Comic.isBundled(comic) {
                let fileURL = resolvedFileURL(for: comic)
                let didStartAccess = fileURL.access?.startAccessingSecurityScopedResource() ?? false
                defer { if didStartAccess { fileURL.access?.stopAccessingSecurityScopedResource() } }
                do {
                    let taken = try fileStore.takeFile(at: fileURL.url, entryID: entryID)
                    storedName = taken.storedName
                    fileSize = taken.fileSize
                    kind = .file
                } catch {
                    // File locked/missing: still trash the catalog row so the
                    // entry is restorable; report the file problem.
                    AppLog.trash.error("[Trash] ⚠️ Could not take file for \(comic.fileName): \(error.localizedDescription)")
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
                coverThumb: TrashService.thumbnail(from: comic.coverImageData)
            )

            do {
                try await database.insertTrashEntry(entry)
                try await database.deleteComic(withID: comic.id)
                outcome.trashed += 1
            } catch {
                AppLog.trash.error("[Trash] ⚠️ Manifest/delete failed for \(comic.fileName): \(error.localizedDescription)")
                // If we already took the file but couldn't record it, put it back.
                if let storedName {
                    _ = try? fileStore.restoreFile(storedName: storedName, toOriginalPath: comic.filePath.path)
                }
            }
        }
        return outcome
    }

    /// Resolve the comic's real file URL via its security-scoped bookmark
    /// (same pattern the old deleteFileOnDisk used).
    private func resolvedFileURL(for comic: Comic) -> (url: URL, access: URL?) {
        guard let bookmarkData = comic.bookmarkData else { return (comic.filePath, nil) }
        var isStale = false
        #if os(macOS)
        let resolved = try? URL(
            resolvingBookmarkData: bookmarkData, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &isStale)
        #else
        let resolved = try? URL(
            resolvingBookmarkData: bookmarkData, options: [],
            relativeTo: nil, bookmarkDataIsStale: &isStale)
        #endif
        guard let resolved else { return (comic.filePath, nil) }
        return (resolved, resolved)
    }

    // MARK: - Restore

    enum RestoreOutcome {
        case originalPath
        case renamed
        case homeLibrary
        case catalogOnly
        case failed(String)
    }

    func restore(
        _ entry: TrashEntry,
        fileIntoHomeLibrary: (URL, Comic) async -> (URL, Data?)?
    ) async -> RestoreOutcome {
        guard let snapshot = TrashSnapshot.decode(entry.comicSnapshot) else {
            return .failed("This trash entry's snapshot can't be read.")
        }
        var comic = snapshot.comic
        var outcome: RestoreOutcome = .catalogOnly

        if let storedName = entry.trashedFileName {
            do {
                switch try fileStore.restoreFile(storedName: storedName, toOriginalPath: entry.originalPath) {
                case .originalPath(let url):
                    comic.filePath = url
                    outcome = .originalPath
                case .renamed(let url):
                    comic.filePath = url
                    comic.fileName = url.lastPathComponent
                    outcome = .renamed
                case .failedParentMissing:
                    // Fall back: file into the home library.
                    let stored = fileStore.storedFileURL(storedName)
                    if let (newURL, bookmark) = await fileIntoHomeLibrary(stored, comic) {
                        comic.filePath = newURL
                        comic.fileName = newURL.lastPathComponent
                        comic.bookmarkData = bookmark
                        outcome = .homeLibrary
                    } else {
                        return .failed("The original folder is gone and the file couldn't be re-filed into the library.")
                    }
                }
            } catch {
                return .failed("Couldn't move the file out of the Trash: \(error.localizedDescription)")
            }
        }

        do {
            comic.needsAttention = false
            try await database.saveComic(comic)
            for folderID in snapshot.folderIDs where (try? await database.folderExists(id: folderID)) == true {
                try? await database.addComics([comic.id], toFolder: folderID)
            }
            try await database.deleteTrashEntry(withID: entry.id)
            AppLog.trash.info("[Trash] ♻️ Restored \(entry.displayTitle)")
            return outcome
        } catch {
            return .failed("The book's catalog entry couldn't be restored: \(error.localizedDescription)")
        }
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

    @discardableResult
    func sweepExpired(retentionDays: Int?) async -> Int {
        guard retentionDays != nil else { return 0 }
        let expired = TrashRetention.expired(await entries(), retentionDays: retentionDays)
        for entry in expired {
            await purge(entry)
        }
        if !expired.isEmpty {
            AppLog.trash.info("[Trash] 🧹 Sweep purged \(expired.count) expired entr\(expired.count == 1 ? "y" : "ies")")
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

    /// Downscale cover data to a small JPEG for the trash list (~120pt @2x).
    static func thumbnail(from coverData: Data?) -> Data? {
        guard let coverData else { return nil }
        #if canImport(ImageIO)
        guard let src = CGImageSourceCreateWithData(coverData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
        #else
        return coverData
        #endif
    }
}
```

Add `import ImageIO` (and `import CoreGraphics` if needed) at the top alongside Foundation. Fix any compile-level friction (e.g. `NSMutableData` needs Foundation, defer-with-tuple access) without changing behavior. Note the `defer` around security scope inside the loop: Swift's `defer` fires at end of the enclosing scope — wrap the take in a `do { }` block or an inner function so the scope releases per-book, not at function end. Implement it as a small private helper `takeFileResolvingBookmark(for:entryID:) throws -> (String, Int64)` containing the resolve + access + take + release sequence if that reads cleaner — behavior over literal transcription here.

- [ ] **Step 2: Build + full tests**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet && xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: SUCCESS / PASS.

- [ ] **Step 3: Commit**

```bash
git add SCO-OSXCursor/Services/TrashService.swift
git commit -m "feat(trash): TrashService — trash, restore with fallbacks, purge, sweep

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: LibraryViewModel rewiring + launch sweep

**Files:**
- Modify: `SCO-OSXCursor/ViewModels/LibraryViewModel.swift` (delete functions ~lines 936–1020; retired-samples call ~line 871; add restore/sweep plumbing)

**Interfaces:**
- Consumes: `TrashService.shared`, `TrashRetention.days(fromStoredValue:)`, `LibraryFileService` (existing `moveToLibrary`-style filing — read its real signature at Services/LibraryFileService.swift:91 and adapt the closure), `folders(containingAnyOf:)` (~line 1711), existing `loadFolders()`/comics reload.
- Produces (Task 5 calls these):

```swift
// On LibraryViewModel:
func trashEntries() async -> [TrashEntry]                       // passthrough
func restoreFromTrash(_ entry: TrashEntry) async -> TrashService.RestoreOutcome
func purgeTrashEntry(_ entry: TrashEntry) async
func emptyTrash() async
func trashTotalSize() -> Int64
static let trashRetentionDefaultsKey = "trashRetentionDays"     // Int, 0 = Never, default 30
func sweepTrashOnLaunch()                                       // fire-and-forget Task
```

- [ ] **Step 1: Reroute the two delete functions.** Replace the bodies (keep names/signatures; docs updated):

```swift
    /// Remove books from the app — the catalog rows move to the Trash
    /// (restorable from Maintenance). Files on disk are untouched.
    func deleteComicsFromApp(_ toDelete: [Comic]) async {
        await trashComics(toDelete, deleteFiles: false)
    }

    /// Delete the underlying files from disk too — both the files and the
    /// catalog rows move to the Trash (restorable from Maintenance).
    func deleteComicsFromDevice(_ toDelete: [Comic]) async {
        await trashComics(toDelete, deleteFiles: true)
    }

    private func trashComics(_ toDelete: [Comic], deleteFiles: Bool) async {
        guard !toDelete.isEmpty else { return }
        let ids = Set(toDelete.map(\.id))
        let membershipFolders = folders(containingAnyOf: ids)
        let outcome = await TrashService.shared.trash(
            toDelete, deleteFiles: deleteFiles,
            folderIDs: { comic in
                membershipFolders
                    .filter { folder in /* folder contains comic.id — use the same
                        membership source folders(containingAnyOf:) draws from */ true }
                    .map(\.id)
            }
        )
        // Refresh in-memory state the same way the old delete did (drop the
        // trashed comics from `comics`, reload folders) — reuse the existing
        // post-delete bookkeeping from the old deleteComicsFromApp body.
        comics.removeAll { ids.contains($0.id) }
        await loadFolders()
        AppLog.trash.info("[Trash] 🗑️ Moved \(outcome.trashed) book(s) to Trash (fileProblems: \(outcome.fileProblems))")
    }
```

IMPORTANT — the folder-membership closure above is deliberately not literal: `folders(containingAnyOf:)` returns folders containing ANY of the ids, not a per-comic map. Read the membership source it uses (there is a membership map or per-folder comic-ID set in the view model / database — `DatabaseManager` has a "Full membership map: folderID → set of comic IDs" function near line 1530). Build a real per-comic `[UUID]` from that map. Getting per-comic memberships RIGHT is a review gate for this task.

Keep a true hard-delete for internal callers: rename the OLD body of `deleteComicsFromApp` to `private func hardDeleteComicsFromApp(_ toDelete: [Comic]) async` (row deletion + in-memory removal + `loadFolders`, no trash), and change the retired-samples call at ~line 871 from `deleteComicsFromApp(retired)` to `hardDeleteComicsFromApp(retired)`. Delete `deleteFileOnDisk` entirely (its bookmark logic now lives in TrashService).

- [ ] **Step 2: Add the passthroughs + launch sweep** (new MARK near the delete functions):

```swift
    // MARK: - Trash (restore / purge / sweep)

    static let trashRetentionDefaultsKey = "trashRetentionDays"

    func trashEntries() async -> [TrashEntry] {
        await TrashService.shared.entries()
    }

    func restoreFromTrash(_ entry: TrashEntry) async -> TrashService.RestoreOutcome {
        let outcome = await TrashService.shared.restore(entry) { storedFile, comic in
            // Home-library fallback: file the stored file using the existing
            // library filing service. Adapt to LibraryFileService's real API
            // (destinationURL/moveToLibrary at Services/LibraryFileService.swift:34/91):
            // compute the destination for `comic`, move the stored file there,
            // mint a bookmark, and return (newURL, bookmark). Return nil if the
            // home library isn't configured or the move fails.
            return await self.fileTrashedFileIntoHomeLibrary(storedFile, comic: comic)
        }
        if case .failed = outcome { return outcome }
        await reloadAfterRestore()
        return outcome
    }

    private func reloadAfterRestore() async {
        // Reuse the existing "a comic was added" reload: refetch comics from
        // the database (the same call loadComics/refresh uses) + loadFolders().
    }

    func purgeTrashEntry(_ entry: TrashEntry) async {
        await TrashService.shared.purge(entry)
    }

    func emptyTrash() async {
        await TrashService.shared.purgeAll()
    }

    func trashTotalSize() -> Int64 {
        TrashService.shared.totalSize()
    }

    /// Launch sweep — call once from app startup (fire-and-forget).
    func sweepTrashOnLaunch() {
        let stored = UserDefaults.standard.object(forKey: Self.trashRetentionDefaultsKey) as? Int ?? 30
        let days = TrashRetention.days(fromStoredValue: stored)
        Task { await TrashService.shared.sweepExpired(retentionDays: days) }
    }
```

The two "adapt" comments are instructions to the implementer, not shippable stubs: implement `fileTrashedFileIntoHomeLibrary` against LibraryFileService's actual API and `reloadAfterRestore` against the view model's actual load function (find the function the import flow calls after adding a comic — reuse it). Both must be real, working code in the commit.

Call `sweepTrashOnLaunch()` from wherever `LibraryViewModel` finishes its initial load (find the init/`loadComics` completion; one call, guarded from repeat by a `private var didSweepTrash = false`).

- [ ] **Step 3: Build + full tests**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet && xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: SUCCESS / PASS.

- [ ] **Step 4: Commit** (this file carries the user's pre-existing retiredSampleFiles hunk — see Global Constraints; name it in the commit body)

```bash
git add SCO-OSXCursor/ViewModels/LibraryViewModel.swift
git commit -m "feat(trash): route user deletes through TrashService; launch sweep

Includes pre-existing retiredSampleFiles list addition that was already in
the working tree.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Maintenance "Trash" section UI

**Files:**
- Modify: `SCO-OSXCursor/Views/Maintenance/MaintenanceView.swift` (new section using the existing `DashboardSectionCard` wrapper — read the Database section ~line 267 and mirror its chrome)

**Interfaces:**
- Consumes: Task 4's `LibraryViewModel` trash API, `TrashRetention.daysRemaining(for:retentionDays:)`, `TrashEntry`.
- Produces: none (leaf UI).

- [ ] **Step 1: State + section.** Add to MaintenanceView:

```swift
    // ── Trash ──
    @State private var trashEntries: [TrashEntry] = []
    @State private var trashSize: Int64 = 0
    @State private var trashStatus: String?
    @State private var showingEmptyTrashConfirm = false
    @State private var pendingPurgeEntry: TrashEntry?
    @AppStorage(LibraryViewModel.trashRetentionDefaultsKey) private var trashRetentionDays: Int = 30
```

Insert a `trashSection` into the body's section stack (after Storage), built with `DashboardSectionCard(title: "Trash", subtitle: ...)` matching the file's other sections:

- Header content: `"\(trashEntries.count) item(s) · \(ByteCountFormatter.string(fromByteCount: trashSize, countStyle: .file))"`.
- Empty state when `trashEntries.isEmpty`: "Trash is empty." + caption "Deleted books are kept here and can be restored with their metadata, reading progress, and folders."
- Row per entry (`ForEach(trashEntries)`): thumbnail (`Image` from `coverThumb` data via `NSImage`/`UIImage` cross-platform init — follow how other views render `coverImageData`), `displayTitle`, kind line (`entry.kind == .file ? "File in Trash" : "Removed from library — file kept on disk"`), deleted date (`entry.deletedAt.formatted(date: .abbreviated, time: .omitted)`), and days remaining via:

```swift
    private func remainingLabel(for entry: TrashEntry) -> String {
        let days = TrashRetention.days(fromStoredValue: trashRetentionDays)
        guard let remaining = TrashRetention.daysRemaining(for: entry, retentionDays: days) else {
            return "Kept until emptied"
        }
        return remaining == 0 ? "Purges today" : "Purges in \(remaining) day\(remaining == 1 ? "" : "s")"
    }
```

- Per-row buttons: **Restore** (calls `restoreEntry(entry)`), **Delete Now** (sets `pendingPurgeEntry`, confirmation alert "Permanently delete \(entry.displayTitle)? This cannot be undone." → `purgeEntry`).
- Footer: **Empty Trash** button (disabled when empty; `.foregroundColor(AccentColors.error)`; confirmation naming count + size) and the retention picker:

```swift
    Picker("Keep deleted items", selection: $trashRetentionDays) {
        Text("7 Days").tag(7)
        Text("30 Days").tag(30)
        Text("90 Days").tag(90)
        Text("Never Delete").tag(0)
    }
    .pickerStyle(.segmented)
```

with caption "Items older than this are removed automatically when the app launches. 'Never Delete' keeps everything until you empty the Trash."
- Status line: render `trashStatus` like the other sections' status strings.

- [ ] **Step 2: Actions.**

```swift
    private func refreshTrash() {
        Task {
            trashEntries = await libraryViewModel.trashEntries()
            trashSize = libraryViewModel.trashTotalSize()
        }
    }

    private func restoreEntry(_ entry: TrashEntry) {
        Task {
            let outcome = await libraryViewModel.restoreFromTrash(entry)
            switch outcome {
            case .originalPath: trashStatus = "\(entry.displayTitle) restored to its original location."
            case .renamed: trashStatus = "\(entry.displayTitle) restored next to a newer file with the same name."
            case .homeLibrary: trashStatus = "\(entry.displayTitle) restored into your home library (its original folder is gone)."
            case .catalogOnly: trashStatus = "\(entry.displayTitle) restored to your library."
            case .failed(let reason): trashStatus = "Restore failed: \(reason)"
            }
            refreshTrash()
        }
    }

    private func purgeEntry(_ entry: TrashEntry) {
        Task {
            await libraryViewModel.purgeTrashEntry(entry)
            trashStatus = "\(entry.displayTitle) permanently deleted."
            refreshTrash()
        }
    }

    private func emptyTrash() {
        Task {
            await libraryViewModel.emptyTrash()
            trashStatus = "Trash emptied."
            refreshTrash()
        }
    }
```

Call `refreshTrash()` from the view's existing `.onAppear`/`.task` alongside the other section loaders.

- [ ] **Step 3: Build, run tests, visually sanity-check the section compiles for iOS too** (`xcodebuild build -scheme SCO-OSXCursor -destination 'generic/platform=iOS Simulator' -quiet` if the scheme supports it — if that destination errors, macOS build suffices; note it in the report).

- [ ] **Step 4: Commit**

```bash
git add SCO-OSXCursor/Views/Maintenance/MaintenanceView.swift
git commit -m "feat(trash): Maintenance Trash section — list, restore, purge, retention picker

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Copy changes — dialogs and the in-app manual

**Files:**
- Modify: `SCO-OSXCursor/Views/Library/LibraryView.swift` (`deleteFolderButtons` ~line 1196 and any selection-delete confirmation copy)
- Modify: `SCO-OSXCursor/Views/Dashboard/DashboardHealthView.swift` (delete confirmation ~lines 306–363)
- Modify: `SCO-OSXCursor/Views/Help/UserManualView.swift` (~lines 222, 308, 757)

**Interfaces:** none — copy only. Grep first: `grep -rn "cannot be undone\|can't be undone\|permanently" SCO-OSXCursor/Views --include="*.swift"` and update every user-delete-related hit (leave Empty Trash/Delete Now copy from Task 5, and any non-delete "permanent" copy, alone).

- [ ] **Step 1: Dialog copy.**
- Folder delete third option: "Delete Files from Device" explanatory text → "Moves the folder's books and their files to the Trash (Maintenance tab). Kept for your retention period — 30 days by default — then removed." Adjust the exact sentence to fit the existing dialog structure; keep button labels unchanged.
- DashboardHealthView delete confirmation message: replace any "permanent"/"cannot be undone" phrasing with "The book moves to the Trash in Maintenance, where you can restore it."
- Library selection/context delete confirmations: same treatment where such copy exists.

- [ ] **Step 2: Manual copy.** Update the three UserManualView passages:
- ~line 222 (Deleting Books): deleting now sends books (and files, for device deletes) to the Trash in Maintenance; restore brings back metadata, reading progress, and folders; the retention setting controls auto-purge; Empty Trash/Delete Now are the permanent actions.
- ~line 308 (Delete Folder three choices): the "Delete Files from Device" branch now says files go to the Trash instead of "cannot be undone".
- ~line 757 (menu reference row): same correction.
Also ADD one FeatureRow to the Maintenance manual section describing the Trash (what lands there, restore, retention picker, Empty Trash) — mirror the section's existing FeatureRow style.

- [ ] **Step 3: Build + full tests**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet && xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet`
Expected: SUCCESS / PASS.

- [ ] **Step 4: Commit**

```bash
git add SCO-OSXCursor/Views/Library/LibraryView.swift SCO-OSXCursor/Views/Dashboard/DashboardHealthView.swift SCO-OSXCursor/Views/Help/UserManualView.swift
git commit -m "docs(trash): delete dialogs and manual describe Trash instead of permanent loss

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Final verification (after all tasks)

- [ ] `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet` — SUCCESS
- [ ] `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests -quiet` — all suites PASS (152 pre-existing + new Trash suites)
- [ ] Spec cross-check: storage/manifest→1, file ops→2, service API→3, rewiring+sweep→4, Maintenance UI+retention picker→5, copy→6. Manual live checklist (run by the user in-app): delete-from-app → restore (folders/progress back); delete-from-device → file appears in container Trash → restore to original path; occupy original then restore → " (restored)"; retention picker + relaunch sweep; Empty Trash.
