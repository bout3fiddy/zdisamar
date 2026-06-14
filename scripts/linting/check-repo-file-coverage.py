#!/usr/bin/env python3
"""Verify every non-ignored Zig file has an owner row in the refactor coverage matrix."""

import argparse
import ast
import json
import subprocess
from collections.abc import Sequence
from fnmatch import fnmatch
from pathlib import Path

DEFAULT_MATRIX = Path(
    "scratch/refactor/2026-06-11-explicit-dataflow-refactor/repo-file-coverage.md"
)
MATRIX_SEARCH_ROOT = Path("scratch/refactor/2026-06-11-explicit-dataflow-refactor")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", type=Path, default=None)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)

    matrix = args.matrix if args.matrix is not None else resolve_default_matrix()
    patterns = extract_patterns(matrix)
    files = [path for path in git_ls_files() if Path(path).exists()]
    unmatched = [path for path in files if not any(fnmatch(path, pattern) for pattern in patterns)]
    report = {
        "schema_version": 1,
        "tool": "check-repo-file-coverage",
        "matrix": str(matrix),
        "files": len(files),
        "patterns": len(patterns),
        "unmatched": unmatched,
        "unmatched_count": len(unmatched),
    }

    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(f"files={len(files)} unmatched={len(unmatched)} patterns={len(patterns)}")
        if unmatched:
            print("\n".join(unmatched))

    return 1 if unmatched else 0


def resolve_default_matrix() -> Path:
    if DEFAULT_MATRIX.exists():
        return DEFAULT_MATRIX
    matches = sorted(MATRIX_SEARCH_ROOT.glob("**/repo-file-coverage.md"))
    if not matches:
        return DEFAULT_MATRIX
    return matches[0]


def extract_patterns(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    start = text.index("patterns = [")
    end = text.index("]\n", start) + 1
    module = ast.parse(text[start:end])

    assignment = module.body[0]
    if not isinstance(assignment, ast.Assign) or not isinstance(assignment.value, ast.List):
        raise ValueError(f"{path} does not contain a literal patterns list")

    patterns: list[str] = []
    for item in assignment.value.elts:
        if not isinstance(item, ast.Constant) or not isinstance(item.value, str):
            raise ValueError(f"{path} contains a non-string coverage pattern")
        patterns.append(item.value)

    return patterns


def git_ls_files() -> list[str]:
    output = subprocess.check_output(
        [
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            ":(glob)*.zig",
            ":(glob)**/*.zig",
        ],
        text=True,
    )
    return output.splitlines()


if __name__ == "__main__":
    raise SystemExit(main())
