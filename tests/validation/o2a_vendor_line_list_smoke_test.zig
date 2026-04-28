const std = @import("std");
const zdisamar = @import("zdisamar");
const disamar_reference = zdisamar.disamar_reference;
const ReferenceData = disamar_reference.ReferenceData;

test "DISAMAR reference O2A helper preserves weak-lane rows while retaining strong sidecars" {
    var line_list = try disamar_reference.loadDisamarReferenceO2ASpectroscopyLineList(std.testing.allocator);
    defer line_list.deinit(std.testing.allocator);

    try line_list.buildStrongLineMatchIndex(std.testing.allocator);
    try std.testing.expect(!line_list.preserve_anchor_weak_lines);

    const probe_wavelength_nm = 762.29;
    const probe_temperature_k = 190.5;
    const probe_pressure_hpa = 0.000258;

    var prepared_state = (try line_list.prepareStrongLineState(
        std.testing.allocator,
        probe_temperature_k,
        probe_pressure_hpa,
    )).?;
    defer prepared_state.deinit(std.testing.allocator);

    const preserved = line_list.evaluateAtPrepared(
        probe_wavelength_nm,
        probe_temperature_k,
        probe_pressure_hpa,
        &prepared_state,
    );
    const weak_only_view = ReferenceData.SpectroscopyLineList{
        .lines = line_list.lines,
        .lines_sorted_ascending = line_list.lines_sorted_ascending,
        .runtime_controls = line_list.runtime_controls,
    };
    const weak_only = weak_only_view.evaluateAt(
        probe_wavelength_nm,
        probe_temperature_k,
        probe_pressure_hpa,
    );

    try std.testing.expectApproxEqRel(
        weak_only.weak_line_sigma_cm2_per_molecule,
        preserved.weak_line_sigma_cm2_per_molecule,
        1.0e-12,
    );
    try std.testing.expect(preserved.strong_line_sigma_cm2_per_molecule > 0.0);
}
