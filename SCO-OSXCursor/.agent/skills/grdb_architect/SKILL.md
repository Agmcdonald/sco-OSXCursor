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