//
//  LearningView.swift
//  SCO-OSXCursor
//
//  Stage 3: shows what the app has learned — known series (with publisher,
//  format, aliases, and how often they've been used) and the history of
//  corrections it learned from.
//

import SwiftUI

struct LearningView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    @ObservedObject private var knowledge = SeriesKnowledge.shared
    @State private var corrections: [CorrectionRecord] = []
    @State private var searchText = ""

    /// Live count of books per series (normalized name) in the library —
    /// shown instead of the internal learning counter, which also ticks on
    /// corrections and would mislead (e.g. 13 books showing "21").
    private var libraryCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for comic in libraryViewModel.comics {
            guard let series = comic.series, !series.isEmpty else { continue }
            counts[SeriesKnowledgeRecord.normalize(series), default: 0] += 1
        }
        return counts
    }

    private var filteredRecords: [SeriesKnowledgeRecord] {
        let base: [SeriesKnowledgeRecord]
        if searchText.isEmpty {
            base = knowledge.records
        } else {
            let query = searchText.lowercased()
            base = knowledge.records.filter {
                $0.seriesName.lowercased().contains(query)
                    || ($0.publisher?.lowercased().contains(query) ?? false)
                    || $0.aliases.contains(where: { $0.contains(query) })
            }
        }
        // Stable display order: most books in library first, then alphabetical
        // (matches the count shown on each row)
        let counts = libraryCounts
        return base.sorted {
            let a = counts[$0.normalizedName] ?? 0
            let b = counts[$1.normalizedName] ?? 0
            if a != b { return a > b }
            return $0.seriesName.localizedCaseInsensitiveCompare($1.seriesName)
                == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Learning")
                    .font(Typography.h1)
                    .foregroundColor(TextColors.primary)
                Text(
                    "\(knowledge.records.count) learned series · the app uses these to identify new imports automatically"
                )
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.md)

            List {
                Section("Learned Series") {
                    if filteredRecords.isEmpty {
                        Text(
                            searchText.isEmpty
                                ? "Nothing learned yet — confirm imports in Organize and the app starts remembering."
                                : "No matches for \"\(searchText)\""
                        )
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.tertiary)
                    }

                    // Stable identity via normalizedName — records learned
                    // during this session have no DB id yet, and nil/duplicate
                    // ForEach ids scrambled row placement
                    ForEach(filteredRecords, id: \.normalizedName) { record in
                        seriesRow(record)
                            .contextMenu {
                                Button(role: .destructive) {
                                    knowledge.delete(record)
                                } label: {
                                    Label("Forget This Series", systemImage: "trash")
                                }
                            }
                    }
                }

                Section("Recent Corrections") {
                    if corrections.isEmpty {
                        Text("No corrections recorded yet.")
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.tertiary)
                    }

                    ForEach(Array(corrections.enumerated()), id: \.offset) { _, correction in
                        correctionRow(correction)
                    }
                }
            }
            #if os(macOS)
                .listStyle(.inset)
            #else
                .listStyle(.insetGrouped)
            #endif
        }
        .searchable(text: $searchText, prompt: "Search learned series")
        .task {
            await knowledge.loadIfNeeded()
            corrections =
                (try? await DatabaseManager.shared.fetchRecentCorrections(limit: 50)) ?? []
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func seriesRow(_ record: SeriesKnowledgeRecord) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: record.bookFormat.icon)
                .font(.system(size: 16))
                .foregroundColor(AccentColors.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.seriesName)
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)

                HStack(spacing: Spacing.sm) {
                    if let publisher = record.publisher {
                        Text(publisher)
                            .font(Typography.caption)
                            .foregroundColor(TextColors.secondary)
                    }
                    Text("Format: \(record.bookFormat.displayName)")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }

                if !record.aliases.isEmpty {
                    Text("Also known as: \(record.aliases.joined(separator: ", "))")
                        .font(Typography.caption)
                        .foregroundColor(AccentColors.primary.opacity(0.8))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Books of this series actually in the library right now
            let inLibrary = libraryCounts[record.normalizedName] ?? 0
            VStack(spacing: 1) {
                Text("\(inLibrary)")
                    .font(Typography.bodySmall.weight(.semibold))
                    .foregroundColor(TextColors.primary)
                Text("in library")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(BackgroundColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func correctionRow(_ correction: CorrectionRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let original = correction.originalSeries,
                let corrected = correction.correctedSeries,
                SeriesKnowledgeRecord.normalize(original)
                    != SeriesKnowledgeRecord.normalize(corrected)
            {
                HStack(spacing: Spacing.xs) {
                    Text(original)
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                        .strikethrough()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(TextColors.tertiary)
                    Text(corrected)
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.primary)
                }
            }

            if let correctedPublisher = correction.correctedPublisher,
                SeriesKnowledgeRecord.normalize(correction.originalPublisher ?? "")
                    != SeriesKnowledgeRecord.normalize(correctedPublisher)
            {
                Text("Publisher → \(correctedPublisher)")
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
            }

            HStack(spacing: Spacing.sm) {
                if let file = correction.sourceFileName {
                    Text(file)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(correction.createdAt, style: .date)
                    .font(Typography.caption)
                    .foregroundColor(TextColors.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview
#Preview {
    LearningView(libraryViewModel: LibraryViewModel(database: DatabaseManager.shared))
}
