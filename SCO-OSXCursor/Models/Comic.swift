//
//  Comic.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation
import GRDB
import SwiftUI

// MARK: - Comic Model
struct Comic: Identifiable, Codable {
    // NOTE: Comic is a struct (value type), so updates create new copies
    // The ViewModel and Library are responsible for updating the stored copy
    // MARK: - Core Properties
    let id: UUID
    var filePath: URL
    var fileName: String
    var bookmarkData: Data?  // Security-scoped bookmark for persistent file access

    // MARK: - Metadata
    var title: String?
    var publisher: String?
    var series: String?
    var issueNumber: String?
    var volume: Int?
    var year: Int?
    /// What kind of book this file is (single issue, one-shot/OGN, collected
    /// volume). Drives clean-naming and import-readiness rules.
    var bookFormat: BookFormat

    // MARK: - Additional Metadata
    var writer: String?
    var artist: String?
    var coverArtist: String?
    var colorist: String?
    var inker: String?
    var editor: String?
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
    var rating: Int?  // 1-5 stars
    var isFavorite: Bool
    var isOnReadingList: Bool
    /// Set when a file move fails or the file is missing on disk; cleared when resolved.
    var needsAttention: Bool

    // MARK: - Reader Preferences
    var preferredTransition: String?  // Per-book transition override (PageTransition.rawValue)
    var readingStyle: String?         // Per-book reading style override (ReadingStyle.rawValue)
    var epubFontSize: Int?            // Per-book EPUB font size (pt), nil = default (16pt)
    var epubTheme: String?            // Per-book EPUB theme (EPUBTheme.rawValue)
    var zoomScale: Double?            // Per-book remembered zoom, nil = 1× (no zoom)
    var contentRating: ContentRating

    // MARK: - ComicVine Metadata
    var comicVineVolumeID: Int?       // Matched ComicVine volume (series) id
    var comicVineIssueID: Int?        // Matched ComicVine issue id (if resolved)
    /// When ComicVine metadata was last fetched. Non-nil = don't auto re-fetch
    /// (responses must be cached per ComicVine's terms) unless the user forces it.
    var metadataFetchedAt: Date?
    /// JSON [CVCandidate] stored when a search was ambiguous, so the user can
    /// resolve it later from the match picker at zero additional API cost.
    var metadataCandidates: String?

    // MARK: - File Info
    var fileSize: Int64  // in bytes
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
        bookFormat: BookFormat = .issue,
        writer: String? = nil,
        artist: String? = nil,
        coverArtist: String? = nil,
        colorist: String? = nil,
        inker: String? = nil,
        editor: String? = nil,
        summary: String? = nil,
        coverImageData: Data? = nil,
        status: Status = .unread,
        currentPage: Int = 0,
        totalPages: Int = 0,
        lastReadDate: Date? = nil,
        tags: [String] = [],
        rating: Int? = nil,
        isFavorite: Bool = false,
        isOnReadingList: Bool = false,
        needsAttention: Bool = false,
        preferredTransition: String? = nil,
        readingStyle: String? = nil,
        epubFontSize: Int? = nil,
        epubTheme: String? = nil,
        zoomScale: Double? = nil,
        comicVineVolumeID: Int? = nil,
        comicVineIssueID: Int? = nil,
        metadataFetchedAt: Date? = nil,
        metadataCandidates: String? = nil,
        contentRating: ContentRating = .allAges,
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
        self.bookFormat = bookFormat
        self.writer = writer
        self.artist = artist
        self.coverArtist = coverArtist
        self.colorist = colorist
        self.inker = inker
        self.editor = editor
        self.summary = summary
        self.coverImageData = coverImageData
        self.status = status
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.lastReadDate = lastReadDate
        self.tags = tags
        self.rating = rating
        self.isFavorite = isFavorite
        self.isOnReadingList = isOnReadingList
        self.needsAttention = needsAttention
        self.preferredTransition = preferredTransition
        self.readingStyle = readingStyle
        self.epubFontSize = epubFontSize
        self.epubTheme = epubTheme
        self.zoomScale = zoomScale
        self.comicVineVolumeID = comicVineVolumeID
        self.comicVineIssueID = comicVineIssueID
        self.metadataFetchedAt = metadataFetchedAt
        self.metadataCandidates = metadataCandidates
        self.contentRating = contentRating
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

