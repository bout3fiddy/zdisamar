use zdisamar::common::math::quadrature::gauss_legendre::{
    fill_disamar_div_points_01, fill_disamar_div_points_interval, fill_nodes_and_weights, rule,
};

fn assert_close(left: f64, right: f64) {
    assert!((left - right).abs() <= 1.0e-12, "{left} != {right}");
}

#[test]
fn gauss_legendre_rules_expose_stable_nodes_and_weights() {
    let one_point = rule(1).unwrap();
    assert_eq!(one_point.count, 1);
    assert_close(one_point.nodes[0], 0.0);
    assert_close(one_point.weights[0], 2.0);

    let three_point = rule(3).unwrap();
    assert_eq!(three_point.count, 3);
    assert_close(three_point.nodes[1], 0.0);
    assert_close(three_point.weights[1], 0.8888888888888888);

    let seven_point = rule(7).unwrap();
    assert_eq!(seven_point.count, 7);
    assert_close(seven_point.nodes[3], 0.0);
    assert_close(seven_point.weights[3], 0.4179591836734694);

    let ten_point = rule(10).unwrap();
    assert_eq!(ten_point.count, 10);
    assert_close(ten_point.nodes[0], -0.9739065285171717);
    assert_close(ten_point.weights[4], 0.2955242247147529);
}

#[test]
fn gauss_legendre_dynamic_fill_supports_higher_order_rules() {
    let mut nodes = [0.0; 20];
    let mut weights = [0.0; 20];

    fill_nodes_and_weights(20, &mut nodes, &mut weights).unwrap();

    assert_close(nodes[0], -0.9931285991850949);
    assert_close(weights[9], 0.1527533871307258);
    assert_close(nodes[0], -nodes[19]);
}

#[test]
fn disamar_gauss_division_points_scale_to_unit_and_custom_intervals() {
    let mut nodes = [0.0; 5];
    let mut weights = [0.0; 5];

    fill_disamar_div_points_01(5, &mut nodes, &mut weights).unwrap();

    let weight_sum = weights.iter().sum::<f64>();
    for index in 0..5 {
        assert!((0.0..=1.0).contains(&nodes[index]));
        if index > 0 {
            assert!(nodes[index - 1] < nodes[index]);
        }
    }
    assert_close(weight_sum, 1.0);

    fill_disamar_div_points_interval(2, 10.0, 20.0, &mut nodes[..2], &mut weights[..2]).unwrap();
    assert!(nodes[0] > 10.0);
    assert!(nodes[1] < 20.0);
    assert_close(weights[0] + weights[1], 10.0);
}
