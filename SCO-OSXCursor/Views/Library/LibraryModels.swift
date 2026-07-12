//
//  LibraryModels.swift
//  SCO-OSXCursor
//
//  Library browsing models and query logic, extracted from LibraryView
//  (Stage 4 split). Pure data + functions — no SwiftUI views — so the
//  filter/sort/group pipeline is unit-testable.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom UTTypes (import file picker)

extension UTType {
    static var cbr: UTType {
        UTType(exportedAs: "com.rarlab.rar-archive")
    }

    // epub is a well-known public UTType — use the system identifier
    static var epub: UTType {
        UTType(importedAs: "org.idpf.epub-container")
    }
}

// MARK: - View Mode

enum LibraryViewMode {
    case grid, list, publisher, folders
}

// MARK: - Library Scope

/// What the grid is currently scoped to. `all` is the whole library, `unfiled`
/// is books that belong to no folder, and `folder` is one collection.
enum LibraryScope: Equatable {
    case all
    case unfiled
    case folder(UUID)
}

// MARK: - Sort Option

enum LibrarySortOption: String, CaseIterable {
    case title = "Title (A-Z)"
    case dateAdded = "Date Added"
    case dateModified = "Recently Modified"
    case publisher = "Publisher"
    case year = "Publication Year"
    case rating = "Rating"
    case fileSize = "File Size"

    var icon: String {
        switch self {
        case .title: return "textformat"
        case .dateAdded: return "calendar.badge.plus"
        case .dateModified: return "calendar.badge.clock"
        case .publisher: return "building.2"
        case .year: return "calendar"
        case .rating: return "star"
        case .fileSize: return "externaldrive"
        }
    }
}

// MARK: - Filters

/// All library filters in one value — one binding instead of several.
/// Every group is MULTI-SELECT: an empty set means "All" for that group;
/// values within a group combine with OR (PDF + EPUB shows both), and
/// groups combine with AND (2015 + Marvel = Marvel books from 2015).
struct LibraryFilters: Equatable {
    var statuses: Set<Comic.Status> = []
    var publishers: Set<String> = []
    var series: Set<String> = []
    var years: Set<Int> = []
    var contentRatings: Set<Comic.ContentRating> = []
    var fileTypes: Set<Comic.FileType> = []
    var readingList: Bool = false

    var hasActive: Bool {
        !statuses.isEmpty || !publishers.isEmpty || !series.isEmpty || !years.isEmpty
            || !contentRatings.isEmpty || !fileTypes.isEmpty || readingList
    }

    mutating func clear() {
        self = LibraryFilters()
    }

    /// Toggle chip helper: insert if absent, remove if present.
    mutating func toggle<T: Hashable>(
        _ value: T, in keyPath: WritableKeyPath<LibraryFilters, Set<T>>
    ) {
        if self[keyPath: keyPath].contains(value) {
            self[keyPath: keyPath].remove(value)
        } else {
            self[keyPath: keyPath].insert(value)
        }
    }
}

// MARK: - Publisher Hierarchy

struct SeriesGroup: Identifiable {
    let id: String  // "Publisher::Series"
    let series: String
    let comics: [Comic]
    var yearRange: String {
        let years = comics.compactMap { $0.year }.sorted()
        guard !years.isEmpty else { return "" }
        if years.first == years.last { return String(years.first!) }
        return "\(years.first!)-\(years.last!)"
    }
}

struct PublisherGroup: Identifiable {
    let id: String  // publisher name
    let publisher: String
    let seriesGroups: [SeriesGroup]
    var totalComics: Int { seriesGroups.reduce(0) { $0 + $1.comics.count } }
    var yearRange: String {
        let years = seriesGroups.flatMap { $0.comics }.compactMap { $0.year }.sorted()
        guard !years.isEmpty else { return "" }
        if years.first == years.last { return String(years.first!) }
        return "\(years.first!)-\(years.last!)"
    }
}

// MARK: - Query Pipeline

enum LibraryQuery {

