import argparse
import math
import os
import tempfile
import time
from pathlib import Path

REFERENCE_SPECTRUM_BUDGET_S = 8.0


def parse_args() -> argparse.Namespace:

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--forbid-path",
        type=Path,
        help="Path that must not provide the imported zdisamar package.",
    )

    return parser.parse_args()


def main() -> int:

    args = parse_args()

    with tempfile.TemporaryDirectory() as tmpdir:
        old_cwd = Path.cwd()

        try:
            os.chdir(tmpdir)

            import zdisamar
            from zdisamar import reference_data, rtm
            from zdisamar.bindings.loader import library_filename, load_library
            from zdisamar.wavelength_bands import o2a

            package_file = Path(zdisamar.__file__).resolve()

            if args.forbid_path is not None:
                forbidden = args.forbid_path.resolve()

                if package_file.is_relative_to(forbidden):
                    raise AssertionError(f"zdisamar imported from source tree: {package_file}")

            library = load_library()
            assert Path(library._name).name == library_filename()
            assert reference_data.path("cross_sections/o2o2_bira_o2a.dat").is_file()

            reference_scene = o2a.reference_scene()
            scene_repr = repr(reference_scene)
            assert "Scene(" in scene_repr
            assert "spectral_grid=755-776 nm (701 samples)" in scene_repr
            assert "ReferenceAsset(" not in scene_repr

            # Linux wheel regression: this call crosses Python -> C -> Zig and
            # starts native worker threads. Without libc/pthread linkage in the
            # shared library, Linux can fail here even when the same code works
            # as a standalone Zig executable or on macOS.
            reference_spectrum_start_s = time.perf_counter()
            reference_spectrum = rtm.spectrum(reference_scene)
            reference_spectrum_s = time.perf_counter() - reference_spectrum_start_s
            print(
                f"reference_spectrum_s={reference_spectrum_s:.6f} "
                f"budget_s={REFERENCE_SPECTRUM_BUDGET_S:.1f}",
                flush=True,
            )

            if reference_spectrum_s > REFERENCE_SPECTRUM_BUDGET_S:
                raise AssertionError(
                    "rtm.spectrum(reference_case) exceeded wheel smoke latency budget: "
                    f"{reference_spectrum_s:.3f}s > {REFERENCE_SPECTRUM_BUDGET_S:.1f}s"
                )

            assert len(reference_spectrum.wavelength_nm) == 701
            assert all(math.isfinite(value) for value in reference_spectrum.reflectance)
            assert sum(1 for value in reference_spectrum.reflectance if value != 0.0) == 701
            reflectance_min = min(reference_spectrum.reflectance)
            reflectance_max = max(reference_spectrum.reflectance)
            assert 0.005 < reflectance_min < 0.008
            assert 0.22 < reflectance_max < 0.24
            spectrum_repr = repr(reference_spectrum)
            assert "Spectrum(" in spectrum_repr
            assert "samples=701" in spectrum_repr
            assert "array(" not in spectrum_repr
            assert reference_spectrum.plot.reflectance() is not None

            scene = o2a.reference_scene()
            scene.optimisation.fastmode.enabled = True
            assert int(scene.spectral_grid.sample_count) > 0
            wavelengths = [760.76]
            budget = rtm.atmospheric_budget(scene, wavelengths)
            assert budget.row_count > 0
            assert len(budget.column("wavelength_nm")) == budget.row_count
        finally:
            os.chdir(old_cwd)

    print("wheel_install_smoke=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
