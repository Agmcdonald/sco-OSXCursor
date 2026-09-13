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
            // Fixed 86,400s days, matching TrashRetention's own arithmetic —
            // Calendar day-math would drift an hour across a DST transition and
            // break the boundary assertions below on real dates.
            deletedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
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

// MARK: - Escalation (catalog-only → file in Trash)

/// The pure half of `TrashService.escalateToDeviceDelete`: which entries the
/// action applies to, and what the rewritten manifest row must preserve. The
/// disk/DB half needs a database seam the service doesn't have yet.
@Suite struct TrashEscalationTests {

    private func entry(kind: TrashKind, trashedFileName: String?) -> TrashEntry {
        TrashEntry(
            id: UUID(),
            comicSnapshot: #"{"folderIDs":[]}"#,
            originalPath: "/tmp/lib/Batman #001.cbz",
            bookmarkData: Data([0x01, 0x02]),
            trashedFileName: trashedFileName,
            fileSize: trashedFileName == nil ? 0 : 4_096,
            deletedAt: Date(timeIntervalSince1970: 1_700_000_000),
            kind: kind,
            displayTitle: "Batman #001",
            coverThumb: Data([0xFF, 0xD8])
        )
    }

    @Test func onlyCatalogEntriesWithNoStoredFileCanEscalate() {
        #expect(entry(kind: .catalog, trashedFileName: nil).canEscalateToDeviceDelete)
        // Its file is already in the Trash — nothing left to take.
        #expect(!entry(kind: .file, trashedFileName: "abc.cbz").canEscalateToDeviceDelete)
        // Defensive: a mislabelled row that already names a stored file must
        // not be taken a second time.
        #expect(!entry(kind: .catalog, trashedFileName: "abc.cbz").canEscalateToDeviceDelete)
    }

    @Test func escalatedRowKeepsPurgeClockAndRestoreSource() {
        let original = entry(kind: .catalog, trashedFileName: nil)
        let escalated = original.escalated(storedName: "\(original.id.uuidString).cbz", fileSize: 9_001)

        #expect(escalated.kind == .file)
        #expect(escalated.trashedFileName == "\(original.id.uuidString).cbz")
        #expect(escalated.fileSize == 9_001)
        // The upsert replaces the row in place, so these must survive verbatim:
        // a changed id would orphan the file, a changed deletedAt would restart
        // the retention clock, and the snapshot/cover are what restore needs.
        #expect(escalated.id == original.id)
        #expect(escalated.deletedAt == original.deletedAt)
        #expect(escalated.comicSnapshot == original.comicSnapshot)
        #expect(escalated.originalPath == original.originalPath)
        #expect(escalated.bookmarkData == original.bookmarkData)
        #expect(escalated.coverThumb == original.coverThumb)
        #expect(escalated.displayTitle == original.displayTitle)
    }

