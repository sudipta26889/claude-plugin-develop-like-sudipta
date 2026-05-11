# iTerm2 support

The bridge defaults to macOS Terminal.app but supports iTerm2 via the `TERMINAL_APP` env var.

## Quick start

Set the env var before any bridge command:

```bash
export TERMINAL_APP=iTerm2
bash ~/.cache/ccbridge/start_watchdog.sh
echo "hello CC" | ~/.cache/ccbridge/send.sh
```

Or per-invocation:

```bash
TERMINAL_APP=iTerm2 ~/.cache/ccbridge/read.sh
```

## What changes between Terminal.app and iTerm2

| Aspect | Terminal.app | iTerm2 |
|---|---|---|
| App name in `tell application` | `Terminal` | `iTerm2` (sometimes `iTerm`) |
| Buffer accessor | `contents of selected tab of front window` | `contents of current session of current window` |
| Scrollback accessor | `history of selected tab of front window` | NOT EXPOSED — falls back to `contents` |
| `key code 51` (Backspace) | works | works |
| `keystroke "a" using {command down}` (Cmd+A) | works | works |
| Activate semantics | `tell application "Terminal" to activate` | `tell application "iTerm2" to activate` |
| Multi-window/multi-tab | `front window` + `selected tab` | `current window` + `current session` |

The bundled `keys.sh`, `read.sh`, and `read_history.sh` already branch on `$TERMINAL_APP` and use the correct AppleScript dialect. `send.sh` uses `$TERMINAL_APP` for the activate call. Everything else (Cmd+V, Return) is OS-level via System Events and works the same.

## Known limitations on iTerm2

1. **No `history of` equivalent.** iTerm2's AppleScript dictionary doesn't expose full scrollback; `read_history.sh` falls back to `contents`, which is the visible buffer + a small ring buffer. If your paste verification fragment scrolled past the buffer, you'll get a false-fail. Mitigations:
   - Use shorter messages
   - Read more aggressively after send (`sleep 1` then read instead of waiting 4s)
   - Trust `read.sh` over `read_history.sh` on iTerm

2. **`current session of current window` semantics.** iTerm's "current session" is whichever pane is focused. If you have split panes, the keystrokes go to whichever pane has focus, NOT necessarily the one you're reading from. Use single-pane sessions for the bridge.

3. **iTerm2 nightly vs stable.** Some AppleScript surface changes between iTerm2 versions (e.g. Build 3.5+ vs 3.4). The bridge has been tested on 3.5; older versions may need `iTerm` (no "2") in the `tell` block.

## Switching mid-session

If you started with Terminal.app and want to switch to iTerm2:

1. Stop the watchdog: `bash ~/.cache/ccbridge/stop_watchdog.sh`
2. Export `TERMINAL_APP=iTerm2`
3. Start a new CC session in iTerm2
4. Restart the watchdog: `bash ~/.cache/ccbridge/start_watchdog.sh`

The watchdog reads `$TERMINAL_APP` at start time, so each new instance picks up the current value. Don't change the env var while the watchdog is running — it'll continue using whatever value it started with.

## Other terminals

- **Ghostty**: untested. Has minimal AppleScript surface as of this writing. Likely needs `tell application "Ghostty"` + `frontmost` + `keystroke` (no buffer accessor at all). The bridge's read functions will fail; you'd need to remove the verification step.
- **Warp**: untested. Heavier UI but more AppleScript-friendly than Ghostty. Try `TERMINAL_APP=Warp` and see what works.
- **Kitty**: cross-platform, no AppleScript dictionary. Use the SSH-headless variant (see `ssh_variant.md`) — drives `claude -p -c` directly without a TUI.
