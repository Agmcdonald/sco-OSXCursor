//
//  AutocompleteTextField.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/15/25.
//

import SwiftUI

struct AutocompleteTextField: View {
    let title: String
    @Binding var text: String
    let fetchSuggestions: (String) async -> [String]
    var onCommit: (() -> Void)? = nil

    @State private var suggestions: [String] = []
    @State private var isShowingSuggestions = false
    @State private var debateTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(
                title, text: $text,
                onCommit: {
                    onCommit?()
                    isShowingSuggestions = false
                }
            )
            .focused($isFocused)
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundColor(TextColors.primary)
            .padding(Spacing.md)
            .background(BackgroundColors.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(BorderColors.subtle, lineWidth: 1)
            )
            .onChange(of: text) { _, newValue in
                guard isFocused else { return }
                performDebouncedSearch(query: newValue)
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    // Delay hiding to allow tap on suggestion
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isShowingSuggestions = false
                    }
                }
            }

            // Suggestions dropdown
            if isShowingSuggestions && !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(action: {
                                text = suggestion
                                isShowingSuggestions = false
                                onCommit?()
                            }) {
                                Text(suggestion)
                                    .font(Typography.body)
                                    .foregroundColor(TextColors.primary)
                                    .padding(.vertical, Spacing.sm)
                                    .padding(.horizontal, Spacing.md)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                // Optional: hover effect
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
                .frame(maxHeight: 200)
                .background(BackgroundColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BorderColors.subtle, lineWidth: 1)
                )
                .offset(y: Spacing.xs)
                .zIndex(1)  // Ensure it floats above other content
            }
        }
        .zIndex(isShowingSuggestions ? 1 : 0)  // Ensure parent ZStack renders this on top
    }

    private func performDebouncedSearch(query: String) {
        debateTask?.cancel()

        guard !query.isEmpty else {
            suggestions = []
            isShowingSuggestions = false
            return
        }

        debateTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms debounce
            if Task.isCancelled { return }

            let results = await fetchSuggestions(query)

            await MainActor.run {
                self.suggestions = results
                self.isShowingSuggestions = !results.isEmpty
            }
        }
    }
}
