0000000100008ca8 <_codegen_dot_gauss_pair>:
100008ca8: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100008cac: 910003fd    	mov	x29, sp
100008cb0: 900000a8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100008cb4: 9118e108    	add	x8, x8, #0x638
100008cb8: fd410d00    	ldr	d0, [x8, #0x218]
100008cbc: d2970a49    	mov	x9, #0xb852             ; =47186
100008cc0: f2b0a3c9    	movk	x9, #0x851e, lsl #16
100008cc4: f2ca3d69    	movk	x9, #0x51eb, lsl #32
100008cc8: f2e7f909    	movk	x9, #0x3fc8, lsl #48
100008ccc: 9e670121    	fmov	d1, x9
100008cd0: 1e610801    	fmul	d1, d0, d1
100008cd4: d2947ae9    	mov	x9, #0xa3d7             ; =41943
100008cd8: f2a7ae09    	movk	x9, #0x3d70, lsl #16
100008cdc: f2dae149    	movk	x9, #0xd70a, lsl #32
100008ce0: f2e7fa69    	movk	x9, #0x3fd3, lsl #48
100008ce4: 9e670122    	fmov	d2, x9
100008ce8: 1e620800    	fmul	d0, d0, d2
100008cec: fd411102    	ldr	d2, [x8, #0x220]
100008cf0: d29df3c9    	mov	x9, #0xef9e             ; =61342
100008cf4: f2b8d4e9    	movk	x9, #0xc6a7, lsl #16
100008cf8: f2c6e969    	movk	x9, #0x374b, lsl #32
100008cfc: f2e7f929    	movk	x9, #0x3fc9, lsl #48
100008d00: 9e670123    	fmov	d3, x9
100008d04: 1e630843    	fmul	d3, d2, d3
100008d08: 1e632821    	fadd	d1, d1, d3
100008d0c: d2845a29    	mov	x9, #0x22d1             ; =8913
100008d10: f2bf3b69    	movk	x9, #0xf9db, lsl #16
100008d14: f2cd4fc9    	movk	x9, #0x6a7e, lsl #32
100008d18: f2e7fa89    	movk	x9, #0x3fd4, lsl #48
100008d1c: 9e670123    	fmov	d3, x9
100008d20: 1e630842    	fmul	d2, d2, d3
100008d24: 1e622800    	fadd	d0, d0, d2
100008d28: fd411502    	ldr	d2, [x8, #0x228]
100008d2c: d284dd49    	mov	x9, #0x26ea             ; =9962
100008d30: f2a10629    	movk	x9, #0x831, lsl #16
100008d34: f2c39589    	movk	x9, #0x1cac, lsl #32
100008d38: f2e7f949    	movk	x9, #0x3fca, lsl #48
100008d3c: 9e670123    	fmov	d3, x9
100008d40: 1e630843    	fmul	d3, d2, d3
100008d44: 1e632821    	fadd	d1, d1, d3
100008d48: d2943969    	mov	x9, #0xa1cb             ; =41419
100008d4c: f2b6c8a9    	movk	x9, #0xb645, lsl #16
100008d50: f2dfbe69    	movk	x9, #0xfdf3, lsl #32
100008d54: f2e7fa89    	movk	x9, #0x3fd4, lsl #48
100008d58: 9e670123    	fmov	d3, x9
100008d5c: 1e630842    	fmul	d2, d2, d3
100008d60: 1e622800    	fadd	d0, d0, d2
100008d64: fd411902    	ldr	d2, [x8, #0x230]
100008d68: d28bc6a9    	mov	x9, #0x5e35             ; =24117
100008d6c: f2a93749    	movk	x9, #0x49ba, lsl #16
100008d70: f2c04189    	movk	x9, #0x20c, lsl #32
100008d74: f2e7f969    	movk	x9, #0x3fcb, lsl #48
100008d78: 9e670123    	fmov	d3, x9
100008d7c: 1e630843    	fmul	d3, d2, d3
100008d80: 1e632821    	fadd	d1, d1, d3
100008d84: d2841889    	mov	x9, #0x20c4             ; =8388
100008d88: f2ae5609    	movk	x9, #0x72b0, lsl #16
100008d8c: f2d22d09    	movk	x9, #0x9168, lsl #32
100008d90: f2e7faa9    	movk	x9, #0x3fd5, lsl #48
100008d94: 9e670123    	fmov	d3, x9
100008d98: 1e630842    	fmul	d2, d2, d3
100008d9c: 1e622800    	fadd	d0, d0, d2
100008da0: fd411d02    	ldr	d2, [x8, #0x238]
100008da4: d292b029    	mov	x9, #0x9581             ; =38273
100008da8: f2b16869    	movk	x9, #0x8b43, lsl #16
100008dac: f2dced89    	movk	x9, #0xe76c, lsl #32
100008db0: f2e7f969    	movk	x9, #0x3fcb, lsl #48
100008db4: 9e670123    	fmov	d3, x9
100008db8: 1e630843    	fmul	d3, d2, d3
100008dbc: 1e632821    	fadd	d1, d1, d3
100008dc0: d293f7c9    	mov	x9, #0x9fbe             ; =40894
100008dc4: f2a5e349    	movk	x9, #0x2f1a, lsl #16
100008dc8: f2c49ba9    	movk	x9, #0x24dd, lsl #32
100008dcc: f2e7fac9    	movk	x9, #0x3fd6, lsl #48
100008dd0: 9e670123    	fmov	d3, x9
100008dd4: 1e630842    	fmul	d2, d2, d3
100008dd8: 1e622800    	fadd	d0, d0, d2
100008ddc: fd412102    	ldr	d2, [x8, #0x240]
100008de0: b202e7e9    	mov	x9, #-0x3333333333333334 ; =-3689348814741910324
100008de4: f29999a9    	movk	x9, #0xcccd
100008de8: f2e7f989    	movk	x9, #0x3fcc, lsl #48
100008dec: 9e670123    	fmov	d3, x9
100008df0: 1e630843    	fmul	d3, d2, d3
100008df4: 1e632821    	fadd	d1, d1, d3
100008df8: d283d709    	mov	x9, #0x1eb8             ; =7864
100008dfc: f2bd70a9    	movk	x9, #0xeb85, lsl #16
100008e00: f2d70a29    	movk	x9, #0xb851, lsl #32
100008e04: f2e7fac9    	movk	x9, #0x3fd6, lsl #48
100008e08: 9e670123    	fmov	d3, x9
100008e0c: 1e630842    	fmul	d2, d2, d3
100008e10: 1e622800    	fadd	d0, d0, d2
100008e14: fd412502    	ldr	d2, [x8, #0x248]
100008e18: d2808329    	mov	x9, #0x419              ; =1049
100008e1c: f2a1cac9    	movk	x9, #0xe56, lsl #16
100008e20: f2d645a9    	movk	x9, #0xb22d, lsl #32
100008e24: f2e7f9a9    	movk	x9, #0x3fcd, lsl #48
100008e28: 9e670123    	fmov	d3, x9
100008e2c: 1e630843    	fmul	d3, d2, d3
100008e30: 1e632821    	fadd	d1, d1, d3
100008e34: d293b649    	mov	x9, #0x9db2             ; =40370
100008e38: f2b4fde9    	movk	x9, #0xa7ef, lsl #16
100008e3c: f2c978c9    	movk	x9, #0x4bc6, lsl #32
100008e40: f2e7fae9    	movk	x9, #0x3fd7, lsl #48
100008e44: 9e670123    	fmov	d3, x9
100008e48: 1e630842    	fmul	d2, d2, d3
100008e4c: 1e622800    	fadd	d0, d0, d2
100008e50: fd412902    	ldr	d2, [x8, #0x250]
100008e54: d2876c89    	mov	x9, #0x3b64             ; =15204
100008e58: f2a9fbe9    	movk	x9, #0x4fdf, lsl #16
100008e5c: f2d2f1a9    	movk	x9, #0x978d, lsl #32
100008e60: f2e7f9c9    	movk	x9, #0x3fce, lsl #48
100008e64: 9e670123    	fmov	d3, x9
100008e68: 1e630843    	fmul	d3, d2, d3
100008e6c: 1e632821    	fadd	d1, d1, d3
100008e70: d2839589    	mov	x9, #0x1cac             ; =7340
100008e74: f2ac8b49    	movk	x9, #0x645a, lsl #16
100008e78: f2dbe769    	movk	x9, #0xdf3b, lsl #32
100008e7c: f2e7fae9    	movk	x9, #0x3fd7, lsl #48
100008e80: 9e670123    	fmov	d3, x9
100008e84: 1e630842    	fmul	d2, d2, d3
100008e88: 1e622800    	fadd	d0, d0, d2
100008e8c: fd412d02    	ldr	d2, [x8, #0x258]
100008e90: d28e5609    	mov	x9, #0x72b0             ; =29360
100008e94: f2b22d09    	movk	x9, #0x9168, lsl #16
100008e98: f2cf9da9    	movk	x9, #0x7ced, lsl #32
100008e9c: f2e7f9e9    	movk	x9, #0x3fcf, lsl #48
100008ea0: 9e670123    	fmov	d3, x9
100008ea4: 1e630843    	fmul	d3, d2, d3
100008ea8: 1e632821    	fadd	d1, d1, d3
100008eac: d29374c9    	mov	x9, #0x9ba6             ; =39846
100008eb0: f2a41889    	movk	x9, #0x20c4, lsl #16
100008eb4: f2ce5609    	movk	x9, #0x72b0, lsl #32
100008eb8: f2e7fb09    	movk	x9, #0x3fd8, lsl #48
100008ebc: 9e670123    	fmov	d3, x9
100008ec0: 1e630842    	fmul	d2, d2, d3
100008ec4: 1e622800    	fadd	d0, d0, d2
100008ec8: fd413102    	ldr	d2, [x8, #0x260]
100008ecc: d29a9fc9    	mov	x9, #0xd4fe             ; =54526
100008ed0: f2bd2f09    	movk	x9, #0xe978, lsl #16
100008ed4: f2c624c9    	movk	x9, #0x3126, lsl #32
100008ed8: f2e7fa09    	movk	x9, #0x3fd0, lsl #48
100008edc: 9e670123    	fmov	d3, x9
100008ee0: 1e630843    	fmul	d3, d2, d3
100008ee4: 1e632821    	fadd	d1, d1, d3
100008ee8: d2835409    	mov	x9, #0x1aa0             ; =6816
100008eec: f2bba5e9    	movk	x9, #0xdd2f, lsl #16
100008ef0: f2c0c489    	movk	x9, #0x624, lsl #32
100008ef4: f2e7fb29    	movk	x9, #0x3fd9, lsl #48
100008ef8: 9e670123    	fmov	d3, x9
100008efc: 1e630842    	fmul	d2, d2, d3
100008f00: 1e622800    	fadd	d0, d0, d2
100008f04: 6d000101    	stp	d1, d0, [x8]
100008f08: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100008f0c: d65f03c0    	ret