        /// Human-readable label shown in the UI (rawValue is kept for DB compatibility)
        var displayLabel: String {
            switch self {
            case .unread: return "Unread"
            case .reading: return "Currently Reading"
            case .completed: return "Completed"
            }
        }

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

// MARK: - Content Rating Enum
extension Comic {
    enum ContentRating: Int, Codable, CaseIterable {
        case allAges = 0, teen, matureTeen, mature, explicit

        var label: String {
            switch self {
            case .allAges: return "All Ages"
            case .teen: return "Teen"
            case .matureTeen: return "Mature Teen"
            case .mature: return "Mature"
            case .explicit: return "Explicit"
            }
        }
    }
}

// MARK: - Book Format Enum
extension Comic {
    /// What kind of book a file represents. A "volume" here means a collected
    /// edition / manga volume (Series Vol. 03), distinct from the `volume`
    /// integer on issues which disambiguates relaunched runs (Iron Man v3 #1).
    enum BookFormat: String, Codable, CaseIterable {
        case issue = "issue"
        case oneShot = "one_shot"
        case volume = "volume"
        case ebook = "ebook"

        var displayName: String {
            switch self {
            case .issue: return "Issue"
            case .oneShot: return "One-Shot"
            case .volume: return "Volume"
            case .ebook: return "eBook"
            }
        }

        var icon: String {
            switch self {
            case .issue: return "number"
            case .oneShot: return "book.closed"
            case .volume: return "books.vertical"
            case .ebook: return "text.book.closed"
            }
        }

        /// Heuristic detection from parsed filename metadata:
        /// EPUBs are prose ebooks; an issue number means a single issue; a
        /// volume number without an issue means a collected/manga volume;
        /// neither means a one-shot/OGN.
        static func detect(
            issueNumber: String?, volume: Int?, fileType: Comic.FileType? = nil
        ) -> BookFormat {
            if fileType == .epub { return .ebook }
            if let issueNumber, !issueNumber.isEmpty { return .issue }
            if volume != nil { return .volume }
            return .oneShot
        }
    }
}

// MARK: - File Type Enum
extension Comic {
    enum FileType: String, Codable, CaseIterable {
        case cbz = "cbz"
        case cbr = "cbr"
        case pdf = "pdf"
        case epub = "epub"

        var displayName: String {
            rawValue.uppercased()
        }

        var icon: String {
            switch self {
            case .cbz, .cbr: return "doc.zipper"
            case .pdf: return "doc.richtext"
            case .epub: return "book.pages"
            }
        }

        /// True for formats whose content is text/HTML (not image pages)
        var isTextBased: Bool {
            self == .epub
        }
    }
}

// MARK: - Computed Properties
extension Comic {
    /// Display name shown on library cards and used as the alphabetical sort
    /// key. Comics use the SERIES so the grid stays grouped by series and
    /// sorts predictably — the per-issue storyline title (e.g. ComicVine's
    /// issue name) is shown separately in the Info panel and editor, and would
    /// otherwise scatter the library (e.g. "Action Comics" sorting under its
    /// storyline "Future Shock"). eBooks/novels prefer their title, since they
    /// often have no distinct series.
    var displayName: String {
        if fileType != .epub, let series = series, !series.isEmpty {
            return series
        }
        if let title = title, !title.isEmpty {
            return title
        }
        if let series = series, !series.isEmpty {
            return series
        }
        return fileName.replacingOccurrences(of: ".\(fileType.rawValue)", with: "")
    }

    /// Human-readable label for the item type (comic vs book)
    var mediaTypeLabel: String {
        fileType == .epub ? "Book" : "Comic"
    }

