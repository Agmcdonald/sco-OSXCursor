//
//  LibrarySelectionBottomBar.swift
//  SCO-OSXCursor
//
//  Touch-platform bulk actions for selection mode — a bar pinned over the
//  bottom of the grid (Stage 1 of SWIPE_SELECT_PLAN.md), matching the shape
//  Panels uses: a few frequent actions inline, everything else under More.
//
//  iOS/iPadOS only. macOS keeps the header-resident LibrarySelectionBar: a
//  floating bar over the content is a touch idiom, and the Mac header row
//  already has the width to show every action at once.
//

#if os(iOS)

    import SwiftUI

    struct LibrarySelectionBottomBar: View {
        let selectedCount: Int
        let actions: LibrarySelectionActions

        private var isEmpty: Bool { selectedCount == 0 }

        var body: some View {
            HStack(spacing: Spacing.xl) {
                barButton(
                    title: "Folder",
                    systemImage: "folder.badge.plus",
                    isMenu: true
                ) {
                    addToFolderMenu
                }

                barButton(title: "List", systemImage: "text.badge.plus") {
                    actions.onAddToList()
                }

                barButton(title: "Send", systemImage: "ipad.and.arrow.forward") {
                    actions.onSendToDevice()
                }

                barButton(
                    title: "Delete",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    actions.onDelete()
                }

                barButton(title: "More", systemImage: "ellipsis.circle", isMenu: true) {
                    moreMenu
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(BorderColors.subtle, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.sm)
            // The bar outlives an empty selection: a swipe can deselect its
            // way to zero mid-drag, and having the bar vanish under the
            // finger would be worse than showing disabled buttons.
            .animation(.easeInOut(duration: 0.2), value: isEmpty)
        }

        // MARK: - Menus

        @ViewBuilder
        private var addToFolderMenu: some View {
            ForEach(actions.folders) { folder in
                Button {
                    actions.onAddToFolder(folder.id)
                } label: {
                    Label(folder.name, systemImage: folder.icon ?? "folder")
                }
            }
            if !actions.folders.isEmpty { Divider() }
            Button(action: actions.onNewFolder) {
                Label("New Folder…", systemImage: "plus")
            }
        }

        @ViewBuilder
        private var moreMenu: some View {
            Button(action: actions.onMarkAsRead) {
                Label("Mark as Read", systemImage: "checkmark.circle")
            }
            Button(action: actions.onMarkAsUnread) {
                Label("Mark as Unread (Reset Progress)", systemImage: "book.closed")
            }

            Divider()

            Button(action: actions.onEditFields) {
                Label("Edit Fields…", systemImage: "square.and.pencil")
            }
            Button(action: actions.onFetchMetadata) {
                Label("Fetch Metadata", systemImage: "network")
            }
            .disabled(actions.isFetchingMetadata)
            Button(action: actions.onRegenerateCovers) {
                Label("Regenerate Cover", systemImage: "arrow.clockwise.circle")
            }

            let removable = actions.removalFolders()
            if !removable.isEmpty {
                Divider()
                Menu {
                    ForEach(removable) { folder in
                        Button {
                            actions.onRemoveFromFolder(folder.id)
                        } label: {
                            Label(folder.name, systemImage: folder.icon ?? "folder")
                        }
                    }
                } label: {
                    Label("Remove from Folder", systemImage: "folder.badge.minus")
                }
            }
        }

        // MARK: - Button Chrome

        /// Plain action button.
        private func barButton(
            title: String,
            systemImage: String,
            role: ButtonRole? = nil,
            action: @escaping () -> Void
        ) -> some View {
            Button(role: role) {
                guard !isEmpty else { return }
                action()
            } label: {
                barLabel(title: title, systemImage: systemImage, role: role)
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
        }

        /// Menu-backed button. Kept separate from the action form so the
        /// label styling stays in one place.
        private func barButton<Content: View>(
            title: String,
            systemImage: String,
            isMenu: Bool,
            @ViewBuilder content: () -> Content
        ) -> some View {
            Menu {
                content()
            } label: {
                barLabel(title: title, systemImage: systemImage, role: nil)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .disabled(isEmpty)
        }

        private func barLabel(
            title: String, systemImage: String, role: ButtonRole?
        ) -> some View {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(title)
                    .font(Typography.tiny)
            }
            .foregroundColor(tint(for: role))
            .frame(minWidth: 52)
            .contentShape(Rectangle())
        }

        private func tint(for role: ButtonRole?) -> Color {
            if isEmpty { return TextColors.tertiary }
            return role == .destructive ? .red : AccentColors.primary
        }
    }

#endif
