import SwiftUI

struct DashboardActivityView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    @State private var events: [ActivityEvent] = []
    @State private var isLoading = true
    @State private var filterAction: ActivityEvent.ActionType? = nil

    private var filteredEvents: [ActivityEvent] {
        guard let filter = filterAction else { return events }
        return events.filter { $0.action == filter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            DashboardSectionCard(
                title: "Recent Activity",
                subtitle: "Last 50 changes to your library and knowledge base"
            ) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ActivityFilterChip(label: "All", isSelected: filterAction == nil) {
                                filterAction = nil
                            }
                            ForEach(ActivityEvent.ActionType.allCases, id: \.self) { type in
                                if events.contains(where: { $0.action == type }) {
                                    ActivityFilterChip(
                                        label: type.displayName,
                                        icon: type.icon,
                                        isSelected: filterAction == type
                                    ) {
                                        filterAction = (filterAction == type) ? nil : type
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView().padding()
                            Spacer()
                        }
                    } else if filteredEvents.isEmpty {
                        VStack(spacing: Spacing.sm) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 36))
                                .foregroundColor(TextColors.tertiary)
                            Text("No activity yet")
                                .font(Typography.bodySmall)
                                .foregroundColor(TextColors.secondary)
                            Text("Changes to your library will appear here")
                                .font(Typography.caption)
                                .foregroundColor(TextColors.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredEvents.enumerated()), id: \.element.id) {
                                _, event in
                                ActivityEventRow(event: event, comics: libraryViewModel.comics)
                                if event.id != filteredEvents.last?.id {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadActivity()
        }
        .onChange(of: libraryViewModel.comics.count) {
            Task { await loadActivity() }
        }
    }

    private func loadActivity() async {
        isLoading = true
        events = (try? await DatabaseManager.shared.fetchRecentActivity(limit: 50)) ?? []
        isLoading = false
    }
}

// MARK: - Activity Event Row

struct ActivityEventRow: View {
    let event: ActivityEvent
    let comics: [Comic]

    private var comicName: String? {
        guard let cid = event.comicId, let uuid = UUID(uuidString: cid) else { return nil }
        return comics.first(where: { $0.id == uuid })?.displayName ?? event.newValue
    }

    private var iconColor: Color {
        switch event.action.color {
        case "blue": return AccentColors.primary
        case "red": return .red
        case "orange": return .orange
        case "green": return .green
        case "pink": return .pink
        case "purple": return .purple
        default: return TextColors.secondary
        }
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(event.timestamp)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: event.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: event.action.icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.action.displayName)
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.primary)
                    Spacer()
                    Text(timeAgo)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }

                if let name = comicName {
                    Text(name)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        .lineLimit(1)
                }

                // Show diff if both old and new are present
                if let old = event.oldValue, let new = event.newValue,
                    !old.isEmpty, !new.isEmpty, old != new
                {
                    HStack(spacing: 4) {
                        Text(old)
                            .strikethrough()
                            .foregroundColor(TextColors.tertiary)
                        Image(systemName: "arrow.right")
                            .foregroundColor(TextColors.tertiary)
                        Text(new)
                            .foregroundColor(AccentColors.primary)
                    }
                    .font(Typography.caption)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Filter Chip

struct ActivityFilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(label)
                    .font(Typography.caption)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 5)
            .background(
                isSelected ? AccentColors.primary.opacity(0.15) : BackgroundColors.secondary
            )
            .foregroundColor(isSelected ? AccentColors.primary : TextColors.secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? AccentColors.primary.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
