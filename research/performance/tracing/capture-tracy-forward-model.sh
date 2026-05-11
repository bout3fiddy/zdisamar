#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  research/performance/tracing/capture-tracy-forward-model.sh [--seconds N] [--no-open]

Tracing:
  -Denable-ztracy=true always enables the full nested forward/LABOS zone set.

Examples:
  research/performance/tracing/capture-tracy-forward-model.sh
  research/performance/tracing/capture-tracy-forward-model.sh --seconds 20 --no-open
USAGE
}

seconds=""
open_trace=1

while (($#)); do
  case "$1" in
    --seconds)
      if (($# < 2)); then
        echo "missing value for --seconds" >&2
        exit 2
      fi
      seconds="$2"
      shift 2
      ;;
    --no-open)
      open_trace=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unsupported argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$seconds" ]]; then
  seconds=20
fi

case "$seconds" in
  ''|*[!0-9]*)
    echo "--seconds must be a positive integer" >&2
    exit 2
    ;;
  0)
    echo "--seconds must be greater than zero" >&2
    exit 2
    ;;
esac

if ! command -v tracy-capture >/dev/null 2>&1; then
  echo "tracy-capture is not on PATH. Install Tracy or add its bin directory to PATH." >&2
  exit 127
fi

if ! command -v tracy-csvexport >/dev/null 2>&1; then
  echo "tracy-csvexport is not on PATH. Install Tracy or add its bin directory to PATH." >&2
  exit 127
fi

if ((open_trace)) && ! command -v tracy-profiler >/dev/null 2>&1; then
  echo "tracy-profiler is not on PATH. Install Tracy or pass --no-open." >&2
  exit 127
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
trace_root="$repo_root/research/performance/tracing/output"
capture_dir="$trace_root/captures"
run_output_dir="$trace_root/labos-bottleneck"
trace_file="$capture_dir/labos.tracy"

mkdir -p "$capture_dir" "$run_output_dir"
rm -f "$trace_file"

build_args=(
  labos-bottleneck-trace
  -Denable-ztracy=true
  -Dtrace-optimize=ReleaseFast
)

echo "capturing full Tracy run to $trace_file"
(
  cd "$repo_root"
  tracy-capture -o "$trace_file" -f -s "$seconds" &
  capture_pid=$!

  cleanup() {
    if kill -0 "$capture_pid" >/dev/null 2>&1; then
      kill "$capture_pid" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup EXIT

  sleep 0.1
  zig build "${build_args[@]}" -- --output-dir "$run_output_dir"
  wait "$capture_pid"
  trap - EXIT
)

echo "saved $trace_file"

summary_json="$run_output_dir/summary.json"
if [[ -f "$summary_json" ]]; then
  echo
  echo "run summary"
  awk -F ': ' '
    /"prepare_s"/ { prepare = $2 }
    /"forward_wall_s"/ { forward = $2 }
    END {
      gsub(/[, ]/, "", prepare)
      gsub(/[, ]/, "", forward)
      printf "  prepare_s:              %s\n", prepare
      printf "  forward_wall_s:         %s\n", forward
    }
  ' "$summary_json"
fi

echo
echo "major phases (wall-ish zones; worker totals are summed across threads)"
tracy-csvexport "$trace_file" |
  awk -F, '
    NR == 1 { next }
    $1 ~ /^(trace_cli|prepare|simulate|profile_spectroscopy_cache|forward_prefetch|wavelength_sampling|optical_prepare)/ {
      printf "%12.3f ms  %6d x  %12.3f ms mean  %s\n", $4 / 1000000, $6, $7 / 1000000, $1
    }
  ' |
  sort -nr

echo
echo "top zones by aggregate time"
tracy-csvexport "$trace_file" |
  awk -F, '
    NR == 1 { next }
    $4 >= 100000 {
      printf "%12.3f ms  %6d x  %12.3f ms mean  %s\n", $4 / 1000000, $6, $7 / 1000000, $1
    }
  ' |
  sort -nr |
  head -20

echo
echo "timeline starts"
tracy-csvexport -u "$trace_file" |
  awk -F, '
    NR == 1 { next }
    $1 ~ /^(trace_cli|prepare|simulate|profile_spectroscopy_cache|forward_prefetch|wavelength_sampling|optical_prepare)/ {
      printf "%12.3f ms start  %12.3f ms duration  thread %-4s  %s\n", $4 / 1000000, $5 / 1000000, $6, $1
    }
  ' |
  sort -n |
  head -30

if ((open_trace)); then
  tracy-profiler "$trace_file"
fi
