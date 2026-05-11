# Loop mechanics

Concrete how-to for the experiment loop itself. The shared driver is
`scripts/run_autoresearch.sh`; this doc explains its internals so you can
debug, extend, or build a custom driver in v4.2.

## The proposer

The autoresearch loop needs an agent to propose the next mutation. There
are two modes. The dispatcher (`propose_hypothesis.sh`) handles the
selection; loop drivers and commands don't need to know which mode is
active — they always call the dispatcher.

### Mode 1 — File-based (default without API key)

- `propose_via_file.sh` writes `.proposed_prompt.txt` and blocks waiting
  for `.proposed_target.txt`.
- Cowork (or Claude Code) reads the prompt, generates a proposed mutation,
  writes the target file (the full new content of the target — no diff,
  no preamble).
- The proposer reads it, emits the content on stdout, deletes both
  scratch files, exits 0.
- Pattern matches sd-claude-code-access's file-based directive pattern.
- Best for: interactive use during a Cowork session, when no API key is
  available, or when you want a human in the loop.

Tunables (env vars):

- `PROPOSER_FILE_TIMEOUT` — seconds to wait for `.proposed_target.txt`.
  Default 5 (short so unattended `run_autoresearch.sh --once` doesn't
  hang). Interactive Cowork sessions should set this to several minutes
  (e.g. `export PROPOSER_FILE_TIMEOUT=600`).
- `PROPOSER_FILE_POLL_SEC` — poll interval in seconds. Default 5.

### Mode 2 — API-based (default with `ANTHROPIC_API_KEY`)

- `propose_via_api.sh` constructs a prompt (system + user) and curls
  `https://api.anthropic.com/v1/messages` directly with the
  `claude-sonnet-4-6` model.
- Parses `content[0].text` and emits the proposed target content to
  stdout.
- Fully autonomous — no human/Cowork in the loop.
- Best for: overnight runs, CI, multi-skill swarms.

Exit codes (from `propose_via_api.sh`):

- `0` — success.
- `2` — missing key OR HTTP 401/403 auth failure.
- `3` — HTTP 429 rate-limit.
- `4` — HTTP 5xx server error or unreachable.
- `1` — generic error (bad args, parse failure, etc.).

Tunables (env vars):

- `ANTHROPIC_API_KEY` (required).
- `ANTHROPIC_MODEL` (default `claude-sonnet-4-6`).
- `ANTHROPIC_API_URL` (default the production endpoint — override for
  proxies or local replays).
- `ANTHROPIC_MAX_TOKENS` (default 4096).

### Selecting the mode

Priority order (first match wins):

1. `<skill>/autoresearch/config.json` → `"proposer_mode": "file" | "api"`.
2. `PROPOSER_MODE` env var.
3. Autodetect — `ANTHROPIC_API_KEY` set ⇒ `"api"`, else `"file"`.

Example `config.json`:

```json
{ "proposer_mode": "file" }
```

## Time-boxing an experiment

Each `score.sh` call is wrapped in a timeout. Bash 3.2 (macOS default)
has no built-in `timeout` command, so we use a portable pattern:

```bash
run_with_timeout() {
  local secs="$1"; shift
  ( "$@" ) &
  local pid=$!
  ( sleep "$secs" && kill -TERM "$pid" 2>/dev/null && \
    sleep 2 && kill -KILL "$pid" 2>/dev/null ) &
  local watcher=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill -TERM "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return $rc
}

# Usage
run_with_timeout 300 bash autoresearch/score.sh "$SKILL_DIR"
```

Experiments that exceed `--time SEC` get a non-zero exit code and are
treated as rejected (score = `-inf` for comparison purposes, but
`.baselines.json` records `accepted=false, reason=timeout`).

## Capturing the score

`score.sh` writes its output to a temp file; the driver reads the LAST
non-empty line and parses it as a float. Anything else is treated as a
parse failure (rejected). This lets scoring scripts emit verbose
debug info to stdout without breaking the protocol — but the last line
must be the score.

```bash
SCORE_OUT="$(mktemp)"
run_with_timeout "$TIME_BUDGET" bash autoresearch/score.sh "$SKILL_DIR" \
  > "$SCORE_OUT" 2>&1
rc=$?

if [ "$rc" -ne 0 ]; then
  # rejected: timeout or scorer crash
  ...
fi

# Last non-empty line, parsed as float
score_line="$(grep -v '^[[:space:]]*$' "$SCORE_OUT" | tail -1)"
if ! echo "$score_line" | grep -Eq '^-?[0-9]+(\.[0-9]+)?$'; then
  # rejected: unparseable score
  ...
fi
score="$score_line"
```

## Git commit semantics

The driver uses a per-iteration accept/reject pattern that keeps the git
history readable.

**Accept** (score improved):

```bash
git add -- "$TARGET_FILE"
git commit -m "experiment: score=$SCORE on $SKILL target=$TARGET"
# baseline is now $SCORE; next iteration compares against this
```

