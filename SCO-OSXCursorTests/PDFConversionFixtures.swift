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
    /// pixel size (72 dpi) so the aspect ratios agree exactly, unless a
    /// different `mediaBox` is supplied (used to test aspect-mismatch).
    static func jpegOnlyPDF(jpeg: Data, width: Int, height: Int,
                            mediaBox: (width: Int, height: Int)? = nil) -> Data {
        let boxW = mediaBox?.width ?? width
        let boxH = mediaBox?.height ?? height

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
        append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(boxW) \(boxH)] ")
        append("/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>\nendobj\n")
        beginObject(4)
        append("<< /Type /XObject /Subtype /Image /Width \(width) /Height \(height) ")
        append("/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode ")
        append("/Length \(jpeg.count) >>\nstream\n")
        pdf.append(jpeg)
        append("\nendstream\nendobj\n")
        let contents = "q \(boxW) 0 0 \(boxH) 0 0 cm /Im0 Do Q"
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
