"""Generic state-vector composition."""

from collections.abc import Sequence
from typing import Any, Protocol

import numpy as np

StateName = str


class StateVectorParameter(Protocol):
    """One scalar retrieval coordinate and its model-setting writer."""

    name: StateName
    initial: float
    prior: float
    variance: float
    lower: float | None
    upper: float | None

    def write_to(self, target: Any, value: float) -> None:
        """Write one scalar state value into the inverse-model settings target."""


class StateVector:
    """Ordered retrieval variables plus prior covariance terms."""

    def __init__(self, parameters: Sequence[StateVectorParameter]):

        if not parameters:
            raise ValueError("state vector must contain at least one parameter")

        names = tuple(parameter.name for parameter in parameters)

        if len(set(names)) != len(names):
            raise ValueError("state vector parameter names must be unique")

        self._parameters = tuple(parameters)

    @property
    def parameters(self) -> tuple[StateVectorParameter, ...]:
        """Expose retrieval variables in solver order."""

        return self._parameters

    @property
    def names(self) -> tuple[StateName, ...]:
        """Return retrieval variable names in solver order."""

        return tuple(parameter.name for parameter in self._parameters)

    @property
    def jacobian_names(self) -> tuple[StateName, ...]:
        """Return the model Jacobian names used for each retrieval variable."""

        return tuple(
            getattr(parameter, "jacobian_name", parameter.name) for parameter in self._parameters
        )

    def jacobian_scales(self, state: np.ndarray) -> np.ndarray:
        """Scale model Jacobians into the chosen retrieval variables."""

        if len(state) != len(self._parameters):
            raise ValueError("state length does not match state vector")

        scales: list[float] = []

        for parameter, value in zip(self._parameters, state, strict=True):
            scale = getattr(parameter, "jacobian_scale", None)
            scales.append(1.0 if scale is None else float(scale(float(value))))

        return np.asarray(scales, dtype=np.float64)

    def initial_state(self) -> np.ndarray:
        """Return the starting retrieval state."""

        return np.array([parameter.initial for parameter in self._parameters], dtype=np.float64)

    def prior_state(self) -> np.ndarray:
        """Return the prior retrieval state."""

        return np.array([parameter.prior for parameter in self._parameters], dtype=np.float64)

    def prior_covariance(self) -> np.ndarray:
        """Return the diagonal prior covariance used by this OE solver."""

        return np.diag([parameter.variance for parameter in self._parameters]).astype(np.float64)

    def clip_to_bounds(self, state: np.ndarray) -> np.ndarray:
        """Keep updated retrieval variables within their physical bounds."""

        bounded = np.array(state, copy=True)

        for index, parameter in enumerate(self._parameters):
            if parameter.lower is not None:
                bounded[index] = max(float(parameter.lower), bounded[index])

            if parameter.upper is not None:
                bounded[index] = min(float(parameter.upper), bounded[index])

        return bounded

    def write_to(self, target: Any, state: np.ndarray) -> None:
        """Write all retrieval variables into one O2 A scene."""

        if len(state) != len(self._parameters):
            raise ValueError("state length does not match state vector")

        for parameter, value in zip(self._parameters, state, strict=True):
            parameter.write_to(target, float(value))
