import numpy as np
import pytest
from rtm_scene import narrow
from zdisamar import rtm

pytestmark = pytest.mark.integration


def spectrum_arrays(spectrum) -> dict[str, np.ndarray]:
    return {
        "wavelength_nm": np.asarray(spectrum.wavelength_nm, dtype=np.float64),
        "radiance": np.asarray(spectrum.radiance, dtype=np.float64),
        "irradiance": np.asarray(spectrum.irradiance, dtype=np.float64),
        "reflectance": np.asarray(spectrum.reflectance, dtype=np.float64),
    }


def test_reference_data_resolves_from_external_cwd(tmp_path, monkeypatch) -> None:
    monkeypatch.chdir(tmp_path)

    # Narrow representative band: this test verifies external-cwd asset resolution, route
    # determinism, and finiteness -- all independent of band width.
    scene = narrow()
    assert "vendor/disamar-fortran" not in scene.o2_lines.line_list_asset.path

    spectrum = rtm.spectrum(scene)
    reference_spectrum = rtm.spectrum(narrow())

    assert len(spectrum.wavelength_nm) == int(scene.spectral_grid.sample_count)
    assert len(reference_spectrum.wavelength_nm) == int(scene.spectral_grid.sample_count)
    for field, values in spectrum_arrays(spectrum).items():
        assert np.all(np.isfinite(values))
        assert np.allclose(values, spectrum_arrays(reference_spectrum)[field], atol=0.0, rtol=0.0)

    with rtm.SessionCache(scene) as cache:
        cached_spectrum = cache.spectrum()
        for field, values in spectrum_arrays(cached_spectrum).items():
            assert np.allclose(values, spectrum_arrays(spectrum)[field], atol=0.0, rtol=0.0)
