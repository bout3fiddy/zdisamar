#!/usr/bin/env python3
"""Require a blank line before Python control-flow statement blocks."""

import ast
import sys
from collections.abc import Iterable, Sequence
from pathlib import Path

CONTROL_STATEMENTS = (
    ast.If,
    ast.For,
    ast.AsyncFor,
    ast.While,
    ast.Try,
    ast.TryStar,
    ast.With,
    ast.AsyncWith,
    ast.Match,
)

SPACED_BEFORE_STATEMENTS = (
    *CONTROL_STATEMENTS,
    ast.Return,
)


def main(argv: Sequence[str]) -> int:

    findings = [
        finding for path in argv if path.endswith(".py") for finding in check_path(Path(path))
    ]

    if findings:
        print("Python control-flow spacing violations:")

        for finding in findings:
            print(finding)

        return 1

    return 0


def check_path(path: Path) -> list[str]:

    source = path.read_text(encoding="utf-8")
    lines = source.splitlines()

    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        return [f"{path}:{exc.lineno}: PYCONTROLSPACING could not parse Python file"]

    return list(check_block(path, lines, tree.body))


def check_block(path: Path, lines: list[str], body: Sequence[ast.stmt]) -> Iterable[str]:

    for previous, statement in zip(body, body[1:], strict=False):
        if isinstance(statement, SPACED_BEFORE_STATEMENTS) and not has_blank_line_between(
            lines,
            previous,
            statement,
        ):
            yield (
                f"{path}:{statement.lineno}: PYCONTROLSPACING "
                f"add a blank line before this {statement_name(statement)} statement"
            )

        if isinstance(previous, CONTROL_STATEMENTS) and not has_blank_line_between(
            lines,
            previous,
            statement,
        ):
            yield (
                f"{path}:{statement.lineno}: PYCONTROLSPACING "
                f"add a blank line after the preceding {statement_name(previous)} block"
            )

    for statement in body:
        if isinstance(statement, ast.FunctionDef | ast.AsyncFunctionDef):
            yield from check_function_body_start(path, lines, statement)

        yield from check_nested_blocks(path, lines, statement)


def check_function_body_start(
    path: Path,
    lines: list[str],
    statement: ast.FunctionDef | ast.AsyncFunctionDef,
) -> Iterable[str]:

    if is_ellipsis_stub(statement):
        return

    first_real_statement = first_non_docstring_statement(statement)

    if first_real_statement is None:
        return

    if first_real_statement.lineno == statement.lineno:
        yield (
            f"{path}:{statement.lineno}: PYCONTROLSPACING put this function body on its own line"
        )

        return

    if has_blank_line_after_function_header(lines, statement, first_real_statement):
        return

    yield (
        f"{path}:{first_real_statement.lineno}: PYCONTROLSPACING "
        "add a blank line before this function body statement"
    )


def first_non_docstring_statement(
    statement: ast.FunctionDef | ast.AsyncFunctionDef,
) -> ast.stmt | None:

    body = statement.body

    if (
        body
        and isinstance(body[0], ast.Expr)
        and isinstance(body[0].value, ast.Constant)
        and isinstance(body[0].value.value, str)
    ):
        body = body[1:]

    return body[0] if body else None


def statement_name(statement: ast.stmt) -> str:

    if isinstance(statement, ast.If):
        return "if"

    if isinstance(statement, ast.For):
        return "for"

    if isinstance(statement, ast.AsyncFor):
        return "async for"

    if isinstance(statement, ast.While):
        return "while"

    if isinstance(statement, ast.Try | ast.TryStar):
        return "try"

    if isinstance(statement, ast.With):
        return "with"

    if isinstance(statement, ast.AsyncWith):
        return "async with"

    if isinstance(statement, ast.Match):
        return "match"

    if isinstance(statement, ast.Return):
        return "return"

    return type(statement).__name__


def is_ellipsis_stub(statement: ast.FunctionDef | ast.AsyncFunctionDef) -> bool:

    if len(statement.body) != 1:
        return False

    body_statement = statement.body[0]

    return (
        isinstance(body_statement, ast.Expr)
        and isinstance(body_statement.value, ast.Constant)
        and body_statement.value.value is Ellipsis
    )


def check_nested_blocks(path: Path, lines: list[str], statement: ast.stmt) -> Iterable[str]:

    for child_body in child_statement_bodies(statement):
        yield from check_block(path, lines, child_body)


def child_statement_bodies(statement: ast.stmt) -> Iterable[Sequence[ast.stmt]]:

    for field_name in ("body", "orelse", "finalbody"):
        child_body = getattr(statement, field_name, None)

        if child_body:
            yield child_body

    if isinstance(statement, ast.Try | ast.TryStar):
        for handler in statement.handlers:
            if handler.body:
                yield handler.body

    if isinstance(statement, ast.Match):
        for case in statement.cases:
            if case.body:
                yield case.body


def has_blank_line_between(lines: list[str], previous: ast.stmt, statement: ast.stmt) -> bool:

    previous_end_lineno = previous.end_lineno

    if previous_end_lineno is None:
        previous_end_lineno = previous.lineno

    between = lines[previous_end_lineno : statement.lineno - 1]

    return any(line.strip() == "" for line in between)


def has_blank_line_after_function_header(
    lines: list[str],
    statement: ast.FunctionDef | ast.AsyncFunctionDef,
    first_body_statement: ast.stmt,
) -> bool:

    between = lines[statement.lineno : first_body_statement.lineno - 1]

    return any(line.strip() == "" for line in between)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
