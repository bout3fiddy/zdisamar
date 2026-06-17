const std = @import("std");

const native_json =
    \\{
    \\  "aerosol": {
    \\    "angstrom_exponent": 0.0,
    \\    "asymmetry_factor": 0.7,
    \\    "optical_depth": 0.3,
    \\    "placement": {
    \\      "bottom_altitude_km": null,
    \\      "bottom_pressure_hpa": 520.0,
    \\      "interval_index_1based": 2,
    \\      "semantics": "explicit_interval_bounds",
    \\      "top_altitude_km": null,
    \\      "top_pressure_hpa": 500.0
    \\    },
    \\    "reference_wavelength_nm": 550.0,
    \\    "single_scatter_albedo": 1.0
    \\  },
    \\  "fit_interval_index_1based": 2,
    \\  "geometry": {
    \\    "model": "pseudo_spherical",
    \\    "relative_azimuth_deg": 120.0,
    \\    "solar_zenith_deg": 60.0,
    \\    "viewing_zenith_deg": 30.0
    \\  },
    \\  "inputs": {
    \\    "airmass_factor_lut": {
    \\      "format": "csv",
    \\      "id": "airmass_factor_lut",
    \\      "path": "data/reference_data/luts/airmass_factor_nadir_demo.csv"
    \\    },
    \\    "atmosphere_profile": {
    \\      "format": "profile_csv",
    \\      "id": "atmosphere_profile",
    \\      "path": "data/reference_data/climatologies/vendor_config_o2a_profile.csv"
    \\    },
    \\    "raw_solar_reference": {
    \\      "format": "solar_reference_csv",
    \\      "id": "raw_solar_reference",
    \\      "path": "data/reference_data/solar/o2a_solar_reference_753_778.csv"
    \\    },
    \\    "vendor_reference_csv": {
    \\      "format": "disamar_o2a_reference_csv",
    \\      "id": "vendor_reference_csv",
    \\      "path": "data/reference_data/validation/o2a_with_cia_disamar_reference.csv"
    \\    }
    \\  },
    \\  "intervals": [
    \\    {
    \\      "altitude_divisions": 28,
    \\      "bottom_altitude_km": null,
    \\      "bottom_pressure_hpa": 500.0,
    \\      "bottom_pressure_variance_hpa2": 0.0,
    \\      "index_1based": 1,
    \\      "top_altitude_km": null,
    \\      "top_pressure_hpa": 0.3,
    \\      "top_pressure_variance_hpa2": 0.0
    \\    },
    \\    {
    \\      "altitude_divisions": 6,
    \\      "bottom_altitude_km": null,
    \\      "bottom_pressure_hpa": 520.0,
    \\      "bottom_pressure_variance_hpa2": 0.0,
    \\      "index_1based": 2,
    \\      "top_altitude_km": null,
    \\      "top_pressure_hpa": 500.0,
    \\      "top_pressure_variance_hpa2": 0.0
    \\    },
    \\    {
    \\      "altitude_divisions": 8,
    \\      "bottom_altitude_km": null,
    \\      "bottom_pressure_hpa": 1013.25,
    \\      "bottom_pressure_variance_hpa2": 0.0,
    \\      "index_1based": 3,
    \\      "top_altitude_km": null,
    \\      "top_pressure_hpa": 520.0,
    \\      "top_pressure_variance_hpa2": 0.0
    \\    }
    \\  ],
    \\  "layer_count": 3,
    \\  "metadata": {
    \\    "description": "DISAMAR O2A reference scene defined in Python.",
    \\    "id": "disamar_reference_o2a",
    \\    "storage": "disamar-reference-o2a"
    \\  },
    \\  "o2": {
    \\    "cutoff_sim_cm1": 200.0,
    \\    "isotopes_sim": [
    \\      1,
    \\      2,
    \\      3
    \\    ],
    \\    "line_list_asset": {
    \\      "format": "hitran_par_o2a",
    \\      "id": "o2_hitran",
    \\      "path": "data/reference_data/cross_sections/o2a_hitran_07_hit08_tropomi.par"
    \\    },
    \\    "line_mixing_asset": {
    \\      "format": "lisa_rmf",
    \\      "id": "o2_line_mixing",
    \\      "path": "data/reference_data/cross_sections/o2a_lisa_rmf.dat"
    \\    },
    \\    "line_mixing_factor": 1.0,
    \\    "strong_lines_asset": {
    \\      "format": "lisa_sdf",
    \\      "id": "o2_strong_lines",
    \\      "path": "data/reference_data/cross_sections/o2a_lisa_sdf.dat"
    \\    },
    \\    "threshold_line_sim": 3e-05
    \\  },
    \\  "o2o2": {
    \\    "cia_asset": {
    \\      "format": "bira_cia",
    \\      "id": "o2o2_cia",
    \\      "path": "data/reference_data/cross_sections/o2o2_bira_o2a.dat"
    \\    },
    \\    "enabled": true
    \\  },
    \\  "observation": {
    \\    "adaptive_reference_grid": {
    \\      "points_per_fwhm": 20,
    \\      "strong_line_max_divisions": 40,
    \\      "strong_line_min_divisions": 8
    \\    },
    \\    "builtin_line_shape": "flat_top_n4",
    \\    "high_resolution_half_span_nm": 1.14,
    \\    "high_resolution_step_nm": 0.01,
    \\    "instrument_line_fwhm_nm": 0.38,
    \\    "instrument_name": "disamar-o2a-compare",
    \\    "measured_wavelengths_nm": [],
    \\    "regime": "nadir",
    \\    "sampling": "native",
    \\    "solar_reference_asset_id": "raw_solar_reference"
    \\  },
    \\  "plan": {
    \\    "derivative_mode": "none"
    \\  },
    \\  "rtm_controls": {
    \\    "integrate_source_function": true,
    \\    "n_streams": 20,
    \\    "performance_thresholds": {
    \\      "aerosol_tangent_order_cap": null,
    \\      "fourier_floor_scalar": 2,
    \\      "fourier_order_cap": null,
    \\      "fourier_tail_reflectance_epsilon": 3e-14,
    \\      "num_orders_max": 0,
    \\      "phase_function_truncation_threshold": 1e-08,
    \\      "threshold_conv_first": 1.5e-07,
    \\      "threshold_conv_mult": 1.5e-09,
    \\      "threshold_doubl": 1e-06,
    \\      "threshold_mul": 1e-08
    \\    },
    \\    "renorm_phase_function": true,
    \\    "scattering": "multiple",
    \\    "use_spherical_correction": true
    \\  },
    \\  "scene_id": "o2a_disamar_reference_python",
    \\  "spectral_grid": {
    \\    "end_nm": 776.0,
    \\    "sample_count": 701,
    \\    "start_nm": 755.0
    \\  },
    \\  "sublayer_divisions": 4,
    \\  "surface_albedo": 0.2,
    \\  "surface_pressure_hpa": 1013.25
    \\}
