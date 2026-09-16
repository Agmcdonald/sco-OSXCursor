//
//  OrganizeScanExclusionTests.swift
//  SCO-OSXCursorTests
//
//  A rescan of the library root must not re-stage archived originals
//  filed under the reserved "Converted PDFs" folder.
//

import Foundation
import Testing

@testable import SCO_OSXCursor

struct OrganizeScanExclusionTests {

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanExclusionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func excludesConvertedPDFsFolderFromRecursiveScan() throws {
        let root = try makeRoot()
        let fm = FileManager.default

        let keptFolder = root.appendingPathComponent("DC Comics/Batman", isDirectory: true)
        try fm.createDirectory(at: keptFolder, withIntermediateDirectories: true)
        let keptFile = keptFolder.appendingPathComponent("a.cbz")
        try Data("cbz".utf8).write(to: keptFile)

        let archivedFolder = root
            .appendingPathComponent(ConvertedPDFArchiver.folderName, isDirectory: true)
            .appendingPathComponent("DC Comics/Batman", isDirectory: true)
        try fm.createDirectory(at: archivedFolder, withIntermediateDirectories: true)
        let archivedFile = archivedFolder.appendingPathComponent("b.pdf")
        try Data("pdf".utf8).write(to: archivedFile)

        let result = OrganizeViewModel.expandComicFileURLs(
            [root], validExtensions: ["cbz", "cbr", "pdf", "epub"])

        #expect(result.contains(keptFile))
        #expect(!result.contains(archivedFile))
    }
}
