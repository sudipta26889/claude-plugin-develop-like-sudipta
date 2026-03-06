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
| completion-gate.sh | Stop | Verifies tests pass, coverage meets threshold, no orphaned TODOs |
| state-saver.sh | PreCompact | Saves session state to .claude/plans/ before context compaction |

## Dependencies

- **Required:** python3, git
- **Optional:** ruff (dead code detection), pytest + coverage (test/coverage checks)

## Installation

Run `bash hooks/setup.sh` to:
1. Make all hook scripts executable
2. Auto-detect and update hook paths in hooks.json
3. Check dependencies
4. Provide instructions for merging into Claude Code settings
