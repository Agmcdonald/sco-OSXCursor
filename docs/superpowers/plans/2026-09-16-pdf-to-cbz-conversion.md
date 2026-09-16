# PDF → CBZ Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert PDF comics to CBZ — automatically during Organize (opt-in), by merging several staged PDFs into one CBZ, or post-hoc from the library — with originals preserved under `<LibraryRoot>/Converted PDFs/…`.

**Architecture:** A pure conversion layer (`PDFPageExtractor` → `PDFToCBZConverter` → `ConvertedPDFArchiver`, all in `SCO-OSXCursor/Services/Conversion/`) with zero UI/DB knowledge, orchestrated by a `LibraryViewModel` extension (post-hoc path) and `OrganizeViewModel.confirmMatch` (organize path). Smart-hybrid page images: lossless copy of embedded full-page JPEGs via CGPDF, PDFKit render fallback otherwise.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, PDFKit + CoreGraphics (CGPDF), ZIPFoundation 0.9.20, GRDB 7.8.0, Swift Testing (`import Testing`, `@Test`, `#expect`).

**Spec:** `docs/superpowers/specs/2026-09-16-pdf-to-cbz-conversion-design.md`

## Global Constraints

- Repo root: `/Users/andrewmcdonald/Documents/Apps/Current XCode Projects/SCO-OSXAntigrav/sco-OSXCursor`. All paths below are relative to it. App sources live in `SCO-OSXCursor/`, tests in `SCO-OSXCursorTests/`.
- The Xcode project uses **file-system synchronized groups** — a new `.swift` file saved under `SCO-OSXCursor/` or `SCO-OSXCursorTests/` joins its target automatically. Never edit `project.pbxproj`.
- **Never delete a user file.** Originals are only ever *moved*, and only after the CBZ verifies. Conflicts get " (2)" suffixes via `LibraryFileService.resolveConflict`.
- **Never add a field to the `AppSettings` Codable struct** for this feature. The codebase stores opt-in flags under their own UserDefaults keys instead (see comment at `SCO-OSXCursor/ViewModels/LibraryViewModel.swift:605-608` — a new required Codable field invalidates previously saved settings). The organize toggle uses key `"convertPDFsOnOrganize"`. This intentionally supersedes the spec's "add to AppSettings with safe default" wording; spec intent (old settings survive) is preserved.
- Cross-platform: guard AppKit with `#if os(macOS)`; UI code compiles for iOS too (test files are macOS-only and may use AppKit freely).
- Unit tests use Swift Testing, style of `SCO-OSXCursorTests/ComicInfoWriterTests.swift` (`@testable import SCO_OSXCursor`).
- Build check: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet` (from repo root). Expect exit 0.
- Test run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/<SuiteName> -quiet`.
- Commit after every task, message style `feat(convert): …` / `test(convert): …`, ending with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- `.claude/worktrees/*` contains stale tree copies — never read or edit files there. Also ignore the dead files `SCO-OSXCursor.xcodeproj/SCO-OSXCursor/Services/Organization/FileOrganizer.swift` and `.../Database/DatabaseManager.swift` (not in any target).

---

### Task 1: PDFPageExtractor (smart hybrid page images)

**Files:**
- Modify: `SCO-OSXCursor/Services/ComicReader/PDFReader.swift:221` (make `renderPageToImageData` internal static)
- Create: `SCO-OSXCursor/Services/Conversion/PDFPageExtractor.swift`
- Create: `SCO-OSXCursorTests/PDFConversionFixtures.swift`
- Test: `SCO-OSXCursorTests/PDFPageExtractorTests.swift`

