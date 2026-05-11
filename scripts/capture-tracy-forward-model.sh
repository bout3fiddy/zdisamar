#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/capture-tracy-forward-model.sh [default|deep] [--seconds N] [--no-open]

Modes:
  default  Capture worker-level Tracy zones with low event volume.
  deep     Capture nested forward/LABOS zones and call stacks; use for short diagnostics.

Examples:
  scripts/capture-tracy-forward-model.sh
  scripts/capture-tracy-forward-model.sh deep
  scripts/capture-tracy-forward-model.sh deep --seconds 20 --no-open
USAGE
}

mode="default"
seconds=""
open_trace=1

while (($#)); do
  case "$1" in
    default|deep)
      mode="$1"
      shift
      ;;
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
  case "$mode" in
    default) seconds=15 ;;
    deep) seconds=20 ;;
  esac
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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture_dir="$repo_root/out/tracy-investigation/captures"
run_output_dir="$repo_root/out/tracy-investigation/${mode}-capture-run"
trace_file="$capture_dir/labos-${mode}.tracy"

mkdir -p "$capture_dir" "$run_output_dir"
rm -f "$trace_file"

build_args=(
  labos-bottleneck-trace
  -Denable-ztracy=true
  -Dztracy-on-demand=false
  -Dtrace-optimize=ReleaseFast
)

if [[ "$mode" == "deep" ]]; then
  build_args+=(
    -Denable-ztracy-deep=true
    -Dztracy-callstack=8
  )
fi

echo "capturing $mode Tracy run to $trace_file"
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
    /"prepare_load_inputs_s"/ { prepare_load = $2 }
    /"prepare_build_scene_s"/ { prepare_scene = $2 }
    /"prepare_optical_prepare_s"/ { prepare_optical = $2 }
    /"prepare_optical_context_init_s"/ { prepare_optical_context = $2 }
    /"prepare_optical_absorbers_build_s"/ { prepare_optical_absorbers = $2 }
    /"prepare_optical_accumulation_s"/ { prepare_optical_accumulation = $2 }
    /"prepare_optical_shared_geometry_s"/ { prepare_optical_geometry = $2 }
    /"prepare_weak_cutoff_grid_s"/ { prepare_cutoff = $2 }
    /"prepare_solar_rewindow_s"/ { prepare_solar = $2 }
    /"forward_wall_s"/ { forward = $2 }
    /"worker_count"/ { workers = $2 }
    /"high_resolution_misses"/ { misses = $2 }
    /"fourier_terms"/ { fourier = $2 }
    END {
      gsub(/[, ]/, "", prepare)
      gsub(/[, ]/, "", prepare_load)
      gsub(/[, ]/, "", prepare_scene)
      gsub(/[, ]/, "", prepare_optical)
      gsub(/[, ]/, "", prepare_optical_context)
      gsub(/[, ]/, "", prepare_optical_absorbers)
      gsub(/[, ]/, "", prepare_optical_accumulation)
      gsub(/[, ]/, "", prepare_optical_geometry)
      gsub(/[, ]/, "", prepare_cutoff)
      gsub(/[, ]/, "", prepare_solar)
      gsub(/[, ]/, "", forward)
      gsub(/[, ]/, "", workers)
      gsub(/[, ]/, "", misses)
      gsub(/[, ]/, "", fourier)
      printf "  prepare_s:              %s\n", prepare
      printf "  prepare.load_inputs_s:  %s\n", prepare_load
      printf "  prepare.build_scene_s:  %s\n", prepare_scene
      printf "  prepare.optical_s:      %s\n", prepare_optical
      printf "  prepare.opt.context_s:  %s\n", prepare_optical_context
      printf "  prepare.opt.absorbers_s:%s\n", prepare_optical_absorbers
      printf "  prepare.opt.accum_s:    %s\n", prepare_optical_accumulation
      printf "  prepare.opt.geometry_s: %s\n", prepare_optical_geometry
      printf "  prepare.cutoff_grid_s:  %s\n", prepare_cutoff
      printf "  prepare.solar_window_s: %s\n", prepare_solar
      printf "  forward_wall_s:         %s\n", forward
      printf "  worker_count:           %s\n", workers
      printf "  high_resolution_misses: %s\n", misses
      printf "  fourier_terms:          %s\n", fourier
    }
  ' "$summary_json"
fi

echo
echo "major phases (wall-ish zones; worker totals are summed across threads)"
tracy-csvexport "$trace_file" |
  awk -F, '
    NR == 1 { next }
    $1 ~ /^(trace_cli|simulate|profile_spectroscopy_cache|forward_prefetch|wavelength_sampling|optical_prepare)/ {
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
    $1 ~ /^(trace_cli|simulate|profile_spectroscopy_cache|forward_prefetch|wavelength_sampling|optical_prepare)/ {
      printf "%12.3f ms start  %12.3f ms duration  thread %-4s  %s\n", $4 / 1000000, $5 / 1000000, $6, $1
    }
  ' |
  sort -n |
  head -30

if ((open_trace)); then
  tracy-profiler "$trace_file"
fi
