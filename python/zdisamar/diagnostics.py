"""Research diagnostic helpers built on the coarse native O2A wrapper."""

from __future__ import annotations

import copy
from dataclasses import dataclass
import math
from typing import TYPE_CHECKING, Callable

if TYPE_CHECKING:
    from .ffi import PreparedDefaultO2A, PreparedO2A


class DiagnosticTable:
    """Small owned table wrapper for Python-built diagnostic arrays."""

    def __init__(self, table, metadata: dict[str, object] | None = None):
        self._table = table
        self.metadata = {} if metadata is None else dict(metadata)

    @property
    def table(self):
        return self._table

    @property
    def row_count(self) -> int:
        return int(self._table.size)

    @property
    def columns(self) -> tuple[str, ...]:
        return tuple(self._table.dtype.names or ())

    def column(self, name: str):
        if name not in self.columns:
            raise KeyError(name)
        return self._table[name]

    def to_rows(self) -> list[dict[str, float | int]]:
        return [{name: row[name].item() for name in self.columns} for row in self._table]

    def to_pandas(self):
        import pandas as pd

        return pd.DataFrame.from_records(self.to_rows())

    def close(self) -> None:
        return None

    def __enter__(self) -> "DiagnosticTable":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


@dataclass(frozen=True)
class PerturbationSummary:
    label: str
    parameter_path: str
    baseline_value: object
    perturbed_value: object
    max_abs_delta_reflectance: float
    max_abs_delta_wavelength_nm: float
    mean_abs_delta_reflectance: float


class PerturbationResult(DiagnosticTable):
    def __init__(
        self,
        table,
        summary: PerturbationSummary,
        metadata: dict[str, object] | None = None,
    ):
        super().__init__(table, metadata)
        self.summary = summary


class O2O2CIADiagnostics:
    """O2-O2 collision-induced absorption diagnostics from native budget rows."""

    def __init__(self, prepared: "PreparedO2A | PreparedDefaultO2A"):
        self._prepared = prepared

    def diagnostics(self, wavelengths_nm) -> DiagnosticTable:
        import numpy as np

        with self._prepared.atmosphere.budget(wavelengths_nm=wavelengths_nm) as budget:
            budget_table = budget.table.copy()

        dtype = [
            ("wavelength_nm", "f8"),
            ("layer_index", "u4"),
            ("sublayer_index", "u4"),
            ("global_sublayer_index", "u4"),
            ("interval_index_1based", "u4"),
            ("altitude_km", "f8"),
            ("pressure_hpa", "f8"),
            ("temperature_k", "f8"),
            ("oxygen_number_density_cm3", "f8"),
            ("path_length_cm", "f8"),
            ("cia_cross_section_cm5_per_molecule2", "f8"),
            ("cia_optical_depth", "f8"),
            ("total_absorption_optical_depth", "f8"),
            ("total_optical_depth", "f8"),
            ("cia_share_of_total_absorption", "f8"),
            ("cia_share_of_total_optical_depth", "f8"),
        ]
        table = np.empty(budget_table.size, dtype=dtype)
        for name in (
            "wavelength_nm",
            "layer_index",
            "sublayer_index",
            "global_sublayer_index",
            "interval_index_1based",
            "altitude_km",
            "pressure_hpa",
            "temperature_k",
            "oxygen_number_density_cm3",
            "path_length_cm",
            "cia_optical_depth",
            "total_absorption_optical_depth",
            "total_optical_depth",
        ):
            table[name] = budget_table[name]

        pair_path = np.square(table["oxygen_number_density_cm3"]) * table["path_length_cm"]
        table["cia_cross_section_cm5_per_molecule2"] = np.divide(
            table["cia_optical_depth"],
            pair_path,
            out=np.zeros_like(table["cia_optical_depth"]),
            where=pair_path > 0.0,
        )
        table["cia_share_of_total_absorption"] = np.divide(
            table["cia_optical_depth"],
            table["total_absorption_optical_depth"],
            out=np.zeros_like(table["cia_optical_depth"]),
            where=table["total_absorption_optical_depth"] > 0.0,
        )
        table["cia_share_of_total_optical_depth"] = np.divide(
            table["cia_optical_depth"],
            table["total_optical_depth"],
            out=np.zeros_like(table["cia_optical_depth"]),
            where=table["total_optical_depth"] > 0.0,
        )
        return DiagnosticTable(table, {"source": "atmospheric_budget"})


