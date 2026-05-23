import argparse
import json
from pathlib import Path
from typing import cast

import altair as alt
import polars as pl

ROOT = Path(__file__).resolve().parents[2]
PIPELINE_DIR = ROOT / "research" / "data-pipeline"
DEFAULT_SWEEP_ROOT = PIPELINE_DIR / "data" / "full-spectrum-758-770-ms"
DEFAULT_OUTPUT_DIR = PIPELINE_DIR / "reports" / "calculation-telemetry-latest"
LOG_EPSILON = 1.0e-300

DECISION_TABLE = "decision_rows"
SCALAR_TABLE = "scalar_expression_rows"
REDUCTION_TABLE = "reduction_expression_rows"


def main() -> None:

    args = parse_args()
    sweep_root = args.sweep_root.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    tables_dir = output_dir / "tables"
    tables_dir.mkdir(exist_ok=True)
    plot_files: dict[str, Path] = {}

    if not args.skip_plots:
        plots_dir = output_dir / "plots"
        plots_dir.mkdir(exist_ok=True)
        alt.data_transformers.disable_max_rows()

    scene_catalog = pl.read_parquet(sweep_root / "scene_catalog.parquet")
    scenes = scene_ids(scene_catalog)
    expression_catalog = pl.read_parquet(sweep_root / scenes[0] / "expression_catalog.parquet")

    decision_scan = scan_sweep_table(sweep_root, scenes, DECISION_TABLE)
    scalar_scan = scan_sweep_table(sweep_root, scenes, SCALAR_TABLE)
    reduction_scan = scan_sweep_table(sweep_root, scenes, REDUCTION_TABLE)

    decision_summary = collect_decision_summary(decision_scan, expression_catalog)
    decision_by_scene = collect_decision_by_scene(decision_scan, expression_catalog)
    qseries_by_scene = collect_qseries_by_scene(decision_scan, scene_catalog)
    qseries_by_coordinate = collect_qseries_by_coordinate(decision_scan, expression_catalog)
    qseries_downstream = collect_qseries_downstream(decision_scan, expression_catalog)
    orders_by_order = collect_orders_by_order(decision_scan)
    layer_doubling = collect_layer_doubling(decision_scan)
    layer_doubling_classes = collect_layer_doubling_classes(decision_scan)
    scalar_summary = collect_scalar_summary(scalar_scan, expression_catalog)
    fourier_by_index = collect_fourier_by_index(scalar_scan, decision_scan)
    reduction_rows = collect_reduction_rows(reduction_scan, expression_catalog)
    event_volume = collect_event_volume(scene_catalog)

    write_tables(
        tables_dir,
        {
            "event_volume.csv": event_volume,
            "decision_summary.csv": decision_summary,
            "decision_by_scene.csv": decision_by_scene,
            "qseries_by_scene.csv": qseries_by_scene,
            "qseries_by_coordinate.csv": qseries_by_coordinate,
            "qseries_downstream.csv": qseries_downstream,
            "orders_by_order.csv": orders_by_order,
            "layer_doubling_by_layer.csv": layer_doubling,
            "layer_doubling_coordinate_classes.csv": layer_doubling_classes,
            "scalar_summary.csv": scalar_summary,
            "fourier_by_index.csv": fourier_by_index,
            "reduction_rows.csv": reduction_rows,
        },
    )

    if not args.skip_plots:
        plot_files = write_plots(
            plots_dir,
            scene_catalog,
            event_volume,
            decision_summary,
            qseries_by_scene,
            layer_doubling,
            fourier_by_index,
            reduction_rows,
        )

    report = build_report(
        sweep_root,
        scene_catalog,
        event_volume,
        decision_summary,
        qseries_by_scene,
        qseries_by_coordinate,
        qseries_downstream,
        orders_by_order,
        layer_doubling,
        layer_doubling_classes,
        scalar_summary,
        fourier_by_index,
        reduction_rows,
        plot_files,
    )
    (output_dir / "report.md").write_text(report)
    (output_dir / "manifest.json").write_text(
        json.dumps(
            {
                "sweep_root": display_path(sweep_root),
                "report": display_path(output_dir / "report.md"),
                "plots": {name: display_path(path) for name, path in plot_files.items()},
            },
            indent=2,
        )
        + "\n",
    )
    print(f"wrote calculation telemetry analysis to {display_path(output_dir)}")


def parse_args() -> argparse.Namespace:

    parser = argparse.ArgumentParser(
        description="Analyze calculation telemetry Parquet data for math-level pruning candidates.",
    )
    parser.add_argument("--sweep-root", type=Path, default=DEFAULT_SWEEP_ROOT)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--skip-plots", action="store_true")

    return parser.parse_args()


def scene_ids(scene_catalog: pl.DataFrame) -> list[str]:

    return [str(value) for value in scene_catalog.get_column("scene_id").to_list()]


