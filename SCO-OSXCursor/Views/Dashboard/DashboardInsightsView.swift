import Charts
import SwiftUI

struct DashboardInsightsView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel

    // Computed stats derived from the library
    private var totalComics: Int { libraryViewModel.comics.count }
    private var uniqueSeries: Int {
        Set(libraryViewModel.comics.compactMap { $0.series?.isEmpty == false ? $0.series : nil })
            .count
    }
    private var uniquePublishers: Int {
        Set(libraryViewModel.comics.compactMap { $0.normalizedPublisher }).count
    }
    private var avgIssuesPerSeries: Int {
        guard uniqueSeries > 0 else { return 0 }
        return totalComics / uniqueSeries
    }
    private var completenessPercentage: Double {
        // Series completeness = % of series that have 5+ issues
        let seriesGroups = Dictionary(
            grouping: libraryViewModel.comics.compactMap { $0.series }, by: { $0 })
        guard !seriesGroups.isEmpty else { return 0 }
        let complete = seriesGroups.values.filter { $0.count >= 5 }.count
        return Double(complete) / Double(seriesGroups.count)
    }

    private var topPublishers: [(publisher: String, count: Int)] {
        var counts: [String: Int] = [:]
        for comic in libraryViewModel.comics {
            let pub = comic.normalizedPublisher ?? "Unknown Publisher"
            counts[pub, default: 0] += 1
        }
        return counts.map { (publisher: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(6)
            .map { $0 }
    }

    private var comicsByDecade: [(decade: String, count: Int)] {
        var counts: [Int: Int] = [:]
        for comic in libraryViewModel.comics {
            guard let year = comic.year else { continue }
            let decade = (year / 10) * 10
            counts[decade, default: 0] += 1
        }
        return counts.map { (decade: "\($0.key)s", count: $0.value) }
            .sorted { $0.decade < $1.decade }
    }

    private var comicsByYear: [(year: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for comic in libraryViewModel.comics {
            guard let year = comic.year else { continue }
            counts[year, default: 0] += 1
        }
        return counts.map { (year: $0.key, count: $0.value) }
            .sorted { $0.year < $1.year }
    }

    private var mostCollectedSeries: [(series: String, count: Int)] {
        var counts: [String: Int] = [:]
        for comic in libraryViewModel.comics {
            guard let series = comic.series, !series.isEmpty else { continue }
            counts[series, default: 0] += 1
        }
        return counts.map { (series: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Collection Overview Card
            DashboardSectionCard(
                title: "Collection Overview",
                subtitle: "Key metrics and trends from your comic library"
            ) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Key metrics row
                    HStack(spacing: Spacing.xl) {
                        InsightMetric(
                            value: "\(totalComics)", label: "Total Comics",
                            color: AccentColors.primary)
                        InsightMetric(
                            value: "\(uniqueSeries)", label: "Unique Series", color: .purple)
                        InsightMetric(
                            value: "\(uniquePublishers)", label: "Publishers", color: .green)
                        InsightMetric(
                            value: "\(avgIssuesPerSeries)", label: "Avg Issues/Series",
                            color: .orange)
                    }

                    // Completeness bar
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("Collection Completeness")
                                .font(Typography.h3)
                                .foregroundColor(TextColors.primary)
                            Spacer()
                            Text("\(Int(completenessPercentage * 100))%")
                                .font(Typography.h3)
                                .foregroundColor(TextColors.secondary)
                        }
                        ProgressView(value: completenessPercentage)
                            .progressViewStyle(.linear)
                            .tint(AccentColors.primary)
                        Text("Based on series with 5+ issues")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.tertiary)
                    }
                }
            }

            // Charts Row
            HStack(alignment: .top, spacing: Spacing.md) {
                // Top Publishers chart
                DashboardSectionCard(title: "Top Publishers") {
                    if topPublishers.isEmpty {
                        EmptyChartPlaceholder(label: "No publisher data")
                    } else {
                        Chart(topPublishers, id: \.publisher) { item in
                            BarMark(
                                x: .value("Count", item.count),
                                y: .value("Publisher", item.publisher)
                            )
                            .foregroundStyle(AccentColors.primary.gradient)
                            .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(preset: .aligned)
                        }
                        .chartYAxis {
                            AxisMarks(preset: .aligned) { _ in
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 200)
                    }
                }
                .frame(maxWidth: .infinity)

                // Comics by Decade chart
                DashboardSectionCard(title: "Comics by Decade") {
                    if comicsByDecade.isEmpty {
                        EmptyChartPlaceholder(label: "No decade data")
                    } else {
                        Chart(comicsByDecade, id: \.decade) { item in
                            BarMark(
                                x: .value("Decade", item.decade),
                                y: .value("Count", item.count)
                            )
                            .foregroundStyle(AccentColors.primary.gradient)
                            .cornerRadius(4)
                        }
                        .frame(height: 200)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Comics by Publication Year (full-width line chart)
            DashboardSectionCard(title: "Comics by Publication Year") {
                if comicsByYear.isEmpty {
                    EmptyChartPlaceholder(label: "No year data")
                } else {
                    Chart(comicsByYear, id: \.year) { item in
                        BarMark(
                            x: .value("Year", item.year),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(AccentColors.primary.gradient)
                        .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 5)) { value in
                            AxisValueLabel()
                            AxisGridLine(stroke: StrokeStyle(dash: [3, 3]))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                            AxisGridLine(stroke: StrokeStyle(dash: [3, 3]))
                        }
                    }
                    .frame(height: 220)
                }
            }

            // Most Collected Series list
            DashboardSectionCard(
                title: "Most Collected Series",
                subtitle: "Series with the most issues in your collection"
            ) {
                if mostCollectedSeries.isEmpty {
                    EmptyChartPlaceholder(label: "No series data")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(mostCollectedSeries.enumerated()), id: \.element.series) {
                            index, item in
                            HStack {
                                Text("#\(index + 1)")
                                    .font(Typography.caption)
                                    .foregroundColor(TextColors.tertiary)
                                    .frame(width: 28, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.series)
                                        .font(Typography.bodySmall)
                                        .foregroundColor(TextColors.primary)
                                    Text("\(item.count) issues")
                                        .font(Typography.caption)
                                        .foregroundColor(TextColors.secondary)
                                }

                                Spacer()

                                // Status badge placeholder
                                let status = seriesStatus(for: item.series)
                                Text(status)
                                    .font(Typography.caption)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, 3)
                                    .background(statusColor(for: status).opacity(0.15))
                                    .foregroundColor(statusColor(for: status))
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, Spacing.sm)

                            if index < mostCollectedSeries.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func seriesStatus(for series: String) -> String {
        let matching = libraryViewModel.comics.filter { $0.series == series }
        let hasReading = matching.contains { $0.status == .reading }
        let allCompleted = matching.allSatisfy { $0.status == .completed }
        if allCompleted { return "Complete" }
        if hasReading { return "Started" }
        return "Unread"
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Complete": return .green
        case "Started": return AccentColors.primary
        default: return TextColors.tertiary
        }
    }
}

// MARK: - Helper Components

struct InsightMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyChartPlaceholder: View {
    let label: String
    var body: some View {
        HStack {
            Spacer()
            Text(label)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.tertiary)
            Spacer()
        }
        .frame(height: 80)
    }
}
