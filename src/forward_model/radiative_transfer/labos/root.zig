const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const execute_mod = @import("execute.zig");
const layers_mod = @import("layers.zig");
const orders_mod = @import("orders.zig");
const reflectance_mod = @import("reflectance.zig");

pub const max_gauss = basis.max_gauss;
pub const max_extra = basis.max_extra;
pub const max_nmutot = basis.max_nmutot;
pub const max_n2 = basis.max_n2;
pub const max_phase_coef = basis.max_phase_coef;

pub const Mat = basis.Mat;
pub const Vec = basis.Vec;
pub const Vec2 = basis.Vec2;
pub const Geometry = basis.Geometry;
pub const LayerRT = basis.LayerRT;
pub const UDField = basis.UDField;
pub const UDLocal = basis.UDLocal;
pub const PhaseKernel = basis.PhaseKernel;
pub const FourierPlmBasis = basis.FourierPlmBasis;
pub const fillZplusZminFromBasis = basis.fillZplusZminFromBasis;
pub const AttenArray = attenuation.AttenArray;
pub const DynamicAttenArray = attenuation.DynamicAttenArray;

pub const smul = basis.smul;
pub const esmul = basis.esmul;
pub const semul = basis.semul;
pub const matAdd = basis.matAdd;
pub const qseries = basis.qseries;
pub const fillZplusZmin = basis.fillZplusZmin;

pub const fillAttenuation = attenuation.fillAttenuation;
pub const fillAttenuationDynamic = attenuation.fillAttenuationDynamic;
pub const fillAttenuationDynamicWithGrid = attenuation.fillAttenuationDynamicWithGrid;

pub const internal = @import("internal.zig");
pub const calcRTlayersInto = layers_mod.calcRTlayersInto;
pub const calcRTlayersIntoWithBasis = layers_mod.calcRTlayersIntoWithBasis;
pub const calcRTlayers = layers_mod.calcRTlayers;
pub const fillSurface = layers_mod.fillSurface;

pub const dotGauss = orders_mod.dotGauss;
pub const OrdersWorkspace = orders_mod.OrdersWorkspace;
pub const ordersScatInto = orders_mod.ordersScatInto;

pub const calcReflectance = reflectance_mod.calcReflectance;
pub const calcIntegratedReflectance = reflectance_mod.calcIntegratedReflectance;
pub const calcIntegratedReflectanceWithBasis = reflectance_mod.calcIntegratedReflectanceWithBasis;
pub const resolvedFourierMax = reflectance_mod.resolvedFourierMax;
pub const resolvedPhaseCoefficientMax = reflectance_mod.resolvedPhaseCoefficientMax;
pub const totalScatteringOpticalDepth = reflectance_mod.totalScatteringOpticalDepth;

pub const execute = execute_mod.execute;