**Interfaces:**
- Consumes: `PDFReader.renderPageToImageData(_ page: PDFPage) -> Data` (after this task's refactor).
- Produces: `PDFPageExtractor.imageData(for: PDFPage) -> Data` and `PDFPageExtractor.losslessJPEGData(for: PDFPage) -> Data?` (both `static`, enum namespace). Test fixtures: `PDFConversionFixtures.solidJPEG(width:height:) -> Data`, `PDFConversionFixtures.jpegOnlyPDF(jpeg:width:height:) -> Data`, `PDFConversionFixtures.textPDF() -> Data`.

- [ ] **Step 1: Refactor `PDFReader.renderPageToImageData` to internal static**

In `SCO-OSXCursor/Services/ComicReader/PDFReader.swift`, change line 221:

```swift
// BEFORE
    private func renderPageToImageData(_ page: PDFPage) -> Data {
// AFTER
    static func renderPageToImageData(_ page: PDFPage) -> Data {
```

Body unchanged (it uses no instance state). Update the three call sites inside PDFReader (lines 90, 143, 183): `renderPageToImageData(pdfPage)` → `Self.renderPageToImageData(pdfPage)` (and `…(firstPage)` at 183).

- [ ] **Step 2: Write the test fixtures helper**

Create `SCO-OSXCursorTests/PDFConversionFixtures.swift`:

```swift
//
//  PDFConversionFixtures.swift
//  SCO-OSXCursorTests
//
//  Deterministic PDF/JPEG fixtures for the PDF → CBZ conversion tests.
//  jpegOnlyPDF is hand-assembled so the JPEG bytes land in the PDF
//  verbatim as a DCTDecode image XObject — drawing through a CGContext
//  would re-encode them and defeat the lossless-extraction tests.
//

import AppKit
import CoreText
import Foundation

enum PDFConversionFixtures {

    /// Solid-color JPEG of the given pixel size.
    static func solidJPEG(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
    }

    /// Single-page PDF that is exactly one full-page DCTDecode image —
    /// the shape of a scanned comic page. MediaBox matches the image's
    /// pixel size (72 dpi) so the aspect ratios agree exactly.
    static func jpegOnlyPDF(jpeg: Data, width: Int, height: Int) -> Data {
        var pdf = Data()
        var offsets: [Int] = []
        func append(_ string: String) { pdf.append(string.data(using: .ascii)!) }
        func beginObject(_ number: Int) {
            offsets.append(pdf.count)
            append("\(number) 0 obj\n")
        }

        append("%PDF-1.4\n")
        beginObject(1)
        append("<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
        beginObject(2)
        append("<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
        beginObject(3)
        append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(width) \(height)] ")
        append("/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>\nendobj\n")
        beginObject(4)
        append("<< /Type /XObject /Subtype /Image /Width \(width) /Height \(height) ")
        append("/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode ")
        append("/Length \(jpeg.count) >>\nstream\n")
        pdf.append(jpeg)
        append("\nendstream\nendobj\n")
        let contents = "q \(width) 0 0 \(height) 0 0 cm /Im0 Do Q"
        beginObject(5)
        append("<< /Length \(contents.count) >>\nstream\n\(contents)\nendstream\nendobj\n")

        let xrefStart = pdf.count
        append("xref\n0 6\n")
        append("0000000000 65535 f \n")
        for offset in offsets {
            append(String(format: "%010d 00000 n \n", offset))
        }
        append("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xrefStart)\n%%EOF\n")
        return pdf
    }

    /// Single-page PDF containing drawn text (embeds a /Font resource) —
    /// must take the render fallback, never the lossless path.
    static func textPDF() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
        context.beginPDFPage(nil)
        let attributed = NSAttributedString(
            string: "Hello, comics!",
            attributes: [.font: NSFont.systemFont(ofSize: 24)])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// Writes `data` to a unique temp file with the given extension and
    /// returns its URL. Caller may delete; temp dir is per-test-run.
    static func writeTemp(_ data: Data, ext: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFConversionFixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fixture-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }
}
```

- [ ] **Step 3: Write the failing tests**

Create `SCO-OSXCursorTests/PDFPageExtractorTests.swift`:

```swift
//
//  PDFPageExtractorTests.swift
//  SCO-OSXCursorTests
//
//  Smart-hybrid page extraction: lossless JPEG passthrough for scanned
//  (single-image) pages, PDFKit render fallback for everything else.
//

import Foundation
import PDFKit
import Testing

@testable import SCO_OSXCursor

struct PDFPageExtractorTests {

    private func page(from pdfData: Data) throws -> PDFPage {
        let doc = try #require(PDFDocument(data: pdfData))
        return try #require(doc.page(at: 0))
    }

    @Test func losslessPathReturnsExactJPEGBytes() throws {
        let jpeg = PDFConversionFixtures.solidJPEG(width: 400, height: 600)
        let pdf = PDFConversionFixtures.jpegOnlyPDF(jpeg: jpeg, width: 400, height: 600)
        let extracted = PDFPageExtractor.losslessJPEGData(for: try page(from: pdf))
        #expect(extracted == jpeg)
    }

    @Test func imageDataUsesLosslessPathForScannedPage() throws {
        let jpeg = PDFConversionFixtures.solidJPEG(width: 400, height: 600)
        let pdf = PDFConversionFixtures.jpegOnlyPDF(jpeg: jpeg, width: 400, height: 600)
        #expect(PDFPageExtractor.imageData(for: try page(from: pdf)) == jpeg)
    }

    @Test func textPageDeclinesLosslessPath() throws {
        let pdf = PDFConversionFixtures.textPDF()
        #expect(PDFPageExtractor.losslessJPEGData(for: try page(from: pdf)) == nil)
    }

    @Test func textPageStillRendersNonEmptyJPEG() throws {
        let pdf = PDFConversionFixtures.textPDF()
        let data = PDFPageExtractor.imageData(for: try page(from: pdf))
        #expect(!data.isEmpty)
        // JPEG magic bytes FF D8
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func aspectMismatchDeclinesLosslessPath() throws {
        // Image 400×600 declared on a square 600×600 page → not full-page
        let jpeg = PDFConversionFixtures.solidJPEG(width: 400, height: 600)
        var pdf = PDFConversionFixtures.jpegOnlyPDF(jpeg: jpeg, width: 400, height: 600)
        // Rebuild with a mismatched MediaBox by string surgery on the fixture
        let s = String(decoding: pdf, as: UTF8.self)
            .replacingOccurrences(of: "/MediaBox [0 0 400 600]", with: "/MediaBox [0 0 600 600]")
        pdf = Data(s.utf8)
        #expect(PDFPageExtractor.losslessJPEGData(for: try page(from: pdf)) == nil)
    }
}
```

Note: the string-surgery in the last test is safe — the JPEG bytes survive a UTF-8 round trip is NOT guaranteed, so instead of `String(decoding:)`, implement it by locating the ASCII range: use `pdf.range(of: Data("/MediaBox [0 0 400 600]".utf8))` and `pdf.replaceSubrange(range, with: Data("/MediaBox [0 0 600 600]".utf8))` (same byte length not required — Data.replaceSubrange handles it, and the xref offsets shifting doesn't matter because PDFKit repairs simple offset damage; if `PDFDocument(data:)` returns nil in practice, change `jpegOnlyPDF` to accept an optional `mediaBox: (Int, Int)?` parameter instead and pass `(600, 600)` — preferred, do this from the start):

Actually, **do the parameter version from the start** — add to `jpegOnlyPDF`:

```swift
static func jpegOnlyPDF(jpeg: Data, width: Int, height: Int,
                        mediaBox: (width: Int, height: Int)? = nil) -> Data {
    let boxW = mediaBox?.width ?? width
    let boxH = mediaBox?.height ?? height
    // … and in object 3 use \(boxW) \(boxH), and in object 5's cm matrix use \(boxW) / \(boxH)
```

and the test becomes:

```swift
    @Test func aspectMismatchDeclinesLosslessPath() throws {
        let jpeg = PDFConversionFixtures.solidJPEG(width: 400, height: 600)
        let pdf = PDFConversionFixtures.jpegOnlyPDF(
            jpeg: jpeg, width: 400, height: 600, mediaBox: (600, 600))
        #expect(PDFPageExtractor.losslessJPEGData(for: try page(from: pdf)) == nil)
    }
```

- [ ] **Step 4: Run tests, expect compile failure (PDFPageExtractor undefined)**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/PDFPageExtractorTests -quiet`
Expected: FAIL — `cannot find 'PDFPageExtractor' in scope`.

- [ ] **Step 5: Implement PDFPageExtractor**

Create `SCO-OSXCursor/Services/Conversion/PDFPageExtractor.swift`:

```swift
//
//  PDFPageExtractor.swift
//  SCO-OSXCursor
//
//  Produces page images for PDF → CBZ conversion ("smart hybrid"): a page
//  that is exactly one full-page DCTDecode (JPEG) image with no text layer
//  has its JPEG bytes copied out losslessly; every other page falls back
//  to PDFReader's PDFKit render (2×, long side ≤ 8000 px, JPEG q0.85).
//

import Foundation
import PDFKit

enum PDFPageExtractor {

    /// JPEG data for a page — lossless extraction when safe, render otherwise.
    static func imageData(for page: PDFPage) -> Data {
        if let lossless = losslessJPEGData(for: page) {
            return lossless
        }
        return PDFReader.renderPageToImageData(page)
    }

    /// The page's embedded JPEG bytes, when the page is exactly one
    /// full-page DCTDecode image and nothing else. Returns nil whenever
    /// any condition fails — callers fall back to rendering.
    ///
    /// Conditions:
    /// - page rotation is 0 (raw bytes would come out unrotated)
    /// - no /Font resources (a font implies a text layer)
    /// - every XObject is an image, there is exactly one, and it has no
    ///   /SMask (a soft mask's transparency would be lost)
    /// - image aspect ratio within 20% of the page's (full-page scan)
    /// - the stream decodes as .jpegEncoded (DCTDecode)
    static func losslessJPEGData(for page: PDFPage) -> Data? {
        guard abs(page.rotation % 360) == 0,
              let pageRef = page.pageRef,
              let pageDict = pageRef.dictionary
        else { return nil }

        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources),
              let resources
        else { return nil }

        var fonts: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Font", &fonts),
           let fonts, CGPDFDictionaryGetCount(fonts) > 0 {
            return nil
        }

        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects),
              let xObjects
        else { return nil }

        var images: [(stream: CGPDFStreamRef, width: Int, height: Int)] = []
        var disqualified = false
        CGPDFDictionaryApplyBlock(xObjects, { _, value, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(value, .stream, &stream),
                  let stream,
                  let streamDict = CGPDFStreamGetDictionary(stream)
            else {
                disqualified = true
                return true
            }
            var subtype: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtype),
                  let subtype, String(cString: subtype) == "Image"
            else {
                disqualified = true
                return true
            }
            var maskObject: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(streamDict, "SMask", &maskObject) {
                disqualified = true
                return true
            }
            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            CGPDFDictionaryGetInteger(streamDict, "Width", &width)
            CGPDFDictionaryGetInteger(streamDict, "Height", &height)
            images.append((stream, Int(width), Int(height)))
            return true
        }, nil)

        guard !disqualified, images.count == 1,
              let image = images.first,
              image.width > 0, image.height > 0
        else { return nil }

        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let pageAspect = bounds.width / bounds.height
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        guard abs(imageAspect - pageAspect) / pageAspect <= 0.2 else { return nil }

        var format = CGPDFDataFormat.raw
        guard let cfData = CGPDFStreamCopyData(image.stream, &format),
              format == .jpegEncoded
        else { return nil }
        return cfData as Data
    }
}
```

- [ ] **Step 6: Run tests, expect pass**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/PDFPageExtractorTests -quiet`
Expected: PASS (5 tests). If `losslessPathReturnsExactJPEGBytes` fails with nil, debug by printing which guard failed — most likely candidate is the fixture's xref (check `PDFDocument(data:)` non-nil first) or `CGPDFObjectGetValue` needing `.stream` type constant `CGPDFObjectType.stream`.

- [ ] **Step 7: Commit**

