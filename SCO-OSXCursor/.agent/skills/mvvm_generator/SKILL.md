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