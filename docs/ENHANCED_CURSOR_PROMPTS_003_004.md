# Enhanced Cursor Prompts for Tasks 003 & 004
## With Design Reference Guide

---

## TASK-003: Design System (Enhanced)

### Context
You have a complete design reference extracted from the Electron prototype screenshots. The design uses a dark theme with specific colors, typography, and layout specifications.

### Cursor Prompt

```
Create Utilities/DesignSystem.swift implementing the complete design system from DESIGN_REFERENCE.md.

REQUIREMENTS:

1. COLOR SYSTEM
   Copy exactly from @DESIGN_REFERENCE.md - Color Palette section:
   
   enum BackgroundColors {
       static let primary = Color(hex: "#0F1419")
       static let secondary = Color(hex: "#1A1F26")
       static let elevated = Color(hex: "#232931")
       static let sidebar = Color(hex: "#16191E")
   }
   
   enum TextColors {
       static let primary = Color.white.opacity(0.95)
       static let secondary = Color.white.opacity(0.60)
       static let tertiary = Color.white.opacity(0.40)
       static let disabled = Color.white.opacity(0.25)
   }
   
   enum AccentColors {
       static let primary = Color(hex: "#3B82F6")
       static let primaryHover = Color(hex: "#2563EB")
       static let primaryActive = Color(hex: "#1D4ED8")
       static let success = Color(hex: "#10B981")
       static let warning = Color(hex: "#F59E0B")
       static let error = Color(hex: "#EF4444")
   }
   
   enum SemanticColors {
       // Publisher badges
       static let dcComics = Color(hex: "#3B82F6")
       static let marvel = Color(hex: "#EF4444")
       static let imageComics = Color(hex: "#F59E0B")
       static let darkHorse = Color(hex: "#EAB308")
       static let vertigo = Color(hex: "#8B5CF6")
       
       // Status indicators
       static let unread = Color(hex: "#3B82F6")
       static let reading = Color(hex: "#F59E0B")
       static let completed = Color(hex: "#10B981")
       
       // Selection
       static let selectionOverlay = Color(hex: "#3B82F6").opacity(0.15)
   }
   
   enum BorderColors {
       static let subtle = Color.white.opacity(0.08)
       static let regular = Color.white.opacity(0.12)
       static let emphasized = Color.white.opacity(0.20)
       static let focus = AccentColors.primary
   }

2. TYPOGRAPHY SYSTEM
   Copy exactly from @DESIGN_REFERENCE.md - Typography section:
   
   enum Typography {
       // Headings
       static let h1 = Font.system(size: 32, weight: .bold, design: .default)
       static let h2 = Font.system(size: 24, weight: .semibold, design: .default)
       static let h3 = Font.system(size: 18, weight: .semibold, design: .default)
       
       // Body
       static let body = Font.system(size: 15, weight: .regular, design: .default)
       static let bodySmall = Font.system(size: 13, weight: .regular, design: .default)
       
       // UI
       static let button = Font.system(size: 14, weight: .medium, design: .default)
       static let navigation = Font.system(size: 15, weight: .medium, design: .default)
       
       // Labels
       static let caption = Font.system(size: 12, weight: .regular, design: .default)
       static let label = Font.system(size: 11, weight: .medium, design: .default)
       static let tiny = Font.system(size: 10, weight: .medium, design: .default)
   }

3. LAYOUT SYSTEM
   Copy exactly from @DESIGN_REFERENCE.md - Layout System section:
   
   enum Layout {
       // Window
       static let minWindowWidth: CGFloat = 1200
       static let minWindowHeight: CGFloat = 700
       static let defaultWindowWidth: CGFloat = 1440
       static let defaultWindowHeight: CGFloat = 900
       
       // Sidebar
       static let sidebarWidth: CGFloat = 240
       static let sidebarCollapsedWidth: CGFloat = 72
       
       // Detail Panel
       static let detailPanelWidth: CGFloat = 360
       static let detailPanelMinWidth: CGFloat = 300
       static let detailPanelMaxWidth: CGFloat = 480
   }
   
   enum Spacing {
       static let xs: CGFloat = 4
       static let sm: CGFloat = 8
       static let md: CGFloat = 12
       static let lg: CGFloat = 16
       static let xl: CGFloat = 20
       static let xxl: CGFloat = 24
       static let xxxl: CGFloat = 32
   }

4. COLOR HEX INITIALIZER
   Add this extension for hex color support:
   
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

5. PREVIEW
   Add SwiftUI preview showing:
   - Color swatches with labels
   - Typography examples
   - Layout measurements

CRITICAL:
- Copy hex values EXACTLY as specified
- Use San Francisco (system) font throughout
- All opacity values must match exactly
- No modifications to the design system

SUCCESS CRITERIA:
✅ All colors defined with correct hex values
✅ All typography styles defined
✅ All layout constants defined
✅ Hex color initializer works
✅ Preview compiles and displays correctly
✅ Can import and use in other views

REFERENCE: @DESIGN_REFERENCE.md sections: Color Palette, Typography, Layout System
```

