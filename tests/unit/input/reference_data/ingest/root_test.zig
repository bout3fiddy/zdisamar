const internal = @import("internal");

test "ingest package includes retained reference loaders" {
    _ = internal.input_reference_data.ingest_reference_assets;
}
