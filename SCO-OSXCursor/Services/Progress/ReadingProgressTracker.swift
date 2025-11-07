//
//  ReadingProgressTracker.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation

// MARK: - Reading Progress Model
struct ReadingProgress: Codable {
    let comicID: UUID
    var currentPage: Int
    let totalPages: Int
    var lastReadDate: Date
    var status: Comic.Status
    
    /// Calculate progress percentage
    var progressPercentage: Double {
        guard totalPages > 0 else { return 0.0 }
        return Double(currentPage) / Double(totalPages)
    }
    
    /// Check if comic is completed
    var isCompleted: Bool {
        return currentPage >= totalPages - 1 || status == .completed
    }
}

// MARK: - Reading Progress Tracker
class ReadingProgressTracker {
    static let shared = ReadingProgressTracker()
    
    private let userDefaultsKey = "com.supercomicorganizer.readingProgress"
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Save Progress
    
    /// Save progress for a comic
    func saveProgress(_ progress: ReadingProgress) {
        var allProgress = loadAllProgress()
        allProgress[progress.comicID] = progress
        
        // Encode to JSON
        if let encoded = try? JSONEncoder().encode(allProgress) {
            defaults.set(encoded, forKey: userDefaultsKey)
            print("[ProgressTracker] ✅ Saved progress for comic \(progress.comicID): Page \(progress.currentPage + 1)/\(progress.totalPages)")
        } else {
            print("[ProgressTracker] ❌ Failed to encode progress")
        }
    }
    
    /// Quick update just the current page for a comic
    func updatePage(for comicID: UUID, currentPage: Int, totalPages: Int) {
        var progress: ReadingProgress
        
        if let existing = loadProgress(for: comicID) {
            progress = existing
            progress.currentPage = currentPage
            progress.lastReadDate = Date()
            
            // Auto-update status based on progress
            if currentPage >= totalPages - 1 {
                progress.status = .completed
            } else if currentPage > 0 {
                progress.status = .reading
            }
        } else {
            // Create new progress
            progress = ReadingProgress(
                comicID: comicID,
                currentPage: currentPage,
                totalPages: totalPages,
                lastReadDate: Date(),
                status: currentPage > 0 ? .reading : .unread
            )
        }
        
        saveProgress(progress)
    }
    
    // MARK: - Load Progress
    
    /// Load progress for a specific comic
    func loadProgress(for comicID: UUID) -> ReadingProgress? {
        let allProgress = loadAllProgress()
        return allProgress[comicID]
    }
    
    /// Load all saved progress
    func loadAllProgress() -> [UUID: ReadingProgress] {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([UUID: ReadingProgress].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    // MARK: - Delete Progress
    
    /// Delete progress for a specific comic
    func deleteProgress(for comicID: UUID) {
        var allProgress = loadAllProgress()
        allProgress.removeValue(forKey: comicID)
        
        if let encoded = try? JSONEncoder().encode(allProgress) {
            defaults.set(encoded, forKey: userDefaultsKey)
            print("[ProgressTracker] 🗑️ Deleted progress for comic \(comicID)")
        }
    }
    
    /// Clear all progress
    func clearAllProgress() {
        defaults.removeObject(forKey: userDefaultsKey)
        print("[ProgressTracker] 🗑️ Cleared all reading progress")
    }
    
    // MARK: - Statistics
    
    /// Get reading statistics
    func getStatistics() -> (totalComics: Int, reading: Int, completed: Int) {
        let allProgress = loadAllProgress()
        let reading = allProgress.values.filter { $0.status == .reading }.count
        let completed = allProgress.values.filter { $0.status == .completed }.count
        return (allProgress.count, reading, completed)
    }
}

