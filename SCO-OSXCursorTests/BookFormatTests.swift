//
//  BookFormatTests.swift
//  SCO-OSXCursorTests
//
//  Tests for the Stage 2/3 logic: book-format detection, format-aware
//  readiness and naming for staged comics, clean filenames, and the
//  series-knowledge record normalization used by the learning system.
//

import Foundation
import Testing

@testable import SCO_OSXCursor

// MARK: - Book Format Detection

struct BookFormatDetectionTests {

    @Test func issueNumberMeansIssue() {
        #expect(Comic.BookFormat.detect(issueNumber: "012", volume: nil) == .issue)
        #expect(Comic.BookFormat.detect(issueNumber: "1A", volume: 3) == .issue)
    }

    @Test func volumeWithoutIssueMeansVolume() {
        #expect(Comic.BookFormat.detect(issueNumber: nil, volume: 3) == .volume)
        #expect(Comic.BookFormat.detect(issueNumber: "", volume: 1) == .volume)
    }

    @Test func neitherMeansOneShot() {
        #expect(Comic.BookFormat.detect(issueNumber: nil, volume: nil) == .oneShot)
        #expect(Comic.BookFormat.detect(issueNumber: "", volume: nil) == .oneShot)
    }
}

// MARK: - Clean Filename per Format

struct CleanFileNameTests {

    private func makeComic(
        series: String? = "Test Series",
        issue: String? = nil,
        volume: Int? = nil,
        year: Int? = nil,
        format: Comic.BookFormat = .issue
    ) -> Comic {
        Comic(
            filePath: URL(fileURLWithPath: "/tmp/original file.cbz"),
            fileName: "original file.cbz",
            series: series,
            issueNumber: issue,
            volume: volume,
            year: year,
            bookFormat: format
        )
    }

    @Test func issueNaming() {
        let comic = makeComic(issue: "001", year: 2025, format: .issue)
        #expect(comic.cleanFileName == "Test Series #001 (2025).cbz")
    }

    @Test func issueWithRunVolume() {
        let comic = makeComic(issue: "001", volume: 2, year: 2025, format: .issue)
        #expect(comic.cleanFileName == "Test Series V2 #001 (2025).cbz")
    }

    @Test func oneShotNaming() {
        // One-shots have no issue number — just "Series (Year)"
        let comic = makeComic(year: 2026, format: .oneShot)
        #expect(comic.cleanFileName == "Test Series (2026).cbz")
    }

    @Test func volumeNaming() {
        let comic = makeComic(volume: 3, year: 2020, format: .volume)
        #expect(comic.cleanFileName == "Test Series Vol. 03 (2020).cbz")
    }

    @Test func fallsBackToOriginalWithoutSeries() {
        let comic = makeComic(series: nil, issue: "001")
        #expect(comic.cleanFileName == "original file.cbz")
    }
}

// MARK: - Staged Comic Readiness (format-aware)

struct StagedComicReadinessTests {

    private func staged(
        series: String, issue: String? = nil, volume: Int? = nil,
        year: Int? = nil, publisher: String? = nil, format: Comic.BookFormat
    ) -> StagedComic {
        var comic = StagedComic(url: URL(fileURLWithPath: "/tmp/whatever.cbz"))
        comic.series = series
        comic.issueNumber = issue
        comic.volume = volume
        comic.year = year
        comic.publisher = publisher
        comic.bookFormat = format
        return comic
    }

    @Test func fullIssueIsReadyAndHigh() {
        var comic = staged(
            series: "Sludge", issue: "005", year: 1994,
            publisher: "Malibu Comics Entertainment", format: .issue)
        comic.reevaluate(userEdited: false)
        #expect(comic.confidence == .high)
        #expect(comic.status == .ready)
    }

    @Test func issueWithoutYearIsMediumNotAutoReady() {
        var comic = staged(series: "Sludge", issue: "005", format: .issue)
        comic.status = .pending
        comic.reevaluate(userEdited: false)
        #expect(comic.confidence == .medium)
        #expect(comic.status == .pending)  // auto-parse needs HIGH to go Ready
    }

    @Test func userEditedCoreFieldsBecomeReady() {
        var comic = staged(series: "Sludge", issue: "005", format: .issue)
        comic.status = .pending
        comic.reevaluate(userEdited: true)
        #expect(comic.status == .ready)  // user-confirmed core fields suffice
    }

    @Test func oneShotNeedsNoIssueNumber() {
        var comic = staged(
            series: "Supergirl - The World", year: 2026,
            publisher: "DC Comics", format: .oneShot)
        comic.reevaluate(userEdited: false)
        #expect(comic.confidence == .high)
        #expect(comic.status == .ready)
    }

    @Test func volumeNeedsVolumeNumber() {
        var withVolume = staged(
            series: "Solo Leveling", volume: 3, year: 2024,
            publisher: "Yen Press", format: .volume)
        withVolume.reevaluate(userEdited: false)
        #expect(withVolume.confidence == .high)

        var withoutVolume = staged(
            series: "Solo Leveling", year: 2024,
            publisher: "Yen Press", format: .volume)
        withoutVolume.reevaluate(userEdited: false)
        #expect(withoutVolume.confidence == .low)
    }

    @Test func proposedFileNamePerFormat() {
        var oneShot = staged(series: "Big Story", year: 2026, format: .oneShot)
        #expect(oneShot.proposedFileName == "Big Story (2026).cbz")

        var volume = staged(series: "Manga Run", volume: 7, year: 2023, format: .volume)
        #expect(volume.proposedFileName == "Manga Run Vol. 07 (2023).cbz")

        var issue = staged(series: "Caped Hero", issue: "012", year: 2025, format: .issue)
        #expect(issue.proposedFileName == "Caped Hero #012 (2025).cbz")

        // Silence "never mutated" warnings — reevaluate exercises the structs
        oneShot.reevaluate(userEdited: false)
        volume.reevaluate(userEdited: false)
        issue.reevaluate(userEdited: false)
    }
}

// MARK: - Series Knowledge Records

struct SeriesKnowledgeRecordTests {

    @Test func normalizationIsCaseAndWhitespaceInsensitive() {
        #expect(SeriesKnowledgeRecord.normalize("  Amazing Spider-Man ") == "amazing spider-man")
        #expect(
            SeriesKnowledgeRecord.normalize("SLUDGE")
                == SeriesKnowledgeRecord.normalize("sludge"))
    }

    @Test func recordCarriesAliasesAndFormat() {
        let record = SeriesKnowledgeRecord(
            seriesName: "Amazing Spider-Man",
            publisher: "Marvel Comics",
            bookFormat: .issue,
            aliases: ["asm"],
            useCount: 25
        )
        #expect(record.normalizedName == "amazing spider-man")
        #expect(record.aliases.contains("asm"))
        #expect(record.publisher == "Marvel Comics")
    }
}
