#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-scaffolding/instrumentation/trace/evidence/labos-bottleneck}"

zig build labos-bottleneck-trace \
  -Denable-ztracy=true \
  -Doptimize=ReleaseFast \
  -- --output-dir "$OUT"

printf 'wrote %s\n' "$OUT"
