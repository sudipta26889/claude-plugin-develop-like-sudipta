# Substrate and access — how Cowork's commands actually reach the user's Mac

This is the first thing to understand before anything else in this skill. The bundled scripts (`send.sh`, `read.sh`, `watchdog.sh`, etc.) **must run on the user's macOS host**, not in Cowork's sandbox. AppleScript only exists on macOS; the sandbox is Linux.

This document defines the **substrate detection ladder** Cowork must walk through at the start of every session, and the consequences of each path.

## The three execution paths

| Path | Mechanism | Speed | Typing restriction | When available |
|---|---|---|---|---|
| **A. Desktop_Commander MCP** | `mcp__Desktop_Commander__*` runs commands directly on the user's Mac via SSH-like daemon | fast | none (it's full shell) | Cowork desktop app on macOS, DC connector installed |
| **B. computer-use MCP** | `mcp__computer-use__*` controls the Mac via screenshots + clicks | slow | **Terminal/iTerm are tier-click — typing IS blocked at MCP level**; must shell out to osascript to actually type | Cowork desktop app on macOS, computer-use granted |
| **C. Manual / user-driven** | Tell the user to run install + start-watchdog commands themselves | n/a | none | always — last-resort fallback |

**Important reality:** Cowork's bash tool runs in a Linux sandbox. It cannot run `osascript`. It cannot write to `~/.cache/ccbridge/` on the user's Mac. It can only read from user-selected mounted folders (`/Users/sudipta/Workspace/...` mapped via `/sessions/.../mnt/...`). So **the sandbox bash is not a viable path** for driving CC — it's only useful for editing files in mounted dirs.

## Detection ladder (run at session start, in this exact order)

### Step 0 — Confirm we are in Cowork on macOS

If the user is on a different OS, the bridge does not apply at all. Inspect:
- The system prompt mentions Cowork mode? ✓
- The mounted workspace path looks like `/Users/<name>/...`? ✓
- `uname -s` in bash returns `Linux` BUT mounted paths are macOS-style? ✓ (the sandbox is Linux, but the host is macOS)

If any of these fail → tell the user this skill is macOS-only and stop.

### Step 1 — Probe MCP availability

Without making tool calls (just by introspecting the prompt context), check which MCPs are present:

- **Desktop_Commander present?** → look for `mcp__Desktop_Commander__*` tool names in the tool list. If yes → **Path A** is preferred.
- **computer-use present?** → look for `mcp__computer-use__*` tool names. If yes → **Path B** is a fallback.
- **Neither present?** → only **Path C** (manual) is possible.

If both are present, **prefer Path A**. Desktop_Commander is API-driven, no GUI focus, no screenshot latency.

### Step 2 — Confirm CC is actually running

Regardless of path, Cowork needs to verify CC is alive in Terminal before driving it:

**Path A (Desktop_Commander):**
```
mcp__Desktop_Commander__start_process / interact_with_process
  → ps aux | grep -i 'claude' | grep -v grep
  → osascript -e 'tell application "Terminal" to return name of selected tab of front window'
```

**Path B (computer-use):**
```
mcp__computer-use__list_granted_applications
  → confirm Terminal (or iTerm) is in the list
mcp__computer-use__request_access(applications=["Terminal"])
  → user approves; check the returned tier — should be "click"
mcp__computer-use__screenshot()
  → visually confirm CC's prompt is on screen
```

**Path C (manual):** ask the user "Is Claude Code running in Terminal.app right now? If yes, paste a screenshot or describe what you see."

### Step 3 — Install the bridge scripts on the Mac

The scripts live in the plugin at `<plugin-skill-path>/scripts/*`. They need to be copied to `~/.cache/ccbridge/` on the user's Mac (idempotent).

**Path A:**
```
mcp__Desktop_Commander__create_directory(path="~/.cache/ccbridge")
mcp__Desktop_Commander__start_process(
  command="bash <path-to-plugin>/skills/sd-claude-code-access/scripts/install.sh"
)
```
This actually runs install.sh on the user's Mac. The plugin is installed under `~/.claude/plugins/.../develop-like-sudipta/` so the path is reachable.

**Path B:**
```
mcp__computer-use__open_application(name="Terminal")
mcp__computer-use__request_access(applications=["Terminal"])
# computer-use cannot TYPE into Terminal (tier-click), but can scroll/click.
# Workaround: write a one-liner to a file under a mounted workspace dir, then ask the
# user to drag/drop that file into Terminal (Terminal accepts drag-drop to insert path)
# OR ask the user to manually run a single short command we display in chat.
```
This is awkward. In practice with Path B, fall through to Path C for install — ask the user to run a single command. (Once installed, send.sh/read.sh handle subsequent driving via the running watchdog.)

**Path C:**
Display the command in chat:
```
# Run this once in your Mac Terminal:
bash ~/.claude/plugins/marketplaces/.../develop-like-sudipta/skills/sd-claude-code-access/scripts/install.sh
```
Wait for user to confirm done.

### Step 4 — Start the watchdog and acquire the driver lock

**Path A:**
```
mcp__Desktop_Commander__start_process(
  command="WORKSPACE=<workspace> bash ~/.cache/ccbridge/start_watchdog.sh"
)
```

**Path B / C:** display command, ask user to run it. With Path B, follow up with `read.sh` polling via DC if available; otherwise polling-by-screenshot.

