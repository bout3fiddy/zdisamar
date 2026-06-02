#!/usr/bin/env python3
"""Flag Zig readability problems covered by the project style guide."""

import argparse
import json
import re
import sys
from collections import Counter
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

FN_RE = re.compile(r"\b(?:pub\s+)?(?:inline\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)\b")
CONTROL_RE = re.compile(r"\b(if|for|while|switch)\s*\(")
EARLY_EXIT_RE = re.compile(r"\b(return|continue|break)\b")
BRANCH_RE = re.compile(r"\b(else|orelse|catch)\b")
ASSIGN_IF_RE = re.compile(r"=\s*if\s*\(")
VALUE_BLOCK_RE = re.compile(r"(?:=|orelse)\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\{")
FORBIDDEN_COMMENT_LABEL_RE = re.compile(
    r"\b(Purpose|Data|Flow|Boundary|Provenance)\s*:",
    re.IGNORECASE,
)
GENERIC_VALUE_BLOCK_LABELS = {
    "blk",
    "block",
    "choice",
    "result",
    "tmp",
    "value",
}


@dataclass(frozen=True)
class Finding:
    path: Path
    line_start: int
    line_end: int
    rule: str
    severity: str
    category: str
    message: str
    metrics: dict[str, int]
    suggestions: tuple[str, ...]
    performance_safety: tuple[str, ...] = ()
    details: dict[str, object] | None = None

    def render(self) -> str:

        location = f"{self.path}:{self.line_start}"

        if self.line_end != self.line_start:
            location = f"{self.path}:{self.line_start}-{self.line_end}"

        return f"{location}: {self.rule} {self.message}"

    def to_json(self) -> dict[str, object]:

        result: dict[str, object] = {
            "path": str(self.path),
            "line_start": self.line_start,
            "line_end": self.line_end,
            "rule": self.rule,
            "severity": self.severity,
            "category": self.category,
            "message": self.message,
            "metrics": self.metrics,
            "suggestions": list(self.suggestions),
            "performance_safety": list(self.performance_safety),
        }

        if self.details is not None:
            result["details"] = self.details

        return result


@dataclass(frozen=True)
class Paragraph:
    start_line: int
    end_line: int
    lines: tuple[str, ...]


@dataclass(frozen=True)
class IfAssignment:
    name: str
    line_start: int
    line_end: int
    conditions: tuple[str, ...]


def main(argv: Sequence[str]) -> int:

    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", help="Zig files or directories to check")
    parser.add_argument("--min-lines", type=int, default=10)
    parser.add_argument("--min-score", type=int, default=7)
    parser.add_argument("--min-if-expression-lines", type=int, default=5)
    parser.add_argument(
        "--max-line-length",
        type=int,
        default=120,
        help="Warn when non-box lines exceed this width. Use 0 to disable.",
    )
    parser.add_argument("--format", choices=("json", "text"), default="json")
    parser.add_argument(
        "--strict-value-blocks",
        action="store_true",
        help="Treat generic labels on value-returning blocks as hard findings.",
    )
    parser.add_argument(
        "--strict-functions",
        action="store_true",
        help="Require a function box as the first statement inside each function.",
    )
    args = parser.parse_args(argv)

    findings = [
        finding
        for path in zig_paths(args.paths)
        for finding in check_path(
            path,
            min_lines=args.min_lines,
            min_score=args.min_score,
            min_if_expression_lines=args.min_if_expression_lines,
            max_line_length=args.max_line_length,
            strict_value_blocks=args.strict_value_blocks,
            strict_functions=args.strict_functions,
        )
    ]

    if findings:
        if args.format == "json":
            print_json_report(args.paths, findings)
        else:
            print("Zig styleguide violations:")

            for finding in findings:
                print(finding.render())

        return 1

    if args.format == "json":
        print_json_report(args.paths, findings)

    return 0


def print_json_report(raw_paths: Sequence[str], findings: Sequence[Finding]) -> None:

    rule_counts = Counter(finding.rule for finding in findings)
    severity_counts = Counter(finding.severity for finding in findings)
    category_counts = Counter(finding.category for finding in findings)
    report = {
        "schema_version": 1,
        "tool": "check-zig-styleguide",
        "checked": list(raw_paths),
        "summary": {
            "finding_count": len(findings),
            "category_counts": dict(sorted(category_counts.items())),
            "rule_counts": dict(sorted(rule_counts.items())),
            "severity_counts": dict(sorted(severity_counts.items())),
        },
        "findings": [finding.to_json() for finding in findings],
    }
    print(json.dumps(report, indent=2, sort_keys=True))


