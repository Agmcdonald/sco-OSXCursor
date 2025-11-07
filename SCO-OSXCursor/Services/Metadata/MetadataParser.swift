//
//  MetadataParser.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/7/25.
//

import Foundation

// MARK: - Metadata Parser
class MetadataParser {
    
    // MARK: - Parse ComicInfo.xml
    
    /// Parse ComicInfo.xml data into ComicMetadata
    static func parseComicInfo(from data: Data) -> ComicMetadata? {
        do {
            let decoder = XMLDecoder()
            
            // Configure decoder for ComicInfo.xml structure
            decoder.shouldProcessNamespaces = false
            decoder.dateDecodingStrategy = .formatted({
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter
            })
            
            let metadata = try decoder.decode(ComicInfo.self, from: data)
            return metadata.toComicMetadata()
            
        } catch {
            print("[MetadataParser] ❌ Failed to parse ComicInfo.xml: \(error)")
            return nil
        }
    }
    
    // MARK: - Parse from Filename
    
    /// Extract metadata from filename using common patterns
    /// Examples:
    /// - "Batman #001 (2024).cbz" -> series: Batman, issueNumber: 001, year: 2024
    /// - "Amazing Spider-Man 001 (Marvel).cbz" -> series: Amazing Spider-Man, issueNumber: 001, publisher: Marvel
    static func parseFromFilename(_ filename: String) -> ComicMetadata {
        var metadata = ComicMetadata()
        
        // Remove file extension
        let nameWithoutExt = filename.replacingOccurrences(of: "\\.cbz$|\\.cbr$|\\.pdf$", with: "", options: .regularExpression)
        
        // Pattern 1: "Series #Issue (Year)" or "Series Issue (Year)"
        if let match = nameWithoutExt.range(of: #"^(.+?)\s+#?(\d+[A-Za-z]?)\s+\((\d{4})\)"#, options: .regularExpression) {
            let components = nameWithoutExt[match].components(separatedBy: .whitespaces)
            if components.count >= 3 {
                // Extract series (everything before the issue number)
                if let hashIndex = nameWithoutExt.firstIndex(of: "#") {
                    metadata.series = String(nameWithoutExt[..<hashIndex]).trimmingCharacters(in: .whitespaces)
                } else {
                    // Find where numbers start
                    let words = components.filter { !$0.starts(with: "(") && !$0.allSatisfy({ $0.isNumber }) }
                    metadata.series = words.joined(separator: " ")
                }
                
                // Extract issue number
                if let numberMatch = nameWithoutExt.range(of: #"\d+[A-Za-z]?"#, options: .regularExpression) {
                    metadata.number = String(nameWithoutExt[numberMatch])
                }
                
                // Extract year
                if let yearMatch = nameWithoutExt.range(of: #"\((\d{4})\)"#, options: .regularExpression) {
                    let yearStr = String(nameWithoutExt[yearMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                    metadata.year = Int(yearStr)
                }
            }
        }
        
        // Pattern 2: Extract publisher from parentheses
        if let publisherMatch = nameWithoutExt.range(of: #"\(([^)]+)\)(?!.*\()"#, options: .regularExpression) {
            let publisherStr = String(nameWithoutExt[publisherMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            // Check if it's not a year
            if Int(publisherStr) == nil && publisherStr.count > 2 {
                metadata.publisher = publisherStr
            }
        }
        
        // If no series extracted, use the full filename
        if metadata.series == nil {
            metadata.series = nameWithoutExt
        }
        
        return metadata
    }
    
    // MARK: - Merge Metadata
    
    /// Merge metadata from multiple sources, prioritizing in order: comicInfo, pdf, filename
    static func merge(comicInfo: ComicMetadata?, pdf: ComicMetadata?, filename: ComicMetadata?) -> ComicMetadata {
        var result = ComicMetadata()
        
        // Helper function to pick first non-nil value
        func pick<T>(_ values: T?...) -> T? {
            values.first(where: { $0 != nil }) ?? nil
        }
        
        result.title = pick(comicInfo?.title, pdf?.title, filename?.title)
        result.series = pick(comicInfo?.series, pdf?.series, filename?.series)
        result.number = pick(comicInfo?.number, pdf?.number, filename?.number)
        result.volume = pick(comicInfo?.volume, pdf?.volume, filename?.volume)
        result.summary = pick(comicInfo?.summary, pdf?.summary, filename?.summary)
        result.publisher = pick(comicInfo?.publisher, pdf?.publisher, filename?.publisher)
        result.writer = pick(comicInfo?.writer, pdf?.writer, filename?.writer)
        result.penciller = pick(comicInfo?.penciller, pdf?.penciller, filename?.penciller)
        result.coverArtist = pick(comicInfo?.coverArtist, pdf?.coverArtist, filename?.coverArtist)
        result.year = pick(comicInfo?.year, pdf?.year, filename?.year)
        result.month = pick(comicInfo?.month, pdf?.month, filename?.month)
        result.pageCount = pick(comicInfo?.pageCount, pdf?.pageCount, filename?.pageCount)
        
        return result
    }
}

// MARK: - XML Decoder Helper

/// Custom decoder for XML parsing
/// Using a simple XMLParser-based approach since ComicInfo.xml structure is straightforward
class XMLDecoder {
    var shouldProcessNamespaces = false
    var dateDecodingStrategy: DateDecodingStrategy = .formatted({
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    })
    
    enum DateDecodingStrategy {
        case formatted(() -> DateFormatter)
    }
    
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let parser = ComicInfoXMLParser()
        return try parser.parse(data: data)
    }
}

// MARK: - ComicInfo XML Structure
struct ComicInfo: Codable {
    var title: String?
    var series: String?
    var number: String?
    var volume: Int?
    var summary: String?
    var notes: String?
    var publisher: String?
    var imprint: String?
    var genre: String?
    var web: String?
    var languageISO: String?
    var format: String?
    var ageRating: String?
    var year: Int?
    var month: Int?
    var day: Int?
    var writer: String?
    var penciller: String?
    var inker: String?
    var colorist: String?
    var letterer: String?
    var coverArtist: String?
    var editor: String?
    var pageCount: Int?
    var characters: String?
    var teams: String?
    var locations: String?
    var storyArc: String?
    var seriesGroup: String?
    var blackAndWhite: String?
    var manga: String?
    var scanInformation: String?
    
    func toComicMetadata() -> ComicMetadata {
        return ComicMetadata(
            title: title,
            series: series,
            number: number,
            volume: volume,
            summary: summary,
            notes: notes,
            publisher: publisher,
            imprint: imprint,
            genre: genre,
            web: web,
            languageISO: languageISO,
            format: format,
            ageRating: ageRating,
            year: year,
            month: month,
            day: day,
            writer: writer,
            penciller: penciller,
            inker: inker,
            colorist: colorist,
            letterer: letterer,
            coverArtist: coverArtist,
            editor: editor,
            pageCount: pageCount,
            characters: characters,
            teams: teams,
            locations: locations,
            storyArc: storyArc,
            seriesGroup: seriesGroup,
            blackAndWhite: blackAndWhite == "Yes" || blackAndWhite == "true",
            manga: manga,
            scanInformation: scanInformation
        )
    }
}

// MARK: - XML Parser Implementation
class ComicInfoXMLParser: NSObject, XMLParserDelegate {
    private var currentElement: String = ""
    private var currentValue: String = ""
    private var metadata: ComicInfo = ComicInfo()
    
    func parse<T: Decodable>(data: Data) throws -> T {
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        guard parser.parse() else {
            throw NSError(domain: "XMLParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse XML"])
        }
        
        return metadata as! T
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentValue = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard !currentValue.isEmpty else { return }
        
        switch elementName {
        case "Title": metadata.title = currentValue
        case "Series": metadata.series = currentValue
        case "Number": metadata.number = currentValue
        case "Volume": metadata.volume = Int(currentValue)
        case "Summary": metadata.summary = currentValue
        case "Notes": metadata.notes = currentValue
        case "Publisher": metadata.publisher = currentValue
        case "Imprint": metadata.imprint = currentValue
        case "Genre": metadata.genre = currentValue
        case "Web": metadata.web = currentValue
        case "LanguageISO": metadata.languageISO = currentValue
        case "Format": metadata.format = currentValue
        case "AgeRating": metadata.ageRating = currentValue
        case "Year": metadata.year = Int(currentValue)
        case "Month": metadata.month = Int(currentValue)
        case "Day": metadata.day = Int(currentValue)
        case "Writer": metadata.writer = currentValue
        case "Penciller": metadata.penciller = currentValue
        case "Inker": metadata.inker = currentValue
        case "Colorist": metadata.colorist = currentValue
        case "Letterer": metadata.letterer = currentValue
        case "CoverArtist": metadata.coverArtist = currentValue
        case "Editor": metadata.editor = currentValue
        case "PageCount": metadata.pageCount = Int(currentValue)
        case "Characters": metadata.characters = currentValue
        case "Teams": metadata.teams = currentValue
        case "Locations": metadata.locations = currentValue
        case "StoryArc": metadata.storyArc = currentValue
        case "SeriesGroup": metadata.seriesGroup = currentValue
        case "BlackAndWhite": metadata.blackAndWhite = currentValue
        case "Manga": metadata.manga = currentValue
        case "ScanInformation": metadata.scanInformation = currentValue
        default: break
        }
        
        currentValue = ""
    }
}

