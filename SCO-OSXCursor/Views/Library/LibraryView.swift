//
//  LibraryView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

struct LibraryView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundColor(TextColors.tertiary)
            
            Text("Library View")
                .font(Typography.h1)
                .foregroundColor(TextColors.primary)
            
            Text("Comic collection will appear here")
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
            
            Text("Browse your collection of comics with beautiful cover art")
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
    LibraryView()
}