    @Test func escalatedRowIsNoLongerEscalatable() {
        let escalated = entry(kind: .catalog, trashedFileName: nil)
            .escalated(storedName: "stored.cbz", fileSize: 1)
        #expect(!escalated.canEscalateToDeviceDelete)
    }
}

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
        _ = try writeFile("X.cbz", in: lib, contents: "newcomer")  // occupy the spot

        let dest = try store.restoreFile(storedName: taken.storedName, toOriginalPath: originalPath)
        let expected = lib.appendingPathComponent("X (restored).cbz")
        #expect(dest == .renamed(expected))
        #expect(FileManager.default.fileExists(atPath: expected.path))
        // The occupier is untouched:
        #expect(try String(contentsOf: URL(fileURLWithPath: originalPath), encoding: .utf8) == "newcomer")
    }

    @Test func restoreIntoDoublyOccupiedPathNumbersTheSuffix() throws {
        let (store, sandbox) = try makeStore()
        let lib = sandbox.appendingPathComponent("lib")
        let source = try writeFile("X.cbz", in: lib)
        let originalPath = source.path
        let taken = try store.takeFile(at: source, entryID: UUID())
        // Both the original spot AND the first " (restored)" name are occupied.
        _ = try writeFile("X.cbz", in: lib, contents: "newcomer")
        _ = try writeFile("X (restored).cbz", in: lib, contents: "earlier restore")

        let dest = try store.restoreFile(storedName: taken.storedName, toOriginalPath: originalPath)
        let expected = lib.appendingPathComponent("X (restored 2).cbz")
        #expect(dest == .renamed(expected))
        #expect(FileManager.default.fileExists(atPath: expected.path))
        // Neither occupier was touched:
        #expect(try String(contentsOf: URL(fileURLWithPath: originalPath), encoding: .utf8) == "newcomer")
        #expect(
            try String(contentsOf: lib.appendingPathComponent("X (restored).cbz"), encoding: .utf8)
                == "earlier restore")
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

    @Test func restoreIntoUnwritableParentReportsFallback() throws {
        let (store, sandbox) = try makeStore()
        let lib = sandbox.appendingPathComponent("lib")
        let source = try writeFile("X.cbz", in: lib)
        let originalPath = source.path
        let taken = try store.takeFile(at: source, entryID: UUID())

        // The original folder still EXISTS — it just won't accept a write any
        // more (read-only volume / revoked permission / sandbox refusal). That
        // must report the fallback, not throw out of the restore.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: lib.path)
        defer {
            // Restore write permission so the temp sandbox can be cleaned up.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: lib.path)
        }

        let dest = try store.restoreFile(storedName: taken.storedName, toOriginalPath: originalPath)
        #expect(dest == .failedParentMissing)
        // File still safely in the trash, ready for home-library re-filing:
        #expect(FileManager.default.fileExists(atPath: store.storedFileURL(taken.storedName).path))
    }

    @Test func purgeAndTotalSize() throws {
        let (store, sandbox) = try makeStore()
        let a = try writeFile("A.cbz", in: sandbox.appendingPathComponent("lib"), contents: "12345")
        let b = try writeFile(
            "B.cbz", in: sandbox.appendingPathComponent("lib"), contents: "1234567890")
        let ta = try store.takeFile(at: a, entryID: UUID())
        let tb = try store.takeFile(at: b, entryID: UUID())
        #expect(store.totalSize() == 15)
        store.purgeFile(ta.storedName)
        #expect(store.totalSize() == 10)
        store.purgeFile(nil)  // no-op, no crash
        store.purgeFile(ta.storedName)  // already gone → idempotent no-op
        store.purgeFile(tb.storedName)
        #expect(store.totalSize() == 0)
    }

    @Test func failedTakeNeverDeletesAPreexistingStoredFile() throws {
        let (store, sandbox) = try makeStore()
        let lib = sandbox.appendingPathComponent("lib")
        let entryID = UUID()
        let first = try writeFile("X.cbz", in: lib, contents: "the only copy")
        let taken = try store.takeFile(at: first, entryID: entryID)

        // Same entryID again → the stored name is already occupied. The take must
        // fail without destroying what is already in the trash.
        let second = try writeFile("X2.cbz", in: lib, contents: "newer file")
        #expect(throws: (any Error).self) {
            _ = try store.takeFile(at: second, entryID: entryID)
        }
        let stored = store.storedFileURL(taken.storedName)
        #expect(FileManager.default.fileExists(atPath: stored.path))
        #expect(try String(contentsOf: stored, encoding: .utf8) == "the only copy")
    }

    @Test func unsafeStoredNamesAreRejected() throws {
        let (store, sandbox) = try makeStore()
        let outsider = try writeFile("outsider.cbz", in: sandbox, contents: "keep me")
        let source = try writeFile("X.cbz", in: sandbox.appendingPathComponent("lib"))
        let taken = try store.takeFile(at: source, entryID: UUID())

        // A traversing name would reach a file outside the trash directory.
        store.purgeFile("../outsider.cbz")
        #expect(FileManager.default.fileExists(atPath: outsider.path))
        #expect(throws: (any Error).self) {
            try store.restoreFile(
                storedName: "../outsider.cbz",
                toOriginalPath: sandbox.appendingPathComponent("lib/Y.cbz").path)
        }
        #expect(FileManager.default.fileExists(atPath: outsider.path))
        // The legitimate entry is untouched by the rejected calls.
        #expect(FileManager.default.fileExists(atPath: store.storedFileURL(taken.storedName).path))
    }
}
