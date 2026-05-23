"""Hardcoded benchmark configuration."""

from pathlib import Path

from validation.optimal_estimation import reference_cases as oe_cases

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
BENCHMARK_ROOT = REPO_ROOT / "benchmark"
RUNS_DIR = BENCHMARK_ROOT / ".runs"
DB_PATH = RUNS_DIR / "benchmark.sqlite"
RESULTS_PATH = BENCHMARK_ROOT / "results.json"
FAST_RESULTS_PATH = BENCHMARK_ROOT / "fast_results.json"
REFERENCE_SPECTRA_DIR = REPO_ROOT / "validation" / "reference_data" / "spectra"
REFERENCE_OE_PATH = (
    REPO_ROOT
    / "validation"
    / "reference_data"
    / "optimal_estimation"
    / "disamar_o2a_two_state_reference.json"
)

SCHEMA_VERSION: int = 4
BENCHMARK_NAME: str = "zdisamar_current"
COMMAND: str = "uv run benchmark/run_benchmark.py"

FORWARD_REPEATS: int = 10
RETRIEVAL_REPEATS: int = 10
SWEEP_COUNT: int = oe_cases.run_count()
FAST_SCENE_LABELS: tuple[str, ...] | None = None
SWEEP_CASE_INDICES: tuple[int, ...] | None = None
WORKER_LIMIT_ENV = "ZDISAMAR_WORKER_LIMIT"
WORKER_LIMIT: int | None = None
HOST_CPU_COUNT: int | None = None
EFFECTIVE_WORKER_CAP: int | None = None
FORWARD_STATE_NAMES = (
    "aerosol_optical_depth",
    "aerosol_layer_mid_pressure_hpa",
)
SPECTRA_EDGE_EXCLUSION_COUNT = 1
RADIANCE_REFERENCE_PATH = REFERENCE_SPECTRA_DIR / "o2a_jacobian_retrieval_instrument_forward.csv"
REFLECTANCE_JACOBIAN_REFERENCE_PATH = (
    REFERENCE_SPECTRA_DIR / "o2a_jacobian_simulation_instrument_reflectance.csv"
)
REFERENCE_COLUMNS = {
    "aerosol_optical_depth": "aerosolTau",
    "aerosol_layer_mid_pressure_hpa": "intervalDP",
}


def run_controls() -> dict[
    str,
    bool | int | str | tuple[str, ...] | tuple[int, ...] | None,
]:

    return {
        "forward_repeats": FORWARD_REPEATS,
        "retrieval_single_case_repeats": RETRIEVAL_REPEATS,
        "retrieval_sweep_session_count": SWEEP_COUNT,
        "retrieval_sweep_fast_mode_count": SWEEP_COUNT,
        "fast_scene_labels": FAST_SCENE_LABELS,
        "retrieval_sweep_case_indices": SWEEP_CASE_INDICES,
        "native_worker_limit_env": WORKER_LIMIT_ENV,
        "native_worker_limit": WORKER_LIMIT,
        "host_cpu_count": HOST_CPU_COUNT,
        "effective_native_worker_cap": EFFECTIVE_WORKER_CAP,
        "fortran_disamar_runs": False,
    }
