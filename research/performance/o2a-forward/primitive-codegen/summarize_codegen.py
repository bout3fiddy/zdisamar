#!/usr/bin/env python3
"""Summarize the retained primitive-codegen timing and disassembly outputs."""

import csv
import re
import sys
from collections import Counter
from pathlib import Path

SYMBOL_GROUPS = {
    "codegen_smul12x10": ["codegen_smul12x10"],
    "codegen_smul_add_semul3_12": [
        "codegen_smul_add_semul3_12",
        "bench_primitives.smulAddSemul3_12",
        "bench_primitives.smulAddSemul3_12KnownTraces",
    ],
    "codegen_smul_add_semul3_known_right_trace_12": [
        "codegen_smul_add_semul3_known_right_trace_12",
        "bench_primitives.smulAddSemul3_12KnownRightTrace",
        "bench_primitives.smulAddSemul3_12KnownTraces",
    ],
    "codegen_qseries_nonzero_12x10": [
        "codegen_qseries_nonzero_12x10",
        "bench_primitives.qseriesFromProduct",
    ],
    "codegen_dot_gauss_pair": ["codegen_dot_gauss_pair"],
}

PRIMITIVES = [
    ("smul_12x10", "codegen_smul12x10"),
    ("smul_add_semul3_12", "codegen_smul_add_semul3_12"),
    (
        "smul_add_semul3_known_right_trace_12",
        "codegen_smul_add_semul3_known_right_trace_12",
    ),
    ("qseries_nonzero_12x10", "codegen_qseries_nonzero_12x10"),
    ("dot_gauss_pair", "codegen_dot_gauss_pair"),
]

LABEL_RE = re.compile(r"^[0-9a-fA-F]+ <([^>]+)>:")

FP_PREFIXES = (
    "fadd",
    "fsub",
    "fmul",
    "fdiv",
    "fmadd",
    "fmla",
    "fnmadd",
    "addsd",
    "subsd",
    "mulsd",
    "divsd",
    "vadd",
    "vsub",
    "vmul",
    "vdiv",
    "vfma",
    "vfmadd",
)
DIV_PREFIXES = ("fdiv", "divsd", "divpd", "vdiv")
LOAD_STORE_PREFIXES = ("ldr", "ldp", "str", "stp", "ld1", "st1", "mov", "vmov")
BRANCH_PREFIXES = ("b", "bl", "ret", "j", "call")


def normalize_symbol(name: str) -> str:

    name = name.strip()

    if name.startswith("_"):
        name = name[1:]

    return name


def split_sections(asm_text: str) -> dict[str, list[str]]:

    symbol_set = {symbol for symbols in SYMBOL_GROUPS.values() for symbol in symbols}
    sections: dict[str, list[str]] = {}
    current: str | None = None

    for line in asm_text.splitlines():
        label = LABEL_RE.match(line)

        if label:
            symbol = normalize_symbol(label.group(1))
            current = symbol if symbol in symbol_set else None

        if current is not None:
            sections.setdefault(current, []).append(line)

    return sections


def parse_instruction(line: str) -> str | None:

    if ":" not in line:
        return None

    _, body = line.split(":", 1)
    parts = body.split()

    while parts and re.fullmatch(r"[0-9a-fA-F]{2,8}", parts[0]):
        parts.pop(0)

    if not parts:
        return None

    mnemonic = parts[0].lower()

    if not re.match(r"[a-z.][a-z0-9_.]*$", mnemonic):
        return None

    return mnemonic


def instruction_mix(lines: list[str]) -> dict[str, int]:

    mnemonics = [mnemonic for line in lines if (mnemonic := parse_instruction(line))]
    counts = Counter(mnemonics)

    return {
        "instructions": len(mnemonics),
        "fp_arithmetic": sum(
            count for mnemonic, count in counts.items() if mnemonic.startswith(FP_PREFIXES)
        ),
        "fp_divide": sum(
            count for mnemonic, count in counts.items() if mnemonic.startswith(DIV_PREFIXES)
        ),
        "load_store_move": sum(
            count for mnemonic, count in counts.items() if mnemonic.startswith(LOAD_STORE_PREFIXES)
        ),
        "branch_call_ret": sum(
            count for mnemonic, count in counts.items() if mnemonic.startswith(BRANCH_PREFIXES)
        ),
    }


def read_timings(path: Path) -> list[dict[str, str]]:

    rows: list[dict[str, str]] = []

    with path.open(newline="") as handle:
        filtered = (line for line in handle if not line.startswith("#"))

        for row in csv.DictReader(filtered):
            rows.append(row)

    return rows


