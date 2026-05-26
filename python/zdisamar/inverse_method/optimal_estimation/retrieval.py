"""Retrieval data objects and diagnostics."""

import math
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass, field
from numbers import Real
from typing import Self

from ...display import NotebookDisplay, PrettyMapping
from .rtm_evaluation import RtmEvaluation
from .state_vector import StateName

MIN_SIGNAL_FOR_SNR = 1.0e-300


def measurement_float(value: object, *, label: str) -> float:
    """Convert one public measurement scalar with a typed failure."""

    if isinstance(value, bool) or not isinstance(value, Real):
        raise TypeError(f"{label} must contain only numeric values")

    return float(value)


def measurement_values(
    values: object,
    *,
    count: int,
    label: str,
) -> tuple[float, ...]:
    """Return one measurement vector, broadcasting scalar instrument terms."""

    if isinstance(values, Real) and not isinstance(values, bool):
        return (float(values),) * count

    if isinstance(values, str | bytes):
        raise TypeError(f"{label} must be a number or numeric sequence")

    if not isinstance(values, Iterable):
        raise TypeError(f"{label} must be a number or numeric sequence")

    parsed = tuple(measurement_float(value, label=label) for value in values)

    if len(parsed) != count:
        raise ValueError(f"{label} length must match the measurement grid")

    return parsed


@dataclass(frozen=True, init=False)
class Measurement(NotebookDisplay):
    """Observed retrieval vector and per-sample reflectance signal-to-noise ratio.

    The first implementation uses reflectance as the retrieval quantity because
    the current O2 A validation bundle is expressed as sun-normalized
    radiance/reflectance.  The native OE request converts signal-to-noise into
    reflectance sigma and then into the diagonal measurement covariance expected
    by the solver.
    """

    wavelength_nm: tuple[float, ...]
    reflectance: tuple[float, ...]
    signal_to_noise: tuple[float, ...]

    def __init__(
        self,
        wavelength_nm: Sequence[float],
        reflectance: Sequence[float],
        signal_to_noise: float | Sequence[float],
    ) -> None:

        wavelength_values = tuple(float(value) for value in wavelength_nm)
        reflectance_values = tuple(float(value) for value in reflectance)
        signal_to_noise_values = measurement_values(
            signal_to_noise,
            count=len(wavelength_values),
            label="signal_to_noise",
        )

        if not wavelength_values:
            raise ValueError("measurement must contain at least one sample")

        if len(wavelength_values) != len(reflectance_values) or len(wavelength_values) != len(
            signal_to_noise_values
        ):
            raise ValueError("measurement wavelength, reflectance, and SNR shapes must match")

        if any(not math.isfinite(value) for value in wavelength_values + reflectance_values):
            raise ValueError("measurement wavelength and reflectance values must be finite")

        if any(not math.isfinite(value) or value <= 0.0 for value in signal_to_noise_values):
            raise ValueError("measurement signal-to-noise values must be finite and positive")

        if any(
            upper <= lower
            for lower, upper in zip(wavelength_values, wavelength_values[1:], strict=False)
        ):
            raise ValueError("measurement wavelength grid must be strictly increasing")

        object.__setattr__(self, "wavelength_nm", wavelength_values)
        object.__setattr__(self, "reflectance", reflectance_values)
        object.__setattr__(self, "signal_to_noise", signal_to_noise_values)

    @classmethod
    def from_reflectance_uncertainty(
        cls,
        *,
        wavelength_nm: Sequence[float],
        reflectance: Sequence[float],
        reflectance_uncertainty: float | Sequence[float],
    ) -> Self:
        """Build a measurement when an error model is already in reflectance units."""

        wavelength_values = tuple(float(value) for value in wavelength_nm)
        reflectance_values = tuple(float(value) for value in reflectance)
        uncertainty_values = measurement_values(
            reflectance_uncertainty,
            count=len(reflectance_values),
            label="reflectance_uncertainty",
        )

        if len(wavelength_values) != len(reflectance_values):
            raise ValueError("wavelength_nm and reflectance lengths must match")

        if any(not math.isfinite(value) or value <= 0.0 for value in uncertainty_values):
            raise ValueError("reflectance_uncertainty values must be finite and positive")

        signal_to_noise = tuple(
            max(abs(reflectance_value), MIN_SIGNAL_FOR_SNR) / uncertainty
            for reflectance_value, uncertainty in zip(
                reflectance_values,
                uncertainty_values,
                strict=True,
            )
        )

        return cls(
            wavelength_nm=wavelength_values,
            reflectance=reflectance_values,
            signal_to_noise=signal_to_noise,
        )

    @property
    def reflectance_uncertainty(self) -> tuple[float, ...]:
        """Return the per-wavelength 1-sigma reflectance noise implied by SNR."""

        return tuple(
            max(abs(reflectance), MIN_SIGNAL_FOR_SNR) / snr
            for reflectance, snr in zip(self.reflectance, self.signal_to_noise, strict=True)
        )

    def summary(self) -> PrettyMapping:
        """Return a compact display summary for notebooks."""

        return PrettyMapping(
            "MeasurementSummary",
            {
                "samples": len(self.wavelength_nm),
                "wavelength_nm": [self.wavelength_nm[0], self.wavelength_nm[-1]],
                "reflectance": [min(self.reflectance), max(self.reflectance)],
                "signal_to_noise": [min(self.signal_to_noise), max(self.signal_to_noise)],
            },
        )

    def __repr__(self) -> str:

        return (
            "Measurement("
            f"samples={len(self.wavelength_nm)}, "
            f"wavelength_nm={self.wavelength_nm[0]:g}-{self.wavelength_nm[-1]:g}, "
            f"signal_to_noise={min(self.signal_to_noise):g}-{max(self.signal_to_noise):g}"
            ")"
        )


