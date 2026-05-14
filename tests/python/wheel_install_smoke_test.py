import argparse
import os
import tempfile
from pathlib import Path


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

            case = o2a.reference_case().with_fast_mode()
            spectrum = rtm.spectrum(case)
            assert int(spectrum.wavelength_nm.size) == int(case.spectral_grid.sample_count)
        finally:
            os.chdir(old_cwd)

    print("wheel_install_smoke=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
