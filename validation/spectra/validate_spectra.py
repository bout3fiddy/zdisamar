#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "altair>=5.5",
#   "vl-convert-python>=1.7",
#   "numpy>=2.2",
#   "pandas>=2.2",
# ]
# ///

import math
import sys
from pathlib import Path
from typing import TypedDict

import altair as alt  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(REPO_ROOT), str(REPO_ROOT / "python")]

import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from numpy.typing import NDArray  # noqa: E402
from zdisamar import rtm  # noqa: E402
from zdisamar.plot.properties import PLOT  # noqa: E402
from zdisamar.wavelength_bands import o2a  # noqa: E402

from validation.common.paths import stable_repo_path, write_json  # noqa: E402
from validation.o2a import baseline as oe_baseline  # noqa: E402
from validation.o2a.case import build_o2a_jacobian_case  # noqa: E402
from validation.spectra.residuals import residual_blowup_regions, residual_metrics  # noqa: E402

VALIDATION_DIR = REPO_ROOT / "validation"
SPECTRA_DIR = VALIDATION_DIR / "spectra"
REFERENCE_DATA_DIR = VALIDATION_DIR / "reference_data" / "spectra"
OUTPUTS_DIR = VALIDATION_DIR / "outputs" / "spectra"

RADIANCE_REFERENCE_PATH = REFERENCE_DATA_DIR / "o2a_jacobian_retrieval_instrument_forward.csv"
REFLECTANCE_JACOBIAN_REFERENCE_PATH = (
    REFERENCE_DATA_DIR / "o2a_jacobian_simulation_instrument_reflectance.csv"
)

PLOT_PATH = OUTPUTS_DIR / "o2a_validation.png"
DATA_PATH = OUTPUTS_DIR / "o2a_validation_data.csv"
METRICS_PATH = OUTPUTS_DIR / "comparison_metrics.json"
MANIFEST_PATH = OUTPUTS_DIR / "bundle_manifest.json"

CANONICAL_COMMAND = "uv run validation/spectra/validate_spectra.py"
REFLECTANCE_THRESHOLD = 1.0e-13
THRESHOLD_EDGE_EXCLUSION_COUNT = 1
STATE_NAMES = (
    "aerosol_optical_depth",
    "aerosol_layer_mid_pressure_hpa",
)
REFERENCE_COLUMNS = {
    "aerosol_optical_depth": "aerosolTau",
    "aerosol_layer_mid_pressure_hpa": "intervalDP",
}
BLOWUP_REGION_FRACTION = 0.40
BLOWUP_REGION_PADDING_NM = 0.04
BLOWUP_REGION_LIMITS = {
    "RTM reflectance": 3,
    "dR/d aerosol optical depth": 3,
    "dR/d aerosol layer mid pressure": 2,
}

FloatArray = NDArray[np.float64]
ResidualRegion = dict[str, float]


class ValidationSeries(TypedDict):
    series: str
    y_label: str
    zdisamar: FloatArray
    reference: FloatArray


class MetricRow(TypedDict):
    max_abs_residual: float
    max_abs_wavelength_nm: float
    rmse: float
    mean_signed: float
    series: str
    full_grid_max_abs_residual: float
    full_grid_max_abs_wavelength_nm: float
    threshold_excluded_edge_samples_per_side: int
    marked_residual_blowup_regions_nm: list[ResidualRegion]


def run_zdisamar_validation(case) -> dict[str, np.ndarray]:

    spectrum = rtm.spectrum(case, jacobian=True, jacobian_state_names=STATE_NAMES)
    wavelength_nm = np.asarray(spectrum.wavelength_nm, dtype=np.float64).copy()
    reflectance = np.asarray(spectrum.reflectance, dtype=np.float64).copy()
    state_names = spectrum.jacobian_state_names
    reflectance_jacobian = np.column_stack(
        [spectrum.reflectance_jacobian(state_name) for state_name in STATE_NAMES]
    )

    if tuple(state_names) != STATE_NAMES:
        raise RuntimeError(f"unexpected Jacobian states: {state_names}")

    return {
        "wavelength_nm": wavelength_nm,
        "reflectance": reflectance,
        "reflectance_jacobian": reflectance_jacobian,
    }


def mid_pressure_jacobian_scale(case) -> float:

    from zdisamar.optimal_estimation import o2a as o2a_oe

    profile = o2a_oe.pressure_altitude_profile_from_scene(case)

    aerosol_mid_pressure_hpa = 0.5 * (
        case.aerosol.placement.top_pressure_hpa + case.aerosol.placement.bottom_pressure_hpa
    )

    return profile.altitude_derivative_at_pressure(aerosol_mid_pressure_hpa)


