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
pub const adapters = struct {
    pub const ingest = @import("input/reference_data/ingest/root.zig");
    pub const ingest_reference_assets = @import("input/reference_data/ingest/reference_assets.zig");
    pub const ingest_reference_assets_loaded_asset = @import("input/reference_data/ingest/reference_assets_loaded_asset.zig");
    pub const o2a_parity_parser = @import("validation/disamar_reference/parser.zig");
    pub const o2a_parity_scene = @import("validation/disamar_reference/scene.zig");
};
pub const vendor_o2a_trace_support = @import("validation/disamar_reference/yaml.zig");
pub const vendor_o2a_trace_runtime = @import("validation/disamar_reference/run.zig");

pub const core = struct {
    pub const errors = @import("common/errors.zig");
    pub const units = @import("common/units.zig");
    pub const lut_controls = @import("common/lut_controls.zig");
};

pub const kernels = struct {
    pub const optics = struct {
        pub const preparation = @import("forward_model/optical_properties/root.zig");
        pub const prepare = struct {
            pub const phase_functions = @import("forward_model/optical_properties/shared/phase_functions.zig");
            pub const band_means = @import("forward_model/optical_properties/shared/band_means.zig");
            pub const particle_profiles = @import("forward_model/optical_properties/shared/particle_profiles.zig");
        };
    };

    pub const spectra = struct {
        pub const calibration = @import("forward_model/instrument_grid/spectral_math/calibration.zig");
        pub const convolution = @import("forward_model/instrument_grid/spectral_math/convolution.zig");
        pub const grid = @import("forward_model/instrument_grid/spectral_math/grid.zig");
        pub const noise = @import("forward_model/instrument_grid/spectral_math/noise.zig");
        pub const sampling = @import("forward_model/instrument_grid/spectral_math/sampling.zig");
    };

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

    pub const transport = struct {
        pub const common = @import("forward_model/radiative_transfer/root.zig");
        pub const derivatives = @import("forward_model/radiative_transfer/derivatives.zig");
        pub const dispatcher = @import("forward_model/radiative_transfer/dispatcher.zig");
        pub const labos = @import("forward_model/radiative_transfer/labos/root.zig");
        pub const measurement = @import("forward_model/instrument_grid/root.zig");
        pub const adding = @import("forward_model/radiative_transfer/adding/root.zig");
    };
};

pub const plugin_internal = struct {
    pub const providers = struct {
        const root = @import("forward_model/builtins/root.zig");

        pub const Bindings = root.Bindings;
        pub const Instrument = @import("forward_model/builtins/instrument.zig");
        pub const instrument_integration = @import("forward_model/builtins/instrument/integration.zig");
        pub const Surface = @import("forward_model/builtins/surface.zig");
        pub const Transport = @import("forward_model/builtins/transport.zig");
        pub const Noise = @import("forward_model/builtins/noise.zig");

        pub fn exact() Bindings {
            return root.exact();
        }
    };
};
