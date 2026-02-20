import SwiftUI

struct DashboardHealthView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel

    private var totalComics: Int { libraryViewModel.comics.count }

    // Comics missing metadata
    private var missingMetadata: [Comic] {
        libraryViewModel.comics.filter {
            ($0.title == nil || $0.title?.isEmpty == true)
                && ($0.series == nil || $0.series?.isEmpty == true)
        }
    }

    // Comics missing covers
    private var missingCovers: [Comic] {
        libraryViewModel.comics.filter { $0.coverImageData == nil }
    }

    // Potential duplicates: same series + same issue number
    private var potentialDuplicateGroups: [[Comic]] {
        var groups: [String: [Comic]] = [:]
        for comic in libraryViewModel.comics {
            if let series = comic.series, !series.isEmpty,
                let issue = comic.issueNumber, !issue.isEmpty
            {
                let key = "\(series.lowercased())_\(issue.lowercased())"
                groups[key, default: []].append(comic)
            }
        }
        return groups.values.filter { $0.count > 1 }.map { $0 }
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
                                actionLabel: "Review Duplicates"
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
                                actionLabel: "Review Comics"
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
                                actionLabel: "Review Comics"
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

            Button(actionLabel) { /* TODO: navigate to maintenance */  }
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
