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
        // Build marker — confirms which code the running binary was compiled from.
        // If this line is missing from the console, the device is running a STALE build.
        print("[App] 🏷️ Build: claude/optimization-pass — Stage 3 (learning system)")
    }

    @Environment(\.openWindow) private var openWindow
    @StateObject private var settingsViewModel = SettingsViewModel()

    var body: some Scene {
        WindowGroup("") {
            ContentView()
                .environmentObject(settingsViewModel)
                .preferredColorScheme(settingsViewModel.settings.theme.colorScheme)
        }
        .defaultSize(width: AppLayout.defaultWindowWidth, height: AppLayout.defaultWindowHeight)
        #if os(macOS)
            .commands {
                CommandGroup(replacing: .help) {
                    Button("Super Comic Organizer Help") {
                        openWindow(id: "user-manual")
                    }
                    .keyboardShortcut("?", modifiers: .command)
                }
            }
        #endif

        #if os(macOS)
            Window("User Manual", id: "user-manual") {
                UserManualView()
                    .environmentObject(settingsViewModel)
            }
            .defaultSize(width: 800, height: 900)
            .handlesExternalEvents(matching: Set(arrayLiteral: "user-manual"))
        #endif
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
