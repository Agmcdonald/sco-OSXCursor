//
//  StagedComicMergeTests.swift
//  SCO-OSXCursorTests
//

import Foundation
import Testing

@testable import SCO_OSXCursor

struct StagedComicMergeTests {

    @Test func mergedStagedComicProposesCBZExtension() {
        var staged = StagedComic(url: URL(fileURLWithPath: "/tmp/Saga Book One (2014).pdf"))
        staged.series = "Saga"
        staged.volume = 1
        staged.year = 2014
        staged.bookFormat = .volume
        #expect(staged.proposedFileName.hasSuffix(".pdf"))

        staged.mergeSourceURLs = [
            URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.pdf"),
        ]
        #expect(staged.proposedFileName.hasSuffix(".cbz"))
    }
}
