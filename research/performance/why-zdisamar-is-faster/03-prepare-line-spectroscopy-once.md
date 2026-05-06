# 03. Prepare Line Spectroscopy Once

Measured forward-time saving: `163db7e -> 5ef6c71`, 35.364130 s to 8.432518 s, saving 26.931612 s for one spectrum.

## Why This Step Exists

O2 absorption is calculated from spectroscopy lines. A line contribution depends on the line data, pressure, temperature, and wavelength. Pressure and temperature come from the atmospheric profile. They are the same for every wavelength in a single prepared O2 A scene.

That means a large part of the line calculation can be prepared once per atmospheric profile node. The forward calculation should then do only the wavelength-dependent part.

## What DISAMAR Does

DISAMAR builds absorption cross sections over pressure levels and high-resolution wavelengths. The code loops over pressure, calls the absorption routines over the wavelength grid, and then adds weak-line, strong-line, and line-mixing terms into the cross-section table.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/vendor/disamar-fortran/src/HITRANModule.f90#L161-L212)

Excerpt:

```fortran
do iP = 0, traceGasS%nalt

  T = traceGasS%temperature(iP)              ! T in K
  P = traceGasS%pressure(iP) / 1013.25d0     ! P  in atm

  call CalculatAbsXsec(errS,  T, P, XsecS%cutoff, wavelHRS%wavel(:), XsecS%Xsec(:, iP), hitranS)
  if (errorCheck(errS)) return

  if ( filterStrongLinesO2A ) then
    call CalculateLineMixingXsec(errS, T, P, waveNumbers, hitranS, SDFS, RMFS, Xsec, Xsec_LM)
    if (errorCheck(errS)) return
    if ( useLM ) then
      do iwave = 1, wavelHRS%nwavel
        XsecS%Xsec(iwave, iP) = XsecS%Xsec(iwave, iP) + Xsec(wavelHRS%nwavel+1 - iwave) &
                              + XsecS%factorLM * Xsec_LM(wavelHRS%nwavel+1 - iwave)
      end do
    else
      do iwave = 1, wavelHRS%nwavel
        XsecS%Xsec(iwave, iP) = XsecS%Xsec(iwave, iP) + Xsec(wavelHRS%nwavel + 1 - iwave)
      end do
    end if
  end if

end do ! loop over pressures
```

This is a table-building design. It is useful for DISAMAR's full executable, but for zdisamar's repeated O2 A forward calculation we can prepare the pressure/temperature part once and keep it with the prepared scene.

## What zdisamar Does

zdisamar prepares weak-line and strong-line state for each profile pressure and temperature. It stores that prepared spectroscopy state with the prepared optical scene.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/optical_properties/state_build/absorbers.zig#L154-L170)

Excerpt:

```zig
if (!loaded_profile_states) {
    if (state.profile_weak_line_states) |states| {
        const line_list = state.owned_lines.?;
        for (states, context.spectroscopy_profile_temperatures_k, context.spectroscopy_profile_pressures_hpa) |*slot, temperature_k, pressure_hpa| {
            slot.* = try line_list.prepareWeakLineState(allocator, temperature_k, pressure_hpa);
            state.profile_weak_line_state_count += 1;
        }
    }
}
if (!loaded_profile_states) {
    if (state.profile_strong_line_states) |states| {
        const line_list = state.owned_lines.?;
        for (states, context.spectroscopy_profile_temperatures_k, context.spectroscopy_profile_pressures_hpa) |*slot, temperature_k, pressure_hpa| {
            slot.* = (try line_list.prepareStrongLineState(allocator, temperature_k, pressure_hpa)).?;
            state.profile_strong_line_state_count += 1;
        }
    }
}
```

For each high-resolution wavelength, zdisamar then selects the nearby strong lines and evaluates the profile nodes using the prepared line state.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/optical_properties/state_build/state_spectroscopy.zig#L60-L87)

```zig
const wavelength_window = if (prepared_states != null)
    LineListEval.prepareStrongLineWavelengthWindow(line_list, wavelength_nm)
else
    null;
for (0..node_count) |index| {
    const evaluation = if (prepared_states) |states|
        LineListEval.totalSigmaWithPreparedStrongLineStateAndWindow(
            line_list,
            wavelength_nm,
            self.spectroscopy_profile_temperatures_k[index],
            self.spectroscopy_profile_pressures_hpa[index],
            &states[index],
            if (prepared_weak_states) |weak_states| &weak_states[index] else null,
            &wavelength_window.?,
        )
    else
        LineListEval.totalSigmaAt(
            line_list,
            wavelength_nm,
            self.spectroscopy_profile_temperatures_k[index],
            self.spectroscopy_profile_pressures_hpa[index],
        );
    cache.weak_values[index] = evaluation.weak_line_sigma_cm2_per_molecule;
    cache.strong_values[index] = evaluation.strong_line_sigma_cm2_per_molecule;
    cache.line_values[index] = evaluation.line_sigma_cm2_per_molecule;
    cache.line_mixing_values[index] = evaluation.line_mixing_sigma_cm2_per_molecule;
    cache.total_values[index] = evaluation.total_sigma_cm2_per_molecule;
}
```

The weak-line preparation stores the pressure/temperature-dependent line state once.

Source link: [GitHub source](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/input/reference/spectroscopy/line_list_ops.zig#L126-L147)

```zig
pub fn prepareWeakLineState(
    self: SpectroscopyLineList,
    allocator: Types.Allocator,
    temperature_k: f64,
    pressure_hpa: f64,
) !Types.WeakLinePreparedState {
    const pressure_scale = @max(pressure_hpa / 1013.25, Types.min_spectroscopy_pressure_atm);
    const lines = try allocator.alloc(Types.WeakLinePreparedLineState, self.lines.len);
    errdefer allocator.free(lines);
    for (self.lines, lines) |line, *slot| {
        slot.* = Physics.prepareWeakLinePreparedLineState(
            line,
            temperature_k,
            pressure_scale,
            Types.hitran_reference_temperature_k,
        );
    }
    return .{
        .line_count = self.lines.len,
        .lines = lines,
    };
}
```

## Why It Matters

Before this change, the forward calculation paid too much of the spectroscopy cost while walking the high-resolution wavelength grid. After this change, pressure/temperature-dependent line work lives in preparation, and the forward pass mostly pays for the wavelength-dependent lookup and summation. That saved about 26.93 s in the checkpoint table.
