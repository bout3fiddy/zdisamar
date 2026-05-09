#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "numpy>=2.2",
#   "polars>=1.35",
# ]
# ///

import copy
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

import numpy as np
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
    REPO_ROOT / "validation" / "optimal_estimation" / "data" / "reference" / "baseline_config.in"
)
DISAMAR_EXE = REPO_ROOT / "vendor" / "disamar-fortran" / "src" / "Disamar.exe"
DISAMAR_REFSPEC = REPO_ROOT / "vendor" / "disamar-fortran" / "RefSpec"

sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

import zdisamar as zd  # noqa: E402
from zdisamar.inverse_method import optimal_estimation  # noqa: E402
from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe  # noqa: E402

from validation.common import o2a_retrieval_baseline as oe_baseline  # noqa: E402
from validation.common.o2a_reference_case import build_o2a_case  # noqa: E402
from validation.common.paths import stable_repo_path, write_json  # noqa: E402

type ScalarValue = bool | int | float | str

RUN_COUNT = 100
SCENE_SAMPLE_COUNT = 500
BATCH_SIZE = 10
RNG_SEED = 20260507
DISAMAR_WORKERS = max(1, min(BATCH_SIZE, os.cpu_count() or 2))
ZDISAMAR_WORKERS = 1
LAYER_THICKNESS_HPA = oe_baseline.LAYER_THICKNESS_HPA
WAVELENGTH_START_NM = oe_baseline.WAVELENGTH_START_NM
WAVELENGTH_END_NM = oe_baseline.WAVELENGTH_END_NM
WAVELENGTH_STEP_NM = oe_baseline.WAVELENGTH_STEP_NM
DISAMAR_PRESSURE_PRIOR_VARIANCE = 150.0**2
DISAMAR_CASE_TIMEOUT_S = 5400.0
FLOAT_TOKEN_PATTERN = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[EDed][+-]?\d+)?")


def uniform_lhs(rng: np.random.Generator, low: float, high: float, count: int) -> np.ndarray:
    values = (np.arange(count, dtype=np.float64) + rng.random(count)) / count
    rng.shuffle(values)
    return low + values * (high - low)


def sampled_scenes(count: int, seed: int) -> list[dict[str, float]]:
    rng = np.random.default_rng(seed)
    solar = uniform_lhs(rng, 25.0, 65.0, count)
    view = uniform_lhs(rng, 0.0, 50.0, count)
    azimuth = uniform_lhs(rng, 0.0, 180.0, count)
    surface_pressure = uniform_lhs(rng, 820.0, 1040.0, count)
    surface_albedo = uniform_lhs(rng, 0.05, 0.55, count)
    aerosol_optical_depth = np.exp(uniform_lhs(rng, math.log(0.10), math.log(2.0), count))
    mid_fraction = uniform_lhs(rng, 0.18, 0.78, count)
    scenes: list[dict[str, float]] = []
    for index in range(count):
        mid_min = 225.0
        mid_max = surface_pressure[index] - 100.0
        scenes.append(
            {
                "solar_zenith_deg": float(solar[index]),
                "viewing_zenith_deg": float(view[index]),
                "relative_azimuth_deg": float(azimuth[index]),
                "surface_pressure_hpa": float(surface_pressure[index]),
                "surface_albedo": float(surface_albedo[index]),
                "aerosol_optical_depth": float(aerosol_optical_depth[index]),
                "aerosol_mid_pressure_hpa": float(
                    mid_min + mid_fraction[index] * (mid_max - mid_min)
                ),
            }
        )
    return scenes


def initial_aod(truth: float, index: int) -> float:
    factor = 1.12 if index % 2 == 0 else 0.88
    return min(5.0, max(0.02, truth * factor + 0.01))


def initial_mid_pressure(truth: float, surface_pressure: float, index: int) -> float:
    offset = [-25.0, -15.0, 15.0, 25.0][index % 4]
    return min(surface_pressure - 75.0, max(100.0, truth + offset))


def layer_bounds(mid_pressure_hpa: float) -> tuple[float, float]:
    return (
        mid_pressure_hpa - 0.5 * LAYER_THICKNESS_HPA,
        mid_pressure_hpa + 0.5 * LAYER_THICKNESS_HPA,
    )


def update_layer_pressures(case: zd.O2AInput, mid_pressure_hpa: float) -> None:
    top_pressure, bottom_pressure = layer_bounds(mid_pressure_hpa)
    case.aerosol.placement.top_pressure_hpa = top_pressure
    case.aerosol.placement.bottom_pressure_hpa = bottom_pressure
    for interval in case.atmosphere.intervals:
        if interval.index_1based == 1:
            interval.bottom_pressure_hpa = top_pressure
        elif interval.index_1based == 2:
            interval.top_pressure_hpa = top_pressure
            interval.bottom_pressure_hpa = bottom_pressure
        elif interval.index_1based == 3:
            interval.top_pressure_hpa = bottom_pressure
            interval.bottom_pressure_hpa = case.surface.pressure_hpa


