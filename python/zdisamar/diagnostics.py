"""Research diagnostic helpers built on the coarse native O2A wrapper."""

from __future__ import annotations

import copy
from dataclasses import dataclass
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
    """O2-O2 collision-induced absorption diagnostics from the native core."""

    def __init__(self, prepared: "PreparedO2A | PreparedDefaultO2A"):
        self._prepared = prepared

    def diagnostics(self, wavelengths_nm):
        return self._prepared.o2_o2_cia_diagnostics(wavelengths_nm)


class InstrumentResponseDiagnostics:
    """Instrument response and high-resolution wavelength sampling diagnostics from the native core."""

    def __init__(self, prepared: "PreparedO2A | PreparedDefaultO2A"):
        self._prepared = prepared

    def sampling_table(
        self,
        wavelengths_nm=None,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ):
        import numpy as np

        case = self._prepared.input
        nominal = _nominal_wavelengths(case) if wavelengths_nm is None else np.asarray(wavelengths_nm, dtype=np.float64)
        return self._prepared.instrument_response_sampling(nominal, channels=channels)


class RadiativeTransferDiagnostics:
    """Bounded layer diagnostics from the native core."""

    def __init__(self, prepared: "PreparedO2A | PreparedDefaultO2A"):
        self._prepared = prepared

    def diagnostics(self, wavelengths_nm, spectrum=None):
        return self._prepared.radiative_transfer_diagnostics(wavelengths_nm, spectrum=spectrum)


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

    def mutate_spectrum_deltas(
        self,
        perturbations: list[tuple[str, Callable[[object], None]]],
    ) -> list[PerturbationResult]:
        baseline_case = self._prepared.input
        baseline = _run_spectrum(baseline_case, self._prepared.library_path)
        results: list[PerturbationResult] = []
        for label, mutate in perturbations:
            perturbed_case = copy.deepcopy(baseline_case)
            mutate(perturbed_case)
            perturbed = _run_spectrum(perturbed_case, self._prepared.library_path)
            results.append(
                _spectrum_delta_from_arrays(
                    baseline,
                    perturbed,
                    label,
                    None,
                    None,
                    label,
                )
            )
        return results


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
