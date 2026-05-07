#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-validation/outputs/performance/labos-bottleneck}"

zig build labos-bottleneck-trace -- --output-dir "$OUT"
zig build bench > "$OUT/labos_kernel_bench.txt" 2>&1
uv run validation/performance/labos_bottleneck_summarize.py

printf 'wrote %s\n' "$OUT"
