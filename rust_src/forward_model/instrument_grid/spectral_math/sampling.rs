#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ShapeMismatch,
}

pub type Result<T> = std::result::Result<T, Error>;

pub fn sample_linear_clamped(x: &[f64], y: &[f64], target_x: f64) -> Result<f64> {
    if x.len() != y.len() || x.is_empty() {
        return Err(Error::ShapeMismatch);
    }
    Ok(sample_linear_clamped_assume_valid(x, y, target_x))
}

pub fn sample_linear_clamped_assume_valid(x: &[f64], y: &[f64], target_x: f64) -> f64 {
    debug_assert_eq!(x.len(), y.len());
    debug_assert!(!x.is_empty());

    if x.len() == 1 {
        return y[0];
    }
    if target_x <= x[0] {
        return y[0];
    }
    if target_x >= x[x.len() - 1] {
        return y[y.len() - 1];
    }
    for index in 0..x.len() - 1 {
        let left_x = x[index];
        let right_x = x[index + 1];
        if target_x < left_x || target_x > right_x {
            continue;
        }
        let alpha = (target_x - left_x) / (right_x - left_x);
        return (1.0 - alpha) * y[index] + alpha * y[index + 1];
    }
    y[y.len() - 1]
}
