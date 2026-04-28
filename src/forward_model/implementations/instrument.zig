const provider = @import("instrument/implementation.zig");
const types = @import("instrument/types.zig");

pub const default_integration_sample_count = types.default_integration_sample_count;
pub const max_integration_sample_count = types.max_integration_sample_count;

pub const IntegrationKernel = types.IntegrationKernel;

pub const Implementation = provider.Implementation;

pub fn resolve(provider_id: []const u8) ?Implementation {
    return provider.resolve(provider_id);
}
