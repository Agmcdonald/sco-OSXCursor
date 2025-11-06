# Screenshot Reference Guide
## Which Screenshot Shows What

This guide helps you find the right screenshot when comparing your implementation to the design.

---

## Main Library View

### Screenshot: `Screenshot 2025-10-23 015144.png`
**Shows:**
- Three-column layout (sidebar, grid, detail panel)
- Sidebar navigation (all 7 items)
- Comic grid with covers
- Detail panel with large cover preview
- Publisher badges (DC logo visible)
- Dark theme colors
- Search bar and filters
- View mode toggles (grid/list/compact)

**Use for:**
- Overall layout verification
- Color checking (backgrounds, text)
- Grid spacing
- Sidebar width
- Detail panel content

---

## Library Grid (Zoomed Out)

### Screenshot: `Screenshot 2025-10-23 015445.png`
**Shows:**
- Full comic grid (many comics visible)
- Grid spacing and layout
- Comic card proportions
- Multiple publisher badges
- Consistent card styling
- Issue numbers and years

**Use for:**
- Grid spacing verification (20px horizontal, 24px vertical)
- Card aspect ratio (2:3)
- Badge placement
- Text hierarchy on cards

---

## Reader View (Double-Page)

### Screenshot: `Screenshot 2025-10-23 015558.png`
**Shows:**
- Full-screen reader with two pages side-by-side
- Pure black background
- Top controls bar (back button, page counter, close)
- Bottom toolbar with emoji reactions
- Navigation controls
- Page layout

