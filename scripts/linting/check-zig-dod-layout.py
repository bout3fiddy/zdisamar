#!/usr/bin/env python3
"""Rank Zig loops that walk broad rows while reading few fields."""

import argparse
import json
import re
import sys
from collections import Counter
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

STRUCT_RE = re.compile(
    r"^\s*(?:pub\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"(?:extern\s+|packed\s+)?struct\b"
)
FIELD_RE = re.compile(r"^\s*(?:pub\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^,=]+)")
FN_RE = re.compile(r"\b(?:pub\s+)?(?:inline\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\b")
LOCAL_TYPE_RE = re.compile(r"\b(?:const|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^=;]+)")

HOT_PATH_PARTS = {
    "forward_model",
    "instrument_grid",
    "labos",
    "optical_properties",
    "optimal_estimation",
}
ACCESS_WORDS = {"for", "if", "while", "switch", "return", "try", "catch", "else"}
NUMERIC_TYPES = {
    "bool": 1,
    "u1": 1,
    "u2": 1,
    "u3": 1,
    "u4": 1,
    "u8": 1,
    "i8": 1,
    "u16": 2,
    "i16": 2,
    "f16": 2,
    "u32": 4,
    "i32": 4,
    "f32": 4,
    "usize": 8,
    "isize": 8,
    "u64": 8,
    "i64": 8,
    "f64": 8,
}
COLD_TYPE_WORDS = {
    "Allocator",
    "ArrayList",
    "HashMap",
    "String",
    "Path",
    "File",
    "Reader",
    "Writer",
    "Error",
    "Report",
    "Diagnostic",
    "Diagnostics",
    "Config",
    "Controls",
    "Cache",
    "Key",
    "Manifest",
}


@dataclass(frozen=True)
class FieldInfo:
    name: str
    type_name: str
    line: int
    estimated_bytes: int
    cold_hint: bool


@dataclass(frozen=True)
class StructInfo:
    name: str
    path: Path
    line_start: int
    line_end: int
    fields: tuple[FieldInfo, ...]

    @property
    def estimated_bytes(self) -> int:
        return sum(field.estimated_bytes for field in self.fields)


@dataclass(frozen=True)
class FunctionInfo:
    name: str
    path: Path
    line_start: int
    line_end: int
    signature: str
    body_lines: tuple[str, ...]
    params: dict[str, str]


@dataclass(frozen=True)
class LoopUse:
    iterable: str
    variable: str
    pointer_capture: bool
    line_start: int
    line_end: int
    body: str


@dataclass(frozen=True)
class Finding:
    path: Path
    line_start: int
    line_end: int
    function: str
    rule: str
    severity: str
    score: int
    struct_name: str
    iterable: str
    variable: str
    pointer_capture: bool
    field_count: int
    estimated_row_bytes: int
    read_fields: tuple[str, ...]
    unused_fields: tuple[str, ...]
    cold_unused_fields: tuple[str, ...]
    message: str
    suggestion: str

    def to_json(self) -> dict[str, object]:
        return {
            "path": str(self.path),
            "line_start": self.line_start,
            "line_end": self.line_end,
            "function": self.function,
            "rule": self.rule,
            "severity": self.severity,
            "score": self.score,
            "struct_name": self.struct_name,
            "iterable": self.iterable,
            "variable": self.variable,
            "capture": "pointer" if self.pointer_capture else "value",
            "field_count": self.field_count,
            "estimated_row_bytes": self.estimated_row_bytes,
            "read_fields": list(self.read_fields),
            "unused_fields": list(self.unused_fields),
            "cold_unused_fields": list(self.cold_unused_fields),
            "message": self.message,
            "suggestion": self.suggestion,
        }

    def render(self) -> str:
        fields = ", ".join(self.read_fields)
        unused = ", ".join(self.unused_fields[:6])
        if len(self.unused_fields) > 6:
            unused += f", +{len(self.unused_fields) - 6} more"
        capture = f"*{self.variable}" if self.pointer_capture else self.variable
        copy_note = (
            "pointer capture; no by-value row copy, but the loop still strides over the wide row"
            if self.pointer_capture
            else "value capture; the source loop copies the row unless the compiler removes it"
        )
        return (
            f"{self.path}:{self.line_start}: {self.rule} {self.severity} "
            f"score={self.score} {self.message}\n"
            f"  function: {self.function}\n"
            f"  loop: for ({self.iterable}) |{capture}| over {self.struct_name}\n"
            f"  capture: {copy_note}\n"
            f"  reads: {fields}\n"
            f"  unused row fields in this loop: {unused}\n"
            f"  suggestion: {self.suggestion}"
        )


