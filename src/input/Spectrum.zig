const errors = @import("../common/errors.zig");
const units = @import("../common/units.zig");

// Spectrum.zig -----------------------------------------------------------------------------------------------|
// Public nominal wavelength-grid row carried by Scene. It is the small input-side description of how many     |
// product samples the caller wants and, when no measured wavelength vector is present, where those nominal    |
// samples are placed. Setup later expands this row into retained wavelength-sampling and forward-miss plans.  |
//                                                                                                             |
// route                                                                                                       |
//   Scene.spectral_grid                                                                                       |
//     -> Scene.validate rejects empty or invalid nominal axes                                                 |
//     -> simulate.buildSimulationSetup copies the row into grid.SpectralGrid and grid.ResolvedAxis            |
//     -> wavelength_sampling builds retained product rows and forward-cache misses                            |
//     -> output summaries, diagnostics, and validation helpers report or truncate the product sample count    |
//                                                                                                             |
// measured-wavelength boundary                                                                                |
//   SpectralGrid is the fallback uniform nominal axis. ObservationModel.measured_wavelengths_nm can replace   |
//   the effective sample locations, but Scene.validate still requires the measured vector length to match     |
//   sample_count. LUT keys hash either the uniform count or the measured-wavelength hash so retained assets   |
//   cannot be reused for a different product axis.                                                            |
//                                                                                                             |
// setup consumers                                                                                             |
//   wavelengthPlanKey hashes start_nm, end_nm, and sample_count before deciding whether ProductStorage can    |
//   reuse a wavelength plan. band_means walks the uniform axis when no operational reference grid is present. |
//   forward_layers uses the span and sample_count to form the scalar spectral quadrature weight passed to RTM.|
//                                                                                                             |
// validation contract                                                                                         |
//   common.units.WavelengthRange checks finite start/end in nanometers and start < end. This file adds the    |
//   non-empty sample-count requirement because a product grid with zero rows cannot size output buffers,      |
//   retained wavelength plans, or validation spectra.                                                         |
//                                                                                                             |
// memory                                                                                                      |
//   This is a 24 B value row with no referenced storage or deinit path. It can be copied freely in setup code;|
//   repeated wavelength loops read the prepared sampling rows derived from this public input shape.           |
// ------------------------------------------------------------------------------------------------------------|

// SpectralGrid -----------------------------------------------------------------------------------------------|
// One public spectral grid request.                                                                           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] start_nm     : f64                                                                                 |
// [ 8..15] end_nm       : f64                                                                                 |
// [16..19] sample_count : u32                                                                                 |
// [20..23] trailing padding : 4 B                                                                             |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per instance = 24 B (0.023 KiB); total = per instance * live grid count                          |
pub const SpectralGrid = struct {
    start_nm: f64 = 270.0,
    end_nm: f64 = 2400.0,
    sample_count: u32 = 0,

    pub fn validate(self: SpectralGrid) errors.Error!void {
        // SpectralGrid.validate ------------------------------------------------------------------------------|
        // Validate the nominal axis before Scene builds wavelength plans or output buffers.                   |
        //                                                                                                     |
        // checks                                                                                              |
        //   WavelengthRange : finite nanometer bounds with start_nm < end_nm                                  |
        //   sample_count    : at least one product sample                                                     |
        //                                                                                                     |
        // error map                                                                                           |
        //   unit-level InvalidRange/InvalidValue both become the public InvalidRequest error used by Scene.   |
        // ----------------------------------------------------------------------------------------------------|

        (units.WavelengthRange{
            .start_nm = self.start_nm,
            .end_nm = self.end_nm,
        }).validate() catch return errors.Error.InvalidRequest;

        if (self.sample_count == 0) {
            return errors.Error.InvalidRequest;
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|
