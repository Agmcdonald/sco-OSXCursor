//
//  ComicMetadata.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/7/25.
//
//  ComicInfo.xml Metadata Structure
//  ================================
//  Standard format for comic book metadata stored in CBZ files
//  XML file typically located at root of ZIP archive as "ComicInfo.xml"
//
//  Key Fields:
//  - Title: Comic book title
//  - Series: Series name
//  - Number: Issue number
//  - Volume: Volume number
//  - Summary: Plot synopsis
//  - Publisher: Publishing company
//  - Writer: Story writer(s)
//  - Penciller: Primary artist
//  - Inker: Inking artist
//  - Colorist: Color artist
//  - Letterer: Lettering artist
//  - CoverArtist: Cover artist
//  - Editor: Editor name
//  - Year: Publication year
//  - Month: Publication month (1-12)
//  - Day: Publication day
//  - PageCount: Total number of pages
//  - LanguageISO: Language code (e.g., "en")
//  - Genre: Genre/category
//  - Web: Website URL
//  - Characters: Character list
//  - Teams: Team/group list
//  - Locations: Location list
//  - AgeRating: Age rating
//  - StoryArc: Story arc name
//  - SeriesGroup: Series grouping
//

import Foundation

// MARK: - Comic Metadata Model
struct ComicMetadata: Codable {
    // Core Info
    var title: String?
    var series: String?
    var number: String?           // Issue number (can be string like "1A" or "Annual 1")
    var volume: Int?
    var summary: String?
    var notes: String?
    
    // Publishing Info
    var publisher: String?
    var imprint: String?
    var genre: String?
    var web: String?
    var languageISO: String?
    var format: String?
    var ageRating: String?
    
    // Dates
    var year: Int?
    var month: Int?
    var day: Int?
    
    // Credits
    var writer: String?
    var penciller: String?
    var inker: String?
    var colorist: String?
    var letterer: String?
    var coverArtist: String?
    var editor: String?
    
    // Content
    var pageCount: Int?
    var characters: String?
    var teams: String?
    var locations: String?
    var storyArc: String?
    var seriesGroup: String?
    
    // Additional
    var blackAndWhite: Bool?
    var manga: String?           // Manga reading direction
    var scanInformation: String?
    
    // CodingKeys for XML parsing
    enum CodingKeys: String, CodingKey {
        case title = "Title"
        case series = "Series"
        case number = "Number"
        case volume = "Volume"
        case summary = "Summary"
        case notes = "Notes"
        case publisher = "Publisher"
        case imprint = "Imprint"
        case genre = "Genre"
        case web = "Web"
        case languageISO = "LanguageISO"
        case format = "Format"
        case ageRating = "AgeRating"
        case year = "Year"
        case month = "Month"
        case day = "Day"
        case writer = "Writer"
        case penciller = "Penciller"
        case inker = "Inker"
        case colorist = "Colorist"
        case letterer = "Letterer"
        case coverArtist = "CoverArtist"
        case editor = "Editor"
        case pageCount = "PageCount"
        case characters = "Characters"
        case teams = "Teams"
        case locations = "Locations"
        case storyArc = "StoryArc"
        case seriesGroup = "SeriesGroup"
        case blackAndWhite = "BlackAndWhite"
        case manga = "Manga"
        case scanInformation = "ScanInformation"
    }
    
    // Computed Properties
    var displayTitle: String? {
        if let title = title, !title.isEmpty {
            return title
        }
        if let series = series, !series.isEmpty {
            var result = series
            if let number = number, !number.isEmpty {
                result += " #\(number)"
            }
            return result
        }
        return nil
    }
    
    var publicationDate: Date? {
        guard let year = year else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month ?? 1
        components.day = day ?? 1
        return Calendar.current.date(from: components)
    }
    
    // Combine all credits into single string
    var allCredits: String? {
        var credits: [String] = []
        if let writer = writer, !writer.isEmpty {
            credits.append("Writer: \(writer)")
        }
        if let penciller = penciller, !penciller.isEmpty {
            credits.append("Artist: \(penciller)")
        }
        if let colorist = colorist, !colorist.isEmpty {
            credits.append("Colorist: \(colorist)")
        }
        if let coverArtist = coverArtist, !coverArtist.isEmpty {
            credits.append("Cover: \(coverArtist)")
        }
        return credits.isEmpty ? nil : credits.joined(separator: " • ")
    }
}

// MARK: - Metadata Source
enum MetadataSource {
    case comicInfo      // ComicInfo.xml from CBZ
    case pdfProperties  // PDF document properties
    case filename       // Parsed from filename
    case manual         // User-entered
}

