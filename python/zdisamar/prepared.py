"""Prepared O2A inputs and user-facing forward-model helpers."""

from __future__ import annotations

import copy
import ctypes
from typing import Any

from .c_abi import CSpectrum
from .native_tables import (
    AtmosphericBudget,
    InstrumentResponseTable,
    O2LineContributions,
    OxygenCollisionInducedAbsorptionDiagnosticTable,
    RadiativeTransferDiagnosticTable,
)
from .runtime import Context, LibraryPath
from .spectrum import Spectrum
from .types import O2AInput


class AtmosphereDiagnostics:
    """Prepared atmospheric diagnostic entrypoints."""

    def __init__(self, prepared: Any):
        self._prepared = prepared

    def budget(self, wavelengths_nm) -> AtmosphericBudget:
        return self._prepared.atmospheric_budget(wavelengths_nm)


class O2LineDiagnostics:
    """Prepared O2 line diagnostic entrypoints."""

    def __init__(self, prepared: Any):
        self._prepared = prepared

    def contributions(self, wavelengths_nm, max_rows: int = 50_000) -> O2LineContributions:
        return self._prepared.o2_line_contributions(wavelengths_nm, max_rows=max_rows)


class PreparedO2ABase:
    """Shared prepared O2A wrapper behavior."""

    def __init__(self, ctx: Context, input: O2AInput, library_path: LibraryPath):
        self._ctx: Context | None = ctx
        self._input = copy.deepcopy(input)
        self._library_path = library_path

    @property
    def input(self) -> O2AInput:
        return copy.deepcopy(self._input)

    @property
    def library_path(self) -> LibraryPath:
        return self._library_path

    def _require_context(self) -> Context:
        if self._ctx is None:
            raise RuntimeError("prepared input is closed")
        return self._ctx

    def forward_model(self, *, jacobian: bool = False) -> Spectrum:
        return self._require_context().forward_model(jacobian=jacobian)

    @property
    def atmosphere(self) -> AtmosphereDiagnostics:
        self._require_context()
        return AtmosphereDiagnostics(self)

    @property
    def o2_lines(self) -> O2LineDiagnostics:
        self._require_context()
        return O2LineDiagnostics(self)

    @property
    def collision_induced_absorption(self):
        self._require_context()
        from .diagnostics import OxygenCollisionInducedAbsorptionDiagnostics

        return OxygenCollisionInducedAbsorptionDiagnostics(self)

    @property
    def instrument_response(self):
        self._require_context()
        from .diagnostics import InstrumentResponseDiagnostics

        return InstrumentResponseDiagnostics(self)

    @property
    def radiative_transfer(self):
        self._require_context()
        from .diagnostics import RadiativeTransferDiagnostics

        return RadiativeTransferDiagnostics(self)

    @property
    def perturbations(self):
        self._require_context()
        from .diagnostics import PerturbationDiagnostics

        return PerturbationDiagnostics(self)

    def atmospheric_budget(self, wavelengths_nm) -> AtmosphericBudget:
        return self._require_context().atmospheric_budget(wavelengths_nm)

    def o2_line_contributions(self, wavelengths_nm, max_rows: int = 50_000) -> O2LineContributions:
        return self._require_context().o2_line_contributions(wavelengths_nm, max_rows=max_rows)

    def instrument_response_sampling(
        self,
        wavelengths_nm,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ) -> InstrumentResponseTable:
        return self._require_context().instrument_response_sampling(
            wavelengths_nm, channels=channels
        )

    def collision_induced_absorption_diagnostics(
        self, wavelengths_nm
    ) -> OxygenCollisionInducedAbsorptionDiagnosticTable:
        return self._require_context().collision_induced_absorption_diagnostics(wavelengths_nm)

    def radiative_transfer_diagnostics(
        self,
        wavelengths_nm,
        spectrum: Spectrum | None = None,
    ) -> RadiativeTransferDiagnosticTable:
        return self._require_context().radiative_transfer_diagnostics(
            wavelengths_nm, spectrum=spectrum
        )

    def close(self) -> None:
        if self._ctx is not None:
            self._ctx.close()
            self._ctx = None

    def __enter__(self):
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


class PreparedDefaultO2A(PreparedO2ABase):
    """Prepared default O2A input for research-facing forward-model calls."""

    def __init__(self, library_path: LibraryPath = None):
        ctx = Context(library_path)
        try:
            input = ctx.default_o2a_input()
            ctx.prepare_default_o2a()
        except Exception:
            ctx.close()
            raise
        super().__init__(ctx, input, library_path)


class PreparedO2A(PreparedO2ABase):
    """Prepared O2A input for research-facing forward-model calls."""

    def __init__(self, input: O2AInput, library_path: LibraryPath = None):
        ctx = Context(library_path)
        try:
            ctx.prepare_o2a(input)
        except Exception:
            ctx.close()
            raise
        super().__init__(ctx, input, library_path)


def o2a_disamar_reference_input(
    library_path: LibraryPath = None,
) -> O2AInput:
    with Context(library_path) as ctx:
        return ctx.default_o2a_input()


def prepare(
    input: O2AInput,
    library_path: LibraryPath = None,
) -> PreparedO2A:
    return PreparedO2A(input, library_path)


def prepare_default_o2a(
    library_path: LibraryPath = None,
) -> PreparedDefaultO2A:
    return PreparedDefaultO2A(library_path)


def forward(library_path: LibraryPath = None, *, jacobian: bool = False) -> Spectrum:
    ctx = Context(library_path)
    try:
        ctx.prepare_default_o2a()
        raw = CSpectrum()
        runner = ctx._lib.zds_run_spectrum_jacobian if jacobian else ctx._lib.zds_run_spectrum
        ctx._check(runner(ctx._ctx, ctypes.byref(raw)))
        return Spectrum(ctx, raw, close_owner=True)
    except Exception:
        ctx.close()
        raise