```bash
git add SCO-OSXCursor/Services/Conversion/PDFPageExtractor.swift SCO-OSXCursor/Services/ComicReader/PDFReader.swift SCO-OSXCursorTests/PDFConversionFixtures.swift SCO-OSXCursorTests/PDFPageExtractorTests.swift
git commit -m "feat(convert): smart-hybrid PDF page extraction (lossless JPEG + render fallback)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: PDFToCBZConverter (archive assembly + verify + place)

**Files:**
- Modify: `SCO-OSXCursor/Services/ComicReader/CBZMetadataEmbedder.swift:185` (make `imageEntryCount` internal)
- Create: `SCO-OSXCursor/Services/Conversion/PDFToCBZConverter.swift`
- Test: `SCO-OSXCursorTests/PDFToCBZConverterTests.swift`

**Interfaces:**
- Consumes: `PDFPageExtractor.imageData(for:)` (Task 1), `ComicInfoWriter.xmlData(for:mergingExisting:)`, `CBZMetadataEmbedder.entryPath` / `.comicInfoEntry(in:)` / `.imageEntryCount(in:)`, `LibraryFileService.shared.resolveConflict(at:)`.
- Produces:
  - `enum PDFConversionError: LocalizedError { case cannotOpen(String), encrypted(String), noPages(String), verificationFailed }`
  - `PDFToCBZConverter.convert(sources: [URL], metadata: Comic, destinationDirectory: URL, baseFileName: String, onPageProgress: @Sendable (Int, Int) -> Void) throws -> ConversionResult` (static, synchronous — call from a background task)
  - `struct ConversionResult { let cbzURL: URL; let pageCount: Int }` (nested in PDFToCBZConverter)

- [ ] **Step 1: Make `imageEntryCount` internal**

In `SCO-OSXCursor/Services/ComicReader/CBZMetadataEmbedder.swift` line 185:

```swift
// BEFORE
    private static func imageEntryCount(in archive: Archive) -> Int {
// AFTER
    /// Page-image count (jpg/jpeg/png/gif/webp/bmp, skipping __MACOSX).
    static func imageEntryCount(in archive: Archive) -> Int {
```

- [ ] **Step 2: Write the failing tests**

Create `SCO-OSXCursorTests/PDFToCBZConverterTests.swift`:

```swift
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
```

- [ ] **Step 3: Run tests, expect compile failure**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/PDFToCBZConverterTests -quiet`
Expected: FAIL — `cannot find 'PDFToCBZConverter' in scope`.

- [ ] **Step 4: Implement PDFToCBZConverter**

Create `SCO-OSXCursor/Services/Conversion/PDFToCBZConverter.swift`:

```swift
//
//  PDFToCBZConverter.swift
//  SCO-OSXCursor
//
//  Converts one or more PDFs (in order) into a single verified CBZ.
//
//  Safety contract (mirrors CBZMetadataEmbedder): the archive is
//  assembled in a temp folder on the destination's volume, re-opened and
//  verified (image entry count == page count, ComicInfo.xml present),
//  and only then moved into place — conflict-safe, never overwriting.
//  Source PDFs are never modified or deleted by this type.
//
//  Synchronous & self-contained: call from a background task. The caller
//  is responsible for security-scoped access to the sources and the
//  destination directory.
//

import Foundation
import PDFKit
import ZIPFoundation
import os

// MARK: - Errors

enum PDFConversionError: LocalizedError {
    case cannotOpen(String)
    case encrypted(String)
    case noPages(String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let name):
            return "\"\(name)\" couldn't be opened as a PDF."
        case .encrypted(let name):
            return "\"\(name)\" is password-protected. Remove the password, then convert."
        case .noPages(let name):
            return "\"\(name)\" has no pages."
        case .verificationFailed:
            return "The converted CBZ failed verification. The original PDF was not modified."
        }
    }
}

// MARK: - Converter

final class PDFToCBZConverter {

    struct ConversionResult {
        let cbzURL: URL
        let pageCount: Int
    }

    /// Converts `sources` (in order) into `<destinationDirectory>/<baseFileName>.cbz`.
    ///
    /// Pages are named P00001.jpg… with numbering continuous across
    /// sources and stored uncompressed (they're JPEGs — deflating is
    /// waste, same reasoning as BookPackageExporter). A fresh
    /// ComicInfo.xml built from `metadata` (PageCount corrected to the
    /// real total) is added deflated. `onPageProgress` receives
    /// (pagesDone, totalPages) per page.
    static func convert(
        sources: [URL],
        metadata: Comic,
        destinationDirectory: URL,
        baseFileName: String,
        onPageProgress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) throws -> ConversionResult {
        precondition(!sources.isEmpty, "convert() needs at least one source")
        let fm = FileManager.default

        // ── Open every source up front so failures precede any writing ──
        var documents: [PDFDocument] = []
        for url in sources {
            guard let document = PDFDocument(url: url) else {
                throw PDFConversionError.cannotOpen(url.lastPathComponent)
            }
            if document.isLocked || document.isEncrypted {
                throw PDFConversionError.encrypted(url.lastPathComponent)
            }
            if document.pageCount == 0 {
                throw PDFConversionError.noPages(url.lastPathComponent)
            }
            documents.append(document)
        }
        let totalPages = documents.reduce(0) { $0 + $1.pageCount }

        // ── Assemble in a temp dir on the destination volume ──
        let tempDir = try fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destinationDirectory, create: true)
        defer { try? fm.removeItem(at: tempDir) }
        let tempURL = tempDir.appendingPathComponent("\(baseFileName).cbz")
        let archive = try Archive(url: tempURL, accessMode: .create)

        var pageNumber = 0
        for document in documents {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else {
                    throw PDFConversionError.verificationFailed
                }
                pageNumber += 1
                let imageData = autoreleasepool { PDFPageExtractor.imageData(for: page) }
                guard !imageData.isEmpty else {
                    throw PDFConversionError.verificationFailed
                }
                try archive.addEntry(
                    with: String(format: "P%05d.jpg", pageNumber), type: .file,
                    uncompressedSize: Int64(imageData.count),
                    compressionMethod: .none
                ) { position, size in
                    let start = Int(position)
                    return imageData.subdata(in: start..<start + size)
                }
                onPageProgress(pageNumber, totalPages)
            }
        }

        // ── ComicInfo.xml (fresh — a brand-new file has nothing to merge) ──
        var comicForXML = metadata
        comicForXML.totalPages = totalPages
        let xml = ComicInfoWriter.xmlData(for: comicForXML, mergingExisting: nil)
        try archive.addEntry(
            with: CBZMetadataEmbedder.entryPath, type: .file,
            uncompressedSize: Int64(xml.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            return xml.subdata(in: start..<start + size)
        }

        // ── Verify before the CBZ may exist at the destination ──
        let check = try Archive(url: tempURL, accessMode: .read)
        guard CBZMetadataEmbedder.imageEntryCount(in: check) == totalPages,
              CBZMetadataEmbedder.comicInfoEntry(in: check) != nil
        else { throw PDFConversionError.verificationFailed }

        // ── Move into place, never overwriting ──
        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        var destination = destinationDirectory.appendingPathComponent("\(baseFileName).cbz")
        destination = LibraryFileService.shared.resolveConflict(at: destination)
        try fm.moveItem(at: tempURL, to: destination)

        AppLog.files.info(
            "[PDFToCBZConverter] ✅ \(sources.count) PDF(s) → \(destination.lastPathComponent) (\(totalPages) pages)")
        return ConversionResult(cbzURL: destination, pageCount: totalPages)
    }
}
```

- [ ] **Step 5: Run tests, expect pass**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/PDFToCBZConverterTests -quiet`
Expected: PASS (5 tests). Also re-run Task 1's suite (embedder change): `-only-testing:SCO-OSXCursorTests/PDFPageExtractorTests` — PASS.

- [ ] **Step 6: Commit**

```bash
git add SCO-OSXCursor/Services/Conversion/PDFToCBZConverter.swift SCO-OSXCursor/Services/ComicReader/CBZMetadataEmbedder.swift SCO-OSXCursorTests/PDFToCBZConverterTests.swift
git commit -m "feat(convert): PDFToCBZConverter — verified, conflict-safe CBZ assembly

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: ConvertedPDFArchiver (originals filing) + LibraryFileService.moveFile

**Files:**
- Modify: `SCO-OSXCursor/Services/LibraryFileService.swift` (add `moveFile(at:to:)` near `moveToLibrary`)
- Create: `SCO-OSXCursor/Services/Conversion/ConvertedPDFArchiver.swift`
- Test: `SCO-OSXCursorTests/ConvertedPDFArchiverTests.swift`

**Interfaces:**
- Consumes: `LibraryFileService.shared.destinationURL(for:in:folderStructure:)`, `.resolveConflict(at:)`, and the private `isCrossVolume`/`crossVolumeMove` (via the new internal `moveFile`).
- Produces:
  - `LibraryFileService.moveFile(at source: URL, to destination: URL) throws`
  - `ConvertedPDFArchiver.folderName == "Converted PDFs"` (static let)
  - `ConvertedPDFArchiver.mirrorSubpath(for comic: Comic, libraryRoot: URL) -> String`
  - `ConvertedPDFArchiver.archiveOriginal(_ original: URL, libraryRoot: URL, mirrorSubpath: String) throws -> URL` (@discardableResult)
  - `ConvertedPDFArchiver.relativePath(of url: URL, under root: URL) -> String?`

- [ ] **Step 1: Add `moveFile` to LibraryFileService**

In `SCO-OSXCursor/Services/LibraryFileService.swift`, after `moveToLibrary` (after line 195), add:

```swift
    // MARK: - Plain File Move

    /// Same-volume rename, or copy → verify → delete across volumes.
    /// Assumes the caller resolved conflicts and holds any security scopes.
    /// The source is deleted only after a verified copy (cross-volume) —
    /// same contract as moveToLibrary, without the DB coupling.
    func moveFile(at source: URL, to destination: URL) throws {
        if isCrossVolume(from: source, to: destination) {
            try crossVolumeMove(from: source, to: destination)
        } else {
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }
```

- [ ] **Step 2: Write the failing tests**

Create `SCO-OSXCursorTests/ConvertedPDFArchiverTests.swift`:

```swift
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
            for: makeComic(filePath: filePath), libraryRoot: root)
        #expect(subpath == "DC Comics/Batman")
    }

    @Test func fallsBackToDestinationFolderForBooksOutsideTheRoot() throws {
        let root = try makeRoot()
        let filePath = URL(fileURLWithPath: "/Users/nobody/Downloads/Batman #012 (2024).pdf")
        let subpath = ConvertedPDFArchiver.mirrorSubpath(
            for: makeComic(filePath: filePath), libraryRoot: root)
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
```

Note: `fallsBackToDestinationFolderForBooksOutsideTheRoot` depends on `AppSettings.load().folderStructure` being the default `.publisherSeriesIssue` in the test environment. To make it deterministic, have `mirrorSubpath` accept the structure: add parameter `folderStructure: AppSettings.FolderStructure = AppSettings.load().folderStructure` and pass `.publisherSeriesIssue` explicitly in the test.

- [ ] **Step 3: Run tests, expect compile failure**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/ConvertedPDFArchiverTests -quiet`
Expected: FAIL — `cannot find 'ConvertedPDFArchiver' in scope`.

- [ ] **Step 4: Implement ConvertedPDFArchiver**

Create `SCO-OSXCursor/Services/Conversion/ConvertedPDFArchiver.swift`:

```swift
//
//  ConvertedPDFArchiver.swift
//  SCO-OSXCursor
//
//  Files a converted book's original PDF(s) into
//  "<LibraryRoot>/Converted PDFs/<Publisher>/<Series>/…", mirroring where
//  the converted CBZ lives (or would live) under the root — so a user
//  who wants to delete originals can find each one exactly where its
//  book is filed. Move-only: originals are never deleted, and name
//  conflicts get " (2)" suffixes.
//
//  Callers hold the library root's security scope.
//

import Foundation

enum ConvertedPDFArchiver {

    static let folderName = "Converted PDFs"

    /// Folder path (relative to the library root) the original should
    /// mirror: the comic's own parent folder when it lives under the
    /// root (and isn't already inside Converted PDFs), otherwise the
    /// folder destinationURL would file it into.
    static func mirrorSubpath(
        for comic: Comic,
        libraryRoot: URL,
        folderStructure: AppSettings.FolderStructure = AppSettings.load().folderStructure
    ) -> String {
        let parent = comic.filePath.deletingLastPathComponent()
        if let relative = relativePath(of: parent, under: libraryRoot),
           !relative.hasPrefix(folderName) {
            return relative
        }
        let destinationFolder = LibraryFileService.shared
            .destinationURL(for: comic, in: libraryRoot, folderStructure: folderStructure)
            .deletingLastPathComponent()
        return relativePath(of: destinationFolder, under: libraryRoot) ?? ""
    }

    /// Moves `original` into the mirror folder; returns where it landed.
    @discardableResult
    static func archiveOriginal(
        _ original: URL, libraryRoot: URL, mirrorSubpath: String
    ) throws -> URL {
        let fm = FileManager.default
        var folder = libraryRoot.appendingPathComponent(folderName, isDirectory: true)
        if !mirrorSubpath.isEmpty {
            folder.appendPathComponent(mirrorSubpath, isDirectory: true)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var destination = folder.appendingPathComponent(original.lastPathComponent)
        destination = LibraryFileService.shared.resolveConflict(at: destination)
        try LibraryFileService.shared.moveFile(at: original, to: destination)
        AppLog.files.info(
            "[ConvertedPDFArchiver] ✅ Filed original: \(original.lastPathComponent) → \(folderName)/\(mirrorSubpath)")
        return destination
    }

    /// `url`'s path relative to `root` ("" when equal), nil when outside.
    static func relativePath(of url: URL, under root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath == rootPath { return "" }
        guard urlPath.hasPrefix(rootPath + "/") else { return nil }
        return String(urlPath.dropFirst(rootPath.count + 1))
    }
}
```

- [ ] **Step 5: Run tests, expect pass**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/ConvertedPDFArchiverTests -quiet`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add SCO-OSXCursor/Services/Conversion/ConvertedPDFArchiver.swift SCO-OSXCursor/Services/LibraryFileService.swift SCO-OSXCursorTests/ConvertedPDFArchiverTests.swift
git commit -m "feat(convert): file converted originals under Converted PDFs with mirrored paths

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Post-hoc conversion engine (LibraryViewModel + ActivityEvent)

**Files:**
- Modify: `SCO-OSXCursor/Models/ActivityEvent.swift` (new `.converted` case)
- Create: `SCO-OSXCursor/ViewModels/LibraryViewModel+ConvertPDF.swift`

**Interfaces:**
- Consumes: `PDFToCBZConverter.convert(...)` (Task 2), `ConvertedPDFArchiver` (Task 3), `LibraryViewModel.persistComic(_:)`, `.logActivity(_:comic:old:new:)`, `SettingsViewModel().resolveHomeLibraryURL()`, `Comic.isBundled(_:)`.
- Produces:
  - `ActivityEvent.ActionType.converted` (rawValue `"converted_to_cbz"`)
  - `LibraryViewModel.ConvertedBook { let comic: Comic; let archivedOriginalURL: URL?; let warning: String? }`
  - `LibraryViewModel.convertPDFToCBZ(_ comic: Comic, pageProgress: (@Sendable (Int, Int) -> Void)?) async throws -> ConvertedBook`

- [ ] **Step 1: Add the `.converted` activity kind**

In `SCO-OSXCursor/Models/ActivityEvent.swift`:

After line 21 (`case fileMoveFailed = "file_move_failed"`) add:
```swift
        case converted = "converted_to_cbz"
```
In `displayName` after the `.fileMoveFailed` case add:
```swift
            case .converted: return "Converted to CBZ"
```
In `icon` after `.fileMoveFailed` add:
```swift
            case .converted: return "doc.zipper"
```
In `color`, extend the `.fileMoved` line's neighborhood with:
```swift
            case .converted: return "teal"
```

- [ ] **Step 2: Implement the conversion engine**

Create `SCO-OSXCursor/ViewModels/LibraryViewModel+ConvertPDF.swift`:

```swift
//
//  LibraryViewModel+ConvertPDF.swift
//  SCO-OSXCursor
//
//  Post-hoc PDF → CBZ conversion for books already in the library.
//
//  Per book: write the CBZ beside the PDF (verified, conflict-safe) →
//  update the SAME record in place (id kept; the import path's UUIDs are
//  path-derived, so re-importing would fork identity) → log activity →
//  file the original under "<Library>/Converted PDFs/…". The PDF is
//  never deleted; if the DB update fails the CBZ is removed so the
//  library never points at a file that isn't there.
//

import Foundation

extension LibraryViewModel {

    struct ConvertedBook {
        let comic: Comic
        /// Where the original PDF was filed, when archiving succeeded.
        let archivedOriginalURL: URL?
        /// Non-fatal problem to surface (original couldn't be archived, …).
        let warning: String?
    }

    func convertPDFToCBZ(
        _ comic: Comic,
        pageProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> ConvertedBook {
        guard comic.fileType == .pdf, !Comic.isBundled(comic), !comic.needsAttention else {
            throw PDFConversionError.cannotOpen(comic.fileName)
        }

        // ── Resolve the file (bookmark first) — same as embedComicInfo ──
        var fileURL = comic.filePath
        var didStartAccess = false
        if let bookmarkData = comic.bookmarkData {
            var isStale = false
            #if os(macOS)
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData, options: .withSecurityScope,
                    relativeTo: nil, bookmarkDataIsStale: &isStale)
                {
                    fileURL = resolved
                    didStartAccess = resolved.startAccessingSecurityScopedResource()
                }
            #else
                if let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData, options: [],
                    relativeTo: nil, bookmarkDataIsStale: &isStale)
                {
                    fileURL = resolved
                    didStartAccess = resolved.startAccessingSecurityScopedResource()
                }
            #endif
        }
        defer { if didStartAccess { fileURL.stopAccessingSecurityScopedResource() } }

        // Conversions rewrite files under the home library root — hold
        // its scope for the whole operation (same rule as embedComicInfo).
        let scopedLibraryRoot = beginHomeLibraryScope()
        defer { scopedLibraryRoot?.stopAccessingSecurityScopedResource() }

        let sourceURL = fileURL
        let directory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let metadata = comic
        let progress = pageProgress ?? { _, _ in }

        let result: PDFToCBZConverter.ConversionResult
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try PDFToCBZConverter.convert(
                    sources: [sourceURL], metadata: metadata,
                    destinationDirectory: directory, baseFileName: baseName,
                    onPageProgress: progress)
            }.value
        } catch {
            // A cloud-synced source fails with an opaque sandbox error —
            // translate it, same as LibraryFileService.moveToLibrary.
            if LibraryFileService.isCloudDriveURL(sourceURL) {
                throw LibraryFileError.cloudDriveSource(sourceURL)
            }
            throw error
        }

        // ── Update the record in place (same id) ──
        var updated = comic
        updated.filePath = result.cbzURL
        updated.fileName = result.cbzURL.lastPathComponent
        updated.fileType = .cbz
        updated.totalPages = result.pageCount
        updated.pdfReadsAsBook = false
        updated.dateModified = Date()
        if let size = try? FileManager.default
            .attributesOfItem(atPath: result.cbzURL.path)[.size] as? Int64
        {
            updated.fileSize = size
        }
        #if os(macOS)
            updated.bookmarkData = try? result.cbzURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
            updated.bookmarkData = try? result.cbzURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif

        do {
            try await persistComic(updated)
        } catch {
            // Never leave the record pointing at nothing: drop the CBZ,
            // the record still points at the untouched PDF.
            try? FileManager.default.removeItem(at: result.cbzURL)
            throw error
        }
        if let index = comics.firstIndex(where: { $0.id == updated.id }) {
            comics[index] = updated
        }
        await logActivity(.converted, comic: updated, old: comic.fileName, new: updated.fileName)

        // ── File the original PDF (non-fatal on failure) ──
        var archivedURL: URL?
        var warning: String?
        if let libraryRoot = scopedLibraryRoot ?? SettingsViewModel().resolveHomeLibraryURL() {
            do {
                let subpath = ConvertedPDFArchiver.mirrorSubpath(
                    for: comic, libraryRoot: libraryRoot)
                archivedURL = try ConvertedPDFArchiver.archiveOriginal(
                    sourceURL, libraryRoot: libraryRoot, mirrorSubpath: subpath)
            } catch {
                warning =
                    "\(comic.displayTitle): converted, but the original PDF couldn't be moved to Converted PDFs (\(error.localizedDescription)). It's still next to the new CBZ."
            }
        } else {
            warning =
                "\(comic.displayTitle): converted. No home library is set, so the original PDF stays where it was."
        }

        return ConvertedBook(comic: updated, archivedOriginalURL: archivedURL, warning: warning)
    }
}
```

**Note on naming (spec §7's "cleanedFileName emits .cbz"):** no `cleanedFileName` change is needed. After conversion the record's `fileName` already ends in `.cbz`, and `cleanedFileName(for:)` derives its extension from `comic.fileName` — so every later re-sort/rename naturally produces `.cbz` names. Do not add an override parameter.

**Check while implementing:** `beginHomeLibraryScope()` is declared in LibraryViewModel around line 1294 — confirm its exact name/signature (`func beginHomeLibraryScope() -> URL?`) and its access level allows extension use (same type, any level works). If it starts the scope itself, do NOT double-start; the code above only *stops* what it returns, matching `embedComicInfo`'s usage at line 517-518.

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet`
Expected: exit 0, no warnings about Sendable in the new file. (No new unit test — the method is DB/MainActor orchestration of parts already tested in Tasks 1–3.)

- [ ] **Step 4: Commit**

```bash
git add SCO-OSXCursor/Models/ActivityEvent.swift SCO-OSXCursor/ViewModels/LibraryViewModel+ConvertPDF.swift
git commit -m "feat(convert): post-hoc PDF→CBZ engine — record updated in place, original archived

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Post-hoc conversion UI (sheet + menus)

**Files:**
- Create: `SCO-OSXCursor/ViewModels/ConvertToCBZViewModel.swift`
- Create: `SCO-OSXCursor/Views/Library/ConvertToCBZSheet.swift`
- Modify: `SCO-OSXCursor/Views/Library/ComicCellModifiers.swift` (ComicCellActions + context menu)
- Modify: `SCO-OSXCursor/Views/Library/LibrarySelectionActions.swift`
- Modify: `SCO-OSXCursor/Views/Library/LibrarySelectionBar.swift` (macOS)
- Modify: `SCO-OSXCursor/Views/Library/LibrarySelectionBottomBar.swift` (iOS)
- Modify: `SCO-OSXCursor/Views/Library/LibraryView.swift` (state, sheet, handlers, action wiring)

**Interfaces:**
- Consumes: `LibraryViewModel.convertPDFToCBZ(_:pageProgress:)` (Task 4).
- Produces: `ConvertToCBZViewModel` (`Phase`, `init(selection:)`, `run(library:)`), `ConvertToCBZSheet(selection:library:)`. New action fields: `ComicCellActions.convertToCBZ: (Comic) -> Void`, `LibrarySelectionActions.onConvertToCBZ: () -> Void`.

- [ ] **Step 1: ViewModel**

Create `SCO-OSXCursor/ViewModels/ConvertToCBZViewModel.swift`:

```swift
//
//  ConvertToCBZViewModel.swift
//  SCO-OSXCursor
//
//  Phase machine for the post-hoc "Convert to CBZ" sheet
//  (preview → running → done), in the shape of ReorganizeViewModel.
//  One book failing never halts the batch.
//

import Foundation
import SwiftUI

@MainActor
final class ConvertToCBZViewModel: ObservableObject {

    enum Phase {
        case ready      // preview list shown, awaiting confirmation
        case running    // converting
        case done       // all attempted
    }

    struct ItemError: Identifiable {
        let id = UUID()
        let name: String
        let reason: String
    }

    @Published var phase: Phase = .ready
    @Published var progress: Double = 0
    @Published var statusLine: String = ""
    @Published var completedCount = 0
    @Published var failedCount = 0
    @Published var errors: [ItemError] = []
    @Published var warnings: [String] = []

    /// PDFs only — the caller may hand over a mixed selection.
    let candidates: [Comic]
    /// Books from the selection the sheet won't touch (not PDFs, samples…).
    let skippedCount: Int

    init(selection: [Comic]) {
        let eligible = selection.filter {
            $0.fileType == .pdf && !Comic.isBundled($0) && !$0.needsAttention
        }
        self.candidates = eligible
        self.skippedCount = selection.count - eligible.count
    }

    func run(library: LibraryViewModel) async {
        guard phase == .ready, !candidates.isEmpty else { return }
        phase = .running
        let total = candidates.count

        for (index, comic) in candidates.enumerated() {
            let name = comic.displayTitle
            statusLine = "Converting \(name)…"
            do {
                let outcome = try await library.convertPDFToCBZ(comic) { [weak self] page, pages in
                    Task { @MainActor [weak self] in
                        self?.statusLine = "Converting \(name) — page \(page) of \(pages)"
                    }
                }
                completedCount += 1
                if let warning = outcome.warning { warnings.append(warning) }
            } catch {
                failedCount += 1
                errors.append(ItemError(name: name, reason: error.localizedDescription))
            }
            progress = Double(index + 1) / Double(total)
        }

        statusLine = ""
        phase = .done
    }
}
```

- [ ] **Step 2: Sheet view**

Create `SCO-OSXCursor/Views/Library/ConvertToCBZSheet.swift`:

```swift
//
//  ConvertToCBZSheet.swift
//  SCO-OSXCursor
//
//  Preview → run → done sheet for converting library PDFs to CBZ.
//

import SwiftUI

struct ConvertToCBZSheet: View {
    @StateObject private var viewModel: ConvertToCBZViewModel
    let library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    init(selection: [Comic], library: LibraryViewModel) {
        _viewModel = StateObject(wrappedValue: ConvertToCBZViewModel(selection: selection))
        self.library = library
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Convert to CBZ")
                .font(Typography.h2)
                .foregroundColor(TextColors.primary)

            switch viewModel.phase {
            case .ready: readyView
            case .running: runningView
            case .done: doneView
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 480, minHeight: 360)
    }

    // MARK: - Ready (preview)

    private var readyView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(
                "Each PDF becomes a CBZ next to it — scanned pages keep their original image quality. The book's entry keeps its reading progress, lists, and folders. Afterwards the original PDF is filed under \"Converted PDFs\" in your home library, so you can delete it whenever you like."
            )
            .font(Typography.bodySmall)
            .foregroundColor(TextColors.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if viewModel.skippedCount > 0 {
                Text("\(viewModel.skippedCount) selected item(s) aren't convertible PDFs and will be skipped.")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
            }

            List(viewModel.candidates) { comic in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comic.displayTitle).font(Typography.body)
                        Text(comic.fileName)
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                    }
                    Spacer()
                    if comic.totalPages > 0 {
                        Text("\(comic.totalPages) pages")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                    }
                    Text(ByteCountFormatter.string(
                        fromByteCount: comic.fileSize, countStyle: .file))
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                }
            }
            .frame(minHeight: 140)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Convert \(viewModel.candidates.count) Book\(viewModel.candidates.count == 1 ? "" : "s")") {
                    Task { await viewModel.run(library: library) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.candidates.isEmpty)
            }
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ProgressView(value: viewModel.progress)
            Text(viewModel.statusLine)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
            Text("\(viewModel.completedCount + viewModel.failedCount) of \(viewModel.candidates.count)")
                .font(Typography.caption)
                .foregroundColor(TextColors.tertiary)
            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(
                "\(viewModel.completedCount) converted, \(viewModel.failedCount) failed",
                systemImage: viewModel.failedCount == 0
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(Typography.h3)
            .foregroundColor(viewModel.failedCount == 0 ? .green : .orange)

            if !viewModel.errors.isEmpty || !viewModel.warnings.isEmpty {
                List {
                    ForEach(viewModel.errors) { error in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error.name).font(Typography.body)
                            Text(error.reason)
                                .font(Typography.caption)
                                .foregroundColor(.red)
                        }
                    }
                    ForEach(viewModel.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(Typography.caption)
                            .foregroundColor(.orange)
                    }
                }
                .frame(minHeight: 120)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
```

(Adjust `Typography`/`Spacing`/`TextColors` member names only if the compiler objects — they're the project's design tokens used throughout `SettingsView.swift`.)

- [ ] **Step 3: Context menu (single book)**

In `SCO-OSXCursor/Views/Library/ComicCellModifiers.swift`:

In `struct ComicCellActions` (line 15), after `var embedMetadata: (Comic) -> Void = { _ in }` (line 44) add:

```swift
    /// Convert a PDF book to CBZ (post-hoc, moves the original to Converted PDFs).
    var convertToCBZ: (Comic) -> Void = { _ in }
```

In `menuContent`, directly after the embed-metadata `if comic.fileType == .cbz …` block (ends line 297), add:

```swift
        // Convert a PDF into a CBZ — the record keeps its identity and the
        // original PDF is filed under Converted PDFs in the home library.
        if comic.fileType == .pdf && !Comic.isBundled(comic) && !comic.needsAttention {
            Button(action: { actions.convertToCBZ(comic) }) {
                Label("Convert to CBZ…", systemImage: "doc.zipper")
            }
        }
```

- [ ] **Step 4: Selection bars (batch)**

In `SCO-OSXCursor/Views/Library/LibrarySelectionActions.swift`, after `var onEmbedMetadata: () -> Void = {}` (line 30) add:

```swift
    /// Convert every selected PDF book to CBZ (opens the conversion sheet).
    var onConvertToCBZ: () -> Void = {}
```

In `SCO-OSXCursor/Views/Library/LibrarySelectionBottomBar.swift`, inside `moreMenu` after the `onEmbedMetadata` button (line 114-118), add:

```swift
            Button(action: actions.onConvertToCBZ) {
                Label("Convert to CBZ…", systemImage: "doc.zipper")
            }
            .help("Convert the selected PDF books to CBZ. Non-PDFs are skipped.")
```

In `SCO-OSXCursor/Views/Library/LibrarySelectionBar.swift` (macOS), add an equivalent button right after the embed-metadata button (around line 295) using the same visual chrome as its neighbors (copy the embed button's `Button { … } label: { HStack { Image(systemName:); Text("Convert to CBZ") } }` structure exactly, calling `onConvertToCBZ()`; it needs the same `var onConvertToCBZ: () -> Void = {}` property added to that view's declared inputs — check the top of the file for how `onEmbedMetadata` is declared and mirror it).

- [ ] **Step 5: Wire up in LibraryView**

In `SCO-OSXCursor/Views/Library/LibraryView.swift`:

Add state near `isEmbeddingMetadata` (line 150):

```swift
    @State private var showingConvertSheet = false
    @State private var convertSelection: [Comic] = []
```

Add sheet alongside the other `.sheet` modifiers (search `.sheet(isPresented:` in the body):

```swift
        .sheet(isPresented: $showingConvertSheet) {
            ConvertToCBZSheet(selection: convertSelection, library: viewModel)
        }
```

Add handlers near `embedMetadataSingle` (line 1650):

```swift
    // MARK: - Convert to CBZ

    private func convertToCBZSingle(_ comic: Comic) {
        convertSelection = [comic]
        showingConvertSheet = true
    }

    private func convertToCBZForSelected() {
        guard !selectedComics.isEmpty else { return }
        convertSelection = viewModel.comics.filter { selectedComics.contains($0.id) }
        showingConvertSheet = true
    }
```

Wire the closures: find where `ComicCellActions(` is constructed (grep `embedMetadata:` in LibraryView.swift) and add `convertToCBZ: { convertToCBZSingle($0) }` beside it; find where `LibrarySelectionActions(` is constructed (grep `onEmbedMetadata:`, around line 576) and add `onConvertToCBZ: { convertToCBZForSelected() }`. Pass `onConvertToCBZ` through `LibrarySelectionBar`'s init the same way `onEmbedMetadata` flows.

- [ ] **Step 6: Build + smoke test**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet`
Expected: exit 0. Then run existing suites to catch regressions:
`xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add SCO-OSXCursor/ViewModels/ConvertToCBZViewModel.swift SCO-OSXCursor/Views/Library/ConvertToCBZSheet.swift SCO-OSXCursor/Views/Library/ComicCellModifiers.swift SCO-OSXCursor/Views/Library/LibrarySelectionActions.swift SCO-OSXCursor/Views/Library/LibrarySelectionBar.swift SCO-OSXCursor/Views/Library/LibrarySelectionBottomBar.swift SCO-OSXCursor/Views/Library/LibraryView.swift
git commit -m "feat(ui): Convert to CBZ sheet, context-menu and selection-bar actions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Settings toggle ("Convert PDFs to CBZ When Organizing")

**Files:**
- Modify: `SCO-OSXCursor/Views/Settings/SettingsView.swift` (AppStorage + organization section row)
- Modify: `SCO-OSXCursor/ViewModels/OrganizeViewModel.swift` (static accessor)
- Modify: `docs/superpowers/specs/2026-09-16-pdf-to-cbz-conversion-design.md` (one-line amendment)

**Interfaces:**
- Produces: UserDefaults key `"convertPDFsOnOrganize"` (Bool, default false); `OrganizeViewModel.convertPDFsOnOrganizeEnabled: Bool` (static).

- [ ] **Step 1: SettingsView**

Near line 445 (beside `@AppStorage("autoEmbedComicInfo")`), add:

```swift
    // Read by OrganizeViewModel.convertPDFsOnOrganizeEnabled. Its own
    // UserDefaults key, NOT an AppSettings field (same reasoning as
    // autoEmbedComicInfo — a new Codable field would invalidate saved
    // settings on decode).
    @AppStorage("convertPDFsOnOrganize") private var convertPDFsOnOrganize = false
```

In `organizationSettings` (line 878), after the `autoSortIntoLibrary` toggle block (around line 1104 — find the closing of that HStack/padding group and insert a sibling), add:

```swift
            // PDF → CBZ conversion on organize
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Convert PDFs to CBZ When Organizing")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)

                    Text(
                        "When a PDF is confirmed in Organize, SCO converts it to a CBZ (scanned pages keep their original image quality), imports the CBZ, and files the original PDF under \"Converted PDFs\" in your home library. Quick Add always imports PDFs as-is. If a conversion fails, the PDF imports unchanged."
                    )
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $convertPDFsOnOrganize)
                    .labelsHidden()
            }
            .padding(Spacing.md)
```

(Match the exact wrapper styling — `.padding`/`.background` — of the `autoSortIntoLibrary` row next to it; copy its modifiers verbatim.)

- [ ] **Step 2: OrganizeViewModel accessor**

In `SCO-OSXCursor/ViewModels/OrganizeViewModel.swift`, after the `// MARK: - Computed Properties` section (line 69):

```swift
    /// Settings → Organization toggle: convert PDFs to CBZ on confirm.
    /// Its own UserDefaults key — see SettingsView's declaration.
    static var convertPDFsOnOrganizeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "convertPDFsOnOrganize")
    }
```

- [ ] **Step 3: Amend the spec**

In `docs/superpowers/specs/2026-09-16-pdf-to-cbz-conversion-design.md` §3, replace the sentence beginning "New `AppSettings.convertPDFsOnOrganize: Bool`…" with:

```markdown
- New setting under UserDefaults key `"convertPDFsOnOrganize"` (default **off**), stored the same way as `autoEmbedComicInfo` — its own key, not an `AppSettings` Codable field, which would invalidate previously saved settings on decode (see LibraryViewModel.swift:605). Toggle lives in the Organization section of `SettingsView`.
```

- [ ] **Step 4: Build**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add SCO-OSXCursor/Views/Settings/SettingsView.swift SCO-OSXCursor/ViewModels/OrganizeViewModel.swift docs/superpowers/specs/2026-09-16-pdf-to-cbz-conversion-design.md
git commit -m "feat(settings): Convert PDFs to CBZ When Organizing toggle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Organize auto-convert hook + processing status UI

**Files:**
- Modify: `SCO-OSXCursor/ViewModels/OrganizeViewModel.swift` (`confirmMatch`, helpers, `processingDetail`)
- Modify: `SCO-OSXCursor/Views/Organize/OrganizeView.swift` (processing bar with detail label)

**Interfaces:**
- Consumes: `PDFToCBZConverter.convert`, `ConvertedPDFArchiver`, `OrganizeViewModel.convertPDFsOnOrganizeEnabled` (Task 6), `SettingsViewModel().resolveHomeLibraryURL()`.
- Produces: `OrganizeViewModel.processingDetail: String?` and `lastConversionWarning: String?` (@Published); private helpers `comicForConversion(from: StagedComic) -> Comic`, `convertStagedPDF(sources: [URL], staged: StagedComic, destinationDirectory: URL, baseFileName: String) async -> URL?`, `archiveConvertedOriginals(_ urls: [URL], importedAt: URL, staged: StagedComic)`. **Task 8 reuses all three — keep the signatures exactly as written here (they take a source *array* for that reason).**

- [ ] **Step 1: Add published detail + helpers to OrganizeViewModel**

Below `@Published var processingProgress` (line 48):

```swift
    /// Live line under the progress bar, e.g. "Converting X — page 3 of 32".
    @Published var processingDetail: String?
    /// Shown when a conversion failed and the PDF imported natively.
    @Published var lastConversionWarning: String?
```

Clear `lastConversionWarning = nil` at the top of `confirmAllReady` and `confirmMatch` so a stale warning doesn't outlive the next batch.

Add these private helpers (below `confirmAllReady`):

```swift
    // MARK: - PDF → CBZ on Confirm

    /// A metadata carrier for ComicInfoWriter — the staged fields as a Comic.
    private func comicForConversion(from staged: StagedComic) -> Comic {
        Comic(
            filePath: staged.originalURL,
            fileName: staged.originalURL.lastPathComponent,
            title: staged.title,
            publisher: staged.publisher,
            series: staged.series.isEmpty ? nil : staged.series,
            issueNumber: staged.issueNumber,
            volume: staged.volume,
            year: staged.year,
            bookFormat: staged.bookFormat,
            writer: staged.writer,
            artist: staged.artist,
            coverArtist: staged.coverArtist,
            colorist: staged.colorist,
            inker: staged.inker,
            editor: staged.editor,
            summary: staged.summary,
            fileType: .pdf
        )
    }

    /// Converts staged PDF source(s) into one CBZ in `destinationDirectory`.
    /// Returns the CBZ URL, or nil on failure (caller imports the PDF
    /// natively — conversion failure never blocks an import).
    private func convertStagedPDF(
        sources: [URL],
        staged: StagedComic,
        destinationDirectory: URL,
        baseFileName: String
    ) async -> URL? {
        let metadata = comicForConversion(from: staged)
        let displayName = sources.first?.lastPathComponent ?? staged.originalFileName
        var scoped: [URL] = []
        for url in sources where url.startAccessingSecurityScopedResource() {
            scoped.append(url)
        }
        defer { for url in scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try PDFToCBZConverter.convert(
                    sources: sources, metadata: metadata,
                    destinationDirectory: destinationDirectory,
                    baseFileName: baseFileName
                ) { page, total in
                    Task { @MainActor [weak self] in
                        self?.processingDetail =
                            "Converting \(displayName) — page \(page) of \(total)"
                    }
                }
            }.value
            processingDetail = nil
            return result.cbzURL
        } catch {
            AppLog.organize.error(
                "[OrganizeViewModel] ⚠️ PDF→CBZ failed (importing natively): \(error.localizedDescription)")
            processingDetail = nil
            lastConversionWarning =
                "\(displayName): conversion failed (\(error.localizedDescription)) — imported as PDF."
            return nil
        }
    }

    /// Files converted originals under <root>/Converted PDFs/…, mirroring
    /// the folder the imported CBZ lives in. Best-effort: failures log.
    private func archiveConvertedOriginals(
        _ urls: [URL], importedAt cbzURL: URL, staged: StagedComic
    ) {
        guard let libraryRoot = SettingsViewModel().resolveHomeLibraryURL() else {
            AppLog.organize.info(
                "[OrganizeViewModel] No home library set — converted original(s) left in place")
            return
        }
        let rootAccessing = libraryRoot.startAccessingSecurityScopedResource()
        defer { if rootAccessing { libraryRoot.stopAccessingSecurityScopedResource() } }

        // Mirror where the CBZ actually landed (auto-sort may have moved
        // it). If the record can't be found, fall back to the staged
        // metadata — mirrorSubpath then computes the destination folder
        // the CBZ would be filed into.
        let landed = libraryViewModel.comics.first {
            $0.filePath.standardizedFileURL == cbzURL.standardizedFileURL
                || $0.fileName == cbzURL.lastPathComponent
        }
        let subpathSource = landed ?? comicForConversion(from: staged)
        let subpath = ConvertedPDFArchiver.mirrorSubpath(
            for: subpathSource, libraryRoot: libraryRoot)
        for url in urls {
            do {
                try ConvertedPDFArchiver.archiveOriginal(
                    url, libraryRoot: libraryRoot, mirrorSubpath: subpath)
            } catch {
                AppLog.organize.error(
                    "[OrganizeViewModel] ⚠️ Couldn't file original \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
```

- [ ] **Step 2: Hook into `confirmMatch`**

In `confirmMatch` (line 372), after the rename block (ends line 417) and before step 2 (`importStagedComic`, line 419), insert:

```swift
        // 1.5 Convert PDF → CBZ when the setting is on. The CBZ is written
        //     next to the (renamed) PDF; the import below then targets the
        //     CBZ. On failure the PDF imports natively, exactly as before.
        var convertedOriginals: [URL] = []
        if finalURL.pathExtension.lowercased() == "pdf",
           Self.convertPDFsOnOrganizeEnabled
        {
            let baseName = finalURL.deletingPathExtension().lastPathComponent
            if let cbzURL = await convertStagedPDF(
                sources: [finalURL],
                staged: current,
                destinationDirectory: finalURL.deletingLastPathComponent(),
                baseFileName: baseName)
            {
                convertedOriginals = [finalURL]
                finalURL = cbzURL
            }
        }
```

`finalURL` is currently `let`-bound via `var finalURL = originalURL` (line 378) — already `var`, no change needed.

Then, after the auto-sort block (ends line 474, `lastMoveDestination` set) and before the learning step, insert:

```swift
        // 3.5 File converted originals under Converted PDFs (best-effort).
        if !convertedOriginals.isEmpty {
            archiveConvertedOriginals(convertedOriginals, importedAt: finalURL, staged: current)
        }
```

(After auto-sort the CBZ may have moved, making `finalURL` stale as a path — that's why the helper's lookup also matches on `fileName`.)

- [ ] **Step 3: Processing bar in OrganizeView**

`isProcessing`/`processingProgress` are not currently rendered anywhere. In `SCO-OSXCursor/Views/Organize/OrganizeView.swift`, find the main content `VStack` that hosts the staged-comics list (grep `stagedComics` in the file for the list/table) and insert directly above the list:

```swift
            if viewModel.isProcessing {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ProgressView(value: viewModel.processingProgress)
                    if let detail = viewModel.processingDetail {
                        Text(detail)
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            }

            if let warning = viewModel.lastConversionWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(Typography.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, Spacing.lg)
            }
```

- [ ] **Step 4: Build + manual test**

Run: `xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet` — exit 0.

Manual (launch the app): Settings → toggle ON → Organize → add a PDF → fill metadata → Confirm. Verify: library gets a `.cbz` book, original PDF appears under `<Library>/Converted PDFs/<Publisher>/<Series>/`, progress label showed page counts. Toggle OFF → confirm another PDF → imports natively (unchanged behavior).

- [ ] **Step 5: Commit**

```bash
git add SCO-OSXCursor/ViewModels/OrganizeViewModel.swift SCO-OSXCursor/Views/Organize/OrganizeView.swift
git commit -m "feat(organize): auto-convert confirmed PDFs to CBZ with live page progress

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Merge staged PDFs into one CBZ

**Files:**
- Modify: `SCO-OSXCursor/Models/StagedComic.swift` (merge state + proposedFileName extension override)
- Modify: `SCO-OSXCursor/ViewModels/OrganizeViewModel.swift` (merge action + confirmMatch merge branch)
- Create: `SCO-OSXCursor/Views/Organize/MergePDFsSheet.swift`
- Modify: `SCO-OSXCursor/Views/Organize/OrganizeView.swift` (merge button + sheet)
- Test: `SCO-OSXCursorTests/StagedComicMergeTests.swift`

**Interfaces:**
- Consumes: Task 7's `convertStagedPDF(sources:staged:destinationDirectory:baseFileName:)` and `archiveConvertedOriginals(_:importedAt:staged:)`.
- Produces: `StagedComic.mergeSourceURLs: [URL]?`; `OrganizeViewModel.checkedPDFsForMerge: [StagedComic]`, `OrganizeViewModel.mergeStagedPDFs(ordered: [StagedComic])`.

- [ ] **Step 1: Write the failing test**

Create `SCO-OSXCursorTests/StagedComicMergeTests.swift`:

```swift
//
//  StagedComicMergeTests.swift
//  SCO-OSXCursorTests
//

import Foundation
import Testing

@testable import SCO_OSXCursor

struct StagedComicMergeTests {

    @Test func mergedStagedComicProposesCBZExtension() {
        var staged = StagedComic(url: URL(fileURLWithPath: "/tmp/Saga Book One (2014).pdf"))
        staged.series = "Saga"
        staged.volume = 1
        staged.year = 2014
        staged.bookFormat = .volume
        #expect(staged.proposedFileName.hasSuffix(".pdf"))

        staged.mergeSourceURLs = [
            URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.pdf"),
        ]
        #expect(staged.proposedFileName.hasSuffix(".cbz"))
    }
}
```

- [ ] **Step 2: Run test, expect compile failure**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/StagedComicMergeTests -quiet`
Expected: FAIL — `value of type 'StagedComic' has no member 'mergeSourceURLs'`.

- [ ] **Step 3: StagedComic changes**

In `SCO-OSXCursor/Models/StagedComic.swift`, after `var summary: String?` (line 66):

```swift
    /// When set, this staged item is a pending MERGE: confirming converts
    /// these PDFs (in order) into one CBZ. nil for ordinary items.
    var mergeSourceURLs: [URL]? = nil
```

In `proposedFileName` (line 145), change the extension line (177-179):

```swift
// BEFORE
        // Preserve original extension
        let ext = originalURL.pathExtension
        return parts.joined(separator: " ") + ".\(ext)"
// AFTER
        // Preserve original extension — except a pending merge, whose
        // confirm produces a CBZ.
        let ext = mergeSourceURLs == nil ? originalURL.pathExtension : "cbz"
        return parts.joined(separator: " ") + ".\(ext)"
```

- [ ] **Step 4: Run test, expect pass**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -only-testing:SCO-OSXCursorTests/StagedComicMergeTests -quiet`
Expected: PASS.

- [ ] **Step 5: OrganizeViewModel merge action**

Add to OrganizeViewModel (near the other computed properties):

```swift
    /// Checked staged PDFs eligible for "Merge into One CBZ" (2+, all
    /// plain PDFs, none already a pending merge). Empty when ineligible.
    var checkedPDFsForMerge: [StagedComic] {
        let checked = stagedComics.filter { checkedComicIDs.contains($0.id) }
        guard checked.count >= 2,
            checked.allSatisfy({
                $0.originalURL.pathExtension.lowercased() == "pdf"
                    && $0.mergeSourceURLs == nil
            })
        else { return [] }
        return checked
    }

    /// Collapse `ordered` (2+) into one pending-merge staged item.
    /// Metadata comes from the first item; the rest leave staging.
    func mergeStagedPDFs(ordered: [StagedComic]) {
        guard ordered.count >= 2, var merged = ordered.first else { return }
        merged.mergeSourceURLs = ordered.map(\.originalURL)
        merged.reevaluate(userEdited: false)
        let absorbedIDs = Set(ordered.dropFirst().map(\.id))
        stagedComics.removeAll { absorbedIDs.contains($0.id) }
        if let index = stagedComics.firstIndex(where: { $0.id == merged.id }) {
            stagedComics[index] = merged
        }
        checkedComicIDs.subtract(absorbedIDs)
        checkedComicIDs.remove(merged.id)
        selectedComicID = merged.id
    }
```

- [ ] **Step 6: confirmMatch merge branch**

In `confirmMatch`, two changes.

(a) Skip the rename for pending merges — wrap the existing rename block (lines 383-417):

```swift
        // Pending merges skip the rename: the sources keep their names
        // (they end up in Converted PDFs) and the merged CBZ is created
        // under proposedFileName directly.
        let newFileName = current.proposedFileName
        if current.mergeSourceURLs == nil, newFileName != originalURL.lastPathComponent {
            // … existing rename block unchanged …
        }
```

(b) Replace Task 7's step-1.5 block with a version handling both shapes:

```swift
        // 1.5 Convert to CBZ: always for a pending merge, and for single
        //     PDFs when the setting is on. On failure a single PDF imports
        //     natively; a failed merge keeps the item staged with an error.
        var convertedOriginals: [URL] = []
        if let mergeSources = current.mergeSourceURLs {
            let baseName = (newFileName as NSString).deletingPathExtension
            guard let cbzURL = await convertStagedPDF(
                sources: mergeSources,
                staged: current,
                destinationDirectory: mergeSources[0].deletingLastPathComponent(),
                baseFileName: baseName)
            else {
                // Merge cannot fall back to a native import (there are
                // several files). Mark the staged item and bail out.
                if let index = stagedComics.firstIndex(where: { $0.id == current.id }) {
                    stagedComics[index].status = .error
                }
                return
            }
            convertedOriginals = mergeSources
            finalURL = cbzURL
        } else if finalURL.pathExtension.lowercased() == "pdf",
                  Self.convertPDFsOnOrganizeEnabled
        {
            let baseName = finalURL.deletingPathExtension().lastPathComponent
            if let cbzURL = await convertStagedPDF(
                sources: [finalURL],
                staged: current,
                destinationDirectory: finalURL.deletingLastPathComponent(),
                baseFileName: baseName)
            {
                convertedOriginals = [finalURL]
                finalURL = cbzURL
            }
        }
```

Note: `importStagedComic(originalURL: originalURL, …)` stays as-is — the stable UUID derives from the first source's original path, which is exactly the "same book" identity we want.

- [ ] **Step 7: MergePDFsSheet**

Create `SCO-OSXCursor/Views/Organize/MergePDFsSheet.swift`:

```swift
//
//  MergePDFsSheet.swift
//  SCO-OSXCursor
//
//  Order-and-confirm sheet for merging checked staged PDFs into one CBZ.
//  Metadata comes from the first file (editable afterwards in the
//  inspector, like any staged item).
//

import SwiftUI

struct MergePDFsSheet: View {
    let candidates: [StagedComic]
    let onMerge: ([StagedComic]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var ordered: [StagedComic] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Merge into One CBZ")
                .font(Typography.h2)
                .foregroundColor(TextColors.primary)

            Text(
                "These PDFs become a single CBZ, pages in the order below (drag to reorder). Metadata starts from the first file — edit it in the inspector before confirming. The original PDFs are filed under \"Converted PDFs\" after a successful convert."
            )
            .font(Typography.bodySmall)
            .foregroundColor(TextColors.secondary)
            .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(ordered) { staged in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(TextColors.tertiary)
                        Text(staged.originalFileName)
                            .font(Typography.body)
                        Spacer()
                        Text(ByteCountFormatter.string(
                            fromByteCount: staged.fileSize, countStyle: .file))
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                    }
                }
                .onMove { from, to in
                    ordered.move(fromOffsets: from, toOffset: to)
                }
            }
            .frame(minHeight: 160)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Merge \(ordered.count) PDFs") {
                    onMerge(ordered)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(ordered.count < 2)
            }
        }
        .padding(Spacing.xl)
        .frame(minWidth: 460, minHeight: 340)
        .onAppear { ordered = candidates }
    }
}
```

- [ ] **Step 8: OrganizeView button + sheet**

In `SCO-OSXCursor/Views/Organize/OrganizeView.swift`: add state `@State private var showingMergeSheet = false`; add the sheet modifier next to the view's other sheets:

```swift
        .sheet(isPresented: $showingMergeSheet) {
            MergePDFsSheet(candidates: viewModel.checkedPDFsForMerge) { ordered in
                viewModel.mergeStagedPDFs(ordered: ordered)
            }
        }
