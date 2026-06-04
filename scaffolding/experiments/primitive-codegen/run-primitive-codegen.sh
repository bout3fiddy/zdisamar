#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
experiment_dir="$repo_root/scaffolding/experiments/primitive-codegen"
output_dir="$experiment_dir/outputs"
bench_bin="$output_dir/bench-primitives"

mkdir -p "$output_dir"

zig build-exe \
  "$experiment_dir/bench_primitives.zig" \
  -O ReleaseFast \
  -femit-bin="$bench_bin"

"$bench_bin" > "$output_dir/timings.csv" 2>&1

{
  printf 'date=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'zig=%s\n' "$(zig version)"
  printf 'uname=%s\n' "$(uname -a)"
} > "$output_dir/environment.txt"

if command -v xcrun >/dev/null 2>&1 && xcrun --find llvm-objdump >/dev/null 2>&1; then
  xcrun llvm-objdump -d --demangle "$bench_bin" > "$output_dir/bench-primitives.asm"
elif command -v llvm-objdump >/dev/null 2>&1; then
  llvm-objdump -d --demangle "$bench_bin" > "$output_dir/bench-primitives.asm"
elif command -v objdump >/dev/null 2>&1; then
  objdump -d --demangle "$bench_bin" > "$output_dir/bench-primitives.asm"
else
  printf 'no objdump-compatible disassembler found\n' >&2
  exit 1
fi

uv run "$experiment_dir/summarize_codegen.py" "$output_dir"

printf 'wrote %s\n' "$output_dir"
