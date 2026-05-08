#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "altair>=5.5",
#   "polars>=1.35",
#   "vl-convert-python>=1.7",
# ]
# ///

from __future__ import annotations

import math
import sys
from pathlib import Path
from typing import Any, cast

import altair as alt
import polars as pl

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
DATA_PATH = (
    REPO_ROOT
    / "out"
    / "validation"
    / "optimal_estimation"
    / "paired_disamar_zdisamar"
    / "paired_retrieval_runs.parquet"
)
OUTPUTS_DIR = REPO_ROOT / "validation" / "outputs" / "optimal_estimation"
RETRIEVED_PLOT_PATH = OUTPUTS_DIR / "paired_oe_retrieved_scatter.png"
ERROR_HISTOGRAM_PATH = OUTPUTS_DIR / "paired_oe_error_histograms.png"
LATENCY_PLOT_PATH = OUTPUTS_DIR / "paired_oe_latency.png"
MANIFEST_PATH = OUTPUTS_DIR / "paired_oe_plot_manifest.json"

sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from validation.common.altair_style import (  # noqa: E402
    VALIDATION_BLUE,
    VALIDATION_ORANGE,
    enable_validation_theme,
)
from validation.common.paths import stable_repo_path, write_json  # noqa: E402

alt.data_transformers.disable_max_rows()
enable_validation_theme()

MODEL_LABELS = {
    "disamar_fortran": "DISAMAR Fortran",
    "zdisamar": "zdisamar",
}
MODEL_COLORS = [VALIDATION_BLUE, VALIDATION_ORANGE]


def require_data() -> pl.DataFrame:
    if not DATA_PATH.exists():
        raise SystemExit(
            f"missing paired retrieval parquet: {stable_repo_path(DATA_PATH)}; "
            "run validation/optimal_estimation/paired_disamar_zdisamar_sweep.py first"
        )
    frame = pl.read_parquet(DATA_PATH)
    if frame.is_empty():
        raise SystemExit(f"paired retrieval parquet is empty: {stable_repo_path(DATA_PATH)}")
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
    return frame.with_columns(
        pl.col("model").replace(MODEL_LABELS).alias("model_label"),
    )


def retrieved_rows(frame: pl.DataFrame) -> pl.DataFrame:
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
    return pl.concat([aod, pressure])


def error_rows(frame: pl.DataFrame) -> pl.DataFrame:
    ok = frame.filter(pl.col("status") == "ok")
    aod = ok.select(
        "case",
        "model_label",
        pl.lit("Aerosol optical depth").alias("parameter"),
        pl.col("aerosol_optical_depth_error").alias("error"),
    )
    pressure = ok.select(
        "case",
        "model_label",
        pl.lit("Aerosol mid pressure [hPa]").alias("parameter"),
        pl.col("aerosol_mid_pressure_error_hpa").alias("error"),
    )
    return pl.concat([aod, pressure])


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


def retrieved_scatter_row(frame: pl.DataFrame) -> alt.HConcatChart:
    data = retrieved_rows(frame)
    charts = []
    for parameter in data["parameter"].unique().to_list():
        subset = data.filter(pl.col("parameter") == parameter)
        truth_min = float(cast(float, subset["truth"].min()))
        retrieved_min = float(cast(float, subset["retrieved"].min()))
        truth_max = float(cast(float, subset["truth"].max()))
        retrieved_max = float(cast(float, subset["retrieved"].max()))
        min_value = min(truth_min, retrieved_min)
        max_value = max(truth_max, retrieved_max)
        pad = (max_value - min_value) * 0.04
        line_rows = pl.DataFrame([{"line_min": min_value - pad, "line_max": max_value + pad}])
        line = (
            alt.Chart(line_rows)
            .mark_line(color="black", strokeDash=[4, 3], strokeWidth=1)
            .encode(
                x="line_min:Q",
                x2="line_max:Q",
                y="line_min:Q",
                y2="line_max:Q",
            )
        )
        points = (
            alt.Chart(subset)
            .mark_circle(size=34, opacity=0.72)
            .encode(
                x=alt.X("truth:Q", title="True value"),
                y=alt.Y("retrieved:Q", title="Retrieved value"),
                color=alt.Color(
                    "model_label:N",
                    title="Model",
                    scale=alt.Scale(range=MODEL_COLORS),
                ),
                tooltip=[
                    "case:Q",
                    "model_label:N",
                    "parameter:N",
                    alt.Tooltip("truth:Q", format=".6g"),
                    alt.Tooltip("retrieved:Q", format=".6g"),
                ],
            )
            .properties(title=str(parameter), width=340, height=300)
        )
        charts.append(points + line)
    return alt.hconcat(*charts)


def paired_difference_histogram_row(frame: pl.DataFrame) -> alt.HConcatChart:
    data = paired_difference_rows(frame)
    charts = []
    for parameter, x_title in (
        ("Aerosol optical depth", "zdisamar retrieved - DISAMAR retrieved"),
        (
            "Aerosol mid pressure [hPa]",
            "zdisamar retrieved - DISAMAR retrieved [hPa]",
        ),
    ):
        subset = data.filter(pl.col("parameter") == parameter)
        zero_line = (
            alt.Chart(pl.DataFrame([{"zero": 0.0}]))
            .mark_rule(color="black", strokeDash=[4, 3], strokeWidth=1)
            .encode(x="zero:Q")
        )
        histogram = (
            alt.Chart(subset)
            .mark_bar(color=VALIDATION_BLUE, opacity=0.78)
            .encode(
                x=alt.X("difference:Q", bin=alt.Bin(maxbins=45), title=x_title),
                y=alt.Y("count():Q", title="Count"),
                tooltip=[
                    "parameter:N",
                    alt.Tooltip("count():Q", title="count"),
                ],
            )
            .properties(title=parameter, width=340, height=220)
        )
        charts.append(histogram + zero_line)
    return alt.hconcat(*charts)