;

// The full-band spectral grid block, verbatim from native_json (unique substring). narrowJson
// swaps it for a ~1.5nm window on the O2 A-band R-branch so control-flow / structural tests
// prepare ~4x faster. native_json itself is left byte-identical so the canonical full-band
// golden tests keep their exact inputs.
const full_grid_block =
    \\    "end_nm": 776.0,
    \\    "sample_count": 701,
    \\    "start_nm": 755.0
;
const narrow_grid_block =
    \\    "end_nm": 761.0,
    \\    "sample_count": 16,
    \\    "start_nm": 759.5
;

pub fn nativeJson(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(u8, native_json);
}

pub fn narrowJson(allocator: std.mem.Allocator) ![]u8 {
    // narrowJson ------------------------------------------------------------------------------------------- |
    // Default scene over a narrow representative band; use for tests that check control flow,                |
    // batching/fastmode structure, or error paths rather than canonical full-band physics values.           |
    // ------------------------------------------------------------------------------------------------------ |
    const size = std.mem.replacementSize(u8, native_json, full_grid_block, narrow_grid_block);
    const rendered = try allocator.alloc(u8, size);
    const count = std.mem.replace(u8, native_json, full_grid_block, narrow_grid_block, rendered);
    std.debug.assert(count == 1);
    return rendered;
}
