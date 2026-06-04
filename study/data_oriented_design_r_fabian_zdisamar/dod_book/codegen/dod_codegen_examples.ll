; ModuleID = 'BitcodeBuffer'
source_filename = "dod_codegen_examples"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-apple-macosx26.4.1-unknown"

%dod_codegen_examples.PreparedInput = type { double, double }
%dod_codegen_examples.MissRow = type { i32, i32 }
%dod_codegen_examples.ForwardResult = type { double, double }
%dod_codegen_examples.KeyPayload = type { double, double, double, double }

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local double @sumOpticalDepth(ptr nocapture nonnull readonly align 8 %0, i64 %1) local_unnamed_addr #0 {
  %.not = icmp eq i64 %1, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %2
  %min.iters.check = icmp ult i64 %1, 4
  br i1 %min.iters.check, label %.lr.ph.preheader9, label %vector.ph

vector.ph:                                        ; preds = %.lr.ph.preheader
  %n.vec = and i64 %1, -4
  %scevgep12 = getelementptr i8, ptr %0, i64 48
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv18 = phi i64 [ %lsr.iv.next19, %vector.body ], [ %n.vec, %vector.ph ]
  %lsr.iv13 = phi ptr [ %scevgep14, %vector.body ], [ %scevgep12, %vector.ph ]
  %vec.phi = phi double [ 0.000000e+00, %vector.ph ], [ %10, %vector.body ]
  %scevgep17 = getelementptr i8, ptr %lsr.iv13, i64 -48
  %scevgep16 = getelementptr i8, ptr %lsr.iv13, i64 -24
  %scevgep15 = getelementptr i8, ptr %lsr.iv13, i64 24
  %3 = load double, ptr %scevgep17, align 8
  %4 = load double, ptr %scevgep16, align 8
  %5 = load double, ptr %lsr.iv13, align 8
  %6 = load double, ptr %scevgep15, align 8
  %7 = fadd double %vec.phi, %3
  %8 = fadd double %7, %4
  %9 = fadd double %8, %5
  %10 = fadd double %9, %6
  %scevgep14 = getelementptr i8, ptr %lsr.iv13, i64 96
  %lsr.iv.next19 = add i64 %lsr.iv18, -4
  %11 = icmp eq i64 %lsr.iv.next19, 0
  br i1 %11, label %middle.block, label %vector.body, !llvm.loop !1

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %1, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %.lr.ph.preheader9

.lr.ph.preheader9:                                ; preds = %.lr.ph.preheader, %middle.block
  %.05.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %.lr.ph.preheader ]
  %.034.ph = phi double [ %10, %middle.block ], [ 0.000000e+00, %.lr.ph.preheader ]
  %12 = sub i64 %1, %.05.ph
  %13 = mul i64 %.05.ph, 24
  %scevgep = getelementptr i8, ptr %0, i64 %13
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader9, %.lr.ph
  %lsr.iv10 = phi ptr [ %scevgep, %.lr.ph.preheader9 ], [ %scevgep11, %.lr.ph ]
  %lsr.iv = phi i64 [ %12, %.lr.ph.preheader9 ], [ %lsr.iv.next, %.lr.ph ]
  %.034 = phi double [ %15, %.lr.ph ], [ %.034.ph, %.lr.ph.preheader9 ]
  %14 = load double, ptr %lsr.iv10, align 8
  %15 = fadd double %.034, %14
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep11 = getelementptr i8, ptr %lsr.iv10, i64 24
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !4

._crit_edge:                                      ; preds = %.lr.ph, %middle.block, %2
  %.03.lcssa = phi double [ 0.000000e+00, %2 ], [ %10, %middle.block ], [ %15, %.lr.ph ]
  ret double %.03.lcssa
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none) uwtable
define dso_local double @sumOpticalDepthScienceLayer(ptr nocapture nonnull readonly align 8 %0, i64 %1) local_unnamed_addr #1 {
  %.not = icmp eq i64 %1, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %2
  %min.iters.check = icmp ult i64 %1, 4
  br i1 %min.iters.check, label %.lr.ph.preheader9, label %vector.ph

vector.ph:                                        ; preds = %.lr.ph.preheader
  %n.vec = and i64 %1, -4
  %scevgep12 = getelementptr i8, ptr %0, i64 80
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv18 = phi i64 [ %lsr.iv.next19, %vector.body ], [ %n.vec, %vector.ph ]
  %lsr.iv13 = phi ptr [ %scevgep14, %vector.body ], [ %scevgep12, %vector.ph ]
  %vec.phi = phi double [ 0.000000e+00, %vector.ph ], [ %14, %vector.body ]
  %scevgep17 = getelementptr i8, ptr %lsr.iv13, i64 -64
  %scevgep16 = getelementptr i8, ptr %lsr.iv13, i64 -32
  %scevgep15 = getelementptr i8, ptr %lsr.iv13, i64 32
  %3 = load ptr, ptr %scevgep17, align 8
  %4 = load ptr, ptr %scevgep16, align 8
  %5 = load ptr, ptr %lsr.iv13, align 8
  %6 = load ptr, ptr %scevgep15, align 8
  %7 = load double, ptr %3, align 8
  %8 = load double, ptr %4, align 8
  %9 = load double, ptr %5, align 8
  %10 = load double, ptr %6, align 8
  %11 = fadd double %vec.phi, %7
  %12 = fadd double %11, %8
  %13 = fadd double %12, %9
  %14 = fadd double %13, %10
  %scevgep14 = getelementptr i8, ptr %lsr.iv13, i64 128
  %lsr.iv.next19 = add i64 %lsr.iv18, -4
  %15 = icmp eq i64 %lsr.iv.next19, 0
  br i1 %15, label %middle.block, label %vector.body, !llvm.loop !5

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %1, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %.lr.ph.preheader9

.lr.ph.preheader9:                                ; preds = %.lr.ph.preheader, %middle.block
  %.05.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %.lr.ph.preheader ]
  %.034.ph = phi double [ %14, %middle.block ], [ 0.000000e+00, %.lr.ph.preheader ]
  %16 = sub i64 %1, %.05.ph
  %17 = shl i64 %.05.ph, 5
  %18 = add nuw nsw i64 %17, 16
  %scevgep = getelementptr i8, ptr %0, i64 %18
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader9, %.lr.ph
  %lsr.iv10 = phi ptr [ %scevgep, %.lr.ph.preheader9 ], [ %scevgep11, %.lr.ph ]
  %lsr.iv = phi i64 [ %16, %.lr.ph.preheader9 ], [ %lsr.iv.next, %.lr.ph ]
  %.034 = phi double [ %21, %.lr.ph ], [ %.034.ph, %.lr.ph.preheader9 ]
  %19 = load ptr, ptr %lsr.iv10, align 8
  %20 = load double, ptr %19, align 8
  %21 = fadd double %.034, %20
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep11 = getelementptr i8, ptr %lsr.iv10, i64 32
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !6

._crit_edge:                                      ; preds = %.lr.ph, %middle.block, %2
  %.03.lcssa = phi double [ 0.000000e+00, %2 ], [ %14, %middle.block ], [ %21, %.lr.ph ]
  ret double %.03.lcssa
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local double @prepareEveryProduct(ptr nocapture nonnull readonly align 8 %0, ptr nocapture nonnull readonly align 8 %1, i64 %2) local_unnamed_addr #0 {
  %4 = alloca %dod_codegen_examples.PreparedInput, align 8
  %.not = icmp eq i64 %2, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph

.lr.ph:                                           ; preds = %3
  %.val = load double, ptr %0, align 8
  %5 = getelementptr i8, ptr %0, i64 8
  %.val3 = load double, ptr %5, align 8
  %.val4 = load double, ptr %1, align 8
  %6 = getelementptr i8, ptr %1, i64 8
  %.val5 = load double, ptr %6, align 8
  br label %7

7:                                                ; preds = %.lr.ph, %7
  %lsr.iv = phi i64 [ %2, %.lr.ph ], [ %lsr.iv.next, %7 ]
  %.09 = phi double [ 0.000000e+00, %.lr.ph ], [ %9, %7 ]
  call fastcc void @dod_codegen_examples.prepareInputForCodegen(ptr noalias %4, double %.val, double %.val3, double %.val4, double %.val5)
  %.sroa.0.0.copyload = load double, ptr %4, align 8
  %sunkaddr = getelementptr inbounds i8, ptr %4, i64 8
  %.sroa.2.0.copyload = load double, ptr %sunkaddr, align 8
  %8 = tail call fastcc double @dod_codegen_examples.runPreparedForCodegen(double %.sroa.0.0.copyload, double %.sroa.2.0.copyload)
  %9 = fadd double %.09, %8
  %lsr.iv.next = add i64 %lsr.iv, -1
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %7

._crit_edge:                                      ; preds = %7, %3
  %.0.lcssa = phi double [ 0.000000e+00, %3 ], [ %9, %7 ]
  ret double %.0.lcssa
}

; Function Attrs: mustprogress nofree noinline norecurse nosync nounwind willreturn memory(argmem: write) uwtable
define internal fastcc void @dod_codegen_examples.prepareInputForCodegen(ptr noalias nocapture nonnull writeonly initializes((0, 16)) %0, double %.0.val, double %.8.val, double %.0.val1, double %.8.val3) unnamed_addr #2 {
  %2 = fmul double %.0.val, %.0.val1
  store double %2, ptr %0, align 8
  %3 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %4 = fadd double %.8.val, %.8.val3
  store double %4, ptr %3, align 8
  ret void
}

; Function Attrs: mustprogress nofree noinline norecurse nosync nounwind willreturn memory(none) uwtable
define internal fastcc double @dod_codegen_examples.runPreparedForCodegen(double %.0.val, double %.8.val) unnamed_addr #3 {
  %1 = fadd double %.0.val, %.8.val
  ret double %1
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local double @runAlreadyPreparedProducts(ptr nocapture nonnull readonly align 8 %0, i64 %1) local_unnamed_addr #0 {
  %.not = icmp eq i64 %1, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph

.lr.ph:                                           ; preds = %2
  %.val = load double, ptr %0, align 8
  %3 = getelementptr i8, ptr %0, i64 8
  %.val3 = load double, ptr %3, align 8
  %4 = tail call fastcc double @dod_codegen_examples.runPreparedForCodegen(double %.val, double %.val3)
  %min.iters.check = icmp ult i64 %1, 4
  br i1 %min.iters.check, label %scalar.ph.preheader, label %vector.ph

vector.ph:                                        ; preds = %.lr.ph
  %n.vec = and i64 %1, -4
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv8 = phi i64 [ %lsr.iv.next9, %vector.body ], [ %n.vec, %vector.ph ]
  %vec.phi = phi double [ 0.000000e+00, %vector.ph ], [ %8, %vector.body ]
  %5 = fadd double %vec.phi, %4
  %6 = fadd double %5, %4
  %7 = fadd double %6, %4
  %8 = fadd double %7, %4
  %lsr.iv.next9 = add i64 %lsr.iv8, -4
  %9 = icmp eq i64 %lsr.iv.next9, 0
  br i1 %9, label %middle.block, label %vector.body, !llvm.loop !7

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %1, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %scalar.ph.preheader

scalar.ph.preheader:                              ; preds = %.lr.ph, %middle.block
  %.05.ph = phi double [ %8, %middle.block ], [ 0.000000e+00, %.lr.ph ]
  %.024.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %.lr.ph ]
  %10 = sub i64 %1, %.024.ph
  br label %scalar.ph

scalar.ph:                                        ; preds = %scalar.ph.preheader, %scalar.ph
  %lsr.iv = phi i64 [ %10, %scalar.ph.preheader ], [ %lsr.iv.next, %scalar.ph ]
  %.05 = phi double [ %11, %scalar.ph ], [ %.05.ph, %scalar.ph.preheader ]
  %11 = fadd double %.05, %4
  %lsr.iv.next = add i64 %lsr.iv, -1
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %scalar.ph, !llvm.loop !8

._crit_edge:                                      ; preds = %scalar.ph, %middle.block, %2
  %.0.lcssa = phi double [ 0.000000e+00, %2 ], [ %8, %middle.block ], [ %11, %scalar.ph ]
  ret double %.0.lcssa
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @fillLayerSource(ptr nocapture nonnull readonly align 8 %0, ptr nocapture nonnull writeonly align 8 %1, i64 %2, double %3) local_unnamed_addr #4 {
  %.not = icmp eq i64 %2, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %4
  %min.iters.check = icmp ult i64 %2, 9
  br i1 %min.iters.check, label %.lr.ph.preheader15, label %vector.memcheck

vector.memcheck:                                  ; preds = %.lr.ph.preheader
  %5 = shl i64 %2, 3
  %scevgep = getelementptr i8, ptr %1, i64 %5
  %6 = mul i64 %2, 24
  %7 = getelementptr i8, ptr %0, i64 %6
  %scevgep3 = getelementptr i8, ptr %7, i64 -8
  %bound0 = icmp ult ptr %1, %scevgep3
  %bound1 = icmp ult ptr %0, %scevgep
  %found.conflict = and i1 %bound0, %bound1
  br i1 %found.conflict, label %.lr.ph.preheader15, label %vector.ph

vector.ph:                                        ; preds = %vector.memcheck
  %n.mod.vf = and i64 %2, 7
  %8 = icmp eq i64 %n.mod.vf, 0
  %9 = select i1 %8, i64 8, i64 %n.mod.vf
  %n.vec = sub i64 %2, %9
  %broadcast.splatinsert = insertelement <2 x double> poison, double %3, i64 0
  %broadcast.splat = shufflevector <2 x double> %broadcast.splatinsert, <2 x double> poison, <2 x i32> zeroinitializer
  %scevgep25 = getelementptr i8, ptr %1, i64 32
  %scevgep31 = getelementptr i8, ptr %0, i64 96
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv32 = phi ptr [ %scevgep33, %vector.body ], [ %scevgep31, %vector.ph ]
  %lsr.iv26 = phi ptr [ %scevgep27, %vector.body ], [ %scevgep25, %vector.ph ]
  %lsr.iv23 = phi i64 [ %lsr.iv.next24, %vector.body ], [ %n.vec, %vector.ph ]
  %scevgep34 = getelementptr i8, ptr %lsr.iv32, i64 -96
  %scevgep36 = getelementptr i8, ptr %lsr.iv32, i64 -48
  %scevgep35 = getelementptr i8, ptr %lsr.iv32, i64 48
  %scevgep29 = getelementptr i8, ptr %lsr.iv26, i64 -32
  %ldN = call { <2 x double>, <2 x double>, <2 x double> } @llvm.aarch64.neon.ld3.v2f64.p0(ptr %scevgep34)
  %10 = extractvalue { <2 x double>, <2 x double>, <2 x double> } %ldN, 1
  %11 = extractvalue { <2 x double>, <2 x double>, <2 x double> } %ldN, 0
  %ldN37 = call { <2 x double>, <2 x double>, <2 x double> } @llvm.aarch64.neon.ld3.v2f64.p0(ptr %scevgep36)
  %12 = extractvalue { <2 x double>, <2 x double>, <2 x double> } %ldN37, 1
  %13 = extractvalue { <2 x double>, <2 x double>, <2 x double> } %ldN37, 0
  %ldN38 = call { <2 x double>, <2 x double>, <2 x double> } @llvm.aarch64.neon.ld3.v2f64.p0(ptr %lsr.iv32)
  %14 = extractvalue { <2 x double>, <2 x double>, <2 x double> } %ldN38, 1
  %15 = extractvalue { <2 x double>, <2 x double>, <2 x double> } %ldN38, 0
  %ldN39 = call { <2 x double>, <2 x double>, <2 x double> } @llvm.aarch64.neon.ld3.v2f64.p0(ptr %scevgep35)
  %16 = extractvalue { <2 x double>, <2 x double>, <2 x double> } %ldN39, 1
  %17 = extractvalue { <2 x double>, <2 x double>, <2 x double> } %ldN39, 0
  %18 = tail call <2 x double> @llvm.fma.v2f64(<2 x double> %11, <2 x double> %10, <2 x double> %broadcast.splat)
  %19 = tail call <2 x double> @llvm.fma.v2f64(<2 x double> %13, <2 x double> %12, <2 x double> %broadcast.splat)
  %20 = tail call <2 x double> @llvm.fma.v2f64(<2 x double> %15, <2 x double> %14, <2 x double> %broadcast.splat)
  %21 = tail call <2 x double> @llvm.fma.v2f64(<2 x double> %17, <2 x double> %16, <2 x double> %broadcast.splat)
  %scevgep30 = getelementptr i8, ptr %lsr.iv26, i64 -16
  %scevgep28 = getelementptr i8, ptr %lsr.iv26, i64 16
  store <2 x double> %18, ptr %scevgep29, align 8, !alias.scope !9, !noalias !12
  store <2 x double> %19, ptr %scevgep30, align 8, !alias.scope !9, !noalias !12
  store <2 x double> %20, ptr %lsr.iv26, align 8, !alias.scope !9, !noalias !12
  store <2 x double> %21, ptr %scevgep28, align 8, !alias.scope !9, !noalias !12
  %lsr.iv.next24 = add i64 %lsr.iv23, -8
  %scevgep27 = getelementptr i8, ptr %lsr.iv26, i64 64
  %scevgep33 = getelementptr i8, ptr %lsr.iv32, i64 192
  %22 = icmp eq i64 %lsr.iv.next24, 0
  br i1 %22, label %.lr.ph.preheader15, label %vector.body, !llvm.loop !14

