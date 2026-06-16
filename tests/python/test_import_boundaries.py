import math
import os
import subprocess
import sys
from pathlib import Path


def test_import_laziness() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    python_root = repo_root / "python"
    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join(
        [str(repo_root), str(python_root), env.get("PYTHONPATH", "")]
    )
    script = """
import sys

import zdisamar as zd

assert "numpy" not in sys.modules
assert "pandas" not in sys.modules
assert "altair" not in sys.modules
assert zd.__all__ == ["reference_data", "rtm", "optimal_estimation", "wavelength_bands"]
assert not hasattr(zd, "prepare")
assert not hasattr(zd, "forward")
assert not hasattr(zd, "Scene")

import zdisamar.api as api

assert api.__all__ == ["reference_data", "rtm", "optimal_estimation", "wavelength_bands"]

from zdisamar import optimal_estimation

assert optimal_estimation.Measurement.__name__ == "Measurement"
"""

    subprocess.run([sys.executable, "-c", script], check=True, env=env)


def test_plot_package_boundary() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    python_root = repo_root / "python"
    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join(
        [str(repo_root), str(python_root), env.get("PYTHONPATH", "")]
    )
    script = """
import importlib.util
import sys

assert importlib.util.find_spec("zdisamar.plot") is not None
assert "zdisamar.plot" not in sys.modules

from zdisamar.plot.properties import PLOT

assert PLOT.width == 1311
assert PLOT.height == 465
assert PLOT.markers_nm == (755.0, 760.76, 776.0)
assert "blue" in PLOT.colors
"""

    subprocess.run([sys.executable, "-c", script], check=True, env=env)


def test_rtm_conversions() -> None:

    import numpy as np
    from zdisamar import rtm

    mu0 = rtm.solar_zenith_cosine_from_degrees(60.0)
    radiance = np.array([2.0, 3.0], dtype=np.float64)
    irradiance = np.array([10.0, 12.0], dtype=np.float64)
    assert np.allclose(rtm.sun_normalized_radiance(radiance, irradiance), radiance / irradiance)
    assert np.allclose(
        rtm.reflectance_from_radiance(radiance, irradiance, mu0),
        radiance * math.pi / (mu0 * irradiance),
    )

    radiance_jacobian = np.array([[0.2, 0.4], [0.3, 0.6]], dtype=np.float64)
    expected = radiance_jacobian / ((mu0 * irradiance / math.pi)[:, None])
    assert np.allclose(
        rtm.reflectance_jacobian_from_radiance_jacobian(
            radiance_jacobian,
            irradiance,
            mu0,
        ),
        expected,
    )
    assert np.allclose(
        rtm.reflectance_noise_from_sun_normalized_radiance_noise(np.array([1.0]), mu0),
        np.array([math.pi / mu0]),
    )


def test_plot_jacobian_uses_rtm_conversion() -> None:

    import numpy as np
    from zdisamar import rtm
    from zdisamar.plot.jacobian import jacobian_frame

    class Spectrum:
        jacobian_state_names = ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")
        wavelength_nm = np.array([755.0, 760.0], dtype=np.float64)
        irradiance = np.array([10.0, 12.0], dtype=np.float64)
        radiance_jacobian = np.array([[0.2, 0.02], [0.3, 0.03]], dtype=np.float64)

        def reflectance_jacobian(self, state: str):

            assert state == "aerosol_optical_depth"

            return rtm.reflectance_jacobian_from_radiance_jacobian(
                self.radiance_jacobian[:, 0],
                self.irradiance,
                0.5,
            )

    frame, field, _title = jacobian_frame(Spectrum(), "aerosol_optical_depth")
    assert field == "reflectance_jacobian"
    assert np.allclose(
        np.array([row[field] for row in frame], dtype=float),
        rtm.reflectance_jacobian_from_radiance_jacobian(
            Spectrum.radiance_jacobian[:, 0],
            Spectrum.irradiance,
            0.5,
        ),
    )
