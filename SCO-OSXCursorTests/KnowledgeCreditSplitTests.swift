//
//  KnowledgeCreditSplitTests.swift
//  SCO-OSXCursorTests
//
//  Tests for splitting combined creator-credit fields ("A, B & C") into
//  individual Knowledge Base entries, and for the isCreatorType flag that
//  keeps series/publisher names intact.
//

import Foundation
import Testing

@testable import SCO_OSXCursor

@Suite("Knowledge credit splitting")
struct KnowledgeCreditSplitTests {

    @Test("Comma-separated names split into individuals")
    func splitsCommaSeparated() {
        let names = KnowledgeEntry.splitCreditNames(
            "Claire Roe, J. Bone, Nicola Scott, Ro Stein, Ted Brandt")
        #expect(names == ["Claire Roe", "J. Bone", "Nicola Scott", "Ro Stein", "Ted Brandt"])
    }

    @Test("Ampersand and semicolon are also separators")
    func splitsMixedSeparators() {
        let names = KnowledgeEntry.splitCreditNames("Jim Lee & Scott Williams; Alex Sinclair")
        #expect(names == ["Jim Lee", "Scott Williams", "Alex Sinclair"])
    }

    @Test("Whitespace is trimmed and empties dropped")
    func trimsAndDropsEmpties() {
        let names = KnowledgeEntry.splitCreditNames("  Stan Lee ,, & Jack Kirby ,")
        #expect(names == ["Stan Lee", "Jack Kirby"])
    }

    @Test("Duplicates are removed, first spelling wins")
    func dedupesCaseInsensitively() {
        let names = KnowledgeEntry.splitCreditNames("Jim Lee, jim lee, JIM LEE")
        #expect(names == ["Jim Lee"])
    }

    @Test("A single clean name passes through unchanged")
    func singleNameUnchanged() {
        #expect(KnowledgeEntry.splitCreditNames("Nicola Scott") == ["Nicola Scott"])
    }

    @Test("Nil and empty input yield no names")
    func emptyInput() {
        #expect(KnowledgeEntry.splitCreditNames(nil).isEmpty)
        #expect(KnowledgeEntry.splitCreditNames("   ").isEmpty)
    }

    @Test("Creator types are flagged for splitting; series/publisher are not")
    func creatorTypeFlag() {
        #expect(KnowledgeEntry.EntryType.writer.isCreatorType)
        #expect(KnowledgeEntry.EntryType.artist.isCreatorType)
        #expect(KnowledgeEntry.EntryType.coverArtist.isCreatorType)
        #expect(KnowledgeEntry.EntryType.colorist.isCreatorType)
        #expect(KnowledgeEntry.EntryType.inker.isCreatorType)
        #expect(KnowledgeEntry.EntryType.editor.isCreatorType)

        #expect(!KnowledgeEntry.EntryType.series.isCreatorType)
        #expect(!KnowledgeEntry.EntryType.publisher.isCreatorType)
    }
}
