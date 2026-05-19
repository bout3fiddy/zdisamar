import os
import tempfile

from zdisamar import rtm
from zdisamar.wavelength_bands import o2a


def main() -> int:

    with tempfile.TemporaryDirectory() as tmpdir:
        old_cwd = os.getcwd()

        try:
            os.chdir(tmpdir)
            case = o2a.reference_case()
            assert "vendor/disamar-fortran" not in case.o2_lines.line_list_asset.path

            spectrum = rtm.spectrum(case)
            assert len(spectrum.wavelength_nm) == int(case.spectral_grid.sample_count)

            reference_spectrum = rtm.spectrum(o2a.reference_case())
            assert len(reference_spectrum.wavelength_nm) == int(case.spectral_grid.sample_count)

            with rtm.SessionCache(case) as cache:
                cached_spectrum = cache.spectrum()
                assert len(cached_spectrum.wavelength_nm) == int(case.spectral_grid.sample_count)
        finally:
            os.chdir(old_cwd)

    print("prepare_external_cwd=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