.lr.ph.preheader15:                               ; preds = %vector.body, %vector.memcheck, %.lr.ph.preheader
  %.02.ph = phi i64 [ 0, %vector.memcheck ], [ 0, %.lr.ph.preheader ], [ %n.vec, %vector.body ]
  %23 = sub i64 %2, %.02.ph
  %24 = shl i64 %.02.ph, 3
  %scevgep16 = getelementptr i8, ptr %1, i64 %24
  %25 = mul i64 %.02.ph, 24
  %26 = add i64 %25, 8
  %scevgep19 = getelementptr i8, ptr %0, i64 %26
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader15, %.lr.ph
  %lsr.iv20 = phi ptr [ %scevgep19, %.lr.ph.preheader15 ], [ %scevgep21, %.lr.ph ]
  %lsr.iv17 = phi ptr [ %scevgep16, %.lr.ph.preheader15 ], [ %scevgep18, %.lr.ph ]
  %lsr.iv = phi i64 [ %23, %.lr.ph.preheader15 ], [ %lsr.iv.next, %.lr.ph ]
  %scevgep22 = getelementptr i8, ptr %lsr.iv20, i64 -8
  %27 = load double, ptr %scevgep22, align 8
  %28 = load double, ptr %lsr.iv20, align 8
  %29 = tail call double @llvm.fma.f64(double %27, double %28, double %3)
  store double %29, ptr %lsr.iv17, align 8
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep18 = getelementptr i8, ptr %lsr.iv17, i64 8
  %scevgep21 = getelementptr i8, ptr %lsr.iv20, i64 24
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !15

._crit_edge:                                      ; preds = %.lr.ph, %4
  ret void
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare double @llvm.fma.f64(double, double, double) #5

; Function Attrs: nofree norecurse nosync nounwind memory(write, argmem: readwrite, inaccessiblemem: none) uwtable
define dso_local i64 @appendLayerSourceChecked(ptr nocapture nonnull readonly align 8 %0, ptr nocapture nonnull align 8 %1, i64 %2, double %3) local_unnamed_addr #6 {
  %.not5 = icmp eq i64 %2, 0
  br i1 %.not5, label %.._crit_edge_crit_edge, label %.lr.ph

.._crit_edge_crit_edge:                           ; preds = %4
  %sunkaddr = getelementptr inbounds i8, ptr %1, i64 8
  %.pre7 = load i64, ptr %sunkaddr, align 8
  br label %common.ret

.lr.ph:                                           ; preds = %4
  %sunkaddr11 = getelementptr inbounds i8, ptr %1, i64 8
  %.pre = load i64, ptr %sunkaddr11, align 8
  %scevgep = getelementptr i8, ptr %0, i64 8
  br label %5

common.ret:                                       ; preds = %8, %5, %.._crit_edge_crit_edge
  %common.ret.op = phi i64 [ %.pre7, %.._crit_edge_crit_edge ], [ %6, %5 ], [ %13, %8 ]
  ret i64 %common.ret.op

5:                                                ; preds = %.lr.ph, %8
  %lsr.iv8 = phi ptr [ %scevgep, %.lr.ph ], [ %scevgep9, %8 ]
  %lsr.iv = phi i64 [ %2, %.lr.ph ], [ %lsr.iv.next, %8 ]
  %6 = phi i64 [ %.pre, %.lr.ph ], [ %13, %8 ]
  %sunkaddr12 = getelementptr inbounds i8, ptr %1, i64 16
  %7 = load i64, ptr %sunkaddr12, align 8
  %.not = icmp ult i64 %6, %7
  br i1 %.not, label %8, label %common.ret

8:                                                ; preds = %5
  %scevgep10 = getelementptr i8, ptr %lsr.iv8, i64 -8
  %.sroa.2.0.copyload = load double, ptr %lsr.iv8, align 8
  %.sroa.0.0.copyload = load double, ptr %scevgep10, align 8
  %9 = load ptr, ptr %1, align 8
  %10 = getelementptr inbounds double, ptr %9, i64 %6
  %11 = tail call double @llvm.fma.f64(double %.sroa.0.0.copyload, double %.sroa.2.0.copyload, double %3)
  store double %11, ptr %10, align 8
  %sunkaddr13 = getelementptr inbounds i8, ptr %1, i64 8
  %12 = load i64, ptr %sunkaddr13, align 8
  %13 = add nuw i64 %12, 1
  store i64 %13, ptr %sunkaddr13, align 8
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep9 = getelementptr i8, ptr %lsr.iv8, i64 24
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %common.ret, label %5
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @fillReflectance(ptr nocapture nonnull readonly align 8 %0, ptr nocapture nonnull readonly align 8 %1, ptr nocapture nonnull writeonly align 8 %2, i64 %3) local_unnamed_addr #4 {
  %.not = icmp eq i64 %3, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %4
  %min.iters.check = icmp ult i64 %3, 8
  br i1 %min.iters.check, label %.lr.ph.preheader13, label %vector.memcheck

vector.memcheck:                                  ; preds = %.lr.ph.preheader
  %5 = ptrtoint ptr %2 to i64
  %6 = ptrtoint ptr %0 to i64
  %7 = ptrtoint ptr %1 to i64
  %8 = sub i64 %5, %6
  %diff.check = icmp ult i64 %8, 64
  %9 = sub i64 %5, %7
  %diff.check4 = icmp ult i64 %9, 64
  %conflict.rdx = or i1 %diff.check, %diff.check4
  br i1 %conflict.rdx, label %.lr.ph.preheader13, label %vector.ph

vector.ph:                                        ; preds = %vector.memcheck
  %n.vec = and i64 %3, -8
  %scevgep24 = getelementptr i8, ptr %2, i64 32
  %scevgep30 = getelementptr i8, ptr %0, i64 32
  %scevgep36 = getelementptr i8, ptr %1, i64 32
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv37 = phi ptr [ %scevgep38, %vector.body ], [ %scevgep36, %vector.ph ]
  %lsr.iv31 = phi ptr [ %scevgep32, %vector.body ], [ %scevgep30, %vector.ph ]
  %lsr.iv25 = phi ptr [ %scevgep26, %vector.body ], [ %scevgep24, %vector.ph ]
  %lsr.iv22 = phi i64 [ %lsr.iv.next23, %vector.body ], [ %n.vec, %vector.ph ]
  %scevgep33 = getelementptr i8, ptr %lsr.iv31, i64 -32
  %scevgep35 = getelementptr i8, ptr %lsr.iv31, i64 -16
  %scevgep34 = getelementptr i8, ptr %lsr.iv31, i64 16
  %wide.load = load <2 x double>, ptr %scevgep33, align 8
  %wide.load5 = load <2 x double>, ptr %scevgep35, align 8
  %wide.load6 = load <2 x double>, ptr %lsr.iv31, align 8
  %wide.load7 = load <2 x double>, ptr %scevgep34, align 8
  %scevgep39 = getelementptr i8, ptr %lsr.iv37, i64 -32
  %scevgep41 = getelementptr i8, ptr %lsr.iv37, i64 -16
  %scevgep40 = getelementptr i8, ptr %lsr.iv37, i64 16
  %wide.load8 = load <2 x double>, ptr %scevgep39, align 8
  %wide.load9 = load <2 x double>, ptr %scevgep41, align 8
  %wide.load10 = load <2 x double>, ptr %lsr.iv37, align 8
  %wide.load11 = load <2 x double>, ptr %scevgep40, align 8
  %scevgep28 = getelementptr i8, ptr %lsr.iv25, i64 -32
  %10 = fcmp une <2 x double> %wide.load8, zeroinitializer
  %11 = fcmp une <2 x double> %wide.load9, zeroinitializer
  %12 = fcmp une <2 x double> %wide.load10, zeroinitializer
  %13 = fcmp une <2 x double> %wide.load11, zeroinitializer
  %14 = fdiv <2 x double> %wide.load, %wide.load8
  %15 = fdiv <2 x double> %wide.load5, %wide.load9
  %16 = fdiv <2 x double> %wide.load6, %wide.load10
  %17 = fdiv <2 x double> %wide.load7, %wide.load11
  %18 = select <2 x i1> %10, <2 x double> %14, <2 x double> zeroinitializer
  %19 = select <2 x i1> %11, <2 x double> %15, <2 x double> zeroinitializer
  %20 = select <2 x i1> %12, <2 x double> %16, <2 x double> zeroinitializer
  %21 = select <2 x i1> %13, <2 x double> %17, <2 x double> zeroinitializer
  %scevgep29 = getelementptr i8, ptr %lsr.iv25, i64 -16
  %scevgep27 = getelementptr i8, ptr %lsr.iv25, i64 16
  store <2 x double> %18, ptr %scevgep28, align 8
  store <2 x double> %19, ptr %scevgep29, align 8
  store <2 x double> %20, ptr %lsr.iv25, align 8
  store <2 x double> %21, ptr %scevgep27, align 8
  %lsr.iv.next23 = add i64 %lsr.iv22, -8
  %scevgep26 = getelementptr i8, ptr %lsr.iv25, i64 64
  %scevgep32 = getelementptr i8, ptr %lsr.iv31, i64 64
  %scevgep38 = getelementptr i8, ptr %lsr.iv37, i64 64
  %22 = icmp eq i64 %lsr.iv.next23, 0
  br i1 %22, label %middle.block, label %vector.body, !llvm.loop !16

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %3, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %.lr.ph.preheader13

.lr.ph.preheader13:                               ; preds = %vector.memcheck, %.lr.ph.preheader, %middle.block
  %.03.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %vector.memcheck ], [ 0, %.lr.ph.preheader ]
  %23 = sub i64 %3, %.03.ph
  %24 = shl i64 %.03.ph, 3
  %scevgep = getelementptr i8, ptr %2, i64 %24
  %scevgep16 = getelementptr i8, ptr %1, i64 %24
  %scevgep19 = getelementptr i8, ptr %0, i64 %24
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader13, %.lr.ph
  %lsr.iv20 = phi ptr [ %scevgep19, %.lr.ph.preheader13 ], [ %scevgep21, %.lr.ph ]
  %lsr.iv17 = phi ptr [ %scevgep16, %.lr.ph.preheader13 ], [ %scevgep18, %.lr.ph ]
  %lsr.iv14 = phi ptr [ %scevgep, %.lr.ph.preheader13 ], [ %scevgep15, %.lr.ph ]
  %lsr.iv = phi i64 [ %23, %.lr.ph.preheader13 ], [ %lsr.iv.next, %.lr.ph ]
  %25 = load double, ptr %lsr.iv20, align 8
  %26 = load double, ptr %lsr.iv17, align 8
  %27 = fcmp une double %26, 0.000000e+00
  %28 = fdiv double %25, %26
  %29 = select i1 %27, double %28, double 0.000000e+00
  store double %29, ptr %lsr.iv14, align 8
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep15 = getelementptr i8, ptr %lsr.iv14, i64 8
  %scevgep18 = getelementptr i8, ptr %lsr.iv17, i64 8
  %scevgep21 = getelementptr i8, ptr %lsr.iv20, i64 8
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !17

._crit_edge:                                      ; preds = %.lr.ph, %middle.block, %4
  ret void
}

; Function Attrs: nounwind uwtable
define dso_local double @fillReflectanceAllocateLike(ptr nocapture nonnull readonly align 8 %0, ptr nocapture nonnull readonly align 8 %1, ptr nocapture nonnull readonly align 8 %2, i64 %3) local_unnamed_addr #7 {
  %5 = load ptr, ptr %0, align 8
  %6 = tail call ptr %5(i64 %3) #11
  %.not7 = icmp eq i64 %3, 0
  br i1 %.not7, label %._crit_edge.thread, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %4
  %min.iters.check = icmp ult i64 %3, 8
  br i1 %min.iters.check, label %.lr.ph.preheader17, label %vector.memcheck

vector.memcheck:                                  ; preds = %.lr.ph.preheader
  %7 = ptrtoint ptr %6 to i64
  %8 = ptrtoint ptr %1 to i64
  %9 = ptrtoint ptr %2 to i64
  %10 = sub i64 %7, %8
  %diff.check = icmp ult i64 %10, 64
  %11 = sub i64 %7, %9
  %diff.check8 = icmp ult i64 %11, 64
  %conflict.rdx = or i1 %diff.check, %diff.check8
  br i1 %conflict.rdx, label %.lr.ph.preheader17, label %vector.ph

vector.ph:                                        ; preds = %vector.memcheck
  %n.vec = and i64 %3, -8
  %scevgep28 = getelementptr i8, ptr %6, i64 32
  %scevgep34 = getelementptr i8, ptr %1, i64 32
  %scevgep40 = getelementptr i8, ptr %2, i64 32
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv41 = phi ptr [ %scevgep42, %vector.body ], [ %scevgep40, %vector.ph ]
  %lsr.iv35 = phi ptr [ %scevgep36, %vector.body ], [ %scevgep34, %vector.ph ]
  %lsr.iv29 = phi ptr [ %scevgep30, %vector.body ], [ %scevgep28, %vector.ph ]
  %lsr.iv26 = phi i64 [ %lsr.iv.next27, %vector.body ], [ %n.vec, %vector.ph ]
  %scevgep37 = getelementptr i8, ptr %lsr.iv35, i64 -32
  %scevgep39 = getelementptr i8, ptr %lsr.iv35, i64 -16
  %scevgep38 = getelementptr i8, ptr %lsr.iv35, i64 16
  %wide.load = load <2 x double>, ptr %scevgep37, align 8
  %wide.load9 = load <2 x double>, ptr %scevgep39, align 8
  %wide.load10 = load <2 x double>, ptr %lsr.iv35, align 8
  %wide.load11 = load <2 x double>, ptr %scevgep38, align 8
  %scevgep43 = getelementptr i8, ptr %lsr.iv41, i64 -32
  %scevgep45 = getelementptr i8, ptr %lsr.iv41, i64 -16
  %scevgep44 = getelementptr i8, ptr %lsr.iv41, i64 16
  %wide.load12 = load <2 x double>, ptr %scevgep43, align 8
  %wide.load13 = load <2 x double>, ptr %scevgep45, align 8
  %wide.load14 = load <2 x double>, ptr %lsr.iv41, align 8
  %wide.load15 = load <2 x double>, ptr %scevgep44, align 8
  %scevgep32 = getelementptr i8, ptr %lsr.iv29, i64 -32
  %12 = fcmp une <2 x double> %wide.load12, zeroinitializer
  %13 = fcmp une <2 x double> %wide.load13, zeroinitializer
  %14 = fcmp une <2 x double> %wide.load14, zeroinitializer
  %15 = fcmp une <2 x double> %wide.load15, zeroinitializer
  %16 = fdiv <2 x double> %wide.load, %wide.load12
  %17 = fdiv <2 x double> %wide.load9, %wide.load13
  %18 = fdiv <2 x double> %wide.load10, %wide.load14
  %19 = fdiv <2 x double> %wide.load11, %wide.load15
  %20 = select <2 x i1> %12, <2 x double> %16, <2 x double> zeroinitializer
  %21 = select <2 x i1> %13, <2 x double> %17, <2 x double> zeroinitializer
  %22 = select <2 x i1> %14, <2 x double> %18, <2 x double> zeroinitializer
  %23 = select <2 x i1> %15, <2 x double> %19, <2 x double> zeroinitializer
  %scevgep33 = getelementptr i8, ptr %lsr.iv29, i64 -16
  %scevgep31 = getelementptr i8, ptr %lsr.iv29, i64 16
  store <2 x double> %20, ptr %scevgep32, align 8
  store <2 x double> %21, ptr %scevgep33, align 8
  store <2 x double> %22, ptr %lsr.iv29, align 8
  store <2 x double> %23, ptr %scevgep31, align 8
  %lsr.iv.next27 = add i64 %lsr.iv26, -8
  %scevgep30 = getelementptr i8, ptr %lsr.iv29, i64 64
  %scevgep36 = getelementptr i8, ptr %lsr.iv35, i64 64
  %scevgep42 = getelementptr i8, ptr %lsr.iv41, i64 64
  %24 = icmp eq i64 %lsr.iv.next27, 0
  br i1 %24, label %middle.block, label %vector.body, !llvm.loop !18

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %3, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %.lr.ph.preheader17

.lr.ph.preheader17:                               ; preds = %vector.memcheck, %.lr.ph.preheader, %middle.block
  %.06.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %vector.memcheck ], [ 0, %.lr.ph.preheader ]
  %25 = sub i64 %3, %.06.ph
  %26 = shl i64 %.06.ph, 3
  %scevgep = getelementptr i8, ptr %6, i64 %26
  %scevgep20 = getelementptr i8, ptr %2, i64 %26
  %scevgep23 = getelementptr i8, ptr %1, i64 %26
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader17, %.lr.ph
  %lsr.iv24 = phi ptr [ %scevgep23, %.lr.ph.preheader17 ], [ %scevgep25, %.lr.ph ]
  %lsr.iv21 = phi ptr [ %scevgep20, %.lr.ph.preheader17 ], [ %scevgep22, %.lr.ph ]
  %lsr.iv18 = phi ptr [ %scevgep, %.lr.ph.preheader17 ], [ %scevgep19, %.lr.ph ]
  %lsr.iv = phi i64 [ %25, %.lr.ph.preheader17 ], [ %lsr.iv.next, %.lr.ph ]
  %27 = load double, ptr %lsr.iv24, align 8
  %28 = load double, ptr %lsr.iv21, align 8
  %29 = fcmp une double %28, 0.000000e+00
  %30 = fdiv double %27, %28
  %31 = select i1 %29, double %30, double 0.000000e+00
  store double %31, ptr %lsr.iv18, align 8
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep19 = getelementptr i8, ptr %lsr.iv18, i64 8
  %scevgep22 = getelementptr i8, ptr %lsr.iv21, i64 8
  %scevgep25 = getelementptr i8, ptr %lsr.iv24, i64 8
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !19