class InstrumentResponseDiagnostics:
    """Instrument response and high-resolution wavelength sampling diagnostics."""

    def __init__(self, prepared: "PreparedO2A | PreparedDefaultO2A"):
        self._prepared = prepared

    def sampling_table(
        self,
        wavelengths_nm=None,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ) -> DiagnosticTable:
        import numpy as np

        case = self._prepared.input
        nominal = _nominal_wavelengths(case) if wavelengths_nm is None else np.asarray(wavelengths_nm, dtype=np.float64)
        offsets, weights, raw_weights = _instrument_kernel(case)
        channel_codes = {"radiance": 0, "irradiance": 1}
        dtype = [
            ("nominal_index", "i4"),
            ("nominal_wavelength_nm", "f8"),
            ("channel", "u1"),
            ("sample_index", "u4"),
            ("support_count", "u4"),
            ("offset_nm", "f8"),
            ("support_wavelength_nm", "f8"),
            ("weight", "f8"),
            ("raw_response_weight", "f8"),
            ("support_width_nm", "f8"),
            ("instrument_fwhm_nm", "f8"),
            ("high_resolution_step_nm", "f8"),
            ("high_resolution_half_span_nm", "f8"),
            ("adaptive_points_per_fwhm", "u4"),
            ("adaptive_strong_line_min_divisions", "u4"),
            ("adaptive_strong_line_max_divisions", "u4"),
        ]
        rows = np.empty(nominal.size * len(channels) * offsets.size, dtype=dtype)
        grid = _nominal_wavelengths(case)
        adaptive = case.instrument_response.adaptive_reference_grid
        support_width = float(offsets[-1] - offsets[0]) if offsets.size else 0.0
        row_index = 0
        for nominal_wavelength in nominal:
            nominal_index = int(np.argmin(np.abs(grid - nominal_wavelength))) if grid.size else -1
            for channel in channels:
                channel_code = channel_codes[channel]
                for sample_index, (offset, weight, raw_weight) in enumerate(
                    zip(offsets, weights, raw_weights, strict=True)
                ):
                    rows[row_index] = (
                        nominal_index,
                        float(nominal_wavelength),
                        channel_code,
                        sample_index,
                        offsets.size,
                        float(offset),
                        float(nominal_wavelength + offset),
                        float(weight),
                        float(raw_weight),
                        support_width,
                        case.instrument_response.instrument_line_fwhm_nm,
                        case.instrument_response.high_resolution_step_nm,
                        case.instrument_response.high_resolution_half_span_nm,
                        int(adaptive.get("points_per_fwhm", 0)),
                        int(adaptive.get("strong_line_min_divisions", 0)),
                        int(adaptive.get("strong_line_max_divisions", 0)),
                    )
                    row_index += 1
        return DiagnosticTable(rows, {"channel_labels": channel_codes})