def scan_sweep_table(sweep_root: Path, scenes: list[str], table_name: str) -> pl.LazyFrame:

    scans: list[pl.LazyFrame] = []

    for scene in scenes:
        path = sweep_root / scene / f"{table_name}.parquet"

        if not path.exists():
            raise FileNotFoundError(f"missing telemetry table: {path}")

        scans.append(pl.scan_parquet(path).with_columns(pl.lit(scene).alias("scene_id")))

    return pl.concat(scans)


def collect_decision_summary(
    decision_scan: pl.LazyFrame,
    expression_catalog: pl.DataFrame,
) -> pl.DataFrame:

    log_ratio = threshold_log_ratio()

    return collect_frame(
        decision_scan.group_by("expr_id")
        .agg(
            pl.len().alias("rows"),
            pl.col("taken").mean().alias("taken_fraction"),
            pl.col("work_if_taken").sum().alias("work_if_taken_sum"),
            pl.col("work_if_not_taken").sum().alias("work_if_not_taken_sum"),
            pl.col("margin").quantile(0.001).alias("margin_p001"),
            pl.col("margin").quantile(0.01).alias("margin_p01"),
            pl.col("margin").median().alias("margin_p50"),
            pl.col("margin").quantile(0.99).alias("margin_p99"),
            pl.col("margin").quantile(0.999).alias("margin_p999"),
            log_ratio.quantile(0.01).alias("log_ratio_p01"),
            log_ratio.median().alias("log_ratio_p50"),
            log_ratio.quantile(0.99).alias("log_ratio_p99"),
        )
        .join(catalog_lazy(expression_catalog), on="expr_id")
        .sort("rows", descending=True)
    )


def collect_decision_by_scene(
    decision_scan: pl.LazyFrame,
    expression_catalog: pl.DataFrame,
) -> pl.DataFrame:

    log_ratio = threshold_log_ratio()

    return collect_frame(
        decision_scan.group_by("scene_id", "expr_id")
        .agg(
            pl.len().alias("rows"),
            pl.col("taken").mean().alias("taken_fraction"),
            log_ratio.median().alias("log_ratio_p50"),
        )
        .join(catalog_lazy(expression_catalog), on="expr_id")
        .sort("expr_id", "scene_id")
    )


def collect_qseries_by_scene(
    decision_scan: pl.LazyFrame,
    scene_catalog: pl.DataFrame,
) -> pl.DataFrame:

    log_ratio = threshold_log_ratio()

    return collect_frame(
        decision_scan.filter(pl.col("expr_id") == 12)
        .group_by("scene_id")
        .agg(
            pl.len().alias("rows"),
            pl.col("taken").mean().alias("skip_fraction"),
            log_ratio.quantile(0.01).alias("log_ratio_p01"),
            log_ratio.median().alias("log_ratio_p50"),
            log_ratio.quantile(0.99).alias("log_ratio_p99"),
        )
        .join(
            scene_catalog.lazy().select(
                "scene_id",
                "surface_albedo",
                "aerosol_optical_depth",
                "solar_zenith_deg",
                "viewing_zenith_deg",
                "relative_azimuth_deg",
                "total_event_rows",
            ),
            on="scene_id",
        )
        .sort("skip_fraction")
    )


def collect_qseries_by_coordinate(
    decision_scan: pl.LazyFrame,
    expression_catalog: pl.DataFrame,
) -> pl.DataFrame:

    log_ratio = threshold_log_ratio()

    return collect_frame(
        decision_scan.filter(pl.col("expr_id") == 12)
        .group_by("layer_index", "fourier_index", "order_index", "state_index")
        .agg(
            pl.len().alias("rows"),
            pl.col("taken").mean().alias("skip_fraction"),
            pl.col("taken").min().alias("min_skip"),
            pl.col("taken").max().alias("max_skip"),
            log_ratio.median().alias("log_ratio_p50"),
        )
        .with_columns(
            threshold_class("min_skip", "max_skip", "always_skip", "never_skip").alias(
                "skip_class"
            ),
            pl.lit(12).alias("expr_id"),
        )
        .join(catalog_lazy(expression_catalog), on="expr_id")
        .sort("layer_index", "fourier_index", "order_index", "state_index")
    )


def collect_qseries_downstream(
    decision_scan: pl.LazyFrame,
    expression_catalog: pl.DataFrame,
) -> pl.DataFrame:

    log_ratio = threshold_log_ratio()

    return collect_frame(
        decision_scan.filter(pl.col("expr_id").is_in([13, 14, 15]))
        .with_columns((pl.col("branch") == 1).alias("qseries_is_zero"))
        .group_by("expr_id", "qseries_is_zero")
        .agg(
            pl.len().alias("rows"),
            pl.col("taken").mean().alias("nonzero_fraction"),
            pl.col("taken").min().alias("min_nonzero"),
            pl.col("taken").max().alias("max_nonzero"),
            log_ratio.quantile(0.01).alias("log_ratio_p01"),
            log_ratio.median().alias("log_ratio_p50"),
            log_ratio.quantile(0.99).alias("log_ratio_p99"),
        )
        .with_columns(
            threshold_class(
                "min_nonzero",
                "max_nonzero",
                "always_nonzero",
                "always_zero",
            ).alias("nonzero_class")
        )
        .join(catalog_lazy(expression_catalog), on="expr_id")
        .sort("expr_id", "qseries_is_zero")
    )


