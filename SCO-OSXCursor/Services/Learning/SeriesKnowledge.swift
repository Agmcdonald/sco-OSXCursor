//
//  SeriesKnowledge.swift
//  SCO-OSXCursor
//
//  Stage 3: the persistent learning system.
//
//  Every confirmed import teaches the app a series → publisher/format link;
//  every user correction teaches it an alias ("ASM" → "Amazing Spider-Man").
//  During staging, parsed filenames are matched against this knowledge (plus
//  folder-name hints) so books from known series arrive pre-identified.
//
//  The in-memory cache is the working copy; every mutation is mirrored to the
//  series_knowledge / correction_history tables.
//

import Foundation

@MainActor
final class SeriesKnowledge: ObservableObject {
    static let shared = SeriesKnowledge()

    private let database = DatabaseManager.shared

    /// All learned series, sorted by use count (kept published for LearningView)
    @Published private(set) var records: [SeriesKnowledgeRecord] = []

    // Lookup indexes (rebuilt whenever records change)
    private var indexByNormalized: [String: Int] = [:]
    private var aliasToCanonical: [String: String] = [:]

    /// Known publisher names (normalized → display) for folder-hint matching,
    /// built from learned series and the knowledge base.
    private var knownPublishers: [String: String] = [:]

    private var loaded = false

    private init() {}

