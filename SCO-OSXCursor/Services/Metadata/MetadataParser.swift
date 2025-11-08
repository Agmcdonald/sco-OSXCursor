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
    /// - "Blade - Red Band 002 (2024) (Paper) (Glix).cbz" -> series: Blade - Red Band, number: 002, year: 2024, format: Paper, publisher: Glix
    /// - "Laura Kinney - Sabretooth 002 (2025) (Digital) (Kileko-Empire).cbz" -> full extraction
    static func parseFromFilename(_ filename: String) -> ComicMetadata {
        var metadata = ComicMetadata()
        
        // Remove file extension
        let nameWithoutExt = filename.replacingOccurrences(of: "\\.cbz$|\\.cbr$|\\.pdf$", with: "", options: .regularExpression)
        
        print("[MetadataParser] 📝 Parsing filename: \(nameWithoutExt)")
        
        // Extract all parenthetical content: (2024), (Paper), (Glix), etc.
        var parentheticals: [String] = []
        let parenPattern = #"\(([^)]+)\)"#
        let parenRegex = try? NSRegularExpression(pattern: parenPattern)
        let parenMatches = parenRegex?.matches(in: nameWithoutExt, range: NSRange(nameWithoutExt.startIndex..., in: nameWithoutExt))
        
        for match in parenMatches ?? [] {
            if let range = Range(match.range(at: 1), in: nameWithoutExt) {
                let content = String(nameWithoutExt[range])
                parentheticals.append(content)
            }
        }
        
        print("[MetadataParser]    Parentheticals found: \(parentheticals)")
        
        // Extract metadata from parentheticals
        for content in parentheticals {
            // Check if it's a year (4 digits)
            if let year = Int(content), content.count == 4, year > 1900, year < 2100 {
                metadata.year = year
                print("[MetadataParser]    ✓ Year: \(year)")
            }
            // Check if it's a format indicator
            else if ["Digital", "Paper", "Scan", "Print"].contains(where: { content.localizedCaseInsensitiveContains($0) }) {
                metadata.format = content
                print("[MetadataParser]    ✓ Format: \(content)")
            }
            // Check if it's a publisher (ends with common patterns or contains known publishers)
            else if content.hasSuffix("-Empire") || content.hasSuffix("Comics") || content.hasSuffix("Publishing") ||
                    content.contains("Marvel") || content.contains("DC") || content.contains("Image") {
                metadata.publisher = content
                print("[MetadataParser]    ✓ Publisher: \(content)")
            }
            // Check for scan group or release group patterns
            else if content.count < 30 && content.count > 2 {
                // Skip common non-publisher terms
                let skipTerms = ["covers", "cover", "variant", "variants", "remastered", "hd", "graphic novel"]
                if !skipTerms.contains(where: { content.localizedCaseInsensitiveContains($0) }) {
                    // Likely a publisher/release group (Glix, dekabro-Empire, Paper, etc.)
                    if metadata.publisher == nil {
                        metadata.publisher = content
                        print("[MetadataParser]    ✓ Publisher (group): \(content)")
                    }
                    metadata.scanInformation = content
                }
            }
        }
        
        // Remove all parenthetical content to get base name
        let baseName = nameWithoutExt.replacingOccurrences(of: #"\s*\([^)]+\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        print("[MetadataParser]    Base name: \(baseName)")
        
        // Extract issue number from base name
        // Look for patterns like: "002", "#002", " 002 ", "- 002", ending with "002"
        // Try multiple patterns in order of specificity
        if let issueMatch = baseName.range(of: #"[\s#-](\d{3,4}[A-Za-z]?)(?:\s|$)"#, options: .regularExpression) {
            let issueStr = String(baseName[issueMatch])
                .trimmingCharacters(in: CharacterSet(charactersIn: " #-"))
            metadata.number = issueStr
            print("[MetadataParser]    ✓ Issue: \(issueStr)")
            
            // Extract series (everything before the issue number)
            if let issueRange = baseName.range(of: #"[\s#-]\d{3,4}[A-Za-z]?"#, options: .regularExpression) {
                let seriesName = String(baseName[..<issueRange.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " -#"))
                if !seriesName.isEmpty {
                    metadata.series = seriesName
                    print("[MetadataParser]    ✓ Series: \(seriesName)")
                }
            }
        } 
        // Try shorter issue numbers (1-2 digits) at end of string
        else if let issueMatch = baseName.range(of: #"[\s#-](\d{1,3}[A-Za-z]?)$"#, options: .regularExpression) {
            let issueStr = String(baseName[issueMatch])
                .trimmingCharacters(in: CharacterSet(charactersIn: " #-"))
            metadata.number = issueStr
            print("[MetadataParser]    ✓ Issue (short): \(issueStr)")
            
            // Extract series (everything before the issue number)
            let seriesName = String(baseName[..<issueMatch.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " -#"))
            if !seriesName.isEmpty {
                metadata.series = seriesName
                print("[MetadataParser]    ✓ Series: \(seriesName)")
            }
        } else {
            // No clear issue number, use full base name as series
            metadata.series = baseName
            print("[MetadataParser]    ✓ Series (no issue): \(baseName)")
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
        result.format = pick(comicInfo?.format, pdf?.format, filename?.format)
        result.scanInformation = pick(comicInfo?.scanInformation, pdf?.scanInformation, filename?.scanInformation)
        
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

