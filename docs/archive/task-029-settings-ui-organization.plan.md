# TASK-029: Settings UI — Organization Settings

## Current State Analysis

**What exists:**
- `AppSettings.swift` defines comprehensive organization settings:
  - `folderStructure` (enum with multiple options: Publisher/Series/Issue, Series/Issue, Flat, etc.)
  - `namingPattern` (string with variable support: {publisher}, {series}, {issue}, etc.)
  - `rootLibraryPath` (URL for library location)
  - `autoOrganize` (Bool toggle)
  - `confidenceThreshold` (Double 0.0-1.0)
  - Helper methods for naming pattern validation and preview
- `SettingsView.swift` currently only shows Reader settings (page transition)
- `PublisherDetector` exists but is hardcoded; database has `publisher_mappings` table

**What's missing:**
- UI in SettingsView to configure organization settings
- Settings persistence integration (AppSettings has save/load but may not be actively used)
- UI for folder structure selection
- UI for naming pattern editor with variable help
- UI for root library path selection
- UI for auto-organize toggle
- UI for confidence threshold slider

## Implementation Plan

### 1. Create SettingsViewModel
- **File**: `SCO-OSXCursor/ViewModels/SettingsViewModel.swift` (new)
- **Action**: Create ObservableObject to manage AppSettings
  - Load settings from UserDefaults on init
  - Auto-save on changes (debounced)
  - Provide @Published properties for UI binding
  - Handle settings validation

### 2. Update Default Naming Pattern
- **File**: `SCO-OSXCursor/Models/AppSettings.swift`
- **Action**: Update default naming pattern to include series in filename
  - Change from: `"{publisher}/{series}/#{issue} ({year})"`
  - Change to: `"{publisher}/{series}/{series} - #{issue} ({year})"`
  - This produces: `DC Comics/Batman/Batman - #001 (2024).cbz`
  - Makes files identifiable even when moved out of folder structure

### 3. Expand SettingsView with Organization Section
- **File**: `SCO-OSXCursor/Views/Settings/SettingsView.swift`
- **Action**: Add comprehensive organization settings UI:
  - **Section Header**: "Organization" with icon
  - **Folder Structure Picker**: 
    - Picker showing all FolderStructure enum options
    - Show description for each option
    - Show example path for selected structure
  - **Naming Pattern Editor**:
    - TextField for pattern input
    - Helper text below showing all available variables: `{publisher}, {series}, {issue}, {year}, {title}, {volume}, {writer}, {artist}`
    - Live preview showing example output using sample comic data
    - Validation indicator (checkmark if valid)
  - **Root Library Path**:
    - Button to select folder path
    - Display current path (or "Not set")
    - Clear button to remove path
  - **Auto-Organize Toggle**:
    - Toggle switch with description
    - Explain what auto-organize does
  - **Confidence Threshold**:
    - Slider (0.0-1.0) with step 0.1
    - Display current value as percentage (e.g., "70%")
    - Description explaining what confidence threshold means
  - **Reset to Defaults Button**:
    - Button to reset all organization settings to defaults
    - Confirmation alert before resetting

### 4. Add UI Components for Settings
- **File**: `SCO-OSXCursor/Views/Settings/SettingsView.swift` (inline components)
- **Action**: Create reusable components within SettingsView:
  - `FolderStructurePicker`: Picker with descriptions and examples
  - `NamingPatternEditor`: TextField with helper text and preview
  - `PathSelector`: Button to select folder path with display
  - `ConfidenceSlider`: Slider with formatted value display

### 5. Integrate Settings Persistence
- **File**: `SCO-OSXCursor/ViewModels/SettingsViewModel.swift`
- **Action**: Ensure settings are saved/loaded properly:
  - Load from UserDefaults on init using `AppSettings.load()`
  - Auto-save when any setting changes (debounced, ~250ms)
  - Handle settings migration if structure changes
  - Provide reset method that calls `AppSettings.reset()` and reloads

### 6. Add Settings Preview/Examples
- **File**: `SCO-OSXCursor/Views/Settings/SettingsView.swift`
- **Action**: Show helpful examples:
  - Example folder structure path based on selected structure
  - Example filename based on naming pattern (using sample comic: "Batman #001 (2024)")
  - Full example path showing complete organization structure

