// errors.zig -------------------------------------------------------------------------------------------------|
// Shared setup/input errors for the O2 A table layer.                                                         |
// ------------------------------------------------------------------------------------------------------------|

pub const Error = error{
    EmptyAsset,
    InvalidAssetFormat,
    InvalidControl,
    InvalidRequest,
    InvalidNumber,
    InvalidO2Case,
    UnsupportedJsonInput,
};
