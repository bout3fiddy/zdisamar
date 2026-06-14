import os
import tempfile

from zdisamar import rtm
from zdisamar.wavelength_bands import o2a


def main() -> int:

    with tempfile.TemporaryDirectory() as tmpdir:
        old_cwd = os.getcwd()

        try:
            os.chdir(tmpdir)
            scene = o2a.reference_scene()
            assert "vendor/disamar-fortran" not in scene.o2_lines.line_list_asset.path

            spectrum = rtm.spectrum(scene)
            assert len(spectrum.wavelength_nm) == int(scene.spectral_grid.sample_count)

            reference_spectrum = rtm.spectrum(o2a.reference_scene())
            assert len(reference_spectrum.wavelength_nm) == int(scene.spectral_grid.sample_count)

            with rtm.SessionCache(scene) as cache:
                cached_spectrum = cache.spectrum()
                assert len(cached_spectrum.wavelength_nm) == int(scene.spectral_grid.sample_count)
        finally:
            os.chdir(old_cwd)

    print("prepare_external_cwd=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
