# Super Comic Organizer - Task-Based Implementation Plan
## Move at Your Own Pace

**Version:** 3.0 - Task-Based  
**Last Updated:** November 5, 2025  
**Approach:** Complete tasks in order, track by checkboxes

---

## How This Works

### Task Organization
- **Grouped by feature area** (not by days/weeks)
- **Clear dependencies** (what must be done first)
- **Move as fast as you want** - no artificial time limits
- **Track by completion** - check off as you go

### Task Format
```
□ TASK-ID: Task Name
  Dependencies: [Other tasks that must be done first]
  Estimated: [Rough time if working focused]
  Files: [What you'll create/modify]
  Success: [How you know it's done]
```

---

## 🎯 MILESTONE 1: Project Foundation
**Goal:** Running app with basic structure

### □ TASK-001: Initial Project Setup
**Dependencies:** None  
**Estimated:** 30 minutes  
**Files:** Xcode project, Package.swift

**Steps:**
1. Create multiplatform Xcode project named "SuperComicOrganizer"
2. Add ZIPFoundation package: `https://github.com/weichsel/ZIPFoundation.git`
3. Add GRDB package: `https://github.com/groue/GRDB.swift.git`
4. Configure app capabilities (File Access, Network)
5. First successful build (⌘R)

**Success Criteria:**
- [ ] Project builds without errors
- [ ] Runs on macOS
- [ ] Runs on iPad simulator
- [ ] Package dependencies imported successfully

**Cursor Prompt:**
```
Create new Xcode multiplatform project for Super Comic Organizer.
Add package dependencies:
- ZIPFoundation (0.9.0+)
- GRDB (6.0.0+)
Configure capabilities for file access.
Guide me step by step.
```

---

### □ TASK-002: Folder Structure
**Dependencies:** TASK-001  
**Estimated:** 15 minutes  
**Files:** Folder organization

**Create these groups:**
```
SuperComicOrganizer/
├── Models/
├── Views/
│   ├── Library/
│   ├── Reader/
│   ├── Organize/
│   └── Settings/
├── ViewModels/
├── Services/
│   ├── ComicReader/
│   ├── Organization/
│   ├── Learning/
│   ├── Progress/
│   └── Database/
└── Utilities/
```

**Success Criteria:**
- [ ] All folders exist in Xcode navigator
- [ ] Project still builds

---

### □ TASK-003: Design System
**Dependencies:** TASK-002  
**Estimated:** 1 hour  
**Files:** `Utilities/DesignSystem.swift`

**Implementation:**
```swift
// Copy from Code_Examples_Part1.md or create:
enum AppColors { }
enum AppFonts { }
enum AppLayout { }
```

**Success Criteria:**
- [ ] DesignSystem.swift created
- [ ] Can reference AppColors.accent in any view
- [ ] Preview shows design tokens work

**Cursor Prompt:**
```
Create DesignSystem.swift in Utilities folder.
Reference: @docs/Panels_Clone_Plus_SuperComicOrganizer_Plan.md - Design System
Include AppColors, AppFonts, AppLayout enums.
Use native colors and fonts only.
```

---

### □ TASK-004: Navigation Structure
**Dependencies:** TASK-003  
**Estimated:** 1.5 hours  
**Files:** `ContentView.swift`, placeholder views

**Implementation:**
- NavigationSplitView with sidebar
- Tabs: Library, Organize, Settings
- Placeholder detail views for each

**Success Criteria:**
- [ ] Can navigate between all sections
- [ ] Sidebar selection highlights correctly
- [ ] Each section shows placeholder content
- [ ] Works on both macOS and iPad

**Cursor Prompt:**
```
Implement ContentView with NavigationSplitView.
Reference: @docs/Code_Examples_Part1.md - ContentView
Sidebar with: Library, Organize, Settings
Create empty placeholder views for each.
```

---

## 🎯 MILESTONE 2: Data Foundation
**Goal:** Core data models and structures

### □ TASK-005: Comic Model
**Dependencies:** TASK-002  
**Estimated:** 1 hour  
**Files:** `Models/Comic.swift`

**Implementation:**
```swift
struct Comic: Identifiable, Codable {
    let id: UUID
    var filePath: URL
    var fileName: String
    var title: String?
    var publisher: String?
    var series: String?
    var issueNumber: String?
    var year: Int?
    var coverImageData: Data?
    var status: Status
    // ... rest from blueprint
}
```

**Success Criteria:**
- [ ] Comic.swift compiles
- [ ] Can create test Comic instances
- [ ] Has all required properties
- [ ] Status enum included
- [ ] Has computed properties (displayName, etc.)

**Cursor Prompt:**
```
Create Comic.swift model in Models folder.
Reference: @docs/SuperComicOrganizer_Development_Blueprint.md - Comic Model
Include all properties, Status enum, and computed properties.
Add sample() static method for testing.
```

---

### □ TASK-006: Settings Model
**Dependencies:** TASK-002  
**Estimated:** 30 minutes  
**Files:** `Models/AppSettings.swift`

**Implementation:**
- FolderStructure enum
- NamingPattern options
- All configuration properties

