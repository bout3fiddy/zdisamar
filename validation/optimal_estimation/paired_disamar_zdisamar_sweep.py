#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "altair>=5.5",
#   "vl-convert-python>=1.7",
#   "numpy>=2.2",
#   "pandas>=2.2",
#   "polars>=1.35",
# ]
# ///

import json
import math
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any, cast

import altair as alt
import pandas as pd
import polars as pl

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
OUTPUT_ROOT = REPO_ROOT / "out" / "validation" / "optimal_estimation" / "paired_disamar_zdisamar"
ROWS_DIR = OUTPUT_ROOT / "rows"
FORTRAN_CASES_DIR = OUTPUT_ROOT / "fortran_cases"
SCENES_PATH = OUTPUT_ROOT / "paired_retrieval_scenes.parquet"
PARQUET_PATH = OUTPUT_ROOT / "paired_retrieval_runs.parquet"
SUMMARY_PATH = OUTPUT_ROOT / "paired_retrieval_summary.json"
DISAMAR_TEMPLATE = (
    REPO_ROOT / "validation" / "reference_data" / "optimal_estimation" / "baseline_config.in"
)
DISAMAR_EXE = REPO_ROOT / "vendor" / "disamar-fortran" / "src" / "Disamar.exe"
DISAMAR_REFSPEC = REPO_ROOT / "vendor" / "disamar-fortran" / "RefSpec"
TRACKED_OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
RETRIEVED_PLOT_PATH = TRACKED_OUTPUTS_DIR / "paired_oe_retrieved_scatter.png"
ERROR_HISTOGRAM_PATH = TRACKED_OUTPUTS_DIR / "paired_oe_error_histograms.png"
LATENCY_PLOT_PATH = TRACKED_OUTPUTS_DIR / "paired_oe_latency.png"
MANIFEST_PATH = TRACKED_OUTPUTS_DIR / "paired_oe_plot_manifest.json"
FAST_MODE_SUMMARY_PATH = (
    TRACKED_OUTPUTS_DIR / "zdisamar_o2a_fast_mode_sweep_comparison_summary.json"
)

sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

import zdisamar as zd  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402
from zdisamar.plot.properties import PLOT  # noqa: E402

from validation.common.paths import stable_repo_path, write_json  # noqa: E402
from validation.o2a import baseline as oe_baseline  # noqa: E402
from validation.o2a.case import build_o2a_case  # noqa: E402
from validation.o2a.measurement_noise import (  # noqa: E402
    measurement_from_o2a_baseline_noise,
)
from validation.optimal_estimation import reference_cases as oe_cases  # noqa: E402
from validation.optimal_estimation import setup as oe_setup  # noqa: E402

type ScalarValue = bool | int | float | str

RUN_COUNT = oe_cases.run_count()
SCENE_SAMPLE_COUNT = oe_cases.scene_sample_count()
BATCH_SIZE = 10
RNG_SEED = oe_cases.seed()
DISAMAR_WORKERS = max(1, min(BATCH_SIZE, os.cpu_count() or 2))
ZDISAMAR_WORKERS = 1
WAVELENGTH_START_NM = oe_baseline.WAVELENGTH_START_NM
WAVELENGTH_END_NM = oe_baseline.WAVELENGTH_END_NM
WAVELENGTH_STEP_NM = oe_baseline.WAVELENGTH_STEP_NM
DISAMAR_PRESSURE_PRIOR_VARIANCE = 150.0**2
DISAMAR_CASE_TIMEOUT_S = 5400.0
FLOAT_TOKEN_PATTERN = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[EDed][+-]?\d+)?")
MODEL_LABELS = {
    "disamar_fortran": "DISAMAR Fortran",
    "zdisamar": "zdisamar",
    "zdisamar_fast": "zdisamar-fast",
}
MODEL_COLORS = [PLOT.colors["blue"], PLOT.colors["orange"], PLOT.colors["red"]]
MODEL_MARKERS = {
    "DISAMAR Fortran": "circle",
    "zdisamar": "cross",
    "zdisamar-fast": "square",
}


