//
//  MaintenanceView.swift
//  SCO-OSXCursor
//
//  The Maintenance tab: library integrity fixes, database housekeeping
//  (backup / restore / optimize), and storage management. The Dashboard's
//  Health tab shows the read-only score; the actions all live here.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct MaintenanceView: View {
    @ObservedObject var libraryViewModel: LibraryViewModel

    // ── Library integrity ──
    @State private var reviewMode: HealthReviewMode?
    @State private var isScanningFiles = false
    @State private var fileScanStatus: String?

    // ── Database ──
    @State private var dbSizeBytes: Int64?
    @State private var isCheckingIntegrity = false
    @State private var integrityResult: String?
    @State private var isOptimizing = false
    @State private var optimizeStatus: String?
    @State private var activityStatus: String?
    @State private var isCleaningOrphans = false
    @State private var orphanStatus: String?

    // ── Backup / restore ──
    @State private var backupDocument: LibraryBackupDocument?
    @State private var showingBackupExporter = false
    @State private var showingRestoreImporter = false
    @State private var pendingRestoreData: Data?
    @State private var showingRestoreConfirm = false
    @State private var restoreSucceeded = false

    // ── Learning ──
    @State private var patternCount = 0
    @State private var showingClearPatternsConfirm = false

    // ── Storage ──
    @State private var imageCacheDiskBytes: Int64?
    @State private var cacheStatus: String?

    // ── Trash ──
    @State private var trashEntries: [TrashEntry] = []
    @State private var trashSize: Int64 = 0
    @State private var trashStatus: String?
    @State private var showingEmptyTrashConfirm = false
    @State private var pendingPurgeEntry: TrashEntry?
    @AppStorage(LibraryViewModel.trashRetentionDefaultsKey) private var trashRetentionDays: Int = 30

    // Shared error alert
    @State private var maintenanceError: String?

    // MARK: - Derived issue lists

    private var missingMetadata: [Comic] {
        LibraryHealth.missingMetadata(in: libraryViewModel.comics)
    }

    private var missingCovers: [Comic] {
        LibraryHealth.missingCovers(in: libraryViewModel.comics)
    }

    private var duplicateGroups: [[Comic]] {
        LibraryHealth.duplicateGroups(in: libraryViewModel.comics)
    }

    private var missingFilesCount: Int {
        libraryViewModel.comics.filter { $0.needsAttention }.count
    }

    private var hasIntegrityIssues: Bool {
        !missingMetadata.isEmpty || !missingCovers.isEmpty
            || !duplicateGroups.isEmpty || missingFilesCount > 0
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Maintenance")
                        .font(Typography.h1)
                        .foregroundColor(TextColors.primary)
                    Text("Keep your library catalog healthy — fix issues, back up, and reclaim space")
                        .font(Typography.body)
                        .foregroundColor(TextColors.secondary)
                }
                .padding(.top, Spacing.xl)

                integritySection
                databaseSection
                storageSection
                trashSection
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .background(BackgroundColors.primary)
        .task {
            await refreshSizes()
            await loadTrash()
        }
        .onAppear { patternCount = OrganizationLearner.shared.getPatternCount() }
        // Issue review sheets (shared with the old Health tab flow)
        .sheet(item: $reviewMode) { mode in
            HealthReviewSheet(
                libraryViewModel: libraryViewModel,
                mode: mode,
                onClose: { reviewMode = nil }
            )
        }
        // Backup exporter
        .fileExporter(
            isPresented: $showingBackupExporter,
            document: backupDocument,
            contentType: .sqliteDatabase,
            defaultFilename: "SCO-Library-Backup-\(Self.backupDateString())"
        ) { result in
            if case .failure(let error) = result {
                maintenanceError = error.localizedDescription
            }
            backupDocument = nil
        }
        // Restore importer
        .fileImporter(
            isPresented: $showingRestoreImporter,
            allowedContentTypes: [.sqliteDatabase, .database, .data]
        ) { result in
            handleRestoreSelection(result)
        }
        .alert("Replace Library Catalog?", isPresented: $showingRestoreConfirm) {
            Button("Cancel", role: .cancel) { pendingRestoreData = nil }
            Button("Restore", role: .destructive) { performRestore() }
        } message: {
            Text(
                "Your current catalog will be replaced with the backup — all books, folders, reading progress, and learned data revert to how they were when the backup was made. This cannot be undone."
            )
        }
        .alert("Restore Complete", isPresented: $restoreSucceeded) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your library catalog was restored from the backup.")
        }
        .alert("Clear Learned Patterns?", isPresented: $showingClearPatternsConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task {
                    await OrganizationLearner.shared.clearAllPatterns()
                    patternCount = OrganizationLearner.shared.getPatternCount()
                }
            }
        } message: {
            Text(
                "All \(patternCount) learned organization pattern\(patternCount == 1 ? "" : "s") will be forgotten. The app will re-learn from your future corrections."
            )
        }
        .alert("Empty Trash?", isPresented: $showingEmptyTrashConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) { emptyTrash() }
        } message: {
            Text(
                "Permanently delete \(trashEntries.count) item\(trashEntries.count == 1 ? "" : "s") (\(Self.formatBytes(trashSize)))? This cannot be undone."
            )
        }
        .alert(
            "Permanently Delete?",
            isPresented: Binding(
                get: { pendingPurgeEntry != nil },
                set: { if !$0 { pendingPurgeEntry = nil } }),
            presenting: pendingPurgeEntry
        ) { entry in
            Button("Cancel", role: .cancel) { pendingPurgeEntry = nil }
            Button("Delete", role: .destructive) { purgeEntry(entry) }
        } message: { entry in
            Text("Permanently delete \(entry.displayTitle)? This cannot be undone.")
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { maintenanceError != nil },
                set: { if !$0 { maintenanceError = nil } })
        ) {
            Button("OK", role: .cancel) { maintenanceError = nil }
        } message: {
            Text(maintenanceError ?? "")
        }
    }

    // MARK: - Library Integrity

    private var integritySection: some View {
        DashboardSectionCard(
            title: "Library Integrity",
            subtitle: "Find and fix problems with the books in your library"
        ) {
            VStack(spacing: Spacing.sm) {
                if !duplicateGroups.isEmpty {
                    HealthIssueRow(
                        icon: "doc.on.doc",
                        iconColor: .red,
                        title: "Potential Duplicates",
                        description:
                            "Found \(duplicateGroups.count) set\(duplicateGroups.count == 1 ? "" : "s") of comics that might be duplicates.",
                        badgeCount: duplicateGroups.count,
                        actionLabel: "Review",
                        action: { reviewMode = .duplicates }
                    )
                    Divider()
                }

                if !missingMetadata.isEmpty {
                    HealthIssueRow(
                        icon: "tag.slash",
                        iconColor: .orange,
                        title: "Missing Metadata",
                        description:
                            "\(missingMetadata.count) comic\(missingMetadata.count == 1 ? "" : "s") missing title or series information.",
                        badgeCount: missingMetadata.count,
                        actionLabel: "Review",
                        action: { reviewMode = .missingMetadata }
                    )
                    Divider()
                }

                if !missingCovers.isEmpty {
                    HealthIssueRow(
                        icon: "photo.badge.exclamationmark",
                        iconColor: .orange,
                        title: "Missing Cover Art",
                        description:
                            "\(missingCovers.count) comic\(missingCovers.count == 1 ? "" : "s") have no cover image.",
                        badgeCount: missingCovers.count,
                        actionLabel: "Review",
                        action: { reviewMode = .missingCovers }
                    )
                    Divider()
                }

                if missingFilesCount > 0 {
                    HealthIssueRow(
                        icon: "questionmark.folder",
                        iconColor: .red,
                        title: "Missing Files",
                        description:
                            "\(missingFilesCount) book\(missingFilesCount == 1 ? " points" : "s point") to a file that can't be found on disk.",
                        badgeCount: missingFilesCount,
                        actionLabel: isScanningFiles ? "Scanning…" : "Rescan",
                        action: { scanForMissingFiles() }
                    )
                    Divider()
                }

                if !hasIntegrityIssues {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No Issues Detected")
                                .font(Typography.h3)
                                .foregroundColor(TextColors.primary)
                            Text("Your library looks great!")
                                .font(Typography.bodySmall)
                                .foregroundColor(TextColors.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Spacing.xs)
                    Divider()
                }

                // Always-available file scan
                maintenanceRow(
                    icon: "internaldrive",
                    title: "Scan for Missing Files",
                    description: fileScanStatus
                        ?? "Check that every book's file still exists on disk. Books whose files have moved or been deleted get flagged."
                ) {
                    Button(isScanningFiles ? "Scanning…" : "Scan Now") {
                        scanForMissingFiles()
                    }
                    .disabled(isScanningFiles)
                }
            }
        }
    }

    // MARK: - Database

    private var databaseSection: some View {
        DashboardSectionCard(
            title: "Database",
            subtitle: "Back up, restore, and tune the library catalog"
        ) {
            VStack(spacing: Spacing.sm) {
                // Backup / Restore
                maintenanceRow(
                    icon: "externaldrive.badge.timemachine",
                    title: "Back Up Library Catalog",
                    description:
                        "Save a snapshot of every book's metadata, reading progress, folders, and learned data\(dbSizeText). Does not include the comic files themselves."
                ) {
                    Button("Back Up…") { startBackup() }
                }

                Divider()

                maintenanceRow(
                    icon: "arrow.counterclockwise.circle",
                    title: "Restore from Backup",
                    description:
                        "Replace the current catalog with a previously saved backup file. Your current catalog is overwritten."
                ) {
                    Button("Restore…") { showingRestoreImporter = true }
                }

                Divider()

                // Integrity + optimize
                maintenanceRow(
                    icon: "checkmark.shield",
                    title: "Check Database Integrity",
                    description: integrityResult
                        ?? "Run SQLite's built-in corruption check on the catalog file."
                ) {
                    Button(isCheckingIntegrity ? "Checking…" : "Check") {
                        checkIntegrity()
                    }
                    .disabled(isCheckingIntegrity)
                }

                Divider()

                maintenanceRow(
                    icon: "speedometer",
                    title: "Optimize Database",
                    description: optimizeStatus
                        ?? "Rebuild indexes and reclaim unused space. Useful after deleting many books."
                ) {
                    Button(isOptimizing ? "Optimizing…" : "Optimize") {
                        optimizeDatabase()
                    }
                    .disabled(isOptimizing)
                }

                Divider()

                // Activity log pruning
                maintenanceRow(
                    icon: "clock.arrow.circlepath",
                    title: "Prune Activity Log",
                    description: activityStatus
                        ?? "Remove old entries from the activity history shown on the Dashboard."
                ) {
                    Menu("Prune…") {
                        Button("Older than 30 days") { pruneActivity(days: 30) }
                        Button("Older than 90 days") { pruneActivity(days: 90) }
                        Button("Clear All", role: .destructive) { pruneActivity(days: 0) }
                    }
                    .fixedSize()
                }

                Divider()

                // Orphaned knowledge
                maintenanceRow(
                    icon: "book.closed.circle",
                    title: "Clean Up Knowledge Base",
                    description: orphanStatus
                        ?? "Remove publisher and series suggestions that no book in your library uses anymore."
                ) {
                    Button(isCleaningOrphans ? "Cleaning…" : "Clean Up") {
                        cleanOrphanedKnowledge()
                    }
                    .disabled(isCleaningOrphans)
                }

                Divider()

                // Learned patterns
                maintenanceRow(
                    icon: "brain.head.profile",
                    title: "Clear Learned Patterns",
                    description:
                        patternCount > 0
                        ? "\(patternCount) organization pattern\(patternCount == 1 ? "" : "s") learned from your corrections. Clearing starts the learning over."
                        : "No patterns learned yet — nothing to clear."
                ) {
                    Button("Clear…", role: .destructive) {
                        showingClearPatternsConfirm = true
                    }
                    .disabled(patternCount == 0)
                }
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        DashboardSectionCard(
            title: "Storage",
            subtitle: "Reclaim disk space used by caches"
        ) {
            maintenanceRow(
                icon: "photo.stack",
                title: "Image Caches",
                description: cacheStatus
                    ?? "Decoded pages, covers, and page thumbnails\(cacheSizeText). Safe to clear — images are regenerated as you browse and read."
            ) {
                Button("Clear Caches") { clearImageCaches() }
            }
        }
    }

    // MARK: - Trash

    private var trashSection: some View {
        DashboardSectionCard(title: "Trash", subtitle: trashSummary) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if trashEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trash is empty.")
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.primary)
                        Text(
                            "Deleted books are kept here and can be restored with their metadata, reading progress, and folders."
                        )
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.xs)
                } else {
                    ForEach(trashEntries) { entry in
                        trashRow(entry)
                        Divider()
                    }
                }

                // Footer: empty-all + retention window
                HStack {
                    Button("Empty Trash") { showingEmptyTrashConfirm = true }
                        .foregroundColor(AccentColors.error)
                        .disabled(trashEntries.isEmpty)
                    Spacer()
                }
                .padding(.vertical, Spacing.xs)

                Divider()

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Picker("Keep deleted items", selection: $trashRetentionDays) {
                        Text("7 Days").tag(7)
                        Text("30 Days").tag(30)
                        Text("90 Days").tag(90)
                        Text("Never Delete").tag(0)
                    }
                    .pickerStyle(.segmented)

                    Text(
                        "Items older than this are removed automatically when the app launches. 'Never Delete' keeps everything until you empty the Trash."
                    )
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Spacing.xs)

                if let trashStatus {
                    Text(trashStatus)
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One trashed book: cover thumb, title, what was deleted, and when it goes.
    private func trashRow(_ entry: TrashEntry) -> some View {
        HStack(spacing: Spacing.sm) {
            trashThumbnail(for: entry)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.primary)
                    .lineLimit(2)
                Text(
                    entry.kind == .file
                        ? "File in Trash" : "Removed from library — file kept on disk"
                )
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
                Text(
                    "Deleted \(entry.deletedAt.formatted(date: .abbreviated, time: .omitted)) · \(remainingLabel(for: entry))"
                )
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
            }

            Spacer()

            Button("Restore") { restoreEntry(entry) }
            Button("Delete Now", role: .destructive) { pendingPurgeEntry = entry }
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private func trashThumbnail(for entry: TrashEntry) -> some View {
        Group {
            #if os(macOS)
                if let data = entry.coverThumb, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    trashThumbnailPlaceholder
                }
            #else
                if let data = entry.coverThumb, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    trashThumbnailPlaceholder
                }
            #endif
        }
        .frame(width: 32, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var trashThumbnailPlaceholder: some View {
        Rectangle()
            .fill(BackgroundColors.secondary)
            .overlay(
                Image(systemName: "book.closed")
                    .font(.system(size: 14))
                    .foregroundColor(TextColors.tertiary)
            )
    }

    private var trashSummary: String {
        "\(trashEntries.count) item\(trashEntries.count == 1 ? "" : "s") · \(Self.formatBytes(trashSize))"
    }

    private func remainingLabel(for entry: TrashEntry) -> String {
        let days = TrashRetention.days(fromStoredValue: trashRetentionDays)
        guard let remaining = TrashRetention.daysRemaining(for: entry, retentionDays: days) else {
            return "Kept until emptied"
        }
        return remaining == 0 ? "Purges today" : "Purges in \(remaining) day\(remaining == 1 ? "" : "s")"
    }

    // MARK: - Row helper

    /// A standard maintenance row: icon, title + description, trailing control.
    private func maintenanceRow<Control: View>(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(AccentColors.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodySmall)
                    .foregroundColor(TextColors.primary)
                Text(description)
                    .font(Typography.caption)
                    .foregroundColor(TextColors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            control()
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Formatting

    private var dbSizeText: String {
        guard let bytes = dbSizeBytes else { return "" }
        return " (currently \(Self.formatBytes(bytes)))"
    }

    private var cacheSizeText: String {
        guard let bytes = imageCacheDiskBytes else { return "" }
        return " — \(Self.formatBytes(bytes)) on disk"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func backupDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - Actions

    private func refreshSizes() async {
        dbSizeBytes = try? DatabaseManager.shared.databaseFileSizeBytes()
        imageCacheDiskBytes = await Task.detached(priority: .utility) {
            PageImageCache.shared.diskCacheSizeBytes()
        }.value
    }

    private func scanForMissingFiles() {
        isScanningFiles = true
        fileScanStatus = "Scanning library…"
        Task {
            await libraryViewModel.checkMissingFiles()
            let count = missingFilesCount
            fileScanStatus =
                count == 0
                ? "Scan complete — every book's file was found."
                : "Scan complete — \(count) book\(count == 1 ? "" : "s") flagged as missing."
            isScanningFiles = false
        }
    }

    private func startBackup() {
        Task {
            do {
                let data = try await DatabaseManager.shared.makeBackupData()
                backupDocument = LibraryBackupDocument(data: data)
                showingBackupExporter = true
            } catch {
                maintenanceError = error.localizedDescription
            }
        }
    }

    private func handleRestoreSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingRestoreData = try Data(contentsOf: url)
                showingRestoreConfirm = true
            } catch {
                maintenanceError = error.localizedDescription
            }
        case .failure(let error):
            maintenanceError = error.localizedDescription
        }
    }

    private func performRestore() {
        guard let data = pendingRestoreData else { return }
        pendingRestoreData = nil
        Task {
            do {
                try await DatabaseManager.shared.restoreFromBackup(data)
                await libraryViewModel.loadComics()
                await refreshSizes()
                restoreSucceeded = true
            } catch {
                maintenanceError = error.localizedDescription
            }
        }
    }

    private func checkIntegrity() {
        isCheckingIntegrity = true
        Task {
            do {
                let result = try await DatabaseManager.shared.integrityCheck()
                integrityResult =
                    result.lowercased() == "ok"
                    ? "Integrity check passed — no problems found."
                    : "Problems found: \(result)"
            } catch {
                maintenanceError = error.localizedDescription
            }
            isCheckingIntegrity = false
        }
    }

    private func optimizeDatabase() {
        isOptimizing = true
        optimizeStatus = "Rebuilding indexes and compacting…"
        Task {
            do {
                let before = dbSizeBytes
                try await DatabaseManager.shared.optimizeDatabase()
                await refreshSizes()
                if let before, let after = dbSizeBytes, before > after {
                    optimizeStatus =
                        "Done — reclaimed \(Self.formatBytes(before - after))."
                } else {
                    optimizeStatus = "Done — database is already compact."
                }
            } catch {
                optimizeStatus = nil
                maintenanceError = error.localizedDescription
            }
            isOptimizing = false
        }
    }

    private func pruneActivity(days: Int) {
        Task {
            do {
                let cutoff =
                    days == 0
                    ? Date()
                    : Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
                try await DatabaseManager.shared.pruneActivity(olderThan: cutoff)
                activityStatus =
                    days == 0
                    ? "Activity log cleared."
                    : "Removed entries older than \(days) days."
            } catch {
                maintenanceError = error.localizedDescription
            }
        }
    }

    private func cleanOrphanedKnowledge() {
        isCleaningOrphans = true
        Task {
            let removed = await libraryViewModel.pruneOrphanedKnowledge()
            orphanStatus =
                removed == 0
                ? "Nothing to clean — every suggestion is still in use."
                : "Removed \(removed) unused suggestion\(removed == 1 ? "" : "s")."
            isCleaningOrphans = false
        }
    }

    private func clearImageCaches() {
        cacheStatus = "Clearing…"
        Task {
            await withCheckedContinuation { continuation in
                PageImageCache.shared.clearAllIncludingDisk {
                    continuation.resume()
                }
            }
            imageCacheDiskBytes = await Task.detached(priority: .utility) {
                PageImageCache.shared.diskCacheSizeBytes()
            }.value
            cacheStatus = "Caches cleared."
        }
    }

    // MARK: - Trash actions

    private func loadTrash() async {
        trashEntries = await libraryViewModel.trashEntries()
        trashSize = libraryViewModel.trashTotalSize()
    }

    private func restoreEntry(_ entry: TrashEntry) {
        Task {
            let outcome = await libraryViewModel.restoreFromTrash(entry)
            switch outcome {
            case .originalPath:
                trashStatus = "\(entry.displayTitle) restored to its original location."
            case .renamed:
                trashStatus = "\(entry.displayTitle) restored next to a newer file with the same name."
            case .homeLibrary:
                trashStatus =
                    "\(entry.displayTitle) restored into your home library (its original folder is gone)."
            case .catalogOnly:
                trashStatus = "\(entry.displayTitle) restored to your library."
            case .failed(let reason):
                trashStatus = "Restore failed: \(reason)"
            }
            await loadTrash()
        }
    }

    private func purgeEntry(_ entry: TrashEntry) {
        Task {
            await libraryViewModel.purgeTrashEntry(entry)
            trashStatus = "\(entry.displayTitle) permanently deleted."
            await loadTrash()
        }
    }

    private func emptyTrash() {
        Task {
            await libraryViewModel.emptyTrash()
            trashStatus = "Trash emptied."
            await loadTrash()
        }
    }
}

// MARK: - Library Backup Document

extension UTType {
    /// SQLite database type, preferring the ".db" extension for exports.
    static var sqliteDatabase: UTType {
        UTType(filenameExtension: "db") ?? .database
    }
}

/// A simple in-memory document used to export the library catalog snapshot.
struct LibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sqliteDatabase, .database, .data] }
    static var writableContentTypes: [UTType] { [.sqliteDatabase] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
