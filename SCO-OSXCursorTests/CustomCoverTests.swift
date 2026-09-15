//
//  CustomCoverTests.swift
//  SCO-OSXCursorTests
//
//  Custom book covers: display precedence, Codable round-trip, and
//  rescan-merge preservation.
//

import Foundation
import Testing

#if os(macOS)
    import AppKit
#endif

@testable import SCO_OSXCursor

@Suite struct CustomCoverTests {

    private func makeComic() -> Comic {
        Comic(
            filePath: URL(fileURLWithPath: "/tmp/lib/Webtoon/Strip #001.cbz"),
            fileName: "Strip #001.cbz",
            coverImageData: Data([0x01, 0x02])
        )
    }

    @Test func displayCoverPrefersCustomAndRestoresExtracted() {
        var c = makeComic()
        #expect(c.displayCoverData == Data([0x01, 0x02]))
        c.customCoverImageData = Data([0x0A, 0x0B])
        #expect(c.displayCoverData == Data([0x0A, 0x0B]))
        c.customCoverImageData = nil
        #expect(c.displayCoverData == Data([0x01, 0x02]))
    }

    @Test func displayCoverNilWhenBothAbsent() {
        var c = makeComic()
        c.coverImageData = nil
        #expect(c.displayCoverData == nil)
    }

    @Test func codableRoundTripKeepsCustomCover() throws {
        var c = makeComic()
        c.customCoverImageData = Data([0x0A, 0x0B])
        let decoded = try JSONDecoder().decode(Comic.self, from: JSONEncoder().encode(c))
        #expect(decoded.customCoverImageData == Data([0x0A, 0x0B]))
    }

    // Trash snapshots and .scobook manifests written before this feature
    // have no customCoverImageData key — they must decode to nil, not throw.
    @Test func decodingSnapshotWithoutFieldYieldsNil() throws {
        let decoded = try JSONDecoder().decode(
            Comic.self, from: JSONEncoder().encode(makeComic()))
        #expect(decoded.customCoverImageData == nil)
    }

    @Test func rescanMergePreservesCustomCover() {
        var existing = makeComic()
        existing.customCoverImageData = Data([0x0A, 0x0B])
        var extracted = makeComic()
        extracted.coverImageData = Data([0x03, 0x04])  // fresh first-page extraction
        let merged = Comic.merged(existing: existing, extracted: extracted)
        #expect(merged.customCoverImageData == Data([0x0A, 0x0B]))
        #expect(merged.coverImageData == Data([0x03, 0x04]))
        #expect(merged.displayCoverData == Data([0x0A, 0x0B]))
    }

    // The webcomic case: normalization must cap the long side at 800 px, so
    // a picked image never bloats the DB (and the sliver problem the custom
    // cover exists to fix stays fixed for the stored bytes).
    #if os(macOS)
        @Test func storageNormalizationCapsTallStrips() throws {
            let size = NSSize(width: 200, height: 4000)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.red.setFill()
            NSRect(origin: .zero, size: size).fill()
            image.unlockFocus()
            let raw = try #require(PageImageCache.jpegData(from: image, quality: 0.9))
            let stored = try #require(PageImageCache.storageCoverData(from: raw))
            let rep = try #require(NSBitmapImageRep(data: stored))
            #expect(max(rep.pixelsWide, rep.pixelsHigh) <= 800)
        }
    #endif
}