def retrieve_zdisamar(
    *,
    index: int,
    scene: dict[str, float],
    initial: dict[str, float],
) -> dict[str, Any]:
    base = build_o2a_case(zd, jacobian_reference_layer=True)
    oe_baseline.configure_case(base)
    case = oe_setup.build_scene(base, index=index, id_prefix="paired_oe", scene=scene, id_width=4)
    start = time.perf_counter()
    try:
        with zd.prepare(case) as prepared:
            measurement = measurement_from_o2a_baseline_noise(prepared)
            profile = o2a_oe.pressure_altitude_profile_from_prepared(prepared)
        state_vector = oe_setup.aerosol_two_state_vector(
            initial=initial,
            profile=profile,
            surface_pressure_hpa=scene["surface_pressure_hpa"],
        )
        with zd.o2a_forward_session(case) as session:
            result = o2a_oe.disamar_oe(
                inverse_model=o2a_oe.O2AInverseForwardModel(
                    case,
                    forward_session=session,
                ),
                measurement=measurement,
                state_vector=state_vector,
                controls=oe_setup.retrieval_controls(),
            )
        retrieved_aod = result.value("aerosol_optical_depth")
        retrieved_mid_pressure = result.value("aerosol_layer_mid_pressure_hpa")
        return {
            "model": "zdisamar",
            "status": "ok",
            "converged": bool(result.converged),
            "iterations": int(result.iterations),
            "retrieval_s": time.perf_counter() - start,
            "retrieved_aerosol_optical_depth": retrieved_aod,
            "retrieved_aerosol_mid_pressure_hpa": retrieved_mid_pressure,
            "error": "",
        }
    except Exception as exc:  # noqa: BLE001 - recorded as validation evidence.
        return {
            "model": "zdisamar",
            "status": "error",
            "converged": False,
            "iterations": 0,
            "retrieval_s": time.perf_counter() - start,
            "retrieved_aerosol_optical_depth": math.nan,
            "retrieved_aerosol_mid_pressure_hpa": math.nan,
            "error": repr(exc),
        }


def config_line(key: str, values: str) -> str:
    return f"{key:<32} {values}\n"


def render_disamar_config(scene: dict[str, float], initial: dict[str, float]) -> str:
    truth_top, truth_bottom = oe_setup.layer_bounds(scene["aerosol_mid_pressure_hpa"])
    initial_top, initial_bottom = oe_setup.layer_bounds(initial["aerosol_mid_pressure_hpa"])
    lines = DISAMAR_TEMPLATE.read_text().splitlines(keepends=True)
    rendered: list[str] = []
    section = ""
    subsection = ""
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("SECTION "):
            section = stripped.split(maxsplit=2)[1]
            subsection = ""
        elif stripped.startswith("subsection "):
            subsection = stripped.split(maxsplit=2)[1]

        key = stripped.split(maxsplit=1)[0] if stripped and not stripped.startswith("#") else ""
        if section == "GENERAL" and key == "simulationOnly":
            rendered.append(config_line(key, "0"))
        elif section == "INSTRUMENT" and key == "wavelength_start":
            rendered.append(config_line(key, f"{WAVELENGTH_START_NM:.2f}"))
        elif section == "INSTRUMENT" and key == "wavelength_end":
            rendered.append(config_line(key, f"{WAVELENGTH_END_NM:.2f}"))
        elif section == "INSTRUMENT" and key == "wavelength_step":
            rendered.append(config_line(key, f"{WAVELENGTH_STEP_NM:.2f}"))
        elif section == "GEOMETRY" and key in {
            "solar_zenith_angle_sim",
            "solar_zenith_angle_retr",
        }:
            rendered.append(config_line(key, f"{scene['solar_zenith_deg']:.8f}d0"))
        elif section == "GEOMETRY" and key in {
            "instrument_nadir_angle_sim",
            "instrument_nadir_angle_retr",
        }:
            rendered.append(config_line(key, f"{scene['viewing_zenith_deg']:.8f}d0"))
        elif section == "GEOMETRY" and key in {
            "solar_azimuth_angle_sim",
            "solar_azimuth_angle_retr",
        }:
            rendered.append(config_line(key, f"{scene['relative_azimuth_deg']:.8f}d0"))
        elif section == "GEOMETRY" and key in {
            "instrument_azimuth_angle_sim",
            "instrument_azimuth_angle_retr",
        }:
            rendered.append(config_line(key, "0.00000000d0"))
        elif section == "SURFACE" and key in {"surfPressureSim", "surfPressureRetr"}:
            rendered.append(config_line(key, f"{scene['surface_pressure_hpa']:.8f}"))
        elif section == "SURFACE" and key == "wavelSurfAlbedo":
            rendered.append(
                config_line(
                    key,
                    " ".join(
                        f"{wavelength:.1f}"
                        for wavelength in oe_baseline.SURFACE_ALBEDO_WAVELENGTHS_NM
                    ),
                )
            )
        elif section == "SURFACE" and key == "surfAlbedo":
            rendered.append(
                config_line(
                    key,
                    " ".join(
                        f"{scene['surface_albedo']:.8f}"
                        for _ in oe_baseline.SURFACE_ALBEDO_WAVELENGTHS_NM
                    ),
                )
            )
        elif section == "ATMOSPHERIC_INTERVALS" and key == "topPressureSim":
            rendered.append(config_line(key, f"{truth_bottom:.8f} {truth_top:.8f} 0.3"))
        elif section == "ATMOSPHERIC_INTERVALS" and key == "topPressureRetr":
            rendered.append(config_line(key, f"{initial_bottom:.8f} {initial_top:.8f} 0.3"))
        elif section == "ATMOSPHERIC_INTERVALS" and key == "APvarianceTopPressure":
            rendered.append(
                config_line(
                    key,
                    f"{DISAMAR_PRESSURE_PRIOR_VARIANCE:.8f} "
                    f"{DISAMAR_PRESSURE_PRIOR_VARIANCE:.8f} 1.0E-4",
                )
            )
        elif section == "AEROSOL" and subsection == "HGscatteringSim" and key == "opticalThickness":
            rendered.append(config_line(key, f"2 {scene['aerosol_optical_depth']:.10f}"))
        elif (
            section == "AEROSOL" and subsection == "HGscatteringRetr" and key == "opticalThickness"
        ):
            rendered.append(config_line(key, f"2 {initial['aerosol_optical_depth']:.10f} 0.8"))
        elif section == "AEROSOL" and key == "singleScatteringAlbedo":
            rendered.append(config_line(key, f"2 {oe_baseline.AEROSOL_SINGLE_SCATTER_ALBEDO:.10f}"))
        elif section == "AEROSOL" and key == "angstromCoefficient":
            rendered.append(config_line(key, f"2 {oe_baseline.AEROSOL_ANGSTROM_EXPONENT:.10f}"))
        elif section == "AEROSOL" and key == "HGparameter_g":
            rendered.append(config_line(key, f"2 {oe_baseline.AEROSOL_ASYMMETRY_FACTOR:.10f}"))
        else:
            rendered.append(line)
    return "".join(rendered)


