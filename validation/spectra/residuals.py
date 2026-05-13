"""Residual metrics shared by validation reports."""

import numpy as np


def residual_metrics(
    wavelength_nm: np.ndarray,
    residual: np.ndarray,
) -> dict[str, float]:

    magnitude = np.abs(residual)
    max_abs_index = int(np.argmax(magnitude))

    return {
        "max_abs_residual": float(np.max(magnitude)),
        "max_abs_wavelength_nm": float(wavelength_nm[max_abs_index]),
        "rmse": float(np.sqrt(np.mean(residual * residual))),
        "mean_signed": float(np.mean(residual)),
    }


def residual_blowup_regions(
    wavelength_nm: np.ndarray,
    residual: np.ndarray,
    *,
    fraction: float,
    padding_nm: float,
    limit: int,
    min_wavelength_nm: float,
    max_wavelength_nm: float,
) -> list[dict[str, float]]:

    magnitude = np.abs(residual)

    if magnitude.size == 0:
        return []

    threshold = fraction * float(np.max(magnitude))
    mask = magnitude >= threshold
    regions: list[dict[str, float]] = []
    start_index: int | None = None

    for index, selected in enumerate(mask):
        if selected and start_index is None:
            start_index = index

        is_last = index == mask.size - 1

        if start_index is not None and (not selected or is_last):
            end_index = index if selected and is_last else index - 1
            region_magnitude = magnitude[start_index : end_index + 1]
            peak_index = start_index + int(np.argmax(region_magnitude))
            regions.append(
                {
                    "start_nm": max(
                        min_wavelength_nm,
                        float(wavelength_nm[start_index]) - padding_nm,
                    ),
                    "end_nm": min(
                        max_wavelength_nm,
                        float(wavelength_nm[end_index]) + padding_nm,
                    ),
                    "peak_nm": float(wavelength_nm[peak_index]),
                    "peak_abs_residual": float(magnitude[peak_index]),
                }
            )
            start_index = None

    strongest = sorted(
        regions,
        key=lambda region: region["peak_abs_residual"],
        reverse=True,
    )[:limit]

    return sorted(strongest, key=lambda region: region["start_nm"])
