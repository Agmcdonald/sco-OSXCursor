//
//  StagedComic.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 2/15/26.
//

import Foundation
import SwiftUI

/// Represents a comic file in the "Organize" staging area.
/// Not yet a full `Comic` model in the database.
struct StagedComic: Identifiable, Equatable {
    let id: UUID
    let originalURL: URL

    // Status
    enum Status: String, CaseIterable {
        case pending = "Pending"
        case ready = "Ready"  // Metadata complete
        case error = "Error"
        case imported = "Imported"
    }
    var status: Status = .pending

    // Parse Confidence
    enum Confidence: String, CaseIterable, Comparable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        static func < (lhs: Confidence, rhs: Confidence) -> Bool {
            let order: [Confidence] = [.low, .medium, .high]
            guard let l = order.firstIndex(of: lhs), let r = order.firstIndex(of: rhs) else {
                return false
            }
            return l < r
        }

        var color: Color {
            switch self {
            case .low: return .red
            case .medium: return .orange
            case .high: return .green
            }
        }
    }
    var confidence: Confidence = .low

    // Editable Metadata
    var series: String
    var issueNumber: String?
    var volume: Int?
    var year: Int?
    /// Issue / one-shot / collected volume — auto-detected, user-editable
    var bookFormat: Comic.BookFormat = .issue
    var publisher: String?
    var format: String?  // "Digital", "Scan", etc.
    var title: String?
    var writer: String?
    var artist: String?
    var coverArtist: String?
    var colorist: String?
    var inker: String?
    var editor: String?
    var summary: String?

    // Original File Info
    let originalFileName: String
    let fileSize: Int64

    init(url: URL) {
        self.id = UUID()
        self.originalURL = url
        self.originalFileName = url.lastPathComponent
        self.fileSize =
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        // Initial parse
        let metadata = MetadataParser.parseFromFilename(url.lastPathComponent)
        self.series = metadata.series ?? ""
        self.issueNumber = metadata.number
        self.volume = metadata.volume
        self.year = metadata.year
        self.publisher = metadata.publisher
        self.format = metadata.format
        self.title = metadata.title
        self.writer = metadata.writer
        self.artist = metadata.penciller
        self.coverArtist = metadata.coverArtist
        self.summary = metadata.summary

        // Detect what kind of book this is from the parsed metadata
        self.bookFormat = Comic.BookFormat.detect(
            issueNumber: self.issueNumber, volume: self.volume)

        // Calculate initial confidence
        reevaluate(userEdited: false)
    }

    /// Recompute confidence and Ready status using format-aware rules.
    /// - Issues need series + issue number (one-shots and volumes don't have one).
    /// - One-shots need series + year.
    /// - Volumes need series + volume number.
    /// Auto-parsed books only become Ready at HIGH confidence; user-edited
    /// books become Ready once the core fields are filled.
    mutating func reevaluate(userEdited: Bool) {
        let hasSeries = !series.isEmpty
        let core: Bool  // minimum fields for this format
        let full: Bool  // high confidence

        switch bookFormat {
        case .issue:
            core = hasSeries && (issueNumber?.isEmpty == false)
            full = core && year != nil && publisher != nil
        case .oneShot:
            core = hasSeries && year != nil
            full = core && publisher != nil
        case .volume:
            core = hasSeries && volume != nil
            full = core && year != nil && publisher != nil
        }

        confidence = full ? .high : (core ? .medium : .low)

        if full || (userEdited && core) {
            status = .ready
        } else if !core {
            status = .pending
        }
    }

    // Computed Clean Filename (preview of rename)
    var proposedFileName: String {
        var parts: [String] = []

        if !series.isEmpty {
            parts.append(series)
        } else {
            return originalFileName  // Fallback if no series
        }

        switch bookFormat {
        case .issue:
            if let vol = volume {
                parts.append("V\(vol)")
            }
            if let issue = issueNumber, !issue.isEmpty {
                parts.append("#\(issue)")
            }

        case .oneShot:
            // Self-contained book: "Series (Year)"
            break

        case .volume:
            if let vol = volume {
                parts.append(String(format: "Vol. %02d", vol))
            }
        }

        if let y = year {
            parts.append("(\(y))")
        }

        // Preserve original extension
        let ext = originalURL.pathExtension
        return parts.joined(separator: " ") + ".\(ext)"
    }
}
