"""Retrieval data objects and diagnostics."""

from collections.abc import Callable
from dataclasses import dataclass, field

import numpy as np

from .forward_evaluation import ForwardEvaluation
from .state_vector import StateName


@dataclass(frozen=True)
class Measurement:
    """Observed retrieval vector y and diagonal measurement covariance.

    The first implementation uses reflectance as the retrieval quantity because
    the current O2 A validation bundle is expressed as sun-normalized
    radiance/reflectance.  `variance` is the diagonal of S_e; a full covariance
    can be added later without changing the public meaning of this type.
    """

    wavelength_nm: np.ndarray
    reflectance: np.ndarray
    variance: np.ndarray


@dataclass(frozen=True)
class RetrievalControls:
    """Iteration controls for the optimal estimation loop."""

    max_iterations: int = 10
    state_vector_convergence_threshold: float = 1.0
    max_change_transformed_state: float = 1.0

    @classmethod
    def from_disamar_retrieval_specs(cls) -> RetrievalControls:
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
    state: np.ndarray
    chi2: float
    chi2_reflectance: float
    chi2_state_vector: float
    state_vector_convergence: float
    snr_normal: bool


@dataclass(frozen=True)
class IterationTiming:
    """Wall-clock timing for the two expensive phases of one retrieval update."""

    index: int
    forward_model_and_jacobian_s: float
    solver_update_s: float
    total_iteration_s: float


@dataclass(frozen=True)
class Result:
    """Final optimal estimation state plus diagnostics needed for retrieval experiments."""

    state_names: tuple[StateName, ...]
    state: np.ndarray
    iterations: int
    converged: bool
    history: tuple[Iteration, ...]
    posterior_covariance: np.ndarray
    averaging_kernel: np.ndarray
    timing: tuple[IterationTiming, ...] = ()
    measurement: Measurement | None = None
    last_evaluated_state: np.ndarray | None = None
    last_evaluation: ForwardEvaluation | None = None
    _final_evaluation: ForwardEvaluation | None = field(default=None, repr=False)
    _final_evaluation_factory: Callable[[], ForwardEvaluation] | None = field(
        default=None,
        repr=False,
        compare=False,
    )

    def value(self, name: StateName) -> float:
        return float(self.state[self.state_names.index(name)])

    @property
    def final_evaluation(self) -> ForwardEvaluation | None:
        evaluation = self._final_evaluation
        if evaluation is not None:
            return evaluation
        factory = self._final_evaluation_factory
        if factory is None:
            return None
        evaluation = factory()
        object.__setattr__(self, "_final_evaluation", evaluation)
        object.__setattr__(self, "_final_evaluation_factory", None)
        return evaluation

    @property
    def plot(self):
        from ...plot.optimal_estimation import OptimalEstimationPlot

        return OptimalEstimationPlot(self)
