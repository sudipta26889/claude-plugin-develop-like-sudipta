# SSH-bridge variant — when Cowork and CC are on different machines

> This is **Path D** in the substrate-detection ladder — see [`references/substrate_and_access.md`](substrate_and_access.md) for the probe (`scripts/ssh_probe.sh`) + selection flow + per-action mapping. This document covers the two SSH-specific implementation variants (interactive TUI vs headless `claude -p -c`).

If Cowork's sandbox runs on machine A and CC runs on machine B (e.g., Cowork on a MacBook Air, CC on a workstation accessed via SSH), the local-Terminal bridge doesn't apply directly. There are two viable substitutes.

## Substrate detection

```bash
uname -n                              # this is THIS machine (where Cowork's bash runs)
osascript -e 'tell application "Terminal" to return name of selected tab of front window'
# If the tab title says "ssh some-other-machine" but bash is local,
# you've got a cross-machine setup.
```

If Cowork's bash is on machine A and the user's CC session is *displayed* in a Terminal window on A but actually *running* on B (because of an SSH session), the existing local-Terminal bridge in `send.sh` STILL works — you're driving Terminal.app on A, and Terminal forwards keystrokes through the SSH stream to CC on B. This is the most common case and was the case in the original session that produced this skill.

The SSH-bridge variant below is only needed if Cowork itself runs on a different machine and there's no local Terminal showing CC.

## Variant A — SSH headless invocations

Each turn becomes a `claude -p -c "<message>"` invocation on the remote machine:

```bash
ssh user@host \
  'cd /path/to/workspace && /Users/user/.local/bin/claude --continue --print \
     --output-format stream-json --include-partial-messages \
     "<your message>"'
```

Properties:

- `--continue` (`-c`) resumes the existing session in the workspace dir
- `--print` (`-p`) is non-interactive; CC processes the message, prints the response, exits
- Each invocation is a fresh process; the conversation is durable in `~/.claude/projects/<encoded>/<session>.jsonl`

Trade-offs:

- ✅ Same conversation continues across invocations (via `--continue`)
- ✅ No paste mechanics, no clipboard, no AppleScript — pure SSH
- ❌ User must EXIT their interactive CC first, otherwise file locking conflicts
- ❌ No live token streaming feel for the user — they only see what Cowork relays back
- ❌ Cowork has to parse the JSONL output

## Variant B — Tmux on the remote machine

If you have or can install `tmux` on the remote:

```bash
ssh user@host 'tmux new-session -d -s cc "claude --continue"'
# then to send keys:
ssh user@host "tmux send-keys -t cc '<message>' Enter"
# and to capture:
ssh user@host 'tmux capture-pane -t cc -p'
```

Properties:

- ✅ The CC session stays interactive on the remote, like the local Terminal case
- ✅ User can `tmux attach -t cc` from any machine to watch
- ❌ Requires tmux installed on remote (often not the case on a Mac)
- ❌ Two-step send (send-keys for body, send-keys Enter to submit)
- ❌ tmux's send-keys handles multi-line text awkwardly; consider writing message to a remote file first then `tmux send-keys -t cc 'cat /tmp/msg.md | pbpaste-equivalent'`

## When local-Terminal bridge still applies cross-machine

If the user has Terminal.app open on their local Mac with an SSH session inside it to CC running remotely:

- Cowork is local
- Terminal.app is local
- The SSH connection inside Terminal forwards keystrokes to remote CC

Then the bundled `send.sh` works unmodified. You're driving the local Terminal, which carries your keystrokes via the SSH transport. This was the actual setup in the run that produced this skill: Cowork on M4 Air, Terminal on M4 Air, SSH from M4→M1, CC on M1.

## Hybrid: bridge for input, headless for verification

A hybrid that has worked well: use the local-Terminal bridge for sending (because CC's interactive TUI is what the user sees), but also `ssh remote 'cat ~/.claude/projects/<encoded>/<session>.jsonl | tail -50'` to read CC's actual conversation log when paste verification is in doubt. The JSONL is more authoritative than the TUI display.

## Picking a variant

| Setup | Recommendation |
|---|---|
| Cowork local, CC local in Terminal.app | Local-Terminal bridge (default) |
| Cowork local, CC remote, user's local Terminal SSH'd to CC | Local-Terminal bridge — keystrokes traverse SSH |
| Cowork local, CC remote, no local Terminal showing CC | SSH headless (`claude -p -c`) — cleanest |
| Cowork remote, CC remote, both on the same machine | Local-Terminal bridge if Cowork's bash can reach the remote's Terminal (unlikely); else SSH headless |
| Anything else | Tell the user "Cowork's CC bridge needs Terminal.app or SSH access — I can't proceed without one" |
