use zdisamar::forward_model::{
    optical_properties::shared::phase_functions::{self, PhaseCoefficients},
    radiative_transfer::{
        common_types::LayerInput,
        labos::{
            FourierPlmBasis, Geometry, MAX_PHASE_COEF, fill_layer_effective_scattering_suffixes,
            fill_layer_phase_max_indices, fill_surface, fill_zplus_zmin_from_basis,
            renormalize_zero_fourier_phase_kernel, zero_fourier_integral,
        },
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

fn phase_coefficients(entries: &[(usize, f64)]) -> PhaseCoefficients {
    let mut coefficients = phase_functions::zero_phase_coefficients();
    for &(index, value) in entries {
        coefficients[index] = value;
    }
    coefficients
}

#[test]
fn zero_fourier_surface_is_weight_outer_product() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let surface = fill_surface(0, 0.21, &geometry);

    for i in 0..geometry.nmutot {
        for j in 0..geometry.nmutot {
            assert_close(
                surface.r.get(i, j),
                geometry.w[i] * 0.21 * geometry.w[j],
                1.0e-12,
            );
            assert_close(surface.t.get(i, j), 0.0, 0.0);
        }
    }

    let nonzero_fourier_surface = fill_surface(1, 0.21, &geometry);
    for value in nonzero_fourier_surface
        .r
        .data
        .iter()
        .take(geometry.nmutot * geometry.nmutot)
    {
        assert_close(*value, 0.0, 0.0);
    }
}

#[test]
fn layer_phase_max_and_effective_scattering_suffixes_match_phase_support() {
    let layers = vec![
        LayerInput {
            phase_coefficients: phase_coefficients(&[(1, 0.5), (3, 0.25)]),
            ..LayerInput::default()
        },
        LayerInput {
            phase_coefficients: phase_coefficients(&[(2, -0.3)]),
            ..LayerInput::default()
        },
    ];
    let mut max_indices = vec![0; layers.len()];
    fill_layer_phase_max_indices(&mut max_indices, &layers);
    assert_eq!(max_indices, [3, 2]);

    let mut suffixes = vec![0.0; layers.len() * MAX_PHASE_COEF];
    fill_layer_effective_scattering_suffixes(&mut suffixes, &layers, &max_indices);
    let first = &suffixes[..MAX_PHASE_COEF];
    assert_close(first[3], 0.25 / 7.0, 1.0e-12);
    assert_close(first[2], 0.25 / 7.0, 1.0e-12);
    assert_close(first[1], 0.5 / 3.0, 1.0e-12);
    assert_close(first[0], 1.0, 1.0e-12);
}

#[test]
fn zero_fourier_integral_reads_unweighted_phase_column() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let phase = phase_functions::zero_phase_coefficients();
    let basis = FourierPlmBasis::init(0, 0, &geometry);
    let kernel = fill_zplus_zmin_from_basis(0, phase, &geometry, &basis);

    assert_close(
        zero_fourier_integral(&kernel.zplus, &kernel.zmin, &geometry, 0),
        2.0,
        1.0e-12,
    );
}

#[test]
fn zero_fourier_renormalization_restores_column_integrals() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let phase = phase_functions::zero_phase_coefficients();
    let basis = FourierPlmBasis::init(0, 0, &geometry);
    let mut kernel = fill_zplus_zmin_from_basis(0, phase, &geometry, &basis);

    for value in kernel
        .zplus
        .data
        .iter_mut()
        .take(geometry.nmutot * geometry.nmutot)
    {
        *value *= 0.8;
    }
    renormalize_zero_fourier_phase_kernel(&geometry, &mut kernel.zplus, &mut kernel.zmin);

    for column in 0..geometry.nmutot {
        assert_close(
            zero_fourier_integral(&kernel.zplus, &kernel.zmin, &geometry, column),
            2.0,
            1.0e-10,
        );
    }
}