---

## TASK-004: Navigation Structure (Enhanced)

### Context
You need to create the three-column layout matching the Electron prototype exactly. The design has a sidebar, main content area, and optional detail panel.

### Cursor Prompt

```
Create ContentView.swift implementing the three-column navigation structure from DESIGN_REFERENCE.md.

REQUIREMENTS:

1. THREE-COLUMN LAYOUT
   Implement NavigationSplitView with:
   
   ┌────────────┬──────────────────────────────────┬────────────┐
   │  Sidebar   │     Main Content Area            │   Detail   │
   │  (240px)   │     (Flexible)                   │   (360px)  │
   │            │                                  │            │
   │ [Nav Items]│  [Selected View Content]         │  [Optional]│
   └────────────┴──────────────────────────────────┴────────────┘

2. SIDEBAR IMPLEMENTATION
   Create SidebarView with:
   
   - Width: Layout.sidebarWidth (240px)
   - Background: BackgroundColors.sidebar
   - Top section: App logo/title
   - Navigation items (7 total):
     * Dashboard (chart.bar)
     * Library (books.vertical) 
     * Organize (folder.badge.gearshape)
     * Learning (brain.head.profile)
     * Knowledge (book.closed)
     * Maintenance (wrench.and.screwdriver)
     * Settings (gear)
   - Bottom section: "Switch to Light Mode" toggle
   
   Each nav item should use SidebarItem component:
   
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

3. PLACEHOLDER VIEWS
   Create three empty placeholder views:
   
   struct LibraryView: View {
       var body: some View {
           VStack {
               Text("Library View")
                   .font(Typography.h1)
                   .foregroundColor(TextColors.primary)
               Text("Comic collection will appear here")
                   .font(Typography.body)
                   .foregroundColor(TextColors.secondary)
           }
           .frame(maxWidth: .infinity, maxHeight: .infinity)
           .background(BackgroundColors.primary)
       }
   }
   
   struct OrganizeView: View {
       var body: some View {
           VStack {
               Text("Organize View")
                   .font(Typography.h1)
                   .foregroundColor(TextColors.primary)
               Text("Drag and drop comics to organize")
                   .font(Typography.body)
                   .foregroundColor(TextColors.secondary)
           }
           .frame(maxWidth: .infinity, maxHeight: .infinity)
           .background(BackgroundColors.primary)
       }
   }
   
   struct SettingsView: View {
       var body: some View {
           VStack {
               Text("Settings View")
                   .font(Typography.h1)
                   .foregroundColor(TextColors.primary)
               Text("Configure your preferences")
                   .font(Typography.body)
                   .foregroundColor(TextColors.secondary)
           }
           .frame(maxWidth: .infinity, maxHeight: .infinity)
           .background(BackgroundColors.primary)
       }
   }

4. MAIN CONTENTVIEW STRUCTURE
   
   struct ContentView: View {
       @State private var selectedTab: Tab = .library
       
       enum Tab: String, CaseIterable {
           case dashboard = "Dashboard"
           case library = "Library"
           case organize = "Organize"
           case learning = "Learning"
           case knowledge = "Knowledge"
           case maintenance = "Maintenance"
           case settings = "Settings"
           
           var icon: String {
               switch self {
               case .dashboard: return "chart.bar"
               case .library: return "books.vertical"
               case .organize: return "folder.badge.gearshape"
               case .learning: return "brain.head.profile"
               case .knowledge: return "book.closed"
               case .maintenance: return "wrench.and.screwdriver"
               case .settings: return "gear"
               }
           }
       }
       
       var body: some View {
           NavigationSplitView {
               // Sidebar
               SidebarView(selectedTab: $selectedTab)
                   .frame(width: Layout.sidebarWidth)
           } detail: {
               // Main content
               selectedView()
                   .frame(maxWidth: .infinity, maxHeight: .infinity)
           }
       }
       
       @ViewBuilder
       private func selectedView() -> some View {
           switch selectedTab {
           case .dashboard:
               Text("Dashboard").foregroundColor(.white)
           case .library:
               LibraryView()
           case .organize:
               OrganizeView()
           case .learning:
               Text("Learning").foregroundColor(.white)
           case .knowledge:
               Text("Knowledge").foregroundColor(.white)
           case .maintenance:
               Text("Maintenance").foregroundColor(.white)
           case .settings:
               SettingsView()
           }
       }
   }

5. STYLING
   Apply design system consistently:
   - Import: import SwiftUI
   - Use: DesignSystem colors and fonts throughout
   - Sidebar hover: BackgroundColors.elevated
   - Selected state: AccentColors.primary with 12% opacity
   - Default text: TextColors.secondary
   - Selected text: AccentColors.primary

CRITICAL:
- Must import DesignSystem: "import SwiftUI" at top
- Use ONLY colors/fonts from DesignSystem
- Sidebar must be exactly 240px wide
- Navigation items must highlight on selection
- Hover states should work on macOS

SUCCESS CRITERIA:
✅ Three-column layout displays correctly
✅ Can navigate between all sections
✅ Sidebar selection highlights with blue accent
✅ Hover states work (macOS)
✅ Placeholder views show content
✅ Dark theme applied throughout
✅ Works on both macOS and iPad

TESTING:
1. Build and run (⌘R)
2. Click each navigation item
3. Verify selection highlight appears
4. Verify colors match screenshots
5. Test on iPad simulator

REFERENCE: 
- @DESIGN_REFERENCE.md sections: Navigation & Sidebar, Three-Column Layout
- @Panels_Clone_Plus_SuperComicOrganizer_Plan.md for structure examples
```

