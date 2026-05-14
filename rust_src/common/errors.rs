#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    OutOfMemory,
    InvalidRequest,
    MissingScene,
    MissingObservationInstrument,
}

pub type Result<T> = std::result::Result<T, Error>;
