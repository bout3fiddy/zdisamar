//! Purpose:
//!   Own the retained spectral-ASCII fit-window marker compatibility rules.
//!
//! Physics:
//!   None directly; this module preserves older ingest delimiters long enough
//!   for adapters to translate them into the canonical channel structure.
//!
//! Vendor:
//!   `spectral ASCII fit-window compatibility`
//!
//! Design:
//!   Keep legacy marker strings and matching policy out of the main parser so
//!   the normal channel path stays literal.
//!
//! Invariants:
//!   Only the legacy whole-window markers are handled here; explicit channel
//!   markers remain the canonical parse path.
//!
//! Validation:
//!   Spectral ASCII parser tests cover the accepted marker combinations.

const std = @import("std");

pub fn isLegacyStartMarker(line: []const u8) bool {
    return std.mem.eql(u8, line, "start_fit_window");
}

pub fn isLegacyEndMarker(line: []const u8) bool {
    return std.mem.eql(u8, line, "end_fit_window");
}
