# Super Comic Organizer - Design Reference Guide
## Based on Electron Prototype Screenshots

**Purpose:** This document provides detailed design specifications extracted from the Electron prototype to guide Cursor in recreating the exact visual style in the native Swift/SwiftUI app.

---

## Table of Contents
1. [Design Overview](#design-overview)
2. [Color Palette](#color-palette)
3. [Typography](#typography)
4. [Layout System](#layout-system)
5. [Component Specifications](#component-specifications)
6. [Navigation & Sidebar](#navigation--sidebar)
7. [Library View](#library-view)
8. [Detail Panel](#detail-panel)
9. [Reader View](#reader-view)
10. [Spacing & Grid](#spacing--grid)

---

## Design Overview

### Style Keywords
- **Dark Theme Dominant** - Deep, near-black backgrounds
- **High Contrast** - Bright comic covers against dark UI
- **Content-First** - UI elements are subtle, letting comics shine
- **Clean & Modern** - Minimal chrome, no unnecessary decoration
- **Professional** - Polished, production-quality appearance

### Design Philosophy
The app uses a **dark-by-default** interface that:
1. Reduces eye strain during long reading sessions
2. Makes colorful comic covers "pop" visually
3. Provides professional, modern aesthetic
4. Saves battery on OLED displays (iPad Pro, MacBook Pro)

---

## Color Palette

### Background Colors

```swift
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
```

### Text Colors

```swift
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
```

### Accent Colors

```swift
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
```

### Semantic Colors

```swift
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
```

### Border Colors

```swift
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
```

---

## Typography

### Font Family
Use **San Francisco** (system default) for all text. This ensures native feel and excellent readability.

### Font Sizes & Weights

```swift
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
```

### Text Styling Examples

```swift
// Page Title
Text("Library")
    .font(Typography.h1)
    .foregroundColor(TextColors.primary)

// Comic Title
Text("Absolute Batman")
    .font(Typography.h3)
    .foregroundColor(TextColors.primary)
    .lineLimit(2)

// Comic Metadata
Text("Issue #013 (2025)")
    .font(Typography.caption)
    .foregroundColor(TextColors.secondary)

// Sidebar Item
Text("Dashboard")
    .font(Typography.navigation)
    .foregroundColor(TextColors.secondary)
```

---

## Layout System

### Window & Panel Sizes

```swift
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
```

### Three-Column Layout

The app uses a **three-column layout**:

```
┌────────────┬──────────────────────────────────┬────────────┐
│  Sidebar   │     Main Content Area            │   Detail   │
│  (240px)   │     (Flexible)                   │   (360px)  │
│            │                                  │            │
│ Dashboard  │  ┌─────┬─────┬─────┬─────┐     │  [Cover]   │
│ Library    │  │Comic│Comic│Comic│Comic│     │            │
│ Organize   │  │ #1  │ #2  │ #3  │ #4  │     │  Info      │
│ Learning   │  └─────┴─────┴─────┴─────┘     │  Details   │
│ Knowledge  │  ┌─────┬─────┬─────┬─────┐     │            │
│ Maintenance│  │Comic│Comic│Comic│Comic│     │  Buttons   │
│ Settings   │  │ #5  │ #6  │ #7  │ #8  │     │            │
│            │  └─────┴─────┴─────┴─────┘     │            │
└────────────┴──────────────────────────────────┴────────────┘
```

---

## Component Specifications

### 1. Sidebar Navigation

#### Visual Specs
- **Background:** `BackgroundColors.sidebar`
- **Width:** 240px
- **Item Height:** 44px
- **Icon Size:** 18x18px
- **Text:** `Typography.navigation`
- **Hover:** `BackgroundColors.elevated`
- **Selected:** `AccentColors.primary.opacity(0.12)` background + `AccentColors.primary` text

#### Structure
```swift
struct SidebarItem: View {
    let icon: String        // SF Symbol name
    let title: String
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 18, height: 18)
            
            Text(title)
                .font(Typography.navigation)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? AccentColors.primary.opacity(0.12) : Color.clear)
        .foregroundColor(isSelected ? AccentColors.primary : TextColors.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
    }
}
```

#### Navigation Items
```swift
let navigationItems = [
    ("chart.bar", "Dashboard"),
    ("books.vertical", "Library"),
    ("folder.badge.gearshape", "Organize"),
    ("brain.head.profile", "Learning"),
    ("book.closed", "Knowledge"),
    ("wrench.and.screwdriver", "Maintenance"),
    ("gear", "Settings")
]
```

---

### 2. Comic Card (Grid View)

#### Visual Specs
- **Card Width:** 160px
- **Card Height:** ~280px (including text)
- **Cover Aspect Ratio:** 2:3 (standard comic book)
- **Cover Height:** 240px
- **Corner Radius:** 8px
- **Shadow:** Subtle drop shadow
- **Hover Effect:** Lift + brighter shadow

#### Structure
```swift
struct ComicCard: View {
    let comic: Comic
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover Image
            ZStack {
                if let coverImage = comic.coverImage {
                    Image(nsImage: coverImage)
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                        .frame(width: 160, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    // Placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(BackgroundColors.elevated)
                        .frame(width: 160, height: 240)
                        .overlay(
                            VStack {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 32))
                                    .foregroundColor(TextColors.tertiary)
                                Text("No Cover")
                                    .font(Typography.caption)
                                    .foregroundColor(TextColors.tertiary)
                            }
                        )
                }
                
                // DC/Marvel badge (top-right corner)
                if let publisher = comic.publisher {
                    VStack {
                        HStack {
                            Spacer()
                            PublisherBadge(publisher: publisher)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .shadow(
                color: .black.opacity(isHovered ? 0.4 : 0.2),
                radius: isHovered ? 12 : 6,
                x: 0,
                y: isHovered ? 6 : 3
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            
            // Title
            Text(comic.title ?? "Unknown")
                .font(Typography.h3)
                .foregroundColor(TextColors.primary)
                .lineLimit(2)
                .frame(width: 160, alignment: .leading)
            
            // Issue & Year
            HStack(spacing: 4) {
                if let issue = comic.issueNumber {
                    Text("Issue #\(issue)")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.secondary)
                }
                if let year = comic.year {
                    Text("(\(year))")
                        .font(Typography.caption)
                        .foregroundColor(TextColors.tertiary)
                }
            }
        }
        .frame(width: 160)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
```

#### Grid Layout
```swift
let columns = [
    GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)
]

LazyVGrid(columns: columns, spacing: 24) {
    ForEach(comics) { comic in
        ComicCard(comic: comic)
            .onTapGesture {
                selectedComic = comic
            }
    }
}
.padding(20)
```

---

### 3. Detail Panel (Right Side)

#### Visual Specs
- **Width:** 360px
- **Background:** `BackgroundColors.secondary`
- **Padding:** 20px
- **Border:** Left border with `BorderColors.subtle`

#### Structure
```swift
struct DetailPanel: View {
    let comic: Comic
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Large Cover Preview
                if let coverImage = comic.coverImage {
                    Image(nsImage: coverImage)
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.3), radius: 12)
                }
                
                // Basic Information Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Basic Information")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    
                    DetailRow(label: "Publisher", value: comic.publisher ?? "Unknown")
                    DetailRow(label: "Volume", value: comic.volume ?? "—")
                    DetailRow(label: "Publication Date", value: comic.publicationDate ?? "—")
                }
                
                // Summary Section
                if let summary = comic.summary {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(Typography.h3)
                            .foregroundColor(TextColors.primary)
                        
                        Text(summary)
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.secondary)
                            .lineSpacing(4)
                    }
                }
                
                // Rating Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Rating")
                        .font(Typography.h3)
                        .foregroundColor(TextColors.primary)
                    
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= (comic.rating ?? 0) ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                                .font(.system(size: 20))
                        }
                    }
                }
                
                // Action Buttons
                VStack(spacing: 12) {
                    PrimaryButton(title: "Read Comic", icon: "book") {
                        // Open reader
                    }
                    
                    HStack(spacing: 12) {
                        SecondaryButton(title: "Add to List", icon: "plus.circle") {
                            // Add to list
                        }
                        
                        SecondaryButton(title: "Mark Read", icon: "checkmark.circle") {
                            // Mark as read
                        }
                    }
                    
                    SecondaryButton(title: "Fix Cover", icon: "photo") {
                        // Fix cover
                    }
                    
                    SecondaryButton(title: "Set as Series Cover", icon: "square.on.square") {
                        // Set as series cover
                    }
                    
                    SecondaryButton(title: "Edit", icon: "pencil") {
                        // Edit metadata
                    }
                    
                    DangerButton(title: "Delete", icon: "trash") {
                        // Delete comic
                    }
                }
            }
            .padding(20)
        }
        .frame(width: Layout.detailPanelWidth)
        .background(BackgroundColors.secondary)
        .overlay(
            Rectangle()
                .fill(BorderColors.subtle)
                .frame(width: 1),
            alignment: .leading
        )
    }
}
```

#### Detail Row Component
```swift
struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.secondary)
            
            Spacer()
            
            Text(value)
                .font(Typography.bodySmall)
                .foregroundColor(TextColors.primary)
        }
    }
}
```

---

### 4. Buttons

#### Primary Button
```swift
struct PrimaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                
                Text(title)
                    .font(Typography.button)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(AccentColors.primary)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
```

#### Secondary Button
```swift
struct SecondaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                
                Text(title)
                    .font(Typography.button)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(BackgroundColors.elevated)
            .foregroundColor(TextColors.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(BorderColors.regular, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
```

#### Danger Button
```swift
struct DangerButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                
                Text(title)
                    .font(Typography.button)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(AccentColors.error)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
```

---

### 5. Publisher Badge

```swift
struct PublisherBadge: View {
    let publisher: String
    
    var publisherColor: Color {
        switch publisher.lowercased() {
        case let p where p.contains("dc"):
            return SemanticColors.dcComics
        case let p where p.contains("marvel"):
            return SemanticColors.marvel
        case let p where p.contains("image"):
            return SemanticColors.imageComics
        case let p where p.contains("dark horse"):
            return SemanticColors.darkHorse
        case let p where p.contains("vertigo"):
            return SemanticColors.vertigo
        default:
            return TextColors.tertiary
        }
    }
    
    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 24))
            .foregroundColor(publisherColor)
            .background(
                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
            )
            .shadow(color: .black.opacity(0.3), radius: 2)
    }
}
```

---

### 6. Top Toolbar

#### Visual Specs
- **Height:** 56px
- **Background:** `BackgroundColors.secondary`
- **Bottom Border:** `BorderColors.subtle`
- **Content Padding:** 16px horizontal

#### Structure
```swift
struct TopToolbar: View {
    @Binding var searchText: String
    let onAddFiles: () -> Void
    let onScanFolder: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Add Files Button
            Button(action: onAddFiles) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                    Text("Add Files...")
                        .font(Typography.button)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(BackgroundColors.elevated)
                .foregroundColor(TextColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            // Scan Folder Button
            Button(action: onScanFolder) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.ellipsis")
                        .font(.system(size: 14, weight: .medium))
                    Text("Scan Folder...")
                        .font(Typography.button)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(BackgroundColors.elevated)
                .foregroundColor(TextColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Export & Trash Icons
            Button(action: {}) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18))
                    .foregroundColor(TextColors.secondary)
            }
            .buttonStyle(.plain)
            
            Button(action: {}) {
                Image(systemName: "trash")
                    .font(.system(size: 18))
                    .foregroundColor(TextColors.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(BackgroundColors.secondary)
        .overlay(
            Rectangle()
                .fill(BorderColors.subtle)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
```

---

### 7. Content Header

#### Visual Specs
- **Height:** ~100px (flexible)
- **Title Font:** `Typography.h1`
- **Subtitle Font:** `Typography.bodySmall`

#### Structure
```swift
struct ContentHeader: View {
    let title: String
    let subtitle: String?
    @Binding var searchText: String
    @Binding var viewMode: ViewMode
    
    enum ViewMode {
        case grid, list, compact
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Title & Subtitle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Typography.h1)
                        .foregroundColor(TextColors.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Typography.bodySmall)
                            .foregroundColor(TextColors.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Search & Controls
            HStack(spacing: 12) {
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(TextColors.tertiary)
                    
                    TextField("Search series, issue, publisher, creator...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Typography.body)
                        .foregroundColor(TextColors.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(BackgroundColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 400)
                
                // Dropdown Filters
                Menu {
                    Button("All Ratings") {}
                    Button("5 Stars") {}
                    Button("4+ Stars") {}
                } label: {
                    HStack(spacing: 6) {
                        Text("All Ratings")
                            .font(Typography.bodySmall)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(TextColors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(BackgroundColors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                
                Menu {
                    Button("Issue (A-Z)") {}
                    Button("Issue (Z-A)") {}
                    Button("Year") {}
                } label: {
                    HStack(spacing: 6) {
                        Text("Issue (A-Z)")
                            .font(Typography.bodySmall)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(TextColors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(BackgroundColors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
                
                // Zoom Slider
                HStack(spacing: 8) {
                    Image(systemName: "minus")
                        .font(.system(size: 12))
                        .foregroundColor(TextColors.tertiary)
                    
                    Slider(value: .constant(0.5), in: 0...1)
                        .frame(width: 80)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundColor(TextColors.tertiary)
                }
                
                // View Mode Toggle
                HStack(spacing: 0) {
                    Button(action: { viewMode = .grid }) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14))
                            .foregroundColor(viewMode == .grid ? TextColors.primary : TextColors.tertiary)
                            .frame(width: 32, height: 32)
                            .background(viewMode == .grid ? BackgroundColors.elevated : Color.clear)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { viewMode = .list }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14))
                            .foregroundColor(viewMode == .list ? TextColors.primary : TextColors.tertiary)
                            .frame(width: 32, height: 32)
                            .background(viewMode == .list ? BackgroundColors.elevated : Color.clear)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { viewMode = .compact }) {
                        Image(systemName: "rectangle.grid.1x2")
                            .font(.system(size: 14))
                            .foregroundColor(viewMode == .compact ? TextColors.primary : TextColors.tertiary)
                            .frame(width: 32, height: 32)
                            .background(viewMode == .compact ? BackgroundColors.elevated : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
                .background(BackgroundColors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(20)
    }
}
```

---

## Reader View

### Visual Specs
- **Background:** Pure black `Color.black`
- **Control Overlay:** Semi-transparent with blur
- **Page Counter:** Top center
- **Navigation:** Bottom toolbar with emoji reactions

#### Structure
```swift
struct ReaderView: View {
    let comic: Comic
    @State private var currentPage = 0
    @State private var showControls = true
    
    var body: some View {
        ZStack {
            // Pure black background
            Color.black.ignoresSafeArea()
            
            // Comic pages (double-page view shown)
            HStack(spacing: 8) {
                // Left page
                if currentPage > 0 {
                    ComicPageView(pageNumber: currentPage - 1)
                }
                
                // Right page
                ComicPageView(pageNumber: currentPage)
            }
            .padding()
            
            // Top Controls (when visible)
            if showControls {
                VStack {
                    HStack {
                        Button(action: { /* close */ }) {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14))
                                Text("Back")
                                    .font(Typography.button)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        // Page counter
                        Text("Page 2 / 29")
                            .font(Typography.bodySmall)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        
                        Spacer()
                        
                        Button(action: { /* close */ }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    
                    Spacer()
                }
            }
            
            // Bottom Controls (when visible)
            if showControls {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 16) {
                        // Navigation buttons
                        Button(action: { currentPage -= 1 }) {
                            Image(systemName: "chevron.left.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        .disabled(currentPage == 0)
                        
                        Button(action: { currentPage += 1 }) {
                            Image(systemName: "chevron.right.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        // Emoji Reactions
                        HStack(spacing: 12) {
                            ForEach(["😡", "😠", "😐", "😊", "😃", "🤩", "💀"], id: \.self) { emoji in
                                Button(action: {}) {
                                    Text(emoji)
                                        .font(.system(size: 24))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Spacer()
                        
                        // Utility buttons
                        Button(action: {}) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "pause.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "arrow.clockwise.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 32)
                }
            }
        }
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }
        }
    }
}
```

---

## Spacing & Grid

### Spacing Scale
```swift
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}
```

### Grid Spacing
- **Comic Grid:** 20px horizontal, 24px vertical
- **Sidebar Items:** 8px horizontal padding, 4px between items
- **Content Padding:** 20px all around main content area

---

## Cursor Prompts

### For TASK-003: Design System

```
Create DesignSystem.swift in Utilities folder with the following structure:

1. Copy ALL color definitions from DESIGN_REFERENCE.md including:
   - BackgroundColors enum with primary, secondary, elevated, sidebar
   - TextColors enum with primary, secondary, tertiary, disabled
   - AccentColors enum with primary, success, warning, error
   - SemanticColors enum for publisher badges and status
   - BorderColors enum for dividers and borders

2. Copy ALL typography definitions from DESIGN_REFERENCE.md including:
   - Typography enum with h1, h2, h3
   - Body text styles (body, bodySmall)
   - UI text styles (button, navigation)
   - Label styles (caption, label, tiny)

3. Copy ALL layout constants from DESIGN_REFERENCE.md including:
   - Layout enum with window sizes
   - Sidebar width constants
   - Detail panel width constants

4. Add Color hex initializer:
   extension Color {
       init(hex: String) {
           // Parse hex color
       }
   }

Reference: @DESIGN_REFERENCE.md sections: Color Palette, Typography, Layout System
Use native SwiftUI Color and Font types.
Test with preview showing each color and font style.
```

### For TASK-004: Navigation Structure

```
Create ContentView.swift with three-column layout matching DESIGN_REFERENCE.md.

Structure:
1. NavigationSplitView with:
   - Sidebar (240px width, BackgroundColors.sidebar)
   - Main content area (flexible)
   - Detail panel (360px width, optional)

2. Sidebar should include:
   - App logo/title at top
   - Navigation items with SF Symbol icons:
     * Dashboard (chart.bar)
     * Library (books.vertical)
     * Organize (folder.badge.gearshape)
     * Learning (brain.head.profile)
     * Knowledge (book.closed)
     * Maintenance (wrench.and.screwdriver)
     * Settings (gear)
   - Light mode toggle at bottom

3. Apply design system:
   - Use BackgroundColors.sidebar for sidebar
   - Use BackgroundColors.primary for main content
   - Use Typography.navigation for nav items
   - Selected state: AccentColors.primary with 12% opacity background
   - Hover state: BackgroundColors.elevated

4. Create SidebarItem component (refer to DESIGN_REFERENCE.md)
5. Create placeholder views: LibraryView, OrganizeView, SettingsView

Reference: @DESIGN_REFERENCE.md sections: Navigation & Sidebar, Three-Column Layout
Test: Can navigate between sections, selection highlights correctly
```

---

## Implementation Notes

### Color Extension
You'll need this helper for hex colors:

```swift
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
```

### Dark Mode Only (Initially)
The app is designed for dark mode first. Light mode can be added later if desired.

```swift
// In App file
@main
struct SuperComicOrganizerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark) // Force dark mode
        }
    }
}
```

---

## Quick Reference Card

### Most Common Colors
```swift
// Backgrounds
BackgroundColors.primary      // Main app background
BackgroundColors.elevated     // Cards, buttons

// Text
TextColors.primary            // Main text
TextColors.secondary          // Metadata

// Accent
AccentColors.primary          // Blue for actions
AccentColors.error            // Red for delete
```

### Most Common Fonts
```swift
Typography.h1                 // Page titles
Typography.h3                 // Card titles
Typography.body               // Regular text
Typography.caption            // Small labels
```

### Most Common Spacing
```swift
.padding(20)                  // Main content padding
.spacing(20)                  // Grid horizontal spacing
.spacing(24)                  // Grid vertical spacing
```

---

**End of Design Reference**

This document should provide Cursor with everything needed to recreate the exact visual style from your Electron prototype. All measurements, colors, and components are specified with production-ready code examples.