def zig_paths(raw_paths: Sequence[str]) -> Iterable[Path]:

    for raw_path in raw_paths:
        path = Path(raw_path)

        if path.is_dir():
            yield from sorted(
                child
                for child in path.rglob("*")
                if child.suffix in {".zig", ".zon"} and not is_ignored_path(child)
            )
        elif path.suffix in {".zig", ".zon"} and not is_ignored_path(path):
            yield path


def is_ignored_path(path: Path) -> bool:

    ignored_parts = {".git", ".zig-cache", "zig-out", "vendor", "out"}

    return any(part in ignored_parts for part in path.parts)


def check_path(
    path: Path,
    *,
    min_lines: int,
    min_score: int,
    min_if_expression_lines: int,
    max_line_length: int,
    strict_value_blocks: bool,
    strict_functions: bool,
) -> Iterable[Finding]:

    lines = path.read_text(encoding="utf-8").splitlines()

    yield from check_comment_shape(path, lines)
    yield from check_function_header_comments(path, lines)
    yield from check_instrumentation_spacing(path, lines)
    yield from check_box_rails(path, lines)
    yield from check_line_lengths(path, lines, max_line_length=max_line_length)
    yield from check_dense_paragraphs(path, lines, min_lines=min_lines, min_score=min_score)
    yield from check_dense_if_expressions(
        path,
        lines,
        min_if_expression_lines=min_if_expression_lines,
    )
    yield from check_parallel_decisions(path, lines)
    yield from check_value_block_labels(path, lines, strict_value_blocks=strict_value_blocks)

    if strict_functions:
        yield from check_function_boxes(path, lines)


def check_comment_shape(path: Path, lines: Sequence[str]) -> Iterable[Finding]:

    for index, line in enumerate(lines):
        line_number = index + 1
        stripped = line.strip()

        if stripped == "//":
            yield Finding(
                path=path,
                line_start=line_number,
                line_end=line_number,
                rule="ZIGCOMMENT",
                severity="warning",
                category="mechanical",
                message="bare // spacer comment",
                metrics={},
                suggestions=("Remove the spacer comment and use a blank line.",),
            )
            continue

        if not stripped.startswith("//"):
            continue

        if is_box_line(line):
            continue

        if FORBIDDEN_COMMENT_LABEL_RE.search(stripped):
            yield Finding(
                path=path,
                line_start=line_number,
                line_end=line_number,
                rule="ZIGCOMMENT",
                severity="warning",
                category="mechanical",
                message="label-style comment wording",
                metrics={},
                suggestions=("Rewrite the line as plain explanation without a label prefix.",),
            )

        if index == 0:
            continue

        previous = lines[index - 1]

        if previous.strip() == "" or previous.strip().startswith("//"):
            continue

        yield Finding(
            path=path,
            line_start=line_number,
            line_end=line_number,
            rule="ZIGCOMMENTSPACE",
            severity="warning",
            category="readability",
            message="explanatory comment is packed against code",
            metrics={},
            suggestions=("Add one blank line before the comment.",),
            performance_safety=("Whitespace and comments do not affect compiler output.",),
        )


def check_function_header_comments(path: Path, lines: Sequence[str]) -> Iterable[Finding]:

    for index, line in enumerate(lines):
        if FN_RE.search(strip_line_comment(line)) is None:
            continue

        if index == 0:
            continue

        previous = lines[index - 1]

        if not previous.lstrip().startswith("//"):
            continue

        yield Finding(
            path=path,
            line_start=index,
            line_end=index + 1,
            rule="ZIGFNCOMMENT",
            severity="warning",
            category="mechanical",
            message="comment sits immediately above a function definition",
            metrics={},
            suggestions=(
                "Move the comment into the function box as the first body statement.",
                "Leave a blank line before fn only when the previous comment "
                "belongs to another block.",
            ),
            performance_safety=("Moving comments does not affect compiler output.",),
        )


