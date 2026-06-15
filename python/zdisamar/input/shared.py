"""Shared helpers for typed input objects."""

import math
from collections.abc import Iterable, Mapping


def to_float(value: object) -> float:
    """Accept the validation-file spelling of missing numeric values."""

    if isinstance(value, str) and value.lower() == "nan":
        return math.nan

    if isinstance(value, str | int | float):
        return float(value)

    raise TypeError(f"expected numeric value, got {type(value).__name__}")


def placeholder_float(data: dict[str, object], key: str, default: float) -> float:
    """Convert inert placeholder fields where null means omitted."""

    value = data.get(key, default)

    return default if value is None else to_float(value)


def to_int(value: object) -> int:
    """Convert a JSON scalar to int with a typed failure for bad shapes."""

    if isinstance(value, str | int | float):
        return int(value)

    raise TypeError(f"expected integer value, got {type(value).__name__}")


def to_bool(value: object) -> bool:
    """Convert a JSON scalar to bool."""

    if isinstance(value, bool):
        return value

    if isinstance(value, str):
        normalized = value.lower()

        if normalized in {"true", "1", "yes"}:
            return True

        if normalized in {"false", "0", "no"}:
            return False

    if isinstance(value, int | float):
        return bool(value)

    raise TypeError(f"expected boolean value, got {type(value).__name__}")


def object_dict(value: object) -> dict[str, object]:
    """Return a string-keyed object mapping."""

    if not isinstance(value, Mapping):
        raise TypeError(f"expected object mapping, got {type(value).__name__}")

    return {str(key): item for key, item in value.items()}


def object_dict_list(value: object) -> list[dict[str, object]]:
    """Return a list of string-keyed object mappings."""

    if not isinstance(value, Iterable) or isinstance(value, str | bytes):
        raise TypeError(f"expected object-list value, got {type(value).__name__}")

    return [object_dict(item) for item in value]


def int_dict(value: object) -> dict[str, int]:
    """Return a string-keyed integer mapping."""

    return {key: to_int(item) for key, item in object_dict(value).items()}


def int_list(value: object) -> list[int]:
    """Return a list of integers from a JSON array."""

    if not isinstance(value, Iterable) or isinstance(value, str | bytes):
        raise TypeError(f"expected integer-list value, got {type(value).__name__}")

    return [to_int(item) for item in value]


def optional_float(data: dict[str, object], key: str) -> float | None:
    """Keep omitted optional science settings as None."""

    value = data.get(key)

    return None if value is None else to_float(value)


def json_value(value: object) -> object:
    """Write NaN as text because JSON has no portable NaN number."""

    if isinstance(value, float) and math.isnan(value):
        return "nan"

    if isinstance(value, list):
        return [json_value(item) for item in value]

    if isinstance(value, dict):
        return {key: json_value(item) for key, item in value.items()}

    return value


def native_json_value(value: object) -> object:
    """Write inert NaN placeholders as null for the native Zig JSON boundary."""

    if isinstance(value, float) and math.isnan(value):
        return None

    if isinstance(value, list):
        return [native_json_value(item) for item in value]

    if isinstance(value, dict):
        return {key: native_json_value(item) for key, item in value.items()}

    return value
