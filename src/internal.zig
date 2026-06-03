pub const scene = @import("input/Scene.zig");
pub const Scene = scene.Scene;
pub const absorber = @import("input/Absorber.zig");
pub const atmosphere = @import("input/Atmosphere.zig");
pub const bands = @import("input/Bands.zig");
pub const binding = @import("input/Binding.zig");
pub const geometry = @import("input/Geometry.zig");
pub const instrument = @import("input/Instrument.zig");
pub const measurement = @import("input/Measurement.zig");
pub const surface = @import("input/Surface.zig");
pub const hitran_partition_tables = @import("input/hitran_partition_tables.zig");
pub const reference_data = @import("input/ReferenceData.zig");
// layout(64-bit):
//   size: 0 B, align: 1 B
//   field storage: 0 B; padding: 0 B (0 bits)
//   footprint: no runtime field storage; namespace/type declarations only
pub const reference = struct {
    pub const airmass_phase = @import("input/reference/airmass_phase.zig");
    pub const cia = @import("input/reference/cia.zig");
    pub const climatology = @import("input/reference/climatology.zig");
    pub const cross_sections = @import("input/reference/cross_sections.zig");
    pub const rayleigh = @import("input/reference/rayleigh.zig");
    pub const spectroscopy_strong_lines = @import("input/reference/spectroscopy/strong_lines.zig");
};
// layout(64-bit):
//   size: 0 B, align: 1 B
//   field storage: 0 B; padding: 0 B (0 bits)
//   footprint: no runtime field storage; namespace/type declarations only
pub const input_reference_data = struct {
    pub const ingest_reference_assets = @import("input/reference_data/ingest/reference_assets.zig");
    pub const ingest_reference_assets_loaded_asset = @import("input/reference_data/ingest/reference_assets_loaded_asset.zig");
};

pub const o2a_reference = @import("input/o2a_reference/root.zig");
pub const optimal_estimation = @import("optimal_estimation/retrieval.zig");

// layout(64-bit):
//   size: 0 B, align: 1 B
//   field storage: 0 B; padding: 0 B (0 bits)
//   footprint: no runtime field storage; namespace/type declarations only
pub const common = struct {
    pub const errors = @import("common/errors.zig");
    pub const units = @import("common/units.zig");
    pub const lut_controls = @import("common/lut_controls.zig");
    // layout(64-bit):
    //   size: 0 B, align: 1 B
    //   field storage: 0 B; padding: 0 B (0 bits)
    //   footprint: no runtime field storage; namespace/type declarations only
    pub const math = struct {
        // layout(64-bit):
        //   size: 0 B, align: 1 B
        //   field storage: 0 B; padding: 0 B (0 bits)
        //   footprint: no runtime field storage; namespace/type declarations only
        pub const quadrature = struct {
            pub const gauss_legendre = @import("common/math/quadrature/gauss_legendre.zig");
        };
        // layout(64-bit):
        //   size: 0 B, align: 1 B
        //   field storage: 0 B; padding: 0 B (0 bits)
        //   footprint: no runtime field storage; namespace/type declarations only
        pub const linalg = struct {
            pub const cholesky = @import("common/math/linalg/cholesky.zig");
            pub const small_dense = @import("common/math/linalg/small_dense.zig");
        };
        // layout(64-bit):
        //   size: 0 B, align: 1 B
        //   field storage: 0 B; padding: 0 B (0 bits)
        //   footprint: no runtime field storage; namespace/type declarations only
        pub const interpolation = struct {
            pub const spline = @import("common/math/interpolation/spline.zig");
        };
    };
};