def collect_orders_by_order(decision_scan: pl.LazyFrame) -> pl.DataFrame:

    log_ratio = threshold_log_ratio()

    return collect_frame(
        decision_scan.filter(pl.col("expr_id") == 20)
        .group_by("branch", "order_index")
        .agg(
            pl.len().alias("rows"),
            pl.col("taken").mean().alias("converged_fraction"),
            log_ratio.median().alias("log_ratio_p50"),
        )
        .sort("branch", "order_index")
    )


def collect_layer_doubling(decision_scan: pl.LazyFrame) -> pl.DataFrame:

    log_ratio = threshold_log_ratio()

    return collect_frame(
        decision_scan.filter(pl.col("expr_id") == 11)
        .group_by("layer_index")
        .agg(
            pl.len().alias("rows"),
            pl.col("taken").mean().alias("doubling_fraction"),
            log_ratio.quantile(0.01).alias("log_ratio_p01"),
            log_ratio.median().alias("log_ratio_p50"),
            log_ratio.quantile(0.99).alias("log_ratio_p99"),
        )
        .sort("layer_index")
    )


def collect_layer_doubling_classes(decision_scan: pl.LazyFrame) -> pl.DataFrame:

    log_ratio = threshold_log_ratio()

    return collect_frame(
        decision_scan.filter(pl.col("expr_id") == 11)
        .group_by("layer_index", "fourier_index", "branch")
        .agg(
            pl.len().alias("rows"),
            pl.col("taken").mean().alias("doubling_fraction"),
            pl.col("taken").min().alias("min_doubling"),
            pl.col("taken").max().alias("max_doubling"),
            pl.col("work_if_taken").mean().alias("mean_doubling_count"),
            log_ratio.median().alias("log_ratio_p50"),
        )
        .with_columns(
            threshold_class(
                "min_doubling",
                "max_doubling",
                "always_doubling",
                "never_doubling",
            ).alias("doubling_class")
        )
        .sort("layer_index", "fourier_index", "branch")
    )


def collect_scalar_summary(
    scalar_scan: pl.LazyFrame,
    expression_catalog: pl.DataFrame,
) -> pl.DataFrame:

    return collect_frame(
        scalar_scan.group_by("expr_id")
        .agg(
            pl.len().alias("rows"),
            pl.col("finite").mean().alias("finite_fraction"),
            pl.col("clamped").mean().alias("clamped_fraction"),
            pl.col("skipped").mean().alias("skipped_fraction"),
            (pl.col("abs_result") <= 1.0e-14).mean().alias("abs_le_1e_14"),
            (pl.col("abs_result") <= 1.0e-12).mean().alias("abs_le_1e_12"),
            (pl.col("abs_result") <= 1.0e-10).mean().alias("abs_le_1e_10"),
            pl.col("abs_result").quantile(0.001).alias("abs_p001"),
            pl.col("abs_result").quantile(0.01).alias("abs_p01"),
            pl.col("abs_result").median().alias("abs_p50"),
            pl.col("abs_result").quantile(0.99).alias("abs_p99"),
            pl.col("abs_result").max().alias("abs_max"),
            pl.col("relative_scale").quantile(0.01).alias("rel_p01"),
            pl.col("relative_scale").median().alias("rel_p50"),
            pl.col("relative_scale").quantile(0.99).alias("rel_p99"),
        )
        .join(catalog_lazy(expression_catalog), on="expr_id")
        .sort("rows", descending=True)
    )


def collect_fourier_by_index(
    scalar_scan: pl.LazyFrame,
    decision_scan: pl.LazyFrame,
) -> pl.DataFrame:

    scalar = (
        scalar_scan.filter(pl.col("expr_id") == 30)
        .group_by("fourier_index")
        .agg(
            pl.len().alias("rows"),
            pl.col("abs_result").median().alias("abs_p50"),
            pl.col("abs_result").quantile(0.9).alias("abs_p90"),
            pl.col("abs_result").quantile(0.99).alias("abs_p99"),
            (pl.col("abs_result") <= 1.0e-10).mean().alias("le_1e_10"),
            (pl.col("abs_result") <= 1.0e-8).mean().alias("le_1e_8"),
        )
    )
    tail = (
        decision_scan.filter(pl.col("expr_id") == 31)
        .group_by("fourier_index")
        .agg(
            pl.col("taken").mean().alias("tail_break_rate"),
            threshold_log_ratio().median().alias("tail_log_ratio_p50"),
        )
    )

    return collect_frame(scalar.join(tail, on="fourier_index").sort("fourier_index"))