@dataclass(frozen=True)
class RetrievalControls:
    """Iteration controls for the optimal estimation loop."""

    max_iterations: int = 10
    state_vector_convergence_threshold: float = 1.0
    max_change_transformed_state: float = 1.0

    @classmethod
    def from_disamar_retrieval_specs(cls) -> Self:
        """Return controls from the current DISAMAR `retrieval_specs` fixture."""

        return cls(
            max_iterations=10,
            state_vector_convergence_threshold=1.0,
            max_change_transformed_state=1.0,
        )


@dataclass(frozen=True)
class Iteration:
    """Per-iteration retrieval diagnostics.

    These fields record the quantities needed to audit an optimal estimation trajectory:
    chi-square for the spectral residual, chi-square for the state-vector
    movement, the convergence metric, and whether the signal-to-noise reduction
    safeguard was inactive.
    """

    index: int
    state: Sequence[float]
    chi2: float
    chi2_reflectance: float
    chi2_state_vector: float
    state_vector_convergence: float
    snr_normal: bool


@dataclass(frozen=True)
class FastCorrection:
    """Diagnostics for a fastmode retrieval finalized by one full-physics update."""

    fast_iterations: int
    fast_converged: bool
    fast_state: Sequence[float]
    full_correction: Iteration | None
    full_correction_converged: bool
    full_correction_state_vector_convergence: float


@dataclass(frozen=True)
class Result(NotebookDisplay):
    """Final optimal estimation state plus diagnostics needed for retrieval experiments."""

    state_names: tuple[StateName, ...]
    state: Sequence[float]
    iterations: int
    converged: bool
    history: tuple[Iteration, ...]
    posterior_covariance: Sequence[Sequence[float]]
    averaging_kernel: Sequence[Sequence[float]]
    measurement: Measurement | None = None
    final_evaluation: RtmEvaluation | None = None
    last_evaluated_state: Sequence[float] | None = None
    last_evaluation: RtmEvaluation | None = None
    initial_state: Sequence[float] | None = None
    fast_correction: FastCorrection | None = None
    _final_evaluation_factory: Callable[[], RtmEvaluation] | None = field(
        default=None,
        repr=False,
        compare=False,
    )

    def __getattribute__(self, name: str):
        """Evaluate the final spectrum only when a caller asks for it."""

        if name != "final_evaluation":
            return object.__getattribute__(self, name)

        evaluation = object.__getattribute__(self, name)

        if evaluation is not None:
            return evaluation

        factory = object.__getattribute__(self, "_final_evaluation_factory")

        if factory is None:
            return None

        evaluation = factory()
        object.__setattr__(self, "final_evaluation", evaluation)
        object.__setattr__(self, "_final_evaluation_factory", None)

        return evaluation

    def value(self, name: StateName) -> float:
        """Return a named retrieval value without exposing array position."""

        return float(self.state[self.state_names.index(name)])

    def posterior_uncertainty(self, name: StateName) -> float:
        """Return one posterior 1-sigma state uncertainty."""

        index = self.state_names.index(name)

        return math.sqrt(max(float(self.posterior_covariance[index][index]), 0.0))

    def summary(self) -> PrettyMapping:
        """Return a compact display summary for notebooks."""

        state = {
            name: {
                "value": self.value(name),
                "posterior_uncertainty": self.posterior_uncertainty(name),
            }
            for name in self.state_names
        }
        payload: dict[str, object] = {
            "converged": self.converged,
            "iterations": self.iterations,
            "state": state,
        }

        if self.fast_correction is not None:
            payload["fastmode"] = {
                "fast_iterations": self.fast_correction.fast_iterations,
                "fast_converged": self.fast_correction.fast_converged,
                "full_correction_converged": self.fast_correction.full_correction_converged,
            }

        return PrettyMapping("RetrievalSummary", payload)

    def __repr__(self) -> str:

        values = ", ".join(f"{name}={self.value(name):g}" for name in self.state_names)

        return f"Result(converged={self.converged}, iterations={self.iterations}, {values})"

    @property
    def plot(self):
        """Import plotting only when a caller asks for retrieval figures."""

        from ...plot.optimal_estimation import OptimalEstimationPlot

        return OptimalEstimationPlot(self)
