"""Data normalization helpers for plotting objects and tables."""

from collections.abc import Sequence
from typing import Any

from . import fields


def to_dataframe(obj: Any):
    """Convert supported zdisamar plotting inputs to a Pandas data frame."""

    import pandas as pd

    if isinstance(obj, pd.DataFrame):
        return obj.copy()
    if _looks_like_spectrum(obj):
        return pd.DataFrame(
            {
                fields.WAVELENGTH_NM: _copy_array(obj.wavelength_nm),
                fields.RADIANCE: _copy_array(obj.radiance),
                fields.IRRADIANCE: _copy_array(obj.irradiance),
                fields.REFLECTANCE: _copy_array(obj.reflectance),
                fields.SUN_NORMALIZED_RADIANCE: _copy_array(obj.sun_normalized_radiance),
            }
        )
    if hasattr(obj, "table"):
        return pd.DataFrame.from_records(obj.table)
    raise TypeError(f"unsupported plotting data input: {type(obj).__name__}")


def require_columns(frame, required: Sequence[str]) -> None:
    missing = [name for name in required if name not in frame.columns]
    if missing:
        raise ValueError(f"missing required plotting columns: {', '.join(missing)}")


def spectrum_frame(spectrum: Any):
    frame = to_dataframe(spectrum)
    require_columns(frame, fields.SPECTRUM_FIELDS)
    return frame


def with_channel_labels(obj: Any):
    result = to_dataframe(obj)
    if "channel_label" in result.columns or "channel" not in result.columns:
        return result
    labels = {0: "radiance", 1: "irradiance", "0": "radiance", "1": "irradiance"}
    result = result.copy()
    result["channel_label"] = result["channel"].map(labels).fillna(result["channel"].astype(str))
    return result


def _looks_like_spectrum(obj: Any) -> bool:
    return all(hasattr(obj, name) for name in fields.SPECTRUM_FIELDS)


def _copy_array(value: Any):
    try:
        return value.copy()
    except AttributeError:
        return value
