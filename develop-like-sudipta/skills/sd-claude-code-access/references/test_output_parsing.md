# Structured test-output parsing

## Why this exists

`assets/bug_report_template.md` has a "Captured evidence" section with
fields that need to be filled accurately:

- **Failing assertion / test name** with line number
- **Expected vs actual**
- **Files implicated** (resolved to repo-relative paths)
- **Stack trace** (verbatim)

But pytest, jest, vitest, cargo, `go test`, and `mvn test` each print
output in their own format. Grepping heuristically across all of them
gives unreliable extractions — wrong line numbers, missing assertions,
or worst of all, fabricated fields when the regex picks up unrelated
text.

`scripts/parse_test_output.py` solves this. It detects the runner
from output signatures, applies a runner-specific extractor, and emits
one normalized JSON document. The Cowork agent then maps those fields
1:1 into the bug-report template — no guessing.

## Invocation

```bash
# Pipe raw output (most common, paired with the failing command):
$ pytest tests/ 2>&1 | tee raw.txt | python3 scripts/parse_test_output.py > parsed.json

# Or pass a file path:
$ python3 scripts/parse_test_output.py raw.txt > parsed.json

# Force a runner if auto-detection picks the wrong one:
$ python3 scripts/parse_test_output.py --runner pytest < raw.txt

# Optionally record the original test command's exit code:
$ python3 scripts/parse_test_output.py --exit-code 1 < raw.txt
```

The parser exits **0** on any successful parse, including when no
runner is detected and when the runner shows failures. The intent is
that the calling shell pipeline can always continue; the *caller*
inspects `summary.failed` and `failures` to decide what to do.

## JSON schema

```json
{
  "runner": "pytest",
  "exit_code": 1,
  "summary": {"passed": 12, "failed": 3, "skipped": 1, "errors": 0},
  "failures": [
    {
      "test": "tests/unit/test_cart.py::test_total_includes_tax",
      "file": "tests/unit/test_cart.py",
      "line": 42,
      "assertion": "assert total == Decimal('11.00')",
      "expected": "Decimal('11.00')",
      "actual": "Decimal('10.00')",
      "traceback": "...verbatim block from FAILURES section..."
    }
  ]
}
```

Field semantics:

| Field | Meaning | When `null` |
|---|---|---|
| `runner` | Detected runner name, or `null` if no signature matched | Output didn't look like any supported runner |
| `exit_code` | Echoed from `--exit-code N`, else `null` | Caller didn't pass `--exit-code` |
| `summary.passed/failed/skipped/errors` | Counts from the runner's own summary line | Defaults to 0 if the summary couldn't be parsed |
| `failures[].test` | Full test identifier as the runner prints it | Should always be set if there's a failure entry |
| `failures[].file` | File path from the failure location (often a test file, sometimes source) | Stack trace was absent or unparseable |
| `failures[].line` | 1-based line number from the failure location | Same as `file` |
| `failures[].assertion` | The asserting line of code, verbatim | Runner didn't print a pointer line |
| `failures[].expected` | Expected value as a string (quoted as the runner displays it) | No "expected vs actual" pattern matched |
| `failures[].actual` | Actual value | Same as `expected` |
| `failures[].traceback` | Verbatim block, including stack/diff/output | No failure block matched the test name |

**Important:** the parser NEVER fabricates fields. If it can't extract
something, the value is `null`. Empty strings are not used to mean
"missing".

## Supported runners

| Runner | Detection pattern (any of) | Known limitations |
|---|---|---|
| `pytest` | `========== test session starts ==========` header; `^FAILED ` lines in short summary | If pytest is run with `--no-header` AND `-q` AND `--no-summary`, detection may miss. Forcing `--runner pytest` works. |
| `jest` | `PASS`/`FAIL` file-marker lines; `^Test Suites:` summary | `failures[].file/line` come from the stack trace at the bottom of the bullet block. If the stack is filtered (e.g. `--silent`), they may be `null`. |
| `vitest` | `^ RUN  v<digit>` header; `❯` markers | Diff format depends on Vitest version — both `- Expected/+ Received` and `expected 'x' to be 'y'` forms are handled. |
| `cargo` | `running N tests` and `^test result: (FAILED\|ok)\.` lines | Only handles `assertion left == right` panic-style failures cleanly; arbitrary panic messages still set `file`/`line` but leave `expected`/`actual` `null`. |
| `go` | `^--- FAIL: TestName (Xs)` lines; `^FAIL\t<package>` footer | `t.Errorf("got %v, want %v", ...)` idiom is parsed; structured `testify` assertions populate `assertion` but may leave `expected`/`actual` `null`. |
| `maven` | `maven-surefire-plugin` banner; `Tests run: N, Failures: M, Errors: E` line | Picks up the **final** aggregate line, so per-module rollups should still be correct. Errors (vs failures) are counted in `summary.errors` separately. |

## Failure mode

If the parser exits 0 with `{"runner": null, "failures": []}` **or** with
`failures: []` despite the original test command returning non-zero, the
output format isn't recognized (or has changed). The caller should
treat this as a **parse failure** and fall back to manual capture per
`references/bug_driven_tdd.md` step 1 — copy the raw last-200-lines
verbatim into the bug report and extract assertion/file/line by hand.

A non-empty `summary.failed` count combined with an empty `failures`
list is also a red flag: the runner was detected, the summary was
read, but per-failure extraction missed. Same fallback applies.

## Mapping to the bug report

The JSON maps 1:1 into `assets/bug_report_template.md` → "Captured
evidence":

| JSON field | Template field |
|---|---|
| `failures[0].test` + `failures[0].line` | "Failing assertion / test name — line `<NN>`" |
| `failures[0].assertion` | "assertion text with expected vs actual" |
| `failures[0].expected`, `.actual` | inline in the above line |
| `failures[0].file` | First entry under "Files implicated" |
| `failures[0].traceback` | "Stack trace (if present)" code block |
| Raw piped stdout+stderr | "Last 200 lines of stdout+stderr" code block |

If there are multiple failures, the bug report should still focus on
**one** bug (one symptom). Use `failures[0]` for the primary capture
and reference the rest in "Notes" if they're causally linked.

## Extending the parser

To add a new runner (say, `phpunit`):

1. **Pick a detection signature.** Find a line that every run of the
   new runner emits and that no other runner emits. Add it to
   `detect_runner()` in `scripts/parse_test_output.py`. Put more
   specific patterns first to avoid clashes.

2. **Write the extractor.** Add `parse_phpunit(text: str) -> dict`
   following the existing pattern: regex out the summary line, then
   regex out each failure block, populate one `_make_failure()` dict
   per failure. Leave any field `None` if you can't extract it cleanly
   — don't guess.

3. **Register it.** Add `"phpunit": parse_phpunit` to the `RUNNERS`
   dict near the bottom of the script.

4. **Add a fixture.** Drop a realistic raw-output sample into
   `evals/fixtures/phpunit_<N>_failures.txt`. Hand-write from a real
   run; don't synthesize.

5. **Extend the smoke test.** Add `phpunit_<N>_failures.txt|phpunit|<N>`
   to the `CASES` array in `evals/test_parse_test_output.sh`.

6. **Run it:** `bash evals/test_parse_test_output.sh`. All cases must
   pass.

## Determinism

The parser is pure-Python stdlib, deterministic on identical input,
and has no network or filesystem side effects beyond reading the input
file (when a path is given). It's safe to run in CI and on pre-commit
hooks.
