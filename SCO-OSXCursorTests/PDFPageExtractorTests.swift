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
        let pdf = PDFConversionFixtures.jpegOnlyPDF(
            jpeg: jpeg, width: 400, height: 600, mediaBox: (600, 600))
        #expect(PDFPageExtractor.losslessJPEGData(for: try page(from: pdf)) == nil)
    }
}
