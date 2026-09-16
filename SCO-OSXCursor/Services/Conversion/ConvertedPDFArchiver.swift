//
//  ConvertedPDFArchiver.swift
//  SCO-OSXCursor
//
//  Files a converted book's original PDF(s) into
//  "<LibraryRoot>/Converted PDFs/<Publisher>/<Series>/…", mirroring where
//  the converted CBZ lives (or would live) under the root — so a user
//  who wants to delete originals can find each one exactly where its
//  book is filed. Move-only: originals are never deleted, and name
//  conflicts get " (2)" suffixes.
//
//  Callers hold the library root's security scope.
//

import Foundation

enum ConvertedPDFArchiver {

    static let folderName = "Converted PDFs"

    /// Folder path (relative to the library root) the original should
    /// mirror: the comic's own parent folder when it lives under the
    /// root (and isn't already inside Converted PDFs), otherwise the
    /// folder destinationURL would file it into.
    static func mirrorSubpath(
        for comic: Comic,
        libraryRoot: URL,
        folderStructure: AppSettings.FolderStructure = AppSettings.load().folderStructure
    ) -> String {
        let parent = comic.filePath.deletingLastPathComponent()
        if let relative = relativePath(of: parent, under: libraryRoot),
           !relative.hasPrefix(folderName) {
            return relative
        }
        let destinationFolder = LibraryFileService.shared
            .destinationURL(for: comic, in: libraryRoot, folderStructure: folderStructure)
            .deletingLastPathComponent()
        return relativePath(of: destinationFolder, under: libraryRoot) ?? ""
    }

    /// Moves `original` into the mirror folder; returns where it landed.
    @discardableResult
    static func archiveOriginal(
        _ original: URL, libraryRoot: URL, mirrorSubpath: String
    ) throws -> URL {
        let fm = FileManager.default
        var folder = libraryRoot.appendingPathComponent(folderName, isDirectory: true)
        if !mirrorSubpath.isEmpty {
            folder.appendPathComponent(mirrorSubpath, isDirectory: true)
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var destination = folder.appendingPathComponent(original.lastPathComponent)
        destination = LibraryFileService.shared.resolveConflict(at: destination)
        try LibraryFileService.shared.moveFile(at: original, to: destination)
        AppLog.files.info(
            "[ConvertedPDFArchiver] ✅ Filed original: \(original.lastPathComponent) → \(folderName)/\(mirrorSubpath)")
        return destination
    }

    /// `url`'s path relative to `root` ("" when equal), nil when outside.
    static func relativePath(of url: URL, under root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath == rootPath { return "" }
        guard urlPath.hasPrefix(rootPath + "/") else { return nil }
        return String(urlPath.dropFirst(rootPath.count + 1))
    }
}