def collect_reduction_rows(
    reduction_scan: pl.LazyFrame,
    expression_catalog: pl.DataFrame,
) -> pl.DataFrame:

    return collect_frame(
        reduction_scan.join(catalog_lazy(expression_catalog), on="expr_id").sort(
            "scene_id", "expr_id"
        )
    )


def collect_event_volume(scene_catalog: pl.DataFrame) -> pl.DataFrame:

    return scene_catalog.select(
        "scene_id",
        "surface_albedo",
        "aerosol_optical_depth",
        "solar_zenith_deg",
        "viewing_zenith_deg",
        "scalar_rows",
        "reduction_rows",
        "decision_rows",
        "total_event_rows",
        "parquet_bytes",
        "forward_wall_s",
    )


def threshold_log_ratio() -> pl.Expr:

    return ((pl.col("lhs").abs() + LOG_EPSILON) / (pl.col("threshold").abs() + LOG_EPSILON)).log10()


def threshold_class(
    min_column: str,
    max_column: str,
    always_true_label: str,
    always_false_label: str,
) -> pl.Expr:

    return (
        pl.when((pl.col(min_column) == 1) & (pl.col(max_column) == 1))
        .then(pl.lit(always_true_label))
        .when((pl.col(min_column) == 0) & (pl.col(max_column) == 0))
        .then(pl.lit(always_false_label))
        .otherwise(pl.lit("mixed"))
    )


def collect_frame(query: pl.LazyFrame) -> pl.DataFrame:

    return cast(pl.DataFrame, query.collect())


def catalog_lazy(expression_catalog: pl.DataFrame) -> pl.LazyFrame:

    return expression_catalog.lazy().select("expr_id", "expr_name", "row_table", "equation")


def write_tables(output_dir: Path, tables: dict[str, pl.DataFrame]) -> None:

    for name, frame in tables.items():
        frame.write_csv(output_dir / name)


def write_plots(
    plots_dir: Path,
    scene_catalog: pl.DataFrame,
    event_volume: pl.DataFrame,
    decision_summary: pl.DataFrame,
    qseries_by_scene: pl.DataFrame,
    layer_doubling: pl.DataFrame,
    fourier_by_index: pl.DataFrame,
    reduction_rows: pl.DataFrame,
) -> dict[str, Path]:

    plot_files = {
        "event_volume": plots_dir / "01_event_volume.html",
        "decision_thresholds": plots_dir / "02_decision_thresholds.html",
        "qseries_scene": plots_dir / "03_qseries_scene.html",
        "layer_doubling": plots_dir / "04_layer_doubling.html",
        "fourier_tail": plots_dir / "05_fourier_tail.html",
        "reduction_plan": plots_dir / "06_reduction_plan.html",
    }

    event_volume_chart(event_volume).save(plot_files["event_volume"])
    decision_threshold_chart(decision_summary).save(plot_files["decision_thresholds"])
    qseries_scene_chart(qseries_by_scene).save(plot_files["qseries_scene"])
    layer_doubling_chart(layer_doubling).save(plot_files["layer_doubling"])
    fourier_tail_chart(fourier_by_index).save(plot_files["fourier_tail"])
    reduction_plan_chart(scene_catalog, reduction_rows).save(plot_files["reduction_plan"])

    return plot_files


def event_volume_chart(event_volume: pl.DataFrame):

    frame = event_volume.select(
        "scene_id",
        "scalar_rows",
        "decision_rows",
        "reduction_rows",
    ).unpivot(
        index="scene_id",
        variable_name="row_table",
        value_name="rows",
    )

    return (
        alt.Chart(chart_data(frame))
        .mark_bar()
        .encode(
            x=alt.X("scene_id:N", sort="-y", title="Scene"),
            y=alt.Y("rows:Q", stack="zero", title="Captured rows"),
            color=alt.Color("row_table:N", title="Row table"),
            tooltip=["scene_id:N", "row_table:N", alt.Tooltip("rows:Q", format=",")],
        )
        .properties(width=820, height=360, title="Captured event volume by scene")
    )


def decision_threshold_chart(decision_summary: pl.DataFrame):

    return (
        alt.Chart(chart_data(decision_summary))
        .mark_circle(size=180)
        .encode(
            x=alt.X("taken_fraction:Q", title="Branch taken fraction"),
            y=alt.Y("expr_name:N", sort="-x", title="Decision expression"),
            size=alt.Size("rows:Q", title="Rows"),
            color=alt.Color("log_ratio_p50:Q", title="median log10(|lhs|/|threshold|)"),
            tooltip=[
                "expr_name:N",
                alt.Tooltip("rows:Q", format=","),
                alt.Tooltip("taken_fraction:Q", format=".3f"),
                alt.Tooltip("log_ratio_p01:Q", format=".2f"),
                alt.Tooltip("log_ratio_p50:Q", format=".2f"),
                alt.Tooltip("log_ratio_p99:Q", format=".2f"),
            ],
        )
        .properties(width=760, height=280, title="Decision branch stability and margin")
    )


