# Agent Skill: Design System Guardian
## Description
This skill enforces the SCO-OSXCursor design system. It ensures all SwiftUI views use the project's custom typography, spacing tokens, and publisher-aware color palettes instead of system defaults.

## Trigger
Use this skill when:
- Generating or modifying SwiftUI Views.
- The user asks to "style" or "polish" a UI component.
- The user mentions "Publisher Colors" or "Comic Fonts".

## Rules & Constraints
1. **Typography:**
   - NEVER use system fonts like `.title`, `.headline`, or `.body`.
   - ALWAYS use the custom `Font.comic` extension:
     - `Font.comic(.display)` for headers.
     - `Font.comic(.reading)` for body text.
     - `Font.comic(.caption)` for metadata.

2. **Colors (Publisher-Aware):**
   - Do NOT use hardcoded colors (e.g., `.red`, `.blue`).
   - Use `Color.theme` for semantic colors:
     - `Color.theme.background`
     - `Color.theme.surface`
   - Use `PublisherTheme` for dynamic branding:
     - `PublisherTheme(for: comic).primary`
     - `PublisherTheme(for: comic).accent`

3. **Components:**
   - Use `ComicCardView` for displaying covers.
   - Use `MetadateBadge` for tags.

## Example Output
```swift
// WRONG
Text(comic.title).font(.title).foregroundColor(.blue)

// RIGHT
Text(comic.title)
    .font(.comic(.display))
    .foregroundColor(PublisherTheme(for: comic).primary)
---

### 2. The GRDB Schema Architect
**Path:** `.agent/skills/grdb_architect/SKILL.md`

```markdown
# Agent Skill: GRDB Schema Architect
## Description
This skill manages the SQLite database layer using GRDB. It ensures thread safety, correct migration patterns, and efficient query generation for the comic library.

## Trigger
Use this skill when:
- Creating or modifying `PersistableRecord` models.
- Writing database migrations.
- optimizing SQL queries or FetchRequests.

## Rules & Constraints
1. **Migrations:**
   - Always check `AppDatabase.swift` for the current migration version.
   - When modifying a struct, generate a corresponding `migrator.registerMigration(...)` block.
   - Column names must be defined in a `enum Columns: String, ColumnExpression` within the Record struct.

2. **Concurrency:**
   - Database writes must happen inside `dbWriter.write`.
   - Database reads should use `dbReader.read` or `ValueObservation` for reactive UI updates.

3. **Naming Conventions:**
   - Table names must be plural (e.g., `ComicIssues`, `Publishers`).
   - Struct names must be singular (e.g., `ComicIssue`, `Publisher`).

## Template: New Record
```swift
import GRDB

struct NewModel: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    
    enum Columns: String, ColumnExpression {
        case id, name
    }
}

---

### 3. The MVVM Boilerplate Generator
**Path:** `.agent/skills/mvvm_generator/SKILL.md`

```markdown
# Agent Skill: MVVM Generator
## Description
Scaffolds new features following the project's strict MVVM architecture. Ensures separation of concerns between View, ViewModel, and Service layers.

## Trigger
Use this skill when:
- The user asks to "create a feature" or "scaffold a view".
- The user mentions "MVVM".

## Rules & Constraints
1. **ViewModel Structure:**
   - Must be a `class` conforming to `ObservableObject`.
   - Must be annotated with `@MainActor` to ensure UI updates happen on the main thread.
   - Dependencies (Services) must be injected via `init`.

2. **View Structure:**
   - Must own the ViewModel using `@StateObject`.
   - Should rely on the ViewModel for all logic, formatting, and state management.

3. **Service Layer:**
   - Do NOT put business logic in the View. Call a function on the ViewModel, which calls the Service.

## Template
```swift
// 1. ViewModel
@MainActor
class FeatureViewModel: ObservableObject {
    @Published var state: ViewState = .idle
    private let service: ServiceProtocol
    
    init(service: ServiceProtocol = DefaultService()) {
        self.service = service
    }
}

// 2. View
struct FeatureView: View {
    @StateObject private var viewModel = FeatureViewModel()
    
    var body: some View {
        // UI Implementation
    }
}

---

### 4. The Doc-Keeper
**Path:** `.agent/skills/doc_keeper/SKILL.md`

```markdown
# Agent Skill: Doc-Keeper
## Description
Maintains the high-quality documentation standards of SCO-OSXCursor. It ensures that code changes are reflected in the project's tracking files.

## Trigger
Use this skill when:
- The user says "Update docs" or "I finished X".
- Writing a commit message or PR description.
- Closing a task from the plan.

## Rules & Constraints
1. **File Awareness:**
   - `IMPLEMENTATION_COMPLETE.md`: High-level summary of finished milestones.
   - `task-029-settings-ui-organization.plan.md`: Specific tracking for the current Organization feature.
   - `READER_ENHANCEMENTS_SUMMARY.md`: Details on gesture/rendering engines.

2. **Formatting:**
   - Use `[x]` to mark checklist items as complete.
   - When adding new features, follow the existing style: `**Feature Name**: Description`.

3. **Verification:**
   - Before marking a task complete, ask: "Did we implement the tests for this?"
   - If a feature changes (e.g., gestures), check if `docs/INDEX.md` needs a new screenshot reference.