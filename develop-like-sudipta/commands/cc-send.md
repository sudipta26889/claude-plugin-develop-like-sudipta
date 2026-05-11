---
description: Relay a single message to a running Claude Code session — no watchdog, no audit, just keyboard bridge
argument-hint: <message-or-path-to-md-file>
---

Send a message to the user's running Claude Code session — one-shot, no orchestration.

**Invoke the `sd-claude-code-access` skill** for the `send.sh` and `read.sh` bridge scripts. If the bridge isn't installed, install it first (`bash <plugin-skill-path>/scripts/install.sh`).

## Procedure

0. **Substrate detection.** Probe MCPs (Desktop_Commander → Path A preferred; computer-use → Path B with `request_access` for Terminal; else Path C). Brief the user on the chosen path.
1. **Inspect `$ARGUMENTS`** — is it a short string, a long markdown block, or a path to a file?
2. **For short messages (≤3 sentences):**
   - **Path A:** `mcp__Desktop_Commander__start_process(command="echo '$ARGUMENTS' | ~/.cache/ccbridge/send.sh")`
   - **Path B/C:** display the command for the user to run:
     ```bash
     echo "$ARGUMENTS" | ~/.cache/ccbridge/send.sh
     ```
3. **For long content (multi-paragraph, code blocks, lists):**
   - Ask the user for the workspace path if not in context.
   - Write to `<workspace>/.cc/oneshot.md` using Cowork's `Write` tool (works on mounted dir regardless of path).
   - Path A: `mcp__Desktop_Commander__start_process(command="echo 'Read \\\`.cc/oneshot.md\\\` and apply it.' | ~/.cache/ccbridge/send.sh")`
   - Path B/C: display the send command for the user.
4. **For a path:** read the file, follow the long-content path above (workspace-relative).
5. **Verify the paste landed** — `send.sh` already does middle-fragment grep; report its exit code.
6. **Poll the response** for ~30s:
   ```bash
   for i in 1 2 3 4 5; do sleep 6; ~/.cache/ccbridge/read.sh | tail -20; done
   ```
7. **Summarize what came back** to the user.
8. **Report the token-upload counter** if visible in the buffer (helps user know CC is still alive).

## Don't

- Don't run the watchdog or audit. This is a deliberate one-shot.
- Don't paste long markdown directly. Use the file pattern.
- Don't loop. This command is single-shot by design — if the user wants iteration, use `/cc-drive`.
