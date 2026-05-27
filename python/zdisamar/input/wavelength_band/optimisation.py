"""Case-owned optimisation settings for wavelength-band inputs."""

import math
from bisect import bisect_left
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Protocol, Self

from ..shared import object_dict, object_dict_list, to_bool, to_float, to_int


class RadiativeTransferCaseSection(Protocol):
    @property
    def performance_thresholds(self) -> object: ...


class InstrumentResponseCaseSection(Protocol):
    @property
    def adaptive_reference_grid(self) -> dict[str, int]: ...


class FastModeApplicationCase(Protocol):
    @property
    def radiative_transfer(self) -> RadiativeTransferCaseSection: ...

    @property
    def instrument_response(self) -> InstrumentResponseCaseSection: ...


def reject_unknown_fields(data: dict[str, object], allowed: set[str], label: str) -> None:
    """Reject parsed optimisation controls that have no implementation."""

    unknown = set(data) - allowed

    if unknown:
        joined = ", ".join(sorted(unknown))
        raise ValueError(f"unsupported {label} fields: {joined}")


def optional_int(value: object) -> int | None:

    return None if value is None else to_int(value)


def optional_float(value: object) -> float | None:

    return None if value is None else to_float(value)


def finite_positive_optional_float(value: object, *, label: str) -> float | None:

    parsed = optional_float(value)

    if parsed is not None and (not math.isfinite(parsed) or parsed <= 0.0):
        raise ValueError(f"{label} uncertainty scale must be finite and positive")

    return parsed


def float_sequence(value: object, *, label: str) -> tuple[float, ...]:

    if not isinstance(value, Sequence) or isinstance(value, str | bytes):
        raise TypeError(f"{label} must be a numeric sequence")

    return tuple(to_float(item) for item in value)


def wavelength_window(value: object, *, label: str) -> tuple[float, float]:

    values = float_sequence(value, label=f"{label} wavelength window")

    if len(values) != 2:
        raise ValueError(f"{label} wavelength window must contain two values")

    start_nm, end_nm = values

    if not math.isfinite(start_nm) or not math.isfinite(end_nm) or end_nm <= start_nm:
        raise ValueError(f"{label} wavelength window is invalid")

    return start_nm, end_nm


def selected_window_wavelengths(
    measurement_wavelengths_nm: Sequence[float],
    *,
    wavelength_window_nm: tuple[float, float],
    wavelength_count: int | None,
    label: str,
    minimum_samples: int = 2,
) -> tuple[float, ...]:
    """Select measured wavelengths from one configured wavelength window."""

    if minimum_samples < 1:
        raise ValueError(f"{label} minimum sample count must be at least one")

    axis = measured_wavelength_tuple(measurement_wavelengths_nm)
    start_nm, end_nm = wavelength_window_nm
    window = tuple(value for value in axis if start_nm <= value <= end_nm)

    if len(window) < minimum_samples:
        raise ValueError(f"{label} wavelength window retained fewer than {minimum_samples} samples")

    if wavelength_count is None:
        return window

    count = int(wavelength_count)

    if count < minimum_samples:
        raise ValueError(f"{label} wavelength count must be at least {minimum_samples}")

    if len(window) <= count:
        return window

    step = (len(window) - 1) / float(count - 1)
    indices = sorted({round(index * step) for index in range(count)})

    return tuple(window[index] for index in indices)


@dataclass(frozen=True)
class FastModeWavelengthWindow:
    """Evenly sampled measured wavelengths from one physical wavelength interval."""

    wavelength_window_nm: tuple[float, float]
    wavelength_count: int | None

    @classmethod
    def from_dict(cls, data: dict[str, object], *, label: str) -> Self:

        allowed = {"wavelength_window_nm", "wavelength_count"}
        reject_unknown_fields(data, allowed, label)

        return cls(
            wavelength_window_nm=wavelength_window(
                data.get("wavelength_window_nm"),
                label=label,
            ),
            wavelength_count=optional_int(data.get("wavelength_count")),
        )

    def resolved_wavelengths(
        self,
        measurement_wavelengths_nm: Sequence[float],
        *,
        label: str,
        minimum_samples: int = 2,
    ) -> tuple[float, ...]:

        return selected_window_wavelengths(
            measurement_wavelengths_nm,
            wavelength_window_nm=self.wavelength_window_nm,
            wavelength_count=self.wavelength_count,
            label=label,
            minimum_samples=minimum_samples,
        )

    def to_dict(self) -> dict[str, object]:

        return {
            "wavelength_window_nm": list(self.wavelength_window_nm),
            "wavelength_count": self.wavelength_count,
        }


