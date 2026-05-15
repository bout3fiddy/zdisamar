pub mod api;
pub mod common;
pub mod forward_model;
pub mod input;
pub mod output;

pub type Input = input::scene::Scene;
pub type O2AInput = input::o2a_reference::ResolvedVendorO2ACase;
pub type OpticalProperties = forward_model::optical_properties::PreparedOpticalState;
pub type Method = forward_model::method::Method;
pub type CalculationStorage =
    forward_model::instrument_grid::grid_calculation::storage::SummaryStorage;
pub type Output = forward_model::instrument_grid::InstrumentGridProduct;
pub type PreparedO2A = input::o2a_reference::VendorO2APreparedCase;
pub type O2ASessionStorage =
    forward_model::instrument_grid::grid_calculation::storage::ProductStorage;
pub type DiagnosticReport = output::SummaryReport;
pub type AtmosphericBudgetRow = output::AtmosphericBudgetRow;
pub type InstrumentResponseRow = output::InstrumentResponseRow;
pub type O2LineContributionRow = output::O2LineContributionRow;
pub type O2LineContributionTable = output::O2LineContributionTable;
pub type O2O2CiaRow = output::O2O2CiaRow;
pub type RadiativeTransferDiagnosticRow = output::RadiativeTransferDiagnosticRow;
pub type RadiativeTransferSpectrumView<'a> = output::SpectrumView<'a>;
pub type RadiativeTransferControls =
    forward_model::radiative_transfer::common_types::RadiativeTransferControls;
pub type RadiativeTransferPerformanceThresholds =
    forward_model::radiative_transfer::common_types::RadiativeTransferPerformanceThresholds;
pub type RadiativeTransferJacobian = forward_model::jacobian::Vector;

pub use output as report;

pub mod o2a {
    pub use crate::input::o2a_reference::*;
}

pub fn default_o2a_input() -> O2AInput {
    input::o2a_reference::default_input()
}

pub fn prepare_o2a(input: &O2AInput) -> Result<PreparedO2A, input::o2a_reference::RunError> {
    input::o2a_reference::prepare_resolved_vendor_o2a_case(input)
}

pub fn run_o2a(
    prepared: &PreparedO2A,
) -> Result<Output, forward_model::instrument_grid::grid_calculation::simulate::Error> {
    forward_model::instrument_grid::grid_calculation::simulate::simulate_product(
        &prepared.scene,
        prepared.route,
        &prepared.prepared,
    )
}

pub fn run_o2a_with_session_storage(
    storage: &mut O2ASessionStorage,
    prepared: &PreparedO2A,
) -> Result<Output, forward_model::instrument_grid::grid_calculation::simulate::Error> {
    let view =
        forward_model::instrument_grid::grid_calculation::product::simulate_product_with_workspace(
            storage,
            &prepared.scene,
            prepared.route,
            &prepared.prepared,
            forward_model::implementations::root::exact(),
        )?;
    Ok(view.to_owned())
}

pub fn warm_o2a_session_storage(
    storage: &mut O2ASessionStorage,
    prepared: &PreparedO2A,
) -> Result<(), forward_model::instrument_grid::grid_calculation::simulate::Error> {
    forward_model::instrument_grid::grid_calculation::product::warm_product_workspace(
        storage,
        &prepared.scene,
        prepared.route,
        &prepared.prepared,
        forward_model::implementations::root::exact(),
    )
}

pub fn run_resolved_o2a(
    input: &O2AInput,
) -> Result<input::o2a_reference::VendorO2AReflectanceCase, input::o2a_reference::RunError> {
    input::o2a_reference::run_resolved_vendor_o2a_reflectance_case(input)
}