**Success Criteria:**
- [ ] AppSettings.swift compiles
- [ ] FolderStructure enum has all cases
- [ ] Codable conformance works
- [ ] Can save/load with UserDefaults

---

## 🎯 MILESTONE 3: Library UI (Reader-Ready)
**Goal:** Beautiful library that's ready to show real comics

### □ TASK-007: Library Grid Layout
**Dependencies:** TASK-004, TASK-005  
**Estimated:** 2 hours  
**Files:** `Views/Library/LibraryView.swift`, `Views/Library/LibraryGridView.swift`

**Implementation:**
- LazyVGrid with adaptive columns
- Mock comic data (10 comics)
- Smooth scrolling

**Success Criteria:**
- [ ] Grid displays 10 mock comics
- [ ] Scrolling is smooth (60 FPS)
- [ ] Columns adapt to screen size
- [ ] Works on macOS and iPad

**Cursor Prompt:**
```
Implement LibraryGridView with LazyVGrid.
Reference: @docs/Code_Examples_Part1.md - Library View section
Use mock Comic data (create 10 samples).
Adaptive columns, smooth scrolling.
```

---

### □ TASK-008: Comic Card Component
**Dependencies:** TASK-007  
**Estimated:** 1.5 hours  
**Files:** `Views/Library/ComicCardView.swift`

**Implementation:**
- Cover image (placeholder for now)
- Title, publisher, issue number
- Status indicator
- Tap gesture (no action yet)

**Success Criteria:**
- [ ] Card looks professional
- [ ] All info displays correctly
- [ ] Placeholder cover shows
- [ ] Tap is detected (print statement OK)

**Cursor Prompt:**
```
Create ComicCardView component.
Reference: @docs/Code_Examples_Part1.md - Comic Card section
Show cover (placeholder), title, publisher badge, issue number.
Add tap gesture recognition.
Use DesignSystem styles.
```

---

### □ TASK-009: Library Toolbar
**Dependencies:** TASK-007  
**Estimated:** 1 hour  
**Files:** Update `Views/Library/LibraryView.swift`

**Implementation:**
- Search bar (UI only, no function yet)
- Grid/List toggle (UI only)
- "Add Comics" button (no action yet)

**Success Criteria:**
- [ ] Toolbar looks good
- [ ] All controls present
- [ ] Buttons are tappable
- [ ] Layout adapts to screen size

---

## 🎯 MILESTONE 4: Comic Reading Engine ⭐
**Goal:** Can actually read comic files

### □ TASK-010: CBZ Reader Service
**Dependencies:** TASK-005  
**Estimated:** 3 hours  
**Files:** `Services/ComicReader/ComicReaderService.swift`, `Services/ComicReader/CBZReader.swift`

**Implementation:**
- ComicReaderProtocol definition
- CBZReader class
- Extract images from ZIP
- Natural sorting
- Security-scoped resources
- ComicInfo.xml parsing

**Success Criteria:**
- [ ] Can open a CBZ file
- [ ] Extracts all images
- [ ] Images in correct order (1, 2, 3... not 1, 10, 11, 2)
- [ ] Cover extraction works
- [ ] ComicInfo.xml parsed if present
- [ ] No security errors

**Cursor Prompt:**
```
Implement CBZReader exactly from:
@docs/Code_Examples_Part1.md - Complete CBZ Reader Implementation

Must include:
- Security-scoped resource access
- Natural sorting (localizedStandardCompare)
- Image extraction
- ComicInfo.xml parsing
- Error handling

Test with real CBZ file.
```

**Test Before Moving On:**
- Create test CBZ (ZIP with 3-4 images)
- Verify images extract in order
- Verify cover displays

---

### □ TASK-011: PDF Reader Service
**Dependencies:** TASK-005  
**Estimated:** 2 hours  
**Files:** `Services/ComicReader/PDFReader.swift`

**Implementation:**
- PDFReader class using PDFKit
- First page as cover
- Page count
- PDF metadata extraction

**Success Criteria:**
- [ ] Can open PDF files
- [ ] Cover extracted from first page
- [ ] Page count correct
- [ ] PDF metadata parsed
- [ ] No PDFKit errors

**Cursor Prompt:**
```
Implement PDFReader using Apple's PDFKit.
Reference: @docs/Code_Examples_Part1.md - PDF Reader section
Extract cover from first page.
Parse PDF metadata (title, author).
Handle errors gracefully.
```

---

### □ TASK-012: Comic Page View
**Dependencies:** TASK-010  
**Estimated:** 2 hours  
**Files:** `Views/Reader/ComicPageView.swift`

**Implementation:**
- Display single page image
- Pinch-to-zoom gesture
- Pan gesture when zoomed
- Double-tap to zoom
- Reset zoom on page change

**Success Criteria:**
- [ ] Page displays full screen
- [ ] Pinch-to-zoom works
- [ ] Can pan when zoomed
- [ ] Double-tap toggles zoom
- [ ] Zoom resets properly

**Cursor Prompt:**
```
Create ComicPageView with zoom/pan support.
Reference: @docs/Panels_Clone_Plus_SuperComicOrganizer_Plan.md - ComicPageView

Include:
- MagnificationGesture for pinch-to-zoom
- DragGesture for panning (when zoomed)
- Double-tap gesture to toggle zoom
- Reset to fit on page change
```