**Use for:**
- Reader interface design
- Control placement
- Page layout
- Black background (#000000)
- Toolbar styling

---

## Detail Panel Focus

### Screenshot: `Screenshot 2025-10-23 015148.png`
**Shows:**
- Right panel with full comic details
- Large cover preview
- "Basic Information" section
- Publisher, Volume, Publication Date
- Summary section
- Rating emoji display
- Action buttons (Read Comic, Add to List, etc.)
- Button styling and spacing

**Use for:**
- Detail panel layout
- Button hierarchy (primary vs secondary)
- Information row spacing
- Rating display
- Cover preview size

---

## Sidebar Navigation

### Best shown in: `Screenshot 2025-10-23 015144.png`
**Shows:**
- App logo at top
- 7 navigation items with icons:
  1. Dashboard (chart.bar)
  2. Library (books.vertical) - SELECTED
  3. Organize (folder.badge.gearshape)
  4. Learning (brain.head.profile)
  5. Knowledge (book.closed)
  6. Maintenance (wrench.and.screwdriver)
  7. Settings (gear)
- "Switch to Light Mode" at bottom
- Selection highlight (blue background)
- Sidebar width (240px)

**Use for:**
- Sidebar layout
- Navigation item styling
- Selection state
- Icon placement
- Text alignment

---

## Top Toolbar

### Best shown in: `Screenshot 2025-10-23 015445.png`
**Shows:**
- "Add Files..." button
- "Scan Folder..." button
- Export and trash icons (right side)
- Button styling
- Toolbar height and padding

**Use for:**
- Toolbar layout
- Button styling
- Icon sizes
- Spacing

---

## Content Header

### Best shown in: `Screenshot 2025-10-23 015144.png` and `015445.png`
**Shows:**
- "Library" title (32pt bold)
- Subtitle: "Browse your collection of 190 comics"
- Search bar with placeholder text
- Dropdown filters ("All Ratings", "Issue (A-Z)")
- Zoom slider
- View mode toggle buttons
- Checkbox for "Selection Mode"

**Use for:**
- Header layout
- Search bar styling
- Filter dropdown design
- Toggle button group
- Title typography

---

## Comic Cards

### Best shown in: `Screenshot 2025-10-23 015445.png`
**Shows:**
- Card dimensions (160px wide × ~280px total)
- Cover image (160px × 240px)
- Publisher badge (top-right corner)
- Title below cover (2 lines max)
- Issue number and year
- Card shadow and corner radius

**Use for:**
- Card component structure
- Image aspect ratio
- Text truncation
- Badge placement
- Spacing within card

---

## Action Buttons

### Best shown in: `Screenshot 2025-10-23 015148.png`
**Shows:**
- Primary button: "Read Comic" (white text, blue background)
- Secondary buttons: "Add to List", "Mark Read" (outlined)
- Secondary buttons: "Fix Cover", "Set as Series Cover", "Edit"
- Danger button: "Delete" (white text, red background)
- Button heights, padding, spacing
- Icon + text layout

**Use for:**
- Button styling
- Color usage (primary blue, error red)
- Button hierarchy
- Icon placement
- Rounded corners

---

## Publisher Badges

### Visible in multiple screenshots
**Shows:**
- DC Comics: Blue circle badge
- Marvel: Visible on various covers
- Different publisher colors

**Use for:**
- Badge size (24-28px)
- Badge placement (top-right, 8px padding)
- Shadow effect
- Circle background

---

## Color Verification

Use these specific areas in screenshots to verify colors:

### Background Colors:
- **Main background** (`#0F1419`): 
  - Center area behind comic grid
  - Screenshot: `015144.png`, `015445.png`

- **Sidebar background** (`#16191E`):
  - Left sidebar area
  - Screenshot: Any with sidebar visible

- **Detail panel background** (`#1A1F26`):
  - Right panel area
  - Screenshot: `015144.png`, `015148.png`

- **Elevated surfaces** (`#232931`):
  - Comic cards background
  - Search bar background
  - Dropdown buttons
  - Screenshot: `015445.png` (card backgrounds)

### Text Colors:
- **Primary text** (white at 95%):
  - Comic titles
  - Navigation items (selected)
  - Page headers

- **Secondary text** (white at 60%):
  - Navigation items (unselected)
  - Comic metadata (issue, year)
  - Subtitles

- **Tertiary text** (white at 40%):
  - Placeholder text
  - Disabled items

### Accent Colors:
- **Primary blue** (`#3B82F6`):
  - Selected navigation item background
  - "Read Comic" button
  - DC Comics badge
  - Screenshot: `015144.png` (Library is selected)

- **Error red** (`#EF4444`):
  - "Delete" button
  - Screenshot: `015148.png` (bottom of detail panel)

---

## Typography Verification

Use these areas to verify font sizes:

### Heading 1 (32pt, bold):
- "Library" title
- Screenshot: `015144.png`, `015445.png`

### Heading 3 (18pt, semibold):
- Comic titles on cards
- "Basic Information" section header
- Screenshot: `015445.png` (card titles)

### Body (15pt, regular):
- Navigation items
- Search placeholder
- Screenshot: `015144.png` (sidebar items)

### Body Small (13pt, regular):
- Comic metadata
- Detail panel values
- Screenshot: `015148.png` (right panel)

### Caption (12pt, regular):
- Issue numbers and years on cards
- Screenshot: `015445.png` (under card titles)

### Button (14pt, medium):
- All button text
- Screenshot: `015148.png` (action buttons)

---

## Layout Measurements

Use these screenshots to verify measurements:

### Sidebar Width (240px):
- Screenshot: `015144.png`
- Measure: Left edge to content start

### Detail Panel Width (360px):
- Screenshot: `015144.png`, `015148.png`
- Measure: Right panel width

### Card Width (160px):
- Screenshot: `015445.png`
- Measure: Single comic card width

### Grid Spacing:
- **Horizontal:** 20px between cards
- **Vertical:** 24px between rows
- Screenshot: `015445.png`

### Padding:
- **Content padding:** 20px
- **Sidebar item padding:** 16px horizontal, 12px vertical
- Screenshot: `015144.png`

---

## Quick Reference Table

| Element | Best Screenshot | What to Check |
|---------|----------------|---------------|
| Overall Layout | `015144.png` | Three-column structure |
| Sidebar | `015144.png` | Navigation items, selection |
| Comic Grid | `015445.png` | Spacing, card layout |
| Comic Card | `015445.png` | Dimensions, styling |
| Detail Panel | `015148.png` | Layout, buttons |
| Reader | `015558.png` | Full-screen layout |
| Top Toolbar | `015445.png` | Buttons, icons |
| Content Header | `015144.png` | Search, filters, title |
| Colors | `015144.png` | All backgrounds visible |
| Typography | `015445.png` | Multiple text styles |

---

## Comparison Workflow

When implementing a feature:

1. **Find the relevant screenshot** using this guide
2. **Open the screenshot** on a second monitor or side-by-side
3. **Build your implementation** in Xcode
4. **Compare visually**:
   - Colors (use color picker if needed)
   - Spacing (measure with ruler tool)
   - Typography (size and weight)
   - Layout (proportions and alignment)
5. **Iterate** until it matches

---

## Color Picker Tips

If you want to verify colors exactly:

### macOS:
1. Open screenshot in Preview
2. Tools → Show Inspector (⌘I)
3. Click eyedropper tool
4. Click on color you want to check
5. Copy hex value

### Photoshop/Design Tools:
1. Import screenshot
2. Use eyedropper tool
3. Check hex value in color panel

### Xcode:
1. Right-click on color asset
2. Show in Finder
3. Compare with screenshot

---

## Not in Screenshots

These features are **NOT** shown in the screenshots but are in the design plan:

- Organize view with drag-and-drop zone
- Learning view with corrections interface
- Settings view with preferences
- Knowledge database view
- Maintenance view
- Reading mode (single page)
- Reading mode (continuous scroll)

For these, refer to:
- `Panels_Clone_Plus_SuperComicOrganizer_Plan.md`
- `SuperComicOrganizer_Development_Blueprint.md`

---

## Screenshot File Names

For easy reference:

```
Library Main View:        Screenshot 2025-10-23 015144.png
Library Detail Panel:     Screenshot 2025-10-23 015148.png
Library Grid (Zoomed):    Screenshot 2025-10-23 015445.png
Reader View:              Screenshot 2025-10-23 015558.png
```

All other screenshots show various states of these views (different selections, hover states, etc.).

---

**Use this guide as your visual reference during development!**
