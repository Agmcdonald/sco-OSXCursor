//
//  OrganizationLearner.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//

import Foundation
import GRDB
import os

// MARK: - Organization Learner
/// Service that learns naming patterns from imported books and applies them to future imports
class OrganizationLearner {
    static let shared = OrganizationLearner()
    
    private let database = DatabaseManager.shared
    private var learnedPatterns: [String: LearnedPattern] = [:] // Key: publisher name
    
    private init() {
        loadLearnedPatterns()
    }
    
    // MARK: - Pattern Learning
    
    /// Analyze a comic and learn its naming pattern
    /// - Parameters:
    ///   - comic: The imported comic
    ///   - originalFilename: The original filename before import
    /// - Returns: Suggested naming pattern if learned, nil otherwise
    func learnFromComic(_ comic: Comic, originalFilename: String) async -> String? {
        guard let publisher = comic.publisher else { return nil }
        
        // Extract pattern from filename
        let pattern = extractPattern(from: originalFilename, comic: comic)
        
        // Update learned pattern for this publisher
        await updateLearnedPattern(publisher: publisher, pattern: pattern, comic: comic)
        
        // Return pattern if confidence is high enough
        if let learnedPattern = learnedPatterns[publisher],
           learnedPattern.confidence >= AppSettings.load().confidenceThreshold {
            return learnedPattern.pattern
        }
        
        return nil
    }
    
    /// Extract naming pattern from filename
    private func extractPattern(from filename: String, comic: Comic) -> String {
        var pattern = filename
        
        // Replace actual values with pattern variables
        if let publisher = comic.publisher {
            pattern = pattern.replacingOccurrences(of: publisher, with: "{publisher}", options: .caseInsensitive)
        }
        
        if let series = comic.series {
            pattern = pattern.replacingOccurrences(of: series, with: "{series}", options: .caseInsensitive)
        }
        
        if let issueNumber = comic.issueNumber {
            pattern = pattern.replacingOccurrences(of: issueNumber, with: "{issue}", options: .caseInsensitive)
            // Also handle #001, #1, etc.
            pattern = pattern.replacingOccurrences(of: "#\(issueNumber)", with: "#{issue}", options: .caseInsensitive)
        }
        
        if let year = comic.year {
            pattern = pattern.replacingOccurrences(of: String(year), with: "{year}", options: .caseInsensitive)
            // Handle (2024) format
            pattern = pattern.replacingOccurrences(of: "(\(year))", with: "({year})", options: .caseInsensitive)
        }
        
        // Clean up any remaining specific values (keep structure)
        // Remove file extension
        pattern = pattern.replacingOccurrences(of: "\\.cbz$|\\.cbr$|\\.pdf$", with: "", options: .regularExpression)
        
        return pattern
    }
    
    /// Update learned pattern for a publisher
    private func updateLearnedPattern(publisher: String, pattern: String, comic: Comic) async {
        let normalizedPublisher = PublisherDetector.normalize(publisher) ?? publisher
        
        if var existingPattern = learnedPatterns[normalizedPublisher] {
            // Pattern exists - check if it matches
            if existingPattern.pattern == pattern {
                // Matches - increase confidence
                existingPattern.confidence = min(1.0, existingPattern.confidence + 0.1)
                existingPattern.matchCount += 1
            } else {
                // Different pattern - decrease confidence or replace if very different
                existingPattern.confidence = max(0.0, existingPattern.confidence - 0.05)
                
                // If confidence drops too low, replace with new pattern
                if existingPattern.confidence < 0.3 {
                    existingPattern.pattern = pattern
                    existingPattern.confidence = 0.5
                    existingPattern.matchCount = 1
                }
            }
            
            existingPattern.lastUpdated = Date()
            learnedPatterns[normalizedPublisher] = existingPattern
        } else {
            // New pattern - create with initial confidence
            let newPattern = LearnedPattern(
                publisher: normalizedPublisher,
                pattern: pattern,
                confidence: 0.5,
                matchCount: 1,
                lastUpdated: Date()
            )
            learnedPatterns[normalizedPublisher] = newPattern
        }
        
        // Save to database
        await saveLearnedPattern(learnedPatterns[normalizedPublisher]!)
    }
    
