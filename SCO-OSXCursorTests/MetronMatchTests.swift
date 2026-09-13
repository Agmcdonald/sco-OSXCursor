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

// MARK: - Metron DTO decoding

@Suite struct MetronDTOTests {

    @Test func decodesSeriesListPage() throws {
        let json = """
        {"count":2,"next":null,"previous":null,"results":[
          {"id":2658,"series":"Superman (2016)","year_began":2016,"year_end":2018,
           "volume":4,"issue_count":52,
           "publisher":{"id":2,"name":"DC Comics"},
           "series_type":{"id":10,"name":"Ongoing Series"},
           "cv_id":91699,"gcd_id":null,"modified":"2024-01-01T00:00:00Z"}
          ,
          {"id":100,"series":"Superman (1987)","year_began":1987,"year_end":2006,
           "volume":2,"issue_count":228,
           "publisher":{"id":2,"name":"DC Comics"},
           "series_type":{"id":10,"name":"Ongoing Series"},
           "cv_id":null,"gcd_id":null,"modified":"2024-01-01T00:00:00Z"}
        ]}
        """.data(using: .utf8)!
        let page = try JSONDecoder().decode(MTPage<MTSeriesResult>.self, from: json)
        #expect(page.results.count == 2)
        let ref = MTSeriesRef(listRow: page.results[0])
        #expect(ref.id == 2658)
        #expect(ref.name == "Superman (2016)")
        #expect(ref.yearBegan == 2016)
        #expect(ref.publisher == "DC Comics")
        #expect(ref.issueCount == 52)
    }

    @Test func decodesIssueListRow() throws {
        let json = """
        {"count":1,"next":null,"previous":null,"results":[
          {"id":38181,"series":{"name":"Superman","volume":4,"year_began":2016},
           "number":"6","issue":"Superman (2016) #6",
           "cover_date":"2016-11-01","store_date":"2016-09-07",
           "image":"https://static.metron.cloud/media/issue/2018/x.jpg",
           "cover_hash":"abc","modified":"2024-01-01T00:00:00Z"}
        ]}
        """.data(using: .utf8)!
        let page = try JSONDecoder().decode(MTPage<MTIssueResult>.self, from: json)
        #expect(page.results.first?.id == 38181)
        #expect(page.results.first?.number == "6")
        #expect(page.results.first?.coverDate == "2016-11-01")
        #expect(page.results.first?.storeDate == "2016-09-07")
    }

    @Test func decodesIssueDetail() throws {
        let json = """
        {"id":38181,"publisher":{"id":2,"name":"DC Comics"},
         "series":{"id":2658,"name":"Superman","sort_name":"Superman","volume":4,
                   "year_began":2016,"series_type":{"id":10,"name":"Ongoing Series"},"genres":[]},
         "number":"6","alt_number":"","title":"","name":["Son of Superman, Part Six"],
         "cover_date":"2016-11-01","store_date":"2016-09-07",
         "price":"2.99","rating":{"id":1,"name":"Everyone"},"sku":"","isbn":"","upc":"","page":32,
         "desc":"Superman and son face the Eradicator.",
         "image":"https://static.metron.cloud/media/issue/2018/x.jpg","cover_hash":"abc",
         "arcs":[{"id":93,"name":"Son of Superman","modified":"2024-01-01T00:00:00Z"}],
         "credits":[
           {"id":573,"creator":"Peter J. Tomasi","role":[{"id":30,"name":"Writer"}]},
           {"id":574,"creator":"Patrick Gleason","role":[{"id":1,"name":"Penciller"},{"id":6,"name":"Cover"}]},
           {"id":575,"creator":"Mick Gray","role":[{"id":2,"name":"Inker"}]}
         ],
         "characters":[{"id":1,"name":"Superman","modified":"2024-01-01T00:00:00Z"},
                       {"id":2,"name":"Jonathan Kent","modified":"2024-01-01T00:00:00Z"}],
         "teams":[{"id":5,"name":"Eradicators","modified":"2024-01-01T00:00:00Z"}],
         "universes":[],"reprints":[],"variants":[],
         "cv_id":519906,"gcd_id":null,"resource_url":"https://metron.cloud/issue/superman-2016-6/",
         "modified":"2024-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let detail = try JSONDecoder().decode(MTIssueDetail.self, from: json)
        #expect(detail.storyTitles == ["Son of Superman, Part Six"])
        #expect(detail.desc == "Superman and son face the Eradicator.")
        #expect(detail.arcs?.map(\.name) == ["Son of Superman"])
        #expect(detail.characters?.map(\.name) == ["Superman", "Jonathan Kent"])
        #expect(detail.teams?.map(\.name) == ["Eradicators"])
        #expect(detail.credits?.count == 3)
        #expect(detail.credits?[1].roles.map(\.name) == ["Penciller", "Cover"])
        #expect(detail.storeDate == "2016-09-07")
    }
}

// MARK: - Metron link parsing

@Suite struct MetronLinkParserTests {

    @Test func parsesAPIStyleSeriesURL() {
        #expect(MTLinkParser.parse("https://metron.cloud/api/series/2658/") == .series(2658))
    }

    @Test func parsesNumericIssueURL() {
        #expect(MTLinkParser.parse("https://metron.cloud/issue/38181/") == .issue(38181))
    }

    @Test func bareNumberIsSeries() {
        #expect(MTLinkParser.parse(" 2658 ") == .series(2658))
    }

    @Test func slugURLRejected() {
        #expect(MTLinkParser.parse("https://metron.cloud/issue/superman-2016-6/") == nil)
    }

    @Test func garbageRejected() {
        #expect(MTLinkParser.parse("not a link") == nil)
        #expect(MTLinkParser.parse("") == nil)
    }
}

// MARK: - Metron dates

@Suite struct MetronDateTests {

    @Test func parsesISODateAndYear() {
        #expect(MetronDates.year(from: "2016-11-01") == 2016)
        #expect(MetronDates.parse("2016-09-07") != nil)
        #expect(MetronDates.parse(nil) == nil)
        #expect(MetronDates.year(from: "bad") == nil)
    }
}
