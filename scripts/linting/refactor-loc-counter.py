#!/usr/bin/env python3
"""Count Zig LOC for the explicit-dataflow refactor guardrail."""

import argparse
import json
import subprocess
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

COUNTED_EXCLUSIONS = (
    "src/forward_model/instrumentation/",
    "src/instrumentation/",
    "src/validation/",
    "src/input/o2a_reference/metrics.zig",
    "src/internal.zig",
)


@dataclass(frozen=True)
class FileCount:
    path: str
    loc: int
    counted: bool


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format.",
    )
    args = parser.parse_args(argv)

    files = [
        path
        for path in git_ls_files()
        if path.startswith("src/") and path.endswith(".zig") and not is_test_path(path)
    ]
    counts = tuple(
        FileCount(
            path=path, loc=count_code_lines(Path(path)), counted=is_counted_product_file(path)
        )
        for path in files
    )

    raw_loc = sum(item.loc for item in counts)
    counted_loc = sum(item.loc for item in counts if item.counted)
    raw_files = len(counts)
    counted_files = sum(1 for item in counts if item.counted)

    report = {
        "schema_version": 1,
        "tool": "refactor-loc-counter",
        "scope": "tracked non-test Zig files under src/",
        "exclusions": list(COUNTED_EXCLUSIONS),
        "summary": {
            "raw_src_loc": raw_loc,
            "raw_src_files": raw_files,
            "counted_product_api_loc": counted_loc,
            "counted_product_api_files": counted_files,
        },
        "files": [{"path": item.path, "loc": item.loc, "counted": item.counted} for item in counts],
    }

    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(f"raw_src_loc={raw_loc} raw_src_files={raw_files}")
        print(f"counted_product_api_loc={counted_loc} counted_product_api_files={counted_files}")
        print("counted exclusions:")
        for exclusion in COUNTED_EXCLUSIONS:
            print(f"  {exclusion}")

    return 0


def git_ls_files() -> list[str]:
    output = subprocess.check_output(["git", "ls-files"], text=True)
    return output.splitlines()


def is_test_path(path: str) -> bool:
    name = Path(path).name
    return name.endswith("_test.zig") or "/test/" in path or "/tests/" in path


def is_counted_product_file(path: str) -> bool:
    return not any(
        path == exclusion or path.startswith(exclusion) for exclusion in COUNTED_EXCLUSIONS
    )


def count_code_lines(path: Path) -> int:
    loc = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        code = strip_line_comment(line).strip()
        if code:
            loc += 1
    return loc


def strip_line_comment(line: str) -> str:
    in_string = False
    escaped = False
    index = 0

    while index < len(line):
        char = line[index]

        if escaped:
            escaped = False
        elif char == "\\" and in_string:
            escaped = True
        elif char == '"':
            in_string = not in_string
        elif not in_string and char == "/" and index + 1 < len(line) and line[index + 1] == "/":
            return line[:index]

        index += 1

    return line


if __name__ == "__main__":
    raise SystemExit(main())
