//
//  TransferManifest.swift
//  SCO-OSXCursor
//
//  The versioned JSON manifest embedded in a `.scobook` transfer package
//  (see docs/DESIGN_book_transfer_2026-07.md). A package is a plain zip:
//
//      manifest.json           — this struct, ISO-8601 dates
//      book/<original name>    — the book file, byte-for-byte untouched
//      cover                   — raw cover image bytes (optional)
//
//  The manifest carries the *transferable subset* of `Comic`: metadata,
//  reading progress, favorite/reading-list flags, and per-book reader
//  preferences. Deliberately excluded: file paths, security-scoped
//  bookmarks, folder membership (folders are device-local — the receiver
//  offers placement instead), `needsAttention`, and transient ComicVine
//  candidate/backup state.
//
//  `comicID` is preserved across devices so a re-sent book can be
//  recognized and offered as a progress/metadata update instead of a
//  duplicate.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Package Layout

/// Constants describing the `.scobook` package layout, shared by the
/// exporter and importer.
enum BookPackage {
    /// File extension for transfer packages.
    static let fileExtension = "scobook"
    /// Exported UTType identifier (declared in Info.plist).
    static let typeIdentifier = "com.rapturepress.supercomicorganizer.scobook"
    /// Zip entry holding the JSON manifest.
    static let manifestEntryPath = "manifest.json"
    /// Zip entry holding the raw cover image bytes (optional).
    static let coverEntryPath = "cover"
    /// Zip entry path for the book file itself.
    static func bookEntryPath(for fileName: String) -> String {
        "book/\(fileName)"
    }

    /// Shared JSON coding — ISO-8601 dates, stable key order for diffability.
    static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension UTType {
    /// The `.scobook` transfer package (exported type, see Info.plist).
    static var scoBookPackage: UTType {
        UTType(exportedAs: BookPackage.typeIdentifier)
    }
}

// MARK: - Transfer Manifest

struct TransferManifest: Codable {
    /// Bump when the manifest layout changes incompatibly. Readers refuse
    /// packages with a HIGHER version than they understand.
    static let currentFormatVersion = 1

    // Package info
    var formatVersion: Int
    var appVersion: String?
    /// "macOS" / "iPadOS" — shown in the receive sheet.
    var sentFromPlatform: String
    var sentAt: Date

    // Identity & integrity
    /// The comic's UUID, preserved across devices (drives duplicate detection).
    var comicID: UUID
    var originalFileName: String
    var fileType: String        // Comic.FileType.rawValue
    var fileSize: Int64
    /// Lowercase hex SHA-256 of the book file, verified after extraction.
    var fileSHA256: String
    /// Zip entry path of the book file inside the package.
    var bookEntryPath: String
    var hasCover: Bool
    /// When the book was added on the sending device (informational only —
    /// the receiver sets its own `dateAdded`).
    var sentDateAdded: Date?

    // MARK: Metadata

    struct Metadata: Codable {
        var title: String?
        var publisher: String?
        var series: String?
        var issueNumber: String?
        var volume: Int?
        var year: Int?
        var bookFormat: String   // Comic.BookFormat.rawValue
        var writer: String?
        var artist: String?
        var coverArtist: String?
        var colorist: String?
        var inker: String?
        var editor: String?
        var summary: String?
        var tags: [String]
        var rating: Int?
        var contentRating: Int   // Comic.ContentRating.rawValue
        /// Optional so manifests from older app versions still decode.
        var storyArcs: [String]?
        var comicVineVolumeID: Int?
        var comicVineIssueID: Int?
        /// Preserved so the receiver's re-fetch gate keeps working (cached
        /// ComicVine responses must not be re-fetched without user intent).
        var metadataFetchedAt: Date?
    }

    // MARK: Reading State

    struct ReadingState: Codable {
        var status: String       // Comic.Status.rawValue
        var currentPage: Int
        var totalPages: Int
        var lastReadDate: Date?
        var isFavorite: Bool
        var isOnReadingList: Bool
    }

    // MARK: Per-Book Reader Preferences

