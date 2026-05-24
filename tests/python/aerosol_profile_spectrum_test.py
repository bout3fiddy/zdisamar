"""Smoke coverage for multi-layer aerosol-profile spectra."""

import math

from zdisamar import rtm


def main() -> None:
    case = rtm.o2a_reference_case()
    profile = (
        rtm.AerosolProfileLayer(
            top_pressure_hpa=430.0,
            bottom_pressure_hpa=510.0,
            optical_depth=0.18,
            single_scatter_albedo=0.96,
            asymmetry_factor=0.72,
            angstrom_exponent=0.4,
        ),
        rtm.AerosolProfileLayer(
            top_pressure_hpa=760.0,
            bottom_pressure_hpa=900.0,
            optical_depth=0.24,
            single_scatter_albedo=0.88,
            asymmetry_factor=0.55,
            angstrom_exponent=1.5,
        ),
    )

    with rtm.SessionCache(case) as cache:
        baseline = cache.spectrum()
        profiled = cache.aerosol_profile_spectrum(profile)

    assert len(profiled.wavelength_nm) == len(baseline.wavelength_nm)
    assert len(profiled.reflectance) == len(baseline.reflectance)
    assert all(math.isfinite(value) for value in profiled.reflectance)
    max_delta = max(abs(a - b) for a, b in zip(profiled.reflectance, baseline.reflectance))
    assert max_delta > 1.0e-8

    print("aerosol_profile_spectrum=ok")


if __name__ == "__main__":
    main()
