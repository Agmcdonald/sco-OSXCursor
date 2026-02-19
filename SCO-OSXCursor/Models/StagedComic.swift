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
    var publisher: String?
    var format: String?  // "Digital", "Scan", etc.

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

        // Calculate initial confidence
        if !self.series.isEmpty && self.issueNumber != nil && self.year != nil
            && self.publisher != nil
        {
            self.confidence = .high
            self.status = .ready
        } else if !self.series.isEmpty && self.issueNumber != nil {
            self.confidence = .medium
        } else {
            self.confidence = .low
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

        if let vol = volume {
            parts.append("V\(vol)")
        }

        if let issue = issueNumber, !issue.isEmpty {
            parts.append("#\(issue)")
        }

        if let y = year {
            parts.append("(\(y))")
        }

        // Preserve original extension
        let ext = originalURL.pathExtension
        return parts.joined(separator: " ") + ".\(ext)"
    }
}
