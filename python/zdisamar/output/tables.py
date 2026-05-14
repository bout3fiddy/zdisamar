"""Dataclass tables returned by RTM diagnostic functions."""

from collections.abc import Mapping
from dataclasses import dataclass
from typing import ClassVar

import numpy as np
from numpy.typing import NDArray

from ..bindings.structures import (
    CAtmosphericBudgetRow,
    CInstrumentResponseRow,
    CRadiativeTransferDiagnosticRow,
    O2LineContributionRow,
    OxygenCollisionInducedAbsorptionRow,
)


def field_names(structure: type[object]) -> tuple[str, ...]:
    """Keep Python table columns in the same order as the model output."""

    fields = getattr(structure, "_fields_")  # noqa: B009

    return tuple(str(field[0]) for field in fields)


@dataclass(frozen=True)
class RtmTable:
    """Copied RTM diagnostic rows."""

    data: NDArray[np.void]

    columns: ClassVar[tuple[str, ...]]
    label_columns: ClassVar[Mapping[str, tuple[str, Mapping[int, str]]]] = {}

    @property
    def row_count(self) -> int:

        return int(self.data.shape[0])

    @property
    def table(self) -> NDArray[np.void]:
        """Return a copy so analysis code cannot mutate the stored table."""

        return self.data.copy()

    def column(self, name: str) -> NDArray[np.generic]:

        if name not in self.columns:
            raise KeyError(name)

        return self.data[name].copy()

    def to_rows(self) -> list[dict[str, object]]:
        """Return rows with labels for coded model fields."""

        rows: list[dict[str, object]] = []

        for row in self.data:
            item = {name: row[name].item() for name in self.columns}

            for label_name, (source_name, labels) in self.label_columns.items():
                item[label_name] = labels.get(int(item[source_name]), "unknown")

            rows.append(item)

        return rows

    def to_pandas(self):
        """Create a DataFrame only when the caller needs pandas."""

        import pandas as pd

        return pd.DataFrame.from_records(self.to_rows())


@dataclass(frozen=True)
class AtmosphericBudget(RtmTable):
    """Atmospheric support-row absorption and scattering table."""

    support_row_kind_labels = {
        0: "physical",
        1: "parity_boundary",
        2: "parity_active",
    }
    subcolumn_label_labels = {
        0: "unspecified",
        1: "boundary_layer",
        2: "free_troposphere",
        3: "fit_interval",
        4: "stratosphere",
    }
    columns = field_names(CAtmosphericBudgetRow)
    label_columns = {
        "support_row_kind_label": ("support_row_kind", support_row_kind_labels),
        "subcolumn_label_label": ("subcolumn_label", subcolumn_label_labels),
    }

    @property
    def plot(self):

        from ..plot.atmosphere import BudgetPlot

        return BudgetPlot(self)


@dataclass(frozen=True)
class O2LineContributions(RtmTable):
    """O2 line-by-line contribution table for selected wavelengths."""

    total_row_count: int = 0
    truncated: bool = False

    row_kind_labels = {
        0: "weak_line",
        1: "strong_line",
    }
    status_labels = {
        0: "weak_included",
        1: "weak_excluded_by_strong_line",
        2: "strong_sidecar",
        3: "weak_zero_after_cutoff",
    }
    columns = field_names(O2LineContributionRow)
    label_columns = {
        "row_kind_label": ("row_kind", row_kind_labels),
        "status_label": ("status", status_labels),
    }


@dataclass(frozen=True)
class InstrumentResponseTable(RtmTable):
    """Instrument response support-weight table."""

    channel_labels = {
        0: "radiance",
        1: "irradiance",
    }
    integration_mode_labels = {
        0: "auto",
        1: "explicit_hr_grid",
        2: "disamar_hr_grid",
        3: "adaptive",
    }
    columns = field_names(CInstrumentResponseRow)
    label_columns = {
        "channel_label": ("channel", channel_labels),
        "integration_mode_label": ("integration_mode", integration_mode_labels),
    }

    @property
    def plot(self):

        from ..plot.instrument_response import InstrumentResponsePlot

        return InstrumentResponsePlot(self)


@dataclass(frozen=True)
class OxygenCollisionInducedAbsorptionDiagnosticTable(RtmTable):
    """O2-O2 collision-induced absorption diagnostic table."""

    columns = field_names(OxygenCollisionInducedAbsorptionRow)

    @property
    def plot(self):

        from ..plot.collision_induced_absorption import CollisionInducedAbsorptionPlot

        return CollisionInducedAbsorptionPlot(self)


@dataclass(frozen=True)
class RadiativeTransferDiagnosticTable(RtmTable):
    """Bounded radiative-transfer diagnostic table."""

    columns = field_names(CRadiativeTransferDiagnosticRow)