    /// Search + filter + sort, in display order.
    ///
    /// - Parameter restrictTo: when non-nil, only comics whose IDs are in this
    ///   set are considered (used to scope the grid to the current folder).
    ///   Pass nil to search/sort the whole library.
    static func apply(
        to comics: [Comic],
        searchText: String,
        filters: LibraryFilters,
        sort: LibrarySortOption,
        restrictTo: Set<UUID>? = nil
    ) -> [Comic] {
        var result = comics

        // Folder scope (applied before search/filter)
        if let restrictTo = restrictTo {
            result = result.filter { restrictTo.contains($0.id) }
        }

        // Search across all metadata fields
        if !searchText.isEmpty {
            result = result.filter { comic in
                comic.displayTitle.localizedCaseInsensitiveContains(searchText)
                    || comic.fileName.localizedCaseInsensitiveContains(searchText)
                    || comic.title?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.publisher?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.series?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.writer?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.artist?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.coverArtist?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.summary?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.issueNumber?.localizedCaseInsensitiveContains(searchText) == true
                    || comic.tags.contains(where: {
                        $0.localizedCaseInsensitiveContains(searchText)
                    })
                    || comic.storyArcs.contains(where: {
                        $0.localizedCaseInsensitiveContains(searchText)
                    })
            }
        }

        // Multi-select groups: empty set = "All"; values OR within a group.
        if !filters.statuses.isEmpty {
            result = result.filter { filters.statuses.contains($0.status) }
        }
        if filters.readingList {
            result = result.filter { $0.isOnReadingList }
        }
        if !filters.publishers.isEmpty {
            result = result.filter {
                guard let publisher = $0.publisher else { return false }
                return filters.publishers.contains(publisher)
            }
        }
        if !filters.series.isEmpty {
            result = result.filter {
                guard let series = $0.series else { return false }
                return filters.series.contains(series)
            }
        }
        if !filters.years.isEmpty {
            result = result.filter {
                guard let year = $0.year else { return false }
                return filters.years.contains(year)
            }
        }
        if !filters.contentRatings.isEmpty {
            result = result.filter { filters.contentRatings.contains($0.contentRating) }
        }
        if !filters.fileTypes.isEmpty {
            result = result.filter { filters.fileTypes.contains($0.fileType) }
        }

        switch sort {
        case .title:
            result.sort {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
        case .dateAdded:
            result.sort { $0.dateAdded > $1.dateAdded }
        case .dateModified:
            result.sort { $0.dateModified > $1.dateModified }
        case .publisher:
            result.sort { ($0.publisher ?? "") < ($1.publisher ?? "") }
        case .year:
            result.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .rating:
            result.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .fileSize:
            result.sort { $0.fileSize > $1.fileSize }
        }

        // Rank search results: comics whose *visible* identity (title, series,
        // filename) matches the query float above comics that only matched
        // deep metadata (summary, creators, tags, story arcs). Both groups
        // keep the user's chosen sort order (filter is a stable partition).
        if !searchText.isEmpty {
            let primary = result.filter { isPrimaryMatch($0, searchText) }
            let secondary = result.filter { !isPrimaryMatch($0, searchText) }
            result = primary + secondary
        }

        return result
    }

    /// True when the query matches the fields a user actually sees on the
    /// card — the comic's own name — rather than buried metadata.
    private static func isPrimaryMatch(_ comic: Comic, _ searchText: String) -> Bool {
        comic.displayTitle.localizedCaseInsensitiveContains(searchText)
            || comic.title?.localizedCaseInsensitiveContains(searchText) == true
            || comic.series?.localizedCaseInsensitiveContains(searchText) == true
            || comic.fileName.localizedCaseInsensitiveContains(searchText)
    }

    /// Sort folders for the folder view, reusing the shared sort menu.
    /// Comic-specific options that don't map to a folder fall back to name:
    ///   Title → name A-Z · Date Added → created · Recently Modified → modified
    ///   File Size → book count (largest first) · others → name A-Z
    static func sortFolders(
        _ folders: [Folder],
        by sort: LibrarySortOption,
        count: (UUID) -> Int
    ) -> [Folder] {
        switch sort {
        case .dateAdded:
            return folders.sorted { $0.createdAt > $1.createdAt }
        case .dateModified:
            return folders.sorted { $0.dateModified > $1.dateModified }
        case .fileSize:
            return folders.sorted {
                let a = count($0.id)
                let b = count($1.id)
                if a != b { return a > b }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .title, .publisher, .year, .rating:
            return folders.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    /// Publisher → series → issues hierarchy for the publisher browse view.
    static func publisherGroups(from comics: [Comic]) -> [PublisherGroup] {
        let grouped = Dictionary(grouping: comics) { $0.publisher ?? "Unknown Publisher" }
        return
            grouped
            .map { (pub, pubComics) -> PublisherGroup in
                let seriesGrouped = Dictionary(grouping: pubComics) {
                    $0.series ?? "Unknown Series"
                }
                let seriesGroups =
                    seriesGrouped
                    .map { (ser, serComics) -> SeriesGroup in
                        SeriesGroup(
                            id: "\(pub)::\(ser)",
                            series: ser,
                            comics: serComics.sorted {
                                ($0.issueNumber ?? "").localizedStandardCompare(
                                    $1.issueNumber ?? "") == .orderedAscending
                            }
                        )
                    }
                    .sorted { $0.series.localizedStandardCompare($1.series) == .orderedAscending }
                return PublisherGroup(id: pub, publisher: pub, seriesGroups: seriesGroups)
            }
            .sorted { $0.publisher.localizedStandardCompare($1.publisher) == .orderedAscending }
    }
}

// MARK: - Cover Size (grid sizing)

/// Bounds for the user-adjustable cover size slider.
enum LibraryCoverSize {
    static let minimum: Double = 120
    static let maximum: Double = 260
    static let `default`: Double = 160
}
