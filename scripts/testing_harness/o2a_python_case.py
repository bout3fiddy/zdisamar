from __future__ import annotations


def asset(zd, id: str, path: str, format: str):
    return zd.ReferenceAsset(id=id, path=path, format=format)


def build_o2a_case(zd, *, jacobian_reference_layer: bool = False):
    aerosol_top_pressure_hpa = 875.0 if jacobian_reference_layer else 500.0
    aerosol_bottom_pressure_hpa = 925.0 if jacobian_reference_layer else 520.0
    viewing_zenith_deg = 0.0 if jacobian_reference_layer else 30.0
    relative_azimuth_deg = 0.0 if jacobian_reference_layer else 120.0
    upper_interval_divisions = 28
    aerosol_interval_divisions = 2 if jacobian_reference_layer else 6
    lower_interval_divisions = 4 if jacobian_reference_layer else 8
    spectral_start_nm = 755.0
    spectral_end_nm = 776.0
    spectral_sample_count = 701

    return zd.O2AInput(
        metadata={
            "id": "disamar_reference_o2a",
            "storage": "disamar-reference-o2a",
            "description": "DISAMAR O2 A reference case defined in Python.",
        },
        plan={
            "model_family": "disamar_standard",
            "transport_solver": "dispatcher",
            "execution_solver_mode": "scalar",
            "execution_derivative_mode": "none",
        },
        reference_assets=zd.ReferenceAssets(
            atmosphere_profile=asset(
                zd,
                "atmosphere_profile",
                "data/reference_data/climatologies/vendor_config_o2a_profile.csv",
                "profile_csv",
            ),
            vendor_reference_csv=asset(
                zd,
                "vendor_reference_csv",
                "validation/spectra/data/o2a_with_cia_disamar_reference.csv",
                "disamar_o2a_reference_csv",
            ),
            raw_solar_reference=asset(
                zd,
                "raw_solar_reference",
                "data/reference_data/solar/o2a_solar_reference_753_778.csv",
                "solar_reference_csv",
            ),
            airmass_factor_lut=asset(
                zd,
                "airmass_factor_lut",
                "data/reference_data/luts/airmass_factor_nadir_demo.csv",
                "csv",
            ),
        ),
        scene_id="o2a_disamar_reference_python",
        spectral_grid=zd.SpectralGrid(
            start_nm=spectral_start_nm,
            end_nm=spectral_end_nm,
            sample_count=spectral_sample_count,
        ),
        atmosphere=zd.Atmosphere(
            layer_count=3,
            sublayer_divisions=4,
            fit_interval_index_1based=2,
            intervals=[
                zd.VerticalInterval(
                    index_1based=1,
                    top_pressure_hpa=0.3,
                    bottom_pressure_hpa=aerosol_top_pressure_hpa,
                    altitude_divisions=upper_interval_divisions,
                ),
                zd.VerticalInterval(
                    index_1based=2,
                    top_pressure_hpa=aerosol_top_pressure_hpa,
                    bottom_pressure_hpa=aerosol_bottom_pressure_hpa,
                    altitude_divisions=aerosol_interval_divisions,
                ),
                zd.VerticalInterval(
                    index_1based=3,
                    top_pressure_hpa=aerosol_bottom_pressure_hpa,
                    bottom_pressure_hpa=1013.25,
                    altitude_divisions=lower_interval_divisions,
                ),
            ],
        ),
        surface=zd.Surface(albedo=0.2, pressure_hpa=1013.25),
        geometry=zd.Geometry(
            model="pseudo_spherical",
            solar_zenith_deg=60.0,
            viewing_zenith_deg=viewing_zenith_deg,
            relative_azimuth_deg=relative_azimuth_deg,
        ),
        aerosol=zd.Aerosol(
            optical_depth_550_nm=0.3,
            single_scatter_albedo=1.0,
            asymmetry_factor=0.7,
            angstrom_exponent=0.0,
            reference_wavelength_nm=550.0,
            layer_center_km=5.4,
            layer_width_km=0.4,
            placement=zd.AerosolPlacement(
                semantics="explicit_interval_bounds",
                interval_index_1based=2,
                top_pressure_hpa=aerosol_top_pressure_hpa,
                bottom_pressure_hpa=aerosol_bottom_pressure_hpa,
            ),
        ),
        instrument_response=zd.InstrumentResponse(
            instrument_name="disamar-o2a-compare",
            regime="nadir",
            sampling="native",
            noise_model="none",
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
        o2_lines=zd.O2LineByLine(
            line_list_asset=asset(
                zd,
                "o2_hitran",
                "vendor/disamar-fortran/RefSpec/07_HIT08_TROPOMI.par",
                "hitran_par_o2a",
            ),
            line_mixing_asset=asset(
                zd,
                "o2_line_mixing",
                "data/reference_data/cross_sections/o2a_lisa_rmf.dat",
                "lisa_rmf",
            ),
            strong_lines_asset=asset(
                zd,
                "o2_strong_lines",
                "data/reference_data/cross_sections/o2a_lisa_sdf.dat",
                "lisa_sdf",
            ),
            line_mixing_factor=1.0,
            isotopes_sim=[1, 2, 3],
            threshold_line_sim=3.0e-5,
            cutoff_sim_cm1=200.0,
        ),
        collision_induced_absorption=zd.OxygenCollisionInducedAbsorption(
            enabled=True,
            cross_section_asset=asset(
                zd,
                "o2o2_cia",
                "data/reference_data/cross_sections/o2o2_bira_o2a.dat",
                "bira_cia",
            ),
        ),
        radiative_transfer=zd.RadiativeTransferControls(
            scattering="multiple",
            n_streams=20,
            use_adding=False,
            num_orders_max=0,
            fourier_floor_scalar=2,
            threshold_conv_first=1.5e-7,
            threshold_conv_mult=1.5e-9,
            threshold_doubl=1.0e-6,
            threshold_mul=1.0e-8,
            use_spherical_correction=True,
            integrate_source_function=True,
            renorm_phase_function=True,
            phase_function_truncation_threshold=1.0e-6 if jacobian_reference_layer else 1.0e-8,
            stokes_dimension=1,
        ),
        outputs=[],
        validation={
            "strict_unknown_fields": True,
            "require_resolved_assets": True,
            "require_resolved_stage_references": True,
        },
    )
