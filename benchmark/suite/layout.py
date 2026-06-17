"""Memory-layout diagnostics derived from benchmark scenes."""

from typing import Any

import numpy as np
from zdisamar import rtm

from . import cases, config

INLINE_INTEGRATION_SAMPLE_COUNT = 5
WAVELENGTH_SAMPLING_ROW_BYTES = 200
OLD_WAVELENGTH_SAMPLING_ROW_BYTES = 65_592
OWNED_WAVELENGTH_SAMPLING_HEADER_BYTES = 48
INTEGRATION_KERNEL_BYTES = 32_784
SIDE_SAMPLE_BYTES = 16
MIN_PARALLEL_WAVELENGTH_SAMPLE_COUNT = 64
MAX_WORKERS = 64
COLLISION_COMPLEX_PROFILE_CACHE_OLD_BYTES = 2_072
COLLISION_COMPLEX_PROFILE_CACHE_BYTES = 1_048
COLLISION_COMPLEX_PROFILE_CACHE_CAPACITY = 64
COLLISION_COMPLEX_PROFILE_NODE_COUNT = 47
SPLINE_ENDPOINT_SECANT_SAMPLE_SCRATCH_BYTES = 10_240

INTEGRATION_MODE_LABELS = {
    0: "auto",
    1: "explicit_hr_grid",
    2: "disamar_hr_grid",
    3: "adaptive",
}
CHANNEL_LABELS = {
    0: "radiance",
    1: "irradiance",
}


def memory_layout_diagnostics() -> dict[str, Any]:

    return {
        "instrument_sampling": instrument_sampling_layout(),
        "optical_accumulation": optical_accumulation_layout(),
    }


def instrument_sampling_layout() -> dict[str, Any]:

    case = cases.forward_case()
    nominal_wavelengths_nm = rtm.nominal_wavelengths(case)
    response = rtm.instrument_response(case, nominal_wavelengths_nm)
    rows = response.to_rows()
    kernel_rows = [row for row in rows if int(row["sample_index"]) == 0]
    support_counts = np.asarray([row["support_count"] for row in kernel_rows], dtype=np.int64)
    nominal_sample_count = len(nominal_wavelengths_nm)
    kernel_count = int(support_counts.size)
    side_sample_count = int(support_counts[support_counts > INLINE_INTEGRATION_SAMPLE_COUNT].sum())
    side_kernel_count = int(np.count_nonzero(support_counts > INLINE_INTEGRATION_SAMPLE_COUNT))
    current_row_payload_bytes = nominal_sample_count * WAVELENGTH_SAMPLING_ROW_BYTES
    current_side_storage_bytes = side_sample_count * SIDE_SAMPLE_BYTES
    current_owned_plan_bytes = (
        OWNED_WAVELENGTH_SAMPLING_HEADER_BYTES
        + current_row_payload_bytes
        + current_side_storage_bytes
    )
    previous_row_payload_bytes = nominal_sample_count * OLD_WAVELENGTH_SAMPLING_ROW_BYTES
    saved_row_payload_bytes = previous_row_payload_bytes - (
        current_row_payload_bytes + current_side_storage_bytes
    )
    sampling_worker_count = preferred_sampling_worker_count(nominal_sample_count)

    return {
        "boundary": "post-timing diagnostic; excluded from benchmark wall time and peak RSS",
        "source": "instrument_response_sampling over benchmark forward_case nominal grid",
        "nominal_sample_count": nominal_sample_count,
        "kernel_count": kernel_count,
        "support_sample_count": len(rows),
        "support_count_stats": int_stats(support_counts),
        "support_count_histogram": int_histogram(support_counts),
        "integration_mode_histogram": labeled_histogram(
            np.asarray([row["integration_mode"] for row in kernel_rows], dtype=np.int64),
            INTEGRATION_MODE_LABELS,
        ),
        "channel_stats": channel_stats(kernel_rows),
        "inline_threshold_samples": INLINE_INTEGRATION_SAMPLE_COUNT,
        "inline_kernel_count": int(kernel_count - side_kernel_count),
        "side_kernel_count": side_kernel_count,
        "side_sample_count": side_sample_count,
        "estimated_sampling_worker_count": sampling_worker_count,
        "integration_kernel_scratch_bytes_per_worker": INTEGRATION_KERNEL_BYTES,
        "integration_kernel_scratch_bytes_at_worker_count": (
            sampling_worker_count * INTEGRATION_KERNEL_BYTES
        ),
        "current_owned_wavelength_sampling_bytes": current_owned_plan_bytes,
        "current_row_payload_bytes": current_row_payload_bytes,
        "current_side_storage_bytes": current_side_storage_bytes,
        "previous_full_kernel_row_payload_bytes": previous_row_payload_bytes,
        "estimated_row_payload_saved_bytes": saved_row_payload_bytes,
        "estimated_row_payload_saved_mib": mib(saved_row_payload_bytes),
        "estimated_row_payload_reduction_ratio": ratio(
            saved_row_payload_bytes,
            previous_row_payload_bytes,
        ),
    }