    /// Full display title with issue number and year
    var displayTitle: String {
        var result = displayName
        if let issueNumber = issueNumber, !issueNumber.isEmpty {
            // Only add '#' prefix if issue number starts with a digit
            if issueNumber.prefix(1).allSatisfy(\.isNumber) {
                result += " #\(issueNumber)"
            } else {
                result += " \(issueNumber)"
            }
        }
        if let year = year {
            result += " (\(String(year)))"
        }
        return result
    }

    /// Clean filename built from parsed metadata (for display and renaming).
    /// Format depends on the book's format:
    ///   issue    → "Series Name V2 #001 (2025).cbz"
    ///   one-shot → "Series Name (2025).cbz"
    ///   volume   → "Series Name Vol. 03 (2025).cbz"
    var cleanFileName: String {
        var parts: [String] = []

        // Series name (or title, or original filename without extension)
        let baseName: String
        if let series = series, !series.isEmpty {
            baseName = series
        } else if let title = title, !title.isEmpty {
            baseName = title
        } else {
            // Just return original filename as-is
            return fileName
        }
        parts.append(baseName)

        switch bookFormat {
        case .issue:
            // Run/volume disambiguator (Iron Man v3)
            if let volume = volume {
                parts.append("V\(volume)")
            }
            if let issueNumber = issueNumber, !issueNumber.isEmpty {
                // Only add '#' prefix if issue number starts with a digit
                if issueNumber.prefix(1).allSatisfy(\.isNumber) {
                    parts.append("#\(issueNumber)")
                } else {
                    parts.append(issueNumber)
                }
            }

        case .oneShot, .ebook:
            // Self-contained book: just "Title (Year)"
            break

        case .volume:
            // Collected edition / manga volume
            if let volume = volume {
                parts.append(String(format: "Vol. %02d", volume))
            }
        }

        // Year
        if let year = year {
            parts.append("(\(year))")
        }

        return parts.joined(separator: " ") + ".\(fileType.rawValue)"
    }

    /// Reading progress as percentage (0.0 - 1.0)
    var progress: Double {
        guard totalPages > 0 else { return 0.0 }
        // currentPage is 0-based, so add 1 for actual page number
        return Double(currentPage + 1) / Double(totalPages)
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

    /// Publisher badge color (using PublisherDetector)
    var publisherColor: Color {
        return PublisherDetector.color(for: publisher)
    }

    /// Normalized publisher name
    var normalizedPublisher: String? {
        return PublisherDetector.normalize(publisher)
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
            fileSize: 45_000_000,  // 45 MB
            fileType: .cbz
        )
    }

