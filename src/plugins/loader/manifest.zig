pub const ExecutionLane = enum {
    declarative,
    native,
};

pub const CapabilityDecl = struct {
    slot: []const u8,
    name: []const u8,
};

pub const PluginManifest = struct {
    schema_version: u32 = 1,
    id: []const u8,
    version: []const u8,
    lane: ExecutionLane = .declarative,
    capabilities: []const CapabilityDecl = &[_]CapabilityDecl{},

    pub fn isCompatible(self: PluginManifest, abi_version: u32) bool {
        return self.schema_version == abi_version;
    }
};
