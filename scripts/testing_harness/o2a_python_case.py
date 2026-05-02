from __future__ import annotations


def asset(zd, id: str, path: str, format: str):
    return zd.ReferenceAsset(id=id, path=path, format=format)


def build_o2a_case(zd):
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
                "validation/o2a_with_cia_disamar_reference.csv",
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
        spectral_grid=zd.SpectralGrid(start_nm=755.0, end_nm=776.0, sample_count=701),
        atmosphere=zd.Atmosphere(
            layer_count=3,
            sublayer_divisions=4,
            fit_interval_index_1based=2,
            intervals=[
                zd.VerticalInterval(
                    index_1based=1,
                    top_pressure_hpa=0.3,
                    bottom_pressure_hpa=500.0,
                    altitude_divisions=28,
                ),
                zd.VerticalInterval(
                    index_1based=2,
                    top_pressure_hpa=500.0,
                    bottom_pressure_hpa=520.0,
                    altitude_divisions=6,
                ),
                zd.VerticalInterval(
                    index_1based=3,
                    top_pressure_hpa=520.0,
                    bottom_pressure_hpa=1013.25,
                    altitude_divisions=8,
                ),
            ],
        ),
        surface=zd.Surface(albedo=0.2, pressure_hpa=1013.25),
        geometry=zd.Geometry(
            model="pseudo_spherical",
            solar_zenith_deg=60.0,
            viewing_zenith_deg=30.0,
            relative_azimuth_deg=120.0,
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
                top_pressure_hpa=500.0,
                bottom_pressure_hpa=520.0,
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
                "points_per_fwhm": 20,
                "strong_line_min_divisions": 8,
                "strong_line_max_divisions": 40,
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
        o2_o2_cia=zd.O2O2CIA(
            enabled=True,
            cia_asset=asset(
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
            stokes_dimension=1,
        ),
        outputs=[],
        validation={
            "strict_unknown_fields": True,
            "require_resolved_assets": True,
            "require_resolved_stage_references": True,
        },
    )
