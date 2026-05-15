use std::f64::consts::PI;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rule {
    pub count: u32,
    pub nodes: [f64; 10],
    pub weights: [f64; 10],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    InvalidOrder,
    UnsupportedOrder,
}

pub fn fill_nodes_and_weights(
    order: u32,
    nodes_out: &mut [f64],
    weights_out: &mut [f64],
) -> Result<(), Error> {
    if order == 0 || nodes_out.len() < order as usize || weights_out.len() < order as usize {
        return Err(Error::InvalidOrder);
    }

    let order_usize = order as usize;
    let half_count = order_usize.div_ceil(2);
    let tolerance = 1.0e-14;

    for index in 0..half_count {
        let mut root = (PI * (index as f64 + 0.75) / (order as f64 + 0.5)).cos();
        loop {
            let polynomial = legendre_polynomial(order, root);
            let derivative =
                legendre_derivative(order, root, polynomial.value, polynomial.previous_value);
            let next_root = root - polynomial.value / derivative;
            if (next_root - root).abs() <= tolerance {
                root = next_root;
                break;
            }
            root = next_root;
        }

        let polynomial = legendre_polynomial(order, root);
        let derivative =
            legendre_derivative(order, root, polynomial.value, polynomial.previous_value);
        let weight = 2.0 / ((1.0 - root * root) * derivative * derivative);

        nodes_out[index] = -root;
        weights_out[index] = weight;
        let mirrored_index = order_usize - 1 - index;
        nodes_out[mirrored_index] = root;
        weights_out[mirrored_index] = weight;
    }
    Ok(())
}

pub const MAX_DISAMAR_DIVISION_POINTS: usize = 256;

pub fn fill_disamar_div_points_01(
    order: u32,
    nodes_out: &mut [f64],
    weights_out: &mut [f64],
) -> Result<(), Error> {
    if order == 0
        || nodes_out.len() < order as usize
        || weights_out.len() < order as usize
        || order as usize > MAX_DISAMAR_DIVISION_POINTS
    {
        return Err(Error::InvalidOrder);
    }

    let (diagonal, first_row, order_usize) = disamar_division_eigensystem(order)?;
    for index in 0..order_usize {
        nodes_out[index] = (diagonal[index] + 1.0) * 0.5;
        weights_out[index] = first_row[index] * first_row[index];
    }
    Ok(())
}

pub fn fill_disamar_div_points_interval(
    order: u32,
    a0: f64,
    b0: f64,
    nodes_out: &mut [f64],
    weights_out: &mut [f64],
) -> Result<(), Error> {
    if order == 0
        || nodes_out.len() < order as usize
        || weights_out.len() < order as usize
        || order as usize > MAX_DISAMAR_DIVISION_POINTS
    {
        return Err(Error::InvalidOrder);
    }

    let (diagonal, first_row, order_usize) = disamar_division_eigensystem(order)?;
    let span = b0 - a0;
    for index in 0..order_usize {
        weights_out[index] = first_row[index] * first_row[index] * 0.5 * span;
        nodes_out[index] = (diagonal[index] + 1.0) * 0.5 * span + a0;
    }
    Ok(())
}

fn disamar_division_eigensystem(
    order: u32,
) -> Result<
    (
        [f64; MAX_DISAMAR_DIVISION_POINTS],
        [f64; MAX_DISAMAR_DIVISION_POINTS],
        usize,
    ),
    Error,
> {
    if order == 0 || order as usize > MAX_DISAMAR_DIVISION_POINTS {
        return Err(Error::InvalidOrder);
    }

    let order_usize = order as usize;
    let mut diagonal = [0.0; MAX_DISAMAR_DIVISION_POINTS];
    let mut off_diagonal = [0.0; MAX_DISAMAR_DIVISION_POINTS];
    let mut first_row = [0.0; MAX_DISAMAR_DIVISION_POINTS];

    if order_usize > 1 {
        for (index, value) in off_diagonal.iter_mut().enumerate().take(order_usize - 1) {
            let abi = (index + 1) as f64;
            *value = abi / (4.0 * abi * abi - 1.0).sqrt();
        }
    }
    first_row[0] = 1.0;

    // DISAMAR obtains the [0, 1] division points through the Jacobi matrix
    // eigenproblem, not by rescaling the Newton roots. Keeping that path avoids
    // tiny ordering and weight differences in downstream RTM parity checks.
    gausq2_disamar(
        &mut diagonal[..order_usize],
        &mut off_diagonal[..order_usize],
        &mut first_row[..order_usize],
    )?;

    Ok((diagonal, first_row, order_usize))
}