### 7. Create Adaptive Learning Service
- **File**: `SCO-OSXCursor/Services/Learning/OrganizationLearner.swift` (new)
- **Action**: Create service that learns from imported books:
  - **Pattern Detection**: Analyze imported comics to detect naming patterns
    - Extract patterns from existing filenames (e.g., "Series #001 (2024).cbz" → pattern detected)
    - Group patterns by publisher (using publisher mappings)
    - Track pattern frequency and confidence
  - **Publisher-Based Learning**: 
    - When a comic is imported with a publisher that exists in publisher_mappings
    - Check if similar titles/series from same publisher follow a pattern
    - Learn the naming convention used for that publisher
    - Update naming pattern suggestions based on learned patterns
  - **Pattern Matching**:
    - When new comic is imported, check if it matches learned patterns
    - If publisher matches and pattern confidence exceeds threshold, suggest/apply learned pattern
    - Update pattern confidence based on successful matches
  - **Integration Points**:
    - Called during import process (LibraryViewModel.importComic)
    - Uses publisher mappings from database
    - Respects confidence threshold from AppSettings
    - Logs learning decisions for debugging

### 8. Integrate Learning into Import Flow
- **File**: `SCO-OSXCursor/ViewModels/LibraryViewModel.swift`
- **Action**: Integrate OrganizationLearner into import process:
  - After metadata extraction, call learner to analyze pattern
  - If pattern matches learned publisher pattern with high confidence, log suggestion
  - Store learned patterns in database (new table or extend publisher_mappings)
  - Update naming pattern suggestions in SettingsViewModel when patterns are learned

### 9. Add Learning Status to Settings UI
- **File**: `SCO-OSXCursor/Views/Settings/SettingsView.swift`
- **Action**: Add learning status display:
  - Show number of learned patterns
  - Show which publishers have learned patterns
  - Option to view/clear learned patterns
  - Toggle to enable/disable adaptive learning (uses AppSettings.enableLearning)

### 10. Add Correction/Feedback System
- **File**: `SCO-OSXCursor/Views/Library/ComicDetailView.swift` (new) or extend existing views
- **Action**: Create UI for correcting imported comics:
  - **Edit Comic Metadata**: 
    - Allow editing publisher (with autocomplete from publisher_mappings)
    - Allow editing series name
    - Allow editing other metadata fields (title, issue number, year, etc.)
    - Save button to persist corrections
  - **Correction Feedback**:
    - When user corrects publisher/series, mark as "user corrected"
    - Log correction in activity_log table
    - Feed correction back to OrganizationLearner
  - **Learning from Corrections**:
    - When publisher is corrected, update learned patterns for that publisher
    - When series is corrected, learn that series belongs to corrected publisher
    - Adjust pattern confidence based on corrections (corrections increase confidence for correct patterns)
    - Future imports with similar metadata will use corrected information

### 11. Integrate Corrections into Learning System
- **File**: `SCO-OSXCursor/Services/Learning/OrganizationLearner.swift`
- **Action**: Add correction handling:
  - **Record Corrections**: 
    - Method to record user corrections (correctedPublisher, correctedSeries, originalValues)
    - Store in database (extend activity_log or create corrections table)
  - **Learn from Corrections**:
    - When publisher is corrected, update publisher_mappings confidence
    - When series is corrected, learn series-to-publisher association
    - Adjust naming pattern confidence based on corrections
    - Future imports: if metadata matches corrected pattern, use corrected values
  - **Pattern Adjustment**:
    - If user corrects a comic that matched a learned pattern, adjust pattern confidence
    - If correction confirms a pattern, increase confidence
    - If correction contradicts a pattern, decrease confidence or remove pattern

### 12. Add Correction UI to Library View
- **File**: `SCO-OSXCursor/Views/Library/LibraryView.swift` or `ComicCardView.swift`
- **Action**: Add correction access points:
  - **Context Menu**: Add "Edit Metadata" option to comic context menu
  - **Detail View**: Create/edit comic detail view with editable fields
  - **Quick Edit**: Inline editing for publisher/series in list view (optional)
  - **Correction Indicator**: Show badge/icon if comic was user-corrected

