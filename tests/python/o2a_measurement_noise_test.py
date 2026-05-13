#!/usr/bin/env -S uv run python
"""Check retained O2 A baseline measurement-noise scaling."""

import math
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
PYTHON_ROOT = REPO_ROOT / "python"
sys.path[:0] = [str(REPO_ROOT), str(PYTHON_ROOT)]

from validation.o2a import baseline  # noqa: E402
from validation.o2a.measurement_noise import (  # noqa: E402
    components_from_spectrum,
    instrument_mapped_s5_reference_radiance,
)


def main() -> int:

    wavelength_nm = np.array([758.0, 760.0, 762.0, 770.0], dtype=np.float64)
    reference_radiance = instrument_mapped_s5_reference_radiance(wavelength_nm)
    reflectance = np.full(wavelength_nm.shape, 0.2, dtype=np.float64)
    irradiance = np.full(wavelength_nm.shape, 5.0e14, dtype=np.float64)

    same_signal = components_from_spectrum(
        wavelength_nm=wavelength_nm,
        radiance=reference_radiance,
        irradiance=irradiance,
        reflectance=reflectance,
    )
    oversampled_reference_snr = baseline.RADIANCE_REFERENCE_SNR * math.sqrt(
        baseline.WAVELENGTH_STEP_NM / baseline.RADIANCE_REFERENCE_BIN_WIDTH_NM
    )
    assert math.isclose(
        same_signal.radiance_snr[0],
        oversampled_reference_snr,
        rel_tol=1.0e-12,
    )

    brighter_signal = components_from_spectrum(
        wavelength_nm=wavelength_nm,
        radiance=4.0 * reference_radiance,
        irradiance=irradiance,
        reflectance=reflectance,
    )
    assert math.isclose(
        brighter_signal.radiance_snr[0],
        2.0 * same_signal.radiance_snr[0],
        rel_tol=1.0e-12,
    )
    assert np.all(brighter_signal.reflectance_snr < brighter_signal.radiance_snr)
    assert np.all(brighter_signal.reflectance_noise > 0.0)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
