const types = @import("types.zig");
const matrix = @import("matrix.zig");
const phase_basis = @import("phase_basis.zig");

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
pub const esmul = matrix.esmul;
pub const semul = matrix.semul;
pub const matAdd = matrix.matAdd;
pub const matAddSemul3 = matrix.matAddSemul3;
pub const smulAddSemul3 = matrix.smulAddSemul3;
pub const matAddEsmul3 = matrix.matAddEsmul3;
pub const semulAdd = matrix.semulAdd;
pub const esmulSemulAdd = matrix.esmulSemulAdd;
pub const qseries = matrix.qseries;
pub const qseriesKnownNonzeroProduct = matrix.qseriesKnownNonzeroProduct;
pub const qseriesKnownNonzeroProductWithThreshold = matrix.qseriesKnownNonzeroProductWithThreshold;

pub const PhaseKernel = phase_basis.PhaseKernel;
pub const PhaseKernelRow = phase_basis.PhaseKernelRow;
pub const FourierPlmBasis = phase_basis.FourierPlmBasis;
pub const fillZplusZminFromBasis = phase_basis.fillZplusZminFromBasis;
pub const fillZplusZminFromBasisLimited = phase_basis.fillZplusZminFromBasisLimited;
pub const fillZplusZminRowFromBasisLimited = phase_basis.fillZplusZminRowFromBasisLimited;
pub const fillZplusZmin = phase_basis.fillZplusZmin;