---

### □ TASK-013: Paged Reader View
**Dependencies:** TASK-012  
**Estimated:** 3 hours  
**Files:** `Views/Reader/PagedReaderView.swift`

**Implementation:**
- Swipe left/right for page turning
- Smooth page transitions
- Preload next/previous page
- Current page tracking

**Success Criteria:**
- [ ] Can swipe to turn pages
- [ ] Transitions are smooth
- [ ] No lag between pages
- [ ] Edge cases handled (first/last page)

**Cursor Prompt:**
```
Implement PagedReaderView with swipe gestures.
Reference: @docs/Panels_Clone_Plus_SuperComicOrganizer_Plan.md - Paged Reading

Requirements:
- DragGesture for page turning
- 30% screen width threshold
- Smooth animations
- Preload adjacent pages
- Track current page
```

---

### □ TASK-014: Reader Controls Overlay
**Dependencies:** TASK-013  
**Estimated:** 2 hours  
**Files:** `Views/Reader/ReaderControlsOverlay.swift`

**Implementation:**
- Top bar: close, page count, menu
- Bottom bar: slider, prev/next buttons
- Show/hide on tap
- Status bar management

**Success Criteria:**
- [ ] Controls show/hide on tap
- [ ] Page slider works
- [ ] Prev/next buttons work
- [ ] Close button dismisses reader
- [ ] Status bar hidden when controls hidden

**Cursor Prompt:**
```
Create ReaderControlsOverlay.
Reference: @docs/Panels_Clone_Plus_SuperComicOrganizer_Plan.md - Reader Controls

Top bar: close button, page count, menu
Bottom bar: page slider, prev/next buttons
Toggle visibility on tap.
Hide status bar with controls.
```

---

### □ TASK-015: Main Comic Reader View
**Dependencies:** TASK-013, TASK-014  
**Estimated:** 2 hours  
**Files:** `Views/Reader/ComicReaderView.swift`, `ViewModels/ReaderViewModel.swift`

**Implementation:**
- ReaderViewModel to load pages
- ComicReaderView container
- Connect all reader components
- Handle loading states
- Error states

**Success Criteria:**
- [ ] Opens comic file
- [ ] Loads all pages
- [ ] Displays in PagedReaderView
- [ ] Controls work
- [ ] Loading indicator shows
- [ ] Errors display gracefully

**Cursor Prompt:**
```
Create ComicReaderView and ReaderViewModel.
Reference: @docs/Panels_Clone_Plus_SuperComicOrganizer_Plan.md - Reader View

ViewModel loads pages using CBZReader.
View displays pages in PagedReaderView.
Include controls overlay.
Handle loading and error states.
```

---

### □ TASK-016: Connect Reader to Library
**Dependencies:** TASK-015, TASK-008  
**Estimated:** 1.5 hours  
**Files:** Update `Views/Library/LibraryView.swift`, `ViewModels/LibraryViewModel.swift`

**Implementation:**
- Tap on card opens reader
- Pass comic to reader
- Reader presented as sheet
- Dismisses back to library

**Success Criteria:**
- [ ] Tap card opens reader
- [ ] Comic displays correctly
- [ ] Can read full comic
- [ ] Dismiss returns to library
- [ ] No memory leaks

**Test End-to-End:**
- Import comic
- See in library
- Tap to open
- Read all pages
- Close reader
- Verify smooth throughout

---

## 🎯 MILESTONE 5: File Import
**Goal:** Get real comics into the app

### □ TASK-017: File Import UI
**Dependencies:** TASK-016  
**Estimated:** 1 hour  
**Files:** Update `Views/Library/LibraryView.swift`

**Implementation:**
- fileImporter modifier
- Allow CBZ and PDF types
- Multiple selection enabled
- Handle file picker result

**Success Criteria:**
- [ ] "Add Comics" button shows file picker
- [ ] Can select CBZ files
- [ ] Can select PDF files
- [ ] Can select multiple files
- [ ] File picker dismisses properly

---

### □ TASK-018: File Import Processing
**Dependencies:** TASK-017, TASK-010, TASK-011  
**Estimated:** 2 hours  
**Files:** Update `ViewModels/LibraryViewModel.swift`

**Implementation:**
- Process selected files
- Extract cover for each
- Create Comic objects
- Add to library array
- Handle errors

**Success Criteria:**
- [ ] Imports CBZ files
- [ ] Imports PDF files
- [ ] Covers extracted
- [ ] Comics appear in grid
- [ ] Multiple files handled
- [ ] Errors don't crash app

**Test:**
- Import 5 CBZ files
- Import 2 PDF files
- Verify all appear in library
- Verify covers display
- Open and read each one

---

### □ TASK-019: Drag and Drop Support
**Dependencies:** TASK-018  
**Estimated:** 1.5 hours  
**Files:** Update `Views/Library/LibraryView.swift`

**Implementation:**
- onDrop modifier for grid
- Handle fileURL drops
- Process dropped files
- Visual feedback (isTargeted)

