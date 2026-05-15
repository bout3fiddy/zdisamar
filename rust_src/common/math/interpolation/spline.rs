pub const MAX_SPLINE_POINT_COUNT: usize = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ShapeMismatch,
    NotEnoughPoints,
    OutOfDomain,
}

pub fn sample_endpoint_secant(x: &[f64], y: &[f64], target_x: f64) -> Result<f64, Error> {
    if x.len() != y.len() {
        return Err(Error::ShapeMismatch);
    }
    if x.len() < 3 || x.len() > MAX_SPLINE_POINT_COUNT {
        return Err(Error::NotEnoughPoints);
    }
    if target_x < x[0] || target_x > x[x.len() - 1] {
        return Err(Error::OutOfDomain);
    }

    let second = endpoint_secant_second_derivatives(x, y)?;
    sample_with_second_derivatives(x, y, &second, target_x)
}

pub fn endpoint_secant_second_derivatives(x: &[f64], y: &[f64]) -> Result<Vec<f64>, Error> {
    if x.len() != y.len() {
        return Err(Error::ShapeMismatch);
    }
    if x.len() < 3 || x.len() > MAX_SPLINE_POINT_COUNT {
        return Err(Error::NotEnoughPoints);
    }

    let len = x.len();
    let c1 = y.to_vec();
    let mut c2 = vec![0.0; len];
    let mut c3 = vec![0.0; len];
    let mut c4 = vec![0.0; len];

    // DISAMAR builds this spline with endpoint slopes set to the adjacent
    // secants. Keeping that shape avoids small differences in spectral assets.
    c2[0] = (y[1] - y[0]) / (x[1] - x[0]);
    c2[len - 1] = (y[len - 1] - y[len - 2]) / (x[len - 1] - x[len - 2]);

    for index in 1..len {
        c3[index] = x[index] - x[index - 1];
        c4[index] = (c1[index] - c1[index - 1]) / c3[index];
    }

    c4[0] = 1.0;
    c3[0] = 0.0;

    for index in 1..len - 1 {
        let g = -c3[index + 1] / c4[index - 1];
        c2[index] =
            g * c2[index - 1] + 3.0 * (c3[index] * c4[index + 1] + c3[index + 1] * c4[index]);
        c4[index] = g * c3[index - 1] + 2.0 * (c3[index] + c3[index + 1]);
    }

    for solve_index in (0..len - 1).rev() {
        c2[solve_index] =
            (c2[solve_index] - c3[solve_index] * c2[solve_index + 1]) / c4[solve_index];
    }

    for index in 1..len {
        let dtau = c3[index];
        let divdf1 = (c1[index] - c1[index - 1]) / dtau;
        let divdf3 = c2[index - 1] + c2[index] - 2.0 * divdf1;
        c3[index - 1] = 2.0 * (divdf1 - c2[index - 1] - divdf3) / dtau;
        c4[index - 1] = 6.0 * divdf3 / (dtau * dtau);
    }

    let mut second = vec![0.0; len];
    second[0] = -0.5 * c3[1];
    second[1..len - 1].copy_from_slice(&c3[1..len - 1]);
    second[len - 1] = -0.5 * c3[len - 2];
    Ok(second)
}

pub fn sample_with_second_derivatives(
    x: &[f64],
    y: &[f64],
    second: &[f64],
    target_x: f64,
) -> Result<f64, Error> {
    if x.len() != y.len() || x.len() != second.len() {
        return Err(Error::ShapeMismatch);
    }
    if x.len() < 3 {
        return Err(Error::NotEnoughPoints);
    }
    if target_x < x[0] || target_x > x[x.len() - 1] {
        return Err(Error::OutOfDomain);
    }

    let mut lower_index = 0;
    let mut upper_index = x.len() - 1;
    while upper_index - lower_index > 1 {
        let middle = (upper_index + lower_index) / 2;
        if x[middle] > target_x {
            upper_index = middle;
        } else {
            lower_index = middle;
        }
    }

    let span = x[upper_index] - x[lower_index];
    let a = (x[upper_index] - target_x) / span;
    let b = (target_x - x[lower_index]) / span;
    Ok(a * y[lower_index]
        + b * y[upper_index]
        + ((a * a * a - a) * second[lower_index] + (b * b * b - b) * second[upper_index])
            * (span * span)
            / 6.0)
}
