import SwiftUI

struct DashboardHealthView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    /// Navigates to the Maintenance tab, where the fix-it actions live.
    var onOpenMaintenance: () -> Void = {}

    private var totalComics: Int { libraryViewModel.comics.count }

    private var missingMetadata: [Comic] {
        LibraryHealth.missingMetadata(in: libraryViewModel.comics)
    }

    private var missingCovers: [Comic] {
        LibraryHealth.missingCovers(in: libraryViewModel.comics)
    }

    private var potentialDuplicateGroups: [[Comic]] {
        LibraryHealth.duplicateGroups(in: libraryViewModel.comics)
    }

    // Health score: penalise for issues
    private var healthScore: Int {
        guard totalComics > 0 else { return 100 }
        var score = 100.0
        let missingMetadataPenalty = min(
            20.0, Double(missingMetadata.count) / Double(totalComics) * 100)
        let missingCoverPenalty = min(10.0, Double(missingCovers.count) / Double(totalComics) * 50)
        let duplicatePenalty = min(10.0, Double(potentialDuplicateGroups.count) * 5.0)
        score -= missingMetadataPenalty + missingCoverPenalty + duplicatePenalty
        return max(0, Int(score.rounded()))
    }

    private var healthLabel: String {
        switch healthScore {
        case 90...100: return "Excellent"
        case 75..<90: return "Good"
        case 50..<75: return "Fair"
        default: return "Needs Work"
        }
    }

    private var healthColor: Color {
        switch healthScore {
        case 90...100: return .green
        case 75..<90: return AccentColors.primary
        case 50..<75: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Overall Health Score
            DashboardSectionCard(
                title: "Library Health",
                subtitle: "Overall health and quality metrics for your comic collection"
            ) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("\(healthScore)%")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(healthColor)
                            Text(healthLabel)
                                .font(Typography.h3)
                                .foregroundColor(TextColors.secondary)
                        }
                        Spacer()

                        // Breakdown mini metrics
                        HStack(spacing: Spacing.xl) {
                            HealthMetric(
                                value: "\(totalComics)", label: "Total Comics",
                                icon: "books.vertical", color: AccentColors.primary)
                            HealthMetric(
                                value: "\(missingMetadata.count)", label: "Missing Metadata",
                                icon: "tag.slash", color: missingMetadata.isEmpty ? .green : .orange
                            )
                            HealthMetric(
                                value: "\(missingCovers.count)", label: "Missing Covers",
                                icon: "photo.badge.exclamationmark",
                                color: missingCovers.isEmpty ? .green : .orange)
                            HealthMetric(
                                value: "\(potentialDuplicateGroups.count)",
                                label: "Potential Duplicates", icon: "doc.on.doc",
                                color: potentialDuplicateGroups.isEmpty ? .green : .red)
                        }
                    }

                    ProgressView(value: Double(healthScore) / 100.0)
                        .progressViewStyle(.linear)
                        .tint(healthColor)
                        .scaleEffect(x: 1, y: 1.5, anchor: .center)
                }
            }

            // Issues Detected
            if !missingMetadata.isEmpty || !missingCovers.isEmpty
                || !potentialDuplicateGroups.isEmpty
            {
                DashboardSectionCard(title: "Issues Detected") {
                    VStack(spacing: Spacing.sm) {
                        if !potentialDuplicateGroups.isEmpty {
                            HealthIssueRow(
                                icon: "doc.on.doc",
                                iconColor: .red,
                                title: "Potential Duplicates",
                                description:
                                    "Found \(potentialDuplicateGroups.count) set\(potentialDuplicateGroups.count == 1 ? "" : "s") of comics that might be duplicates.",
                                badgeCount: potentialDuplicateGroups.count,
                                actionLabel: "Fix in Maintenance",
                                action: onOpenMaintenance
                            )
                        }

                        if !missingMetadata.isEmpty {
                            if !potentialDuplicateGroups.isEmpty { Divider() }
                            HealthIssueRow(
                                icon: "tag.slash",
                                iconColor: .orange,
                                title: "Missing Metadata",
                                description:
                                    "\(missingMetadata.count) comic\(missingMetadata.count == 1 ? "" : "s") missing title or series information.",
                                badgeCount: missingMetadata.count,
                                actionLabel: "Fix in Maintenance",
                                action: onOpenMaintenance
                            )
                        }

                        if !missingCovers.isEmpty {
                            if !missingMetadata.isEmpty || !potentialDuplicateGroups.isEmpty {
                                Divider()
                            }
                            HealthIssueRow(
                                icon: "photo.badge.exclamationmark",
                                iconColor: .orange,
                                title: "Missing Cover Art",
                                description:
                                    "\(missingCovers.count) comic\(missingCovers.count == 1 ? "" : "s") have no cover image.",
                                badgeCount: missingCovers.count,
                                actionLabel: "Fix in Maintenance",
                                action: onOpenMaintenance
                            )
                        }
                    }
                }
            } else {
                DashboardSectionCard {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Issues Detected")
                                .font(Typography.h3)
                                .foregroundColor(TextColors.primary)
                            Text("Your library looks great!")
                                .font(Typography.bodySmall)
                                .foregroundColor(TextColors.secondary)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
        }
    }
}