def parse_scalar(text: str, name: str, default: ScalarValue = math.nan) -> ScalarValue:
    match = re.search(rf"^{re.escape(name)}\s*=\s*(.+?)\s*$", text, re.MULTILINE)
    if not match:
        return default
    value = match.group(1).strip()
    if value.lower() in {"true", "false"}:
        return value.lower() == "true"
    try:
        return int(value)
    except ValueError:
        try:
            return float(value.replace("D", "E").replace("d", "E"))
        except ValueError:
            return value


def parse_array(text: str, name: str) -> list[float]:
    begin = re.search(rf"BeginArray\({re.escape(name)},\s*float64\)", text)
    if not begin:
        raise ValueError(f"missing DISAMAR asciiHDF array {name}")
    end = text.find("EndArray", begin.end())
    if end == -1:
        raise ValueError(f"unterminated DISAMAR asciiHDF array {name}")
    body = text[begin.end() : end]
    size_match = re.search(r"Size\s*=([^\n]+)\n", body)
    if not size_match:
        raise ValueError(f"missing Size for DISAMAR asciiHDF array {name}")
    declared_size = [int(token) for token in re.findall(r"\d+", size_match.group(1))]
    expected_count = math.prod(declared_size)
    values_text = body[size_match.end() :]
    values: list[float] = []
    for token in FLOAT_TOKEN_PATTERN.findall(values_text):
        values.append(float(token.replace("D", "E").replace("d", "E")))
    if len(values) != expected_count:
        raise ValueError(
            f"DISAMAR asciiHDF array {name} declared {expected_count} values "
            f"but parsed {len(values)}"
        )
    return values


def retrieve_disamar_fortran(
    *,
    index: int,
    scene: dict[str, float],
    initial: dict[str, float],
) -> dict[str, Any]:
    case_dir = FORTRAN_CASES_DIR / f"case_{index:04d}"
    if case_dir.exists():
        shutil.rmtree(case_dir)
    case_dir.mkdir(parents=True)
    (case_dir / "Config.in").write_text(render_disamar_config(scene, initial))
    (case_dir / "RefSpec").symlink_to(DISAMAR_REFSPEC, target_is_directory=True)
    start = time.perf_counter()
    log_path = case_dir / "disamar.stdout.log"
    try:
        with log_path.open("w") as log_file:
            subprocess.run(
                [str(DISAMAR_EXE)],
                cwd=case_dir,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                check=True,
                timeout=DISAMAR_CASE_TIMEOUT_S,
            )
        retrieval_s = time.perf_counter() - start
        ascii_hdf = (case_dir / "disamar.asciiHDF").read_text()
        aod = parse_array(ascii_hdf, "aerosol_tau")
        top_pressure = parse_array(ascii_hdf, "fit_interval_top_pressure")
        base_pressure = parse_array(ascii_hdf, "fit_interval_base_pressure")
        retrieved_mid_pressure = 0.5 * (top_pressure[2] + base_pressure[2])
        return {
            "model": "disamar_fortran",
            "status": "ok",
            "converged": bool(parse_scalar(ascii_hdf, "solution_has_converged", False)),
            "iterations": int(parse_scalar(ascii_hdf, "number of iterations", 0)),
            "retrieval_s": retrieval_s,
            "retrieved_aerosol_optical_depth": aod[2],
            "retrieved_aerosol_mid_pressure_hpa": retrieved_mid_pressure,
            "error": "",
        }
    except Exception as exc:  # noqa: BLE001 - recorded as validation evidence.
        return {
            "model": "disamar_fortran",
            "status": "error",
            "converged": False,
            "iterations": 0,
            "retrieval_s": time.perf_counter() - start,
            "retrieved_aerosol_optical_depth": math.nan,
            "retrieved_aerosol_mid_pressure_hpa": math.nan,
            "error": repr(exc),
        }


