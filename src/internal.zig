//! Purpose:
//!   Provide a narrow internal umbrella for helper scripts that need direct
//!   access to non-public O2A implementation modules.
//!
//! Design:
//!   This file is not re-exported from the public root. It exists only so
//!   local harnesses can bind the same internal module paths without widening
//!   the shipped library surface.

pub const scene = @import("model/Scene.zig");
pub const Scene = scene.Scene;
pub const absorber = @import("model/Absorber.zig");
pub const atmosphere = @import("model/Atmosphere.zig");
pub const instrument = @import("model/Instrument.zig");
pub const hitran_partition_tables = @import("model/hitran_partition_tables.zig");
pub const reference_data = @import("model/ReferenceData.zig");

pub const kernels = struct {
    pub const optics = struct {
        pub const preparation = @import("kernels/optics/preparation.zig");
    };

    pub const spectra = struct {
        pub const calibration = @import("kernels/spectra/calibration.zig");
    };

    pub const transport = struct {
        pub const common = @import("kernels/transport/common.zig");
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
