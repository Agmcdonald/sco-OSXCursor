//
//  EPUBReader.swift
//  SCO-OSXCursor
//
//  Parses .epub files (which are renamed ZIPs) to extract chapter HTML content,
//  cover images, and metadata from the OPF package document.
//

import Foundation
import SwiftUI
import ZIPFoundation

// MARK: - EPUB Chapter

/// Represents a single chapter/section in an EPUB, ready for display.
struct EPUBChapter: Identifiable {
    let id = UUID()
    let index: Int
    let title: String
    /// Absolute path to the chapter HTML file inside the extracted temp directory.
    let fileURL: URL
    /// Base URL for the folder containing the chapter (so WKWebView can resolve relative assets).
    let baseURL: URL

    /// Reads and returns the HTML content of this chapter.
    func htmlContent() throws -> String {
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}

// MARK: - EPUB Reader

/// Implements `ComicReaderProtocol` for .epub files.
/// EPUBs are ZIP archives containing HTML chapters, CSS, images, and an OPF package manifest.
final class EPUBReader: ComicReaderProtocol {

    // MARK: - ComicReaderProtocol

    func loadComic(from url: URL) async throws -> ComicBook {
        let tempDir = try extractEPUB(at: url)
        let chapters = try parseChapters(from: tempDir)

        guard !chapters.isEmpty else {
            throw ComicReaderError.noImages  // Re-use existing error: "no content found"
        }

        // Encode each chapter as UTF-8 data so it fits into ComicPage.imageData.
        // EPUBReaderView detects fileType == .epub and decodes back to String.
        var pages: [ComicPage] = []
        for chapter in chapters {
            let html = (try? chapter.htmlContent()) ?? "<html><body><p>Chapter \(chapter.index + 1)</p></body></html>"
            let data = html.data(using: .utf8) ?? Data()
            pages.append(ComicPage(pageNumber: chapter.index, imageData: data, fileName: chapter.fileURL.lastPathComponent))
        }

        let metadata = try? parseOPFMetadata(from: tempDir)
        return ComicBook(sourceURL: url, pages: pages, metadata: metadata)
    }

    func extractCover(from url: URL) async throws -> Data {
        let tempDir = try extractEPUB(at: url)
        return (try? findCoverImage(in: tempDir)) ?? Data()
    }

    func getPageCount(from url: URL) async throws -> Int {
        let tempDir = try extractEPUB(at: url)
        let chapters = try parseChapters(from: tempDir)
        return max(chapters.count, 1)
    }

    func loadPage(at index: Int, from url: URL) async throws -> ComicPage {
        let tempDir = try extractEPUB(at: url)
        let chapters = try parseChapters(from: tempDir)
        guard index < chapters.count else { throw ComicReaderError.fileNotFound }
        let chapter = chapters[index]
        let html = (try? chapter.htmlContent()) ?? ""
        let data = html.data(using: .utf8) ?? Data()
        return ComicPage(pageNumber: index, imageData: data, fileName: chapter.fileURL.lastPathComponent)
    }

    // MARK: - Extraction

    /// Extracts the EPUB ZIP into a unique temp subdirectory, returns the root URL.
    private func extractEPUB(at url: URL) throws -> URL {
        // Use a deterministic subfolder based on filename so repeated calls reuse the same extraction.
        let fm = FileManager.default
        let tmpBase = fm.temporaryDirectory
            .appendingPathComponent("SCO_EPUB")
            .appendingPathComponent(url.lastPathComponent.replacingOccurrences(of: ".epub", with: ""))

        if fm.fileExists(atPath: tmpBase.path) {
            // Already extracted — re-use
            return tmpBase
        }

        try fm.createDirectory(at: tmpBase, withIntermediateDirectories: true)
        try fm.unzipItem(at: url, to: tmpBase)
        print("[EPUBReader] ✅ Extracted EPUB to: \(tmpBase.path)")
        return tmpBase
    }

    // MARK: - OPF Location

    /// Reads META-INF/container.xml to find the path of the OPF package document.
    private func opfURL(in epubDir: URL) throws -> URL {
        let containerURL = epubDir.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw ComicReaderError.invalidFormat
        }
        let data = try Data(contentsOf: containerURL)
        let parser = ContainerXMLParser(data: data)
        guard let opfPath = parser.parse() else {
            throw ComicReaderError.metadataParsingFailed
        }
        return epubDir.appendingPathComponent(opfPath)
    }

    // MARK: - Chapter Parsing

    /// Parses the OPF spine to return ordered chapters.
    private func parseChapters(from epubDir: URL) throws -> [EPUBChapter] {
        let opf = try opfURL(in: epubDir)
        let opfDir = opf.deletingLastPathComponent()
        let data = try Data(contentsOf: opf)

        let parser = OPFParser(data: data, opfDirectory: opfDir)
        return parser.parseChapters()
    }

    // MARK: - Metadata

    private func parseOPFMetadata(from epubDir: URL) throws -> ComicMetadata {
        let opf = try opfURL(in: epubDir)
        let data = try Data(contentsOf: opf)
        let parser = OPFParser(data: data, opfDirectory: opf.deletingLastPathComponent())
        return parser.parseMetadata()
    }

