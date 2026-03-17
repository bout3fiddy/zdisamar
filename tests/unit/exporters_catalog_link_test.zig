const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

comptime {
    _ = zdisamar.exporters;
    _ = internal.builtin_exporters_catalog;
}
