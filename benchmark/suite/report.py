"""Final JSON report generation."""

import json
import subprocess
import time
from pathlib import Path
from typing import Any

from . import config
from .db import BenchmarkDb
from .stats import json_ready


def git_metadata() -> dict[str, Any]:

    return {
        "branch": git_output("rev-parse", "--abbrev-ref", "HEAD"),
        "commit": git_output("rev-parse", "HEAD"),
        "dirty_before_run": bool(git_output("status", "--short")),
    }


def git_output(*args: str) -> str:

    completed = subprocess.run(
        ["git", *args],
        cwd=config.REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )

    return completed.stdout.strip()


def build_results(
    db: BenchmarkDb,
    run_id: str,
    *,
    total_benchmark_wall_s: float,
    total_benchmark_process_cpu_s: float,
    memory: dict[str, Any],
    memory_layout: dict[str, Any],
) -> dict[str, Any]:

    run = db.run_payload(run_id)
    summaries = db.summaries(run_id)
    native_binding = summaries["native_binding"]
    forward = {
        "no_session": summaries["forward_no_session"],
        "session": summaries["forward_session"],
        "fast_mode": summaries["forward_fast_mode"],
    }
    retrieval = retrieval_payload(summaries)

    cases = {
        "forward_no_session": forward["no_session"],
        "forward_session": forward["session"],
        "forward_fast_mode": forward["fast_mode"],
    }
    comparisons: dict[str, Any] = {}
    if retrieval["status"] == "skipped":
        cases["retrieval_skipped"] = retrieval
    else:
        cases.update(
            {
                "retrieval_session": retrieval["single"]["session"],
                "retrieval_fast_mode": retrieval["single"]["fast_mode"],
                "retrieval_sweep_session": retrieval["sweep"]["session"],
                "retrieval_sweep_fast_mode": retrieval["sweep"]["fast_mode"],
            }
        )
        comparisons.update(
            {
                "retrieval_fast_minus_session_single_case": retrieval["single"][
                    "fast_minus_session"
                ],
                "retrieval_sweep_fast_minus_session": retrieval["sweep"]["fast_minus_session"],
            }
        )

    return {
        "schema_version": config.SCHEMA_VERSION,
        "benchmark": config.BENCHMARK_NAME,
        "run_id": run_id,
        "created_at_unix_s": run["started_at_unix_s"],
        "finished_at_unix_s": run["finished_at_unix_s"] or time.time(),
        "total_benchmark_wall_s": total_benchmark_wall_s,
        "total_benchmark_process_cpu_s": total_benchmark_process_cpu_s,
        "total_benchmark_average_active_cores": active_cores(
            total_benchmark_process_cpu_s,
            total_benchmark_wall_s,
        ),
        "memory": memory,
        "memory_layout": memory_layout,
        "command": config.COMMAND,
        "output": "benchmark/results.json",
        "scratch_db": "benchmark/.runs/benchmark.sqlite",
        "run_controls": config.run_controls(),
        "native_binding": native_binding,
        "cases": cases,
        "comparisons": comparisons,
        "report": build_compact_report(forward, retrieval, memory, memory_layout),
    }


def retrieval_payload(summaries: dict[str, Any]) -> dict[str, Any]:

    if "retrieval_skipped" in summaries:
        return summaries["retrieval_skipped"]

    return {
        "status": "complete",
        "single": {
            "session": summaries["retrieval_session"],
            "fast_mode": summaries["retrieval_fast_mode"],
            "fast_minus_session": summaries["retrieval_fast_minus_session_single_case"],
        },
        "sweep": {
            "session": summaries["retrieval_sweep_session"],
            "fast_mode": summaries["retrieval_sweep_fast_mode"],
            "fast_minus_session": summaries["retrieval_sweep_fast_minus_session"],
        },
    }