def default_fast_stage_wavelength_windows() -> tuple[FastModeWavelengthWindow, ...]:
    """Return the tuned sparse fast-stage O2 A row selectors used by fastmode."""

    return (
        FastModeWavelengthWindow((758.0, 758.08), 2),
        FastModeWavelengthWindow((758.2, 758.28), 2),
        FastModeWavelengthWindow((758.36, 758.48), 2),
        FastModeWavelengthWindow((765.2, 765.32), 2),
        FastModeWavelengthWindow((765.44, 765.68), 2),
        FastModeWavelengthWindow((766.24, 766.84), 2),
    )


@dataclass
class FastModeRadiativeTransfer:
    """RTM work-reduction controls applied when O2 A fastmode is enabled.

    These fields are a case-owned view onto the LABOS performance thresholds.
    They do not change the physical scene, measurement grid, aerosol state, or
    instrument model.  They change how much radiative-transfer work is done
    before a term is treated as small enough to skip.

    `fourier_order_cap` skips whole azimuthal Fourier orders above the cap.
    `aerosol_tangent_order_cap` does the same for AOD/pressure tangent
    weighting functions when the general Fourier cap is relaxed.
    `fourier_tail_reflectance_epsilon` lets the solver stop the Fourier series
    after the retained floor order once the reflectance tail is small.
    `threshold_doubl` relaxes the layer-doubling start threshold, reducing
    doubling work at the cost of a stronger transport approximation.
    The `qzero_*_product_suppression` flags are experimental downstream matrix
    product skips; retained fastmode defaults keep them disabled.
    """

    fourier_order_cap: int | None = 5
    aerosol_tangent_order_cap: int | None = 11
    fourier_tail_reflectance_epsilon: float = 1.0e-11
    threshold_doubl: float = 3.0e-5
    qzero_rd_product_suppression: bool = False
    qzero_tu_product_suppression: bool = False
    qzero_td_product_suppression: bool = False

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        allowed = {
            "fourier_order_cap",
            "aerosol_tangent_order_cap",
            "fourier_tail_reflectance_epsilon",
            "threshold_doubl",
            "qzero_rd_product_suppression",
            "qzero_tu_product_suppression",
            "qzero_td_product_suppression",
        }
        reject_unknown_fields(data, allowed, "fastmode radiative-transfer")
        defaults = cls()

        return cls(
            fourier_order_cap=optional_int(
                data.get("fourier_order_cap", defaults.fourier_order_cap)
            ),
            aerosol_tangent_order_cap=optional_int(
                data.get("aerosol_tangent_order_cap", defaults.aerosol_tangent_order_cap)
            ),
            fourier_tail_reflectance_epsilon=to_float(
                data.get(
                    "fourier_tail_reflectance_epsilon",
                    defaults.fourier_tail_reflectance_epsilon,
                )
            ),
            threshold_doubl=to_float(data.get("threshold_doubl", defaults.threshold_doubl)),
            qzero_rd_product_suppression=to_bool(
                data.get(
                    "qzero_rd_product_suppression",
                    defaults.qzero_rd_product_suppression,
                )
            ),
            qzero_tu_product_suppression=to_bool(
                data.get(
                    "qzero_tu_product_suppression",
                    defaults.qzero_tu_product_suppression,
                )
            ),
            qzero_td_product_suppression=to_bool(
                data.get(
                    "qzero_td_product_suppression",
                    defaults.qzero_td_product_suppression,
                )
            ),
        )

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
    """High-resolution O2 line-grid controls changed by fastmode.

    These knobs reduce work before convolution to the instrument grid.  Lower
    values produce fewer high-resolution samples around O2 A lines, so they can
    speed up the forward model but may under-resolve narrow line structure.

    `points_per_fwhm` controls the nominal high-resolution sampling density per
    instrument-line FWHM.  `strong_line_min_divisions` and
    `strong_line_max_divisions` bound the extra subdivisions around strong line
    cores, where most of the O2 A information lives.
    """

    points_per_fwhm: int = 28
    strong_line_min_divisions: int = 6
    strong_line_max_divisions: int = 22

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        allowed = {
            "points_per_fwhm",
            "strong_line_min_divisions",
            "strong_line_max_divisions",
        }
        reject_unknown_fields(data, allowed, "fastmode adaptive-reference-grid")
        defaults = cls()

        return cls(
            points_per_fwhm=to_int(data.get("points_per_fwhm", defaults.points_per_fwhm)),
            strong_line_min_divisions=to_int(
                data.get("strong_line_min_divisions", defaults.strong_line_min_divisions)
            ),
            strong_line_max_divisions=to_int(
                data.get("strong_line_max_divisions", defaults.strong_line_max_divisions)
            ),
        )

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
    """Fast-stage optimal-estimation iteration controls.

    `max_iterations` is the hard stop for the fastmode solve before any final
    correction.  `state_vector_convergence_threshold` is compared with the
    posterior-weighted state update metric; lower values require a smaller
    state step before convergence is accepted.  `max_change_transformed_state`
    limits each update in the transformed OE state basis and activates the
    signal-to-noise safeguard when the proposed step is too large.
    """

    max_iterations: int = 10
    state_vector_convergence_threshold: float = 1.0
    max_change_transformed_state: float = 1.0

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        allowed = {
            "max_iterations",
            "state_vector_convergence_threshold",
            "max_change_transformed_state",
        }
        reject_unknown_fields(data, allowed, "fastmode OE controls")
        defaults = cls()

        return cls(
            max_iterations=to_int(data.get("max_iterations", defaults.max_iterations)),
            state_vector_convergence_threshold=to_float(
                data.get(
                    "state_vector_convergence_threshold",
                    defaults.state_vector_convergence_threshold,
                )
            ),
            max_change_transformed_state=to_float(
                data.get("max_change_transformed_state", defaults.max_change_transformed_state)
            ),
        )

    def to_dict(self) -> dict[str, float | int]:

        return {
            "max_iterations": self.max_iterations,
            "state_vector_convergence_threshold": self.state_vector_convergence_threshold,
            "max_change_transformed_state": self.max_change_transformed_state,
        }