**Success Criteria:**
- [ ] Can drag files from Finder
- [ ] Drop zone highlights
- [ ] Files import on drop
- [ ] Works on macOS
- [ ] Multiple files supported

---

## 🎯 MILESTONE 6: Reading Progress
**Goal:** Remember where user left off

### □ TASK-020: Progress Tracking Service
**Dependencies:** TASK-015  
**Estimated:** 1.5 hours  
**Files:** `Services/Progress/ReadingProgressTracker.swift`

**Implementation:**
- Progress struct (comicID, currentPage, totalPages, lastRead)
- Save progress to UserDefaults
- Load progress on open
- Get all progress

**Success Criteria:**
- [ ] Progress saves on reader close
- [ ] Progress restores on reader open
- [ ] Persists across app restarts
- [ ] Multiple comics tracked

---

### □ TASK-021: Progress UI Indicators
**Dependencies:** TASK-020  
**Estimated:** 1 hour  
**Files:** Update `Views/Library/ComicCardView.swift`

**Implementation:**
- Progress bar on comic cards
- Percentage complete text
- Visual indicator for unread/reading/complete

**Success Criteria:**
- [ ] Progress bar shows on cards
- [ ] Updates after reading
- [ ] Visual states clear
- [ ] Doesn't clutter design

**Test:**
- Read comic halfway
- Close reader
- Verify progress shows
- Reopen comic
- Verify continues from same page

---

## ✅ CHECKPOINT: Reader MVP Complete!

At this point you have a **fully functional comic reader**:
- [x] Beautiful library
- [x] Import CBZ and PDF files
- [x] Read comics with page turning
- [x] Zoom and pan
- [x] Progress tracking
- [x] Professional UI

**This is usable now!** You can read comics daily. Everything after this enhances the organization features.

**Celebrate:** 🎉 You've built a working comic reader!

---

## 🎯 MILESTONE 7: Database Foundation
**Goal:** Persistent storage for comics

### □ TASK-022: Database Manager Setup
**Dependencies:** TASK-005  
**Estimated:** 2.5 hours  
**Files:** `Services/Database/DatabaseManager.swift`

**Implementation:**
- GRDB database queue
- Database migrations
- Comics table schema
- Publisher_mappings table
- Activity_log table
- Indexes

**Success Criteria:**
- [ ] Database created on first launch
- [ ] Tables exist
- [ ] Indexes created
- [ ] Location: Application Support/SuperComicOrganizer/
- [ ] No errors on startup

**Cursor Prompt:**
```
Implement DatabaseManager using GRDB.
Reference: @docs/Code_Examples_Part1.md - Database Setup

Create tables:
- comics
- publisher_mappings  
- activity_log

Include migrations and indexes.
```

---

### □ TASK-023: Comic CRUD Operations
**Dependencies:** TASK-022  
**Estimated:** 1.5 hours  
**Files:** Update `Services/Database/DatabaseManager.swift`

**Implementation:**
- Make Comic conform to FetchableRecord, PersistableRecord
- saveComic()
- fetchAllComics()
- updateComic()
- deleteComic()
- searchComics()

**Success Criteria:**
- [ ] Can save comics to database
- [ ] Can retrieve all comics
- [ ] Can update comic properties
- [ ] Can delete comics
- [ ] Search works
- [ ] Tested with 100+ comics

---

### □ TASK-024: Connect Library to Database
**Dependencies:** TASK-023  
**Estimated:** 1 hour  
**Files:** Update `ViewModels/LibraryViewModel.swift`

**Implementation:**
- Load comics from database on launch
- Save new imports to database
- Update UI from database

**Success Criteria:**
- [ ] Library loads from database
- [ ] New imports save to database
- [ ] Comics persist across app restarts
- [ ] No duplicate comics

**Test:**
- Import 10 comics
- Quit app
- Relaunch
- Verify all 10 comics still there

---

## 🎯 MILESTONE 8: Metadata Extraction
**Goal:** Parse comic information from files

### □ TASK-025: Filename Pattern Parser
**Dependencies:** TASK-005  
**Estimated:** 2.5 hours  
**Files:** `Services/Organization/FilenameMetadataExtractor.swift`

**Implementation:**
- Parse "Series #123 (Year)"
- Parse "Series v1 001 (Year) (Publisher)"
- Parse "Publisher - Series - Issue (Year)"
- Extract publisher, series, issue, year
- Handle variations

**Success Criteria:**
- [ ] Correctly parses common patterns
- [ ] Extracts all metadata fields
- [ ] Handles malformed filenames gracefully
- [ ] Tested with 20+ different patterns

**Test Filenames:**
```
Batman #1 (2024).cbz
Amazing Spider-Man v1 001 (1963) (Marvel).cbz
DC Comics - Batman - 001 (1940).cbz
Detective Comics (1937) 027.cbz
```

---

### □ TASK-026: ComicInfo.xml Parser
**Dependencies:** TASK-010  
**Estimated:** 1.5 hours  
**Files:** `Services/Organization/ComicInfoParser.swift`

**Implementation:**
- Parse XML metadata
- Extract Title, Publisher, Series, Number, Year
- Extract Writer, Artist, Summary
- Handle malformed XML