    /// Generate multiple sample comics for testing
    static var samples: [Comic] {
        var comics: [Comic] = [
            sample(
                title: "Absolute Batman", publisher: "DC Comics", issueNumber: "001", year: 2025,
                status: .unread),
            sample(
                title: "Absolute Batman", publisher: "DC Comics", issueNumber: "002", year: 2025,
                status: .reading),
            sample(
                title: "Absolute Batman", publisher: "DC Comics", issueNumber: "003", year: 2025,
                status: .completed),
            sample(
                title: "Absolute Flash", publisher: "DC Comics", issueNumber: "001", year: 2025,
                status: .unread),
            sample(
                title: "Absolute Superman", publisher: "DC Comics", issueNumber: "001", year: 2025,
                status: .unread),
            sample(
                title: "Amazing Spider-Man", publisher: "Marvel", issueNumber: "001", year: 2025,
                status: .reading),
            sample(
                title: "X-Men", publisher: "Marvel", issueNumber: "001", year: 2025,
                status: .completed),
            sample(
                title: "The Walking Dead", publisher: "Image Comics", issueNumber: "001",
                year: 2003, status: .completed),
            sample(
                title: "Saga", publisher: "Image Comics", issueNumber: "001", year: 2012,
                status: .unread),
            sample(
                title: "Hellboy", publisher: "Dark Horse", issueNumber: "001", year: 1994,
                status: .reading),
        ]

        // Mark some as favorites
        comics[0].isFavorite = true  // Absolute Batman #001
        comics[5].isFavorite = true  // Amazing Spider-Man #001
        comics[8].isFavorite = true  // Saga #001

        // Set some reading progress
        comics[1].currentPage = 15  // Absolute Batman #002 - 47%
        comics[5].currentPage = 20  // Amazing Spider-Man - 63%
        comics[9].currentPage = 8  // Hellboy - 25%

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

// MARK: - GRDB Conformance
extension Comic: FetchableRecord, PersistableRecord {
    static let databaseTableName = "comics"

    // Column names (using string literals to avoid circular reference with CodingKeys)
    enum Columns {
        static let id = Column("id")
        static let filePath = Column("file_path")
        static let fileName = Column("file_name")
        static let bookmarkData = Column("bookmark_data")
        static let title = Column("title")
        static let publisher = Column("publisher")
        static let series = Column("series")
        static let issueNumber = Column("issue_number")
        static let volume = Column("volume")
        static let year = Column("year")
        static let bookFormat = Column("book_format")
        static let writer = Column("writer")
        static let artist = Column("artist")
        static let coverArtist = Column("cover_artist")
        static let colorist = Column("colorist")
        static let inker = Column("inker")
        static let editor = Column("editor")
        static let summary = Column("summary")
        static let coverImageData = Column("cover_image_data")
        static let status = Column("status")
        static let currentPage = Column("current_page")
        static let totalPages = Column("total_pages")
        static let lastReadDate = Column("last_read_date")
        static let tags = Column("tags")
        static let rating = Column("rating")
        static let isFavorite = Column("is_favorite")
        static let isOnReadingList = Column("is_on_reading_list")
        static let needsAttention = Column("needs_attention")
        static let preferredTransition = Column("preferred_transition")
        static let readingStyle = Column("reading_style")
        static let epubFontSize = Column("epub_font_size")
        static let epubTheme = Column("epub_theme")
        static let zoomScale = Column("zoom_scale")
        static let comicVineVolumeID = Column("comicvine_volume_id")
        static let comicVineIssueID = Column("comicvine_issue_id")
        static let metadataFetchedAt = Column("metadata_fetched_at")
        static let metadataCandidates = Column("metadata_candidates")
        static let contentRating = Column("content_rating")
        static let fileSize = Column("file_size")
        static let fileType = Column("file_type")
        static let dateAdded = Column("date_added")
        static let dateModified = Column("date_modified")
    }

    // Custom encoding for database
    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.filePath] = filePath.path  // Store as string
        container[Columns.fileName] = fileName
        container[Columns.bookmarkData] = bookmarkData
        container[Columns.title] = title
        container[Columns.publisher] = publisher
        container[Columns.series] = series
        container[Columns.issueNumber] = issueNumber
        container[Columns.volume] = volume
        container[Columns.year] = year
        container[Columns.bookFormat] = bookFormat.rawValue
        container[Columns.writer] = writer
        container[Columns.artist] = artist
        container[Columns.coverArtist] = coverArtist
        container[Columns.colorist] = colorist
        container[Columns.inker] = inker
        container[Columns.editor] = editor
        container[Columns.summary] = summary
        container[Columns.coverImageData] = coverImageData
        container[Columns.status] = status.rawValue
        container[Columns.currentPage] = currentPage
        container[Columns.totalPages] = totalPages
        container[Columns.lastReadDate] = lastReadDate
        container[Columns.tags] = try? JSONEncoder().encode(tags)  // Store as JSON
        container[Columns.rating] = rating
        container[Columns.isFavorite] = isFavorite
        container[Columns.isOnReadingList] = isOnReadingList
        container[Columns.needsAttention] = needsAttention
        container[Columns.preferredTransition] = preferredTransition
        container[Columns.readingStyle] = readingStyle
        container[Columns.epubFontSize] = epubFontSize
        container[Columns.epubTheme] = epubTheme
        container[Columns.zoomScale] = zoomScale
        container[Columns.comicVineVolumeID] = comicVineVolumeID
        container[Columns.comicVineIssueID] = comicVineIssueID
        container[Columns.metadataFetchedAt] = metadataFetchedAt
        container[Columns.metadataCandidates] = metadataCandidates
        container[Columns.contentRating] = contentRating.rawValue
        container[Columns.fileSize] = fileSize
        container[Columns.fileType] = fileType.rawValue
        container[Columns.dateAdded] = dateAdded
        container[Columns.dateModified] = dateModified
    }

