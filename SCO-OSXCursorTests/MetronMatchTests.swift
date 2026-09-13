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
        #expect(page.results.first?.series?.name == "Superman")
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

// MARK: - Issue list query building

/// Metron's `IssueFilter` declares the series filter as
/// `series_id = NumberFilter(field_name="series__id")`. django-filter
/// silently ignores unknown params, so sending `series=<id>` returns page 1
/// of EVERY issue with that number database-wide — the wrong issue's credits
/// then get applied. These pin the parameter names.
@Suite struct MetronQueryTests {

    @Test func issueQueryUsesSeriesIDAndNumber() {
        let items = MetronService.issueQuery(seriesID: 2658, issueNumber: "4")
        #expect(items.map(\.name) == ["series_id", "number"])
        #expect(items.map(\.value) == ["2658", "4"])
    }

    @Test func issueQueryWithoutNumberIsSeriesOnly() {
        let items = MetronService.issueQuery(seriesID: 2658, issueNumber: nil)
        #expect(items.count == 1)
        #expect(items.first?.name == "series_id")
        #expect(items.first?.value == "2658")
    }

    @Test func issueQueryTreatsEmptyNumberAsAbsent() {
        let items = MetronService.issueQuery(seriesID: 7, issueNumber: "")
        #expect(items.map(\.name) == ["series_id"])
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

    @Test func digitLeadingSlugRejected() {
        #expect(MTLinkParser.parse("https://metron.cloud/series/2000-ad-1977/") == nil)
        #expect(MTLinkParser.parse("https://metron.cloud/issue/52-2006-1/") == nil)
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

    /// Store dates are UTC midnight; display must not slide a day west of UTC.
    @Test func displayRendersTheUTCCalendarDay() throws {
        let date = try #require(MetronDates.parse("2016-09-07"))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2016)
        #expect(parts.month == 9)
        #expect(parts.day == 7)

        let shown = MetronDates.display(date)
        #expect(shown.contains("2016"))
        #expect(shown.contains("7"))
    }
}

// MARK: - Metron scoring & fill

@Suite struct MetronFillTests {

    private func makeComic(
        series: String? = "Superman", issue: String? = "6",
        year: Int? = 2016, publisher: String? = nil
    ) -> Comic {
        Comic(
            filePath: URL(fileURLWithPath: "/tmp/s.cbz"),
            fileName: "s.cbz",
            publisher: publisher,
            series: series,
            issueNumber: issue,
            year: year
        )
    }

    @Test func scoringPrefersMatchingYear() {
        let comic = makeComic(year: 2016)
        let new = MTSeriesRef(id: 1, name: "Superman", yearBegan: 2016, publisher: "DC Comics", issueCount: 52)
        let old = MTSeriesRef(id: 2, name: "Superman", yearBegan: 1987, publisher: "DC Comics", issueCount: 228)
        let q = "Superman"
        #expect(MetronMatcher.score(new, against: comic, query: q)
                > MetronMatcher.score(old, against: comic, query: q))
    }

    @Test func applySeriesFillsBlanksAndCanonicalName() {
        var comic = makeComic(series: "superman", publisher: nil)
        comic.year = nil
        let ref = MTSeriesRef(id: 2658, name: "Superman (2016)", yearBegan: 2016, publisher: "DC Comics", issueCount: 52)
        let filled = MetronFetcher.applySeries(ref, to: comic)
        #expect(filled.series == "Superman (2016)")   // canonical
        #expect(filled.publisher == "DC Comics")      // blank-filled
        #expect(filled.year == 2016)                  // blank-filled
        #expect(filled.metronSeriesID == 2658)
    }

    @Test func applySeriesNeverClobbersExistingPublisherOrYear() {
        let comic = makeComic(year: 1999, publisher: "My Publisher")
        let ref = MTSeriesRef(id: 1, name: "Superman", yearBegan: 2016, publisher: "DC Comics", issueCount: 52)
        let filled = MetronFetcher.applySeries(ref, to: comic)
        #expect(filled.publisher == "My Publisher")
        #expect(filled.year == 1999)
    }

    @Test func applyIssueFillsEverything() {
        let comic = makeComic()
        let list = MTIssueResult(
            id: 38181, number: "6", issueName: "Superman (2016) #6",
            coverDate: "2016-11-01", storeDate: "2016-09-07"
        )
        let detail = MTIssueDetail(
            id: 38181, number: "6", collectionTitle: "",
            storyTitles: ["Son of Superman, Part Six"],
            coverDate: "2016-11-01", storeDate: "2016-09-07",
            desc: "Superman and son face the Eradicator.",
            image: nil,
            credits: [
                MTCredit(creator: "Peter J. Tomasi", roles: [MTGenericItem(id: 30, name: "Writer")]),
                MTCredit(creator: "Patrick Gleason", roles: [
                    MTGenericItem(id: 1, name: "Penciller"), MTGenericItem(id: 6, name: "Cover"),
                ]),
                MTCredit(creator: "Mick Gray", roles: [MTGenericItem(id: 2, name: "Inker")]),
            ],
            arcs: [MTGenericItem(id: 93, name: "Son of Superman")],
            characters: [MTGenericItem(id: 1, name: "Superman"), MTGenericItem(id: 2, name: "Jonathan Kent")],
            teams: [MTGenericItem(id: 5, name: "Eradicators")]
        )
        let filled = MetronFetcher.applyIssue(list: list, detail: detail, to: comic)
        #expect(filled.metronIssueID == 38181)
        #expect(filled.title == "Son of Superman, Part Six")
        #expect(filled.summary == "Superman and son face the Eradicator.")
        #expect(filled.writer == "Peter J. Tomasi")
        #expect(filled.artist == "Patrick Gleason")
        #expect(filled.coverArtist == "Patrick Gleason")
        #expect(filled.inker == "Mick Gray")
        #expect(filled.storyArcs == ["Son of Superman"])
        #expect(filled.characters == ["Superman", "Jonathan Kent"])
        #expect(filled.teams == ["Eradicators"])
        #expect(filled.storeDate == MetronDates.parse("2016-09-07"))
    }

    @Test func applyIssueNeverWipesArcsCharactersTeamsWithEmpty() {
        var comic = makeComic()
        comic.storyArcs = ["Existing Arc"]
        comic.characters = ["Existing Character"]
        comic.teams = ["Existing Team"]
        let list = MTIssueResult(id: 1, number: "6", issueName: nil, coverDate: nil, storeDate: nil)
        let detail = MTIssueDetail(
            id: 1, number: "6", collectionTitle: nil, storyTitles: nil,
            coverDate: nil, storeDate: nil, desc: nil, image: nil,
            credits: nil, arcs: [], characters: [], teams: []
        )
        let filled = MetronFetcher.applyIssue(list: list, detail: detail, to: comic)
        #expect(filled.storyArcs == ["Existing Arc"])
        #expect(filled.characters == ["Existing Character"])
        #expect(filled.teams == ["Existing Team"])
    }
}

// MARK: - Search over characters/teams

@Suite struct MetronSearchTests {
    @Test func searchMatchesCharactersAndTeams() {
        var comic = Comic(filePath: URL(fileURLWithPath: "/tmp/x.cbz"), fileName: "x.cbz", series: "X")
        comic.characters = ["Booster Gold"]
        comic.teams = ["Birds of Prey"]
        // Use the same predicate the library search uses.
        #expect(comicMatchesSearch(comic, "booster"))
        #expect(comicMatchesSearch(comic, "birds of prey"))
        #expect(!comicMatchesSearch(comic, "zatanna"))
    }

    /// Pins the clauses that moved out of LibraryQuery.apply into the free function.
    @Test func searchStillMatchesPreExistingFields() {
        var comic = Comic(filePath: URL(fileURLWithPath: "/tmp/y.cbz"), fileName: "y.cbz", series: "Blue Beetle")
        comic.title = "Kord Industries"
        comic.publisher = "Charlton"
        comic.issueNumber = "12"
        comic.writer = "Steve Ditko"
        comic.tags = ["Silver Age"]
        comic.storyArcs = ["Crisis on Infinite Earths"]

        #expect(comicMatchesSearch(comic, "blue beetle"))
        #expect(comicMatchesSearch(comic, "kord"))
        #expect(comicMatchesSearch(comic, "charlton"))
        #expect(comicMatchesSearch(comic, "ditko"))
        #expect(comicMatchesSearch(comic, "silver age"))
        #expect(comicMatchesSearch(comic, "infinite earths"))
        #expect(comicMatchesSearch(comic, "y.cbz"))
        #expect(!comicMatchesSearch(comic, "aquaman"))
    }
}
