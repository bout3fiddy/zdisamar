const std = @import("std");

pub const CloudType = enum {
    none,
    lamb_wavel_indep,
    lambertian,
    mie_scattering,
    hg_scattering,
};

pub const AerosolType = enum {
    none,
    lamb_wavel_indep,
    lambertian,
    mie_scattering,
    hg_scattering,
};

pub const AbsorberSpecies = enum {
    o3,
    trop_o3,
    strat_o3,
    no2,
    trop_no2,
    strat_no2,
    so2,
    hcho,
    bro,
    chocho,
    o2_o2,
    o2,
    h2o,
    co2,
    ch4,
    co,
    nh3,

    pub fn isLineAbsorbing(self: AbsorberSpecies) bool {
        return switch (self) {
            .o2, .h2o, .co2, .ch4, .co, .nh3 => true,
            else => false,
        };
    }

    pub fn isCrossSection(self: AbsorberSpecies) bool {
        return switch (self) {
            .o3, .trop_o3, .strat_o3, .no2, .trop_no2, .strat_no2, .so2, .hcho, .bro, .chocho, .o2_o2 => true,
            else => false,
        };
    }

    pub fn isColumnFittable(self: AbsorberSpecies) bool {
        return switch (self) {
            .o2, .o2_o2 => false,
            else => true,
        };
    }

    pub fn isProfileFittable(self: AbsorberSpecies) bool {
        return self.isColumnFittable();
    }

    pub fn hitranIndex(self: AbsorberSpecies) ?u8 {
        return switch (self) {
            .h2o => 1,
            .co2 => 2,
            .o3, .trop_o3, .strat_o3 => 3,
            .co => 5,
            .ch4 => 6,
            .o2 => 7,
            .so2 => 9,
            .no2, .trop_no2, .strat_no2 => 10,
            .nh3 => 11,
            else => null,
        };
    }

    pub fn fromVendorName(name: []const u8) ?AbsorberSpecies {
        const map = .{
            .{ "O3", .o3 },
            .{ "trop_O3", .trop_o3 },
            .{ "strat_O3", .strat_o3 },
            .{ "NO2", .no2 },
            .{ "trop_NO2", .trop_no2 },
            .{ "strat_NO2", .strat_no2 },
            .{ "SO2", .so2 },
            .{ "HCHO", .hcho },
            .{ "BrO", .bro },
            .{ "CHOCHO", .chocho },
            .{ "O2-O2", .o2_o2 },
            .{ "O2", .o2 },
            .{ "H2O", .h2o },
            .{ "CO2", .co2 },
            .{ "CH4", .ch4 },
            .{ "CO", .co },
            .{ "NH3", .nh3 },
        };
        inline for (map) |entry| {
            if (std.mem.eql(u8, name, entry[0])) return entry[1];
        }
        return null;
    }
};
