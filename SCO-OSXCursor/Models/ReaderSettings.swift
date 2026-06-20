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
    case curl = "Page Curl"
    case fade = "Fade"
    case zoom = "Zoom"
    case none = "None"

    var icon: String {
        switch self {
        case .slide: return "arrow.left.arrow.right"
        case .curl: return "book.pages"
        case .fade: return "circle.dotted"
        case .zoom: return "arrow.up.left.and.arrow.down.right"
        case .none: return "minus"
        }
    }

    var isAvailableOnCurrentPlatform: Bool {
        switch self {
        case .curl:
            // Apple Books-style curl uses UIPageViewController — iOS/iPadOS only
            #if os(iOS)
                return true
            #else
                return false
            #endif
        default:
            return true
        }
    }
    
    func transition(for direction: Edge) -> AnyTransition {
        switch self {
        case .slide, .curl:
            // .curl renders via UIPageViewController on iOS; this branch is
            // the macOS/SwiftUI fallback (a slide push) for synced books
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
        case .slide, .curl:
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

// MARK: - EPUB Typography

/// Reader font for EPUBs. `.system` preserves the original stack
/// (`-apple-system` first, so it renders San Francisco).
enum EPUBFontFamily: String, CaseIterable, Codable {
    case system = "System"
    case newYork = "New York"
    case georgia = "Georgia"
    case palatino = "Palatino"
    case charter = "Charter"

    var displayName: String { rawValue }

    var cssFontFamily: String {
        switch self {
        case .system: return "-apple-system, 'Georgia', serif"  // original default stack
        case .newYork: return "ui-serif, 'Georgia', serif"      // Apple New York via WebKit ui-serif
        case .georgia: return "'Georgia', serif"
        case .palatino: return "'Palatino', 'Book Antiqua', ui-serif, serif"
        case .charter: return "'Charter', ui-serif, serif"
        }
    }
}

/// Line spacing for EPUB text. `.normal` matches the original 1.75.
enum EPUBLineSpacing: String, CaseIterable, Codable {
    case compact = "Compact"
    case normal = "Normal"
    case relaxed = "Relaxed"

    var displayName: String { rawValue }

    var value: Double {
        switch self {
        case .compact: return 1.5
        case .normal: return 1.75   // original hard-coded value
        case .relaxed: return 2.05
        }
    }
}

/// Page margins for EPUB text. `.normal` matches the original layout values.
enum EPUBMargins: String, CaseIterable, Codable {
    case narrow = "Narrow"
    case normal = "Normal"
    case wide = "Wide"

    var displayName: String { rawValue }

    /// Vertical-scroll mode: horizontal text inset (pt)
    var verticalPadding: Int {
        switch self {
        case .narrow: return 16
        case .normal: return 24    // original
        case .wide: return 40
        }
    }

    /// Vertical-scroll mode: max text column width (pt)
    var maxTextWidth: Int {
        switch self {
        case .narrow: return 780
        case .normal: return 680   // original
        case .wide: return 560
        }
    }

    /// Horizontal (paged) mode: page inset; column width/gap derive from it
    var horizontalPadding: Int {
        switch self {
        case .narrow: return 12
        case .normal: return 20    // original
        case .wide: return 32
        }
    }
}

// MARK: - Tap Zone Width

/// How much of each screen edge acts as a page-turn tap zone (per side).
enum TapZoneWidth: String, CaseIterable, Codable {
    case narrow = "Narrow"
    case medium = "Medium"
    case wide = "Wide"

    /// Fraction of screen width per side
    var fraction: CGFloat {
        switch self {
        case .narrow: return 0.10
        case .medium: return 0.15
        case .wide: return 0.30
        }
    }

    var description: String {
        switch self {
        case .narrow: return "10% per side"
        case .medium: return "15% per side"
        case .wide: return "30% per side"
        }
    }
}

class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()

    @Published var pageTransition: PageTransition  // Global default transition
    @Published var defaultReadingStyle: ReadingStyle  // Global default reading style
    @Published var defaultEPUBTheme: EPUBTheme        // Global default EPUB theme
    @Published var tapZoneWidth: TapZoneWidth         // Edge tap-zone width (app-wide)
    // EPUB typography (app-wide; font SIZE stays per-book via epubFontSize)
    @Published var epubFontFamily: EPUBFontFamily
    @Published var epubLineSpacing: EPUBLineSpacing
    @Published var epubMargins: EPUBMargins
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

        if let saved = UserDefaults.standard.string(forKey: "tapZoneWidth"),
           let width = TapZoneWidth(rawValue: saved) {
            self.tapZoneWidth = width
        } else {
            self.tapZoneWidth = .medium
        }

        self.epubFontFamily = UserDefaults.standard.string(forKey: "epubFontFamily")
            .flatMap { EPUBFontFamily(rawValue: $0) } ?? .system
        self.epubLineSpacing = UserDefaults.standard.string(forKey: "epubLineSpacing")
            .flatMap { EPUBLineSpacing(rawValue: $0) } ?? .normal
        self.epubMargins = UserDefaults.standard.string(forKey: "epubMargins")
            .flatMap { EPUBMargins(rawValue: $0) } ?? .normal

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

        $tapZoneWidth
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { value in
                UserDefaults.standard.set(value.rawValue, forKey: "tapZoneWidth")
            }
            .store(in: &cancellables)

        $epubFontFamily
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "epubFontFamily") }
            .store(in: &cancellables)

        $epubLineSpacing
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "epubLineSpacing") }
            .store(in: &cancellables)

        $epubMargins
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "epubMargins") }
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