def check_instrumentation_spacing(path: Path, lines: Sequence[str]) -> Iterable[Finding]:

    for index, line in enumerate(lines):
        stripped = line.strip()

        if (
            stripped.startswith("// instrumentation:")
            and index > 0
            and lines[index - 1].strip() != ""
        ):
            yield Finding(
                path=path,
                line_start=index + 1,
                line_end=index + 1,
                rule="ZIGINSTRUMENTSPACE",
                severity="warning",
                category="readability",
                message="instrumentation header is packed against previous code",
                metrics={},
                suggestions=("Add one blank line before the instrumentation header.",),
                performance_safety=("Whitespace and comments do not affect compiler output.",),
            )

        if (
            stripped.startswith("// end instrumentation:")
            and index + 1 < len(lines)
            and lines[index + 1].strip() != ""
        ):
            yield Finding(
                path=path,
                line_start=index + 1,
                line_end=index + 2,
                rule="ZIGINSTRUMENTSPACE",
                severity="warning",
                category="readability",
                message="instrumentation footer is packed against following code",
                metrics={},
                suggestions=("Add one blank line after the instrumentation footer.",),
                performance_safety=("Whitespace and comments do not affect compiler output.",),
            )


def check_line_lengths(
    path: Path,
    lines: Sequence[str],
    *,
    max_line_length: int,
) -> Iterable[Finding]:

    if max_line_length <= 0:
        return

    for index, line in enumerate(lines):
        line_number = index + 1
        stripped = line.rstrip()

        if len(stripped) <= max_line_length:
            continue

        if is_box_line(stripped):
            continue

        if "http://" in stripped or "https://" in stripped:
            continue

        line_kind = "comment" if stripped.lstrip().startswith("//") else "code"
        yield Finding(
            path=path,
            line_start=line_number,
            line_end=line_number,
            rule="ZIGLINELENGTH",
            severity="warning",
            category="readability",
            message=f"{line_kind} line exceeds {max_line_length} columns",
            metrics={"length": len(stripped), "max_length": max_line_length},
            suggestions=(
                "Wrap calls with one important argument per line.",
                "Split long conditions into named booleans or a named value block.",
                "Shorten value-block labels when break :label makes a line too wide.",
            ),
            performance_safety=(
                "Line wrapping does not change generated code.",
                "Do not move guards or calls while wrapping the line.",
            ),
        )


def check_box_rails(path: Path, lines: Sequence[str]) -> Iterable[Finding]:

    rail_lengths = [len(line) for line in lines if is_box_line(line)]

    if not rail_lengths:
        return

    expected_length = Counter(rail_lengths).most_common(1)[0][0]

    previous_was_box_line = False

    for index, line in enumerate(lines):
        line_number = index + 1

        if not is_box_line(line):
            previous_was_box_line = False
            continue

        if len(line) != expected_length:
            yield Finding(
                path=path,
                line_start=line_number,
                line_end=line_number,
                rule="ZIGBOXRAIL",
                severity="warning",
                category="mechanical",
                message="right rail is not aligned with the file's main box rail",
                metrics={"actual_column": len(line), "expected_column": expected_length},
                suggestions=("Adjust spaces before the final | so the rail lines up.",),
            )

        if not previous_was_box_line and not is_box_header_or_fence(line):
            yield Finding(
                path=path,
                line_start=line_number,
                line_end=line_number,
                rule="ZIGBOXHEADER",
                severity="warning",
                category="mechanical",
                message="first line of a box does not carry the dashed title rail",
                metrics={},
                suggestions=("Make the first box line look like // name ----|.",),
            )

        previous_was_box_line = True


def check_dense_paragraphs(
    path: Path,
    lines: Sequence[str],
    *,
    min_lines: int,
    min_score: int,
) -> Iterable[Finding]:

    for paragraph in paragraphs(lines):
        metrics = density_metrics(paragraph.lines)
        score = metrics["score"]

        if len(paragraph.lines) >= min_lines and score >= min_score:
            yield Finding(
                path=path,
                line_start=paragraph.start_line,
                line_end=paragraph.end_line,
                rule="ZIGDENSITY",
                severity="warning",
                category="readability",
                message="dense code paragraph",
                metrics={"code_lines": len(paragraph.lines), **metrics},
                suggestions=(
                    "Add blank lines between setup, guards, branch choice, loops, "
                    "and output writes.",
                    "Name branch conditions when an if expression starts hiding the reason.",
                    "Split a calculation when a single paragraph mixes guards, "
                    "cache choice, and math.",
                ),
                performance_safety=(
                    "Preserve guard order.",
                    "Do not compute values before guards just to make the code look nicer.",
                    "Prefer local consts or blk expressions before helper extraction.",
                    "If extracting a helper from a hot path, verify codegen or benchmark.",
                ),
            )