```

Add a button where the other bulk actions for checked items live (grep `checkedComicIDs`/`checkedCount` in OrganizeView to find the bulk-action toolbar/row):

```swift
            if viewModel.checkedPDFsForMerge.count >= 2 {
                Button {
                    showingMergeSheet = true
                } label: {
                    Label("Merge into One CBZ", systemImage: "doc.zipper")
                }
            }
```

Also mark pending merges visibly in the staged list row (find the row view — grep `originalFileName` in OrganizeView / its row subview) with a small badge:

```swift
            if comic.mergeSourceURLs != nil {
                Text("MERGE · \(comic.mergeSourceURLs?.count ?? 0) PDFs")
                    .font(Typography.tiny)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(AccentColors.primary.opacity(0.15))
                    .clipShape(Capsule())
            }
```

- [ ] **Step 9: Build + full tests + manual**

Run: `xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet`
Expected: PASS (all suites).

Manual: stage 3 PDFs → check them → Merge into One CBZ → reorder → Merge → item shows MERGE badge and `.cbz` proposed name → Confirm → one CBZ in library with continuous pages; all 3 PDFs under Converted PDFs.

- [ ] **Step 10: Commit**

```bash
git add SCO-OSXCursor/Models/StagedComic.swift SCO-OSXCursor/ViewModels/OrganizeViewModel.swift SCO-OSXCursor/Views/Organize/MergePDFsSheet.swift SCO-OSXCursor/Views/Organize/OrganizeView.swift SCO-OSXCursorTests/StagedComicMergeTests.swift
git commit -m "feat(organize): merge checked staged PDFs into one CBZ

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Final verification + user manual

