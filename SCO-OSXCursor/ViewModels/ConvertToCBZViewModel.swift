//
//  ConvertToCBZViewModel.swift
//  SCO-OSXCursor
//
//  Phase machine for the post-hoc "Convert to CBZ" sheet
//  (preview → running → done), in the shape of ReorganizeViewModel.
//  One book failing never halts the batch.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ConvertToCBZViewModel: ObservableObject {

    enum Phase {
        case ready      // preview list shown, awaiting confirmation
        case running    // converting
        case done       // all attempted
    }

    struct ItemError: Identifiable {
        let id = UUID()
        let name: String
        let reason: String
    }

    @Published var phase: Phase = .ready
    @Published var progress: Double = 0
    @Published var statusLine: String = ""
    @Published var completedCount = 0
    @Published var failedCount = 0
    @Published var errors: [ItemError] = []
    @Published var warnings: [String] = []

    /// PDFs only — the caller may hand over a mixed selection.
    let candidates: [Comic]
    /// Books from the selection the sheet won't touch (not PDFs, samples…).
    let skippedCount: Int

    init(selection: [Comic]) {
        // pdfReadsAsBook is deliberately NOT an exclusion: it's a reader
        // preference, not evidence the PDF is prose. Only the user-set
        // ebook format opts a PDF out of explicit conversion.
        let eligible = selection.filter {
            $0.fileType == .pdf && !Comic.isBundled($0) && !$0.needsAttention
                && $0.bookFormat != .ebook
        }
        self.candidates = eligible
        self.skippedCount = selection.count - eligible.count
    }

    func run(library: LibraryViewModel) async {
        guard phase == .ready, !candidates.isEmpty else { return }
        phase = .running
        let total = candidates.count

        for (index, comic) in candidates.enumerated() {
            let name = comic.displayTitle
            statusLine = "Converting \(name)…"
            do {
                let outcome = try await library.convertPDFToCBZ(comic) { [weak self] page, pages in
                    Task { @MainActor [weak self] in
                        self?.statusLine = "Converting \(name) — page \(page) of \(pages)"
                    }
                }
                completedCount += 1
                if let warning = outcome.warning { warnings.append(warning) }
            } catch {
                failedCount += 1
                errors.append(ItemError(name: name, reason: error.localizedDescription))
            }
            progress = Double(index + 1) / Double(total)
        }

        statusLine = ""
        phase = .done
    }
}