## Files to Modify/Create

1. `SCO-OSXCursor/Views/Settings/SettingsView.swift` - Expand with organization settings UI
2. `SCO-OSXCursor/ViewModels/SettingsViewModel.swift` - New file for settings management
3. `SCO-OSXCursor/Models/AppSettings.swift` - Update default naming pattern
4. `SCO-OSXCursor/Services/Learning/OrganizationLearner.swift` - New learning service
5. `SCO-OSXCursor/ViewModels/LibraryViewModel.swift` - Integrate learning into import
6. `SCO-OSXCursor/Services/Database/DatabaseManager.swift` - Add table for learned patterns (or extend publisher_mappings)
7. `SCO-OSXCursor/Views/Library/ComicDetailView.swift` - New view for editing comic metadata
8. `SCO-OSXCursor/ViewModels/ComicEditViewModel.swift` - New view model for editing comics
9. `SCO-OSXCursor/Views/Library/LibraryView.swift` - Add correction UI access points

## Expected Outcome

- SettingsView includes a complete Organization section with all settings
- Users can configure:
  - Folder structure (Publisher/Series/Issue, Series/Issue, Flat, Custom, etc.) with examples
  - Naming pattern with variable support, helper text, and live preview
  - Root library path with folder picker
  - Auto-organize toggle with explanation
  - Confidence threshold slider with percentage display
  - Reset to defaults button with confirmation
  - Learning status showing learned patterns and publishers
- Default naming pattern includes series in filename: `{publisher}/{series}/{series} - #{issue} ({year})`
- Settings persist across app launches
- UI is clear and provides helpful examples/previews
- Publisher mapping management remains in Knowledge view (not in Settings)
- **Adaptive Learning System**:
  - App learns naming patterns from imported books
  - When a book matches a publisher in publisher_mappings, app analyzes its naming pattern
  - Similar titles from same publisher automatically use learned naming convention
  - Learning respects confidence threshold setting
  - Patterns improve over time as more books are imported
  - Users can view and manage learned patterns in Settings
- **Correction/Feedback System**:
  - Users can correct publisher/series for incorrectly imported books
  - Corrections are recorded and fed back into learning system
  - System learns from corrections to improve future imports
  - Corrected comics are marked and can be reviewed
  - Future imports with similar metadata use corrected information

## Design Notes

- Use consistent styling with existing SettingsView (Form with sections)
- Match app's design system (Typography, Spacing, Colors)
- Provide clear descriptions and examples for each setting
- Make it easy to understand what each setting does
- Show live previews where helpful (naming pattern, folder structure)

## Learning System Details

### How Learning Works:
1. **Pattern Detection**: When a comic is imported:
   - Extract filename pattern (e.g., "Batman #001 (2024).cbz" → "{series} #{issue} ({year})")
   - Identify publisher from metadata or publisher_mappings
   - Store pattern with publisher association

2. **Pattern Matching**: When a new comic is imported:
   - Check if publisher exists in publisher_mappings
   - Look for learned patterns for that publisher
   - If pattern confidence > confidence threshold, suggest/apply learned pattern
   - If pattern matches existing learned pattern, increase confidence

3. **Pattern Updates**: 
   - When similar titles appear (same publisher, similar series naming), update pattern confidence
   - Patterns with higher confidence are preferred
   - Patterns can be manually overridden by user

4. **Integration**:
   - Learning happens automatically during import (if enableLearning is true)
   - Learned patterns inform naming pattern suggestions
   - Users can view learned patterns in Settings
   - Users can clear learned patterns if needed

5. **Correction Feedback Loop**:
   - User corrects publisher/series for incorrectly imported comic
   - Correction is recorded in database (activity_log or corrections table)
   - OrganizationLearner processes correction:
     - Updates publisher_mappings confidence if publisher was corrected
     - Learns series-to-publisher association if series was corrected
     - Adjusts pattern confidence (increases if correction confirms pattern, decreases if contradicts)
   - Future imports: If metadata matches corrected pattern, use corrected values
   - System becomes more accurate over time as corrections accumulate

