"""Shared wrappers for diagnostic tables returned by the O2 A model."""

from collections.abc import Mapping
from typing import Any, ClassVar

from ..bindings.structures import (
    CAtmosphericBudget,
    CAtmosphericBudgetRow,
    CInstrumentResponse,
    CInstrumentResponseRow,
    CRadiativeTransferDiagnosticRow,
    CRadiativeTransferDiagnostics,
    O2LineContributionRow,
    O2LineContributionsRaw,
    OxygenCollisionInducedAbsorptionDiagnosticsRaw,
    OxygenCollisionInducedAbsorptionRow,
)


class NativeTable:
    """Common behavior for diagnostic tables owned by the O2 A model."""

    columns: ClassVar[tuple[str, ...]]
    label_columns: ClassVar[Mapping[str, tuple[str, Mapping[int, str]]]] = {}
    _closed_message: ClassVar[str]
    _free_method: ClassVar[str]
    _raw_type: ClassVar[type[Any]]

    def __init__(self, owner: Any, raw: Any):

        self._owner: Any | None = owner
        self._raw: Any = raw
        self._table_cache: Any | None = None

    def _require_open(self) -> None:

        if self._owner is None or self._owner._ctx is None:
            raise RuntimeError(self._closed_message)

    @property
    def row_count(self) -> int:

        return int(self._raw.len)

    @property
    def table(self) -> Any:
        """Return a copy so analysis code cannot mutate the stored table."""

        return self._table().copy()

    def column(self, name: str) -> Any:

        if name not in self.columns:
            raise KeyError(name)

        return self._table()[name].copy()

    def to_rows(self) -> list[dict[str, object]]:
        """Return rows with labels for coded model fields."""

        rows: list[dict[str, object]] = []

        for row in self._table():
            item = {name: row[name].item() for name in self.columns}

            for label_name, (source_name, labels) in self.label_columns.items():
                item[label_name] = labels.get(int(item[source_name]), "unknown")

            rows.append(item)

        return rows

    def to_pandas(self) -> Any:
        """Create a DataFrame only when the caller needs pandas."""

        import pandas as pd

        return pd.DataFrame.from_records(self.to_rows())

    def close(self) -> None:
        """Release table memory held by the zdisamar model."""

        if self._owner is not None:
            getattr(self._owner, self._free_method)(self._raw)
            self._owner = None
            self._raw = self._raw_type()
            self._table_cache = None

    def __enter__(self):

        return self

    def __exit__(self, *_exc: object) -> None:

        self.close()

    def _table(self) -> Any:

        self._require_open()

        if self._table_cache is None:
            import numpy as np

            self._table_cache = np.ctypeslib.as_array(
                self._raw.rows,
                shape=(self._raw.len,),
            ).copy()

        return self._table_cache


def field_names(structure: type[Any]) -> tuple[str, ...]:
    """Keep Python table columns in the same order as the model output."""

    return tuple(str(field[0]) for field in structure._fields_)


class AtmosphericBudget(NativeTable):
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
    _closed_message = "atmospheric budget is closed"
    _free_method = "_free_atmospheric_budget"
    _raw_type = CAtmosphericBudget

    @property
    def plot(self):

        from ..plot.atmosphere import BudgetPlot

        return BudgetPlot(self)


class O2LineContributions(NativeTable):
    """O2 line-by-line contribution table for selected wavelengths."""

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
    _closed_message = "O2 line contribution table is closed"
    _free_method = "_free_o2_line_contributions"
    _raw_type = O2LineContributionsRaw

    @property
    def total_row_count(self) -> int:
        """Report how many O2 line rows existed before the requested cap."""

        return int(self._raw.total_row_count)

    @property
    def truncated(self) -> bool:
        """Show whether the line-contribution evidence was capped."""

        return bool(self._raw.truncated)


class InstrumentResponseTable(NativeTable):
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
    _closed_message = "instrument response table is closed"
    _free_method = "_free_instrument_response"
    _raw_type = CInstrumentResponse

    @property
    def plot(self):

        from ..plot.instrument_response import InstrumentResponsePlot

        return InstrumentResponsePlot(self)


class OxygenCollisionInducedAbsorptionDiagnosticTable(NativeTable):
    """O2-O2 collision-induced absorption diagnostic table."""

    columns = field_names(OxygenCollisionInducedAbsorptionRow)
    _closed_message = "O2-O2 collision-induced absorption diagnostic table is closed"
    _free_method = "_free_collision_induced_absorption_diagnostics"
    _raw_type = OxygenCollisionInducedAbsorptionDiagnosticsRaw

    @property
    def plot(self):

        from ..plot.collision_induced_absorption import CollisionInducedAbsorptionPlot

        return CollisionInducedAbsorptionPlot(self)


class RadiativeTransferDiagnosticTable(NativeTable):
    """Bounded radiative-transfer diagnostic table."""

    columns = field_names(CRadiativeTransferDiagnosticRow)
    _closed_message = "radiative-transfer diagnostic table is closed"
    _free_method = "_free_radiative_transfer_diagnostics"
    _raw_type = CRadiativeTransferDiagnostics
