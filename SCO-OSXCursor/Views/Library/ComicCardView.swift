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

            // Comic info — FIXED HEIGHT so every card in a row is the same
            // height and covers sit in level rows regardless of title length
            // (grid alignment request, Andrew, June 9). Title always reserves
            // two lines; one metadata line below; progress moved onto the
            // cover itself as a thin bottom bar.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Title — reserved 2-line slot, top-aligned
                Text(comic.displayName)
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: 44, alignment: .topLeading)

                // One metadata line: issue/year • publisher (reserved even
                // when empty so card heights never drift)
                HStack(spacing: Spacing.xs) {
                    if let issueNumber = comic.issueNumber {
                        Text("Issue #\(issueNumber)")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }

                    if let year = comic.year {
                        Text("(\(String(year)))")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }

                    if let publisher = comic.publisher {
                        if comic.issueNumber != nil || comic.year != nil {
                            Text("•")
                                .font(Typography.caption)
                                .foregroundColor(TextColors.tertiary)
                        }
                        Circle()
                            .fill(comic.publisherColor)
                            .frame(width: 6, height: 6)
                        Text(publisher)
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .frame(height: 16)
            }
        }
        .padding(Spacing.md)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // CRITICAL: .clipped()/.clipShape only clip DRAWING — the cover's
        // aspect-fill overflow stays tappable outside the card, so taps on a
        // card could open the NEIGHBORING comic (whichever rendered later).
        // contentShape bounds hit-testing to the visible card.
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHovered ? AccentColors.primary : BorderColors.subtle,
                    lineWidth: isHovered ? 2 : 1)
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
                // Cover image or placeholder — decoded once via the cover
                // cache (raw NSImage/UIImage(data:) re-decoded the full bytes
                // on every grid render)
                if let coverData = comic.coverImageData,
                    let cover = PageImageCache.shared.coverImage(
                        from: coverData, cacheKey: comic.id.uuidString)
                {
                    #if os(macOS)
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    #else
                        Image(uiImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    #endif
                } else {
                    placeholderCover
                }

                // Status badge overlay
                VStack {
                    HStack {
                        // ⚠ Attention badge (file missing / move failed)
                        if comic.needsAttention {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AccentColors.warning)
                                .padding(5)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .padding(Spacing.sm)
                        }

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

                    // Bottom-left badges (reading list + favourite)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Spacer()
                            // Reading list badge
                            if comic.isOnReadingList {
                                Image("ReadingListIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .padding(4)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .padding(Spacing.sm)
                            }
                        }

                        Spacer()

                        // Favourite indicator (keeps its original position)
                        VStack(alignment: .trailing) {
                            Spacer()
                            if comic.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(AccentColors.warning)
                                    .padding(Spacing.xs)
                                    .background(BackgroundColors.elevated.opacity(0.9))
                                    .clipShape(Circle())
                                    .padding(Spacing.sm)
                            }
                        }
                    }  // HStack bottom badges
                }  // VStack overlay

                // Reading progress — thin bar along the cover's bottom edge
                // (replaces the in-card progress row so card heights stay
                // uniform for level grid rows)
                if comic.isInProgress {
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black.opacity(0.35))
                                .frame(height: 4)

                            Rectangle()
                                .fill(comic.status.color)
                                .frame(
                                    width: geometry.size.width * comic.progress, height: 4)
                        }
                    }
                }
            }  // ZStack
            .clipped()  // Clip content to geometry bounds
        }
        .aspectRatio(2 / 3, contentMode: .fit)  // Standard comic book portrait aspect ratio
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
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 160, maximum: 200), spacing: Spacing.xl)
            ], spacing: Spacing.xxl
        ) {
            ForEach(Comic.samples) { comic in
                ComicCardView(comic: comic)
            }
        }
        .padding(Spacing.xl)
    }
    .background(BackgroundColors.primary)
}
