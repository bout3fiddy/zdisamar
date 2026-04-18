const std = @import("std");
const AbsorberSpecies = @import("../../o2a/support/enums.zig").AbsorberSpecies;

pub fn resolveAbsorberSpeciesName(species_name: []const u8) ?AbsorberSpecies {
    if (std.meta.stringToEnum(AbsorberSpecies, species_name)) |species| return species;
    if (std.ascii.eqlIgnoreCase(species_name, "o2_o2")) return .o2_o2;
    if (std.ascii.eqlIgnoreCase(species_name, "o2o2")) return .o2_o2;
    if (std.ascii.eqlIgnoreCase(species_name, "o2-o2")) return .o2_o2;
    return null;
}

pub fn resolvedAbsorberSpecies(absorber: anytype) ?AbsorberSpecies {
    if (absorber.resolved_species) |species| return species;
    return resolveAbsorberSpeciesName(absorber.species);
}