**Files:**
- Modify: `SCO-OSXCursor/Views/Help/UserManualView.swift` (Organize section blurb)

- [ ] **Step 1: User manual blurb**

In `SCO-OSXCursor/Views/Help/UserManualView.swift`, find the Organize section (around lines 64-71 and 331-340 where Quick Add vs Organize are described) and append one paragraph to the Organize description matching the surrounding copy style:

```
PDFs can be converted to CBZ automatically when confirmed (Settings → Organization), or merged — check two or more staged PDFs and choose Merge into One CBZ. Originals are kept under "Converted PDFs" in your home library. You can also convert any PDF already in your library from its right-click menu.
```

- [ ] **Step 2: Full test suite + build**

```bash
xcodebuild test -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet
```
Expected: PASS, zero failures across all suites (new + pre-existing).

```bash
xcodebuild build -scheme SCO-OSXCursor -destination 'platform=macOS' -quiet
```
Expected: exit 0.

- [ ] **Step 3: Manual end-to-end sweep**

1. Post-hoc single: right-click a library PDF → Convert to CBZ… → sheet preview → Convert → book flips to CBZ (same reading state), PDF filed under Converted PDFs mirroring its folder.
2. Post-hoc batch: select PDFs + a CBZ → selection bar → Convert to CBZ… → CBZ counted as skipped, PDFs convert, errors (if any) listed without halting.
3. Organize toggle ON single-PDF confirm (Task 7 checklist).
4. Merge (Task 8 checklist).
5. Quick Add a PDF → still imports natively as PDF.

- [ ] **Step 4: Commit**

```bash
git add SCO-OSXCursor/Views/Help/UserManualView.swift
git commit -m "docs(help): PDF to CBZ conversion in the user manual

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
