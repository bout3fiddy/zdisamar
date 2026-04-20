# Spectroscopy: Remaining Thermodynamics Gap

## Issue

The remaining spectroscopy parity gap is now narrow. The only clear real
behavior difference left in the scoped spectroscopy code is the partition
function interpolator. There is also a smaller provenance mismatch from
synthesized branch metadata. These are real issues, but they are no longer the
dominant source of the current O2A residuals.

## DISAMAR Does

### 1. Uses spline interpolation for HITRAN `Q(T)`

DISAMAR builds spline second derivatives for the partition table and evaluates
`Q(T)` and `Q(T0)` with `splint(...)` before forming `QT0/QT`:

- [vendor/disamar-fortran/src/HITRANModule.f90:777](../../../vendor/disamar-fortran/src/HITRANModule.f90:777)
- [HITRANModule.f90:783](../../../vendor/disamar-fortran/src/HITRANModule.f90:783)

```fortran
call getQtabulated(errS, hitranS, hitranS%isotopologue(1), NTtabulated, Qtabulated)
call spline (errS,  Ttabulated, Qtabulated, DSpline, status)
QT  = splint ( errS, Ttabulated, Qtabulated, DSpline, T , status)
QT0 = splint ( errS, Ttabulated, Qtabulated, DSpline, T0, status)
rapQ1 = QT0/QT
```

### 2. Uses source-backed O2A branch metadata only

The O2 strong-line filtering logic uses branch identifiers only when they are
actually parsed from the HITRAN row during DISAMAR’s O2A filtering pass:

- [vendor/disamar-fortran/src/HITRANModule.f90:1090](../../../vendor/disamar-fortran/src/HITRANModule.f90:1090)

```fortran
if ( hitranS%isotopologue(igas) == 1 .AND. ic1_read == 5 .AND. ic2_read == 1 .and. Nf_read <= 35 ) then
  ! strong lines
else
  ! weak lines
end if
```

## Zig Does

### 1. Uses linear interpolation for `Q(T)`

Zig stores the same partition tables but interpolates them linearly:

- [src/model/hitran_partition_tables.zig:436](../../../src/model/hitran_partition_tables.zig:436)
- [src/model/reference/spectroscopy/strong_lines.zig:132](../../../src/model/reference/spectroscopy/strong_lines.zig:132)

```zig
pub fn ratioT0OverT(isotopologue_code: i32, temperature_k: f64, reference_temperature_k: f64) ?f64 {
    ...
    const q_t = interpolatePartitionTable(table, temperature_k);
    const q_ref = interpolatePartitionTable(table, reference_temperature_k);
    return q_ref / @max(q_t, 1.0e-12);
}
```

```zig
const partition_ratio = hitran_partition_tables.ratioT0OverT(66, safe_temperature, Types.hitran_reference_temperature_k) orelse temperature_ratio;
state.population_t[row_index] = strong_line.population_t0 *
    partition_ratio *
    @exp(Types.hitran_hc_over_kb_cm_k * strong_line.lower_state_energy_cm1 * ((1.0 / Types.hitran_reference_temperature_k) - (1.0 / safe_temperature)));
```

### 2. Synthesizes fallback branch metadata

Zig can infer O2A branch metadata from textual fields even when the original
inline branch fields are absent:

- [src/adapters/ingest/reference_assets_formats_helpers.zig:168](../../../src/adapters/ingest/reference_assets_formats_helpers.zig:168)

```zig
pub fn fallbackVendorO2ABranchMetadata(line: []const u8, center_wavenumber_cm1: f64) !?VendorO2ABranchMetadata {
    if (center_wavenumber_cm1 < 12800.0 or center_wavenumber_cm1 > 13250.0) return null;
    ...
    return .{
        .branch_ic1 = 5,
        .branch_ic2 = 1,
        .rotational_nf = upper_nf,
    };
}
```

## Why Zig Is Wrong For Parity

### Partition function

For parity, linear `Q(T)` interpolation is simply the wrong function. DISAMAR is
using a spline-smoothed partition ratio, so Zig feeds slightly different
thermodynamic scaling into both weak and strong lines.

### Metadata provenance

For parity, synthesized branch metadata is not equivalent to source-backed
branch metadata. Even when Zig now avoids the worst weak-line exclusion bug, the
line catalog and some partition-selection surfaces still carry metadata that
DISAMAR never had as inline source fields.

## Evidence From Current Probes

### 1. Strong-state drift is small and thermodynamic in character

The first aligned physics divergence at the hotspot is now in `strong_state.csv`
and is tiny:

- `sig_moy_cm1` max diff `4.835237632506e-08`
- `population_t` max diff `1.877401249184e-06`
- `line_mixing_coefficient` max diff `6.402761754121e-08`
- `dipole_t` exact
- `mod_sig_cm1` exact

Source:

- [hotspot_75962_after_parity/diff/summary.txt](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/diff/summary.txt)

### 2. Branch metadata still differs in the line catalog

The first key mismatch in `line_catalog.csv` is still:

- vendor `branch_ic1/branch_ic2/rotational_nf = NaN/NaN/NaN`
- Zig `5/1/1`

Source:

- [hotspot_75962_after_parity/diff/summary.txt](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/diff/summary.txt)

### 3. Weak-line membership is no longer the main problem

At `759.62 nm`, vendor and Zig now keep the same contributor set:

- `vendor_only = 0`
- `yaml_only = 0`

Source:

- [hotspot_75962_after_parity/diff/weak_line_contributors_summary.txt](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/diff/weak_line_contributors_summary.txt)

## What Is Not The Main Blocker Anymore

The current evidence does **not** point to:

- broken Voigt / CPF machinery
- broken strong-line renormalization
- broken `mod_sig_cm1`
- broken `dipole_t`

Those surfaces are already essentially matched. The dominant remaining residuals
are larger and live downstream in optics-state and measurement-kernel
realization.

## Minimal Corrective Direction

1. Replace linear partition interpolation with DISAMAR-style spline evaluation
   in [src/model/hitran_partition_tables.zig](../../../src/model/hitran_partition_tables.zig).
2. Keep synthesized branch metadata out of parity-critical “vendor source
   metadata” decisions in
   [src/model/reference/spectroscopy/line_list_ops.zig](../../../src/model/reference/spectroscopy/line_list_ops.zig).