### Step 5 — Verify the bridge is alive

```
mcp__Desktop_Commander__start_process(command="bash ~/.cache/ccbridge/diagnose.sh <workspace>")
```
Or, for Path C, ask user to run diagnose.sh and paste output.

## Per-action mapping (during a run)

| Action | Path A | Path B | Path C |
|---|---|---|---|
| Write directive | Use `Write` tool on the mounted workspace dir (works regardless of path) | same | same |
| Send trigger to CC | `Desktop_Commander__start_process` → `echo '...' \| ~/.cache/ccbridge/send.sh` | screenshot Terminal, ask user to run `echo` cmd | display cmd, user runs it |
| Read terminal | DC → `~/.cache/ccbridge/read.sh` | `computer-use__screenshot` + visual inspection | ask user to paste recent output |
| Approve a prompt | watchdog handles automatically (if started) | watchdog (if started) | user approves manually |
| Interrupt hung CC | DC → `keys.sh esc` | `computer-use__key` (tier-click — `key` may be allowed; verify with `request_access`) | tell user "press Esc" |
| Run unit tests | DC → `start_process` with the test command | display cmd, ask user | display cmd, ask user |
| Drive Claude in Chrome (browser-test) | `mcp__Claude_in_Chrome__*` directly — separate MCP, not the host driver | same | same |
| Read git log | DC → `git log` on host workspace, OR sandbox bash on mounted dir (both work for read) | same | same |
| Commit `docs/e2e-testing/*` | Cowork's `Write` to mounted dir, then DC → `git add && git commit` | same with user running git | user runs git |

## Tier-click reality (computer-use + Terminal)

If you fall to Path B and try to `mcp__computer-use__type` while Terminal is frontmost, you'll get an error:

```
ToolError: Terminal is tier "click" — typing, key presses, right-click,
modifier-clicks, and drag-drop are blocked. Use bash for shell commands.
```

What this means in practice:
- `left_click` on a button → ✓ allowed
- `key` for plain Enter → may be allowed (verify with request_access response)
- `type "anything"` → ✗ blocked
- Drag-drop a file onto Terminal → ✗ blocked

Workarounds inside Path B:
- For one-line commands: write to a file in a mounted dir, instruct user to copy-paste manually
- For multi-line: file-based directive pattern (already used by send.sh) is doubly valuable here

The Path A flow (`Desktop_Commander`) **does not have this restriction** because it executes shell commands directly, not via the GUI.

## request_access flow (computer-use only)

Before any `computer-use` call:

1. `mcp__computer-use__request_access(applications=["Terminal"])`
2. User sees a permission dialog naming the app.
3. The response includes the granted tier (`read`, `click`, `full`).
4. Plan tool calls based on the tier:
   - `read` → screenshot only (browsers default to this)
   - `click` → screenshot + clicks (Terminal lives here)
   - `full` → screenshot + clicks + typing + everything (most native apps)
5. If your task needs a tool not available at the granted tier → ask the user to re-grant at the needed tier, OR switch paths.

## Watchdog lifecycle by path

The watchdog (`watchdog.sh`) is a long-running background loop on the user's Mac that auto-approves CC permission prompts. It MUST run on the host.

**Path A:** `Desktop_Commander__start_process` with `nohup ... &` — the process persists after the tool call returns. You can check on it later with `Desktop_Commander__list_processes`.

**Path B:** spawn it via osascript that the user runs once. Cowork can poll via `read.sh` over Desktop_Commander or visually via screenshots.

**Path C:** user runs it manually; Cowork polls via "ask the user to paste recent output."

## Failure modes by path

| Symptom | Path A likely cause | Path B likely cause | Path C likely cause |
|---|---|---|---|
| Send didn't land | DC daemon not running on host | computer-use lost Terminal focus | user typed something else mid-paste |
| Watchdog silent | watchdog process died — restart via DC | watchdog never started | user forgot to start it |
| Can't read terminal | DC process call timed out | screenshot didn't capture latest scrollback | user pasted stale output |
| Auth/permission denied | DC daemon needs re-auth on host | request_access dialog not approved | n/a |

## What the SKILL.md pre-flight should do

This is THE step that has to happen before anything else:

```
Step 0: Substrate detection
  - Probe for Desktop_Commander, computer-use, Claude_in_Chrome
  - If Desktop_Commander present → Path A; install bridge via DC; start watchdog via DC
  - Else if computer-use present → Path B; request_access for Terminal;
    fall back to user-driven install (Path C subset)
  - Else → Path C; surface required commands to user, wait for confirmation
  - Record chosen path in <workspace>/.cc/state.json as event substrate_chosen path=<A|B|C>
```

Then proceed to existing pre-flight (read STATUS.md, etc.).

## Don't

- **Don't assume bash + osascript works.** Cowork's bash is Linux. Always go via Desktop_Commander (or fall back) for any command that needs to run on the Mac.
- **Don't skip request_access for computer-use.** The first computer-use call will be denied otherwise.
- **Don't try to `type` into Terminal via computer-use.** It's tier-click. Use a shelled-out osascript via Desktop_Commander, or fall to Path C.
- **Don't run two watchdogs.** The driver lock prevents this on the host side, but Path B/C runs may not set `WORKSPACE` — risk of duplicate.
- **Don't proceed to phase 1 without confirming the bridge is alive via diagnose.sh.** This is the only honest "go" signal.
