import SwiftUI

struct DashboardOverviewView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    @State private var topPublishers: [(String, Int)] = []

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Left Column
            VStack(spacing: Spacing.md) {
                // Queue Progress
                DashboardSectionCard(title: "Queue Progress") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ProgressView(value: 0.0)  // Placeholder
                            .progressViewStyle(.linear)
                            .tint(AccentColors.primary)

                        Text("0 of 0 files processed.")
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                    }
                }

                // Quick Actions
                DashboardSectionCard(title: "Quick Actions") {
                    VStack(spacing: Spacing.sm) {
                        Button(action: {
                            // TODO: Add files action
                        }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("Add Files")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(AccentColors.primary)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            // TODO: Scan folder action
                        }) {
                            HStack {
                                Image(systemName: "folder.badge.magnifyingglass")
                                Text("Scan Folder")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(BackgroundColors.secondary)
                            .foregroundColor(AccentColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            // TODO: Open knowledge action
                        }) {
                            HStack {
                                Image(systemName: "tag")
                                Text("Open Knowledge")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(BackgroundColors.secondary)
                            .foregroundColor(AccentColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Middle Column
            VStack(spacing: Spacing.md) {
                DashboardSectionCard(
                    title: "Library Statistics", subtitle: "Breakdown of your comic collection"
                ) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Top Publishers")
                                .font(Typography.h3)
                                .foregroundColor(TextColors.primary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(topPublishers, id: \.0) { publisher in
                                        Text("\(publisher.0): \(publisher.1)")
                                            .font(Typography.caption)
                                            .padding(.horizontal, Spacing.sm)
                                            .padding(.vertical, 4)
                                            .background(BackgroundColors.secondary)
                                            .foregroundColor(TextColors.secondary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // Placeholder for decades
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Popular Decades")
                                .font(Typography.h3)
                                .foregroundColor(TextColors.primary)

                            HStack {
                                Text("2020s: 142")
                                    .font(Typography.caption)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, 4)
                                    .background(BackgroundColors.secondary)
                                    .foregroundColor(TextColors.secondary)
                                    .clipShape(Capsule())

                                Text("1930s: 39")
                                    .font(Typography.caption)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, 4)
                                    .background(BackgroundColors.secondary)
                                    .foregroundColor(TextColors.secondary)
                                    .clipShape(Capsule())
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(libraryViewModel.comics.count)")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(TextColors.primary)
                            Text("Total Comics")
                                .font(Typography.caption)
                                .foregroundColor(TextColors.secondary)
                        }
                    }
                }
                .onAppear {
                    calculateStats()
                }
                .onChange(of: libraryViewModel.comics) { _, _ in
                    calculateStats()
                }
            }
            .frame(maxWidth: .infinity)

            // Right Column
            VStack(spacing: Spacing.md) {
                DashboardSectionCard(
                    title: "Recent Actions", subtitle: "A log of the latest file operations."
                ) {
                    VStack(spacing: Spacing.lg) {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "info.circle")
                                .foregroundColor(AccentColors.primary)
                                .font(.system(size: 20))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Database is empty. Add files to start your library.")
                                    .font(Typography.bodySmall)
                                    .foregroundColor(TextColors.primary)
                                Text("5:03:41 PM")
                                    .font(Typography.caption)
                                    .foregroundColor(TextColors.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, Spacing.md)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func calculateStats() {
        // Calculate Top Publishers
        var publisherCounts: [String: Int] = [:]
        for comic in libraryViewModel.comics {
            let pub = comic.normalizedPublisher ?? "Unknown Publisher"
            publisherCounts[pub, default: 0] += 1
        }

        topPublishers = publisherCounts.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0 }
    }
}
