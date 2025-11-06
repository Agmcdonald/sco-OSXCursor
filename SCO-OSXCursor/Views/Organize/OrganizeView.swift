//
//  OrganizeView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

struct OrganizeView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 64))
                .foregroundColor(TextColors.tertiary)
            
            Text("Organize View")
                .font(Typography.h1)
                .foregroundColor(TextColors.primary)
            
            Text("Drag and drop comics to organize")
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
            
            Text("Smart file organization with learning capabilities")
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
    OrganizeView()
}