def build_validation_rows(
    case, current: dict[str, np.ndarray], pressure_jacobian_scale: float
) -> tuple[pd.DataFrame, list[MetricRow]]:

    radiance_reference = pd.read_csv(RADIANCE_REFERENCE_PATH)
    jacobian_reference = pd.read_csv(REFLECTANCE_JACOBIAN_REFERENCE_PATH)
    wavelength_nm = current["wavelength_nm"]
    mu0 = math.cos(math.radians(case.geometry.solar_zenith_deg))

    rows: list[ValidationSeries] = [
        {
            "series": "RTM reflectance",
            "y_label": "Reflectance",
            "zdisamar": current["reflectance"],
            "reference": np.interp(
                wavelength_nm,
                radiance_reference["wavelength_nm"],
                radiance_reference["sun_normalized_radiance"],
            )
            * np.pi
            / mu0,
        },
    ]
    jacobian_labels = {
        "aerosol_optical_depth": (
            "dR/d aerosol optical depth",
            "dR/d aerosol\noptical depth",
        ),
        "aerosol_layer_mid_pressure_hpa": (
            "dR/d aerosol layer mid pressure",
            "dR/d aerosol layer\nmid pressure",
        ),
    }

    for state_index, state_name in enumerate(STATE_NAMES):
        series_label, y_label = jacobian_labels[state_name]
        reference_values = np.interp(
            wavelength_nm,
            jacobian_reference["wavelength_nm"],
            jacobian_reference[REFERENCE_COLUMNS[state_name]],
        )
        zdisamar_values = current["reflectance_jacobian"][:, state_index]

        if state_name == "aerosol_layer_mid_pressure_hpa":
            reference_values = reference_values * pressure_jacobian_scale
            zdisamar_values = zdisamar_values * pressure_jacobian_scale

        rows.append(
            {
                "series": series_label,
                "y_label": y_label,
                "zdisamar": zdisamar_values,
                "reference": reference_values,
            }
        )

    records = []
    metrics = []
    threshold_slice = slice(
        THRESHOLD_EDGE_EXCLUSION_COUNT,
        len(wavelength_nm) - THRESHOLD_EDGE_EXCLUSION_COUNT,
    )

    for row in rows:
        residual = row["zdisamar"] - row["reference"]
        residual_metric = residual_metrics(
            wavelength_nm[threshold_slice], residual[threshold_slice]
        )
        full_grid_metric = residual_metrics(wavelength_nm, residual)
        metric: MetricRow = {
            "max_abs_residual": residual_metric["max_abs_residual"],
            "max_abs_wavelength_nm": residual_metric["max_abs_wavelength_nm"],
            "rmse": residual_metric["rmse"],
            "mean_signed": residual_metric["mean_signed"],
            "series": row["series"],
            "full_grid_max_abs_residual": full_grid_metric["max_abs_residual"],
            "full_grid_max_abs_wavelength_nm": full_grid_metric["max_abs_wavelength_nm"],
            "threshold_excluded_edge_samples_per_side": THRESHOLD_EDGE_EXCLUSION_COUNT,
            "marked_residual_blowup_regions_nm": residual_blowup_regions(
                wavelength_nm,
                residual,
                fraction=BLOWUP_REGION_FRACTION,
                padding_nm=BLOWUP_REGION_PADDING_NM,
                limit=BLOWUP_REGION_LIMITS[row["series"]],
                min_wavelength_nm=oe_baseline.WAVELENGTH_START_NM,
                max_wavelength_nm=oe_baseline.WAVELENGTH_END_NM,
            ),
        }
        metrics.append(metric)

        for wavelength, reference, zdisamar, value_residual in zip(
            wavelength_nm,
            row["reference"],
            row["zdisamar"],
            residual,
            strict=False,
        ):
            records.append(
                {
                    "wavelength_nm": float(wavelength),
                    "series": row["series"],
                    "y_label": row["y_label"],
                    "kind": "reference",
                    "value": float(reference),
                    "residual": 0.0,
                }
            )
            records.append(
                {
                    "wavelength_nm": float(wavelength),
                    "series": row["series"],
                    "y_label": row["y_label"],
                    "kind": "zdisamar",
                    "value": float(zdisamar),
                    "residual": float(value_residual),
                }
            )

    return pd.DataFrame.from_records(records), metrics


