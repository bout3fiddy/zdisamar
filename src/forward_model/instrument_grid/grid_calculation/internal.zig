// Test-access seam for measurement transport helpers.

pub const spectral_forward = @import("spectral_forward.zig");

pub const min_parallel_forward_miss_count = spectral_forward.min_parallel_forward_miss_count;
pub const preferredForwardWorkerCount = spectral_forward.preferredForwardWorkerCount;
