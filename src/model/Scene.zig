pub const SpectralGrid = struct {
    start_nm: f64 = 270.0,
    end_nm: f64 = 2400.0,
    sample_count: u32 = 0,
};

pub const Atmosphere = struct {
    layer_count: u32 = 0,
    has_clouds: bool = false,
    has_aerosols: bool = false,
};

pub const Geometry = struct {
    solar_zenith_deg: f64 = 0.0,
    viewing_zenith_deg: f64 = 0.0,
    relative_azimuth_deg: f64 = 0.0,
};

pub const ObservationModel = struct {
    instrument: []const u8 = "generic",
    sampling: []const u8 = "native",
    noise_model: []const u8 = "none",
};

pub const Blueprint = struct {
    id: []const u8 = "scene-template",
    spectral_grid: SpectralGrid = .{},
    derivative_mode: []const u8 = "none",
};

pub const Scene = struct {
    id: []const u8 = "scene-0",
    atmosphere: Atmosphere = .{},
    geometry: Geometry = .{},
    spectral_grid: SpectralGrid = .{},
    observation_model: ObservationModel = .{},
};