class RadiativeTransferDiagnostics:
    """Bounded layer diagnostics for the radiative-transfer setup."""

    def __init__(self, prepared: "PreparedO2A | PreparedDefaultO2A"):
        self._prepared = prepared

    def diagnostics(self, wavelengths_nm, spectrum=None) -> DiagnosticTable:
        import numpy as np

        with self._prepared.atmosphere.budget(wavelengths_nm=wavelengths_nm) as budget:
            budget_table = budget.table.copy()

        case = self._prepared.input
        airmass = _airmass_factor(case)
        final_reflectance = _interpolated_spectrum_column(spectrum, "reflectance", budget_table["wavelength_nm"])
        final_radiance = _interpolated_spectrum_column(spectrum, "radiance", budget_table["wavelength_nm"])
        dtype = [
            ("wavelength_nm", "f8"),
            ("layer_index", "u4"),
            ("sublayer_index", "u4"),
            ("global_sublayer_index", "u4"),
            ("interval_index_1based", "u4"),
            ("altitude_km", "f8"),
            ("total_optical_depth", "f8"),
            ("total_absorption_optical_depth", "f8"),
            ("total_scattering_optical_depth", "f8"),
            ("single_scatter_albedo", "f8"),
            ("cumulative_optical_depth_above", "f8"),
            ("mid_layer_transmission_proxy", "f8"),
            ("direct_surface_transmission_proxy", "f8"),
            ("atmospheric_scattering_source_proxy", "f8"),
            ("absorption_loss_proxy", "f8"),
            ("pseudo_spherical_airmass_factor", "f8"),
            ("n_streams", "u4"),
            ("integrate_source_function", "u1"),
            ("final_reflectance", "f8"),
            ("final_radiance", "f8"),
        ]
        table = np.empty(budget_table.size, dtype=dtype)
        for name in (
            "wavelength_nm",
            "layer_index",
            "sublayer_index",
            "global_sublayer_index",
            "interval_index_1based",
            "altitude_km",
            "total_optical_depth",
            "total_absorption_optical_depth",
            "total_scattering_optical_depth",
            "single_scatter_albedo",
        ):
            table[name] = budget_table[name]
        table["pseudo_spherical_airmass_factor"] = airmass
        table["n_streams"] = case.radiative_transfer.n_streams
        table["integrate_source_function"] = 1 if case.radiative_transfer.integrate_source_function else 0
        table["final_reflectance"] = final_reflectance
        table["final_radiance"] = final_radiance

        for wavelength in np.unique(table["wavelength_nm"]):
            indexes = np.flatnonzero(table["wavelength_nm"] == wavelength)
            cumulative = 0.0
            for index in indexes:
                optical_depth = float(table["total_optical_depth"][index])
                mid_depth = cumulative + 0.5 * optical_depth
                transmission = math.exp(-airmass * max(mid_depth, 0.0))
                table["cumulative_optical_depth_above"][index] = cumulative
                table["mid_layer_transmission_proxy"][index] = transmission
                table["direct_surface_transmission_proxy"][index] = math.exp(
                    -airmass * max(cumulative + optical_depth, 0.0)
                )
                table["atmospheric_scattering_source_proxy"][index] = (
                    table["total_scattering_optical_depth"][index] * transmission
                )
                table["absorption_loss_proxy"][index] = table["total_absorption_optical_depth"][index] * transmission
                cumulative += optical_depth

        return DiagnosticTable(table, {"source": "atmospheric_budget", "proxy_terms": True})


