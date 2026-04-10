#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
POLICY_ROOTS = [
    REPO_ROOT / "src" / "core",
    REPO_ROOT / "src" / "kernels",
    REPO_ROOT / "src" / "retrieval",
    REPO_ROOT / "src" / "runtime",
    REPO_ROOT / "src" / "plugins",
    REPO_ROOT / "src" / "api",
]

UNREACHABLE_RE = re.compile(r"\bcatch unreachable\b|\bunreachable\b")
IMPORT_RE = re.compile(r'@import\("([^"]+)"\)')
IMPORT_DECL_RE = re.compile(r'^(?:pub\s+)?const\s+\w+\s*=\s*@import\("')


def iter_source_files() -> list[Path]:
    files: list[Path] = []
    for root in POLICY_ROOTS:
        files.extend(sorted(root.rglob("*.zig")))
    return files


def relative(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def boundary_findings(path: Path, line_no: int, line: str) -> list[dict[str, object]]:
    rel = relative(path)
    findings: list[dict[str, object]] = []
    if not rel.startswith(("src/core/", "src/kernels/")):
        return findings

    match = IMPORT_RE.search(line)
    if match and "adapters/" in match.group(1):
        findings.append(
            {
                "code": "core-kernel-import-boundary",
                "file": rel,
                "line": line_no,
                "message": "core and kernels must not import adapters directly",
                "text": line.rstrip(),
            }
        )
    return findings


def unreachable_findings(path: Path, line_no: int, line: str) -> list[dict[str, object]]:
    if not UNREACHABLE_RE.search(line):
        return []
    return [
        {
            "code": "runtime-unreachable",
            "file": relative(path),
            "line": line_no,
            "message": "runtime-facing unreachable or catch unreachable requires review",
            "text": line.rstrip(),
        }
    ]


def late_import_findings(path: Path, lines: list[str]) -> list[dict[str, object]]:
    findings: list[dict[str, object]] = []
    seen_body = False
    for line_no, raw_line in enumerate(lines, 1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        is_import = IMPORT_DECL_RE.match(stripped) is not None
        if is_import and seen_body:
            findings.append(
                {
                    "code": "late-import",
                    "file": relative(path),
                    "line": line_no,
                    "message": "imports should stay grouped at the top of the file",
                    "text": raw_line.rstrip(),
                }
            )
        if is_import:
            continue
        if stripped.startswith(("const ", "pub const ")):
            if any(
                marker in stripped
                for marker in (
                    "= struct",
                    "= enum",
                    "= union",
                    "= opaque",
                    "= packed",
                    "= extern",
                )
            ) or not stripped.endswith(";"):
                seen_body = True
            continue
        seen_body = True
    return findings


def collect_findings() -> list[dict[str, object]]:
    findings: list[dict[str, object]] = []
    for path in iter_source_files():
        lines = path.read_text().splitlines()
        for line_no, line in enumerate(lines, 1):
            findings.extend(boundary_findings(path, line_no, line))
            findings.extend(unreachable_findings(path, line_no, line))
        findings.extend(late_import_findings(path, lines))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description="Run zdisamar architecture/policy checks.")
    parser.add_argument("--report", required=True, help="Path to the JSON report file.")
    args = parser.parse_args()

    report_path = REPO_ROOT / args.report
    report_path.parent.mkdir(parents=True, exist_ok=True)

    findings = collect_findings()
    payload = {
        "version": 1,
        "finding_count": len(findings),
        "findings": findings,
    }
    report_path.write_text(json.dumps(payload, indent=2) + "\n")

    if findings:
        print(f"tidy found {len(findings)} policy findings")
        for finding in findings[:20]:
            print(
                f"{finding['code']}: {finding['file']}:{finding['line']}: {finding['message']}"
            )
        if len(findings) > 20:
            print(f"... and {len(findings) - 20} more")
        return 1

    print("tidy found no policy findings")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
