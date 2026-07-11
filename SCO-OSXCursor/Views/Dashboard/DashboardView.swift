import SwiftUI

struct DashboardView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    /// Navigates to the Knowledge tab (wired up in ContentView).
    var onOpenKnowledge: () -> Void = {}
    /// Navigates to the Maintenance tab (wired up in ContentView).
    var onOpenMaintenance: () -> Void = {}
    @State private var selectedTab: DashboardTab = .overview

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        /// iPhone: four metric tiles in one row squeeze the text — use a
        /// 2×2 grid instead, and let the tab selector scroll.
        private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
        private var isCompact: Bool { false }
    #endif

    enum DashboardTab: String, CaseIterable {
        case overview = "Overview"
        case insights = "Insights"
        case reading = "Reading"
        case health = "Health"
        case activity = "Activity"

        var icon: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .insights: return "chart.xyaxis.line"
            case .reading: return "book.open"
            case .health: return "bolt.fill"
            case .activity: return "pulse"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Dashboard")
                        .font(Typography.h1)
                        .foregroundColor(TextColors.primary)
                    Text("Overview of your comic collection and organization progress")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                }
                .padding(.top, Spacing.xl)
                .padding(.horizontal, Spacing.xl)

                // Top Metrics Row — iPhone gets a 2×2 grid, wider screens one row
                Group {
                    if isCompact {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: Spacing.md),
                                GridItem(.flexible(), spacing: Spacing.md),
                            ],
                            spacing: Spacing.md
                        ) {
                            metricCards
                        }
                    } else {
                        HStack(spacing: Spacing.md) {
                            metricCards
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)

                // Tab Selector
                DashboardTabSelector(selectedTab: $selectedTab, isCompact: isCompact)
                    .padding(.horizontal, Spacing.xl)

                // Tab Content
                Group {
                    switch selectedTab {
                    case .overview:
                        DashboardOverviewView(
                            libraryViewModel: libraryViewModel,
                            onOpenKnowledge: onOpenKnowledge
                        )
                    case .insights:
                        DashboardInsightsView(libraryViewModel: libraryViewModel)
                    case .reading:
                        DashboardReadingView(libraryViewModel: libraryViewModel)
                    case .health:
                        DashboardHealthView(
                            libraryViewModel: libraryViewModel,
                            onOpenMaintenance: onOpenMaintenance
                        )
                    case .activity:
                        DashboardActivityView(libraryViewModel: libraryViewModel)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .background(BackgroundColors.primary)
    }

    /// The four metric tiles, shared by the compact grid and the wide row.
    @ViewBuilder
    private var metricCards: some View {
        MetricCard(
            title: "Files in Queue",
            value: "0"  // Placeholder until OrganizeViewModel is integrated
        )
        MetricCard(
            title: "Comics in Library",
            value: "\(libraryViewModel.comics.count)"
        )
        MetricCard(
            title: "Needs Review",
            value: "0"  // Placeholder
        )
        MetricCard(
            title: "Errors",
            value: "0",  // Placeholder
            valueColor: AccentColors.error
        )
    }
}

// MARK: - Reusable Components

struct MetricCard: View {
    let title: String
    let value: String
    var valueColor: Color = TextColors.primary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)

            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct DashboardTabSelector: View {
    @Binding var selectedTab: DashboardView.DashboardTab
    /// iPhone: tabs keep their natural width and scroll horizontally instead
    /// of dividing the bar into five slivers that wrap mid-word.
    var isCompact: Bool = false

    var body: some View {
        Group {
            if isCompact {
                ScrollView(.horizontal, showsIndicators: false) {
                    tabButtons
                }
            } else {
                tabButtons
            }
        }
        .padding(Spacing.xs)
        .background(BackgroundColors.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var tabButtons: some View {
        HStack(spacing: 0) {
            ForEach(DashboardView.DashboardTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                            .fixedSize()
                    }
                    .font(Typography.button)
                    .padding(.vertical, Spacing.sm)
                    .padding(.horizontal, isCompact ? Spacing.md : 0)
                    .frame(maxWidth: isCompact ? nil : .infinity)
                    .background(selectedTab == tab ? BackgroundColors.elevated : Color.clear)
                    .foregroundColor(selectedTab == tab ? TextColors.primary : TextColors.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    // Make the WHOLE tab area clickable, not just the label.
                    // .plain buttons only hit-test opaque pixels, so without
                    // this the transparent padding around the text ignores
                    // clicks.
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DashboardSectionCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    let content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let title = title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.h2)
                        .foregroundColor(TextColors.primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.secondary)
                    }
                }
            }

            content
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