// MARK: - Health Computations

/// Shared issue detection used by the Health tab and its review sheet.
enum LibraryHealth {
    static func missingMetadata(in comics: [Comic]) -> [Comic] {
        comics.filter {
            ($0.title == nil || $0.title?.isEmpty == true)
                && ($0.series == nil || $0.series?.isEmpty == true)
        }
    }

    static func missingCovers(in comics: [Comic]) -> [Comic] {
        comics.filter { $0.coverImageData == nil }
    }

    /// Potential duplicates: same series + same issue number. Groups are
    /// sorted by series/issue so the list order is stable across refreshes.
    static func duplicateGroups(in comics: [Comic]) -> [[Comic]] {
        var groups: [String: [Comic]] = [:]
        for comic in comics {
            if let series = comic.series, !series.isEmpty,
                let issue = comic.issueNumber, !issue.isEmpty
            {
                let key = "\(series.lowercased())_\(issue.lowercased())"
                groups[key, default: []].append(comic)
            }
        }
        return groups
            .filter { $0.value.count > 1 }
            .sorted { $0.key < $1.key }
            .map { $0.value }
    }
}

// MARK: - Helper Views

struct HealthMetric: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TextColors.primary)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HealthIssueRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let badgeCount: Int
    let actionLabel: String
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.primary)
                    Text("\(badgeCount)")
                        .font(Typography.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(iconColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                Text(description)
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
            }

            Spacer()

            Button(actionLabel, action: action)
                .buttonStyle(.plain)
                .font(Typography.bodySmall)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(BackgroundColors.secondary)
                .foregroundColor(TextColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Review Sheet

/// Which health issue the review sheet is showing.
enum HealthReviewMode: String, Identifiable {
    case duplicates
    case missingMetadata
    case missingCovers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicates: return "Potential Duplicates"
        case .missingMetadata: return "Missing Metadata"
        case .missingCovers: return "Missing Cover Art"
        }
    }
}

