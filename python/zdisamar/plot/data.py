"""Data normalization helpers for plotting objects and tables."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from . import fields


def to_dataframe(obj: Any):
    """Convert supported zdisamar plotting inputs to a Pandas data frame."""

    import numpy as np
    import pandas as pd

    if isinstance(obj, pd.DataFrame):
        return obj.copy()
    if isinstance(obj, str | Path):
        return pd.read_csv(obj)
    if _looks_like_spectrum(obj):
        return pd.DataFrame(
            {
                fields.WAVELENGTH_NM: _copy_array(obj.wavelength_nm),
                fields.RADIANCE: _copy_array(obj.radiance),
                fields.IRRADIANCE: _copy_array(obj.irradiance),
                fields.REFLECTANCE: _copy_array(obj.reflectance),
            }
        )
    if hasattr(obj, "table"):
        return to_dataframe(obj.table)
    if isinstance(obj, np.ndarray):
        if obj.dtype.names:
            return pd.DataFrame.from_records(obj)
        return pd.DataFrame(obj)
    if isinstance(obj, Mapping):
        return pd.DataFrame(obj)
    if isinstance(obj, Sequence) and not isinstance(obj, str | bytes | bytearray):
        return pd.DataFrame(obj)
    raise TypeError(f"unsupported plotting data input: {type(obj).__name__}")


def require_columns(frame, required: Sequence[str]) -> None:
    missing = [name for name in required if name not in frame.columns]
    if missing:
        raise ValueError(f"missing required plotting columns: {', '.join(missing)}")


def filter_window(frame, window_nm: tuple[float, float] | None):
    if window_nm is None:
        return frame
    require_columns(frame, [fields.WAVELENGTH_NM])
    start_nm, end_nm = window_nm
    if end_nm < start_nm:
        raise ValueError("window_nm end must be greater than or equal to start")
    return frame[
        (frame[fields.WAVELENGTH_NM] >= start_nm) & (frame[fields.WAVELENGTH_NM] <= end_nm)
    ]


def marker_frame(markers_nm: Sequence[float]):
    import pandas as pd

    return pd.DataFrame({fields.WAVELENGTH_NM: [float(value) for value in markers_nm]})


def spectrum_frame(spectrum: Any, window_nm: tuple[float, float] | None = None):
    frame = to_dataframe(spectrum)
    require_columns(frame, fields.SPECTRUM_FIELDS)
    return filter_window(frame, window_nm)


def comparison_frame(
    current: Any,
    reference: Any,
    quantity: str,
    *,
    relative: bool = False,
    window_nm: tuple[float, float] | None = None,
):
    """Return current/reference/residual rows on the current wavelength grid."""

    import numpy as np
    import pandas as pd

    current_frame = filter_window(to_dataframe(current), window_nm).sort_values(
        fields.WAVELENGTH_NM
    )
    reference_frame = to_dataframe(reference).sort_values(fields.WAVELENGTH_NM)
    require_columns(current_frame, [fields.WAVELENGTH_NM, quantity])
    require_columns(reference_frame, [fields.WAVELENGTH_NM, quantity])

    wavelength_nm = current_frame[fields.WAVELENGTH_NM].to_numpy(dtype=float)
    current_values = current_frame[quantity].to_numpy(dtype=float)
    reference_values = np.interp(
        wavelength_nm,
        reference_frame[fields.WAVELENGTH_NM].to_numpy(dtype=float),
        reference_frame[quantity].to_numpy(dtype=float),
    )
    residual = current_values - reference_values
    relative_residual = np.divide(
        residual,
        reference_values,
        out=np.zeros_like(residual),
        where=reference_values != 0.0,
    )
    value = relative_residual if relative else residual
    return pd.DataFrame(
        {
            fields.WAVELENGTH_NM: wavelength_nm,
            "current": current_values,
            "reference": reference_values,
            fields.RESIDUAL: residual,
            fields.RELATIVE_RESIDUAL: relative_residual,
            "plotted_residual": value,
            fields.QUANTITY: quantity,
        }
    )


def metric_frame(current: Any, reference: Any, quantities: Sequence[str], metrics: Sequence[str]):
    import numpy as np
    import pandas as pd

    rows: list[dict[str, object]] = []
    for quantity in quantities:
        comparison = comparison_frame(current, reference, quantity)
        residual = comparison[fields.RESIDUAL].to_numpy(dtype=float)
        values = {
            "mae": float(np.mean(np.abs(residual))),
            "rmse": float(np.sqrt(np.mean(np.square(residual)))),
            "max_abs": float(np.max(np.abs(residual))),
            "mean_signed": float(np.mean(residual)),
        }
        for metric in metrics:
            if metric not in values:
                raise ValueError(f"unsupported validation metric: {metric}")
            rows.append(
                {
                    fields.QUANTITY: quantity,
                    fields.METRIC: metric,
                    fields.VALUE: values[metric],
                }
            )
    return pd.DataFrame.from_records(rows)


def _looks_like_spectrum(obj: Any) -> bool:
    return all(hasattr(obj, name) for name in fields.SPECTRUM_FIELDS)


def _copy_array(value: Any):
    try:
        return value.copy()
    except AttributeError:
        return value
