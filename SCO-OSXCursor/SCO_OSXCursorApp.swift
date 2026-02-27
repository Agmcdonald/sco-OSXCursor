//
//  SCO_OSXCursorApp.swift
//  SCO-OSXCursor
//
//  Created by Andrew McDonald on 11/5/25.
//

import SwiftUI

@main
@MainActor
struct SCO_OSXCursorApp: App {

    init() {
        // Initialize database on app startup
        _ = DatabaseManager.shared
        print("[App] ✅ App initialization complete")
    }

    @StateObject private var settingsViewModel = SettingsViewModel()

    var body: some Scene {
        WindowGroup("") {
            ContentView()
                .environmentObject(settingsViewModel)
                .preferredColorScheme(settingsViewModel.settings.theme.colorScheme)
        }
        .defaultSize(width: AppLayout.defaultWindowWidth, height: AppLayout.defaultWindowHeight)
    }
}

extension AppSettings.Theme {
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }
}
