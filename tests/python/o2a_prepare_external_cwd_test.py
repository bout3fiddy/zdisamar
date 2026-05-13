import os
import tempfile

import zdisamar as zd


def main() -> int:

    with tempfile.TemporaryDirectory() as tmpdir:
        os.chdir(tmpdir)
        case = zd.o2a_disamar_reference_input()
        assert "vendor/disamar-fortran" not in case.o2_lines.line_list_asset.path

        with zd.prepare(case) as prepared, prepared.forward_model() as spectrum:
            assert int(spectrum.wavelength_nm.size) == int(case.spectral_grid.sample_count)

        with zd.prepare_default_o2a() as prepared, prepared.forward_model() as spectrum:
            assert int(spectrum.wavelength_nm.size) == int(case.spectral_grid.sample_count)

        with zd.forward() as spectrum:
            assert int(spectrum.wavelength_nm.size) == int(case.spectral_grid.sample_count)

    print("prepare_external_cwd=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
