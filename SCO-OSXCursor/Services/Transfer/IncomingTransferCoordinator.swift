//
//  IncomingTransferCoordinator.swift
//  SCO-OSXCursor
//
//  Owns the single "what .scobook package is currently being shown/imported"
//  slot, plus a FIFO queue feeding it. Originally this lived inline in
//  ContentView (driving its .onOpenURL), but a `.scobook` can now also
//  arrive via drag-and-drop onto the Library or Organize views — pulling it
//  out into a shared, injectable coordinator means every entry point queues
//  into the same place instead of racing each other for one @State slot.
//
//  Multiple `.scobook` files can arrive back-to-back — e.g. multi-select
//  "Copy to Super Comic Organizer" from the iOS Files app, or a multi-file
//  drag from Files onto the app in Split View. Queue them and peek/import
//  one at a time instead of dropping every package after the first.
//
//  NOTE: iOS only ever hands the app ONE url per "Open In" share-sheet event
//  when multiple files are involved (confirmed OS-level limitation, not a
//  bug in this queue) — the share-sheet path still only imports one file at
//  a time until a dedicated Share Extension exists. Drag-and-drop is not
//  subject to that limitation, which is why it can carry a real batch.
//

import Combine
import Foundation

@MainActor
final class IncomingTransferCoordinator: ObservableObject {

    /// The package currently driving `TransferReceiveSheet`. Nil = nothing
    /// showing right now.
    @Published var incomingPackage: IncomingBookPackage?
    /// Set when a queued package fails to peek; drives an alert.
    @Published var incomingTransferError: String?

    private var incomingURLQueue: [URL] = []
    private var isPeekingIncomingURL = false

    /// Queue a single `.scobook` URL (non-`.scobook` URLs are ignored).
    func enqueue(_ url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == BookPackage.fileExtension else {
            return
        }
        incomingURLQueue.append(url)
        processNextIfPossible()
    }

    /// Queue several URLs at once (e.g. a multi-file drag-and-drop drop).
    /// Non-`.scobook` URLs are silently skipped — callers should route those
    /// through their normal comic-import path instead.
    func enqueue(urls: [URL]) {
        let scobooks = urls.filter {
            $0.isFileURL && $0.pathExtension.lowercased() == BookPackage.fileExtension
        }
        guard !scobooks.isEmpty else { return }
        incomingURLQueue.append(contentsOf: scobooks)
        processNextIfPossible()
    }

    /// Call from the sheet's Done/close path: clears the slot so
    /// `.sheet(item:)` starts dismissing. The next queued package is NOT
    /// presented here — presenting while the dismissal animation is still
    /// running makes UIKit drop the transition and permanently wedges the
    /// sheet (stale content on screen, binding already nil). The queue
    /// advances from `.sheet(item:onDismiss:)` via `presentNextQueued()`,
    /// which the system only fires once the old sheet is fully gone.
    func packageSheetDismissed() {
        incomingPackage = nil
    }

    /// Call from `.sheet(item:onDismiss:)` — the previous sheet is fully
    /// torn down at that point, so presenting the next package can't race
    /// the dismissal animation.
    func presentNextQueued() {
        processNextIfPossible()
    }

    /// Pulls the next queued URL and peeks it, as long as nothing is
    /// currently being shown/imported. Safe to call repeatedly.
    private func processNextIfPossible() {
        guard incomingPackage == nil, !isPeekingIncomingURL, !incomingURLQueue.isEmpty else {
            return
        }
        isPeekingIncomingURL = true
        let url = incomingURLQueue.removeFirst()

        Task {
            defer { isPeekingIncomingURL = false }
            do {
                let package = try await Task.detached(priority: .userInitiated) {
                    try BookPackageImporter.peek(at: url)
                }.value
                incomingPackage = package
            } catch {
                incomingTransferError = error.localizedDescription
                // This URL failed — move on to whatever else is queued.
                processNextIfPossible()
            }
        }
    }
}
