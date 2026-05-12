#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "altair>=5.5",
#   "matplotlib>=3.10",
#   "polars>=1.35",
#   "vl-convert-python>=1.7",
# ]
# ///

import math
import sys
from pathlib import Path
from typing import Any, cast

import altair as alt
import matplotlib.pyplot as plt
import polars as pl
from matplotlib.ticker import MaxNLocator

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

from zdisamar.plot.properties import PLOT  # noqa: E402

from validation.common.paths import stable_repo_path, write_json  # noqa: E402

alt.data_transformers.disable_max_rows()
PLOT.prepare()

MODEL_LABELS = {
    "disamar_fortran": "DISAMAR Fortran",
    "zdisamar": "zdisamar",
}
MODEL_COLORS = [PLOT.colors["blue"], PLOT.colors["orange"]]
MODEL_MARKERS = {
    "DISAMAR Fortran": "o",
    "zdisamar": "x",
}
MONOSPACE_FONT = "Menlo"


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


def series_stats(series: pl.Series) -> dict[str, float]:
    if series.is_empty():
        return {"min": math.nan, "median": math.nan, "mean": math.nan, "max": math.nan}
    return {
        "min": float(cast(float, series.min())),
        "median": float(cast(float, series.median())),
        "mean": float(cast(float, series.mean())),
        "max": float(cast(float, series.max())),
    }


def paired_difference_stats(frame: pl.DataFrame) -> dict[str, dict[str, float]]:
    data = paired_difference_rows(frame)
    return {
        "aerosol_optical_depth": series_stats(
            data.filter(pl.col("parameter") == "Aerosol optical depth")["difference"]
        ),
        "aerosol_mid_pressure_hpa": series_stats(
            data.filter(pl.col("parameter") == "Aerosol mid pressure [hPa]")["difference"]
        ),
    }


def signed(value: float, precision: str) -> str:
    if math.isnan(value):
        return "nan"
    return f"{value:+{precision}}"


def difference_subtitle(stats: dict[str, float], precision: str, unit: str = "") -> str:
    suffix = f" {unit}" if unit else ""
    return (
        f"median {signed(stats['median'], precision)}{suffix}; "
        f"range {signed(stats['min'], precision)} to {signed(stats['max'], precision)}{suffix}"
    )


def set_matplotlib_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "monospace",
            "font.monospace": [
                MONOSPACE_FONT,
                "Monaco",
                "Consolas",
                "Liberation Mono",
                "DejaVu Sans Mono",
                "monospace",
            ],
            "axes.grid": True,
            "grid.color": PLOT.colors["grid"],
            "grid.alpha": 0.25,
        }
    )


def scatter_panel(
    ax,
    data: pl.DataFrame,
    *,
    parameter: str,
    truth_field: str,
    retrieved_field: str,
    title: str,
) -> None:
    subset = data.filter(pl.col("parameter") == parameter)
    for model_label, color in zip(MODEL_LABELS.values(), MODEL_COLORS, strict=True):
        model_subset = subset.filter(pl.col("model_label") == model_label)
        ax.scatter(
            model_subset[truth_field].to_list(),
            model_subset[retrieved_field].to_list(),
            s=34,
            alpha=0.78,
            label=model_label,
            color=color,
            marker=MODEL_MARKERS[model_label],
        )
    truth_min = float(cast(float, subset[truth_field].min()))
    retrieved_min = float(cast(float, subset[retrieved_field].min()))
    truth_max = float(cast(float, subset[truth_field].max()))
    retrieved_max = float(cast(float, subset[retrieved_field].max()))
    min_value = min(truth_min, retrieved_min)
    max_value = max(truth_max, retrieved_max)
    pad = (max_value - min_value) * 0.04
    lower = min_value - pad
    upper = max_value + pad
    ax.plot(
        [lower, upper],
        [lower, upper],
        color="black",
        linestyle=(0, (4, 3)),
        linewidth=1,
    )
    ax.set_xlim(lower, upper)
    ax.set_ylim(lower, upper)
    ax.set_title(title, fontsize=20, pad=16)
    ax.set_xlabel("True value", fontsize=15, labelpad=14)
    ax.set_ylabel("Retrieved value", fontsize=15, labelpad=12, fontweight="bold")
    ax.tick_params(labelsize=12, pad=6)


