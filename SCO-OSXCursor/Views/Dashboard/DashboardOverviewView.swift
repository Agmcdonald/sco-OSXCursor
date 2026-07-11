import SwiftUI
import UniformTypeIdentifiers

struct DashboardOverviewView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    /// Navigates to the Knowledge tab (wired up in ContentView).
    var onOpenKnowledge: () -> Void = {}
    @ObservedObject private var comicVineQuota = ComicVineQuota.shared
    @State private var topPublishers: [(String, Int)] = []
    @State private var showingFilePicker = false
    @State private var showingFolderScanner = false
    // Import paused while the user decides on a home library folder
    @State private var showingHomeLibraryPrompt = false
    @State private var pendingImportURLs: [URL] = []

    var body: some View {
        VStack(spacing: Spacing.md) {
            if useSingleColumn {
                // iPhone: actions first, quota bar last
                columns
                comicVineQuotaCard
            } else {
                // ComicVine API quota — full-width bar above the three columns
                comicVineQuotaCard
                columns
            }
        }
        // SwiftUI honors only ONE .fileImporter per view, so each importer
        // sits on its own invisible background view (same pattern as
        // LibraryView).
        // Add Files — same types as Library Quick Add.
        .background(
            Color.clear.fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [
                    .folder, .zip, .pdf, .cbr, .epub, UTType(filenameExtension: "cbr")!,
                    UTType(filenameExtension: "epub") ?? .data,
                ],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
        )
        // Scan Folder — folder-only; importComics expands folders recursively.
        .background(
            Color.clear.fileImporter(
                isPresented: $showingFolderScanner,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
        )
        // Offer to set a home library before the first sorted import
        .modifier(
            HomeLibrarySetupPrompt(
                isPresented: $showingHomeLibraryPrompt,
                pendingURLs: $pendingImportURLs,
                onImport: { urls in
                    Task { await libraryViewModel.importComics(from: urls) }
                }
            )
        )
    }

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        /// iPhone: three side-by-side columns don't fit — stack every card
        /// full-width instead (same width as the ComicVine API bar).
        private var useSingleColumn: Bool { horizontalSizeClass == .compact }
    #else
        private var useSingleColumn: Bool { false }
    #endif

    @ViewBuilder
    private var columns: some View {
        if useSingleColumn {
            VStack(spacing: Spacing.md) {
                quickActionsCard
                queueProgressCard
                libraryStatsCard
                recentActionsCard
            }
        } else {
            HStack(alignment: .top, spacing: Spacing.md) {
                // Left Column
                VStack(spacing: Spacing.md) {
                    queueProgressCard
                    quickActionsCard
                }
                .frame(maxWidth: .infinity)

                // Middle Column
                VStack(spacing: Spacing.md) {
                    libraryStatsCard
                }
                .frame(maxWidth: .infinity)

                // Right Column
                VStack(spacing: Spacing.md) {
                    recentActionsCard
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Cards

    private var comicVineQuotaCard: some View {
        DashboardSectionCard(
            title: "ComicVine API",
            subtitle: "Metadata calls used this hour."
        ) {
            comicVineQuotaContent
        }
    }

    private var queueProgressCard: some View {
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
    }

    private var quickActionsCard: some View {
        DashboardSectionCard(title: "Quick Actions") {
                    VStack(spacing: Spacing.sm) {
                        Button(action: {
                            showingFilePicker = true
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
                            showingFolderScanner = true
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
                            onOpenKnowledge()
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

    private var libraryStatsCard: some View {
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

    private var recentActionsCard: some View {
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

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if HomeLibrarySetupPrompt.needsPrompt {
                pendingImportURLs = urls
                showingHomeLibraryPrompt = true
            } else {
                Task { await libraryViewModel.importComics(from: urls) }
            }
        case .failure(let error):
            AppLog.library.error(
                "Dashboard file import failed: \(error.localizedDescription)")
        }
    }

    /// Laid out for the full-width bar: count | progress | reset time.
    private var comicVineQuotaContent: some View {
        HStack(spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text("\(comicVineQuota.callsInLastHour)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(
                        comicVineQuota.callsInLastHour >= ComicVineQuota.hourlyLimit
                            ? AccentColors.error : TextColors.primary
                    )
                Text("/ \(ComicVineQuota.hourlyLimit) calls")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
            }
            .fixedSize()

            ProgressView(
                value: Double(min(comicVineQuota.callsInLastHour, ComicVineQuota.hourlyLimit)),
                total: Double(ComicVineQuota.hourlyLimit)
            )
            .tint(
                comicVineQuota.callsInLastHour >= ComicVineQuota.hourlyLimit
                    ? AccentColors.error : AccentColors.primary
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: Spacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                Text(
                    comicVineQuota.nextReset.map {
                        "More budget at \($0.formatted(date: .omitted, time: .shortened))"
                    } ?? "No calls yet this hour."
                )
                .font(Typography.caption)
            }
            .foregroundColor(TextColors.tertiary)
            .fixedSize()
        }
        .padding(.top, Spacing.sm)
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