def create_validation_plot(data: pd.DataFrame, output_path: Path) -> None:

    series_order = list(dict.fromkeys(data["series"]))
    rows = []

    for row_index, series in enumerate(series_order):
        row_data = data[data["series"] == series]
        zdisamar = row_data[row_data["kind"] == "zdisamar"]
        y_label = str(zdisamar["y_label"].iloc[0])
        blowup_regions = residual_blowup_regions(
            zdisamar["wavelength_nm"].to_numpy(dtype=np.float64),
            zdisamar["residual"].to_numpy(dtype=np.float64),
            fraction=BLOWUP_REGION_FRACTION,
            padding_nm=BLOWUP_REGION_PADDING_NM,
            limit=BLOWUP_REGION_LIMITS[series],
            min_wavelength_nm=755.0,
            max_wavelength_nm=776.0,
        )
        regions = pd.DataFrame.from_records(blowup_regions)
        series_title = series if row_index == 0 else f"{series}"
        x = alt.X(
            "wavelength_nm:Q",
            title="Wavelength (nm)",
            scale=alt.Scale(
                domain=[oe_baseline.WAVELENGTH_START_NM, oe_baseline.WAVELENGTH_END_NM],
                zero=False,
            ),
        )
        region_rect = (
            alt.Chart(regions)
            .mark_rect(color=PLOT.colors["red"], opacity=0.08)
            .encode(x="start_nm:Q", x2="end_nm:Q")
            if not regions.empty
            else alt.Chart(pd.DataFrame({"start_nm": []})).mark_rect()
        )
        peak_rules = (
            alt.Chart(regions)
            .mark_rule(color=PLOT.colors["red"], opacity=0.50, strokeDash=[1, 3])
            .encode(x="peak_nm:Q")
            if not regions.empty
            else alt.Chart(pd.DataFrame({"peak_nm": []})).mark_rule()
        )
        values = (
            alt.layer(
                region_rect,
                peak_rules,
                alt.Chart(row_data)
                .mark_line()
                .encode(
                    x=x,
                    y=alt.Y(
                        "value:Q",
                        title=y_label.replace("\n", " "),
                        axis=alt.Axis(format=".4g"),
                        scale=alt.Scale(zero=False),
                    ),
                    color=alt.Color(
                        "kind:N",
                        title=None,
                        scale=alt.Scale(
                            domain=["reference", "zdisamar"],
                            range=[PLOT.colors["blue"], PLOT.colors["orange"]],
                        ),
                    ),
                    strokeDash=alt.StrokeDash(
                        "kind:N",
                        title=None,
                        scale=alt.Scale(domain=["reference", "zdisamar"], range=[[1, 0], [5, 4]]),
                    ),
                    tooltip=[
                        alt.Tooltip("wavelength_nm:Q", title="Wavelength (nm)", format=".4f"),
                        alt.Tooltip("kind:N", title="Series"),
                        alt.Tooltip("value:Q", title="Value", format=".8g"),
                    ],
                ),
            )
            .properties(width=620, height=190, title=series_title)
            .resolve_scale(color="independent", strokeDash="independent")
        )
        residual_zero = (
            alt.Chart(pd.DataFrame({"zero": [0.0]}))
            .mark_rule(color=PLOT.colors["black"], strokeDash=[4, 3], strokeWidth=0.75)
            .encode(y="zero:Q")
        )
        residual = alt.layer(
            region_rect,
            peak_rules,
            residual_zero,
            alt.Chart(zdisamar)
            .mark_line(color=PLOT.colors["black"], strokeWidth=1.15)
            .encode(
                x=x,
                y=alt.Y(
                    "residual:Q",
                    title="zdisamar - reference",
                    axis=alt.Axis(format=".3e"),
                    scale=alt.Scale(zero=False),
                ),
                tooltip=[
                    alt.Tooltip("wavelength_nm:Q", title="Wavelength (nm)", format=".4f"),
                    alt.Tooltip("residual:Q", title="Residual", format=".8g"),
                ],
            ),
        ).properties(width=500, height=190, title="Residual")
        rows.append(alt.hconcat(values, residual, spacing=28))

    chart = alt.vconcat(*rows, spacing=18).properties(
        title="O2A validation against DISAMAR reference"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    chart.save(output_path, scale_factor=4.0)


def write_metrics(metrics: list[MetricRow], output_path: Path) -> None:

    payload = {
        "schema_version": 2,
        "sample_count": oe_baseline.SAMPLE_COUNT,
        "wavelength_min_nm": oe_baseline.WAVELENGTH_START_NM,
        "wavelength_max_nm": oe_baseline.WAVELENGTH_END_NM,
        "reflectance_threshold": REFLECTANCE_THRESHOLD,
        "threshold_domain": {
            "description": (
                "The pass/fail threshold applies to the interior instrument grid; "
                "the first and last samples are slit-convolution boundary samples "
                "and remain plotted plus reported as full-grid residuals."
            ),
            "excluded_edge_samples_per_side": THRESHOLD_EDGE_EXCLUSION_COUNT,
        },
        "passes_reflectance_threshold": all(
            float(metric["max_abs_residual"]) <= REFLECTANCE_THRESHOLD for metric in metrics
        ),
        "series": metrics,
        "reference_paths": {
            "radiance": stable_repo_path(RADIANCE_REFERENCE_PATH),
            "reflectance_jacobian": stable_repo_path(REFLECTANCE_JACOBIAN_REFERENCE_PATH),
        },
    }
    write_json(output_path, payload)


def write_manifest(output_path: Path) -> None:

    tracked_outputs = [
        PLOT_PATH,
        DATA_PATH,
        METRICS_PATH,
        MANIFEST_PATH,
    ]
    manifest = {
        "schema_version": 2,
        "canonical_command": CANONICAL_COMMAND,
        "tracked_output_dir": stable_repo_path(SPECTRA_DIR),
        "tracked_outputs": [stable_repo_path(path) for path in tracked_outputs],
        "reference_paths": [
            stable_repo_path(RADIANCE_REFERENCE_PATH),
            stable_repo_path(REFLECTANCE_JACOBIAN_REFERENCE_PATH),
        ],
        "policy": {
            "validation_case": "hardcoded_o2a_jacobian_reference",
            "note": (
                "The tracked O2 A validation plot is generated by the "
                "Python API and compares zdisamar reflectance plus "
                "reflectance Jacobians against committed DISAMAR reference "
                "derivatives. Thresholds apply to the interior instrument "
                "grid; slit-convolution edge samples are reported separately."
            ),
        },
    }
    write_json(output_path, manifest)


def build_bundle(
    output_dir: Path = SPECTRA_DIR,
) -> list[MetricRow]:

    if output_dir != SPECTRA_DIR:
        raise ValueError("validate_spectra is intentionally hardwired to validation/spectra/")

    case = build_o2a_jacobian_case(o2a)
    oe_baseline.configure_case(case)
    pressure_jacobian_scale = mid_pressure_jacobian_scale(case)
    current = run_zdisamar_validation(case)
    data, metrics = build_validation_rows(case, current, pressure_jacobian_scale)

    output_dir.mkdir(parents=True, exist_ok=True)
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    data.to_csv(DATA_PATH, index=False)
    create_validation_plot(data, PLOT_PATH)
    write_metrics(metrics, METRICS_PATH)
    write_manifest(MANIFEST_PATH)

    return metrics


def validate_outputs(metrics: list[MetricRow]) -> list[str]:

    failures: list[str] = []

    for path in (PLOT_PATH, DATA_PATH, METRICS_PATH, MANIFEST_PATH):
        if not path.exists():
            failures.append(f"missing generated output: {stable_repo_path(path)}")

    if len(metrics) != 3:
        failures.append(f"expected 3 validation series, got {len(metrics)}")

    if [metric["series"] for metric in metrics] != [
        "RTM reflectance",
        "dR/d aerosol optical depth",
        "dR/d aerosol layer mid pressure",
    ]:
        failures.append("unexpected validation series order")

    for metric in metrics:
        if float(metric["max_abs_residual"]) > REFLECTANCE_THRESHOLD:
            failures.append(
                f"{metric['series']} max_abs_residual "
                f"{float(metric['max_abs_residual']):.3e} exceeds "
                f"{REFLECTANCE_THRESHOLD:.3e}"
            )

    for path in (METRICS_PATH, MANIFEST_PATH):
        if "/Users/" in path.read_text():
            failures.append(f"absolute user path leaked into {stable_repo_path(path)}")

    return failures


def main() -> int:

    metrics = build_bundle()
    failures = validate_outputs(metrics)

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)

        return 1

    worst = max(metrics, key=lambda row: float(row["max_abs_residual"]))
    print(
        "o2a_validation="
        f"{stable_repo_path(PLOT_PATH)} max_abs={float(worst['max_abs_residual']):.3e} "
        f"series={worst['series']}"
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
