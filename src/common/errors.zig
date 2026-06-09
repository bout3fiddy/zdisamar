// errors.zig ------------------------------------------------------------------------------------------------|
// Shared typed error set for validation and caller-visible source-tree failures.                             |
//                                                                                                            |
// used by                                                                                                    |
//   input structs when a Scene or nested control row is incomplete or invalid                                |
//   forward-model setup and storage code when they compose input, RTM, grid, and allocation errors           |
//                                                                                                            |
// boundary                                                                                                   |
//   These errors are deliberately small. Product code should reject bad input with one of these typed errors |
//   instead of accepting a partially ignored control or silently falling back to another physics path.       |
// -----------------------------------------------------------------------------------------------------------|

pub const Error = error{
    OutOfMemory,
    InvalidRequest,
    MissingScene,
    MissingObservationInstrument,
};
