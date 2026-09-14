//
//  ComicInfoWriterTests.swift
//  SCO-OSXCursorTests
//
//  Tests for ComicInfoWriter — the ComicInfo.xml serializer behind
//  "Save Metadata to File".
//

import Foundation
import Testing

@testable import SCO_OSXCursor

struct ComicInfoWriterTests {

    // MARK: - Helpers

    private func makeComic(
        title: String? = nil,
        series: String? = "Saga",
        issueNumber: String? = "001",
        volume: Int? = nil,
        year: Int? = 2012,
        publisher: String? = "Image Comics",
        writer: String? = "Brian K. Vaughan",
        artist: String? = "Fiona Staples",
        summary: String? = nil,
        totalPages: Int = 0,
        tags: [String] = [],
        storyArcs: [String] = [],
        characters: [String] = [],
        contentRating: Comic.ContentRating = .allAges
    ) -> Comic {
        Comic(
            filePath: URL(fileURLWithPath: "/tmp/test.cbz"),
            fileName: "test.cbz",
            title: title,
            publisher: publisher,
            series: series,
            issueNumber: issueNumber,
            volume: volume,
            year: year,
            writer: writer,
            artist: artist,
            summary: summary,
            totalPages: totalPages,
            tags: tags,
            storyArcs: storyArcs,
            characters: characters,
            contentRating: contentRating,
            fileType: .cbz
        )
    }

