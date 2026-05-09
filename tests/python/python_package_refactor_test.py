import copy
import importlib.util
import math
import os
import sys
import tempfile
from pathlib import Path


def assert_import_laziness() -> None:
    import zdisamar as zd

    assert "numpy" not in sys.modules
    assert "pandas" not in sys.modules
    assert "altair" not in sys.modules
    assert "inverse_method" not in zd.__all__
    assert "DiagnosticTable" not in zd.__all__
    assert "O2LineDiagnostics" not in zd.__all__
    assert "PerturbationDiagnostics" not in zd.__all__
    assert "RadiativeTransferDiagnosticTable" not in zd.__all__

    import zdisamar.api as api

    assert "O2LineContributions" not in api.__all__
    assert "O2LineDiagnostics" not in api.__all__
    assert "RadiativeTransferDiagnosticTable" not in api.__all__


def assert_plot_package_boundary() -> None:
    assert importlib.util.find_spec("zdisamar.plot") is not None
    assert "zdisamar.plot" not in sys.modules

    from zdisamar.plot.properties import PLOT

    assert PLOT.width == 1311
    assert PLOT.height == 465
    assert PLOT.markers_nm == (755.0, 760.76, 776.0)
    assert "blue" in PLOT.colors


def assert_quantity_conversions() -> None:
    import numpy as np
    from zdisamar.quantities import (
        reflectance_from_radiance,
        reflectance_jacobian_from_radiance_jacobian,
        reflectance_noise_from_sun_normalized_radiance_noise,
        solar_mu0_from_zenith_deg,
        sun_normalized_radiance,
    )

    mu0 = solar_mu0_from_zenith_deg(60.0)
    radiance = np.array([2.0, 3.0], dtype=np.float64)
    irradiance = np.array([10.0, 12.0], dtype=np.float64)
    assert np.allclose(sun_normalized_radiance(radiance, irradiance), radiance / irradiance)
    assert np.allclose(
        reflectance_from_radiance(radiance, irradiance, mu0),
        radiance * math.pi / (mu0 * irradiance),
    )

    radiance_jacobian = np.array([[0.2, 0.4], [0.3, 0.6]], dtype=np.float64)
    expected = radiance_jacobian / ((mu0 * irradiance / math.pi)[:, None])
    assert np.allclose(
        reflectance_jacobian_from_radiance_jacobian(radiance_jacobian, irradiance, mu0),
        expected,
    )
    assert np.allclose(
        reflectance_noise_from_sun_normalized_radiance_noise(np.array([1.0]), mu0),
        np.array([math.pi / mu0]),
    )


def assert_plot_jacobian_uses_shared_conversion() -> None:
    import numpy as np
    from zdisamar.plot.jacobian import jacobian_frame
    from zdisamar.quantities import reflectance_jacobian_from_radiance_jacobian

    class Spectrum:
        jacobian_state_names = ("aerosol_optical_depth",)
        wavelength_nm = np.array([755.0, 760.0], dtype=np.float64)
        irradiance = np.array([10.0, 12.0], dtype=np.float64)
        radiance_jacobian = np.array([[0.2], [0.3]], dtype=np.float64)

        def reflectance_jacobian(self, state: str):
            assert state == "aerosol_optical_depth"
            return reflectance_jacobian_from_radiance_jacobian(
                self.radiance_jacobian[:, 0],
                self.irradiance,
                0.5,
            )

    frame, field, _title = jacobian_frame(Spectrum(), "aerosol_optical_depth")
    assert field == "reflectance_jacobian"
    assert np.allclose(
        frame[field].to_numpy(dtype=float),
        reflectance_jacobian_from_radiance_jacobian(
            Spectrum.radiance_jacobian[:, 0],
            Spectrum.irradiance,
            0.5,
        ),
    )


def assert_reference_data_and_native_table() -> None:
    import numpy as np
    import zdisamar as zd

    with tempfile.TemporaryDirectory() as tmpdir:
        old_cwd = Path.cwd()
        try:
            os.chdir(tmpdir)
            case = zd.o2a_disamar_reference_input()
            assert "vendor/disamar-fortran" not in case.o2_lines.line_list_asset.path
            mutable_case = copy.deepcopy(case)
            with zd.o2a_forward_session() as session:
                session.prepare(mutable_case)
                mutable_case.geometry.solar_zenith_deg = 0.0
                with session.forward_model() as spectrum:
                    assert spectrum.input is not None
                    assert (
                        spectrum.input.geometry.solar_zenith_deg == case.geometry.solar_zenith_deg
                    )
            with (
                zd.prepare(case) as prepared,
                prepared.atmosphere.budget(np.array([760.76], dtype=np.float64)) as budget,
            ):
                assert not hasattr(prepared, "o2_lines")
                assert not hasattr(prepared, "radiative_transfer")
                assert not hasattr(prepared, "perturbations")
                assert budget.row_count > 0
                assert budget.column("wavelength_nm").size == budget.row_count
                first_table = budget.table
                first_wavelength = float(first_table["wavelength_nm"][0])
                first_table["wavelength_nm"][0] = -1.0
                assert float(budget.column("wavelength_nm")[0]) == first_wavelength
                rows = budget.to_rows()
                assert len(rows) == budget.row_count
                assert "support_row_kind_label" in rows[0]
                with prepared.forward_model() as spectrum:
                    output = Path(tmpdir) / "reflectance"
                    chart = spectrum.plot.reflectance(save=output)
                    assert chart is not None
                    assert output.with_suffix(".png").exists()
        finally:
            os.chdir(old_cwd)


def main() -> int:
    assert_import_laziness()
    assert_plot_package_boundary()
    assert_quantity_conversions()
    assert_plot_jacobian_uses_shared_conversion()
    assert_reference_data_and_native_table()
    print("python_package_refactor=ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