**Success Criteria:**
- [ ] Parses valid ComicInfo.xml
- [ ] Extracts all fields
- [ ] Handles missing fields
- [ ] Doesn't crash on bad XML

---

### □ TASK-027: Unified Metadata Extractor
**Dependencies:** TASK-025, TASK-026  
**Estimated:** 1 hour  
**Files:** `Services/Organization/MetadataExtractor.swift`

**Implementation:**
- Try ComicInfo.xml first
- Fall back to filename parsing
- Merge results intelligently
- Return combined metadata

**Success Criteria:**
- [ ] Uses best source for each field
- [ ] Handles missing data
- [ ] Preference order makes sense

---

### □ TASK-028: Apply Metadata on Import
**Dependencies:** TASK-027  
**Estimated:** 1 hour  
**Files:** Update import process

**Implementation:**
- Extract metadata during import
- Populate Comic properties
- Save to database
- Display in library

**Success Criteria:**
- [ ] Imported comics have metadata
- [ ] Publisher shows on cards
- [ ] Series and issue display
- [ ] Year shows when available

**Test:**
- Import comics with various filename patterns
- Verify metadata extracted
- Check library cards show info

---

## 🎯 MILESTONE 9: File Organization
**Goal:** Organize comic files into folders

### □ TASK-029: Settings UI
**Dependencies:** TASK-006  
**Estimated:** 2 hours  
**Files:** `Views/Settings/SettingsView.swift`

**Implementation:**
- Folder structure picker
- Naming pattern field
- Root library path picker
- Auto-organize toggle
- Confidence threshold slider

**Success Criteria:**
- [ ] All settings controls work
- [ ] Values save to UserDefaults
- [ ] Load on app launch
- [ ] NSOpenPanel works (macOS)
- [ ] Persists across restarts

---

### □ TASK-030: File Organizer Service
**Dependencies:** TASK-027, TASK-029  
**Estimated:** 3 hours  
**Files:** `Services/Organization/FileOrganizer.swift`

**Implementation:**
- Build destination path from settings
- Build new filename from pattern
- Create directories
- Move/rename files
- Update database
- Handle conflicts
- Rollback on error

**Success Criteria:**
- [ ] Organizes to correct path
- [ ] Renames correctly
- [ ] Creates folders as needed
- [ ] Handles duplicate names
- [ ] No data loss on error
- [ ] Database stays in sync

**Test:**
- Organize 10 comics
- Verify correct folder structure
- Verify filenames correct
- Verify files moved (not copied)
- Verify database updated

---

### □ TASK-031: Organize View UI
**Dependencies:** TASK-030  
**Estimated:** 2.5 hours  
**Files:** `Views/Organize/OrganizeView.swift`, related components

**Implementation:**
- Drop zone for files
- Processing queue display
- Show extracted metadata
- Show suggested organization
- Organize button
- Progress indicators

**Success Criteria:**
- [ ] Drag-drop accepts files
- [ ] Shows metadata suggestions
- [ ] Shows destination path
- [ ] Organize button works
- [ ] Progress visible
- [ ] Errors display

---

## 🎯 MILESTONE 10: Learning System
**Goal:** App gets smarter with use

### □ TASK-032: Publisher Seed Data
**Dependencies:** TASK-023  
**Estimated:** 1.5 hours  
**Files:** Seed data in database init

**Implementation:**
- DC Comics mapping (aliases, keywords)
- Marvel Comics mapping
- Image Comics mapping
- Dark Horse mapping
- IDW mapping
- Import on first launch

**Success Criteria:**
- [ ] All major publishers seeded
- [ ] Character keywords included
- [ ] Series keywords included
- [ ] Only imports once
- [ ] Database query confirms present

**Seed Data:**
```swift
DC: ["Batman", "Superman", "Wonder Woman", "Flash", ...]
Marvel: ["Spider-Man", "Iron Man", "X-Men", "Avengers", ...]
Image: ["Walking Dead", "Spawn", "Invincible", ...]
```

---

### □ TASK-033: Pattern Matcher
**Dependencies:** TASK-032  
**Estimated:** 2 hours  
**Files:** `Services/Learning/PatternMatcher.swift`

**Implementation:**
- Extract keywords from filename
- Match against publisher mappings
- Score matches
- Return ranked results

**Success Criteria:**
- [ ] Finds correct publisher for common names
- [ ] Handles aliases (DC = Detective Comics)
- [ ] Scores make sense
- [ ] Fast (< 50ms per comic)

---

### □ TASK-034: Confidence Calculator
**Dependencies:** TASK-033  
**Estimated:** 1.5 hours  
**Files:** `Services/Learning/ConfidenceCalculator.swift`

**Implementation:**
- Calculate confidence (0.0-1.0)
- Boost for publisher name in filename
- Boost for character keywords
- Boost for user confirmation
- Boost for pattern frequency

**Success Criteria:**
- [ ] Scores between 0.0 and 1.0
- [ ] High confidence for obvious matches
- [ ] Low confidence for ambiguous
- [ ] Improves with corrections

---