class PerturbationDiagnostics:
    """Coarse forward-model perturbation helper."""

    def __init__(self, prepared: "PreparedO2A | PreparedDefaultO2A"):
        self._prepared = prepared

    def spectrum_delta(
        self,
        parameter_path: str,
        value,
        label: str | None = None,
    ) -> PerturbationResult:
        baseline_case = self._prepared.input
        perturbed_case = copy.deepcopy(baseline_case)
        baseline_value = _get_path(perturbed_case, parameter_path)
        _set_path(perturbed_case, parameter_path, value)
        return _spectrum_delta(
            baseline_case,
            perturbed_case,
            self._prepared.library_path,
            parameter_path,
            baseline_value,
            value,
            label or f"{parameter_path}={value}",
        )

    def spectrum_deltas(self, perturbations: list[dict[str, object]]) -> list[PerturbationResult]:
        baseline_case = self._prepared.input
        baseline = _run_spectrum(baseline_case, self._prepared.library_path)
        results: list[PerturbationResult] = []
        for perturbation in perturbations:
            parameter_path = str(perturbation["parameter_path"])
            value = perturbation["value"]
            label = str(perturbation.get("label", f"{parameter_path}={value}"))
            perturbed_case = copy.deepcopy(baseline_case)
            baseline_value = _get_path(perturbed_case, parameter_path)
            _set_path(perturbed_case, parameter_path, value)
            perturbed = _run_spectrum(perturbed_case, self._prepared.library_path)
            results.append(
                _spectrum_delta_from_arrays(
                    baseline,
                    perturbed,
                    parameter_path,
                    baseline_value,
                    value,
                    label,
                )
            )
        return results

    def relative_spectrum_delta(
        self,
        parameter_path: str,
        factor: float,
        label: str | None = None,
    ) -> PerturbationResult:
        baseline_case = self._prepared.input
        baseline_value = _get_path(baseline_case, parameter_path)
        return self.spectrum_delta(
            parameter_path,
            baseline_value * factor,
            label or f"{parameter_path}x{factor:g}",
        )

    def mutate_spectrum_delta(
        self,
        label: str,
        mutate: Callable[[object], None],
    ) -> PerturbationResult:
        baseline_case = self._prepared.input
        perturbed_case = copy.deepcopy(baseline_case)
        mutate(perturbed_case)
        return _spectrum_delta(
            baseline_case,
            perturbed_case,
            self._prepared.library_path,
            label,
            None,
            None,
            label,
        )


def _spectrum_delta(
    baseline_case,
    perturbed_case,
    library_path,
    parameter_path: str,
    baseline_value,
    perturbed_value,
    label: str,
) -> PerturbationResult:
    baseline = _run_spectrum(baseline_case, library_path)
    perturbed = _run_spectrum(perturbed_case, library_path)
    return _spectrum_delta_from_arrays(
        baseline,
        perturbed,
        parameter_path,
        baseline_value,
        perturbed_value,
        label,
    )


def _spectrum_delta_from_arrays(
    baseline,
    perturbed,
    parameter_path: str,
    baseline_value,
    perturbed_value,
    label: str,
) -> PerturbationResult:
    import numpy as np

    if not np.array_equal(baseline["wavelength_nm"], perturbed["wavelength_nm"]):
        perturbed_reflectance = np.interp(
            baseline["wavelength_nm"],
            perturbed["wavelength_nm"],
            perturbed["reflectance"],
        )
        perturbed_radiance = np.interp(
            baseline["wavelength_nm"],
            perturbed["wavelength_nm"],
            perturbed["radiance"],
        )
    else:
        perturbed_reflectance = perturbed["reflectance"]
        perturbed_radiance = perturbed["radiance"]

    delta_reflectance = perturbed_reflectance - baseline["reflectance"]
    abs_delta = np.abs(delta_reflectance)
    max_index = int(np.argmax(abs_delta))
    dtype = [
        ("wavelength_nm", "f8"),
        ("baseline_reflectance", "f8"),
        ("perturbed_reflectance", "f8"),
        ("delta_reflectance", "f8"),
        ("abs_delta_reflectance", "f8"),
        ("baseline_radiance", "f8"),
        ("perturbed_radiance", "f8"),
    ]
    table = np.empty(baseline["wavelength_nm"].size, dtype=dtype)
    table["wavelength_nm"] = baseline["wavelength_nm"]
    table["baseline_reflectance"] = baseline["reflectance"]
    table["perturbed_reflectance"] = perturbed_reflectance
    table["delta_reflectance"] = delta_reflectance
    table["abs_delta_reflectance"] = abs_delta
    table["baseline_radiance"] = baseline["radiance"]
    table["perturbed_radiance"] = perturbed_radiance
    summary = PerturbationSummary(
        label=label,
        parameter_path=parameter_path,
        baseline_value=baseline_value,
        perturbed_value=perturbed_value,
        max_abs_delta_reflectance=float(abs_delta[max_index]),
        max_abs_delta_wavelength_nm=float(table["wavelength_nm"][max_index]),
        mean_abs_delta_reflectance=float(np.mean(abs_delta)),
    )
    return PerturbationResult(table, summary)


