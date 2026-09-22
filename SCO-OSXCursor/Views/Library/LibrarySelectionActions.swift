//
//  LibrarySelectionActions.swift
//  SCO-OSXCursor
//
//  Bulk-action wiring for selection mode, shared by the macOS header bar
//  (LibrarySelectionBar) and the touch bottom bar (LibrarySelectionBottomBar).
//
//  Both bars offer the same operations in different chrome, so the closures
//  live in one bundle built once by LibraryView. That keeps the two bars from
//  drifting apart, and keeps thirteen inline closures out of
//  LibraryView.browseLayout — this file has a history of Swift type-check
//  blowups when large literal argument lists pile up in one body.
//

import SwiftUI

struct LibrarySelectionActions {
    var onMarkAsRead: () -> Void = {}
    var onMarkAsUnread: () -> Void = {}
    var onEditFields: () -> Void = {}
    var onAddToList: () -> Void = {}
    var onRegenerateCovers: () -> Void = {}
    var onFetchMetadata: () -> Void = {}
    /// Force variant: re-fetches every selected comic, replacing what an
    /// earlier fetch stored (the normal batch skips already-fetched books).
    var onRefetchMetadata: () -> Void = {}
    var onDelete: () -> Void = {}
    var onSendToDevice: () -> Void = {}
    /// Write each selected book's metadata back into its CBZ as ComicInfo.xml.
    var onEmbedMetadata: () -> Void = {}
    /// Combine the selected CBZ files into one larger CBZ. Needs two or
    /// more books, so the control is disabled below that.
    var onMergeToCBZ: () -> Void = {}

    /// Disables the metadata button and shows a spinner while a batch runs.
    var isFetchingMetadata: Bool = false
    /// Disables Save Metadata to File while an embed batch is rewriting files.
    var isEmbeddingMetadata: Bool = false

    /// Folders offered by the "Add to Folder" menu.
    var folders: [Folder] = []
    var onAddToFolder: (UUID) -> Void = { _ in }
    var onNewFolder: () -> Void = {}

    /// Folders holding at least one selected comic. Evaluated per render so
    /// the "Remove from Folder" menu tracks the live selection.
    var removalFolders: () -> [Folder] = { [] }
    var onRemoveFromFolder: (UUID) -> Void = { _ in }
}
