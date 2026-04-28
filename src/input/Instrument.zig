const contract = @import("instrument/contract.zig");

pub const max_line_shape_samples = contract.max_line_shape_samples;
pub const max_line_shape_nominals = contract.max_line_shape_nominals;
pub const max_operational_refspec_temperature_coefficients = contract.max_operational_refspec_temperature_coefficients;
pub const max_operational_refspec_pressure_coefficients = contract.max_operational_refspec_pressure_coefficients;

pub const Id = contract.Id;
pub const OperationalReferenceGrid = contract.OperationalReferenceGrid;
pub const AdaptiveReferenceGrid = contract.AdaptiveReferenceGrid;
pub const OperationalSolarSpectrum = contract.OperationalSolarSpectrum;
pub const OperationalCrossSectionLut = contract.OperationalCrossSectionLut;
pub const InstrumentLineShape = contract.InstrumentLineShape;
pub const InstrumentLineShapeTable = contract.InstrumentLineShapeTable;
pub const BuiltinLineShapeKind = contract.BuiltinLineShapeKind;
pub const SpectralChannel = contract.SpectralChannel;
pub const Instrument = contract.Instrument;