def check_dense_if_expressions(
    path: Path,
    lines: Sequence[str],
    *,
    min_if_expression_lines: int,
) -> Iterable[Finding]:

    for start_index, line in enumerate(lines):
        if not ASSIGN_IF_RE.search(strip_line_comment(line)):
            continue

        expression_lines = expression_until_semicolon(lines, start_index)
        expression_text = "\n".join(strip_line_comment(item) for item in expression_lines)
        nested_if_count = len(re.findall(r"\bif\s*\(", expression_text))
        early_exit_count = len(EARLY_EXIT_RE.findall(expression_text))
        branch_count = len(BRANCH_RE.findall(expression_text))
        call_line_count = count_call_argument_lines(expression_lines)
        is_mostly_wrapped_calls = (
            nested_if_count == 1
            and early_exit_count == 0
            and len(expression_lines) >= min_if_expression_lines
            and call_line_count >= len(expression_lines) // 2
        )

        if (
            len(expression_lines) >= min_if_expression_lines
            or nested_if_count > 1
            or early_exit_count
        ):
            severity = "info" if is_mostly_wrapped_calls else "warning"
            category = "advisory" if is_mostly_wrapped_calls else "readability"
            message = (
                "long assigned if-expression"
                if is_mostly_wrapped_calls
                else "if-expression is doing too much inside an assignment"
            )
            yield Finding(
                path=path,
                line_start=start_index + 1,
                line_end=start_index + len(expression_lines),
                rule="ZIGIFEXPR",
                severity=severity,
                category=category,
                message=message,
                metrics={
                    "lines": len(expression_lines),
                    "nested_if_count": nested_if_count,
                    "branch_count": branch_count,
                    "early_exit_count": early_exit_count,
                    "call_line_count": call_line_count,
                },
                suggestions=(
                    "Move the branch into a named boolean or a small block.",
                    "Avoid return or nested if inside an assigned if expression.",
                ),
                performance_safety=(
                    "Keep the same short-circuit behavior.",
                    "Do not move expensive calls before the branch that guards them.",
                    "Prefer local consts or blk expressions before helper extraction.",
                ),
            )


def check_parallel_decisions(path: Path, lines: Sequence[str]) -> Iterable[Finding]:

    assignments = assigned_if_expressions(lines)

    for group in nearby_assignment_groups(assignments):
        if len(group) < 2:
            continue

        condition_to_names: dict[str, list[str]] = {}

        for assignment in group:
            for condition in assignment.conditions:
                condition_to_names.setdefault(condition, []).append(assignment.name)

        shared_conditions = {
            condition: names
            for condition, names in condition_to_names.items()
            if len(set(names)) >= 2
        }

        if not shared_conditions:
            continue

        line_start = group[0].line_start
        line_end = group[-1].line_end
        repeated_condition_count = sum(len(set(names)) for names in shared_conditions.values())

        yield Finding(
            path=path,
            line_start=line_start,
            line_end=line_end,
            rule="ZIGPARALLELDECISION",
            severity="warning",
            category="readability",
            message="nearby assigned if-expressions repeat route-selection logic",
            metrics={
                "assigned_if_count": len(group),
                "shared_condition_count": len(shared_conditions),
                "repeated_condition_count": repeated_condition_count,
            },
            details={
                "assignments": [assignment.name for assignment in group],
                "shared_conditions": {
                    condition: sorted(set(names))
                    for condition, names in sorted(shared_conditions.items())
                },
            },
            suggestions=(
                "Name repeated route conditions once.",
                "Group route selection into a local blk when several outputs share it.",
                "Keep the original branch order.",
            ),
            performance_safety=(
                "Preserve short-circuit order.",
                "Do not compute a value before the guard that used to protect it.",
                "Prefer local consts or blk expressions before helper extraction.",
            ),
        )


