pub const scene = @import("input/Scene.zig");
pub const Scene = scene.Scene;
pub const absorber = @import("input/Absorber.zig");
pub const atmosphere = @import("input/Atmosphere.zig");
pub const bands = @import("input/Bands.zig");
pub const binding = @import("input/Binding.zig");
pub const geometry = @import("input/Geometry.zig");
pub const instrument = @import("input/Instrument.zig");
pub const inverse_problem = @import("input/InverseProblem.zig");
pub const measurement = @import("input/Measurement.zig");
pub const state_vector = @import("input/StateVector.zig");
pub const surface = @import("input/Surface.zig");
pub const hitran_partition_tables = @import("input/hitran_partition_tables.zig");
pub const reference_data = @import("input/ReferenceData.zig");
pub const reference = struct {
    pub const airmass_phase = @import("input/reference/airmass_phase.zig");
    pub const cia = @import("input/reference/cia.zig");
    pub const climatology = @import("input/reference/climatology.zig");
    pub const cross_sections = @import("input/reference/cross_sections.zig");
    pub const rayleigh = @import("input/reference/rayleigh.zig");
};
pub const input_reference_data = struct {
    pub const ingest = @import("input/reference_data/ingest/root.zig");
    pub const ingest_reference_assets = @import("input/reference_data/ingest/reference_assets.zig");
    pub const ingest_reference_assets_loaded_asset = @import("input/reference_data/ingest/reference_assets_loaded_asset.zig");
};

pub const disamar_reference = struct {
    pub const parser = @import("validation/disamar_reference/parser.zig");
    pub const scene = @import("validation/disamar_reference/scene.zig");
    pub const yaml = @import("validation/disamar_reference/yaml.zig");
    pub const run = @import("validation/disamar_reference/run.zig");
};

pub const common = struct {
    pub const errors = @import("common/errors.zig");
    pub const units = @import("common/units.zig");
    pub const lut_controls = @import("common/lut_controls.zig");
    pub const math = struct {
        pub const quadrature = struct {
            pub const gauss_legendre = @import("common/math/quadrature/gauss_legendre.zig");
        };
        pub const linalg = struct {
            pub const cholesky = @import("common/math/linalg/cholesky.zig");
            pub const small_dense = @import("common/math/linalg/small_dense.zig");
        };
        pub const interpolation = struct {
            pub const spline = @import("common/math/interpolation/spline.zig");
        };
    };
};

pub const forward_model = struct {
    pub const optical_properties = struct {
        const root = @import("forward_model/optical_properties/root.zig");

        pub const state = root.state;
        pub const builder = root.builder;
        pub const spectroscopy = root.spectroscopy;
        pub const evaluation = root.evaluation;
        pub const transport = root.transport;
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

        pub const shared = struct {
            pub const phase_functions = @import("forward_model/optical_properties/shared/phase_functions.zig");
            pub const band_means = @import("forward_model/optical_properties/shared/band_means.zig");
            pub const particle_profiles = @import("forward_model/optical_properties/shared/particle_profiles.zig");
        };
    };

    pub const instrument_grid = struct {
        const root = @import("forward_model/instrument_grid/root.zig");

        pub const internal = root.internal;
        pub const types = root.types;
        pub const storage = root.storage;
        pub const cache = root.cache;
        pub const forward_input = root.forward_input;
        pub const spectral_eval = root.spectral_eval;
        pub const product = root.product;
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

        pub const spectral_math = struct {
            pub const calibration = @import("forward_model/instrument_grid/spectral_math/calibration.zig");
            pub const convolution = @import("forward_model/instrument_grid/spectral_math/convolution.zig");
            pub const grid = @import("forward_model/instrument_grid/spectral_math/grid.zig");
            pub const noise = @import("forward_model/instrument_grid/spectral_math/noise.zig");
            pub const sampling = @import("forward_model/instrument_grid/spectral_math/sampling.zig");
        };
    };

    pub const radiative_transfer = struct {
        const root = @import("forward_model/radiative_transfer/root.zig");

        pub const phase_coefficient_count = root.phase_coefficient_count;
        pub const ScatteringMode = root.ScatteringMode;
        pub const RadiativeTransferControls = root.RadiativeTransferControls;
        pub const TransportFamily = root.TransportFamily;
        pub const ImplementationClass = root.ImplementationClass;
        pub const DerivativeSemantics = root.DerivativeSemantics;
        pub const Regime = root.Regime;
        pub const ExecutionMode = root.ExecutionMode;
        pub const DerivativeMode = root.DerivativeMode;
        pub const DispatchRequest = root.DispatchRequest;
        pub const Route = root.Route;
        pub const LayerInput = root.LayerInput;
        pub const SourceInterfaceInput = root.SourceInterfaceInput;
        pub const RtmQuadratureLevel = root.RtmQuadratureLevel;
        pub const RtmQuadratureGrid = root.RtmQuadratureGrid;
        pub const PseudoSphericalSample = root.PseudoSphericalSample;
        pub const PseudoSphericalGrid = root.PseudoSphericalGrid;
        pub const ForwardInput = root.ForwardInput;
        pub const ForwardResult = root.ForwardResult;
        pub const PrepareError = root.PrepareError;
        pub const ExecuteError = root.ExecuteError;
        pub const Error = root.Error;
        pub const prepareRoute = root.prepareRoute;
        pub const sourceInterfaceFromLayers = root.sourceInterfaceFromLayers;
        pub const fillSourceInterfacesFromLayers = root.fillSourceInterfacesFromLayers;

        pub const derivatives = @import("forward_model/radiative_transfer/derivatives.zig");
        pub const dispatcher = @import("forward_model/radiative_transfer/dispatcher.zig");
        pub const labos = @import("forward_model/radiative_transfer/labos/root.zig");
        pub const adding = @import("forward_model/radiative_transfer/adding/root.zig");
    };

    pub const implementations = struct {
        const root = @import("forward_model/implementations/root.zig");

        pub const Bindings = root.Bindings;
        pub const Instrument = @import("forward_model/implementations/instrument.zig");
        pub const instrument_integration = @import("forward_model/implementations/instrument/integration.zig");
        pub const Surface = @import("forward_model/implementations/surface.zig");
        pub const Transport = @import("forward_model/implementations/transport.zig");
        pub const Noise = @import("forward_model/implementations/noise.zig");

        pub fn exact() Bindings {
            return root.exact();
        }
    };
};