    // Custom decoding from database
    init(row: Row) throws {
        // Required properties
        guard let idString: String = row["id"],
            let id = UUID(uuidString: idString),
            let filePathString: String = row["file_path"],
            let fileName: String = row["file_name"],
            let statusString: String = row["status"],
            let status = Status(rawValue: statusString),
            let fileTypeString: String = row["file_type"],
            let fileType = FileType(rawValue: fileTypeString),
            let currentPage: Int = row["current_page"],
            let totalPages: Int = row["total_pages"],
            let fileSize: Int64 = row["file_size"],
            let dateAdded: Date = row["date_added"],
            let dateModified: Date = row["date_modified"]
        else {
            throw DatabaseError.fetchFailed
        }

        // Decode tags from JSON
        var decodedTags: [String] = []
        if let tagsData: Data = row["tags"] {
            decodedTags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
        }

        self.init(
            id: id,
            filePath: URL(fileURLWithPath: filePathString),
            fileName: fileName,
            bookmarkData: row["bookmark_data"],
            title: row["title"],
            publisher: row["publisher"],
            series: row["series"],
            issueNumber: row["issue_number"],
            volume: row["volume"],
            year: row["year"],
            bookFormat: BookFormat(rawValue: row["book_format"] ?? "issue") ?? .issue,
            writer: row["writer"],
            artist: row["artist"],
            coverArtist: row["cover_artist"],
            colorist: row["colorist"],
            inker: row["inker"],
            editor: row["editor"],
            summary: row["summary"],
            coverImageData: row["cover_image_data"],
            status: status,
            currentPage: currentPage,
            totalPages: totalPages,
            lastReadDate: row["last_read_date"],
            tags: decodedTags,
            rating: row["rating"],
            isFavorite: row["is_favorite"] ?? false,
            isOnReadingList: row["is_on_reading_list"] ?? false,
            needsAttention: row["needs_attention"] ?? false,
            preferredTransition: row["preferred_transition"],
            readingStyle: row["reading_style"],
            epubFontSize: row["epub_font_size"],
            epubTheme: row["epub_theme"],
            zoomScale: row["zoom_scale"],
            comicVineVolumeID: row["comicvine_volume_id"],
            comicVineIssueID: row["comicvine_issue_id"],
            metadataFetchedAt: row["metadata_fetched_at"],
            metadataCandidates: row["metadata_candidates"],
            contentRating: ContentRating(rawValue: row["content_rating"] ?? 0) ?? .allAges,
            fileSize: fileSize,
            fileType: fileType,
            dateAdded: dateAdded,
            dateModified: dateModified
        )
    }
}

// MARK: - Bundle Detection
extension Comic {
    /// Memoized list of known bundled files (scanned once)
    private static let knownBundledFiles: [String] = {
        let exts = ["cbz", "pdf", "cbr", "epub"]
        return exts.flatMap { ext in
            Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil)?
                .map { $0.lastPathComponent } ?? []
        }
    }()

    /// A URL that is guaranteed to work even if the bundle path changed (common on iOS)
    var resolvedURL: URL {
        if Comic.isBundled(self) {
            // Re-locate in bundle by filename
            if let bundleURL = Bundle.main.url(
                forResource: (fileName as NSString).deletingPathExtension,
                withExtension: (fileName as NSString).pathExtension)
            {
                return bundleURL
            }
        }
        return filePath
    }

    /// Check if a comic is a bundled sample resource
    static func isBundled(_ comic: Comic) -> Bool {
        let isInBundle = comic.filePath.path.contains(Bundle.main.bundlePath)
        let matchesBundledFilename = knownBundledFiles.contains {
            $0.caseInsensitiveCompare(comic.fileName) == .orderedSame
        }
        return isInBundle || matchesBundledFilename
    }
}
