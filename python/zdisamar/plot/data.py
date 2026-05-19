"""Data normalization helpers for plotting objects and tables."""

from collections.abc import Iterable, Mapping, Sequence
from typing import Protocol, TypeGuard

from . import fields

PlotRow = dict[str, object]


class RowProvider(Protocol):
    """Native table objects expose rows without requiring pandas."""

    def to_rows(self) -> Sequence[Mapping[str, object]]: ...


def to_records(obj: object) -> list[PlotRow]:
    """Convert supported zdisamar plotting inputs to plain Python rows."""

    if is_row_sequence(obj):
        return [dict(item) for item in obj]

    if looks_like_spectrum(obj):
        return spectrum_records(obj)

    if has_rows(obj):
        rows = obj.to_rows()

        return [dict(row) for row in rows]

    raise TypeError(f"unsupported plotting data input: {type(obj).__name__}")


def require_columns(rows: Sequence[Mapping[str, object]], required: Sequence[str]) -> None:
    """Fail early when a plot is missing its physical quantity columns."""

    present = set[str]()

    for row in rows:
        present.update(row.keys())

    missing = [name for name in required if name not in present]

    if missing:
        raise ValueError(f"missing required plotting columns: {', '.join(missing)}")


def spectrum_frame(spectrum):
    """Put spectrum-like objects into one plotting table shape."""

    frame = to_records(spectrum)
    require_columns(frame, fields.SPECTRUM_FIELDS)

    return frame


def with_channel_labels(obj):
    """Add radiance/irradiance labels to instrument-response rows."""

    result = to_records(obj)

    if not result:
        return result

    if "channel_label" in result[0] or "channel" not in result[0]:
        return result

    labels: dict[object, str] = {0: "radiance", 1: "irradiance", "0": "radiance", "1": "irradiance"}

    return [
        {
            **row,
            "channel_label": labels.get(row.get("channel"), str(row.get("channel"))),
        }
        for row in result
    ]


def column_values(rows: Iterable[Mapping[str, object]], name: str) -> list[float]:
    """Return one numeric column as floats."""

    return [as_float(row[name]) for row in rows]


def as_float(value: object) -> float:
    """Convert a plotting scalar to float and reject non-numeric table values."""

    if isinstance(value, int | float | str):
        return float(value)

    raise TypeError(f"expected numeric plotting value, got {type(value).__name__}")


def spectrum_records(obj: object) -> list[PlotRow]:

    wavelength_nm = list(getattr(obj, fields.WAVELENGTH_NM))
    radiance = list(getattr(obj, fields.RADIANCE))
    irradiance = list(getattr(obj, fields.IRRADIANCE))
    reflectance = list(getattr(obj, fields.REFLECTANCE))
    sun_normalized = list(getattr(obj, fields.SUN_NORMALIZED_RADIANCE))

    zipped = zip(
        wavelength_nm,
        radiance,
        irradiance,
        reflectance,
        sun_normalized,
        strict=True,
    )

    rows: list[PlotRow] = []

    for values in zipped:
        wavelength = values[0]
        radiance_value = values[1]
        irradiance_value = values[2]
        reflectance_value = values[3]
        sun_normalized_value = values[4]
        rows.append(
            {
                fields.WAVELENGTH_NM: float(wavelength),
                fields.RADIANCE: float(radiance_value),
                fields.IRRADIANCE: float(irradiance_value),
                fields.REFLECTANCE: float(reflectance_value),
                fields.SUN_NORMALIZED_RADIANCE: float(sun_normalized_value),
            }
        )

    return rows


def looks_like_spectrum(obj) -> bool:

    return all(hasattr(obj, name) for name in fields.SPECTRUM_FIELDS)


def has_rows(obj: object) -> TypeGuard[RowProvider]:

    return callable(getattr(obj, "to_rows", None))


def is_row_sequence(obj: object) -> TypeGuard[list[Mapping[str, object]]]:

    return isinstance(obj, list) and all(isinstance(item, Mapping) for item in obj)
