# Hook Input/Output Format

## Overview

These hooks integrate with Claude Code's hook system. Each hook receives JSON on stdin and outputs JSON on stdout.

## Input Format (stdin)

### PreToolUse / PostToolUse hooks
```json
{
  "tool_name": "Write|Edit|MultiEdit",
  "file_path": "/path/to/file.py",
  "path": "/path/to/file.py"
}
```

### Stop hooks
No stdin input. Hook runs at end of agent response.

### PreCompact hooks
No stdin input. Hook runs before context compaction.

## Output Format (stdout)

All hooks output JSON with optional `additionalContext`:
```json
{
  "additionalContext": "Message that Claude sees as guidance for its next response."
}
```

If no output is needed, the hook exits silently with code 0.

## Hook Scripts

| Script | Event | Purpose |
|--------|-------|---------|
| tdd-gate.sh | PreToolUse (Write/Edit) | Checks test file exists before production code edit |
| post-edit-check.sh | PostToolUse (Write/Edit) | Scans for env vars, secrets, dead code, Dockerfile issues |
| completion-gate.sh | Stop | Counts orphaned TODOs in changed files. Tests and coverage run only with `COMPLETION_GATE_RUN_TESTS=1` |
| state-saver.sh | PreCompact | Saves session state to .claude/state/autosaves/ before context compaction |

### completion-gate opt-in

The Stop hook runs after every reply, so by default it does not run test suites. Set `COMPLETION_GATE_RUN_TESTS=1` to also run pytest (`-x`), `npm test` (with `--maxWorkers=3` when the test script is jest or vitest) and `coverage report --fail-under=80`. Failure is judged by exit code. `hooks.json` caps the hook at 120 s.

## Dependencies

- **Required:** python3, git
- **Optional:** ruff (dead code detection), pytest + coverage (only used with `COMPLETION_GATE_RUN_TESTS=1`)

## Installation

Run `bash hooks/setup.sh` to:
1. Make all hook scripts executable
2. Auto-detect and update hook paths in hooks.json
3. Check dependencies
4. Provide instructions for merging into Claude Code settings
