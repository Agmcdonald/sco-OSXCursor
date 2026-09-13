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