### □ TASK-035: Learning Engine
**Dependencies:** TASK-033, TASK-034  
**Estimated:** 3 hours  
**Files:** `Services/Learning/LearningEngine.swift`

**Implementation:**
- analyzeComic() method
- learnFromCorrection() method
- Update publisher mappings
- Create new mappings
- Build reasoning strings

**Success Criteria:**
- [ ] Analyzes comics correctly
- [ ] Provides suggestions
- [ ] Learns from corrections
- [ ] New publishers added
- [ ] Keyword lists grow

**Test:**
- Analyze 50 comics
- Note accuracy
- Correct 10 wrong suggestions
- Re-analyze similar comics
- Verify accuracy improved

---

### □ TASK-036: Confidence Indicators UI
**Dependencies:** TASK-034  
**Estimated:** 1 hour  
**Files:** Update card and organize views

**Implementation:**
- Color-coded badges (green/yellow/red)
- Show percentage
- Show reasoning on tap

**Success Criteria:**
- [ ] Badges display on cards
- [ ] Colors match confidence level
- [ ] Reasoning clear and helpful

---

### □ TASK-037: Correction Interface
**Dependencies:** TASK-035, TASK-036  
**Estimated:** 2 hours  
**Files:** `Views/Learning/CorrectionSheet.swift`

**Implementation:**
- Show current suggestion
- Manual input fields
- Publisher picker/search
- Save correction
- Trigger learning

**Success Criteria:**
- [ ] Easy to correct metadata
- [ ] Changes save to database
- [ ] Learning engine updates
- [ ] Similar comics re-analyzed

---

### □ TASK-038: Learning Queue View
**Dependencies:** TASK-037  
**Estimated:** 1.5 hours  
**Files:** `Views/Learning/LearningQueueView.swift`

**Implementation:**
- List comics needing review
- Filter by confidence threshold
- Bulk accept/reject
- Show reasoning

**Success Criteria:**
- [ ] Shows low-confidence comics
- [ ] Sortable/filterable
- [ ] Bulk actions work
- [ ] Individual corrections work

---

## ✅ CHECKPOINT: Organization MVP Complete!

At this point you have:
- [x] Full comic reader
- [x] File organization
- [x] Metadata extraction
- [x] Learning system
- [x] Complete MVP!

**This is production-ready!** Everything after this is enhancement.

---

## 🎯 MILESTONE 11: API Integration (Optional)
**Goal:** Rich metadata from ComicVine

### □ TASK-039: ComicVine API Client
**Dependencies:** TASK-029  
**Estimated:** 3 hours  
**Files:** `Services/API/ComicVineService.swift`

**Implementation:**
- API client setup
- Search endpoint
- Details endpoint
- Rate limiting (1 req/sec)
- Error handling
- Response parsing

**Success Criteria:**
- [ ] Can search by title
- [ ] Can fetch details by ID
- [ ] Rate limiting works
- [ ] Errors handled gracefully
- [ ] API key stored in settings

---

### □ TASK-040: API Search UI
**Dependencies:** TASK-039  
**Estimated:** 2 hours  
**Files:** API search sheet

**Implementation:**
- Search interface
- Results list
- Preview metadata
- Select result
- Update comic

**Success Criteria:**
- [ ] Search works
- [ ] Results display with covers
- [ ] Can select result
- [ ] Metadata updates
- [ ] Saves to database

---

### □ TASK-041: Auto-Lookup Feature
**Dependencies:** TASK-040  
**Estimated:** 1.5 hours  
**Files:** Update organize flow

**Implementation:**
- Auto-lookup setting
- Batch lookup for low confidence
- Update metadata
- Respect rate limits

**Success Criteria:**
- [ ] Auto-lookups low-confidence comics
- [ ] Doesn't exceed rate limit
- [ ] Improves accuracy
- [ ] Can be disabled

---

## 🎯 MILESTONE 12: Polish & Optimization
**Goal:** Production-ready quality

### □ TASK-042: Performance Optimization
**Dependencies:** All core features  
**Estimated:** 2 hours

**Focus Areas:**
- Profile with Instruments
- Optimize slow operations
- Reduce memory usage
- Cache thumbnails
- Lazy load where possible

**Success Criteria:**
- [ ] Library scrolling smooth (60 FPS)
- [ ] Memory usage reasonable
- [ ] No memory leaks
- [ ] Fast app launch

---

### □ TASK-043: Error Handling Polish
**Dependencies:** All core features  
**Estimated:** 1.5 hours

**Implementation:**
- User-friendly error messages
- Retry logic where appropriate
- Graceful degradation
- Error logging

**Success Criteria:**
- [ ] No crashes on errors
- [ ] Clear error messages
- [ ] User knows what to do
- [ ] Errors logged for debugging

---

### □ TASK-044: Loading States
**Dependencies:** All core features  
**Estimated:** 1 hour

**Add loading indicators:**
- Library loading
- Import processing
- Organization in progress
- API requests

**Success Criteria:**
- [ ] User always knows what's happening
- [ ] No blank screens
- [ ] Progress visible
- [ ] Can cancel long operations

---

### □ TASK-045: Animations & Transitions
**Dependencies:** All UI tasks  
**Estimated:** 1.5 hours