def render_table(headers: list[str], rows: list[list[str]]) -> str:

    widths = [
        max(len(headers[idx]), *(len(row[idx]) for row in rows)) for idx in range(len(headers))
    ]
    out = [
        "| " + " | ".join(header.ljust(widths[idx]) for idx, header in enumerate(headers)) + " |",
        "| " + " | ".join("-" * width for width in widths) + " |",
    ]

    for row in rows:
        out.append(
            "| " + " | ".join(value.ljust(widths[idx]) for idx, value in enumerate(row)) + " |"
        )

    return "\n".join(out)


def main() -> int:

    if len(sys.argv) != 2:
        print("usage: summarize_codegen.py <outputs-dir>", file=sys.stderr)

        return 2

    out_dir = Path(sys.argv[1])
    timings = read_timings(out_dir / "timings.csv")
    asm_text = (out_dir / "bench-primitives.asm").read_text()
    sections = split_sections(asm_text)

    mixes: dict[str, dict[str, int]] = {}

    for group, symbols in SYMBOL_GROUPS.items():
        lines: list[str] = []

        for symbol in symbols:
            if symbol in sections:
                lines.extend(sections[symbol])
                lines.append("")

        (out_dir / f"{group}.asm").write_text("\n".join(lines).rstrip() + "\n")
        mixes[group] = instruction_mix(lines)

    timing_rows = [
        [
            row["operation"],
            f"{int(row['iterations']):,}",
            f"{int(row['elapsed_ns']):,}",
            f"{float(row['ns_per_call']):.3f}",
            f"{float(row['checksum']):.6g}",
        ]
        for row in timings
    ]
    mix_rows = [
        [
            symbol,
            str(mix["instructions"]),
            str(mix["fp_arithmetic"]),
            str(mix["fp_divide"]),
            str(mix["load_store_move"]),
            str(mix["branch_call_ret"]),
        ]
        for symbol, mix in mixes.items()
    ]
    timing_by_operation = {row["operation"]: row for row in timings}
    total_ns_per_call = sum(
        float(timing_by_operation[operation]["ns_per_call"]) for operation, _ in PRIMITIVES
    )
    total_static_instructions = sum(mixes[symbol]["instructions"] for _, symbol in PRIMITIVES)
    instruction_cost_rows = []

    for operation, symbol in PRIMITIVES:
        ns_per_call = float(timing_by_operation[operation]["ns_per_call"])
        static_instructions = mixes[symbol]["instructions"]
        ns_per_static_instruction = ns_per_call / static_instructions
        instruction_cost_rows.append(
            [
                operation,
                f"{ns_per_call:.3f}",
                f"{static_instructions:,}",
                f"{ns_per_static_instruction:.4f}",
                f"{100.0 * ns_per_call / total_ns_per_call:.2f}%",
                f"{100.0 * static_instructions / total_static_instructions:.2f}%",
            ]
        )

    summary = "\n".join(
        [
            "# Primitive Codegen Summary",
            "",
            "Generated from the retained research-only primitive-codegen measurements.",
            (
                "The harness mirrors the fixed 12x10 LABOS primitive shapes with "
                "deterministic mock matrices; it is not linked into the forward model."
            ),
            "",
            "## Timing",
            "",
            render_table(
                ["operation", "iterations", "elapsed ns", "ns/call", "checksum"],
                timing_rows,
            ),
            "",
            "## Disassembly Instruction Mix",
            "",
            render_table(
                [
                    "symbol",
                    "instructions",
                    "fp arithmetic",
                    "fp divide",
                    "load/store/move",
                    "branch/call/ret",
                ],
                mix_rows,
            ),
            "",
            "## Instruction-Level Orientation",
            "",
            (
                "Instruction counts here are static disassembly counts for the "
                "extracted symbol/callee group, not dynamic retired-instruction "
                "counts. `ns/static instr` is a reading aid for this retained "
                "harness run, not a CPU throughput claim."
            ),
            "",
            render_table(
                [
                    "operation",
                    "ns/call",
                    "static instr",
                    "ns/static instr",
                    "% isolated call time",
                    "% static instr",
                ],
                instruction_cost_rows,
            ),
            "",
            "## Reading",
            "",
            (
                "- `smul_12x10` and `smul_add_semul3_12` are mostly straight-line "
                "multiply-add work over the fixed 12x10 shape."
            ),
            (
                "- `qseries_nonzero_12x10` is much heavier per call because it "
                "includes the 12x10 product plus a 10x10 pivoted solve and the "
                "extra block products."
            ),
            (
                "- `dot_gauss_pair` is tiny per call, but it matters in the full "
                "run because the trace counts hundreds of millions of calls."
            ),
            (
                "- Read these numbers as code-generation evidence for the primitive "
                "shapes, not as a replacement for the full LABOS trace."
            ),
            "",
        ]
    )
    (out_dir / "codegen-summary.md").write_text(summary)
    print(f"wrote {out_dir / 'codegen-summary.md'}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
