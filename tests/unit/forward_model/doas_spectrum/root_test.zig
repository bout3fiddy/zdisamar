const std = @import("std");
const internal = @import("internal");

const doas_spectrum = internal.forward_model.doas_spectrum;

test "Legendre smooth split preserves Fortran DISMAS polynomial semantics" {
    var workspace = try doas_spectrum.Workspace.init(std.testing.allocator, 5, 3);
    defer workspace.deinit(std.testing.allocator);

    const wavelengths_nm = [_]f64{ 760.0, 761.0, 762.0, 763.0, 764.0 };
    var values: [wavelengths_nm.len]f64 = undefined;
    for (&values, wavelengths_nm) |*value, wavelength_nm| {
        const x = 2.0 * (wavelength_nm - wavelengths_nm[0]) /
            (wavelengths_nm[wavelengths_nm.len - 1] - wavelengths_nm[0]) - 1.0;
        value.* = 3.0 + 2.0 * x + 0.25 * (3.0 * x * x - 1.0);
    }

    var smooth: [wavelengths_nm.len]f64 = undefined;
    var differential: [wavelengths_nm.len]f64 = undefined;
    try doas_spectrum.splitSmoothDifferentialInto(
        &wavelengths_nm,
        &values,
        null,
        2,
        &workspace,
        &smooth,
        &differential,
    );

    for (values, smooth, differential) |expected, actual, residual| {
        try std.testing.expectApproxEqAbs(expected, actual, 1.0e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), residual, 1.0e-12);
    }
}

test "differential slant optical thickness sums trace gas columns" {
    const amf = [_]f64{ 2.0, 2.0, 2.0, 2.0, 2.0 };
    const sigma_diff = [_]f64{ -0.2, -0.1, 0.0, 0.1, 0.2 };
    const traces = [_]doas_spectrum.TraceGasDifferential{.{
        .column = 4.0,
        .air_mass_factor = &amf,
        .differential_cross_section = &sigma_diff,
    }};

    var tau_diff: [sigma_diff.len]f64 = undefined;
    try doas_spectrum.differentialSlantOpticalThicknessInto(&traces, &tau_diff);

    for (tau_diff, sigma_diff) |actual, sigma| {
        try std.testing.expectApproxEqAbs(8.0 * sigma, actual, 1.0e-12);
    }
}

test "slant optical thickness fit subtracts the smooth absorption baseline" {
    var workspace = try doas_spectrum.Workspace.init(std.testing.allocator, 5, 1);
    defer workspace.deinit(std.testing.allocator);

    const wavelengths_nm = [_]f64{ 760.0, 761.0, 762.0, 763.0, 764.0 };
    const amf = [_]f64{ 2.0, 2.0, 2.0, 2.0, 2.0 };
    const sigma = [_]f64{ 9.8, 9.9, 10.0, 10.1, 10.2 };
    const traces = [_]doas_spectrum.TraceGasAbsorption{.{
        .column = 4.0,
        .air_mass_factor = &amf,
        .cross_section = &sigma,
    }};

    var tau_diff: [wavelengths_nm.len]f64 = undefined;
    try doas_spectrum.fitSlantDifferentialOpticalThicknessInto(
        &wavelengths_nm,
        &traces,
        0,
        &workspace,
        &tau_diff,
    );

    const expected = [_]f64{ -1.6, -0.8, 0.0, 0.8, 1.6 };
    for (expected, tau_diff) |expected_value, actual| {
        try std.testing.expectApproxEqAbs(expected_value, actual, 1.0e-11);
    }
}

test "zero crossing support matches DISMAS reduced RTM wavelength selection" {
    const wavelengths_nm = [_]f64{ 760.0, 761.0, 762.0, 763.0 };
    const tau_diff = [_]f64{ 1.0, -1.0, -2.0, 2.0 };
    var support: [2]f64 = undefined;

    const count = try doas_spectrum.zeroCrossingSupportInto(
        &wavelengths_nm,
        &tau_diff,
        0.1,
        &support,
    );

    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectApproxEqAbs(@as(f64, 760.5), support[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 762.5), support[1], 1.0e-12);
}

test "log-smooth reflectance reconstruction applies differential absorption" {
    var workspace = try doas_spectrum.Workspace.init(std.testing.allocator, 5, 2);
    defer workspace.deinit(std.testing.allocator);

    const support_wavelengths_nm = [_]f64{ 760.0, 762.0, 764.0 };
    var support_reflectance: [support_wavelengths_nm.len]f64 = undefined;
    for (&support_reflectance, support_wavelengths_nm) |*reflectance, wavelength_nm| {
        const x = 2.0 * (wavelength_nm - support_wavelengths_nm[0]) /
            (support_wavelengths_nm[support_wavelengths_nm.len - 1] - support_wavelengths_nm[0]) - 1.0;
        reflectance.* = @exp(0.2 + 0.1 * x);
    }

    const output_wavelengths_nm = [_]f64{ 760.0, 761.0, 762.0, 763.0, 764.0 };
    const tau_diff = [_]f64{ 0.0, 0.1, -0.2, 0.3, -0.4 };
    var reflectance: [output_wavelengths_nm.len]f64 = undefined;
    try doas_spectrum.fitSmoothReflectanceAndReconstructInto(
        &support_wavelengths_nm,
        &support_reflectance,
        &output_wavelengths_nm,
        &tau_diff,
        1,
        &workspace,
        &reflectance,
    );

    for (output_wavelengths_nm, tau_diff, reflectance) |wavelength_nm, tau, actual| {
        const x = 2.0 * (wavelength_nm - support_wavelengths_nm[0]) /
            (support_wavelengths_nm[support_wavelengths_nm.len - 1] - support_wavelengths_nm[0]) - 1.0;
        const expected = @exp(0.2 + 0.1 * x - tau);
        try std.testing.expectApproxEqAbs(expected, actual, 1.0e-12);
    }
}