def row_path(index: int, model: str) -> Path:
    return ROWS_DIR / model / f"case_{index:04d}.parquet"


def add_common_fields(
    index: int,
    scene: dict[str, float],
    initial: dict[str, float],
    result: dict[str, Any],
) -> dict[str, Any]:
    row = {
        "case": index,
        **scene,
        "initial_aerosol_optical_depth": initial["aerosol_optical_depth"],
        "initial_aerosol_mid_pressure_hpa": initial["aerosol_mid_pressure_hpa"],
        **result,
    }
    row["aerosol_optical_depth_error"] = (
        row["retrieved_aerosol_optical_depth"] - scene["aerosol_optical_depth"]
    )
    row["aerosol_mid_pressure_error_hpa"] = (
        row["retrieved_aerosol_mid_pressure_hpa"] - scene["aerosol_mid_pressure_hpa"]
    )
    row["aerosol_optical_depth_abs_error"] = abs(row["aerosol_optical_depth_error"])
    row["aerosol_mid_pressure_abs_error_hpa"] = abs(row["aerosol_mid_pressure_error_hpa"])
    return row


def case_initial(index: int, scene: dict[str, float]) -> dict[str, float]:
    return oe_cases.initial_state(index, scene)


def run_model_case(task: tuple[str, int, dict[str, float]]) -> dict[str, Any]:
    model, index, scene = task
    initial = case_initial(index, scene)
    if model == "zdisamar":
        result = retrieve_zdisamar(index=index, scene=scene, initial=initial)
    elif model == "disamar_fortran":
        result = retrieve_disamar_fortran(index=index, scene=scene, initial=initial)
    else:
        raise ValueError(f"unknown model {model}")
    return add_common_fields(index, scene, initial, result)


def run_case(index: int, scene: dict[str, float]) -> list[dict[str, Any]]:
    initial = case_initial(index, scene)
    rows: list[dict[str, Any]] = []
    for result in (
        retrieve_zdisamar(index=index, scene=scene, initial=initial),
        retrieve_disamar_fortran(index=index, scene=scene, initial=initial),
    ):
        rows.append(add_common_fields(index, scene, initial, result))
    return rows


def model_summary(rows: list[dict[str, Any]]) -> dict[str, Any]:
    frame = pl.DataFrame(rows)
    summaries: dict[str, Any] = {}
    for model in sorted(frame["model"].unique().to_list()):
        subset = frame.filter(pl.col("model") == model)
        ok = subset.filter(pl.col("status") == "ok")
        summaries[model] = {
            "runs": subset.height,
            "ok": ok.height,
            "converged": int(ok["converged"].sum()) if ok.height else 0,
            "retrieval_s_mean": (
                float(cast(float, ok["retrieval_s"].mean())) if ok.height else math.nan
            ),
            "retrieval_s_median": (
                float(cast(float, ok["retrieval_s"].median())) if ok.height else math.nan
            ),
            "retrieval_s_max": (
                float(cast(float, ok["retrieval_s"].max())) if ok.height else math.nan
            ),
            "aod_abs_error_max": (
                float(cast(float, ok["aerosol_optical_depth_abs_error"].max()))
                if ok.height
                else math.nan
            ),
            "mid_pressure_abs_error_hpa_max": (
                float(cast(float, ok["aerosol_mid_pressure_abs_error_hpa"].max()))
                if ok.height
                else math.nan
            ),
        }
    return summaries


def scene_rows() -> list[dict[str, Any]]:
    return oe_cases.case_rows(count=RUN_COUNT)


def write_row(row: dict[str, Any]) -> None:
    path = row_path(int(row["case"]), str(row["model"]))
    path.parent.mkdir(parents=True, exist_ok=True)
    pl.DataFrame([row]).write_parquet(path)


def load_completed_rows() -> list[dict[str, Any]]:
    paths = sorted(ROWS_DIR.glob("*/*.parquet"))
    if not paths:
        return []
    return pl.concat([pl.read_parquet(path) for path in paths], how="diagonal_relaxed").to_dicts()


def bootstrap_row_shards() -> None:
    if any(ROWS_DIR.glob("*/*.parquet")) or not PARQUET_PATH.exists():
        return
    frame = pl.read_parquet(PARQUET_PATH)
    if frame.is_empty():
        return
    for row in frame.to_dicts():
        if "aerosol_optical_depth_error" not in row:
            row["aerosol_optical_depth_error"] = (
                row["retrieved_aerosol_optical_depth"] - row["aerosol_optical_depth"]
            )
        if "aerosol_mid_pressure_error_hpa" not in row:
            row["aerosol_mid_pressure_error_hpa"] = (
                row["retrieved_aerosol_mid_pressure_hpa"] - row["aerosol_mid_pressure_hpa"]
            )
        write_row(row)
    print(
        f"seeded {frame.height} resumable row shard(s) from {stable_repo_path(PARQUET_PATH)}",
        flush=True,
    )


def run_model(model: str, scenes: list[dict[str, float]], workers: int) -> None:
    indexed_scenes = list(enumerate(scenes, start=1))
    run_model_indexed(model, indexed_scenes, workers)


