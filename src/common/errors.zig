// errors.zig -------------------------------------------------------------------------------------------------|
// Shared setup/input errors for the table layer.                                                         |
// ------------------------------------------------------------------------------------------------------------|

pub const Error = error{
    EmptyAsset,
    InvalidAssetFormat,
    InvalidControl,
    InvalidRequest,
    InvalidNumber,
    InvalidScene,
    UnsupportedJsonInput,
};