def check_value_block_labels(
    path: Path,
    lines: Sequence[str],
    *,
    strict_value_blocks: bool,
) -> Iterable[Finding]:

    for start_index, line in enumerate(lines):
        match = VALUE_BLOCK_RE.search(strip_line_comment(line))

        if match is None:
            continue

        label = match.group(1)

        if label not in GENERIC_VALUE_BLOCK_LABELS:
            continue

        end_index = find_block_end_index(lines, start_index)
        block_lines = lines[start_index : end_index + 1]
        block_text = "\n".join(strip_line_comment(item) for item in block_lines)
        code_line_count = sum(
            1
            for item in block_lines
            if strip_line_comment(item).strip()
            and not strip_line_comment(item).lstrip().startswith("//")
        )
        break_count = len(re.findall(rf"\bbreak\s*:{re.escape(label)}\b", block_text))
        control_count = len(CONTROL_RE.findall(block_text))
        nontrivial = code_line_count >= 5 or break_count >= 2 or control_count > 0

        if not strict_value_blocks and not nontrivial:
            continue

        yield Finding(
            path=path,
            line_start=start_index + 1,
            line_end=end_index + 1,
            rule="ZIGBLOCKNAME",
            severity="error" if strict_value_blocks else "warning",
            category="readability",
            message=f"generic value-block label `{label}`",
            metrics={
                "code_lines": code_line_count,
                "break_count": break_count,
                "control_count": control_count,
            },
            details={"label": label},
            suggestions=(
                "Rename the label after the choice the block makes.",
                "Use labels such as choose_phase_limit, build_phase_rows, or load_cached_value.",
                "Keep the break targets matching the label.",
            ),
            performance_safety=(
                "Renaming a Zig block label does not change generated code.",
                "Do not move guards or calls while renaming the label.",
            ),
        )


def check_function_boxes(path: Path, lines: Sequence[str]) -> Iterable[Finding]:

    index = 0

    while index < len(lines):
        line = lines[index]
        match = FN_RE.search(line)

        if match is None:
            index += 1
            continue

        fn_name = match.group(1)
        open_brace_index = find_function_open_brace(lines, index)

        if open_brace_index is None:
            index += 1
            continue

        first_body_index = next_nonblank_index(lines, open_brace_index + 1)

        if first_body_index is None:
            index = open_brace_index + 1
            continue

        first_body_line = lines[first_body_index]

        if not is_box_header_or_fence(first_body_line):
            yield Finding(
                path=path,
                line_start=first_body_index + 1,
                line_end=first_body_index + 1,
                rule="ZIGFNBOX",
                severity="info",
                category="advisory",
                message=f"{fn_name} does not start with an inside-the-body function box",
                metrics={},
                suggestions=(
                    "Put the function map inside the body, immediately after the opening brace.",
                ),
            )

        index = open_brace_index + 1


def paragraphs(lines: Sequence[str]) -> Iterable[Paragraph]:

    start_line: int | None = None
    paragraph_lines: list[str] = []

    for line_number, line in enumerate(lines, start=1):
        if line.strip() == "":
            if paragraph_lines and start_line is not None:
                yield Paragraph(start_line, line_number - 1, tuple(paragraph_lines))

            start_line = None
            paragraph_lines = []
            continue

        if is_comment_only(line):
            continue

        if start_line is None:
            start_line = line_number

        paragraph_lines.append(strip_line_comment(line))

    if paragraph_lines and start_line is not None:
        yield Paragraph(start_line, len(lines), tuple(paragraph_lines))


def density_metrics(lines: Sequence[str]) -> dict[str, int]:

    control_count = 0
    branch_count = 0
    early_exit_count = 0
    assigned_if_count = 0
    single_line_guard_count = 0

    for line in lines:
        control_count += len(CONTROL_RE.findall(line))
        branch_count += len(BRANCH_RE.findall(line))
        early_exit_count += len(EARLY_EXIT_RE.findall(line))

        if ASSIGN_IF_RE.search(line):
            assigned_if_count += 1

        if is_single_line_guard(line):
            single_line_guard_count += 1

    score = (
        control_count
        + branch_count
        + early_exit_count
        + (2 * assigned_if_count)
        + single_line_guard_count
    )

    return {
        "score": score,
        "control_count": control_count,
        "branch_count": branch_count,
        "early_exit_count": early_exit_count,
        "assigned_if_count": assigned_if_count,
        "single_line_guard_count": single_line_guard_count,
    }


