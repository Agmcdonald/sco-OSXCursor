# How to Use Design Reference with Cursor
## Quick Start Guide

---

## What You Have

You now have **two new documents** that work together:

1. **DESIGN_REFERENCE.md** - Complete visual design specifications
   - Extracted from your Electron app screenshots
   - Exact colors (hex values)
   - Exact fonts and sizes
   - Exact layout measurements
   - Component structures with code

2. **ENHANCED_CURSOR_PROMPTS_003_004.md** - Ready-to-use Cursor prompts
   - Enhanced versions of TASK-003 and TASK-004
   - Reference the design document
   - Include all specifications inline
   - Step-by-step instructions

---

## How to Use with Cursor

### Method 1: Copy/Paste Prompts (Recommended)

#### For TASK-003 (Design System):

1. **Open Cursor** in your Xcode project
2. **Open Chat** (Cmd+L or click chat icon)
3. **Copy the entire TASK-003 prompt** from `ENHANCED_CURSOR_PROMPTS_003_004.md`
4. **Paste into Cursor chat**
5. **Press Enter**

Cursor will:
- Create `Utilities/DesignSystem.swift`
- Add all color definitions
- Add all typography definitions
- Add layout constants
- Add the hex color extension
- Create a preview

#### For TASK-004 (Navigation):

1. **After TASK-003 succeeds**
2. **Copy the entire TASK-004 prompt** from `ENHANCED_CURSOR_PROMPTS_003_004.md`
3. **Paste into Cursor chat**
4. **Press Enter**

Cursor will:
- Create `ContentView.swift`
- Create `SidebarView` with all nav items
- Create placeholder views (Library, Organize, Settings)
- Apply the design system
- Set up three-column layout

---

### Method 2: Reference Design Document

If you prefer to guide Cursor more interactively:

1. **Open Cursor chat**
2. **Type:** 
   ```
   Create DesignSystem.swift based on @DESIGN_REFERENCE.md
   
   Include all sections:
   - Color Palette
   - Typography
   - Layout System
   ```

3. **Cursor will read** the design reference and implement it

**Advantage:** More flexible, can ask for specific sections
**Disadvantage:** May need more back-and-forth

---

## Understanding the Design Reference

### What's in DESIGN_REFERENCE.md?

The document has **10 main sections**:

1. **Design Overview** - Overall style and philosophy
2. **Color Palette** - All colors with hex values
3. **Typography** - All font styles and sizes
4. **Layout System** - Window and panel measurements
5. **Component Specifications** - 7 ready-to-use components
6. **Navigation & Sidebar** - Sidebar implementation
7. **Library View** - Comic grid specifications
8. **Detail Panel** - Right panel specifications
9. **Reader View** - Full-screen reading mode
10. **Spacing & Grid** - Spacing scale

### Most Important Sections for Initial Tasks

For **Tasks 003-004**, focus on:
- Section 2: Color Palette
- Section 3: Typography  
- Section 4: Layout System
- Section 6: Navigation & Sidebar

You can return to other sections as you build more features.

---

## What Makes This Different from Before?

### Previous Approach:
```
"Create a design system with colors and fonts"
```
*Problem:* Too vague, Cursor has to guess

### New Approach:
```
"Create DesignSystem.swift with these exact specifications:
- Background primary: #0F1419
- Text primary: white at 95% opacity
- H1 font: 32pt bold
..."
```
*Benefit:* Cursor knows exactly what to create

---

## Verification Steps

### After TASK-003 (Design System):

1. **File exists**: `Utilities/DesignSystem.swift`
2. **Colors compile**: Try this in any view:
   ```swift
   Text("Test")
       .foregroundColor(TextColors.primary)
       .background(BackgroundColors.primary)
   ```
3. **Fonts work**: Try this:
   ```swift
   Text("Title").font(Typography.h1)
   ```
4. **Build succeeds**: Press ⌘R

### After TASK-004 (Navigation):