def save_retrieved_plot(frame: pl.DataFrame) -> None:
    chart = (
        alt.vconcat(
            retrieved_scatter_row(frame),
            paired_difference_histogram_row(frame),
        )
        .resolve_scale(x="independent", y="independent")
        .properties(
            title=alt.TitleParams(
                text="Retrieved State Versus Truth",
                subtitle=(
                    "Top: each model retrieval against known synthetic truth. "
                    "Bottom: paired retrieval difference per scene "
                    "(zdisamar - DISAMAR Fortran)."
                ),
            )
        )
    )
    chart.save(RETRIEVED_PLOT_PATH, ppi=160)


def save_error_histograms(frame: pl.DataFrame) -> None:
    data = error_rows(frame)
    charts = []
    for parameter, x_title in (
        ("Aerosol optical depth", "Retrieved AOD - true AOD"),
        (
            "Aerosol mid pressure [hPa]",
            "Retrieved mid pressure - true mid pressure [hPa]",
        ),
    ):
        subset = data.filter(pl.col("parameter") == parameter)
        chart = (
            alt.Chart(subset)
            .mark_bar(opacity=0.76)
            .encode(
                x=alt.X("error:Q", bin=alt.Bin(maxbins=45), title=x_title),
                y=alt.Y("count():Q", title="Count"),
                color=alt.Color(
                    "model_label:N",
                    title="Model",
                    scale=alt.Scale(range=MODEL_COLORS),
                ),
                tooltip=[
                    "model_label:N",
                    "parameter:N",
                    alt.Tooltip("count():Q", title="count"),
                ],
            )
            .properties(title=parameter, width=340, height=260)
        )
        charts.append(chart)
    chart = alt.hconcat(*charts).properties(
        title=alt.TitleParams(
            text="Retrieval Error Histograms",
            subtitle=(
                "Error is computed against each model's own synthetic scene truth: "
                "retrieved value - true value. It is not the zdisamar-minus-DISAMAR "
                "retrieval difference."
            ),
        )
    )
    chart.save(ERROR_HISTOGRAM_PATH, ppi=160)


def save_latency_plot(frame: pl.DataFrame) -> None:
    ok = frame.filter(pl.col("status") == "ok")
    chart = (
        alt.Chart(ok)
        .mark_boxplot(extent="min-max", size=52)
        .encode(
            x=alt.X("model_label:N", title=None, sort=["DISAMAR Fortran", "zdisamar"]),
            y=alt.Y("retrieval_s:Q", title="Retrieval wall time [s]", scale=alt.Scale(type="log")),
            color=alt.Color(
                "model_label:N",
                title="Model",
                scale=alt.Scale(range=MODEL_COLORS),
                legend=None,
            ),
            tooltip=[
                "model_label:N",
                alt.Tooltip("retrieval_s:Q", format=".3f"),
                alt.Tooltip("iterations:Q", format="d"),
            ],
        )
        .properties(title="Optimal Estimation Retrieval Latency", width=420, height=300)
    )
    chart.save(LATENCY_PLOT_PATH, ppi=160)


def stats(values: list[float]) -> dict[str, float]:
    if not values:
        return {"min": math.nan, "median": math.nan, "mean": math.nan, "max": math.nan}
    series = pl.Series(values)
    return {
        "min": float(cast(float, series.min())),
        "median": float(cast(float, series.median())),
        "mean": float(cast(float, series.mean())),
        "max": float(cast(float, series.max())),
    }


def manifest(frame: pl.DataFrame) -> dict[str, Any]:
    ok = frame.filter(pl.col("status") == "ok")
    by_model: dict[str, Any] = {}
    for model in sorted(frame["model"].unique().to_list()):
        subset = frame.filter(pl.col("model") == model)
        ok_subset = subset.filter(pl.col("status") == "ok")
        by_model[str(model)] = {
            "rows": subset.height,
            "ok": ok_subset.height,
            "converged": int(ok_subset["converged"].sum()) if ok_subset.height else 0,
            "retrieval_s": stats(ok_subset["retrieval_s"].to_list()),
            "aod_abs_error": stats(ok_subset["aerosol_optical_depth_abs_error"].to_list()),
            "mid_pressure_abs_error_hpa": stats(
                ok_subset["aerosol_mid_pressure_abs_error_hpa"].to_list()
            ),
        }
    return {
        "source_data": stable_repo_path(DATA_PATH),
        "source_rows": frame.height,
        "source_ok_rows": ok.height,
        "plots": {
            "retrieved_scatter": stable_repo_path(RETRIEVED_PLOT_PATH),
            "error_histograms": stable_repo_path(ERROR_HISTOGRAM_PATH),
            "latency": stable_repo_path(LATENCY_PLOT_PATH),
        },
        "by_model": by_model,
    }


def main() -> None:
    OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
    frame = require_data()
    save_retrieved_plot(frame)
    save_error_histograms(frame)
    save_latency_plot(frame)
    payload = manifest(frame)
    write_json(MANIFEST_PATH, payload)
    print(f"wrote {stable_repo_path(RETRIEVED_PLOT_PATH)}")
    print(f"wrote {stable_repo_path(ERROR_HISTOGRAM_PATH)}")
    print(f"wrote {stable_repo_path(LATENCY_PLOT_PATH)}")
    print(f"wrote {stable_repo_path(MANIFEST_PATH)}")


if __name__ == "__main__":
    main()