def run_model_indexed(
    model: str,
    indexed_scenes: list[tuple[int, dict[str, float]]],
    workers: int,
) -> None:
    pending: list[tuple[str, int, dict[str, float]]] = []
    for index, scene in indexed_scenes:
        if not row_path(index, model).exists():
            pending.append((model, index, scene))

    if not pending:
        print(f"{model}: all {len(indexed_scenes)} rows already exist", flush=True)
        return

    print(
        f"{model}: running {len(pending)} missing rows with {workers} worker(s)",
        flush=True,
    )
    with ProcessPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(run_model_case, task) for task in pending]
        for future in as_completed(futures):
            row = future.result()
            write_row(row)
            print(
                f"{int(row['case']):04d} {row['model']:15s} status={row['status']} "
                f"conv={row['converged']} it={row['iterations']} "
                f"dt={row['retrieval_s']:.3f}s "
                f"aod_err={row['aerosol_optical_depth_abs_error']:.3g} "
                f"midp_err={row['aerosol_mid_pressure_abs_error_hpa']:.3g}",
                flush=True,
            )


def write_merged_outputs(start: float) -> dict[str, Any]:
    rows = load_completed_rows()
    if rows:
        frame = pl.DataFrame(rows)
        frame = frame.sort(["case", "model"])
        frame.write_parquet(PARQUET_PATH)
    summary = {
        "run_count": RUN_COUNT,
        "rng_seed": RNG_SEED,
        "scene_sample_count": SCENE_SAMPLE_COUNT,
        "reference_cases": oe_cases.manifest_path(),
        "wall_s": time.perf_counter() - start,
        "scenes_path": stable_repo_path(SCENES_PATH),
        "rows_path": stable_repo_path(PARQUET_PATH),
        "row_shards_dir": stable_repo_path(ROWS_DIR),
        "fortran_cases_dir": stable_repo_path(FORTRAN_CASES_DIR),
        "disamar_baseline_config": stable_repo_path(DISAMAR_TEMPLATE),
        "wavelength_start_nm": WAVELENGTH_START_NM,
        "wavelength_end_nm": WAVELENGTH_END_NM,
        "wavelength_step_nm": WAVELENGTH_STEP_NM,
        "disamar_workers": DISAMAR_WORKERS,
        "zdisamar_workers": ZDISAMAR_WORKERS,
        "completed_rows": len(rows),
        "model_summary": model_summary(rows) if rows else {},
    }
    write_json(SUMMARY_PATH, summary)
    return summary


def paired_frame() -> pl.DataFrame:
    if not PARQUET_PATH.exists():
        raise SystemExit(
            f"missing paired retrieval parquet: {stable_repo_path(PARQUET_PATH)}; "
            "run this script to generate the paired retrieval rows first"
        )
    frame = pl.read_parquet(PARQUET_PATH)
    if frame.is_empty():
        raise SystemExit(f"paired retrieval parquet is empty: {stable_repo_path(PARQUET_PATH)}")
    if "aerosol_optical_depth_error" not in frame.columns:
        frame = frame.with_columns(
            (pl.col("retrieved_aerosol_optical_depth") - pl.col("aerosol_optical_depth")).alias(
                "aerosol_optical_depth_error"
            ),
        )
    if "aerosol_mid_pressure_error_hpa" not in frame.columns:
        frame = frame.with_columns(
            (
                pl.col("retrieved_aerosol_mid_pressure_hpa") - pl.col("aerosol_mid_pressure_hpa")
            ).alias("aerosol_mid_pressure_error_hpa"),
        )
    return frame.with_columns(pl.col("model").replace(MODEL_LABELS).alias("model_label"))


def paired_difference_rows(frame: pl.DataFrame) -> pl.DataFrame:
    ok = frame.filter(pl.col("status") == "ok")
    wide = ok.pivot(
        "model",
        index="case",
        values=[
            "retrieved_aerosol_optical_depth",
            "retrieved_aerosol_mid_pressure_hpa",
        ],
    )
    aod = wide.select(
        "case",
        pl.lit("Aerosol optical depth").alias("parameter"),
        (
            pl.col("retrieved_aerosol_optical_depth_zdisamar")
            - pl.col("retrieved_aerosol_optical_depth_disamar_fortran")
        ).alias("difference"),
    )
    pressure = wide.select(
        "case",
        pl.lit("Aerosol mid pressure [hPa]").alias("parameter"),
        (
            pl.col("retrieved_aerosol_mid_pressure_hpa_zdisamar")
            - pl.col("retrieved_aerosol_mid_pressure_hpa_disamar_fortran")
        ).alias("difference"),
    )
    return pl.concat([aod, pressure])


def plot_stats(values: list[float]) -> dict[str, float]:
    if not values:
        return {"min": math.nan, "median": math.nan, "mean": math.nan, "max": math.nan}
    series = pl.Series(values)
    return {
        "min": float(cast(float, series.min())),
        "median": float(cast(float, series.median())),
        "mean": float(cast(float, series.mean())),
        "max": float(cast(float, series.max())),
    }


