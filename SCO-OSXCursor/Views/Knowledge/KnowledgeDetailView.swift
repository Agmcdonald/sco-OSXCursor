//
//  KnowledgeDetailView.swift
//  SCO-OSXCursor
//
//  Drill-down for a Knowledge entry: stats and related books aggregated
//  live from the library. A series shows its issues, years, publisher and
//  contributors; a creator shows everything they're credited on; a
//  publisher shows its series.
//

import SwiftUI

struct KnowledgeDetailView: View {
    let entry: KnowledgeEntry
    let comics: [Comic]

    // MARK: - Matching

    /// Comics in the library that this entry describes.
    private var matches: [Comic] {
        comics.filter { matchesEntry($0) }
    }

    private func matchesEntry(_ comic: Comic) -> Bool {
        let name = entry.normalizedName

        func equals(_ value: String?) -> Bool {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name
        }
        // Credit fields can list several people ("A, B & C") — substring match
        func credits(_ value: String?) -> Bool {
            (value ?? "").lowercased().contains(name)
        }

        switch entry.type {
        case .series: return equals(comic.series)
        case .publisher: return equals(comic.publisher)
        case .writer: return credits(comic.writer)
        case .artist: return credits(comic.artist)
        case .coverArtist: return credits(comic.coverArtist)
        case .colorist: return credits(comic.colorist)
        case .inker: return credits(comic.inker)
        case .editor: return credits(comic.editor)
        }
    }

    // MARK: - Aggregates

    private var sortedMatches: [Comic] {
        matches.sorted { a, b in
            let seriesA = a.series ?? "", seriesB = b.series ?? ""
            if seriesA != seriesB {
                return seriesA.localizedCaseInsensitiveCompare(seriesB) == .orderedAscending
            }
            let issueA = Int(a.issueNumber ?? "") ?? Int.max
            let issueB = Int(b.issueNumber ?? "") ?? Int.max
            if issueA != issueB { return issueA < issueB }
            return (a.year ?? 0) < (b.year ?? 0)
        }
    }

    private var yearRange: String? {
        let years = matches.compactMap(\.year)
        guard let min = years.min(), let max = years.max() else { return nil }
        return min == max ? "\(min)" : "\(min)–\(max)"
    }

    private var publishers: [String] {
        distinct(matches.compactMap(\.publisher))
    }

