#!/usr/bin/env python3
"""parse_test_output.py — structured extraction of test-runner output.

Reads raw test-runner output from stdin or a file path, auto-detects the
runner (pytest / jest / vitest / cargo / go / maven), and emits a normalized
JSON document on stdout describing the run.

Usage:
    parse_test_output.py < raw_output.txt
    parse_test_output.py raw_output.txt
    parse_test_output.py --runner pytest < raw_output.txt

Exit code:
    0 — parsing succeeded (even if the input shows failing tests, OR if no
        runner could be detected; in the latter case the JSON will contain
        empty `failures` and the caller should fall back to manual capture).
    2 — invalid invocation (bad --runner value, can't read file).

The JSON schema is documented in references/test_output_parsing.md.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Callable, Optional


# ---------------------------------------------------------------------------
# Runner detection
# ---------------------------------------------------------------------------

def detect_runner(text: str) -> Optional[str]:
    """Return the runner name, or None if no signature matches."""
    # Order matters: more specific patterns first.
    if re.search(r"=+ test session starts =+", text) or re.search(
        r"^FAILED ", text, re.MULTILINE
    ):
        return "pytest"
    if re.search(r"^ RUN  v\d", text, re.MULTILINE) or "❯" in text:
        return "vitest"
    if re.search(r"^(PASS|FAIL)\s+\S+\.(test|spec)\.", text, re.MULTILINE) or re.search(
        r"^Test Suites:", text, re.MULTILINE
    ):
        return "jest"
    if re.search(r"^test result: (FAILED|ok)\.", text, re.MULTILINE) or re.search(
        r"^running \d+ tests?$", text, re.MULTILINE
    ):
        return "cargo"
    if re.search(r"^--- (FAIL|PASS): \w+", text, re.MULTILINE) or re.search(
        r"^FAIL\s+\S+", text, re.MULTILINE
    ):
        return "go"
    if re.search(r"maven-surefire-plugin", text) or re.search(
        r"^\[(INFO|ERROR)\] Tests run: \d+, Failures: \d+", text, re.MULTILINE
    ):
        return "maven"
    return None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _empty_summary() -> dict:
    return {"passed": 0, "failed": 0, "skipped": 0, "errors": 0}


def _make_failure(test: Optional[str] = None) -> dict:
    return {
        "test": test,
        "file": None,
        "line": None,
        "assertion": None,
        "expected": None,
        "actual": None,
        "traceback": None,
    }


# ---------------------------------------------------------------------------
# pytest
# ---------------------------------------------------------------------------

PYTEST_SUMMARY_RE = re.compile(
    r"=+\s*(?:(\d+)\s+failed)?,?\s*(?:(\d+)\s+passed)?,?\s*"
    r"(?:(\d+)\s+skipped)?,?\s*(?:(\d+)\s+errors?)?",
)

PYTEST_FAILED_LINE_RE = re.compile(
    r"^FAILED\s+(?P<test>\S+)(?:\s+-\s+(?P<msg>.+))?$",
    re.MULTILINE,
)

PYTEST_ASSERT_RE = re.compile(r"AssertionError: assert\s+(.+?)\s+==\s+(.+?)$")


def parse_pytest(text: str) -> dict:
    summary = _empty_summary()
    # The "short test summary" / final stats line.
    # Look for the FINAL summary line first (it can repeat).
    final = re.search(
        r"=+\s+(?P<body>[^=]+?)\s+in\s+[\d.]+s\s*=+\s*$",
        text,
        re.MULTILINE,
    )
    if final:
        body = final.group("body")
        for n, kind in re.findall(r"(\d+)\s+(passed|failed|skipped|errors?|error)", body):
            kind = "errors" if kind.startswith("error") else kind
            summary[kind] = summary.get(kind, 0) + int(n)

    # Fallback: scan for any summary-looking line.
    if sum(summary.values()) == 0:
        for n, kind in re.findall(
            r"(\d+)\s+(passed|failed|skipped|errors?|error)", text
        ):
            kind = "errors" if kind.startswith("error") else kind
            summary[kind] += int(n)

    # Collect failure test ids from the short summary block.
    failures = []
    seen_tests = set()
    for m in PYTEST_FAILED_LINE_RE.finditer(text):
        test_id = m.group("test")
        if test_id in seen_tests:
            continue
        seen_tests.add(test_id)
        f = _make_failure(test=test_id)
        # Try to find the failure traceback block in the FAILURES section.
        # Test IDs look like path/to/test.py::test_name — the section header
        # uses just the bare test name padded by underscores.
        bare_name = test_id.split("::")[-1]
        block = _pytest_failure_block(text, bare_name)
        if block:
            f["traceback"] = block.strip()
            # Try to extract assertion line ("> assert ...").
            assert_m = re.search(r"^>\s+(.*)$", block, re.MULTILINE)
            if assert_m:
                f["assertion"] = assert_m.group(1).strip()
            # File:line — look for "path/to/test.py:NN: AssertionError" or
            # "path/to/file.py:NN: in funcname".
            loc = re.search(
                r"^(?P<file>[^\s:]+?):(?P<line>\d+):\s*(?:AssertionError|in\s+\w+|\w+Error)",
                block,
                re.MULTILINE,
            )
            if loc:
                f["file"] = loc.group("file")
                f["line"] = int(loc.group("line"))
            # Expected vs actual from "assert X == Y".
            ea = re.search(
                r"AssertionError: assert\s+(?P<actual>.+?)\s+==\s+(?P<expected>.+)$",
                block,
                re.MULTILINE,
            )
            if ea:
                f["actual"] = ea.group("actual").strip()
                f["expected"] = ea.group("expected").strip()
        failures.append(f)

    return {"runner": "pytest", "summary": summary, "failures": failures}


def _pytest_failure_block(text: str, bare_name: str) -> Optional[str]:
    """Return the block of text under the FAILURES section for `bare_name`."""
    # Header looks like "______ test_total_includes_tax ______".
    pattern = re.compile(
        rf"^_+\s+{re.escape(bare_name)}\s+_+\s*$",
        re.MULTILINE,
    )
    m = pattern.search(text)
    if not m:
        return None
    start = m.end()
    # End is the next header line of underscores or the short summary divider.
    end_m = re.search(
        r"^(?:_+\s+\w+\s+_+|=+\s*short test summary|=+\s*\d+\s+(?:failed|passed))",
        text[start:],
        re.MULTILINE,
    )
    end = start + end_m.start() if end_m else len(text)
    return text[start:end]


# ---------------------------------------------------------------------------
# jest
# ---------------------------------------------------------------------------

JEST_TESTS_LINE_RE = re.compile(
    r"^Tests:\s+(?:(\d+)\s+failed,\s*)?(?:(\d+)\s+skipped,\s*)?"
    r"(?:(\d+)\s+passed,\s*)?(\d+)\s+total",
    re.MULTILINE,
)

JEST_BULLET_RE = re.compile(r"^\s*●\s+(?P<test>.+?)\s*$", re.MULTILINE)


def parse_jest(text: str) -> dict:
    summary = _empty_summary()
    m = JEST_TESTS_LINE_RE.search(text)
    if m:
        failed, skipped, passed, _total = m.groups()
        summary["failed"] = int(failed or 0)
        summary["skipped"] = int(skipped or 0)
        summary["passed"] = int(passed or 0)

    failures = []
    # Each "● <test>" introduces a failure block. The text between successive
    # bullets (or between the last bullet and the summary) is the body.
    bullets = list(JEST_BULLET_RE.finditer(text))
    for i, bm in enumerate(bullets):
        test_name = bm.group("test").strip()
        start = bm.end()
        end = (
            bullets[i + 1].start()
            if i + 1 < len(bullets)
            else _find_jest_block_end(text, start)
        )
        block = text[start:end]
        f = _make_failure(test=test_name)
        f["traceback"] = block.strip() or None
        # Extract "Expected: ..." / "Received: ..." (jest convention).
        exp = re.search(r"^\s*Expected:\s*(.+?)\s*$", block, re.MULTILINE)
        rec = re.search(r"^\s*Received:\s*(.+?)\s*$", block, re.MULTILINE)
        if exp:
            f["expected"] = exp.group(1).strip()
        if rec:
            f["actual"] = rec.group(1).strip()
        # The "> NN |   expect(...)" pointer line is the assertion.
        assert_m = re.search(
            r"^\s*>\s+\d+\s*\|\s*(?P<code>.+?)\s*$", block, re.MULTILINE
        )
        if assert_m:
            f["assertion"] = assert_m.group("code").strip()
        # File:line from "at Object.<anonymous> (path:NN:NN)" or "at (path:NN:NN)".
        loc = re.search(
            r"\(?(?P<file>[^\s()]+\.(?:tsx?|jsx?|mjs|cjs)):(?P<line>\d+):\d+\)?",
            block,
        )
        if loc:
            f["file"] = loc.group("file")
            f["line"] = int(loc.group("line"))
        failures.append(f)

    return {"runner": "jest", "summary": summary, "failures": failures}


def _find_jest_block_end(text: str, start: int) -> int:
    # End at the "Test Suites:" / "Tests:" / "Snapshots:" summary banner.
    end_m = re.search(
        r"^(?:Test Suites:|Tests:|Snapshots:|Ran all test suites)",
        text[start:],
        re.MULTILINE,
    )
    return start + end_m.start() if end_m else len(text)


# ---------------------------------------------------------------------------
# vitest
# ---------------------------------------------------------------------------

VITEST_TESTS_RE = re.compile(
    r"^\s*Tests\s+(?:(\d+)\s+failed\s*\|\s*)?(?:(\d+)\s+skipped\s*\|\s*)?"
    r"(\d+)\s+passed",
    re.MULTILINE,
)

VITEST_FAIL_HEADER_RE = re.compile(
    r"^\s*FAIL\s+(?P<test>.+?)\s*$",
    re.MULTILINE,
)


def parse_vitest(text: str) -> dict:
    summary = _empty_summary()
    m = VITEST_TESTS_RE.search(text)
    if m:
        failed, skipped, passed = m.groups()
        summary["failed"] = int(failed or 0)
        summary["skipped"] = int(skipped or 0)
        summary["passed"] = int(passed or 0)

    failures = []
    headers = list(VITEST_FAIL_HEADER_RE.finditer(text))
    for i, hm in enumerate(headers):
        test_name = hm.group("test").strip()
        start = hm.end()
        if i + 1 < len(headers):
            end = headers[i + 1].start()
        else:
            end_m = re.search(
                r"^(?:⎯+|\s*Test Files\s+|\s*Tests\s+\d+)",
                text[start:],
                re.MULTILINE,
            )
            end = start + end_m.start() if end_m else len(text)
        block = text[start:end]
        f = _make_failure(test=test_name)
        f["traceback"] = block.strip() or None
        # Expected/Received via "- Expected\n+ Received" diff blocks.
        # Skip the "- Expected" / "+ Received" label lines themselves.
        for dm in re.finditer(r"^-\s+(.+?)\s*$", block, re.MULTILINE):
            val = dm.group(1).strip()
            if val.lower() != "expected":
                f["expected"] = val
                break
        for dm in re.finditer(r"^\+\s+(.+?)\s*$", block, re.MULTILINE):
            val = dm.group(1).strip()
            if val.lower() != "received":
                f["actual"] = val
                break
        # Also accept "expected 'x' to be 'y'" form.
        if not f["expected"] or not f["actual"]:
            inline = re.search(
                r"expected\s+(?P<actual>.+?)\s+to\s+be\s+(?P<expected>.+?)(?:\s|$)",
                block,
            )
            if inline:
                f["actual"] = f["actual"] or inline.group("actual").strip(" '\"")
                f["expected"] = f["expected"] or inline.group("expected").strip(" '\"")
        # File:line from "❯ path:NN:NN".
        loc = re.search(
            r"❯\s+(?P<file>[^\s:]+):(?P<line>\d+):\d+",
            block,
        )
        if loc:
            f["file"] = loc.group("file")
            f["line"] = int(loc.group("line"))
        # Assertion line from "> NN|   code".
        assert_m = re.search(
            r"^\s*\d+\|\s*(?P<code>.*expect.*)$", block, re.MULTILINE
        )
        if assert_m:
            f["assertion"] = assert_m.group("code").strip()
        failures.append(f)

    return {"runner": "vitest", "summary": summary, "failures": failures}


# ---------------------------------------------------------------------------
# cargo
# ---------------------------------------------------------------------------

CARGO_RESULT_RE = re.compile(
    r"^test result:\s+(?:FAILED|ok)\.\s+(\d+)\s+passed;\s*(\d+)\s+failed"
    r"(?:;\s*(\d+)\s+ignored)?",
    re.MULTILINE,
)

CARGO_FAILED_TEST_RE = re.compile(
    r"^---- (?P<test>\S+) stdout ----\s*$",
    re.MULTILINE,
)


def parse_cargo(text: str) -> dict:
    summary = _empty_summary()
    m = CARGO_RESULT_RE.search(text)
    if m:
        passed, failed, ignored = m.groups()
        summary["passed"] = int(passed)
        summary["failed"] = int(failed)
        summary["skipped"] = int(ignored or 0)

    failures = []
    blocks = list(CARGO_FAILED_TEST_RE.finditer(text))
    for i, bm in enumerate(blocks):
        test_name = bm.group("test")
        start = bm.end()
        if i + 1 < len(blocks):
            end = blocks[i + 1].start()
        else:
            end_m = re.search(r"^\s*failures:\s*$", text[start:], re.MULTILINE)
            end = start + end_m.start() if end_m else len(text)
        block = text[start:end]
        f = _make_failure(test=test_name)
        f["traceback"] = block.strip() or None
        # File:line from "panicked at src/lib.rs:NN:NN".
        loc = re.search(
            r"panicked at\s+(?P<file>[^\s:]+):(?P<line>\d+)(?::\d+)?",
            block,
        )
        if loc:
            f["file"] = loc.group("file")
            f["line"] = int(loc.group("line"))
        # "assertion `left == right` failed\n  left: X\n right: Y"
        lr = re.search(
            r"assertion[^\n]*failed[^\n]*\n\s*left:\s*(?P<left>.+?)\n\s*right:\s*(?P<right>.+?)\s*$",
            block,
            re.MULTILINE,
        )
        if lr:
            f["actual"] = lr.group("left").strip()
            f["expected"] = lr.group("right").strip()
            f["assertion"] = "assertion `left == right` failed"
        failures.append(f)

    return {"runner": "cargo", "summary": summary, "failures": failures}


# ---------------------------------------------------------------------------
# go
# ---------------------------------------------------------------------------

GO_FAIL_RE = re.compile(
    r"^--- FAIL:\s+(?P<test>\S+)\s+\([\d.]+s\)\s*$",
    re.MULTILINE,
)

GO_PASS_RE = re.compile(
    r"^--- PASS:\s+\S+\s+\([\d.]+s\)\s*$",
    re.MULTILINE,
)

GO_SKIP_RE = re.compile(
    r"^--- SKIP:\s+\S+\s+\([\d.]+s\)\s*$",
    re.MULTILINE,
)


def parse_go(text: str) -> dict:
    summary = _empty_summary()
    summary["passed"] = len(GO_PASS_RE.findall(text))
    summary["failed"] = len(GO_FAIL_RE.findall(text))
    summary["skipped"] = len(GO_SKIP_RE.findall(text))

    failures = []
    # Build a list of all === RUN positions so we can carve per-test blocks.
    run_re = re.compile(r"^=== RUN\s+(?P<name>\S+)\s*$", re.MULTILINE)
    runs = [(m.group("name"), m.start(), m.end()) for m in run_re.finditer(text)]
    # Map run name -> (start, next_run_start_or_eof).
    boundaries = {}
    for i, (name, s, e) in enumerate(runs):
        nxt = runs[i + 1][1] if i + 1 < len(runs) else len(text)
        boundaries.setdefault(name, []).append((e, nxt))

    for m in GO_FAIL_RE.finditer(text):
        test_name = m.group("test")
        # Use the LAST run-boundary for this test (most recent).
        block = ""
        if test_name in boundaries:
            s, e = boundaries[test_name][-1]
            block = text[s:e]
        f = _make_failure(test=test_name)
        f["traceback"] = block.strip() or None
        # File:line from "    cart_test.go:42: total mismatch: ..."
        loc = re.search(
            r"^\s*(?P<file>\S+\.go):(?P<line>\d+):\s*(?P<msg>.+?)\s*$",
            block,
            re.MULTILINE,
        )
        if loc:
            f["file"] = loc.group("file")
            f["line"] = int(loc.group("line"))
            f["assertion"] = loc.group("msg").strip()
            # Try "got X, want Y" idiom.
            gw = re.search(
                r"got\s+(?P<actual>.+?),\s*want\s+(?P<expected>.+?)\s*$",
                loc.group("msg"),
            )
            if gw:
                f["actual"] = gw.group("actual").strip()
                f["expected"] = gw.group("expected").strip()
        failures.append(f)

    return {"runner": "go", "summary": summary, "failures": failures}


# ---------------------------------------------------------------------------
# maven (surefire)
# ---------------------------------------------------------------------------

MAVEN_FINAL_RE = re.compile(
    r"^\[(?:INFO|ERROR)\]\s+Tests run:\s*(?P<run>\d+),\s*"
    r"Failures:\s*(?P<failures>\d+),\s*Errors:\s*(?P<errors>\d+),\s*"
    r"Skipped:\s*(?P<skipped>\d+)\s*$",
    re.MULTILINE,
)

MAVEN_FAIL_HEADER_RE = re.compile(
    r"^\[ERROR\]\s+(?P<test>[\w.$]+)\s+Time elapsed:.*<<<\s*FAILURE!",
    re.MULTILINE,
)


def parse_maven(text: str) -> dict:
    summary = _empty_summary()
    # The final aggregate line appears AFTER "Results:" near the bottom.
    finals = list(MAVEN_FINAL_RE.finditer(text))
    if finals:
        m = finals[-1]
        run = int(m.group("run"))
        failed = int(m.group("failures"))
        errors = int(m.group("errors"))
        skipped = int(m.group("skipped"))
        summary["failed"] = failed
        summary["errors"] = errors
        summary["skipped"] = skipped
        summary["passed"] = max(0, run - failed - errors - skipped)

    failures = []
    headers = list(MAVEN_FAIL_HEADER_RE.finditer(text))
    for i, hm in enumerate(headers):
        test_name = hm.group("test").strip()
        start = hm.end()
        if i + 1 < len(headers):
            end = headers[i + 1].start()
        else:
            end_m = re.search(
                r"^\[INFO\]\s+Running\s+|^\[INFO\]\s+Results:|^\[ERROR\]\s+Failures:",
                text[start:],
                re.MULTILINE,
            )
            end = start + end_m.start() if end_m else len(text)
        block = text[start:end]
        f = _make_failure(test=test_name)
        f["traceback"] = block.strip() or None
        # "expected: <X> but was: <Y>"
        ea = re.search(
            r"expected:\s*<(?P<expected>[^>]+)>\s*but was:\s*<(?P<actual>[^>]+)>",
            block,
        )
        if ea:
            f["expected"] = ea.group("expected").strip()
            f["actual"] = ea.group("actual").strip()
        # File:line from "at com.example.cart.CartTest.testCalculateTotalWithTax(CartTest.java:42)"
        loc = re.search(
            r"\((?P<file>[\w$]+\.java):(?P<line>\d+)\)",
            block,
        )
        if loc:
            f["file"] = loc.group("file")
            f["line"] = int(loc.group("line"))
        # Assertion line: first AssertionFailedError / AssertionError line.
        assert_m = re.search(
            r"^(?P<line>\S*Assert\S*(?:Error|Exception)[^\n]*)$",
            block,
            re.MULTILINE,
        )
        if assert_m:
            f["assertion"] = assert_m.group("line").strip()
        failures.append(f)

    return {"runner": "maven", "summary": summary, "failures": failures}


# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

RUNNERS: dict[str, Callable[[str], dict]] = {
    "pytest": parse_pytest,
    "jest": parse_jest,
    "vitest": parse_vitest,
    "cargo": parse_cargo,
    "go": parse_go,
    "maven": parse_maven,
}


def _empty_result(runner: Optional[str]) -> dict:
    return {
        "runner": runner,
        "summary": _empty_summary(),
        "failures": [],
    }


def parse(text: str, forced_runner: Optional[str] = None) -> dict:
    if forced_runner:
        runner = forced_runner
    else:
        runner = detect_runner(text)
    if runner is None:
        return _empty_result(None)
    parser = RUNNERS.get(runner)
    if parser is None:
        return _empty_result(runner)
    return parser(text)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _read_input(path: Optional[str]) -> str:
    if path and path != "-":
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                return fh.read()
        except OSError as e:
            print(f"parse_test_output.py: cannot read {path}: {e}", file=sys.stderr)
            sys.exit(2)
    return sys.stdin.read()


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Parse test-runner output into normalized JSON.",
    )
    parser.add_argument(
        "path",
        nargs="?",
        default=None,
        help="Path to raw output file. Reads stdin if omitted or '-'.",
    )
    parser.add_argument(
        "--runner",
        choices=sorted(RUNNERS.keys()),
        default=None,
        help="Force a specific runner instead of auto-detecting.",
    )
    parser.add_argument(
        "--exit-code",
        type=int,
        default=None,
        help="Exit code of the original test command (recorded as-is in JSON).",
    )
    args = parser.parse_args(argv)

    text = _read_input(args.path)
    result = parse(text, forced_runner=args.runner)
    if args.exit_code is not None:
        result["exit_code"] = args.exit_code
    else:
        result.setdefault("exit_code", None)
    # Stable key order.
    ordered = {
        "runner": result.get("runner"),
        "exit_code": result.get("exit_code"),
        "summary": result.get("summary", _empty_summary()),
        "failures": result.get("failures", []),
    }
    json.dump(ordered, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