/// Lists the books behind a Health issue and offers a fix:
/// duplicates → per-copy delete; missing metadata → batch ComicVine fetch;
/// missing covers → batch cover regeneration.
struct HealthReviewSheet: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    let mode: HealthReviewMode
    let onClose: () -> Void

    @State private var comicPendingDelete: Comic?
    @State private var deleteFileToo = false
    @State private var isWorking = false
    @State private var statusText: String?

    private var duplicateGroups: [[Comic]] {
        LibraryHealth.duplicateGroups(in: libraryViewModel.comics)
    }

    private var flatComics: [Comic] {
        switch mode {
        case .duplicates: return []
        case .missingMetadata: return LibraryHealth.missingMetadata(in: libraryViewModel.comics)
        case .missingCovers: return LibraryHealth.missingCovers(in: libraryViewModel.comics)
        }
    }

    private var isEmpty: Bool {
        mode == .duplicates ? duplicateGroups.isEmpty : flatComics.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .background(BackgroundColors.primary)
        #if os(macOS)
            .frame(minWidth: 560, minHeight: 460)
        #endif
        .alert(
            deleteFileToo ? "Delete File from Device" : "Remove from Library",
            isPresented: Binding(
                get: { comicPendingDelete != nil },
                set: { if !$0 { comicPendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { comicPendingDelete = nil }
            Button(deleteFileToo ? "Delete File" : "Remove", role: .destructive) {
                if let comic = comicPendingDelete {
                    let deleteFile = deleteFileToo
                    Task {
                        if deleteFile {
                            await libraryViewModel.deleteComicsFromDevice([comic])
                        } else {
                            await libraryViewModel.deleteComicsFromApp([comic])
                        }
                    }
                }
                comicPendingDelete = nil
            }
        } message: {
            Text(
                deleteFileToo
                    ? "\"\(comicPendingDelete?.displayName ?? "")\" will be removed from the library AND its file deleted from this device. This cannot be undone."
                    : "\"\(comicPendingDelete?.displayName ?? "")\" will be removed from the library. The file stays on disk."
            )
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
                if let statusText {
                    Text(statusText)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                }
            }

            Spacer()

            if mode == .missingMetadata && !flatComics.isEmpty {
                Button(isWorking ? "Fetching…" : "Fetch All from ComicVine") {
                    fetchAllMetadata()
                }
                .disabled(isWorking)
            }

            if mode == .missingCovers && !flatComics.isEmpty {
                Button("Regenerate All Covers") {
                    libraryViewModel.regenerateCovers(for: flatComics)
                    statusText = "Regenerating \(flatComics.count) cover\(flatComics.count == 1 ? "" : "s") in the background…"
                }
            }

            Button("Done", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
        .padding(Spacing.md)
    }

    // MARK: Content

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            Text("All clear — nothing left to review.")
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                if mode == .duplicates {
                    ForEach(Array(duplicateGroups.enumerated()), id: \.offset) { _, group in
                        duplicateSection(group)
                    }
                } else {
                    ForEach(flatComics) { comic in
                        HealthReviewRow(comic: comic, showDeleteMenu: false) { _ in }
                        Divider()
                    }
                }
            }
            .padding(Spacing.md)
        }
    }

    @ViewBuilder
    private func duplicateSection(_ group: [Comic]) -> some View {
        let first = group[0]
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("\(first.series ?? "Unknown") #\(first.issueNumber ?? "?") — \(group.count) copies")
                .font(Typography.h3)
                .foregroundColor(TextColors.primary)
                .padding(.top, Spacing.xs)

            ForEach(group) { comic in
                HealthReviewRow(comic: comic, showDeleteMenu: true) { deleteFile in
                    deleteFileToo = deleteFile
                    comicPendingDelete = comic
                }
            }
            Divider()
        }
    }

    // MARK: Actions

    private func fetchAllMetadata() {
        let comics = flatComics
        isWorking = true
        Task {
            let result = await libraryViewModel.fetchComicVineMetadataBatch(for: comics) {
                done, total in
                statusText = "Fetching… \(done) of \(total)"
            }
            statusText = result.summary
            isWorking = false
        }
    }
}

/// One book row in the review sheet: cover thumbnail, names, file details,
/// and (for duplicates) a delete menu.
private struct HealthReviewRow: View {
    let comic: Comic
    let showDeleteMenu: Bool
    /// Called with `true` to also delete the file on disk.
    let onDelete: (Bool) -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            coverThumb

            VStack(alignment: .leading, spacing: 2) {
                Text(comic.displayName)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(1)
                Text("\(comic.fileName) · \(comic.fileSizeFormatted)")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if showDeleteMenu {
                Menu {
                    Button("Remove from Library", role: .destructive) { onDelete(false) }
                    Button("Delete File from Device…", role: .destructive) { onDelete(true) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var coverThumb: some View {
        if let data = comic.coverImageData,
            let cover = PageImageCache.shared.coverImage(
                from: data, cacheKey: comic.id.uuidString)
        {
            #if os(macOS)
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 44)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            #else
                Image(uiImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 44)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            #endif
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(BackgroundColors.secondary)
                .frame(width: 32, height: 44)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 12))
                        .foregroundColor(TextColors.tertiary)
                )
        }
    }
}
