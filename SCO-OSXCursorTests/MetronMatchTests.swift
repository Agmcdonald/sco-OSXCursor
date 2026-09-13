//
//  MetronMatchTests.swift
//  SCO-OSXCursorTests
//
//  Tests for the Metron metadata integration: model fields, snapshot
//  round-trip, DTO decoding, link parsing, and fill behavior.
//

import Foundation
import Testing

@testable import SCO_OSXCursor

// MARK: - Model & snapshot

@Suite struct MetronModelTests {

    @Test func snapshotRoundTripsMetronFields() throws {
        var comic = Comic(
            filePath: URL(fileURLWithPath: "/tmp/a.cbz"),
            fileName: "a.cbz",
            series: "Alpha",
            year: 2020
        )
        comic.characters = ["Superman", "Lois Lane"]
        comic.teams = ["Justice League"]
        comic.storeDate = Date(timeIntervalSince1970: 1_700_000_000)
        comic.metronSeriesID = 42
        comic.metronIssueID = 99

        let snapshot = CVMetadataSnapshot(of: comic)
        var restored = Comic(
            filePath: URL(fileURLWithPath: "/tmp/a.cbz"),
            fileName: "a.cbz"
        )
        // Simulate a fetch having overwritten everything, then undo.
        restored.characters = ["Wrong"]
        restored.teams = ["Wrong"]
        restored.storeDate = Date()
        restored.metronSeriesID = 1
        restored.metronIssueID = 2
        snapshot.restore(onto: &restored)

        #expect(restored.characters == ["Superman", "Lois Lane"])
        #expect(restored.teams == ["Justice League"])
        #expect(restored.storeDate == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(restored.metronSeriesID == 42)
        #expect(restored.metronIssueID == 99)
    }

    @Test func legacySnapshotJSONStillDecodes() throws {
        // A pre-v32 snapshot has none of the Metron fields.
        let legacy = #"{"title":"Old","storyArcs":["Arc"]}"#
        let snapshot = CVMetadataSnapshot.decode(legacy)
        #expect(snapshot != nil)
        #expect(snapshot?.title == "Old")
        #expect(snapshot?.characters == nil)
        #expect(snapshot?.teams == nil)
        #expect(snapshot?.storeDate == nil)
    }
}

// MARK: - Candidate provider tag

@Suite struct CandidateProviderTests {

    @Test func legacyCandidateJSONDecodesAsComicVine() {
        let legacy = #"[{"id":123,"name":"Iron Man","startYear":1968,"publisher":"Marvel","issueCount":332}]"#
        let list = CVCandidate.decodeList(legacy)
        #expect(list.count == 1)
        #expect(list[0].provider == nil)
        #expect(list[0].isMetron == false)
    }

    @Test func metronCandidateRoundTrips() {
        let candidate = CVCandidate(
            id: 42, name: "Superman", startYear: 2016,
            publisher: "DC Comics", issueCount: 45, provider: "Metron"
        )
        let json = CVCandidate.encodeList([candidate])
        let decoded = CVCandidate.decodeList(json)
        #expect(decoded.first?.isMetron == true)
    }
}
