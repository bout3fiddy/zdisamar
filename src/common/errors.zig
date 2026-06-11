// errors.zig -------------------------------------------------------------------------------------------------|
// Shared setup/input errors for the WP2 table layer.                                                          |
// ------------------------------------------------------------------------------------------------------------|

pub const Error = error{
    EmptyAsset,
    InvalidAssetFormat,
    InvalidControl,
    InvalidNumber,
    InvalidReferenceCase,
    UnsupportedJsonInput,
};