def histogram_panel(
    ax,
    data: pl.DataFrame,
    *,
    parameter: str,
    title: str,
    subtitle: str,
    xlabel: str,
    bins: int = 45,
) -> None:
    subset = data.filter(pl.col("parameter") == parameter)
    ax.hist(subset["difference"].to_list(), bins=bins, color=PLOT.colors["blue"], alpha=0.78)
    ax.axvline(0.0, color="black", linestyle=(0, (4, 3)), linewidth=1)
    ax.set_title(f"{title}\n{subtitle}", fontsize=16, pad=16)
    ax.set_xlabel(xlabel, fontsize=15, labelpad=16, fontweight="bold")
    ax.set_ylabel("Count", fontsize=15, labelpad=12, fontweight="bold")
    ax.tick_params(labelsize=12, pad=6)
    ax.xaxis.set_major_locator(MaxNLocator(nbins=5))
    ax.yaxis.set_major_locator(MaxNLocator(nbins=6, integer=True))
    ax.minorticks_off()
    ax.grid(True, which="major", axis="both", alpha=0.25)


def save_retrieved_plot(frame: pl.DataFrame) -> None:
    set_matplotlib_style()
    retrieved = retrieved_rows(frame)
    scatter_data = retrieved.rename({"truth": "truth_value", "retrieved": "retrieved_value"})
    differences = paired_difference_rows(frame)
    difference_stats = paired_difference_stats(frame)
    fig, axes = plt.subplots(2, 2, figsize=(14, 11), dpi=180)
    fig.suptitle("Retrieved State Versus Truth", fontsize=24, y=0.982)
    fig.text(
        0.5,
        0.948,
        (
            "Top: each model retrieval against known synthetic truth. "
            "\nBottom: paired retrieval difference per scene "
            "(zdisamar - DISAMAR Fortran)."
        ),
        ha="center",
        va="top",
        fontsize=11,
        family="monospace",
    )
    scatter_panel(
        axes[0, 0],
        scatter_data,
        parameter="Aerosol mid pressure",
        truth_field="truth_value",
        retrieved_field="retrieved_value",
        title="Aerosol mid pressure",
    )
    scatter_panel(
        axes[0, 1],
        scatter_data,
        parameter="Aerosol optical depth",
        truth_field="truth_value",
        retrieved_field="retrieved_value",
        title="Aerosol optical depth",
    )
    histogram_panel(
        axes[1, 0],
        differences,
        parameter="Aerosol optical depth",
        title="Aerosol optical depth",
        subtitle=difference_subtitle(difference_stats["aerosol_optical_depth"], ".3e"),
        xlabel="zdisamar retrieved - DISAMAR retrieved",
    )
    histogram_panel(
        axes[1, 1],
        differences,
        parameter="Aerosol mid pressure [hPa]",
        title="Aerosol mid pressure [hPa]",
        subtitle=difference_subtitle(
            difference_stats["aerosol_mid_pressure_hpa"],
            ".4f",
            "hPa",
        ),
        xlabel="zdisamar retrieved - DISAMAR retrieved [hPa]",
    )
    handles, labels = axes[0, 0].get_legend_handles_labels()
    legend = fig.legend(
        handles,
        labels,
        loc="upper center",
        bbox_to_anchor=(0.5, 0.902),
        ncols=2,
        frameon=True,
        fontsize=12,
    )
    legend.get_frame().set_edgecolor("#cccccc")
    legend.get_frame().set_facecolor("white")
    fig.subplots_adjust(
        left=0.08,
        right=0.985,
        top=0.77,
        bottom=0.085,
        hspace=0.64,
        wspace=0.32,
    )
    fig.savefig(RETRIEVED_PLOT_PATH, bbox_inches="tight")
    plt.close(fig)


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
    differences = paired_difference_stats(frame)
    return {
        "source_data": DATA_PATH.relative_to(REPO_ROOT).as_posix(),
        "source_rows": frame.height,
        "source_ok_rows": ok.height,
        "plots": {
            "retrieved_scatter": stable_repo_path(RETRIEVED_PLOT_PATH),
            "error_histograms": stable_repo_path(ERROR_HISTOGRAM_PATH),
            "latency": stable_repo_path(LATENCY_PLOT_PATH),
        },
        "paired_difference": differences,
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