@dataclass
class FastModeFinalCorrection:
    """One sparse full-physics OE update after fastmode convergence.

    When enabled, fastmode first solves the full measurement vector with the
    fast RTM settings, then computes one full-physics forward model and
    Jacobian on a smaller correction wavelength set.  The correction reuses the
    same retrieval session and updates only the retrieved state vector.

    `wavelength_window_nm` plus `wavelength_count` is the convenient selector:
    it picks evenly spaced measured wavelengths inside the window.  Set
    `wavelength_count=None` to retain every measured wavelength in the window.
    `wavelengths_nm` overrides the window selector with explicit wavelengths;
    each value must map to a unique measurement-grid sample.  `uncertainty_scale`
    overrides the default retained-fraction uncertainty scaling for experiments
    with sparse or weighted correction grids.
    """

    enabled: bool = True
    wavelength_window_nm: tuple[float, float] = (765.2, 768.0)
    wavelength_count: int | None = 4
    wavelengths_nm: tuple[float, ...] = ()
    uncertainty_scale: float | None = None

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        allowed = {
            "enabled",
            "wavelength_window_nm",
            "wavelength_count",
            "wavelengths_nm",
            "uncertainty_scale",
        }
        reject_unknown_fields(data, allowed, "fastmode final-correction")
        defaults = cls()
        wavelengths_value = data.get("wavelengths_nm", defaults.wavelengths_nm)
        wavelengths = (
            measured_wavelength_tuple(float_sequence(wavelengths_value, label="wavelengths_nm"))
            if wavelengths_value
            else ()
        )

        return cls(
            enabled=to_bool(data.get("enabled", defaults.enabled)),
            wavelength_window_nm=wavelength_window(
                data.get("wavelength_window_nm", defaults.wavelength_window_nm),
                label="fastmode final-correction",
            ),
            wavelength_count=optional_int(data.get("wavelength_count", defaults.wavelength_count)),
            wavelengths_nm=wavelengths,
            uncertainty_scale=finite_positive_optional_float(
                data.get("uncertainty_scale", defaults.uncertainty_scale),
                label="fastmode final-correction",
            ),
        )

    def resolved_wavelengths(
        self,
        measurement_wavelengths_nm: Sequence[float],
    ) -> tuple[float, ...]:
        """Return concrete correction wavelengths on the measurement grid."""

        axis = measured_wavelength_tuple(measurement_wavelengths_nm)

        if self.wavelengths_nm:
            indices = measurement_indices_for_wavelengths(axis, self.wavelengths_nm)

            return tuple(axis[index] for index in indices)

        return selected_window_wavelengths(
            axis,
            wavelength_window_nm=self.wavelength_window_nm,
            wavelength_count=self.wavelength_count,
            label="fastmode final-correction",
        )

    def resolved_dict(self, measurement_wavelengths_nm: Sequence[float]) -> dict[str, object]:
        """Return the executed correction settings with explicit wavelengths."""

        return {
            "enabled": self.enabled,
            "wavelength_window_nm": list(self.wavelength_window_nm),
            "wavelength_count": self.wavelength_count,
            "wavelengths_nm": list(self.resolved_wavelengths(measurement_wavelengths_nm))
            if self.enabled
            else [],
            "uncertainty_scale": self.uncertainty_scale,
        }

    def to_dict(self) -> dict[str, object]:

        return {
            "enabled": self.enabled,
            "wavelength_window_nm": list(self.wavelength_window_nm),
            "wavelength_count": self.wavelength_count,
            "wavelengths_nm": list(self.wavelengths_nm),
            "uncertainty_scale": self.uncertainty_scale,
        }


