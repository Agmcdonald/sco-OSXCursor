//
//  FolderBarView.swift
//  SCO-OSXCursor
//
//  Compact scope bar below the library header. Three quick scopes — All Books,
//  Unfiled (books in no folder), and a "Folders" dropdown that lists every
//  collection alphabetically with its count — keep the bar tidy no matter how
//  many folders exist. Selecting a folder scopes the grid to it; full folder
//  management (rename / delete / sorting) lives in the Folder view.
//

import SwiftUI

struct FolderBarView: View {
    let folders: [Folder]
    @Binding var scope: LibraryScope
    /// Book count for a given folder id.
    let folderCount: (UUID) -> Int
    /// Total books in the whole library (for "All Books").
    let totalCount: Int
    /// Books not in any folder (for "Unfiled").
    let unfiledCount: Int
    let onNewFolder: () -> Void

    /// Folders A→Z for the dropdown.
    private var alphabetical: [Folder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Name of the folder currently scoped, if any.
    private var activeFolderName: String? {
        if case let .folder(id) = scope {
            return folders.first(where: { $0.id == id })?.name
        }
        return nil
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                chip(
                    title: "All Books",
                    systemImage: "books.vertical",
                    count: totalCount,
                    isSelected: scope == .all,
                    action: { scope = .all }
                )

                chip(
                    title: "Unfiled",
                    systemImage: "tray",
                    count: unfiledCount,
                    isSelected: scope == .unfiled,
                    action: { scope = .unfiled }
                )

                // Folders dropdown — alphabetical, tidy regardless of count.
                Menu {
                    if alphabetical.isEmpty {
                        Text("No folders yet")
                    } else {
                        ForEach(alphabetical) { folder in
                            Button(action: { scope = .folder(folder.id) }) {
                                Label(
                                    "\(folder.name)  (\(folderCount(folder.id)))",
                                    systemImage: folder.icon ?? "folder")
                            }
                        }
                    }
                    Divider()
                    Button(action: onNewFolder) {
                        Label("New Folder…", systemImage: "plus")
                    }
                } label: {
                    foldersLabel
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Folders dropdown label

    private var foldersLabel: some View {
        let active = activeFolderName
        let selected = active != nil
        return HStack(spacing: Spacing.xs) {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
            Text(active ?? "Folders")
                .font(Typography.bodySmall)
                .lineLimit(1)
            if case let .folder(id) = scope {
                Text("\(folderCount(id))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(selected ? .white : TextColors.primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(selected ? AccentColors.primary : BackgroundColors.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.clear : BorderColors.subtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Chip

    private func chip(
        title: String,
        systemImage: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(Typography.bodySmall)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : TextColors.tertiary)
            }
            .foregroundColor(isSelected ? .white : TextColors.primary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? AccentColors.primary : BackgroundColors.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : BorderColors.subtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
