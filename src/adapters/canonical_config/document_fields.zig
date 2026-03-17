const std = @import("std");
const SolverMode = @import("../../core/Plan.zig").SolverMode;
const GeometryModel = @import("../../model/Geometry.zig").Model;
const SpectroscopyMode = @import("../../model/Absorber.zig").SpectroscopyMode;
const Instrument = @import("../../model/Instrument.zig").Instrument;
const InstrumentId = @import("../../model/Instrument.zig").Id;
const ObservationRegime = @import("../../model/ObservationModel.zig").ObservationRegime;
const SurfaceKind = @import("../../model/Surface.zig").Surface.Kind;
const DerivativeMode = @import("../../model/InverseProblem.zig").DerivativeMode;
const StateTransform = @import("../../model/StateVector.zig").Transform;
const ExportFormat = @import("../exporters/format.zig").ExportFormat;

pub const AssetKind = enum {
    file,
};

pub const IngestAdapter = enum {
    spectral_ascii,
};

pub const ProductKind = enum {
    measurement_space,
    state_vector,
    fitted_measurement,
    averaging_kernel,
    jacobian,
    posterior_covariance,
    result,
    diagnostics,
};

pub const Error = error{
    InvalidValue,
    UnsupportedIngestAdapter,
};

pub fn parseAssetKind(kind: []const u8) Error!AssetKind {
    if (std.mem.eql(u8, kind, "file")) return .file;
    return error.InvalidValue;
}

pub fn parseIngestAdapter(adapter: []const u8) Error!IngestAdapter {
    if (std.mem.eql(u8, adapter, "spectral_ascii")) return .spectral_ascii;
    return error.UnsupportedIngestAdapter;
}

pub fn parseSolverMode(value: []const u8) Error!SolverMode {
    if (std.mem.eql(u8, value, "scalar")) return .scalar;
    if (std.mem.eql(u8, value, "polarized")) return .polarized;
    if (std.mem.eql(u8, value, "derivative_enabled")) return .derivative_enabled;
    return error.InvalidValue;
}

pub fn parseDerivativeMode(value: []const u8) Error!DerivativeMode {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "semi_analytical")) return .semi_analytical;
    if (std.mem.eql(u8, value, "analytical_plugin")) return .analytical_plugin;
    if (std.mem.eql(u8, value, "numerical")) return .numerical;
    return error.InvalidValue;
}

pub fn parseGeometryModel(value: []const u8) Error!GeometryModel {
    if (std.mem.eql(u8, value, "plane_parallel")) return .plane_parallel;
    if (std.mem.eql(u8, value, "pseudo_spherical")) return .pseudo_spherical;
    if (std.mem.eql(u8, value, "spherical")) return .spherical;
    return error.InvalidValue;
}

pub fn parseObservationRegime(value: []const u8) Error!ObservationRegime {
    if (std.mem.eql(u8, value, "nadir")) return .nadir;
    if (std.mem.eql(u8, value, "limb")) return .limb;
    if (std.mem.eql(u8, value, "occultation")) return .occultation;
    return error.InvalidValue;
}

pub fn parseSamplingMode(value: []const u8) Error!Instrument.SamplingMode {
    return Instrument.SamplingMode.parse(value) catch error.InvalidValue;
}

pub fn parseNoiseModelKind(value: []const u8) Error!Instrument.NoiseModelKind {
    return Instrument.NoiseModelKind.parse(value) catch error.InvalidValue;
}

pub fn parseSurfaceKind(value: []const u8) Error!SurfaceKind {
    return SurfaceKind.parse(value) catch error.InvalidValue;
}

pub fn parseSpectroscopyMode(value: []const u8) Error!SpectroscopyMode {
    if (std.mem.eql(u8, value, "line_by_line")) return .line_by_line;
    if (std.mem.eql(u8, value, "cia")) return .cia;
    if (std.mem.eql(u8, value, "cross_sections")) return .cross_sections;
    return error.InvalidValue;
}

pub fn parseStateTransform(value: []const u8) Error!StateTransform {
    if (std.mem.eql(u8, value, "none")) return .none;
    if (std.mem.eql(u8, value, "log")) return .log;
    if (std.mem.eql(u8, value, "logit")) return .logit;
    return error.InvalidValue;
}

pub fn parseProductKind(value: []const u8) Error!ProductKind {
    if (std.mem.eql(u8, value, "measurement_space")) return .measurement_space;
    if (std.mem.eql(u8, value, "state_vector")) return .state_vector;
    if (std.mem.eql(u8, value, "fitted_measurement")) return .fitted_measurement;
    if (std.mem.eql(u8, value, "averaging_kernel")) return .averaging_kernel;
    if (std.mem.eql(u8, value, "jacobian")) return .jacobian;
    if (std.mem.eql(u8, value, "posterior_covariance")) return .posterior_covariance;
    if (std.mem.eql(u8, value, "result")) return .result;
    if (std.mem.eql(u8, value, "diagnostics")) return .diagnostics;
    return error.InvalidValue;
}

pub fn parseExportFormat(value: []const u8) Error!ExportFormat {
    if (std.mem.eql(u8, value, "netcdf_cf")) return .netcdf_cf;
    if (std.mem.eql(u8, value, "zarr")) return .zarr;
    return error.InvalidValue;
}

pub fn normalizeTransportProvider(solver: []const u8, provider: []const u8) []const u8 {
    if (provider.len != 0) {
        if (std.mem.eql(u8, provider, "builtin.transport_dispatcher") or std.mem.eql(u8, provider, "builtin.dispatcher")) {
            return "builtin.dispatcher";
        }
        return provider;
    }
    if (std.mem.eql(u8, solver, "dispatcher") or std.mem.eql(u8, solver, "builtin.dispatcher") or std.mem.eql(u8, solver, "builtin.transport_dispatcher")) {
        return "builtin.dispatcher";
    }
    return "builtin.dispatcher";
}

pub fn normalizeRetrievalProvider(name: []const u8, explicit_provider: ?[]const u8) ?[]const u8 {
    if (explicit_provider) |provider| return provider;
    if (std.mem.eql(u8, name, "oe")) return "builtin.oe_solver";
    if (std.mem.eql(u8, name, "doas")) return "builtin.doas_solver";
    if (std.mem.eql(u8, name, "dismas")) return "builtin.dismas_solver";
    if (name.len == 0) return null;
    return name;
}

pub fn normalizeSurfaceProvider(explicit_provider: []const u8, model: SurfaceKind) []const u8 {
    if (explicit_provider.len != 0) return explicit_provider;
    return switch (model) {
        .lambertian => "builtin.lambertian_surface",
    };
}

pub fn normalizeInstrumentProvider(explicit_provider: []const u8, instrument_id: InstrumentId) []const u8 {
    if (explicit_provider.len != 0) return explicit_provider;
    _ = instrument_id;
    return "builtin.generic_response";
}