---

## Additional Notes

### For Cursor Agent
When implementing these tasks:

1. **Read the design reference first**: `@DESIGN_REFERENCE.md` contains exact specifications
2. **Copy, don't interpret**: The hex values and measurements are exact
3. **Test as you build**: Run preview or build after each section
4. **Follow the structure**: The component structures are production-ready

### Design Validation
After implementation, compare against the screenshots:
- Sidebar should be very dark (#16191E)
- Main content should be slightly lighter (#0F1419)
- Blue accent should be #3B82F6
- Text hierarchy should be obvious (32pt → 18pt → 15pt)

### Common Issues
1. **Colors look wrong**: Check hex values match exactly
2. **Layout breaks on iPad**: Ensure NavigationSplitView is used
3. **Fonts look off**: Verify using system font, not custom
4. **Sidebar too wide/narrow**: Must be exactly 240px

---

## Quick Verification Checklist

### After TASK-003:
- [ ] DesignSystem.swift file exists in Utilities/
- [ ] All color enums compile without errors
- [ ] Hex color extension works
- [ ] Can use `BackgroundColors.primary` in any view
- [ ] Preview shows color swatches

### After TASK-004:
- [ ] ContentView.swift exists
- [ ] Sidebar displays all 7 navigation items
- [ ] Can click each item and see selection
- [ ] Selection turns blue (#3B82F6)
- [ ] Placeholder views display
- [ ] Dark theme is applied
- [ ] Build succeeds on macOS target

---

## Example Test Commands for Cursor

After TASK-003:
```swift
// In any view, test the design system:
VStack {
    Rectangle().fill(BackgroundColors.primary).frame(height: 50)
    Text("Hello").font(Typography.h1).foregroundColor(TextColors.primary)
}
```

After TASK-004:
```swift
// Run and test navigation:
1. Build (⌘R)
2. Click "Library" - should highlight in blue
3. Click "Settings" - should switch views
4. Verify dark theme throughout
```

---

**These prompts provide exact specifications for Cursor to recreate your Electron app's design in native Swift/SwiftUI.**
