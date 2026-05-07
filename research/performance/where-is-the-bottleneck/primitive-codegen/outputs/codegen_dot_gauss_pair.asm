000000010000b184 <_codegen_dot_gauss_pair>:
10000b184: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
10000b188: 910003fd    	mov	x29, sp
10000b18c: b0000088    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000b190: 91184108    	add	x8, x8, #0x610
10000b194: fd410900    	ldr	d0, [x8, #0x210]
10000b198: d2970a49    	mov	x9, #0xb852             ; =47186
10000b19c: f2b0a3c9    	movk	x9, #0x851e, lsl #16
10000b1a0: f2ca3d69    	movk	x9, #0x51eb, lsl #32
10000b1a4: f2e7f909    	movk	x9, #0x3fc8, lsl #48
10000b1a8: 9e670121    	fmov	d1, x9
10000b1ac: 1e610801    	fmul	d1, d0, d1
10000b1b0: d2947ae9    	mov	x9, #0xa3d7             ; =41943
10000b1b4: f2a7ae09    	movk	x9, #0x3d70, lsl #16
10000b1b8: f2dae149    	movk	x9, #0xd70a, lsl #32
10000b1bc: f2e7fa69    	movk	x9, #0x3fd3, lsl #48
10000b1c0: 9e670122    	fmov	d2, x9
10000b1c4: 1e620800    	fmul	d0, d0, d2
10000b1c8: fd410d02    	ldr	d2, [x8, #0x218]
10000b1cc: d29df3c9    	mov	x9, #0xef9e             ; =61342
10000b1d0: f2b8d4e9    	movk	x9, #0xc6a7, lsl #16
10000b1d4: f2c6e969    	movk	x9, #0x374b, lsl #32
10000b1d8: f2e7f929    	movk	x9, #0x3fc9, lsl #48
10000b1dc: 9e670123    	fmov	d3, x9
10000b1e0: 1e630843    	fmul	d3, d2, d3
10000b1e4: 1e632821    	fadd	d1, d1, d3
10000b1e8: d2845a29    	mov	x9, #0x22d1             ; =8913
10000b1ec: f2bf3b69    	movk	x9, #0xf9db, lsl #16
10000b1f0: f2cd4fc9    	movk	x9, #0x6a7e, lsl #32
10000b1f4: f2e7fa89    	movk	x9, #0x3fd4, lsl #48
10000b1f8: 9e670123    	fmov	d3, x9
10000b1fc: 1e630842    	fmul	d2, d2, d3
10000b200: 1e622800    	fadd	d0, d0, d2
10000b204: fd411102    	ldr	d2, [x8, #0x220]
10000b208: d284dd49    	mov	x9, #0x26ea             ; =9962
10000b20c: f2a10629    	movk	x9, #0x831, lsl #16
10000b210: f2c39589    	movk	x9, #0x1cac, lsl #32
10000b214: f2e7f949    	movk	x9, #0x3fca, lsl #48
10000b218: 9e670123    	fmov	d3, x9
10000b21c: 1e630843    	fmul	d3, d2, d3
10000b220: 1e632821    	fadd	d1, d1, d3
10000b224: d2943969    	mov	x9, #0xa1cb             ; =41419
10000b228: f2b6c8a9    	movk	x9, #0xb645, lsl #16
10000b22c: f2dfbe69    	movk	x9, #0xfdf3, lsl #32
10000b230: f2e7fa89    	movk	x9, #0x3fd4, lsl #48
10000b234: 9e670123    	fmov	d3, x9
10000b238: 1e630842    	fmul	d2, d2, d3
10000b23c: 1e622800    	fadd	d0, d0, d2
10000b240: fd411502    	ldr	d2, [x8, #0x228]
10000b244: d28bc6a9    	mov	x9, #0x5e35             ; =24117
10000b248: f2a93749    	movk	x9, #0x49ba, lsl #16
10000b24c: f2c04189    	movk	x9, #0x20c, lsl #32
10000b250: f2e7f969    	movk	x9, #0x3fcb, lsl #48
10000b254: 9e670123    	fmov	d3, x9
10000b258: 1e630843    	fmul	d3, d2, d3
10000b25c: 1e632821    	fadd	d1, d1, d3
10000b260: d2841889    	mov	x9, #0x20c4             ; =8388
10000b264: f2ae5609    	movk	x9, #0x72b0, lsl #16
10000b268: f2d22d09    	movk	x9, #0x9168, lsl #32
10000b26c: f2e7faa9    	movk	x9, #0x3fd5, lsl #48
10000b270: 9e670123    	fmov	d3, x9
10000b274: 1e630842    	fmul	d2, d2, d3
10000b278: 1e622800    	fadd	d0, d0, d2
10000b27c: fd411902    	ldr	d2, [x8, #0x230]
10000b280: d292b029    	mov	x9, #0x9581             ; =38273
10000b284: f2b16869    	movk	x9, #0x8b43, lsl #16
10000b288: f2dced89    	movk	x9, #0xe76c, lsl #32
10000b28c: f2e7f969    	movk	x9, #0x3fcb, lsl #48
10000b290: 9e670123    	fmov	d3, x9
10000b294: 1e630843    	fmul	d3, d2, d3
10000b298: 1e632821    	fadd	d1, d1, d3
10000b29c: d293f7c9    	mov	x9, #0x9fbe             ; =40894
10000b2a0: f2a5e349    	movk	x9, #0x2f1a, lsl #16
10000b2a4: f2c49ba9    	movk	x9, #0x24dd, lsl #32
10000b2a8: f2e7fac9    	movk	x9, #0x3fd6, lsl #48
10000b2ac: 9e670123    	fmov	d3, x9
10000b2b0: 1e630842    	fmul	d2, d2, d3
10000b2b4: 1e622800    	fadd	d0, d0, d2
10000b2b8: fd411d02    	ldr	d2, [x8, #0x238]
10000b2bc: b202e7e9    	mov	x9, #-0x3333333333333334 ; =-3689348814741910324
10000b2c0: f29999a9    	movk	x9, #0xcccd
10000b2c4: f2e7f989    	movk	x9, #0x3fcc, lsl #48
10000b2c8: 9e670123    	fmov	d3, x9
10000b2cc: 1e630843    	fmul	d3, d2, d3
10000b2d0: 1e632821    	fadd	d1, d1, d3
10000b2d4: d283d709    	mov	x9, #0x1eb8             ; =7864
10000b2d8: f2bd70a9    	movk	x9, #0xeb85, lsl #16
10000b2dc: f2d70a29    	movk	x9, #0xb851, lsl #32
10000b2e0: f2e7fac9    	movk	x9, #0x3fd6, lsl #48
10000b2e4: 9e670123    	fmov	d3, x9
10000b2e8: 1e630842    	fmul	d2, d2, d3
10000b2ec: 1e622800    	fadd	d0, d0, d2
10000b2f0: fd412102    	ldr	d2, [x8, #0x240]
10000b2f4: d2808329    	mov	x9, #0x419              ; =1049
10000b2f8: f2a1cac9    	movk	x9, #0xe56, lsl #16
10000b2fc: f2d645a9    	movk	x9, #0xb22d, lsl #32
10000b300: f2e7f9a9    	movk	x9, #0x3fcd, lsl #48
10000b304: 9e670123    	fmov	d3, x9
10000b308: 1e630843    	fmul	d3, d2, d3
10000b30c: 1e632821    	fadd	d1, d1, d3
10000b310: d293b649    	mov	x9, #0x9db2             ; =40370
10000b314: f2b4fde9    	movk	x9, #0xa7ef, lsl #16
10000b318: f2c978c9    	movk	x9, #0x4bc6, lsl #32
10000b31c: f2e7fae9    	movk	x9, #0x3fd7, lsl #48
10000b320: 9e670123    	fmov	d3, x9
10000b324: 1e630842    	fmul	d2, d2, d3
10000b328: 1e622800    	fadd	d0, d0, d2
10000b32c: fd412502    	ldr	d2, [x8, #0x248]
10000b330: d2876c89    	mov	x9, #0x3b64             ; =15204
10000b334: f2a9fbe9    	movk	x9, #0x4fdf, lsl #16
10000b338: f2d2f1a9    	movk	x9, #0x978d, lsl #32
10000b33c: f2e7f9c9    	movk	x9, #0x3fce, lsl #48
10000b340: 9e670123    	fmov	d3, x9
10000b344: 1e630843    	fmul	d3, d2, d3
10000b348: 1e632821    	fadd	d1, d1, d3
10000b34c: d2839589    	mov	x9, #0x1cac             ; =7340
10000b350: f2ac8b49    	movk	x9, #0x645a, lsl #16
10000b354: f2dbe769    	movk	x9, #0xdf3b, lsl #32
10000b358: f2e7fae9    	movk	x9, #0x3fd7, lsl #48
10000b35c: 9e670123    	fmov	d3, x9
10000b360: 1e630842    	fmul	d2, d2, d3
10000b364: 1e622800    	fadd	d0, d0, d2
10000b368: fd412902    	ldr	d2, [x8, #0x250]
10000b36c: d28e5609    	mov	x9, #0x72b0             ; =29360
10000b370: f2b22d09    	movk	x9, #0x9168, lsl #16
10000b374: f2cf9da9    	movk	x9, #0x7ced, lsl #32
10000b378: f2e7f9e9    	movk	x9, #0x3fcf, lsl #48
10000b37c: 9e670123    	fmov	d3, x9
10000b380: 1e630843    	fmul	d3, d2, d3
10000b384: 1e632821    	fadd	d1, d1, d3
10000b388: d29374c9    	mov	x9, #0x9ba6             ; =39846
10000b38c: f2a41889    	movk	x9, #0x20c4, lsl #16
10000b390: f2ce5609    	movk	x9, #0x72b0, lsl #32
10000b394: f2e7fb09    	movk	x9, #0x3fd8, lsl #48
10000b398: 9e670123    	fmov	d3, x9
10000b39c: 1e630842    	fmul	d2, d2, d3
10000b3a0: 1e622800    	fadd	d0, d0, d2
10000b3a4: fd412d02    	ldr	d2, [x8, #0x258]
10000b3a8: d29a9fc9    	mov	x9, #0xd4fe             ; =54526
10000b3ac: f2bd2f09    	movk	x9, #0xe978, lsl #16
10000b3b0: f2c624c9    	movk	x9, #0x3126, lsl #32
10000b3b4: f2e7fa09    	movk	x9, #0x3fd0, lsl #48
10000b3b8: 9e670123    	fmov	d3, x9
10000b3bc: 1e630843    	fmul	d3, d2, d3
10000b3c0: 1e632821    	fadd	d1, d1, d3
10000b3c4: d2835409    	mov	x9, #0x1aa0             ; =6816
10000b3c8: f2bba5e9    	movk	x9, #0xdd2f, lsl #16
10000b3cc: f2c0c489    	movk	x9, #0x624, lsl #32
10000b3d0: f2e7fb29    	movk	x9, #0x3fd9, lsl #48
10000b3d4: 9e670123    	fmov	d3, x9
10000b3d8: 1e630842    	fmul	d2, d2, d3
10000b3dc: 1e622800    	fadd	d0, d0, d2
10000b3e0: 6d000101    	stp	d1, d0, [x8]
10000b3e4: a8c17bfd    	ldp	x29, x30, [sp], #0x10
10000b3e8: d65f03c0    	ret
