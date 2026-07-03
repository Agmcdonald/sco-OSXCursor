//
//  NextIssuePreviewOverlay.swift
//  SCO-OSXCursor
//
//  End-of-book "Up Next" suggestion. Shown when the user turns forward past
//  the last page; presents the next book (per the library's current sort
//  order) with a medium cover preview. Turning forward once more — or
//  clicking Start Reading — advances into that book like turning a page.
//

import SwiftUI

struct NextIssuePreviewOverlay: View {
    let comic: Comic
    /// Reading direction of the CURRENT book — used to point the hint arrow
    /// in the direction that actually advances.
    let isRTL: Bool
    let onStart: () -> Void
    let onDismiss: () -> Void

    private var coverImage: PlatformImage? {
        guard let data = comic.coverImageData else { return nil }
        return PageImageCache.shared.coverImage(
            from: data, cacheKey: comic.id.uuidString)
    }

    /// "Series #Issue" when available, falling back gracefully.
    private var seriesLine: String? {
        switch (comic.series, comic.issueNumber) {
        case (let series?, let issue?): return "\(series) #\(issue)"
        case (let series?, nil): return series
        case (nil, let issue?): return "Issue #\(issue)"
        case (nil, nil): return nil
        }
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop. It sits ABOVE the reader's tap zones and swipe
            // handlers, so it must keep "turn the page" working itself:
            // a tap in the forward zone or a forward swipe advances into the
            // next book; taps/swipes anywhere else dismiss the preview.
            GeometryReader { geo in
                Color.black.opacity(0.72)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                let distance = hypot(dx, dy)

                                if distance < 10 {
                                    // Tap — outer third on the forward side
                                    // counts as "turn the page again"
                                    let fraction =
                                        value.startLocation.x / max(geo.size.width, 1)
                                    let forwardTap =
                                        isRTL ? fraction < 0.3 : fraction > 0.7
                                    if forwardTap {
                                        onStart()
                                    } else {
                                        onDismiss()
                                    }
                                } else if abs(dx) > abs(dy), abs(dx) > 40 {
                                    // Swipe — forward advances, backward dismisses
                                    let forwardSwipe = isRTL ? dx > 0 : dx < 0
                                    if forwardSwipe {
                                        onStart()
                                    } else {
                                        onDismiss()
                                    }
                                }
                            }
                    )
            }
            .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Text("UP NEXT")
                    .font(Typography.caption)
                    .fontWeight(.semibold)
                    .tracking(2)
                    .foregroundColor(TextColors.secondary)

                // Medium cover preview
                coverView
                    .frame(width: 200, height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 18, y: 8)

                VStack(spacing: Spacing.sm) {
                    Text(comic.displayTitle)
                        .font(Typography.h3)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let seriesLine {
                        Text(seriesLine)
                            .font(Typography.body)
                            .foregroundColor(TextColors.secondary)
                            .lineLimit(1)
                    }

                    if comic.totalPages > 0 {
                        Text("\(comic.totalPages) pages")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                    }
                }
                .padding(.horizontal, Spacing.xl)

                Button(action: onStart) {
                    HStack(spacing: Spacing.sm) {
                        Text("Start Reading")
                        Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                    }
                    .font(Typography.button)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.vertical, Spacing.md)
                    .background(AccentColors.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                Text(isRTL ? "or turn the page again ←" : "or turn the page again →")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
            }
            .padding(Spacing.xxl)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(BackgroundColors.elevated.opacity(0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(BorderColors.subtle, lineWidth: 1)
            )
            .padding(Spacing.xl)
            .onTapGesture {}  // swallow taps on the card itself
        }
    }

    @ViewBuilder
    private var coverView: some View {
        if let image = coverImage {
            #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 300)
                    .clipped()
            #else
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 300)
                    .clipped()
            #endif
        } else {
            ZStack {
                LinearGradient(
                    colors: [BackgroundColors.secondary, BackgroundColors.primary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "book.closed")
                    .font(.system(size: 44))
                    .foregroundColor(TextColors.tertiary)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        NextIssuePreviewOverlay(
            comic: Comic.sample(),
            isRTL: false,
            onStart: {},
            onDismiss: {}
        )
    }
}