@dataclass(frozen=True)
class Audit:
    paths: tuple[Path, ...]
    structs: tuple[StructInfo, ...]
    functions: tuple[FunctionInfo, ...]
    loops_seen: int
    loops_analyzed: int
    findings: tuple[Finding, ...]


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "paths",
        nargs="*",
        default=("src",),
        help="Zig files or directories to check. Defaults to src/.",
    )
    parser.add_argument("--format", choices=("text", "json"), default="text")
    parser.add_argument("--max-findings", type=int, default=25)
    parser.add_argument("--min-score", type=int, default=55)
    parser.add_argument("--min-fields", type=int, default=5)
    parser.add_argument("--max-read-fields", type=int, default=3)
    parser.add_argument(
        "--fail-on",
        choices=("none", "low", "medium", "high"),
        default="none",
        help="Exit non-zero when a finding at or above this severity is present.",
    )
    parser.add_argument(
        "--allow-non-src",
        action="store_true",
        help="Allow paths outside src/. Intended for focused local experiments.",
    )
    args = parser.parse_args(argv)

    raw_paths = tuple(Path(path) for path in args.paths)
    if not args.allow_non_src:
        reject_non_src_paths(raw_paths)

    paths = tuple(zig_paths(raw_paths))
    audit = run_audit(
        paths,
        min_fields=args.min_fields,
        max_read_fields=args.max_read_fields,
        min_score=args.min_score,
    )

    findings = audit.findings[: args.max_findings if args.max_findings >= 0 else None]
    if args.format == "json":
        print_json_report(audit, findings)
    else:
        print_text_report(audit, findings, max_findings=args.max_findings)

    return 1 if should_fail(audit.findings, args.fail_on) else 0


def reject_non_src_paths(paths: Sequence[Path]) -> None:
    for path in paths:
        parts = path.parts
        if parts and parts[0] == "src":
            continue
        raise SystemExit(
            f"{path}: DOD layout audit is scoped to src/. "
            "Use --allow-non-src for a focused experiment."
        )


def zig_paths(paths: Sequence[Path]) -> Iterable[Path]:
    for path in paths:
        if path.is_dir():
            yield from sorted(child for child in path.rglob("*.zig") if not is_ignored_path(child))
        elif path.suffix == ".zig" and not is_ignored_path(path):
            yield path


def is_ignored_path(path: Path) -> bool:
    ignored_parts = {".git", ".zig-cache", "zig-out", "vendor", "out"}
    return any(part in ignored_parts for part in path.parts)


def run_audit(
    paths: Sequence[Path],
    *,
    min_fields: int,
    max_read_fields: int,
    min_score: int,
) -> Audit:
    source = {path: path.read_text(encoding="utf-8").splitlines() for path in paths}
    structs = tuple(
        struct for path, lines in source.items() for struct in parse_structs(path, lines)
    )
    functions = tuple(
        function for path, lines in source.items() for function in parse_functions(path, lines)
    )
    unique_structs = unique_struct_index(structs)

    loops_seen = 0
    loops_analyzed = 0
    findings: list[Finding] = []
    for function in functions:
        local_types = collect_local_types(function)
        for loop in parse_loops(function):
            loops_seen += 1
            row_type = resolve_loop_row_type(loop, function, local_types, unique_structs)
            if row_type is None:
                continue
            struct = unique_structs.get(row_type)
            if struct is None:
                continue
            loops_analyzed += 1
            finding = analyze_loop(
                loop,
                function,
                struct,
                min_fields=min_fields,
                max_read_fields=max_read_fields,
                min_score=min_score,
            )
            if finding is not None:
                findings.append(finding)

    return Audit(
        paths=tuple(paths),
        structs=structs,
        functions=functions,
        loops_seen=loops_seen,
        loops_analyzed=loops_analyzed,
        findings=tuple(sorted(findings, key=finding_sort_key)),
    )