**Polish:**
- Smooth view transitions
- Card hover effects (macOS)
- Button feedback
- Sheet presentations
- Subtle animations

**Success Criteria:**
- [ ] Feels polished
- [ ] Not overdone
- [ ] Smooth (60 FPS)
- [ ] Enhances UX

---

### □ TASK-046: Accessibility
**Dependencies:** All UI tasks  
**Estimated:** 1 hour

**Implementation:**
- VoiceOver support
- Dynamic Type support
- Keyboard navigation
- Focus management
- Contrast ratios

**Success Criteria:**
- [ ] VoiceOver describes UI correctly
- [ ] Text scales properly
- [ ] Keyboard navigation works
- [ ] Passes accessibility audit

---

### □ TASK-047: Testing & Bug Fixes
**Dependencies:** All features  
**Estimated:** 3 hours

**Test:**
- End-to-end workflows
- Edge cases
- Platform-specific issues
- Large libraries (1000+ comics)
- Memory with large files

**Success Criteria:**
- [ ] No crashes in normal use
- [ ] All features work
- [ ] Edge cases handled
- [ ] Performance good with large library

---

## 🎉 Final Checklist: Production Ready

### Features Complete
- [ ] Comic reader works smoothly
- [ ] File import works (CBZ, PDF)
- [ ] Library displays all comics
- [ ] Organization works
- [ ] Metadata extraction accurate
- [ ] Learning system improves
- [ ] Settings persist
- [ ] Progress tracking works

### Quality Metrics
- [ ] No crashes during testing
- [ ] Smooth scrolling (60 FPS)
- [ ] Fast loading (< 2s for 1000 comics)
- [ ] Memory reasonable (< 1GB)
- [ ] Works on macOS
- [ ] Works on iPad
- [ ] Dark mode supported

### Code Quality
- [ ] All code committed to git
- [ ] No compiler warnings
- [ ] No force unwrapping
- [ ] Error handling everywhere
- [ ] No memory leaks
- [ ] Comments on complex code

### User Testing
- [ ] Tested by others
- [ ] Feedback collected
- [ ] Critical bugs fixed
- [ ] Ready for daily use

---

## 📊 Task Dependencies Chart

```
Foundation:
TASK-001 → TASK-002 → TASK-003 → TASK-004

Data Models:
TASK-002 → TASK-005, TASK-006

Library UI:
TASK-004 + TASK-005 → TASK-007 → TASK-008 → TASK-009

Reader Core:
TASK-005 → TASK-010, TASK-011 → TASK-012 → TASK-013 → TASK-014 → TASK-015

Reader + Library:
TASK-015 + TASK-008 → TASK-016

Import:
TASK-016 + TASK-010 + TASK-011 → TASK-017 → TASK-018 → TASK-019

Progress:
TASK-015 → TASK-020 → TASK-021

Database:
TASK-005 → TASK-022 → TASK-023 → TASK-024

Metadata:
TASK-005 → TASK-025, TASK-026 → TASK-027 → TASK-028

Organization:
TASK-027 + TASK-029 → TASK-030 → TASK-031

Learning:
TASK-023 → TASK-032 → TASK-033 → TASK-034 → TASK-035 → TASK-036, TASK-037, TASK-038

API (Optional):
TASK-029 → TASK-039 → TASK-040 → TASK-041

Polish:
All features → TASK-042 through TASK-047
```

---

## 🚀 Suggested Task Order (Fast Track)

### Sprint 1: Get Something Running
```
TASK-001 → TASK-002 → TASK-003 → TASK-004
Result: App runs with navigation
Time: ~3 hours
```

### Sprint 2: Add Visual Content
```
TASK-005 → TASK-007 → TASK-008 → TASK-009
Result: Beautiful library with mock comics
Time: ~5 hours
```

### Sprint 3: Build Reader (Most Important!)
```
TASK-010 → TASK-011 → TASK-012 → TASK-013 → TASK-014 → TASK-015
Result: Working comic reader!
Time: ~15 hours
```

### Sprint 4: Connect Everything
```
TASK-016 → TASK-017 → TASK-018 → TASK-019 → TASK-020 → TASK-021
Result: Import and read real comics!
Time: ~8 hours
```

**At this point: USABLE APP! (~31 hours total)**

### Sprint 5: Add Persistence
```
TASK-022 → TASK-023 → TASK-024
Result: Comics saved to database
Time: ~5 hours
```

### Sprint 6: Smart Features
```
TASK-025 → TASK-026 → TASK-027 → TASK-028 → TASK-029 → TASK-030 → TASK-031
Result: Metadata extraction and organization
Time: ~13 hours
```

### Sprint 7: Learning System
```
TASK-032 → TASK-033 → TASK-034 → TASK-035 → TASK-036 → TASK-037 → TASK-038
Result: App learns and improves
Time: ~13 hours
```

**At this point: COMPLETE MVP! (~62 hours total)**

### Sprint 8: Polish (Optional)
```
TASK-042 → TASK-043 → TASK-044 → TASK-045 → TASK-046 → TASK-047
Result: Production-ready quality
Time: ~10 hours
```

