use zdisamar::{
    common::errors,
    input::binding::{Binding, BindingKind, IngestRef, NamedRef},
};

#[test]
fn binding_validates_kind_specific_naming_rules() {
    assert_eq!(Binding::None.validate(), Ok(()));
    assert_eq!(Binding::Atmosphere.validate(), Ok(()));
    assert_eq!(Binding::BundleDefault.validate(), Ok(()));
    assert_eq!(
        Binding::Asset(NamedRef {
            name: "solar_spectrum".to_string(),
        })
        .validate(),
        Ok(())
    );

    assert_eq!(
        Binding::Ingest(IngestRef::from_full_name("")).validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn binding_reports_kind_name_and_enabled_state() {
    let binding = Binding::StageProduct(NamedRef {
        name: "radiance".to_string(),
    });

    assert!(binding.enabled());
    assert_eq!(binding.kind(), BindingKind::StageProduct);
    assert_eq!(binding.name(), "radiance");
    assert!(binding.ingest_reference().is_none());
}

#[test]
fn ingest_reference_splits_full_name_at_first_dot() {
    let ingest = IngestRef::from_full_name("o2a.reflectance");

    assert_eq!(ingest.full_name, "o2a.reflectance");
    assert_eq!(ingest.ingest_name, "o2a");
    assert_eq!(ingest.output_name, "reflectance");
    assert_eq!(ingest.validate(), Ok(()));
    assert_eq!(
        Binding::Ingest(ingest.clone()).ingest_reference(),
        Some(&ingest)
    );
}
