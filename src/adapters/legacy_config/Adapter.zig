const Importer = @import("config_in_importer.zig");
const ImportToCanonical = @import("import_to_canonical.zig");
const SchemaMapper = @import("schema_mapper.zig");

pub const ParseError = Importer.ParseError;
pub const PreparedRun = SchemaMapper.PreparedRun;
pub const parse = Importer.parse;
pub const ImportWarning = ImportToCanonical.ImportWarning;
pub const ImportedDocument = ImportToCanonical.ImportedDocument;
pub const importFile = ImportToCanonical.importFile;
pub const importSource = ImportToCanonical.importSource;

test {
    _ = @import("config_in_importer.zig");
    _ = @import("import_to_canonical.zig");
    _ = @import("schema_mapper.zig");
}
