//
//  HomeLibrarySetupPrompt.swift
//  SCO-OSXCursor
//
//  Quick Add / Add Files / Scan Folder file books into the home library
//  (auto-sort). When auto-sort is on but no home library folder has been
//  chosen yet, this modifier interrupts the import with an offer to pick
//  one. Declining imports the books in place (pre-Milestone behaviour).
//
//  Shared by LibraryView and DashboardOverviewView so both import entry
//  points behave identically.
//

import SwiftUI
import UniformTypeIdentifiers

struct HomeLibrarySetupPrompt: ViewModifier {
    /// Presents the alert. Set alongside `pendingURLs` by the caller.
    @Binding var isPresented: Bool
    /// The URLs whose import is paused while the user decides.
    @Binding var pendingURLs: [URL]
    /// Runs the actual import once the decision is made.
    let onImport: ([URL]) -> Void

    @State private var showingFolderPicker = false

    /// True when an import should first ask the user to set a home library:
    /// auto-sort is enabled but no home library folder is configured.
    @MainActor static var needsPrompt: Bool {
        AppSettings.load().autoSortIntoLibrary
            && SettingsViewModel().resolveHomeLibraryURL() == nil
    }

    func body(content: Content) -> some View {
        content
            .alert("Choose a Home Library Folder?", isPresented: $isPresented) {
                Button("Choose Folder…") { showingFolderPicker = true }
                Button("Import in Place", role: .cancel) { runPendingImport() }
            } message: {
                Text(
                    "SCO can file these books into Publisher/Series folders inside a home library. Books without a known publisher go to “Unknown Publisher” until you set one. Or import them where they are — you can set a home library later in Settings."
                )
            }
            // Own background view: SwiftUI honours only ONE .fileImporter
            // per view (same pattern as LibraryView's other importers).
            .background(
                Color.clear.fileImporter(
                    isPresented: $showingFolderPicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let folder = urls.first {
                        SettingsViewModel().setHomeLibraryFolder(folder)
                    }
                    // Picker cancelled/failed → import in place instead.
                    runPendingImport()
                }
            )
    }

    private func runPendingImport() {
        let urls = pendingURLs
        pendingURLs = []
        guard !urls.isEmpty else { return }
        onImport(urls)
    }
}
