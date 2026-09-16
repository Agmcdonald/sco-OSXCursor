//
//  PDFToCBZConverterTests.swift
//  SCO-OSXCursorTests
//
//  End-to-end conversion: PDFs in, verified CBZ out. Sources untouched.
//

import Foundation
import Testing
import ZIPFoundation

@testable import SCO_OSXCursor

struct PDFToCBZConverterTests {

    private func makeMetadata() -> Comic {
        Comic(
            filePath: URL(fileURLWithPath: "/tmp/test.pdf"),
            fileName: "test.pdf",
            publisher: "Image Comics",
            series: "Saga",
            issueNumber: "001",
            year: 2012,
            fileType: .pdf
        )
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConverterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func entryData(_ archive: Archive, _ path: String) throws -> Data {
        let entry = try #require(archive[path])
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        return data
    }

    @Test func convertsScannedPDFLosslesslyWithComicInfo() throws {
        let jpeg = PDFConversionFixtures.solidJPEG(width: 400, height: 600)
        let pdfData = PDFConversionFixtures.jpegOnlyPDF(jpeg: jpeg, width: 400, height: 600)
        let source = try PDFConversionFixtures.writeTemp(pdfData, ext: "pdf")
        let destination = try tempDir()

        let result = try PDFToCBZConverter.convert(
            sources: [source], metadata: makeMetadata(),
            destinationDirectory: destination, baseFileName: "Saga #001 (2012)")

        #expect(result.pageCount == 1)
        #expect(result.cbzURL.lastPathComponent == "Saga #001 (2012).cbz")
        // Source untouched
        #expect(FileManager.default.fileExists(atPath: source.path))

        let archive = try Archive(url: result.cbzURL, accessMode: .read)
        #expect(try entryData(archive, "P00001.jpg") == jpeg)  // lossless
        let xml = try entryData(archive, "ComicInfo.xml")
        let parsed = MetadataParser.parseComicInfo(from: xml)
        #expect(parsed?.series == "Saga")
        #expect(parsed?.pageCount == 1)
    }

    @Test func mergesMultipleSourcesInOrderWithContinuousNumbering() throws {
        let jpegA = PDFConversionFixtures.solidJPEG(width: 400, height: 600)
        let jpegB = PDFConversionFixtures.solidJPEG(width: 402, height: 600)
        let sourceA = try PDFConversionFixtures.writeTemp(
            PDFConversionFixtures.jpegOnlyPDF(jpeg: jpegA, width: 400, height: 600), ext: "pdf")
        let sourceB = try PDFConversionFixtures.writeTemp(
            PDFConversionFixtures.jpegOnlyPDF(jpeg: jpegB, width: 402, height: 600), ext: "pdf")
        let destination = try tempDir()

        let result = try PDFToCBZConverter.convert(
            sources: [sourceA, sourceB], metadata: makeMetadata(),
            destinationDirectory: destination, baseFileName: "Merged")

        #expect(result.pageCount == 2)
        let archive = try Archive(url: result.cbzURL, accessMode: .read)
        #expect(try entryData(archive, "P00001.jpg") == jpegA)
        #expect(try entryData(archive, "P00002.jpg") == jpegB)
    }

    @Test func neverOverwritesAnExistingCBZ() throws {
        let jpeg = PDFConversionFixtures.solidJPEG(width: 400, height: 600)
        let source = try PDFConversionFixtures.writeTemp(
            PDFConversionFixtures.jpegOnlyPDF(jpeg: jpeg, width: 400, height: 600), ext: "pdf")
        let destination = try tempDir()
        let occupied = destination.appendingPathComponent("Book.cbz")
        try Data("not a real cbz".utf8).write(to: occupied)

        let result = try PDFToCBZConverter.convert(
            sources: [source], metadata: makeMetadata(),
            destinationDirectory: destination, baseFileName: "Book")

        #expect(result.cbzURL.lastPathComponent == "Book (2).cbz")
        #expect(try Data(contentsOf: occupied) == Data("not a real cbz".utf8))
    }

    @Test func createsANotYetExistingDestinationDirectory() throws {
        let jpeg = PDFConversionFixtures.solidJPEG(width: 400, height: 600)
        let source = try PDFConversionFixtures.writeTemp(
            PDFConversionFixtures.jpegOnlyPDF(jpeg: jpeg, width: 400, height: 600), ext: "pdf")
        // A destination folder that does not exist yet — not created here.
        let destination = try tempDir().appendingPathComponent("new/nested", isDirectory: true)

        let result = try PDFToCBZConverter.convert(
            sources: [source], metadata: makeMetadata(),
            destinationDirectory: destination, baseFileName: "Fresh")

        #expect(result.pageCount == 1)
        #expect(FileManager.default.fileExists(atPath: result.cbzURL.path))
        #expect(result.cbzURL.deletingLastPathComponent().path == destination.path)
    }

    @Test func garbageInputThrowsCannotOpen() throws {
        let source = try PDFConversionFixtures.writeTemp(Data("junk".utf8), ext: "pdf")
        let destination = try tempDir()
        #expect(throws: PDFConversionError.self) {
            try PDFToCBZConverter.convert(
                sources: [source], metadata: makeMetadata(),
                destinationDirectory: destination, baseFileName: "X")
        }
    }

    @Test func reportsPageProgress() throws {
        let jpeg = PDFConversionFixtures.solidJPEG(width: 400, height: 600)
        let source = try PDFConversionFixtures.writeTemp(
            PDFConversionFixtures.jpegOnlyPDF(jpeg: jpeg, width: 400, height: 600), ext: "pdf")
        let destination = try tempDir()

        // Synchronous callback — collect into a locked box for Sendable
        final class Box: @unchecked Sendable {
            var ticks: [(Int, Int)] = []
            let lock = NSLock()
            func add(_ p: Int, _ t: Int) { lock.lock(); ticks.append((p, t)); lock.unlock() }
        }
        let box = Box()
        _ = try PDFToCBZConverter.convert(
            sources: [source], metadata: makeMetadata(),
            destinationDirectory: destination, baseFileName: "P",
            onPageProgress: { box.add($0, $1) })
        #expect(box.ticks.count == 1)
        #expect(box.ticks.first?.0 == 1)
        #expect(box.ticks.first?.1 == 1)
    }
}