def qseries_scene_chart(qseries_by_scene: pl.DataFrame):

    return (
        alt.Chart(chart_data(qseries_by_scene))
        .mark_circle(size=180)
        .encode(
            x=alt.X("aerosol_optical_depth:Q", title="AOD"),
            y=alt.Y("skip_fraction:Q", title="q-series skip fraction"),
            color=alt.Color("surface_albedo:Q", title="Albedo"),
            size=alt.Size("rows:Q", title="Rows"),
            tooltip=[
                "scene_id:N",
                alt.Tooltip("rows:Q", format=","),
                alt.Tooltip("skip_fraction:Q", format=".3f"),
                alt.Tooltip("log_ratio_p50:Q", format=".2f"),
                alt.Tooltip("surface_albedo:Q", format=".2f"),
                alt.Tooltip("aerosol_optical_depth:Q", format=".2f"),
            ],
        )
        .properties(width=720, height=360, title="q-series skip behavior by scene")
    )


def layer_doubling_chart(layer_doubling: pl.DataFrame):

    base = alt.Chart(chart_data(layer_doubling)).encode(
        x=alt.X("layer_index:Q", title="Layer index"),
        tooltip=[
            alt.Tooltip("layer_index:Q", format=".0f"),
            alt.Tooltip("rows:Q", format=","),
            alt.Tooltip("doubling_fraction:Q", format=".3f"),
            alt.Tooltip("log_ratio_p50:Q", format=".2f"),
        ],
    )

    fraction = base.mark_line(point=True).encode(
        y=alt.Y("doubling_fraction:Q", title="Doubling trigger fraction"),
    )
    ratio = base.mark_line(point=True, color="#b25c00").encode(
        y=alt.Y("log_ratio_p50:Q", title="median log10(tau_eff / threshold)"),
    )

    return alt.vconcat(fraction, ratio).properties(title="Layer-doubling trigger by layer")


def fourier_tail_chart(fourier_by_index: pl.DataFrame):

    magnitude = (
        fourier_by_index.select("fourier_index", "abs_p50", "abs_p90", "abs_p99")
        .unpivot(
            index="fourier_index",
            variable_name="quantile",
            value_name="abs_weighted_reflectance",
        )
        .with_columns(
            pl.when(pl.col("abs_weighted_reflectance") <= 0)
            .then(None)
            .otherwise(pl.col("abs_weighted_reflectance"))
            .alias("abs_weighted_reflectance")
        )
    )

    magnitude_chart = (
        alt.Chart(chart_data(magnitude))
        .mark_line()
        .encode(
            x=alt.X("fourier_index:Q", title="Fourier index"),
            y=alt.Y(
                "abs_weighted_reflectance:Q",
                scale=alt.Scale(type="log"),
                title="abs(weighted reflectance)",
            ),
            color=alt.Color("quantile:N", title="Quantile"),
            tooltip=[
                alt.Tooltip("fourier_index:Q", format=".0f"),
                "quantile:N",
                alt.Tooltip("abs_weighted_reflectance:Q", format=".3e"),
            ],
        )
        .properties(width=760, height=300, title="Fourier contribution decay")
    )
    tail_chart = (
        alt.Chart(chart_data(fourier_by_index))
        .mark_line(point=True, color="#6d5bd0")
        .encode(
            x=alt.X("fourier_index:Q", title="Fourier index"),
            y=alt.Y("tail_break_rate:Q", title="Tail break rate"),
            tooltip=[
                alt.Tooltip("fourier_index:Q", format=".0f"),
                alt.Tooltip("rows:Q", format=","),
                alt.Tooltip("tail_break_rate:Q", format=".3f"),
                alt.Tooltip("le_1e_10:Q", format=".3f"),
                alt.Tooltip("le_1e_8:Q", format=".3f"),
            ],
        )
        .properties(width=760, height=240, title="Observed tail-break rate")
    )

    return alt.vconcat(magnitude_chart, tail_chart)


