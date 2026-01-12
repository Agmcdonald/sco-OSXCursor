//
//  DesignSystem.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

// MARK: - Background Colors
enum BackgroundColors {
    // Main app background
    static let primary = Color.adaptive(light: "#FFFFFF", dark: "#0F1419")

    // Secondary background
    static let secondary = Color.adaptive(light: "#F8F9FA", dark: "#1A1F26")

    // Elevated surfaces (cards, panels)
    static let elevated = Color.adaptive(light: "#FFFFFF", dark: "#232931")

    // Sidebar background
    static let sidebar = Color.adaptive(light: "#F0F2F5", dark: "#16191E")
}

// MARK: - Text Colors
enum TextColors {
    // Primary text - high emphasis
    static let primary = Color.adaptive(light: "#1A1F26", dark: "#F2F2F2")

    // Secondary text - medium emphasis
    static let secondary = Color.adaptive(light: "#4A5568", dark: "#A0AEC0")

    // Tertiary text - low emphasis
    static let tertiary = Color.adaptive(light: "#718096", dark: "#718096")

    // Disabled text
    static let disabled = Color.adaptive(light: "#A0AEC0", dark: "#4A5568")
}

// MARK: - Accent Colors
enum AccentColors {
    // Primary action - buttons, links, selection
    static let primary = Color(hex: "#3B82F6")  // Blue
    static let primaryHover = Color(hex: "#2563EB")
    static let primaryActive = Color(hex: "#1D4ED8")

    static let success = Color(hex: "#10B981")  // Green
    static let warning = Color(hex: "#F59E0B")  // Amber
    static let error = Color(hex: "#EF4444")  // Red
}

// MARK: - Semantic Colors
enum SemanticColors {
    // Publisher colors
    static let dcComics = Color(hex: "#3B82F6")
    static let marvel = Color(hex: "#EF4444")
    static let imageComics = Color(hex: "#F59E0B")
    static let darkHorse = Color(hex: "#EAB308")
    static let vertigo = Color(hex: "#8B5CF6")

    // Status indicators
    static let unread = Color(hex: "#3B82F6")
    static let reading = Color(hex: "#F59E0B")
    static let completed = Color(hex: "#10B981")

    static let selectionOverlay = Color(hex: "#3B82F6").opacity(0.15)
}

// MARK: - Border Colors
enum BorderColors {
    static let subtle = Color.adaptive(light: "#E2E8F0", dark: "#FFFFFF", darkOpacity: 0.08)
    static let regular = Color.adaptive(light: "#CBD5E0", dark: "#FFFFFF", darkOpacity: 0.12)
    static let emphasized = Color.adaptive(light: "#A0AEC0", dark: "#FFFFFF", darkOpacity: 0.20)
    static let focus = AccentColors.primary
}

// MARK: - Typography
enum Typography {
    // MARK: - Headings
    static let h1 = Font.system(size: 32, weight: .bold, design: .default)
    static let h2 = Font.system(size: 24, weight: .semibold, design: .default)
    static let h3 = Font.system(size: 18, weight: .semibold, design: .default)

    // MARK: - Body Text
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)

    // MARK: - UI Text
    static let button = Font.system(size: 14, weight: .medium, design: .default)
    static let navigation = Font.system(size: 15, weight: .medium, design: .default)

    // MARK: - Labels
    static let caption = Font.system(size: 12, weight: .regular, design: .default)
    static let label = Font.system(size: 11, weight: .medium, design: .default)
    static let tiny = Font.system(size: 10, weight: .medium, design: .default)
}

// MARK: - App Layout
enum AppLayout {
    static let minWindowWidth: CGFloat = 1200
    static let minWindowHeight: CGFloat = 700
    static let defaultWindowWidth: CGFloat = 1440
    static let defaultWindowHeight: CGFloat = 900

    static let sidebarWidth: CGFloat = 240
    static let sidebarCollapsedWidth: CGFloat = 72

    static let detailPanelWidth: CGFloat = 360
    static let detailPanelMinWidth: CGFloat = 300
    static let detailPanelMaxWidth: CGFloat = 480
}

// MARK: - Spacing
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

// MARK: - Color Extension (Hex Support)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Create an adaptive color that responds to light/dark mode
    static func adaptive(
        light: String, dark: String, lightOpacity: Double = 1.0, darkOpacity: Double = 1.0
    ) -> Color {
        #if os(macOS)
            return Color(
                NSColor(name: nil) { appearance in
                    if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                        return NSColor(hex: dark).withAlphaComponent(CGFloat(darkOpacity))
                    }
                    return NSColor(hex: light).withAlphaComponent(CGFloat(lightOpacity))
                })
        #else
            return Color(
                UIColor { traitCollection in
                    if traitCollection.userInterfaceStyle == .dark {
                        return UIColor(hex: dark).withAlphaComponent(CGFloat(darkOpacity))
                    }
                    return UIColor(hex: light).withAlphaComponent(CGFloat(lightOpacity))
                })
        #endif
    }
}

// MARK: - Platform Color Extensions
#if os(macOS)
    extension NSColor {
        convenience init(hex: String) {
            let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&int)
            let r: UInt64
            let g: UInt64
            let b: UInt64
            switch hex.count {
            case 3:  // RGB (12-bit)
                (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
            case 6:  // RGB (24-bit)
                (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
            default:
                (r, g, b) = (255, 255, 255)
            }
            self.init(
                red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1.0)
        }
    }
#else
    extension UIColor {
        convenience init(hex: String) {
            let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&int)
            let r: UInt64
            let g: UInt64
            let b: UInt64
            switch hex.count {
            case 3:  // RGB (12-bit)
                (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
            case 6:  // RGB (24-bit)
                (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
            default:
                (r, g, b) = (255, 255, 255)
            }
            self.init(
                red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1.0)
        }
    }
#endif
