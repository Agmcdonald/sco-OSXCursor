//
//  Comic.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import SwiftUI

// MARK: - Comic Model
struct Comic: Identifiable, Codable {
    // NOTE: Comic is a struct (value type), so updates create new copies
    // The ViewModel and Library are responsible for updating the stored copy
    // MARK: - Core Properties
    let id: UUID
    var filePath: URL
    var fileName: String
    var bookmarkData: Data? // Security-scoped bookmark for persistent file access
    
    // MARK: - Metadata
    var title: String?
    var publisher: String?
    var series: String?
    var issueNumber: String?
    var volume: Int?
    var year: Int?
    
    // MARK: - Additional Metadata
    var writer: String?
    var artist: String?
    var coverArtist: String?
    var summary: String?
    
    // MARK: - Cover & Visual
    var coverImageData: Data?
    
    // MARK: - Status & Progress
    var status: Status
    var currentPage: Int
    var totalPages: Int
    var lastReadDate: Date?
    
    // MARK: - Organization
    var tags: [String]
    var rating: Int? // 1-5 stars
    var isFavorite: Bool
    
    // MARK: - File Info
    var fileSize: Int64 // in bytes
    var fileType: FileType
    
    // MARK: - Timestamps
    var dateAdded: Date
    var dateModified: Date
    
    // MARK: - Initializer
    init(
        id: UUID = UUID(),
        filePath: URL,
        fileName: String,
        bookmarkData: Data? = nil,
        title: String? = nil,
        publisher: String? = nil,
        series: String? = nil,
        issueNumber: String? = nil,
        volume: Int? = nil,
        year: Int? = nil,
        writer: String? = nil,
        artist: String? = nil,
        coverArtist: String? = nil,
        summary: String? = nil,
        coverImageData: Data? = nil,
        status: Status = .unread,
        currentPage: Int = 0,
        totalPages: Int = 0,
        lastReadDate: Date? = nil,
        tags: [String] = [],
        rating: Int? = nil,
        isFavorite: Bool = false,
        fileSize: Int64 = 0,
        fileType: FileType = .cbz,
        dateAdded: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.fileName = fileName
        self.bookmarkData = bookmarkData
        self.title = title
        self.publisher = publisher
        self.series = series
        self.issueNumber = issueNumber
        self.volume = volume
        self.year = year
        self.writer = writer
        self.artist = artist
        self.coverArtist = coverArtist
        self.summary = summary
        self.coverImageData = coverImageData
        self.status = status
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.lastReadDate = lastReadDate
        self.tags = tags
        self.rating = rating
        self.isFavorite = isFavorite
        self.fileSize = fileSize
        self.fileType = fileType
        self.dateAdded = dateAdded
        self.dateModified = dateModified
    }
}

// MARK: - Status Enum
extension Comic {
    enum Status: String, Codable, CaseIterable {
        case unread = "Unread"
        case reading = "Reading"
        case completed = "Completed"
        
        var color: Color {
            switch self {
            case .unread: return SemanticColors.unread
            case .reading: return SemanticColors.reading
            case .completed: return SemanticColors.completed
            }
        }
        
        var icon: String {
            switch self {
            case .unread: return "book.closed"
            case .reading: return "book"
            case .completed: return "checkmark.circle.fill"
            }
        }
    }
}

// MARK: - File Type Enum
extension Comic {
    enum FileType: String, Codable, CaseIterable {
        case cbz = "cbz"
        case cbr = "cbr"
        case pdf = "pdf"
        
        var displayName: String {
            rawValue.uppercased()
        }
        
        var icon: String {
            switch self {
            case .cbz, .cbr: return "doc.zipper"
            case .pdf: return "doc.richtext"
            }
        }
    }
}

