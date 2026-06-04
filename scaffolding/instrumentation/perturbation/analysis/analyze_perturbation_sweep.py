#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# ///

"""Build the markdown report for the compact perturbation sweep."""

import argparse
import json
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[4]
PERTURBATION_DATA_ROOT = REPO_ROOT / "out" / "scaffolding" / "perturbation" / "data"
REPORT_PATH = Path(__file__).with_name("report.md")
DEFAULT_SUMMARY = PERTURBATION_DATA_ROOT / "o2a-default" / "summary.json"
FAST_RESULTS = REPO_ROOT / "benchmark/fast_results.json"


def parse_args() -> argparse.Namespace:

    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", type=Path, default=DEFAULT_SUMMARY)
    parser.add_argument("--report", type=Path, default=REPORT_PATH)

    return parser.parse_args()


def main() -> int:

    args = parse_args()
    summary_path = args.summary.resolve()

    with summary_path.open() as file:
        summary = json.load(file)

    fast_results = load_json(FAST_RESULTS)
    report = build_report(summary, summary_path, fast_results)
    args.report.write_text(report, encoding="utf-8")
    print(f"wrote {args.report.relative_to(REPO_ROOT)}")

    return 0


def load_json(path: Path) -> dict[str, Any] | None:

    if not path.exists():
        return None

    with path.open() as file:
        return json.load(file)


