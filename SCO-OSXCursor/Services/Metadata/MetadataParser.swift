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

    // Metadata noise patterns to strip from filenames (case-insensitive).
    // These are removed early so they don't interfere with series/issue extraction.
    private static let metadataNoisePatterns: [String] = [
        #"\(digital\)"#,
        #"\(web[- ]?rip\)"#,
        #"\(DCP\)"#,
        #"\(c2c\)"#,
        #"\(GetComics\.INFO\)"#,
        #"\(Minutemen-[^\)]+\)"#,
        #"\(Empire\)"#,
        #"\(Kileko[^\)]*\)"#,
        #"\(\d+\s*covers?\)"#,  // (2 covers), (3 covers)
        #"\(one[- ]?shot\)"#,
        #"\(annual\)"#,
        #"\(cbr\)"#,
        #"\(cbz\)"#,
        #"\(scan\)"#,
    ]

    /// Extract metadata from filename using the sco-dyad ordered extraction pipeline.
    ///
    /// The extraction order is critical — each step cleans the string before the next:
    /// 1. Extract `(of #)` mini-series total
    /// 2. Capture format/scan info, then strip metadata noise
    /// 3. Extract year `(\d{4})`
    /// 4. Extract volume (`V1`, `Vol 2`, `(V1)`)
    /// 5. Extract issue number and split to get series name
    /// 6. Clean series name
    /// 7. Infer publisher from character names
    ///
    /// Examples:
    /// - `"Batman #001 (2024).cbz"` → series: Batman, number: 001, year: 2024
    /// - `"A-Force V2 #003 (2016).cbz"` → series: A-Force, number: 003, year: 2016, volume: 2
    /// - `"Saga 001 (of 04) (2024) (Digital).cbz"` → series: Saga, number: 001, ofTotal: 04, year: 2024
    /// - `"Batman_001_(2024)_(Digital)_(DCP).cbz"` → series: Batman, number: 001, year: 2024
    static func parseFromFilename(_ filename: String) -> ComicMetadata {
        var metadata = ComicMetadata()

        // Remove file extension
        var working = filename.replacingOccurrences(
            of: #"\.(cbz|cbr|pdf|zip|rar)$"#, with: "",
            options: [.regularExpression, .caseInsensitive])

        // Convert underscores to spaces
        working = working.replacingOccurrences(of: "_", with: " ")

        print("[MetadataParser] 📝 Parsing filename: \(working)")

        // ============================================================
        // Step 0: Extract (of #) mini-series total — must be first
        // ============================================================
        if let ofMatch = working.range(
            of: #"\(of\s*(\d+)\)"#, options: [.regularExpression, .caseInsensitive])
        {
            let matched = String(working[ofMatch])
            // Extract just the number
            if let numRange = matched.range(of: #"\d+"#, options: .regularExpression) {
                metadata.ofTotal = String(matched[numRange])
                print("[MetadataParser]    ✓ Of Total: \(metadata.ofTotal!)")
            }
            working = working.replacingCharacters(in: ofMatch, with: "")
        }

        // ============================================================
        // Step 1: Capture format/scan info, then strip metadata noise
        // ============================================================
        // First, capture useful parenthetical info before stripping
        let parenPattern = #"\(([^)]+)\)"#
        if let parenRegex = try? NSRegularExpression(pattern: parenPattern) {
            let matches = parenRegex.matches(
                in: working, range: NSRange(working.startIndex..., in: working))
            for match in matches {
                if let range = Range(match.range(at: 1), in: working) {
                    let content = String(working[range])

                    // Capture format indicators before they get stripped
                    let formatTerms = ["digital", "paper", "scan", "print", "hd", "remastered"]
                    if formatTerms.contains(where: { content.localizedCaseInsensitiveContains($0) })
                    {
                        if metadata.format == nil {
                            metadata.format = content
                            print("[MetadataParser]    ✓ Format: \(content)")
                        }
                    }

                    // Capture scan/release group info (text-text patterns like "Kileko-Empire")
                    if content.contains("-") && !content.contains(" ") && content.count > 3 {
                        metadata.scanInformation = content
                        print("[MetadataParser]    ✓ Scan Info: \(content)")
                    }
                }
            }
        }

        // Now strip all metadata noise patterns
        for pattern in metadataNoisePatterns {
            working = working.replacingOccurrences(
                of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        // Also strip generic (text-text) patterns like (dekabro-Empire)
        working = working.replacingOccurrences(
            of: #"\([a-zA-Z]+-[a-zA-Z]+\)"#, with: "", options: .regularExpression)

        // ============================================================
        // Step 2: Extract year (YYYY) from parentheses
        // ============================================================
        if let yearMatch = working.range(of: #"\((\d{4})\)"#, options: .regularExpression) {
            let matched = String(working[yearMatch])
            if let numRange = matched.range(of: #"\d{4}"#, options: .regularExpression) {
                let yearStr = String(matched[numRange])
                if let year = Int(yearStr), year > 1900, year < 2100 {
                    metadata.year = year
                    print("[MetadataParser]    ✓ Year: \(year)")
                }
            }
            working = working.replacingCharacters(in: yearMatch, with: "")
        }

        // ============================================================
        // Step 3: Extract volume (V1, Vol 2, Volume 3, or (V1))
        // ============================================================
        // Try standalone: "V1", "Vol 2", "Volume 3"
        let volumePatterns = [
            #"\bVol(?:ume)?\.?\s*(\d+)\b"#,  // Vol 2, Volume 3, Vol.2
            #"\bV(\d+)\b"#,  // V2
        ]
        for pattern in volumePatterns {
            if let volMatch = working.range(
                of: pattern, options: [.regularExpression, .caseInsensitive])
            {
                let matched = String(working[volMatch])
                if let numRange = matched.range(of: #"\d+"#, options: .regularExpression) {
                    if let vol = Int(String(matched[numRange])) {
                        metadata.volume = vol
                        print("[MetadataParser]    ✓ Volume: \(vol)")
                    }
                }
                working = working.replacingCharacters(in: volMatch, with: "")
                break
            }
        }
        // Try parenthesized: (V1), (Vol 2)
        if metadata.volume == nil {
            if let volMatch = working.range(
                of: #"\((?:Vol(?:ume)?\.?\s*|V)(\d+)\)"#,
                options: [.regularExpression, .caseInsensitive])
            {
                let matched = String(working[volMatch])
                if let numRange = matched.range(of: #"\d+"#, options: .regularExpression) {
                    if let vol = Int(String(matched[numRange])) {
                        metadata.volume = vol
                        print("[MetadataParser]    ✓ Volume (paren): \(vol)")
                    }
                }
                working = working.replacingCharacters(in: volMatch, with: "")
            }
        }

        // ============================================================
        // Step 4: Extract issue number — try patterns in specificity order
        // ============================================================
        // Strip any remaining parenthetical content before issue extraction
        let cleanedForIssue =
            working
            .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        print("[MetadataParser]    Cleaned for issue: \(cleanedForIssue)")

        // Pattern A: #123 or # 123 (explicit hash)
        // Pattern B: "issue 123" or "issue #123"
        // Pattern C: 3-4 digit standalone (001, 0045)
        // Pattern D: 1-2 digits at end of string
        let issuePatterns: [(pattern: String, description: String)] = [
            (#"#\s*(\d+\.?\d*[A-Za-z]?)"#, "hash"),
            (#"(?i)\bissue\s*#?\s*(\d+\.?\d*[A-Za-z]?)"#, "issue keyword"),
            (#"[\s-](\d{3,4}[A-Za-z]?)(?:\s|$)"#, "3-4 digit"),
            (#"[\s#-](\d{1,2}[A-Za-z]?)$"#, "1-2 digit end"),
        ]

        var issueFound = false
        for (pattern, desc) in issuePatterns {
            if let issueMatch = cleanedForIssue.range(of: pattern, options: .regularExpression) {
                let matched = String(cleanedForIssue[issueMatch])
                // Extract just the number portion
                let issueStr = matched.trimmingCharacters(in: CharacterSet(charactersIn: " #-"))
                    .replacingOccurrences(
                        of: #"(?i)^issue\s*#?\s*"#, with: "", options: .regularExpression)

                if !issueStr.isEmpty {
                    // Zero-pad to 3 digits if it's purely numeric
                    if let issueNum = Int(issueStr) {
                        metadata.number = String(format: "%03d", issueNum)
                    } else {
                        metadata.number = issueStr
                    }
                    print("[MetadataParser]    ✓ Issue (\(desc)): \(metadata.number!)")

                    // Split at the issue number — everything before is the series name
                    let seriesName = String(cleanedForIssue[..<issueMatch.lowerBound])
                        .trimmingCharacters(in: CharacterSet(charactersIn: " -#"))
                    if !seriesName.isEmpty {
                        metadata.series = seriesName
                        print("[MetadataParser]    ✓ Series: \(seriesName)")
                    }

                    issueFound = true
                    break
                }
            }
        }

        // Fallback: no issue number found, use full cleaned string as series
        if !issueFound {
            let fallbackSeries =
                cleanedForIssue
                .replacingOccurrences(of: #"\[.*?\]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: " -#"))
            if !fallbackSeries.isEmpty {
                metadata.series = fallbackSeries
                print("[MetadataParser]    ✓ Series (no issue): \(fallbackSeries)")
            }
        }

        // ============================================================
        // Step 5: Clean series name
        // ============================================================
        if var series = metadata.series {
            // Strip remaining bracket content
            series = series.replacingOccurrences(
                of: #"\[.*?\]"#, with: "", options: .regularExpression)
            // Strip remaining parenthetical content
            series = series.replacingOccurrences(
                of: #"\(.*?\)"#, with: "", options: .regularExpression)
            // Collapse multiple spaces
            series = series.replacingOccurrences(
                of: #"\s{2,}"#, with: " ", options: .regularExpression)
            // Trim trailing non-alphanumeric (but preserve hyphens in names like Spider-Man)
            series = series.trimmingCharacters(in: .whitespacesAndNewlines)
            series = series.replacingOccurrences(
                of: #"[\s\-]+$"#, with: "", options: .regularExpression)

            if !series.isEmpty {
                metadata.series = series
            }
        }

        // ============================================================
        // Step 6: Infer publisher from character names (fallback)
        // ============================================================
        if metadata.publisher == nil {
            if let detected = PublisherDetector.detectFromCharacters(metadata.series) {
                metadata.publisher = detected
                print("[MetadataParser]    ✓ Publisher (from characters): \(detected)")
            }
        }

        print(
            "[MetadataParser] ✅ Result: series=\(metadata.series ?? "nil"), issue=\(metadata.number ?? "nil"), year=\(metadata.year.map { String($0) } ?? "nil"), volume=\(metadata.volume.map { String($0) } ?? "nil"), publisher=\(metadata.publisher ?? "nil"), ofTotal=\(metadata.ofTotal ?? "nil")"
        )

        return metadata
    }

    // MARK: - Merge Metadata

    /// Merge metadata from multiple sources, prioritizing in order: comicInfo, pdf, filename
    static func merge(comicInfo: ComicMetadata?, pdf: ComicMetadata?, filename: ComicMetadata?)
        -> ComicMetadata
    {
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
        result.scanInformation = pick(
            comicInfo?.scanInformation, pdf?.scanInformation, filename?.scanInformation)

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
            throw NSError(
                domain: "XMLParser", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse XML"])
        }

        return metadata as! T
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentValue = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
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
