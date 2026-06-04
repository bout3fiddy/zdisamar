const types = @import("types.zig");
const matrix = @import("matrix.zig");
const phase_basis = @import("phase_basis.zig");

// basis.zig -------------------------------------------------------------------------------------------------|
// Private LABOS basis facade. Re-exports fixed-size types, matrix kernels, and Plm/phase helpers used by     |
// the sibling LABOS implementation files. No runtime work happens in this file.                              |
// -----------------------------------------------------------------------------------------------------------|

pub const max_gauss = types.max_gauss;
pub const max_extra = types.max_extra;
pub const max_nmutot = types.max_nmutot;
pub const max_n2 = types.max_n2;
pub const max_phase_coef = types.max_phase_coef;

pub const Mat = types.Mat;
pub const Vec = types.Vec;
pub const Vec2 = types.Vec2;
pub const LayerRT = types.LayerRT;
pub const UDField = types.UDField;
pub const UDLocal = types.UDLocal;
pub const Geometry = types.Geometry;

pub const smul = matrix.smul;
pub const smulInto = matrix.smulInto;
pub const smulIntoKnownTraces = matrix.smulIntoKnownTraces;
pub const smulIntoKnownTracesIfNonzero = matrix.smulIntoKnownTracesIfNonzero;
pub const esmul = matrix.esmul;
pub const semul = matrix.semul;
pub const matAdd = matrix.matAdd;
pub const matAddSemul3 = matrix.matAddSemul3;
pub const smulAddSemul3 = matrix.smulAddSemul3;
pub const smulAddSemul3KnownRightTrace = matrix.smulAddSemul3KnownRightTrace;
pub const smulAddSemul3KnownRightTraceInto = matrix.smulAddSemul3KnownRightTraceInto;
pub const matAddEsmul3 = matrix.matAddEsmul3;
pub const matAddEsmul3ProductKnownNonzeroInto = matrix.matAddEsmul3ProductKnownNonzeroInto;
pub const matAddEsmul = matrix.matAddEsmul;
pub const matAddEsmulInto = matrix.matAddEsmulInto;
pub const semulAdd = matrix.semulAdd;
pub const semulAddProductKnownNonzeroInto = matrix.semulAddProductKnownNonzeroInto;
pub const semulInto = matrix.semulInto;
pub const esmulSemul = matrix.esmulSemul;
pub const esmulSemulInto = matrix.esmulSemulInto;
pub const esmulSemulSelfInto = matrix.esmulSemulSelfInto;
pub const esmulSemulAdd = matrix.esmulSemulAdd;
pub const esmulSemulAddProductKnownNonzeroInto = matrix.esmulSemulAddProductKnownNonzeroInto;
pub const esmulSemulSelfAddProductKnownNonzeroInto = matrix.esmulSemulSelfAddProductKnownNonzeroInto;
pub const qseries = matrix.qseries;
pub const qseriesKnownNonzeroProduct = matrix.qseriesKnownNonzeroProduct;
pub const qseriesKnownNonzeroProductInto = matrix.qseriesKnownNonzeroProductInto;

pub const PhaseKernel = phase_basis.PhaseKernel;
pub const PhaseKernelRow = phase_basis.PhaseKernelRow;
pub const FourierPlmBasis = phase_basis.FourierPlmBasis;
pub const fillZplusZminFromBasis = phase_basis.fillZplusZminFromBasis;
pub const fillZplusZminFromBasisLimited = phase_basis.fillZplusZminFromBasisLimited;
pub const fillZplusZminFromWeightedPhaseLimited = phase_basis.fillZplusZminFromWeightedPhaseLimited;
pub const fillZplusZminRowFromBasisLimited = phase_basis.fillZplusZminRowFromBasisLimited;
pub const fillZplusZminRowFromWeightedPhaseLimited = phase_basis.fillZplusZminRowFromWeightedPhaseLimited;
pub const fillZplusZmin = phase_basis.fillZplusZmin;
