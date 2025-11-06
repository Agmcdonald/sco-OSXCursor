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
    
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid
    @State private var selectedComic: Comic?
    
    enum ViewMode {
        case grid, list
    }
    
    var filteredComics: [Comic] {
        if searchText.isEmpty {
            return comics
        }
        return comics.filter { comic in
            comic.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            comic.publisher?.localizedCaseInsensitiveContains(searchText) == true ||
            comic.series?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
            
            Divider()
                .background(BorderColors.subtle)
            
            // Content
            if viewMode == .grid {
                gridView
            } else {
                listView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BackgroundColors.primary)
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Library")
                        .font(Typography.h1)
                        .foregroundColor(TextColors.primary)
                    
                    Text("Browse your collection of \(filteredComics.count) comics")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                }
                
                Spacer()
                
                // View mode toggle
                HStack(spacing: Spacing.sm) {
                    Button(action: { viewMode = .grid }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 16))
                            .foregroundColor(viewMode == .grid ? AccentColors.primary : TextColors.secondary)
                            .frame(width: 32, height: 32)
                            .background(viewMode == .grid ? AccentColors.primary.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { viewMode = .list }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16))
                            .foregroundColor(viewMode == .list ? AccentColors.primary : TextColors.secondary)
                            .frame(width: 32, height: 32)
                            .background(viewMode == .list ? AccentColors.primary.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Search bar
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(TextColors.tertiary)
                
                TextField("Search comics, series, publisher...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(TextColors.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.md)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(Spacing.xl)
    }
    
    // MARK: - Grid View
    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 160, maximum: 200), spacing: Spacing.xl)
                ],
                spacing: Spacing.xxl
            ) {
                ForEach(filteredComics) { comic in
                    ComicCardView(comic: comic)
                        .onTapGesture {
                            selectedComic = comic
                        }
                }
            }
            .padding(Spacing.xl)
        }
    }
    
    // MARK: - List View
    private var listView: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                ForEach(filteredComics) { comic in
                    ComicRowView(comic: comic)
                        .onTapGesture {
                            selectedComic = comic
                        }
                }
            }
            .padding(Spacing.xl)
        }
    }
}

// MARK: - Comic Row View
struct ComicRowView: View {
    let comic: Comic
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: Spacing.lg) {
            // Placeholder cover
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [BackgroundColors.secondary, BackgroundColors.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Image(systemName: comic.fileType.icon)
                    .font(.system(size: 24))
                    .foregroundColor(TextColors.tertiary)
            }
            .frame(width: 60, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
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
        .background(isHovered ? BackgroundColors.secondary : BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? BorderColors.regular : BorderColors.subtle, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    LibraryView()
}

