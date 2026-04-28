pub const scene = @import("model/Scene.zig");
pub const Scene = scene.Scene;
pub const absorber = @import("model/Absorber.zig");
pub const atmosphere = @import("model/Atmosphere.zig");
pub const instrument = @import("model/Instrument.zig");
pub const hitran_partition_tables = @import("model/hitran_partition_tables.zig");
pub const reference_data = @import("model/ReferenceData.zig");
pub const vendor_o2a_trace_support = @import("o2a/data/vendor_parity_yaml.zig");
pub const vendor_o2a_trace_runtime = @import("o2a/data/vendor_parity_runtime.zig");

pub const core = struct {
    pub const errors = @import("core/errors.zig");
    pub const units = @import("core/units.zig");
    pub const lut_controls = @import("core/lut_controls.zig");
};

pub const kernels = struct {
    pub const optics = struct {
        pub const preparation = @import("kernels/optics/preparation.zig");
        pub const prepare = struct {
            pub const phase_functions = @import("kernels/optics/prepare/phase_functions.zig");
            pub const band_means = @import("kernels/optics/prepare/band_means.zig");
        };
    };

    pub const spectra = struct {
        pub const calibration = @import("kernels/spectra/calibration.zig");
        pub const convolution = @import("kernels/spectra/convolution.zig");
        pub const grid = @import("kernels/spectra/grid.zig");
        pub const noise = @import("kernels/spectra/noise.zig");
        pub const sampling = @import("kernels/spectra/sampling.zig");
    };

    pub const quadrature = struct {
        pub const gauss_legendre = @import("kernels/quadrature/gauss_legendre.zig");
    };

    pub const linalg = struct {
        pub const cholesky = @import("kernels/linalg/cholesky.zig");
        pub const small_dense = @import("kernels/linalg/small_dense.zig");
    };

    pub const interpolation = struct {
        pub const spline = @import("kernels/interpolation/spline.zig");
    };

    pub const transport = struct {
        pub const common = @import("kernels/transport/common.zig");
        pub const derivatives = @import("kernels/transport/derivatives.zig");
        pub const dispatcher = @import("kernels/transport/dispatcher.zig");
        pub const labos = @import("kernels/transport/labos.zig");
        pub const measurement = @import("kernels/transport/measurement.zig");
    };
};

pub const plugin_internal = struct {
    pub const providers = struct {
        const root = @import("o2a/providers/root.zig");

        pub const Bindings = root.Bindings;
        pub const Instrument = @import("o2a/providers/instrument.zig");
        pub const instrument_integration = @import("o2a/providers/instrument/integration.zig");

        pub fn exact() Bindings {
            return root.exact();
        }
    };
};
