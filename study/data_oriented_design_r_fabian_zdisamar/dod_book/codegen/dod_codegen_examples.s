	.build_version macos, 26, 4, 1
	.section	__TEXT,__text,regular,pure_instructions
	.globl	_sumOpticalDepth
	.p2align	2
_sumOpticalDepth:
	.cfi_startproc
	cbz	x1, LBB0_3
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_remember_state
	cmp	x1, #4
	b.hs	LBB0_4
	mov	x8, #0
	movi	d0, #0000000000000000
	b	LBB0_7
LBB0_3:
	.cfi_def_cfa wsp, 0
	.cfi_same_value w30
	.cfi_same_value w29
	movi	d0, #0000000000000000
	ret
LBB0_4:
	.cfi_restore_state
	and	x8, x1, #0xfffffffffffffffc
	add	x9, x0, #48
	neg	x10, x8
	movi	d0, #0000000000000000
LBB0_5:
	ldur	d1, [x9, #-48]
	ldur	d2, [x9, #-24]
	ldr	d3, [x9]
	ldr	d4, [x9, #24]
	fadd	d0, d0, d1
	fadd	d0, d0, d2
	fadd	d0, d0, d3
	fadd	d0, d0, d4
	add	x9, x9, #96
	adds	x10, x10, #4
	b.ne	LBB0_5
	cmp	x1, x8
	b.eq	LBB0_9
LBB0_7:
	mov	w9, #24
	madd	x9, x8, x9, x0
	sub	x8, x8, x1
LBB0_8:
	ldr	d1, [x9], #24
	fadd	d0, d0, d1
	adds	x8, x8, #1
	b.lo	LBB0_8
LBB0_9:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.globl	_sumOpticalDepthScienceLayer
	.p2align	2
_sumOpticalDepthScienceLayer:
	.cfi_startproc
	cbz	x1, LBB1_3
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_remember_state
	cmp	x1, #4
	b.hs	LBB1_4
	mov	x8, #0
	movi	d0, #0000000000000000
	b	LBB1_7
LBB1_3:
	.cfi_def_cfa wsp, 0
	.cfi_same_value w30
	.cfi_same_value w29
	movi	d0, #0000000000000000
	ret
LBB1_4:
	.cfi_restore_state
	and	x8, x1, #0xfffffffffffffffc
	add	x9, x0, #80
	neg	x10, x8
	movi	d0, #0000000000000000
LBB1_5:
	ldur	x11, [x9, #-64]
	ldur	x12, [x9, #-32]
	ldr	x13, [x9]
	ldr	x14, [x9, #32]
	ldr	d1, [x11]
	ldr	d2, [x12]
	ldr	d3, [x13]
	ldr	d4, [x14]
	fadd	d0, d0, d1
	fadd	d0, d0, d2
	fadd	d0, d0, d3
	fadd	d0, d0, d4
	add	x9, x9, #128
	adds	x10, x10, #4
	b.ne	LBB1_5
	cmp	x1, x8
	b.eq	LBB1_9
LBB1_7:
	add	x9, x0, x8, lsl #5
	add	x9, x9, #16
	sub	x8, x8, x1
LBB1_8:
	ldr	x10, [x9], #32
	ldr	d1, [x10]
	fadd	d0, d0, d1
	adds	x8, x8, #1
	b.lo	LBB1_8
LBB1_9:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.globl	_prepareEveryProduct
	.p2align	2
_prepareEveryProduct:
	.cfi_startproc
	sub	sp, sp, #96
	.cfi_def_cfa_offset 96
	stp	d13, d12, [sp, #16]
	stp	d11, d10, [sp, #32]
	stp	d9, d8, [sp, #48]
	stp	x20, x19, [sp, #64]
	stp	x29, x30, [sp, #80]
	add	x29, sp, #80
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	.cfi_offset b8, -40
	.cfi_offset b9, -48
	.cfi_offset b10, -56
	.cfi_offset b11, -64
	.cfi_offset b12, -72
	.cfi_offset b13, -80
	cbz	x2, LBB2_3
	mov	x19, x2
	ldp	d9, d10, [x0]
	movi	d8, #0000000000000000
	ldp	d11, d12, [x1]
LBB2_2:
	mov	x0, sp
	fmov	d0, d9
	fmov	d1, d10
	fmov	d2, d11
	fmov	d3, d12
	bl	_dod_codegen_examples.prepareInputForCodegen
	ldp	d0, d1, [sp]
	bl	_dod_codegen_examples.runPreparedForCodegen
	fadd	d8, d8, d0
	subs	x19, x19, #1
	b.ne	LBB2_2
	b	LBB2_4
LBB2_3:
	movi	d8, #0000000000000000
LBB2_4:
	fmov	d0, d8
	.cfi_def_cfa wsp, 96
	ldp	x29, x30, [sp, #80]
	ldp	x20, x19, [sp, #64]
	ldp	d9, d8, [sp, #48]
	ldp	d11, d10, [sp, #32]
	ldp	d13, d12, [sp, #16]
	add	sp, sp, #96
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	.cfi_restore w19
	.cfi_restore w20
	.cfi_restore b8
	.cfi_restore b9
	.cfi_restore b10
	.cfi_restore b11
	.cfi_restore b12
	.cfi_restore b13
	ret
	.cfi_endproc

	.p2align	2
_dod_codegen_examples.prepareInputForCodegen:
	.cfi_startproc
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	fmul	d0, d0, d2
	fadd	d1, d1, d3
	stp	d0, d1, [x0]
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.p2align	2
_dod_codegen_examples.runPreparedForCodegen:
	.cfi_startproc
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	fadd	d0, d0, d1
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.globl	_runAlreadyPreparedProducts
	.p2align	2
_runAlreadyPreparedProducts:
	.cfi_startproc
	cbz	x1, LBB5_3
	stp	x20, x19, [sp, #-32]!
	.cfi_def_cfa_offset 32
	stp	x29, x30, [sp, #16]
	add	x29, sp, #16
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	.cfi_remember_state
	mov	x19, x1
	ldp	d0, d1, [x0]
	bl	_dod_codegen_examples.runPreparedForCodegen
	cmp	x19, #4
	b.hs	LBB5_4
	mov	x8, #0
	movi	d1, #0000000000000000
	b	LBB5_7
LBB5_3:
	.cfi_def_cfa wsp, 0
	.cfi_same_value w30
	.cfi_same_value w29
	.cfi_same_value w19
	.cfi_same_value w20
	movi	d0, #0000000000000000
	ret
LBB5_4:
	.cfi_restore_state
	and	x8, x19, #0xfffffffffffffffc
	neg	x9, x8
	movi	d1, #0000000000000000
LBB5_5:
	fadd	d1, d0, d1
	fadd	d1, d0, d1
	fadd	d1, d0, d1
	fadd	d1, d0, d1
	adds	x9, x9, #4
	b.ne	LBB5_5
	cmp	x19, x8
	b.eq	LBB5_9
LBB5_7:
	sub	x8, x8, x19
LBB5_8:
	fadd	d1, d0, d1
	adds	x8, x8, #1
	b.lo	LBB5_8
LBB5_9:
	.cfi_def_cfa wsp, 32
	ldp	x29, x30, [sp, #16]
	ldp	x20, x19, [sp], #32
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	.cfi_restore w19
	.cfi_restore w20
	fmov	d0, d1
	ret
	.cfi_endproc

	.globl	_fillLayerSource
	.p2align	2
_fillLayerSource:
	.cfi_startproc
	cbz	x2, LBB6_10
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	cmp	x2, #9
	b.lo	LBB6_4
	add	x8, x1, x2, lsl #3
	cmp	x0, x8
	b.hs	LBB6_5
	mov	w8, #24
	madd	x8, x2, x8, x0
	sub	x8, x8, #8
	cmp	x1, x8
	b.hs	LBB6_5
LBB6_4:
	mov	x8, #0
	b	LBB6_7
LBB6_5:
	ands	x8, x2, #0x7
	mov	w9, #8
	csel	x11, x9, x8, eq
	sub	x8, x2, x11
	dup.2d	v1, v0[0]
	add	x9, x1, #32
	add	x10, x0, #96
	sub	x11, x11, x2
LBB6_6:
	sub	x12, x10, #96
	sub	x13, x10, #48
	ld3.2d	{ v2, v3, v4 }, [x12]
	ld3.2d	{ v5, v6, v7 }, [x13]
	mov	x12, x10
	ld3.2d	{ v16, v17, v18 }, [x12], #48
	ld3.2d	{ v19, v20, v21 }, [x12]
	mov.16b	v22, v1
	fmla.2d	v22, v3, v2
	mov.16b	v2, v1
	fmla.2d	v2, v6, v5
	mov.16b	v3, v1
	fmla.2d	v3, v17, v16
	mov.16b	v4, v1
	fmla.2d	v4, v20, v19
	stp	q22, q2, [x9, #-32]
	stp	q3, q4, [x9], #64
	add	x10, x10, #192
	adds	x11, x11, #8
	b.ne	LBB6_6
LBB6_7:
	add	x9, x1, x8, lsl #3
	mov	w10, #24
	madd	x10, x8, x10, x0
	add	x10, x10, #8
	sub	x8, x8, x2
LBB6_8:
	ldp	d1, d2, [x10, #-8]
	fmadd	d1, d1, d2, d0
	str	d1, [x9], #8
	add	x10, x10, #24
	adds	x8, x8, #1
	b.lo	LBB6_8
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
LBB6_10:
	ret
	.cfi_endproc

	.globl	_appendLayerSourceChecked
	.p2align	2
_appendLayerSourceChecked:
	.cfi_startproc
	mov	x8, x0
	ldr	x0, [x1, #8]
	cbz	x2, LBB7_5
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	add	x8, x8, #8
LBB7_2:
	ldr	x9, [x1, #16]
	cmp	x0, x9
	b.hs	LBB7_4
	ldp	d2, d1, [x8, #-8]
	ldr	x9, [x1]
	fmadd	d1, d2, d1, d0
	str	d1, [x9, x0, lsl #3]
	ldr	x9, [x1, #8]
	add	x0, x9, #1
	str	x0, [x1, #8]
	add	x8, x8, #24
	subs	x2, x2, #1
	b.ne	LBB7_2
LBB7_4:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
LBB7_5:
	ret
	.cfi_endproc

	.globl	_fillReflectance
	.p2align	2
_fillReflectance:
	.cfi_startproc
	cbz	x3, LBB8_6
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_remember_state
	cmp	x3, #8
	b.hs	LBB8_7
	mov	x8, #0
LBB8_3:
	lsl	x11, x8, #3
	add	x9, x2, x11
	add	x10, x1, x11
	add	x11, x0, x11
	sub	x8, x8, x3
	movi	d0, #0000000000000000
LBB8_4:
	ldr	d1, [x11], #8
	ldr	d2, [x10], #8
	fdiv	d1, d1, d2
	fcmp	d2, #0.0
	fcsel	d1, d1, d0, ne
	str	d1, [x9], #8
	adds	x8, x8, #1
	b.lo	LBB8_4
LBB8_5:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
LBB8_6:
	ret
LBB8_7:
	.cfi_restore_state
	mov	x8, #0
	sub	x9, x2, x0
	cmp	x9, #64
	b.lo	LBB8_3
	sub	x9, x2, x1
	cmp	x9, #64
	b.lo	LBB8_3
	and	x8, x3, #0xfffffffffffffff8
	add	x9, x2, #32
	add	x10, x0, #32
	add	x11, x1, #32
	neg	x12, x8
LBB8_10:
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	ldp	q4, q5, [x11, #-32]
	ldp	q6, q7, [x11], #64
	fcmeq.2d	v16, v4, #0.0
	fcmeq.2d	v17, v5, #0.0
	fcmeq.2d	v18, v6, #0.0
	fcmeq.2d	v19, v7, #0.0
	fdiv.2d	v0, v0, v4
	fdiv.2d	v1, v1, v5
	fdiv.2d	v2, v2, v6
	fdiv.2d	v3, v3, v7
	bic.16b	v0, v0, v16
	bic.16b	v1, v1, v17
	bic.16b	v2, v2, v18
	bic.16b	v3, v3, v19
	stp	q0, q1, [x9, #-32]
	stp	q2, q3, [x9], #64
	adds	x12, x12, #8
	b.ne	LBB8_10
	cmp	x3, x8
	b.ne	LBB8_3
	b	LBB8_5
	.cfi_endproc

	.globl	_fillReflectanceAllocateLike
	.p2align	2
_fillReflectanceAllocateLike:
	.cfi_startproc
	stp	d9, d8, [sp, #-64]!
	.cfi_def_cfa_offset 64
	stp	x22, x21, [sp, #16]
	stp	x20, x19, [sp, #32]
	stp	x29, x30, [sp, #48]
	add	x29, sp, #48
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	.cfi_offset w21, -40
	.cfi_offset w22, -48
	.cfi_offset b8, -56
	.cfi_offset b9, -64
	.cfi_remember_state
	mov	x20, x3
	mov	x22, x2
	mov	x21, x1
	mov	x19, x0
	ldr	x8, [x0]
	mov	x0, x3
	blr	x8
	cbz	x20, LBB9_6
	cmp	x20, #8
	b.hs	LBB9_8
	mov	x8, #0
LBB9_3:
	lsl	x11, x8, #3
	add	x9, x0, x11
	add	x10, x22, x11
	add	x11, x21, x11
	sub	x8, x8, x20
	movi	d0, #0000000000000000
LBB9_4:
	ldr	d1, [x11], #8
	ldr	d2, [x10], #8
	fdiv	d1, d1, d2
	fcmp	d2, #0.0
	fcsel	d1, d1, d0, ne
	str	d1, [x9], #8
	adds	x8, x8, #1
	b.lo	LBB9_4
LBB9_5:
	ldr	d8, [x0]
	b	LBB9_7
LBB9_6:
	movi	d8, #0000000000000000
LBB9_7:
	ldr	x8, [x19, #8]
	blr	x8
	fmov	d0, d8
	.cfi_def_cfa wsp, 64
	ldp	x29, x30, [sp, #48]
	ldp	x20, x19, [sp, #32]
	ldp	x22, x21, [sp, #16]
	ldp	d9, d8, [sp], #64
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	.cfi_restore w19
	.cfi_restore w20
	.cfi_restore w21
	.cfi_restore w22
	.cfi_restore b8
	.cfi_restore b9
	ret
LBB9_8:
	.cfi_restore_state
	mov	x8, #0
	sub	x9, x0, x21
	cmp	x9, #64
	b.lo	LBB9_3
	sub	x9, x0, x22
	cmp	x9, #64
	b.lo	LBB9_3
	and	x8, x20, #0xfffffffffffffff8
	add	x9, x0, #32
	add	x10, x21, #32
	add	x11, x22, #32
	neg	x12, x8
LBB9_11:
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	ldp	q4, q5, [x11, #-32]
	ldp	q6, q7, [x11], #64
	fcmeq.2d	v16, v4, #0.0
	fcmeq.2d	v17, v5, #0.0
	fcmeq.2d	v18, v6, #0.0
	fcmeq.2d	v19, v7, #0.0
	fdiv.2d	v0, v0, v4
	fdiv.2d	v1, v1, v5
	fdiv.2d	v2, v2, v6
	fdiv.2d	v3, v3, v7
	bic.16b	v0, v0, v16
	bic.16b	v1, v1, v17
	bic.16b	v2, v2, v18
	bic.16b	v3, v3, v19
	stp	q0, q1, [x9, #-32]
	stp	q2, q3, [x9], #64
	adds	x12, x12, #8
	b.ne	LBB9_11
	cmp	x20, x8
	b.ne	LBB9_3
	b	LBB9_5
	.cfi_endproc

	.globl	_fillReflectanceNoAlias
	.p2align	2
_fillReflectanceNoAlias:
	.cfi_startproc
	cbz	x3, LBB10_9
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	cmp	x3, #8
	b.hs	LBB10_3
	mov	x8, #0
	b	LBB10_6
LBB10_3:
	and	x8, x3, #0xfffffffffffffff8
	add	x9, x2, #32
	add	x10, x0, #32
	add	x11, x1, #32
	neg	x12, x8
LBB10_4:
	ldp	q0, q1, [x10, #-32]
	ldp	q2, q3, [x10], #64
	ldp	q4, q5, [x11, #-32]
	ldp	q6, q7, [x11], #64
	fcmeq.2d	v16, v4, #0.0
	fcmeq.2d	v17, v5, #0.0
	fcmeq.2d	v18, v6, #0.0
	fcmeq.2d	v19, v7, #0.0
	fdiv.2d	v0, v0, v4
	fdiv.2d	v1, v1, v5
	fdiv.2d	v2, v2, v6
	fdiv.2d	v3, v3, v7
	bic.16b	v0, v0, v16
	bic.16b	v1, v1, v17
	bic.16b	v2, v2, v18
	bic.16b	v3, v3, v19
	stp	q0, q1, [x9, #-32]
	stp	q2, q3, [x9], #64
	adds	x12, x12, #8
	b.ne	LBB10_4
	cmp	x3, x8
	b.eq	LBB10_8
LBB10_6:
	lsl	x11, x8, #3
	add	x9, x2, x11
	add	x10, x1, x11
	add	x11, x0, x11
	sub	x8, x8, x3
	movi	d0, #0000000000000000
LBB10_7:
	ldr	d1, [x11], #8
	ldr	d2, [x10], #8
	fdiv	d1, d1, d2
	fcmp	d2, #0.0
	fcsel	d1, d1, d0, ne
	str	d1, [x9], #8
	adds	x8, x8, #1
	b.lo	LBB10_7
LBB10_8:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
LBB10_9:
	ret
	.cfi_endproc

	.globl	_integrateIndexed
	.p2align	2
_integrateIndexed:
	.cfi_startproc
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	cbz	x4, LBB11_7
	mov	x8, #0
	b	LBB11_4
LBB11_2:
	movi	d0, #0000000000000000
LBB11_3:
	str	d0, [x3, x8, lsl #3]
	add	x8, x8, #1
	cmp	x8, x4
	b.eq	LBB11_7
LBB11_4:
	add	x9, x0, x8, lsl #3
	ldr	w10, [x9, #4]
	cbz	w10, LBB11_2
	ldr	w9, [x9]
	add	x10, x10, x9
	movi	d0, #0000000000000000
LBB11_6:
	ldr	w11, [x1, x9, lsl #2]
	lsl	x11, x11, #4
	ldr	d1, [x2, x11]
	fadd	d0, d0, d1
	add	x9, x9, #1
	cmp	x9, x10
	b.lo	LBB11_6
	b	LBB11_3
LBB11_7:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.globl	_integrateLinearSearch
	.p2align	2
_integrateLinearSearch:
	.cfi_startproc
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	cbz	x5, LBB12_16
	mov	x8, #0
	cbnz	x6, LBB12_4
	b	LBB12_13
LBB12_2:
	movi	d0, #0000000000000000
LBB12_3:
	str	d0, [x4, x8, lsl #3]
	add	x8, x8, #1
	cmp	x8, x5
	b.eq	LBB12_16
LBB12_4:
	add	x9, x0, x8, lsl #3
	ldr	w10, [x9, #4]
	cbz	w10, LBB12_2
	ldr	w9, [x9]
	add	x10, x10, x9
	movi	d0, #0000000000000000
	b	LBB12_8
LBB12_6:
	mov	x11, x6
LBB12_7:
	lsl	x11, x11, #4
	ldr	d1, [x3, x11]
	fadd	d0, d0, d1
	add	x9, x9, #1
	cmp	x9, x10
	b.hs	LBB12_3
LBB12_8:
	mov	x11, #0
	ldr	d1, [x1, x9, lsl #3]
LBB12_9:
	ldr	d2, [x2, x11, lsl #3]
	fcmp	d2, d1
	b.eq	LBB12_7
	add	x11, x11, #1
	cmp	x6, x11
	b.ne	LBB12_9
	b	LBB12_6
LBB12_11:
	movi	d0, #0000000000000000
LBB12_12:
	str	d0, [x4, x8, lsl #3]
	add	x8, x8, #1
	cmp	x8, x5
	b.eq	LBB12_16
LBB12_13:
	add	x9, x0, x8, lsl #3
	ldr	w10, [x9, #4]
	cbz	w10, LBB12_11
	ldr	w9, [x9]
	add	x10, x10, x9
	ldr	d1, [x3]
	movi	d0, #0000000000000000
LBB12_15:
	fadd	d0, d1, d0
	add	x9, x9, #1
	cmp	x9, x10
	b.lo	LBB12_15
	b	LBB12_12
LBB12_16:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.globl	_lowerBound
	.p2align	2
_lowerBound:
	.cfi_startproc
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	mov	x8, #0
	cbz	x1, LBB13_2
LBB13_1:
	sub	x9, x1, x8
	add	x9, x8, x9, lsr #1
	ldr	d1, [x0, x9, lsl #3]
	fcmp	d1, d0
	csinc	x8, x8, x9, pl
	csel	x1, x1, x9, mi
	cmp	x8, x1
	b.lo	LBB13_1
LBB13_2:
	mov	x0, x8
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.globl	_lowerBoundInModel
	.p2align	2
_lowerBoundInModel:
	.cfi_startproc
	ldr	x9, [x0, #8]
	cbz	x9, LBB14_4
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	mov	x8, x0
	mov	x0, #0
	ldr	x8, [x8]
LBB14_2:
	sub	x10, x9, x0
	add	x10, x0, x10, lsr #1
	ldr	d1, [x8, x10, lsl #3]
	fcmp	d1, d0
	csinc	x0, x0, x10, pl
	csel	x9, x9, x10, mi
	cmp	x0, x9
	b.lo	LBB14_2
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
LBB14_4:
	mov	x0, #0
	ret
	.cfi_endproc

	.globl	_lookupPayloadLinear
	.p2align	2
_lookupPayloadLinear:
	.cfi_startproc
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	cbz	x1, LBB15_4
	fmov	d1, d0
	add	x8, x0, #16
	mov	x9, x1
LBB15_2:
	ldur	d0, [x8, #-16]
	fcmp	d0, d1
	b.ge	LBB15_5
	add	x8, x8, #32
	subs	x9, x9, #1
	b.ne	LBB15_2
LBB15_4:
	add	x10, x0, x1, lsl #5
	ldur	d0, [x10, #-32]
	sub	x9, x10, #24
	sub	x8, x10, #16
	sub	x10, x10, #8
	b	LBB15_6
LBB15_5:
	add	x10, x8, #8
	sub	x9, x8, #8
LBB15_6:
	ldr	d3, [x10]
	ldr	d2, [x8]
	ldr	d1, [x9]
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.globl	_refreshDirty
	.p2align	2
_refreshDirty:
	.cfi_startproc
	cbz	x2, LBB16_9
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	mov	x8, #0
	cmp	x2, #8
	b.lo	LBB16_6
	sub	x9, x1, x0
	cmp	x9, #64
	b.lo	LBB16_6
	and	x8, x2, #0xfffffffffffffff8
	add	x9, x1, #32
	add	x10, x0, #32
	neg	x11, x8
	fmov.2d	v0, #1.00000000
LBB16_4:
	ldp	q1, q2, [x10, #-32]
	ldp	q3, q4, [x10], #64
	fadd.2d	v1, v1, v1
	fadd.2d	v2, v2, v2
	fadd.2d	v3, v3, v3
	fadd.2d	v4, v4, v4
	fadd.2d	v1, v1, v0
	fadd.2d	v2, v2, v0
	fadd.2d	v3, v3, v0
	fadd.2d	v4, v4, v0
	stp	q1, q2, [x9, #-32]
	stp	q3, q4, [x9], #64
	adds	x11, x11, #8
	b.ne	LBB16_4
	cmp	x2, x8
	b.eq	LBB16_8
LBB16_6:
	lsl	x10, x8, #3
	add	x9, x1, x10
	add	x10, x0, x10
	sub	x8, x8, x2
	fmov	d0, #1.00000000
LBB16_7:
	ldr	d1, [x10], #8
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	str	d1, [x9], #8
	adds	x8, x8, #1
	b.lo	LBB16_7
LBB16_8:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
LBB16_9:
	ret
	.cfi_endproc

	.globl	_refreshScanAllFlags
	.p2align	2
_refreshScanAllFlags:
	.cfi_startproc
	cbz	x3, LBB17_9
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_remember_state
	and	x8, x3, #0x7
	cmp	x3, #8
	b.hs	LBB17_10
	mov	x9, #0
LBB17_3:
	cbz	x8, LBB17_8
	lsl	x11, x9, #3
	add	x10, x0, x11
	add	x11, x2, x11
	add	x9, x1, x9
	fmov	d0, #1.00000000
	b	LBB17_6
LBB17_5:
	add	x10, x10, #8
	add	x11, x11, #8
	subs	x8, x8, #1
	b.eq	LBB17_8
LBB17_6:
	ldrb	w12, [x9], #1
	cbz	w12, LBB17_5
	ldr	d1, [x10]
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	str	d1, [x11]
	b	LBB17_5
LBB17_8:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
LBB17_9:
	ret
LBB17_10:
	.cfi_restore_state
	and	x9, x3, #0xfffffffffffffff8
	neg	x10, x9
	add	x11, x1, #3
	add	x12, x0, #32
	add	x13, x2, #32
	fmov	d0, #1.00000000
	b	LBB17_12
LBB17_11:
	add	x11, x11, #8
	add	x12, x12, #64
	add	x13, x13, #64
	adds	x10, x10, #8
	b.eq	LBB17_3
LBB17_12:
	ldurb	w14, [x11, #-3]
	cbz	w14, LBB17_14
	ldur	d1, [x12, #-32]
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	stur	d1, [x13, #-32]
LBB17_14:
	ldurb	w14, [x11, #-2]
	cbz	w14, LBB17_16
	ldur	d1, [x12, #-24]
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	stur	d1, [x13, #-24]
LBB17_16:
	ldurb	w14, [x11, #-1]
	cbz	w14, LBB17_18
	ldur	d1, [x12, #-16]
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	stur	d1, [x13, #-16]
LBB17_18:
	ldrb	w14, [x11]
	cbz	w14, LBB17_20
	ldur	d1, [x12, #-8]
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	stur	d1, [x13, #-8]
LBB17_20:
	ldrb	w14, [x11, #1]
	cbz	w14, LBB17_22
	ldr	d1, [x12]
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	str	d1, [x13]
LBB17_22:
	ldrb	w14, [x11, #2]
	cbz	w14, LBB17_24
	ldr	d1, [x12, #8]
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	str	d1, [x13, #8]
LBB17_24:
	ldrb	w14, [x11, #3]
	cbz	w14, LBB17_26
	ldr	d1, [x12, #16]
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	str	d1, [x13, #16]
LBB17_26:
	ldrb	w14, [x11, #4]
	cbz	w14, LBB17_11
	ldr	d1, [x12, #24]
	fadd	d1, d1, d1
	fadd	d1, d1, d0
	str	d1, [x13, #24]
	b	LBB17_11
	.cfi_endproc

	.globl	_ensureJacobianStorage
	.p2align	2
_ensureJacobianStorage:
	.cfi_startproc
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	cmp	x1, x0
	csel	x8, x1, x0, hi
	cmp	x0, #0
	csel	x0, xzr, x8, eq
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.globl	_prefixStarts
	.p2align	2
_prefixStarts:
	.cfi_startproc
	cbz	x2, LBB19_5
	str	wzr, [x1]
	subs	x8, x2, #1
	b.eq	LBB19_5
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	mov	w9, #0
	add	x10, x1, #4
LBB19_3:
	ldr	w11, [x0], #4
	add	w9, w11, w9
	str	w9, [x10], #4
	subs	x8, x8, #1
	b.ne	LBB19_3
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
LBB19_5:
	ret
	.cfi_endproc

	.globl	_startByResummingCounts
	.p2align	2
_startByResummingCounts:
	.cfi_startproc
	cbz	x1, LBB20_3
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_remember_state
	cmp	x1, #4
	b.hs	LBB20_4
	mov	w8, #0
	mov	x9, #0
	b	LBB20_13
LBB20_3:
	.cfi_def_cfa wsp, 0
	.cfi_same_value w30
	.cfi_same_value w29
	mov	w0, #0
	ret
LBB20_4:
	.cfi_restore_state
	cmp	x1, #16
	b.hs	LBB20_6
	mov	x9, #0
	mov	w8, #0
	b	LBB20_10
LBB20_6:
	and	x9, x1, #0xfffffffffffffff0
	add	x8, x0, #32
	neg	x10, x9
	movi.2d	v0, #0000000000000000
	movi.2d	v1, #0000000000000000
	movi.2d	v2, #0000000000000000
	movi.2d	v3, #0000000000000000
LBB20_7:
	ldp	q4, q5, [x8, #-32]
	ldp	q6, q7, [x8], #64
	add.4s	v0, v4, v0
	add.4s	v1, v5, v1
	add.4s	v2, v6, v2
	add.4s	v3, v7, v3
	adds	x10, x10, #16
	b.ne	LBB20_7
	add.4s	v0, v1, v0
	add.4s	v1, v2, v3
	add.4s	v0, v0, v1
	addv.4s	s0, v0
	fmov	w8, s0
	cmp	x1, x9
	b.eq	LBB20_15
	tst	x1, #0xc
	b.eq	LBB20_13
LBB20_10:
	mov	x10, x9
	and	x9, x1, #0xfffffffffffffffc
	movi.2d	v0, #0000000000000000
	mov.s	v0[0], w8
	add	x8, x0, x10, lsl #2
	sub	x10, x10, x9
LBB20_11:
	ldr	q1, [x8], #16
	add.4s	v0, v1, v0
	adds	x10, x10, #4
	b.ne	LBB20_11
	addv.4s	s0, v0
	fmov	w8, s0
	cmp	x1, x9
	b.eq	LBB20_15
LBB20_13:
	add	x10, x0, x9, lsl #2
	sub	x9, x9, x1
LBB20_14:
	ldr	w11, [x10], #4
	add	w8, w11, w8
	adds	x9, x9, #1
	b.lo	LBB20_14
LBB20_15:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	mov	x0, x8
	ret
	.cfi_endproc

	.globl	_workerSum
	.p2align	2
_workerSum:
	.cfi_startproc
	movi	d0, #0000000000000000
	subs	x8, x2, x1
	b.ls	LBB21_10
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	cmp	x8, #8
	b.hs	LBB21_3
	movi	d0, #0000000000000000
	b	LBB21_7
LBB21_3:
	and	x9, x8, #0xfffffffffffffff8
	add	x10, x0, x1, lsl #3
	add	x10, x10, #32
	neg	x11, x9
	movi	d0, #0000000000000000
LBB21_4:
	ldp	q1, q2, [x10, #-32]
	mov	d3, v1[1]
	mov	d4, v2[1]
	ldp	q5, q6, [x10], #64
	mov	d7, v5[1]
	mov	d16, v6[1]
	fadd	d0, d0, d1
	fadd	d0, d0, d3
	fadd	d0, d0, d2
	fadd	d0, d0, d4
	fadd	d0, d0, d5
	fadd	d0, d0, d7
	fadd	d0, d0, d6
	fadd	d0, d0, d16
	adds	x11, x11, #8
	b.ne	LBB21_4
	cmp	x8, x9
	b.eq	LBB21_9
	add	x1, x9, x1
	sub	x8, x2, x1
LBB21_7:
	add	x9, x0, x1, lsl #3
LBB21_8:
	ldr	d1, [x9], #8
	fadd	d0, d0, d1
	subs	x8, x8, #1
	b.ne	LBB21_8
LBB21_9:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
LBB21_10:
	ret
	.cfi_endproc

	.globl	_workerWriteEveryItem
	.p2align	2
_workerWriteEveryItem:
	.cfi_startproc
	str	xzr, [x1]
	movi	d0, #0000000000000000
	subs	x8, x2, x3
	b.hs	LBB22_4
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	add	x9, x0, x2, lsl #3
	movi	d0, #0000000000000000
LBB22_2:
	ldr	d1, [x9], #8
	fadd	d0, d0, d1
	str	d0, [x1]
	adds	x8, x8, #1
	b.lo	LBB22_2
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
LBB22_4:
	ret
	.cfi_endproc

	.globl	_sumSelected
	.p2align	2
_sumSelected:
	.cfi_startproc
	cbz	x2, LBB23_9
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_remember_state
	mov	x8, x0
	and	x9, x2, #0x7
	cmp	x2, #8
	b.hs	LBB23_10
	mov	x10, #0
	mov	w0, #0
LBB23_3:
	cbz	x9, LBB23_8
	add	x11, x1, x10, lsl #2
	add	x8, x8, x10
	b	LBB23_6
LBB23_5:
	add	x11, x11, #4
	subs	x9, x9, #1
	b.eq	LBB23_8
LBB23_6:
	ldrb	w10, [x8], #1
	cbz	w10, LBB23_5
	ldr	w10, [x11]
	add	w0, w10, w0
	b	LBB23_5
LBB23_8:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
LBB23_9:
	mov	w0, #0
	ret
LBB23_10:
	.cfi_restore_state
	mov	w0, #0
	and	x10, x2, #0xfffffffffffffff8
	neg	x11, x10
	add	x12, x8, #3
	add	x13, x1, #16
	b	LBB23_12
LBB23_11:
	add	x12, x12, #8
	add	x13, x13, #32
	adds	x11, x11, #8
	b.eq	LBB23_3
LBB23_12:
	ldurb	w14, [x12, #-3]
	cbz	w14, LBB23_14
	ldur	w14, [x13, #-16]
	add	w0, w14, w0
LBB23_14:
	ldurb	w14, [x12, #-2]
	cbz	w14, LBB23_16
	ldur	w14, [x13, #-12]
	add	w0, w14, w0
LBB23_16:
	ldurb	w14, [x12, #-1]
	cbz	w14, LBB23_18
	ldur	w14, [x13, #-8]
	add	w0, w14, w0
LBB23_18:
	ldrb	w14, [x12]
	cbz	w14, LBB23_20
	ldur	w14, [x13, #-4]
	add	w0, w14, w0
LBB23_20:
	ldrb	w14, [x12, #1]
	cbz	w14, LBB23_22
	ldr	w14, [x13]
	add	w0, w14, w0
LBB23_22:
	ldrb	w14, [x12, #2]
	cbz	w14, LBB23_24
	ldr	w14, [x13, #4]
	add	w0, w14, w0
LBB23_24:
	ldrb	w14, [x12, #3]
	cbz	w14, LBB23_26
	ldr	w14, [x13, #8]
	add	w0, w14, w0
LBB23_26:
	ldrb	w14, [x12, #4]
	cbz	w14, LBB23_11
	ldr	w14, [x13, #12]
	add	w0, w14, w0
	b	LBB23_11
	.cfi_endproc

	.globl	_sumGroupedValues
	.p2align	2
_sumGroupedValues:
	.cfi_startproc
	cbz	x1, LBB24_3
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_remember_state
	cmp	x1, #4
	b.hs	LBB24_4
	mov	x9, #0
	mov	w8, #0
	b	LBB24_13
LBB24_3:
	.cfi_def_cfa wsp, 0
	.cfi_same_value w30
	.cfi_same_value w29
	mov	w0, #0
	ret
LBB24_4:
	.cfi_restore_state
	cmp	x1, #16
	b.hs	LBB24_6
	mov	x9, #0
	mov	w8, #0
	b	LBB24_10
LBB24_6:
	and	x9, x1, #0xfffffffffffffff0
	add	x8, x0, #32
	neg	x10, x9
	movi.2d	v0, #0000000000000000
	movi.2d	v1, #0000000000000000
	movi.2d	v2, #0000000000000000
	movi.2d	v3, #0000000000000000
LBB24_7:
	ldp	q4, q5, [x8, #-32]
	ldp	q6, q7, [x8], #64
	add.4s	v0, v4, v0
	add.4s	v1, v5, v1
	add.4s	v2, v6, v2
	add.4s	v3, v7, v3
	adds	x10, x10, #16
	b.ne	LBB24_7
	add.4s	v0, v1, v0
	add.4s	v1, v2, v3
	add.4s	v0, v0, v1
	addv.4s	s0, v0
	fmov	w8, s0
	cmp	x1, x9
	b.eq	LBB24_15
	tst	x1, #0xc
	b.eq	LBB24_13
LBB24_10:
	mov	x10, x9
	and	x9, x1, #0xfffffffffffffffc
	movi.2d	v0, #0000000000000000
	mov.s	v0[0], w8
	add	x8, x0, x10, lsl #2
	sub	x10, x10, x9
LBB24_11:
	ldr	q1, [x8], #16
	add.4s	v0, v1, v0
	adds	x10, x10, #4
	b.ne	LBB24_11
	addv.4s	s0, v0
	fmov	w8, s0
	cmp	x1, x9
	b.eq	LBB24_15
LBB24_13:
	add	x10, x0, x9, lsl #2
	sub	x9, x9, x1
LBB24_14:
	ldr	w11, [x10], #4
	add	w8, w11, w8
	adds	x9, x9, #1
	b.lo	LBB24_14
LBB24_15:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	mov	x0, x8
	ret
	.cfi_endproc

	.globl	_sum
	.p2align	2
_sum:
	.cfi_startproc
	cbz	x1, LBB25_3
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_remember_state
	cmp	x1, #8
	b.hs	LBB25_4
	mov	x8, #0
	movi	d0, #0000000000000000
	b	LBB25_7
LBB25_3:
	.cfi_def_cfa wsp, 0
	.cfi_same_value w30
	.cfi_same_value w29
	movi	d0, #0000000000000000
	ret
LBB25_4:
	.cfi_restore_state
	and	x8, x1, #0xfffffffffffffff8
	add	x9, x0, #32
	neg	x10, x8
	movi	d0, #0000000000000000
LBB25_5:
	ldp	q1, q2, [x9, #-32]
	mov	d3, v1[1]
	mov	d4, v2[1]
	ldp	q5, q6, [x9], #64
	mov	d7, v5[1]
	mov	d16, v6[1]
	fadd	d0, d0, d1
	fadd	d0, d0, d3
	fadd	d0, d0, d2
	fadd	d0, d0, d4
	fadd	d0, d0, d5
	fadd	d0, d0, d7
	fadd	d0, d0, d6
	fadd	d0, d0, d16
	adds	x10, x10, #8
	b.ne	LBB25_5
	cmp	x1, x8
	b.eq	LBB25_9
LBB25_7:
	add	x9, x0, x8, lsl #3
	sub	x8, x8, x1
LBB25_8:
	ldr	d1, [x9], #8
	fadd	d0, d0, d1
	adds	x8, x8, #1
	b.lo	LBB25_8
LBB25_9:
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	ret
	.cfi_endproc

	.globl	_sumOpticalDepthColumn
	.p2align	2
_sumOpticalDepthColumn:
	.cfi_startproc
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset 16
	mov	x29, sp
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_def_cfa wsp, 16
	ldp	x29, x30, [sp], #16
	.cfi_def_cfa_offset 0
	.cfi_restore w30
	.cfi_restore w29
	b	_sum
	.cfi_endproc

.subsections_via_symbols