### Sprint 9: API (Optional)
```
TASK-039 → TASK-040 → TASK-041
Result: ComicVine integration
Time: ~7 hours
```

---

## 🎯 Task Tracking Template

Copy this to a `TASKS.md` file in your project:

```markdown
# Super Comic Organizer - Task Progress

## Sprint 1: Foundation ⏱️ ~3 hours
- [ ] TASK-001: Initial Project Setup
- [ ] TASK-002: Folder Structure
- [ ] TASK-003: Design System
- [ ] TASK-004: Navigation Structure

## Sprint 2: Library UI ⏱️ ~5 hours
- [ ] TASK-005: Comic Model
- [ ] TASK-007: Library Grid Layout
- [ ] TASK-008: Comic Card Component
- [ ] TASK-009: Library Toolbar

## Sprint 3: Reader ⏱️ ~15 hours ⭐
- [ ] TASK-010: CBZ Reader Service
- [ ] TASK-011: PDF Reader Service
- [ ] TASK-012: Comic Page View
- [ ] TASK-013: Paged Reader View
- [ ] TASK-014: Reader Controls Overlay
- [ ] TASK-015: Main Comic Reader View

## Sprint 4: Integration ⏱️ ~8 hours
- [ ] TASK-016: Connect Reader to Library
- [ ] TASK-017: File Import UI
- [ ] TASK-018: File Import Processing
- [ ] TASK-019: Drag and Drop Support
- [ ] TASK-020: Progress Tracking Service
- [ ] TASK-021: Progress UI Indicators

✅ CHECKPOINT: Usable Reader!

## Sprint 5: Database ⏱️ ~5 hours
- [ ] TASK-022: Database Manager Setup
- [ ] TASK-023: Comic CRUD Operations
- [ ] TASK-024: Connect Library to Database

## Sprint 6: Organization ⏱️ ~13 hours
- [ ] TASK-025: Filename Pattern Parser
- [ ] TASK-026: ComicInfo.xml Parser
- [ ] TASK-027: Unified Metadata Extractor
- [ ] TASK-028: Apply Metadata on Import
- [ ] TASK-029: Settings UI
- [ ] TASK-030: File Organizer Service
- [ ] TASK-031: Organize View UI

## Sprint 7: Learning ⏱️ ~13 hours
- [ ] TASK-032: Publisher Seed Data
- [ ] TASK-033: Pattern Matcher
- [ ] TASK-034: Confidence Calculator
- [ ] TASK-035: Learning Engine
- [ ] TASK-036: Confidence Indicators UI
- [ ] TASK-037: Correction Interface
- [ ] TASK-038: Learning Queue View

✅ CHECKPOINT: Complete MVP!

## Sprint 8: Polish ⏱️ ~10 hours
- [ ] TASK-042: Performance Optimization
- [ ] TASK-043: Error Handling Polish
- [ ] TASK-044: Loading States
- [ ] TASK-045: Animations & Transitions
- [ ] TASK-046: Accessibility
- [ ] TASK-047: Testing & Bug Fixes

## Sprint 9: API (Optional) ⏱️ ~7 hours
- [ ] TASK-039: ComicVine API Client
- [ ] TASK-040: API Search UI
- [ ] TASK-041: Auto-Lookup Feature

## Current Sprint: [FILL IN]
## Current Task: [FILL IN]
## Estimated Hours Remaining: [FILL IN]
```

---

## 💡 Tips for Moving Fast

### 1. **Focus on One Task at a Time**
Complete each task fully before moving to next. No half-finished work.

### 2. **Use the Code Examples**
Copy from `Code_Examples_Part1.md` liberally. Don't reinvent.

### 3. **Test Immediately**
Build and run after each task. Catch bugs early.

### 4. **Commit After Each Task**
```bash
git add .
git commit -m "Complete TASK-XXX: [task name]"
```

### 5. **Skip Optional Tasks Initially**
Get to usable reader (Sprint 4) as fast as possible. Everything else can wait.

### 6. **Batch Similar Tasks**
Do all reader tasks together. Do all UI tasks together. Stay in flow.

### 7. **Time-Box Tasks**
If stuck >2x estimated time, ask for help or move on. Come back later.

---

## 🎮 Challenge Mode: Speed Run

**Goal:** Working reader in one focused day

**8:00 AM - Sprint 1 (Foundation)** ⏱️ 3 hours
- TASK-001 through TASK-004
- Break at 11:00 AM

**11:30 AM - Sprint 2 (Library UI)** ⏱️ 3 hours  
- TASK-005, TASK-007, TASK-008, TASK-009
- Lunch at 2:30 PM

**3:30 PM - Sprint 3 (Reader Core)** ⏱️ 5 hours
- TASK-010 through TASK-013
- Dinner at 8:30 PM

**9:30 PM - Sprint 4 (Integration)** ⏱️ 3 hours
- TASK-014 through TASK-018
- Done by midnight with working reader!

**Total:** ~14 hours focused work  
**Result:** Can read comics!

---

## 📝 Notes Section

Use this space to track:
- Blockers encountered
- Decisions made
- Things to revisit
- Ideas for future

---

**Ready to start? Pick TASK-001 and go! 🚀**
