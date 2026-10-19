#!/usr/bin/env python3
"""XTools UI lint.

Guards the v4.1 composition layer against raw visual literals and new
hand-rolled motion. Hard rules must stay at zero in tool-page code; spacing
and frame literals are ratcheted so a page family may only reduce its budget.

Usage:
    python3 tools/ui-lint.py
    python3 tools/ui-lint.py --update-baseline
    python3 tools/ui-lint.py --list
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN_ROOT = ROOT / "Sources" / "XTools" / "ToolPages"
EXCLUDED_DIRS = {SCAN_ROOT / "Workbench"}
BASELINE = ROOT / "tools" / "ui-lint-baseline.json"

# Rules that must never appear in tool-page code.
HARD_RULES: dict[str, re.Pattern[str]] = {
    "raw_color": re.compile(r"\bColor\((red:|\.sRGB|\.displayP3)|#colorLiteral|\bColor\.(white|black)\b"),
    "raw_corner_radius": re.compile(r"\.cornerRadius\(\s*[0-9]|cornerRadius:\s*[0-9]"),
    "raw_font_size": re.compile(r"\.font\(\.system\(\s*size:\s*[0-9]"),
    "raw_shadow": re.compile(r"\.shadow\("),
    "raw_motion": re.compile(r"\.animation\(|\.animation\s*\{|\bwithAnimation\s*[({]"),
}

# Rules counted per file; the baseline may only go down.
RATCHET_RULES: dict[str, re.Pattern[str]] = {
    "padding_literal": re.compile(
        r"\.padding\(\s*(?:\.(?:horizontal|vertical|top|leading|trailing|bottom|all)\s*,\s*)?[0-9]"
    ),
    "spacing_literal": re.compile(r"\bspacing:\s*[0-9]"),
    "frame_literal": re.compile(
        r"\.frame\(\s*(?:minWidth|maxWidth|width|minHeight|maxHeight|height):\s*[0-9]"
    ),
}

# File-scoped exemptions. Keep the list short and justify every entry.
FILE_EXEMPTIONS: dict[str, set[str]] = {
    # Functional color-picker tracks and saturation/preview swatches: these
    # render user data, not design tokens.
    "Sources/XTools/ToolPages/Image/ColorPickerPage.swift": {"raw_color"},
    # Shared image preview implementation: the only owner of the
    # replacement-motion policy (ADR-0018) and it reads ToolMotion tokens.
    "Sources/XTools/ToolPages/Image/ImagePreviewStage.swift": {"raw_motion"},
}

IGNORE_MARKER = "ui-lint:ignore"


def iter_swift_files() -> list[Path]:
    files: list[Path] = []
    for path in sorted(SCAN_ROOT.rglob("*.swift")):
        if any(path.is_relative_to(skip) for skip in EXCLUDED_DIRS):
            continue
        files.append(path)
    return files


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def scan() -> tuple[list[dict[str, object]], dict[str, dict[str, int]]]:
    violations: list[dict[str, object]] = []
    counts: dict[str, dict[str, int]] = {rule: {} for rule in RATCHET_RULES}

    for path in iter_swift_files():
        key = rel(path)
        exempt = FILE_EXEMPTIONS.get(key, set())
        for line_no, line in enumerate(path.read_text().splitlines(), start=1):
            if IGNORE_MARKER in line:
                continue
            # TimelineView schedules are not SwiftUI view animations.
            if "TimelineView(" in line or "minimumInterval" in line:
                continue
            for rule, pattern in HARD_RULES.items():
                if rule in exempt:
                    continue
                if pattern.search(line):
                    violations.append(
                        {"rule": rule, "file": key, "line": line_no, "text": line.strip()[:160]}
                    )
            for rule, pattern in RATCHET_RULES.items():
                if pattern.search(line):
                    counts[rule][key] = counts[rule].get(key, 0) + 1
    return violations, counts


def totals(counts: dict[str, dict[str, int]]) -> dict[str, int]:
    return {rule: sum(files.values()) for rule, files in counts.items()}


def load_baseline() -> dict[str, dict[str, int]] | None:
    if not BASELINE.exists():
        return None
    data = json.loads(BASELINE.read_text())
    return data.get("counts")


def write_baseline(counts: dict[str, dict[str, int]]) -> None:
    payload = {
        "version": 1,
        "note": "Ratchet baseline for tools/ui-lint.py. Lower, never raise.",
        "counts": counts,
    }
    BASELINE.parent.mkdir(parents=True, exist_ok=True)
    BASELINE.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="XTools UI lint")
    parser.add_argument("--update-baseline", action="store_true")
    parser.add_argument("--list", action="store_true", help="print scanned files")
    args = parser.parse_args()

    if not SCAN_ROOT.is_dir():
        print(f"ui-lint: missing scan root {SCAN_ROOT}", file=sys.stderr)
        return 2

    if args.list:
        for path in iter_swift_files():
            print(rel(path))
        return 0

    violations, counts = scan()

    if args.update_baseline:
        write_baseline(counts)
        print(f"ui-lint: baseline updated at {rel(BASELINE)}")
        return 0

    baseline = load_baseline()
    failures = 0

    if violations:
        failures += len(violations)
        print(f"ui-lint: {len(violations)} hard violation(s)")
        for item in violations:
            print(f"  {item['file']}:{item['line']}  [{item['rule']}]  {item['text']}")

    if baseline is None:
        failures += 1
        print(f"ui-lint: missing baseline {rel(BASELINE)}; run --update-baseline")
    else:
        increased: list[str] = []
        for rule, per_file in counts.items():
            base_per_file = baseline.get(rule, {})
            for file, count in per_file.items():
                allowed = base_per_file.get(file, 0)
                if count > allowed:
                    increased.append(f"{rule} {file}: {count} > {allowed}")
            for file, allowed in base_per_file.items():
                if per_file.get(file, 0) < allowed:
                    print(f"ui-lint: budget available: {rule} {file} {per_file.get(file, 0)}/{allowed}")
        if increased:
            failures += len(increased)
            print(f"ui-lint: {len(increased)} ratchet increase(s) (reduce literals instead of raising the baseline)")
            for item in increased:
                print(f"  {item}")

    current = totals(counts)
    print("ui-lint: ratchet totals " + ", ".join(f"{rule}={value}" for rule, value in sorted(current.items())))
    print("ui-lint: PASS" if failures == 0 else f"ui-lint: FAIL ({failures})")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