def parse_structs(path: Path, lines: Sequence[str]) -> Iterable[StructInfo]:
    index = 0
    while index < len(lines):
        line = code_part(lines[index])
        match = STRUCT_RE.match(line)
        if match is None:
            index += 1
            continue

        name = match.group(1)
        body_start = find_open_brace(lines, index)
        if body_start is None:
            index += 1
            continue

        end = find_block_end(lines, body_start)
        fields = tuple(parse_struct_fields(lines, body_start, end))
        yield StructInfo(
            name=name,
            path=path,
            line_start=index + 1,
            line_end=end + 1,
            fields=fields,
        )
        index = end + 1


def parse_struct_fields(
    lines: Sequence[str],
    body_start: int,
    body_end: int,
) -> Iterable[FieldInfo]:
    depth = 0
    for index in range(body_start, body_end + 1):
        line = code_part(lines[index])
        depth += line.count("{")
        candidate_depth = depth
        depth -= line.count("}")
        if candidate_depth != 1:
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith(("pub fn", "fn ", "const ", "var ")):
            continue
        match = FIELD_RE.match(line)
        if match is None:
            continue
        field_name = match.group(1)
        type_name = clean_type(match.group(2))
        yield FieldInfo(
            name=field_name,
            type_name=type_name,
            line=index + 1,
            estimated_bytes=estimate_type_bytes(type_name),
            cold_hint=is_cold_type(type_name, field_name),
        )


def parse_functions(path: Path, lines: Sequence[str]) -> Iterable[FunctionInfo]:
    index = 0
    while index < len(lines):
        line = code_part(lines[index])
        match = FN_RE.search(line)
        if match is None:
            index += 1
            continue

        name = match.group(1)
        body_start = find_open_brace(lines, index)
        if body_start is None:
            index += 1
            continue

        end = find_block_end(lines, body_start)
        signature = "\n".join(lines[index : body_start + 1])
        body_lines = tuple(lines[body_start : end + 1])
        yield FunctionInfo(
            name=name,
            path=path,
            line_start=index + 1,
            line_end=end + 1,
            signature=signature,
            body_lines=body_lines,
            params=parse_params(signature),
        )
        index = end + 1


def parse_params(signature: str) -> dict[str, str]:
    start = signature.find("(")
    if start == -1:
        return {}
    end = matching_delimiter(signature, start, "(", ")")
    if end is None:
        return {}

    params: dict[str, str] = {}
    for param in split_top_level(signature[start + 1 : end]):
        param = " ".join(param.strip().split())
        if not param or param == "...":
            continue
        if param.startswith("comptime "):
            param = param.removeprefix("comptime ").strip()
        match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)", param)
        if match is None:
            continue
        params[match.group(1)] = clean_type(match.group(2))
    return params


def collect_local_types(function: FunctionInfo) -> dict[str, str]:
    local_types = dict(function.params)
    for line in function.body_lines:
        match = LOCAL_TYPE_RE.search(code_part(line))
        if match is not None:
            local_types[match.group(1)] = clean_type(match.group(2))
    return local_types


