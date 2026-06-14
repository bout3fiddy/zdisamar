#!/usr/bin/env python3
"""Count Zig LOC for the explicit-dataflow refactor guardrail."""

import argparse
import json
import re
import subprocess
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

COUNTED_EXCLUSIONS = (
    "src/instrumentation/",
    "src/validation/",
    "src/internal.zig",
)


@dataclass(frozen=True)
class FileCount:
    path: str
    loc: int
    logical_sloc: int
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
        if Path(path).exists()
    ]
    counts = tuple(
        FileCount(
            path=path,
            loc=count_code_lines(Path(path)),
            logical_sloc=count_logical_sloc(Path(path)),
            counted=is_counted_product_file(path),
        )
        for path in files
    )

    raw_loc = sum(item.loc for item in counts)
    raw_logical_sloc = sum(item.logical_sloc for item in counts)
    counted_loc = sum(item.loc for item in counts if item.counted)
    counted_logical_sloc = sum(item.logical_sloc for item in counts if item.counted)
    raw_files = len(counts)
    counted_files = sum(1 for item in counts if item.counted)

    report = {
        "schema_version": 1,
        "tool": "refactor-loc-counter",
        "scope": "non-ignored non-test Zig files under src/",
        "exclusions": list(COUNTED_EXCLUSIONS),
        "summary": {
            "raw_src_loc": raw_loc,
            "raw_src_logical_sloc": raw_logical_sloc,
            "raw_src_files": raw_files,
            "counted_product_api_loc": counted_loc,
            "counted_product_api_logical_sloc": counted_logical_sloc,
            "counted_product_api_files": counted_files,
        },
        "files": [
            {
                "path": item.path,
                "loc": item.loc,
                "logical_sloc": item.logical_sloc,
                "counted": item.counted,
            }
            for item in counts
        ],
    }

    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(f"raw_src_loc={raw_loc} raw_src_files={raw_files}")
        print(f"raw_src_logical_sloc={raw_logical_sloc} raw_src_files={raw_files}")
        print(f"counted_product_api_loc={counted_loc} counted_product_api_files={counted_files}")
        print(
            f"counted_product_api_logical_sloc={counted_logical_sloc} "
            f"counted_product_api_files={counted_files}"
        )
        print("counted exclusions:")
        for exclusion in COUNTED_EXCLUSIONS:
            print(f"  {exclusion}")

    return 0


def git_ls_files() -> list[str]:
    output = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        text=True,
    )
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


def count_logical_sloc(path: Path) -> int:
    code = "\n".join(strip_comments_and_strings(path.read_text(encoding="utf-8").splitlines()))
    return (
        code.count(";")
        + len(
            re.findall(
                r"\b(?:pub\s+)?(?:export\s+)?(?:inline\s+)?fn\s+[A-Za-z_][A-Za-z0-9_]*", code
            )
        )
        + len(re.findall(r"\btest\s*(?:\"|\{)", code))
    )


def strip_comments_and_strings(lines: Sequence[str]) -> list[str]:
    return [
        strip_strings(strip_line_comment(line)) for line in lines if not multiline_string_line(line)
    ]


def multiline_string_line(line: str) -> bool:
    return line.lstrip().startswith("\\\\")


def strip_strings(line: str) -> str:
    result: list[str] = []
    in_string = False
    escaped = False

    for char in line:
        if escaped:
            result.append(" ")
            escaped = False
        elif char == "\\" and in_string:
            result.append(" ")
            escaped = True
        elif char == '"':
            result.append(" ")
            in_string = not in_string
        elif in_string:
            result.append(" ")
        else:
            result.append(char)

    return "".join(result)


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
