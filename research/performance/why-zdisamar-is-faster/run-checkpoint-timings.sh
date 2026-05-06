#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

CHECKOUT="${CHECKOUT:-/tmp/zdisamar-perf-checkpoints}"
OUT="${OUT:-/tmp/zdisamar-perf-checkpoints.tsv}"
LOG_DIR="${LOG_DIR:-/tmp/zdisamar-perf-checkpoint-logs}"
MODE="${MODE:-all}"

SPEEDUP_COMMITS=(
  "5ef6c71 line_spectroscopy_and_grid"
  "b0a9e0f reusable_storage"
  "97088cf fused_doubling_math"
  "0ae1cad direct_matrix_math"
  "f42445d skip_empty_layers"
  "c423f4a fourier_tail"
  "862511b final_checkpoint"
)

EARLY_SPLIT_COMMITS=(
  "511061b first_split_timer profile_bin"
  "e23035b shared_grid_fast_intermediate profile_bin"
  "56ec761 rtm_prep_tightened profile_bin"
  "f8f495d tracked_plot_bundle profile_bin"
  "207034e spectroscopy_partition install"
)

PYTHON_BASELINE_COMMITS=(
  "163db7e python_validation_baseline"
)

fail() {
  local label="$1"
  local phase="$2"
  printf 'checkpoint %s failed during %s\n' "$label" "$phase" >&2
  printf 'logs are in %s\n' "$LOG_DIR" >&2
  exit 1
}

want_section() {
  local section="$1"
  case "$MODE" in
    all) return 0 ;;
    early) [ "$section" = "early" ] ;;
    python-baseline) [ "$section" = "python-baseline" ] ;;
    speedup) [ "$section" = "speedup" ] ;;
    *)
      printf 'unknown MODE=%s\n' "$MODE" >&2
      printf 'valid modes: all, early, python-baseline, speedup\n' >&2
      exit 1
      ;;
  esac
}

prepare_checkout() {
  local commit="$1"

  git -C "$CHECKOUT" checkout --quiet --detach "$commit"

  if [ -d "$REPO_ROOT/vendor" ]; then
    mkdir -p "$CHECKOUT/vendor"
    rsync -a --delete "$REPO_ROOT/vendor/" "$CHECKOUT/vendor/"
  fi
}

rm -rf "$CHECKOUT" "$LOG_DIR"
mkdir -p "$(dirname "$OUT")" "$LOG_DIR"

git clone --quiet --no-hardlinks "$REPO_ROOT" "$CHECKOUT" >/dev/null

if [ -d "$REPO_ROOT/vendor" ]; then
  mkdir -p "$CHECKOUT/vendor"
  rsync -a "$REPO_ROOT/vendor/" "$CHECKOUT/vendor/"
fi

printf 'checkpoint\tprepare_s\tforward_s\ttotal_s\n' > "$OUT"

if want_section "early"; then
  for entry in "${EARLY_SPLIT_COMMITS[@]}"; do
    read -r commit label build_mode <<< "$entry"

    prepare_checkout "$commit"
    output_dir="$CHECKOUT/out/perf_timeline/$label"
    rm -rf "$output_dir"

    if [ "$build_mode" = "profile_bin" ]; then
      build_command="zig build o2a-forward-profile-bin"
    else
      build_command="zig build install"
    fi
    run_command="zig-out/bin/zdisamar-o2a-forward-profile --repeat 1 --output-dir $output_dir"

    (
      cd "$CHECKOUT"
      $build_command
    ) >"$LOG_DIR/build-${label}.log" 2>&1 || fail "$label" "build"

    (
      cd "$CHECKOUT"
      $run_command
    ) >"$LOG_DIR/run-${label}.log" 2>&1 || fail "$label" "timing run"

    python3 - "$output_dir/summary.json" "$commit" "$label" "$build_command; $run_command" <<'PY' >> "$OUT"
import json
import sys

summary = json.load(open(sys.argv[1]))
print(
    f"{sys.argv[2]} {sys.argv[3]}",
    "",
    summary["total_forward_ns"]["mean_ns"] / 1.0e9,
    "",
    sep="\t",
)
PY
  done
fi

if want_section "python-baseline"; then
  for entry in "${PYTHON_BASELINE_COMMITS[@]}"; do
    read -r commit label <<< "$entry"

    prepare_checkout "$commit"
    rm -rf "$CHECKOUT/out/ci/o2a_validation_spectrum"

    build_command="zig build install"
    run_command="PYTHONPATH=$CHECKOUT uv run scripts/testing_harness/python_o2a_validation_spectrum.py"

    (
      cd "$CHECKOUT"
      $build_command
    ) >"$LOG_DIR/build-${label}.log" 2>&1 || fail "$label" "build"

    (
      cd "$CHECKOUT"
      PYTHONPATH="$CHECKOUT" uv run scripts/testing_harness/python_o2a_validation_spectrum.py
    ) >"$LOG_DIR/run-${label}.log" 2>&1 || fail "$label" "validation run"

    python3 - "$CHECKOUT/out/ci/o2a_validation_spectrum/summary.json" "$commit" "$label" "$build_command; $run_command" <<'PY' >> "$OUT"
import json
import sys

summary = json.load(open(sys.argv[1]))
prepare_s = summary["timing"]["prepare_o2a_s"]
forward_s = summary["timing"]["forward_model_s"]
print(
    f"{sys.argv[2]} {sys.argv[3]}",
    prepare_s,
    forward_s,
    prepare_s + forward_s,
    sep="\t",
)
PY
    rm -rf "$CHECKOUT/out/ci/o2a_validation_spectrum"
  done
fi

if want_section "speedup"; then
for entry in "${SPEEDUP_COMMITS[@]}"; do
  read -r commit label <<< "$entry"

  prepare_checkout "$commit"

  (
    cd "$CHECKOUT"
    zig build install
  ) >"$LOG_DIR/build-${label}.log" 2>&1 || fail "$label" "build"

  (
    cd "$CHECKOUT"
    PYTHONPATH="$CHECKOUT" uv run scripts/testing_harness/python_o2a_validation_spectrum.py
  ) >"$LOG_DIR/run-${label}.log" 2>&1 || fail "$label" "validation run"

  python3 - "$CHECKOUT/out/ci/o2a_validation_spectrum/summary.json" "$commit" "$label" "zig build install; PYTHONPATH=$CHECKOUT uv run scripts/testing_harness/python_o2a_validation_spectrum.py" <<'PY' >> "$OUT"
import json
import sys

summary = json.load(open(sys.argv[1]))
prepare_s = summary["timing"]["prepare_o2a_s"]
forward_s = summary["timing"]["forward_model_s"]
print(
    f"{sys.argv[2]} {sys.argv[3]}",
    prepare_s,
    forward_s,
    prepare_s + forward_s,
    sep="\t",
)
PY
  rm -rf "$CHECKOUT/out/ci/o2a_validation_spectrum"
done
fi

cat "$OUT"
