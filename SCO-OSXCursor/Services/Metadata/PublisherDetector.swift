//
//  PublisherDetector.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/7/25.
//

import Foundation
import SwiftUI

// MARK: - Publisher Detector
struct PublisherDetector {

    /// Publisher pattern matching database
    private static let publishers: [PublisherInfo] = [
        // Big Two
        PublisherInfo(
            name: "DC Comics", aliases: ["dc comics", "dc", "dccomics"],
            color: SemanticColors.dcComics),
        PublisherInfo(
            name: "Marvel Comics", aliases: ["marvel", "marvel comics", "marvelcomics"],
            color: SemanticColors.marvel),

        // Major Publishers
        PublisherInfo(
            name: "Image Comics", aliases: ["image", "image comics"],
            color: SemanticColors.imageComics),
        PublisherInfo(
            name: "Dark Horse Comics", aliases: ["dark horse", "darkhorse"],
            color: SemanticColors.darkHorse),
        PublisherInfo(
            name: "IDW Publishing", aliases: ["idw", "idw publishing"], color: Color.blue),
        PublisherInfo(
            name: "Boom! Studios", aliases: ["boom", "boom!", "boom studios"], color: Color.orange),
        PublisherInfo(
            name: "Valiant Comics", aliases: ["valiant", "valiant entertainment"], color: Color.red),
        PublisherInfo(name: "Dynamite Entertainment", aliases: ["dynamite"], color: Color.yellow),

        // Imprints & Subsidiaries
        PublisherInfo(name: "Vertigo", aliases: ["vertigo"], color: SemanticColors.vertigo),
        PublisherInfo(name: "WildStorm", aliases: ["wildstorm"], color: Color.teal),
        PublisherInfo(name: "MAX Comics", aliases: ["max", "max comics"], color: Color.red),
        PublisherInfo(name: "Icon Comics", aliases: ["icon", "icon comics"], color: Color.blue),
        PublisherInfo(
            name: "Black Label", aliases: ["black label", "dc black label"], color: Color.black),

        // Independent
        PublisherInfo(name: "Fantagraphics", aliases: ["fantagraphics"], color: Color.purple),
        PublisherInfo(
            name: "Drawn & Quarterly", aliases: ["drawn and quarterly", "drawn & quarterly"],
            color: Color.indigo),
        PublisherInfo(name: "Viz Media", aliases: ["viz", "viz media"], color: Color.red),
        PublisherInfo(name: "Kodansha", aliases: ["kodansha"], color: Color.orange),
        PublisherInfo(name: "Yen Press", aliases: ["yen press"], color: Color.blue),

        // Digital First
        PublisherInfo(name: "Webtoon", aliases: ["webtoon"], color: Color.green),
        PublisherInfo(name: "Tapas", aliases: ["tapas"], color: Color.orange),

        // Classic
        PublisherInfo(name: "EC Comics", aliases: ["ec comics", "ec"], color: Color.brown),
        PublisherInfo(name: "Gold Key", aliases: ["gold key"], color: Color.yellow),
        PublisherInfo(name: "Dell Comics", aliases: ["dell", "dell comics"], color: Color.green),
    ]

    /// Detect publisher from string (metadata, filename, etc.)
    static func detect(from text: String?) -> PublisherInfo? {
        guard let text = text?.lowercased() else { return nil }

        // Try exact and partial matches
        for publisher in publishers {
            for alias in publisher.aliases {
                if text.contains(alias) {
                    return publisher
                }
            }
        }

        return nil
    }