def paired_difference_stats(frame: pl.DataFrame) -> dict[str, dict[str, float]]:
    data = paired_difference_rows(frame)
    return {
        "aerosol_optical_depth": plot_stats(
            data.filter(pl.col("parameter") == "Aerosol optical depth")["difference"].to_list()
        ),
        "aerosol_mid_pressure_hpa": plot_stats(
            data.filter(pl.col("parameter") == "Aerosol mid pressure [hPa]")["difference"].to_list()
        ),
    }


def signed(value: float, precision: str) -> str:
    if math.isnan(value):
        return "nan"
    return f"{value:+{precision}}"


def difference_subtitle(stats_payload: dict[str, float], precision: str, unit: str = "") -> str:
    suffix = f" {unit}" if unit else ""
    return (
        f"median {signed(stats_payload['median'], precision)}{suffix}; "
        f"range {signed(stats_payload['min'], precision)} "
        f"to {signed(stats_payload['max'], precision)}{suffix}"
    )


def _model_color() -> alt.Color:
    return alt.Color(
        "model_label:N",
        title=None,
        scale=alt.Scale(domain=list(MODEL_LABELS.values()), range=MODEL_COLORS),
    )


def _extent(values: list[float]) -> tuple[float, float]:
    lower = float(min(values))
    upper = float(max(values))
    padding = max((upper - lower) * 0.04, 1.0e-12)
    return lower - padding, upper + padding


def _identity_line(lower: float, upper: float):
    return (
        alt.Chart(pd.DataFrame({"x": [lower, upper], "y": [lower, upper]}))
        .mark_line(color=PLOT.colors["black"], strokeDash=[4, 3], strokeWidth=1)
        .encode(x="x:Q", y="y:Q")
    )


def scatter_chart(
    rows: pl.DataFrame,
    *,
    parameter: str,
    truth_field: str,
    retrieved_field: str,
    title: str,
):
    subset = rows.filter(pl.col("parameter") == parameter)
    data = pd.DataFrame(subset.to_dicts())
    lower, upper = _extent(
        data[truth_field].astype(float).to_list() + data[retrieved_field].astype(float).to_list()
    )
    points = (
        alt.Chart(data)
        .mark_point(filled=True, size=48, opacity=0.78)
        .encode(
            x=alt.X(truth_field + ":Q", title="True value", scale=alt.Scale(domain=[lower, upper])),
            y=alt.Y(
                retrieved_field + ":Q",
                title="Retrieved value",
                scale=alt.Scale(domain=[lower, upper]),
            ),
            color=_model_color(),
            shape=alt.Shape(
                "model_label:N",
                title=None,
                scale=alt.Scale(
                    domain=list(MODEL_MARKERS),
                    range=[MODEL_MARKERS[label] for label in MODEL_MARKERS],
                ),
            ),
            tooltip=[
                alt.Tooltip("case:O", title="Case"),
                alt.Tooltip("model_label:N", title="Model"),
                alt.Tooltip(truth_field + ":Q", title="Truth", format=".6g"),
                alt.Tooltip(retrieved_field + ":Q", title="Retrieved", format=".6g"),
            ],
        )
    )
    return alt.layer(_identity_line(lower, upper), points).properties(
        width=530, height=330, title=title
    )


def histogram_chart(
    rows: pl.DataFrame,
    *,
    parameter: str,
    title: str,
    subtitle: str,
    xlabel: str,
):
    subset = rows.filter(pl.col("parameter") == parameter)
    data = pd.DataFrame(subset.to_dicts())
    histogram = (
        alt.Chart(data)
        .mark_bar(color=PLOT.colors["blue"], opacity=0.78)
        .encode(
            x=alt.X("difference:Q", bin=alt.Bin(maxbins=45), title=xlabel),
            y=alt.Y("count():Q", title="Count"),
            tooltip=[
                alt.Tooltip("count():Q", title="Count"),
                alt.Tooltip("difference:Q", title="Difference", format=".6g"),
            ],
        )
    )
    zero = (
        alt.Chart(pd.DataFrame({"zero": [0.0]}))
        .mark_rule(color=PLOT.colors["black"], strokeDash=[4, 3], strokeWidth=1)
        .encode(x="zero:Q")
    )
    return alt.layer(histogram, zero).properties(
        width=530,
        height=300,
        title={"text": title, "subtitle": subtitle},
    )


