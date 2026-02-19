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