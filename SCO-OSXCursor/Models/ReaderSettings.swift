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

// MARK: - EPUB Theme

enum EPUBTheme: String, CaseIterable, Codable {
    case dark = "Dark"
    case light = "Light"
    case sepia = "Sepia"
    
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .sepia: return "leaf.fill"
        }
    }
    
    var cssColors: (background: String, text: String, accent: String) {
        switch self {
        case .dark:
            return ("#1A1A1E", "#E8E6F0", "#9B8FE8")
        case .light:
            return ("#FFFFFF", "#1E1E26", "#6A5AE0")
        case .sepia:
            return ("#FBF0D9", "#5F4B32", "#D28E3D")
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
            // True push: the new page slides in from `direction` while the
            // old page slides out the opposite edge — both move together.
            return .asymmetric(
                insertion: .move(edge: direction),
                removal: .move(edge: direction == .trailing ? .leading : .trailing)
            )
        case .fade:
            return .opacity
        case .zoom:
            // Incoming page grows in; outgoing page expands slightly past
            // full size as it fades — a gentle depth cue instead of a blink
            return .asymmetric(
                insertion: .scale(scale: 0.94).combined(with: .opacity),
                removal: .scale(scale: 1.04).combined(with: .opacity)
            )
        case .none:
            return .identity
        }
    }

    func animation() -> Animation {
        switch self {
        case .slide:
            // Spring reads as a physical page push (Panels-like)
            return .spring(response: 0.38, dampingFraction: 0.86)
        case .zoom:
            return .easeInOut(duration: 0.35)
        case .fade:
            return .easeInOut(duration: 0.35)
        case .none:
            return .linear(duration: 0.05)
        }
    }
}

class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()

    @Published var pageTransition: PageTransition  // Global default transition
    @Published var defaultReadingStyle: ReadingStyle  // Global default reading style
    @Published var defaultEPUBTheme: EPUBTheme        // Global default EPUB theme
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

        if let saved = UserDefaults.standard.string(forKey: "defaultEPUBTheme"),
           let theme = EPUBTheme(rawValue: saved) {
            self.defaultEPUBTheme = theme
        } else {
            self.defaultEPUBTheme = .dark
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

        $defaultEPUBTheme
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { value in
                UserDefaults.standard.set(value.rawValue, forKey: "defaultEPUBTheme")
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

    // MARK: - EPUB Theme Helpers

    /// Get the effective EPUB theme for a specific comic
    func effectiveEPUBTheme(for comic: Comic?) -> EPUBTheme {
        if let comic = comic,
           let themeString = comic.epubTheme,
           let theme = EPUBTheme(rawValue: themeString) {
            return theme
        }
        return defaultEPUBTheme
    }

    /// Save per-book EPUB theme preference
    func setPreferredEPUBTheme(_ theme: EPUBTheme?, for comic: inout Comic) {
        comic.epubTheme = theme?.rawValue
        comic.dateModified = Date()
    }
}

