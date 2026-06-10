//
//  KnowledgeView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/15/25.
//

import SwiftUI

struct KnowledgeView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel
    @StateObject private var viewModel = KnowledgeViewModel()
    @State private var isShowingAddSheet = false
    @State private var newEntryName = ""
    @State private var selectedEntry: KnowledgeEntry?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()
                .background(BorderColors.subtle)

            // Content
            #if os(macOS)
                HSplitView {
                    // Sidebar List
                    VStack(spacing: 0) {
                        searchBar
                            .padding(Spacing.md)

                        List(viewModel.entries) { entry in
                            HStack {
                                Text(entry.name)
                                    .font(Typography.body)
                                    .foregroundColor(TextColors.primary)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, Spacing.sm)
                            .background(
                                selectedEntry?.id == entry.id && selectedEntry?.type == entry.type
                                    ? AccentColors.primary.opacity(0.15) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedEntry = entry
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    if selectedEntry == entry { selectedEntry = nil }
                                    viewModel.deleteEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                    .frame(minWidth: 250, maxWidth: 350)

                    // Detail: live stats aggregated from the library
                    if let entry = selectedEntry {
                        KnowledgeDetailView(entry: entry, comics: libraryViewModel.comics)
                            .id("\(entry.type.rawValue)-\(entry.normalizedName)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack {
                            Text("Select an item to view usage statistics")
                                .font(Typography.body)
                                .foregroundColor(TextColors.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(BackgroundColors.primary)
                    }
                }
            #else
                VStack(spacing: 0) {
                    searchBar
                        .padding(Spacing.md)

                    List(viewModel.entries) { entry in
                        HStack {
                            Text(entry.name)
                                .font(Typography.body)
                                .foregroundColor(TextColors.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(TextColors.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEntry = entry
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteEntry(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                .sheet(item: $selectedEntry) { entry in
                    KnowledgeDetailView(entry: entry, comics: libraryViewModel.comics)
                }
            #endif
        }
        .background(BackgroundColors.sidebar)
        .onAppear {
            viewModel.fetchData()
        }
        .sheet(isPresented: $isShowingAddSheet) {
            VStack(spacing: Spacing.lg) {
                Text("Add New \(viewModel.selectedType.capitalized)")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)

                TextField("Name", text: $newEntryName)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 300)
                    .onSubmit {
                        if !newEntryName.isEmpty {
                            viewModel.addEntry(name: newEntryName)
                            newEntryName = ""
                            isShowingAddSheet = false
                        }
                    }

                HStack(spacing: Spacing.md) {
                    Button("Cancel") {
                        isShowingAddSheet = false
                        newEntryName = ""
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Add") {
                        viewModel.addEntry(name: newEntryName)
                        newEntryName = ""
                        isShowingAddSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newEntryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(Spacing.xl)
            .background(BackgroundColors.elevated)
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Knowledge Base")
                    .font(Typography.h1)
                    .foregroundColor(TextColors.primary)

                Spacer()

                Button(action: { isShowingAddSheet = true }) {
                    Label("Add Entry", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            Picker("Type", selection: $viewModel.selectedType) {
                ForEach(KnowledgeEntry.EntryType.allCases, id: \.rawValue) { type in
                    Text(type.pluralName).tag(type.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 400)
        }
        .padding(Spacing.xl)
        .background(BackgroundColors.primary)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(TextColors.tertiary)
            TextField("Search...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    viewModel.fetchData()
                }
        }
        .padding(Spacing.sm)
        .background(BackgroundColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