def build_compact_report(
    forward: dict[str, Any],
    retrieval: dict[str, Any],
    memory: dict[str, Any],
    memory_layout: dict[str, Any],
) -> dict[str, list[dict[str, str]]]:

    no_session = forward["no_session"]
    session = forward["session"]
    fast_forward = forward["fast_mode"]

    case_rows = [
        {
            "case": "Forward, no session",
            "timing": f"median {no_session['timing_s']['median']:.3f}s",
            "residuals": format_forward_residuals(no_session),
        },
        {
            "case": "Forward, session",
            "timing": (
                f"setup {session['timing_s']['setup_s']:.3f}s; "
                f"cached run {session['timing_s']['cached_run_s']['median']:.3f}s; "
                f"first-use {session['timing_s']['first_use_total_s']:.3f}s"
            ),
            "residuals": format_session_delta(session),
        },
        {
            "case": "Forward, fast mode",
            "timing": (
                "baseline reference "
                f"{fast_forward['timing_s']['baseline_reference_run_s']['median']:.3f}s; "
                "4-scene fast median "
                f"{fast_forward['timing_s']['four_scene_fast_total_s']['median']:.3f}s"
            ),
            "residuals": format_fast_forward_residuals(fast_forward),
        },
    ]
    if retrieval["status"] == "skipped":
        case_rows.append(
            {
                "case": "OE, retrieval",
                "timing": "skipped",
                "residuals": f"{retrieval['owner']}: {retrieval['reason']}",
            }
        )
    else:
        retrieval_session = retrieval["single"]["session"]
        retrieval_fast = retrieval["single"]["fast_mode"]
        retrieval_sweep = retrieval["sweep"]
        fast_sweep_timing = retrieval_sweep["fast_mode"]["timing_s"]["first_use_total_s"]
        sweep_count = retrieval_sweep["fast_mode"]["run_count"]
        case_rows.extend(
            [
                {
                    "case": "OE, session",
                    "timing": (
                        "retrieval "
                        f"{retrieval_session['timing_s']['retrieval_s']['median']:.6f}s; "
                        f"setup {retrieval_session['timing_s']['setup_s']['median']:.6f}s"
                    ),
                    "residuals": format_retrieval_truth_residuals(retrieval_session),
                },
                {
                    "case": "OE, fast mode",
                    "timing": (
                        f"{sweep_count}-case median "
                        f"{fast_sweep_timing['median']:.6f}s; "
                        f"mean {fast_sweep_timing['mean']:.6f}s; "
                        f"range {fast_sweep_timing['min']:.6f}-"
                        f"{fast_sweep_timing['max']:.6f}s"
                    ),
                    "residuals": format_fast_retrieval_residuals(
                        retrieval_fast,
                        retrieval_sweep,
                    ),
                },
            ]
        )

    return {
        "case_rows": case_rows,
        "total_wall_clock_rows": total_wall_rows(forward, retrieval),
        "resource_rows": resource_rows(forward, retrieval, memory),
        "memory_layout_rows": memory_layout_rows(memory_layout),
    }


def memory_layout_rows(memory_layout: dict[str, Any]) -> list[dict[str, str]]:

    instrument = memory_layout["instrument_sampling"]
    optical = memory_layout["optical_accumulation"]
    support = instrument["support_count_stats"]

    return [
        {
            "area": "Instrument sampling plan",
            "shape": (
                f"{instrument['nominal_sample_count']} wavelengths, "
                f"{instrument['kernel_count']} channel kernels, "
                f"support count median {support['median']:.1f}, max {support['max']}"
            ),
            "memory": (
                f"current owned plan {instrument['current_owned_wavelength_sampling_bytes']} B; "
                "estimated row payload saved "
                f"{instrument['estimated_row_payload_saved_mib']:.2f} MiB"
            ),
        },
        {
            "area": "Integration kernel scratch",
            "shape": (
                f"{instrument['estimated_sampling_worker_count']} sampling worker(s), "
                f"{instrument['integration_kernel_scratch_bytes_per_worker']} B each"
            ),
            "memory": (
                f"{instrument['integration_kernel_scratch_bytes_at_worker_count']} B transient"
            ),
        },
        {
            "area": "Collision-complex profile cache",
            "shape": (
                f"{optical['benchmark_profile_node_count']} profile nodes, "
                f"capacity {optical['collision_complex_profile_cache_capacity']}"
            ),
            "memory": (
                "request cache "
                f"{optical['previous_collision_complex_profile_cache_bytes']} -> "
                f"{optical['current_collision_complex_profile_cache_bytes']} B; "
                "sample spline scratch "
                f"{optical['previous_collision_complex_sample_spline_scratch_bytes']} -> "
                f"{optical['current_collision_complex_sample_spline_scratch_bytes']} B"
            ),
        },
    ]