def save_retrieved_plot(frame: pl.DataFrame) -> None:
    PLOT.prepare()
    ok = frame.filter(pl.col("status") == "ok")
    aod = ok.select(
        "case",
        "model_label",
        pl.lit("Aerosol optical depth").alias("parameter"),
        pl.col("aerosol_optical_depth").alias("truth"),
        pl.col("retrieved_aerosol_optical_depth").alias("retrieved"),
    )
    pressure = ok.select(
        "case",
        "model_label",
        pl.lit("Aerosol mid pressure").alias("parameter"),
        pl.col("aerosol_mid_pressure_hpa").alias("truth"),
        pl.col("retrieved_aerosol_mid_pressure_hpa").alias("retrieved"),
    )
    retrieved = pl.concat([aod, pressure]).rename(
        {"truth": "truth_value", "retrieved": "retrieved_value"}
    )
    differences = paired_difference_rows(frame)
    difference_stats = paired_difference_stats(frame)
    top = alt.hconcat(
        scatter_chart(
            retrieved,
            parameter="Aerosol mid pressure",
            truth_field="truth_value",
            retrieved_field="retrieved_value",
            title="Aerosol mid pressure",
        ),
        scatter_chart(
            retrieved,
            parameter="Aerosol optical depth",
            truth_field="truth_value",
            retrieved_field="retrieved_value",
            title="Aerosol optical depth",
        ),
        spacing=32,
    )
    bottom = alt.hconcat(
        histogram_chart(
            differences,
            parameter="Aerosol optical depth",
            title="Aerosol optical depth",
            subtitle=difference_subtitle(difference_stats["aerosol_optical_depth"], ".3e"),
            xlabel="zdisamar retrieved - DISAMAR retrieved",
        ),
        histogram_chart(
            differences,
            parameter="Aerosol mid pressure [hPa]",
            title="Aerosol mid pressure [hPa]",
            subtitle=difference_subtitle(
                difference_stats["aerosol_mid_pressure_hpa"],
                ".4f",
                "hPa",
            ),
            xlabel="zdisamar retrieved - DISAMAR retrieved [hPa]",
        ),
        spacing=32,
    )
    chart = alt.vconcat(top, bottom, spacing=42).properties(
        title={
            "text": "Retrieved State Versus Truth",
            "subtitle": (
                "Top: each model retrieval against known synthetic truth. Bottom: paired "
                "retrieval difference per scene (zdisamar - DISAMAR Fortran)."
            ),
        }
    )
    PLOT.save(chart, RETRIEVED_PLOT_PATH)


def save_error_histograms(frame: pl.DataFrame) -> None:
    PLOT.prepare()
    ok = frame.filter(pl.col("status") == "ok")
    data = pd.DataFrame(ok.to_dicts())
    charts = []
    for column, title, xlabel in (
        ("aerosol_optical_depth_error", "Aerosol optical depth", "Retrieved AOD - true AOD"),
        (
            "aerosol_mid_pressure_error_hpa",
            "Aerosol mid pressure",
            "Retrieved mid pressure - true mid pressure [hPa]",
        ),
    ):
        charts.append(
            alt.Chart(data)
            .mark_bar(opacity=0.58)
            .encode(
                x=alt.X(column + ":Q", bin=alt.Bin(maxbins=35), title=xlabel),
                y=alt.Y("count():Q", title="Count"),
                color=_model_color(),
                tooltip=[
                    alt.Tooltip("model_label:N", title="Model"),
                    alt.Tooltip("count():Q", title="Count"),
                ],
            )
            .properties(width=520, height=320, title=title)
        )
    chart = alt.hconcat(*charts, spacing=32).properties(title="Retrieval Error Histograms")
    PLOT.save(chart, ERROR_HISTOGRAM_PATH)


def save_latency_plot(frame: pl.DataFrame) -> None:
    PLOT.prepare()
    ok = frame.filter(pl.col("status") == "ok")
    rows: list[dict[str, float | str]] = []
    for model in ("disamar_fortran", "zdisamar"):
        model_rows = ok.filter(pl.col("model") == model)
        if model_rows.is_empty():
            continue
        stats_payload = plot_stats(model_rows["retrieval_s"].to_list())
        rows.append(
            {
                "model": model,
                "model_label": MODEL_LABELS[model],
                "minimum": stats_payload["min"],
                "median": stats_payload["median"],
                "mean": stats_payload["mean"],
                "maximum": stats_payload["max"],
            }
        )
    fast_stats = fast_mode_latency_stats()
    if fast_stats:
        rows.append(
            {
                "model": "zdisamar_fast",
                "model_label": MODEL_LABELS["zdisamar_fast"],
                "minimum": fast_stats["min"],
                "median": fast_stats["median"],
                "mean": fast_stats["mean"],
                "maximum": fast_stats["max"],
            }
        )
    data = pd.DataFrame.from_records(rows)
    color = alt.Color(
        "model_label:N",
        title=None,
        scale=alt.Scale(domain=list(MODEL_LABELS.values()), range=MODEL_COLORS),
    )
    span = (
        alt.Chart(data)
        .mark_rule(size=8, opacity=0.26)
        .encode(
            x=alt.X("model_label:N", title=None),
            y=alt.Y(
                "minimum:Q",
                title="Retrieval wall time [s]",
                scale=alt.Scale(type="log"),
            ),
            y2="maximum:Q",
            color=color,
        )
    )
    median = (
        alt.Chart(data)
        .mark_tick(thickness=2.6, size=46)
        .encode(x="model_label:N", y="median:Q", color=color)
    )
    mean = (
        alt.Chart(data)
        .mark_point(filled=True, size=44)
        .encode(
            x="model_label:N",
            y="mean:Q",
            color=color,
            tooltip=[
                alt.Tooltip("model_label:N", title="Model"),
                alt.Tooltip("minimum:Q", title="Min", format=".4g"),
                alt.Tooltip("median:Q", title="Median", format=".4g"),
                alt.Tooltip("mean:Q", title="Mean", format=".4g"),
                alt.Tooltip("maximum:Q", title="Max", format=".4g"),
            ],
        )
    )
    chart = alt.layer(span, median, mean).properties(
        width=620,
        height=420,
        title={
            "text": "Optimal Estimation Retrieval Latency",
            "subtitle": "Line spans min-max; horizontal tick is median; dot is mean.",
        },
    )
    PLOT.save(chart, LATENCY_PLOT_PATH)


