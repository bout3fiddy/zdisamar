"""Canonical O2 A validation scene construction."""

O2A_REFERENCE_CSV = "data/reference_data/validation/o2a_with_cia_disamar_reference.csv"


def asset(band, id: str, path: str, format: str):

    return band.ReferenceAsset(id=id, path=path, format=format)


def build_o2a_case(band, *, jacobian_reference_layer: bool = False):

    aerosol_top_pressure_hpa = 875.0 if jacobian_reference_layer else 500.0
    aerosol_bottom_pressure_hpa = 925.0 if jacobian_reference_layer else 520.0
    viewing_zenith_deg = 0.0 if jacobian_reference_layer else 30.0
    relative_azimuth_deg = 0.0 if jacobian_reference_layer else 120.0
    aerosol_interval_divisions = 2 if jacobian_reference_layer else 6
    lower_interval_divisions = 4 if jacobian_reference_layer else 8
    performance_thresholds = band.RadiativeTransferPerformanceThresholds.o2a_default()

    if jacobian_reference_layer:
        performance_thresholds.phase_function_truncation_threshold = 1.0e-6

    return band.O2ACase(
        metadata={
            "id": "disamar_reference_o2a",
            "storage": "disamar-reference-o2a",
            "description": "DISAMAR O2 A reference case defined in Python.",
        },
        plan={
            "derivative_mode": "none",
        },
        reference_assets=band.ReferenceAssets(
            atmosphere_profile=asset(
                band,
                "atmosphere_profile",
                "data/reference_data/climatologies/vendor_config_o2a_profile.csv",
                "profile_csv",
            ),
            vendor_reference_csv=asset(
                band,
                "vendor_reference_csv",
                O2A_REFERENCE_CSV,
                "disamar_o2a_reference_csv",
            ),
            raw_solar_reference=asset(
                band,
                "raw_solar_reference",
                "data/reference_data/solar/o2a_solar_reference_753_778.csv",
                "solar_reference_csv",
            ),
            airmass_factor_lut=asset(
                band,
                "airmass_factor_lut",
                "data/reference_data/luts/airmass_factor_nadir_demo.csv",
                "csv",
            ),
        ),
        scene_id="o2a_disamar_reference_python",
        spectral_grid=band.SpectralGrid(start_nm=755.0, end_nm=776.0, sample_count=701),
        atmosphere=band.Atmosphere(
            layer_count=3,
            sublayer_divisions=4,
            fit_interval_index_1based=2,
            intervals=[
                band.VerticalInterval(
                    index_1based=1,
                    top_pressure_hpa=0.3,
                    bottom_pressure_hpa=aerosol_top_pressure_hpa,
                    altitude_divisions=28,
                ),
                band.VerticalInterval(
                    index_1based=2,
                    top_pressure_hpa=aerosol_top_pressure_hpa,
                    bottom_pressure_hpa=aerosol_bottom_pressure_hpa,
                    altitude_divisions=aerosol_interval_divisions,
                ),
                band.VerticalInterval(
                    index_1based=3,
                    top_pressure_hpa=aerosol_bottom_pressure_hpa,
                    bottom_pressure_hpa=1013.25,
                    altitude_divisions=lower_interval_divisions,
                ),
            ],
        ),
        surface=band.Surface(albedo=0.2, pressure_hpa=1013.25),
        geometry=band.Geometry(
            model="pseudo_spherical",
            solar_zenith_deg=60.0,
            viewing_zenith_deg=viewing_zenith_deg,
            relative_azimuth_deg=relative_azimuth_deg,
        ),
        aerosol=band.Aerosol(
            optical_depth_550_nm=0.3,
            single_scatter_albedo=1.0,
            asymmetry_factor=0.7,
            angstrom_exponent=0.0,
            reference_wavelength_nm=550.0,
            placement=band.AerosolPlacement(
                semantics="explicit_interval_bounds",
                interval_index_1based=2,
                top_pressure_hpa=aerosol_top_pressure_hpa,
                bottom_pressure_hpa=aerosol_bottom_pressure_hpa,
            ),
        ),
        instrument_response=band.InstrumentResponse(
            instrument_name="disamar-o2a-compare",
            regime="nadir",
            sampling="native",
            instrument_line_fwhm_nm=0.38,
            builtin_line_shape="flat_top_n4",
            high_resolution_step_nm=0.01,
            high_resolution_half_span_nm=1.14,
            adaptive_reference_grid={
                "points_per_fwhm": 12 if jacobian_reference_layer else 20,
                "strong_line_min_divisions": 8,
                "strong_line_max_divisions": 30 if jacobian_reference_layer else 40,
            },
            solar_reference_asset_id="raw_solar_reference",
        ),
        o2_lines=band.O2LineByLine(
            line_list_asset=asset(
                band,
                "o2_hitran",
                "data/reference_data/cross_sections/o2a_hitran_07_hit08_tropomi.par",
                "hitran_par_o2a",
            ),
            line_mixing_asset=asset(
                band,
                "o2_line_mixing",
                "data/reference_data/cross_sections/o2a_lisa_rmf.dat",
                "lisa_rmf",
            ),
            strong_lines_asset=asset(
                band,
                "o2_strong_lines",
                "data/reference_data/cross_sections/o2a_lisa_sdf.dat",
                "lisa_sdf",
            ),
            line_mixing_factor=1.0,
            isotopes_sim=[1, 2, 3],
            threshold_line_sim=3.0e-5,
            cutoff_sim_cm1=200.0,
        ),
        collision_induced_absorption=band.OxygenCollisionInducedAbsorption(
            enabled=True,
            cross_section_asset=asset(
                band,
                "o2o2_cia",
                "data/reference_data/cross_sections/o2o2_bira_o2a.dat",
                "bira_cia",
            ),
        ),
        radiative_transfer=band.RadiativeTransferControls(
            scattering="multiple",
            n_streams=20,
            performance_thresholds=performance_thresholds,
            use_spherical_correction=True,
            integrate_source_function=True,
            renorm_phase_function=True,
        ),
        outputs=[],
        validation={
            "strict_unknown_fields": True,
            "require_resolved_assets": True,
            "require_resolved_stage_references": True,
        },
    )


def build_o2a_jacobian_case(band):

    case = build_o2a_case(band, jacobian_reference_layer=True)
    case.metadata["id"] = "disamar_reference_o2a_jacobian_validation"
    case.metadata["storage"] = "disamar-reference-o2a-jacobian-validation"
    case.metadata["description"] = "Hardcoded DISAMAR O2 A Jacobian validation case."
    case.scene_id = "o2a_disamar_reference_jacobian_validation"
    case.instrument_response.instrument_name = "disamar-o2a-jacobian-validation"

    return case
