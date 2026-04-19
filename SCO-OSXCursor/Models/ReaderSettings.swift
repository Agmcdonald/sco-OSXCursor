//
//  ReaderSettings.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/9/25.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Reading Style

enum ReadingStyle: String, CaseIterable, Codable {
    case standard    = "Standard"
    case verticalScroll = "Vertical Scroll"
    case mangaRTL    = "Manga / Manhwa"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .standard:      return "book"
        case .verticalScroll: return "arrow.down.to.line"
        case .mangaRTL:      return "arrow.left.to.line"
        }
    }

    var description: String {
        switch self {
        case .standard:
            return "Left-to-right paged reading. Swipe or use arrow keys to turn pages."
        case .verticalScroll:
            return "Continuous vertical strip. Optimized for webtoons and infinite-scroll comics."
        case .mangaRTL:
            return "Right-to-left reading order. Navigation is reversed for manga and manhwa."
        }
    }
}

// MARK: - Page Transition

enum PageTransition: String, CaseIterable, Codable {
    case slide = "Slide"
    case fade = "Fade"
    case zoom = "Zoom"
    case none = "None"
    
    var icon: String {
        switch self {
        case .slide: return "arrow.left.arrow.right"
        case .fade: return "circle.dotted"
        case .zoom: return "arrow.up.left.and.arrow.down.right"
        case .none: return "minus"
        }
    }
    
    var isAvailableOnCurrentPlatform: Bool {
        return true
    }
    
    func transition(for direction: Edge) -> AnyTransition {
        switch self {
        case .slide:
            return .asymmetric(
                insertion: .move(edge: direction),
                removal: .move(edge: direction == .trailing ? .leading : .trailing)
            )
        case .fade:
            return .opacity
        case .zoom:
            return .scale.combined(with: .opacity)
        case .none:
            return .identity
        }
    }
    
    func animation() -> Animation {
        #if os(macOS)
        let baseDuration = 0.25  // Faster on macOS for performance
        #else
        let baseDuration = 0.3
        #endif
        
        switch self {
        case .slide, .zoom:
            return .easeInOut(duration: baseDuration)
        case .fade:
            return .easeInOut(duration: 0.2)
        case .none:
            return .linear(duration: 0.05)
        }
    }
}

class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()

    @Published var pageTransition: PageTransition  // Global default transition
    @Published var defaultReadingStyle: ReadingStyle  // Global default reading style
    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "pageTransition"),
           let transition = PageTransition(rawValue: saved) {
            self.pageTransition = transition
        } else {
            self.pageTransition = .slide
        }

        if let saved = UserDefaults.standard.string(forKey: "defaultReadingStyle"),
           let style = ReadingStyle(rawValue: saved) {
            self.defaultReadingStyle = style
        } else {
            self.defaultReadingStyle = .standard
        }

        // Debounced save on main thread (macOS 26 safe)
        $pageTransition
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { value in
                UserDefaults.standard.set(value.rawValue, forKey: "pageTransition")
            }
            .store(in: &cancellables)

        $defaultReadingStyle
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { value in
                UserDefaults.standard.set(value.rawValue, forKey: "defaultReadingStyle")
            }
            .store(in: &cancellables)
    }

    // MARK: - Transition Helpers

    /// Get the effective transition for a specific comic (uses book's preference if set, otherwise global default)
    func effectiveTransition(for comic: Comic?) -> PageTransition {
        if let comic = comic,
           let preferredString = comic.preferredTransition,
           let preferred = PageTransition(rawValue: preferredString),
           preferred.isAvailableOnCurrentPlatform {
            return preferred
        }
        return pageTransition
    }

    /// Save per-book transition preference
    func setPreferredTransition(_ transition: PageTransition?, for comic: inout Comic) {
        comic.preferredTransition = transition?.rawValue
        comic.dateModified = Date()
    }

    // MARK: - Reading Style Helpers

    /// Get the effective reading style for a specific comic (per-book override, then global default)
    func effectiveReadingStyle(for comic: Comic?) -> ReadingStyle {
        if let comic = comic,
           let styleString = comic.readingStyle,
           let style = ReadingStyle(rawValue: styleString) {
            return style
        }
        return defaultReadingStyle
    }

    /// Save per-book reading style preference
    func setPreferredReadingStyle(_ style: ReadingStyle?, for comic: inout Comic) {
        comic.readingStyle = style?.rawValue
        comic.dateModified = Date()
    }
}

