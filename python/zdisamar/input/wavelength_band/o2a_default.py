"""Packaged reference scene factory."""

from ..aerosol import Aerosol, AerosolPlacement
from ..assets import ReferenceAsset, ReferenceAssets
from ..atmosphere import Atmosphere, VerticalInterval
from ..geometry import Geometry, Surface
from ..instrument import InstrumentResponse, SpectralGrid
from ..radiative_transfer import (
    RadiativeTransferControls,
    RadiativeTransferPerformanceThresholds,
)
from ..spectroscopy import LineByLine, OxygenCollisionInducedAbsorption
from .o2a import Scene


def reference_asset(id: str, path: str, format: str) -> ReferenceAsset:

    return ReferenceAsset(id=id, path=path, format=format)


def default_o2a_scene() -> Scene:
    """Return the packaged DISAMAR-family reference scene."""

    return Scene(
        metadata={
            "id": "disamar_reference_o2a",
            "storage": "disamar-reference-o2a",
            "description": "DISAMAR O2A reference scene defined in Python.",
        },
        plan={
            "derivative_mode": "none",
        },
        reference_assets=ReferenceAssets(
            atmosphere_profile=reference_asset(
                "atmosphere_profile",
                "data/reference_data/climatologies/vendor_config_o2a_profile.csv",
                "profile_csv",
            ),
            vendor_reference_csv=reference_asset(
                "vendor_reference_csv",
                "data/reference_data/validation/o2a_with_cia_disamar_reference.csv",
                "disamar_o2a_reference_csv",
            ),
            raw_solar_reference=reference_asset(
                "raw_solar_reference",
                "data/reference_data/solar/o2a_solar_reference_753_778.csv",
                "solar_reference_csv",
            ),
            airmass_factor_lut=reference_asset(
                "airmass_factor_lut",
                "data/reference_data/luts/airmass_factor_nadir_demo.csv",
                "csv",
            ),
        ),
        scene_id="o2a_disamar_reference_python",
        spectral_grid=SpectralGrid(start_nm=755.0, end_nm=776.0, sample_count=701),
        atmosphere=Atmosphere(
            layer_count=3,
            sublayer_divisions=4,
            fit_interval_index_1based=2,
            intervals=[
                VerticalInterval(
                    index_1based=1,
                    top_pressure_hpa=0.3,
                    bottom_pressure_hpa=500.0,
                    altitude_divisions=28,
                ),
                VerticalInterval(
                    index_1based=2,
                    top_pressure_hpa=500.0,
                    bottom_pressure_hpa=520.0,
                    altitude_divisions=6,
                ),
                VerticalInterval(
                    index_1based=3,
                    top_pressure_hpa=520.0,
                    bottom_pressure_hpa=1013.25,
                    altitude_divisions=8,
                ),
            ],
        ),
        surface=Surface(albedo=0.2, pressure_hpa=1013.25),
        geometry=Geometry(
            model="pseudo_spherical",
            solar_zenith_deg=60.0,
            viewing_zenith_deg=30.0,
            relative_azimuth_deg=120.0,
        ),
        aerosol=Aerosol(
            optical_depth_550_nm=0.3,
            single_scatter_albedo=1.0,
            asymmetry_factor=0.7,
            angstrom_exponent=0.0,
            reference_wavelength_nm=550.0,
            placement=AerosolPlacement(
                semantics="explicit_interval_bounds",
                interval_index_1based=2,
                top_pressure_hpa=500.0,
                bottom_pressure_hpa=520.0,
            ),
        ),
        instrument_response=InstrumentResponse(
            instrument_name="disamar-o2a-compare",
            regime="nadir",
            sampling="native",
            instrument_line_fwhm_nm=0.38,
            builtin_line_shape="flat_top_n4",
            high_resolution_step_nm=0.01,
            high_resolution_half_span_nm=1.14,
            adaptive_reference_grid={
                "points_per_fwhm": 20,
                "strong_line_min_divisions": 8,
                "strong_line_max_divisions": 40,
            },
            solar_reference_asset_id="raw_solar_reference",
        ),
        o2_lines=LineByLine(
            line_list_asset=reference_asset(
                "o2_hitran",
                "data/reference_data/cross_sections/o2a_hitran_07_hit08_tropomi.par",
                "hitran_par_o2a",
            ),
            line_mixing_asset=reference_asset(
                "o2_line_mixing",
                "data/reference_data/cross_sections/o2a_lisa_rmf.dat",
                "lisa_rmf",
            ),
            strong_lines_asset=reference_asset(
                "o2_strong_lines",
                "data/reference_data/cross_sections/o2a_lisa_sdf.dat",
                "lisa_sdf",
            ),
            line_mixing_factor=1.0,
            isotopes_sim=[1, 2, 3],
            threshold_line_sim=3.0e-5,
            cutoff_sim_cm1=200.0,
        ),
        collision_induced_absorption=OxygenCollisionInducedAbsorption(
            enabled=True,
            cross_section_asset=reference_asset(
                "o2o2_cia",
                "data/reference_data/cross_sections/o2o2_bira_o2a.dat",
                "bira_cia",
            ),
        ),
        radiative_transfer=RadiativeTransferControls(
            scattering="multiple",
            n_streams=20,
            performance_thresholds=RadiativeTransferPerformanceThresholds.o2a_default(),
            use_spherical_correction=True,
            integrate_source_function=True,
            renorm_phase_function=True,
        ),
    )