    struct ReaderPrefs: Codable {
        var preferredTransition: String?
        var readingStyle: String?
        var epubFontSize: Int?
        var epubTheme: String?
        var zoomScale: Double?
        var thumbnailBarPosition: String?
    }

    var metadata: Metadata
    var readingState: ReadingState
    var readerPrefs: ReaderPrefs

    // MARK: - Build from a Comic (sending side)

    init(comic: Comic, fileSHA256: String, actualFileSize: Int64) {
        self.formatVersion = TransferManifest.currentFormatVersion
        self.appVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #if os(macOS)
            self.sentFromPlatform = "macOS"
        #else
            self.sentFromPlatform = "iPadOS"
        #endif
        self.sentAt = Date()

        self.comicID = comic.id
        self.originalFileName = comic.fileName
        self.fileType = comic.fileType.rawValue
        self.fileSize = actualFileSize
        self.fileSHA256 = fileSHA256
        self.bookEntryPath = BookPackage.bookEntryPath(for: comic.fileName)
        self.hasCover = comic.coverImageData != nil
        self.sentDateAdded = comic.dateAdded

        self.metadata = Metadata(
            title: comic.title,
            publisher: comic.publisher,
            series: comic.series,
            issueNumber: comic.issueNumber,
            volume: comic.volume,
            year: comic.year,
            bookFormat: comic.bookFormat.rawValue,
            writer: comic.writer,
            artist: comic.artist,
            coverArtist: comic.coverArtist,
            colorist: comic.colorist,
            inker: comic.inker,
            editor: comic.editor,
            summary: comic.summary,
            tags: comic.tags,
            rating: comic.rating,
            contentRating: comic.contentRating.rawValue,
            storyArcs: comic.storyArcs,
            comicVineVolumeID: comic.comicVineVolumeID,
            comicVineIssueID: comic.comicVineIssueID,
            metadataFetchedAt: comic.metadataFetchedAt
        )
        self.readingState = ReadingState(
            status: comic.status.rawValue,
            currentPage: comic.currentPage,
            totalPages: comic.totalPages,
            lastReadDate: comic.lastReadDate,
            isFavorite: comic.isFavorite,
            isOnReadingList: comic.isOnReadingList
        )
        self.readerPrefs = ReaderPrefs(
            preferredTransition: comic.preferredTransition,
            readingStyle: comic.readingStyle,
            epubFontSize: comic.epubFontSize,
            epubTheme: comic.epubTheme,
            zoomScale: comic.zoomScale,
            thumbnailBarPosition: comic.thumbnailBarPosition
        )
    }

    // MARK: - Decoded Enum Accessors

    var decodedFileType: Comic.FileType {
        Comic.FileType(rawValue: fileType) ?? .cbz
    }

    var decodedStatus: Comic.Status {
        Comic.Status(rawValue: readingState.status) ?? .unread
    }

    var decodedBookFormat: Comic.BookFormat {
        Comic.BookFormat(rawValue: metadata.bookFormat) ?? .issue
    }

    var decodedContentRating: Comic.ContentRating {
        Comic.ContentRating(rawValue: metadata.contentRating) ?? .allAges
    }

    /// Display title for the receive sheet (mirrors `Comic.displayTitle`).
    var displayTitle: String {
        var result =
            metadata.series?.nonEmptyTrimmed
            ?? metadata.title?.nonEmptyTrimmed
            ?? (originalFileName as NSString).deletingPathExtension
        if let issue = metadata.issueNumber?.nonEmptyTrimmed {
            result += issue.prefix(1).allSatisfy(\.isNumber) ? " #\(issue)" : " \(issue)"
        }
        if let year = metadata.year {
            result += " (\(String(year)))"
        }
        return result
    }

    // MARK: - Materialize on the Receiving Side

