//! Purpose:
//!   Thin LABOS basis facade over shared types, matrix algebra, and phase basis logic.

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
pub const esmul = matrix.esmul;
pub const semul = matrix.semul;
pub const matAdd = matrix.matAdd;
pub const qseries = matrix.qseries;

pub const PhaseKernel = phase_basis.PhaseKernel;
pub const FourierPlmBasis = phase_basis.FourierPlmBasis;
pub const fillZplusZminFromBasis = phase_basis.fillZplusZminFromBasis;
pub const fillZplusZminFromBasisLimited = phase_basis.fillZplusZminFromBasisLimited;
pub const fillZplusZmin = phase_basis.fillZplusZmin;
