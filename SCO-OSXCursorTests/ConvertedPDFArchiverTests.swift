//
//  ConvertedPDFArchiverTests.swift
//  SCO-OSXCursorTests
//
//  Filing converted originals under <root>/Converted PDFs/… with a path
//  that mirrors where the book lives (or would live) in the library.
//

import Foundation
import Testing

@testable import SCO_OSXCursor

struct ConvertedPDFArchiverTests {

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

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

    @Test func mirrorsParentFolderForBooksInsideTheRoot() throws {
        let root = try makeRoot()
        let filePath = root
            .appendingPathComponent("DC Comics/Batman", isDirectory: true)
            .appendingPathComponent("Batman #012 (2024).pdf")
        let subpath = ConvertedPDFArchiver.mirrorSubpath(
            for: makeComic(filePath: filePath), libraryRoot: root,
            folderStructure: .publisherSeriesIssue)
        #expect(subpath == "DC Comics/Batman")
    }

    @Test func fallsBackToDestinationFolderForBooksOutsideTheRoot() throws {
        let root = try makeRoot()
        let filePath = URL(fileURLWithPath: "/Users/nobody/Downloads/Batman #012 (2024).pdf")
        let subpath = ConvertedPDFArchiver.mirrorSubpath(
            for: makeComic(filePath: filePath), libraryRoot: root,
            folderStructure: .publisherSeriesIssue)
        // destinationURL files under Publisher/Series for the default structure
        #expect(subpath == "DC Comics/Batman")
    }

    @Test func relativePathReturnsNilOutsideRoot() throws {
        let root = try makeRoot()
        #expect(ConvertedPDFArchiver.relativePath(
            of: URL(fileURLWithPath: "/elsewhere/x"), under: root) == nil)
        #expect(ConvertedPDFArchiver.relativePath(of: root, under: root) == "")
    }

    @Test func archiveOriginalMovesFileAndResolvesConflicts() throws {
        let root = try makeRoot()
        let original = root.appendingPathComponent("Book.pdf")
        try Data("pdf-one".utf8).write(to: original)

        let archived = try ConvertedPDFArchiver.archiveOriginal(
            original, libraryRoot: root, mirrorSubpath: "DC Comics/Batman")
        #expect(archived.path.hasSuffix("Converted PDFs/DC Comics/Batman/Book.pdf"))
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(try Data(contentsOf: archived) == Data("pdf-one".utf8))

        // Second file with the same name → " (2)", first is untouched
        try Data("pdf-two".utf8).write(to: original)
        let archived2 = try ConvertedPDFArchiver.archiveOriginal(
            original, libraryRoot: root, mirrorSubpath: "DC Comics/Batman")
        #expect(archived2.lastPathComponent == "Book (2).pdf")
        #expect(try Data(contentsOf: archived) == Data("pdf-one".utf8))
    }
}
