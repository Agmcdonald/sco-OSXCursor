import SwiftUI

struct ComicInspectorView: View {
    let comic: Comic
    var onDismiss: (() -> Void)? = nil

    /// True when metadata came from a ComicVine lookup.
    private var sourceIsComicVine: Bool {
        comic.metadataFetchedAt != nil || comic.comicVineVolumeID != nil
    }

    private var sourceLabel: String {
        if let date = comic.metadataFetchedAt {
            return "ComicVine • " + date.formatted(date: .abbreviated, time: .omitted)
        }
        return sourceIsComicVine ? "ComicVine" : "Entered manually"
    }

    private var hasAnyCredit: Bool {
        [comic.writer, comic.artist, comic.coverArtist,
         comic.colorist, comic.inker, comic.editor]
            .contains { ($0?.isEmpty == false) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {

                // ── Close button row ──────────────────────────────────────
                HStack {
                    Text("Info")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    Spacer()
                    Button(action: { onDismiss?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(TextColors.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Inspector")
                }

                // ── Cover art ─────────────────────────────────────────────
                ZStack {
                    if let coverData = comic.coverImageData {
                        #if os(macOS)
                            if let nsImage = NSImage(data: coverData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(radius: 4)
                            }
                        #else
                            if let uiImage = UIImage(data: coverData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(radius: 4)
                            }
                        #endif
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BackgroundColors.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: "book.closed")
                                    .font(.system(size: 40))
                                    .foregroundColor(TextColors.tertiary)
                            )
                    }
                }
                .padding(.bottom, Spacing.sm)

                // ── Metadata fields (hidden when blank) ───────────────────
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if let title = comic.title, !title.isEmpty {
                        InspectorField(title: "Storyline Title", value: title)
                    }
                    if let series = comic.series, !series.isEmpty {
                        InspectorField(title: "Series", value: series)
                    }
                    if let publisher = comic.publisher, !publisher.isEmpty {
                        InspectorField(title: "Publisher", value: publisher)
                    }
                    if let issue = comic.issueNumber, !issue.isEmpty {
                        InspectorField(title: "Issue", value: issue)
                    }
                    if let year = comic.year {
                        InspectorField(title: "Year", value: String(year))
                    }
                    
                    InspectorField(title: "Content Rating", value: comic.contentRating.label)
                    
                    if let rating = comic.rating, rating > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("User Rating")
                                .font(Typography.label)
                                .foregroundColor(TextColors.tertiary)
                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .foregroundColor(star <= rating ? AccentColors.warning : TextColors.tertiary)
                                        .font(.system(size: 14))
                                }
                            }
                        }
                    }

                    // Where this metadata came from
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Metadata Source")
                            .font(Typography.label)
                            .foregroundColor(TextColors.tertiary)
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: sourceIsComicVine ? "network" : "pencil")
                                .font(.system(size: 12))
                            Text(sourceLabel)
                        }
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                    }
                }

                // ── Credits (hidden when none) ────────────────────────────
                if hasAnyCredit {
                    Divider()
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Credits")
                            .font(Typography.h3)
                            .foregroundColor(TextColors.primary)

                        if let v = comic.writer, !v.isEmpty {
                            InspectorField(title: "Writer", value: v)
                        }
                        if let v = comic.artist, !v.isEmpty {
                            InspectorField(title: "Artist", value: v)
                        }
                        if let v = comic.coverArtist, !v.isEmpty {
                            InspectorField(title: "Cover Artist", value: v)
                        }
                        if let v = comic.colorist, !v.isEmpty {
                            InspectorField(title: "Colorist", value: v)
                        }
                        if let v = comic.inker, !v.isEmpty {
                            InspectorField(title: "Inker", value: v)
                        }
                        if let v = comic.editor, !v.isEmpty {
                            InspectorField(title: "Editor", value: v)
                        }
                    }
                }

                // ── Summary (hidden when blank) ───────────────────────────
                if let summary = comic.summary, !summary.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Summary")
                            .font(Typography.label)
                            .foregroundColor(TextColors.tertiary)
                        Text(summary)
                            .font(Typography.body)
                            .foregroundColor(TextColors.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // ── Tags (hidden when none) ───────────────────────────────
                if !comic.tags.isEmpty {
                    Divider()
                    InspectorField(
                        title: "Tags",
                        value: comic.tags.joined(separator: ", "))
                }

                Divider()

                // ── File info ─────────────────────────────────────────────
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("File Info")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)

                    InspectorField(title: "Name", value: comic.cleanFileName)
                    InspectorField(title: "Original Name", value: comic.fileName)
                    InspectorField(title: "Size", value: comic.fileSizeFormatted)

                    // "Show in Finder" button (macOS only)
                    #if os(macOS)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(Typography.label)
                            .foregroundColor(TextColors.tertiary)

                        Button(action: {
                            NSWorkspace.shared.activateFileViewerSelecting([comic.resolvedURL])
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "folder")
                                    .font(.system(size: 13))
                                Text("Show in Finder")
                                    .font(Typography.bodySmall)
                            }
                            .foregroundColor(AccentColors.primary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.primary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    #endif
                }

                Spacer()
            }
            .padding(Spacing.xl)
        }
        .background(BackgroundColors.primary)
    }
}

// MARK: - Field row
private struct InspectorField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Typography.label)
                .foregroundColor(TextColors.tertiary)
            Text(value)
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
                .textSelection(.enabled)
        }
    }
}