._crit_edge.thread:                               ; preds = %4, %._crit_edge
  %32 = phi double [ %35, %._crit_edge ], [ 0.000000e+00, %4 ]
  %33 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %34 = load ptr, ptr %33, align 8
  tail call void %34(ptr nonnull align 8 %6) #11
  ret double %32

._crit_edge:                                      ; preds = %.lr.ph, %middle.block
  %35 = load double, ptr %6, align 8
  br label %._crit_edge.thread
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @fillReflectanceNoAlias(ptr noalias nocapture nonnull readonly align 8 %0, ptr noalias nocapture nonnull readonly align 8 %1, ptr noalias nocapture nonnull writeonly align 8 %2, i64 %3) local_unnamed_addr #4 {
  %.not = icmp eq i64 %3, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %4
  %min.iters.check = icmp ult i64 %3, 8
  br i1 %min.iters.check, label %.lr.ph.preheader12, label %vector.ph

vector.ph:                                        ; preds = %.lr.ph.preheader
  %n.vec = and i64 %3, -8
  %scevgep23 = getelementptr i8, ptr %2, i64 32
  %scevgep29 = getelementptr i8, ptr %0, i64 32
  %scevgep35 = getelementptr i8, ptr %1, i64 32
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv36 = phi ptr [ %scevgep37, %vector.body ], [ %scevgep35, %vector.ph ]
  %lsr.iv30 = phi ptr [ %scevgep31, %vector.body ], [ %scevgep29, %vector.ph ]
  %lsr.iv24 = phi ptr [ %scevgep25, %vector.body ], [ %scevgep23, %vector.ph ]
  %lsr.iv21 = phi i64 [ %lsr.iv.next22, %vector.body ], [ %n.vec, %vector.ph ]
  %scevgep32 = getelementptr i8, ptr %lsr.iv30, i64 -32
  %scevgep34 = getelementptr i8, ptr %lsr.iv30, i64 -16
  %scevgep33 = getelementptr i8, ptr %lsr.iv30, i64 16
  %wide.load = load <2 x double>, ptr %scevgep32, align 8
  %wide.load4 = load <2 x double>, ptr %scevgep34, align 8
  %wide.load5 = load <2 x double>, ptr %lsr.iv30, align 8
  %wide.load6 = load <2 x double>, ptr %scevgep33, align 8
  %scevgep38 = getelementptr i8, ptr %lsr.iv36, i64 -32
  %scevgep40 = getelementptr i8, ptr %lsr.iv36, i64 -16
  %scevgep39 = getelementptr i8, ptr %lsr.iv36, i64 16
  %wide.load7 = load <2 x double>, ptr %scevgep38, align 8
  %wide.load8 = load <2 x double>, ptr %scevgep40, align 8
  %wide.load9 = load <2 x double>, ptr %lsr.iv36, align 8
  %wide.load10 = load <2 x double>, ptr %scevgep39, align 8
  %scevgep27 = getelementptr i8, ptr %lsr.iv24, i64 -32
  %5 = fcmp une <2 x double> %wide.load7, zeroinitializer
  %6 = fcmp une <2 x double> %wide.load8, zeroinitializer
  %7 = fcmp une <2 x double> %wide.load9, zeroinitializer
  %8 = fcmp une <2 x double> %wide.load10, zeroinitializer
  %9 = fdiv <2 x double> %wide.load, %wide.load7
  %10 = fdiv <2 x double> %wide.load4, %wide.load8
  %11 = fdiv <2 x double> %wide.load5, %wide.load9
  %12 = fdiv <2 x double> %wide.load6, %wide.load10
  %13 = select <2 x i1> %5, <2 x double> %9, <2 x double> zeroinitializer
  %14 = select <2 x i1> %6, <2 x double> %10, <2 x double> zeroinitializer
  %15 = select <2 x i1> %7, <2 x double> %11, <2 x double> zeroinitializer
  %16 = select <2 x i1> %8, <2 x double> %12, <2 x double> zeroinitializer
  %scevgep28 = getelementptr i8, ptr %lsr.iv24, i64 -16
  %scevgep26 = getelementptr i8, ptr %lsr.iv24, i64 16
  store <2 x double> %13, ptr %scevgep27, align 8
  store <2 x double> %14, ptr %scevgep28, align 8
  store <2 x double> %15, ptr %lsr.iv24, align 8
  store <2 x double> %16, ptr %scevgep26, align 8
  %lsr.iv.next22 = add i64 %lsr.iv21, -8
  %scevgep25 = getelementptr i8, ptr %lsr.iv24, i64 64
  %scevgep31 = getelementptr i8, ptr %lsr.iv30, i64 64
  %scevgep37 = getelementptr i8, ptr %lsr.iv36, i64 64
  %17 = icmp eq i64 %lsr.iv.next22, 0
  br i1 %17, label %middle.block, label %vector.body, !llvm.loop !20

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %3, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %.lr.ph.preheader12

.lr.ph.preheader12:                               ; preds = %.lr.ph.preheader, %middle.block
  %.03.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %.lr.ph.preheader ]
  %18 = sub i64 %3, %.03.ph
  %19 = shl i64 %.03.ph, 3
  %scevgep = getelementptr i8, ptr %2, i64 %19
  %scevgep15 = getelementptr i8, ptr %1, i64 %19
  %scevgep18 = getelementptr i8, ptr %0, i64 %19
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader12, %.lr.ph
  %lsr.iv19 = phi ptr [ %scevgep18, %.lr.ph.preheader12 ], [ %scevgep20, %.lr.ph ]
  %lsr.iv16 = phi ptr [ %scevgep15, %.lr.ph.preheader12 ], [ %scevgep17, %.lr.ph ]
  %lsr.iv13 = phi ptr [ %scevgep, %.lr.ph.preheader12 ], [ %scevgep14, %.lr.ph ]
  %lsr.iv = phi i64 [ %18, %.lr.ph.preheader12 ], [ %lsr.iv.next, %.lr.ph ]
  %20 = load double, ptr %lsr.iv19, align 8
  %21 = load double, ptr %lsr.iv16, align 8
  %22 = fcmp une double %21, 0.000000e+00
  %23 = fdiv double %20, %21
  %24 = select i1 %22, double %23, double 0.000000e+00
  store double %24, ptr %lsr.iv13, align 8
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep14 = getelementptr i8, ptr %lsr.iv13, i64 8
  %scevgep17 = getelementptr i8, ptr %lsr.iv16, i64 8
  %scevgep20 = getelementptr i8, ptr %lsr.iv19, i64 8
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !21

._crit_edge:                                      ; preds = %.lr.ph, %middle.block, %4
  ret void
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @integrateIndexed(ptr nocapture nonnull readonly align 4 %0, ptr nocapture nonnull readonly align 4 %1, ptr nocapture nonnull readonly align 8 %2, ptr nocapture nonnull writeonly align 8 %3, i64 %4) local_unnamed_addr #4 {
  %.not = icmp eq i64 %4, 0
  br i1 %.not, label %._crit_edge15, label %.lr.ph14.preheader

.lr.ph14.preheader:                               ; preds = %5
  br label %.lr.ph14

.lr.ph14:                                         ; preds = %.lr.ph14.preheader, %._crit_edge
  %.0912 = phi i64 [ %18, %._crit_edge ], [ 0, %.lr.ph14.preheader ]
  %6 = getelementptr inbounds %dod_codegen_examples.MissRow, ptr %0, i64 %.0912
  %.sroa.0.0.copyload = load i32, ptr %6, align 4
  %.sroa.2.0..sroa_idx = getelementptr inbounds nuw i8, ptr %6, i64 4
  %.sroa.2.0.copyload = load i32, ptr %.sroa.2.0..sroa_idx, align 4
  %7 = zext i32 %.sroa.0.0.copyload to i64
  %8 = zext i32 %.sroa.2.0.copyload to i64
  %9 = add nuw nsw i64 %8, %7
  %.not16 = icmp eq i32 %.sroa.2.0.copyload, 0
  br i1 %.not16, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %.lr.ph14
  br label %.lr.ph

._crit_edge15:                                    ; preds = %._crit_edge, %5
  ret void

.lr.ph:                                           ; preds = %.lr.ph.preheader, %.lr.ph
  %.011 = phi i64 [ %16, %.lr.ph ], [ %7, %.lr.ph.preheader ]
  %.0810 = phi double [ %15, %.lr.ph ], [ 0.000000e+00, %.lr.ph.preheader ]
  %10 = shl nuw nsw i64 %.011, 2
  %scevgep = getelementptr i8, ptr %1, i64 %10
  %11 = load i32, ptr %scevgep, align 4
  %12 = zext i32 %11 to i64
  %13 = getelementptr inbounds nuw %dod_codegen_examples.ForwardResult, ptr %2, i64 %12
  %14 = load double, ptr %13, align 8
  %15 = fadd double %.0810, %14
  %16 = add nuw nsw i64 %.011, 1
  %17 = icmp samesign ult i64 %16, %9
  br i1 %17, label %.lr.ph, label %._crit_edge

._crit_edge:                                      ; preds = %.lr.ph, %.lr.ph14
  %.08.lcssa = phi double [ 0.000000e+00, %.lr.ph14 ], [ %15, %.lr.ph ]
  %sunkaddr = mul i64 %.0912, 8
  %sunkaddr17 = getelementptr inbounds i8, ptr %3, i64 %sunkaddr
  store double %.08.lcssa, ptr %sunkaddr17, align 8
  %18 = add nuw i64 %.0912, 1
  %exitcond.not = icmp eq i64 %18, %4
  br i1 %exitcond.not, label %._crit_edge15, label %.lr.ph14
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @integrateLinearSearch(ptr nocapture nonnull readonly align 4 %0, ptr nocapture nonnull readonly align 8 %1, ptr nocapture nonnull readonly align 8 %2, ptr nocapture nonnull readonly align 8 %3, ptr nocapture nonnull writeonly align 8 %4, i64 %5, i64 %6) local_unnamed_addr #4 {
  %.fr25 = freeze i64 %6
  %.not = icmp eq i64 %5, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph

.lr.ph:                                           ; preds = %7
  %.not26 = icmp eq i64 %.fr25, 0
  br i1 %.not26, label %.lr.ph.split.preheader, label %.lr.ph.split.us.preheader

.lr.ph.split.us.preheader:                        ; preds = %.lr.ph
  br label %.lr.ph.split.us

.lr.ph.split.preheader:                           ; preds = %.lr.ph
  br label %.lr.ph.split

.lr.ph.split.us:                                  ; preds = %.lr.ph.split.us.preheader, %._crit_edge22.split.us.us
  %.01324.us = phi i64 [ %12, %._crit_edge22.split.us.us ], [ 0, %.lr.ph.split.us.preheader ]
  %8 = getelementptr inbounds %dod_codegen_examples.MissRow, ptr %0, i64 %.01324.us
  %.sroa.0.0.copyload.us = load i32, ptr %8, align 4
  %.sroa.2.0..sroa_idx.us = getelementptr inbounds nuw i8, ptr %8, i64 4
  %.sroa.2.0.copyload.us = load i32, ptr %.sroa.2.0..sroa_idx.us, align 4
  %9 = zext i32 %.sroa.0.0.copyload.us to i64
  %10 = zext i32 %.sroa.2.0.copyload.us to i64
  %11 = add nuw nsw i64 %10, %9
  %.not28 = icmp eq i32 %.sroa.2.0.copyload.us, 0
  br i1 %.not28, label %._crit_edge22.split.us.us, label %.lr.ph.us.us.preheader

.lr.ph.us.us.preheader:                           ; preds = %.lr.ph.split.us
  br label %.lr.ph.us.us

._crit_edge22.split.us.us:                        ; preds = %._crit_edge.us.us, %.lr.ph.split.us
  %.014.lcssa.us = phi double [ 0.000000e+00, %.lr.ph.split.us ], [ %23, %._crit_edge.us.us ]
  %sunkaddr = mul i64 %.01324.us, 8
  %sunkaddr42 = getelementptr inbounds i8, ptr %4, i64 %sunkaddr
  store double %.014.lcssa.us, ptr %sunkaddr42, align 8
  %12 = add nuw i64 %.01324.us, 1
  %exitcond31.not = icmp eq i64 %12, %5
  br i1 %exitcond31.not, label %._crit_edge, label %.lr.ph.split.us

.lr.ph.us.us:                                     ; preds = %.lr.ph.us.us.preheader, %._crit_edge.us.us
  %.01219.us.us = phi i64 [ %24, %._crit_edge.us.us ], [ %9, %.lr.ph.us.us.preheader ]
  %.01418.us.us = phi double [ %23, %._crit_edge.us.us ], [ 0.000000e+00, %.lr.ph.us.us.preheader ]
  %13 = getelementptr inbounds nuw double, ptr %1, i64 %.01219.us.us
  %14 = load double, ptr %13, align 8
  br label %15

15:                                               ; preds = %19, %.lr.ph.us.us
  %.015.us.us = phi i64 [ 0, %.lr.ph.us.us ], [ %20, %19 ]
  %16 = shl i64 %.015.us.us, 3
  %scevgep = getelementptr i8, ptr %2, i64 %16
  %17 = load double, ptr %scevgep, align 8
  %18 = fcmp oeq double %17, %14
  br i1 %18, label %._crit_edge.us.us, label %19

19:                                               ; preds = %15
  %20 = add nuw i64 %.015.us.us, 1
  %exitcond.not = icmp eq i64 %.fr25, %20
  br i1 %exitcond.not, label %._crit_edge.us.us, label %15

._crit_edge.us.us:                                ; preds = %15, %19
  %.0.lcssa.us.us = phi i64 [ %.fr25, %19 ], [ %.015.us.us, %15 ]
  %21 = getelementptr inbounds %dod_codegen_examples.ForwardResult, ptr %3, i64 %.0.lcssa.us.us
  %22 = load double, ptr %21, align 8
  %23 = fadd double %.01418.us.us, %22
  %24 = add nuw nsw i64 %.01219.us.us, 1
  %25 = icmp samesign ult i64 %24, %11
  br i1 %25, label %.lr.ph.us.us, label %._crit_edge22.split.us.us

.lr.ph.split:                                     ; preds = %.lr.ph.split.preheader, %._crit_edge22.split
  %.01324 = phi i64 [ %35, %._crit_edge22.split ], [ 0, %.lr.ph.split.preheader ]
  %26 = getelementptr inbounds %dod_codegen_examples.MissRow, ptr %0, i64 %.01324
  %.sroa.0.0.copyload = load i32, ptr %26, align 4
  %.sroa.2.0..sroa_idx = getelementptr inbounds nuw i8, ptr %26, i64 4
  %.sroa.2.0.copyload = load i32, ptr %.sroa.2.0..sroa_idx, align 4
  %27 = zext i32 %.sroa.0.0.copyload to i64
  %28 = zext i32 %.sroa.2.0.copyload to i64
  %29 = add nuw nsw i64 %28, %27
  %.not27 = icmp eq i32 %.sroa.2.0.copyload, 0
  br i1 %.not27, label %._crit_edge22.split, label %.lr.ph21

.lr.ph21:                                         ; preds = %.lr.ph.split
  %30 = load double, ptr %3, align 8
  br label %31

._crit_edge:                                      ; preds = %._crit_edge22.split.us.us, %._crit_edge22.split, %7
  ret void

31:                                               ; preds = %.lr.ph21, %31
  %.01219 = phi i64 [ %27, %.lr.ph21 ], [ %33, %31 ]
  %.01418 = phi double [ 0.000000e+00, %.lr.ph21 ], [ %32, %31 ]
  %32 = fadd double %.01418, %30
  %33 = add nuw nsw i64 %.01219, 1
  %34 = icmp samesign ult i64 %33, %29
  br i1 %34, label %31, label %._crit_edge22.split

._crit_edge22.split:                              ; preds = %31, %.lr.ph.split
  %.014.lcssa = phi double [ 0.000000e+00, %.lr.ph.split ], [ %32, %31 ]
  %sunkaddr43 = mul i64 %.01324, 8
  %sunkaddr44 = getelementptr inbounds i8, ptr %4, i64 %sunkaddr43
  store double %.014.lcssa, ptr %sunkaddr44, align 8
  %35 = add nuw i64 %.01324, 1
  %exitcond32.not = icmp eq i64 %35, %5
  br i1 %exitcond32.not, label %._crit_edge, label %.lr.ph.split
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local i64 @lowerBound(ptr nocapture nonnull readonly align 8 %0, i64 %1, double %2) local_unnamed_addr #0 {
  %.not = icmp eq i64 %1, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %3
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %.lr.ph
  %.09 = phi i64 [ %.1, %.lr.ph ], [ %1, %.lr.ph.preheader ]
  %.068 = phi i64 [ %.17, %.lr.ph ], [ 0, %.lr.ph.preheader ]
  %4 = sub nuw i64 %.09, %.068
  %5 = lshr i64 %4, 1
  %6 = add nuw i64 %5, %.068
  %7 = getelementptr inbounds double, ptr %0, i64 %6
  %8 = load double, ptr %7, align 8
  %9 = fcmp olt double %8, %2
  %10 = add nuw i64 %6, 1
  %.17 = select i1 %9, i64 %10, i64 %.068
  %.1 = select i1 %9, i64 %.09, i64 %6
  %11 = icmp ult i64 %.17, %.1
  br i1 %11, label %.lr.ph, label %._crit_edge