// MARK: - Computed Properties
extension Comic {
    /// Display name for the comic (uses title if available, otherwise filename)
    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return fileName.replacingOccurrences(of: ".\(fileType.rawValue)", with: "")
    }
    
    /// Full display title with issue number
    var displayTitle: String {
        var result = displayName
        if let issueNumber = issueNumber, !issueNumber.isEmpty {
            result += " #\(issueNumber)"
        }
        if let year = year {
            result += " (\(year))"
        }
        return result
    }
    
    /// Reading progress as percentage (0.0 - 1.0)
    var progress: Double {
        guard totalPages > 0 else { return 0.0 }
        return Double(currentPage) / Double(totalPages)
    }
    
    /// Reading progress as percentage string
    var progressPercentage: String {
        let percentage = Int(progress * 100)
        return "\(percentage)%"
    }
    
    /// Check if comic has been read
    var isRead: Bool {
        return status == .completed || (totalPages > 0 && currentPage >= totalPages)
    }
    
    /// Check if comic is currently being read
    var isInProgress: Bool {
        return status == .reading || (currentPage > 0 && currentPage < totalPages)
    }
    
    /// File size in human-readable format
    var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    /// Publisher badge color
    var publisherColor: Color {
        guard let publisher = publisher?.lowercased() else {
            return AccentColors.primary
        }
        
        if publisher.contains("dc") {
            return SemanticColors.dcComics
        } else if publisher.contains("marvel") {
            return SemanticColors.marvel
        } else if publisher.contains("image") {
            return SemanticColors.imageComics
        } else if publisher.contains("dark horse") {
            return SemanticColors.darkHorse
        } else if publisher.contains("vertigo") {
            return SemanticColors.vertigo
        }
        
        return AccentColors.primary
    }
}

// MARK: - Sample Data
extension Comic {
    /// Generate sample comic for testing and previews
    static func sample(
        title: String = "Absolute Batman",
        publisher: String = "DC Comics",
        issueNumber: String = "001",
        year: Int = 2025,
        status: Status = .unread
    ) -> Comic {
        Comic(
            filePath: URL(fileURLWithPath: "/tmp/\(title).cbz"),
            fileName: "\(title) #\(issueNumber) (\(year)).cbz",
            title: title,
            publisher: publisher,
            series: title,
            issueNumber: issueNumber,
            year: year,
            writer: "Scott Snyder",
            artist: "Nick Dragotta",
            summary: "A reimagining of the Dark Knight in an all-new universe.",
            status: status,
            currentPage: 0,
            totalPages: 32,
            tags: ["Batman", "DC", "Superhero"],
            fileSize: 45_000_000, // 45 MB
            fileType: .cbz
        )
    }
    
    /// Generate multiple sample comics for testing
    static var samples: [Comic] {
        var comics: [Comic] = [
            sample(title: "Absolute Batman", publisher: "DC Comics", issueNumber: "001", year: 2025, status: .unread),
            sample(title: "Absolute Batman", publisher: "DC Comics", issueNumber: "002", year: 2025, status: .reading),
            sample(title: "Absolute Batman", publisher: "DC Comics", issueNumber: "003", year: 2025, status: .completed),
            sample(title: "Absolute Flash", publisher: "DC Comics", issueNumber: "001", year: 2025, status: .unread),
            sample(title: "Absolute Superman", publisher: "DC Comics", issueNumber: "001", year: 2025, status: .unread),
            sample(title: "Amazing Spider-Man", publisher: "Marvel", issueNumber: "001", year: 2025, status: .reading),
            sample(title: "X-Men", publisher: "Marvel", issueNumber: "001", year: 2025, status: .completed),
            sample(title: "The Walking Dead", publisher: "Image Comics", issueNumber: "001", year: 2003, status: .completed),
            sample(title: "Saga", publisher: "Image Comics", issueNumber: "001", year: 2012, status: .unread),
            sample(title: "Hellboy", publisher: "Dark Horse", issueNumber: "001", year: 1994, status: .reading),
        ]
        
        // Mark some as favorites
        comics[0].isFavorite = true  // Absolute Batman #001
        comics[5].isFavorite = true  // Amazing Spider-Man #001
        comics[8].isFavorite = true  // Saga #001
        
        // Set some reading progress
        comics[1].currentPage = 15    // Absolute Batman #002 - 47%
        comics[5].currentPage = 20    // Amazing Spider-Man - 63%
        comics[9].currentPage = 8     // Hellboy - 25%
        
        return comics
    }
}

// MARK: - Equatable
extension Comic: Equatable {
    static func == (lhs: Comic, rhs: Comic) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable
extension Comic: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