    private var seriesBreakdown: [(name: String, count: Int)] {
        Dictionary(grouping: matches.compactMap(\.series), by: { $0.lowercased() })
            .compactMap { _, names in names.first.map { ($0, names.count) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    }

    private func distinct(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            // Credit fields may hold several names — split before de-duping
            for part in value.components(separatedBy: CharacterSet(charactersIn: ",&;"))
            where !part.trimmingCharacters(in: .whitespaces).isEmpty {
                let cleanPart = part.trimmingCharacters(in: .whitespaces)
                if seen.insert(cleanPart.lowercased()).inserted {
                    result.append(cleanPart)
                }
            }
        }
        return result.sorted()
    }

    private var contributorSections: [(role: String, names: [String])] {
        [
            ("Writers", distinct(matches.compactMap(\.writer))),
            ("Artists", distinct(matches.compactMap(\.artist))),
            ("Cover Artists", distinct(matches.compactMap(\.coverArtist))),
            ("Colorists", distinct(matches.compactMap(\.colorist))),
            ("Inkers", distinct(matches.compactMap(\.inker))),
            ("Editors", distinct(matches.compactMap(\.editor))),
        ].filter { !$0.1.isEmpty }
    }

    /// For creator entries: which roles this person appears under
    private var rolesHeld: [String] {
        var roles: [String] = []
        let name = entry.normalizedName
        func credited(_ keyPath: KeyPath<Comic, String?>) -> Bool {
            matches.contains { ($0[keyPath: keyPath] ?? "").lowercased().contains(name) }
        }
        if credited(\.writer) { roles.append("Writer") }
        if credited(\.artist) { roles.append("Artist") }
        if credited(\.coverArtist) { roles.append("Cover Artist") }
        if credited(\.colorist) { roles.append("Colorist") }
        if credited(\.inker) { roles.append("Inker") }
        if credited(\.editor) { roles.append("Editor") }
        return roles
    }

    private var isCreatorEntry: Bool {
        switch entry.type {
        case .series, .publisher: return false
        default: return true
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Title
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(entry.name)
                        .font(Typography.h2)
                        .foregroundColor(TextColors.primary)
                    Text(entry.type.displayName)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                }

                if matches.isEmpty {
                    Text("No books in your library reference this entry yet.")
                        .font(Typography.body)
                        .foregroundColor(TextColors.tertiary)
                        .padding(.top, Spacing.lg)
                } else {
                    // Stat chips
                    HStack(spacing: Spacing.md) {
                        statChip("\(matches.count)", label: matches.count == 1 ? "Book" : "Books")
                        if let yearRange {
                            statChip(yearRange, label: "Years")
                        }
                        if entry.type != .publisher, let publisher = publishers.first {
                            statChip(
                                publishers.count > 1
                                    ? "\(publisher) +\(publishers.count - 1)" : publisher,
                                label: "Publisher")
                        }
                        if entry.type != .series {
                            statChip("\(seriesBreakdown.count)", label: "Series")
                        }
                    }

                    // Roles (creators only)
                    if isCreatorEntry && !rolesHeld.isEmpty {
                        section("Credited As") {
                            Text(rolesHeld.joined(separator: " · "))
                                .font(Typography.body)
                                .foregroundColor(TextColors.primary)
                        }
                    }

                    // Series breakdown (publisher & creator entries)
                    if entry.type != .series && seriesBreakdown.count > 0 {
                        section("Series") {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                ForEach(seriesBreakdown, id: \.name) { item in
                                    HStack {
                                        Text(item.name)
                                            .font(Typography.body)
                                            .foregroundColor(TextColors.primary)
                                        Spacer()
                                        Text("\(item.count)")
                                            .font(Typography.caption)
                                            .foregroundColor(TextColors.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Contributors (series & publisher entries)
                    if !isCreatorEntry && !contributorSections.isEmpty {
                        section("Contributors") {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(contributorSections, id: \.role) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.role)
                                            .font(Typography.caption)
                                            .foregroundColor(TextColors.secondary)
                                        Text(item.names.joined(separator: ", "))
                                            .font(Typography.bodySmall)
                                            .foregroundColor(TextColors.primary)
                                    }
                                }
                            }
                        }
                    }

                    // Books
                    section(entry.type == .series ? "Issues" : "Books") {
                        VStack(spacing: Spacing.sm) {
                            ForEach(sortedMatches) { comic in
                                bookRow(comic)
                            }
                        }
                    }
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BackgroundColors.primary)
    }

    // MARK: - Components

    @ViewBuilder
    private func statChip(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Typography.bodySmall.weight(.semibold))
                .foregroundColor(TextColors.primary)
                .lineLimit(1)
            Text(label)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.h3)
                .foregroundColor(TextColors.primary)
            content()
        }
        .padding(.top, Spacing.sm)
    }

    @ViewBuilder
    private func bookRow(_ comic: Comic) -> some View {
        HStack(spacing: Spacing.md) {
            // Cover thumbnail
            if let coverData = comic.coverImageData,
                let cover = PageImageCache.shared.coverImage(
                    from: coverData, cacheKey: comic.id.uuidString)
            {
                #if os(macOS)
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                #else
                    Image(uiImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                #endif
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(BackgroundColors.elevated)
                    .frame(width: 32, height: 48)
                    .overlay(
                        Image(systemName: "book.closed")
                            .font(.system(size: 12))
                            .foregroundColor(TextColors.tertiary)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(comic.displayTitle)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(1)

                HStack(spacing: Spacing.sm) {
                    if entry.type != .publisher, let publisher = comic.publisher {
                        Text(publisher)
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                    }
                    Text(comic.bookFormat.displayName)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }
            }

            Spacer()

            if comic.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(SemanticColors.completed)
            }
        }
        .padding(Spacing.sm)
        .background(BackgroundColors.elevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