._crit_edge:                                      ; preds = %.lr.ph, %3
  %.06.lcssa = phi i64 [ 0, %3 ], [ %.17, %.lr.ph ]
  ret i64 %.06.lcssa
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none) uwtable
define dso_local i64 @lowerBoundInModel(ptr nocapture nonnull readonly align 8 %0, double %1) local_unnamed_addr #1 {
  %3 = getelementptr inbounds nuw i8, ptr %0, i64 8
  %4 = load i64, ptr %3, align 8
  %5 = load ptr, ptr %0, align 8
  %.not = icmp eq i64 %4, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %2
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %.lr.ph
  %.09 = phi i64 [ %.1, %.lr.ph ], [ %4, %.lr.ph.preheader ]
  %.068 = phi i64 [ %.17, %.lr.ph ], [ 0, %.lr.ph.preheader ]
  %6 = sub nuw i64 %.09, %.068
  %7 = lshr i64 %6, 1
  %8 = add nuw i64 %7, %.068
  %9 = getelementptr inbounds double, ptr %5, i64 %8
  %10 = load double, ptr %9, align 8
  %11 = fcmp olt double %10, %1
  %12 = add nuw i64 %8, 1
  %.17 = select i1 %11, i64 %12, i64 %.068
  %.1 = select i1 %11, i64 %.09, i64 %8
  %13 = icmp ult i64 %.17, %.1
  br i1 %13, label %.lr.ph, label %._crit_edge

._crit_edge:                                      ; preds = %.lr.ph, %2
  %.06.lcssa = phi i64 [ 0, %2 ], [ %.17, %.lr.ph ]
  ret i64 %.06.lcssa
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local %dod_codegen_examples.KeyPayload @lookupPayloadLinear(ptr nocapture nonnull readonly align 8 %0, i64 %1, double %2) local_unnamed_addr #0 {
  %.not = icmp eq i64 %1, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %3
  %scevgep = getelementptr i8, ptr %0, i64 16
  br label %.lr.ph

common.ret:                                       ; preds = %7, %._crit_edge
  %.unpack.pn = phi double [ %.unpack, %._crit_edge ], [ %.sroa.0.0.copyload, %7 ]
  %.unpack3.pn.in = phi ptr [ %.elt2, %._crit_edge ], [ %scevgep23, %7 ]
  %.unpack5.pn.in = phi ptr [ %.elt4, %._crit_edge ], [ %lsr.iv, %7 ]
  %.unpack7.pn.in = phi ptr [ %.elt6, %._crit_edge ], [ %scevgep24, %7 ]
  %.unpack7.pn = load double, ptr %.unpack7.pn.in, align 8
  %.unpack5.pn = load double, ptr %.unpack5.pn.in, align 8
  %.unpack3.pn = load double, ptr %.unpack3.pn.in, align 8
  %.pn9 = insertvalue %dod_codegen_examples.KeyPayload poison, double %.unpack.pn, 0
  %.pn8 = insertvalue %dod_codegen_examples.KeyPayload %.pn9, double %.unpack3.pn, 1
  %.pn = insertvalue %dod_codegen_examples.KeyPayload %.pn8, double %.unpack5.pn, 2
  %common.ret.op = insertvalue %dod_codegen_examples.KeyPayload %.pn, double %.unpack7.pn, 3
  ret %dod_codegen_examples.KeyPayload %common.ret.op

.lr.ph:                                           ; preds = %.lr.ph.preheader, %8
  %lsr.iv25 = phi i64 [ %1, %.lr.ph.preheader ], [ %lsr.iv.next, %8 ]
  %lsr.iv = phi ptr [ %scevgep, %.lr.ph.preheader ], [ %scevgep22, %8 ]
  %scevgep26 = getelementptr i8, ptr %lsr.iv, i64 -16
  %.sroa.0.0.copyload = load double, ptr %scevgep26, align 8
  %4 = fcmp ult double %.sroa.0.0.copyload, %2
  br i1 %4, label %8, label %7

._crit_edge:                                      ; preds = %8, %3
  %5 = getelementptr %dod_codegen_examples.KeyPayload, ptr %0, i64 %1
  %6 = getelementptr i8, ptr %5, i64 -32
  %.unpack = load double, ptr %6, align 8
  %.elt2 = getelementptr i8, ptr %5, i64 -24
  %.elt4 = getelementptr i8, ptr %5, i64 -16
  %.elt6 = getelementptr i8, ptr %5, i64 -8
  br label %common.ret

7:                                                ; preds = %.lr.ph
  %scevgep24 = getelementptr i8, ptr %lsr.iv, i64 8
  %scevgep23 = getelementptr i8, ptr %lsr.iv, i64 -8
  br label %common.ret

8:                                                ; preds = %.lr.ph
  %scevgep22 = getelementptr i8, ptr %lsr.iv, i64 32
  %lsr.iv.next = add i64 %lsr.iv25, -1
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @refreshDirty(ptr nocapture nonnull readonly align 8 %0, ptr nocapture nonnull writeonly align 8 %1, i64 %2) local_unnamed_addr #4 {
  %.not = icmp eq i64 %2, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %3
  %4 = ptrtoint ptr %1 to i64
  %5 = ptrtoint ptr %0 to i64
  %min.iters.check = icmp ult i64 %2, 8
  %6 = sub i64 %4, %5
  %diff.check = icmp ult i64 %6, 64
  %or.cond = select i1 %min.iters.check, i1 true, i1 %diff.check
  br i1 %or.cond, label %.lr.ph.preheader7, label %vector.ph

vector.ph:                                        ; preds = %.lr.ph.preheader
  %n.vec = and i64 %2, -8
  %scevgep15 = getelementptr i8, ptr %1, i64 32
  %scevgep21 = getelementptr i8, ptr %0, i64 32
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv22 = phi ptr [ %scevgep23, %vector.body ], [ %scevgep21, %vector.ph ]
  %lsr.iv16 = phi ptr [ %scevgep17, %vector.body ], [ %scevgep15, %vector.ph ]
  %lsr.iv13 = phi i64 [ %lsr.iv.next14, %vector.body ], [ %n.vec, %vector.ph ]
  %scevgep24 = getelementptr i8, ptr %lsr.iv22, i64 -32
  %scevgep26 = getelementptr i8, ptr %lsr.iv22, i64 -16
  %scevgep25 = getelementptr i8, ptr %lsr.iv22, i64 16
  %wide.load = load <2 x double>, ptr %scevgep24, align 8
  %wide.load3 = load <2 x double>, ptr %scevgep26, align 8
  %wide.load4 = load <2 x double>, ptr %lsr.iv22, align 8
  %wide.load5 = load <2 x double>, ptr %scevgep25, align 8
  %scevgep19 = getelementptr i8, ptr %lsr.iv16, i64 -32
  %7 = fmul <2 x double> %wide.load, splat (double 2.000000e+00)
  %8 = fmul <2 x double> %wide.load3, splat (double 2.000000e+00)
  %9 = fmul <2 x double> %wide.load4, splat (double 2.000000e+00)
  %10 = fmul <2 x double> %wide.load5, splat (double 2.000000e+00)
  %11 = fadd <2 x double> %7, splat (double 1.000000e+00)
  %12 = fadd <2 x double> %8, splat (double 1.000000e+00)
  %13 = fadd <2 x double> %9, splat (double 1.000000e+00)
  %14 = fadd <2 x double> %10, splat (double 1.000000e+00)
  %scevgep20 = getelementptr i8, ptr %lsr.iv16, i64 -16
  %scevgep18 = getelementptr i8, ptr %lsr.iv16, i64 16
  store <2 x double> %11, ptr %scevgep19, align 8
  store <2 x double> %12, ptr %scevgep20, align 8
  store <2 x double> %13, ptr %lsr.iv16, align 8
  store <2 x double> %14, ptr %scevgep18, align 8
  %lsr.iv.next14 = add i64 %lsr.iv13, -8
  %scevgep17 = getelementptr i8, ptr %lsr.iv16, i64 64
  %scevgep23 = getelementptr i8, ptr %lsr.iv22, i64 64
  %15 = icmp eq i64 %lsr.iv.next14, 0
  br i1 %15, label %middle.block, label %vector.body, !llvm.loop !22

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %2, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %.lr.ph.preheader7

.lr.ph.preheader7:                                ; preds = %.lr.ph.preheader, %middle.block
  %.02.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %.lr.ph.preheader ]
  %16 = sub i64 %2, %.02.ph
  %17 = shl i64 %.02.ph, 3
  %scevgep = getelementptr i8, ptr %1, i64 %17
  %scevgep10 = getelementptr i8, ptr %0, i64 %17
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader7, %.lr.ph
  %lsr.iv11 = phi ptr [ %scevgep10, %.lr.ph.preheader7 ], [ %scevgep12, %.lr.ph ]
  %lsr.iv8 = phi ptr [ %scevgep, %.lr.ph.preheader7 ], [ %scevgep9, %.lr.ph ]
  %lsr.iv = phi i64 [ %16, %.lr.ph.preheader7 ], [ %lsr.iv.next, %.lr.ph ]
  %18 = load double, ptr %lsr.iv11, align 8
  %19 = fmul double %18, 2.000000e+00
  %20 = fadd double %19, 1.000000e+00
  store double %20, ptr %lsr.iv8, align 8
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep9 = getelementptr i8, ptr %lsr.iv8, i64 8
  %scevgep12 = getelementptr i8, ptr %lsr.iv11, i64 8
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !23

._crit_edge:                                      ; preds = %.lr.ph, %middle.block, %3
  ret void
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @refreshScanAllFlags(ptr nocapture nonnull readonly align 8 %0, ptr nocapture nonnull readonly align 1 %1, ptr nocapture nonnull writeonly align 8 %2, i64 %3) local_unnamed_addr #4 {
  %.not4 = icmp eq i64 %3, 0
  br i1 %.not4, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %4
  %xtraiter = and i64 %3, 7
  %5 = icmp ult i64 %3, 8
  br i1 %5, label %._crit_edge.loopexit.unr-lcssa, label %.lr.ph.preheader.new

.lr.ph.preheader.new:                             ; preds = %.lr.ph.preheader
  %6 = lshr i64 %3, 3
  %7 = mul i64 %6, -8
  %scevgep15 = getelementptr i8, ptr %1, i64 3
  %scevgep25 = getelementptr i8, ptr %0, i64 32
  %scevgep35 = getelementptr i8, ptr %2, i64 32
  br label %.lr.ph

.lr.ph:                                           ; preds = %52, %.lr.ph.preheader.new
  %lsr.iv36 = phi ptr [ %scevgep37, %52 ], [ %scevgep35, %.lr.ph.preheader.new ]
  %lsr.iv26 = phi ptr [ %scevgep27, %52 ], [ %scevgep25, %.lr.ph.preheader.new ]
  %lsr.iv16 = phi ptr [ %scevgep17, %52 ], [ %scevgep15, %.lr.ph.preheader.new ]
  %lsr.iv13 = phi i64 [ %lsr.iv.next14, %52 ], [ 0, %.lr.ph.preheader.new ]
  %scevgep18 = getelementptr i8, ptr %lsr.iv16, i64 -3
  %8 = load i8, ptr %scevgep18, align 1
  %.not = icmp eq i8 %8, 0
  br i1 %.not, label %.lr.ph.1, label %53

._crit_edge.loopexit.unr-lcssa.loopexit:          ; preds = %52
  %9 = mul i64 %lsr.iv.next14, -1
  br label %._crit_edge.loopexit.unr-lcssa

._crit_edge.loopexit.unr-lcssa:                   ; preds = %._crit_edge.loopexit.unr-lcssa.loopexit, %.lr.ph.preheader
  %.03.unr = phi i64 [ 0, %.lr.ph.preheader ], [ %9, %._crit_edge.loopexit.unr-lcssa.loopexit ]
  %lcmp.mod.not = icmp eq i64 %xtraiter, 0
  br i1 %lcmp.mod.not, label %._crit_edge, label %.lr.ph.epil.preheader

.lr.ph.epil.preheader:                            ; preds = %._crit_edge.loopexit.unr-lcssa
  %10 = shl i64 %.03.unr, 3
  %scevgep = getelementptr i8, ptr %0, i64 %10
  %scevgep6 = getelementptr i8, ptr %2, i64 %10
  %scevgep9 = getelementptr i8, ptr %1, i64 %.03.unr
  br label %.lr.ph.epil

.lr.ph.epil:                                      ; preds = %.lr.ph.epil.preheader, %16
  %lsr.iv12 = phi i64 [ %xtraiter, %.lr.ph.epil.preheader ], [ %lsr.iv.next, %16 ]
  %lsr.iv10 = phi ptr [ %scevgep9, %.lr.ph.epil.preheader ], [ %scevgep11, %16 ]
  %lsr.iv7 = phi ptr [ %scevgep6, %.lr.ph.epil.preheader ], [ %scevgep8, %16 ]
  %lsr.iv = phi ptr [ %scevgep, %.lr.ph.epil.preheader ], [ %scevgep5, %16 ]
  %11 = load i8, ptr %lsr.iv10, align 1
  %.not.epil = icmp eq i8 %11, 0
  %scevgep11 = getelementptr i8, ptr %lsr.iv10, i64 1
  br i1 %.not.epil, label %16, label %12

12:                                               ; preds = %.lr.ph.epil
  %13 = load double, ptr %lsr.iv, align 8
  %14 = fmul double %13, 2.000000e+00
  %15 = fadd double %14, 1.000000e+00
  store double %15, ptr %lsr.iv7, align 8
  br label %16

16:                                               ; preds = %12, %.lr.ph.epil
  %scevgep5 = getelementptr i8, ptr %lsr.iv, i64 8
  %scevgep8 = getelementptr i8, ptr %lsr.iv7, i64 8
  %lsr.iv.next = add nsw i64 %lsr.iv12, -1
  %epil.iter.cmp.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %epil.iter.cmp.not, label %._crit_edge, label %.lr.ph.epil, !llvm.loop !24

._crit_edge:                                      ; preds = %16, %._crit_edge.loopexit.unr-lcssa, %4
  ret void

.lr.ph.1:                                         ; preds = %.lr.ph, %53
  %scevgep20 = getelementptr i8, ptr %lsr.iv16, i64 -2
  %17 = load i8, ptr %scevgep20, align 1
  %.not.1 = icmp eq i8 %17, 0
  br i1 %.not.1, label %.lr.ph.2, label %18

18:                                               ; preds = %.lr.ph.1
  %scevgep40 = getelementptr i8, ptr %lsr.iv36, i64 -24
  %scevgep30 = getelementptr i8, ptr %lsr.iv26, i64 -24
  %19 = load double, ptr %scevgep30, align 8
  %20 = fmul double %19, 2.000000e+00
  %21 = fadd double %20, 1.000000e+00
  store double %21, ptr %scevgep40, align 8
  br label %.lr.ph.2

.lr.ph.2:                                         ; preds = %18, %.lr.ph.1
  %scevgep21 = getelementptr i8, ptr %lsr.iv16, i64 -1
  %22 = load i8, ptr %scevgep21, align 1
  %.not.2 = icmp eq i8 %22, 0
  br i1 %.not.2, label %.lr.ph.3, label %23

23:                                               ; preds = %.lr.ph.2
  %scevgep41 = getelementptr i8, ptr %lsr.iv36, i64 -16
  %scevgep31 = getelementptr i8, ptr %lsr.iv26, i64 -16
  %24 = load double, ptr %scevgep31, align 8
  %25 = fmul double %24, 2.000000e+00
  %26 = fadd double %25, 1.000000e+00
  store double %26, ptr %scevgep41, align 8
  br label %.lr.ph.3

.lr.ph.3:                                         ; preds = %23, %.lr.ph.2
  %27 = load i8, ptr %lsr.iv16, align 1
  %.not.3 = icmp eq i8 %27, 0
  br i1 %.not.3, label %.lr.ph.4, label %28

28:                                               ; preds = %.lr.ph.3
  %scevgep42 = getelementptr i8, ptr %lsr.iv36, i64 -8
  %scevgep32 = getelementptr i8, ptr %lsr.iv26, i64 -8
  %29 = load double, ptr %scevgep32, align 8
  %30 = fmul double %29, 2.000000e+00
  %31 = fadd double %30, 1.000000e+00
  store double %31, ptr %scevgep42, align 8
  br label %.lr.ph.4

.lr.ph.4:                                         ; preds = %28, %.lr.ph.3
  %scevgep23 = getelementptr i8, ptr %lsr.iv16, i64 1
  %32 = load i8, ptr %scevgep23, align 1
  %.not.4 = icmp eq i8 %32, 0
  br i1 %.not.4, label %.lr.ph.5, label %33

33:                                               ; preds = %.lr.ph.4
  %34 = load double, ptr %lsr.iv26, align 8
  %35 = fmul double %34, 2.000000e+00
  %36 = fadd double %35, 1.000000e+00
  store double %36, ptr %lsr.iv36, align 8
  br label %.lr.ph.5