def reduction_plan_chart(scene_catalog: pl.DataFrame, reduction_rows: pl.DataFrame):

    reflectance = (
        reduction_rows.filter(pl.col("expr_id") == 3)
        .join(
            scene_catalog.select(
                "scene_id",
                "surface_albedo",
                "aerosol_optical_depth",
                "solar_zenith_deg",
                "viewing_zenith_deg",
            ),
            on="scene_id",
        )
        .select(
            "scene_id",
            "surface_albedo",
            "aerosol_optical_depth",
            "result",
            "min_term",
        )
    )

    return (
        alt.Chart(chart_data(reflectance))
        .mark_circle(size=180)
        .encode(
            x=alt.X("aerosol_optical_depth:Q", title="AOD"),
            y=alt.Y("result:Q", title="max reflectance"),
            color=alt.Color("surface_albedo:Q", title="Albedo"),
            tooltip=[
                "scene_id:N",
                alt.Tooltip("aerosol_optical_depth:Q", format=".2f"),
                alt.Tooltip("surface_albedo:Q", format=".2f"),
                alt.Tooltip("result:Q", format=".4f"),
                alt.Tooltip("min_term:Q", format=".3e"),
            ],
        )
        .properties(width=720, height=360, title="Reflectance assembly range by scene")
    )


def chart_data(frame: pl.DataFrame) -> alt.Data:

    return alt.Data(values=frame.to_dicts())


