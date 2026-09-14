//
//  ComicInfoWriter.swift
//  SCO-OSXCursor
//
//  Serializes a library book's metadata into ComicInfo.xml so it can be
//  embedded back into the book's CBZ file ("Save Metadata to File").
//
//  Merge policy — the file mirrors the library for fields the library owns,
//  and keeps everything else exactly as another tagger wrote it:
//
//  • SYNCED fields (Title, Series, Number, Volume, Year, Publisher, Writer,
//    Penciller, Inker, Colorist, CoverArtist, Editor, Summary) are written
//    from the library record. A field the library holds empty is REMOVED from
//    the file — the user cleared it (or never had it), and the whole point of
//    embedding is that the file states what the library states.
//
//  • ADDITIVE fields (PageCount, Tags, StoryArc, Characters, Teams,
//    AgeRating) are written only when the library actually has a value.
//    They're often filled by other tools but not tracked 1:1 by the library
//    (e.g. Characters only arrive via a Metron fetch), so an empty library
//    value means "never captured", not "cleared" — the file's value survives.
//
//  • Everything else (Genre, Web, LanguageISO, Notes, Month, Day, Manga,
//    BlackAndWhite, ScanInformation, the <Pages> block with page hashes,
//    and any element we don't know at all) is preserved verbatim from the
//    existing ComicInfo.xml.
//

import Foundation

enum ComicInfoWriter {

    // MARK: - Public API

    /// Builds the ComicInfo.xml document for a comic, merging over the
    /// archive's existing ComicInfo.xml (pass nil when the file has none).
    static func xmlData(for comic: Comic, mergingExisting existingXML: Data? = nil) -> Data {
        let existingRoot = existingXML.flatMap { RawXMLNode.parse($0) }

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
        lines.append("<ComicInfo\(rootAttributes(from: existingRoot))>")

        let synced = syncedValues(for: comic)
        let additive = additiveValues(for: comic)
        var emittedNames = Set<String>()

        for name in canonicalElementOrder {
            emittedNames.insert(name)

            if let libraryValue = synced[name] {
                // Library-owned: write the value, or drop the element when
                // the library holds it empty.
                if let value = libraryValue {
                    lines.append(elementLine(name, value))
                }
                continue
            }

            if let value = additive[name] {
                lines.append(elementLine(name, value))
                continue
            }

            // Preserved: copy the existing element(s) through unchanged.
            for node in existingRoot?.children(named: name) ?? [] {
                lines.append(contentsOf: node.serialized(indent: 1))
            }
        }

        // Elements we don't know about at all (GTIN, Review, custom tags…)
        // ride along in their original order.
        for node in existingRoot?.childElements ?? [] where !emittedNames.contains(node.name) {
            lines.append(contentsOf: node.serialized(indent: 1))
        }

        lines.append("</ComicInfo>")
        return Data(lines.joined(separator: "\n").utf8)
    }

    // MARK: - Field Mapping

    /// ComicInfo schema order for every element this writer understands.
    /// Readers are order-insensitive, but a stable order keeps diffs and
    /// repeat embeds deterministic.
    private static let canonicalElementOrder: [String] = [
        "Title", "Series", "Number", "Count", "Volume", "AlternateSeries",
        "AlternateNumber", "AlternateCount", "Summary", "Notes",
        "Year", "Month", "Day",
        "Writer", "Penciller", "Inker", "Colorist", "Letterer",
        "CoverArtist", "Editor",
        "Publisher", "Imprint", "Genre", "Tags", "Web",
        "PageCount", "LanguageISO", "Format",
        "BlackAndWhite", "Manga",
        "Characters", "Teams", "Locations",
        "ScanInformation", "StoryArc", "SeriesGroup", "AgeRating",
        "CommunityRating", "MainCharacterOrTeam", "Review",
        "Pages",
    ]

    /// Library-owned fields: element name → value (nil = remove from file).
    private static func syncedValues(for comic: Comic) -> [String: String?] {
        [
            "Title": trimmed(comic.title),
            "Series": trimmed(comic.series),
            "Number": trimmed(comic.issueNumber),
            "Volume": comic.volume.map(String.init),
            "Year": comic.year.map(String.init),
            "Writer": trimmed(comic.writer),
            "Penciller": trimmed(comic.artist),
            "Inker": trimmed(comic.inker),
            "Colorist": trimmed(comic.colorist),
            "CoverArtist": trimmed(comic.coverArtist),
            "Editor": trimmed(comic.editor),
            "Publisher": trimmed(comic.publisher),
            "Summary": trimmed(comic.summary),
        ]
    }