    // MARK: - Cover Image

    private func findCoverImage(in epubDir: URL) throws -> Data {
        let opf = try opfURL(in: epubDir)
        let opfDir = opf.deletingLastPathComponent()
        let data = try Data(contentsOf: opf)

        let parser = OPFParser(data: data, opfDirectory: opfDir)
        if let coverURL = parser.parseCoverImageURL() {
            return try Data(contentsOf: coverURL)
        }

        // Fallback: search for common cover filenames
        let fm = FileManager.default
        let coverNames = ["cover.jpg", "cover.png", "cover.jpeg", "Cover.jpg", "Cover.png"]
        if let found = fm.enumerator(at: epubDir, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { coverNames.contains($0.lastPathComponent) })
        {
            return try Data(contentsOf: found)
        }

        throw ComicReaderError.noImages
    }

    // MARK: - Public Chapter Loader (for EPUBReaderView)

    /// Loads all chapters for a given epub URL. Used directly by EPUBReaderView.
    func loadChapters(from url: URL) throws -> [EPUBChapter] {
        let tempDir = try extractEPUB(at: url)
        return try parseChapters(from: tempDir)
    }
}

// MARK: - Container XML Parser

/// Minimal XML parser that extracts the OPF path from META-INF/container.xml.
private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var opfPath: String?

    init(data: Data) {
        self.data = data
    }

    func parse() -> String? {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        return opfPath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "rootfile", let path = attributeDict["full-path"] {
            opfPath = path
        }
    }
}

// MARK: - OPF Parser

/// Parses the OPF package document to extract spine order, metadata, and cover reference.
private final class OPFParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let opfDirectory: URL

    // Manifest: id → href
    private var manifest: [String: String] = [:]
    // manifest id → media-type
    private var manifestMediaType: [String: String] = [:]
    // Spine item refs in order
    private var spineRefs: [String] = []
    // Navigation / TOC data: id → title
    private var navTitles: [String: String] = [:]
    // Cover image id from metadata
    private var coverImageID: String?
    // Dublin Core metadata
    private var dcTitle: String?
    private var dcCreator: String?
    private var dcPublisher: String?
    private var dcDate: String?
    private var dcDescription: String?
    private var dcLanguage: String?

    private var currentElement: String = ""
    private var currentText: String = ""

    init(data: Data, opfDirectory: URL) {
        self.data = data
        self.opfDirectory = opfDirectory
    }

    func parseChapters() -> [EPUBChapter] {
        runParser()
        var chapters: [EPUBChapter] = []
        for (index, idref) in spineRefs.enumerated() {
            guard let href = manifest[idref] else { continue }
            // Decode URL-encoded paths (e.g. "chapter%201.html" -> "chapter 1.html")
            let decodedHref = href.removingPercentEncoding ?? href
            let fileURL = opfDirectory.appendingPathComponent(decodedHref)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let baseURL = fileURL.deletingLastPathComponent()
            let title = navTitles[idref] ?? "Chapter \(index + 1)"
            chapters.append(EPUBChapter(index: index, title: title, fileURL: fileURL, baseURL: baseURL))
        }
        return chapters
    }

    func parseMetadata() -> ComicMetadata {
        runParser()
        var yearInt: Int? = nil
        if let dateStr = dcDate {
            let components = dateStr.split(separator: "-")
            if let yearStr = components.first {
                yearInt = Int(yearStr)
            }
        }
        var meta = ComicMetadata()
        meta.title = dcTitle
        meta.writer = dcCreator
        meta.publisher = dcPublisher
        meta.year = yearInt
        meta.summary = dcDescription
        meta.languageISO = dcLanguage
        return meta
    }

    func parseCoverImageURL() -> URL? {
        runParser()
        // Look for an item marked as cover in metadata
        if let covID = coverImageID, let href = manifest[covID] {
            let url = opfDirectory.appendingPathComponent(href)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // Fallback: first manifest item with image media type
        for (id, href) in manifest {
            if let mt = manifestMediaType[id], mt.hasPrefix("image/") {
                let url = opfDirectory.appendingPathComponent(href)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    // MARK: - Internal

    private var didParse = false
    private func runParser() {
        guard !didParse else { return }
        didParse = true
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "item":
            // Manifest item
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href
                manifestMediaType[id] = attributeDict["media-type"]
            }

        case "itemref":
            // Spine reference
            if let idref = attributeDict["idref"],
               attributeDict["linear"] != "no"
            {
                spineRefs.append(idref)
            }

        case "meta":
            // Cover image reference (EPUB 2 style)
            if attributeDict["name"] == "cover", let content = attributeDict["content"] {
                coverImageID = content
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "dc:title":  dcTitle = text
        case "dc:creator": dcCreator = text
        case "dc:publisher": dcPublisher = text
        case "dc:date": dcDate = text
        case "dc:description": dcDescription = text
        case "dc:language": dcLanguage = text
        default: break
        }
        currentText = ""
    }
}