    // MARK: - Loading

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        await reload()
    }

    func reload() async {
        let fetched = (try? await database.fetchAllSeriesKnowledge()) ?? []
        records = fetched
        rebuildIndexes()

        // Publisher names from the knowledge base supplement the built-in list
        if let entries = try? await database.fetchKnowledgeEntries(type: .publisher) {
            for entry in entries {
                knownPublishers[entry.normalizedName] = entry.name
            }
        }
        print("[SeriesKnowledge] 📚 Loaded \(records.count) learned series")
    }

    private func rebuildIndexes() {
        indexByNormalized.removeAll()
        aliasToCanonical.removeAll()
        for (i, record) in records.enumerated() {
            indexByNormalized[record.normalizedName] = i
            for alias in record.aliases {
                aliasToCanonical[alias] = record.normalizedName
            }
            if let publisher = record.publisher, !publisher.isEmpty {
                knownPublishers[SeriesKnowledgeRecord.normalize(publisher)] = publisher
            }
        }
    }

    // MARK: - Matching

    struct Match {
        let canonicalSeries: String
        let publisher: String?
        let bookFormat: Comic.BookFormat
        let viaAlias: Bool
    }

    /// Match a parsed series name against learned knowledge (exact, then alias).
    func match(series: String?) -> Match? {
        guard let series, !series.isEmpty else { return nil }
        let normalized = SeriesKnowledgeRecord.normalize(series)

        if let i = indexByNormalized[normalized] {
            let r = records[i]
            return Match(
                canonicalSeries: r.seriesName, publisher: r.publisher,
                bookFormat: r.bookFormat, viaAlias: false)
        }
        if let canonical = aliasToCanonical[normalized], let i = indexByNormalized[canonical] {
            let r = records[i]
            return Match(
                canonicalSeries: r.seriesName, publisher: r.publisher,
                bookFormat: r.bookFormat, viaAlias: true)
        }
        return nil
    }

    // MARK: - Folder Hints
    //
    // Most files have no ComicInfo.xml — but they often live in folders like
    // "Marvel Comics/Amazing Spider-Man/". Use ancestor folder names as
    // publisher (exact match only) and series hints.

    struct FolderHints {
        var publisher: String?
        var series: String?
    }

    func folderHints(for fileURL: URL) -> FolderHints {
        var hints = FolderHints()

        // Look at up to 3 nearest ancestor folders
        let folderNames = fileURL.deletingLastPathComponent().pathComponents.suffix(3)

        for name in folderNames.reversed() {  // nearest folder first
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "/" else { continue }
            let normalized = SeriesKnowledgeRecord.normalize(trimmed)

            // Publisher? (exact match against built-in + learned publishers)
            if hints.publisher == nil {
                if let exact = PublisherDetector.exactMatch(trimmed) {
                    hints.publisher = exact
                    continue
                }
                if let known = knownPublishers[normalized] {
                    hints.publisher = known
                    continue
                }
            }

            // Known series folder? ("…/Sludge/Sludge 01.cbz")
            if hints.series == nil {
                if let i = indexByNormalized[normalized] {
                    hints.series = records[i].seriesName
                    continue
                }
                if let canonical = aliasToCanonical[normalized],
                    let i = indexByNormalized[canonical]
                {
                    hints.series = records[i].seriesName
                    continue
                }
                // Nearest unrecognized folder is still a series candidate
                // (only used when the filename parse found no series at all)
                if hints.series == nil, name == folderNames.last {
                    hints.series = trimmed
                }
            }
        }
        return hints
    }

    // MARK: - Learning

    /// Record a confirmed import — series → publisher/format association.
    func recordImport(series: String?, publisher: String?, bookFormat: Comic.BookFormat) {
        guard let series, !series.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let normalized = SeriesKnowledgeRecord.normalize(series)
        let cleanPublisher = publisher?.isEmpty == false ? publisher : nil

        if let i = indexByNormalized[normalized] {
            var record = records[i]
            record.useCount += 1
            record.lastUsed = Date()
            if let cleanPublisher { record.publisher = cleanPublisher }
            // Only flip format away from .issue once we see evidence — keeps a
            // stray TPB from re-labeling an issue-based series.
            if record.bookFormat == .issue && bookFormat != .issue {
                record.bookFormat = bookFormat
            }
            records[i] = record
            persist(record)
        } else {
            let record = SeriesKnowledgeRecord(
                seriesName: series.trimmingCharacters(in: .whitespaces),
                publisher: cleanPublisher,
                bookFormat: bookFormat
            )
            records.append(record)
            rebuildIndexes()
            persist(record)
        }
    }

    /// Record a user correction. Series renames become aliases; everything is
    /// logged to correction_history. No-ops when nothing actually changed.
    func recordCorrection(
        originalSeries: String?, correctedSeries: String?,
        originalPublisher: String?, correctedPublisher: String?,
        filename: String?
    ) {
        let originalNorm = originalSeries.map(SeriesKnowledgeRecord.normalize)
        let correctedNorm = correctedSeries.map(SeriesKnowledgeRecord.normalize)

        let seriesChanged =
            originalNorm != nil && correctedNorm != nil && originalNorm != correctedNorm
            && originalNorm?.isEmpty == false
        let publisherChanged =
            correctedPublisher?.isEmpty == false
            && SeriesKnowledgeRecord.normalize(originalPublisher ?? "")
                != SeriesKnowledgeRecord.normalize(correctedPublisher ?? "")

        guard seriesChanged || publisherChanged else { return }

        // Learn the alias: next time the parser produces the "wrong" name,
        // it maps straight to the corrected series.
        if seriesChanged, let correctedNorm, let originalNorm,
            let i = indexByNormalized[correctedNorm]
        {
            var record = records[i]
            if !record.aliases.contains(originalNorm) {
                record.aliases.append(originalNorm)
                records[i] = record
                rebuildIndexes()
                persist(record)
                print(
                    "[SeriesKnowledge] 🎓 Learned alias: '\(originalSeries ?? "")' → '\(record.seriesName)'"
                )
            }
        }

        let correction = CorrectionRecord(
            originalSeries: originalSeries,
            correctedSeries: correctedSeries,
            originalPublisher: originalPublisher,
            correctedPublisher: correctedPublisher,
            sourceFileName: filename
        )
        Task { try? await database.logCorrection(correction) }
    }

    /// Remove a learned series (Learning view)
    func delete(_ record: SeriesKnowledgeRecord) {
        records.removeAll { $0.normalizedName == record.normalizedName }
        rebuildIndexes()
        Task {
            try? await database.deleteSeriesKnowledge(normalizedName: record.normalizedName)
        }
    }

    private func persist(_ record: SeriesKnowledgeRecord) {
        Task { try? await database.upsertSeriesKnowledge(record) }
    }
}
