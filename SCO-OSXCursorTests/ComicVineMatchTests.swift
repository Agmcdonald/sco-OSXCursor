//
//  ComicVineMatchTests.swift
//  SCO-OSXCursorTests
//
//  Tests for ComicVine match scoring (year weighting) and the pasted-link /
//  ID parser used by the "Choose the Right Match" override.
//

import Foundation
import Testing

@testable import SCO_OSXCursor

// MARK: - Helpers

private func makeComic(series: String, year: Int?, publisher: String?) -> Comic {
    Comic(
        filePath: URL(fileURLWithPath: "/tmp/\(series).cbz"),
        fileName: "\(series).cbz",
        publisher: publisher,
        series: series,
        issueNumber: "6",
        year: year
    )
}

private func makeVolume(
    id: Int,
    name: String,
    startYear: Int?,
    publisher: String?
) -> CVVolumeResult {
    CVVolumeResult(
        id: id,
        name: name,
        startYear: startYear.map(String.init),
        publisher: CVPublisher(name: publisher),
        countOfIssues: nil
    )
}

// MARK: - Year scoring

struct ComicVineYearScoreTests {

    @Test func exactYearIsStrongest() {
        #expect(ComicVineMatcher.yearScore(comicYear: 2026, volumeYear: 2026) == 0.35)
    }

    @Test func oneYearOffIsModest() {
        #expect(ComicVineMatcher.yearScore(comicYear: 2026, volumeYear: 2025) == 0.15)
    }

    @Test func fewYearsOffIsSmall() {
        #expect(ComicVineMatcher.yearScore(comicYear: 2026, volumeYear: 2023) == 0.05)
    }

    @Test func moderateGapPenalized() {
        #expect(ComicVineMatcher.yearScore(comicYear: 2026, volumeYear: 2019) == -0.15)
    }

    @Test func largeGapPenalizedHard() {
        // 2026 book vs a 1968 volume — clearly the wrong run.
        #expect(ComicVineMatcher.yearScore(comicYear: 2026, volumeYear: 1968) == -0.35)
    }

    @Test func unknownYearIsNeutral() {
        #expect(ComicVineMatcher.yearScore(comicYear: nil, volumeYear: 2026) == 0)
        #expect(ComicVineMatcher.yearScore(comicYear: 2026, volumeYear: nil) == 0)
    }
}

// MARK: - End-to-end scoring (the Iron Man case)

struct ComicVineScoreTests {

    @Test func matchingYearVolumeBeatsLongRunningSameName() {
        let comic = makeComic(series: "Iron Man", year: 2026, publisher: "Marvel")

        let new2026 = makeVolume(id: 170313, name: "Iron Man", startYear: 2026, publisher: "Marvel")
        let classic1968 = makeVolume(id: 1, name: "Iron Man", startYear: 1968, publisher: "Marvel")

        let scoreNew = ComicVineMatcher.score(new2026, against: comic, query: "Iron Man")
        let scoreOld = ComicVineMatcher.score(classic1968, against: comic, query: "Iron Man")

        #expect(scoreNew > scoreOld)
        // The gap should be large enough to clear the auto-apply ambiguity guard.
        #expect(scoreNew - scoreOld >= 0.2)
    }

    @Test func exactNameStillBeatsSupersetNameOnEqualYear() {
        let comic = makeComic(series: "Iron Man", year: 2026, publisher: "Marvel")

        let exact = makeVolume(id: 170313, name: "Iron Man", startYear: 2026, publisher: "Marvel")
        let superset = makeVolume(id: 99, name: "Invincible Iron Man", startYear: 2026, publisher: "Marvel")

        #expect(
            ComicVineMatcher.score(exact, against: comic, query: "Iron Man")
            > ComicVineMatcher.score(superset, against: comic, query: "Iron Man")
        )
    }
}

// MARK: - Link / ID parser

struct CVLinkParserTests {

    @Test func parsesFullVolumeURL() {
        #expect(
            CVLinkParser.parse("https://comicvine.gamespot.com/iron-man/4050-170313/")
            == .volume(170313)
        )
    }

    @Test func parsesFullIssueURL() {
        #expect(
            CVLinkParser.parse("https://comicvine.gamespot.com/iron-man-6-iron-man-team-up/4000-1169604/")
            == .issue(1169604)
        )
    }

    @Test func parsesBareSlug() {
        #expect(CVLinkParser.parse("4050-170313") == .volume(170313))
    }

    @Test func parsesBareNumberAsVolume() {
        #expect(CVLinkParser.parse("170313") == .volume(170313))
    }

    @Test func trimsWhitespace() {
        #expect(CVLinkParser.parse("  4050-170313\n") == .volume(170313))
    }

    @Test func rejectsUnknownResourcePrefix() {
        // 4005 = character page — not something we can match a volume from.
        #expect(CVLinkParser.parse("https://comicvine.gamespot.com/iron-man/4005-1455/") == nil)
    }

    @Test func rejectsJunk() {
        #expect(CVLinkParser.parse("not a link") == nil)
        #expect(CVLinkParser.parse("") == nil)
    }
}