    // MARK: - Pattern Application
    
    /// Get suggested naming pattern for a comic based on learned patterns
    /// - Parameter comic: The comic to get pattern for
    /// - Returns: Suggested pattern if available and confidence is high enough, nil otherwise
    func getSuggestedPattern(for comic: Comic) -> String? {
        guard let publisher = comic.publisher else { return nil }
        let normalizedPublisher = PublisherDetector.normalize(publisher) ?? publisher
        
        guard let learnedPattern = learnedPatterns[normalizedPublisher] else { return nil }
        
        let settings = AppSettings.load()
        guard learnedPattern.confidence >= settings.confidenceThreshold else { return nil }
        
        return learnedPattern.pattern
    }
    
    // MARK: - Correction Learning
    
    /// Learn from a user correction
    /// - Parameters:
    ///   - comic: The corrected comic
    ///   - originalPublisher: Original publisher (before correction)
    ///   - correctedPublisher: Corrected publisher
    ///   - originalSeries: Original series (before correction)
    ///   - correctedSeries: Corrected series
    func learnFromCorrection(
        comic: Comic,
        originalPublisher: String?,
        correctedPublisher: String?,
        originalSeries: String?,
        correctedSeries: String?
    ) async {
        // Persist through the Stage 3 learning system: series renames become
        // aliases, associations are remembered, corrections are logged.
        await MainActor.run {
            SeriesKnowledge.shared.recordCorrection(
                originalSeries: originalSeries,
                correctedSeries: correctedSeries ?? comic.series,
                originalPublisher: originalPublisher,
                correctedPublisher: correctedPublisher ?? comic.publisher,
                filename: comic.fileName
            )
            SeriesKnowledge.shared.recordImport(
                series: correctedSeries ?? comic.series,
                publisher: correctedPublisher ?? comic.publisher,
                bookFormat: comic.bookFormat,
                countsAsImport: false  // correction, not a new import
            )
        }

        // If publisher was corrected, update publisher mappings confidence
        if let original = originalPublisher,
           let corrected = correctedPublisher,
           original != corrected {
            await updatePublisherMappingConfidence(original: original, corrected: corrected)
        }
        
        // If series was corrected, learn series-to-publisher association
        if let correctedPublisher = correctedPublisher ?? comic.publisher,
           let correctedSeries = correctedSeries ?? comic.series,
           let originalSeries = originalSeries,
           originalSeries != correctedSeries {
            await learnSeriesAssociation(series: correctedSeries, publisher: correctedPublisher)
        }
        
        // Adjust pattern confidence based on correction
        if let publisher = correctedPublisher ?? comic.publisher {
            await adjustPatternConfidence(publisher: publisher, confirmed: true)
        }
    }
    
    /// Update publisher mapping confidence when corrected
    private func updatePublisherMappingConfidence(original: String, corrected: String) async {
        // This would update the publisher_mappings table
        // For now, we'll log it - full implementation would update database
        AppLog.learning.debug("[OrganizationLearner] 📝 Learned correction: '\(original)' → '\(corrected)'")
    }
    
    /// Learn series-to-publisher association
    private func learnSeriesAssociation(series: String, publisher: String) async {
        // Store association for future use
        AppLog.learning.debug("[OrganizationLearner] 📝 Learned association: '\(series)' → '\(publisher)'")
    }
    
    /// Adjust pattern confidence based on correction
    private func adjustPatternConfidence(publisher: String, confirmed: Bool) async {
        let normalizedPublisher = PublisherDetector.normalize(publisher) ?? publisher
        
        if var pattern = learnedPatterns[normalizedPublisher] {
            if confirmed {
                // Correction confirms pattern - increase confidence
                pattern.confidence = min(1.0, pattern.confidence + 0.2)
            } else {
                // Correction contradicts pattern - decrease confidence
                pattern.confidence = max(0.0, pattern.confidence - 0.2)
            }
            
            pattern.lastUpdated = Date()
            learnedPatterns[normalizedPublisher] = pattern
            await saveLearnedPattern(pattern)
        }
    }
    