    /// Written only when the library has a value; otherwise the existing
    /// element is preserved.
    private static func additiveValues(for comic: Comic) -> [String: String] {
        var values: [String: String] = [:]
        if comic.totalPages > 0 {
            values["PageCount"] = String(comic.totalPages)
        }
        if !comic.tags.isEmpty {
            values["Tags"] = comic.tags.joined(separator: ", ")
        }
        if !comic.storyArcs.isEmpty {
            values["StoryArc"] = comic.storyArcs.joined(separator: ", ")
        }
        if !comic.characters.isEmpty {
            values["Characters"] = comic.characters.joined(separator: ", ")
        }
        if !comic.teams.isEmpty {
            values["Teams"] = comic.teams.joined(separator: ", ")
        }
        // .allAges is the library default for books nobody ever rated, so
        // only a deliberate rating overwrites what the file says.
        if comic.contentRating != .allAges {
            values["AgeRating"] = ageRatingString(comic.contentRating)
        }
        return values
    }

    /// Library rating → ComicInfo v2 AgeRating enumeration value.
    private static func ageRatingString(_ rating: Comic.ContentRating) -> String {
        switch rating {
        case .allAges: return "Everyone"
        case .teen: return "Teen"
        case .matureTeen: return "MA15+"
        case .mature: return "Mature 17+"
        case .explicit: return "Adults Only 18+"
        }
    }

    // MARK: - Serialization Helpers

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }

    private static func rootAttributes(from existingRoot: RawXMLNode?) -> String {
        if let existing = existingRoot, !existing.attributes.isEmpty {
            return existing.serializedAttributes
        }
        // Sorted like serializedAttributes so a re-embed of our own output
        // is byte-identical (and detected as "unchanged").
        return " xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\""
            + " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""
    }

    private static func elementLine(_ name: String, _ value: String) -> String {
        "  <\(name)>\(RawXMLNode.escapeText(value))</\(name)>"
    }
}

// MARK: - Raw XML Tree

/// Minimal ordered XML tree used to carry existing ComicInfo.xml content
/// through an embed untouched — including nested blocks like <Pages> and
/// elements this app knows nothing about. Not a general XML library:
/// comments and processing instructions are dropped, and mixed
/// text-and-children content keeps only the children (neither occurs in
/// ComicInfo files written by real taggers).
final class RawXMLNode {
    let name: String
    let attributes: [String: String]
    var text: String = ""
    var childElements: [RawXMLNode] = []

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    /// Parses `data` and returns the document's root element, or nil for
    /// malformed XML (an embed then just writes a fresh document).
    static func parse(_ data: Data) -> RawXMLNode? {
        let builder = RawXMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root
    }

    func children(named name: String) -> [RawXMLNode] {
        childElements.filter { $0.name == name }
    }

    /// Attribute string with a leading space, sorted for determinism.
    var serializedAttributes: String {
        attributes.sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\(RawXMLNode.escapeAttribute($0.value))\"" }
            .joined()
    }

    /// The node (and its subtree) as indented XML lines.
    func serialized(indent: Int) -> [String] {
        let pad = String(repeating: "  ", count: indent)
        if childElements.isEmpty {
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                return ["\(pad)<\(name)\(serializedAttributes) />"]
            }
            return ["\(pad)<\(name)\(serializedAttributes)>\(RawXMLNode.escapeText(trimmedText))</\(name)>"]
        }
        var lines = ["\(pad)<\(name)\(serializedAttributes)>"]
        for child in childElements {
            lines.append(contentsOf: child.serialized(indent: indent + 1))
        }
        lines.append("\(pad)</\(name)>")
        return lines
    }

    static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ value: String) -> String {
        escapeText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// XMLParser delegate that assembles the RawXMLNode tree.
private final class RawXMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: RawXMLNode?
    private var stack: [RawXMLNode] = []

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        let node = RawXMLNode(name: elementName, attributes: attributeDict)
        if let parent = stack.last {
            parent.childElements.append(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            stack.last?.text += string
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        stack.removeLast()
    }
}
