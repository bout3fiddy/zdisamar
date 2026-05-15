use zdisamar::common::math::quadrature::gauss_legendre::{
    Error, fill_disamar_div_points_01, fill_disamar_div_points_interval, fill_nodes_and_weights,
    rule,
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

#[test]
fn gauss_legendre_rules_expose_stable_nodes_and_weights() {
    let one_point = rule(1).unwrap();
    assert_eq!(one_point.count, 1);
    assert_close(one_point.nodes[0], 0.0, 1.0e-12);
    assert_close(one_point.weights[0], 2.0, 1.0e-12);

    let three_point = rule(3).unwrap();
    assert_eq!(three_point.count, 3);
    assert_close(three_point.nodes[1], 0.0, 1.0e-12);
    assert_close(three_point.weights[1], 0.8888888888888888, 1.0e-12);

    let seven_point = rule(7).unwrap();
    assert_eq!(seven_point.count, 7);
    assert_close(seven_point.nodes[3], 0.0, 1.0e-12);
    assert_close(seven_point.weights[3], 0.4179591836734694, 1.0e-12);

    let ten_point = rule(10).unwrap();
    assert_eq!(ten_point.count, 10);
    assert_close(ten_point.nodes[0], -0.9739065285171717, 1.0e-12);
    assert_close(ten_point.weights[4], 0.2955242247147529, 1.0e-12);
}

#[test]
fn gauss_legendre_dynamic_fill_supports_higher_order_rules() {
    let mut nodes = [0.0; 20];
    let mut weights = [0.0; 20];

    fill_nodes_and_weights(20, &mut nodes, &mut weights).unwrap();
    assert_close(nodes[0], -0.9931285991850949, 1.0e-12);
    assert_close(weights[9], 0.1527533871307258, 1.0e-12);
    assert_close(nodes[0], -nodes[19], 1.0e-12);
}

#[test]
fn disamar_gauss_division_points_are_scaled_to_unit_interval() {
    let mut nodes = [0.0; 5];
    let mut weights = [0.0; 5];

    fill_disamar_div_points_01(5, &mut nodes, &mut weights).unwrap();

    let mut sum_weights = 0.0;
    for index in 0..5 {
        assert!((0.0..=1.0).contains(&nodes[index]));
        sum_weights += weights[index];
    }
    assert!(nodes.windows(2).all(|pair| pair[0] < pair[1]));
    assert_close(sum_weights, 1.0, 1.0e-12);
}

#[test]
fn disamar_gauss_division_points_scale_to_explicit_interval() {
    let mut nodes = [0.0; 4];
    let mut weights = [0.0; 4];

    fill_disamar_div_points_interval(4, 2.0, 6.0, &mut nodes, &mut weights).unwrap();

    assert!(nodes.iter().all(|node| (2.0..=6.0).contains(node)));
    // The interval helper mirrors the vendor routine's half-span scaling.
    // The dedicated [0, 1] helper above is the one used for LABOS geometry.
    assert_close(weights.iter().sum::<f64>(), 2.0, 1.0e-12);
    assert_eq!(
        fill_disamar_div_points_01(0, &mut nodes, &mut weights),
        Err(Error::InvalidOrder)
    );
}