    private func xmlString(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Fresh Document

    @Test func freshDocumentRoundTripsThroughParser() {
        let comic = makeComic(summary: "A space opera.", totalPages: 32)
        let data = ComicInfoWriter.xmlData(for: comic)

        let parsed = MetadataParser.parseComicInfo(from: data)
        #expect(parsed != nil)
        #expect(parsed?.series == "Saga")
        #expect(parsed?.number == "001")
        #expect(parsed?.year == 2012)
        #expect(parsed?.publisher == "Image Comics")
        #expect(parsed?.writer == "Brian K. Vaughan")
        #expect(parsed?.penciller == "Fiona Staples")
        #expect(parsed?.summary == "A space opera.")
        #expect(parsed?.pageCount == 32)
    }

    @Test func freshDocumentHasDeclarationAndRoot() {
        let data = ComicInfoWriter.xmlData(for: makeComic())
        let xml = xmlString(data)
        #expect(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>"))
        #expect(xml.contains("<ComicInfo"))
        #expect(xml.hasSuffix("</ComicInfo>"))
        // Empty library fields don't produce empty elements.
        #expect(!xml.contains("<Title>"))
        #expect(!xml.contains("<Summary>"))
    }

    // MARK: - Merging: Preservation

    @Test func preservesUntrackedFieldsFromExistingXML() {
        let existing = """
            <?xml version="1.0" encoding="utf-8"?>
            <ComicInfo>
              <Title>Old Title</Title>
              <Series>Old Series</Series>
              <Genre>Science Fiction</Genre>
              <LanguageISO>en</LanguageISO>
              <Month>3</Month>
              <Day>14</Day>
              <Notes>Tagged by ComicTagger</Notes>
              <GTIN>12345</GTIN>
              <Pages>
                <Page Image="0" Type="FrontCover" ImageSize="1234" />
                <Page Image="1" ImageSize="5678" />
              </Pages>
            </ComicInfo>
            """
        let comic = makeComic(title: "New Title", series: "New Series")
        let data = ComicInfoWriter.xmlData(
            for: comic, mergingExisting: Data(existing.utf8))
        let xml = xmlString(data)

        // Library-owned fields reflect the library.
        #expect(xml.contains("<Title>New Title</Title>"))
        #expect(xml.contains("<Series>New Series</Series>"))
        #expect(!xml.contains("Old Title"))

        // Untracked fields survive verbatim.
        #expect(xml.contains("<Genre>Science Fiction</Genre>"))
        #expect(xml.contains("<LanguageISO>en</LanguageISO>"))
        #expect(xml.contains("<Month>3</Month>"))
        #expect(xml.contains("<Day>14</Day>"))
        #expect(xml.contains("<Notes>Tagged by ComicTagger</Notes>"))
        // Unknown element rides along.
        #expect(xml.contains("<GTIN>12345</GTIN>"))
        // Nested Pages block, attributes intact.
        #expect(xml.contains("<Pages>"))
        #expect(xml.contains("Type=\"FrontCover\""))
        #expect(xml.contains("Image=\"1\""))
    }

    @Test func syncedFieldIsRemovedWhenLibraryHoldsItEmpty() {
        let existing = """
            <ComicInfo>
              <Title>Storyline Title</Title>
              <Series>Saga</Series>
              <Editor>Eric Stephenson</Editor>
            </ComicInfo>
            """
        // Library has no title and no editor → both leave the file.
        let comic = makeComic(title: nil)
        let data = ComicInfoWriter.xmlData(
            for: comic, mergingExisting: Data(existing.utf8))
        let xml = xmlString(data)

        #expect(!xml.contains("<Title>"))
        #expect(!xml.contains("<Editor>"))
        #expect(xml.contains("<Series>Saga</Series>"))
    }

    @Test func additiveFieldsPreserveFileValueWhenLibraryIsEmpty() {
        let existing = """
            <ComicInfo>
              <Characters>Alana, Marko</Characters>
              <AgeRating>Teen</AgeRating>
              <PageCount>28</PageCount>
            </ComicInfo>
            """
        // Library never captured characters/rating/pages → file wins.
        let comic = makeComic(totalPages: 0)
        let data = ComicInfoWriter.xmlData(
            for: comic, mergingExisting: Data(existing.utf8))
        let xml = xmlString(data)

        #expect(xml.contains("<Characters>Alana, Marko</Characters>"))
        #expect(xml.contains("<AgeRating>Teen</AgeRating>"))
        #expect(xml.contains("<PageCount>28</PageCount>"))
    }

    @Test func additiveFieldsOverwriteWhenLibraryHasValues() {
        let existing = """
            <ComicInfo>
              <Characters>Someone Else</Characters>
              <AgeRating>Everyone</AgeRating>
            </ComicInfo>
            """
        let comic = makeComic(
            characters: ["Alana", "Marko"],
            contentRating: .mature
        )
        let data = ComicInfoWriter.xmlData(
            for: comic, mergingExisting: Data(existing.utf8))
        let xml = xmlString(data)

        #expect(xml.contains("<Characters>Alana, Marko</Characters>"))
        #expect(xml.contains("<AgeRating>Mature 17+</AgeRating>"))
        #expect(!xml.contains("Someone Else"))
    }

    @Test func tagsAndStoryArcsAreWritten() {
        let comic = makeComic(
            tags: ["Favorites", "Space"],
            storyArcs: ["Chapter One"]
        )
        let xml = xmlString(ComicInfoWriter.xmlData(for: comic))
        #expect(xml.contains("<Tags>Favorites, Space</Tags>"))
        #expect(xml.contains("<StoryArc>Chapter One</StoryArc>"))
    }

    // MARK: - Escaping

    @Test func escapesReservedCharacters() {
        let comic = makeComic(
            series: "Mice & <Mystics>",
            summary: "Cats > mice & \"cheese\""
        )
        let xml = xmlString(ComicInfoWriter.xmlData(for: comic))
        #expect(xml.contains("<Series>Mice &amp; &lt;Mystics&gt;</Series>"))
        #expect(xml.contains("<Summary>Cats &gt; mice &amp; \"cheese\"</Summary>"))
    }

    // MARK: - Robustness

    @Test func malformedExistingXMLFallsBackToFreshDocument() {
        let broken = Data("<ComicInfo><Title>Unclosed".utf8)
        let data = ComicInfoWriter.xmlData(for: makeComic(), mergingExisting: broken)
        let parsed = MetadataParser.parseComicInfo(from: data)
        #expect(parsed?.series == "Saga")
    }

    @Test func reEmbeddingOwnOutputIsByteIdentical() {
        // The embedder skips the file rewrite when the merged XML equals
        // what's already in the archive — that only works if a second pass
        // over our own output is byte-identical.
        let comic = makeComic(
            title: "The Brand New Day",
            summary: "Multi\nline summary.",
            totalPages: 32,
            tags: ["Favorites"],
            contentRating: .teen
        )
        let first = ComicInfoWriter.xmlData(for: comic)
        let second = ComicInfoWriter.xmlData(for: comic, mergingExisting: first)
        #expect(first == second)
    }
}
