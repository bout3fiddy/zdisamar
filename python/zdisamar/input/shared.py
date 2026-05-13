"""Shared helpers for typed input objects."""

import math
from typing import Any


def to_float(value: Any) -> float:
    """Accept the validation-file spelling of missing numeric values."""

    if isinstance(value, str) and value.lower() == "nan":
        return math.nan

    return float(value)


def optional_float(data: dict[str, Any], key: str) -> float | None:
    """Keep omitted optional science settings as None."""

    value = data.get(key)

    return None if value is None else to_float(value)


def json_value(value: Any) -> Any:
    """Write NaN as text because JSON has no portable NaN number."""

    if isinstance(value, float) and math.isnan(value):
        return "nan"

    if isinstance(value, list):
        return [json_value(item) for item in value]

    if isinstance(value, dict):
        return {key: json_value(item) for key, item in value.items()}

    return value
