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

        // ── The destination must exist before we can ask for an
        //    .itemReplacementDirectory "appropriate for" it — Foundation
        //    throws NSCocoaErrorDomain Code=4 otherwise. ──
        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

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
        var destination = destinationDirectory.appendingPathComponent("\(baseFileName).cbz")
        destination = LibraryFileService.shared.resolveConflict(at: destination)
        try fm.moveItem(at: tempURL, to: destination)

        AppLog.files.info(
            "[PDFToCBZConverter] ✅ \(sources.count) PDF(s) → \(destination.lastPathComponent) (\(totalPages) pages)")
        return ConversionResult(cbzURL: destination, pageCount: totalPages)
    }
}