def build_report(
    sweep_root: Path,
    scene_catalog: pl.DataFrame,
    event_volume: pl.DataFrame,
    decision_summary: pl.DataFrame,
    qseries_by_scene: pl.DataFrame,
    qseries_by_coordinate: pl.DataFrame,
    qseries_downstream: pl.DataFrame,
    orders_by_order: pl.DataFrame,
    layer_doubling: pl.DataFrame,
    layer_doubling_classes: pl.DataFrame,
    scalar_summary: pl.DataFrame,
    fourier_by_index: pl.DataFrame,
    reduction_rows: pl.DataFrame,
    plot_files: dict[str, Path],
) -> str:

    total_rows = int(scene_catalog.get_column("total_event_rows").sum())
    total_bytes = int(scene_catalog.get_column("parquet_bytes").sum())
    forward_s = float(scene_catalog.get_column("forward_wall_s").sum())

    qseries = row_by_expr(decision_summary, "labos_qseries_skip")
    doubling = row_by_expr(decision_summary, "labos_doubling_trigger")
    orders = row_by_expr(decision_summary, "orders_convergence")
    tail = row_by_expr(decision_summary, "fourier_tail_break")
    fourier = row_by_expr(scalar_summary, "fourier_weighted_reflectance")
    reflectance_clamp = row_by_expr(scalar_summary, "labos_reflectance_clamp")
    jacobian_norm = row_by_expr(scalar_summary, "labos_jacobian_norm1")

    qseries_min = qseries_by_scene.get_column("skip_fraction").min()
    qseries_max = qseries_by_scene.get_column("skip_fraction").max()
    high_fourier = fourier_by_index.filter(pl.col("fourier_index") >= 64)
    high_fourier_small = high_fourier.get_column("le_1e_10").min()
    always_no_doubling = layer_doubling.filter(pl.col("doubling_fraction") == 0)
    partial_doubling = layer_doubling.filter(
        (pl.col("doubling_fraction") > 0) & (pl.col("doubling_fraction") < 1)
    )
    qseries_coordinate_classes = class_counts(qseries_by_coordinate, "skip_class")
    layer_coordinate_classes = class_counts(layer_doubling_classes, "doubling_class")
    forward_reuse = reduction_rows.filter(pl.col("expr_name") == "forward_miss_reuse").row(
        0, named=True
    )
    sampling_shape = reduction_rows.filter(pl.col("expr_name") == "sampling_kernel_shape").row(
        0, named=True
    )
    qseries_rows = row_int(qseries, "rows")
    qseries_event_fraction = 100.0 * row_float(qseries, "rows") / total_rows
    qseries_family_rows = qseries_rows + int(qseries_downstream.get_column("rows").sum())
    qseries_family_fraction = 100.0 * qseries_family_rows / total_rows
    doubling_taken_pct = 100.0 * row_float(doubling, "taken_fraction")
    doubling_rows = row_int(doubling, "rows")
    orders_taken_pct = 100.0 * row_float(orders, "taken_fraction")
    tail_taken_pct = 100.0 * row_float(tail, "taken_fraction")
    qseries_min_pct = 100.0 * scalar_float(qseries_min)
    qseries_max_pct = 100.0 * scalar_float(qseries_max)
    fourier_abs_p50 = row_float(fourier, "abs_p50")
    fourier_le_1e_10_pct = 100.0 * row_float(fourier, "abs_le_1e_10")
    high_fourier_small_pct = 100.0 * scalar_float(high_fourier_small)
    clamp_pct = 100.0 * row_float(reflectance_clamp, "clamped_fraction")
    jacobian_zero_pct = 100.0 * row_float(jacobian_norm, "abs_le_1e_14")
    forward_miss_count = row_int(forward_reuse, "nonzero_count")
    forward_reference_count = row_int(forward_reuse, "term_count")
    forward_unique_pct = 100.0 * row_float(forward_reuse, "mean")
    side_sample_count = int(row_float(sampling_shape, "result"))

    lines = [
        "# Calculation Telemetry Analysis",
        "",
        f"- Sweep root: `{display_path(sweep_root)}`",
        f"- Scenes: {scene_catalog.height}",
        f"- Event rows: {total_rows:,}",
        f"- Parquet bytes: {total_bytes:,}",
        f"- Forward wall time captured by telemetry executable: {forward_s:.2f} s",
        "",
        "These are research observations from the captured numeric state. They are not",
        "drop-in model changes; each optimization needs a same-boundary runtime benchmark",
        "and a scientific precision gate before it is accepted.",
        "",
        "## 1. Event Volume And Row Drivers",
        "",
        *plot_line("event_volume", plot_files),
        "Decision rows dominate the captured stream. The q-series threshold family",
        f"contains {qseries_family_rows:,} rows, which is "
        f"{qseries_family_fraction:.1f}% of all captured events. The base",
        f"`labos_qseries_skip` expression contributes {qseries_rows:,} rows "
        f"({qseries_event_fraction:.1f}%).",
        "This says the first mathematical target is not spectral-grid setup but the",
        "matrix-product/q-series decision surface inside LABOS doubling.",
        "",
        "Optimization opportunity: make q-series zero classification cheaper or move",
        "more of it into a prepared per-layer/per-Fourier state. This is the biggest",
        "observable repeated calculation in the current capture.",
        "",
        "## 2. Decision Threshold Behavior",
        "",
        *plot_line("decision_thresholds", plot_files),
        f"`labos_doubling_trigger` is taken {doubling_taken_pct:.1f}% "
        f"of the time over {doubling_rows:,} rows. `orders_convergence` reports "
        f"convergence for {orders_taken_pct:.1f}% of rows, but the",
        "late-order rows show the cap is still active. `fourier_tail_break` is taken",
        f"only {tail_taken_pct:.1f}% of rows, despite the Fourier",
        "contribution distribution becoming tiny at high indices.",
        "",
        "Optimization opportunity: treat these threshold checks as mathematical state",
        "classifiers, not generic branches. The report tables show which thresholds",
        "are usually far from their boundary and which are genuinely marginal.",
        "",
        "## 3. q-Series Skip Surface",
        "",
        *plot_line("qseries_scene", plot_files),
        f"The q-series skip fraction ranges from {qseries_min_pct:.1f}% to "
        f"{qseries_max_pct:.1f}% by scene. The scene ordering follows aerosol",
        "and geometry enough that a single global branch-rate assumption would be weak.",
        "The median `log10(abs(lhs)/threshold)` moves from below zero in clean scenes to",
        "above zero in dense scenes.",
        "",
        "The q-series rows now carry layer, Fourier index, doubling-step index, and",
        "phase-max coordinates. Coordinate classes across the sweep:",
        f"- always skipped: {qseries_coordinate_classes.get('always_skip', 0):,}",
        f"- never skipped: {qseries_coordinate_classes.get('never_skip', 0):,}",
        f"- mixed: {qseries_coordinate_classes.get('mixed', 0):,}",
        "",
        "Optimization opportunity: use the mixed coordinate set as the risk boundary.",
        "Always-skip coordinates are candidates for prepared zero-work handling; mixed",
        "coordinates need the current exact threshold until precision tests prove more.",
        "",
        "## 4. q-Series Downstream Gates",
        "",
        *qseries_downstream_lines(qseries_downstream),
        "",
        "These rows answer whether `qseries_is_zero` merely skips the q-series product",
        "or whether it also predicts the later `R-D`, `T-U`, and `T-D` products. The",
        "`qseries_is_zero=false` rows are almost always nonzero downstream, so the",
        "current heavy path is justified there. The `qseries_is_zero=true` rows are",
        "mostly zero downstream but not universally zero, so the opportunity is a",
        "specialized q-zero path with its own smaller gates, not a blanket removal of",
        "all downstream work.",
        "",
        "## 5. Layer-Doubling Trigger By Layer",
        "",
        *plot_line("layer_doubling", plot_files),
        "",
        f"{always_no_doubling.height} layers never trigger doubling in this sweep, and "
        f"{partial_doubling.height} layers are mixed. The middle aerosol interval is",
        "mostly above threshold; the upper tail layers are consistently below it.",
        "",
        "Layer/Fourier/phase coordinate classes across the sweep:",
        f"- always doubling: {layer_coordinate_classes.get('always_doubling', 0):,}",
        f"- never doubling: {layer_coordinate_classes.get('never_doubling', 0):,}",
        f"- mixed: {layer_coordinate_classes.get('mixed', 0):,}",
        "",
        "Optimization opportunity: pre-partition layers into always-doubling, mixed, and",
        "always-thin groups after scene preparation. That would avoid re-evaluating the",
        "same depth test in the inner Fourier/layer loops and keep the mixed set explicit",
        "for precision-sensitive cases.",
        "",
        "## 6. Fourier Tail And Contribution Magnitudes",
        "",
        *plot_line("fourier_tail", plot_files),
        "`fourier_weighted_reflectance` has median absolute result "
        f"{fourier_abs_p50:.3e}; {fourier_le_1e_10_pct:.1f}% of rows are below "
        "1e-10. For",
        f"Fourier indices >= 64, at least {high_fourier_small_pct:.1f}% of rows",
        "are below 1e-10, while the tail-break rule only becomes universal at the final",
        "captured index.",
        "",
        "Optimization opportunity: the tail rule appears conservative relative to the",
        "observed contribution magnitudes. A precision-bounded experiment should test an",
        "earlier Fourier stop based on cumulative reflectance contribution, not only the",
        "per-term threshold currently captured.",
        "",
        "## 7. Scalar Redundancy And Reduction Shape",
        "",
        *plot_line("reduction_plan", plot_files),
        f"`labos_reflectance_clamp` clamped {clamp_pct:.1f}% "
        "of rows in this sweep, so the clamp is a cold safety boundary here. "
        f"`labos_jacobian_norm1` is exactly zero for {jacobian_zero_pct:.1f}% "
        "of rows because this sweep did not request Jacobians.",
        "",
        f"The spectral miss plan has {forward_miss_count:,} unique misses over "
        f"{forward_reference_count:,} sample-index references "
        f"({forward_unique_pct:.2f}%). The sampling kernel still carries",
        f"{side_sample_count:,} side samples for this 401-sample 758-770 nm grid.",
        "",
        "Optimization opportunity: the wavelength-cache reuse is already strong, so the",
        "remaining grid math is likely side-storage movement and aggregation verbosity.",
        "For no-Jacobian routes, remove derivative-norm work from the route entirely",
        "rather than recording or summing zeros.",
        "",
        "## Output Tables",
        "",
        "- `tables/event_volume.csv`",
        "- `tables/decision_summary.csv`",
        "- `tables/decision_by_scene.csv`",
        "- `tables/qseries_by_scene.csv`",
        "- `tables/qseries_by_coordinate.csv`",
        "- `tables/qseries_downstream.csv`",
        "- `tables/orders_by_order.csv`",
        "- `tables/layer_doubling_by_layer.csv`",
        "- `tables/layer_doubling_coordinate_classes.csv`",
        "- `tables/scalar_summary.csv`",
        "- `tables/fourier_by_index.csv`",
        "- `tables/reduction_rows.csv`",
        "",
    ]

    return "\n".join(lines)


