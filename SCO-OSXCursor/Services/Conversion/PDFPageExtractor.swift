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
