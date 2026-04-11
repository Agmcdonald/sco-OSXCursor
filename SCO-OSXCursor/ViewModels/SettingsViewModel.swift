//
//  SettingsViewModel.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Settings ViewModel
@MainActor
class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load settings from UserDefaults
        self.settings = AppSettings.load()

        // Auto-save settings when they change (debounced)
        $settings
            .dropFirst()  // Skip initial value
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] newSettings in
                self?.saveSettings()
            }
            .store(in: &cancellables)
    }

    // MARK: - Settings Properties (for direct binding)

    var folderStructure: Binding<AppSettings.FolderStructure> {
        Binding(
            get: { self.settings.folderStructure },
            set: { self.settings.folderStructure = $0 }
        )
    }

    var namingPattern: Binding<String> {
        Binding(
            get: { self.settings.namingPattern },
            set: { self.settings.namingPattern = $0 }
        )
    }

    var rootLibraryPath: Binding<URL?> {
        Binding(
            get: { self.settings.rootLibraryPath },
            set: { self.settings.rootLibraryPath = $0 }
        )
    }

    var autoSortIntoLibrary: Binding<Bool> {
        Binding(
            get: { self.settings.autoSortIntoLibrary },
            set: { self.settings.autoSortIntoLibrary = $0 }
        )
    }

    var autoOrganize: Binding<Bool> {
        Binding(
            get: { self.settings.autoOrganize },
            set: { self.settings.autoOrganize = $0 }
        )
    }

    var confidenceThreshold: Binding<Double> {
        Binding(
            get: { self.settings.confidenceThreshold },
            set: { self.settings.confidenceThreshold = $0 }
        )
    }

    var theme: Binding<AppSettings.Theme> {
        Binding(
            get: { self.settings.theme },
            set: { self.settings.theme = $0 }
        )
    }

    var showDetailPanel: Binding<Bool> {
        Binding(
            get: { self.settings.showDetailPanel },
            set: { self.settings.showDetailPanel = $0 }
        )
    }

    var gridColumns: Binding<Int> {
        Binding(
            get: { self.settings.gridColumns },
            set: { self.settings.gridColumns = $0 }
        )
    }

    var cardSize: Binding<AppSettings.CardSize> {
        Binding(
            get: { self.settings.cardSize },
            set: { self.settings.cardSize = $0 }
        )
    }

    var enableLearning: Binding<Bool> {
        Binding(
            get: { self.settings.enableLearning },
            set: { self.settings.enableLearning = $0 }
        )
    }

    // MARK: - Actions

    /// Save settings to UserDefaults
    private func saveSettings() {
        settings.save()
        print("[SettingsViewModel] 💾 Settings saved")
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        AppSettings.reset()
        self.settings = AppSettings.load()
        print("[SettingsViewModel] 🔄 Settings reset to defaults")
    }

    /// Validate naming pattern
    func validateNamingPattern(_ pattern: String) -> Bool {
        return settings.isValidNamingPattern(pattern)
    }

    /// Preview naming pattern with sample comic
    func previewNamingPattern() -> String {
        let sampleComic = Comic.sample(
            title: "Batman",
            publisher: "DC Comics",
            issueNumber: "001",
            year: 2024
        )
        return settings.previewNamingPattern(with: sampleComic)
    }

    /// Get example path for folder structure
    func examplePath(for structure: AppSettings.FolderStructure) -> String {
        return structure.examplePath
    }

    // MARK: - Home Library Management

    /// Persists the chosen folder: stores the path AND creates a security-scoped
    /// bookmark so the sandbox can reach the folder across relaunches.
    func setHomeLibraryFolder(_ url: URL) {
        settings.rootLibraryPath = url
        #if os(macOS)
        settings.homeLibraryBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        settings.homeLibraryBookmark = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        saveSettings()
        print("[SettingsViewModel] 📁 Home library set: \(url.path)")
    }

    /// Resolves the stored bookmark → URL, refreshing it if stale.
    /// Returns nil if no bookmark is stored or the volume is not mounted.
    func resolveHomeLibraryURL() -> URL? {
        // Quick path: bookmark available
        if let bookmarkData = settings.homeLibraryBookmark {
            var isStale = false
            #if os(macOS)
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    // Refresh stale bookmark
                    settings.homeLibraryBookmark = try? resolved.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    saveSettings()
                }
                return resolved
            }
            #else
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved
            }
            #endif
        }
        // Fallback: use raw URL if set
        return settings.rootLibraryPath
    }

    /// Status of the home library folder.
    enum HomeLibraryStatus {
        case notSet
        case accessible
        case notFound        // Path doesn't exist
        case volumeNotMounted // Path exists in settings but volume not present
        case notWritable
    }

    /// Validates the home library folder and returns its current status.
    func homeLibraryStatus() -> HomeLibraryStatus {
        guard let url = resolveHomeLibraryURL() else { return .notSet }
        let fm = FileManager.default
        // Check the volume is mounted
        var isReachable = false
        do {
            isReachable = try url.checkResourceIsReachable()
        } catch {
            // The error may be "no such volume" on external drives
            let nsErr = error as NSError
            if nsErr.code == NSFileReadNoSuchFileError || nsErr.code == NSFileNoSuchFileError {
                // Distinguish: if the root path contains the library root but drive is gone
                return fm.fileExists(atPath: "/Volumes") ? .volumeNotMounted : .notFound
            }
            return .notFound
        }
        guard isReachable else { return .notFound }
        guard fm.isWritableFile(atPath: url.path) else { return .notWritable }
        return .accessible
    }

    /// Returns the raw stored `rootLibraryPath` URL **without** any bookmark
    /// resolution or reachability check.  Used by `RelocateLibraryView` as the
    /// "old root" when the bookmark is stale and `resolveHomeLibraryURL()` returns nil.
    func storedHomeLibraryURL() -> URL? {
        settings.rootLibraryPath
    }
}
