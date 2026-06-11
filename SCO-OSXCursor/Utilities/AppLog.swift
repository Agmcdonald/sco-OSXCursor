//
//  AppLog.swift
//  SCO-OSXCursor
//
//  Centralized os.Logger wrappers (Stage 4: replace print() with os.Logger).
//  Usage: AppLog.library.debug("Loaded \(count) comics")
//
//  AppLogger takes a plain String so any Swift interpolation works (os.Logger
//  itself restricts interpolation types — e.g. \(error) wouldn't compile).
//  Messages are logged with .public privacy: this is a local, personal-library
//  app and these messages replace what print() already wrote to the console.
//
//  Levels: .debug for development tracing (not persisted), .info for
//  notable events, .error for failures (persisted).
//  View logs in Console.app filtered by the subsystem, or via:
//    log stream --predicate 'subsystem CONTAINS "SuperComicOrganizer"'
//

import Foundation
import os

struct AppLogger {
    private let logger: Logger

    init(category: String) {
        let subsystem = Bundle.main.bundleIdentifier ?? "SuperComicOrganizer"
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

enum AppLog {
    /// SQLite / persistence (DatabaseManager)
    static let database = AppLogger(category: "Database")
    /// Library browsing & management (LibraryView*, LibraryViewModel)
    static let library = AppLogger(category: "Library")
    /// Reading experience (reader views, ReaderViewModel, format readers)
    static let reader = AppLogger(category: "Reader")
    /// Import / staging / organization (OrganizeViewModel)
    static let organize = AppLogger(category: "Organize")
    /// Filename parsing & metadata (MetadataParser, ComicInfo)
    static let metadata = AppLogger(category: "Metadata")
    /// Series knowledge & learning (OrganizationLearner, SeriesKnowledge)
    static let learning = AppLogger(category: "Learning")
    /// File operations (LibraryFileService, LibraryRelocator, progress files)
    static let files = AppLogger(category: "Files")
    /// App lifecycle, settings, everything else
    static let app = AppLogger(category: "App")
}
