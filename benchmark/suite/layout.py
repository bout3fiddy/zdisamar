"""Memory-layout diagnostics derived from benchmark scenes."""

from typing import Any

COLLISION_COMPLEX_PROFILE_CACHE_OLD_BYTES = 2_072
COLLISION_COMPLEX_PROFILE_CACHE_BYTES = 1_048
COLLISION_COMPLEX_PROFILE_CACHE_CAPACITY = 64
COLLISION_COMPLEX_PROFILE_NODE_COUNT = 47
SPLINE_ENDPOINT_SECANT_SAMPLE_SCRATCH_BYTES = 10_240


def memory_layout_diagnostics() -> dict[str, Any]:

    return {
        "optical_accumulation": optical_accumulation_layout(),
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


def kib(byte_count: int) -> float:

    return byte_count / 1024
