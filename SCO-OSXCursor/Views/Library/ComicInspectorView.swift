import SwiftUI

struct ComicInspectorView: View {
    let comic: Comic
    var onDismiss: (() -> Void)? = nil

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
