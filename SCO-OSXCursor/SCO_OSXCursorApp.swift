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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)  // Force dark mode
        }
        .defaultSize(width: Layout.defaultWindowWidth, height: Layout.defaultWindowHeight)
    }
}