.lr.ph.5:                                         ; preds = %33, %.lr.ph.4
  %scevgep24 = getelementptr i8, ptr %lsr.iv16, i64 2
  %37 = load i8, ptr %scevgep24, align 1
  %.not.5 = icmp eq i8 %37, 0
  br i1 %.not.5, label %.lr.ph.6, label %38

38:                                               ; preds = %.lr.ph.5
  %scevgep44 = getelementptr i8, ptr %lsr.iv36, i64 8
  %scevgep34 = getelementptr i8, ptr %lsr.iv26, i64 8
  %39 = load double, ptr %scevgep34, align 8
  %40 = fmul double %39, 2.000000e+00
  %41 = fadd double %40, 1.000000e+00
  store double %41, ptr %scevgep44, align 8
  br label %.lr.ph.6

.lr.ph.6:                                         ; preds = %38, %.lr.ph.5
  %scevgep22 = getelementptr i8, ptr %lsr.iv16, i64 3
  %42 = load i8, ptr %scevgep22, align 1
  %.not.6 = icmp eq i8 %42, 0
  br i1 %.not.6, label %.lr.ph.7, label %43

43:                                               ; preds = %.lr.ph.6
  %scevgep43 = getelementptr i8, ptr %lsr.iv36, i64 16
  %scevgep33 = getelementptr i8, ptr %lsr.iv26, i64 16
  %44 = load double, ptr %scevgep33, align 8
  %45 = fmul double %44, 2.000000e+00
  %46 = fadd double %45, 1.000000e+00
  store double %46, ptr %scevgep43, align 8
  br label %.lr.ph.7

.lr.ph.7:                                         ; preds = %43, %.lr.ph.6
  %scevgep19 = getelementptr i8, ptr %lsr.iv16, i64 4
  %47 = load i8, ptr %scevgep19, align 1
  %.not.7 = icmp eq i8 %47, 0
  br i1 %.not.7, label %52, label %48

48:                                               ; preds = %.lr.ph.7
  %scevgep39 = getelementptr i8, ptr %lsr.iv36, i64 24
  %scevgep28 = getelementptr i8, ptr %lsr.iv26, i64 24
  %49 = load double, ptr %scevgep28, align 8
  %50 = fmul double %49, 2.000000e+00
  %51 = fadd double %50, 1.000000e+00
  store double %51, ptr %scevgep39, align 8
  br label %52

52:                                               ; preds = %48, %.lr.ph.7
  %lsr.iv.next14 = add i64 %lsr.iv13, -8
  %scevgep17 = getelementptr i8, ptr %lsr.iv16, i64 8
  %scevgep27 = getelementptr i8, ptr %lsr.iv26, i64 64
  %scevgep37 = getelementptr i8, ptr %lsr.iv36, i64 64
  %niter.ncmp.7 = icmp eq i64 %7, %lsr.iv.next14
  br i1 %niter.ncmp.7, label %._crit_edge.loopexit.unr-lcssa.loopexit, label %.lr.ph

53:                                               ; preds = %.lr.ph
  %scevgep38 = getelementptr i8, ptr %lsr.iv36, i64 -32
  %scevgep29 = getelementptr i8, ptr %lsr.iv26, i64 -32
  %54 = load double, ptr %scevgep29, align 8
  %55 = fmul double %54, 2.000000e+00
  %56 = fadd double %55, 1.000000e+00
  store double %56, ptr %scevgep38, align 8
  br label %.lr.ph.1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none) uwtable
define dso_local i64 @ensureJacobianStorage(i64 %0, i64 %1) local_unnamed_addr #8 {
common.ret:
  %2 = icmp eq i64 %0, 0
  %spec.select = tail call i64 @llvm.umax.i64(i64 %1, i64 %0)
  %common.ret.op = select i1 %2, i64 0, i64 %spec.select
  ret i64 %common.ret.op
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local void @prefixStarts(ptr nocapture nonnull readonly align 4 %0, ptr nocapture nonnull writeonly align 4 %1, i64 %2) local_unnamed_addr #4 {
  %4 = icmp eq i64 %2, 0
  br i1 %4, label %common.ret, label %5

common.ret:                                       ; preds = %.lr.ph, %5, %3
  ret void

5:                                                ; preds = %3
  store i32 0, ptr %1, align 4
  %.not = icmp eq i64 %2, 1
  br i1 %.not, label %common.ret, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %5
  %6 = add i64 %2, -1
  %scevgep18 = getelementptr i8, ptr %1, i64 4
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %.lr.ph
  %lsr.iv19 = phi ptr [ %scevgep18, %.lr.ph.preheader ], [ %scevgep20, %.lr.ph ]
  %lsr.iv17 = phi i64 [ %6, %.lr.ph.preheader ], [ %lsr.iv.next, %.lr.ph ]
  %lsr.iv = phi ptr [ %0, %.lr.ph.preheader ], [ %scevgep, %.lr.ph ]
  %7 = phi i32 [ %9, %.lr.ph ], [ 0, %.lr.ph.preheader ]
  %8 = load i32, ptr %lsr.iv, align 4
  %9 = add nuw i32 %8, %7
  store i32 %9, ptr %lsr.iv19, align 4
  %scevgep = getelementptr i8, ptr %lsr.iv, i64 4
  %lsr.iv.next = add i64 %lsr.iv17, -1
  %scevgep20 = getelementptr i8, ptr %lsr.iv19, i64 4
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %common.ret, label %.lr.ph
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local i32 @startByResummingCounts(ptr nocapture nonnull readonly align 4 %0, i64 %1) local_unnamed_addr #0 {
  %.not = icmp eq i64 %1, 0
  br i1 %.not, label %._crit_edge, label %iter.check

iter.check:                                       ; preds = %2
  %min.iters.check = icmp ult i64 %1, 4
  br i1 %min.iters.check, label %.lr.ph.preheader, label %vector.main.loop.iter.check

vector.main.loop.iter.check:                      ; preds = %iter.check
  %min.iters.check8 = icmp ult i64 %1, 16
  br i1 %min.iters.check8, label %vec.epilog.ph, label %vector.ph

vector.ph:                                        ; preds = %vector.main.loop.iter.check
  %n.vec = and i64 %1, -16
  %scevgep42 = getelementptr i8, ptr %0, i64 32
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv48 = phi i64 [ %lsr.iv.next49, %vector.body ], [ %n.vec, %vector.ph ]
  %lsr.iv43 = phi ptr [ %scevgep44, %vector.body ], [ %scevgep42, %vector.ph ]
  %vec.phi = phi <4 x i32> [ zeroinitializer, %vector.ph ], [ %3, %vector.body ]
  %vec.phi9 = phi <4 x i32> [ zeroinitializer, %vector.ph ], [ %4, %vector.body ]
  %vec.phi10 = phi <4 x i32> [ zeroinitializer, %vector.ph ], [ %5, %vector.body ]
  %vec.phi11 = phi <4 x i32> [ zeroinitializer, %vector.ph ], [ %6, %vector.body ]
  %scevgep47 = getelementptr i8, ptr %lsr.iv43, i64 -32
  %scevgep46 = getelementptr i8, ptr %lsr.iv43, i64 -16
  %scevgep45 = getelementptr i8, ptr %lsr.iv43, i64 16
  %wide.load = load <4 x i32>, ptr %scevgep47, align 4
  %wide.load12 = load <4 x i32>, ptr %scevgep46, align 4
  %wide.load13 = load <4 x i32>, ptr %lsr.iv43, align 4
  %wide.load14 = load <4 x i32>, ptr %scevgep45, align 4
  %3 = add <4 x i32> %wide.load, %vec.phi
  %4 = add <4 x i32> %wide.load12, %vec.phi9
  %5 = add <4 x i32> %wide.load13, %vec.phi10
  %6 = add <4 x i32> %wide.load14, %vec.phi11
  %scevgep44 = getelementptr i8, ptr %lsr.iv43, i64 64
  %lsr.iv.next49 = add i64 %lsr.iv48, -16
  %7 = icmp eq i64 %lsr.iv.next49, 0
  br i1 %7, label %middle.block, label %vector.body, !llvm.loop !26

middle.block:                                     ; preds = %vector.body
  %bin.rdx = add <4 x i32> %4, %3
  %bin.rdx15 = add <4 x i32> %5, %bin.rdx
  %bin.rdx16 = add <4 x i32> %6, %bin.rdx15
  %8 = tail call i32 @llvm.vector.reduce.add.v4i32(<4 x i32> %bin.rdx16)
  %cmp.n = icmp eq i64 %1, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %vec.epilog.iter.check

vec.epilog.iter.check:                            ; preds = %middle.block
  %n.vec.remaining = and i64 %1, 12
  %min.epilog.iters.check = icmp eq i64 %n.vec.remaining, 0
  br i1 %min.epilog.iters.check, label %.lr.ph.preheader, label %vec.epilog.ph

vec.epilog.ph:                                    ; preds = %vec.epilog.iter.check, %vector.main.loop.iter.check
  %vec.epilog.resume.val = phi i64 [ %n.vec, %vec.epilog.iter.check ], [ 0, %vector.main.loop.iter.check ]
  %bc.merge.rdx = phi i32 [ %8, %vec.epilog.iter.check ], [ 0, %vector.main.loop.iter.check ]
  %n.vec18 = and i64 %1, -4
  %9 = insertelement <4 x i32> <i32 poison, i32 0, i32 0, i32 0>, i32 %bc.merge.rdx, i64 0
  %10 = shl i64 %vec.epilog.resume.val, 2
  %scevgep37 = getelementptr i8, ptr %0, i64 %10
  %11 = sub i64 %vec.epilog.resume.val, %n.vec18
  br label %vec.epilog.vector.body

vec.epilog.vector.body:                           ; preds = %vec.epilog.vector.body, %vec.epilog.ph
  %lsr.iv40 = phi i64 [ %lsr.iv.next41, %vec.epilog.vector.body ], [ %11, %vec.epilog.ph ]
  %lsr.iv38 = phi ptr [ %scevgep39, %vec.epilog.vector.body ], [ %scevgep37, %vec.epilog.ph ]
  %vec.phi20 = phi <4 x i32> [ %9, %vec.epilog.ph ], [ %12, %vec.epilog.vector.body ]
  %wide.load21 = load <4 x i32>, ptr %lsr.iv38, align 4
  %12 = add <4 x i32> %wide.load21, %vec.phi20
  %scevgep39 = getelementptr i8, ptr %lsr.iv38, i64 16
  %lsr.iv.next41 = add i64 %lsr.iv40, 4
  %13 = icmp eq i64 %lsr.iv.next41, 0
  br i1 %13, label %vec.epilog.middle.block, label %vec.epilog.vector.body, !llvm.loop !27

vec.epilog.middle.block:                          ; preds = %vec.epilog.vector.body
  %14 = tail call i32 @llvm.vector.reduce.add.v4i32(<4 x i32> %12)
  %cmp.n23 = icmp eq i64 %1, %n.vec18
  br i1 %cmp.n23, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %vec.epilog.iter.check, %vec.epilog.middle.block, %iter.check
  %.07.ph = phi i32 [ %14, %vec.epilog.middle.block ], [ 0, %iter.check ], [ %8, %vec.epilog.iter.check ]
  %.056.ph = phi i64 [ %n.vec18, %vec.epilog.middle.block ], [ 0, %iter.check ], [ %n.vec, %vec.epilog.iter.check ]
  %15 = sub i64 %1, %.056.ph
  %16 = shl i64 %.056.ph, 2
  %scevgep = getelementptr i8, ptr %0, i64 %16
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %.lr.ph
  %lsr.iv35 = phi ptr [ %scevgep, %.lr.ph.preheader ], [ %scevgep36, %.lr.ph ]
  %lsr.iv = phi i64 [ %15, %.lr.ph.preheader ], [ %lsr.iv.next, %.lr.ph ]
  %.07 = phi i32 [ %18, %.lr.ph ], [ %.07.ph, %.lr.ph.preheader ]
  %17 = load i32, ptr %lsr.iv35, align 4
  %18 = add nuw i32 %17, %.07
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep36 = getelementptr i8, ptr %lsr.iv35, i64 4
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !28

._crit_edge:                                      ; preds = %.lr.ph, %middle.block, %vec.epilog.middle.block, %2
  %.0.lcssa = phi i32 [ 0, %2 ], [ %8, %middle.block ], [ %14, %vec.epilog.middle.block ], [ %18, %.lr.ph ]
  ret i32 %.0.lcssa
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local double @workerSum(ptr nocapture nonnull readonly align 8 %0, i64 %1, i64 %2) local_unnamed_addr #0 {
  %4 = icmp ugt i64 %2, %1
  br i1 %4, label %.lr.ph.preheader, label %._crit_edge

.lr.ph.preheader:                                 ; preds = %3
  %5 = sub nuw i64 %2, %1
  %min.iters.check = icmp ult i64 %5, 8
  br i1 %min.iters.check, label %.lr.ph.preheader13, label %vector.ph

vector.ph:                                        ; preds = %.lr.ph.preheader
  %n.vec = and i64 %5, -8
  %6 = add i64 %1, %n.vec
  %7 = shl i64 %1, 3
  %8 = add i64 %7, 32
  %scevgep16 = getelementptr i8, ptr %0, i64 %8
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv22 = phi i64 [ %lsr.iv.next23, %vector.body ], [ %n.vec, %vector.ph ]
  %lsr.iv17 = phi ptr [ %scevgep18, %vector.body ], [ %scevgep16, %vector.ph ]
  %vec.phi = phi double [ 0.000000e+00, %vector.ph ], [ %12, %vector.body ]
  %scevgep21 = getelementptr i8, ptr %lsr.iv17, i64 -32
  %scevgep20 = getelementptr i8, ptr %lsr.iv17, i64 -16
  %scevgep19 = getelementptr i8, ptr %lsr.iv17, i64 16
  %wide.load = load <2 x double>, ptr %scevgep21, align 8
  %wide.load7 = load <2 x double>, ptr %scevgep20, align 8
  %wide.load8 = load <2 x double>, ptr %lsr.iv17, align 8
  %wide.load9 = load <2 x double>, ptr %scevgep19, align 8
  %9 = tail call double @llvm.vector.reduce.fadd.v2f64(double %vec.phi, <2 x double> %wide.load)
  %10 = tail call double @llvm.vector.reduce.fadd.v2f64(double %9, <2 x double> %wide.load7)
  %11 = tail call double @llvm.vector.reduce.fadd.v2f64(double %10, <2 x double> %wide.load8)
  %12 = tail call double @llvm.vector.reduce.fadd.v2f64(double %11, <2 x double> %wide.load9)
  %scevgep18 = getelementptr i8, ptr %lsr.iv17, i64 64
  %lsr.iv.next23 = add i64 %lsr.iv22, -8
  %13 = icmp eq i64 %lsr.iv.next23, 0
  br i1 %13, label %middle.block, label %vector.body, !llvm.loop !29

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %5, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %.lr.ph.preheader13

.lr.ph.preheader13:                               ; preds = %.lr.ph.preheader, %middle.block
  %.06.ph = phi double [ %12, %middle.block ], [ 0.000000e+00, %.lr.ph.preheader ]
  %.045.ph = phi i64 [ %6, %middle.block ], [ %1, %.lr.ph.preheader ]
  %14 = sub i64 %2, %.045.ph
  %15 = shl i64 %.045.ph, 3
  %scevgep = getelementptr i8, ptr %0, i64 %15
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader13, %.lr.ph
  %lsr.iv14 = phi ptr [ %scevgep, %.lr.ph.preheader13 ], [ %scevgep15, %.lr.ph ]
  %lsr.iv = phi i64 [ %14, %.lr.ph.preheader13 ], [ %lsr.iv.next, %.lr.ph ]
  %.06 = phi double [ %17, %.lr.ph ], [ %.06.ph, %.lr.ph.preheader13 ]
  %16 = load double, ptr %lsr.iv14, align 8
  %17 = fadd double %.06, %16
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep15 = getelementptr i8, ptr %lsr.iv14, i64 8
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !30

._crit_edge:                                      ; preds = %.lr.ph, %middle.block, %3
  %.0.lcssa = phi double [ 0.000000e+00, %3 ], [ %12, %middle.block ], [ %17, %.lr.ph ]
  ret double %.0.lcssa
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable
define dso_local double @workerWriteEveryItem(ptr nocapture nonnull readonly align 8 %0, ptr nocapture nonnull writeonly align 8 initializes((0, 8)) %1, i64 %2, i64 %3) local_unnamed_addr #4 {
  store double 0.000000e+00, ptr %1, align 8
  %5 = icmp ugt i64 %3, %2
  br i1 %5, label %.lr.ph.preheader, label %._crit_edge

.lr.ph.preheader:                                 ; preds = %4
  %6 = sub i64 %3, %2
  %7 = shl i64 %2, 3
  %scevgep = getelementptr i8, ptr %0, i64 %7
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %.lr.ph
  %lsr.iv4 = phi ptr [ %scevgep, %.lr.ph.preheader ], [ %scevgep5, %.lr.ph ]
  %lsr.iv = phi i64 [ %6, %.lr.ph.preheader ], [ %lsr.iv.next, %.lr.ph ]
  %8 = phi double [ %10, %.lr.ph ], [ 0.000000e+00, %.lr.ph.preheader ]
  %9 = load double, ptr %lsr.iv4, align 8
  %10 = fadd double %8, %9
  store double %10, ptr %1, align 8
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep5 = getelementptr i8, ptr %lsr.iv4, i64 8
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph

