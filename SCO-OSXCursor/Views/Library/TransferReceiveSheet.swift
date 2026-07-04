//
//  TransferReceiveSheet.swift
//  SCO-OSXCursor
//
//  Shown when a `.scobook` package is opened (AirDrop → "Open in Super
//  Comic Organizer", Files app, or macOS double-click). Flow:
//
//    • Book already in the library (same UUID or size+name)?
//      → offer "Update Progress & Metadata" vs "Keep Existing Copy".
//    • New book → cover + title + folder placement (existing folder,
//      new folder, or just the library — mirrors the Quick Add flow),
//      then a determinate import progress bar while the file is
//      extracted, verified, and filed into the local library.
//

import SwiftUI

struct TransferReceiveSheet: View {
    let package: IncomingBookPackage
    @ObservedObject var viewModel: LibraryViewModel
    let onDone: () -> Void

    private enum Phase {
        case duplicate(Comic)
        case chooseFolder
        case importing
        case failed(String)
    }

    @State private var phase: Phase = .chooseFolder
    @State private var progress: Double = 0
    @State private var newFolderName = ""
    @State private var hasDecidedPhase = false

    private var manifest: TransferManifest { package.manifest }

    private var trimmedNewName: String {
        newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().background(BorderColors.subtle)

            Group {
                switch phase {
                case .duplicate(let existing):
                    duplicateView(existing)
                case .chooseFolder:
                    folderChoiceView
                case .importing:
                    importingView
                case .failed(let message):
                    failedView(message)
                }
            }
        }
        #if os(macOS)
            .frame(width: 460, height: 560)
        #endif
        .background(BackgroundColors.primary)
        .interactiveDismissDisabled(isImporting)
        .onAppear { decideInitialPhase() }
    }

    private var isImporting: Bool {
        if case .importing = phase { return true }
        return false
    }

    private func decideInitialPhase() {
        guard !hasDecidedPhase else { return }
        hasDecidedPhase = true
        Task {
            // Cold launch via an incoming package can race the library load —
            // make sure comics/folders are in before the duplicate check.
            if viewModel.comics.isEmpty {
                await viewModel.loadComics()
                await viewModel.loadFolders()
            }
            if let existing = BookPackageImporter.findDuplicate(
                of: manifest, in: viewModel.comics)
            {
                phase = .duplicate(existing)
            } else {
                phase = .chooseFolder
            }
        }
    }

    // MARK: - Header (cover + title)

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            coverThumbnail

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Incoming Book")
                    .font(Typography.label)
                    .foregroundColor(TextColors.tertiary)
                Text(manifest.displayTitle)
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(2)
                if let publisher = manifest.metadata.publisher, !publisher.isEmpty {
                    Text(publisher)
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)
                }
                Text(receivedDetails)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.tertiary)
            }

            Spacer()

            Button {
                onDone()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(TextColors.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(isImporting)
            .help("Don't import")
        }
        .padding(Spacing.lg)
    }

    private var receivedDetails: String {
        var parts: [String] = ["Sent from \(manifest.sentFromPlatform)"]
        let state = manifest.readingState
        if state.totalPages > 0, state.currentPage > 0 {
            let pct = Int(
                Double(state.currentPage + 1) / Double(state.totalPages) * 100)
            parts.append("reading progress \(min(pct, 100))%")
        }
        if state.isOnReadingList { parts.append("on reading list") }
        if state.isFavorite { parts.append("favorite") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var coverThumbnail: some View {
        Group {
            #if os(macOS)
                if let data = package.coverData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    coverPlaceholder
                }
            #else
                if let data = package.coverData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    coverPlaceholder
                }
            #endif
        }
        .frame(width: 72, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var coverPlaceholder: some View {
        Rectangle()
            .fill(BackgroundColors.secondary)
            .overlay(
                Image(systemName: "book.closed")
                    .font(.system(size: 24))
                    .foregroundColor(TextColors.tertiary)
            )
    }

    // MARK: - Duplicate

    private func duplicateView(_ existing: Comic) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "books.vertical")
                    .foregroundColor(AccentColors.primary)
                Text("Already in your library")
                    .font(Typography.h3)
                    .foregroundColor(TextColors.primary)
            }

            Text(
                "This book is already here. You can update your copy with the incoming reading progress and metadata, or keep it exactly as it is — the book file itself won't change either way."
            )
            .font(Typography.bodySmall)
            .foregroundColor(TextColors.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(spacing: Spacing.sm) {
                Button {
                    updateExisting(existing)
                } label: {
                    Label(
                        "Update Progress & Metadata",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(Typography.button)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.borderedProminent)
                .tint(AccentColors.primary)

                Button {
                    BookPackageImporter.cleanUp(package)
                    onDone()
                } label: {
                    Text("Keep Existing Copy")
                        .font(Typography.button)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.lg)
    }

    // MARK: - Folder Choice (new book)

    private var folderChoiceView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("Add it to a collection, or just add it to your library.")
                        .font(Typography.bodySmall)
                        .foregroundColor(TextColors.secondary)

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
                                        importNew(choice: .new(trimmedNewName))
                                    }
                                }
                            Button("Create & Add") {
                                importNew(choice: .new(trimmedNewName))
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
                    if !viewModel.folders.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Existing Folder")
                                .font(Typography.label)
                                .foregroundColor(TextColors.tertiary)
                            VStack(spacing: Spacing.xs) {
                                ForEach(viewModel.folders) { folder in
                                    Button {
                                        importNew(choice: .existing(folder.id))
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

            Button {
                importNew(choice: .none)
            } label: {
                Text("Just Add to Library")
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
    }

    // MARK: - Importing

    private var importingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ProgressView(value: progress) {
                Text("Adding to your library…")
                    .font(Typography.body)
                    .foregroundColor(TextColors.primary)
            }
            .progressViewStyle(.linear)
            .tint(AccentColors.primary)
            .frame(maxWidth: 300)

            Text("\(Int(progress * 100))%")
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
            Spacer()
        }
        .padding(Spacing.lg)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(AccentColors.warning)
            Text(message)
                .font(Typography.body)
                .foregroundColor(TextColors.secondary)
                .multilineTextAlignment(.center)
            Button("Close") { onDone() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(Spacing.lg)
    }

    // MARK: - Actions

    /// Duplicate → overwrite the library copy's progress/metadata/prefs with
    /// the incoming manifest (file and dateAdded untouched).
    private func updateExisting(_ existing: Comic) {
        let updated = manifest.apply(to: existing, coverData: package.coverData)
        viewModel.updateComic(updated)
        BookPackageImporter.cleanUp(package)
        onDone()
    }

    /// New book → extract, verify, file into the local library, persist, and
    /// apply the folder choice.
    private func importNew(choice: ImportFolderChoice) {
        phase = .importing
        progress = 0

        Task {
            do {
                let receiveRoot = try BookPackageImporter.resolveReceiveRoot()
                let folderStructure = AppSettings.load().folderStructure
                let incoming = package

                let comic = try await Task.detached(priority: .userInitiated) {
                    try BookPackageImporter.importNewBook(
                        package: incoming,
                        receiveRoot: receiveRoot,
                        folderStructure: folderStructure
                    ) { fraction in
                        Task { @MainActor in progress = fraction }
                    }
                }.value
                AppLog.files.info("[TransferReceiveSheet] ⏱ importNewBook returned: \(comic.fileName)")

                await viewModel.addTransferredComic(comic)
                AppLog.files.info("[TransferReceiveSheet] ⏱ addTransferredComic done")

                switch choice {
                case .none:
                    break
                case .existing(let folderID):
                    await viewModel.addComics([comic.id], toFolder: folderID)
                case .new(let name):
                    if let folder = await viewModel.createFolder(named: name) {
                        await viewModel.addComics([comic.id], toFolder: folder.id)
                    }
                }
                AppLog.files.info("[TransferReceiveSheet] ⏱ folder choice applied")

                BookPackageImporter.cleanUp(package)
                AppLog.files.info("[TransferReceiveSheet] ⏱ cleanUp done — calling onDone")
                onDone()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