def format_forward_residuals(case: dict[str, Any]) -> str:

    metrics = case["residuals"]["disamar_reference"]["series"]
    worst = case["residuals"]["disamar_reference"]["worst_interior_max_abs"]
    reflectance = metrics["RTM reflectance"]["max_abs_residual"]

    return f"DISAMAR fixture worst interior max_abs {worst:.3e}; RTM reflectance {reflectance:.3e}"


def format_session_delta(case: dict[str, Any]) -> str:

    delta = case["residuals"]["vs_no_session"]

    return (
        "vs no-session: "
        f"radiance max_abs {delta['radiance_max_abs']:.3e}; "
        f"reflectance max_abs {delta['reflectance_max_abs']:.3e}"
    )


def format_fast_forward_residuals(case: dict[str, Any]) -> str:

    residual_payload = case["residuals"]
    worst = residual_payload["worst_scene"]

    return (
        f"baseline max_abs {residual_payload['baseline_max_abs']:.3e}; "
        f"4-scene worst {worst['max_abs_residual']:.3e}, "
        f"{worst['max_abs_residual_over_noise']:.3f}x noise"
    )


def format_retrieval_truth_residuals(case: dict[str, Any]) -> str:

    residual_payload = case["residuals"]

    return (
        f"AOD diff {residual_payload['aerosol_optical_depth_abs_diff']:.3e}; "
        "mid-pressure diff "
        f"{residual_payload['aerosol_layer_mid_pressure_abs_diff_hpa']:.3e} hPa"
    )


def format_fast_retrieval_residuals(
    fast: dict[str, Any],
    sweep: dict[str, Any],
) -> str:

    single = fast["residuals"]
    delta = sweep["fast_minus_session"]

    return (
        f"single fast-vs-session AOD delta {single['aerosol_optical_depth_delta']:.3e}; "
        f"sweep max AOD delta {delta['aerosol_optical_depth_delta']['max_abs']:.3e}; "
        f"pressure delta {delta['aerosol_mid_pressure_delta_hpa']['max_abs']:.3e} hPa"
    )


def total_wall_rows(
    forward: dict[str, Any],
    retrieval: dict[str, Any],
) -> list[dict[str, str]]:

    if retrieval["status"] == "skipped":
        return [
            {
                "benchmark": "Forward, no session",
                "total": (
                    f"{forward['no_session']['timing_s']['median']:.3f}s per baseline run median"
                ),
            },
            {
                "benchmark": "Forward, session",
                "total": (
                    f"{forward['session']['timing_s']['first_use_total_s']:.3f}s "
                    "first-use total, or "
                    f"{forward['session']['timing_s']['cached_run_s']['median']:.3f}s "
                    "cached run only"
                ),
            },
            {
                "benchmark": "Forward, fast mode",
                "total": (
                    f"{forward['fast_mode']['timing_s']['four_scene_fast_total_s']['median']:.3f}s "
                    "median over 4 scenes"
                ),
            },
            {
                "benchmark": "OE retrieval",
                "total": f"skipped until {retrieval['owner']}: {retrieval['reason']}",
            },
        ]

    sweep = retrieval["sweep"]
    session_count = sweep["session"]["run_count"]
    fast_count = sweep["fast_mode"]["run_count"]

    return [
        {
            "benchmark": "Forward, no session",
            "total": f"{forward['no_session']['timing_s']['median']:.3f}s per baseline run median",
        },
        {
            "benchmark": "Forward, session",
            "total": (
                f"{forward['session']['timing_s']['first_use_total_s']:.3f}s first-use total, "
                f"or {forward['session']['timing_s']['cached_run_s']['median']:.3f}s "
                "cached run only"
            ),
        },
        {
            "benchmark": "Forward, fast mode",
            "total": (
                f"{forward['fast_mode']['timing_s']['four_scene_fast_total_s']['median']:.3f}s "
                "median over 4 scenes"
            ),
        },
        {
            "benchmark": "OE, no fast mode",
            "total": (
                f"{sweep['session']['timing_s']['total_wall_s']:.3f}s "
                f"over {session_count} retrievals"
            ),
        },
        {
            "benchmark": "OE, fast mode",
            "total": (
                f"{sweep['fast_mode']['timing_s']['total_wall_s']:.3f}s "
                f"over {fast_count} retrievals"
            ),
        },
        {
            "benchmark": "OE fast-mode savings",
            "total": (
                f"{sweep['fast_minus_session']['total_retrieval_wall_s_saved']:.3f}s "
                f"over {min(session_count, fast_count)} retrievals"
            ),
        },
    ]