fn gausq2_disamar(
    diagonal: &mut [f64],
    off_diagonal: &mut [f64],
    first_row: &mut [f64],
) -> Result<(), Error> {
    let n = diagonal.len();
    if n == 0 || off_diagonal.len() != n || first_row.len() != n {
        return Err(Error::InvalidOrder);
    }
    if n == 1 {
        return Ok(());
    }

    let machep = 2.0e-16;
    off_diagonal[n - 1] = 0.0;

    let mut l = 0;
    while l < n {
        let mut iteration_count = 0;
        loop {
            let mut m = l;
            while m < n {
                if m == n - 1 {
                    break;
                }
                if off_diagonal[m].abs() <= machep * (diagonal[m].abs() + diagonal[m + 1].abs()) {
                    break;
                }
                m += 1;
            }

            let mut p = diagonal[l];
            if m == l {
                break;
            }
            if iteration_count == 30 {
                return Err(Error::InvalidOrder);
            }
            iteration_count += 1;

            let mut g = (diagonal[l + 1] - p) / (2.0 * off_diagonal[l]);
            let mut r = (g * g + 1.0).sqrt();
            g = diagonal[m] - p + off_diagonal[l] / (g + disamar_sign(r, g));
            let mut s = 1.0;
            let mut c = 1.0;
            p = 0.0;

            let mut ii = 1;
            while ii <= m - l {
                let i = m - ii;
                let f = s * off_diagonal[i];
                let b = c * off_diagonal[i];
                if f.abs() >= g.abs() {
                    c = g / f;
                    r = (c * c + 1.0).sqrt();
                    off_diagonal[i + 1] = f * r;
                    s = 1.0 / r;
                    c *= s;
                } else {
                    s = f / g;
                    r = (s * s + 1.0).sqrt();
                    off_diagonal[i + 1] = g * r;
                    c = 1.0 / r;
                    s *= c;
                }
                g = diagonal[i + 1] - p;
                r = (diagonal[i] - g) * s + 2.0 * c * b;
                p = s * r;
                diagonal[i + 1] = g + p;
                g = c * r - b;

                let f_component = first_row[i + 1];
                first_row[i + 1] = s * first_row[i] + c * f_component;
                first_row[i] = c * first_row[i] - s * f_component;
                ii += 1;
            }

            diagonal[l] -= p;
            off_diagonal[l] = g;
            off_diagonal[m] = 0.0;
        }
        l += 1;
    }

    for sort_start in 1..n {
        let i = sort_start - 1;
        let mut k = i;
        let mut p = diagonal[i];
        for (j, value) in diagonal.iter().enumerate().take(n).skip(sort_start) {
            if *value >= p {
                continue;
            }
            k = j;
            p = *value;
        }
        if k == i {
            continue;
        }
        diagonal[k] = diagonal[i];
        diagonal[i] = p;
        first_row.swap(i, k);
    }
    Ok(())
}

fn disamar_sign(magnitude: f64, sign_source: f64) -> f64 {
    if sign_source >= 0.0 {
        magnitude.abs()
    } else {
        -magnitude.abs()
    }
}

pub fn rule(order: u32) -> Result<Rule, Error> {
    if order == 0 || order > 10 {
        return Err(Error::UnsupportedOrder);
    }
    let mut nodes = [0.0; 10];
    let mut weights = [0.0; 10];
    fill_nodes_and_weights(order, &mut nodes, &mut weights)?;
    Ok(Rule {
        count: order,
        nodes,
        weights,
    })
}

struct PolynomialState {
    value: f64,
    previous_value: f64,
}

fn legendre_polynomial(order: u32, x: f64) -> PolynomialState {
    if order == 0 {
        return PolynomialState {
            value: 1.0,
            previous_value: 0.0,
        };
    }

    let mut previous_previous = 1.0;
    let mut previous = x;
    if order == 1 {
        return PolynomialState {
            value: previous,
            previous_value: previous_previous,
        };
    }

    let mut current = previous;
    let mut n = 2;
    while n <= order {
        current = (((2.0 * f64::from(n)) - 1.0) * x * previous
            - (f64::from(n) - 1.0) * previous_previous)
            / f64::from(n);
        previous_previous = previous;
        previous = current;
        n += 1;
    }

    PolynomialState {
        value: current,
        previous_value: previous_previous,
    }
}

fn legendre_derivative(order: u32, x: f64, value: f64, previous_value: f64) -> f64 {
    (f64::from(order) * (x * value - previous_value)) / ((x * x) - 1.0)
}
