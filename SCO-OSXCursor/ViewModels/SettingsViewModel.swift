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
}