**Reject** (score worse or equal):

```bash
git checkout -- "$TARGET_FILE"
# target reverts to last committed state; baseline unchanged
```

The baseline is **the last accepted score**, not the score from the
previous iteration. This means a string of rejections doesn't lower the
bar — only an explicit human reset of `.baselines.json` does.

### Why not `git stash`?

We considered `git stash --keep-index` for atomicity, but it leaves the
working tree in a confused state if the loop is interrupted. Plain
`git checkout -- <file>` is simpler and the lock file handles
interruption safely.

## Baseline management

`.baselines.json` (JSONL — one JSON object per line) lives at
`<skill>/autoresearch/.baselines.json`. Format:

```jsonl
{"ts":"2026-05-11T03:14:00Z","target_hash":"a1b2c3d4","score":74.31,"accepted":true,"baseline_before":72.10,"reason":"improved"}
{"ts":"2026-05-11T03:19:12Z","target_hash":"e5f6a7b8","score":73.88,"accepted":false,"baseline_before":74.31,"reason":"worse"}
{"ts":"2026-05-11T03:24:30Z","target_hash":"c9d0e1f2","score":0.00,"accepted":false,"baseline_before":74.31,"reason":"timeout"}
```

Fields:

- `ts` — ISO-8601 UTC timestamp.
- `target_hash` — `git hash-object` of the candidate before scoring (lets
  you reproduce any historical candidate).
- `score` — the float emitted by `score.sh` (or 0.0 for rejections that
  failed to produce a parseable score).
- `accepted` — true if committed, false if reverted.
- `baseline_before` — the baseline at the start of the iteration.
- `reason` — `improved`, `worse`, `equal`, `timeout`, `parse_failure`,
  `validator_rejected`, `crash`.

The driver appends after every iteration. Never rewrite the file mid-run.

### Reading baselines

The agent (or a `--status` command) reads `.baselines.json` to see what's
been tried. Useful queries:

```bash
# Current baseline (last accepted score)
tail -100 .baselines.json | python3 -c '
import sys, json
last = None
for line in sys.stdin:
    o = json.loads(line)
    if o.get("accepted"): last = o
print(last["score"] if last else "no baseline")
'

# Top 5 candidates by score
sort -t: -k4 -nr .baselines.json | head -5

# Rejection reason histogram
python3 -c '
import json, sys, collections
c = collections.Counter()
for line in open(".baselines.json"):
    o = json.loads(line)
    if not o.get("accepted"): c[o.get("reason","unknown")] += 1
for k,v in c.most_common(): print(f"{v:4d} {k}")
'
```

## Lock file (single-driver-per-skill)

`<skill>/autoresearch/.lock` is acquired at run start, released on
clean exit. Format:

```
pid=12345
host=mbp.local
start=2026-05-11T03:00:00Z
budget=50
time=300
```

Acquire:

```bash
LOCK="$SKILL_DIR/autoresearch/.lock"
if [ -f "$LOCK" ]; then
  pid="$(awk -F= '/^pid=/{print $2}' "$LOCK")"
  if kill -0 "$pid" 2>/dev/null; then
    echo "lock held by pid=$pid; refuse to start" >&2
    exit 2
  fi
  # stale: clean up
  rm "$LOCK"
fi
cat > "$LOCK" <<EOF
pid=$$
host=$(hostname)
start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
budget=$BUDGET
time=$TIME_BUDGET
EOF

trap 'rm -f "$LOCK"' EXIT
```

## Parallelism — running on multiple skills

Two valid patterns:

1. **Serial**: run autoresearch on one skill at a time. Same git tree.
   Simplest; commits interleave cleanly because they're sequential.
2. **Parallel via worktrees**: `git worktree add ../skill-A` per skill,
   one driver per worktree. Each worktree has its own lock,
   `.baselines.json`, and HEAD. At end of run, cherry-pick the winning
   commits back to main.

**Do not** run two drivers on the same git tree against different
skills — commits will interleave and invalidate baselines.

## Resume after interruption

If `run_autoresearch.sh` is Ctrl-C'd or SIGTERM'd mid-iteration:

1. The signal handler reverts any uncommitted candidate
   (`git checkout -- $TARGET_FILE`) and releases the lock.
2. `.baselines.json` is intact — only fully-completed iterations are
   recorded.
3. Re-running `run_autoresearch.sh <skill>` picks up: re-reads the lock
   (cleared), re-baselines from the last accepted commit, continues
   experimenting toward `--budget`.

If interrupted by SIGKILL or OOM (no signal handler runs):

1. The lock file remains, holding a dead pid.
2. Manual cleanup: `cat .lock` → verify pid is dead → `rm .lock`.
3. The working tree may have an uncommitted edit to the target file →
   `git status` reveals it → `git checkout -- $TARGET_FILE` to restore.
4. Resume normally.
