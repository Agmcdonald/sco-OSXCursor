//
//  ImportFolderChoiceSheet.swift
//  SCO-OSXCursor
//
//  Shown at the start of a multi-book import (Quick Add). Lets the user file
//  the incoming books into a new or existing folder, or just import them to
//  the library. Single-book imports skip this entirely.
//

import SwiftUI

enum ImportFolderChoice {
    case none
    case existing(UUID)
    case new(String)
}

struct ImportFolderChoiceSheet: View {
    /// e.g. "12 books" or "these books" (folder import).
    let bookCountText: String
    /// Existing folders, already sorted for display.
    let folders: [Folder]
    let onChoice: (ImportFolderChoice) -> Void
    let onCancel: () -> Void

    @State private var newFolderName = ""

    private var trimmedNewName: String {
        newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().background(BorderColors.subtle)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // New folder
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("New Folder")
                            .font(Typography.label)
                            .foregroundColor(TextColors.tertiary)
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(AccentColors.primary)
                            TextField("Folder name", text: $newFolderName)
                                .textFieldStyle(.plain)
                                .font(Typography.body)
                                .onSubmit {
                                    if !trimmedNewName.isEmpty {
                                        onChoice(.new(trimmedNewName))
                                    }
                                }
                            Button("Create & Add") {
                                onChoice(.new(trimmedNewName))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(
                                trimmedNewName.isEmpty
                                    ? TextColors.tertiary : AccentColors.primary
                            )
                            .disabled(trimmedNewName.isEmpty)
                        }
                        .padding(Spacing.md)
                        .background(BackgroundColors.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Existing folders
                    if !folders.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Existing Folder")
                                .font(Typography.label)
                                .foregroundColor(TextColors.tertiary)
                            VStack(spacing: Spacing.xs) {
                                ForEach(folders) { folder in
                                    Button {
                                        onChoice(.existing(folder.id))
                                    } label: {
                                        HStack(spacing: Spacing.sm) {
                                            Image(systemName: folder.icon ?? "folder")
                                                .foregroundColor(AccentColors.primary)
                                            Text(folder.name)
                                                .font(Typography.body)
                                                .foregroundColor(TextColors.primary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12))
                                                .foregroundColor(TextColors.tertiary)
                                        }
                                        .padding(Spacing.md)
                                        .background(BackgroundColors.elevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }

            Divider().background(BorderColors.subtle)

            // Just import
            Button {
                onChoice(.none)
            } label: {
                Text("Just Import to Library")
                    .font(Typography.button)
                    .foregroundColor(TextColors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(BackgroundColors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(Spacing.lg)
        }
        #if os(macOS)
            .frame(width: 460, height: 560)
        #endif
        .background(BackgroundColors.primary)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Add to a Folder?")
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
                Text("You're importing \(bookCountText). Add them to a collection, or just import to your library.")
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(TextColors.tertiary)
            }
            .buttonStyle(.plain)
            .help("Cancel import")
        }
        .padding(Spacing.lg)
    }
}