def fast_mode_latency_stats() -> dict[str, float] | None:
    if not FAST_MODE_SUMMARY_PATH.exists():
        return None
    payload = json.loads(FAST_MODE_SUMMARY_PATH.read_text())
    stats_payload = payload.get("by_mode", {}).get("fast", {}).get("retrieval_s")
    if not isinstance(stats_payload, dict):
        return None
    return {
        "min": float(stats_payload["min"]),
        "median": float(stats_payload["median"]),
        "mean": float(stats_payload["mean"]),
        "max": float(stats_payload["max"]),
    }


def paired_plot_manifest(frame: pl.DataFrame) -> dict[str, Any]:
    ok = frame.filter(pl.col("status") == "ok")
    by_model: dict[str, Any] = {}
    for model in sorted(frame["model"].unique().to_list()):
        subset = frame.filter(pl.col("model") == model)
        ok_subset = subset.filter(pl.col("status") == "ok")
        by_model[str(model)] = {
            "rows": subset.height,
            "ok": ok_subset.height,
            "converged": int(ok_subset["converged"].sum()) if ok_subset.height else 0,
            "retrieval_s": plot_stats(ok_subset["retrieval_s"].to_list()),
            "aod_abs_error": plot_stats(ok_subset["aerosol_optical_depth_abs_error"].to_list()),
            "mid_pressure_abs_error_hpa": plot_stats(
                ok_subset["aerosol_mid_pressure_abs_error_hpa"].to_list()
            ),
        }
    return {
        "source_data": PARQUET_PATH.relative_to(REPO_ROOT).as_posix(),
        "source_rows": frame.height,
        "source_ok_rows": ok.height,
        "reference_cases": oe_cases.manifest_path(),
        "plots": {
            "retrieved_scatter": stable_repo_path(RETRIEVED_PLOT_PATH),
            "error_histograms": stable_repo_path(ERROR_HISTOGRAM_PATH),
            "latency": stable_repo_path(LATENCY_PLOT_PATH),
        },
        "paired_difference": paired_difference_stats(frame),
        "by_model": by_model,
    }


def write_paired_plot_outputs() -> None:
    TRACKED_OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    frame = paired_frame()
    save_retrieved_plot(frame)
    save_error_histograms(frame)
    save_latency_plot(frame)
    write_json(MANIFEST_PATH, paired_plot_manifest(frame))


def main() -> None:
    if not DISAMAR_EXE.exists():
        raise SystemExit(f"missing DISAMAR executable: {stable_repo_path(DISAMAR_EXE)}")
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    start = time.perf_counter()
    scenes_with_initial = scene_rows()
    pl.DataFrame(scenes_with_initial).write_parquet(SCENES_PATH)
    bootstrap_row_shards()
    scenes = [oe_cases.scene_from_row(row) for row in scenes_with_initial]

    indexed_scenes = list(enumerate(scenes, start=1))
    for batch_start in range(0, len(indexed_scenes), BATCH_SIZE):
        batch = indexed_scenes[batch_start : batch_start + BATCH_SIZE]
        batch_label = f"{batch[0][0]:04d}-{batch[-1][0]:04d}" if batch else f"{batch_start + 1:04d}"
        print(f"batch {batch_label}: DISAMAR Fortran", flush=True)
        run_model_indexed("disamar_fortran", batch, DISAMAR_WORKERS)
        write_merged_outputs(start)
        print(f"batch {batch_label}: zdisamar", flush=True)
        run_model_indexed("zdisamar", batch, ZDISAMAR_WORKERS)
        write_merged_outputs(start)

    summary = write_merged_outputs(start)
    print("summary:")
    print(f"  scenes: {stable_repo_path(SCENES_PATH)}")
    print(f"  rows: {stable_repo_path(PARQUET_PATH)}")
    print(f"  summary: {stable_repo_path(SUMMARY_PATH)}")
    print(f"  wall_s: {summary['wall_s']:.3f}")
    for model, payload in summary["model_summary"].items():
        print(f"  {model}: {payload}")
    write_paired_plot_outputs()
    print(f"  plots: {stable_repo_path(MANIFEST_PATH)}")


if __name__ == "__main__":
    main()