def expression_until_semicolon(lines: Sequence[str], start_index: int) -> list[str]:

    expression_lines: list[str] = []

    for line in lines[start_index:]:
        expression_lines.append(line)

        if strip_line_comment(line).strip().endswith(";"):
            break

        if len(expression_lines) >= 40:
            break

    return expression_lines


def assigned_if_expressions(lines: Sequence[str]) -> list[IfAssignment]:

    assignments: list[IfAssignment] = []

    for start_index, line in enumerate(lines):
        if not ASSIGN_IF_RE.search(strip_line_comment(line)):
            continue

        expression_lines = expression_until_semicolon(lines, start_index)
        assignment_name = assigned_const_name(line)

        if assignment_name is None:
            assignment_name = f"<line {start_index + 1}>"

        conditions = tuple(
            condition
            for expression_line in expression_lines
            for condition in extract_if_conditions(strip_line_comment(expression_line))
        )

        if not conditions:
            continue

        assignments.append(
            IfAssignment(
                name=assignment_name,
                line_start=start_index + 1,
                line_end=start_index + len(expression_lines),
                conditions=conditions,
            )
        )

    return assignments


def nearby_assignment_groups(
    assignments: Sequence[IfAssignment],
) -> Iterable[tuple[IfAssignment, ...]]:

    group: list[IfAssignment] = []

    for assignment in assignments:
        if not group:
            group = [assignment]
            continue

        if assignment.line_start - group[-1].line_end <= 4:
            group.append(assignment)
            continue

        yield tuple(group)
        group = [assignment]

    if group:
        yield tuple(group)


def assigned_const_name(line: str) -> str | None:

    match = re.search(r"\bconst\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", strip_line_comment(line))

    if match is None:
        return None

    return match.group(1)


def extract_if_conditions(line: str) -> list[str]:

    conditions: list[str] = []
    search_from = 0

    while True:
        if_index = line.find("if (", search_from)

        if if_index == -1:
            break

        condition_start = if_index + len("if (")
        condition_end = matching_paren_index(line, condition_start - 1)

        if condition_end is None:
            break

        condition = normalize_condition(line[condition_start:condition_end])

        if condition:
            conditions.append(condition)

        search_from = condition_end + 1

    return conditions


def matching_paren_index(line: str, open_paren_index: int) -> int | None:

    depth = 0

    for index in range(open_paren_index, len(line)):
        char = line[index]

        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1

            if depth == 0:
                return index

    return None


def normalize_condition(condition: str) -> str:

    return " ".join(condition.strip().split())


def count_call_argument_lines(lines: Sequence[str]) -> int:

    count = 0

    for line in lines:
        stripped = strip_line_comment(line).strip()

        if not stripped:
            continue

        if stripped in {"else", "null;", "0.0;", "};"}:
            continue

        if stripped.startswith(("if ", "else if ", "return ", "break ", "continue ")):
            continue

        if stripped.endswith(",") or stripped.endswith(")") or stripped.endswith(");"):
            count += 1

    return count


def find_function_open_brace(lines: Sequence[str], start_index: int) -> int | None:

    for index in range(start_index, min(len(lines), start_index + 30)):
        if "{" in strip_line_comment(lines[index]):
            return index

    return None


def find_block_end_index(lines: Sequence[str], start_index: int) -> int:

    depth = 0
    seen_open = False

    for index in range(start_index, len(lines)):
        line = strip_line_comment(lines[index])

        for char in line:
            if char == "{":
                depth += 1
                seen_open = True
            elif char == "}":
                depth -= 1

                if seen_open and depth == 0:
                    return index

    return start_index


def next_nonblank_index(lines: Sequence[str], start_index: int) -> int | None:

    for index in range(start_index, len(lines)):
        if lines[index].strip():
            return index

    return None


def is_single_line_guard(line: str) -> bool:

    stripped = line.strip()

    return stripped.startswith("if ") and (
        " return " in f" {stripped} " or " continue" in stripped or " break" in stripped
    )


def is_comment_only(line: str) -> bool:

    return line.lstrip().startswith("//")


def is_box_line(line: str) -> bool:

    stripped = line.rstrip()

    return stripped.lstrip().startswith("// ") and stripped.endswith("|")


def is_box_header_or_fence(line: str) -> bool:

    stripped = line.rstrip()

    return is_box_line(line) and "----" in stripped


def strip_line_comment(line: str) -> str:

    comment_start = line.find("//")

    return line if comment_start == -1 else line[:comment_start]


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
