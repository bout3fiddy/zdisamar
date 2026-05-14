use zdisamar::{
    common::errors,
    input::instrument::{BuiltinLineShapeKind, Id, InstrumentLineShape, InstrumentLineShapeTable},
};

#[test]
fn instrument_id_parses_labels_and_validates_required_selection() {
    assert_eq!(Id::parse(""), Id::Unset);
    assert_eq!(Id::parse("generic"), Id::Generic);
    assert_eq!(Id::parse("tropomi").label(), "tropomi");
    assert_eq!(Id::parse("custom_lab").label(), "custom_lab");
    assert_eq!(
        Id::Unset.validate(),
        Err(errors::Error::MissingObservationInstrument)
    );
    assert_eq!(Id::Synthetic.validate(), Ok(()));
}

#[test]
fn builtin_line_shape_parses_vendor_aliases() {
    assert_eq!(
        BuiltinLineShapeKind::parse(""),
        Ok(BuiltinLineShapeKind::Gaussian)
    );
    assert_eq!(
        BuiltinLineShapeKind::parse("vendor_flat_top"),
        Ok(BuiltinLineShapeKind::FlatTopN4)
    );
    assert_eq!(
        BuiltinLineShapeKind::parse("triple_flat_top"),
        Ok(BuiltinLineShapeKind::TripleFlatTopN4)
    );
    assert_eq!(
        BuiltinLineShapeKind::parse("mystery"),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn line_shape_validates_and_writes_normalized_kernel() {
    let shape = InstrumentLineShape {
        sample_count: 3,
        offsets_nm: vec![-0.1, 0.0, 0.1],
        weights: vec![1.0, 2.0, 1.0],
    };
    assert_eq!(shape.validate(), Ok(()));

    let mut offsets = [0.0; 3];
    let mut weights = [0.0; 3];
    assert_eq!(shape.write_normalized_kernel(&mut offsets, &mut weights), 3);
    assert_eq!(offsets, [-0.1, 0.0, 0.1]);
    assert_eq!(weights, [0.25, 0.5, 0.25]);

    assert_eq!(
        InstrumentLineShape {
            sample_count: 1,
            offsets_nm: vec![0.0],
            weights: vec![-1.0],
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn line_shape_table_selects_nearest_nominal_and_normalizes_rows() {
    let mut table = InstrumentLineShapeTable {
        nominal_count: 2,
        sample_count: 3,
        nominal_wavelengths_nm: vec![760.0, 761.0],
        offsets_nm: vec![-0.1, 0.0, 0.1],
        weights: vec![1.0, 2.0, 1.0, 2.0, 2.0, 4.0],
    };
    assert_eq!(table.validate(), Ok(()));
    assert_eq!(table.nearest_nominal_index(760.8), Some(1));
    assert_eq!(table.weight_at(1, 2), 4.0);
    table.set_weight(1, 2, 2.0);
    assert_eq!(table.weight_at(1, 2), 2.0);

    let mut offsets = [0.0; 3];
    let mut weights = [0.0; 3];
    assert_eq!(
        table.write_normalized_kernel_for_nominal(760.8, &mut offsets, &mut weights),
        3
    );
    assert_eq!(offsets, [-0.1, 0.0, 0.1]);
    assert_eq!(weights, [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0]);
}
