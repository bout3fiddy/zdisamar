#!/usr/bin/env python3
"""Reject broad hot-path signatures in the explicit-dataflow refactor tree."""

import argparse
import json
import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

HOT_FOLDERS = (
    "src/optics",
    "src/transport",
    "src/spectrum",
    "src/retrieval",
)

BANNED_EXACT_IDENTIFIERS = {
    "Scene",
    "PreparedOpticalState",
    "ProductStorage",
    "Context",
    "Workspace",
    "Request",
    "Cache",
    "ComputeCache",
    "Storage",
}

ALLOWED_DATA_OWNER_IDENTIFIERS = {
    "SolarIrradianceMemory",
    "ProfileLineValues",
    "TransportWorkArrays",
    "SpectrumSamplingTable",
    "RadianceWavelengthList",
}

IDENTIFIER_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
FUNCTION_RE = re.compile(r"\b(?:pub\s+)?(?:inline\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
TYPE_RE = re.compile(
    r"^\s*(?:pub\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"(?:extern\s+|packed\s+)?(?:struct|union|enum)\b"
)


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    symbol: str
    identifier: str
    kind: str
    message: str

    def render(self) -> str:
        return f"{self.path}:{self.line}: {self.kind} {self.message}"

    def to_json(self) -> dict[str, object]:
        return {
            "path": str(self.path),
            "line": self.line,
            "symbol": self.symbol,
            "identifier": self.identifier,
            "kind": self.kind,
            "message": self.message,
        }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*", default=HOT_FOLDERS)
    parser.add_argument("--format", choices=("text", "json"), default="text")
    args = parser.parse_args(argv)

    paths = tuple(zig_paths(args.paths))
    findings = tuple(finding for path in paths for finding in check_path(path))

    if args.format == "json":
        print(
            json.dumps(
                {
                    "schema_version": 1,
                    "tool": "check-explicit-dataflow-signatures",
                    "hot_folders": list(HOT_FOLDERS),
                    "checked_files": [str(path) for path in paths],
                    "banned_identifiers": sorted(BANNED_EXACT_IDENTIFIERS),
                    "allowed_data_owner_identifiers": sorted(ALLOWED_DATA_OWNER_IDENTIFIERS),
                    "summary": {"finding_count": len(findings)},
                    "findings": [finding.to_json() for finding in findings],
                },
                indent=2,
                sort_keys=True,
            )
        )
    elif findings:
        print("Explicit-dataflow signature guardrail violations:")
        for finding in findings:
            print(finding.render())

    return 1 if findings else 0


def zig_paths(raw_paths: Sequence[str]) -> Iterable[Path]:
    for raw_path in raw_paths:
        path = Path(raw_path)
        if path.is_dir():
            yield from sorted(child for child in path.rglob("*.zig") if ignored(child) is False)
        elif path.is_file() and path.suffix == ".zig" and ignored(path) is False:
            yield path


def ignored(path: Path) -> bool:
    ignored_parts = {".git", ".zig-cache", "zig-out", "vendor", "out"}
    return any(part in ignored_parts for part in path.parts)


def check_path(path: Path) -> Iterable[Finding]:
    lines = path.read_text(encoding="utf-8").splitlines()
    clean_lines = strip_comments(lines)

    for line_number, line in enumerate(clean_lines, start=1):
        type_match = TYPE_RE.search(line)
        if type_match:
            type_name = type_match.group(1)
            if banned_type_name(type_name):
                yield Finding(
                    path=path,
                    line=line_number,
                    symbol=type_name,
                    identifier=type_name,
                    kind="broad-type",
                    message=(
                        f"{type_name} is too broad for new hot-path dataflow; "
                        "name the retained data."
                    ),
                )

    yield from check_function_signatures(path, clean_lines)


def check_function_signatures(path: Path, lines: Sequence[str]) -> Iterable[Finding]:
    line_index = 0

    while line_index < len(lines):
        line = lines[line_index]
        match = FUNCTION_RE.search(line)
        if not match:
            line_index += 1
            continue

        fn_name = match.group(1)
        start_line = line_index + 1
        signature_lines = [line]
        paren_depth = line.count("(") - line.count(")")

        while paren_depth > 0 and line_index + 1 < len(lines):
            line_index += 1
            next_line = lines[line_index]
            signature_lines.append(next_line)
            paren_depth += next_line.count("(") - next_line.count(")")

        signature = "\n".join(signature_lines)
        for identifier in IDENTIFIER_RE.findall(signature):
            if identifier in ALLOWED_DATA_OWNER_IDENTIFIERS:
                continue
            if banned_signature_identifier(identifier):
                yield Finding(
                    path=path,
                    line=start_line,
                    symbol=fn_name,
                    identifier=identifier,
                    kind="broad-signature",
                    message=(
                        f"{fn_name} signature mentions {identifier}; pass explicit "
                        "scalars, slices, "
                        "or named physics tables instead."
                    ),
                )

        line_index += 1


def banned_type_name(identifier: str) -> bool:
    if identifier in BANNED_EXACT_IDENTIFIERS:
        return True
    return identifier.endswith("Request") or identifier.endswith("Workspace")


def banned_signature_identifier(identifier: str) -> bool:
    if identifier in BANNED_EXACT_IDENTIFIERS:
        return True
    return identifier.endswith("Request") or identifier.endswith("Workspace")


def strip_comments(lines: Sequence[str]) -> tuple[str, ...]:
    return tuple(strip_line_comment(line) for line in lines)


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