def optical_accumulation_layout() -> dict[str, Any]:

    cache_saved_bytes = (
        COLLISION_COMPLEX_PROFILE_CACHE_OLD_BYTES - COLLISION_COMPLEX_PROFILE_CACHE_BYTES
    )

    return {
        "boundary": "post-timing diagnostic; excluded from benchmark wall time and peak RSS",
        "source": "collision-complex profile cache used by benchmark optical accumulation",
        "benchmark_profile_node_count": COLLISION_COMPLEX_PROFILE_NODE_COUNT,
        "collision_complex_profile_cache_capacity": (COLLISION_COMPLEX_PROFILE_CACHE_CAPACITY),
        "previous_collision_complex_profile_cache_bytes": (
            COLLISION_COMPLEX_PROFILE_CACHE_OLD_BYTES
        ),
        "current_collision_complex_profile_cache_bytes": (COLLISION_COMPLEX_PROFILE_CACHE_BYTES),
        "collision_complex_profile_cache_saved_bytes_per_request": (cache_saved_bytes),
        "collision_complex_profile_cache_saved_kib_per_request": (kib(cache_saved_bytes)),
        "previous_collision_complex_sample_spline_scratch_bytes": (
            SPLINE_ENDPOINT_SECANT_SAMPLE_SCRATCH_BYTES
        ),
        "current_collision_complex_sample_spline_scratch_bytes": 0,
        "collision_complex_sample_spline_scratch_saved_bytes_per_sample": (
            SPLINE_ENDPOINT_SECANT_SAMPLE_SCRATCH_BYTES
        ),
        "collision_complex_sample_spline_scratch_saved_kib_per_sample": (
            kib(SPLINE_ENDPOINT_SECANT_SAMPLE_SCRATCH_BYTES)
        ),
    }


def channel_stats(kernel_rows: list[dict[str, Any]]) -> dict[str, Any]:

    result = {}

    for channel_code, label in CHANNEL_LABELS.items():
        rows = [row for row in kernel_rows if int(row["channel"]) == channel_code]
        counts = np.asarray([row["support_count"] for row in rows], dtype=np.int64)
        side_counts = counts[counts > INLINE_INTEGRATION_SAMPLE_COUNT]
        result[label] = {
            "kernel_count": int(counts.size),
            "support_count_stats": int_stats(counts),
            "support_count_histogram": int_histogram(counts),
            "side_kernel_count": int(side_counts.size),
            "side_sample_count": int(side_counts.sum()),
        }

    return result


def preferred_sampling_worker_count(sample_count: int) -> int:

    if sample_count < MIN_PARALLEL_WAVELENGTH_SAMPLE_COUNT:
        return 1

    count_from_work = max(1, sample_count // MIN_PARALLEL_WAVELENGTH_SAMPLE_COUNT)
    worker_cap = config.EFFECTIVE_WORKER_CAP or 1

    return min(MAX_WORKERS, worker_cap, count_from_work)


def int_stats(values: np.ndarray) -> dict[str, float | int]:

    if values.size == 0:
        return {
            "count": 0,
            "min": 0,
            "median": 0.0,
            "mean": 0.0,
            "p90": 0.0,
            "max": 0,
        }

    return {
        "count": int(values.size),
        "min": int(np.min(values)),
        "median": float(np.median(values)),
        "mean": float(np.mean(values)),
        "p90": float(np.percentile(values, 90.0)),
        "max": int(np.max(values)),
    }


def int_histogram(values: np.ndarray) -> dict[str, int]:

    if values.size == 0:
        return {}

    unique, counts = np.unique(values.astype(np.int64), return_counts=True)

    return {str(int(value)): int(count) for value, count in zip(unique, counts, strict=True)}


def labeled_histogram(values: np.ndarray, labels: dict[int, str]) -> dict[str, int]:

    histogram = int_histogram(values)

    return {labels.get(int(key), str(key)): count for key, count in histogram.items()}


def ratio(numerator: int, denominator: int) -> float:

    if denominator == 0:
        return 0.0

    return numerator / denominator


def mib(byte_count: int) -> float:

    return byte_count / (1024 * 1024)


def kib(byte_count: int) -> float:

    return byte_count / 1024