    // MARK: - Pattern Management
    
    /// Load learned patterns from database (learned_patterns table, v30).
    /// Fire-and-forget from init; the in-memory dictionary is authoritative
    /// once loaded, and imports arriving before the load merely start from an
    /// empty cache (the same behavior as before persistence existed).
    private func loadLearnedPatterns() {
        Task {
            do {
                let stored = try await database.fetchLearnedPatterns()
                guard !stored.isEmpty else { return }
                for pattern in stored {
                    // Don't clobber anything learned since launch
                    if learnedPatterns[pattern.publisher] == nil {
                        learnedPatterns[pattern.publisher] = pattern
                    }
                }
                AppLog.learning.info(
                    "[OrganizationLearner] 📥 Loaded \(stored.count) learned pattern(s) from database")
            } catch {
                AppLog.learning.error(
                    "[OrganizationLearner] ❌ Failed to load learned patterns: \(error.localizedDescription)")
            }
        }
    }

    /// Save learned pattern to database
    private func saveLearnedPattern(_ pattern: LearnedPattern) async {
        do {
            try await database.saveLearnedPattern(pattern)
            AppLog.learning.info("[OrganizationLearner] 💾 Saved pattern for '\(pattern.publisher)': \(pattern.pattern) (confidence: \(Int(pattern.confidence * 100))%)")
        } catch {
            AppLog.learning.error(
                "[OrganizationLearner] ❌ Failed to save pattern for '\(pattern.publisher)': \(error.localizedDescription)")
        }
    }
    
    /// Get all learned patterns
    func getAllLearnedPatterns() -> [LearnedPattern] {
        return Array(learnedPatterns.values).sorted { $0.publisher < $1.publisher }
    }
    
    /// Clear all learned patterns
    func clearAllPatterns() async {
        learnedPatterns.removeAll()
        do {
            try await database.deleteAllLearnedPatterns()
        } catch {
            AppLog.learning.error(
                "[OrganizationLearner] ❌ Failed to clear patterns from database: \(error.localizedDescription)")
        }
        AppLog.learning.debug("[OrganizationLearner] 🗑️ Cleared all learned patterns")
    }
    
    /// Get pattern count
    func getPatternCount() -> Int {
        return learnedPatterns.count
    }
    
    /// Get publishers with learned patterns
    func getPublishersWithPatterns() -> [String] {
        return Array(learnedPatterns.keys).sorted()
    }
}

// MARK: - Learned Pattern Model
struct LearnedPattern {
    let publisher: String
    var pattern: String
    var confidence: Double // 0.0 - 1.0
    var matchCount: Int
    var lastUpdated: Date
}

// MARK: - GRDB Persistence (learned_patterns table, migration v30)

extension LearnedPattern: FetchableRecord, PersistableRecord {
    static let databaseTableName = "learned_patterns"

    enum Columns {
        static let publisher = Column("publisher")
        static let pattern = Column("pattern")
        static let confidence = Column("confidence")
        static let matchCount = Column("match_count")
        static let lastUpdated = Column("last_updated")
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.publisher] = publisher
        container[Columns.pattern] = pattern
        container[Columns.confidence] = confidence
        container[Columns.matchCount] = matchCount
        container[Columns.lastUpdated] = lastUpdated
    }

    init(row: Row) throws {
        guard let publisher: String = row["publisher"],
            let pattern: String = row["pattern"],
            let confidence: Double = row["confidence"],
            let matchCount: Int = row["match_count"],
            let lastUpdated: Date = row["last_updated"]
        else {
            throw DatabaseError.fetchFailed
        }
        self.init(
            publisher: publisher,
            pattern: pattern,
            confidence: confidence,
            matchCount: matchCount,
            lastUpdated: lastUpdated
        )
    }
}




