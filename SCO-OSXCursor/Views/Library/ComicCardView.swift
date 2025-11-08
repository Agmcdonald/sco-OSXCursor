//
//  ComicCardView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

@MainActor
struct ComicCardView: View {
    let comic: Comic
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Cover image
            coverView
            
            // Comic info
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Title
                Text(comic.displayName)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Issue number and year
                if comic.issueNumber != nil || comic.year != nil {
                    HStack(spacing: Spacing.xs) {
                        if let issueNumber = comic.issueNumber {
                            Text("Issue #\(issueNumber)")
                                .font(Typography.caption)
                                .foregroundColor(TextColors.secondary)
                        }
                        
                        if let year = comic.year {
                            Text("(\(String(year)))")
                                .font(Typography.caption)
                                .foregroundColor(TextColors.tertiary)
                        }
                    }
                }
                
                // Publisher badge
                if let publisher = comic.publisher {
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(comic.publisherColor)
                            .frame(width: 6, height: 6)
                        
                        Text(publisher)
                            .font(Typography.label)
                            .foregroundColor(TextColors.secondary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(BackgroundColors.elevated)
                    .clipShape(Capsule())
                }
                
                // Progress indicator
                if comic.isInProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comic.progressPercentage)
                            .font(Typography.label)
                            .foregroundColor(TextColors.tertiary)
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(BackgroundColors.elevated)
                                    .frame(height: 4)
                                
                                // Progress
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(comic.status.color)
                                    .frame(width: geometry.size.width * comic.progress, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? AccentColors.primary : BorderColors.subtle, lineWidth: isHovered ? 2 : 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    // MARK: - Cover View
    private var coverView: some View {
        // Force portrait aspect ratio container
        GeometryReader { geometry in
            ZStack {
                // Cover image or placeholder
                if let coverData = comic.coverImageData {
                    #if os(macOS)
                    if let nsImage = NSImage(data: coverData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        placeholderCover
                    }
                    #else
                    if let uiImage = UIImage(data: coverData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        placeholderCover
                    }
                    #endif
                } else {
                    placeholderCover
                }
                
                // Status badge overlay
                VStack {
                    HStack {
                        Spacer()
                        
                        // Status indicator
                        Circle()
                            .fill(comic.status.color)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(BackgroundColors.elevated, lineWidth: 2)
                            )
                            .padding(Spacing.sm)
                    }
                    
                    Spacer()
                    
                    // Favorite indicator
                    if comic.isFavorite {
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AccentColors.warning)
                                .padding(Spacing.xs)
                                .background(BackgroundColors.elevated.opacity(0.9))
                                .clipShape(Circle())
                                .padding(Spacing.sm)
                            
                            Spacer()
                        }
                    }
                }
            }
            .clipped() // Clip content to geometry bounds
        }
        .aspectRatio(2/3, contentMode: .fit) // Standard comic book portrait aspect ratio
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Placeholder Cover
    private var placeholderCover: some View {
        ZStack {
            // Gradient background
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [BackgroundColors.secondary, BackgroundColors.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Icon
            VStack(spacing: Spacing.sm) {
                Image(systemName: "book.closed")
                    .font(.system(size: 40))
                    .foregroundColor(TextColors.tertiary)
                
                Text(comic.fileType.rawValue.uppercased())
                    .font(Typography.tiny)
                    .foregroundColor(TextColors.tertiary)
            }
        }
    }
}

#Preview("Single Card") {
    ComicCardView(comic: Comic.sample())
        .frame(width: 200)
        .padding()
        .background(BackgroundColors.primary)
}

#Preview("Grid") {
    ScrollView {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 160, maximum: 200), spacing: Spacing.xl)
        ], spacing: Spacing.xxl) {
            ForEach(Comic.samples) { comic in
                ComicCardView(comic: comic)
            }
        }
        .padding(Spacing.xl)
    }
    .background(BackgroundColors.primary)
}