._crit_edge:                                      ; preds = %.lr.ph, %4
  %11 = phi double [ 0.000000e+00, %4 ], [ %10, %.lr.ph ]
  ret double %11
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local i32 @sumSelected(ptr nocapture nonnull readonly align 1 %0, ptr nocapture nonnull readonly align 4 %1, i64 %2) local_unnamed_addr #0 {
  %.not7 = icmp eq i64 %2, 0
  br i1 %.not7, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %3
  %xtraiter = and i64 %2, 7
  %4 = icmp ult i64 %2, 8
  br i1 %4, label %._crit_edge.loopexit.unr-lcssa, label %.lr.ph.preheader.new

.lr.ph.preheader.new:                             ; preds = %.lr.ph.preheader
  %5 = lshr i64 %2, 3
  %6 = mul i64 %5, -8
  %scevgep16 = getelementptr i8, ptr %0, i64 3
  %scevgep26 = getelementptr i8, ptr %1, i64 16
  br label %.lr.ph

.lr.ph:                                           ; preds = %43, %.lr.ph.preheader.new
  %lsr.iv27 = phi ptr [ %scevgep28, %43 ], [ %scevgep26, %.lr.ph.preheader.new ]
  %lsr.iv17 = phi ptr [ %scevgep18, %43 ], [ %scevgep16, %.lr.ph.preheader.new ]
  %lsr.iv14 = phi i64 [ %lsr.iv.next15, %43 ], [ 0, %.lr.ph.preheader.new ]
  %.045 = phi i32 [ 0, %.lr.ph.preheader.new ], [ %.1.7, %43 ]
  %scevgep19 = getelementptr i8, ptr %lsr.iv17, i64 -3
  %7 = load i8, ptr %scevgep19, align 1
  %.not = icmp eq i8 %7, 0
  br i1 %.not, label %.lr.ph.1, label %44

._crit_edge.loopexit.unr-lcssa.loopexit:          ; preds = %43
  %8 = mul i64 %lsr.iv.next15, -1
  br label %._crit_edge.loopexit.unr-lcssa

._crit_edge.loopexit.unr-lcssa:                   ; preds = %._crit_edge.loopexit.unr-lcssa.loopexit, %.lr.ph.preheader
  %.1.lcssa.ph = phi i32 [ poison, %.lr.ph.preheader ], [ %.1.7, %._crit_edge.loopexit.unr-lcssa.loopexit ]
  %.06.unr = phi i64 [ 0, %.lr.ph.preheader ], [ %8, %._crit_edge.loopexit.unr-lcssa.loopexit ]
  %.045.unr = phi i32 [ 0, %.lr.ph.preheader ], [ %.1.7, %._crit_edge.loopexit.unr-lcssa.loopexit ]
  %lcmp.mod.not = icmp eq i64 %xtraiter, 0
  br i1 %lcmp.mod.not, label %._crit_edge, label %.lr.ph.epil.preheader

.lr.ph.epil.preheader:                            ; preds = %._crit_edge.loopexit.unr-lcssa
  %9 = shl i64 %.06.unr, 2
  %scevgep = getelementptr i8, ptr %1, i64 %9
  %scevgep10 = getelementptr i8, ptr %0, i64 %.06.unr
  br label %.lr.ph.epil

.lr.ph.epil:                                      ; preds = %.lr.ph.epil.preheader, %14
  %lsr.iv13 = phi i64 [ %xtraiter, %.lr.ph.epil.preheader ], [ %lsr.iv.next, %14 ]
  %lsr.iv11 = phi ptr [ %scevgep10, %.lr.ph.epil.preheader ], [ %scevgep12, %14 ]
  %lsr.iv = phi ptr [ %scevgep, %.lr.ph.epil.preheader ], [ %scevgep9, %14 ]
  %.045.epil = phi i32 [ %.1.epil, %14 ], [ %.045.unr, %.lr.ph.epil.preheader ]
  %10 = load i8, ptr %lsr.iv11, align 1
  %.not.epil = icmp eq i8 %10, 0
  %scevgep12 = getelementptr i8, ptr %lsr.iv11, i64 1
  br i1 %.not.epil, label %14, label %11

11:                                               ; preds = %.lr.ph.epil
  %12 = load i32, ptr %lsr.iv, align 4
  %13 = add nsw i32 %12, %.045.epil
  br label %14

14:                                               ; preds = %11, %.lr.ph.epil
  %.1.epil = phi i32 [ %13, %11 ], [ %.045.epil, %.lr.ph.epil ]
  %scevgep9 = getelementptr i8, ptr %lsr.iv, i64 4
  %lsr.iv.next = add nsw i64 %lsr.iv13, -1
  %epil.iter.cmp.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %epil.iter.cmp.not, label %._crit_edge, label %.lr.ph.epil, !llvm.loop !31

._crit_edge:                                      ; preds = %14, %._crit_edge.loopexit.unr-lcssa, %3
  %.04.lcssa = phi i32 [ 0, %3 ], [ %.1.lcssa.ph, %._crit_edge.loopexit.unr-lcssa ], [ %.1.epil, %14 ]
  ret i32 %.04.lcssa

.lr.ph.1:                                         ; preds = %.lr.ph, %44
  %.1 = phi i32 [ %46, %44 ], [ %.045, %.lr.ph ]
  %scevgep22 = getelementptr i8, ptr %lsr.iv17, i64 -2
  %15 = load i8, ptr %scevgep22, align 1
  %.not.1 = icmp eq i8 %15, 0
  br i1 %.not.1, label %.lr.ph.2, label %16

16:                                               ; preds = %.lr.ph.1
  %scevgep31 = getelementptr i8, ptr %lsr.iv27, i64 -12
  %17 = load i32, ptr %scevgep31, align 4
  %18 = add nsw i32 %17, %.1
  br label %.lr.ph.2

.lr.ph.2:                                         ; preds = %16, %.lr.ph.1
  %.1.1 = phi i32 [ %18, %16 ], [ %.1, %.lr.ph.1 ]
  %scevgep23 = getelementptr i8, ptr %lsr.iv17, i64 -1
  %19 = load i8, ptr %scevgep23, align 1
  %.not.2 = icmp eq i8 %19, 0
  br i1 %.not.2, label %.lr.ph.3, label %20

20:                                               ; preds = %.lr.ph.2
  %scevgep32 = getelementptr i8, ptr %lsr.iv27, i64 -8
  %21 = load i32, ptr %scevgep32, align 4
  %22 = add nsw i32 %21, %.1.1
  br label %.lr.ph.3

.lr.ph.3:                                         ; preds = %20, %.lr.ph.2
  %.1.2 = phi i32 [ %22, %20 ], [ %.1.1, %.lr.ph.2 ]
  %23 = load i8, ptr %lsr.iv17, align 1
  %.not.3 = icmp eq i8 %23, 0
  br i1 %.not.3, label %.lr.ph.4, label %24

24:                                               ; preds = %.lr.ph.3
  %scevgep33 = getelementptr i8, ptr %lsr.iv27, i64 -4
  %25 = load i32, ptr %scevgep33, align 4
  %26 = add nsw i32 %25, %.1.2
  br label %.lr.ph.4

.lr.ph.4:                                         ; preds = %24, %.lr.ph.3
  %.1.3 = phi i32 [ %26, %24 ], [ %.1.2, %.lr.ph.3 ]
  %scevgep25 = getelementptr i8, ptr %lsr.iv17, i64 1
  %27 = load i8, ptr %scevgep25, align 1
  %.not.4 = icmp eq i8 %27, 0
  br i1 %.not.4, label %.lr.ph.5, label %28

28:                                               ; preds = %.lr.ph.4
  %29 = load i32, ptr %lsr.iv27, align 4
  %30 = add nsw i32 %29, %.1.3
  br label %.lr.ph.5

.lr.ph.5:                                         ; preds = %28, %.lr.ph.4
  %.1.4 = phi i32 [ %30, %28 ], [ %.1.3, %.lr.ph.4 ]
  %scevgep24 = getelementptr i8, ptr %lsr.iv17, i64 2
  %31 = load i8, ptr %scevgep24, align 1
  %.not.5 = icmp eq i8 %31, 0
  br i1 %.not.5, label %.lr.ph.6, label %32

32:                                               ; preds = %.lr.ph.5
  %scevgep35 = getelementptr i8, ptr %lsr.iv27, i64 4
  %33 = load i32, ptr %scevgep35, align 4
  %34 = add nsw i32 %33, %.1.4
  br label %.lr.ph.6

.lr.ph.6:                                         ; preds = %32, %.lr.ph.5
  %.1.5 = phi i32 [ %34, %32 ], [ %.1.4, %.lr.ph.5 ]
  %scevgep21 = getelementptr i8, ptr %lsr.iv17, i64 3
  %35 = load i8, ptr %scevgep21, align 1
  %.not.6 = icmp eq i8 %35, 0
  br i1 %.not.6, label %.lr.ph.7, label %36

36:                                               ; preds = %.lr.ph.6
  %scevgep34 = getelementptr i8, ptr %lsr.iv27, i64 8
  %37 = load i32, ptr %scevgep34, align 4
  %38 = add nsw i32 %37, %.1.5
  br label %.lr.ph.7

.lr.ph.7:                                         ; preds = %36, %.lr.ph.6
  %.1.6 = phi i32 [ %38, %36 ], [ %.1.5, %.lr.ph.6 ]
  %scevgep20 = getelementptr i8, ptr %lsr.iv17, i64 4
  %39 = load i8, ptr %scevgep20, align 1
  %.not.7 = icmp eq i8 %39, 0
  br i1 %.not.7, label %43, label %40

40:                                               ; preds = %.lr.ph.7
  %scevgep30 = getelementptr i8, ptr %lsr.iv27, i64 12
  %41 = load i32, ptr %scevgep30, align 4
  %42 = add nsw i32 %41, %.1.6
  br label %43

43:                                               ; preds = %40, %.lr.ph.7
  %.1.7 = phi i32 [ %42, %40 ], [ %.1.6, %.lr.ph.7 ]
  %lsr.iv.next15 = add i64 %lsr.iv14, -8
  %scevgep18 = getelementptr i8, ptr %lsr.iv17, i64 8
  %scevgep28 = getelementptr i8, ptr %lsr.iv27, i64 32
  %niter.ncmp.7 = icmp eq i64 %6, %lsr.iv.next15
  br i1 %niter.ncmp.7, label %._crit_edge.loopexit.unr-lcssa.loopexit, label %.lr.ph

44:                                               ; preds = %.lr.ph
  %scevgep29 = getelementptr i8, ptr %lsr.iv27, i64 -16
  %45 = load i32, ptr %scevgep29, align 4
  %46 = add nsw i32 %45, %.045
  br label %.lr.ph.1
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local i32 @sumGroupedValues(ptr nocapture nonnull readonly align 4 %0, i64 %1) local_unnamed_addr #0 {
  %.not = icmp eq i64 %1, 0
  br i1 %.not, label %._crit_edge, label %iter.check

iter.check:                                       ; preds = %2
  %min.iters.check = icmp ult i64 %1, 4
  br i1 %min.iters.check, label %.lr.ph.preheader, label %vector.main.loop.iter.check

vector.main.loop.iter.check:                      ; preds = %iter.check
  %min.iters.check6 = icmp ult i64 %1, 16
  br i1 %min.iters.check6, label %vec.epilog.ph, label %vector.ph

vector.ph:                                        ; preds = %vector.main.loop.iter.check
  %n.vec = and i64 %1, -16
  %scevgep40 = getelementptr i8, ptr %0, i64 32
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv46 = phi i64 [ %lsr.iv.next47, %vector.body ], [ %n.vec, %vector.ph ]
  %lsr.iv41 = phi ptr [ %scevgep42, %vector.body ], [ %scevgep40, %vector.ph ]
  %vec.phi = phi <4 x i32> [ zeroinitializer, %vector.ph ], [ %3, %vector.body ]
  %vec.phi7 = phi <4 x i32> [ zeroinitializer, %vector.ph ], [ %4, %vector.body ]
  %vec.phi8 = phi <4 x i32> [ zeroinitializer, %vector.ph ], [ %5, %vector.body ]
  %vec.phi9 = phi <4 x i32> [ zeroinitializer, %vector.ph ], [ %6, %vector.body ]
  %scevgep45 = getelementptr i8, ptr %lsr.iv41, i64 -32
  %scevgep44 = getelementptr i8, ptr %lsr.iv41, i64 -16
  %scevgep43 = getelementptr i8, ptr %lsr.iv41, i64 16
  %wide.load = load <4 x i32>, ptr %scevgep45, align 4
  %wide.load10 = load <4 x i32>, ptr %scevgep44, align 4
  %wide.load11 = load <4 x i32>, ptr %lsr.iv41, align 4
  %wide.load12 = load <4 x i32>, ptr %scevgep43, align 4
  %3 = add <4 x i32> %wide.load, %vec.phi
  %4 = add <4 x i32> %wide.load10, %vec.phi7
  %5 = add <4 x i32> %wide.load11, %vec.phi8
  %6 = add <4 x i32> %wide.load12, %vec.phi9
  %scevgep42 = getelementptr i8, ptr %lsr.iv41, i64 64
  %lsr.iv.next47 = add i64 %lsr.iv46, -16
  %7 = icmp eq i64 %lsr.iv.next47, 0
  br i1 %7, label %middle.block, label %vector.body, !llvm.loop !32

middle.block:                                     ; preds = %vector.body
  %bin.rdx = add <4 x i32> %4, %3
  %bin.rdx13 = add <4 x i32> %5, %bin.rdx
  %bin.rdx14 = add <4 x i32> %6, %bin.rdx13
  %8 = tail call i32 @llvm.vector.reduce.add.v4i32(<4 x i32> %bin.rdx14)
  %cmp.n = icmp eq i64 %1, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %vec.epilog.iter.check

vec.epilog.iter.check:                            ; preds = %middle.block
  %n.vec.remaining = and i64 %1, 12
  %min.epilog.iters.check = icmp eq i64 %n.vec.remaining, 0
  br i1 %min.epilog.iters.check, label %.lr.ph.preheader, label %vec.epilog.ph

vec.epilog.ph:                                    ; preds = %vec.epilog.iter.check, %vector.main.loop.iter.check
  %vec.epilog.resume.val = phi i64 [ %n.vec, %vec.epilog.iter.check ], [ 0, %vector.main.loop.iter.check ]
  %bc.merge.rdx = phi i32 [ %8, %vec.epilog.iter.check ], [ 0, %vector.main.loop.iter.check ]
  %n.vec16 = and i64 %1, -4
  %9 = insertelement <4 x i32> <i32 poison, i32 0, i32 0, i32 0>, i32 %bc.merge.rdx, i64 0
  %10 = shl i64 %vec.epilog.resume.val, 2
  %scevgep35 = getelementptr i8, ptr %0, i64 %10
  %11 = sub i64 %vec.epilog.resume.val, %n.vec16
  br label %vec.epilog.vector.body

vec.epilog.vector.body:                           ; preds = %vec.epilog.vector.body, %vec.epilog.ph
  %lsr.iv38 = phi i64 [ %lsr.iv.next39, %vec.epilog.vector.body ], [ %11, %vec.epilog.ph ]
  %lsr.iv36 = phi ptr [ %scevgep37, %vec.epilog.vector.body ], [ %scevgep35, %vec.epilog.ph ]
  %vec.phi18 = phi <4 x i32> [ %9, %vec.epilog.ph ], [ %12, %vec.epilog.vector.body ]
  %wide.load19 = load <4 x i32>, ptr %lsr.iv36, align 4
  %12 = add <4 x i32> %wide.load19, %vec.phi18
  %scevgep37 = getelementptr i8, ptr %lsr.iv36, i64 16
  %lsr.iv.next39 = add i64 %lsr.iv38, 4
  %13 = icmp eq i64 %lsr.iv.next39, 0
  br i1 %13, label %vec.epilog.middle.block, label %vec.epilog.vector.body, !llvm.loop !33

vec.epilog.middle.block:                          ; preds = %vec.epilog.vector.body
  %14 = tail call i32 @llvm.vector.reduce.add.v4i32(<4 x i32> %12)
  %cmp.n21 = icmp eq i64 %1, %n.vec16
  br i1 %cmp.n21, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %vec.epilog.iter.check, %vec.epilog.middle.block, %iter.check
  %.05.ph = phi i64 [ %n.vec16, %vec.epilog.middle.block ], [ 0, %iter.check ], [ %n.vec, %vec.epilog.iter.check ]
  %.034.ph = phi i32 [ %14, %vec.epilog.middle.block ], [ 0, %iter.check ], [ %8, %vec.epilog.iter.check ]
  %15 = sub i64 %1, %.05.ph
  %16 = shl i64 %.05.ph, 2
  %scevgep = getelementptr i8, ptr %0, i64 %16
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader, %.lr.ph
  %lsr.iv33 = phi ptr [ %scevgep, %.lr.ph.preheader ], [ %scevgep34, %.lr.ph ]
  %lsr.iv = phi i64 [ %15, %.lr.ph.preheader ], [ %lsr.iv.next, %.lr.ph ]
  %.034 = phi i32 [ %18, %.lr.ph ], [ %.034.ph, %.lr.ph.preheader ]
  %17 = load i32, ptr %lsr.iv33, align 4
  %18 = add nsw i32 %17, %.034
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep34 = getelementptr i8, ptr %lsr.iv33, i64 4
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !34