def row_by_expr(frame: pl.DataFrame, expr_name: str) -> dict[str, object]:

    matches = frame.filter(pl.col("expr_name") == expr_name)

    if matches.height != 1:
        raise ValueError(f"expected one row for expression {expr_name}, got {matches.height}")

    return matches.row(0, named=True)


def plot_line(name: str, plot_files: dict[str, Path]) -> list[str]:

    if name not in plot_files:
        return []

    path = display_path(plot_files[name])

    return [f"Plot: [`{path}`]({path})", ""]


def qseries_downstream_lines(frame: pl.DataFrame) -> list[str]:

    lines = [
        "| Gate | q-series zero | Rows | Nonzero fraction | Class | Median log ratio |",
        "| --- | ---: | ---: | ---: | --- | ---: |",
    ]

    for row in frame.iter_rows(named=True):
        lines.append(
            "| {gate} | {qzero} | {rows:,} | {fraction:.3f} | {class_name} | {ratio:.2f} |".format(
                gate=str(row["expr_name"]).removeprefix("labos_qseries_"),
                qzero=int(bool(row["qseries_is_zero"])),
                rows=scalar_int(row["rows"]),
                fraction=scalar_float(row["nonzero_fraction"]),
                class_name=str(row["nonzero_class"]),
                ratio=scalar_float(row["log_ratio_p50"]),
            )
        )

    return lines


def class_counts(frame: pl.DataFrame, class_column: str) -> dict[str, int]:

    counts: dict[str, int] = {}

    for row in frame.group_by(class_column).len().iter_rows(named=True):
        counts[str(row[class_column])] = scalar_int(row["len"])

    return counts


def row_float(row: dict[str, object], key: str) -> float:

    return scalar_float(row[key])


def row_int(row: dict[str, object], key: str) -> int:

    return scalar_int(row[key])


def scalar_float(value: object) -> float:

    if isinstance(value, int | float):
        return float(value)

    raise TypeError(f"expected numeric value, got {type(value).__name__}")


def scalar_int(value: object) -> int:

    if isinstance(value, int):
        return value

    if isinstance(value, float):
        return int(value)

    raise TypeError(f"expected integer value, got {type(value).__name__}")


def display_path(path: Path) -> str:

    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


if __name__ == "__main__":
    main()