def resource_rows(
    forward: dict[str, Any],
    retrieval: dict[str, Any],
    memory: dict[str, Any],
) -> list[dict[str, str]]:

    rows = [
        {
            "benchmark": "Full benchmark process",
            "process_cpu": "see top-level totals",
            "process_memory": format_peak_memory(memory),
        },
        {
            "benchmark": "Forward, no session",
            "process_cpu": format_cpu_summary(forward["no_session"]),
            "process_memory": "included in full benchmark process peak RSS",
        },
        {
            "benchmark": "Forward, session cached run",
            "process_cpu": format_nested_cpu_summary(forward["session"], "cached_run_s"),
            "process_memory": "included in full benchmark process peak RSS",
        },
        {
            "benchmark": "Forward, fast mode",
            "process_cpu": format_nested_cpu_summary(
                forward["fast_mode"],
                "four_scene_fast_total_s",
                core_key="four_scene_fast_total",
            ),
            "process_memory": "included in full benchmark process peak RSS",
        },
    ]
    if retrieval["status"] == "skipped":
        rows.append(
            {
                "benchmark": "OE retrieval",
                "process_cpu": f"skipped until {retrieval['owner']}",
                "process_memory": "not measured",
            }
        )
    else:
        rows.extend(
            [
                {
                    "benchmark": "OE, no fast mode sweep",
                    "process_cpu": format_sweep_cpu_summary(retrieval["sweep"]["session"]),
                    "process_memory": "included in full benchmark process peak RSS",
                },
                {
                    "benchmark": "OE, fast mode sweep",
                    "process_cpu": format_sweep_cpu_summary(retrieval["sweep"]["fast_mode"]),
                    "process_memory": "included in full benchmark process peak RSS",
                },
            ]
        )
    return rows


def format_peak_memory(memory: dict[str, Any]) -> str:

    if not memory["peak_rss_supported"]:
        return "peak RSS unavailable"

    return (
        f"peak RSS {memory['peak_rss_mib']:.1f} MiB; "
        f"delta since benchmark start {memory['peak_rss_delta_mib']:.1f} MiB"
    )


def format_cpu_summary(case: dict[str, Any]) -> str:

    cpu = case["process_cpu_s"]
    cores = case["average_active_cores"]

    return f"median CPU {cpu['median']:.3f}s; median active cores {cores['median']:.2f}"


def format_nested_cpu_summary(
    case: dict[str, Any],
    key: str,
    *,
    core_key: str | None = None,
) -> str:

    core_key = key.removesuffix("_s") if core_key is None else core_key
    cpu = case["process_cpu_s"][key]
    cores = case["average_active_cores"][core_key]

    return f"median CPU {cpu['median']:.3f}s; median active cores {cores['median']:.2f}"


def format_sweep_cpu_summary(case: dict[str, Any]) -> str:

    cpu = case["process_cpu_s"]
    cores = case["average_active_cores"]["first_use_total"]

    return f"total CPU {cpu['total_process_cpu_s']:.3f}s; median active cores {cores['median']:.2f}"


def active_cores(process_cpu_s: float, wall_s: float) -> float:

    if wall_s <= 0.0:
        return 0.0

    return process_cpu_s / wall_s


def write_json_atomic(path: Path, payload: dict[str, Any]) -> None:

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(json_ready(payload), indent=2, sort_keys=True) + "\n")
    temporary.replace(path)