._crit_edge:                                      ; preds = %.lr.ph, %middle.block, %vec.epilog.middle.block, %2
  %.03.lcssa = phi i32 [ 0, %2 ], [ %8, %middle.block ], [ %14, %vec.epilog.middle.block ], [ %18, %.lr.ph ]
  ret i32 %.03.lcssa
}

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local double @sum(ptr nocapture nonnull readonly align 8 %0, i64 %1) local_unnamed_addr #0 {
  %.not = icmp eq i64 %1, 0
  br i1 %.not, label %._crit_edge, label %.lr.ph.preheader

.lr.ph.preheader:                                 ; preds = %2
  %min.iters.check = icmp ult i64 %1, 8
  br i1 %min.iters.check, label %.lr.ph.preheader12, label %vector.ph

vector.ph:                                        ; preds = %.lr.ph.preheader
  %n.vec = and i64 %1, -8
  %scevgep15 = getelementptr i8, ptr %0, i64 32
  br label %vector.body

vector.body:                                      ; preds = %vector.body, %vector.ph
  %lsr.iv21 = phi i64 [ %lsr.iv.next22, %vector.body ], [ %n.vec, %vector.ph ]
  %lsr.iv16 = phi ptr [ %scevgep17, %vector.body ], [ %scevgep15, %vector.ph ]
  %vec.phi = phi double [ 0.000000e+00, %vector.ph ], [ %6, %vector.body ]
  %scevgep20 = getelementptr i8, ptr %lsr.iv16, i64 -32
  %scevgep19 = getelementptr i8, ptr %lsr.iv16, i64 -16
  %scevgep18 = getelementptr i8, ptr %lsr.iv16, i64 16
  %wide.load = load <2 x double>, ptr %scevgep20, align 8
  %wide.load6 = load <2 x double>, ptr %scevgep19, align 8
  %wide.load7 = load <2 x double>, ptr %lsr.iv16, align 8
  %wide.load8 = load <2 x double>, ptr %scevgep18, align 8
  %3 = tail call double @llvm.vector.reduce.fadd.v2f64(double %vec.phi, <2 x double> %wide.load)
  %4 = tail call double @llvm.vector.reduce.fadd.v2f64(double %3, <2 x double> %wide.load6)
  %5 = tail call double @llvm.vector.reduce.fadd.v2f64(double %4, <2 x double> %wide.load7)
  %6 = tail call double @llvm.vector.reduce.fadd.v2f64(double %5, <2 x double> %wide.load8)
  %scevgep17 = getelementptr i8, ptr %lsr.iv16, i64 64
  %lsr.iv.next22 = add i64 %lsr.iv21, -8
  %7 = icmp eq i64 %lsr.iv.next22, 0
  br i1 %7, label %middle.block, label %vector.body, !llvm.loop !35

middle.block:                                     ; preds = %vector.body
  %cmp.n = icmp eq i64 %1, %n.vec
  br i1 %cmp.n, label %._crit_edge, label %.lr.ph.preheader12

.lr.ph.preheader12:                               ; preds = %.lr.ph.preheader, %middle.block
  %.05.ph = phi i64 [ %n.vec, %middle.block ], [ 0, %.lr.ph.preheader ]
  %.034.ph = phi double [ %6, %middle.block ], [ 0.000000e+00, %.lr.ph.preheader ]
  %8 = sub i64 %1, %.05.ph
  %9 = shl i64 %.05.ph, 3
  %scevgep = getelementptr i8, ptr %0, i64 %9
  br label %.lr.ph

.lr.ph:                                           ; preds = %.lr.ph.preheader12, %.lr.ph
  %lsr.iv13 = phi ptr [ %scevgep, %.lr.ph.preheader12 ], [ %scevgep14, %.lr.ph ]
  %lsr.iv = phi i64 [ %8, %.lr.ph.preheader12 ], [ %lsr.iv.next, %.lr.ph ]
  %.034 = phi double [ %11, %.lr.ph ], [ %.034.ph, %.lr.ph.preheader12 ]
  %10 = load double, ptr %lsr.iv13, align 8
  %11 = fadd double %.034, %10
  %lsr.iv.next = add i64 %lsr.iv, -1
  %scevgep14 = getelementptr i8, ptr %lsr.iv13, i64 8
  %exitcond.not = icmp eq i64 %lsr.iv.next, 0
  br i1 %exitcond.not, label %._crit_edge, label %.lr.ph, !llvm.loop !36

._crit_edge:                                      ; preds = %.lr.ph, %middle.block, %2
  %.03.lcssa = phi double [ 0.000000e+00, %2 ], [ %6, %middle.block ], [ %11, %.lr.ph ]
  ret double %.03.lcssa
}

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umax.i64(i64, i64) #9

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare double @llvm.vector.reduce.fadd.v2f64(double, <2 x double>) #9

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare <2 x double> @llvm.fma.v2f64(<2 x double>, <2 x double>, <2 x double>) #9

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.vector.reduce.add.v4i32(<4 x i32>) #9

; Function Attrs: nofree norecurse nosync nounwind memory(argmem: read) uwtable
define dso_local double @sumOpticalDepthColumn(ptr nocapture nonnull readonly align 8 %0, i64 %1) local_unnamed_addr #0 {
  %3 = tail call double @sum(ptr nocapture nonnull readonly align 8 %0, i64 %1) #0
  ret double %3
}

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: read)
declare { <2 x double>, <2 x double>, <2 x double> } @llvm.aarch64.neon.ld3.v2f64.p0(ptr) #10