def build_scene(
    base: zd.O2AInput,
    *,
    index: int,
    scene: dict[str, float],
) -> zd.O2AInput:
    case = copy.deepcopy(base)
    case.metadata["id"] = f"paired_oe_{index:04d}"
    case.scene_id = f"paired_oe_{index:04d}"
    case.geometry.solar_zenith_deg = scene["solar_zenith_deg"]
    case.geometry.viewing_zenith_deg = scene["viewing_zenith_deg"]
    case.geometry.relative_azimuth_deg = scene["relative_azimuth_deg"]
    case.surface.pressure_hpa = scene["surface_pressure_hpa"]
    case.surface.albedo = scene["surface_albedo"]
    case.aerosol.optical_depth_550_nm = scene["aerosol_optical_depth"]
    case.aerosol.single_scatter_albedo = oe_baseline.AEROSOL_SINGLE_SCATTER_ALBEDO
    case.aerosol.asymmetry_factor = oe_baseline.AEROSOL_ASYMMETRY_FACTOR
    case.aerosol.angstrom_exponent = oe_baseline.AEROSOL_ANGSTROM_EXPONENT
    update_layer_pressures(case, scene["aerosol_mid_pressure_hpa"])
    return case


def build_state_vector(
    scene: dict[str, float],
    initial: dict[str, float],
    profile: optimal_estimation.PressureAltitudeProfile,
) -> optimal_estimation.StateVector:
    return optimal_estimation.StateVector(
        [
            optimal_estimation.AerosolOpticalDepth(
                initial=initial["aerosol_optical_depth"],
                prior=initial["aerosol_optical_depth"],
                variance=0.8,
                lower=0.02,
                upper=5.0,
            ),
            optimal_estimation.AerosolLayerMidPressure(
                initial=initial["aerosol_mid_pressure_hpa"],
                prior=initial["aerosol_mid_pressure_hpa"],
                variance=150.0**2,
                thickness_hpa=LAYER_THICKNESS_HPA,
                interval_index_1based=2,
                pressure_altitude_profile=profile,
                lower=225.0,
                upper=scene["surface_pressure_hpa"] - 100.0,
            ),
        ]
    )


def measurement_from_baseline_snr(prepared) -> optimal_estimation.Measurement:
    with prepared.forward_model() as spectrum:
        wavelength_nm = spectrum.wavelength_nm.copy()
        reflectance = spectrum.reflectance.copy()
    reflectance_noise = np.maximum(
        np.abs(reflectance) * oe_baseline.REFLECTANCE_RELATIVE_NOISE,
        1.0e-12,
    )
    return optimal_estimation.Measurement(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        variance=reflectance_noise**2,
    )


def retrieve_zdisamar(
    *,
    index: int,
    scene: dict[str, float],
    initial: dict[str, float],
) -> dict[str, Any]:
    base = build_o2a_case(zd, jacobian_reference_layer=True)
    oe_baseline.configure_case(base)
    case = build_scene(base, index=index, scene=scene)
    start = time.perf_counter()
    try:
        with zd.prepare(case) as prepared:
            measurement = measurement_from_baseline_snr(prepared)
            profile = o2a_oe.pressure_altitude_profile_from_prepared(prepared)
        state_vector = build_state_vector(scene, initial, profile)
        with zd.o2a_forward_session(case) as session:
            result = o2a_oe.disamar_oe(
                inverse_model=optimal_estimation.O2AInverseForwardModel(
                    case,
                    forward_session=session,
                ),
                measurement=measurement,
                state_vector=state_vector,
                controls=optimal_estimation.RetrievalControls.from_disamar_retrieval_specs(),
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
    truth_top, truth_bottom = layer_bounds(scene["aerosol_mid_pressure_hpa"])
    initial_top, initial_bottom = layer_bounds(initial["aerosol_mid_pressure_hpa"])
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
    return {
        "aerosol_optical_depth": initial_aod(scene["aerosol_optical_depth"], index),
        "aerosol_mid_pressure_hpa": initial_mid_pressure(
            scene["aerosol_mid_pressure_hpa"],
            scene["surface_pressure_hpa"],
            index,
        ),
    }


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
    initial = {
        "aerosol_optical_depth": initial_aod(scene["aerosol_optical_depth"], index),
        "aerosol_mid_pressure_hpa": initial_mid_pressure(
            scene["aerosol_mid_pressure_hpa"],
            scene["surface_pressure_hpa"],
            index,
        ),
    }
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
    rows: list[dict[str, Any]] = []
    scenes = sampled_scenes(SCENE_SAMPLE_COUNT, RNG_SEED)[:RUN_COUNT]
    for index, scene in enumerate(scenes, start=1):
        initial = case_initial(index, scene)
        rows.append(
            {
                "case": index,
                **scene,
                "initial_aerosol_optical_depth": initial["aerosol_optical_depth"],
                "initial_aerosol_mid_pressure_hpa": initial["aerosol_mid_pressure_hpa"],
            }
        )
    return rows


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


def main() -> None:
    if not DISAMAR_EXE.exists():
        raise SystemExit(f"missing DISAMAR executable: {stable_repo_path(DISAMAR_EXE)}")
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    start = time.perf_counter()
    scenes_with_initial = scene_rows()
    pl.DataFrame(scenes_with_initial).write_parquet(SCENES_PATH)
    bootstrap_row_shards()
    scenes = [
        {
            key: float(row[key])
            for key in (
                "solar_zenith_deg",
                "viewing_zenith_deg",
                "relative_azimuth_deg",
                "surface_pressure_hpa",
                "surface_albedo",
                "aerosol_optical_depth",
                "aerosol_mid_pressure_hpa",
            )
        }
        for row in scenes_with_initial
    ]

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


if __name__ == "__main__":
    main()