def build_report(
    summary: dict[str, Any],
    summary_path: Path,
    fast_results: dict[str, Any] | None,
) -> str:

    experiments = summary["experiments"]
    neutral = [
        row
        for row in experiments
        if row["suppression"]["changed_count"] > 0
        and row["forward"]["max_abs_reflectance_delta"] == 0.0
        and row["retrieval"]["aerosol_optical_depth_abs_delta"] == 0.0
        and row["retrieval"]["aerosol_layer_mid_pressure_abs_delta_hpa"] == 0.0
    ]
    near_neutral = [
        row
        for row in experiments
        if row["suppression"]["changed_count"] > 0
        and row["forward"]["max_abs_reflectance_delta"] <= 1.0e-6
        and row["retrieval"]["aerosol_optical_depth_abs_delta"] <= 1.0e-5
        and row["retrieval"]["aerosol_layer_mid_pressure_abs_delta_hpa"] <= 1.0e-2
    ]
    high_work = sorted(
        experiments,
        key=lambda row: row["suppression"]["changed_count"],
        reverse=True,
    )[:5]
    spectrally_sensitive = sorted(
        experiments,
        key=lambda row: row["forward"]["max_abs_reflectance_delta"],
        reverse=True,
    )[:5]
    retrieval_sensitive = sorted(
        experiments,
        key=lambda row: max(
            row["retrieval"]["aerosol_optical_depth_abs_delta"],
            row["retrieval"]["aerosol_layer_mid_pressure_abs_delta_hpa"] / 1000.0,
        ),
        reverse=True,
    )[:5]

    lines: list[str] = []
    lines.append("# Perturbation Sensitivity Analysis Report")
    lines.append("")
    lines.append("## Run")
    lines.append("")
    wavelength = summary["wavelength_range_nm"]
    lines.append(f"- Summary artifact: `{summary_path.relative_to(REPO_ROOT)}`")
    lines.append(f"- Storage policy: `{summary['storage_policy']}`")
    lines.append(
        "- Spectrum: "
        f"{wavelength['start']:.3f}-{wavelength['end']:.3f} nm, "
        f"{wavelength['sample_count']} samples"
    )
    lines.append(f"- Experiments: {len(experiments)}")
    lines.append(
        "- Baseline retrieval: "
        f"AOD={summary['baseline']['retrieved_aerosol_optical_depth']:.9e}, "
        "mid-pressure="
        f"{summary['baseline']['retrieved_aerosol_layer_mid_pressure_hpa']:.6f} hPa, "
        f"iterations={summary['baseline']['retrieval_iterations']}"
    )
    lines.append(f"- Summary file size: {summary_path.stat().st_size / 1024:.1f} KiB")
    lines.append("")
    lines.append("## Learnings")
    lines.append("")

    if neutral:
        names = ", ".join(row["name"] for row in neutral)
        lines.append(
            f"- Exact-neutral perturbations in this run: {names}. These are the first "
            "places to inspect for a real mathematical shortcut because they changed "
            "hook decisions/values without moving the final spectrum or retrieval state."
        )
    else:
        lines.append(
            "- No perturbation was exactly neutral once both spectrum and retrieval state "
            "were checked. That means the current candidates need tolerance-bounded, not "
            "zero-difference, optimization rules."
        )

    if near_neutral:
        names = ", ".join(row["name"] for row in near_neutral)
        lines.append(
            "- Near-neutral candidates under max reflectance 1e-6, AOD 1e-5, and "
            f"pressure 1e-2 hPa: {names}."
        )

    lines.append(
        "- The q-zero downstream gates are the cleanest redundancy test: they only act "
        "inside already-recognized q-series skip branches and directly count avoided "
        "matrix-product decisions."
    )
    lines.append(
        "- Forcing q-series skip itself is not safe in this run: it suppresses millions "
        "of gates, but moves reflectance by about 2.4e-3 and pressure by about 21.5 hPa."
    )
    lines.append(
        "- Stopping scattering orders too early is also visibly sensitive: order 8 still "
        "moves reflectance by about 1.4e-4 and pressure by about 1.56 hPa."
    )
    lines.append(
        "- Fourier and scattering-order perturbations are useful as threshold probes, "
        "but large residuals there mean any production optimization should be framed as "
        "a tighter convergence rule, not unconditional deletion."
    )
    lines.append(
        "- Tangent perturbations show retrieval sensitivity separately from forward "
        "reflectance sensitivity; these channels are where OE-specific pruning needs to "
        "be judged."
    )
    lines.append("")
    lines.append("## Near-Neutral Candidates")
    lines.append("")
    near_neutral_sorted = sorted(
        near_neutral,
        key=lambda row: row["suppression"]["changed_count"],
        reverse=True,
    )
    lines.extend(experiment_table(near_neutral_sorted))
    lines.append("")
    lines.append("## Highest Work Suppression")
    lines.append("")
    lines.extend(experiment_table(high_work))
    lines.append("")
    lines.append("## Largest Spectral Movement")
    lines.append("")
    lines.extend(experiment_table(spectrally_sensitive))
    lines.append("")
    lines.append("## Largest Retrieval Movement")
    lines.append("")
    lines.extend(experiment_table(retrieval_sensitive))
    lines.append("")
    lines.append("## Fast Benchmark Canary")
    lines.append("")

    if fast_results:
        cases = fast_results["cases"]
        lines.append(f"- Source: `{FAST_RESULTS.relative_to(REPO_ROOT)}`")
        lines.append(
            f"- Forward fast-mode median: {cases['forward_fast_mode']['median_total_s']:.6f} s"
        )
        lines.append(
            f"- OE session retrieval median: {cases['oe_session']['median_retrieval_s']:.6f} s"
        )
        lines.append(
            f"- OE sweep session total median: {cases['oe_sweep']['session_total_s']:.6f} s"
        )
    else:
        lines.append("- Not run yet in this report refresh.")

    lines.append("")
    lines.append("## Storage Discipline")
    lines.append("")
    lines.append(
        "The sweep writes one compact JSON summary. It does not write per-expression "
        "rows, per-wavelength residual tables, or a database. Spectra are held only long "
        "enough to compute aggregate residuals, then discarded."
    )
    lines.append("")
    lines.append("## Next Actions")
    lines.append("")
    lines.append(
        "- Promote only tolerance-stable findings into production math changes; the "
        "research hooks themselves should stay behind the compile-time build option."
    )
    lines.append(
        "- Expand the scene set after the first actionable candidate appears; the current "
        "compact schema can add scene ids without changing the product path."
    )
    lines.append("")

    return "\n".join(lines)


def experiment_table(rows: list[dict[str, Any]]) -> list[str]:

    header = (
        "| Experiment | Changed / Hit | Max abs refl delta | "
        "AOD abs delta | Pressure abs delta hPa |"
    )
    lines = [
        header,
        "| --- | ---: | ---: | ---: | ---: |",
    ]

    for row in rows:
        suppression = row["suppression"]
        forward = row["forward"]
        retrieval = row["retrieval"]
        lines.append(
            f"| `{row['name']}` | "
            f"{suppression['changed_count']} / {suppression['hit_count']} | "
            f"{forward['max_abs_reflectance_delta']:.3e} | "
            f"{retrieval['aerosol_optical_depth_abs_delta']:.3e} | "
            f"{retrieval['aerosol_layer_mid_pressure_abs_delta_hpa']:.3e} |"
        )

    return lines


if __name__ == "__main__":
    raise SystemExit(main())