attributes #0 = { nofree norecurse nosync nounwind memory(argmem: read) uwtable "frame-pointer"="all" "target-cpu"="apple-m4" "target-features"="+aes,+alternate-sextload-cvt-f32-pattern,+altnzcv,+am,+amvs,+arith-bcc-fusion,+arith-cbz-fusion,+bf16,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+CONTEXTIDREL2,+crc,+disable-latency-sched-heuristic,+dit,+dotprod,+ecv,+el2vmsa,+el3,+fgt,+flagm,+fp16fml,+fp-armv8,+fpac,+fptoint,+fullfp16,+fuse-address,+fuse-adrp-add,+fuse-aes,+fuse-arith-logic,+fuse-crypto-eor,+fuse-csel,+fuse-literals,+hcx,+i8mm,+jsconv,+lor,+lse,+lse2,+mpam,+neon,+nv,+pan,+pan-rwv,+pauth,+perfmon,+predres,+ras,+rcpc,+rcpc-immo,+rdm,+sb,+sel2,+sha2,+sha3,+sme,+sme2,+sme-f64f64,+sme-i16i64,+spe-eef,+specrestrict,+ssbs,+tlb-rmi,+tracev8.4,+uaops,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8.6a,+v8.7a,+v8a,+vh,+wfxt,+xs,+zcm,+zcz,+zcz-gp,-addr-lsl-slow-14,-aggressive-fma,-alu-lsl-fast,-ascend-store-address,-avoid-ldapur,-balance-fp-ops,-brbe,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-chk,-clrbhb,-cmp-bcc-fusion,-cmpbr,-cpa,-crypto,-cssc,-d128,-disable-ldp,-disable-stp,-enable-select-opt,-ete,-exynos-cheap-as-move,-f32mm,-f64mm,-f8f16mm,-f8f32mm,-faminmax,-fix-cortex-a53-835769,-fmv,-force-32bit-jump-tables,-fp8,-fp8dot2,-fp8dot4,-fp8fma,-fprcvt,-fujitsu-monaka,-fuse-addsub-2reg-const1,-gcs,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-ite,-ldp-aligned-only,-ls64,-lse128,-lsfe,-lsui,-lut,-mec,-mops,-mte,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-sve-fp-ld1r,-no-zcz-fp,-occmo,-outline-atomics,-pauth-lr,-pcdphint,-pops,-predictable-select-expensive,-prfm-slc-target,-rand,-rasv2,-rcpc3,-reserve-lr-for-ra,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme2p1,-sme2p2,-sme-b16b16,-sme-f16f16,-sme-f8f16,-sme-f8f32,-sme-fa64,-sme-lutv2,-sme-mop4,-sme-tmop,-spe,-specres2,-ssve-aes,-ssve-bitperm,-ssve-fp8dot2,-ssve-fp8dot4,-ssve-fp8fma,-store-pair-suppress,-stp-aligned-only,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-sve2p2,-sve-aes,-sve-aes2,-sve-b16b16,-sve-bfscale,-sve-bitperm,-sve-f16f32mm,-tagged-globals,-the,-tlbiw,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tpidrro-el0,-trbe,-use-experimental-zeroing-pseudos,-use-fixed-over-scalable-if-equal-cost,-use-postra-scheduler,-use-reciprocal-square-root,-v8.8a,-v8.9a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9.5a,-v9.6a,-v9a,-zcz-fp-workaround" }
attributes #1 = { nofree norecurse nosync nounwind memory(read, inaccessiblemem: none) uwtable "frame-pointer"="all" "target-cpu"="apple-m4" "target-features"="+aes,+alternate-sextload-cvt-f32-pattern,+altnzcv,+am,+amvs,+arith-bcc-fusion,+arith-cbz-fusion,+bf16,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+CONTEXTIDREL2,+crc,+disable-latency-sched-heuristic,+dit,+dotprod,+ecv,+el2vmsa,+el3,+fgt,+flagm,+fp16fml,+fp-armv8,+fpac,+fptoint,+fullfp16,+fuse-address,+fuse-adrp-add,+fuse-aes,+fuse-arith-logic,+fuse-crypto-eor,+fuse-csel,+fuse-literals,+hcx,+i8mm,+jsconv,+lor,+lse,+lse2,+mpam,+neon,+nv,+pan,+pan-rwv,+pauth,+perfmon,+predres,+ras,+rcpc,+rcpc-immo,+rdm,+sb,+sel2,+sha2,+sha3,+sme,+sme2,+sme-f64f64,+sme-i16i64,+spe-eef,+specrestrict,+ssbs,+tlb-rmi,+tracev8.4,+uaops,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8.6a,+v8.7a,+v8a,+vh,+wfxt,+xs,+zcm,+zcz,+zcz-gp,-addr-lsl-slow-14,-aggressive-fma,-alu-lsl-fast,-ascend-store-address,-avoid-ldapur,-balance-fp-ops,-brbe,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-chk,-clrbhb,-cmp-bcc-fusion,-cmpbr,-cpa,-crypto,-cssc,-d128,-disable-ldp,-disable-stp,-enable-select-opt,-ete,-exynos-cheap-as-move,-f32mm,-f64mm,-f8f16mm,-f8f32mm,-faminmax,-fix-cortex-a53-835769,-fmv,-force-32bit-jump-tables,-fp8,-fp8dot2,-fp8dot4,-fp8fma,-fprcvt,-fujitsu-monaka,-fuse-addsub-2reg-const1,-gcs,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-ite,-ldp-aligned-only,-ls64,-lse128,-lsfe,-lsui,-lut,-mec,-mops,-mte,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-sve-fp-ld1r,-no-zcz-fp,-occmo,-outline-atomics,-pauth-lr,-pcdphint,-pops,-predictable-select-expensive,-prfm-slc-target,-rand,-rasv2,-rcpc3,-reserve-lr-for-ra,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme2p1,-sme2p2,-sme-b16b16,-sme-f16f16,-sme-f8f16,-sme-f8f32,-sme-fa64,-sme-lutv2,-sme-mop4,-sme-tmop,-spe,-specres2,-ssve-aes,-ssve-bitperm,-ssve-fp8dot2,-ssve-fp8dot4,-ssve-fp8fma,-store-pair-suppress,-stp-aligned-only,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-sve2p2,-sve-aes,-sve-aes2,-sve-b16b16,-sve-bfscale,-sve-bitperm,-sve-f16f32mm,-tagged-globals,-the,-tlbiw,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tpidrro-el0,-trbe,-use-experimental-zeroing-pseudos,-use-fixed-over-scalable-if-equal-cost,-use-postra-scheduler,-use-reciprocal-square-root,-v8.8a,-v8.9a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9.5a,-v9.6a,-v9a,-zcz-fp-workaround" }
attributes #2 = { mustprogress nofree noinline norecurse nosync nounwind willreturn memory(argmem: write) uwtable "frame-pointer"="all" "target-cpu"="apple-m4" "target-features"="+aes,+alternate-sextload-cvt-f32-pattern,+altnzcv,+am,+amvs,+arith-bcc-fusion,+arith-cbz-fusion,+bf16,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+CONTEXTIDREL2,+crc,+disable-latency-sched-heuristic,+dit,+dotprod,+ecv,+el2vmsa,+el3,+fgt,+flagm,+fp16fml,+fp-armv8,+fpac,+fptoint,+fullfp16,+fuse-address,+fuse-adrp-add,+fuse-aes,+fuse-arith-logic,+fuse-crypto-eor,+fuse-csel,+fuse-literals,+hcx,+i8mm,+jsconv,+lor,+lse,+lse2,+mpam,+neon,+nv,+pan,+pan-rwv,+pauth,+perfmon,+predres,+ras,+rcpc,+rcpc-immo,+rdm,+sb,+sel2,+sha2,+sha3,+sme,+sme2,+sme-f64f64,+sme-i16i64,+spe-eef,+specrestrict,+ssbs,+tlb-rmi,+tracev8.4,+uaops,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8.6a,+v8.7a,+v8a,+vh,+wfxt,+xs,+zcm,+zcz,+zcz-gp,-addr-lsl-slow-14,-aggressive-fma,-alu-lsl-fast,-ascend-store-address,-avoid-ldapur,-balance-fp-ops,-brbe,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-chk,-clrbhb,-cmp-bcc-fusion,-cmpbr,-cpa,-crypto,-cssc,-d128,-disable-ldp,-disable-stp,-enable-select-opt,-ete,-exynos-cheap-as-move,-f32mm,-f64mm,-f8f16mm,-f8f32mm,-faminmax,-fix-cortex-a53-835769,-fmv,-force-32bit-jump-tables,-fp8,-fp8dot2,-fp8dot4,-fp8fma,-fprcvt,-fujitsu-monaka,-fuse-addsub-2reg-const1,-gcs,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-ite,-ldp-aligned-only,-ls64,-lse128,-lsfe,-lsui,-lut,-mec,-mops,-mte,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-sve-fp-ld1r,-no-zcz-fp,-occmo,-outline-atomics,-pauth-lr,-pcdphint,-pops,-predictable-select-expensive,-prfm-slc-target,-rand,-rasv2,-rcpc3,-reserve-lr-for-ra,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme2p1,-sme2p2,-sme-b16b16,-sme-f16f16,-sme-f8f16,-sme-f8f32,-sme-fa64,-sme-lutv2,-sme-mop4,-sme-tmop,-spe,-specres2,-ssve-aes,-ssve-bitperm,-ssve-fp8dot2,-ssve-fp8dot4,-ssve-fp8fma,-store-pair-suppress,-stp-aligned-only,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-sve2p2,-sve-aes,-sve-aes2,-sve-b16b16,-sve-bfscale,-sve-bitperm,-sve-f16f32mm,-tagged-globals,-the,-tlbiw,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tpidrro-el0,-trbe,-use-experimental-zeroing-pseudos,-use-fixed-over-scalable-if-equal-cost,-use-postra-scheduler,-use-reciprocal-square-root,-v8.8a,-v8.9a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9.5a,-v9.6a,-v9a,-zcz-fp-workaround" }
attributes #3 = { mustprogress nofree noinline norecurse nosync nounwind willreturn memory(none) uwtable "frame-pointer"="all" "target-cpu"="apple-m4" "target-features"="+aes,+alternate-sextload-cvt-f32-pattern,+altnzcv,+am,+amvs,+arith-bcc-fusion,+arith-cbz-fusion,+bf16,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+CONTEXTIDREL2,+crc,+disable-latency-sched-heuristic,+dit,+dotprod,+ecv,+el2vmsa,+el3,+fgt,+flagm,+fp16fml,+fp-armv8,+fpac,+fptoint,+fullfp16,+fuse-address,+fuse-adrp-add,+fuse-aes,+fuse-arith-logic,+fuse-crypto-eor,+fuse-csel,+fuse-literals,+hcx,+i8mm,+jsconv,+lor,+lse,+lse2,+mpam,+neon,+nv,+pan,+pan-rwv,+pauth,+perfmon,+predres,+ras,+rcpc,+rcpc-immo,+rdm,+sb,+sel2,+sha2,+sha3,+sme,+sme2,+sme-f64f64,+sme-i16i64,+spe-eef,+specrestrict,+ssbs,+tlb-rmi,+tracev8.4,+uaops,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8.6a,+v8.7a,+v8a,+vh,+wfxt,+xs,+zcm,+zcz,+zcz-gp,-addr-lsl-slow-14,-aggressive-fma,-alu-lsl-fast,-ascend-store-address,-avoid-ldapur,-balance-fp-ops,-brbe,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-chk,-clrbhb,-cmp-bcc-fusion,-cmpbr,-cpa,-crypto,-cssc,-d128,-disable-ldp,-disable-stp,-enable-select-opt,-ete,-exynos-cheap-as-move,-f32mm,-f64mm,-f8f16mm,-f8f32mm,-faminmax,-fix-cortex-a53-835769,-fmv,-force-32bit-jump-tables,-fp8,-fp8dot2,-fp8dot4,-fp8fma,-fprcvt,-fujitsu-monaka,-fuse-addsub-2reg-const1,-gcs,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-ite,-ldp-aligned-only,-ls64,-lse128,-lsfe,-lsui,-lut,-mec,-mops,-mte,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-sve-fp-ld1r,-no-zcz-fp,-occmo,-outline-atomics,-pauth-lr,-pcdphint,-pops,-predictable-select-expensive,-prfm-slc-target,-rand,-rasv2,-rcpc3,-reserve-lr-for-ra,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme2p1,-sme2p2,-sme-b16b16,-sme-f16f16,-sme-f8f16,-sme-f8f32,-sme-fa64,-sme-lutv2,-sme-mop4,-sme-tmop,-spe,-specres2,-ssve-aes,-ssve-bitperm,-ssve-fp8dot2,-ssve-fp8dot4,-ssve-fp8fma,-store-pair-suppress,-stp-aligned-only,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-sve2p2,-sve-aes,-sve-aes2,-sve-b16b16,-sve-bfscale,-sve-bitperm,-sve-f16f32mm,-tagged-globals,-the,-tlbiw,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tpidrro-el0,-trbe,-use-experimental-zeroing-pseudos,-use-fixed-over-scalable-if-equal-cost,-use-postra-scheduler,-use-reciprocal-square-root,-v8.8a,-v8.9a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9.5a,-v9.6a,-v9a,-zcz-fp-workaround" }
attributes #4 = { nofree norecurse nosync nounwind memory(argmem: readwrite) uwtable "frame-pointer"="all" "target-cpu"="apple-m4" "target-features"="+aes,+alternate-sextload-cvt-f32-pattern,+altnzcv,+am,+amvs,+arith-bcc-fusion,+arith-cbz-fusion,+bf16,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+CONTEXTIDREL2,+crc,+disable-latency-sched-heuristic,+dit,+dotprod,+ecv,+el2vmsa,+el3,+fgt,+flagm,+fp16fml,+fp-armv8,+fpac,+fptoint,+fullfp16,+fuse-address,+fuse-adrp-add,+fuse-aes,+fuse-arith-logic,+fuse-crypto-eor,+fuse-csel,+fuse-literals,+hcx,+i8mm,+jsconv,+lor,+lse,+lse2,+mpam,+neon,+nv,+pan,+pan-rwv,+pauth,+perfmon,+predres,+ras,+rcpc,+rcpc-immo,+rdm,+sb,+sel2,+sha2,+sha3,+sme,+sme2,+sme-f64f64,+sme-i16i64,+spe-eef,+specrestrict,+ssbs,+tlb-rmi,+tracev8.4,+uaops,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8.6a,+v8.7a,+v8a,+vh,+wfxt,+xs,+zcm,+zcz,+zcz-gp,-addr-lsl-slow-14,-aggressive-fma,-alu-lsl-fast,-ascend-store-address,-avoid-ldapur,-balance-fp-ops,-brbe,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-chk,-clrbhb,-cmp-bcc-fusion,-cmpbr,-cpa,-crypto,-cssc,-d128,-disable-ldp,-disable-stp,-enable-select-opt,-ete,-exynos-cheap-as-move,-f32mm,-f64mm,-f8f16mm,-f8f32mm,-faminmax,-fix-cortex-a53-835769,-fmv,-force-32bit-jump-tables,-fp8,-fp8dot2,-fp8dot4,-fp8fma,-fprcvt,-fujitsu-monaka,-fuse-addsub-2reg-const1,-gcs,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-ite,-ldp-aligned-only,-ls64,-lse128,-lsfe,-lsui,-lut,-mec,-mops,-mte,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-sve-fp-ld1r,-no-zcz-fp,-occmo,-outline-atomics,-pauth-lr,-pcdphint,-pops,-predictable-select-expensive,-prfm-slc-target,-rand,-rasv2,-rcpc3,-reserve-lr-for-ra,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme2p1,-sme2p2,-sme-b16b16,-sme-f16f16,-sme-f8f16,-sme-f8f32,-sme-fa64,-sme-lutv2,-sme-mop4,-sme-tmop,-spe,-specres2,-ssve-aes,-ssve-bitperm,-ssve-fp8dot2,-ssve-fp8dot4,-ssve-fp8fma,-store-pair-suppress,-stp-aligned-only,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-sve2p2,-sve-aes,-sve-aes2,-sve-b16b16,-sve-bfscale,-sve-bitperm,-sve-f16f32mm,-tagged-globals,-the,-tlbiw,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tpidrro-el0,-trbe,-use-experimental-zeroing-pseudos,-use-fixed-over-scalable-if-equal-cost,-use-postra-scheduler,-use-reciprocal-square-root,-v8.8a,-v8.9a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9.5a,-v9.6a,-v9a,-zcz-fp-workaround" }
attributes #5 = { mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #6 = { nofree norecurse nosync nounwind memory(write, argmem: readwrite, inaccessiblemem: none) uwtable "frame-pointer"="all" "target-cpu"="apple-m4" "target-features"="+aes,+alternate-sextload-cvt-f32-pattern,+altnzcv,+am,+amvs,+arith-bcc-fusion,+arith-cbz-fusion,+bf16,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+CONTEXTIDREL2,+crc,+disable-latency-sched-heuristic,+dit,+dotprod,+ecv,+el2vmsa,+el3,+fgt,+flagm,+fp16fml,+fp-armv8,+fpac,+fptoint,+fullfp16,+fuse-address,+fuse-adrp-add,+fuse-aes,+fuse-arith-logic,+fuse-crypto-eor,+fuse-csel,+fuse-literals,+hcx,+i8mm,+jsconv,+lor,+lse,+lse2,+mpam,+neon,+nv,+pan,+pan-rwv,+pauth,+perfmon,+predres,+ras,+rcpc,+rcpc-immo,+rdm,+sb,+sel2,+sha2,+sha3,+sme,+sme2,+sme-f64f64,+sme-i16i64,+spe-eef,+specrestrict,+ssbs,+tlb-rmi,+tracev8.4,+uaops,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8.6a,+v8.7a,+v8a,+vh,+wfxt,+xs,+zcm,+zcz,+zcz-gp,-addr-lsl-slow-14,-aggressive-fma,-alu-lsl-fast,-ascend-store-address,-avoid-ldapur,-balance-fp-ops,-brbe,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-chk,-clrbhb,-cmp-bcc-fusion,-cmpbr,-cpa,-crypto,-cssc,-d128,-disable-ldp,-disable-stp,-enable-select-opt,-ete,-exynos-cheap-as-move,-f32mm,-f64mm,-f8f16mm,-f8f32mm,-faminmax,-fix-cortex-a53-835769,-fmv,-force-32bit-jump-tables,-fp8,-fp8dot2,-fp8dot4,-fp8fma,-fprcvt,-fujitsu-monaka,-fuse-addsub-2reg-const1,-gcs,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-ite,-ldp-aligned-only,-ls64,-lse128,-lsfe,-lsui,-lut,-mec,-mops,-mte,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-sve-fp-ld1r,-no-zcz-fp,-occmo,-outline-atomics,-pauth-lr,-pcdphint,-pops,-predictable-select-expensive,-prfm-slc-target,-rand,-rasv2,-rcpc3,-reserve-lr-for-ra,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme2p1,-sme2p2,-sme-b16b16,-sme-f16f16,-sme-f8f16,-sme-f8f32,-sme-fa64,-sme-lutv2,-sme-mop4,-sme-tmop,-spe,-specres2,-ssve-aes,-ssve-bitperm,-ssve-fp8dot2,-ssve-fp8dot4,-ssve-fp8fma,-store-pair-suppress,-stp-aligned-only,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-sve2p2,-sve-aes,-sve-aes2,-sve-b16b16,-sve-bfscale,-sve-bitperm,-sve-f16f32mm,-tagged-globals,-the,-tlbiw,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tpidrro-el0,-trbe,-use-experimental-zeroing-pseudos,-use-fixed-over-scalable-if-equal-cost,-use-postra-scheduler,-use-reciprocal-square-root,-v8.8a,-v8.9a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9.5a,-v9.6a,-v9a,-zcz-fp-workaround" }
attributes #7 = { nounwind uwtable "frame-pointer"="all" "target-cpu"="apple-m4" "target-features"="+aes,+alternate-sextload-cvt-f32-pattern,+altnzcv,+am,+amvs,+arith-bcc-fusion,+arith-cbz-fusion,+bf16,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+CONTEXTIDREL2,+crc,+disable-latency-sched-heuristic,+dit,+dotprod,+ecv,+el2vmsa,+el3,+fgt,+flagm,+fp16fml,+fp-armv8,+fpac,+fptoint,+fullfp16,+fuse-address,+fuse-adrp-add,+fuse-aes,+fuse-arith-logic,+fuse-crypto-eor,+fuse-csel,+fuse-literals,+hcx,+i8mm,+jsconv,+lor,+lse,+lse2,+mpam,+neon,+nv,+pan,+pan-rwv,+pauth,+perfmon,+predres,+ras,+rcpc,+rcpc-immo,+rdm,+sb,+sel2,+sha2,+sha3,+sme,+sme2,+sme-f64f64,+sme-i16i64,+spe-eef,+specrestrict,+ssbs,+tlb-rmi,+tracev8.4,+uaops,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8.6a,+v8.7a,+v8a,+vh,+wfxt,+xs,+zcm,+zcz,+zcz-gp,-addr-lsl-slow-14,-aggressive-fma,-alu-lsl-fast,-ascend-store-address,-avoid-ldapur,-balance-fp-ops,-brbe,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-chk,-clrbhb,-cmp-bcc-fusion,-cmpbr,-cpa,-crypto,-cssc,-d128,-disable-ldp,-disable-stp,-enable-select-opt,-ete,-exynos-cheap-as-move,-f32mm,-f64mm,-f8f16mm,-f8f32mm,-faminmax,-fix-cortex-a53-835769,-fmv,-force-32bit-jump-tables,-fp8,-fp8dot2,-fp8dot4,-fp8fma,-fprcvt,-fujitsu-monaka,-fuse-addsub-2reg-const1,-gcs,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-ite,-ldp-aligned-only,-ls64,-lse128,-lsfe,-lsui,-lut,-mec,-mops,-mte,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-sve-fp-ld1r,-no-zcz-fp,-occmo,-outline-atomics,-pauth-lr,-pcdphint,-pops,-predictable-select-expensive,-prfm-slc-target,-rand,-rasv2,-rcpc3,-reserve-lr-for-ra,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme2p1,-sme2p2,-sme-b16b16,-sme-f16f16,-sme-f8f16,-sme-f8f32,-sme-fa64,-sme-lutv2,-sme-mop4,-sme-tmop,-spe,-specres2,-ssve-aes,-ssve-bitperm,-ssve-fp8dot2,-ssve-fp8dot4,-ssve-fp8fma,-store-pair-suppress,-stp-aligned-only,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-sve2p2,-sve-aes,-sve-aes2,-sve-b16b16,-sve-bfscale,-sve-bitperm,-sve-f16f32mm,-tagged-globals,-the,-tlbiw,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tpidrro-el0,-trbe,-use-experimental-zeroing-pseudos,-use-fixed-over-scalable-if-equal-cost,-use-postra-scheduler,-use-reciprocal-square-root,-v8.8a,-v8.9a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9.5a,-v9.6a,-v9a,-zcz-fp-workaround" }
attributes #8 = { mustprogress nofree norecurse nosync nounwind willreturn memory(none) uwtable "frame-pointer"="all" "target-cpu"="apple-m4" "target-features"="+aes,+alternate-sextload-cvt-f32-pattern,+altnzcv,+am,+amvs,+arith-bcc-fusion,+arith-cbz-fusion,+bf16,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+CONTEXTIDREL2,+crc,+disable-latency-sched-heuristic,+dit,+dotprod,+ecv,+el2vmsa,+el3,+fgt,+flagm,+fp16fml,+fp-armv8,+fpac,+fptoint,+fullfp16,+fuse-address,+fuse-adrp-add,+fuse-aes,+fuse-arith-logic,+fuse-crypto-eor,+fuse-csel,+fuse-literals,+hcx,+i8mm,+jsconv,+lor,+lse,+lse2,+mpam,+neon,+nv,+pan,+pan-rwv,+pauth,+perfmon,+predres,+ras,+rcpc,+rcpc-immo,+rdm,+sb,+sel2,+sha2,+sha3,+sme,+sme2,+sme-f64f64,+sme-i16i64,+spe-eef,+specrestrict,+ssbs,+tlb-rmi,+tracev8.4,+uaops,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8.6a,+v8.7a,+v8a,+vh,+wfxt,+xs,+zcm,+zcz,+zcz-gp,-addr-lsl-slow-14,-aggressive-fma,-alu-lsl-fast,-ascend-store-address,-avoid-ldapur,-balance-fp-ops,-brbe,-call-saved-x10,-call-saved-x11,-call-saved-x12,-call-saved-x13,-call-saved-x14,-call-saved-x15,-call-saved-x18,-call-saved-x8,-call-saved-x9,-chk,-clrbhb,-cmp-bcc-fusion,-cmpbr,-cpa,-crypto,-cssc,-d128,-disable-ldp,-disable-stp,-enable-select-opt,-ete,-exynos-cheap-as-move,-f32mm,-f64mm,-f8f16mm,-f8f32mm,-faminmax,-fix-cortex-a53-835769,-fmv,-force-32bit-jump-tables,-fp8,-fp8dot2,-fp8dot4,-fp8fma,-fprcvt,-fujitsu-monaka,-fuse-addsub-2reg-const1,-gcs,-harden-sls-blr,-harden-sls-nocomdat,-harden-sls-retbr,-hbc,-ite,-ldp-aligned-only,-ls64,-lse128,-lsfe,-lsui,-lut,-mec,-mops,-mte,-nmi,-no-bti-at-return-twice,-no-neg-immediates,-no-sve-fp-ld1r,-no-zcz-fp,-occmo,-outline-atomics,-pauth-lr,-pcdphint,-pops,-predictable-select-expensive,-prfm-slc-target,-rand,-rasv2,-rcpc3,-reserve-lr-for-ra,-reserve-x1,-reserve-x10,-reserve-x11,-reserve-x12,-reserve-x13,-reserve-x14,-reserve-x15,-reserve-x18,-reserve-x2,-reserve-x20,-reserve-x21,-reserve-x22,-reserve-x23,-reserve-x24,-reserve-x25,-reserve-x26,-reserve-x27,-reserve-x28,-reserve-x3,-reserve-x4,-reserve-x5,-reserve-x6,-reserve-x7,-reserve-x9,-rme,-slow-misaligned-128store,-slow-paired-128,-slow-strqro-store,-sm4,-sme2p1,-sme2p2,-sme-b16b16,-sme-f16f16,-sme-f8f16,-sme-f8f32,-sme-fa64,-sme-lutv2,-sme-mop4,-sme-tmop,-spe,-specres2,-ssve-aes,-ssve-bitperm,-ssve-fp8dot2,-ssve-fp8dot4,-ssve-fp8fma,-store-pair-suppress,-stp-aligned-only,-strict-align,-sve,-sve2,-sve2-aes,-sve2-bitperm,-sve2-sha3,-sve2-sm4,-sve2p1,-sve2p2,-sve-aes,-sve-aes2,-sve-b16b16,-sve-bfscale,-sve-bitperm,-sve-f16f32mm,-tagged-globals,-the,-tlbiw,-tme,-tpidr-el1,-tpidr-el2,-tpidr-el3,-tpidrro-el0,-trbe,-use-experimental-zeroing-pseudos,-use-fixed-over-scalable-if-equal-cost,-use-postra-scheduler,-use-reciprocal-square-root,-v8.8a,-v8.9a,-v8r,-v9.1a,-v9.2a,-v9.3a,-v9.4a,-v9.5a,-v9.6a,-v9a,-zcz-fp-workaround" }
attributes #9 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #10 = { nocallback nofree nosync nounwind willreturn memory(argmem: read) }
attributes #11 = { nounwind }

!llvm.module.flags = !{!0}

!0 = !{i32 8, !"PIC Level", i32 2}
!1 = distinct !{!1, !2, !3}
!2 = !{!"llvm.loop.isvectorized", i32 1}
!3 = !{!"llvm.loop.unroll.runtime.disable"}
!4 = distinct !{!4, !2}
!5 = distinct !{!5, !2, !3}
!6 = distinct !{!6, !2}
!7 = distinct !{!7, !2, !3}
!8 = distinct !{!8, !2}
!9 = !{!10}
!10 = distinct !{!10, !11}
!11 = distinct !{!11, !"LVerDomain"}
!12 = !{!13}
!13 = distinct !{!13, !11}
!14 = distinct !{!14, !2, !3}
!15 = distinct !{!15, !2}
!16 = distinct !{!16, !2, !3}
!17 = distinct !{!17, !2}
!18 = distinct !{!18, !2, !3}
!19 = distinct !{!19, !2}
!20 = distinct !{!20, !2, !3}
!21 = distinct !{!21, !3, !2}
!22 = distinct !{!22, !2, !3}
!23 = distinct !{!23, !2}
!24 = distinct !{!24, !25}
!25 = !{!"llvm.loop.unroll.disable"}
!26 = distinct !{!26, !2, !3}
!27 = distinct !{!27, !2, !3}
!28 = distinct !{!28, !3, !2}
!29 = distinct !{!29, !2, !3}
!30 = distinct !{!30, !3, !2}
!31 = distinct !{!31, !25}
!32 = distinct !{!32, !2, !3}
!33 = distinct !{!33, !2, !3}
!34 = distinct !{!34, !3, !2}
!35 = distinct !{!35, !2, !3}
!36 = distinct !{!36, !3, !2}
