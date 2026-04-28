pub fn fillLegendreValues(values: []f64, scaled_coordinate: f64) void {
    if (values.len == 0) return;
    values[0] = 1.0;
    if (values.len == 1) return;
    values[1] = scaled_coordinate;
    if (values.len == 2) return;

    for (2..values.len) |index| {
        const order = @as(f64, @floatFromInt(index - 1));
        values[index] =
            (((2.0 * order) + 1.0) * scaled_coordinate * values[index - 1] - order * values[index - 2]) /
            (order + 1.0);
    }
}

pub fn fillLegendreTemperatureDerivative(
    derivative_values: []f64,
    legendre_values: []const f64,
    scaled_coordinate: f64,
    temperature_k: f64,
    minimum_temperature_k: f64,
    maximum_temperature_k: f64,
) void {
    @memset(derivative_values, 0.0);
    if (derivative_values.len <= 1) return;

    const ln_max = @log(maximum_temperature_k);
    const ln_min = @log(minimum_temperature_k);
    const scale = ln_max - ln_min;
    if (scale == 0.0 or temperature_k <= 0.0) return;

    const d_scaled_d_temperature = 2.0 / (scale * temperature_k);
    derivative_values[1] = 1.0;
    for (2..derivative_values.len) |index| {
        derivative_values[index] =
            (scaled_coordinate * derivative_values[index - 1]) +
            (@as(f64, @floatFromInt(index)) * legendre_values[index - 1]);
    }
    for (1..derivative_values.len) |index| {
        derivative_values[index] *= d_scaled_d_temperature;
    }
}
