//
//  KnowledgeViewModel.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/15/25.
//

import Combine
import Foundation
import GRDB  // For database access
import os

@MainActor
class KnowledgeViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedType: String = "series"  // "series", "publisher", "writer", "artist"
    @Published var entries: [KnowledgeEntry] = []
    @Published var publisherMappings: [String] = []  // Populated from publisher_mappings table
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Dependencies
    private let database: DatabaseManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializer
    init(database: DatabaseManager = .shared) {
        self.database = database

        // Setup search debounce (optional, simple fetch for now)
        $selectedType
            .sink { [weak self] _ in self?.fetchData() }
            .store(in: &cancellables)
    }

    // MARK: - Fetching
    func fetchData() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                // Fetch based on selected type
                guard let type = KnowledgeEntry.EntryType(rawValue: selectedType) else {
                    return
                }
                self.entries = try await database.fetchKnowledgeEntries(type: type)

                if !searchText.isEmpty {
                    self.entries = self.entries.filter {
                        $0.name.localizedCaseInsensitiveContains(searchText)
                    }
                }
            } catch {
                errorMessage = "Failed to load data: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    // MARK: - Actions
    func addEntry(name: String) {
        guard !name.isEmpty else { return }

        Task {
            do {
                guard let type = KnowledgeEntry.EntryType(rawValue: selectedType) else {
                    return
                }
                let entry = KnowledgeEntry(type: type, name: name)
                try await database.saveKnowledgeEntry(entry)
                fetchData()  // Refresh
            } catch {
                errorMessage = "Failed to add entry: \(error.localizedDescription)"
            }
        }
    }

    func deleteEntry(_ entry: KnowledgeEntry) {
        Task {
            do {
                try await database.deleteKnowledgeEntry(entry)
                fetchData()  // Refresh
            } catch {
                errorMessage = "Failed to delete entry: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Autocomplete Helpers
    // These will be called by the AutocompleteTextField
    func getSuggestions(for typeString: String, query: String) async -> [String] {
        guard !query.isEmpty else { return [] }

        do {
            if let type = KnowledgeEntry.EntryType(rawValue: typeString) {
                return try await database.searchKnowledge(type: type, query: query)
            }
        } catch {
            AppLog.learning.error("Autocomplete error: \(error)")
        }
        return []
    }
}