    /// Exact (whole-string) publisher match — for folder names, where the
    /// substring matching of `detect(from:)` would false-positive
    /// (e.g. "Pyrate-DCP" contains "dc").
    static func exactMatch(_ name: String) -> String? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        for publisher in publishers {
            if publisher.name.lowercased() == normalized || publisher.aliases.contains(normalized) {
                return publisher.name
            }
        }
        return nil
    }

    /// Get color for a publisher
    static func color(for publisherName: String?) -> Color {
        guard let publisher = detect(from: publisherName) else {
            return AccentColors.primary
        }
        return publisher.color
    }

    /// Normalize publisher name (e.g., "DC" -> "DC Comics")
    static func normalize(_ publisherName: String?) -> String? {
        guard let detected = detect(from: publisherName) else {
            return publisherName
        }
        return detected.name
    }

    /// Extract publisher from metadata (checks multiple fields)
    static func extract(from metadata: ComicMetadata) -> String? {
        // Priority order: publisher field, imprint, scan info patterns
        if let publisher = metadata.publisher, !publisher.isEmpty {
            return normalize(publisher)
        }

        if let imprint = metadata.imprint, !imprint.isEmpty {
            return normalize(imprint)
        }

        // Try to extract from title or series
        if let series = metadata.series {
            if let detected = detect(from: series) {
                return detected.name
            }
        }

        return nil
    }

    // MARK: - Character-Based Publisher Inference

    /// Map of fictional character/team names to their publishers.
    /// Used as a fallback when no publisher is found via aliases or parenthetical content.
    /// Ported from sco-dyad's characterPublisherMap (with Jean Grey bug fixed).
    private static let characterPublisherMap: [String: String] = [
        // DC Comics characters
        "superman": "DC Comics", "batman": "DC Comics", "wonder woman": "DC Comics",
        "flash": "DC Comics", "green lantern": "DC Comics", "aquaman": "DC Comics",
        "cyborg": "DC Comics", "green arrow": "DC Comics", "martian manhunter": "DC Comics",
        "shazam": "DC Comics", "nightwing": "DC Comics", "robin": "DC Comics",
        "batgirl": "DC Comics", "supergirl": "DC Comics", "harley quinn": "DC Comics",
        "joker": "DC Comics", "catwoman": "DC Comics", "poison ivy": "DC Comics",
        "lex luthor": "DC Comics", "deathstroke": "DC Comics", "teen titans": "DC Comics",
        "justice league": "DC Comics", "birds of prey": "DC Comics", "suicide squad": "DC Comics",

        // Marvel Comics characters
        "spider-man": "Marvel Comics", "spiderman": "Marvel Comics",
        "iron man": "Marvel Comics", "captain america": "Marvel Comics",
        "thor": "Marvel Comics", "hulk": "Marvel Comics", "black widow": "Marvel Comics",
        "hawkeye": "Marvel Comics", "ant-man": "Marvel Comics", "wasp": "Marvel Comics",
        "captain marvel": "Marvel Comics", "ms marvel": "Marvel Comics",
        "daredevil": "Marvel Comics", "punisher": "Marvel Comics", "deadpool": "Marvel Comics",
        "wolverine": "Marvel Comics", "x-men": "Marvel Comics", "fantastic four": "Marvel Comics",
        "avengers": "Marvel Comics", "guardians of the galaxy": "Marvel Comics",
        "doctor strange": "Marvel Comics", "scarlet witch": "Marvel Comics",
        "vision": "Marvel Comics", "falcon": "Marvel Comics", "winter soldier": "Marvel Comics",
        "black panther": "Marvel Comics", "storm": "Marvel Comics", "cyclops": "Marvel Comics",
        "jean grey": "Marvel Comics", "magneto": "Marvel Comics", "professor x": "Marvel Comics",
        "venom": "Marvel Comics", "carnage": "Marvel Comics", "green goblin": "Marvel Comics",
        "doctor octopus": "Marvel Comics", "thanos": "Marvel Comics", "loki": "Marvel Comics",
        "galactus": "Marvel Comics",
    ]

    /// Detect publisher by scanning a series name for known character/team names.
    /// This is a fallback — use `detect(from:)` for alias-based matching first.
    static func detectFromCharacters(_ seriesName: String?) -> String? {
        guard let seriesName = seriesName else { return nil }
        let lowerSeries = seriesName.lowercased()
        for (character, publisher) in characterPublisherMap {
            if lowerSeries.contains(character) {
                return publisher
            }
        }
        return nil
    }
}
struct PublisherInfo {
    let name: String
    let aliases: [String]
    let color: Color
}
