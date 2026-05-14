#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    InvalidOrder,
    UnsupportedOrder,
}

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rule {
    pub count: u32,
    pub nodes: [f64; 10],
    pub weights: [f64; 10],
}

pub fn fill_nodes_and_weights(
    order: u32,
    nodes_out: &mut [f64],
    weights_out: &mut [f64],
) -> Result<()> {
    if order == 0 || nodes_out.len() < order as usize || weights_out.len() < order as usize {
        return Err(Error::InvalidOrder);
    }

    let order_usize = order as usize;
    let half_count = order_usize.div_ceil(2);
    let tolerance = 1.0e-14;

    for index in 0..half_count {
        let mut root =
            (std::f64::consts::PI * (index as f64 + 0.75) / (f64::from(order) + 0.5)).cos();
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

pub fn fill_disamar_div_points_01(
    order: u32,
    nodes_out: &mut [f64],
    weights_out: &mut [f64],
) -> Result<()> {
    if order == 0 || nodes_out.len() < order as usize || weights_out.len() < order as usize {
        return Err(Error::InvalidOrder);
    }

    let order_usize = order as usize;
    let mut nodes = vec![0.0; order_usize];
    let mut weights = vec![0.0; order_usize];
    fill_nodes_and_weights(order, &mut nodes, &mut weights)?;
    for index in 0..order_usize {
        nodes_out[index] = (nodes[index] + 1.0) * 0.5;
        weights_out[index] = weights[index] * 0.5;
    }
    Ok(())
}

pub fn fill_disamar_div_points_interval(
    order: u32,
    a0: f64,
    b0: f64,
    nodes_out: &mut [f64],
    weights_out: &mut [f64],
) -> Result<()> {
    if order == 0 || nodes_out.len() < order as usize || weights_out.len() < order as usize {
        return Err(Error::InvalidOrder);
    }
    fill_disamar_div_points_01(order, nodes_out, weights_out)?;
    let span = b0 - a0;
    for index in 0..order as usize {
        nodes_out[index] = nodes_out[index] * span + a0;
        weights_out[index] *= span;
    }
    Ok(())
}

pub fn rule(order: u32) -> Result<Rule> {
    if !(1..=10).contains(&order) {
        return Err(Error::UnsupportedOrder);
    }
    let mut nodes = [0.0; 10];
    let mut weights = [0.0; 10];
    fill_nodes_and_weights(order, &mut nodes, &mut weights).map_err(|_| Error::UnsupportedOrder)?;
    Ok(Rule {
        count: order,
        nodes,
        weights,
    })
}

#[derive(Debug, Clone, Copy)]
struct LegendrePolynomial {
    value: f64,
    previous_value: f64,
}

fn legendre_polynomial(order: u32, x: f64) -> LegendrePolynomial {
    if order == 0 {
        return LegendrePolynomial {
            value: 1.0,
            previous_value: 0.0,
        };
    }
    if order == 1 {
        return LegendrePolynomial {
            value: x,
            previous_value: 1.0,
        };
    }

    let mut p_nm2 = 1.0;
    let mut p_nm1 = x;
    let mut p_n = x;
    for n in 2..=order {
        let nf = f64::from(n);
        p_n = (((2.0 * nf) - 1.0) * x * p_nm1 - (nf - 1.0) * p_nm2) / nf;
        p_nm2 = p_nm1;
        p_nm1 = p_n;
    }
    LegendrePolynomial {
        value: p_n,
        previous_value: p_nm2,
    }
}

fn legendre_derivative(order: u32, x: f64, value: f64, previous_value: f64) -> f64 {
    f64::from(order) * (x * value - previous_value) / (x * x - 1.0)
}
