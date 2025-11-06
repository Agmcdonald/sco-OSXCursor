//
//  AppSettings.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import Foundation

// MARK: - App Settings
struct AppSettings: Codable {
    // MARK: - Organization Settings
    var folderStructure: FolderStructure
    var namingPattern: String
    var rootLibraryPath: URL?
    var autoOrganize: Bool
    var confidenceThreshold: Double // 0.0 - 1.0
    
    // MARK: - Reading Settings
    var readingMode: ReadingMode
    var pageTransition: PageTransition
    var enableDoublePage: Bool
    var fitToScreen: Bool
    
    // MARK: - UI Settings
    var theme: Theme
    var showDetailPanel: Bool
    var gridColumns: Int
    var cardSize: CardSize
    
    // MARK: - Advanced Settings
    var enableLearning: Bool
    var enableMetadataLookup: Bool
    var apiKey: String?
    var maxCacheSize: Int64 // in bytes
    
    // MARK: - Default Initializer
    init(
        folderStructure: FolderStructure = .publisherSeriesIssue,
        namingPattern: String = "{publisher}/{series}/#{issue} ({year})",
        rootLibraryPath: URL? = nil,
        autoOrganize: Bool = false,
        confidenceThreshold: Double = 0.7,
        readingMode: ReadingMode = .fitToWidth,
        pageTransition: PageTransition = .slide,
        enableDoublePage: Bool = true,
        fitToScreen: Bool = true,
        theme: Theme = .dark,
        showDetailPanel: Bool = true,
        gridColumns: Int = 4,
        cardSize: CardSize = .medium,
        enableLearning: Bool = true,
        enableMetadataLookup: Bool = false,
        apiKey: String? = nil,
        maxCacheSize: Int64 = 1_000_000_000 // 1 GB
    ) {
        self.folderStructure = folderStructure
        self.namingPattern = namingPattern
        self.rootLibraryPath = rootLibraryPath
        self.autoOrganize = autoOrganize
        self.confidenceThreshold = confidenceThreshold
        self.readingMode = readingMode
        self.pageTransition = pageTransition
        self.enableDoublePage = enableDoublePage
        self.fitToScreen = fitToScreen
        self.theme = theme
        self.showDetailPanel = showDetailPanel
        self.gridColumns = gridColumns
        self.cardSize = cardSize
        self.enableLearning = enableLearning
        self.enableMetadataLookup = enableMetadataLookup
        self.apiKey = apiKey
        self.maxCacheSize = maxCacheSize
    }
}

// MARK: - Folder Structure Enum
extension AppSettings {
    enum FolderStructure: String, Codable, CaseIterable {
        case publisherSeriesIssue = "Publisher/Series/Issue"
        case seriesIssue = "Series/Issue"
        case publisherSeries = "Publisher/Series"
        case flat = "Flat (All in one folder)"
        case yearPublisherSeries = "Year/Publisher/Series"
        case custom = "Custom"
        
        var displayName: String {
            rawValue
        }
        
        var description: String {
            switch self {
            case .publisherSeriesIssue:
                return "Organizes by Publisher → Series → Individual Issues"
            case .seriesIssue:
                return "Organizes by Series → Individual Issues"
            case .publisherSeries:
                return "Organizes by Publisher → Series (issues together)"
            case .flat:
                return "All comics in a single folder"
            case .yearPublisherSeries:
                return "Organizes by Year → Publisher → Series"
            case .custom:
                return "Use custom naming pattern"
            }
        }
        
        var examplePath: String {
            switch self {
            case .publisherSeriesIssue:
                return "DC Comics/Batman/Batman #001 (2024).cbz"
            case .seriesIssue:
                return "Batman/Batman #001 (2024).cbz"
            case .publisherSeries:
                return "DC Comics/Batman/Batman #001 (2024).cbz"
            case .flat:
                return "Batman #001 (2024).cbz"
            case .yearPublisherSeries:
                return "2024/DC Comics/Batman/Batman #001 (2024).cbz"
            case .custom:
                return "Custom/Path/Batman #001.cbz"
            }
        }
    }
}

// MARK: - Reading Mode Enum
extension AppSettings {
    enum ReadingMode: String, Codable, CaseIterable {
        case fitToWidth = "Fit to Width"
        case fitToHeight = "Fit to Height"
        case fitToScreen = "Fit to Screen"
        case original = "Original Size"
        
        var displayName: String {
            rawValue
        }
    }
}

// MARK: - Page Transition Enum
extension AppSettings {
    enum PageTransition: String, Codable, CaseIterable {
        case slide = "Slide"
        case fade = "Fade"
        case curl = "Page Curl"
        case instant = "Instant"
        
        var displayName: String {
            rawValue
        }
    }
}

// MARK: - Theme Enum
extension AppSettings {
    enum Theme: String, Codable, CaseIterable {
        case dark = "Dark"
        case light = "Light"
        case auto = "System"
        
        var displayName: String {
            rawValue
        }
    }
}

// MARK: - Card Size Enum
extension AppSettings {
    enum CardSize: String, Codable, CaseIterable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
        
        var displayName: String {
            rawValue
        }
        
        var width: CGFloat {
            switch self {
            case .small: return 120
            case .medium: return 160
            case .large: return 200
            }
        }
        
        var height: CGFloat {
            width * 1.5 // 2:3 aspect ratio
        }
    }
}

// MARK: - UserDefaults Extension
extension AppSettings {
    private static let settingsKey = "AppSettings"
    
    /// Save settings to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: AppSettings.settingsKey)
        }
    }
    
    /// Load settings from UserDefaults
    static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return decoded
        }
        return AppSettings() // Return default settings if none saved
    }
    
    /// Reset settings to defaults
    static func reset() {
        UserDefaults.standard.removeObject(forKey: settingsKey)
    }
}

// MARK: - Naming Pattern Variables
extension AppSettings {
    /// Available variables for naming patterns
    static let namingPatternVariables: [String: String] = [
        "{publisher}": "Publisher name (e.g., DC Comics)",
        "{series}": "Series name (e.g., Batman)",
        "{issue}": "Issue number (e.g., 001)",
        "{year}": "Publication year (e.g., 2024)",
        "{title}": "Full comic title",
        "{volume}": "Volume number",
        "{writer}": "Writer name",
        "{artist}": "Artist name"
    ]
    
    /// Validate naming pattern
    func isValidNamingPattern(_ pattern: String) -> Bool {
        // Check if pattern contains at least one valid variable
        return AppSettings.namingPatternVariables.keys.contains { pattern.contains($0) }
    }
    
    /// Preview naming pattern with sample data
    func previewNamingPattern(with comic: Comic) -> String {
        var result = namingPattern
        
        result = result.replacingOccurrences(of: "{publisher}", with: comic.publisher ?? "Unknown")
        result = result.replacingOccurrences(of: "{series}", with: comic.series ?? "Unknown")
        result = result.replacingOccurrences(of: "{issue}", with: comic.issueNumber ?? "000")
        result = result.replacingOccurrences(of: "{year}", with: String(comic.year ?? 0))
        result = result.replacingOccurrences(of: "{title}", with: comic.title ?? "Unknown")
        result = result.replacingOccurrences(of: "{volume}", with: String(comic.volume ?? 1))
        result = result.replacingOccurrences(of: "{writer}", with: comic.writer ?? "Unknown")
        result = result.replacingOccurrences(of: "{artist}", with: comic.artist ?? "Unknown")
        
        return result
    }
}

