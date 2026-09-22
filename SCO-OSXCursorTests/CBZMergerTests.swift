//
//  CBZMergerTests.swift
//  SCO-OSXCursorTests
//
//  Tests for CBZMerger — the engine behind "Merge into CBZ…".
//
//  Real archives on disk, not mocks: page ORDER across parts and the
//  refusal to touch anything that already exists are the two things a
//  merge has to get right, and both only mean something against a ZIP.
//

import Foundation
import Testing
import ZIPFoundation

@testable import SCO_OSXCursor

@Suite struct CBZMergerTests {

    // MARK: - Fixtures

    /// Fresh scratch folder, removed by the caller's `defer`.
    private func makeScratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CBZMergerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a CBZ whose pages carry recognisable bytes, so a merged
    /// archive can be checked page-by-page for the right content in the
    /// right place.
    ///
    /// - Parameters:
    ///   - pageNames: entry paths, written in this order (the merger sorts
    ///     them itself — passing them out of order is how the ordering
    ///     guarantee gets tested).
    ///   - payload: called per page name for its bytes.
    @discardableResult
    private func writeCBZ(
        at url: URL,
        pageNames: [String],
        extras: [String: Data] = [:],
        payload: (String) -> Data
    ) throws -> URL {
        let archive = try Archive(url: url, accessMode: .create)
        for name in pageNames {
            let data = payload(name)
            try archive.addEntry(
                with: name, type: .file, uncompressedSize: Int64(data.count),
                compressionMethod: .deflate
            ) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        for (name, data) in extras {
            try archive.addEntry(
                with: name, type: .file, uncompressedSize: Int64(data.count),
                compressionMethod: .deflate
            ) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    private func comic(_ fileName: String, at url: URL, series: String? = "Saga") -> Comic {
        Comic(
            filePath: url,
            fileName: fileName,
            series: series,
            fileType: .cbz
        )
    }

    private func pages(in url: URL) throws -> [(path: String, data: Data)] {
        let archive = try Archive(url: url, accessMode: .read)
        return try CBZReader.sortedImageEntries(from: archive).map { entry in
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            return (entry.path, data)
        }
    }

    // MARK: - Page Order

    @Test func mergeConcatenatesPartsInTheOrderGiven() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Part two is written with its pages out of order on purpose: the
        // merge has to sort within a part and still keep the parts' order.
        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"),
            pageNames: ["001.jpg", "002.jpg"]
        ) { Data("one-\($0)".utf8) }
        let two = try writeCBZ(
            at: scratch.appendingPathComponent("two.cbz"),
            pageNames: ["010.jpg", "002.jpg", "001.jpg"]
        ) { Data("two-\($0)".utf8) }

        let destination = scratch.appendingPathComponent("merged.cbz")
        let outcome = try CBZMerger().merge(
            sources: [
                CBZMergeSource(comic: comic("one.cbz", at: one), url: one),
                CBZMergeSource(comic: comic("two.cbz", at: two), url: two),
            ],
            into: destination,
            metadata: nil
        )

        #expect(outcome.pageCount == 5)
        #expect(outcome.sourceCount == 2)
        #expect(outcome.url == destination)

        let merged = try pages(in: destination)
        #expect(
            merged.map { $0.path } == [
                "0001.jpg", "0002.jpg", "0003.jpg", "0004.jpg", "0005.jpg",
            ])
        #expect(
            merged.map { String(decoding: $0.data) } == [
                "one-001.jpg", "one-002.jpg",
                // Natural sort inside part two: 001, 002, 010 — not 001,
                // 010, 002, and not the order they were written in.
                "two-001.jpg", "two-002.jpg", "two-010.jpg",
            ])
    }

    @Test func mergeKeepsEachPagesFileExtension() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"), pageNames: ["a.png"]
        ) { Data($0.utf8) }
        let two = try writeCBZ(
            at: scratch.appendingPathComponent("two.cbz"), pageNames: ["b.webp"]
        ) { Data($0.utf8) }

        let destination = scratch.appendingPathComponent("merged.cbz")
        try CBZMerger().merge(
            sources: [
                CBZMergeSource(comic: comic("one.cbz", at: one), url: one),
                CBZMergeSource(comic: comic("two.cbz", at: two), url: two),
            ],
            into: destination, metadata: nil)

        let merged = try pages(in: destination)
        #expect(merged.map { $0.path } == ["0001.png", "0002.webp"])
    }

    @Test func mergeIgnoresNonImageEntriesFromTheParts() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        // A part's own ComicInfo.xml describes that one issue — its
        // PageCount and issue number are wrong for the collection, so it
        // must not ride along.
        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"),
            pageNames: ["001.jpg"],
            extras: [
                "ComicInfo.xml": Data("<ComicInfo><Number>1</Number></ComicInfo>".utf8),
                "readme.txt": Data("hello".utf8),
            ]
        ) { Data($0.utf8) }
        let two = try writeCBZ(
            at: scratch.appendingPathComponent("two.cbz"), pageNames: ["001.jpg"]
        ) { Data($0.utf8) }

        let destination = scratch.appendingPathComponent("merged.cbz")
        try CBZMerger().merge(
            sources: [
                CBZMergeSource(comic: comic("one.cbz", at: one), url: one),
                CBZMergeSource(comic: comic("two.cbz", at: two), url: two),
            ],
            into: destination, metadata: nil)

        let archive = try Archive(url: destination, accessMode: .read)
        #expect(archive.map(\.path).sorted() == ["0001.jpg", "0002.jpg"])
    }

    // MARK: - ComicInfo.xml

    @Test func mergeWritesComicInfoForTheCollection() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"), pageNames: ["001.jpg", "002.jpg"]
        ) { Data($0.utf8) }
        let two = try writeCBZ(
            at: scratch.appendingPathComponent("two.cbz"), pageNames: ["001.jpg"]
        ) { Data($0.utf8) }

        let destination = scratch.appendingPathComponent("merged.cbz")
        let template = Comic(
            filePath: destination,
            fileName: "merged.cbz",
            title: "Saga Vol. 1",
            publisher: "Image Comics",
            series: "Saga",
            year: 2012,
            bookFormat: .volume,
            // Deliberately wrong — the merger must overwrite it with the
            // real merged page count.
            totalPages: 999,
            fileType: .cbz
        )

        try CBZMerger().merge(
            sources: [
                CBZMergeSource(comic: comic("one.cbz", at: one), url: one),
                CBZMergeSource(comic: comic("two.cbz", at: two), url: two),
            ],
            into: destination, metadata: template)

        let archive = try Archive(url: destination, accessMode: .read)
        let entry = try #require(CBZMetadataEmbedder.comicInfoEntry(in: archive))
        var xml = Data()
        _ = try archive.extract(entry) { xml.append($0) }
        let text = String(decoding: xml)

        #expect(text.contains("<Title>Saga Vol. 1</Title>"))
        #expect(text.contains("<Series>Saga</Series>"))
        #expect(text.contains("<PageCount>3</PageCount>"))
        #expect(!text.contains("<PageCount>999</PageCount>"))
        // A collection has no single issue number.
        #expect(!text.contains("<Number>"))
    }

    @Test func mergeWithoutMetadataWritesNoComicInfo() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"), pageNames: ["001.jpg"]
        ) { Data($0.utf8) }
        let two = try writeCBZ(
            at: scratch.appendingPathComponent("two.cbz"), pageNames: ["001.jpg"]
        ) { Data($0.utf8) }

        let destination = scratch.appendingPathComponent("merged.cbz")
        try CBZMerger().merge(
            sources: [
                CBZMergeSource(comic: comic("one.cbz", at: one), url: one),
                CBZMergeSource(comic: comic("two.cbz", at: two), url: two),
            ],
            into: destination, metadata: nil)

        let archive = try Archive(url: destination, accessMode: .read)
        #expect(CBZMetadataEmbedder.comicInfoEntry(in: archive) == nil)
    }

    // MARK: - Refusals

    @Test func mergeRefusesFewerThanTwoSources() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"), pageNames: ["001.jpg"]
        ) { Data($0.utf8) }
        let destination = scratch.appendingPathComponent("merged.cbz")

        #expect(throws: CBZMergeError.self) {
            try CBZMerger().merge(
                sources: [CBZMergeSource(comic: comic("one.cbz", at: one), url: one)],
                into: destination, metadata: nil)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func mergeRefusesAnExistingDestinationAndLeavesItIntact() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"), pageNames: ["001.jpg"]
        ) { Data($0.utf8) }
        let two = try writeCBZ(
            at: scratch.appendingPathComponent("two.cbz"), pageNames: ["001.jpg"]
        ) { Data($0.utf8) }

        let destination = scratch.appendingPathComponent("merged.cbz")
        try Data("precious".utf8).write(to: destination)

        #expect(throws: CBZMergeError.self) {
            try CBZMerger().merge(
                sources: [
                    CBZMergeSource(comic: comic("one.cbz", at: one), url: one),
                    CBZMergeSource(comic: comic("two.cbz", at: two), url: two),
                ],
                into: destination, metadata: nil)
        }
        let afterwards = try Data(contentsOf: destination)
        #expect(afterwards == Data("precious".utf8))
    }

    @Test func mergeRefusesAPartWithNoPagesBeforeWritingAnything() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"), pageNames: ["001.jpg"]
        ) { Data($0.utf8) }
        let empty = try writeCBZ(
            at: scratch.appendingPathComponent("empty.cbz"), pageNames: [],
            extras: ["notes.txt": Data("no pages here".utf8)]
        ) { Data($0.utf8) }

        let destination = scratch.appendingPathComponent("merged.cbz")
        #expect(throws: CBZMergeError.self) {
            try CBZMerger().merge(
                sources: [
                    CBZMergeSource(comic: comic("one.cbz", at: one), url: one),
                    CBZMergeSource(comic: comic("empty.cbz", at: empty), url: empty),
                ],
                into: destination, metadata: nil)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func mergeLeavesThePartsUntouched() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"), pageNames: ["001.jpg", "002.jpg"]
        ) { Data($0.utf8) }
        let two = try writeCBZ(
            at: scratch.appendingPathComponent("two.cbz"), pageNames: ["001.jpg"]
        ) { Data($0.utf8) }
        let before = (try Data(contentsOf: one), try Data(contentsOf: two))


        try CBZMerger().merge(
            sources: [
                CBZMergeSource(comic: comic("one.cbz", at: one), url: one),
                CBZMergeSource(comic: comic("two.cbz", at: two), url: two),
            ],
            into: scratch.appendingPathComponent("merged.cbz"), metadata: nil)

        let afterOne = try Data(contentsOf: one)
        let afterTwo = try Data(contentsOf: two)
        #expect(afterOne == before.0)
        #expect(afterTwo == before.1)
    }

    @Test func mergeReportsProgressUpToOne() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let one = try writeCBZ(
            at: scratch.appendingPathComponent("one.cbz"), pageNames: ["001.jpg", "002.jpg"]
        ) { Data($0.utf8) }
        let two = try writeCBZ(
            at: scratch.appendingPathComponent("two.cbz"), pageNames: ["001.jpg", "002.jpg"]
        ) { Data($0.utf8) }

        final class Recorder: @unchecked Sendable {
            var values: [Double] = []
        }
        let recorder = Recorder()

        try CBZMerger().merge(
            sources: [
                CBZMergeSource(comic: comic("one.cbz", at: one), url: one),
                CBZMergeSource(comic: comic("two.cbz", at: two), url: two),
            ],
            into: scratch.appendingPathComponent("merged.cbz"), metadata: nil
        ) { recorder.values.append($0) }

        #expect(recorder.values.count == 4)
        #expect(recorder.values == recorder.values.sorted())
        #expect(recorder.values.last == 1.0)
    }

    // MARK: - Naming Helpers

    @Test func pageNamesPadToTheMergedPageCount() {
        #expect(CBZMerger.pageName(number: 7, total: 9, like: "x/y/p.JPG") == "0007.jpg")
        #expect(CBZMerger.pageName(number: 7, total: 20000, like: "p.jpg") == "00007.jpg")
        #expect(CBZMerger.pageName(number: 1, total: 2, like: "noextension") == "0001")
    }

    @Test func sanitizedFileNameStripsPathAndPaddingCharacters() {
        #expect(CBZMerger.sanitizedFileName("Saga / Vol: 1") == "Saga Vol 1")
        #expect(CBZMerger.sanitizedFileName("  spaced   out  ") == "spaced out")
        #expect(CBZMerger.sanitizedFileName("...") == "Merged Comic")
        #expect(CBZMerger.sanitizedFileName("") == "Merged Comic")
    }

    @Test func availableURLSidestepsNamesAlreadyOnDisk() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }

        #expect(
            CBZMerger.availableURL(in: scratch, baseName: "Saga Vol. 1").lastPathComponent
                == "Saga Vol. 1.cbz")

        try Data().write(to: scratch.appendingPathComponent("Saga Vol. 1.cbz"))
        #expect(
            CBZMerger.availableURL(in: scratch, baseName: "Saga Vol. 1").lastPathComponent
                == "Saga Vol. 1 2.cbz")

        try Data().write(to: scratch.appendingPathComponent("Saga Vol. 1 2.cbz"))
        #expect(
            CBZMerger.availableURL(in: scratch, baseName: "Saga Vol. 1").lastPathComponent
                == "Saga Vol. 1 3.cbz")
    }

    // MARK: - Selection Filtering

    @MainActor
    @Test func mergeableCBZsKeepsOrderAndDropsOtherFormats() {
        let cbz = Comic(
            filePath: URL(fileURLWithPath: "/tmp/a.cbz"), fileName: "a.cbz", fileType: .cbz)
        let pdf = Comic(
            filePath: URL(fileURLWithPath: "/tmp/b.pdf"), fileName: "b.pdf", fileType: .pdf)
        let cbr = Comic(
            filePath: URL(fileURLWithPath: "/tmp/c.cbr"), fileName: "c.cbr", fileType: .cbr)
        var missing = Comic(
            filePath: URL(fileURLWithPath: "/tmp/d.cbz"), fileName: "d.cbz", fileType: .cbz)
        missing.needsAttention = true
        let second = Comic(
            filePath: URL(fileURLWithPath: "/tmp/e.cbz"), fileName: "e.cbz", fileType: .cbz)

        let kept = LibraryViewModel.mergeableCBZs(from: [cbz, pdf, cbr, missing, second])
        #expect(kept.map(\.fileName) == ["a.cbz", "e.cbz"])
    }

    // MARK: - Spec

    @Test func specFileNameFallsBackFromTitleToSeries() {
        var spec = LibraryViewModel.CBZMergeSpec()
        spec.series = "Saga"
        #expect(spec.fileNameBase == "Saga")

        spec.title = "Saga Vol. 1"
        #expect(spec.fileNameBase == "Saga Vol. 1")

        spec.title = "   "
        #expect(spec.fileNameBase == "Saga")

        spec.series = ""
        #expect(spec.fileNameBase == "Merged Comic")
    }
}

// MARK: - Helpers

extension String {
    fileprivate init(decoding data: Data) {
        self = String(data: data, encoding: .utf8) ?? ""
    }
}
