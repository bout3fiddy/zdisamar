"""Generic state-vector composition."""

import math
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Protocol

StateName = str


class StateVectorParameter(Protocol):
    """One scalar retrieval coordinate and its model-setting writer."""

    name: StateName
    initial: float
    prior: float
    uncertainty: float
    lower: float | None
    upper: float | None

    def write_to(self, target: object, value: float) -> None:
        """Write one scalar state value into the inverse-model settings target."""


@dataclass(frozen=True)
class StateVector:
    """Ordered retrieval variables plus prior uncertainty terms."""

    parameters: Sequence[StateVectorParameter]

    def __post_init__(self) -> None:

        parameters = tuple(self.parameters)

        if not parameters:
            raise ValueError("state vector must contain at least one parameter")

        names = tuple(parameter.name for parameter in parameters)

        if len(set(names)) != len(names):
            raise ValueError("state vector parameter names must be unique")

        for parameter in parameters:
            uncertainty = float(parameter.uncertainty)

            if not math.isfinite(uncertainty) or uncertainty <= 0.0:
                raise ValueError("state vector uncertainty values must be finite and positive")

        object.__setattr__(self, "parameters", parameters)

    @property
    def names(self) -> tuple[StateName, ...]:
        """Return retrieval variable names in solver order."""

        return tuple(parameter.name for parameter in self.parameters)

    @property
    def jacobian_names(self) -> tuple[StateName, ...]:
        """Return the model Jacobian names used for each retrieval variable."""

        return tuple(
            getattr(parameter, "jacobian_name", parameter.name) for parameter in self.parameters
        )

    def jacobian_scales(self, state: Sequence[float]) -> tuple[float, ...]:
        """Scale model Jacobians into the chosen retrieval variables."""

        if len(state) != len(self.parameters):
            raise ValueError("state length does not match state vector")

        scales: list[float] = []

        for parameter, value in zip(self.parameters, state, strict=True):
            scale = getattr(parameter, "jacobian_scale", None)
            scales.append(1.0 if scale is None else float(scale(float(value))))

        return tuple(scales)

    def initial_state(self) -> tuple[float, ...]:
        """Return the starting retrieval state."""

        return tuple(float(parameter.initial) for parameter in self.parameters)

    def prior_state(self) -> tuple[float, ...]:
        """Return the prior retrieval state."""

        return tuple(float(parameter.prior) for parameter in self.parameters)

    def prior_covariance(self) -> tuple[tuple[float, ...], ...]:
        """Return the diagonal prior covariance used by this OE solver."""

        return tuple(
            tuple(
                float(parameter.uncertainty) * float(parameter.uncertainty)
                if row == column
                else 0.0
                for column, _ in enumerate(self.parameters)
            )
            for row, parameter in enumerate(self.parameters)
        )

    def clip_to_bounds(self, state: Sequence[float]) -> tuple[float, ...]:
        """Keep updated retrieval variables within their physical bounds."""

        bounded = [float(value) for value in state]

        for index, parameter in enumerate(self.parameters):
            if parameter.lower is not None:
                bounded[index] = max(float(parameter.lower), bounded[index])

            if parameter.upper is not None:
                bounded[index] = min(float(parameter.upper), bounded[index])

        return tuple(bounded)

    def write_to(self, target: object, state: Sequence[float]) -> None:
        """Write all retrieval variables into one O2 A scene."""

        if len(state) != len(self.parameters):
            raise ValueError("state length does not match state vector")

        for parameter, value in zip(self.parameters, state, strict=True):
            parameter.write_to(target, float(value))
