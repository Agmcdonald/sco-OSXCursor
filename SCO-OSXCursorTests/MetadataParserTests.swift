//
//  MetadataParserTests.swift
//  SCO-OSXCursorTests
//
//  Tests for MetadataParser.parseFromFilename()
//  Ported from sco-dyad's real-world filename patterns.
//

import Testing

@testable import SCO_OSXCursor

// MARK: - Filename Parser Tests

struct MetadataParserTests {

    // MARK: - Basic Parsing

    @Test func basicHashIssue() {
        let result = MetadataParser.parseFromFilename("Batman #001 (2024).cbz")
        #expect(result.series == "Batman")
        #expect(result.number == "001")
        #expect(result.year == 2024)
        #expect(result.publisher == "DC Comics")  // Inferred from character
    }

    @Test func standaloneThreeDigitIssue() {
        let result = MetadataParser.parseFromFilename("Spider-Man 045 (2023).cbr")
        #expect(result.series == "Spider-Man")
        #expect(result.number == "045")
        #expect(result.year == 2023)
        #expect(result.publisher == "Marvel Comics")
    }

    // MARK: - Volume Extraction

    @Test func volumeWithV() {
        let result = MetadataParser.parseFromFilename("A-Force V2 #003 (2016).cbz")
        #expect(result.series == "A-Force")
        #expect(result.number == "003")
        #expect(result.year == 2016)
        #expect(result.volume == 2)
    }

    @Test func volumeWithVol() {
        let result = MetadataParser.parseFromFilename("Wolverine Vol 3 #010 (2020).cbz")
        #expect(result.series == "Wolverine")
        #expect(result.number == "010")
        #expect(result.volume == 3)
        #expect(result.publisher == "Marvel Comics")
    }

    // MARK: - Mini-Series (of #)

    @Test func ofTotalExtraction() {
        let result = MetadataParser.parseFromFilename("Saga 001 (of 04) (2024) (Digital).cbz")
        #expect(result.series == "Saga")
        #expect(result.number == "001")
        #expect(result.ofTotal == "04")
        #expect(result.year == 2024)
        #expect(result.format == "Digital")
    }

    // MARK: - Underscore Handling

    @Test func underscoresConvertedToSpaces() {
        let result = MetadataParser.parseFromFilename("Batman_001_(2024)_(Digital)_(DCP).cbz")
        #expect(result.series == "Batman")
        #expect(result.number == "001")
        #expect(result.year == 2024)
        #expect(result.publisher == "DC Comics")
    }

    // MARK: - Hyphenated Series Names

    @Test func hyphenatedSubtitle() {
        let result = MetadataParser.parseFromFilename(
            "Blade - Red Band 002 (2024) (Paper) (Glix).cbz")
        #expect(result.series == "Blade - Red Band")
        #expect(result.number == "002")
        #expect(result.year == 2024)
    }

    @Test func doubleHyphenatedSeries() {
        let result = MetadataParser.parseFromFilename(
            "Laura Kinney - Sabretooth 002 (2025) (Digital) (Kileko-Empire).cbz")
        #expect(result.series == "Laura Kinney - Sabretooth")
        #expect(result.number == "002")
        #expect(result.year == 2025)
        #expect(result.format == "Digital")
        #expect(result.scanInformation == "Kileko-Empire")
    }

    // MARK: - Metadata Noise Stripping

    @Test func digitalAndDCPStripped() {
        let result = MetadataParser.parseFromFilename(
            "The Private Eye 01 (2013) (Digital) (GetComics.INFO).cbz")
        #expect(result.series == "The Private Eye")
        #expect(result.number == "001")  // Zero-padded
        #expect(result.year == 2013)
    }

    @Test func webRipStripped() {
        let result = MetadataParser.parseFromFilename("Daredevil 005 (2024) (web-rip).cbz")
        #expect(result.series == "Daredevil")
        #expect(result.number == "005")
        #expect(result.year == 2024)
        #expect(result.publisher == "Marvel Comics")
    }

    // MARK: - Issue Zero-Padding

    @Test func singleDigitIssueZeroPadded() {
        let result = MetadataParser.parseFromFilename("Venom #1 (2024).cbz")
        #expect(result.number == "001")
        #expect(result.series == "Venom")
        #expect(result.publisher == "Marvel Comics")
    }

    @Test func twoDigitIssueZeroPadded() {
        let result = MetadataParser.parseFromFilename("Batman #12 (2023).cbz")
        #expect(result.number == "012")
    }

    // MARK: - Character-to-Publisher Inference

    @Test func dcCharacterInference() {
        let result = MetadataParser.parseFromFilename("Nightwing 001 (2024).cbz")
        #expect(result.publisher == "DC Comics")
    }

    @Test func marvelCharacterInference() {
        let result = MetadataParser.parseFromFilename("Deadpool 001 (2024).cbz")
        #expect(result.publisher == "Marvel Comics")
    }

    @Test func noPublisherForUnknownSeries() {
        let result = MetadataParser.parseFromFilename("Saga 001 (2024).cbz")
        #expect(result.publisher == nil)
    }

    // MARK: - Edge Cases

    @Test func noIssueNumber() {
        let result = MetadataParser.parseFromFilename("Maus (2003).cbr")
        #expect(result.series == "Maus")
        #expect(result.number == nil)
        #expect(result.year == 2003)
    }

    @Test func pdfExtension() {
        let result = MetadataParser.parseFromFilename("Batman #001 (2024).pdf")
        #expect(result.series == "Batman")
        #expect(result.number == "001")
    }

    @Test func noExtension() {
        let result = MetadataParser.parseFromFilename("Batman #001 (2024)")
        #expect(result.series == "Batman")
        #expect(result.number == "001")
        #expect(result.year == 2024)
    }
}