def _run_spectrum(case, library_path) -> dict[str, object]:
    from .ffi import prepare

    with prepare(case, library_path=library_path) as prepared:
        with prepared.forward_model() as spectrum:
            return {
                "wavelength_nm": spectrum.wavelength_nm.copy(),
                "radiance": spectrum.radiance.copy(),
                "reflectance": spectrum.reflectance.copy(),
            }


def _nominal_wavelengths(case):
    import numpy as np

    return np.linspace(
        case.spectral_grid.start_nm,
        case.spectral_grid.end_nm,
        case.spectral_grid.sample_count,
        dtype=np.float64,
    )


def _instrument_kernel(case):
    import numpy as np

    response = case.instrument_response
    step_nm = response.high_resolution_step_nm
    half_span_nm = response.high_resolution_half_span_nm
    if step_nm <= 0.0 or half_span_nm <= 0.0:
        half_span_nm = max(3.0 * max(response.instrument_line_fwhm_nm, 1.0e-4), 1.0e-4)
        offsets = np.array([-half_span_nm, -0.5 * half_span_nm, 0.0, 0.5 * half_span_nm, half_span_nm])
    else:
        values = []
        offset = -half_span_nm
        while offset <= half_span_nm + (step_nm * 0.5):
            values.append(offset)
            offset += step_nm
        offsets = np.array(values, dtype=np.float64)
    raw_weights = np.array(
        [_response_weight(response.builtin_line_shape, response.instrument_line_fwhm_nm, offset) for offset in offsets],
        dtype=np.float64,
    )
    weight_sum = float(np.sum(raw_weights))
    weights = np.ones_like(raw_weights) / raw_weights.size if weight_sum <= 0.0 else raw_weights / weight_sum
    return offsets, weights, raw_weights


def _response_weight(shape: str, fwhm_nm: float, offset_nm: float) -> float:
    safe_fwhm = max(fwhm_nm, 1.0e-4)
    if shape == "gaussian":
        sigma = safe_fwhm / 2.354820045
        return math.exp(-0.5 * (offset_nm / sigma) ** 2.0)
    if shape == "flat_top_n4":
        return _flat_top_n4_weight(safe_fwhm, offset_nm)
    if shape == "triple_flat_top_n4":
        return (
            _flat_top_n4_weight(safe_fwhm, offset_nm)
            + _flat_top_n4_weight(safe_fwhm, offset_nm - 0.1)
            + _flat_top_n4_weight(safe_fwhm, offset_nm + 0.1)
        )
    raise ValueError(f"unsupported builtin line shape: {shape}")


def _flat_top_n4_weight(fwhm_nm: float, offset_nm: float) -> float:
    width_nm = fwhm_nm / 1.681793
    return 2.0 ** (-2.0 * (offset_nm / max(width_nm, 1.0e-6)) ** 4.0)


def _airmass_factor(case) -> float:
    solar_mu = math.cos(math.radians(case.geometry.solar_zenith_deg))
    viewing_mu = math.cos(math.radians(case.geometry.viewing_zenith_deg))
    return (1.0 / max(solar_mu, 1.0e-6)) + (1.0 / max(viewing_mu, 1.0e-6))


def _interpolated_spectrum_column(spectrum, column: str, wavelengths_nm):
    import numpy as np

    if spectrum is None:
        return np.full_like(wavelengths_nm, np.nan, dtype=np.float64)
    source_wavelengths = spectrum.wavelength_nm
    source_values = getattr(spectrum, column)
    return np.interp(wavelengths_nm, source_wavelengths, source_values)


def _get_path(obj, path: str):
    current = obj
    for part in path.split("."):
        current = current[part] if isinstance(current, dict) else getattr(current, part)
    return current


def _set_path(obj, path: str, value) -> None:
    parts = path.split(".")
    current = obj
    for part in parts[:-1]:
        current = current[part] if isinstance(current, dict) else getattr(current, part)
    final = parts[-1]
    if isinstance(current, dict):
        current[final] = value
    else:
        setattr(current, final, value)
