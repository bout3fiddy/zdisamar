"""Case-owned optimisation settings for wavelength-band inputs."""

import math
from bisect import bisect_left
from collections.abc import Sequence
from dataclasses import dataclass, field


@dataclass
class FastModeRadiativeTransfer:
    """Radiative-transfer controls changed when O2 A fastmode is enabled."""

    fourier_order_cap: int | None = 5
    aerosol_tangent_order_cap: int | None = 11
    fourier_tail_reflectance_epsilon: float = 1.0e-11
    threshold_doubl: float = 3.0e-5
    qzero_rd_product_suppression: bool = False
    qzero_tu_product_suppression: bool = False
    qzero_td_product_suppression: bool = False

    def apply_to(self, thresholds: object) -> None:
        """Apply the fastmode threshold overrides to a case copy."""

        for key, value in self.to_dict().items():
            if not hasattr(thresholds, key):
                raise ValueError(f"unknown fastmode radiative-transfer knob: {key}")
            setattr(thresholds, key, value)

    def to_dict(self) -> dict[str, float | int | bool | None]:

        return {
            "fourier_order_cap": self.fourier_order_cap,
            "aerosol_tangent_order_cap": self.aerosol_tangent_order_cap,
            "fourier_tail_reflectance_epsilon": self.fourier_tail_reflectance_epsilon,
            "threshold_doubl": self.threshold_doubl,
            "qzero_rd_product_suppression": self.qzero_rd_product_suppression,
            "qzero_tu_product_suppression": self.qzero_tu_product_suppression,
            "qzero_td_product_suppression": self.qzero_td_product_suppression,
        }


@dataclass
class FastModeAdaptiveReferenceGrid:
    """High-resolution line-sampling controls changed by O2 A fastmode."""

    points_per_fwhm: int = 28
    strong_line_min_divisions: int = 6
    strong_line_max_divisions: int = 22

    def apply_to(self, grid: dict[str, int]) -> None:
        """Apply fastmode adaptive-grid overrides to a case copy."""

        for key, value in self.to_dict().items():
            if key not in grid:
                raise ValueError(f"unknown fastmode adaptive-grid knob: {key}")
            grid[key] = int(value)

    def to_dict(self) -> dict[str, int]:

        return {
            "points_per_fwhm": self.points_per_fwhm,
            "strong_line_min_divisions": self.strong_line_min_divisions,
            "strong_line_max_divisions": self.strong_line_max_divisions,
        }


@dataclass
class FastModeOeControls:
    """Optimal-estimation convergence controls used by fastmode by default."""

    max_iterations: int = 10
    state_vector_convergence_threshold: float = 1.0
    max_change_transformed_state: float = 1.0

    def to_dict(self) -> dict[str, float | int]:

        return {
            "max_iterations": self.max_iterations,
            "state_vector_convergence_threshold": self.state_vector_convergence_threshold,
            "max_change_transformed_state": self.max_change_transformed_state,
        }


@dataclass
class FastModeFinalCorrection:
    """One full-physics OE update after fastmode convergence."""

    enabled: bool = True
    wavelength_window_nm: tuple[float, float] = (765.2, 768.0)
    wavelength_count: int | None = 12
    wavelengths_nm: tuple[float, ...] = ()
    variance_scale: float | None = None

    def resolved_wavelengths(
        self,
        measurement_wavelengths_nm: Sequence[float],
    ) -> tuple[float, ...]:
        """Return concrete correction wavelengths on the measurement grid."""

        axis = measured_wavelength_tuple(measurement_wavelengths_nm)

        if self.wavelengths_nm:
            indices = measurement_indices_for_wavelengths(axis, self.wavelengths_nm)
            return tuple(axis[index] for index in indices)

        start_nm, end_nm = self.wavelength_window_nm

        if not math.isfinite(start_nm) or not math.isfinite(end_nm) or end_nm <= start_nm:
            raise ValueError("fastmode final-correction wavelength window is invalid")

        window = tuple(value for value in axis if start_nm <= value <= end_nm)

        if len(window) < 2:
            raise ValueError("fastmode final correction retained fewer than two wavelengths")

        if self.wavelength_count is None:
            return window

        count = int(self.wavelength_count)

        if count < 2:
            raise ValueError("fastmode final-correction wavelength count must be at least two")

        if len(window) <= count:
            return window

        step = (len(window) - 1) / float(count - 1)
        indices = sorted({round(index * step) for index in range(count)})

        return tuple(window[index] for index in indices)

    def resolved_dict(self, measurement_wavelengths_nm: Sequence[float]) -> dict[str, object]:
        """Return the executed correction settings with explicit wavelengths."""

        return {
            "enabled": self.enabled,
            "wavelength_window_nm": list(self.wavelength_window_nm),
            "wavelength_count": self.wavelength_count,
            "wavelengths_nm": list(self.resolved_wavelengths(measurement_wavelengths_nm))
            if self.enabled
            else [],
            "variance_scale": self.variance_scale,
        }

    def to_dict(self) -> dict[str, object]:

        return {
            "enabled": self.enabled,
            "wavelength_window_nm": list(self.wavelength_window_nm),
            "wavelength_count": self.wavelength_count,
            "wavelengths_nm": list(self.wavelengths_nm),
            "variance_scale": self.variance_scale,
        }


