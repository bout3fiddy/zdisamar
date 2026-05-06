"""Thin plotting helpers bound to a prepared Python wrapper object."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Literal

from . import atmosphere as atmosphere_plots
from . import bundles, fields
from . import collision_induced_absorption as collision_induced_absorption_plots
from . import instrument_response as instrument_response_plots
from . import o2_lines as o2_line_plots
from . import perturbation as perturbation_plots
from . import radiative_transfer as rt_plots
from . import spectrum as spectrum_plots
from . import validation as validation_plots


def for_prepared(prepared):
    return PreparedPlots(prepared)


class PreparedPlots:
    def __init__(self, prepared):
        self._prepared = prepared
        self.spectrum = BoundSpectrumPlots(prepared)
        self.validation = BoundValidationPlots(prepared)
        self.atmosphere = BoundAtmospherePlots(prepared)
        self.o2_lines = BoundO2LinePlots(prepared)
        self.collision_induced_absorption = BoundCollisionInducedAbsorptionPlots(prepared)
        self.instrument_response = BoundInstrumentResponsePlots(prepared)
        self.radiative_transfer = BoundRadiativeTransferPlots(prepared)
        self.perturbation = BoundPerturbationPlots(prepared)


class BoundSpectrumPlots:
    def __init__(self, prepared):
        self._prepared = prepared

    def reflectance(
        self, *, spectrum=None, window_nm=None, markers_nm=(), run_forward: bool = False
    ):
        if spectrum is not None:
            return spectrum_plots.reflectance(spectrum, window_nm=window_nm, markers_nm=markers_nm)
        if not run_forward:
            raise ValueError("pass spectrum=... or set run_forward=True")
        with self._prepared.forward_model() as result:
            return spectrum_plots.reflectance(result, window_nm=window_nm, markers_nm=markers_nm)

    def triplet(
        self,
        *,
        spectrum=None,
        markers_nm=(755.0, 760.76, 776.0),
        run_forward: bool = False,
    ):
        if spectrum is not None:
            return spectrum_plots.triplet(spectrum, markers_nm=markers_nm)
        if not run_forward:
            raise ValueError("pass spectrum=... or set run_forward=True")
        with self._prepared.forward_model() as result:
            return spectrum_plots.triplet(result, markers_nm=markers_nm)


class BoundValidationPlots:
    def __init__(self, prepared):
        self._prepared = prepared

    def reflectance_residual_report(
        self,
        reference,
        *,
        spectrum=None,
        residual_threshold: float = 1.0e-14,
        run_forward: bool = False,
    ):
        if spectrum is not None:
            return validation_plots.residual_histogram_report(
                spectrum,
                reference,
                quantity=fields.REFLECTANCE,
                residual_threshold=residual_threshold,
            )
        if not run_forward:
            raise ValueError("pass spectrum=... or set run_forward=True")
        with self._prepared.forward_model() as result:
            return validation_plots.residual_histogram_report(
                result,
                reference,
                quantity=fields.REFLECTANCE,
                residual_threshold=residual_threshold,
            )


class BoundAtmospherePlots:
    def __init__(self, prepared):
        self._prepared = prepared

    def optical_depth_heatmap(
        self,
        *,
        wavelengths_nm: Sequence[float],
        quantity: str = fields.TOTAL_OPTICAL_DEPTH,
        vertical_axis: Literal["altitude_km", "pressure_hpa"] = "altitude_km",
    ):
        with self._prepared.atmosphere.budget(wavelengths_nm=wavelengths_nm) as budget:
            return atmosphere_plots.optical_depth_heatmap(
                budget,
                quantity=quantity,
                vertical_axis=vertical_axis,
                markers_nm=wavelengths_nm,
            )

    def budget(self, *, wavelengths_nm: Sequence[float] = (755.0, 760.76, 776.0)):
        with self._prepared.atmosphere.budget(wavelengths_nm=wavelengths_nm) as budget:
            return bundles.atmospheric_budget(budget, markers_nm=wavelengths_nm)


class BoundO2LinePlots:
    def __init__(self, prepared):
        self._prepared = prepared

    def window(
        self,
        *,
        spectrum=None,
        wavelengths_nm: Sequence[float] = (760.76,),
        center_nm: float = 760.76,
        max_rows: int = 100_000,
        top_n: int = 40,
        run_forward: bool = False,
    ):
        with self._prepared.o2_lines.contributions(
            wavelengths_nm=wavelengths_nm, max_rows=max_rows
        ) as lines:
            if spectrum is not None:
                return o2_line_plots.window(spectrum, lines, center_nm=center_nm, top_n=top_n)
            if not run_forward:
                raise ValueError("pass spectrum=... or set run_forward=True")
            with self._prepared.forward_model() as result:
                return o2_line_plots.window(result, lines, center_nm=center_nm, top_n=top_n)


class BoundCollisionInducedAbsorptionPlots:
    def __init__(self, prepared):
        self._prepared = prepared

    def budget(self, *, wavelengths_nm: Sequence[float] = (755.0, 760.76, 776.0)):
        with self._prepared.collision_induced_absorption.diagnostics(
            wavelengths_nm=wavelengths_nm
        ) as diagnostics:
            return bundles.collision_induced_absorption_budget(
                diagnostics, wavelengths_nm=wavelengths_nm
            )

    def share_spectrum(self, *, wavelengths_nm: Sequence[float] = (755.0, 760.76, 776.0)):
        with self._prepared.collision_induced_absorption.diagnostics(
            wavelengths_nm=wavelengths_nm
        ) as diagnostics:
            return collision_induced_absorption_plots.share_spectrum(diagnostics)


class BoundInstrumentResponsePlots:
    def __init__(self, prepared):
        self._prepared = prepared

    def isrf(
        self,
        *,
        wavelengths_nm: Sequence[float] = (760.76,),
        channel: Literal["radiance", "irradiance"] = "radiance",
    ):
        with self._prepared.instrument_response.sampling_table(
            wavelengths_nm=wavelengths_nm, channels=(channel,)
        ) as table:
            return instrument_response_plots.isrf(
                table, nominal_wavelength_nm=wavelengths_nm[0], channel=channel
            )

    def budget(self, *, wavelengths_nm: Sequence[float] = (760.76,)):
        with self._prepared.instrument_response.sampling_table(
            wavelengths_nm=wavelengths_nm
        ) as table:
            return bundles.instrument_response(table, nominal_wavelength_nm=wavelengths_nm[0])


class BoundRadiativeTransferPlots:
    def __init__(self, prepared):
        self._prepared = prepared

    def budget(
        self,
        *,
        wavelengths_nm: Sequence[float] = (755.0, 760.76, 776.0),
        spectrum=None,
        run_forward: bool = False,
    ):
        if spectrum is not None:
            with self._prepared.radiative_transfer.diagnostics(
                wavelengths_nm=wavelengths_nm, spectrum=spectrum
            ) as table:
                return bundles.radiative_transfer_budget(table, wavelengths_nm=wavelengths_nm)
        if not run_forward:
            raise ValueError("pass spectrum=... or set run_forward=True")
        with (
            self._prepared.forward_model() as result,
            self._prepared.radiative_transfer.diagnostics(
                wavelengths_nm=wavelengths_nm, spectrum=result
            ) as table,
        ):
            return bundles.radiative_transfer_budget(table, wavelengths_nm=wavelengths_nm)

    def source_profile(self, *, wavelengths_nm: Sequence[float] = (755.0, 760.76, 776.0)):
        with self._prepared.radiative_transfer.diagnostics(wavelengths_nm=wavelengths_nm) as table:
            return rt_plots.source_profile(table)


class BoundPerturbationPlots:
    def __init__(self, prepared):
        self._prepared = prepared

    def delta_reflectance(self, parameter_path: str, value, *, label: str | None = None):
        result = self._prepared.perturbations.spectrum_delta(parameter_path, value, label=label)
        return perturbation_plots.delta_reflectance(result)
