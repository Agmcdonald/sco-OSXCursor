//
//  SettingsView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject private var settings = ReaderSettings.shared
    
    var body: some View {
        Form {
            Section("Reader") {
                Picker("Page Transition", selection: $settings.pageTransition) {
                    ForEach(
                        PageTransition.allCases.filter { $0.isAvailableOnCurrentPlatform },
                        id: \.self
                    ) { transition in
                        Label(transition.rawValue, systemImage: transition.icon)
                            .tag(transition)
                    }
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #endif
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}

#Preview {
    SettingsView()
}

