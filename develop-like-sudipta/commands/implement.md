---
description: Implement an existing plan or design doc. SKIP planning. Go straight to TDD + code execution.
---

# Implement Command

**DO NOT create a new plan. DO NOT load superpowers:writing-plans.**
A plan or design doc already exists. Execute it NOW.

## Procedure

1. **READ** the provided plan/design document. If no file specified, check `.claude/plans/` for the latest.
2. **VERIFY** it's actionable — has goal, approach, file list? If yes → proceed.
3. **LOAD** superpowers:subagent-driven-development
4. **BREAK** into tasks — one per module/component.
5. **FOR EACH TASK:**
   - Dispatch `test-writer` agent → RED phase (failing tests)
   - Dispatch `implementer` agent → GREEN phase (minimum code to pass)
   - Run tests to verify GREEN
6. **REFACTOR** — clean up while tests stay GREEN.
7. **REVIEW** — invoke `code-reviewer` agent on all changes.
8. **SECURE** — invoke `security-reviewer` agent on all changes.

This is steps 3-15 of the Unified Workflow. Steps 1-2 (brainstorm/plan) are SKIPPED.

**If the user says "implement" and you're about to load writing-plans → STOP. Use this command instead.**