@dataclass
class FastModeFastStageSampling:
    """Sparse measurement selection used by the fast OE solve.

    Fastmode can trade retrieval speed against information content only through
    this explicit OE setting.  The default keeps a blue continuum window plus
    sparse samples across the O2 A P branch, then the final-correction settings
    run one full-physics update on their own sparse wavelength set.

    `windows` selects evenly spaced samples from one or more measured wavelength
    intervals.  `wavelengths_nm` overrides the window selector with explicit
    measured wavelengths.  `uncertainty_scale=None` applies retained-fraction
    uncertainty scaling so a sparse fast stage keeps comparable total weight.
    """

    enabled: bool = True
    windows: tuple[FastModeWavelengthWindow, ...] = field(
        default_factory=default_fast_stage_wavelength_windows
    )
    wavelengths_nm: tuple[float, ...] = ()
    uncertainty_scale: float | None = None

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        allowed = {
            "enabled",
            "windows",
            "wavelengths_nm",
            "uncertainty_scale",
        }
        reject_unknown_fields(data, allowed, "fastmode fast-stage sampling")
        defaults = cls()
        windows_value = data.get("windows", [window.to_dict() for window in defaults.windows])
        wavelengths_value = data.get("wavelengths_nm", defaults.wavelengths_nm)
        wavelengths = (
            measured_wavelength_tuple(float_sequence(wavelengths_value, label="wavelengths_nm"))
            if wavelengths_value
            else ()
        )

        return cls(
            enabled=to_bool(data.get("enabled", defaults.enabled)),
            windows=tuple(
                FastModeWavelengthWindow.from_dict(
                    window,
                    label="fastmode fast-stage sampling window",
                )
                for window in object_dict_list(windows_value)
            ),
            wavelengths_nm=wavelengths,
            uncertainty_scale=finite_positive_optional_float(
                data.get("uncertainty_scale", defaults.uncertainty_scale),
                label="fastmode fast-stage sampling",
            ),
        )

    def resolved_wavelengths(
        self,
        measurement_wavelengths_nm: Sequence[float],
    ) -> tuple[float, ...]:
        """Return concrete fast-stage wavelengths on the measurement grid."""

        axis = measured_wavelength_tuple(measurement_wavelengths_nm)

        if not self.enabled:
            return axis

        if self.wavelengths_nm:
            indices = measurement_indices_for_wavelengths(
                axis,
                self.wavelengths_nm,
                label="fastmode fast-stage wavelengths",
            )

            return tuple(axis[index] for index in indices)

        if not self.windows:
            raise ValueError(
                "fastmode fast-stage sampling needs at least one window or explicit wavelengths"
            )

        selected: set[float] = set()

        for window in self.windows:
            selected.update(
                window.resolved_wavelengths(
                    axis,
                    label="fastmode fast-stage sampling",
                    minimum_samples=1,
                )
            )

        wavelengths = tuple(sorted(selected))

        if len(wavelengths) < 2:
            raise ValueError("fastmode fast-stage sampling retained fewer than two wavelengths")

        return wavelengths

    def resolved_dict(self, measurement_wavelengths_nm: Sequence[float]) -> dict[str, object]:
        """Return the executed fast-stage sampling with explicit wavelengths."""

        wavelengths = self.resolved_wavelengths(measurement_wavelengths_nm)

        return {
            "enabled": self.enabled,
            "windows": [window.to_dict() for window in self.windows],
            "wavelengths_nm": list(wavelengths),
            "sample_count": len(wavelengths),
            "uncertainty_scale": self.uncertainty_scale,
        }

    def to_dict(self) -> dict[str, object]:

        return {
            "enabled": self.enabled,
            "windows": [window.to_dict() for window in self.windows],
            "wavelengths_nm": list(self.wavelengths_nm),
            "uncertainty_scale": self.uncertainty_scale,
        }


