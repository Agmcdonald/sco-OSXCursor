//
//  DesignSystem.swift
//  SCO-OSXCursor
//
//  Created by Cursor AI on 11/6/25.
//

import SwiftUI

// MARK: - Background Colors
enum BackgroundColors {
    // Main app background - darkest
    static let primary = Color(hex: "#0F1419")        // RGB(15, 20, 25)
    
    // Secondary background - slightly lighter
    static let secondary = Color(hex: "#1A1F26")      // RGB(26, 31, 38)
    
    // Elevated surfaces (cards, panels)
    static let elevated = Color(hex: "#232931")       // RGB(35, 41, 49)
    
    // Sidebar background
    static let sidebar = Color(hex: "#16191E")        // RGB(22, 25, 30)
}

// MARK: - Text Colors
enum TextColors {
    // Primary text - high emphasis
    static let primary = Color.white.opacity(0.95)    // Almost white
    
    // Secondary text - medium emphasis
    static let secondary = Color.white.opacity(0.60)  // Gray-white
    
    // Tertiary text - low emphasis
    static let tertiary = Color.white.opacity(0.40)   // Subtle gray
    
    // Disabled text
    static let disabled = Color.white.opacity(0.25)   // Very subtle
}

// MARK: - Accent Colors
enum AccentColors {
    // Primary action - buttons, links, selection
    static let primary = Color(hex: "#3B82F6")        // Blue - RGB(59, 130, 246)
    
    // Hover state
    static let primaryHover = Color(hex: "#2563EB")   // Darker blue
    
    // Active state
    static let primaryActive = Color(hex: "#1D4ED8")  // Even darker blue
    
    // Success
    static let success = Color(hex: "#10B981")        // Green
    
    // Warning
    static let warning = Color(hex: "#F59E0B")        // Amber
    
    // Error/Delete
    static let error = Color(hex: "#EF4444")          // Red
}

// MARK: - Semantic Colors
enum SemanticColors {
    // Publisher badges
    static let dcComics = Color(hex: "#3B82F6")       // Blue
    static let marvel = Color(hex: "#EF4444")         // Red
    static let imageComics = Color(hex: "#F59E0B")    // Orange
    static let darkHorse = Color(hex: "#EAB308")      // Yellow
    static let vertigo = Color(hex: "#8B5CF6")        // Purple
    
    // Status indicators
    static let unread = Color(hex: "#3B82F6")         // Blue
    static let reading = Color(hex: "#F59E0B")        // Orange
    static let completed = Color(hex: "#10B981")      // Green
    
    // Selection overlay
    static let selectionOverlay = Color(hex: "#3B82F6").opacity(0.15)
}

// MARK: - Border Colors
enum BorderColors {
    // Subtle dividers
    static let subtle = Color.white.opacity(0.08)
    
    // Regular borders
    static let regular = Color.white.opacity(0.12)
    
    // Emphasized borders
    static let emphasized = Color.white.opacity(0.20)
    
    // Focus/Selected state
    static let focus = AccentColors.primary
}

// MARK: - Typography
enum Typography {
    // MARK: - Headings
    
    // Page titles (e.g., "Library")
    static let h1 = Font.system(size: 32, weight: .bold, design: .default)
    
    // Section headers
    static let h2 = Font.system(size: 24, weight: .semibold, design: .default)
    
    // Card titles
    static let h3 = Font.system(size: 18, weight: .semibold, design: .default)
    
    // MARK: - Body Text
    
    // Primary body text
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    
    // Secondary body text
    static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)
    
    // MARK: - UI Text
    
    // Buttons
    static let button = Font.system(size: 14, weight: .medium, design: .default)
    
    // Navigation items
    static let navigation = Font.system(size: 15, weight: .medium, design: .default)
    
    // MARK: - Labels
    
    // Small labels (issue numbers, years)
    static let caption = Font.system(size: 12, weight: .regular, design: .default)
    
    // Metadata labels
    static let label = Font.system(size: 11, weight: .medium, design: .default)
    
    // Tiny labels (badges)
    static let tiny = Font.system(size: 10, weight: .medium, design: .default)
}

// MARK: - Layout
enum Layout {
    // MARK: - Window
    static let minWindowWidth: CGFloat = 1200
    static let minWindowHeight: CGFloat = 700
    static let defaultWindowWidth: CGFloat = 1440
    static let defaultWindowHeight: CGFloat = 900
    
    // MARK: - Sidebar
    static let sidebarWidth: CGFloat = 240
    static let sidebarCollapsedWidth: CGFloat = 72
    
    // MARK: - Detail Panel (Right side)
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
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            // Background Colors
            VStack(alignment: .leading, spacing: 12) {
                Text("Background Colors")
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
                
                HStack(spacing: 12) {
                    ColorSwatch(color: BackgroundColors.primary, name: "Primary")
                    ColorSwatch(color: BackgroundColors.secondary, name: "Secondary")
                    ColorSwatch(color: BackgroundColors.elevated, name: "Elevated")
                    ColorSwatch(color: BackgroundColors.sidebar, name: "Sidebar")
                }
            }
            
            // Accent Colors
            VStack(alignment: .leading, spacing: 12) {
                Text("Accent Colors")
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
                
                HStack(spacing: 12) {
                    ColorSwatch(color: AccentColors.primary, name: "Primary")
                    ColorSwatch(color: AccentColors.success, name: "Success")
                    ColorSwatch(color: AccentColors.warning, name: "Warning")
                    ColorSwatch(color: AccentColors.error, name: "Error")
                }
            }
            
            // Typography Examples
            VStack(alignment: .leading, spacing: 12) {
                Text("Typography")
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Heading 1").font(Typography.h1).foregroundColor(TextColors.primary)
                    Text("Heading 2").font(Typography.h2).foregroundColor(TextColors.primary)
                    Text("Heading 3").font(Typography.h3).foregroundColor(TextColors.primary)
                    Text("Body Text").font(Typography.body).foregroundColor(TextColors.secondary)
                    Text("Caption Text").font(Typography.caption).foregroundColor(TextColors.tertiary)
                }
            }
            
            // Spacing Examples
            VStack(alignment: .leading, spacing: 12) {
                Text("Spacing Scale")
                    .font(Typography.h2)
                    .foregroundColor(TextColors.primary)
                
                VStack(alignment: .leading, spacing: 4) {
                    SpacingBar(size: Spacing.xs, label: "XS (4pt)")
                    SpacingBar(size: Spacing.sm, label: "SM (8pt)")
                    SpacingBar(size: Spacing.md, label: "MD (12pt)")
                    SpacingBar(size: Spacing.lg, label: "LG (16pt)")
                    SpacingBar(size: Spacing.xl, label: "XL (20pt)")
                    SpacingBar(size: Spacing.xxl, label: "XXL (24pt)")
                }
            }
        }
        .padding(24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(BackgroundColors.primary)
}

// MARK: - Preview Helpers
struct ColorSwatch: View {
    let color: Color
    let name: String
    
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BorderColors.regular, lineWidth: 1)
                )
            
            Text(name)
                .font(Typography.caption)
                .foregroundColor(TextColors.secondary)
        }
    }
}

struct SpacingBar: View {
    let size: CGFloat
    let label: String
    
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AccentColors.primary)
                .frame(width: size, height: 20)
            
            Text(label)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
            
            Spacer()
        }
    }
}

