//
//  LibraryView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

struct LibraryView: View {
    // Sample comics for demonstration
    let comics = Comic.samples
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Library")
                    .font(Typography.h1)
                    .foregroundColor(TextColors.primary)
                
                Text("Browse your collection of \(comics.count) comics")
                    .font(Typography.body)
                    .foregroundColor(TextColors.secondary)
            }
            .padding(Spacing.xl)
            
            Divider()
                .background(BorderColors.subtle)
            
            // Comics list (simple list view for now)
            ScrollView {
                VStack(spacing: Spacing.md) {
                    ForEach(comics) { comic in
                        ComicRowView(comic: comic)
                    }
                }
                .padding(Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BackgroundColors.primary)
    }
}

// MARK: - Comic Row View
struct ComicRowView: View {
    let comic: Comic
    
    var body: some View {
        HStack(spacing: Spacing.lg) {
            // Placeholder cover
            RoundedRectangle(cornerRadius: 8)
                .fill(BackgroundColors.elevated)
                .frame(width: 60, height: 90)
                .overlay(
                    Image(systemName: comic.fileType.icon)
                        .font(.system(size: 24))
                        .foregroundColor(TextColors.tertiary)
                )
            
            // Comic info
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(comic.displayTitle)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(1)
                
                if let publisher = comic.publisher {
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(comic.publisherColor)
                            .frame(width: 8, height: 8)
                        
                        Text(publisher)
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.secondary)
                    }
                }
                
                HStack(spacing: Spacing.md) {
                    // Status badge
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: comic.status.icon)
                            .font(.system(size: 10))
                        Text(comic.status.rawValue)
                            .font(Typography.label)
                    }
                    .foregroundColor(comic.status.color)
                    
                    // Progress
                    if comic.totalPages > 0 {
                        Text("\(comic.currentPage)/\(comic.totalPages) pages")
                            .font(Typography.label)
                            .foregroundColor(TextColors.tertiary)
                    }
                    
                    // File size
                    Text(comic.fileSizeFormatted)
                        .font(Typography.label)
                        .foregroundColor(TextColors.tertiary)
                }
            }
            
            Spacer()
            
            // Actions
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(TextColors.tertiary)
        }
        .padding(Spacing.lg)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    LibraryView()
}