@dataclass
class FastModeOe:
    """OE-specific fastmode settings."""

    controls: FastModeOeControls
    final_correction: FastModeFinalCorrection

    @classmethod
    def defaults(cls) -> FastModeOe:

        return cls(
            controls=FastModeOeControls(),
            final_correction=FastModeFinalCorrection(),
        )

    def resolved_dict(self, measurement_wavelengths_nm: Sequence[float]) -> dict[str, object]:

        return {
            "controls": self.controls.to_dict(),
            "final_correction": self.final_correction.resolved_dict(measurement_wavelengths_nm),
        }

    def to_dict(self) -> dict[str, object]:

        return {
            "controls": self.controls.to_dict(),
            "final_correction": self.final_correction.to_dict(),
        }


@dataclass
class FastModeOptimisation:
    """Inspectable O2 A fastmode settings owned by the case."""

    enabled: bool = False
    radiative_transfer: FastModeRadiativeTransfer = field(
        default_factory=FastModeRadiativeTransfer
    )
    adaptive_reference_grid: FastModeAdaptiveReferenceGrid = field(
        default_factory=FastModeAdaptiveReferenceGrid
    )
    oe: FastModeOe = field(default_factory=FastModeOe.defaults)

    def apply_to_case(self, case: object) -> None:
        """Apply fastmode RTM controls to a copied wavelength-band case."""

        self.radiative_transfer.apply_to(case.radiative_transfer.performance_thresholds)
        self.adaptive_reference_grid.apply_to(case.instrument_response.adaptive_reference_grid)

    def resolved_dict(self, measurement_wavelengths_nm: Sequence[float]) -> dict[str, object]:
        """Return the executed fastmode settings with explicit correction wavelengths."""

        return {
            "enabled": self.enabled,
            "radiative_transfer": self.radiative_transfer.to_dict(),
            "adaptive_reference_grid": self.adaptive_reference_grid.to_dict(),
            "oe": self.oe.resolved_dict(measurement_wavelengths_nm),
        }

    def to_dict(self) -> dict[str, object]:

        return {
            "enabled": self.enabled,
            "radiative_transfer": self.radiative_transfer.to_dict(),
            "adaptive_reference_grid": self.adaptive_reference_grid.to_dict(),
            "oe": self.oe.to_dict(),
        }


@dataclass
class O2AOptimisation:
    """Case-owned optimisation modes for O2 A workflows."""

    fastmode: FastModeOptimisation

    @classmethod
    def defaults(cls) -> O2AOptimisation:

        return cls(fastmode=FastModeOptimisation())

    def to_dict(self) -> dict[str, object]:

        return {"fastmode": self.fastmode.to_dict()}


def measured_wavelength_tuple(values: Sequence[float]) -> tuple[float, ...]:
    """Return a finite, strictly increasing wavelength axis."""

    wavelengths = tuple(float(value) for value in values)

    for index, wavelength_nm in enumerate(wavelengths):
        if not math.isfinite(wavelength_nm):
            raise ValueError("wavelengths must be finite")
        if index != 0 and wavelength_nm <= wavelengths[index - 1]:
            raise ValueError("wavelengths must be strictly increasing")

    return wavelengths


def measurement_indices_for_wavelengths(
    measurement_wavelengths_nm: Sequence[float],
    requested_wavelengths_nm: Sequence[float],
) -> list[int]:
    """Map requested correction wavelengths onto the measured retrieval grid."""

    measurement_axis = measured_wavelength_tuple(measurement_wavelengths_nm)
    requested_axis = measured_wavelength_tuple(requested_wavelengths_nm)

    if len(requested_axis) < 2:
        raise ValueError("correction wavelengths must contain at least two samples")

    tolerance = wavelength_match_tolerance(measurement_axis)
    retained_indices: list[int] = []
    previous_index = -1

    for requested in requested_axis:
        insertion = bisect_left(measurement_axis, requested)
        candidates = []

        if insertion < len(measurement_axis):
            candidates.append(insertion)
        if insertion != 0:
            candidates.append(insertion - 1)
        if not candidates:
            raise ValueError("correction wavelengths must overlap the measurement grid")

        index = min(candidates, key=lambda candidate: abs(measurement_axis[candidate] - requested))

        if abs(measurement_axis[index] - requested) > tolerance:
            raise ValueError("correction wavelengths must lie on the measurement grid")
        if index <= previous_index:
            raise ValueError("correction wavelengths must map to unique increasing samples")

        previous_index = index
        retained_indices.append(index)

    return retained_indices


def wavelength_match_tolerance(wavelengths_nm: Sequence[float]) -> float:
    """Return a small absolute tolerance for matching generated wavelength grids."""

    if len(wavelengths_nm) < 2:
        return 1.0e-9

    span = abs(float(wavelengths_nm[-1]) - float(wavelengths_nm[0]))
    step = span / max(1, len(wavelengths_nm) - 1)

    return max(1.0e-9, step * 1.0e-6)
