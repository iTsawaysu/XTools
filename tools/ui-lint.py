#!/usr/bin/env python3
"""Static UI ownership guard for XTools.

The guard protects the boundaries the v9 component contract cares about:
page files compose shared controls instead of defining private button chrome,
and motion stays behind the shared motion layer. It is deliberately small and
deterministic so it can run in build.sh and in UILintContractTests.

Exit code 0 = clean, 1 = violations, 2 = configuration/IO error.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class Violation:
    rule: str
    path: str
    line: int
    message: str


# App-shell AppKit animation is allowed only in these two files because they
# wrap their timing values in ToolMotion.AppKitPreset. Everything else must use
# the shared SwiftUI motion API.
APPKIT_MOTION_ALLOWLIST = {
    "Sources/XTools/AppShell/SidebarNavigationListCoordinator.swift",
    "Sources/XTools/AppShell/SidebarScrollIndicatorView.swift",
}


def is_comment(line: str) -> bool:
    stripped = line.lstrip()
    return stripped.startswith("//") or stripped.startswith("///")


def scan_files(root: Path) -> list[Path]:
    sources = root / "Sources" / "XTools"
    if not sources.is_dir():
        raise FileNotFoundError(f"missing source root: {sources}")
    return sorted(sources.rglob("*.swift"))


def is_page_file(path: Path) -> bool:
    return path.name.endswith("Page.swift") and "ToolPages" in path.parts


def add(violations: list[Violation], rule: str, path: Path, root: Path, line: int, message: str) -> None:
    violations.append(
        Violation(rule=rule, path=str(path.relative_to(root)), line=line, message=message)
    )


def scan(root: Path) -> list[Violation]:
    violations: list[Violation] = []
    files = scan_files(root)

    forbidden_suite = root / "Tests" / "XToolsTests" / "MotionSourceContractTests.swift"
    if forbidden_suite.exists():
        violations.append(
            Violation(
                rule="forbidden-source-contract-suite",
                path=str(forbidden_suite.relative_to(root)),
                line=1,
                message="source-scanning pseudo-contract suite was retired; use ui-lint plus behavior tests",
            )
        )

    for path in files:
        rel = str(path.relative_to(root))
        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        page = is_page_file(path)
        for number, line in enumerate(lines, start=1):
            if is_comment(line):
                continue

            if page and re.search(r"\bstruct\s+\w+\s*:\s*ButtonStyle\b", line):
                add(violations, "page-private-button-style", path, root, number,
                    "page files must compose shared button styles")
            if page and ".buttonStyle(.plain)" in line:
                add(violations, "page-plain-button-style", path, root, number,
                    "use IndexBareButtonStyle or a shared component")
            if page and re.search(r"\bProgressView\s*\(", line):
                add(violations, "page-bare-progress-view", path, root, number,
                    "use IndexProgressLabel / IndexProgressSpinner")
            if page and re.search(r"\.font\(\s*\.system\(size:\s*[0-9]", line):
                add(violations, "page-raw-font-size", path, root, number,
                    "use ToolTypography instead of numeric system font sizes")
            if re.search(r"\brunModal\s*\(", line) or "NSApp.runModal" in line:
                add(violations, "run-modal", path, root, number,
                    "use FileInputPanelClient / FileOutputPanelClient")

            if path.name != "ToolMotion.swift":
                if re.search(r"\bwithAnimation\s*\(", line):
                    add(violations, "raw-with-animation", path, root, number,
                        "use withToolAnimation(_:reduceMotion:_:)")
                if re.search(r"\bAnimation\.(spring|ease|linear|timingCurve|interpolatingSpring)\b", line):
                    add(violations, "raw-animation-curve", path, root, number,
                        "use ToolMotion.Preset / ToolMotion.Curve")
                if re.search(r"(?<!ToolMotion)\.animation\((?!minimumInterval:)", line):
                    add(violations, "raw-animation-modifier", path, root, number,
                        "use .toolAnimation(_:value:)")

            if rel not in APPKIT_MOTION_ALLOWLIST and "NSAnimationContext.runAnimationGroup" in line:
                add(violations, "raw-appkit-animation", path, root, number,
                    "wrap AppKit animation in the shared AppKit motion entry")

    return sorted(violations, key=lambda v: (v.path, v.line, v.rule))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="XTools UI ownership guard")
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="repository root")
    parser.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    args = parser.parse_args(argv)

    root = args.root.resolve()
    try:
        violations = scan(root)
    except OSError as error:
        print(f"ui-lint: {error}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps([asdict(v) for v in violations], ensure_ascii=False, indent=2))
    elif violations:
        for violation in violations:
            print(f"{violation.path}:{violation.line}: {violation.rule}: {violation.message}")
    else:
        print(f"ui-lint: clean ({len(scan_files(root))} Swift files)")

    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