1. **File exists**: `ContentView.swift`
2. **App launches**: Press ⌘R
3. **Sidebar shows**: 7 navigation items visible
4. **Selection works**: Click items, selection highlights
5. **Colors match**: Compare to screenshots
   - Sidebar: Very dark (#16191E)
   - Content: Slightly lighter (#0F1419)
   - Selected: Blue (#3B82F6)

---

## Common Questions

### Q: What if Cursor doesn't reference the design doc?

**A:** Add `@DESIGN_REFERENCE.md` explicitly in your prompt:
```
Create DesignSystem.swift based on specifications in @DESIGN_REFERENCE.md
Copy exact hex values from Color Palette section.
```

### Q: What if colors look wrong?

**A:** Check these:
1. Hex values match exactly
2. Color extension is implemented
3. Dark mode is forced in App file:
   ```swift
   .preferredColorScheme(.dark)
   ```

### Q: What if layout is off?

**A:** Verify:
1. Sidebar width is exactly 240px
2. NavigationSplitView is used (not NavigationStack)
3. Frame modifiers are applied correctly

### Q: Can I customize the design?

**A:** Yes! But do it AFTER tasks 003-004 work. This gives you:
1. A working foundation
2. Consistency across the app
3. Easy to modify centrally

---

## Next Steps After 003-004

Once you have the design system and navigation working:

### TASK-005: Library View
Use these sections from DESIGN_REFERENCE.md:
- Section 5.2: Comic Card (Grid View)
- Section 7: Library View
- Section 8: Content Header

Prompt example:
```
Create LibraryView.swift based on @DESIGN_REFERENCE.md Section 7.
Include:
- Content header with search
- Comic grid using LazyVGrid
- Comic cards from Section 5.2
```

### TASK-006: Detail Panel
Use these sections:
- Section 5.3: Detail Panel (Right Side)
- Section 5.4: Buttons

### Beyond
Continue referencing relevant sections as you build each feature.

---

## Tips for Working with Cursor

### 1. Be Specific About References
❌ Bad: "Create a design system"
✅ Good: "Create DesignSystem.swift from @DESIGN_REFERENCE.md Section 2"

### 2. Include Success Criteria
Always add to your prompts:
```
SUCCESS CRITERIA:
✅ File compiles without errors
✅ Can import in other views
✅ Preview shows all colors
```

### 3. Build Incrementally
Don't try to build everything at once:
1. Design system
2. Navigation
3. One view at a time

### 4. Test After Each Step
Build and run (⌘R) after every task to catch issues early.

### 5. Compare to Screenshots
Keep the screenshot folder open to verify colors and layout match.

---

## Troubleshooting

### Issue: "Cannot find type 'BackgroundColors'"

**Solution:** Make sure DesignSystem.swift:
1. Is in the correct target
2. Has `import SwiftUI` at top
3. Is not inside another struct/class

### Issue: Colors don't match screenshots

**Solution:** 
1. Check hex values are exact
2. Verify Color hex extension works
3. Check alpha/opacity values

### Issue: Sidebar too narrow/wide

**Solution:**
```swift
.frame(width: Layout.sidebarWidth)  // Should be 240
```

### Issue: Navigation doesn't work

**Solution:**
1. Verify using `@State private var selectedTab`
2. Check `NavigationSplitView` is used
3. Ensure binding is passed correctly

---

## Quick Reference

### File Locations
```
YourProject/
├── Utilities/
│   └── DesignSystem.swift      (TASK-003)
├── ContentView.swift            (TASK-004)
└── Views/
    ├── LibraryView.swift        (Placeholder from 004)
    ├── OrganizeView.swift       (Placeholder from 004)
    └── SettingsView.swift       (Placeholder from 004)
```

### Import Pattern
In every view file:
```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        Text("Hello")
            .foregroundColor(TextColors.primary)  // From DesignSystem
            .font(Typography.body)                 // From DesignSystem
    }
}
```

### Force Dark Mode
In your App file:
```swift
@main
struct SuperComicOrganizerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
```

---

## You're Ready!

You now have:
✅ Complete design specifications
✅ Ready-to-use Cursor prompts
✅ Example code for every component
✅ Verification steps
✅ Troubleshooting guide

**Next action:** Open Cursor and start with the TASK-003 prompt!

---

## Support Documents Summary

| Document | Purpose | When to Use |
|----------|---------|-------------|
| **DESIGN_REFERENCE.md** | Complete design specs | Reference throughout development |
| **ENHANCED_CURSOR_PROMPTS_003_004.md** | Ready prompts for tasks 3-4 | Copy/paste into Cursor now |
| **This guide** | How to use the above | Read once, keep handy |
| **Original project docs** | Overall architecture | Reference for later tasks |

---

**Good luck building! The design is now clearly defined, so Cursor should be able to recreate it faithfully.** 🚀
