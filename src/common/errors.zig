// errors.zig ------------------------------------------------------------------------------------------------|
// Shared typed error set for validation failures that should cross input, setup, and storage boundaries.     |
//                                                                                                            |
// used by                                                                                                    |
//   input structs when a Scene or nested control row is incomplete, inconsistent, or outside bounds          |
//   instrument/grid storage when public buffer checks compose allocation and input-validation failures       |
//   unit tests that assert invalid controls produce the expected boundary error                              |
//                                                                                                            |
// current meanings                                                                                           |
//   OutOfMemory                   : allocation or capacity growth failed                                     |
//   InvalidRequest                : caller supplied an unsupported or inconsistent configuration             |
//   MissingScene                  : public API received no Scene where one is required                       |
//   MissingObservationInstrument  : observation/instrument controls are absent for measurement output        |
//                                                                                                            |
// contract                                                                                                   |
//   Keep this set small and caller-visible. Code that parses or validates controls should return one of      |
//   these typed failures where unsupported or incomplete configuration is detected.                          |
// -----------------------------------------------------------------------------------------------------------|

pub const Error = error{
    OutOfMemory,
    InvalidRequest,
    MissingScene,
    MissingObservationInstrument,
};