    /// Builds a brand-new `Comic` from this manifest for insertion into the
    /// receiving library. The manifest is authoritative for metadata and
    /// reading state — filename parsing and ComicVine fetch are skipped.
    func makeComic(
        filePath: URL,
        fileName: String,
        bookmarkData: Data?,
        coverData: Data?
    ) -> Comic {
        Comic(
            id: comicID,
            filePath: filePath,
            fileName: fileName,
            bookmarkData: bookmarkData,
            title: metadata.title,
            publisher: metadata.publisher,
            series: metadata.series,
            issueNumber: metadata.issueNumber,
            volume: metadata.volume,
            year: metadata.year,
            bookFormat: decodedBookFormat,
            writer: metadata.writer,
            artist: metadata.artist,
            coverArtist: metadata.coverArtist,
            colorist: metadata.colorist,
            inker: metadata.inker,
            editor: metadata.editor,
            summary: metadata.summary,
            coverImageData: coverData,
            status: decodedStatus,
            currentPage: readingState.currentPage,
            totalPages: readingState.totalPages,
            lastReadDate: readingState.lastReadDate,
            tags: metadata.tags,
            rating: metadata.rating,
            isFavorite: readingState.isFavorite,
            isOnReadingList: readingState.isOnReadingList,
            needsAttention: false,
            preferredTransition: readerPrefs.preferredTransition,
            readingStyle: readerPrefs.readingStyle,
            epubFontSize: readerPrefs.epubFontSize,
            epubTheme: readerPrefs.epubTheme,
            zoomScale: readerPrefs.zoomScale,
            thumbnailBarPosition: readerPrefs.thumbnailBarPosition,
            comicVineVolumeID: metadata.comicVineVolumeID,
            comicVineIssueID: metadata.comicVineIssueID,
            metadataFetchedAt: metadata.metadataFetchedAt,
            storyArcs: metadata.storyArcs ?? [],
            contentRating: decodedContentRating,
            fileSize: fileSize,
            fileType: decodedFileType,
            dateAdded: Date(),
            dateModified: Date()
        )
    }

    /// Applies this manifest onto an existing library copy of the same book
    /// ("Update progress & metadata" on a duplicate). The receiver's file,
    /// bookmark, and `dateAdded` are kept; everything transferable is
    /// overwritten — the incoming manifest is authoritative.
    func apply(to existing: Comic, coverData: Data?) -> Comic {
        var updated = existing

        // Metadata
        updated.title = metadata.title
        updated.publisher = metadata.publisher
        updated.series = metadata.series
        updated.issueNumber = metadata.issueNumber
        updated.volume = metadata.volume
        updated.year = metadata.year
        updated.bookFormat = decodedBookFormat
        updated.writer = metadata.writer
        updated.artist = metadata.artist
        updated.coverArtist = metadata.coverArtist
        updated.colorist = metadata.colorist
        updated.inker = metadata.inker
        updated.editor = metadata.editor
        updated.summary = metadata.summary
        updated.tags = metadata.tags
        updated.rating = metadata.rating
        updated.contentRating = decodedContentRating
        updated.storyArcs = metadata.storyArcs ?? []
        updated.comicVineVolumeID = metadata.comicVineVolumeID
        updated.comicVineIssueID = metadata.comicVineIssueID
        updated.metadataFetchedAt = metadata.metadataFetchedAt

        // Reading state
        updated.status = decodedStatus
        updated.currentPage = readingState.currentPage
        if readingState.totalPages > 0 {
            updated.totalPages = readingState.totalPages
        }
        updated.lastReadDate = readingState.lastReadDate
        updated.isFavorite = readingState.isFavorite
        updated.isOnReadingList = readingState.isOnReadingList

        // Per-book reader prefs
        updated.preferredTransition = readerPrefs.preferredTransition
        updated.readingStyle = readerPrefs.readingStyle
        updated.epubFontSize = readerPrefs.epubFontSize
        updated.epubTheme = readerPrefs.epubTheme
        updated.zoomScale = readerPrefs.zoomScale
        updated.thumbnailBarPosition = readerPrefs.thumbnailBarPosition

        // Cover (only if the package actually carried one)
        if let coverData {
            updated.coverImageData = coverData
        }

        updated.dateModified = Date()
        return updated
    }
}

// MARK: - String Helper

private extension String {
    /// Returns `self` trimmed, or nil when empty/whitespace-only.
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
