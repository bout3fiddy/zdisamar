"""Prepared O2A inputs and user-facing forward-model helpers."""

import copy
import ctypes
from typing import Any

from ..bindings.context import Context, LibraryPath
from ..bindings.structures import CSpectrum
from ..input.wavelength_band.o2a import O2AInput
from ..output.spectrum import Spectrum
from ..output.tables import (
    AtmosphericBudget,
    InstrumentResponseTable,
    OxygenCollisionInducedAbsorptionDiagnosticTable,
)


# Feedback: prepared.py seems to be doing quite a bit of heavy lifting. but also,
# the name itself has very little meaning of its own.
class AtmosphereDiagnostics:
    """Atmospheric diagnostics for a prepared O2 A case."""

    def __init__(self, prepared: Any):

        self._prepared = prepared

    def budget(self, wavelengths_nm) -> AtmosphericBudget:
        """Inspect how optical depth is distributed through the atmosphere."""

        return self._prepared.atmospheric_budget(wavelengths_nm)


class PreparedO2ABase:
    """Shared behavior for an O2 A case that has already been prepared."""

    def __init__(self, ctx: Context, input: O2AInput, library_path: LibraryPath):

        self._ctx: Context | None = ctx
        self._input = copy.deepcopy(input)
        self._library_path = library_path

    @property
    def input(self) -> O2AInput:
        """Return a copy of the scene so the prepared calculation stays fixed."""

        return copy.deepcopy(self._input)

    @property
    def library_path(self) -> LibraryPath:

        return self._library_path

    def _require_context(self) -> Context:

        if self._ctx is None:
            raise RuntimeError("prepared input is closed")

        return self._ctx

    def forward_model(
        self,
        *,
        jacobian: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
    ) -> Spectrum:
        """Evaluate the prepared O2 A case once."""

        return self._require_context().forward_model(
            jacobian=jacobian,
            jacobian_state_names=jacobian_state_names,
        )

    @property
    def atmosphere(self) -> AtmosphereDiagnostics:
        """Group atmospheric diagnostics under the prepared case."""

        self._require_context()

        return AtmosphereDiagnostics(self)

    @property
    def collision_induced_absorption(self):
        """Group O2-O2 CIA diagnostics under the prepared case."""

        self._require_context()
        from ..output.diagnostics import OxygenCollisionInducedAbsorptionDiagnostics

        return OxygenCollisionInducedAbsorptionDiagnostics(self)

    @property
    def instrument_response(self):
        """Group instrument-response diagnostics under the prepared case."""

        self._require_context()
        from ..output.diagnostics import InstrumentResponseDiagnostics

        return InstrumentResponseDiagnostics(self)

    def atmospheric_budget(self, wavelengths_nm) -> AtmosphericBudget:

        return self._require_context().atmospheric_budget(wavelengths_nm)

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

    def close(self) -> None:
        """Release the prepared O2 A calculation."""

        if self._ctx is not None:
            self._ctx.close()
            self._ctx = None

    def __enter__(self):

        return self

    def __exit__(self, *_exc: object) -> None:

        self.close()


class PreparedDefaultO2A(PreparedO2ABase):
    """Prepared packaged DISAMAR-family O2 A reference case."""

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
    """Prepared user-supplied O2 A case."""

    def __init__(self, input: O2AInput, library_path: LibraryPath = None):

        ctx = Context(library_path)

        try:
            ctx.prepare_o2a(input)
        except Exception:
            ctx.close()
            raise

        super().__init__(ctx, input, library_path)


class O2AForwardSession:
    """Reusable O2 A calculation for retrievals and parameter sweeps."""

    def __init__(self, input: O2AInput | None = None, library_path: LibraryPath = None):

        self._ctx: Context | None = Context(library_path)
        self._input: O2AInput | None = None
        self._library_path = library_path

        if input is not None:
            try:
                self.prepare(input)
                self._require_context().warm_o2a_session()
            except Exception:
                self.close()
                raise

    @property
    def input(self) -> O2AInput:
        """Return the scene currently loaded into the reusable calculation."""

        if self._input is None:
            raise RuntimeError("O2 A session is not prepared")

        return copy.deepcopy(self._input)

    @property
    def library_path(self) -> LibraryPath:

        return self._library_path

    def _require_context(self) -> Context:

        if self._ctx is None:
            raise RuntimeError("O2 A session is closed")

        return self._ctx

    def prepare(self, input: O2AInput) -> O2AForwardSession:
        """Load a new O2 A scene while reusing expensive work arrays."""

        self._require_context().prepare_o2a(input)
        self._input = copy.deepcopy(input)

        return self

    def forward_model(
        self,
        *,
        jacobian: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
    ) -> Spectrum:
        """Evaluate the currently prepared scene without rebuilding work arrays."""

        if self._input is None:
            raise RuntimeError("O2 A session is not prepared")

        return self._require_context().forward_model(
            jacobian=jacobian,
            jacobian_state_names=jacobian_state_names,
        )

    def close(self) -> None:
        """Release the reusable O2 A calculation."""

        if self._ctx is not None:
            self._ctx.close()
            self._ctx = None

        self._input = None

    def __enter__(self) -> O2AForwardSession:

        self._require_context()

        return self

    def __exit__(self, *_exc: object) -> None:

        self.close()


def o2a_disamar_reference_input(
    library_path: LibraryPath = None,
) -> O2AInput:
    """Return the packaged O2 A reference case as editable Python data."""

    with Context(library_path) as ctx:
        return ctx.default_o2a_input()


def prepare(
    input: O2AInput,
    library_path: LibraryPath = None,
) -> PreparedO2A:
    """Prepare a supplied O2 A case for spectra and diagnostics."""

    return PreparedO2A(input, library_path)


def o2a_forward_session(
    input: O2AInput | None = None,
    library_path: LibraryPath = None,
) -> O2AForwardSession:
    """Create a reusable O2 A calculation, optionally with an initial scene."""

    return O2AForwardSession(input, library_path)


def prepare_default_o2a(
    library_path: LibraryPath = None,
) -> PreparedDefaultO2A:
    """Prepare the packaged O2 A reference case."""

    return PreparedDefaultO2A(library_path)


def forward(library_path: LibraryPath = None, *, jacobian: bool = False) -> Spectrum:
    """Run the packaged O2 A reference case in one call."""

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
