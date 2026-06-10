const std = @import("std");
const Scene = @import("../Scene.zig").Scene;

// solar_irradiance.zig -------------------------------------------------------------------------------------- |
// Solar irradiance source-order helper for nominal channels and instrument-integration samples.               |
//                                                                                                             |
// called by                                                                                                   |
//   spectral_forward.zig samples this while scaling each LABOS reflectance factor into radiance.              |
//   spectral_eval.zig samples this while building exact-wavelength irradiance cache rows and while gathering  |
//   nominal irradiance through integration kernels.                                                           |
//                                                                                                             |
// source order                                                                                                |
//   1. operational solar table retained on primary band support, when present                                 |
//   2. tiny bundled O2 A support table, only when the scene requested bundled defaults                        |
//   3. Planck-shaped continuum fallback scaled to the O2 A magnitude near 760 nm                              |
//                                                                                                             |
// hot path                                                                                                    |
//   Called for radiance scaling and irradiance-cache misses. The instrument-grid cache keys exact f64         |
//   wavelengths, so repeated integration offsets reuse the resolved value. This function allocates nothing    |
//   and walks the tiny bundled O2 A table only when the scene requests bundled defaults.                      |
//   Operational solar interpolation uses the table and spline state owned by input/instrument/solar_spectrum. |
//                                                                                                             |
// boundary                                                                                                    |
//   The helper always returns a positive finite floor for downstream radiance/reflectance scaling. It does    |
//   not own solar tables or prepare spline state; operational solar ownership lives in input/instrument.      |
//                                                                                                             |
// numbers                                                                                                     |
//   Bundled values are retained O2 A support samples near 760 nm. The continuum is scaled to the same         |
//   magnitude at 760 nm using a 5778 K black-body shape so out-of-band fallback stays smooth and positive.    |
// ----------------------------------------------------------------------------------------------------------- |

const bundled_o2a_solar_wavelengths_nm = [_]f64{ 755.0, 758.0, 760.01, 761.99, 764.99, 770.0, 776.0 };
const bundled_o2a_solar_irradiance = [_]f64{
    4.805854615e14,
    4.879049767e14,
    4.858697784e14,
    4.615924814e14,
    4.832478218e14,
    4.60914094e14,
    4.759839792e14,
};

pub fn irradianceAtWavelength(scene: *const Scene, wavelength_nm: f64) f64 {
    // irradianceAtWavelength -------------------------------------------------------------------------------- |
    // Resolve one positive irradiance sample from the current scene's solar source order.                     |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : radiance scaling and irradiance-cache misses for nominal/integration samples               |
    //   reads    : observation-model solar support, target wavelength, bundled support arrays                 |
    //   calls    : OperationalSolarSpectrum interpolation, bundledSolarIrradiance                             |
    //                                                                                                         |
    // fallback                                                                                                |
    //   Operational support clamps outside its table. Bundled support falls back to the Planck continuum      |
    //   outside the retained O2 A support range. The final floor keeps zero or negative source data from      |
    //   reaching reflectance/radiance scaling.                                                                |
    // ------------------------------------------------------------------------------------------------------- |

    const operational_band_support = scene.observation_model.primaryOperationalBandSupport();
    const source_irradiance = choose_source_irradiance: {
        const operational_solar_spectrum = &operational_band_support.operational_solar_spectrum;
        if (operational_solar_spectrum.enabled()) {
            const interpolated_irradiance = operational_solar_spectrum.interpolateIrradiance(wavelength_nm);
            break :choose_source_irradiance interpolated_irradiance;
        }

        const uses_bundled_default = scene.observation_model.solar_spectrum_source.kind() == .bundle_default;
        if (uses_bundled_default) {
            const bundled_irradiance =
                bundledSolarIrradiance(wavelength_nm) orelse defaultSolarContinuumIrradiance(wavelength_nm);
            break :choose_source_irradiance bundled_irradiance;
        }

        break :choose_source_irradiance defaultSolarContinuumIrradiance(wavelength_nm);
    };

    return @max(source_irradiance, 1e-6);
}

fn bundledSolarIrradiance(wavelength_nm: f64) ?f64 {
    const first_wavelength_nm = bundled_o2a_solar_wavelengths_nm[0];
    const last_wavelength_nm = bundled_o2a_solar_wavelengths_nm[bundled_o2a_solar_wavelengths_nm.len - 1];
    const outside_bundle = wavelength_nm < first_wavelength_nm or wavelength_nm > last_wavelength_nm;

    if (outside_bundle) {
        return null;
    }

    if (wavelength_nm <= first_wavelength_nm) return bundled_o2a_solar_irradiance[0];

    for (
        bundled_o2a_solar_wavelengths_nm[0 .. bundled_o2a_solar_wavelengths_nm.len - 1],
        bundled_o2a_solar_wavelengths_nm[1..],
        bundled_o2a_solar_irradiance[0 .. bundled_o2a_solar_irradiance.len - 1],
        bundled_o2a_solar_irradiance[1..],
    ) |left_nm, right_nm, left_irradiance, right_irradiance| {
        if (wavelength_nm <= right_nm) {
            const span = right_nm - left_nm;
            if (span == 0.0) return right_irradiance;

            const blend = (wavelength_nm - left_nm) / span;
            return left_irradiance + blend * (right_irradiance - left_irradiance);
        }
    }

    return bundled_o2a_solar_irradiance[bundled_o2a_solar_irradiance.len - 1];
}

fn defaultSolarContinuumIrradiance(wavelength_nm: f64) f64 {
    const reference_wavelength_nm = 760.0;
    const reference_irradiance = 4.87401e14;
    return reference_irradiance *
        planckContinuumShape(wavelength_nm, 5778.0) /
        planckContinuumShape(reference_wavelength_nm, 5778.0);
}

fn planckContinuumShape(wavelength_nm: f64, temperature_k: f64) f64 {
    const h = 6.62607015e-34;
    const c = 2.99792458e8;
    const k = 1.380649e-23;
    const wavelength_m = @max(wavelength_nm, 1.0) * 1.0e-9;
    const exponent = h * c / (wavelength_m * k * @max(temperature_k, 1.0));
    const denominator = @max(std.math.expm1(exponent), 1.0e-12);
    return (2.0 * h * c * c) /
        std.math.pow(f64, wavelength_m, 5.0) /
        denominator;
}
