//
//  SettingsView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "gear")
                .font(.system(size: 64))
                .foregroundColor(TextColors.tertiary)
            
            Text("Settings View")
                .font(Typography.h1)
                .foregroundColor(TextColors.primary)
            
            Text("Configure your preferences")
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
            
            Text("Customize organization rules, folder structures, and more")
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BackgroundColors.primary)
    }
}

#Preview {
    SettingsView()
}

