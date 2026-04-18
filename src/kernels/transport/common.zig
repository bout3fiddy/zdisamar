//! Purpose:
//!   Stable transport common root that reexports the contract types and route
//!   helpers.

const common_types = @import("common_types.zig");
const common_route = @import("common_route.zig");

pub const phase_coefficient_count = common_types.phase_coefficient_count;
pub const ScatteringMode = common_types.ScatteringMode;
pub const RtmControls = common_types.RtmControls;
pub const TransportFamily = common_types.TransportFamily;
pub const ImplementationClass = common_types.ImplementationClass;
pub const DerivativeSemantics = common_types.DerivativeSemantics;
pub const Regime = common_types.Regime;
pub const ExecutionMode = common_types.ExecutionMode;
pub const DerivativeMode = common_types.DerivativeMode;
pub const DispatchRequest = common_types.DispatchRequest;
pub const Route = common_types.Route;
pub const LayerInput = common_types.LayerInput;
pub const SourceInterfaceInput = common_types.SourceInterfaceInput;
pub const RtmQuadratureLevel = common_types.RtmQuadratureLevel;
pub const RtmQuadratureGrid = common_types.RtmQuadratureGrid;
pub const PseudoSphericalSample = common_types.PseudoSphericalSample;
pub const PseudoSphericalGrid = common_types.PseudoSphericalGrid;
pub const ForwardInput = common_types.ForwardInput;
pub const ForwardResult = common_types.ForwardResult;
pub const PrepareError = common_types.PrepareError;
pub const ExecuteError = common_types.ExecuteError;
pub const Error = common_types.Error;

pub const prepareRoute = common_route.prepareRoute;
pub const sourceInterfaceFromLayers = common_route.sourceInterfaceFromLayers;
pub const fillSourceInterfacesFromLayers = common_route.fillSourceInterfacesFromLayers;
