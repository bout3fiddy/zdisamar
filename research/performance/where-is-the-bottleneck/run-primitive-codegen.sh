#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
BASE="$ROOT/research/performance/where-is-the-bottleneck"
OUT="$BASE/primitive-codegen/outputs"
BIN="$OUT/bench-primitives"

mkdir -p "$OUT"

zig build-exe \
  "$BASE/primitive-codegen/bench_primitives.zig" \
  -O ReleaseFast \
  -femit-bin="$BIN"

"$BIN" > "$OUT/timings.csv" 2>&1

{
  printf 'date=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'zig=%s\n' "$(zig version)"
  printf 'uname=%s\n' "$(uname -a)"
} > "$OUT/environment.txt"

if command -v xcrun >/dev/null 2>&1 && xcrun --find llvm-objdump >/dev/null 2>&1; then
  xcrun llvm-objdump -d --demangle "$BIN" > "$OUT/bench-primitives.asm"
elif command -v llvm-objdump >/dev/null 2>&1; then
  llvm-objdump -d --demangle "$BIN" > "$OUT/bench-primitives.asm"
elif command -v objdump >/dev/null 2>&1; then
  objdump -d --demangle "$BIN" > "$OUT/bench-primitives.asm"
else
  printf 'no objdump-compatible disassembler found\n' >&2
  exit 1
fi

uv run "$BASE/primitive-codegen/summarize_codegen.py" "$OUT"

printf 'wrote %s\n' "$OUT"
