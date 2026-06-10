const types = @import("types.zig");
const matrix = @import("matrix.zig");
const phase_basis = @import("phase_basis.zig");

// basis.zig -------------------------------------------------------------------------------------------------|
// Private LABOS alias map for stream data rows, dense matrix kernels, and Fourier phase-basis builders used  |
// by the hot transport files.                                                                                |
//                                                                                                            |
// call chain                                                                                                 |
//   layers.zig, orders.zig, reflectance.zig, attenuation.zig, and workspace.zig import this as basis.        |
//   radiative_transfer/root.zig re-exports selected aliases through the public labos namespace.              |
//   src/internal.zig exposes the same alias map to focused LABOS unit tests.                                 |
//                                                                                                            |
// owning files                                                                                               |
//   types.zig       : fixed stream limits, Mat/Vec rows, LayerRT/UD field rows, and Geometry.                |
//   matrix.zig      : small dense multiply, q-series, and scale/add kernels.                                 |
//   phase_basis.zig : Fourier PLM basis rows and Z+/Z- phase-kernel builders.                                |
//                                                                                                            |
// why keep it                                                                                                |
//   Hot LABOS files share the same terms: Mat, Vec, LayerRT, UDField, FourierPlmBasis, and Z rows. One       |
//   alias map keeps signatures short and makes those names read as one LABOS vocabulary. Removing it would   |
//   scatter the owner-file split through every transport loop without reducing runtime work.                 |
//                                                                                                            |
// runtime shape                                                                                              |
//   This is resolved at compile time. It allocates no storage, owns no buffers, dispatches no calls, and has |
//   no hidden state. The public root facade decides which of these aliases leave the LABOS package.          |
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
