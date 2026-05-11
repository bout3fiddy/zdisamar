#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-research/performance/tracing/output/labos-bottleneck}"

zig build labos-bottleneck-trace \
  -Denable-ztracy=true \
  -Dtrace-optimize=ReleaseFast \
  -- --output-dir "$OUT"

printf 'wrote %s\n' "$OUT"
