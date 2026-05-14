use zdisamar::{
    common::errors::Error,
    input::{Binding, BindingKind, IngestRef, NamedRef},
};

#[test]
fn ingest_ref_splits_full_name_at_first_dot() {
    let reference = IngestRef::from_full_name("meteo.temperature.profile");

    assert_eq!(reference.full_name, "meteo.temperature.profile");
    assert_eq!(reference.ingest_name, "meteo");
    assert_eq!(reference.output_name, "temperature.profile");
    assert_eq!(reference.validate(), Ok(()));
    assert_eq!(
        IngestRef::from_full_name("missing_dot").validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn named_and_ingest_refs_validate_non_empty_names() {
    assert_eq!(
        NamedRef {
            name: "asset".to_string()
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        NamedRef {
            name: String::new()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn binding_reports_kind_name_and_enabled_state() {
    let binding = Binding::Asset(NamedRef {
        name: "aerosol".to_string(),
    });

    assert!(binding.enabled());
    assert_eq!(binding.kind(), BindingKind::Asset);
    assert_eq!(binding.name(), "aerosol");
    assert_eq!(binding.validate(), Ok(()));
    assert_eq!(Binding::None.name(), "");
    assert!(!Binding::None.enabled());
}

#[test]
fn binding_returns_ingest_reference_only_for_ingest_variant() {
    let binding = Binding::Ingest(IngestRef::from_full_name("source.product"));

    assert_eq!(binding.kind(), BindingKind::Ingest);
    assert_eq!(
        binding
            .ingest_reference()
            .map(|reference| reference.output_name.as_str()),
        Some("product")
    );
    assert_eq!(
        Binding::StageProduct(NamedRef {
            name: "stage".to_string()
        })
        .ingest_reference(),
        None
    );
}