def parse_loops(function: FunctionInfo) -> Iterable[LoopUse]:
    absolute_start = function.line_start - 1
    index = 0
    while index < len(function.body_lines):
        line = function.body_lines[index]
        if "for" not in line or "|" not in "\n".join(function.body_lines[index : index + 6]):
            index += 1
            continue

        loop_text = "\n".join(function.body_lines[index : index + 8])
        match = re.search(r"for\s*\((.*?)\)\s*\|(.*?)\|", loop_text, re.S)
        if match is None:
            index += 1
            continue

        iterables = split_top_level(match.group(1))
        captures = [variable.strip() for variable in split_top_level(match.group(2))]
        loop_body_start = find_open_brace(function.body_lines, index)
        if loop_body_start is None:
            loop_body_end = index
        else:
            loop_body_end = find_block_end(function.body_lines, loop_body_start)

        body = "\n".join(function.body_lines[index : loop_body_end + 1])
        for iterable, capture in zip(iterables, captures, strict=False):
            iterable = iterable.strip()
            pointer_capture = capture.startswith("*")
            variable = capture.lstrip("*").strip()
            if not variable or variable == "_" or variable in ACCESS_WORDS:
                continue
            if iterable == "_" or iterable.endswith("..") or ".." in iterable:
                continue
            yield LoopUse(
                iterable=iterable,
                variable=variable,
                pointer_capture=pointer_capture,
                line_start=absolute_start + index + 1,
                line_end=absolute_start + loop_body_end + 1,
                body=body,
            )
        index = max(loop_body_end + 1, index + 1)


def resolve_loop_row_type(
    loop: LoopUse,
    function: FunctionInfo,
    local_types: dict[str, str],
    structs: dict[str, StructInfo],
) -> str | None:
    direct_type = local_types.get(loop.iterable)
    if direct_type is not None:
        return element_type(direct_type)

    parts = loop.iterable.split(".")
    if len(parts) >= 2:
        base_name = parts[0].strip("&* ")
        base_type = local_types.get(base_name)
        if base_type is None and base_name == "self":
            base_type = function.params.get("self")
        if base_type is not None:
            field_type = resolve_field_path(base_type, parts[1:], structs)
            if field_type is not None:
                return element_type(field_type)

    return None


def resolve_field_path(
    base_type: str,
    fields: Sequence[str],
    structs: dict[str, StructInfo],
) -> str | None:
    current = normalize_type_name(base_type)
    current_type: str | None = base_type
    for field in fields:
        struct = structs.get(current)
        if struct is None:
            return None
        field_info = next(
            (candidate for candidate in struct.fields if candidate.name == field), None
        )
        if field_info is None:
            return None
        current_type = field_info.type_name
        current = normalize_type_name(current_type)
    return current_type


def analyze_loop(
    loop: LoopUse,
    function: FunctionInfo,
    struct: StructInfo,
    *,
    min_fields: int,
    max_read_fields: int,
    min_score: int,
) -> Finding | None:
    if len(struct.fields) < min_fields:
        return None

    read_fields = tuple(sorted(field_reads(loop.variable, loop.body)))
    if not read_fields or len(read_fields) > max_read_fields:
        return None

    field_names = {field.name for field in struct.fields}
    read_field_names = tuple(field for field in read_fields if field in field_names)
    if not read_field_names or len(read_field_names) == len(struct.fields):
        return None

    unused_fields = tuple(
        field.name for field in struct.fields if field.name not in read_field_names
    )
    unused_ratio = len(unused_fields) / len(struct.fields)
    if unused_ratio < 0.45:
        return None

    cold_unused_fields = tuple(
        field.name for field in struct.fields if field.name in unused_fields and field.cold_hint
    )
    score = finding_score(
        struct,
        read_count=len(read_field_names),
        unused_ratio=unused_ratio,
        cold_unused_count=len(cold_unused_fields),
        hot_path=is_hot_path(function.path),
        pointer_capture=loop.pointer_capture,
    )
    if score < min_score:
        return None

    severity = severity_for_score(score)
    message = (
        f"{struct.name} has {len(struct.fields)} fields but this loop reads {len(read_field_names)}"
    )
    suggestion = (
        "Check whether this repeated path wants a narrower row, a column slice, "
        "or a prepared index. Keep the current shape if this loop is not hot or "
        "the fields are intentionally consumed together nearby."
    )
    return Finding(
        path=function.path,
        line_start=loop.line_start,
        line_end=loop.line_end,
        function=function.name,
        rule="ZIGDODLAYOUT",
        severity=severity,
        score=score,
        struct_name=struct.name,
        iterable=loop.iterable,
        variable=loop.variable,
        pointer_capture=loop.pointer_capture,
        field_count=len(struct.fields),
        estimated_row_bytes=struct.estimated_bytes,
        read_fields=read_field_names,
        unused_fields=unused_fields,
        cold_unused_fields=cold_unused_fields,
        message=message,
        suggestion=suggestion,
    )


