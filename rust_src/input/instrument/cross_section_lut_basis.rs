pub fn fill_legendre_values(values: &mut [f64], scaled_coordinate: f64) {
    if values.is_empty() {
        return;
    }
    values[0] = 1.0;
    if values.len() == 1 {
        return;
    }
    values[1] = scaled_coordinate;
    if values.len() == 2 {
        return;
    }

    for index in 2..values.len() {
        let order = (index - 1) as f64;
        values[index] = (((2.0 * order) + 1.0) * scaled_coordinate * values[index - 1]
            - order * values[index - 2])
            / (order + 1.0);
    }
}

pub fn fill_legendre_temperature_derivative(
    derivative_values: &mut [f64],
    legendre_values: &[f64],
    scaled_coordinate: f64,
    temperature_k: f64,
    minimum_temperature_k: f64,
    maximum_temperature_k: f64,
) {
    derivative_values.fill(0.0);
    if derivative_values.len() <= 1 {
        return;
    }

    let ln_max = maximum_temperature_k.ln();
    let ln_min = minimum_temperature_k.ln();
    let scale = ln_max - ln_min;
    if scale == 0.0 || temperature_k <= 0.0 {
        return;
    }

    let d_scaled_d_temperature = 2.0 / (scale * temperature_k);
    derivative_values[1] = 1.0;
    for index in 2..derivative_values.len() {
        derivative_values[index] = (scaled_coordinate * derivative_values[index - 1])
            + (index as f64 * legendre_values[index - 1]);
    }
    for value in derivative_values.iter_mut().skip(1) {
        *value *= d_scaled_d_temperature;
    }
}
