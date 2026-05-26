"""Retrieval data objects and diagnostics."""

from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from typing import Self

from .rtm_evaluation import RtmEvaluation
from .state_vector import StateName


@dataclass(frozen=True)
class Measurement:
    """Observed retrieval vector y and diagonal measurement covariance.

    The first implementation uses reflectance as the retrieval quantity because
    the current O2 A validation bundle is expressed as sun-normalized
    radiance/reflectance.  `variance` is the diagonal of S_e; a full covariance
    can be added later without changing the public meaning of this type.
    """

    wavelength_nm: Sequence[float]
    reflectance: Sequence[float]
    variance: Sequence[float]


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
class Result:
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

    @property
    def plot(self):
        """Import plotting only when a caller asks for retrieval figures."""

        from ...plot.optimal_estimation import OptimalEstimationPlot

        return OptimalEstimationPlot(self)