def field_reads(variable: str, body: str) -> set[str]:
    escaped = re.escape(variable)
    patterns = [
        re.compile(rf"\b{escaped}\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)"),
        re.compile(rf"\b{escaped}\s*\.\*\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)"),
    ]
    reads: set[str] = set()
    for pattern in patterns:
        for match in pattern.finditer(body):
            field = match.group(1)
            if field not in ACCESS_WORDS:
                reads.add(field)
    return reads


def finding_score(
    struct: StructInfo,
    *,
    read_count: int,
    unused_ratio: float,
    cold_unused_count: int,
    hot_path: bool,
    pointer_capture: bool,
) -> int:
    score = int(unused_ratio * 65)
    score += min(20, max(0, struct.estimated_bytes - 64) // 8)
    score += min(12, cold_unused_count * 2)
    score += 10 if hot_path else 0
    score += 8 if read_count == 1 else 0
    if pointer_capture:
        score -= 15
    return min(score, 100)


def severity_for_score(score: int) -> str:
    if score >= 85:
        return "high"
    if score >= 65:
        return "medium"
    return "low"


def finding_sort_key(finding: Finding) -> tuple[int, int, str, int]:
    severity_order = {"high": 0, "medium": 1, "low": 2}
    return (
        severity_order[finding.severity],
        -finding.score,
        str(finding.path),
        finding.line_start,
    )


def should_fail(findings: Sequence[Finding], fail_on: str) -> bool:
    if fail_on == "none":
        return False
    threshold = {"low": 0, "medium": 1, "high": 2}[fail_on]
    severity_value = {"low": 0, "medium": 1, "high": 2}
    return any(severity_value[finding.severity] >= threshold for finding in findings)


def unique_struct_index(structs: Sequence[StructInfo]) -> dict[str, StructInfo]:
    by_name: dict[str, list[StructInfo]] = {}
    for struct in structs:
        by_name.setdefault(struct.name, []).append(struct)
    return {name: candidates[0] for name, candidates in by_name.items() if len(candidates) == 1}


def is_hot_path(path: Path) -> bool:
    return any(part in HOT_PATH_PARTS for part in path.parts)


def estimate_type_bytes(type_name: str) -> int:
    clean = clean_type(type_name)
    if clean.startswith("[]") or clean.startswith("[*]") or clean.startswith("[:"):
        return 16
    if clean.startswith("*"):
        return 8
    optional_clean = clean.removeprefix("?")
    if optional_clean.startswith("*"):
        return 8

    array_match = re.match(r"\[(\d+)](.+)", optional_clean)
    if array_match is not None:
        return int(array_match.group(1)) * estimate_type_bytes(array_match.group(2))

    normalized = normalize_type_name(optional_clean)
    if normalized in NUMERIC_TYPES:
        return NUMERIC_TYPES[normalized]
    if normalized.startswith("u") or normalized.startswith("i"):
        try:
            return max(1, int(normalized[1:]) // 8)
        except ValueError:
            return 8
    return 16 if "[]" in clean else 8


def is_cold_type(type_name: str, field_name: str) -> bool:
    if "[]const u8" in type_name or "[:0]const u8" in type_name:
        return True
    field_lower = field_name.lower()
    if any(word.lower() in field_lower for word in COLD_TYPE_WORDS):
        return True
    return any(word in type_name for word in COLD_TYPE_WORDS)


def element_type(type_name: str | None) -> str | None:
    if type_name is None:
        return None
    clean = clean_type(type_name)
    clean = clean.removeprefix("?").strip()

    for prefix in ("[]const ", "[]", "[*]const ", "[*]", "[:0]const ", "[:0]"):
        if clean.startswith(prefix):
            return normalize_type_name(clean.removeprefix(prefix).strip())

    array_match = re.match(r"\[\d+](.+)", clean)
    if array_match is not None:
        return normalize_type_name(array_match.group(1))

    return normalize_type_name(clean)


def normalize_type_name(type_name: str | None) -> str:
    if type_name is None:
        return ""
    clean = clean_type(type_name)
    clean = clean.removeprefix("?").strip()
    for prefix in ("*const ", "*", "[]const ", "[]", "[*]const ", "[*]"):
        if clean.startswith(prefix):
            clean = clean.removeprefix(prefix).strip()
    array_match = re.match(r"\[\d+](.+)", clean)
    if array_match is not None:
        clean = array_match.group(1).strip()
    names = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", clean)
    return names[-1] if names else clean


def clean_type(type_name: str) -> str:
    result = type_name.strip()
    result = result.removesuffix(",").strip()
    result = re.sub(r"\s+", " ", result)
    return result


def code_part(line: str) -> str:
    return line.split("//", 1)[0]


def find_open_brace(lines: Sequence[str], start: int) -> int | None:
    for index in range(start, min(len(lines), start + 40)):
        if "{" in code_part(lines[index]):
            return index
    return None


def find_block_end(lines: Sequence[str], start: int) -> int:
    depth = 0
    started = False
    for index in range(start, len(lines)):
        line = code_part(lines[index])
        if "{" in line:
            started = True
        depth += line.count("{")
        depth -= line.count("}")
        if started and depth <= 0:
            return index
    return len(lines) - 1


def matching_delimiter(text: str, start: int, open_char: str, close_char: str) -> int | None:
    depth = 0
    for index in range(start, len(text)):
        char = text[index]
        if char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return index
    return None


def split_top_level(text: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    pairs = {"(": ")", "[": "]", "{": "}"}
    closers = set(pairs.values())
    for index, char in enumerate(text):
        if char in pairs:
            depth += 1
        elif char in closers:
            depth = max(depth - 1, 0)
        elif char == "," and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    tail = text[start:].strip()
    if tail:
        parts.append(tail)
    return parts


def print_json_report(audit: Audit, findings: Sequence[Finding]) -> None:
    severity_counts = Counter(finding.severity for finding in audit.findings)
    report = {
        "schema_version": 1,
        "tool": "check-zig-dod-layout",
        "checked": [str(path) for path in audit.paths],
        "summary": {
            "finding_count": len(audit.findings),
            "shown_finding_count": len(findings),
            "struct_count": len(audit.structs),
            "function_count": len(audit.functions),
            "loops_seen": audit.loops_seen,
            "loops_analyzed": audit.loops_analyzed,
            "severity_counts": dict(sorted(severity_counts.items())),
        },
        "findings": [finding.to_json() for finding in findings],
    }
    print(json.dumps(report, indent=2, sort_keys=True))


def print_text_report(
    audit: Audit,
    findings: Sequence[Finding],
    *,
    max_findings: int,
) -> None:
    severity_counts = Counter(finding.severity for finding in audit.findings)
    print("Zig DOD layout audit (advisory)")
    print(f"checked files: {len(audit.paths)}")
    print(f"structs found: {len(audit.structs)}")
    print(f"functions found: {len(audit.functions)}")
    print(f"loops seen: {audit.loops_seen}")
    print(f"loops with resolved row type: {audit.loops_analyzed}")
    print(f"findings: {len(audit.findings)} {dict(sorted(severity_counts.items()))}")
    print()
    print(
        "This is a ranking pass, not proof of a bug. Review high-scoring loops "
        "with compiler output or a workload benchmark before changing layout."
    )

    if not findings:
        return

    print()
    print("Top findings:")
    for finding in findings:
        print()
        print(finding.render())

    if max_findings >= 0 and len(audit.findings) > len(findings):
        hidden = len(audit.findings) - len(findings)
        print()
        print(f"{hidden} more findings hidden by --max-findings={max_findings}.")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
