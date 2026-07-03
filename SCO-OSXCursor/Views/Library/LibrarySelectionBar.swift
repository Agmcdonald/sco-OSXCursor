//
//  LibrarySelectionBar.swift
//  SCO-OSXCursor
//
//  Selection-mode action controls, extracted from LibraryView (Stage 4
//  split). Lives in the upper header; on iPad portrait the header wraps it
//  in a horizontal scroller so labels never get crushed.
//

import SwiftUI

struct LibrarySelectionBar: View {
    @Binding var selectedComics: Set<Comic.ID>
    /// IDs of the comics currently visible under the active filter/search —
    /// Select All operates on these, so "search a series → Select All →
    /// Edit Fields" fixes hundreds in three clicks.
    let visibleComicIDs: [Comic.ID]

    let onMarkAsRead: () -> Void
    var onMarkAsUnread: () -> Void = {}
    let onEditFields: () -> Void
    let onAddToList: () -> Void
    let onRegenerateCovers: () -> Void
    let onFetchMetadata: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void
    /// Disables the metadata button + shows a spinner while a batch runs.
    var isFetchingMetadata: Bool = false

    // Folders — bulk-move the whole selection into a folder.
    var folders: [Folder] = []
    var onAddToFolder: (UUID) -> Void = { _ in }
    var onNewFolder: () -> Void = {}
    /// Package the selection as .scobook files for AirDrop (macOS-only in v1).
    var onSendToDevice: () -> Void = {}

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text("\(selectedComics.count) selected")
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)

            // Select All / Deselect All — operates on the current
            // filter/search results
            Button(action: {
                let visibleIDs = Set(visibleComicIDs)
                if selectedComics.count < visibleIDs.count {
                    selectedComics = visibleIDs
                } else {
                    selectedComics.removeAll()
                }
            }) {
                Text(
                    selectedComics.count < visibleComicIDs.count
                        ? "Select All" : "Deselect All"
                )
                .font(Typography.bodySmall)
                .foregroundColor(AccentColors.primary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(AccentColors.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Mark as Read / Unread — one control so the bar doesn't grow
            Menu {
                Button(action: onMarkAsRead) {
                    Label("Mark as Read", systemImage: "checkmark.circle")
                }
                Button(action: onMarkAsUnread) {
                    Label("Mark as Unread (Reset Progress)", systemImage: "book.closed")
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle")
                    Text("Mark as…")
                        .font(Typography.bodySmall)
                }
                .foregroundColor(
                    selectedComics.isEmpty ? TextColors.tertiary : AccentColors.primary
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    selectedComics.isEmpty
                        ? BackgroundColors.elevated : AccentColors.primary.opacity(0.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(selectedComics.isEmpty)

            // Bulk Edit button — set series/publisher/year/format
            // on every selected book at once
            actionButton(
                title: "Edit Fields",
                systemImage: "square.and.pencil",
                action: onEditFields
            )

            // Add to Reading List button
            Button(action: {
                if !selectedComics.isEmpty {
                    onAddToList()
                }
            }) {
                HStack(spacing: Spacing.xs) {
                    Image("ReadingListIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text("Add to List")
                        .font(Typography.bodySmall)
                }
                .foregroundColor(
                    selectedComics.isEmpty ? TextColors.tertiary : AccentColors.primary
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    selectedComics.isEmpty
                        ? BackgroundColors.elevated : AccentColors.primary.opacity(0.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(selectedComics.isEmpty)

            // Add the whole selection to a folder (or a brand-new one)
            Menu {
                ForEach(folders) { folder in
                    Button(action: { onAddToFolder(folder.id) }) {
                        Label(folder.name, systemImage: folder.icon ?? "folder")
                    }
                }
                if !folders.isEmpty { Divider() }
                Button(action: onNewFolder) {
                    Label("New Folder…", systemImage: "plus")
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "folder.badge.plus")
                    Text("Add to Folder")
                        .font(Typography.bodySmall)
                }
                .foregroundColor(
                    selectedComics.isEmpty ? TextColors.tertiary : AccentColors.primary
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    selectedComics.isEmpty
                        ? BackgroundColors.elevated : AccentColors.primary.opacity(0.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .disabled(selectedComics.isEmpty)

            // Fetch ComicVine metadata for the whole selection
            Button(action: {
                if !selectedComics.isEmpty && !isFetchingMetadata {
                    onFetchMetadata()
                }
            }) {
                HStack(spacing: Spacing.xs) {
                    if isFetchingMetadata {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: "network")
                    }
                    Text("Fetch Metadata")
                        .font(Typography.bodySmall)
                }
                .foregroundColor(
                    selectedComics.isEmpty ? TextColors.tertiary : AccentColors.primary
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    selectedComics.isEmpty
                        ? BackgroundColors.elevated : AccentColors.primary.opacity(0.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(selectedComics.isEmpty || isFetchingMetadata)

            // Regenerate Cover button
            Button(action: {
                if !selectedComics.isEmpty {
                    onRegenerateCovers()
                }
            }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.clockwise.circle")
                    Text("Regenerate Cover")
                        .font(Typography.bodySmall)
                }
                .foregroundColor(
                    selectedComics.isEmpty ? TextColors.tertiary : TextColors.primary
                )
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(BackgroundColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(selectedComics.isEmpty)

            // Send the selection to another device (Mac → iPad transfer)
            #if os(macOS)
                actionButton(
                    title: "Send to Device",
                    systemImage: "ipad.and.arrow.forward",
                    action: onSendToDevice
                )
            #endif

            // Delete button
            Button(action: {
                if !selectedComics.isEmpty {
                    onDelete()
                }
            }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "trash")
                    Text("Delete")
                        .font(Typography.bodySmall)
                }
                .foregroundColor(selectedComics.isEmpty ? TextColors.tertiary : .red)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    selectedComics.isEmpty
                        ? BackgroundColors.elevated : Color.red.opacity(0.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(selectedComics.isEmpty)

            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .foregroundColor(TextColors.secondary)
        }
    }

    /// Standard accent-tinted action button, disabled when nothing selected.
    private func actionButton(
        title: String, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            if !selectedComics.isEmpty {
                action()
            }
        }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: systemImage)
                Text(title)
                    .font(Typography.bodySmall)
            }
            .foregroundColor(
                selectedComics.isEmpty ? TextColors.tertiary : AccentColors.primary
            )
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                selectedComics.isEmpty
                    ? BackgroundColors.elevated : AccentColors.primary.opacity(0.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(selectedComics.isEmpty)
    }
}
