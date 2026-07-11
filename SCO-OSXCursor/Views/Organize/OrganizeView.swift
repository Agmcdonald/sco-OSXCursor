//
//  OrganizeView.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 2/15/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct OrganizeView: View {
    @ObservedObject var viewModel: OrganizeViewModel
    /// Navigates to the Settings tab (wired by ContentView) — used by the
    /// "no home library folder" banner.
    var onOpenSettings: () -> Void = {}
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @State private var hideHomeFolderBanner = false
    @State private var showingBulkEdit = false
    @State private var showingFolderPrompt = false
    @State private var folderPromptMode: FolderPromptMode = .allReady
    @State private var isDropTargeted = false
    /// Routes dropped/opened `.scobook` transfer packages into the shared
    /// receive flow instead of the staging pipeline, which only understands
    /// plain comic files.
    @EnvironmentObject private var incomingTransferCoordinator: IncomingTransferCoordinator

    #if os(iOS)
        @State private var iosColumnVisibility: NavigationSplitViewVisibility = .all
        @State private var showingAddFilePicker = false
    #endif

    /// Which set of staged books the folder prompt applies to.
    private enum FolderPromptMode { case allReady, checked }

    /// Splits dropped/opened URLs into `.scobook` transfer packages (routed
    /// to the shared receive flow) and plain comic files (staged for
    /// review). Shared by the macOS and iOS drop handlers.
    private func routeDroppedURLs(_ urls: [URL]) {
        let scobookURLs = urls.filter {
            $0.pathExtension.lowercased() == BookPackage.fileExtension
        }
        let otherURLs = urls.filter {
            $0.pathExtension.lowercased() != BookPackage.fileExtension
        }

        if !scobookURLs.isEmpty {
            incomingTransferCoordinator.enqueue(urls: scobookURLs)
        }
        if !otherURLs.isEmpty {
            Task { await viewModel.addFiles(otherURLs) }
        }
    }

    // MARK: - Home Folder Banner

    /// Shown while no home library folder is set: imports still work, but
    /// files stay where they are instead of being moved and organized.
    private var showsHomeFolderBanner: Bool {
        settingsViewModel.settings.rootLibraryPath == nil && !hideHomeFolderBanner
    }

    private var homeFolderBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .foregroundColor(.orange)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("No home library folder set")
                    .font(.caption.weight(.semibold))
                Text("Imported books will stay in their current location. Choose a home folder and they'll be moved and organized automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Open Settings") {
                onOpenSettings()
            }
            .font(.caption)

            Button {
                hideHomeFolderBanner = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide for now")
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    var body: some View {
        #if os(macOS)
            VStack(spacing: 0) {
                HSplitView {
                // Left: File List (Staging Area)
                VStack(spacing: 0) {
                    // Header / Toolbar
                    HStack {
                        Text("File Processor")
                            .font(.title3)

                        Spacer()

                        Button(action: {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = true
                            panel.canChooseDirectories = false
                            panel.canCreateDirectories = false
                            let types = [
                                UTType(filenameExtension: "cbz"), UTType(filenameExtension: "cbr"),
                                UTType(filenameExtension: "epub"), .pdf, .epub,
                                UTType(exportedAs: BookPackage.typeIdentifier),
                            ].compactMap { $0 }
                            panel.allowedContentTypes = types

                            panel.begin { response in
                                if response == .OK {
                                    routeDroppedURLs(panel.urls)
                                }
                            }
                        }) {
                            Label("Add Files...", systemImage: "plus")
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            // Recursively scan a folder for comic files
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = true
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = false

                            panel.begin { response in
                                if response == .OK {
                                    Task {
                                        await viewModel.addFiles(panel.urls)
                                    }
                                }
                            }
                        }) {
                            Label("Scan Folder...", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Home-folder nudge — imports work without one, but books
                    // won't be moved into an organized library
                    if showsHomeFolderBanner {
                        homeFolderBanner
                    }

                    // List
                    List(viewModel.stagedComics, selection: $viewModel.selectedComicID) { comic in
                        HStack(spacing: 8) {
                            // Checkbox
                            Image(
                                systemName: viewModel.checkedComicIDs.contains(comic.id)
                                    ? "checkmark.square.fill" : "square"
                            )
                            .foregroundColor(
                                viewModel.checkedComicIDs.contains(comic.id)
                                    ? .accentColor : .secondary
                            )
                            .onTapGesture {
                                viewModel.toggleCheck(for: comic.id)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(comic.proposedFileName)
                                    .font(.body)
                                    .foregroundColor(.primary)

                                HStack {
                                    Text(comic.originalFileName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    if comic.status == .ready {
                                        Text("Ready")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 4)
                                            .background(Color.green.opacity(0.1))
                                            .cornerRadius(4)
                                    } else {
                                        Text("Pending")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(comic.id)
                    }
                    .listStyle(.sidebar)

                    // Empty State / Drop Zone
                    if viewModel.stagedComics.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("Drag and drop comic files here")
                                .font(.body)
                                .foregroundColor(.secondary)

                            // First-run mini guide: the three steps from
                            // file on disk to book in the library
                            VStack(alignment: .leading, spacing: 8) {
                                guideRow(1, "Add books — drop CBZ, CBR, PDF, or EPUB files here, or use Add Files / Scan Folder above")
                                guideRow(2, "Select a file to review its details. Fill the fields marked in orange, or let Fetch from ComicVine do it")
                                guideRow(3, "Import books one at a time, or everything marked Ready at once with Apply All Ready")
                            }
                            .padding(12)
                            .frame(maxWidth: 360)
                            .background(Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 300)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                }
                .overlay(
                    Group {
                        if isDropTargeted {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    Color.accentColor,
                                    style: StrokeStyle(lineWidth: 2, dash: [8])
                                )
                                .background(Color.accentColor.opacity(0.08))
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    }
                )

                // Right: Inspector / Editor
                if let selected = viewModel.selectedComic {
                    OrganizeInspectorView(comic: selected, viewModel: viewModel)
                        // Rebuild on selection change AND when a batch fetch
                        // updates staged metadata behind the inspector's back.
                        .id("\(selected.id.uuidString)-\(viewModel.metadataRevision)")
                        .frame(minWidth: 300)
                } else {
                    VStack {
                        Text("Select a file to review details")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                }
                }

                // Batch Action Bar — spans the full window width beneath both
                // panes, so button sizing is dictated by the window and never
                // squished by the File Details panel.
                if !viewModel.stagedComics.isEmpty {
                    Divider()
                    batchActionBar
                }
            }
            .sheet(isPresented: $showingBulkEdit) {
                BulkEditSheet(
                    itemCount: viewModel.checkedComicIDs.count,
                    showsContentRating: false
                ) { values in
                    viewModel.bulkUpdate(ids: viewModel.checkedComicIDs, values: values)
                }
            }
            .sheet(isPresented: $showingFolderPrompt) {
                let count =
                    folderPromptMode == .checked ? viewModel.checkedCount : viewModel.readyCount
                ImportFolderChoiceSheet(
                    bookCountText: "\(count) book\(count == 1 ? "" : "s")",
                    folders: viewModel.availableFolders,
                    onChoice: { choice in
                        showingFolderPrompt = false
                        let mode = folderPromptMode
                        Task {
                            switch mode {
                            case .allReady:
                                await viewModel.confirmAllReady(folderChoice: choice)
                            case .checked:
                                await viewModel.confirmChecked(folderChoice: choice)
                            }
                        }
                    },
                    onCancel: { showingFolderPrompt = false }
                )
            }
        #else
            iOSBody
        #endif
    }

    #if os(macOS)
        // MARK: - Batch Action Bar

        /// Full-width action bar shown while files are staged. Lives OUTSIDE
        /// the split view so the File Details panel never squeezes it.
        private var batchActionBar: some View {
            HStack {
                // Quick selection: check/uncheck everything at once
                Button(action: {
                    viewModel.setAllChecked(
                        viewModel.checkedComicIDs.count < viewModel.stagedComics.count)
                }) {
                    Label(
                        viewModel.checkedComicIDs.count < viewModel.stagedComics.count
                            ? "Check All" : "Uncheck All",
                        systemImage: "checklist")
                }

                // Bulk edit the CHECKED items (set year/publisher/etc. once)
                Button(action: {
                    showingBulkEdit = true
                }) {
                    Label(
                        "Edit \(viewModel.checkedComicIDs.count) Checked…",
                        systemImage: "square.and.pencil")
                }
                .disabled(viewModel.checkedComicIDs.isEmpty)

                // Import the CHECKED items straight into a folder
                Button(action: {
                    folderPromptMode = .checked
                    showingFolderPrompt = true
                }) {
                    Label(
                        "Add \(viewModel.checkedComicIDs.count) to Folder…",
                        systemImage: "folder.badge.plus")
                }
                .disabled(viewModel.checkedComicIDs.isEmpty)

                // Fetch ComicVine metadata for every checked file
                Button(action: {
                    Task { await viewModel.fetchComicVineForChecked() }
                }) {
                    if viewModel.isBatchFetchingCV {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Fetching \(viewModel.batchCVDone)/\(viewModel.batchCVTotal)…")
                        }
                    } else {
                        Label(
                            "Fetch \(viewModel.checkedComicIDs.count) from ComicVine",
                            systemImage: "sparkles")
                    }
                }
                .disabled(viewModel.checkedComicIDs.isEmpty || viewModel.isBatchFetchingCV)

                if let summary = viewModel.batchCVSummary, !viewModel.isBatchFetchingCV {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .help(summary)
                }

                Spacer()

                Button(action: {
                    // More than one book? Offer to file them into a
                    // folder first. A single book just applies.
                    if viewModel.readyCount > 1 {
                        folderPromptMode = .allReady
                        showingFolderPrompt = true
                    } else {
                        Task { await viewModel.confirmAllReady() }
                    }
                }) {
                    Label("Apply All Ready", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.readyCount == 0 || viewModel.isBatchFetchingCV)
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(Color(NSColor.controlBackgroundColor))
        }

        /// One numbered row in the empty-state mini guide.
        private func guideRow(_ number: Int, _ text: String) -> some View {
            HStack(alignment: .top, spacing: 8) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.accentColor))
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        /// Handle files/folders dropped onto the staging list.
        /// URL validation and folder scanning happen in `viewModel.addFiles`.
        private func handleDrop(providers: [NSItemProvider]) -> Bool {
            let group = DispatchGroup()
            var urls: [URL] = []

            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) {
                    (urlData, error) in
                    defer { group.leave() }

                    if let error = error {
                        AppLog.organize.error("Drop: error loading item: \(error)")
                        return
                    }

                    if let urlData = urlData as? Data,
                        let urlString = String(data: urlData, encoding: .utf8),
                        let url = URL(string: urlString)
                    {
                        urls.append(url)
                    }
                }
            }

            group.notify(queue: .main) {
                if !urls.isEmpty {
                    routeDroppedURLs(urls)
                }
            }

            return true
        }
    #endif

    #if os(iOS)
        // MARK: - iOS Body
        //
        // Mirrors the Mac staging workflow (staged list, per-file inspector,
        // ComicVine fetch, bulk edit, batch folder-filing) using a
        // NavigationSplitView so it collapses to a stack on compact widths
        // and shows list+inspector side by side on a full-size iPad. The
        // underlying OrganizeViewModel/OrganizeInspectorView/BulkEditSheet/
        // ImportFolderChoiceSheet are all already cross-platform — this is
        // just the iPad-shaped container around them.

        private var iOSBody: some View {
            NavigationSplitView(columnVisibility: $iosColumnVisibility) {
                stagedListColumn
            } detail: {
                if let selected = viewModel.selectedComic {
                    OrganizeInspectorView(comic: selected, viewModel: viewModel)
                        // Rebuild on selection change AND when a batch fetch
                        // updates staged metadata behind the inspector's back.
                        .id("\(selected.id.uuidString)-\(viewModel.metadataRevision)")
                } else {
                    Text("Select a file to review details")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .sheet(isPresented: $showingBulkEdit) {
                BulkEditSheet(
                    itemCount: viewModel.checkedComicIDs.count,
                    showsContentRating: false
                ) { values in
                    viewModel.bulkUpdate(ids: viewModel.checkedComicIDs, values: values)
                }
            }
            .sheet(isPresented: $showingFolderPrompt) {
                let count =
                    folderPromptMode == .checked ? viewModel.checkedCount : viewModel.readyCount
                ImportFolderChoiceSheet(
                    bookCountText: "\(count) book\(count == 1 ? "" : "s")",
                    folders: viewModel.availableFolders,
                    onChoice: { choice in
                        showingFolderPrompt = false
                        let mode = folderPromptMode
                        Task {
                            switch mode {
                            case .allReady:
                                await viewModel.confirmAllReady(folderChoice: choice)
                            case .checked:
                                await viewModel.confirmChecked(folderChoice: choice)
                            }
                        }
                    },
                    onCancel: { showingFolderPrompt = false }
                )
            }
            .fileImporter(
                isPresented: $showingAddFilePicker,
                allowedContentTypes: iOSImportTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    routeDroppedURLs(urls)
                }
            }
        }

        /// `.scobook` is included so transfer packages picked from Files are
        /// selectable; `routeDroppedURLs` diverts them to the receive flow.
        private var iOSImportTypes: [UTType] {
            [
                .pdf, .epub, UTType(filenameExtension: "cbz"), UTType(filenameExtension: "cbr"),
                UTType(exportedAs: BookPackage.typeIdentifier),
            ].compactMap { $0 }
        }

        private var stagedListColumn: some View {
            Group {
                if viewModel.stagedComics.isEmpty {
                    emptyStagingState
                } else {
                    List(selection: $viewModel.selectedComicID) {
                        ForEach(viewModel.stagedComics) { comic in
                            OrganizeStagedRow(
                                comic: comic,
                                isChecked: viewModel.checkedComicIDs.contains(comic.id),
                                onToggleCheck: { viewModel.toggleCheck(for: comic.id) }
                            )
                            .tag(comic.id)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Organize")
            .safeAreaInset(edge: .top) {
                if showsHomeFolderBanner {
                    homeFolderBanner
                        .padding(.bottom, 4)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddFilePicker = true
                    } label: {
                        Label("Add Files", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !viewModel.stagedComics.isEmpty {
                    iOSBatchActionBar
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleIOSDrop(providers: providers)
            }
            .overlay(
                Group {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                Color.accentColor,
                                style: StrokeStyle(lineWidth: 2, dash: [8])
                            )
                            .background(Color.accentColor.opacity(0.08))
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
            )
        }

        private var emptyStagingState: some View {
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No Files Staged")
                    .font(.headline)
                Text("Tap Add Files, or drag comic files here from the Files app. Then select each file to review its details — fields marked in orange decide whether a book is Ready — and import one at a time or all at once with Apply All Ready.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        // MARK: - Batch Action Bar (iOS)

        /// Bottom action bar mirroring Mac's `batchActionBar`. Space is
        /// tighter on iPad, so the less-common actions (bulk edit, add to
        /// folder, ComicVine fetch) live behind a single "Actions" menu
        /// instead of sitting inline as separate buttons.
        private var iOSBatchActionBar: some View {
            VStack(spacing: 4) {
                Divider()

                HStack {
                    Button {
                        viewModel.setAllChecked(
                            viewModel.checkedComicIDs.count < viewModel.stagedComics.count)
                    } label: {
                        Label(
                            viewModel.checkedComicIDs.count < viewModel.stagedComics.count
                                ? "Check All" : "Uncheck All",
                            systemImage: "checklist")
                    }

                    Spacer()

                    Menu {
                        Button {
                            showingBulkEdit = true
                        } label: {
                            Label(
                                "Edit \(viewModel.checkedComicIDs.count) Checked…",
                                systemImage: "square.and.pencil")
                        }
                        .disabled(viewModel.checkedComicIDs.isEmpty)

                        Button {
                            folderPromptMode = .checked
                            showingFolderPrompt = true
                        } label: {
                            Label(
                                "Add \(viewModel.checkedComicIDs.count) to Folder…",
                                systemImage: "folder.badge.plus")
                        }
                        .disabled(viewModel.checkedComicIDs.isEmpty)

                        Button {
                            Task { await viewModel.fetchComicVineForChecked() }
                        } label: {
                            Label(
                                "Fetch \(viewModel.checkedComicIDs.count) from ComicVine",
                                systemImage: "sparkles")
                        }
                        .disabled(viewModel.checkedComicIDs.isEmpty || viewModel.isBatchFetchingCV)
                    } label: {
                        if viewModel.isBatchFetchingCV {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Fetching \(viewModel.batchCVDone)/\(viewModel.batchCVTotal)…")
                            }
                        } else {
                            Label("Actions", systemImage: "ellipsis.circle")
                        }
                    }
                    .disabled(viewModel.isBatchFetchingCV)

                    Spacer()

                    Button {
                        if viewModel.readyCount > 1 {
                            folderPromptMode = .allReady
                            showingFolderPrompt = true
                        } else {
                            Task { await viewModel.confirmAllReady() }
                        }
                    } label: {
                        Label("Apply All Ready (\(viewModel.readyCount))", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.readyCount == 0 || viewModel.isBatchFetchingCV)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                if let summary = viewModel.batchCVSummary, !viewModel.isBatchFetchingCV {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }
            }
            .background(.bar)
        }

        /// Handle files dropped onto the iOS staging list (Split View drag,
        /// or a drag onto the app's Dock icon). `.scobook` packages and
        /// plain comic files are routed separately by `routeDroppedURLs`.
        private func handleIOSDrop(providers: [NSItemProvider]) -> Bool {
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                        do {
                            if let url = try await provider.loadItem(
                                forTypeIdentifier: "public.file-url", options: nil) as? URL
                            {
                                urls.append(url)
                            }
                        } catch {
                            AppLog.organize.error("Drop: failed to load dropped item: \(error)")
                        }
                    }
                }
                routeDroppedURLs(urls)
            }
            return true
        }
    #endif
}

#if os(iOS)
    // MARK: - Staged Row (iOS)

    /// One row in the iPad staging list: checkbox, proposed name, original
    /// name, and a Ready/Pending badge — the iOS equivalent of the inline
    /// row content Mac's `List` builds directly.
    private struct OrganizeStagedRow: View {
        let comic: StagedComic
        let isChecked: Bool
        let onToggleCheck: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Button(action: onToggleCheck) {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .foregroundColor(isChecked ? .accentColor : .secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(comic.proposedFileName)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack {
                        Text(comic.originalFileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Spacer()

                        if comic.status == .ready {
                            Text("Ready")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                        } else {
                            Text("Pending")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
#endif