@dataclass
class FastModeOe:
    """OE-specific fastmode settings.

    `controls` apply to the fast retrieval stage.  `fast_stage_sampling`
    selects the measured wavelengths passed to that fast solve.  `final_correction`
    controls the optional sparse full-physics update that is applied after
    fastmode convergence.
    """

    controls: FastModeOeControls
    fast_stage_sampling: FastModeFastStageSampling
    final_correction: FastModeFinalCorrection

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        allowed = {"controls", "fast_stage_sampling", "final_correction"}
        reject_unknown_fields(data, allowed, "fastmode OE")

        return cls(
            controls=FastModeOeControls.from_dict(object_dict(data.get("controls", {}))),
            fast_stage_sampling=FastModeFastStageSampling.from_dict(
                object_dict(data.get("fast_stage_sampling", {}))
            ),
            final_correction=FastModeFinalCorrection.from_dict(
                object_dict(data.get("final_correction", {}))
            ),
        )

    @classmethod
    def defaults(cls) -> Self:

        return cls(
            controls=FastModeOeControls(),
            fast_stage_sampling=FastModeFastStageSampling(),
            final_correction=FastModeFinalCorrection(),
        )

    def resolved_dict(self, measurement_wavelengths_nm: Sequence[float]) -> dict[str, object]:

        return {
            "controls": self.controls.to_dict(),
            "fast_stage_sampling": self.fast_stage_sampling.resolved_dict(
                measurement_wavelengths_nm
            ),
            "final_correction": self.final_correction.resolved_dict(measurement_wavelengths_nm),
        }

    def to_dict(self) -> dict[str, object]:

        return {
            "controls": self.controls.to_dict(),
            "fast_stage_sampling": self.fast_stage_sampling.to_dict(),
            "final_correction": self.final_correction.to_dict(),
        }


@dataclass
class FastModeOptimisation:
    """Inspectable O2 A fastmode settings owned by the case.

    Enabling this section does not mutate the physical case immediately.  The
    RTM and adaptive-grid overrides are applied to a copied native case at load
    time, while OE controls and final-correction settings stay on the Python
    case so `retrieve` can run the complete fastmode retrieval in one session.
    """

    enabled: bool = False
    radiative_transfer: FastModeRadiativeTransfer = field(default_factory=FastModeRadiativeTransfer)
    adaptive_reference_grid: FastModeAdaptiveReferenceGrid = field(
        default_factory=FastModeAdaptiveReferenceGrid
    )
    oe: FastModeOe = field(default_factory=FastModeOe.defaults)

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        allowed = {
            "enabled",
            "radiative_transfer",
            "adaptive_reference_grid",
            "oe",
        }
        reject_unknown_fields(data, allowed, "fastmode")

        return cls(
            enabled=to_bool(data.get("enabled", False)),
            radiative_transfer=FastModeRadiativeTransfer.from_dict(
                object_dict(data.get("radiative_transfer", {}))
            ),
            adaptive_reference_grid=FastModeAdaptiveReferenceGrid.from_dict(
                object_dict(data.get("adaptive_reference_grid", {}))
            ),
            oe=FastModeOe.from_dict(object_dict(data.get("oe", {}))),
        )

    def apply_to_case(self, case: FastModeApplicationCase) -> None:
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
    """Case-owned optimisation modes for O2 A workflows.

    The public flow remains one O2 A case and one OE entrypoint.  Optimisation
    settings live beside the physical inputs so they can be serialized and
    rejected if unknown fields are parsed.
    """

    fastmode: FastModeOptimisation

    @classmethod
    def from_dict(cls, data: dict[str, object]) -> Self:

        allowed = {"fastmode"}
        reject_unknown_fields(data, allowed, "O2 A optimisation")

        return cls(fastmode=FastModeOptimisation.from_dict(object_dict(data.get("fastmode", {}))))

    @classmethod
    def defaults(cls) -> Self:

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
    *,
    label: str = "correction wavelengths",
) -> list[int]:
    """Map requested wavelengths onto the measured retrieval grid."""

    measurement_axis = measured_wavelength_tuple(measurement_wavelengths_nm)
    requested_axis = measured_wavelength_tuple(requested_wavelengths_nm)

    if len(requested_axis) < 2:
        raise ValueError(f"{label} must contain at least two samples")

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
            raise ValueError(f"{label} must overlap the measurement grid")

        index = min(candidates, key=lambda candidate: abs(measurement_axis[candidate] - requested))

        if abs(measurement_axis[index] - requested) > tolerance:
            raise ValueError(f"{label} must lie on the measurement grid")

        if index <= previous_index:
            raise ValueError(f"{label} must map to unique increasing samples")

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
