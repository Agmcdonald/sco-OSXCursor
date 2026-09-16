//
//  ConversionDestinationTests.swift
//  SCO-OSXCursorTests
//
//  Where convertPDFToCBZ writes the CBZ: beside the PDF inside the home
//  library, INTO the library for out-of-library books, beside the PDF
//  when no library is set.
//

import Foundation
import Testing

@testable import SCO_OSXCursor

struct ConversionDestinationTests {

    private func makeComic(filePath: URL) -> Comic {
        Comic(
            filePath: filePath,
            fileName: filePath.lastPathComponent,
            publisher: "DC Comics",
            series: "Batman",
            issueNumber: "012",
            year: 2024,
            fileType: .pdf
        )
    }

    @Test func insideLibraryConvertsBesideThePDF() {
        let root = URL(fileURLWithPath: "/Library/Comics", isDirectory: true)
        let source = root.appendingPathComponent("DC Comics/Batman/Batman #012 (2024).pdf")
        let plan = LibraryViewModel.conversionDestination(
            source: source, comic: makeComic(filePath: source), libraryRoot: root,
            folderStructure: .publisherSeriesIssue)
        #expect(plan.directory.standardizedFileURL.path == "/Library/Comics/DC Comics/Batman")
        #expect(plan.baseName == "Batman #012 (2024)")
    }

    @Test func outsideLibraryConvertsIntoTheLibrary() {
        let root = URL(fileURLWithPath: "/Library/Comics", isDirectory: true)
        let source = URL(fileURLWithPath: "/Downloads/Ch 001.pdf")
        let plan = LibraryViewModel.conversionDestination(
            source: source, comic: makeComic(filePath: source), libraryRoot: root,
            folderStructure: .publisherSeriesIssue)
        // destinationURL files under Publisher/Series with the cleaned name
        #expect(plan.directory.standardizedFileURL.path == "/Library/Comics/DC Comics/Batman")
        #expect(plan.baseName.hasPrefix("Batman"))
        #expect(!plan.baseName.hasSuffix(".pdf"))
    }

    @Test func noLibraryConvertsBesideThePDF() {
        let source = URL(fileURLWithPath: "/Downloads/Ch 001.pdf")
        let plan = LibraryViewModel.conversionDestination(
            source: source, comic: makeComic(filePath: source), libraryRoot: nil,
            folderStructure: .publisherSeriesIssue)
        #expect(plan.directory.standardizedFileURL.path == "/Downloads")
        #expect(plan.baseName == "Ch 001")
    }
}
