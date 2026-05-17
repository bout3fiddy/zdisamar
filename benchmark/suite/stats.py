"""Small numerical summaries for benchmark output."""

from collections.abc import Iterable
from typing import Any

import numpy as np


def timing_stats(values: Iterable[float]) -> dict[str, float | int]:
    data = np.asarray(list(values), dtype=np.float64)

    if data.size == 0:
        raise ValueError("cannot summarize an empty sample")

    return {
        "runs": int(data.size),
        "total": float(np.sum(data)),
        "min": float(np.min(data)),
        "median": float(np.median(data)),
        "mean": float(np.mean(data)),
        "p90": float(np.percentile(data, 90.0)),
        "max": float(np.max(data)),
    }


def abs_stats(values: Iterable[float]) -> dict[str, float | int]:
    data = np.abs(np.asarray(list(values), dtype=np.float64))

    if data.size == 0:
        raise ValueError("cannot summarize an empty sample")

    return {
        "runs": int(data.size),
        "max_abs": float(np.max(data)),
        "mean_abs": float(np.mean(data)),
        "median_abs": float(np.median(data)),
    }


def signed_stats(values: Iterable[float]) -> dict[str, float | int]:
    data = np.asarray(list(values), dtype=np.float64)

    if data.size == 0:
        raise ValueError("cannot summarize an empty sample")

    return {
        "runs": int(data.size),
        "min": float(np.min(data)),
        "median": float(np.median(data)),
        "mean": float(np.mean(data)),
        "max": float(np.max(data)),
        "max_abs": float(np.max(np.abs(data))),
    }


def json_ready(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): json_ready(item) for key, item in value.items()}

    if isinstance(value, (list, tuple)):
        return [json_ready(item) for item in value]

    if isinstance(value, np.ndarray):
        return value.tolist()

    if isinstance(value, np.generic):
        return value.item()

    return value
