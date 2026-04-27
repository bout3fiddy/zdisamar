const provider = @import("instrument/provider.zig");
const types = @import("instrument/types.zig");

pub const default_integration_sample_count = types.default_integration_sample_count;
pub const max_integration_sample_count = types.max_integration_sample_count;

pub const IntegrationKernel = types.IntegrationKernel;

pub const Provider = provider.Provider;

pub fn resolve(provider_id: []const u8) ?Provider {
    return provider.resolve(provider_id);
}
