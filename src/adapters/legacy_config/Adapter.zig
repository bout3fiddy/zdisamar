//! Purpose:
//!   Re-export the legacy Config.in import adapter surface.
//!
//! Physics:
//!   The legacy adapter only translates historical flat config inputs into the
//!   typed canonical pipeline; it does not change the scientific behavior.
//!
//! Vendor:
//!   Legacy Config.in import surface.
//!
//! Design:
//!   Keep the adapter root thin so callers can migrate from the legacy config
//!   loader to the canonical document model without changing import sites.
//!
//! Invariants:
//!   The legacy import package must continue to expose the parse and import
//!   entrypoints unchanged.
//!
//! Validation:
//!   Legacy config tests import this adapter root.

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
