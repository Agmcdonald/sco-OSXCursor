//
//  LibraryFilterPanel.swift
//  SCO-OSXCursor
//
//  Filter panel, active-filter badges, and their chip/badge building blocks,
//  extracted from LibraryView (Stage 4 split). All filter state lives in a
//  single LibraryFilters value (see LibraryModels.swift).
//

import SwiftUI

// MARK: - Active Filter Badges

struct LibraryFilterBadgesRow: View {
    @Binding var filters: LibraryFilters

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                if let status = filters.status {
                    FilterBadge(
                        title: "Status: \(status.displayLabel)",
                        icon: status.icon,
                        onRemove: { filters.status = nil }
                    )
                }

                if filters.readingList {
                    FilterBadge(
                        title: "Want to Read",
                        icon: "bookmark.fill",
                        onRemove: { filters.readingList = false }
                    )
                }

                if let publisher = filters.publisher {
                    FilterBadge(
                        title: "Publisher: \(publisher)",
                        icon: "building.2",
                        onRemove: { filters.publisher = nil }
                    )
                }

                if let series = filters.series {
                    FilterBadge(
                        title: "Series: \(series)",
                        icon: "books.vertical",
                        onRemove: { filters.series = nil }
                    )
                }

                if let year = filters.year {
                    FilterBadge(
                        title: "Year: \(String(year))",
                        icon: "calendar",
                        onRemove: { filters.year = nil }
                    )
                }

                // Clear all button
                Button(action: { filters.clear() }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Clear All")
                            .font(Typography.caption)
                    }
                    .foregroundColor(TextColors.tertiary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(BackgroundColors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
        }
    }
}

// MARK: - Filter Panel

struct LibraryFilterPanel: View {
    @Binding var filters: LibraryFilters
    let publishers: [String]
    let series: [String]
    let years: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Filters")
                .font(Typography.h3)
                .foregroundColor(TextColors.primary)

            // Status filter
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Status")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                HStack(spacing: Spacing.sm) {
                    FilterChip(
                        title: "All",
                        isSelected: filters.status == nil && !filters.readingList,
                        action: {
                            filters.status = nil
                            filters.readingList = false
                        }
                    )

                    ForEach(Comic.Status.allCases, id: \.self) { status in
                        FilterChip(
                            title: status.displayLabel,
                            icon: status.icon,
                            color: status.color,
                            isSelected: filters.status == status,
                            action: {
                                filters.status = status
                                filters.readingList = false
                            }
                        )
                    }

                    // Reading list chip
                    FilterChip(
                        title: "Want to Read",
                        icon: "bookmark.fill",
                        color: AccentColors.primary,
                        isSelected: filters.readingList,
                        action: {
                            filters.readingList = true
                            filters.status = nil
                        }
                    )
                }
            }

            // Publisher filter
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Publisher")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        FilterChip(
                            title: "All",
                            isSelected: filters.publisher == nil,
                            action: { filters.publisher = nil }
                        )

                        ForEach(publishers, id: \.self) { publisher in
                            FilterChip(
                                title: publisher,
                                isSelected: filters.publisher == publisher,
                                action: { filters.publisher = publisher }
                            )
                        }
                    }
                }
            }

            // Series filter
            if !series.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Series")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            FilterChip(
                                title: "All",
                                isSelected: filters.series == nil,
                                action: { filters.series = nil }
                            )

                            ForEach(series, id: \.self) { seriesName in
                                FilterChip(
                                    title: seriesName,
                                    isSelected: filters.series == seriesName,
                                    action: { filters.series = seriesName }
                                )
                            }
                        }
                    }
                }
            }

            // Year filter
            if !years.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Year")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            FilterChip(
                                title: "All",
                                isSelected: filters.year == nil,
                                action: { filters.year = nil }
                            )

                            ForEach(years, id: \.self) { year in
                                FilterChip(
                                    title: String(year),
                                    isSelected: filters.year == year,
                                    action: { filters.year = year }
                                )
                            }
                        }
                    }
                }
            }

            // Clear all filters
            if filters.hasActive {
                Button(action: { filters.clear() }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Clear All Filters")
                            .font(Typography.bodySmall)
                    }
                    .foregroundColor(TextColors.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.lg)
        .background(BackgroundColors.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    var color: Color? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }

                Text(title)
                    .font(Typography.bodySmall)
            }
            .foregroundColor(isSelected ? (color ?? AccentColors.primary) : TextColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                isSelected
                    ? (color ?? AccentColors.primary).opacity(0.12) : BackgroundColors.elevated
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? (color ?? AccentColors.primary) : BorderColors.subtle,
                        lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Badge

struct FilterBadge: View {
    let title: String
    var icon: String? = nil
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
            }

            Text(title)
                .font(Typography.caption)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(TextColors.tertiary)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(TextColors.primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(AccentColors.primary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AccentColors.primary.opacity(0.3), lineWidth: 1)
        )
    }
}
