//
//  OrganizeInspectorView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 2/15/26.
//

import Foundation
import SwiftUI

struct OrganizeInspectorView: View {
    @ObservedObject var viewModel: OrganizeViewModel
    @StateObject private var knowledgeViewModel = KnowledgeViewModel()

    // Local state for editing
    @State private var series: String
    @State private var issueNumber: String
    @State private var year: Int
    @State private var publisher: String
    @State private var volume: Int?

    let comic: StagedComic

    init(comic: StagedComic, viewModel: OrganizeViewModel) {
        self.comic = comic
        self.viewModel = viewModel

        // Init state from comic
        _series = State(initialValue: comic.series)
        _issueNumber = State(initialValue: comic.issueNumber ?? "")
        _year = State(initialValue: comic.year ?? 0)
        _publisher = State(initialValue: comic.publisher ?? "")
        _volume = State(initialValue: comic.volume)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {  // Spacing.lg -> 16
                // Header
                HStack {
                    Text("File Details")
                        .font(.title3)  // Typography.h3 -> .title3
                    Spacer()

                    // Confidence Badge
                    Text(comic.confidence.rawValue)
                        .font(.caption)  // Typography.caption -> .caption
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(comic.confidence.color.opacity(0.2))
                        .foregroundColor(comic.confidence.color)
                        .cornerRadius(4)
                }

                Text(comic.originalFileName)
                    .font(.caption)  // Typography.caption -> .caption
                    .foregroundColor(.secondary)  // TextColors.tertiary -> .secondary

                Divider()

                // Form Fields
                Group {
                    // Series
                    VStack(alignment: .leading, spacing: 4) {  // Spacing.xs -> 4
                        Text("Series")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        AutocompleteTextField(
                            title: "Series Name",
                            text: $series,
                            fetchSuggestions: { query in
                                await knowledgeViewModel.getSuggestions(for: "series", query: query)
                            }
                        )
                        .zIndex(2)
                    }

                    HStack(spacing: 12) {  // Spacing.md -> 12
                        // Issue
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Issue")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("001", text: $issueNumber)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        // Volume
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Volume")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("1", value: $volume, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        // Year
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Year")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("YYYY", value: $year, formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }

                    // Publisher
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Publisher")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        AutocompleteTextField(
                            title: "Unknown Publisher",
                            text: $publisher,
                            fetchSuggestions: { query in
                                await knowledgeViewModel.getSuggestions(
                                    for: "publisher", query: query)
                            }
                        )
                        .zIndex(1)
                    }
                }
                .onChange(of: series) { _ in update() }
                .onChange(of: issueNumber) { _ in update() }
                .onChange(of: year) { _ in update() }
                .onChange(of: publisher) { _ in update() }
                .onChange(of: volume) { _ in update() }

                Divider()

                // Actions
                HStack {
                    Button("Import to Library") {
                        Task {
                            update()
                            await viewModel.confirmMatch(comic)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(series.isEmpty || issueNumber.isEmpty)
                }
                .frame(maxWidth: .infinity)

            }
            .padding()
        }
        #if os(macOS)
            .background(Color(NSColor.textBackgroundColor))  // Approximate BackgroundColors.secondary
        #else
            .background(Color(.systemBackground))
        #endif
        .onAppear {
            // Sync auto-parsed metadata back to viewModel so confirmMatch reads current values
            update()
        }
    }

    private func update() {
        Task { @MainActor in
            viewModel.updateMetadata(
                id: comic.id,
                series: series,
                issue: issueNumber,
                year: year,
                publisher: publisher,
                volume: volume
            )
        }
    }
}