// layout(64-bit):
//   size: 0 B, align: 1 B
//   field storage: 0 B; padding: 0 B (0 bits)
//   footprint: no runtime field storage; namespace/type declarations only
pub const forward_model = struct {
    // instrumentation: internal test exports
    // captures: calculation telemetry, perturbation sensitivity, and trace facades
    // why: validation CLIs and unit tests need access without exposing instrumentation in the public API.
    pub const calculation_telemetry = @import("forward_model/calculation_telemetry.zig");
    pub const perturbation_sensitivity = @import("forward_model/perturbation_sensitivity.zig");
    pub const performance_trace = @import("forward_model/performance_trace.zig");
    pub const work_partition = @import("forward_model/work_partition.zig");

    // layout(64-bit):
    //   size: 0 B, align: 1 B
    //   field storage: 0 B; padding: 0 B (0 bits)
    //   footprint: no runtime field storage; namespace/type declarations only
    pub const optical_properties = struct {
        const root = @import("forward_model/optical_properties/root.zig");

        pub const state = root.state;
        pub const spectroscopy = root.spectroscopy;
        pub const evaluation = root.evaluation;
        pub const internal = root.internal;
        pub const carrier_eval = root.carrier_eval;
        pub const forward_layers = root.forward_layers;
        pub const layer_accumulation = root.layer_accumulation;
        pub const pseudo_spherical = root.pseudo_spherical;
        pub const rtm_quadrature = root.rtm_quadrature;
        pub const source_interfaces = root.source_interfaces;
        pub const shared_geometry = root.shared_geometry;
        pub const shared_carrier = root.shared_carrier;
        pub const state_spectroscopy = root.state_spectroscopy;

        pub const PreparationInputs = root.PreparationInputs;
        pub const PreparedLayer = root.PreparedLayer;
        pub const PreparedSublayer = root.PreparedSublayer;
        pub const OpticalDepthBreakdown = root.OpticalDepthBreakdown;
        pub const PreparedOpticalState = root.PreparedOpticalState;
        pub const prepare = root.prepare;

        // layout(64-bit):
        //   size: 0 B, align: 1 B
        //   field storage: 0 B; padding: 0 B (0 bits)
        //   footprint: no runtime field storage; namespace/type declarations only
        pub const shared = struct {
            pub const phase_functions = @import("forward_model/optical_properties/shared/phase_functions.zig");
            pub const band_means = @import("forward_model/optical_properties/shared/band_means.zig");
            pub const particle_profiles = @import("forward_model/optical_properties/shared/particle_profiles.zig");
        };
    };

    // layout(64-bit):
    //   size: 0 B, align: 1 B
    //   field storage: 0 B; padding: 0 B (0 bits)
    //   footprint: no runtime field storage; namespace/type declarations only
    pub const instrument_grid = struct {
        const root = @import("forward_model/instrument_grid/root.zig");

        pub const types = root.types;
        pub const storage = root.storage;
        pub const cache = root.cache;
        pub const forward_input = root.forward_input;
        pub const spectral_eval = root.spectral_eval;
        pub const simulate = root.simulate;

        pub const reflectance_export_name = root.reflectance_export_name;
        pub const fitted_reflectance_export_name = root.fitted_reflectance_export_name;
        pub const Implementations = root.Implementations;
        pub const InstrumentGridSummary = root.InstrumentGridSummary;
        pub const InstrumentGridProduct = root.InstrumentGridProduct;
        pub const InstrumentGridProductView = root.InstrumentGridProductView;
        pub const SummaryStorage = root.SummaryStorage;
        pub const ProductStorage = root.ProductStorage;
        pub const Error = root.Error;
        pub const simulateSummary = root.simulateSummary;
        pub const simulateSummaryWithWorkspace = root.simulateSummaryWithWorkspace;
        pub const simulateProduct = root.simulateProduct;
        pub const simulateProductWithWorkspace = root.simulateProductWithWorkspace;
        pub const warmProductWorkspace = root.warmProductWorkspace;
        pub const spectral_forward = @import("forward_model/instrument_grid/grid_calculation/spectral_forward.zig");

        // layout(64-bit):
        //   size: 0 B, align: 1 B
        //   field storage: 0 B; padding: 0 B (0 bits)
        //   footprint: no runtime field storage; namespace/type declarations only
        pub const spectral_math = struct {
            pub const calibration = @import("forward_model/instrument_grid/spectral_math/calibration.zig");
            pub const convolution = @import("forward_model/instrument_grid/spectral_math/convolution.zig");
            pub const grid = @import("forward_model/instrument_grid/spectral_math/grid.zig");
        };
    };

    // layout(64-bit):
    //   size: 0 B, align: 1 B
    //   field storage: 0 B; padding: 0 B (0 bits)
    //   footprint: no runtime field storage; namespace/type declarations only
    pub const radiative_transfer = struct {
        const root = @import("forward_model/radiative_transfer/root.zig");

        pub const phase_coefficient_count = root.phase_coefficient_count;
        pub const ScatteringMode = root.ScatteringMode;
        pub const RadiativeTransferPerformanceThresholds = root.RadiativeTransferPerformanceThresholds;
        pub const RadiativeTransferControls = root.RadiativeTransferControls;
        pub const TransportFamily = root.TransportFamily;
        pub const Regime = root.Regime;
        pub const ExecutionMode = root.ExecutionMode;
        pub const DerivativeMode = root.DerivativeMode;
        pub const DispatchRequest = root.DispatchRequest;
        pub const Route = root.Route;
        pub const LayerPhase = root.LayerPhase;
        pub const LayerInput = root.LayerInput;
        pub const SourceInterfaceInput = root.SourceInterfaceInput;
        pub const RtmQuadratureLevel = root.RtmQuadratureLevel;
        pub const RtmQuadratureGrid = root.RtmQuadratureGrid;
        pub const PseudoSphericalSample = root.PseudoSphericalSample;
        pub const PseudoSphericalGrid = root.PseudoSphericalGrid;
        pub const ForwardInput = root.ForwardInput;
        pub const Jacobian = root.Jacobian;
        pub const ForwardResult = root.ForwardResult;
        pub const PrepareError = root.PrepareError;
        pub const ExecuteError = root.ExecuteError;
        pub const Error = root.Error;
        pub const prepareRoute = root.prepareRoute;
        pub const execute = root.execute;
        pub const executePrepared = root.executePrepared;
        pub const executePreparedWithLabosWorkspace = root.executePreparedWithLabosWorkspace;
        pub const sourceInterfaceFromLayers = root.sourceInterfaceFromLayers;
        pub const fillSourceInterfacesFromLayers = root.fillSourceInterfacesFromLayers;

        pub const derivatives = @import("forward_model/radiative_transfer/derivatives.zig");
        pub const labos = root.labos;
        pub const labos_basis = @import("forward_model/radiative_transfer/labos/basis.zig");
        pub const labos_layers = @import("forward_model/radiative_transfer/labos/layers.zig");
    };

    // layout(64-bit):
    //   size: 0 B, align: 1 B
    //   field storage: 0 B; padding: 0 B (0 bits)
    //   footprint: no runtime field storage; namespace/type declarations only
    pub const implementations = struct {
        const root = @import("forward_model/implementations/root.zig");

        pub const Bindings = root.Bindings;
        pub const instrument_implementation = @import("forward_model/implementations/instrument/implementation.zig");
        pub const instrument_types = @import("forward_model/implementations/instrument/types.zig");
        pub const instrument_integration = @import("forward_model/implementations/instrument/integration.zig");

        pub fn exact() Bindings {
            return root.exact();
        }
    };
};

// layout(64-bit):
//   size: 0 B, align: 1 B
//   field storage: 0 B; padding: 0 B (0 bits)
//   footprint: no runtime field storage; namespace/type declarations only
pub const output = struct {
    pub const atmospheric_budget = @import("output/atmospheric_budget.zig");
    pub const o2_line_contributions = @import("output/o2_line_contributions.zig");
};
