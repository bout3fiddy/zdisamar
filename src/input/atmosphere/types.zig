// types.zig --------------------------------------------------------------------------------------------------|
// Shared atmosphere tag vocabulary for the public input model. These enums carry no payload and do no         |
// validation by themselves; they name which route the payload rows in interval_grid.zig and                   |
// fraction_control.zig should take.                                                                           |
//                                                                                                             |
// route                                                                                                       |
//   Atmosphere.zig re-exports these names as part of the stable Scene input surface.                          |
//   interval_grid.zig stores IntervalSemantics on IntervalGrid and ParticlePlacementSemantics on              |
//   IntervalPlacement, then validates the matching payload fields before vertical-grid preparation.           |
//   fraction_control.zig stores FractionTarget/FractionKind beside the fraction values and validates          |
//   whether those values are a single scalar fraction or a wavelength-dependent table.                        |
//   vertical_grid.zig and layer_accumulation.zig consume the validated tags while building prepared layer,    |
//   sublayer, aerosol, and particle support rows.                                                             |
//                                                                                                             |
// why this file exists                                                                                        |
//   The enum names are shared by several input child modules and re-exported by Atmosphere. Keeping them      |
//   here avoids making interval-grid payload layout depend on fraction-control payload layout, while the      |
//   concrete structs keep their own memory and validation comments next to the fields they store.             |
//                                                                                                             |
// enum roles                                                                                                  |
//   IntervalSemantics          : how atmosphere layers map to pressure/altitude intervals                     |
//   ParticlePlacementSemantics : how aerosol or particle placement should be interpreted                      |
//   FractionTarget             : which physical quantity receives a fractional split                          |
//   FractionKind               : whether that fraction is constant or wavelength dependent                    |
//                                                                                                             |
// hot path boundary                                                                                           |
//   RTM hot loops do not read these public tags. Setup code copies the resolved choices into prepared optical |
//   state or expands them into support rows; repeated wavelength execution consumes those prepared rows.      |
//                                                                                                             |
// memory                                                                                                      |
//   These are tag-only public enums. This file owns no buffers, referenced storage, or deinit path. When enum |
//   storage size matters, the layout boxes live on the structs that embed the tag.                            |
// ------------------------------------------------------------------------------------------------------------|

pub const IntervalSemantics = enum {
    none,
    altitude_layering_approximation,
    explicit_pressure_bounds,
};

pub const ParticlePlacementSemantics = enum {
    none,
    altitude_center_width_approximation,
    explicit_interval_bounds,
};

pub const FractionTarget = enum {
    none,
    aerosol,
};

pub const FractionKind = enum {
    none,
    wavel_independent,
    wavel_dependent,
};
