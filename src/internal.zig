//! Internal test-support re-exports for the repository's white-box test suites.
const zdisamar = @import("zdisamar");

pub const runtime = zdisamar.test_support.runtime;
pub const c_api = zdisamar.test_support.c_api;
pub const zig_wrappers = zdisamar.test_support.zig_wrappers;
pub const retrieval = zdisamar.test_support.retrieval;
pub const builtin_exporters_catalog = zdisamar.test_support.builtin_exporters_catalog;
pub const exporter_spec = zdisamar.test_support.exporter_spec;
pub const reference_data = zdisamar.test_support.reference_data;
pub const kernels = zdisamar.test_support.kernels;
pub const plugin_internal = zdisamar.test_support.plugin_internal;
