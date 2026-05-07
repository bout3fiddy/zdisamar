00000001000070c8 <_codegen_qseries_nonzero_12x10>:
1000070c8: 6db63bef    	stp	d15, d14, [sp, #-0xa0]!
1000070cc: 6d0133ed    	stp	d13, d12, [sp, #0x10]
1000070d0: 6d022beb    	stp	d11, d10, [sp, #0x20]
1000070d4: 6d0323e9    	stp	d9, d8, [sp, #0x30]
1000070d8: a9046ffc    	stp	x28, x27, [sp, #0x40]
1000070dc: a90567fa    	stp	x26, x25, [sp, #0x50]
1000070e0: a9065ff8    	stp	x24, x23, [sp, #0x60]
1000070e4: a90757f6    	stp	x22, x21, [sp, #0x70]
1000070e8: a9084ff4    	stp	x20, x19, [sp, #0x80]
1000070ec: a9097bfd    	stp	x29, x30, [sp, #0x90]
1000070f0: 910243fd    	add	x29, sp, #0x90
1000070f4: d14007ff    	sub	sp, sp, #0x1, lsl #12   ; =0x1000
1000070f8: d10d83ff    	sub	sp, sp, #0x360
1000070fc: b00000a8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100007100: 91190108    	add	x8, x8, #0x640
100007104: 3dc00112    	ldr	q18, [x8]
100007108: 3dc12103    	ldr	q3, [x8, #0x480]
10000710c: 4fd29061    	fmul.2d	v1, v3, v18[0]
100007110: 3cc0811e    	ldur	q30, [x8, #0x8]
100007114: 3dc13900    	ldr	q0, [x8, #0x4e0]
100007118: 4fde9002    	fmul.2d	v2, v0, v30[0]
10000711c: 4e62d421    	fadd.2d	v1, v1, v2
100007120: 3dc00502    	ldr	q2, [x8, #0x10]
100007124: 3d821fe2    	str	q2, [sp, #0x870]
100007128: 3dc15114    	ldr	q20, [x8, #0x540]
10000712c: 4fc29282    	fmul.2d	v2, v20, v2[0]
100007130: 3d82b3f4    	str	q20, [sp, #0xac0]
100007134: 4e62d421    	fadd.2d	v1, v1, v2
100007138: 3cc18102    	ldur	q2, [x8, #0x18]
10000713c: 3d81cfe2    	str	q2, [sp, #0x730]
100007140: 3dc16915    	ldr	q21, [x8, #0x5a0]
100007144: 4fc292a2    	fmul.2d	v2, v21, v2[0]
100007148: 3d831ff5    	str	q21, [sp, #0xc70]
10000714c: 4e62d421    	fadd.2d	v1, v1, v2
100007150: 3dc00902    	ldr	q2, [x8, #0x20]
100007154: 3d817be2    	str	q2, [sp, #0x5e0]
100007158: 3dc18105    	ldr	q5, [x8, #0x600]
10000715c: 4fc290a2    	fmul.2d	v2, v5, v2[0]
100007160: 3d82ffe5    	str	q5, [sp, #0xbf0]
100007164: 4e62d421    	fadd.2d	v1, v1, v2
100007168: 3cc28102    	ldur	q2, [x8, #0x28]
10000716c: 3d8233e2    	str	q2, [sp, #0x8c0]
100007170: 3dc19906    	ldr	q6, [x8, #0x660]
100007174: 4fc290c2    	fmul.2d	v2, v6, v2[0]
100007178: 3d831be6    	str	q6, [sp, #0xc60]
10000717c: 4e62d421    	fadd.2d	v1, v1, v2
100007180: 3dc00d02    	ldr	q2, [x8, #0x30]
100007184: 3d822fe2    	str	q2, [sp, #0x8b0]
100007188: 3dc1b107    	ldr	q7, [x8, #0x6c0]
10000718c: 4fc290e2    	fmul.2d	v2, v7, v2[0]
100007190: 3d8317e7    	str	q7, [sp, #0xc50]
100007194: 4e62d421    	fadd.2d	v1, v1, v2
100007198: 3cc38102    	ldur	q2, [x8, #0x38]
10000719c: 3d822be2    	str	q2, [sp, #0x8a0]
1000071a0: 3dc1c910    	ldr	q16, [x8, #0x720]
1000071a4: 4fc29202    	fmul.2d	v2, v16, v2[0]
1000071a8: 3d82fbf0    	str	q16, [sp, #0xbe0]
1000071ac: 4e62d421    	fadd.2d	v1, v1, v2
1000071b0: 3dc01102    	ldr	q2, [x8, #0x40]
1000071b4: 3d8227e2    	str	q2, [sp, #0x890]
1000071b8: 3dc1e111    	ldr	q17, [x8, #0x780]
1000071bc: 4fc29222    	fmul.2d	v2, v17, v2[0]
1000071c0: 3d82f7f1    	str	q17, [sp, #0xbd0]
1000071c4: 4e62d421    	fadd.2d	v1, v1, v2
1000071c8: 3cc48102    	ldur	q2, [x8, #0x48]
1000071cc: 3d8223e2    	str	q2, [sp, #0x880]
1000071d0: 3dc1f904    	ldr	q4, [x8, #0x7e0]
1000071d4: 4fc29082    	fmul.2d	v2, v4, v2[0]
1000071d8: 3d82f3e4    	str	q4, [sp, #0xbc0]
1000071dc: 4e080400    	dup.2d	v0, v0[0]
1000071e0: 4e62d421    	fadd.2d	v1, v1, v2
1000071e4: 3d8257e1    	str	q1, [sp, #0x950]
1000071e8: 91122109    	add	x9, x8, #0x488
1000071ec: 0d408520    	ld1.d	{ v0 }[0], [x9]
1000071f0: 3d8307e0    	str	q0, [sp, #0xc10]
1000071f4: 3dc01901    	ldr	q1, [x8, #0x60]
1000071f8: 3d821be1    	str	q1, [sp, #0x860]
1000071fc: 6e61dc00    	fmul.2d	v0, v0, v1
100007200: 6e004000    	ext.16b	v0, v0, v0, #0x8
100007204: 9113a109    	add	x9, x8, #0x4e8
100007208: 4d408523    	ld1.d	{ v3 }[1], [x9]
10000720c: 3d8303e3    	str	q3, [sp, #0xc00]
100007210: 6e61dc61    	fmul.2d	v1, v3, v1
100007214: 4e61d400    	fadd.2d	v0, v0, v1
100007218: 3dc01d01    	ldr	q1, [x8, #0x70]
10000721c: 3d8217e1    	str	q1, [sp, #0x850]
100007220: 4fc19281    	fmul.2d	v1, v20, v1[0]
100007224: 4e61d400    	fadd.2d	v0, v0, v1
100007228: 3cc78101    	ldur	q1, [x8, #0x78]
10000722c: 3d8213e1    	str	q1, [sp, #0x840]
100007230: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100007234: 4e61d400    	fadd.2d	v0, v0, v1
100007238: 3dc02101    	ldr	q1, [x8, #0x80]
10000723c: 3d820fe1    	str	q1, [sp, #0x830]
100007240: 4fc190a1    	fmul.2d	v1, v5, v1[0]
100007244: 4e61d400    	fadd.2d	v0, v0, v1
100007248: 3cc88101    	ldur	q1, [x8, #0x88]
10000724c: 3d820be1    	str	q1, [sp, #0x820]
100007250: 4fc190c1    	fmul.2d	v1, v6, v1[0]
100007254: 4e61d400    	fadd.2d	v0, v0, v1
100007258: 3dc02501    	ldr	q1, [x8, #0x90]
10000725c: 3d8207e1    	str	q1, [sp, #0x810]
100007260: 4fc190e1    	fmul.2d	v1, v7, v1[0]
100007264: 4e61d400    	fadd.2d	v0, v0, v1
100007268: 3cc98101    	ldur	q1, [x8, #0x98]
10000726c: 3d8203e1    	str	q1, [sp, #0x800]
100007270: 4fc19201    	fmul.2d	v1, v16, v1[0]
100007274: 4e61d400    	fadd.2d	v0, v0, v1
100007278: 3dc02901    	ldr	q1, [x8, #0xa0]
10000727c: 3d81ffe1    	str	q1, [sp, #0x7f0]
100007280: 4fc19221    	fmul.2d	v1, v17, v1[0]
100007284: 4e61d400    	fadd.2d	v0, v0, v1
100007288: 3cca8101    	ldur	q1, [x8, #0xa8]
10000728c: 3d81fbe1    	str	q1, [sp, #0x7e0]
100007290: 4fc19081    	fmul.2d	v1, v4, v1[0]
100007294: 4e61d41d    	fadd.2d	v29, v0, v1
100007298: 91126109    	add	x9, x8, #0x498
10000729c: 3dc12500    	ldr	q0, [x8, #0x490]
1000072a0: 4fd29001    	fmul.2d	v1, v0, v18[0]
1000072a4: 3d824fe1    	str	q1, [sp, #0x930]
1000072a8: 4d408520    	ld1.d	{ v0 }[1], [x9]
1000072ac: 4ea01c01    	mov.16b	v1, v0
1000072b0: 9113e109    	add	x9, x8, #0x4f8
1000072b4: 3dc13d00    	ldr	q0, [x8, #0x4f0]
1000072b8: 4fde9002    	fmul.2d	v2, v0, v30[0]
1000072bc: 3d824be2    	str	q2, [sp, #0x920]
1000072c0: 4d408520    	ld1.d	{ v0 }[1], [x9]
1000072c4: 4ea01c03    	mov.16b	v3, v0
1000072c8: 3dc03100    	ldr	q0, [x8, #0xc0]
1000072cc: 3d81f3e0    	str	q0, [sp, #0x7c0]
1000072d0: 4fc09020    	fmul.2d	v0, v1, v0[0]
1000072d4: 4ea11c27    	mov.16b	v7, v1
1000072d8: 3d82efe1    	str	q1, [sp, #0xbb0]
1000072dc: 3ccc8101    	ldur	q1, [x8, #0xc8]
1000072e0: 3d81f7e1    	str	q1, [sp, #0x7d0]
1000072e4: 4fc19061    	fmul.2d	v1, v3, v1[0]
1000072e8: 3d82ebe3    	str	q3, [sp, #0xba0]
1000072ec: 4e61d400    	fadd.2d	v0, v0, v1
1000072f0: 3dc15519    	ldr	q25, [x8, #0x550]
1000072f4: 3dc03501    	ldr	q1, [x8, #0xd0]
1000072f8: 3d81efe1    	str	q1, [sp, #0x7b0]
1000072fc: 4fc19321    	fmul.2d	v1, v25, v1[0]
100007300: 4e61d400    	fadd.2d	v0, v0, v1
100007304: 3dc16d1b    	ldr	q27, [x8, #0x5b0]
100007308: 3ccd8101    	ldur	q1, [x8, #0xd8]
10000730c: 3d81ebe1    	str	q1, [sp, #0x7a0]
100007310: 4fc19361    	fmul.2d	v1, v27, v1[0]
100007314: 4e61d400    	fadd.2d	v0, v0, v1
100007318: 3dc1851a    	ldr	q26, [x8, #0x610]
10000731c: 3dc03901    	ldr	q1, [x8, #0xe0]
100007320: 3d81e7e1    	str	q1, [sp, #0x790]
100007324: 4fc19341    	fmul.2d	v1, v26, v1[0]
100007328: 4e61d400    	fadd.2d	v0, v0, v1
10000732c: 3dc19d11    	ldr	q17, [x8, #0x670]
100007330: 3cce8101    	ldur	q1, [x8, #0xe8]
100007334: 3d81e3e1    	str	q1, [sp, #0x780]
100007338: 4fc19221    	fmul.2d	v1, v17, v1[0]
10000733c: 3d82e7f1    	str	q17, [sp, #0xb90]
100007340: 4e61d400    	fadd.2d	v0, v0, v1
100007344: 3dc1b51c    	ldr	q28, [x8, #0x6d0]
100007348: 3dc03d01    	ldr	q1, [x8, #0xf0]
10000734c: 3d81dfe1    	str	q1, [sp, #0x770]
100007350: 4fc19381    	fmul.2d	v1, v28, v1[0]
100007354: 4e61d400    	fadd.2d	v0, v0, v1
100007358: 3dc1cd1f    	ldr	q31, [x8, #0x730]
10000735c: 3ccf8101    	ldur	q1, [x8, #0xf8]
100007360: 3d81dbe1    	str	q1, [sp, #0x760]
100007364: 4fc193e1    	fmul.2d	v1, v31, v1[0]
100007368: 4e61d400    	fadd.2d	v0, v0, v1
10000736c: 3dc1e50e    	ldr	q14, [x8, #0x790]
100007370: 3dc04101    	ldr	q1, [x8, #0x100]
100007374: 3d81d7e1    	str	q1, [sp, #0x750]
100007378: 4fc191c1    	fmul.2d	v1, v14, v1[0]
10000737c: 4e61d400    	fadd.2d	v0, v0, v1
100007380: 91042109    	add	x9, x8, #0x108
100007384: 3dc1fd0f    	ldr	q15, [x8, #0x7f0]
100007388: 3dc00121    	ldr	q1, [x9]
10000738c: 3d81d3e1    	str	q1, [sp, #0x740]
100007390: 4fc191e1    	fmul.2d	v1, v15, v1[0]
100007394: 4e61d409    	fadd.2d	v9, v0, v1
100007398: 9104a109    	add	x9, x8, #0x128
10000739c: 3dc04900    	ldr	q0, [x8, #0x120]
1000073a0: 3d81c7e0    	str	q0, [sp, #0x710]
1000073a4: 4fc090e0    	fmul.2d	v0, v7, v0[0]
1000073a8: 3dc00121    	ldr	q1, [x9]
1000073ac: 3d81cbe1    	str	q1, [sp, #0x720]
1000073b0: 4fc19061    	fmul.2d	v1, v3, v1[0]
1000073b4: 4e61d400    	fadd.2d	v0, v0, v1
1000073b8: 3dc04d01    	ldr	q1, [x8, #0x130]
1000073bc: 3d81c3e1    	str	q1, [sp, #0x700]
1000073c0: 4fc19321    	fmul.2d	v1, v25, v1[0]
1000073c4: 4e61d400    	fadd.2d	v0, v0, v1
1000073c8: 9104e109    	add	x9, x8, #0x138
1000073cc: 3dc00121    	ldr	q1, [x9]
1000073d0: 3d81bfe1    	str	q1, [sp, #0x6f0]
1000073d4: 4fc19361    	fmul.2d	v1, v27, v1[0]
1000073d8: 4e61d400    	fadd.2d	v0, v0, v1
1000073dc: ad4a0901    	ldp	q1, q2, [x8, #0x140]
1000073e0: 3d81bbe1    	str	q1, [sp, #0x6e0]
1000073e4: 3d81b7e2    	str	q2, [sp, #0x6d0]
1000073e8: 4fc19341    	fmul.2d	v1, v26, v1[0]
1000073ec: 4e61d400    	fadd.2d	v0, v0, v1
1000073f0: 91052109    	add	x9, x8, #0x148
1000073f4: 3dc00121    	ldr	q1, [x9]
1000073f8: 3d81b3e1    	str	q1, [sp, #0x6c0]
1000073fc: 4fc19221    	fmul.2d	v1, v17, v1[0]
100007400: 4e61d400    	fadd.2d	v0, v0, v1
100007404: 4fc29381    	fmul.2d	v1, v28, v2[0]
100007408: 4e61d400    	fadd.2d	v0, v0, v1
10000740c: 91056109    	add	x9, x8, #0x158
100007410: 3dc00121    	ldr	q1, [x9]
100007414: 3d81afe1    	str	q1, [sp, #0x6b0]
100007418: 4fc193e1    	fmul.2d	v1, v31, v1[0]
10000741c: 4e61d400    	fadd.2d	v0, v0, v1
100007420: 3dc05901    	ldr	q1, [x8, #0x160]
100007424: 3d81abe1    	str	q1, [sp, #0x6a0]
100007428: 4fc191c1    	fmul.2d	v1, v14, v1[0]
10000742c: 4e61d400    	fadd.2d	v0, v0, v1
100007430: 9105a109    	add	x9, x8, #0x168
100007434: 3dc00121    	ldr	q1, [x9]
100007438: 3d81a7e1    	str	q1, [sp, #0x690]
10000743c: 4fc191e1    	fmul.2d	v1, v15, v1[0]
100007440: 4e61d408    	fadd.2d	v8, v0, v1
100007444: 9112a109    	add	x9, x8, #0x4a8
100007448: 3dc12900    	ldr	q0, [x8, #0x4a0]
10000744c: 4eb21e4c    	mov.16b	v12, v18
100007450: 4fd29001    	fmul.2d	v1, v0, v18[0]
100007454: 3d8247e1    	str	q1, [sp, #0x910]
100007458: 4d408520    	ld1.d	{ v0 }[1], [x9]
10000745c: 4ea01c02    	mov.16b	v2, v0
100007460: 91142109    	add	x9, x8, #0x508
100007464: 3dc14100    	ldr	q0, [x8, #0x500]
100007468: 4ebe1fcd    	mov.16b	v13, v30
10000746c: 4fde9001    	fmul.2d	v1, v0, v30[0]
100007470: 3d8243e1    	str	q1, [sp, #0x900]
100007474: 4d408520    	ld1.d	{ v0 }[1], [x9]
100007478: 4ea01c04    	mov.16b	v4, v0
10000747c: 91062109    	add	x9, x8, #0x188
100007480: 3dc06100    	ldr	q0, [x8, #0x180]
100007484: 3d819fe0    	str	q0, [sp, #0x670]
100007488: 4fc09040    	fmul.2d	v0, v2, v0[0]
10000748c: 4ea21c43    	mov.16b	v3, v2
100007490: 3d82afe2    	str	q2, [sp, #0xab0]
100007494: 3dc00121    	ldr	q1, [x9]
100007498: 3d81a3e1    	str	q1, [sp, #0x680]
10000749c: 4fc19081    	fmul.2d	v1, v4, v1[0]
1000074a0: 4ea41c92    	mov.16b	v18, v4
1000074a4: 3d82abe4    	str	q4, [sp, #0xaa0]
1000074a8: 4e61d400    	fadd.2d	v0, v0, v1
1000074ac: 3dc06501    	ldr	q1, [x8, #0x190]
1000074b0: 3d819be1    	str	q1, [sp, #0x660]
1000074b4: 3dc15907    	ldr	q7, [x8, #0x560]
1000074b8: 4fc190e1    	fmul.2d	v1, v7, v1[0]
1000074bc: 3d8313e7    	str	q7, [sp, #0xc40]
1000074c0: 4e61d400    	fadd.2d	v0, v0, v1
1000074c4: 91066109    	add	x9, x8, #0x198
1000074c8: 3dc17111    	ldr	q17, [x8, #0x5c0]
1000074cc: 3dc00121    	ldr	q1, [x9]
1000074d0: 3d8197e1    	str	q1, [sp, #0x650]
1000074d4: 4fc19221    	fmul.2d	v1, v17, v1[0]
1000074d8: 3d82dbf1    	str	q17, [sp, #0xb60]
1000074dc: 4e61d400    	fadd.2d	v0, v0, v1
1000074e0: 3dc18904    	ldr	q4, [x8, #0x620]
1000074e4: ad4d0901    	ldp	q1, q2, [x8, #0x1a0]
1000074e8: 3d8193e1    	str	q1, [sp, #0x640]
1000074ec: 3d818be2    	str	q2, [sp, #0x620]
1000074f0: 4fc19081    	fmul.2d	v1, v4, v1[0]
1000074f4: 3d82e3e4    	str	q4, [sp, #0xb80]
1000074f8: 4e61d400    	fadd.2d	v0, v0, v1
1000074fc: 9106a109    	add	x9, x8, #0x1a8
100007500: 3dc1a106    	ldr	q6, [x8, #0x680]
100007504: 3dc00121    	ldr	q1, [x9]
100007508: 3d818fe1    	str	q1, [sp, #0x630]
10000750c: 4fc190c1    	fmul.2d	v1, v6, v1[0]
100007510: 3d830fe6    	str	q6, [sp, #0xc30]
100007514: 4e61d400    	fadd.2d	v0, v0, v1
100007518: 3dc1b910    	ldr	q16, [x8, #0x6e0]
10000751c: 4fc29201    	fmul.2d	v1, v16, v2[0]
100007520: 3d830bf0    	str	q16, [sp, #0xc20]
100007524: 4e61d400    	fadd.2d	v0, v0, v1
100007528: 9106e109    	add	x9, x8, #0x1b8
10000752c: 3dc1d113    	ldr	q19, [x8, #0x740]
100007530: 3dc00121    	ldr	q1, [x9]
100007534: 3d8187e1    	str	q1, [sp, #0x610]
100007538: 4fc19261    	fmul.2d	v1, v19, v1[0]
10000753c: 3d82a3f3    	str	q19, [sp, #0xa80]
100007540: 4e61d400    	fadd.2d	v0, v0, v1
100007544: 3dc1e914    	ldr	q20, [x8, #0x7a0]
100007548: 3dc07101    	ldr	q1, [x8, #0x1c0]
10000754c: 3d8183e1    	str	q1, [sp, #0x600]
100007550: 4fc19281    	fmul.2d	v1, v20, v1[0]
100007554: 3d8277f4    	str	q20, [sp, #0x9d0]
100007558: 4e61d400    	fadd.2d	v0, v0, v1
10000755c: 91072109    	add	x9, x8, #0x1c8
100007560: 3dc20116    	ldr	q22, [x8, #0x800]
100007564: 3dc00121    	ldr	q1, [x9]
100007568: 3d817fe1    	str	q1, [sp, #0x5f0]
10000756c: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100007570: 4e61d41e    	fadd.2d	v30, v0, v1
100007574: 9107a109    	add	x9, x8, #0x1e8
100007578: 3dc07900    	ldr	q0, [x8, #0x1e0]
10000757c: 3d8173e0    	str	q0, [sp, #0x5c0]
100007580: 4fc09060    	fmul.2d	v0, v3, v0[0]
100007584: 3dc00121    	ldr	q1, [x9]
100007588: 3d8177e1    	str	q1, [sp, #0x5d0]
10000758c: 4fc19241    	fmul.2d	v1, v18, v1[0]
100007590: 4e61d400    	fadd.2d	v0, v0, v1
100007594: 3dc07d01    	ldr	q1, [x8, #0x1f0]
100007598: 3d816fe1    	str	q1, [sp, #0x5b0]
10000759c: 4fc190e1    	fmul.2d	v1, v7, v1[0]
1000075a0: 4e61d400    	fadd.2d	v0, v0, v1
1000075a4: 9107e109    	add	x9, x8, #0x1f8
1000075a8: 3dc00121    	ldr	q1, [x9]
1000075ac: 3d816be1    	str	q1, [sp, #0x5a0]
1000075b0: 4fc19221    	fmul.2d	v1, v17, v1[0]
1000075b4: 4e61d400    	fadd.2d	v0, v0, v1
1000075b8: ad500901    	ldp	q1, q2, [x8, #0x200]
1000075bc: 3d8167e1    	str	q1, [sp, #0x590]
1000075c0: 3d815fe2    	str	q2, [sp, #0x570]
1000075c4: 4fc19081    	fmul.2d	v1, v4, v1[0]
1000075c8: 4e61d400    	fadd.2d	v0, v0, v1
1000075cc: 91082109    	add	x9, x8, #0x208
1000075d0: 3dc00121    	ldr	q1, [x9]
1000075d4: 3d8163e1    	str	q1, [sp, #0x580]
1000075d8: 4fc190c1    	fmul.2d	v1, v6, v1[0]
1000075dc: 4e61d400    	fadd.2d	v0, v0, v1
1000075e0: 4fc29201    	fmul.2d	v1, v16, v2[0]
1000075e4: 4e61d400    	fadd.2d	v0, v0, v1
1000075e8: 91086109    	add	x9, x8, #0x218
1000075ec: 3dc00121    	ldr	q1, [x9]
1000075f0: 3d815be1    	str	q1, [sp, #0x560]
1000075f4: 4fc19261    	fmul.2d	v1, v19, v1[0]
1000075f8: 4e61d400    	fadd.2d	v0, v0, v1
1000075fc: 3dc08901    	ldr	q1, [x8, #0x220]
100007600: 3d8157e1    	str	q1, [sp, #0x550]
100007604: 4fc19281    	fmul.2d	v1, v20, v1[0]
100007608: 4e61d400    	fadd.2d	v0, v0, v1
10000760c: 9108a109    	add	x9, x8, #0x228
100007610: 3dc00121    	ldr	q1, [x9]
100007614: 3d8153e1    	str	q1, [sp, #0x540]
100007618: 4fc192c1    	fmul.2d	v1, v22, v1[0]
10000761c: 4e61d413    	fadd.2d	v19, v0, v1
100007620: 9112e109    	add	x9, x8, #0x4b8
100007624: 3dc12d00    	ldr	q0, [x8, #0x4b0]
100007628: 4fcc9001    	fmul.2d	v1, v0, v12[0]
10000762c: 3d823fe1    	str	q1, [sp, #0x8f0]
100007630: ad0833ed    	stp	q13, q12, [sp, #0x100]
100007634: 4d408520    	ld1.d	{ v0 }[1], [x9]
100007638: 4ea01c03    	mov.16b	v3, v0
10000763c: 91146109    	add	x9, x8, #0x518
100007640: 3dc14500    	ldr	q0, [x8, #0x510]
100007644: 4fcd9001    	fmul.2d	v1, v0, v13[0]
100007648: 3d823be1    	str	q1, [sp, #0x8e0]
10000764c: 4d408520    	ld1.d	{ v0 }[1], [x9]
100007650: 4ea01c02    	mov.16b	v2, v0
100007654: 91092109    	add	x9, x8, #0x248
100007658: 3dc09100    	ldr	q0, [x8, #0x240]
10000765c: 3d814be0    	str	q0, [sp, #0x520]
100007660: 4fc09060    	fmul.2d	v0, v3, v0[0]
100007664: 4ea31c74    	mov.16b	v20, v3
100007668: 3d82dfe3    	str	q3, [sp, #0xb70]
10000766c: 3dc00121    	ldr	q1, [x9]
100007670: 3d814fe1    	str	q1, [sp, #0x530]
100007674: 4fc19041    	fmul.2d	v1, v2, v1[0]
100007678: 3d82a7e2    	str	q2, [sp, #0xa90]
10000767c: 4e61d400    	fadd.2d	v0, v0, v1
100007680: 3dc09501    	ldr	q1, [x8, #0x250]
100007684: 3d8147e1    	str	q1, [sp, #0x510]
100007688: 3dc15d10    	ldr	q16, [x8, #0x570]
10000768c: 4fc19201    	fmul.2d	v1, v16, v1[0]
100007690: 3d82cbf0    	str	q16, [sp, #0xb20]
100007694: 4e61d400    	fadd.2d	v0, v0, v1
100007698: 91096109    	add	x9, x8, #0x258
10000769c: 3dc17517    	ldr	q23, [x8, #0x5d0]
1000076a0: 3dc00121    	ldr	q1, [x9]
1000076a4: 3d8143e1    	str	q1, [sp, #0x500]
1000076a8: 4fc192e1    	fmul.2d	v1, v23, v1[0]
1000076ac: 4e61d400    	fadd.2d	v0, v0, v1
1000076b0: 3dc18d18    	ldr	q24, [x8, #0x630]
1000076b4: ad531101    	ldp	q1, q4, [x8, #0x260]
1000076b8: 3d813fe1    	str	q1, [sp, #0x4f0]
1000076bc: 3d8137e4    	str	q4, [sp, #0x4d0]
1000076c0: 4fc19301    	fmul.2d	v1, v24, v1[0]
1000076c4: 4e61d400    	fadd.2d	v0, v0, v1
1000076c8: 9109a109    	add	x9, x8, #0x268
1000076cc: 3dc1a507    	ldr	q7, [x8, #0x690]
1000076d0: 3dc00121    	ldr	q1, [x9]
1000076d4: 3d813be1    	str	q1, [sp, #0x4e0]
1000076d8: 4fc190e1    	fmul.2d	v1, v7, v1[0]
1000076dc: 3d82d7e7    	str	q7, [sp, #0xb50]
1000076e0: 4e61d400    	fadd.2d	v0, v0, v1
1000076e4: 3dc1bd05    	ldr	q5, [x8, #0x6f0]
1000076e8: 4fc490a1    	fmul.2d	v1, v5, v4[0]
1000076ec: 3d82d3e5    	str	q5, [sp, #0xb40]
1000076f0: 4e61d400    	fadd.2d	v0, v0, v1
1000076f4: 9109e109    	add	x9, x8, #0x278
1000076f8: 3dc1d504    	ldr	q4, [x8, #0x750]
1000076fc: 3dc00121    	ldr	q1, [x9]
100007700: 3d8133e1    	str	q1, [sp, #0x4c0]
100007704: 4fc19081    	fmul.2d	v1, v4, v1[0]
100007708: 3d829fe4    	str	q4, [sp, #0xa70]
10000770c: 4e61d400    	fadd.2d	v0, v0, v1
100007710: 3dc1ed03    	ldr	q3, [x8, #0x7b0]
100007714: 3dc0a101    	ldr	q1, [x8, #0x280]
100007718: 3d812fe1    	str	q1, [sp, #0x4b0]
10000771c: 4fc19061    	fmul.2d	v1, v3, v1[0]
100007720: 3d82cfe3    	str	q3, [sp, #0xb30]
100007724: 4e61d400    	fadd.2d	v0, v0, v1
100007728: 910a2109    	add	x9, x8, #0x288
10000772c: 3dc20506    	ldr	q6, [x8, #0x810]
100007730: 3dc00121    	ldr	q1, [x9]
100007734: 3d812be1    	str	q1, [sp, #0x4a0]
100007738: 4fc190c1    	fmul.2d	v1, v6, v1[0]
10000773c: 3d827be6    	str	q6, [sp, #0x9e0]
100007740: 4e61d411    	fadd.2d	v17, v0, v1
100007744: 910aa109    	add	x9, x8, #0x2a8
100007748: 3dc0a900    	ldr	q0, [x8, #0x2a0]
10000774c: 3d8123e0    	str	q0, [sp, #0x480]
100007750: 4fc09280    	fmul.2d	v0, v20, v0[0]
100007754: 3dc00121    	ldr	q1, [x9]
100007758: 3d8127e1    	str	q1, [sp, #0x490]
10000775c: 4fc19041    	fmul.2d	v1, v2, v1[0]
100007760: 4e61d400    	fadd.2d	v0, v0, v1
100007764: 3dc0ad01    	ldr	q1, [x8, #0x2b0]
100007768: 3d811fe1    	str	q1, [sp, #0x470]
10000776c: 4fc19201    	fmul.2d	v1, v16, v1[0]
100007770: 4e61d400    	fadd.2d	v0, v0, v1
100007774: 910ae109    	add	x9, x8, #0x2b8
100007778: 3dc00121    	ldr	q1, [x9]
10000777c: 3d811be1    	str	q1, [sp, #0x460]
100007780: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100007784: 4e61d400    	fadd.2d	v0, v0, v1
100007788: ad560901    	ldp	q1, q2, [x8, #0x2c0]
10000778c: 3d8117e1    	str	q1, [sp, #0x450]
100007790: 3d8113e2    	str	q2, [sp, #0x440]
100007794: 4fc19301    	fmul.2d	v1, v24, v1[0]
100007798: 4eb81f15    	mov.16b	v21, v24
10000779c: 3d825ff8    	str	q24, [sp, #0x970]
1000077a0: 4e61d400    	fadd.2d	v0, v0, v1
1000077a4: 910b2109    	add	x9, x8, #0x2c8
1000077a8: 3dc00121    	ldr	q1, [x9]
1000077ac: 3d810fe1    	str	q1, [sp, #0x430]
1000077b0: 4fc190e1    	fmul.2d	v1, v7, v1[0]
1000077b4: 4e61d400    	fadd.2d	v0, v0, v1
1000077b8: 4fc290a1    	fmul.2d	v1, v5, v2[0]
1000077bc: 4e61d400    	fadd.2d	v0, v0, v1
1000077c0: 910b6109    	add	x9, x8, #0x2d8
1000077c4: 3dc00121    	ldr	q1, [x9]
1000077c8: 3d810be1    	str	q1, [sp, #0x420]
1000077cc: 4fc19081    	fmul.2d	v1, v4, v1[0]
1000077d0: 4e61d400    	fadd.2d	v0, v0, v1
1000077d4: 3dc0b901    	ldr	q1, [x8, #0x2e0]
1000077d8: 3d8107e1    	str	q1, [sp, #0x410]
1000077dc: 4fc19061    	fmul.2d	v1, v3, v1[0]
1000077e0: 4e61d400    	fadd.2d	v0, v0, v1
1000077e4: 91132109    	add	x9, x8, #0x4c8
1000077e8: 3dc13101    	ldr	q1, [x8, #0x4c0]
1000077ec: 4fcc9022    	fmul.2d	v2, v1, v12[0]
1000077f0: 3d8237e2    	str	q2, [sp, #0x8d0]
1000077f4: 4d408521    	ld1.d	{ v1 }[1], [x9]
1000077f8: 4ea11c22    	mov.16b	v2, v1
1000077fc: 910ba109    	add	x9, x8, #0x2e8
100007800: 3dc00121    	ldr	q1, [x9]
100007804: 3d8103e1    	str	q1, [sp, #0x400]
100007808: 4fc190c1    	fmul.2d	v1, v6, v1[0]
10000780c: 4e61d40c    	fadd.2d	v12, v0, v1
100007810: 9114a109    	add	x9, x8, #0x528
100007814: 3dc14900    	ldr	q0, [x8, #0x520]
100007818: 4fcd9001    	fmul.2d	v1, v0, v13[0]
10000781c: 3d80d3e1    	str	q1, [sp, #0x340]
100007820: 4d408520    	ld1.d	{ v0 }[1], [x9]
100007824: 4ea01c03    	mov.16b	v3, v0
100007828: 910c2109    	add	x9, x8, #0x308
10000782c: 3dc0c100    	ldr	q0, [x8, #0x300]
100007830: 3d80fbe0    	str	q0, [sp, #0x3e0]
100007834: 4ea21c46    	mov.16b	v6, v2
100007838: 3d8273e2    	str	q2, [sp, #0x9c0]
10000783c: 4fc09040    	fmul.2d	v0, v2, v0[0]
100007840: 3dc00121    	ldr	q1, [x9]
100007844: 3d80ffe1    	str	q1, [sp, #0x3f0]
100007848: 4fc19061    	fmul.2d	v1, v3, v1[0]
10000784c: 4ea31c72    	mov.16b	v18, v3
100007850: 3d826fe3    	str	q3, [sp, #0x9b0]
100007854: 4e61d400    	fadd.2d	v0, v0, v1
100007858: 3dc0c501    	ldr	q1, [x8, #0x310]
10000785c: 3d80f7e1    	str	q1, [sp, #0x3d0]
100007860: 3dc16110    	ldr	q16, [x8, #0x580]
100007864: 4fc19201    	fmul.2d	v1, v16, v1[0]
100007868: 3d829bf0    	str	q16, [sp, #0xa60]
10000786c: 4e61d400    	fadd.2d	v0, v0, v1
100007870: 910c6109    	add	x9, x8, #0x318
100007874: 3dc17907    	ldr	q7, [x8, #0x5e0]
100007878: 3dc00121    	ldr	q1, [x9]
10000787c: 3d80f3e1    	str	q1, [sp, #0x3c0]
100007880: 4fc190e1    	fmul.2d	v1, v7, v1[0]
100007884: 3d82c7e7    	str	q7, [sp, #0xb10]
100007888: 4e61d400    	fadd.2d	v0, v0, v1
10000788c: 3dc1910a    	ldr	q10, [x8, #0x640]
100007890: ad591101    	ldp	q1, q4, [x8, #0x320]
100007894: 3d80efe1    	str	q1, [sp, #0x3b0]
100007898: 4fc19141    	fmul.2d	v1, v10, v1[0]
10000789c: 3d826bea    	str	q10, [sp, #0x9a0]
1000078a0: 4e61d400    	fadd.2d	v0, v0, v1
1000078a4: 910ca109    	add	x9, x8, #0x328
1000078a8: 3dc1a903    	ldr	q3, [x8, #0x6a0]
1000078ac: 3dc00121    	ldr	q1, [x9]
1000078b0: ad1c87e4    	stp	q4, q1, [sp, #0x390]
1000078b4: 4fc19061    	fmul.2d	v1, v3, v1[0]
1000078b8: 3d82c3e3    	str	q3, [sp, #0xb00]
1000078bc: 4e61d400    	fadd.2d	v0, v0, v1
1000078c0: 3dc1c114    	ldr	q20, [x8, #0x700]
1000078c4: 4fc49281    	fmul.2d	v1, v20, v4[0]
1000078c8: 3d8297f4    	str	q20, [sp, #0xa50]
1000078cc: 4e61d400    	fadd.2d	v0, v0, v1
1000078d0: 910ce109    	add	x9, x8, #0x338
1000078d4: 3dc1d905    	ldr	q5, [x8, #0x760]
1000078d8: 3dc00121    	ldr	q1, [x9]
1000078dc: 3d80e3e1    	str	q1, [sp, #0x380]
1000078e0: 4fc190a1    	fmul.2d	v1, v5, v1[0]
1000078e4: 3d82bfe5    	str	q5, [sp, #0xaf0]
1000078e8: 4e61d400    	fadd.2d	v0, v0, v1
1000078ec: 3dc1f118    	ldr	q24, [x8, #0x7c0]
1000078f0: 3dc0d101    	ldr	q1, [x8, #0x340]
1000078f4: 3d80dfe1    	str	q1, [sp, #0x370]
1000078f8: 4fc19301    	fmul.2d	v1, v24, v1[0]
1000078fc: 3d8293f8    	str	q24, [sp, #0xa40]
100007900: 4e61d400    	fadd.2d	v0, v0, v1
100007904: 910d2109    	add	x9, x8, #0x348
100007908: 3dc2090b    	ldr	q11, [x8, #0x820]
10000790c: 3dc00121    	ldr	q1, [x9]
100007910: 3d80dbe1    	str	q1, [sp, #0x360]
100007914: 4fc19161    	fmul.2d	v1, v11, v1[0]
100007918: 4e61d402    	fadd.2d	v2, v0, v1
10000791c: 910da109    	add	x9, x8, #0x368
100007920: 3dc0d900    	ldr	q0, [x8, #0x360]
100007924: 3d8027e0    	str	q0, [sp, #0x90]
100007928: 4fc090c0    	fmul.2d	v0, v6, v0[0]
10000792c: 3dc00121    	ldr	q1, [x9]
100007930: 3d802be1    	str	q1, [sp, #0xa0]
100007934: 4fc19241    	fmul.2d	v1, v18, v1[0]
100007938: 4e61d400    	fadd.2d	v0, v0, v1
10000793c: 3dc0dd01    	ldr	q1, [x8, #0x370]
100007940: 3d8023e1    	str	q1, [sp, #0x80]
100007944: 4fc19201    	fmul.2d	v1, v16, v1[0]
100007948: 4e61d400    	fadd.2d	v0, v0, v1
10000794c: 910de109    	add	x9, x8, #0x378
100007950: 3dc00121    	ldr	q1, [x9]
100007954: 3d801fe1    	str	q1, [sp, #0x70]
100007958: 4fc190e1    	fmul.2d	v1, v7, v1[0]
10000795c: 4e61d400    	fadd.2d	v0, v0, v1
100007960: ad5c1101    	ldp	q1, q4, [x8, #0x380]
100007964: ad0287e4    	stp	q4, q1, [sp, #0x50]
100007968: 4fc19141    	fmul.2d	v1, v10, v1[0]
10000796c: 4e61d400    	fadd.2d	v0, v0, v1
100007970: 910e2109    	add	x9, x8, #0x388
100007974: 3dc00121    	ldr	q1, [x9]
100007978: 3d8013e1    	str	q1, [sp, #0x40]
10000797c: 4fc19061    	fmul.2d	v1, v3, v1[0]
100007980: 4e61d400    	fadd.2d	v0, v0, v1
100007984: 4fc49281    	fmul.2d	v1, v20, v4[0]
100007988: 4e61d400    	fadd.2d	v0, v0, v1
10000798c: 910e6109    	add	x9, x8, #0x398
100007990: 3dc00121    	ldr	q1, [x9]
100007994: 3d800fe1    	str	q1, [sp, #0x30]
100007998: 4fc190a1    	fmul.2d	v1, v5, v1[0]
10000799c: 4e61d400    	fadd.2d	v0, v0, v1
1000079a0: 3dc0e901    	ldr	q1, [x8, #0x3a0]
1000079a4: 3d800be1    	str	q1, [sp, #0x20]
1000079a8: 4fc19301    	fmul.2d	v1, v24, v1[0]
1000079ac: 4e61d400    	fadd.2d	v0, v0, v1
1000079b0: 910ea109    	add	x9, x8, #0x3a8
1000079b4: 3dc00121    	ldr	q1, [x9]
1000079b8: 3d8007e1    	str	q1, [sp, #0x10]
1000079bc: 4fc19161    	fmul.2d	v1, v11, v1[0]
1000079c0: 3d828feb    	str	q11, [sp, #0xa30]
1000079c4: 4e61d404    	fadd.2d	v4, v0, v1
1000079c8: 3d8253fd    	str	q29, [sp, #0x940]
1000079cc: 4e1807a0    	dup.2d	v0, v29[1]
1000079d0: 3dc257e1    	ldr	q1, [sp, #0x950]
1000079d4: 4e60d420    	fadd.2d	v0, v1, v0
1000079d8: ad1227fe    	stp	q30, q9, [sp, #0x240]
1000079dc: 4e69d400    	fadd.2d	v0, v0, v9
1000079e0: 3d80d7e8    	str	q8, [sp, #0x350]
1000079e4: 4e180501    	dup.2d	v1, v8[1]
1000079e8: 4e61d400    	fadd.2d	v0, v0, v1
1000079ec: 4e7ed400    	fadd.2d	v0, v0, v30
1000079f0: ad0dcff1    	stp	q17, q19, [sp, #0x1b0]
1000079f4: 4e180661    	dup.2d	v1, v19[1]
1000079f8: 4e61d400    	fadd.2d	v0, v0, v1
1000079fc: 4e71d400    	fadd.2d	v0, v0, v17
100007a00: 3d808fec    	str	q12, [sp, #0x230]
100007a04: 4e180581    	dup.2d	v1, v12[1]
100007a08: 4e61d400    	fadd.2d	v0, v0, v1
100007a0c: 3d806be2    	str	q2, [sp, #0x1a0]
100007a10: 4e62d400    	fadd.2d	v0, v0, v2
100007a14: 3d803fe4    	str	q4, [sp, #0xf0]
100007a18: 4e180481    	dup.2d	v1, v4[1]
100007a1c: 4e61d400    	fadd.2d	v0, v0, v1
100007a20: 1e60c000    	fabs	d0, d0
100007a24: d2857369    	mov	x9, #0x2b9b             ; =11163
100007a28: f2b0d429    	movk	x9, #0x86a1, lsl #16
100007a2c: f2d09369    	movk	x9, #0x849b, lsl #32
100007a30: f2e7a0c9    	movk	x9, #0x3d06, lsl #48
100007a34: 9e670121    	fmov	d1, x9
100007a38: 1e612000    	fcmp	d0, d1
100007a3c: 3dc24fe0    	ldr	q0, [sp, #0x930]
100007a40: 3dc24be1    	ldr	q1, [sp, #0x920]
100007a44: 4e61d400    	fadd.2d	v0, v0, v1
100007a48: 3dc21fe7    	ldr	q7, [sp, #0x870]
100007a4c: 3d828bf9    	str	q25, [sp, #0xa20]
100007a50: 4fc79321    	fmul.2d	v1, v25, v7[0]
100007a54: 4e61d400    	fadd.2d	v0, v0, v1
100007a58: 3dc1cfe9    	ldr	q9, [sp, #0x730]
100007a5c: 3d8287fb    	str	q27, [sp, #0xa10]
100007a60: 4fc99361    	fmul.2d	v1, v27, v9[0]
100007a64: 4e61d400    	fadd.2d	v0, v0, v1
100007a68: 4eba1f44    	mov.16b	v4, v26
100007a6c: 3d8267fa    	str	q26, [sp, #0x990]
100007a70: 3dc17be5    	ldr	q5, [sp, #0x5e0]
100007a74: 4fc59341    	fmul.2d	v1, v26, v5[0]
100007a78: 4e61d400    	fadd.2d	v0, v0, v1
100007a7c: 3dc2e7fa    	ldr	q26, [sp, #0xb90]
100007a80: 3dc233e6    	ldr	q6, [sp, #0x8c0]
100007a84: 4fc69341    	fmul.2d	v1, v26, v6[0]
100007a88: 4e61d400    	fadd.2d	v0, v0, v1
100007a8c: 4ebc1f90    	mov.16b	v16, v28
100007a90: 3d82bbfc    	str	q28, [sp, #0xae0]
100007a94: 3dc22ffc    	ldr	q28, [sp, #0x8b0]
100007a98: 4fdc9201    	fmul.2d	v1, v16, v28[0]
100007a9c: 4e61d400    	fadd.2d	v0, v0, v1
100007aa0: 4ebf1fe2    	mov.16b	v2, v31
100007aa4: 3d8283ff    	str	q31, [sp, #0xa00]
100007aa8: 3dc22bfd    	ldr	q29, [sp, #0x8a0]
100007aac: 4fdd93e1    	fmul.2d	v1, v31, v29[0]
100007ab0: 4e61d400    	fadd.2d	v0, v0, v1
100007ab4: 3dc227ff    	ldr	q31, [sp, #0x890]
100007ab8: 3d8263ee    	str	q14, [sp, #0x980]
100007abc: 4fdf91c1    	fmul.2d	v1, v14, v31[0]
100007ac0: 4e61d400    	fadd.2d	v0, v0, v1
100007ac4: 3dc223f2    	ldr	q18, [sp, #0x880]
100007ac8: 3d82b7ef    	str	q15, [sp, #0xad0]
100007acc: 4fd291e1    	fmul.2d	v1, v15, v18[0]
100007ad0: 4e61d400    	fadd.2d	v0, v0, v1
100007ad4: 3d8067e0    	str	q0, [sp, #0x190]
100007ad8: 3dc247e0    	ldr	q0, [sp, #0x910]
100007adc: 3dc243e1    	ldr	q1, [sp, #0x900]
100007ae0: 4e61d400    	fadd.2d	v0, v0, v1
100007ae4: 3dc313f1    	ldr	q17, [sp, #0xc40]
100007ae8: 4fc79221    	fmul.2d	v1, v17, v7[0]
100007aec: 4e61d400    	fadd.2d	v0, v0, v1
100007af0: 3dc2dbfe    	ldr	q30, [sp, #0xb60]
100007af4: 4fc993c1    	fmul.2d	v1, v30, v9[0]
100007af8: 4e61d400    	fadd.2d	v0, v0, v1
100007afc: 3dc2e3ec    	ldr	q12, [sp, #0xb80]
100007b00: 4fc59181    	fmul.2d	v1, v12, v5[0]
100007b04: 4e61d400    	fadd.2d	v0, v0, v1
100007b08: 3dc30fed    	ldr	q13, [sp, #0xc30]
100007b0c: 4fc691a1    	fmul.2d	v1, v13, v6[0]
100007b10: 4e61d400    	fadd.2d	v0, v0, v1
100007b14: 3dc30be8    	ldr	q8, [sp, #0xc20]
100007b18: 4fdc9101    	fmul.2d	v1, v8, v28[0]
100007b1c: 4e61d400    	fadd.2d	v0, v0, v1
100007b20: 3dc2a3f4    	ldr	q20, [sp, #0xa80]
100007b24: 4fdd9281    	fmul.2d	v1, v20, v29[0]
100007b28: 4e61d400    	fadd.2d	v0, v0, v1
100007b2c: 3dc277f3    	ldr	q19, [sp, #0x9d0]
100007b30: 4fdf9261    	fmul.2d	v1, v19, v31[0]
100007b34: 4e61d400    	fadd.2d	v0, v0, v1
100007b38: 4fd292c1    	fmul.2d	v1, v22, v18[0]
100007b3c: 4e61d400    	fadd.2d	v0, v0, v1
100007b40: 3d8243e0    	str	q0, [sp, #0x900]
100007b44: 3dc23fe0    	ldr	q0, [sp, #0x8f0]
100007b48: 3dc23be1    	ldr	q1, [sp, #0x8e0]
100007b4c: 4e61d400    	fadd.2d	v0, v0, v1
100007b50: 3dc2cbe1    	ldr	q1, [sp, #0xb20]
100007b54: 4fc79021    	fmul.2d	v1, v1, v7[0]
100007b58: 4e61d400    	fadd.2d	v0, v0, v1
100007b5c: 3d827ff7    	str	q23, [sp, #0x9f0]
100007b60: 4fc992e1    	fmul.2d	v1, v23, v9[0]
100007b64: 4e61d400    	fadd.2d	v0, v0, v1
100007b68: 4fc592a1    	fmul.2d	v1, v21, v5[0]
100007b6c: 4e61d400    	fadd.2d	v0, v0, v1
100007b70: 3dc2d7ea    	ldr	q10, [sp, #0xb50]
100007b74: 4fc69141    	fmul.2d	v1, v10, v6[0]
100007b78: 4e61d400    	fadd.2d	v0, v0, v1
100007b7c: 3dc2d3e1    	ldr	q1, [sp, #0xb40]
100007b80: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100007b84: 4e61d400    	fadd.2d	v0, v0, v1
100007b88: 3dc29ff7    	ldr	q23, [sp, #0xa70]
100007b8c: 4fdd92e1    	fmul.2d	v1, v23, v29[0]
100007b90: 4e61d400    	fadd.2d	v0, v0, v1
100007b94: 3dc2cff5    	ldr	q21, [sp, #0xb30]
100007b98: 4fdf92a1    	fmul.2d	v1, v21, v31[0]
100007b9c: 4e61d400    	fadd.2d	v0, v0, v1
100007ba0: 3dc27bf8    	ldr	q24, [sp, #0x9e0]
100007ba4: 4fd29301    	fmul.2d	v1, v24, v18[0]
100007ba8: 4e61d400    	fadd.2d	v0, v0, v1
100007bac: 3d803be0    	str	q0, [sp, #0xe0]
100007bb0: 3dc237e0    	ldr	q0, [sp, #0x8d0]
100007bb4: 3dc0d3e1    	ldr	q1, [sp, #0x340]
100007bb8: 4e61d400    	fadd.2d	v0, v0, v1
100007bbc: 3dc29be1    	ldr	q1, [sp, #0xa60]
100007bc0: 4fc79021    	fmul.2d	v1, v1, v7[0]
100007bc4: 4e61d400    	fadd.2d	v0, v0, v1
100007bc8: 3dc2c7e1    	ldr	q1, [sp, #0xb10]
100007bcc: 4fc99021    	fmul.2d	v1, v1, v9[0]
100007bd0: 4e61d400    	fadd.2d	v0, v0, v1
100007bd4: 3dc26be1    	ldr	q1, [sp, #0x9a0]
100007bd8: 4fc59021    	fmul.2d	v1, v1, v5[0]
100007bdc: 4e61d400    	fadd.2d	v0, v0, v1
100007be0: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
100007be4: 4fc69021    	fmul.2d	v1, v1, v6[0]
100007be8: 4e61d400    	fadd.2d	v0, v0, v1
100007bec: 3dc297e1    	ldr	q1, [sp, #0xa50]
100007bf0: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100007bf4: 4e61d400    	fadd.2d	v0, v0, v1
100007bf8: 3dc2bfe1    	ldr	q1, [sp, #0xaf0]
100007bfc: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100007c00: 4e61d400    	fadd.2d	v0, v0, v1
100007c04: 3dc293e1    	ldr	q1, [sp, #0xa40]
100007c08: 4fdf9021    	fmul.2d	v1, v1, v31[0]
100007c0c: 4e61d400    	fadd.2d	v0, v0, v1
100007c10: 4fd29161    	fmul.2d	v1, v11, v18[0]
100007c14: 4e61d400    	fadd.2d	v0, v0, v1
100007c18: 3d808be0    	str	q0, [sp, #0x220]
100007c1c: 3cc68103    	ldur	q3, [x8, #0x68]
100007c20: 3dc21be5    	ldr	q5, [sp, #0x860]
100007c24: 3dc2efe0    	ldr	q0, [sp, #0xbb0]
100007c28: 4fc59000    	fmul.2d	v0, v0, v5[0]
100007c2c: 3dc2ebe1    	ldr	q1, [sp, #0xba0]
100007c30: 4fc39021    	fmul.2d	v1, v1, v3[0]
100007c34: 4e61d400    	fadd.2d	v0, v0, v1
100007c38: 3dc217eb    	ldr	q11, [sp, #0x850]
100007c3c: 4fcb9321    	fmul.2d	v1, v25, v11[0]
100007c40: 4e61d400    	fadd.2d	v0, v0, v1
100007c44: 3dc213e6    	ldr	q6, [sp, #0x840]
100007c48: 4fc69361    	fmul.2d	v1, v27, v6[0]
100007c4c: 4e61d400    	fadd.2d	v0, v0, v1
100007c50: 3dc20ffc    	ldr	q28, [sp, #0x830]
100007c54: 4fdc9081    	fmul.2d	v1, v4, v28[0]
100007c58: 4e61d400    	fadd.2d	v0, v0, v1
100007c5c: 3dc20bfd    	ldr	q29, [sp, #0x820]
100007c60: 4fdd9341    	fmul.2d	v1, v26, v29[0]
100007c64: 4e61d400    	fadd.2d	v0, v0, v1
100007c68: 3dc207e4    	ldr	q4, [sp, #0x810]
100007c6c: 4fc49201    	fmul.2d	v1, v16, v4[0]
100007c70: 4e61d400    	fadd.2d	v0, v0, v1
100007c74: 3dc203ff    	ldr	q31, [sp, #0x800]
100007c78: 4fdf9041    	fmul.2d	v1, v2, v31[0]
100007c7c: 4e61d400    	fadd.2d	v0, v0, v1
100007c80: 3dc1ffe2    	ldr	q2, [sp, #0x7f0]
100007c84: 4fc291c1    	fmul.2d	v1, v14, v2[0]
100007c88: 4e61d400    	fadd.2d	v0, v0, v1
100007c8c: 3dc1fbe9    	ldr	q9, [sp, #0x7e0]
100007c90: 4fc991e1    	fmul.2d	v1, v15, v9[0]
100007c94: 4e61d400    	fadd.2d	v0, v0, v1
100007c98: 3d8063e0    	str	q0, [sp, #0x180]
100007c9c: 3dc2aff2    	ldr	q18, [sp, #0xab0]
100007ca0: 4fc59240    	fmul.2d	v0, v18, v5[0]
100007ca4: 3dc2abe7    	ldr	q7, [sp, #0xaa0]
100007ca8: 4fc390e1    	fmul.2d	v1, v7, v3[0]
100007cac: 4e61d400    	fadd.2d	v0, v0, v1
100007cb0: 4fcb9221    	fmul.2d	v1, v17, v11[0]
100007cb4: 4e61d400    	fadd.2d	v0, v0, v1
100007cb8: 4fc693c1    	fmul.2d	v1, v30, v6[0]
100007cbc: 4e61d400    	fadd.2d	v0, v0, v1
100007cc0: 4fdc9181    	fmul.2d	v1, v12, v28[0]
100007cc4: 4eac1d91    	mov.16b	v17, v12
100007cc8: 4e61d400    	fadd.2d	v0, v0, v1
100007ccc: 4fdd91a1    	fmul.2d	v1, v13, v29[0]
100007cd0: 4e61d400    	fadd.2d	v0, v0, v1
100007cd4: 4ea41c9e    	mov.16b	v30, v4
100007cd8: 4fc49101    	fmul.2d	v1, v8, v4[0]
100007cdc: 4e61d400    	fadd.2d	v0, v0, v1
100007ce0: 4fdf9281    	fmul.2d	v1, v20, v31[0]
100007ce4: 4e61d400    	fadd.2d	v0, v0, v1
100007ce8: 4fc29261    	fmul.2d	v1, v19, v2[0]
100007cec: 4e61d400    	fadd.2d	v0, v0, v1
100007cf0: 4fc992c1    	fmul.2d	v1, v22, v9[0]
100007cf4: 4e61d400    	fadd.2d	v0, v0, v1
100007cf8: 3d805fe0    	str	q0, [sp, #0x170]
100007cfc: 3dc2dfe0    	ldr	q0, [sp, #0xb70]
100007d00: 4fc59000    	fmul.2d	v0, v0, v5[0]
100007d04: 3d8003e3    	str	q3, [sp]
100007d08: 3dc2a7e1    	ldr	q1, [sp, #0xa90]
100007d0c: 4fc39021    	fmul.2d	v1, v1, v3[0]
100007d10: 4e61d400    	fadd.2d	v0, v0, v1
100007d14: 3dc2cbf9    	ldr	q25, [sp, #0xb20]
100007d18: 4fcb9321    	fmul.2d	v1, v25, v11[0]
100007d1c: 4e61d400    	fadd.2d	v0, v0, v1
100007d20: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
100007d24: 4fc69021    	fmul.2d	v1, v1, v6[0]
100007d28: 4e61d400    	fadd.2d	v0, v0, v1
100007d2c: 3dc25fef    	ldr	q15, [sp, #0x970]
100007d30: 4fdc91e1    	fmul.2d	v1, v15, v28[0]
100007d34: 4e61d400    	fadd.2d	v0, v0, v1
100007d38: 4fdd9141    	fmul.2d	v1, v10, v29[0]
100007d3c: 4e61d400    	fadd.2d	v0, v0, v1
100007d40: 3dc2d3e1    	ldr	q1, [sp, #0xb40]
100007d44: 4fc49021    	fmul.2d	v1, v1, v4[0]
100007d48: 4e61d400    	fadd.2d	v0, v0, v1
100007d4c: 4fdf92e1    	fmul.2d	v1, v23, v31[0]
100007d50: 4e61d400    	fadd.2d	v0, v0, v1
100007d54: 4fc292a1    	fmul.2d	v1, v21, v2[0]
100007d58: 4e61d400    	fadd.2d	v0, v0, v1
100007d5c: 4fc99301    	fmul.2d	v1, v24, v9[0]
100007d60: 4e61d400    	fadd.2d	v0, v0, v1
100007d64: 3d8037e0    	str	q0, [sp, #0xd0]
100007d68: 3dc273f0    	ldr	q16, [sp, #0x9c0]
100007d6c: 4fc59200    	fmul.2d	v0, v16, v5[0]
100007d70: 3dc26fe4    	ldr	q4, [sp, #0x9b0]
100007d74: 4fc39081    	fmul.2d	v1, v4, v3[0]
100007d78: 4e61d400    	fadd.2d	v0, v0, v1
100007d7c: 3dc29be1    	ldr	q1, [sp, #0xa60]
100007d80: 4fcb9021    	fmul.2d	v1, v1, v11[0]
100007d84: 4e61d400    	fadd.2d	v0, v0, v1
100007d88: 3dc2c7e1    	ldr	q1, [sp, #0xb10]
100007d8c: 4fc69021    	fmul.2d	v1, v1, v6[0]
100007d90: 4e61d400    	fadd.2d	v0, v0, v1
100007d94: 3dc26bee    	ldr	q14, [sp, #0x9a0]
100007d98: 4fdc91c1    	fmul.2d	v1, v14, v28[0]
100007d9c: 4e61d400    	fadd.2d	v0, v0, v1
100007da0: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
100007da4: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100007da8: 4e61d400    	fadd.2d	v0, v0, v1
100007dac: 3dc297f7    	ldr	q23, [sp, #0xa50]
100007db0: 4fde92e1    	fmul.2d	v1, v23, v30[0]
100007db4: 4e61d400    	fadd.2d	v0, v0, v1
100007db8: 3dc2bfe1    	ldr	q1, [sp, #0xaf0]
100007dbc: 4fdf9021    	fmul.2d	v1, v1, v31[0]
100007dc0: 4e61d400    	fadd.2d	v0, v0, v1
100007dc4: 3dc293f8    	ldr	q24, [sp, #0xa40]
100007dc8: 4fc29301    	fmul.2d	v1, v24, v2[0]
100007dcc: 4e61d400    	fadd.2d	v0, v0, v1
100007dd0: 3dc28fe1    	ldr	q1, [sp, #0xa30]
100007dd4: 4fc99021    	fmul.2d	v1, v1, v9[0]
100007dd8: 4e61d400    	fadd.2d	v0, v0, v1
100007ddc: 3d823fe0    	str	q0, [sp, #0x8f0]
100007de0: 3dc1f3f5    	ldr	q21, [sp, #0x7c0]
100007de4: 3dc307e0    	ldr	q0, [sp, #0xc10]
100007de8: 6e75dc00    	fmul.2d	v0, v0, v21
100007dec: 6e004000    	ext.16b	v0, v0, v0, #0x8
100007df0: 3dc303eb    	ldr	q11, [sp, #0xc00]
100007df4: 6e75dd61    	fmul.2d	v1, v11, v21
100007df8: 4e61d400    	fadd.2d	v0, v0, v1
100007dfc: 3dc2b3e5    	ldr	q5, [sp, #0xac0]
100007e00: 3dc1effc    	ldr	q28, [sp, #0x7b0]
100007e04: 4fdc90a1    	fmul.2d	v1, v5, v28[0]
100007e08: 4e61d400    	fadd.2d	v0, v0, v1
100007e0c: 3dc1ebea    	ldr	q10, [sp, #0x7a0]
100007e10: 3dc31fe1    	ldr	q1, [sp, #0xc70]
100007e14: 4fca9021    	fmul.2d	v1, v1, v10[0]
100007e18: 4e61d400    	fadd.2d	v0, v0, v1
100007e1c: 3dc1e7e3    	ldr	q3, [sp, #0x790]
100007e20: 3dc2fffb    	ldr	q27, [sp, #0xbf0]
100007e24: 4fc39361    	fmul.2d	v1, v27, v3[0]
100007e28: 4e61d400    	fadd.2d	v0, v0, v1
100007e2c: 3dc1e3e8    	ldr	q8, [sp, #0x780]
100007e30: 3dc31bfa    	ldr	q26, [sp, #0xc60]
100007e34: 4fc89341    	fmul.2d	v1, v26, v8[0]
100007e38: 4e61d400    	fadd.2d	v0, v0, v1
100007e3c: 3dc1dfe9    	ldr	q9, [sp, #0x770]
100007e40: 3dc317e1    	ldr	q1, [sp, #0xc50]
100007e44: 4fc99021    	fmul.2d	v1, v1, v9[0]
100007e48: 4e61d400    	fadd.2d	v0, v0, v1
100007e4c: 3dc2fbfd    	ldr	q29, [sp, #0xbe0]
100007e50: 3dc1dbec    	ldr	q12, [sp, #0x760]
100007e54: 4fcc93a1    	fmul.2d	v1, v29, v12[0]
100007e58: 4e61d400    	fadd.2d	v0, v0, v1
100007e5c: 3dc1d7ed    	ldr	q13, [sp, #0x750]
100007e60: 3dc2f7e1    	ldr	q1, [sp, #0xbd0]
100007e64: 4fcd9021    	fmul.2d	v1, v1, v13[0]
100007e68: 4e61d400    	fadd.2d	v0, v0, v1
100007e6c: 3dc1d3ff    	ldr	q31, [sp, #0x740]
100007e70: 3dc2f3e1    	ldr	q1, [sp, #0xbc0]
100007e74: 4fdf9021    	fmul.2d	v1, v1, v31[0]
100007e78: 4e61d400    	fadd.2d	v0, v0, v1
100007e7c: 3d809be0    	str	q0, [sp, #0x260]
100007e80: 4fd59240    	fmul.2d	v0, v18, v21[0]
100007e84: 3dc1f7e6    	ldr	q6, [sp, #0x7d0]
100007e88: 4fc690e1    	fmul.2d	v1, v7, v6[0]
100007e8c: 4e61d400    	fadd.2d	v0, v0, v1
100007e90: 3dc313e1    	ldr	q1, [sp, #0xc40]
100007e94: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100007e98: 4ebc1f92    	mov.16b	v18, v28
100007e9c: 4e61d400    	fadd.2d	v0, v0, v1
100007ea0: 3dc2dbe1    	ldr	q1, [sp, #0xb60]
100007ea4: 4fca9021    	fmul.2d	v1, v1, v10[0]
100007ea8: 4e61d400    	fadd.2d	v0, v0, v1
100007eac: 4fc39221    	fmul.2d	v1, v17, v3[0]
100007eb0: 4e61d400    	fadd.2d	v0, v0, v1
100007eb4: 3dc30fe1    	ldr	q1, [sp, #0xc30]
100007eb8: 4fc89021    	fmul.2d	v1, v1, v8[0]
100007ebc: 4e61d400    	fadd.2d	v0, v0, v1
100007ec0: 3dc30be1    	ldr	q1, [sp, #0xc20]
100007ec4: 4fc99021    	fmul.2d	v1, v1, v9[0]
100007ec8: 4e61d400    	fadd.2d	v0, v0, v1
100007ecc: 4eb41e91    	mov.16b	v17, v20
100007ed0: 4eac1d9c    	mov.16b	v28, v12
100007ed4: 4fcc9281    	fmul.2d	v1, v20, v12[0]
100007ed8: 4e61d400    	fadd.2d	v0, v0, v1
100007edc: 4fcd9261    	fmul.2d	v1, v19, v13[0]
100007ee0: 4e61d400    	fadd.2d	v0, v0, v1
100007ee4: 3d825bf6    	str	q22, [sp, #0x960]
100007ee8: 4fdf92c1    	fmul.2d	v1, v22, v31[0]
100007eec: 4e61d400    	fadd.2d	v0, v0, v1
100007ef0: 3d80d3e0    	str	q0, [sp, #0x340]
100007ef4: 3dc2dff4    	ldr	q20, [sp, #0xb70]
100007ef8: 4eb51ea2    	mov.16b	v2, v21
100007efc: 4fd59280    	fmul.2d	v0, v20, v21[0]
100007f00: 3dc2a7f5    	ldr	q21, [sp, #0xa90]
100007f04: 4fc692a1    	fmul.2d	v1, v21, v6[0]
100007f08: 4e61d400    	fadd.2d	v0, v0, v1
100007f0c: 4fd29321    	fmul.2d	v1, v25, v18[0]
100007f10: 4e61d400    	fadd.2d	v0, v0, v1
100007f14: 4eaa1d59    	mov.16b	v25, v10
100007f18: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
100007f1c: 4fca9021    	fmul.2d	v1, v1, v10[0]
100007f20: 4e61d400    	fadd.2d	v0, v0, v1
100007f24: 4fc391e1    	fmul.2d	v1, v15, v3[0]
100007f28: 4e61d400    	fadd.2d	v0, v0, v1
100007f2c: 3dc2d7e1    	ldr	q1, [sp, #0xb50]
100007f30: 4fc89021    	fmul.2d	v1, v1, v8[0]
100007f34: 4e61d400    	fadd.2d	v0, v0, v1
100007f38: 3dc2d3e1    	ldr	q1, [sp, #0xb40]
100007f3c: 4fc99021    	fmul.2d	v1, v1, v9[0]
100007f40: 4ea91d2c    	mov.16b	v12, v9
100007f44: 4e61d400    	fadd.2d	v0, v0, v1
100007f48: 3dc29fe9    	ldr	q9, [sp, #0xa70]
100007f4c: 4fdc9121    	fmul.2d	v1, v9, v28[0]
100007f50: 4e61d400    	fadd.2d	v0, v0, v1
100007f54: 3dc2cfe1    	ldr	q1, [sp, #0xb30]
100007f58: 4fcd9021    	fmul.2d	v1, v1, v13[0]
100007f5c: 4e61d400    	fadd.2d	v0, v0, v1
100007f60: 3dc27bea    	ldr	q10, [sp, #0x9e0]
100007f64: 4fdf9141    	fmul.2d	v1, v10, v31[0]
100007f68: 4ebf1fef    	mov.16b	v15, v31
100007f6c: 4e61d400    	fadd.2d	v0, v0, v1
100007f70: 3d80cfe0    	str	q0, [sp, #0x330]
100007f74: 4fc29200    	fmul.2d	v0, v16, v2[0]
100007f78: 4fc69081    	fmul.2d	v1, v4, v6[0]
100007f7c: 4e61d400    	fadd.2d	v0, v0, v1
100007f80: 3dc29be6    	ldr	q6, [sp, #0xa60]
100007f84: 4fd290c1    	fmul.2d	v1, v6, v18[0]
100007f88: 4e61d400    	fadd.2d	v0, v0, v1
100007f8c: 3dc2c7e7    	ldr	q7, [sp, #0xb10]
100007f90: 4fd990e1    	fmul.2d	v1, v7, v25[0]
100007f94: 4e61d400    	fadd.2d	v0, v0, v1
100007f98: 4fc391c1    	fmul.2d	v1, v14, v3[0]
100007f9c: 4e61d400    	fadd.2d	v0, v0, v1
100007fa0: 3dc2c3fe    	ldr	q30, [sp, #0xb00]
100007fa4: 4fc893c1    	fmul.2d	v1, v30, v8[0]
100007fa8: 4e61d400    	fadd.2d	v0, v0, v1
100007fac: 4fcc92e1    	fmul.2d	v1, v23, v12[0]
100007fb0: 4e61d400    	fadd.2d	v0, v0, v1
100007fb4: 3dc2bfff    	ldr	q31, [sp, #0xaf0]
100007fb8: 4fdc93e1    	fmul.2d	v1, v31, v28[0]
100007fbc: 4e61d400    	fadd.2d	v0, v0, v1
100007fc0: 4fcd9301    	fmul.2d	v1, v24, v13[0]
100007fc4: 4e61d400    	fadd.2d	v0, v0, v1
100007fc8: 3dc28fe1    	ldr	q1, [sp, #0xa30]
100007fcc: 4fcf9021    	fmul.2d	v1, v1, v15[0]
100007fd0: 4e61d400    	fadd.2d	v0, v0, v1
100007fd4: 3d805be0    	str	q0, [sp, #0x160]
100007fd8: 3dc307ee    	ldr	q14, [sp, #0xc10]
100007fdc: 3dc1c7f0    	ldr	q16, [sp, #0x710]
100007fe0: 6e70ddc0    	fmul.2d	v0, v14, v16
100007fe4: 6e004000    	ext.16b	v0, v0, v0, #0x8
100007fe8: 6e70dd61    	fmul.2d	v1, v11, v16
100007fec: 4e61d400    	fadd.2d	v0, v0, v1
100007ff0: 3dc1c3f2    	ldr	q18, [sp, #0x700]
100007ff4: 4fd290a1    	fmul.2d	v1, v5, v18[0]
100007ff8: 4ea51ca4    	mov.16b	v4, v5
100007ffc: 4e61d400    	fadd.2d	v0, v0, v1
100008000: 3dc31fec    	ldr	q12, [sp, #0xc70]
100008004: 3dc1bfe5    	ldr	q5, [sp, #0x6f0]
100008008: 4fc59181    	fmul.2d	v1, v12, v5[0]
10000800c: 4e61d400    	fadd.2d	v0, v0, v1
100008010: 3dc1bbe3    	ldr	q3, [sp, #0x6e0]
100008014: 4fc39361    	fmul.2d	v1, v27, v3[0]
100008018: 4e61d400    	fadd.2d	v0, v0, v1
10000801c: 3dc1b3f8    	ldr	q24, [sp, #0x6c0]
100008020: 4fd89341    	fmul.2d	v1, v26, v24[0]
100008024: 4e61d400    	fadd.2d	v0, v0, v1
100008028: 3dc317fb    	ldr	q27, [sp, #0xc50]
10000802c: 3dc1b7f7    	ldr	q23, [sp, #0x6d0]
100008030: 4fd79361    	fmul.2d	v1, v27, v23[0]
100008034: 4e61d400    	fadd.2d	v0, v0, v1
100008038: 3dc1afed    	ldr	q13, [sp, #0x6b0]
10000803c: 4fcd93a1    	fmul.2d	v1, v29, v13[0]
100008040: 4e61d400    	fadd.2d	v0, v0, v1
100008044: 3dc2f7ef    	ldr	q15, [sp, #0xbd0]
100008048: 3dc1abfc    	ldr	q28, [sp, #0x6a0]
10000804c: 4fdc91e1    	fmul.2d	v1, v15, v28[0]
100008050: 4e61d400    	fadd.2d	v0, v0, v1
100008054: 3dc2f3e8    	ldr	q8, [sp, #0xbc0]
100008058: 3dc1a7e2    	ldr	q2, [sp, #0x690]
10000805c: 4fc29101    	fmul.2d	v1, v8, v2[0]
100008060: 4e61d400    	fadd.2d	v0, v0, v1
100008064: 3d8057e0    	str	q0, [sp, #0x150]
100008068: 3dc2afe0    	ldr	q0, [sp, #0xab0]
10000806c: 4fd09000    	fmul.2d	v0, v0, v16[0]
100008070: 3dc1cbfd    	ldr	q29, [sp, #0x720]
100008074: 3dc2abe1    	ldr	q1, [sp, #0xaa0]
100008078: 4fdd9021    	fmul.2d	v1, v1, v29[0]
10000807c: 4e61d400    	fadd.2d	v0, v0, v1
100008080: 3dc313e1    	ldr	q1, [sp, #0xc40]
100008084: 4fd29021    	fmul.2d	v1, v1, v18[0]
100008088: 4eb21e5a    	mov.16b	v26, v18
10000808c: 4e61d400    	fadd.2d	v0, v0, v1
100008090: 3dc2dbe1    	ldr	q1, [sp, #0xb60]
100008094: 4fc59021    	fmul.2d	v1, v1, v5[0]
100008098: 4e61d400    	fadd.2d	v0, v0, v1
10000809c: 3dc2e3e1    	ldr	q1, [sp, #0xb80]
1000080a0: 4fc39021    	fmul.2d	v1, v1, v3[0]
1000080a4: 4ea31c72    	mov.16b	v18, v3
1000080a8: 4e61d400    	fadd.2d	v0, v0, v1
1000080ac: 3dc30fe1    	ldr	q1, [sp, #0xc30]
1000080b0: 4fd89021    	fmul.2d	v1, v1, v24[0]
1000080b4: 4e61d400    	fadd.2d	v0, v0, v1
1000080b8: 3dc30be1    	ldr	q1, [sp, #0xc20]
1000080bc: 4fd79021    	fmul.2d	v1, v1, v23[0]
1000080c0: 4e61d400    	fadd.2d	v0, v0, v1
1000080c4: 4fcd9221    	fmul.2d	v1, v17, v13[0]
1000080c8: 4e61d400    	fadd.2d	v0, v0, v1
1000080cc: 4fdc9261    	fmul.2d	v1, v19, v28[0]
1000080d0: 4e61d400    	fadd.2d	v0, v0, v1
1000080d4: 4fc292c1    	fmul.2d	v1, v22, v2[0]
1000080d8: 4ea21c43    	mov.16b	v3, v2
1000080dc: 4e61d400    	fadd.2d	v0, v0, v1
1000080e0: 3d80c7e0    	str	q0, [sp, #0x310]
1000080e4: 4eb01e02    	mov.16b	v2, v16
1000080e8: 4fd09280    	fmul.2d	v0, v20, v16[0]
1000080ec: 4fdd92a1    	fmul.2d	v1, v21, v29[0]
1000080f0: 4e61d400    	fadd.2d	v0, v0, v1
1000080f4: 4eba1f50    	mov.16b	v16, v26
1000080f8: 3dc2cbe1    	ldr	q1, [sp, #0xb20]
1000080fc: 4fda9021    	fmul.2d	v1, v1, v26[0]
100008100: 4e61d400    	fadd.2d	v0, v0, v1
100008104: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
100008108: 4fc59021    	fmul.2d	v1, v1, v5[0]
10000810c: 4e61d400    	fadd.2d	v0, v0, v1
100008110: 3dc25fe1    	ldr	q1, [sp, #0x970]
100008114: 4fd29021    	fmul.2d	v1, v1, v18[0]
100008118: 4e61d400    	fadd.2d	v0, v0, v1
10000811c: 3dc2d7e1    	ldr	q1, [sp, #0xb50]
100008120: 4fd89021    	fmul.2d	v1, v1, v24[0]
100008124: 4e61d400    	fadd.2d	v0, v0, v1
100008128: 3dc2d3e1    	ldr	q1, [sp, #0xb40]
10000812c: 4fd79021    	fmul.2d	v1, v1, v23[0]
100008130: 4e61d400    	fadd.2d	v0, v0, v1
100008134: 4ead1db4    	mov.16b	v20, v13
100008138: 4fcd9121    	fmul.2d	v1, v9, v13[0]
10000813c: 4e61d400    	fadd.2d	v0, v0, v1
100008140: 3dc2cfe1    	ldr	q1, [sp, #0xb30]
100008144: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100008148: 4e61d400    	fadd.2d	v0, v0, v1
10000814c: 4fc39141    	fmul.2d	v1, v10, v3[0]
100008150: 4e61d400    	fadd.2d	v0, v0, v1
100008154: 3d80bfe0    	str	q0, [sp, #0x2f0]
100008158: 3dc273ea    	ldr	q10, [sp, #0x9c0]
10000815c: 4fc29140    	fmul.2d	v0, v10, v2[0]
100008160: 3dc26ffa    	ldr	q26, [sp, #0x9b0]
100008164: 4fdd9341    	fmul.2d	v1, v26, v29[0]
100008168: 4e61d400    	fadd.2d	v0, v0, v1
10000816c: 4fd090c1    	fmul.2d	v1, v6, v16[0]
100008170: 4e61d400    	fadd.2d	v0, v0, v1
100008174: 4fc590e1    	fmul.2d	v1, v7, v5[0]
100008178: 4e61d400    	fadd.2d	v0, v0, v1
10000817c: 3dc26bed    	ldr	q13, [sp, #0x9a0]
100008180: 4fd291a1    	fmul.2d	v1, v13, v18[0]
100008184: 4e61d400    	fadd.2d	v0, v0, v1
100008188: 4fd893c1    	fmul.2d	v1, v30, v24[0]
10000818c: 4e61d400    	fadd.2d	v0, v0, v1
100008190: 3dc297f5    	ldr	q21, [sp, #0xa50]
100008194: 4fd792a1    	fmul.2d	v1, v21, v23[0]
100008198: 4e61d400    	fadd.2d	v0, v0, v1
10000819c: 4fd493e1    	fmul.2d	v1, v31, v20[0]
1000081a0: 4e61d400    	fadd.2d	v0, v0, v1
1000081a4: 3dc293e9    	ldr	q9, [sp, #0xa40]
1000081a8: 4fdc9121    	fmul.2d	v1, v9, v28[0]
1000081ac: 4e61d400    	fadd.2d	v0, v0, v1
1000081b0: 3dc28ff6    	ldr	q22, [sp, #0xa30]
1000081b4: 4fc392c1    	fmul.2d	v1, v22, v3[0]
1000081b8: 4e61d400    	fadd.2d	v0, v0, v1
1000081bc: 3d8033e0    	str	q0, [sp, #0xc0]
1000081c0: 3dc19ff4    	ldr	q20, [sp, #0x670]
1000081c4: 6e74ddc0    	fmul.2d	v0, v14, v20
1000081c8: 6e004000    	ext.16b	v0, v0, v0, #0x8
1000081cc: 3dc303e1    	ldr	q1, [sp, #0xc00]
1000081d0: 6e74dc21    	fmul.2d	v1, v1, v20
1000081d4: 4e61d400    	fadd.2d	v0, v0, v1
1000081d8: 3dc19bf8    	ldr	q24, [sp, #0x660]
1000081dc: 4fd89081    	fmul.2d	v1, v4, v24[0]
1000081e0: 4e61d400    	fadd.2d	v0, v0, v1
1000081e4: 3dc197f9    	ldr	q25, [sp, #0x650]
1000081e8: 4fd99181    	fmul.2d	v1, v12, v25[0]
1000081ec: 4e61d400    	fadd.2d	v0, v0, v1
1000081f0: 3dc2ffe7    	ldr	q7, [sp, #0xbf0]
1000081f4: 3dc193e5    	ldr	q5, [sp, #0x640]
1000081f8: 4fc590e1    	fmul.2d	v1, v7, v5[0]
1000081fc: 4e61d400    	fadd.2d	v0, v0, v1
100008200: 3dc18fee    	ldr	q14, [sp, #0x630]
100008204: 3dc31be1    	ldr	q1, [sp, #0xc60]
100008208: 4fce9021    	fmul.2d	v1, v1, v14[0]
10000820c: 4e61d400    	fadd.2d	v0, v0, v1
100008210: 3dc18be4    	ldr	q4, [sp, #0x620]
100008214: 4fc49361    	fmul.2d	v1, v27, v4[0]
100008218: 4e61d400    	fadd.2d	v0, v0, v1
10000821c: 3dc187e6    	ldr	q6, [sp, #0x610]
100008220: 3dc2fbeb    	ldr	q11, [sp, #0xbe0]
100008224: 4fc69161    	fmul.2d	v1, v11, v6[0]
100008228: 4e61d400    	fadd.2d	v0, v0, v1
10000822c: 3dc183ec    	ldr	q12, [sp, #0x600]
100008230: 4fcc91e1    	fmul.2d	v1, v15, v12[0]
100008234: 4e61d400    	fadd.2d	v0, v0, v1
100008238: 3dc17ff7    	ldr	q23, [sp, #0x5f0]
10000823c: 4fd79101    	fmul.2d	v1, v8, v23[0]
100008240: 4e61d400    	fadd.2d	v0, v0, v1
100008244: 3d8053e0    	str	q0, [sp, #0x140]
100008248: 3dc2effc    	ldr	q28, [sp, #0xbb0]
10000824c: 4fd49380    	fmul.2d	v0, v28, v20[0]
100008250: 3dc2ebff    	ldr	q31, [sp, #0xba0]
100008254: 3dc1a3e2    	ldr	q2, [sp, #0x680]
100008258: 4fc293e1    	fmul.2d	v1, v31, v2[0]
10000825c: 4e61d400    	fadd.2d	v0, v0, v1
100008260: 3dc28bfd    	ldr	q29, [sp, #0xa20]
100008264: 4fd893a1    	fmul.2d	v1, v29, v24[0]
100008268: 4e61d400    	fadd.2d	v0, v0, v1
10000826c: 3dc287f2    	ldr	q18, [sp, #0xa10]
100008270: 4fd99241    	fmul.2d	v1, v18, v25[0]
100008274: 4e61d400    	fadd.2d	v0, v0, v1
100008278: 4ea51cb3    	mov.16b	v19, v5
10000827c: 3dc267e1    	ldr	q1, [sp, #0x990]
100008280: 4fc59021    	fmul.2d	v1, v1, v5[0]
100008284: 4e61d400    	fadd.2d	v0, v0, v1
100008288: 3dc2e7e1    	ldr	q1, [sp, #0xb90]
10000828c: 4fce9021    	fmul.2d	v1, v1, v14[0]
100008290: 4e61d400    	fadd.2d	v0, v0, v1
100008294: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
100008298: 4fc49021    	fmul.2d	v1, v1, v4[0]
10000829c: 4ea41c8f    	mov.16b	v15, v4
1000082a0: 4e61d400    	fadd.2d	v0, v0, v1
1000082a4: 3dc283e1    	ldr	q1, [sp, #0xa00]
1000082a8: 4fc69021    	fmul.2d	v1, v1, v6[0]
1000082ac: 4e61d400    	fadd.2d	v0, v0, v1
1000082b0: 3dc263f1    	ldr	q17, [sp, #0x980]
1000082b4: 4fcc9221    	fmul.2d	v1, v17, v12[0]
1000082b8: 4e61d400    	fadd.2d	v0, v0, v1
1000082bc: 4eb71efe    	mov.16b	v30, v23
1000082c0: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
1000082c4: 4fd79021    	fmul.2d	v1, v1, v23[0]
1000082c8: 4e61d400    	fadd.2d	v0, v0, v1
1000082cc: 3d804fe0    	str	q0, [sp, #0x130]
1000082d0: 3dc2dfe0    	ldr	q0, [sp, #0xb70]
1000082d4: 4fd49000    	fmul.2d	v0, v0, v20[0]
1000082d8: 3dc2a7e1    	ldr	q1, [sp, #0xa90]
1000082dc: 4fc29021    	fmul.2d	v1, v1, v2[0]
1000082e0: 4e61d400    	fadd.2d	v0, v0, v1
1000082e4: 3dc2cbf7    	ldr	q23, [sp, #0xb20]
1000082e8: 4eb81f04    	mov.16b	v4, v24
1000082ec: 4fd892e1    	fmul.2d	v1, v23, v24[0]
1000082f0: 4e61d400    	fadd.2d	v0, v0, v1
1000082f4: 3dc27ff8    	ldr	q24, [sp, #0x9f0]
1000082f8: 4eb91f25    	mov.16b	v5, v25
1000082fc: 4fd99301    	fmul.2d	v1, v24, v25[0]
100008300: 4e61d400    	fadd.2d	v0, v0, v1
100008304: 3dc25ff9    	ldr	q25, [sp, #0x970]
100008308: 4fd39321    	fmul.2d	v1, v25, v19[0]
10000830c: 4eb31e63    	mov.16b	v3, v19
100008310: 4e61d400    	fadd.2d	v0, v0, v1
100008314: 3dc2d7fb    	ldr	q27, [sp, #0xb50]
100008318: 4eae1dd0    	mov.16b	v16, v14
10000831c: 4fce9361    	fmul.2d	v1, v27, v14[0]
100008320: 4e61d400    	fadd.2d	v0, v0, v1
100008324: 3dc2d3ee    	ldr	q14, [sp, #0xb40]
100008328: 4eaf1df3    	mov.16b	v19, v15
10000832c: 4fcf91c1    	fmul.2d	v1, v14, v15[0]
100008330: 4e61d400    	fadd.2d	v0, v0, v1
100008334: 3dc29fe1    	ldr	q1, [sp, #0xa70]
100008338: 4fc69021    	fmul.2d	v1, v1, v6[0]
10000833c: 4e61d400    	fadd.2d	v0, v0, v1
100008340: 3dc2cfef    	ldr	q15, [sp, #0xb30]
100008344: 4fcc91e1    	fmul.2d	v1, v15, v12[0]
100008348: 4e61d400    	fadd.2d	v0, v0, v1
10000834c: 3dc27be8    	ldr	q8, [sp, #0x9e0]
100008350: 4fde9101    	fmul.2d	v1, v8, v30[0]
100008354: 4e61d400    	fadd.2d	v0, v0, v1
100008358: 3d8087e0    	str	q0, [sp, #0x210]
10000835c: 4fd49140    	fmul.2d	v0, v10, v20[0]
100008360: 4fc29341    	fmul.2d	v1, v26, v2[0]
100008364: 4e61d400    	fadd.2d	v0, v0, v1
100008368: 3dc29be1    	ldr	q1, [sp, #0xa60]
10000836c: 4fc49021    	fmul.2d	v1, v1, v4[0]
100008370: 4e61d400    	fadd.2d	v0, v0, v1
100008374: 3dc2c7e1    	ldr	q1, [sp, #0xb10]
100008378: 4fc59021    	fmul.2d	v1, v1, v5[0]
10000837c: 4e61d400    	fadd.2d	v0, v0, v1
100008380: 4fc391a1    	fmul.2d	v1, v13, v3[0]
100008384: 4e61d400    	fadd.2d	v0, v0, v1
100008388: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
10000838c: 4fd09021    	fmul.2d	v1, v1, v16[0]
100008390: 4e61d400    	fadd.2d	v0, v0, v1
100008394: 4fd392a1    	fmul.2d	v1, v21, v19[0]
100008398: 4e61d400    	fadd.2d	v0, v0, v1
10000839c: 3dc2bfe1    	ldr	q1, [sp, #0xaf0]
1000083a0: 4fc69021    	fmul.2d	v1, v1, v6[0]
1000083a4: 4e61d400    	fadd.2d	v0, v0, v1
1000083a8: 4fcc9121    	fmul.2d	v1, v9, v12[0]
1000083ac: 4e61d400    	fadd.2d	v0, v0, v1
1000083b0: 4fde92c1    	fmul.2d	v1, v22, v30[0]
1000083b4: 4e61d400    	fadd.2d	v0, v0, v1
1000083b8: 3d80b3e0    	str	q0, [sp, #0x2c0]
1000083bc: 3dc173e6    	ldr	q6, [sp, #0x5c0]
1000083c0: 3dc307e0    	ldr	q0, [sp, #0xc10]
1000083c4: 6e66dc00    	fmul.2d	v0, v0, v6
1000083c8: 6e004000    	ext.16b	v0, v0, v0, #0x8
1000083cc: 3dc303f3    	ldr	q19, [sp, #0xc00]
1000083d0: 6e66de61    	fmul.2d	v1, v19, v6
1000083d4: 4e61d400    	fadd.2d	v0, v0, v1
1000083d8: 3dc16ffe    	ldr	q30, [sp, #0x5b0]
1000083dc: 3dc2b3f4    	ldr	q20, [sp, #0xac0]
1000083e0: 4fde9281    	fmul.2d	v1, v20, v30[0]
1000083e4: 4e61d400    	fadd.2d	v0, v0, v1
1000083e8: 3dc16be4    	ldr	q4, [sp, #0x5a0]
1000083ec: 3dc31fe1    	ldr	q1, [sp, #0xc70]
1000083f0: 4fc49021    	fmul.2d	v1, v1, v4[0]
1000083f4: 4e61d400    	fadd.2d	v0, v0, v1
1000083f8: 3dc167e5    	ldr	q5, [sp, #0x590]
1000083fc: 4fc590e1    	fmul.2d	v1, v7, v5[0]
100008400: 4e61d400    	fadd.2d	v0, v0, v1
100008404: 3dc31bf0    	ldr	q16, [sp, #0xc60]
100008408: 3dc163e2    	ldr	q2, [sp, #0x580]
10000840c: 4fc29201    	fmul.2d	v1, v16, v2[0]
100008410: 4e61d400    	fadd.2d	v0, v0, v1
100008414: 3dc15fec    	ldr	q12, [sp, #0x570]
100008418: 3dc317e1    	ldr	q1, [sp, #0xc50]
10000841c: 4fcc9021    	fmul.2d	v1, v1, v12[0]
100008420: 4e61d400    	fadd.2d	v0, v0, v1
100008424: 3dc15bed    	ldr	q13, [sp, #0x560]
100008428: 4fcd9161    	fmul.2d	v1, v11, v13[0]
10000842c: 4e61d400    	fadd.2d	v0, v0, v1
100008430: 3dc157eb    	ldr	q11, [sp, #0x550]
100008434: 3dc2f7f5    	ldr	q21, [sp, #0xbd0]
100008438: 4fcb92a1    	fmul.2d	v1, v21, v11[0]
10000843c: 4e61d400    	fadd.2d	v0, v0, v1
100008440: 3dc153e3    	ldr	q3, [sp, #0x540]
100008444: 3dc2f3ea    	ldr	q10, [sp, #0xbc0]
100008448: 4fc39141    	fmul.2d	v1, v10, v3[0]
10000844c: 4e61d400    	fadd.2d	v0, v0, v1
100008450: 3d804be0    	str	q0, [sp, #0x120]
100008454: 4fc69380    	fmul.2d	v0, v28, v6[0]
100008458: 3dc177fa    	ldr	q26, [sp, #0x5d0]
10000845c: 4fda93e1    	fmul.2d	v1, v31, v26[0]
100008460: 4e61d400    	fadd.2d	v0, v0, v1
100008464: 4fde93a1    	fmul.2d	v1, v29, v30[0]
100008468: 4e61d400    	fadd.2d	v0, v0, v1
10000846c: 4fc49241    	fmul.2d	v1, v18, v4[0]
100008470: 4ea41c9c    	mov.16b	v28, v4
100008474: 4e61d400    	fadd.2d	v0, v0, v1
100008478: 3dc267e1    	ldr	q1, [sp, #0x990]
10000847c: 4fc59021    	fmul.2d	v1, v1, v5[0]
100008480: 4ea51cbd    	mov.16b	v29, v5
100008484: 4e61d400    	fadd.2d	v0, v0, v1
100008488: 3dc2e7e7    	ldr	q7, [sp, #0xb90]
10000848c: 4fc290e1    	fmul.2d	v1, v7, v2[0]
100008490: 4e61d400    	fadd.2d	v0, v0, v1
100008494: 3dc2bbf2    	ldr	q18, [sp, #0xae0]
100008498: 4fcc9241    	fmul.2d	v1, v18, v12[0]
10000849c: 4e61d400    	fadd.2d	v0, v0, v1
1000084a0: 3dc283f6    	ldr	q22, [sp, #0xa00]
1000084a4: 4fcd92c1    	fmul.2d	v1, v22, v13[0]
1000084a8: 4e61d400    	fadd.2d	v0, v0, v1
1000084ac: 4fcb9221    	fmul.2d	v1, v17, v11[0]
1000084b0: 4eab1d7f    	mov.16b	v31, v11
1000084b4: 4e61d400    	fadd.2d	v0, v0, v1
1000084b8: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
1000084bc: 4fc39021    	fmul.2d	v1, v1, v3[0]
1000084c0: 4e61d400    	fadd.2d	v0, v0, v1
1000084c4: 3d802fe0    	str	q0, [sp, #0xb0]
1000084c8: 3dc2dfe0    	ldr	q0, [sp, #0xb70]
1000084cc: 4fc69000    	fmul.2d	v0, v0, v6[0]
1000084d0: 3dc2a7e1    	ldr	q1, [sp, #0xa90]
1000084d4: 4fda9021    	fmul.2d	v1, v1, v26[0]
1000084d8: 4eba1f4b    	mov.16b	v11, v26
1000084dc: 4e61d400    	fadd.2d	v0, v0, v1
1000084e0: 4fde92e1    	fmul.2d	v1, v23, v30[0]
1000084e4: 4e61d400    	fadd.2d	v0, v0, v1
1000084e8: 4fdc9301    	fmul.2d	v1, v24, v28[0]
1000084ec: 4e61d400    	fadd.2d	v0, v0, v1
1000084f0: 4fc59321    	fmul.2d	v1, v25, v5[0]
1000084f4: 4e61d400    	fadd.2d	v0, v0, v1
1000084f8: 4fc29361    	fmul.2d	v1, v27, v2[0]
1000084fc: 4e61d400    	fadd.2d	v0, v0, v1
100008500: 4fcc91c1    	fmul.2d	v1, v14, v12[0]
100008504: 4e61d400    	fadd.2d	v0, v0, v1
100008508: 3dc29fe1    	ldr	q1, [sp, #0xa70]
10000850c: 4fcd9021    	fmul.2d	v1, v1, v13[0]
100008510: 4e61d400    	fadd.2d	v0, v0, v1
100008514: 4fdf91e1    	fmul.2d	v1, v15, v31[0]
100008518: 4e61d400    	fadd.2d	v0, v0, v1
10000851c: 4fc39101    	fmul.2d	v1, v8, v3[0]
100008520: 4e61d400    	fadd.2d	v0, v0, v1
100008524: 3d8083e0    	str	q0, [sp, #0x200]
100008528: 3dc273e9    	ldr	q9, [sp, #0x9c0]
10000852c: 4fc69120    	fmul.2d	v0, v9, v6[0]
100008530: 3dc26ff7    	ldr	q23, [sp, #0x9b0]
100008534: 4fcb92e1    	fmul.2d	v1, v23, v11[0]
100008538: 4e61d400    	fadd.2d	v0, v0, v1
10000853c: 3dc29be5    	ldr	q5, [sp, #0xa60]
100008540: 4fde90a1    	fmul.2d	v1, v5, v30[0]
100008544: 4e61d400    	fadd.2d	v0, v0, v1
100008548: 3dc2c7f9    	ldr	q25, [sp, #0xb10]
10000854c: 4fdc9321    	fmul.2d	v1, v25, v28[0]
100008550: 4e61d400    	fadd.2d	v0, v0, v1
100008554: 3dc26bfa    	ldr	q26, [sp, #0x9a0]
100008558: 4fdd9341    	fmul.2d	v1, v26, v29[0]
10000855c: 4e61d400    	fadd.2d	v0, v0, v1
100008560: 3dc2c3fb    	ldr	q27, [sp, #0xb00]
100008564: 4fc29361    	fmul.2d	v1, v27, v2[0]
100008568: 4e61d400    	fadd.2d	v0, v0, v1
10000856c: 3dc297e8    	ldr	q8, [sp, #0xa50]
100008570: 4fcc9101    	fmul.2d	v1, v8, v12[0]
100008574: 4e61d400    	fadd.2d	v0, v0, v1
100008578: 3dc2bfee    	ldr	q14, [sp, #0xaf0]
10000857c: 4fcd91c1    	fmul.2d	v1, v14, v13[0]
100008580: 4e61d400    	fadd.2d	v0, v0, v1
100008584: 3dc293e1    	ldr	q1, [sp, #0xa40]
100008588: 4fdf9021    	fmul.2d	v1, v1, v31[0]
10000858c: 4e61d400    	fadd.2d	v0, v0, v1
100008590: 3dc28fe1    	ldr	q1, [sp, #0xa30]
100008594: 4fc39021    	fmul.2d	v1, v1, v3[0]
100008598: 4e61d400    	fadd.2d	v0, v0, v1
10000859c: 3d807fe0    	str	q0, [sp, #0x1f0]
1000085a0: 3dc14be4    	ldr	q4, [sp, #0x520]
1000085a4: 3dc307e2    	ldr	q2, [sp, #0xc10]
1000085a8: 6e64dc40    	fmul.2d	v0, v2, v4
1000085ac: 6e004000    	ext.16b	v0, v0, v0, #0x8
1000085b0: 6e64de61    	fmul.2d	v1, v19, v4
1000085b4: 4e61d400    	fadd.2d	v0, v0, v1
1000085b8: 3dc147ff    	ldr	q31, [sp, #0x510]
1000085bc: 4fdf9281    	fmul.2d	v1, v20, v31[0]
1000085c0: 4e61d400    	fadd.2d	v0, v0, v1
1000085c4: 3dc143f8    	ldr	q24, [sp, #0x500]
1000085c8: 3dc31fe1    	ldr	q1, [sp, #0xc70]
1000085cc: 4fd89021    	fmul.2d	v1, v1, v24[0]
1000085d0: 4e61d400    	fadd.2d	v0, v0, v1
1000085d4: 3dc13ff3    	ldr	q19, [sp, #0x4f0]
1000085d8: 3dc2ffe1    	ldr	q1, [sp, #0xbf0]
1000085dc: 4fd39021    	fmul.2d	v1, v1, v19[0]
1000085e0: 4e61d400    	fadd.2d	v0, v0, v1
1000085e4: 3dc13beb    	ldr	q11, [sp, #0x4e0]
1000085e8: 4fcb9201    	fmul.2d	v1, v16, v11[0]
1000085ec: 4e61d400    	fadd.2d	v0, v0, v1
1000085f0: 3dc317f1    	ldr	q17, [sp, #0xc50]
1000085f4: 3dc137f4    	ldr	q20, [sp, #0x4d0]
1000085f8: 4fd49221    	fmul.2d	v1, v17, v20[0]
1000085fc: 4e61d400    	fadd.2d	v0, v0, v1
100008600: 3dc133ec    	ldr	q12, [sp, #0x4c0]
100008604: 3dc2fbe1    	ldr	q1, [sp, #0xbe0]
100008608: 4fcc9021    	fmul.2d	v1, v1, v12[0]
10000860c: 4e61d400    	fadd.2d	v0, v0, v1
100008610: 3dc12fed    	ldr	q13, [sp, #0x4b0]
100008614: 4fcd92a1    	fmul.2d	v1, v21, v13[0]
100008618: 4e61d400    	fadd.2d	v0, v0, v1
10000861c: 3dc12bfe    	ldr	q30, [sp, #0x4a0]
100008620: 4fde9141    	fmul.2d	v1, v10, v30[0]
100008624: 4e61d400    	fadd.2d	v0, v0, v1
100008628: 3d80cbe0    	str	q0, [sp, #0x320]
10000862c: 3dc2efe0    	ldr	q0, [sp, #0xbb0]
100008630: 4fc49000    	fmul.2d	v0, v0, v4[0]
100008634: 3dc14ff0    	ldr	q16, [sp, #0x530]
100008638: 3dc2ebe1    	ldr	q1, [sp, #0xba0]
10000863c: 4fd09021    	fmul.2d	v1, v1, v16[0]
100008640: 4e61d400    	fadd.2d	v0, v0, v1
100008644: 3dc28be1    	ldr	q1, [sp, #0xa20]
100008648: 4fdf9021    	fmul.2d	v1, v1, v31[0]
10000864c: 4e61d400    	fadd.2d	v0, v0, v1
100008650: 3dc287e1    	ldr	q1, [sp, #0xa10]
100008654: 4fd89021    	fmul.2d	v1, v1, v24[0]
100008658: 4e61d400    	fadd.2d	v0, v0, v1
10000865c: 3dc267ef    	ldr	q15, [sp, #0x990]
100008660: 4fd391e1    	fmul.2d	v1, v15, v19[0]
100008664: 4e61d400    	fadd.2d	v0, v0, v1
100008668: 4eab1d63    	mov.16b	v3, v11
10000866c: 4fcb90e1    	fmul.2d	v1, v7, v11[0]
100008670: 4e61d400    	fadd.2d	v0, v0, v1
100008674: 4fd49241    	fmul.2d	v1, v18, v20[0]
100008678: 4e61d400    	fadd.2d	v0, v0, v1
10000867c: 4fcc92c1    	fmul.2d	v1, v22, v12[0]
100008680: 4e61d400    	fadd.2d	v0, v0, v1
100008684: 3dc263fc    	ldr	q28, [sp, #0x980]
100008688: 4fcd9381    	fmul.2d	v1, v28, v13[0]
10000868c: 4e61d400    	fadd.2d	v0, v0, v1
100008690: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
100008694: 4fde9021    	fmul.2d	v1, v1, v30[0]
100008698: 4e61d400    	fadd.2d	v0, v0, v1
10000869c: 3d80c3e0    	str	q0, [sp, #0x300]
1000086a0: 3dc2aff6    	ldr	q22, [sp, #0xab0]
1000086a4: 4fc492c0    	fmul.2d	v0, v22, v4[0]
1000086a8: 3dc2abf2    	ldr	q18, [sp, #0xaa0]
1000086ac: 4fd09241    	fmul.2d	v1, v18, v16[0]
1000086b0: 4e61d400    	fadd.2d	v0, v0, v1
1000086b4: 3dc313fd    	ldr	q29, [sp, #0xc40]
1000086b8: 4fdf93a1    	fmul.2d	v1, v29, v31[0]
1000086bc: 4e61d400    	fadd.2d	v0, v0, v1
1000086c0: 3dc2dbf5    	ldr	q21, [sp, #0xb60]
1000086c4: 4eb81f07    	mov.16b	v7, v24
1000086c8: 4fd892a1    	fmul.2d	v1, v21, v24[0]
1000086cc: 4e61d400    	fadd.2d	v0, v0, v1
1000086d0: 3dc2e3e1    	ldr	q1, [sp, #0xb80]
1000086d4: 4fd39021    	fmul.2d	v1, v1, v19[0]
1000086d8: 4e61d400    	fadd.2d	v0, v0, v1
1000086dc: 3dc30fe1    	ldr	q1, [sp, #0xc30]
1000086e0: 4fc39021    	fmul.2d	v1, v1, v3[0]
1000086e4: 4e61d400    	fadd.2d	v0, v0, v1
1000086e8: 3dc30be1    	ldr	q1, [sp, #0xc20]
1000086ec: 4fd49021    	fmul.2d	v1, v1, v20[0]
1000086f0: 4e61d400    	fadd.2d	v0, v0, v1
1000086f4: 3dc2a3e1    	ldr	q1, [sp, #0xa80]
1000086f8: 4fcc9021    	fmul.2d	v1, v1, v12[0]
1000086fc: 4e61d400    	fadd.2d	v0, v0, v1
100008700: 3dc277e1    	ldr	q1, [sp, #0x9d0]
100008704: 4fcd9021    	fmul.2d	v1, v1, v13[0]
100008708: 4e61d400    	fadd.2d	v0, v0, v1
10000870c: 3dc25be6    	ldr	q6, [sp, #0x960]
100008710: 4fde90c1    	fmul.2d	v1, v6, v30[0]
100008714: 4e61d400    	fadd.2d	v0, v0, v1
100008718: 3d823be0    	str	q0, [sp, #0x8e0]
10000871c: 4fc49120    	fmul.2d	v0, v9, v4[0]
100008720: 4fd092e1    	fmul.2d	v1, v23, v16[0]
100008724: 4e61d400    	fadd.2d	v0, v0, v1
100008728: 4fdf90a1    	fmul.2d	v1, v5, v31[0]
10000872c: 4ea51cb8    	mov.16b	v24, v5
100008730: 4e61d400    	fadd.2d	v0, v0, v1
100008734: 4fc79321    	fmul.2d	v1, v25, v7[0]
100008738: 4e61d400    	fadd.2d	v0, v0, v1
10000873c: 4fd39341    	fmul.2d	v1, v26, v19[0]
100008740: 4e61d400    	fadd.2d	v0, v0, v1
100008744: 4fc39361    	fmul.2d	v1, v27, v3[0]
100008748: 4e61d400    	fadd.2d	v0, v0, v1
10000874c: 4fd49101    	fmul.2d	v1, v8, v20[0]
100008750: 4e61d400    	fadd.2d	v0, v0, v1
100008754: 4fcc91c1    	fmul.2d	v1, v14, v12[0]
100008758: 4e61d400    	fadd.2d	v0, v0, v1
10000875c: 3dc293e4    	ldr	q4, [sp, #0xa40]
100008760: 4fcd9081    	fmul.2d	v1, v4, v13[0]
100008764: 4e61d400    	fadd.2d	v0, v0, v1
100008768: 3dc28fe3    	ldr	q3, [sp, #0xa30]
10000876c: 4fde9061    	fmul.2d	v1, v3, v30[0]
100008770: 4e61d400    	fadd.2d	v0, v0, v1
100008774: 3d807be0    	str	q0, [sp, #0x1e0]
100008778: 3dc123f0    	ldr	q16, [sp, #0x480]
10000877c: 6e70dc40    	fmul.2d	v0, v2, v16
100008780: 6e004000    	ext.16b	v0, v0, v0, #0x8
100008784: 3dc303e1    	ldr	q1, [sp, #0xc00]
100008788: 6e70dc21    	fmul.2d	v1, v1, v16
10000878c: 4e61d400    	fadd.2d	v0, v0, v1
100008790: 3dc11fff    	ldr	q31, [sp, #0x470]
100008794: 3dc2b3f7    	ldr	q23, [sp, #0xac0]
100008798: 4fdf92e1    	fmul.2d	v1, v23, v31[0]
10000879c: 4e61d400    	fadd.2d	v0, v0, v1
1000087a0: 3dc11be8    	ldr	q8, [sp, #0x460]
1000087a4: 3dc31ff9    	ldr	q25, [sp, #0xc70]
1000087a8: 4fc89321    	fmul.2d	v1, v25, v8[0]
1000087ac: 4e61d400    	fadd.2d	v0, v0, v1
1000087b0: 3dc117fe    	ldr	q30, [sp, #0x450]
1000087b4: 3dc2ffe7    	ldr	q7, [sp, #0xbf0]
1000087b8: 4fde90e1    	fmul.2d	v1, v7, v30[0]
1000087bc: 4e61d400    	fadd.2d	v0, v0, v1
1000087c0: 3dc10fec    	ldr	q12, [sp, #0x430]
1000087c4: 3dc31be1    	ldr	q1, [sp, #0xc60]
1000087c8: 4fcc9021    	fmul.2d	v1, v1, v12[0]
1000087cc: 4e61d400    	fadd.2d	v0, v0, v1
1000087d0: 3dc113e2    	ldr	q2, [sp, #0x440]
1000087d4: 4fc29221    	fmul.2d	v1, v17, v2[0]
1000087d8: 4e61d400    	fadd.2d	v0, v0, v1
1000087dc: 3dc2fbf3    	ldr	q19, [sp, #0xbe0]
1000087e0: 3dc10bed    	ldr	q13, [sp, #0x420]
1000087e4: 4fcd9261    	fmul.2d	v1, v19, v13[0]
1000087e8: 4e61d400    	fadd.2d	v0, v0, v1
1000087ec: 3dc107f1    	ldr	q17, [sp, #0x410]
1000087f0: 3dc2f7e1    	ldr	q1, [sp, #0xbd0]
1000087f4: 4fd19021    	fmul.2d	v1, v1, v17[0]
1000087f8: 4e61d400    	fadd.2d	v0, v0, v1
1000087fc: 3dc103f4    	ldr	q20, [sp, #0x400]
100008800: 3dc2f3e1    	ldr	q1, [sp, #0xbc0]
100008804: 4fd49021    	fmul.2d	v1, v1, v20[0]
100008808: 4e61d400    	fadd.2d	v0, v0, v1
10000880c: 3d80bbe0    	str	q0, [sp, #0x2e0]
100008810: 3dc2efe0    	ldr	q0, [sp, #0xbb0]
100008814: 4fd09000    	fmul.2d	v0, v0, v16[0]
100008818: 3dc127ea    	ldr	q10, [sp, #0x490]
10000881c: 3dc2ebe1    	ldr	q1, [sp, #0xba0]
100008820: 4fca9021    	fmul.2d	v1, v1, v10[0]
100008824: 4e61d400    	fadd.2d	v0, v0, v1
100008828: 3dc28be1    	ldr	q1, [sp, #0xa20]
10000882c: 4fdf9021    	fmul.2d	v1, v1, v31[0]
100008830: 4e61d400    	fadd.2d	v0, v0, v1
100008834: 3dc287e1    	ldr	q1, [sp, #0xa10]
100008838: 4fc89021    	fmul.2d	v1, v1, v8[0]
10000883c: 4e61d400    	fadd.2d	v0, v0, v1
100008840: 4fde91e1    	fmul.2d	v1, v15, v30[0]
100008844: 4e61d400    	fadd.2d	v0, v0, v1
100008848: 3dc2e7e1    	ldr	q1, [sp, #0xb90]
10000884c: 4fcc9021    	fmul.2d	v1, v1, v12[0]
100008850: 4e61d400    	fadd.2d	v0, v0, v1
100008854: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
100008858: 4fc29021    	fmul.2d	v1, v1, v2[0]
10000885c: 4e61d400    	fadd.2d	v0, v0, v1
100008860: 3dc283e1    	ldr	q1, [sp, #0xa00]
100008864: 4fcd9021    	fmul.2d	v1, v1, v13[0]
100008868: 4e61d400    	fadd.2d	v0, v0, v1
10000886c: 4fd19381    	fmul.2d	v1, v28, v17[0]
100008870: 4e61d400    	fadd.2d	v0, v0, v1
100008874: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
100008878: 4fd49021    	fmul.2d	v1, v1, v20[0]
10000887c: 4e61d400    	fadd.2d	v0, v0, v1
100008880: 3d80b7e0    	str	q0, [sp, #0x2d0]
100008884: 4fd092c0    	fmul.2d	v0, v22, v16[0]
100008888: 4eb61ecb    	mov.16b	v11, v22
10000888c: 4fca9241    	fmul.2d	v1, v18, v10[0]
100008890: 4eaa1d56    	mov.16b	v22, v10
100008894: 4e61d400    	fadd.2d	v0, v0, v1
100008898: 4fdf93a1    	fmul.2d	v1, v29, v31[0]
10000889c: 4e61d400    	fadd.2d	v0, v0, v1
1000088a0: 4fc892a1    	fmul.2d	v1, v21, v8[0]
1000088a4: 4eb51eaa    	mov.16b	v10, v21
1000088a8: 4e61d400    	fadd.2d	v0, v0, v1
1000088ac: 3dc2e3e9    	ldr	q9, [sp, #0xb80]
1000088b0: 4ebe1fc5    	mov.16b	v5, v30
1000088b4: 4fde9121    	fmul.2d	v1, v9, v30[0]
1000088b8: 4e61d400    	fadd.2d	v0, v0, v1
1000088bc: 3dc30ff2    	ldr	q18, [sp, #0xc30]
1000088c0: 4fcc9241    	fmul.2d	v1, v18, v12[0]
1000088c4: 4e61d400    	fadd.2d	v0, v0, v1
1000088c8: 3dc30bfd    	ldr	q29, [sp, #0xc20]
1000088cc: 4fc293a1    	fmul.2d	v1, v29, v2[0]
1000088d0: 4e61d400    	fadd.2d	v0, v0, v1
1000088d4: 3dc2a3e1    	ldr	q1, [sp, #0xa80]
1000088d8: 4fcd9021    	fmul.2d	v1, v1, v13[0]
1000088dc: 4e61d400    	fadd.2d	v0, v0, v1
1000088e0: 3dc277fe    	ldr	q30, [sp, #0x9d0]
1000088e4: 4fd193c1    	fmul.2d	v1, v30, v17[0]
1000088e8: 4e61d400    	fadd.2d	v0, v0, v1
1000088ec: 4fd490c1    	fmul.2d	v1, v6, v20[0]
1000088f0: 4e61d400    	fadd.2d	v0, v0, v1
1000088f4: 3d824fe0    	str	q0, [sp, #0x930]
1000088f8: 3dc273e0    	ldr	q0, [sp, #0x9c0]
1000088fc: 4fd09000    	fmul.2d	v0, v0, v16[0]
100008900: 3dc26fe1    	ldr	q1, [sp, #0x9b0]
100008904: 4fd69021    	fmul.2d	v1, v1, v22[0]
100008908: 4e61d400    	fadd.2d	v0, v0, v1
10000890c: 4fdf9301    	fmul.2d	v1, v24, v31[0]
100008910: 4e61d400    	fadd.2d	v0, v0, v1
100008914: 3dc2c7e1    	ldr	q1, [sp, #0xb10]
100008918: 4fc89021    	fmul.2d	v1, v1, v8[0]
10000891c: 4e61d400    	fadd.2d	v0, v0, v1
100008920: 4fc59341    	fmul.2d	v1, v26, v5[0]
100008924: 4e61d400    	fadd.2d	v0, v0, v1
100008928: 4fcc9361    	fmul.2d	v1, v27, v12[0]
10000892c: 4e61d400    	fadd.2d	v0, v0, v1
100008930: 3dc297e1    	ldr	q1, [sp, #0xa50]
100008934: 4fc29021    	fmul.2d	v1, v1, v2[0]
100008938: 4e61d400    	fadd.2d	v0, v0, v1
10000893c: 4fcd91c1    	fmul.2d	v1, v14, v13[0]
100008940: 4e61d400    	fadd.2d	v0, v0, v1
100008944: 4fd19081    	fmul.2d	v1, v4, v17[0]
100008948: 4e61d400    	fadd.2d	v0, v0, v1
10000894c: 4fd49061    	fmul.2d	v1, v3, v20[0]
100008950: 4e61d400    	fadd.2d	v0, v0, v1
100008954: 3d8077e0    	str	q0, [sp, #0x1d0]
100008958: 3dc307f6    	ldr	q22, [sp, #0xc10]
10000895c: ad5e9be2    	ldp	q2, q6, [sp, #0x3d0]
100008960: 6e66dec0    	fmul.2d	v0, v22, v6
100008964: 6e004000    	ext.16b	v0, v0, v0, #0x8
100008968: 3dc303f8    	ldr	q24, [sp, #0xc00]
10000896c: 6e66df01    	fmul.2d	v1, v24, v6
100008970: 4e61d400    	fadd.2d	v0, v0, v1
100008974: 4fc292e1    	fmul.2d	v1, v23, v2[0]
100008978: 4e61d400    	fadd.2d	v0, v0, v1
10000897c: ad5db3ed    	ldp	q13, q12, [sp, #0x3b0]
100008980: 4fcc9321    	fmul.2d	v1, v25, v12[0]
100008984: 4e61d400    	fadd.2d	v0, v0, v1
100008988: 4fcd90e1    	fmul.2d	v1, v7, v13[0]
10000898c: 4e61d400    	fadd.2d	v0, v0, v1
100008990: ad5c8fff    	ldp	q31, q3, [sp, #0x390]
100008994: 3dc31be1    	ldr	q1, [sp, #0xc60]
100008998: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000899c: 4e61d400    	fadd.2d	v0, v0, v1
1000089a0: 3dc317e1    	ldr	q1, [sp, #0xc50]
1000089a4: 4fdf9021    	fmul.2d	v1, v1, v31[0]
1000089a8: 4e61d400    	fadd.2d	v0, v0, v1
1000089ac: ad5bc3e8    	ldp	q8, q16, [sp, #0x370]
1000089b0: 4fd09261    	fmul.2d	v1, v19, v16[0]
1000089b4: 4e61d400    	fadd.2d	v0, v0, v1
1000089b8: 3dc2f7f4    	ldr	q20, [sp, #0xbd0]
1000089bc: 4fc89281    	fmul.2d	v1, v20, v8[0]
1000089c0: 4e61d400    	fadd.2d	v0, v0, v1
1000089c4: 3dc2f3f5    	ldr	q21, [sp, #0xbc0]
1000089c8: 3dc0dbf3    	ldr	q19, [sp, #0x360]
1000089cc: 4fd392a1    	fmul.2d	v1, v21, v19[0]
1000089d0: 4e61d400    	fadd.2d	v0, v0, v1
1000089d4: 3d80afe0    	str	q0, [sp, #0x2b0]
1000089d8: 3dc2eff7    	ldr	q23, [sp, #0xbb0]
1000089dc: 4fc692e0    	fmul.2d	v0, v23, v6[0]
1000089e0: 3dc2ebf9    	ldr	q25, [sp, #0xba0]
1000089e4: 3dc0ffe7    	ldr	q7, [sp, #0x3f0]
1000089e8: 4fc79321    	fmul.2d	v1, v25, v7[0]
1000089ec: 4e61d400    	fadd.2d	v0, v0, v1
1000089f0: 3dc28bfb    	ldr	q27, [sp, #0xa20]
1000089f4: 4fc29361    	fmul.2d	v1, v27, v2[0]
1000089f8: 4e61d400    	fadd.2d	v0, v0, v1
1000089fc: 3dc287ee    	ldr	q14, [sp, #0xa10]
100008a00: 4fcc91c1    	fmul.2d	v1, v14, v12[0]
100008a04: 4e61d400    	fadd.2d	v0, v0, v1
100008a08: 4fcd91e1    	fmul.2d	v1, v15, v13[0]
100008a0c: 4e61d400    	fadd.2d	v0, v0, v1
100008a10: 3dc2e7fc    	ldr	q28, [sp, #0xb90]
100008a14: 4fc39381    	fmul.2d	v1, v28, v3[0]
100008a18: 4e61d400    	fadd.2d	v0, v0, v1
100008a1c: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
100008a20: 4fdf9021    	fmul.2d	v1, v1, v31[0]
100008a24: 4e61d400    	fadd.2d	v0, v0, v1
100008a28: 3dc283fa    	ldr	q26, [sp, #0xa00]
100008a2c: 4eb01e11    	mov.16b	v17, v16
100008a30: 4fd09341    	fmul.2d	v1, v26, v16[0]
100008a34: 4e61d400    	fadd.2d	v0, v0, v1
100008a38: 3dc263e4    	ldr	q4, [sp, #0x980]
100008a3c: 4fc89081    	fmul.2d	v1, v4, v8[0]
100008a40: 4e61d400    	fadd.2d	v0, v0, v1
100008a44: 3dc2b7e5    	ldr	q5, [sp, #0xad0]
100008a48: 4fd390a1    	fmul.2d	v1, v5, v19[0]
100008a4c: 4e61d400    	fadd.2d	v0, v0, v1
100008a50: 3d80abe0    	str	q0, [sp, #0x2a0]
100008a54: 4fc69160    	fmul.2d	v0, v11, v6[0]
100008a58: 3dc2abe1    	ldr	q1, [sp, #0xaa0]
100008a5c: 4fc79021    	fmul.2d	v1, v1, v7[0]
100008a60: 4ea71ceb    	mov.16b	v11, v7
100008a64: 4e61d400    	fadd.2d	v0, v0, v1
100008a68: 3dc313e1    	ldr	q1, [sp, #0xc40]
100008a6c: 4fc29021    	fmul.2d	v1, v1, v2[0]
100008a70: 4e61d400    	fadd.2d	v0, v0, v1
100008a74: 4fcc9141    	fmul.2d	v1, v10, v12[0]
100008a78: 4e61d400    	fadd.2d	v0, v0, v1
100008a7c: 4fcd9121    	fmul.2d	v1, v9, v13[0]
100008a80: 4e61d400    	fadd.2d	v0, v0, v1
100008a84: 4fc39241    	fmul.2d	v1, v18, v3[0]
100008a88: 4e61d400    	fadd.2d	v0, v0, v1
100008a8c: 4ebf1fe7    	mov.16b	v7, v31
100008a90: 4fdf93a1    	fmul.2d	v1, v29, v31[0]
100008a94: 4e61d400    	fadd.2d	v0, v0, v1
100008a98: 3dc2a3fd    	ldr	q29, [sp, #0xa80]
100008a9c: 4fd093a1    	fmul.2d	v1, v29, v16[0]
100008aa0: 4e61d400    	fadd.2d	v0, v0, v1
100008aa4: 4ea81d10    	mov.16b	v16, v8
100008aa8: 4fc893c1    	fmul.2d	v1, v30, v8[0]
100008aac: 4e61d400    	fadd.2d	v0, v0, v1
100008ab0: 3dc25bfe    	ldr	q30, [sp, #0x960]
100008ab4: 4fd393c1    	fmul.2d	v1, v30, v19[0]
100008ab8: 4e61d400    	fadd.2d	v0, v0, v1
100008abc: 3d8237e0    	str	q0, [sp, #0x8d0]
100008ac0: 3dc2dfff    	ldr	q31, [sp, #0xb70]
100008ac4: 4fc693e0    	fmul.2d	v0, v31, v6[0]
100008ac8: 3dc2a7e8    	ldr	q8, [sp, #0xa90]
100008acc: 4fcb9101    	fmul.2d	v1, v8, v11[0]
100008ad0: 4e61d400    	fadd.2d	v0, v0, v1
100008ad4: 3dc2cbea    	ldr	q10, [sp, #0xb20]
100008ad8: 4fc29141    	fmul.2d	v1, v10, v2[0]
100008adc: 4e61d400    	fadd.2d	v0, v0, v1
100008ae0: 3dc27feb    	ldr	q11, [sp, #0x9f0]
100008ae4: 4fcc9161    	fmul.2d	v1, v11, v12[0]
100008ae8: 4e61d400    	fadd.2d	v0, v0, v1
100008aec: 3dc25fec    	ldr	q12, [sp, #0x970]
100008af0: 4fcd9181    	fmul.2d	v1, v12, v13[0]
100008af4: 4e61d400    	fadd.2d	v0, v0, v1
100008af8: 3dc2d7ed    	ldr	q13, [sp, #0xb50]
100008afc: 4fc391a1    	fmul.2d	v1, v13, v3[0]
100008b00: 4e61d400    	fadd.2d	v0, v0, v1
100008b04: 3dc2d3e1    	ldr	q1, [sp, #0xb40]
100008b08: 4fc79021    	fmul.2d	v1, v1, v7[0]
100008b0c: 4e61d400    	fadd.2d	v0, v0, v1
100008b10: 3dc29fe9    	ldr	q9, [sp, #0xa70]
100008b14: 4fd19121    	fmul.2d	v1, v9, v17[0]
100008b18: 4e61d400    	fadd.2d	v0, v0, v1
100008b1c: 3dc2cfe1    	ldr	q1, [sp, #0xb30]
100008b20: 4fd09021    	fmul.2d	v1, v1, v16[0]
100008b24: 4e61d400    	fadd.2d	v0, v0, v1
100008b28: 3dc27be1    	ldr	q1, [sp, #0x9e0]
100008b2c: 4fd39021    	fmul.2d	v1, v1, v19[0]
100008b30: 4e61d400    	fadd.2d	v0, v0, v1
100008b34: 3d824be0    	str	q0, [sp, #0x920]
100008b38: ad441be7    	ldp	q7, q6, [sp, #0x80]
100008b3c: 6e66dec0    	fmul.2d	v0, v22, v6
100008b40: 6e004000    	ext.16b	v0, v0, v0, #0x8
100008b44: 6e66df01    	fmul.2d	v1, v24, v6
100008b48: 4e61d400    	fadd.2d	v0, v0, v1
100008b4c: 3dc2b3e1    	ldr	q1, [sp, #0xac0]
100008b50: 4fc79021    	fmul.2d	v1, v1, v7[0]
100008b54: 4e61d400    	fadd.2d	v0, v0, v1
100008b58: ad4343f3    	ldp	q19, q16, [sp, #0x60]
100008b5c: 3dc31fe1    	ldr	q1, [sp, #0xc70]
100008b60: 4fd09021    	fmul.2d	v1, v1, v16[0]
100008b64: 4e61d400    	fadd.2d	v0, v0, v1
100008b68: 3dc2ffe1    	ldr	q1, [sp, #0xbf0]
100008b6c: 4fd39021    	fmul.2d	v1, v1, v19[0]
100008b70: 4e61d400    	fadd.2d	v0, v0, v1
100008b74: ad425bf2    	ldp	q18, q22, [sp, #0x40]
100008b78: 3dc31be1    	ldr	q1, [sp, #0xc60]
100008b7c: 4fd29021    	fmul.2d	v1, v1, v18[0]
100008b80: 4e61d400    	fadd.2d	v0, v0, v1
100008b84: 3dc317e1    	ldr	q1, [sp, #0xc50]
100008b88: 4fd69021    	fmul.2d	v1, v1, v22[0]
100008b8c: 4e61d400    	fadd.2d	v0, v0, v1
100008b90: ad410fe2    	ldp	q2, q3, [sp, #0x20]
100008b94: 3dc2fbe1    	ldr	q1, [sp, #0xbe0]
100008b98: 4fc39021    	fmul.2d	v1, v1, v3[0]
100008b9c: 4e61d400    	fadd.2d	v0, v0, v1
100008ba0: 4fc29281    	fmul.2d	v1, v20, v2[0]
100008ba4: 4e61d400    	fadd.2d	v0, v0, v1
100008ba8: 3dc007f4    	ldr	q20, [sp, #0x10]
100008bac: 4fd492a1    	fmul.2d	v1, v21, v20[0]
100008bb0: 4e61d400    	fadd.2d	v0, v0, v1
100008bb4: 3d80a7e0    	str	q0, [sp, #0x290]
100008bb8: 4fc692e0    	fmul.2d	v0, v23, v6[0]
100008bbc: 3dc02bf1    	ldr	q17, [sp, #0xa0]
100008bc0: 4fd19321    	fmul.2d	v1, v25, v17[0]
100008bc4: 4e61d400    	fadd.2d	v0, v0, v1
100008bc8: 4fc79361    	fmul.2d	v1, v27, v7[0]
100008bcc: 4e61d400    	fadd.2d	v0, v0, v1
100008bd0: 4fd091c1    	fmul.2d	v1, v14, v16[0]
100008bd4: 4e61d400    	fadd.2d	v0, v0, v1
100008bd8: 4fd391e1    	fmul.2d	v1, v15, v19[0]
100008bdc: 4eb31e6e    	mov.16b	v14, v19
100008be0: 4e61d400    	fadd.2d	v0, v0, v1
100008be4: 4fd29381    	fmul.2d	v1, v28, v18[0]
100008be8: 4e61d400    	fadd.2d	v0, v0, v1
100008bec: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
100008bf0: 4fd69021    	fmul.2d	v1, v1, v22[0]
100008bf4: 4eb61ecf    	mov.16b	v15, v22
100008bf8: 4e61d400    	fadd.2d	v0, v0, v1
100008bfc: 4fc39341    	fmul.2d	v1, v26, v3[0]
100008c00: 4e61d400    	fadd.2d	v0, v0, v1
100008c04: 4ea21c53    	mov.16b	v19, v2
100008c08: 4fc29081    	fmul.2d	v1, v4, v2[0]
100008c0c: 4e61d400    	fadd.2d	v0, v0, v1
100008c10: 4fd490a1    	fmul.2d	v1, v5, v20[0]
100008c14: 4e61d400    	fadd.2d	v0, v0, v1
100008c18: 3d80a3e0    	str	q0, [sp, #0x280]
100008c1c: 3dc2afe0    	ldr	q0, [sp, #0xab0]
100008c20: 4fc69000    	fmul.2d	v0, v0, v6[0]
100008c24: 3dc2abfc    	ldr	q28, [sp, #0xaa0]
100008c28: 4fd19381    	fmul.2d	v1, v28, v17[0]
100008c2c: 4eb11e22    	mov.16b	v2, v17
100008c30: 4e61d400    	fadd.2d	v0, v0, v1
100008c34: 3dc313e1    	ldr	q1, [sp, #0xc40]
100008c38: 4fc79021    	fmul.2d	v1, v1, v7[0]
100008c3c: 4e61d400    	fadd.2d	v0, v0, v1
100008c40: 3dc2dbe1    	ldr	q1, [sp, #0xb60]
100008c44: 4fd09021    	fmul.2d	v1, v1, v16[0]
100008c48: 4e61d400    	fadd.2d	v0, v0, v1
100008c4c: 3dc2e3e1    	ldr	q1, [sp, #0xb80]
100008c50: 4fce9021    	fmul.2d	v1, v1, v14[0]
100008c54: 4e61d400    	fadd.2d	v0, v0, v1
100008c58: 3dc30fe1    	ldr	q1, [sp, #0xc30]
100008c5c: 4fd29021    	fmul.2d	v1, v1, v18[0]
100008c60: 4e61d400    	fadd.2d	v0, v0, v1
100008c64: 3dc30be1    	ldr	q1, [sp, #0xc20]
100008c68: 4fd69021    	fmul.2d	v1, v1, v22[0]
100008c6c: 4e61d400    	fadd.2d	v0, v0, v1
100008c70: 4fc393a1    	fmul.2d	v1, v29, v3[0]
100008c74: 4e61d400    	fadd.2d	v0, v0, v1
100008c78: 3dc277fd    	ldr	q29, [sp, #0x9d0]
100008c7c: 4fd393a1    	fmul.2d	v1, v29, v19[0]
100008c80: 4eb31e64    	mov.16b	v4, v19
100008c84: 4e61d400    	fadd.2d	v0, v0, v1
100008c88: 4fd493c1    	fmul.2d	v1, v30, v20[0]
100008c8c: 4eb41e85    	mov.16b	v5, v20
100008c90: 4e61d400    	fadd.2d	v0, v0, v1
100008c94: 3d809fe0    	str	q0, [sp, #0x270]
100008c98: 4fc693e0    	fmul.2d	v0, v31, v6[0]
100008c9c: 4fd19101    	fmul.2d	v1, v8, v17[0]
100008ca0: 4e61d400    	fadd.2d	v0, v0, v1
100008ca4: 4fc79141    	fmul.2d	v1, v10, v7[0]
100008ca8: 4e61d400    	fadd.2d	v0, v0, v1
100008cac: 4fd09161    	fmul.2d	v1, v11, v16[0]
100008cb0: 4e61d400    	fadd.2d	v0, v0, v1
100008cb4: 4fce9181    	fmul.2d	v1, v12, v14[0]
100008cb8: 4e61d400    	fadd.2d	v0, v0, v1
100008cbc: 4fd291a1    	fmul.2d	v1, v13, v18[0]
100008cc0: 4e61d400    	fadd.2d	v0, v0, v1
100008cc4: 3dc2d3ed    	ldr	q13, [sp, #0xb40]
100008cc8: 4fd691a1    	fmul.2d	v1, v13, v22[0]
100008ccc: 4e61d400    	fadd.2d	v0, v0, v1
100008cd0: 4fc39121    	fmul.2d	v1, v9, v3[0]
100008cd4: 4ea91d2a    	mov.16b	v10, v9
100008cd8: 4e61d400    	fadd.2d	v0, v0, v1
100008cdc: 3dc2cfe9    	ldr	q9, [sp, #0xb30]
100008ce0: 4fd39121    	fmul.2d	v1, v9, v19[0]
100008ce4: 4e61d400    	fadd.2d	v0, v0, v1
100008ce8: 3dc27bfe    	ldr	q30, [sp, #0x9e0]
100008cec: 4fd493c1    	fmul.2d	v1, v30, v20[0]
100008cf0: 4e61d400    	fadd.2d	v0, v0, v1
100008cf4: 3d8247e0    	str	q0, [sp, #0x910]
100008cf8: 3dc13513    	ldr	q19, [x8, #0x4d0]
100008cfc: ad4803e1    	ldp	q1, q0, [sp, #0x100]
100008d00: 4fc09260    	fmul.2d	v0, v19, v0[0]
100008d04: 3dc14d11    	ldr	q17, [x8, #0x530]
100008d08: 4fc19221    	fmul.2d	v1, v17, v1[0]
100008d0c: 4e61d400    	fadd.2d	v0, v0, v1
100008d10: 3dc1651b    	ldr	q27, [x8, #0x590]
100008d14: 3dc21fe1    	ldr	q1, [sp, #0x870]
100008d18: 4fc19361    	fmul.2d	v1, v27, v1[0]
100008d1c: 4e61d400    	fadd.2d	v0, v0, v1
100008d20: 3dc17d1a    	ldr	q26, [x8, #0x5f0]
100008d24: 3dc1cfe1    	ldr	q1, [sp, #0x730]
100008d28: 4fc19341    	fmul.2d	v1, v26, v1[0]
100008d2c: 4e61d400    	fadd.2d	v0, v0, v1
100008d30: 3dc19519    	ldr	q25, [x8, #0x650]
100008d34: 3dc17be1    	ldr	q1, [sp, #0x5e0]
100008d38: 4fc19321    	fmul.2d	v1, v25, v1[0]
100008d3c: 4e61d400    	fadd.2d	v0, v0, v1
100008d40: 3dc1ad18    	ldr	q24, [x8, #0x6b0]
100008d44: 3dc233e1    	ldr	q1, [sp, #0x8c0]
100008d48: 4fc19301    	fmul.2d	v1, v24, v1[0]
100008d4c: 4e61d400    	fadd.2d	v0, v0, v1
100008d50: 3dc1c517    	ldr	q23, [x8, #0x710]
100008d54: 3dc22fe1    	ldr	q1, [sp, #0x8b0]
100008d58: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100008d5c: 4e61d400    	fadd.2d	v0, v0, v1
100008d60: 3dc1dd16    	ldr	q22, [x8, #0x770]
100008d64: 3dc22be1    	ldr	q1, [sp, #0x8a0]
100008d68: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100008d6c: 4e61d400    	fadd.2d	v0, v0, v1
100008d70: 3dc1f515    	ldr	q21, [x8, #0x7d0]
100008d74: 3dc227e1    	ldr	q1, [sp, #0x890]
100008d78: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100008d7c: 4e61d400    	fadd.2d	v0, v0, v1
100008d80: 3dc20d14    	ldr	q20, [x8, #0x830]
100008d84: 3dc223e1    	ldr	q1, [sp, #0x880]
100008d88: 4fc19281    	fmul.2d	v1, v20, v1[0]
100008d8c: 4e61d400    	fadd.2d	v0, v0, v1
100008d90: 3d817be0    	str	q0, [sp, #0x5e0]
100008d94: 91136109    	add	x9, x8, #0x4d8
100008d98: 9114e10a    	add	x10, x8, #0x538
100008d9c: 4d408533    	ld1.d	{ v19 }[1], [x9]
100008da0: 3dc21be0    	ldr	q0, [sp, #0x860]
100008da4: 4fc09260    	fmul.2d	v0, v19, v0[0]
100008da8: 4d408551    	ld1.d	{ v17 }[1], [x10]
100008dac: 3dc003e1    	ldr	q1, [sp]
100008db0: 4fc19221    	fmul.2d	v1, v17, v1[0]
100008db4: 4e61d400    	fadd.2d	v0, v0, v1
100008db8: 3dc217e1    	ldr	q1, [sp, #0x850]
100008dbc: 4fc19361    	fmul.2d	v1, v27, v1[0]
100008dc0: 4e61d400    	fadd.2d	v0, v0, v1
100008dc4: 3dc213e1    	ldr	q1, [sp, #0x840]
100008dc8: 4fc19341    	fmul.2d	v1, v26, v1[0]
100008dcc: 4e61d400    	fadd.2d	v0, v0, v1
100008dd0: 3dc20fe1    	ldr	q1, [sp, #0x830]
100008dd4: 4fc19321    	fmul.2d	v1, v25, v1[0]
100008dd8: 4e61d400    	fadd.2d	v0, v0, v1
100008ddc: 3dc20be1    	ldr	q1, [sp, #0x820]
100008de0: 4fc19301    	fmul.2d	v1, v24, v1[0]
100008de4: 4e61d400    	fadd.2d	v0, v0, v1
100008de8: 3dc207e1    	ldr	q1, [sp, #0x810]
100008dec: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100008df0: 4e61d400    	fadd.2d	v0, v0, v1
100008df4: 3dc203e1    	ldr	q1, [sp, #0x800]
100008df8: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100008dfc: 4e61d400    	fadd.2d	v0, v0, v1
100008e00: 3dc1ffe1    	ldr	q1, [sp, #0x7f0]
100008e04: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100008e08: 4e61d400    	fadd.2d	v0, v0, v1
100008e0c: 3dc1fbe1    	ldr	q1, [sp, #0x7e0]
100008e10: 4fc19281    	fmul.2d	v1, v20, v1[0]
100008e14: 4e61d400    	fadd.2d	v0, v0, v1
100008e18: 3d8047e0    	str	q0, [sp, #0x110]
100008e1c: 3dc1f3e0    	ldr	q0, [sp, #0x7c0]
100008e20: 4fc09260    	fmul.2d	v0, v19, v0[0]
100008e24: 3dc1f7e1    	ldr	q1, [sp, #0x7d0]
100008e28: 4fc19221    	fmul.2d	v1, v17, v1[0]
100008e2c: 4e61d400    	fadd.2d	v0, v0, v1
100008e30: 3dc1efe1    	ldr	q1, [sp, #0x7b0]
100008e34: 4fc19361    	fmul.2d	v1, v27, v1[0]
100008e38: 4e61d400    	fadd.2d	v0, v0, v1
100008e3c: 3dc1ebe1    	ldr	q1, [sp, #0x7a0]
100008e40: 4fc19341    	fmul.2d	v1, v26, v1[0]
100008e44: 4e61d400    	fadd.2d	v0, v0, v1
100008e48: 3dc1e7e1    	ldr	q1, [sp, #0x790]
100008e4c: 4fc19321    	fmul.2d	v1, v25, v1[0]
100008e50: 4e61d400    	fadd.2d	v0, v0, v1
100008e54: 3dc1e3e1    	ldr	q1, [sp, #0x780]
100008e58: 4fc19301    	fmul.2d	v1, v24, v1[0]
100008e5c: 4e61d400    	fadd.2d	v0, v0, v1
100008e60: 3dc1dfe1    	ldr	q1, [sp, #0x770]
100008e64: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100008e68: 4e61d400    	fadd.2d	v0, v0, v1
100008e6c: 3dc1dbe1    	ldr	q1, [sp, #0x760]
100008e70: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100008e74: 4e61d400    	fadd.2d	v0, v0, v1
100008e78: 3dc1d7e1    	ldr	q1, [sp, #0x750]
100008e7c: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100008e80: 4e61d400    	fadd.2d	v0, v0, v1
100008e84: 3dc1d3e1    	ldr	q1, [sp, #0x740]
100008e88: 4fc19281    	fmul.2d	v1, v20, v1[0]
100008e8c: 4e61d400    	fadd.2d	v0, v0, v1
100008e90: 3d8043e0    	str	q0, [sp, #0x100]
100008e94: 3dc1c7e0    	ldr	q0, [sp, #0x710]
100008e98: 4fc09260    	fmul.2d	v0, v19, v0[0]
100008e9c: 3dc1cbe1    	ldr	q1, [sp, #0x720]
100008ea0: 4fc19221    	fmul.2d	v1, v17, v1[0]
100008ea4: 4e61d400    	fadd.2d	v0, v0, v1
100008ea8: 3dc1c3e1    	ldr	q1, [sp, #0x700]
100008eac: 4fc19361    	fmul.2d	v1, v27, v1[0]
100008eb0: 4e61d400    	fadd.2d	v0, v0, v1
100008eb4: 3dc1bfe1    	ldr	q1, [sp, #0x6f0]
100008eb8: 4fc19341    	fmul.2d	v1, v26, v1[0]
100008ebc: 4e61d400    	fadd.2d	v0, v0, v1
100008ec0: 3dc1bbe1    	ldr	q1, [sp, #0x6e0]
100008ec4: 4fc19321    	fmul.2d	v1, v25, v1[0]
100008ec8: 4e61d400    	fadd.2d	v0, v0, v1
100008ecc: 3dc1b3e1    	ldr	q1, [sp, #0x6c0]
100008ed0: 4fc19301    	fmul.2d	v1, v24, v1[0]
100008ed4: 4e61d400    	fadd.2d	v0, v0, v1
100008ed8: 3dc1b7e1    	ldr	q1, [sp, #0x6d0]
100008edc: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100008ee0: 4e61d400    	fadd.2d	v0, v0, v1
100008ee4: 3dc1afe1    	ldr	q1, [sp, #0x6b0]
100008ee8: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100008eec: 4e61d400    	fadd.2d	v0, v0, v1
100008ef0: 3dc1abe1    	ldr	q1, [sp, #0x6a0]
100008ef4: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100008ef8: 4e61d400    	fadd.2d	v0, v0, v1
100008efc: 3dc1a7e1    	ldr	q1, [sp, #0x690]
100008f00: 4fc19281    	fmul.2d	v1, v20, v1[0]
100008f04: 4e61d400    	fadd.2d	v0, v0, v1
100008f08: 3d81b3e0    	str	q0, [sp, #0x6c0]
100008f0c: 3dc19fe0    	ldr	q0, [sp, #0x670]
100008f10: 4fc09260    	fmul.2d	v0, v19, v0[0]
100008f14: 3dc1a3e1    	ldr	q1, [sp, #0x680]
100008f18: 4fc19221    	fmul.2d	v1, v17, v1[0]
100008f1c: 4e61d400    	fadd.2d	v0, v0, v1
100008f20: 3dc19be1    	ldr	q1, [sp, #0x660]
100008f24: 4fc19361    	fmul.2d	v1, v27, v1[0]
100008f28: 4e61d400    	fadd.2d	v0, v0, v1
100008f2c: 3dc197e1    	ldr	q1, [sp, #0x650]
100008f30: 4fc19341    	fmul.2d	v1, v26, v1[0]
100008f34: 4e61d400    	fadd.2d	v0, v0, v1
100008f38: 3dc193e1    	ldr	q1, [sp, #0x640]
100008f3c: 4fc19321    	fmul.2d	v1, v25, v1[0]
100008f40: 4e61d400    	fadd.2d	v0, v0, v1
100008f44: 3dc18fe1    	ldr	q1, [sp, #0x630]
100008f48: 4fc19301    	fmul.2d	v1, v24, v1[0]
100008f4c: 4e61d400    	fadd.2d	v0, v0, v1
100008f50: 3dc18be1    	ldr	q1, [sp, #0x620]
100008f54: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100008f58: 4e61d400    	fadd.2d	v0, v0, v1
100008f5c: 3dc187e1    	ldr	q1, [sp, #0x610]
100008f60: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100008f64: 4e61d400    	fadd.2d	v0, v0, v1
100008f68: 3dc183e1    	ldr	q1, [sp, #0x600]
100008f6c: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100008f70: 4e61d400    	fadd.2d	v0, v0, v1
100008f74: 3dc17fe1    	ldr	q1, [sp, #0x5f0]
100008f78: 4fc19281    	fmul.2d	v1, v20, v1[0]
100008f7c: 4e61d400    	fadd.2d	v0, v0, v1
100008f80: 3d818be0    	str	q0, [sp, #0x620]
100008f84: 3dc173e0    	ldr	q0, [sp, #0x5c0]
100008f88: 4fc09260    	fmul.2d	v0, v19, v0[0]
100008f8c: 3dc177e1    	ldr	q1, [sp, #0x5d0]
100008f90: 4fc19221    	fmul.2d	v1, v17, v1[0]
100008f94: 4e61d400    	fadd.2d	v0, v0, v1
100008f98: 3dc16fe1    	ldr	q1, [sp, #0x5b0]
100008f9c: 4fc19361    	fmul.2d	v1, v27, v1[0]
100008fa0: 4e61d400    	fadd.2d	v0, v0, v1
100008fa4: 3dc16be1    	ldr	q1, [sp, #0x5a0]
100008fa8: 4fc19341    	fmul.2d	v1, v26, v1[0]
100008fac: 4e61d400    	fadd.2d	v0, v0, v1
100008fb0: 3dc167e1    	ldr	q1, [sp, #0x590]
100008fb4: 4fc19321    	fmul.2d	v1, v25, v1[0]
100008fb8: 4e61d400    	fadd.2d	v0, v0, v1
100008fbc: 3dc163e1    	ldr	q1, [sp, #0x580]
100008fc0: 4fc19301    	fmul.2d	v1, v24, v1[0]
100008fc4: 4e61d400    	fadd.2d	v0, v0, v1
100008fc8: 3dc15fe1    	ldr	q1, [sp, #0x570]
100008fcc: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100008fd0: 4e61d400    	fadd.2d	v0, v0, v1
100008fd4: 3dc15be1    	ldr	q1, [sp, #0x560]
100008fd8: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100008fdc: 4e61d400    	fadd.2d	v0, v0, v1
100008fe0: 3dc157e1    	ldr	q1, [sp, #0x550]
100008fe4: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100008fe8: 4e61d400    	fadd.2d	v0, v0, v1
100008fec: 3dc153e1    	ldr	q1, [sp, #0x540]
100008ff0: 4fc19281    	fmul.2d	v1, v20, v1[0]
100008ff4: 4e61d400    	fadd.2d	v0, v0, v1
100008ff8: 3d8187e0    	str	q0, [sp, #0x610]
100008ffc: 3dc14be0    	ldr	q0, [sp, #0x520]
100009000: 4fc09260    	fmul.2d	v0, v19, v0[0]
100009004: 3dc14fe1    	ldr	q1, [sp, #0x530]
100009008: 4fc19221    	fmul.2d	v1, v17, v1[0]
10000900c: 4e61d400    	fadd.2d	v0, v0, v1
100009010: 3dc147e1    	ldr	q1, [sp, #0x510]
100009014: 4fc19361    	fmul.2d	v1, v27, v1[0]
100009018: 4e61d400    	fadd.2d	v0, v0, v1
10000901c: 3dc143e1    	ldr	q1, [sp, #0x500]
100009020: 4fc19341    	fmul.2d	v1, v26, v1[0]
100009024: 4e61d400    	fadd.2d	v0, v0, v1
100009028: 3dc13fe1    	ldr	q1, [sp, #0x4f0]
10000902c: 4fc19321    	fmul.2d	v1, v25, v1[0]
100009030: 4e61d400    	fadd.2d	v0, v0, v1
100009034: 3dc13be1    	ldr	q1, [sp, #0x4e0]
100009038: 4fc19301    	fmul.2d	v1, v24, v1[0]
10000903c: 4e61d400    	fadd.2d	v0, v0, v1
100009040: 3dc137e1    	ldr	q1, [sp, #0x4d0]
100009044: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100009048: 4e61d400    	fadd.2d	v0, v0, v1
10000904c: 3dc133e1    	ldr	q1, [sp, #0x4c0]
100009050: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100009054: 4e61d400    	fadd.2d	v0, v0, v1
100009058: 3dc12fe1    	ldr	q1, [sp, #0x4b0]
10000905c: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100009060: 4e61d400    	fadd.2d	v0, v0, v1
100009064: 3dc12be1    	ldr	q1, [sp, #0x4a0]
100009068: 4fc19281    	fmul.2d	v1, v20, v1[0]
10000906c: 4e61d400    	fadd.2d	v0, v0, v1
100009070: 3d817fe0    	str	q0, [sp, #0x5f0]
100009074: 3dc123e0    	ldr	q0, [sp, #0x480]
100009078: 4fc09260    	fmul.2d	v0, v19, v0[0]
10000907c: 3dc127e1    	ldr	q1, [sp, #0x490]
100009080: 4fc19221    	fmul.2d	v1, v17, v1[0]
100009084: 4e61d400    	fadd.2d	v0, v0, v1
100009088: 3dc11fe1    	ldr	q1, [sp, #0x470]
10000908c: 4fc19361    	fmul.2d	v1, v27, v1[0]
100009090: 4e61d400    	fadd.2d	v0, v0, v1
100009094: 3dc11be1    	ldr	q1, [sp, #0x460]
100009098: 4fc19341    	fmul.2d	v1, v26, v1[0]
10000909c: 4e61d400    	fadd.2d	v0, v0, v1
1000090a0: 3dc117e1    	ldr	q1, [sp, #0x450]
1000090a4: 4fc19321    	fmul.2d	v1, v25, v1[0]
1000090a8: 4e61d400    	fadd.2d	v0, v0, v1
1000090ac: 3dc10fe1    	ldr	q1, [sp, #0x430]
1000090b0: 4fc19301    	fmul.2d	v1, v24, v1[0]
1000090b4: 4e61d400    	fadd.2d	v0, v0, v1
1000090b8: 3dc113e1    	ldr	q1, [sp, #0x440]
1000090bc: 4fc192e1    	fmul.2d	v1, v23, v1[0]
1000090c0: 4e61d400    	fadd.2d	v0, v0, v1
1000090c4: 3dc10be1    	ldr	q1, [sp, #0x420]
1000090c8: 4fc192c1    	fmul.2d	v1, v22, v1[0]
1000090cc: 4e61d400    	fadd.2d	v0, v0, v1
1000090d0: 3dc107e1    	ldr	q1, [sp, #0x410]
1000090d4: 4fc192a1    	fmul.2d	v1, v21, v1[0]
1000090d8: 4e61d400    	fadd.2d	v0, v0, v1
1000090dc: 3dc103e1    	ldr	q1, [sp, #0x400]
1000090e0: 4fc19281    	fmul.2d	v1, v20, v1[0]
1000090e4: 4e61d400    	fadd.2d	v0, v0, v1
1000090e8: 3d8183e0    	str	q0, [sp, #0x600]
1000090ec: ad5f07e0    	ldp	q0, q1, [sp, #0x3e0]
1000090f0: 4fc09260    	fmul.2d	v0, v19, v0[0]
1000090f4: 4fc19221    	fmul.2d	v1, v17, v1[0]
1000090f8: 4e61d400    	fadd.2d	v0, v0, v1
1000090fc: 3dc0f7e1    	ldr	q1, [sp, #0x3d0]
100009100: 4fc19361    	fmul.2d	v1, v27, v1[0]
100009104: 4e61d400    	fadd.2d	v0, v0, v1
100009108: 3dc0f3e1    	ldr	q1, [sp, #0x3c0]
10000910c: 4fc19341    	fmul.2d	v1, v26, v1[0]
100009110: 4e61d400    	fadd.2d	v0, v0, v1
100009114: 3dc0efe1    	ldr	q1, [sp, #0x3b0]
100009118: 4fc19321    	fmul.2d	v1, v25, v1[0]
10000911c: 4e61d400    	fadd.2d	v0, v0, v1
100009120: 3dc0ebe1    	ldr	q1, [sp, #0x3a0]
100009124: 4fc19301    	fmul.2d	v1, v24, v1[0]
100009128: 4e61d400    	fadd.2d	v0, v0, v1
10000912c: 3dc0e7e1    	ldr	q1, [sp, #0x390]
100009130: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100009134: 4e61d400    	fadd.2d	v0, v0, v1
100009138: 3dc0e3e1    	ldr	q1, [sp, #0x380]
10000913c: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100009140: 4e61d400    	fadd.2d	v0, v0, v1
100009144: 3dc0dfe1    	ldr	q1, [sp, #0x370]
100009148: 4fc192a1    	fmul.2d	v1, v21, v1[0]
10000914c: 4e61d400    	fadd.2d	v0, v0, v1
100009150: 3dc0dbe1    	ldr	q1, [sp, #0x360]
100009154: 4fc19281    	fmul.2d	v1, v20, v1[0]
100009158: 4e61d400    	fadd.2d	v0, v0, v1
10000915c: 3d8177e0    	str	q0, [sp, #0x5d0]
100009160: 4fc69260    	fmul.2d	v0, v19, v6[0]
100009164: 4fc29221    	fmul.2d	v1, v17, v2[0]
100009168: 4e61d400    	fadd.2d	v0, v0, v1
10000916c: 4fc79361    	fmul.2d	v1, v27, v7[0]
100009170: 4e61d400    	fadd.2d	v0, v0, v1
100009174: 4fd09341    	fmul.2d	v1, v26, v16[0]
100009178: 4e61d400    	fadd.2d	v0, v0, v1
10000917c: 4fce9321    	fmul.2d	v1, v25, v14[0]
100009180: 4e61d400    	fadd.2d	v0, v0, v1
100009184: 4fd29301    	fmul.2d	v1, v24, v18[0]
100009188: 4e61d400    	fadd.2d	v0, v0, v1
10000918c: 4fcf92e1    	fmul.2d	v1, v23, v15[0]
100009190: 4e61d400    	fadd.2d	v0, v0, v1
100009194: 4fc392c1    	fmul.2d	v1, v22, v3[0]
100009198: 4e61d400    	fadd.2d	v0, v0, v1
10000919c: 4fc492a1    	fmul.2d	v1, v21, v4[0]
1000091a0: 4e61d400    	fadd.2d	v0, v0, v1
1000091a4: 4fc59281    	fmul.2d	v1, v20, v5[0]
1000091a8: 4e61d400    	fadd.2d	v0, v0, v1
1000091ac: 3d8173e0    	str	q0, [sp, #0x5c0]
1000091b0: ad5e4112    	ldp	q18, q16, [x8, #0x3c0]
1000091b4: 3dc307e0    	ldr	q0, [sp, #0xc10]
1000091b8: 6e72dc00    	fmul.2d	v0, v0, v18
1000091bc: 6e004000    	ext.16b	v0, v0, v0, #0x8
1000091c0: 3dc303e1    	ldr	q1, [sp, #0xc00]
1000091c4: 6e72dc21    	fmul.2d	v1, v1, v18
1000091c8: 4e61d400    	fadd.2d	v0, v0, v1
1000091cc: 3dc2b3e1    	ldr	q1, [sp, #0xac0]
1000091d0: 4fd09021    	fmul.2d	v1, v1, v16[0]
1000091d4: 4e61d400    	fadd.2d	v0, v0, v1
1000091d8: 910f6109    	add	x9, x8, #0x3d8
1000091dc: 3dc00126    	ldr	q6, [x9]
1000091e0: 3dc31fe1    	ldr	q1, [sp, #0xc70]
1000091e4: 4fc69021    	fmul.2d	v1, v1, v6[0]
1000091e8: 4e61d400    	fadd.2d	v0, v0, v1
1000091ec: ad5f1d05    	ldp	q5, q7, [x8, #0x3e0]
1000091f0: 3dc2ffe1    	ldr	q1, [sp, #0xbf0]
1000091f4: 4fc59021    	fmul.2d	v1, v1, v5[0]
1000091f8: 4e61d400    	fadd.2d	v0, v0, v1
1000091fc: 910fa109    	add	x9, x8, #0x3e8
100009200: 3dc00124    	ldr	q4, [x9]
100009204: 3dc31be1    	ldr	q1, [sp, #0xc60]
100009208: 4fc49021    	fmul.2d	v1, v1, v4[0]
10000920c: 4e61d400    	fadd.2d	v0, v0, v1
100009210: 3dc317e1    	ldr	q1, [sp, #0xc50]
100009214: 4fc79021    	fmul.2d	v1, v1, v7[0]
100009218: 4e61d400    	fadd.2d	v0, v0, v1
10000921c: 910fe109    	add	x9, x8, #0x3f8
100009220: 3dc00123    	ldr	q3, [x9]
100009224: 3dc2fbe1    	ldr	q1, [sp, #0xbe0]
100009228: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000922c: 4e61d400    	fadd.2d	v0, v0, v1
100009230: 3dc10102    	ldr	q2, [x8, #0x400]
100009234: 3dc2f7e1    	ldr	q1, [sp, #0xbd0]
100009238: 4fc29021    	fmul.2d	v1, v1, v2[0]
10000923c: 4e61d400    	fadd.2d	v0, v0, v1
100009240: 91102109    	add	x9, x8, #0x408
100009244: 3dc00121    	ldr	q1, [x9]
100009248: 3dc2f3ff    	ldr	q31, [sp, #0xbc0]
10000924c: 4fc193ef    	fmul.2d	v15, v31, v1[0]
100009250: 4e6fd400    	fadd.2d	v0, v0, v15
100009254: 3d81afe0    	str	q0, [sp, #0x6b0]
100009258: 910f2109    	add	x9, x8, #0x3c8
10000925c: 3dc00120    	ldr	q0, [x9]
100009260: 3dc2efff    	ldr	q31, [sp, #0xbb0]
100009264: 4fd293ef    	fmul.2d	v15, v31, v18[0]
100009268: 3dc2ebff    	ldr	q31, [sp, #0xba0]
10000926c: 4fc093ee    	fmul.2d	v14, v31, v0[0]
100009270: 4e6ed5ee    	fadd.2d	v14, v15, v14
100009274: 3dc28bff    	ldr	q31, [sp, #0xa20]
100009278: 4fd093ef    	fmul.2d	v15, v31, v16[0]
10000927c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009280: 3dc287ff    	ldr	q31, [sp, #0xa10]
100009284: 4fc693ef    	fmul.2d	v15, v31, v6[0]
100009288: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000928c: 3dc267ff    	ldr	q31, [sp, #0x990]
100009290: 4fc593ef    	fmul.2d	v15, v31, v5[0]
100009294: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009298: 3dc2e7ff    	ldr	q31, [sp, #0xb90]
10000929c: 4fc493ef    	fmul.2d	v15, v31, v4[0]
1000092a0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000092a4: 3dc2bbff    	ldr	q31, [sp, #0xae0]
1000092a8: 4fc793ef    	fmul.2d	v15, v31, v7[0]
1000092ac: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000092b0: 3dc283ff    	ldr	q31, [sp, #0xa00]
1000092b4: 4fc393ef    	fmul.2d	v15, v31, v3[0]
1000092b8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000092bc: 3dc263ff    	ldr	q31, [sp, #0x980]
1000092c0: 4fc293ef    	fmul.2d	v15, v31, v2[0]
1000092c4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000092c8: 3dc2b7ff    	ldr	q31, [sp, #0xad0]
1000092cc: 4fc193ef    	fmul.2d	v15, v31, v1[0]
1000092d0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000092d4: 3d816fee    	str	q14, [sp, #0x5b0]
1000092d8: 3dc2afff    	ldr	q31, [sp, #0xab0]
1000092dc: 4fd293ee    	fmul.2d	v14, v31, v18[0]
1000092e0: 4fc0938f    	fmul.2d	v15, v28, v0[0]
1000092e4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000092e8: 3dc313fc    	ldr	q28, [sp, #0xc40]
1000092ec: 4fd0938f    	fmul.2d	v15, v28, v16[0]
1000092f0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000092f4: 3dc2dbfc    	ldr	q28, [sp, #0xb60]
1000092f8: 4fc6938f    	fmul.2d	v15, v28, v6[0]
1000092fc: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009300: 3dc2e3fc    	ldr	q28, [sp, #0xb80]
100009304: 4fc5938f    	fmul.2d	v15, v28, v5[0]
100009308: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000930c: 3dc30ffc    	ldr	q28, [sp, #0xc30]
100009310: 4fc4938f    	fmul.2d	v15, v28, v4[0]
100009314: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009318: 3dc30bfc    	ldr	q28, [sp, #0xc20]
10000931c: 4fc7938f    	fmul.2d	v15, v28, v7[0]
100009320: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009324: 3dc2a3fc    	ldr	q28, [sp, #0xa80]
100009328: 4fc3938f    	fmul.2d	v15, v28, v3[0]
10000932c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009330: 4fc293af    	fmul.2d	v15, v29, v2[0]
100009334: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009338: 3dc25bfc    	ldr	q28, [sp, #0x960]
10000933c: 4fc1938f    	fmul.2d	v15, v28, v1[0]
100009340: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009344: 3d819fee    	str	q14, [sp, #0x670]
100009348: 3dc2dffc    	ldr	q28, [sp, #0xb70]
10000934c: 4fd2938e    	fmul.2d	v14, v28, v18[0]
100009350: 4fc0910f    	fmul.2d	v15, v8, v0[0]
100009354: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009358: 3dc2cbfc    	ldr	q28, [sp, #0xb20]
10000935c: 4fd0938f    	fmul.2d	v15, v28, v16[0]
100009360: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009364: 4fc6916f    	fmul.2d	v15, v11, v6[0]
100009368: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000936c: 4fc5918f    	fmul.2d	v15, v12, v5[0]
100009370: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009374: 3dc2d7fc    	ldr	q28, [sp, #0xb50]
100009378: 4fc4938f    	fmul.2d	v15, v28, v4[0]
10000937c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009380: 4fc791af    	fmul.2d	v15, v13, v7[0]
100009384: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009388: 4fc3914f    	fmul.2d	v15, v10, v3[0]
10000938c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009390: 4fc2912f    	fmul.2d	v15, v9, v2[0]
100009394: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009398: 4ebe1fdc    	mov.16b	v28, v30
10000939c: 4fc193cf    	fmul.2d	v15, v30, v1[0]
1000093a0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000093a4: 3d8197ee    	str	q14, [sp, #0x650]
1000093a8: 3dc273fd    	ldr	q29, [sp, #0x9c0]
1000093ac: 4fd293ae    	fmul.2d	v14, v29, v18[0]
1000093b0: 3dc26fea    	ldr	q10, [sp, #0x9b0]
1000093b4: 4fc0914f    	fmul.2d	v15, v10, v0[0]
1000093b8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000093bc: 3dc29beb    	ldr	q11, [sp, #0xa60]
1000093c0: 4fd0916f    	fmul.2d	v15, v11, v16[0]
1000093c4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000093c8: 3dc2c7fe    	ldr	q30, [sp, #0xb10]
1000093cc: 4fc693cf    	fmul.2d	v15, v30, v6[0]
1000093d0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000093d4: 3dc26bec    	ldr	q12, [sp, #0x9a0]
1000093d8: 4fc5918f    	fmul.2d	v15, v12, v5[0]
1000093dc: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000093e0: 3dc2c3ff    	ldr	q31, [sp, #0xb00]
1000093e4: 4fc493ef    	fmul.2d	v15, v31, v4[0]
1000093e8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000093ec: 3dc297ff    	ldr	q31, [sp, #0xa50]
1000093f0: 4fc793ef    	fmul.2d	v15, v31, v7[0]
1000093f4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000093f8: 3dc2bfe8    	ldr	q8, [sp, #0xaf0]
1000093fc: 4fc3910f    	fmul.2d	v15, v8, v3[0]
100009400: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009404: 3dc293e8    	ldr	q8, [sp, #0xa40]
100009408: 4fc2910f    	fmul.2d	v15, v8, v2[0]
10000940c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009410: 3dc28fe9    	ldr	q9, [sp, #0xa30]
100009414: 4fc1912f    	fmul.2d	v15, v9, v1[0]
100009418: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000941c: 3d81b7ee    	str	q14, [sp, #0x6d0]
100009420: 4fd29272    	fmul.2d	v18, v19, v18[0]
100009424: 4fc09220    	fmul.2d	v0, v17, v0[0]
100009428: 4e60d640    	fadd.2d	v0, v18, v0
10000942c: 4fd09370    	fmul.2d	v16, v27, v16[0]
100009430: 4e70d400    	fadd.2d	v0, v0, v16
100009434: 4fc69346    	fmul.2d	v6, v26, v6[0]
100009438: 4e66d400    	fadd.2d	v0, v0, v6
10000943c: 4fc59325    	fmul.2d	v5, v25, v5[0]
100009440: 4e65d400    	fadd.2d	v0, v0, v5
100009444: 4fc49304    	fmul.2d	v4, v24, v4[0]
100009448: 4e64d400    	fadd.2d	v0, v0, v4
10000944c: 4fc792e4    	fmul.2d	v4, v23, v7[0]
100009450: 4e64d400    	fadd.2d	v0, v0, v4
100009454: 4fc392c3    	fmul.2d	v3, v22, v3[0]
100009458: 4e63d400    	fadd.2d	v0, v0, v3
10000945c: 4fc292a2    	fmul.2d	v2, v21, v2[0]
100009460: 4e62d400    	fadd.2d	v0, v0, v2
100009464: 4fc19281    	fmul.2d	v1, v20, v1[0]
100009468: 4e61d400    	fadd.2d	v0, v0, v1
10000946c: 3d81abe0    	str	q0, [sp, #0x6a0]
100009470: 3dc10912    	ldr	q18, [x8, #0x420]
100009474: 3dc307e0    	ldr	q0, [sp, #0xc10]
100009478: 6e72dc00    	fmul.2d	v0, v0, v18
10000947c: 6e004000    	ext.16b	v0, v0, v0, #0x8
100009480: 3dc303e1    	ldr	q1, [sp, #0xc00]
100009484: 6e72dc21    	fmul.2d	v1, v1, v18
100009488: 4e61d401    	fadd.2d	v1, v0, v1
10000948c: 3dc10d00    	ldr	q0, [x8, #0x430]
100009490: 3dc2b3e2    	ldr	q2, [sp, #0xac0]
100009494: 4fc09042    	fmul.2d	v2, v2, v0[0]
100009498: 4e62d422    	fadd.2d	v2, v1, v2
10000949c: 9110e109    	add	x9, x8, #0x438
1000094a0: 3dc00121    	ldr	q1, [x9]
1000094a4: 3dc31fe3    	ldr	q3, [sp, #0xc70]
1000094a8: 4fc19063    	fmul.2d	v3, v3, v1[0]
1000094ac: 4e63d443    	fadd.2d	v3, v2, v3
1000094b0: 3dc11102    	ldr	q2, [x8, #0x440]
1000094b4: 3dc2ffe4    	ldr	q4, [sp, #0xbf0]
1000094b8: 4fc29084    	fmul.2d	v4, v4, v2[0]
1000094bc: 4e64d464    	fadd.2d	v4, v3, v4
1000094c0: 91112109    	add	x9, x8, #0x448
1000094c4: 3dc00123    	ldr	q3, [x9]
1000094c8: 3dc31be5    	ldr	q5, [sp, #0xc60]
1000094cc: 4fc390a5    	fmul.2d	v5, v5, v3[0]
1000094d0: 4e65d485    	fadd.2d	v5, v4, v5
1000094d4: 3dc11504    	ldr	q4, [x8, #0x450]
1000094d8: 3dc317e6    	ldr	q6, [sp, #0xc50]
1000094dc: 4fc490c6    	fmul.2d	v6, v6, v4[0]
1000094e0: 4e66d4a6    	fadd.2d	v6, v5, v6
1000094e4: 91116109    	add	x9, x8, #0x458
1000094e8: 3dc00125    	ldr	q5, [x9]
1000094ec: 3dc2fbe7    	ldr	q7, [sp, #0xbe0]
1000094f0: 4fc590e7    	fmul.2d	v7, v7, v5[0]
1000094f4: 4e67d4c7    	fadd.2d	v7, v6, v7
1000094f8: 3dc11906    	ldr	q6, [x8, #0x460]
1000094fc: 3dc2f7f0    	ldr	q16, [sp, #0xbd0]
100009500: 4fc69210    	fmul.2d	v16, v16, v6[0]
100009504: 4e70d4f0    	fadd.2d	v16, v7, v16
100009508: 9111a109    	add	x9, x8, #0x468
10000950c: 3dc00127    	ldr	q7, [x9]
100009510: 3dc2f3ee    	ldr	q14, [sp, #0xbc0]
100009514: 4fc791ce    	fmul.2d	v14, v14, v7[0]
100009518: 4e6ed610    	fadd.2d	v16, v16, v14
10000951c: 3d81a3f0    	str	q16, [sp, #0x680]
100009520: 9110a108    	add	x8, x8, #0x428
100009524: 3dc2eff0    	ldr	q16, [sp, #0xbb0]
100009528: 4fd2920e    	fmul.2d	v14, v16, v18[0]
10000952c: 3dc00110    	ldr	q16, [x8]
100009530: 3dc2ebef    	ldr	q15, [sp, #0xba0]
100009534: 4fd091ef    	fmul.2d	v15, v15, v16[0]
100009538: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000953c: 3dc28bef    	ldr	q15, [sp, #0xa20]
100009540: 4fc091ef    	fmul.2d	v15, v15, v0[0]
100009544: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009548: 3dc287ef    	ldr	q15, [sp, #0xa10]
10000954c: 4fc191ef    	fmul.2d	v15, v15, v1[0]
100009550: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009554: 3dc267ef    	ldr	q15, [sp, #0x990]
100009558: 4fc291ef    	fmul.2d	v15, v15, v2[0]
10000955c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009560: 3dc2e7ef    	ldr	q15, [sp, #0xb90]
100009564: 4fc391ef    	fmul.2d	v15, v15, v3[0]
100009568: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000956c: 3dc2bbef    	ldr	q15, [sp, #0xae0]
100009570: 4fc491ef    	fmul.2d	v15, v15, v4[0]
100009574: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009578: 3dc283ef    	ldr	q15, [sp, #0xa00]
10000957c: 4fc591ef    	fmul.2d	v15, v15, v5[0]
100009580: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009584: 3dc263ef    	ldr	q15, [sp, #0x980]
100009588: 4fc691ef    	fmul.2d	v15, v15, v6[0]
10000958c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009590: 3dc2b7ef    	ldr	q15, [sp, #0xad0]
100009594: 4fc791ef    	fmul.2d	v15, v15, v7[0]
100009598: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000959c: 3d819bee    	str	q14, [sp, #0x660]
1000095a0: 3dc2afee    	ldr	q14, [sp, #0xab0]
1000095a4: 4fd291ce    	fmul.2d	v14, v14, v18[0]
1000095a8: 3dc2abef    	ldr	q15, [sp, #0xaa0]
1000095ac: 4fd091ef    	fmul.2d	v15, v15, v16[0]
1000095b0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000095b4: 3dc313ef    	ldr	q15, [sp, #0xc40]
1000095b8: 4fc091ef    	fmul.2d	v15, v15, v0[0]
1000095bc: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000095c0: 3dc2dbef    	ldr	q15, [sp, #0xb60]
1000095c4: 4fc191ef    	fmul.2d	v15, v15, v1[0]
1000095c8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000095cc: 3dc2e3ef    	ldr	q15, [sp, #0xb80]
1000095d0: 4fc291ef    	fmul.2d	v15, v15, v2[0]
1000095d4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000095d8: 3dc30fef    	ldr	q15, [sp, #0xc30]
1000095dc: 4fc391ef    	fmul.2d	v15, v15, v3[0]
1000095e0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000095e4: 3dc30bef    	ldr	q15, [sp, #0xc20]
1000095e8: 4fc491ef    	fmul.2d	v15, v15, v4[0]
1000095ec: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000095f0: 3dc2a3ef    	ldr	q15, [sp, #0xa80]
1000095f4: 4fc591ef    	fmul.2d	v15, v15, v5[0]
1000095f8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000095fc: 3dc277ef    	ldr	q15, [sp, #0x9d0]
100009600: 4fc691ef    	fmul.2d	v15, v15, v6[0]
100009604: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009608: 3dc25bef    	ldr	q15, [sp, #0x960]
10000960c: 4fc791ef    	fmul.2d	v15, v15, v7[0]
100009610: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009614: 3d8193ee    	str	q14, [sp, #0x640]
100009618: 3dc2dfee    	ldr	q14, [sp, #0xb70]
10000961c: 4fd291ce    	fmul.2d	v14, v14, v18[0]
100009620: 3dc2a7ef    	ldr	q15, [sp, #0xa90]
100009624: 4fd091ef    	fmul.2d	v15, v15, v16[0]
100009628: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000962c: 3dc2cbef    	ldr	q15, [sp, #0xb20]
100009630: 4fc091ef    	fmul.2d	v15, v15, v0[0]
100009634: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009638: 3dc27fef    	ldr	q15, [sp, #0x9f0]
10000963c: 4fc191ef    	fmul.2d	v15, v15, v1[0]
100009640: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009644: 3dc25fef    	ldr	q15, [sp, #0x970]
100009648: 4fc291ef    	fmul.2d	v15, v15, v2[0]
10000964c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009650: 3dc2d7ef    	ldr	q15, [sp, #0xb50]
100009654: 4fc391ef    	fmul.2d	v15, v15, v3[0]
100009658: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000965c: 4fc491af    	fmul.2d	v15, v13, v4[0]
100009660: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009664: 3dc29fed    	ldr	q13, [sp, #0xa70]
100009668: 4fc591af    	fmul.2d	v15, v13, v5[0]
10000966c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100009670: 3dc2cfed    	ldr	q13, [sp, #0xb30]
100009674: 4fc691af    	fmul.2d	v15, v13, v6[0]
100009678: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000967c: 4fc7938f    	fmul.2d	v15, v28, v7[0]
100009680: 4e6fd5dc    	fadd.2d	v28, v14, v15
100009684: 3d818ffc    	str	q28, [sp, #0x630]
100009688: 4fd293bd    	fmul.2d	v29, v29, v18[0]
10000968c: 4fd0915c    	fmul.2d	v28, v10, v16[0]
100009690: 4e7cd7bc    	fadd.2d	v28, v29, v28
100009694: 4fc0917d    	fmul.2d	v29, v11, v0[0]
100009698: 4e7dd79c    	fadd.2d	v28, v28, v29
10000969c: 4fc193dd    	fmul.2d	v29, v30, v1[0]
1000096a0: 4e7dd79c    	fadd.2d	v28, v28, v29
1000096a4: 4fc2919d    	fmul.2d	v29, v12, v2[0]
1000096a8: 4e7dd79c    	fadd.2d	v28, v28, v29
1000096ac: 3dc2c3fd    	ldr	q29, [sp, #0xb00]
1000096b0: 4fc393bd    	fmul.2d	v29, v29, v3[0]
1000096b4: 4e7dd79c    	fadd.2d	v28, v28, v29
1000096b8: 4fc493fd    	fmul.2d	v29, v31, v4[0]
1000096bc: 4e7dd79c    	fadd.2d	v28, v28, v29
1000096c0: 3dc2bffd    	ldr	q29, [sp, #0xaf0]
1000096c4: 4fc593bd    	fmul.2d	v29, v29, v5[0]
1000096c8: 4e7dd79c    	fadd.2d	v28, v28, v29
1000096cc: 4fc6911d    	fmul.2d	v29, v8, v6[0]
1000096d0: 4e7dd79c    	fadd.2d	v28, v28, v29
1000096d4: 4fc7913d    	fmul.2d	v29, v9, v7[0]
1000096d8: 4e7dd79c    	fadd.2d	v28, v28, v29
1000096dc: 3d81a7fc    	str	q28, [sp, #0x690]
1000096e0: 4fd29272    	fmul.2d	v18, v19, v18[0]
1000096e4: 4fd09230    	fmul.2d	v16, v17, v16[0]
1000096e8: 4e70d650    	fadd.2d	v16, v18, v16
1000096ec: 4fc09360    	fmul.2d	v0, v27, v0[0]
1000096f0: 4e60d600    	fadd.2d	v0, v16, v0
1000096f4: 4fc19341    	fmul.2d	v1, v26, v1[0]
1000096f8: 4e61d400    	fadd.2d	v0, v0, v1
1000096fc: 4fc29321    	fmul.2d	v1, v25, v2[0]
100009700: 4e61d400    	fadd.2d	v0, v0, v1
100009704: 4fc39301    	fmul.2d	v1, v24, v3[0]
100009708: 4e61d400    	fadd.2d	v0, v0, v1
10000970c: 4fc492e1    	fmul.2d	v1, v23, v4[0]
100009710: 4e61d400    	fadd.2d	v0, v0, v1
100009714: 4fc592c1    	fmul.2d	v1, v22, v5[0]
100009718: 4e61d400    	fadd.2d	v0, v0, v1
10000971c: 4fc692a1    	fmul.2d	v1, v21, v6[0]
100009720: 4e61d400    	fadd.2d	v0, v0, v1
100009724: 4fc79281    	fmul.2d	v1, v20, v7[0]
100009728: 4e61d41a    	fadd.2d	v26, v0, v1
10000972c: 54000325    	b.pl	0x100009790 <_codegen_qseries_nonzero_12x10+0x26c8>
100009730: 4eba1f5c    	mov.16b	v28, v26
100009734: ad527bee    	ldp	q14, q30, [sp, #0x240]
100009738: 3dc257e4    	ldr	q4, [sp, #0x950]
10000973c: 3dc0d7ef    	ldr	q15, [sp, #0x350]
100009740: ad4db7ff    	ldp	q31, q13, [sp, #0x1b0]
100009744: ad4caff5    	ldp	q21, q11, [sp, #0x190]
100009748: ad4787fa    	ldp	q26, q1, [sp, #0xf0]
10000974c: 3dc17bf6    	ldr	q22, [sp, #0x5e0]
100009750: ad48abe0    	ldp	q0, q10, [sp, #0x110]
100009754: 3dc1b3e3    	ldr	q3, [sp, #0x6c0]
100009758: 3dc18be5    	ldr	q5, [sp, #0x620]
10000975c: 3dc187e7    	ldr	q7, [sp, #0x610]
100009760: 3dc183f1    	ldr	q17, [sp, #0x600]
100009764: 3dc17ff0    	ldr	q16, [sp, #0x5f0]
100009768: 3dc177f4    	ldr	q20, [sp, #0x5d0]
10000976c: 3dc173f3    	ldr	q19, [sp, #0x5c0]
100009770: ad4a1be8    	ldp	q8, q6, [sp, #0x140]
100009774: ad4bdff9    	ldp	q25, q23, [sp, #0x170]
100009778: 3dc04ff8    	ldr	q24, [sp, #0x130]
10000977c: ad46cbfb    	ldp	q27, q18, [sp, #0xd0]
100009780: ad45f7ec    	ldp	q12, q29, [sp, #0xb0]
100009784: 3dc16fe2    	ldr	q2, [sp, #0x5b0]
100009788: 3dc05be9    	ldr	q9, [sp, #0x160]
10000978c: 14000624    	b	0x10000b01c <_codegen_qseries_nonzero_12x10+0x3f54>
100009790: d2800008    	mov	x8, #0x0                ; =0
100009794: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100009798: 3dc37521    	ldr	q1, [x9, #0xdd0]
10000979c: 3dc257e0    	ldr	q0, [sp, #0x950]
1000097a0: 4ee0d422    	fsub.2d	v2, v1, v0
1000097a4: 6f00e400    	movi.2d	v0, #0000000000000000
1000097a8: ad4c57f7    	ldp	q23, q21, [sp, #0x180]
1000097ac: 4ef5d403    	fsub.2d	v3, v0, v21
1000097b0: 3d8323e2    	str	q2, [sp, #0xc80]
1000097b4: 3d8327e3    	str	q3, [sp, #0xc90]
1000097b8: 3dc243e7    	ldr	q7, [sp, #0x900]
1000097bc: 4ee7d402    	fsub.2d	v2, v0, v7
1000097c0: ad46bbfb    	ldp	q27, q14, [sp, #0xd0]
1000097c4: 4eeed403    	fsub.2d	v3, v0, v14
1000097c8: 3d832be2    	str	q2, [sp, #0xca0]
1000097cc: 3d832fe3    	str	q3, [sp, #0xcb0]
1000097d0: 3dc08be2    	ldr	q2, [sp, #0x220]
1000097d4: 4ee2d403    	fsub.2d	v3, v0, v2
1000097d8: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000097dc: 3dc37922    	ldr	q2, [x9, #0xde0]
1000097e0: 3dc253e4    	ldr	q4, [sp, #0x940]
1000097e4: 4ee4d444    	fsub.2d	v4, v2, v4
1000097e8: 3d8333e3    	str	q3, [sp, #0xcc0]
1000097ec: 3d8337e4    	str	q4, [sp, #0xcd0]
1000097f0: 4ef7d403    	fsub.2d	v3, v0, v23
1000097f4: 3dc05ff9    	ldr	q25, [sp, #0x170]
1000097f8: 4ef9d404    	fsub.2d	v4, v0, v25
1000097fc: 3d833be3    	str	q3, [sp, #0xce0]
100009800: 3d833fe4    	str	q4, [sp, #0xcf0]
100009804: 4efbd403    	fsub.2d	v3, v0, v27
100009808: 3dc23fef    	ldr	q15, [sp, #0x8f0]
10000980c: 4eefd404    	fsub.2d	v4, v0, v15
100009810: 3d8343e3    	str	q3, [sp, #0xd00]
100009814: 3d8347e4    	str	q4, [sp, #0xd10]
100009818: ad52c7e4    	ldp	q4, q17, [sp, #0x250]
10000981c: 4ef1d403    	fsub.2d	v3, v0, v17
100009820: 4ee4d424    	fsub.2d	v4, v1, v4
100009824: 3d834be3    	str	q3, [sp, #0xd20]
100009828: 3d834fe4    	str	q4, [sp, #0xd30]
10000982c: ad598fe4    	ldp	q4, q3, [sp, #0x330]
100009830: 4ee3d403    	fsub.2d	v3, v0, v3
100009834: 4ee4d404    	fsub.2d	v4, v0, v4
100009838: 3d8353e3    	str	q3, [sp, #0xd40]
10000983c: 3d8357e4    	str	q4, [sp, #0xd50]
100009840: ad4aafe6    	ldp	q6, q11, [sp, #0x150]
100009844: 4eebd403    	fsub.2d	v3, v0, v11
100009848: 4ee6d404    	fsub.2d	v4, v0, v6
10000984c: 3d835be3    	str	q3, [sp, #0xd60]
100009850: 3d835fe4    	str	q4, [sp, #0xd70]
100009854: 3dc0d7e3    	ldr	q3, [sp, #0x350]
100009858: 4ee3d443    	fsub.2d	v3, v2, v3
10000985c: 3dc0c7e4    	ldr	q4, [sp, #0x310]
100009860: 4ee4d404    	fsub.2d	v4, v0, v4
100009864: 3d8363e3    	str	q3, [sp, #0xd80]
100009868: 3d8367e4    	str	q4, [sp, #0xd90]
10000986c: 3dc0bfe3    	ldr	q3, [sp, #0x2f0]
100009870: 4ee3d403    	fsub.2d	v3, v0, v3
100009874: 3dc033fd    	ldr	q29, [sp, #0xc0]
100009878: 4efdd404    	fsub.2d	v4, v0, v29
10000987c: 3d836be3    	str	q3, [sp, #0xda0]
100009880: 3d836fe4    	str	q4, [sp, #0xdb0]
100009884: ad49a3f8    	ldp	q24, q8, [sp, #0x130]
100009888: 4ee8d403    	fsub.2d	v3, v0, v8
10000988c: 4ef8d404    	fsub.2d	v4, v0, v24
100009890: 3d8373e3    	str	q3, [sp, #0xdc0]
100009894: 3d8377e4    	str	q4, [sp, #0xdd0]
100009898: 3dc093e3    	ldr	q3, [sp, #0x240]
10000989c: 4ee3d423    	fsub.2d	v3, v1, v3
1000098a0: 3dc087e4    	ldr	q4, [sp, #0x210]
1000098a4: 4ee4d404    	fsub.2d	v4, v0, v4
1000098a8: 3d837be3    	str	q3, [sp, #0xde0]
1000098ac: 3d837fe4    	str	q4, [sp, #0xdf0]
1000098b0: 3dc0b3e3    	ldr	q3, [sp, #0x2c0]
1000098b4: 4ee3d403    	fsub.2d	v3, v0, v3
1000098b8: 3dc04bea    	ldr	q10, [sp, #0x120]
1000098bc: 4eead404    	fsub.2d	v4, v0, v10
1000098c0: 3d8383e3    	str	q3, [sp, #0xe00]
1000098c4: 3d8387e4    	str	q4, [sp, #0xe10]
1000098c8: 3dc02fec    	ldr	q12, [sp, #0xb0]
1000098cc: 4eecd403    	fsub.2d	v3, v0, v12
1000098d0: ad4db7e5    	ldp	q5, q13, [sp, #0x1b0]
1000098d4: 4eedd444    	fsub.2d	v4, v2, v13
1000098d8: 3d838be3    	str	q3, [sp, #0xe20]
1000098dc: 3d838fe4    	str	q4, [sp, #0xe30]
1000098e0: ad4f8fe4    	ldp	q4, q3, [sp, #0x1f0]
1000098e4: 4ee3d403    	fsub.2d	v3, v0, v3
1000098e8: 4ee4d404    	fsub.2d	v4, v0, v4
1000098ec: 3d8393e3    	str	q3, [sp, #0xe40]
1000098f0: 3d8397e4    	str	q4, [sp, #0xe50]
1000098f4: 3dc0cbe3    	ldr	q3, [sp, #0x320]
1000098f8: 4ee3d403    	fsub.2d	v3, v0, v3
1000098fc: 3dc0c3e4    	ldr	q4, [sp, #0x300]
100009900: 4ee4d404    	fsub.2d	v4, v0, v4
100009904: 3d839be3    	str	q3, [sp, #0xe60]
100009908: 3d839fe4    	str	q4, [sp, #0xe70]
10000990c: 3dc23bff    	ldr	q31, [sp, #0x8e0]
100009910: 4effd403    	fsub.2d	v3, v0, v31
100009914: 4ee5d424    	fsub.2d	v4, v1, v5
100009918: 3d83a3e3    	str	q3, [sp, #0xe80]
10000991c: 3d83a7e4    	str	q4, [sp, #0xe90]
100009920: 3dc07be3    	ldr	q3, [sp, #0x1e0]
100009924: 4ee3d403    	fsub.2d	v3, v0, v3
100009928: 3dc0bbe4    	ldr	q4, [sp, #0x2e0]
10000992c: 4ee4d404    	fsub.2d	v4, v0, v4
100009930: 3d83abe3    	str	q3, [sp, #0xea0]
100009934: 3d83afe4    	str	q4, [sp, #0xeb0]
100009938: 3dc0b7e3    	ldr	q3, [sp, #0x2d0]
10000993c: 4ee3d403    	fsub.2d	v3, v0, v3
100009940: 3dc24fe4    	ldr	q4, [sp, #0x930]
100009944: 4ee4d404    	fsub.2d	v4, v0, v4
100009948: 3d83b3e3    	str	q3, [sp, #0xec0]
10000994c: 3d83b7e4    	str	q4, [sp, #0xed0]
100009950: 3dc08fe3    	ldr	q3, [sp, #0x230]
100009954: 4ee3d443    	fsub.2d	v3, v2, v3
100009958: 3dc077e4    	ldr	q4, [sp, #0x1d0]
10000995c: 4ee4d404    	fsub.2d	v4, v0, v4
100009960: 3d83bbe3    	str	q3, [sp, #0xee0]
100009964: 3d83bfe4    	str	q4, [sp, #0xef0]
100009968: ad550fe4    	ldp	q4, q3, [sp, #0x2a0]
10000996c: 4ee3d403    	fsub.2d	v3, v0, v3
100009970: 4ee4d404    	fsub.2d	v4, v0, v4
100009974: 3d83c3e3    	str	q3, [sp, #0xf00]
100009978: 3d83c7e4    	str	q4, [sp, #0xf10]
10000997c: 3dc237f4    	ldr	q20, [sp, #0x8d0]
100009980: 4ef4d403    	fsub.2d	v3, v0, v20
100009984: 3dc24be4    	ldr	q4, [sp, #0x920]
100009988: 4ee4d404    	fsub.2d	v4, v0, v4
10000998c: 3d83cbe3    	str	q3, [sp, #0xf20]
100009990: 3d83cfe4    	str	q4, [sp, #0xf30]
100009994: 3dc06bf3    	ldr	q19, [sp, #0x1a0]
100009998: 4ef3d421    	fsub.2d	v1, v1, v19
10000999c: 3dc0a7e3    	ldr	q3, [sp, #0x290]
1000099a0: 4ee3d403    	fsub.2d	v3, v0, v3
1000099a4: 3d83d3e1    	str	q1, [sp, #0xf40]
1000099a8: 3d83d7e3    	str	q3, [sp, #0xf50]
1000099ac: ad5387e3    	ldp	q3, q1, [sp, #0x270]
1000099b0: 4ee1d401    	fsub.2d	v1, v0, v1
1000099b4: 4ee3d403    	fsub.2d	v3, v0, v3
1000099b8: 3d83dbe1    	str	q1, [sp, #0xf60]
1000099bc: 3d83dfe3    	str	q3, [sp, #0xf70]
1000099c0: 3dc247e1    	ldr	q1, [sp, #0x910]
1000099c4: 4ee1d400    	fsub.2d	v0, v0, v1
1000099c8: 3dc03ffe    	ldr	q30, [sp, #0xf0]
1000099cc: 4efed441    	fsub.2d	v1, v2, v30
1000099d0: 3d83e3e0    	str	q0, [sp, #0xf80]
1000099d4: 3d83e7e1    	str	q1, [sp, #0xf90]
1000099d8: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000099dc: 3dc38120    	ldr	q0, [x9, #0xe00]
1000099e0: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000099e4: 3dc38521    	ldr	q1, [x9, #0xe10]
1000099e8: 3d83efe1    	str	q1, [sp, #0xfb0]
1000099ec: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000099f0: 3dc38921    	ldr	q1, [x9, #0xe20]
1000099f4: 3d83ffe0    	str	q0, [sp, #0xff0]
1000099f8: 3d8403e1    	str	q1, [sp, #0x1000]
1000099fc: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100009a00: 3dc38d20    	ldr	q0, [x9, #0xe30]
100009a04: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100009a08: 3dc39521    	ldr	q1, [x9, #0xe50]
100009a0c: 3d83f3e0    	str	q0, [sp, #0xfc0]
100009a10: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100009a14: 3dc39120    	ldr	q0, [x9, #0xe40]
100009a18: 3d83f7e1    	str	q1, [sp, #0xfd0]
100009a1c: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100009a20: 3dc39921    	ldr	q1, [x9, #0xe60]
100009a24: 3d8407e0    	str	q0, [sp, #0x1010]
100009a28: 3d840be1    	str	q1, [sp, #0x1020]
100009a2c: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100009a30: 3dc39d20    	ldr	q0, [x9, #0xe70]
100009a34: 3d83fbe0    	str	q0, [sp, #0xfe0]
100009a38: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100009a3c: 3dc3a120    	ldr	q0, [x9, #0xe80]
100009a40: 3d840fe0    	str	q0, [sp, #0x1030]
100009a44: d0000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100009a48: 3dc37d22    	ldr	q2, [x9, #0xdf0]
100009a4c: 3d83ebe2    	str	q2, [sp, #0xfa0]
100009a50: 5280012f    	mov	w15, #0x9               ; =9
100009a54: 52800029    	mov	w9, #0x1                ; =1
100009a58: 913fc3ea    	add	x10, sp, #0xff0
100009a5c: 913203eb    	add	x11, sp, #0xc80
100009a60: d298540c    	mov	x12, #0xc2a0            ; =49824
100009a64: f2bfdd6c    	movk	x12, #0xfeeb, lsl #16
100009a68: f2c9096c    	movk	x12, #0x484b, lsl #32
100009a6c: f2e7368c    	movk	x12, #0x39b4, lsl #48
100009a70: 913e83ed    	add	x13, sp, #0xfa0
100009a74: f10005ee    	subs	x14, x15, #0x1
100009a78: f8687950    	ldr	x16, [x10, x8, lsl #3]
100009a7c: 9a9f85ef    	csinc	x15, x15, xzr, hi
100009a80: 8b080211    	add	x17, x16, x8
100009a84: fc717960    	ldr	d0, [x11, x17, lsl #3]
100009a88: 1e60c001    	fabs	d1, d0
100009a8c: f100251f    	cmp	x8, #0x9
100009a90: 54000061    	b.ne	0x100009a9c <_codegen_qseries_nonzero_12x10+0x29d4>
100009a94: 52800131    	mov	w17, #0x9               ; =9
100009a98: 1400000f    	b	0x100009ad4 <_codegen_qseries_nonzero_12x10+0x2a0c>
100009a9c: aa0903e0    	mov	x0, x9
100009aa0: aa0f03e1    	mov	x1, x15
100009aa4: 1e604023    	fmov	d3, d1
100009aa8: aa0803f1    	mov	x17, x8
100009aac: f8607942    	ldr	x2, [x10, x0, lsl #3]
100009ab0: 8b080042    	add	x2, x2, x8
100009ab4: fc627964    	ldr	d4, [x11, x2, lsl #3]
100009ab8: 1e60c084    	fabs	d4, d4
100009abc: 1e632080    	fcmp	d4, d3
100009ac0: 9a91c011    	csel	x17, x0, x17, gt
100009ac4: 1e63cc83    	fcsel	d3, d4, d3, gt
100009ac8: 91000400    	add	x0, x0, #0x1
100009acc: f1000421    	subs	x1, x1, #0x1
100009ad0: 54fffee1    	b.ne	0x100009aac <_codegen_qseries_nonzero_12x10+0x29e4>
100009ad4: eb08023f    	cmp	x17, x8
100009ad8: 54000180    	b.eq	0x100009b08 <_codegen_qseries_nonzero_12x10+0x2a40>
100009adc: f86879a0    	ldr	x0, [x13, x8, lsl #3]
100009ae0: f87179a1    	ldr	x1, [x13, x17, lsl #3]
100009ae4: f82879a1    	str	x1, [x13, x8, lsl #3]
100009ae8: f83179a0    	str	x0, [x13, x17, lsl #3]
100009aec: f8717940    	ldr	x0, [x10, x17, lsl #3]
100009af0: f8287940    	str	x0, [x10, x8, lsl #3]
100009af4: f8317950    	str	x16, [x10, x17, lsl #3]
100009af8: f8687950    	ldr	x16, [x10, x8, lsl #3]
100009afc: 8b080211    	add	x17, x16, x8
100009b00: fc717960    	ldr	d0, [x11, x17, lsl #3]
100009b04: 1e60c001    	fabs	d1, d0
100009b08: 9e670183    	fmov	d3, x12
100009b0c: 1e632020    	fcmp	d1, d3
100009b10: 540003e4    	b.mi	0x100009b8c <_codegen_qseries_nonzero_12x10+0x2ac4>
100009b14: f100251f    	cmp	x8, #0x9
100009b18: 54000640    	b.eq	0x100009be0 <_codegen_qseries_nonzero_12x10+0x2b18>
100009b1c: d2800000    	mov	x0, #0x0                ; =0
100009b20: 91000511    	add	x17, x8, #0x1
100009b24: 8b090210    	add	x16, x16, x9
100009b28: 8b100d70    	add	x16, x11, x16, lsl #3
100009b2c: 8b110001    	add	x1, x0, x17
100009b30: f8617941    	ldr	x1, [x10, x1, lsl #3]
100009b34: 8b080022    	add	x2, x1, x8
100009b38: fc627961    	ldr	d1, [x11, x2, lsl #3]
100009b3c: 1e601821    	fdiv	d1, d1, d0
100009b40: fc227961    	str	d1, [x11, x2, lsl #3]
100009b44: 8b010121    	add	x1, x9, x1
100009b48: 8b010d61    	add	x1, x11, x1, lsl #3
100009b4c: aa1003e2    	mov	x2, x16
100009b50: aa0f03e3    	mov	x3, x15
100009b54: fc408443    	ldr	d3, [x2], #0x8
100009b58: fd400024    	ldr	d4, [x1]
100009b5c: 1e630823    	fmul	d3, d1, d3
100009b60: 1e633883    	fsub	d3, d4, d3
100009b64: fc008423    	str	d3, [x1], #0x8
100009b68: f1000463    	subs	x3, x3, #0x1
100009b6c: 54ffff41    	b.ne	0x100009b54 <_codegen_qseries_nonzero_12x10+0x2a8c>
100009b70: 91000400    	add	x0, x0, #0x1
100009b74: eb0f001f    	cmp	x0, x15
100009b78: 54fffda1    	b.ne	0x100009b2c <_codegen_qseries_nonzero_12x10+0x2a64>
100009b7c: 91000529    	add	x9, x9, #0x1
100009b80: aa0e03ef    	mov	x15, x14
100009b84: aa1103e8    	mov	x8, x17
100009b88: 17ffffbb    	b	0x100009a74 <_codegen_qseries_nonzero_12x10+0x29ac>
100009b8c: 4eb31e64    	mov.16b	v4, v19
100009b90: 4eba1f5c    	mov.16b	v28, v26
100009b94: 3dc17bf6    	ldr	q22, [sp, #0x5e0]
100009b98: ad4803e1    	ldp	q1, q0, [sp, #0x100]
100009b9c: 3dc1b3e3    	ldr	q3, [sp, #0x6c0]
100009ba0: 4ea51cbf    	mov.16b	v31, v5
100009ba4: 3dc18be5    	ldr	q5, [sp, #0x620]
100009ba8: 3dc187e7    	ldr	q7, [sp, #0x610]
100009bac: 4eae1dd2    	mov.16b	v18, v14
100009bb0: 4eab1d69    	mov.16b	v9, v11
100009bb4: 3dc183f1    	ldr	q17, [sp, #0x600]
100009bb8: 3dc17ff0    	ldr	q16, [sp, #0x5f0]
100009bbc: 4ebe1fda    	mov.16b	v26, v30
100009bc0: 3dc177f4    	ldr	q20, [sp, #0x5d0]
100009bc4: ad527bee    	ldp	q14, q30, [sp, #0x240]
100009bc8: 3dc173f3    	ldr	q19, [sp, #0x5c0]
100009bcc: 3dc16fe2    	ldr	q2, [sp, #0x5b0]
100009bd0: 4ea41c8b    	mov.16b	v11, v4
100009bd4: 3dc0d7ef    	ldr	q15, [sp, #0x350]
100009bd8: 3dc257e4    	ldr	q4, [sp, #0x950]
100009bdc: 14000510    	b	0x10000b01c <_codegen_qseries_nonzero_12x10+0x3f54>
100009be0: 3d816bfa    	str	q26, [sp, #0x5a0]
100009be4: d2800008    	mov	x8, #0x0                ; =0
100009be8: 913203e9    	add	x9, sp, #0xc80
100009bec: f947fbea    	ldr	x10, [sp, #0xff0]
100009bf0: f947ffeb    	ldr	x11, [sp, #0xff8]
100009bf4: 8b0b0d2b    	add	x11, x9, x11, lsl #3
100009bf8: 9100216c    	add	x12, x11, #0x8
100009bfc: f94803ed    	ldr	x13, [sp, #0x1000]
100009c00: f94807ef    	ldr	x15, [sp, #0x1008]
100009c04: 8b0d0d2d    	add	x13, x9, x13, lsl #3
100009c08: 910041ae    	add	x14, x13, #0x10
100009c0c: f9480bf1    	ldr	x17, [sp, #0x1010]
100009c10: f9480fe1    	ldr	x1, [sp, #0x1018]
100009c14: 8b0f0d2f    	add	x15, x9, x15, lsl #3
100009c18: 910061f0    	add	x16, x15, #0x18
100009c1c: f94813e3    	ldr	x3, [sp, #0x1020]
100009c20: f94817e6    	ldr	x6, [sp, #0x1028]
100009c24: 8b110d31    	add	x17, x9, x17, lsl #3
100009c28: 91008220    	add	x0, x17, #0x20
100009c2c: f9481bf3    	ldr	x19, [sp, #0x1030]
100009c30: f9481ff5    	ldr	x21, [sp, #0x1038]
100009c34: 8b010d21    	add	x1, x9, x1, lsl #3
100009c38: 9100a022    	add	x2, x1, #0x28
100009c3c: 913e83f8    	add	x24, sp, #0xfa0
100009c40: 4d40cf00    	ld1r.2d	{ v0 }, [x24]
100009c44: 3d831fe0    	str	q0, [sp, #0xc70]
100009c48: fd47f7e0    	ldr	d0, [sp, #0xfe8]
100009c4c: 8b030d24    	add	x4, x9, x3, lsl #3
100009c50: 9100c085    	add	x5, x4, #0x30
100009c54: b27d0303    	orr	x3, x24, #0x8
100009c58: 4d40cc61    	ld1r.2d	{ v1 }, [x3]
100009c5c: 3d831be1    	str	q1, [sp, #0xc60]
100009c60: 91004303    	add	x3, x24, #0x10
100009c64: 4d40cc61    	ld1r.2d	{ v1 }, [x3]
100009c68: 3d8317e1    	str	q1, [sp, #0xc50]
100009c6c: 8b060d26    	add	x6, x9, x6, lsl #3
100009c70: 9100e0c7    	add	x7, x6, #0x38
100009c74: 91006303    	add	x3, x24, #0x18
100009c78: fd400161    	ldr	d1, [x11]
100009c7c: 3d8313e1    	str	q1, [sp, #0xc40]
100009c80: 4d40cc61    	ld1r.2d	{ v1 }, [x3]
100009c84: 3d830fe1    	str	q1, [sp, #0xc30]
100009c88: 8b130d33    	add	x19, x9, x19, lsl #3
100009c8c: 91010274    	add	x20, x19, #0x40
100009c90: fd4001a1    	ldr	d1, [x13]
100009c94: 3d830be1    	str	q1, [sp, #0xc20]
100009c98: fd4005a1    	ldr	d1, [x13, #0x8]
100009c9c: 3d8307e1    	str	q1, [sp, #0xc10]
100009ca0: 8b150d35    	add	x21, x9, x21, lsl #3
100009ca4: 910122b6    	add	x22, x21, #0x48
100009ca8: 91010317    	add	x23, x24, #0x40
100009cac: 9100e319    	add	x25, x24, #0x38
100009cb0: 9100c31a    	add	x26, x24, #0x30
100009cb4: 9100a31b    	add	x27, x24, #0x28
100009cb8: 91008318    	add	x24, x24, #0x20
100009cbc: fd4001e1    	ldr	d1, [x15]
100009cc0: 3d8303e1    	str	q1, [sp, #0xc00]
100009cc4: fd4005e1    	ldr	d1, [x15, #0x8]
100009cc8: 3d82ffe1    	str	q1, [sp, #0xbf0]
100009ccc: 8b0a0d23    	add	x3, x9, x10, lsl #3
100009cd0: fd4009e1    	ldr	d1, [x15, #0x10]
100009cd4: 3d82fbe1    	str	q1, [sp, #0xbe0]
100009cd8: 4d40cf01    	ld1r.2d	{ v1 }, [x24]
100009cdc: 3d82f7e1    	str	q1, [sp, #0xbd0]
100009ce0: fd400221    	ldr	d1, [x17]
100009ce4: 3d82f3e1    	str	q1, [sp, #0xbc0]
100009ce8: fd400621    	ldr	d1, [x17, #0x8]
100009cec: 3d82efe1    	str	q1, [sp, #0xbb0]
100009cf0: fd400a21    	ldr	d1, [x17, #0x10]
100009cf4: 3d82ebe1    	str	q1, [sp, #0xba0]
100009cf8: fd400e21    	ldr	d1, [x17, #0x18]
100009cfc: 3d82e7e1    	str	q1, [sp, #0xb90]
100009d00: 4d40cf61    	ld1r.2d	{ v1 }, [x27]
100009d04: 3d82e3e1    	str	q1, [sp, #0xb80]
100009d08: fd400021    	ldr	d1, [x1]
100009d0c: 3d82dfe1    	str	q1, [sp, #0xb70]
100009d10: fd400421    	ldr	d1, [x1, #0x8]
100009d14: 3d82dbe1    	str	q1, [sp, #0xb60]
100009d18: fd400821    	ldr	d1, [x1, #0x10]
100009d1c: 3d82d7e1    	str	q1, [sp, #0xb50]
100009d20: fd400c21    	ldr	d1, [x1, #0x18]
100009d24: 3d82d3e1    	str	q1, [sp, #0xb40]
100009d28: fd401021    	ldr	d1, [x1, #0x20]
100009d2c: 3d82cfe1    	str	q1, [sp, #0xb30]
100009d30: 4d40cf41    	ld1r.2d	{ v1 }, [x26]
100009d34: 3d82cbe1    	str	q1, [sp, #0xb20]
100009d38: fd400081    	ldr	d1, [x4]
100009d3c: 3d82c7e1    	str	q1, [sp, #0xb10]
100009d40: fd400481    	ldr	d1, [x4, #0x8]
100009d44: 3d82c3e1    	str	q1, [sp, #0xb00]
100009d48: fd400881    	ldr	d1, [x4, #0x10]
100009d4c: 3d82bfe1    	str	q1, [sp, #0xaf0]
100009d50: fd400c81    	ldr	d1, [x4, #0x18]
100009d54: 3d82bbe1    	str	q1, [sp, #0xae0]
100009d58: fd401081    	ldr	d1, [x4, #0x20]
100009d5c: 3d82b7e1    	str	q1, [sp, #0xad0]
100009d60: fd401481    	ldr	d1, [x4, #0x28]
100009d64: 3d82b3e1    	str	q1, [sp, #0xac0]
100009d68: 4d40cf21    	ld1r.2d	{ v1 }, [x25]
100009d6c: 3d82afe1    	str	q1, [sp, #0xab0]
100009d70: fd4000c1    	ldr	d1, [x6]
100009d74: 3d82abe1    	str	q1, [sp, #0xaa0]
100009d78: fd4004c1    	ldr	d1, [x6, #0x8]
100009d7c: 3d82a7e1    	str	q1, [sp, #0xa90]
100009d80: 4e080400    	dup.2d	v0, v0[0]
100009d84: 3d82a3e0    	str	q0, [sp, #0xa80]
100009d88: aa0303f8    	mov	x24, x3
100009d8c: 914007e9    	add	x9, sp, #0x1, lsl #12   ; =0x1000
100009d90: 91010129    	add	x9, x9, #0x40
100009d94: 5280004a    	mov	w10, #0x2               ; =2
100009d98: fd4008c0    	ldr	d0, [x6, #0x10]
100009d9c: 3d829fe0    	str	q0, [sp, #0xa70]
100009da0: fd400cc0    	ldr	d0, [x6, #0x18]
100009da4: 3d829be0    	str	q0, [sp, #0xa60]
100009da8: fd4010c0    	ldr	d0, [x6, #0x20]
100009dac: 3d8297e0    	str	q0, [sp, #0xa50]
100009db0: fd4014c0    	ldr	d0, [x6, #0x28]
100009db4: 3d8293e0    	str	q0, [sp, #0xa40]
100009db8: 4d40cee0    	ld1r.2d	{ v0 }, [x23]
100009dbc: 3d828fe0    	str	q0, [sp, #0xa30]
100009dc0: fd4018c0    	ldr	d0, [x6, #0x30]
100009dc4: 3d828be0    	str	q0, [sp, #0xa20]
100009dc8: fd400260    	ldr	d0, [x19]
100009dcc: 3d8287e0    	str	q0, [sp, #0xa10]
100009dd0: fd400660    	ldr	d0, [x19, #0x8]
100009dd4: 3d8283e0    	str	q0, [sp, #0xa00]
100009dd8: fd400a60    	ldr	d0, [x19, #0x10]
100009ddc: 3d827fe0    	str	q0, [sp, #0x9f0]
100009de0: fd400e60    	ldr	d0, [x19, #0x18]
100009de4: 3d827be0    	str	q0, [sp, #0x9e0]
100009de8: fd401260    	ldr	d0, [x19, #0x20]
100009dec: 3d8277e0    	str	q0, [sp, #0x9d0]
100009df0: fd401660    	ldr	d0, [x19, #0x28]
100009df4: 3d8273e0    	str	q0, [sp, #0x9c0]
100009df8: fd401a60    	ldr	d0, [x19, #0x30]
100009dfc: 3d826fe0    	str	q0, [sp, #0x9b0]
100009e00: fd401e60    	ldr	d0, [x19, #0x38]
100009e04: 3d826be0    	str	q0, [sp, #0x9a0]
100009e08: fd4002a0    	ldr	d0, [x21]
100009e0c: 3d8267e0    	str	q0, [sp, #0x990]
100009e10: fd4006a0    	ldr	d0, [x21, #0x8]
100009e14: 3d8263e0    	str	q0, [sp, #0x980]
100009e18: fd400aa0    	ldr	d0, [x21, #0x10]
100009e1c: 3d825fe0    	str	q0, [sp, #0x970]
100009e20: fd400ea0    	ldr	d0, [x21, #0x18]
100009e24: 3d825be0    	str	q0, [sp, #0x960]
100009e28: fd4012a0    	ldr	d0, [x21, #0x20]
100009e2c: 3d8257e0    	str	q0, [sp, #0x950]
100009e30: fd4016a0    	ldr	d0, [x21, #0x28]
100009e34: 3d8253e0    	str	q0, [sp, #0x940]
100009e38: fd401aa0    	ldr	d0, [x21, #0x30]
100009e3c: 3d824fe0    	str	q0, [sp, #0x930]
100009e40: fd401ea0    	ldr	d0, [x21, #0x38]
100009e44: 3d824be0    	str	q0, [sp, #0x920]
100009e48: fd4022a0    	ldr	d0, [x21, #0x40]
100009e4c: 3d8247e0    	str	q0, [sp, #0x910]
100009e50: 4d40cec0    	ld1r.2d	{ v0 }, [x22]
100009e54: 3d8243e0    	str	q0, [sp, #0x900]
100009e58: fd402660    	ldr	d0, [x19, #0x48]
100009e5c: 3d823fe0    	str	q0, [sp, #0x8f0]
100009e60: 4d40ce80    	ld1r.2d	{ v0 }, [x20]
100009e64: 3d823be0    	str	q0, [sp, #0x8e0]
100009e68: fd4020c0    	ldr	d0, [x6, #0x40]
100009e6c: 3d8237e0    	str	q0, [sp, #0x8d0]
100009e70: fd4024c0    	ldr	d0, [x6, #0x48]
100009e74: 3d8233e0    	str	q0, [sp, #0x8c0]
100009e78: 4d40cce0    	ld1r.2d	{ v0 }, [x7]
100009e7c: 3d822fe0    	str	q0, [sp, #0x8b0]
100009e80: fd401c80    	ldr	d0, [x4, #0x38]
100009e84: 3d822be0    	str	q0, [sp, #0x8a0]
100009e88: fd402080    	ldr	d0, [x4, #0x40]
100009e8c: 3d8227e0    	str	q0, [sp, #0x890]
100009e90: fd402480    	ldr	d0, [x4, #0x48]
100009e94: 3d8223e0    	str	q0, [sp, #0x880]
100009e98: 4d40cca0    	ld1r.2d	{ v0 }, [x5]
100009e9c: 3d821fe0    	str	q0, [sp, #0x870]
100009ea0: fd401820    	ldr	d0, [x1, #0x30]
100009ea4: 3d821be0    	str	q0, [sp, #0x860]
100009ea8: fd401c20    	ldr	d0, [x1, #0x38]
100009eac: 3d8217e0    	str	q0, [sp, #0x850]
100009eb0: fd402020    	ldr	d0, [x1, #0x40]
100009eb4: 3d8213e0    	str	q0, [sp, #0x840]
100009eb8: fd402420    	ldr	d0, [x1, #0x48]
100009ebc: 3d820fe0    	str	q0, [sp, #0x830]
100009ec0: 4d40cc40    	ld1r.2d	{ v0 }, [x2]
100009ec4: 3d820be0    	str	q0, [sp, #0x820]
100009ec8: fd401620    	ldr	d0, [x17, #0x28]
100009ecc: 3d8207e0    	str	q0, [sp, #0x810]
100009ed0: fd401a20    	ldr	d0, [x17, #0x30]
100009ed4: 3d8203e0    	str	q0, [sp, #0x800]
100009ed8: fd401e20    	ldr	d0, [x17, #0x38]
100009edc: 3d81ffe0    	str	q0, [sp, #0x7f0]
100009ee0: fd402220    	ldr	d0, [x17, #0x40]
100009ee4: 3d81fbe0    	str	q0, [sp, #0x7e0]
100009ee8: fd402620    	ldr	d0, [x17, #0x48]
100009eec: 3d81f7e0    	str	q0, [sp, #0x7d0]
100009ef0: 4d40cc00    	ld1r.2d	{ v0 }, [x0]
100009ef4: 3d81f3e0    	str	q0, [sp, #0x7c0]
100009ef8: fd4011e0    	ldr	d0, [x15, #0x20]
100009efc: 3d81efe0    	str	q0, [sp, #0x7b0]
100009f00: fd4015e0    	ldr	d0, [x15, #0x28]
100009f04: 3d81ebe0    	str	q0, [sp, #0x7a0]
100009f08: fd4019e0    	ldr	d0, [x15, #0x30]
100009f0c: 3d81e7e0    	str	q0, [sp, #0x790]
100009f10: fd401de0    	ldr	d0, [x15, #0x38]
100009f14: 3d81e3e0    	str	q0, [sp, #0x780]
100009f18: fd4021e0    	ldr	d0, [x15, #0x40]
100009f1c: 3d81dfe0    	str	q0, [sp, #0x770]
100009f20: fd4025e0    	ldr	d0, [x15, #0x48]
100009f24: 3d81dbe0    	str	q0, [sp, #0x760]
100009f28: 4d40ce00    	ld1r.2d	{ v0 }, [x16]
100009f2c: 3d81d7e0    	str	q0, [sp, #0x750]
100009f30: fd400da0    	ldr	d0, [x13, #0x18]
100009f34: 3d81d3e0    	str	q0, [sp, #0x740]
100009f38: fd4011a0    	ldr	d0, [x13, #0x20]
100009f3c: 3d81cfe0    	str	q0, [sp, #0x730]
100009f40: fd4015a0    	ldr	d0, [x13, #0x28]
100009f44: 3d81cbe0    	str	q0, [sp, #0x720]
100009f48: fd4019a0    	ldr	d0, [x13, #0x30]
100009f4c: 3d81c7e0    	str	q0, [sp, #0x710]
100009f50: fd401da0    	ldr	d0, [x13, #0x38]
100009f54: 3d81c3e0    	str	q0, [sp, #0x700]
100009f58: fd4021a0    	ldr	d0, [x13, #0x40]
100009f5c: 3d81bfe0    	str	q0, [sp, #0x6f0]
100009f60: fd4025a0    	ldr	d0, [x13, #0x48]
100009f64: 3d81bbe0    	str	q0, [sp, #0x6e0]
100009f68: 4d40cddd    	ld1r.2d	{ v29 }, [x14]
100009f6c: 6d410173    	ldp	d19, d0, [x11, #0x10]
100009f70: 6d421163    	ldp	d3, d4, [x11, #0x20]
100009f74: 6d431965    	ldp	d5, d6, [x11, #0x30]
100009f78: 6d444167    	ldp	d7, d16, [x11, #0x40]
100009f7c: 4d40cd91    	ld1r.2d	{ v17 }, [x12]
100009f80: 4ddfcf12    	ld1r.2d	{ v18 }, [x24], #8
100009f84: fd400314    	ldr	d20, [x24]
100009f88: 6d415875    	ldp	d21, d22, [x3, #0x10]
100009f8c: 6d426077    	ldp	d23, d24, [x3, #0x20]
100009f90: 6d436879    	ldp	d25, d26, [x3, #0x30]
100009f94: 6d44707b    	ldp	d27, d28, [x3, #0x40]
100009f98: 3dc31fe1    	ldr	q1, [sp, #0xc70]
100009f9c: 6ee28c21    	cmeq.2d	v1, v1, v2
100009fa0: 6f03f60b    	fmov.2d	v11, #1.00000000
100009fa4: 4e211d7e    	and.16b	v30, v11, v1
100009fa8: 3dc31be1    	ldr	q1, [sp, #0xc60]
100009fac: 6ee28c21    	cmeq.2d	v1, v1, v2
100009fb0: 4e211d61    	and.16b	v1, v11, v1
100009fb4: 3dc313ff    	ldr	q31, [sp, #0xc40]
100009fb8: 4fdf93df    	fmul.2d	v31, v30, v31[0]
100009fbc: 4effd43f    	fsub.2d	v31, v1, v31
100009fc0: 3dc317e1    	ldr	q1, [sp, #0xc50]
100009fc4: 6ee28c21    	cmeq.2d	v1, v1, v2
100009fc8: 4e211d61    	and.16b	v1, v11, v1
100009fcc: 3dc30be8    	ldr	q8, [sp, #0xc20]
100009fd0: 4fc893c8    	fmul.2d	v8, v30, v8[0]
100009fd4: 4ee8d421    	fsub.2d	v1, v1, v8
100009fd8: 3dc307e8    	ldr	q8, [sp, #0xc10]
100009fdc: 4fc893e8    	fmul.2d	v8, v31, v8[0]
100009fe0: 3dc30fe9    	ldr	q9, [sp, #0xc30]
100009fe4: 6ee28d29    	cmeq.2d	v9, v9, v2
100009fe8: 4e291d69    	and.16b	v9, v11, v9
100009fec: 3dc303ea    	ldr	q10, [sp, #0xc00]
100009ff0: 4fca93ca    	fmul.2d	v10, v30, v10[0]
100009ff4: 4eead529    	fsub.2d	v9, v9, v10
100009ff8: 4ee8d428    	fsub.2d	v8, v1, v8
100009ffc: 3dc2ffe1    	ldr	q1, [sp, #0xbf0]
10000a000: 4fc193e1    	fmul.2d	v1, v31, v1[0]
10000a004: 4ee1d521    	fsub.2d	v1, v9, v1
10000a008: 3dc2fbe9    	ldr	q9, [sp, #0xbe0]
10000a00c: 4fc99109    	fmul.2d	v9, v8, v9[0]
10000a010: 3dc2f7ea    	ldr	q10, [sp, #0xbd0]
10000a014: 6ee28d4a    	cmeq.2d	v10, v10, v2
10000a018: 4e2a1d6a    	and.16b	v10, v11, v10
10000a01c: 4ee9d429    	fsub.2d	v9, v1, v9
10000a020: 3dc2f3e1    	ldr	q1, [sp, #0xbc0]
10000a024: 4fc193c1    	fmul.2d	v1, v30, v1[0]
10000a028: 4ee1d541    	fsub.2d	v1, v10, v1
10000a02c: 3dc2efea    	ldr	q10, [sp, #0xbb0]
10000a030: 4fca93ea    	fmul.2d	v10, v31, v10[0]
10000a034: 4eead421    	fsub.2d	v1, v1, v10
10000a038: 3dc2ebea    	ldr	q10, [sp, #0xba0]
10000a03c: 4fca910a    	fmul.2d	v10, v8, v10[0]
10000a040: 4eead421    	fsub.2d	v1, v1, v10
10000a044: 3dc2e7ea    	ldr	q10, [sp, #0xb90]
10000a048: 4fca912a    	fmul.2d	v10, v9, v10[0]
10000a04c: 3dc2e3ec    	ldr	q12, [sp, #0xb80]
10000a050: 6ee28d8c    	cmeq.2d	v12, v12, v2
10000a054: 4e2c1d6c    	and.16b	v12, v11, v12
10000a058: 3dc2dfed    	ldr	q13, [sp, #0xb70]
10000a05c: 4fcd93cd    	fmul.2d	v13, v30, v13[0]
10000a060: 4eedd58c    	fsub.2d	v12, v12, v13
10000a064: 4eead42a    	fsub.2d	v10, v1, v10
10000a068: 3dc2dbe1    	ldr	q1, [sp, #0xb60]
10000a06c: 4fc193e1    	fmul.2d	v1, v31, v1[0]
10000a070: 4ee1d581    	fsub.2d	v1, v12, v1
10000a074: 3dc2d7ec    	ldr	q12, [sp, #0xb50]
10000a078: 4fcc910c    	fmul.2d	v12, v8, v12[0]
10000a07c: 4eecd421    	fsub.2d	v1, v1, v12
10000a080: 3dc2d3ec    	ldr	q12, [sp, #0xb40]
10000a084: 4fcc912c    	fmul.2d	v12, v9, v12[0]
10000a088: 4eecd421    	fsub.2d	v1, v1, v12
10000a08c: 3dc2cbec    	ldr	q12, [sp, #0xb20]
10000a090: 6ee28d8c    	cmeq.2d	v12, v12, v2
10000a094: 4e2c1d6c    	and.16b	v12, v11, v12
10000a098: 3dc2c7ed    	ldr	q13, [sp, #0xb10]
10000a09c: 4fcd93cd    	fmul.2d	v13, v30, v13[0]
10000a0a0: 4eedd58c    	fsub.2d	v12, v12, v13
10000a0a4: 3dc2c3ed    	ldr	q13, [sp, #0xb00]
10000a0a8: 4fcd93ed    	fmul.2d	v13, v31, v13[0]
10000a0ac: 3dc2cfee    	ldr	q14, [sp, #0xb30]
10000a0b0: 4fce914e    	fmul.2d	v14, v10, v14[0]
10000a0b4: 4eedd58c    	fsub.2d	v12, v12, v13
10000a0b8: 3dc2bfed    	ldr	q13, [sp, #0xaf0]
10000a0bc: 4fcd910d    	fmul.2d	v13, v8, v13[0]
10000a0c0: 4eedd58c    	fsub.2d	v12, v12, v13
10000a0c4: 3dc2bbed    	ldr	q13, [sp, #0xae0]
10000a0c8: 4fcd912d    	fmul.2d	v13, v9, v13[0]
10000a0cc: 4eedd58c    	fsub.2d	v12, v12, v13
10000a0d0: 4eeed421    	fsub.2d	v1, v1, v14
10000a0d4: 3dc2afed    	ldr	q13, [sp, #0xab0]
10000a0d8: 6ee28dad    	cmeq.2d	v13, v13, v2
10000a0dc: 4e2d1d6d    	and.16b	v13, v11, v13
10000a0e0: 3dc2abee    	ldr	q14, [sp, #0xaa0]
10000a0e4: 4fce93ce    	fmul.2d	v14, v30, v14[0]
10000a0e8: 4eeed5ad    	fsub.2d	v13, v13, v14
10000a0ec: 3dc2a7ee    	ldr	q14, [sp, #0xa90]
10000a0f0: 4fce93ee    	fmul.2d	v14, v31, v14[0]
10000a0f4: 3dc2b7ef    	ldr	q15, [sp, #0xad0]
10000a0f8: 4fcf914f    	fmul.2d	v15, v10, v15[0]
10000a0fc: 4eeed5ad    	fsub.2d	v13, v13, v14
10000a100: 3dc29fee    	ldr	q14, [sp, #0xa70]
10000a104: 4fce910e    	fmul.2d	v14, v8, v14[0]
10000a108: 4eeed5ad    	fsub.2d	v13, v13, v14
10000a10c: 3dc29bee    	ldr	q14, [sp, #0xa60]
10000a110: 4fce912e    	fmul.2d	v14, v9, v14[0]
10000a114: 4eeed5ad    	fsub.2d	v13, v13, v14
10000a118: 4eefd58c    	fsub.2d	v12, v12, v15
10000a11c: 3dc28fee    	ldr	q14, [sp, #0xa30]
10000a120: 6ee28dce    	cmeq.2d	v14, v14, v2
10000a124: 4e2e1d6e    	and.16b	v14, v11, v14
10000a128: 3dc287ef    	ldr	q15, [sp, #0xa10]
10000a12c: 4fcf93cf    	fmul.2d	v15, v30, v15[0]
10000a130: 4eefd5ce    	fsub.2d	v14, v14, v15
10000a134: 3dc297ef    	ldr	q15, [sp, #0xa50]
10000a138: 4fcf914f    	fmul.2d	v15, v10, v15[0]
10000a13c: 4eefd5ad    	fsub.2d	v13, v13, v15
10000a140: 3dc283ef    	ldr	q15, [sp, #0xa00]
10000a144: 4fcf93ef    	fmul.2d	v15, v31, v15[0]
10000a148: 4eefd5ce    	fsub.2d	v14, v14, v15
10000a14c: 3dc27fef    	ldr	q15, [sp, #0x9f0]
10000a150: 4fcf910f    	fmul.2d	v15, v8, v15[0]
10000a154: 4eefd5ce    	fsub.2d	v14, v14, v15
10000a158: 3dc2b3ef    	ldr	q15, [sp, #0xac0]
10000a15c: 4fcf902f    	fmul.2d	v15, v1, v15[0]
10000a160: 4eefd58f    	fsub.2d	v15, v12, v15
10000a164: 3dc27bec    	ldr	q12, [sp, #0x9e0]
10000a168: 4fcc912c    	fmul.2d	v12, v9, v12[0]
10000a16c: 4eecd5cc    	fsub.2d	v12, v14, v12
10000a170: 3dc277ee    	ldr	q14, [sp, #0x9d0]
10000a174: 4fce914e    	fmul.2d	v14, v10, v14[0]
10000a178: 4eeed58c    	fsub.2d	v12, v12, v14
10000a17c: 3dc293ee    	ldr	q14, [sp, #0xa40]
10000a180: 4fce902e    	fmul.2d	v14, v1, v14[0]
10000a184: 4eeed5ad    	fsub.2d	v13, v13, v14
10000a188: 3dc2a3ee    	ldr	q14, [sp, #0xa80]
10000a18c: 6ee28dce    	cmeq.2d	v14, v14, v2
10000a190: 4e2e1d6b    	and.16b	v11, v11, v14
10000a194: 3dc267ee    	ldr	q14, [sp, #0x990]
10000a198: 4fce93ce    	fmul.2d	v14, v30, v14[0]
10000a19c: 4eeed56b    	fsub.2d	v11, v11, v14
10000a1a0: 3dc273ee    	ldr	q14, [sp, #0x9c0]
10000a1a4: 4fce902e    	fmul.2d	v14, v1, v14[0]
10000a1a8: 4eeed58c    	fsub.2d	v12, v12, v14
10000a1ac: 3dc263ee    	ldr	q14, [sp, #0x980]
10000a1b0: 4fce93ee    	fmul.2d	v14, v31, v14[0]
10000a1b4: 4eeed56b    	fsub.2d	v11, v11, v14
10000a1b8: 3dc25fee    	ldr	q14, [sp, #0x970]
10000a1bc: 4fce910e    	fmul.2d	v14, v8, v14[0]
10000a1c0: 4eeed56b    	fsub.2d	v11, v11, v14
10000a1c4: 3dc28bee    	ldr	q14, [sp, #0xa20]
10000a1c8: 4fce91ee    	fmul.2d	v14, v15, v14[0]
10000a1cc: 4eeed5ad    	fsub.2d	v13, v13, v14
10000a1d0: 3dc25bee    	ldr	q14, [sp, #0x960]
10000a1d4: 4fce912e    	fmul.2d	v14, v9, v14[0]
10000a1d8: 4eeed56b    	fsub.2d	v11, v11, v14
10000a1dc: 3dc257ee    	ldr	q14, [sp, #0x950]
10000a1e0: 4fce914e    	fmul.2d	v14, v10, v14[0]
10000a1e4: 4eeed56b    	fsub.2d	v11, v11, v14
10000a1e8: 3dc26fee    	ldr	q14, [sp, #0x9b0]
10000a1ec: 4fce91ee    	fmul.2d	v14, v15, v14[0]
10000a1f0: 4eeed58c    	fsub.2d	v12, v12, v14
10000a1f4: 3dc253ee    	ldr	q14, [sp, #0x940]
10000a1f8: 4fce902e    	fmul.2d	v14, v1, v14[0]
10000a1fc: 4eeed56b    	fsub.2d	v11, v11, v14
10000a200: 3dc24fee    	ldr	q14, [sp, #0x930]
10000a204: 4fce91ee    	fmul.2d	v14, v15, v14[0]
10000a208: 4eeed56b    	fsub.2d	v11, v11, v14
10000a20c: 3dc26bee    	ldr	q14, [sp, #0x9a0]
10000a210: 4fce91ae    	fmul.2d	v14, v13, v14[0]
10000a214: 4eeed58c    	fsub.2d	v12, v12, v14
10000a218: 3dc24bee    	ldr	q14, [sp, #0x920]
10000a21c: 4fce91ae    	fmul.2d	v14, v13, v14[0]
10000a220: 4eeed56b    	fsub.2d	v11, v11, v14
10000a224: 3dc247ee    	ldr	q14, [sp, #0x910]
10000a228: 4fce918e    	fmul.2d	v14, v12, v14[0]
10000a22c: 4eeed56b    	fsub.2d	v11, v11, v14
10000a230: 3dc243ee    	ldr	q14, [sp, #0x900]
10000a234: 6e6efd6b    	fdiv.2d	v11, v11, v14
10000a238: 3dc23fee    	ldr	q14, [sp, #0x8f0]
10000a23c: 4fce916e    	fmul.2d	v14, v11, v14[0]
10000a240: 4eeed58c    	fsub.2d	v12, v12, v14
10000a244: 3dc23bee    	ldr	q14, [sp, #0x8e0]
10000a248: 6e6efd8c    	fdiv.2d	v12, v12, v14
10000a24c: 3dc237ee    	ldr	q14, [sp, #0x8d0]
10000a250: 4fce918e    	fmul.2d	v14, v12, v14[0]
10000a254: 4eeed5ad    	fsub.2d	v13, v13, v14
10000a258: 3dc233ee    	ldr	q14, [sp, #0x8c0]
10000a25c: 4fce916e    	fmul.2d	v14, v11, v14[0]
10000a260: 4eeed5ad    	fsub.2d	v13, v13, v14
10000a264: 3dc22fee    	ldr	q14, [sp, #0x8b0]
10000a268: 6e6efdad    	fdiv.2d	v13, v13, v14
10000a26c: 3dc22bee    	ldr	q14, [sp, #0x8a0]
10000a270: 4fce91ae    	fmul.2d	v14, v13, v14[0]
10000a274: 4eeed5ee    	fsub.2d	v14, v15, v14
10000a278: 3dc227ef    	ldr	q15, [sp, #0x890]
10000a27c: 4fcf918f    	fmul.2d	v15, v12, v15[0]
10000a280: 4eefd5ce    	fsub.2d	v14, v14, v15
10000a284: 3dc223ef    	ldr	q15, [sp, #0x880]
10000a288: 4fcf916f    	fmul.2d	v15, v11, v15[0]
10000a28c: 4eefd5ce    	fsub.2d	v14, v14, v15
10000a290: 3dc21fef    	ldr	q15, [sp, #0x870]
10000a294: 6e6ffdce    	fdiv.2d	v14, v14, v15
10000a298: 3dc21bef    	ldr	q15, [sp, #0x860]
10000a29c: 4fcf91cf    	fmul.2d	v15, v14, v15[0]
10000a2a0: 4eefd421    	fsub.2d	v1, v1, v15
10000a2a4: 3dc217ef    	ldr	q15, [sp, #0x850]
10000a2a8: 4fcf91af    	fmul.2d	v15, v13, v15[0]
10000a2ac: 4eefd421    	fsub.2d	v1, v1, v15
10000a2b0: 3dc213ef    	ldr	q15, [sp, #0x840]
10000a2b4: 4fcf918f    	fmul.2d	v15, v12, v15[0]
10000a2b8: 4eefd421    	fsub.2d	v1, v1, v15
10000a2bc: 3dc20fef    	ldr	q15, [sp, #0x830]
10000a2c0: 4fcf916f    	fmul.2d	v15, v11, v15[0]
10000a2c4: 4eefd421    	fsub.2d	v1, v1, v15
10000a2c8: 3dc20bef    	ldr	q15, [sp, #0x820]
10000a2cc: 6e6ffc21    	fdiv.2d	v1, v1, v15
10000a2d0: 3dc207ef    	ldr	q15, [sp, #0x810]
10000a2d4: 4fcf902f    	fmul.2d	v15, v1, v15[0]
10000a2d8: 4eefd54a    	fsub.2d	v10, v10, v15
10000a2dc: 3dc203ef    	ldr	q15, [sp, #0x800]
10000a2e0: 4fcf91cf    	fmul.2d	v15, v14, v15[0]
10000a2e4: 4eefd54a    	fsub.2d	v10, v10, v15
10000a2e8: 3dc1ffef    	ldr	q15, [sp, #0x7f0]
10000a2ec: 4fcf91af    	fmul.2d	v15, v13, v15[0]
10000a2f0: 4eefd54a    	fsub.2d	v10, v10, v15
10000a2f4: 3dc1fbef    	ldr	q15, [sp, #0x7e0]
10000a2f8: 4fcf918f    	fmul.2d	v15, v12, v15[0]
10000a2fc: 4eefd54a    	fsub.2d	v10, v10, v15
10000a300: 3dc1f7ef    	ldr	q15, [sp, #0x7d0]
10000a304: 4fcf916f    	fmul.2d	v15, v11, v15[0]
10000a308: 4eefd54a    	fsub.2d	v10, v10, v15
10000a30c: 3dc1f3ef    	ldr	q15, [sp, #0x7c0]
10000a310: 6e6ffd4a    	fdiv.2d	v10, v10, v15
10000a314: 3dc1efef    	ldr	q15, [sp, #0x7b0]
10000a318: 4fcf914f    	fmul.2d	v15, v10, v15[0]
10000a31c: 4eefd529    	fsub.2d	v9, v9, v15
10000a320: 3dc1ebef    	ldr	q15, [sp, #0x7a0]
10000a324: 4fcf902f    	fmul.2d	v15, v1, v15[0]
10000a328: 4eefd529    	fsub.2d	v9, v9, v15
10000a32c: 3dc1e7ef    	ldr	q15, [sp, #0x790]
10000a330: 4fcf91cf    	fmul.2d	v15, v14, v15[0]
10000a334: 4eefd529    	fsub.2d	v9, v9, v15
10000a338: 3dc1e3ef    	ldr	q15, [sp, #0x780]
10000a33c: 4fcf91af    	fmul.2d	v15, v13, v15[0]
10000a340: 4eefd529    	fsub.2d	v9, v9, v15
10000a344: 3dc1dfef    	ldr	q15, [sp, #0x770]
10000a348: 4fcf918f    	fmul.2d	v15, v12, v15[0]
10000a34c: 4eefd529    	fsub.2d	v9, v9, v15
10000a350: 3dc1dbef    	ldr	q15, [sp, #0x760]
10000a354: 4fcf916f    	fmul.2d	v15, v11, v15[0]
10000a358: 4eefd529    	fsub.2d	v9, v9, v15
10000a35c: 3dc1d7ef    	ldr	q15, [sp, #0x750]
10000a360: 6e6ffd29    	fdiv.2d	v9, v9, v15
10000a364: 3dc1d3ef    	ldr	q15, [sp, #0x740]
10000a368: 4fcf912f    	fmul.2d	v15, v9, v15[0]
10000a36c: 4eefd508    	fsub.2d	v8, v8, v15
10000a370: 3dc1cfef    	ldr	q15, [sp, #0x730]
10000a374: 4fcf914f    	fmul.2d	v15, v10, v15[0]
10000a378: 4eefd508    	fsub.2d	v8, v8, v15
10000a37c: 3dc1cbef    	ldr	q15, [sp, #0x720]
10000a380: 4fcf902f    	fmul.2d	v15, v1, v15[0]
10000a384: 4eefd508    	fsub.2d	v8, v8, v15
10000a388: 3dc1c7ef    	ldr	q15, [sp, #0x710]
10000a38c: 4fcf91cf    	fmul.2d	v15, v14, v15[0]
10000a390: 4eefd508    	fsub.2d	v8, v8, v15
10000a394: 3dc1c3ef    	ldr	q15, [sp, #0x700]
10000a398: 4fcf91af    	fmul.2d	v15, v13, v15[0]
10000a39c: 4eefd508    	fsub.2d	v8, v8, v15
10000a3a0: 3dc1bfef    	ldr	q15, [sp, #0x6f0]
10000a3a4: 4fcf918f    	fmul.2d	v15, v12, v15[0]
10000a3a8: 4eefd508    	fsub.2d	v8, v8, v15
10000a3ac: 3dc1bbef    	ldr	q15, [sp, #0x6e0]
10000a3b0: 4fcf916f    	fmul.2d	v15, v11, v15[0]
10000a3b4: 4eefd508    	fsub.2d	v8, v8, v15
10000a3b8: 6e7dfd08    	fdiv.2d	v8, v8, v29
10000a3bc: 4fd3910f    	fmul.2d	v15, v8, v19[0]
10000a3c0: 4eefd7ff    	fsub.2d	v31, v31, v15
10000a3c4: 4fc0912f    	fmul.2d	v15, v9, v0[0]
10000a3c8: 4eefd7ff    	fsub.2d	v31, v31, v15
10000a3cc: 4fc3914f    	fmul.2d	v15, v10, v3[0]
10000a3d0: 4eefd7ff    	fsub.2d	v31, v31, v15
10000a3d4: 4fc4902f    	fmul.2d	v15, v1, v4[0]
10000a3d8: 4eefd7ff    	fsub.2d	v31, v31, v15
10000a3dc: 4fc591cf    	fmul.2d	v15, v14, v5[0]
10000a3e0: 4eefd7ff    	fsub.2d	v31, v31, v15
10000a3e4: 4fc691af    	fmul.2d	v15, v13, v6[0]
10000a3e8: 4eefd7ff    	fsub.2d	v31, v31, v15
10000a3ec: 4fc7918f    	fmul.2d	v15, v12, v7[0]
10000a3f0: 4eefd7ff    	fsub.2d	v31, v31, v15
10000a3f4: 4fd0916f    	fmul.2d	v15, v11, v16[0]
10000a3f8: 4eefd7ff    	fsub.2d	v31, v31, v15
10000a3fc: 6e71ffff    	fdiv.2d	v31, v31, v17
10000a400: 4fd493ef    	fmul.2d	v15, v31, v20[0]
10000a404: 4eefd7de    	fsub.2d	v30, v30, v15
10000a408: 4fd5910f    	fmul.2d	v15, v8, v21[0]
10000a40c: 4eefd7de    	fsub.2d	v30, v30, v15
10000a410: 4fd6912f    	fmul.2d	v15, v9, v22[0]
10000a414: 4eefd7de    	fsub.2d	v30, v30, v15
10000a418: 4fd7914f    	fmul.2d	v15, v10, v23[0]
10000a41c: 4eefd7de    	fsub.2d	v30, v30, v15
10000a420: 4fd8902f    	fmul.2d	v15, v1, v24[0]
10000a424: 4eefd7de    	fsub.2d	v30, v30, v15
10000a428: 4fd991cf    	fmul.2d	v15, v14, v25[0]
10000a42c: 4eefd7de    	fsub.2d	v30, v30, v15
10000a430: 4fda91af    	fmul.2d	v15, v13, v26[0]
10000a434: 4eefd7de    	fsub.2d	v30, v30, v15
10000a438: 4fdb918f    	fmul.2d	v15, v12, v27[0]
10000a43c: 4eefd7de    	fsub.2d	v30, v30, v15
10000a440: 8b08012b    	add	x11, x9, x8
10000a444: 3d80157f    	str	q31, [x11, #0x50]
10000a448: 3d802968    	str	q8, [x11, #0xa0]
10000a44c: 3d803d69    	str	q9, [x11, #0xf0]
10000a450: 3d80516a    	str	q10, [x11, #0x140]
10000a454: 4fdc917f    	fmul.2d	v31, v11, v28[0]
10000a458: 4effd7de    	fsub.2d	v30, v30, v31
10000a45c: 3d806561    	str	q1, [x11, #0x190]
10000a460: 3d80796e    	str	q14, [x11, #0x1e0]
10000a464: 3d808d6d    	str	q13, [x11, #0x230]
10000a468: 3d80a16c    	str	q12, [x11, #0x280]
10000a46c: 6e72ffc1    	fdiv.2d	v1, v30, v18
10000a470: 3d800161    	str	q1, [x11]
10000a474: 3d80b56b    	str	q11, [x11, #0x2d0]
10000a478: 4e080d41    	dup.2d	v1, x10
10000a47c: 4ee18442    	add.2d	v2, v2, v1
10000a480: 91004108    	add	x8, x8, #0x10
10000a484: f101411f    	cmp	x8, #0x50
10000a488: 54ffd881    	b.ne	0x100009f98 <_codegen_qseries_nonzero_12x10+0x2ed0>
10000a48c: 3dc43be1    	ldr	q1, [sp, #0x10e0]
10000a490: 3dc43fe7    	ldr	q7, [sp, #0x10f0]
10000a494: 3dc17bf5    	ldr	q21, [sp, #0x5e0]
10000a498: 3d809be1    	str	q1, [sp, #0x260]
10000a49c: 4fc192a0    	fmul.2d	v0, v21, v1[0]
10000a4a0: 6f00e411    	movi.2d	v17, #0000000000000000
10000a4a4: 4e71d400    	fadd.2d	v0, v0, v17
10000a4a8: ad485ff4    	ldp	q20, q23, [sp, #0x100]
10000a4ac: 4fc19ae1    	fmul.2d	v1, v23, v1[1]
10000a4b0: 3dc44fe3    	ldr	q3, [sp, #0x1130]
10000a4b4: 3d8057e3    	str	q3, [sp, #0x150]
10000a4b8: 4e61d401    	fadd.2d	v1, v0, v1
10000a4bc: 4fc392a0    	fmul.2d	v0, v21, v3[0]
10000a4c0: 4e71d400    	fadd.2d	v0, v0, v17
10000a4c4: 3dc463e5    	ldr	q5, [sp, #0x1180]
10000a4c8: 3dc467f6    	ldr	q22, [sp, #0x1190]
10000a4cc: 4fc39ae3    	fmul.2d	v3, v23, v3[1]
10000a4d0: 4e63d403    	fadd.2d	v3, v0, v3
10000a4d4: 3dc477e6    	ldr	q6, [sp, #0x11d0]
10000a4d8: ad0997f6    	stp	q22, q5, [sp, #0x130]
10000a4dc: 4fc592a0    	fmul.2d	v0, v21, v5[0]
10000a4e0: 4e71d400    	fadd.2d	v0, v0, v17
10000a4e4: 4fc59ae4    	fmul.2d	v4, v23, v5[1]
10000a4e8: 4e64d400    	fadd.2d	v0, v0, v4
10000a4ec: 4fd69284    	fmul.2d	v4, v20, v22[0]
10000a4f0: 4e64d400    	fadd.2d	v0, v0, v4
10000a4f4: 3dc1b3f9    	ldr	q25, [sp, #0x6c0]
10000a4f8: 4fd69b24    	fmul.2d	v4, v25, v22[1]
10000a4fc: 4e64d400    	fadd.2d	v0, v0, v4
10000a500: 3d831be0    	str	q0, [sp, #0xc60]
10000a504: 3d804be6    	str	q6, [sp, #0x120]
10000a508: 4fc692a0    	fmul.2d	v0, v21, v6[0]
10000a50c: 4e71d400    	fadd.2d	v0, v0, v17
10000a510: 6f00e410    	movi.2d	v16, #0000000000000000
10000a514: 4fc69ae4    	fmul.2d	v4, v23, v6[1]
10000a518: 4e64d400    	fadd.2d	v0, v0, v4
10000a51c: 3dc47be6    	ldr	q6, [sp, #0x11e0]
10000a520: 3dc47fe2    	ldr	q2, [sp, #0x11f0]
10000a524: 3d8073e2    	str	q2, [sp, #0x1c0]
10000a528: 4fc69284    	fmul.2d	v4, v20, v6[0]
10000a52c: 4e64d400    	fadd.2d	v0, v0, v4
10000a530: 4fc69b24    	fmul.2d	v4, v25, v6[1]
10000a534: 4ea61cc9    	mov.16b	v9, v6
10000a538: 3d802fe6    	str	q6, [sp, #0xb0]
10000a53c: 4e64d406    	fadd.2d	v6, v0, v4
10000a540: 3dc48be4    	ldr	q4, [sp, #0x1220]
10000a544: 3d80cbe4    	str	q4, [sp, #0x320]
10000a548: 3dc48feb    	ldr	q11, [sp, #0x1230]
10000a54c: 4fc492a0    	fmul.2d	v0, v21, v4[0]
10000a550: 4e70d400    	fadd.2d	v0, v0, v16
10000a554: 4fc49ae4    	fmul.2d	v4, v23, v4[1]
10000a558: 4e64d400    	fadd.2d	v0, v0, v4
10000a55c: 4fcb9284    	fmul.2d	v4, v20, v11[0]
10000a560: 4eb41e9b    	mov.16b	v27, v20
10000a564: 4e64d400    	fadd.2d	v0, v0, v4
10000a568: 4fcb9b24    	fmul.2d	v4, v25, v11[1]
10000a56c: 3d80c3eb    	str	q11, [sp, #0x300]
10000a570: 4e64d400    	fadd.2d	v0, v0, v4
10000a574: 3dc493e4    	ldr	q4, [sp, #0x1240]
10000a578: 3dc497e2    	ldr	q2, [sp, #0x1250]
10000a57c: 3d806fe2    	str	q2, [sp, #0x1b0]
10000a580: 3dc18bec    	ldr	q12, [sp, #0x620]
10000a584: 4ea41c82    	mov.16b	v2, v4
10000a588: 3d823be4    	str	q4, [sp, #0x8e0]
10000a58c: 4fc49184    	fmul.2d	v4, v12, v4[0]
10000a590: 4e64d400    	fadd.2d	v0, v0, v4
10000a594: 3dc187ef    	ldr	q15, [sp, #0x610]
10000a598: 4fc299e4    	fmul.2d	v4, v15, v2[1]
10000a59c: 4e64d400    	fadd.2d	v0, v0, v4
10000a5a0: 3d8317e0    	str	q0, [sp, #0xc50]
10000a5a4: 3dc49fe2    	ldr	q2, [sp, #0x1270]
10000a5a8: 4fc292a0    	fmul.2d	v0, v21, v2[0]
10000a5ac: 6f00e413    	movi.2d	v19, #0000000000000000
10000a5b0: 4e73d400    	fadd.2d	v0, v0, v19
10000a5b4: 4fc29ae4    	fmul.2d	v4, v23, v2[1]
10000a5b8: 4e64d400    	fadd.2d	v0, v0, v4
10000a5bc: 3dc4a3e5    	ldr	q5, [sp, #0x1280]
10000a5c0: 3dc4a7f0    	ldr	q16, [sp, #0x1290]
10000a5c4: 3d824ff0    	str	q16, [sp, #0x930]
10000a5c8: 4fc59284    	fmul.2d	v4, v20, v5[0]
10000a5cc: 4e64d400    	fadd.2d	v0, v0, v4
10000a5d0: 4fc59b24    	fmul.2d	v4, v25, v5[1]
10000a5d4: ad168be5    	stp	q5, q2, [sp, #0x2d0]
10000a5d8: 4e64d400    	fadd.2d	v0, v0, v4
10000a5dc: 4fd09184    	fmul.2d	v4, v12, v16[0]
10000a5e0: 4e64d400    	fadd.2d	v0, v0, v4
10000a5e4: 4fd099e4    	fmul.2d	v4, v15, v16[1]
10000a5e8: 4e64d400    	fadd.2d	v0, v0, v4
10000a5ec: 3d830fe0    	str	q0, [sp, #0xc30]
10000a5f0: 3dc4b3e4    	ldr	q4, [sp, #0x12c0]
10000a5f4: 3d80afe4    	str	q4, [sp, #0x2b0]
10000a5f8: 3dc4b7ed    	ldr	q13, [sp, #0x12d0]
10000a5fc: 4fc492a0    	fmul.2d	v0, v21, v4[0]
10000a600: 4e73d400    	fadd.2d	v0, v0, v19
10000a604: 4fc49ae4    	fmul.2d	v4, v23, v4[1]
10000a608: 4e64d400    	fadd.2d	v0, v0, v4
10000a60c: 4fcd9284    	fmul.2d	v4, v20, v13[0]
10000a610: 4e64d400    	fadd.2d	v0, v0, v4
10000a614: 4fcd9b24    	fmul.2d	v4, v25, v13[1]
10000a618: 4e64d400    	fadd.2d	v0, v0, v4
10000a61c: 3dc4bbe2    	ldr	q2, [sp, #0x12e0]
10000a620: 3d8237e2    	str	q2, [sp, #0x8d0]
10000a624: 3dc4bff0    	ldr	q16, [sp, #0x12f0]
10000a628: 3d824bf0    	str	q16, [sp, #0x920]
10000a62c: 4fc29184    	fmul.2d	v4, v12, v2[0]
10000a630: 4e64d400    	fadd.2d	v0, v0, v4
10000a634: 4fc299e4    	fmul.2d	v4, v15, v2[1]
10000a638: 4e64d400    	fadd.2d	v0, v0, v4
10000a63c: 3dc17ffa    	ldr	q26, [sp, #0x5f0]
10000a640: 4fd09344    	fmul.2d	v4, v26, v16[0]
10000a644: 4e64d400    	fadd.2d	v0, v0, v4
10000a648: 3dc183fe    	ldr	q30, [sp, #0x600]
10000a64c: 4fd09bc4    	fmul.2d	v4, v30, v16[1]
10000a650: 4e64d400    	fadd.2d	v0, v0, v4
10000a654: 3d8313e0    	str	q0, [sp, #0xc40]
10000a658: 3dc4c7e2    	ldr	q2, [sp, #0x1310]
10000a65c: ad14b7e2    	stp	q2, q13, [sp, #0x290]
10000a660: 3dc4c3e0    	ldr	q0, [sp, #0x1300]
10000a664: 3d806be0    	str	q0, [sp, #0x1a0]
10000a668: 4fc292a0    	fmul.2d	v0, v21, v2[0]
10000a66c: 4e73d400    	fadd.2d	v0, v0, v19
10000a670: 4fc29ae4    	fmul.2d	v4, v23, v2[1]
10000a674: 4e64d400    	fadd.2d	v0, v0, v4
10000a678: 3dc4cbe2    	ldr	q2, [sp, #0x1320]
10000a67c: 3dc4cff4    	ldr	q20, [sp, #0x1330]
10000a680: 4fc29364    	fmul.2d	v4, v27, v2[0]
10000a684: 4e64d400    	fadd.2d	v0, v0, v4
10000a688: 4fc29b24    	fmul.2d	v4, v25, v2[1]
10000a68c: ad138bf4    	stp	q20, q2, [sp, #0x270]
10000a690: 4e64d400    	fadd.2d	v0, v0, v4
10000a694: 4fd49184    	fmul.2d	v4, v12, v20[0]
10000a698: 4e64d400    	fadd.2d	v0, v0, v4
10000a69c: 4fd499e4    	fmul.2d	v4, v15, v20[1]
10000a6a0: 4e64d400    	fadd.2d	v0, v0, v4
10000a6a4: 3dc4d3f0    	ldr	q16, [sp, #0x1340]
10000a6a8: 3d8247f0    	str	q16, [sp, #0x910]
10000a6ac: 3dc4d7e4    	ldr	q4, [sp, #0x1350]
10000a6b0: 3d803fe4    	str	q4, [sp, #0xf0]
10000a6b4: 4fd09344    	fmul.2d	v4, v26, v16[0]
10000a6b8: 4e64d400    	fadd.2d	v0, v0, v4
10000a6bc: 4fd09bc4    	fmul.2d	v4, v30, v16[1]
10000a6c0: 4e64d400    	fadd.2d	v0, v0, v4
10000a6c4: 3d82efe0    	str	q0, [sp, #0xbb0]
10000a6c8: 3dc427e4    	ldr	q4, [sp, #0x1090]
10000a6cc: 3d8253e4    	str	q4, [sp, #0x940]
10000a6d0: 4fc492a0    	fmul.2d	v0, v21, v4[0]
10000a6d4: 4e73d400    	fadd.2d	v0, v0, v19
10000a6d8: 6f00e40a    	movi.2d	v10, #0000000000000000
10000a6dc: 4fc49ae4    	fmul.2d	v4, v23, v4[1]
10000a6e0: 4e64d400    	fadd.2d	v0, v0, v4
10000a6e4: 3dc42bf8    	ldr	q24, [sp, #0x10a0]
10000a6e8: 3dc42ff2    	ldr	q18, [sp, #0x10b0]
10000a6ec: 4fd89364    	fmul.2d	v4, v27, v24[0]
10000a6f0: 4e64d400    	fadd.2d	v0, v0, v4
10000a6f4: 4fd89b24    	fmul.2d	v4, v25, v24[1]
10000a6f8: ad0be3f2    	stp	q18, q24, [sp, #0x170]
10000a6fc: 4e64d400    	fadd.2d	v0, v0, v4
10000a700: 4fd29184    	fmul.2d	v4, v12, v18[0]
10000a704: 4e64d400    	fadd.2d	v0, v0, v4
10000a708: 4fd299e4    	fmul.2d	v4, v15, v18[1]
10000a70c: 4eb21e57    	mov.16b	v23, v18
10000a710: 4e64d400    	fadd.2d	v0, v0, v4
10000a714: 3dc433ff    	ldr	q31, [sp, #0x10c0]
10000a718: 3dc437f2    	ldr	q18, [sp, #0x10d0]
10000a71c: 4fdf9344    	fmul.2d	v4, v26, v31[0]
10000a720: 4e64d400    	fadd.2d	v0, v0, v4
10000a724: 4fdf9bc4    	fmul.2d	v4, v30, v31[1]
10000a728: 3d8037ff    	str	q31, [sp, #0xd0]
10000a72c: 4e64d400    	fadd.2d	v0, v0, v4
10000a730: 3dc177e8    	ldr	q8, [sp, #0x5d0]
10000a734: 3d823ff2    	str	q18, [sp, #0x8f0]
10000a738: 4fd29104    	fmul.2d	v4, v8, v18[0]
10000a73c: 4e64d400    	fadd.2d	v0, v0, v4
10000a740: 3dc173fd    	ldr	q29, [sp, #0x5c0]
10000a744: 4fd29ba4    	fmul.2d	v4, v29, v18[1]
10000a748: 4e64d400    	fadd.2d	v0, v0, v4
10000a74c: 3d830be0    	str	q0, [sp, #0xc20]
10000a750: 4fc79364    	fmul.2d	v4, v27, v7[0]
10000a754: 4e64d421    	fadd.2d	v1, v1, v4
10000a758: 4fc79b24    	fmul.2d	v4, v25, v7[1]
10000a75c: 4ea71cf2    	mov.16b	v18, v7
10000a760: 3d8097e7    	str	q7, [sp, #0x250]
10000a764: 4e64d421    	fadd.2d	v1, v1, v4
10000a768: 3dc443f1    	ldr	q17, [sp, #0x1100]
10000a76c: 3dc447f5    	ldr	q21, [sp, #0x1110]
10000a770: 4fd19184    	fmul.2d	v4, v12, v17[0]
10000a774: 4e64d421    	fadd.2d	v1, v1, v4
10000a778: 4fd199e4    	fmul.2d	v4, v15, v17[1]
10000a77c: ad19c7f5    	stp	q21, q17, [sp, #0x330]
10000a780: 4e64d421    	fadd.2d	v1, v1, v4
10000a784: 4fd59344    	fmul.2d	v4, v26, v21[0]
10000a788: 4e64d421    	fadd.2d	v1, v1, v4
10000a78c: 4fd59bc4    	fmul.2d	v4, v30, v21[1]
10000a790: 4e64d421    	fadd.2d	v1, v1, v4
10000a794: 3dc44be0    	ldr	q0, [sp, #0x1120]
10000a798: 3d805be0    	str	q0, [sp, #0x160]
10000a79c: 4fc09104    	fmul.2d	v4, v8, v0[0]
10000a7a0: 4e64d421    	fadd.2d	v1, v1, v4
10000a7a4: 4fc09ba4    	fmul.2d	v4, v29, v0[1]
10000a7a8: 4e64d420    	fadd.2d	v0, v1, v4
10000a7ac: 3d8307e0    	str	q0, [sp, #0xc10]
10000a7b0: 3dc453e1    	ldr	q1, [sp, #0x1140]
10000a7b4: 4fc19364    	fmul.2d	v4, v27, v1[0]
10000a7b8: 4e64d463    	fadd.2d	v3, v3, v4
10000a7bc: 4fc19b24    	fmul.2d	v4, v25, v1[1]
10000a7c0: 3d80d7e1    	str	q1, [sp, #0x350]
10000a7c4: 4e64d463    	fadd.2d	v3, v3, v4
10000a7c8: 3dc457f0    	ldr	q16, [sp, #0x1150]
10000a7cc: 4fd09184    	fmul.2d	v4, v12, v16[0]
10000a7d0: 4e64d463    	fadd.2d	v3, v3, v4
10000a7d4: 4fd099e4    	fmul.2d	v4, v15, v16[1]
10000a7d8: 3d80c7f0    	str	q16, [sp, #0x310]
10000a7dc: 4e64d463    	fadd.2d	v3, v3, v4
10000a7e0: 3dc45bf3    	ldr	q19, [sp, #0x1160]
10000a7e4: 3dc45ff9    	ldr	q25, [sp, #0x1170]
10000a7e8: 4fd39344    	fmul.2d	v4, v26, v19[0]
10000a7ec: 4e64d463    	fadd.2d	v3, v3, v4
10000a7f0: 4fd39bc4    	fmul.2d	v4, v30, v19[1]
10000a7f4: 3d80bff3    	str	q19, [sp, #0x2f0]
10000a7f8: 4e64d463    	fadd.2d	v3, v3, v4
10000a7fc: 4fd99104    	fmul.2d	v4, v8, v25[0]
10000a800: 4e64d463    	fadd.2d	v3, v3, v4
10000a804: 4fd99ba4    	fmul.2d	v4, v29, v25[1]
10000a808: 3d8033f9    	str	q25, [sp, #0xc0]
10000a80c: 4e64d460    	fadd.2d	v0, v3, v4
10000a810: 3d8303e0    	str	q0, [sp, #0xc00]
10000a814: 3dc417e3    	ldr	q3, [sp, #0x1050]
10000a818: 3d8067e3    	str	q3, [sp, #0x190]
10000a81c: 3dc413e0    	ldr	q0, [sp, #0x1040]
10000a820: 3d8257e0    	str	q0, [sp, #0x950]
10000a824: 3dc1afe0    	ldr	q0, [sp, #0x6b0]
10000a828: 4fc09064    	fmul.2d	v4, v3, v0[0]
10000a82c: 4e6ad484    	fadd.2d	v4, v4, v10
10000a830: 4fc09b07    	fmul.2d	v7, v24, v0[1]
10000a834: 4e67d484    	fadd.2d	v4, v4, v7
10000a838: 3dc16ffb    	ldr	q27, [sp, #0x5b0]
10000a83c: 4fdb9247    	fmul.2d	v7, v18, v27[0]
10000a840: 4e67d484    	fadd.2d	v4, v4, v7
10000a844: 4fdb9827    	fmul.2d	v7, v1, v27[1]
10000a848: 4e67d484    	fadd.2d	v4, v4, v7
10000a84c: 3dc19fea    	ldr	q10, [sp, #0x670]
10000a850: 4fca92c7    	fmul.2d	v7, v22, v10[0]
10000a854: 4e67d484    	fadd.2d	v4, v4, v7
10000a858: 4fca9927    	fmul.2d	v7, v9, v10[1]
10000a85c: 4e67d484    	fadd.2d	v4, v4, v7
10000a860: 3dc197e9    	ldr	q9, [sp, #0x650]
10000a864: 4fc99167    	fmul.2d	v7, v11, v9[0]
10000a868: 4e67d484    	fadd.2d	v4, v4, v7
10000a86c: 4fc998a7    	fmul.2d	v7, v5, v9[1]
10000a870: 4e67d484    	fadd.2d	v4, v4, v7
10000a874: 3dc1b7e1    	ldr	q1, [sp, #0x6d0]
10000a878: 4fc191a7    	fmul.2d	v7, v13, v1[0]
10000a87c: 4e67d484    	fadd.2d	v4, v4, v7
10000a880: 4fc19847    	fmul.2d	v7, v2, v1[1]
10000a884: 4e67d482    	fadd.2d	v2, v4, v7
10000a888: 3d831fe2    	str	q2, [sp, #0xc70]
10000a88c: 3dc46be4    	ldr	q4, [sp, #0x11a0]
10000a890: 4eac1d8b    	mov.16b	v11, v12
10000a894: 4fc49187    	fmul.2d	v7, v12, v4[0]
10000a898: 3dc31be2    	ldr	q2, [sp, #0xc60]
10000a89c: 4e67d445    	fadd.2d	v5, v2, v7
10000a8a0: 4fc499e7    	fmul.2d	v7, v15, v4[1]
10000a8a4: 3d8093e4    	str	q4, [sp, #0x240]
10000a8a8: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a8ac: 3dc46ffc    	ldr	q28, [sp, #0x11b0]
10000a8b0: 4fdc9347    	fmul.2d	v7, v26, v28[0]
10000a8b4: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a8b8: 4fdc9bc7    	fmul.2d	v7, v30, v28[1]
10000a8bc: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a8c0: 3dc473f8    	ldr	q24, [sp, #0x11c0]
10000a8c4: 4fd89107    	fmul.2d	v7, v8, v24[0]
10000a8c8: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a8cc: 4fd89ba7    	fmul.2d	v7, v29, v24[1]
10000a8d0: 3d80b3f8    	str	q24, [sp, #0x2c0]
10000a8d4: 4e67d4a3    	fadd.2d	v3, v5, v7
10000a8d8: 3d82ffe3    	str	q3, [sp, #0xbf0]
10000a8dc: 3dc073f6    	ldr	q22, [sp, #0x1c0]
10000a8e0: 4fd69187    	fmul.2d	v7, v12, v22[0]
10000a8e4: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a8e8: 4fd699e7    	fmul.2d	v7, v15, v22[1]
10000a8ec: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a8f0: 3dc483ed    	ldr	q13, [sp, #0x1200]
10000a8f4: 3dc487ee    	ldr	q14, [sp, #0x1210]
10000a8f8: 4fcd9347    	fmul.2d	v7, v26, v13[0]
10000a8fc: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a900: 4fcd9bc7    	fmul.2d	v7, v30, v13[1]
10000a904: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a908: 4fce9107    	fmul.2d	v7, v8, v14[0]
10000a90c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a910: 4fce9ba7    	fmul.2d	v7, v29, v14[1]
10000a914: 4e67d4c2    	fadd.2d	v2, v6, v7
10000a918: 3d82fbe2    	str	q2, [sp, #0xbe0]
10000a91c: 3dc41be2    	ldr	q2, [sp, #0x1060]
10000a920: 3d8243e2    	str	q2, [sp, #0x900]
10000a924: 3dc41fe7    	ldr	q7, [sp, #0x1070]
10000a928: 4fc09046    	fmul.2d	v6, v2, v0[0]
10000a92c: 6f00e405    	movi.2d	v5, #0000000000000000
10000a930: 4e65d4c6    	fadd.2d	v6, v6, v5
10000a934: 4fc09af2    	fmul.2d	v18, v23, v0[1]
10000a938: 4e72d4c6    	fadd.2d	v6, v6, v18
10000a93c: 4fdb9232    	fmul.2d	v18, v17, v27[0]
10000a940: 4e72d4c6    	fadd.2d	v6, v6, v18
10000a944: 4fdb9a12    	fmul.2d	v18, v16, v27[1]
10000a948: 4e72d4c6    	fadd.2d	v6, v6, v18
10000a94c: 4fca9092    	fmul.2d	v18, v4, v10[0]
10000a950: 4e72d4c6    	fadd.2d	v6, v6, v18
10000a954: 4fca9ad2    	fmul.2d	v18, v22, v10[1]
10000a958: 4e72d4c6    	fadd.2d	v6, v6, v18
10000a95c: 3dc23be2    	ldr	q2, [sp, #0x8e0]
10000a960: 4fc99052    	fmul.2d	v18, v2, v9[0]
10000a964: 4e72d4c6    	fadd.2d	v6, v6, v18
10000a968: 3dc24fe2    	ldr	q2, [sp, #0x930]
10000a96c: 4fc99852    	fmul.2d	v18, v2, v9[1]
10000a970: 4e72d4c6    	fadd.2d	v6, v6, v18
10000a974: 3dc237e2    	ldr	q2, [sp, #0x8d0]
10000a978: 4fc19052    	fmul.2d	v18, v2, v1[0]
10000a97c: 4e72d4c6    	fadd.2d	v6, v6, v18
10000a980: 4fc19a92    	fmul.2d	v18, v20, v1[1]
10000a984: 4e72d4c2    	fadd.2d	v2, v6, v18
10000a988: 3d831be2    	str	q2, [sp, #0xc60]
10000a98c: 3dc06fe6    	ldr	q6, [sp, #0x1b0]
10000a990: 4fc69352    	fmul.2d	v18, v26, v6[0]
10000a994: 3dc317e2    	ldr	q2, [sp, #0xc50]
10000a998: 4e72d450    	fadd.2d	v16, v2, v18
10000a99c: 4fc69bd2    	fmul.2d	v18, v30, v6[1]
10000a9a0: 4e72d610    	fadd.2d	v16, v16, v18
10000a9a4: 3dc49be4    	ldr	q4, [sp, #0x1260]
10000a9a8: 4fc49112    	fmul.2d	v18, v8, v4[0]
10000a9ac: 4e72d610    	fadd.2d	v16, v16, v18
10000a9b0: 4fc49bb2    	fmul.2d	v18, v29, v4[1]
10000a9b4: 4e72d602    	fadd.2d	v2, v16, v18
10000a9b8: 3d82f7e2    	str	q2, [sp, #0xbd0]
10000a9bc: 3dc4abec    	ldr	q12, [sp, #0x12a0]
10000a9c0: 4fcc9352    	fmul.2d	v18, v26, v12[0]
10000a9c4: 3dc30fe2    	ldr	q2, [sp, #0xc30]
10000a9c8: 4e72d451    	fadd.2d	v17, v2, v18
10000a9cc: 4fcc9bd2    	fmul.2d	v18, v30, v12[1]
10000a9d0: 4e72d631    	fadd.2d	v17, v17, v18
10000a9d4: 3dc4afe3    	ldr	q3, [sp, #0x12b0]
10000a9d8: 4fc39112    	fmul.2d	v18, v8, v3[0]
10000a9dc: 4e72d631    	fadd.2d	v17, v17, v18
10000a9e0: 4fc39bb2    	fmul.2d	v18, v29, v3[1]
10000a9e4: 4e72d622    	fadd.2d	v2, v17, v18
10000a9e8: 3d82f3e2    	str	q2, [sp, #0xbc0]
10000a9ec: 4fc090f2    	fmul.2d	v18, v7, v0[0]
10000a9f0: 4e65d652    	fadd.2d	v18, v18, v5
10000a9f4: 4fc09bf4    	fmul.2d	v20, v31, v0[1]
10000a9f8: 4e74d652    	fadd.2d	v18, v18, v20
10000a9fc: 4fdb92b4    	fmul.2d	v20, v21, v27[0]
10000aa00: 4e74d652    	fadd.2d	v18, v18, v20
10000aa04: 4fdb9a74    	fmul.2d	v20, v19, v27[1]
10000aa08: 4e74d652    	fadd.2d	v18, v18, v20
10000aa0c: 4fca9394    	fmul.2d	v20, v28, v10[0]
10000aa10: 4e74d652    	fadd.2d	v18, v18, v20
10000aa14: 4fca99b4    	fmul.2d	v20, v13, v10[1]
10000aa18: 4e74d652    	fadd.2d	v18, v18, v20
10000aa1c: 4fc990d4    	fmul.2d	v20, v6, v9[0]
10000aa20: 4e74d652    	fadd.2d	v18, v18, v20
10000aa24: 4fc99994    	fmul.2d	v20, v12, v9[1]
10000aa28: 4e74d652    	fadd.2d	v18, v18, v20
10000aa2c: 3dc24be2    	ldr	q2, [sp, #0x920]
10000aa30: 4fc19054    	fmul.2d	v20, v2, v1[0]
10000aa34: 4e74d652    	fadd.2d	v18, v18, v20
10000aa38: 3dc247e2    	ldr	q2, [sp, #0x910]
10000aa3c: 4fc19854    	fmul.2d	v20, v2, v1[1]
10000aa40: 4e74d642    	fadd.2d	v2, v18, v20
10000aa44: 3d8317e2    	str	q2, [sp, #0xc50]
10000aa48: 3dc06bf2    	ldr	q18, [sp, #0x1a0]
10000aa4c: 4fd29114    	fmul.2d	v20, v8, v18[0]
10000aa50: 3dc313e2    	ldr	q2, [sp, #0xc40]
10000aa54: 4e74d453    	fadd.2d	v19, v2, v20
10000aa58: 4fd29bb4    	fmul.2d	v20, v29, v18[1]
10000aa5c: 4e74d662    	fadd.2d	v2, v19, v20
10000aa60: 3d82ebe2    	str	q2, [sp, #0xba0]
10000aa64: 3dc03ff1    	ldr	q17, [sp, #0xf0]
10000aa68: 4fd19113    	fmul.2d	v19, v8, v17[0]
10000aa6c: 3dc2efe2    	ldr	q2, [sp, #0xbb0]
10000aa70: 4e73d453    	fadd.2d	v19, v2, v19
10000aa74: 4fd19bb5    	fmul.2d	v21, v29, v17[1]
10000aa78: 4e75d662    	fadd.2d	v2, v19, v21
10000aa7c: 3d82efe2    	str	q2, [sp, #0xbb0]
10000aa80: 3dc423e2    	ldr	q2, [sp, #0x1080]
10000aa84: 4fc09055    	fmul.2d	v21, v2, v0[0]
10000aa88: 4e65d6b5    	fadd.2d	v21, v21, v5
10000aa8c: 3dc23fe6    	ldr	q6, [sp, #0x8f0]
10000aa90: 4fc098d6    	fmul.2d	v22, v6, v0[1]
10000aa94: 4e76d6b5    	fadd.2d	v21, v21, v22
10000aa98: 3dc05be5    	ldr	q5, [sp, #0x160]
10000aa9c: 4fdb90b6    	fmul.2d	v22, v5, v27[0]
10000aaa0: 4e76d6b5    	fadd.2d	v21, v21, v22
10000aaa4: 4fdb9b36    	fmul.2d	v22, v25, v27[1]
10000aaa8: 4e76d6b5    	fadd.2d	v21, v21, v22
10000aaac: 4fca9316    	fmul.2d	v22, v24, v10[0]
10000aab0: 4e76d6b5    	fadd.2d	v21, v21, v22
10000aab4: 4fca99d6    	fmul.2d	v22, v14, v10[1]
10000aab8: 4e76d6b5    	fadd.2d	v21, v21, v22
10000aabc: 4fc99096    	fmul.2d	v22, v4, v9[0]
10000aac0: 4e76d6b5    	fadd.2d	v21, v21, v22
10000aac4: 4fc99876    	fmul.2d	v22, v3, v9[1]
10000aac8: 4e76d6b5    	fadd.2d	v21, v21, v22
10000aacc: 4fc19256    	fmul.2d	v22, v18, v1[0]
10000aad0: 4e76d6b5    	fadd.2d	v21, v21, v22
10000aad4: 3dc0aff2    	ldr	q18, [sp, #0x2b0]
10000aad8: 4fc19257    	fmul.2d	v23, v18, v1[0]
10000aadc: 3dc0a7f4    	ldr	q20, [sp, #0x290]
10000aae0: 4fc19a9f    	fmul.2d	v31, v20, v1[1]
10000aae4: 4fc19a36    	fmul.2d	v22, v17, v1[1]
10000aae8: 4e76d6a1    	fadd.2d	v1, v21, v22
10000aaec: 3d81b7e1    	str	q1, [sp, #0x6d0]
10000aaf0: 3dc17be1    	ldr	q1, [sp, #0x5e0]
10000aaf4: 3dc257e5    	ldr	q5, [sp, #0x950]
10000aaf8: 4fc59035    	fmul.2d	v21, v1, v5[0]
10000aafc: 6f00e401    	movi.2d	v1, #0000000000000000
10000ab00: 4e61d6b5    	fadd.2d	v21, v21, v1
10000ab04: 3dc047e6    	ldr	q6, [sp, #0x110]
10000ab08: 4fc598d6    	fmul.2d	v22, v6, v5[1]
10000ab0c: 4e76d6b5    	fadd.2d	v21, v21, v22
10000ab10: 3dc067f8    	ldr	q24, [sp, #0x190]
10000ab14: 3dc043e6    	ldr	q6, [sp, #0x100]
10000ab18: 4fd890d6    	fmul.2d	v22, v6, v24[0]
10000ab1c: 4e76d6b5    	fadd.2d	v21, v21, v22
10000ab20: 3dc1b3e6    	ldr	q6, [sp, #0x6c0]
10000ab24: 4fd898d6    	fmul.2d	v22, v6, v24[1]
10000ab28: 4e76d6b5    	fadd.2d	v21, v21, v22
10000ab2c: 3dc243e6    	ldr	q6, [sp, #0x900]
10000ab30: 4fc69176    	fmul.2d	v22, v11, v6[0]
10000ab34: 4e76d6b5    	fadd.2d	v21, v21, v22
10000ab38: 4fc699f6    	fmul.2d	v22, v15, v6[1]
10000ab3c: 4e76d6b5    	fadd.2d	v21, v21, v22
10000ab40: 3d803be7    	str	q7, [sp, #0xe0]
10000ab44: 4fc79356    	fmul.2d	v22, v26, v7[0]
10000ab48: 4e76d6b5    	fadd.2d	v21, v21, v22
10000ab4c: 4fc79bd6    	fmul.2d	v22, v30, v7[1]
10000ab50: 4e76d6b5    	fadd.2d	v21, v21, v22
10000ab54: 4fc29116    	fmul.2d	v22, v8, v2[0]
10000ab58: 4e76d6b5    	fadd.2d	v21, v21, v22
10000ab5c: 4fc29bb6    	fmul.2d	v22, v29, v2[1]
10000ab60: 4e76d6a6    	fadd.2d	v6, v21, v22
10000ab64: 3d82e7e6    	str	q6, [sp, #0xb90]
10000ab68: 3dc253e7    	ldr	q7, [sp, #0x940]
10000ab6c: 4fc098f5    	fmul.2d	v21, v7, v0[1]
10000ab70: 4fc090b9    	fmul.2d	v25, v5, v0[0]
10000ab74: 4e61d739    	fadd.2d	v25, v25, v1
10000ab78: 6f00e416    	movi.2d	v22, #0000000000000000
10000ab7c: 4e75d735    	fadd.2d	v21, v25, v21
10000ab80: 3dc09be1    	ldr	q1, [sp, #0x260]
10000ab84: 4fdb9039    	fmul.2d	v25, v1, v27[0]
10000ab88: 4e79d6b5    	fadd.2d	v21, v21, v25
10000ab8c: 3dc057eb    	ldr	q11, [sp, #0x150]
10000ab90: 4fdb9979    	fmul.2d	v25, v11, v27[1]
10000ab94: 4e79d6b5    	fadd.2d	v21, v21, v25
10000ab98: 3dc053fb    	ldr	q27, [sp, #0x140]
10000ab9c: 4fca9379    	fmul.2d	v25, v27, v10[0]
10000aba0: 4e79d6b5    	fadd.2d	v21, v21, v25
10000aba4: 3dc04bf0    	ldr	q16, [sp, #0x120]
10000aba8: 4fca9a19    	fmul.2d	v25, v16, v10[1]
10000abac: 4e79d6b5    	fadd.2d	v21, v21, v25
10000abb0: 3dc0cbea    	ldr	q10, [sp, #0x320]
10000abb4: 4fc99159    	fmul.2d	v25, v10, v9[0]
10000abb8: 4e79d6b5    	fadd.2d	v21, v21, v25
10000abbc: 3dc0bbe6    	ldr	q6, [sp, #0x2e0]
10000abc0: 4fc998d9    	fmul.2d	v25, v6, v9[1]
10000abc4: 4e79d6b5    	fadd.2d	v21, v21, v25
10000abc8: 4e77d6b5    	fadd.2d	v21, v21, v23
10000abcc: 4e7fd6a0    	fadd.2d	v0, v21, v31
10000abd0: 3dc1a3ef    	ldr	q15, [sp, #0x680]
10000abd4: 4fcf90b5    	fmul.2d	v21, v5, v15[0]
10000abd8: 4e76d6b5    	fadd.2d	v21, v21, v22
10000abdc: fd484ff3    	ldr	d19, [sp, #0x1098]
10000abe0: 3d82e3f3    	str	q19, [sp, #0xb80]
10000abe4: 4ea71cf7    	mov.16b	v23, v7
10000abe8: 4ea71cf6    	mov.16b	v22, v7
10000abec: 6e180677    	mov.d	v23[1], v19[0]
10000abf0: 4fcf9af7    	fmul.2d	v23, v23, v15[1]
10000abf4: 4e77d6b5    	fadd.2d	v21, v21, v23
10000abf8: 3dc19be9    	ldr	q9, [sp, #0x660]
10000abfc: 4fc99037    	fmul.2d	v23, v1, v9[0]
10000ac00: 4e77d6b5    	fadd.2d	v21, v21, v23
10000ac04: 4fc99977    	fmul.2d	v23, v11, v9[1]
10000ac08: 4e77d6b5    	fadd.2d	v21, v21, v23
10000ac0c: 3dc193eb    	ldr	q11, [sp, #0x640]
10000ac10: 4fcb9377    	fmul.2d	v23, v27, v11[0]
10000ac14: 4e77d6b5    	fadd.2d	v21, v21, v23
10000ac18: 4fcb9a17    	fmul.2d	v23, v16, v11[1]
10000ac1c: 4e77d6b5    	fadd.2d	v21, v21, v23
10000ac20: 3dc18fff    	ldr	q31, [sp, #0x630]
10000ac24: 4fdf9157    	fmul.2d	v23, v10, v31[0]
10000ac28: 4e77d6b5    	fadd.2d	v21, v21, v23
10000ac2c: 4fdf98d7    	fmul.2d	v23, v6, v31[1]
10000ac30: 4e77d6b5    	fadd.2d	v21, v21, v23
10000ac34: 3dc1a7ea    	ldr	q10, [sp, #0x690]
10000ac38: 4fca9257    	fmul.2d	v23, v18, v10[0]
10000ac3c: 4e77d6b5    	fadd.2d	v21, v21, v23
10000ac40: 4fca9a97    	fmul.2d	v23, v20, v10[1]
10000ac44: 4e77d6a1    	fadd.2d	v1, v21, v23
10000ac48: 3d8313e1    	str	q1, [sp, #0xc40]
10000ac4c: 4fcf9317    	fmul.2d	v23, v24, v15[0]
10000ac50: 6f00e412    	movi.2d	v18, #0000000000000000
10000ac54: 4e72d6f7    	fadd.2d	v23, v23, v18
10000ac58: 3dc063e1    	ldr	q1, [sp, #0x180]
10000ac5c: 4fcf9838    	fmul.2d	v24, v1, v15[1]
10000ac60: 4e78d6f7    	fadd.2d	v23, v23, v24
10000ac64: 3dc097f5    	ldr	q21, [sp, #0x250]
10000ac68: 4fc992b8    	fmul.2d	v24, v21, v9[0]
10000ac6c: 4e78d6f7    	fadd.2d	v23, v23, v24
10000ac70: 3dc0d7e1    	ldr	q1, [sp, #0x350]
10000ac74: 4fc99838    	fmul.2d	v24, v1, v9[1]
10000ac78: 4e78d6f7    	fadd.2d	v23, v23, v24
10000ac7c: 3dc04fe1    	ldr	q1, [sp, #0x130]
10000ac80: 4fcb9038    	fmul.2d	v24, v1, v11[0]
10000ac84: 4e78d6f7    	fadd.2d	v23, v23, v24
10000ac88: 3dc02ff3    	ldr	q19, [sp, #0xb0]
10000ac8c: 4fcb9a78    	fmul.2d	v24, v19, v11[1]
10000ac90: 4e78d6f7    	fadd.2d	v23, v23, v24
10000ac94: 3dc0c3e1    	ldr	q1, [sp, #0x300]
10000ac98: 4fdf9038    	fmul.2d	v24, v1, v31[0]
10000ac9c: 4e78d6f7    	fadd.2d	v23, v23, v24
10000aca0: 3dc0b7e1    	ldr	q1, [sp, #0x2d0]
10000aca4: 4fdf9838    	fmul.2d	v24, v1, v31[1]
10000aca8: 4e78d6f7    	fadd.2d	v23, v23, v24
10000acac: 3dc0abe1    	ldr	q1, [sp, #0x2a0]
10000acb0: 4fca9038    	fmul.2d	v24, v1, v10[0]
10000acb4: 4e78d6f7    	fadd.2d	v23, v23, v24
10000acb8: 3dc0a3e1    	ldr	q1, [sp, #0x280]
10000acbc: 4fca9838    	fmul.2d	v24, v1, v10[1]
10000acc0: 4e78d6e1    	fadd.2d	v1, v23, v24
10000acc4: 3d830fe1    	str	q1, [sp, #0xc30]
10000acc8: 3dc243e1    	ldr	q1, [sp, #0x900]
10000accc: 4fcf9038    	fmul.2d	v24, v1, v15[0]
10000acd0: 4e72d718    	fadd.2d	v24, v24, v18
10000acd4: 6f00e410    	movi.2d	v16, #0000000000000000
10000acd8: 3dc05fe6    	ldr	q6, [sp, #0x170]
10000acdc: 4fcf98d9    	fmul.2d	v25, v6, v15[1]
10000ace0: 4e79d718    	fadd.2d	v24, v24, v25
10000ace4: 3dc0d3e1    	ldr	q1, [sp, #0x340]
10000ace8: 4fc99039    	fmul.2d	v25, v1, v9[0]
10000acec: 4e79d718    	fadd.2d	v24, v24, v25
10000acf0: 3dc0c7e1    	ldr	q1, [sp, #0x310]
10000acf4: 4fc99839    	fmul.2d	v25, v1, v9[1]
10000acf8: 4e79d718    	fadd.2d	v24, v24, v25
10000acfc: 3dc093e1    	ldr	q1, [sp, #0x240]
10000ad00: 4fcb9039    	fmul.2d	v25, v1, v11[0]
10000ad04: 4e79d718    	fadd.2d	v24, v24, v25
10000ad08: 3dc073f4    	ldr	q20, [sp, #0x1c0]
10000ad0c: 4fcb9a99    	fmul.2d	v25, v20, v11[1]
10000ad10: 4e79d718    	fadd.2d	v24, v24, v25
10000ad14: 3dc23be6    	ldr	q6, [sp, #0x8e0]
10000ad18: 4fdf90d9    	fmul.2d	v25, v6, v31[0]
10000ad1c: 4e79d718    	fadd.2d	v24, v24, v25
10000ad20: 3dc24ff2    	ldr	q18, [sp, #0x930]
10000ad24: 4fdf9a59    	fmul.2d	v25, v18, v31[1]
10000ad28: 4e79d718    	fadd.2d	v24, v24, v25
10000ad2c: 3dc237e6    	ldr	q6, [sp, #0x8d0]
10000ad30: 4fca90d9    	fmul.2d	v25, v6, v10[0]
10000ad34: 4e79d718    	fadd.2d	v24, v24, v25
10000ad38: 3dc09fe6    	ldr	q6, [sp, #0x270]
10000ad3c: 4fca98d9    	fmul.2d	v25, v6, v10[1]
10000ad40: 4e79d718    	fadd.2d	v24, v24, v25
10000ad44: ad469ff7    	ldp	q23, q7, [sp, #0xd0]
10000ad48: 4fcf90f9    	fmul.2d	v25, v7, v15[0]
10000ad4c: 4e70d739    	fadd.2d	v25, v25, v16
10000ad50: 4fcf9afb    	fmul.2d	v27, v23, v15[1]
10000ad54: 4e7bd739    	fadd.2d	v25, v25, v27
10000ad58: 3dc0cfe6    	ldr	q6, [sp, #0x330]
10000ad5c: 4fc990db    	fmul.2d	v27, v6, v9[0]
10000ad60: 4e7bd739    	fadd.2d	v25, v25, v27
10000ad64: 3dc0bfe6    	ldr	q6, [sp, #0x2f0]
10000ad68: 4fc998db    	fmul.2d	v27, v6, v9[1]
10000ad6c: 4e7bd739    	fadd.2d	v25, v25, v27
10000ad70: ad1073ed    	stp	q13, q28, [sp, #0x200]
10000ad74: 4fcb939b    	fmul.2d	v27, v28, v11[0]
10000ad78: 4e7bd739    	fadd.2d	v25, v25, v27
10000ad7c: 4fcb99bb    	fmul.2d	v27, v13, v11[1]
10000ad80: 4e7bd739    	fadd.2d	v25, v25, v27
10000ad84: 3dc06ff0    	ldr	q16, [sp, #0x1b0]
10000ad88: 4fdf921b    	fmul.2d	v27, v16, v31[0]
10000ad8c: 4e7bd739    	fadd.2d	v25, v25, v27
10000ad90: 4fdf999b    	fmul.2d	v27, v12, v31[1]
10000ad94: 4e7bd739    	fadd.2d	v25, v25, v27
10000ad98: 3dc24bf2    	ldr	q18, [sp, #0x920]
10000ad9c: 4fca925b    	fmul.2d	v27, v18, v10[0]
10000ada0: 4e7bd739    	fadd.2d	v25, v25, v27
10000ada4: 3dc247e6    	ldr	q6, [sp, #0x910]
10000ada8: 4fca98db    	fmul.2d	v27, v6, v10[1]
10000adac: 4e7bd739    	fadd.2d	v25, v25, v27
10000adb0: 3d808be2    	str	q2, [sp, #0x220]
10000adb4: 4fcf905b    	fmul.2d	v27, v2, v15[0]
10000adb8: 3dc23fe2    	ldr	q2, [sp, #0x8f0]
10000adbc: 4fcf985c    	fmul.2d	v28, v2, v15[1]
10000adc0: 6f00e402    	movi.2d	v2, #0000000000000000
10000adc4: 4e62d77b    	fadd.2d	v27, v27, v2
10000adc8: 4e7cd77b    	fadd.2d	v27, v27, v28
10000adcc: 3dc05bf2    	ldr	q18, [sp, #0x160]
10000add0: 4fc9925c    	fmul.2d	v28, v18, v9[0]
10000add4: 4e7cd77b    	fadd.2d	v27, v27, v28
10000add8: 3dc033e6    	ldr	q6, [sp, #0xc0]
10000addc: 4fc998dc    	fmul.2d	v28, v6, v9[1]
10000ade0: 4e7cd77b    	fadd.2d	v27, v27, v28
10000ade4: 3dc0b3fc    	ldr	q28, [sp, #0x2c0]
10000ade8: 4fcb939c    	fmul.2d	v28, v28, v11[0]
10000adec: 4e7cd77b    	fadd.2d	v27, v27, v28
10000adf0: ad0f3be4    	stp	q4, q14, [sp, #0x1e0]
10000adf4: 4fcb99dc    	fmul.2d	v28, v14, v11[1]
10000adf8: 4eb21e49    	mov.16b	v9, v18
10000adfc: 4e7cd77b    	fadd.2d	v27, v27, v28
10000ae00: 4fdf909c    	fmul.2d	v28, v4, v31[0]
10000ae04: 4ea51ca4    	mov.16b	v4, v5
10000ae08: 4e7cd77b    	fadd.2d	v27, v27, v28
10000ae0c: 3d8077e3    	str	q3, [sp, #0x1d0]
10000ae10: 4fdf987c    	fmul.2d	v28, v3, v31[1]
10000ae14: 4ea11c2e    	mov.16b	v14, v1
10000ae18: 4e7cd77b    	fadd.2d	v27, v27, v28
10000ae1c: 3dc06be1    	ldr	q1, [sp, #0x1a0]
10000ae20: 4fca903c    	fmul.2d	v28, v1, v10[0]
10000ae24: 4e7cd77b    	fadd.2d	v27, v27, v28
10000ae28: 4fca9a3c    	fmul.2d	v28, v17, v10[1]
10000ae2c: 4e7cd76a    	fadd.2d	v10, v27, v28
10000ae30: 3dc17bf2    	ldr	q18, [sp, #0x5e0]
10000ae34: 4fc0925b    	fmul.2d	v27, v18, v0[0]
10000ae38: 4e62d77b    	fadd.2d	v27, v27, v2
10000ae3c: 3d81afe0    	str	q0, [sp, #0x6b0]
10000ae40: ad487fe5    	ldp	q5, q31, [sp, #0x100]
10000ae44: 4fc09bfc    	fmul.2d	v28, v31, v0[1]
10000ae48: 4e7bd79b    	fadd.2d	v27, v28, v27
10000ae4c: 3dc31fe0    	ldr	q0, [sp, #0xc70]
10000ae50: 4fc090bc    	fmul.2d	v28, v5, v0[0]
10000ae54: 4e7bd79b    	fadd.2d	v27, v28, v27
10000ae58: 3dc1b3e3    	ldr	q3, [sp, #0x6c0]
10000ae5c: 4fc0987c    	fmul.2d	v28, v3, v0[1]
10000ae60: 4e7bd79b    	fadd.2d	v27, v28, v27
10000ae64: 3dc31be0    	ldr	q0, [sp, #0xc60]
10000ae68: 3dc18bed    	ldr	q13, [sp, #0x620]
10000ae6c: 4fc091bc    	fmul.2d	v28, v13, v0[0]
10000ae70: 4e7bd79b    	fadd.2d	v27, v28, v27
10000ae74: 3dc187eb    	ldr	q11, [sp, #0x610]
10000ae78: 4fc0997c    	fmul.2d	v28, v11, v0[1]
10000ae7c: 4e7bd79b    	fadd.2d	v27, v28, v27
10000ae80: 3dc317e0    	ldr	q0, [sp, #0xc50]
10000ae84: 4fc0935c    	fmul.2d	v28, v26, v0[0]
10000ae88: 4e7bd79b    	fadd.2d	v27, v28, v27
10000ae8c: 4fc09bdc    	fmul.2d	v28, v30, v0[1]
10000ae90: 4e7bd79b    	fadd.2d	v27, v28, v27
10000ae94: 3dc1b7e0    	ldr	q0, [sp, #0x6d0]
10000ae98: 4fc0911c    	fmul.2d	v28, v8, v0[0]
10000ae9c: 4e7bd79b    	fadd.2d	v27, v28, v27
10000aea0: 4fc09bbc    	fmul.2d	v28, v29, v0[1]
10000aea4: 4e7bd79b    	fadd.2d	v27, v28, v27
10000aea8: 3dc1abe0    	ldr	q0, [sp, #0x6a0]
10000aeac: 4e7bd400    	fadd.2d	v0, v0, v27
10000aeb0: 3d81abe0    	str	q0, [sp, #0x6a0]
10000aeb4: 3dc313e0    	ldr	q0, [sp, #0xc40]
10000aeb8: 4fc0925b    	fmul.2d	v27, v18, v0[0]
10000aebc: 4e62d762    	fadd.2d	v2, v27, v2
10000aec0: 4fc09bfb    	fmul.2d	v27, v31, v0[1]
10000aec4: 4e62d762    	fadd.2d	v2, v27, v2
10000aec8: 3dc30fe0    	ldr	q0, [sp, #0xc30]
10000aecc: 4fc090bb    	fmul.2d	v27, v5, v0[0]
10000aed0: 4e62d762    	fadd.2d	v2, v27, v2
10000aed4: 4fc0987b    	fmul.2d	v27, v3, v0[1]
10000aed8: 4eaa1d40    	mov.16b	v0, v10
10000aedc: 4e62d762    	fadd.2d	v2, v27, v2
10000aee0: 4fd891bb    	fmul.2d	v27, v13, v24[0]
10000aee4: 4e62d762    	fadd.2d	v2, v27, v2
10000aee8: 4fd8997b    	fmul.2d	v27, v11, v24[1]
10000aeec: 4e62d762    	fadd.2d	v2, v27, v2
10000aef0: 4fd9935b    	fmul.2d	v27, v26, v25[0]
10000aef4: 4ea71cf2    	mov.16b	v18, v7
10000aef8: 4e62d762    	fadd.2d	v2, v27, v2
10000aefc: 1e7e101b    	fmov	d27, #-1.00000000
10000af00: 1e7b289c    	fadd	d28, d4, d27
10000af04: 6e080784    	mov.d	v4[0], v28[0]
10000af08: 3dc04bea    	ldr	q10, [sp, #0x120]
10000af0c: 3dc2e3e3    	ldr	q3, [sp, #0xb80]
10000af10: 1e7b287a    	fadd	d26, d3, d27
10000af14: 6e180756    	mov.d	v22[1], v26[0]
10000af18: 3d8253f6    	str	q22, [sp, #0x940]
10000af1c: 1e7b2aba    	fadd	d26, d21, d27
10000af20: 6e080755    	mov.d	v21[0], v26[0]
10000af24: 4fd99bda    	fmul.2d	v26, v30, v25[1]
10000af28: 4eb51ebe    	mov.16b	v30, v21
10000af2c: 4e62d742    	fadd.2d	v2, v26, v2
10000af30: 3dc0d7ef    	ldr	q15, [sp, #0x350]
10000af34: 5e1805fa    	mov	d26, v15[1]
10000af38: 1e7b2b5a    	fadd	d26, d26, d27
10000af3c: 6e18074f    	mov.d	v15[1], v26[0]
10000af40: 4fc0911a    	fmul.2d	v26, v8, v0[0]
10000af44: 4e62d742    	fadd.2d	v2, v26, v2
10000af48: 1e7b29da    	fadd	d26, d14, d27
10000af4c: 6e08074e    	mov.d	v14[0], v26[0]
10000af50: 5e18069a    	mov	d26, v20[1]
10000af54: 1e7b2b5a    	fadd	d26, d26, d27
10000af58: 6e180754    	mov.d	v20[1], v26[0]
10000af5c: 4eb41e8d    	mov.16b	v13, v20
10000af60: 1e7b2a1a    	fadd	d26, d16, d27
10000af64: 6e080750    	mov.d	v16[0], v26[0]
10000af68: 4eb01e1f    	mov.16b	v31, v16
10000af6c: 3d81a7e0    	str	q0, [sp, #0x690]
10000af70: 4fc09bba    	fmul.2d	v26, v29, v0[1]
10000af74: 4ea61cdd    	mov.16b	v29, v6
10000af78: 4e62d742    	fadd.2d	v2, v26, v2
10000af7c: 5e18059a    	mov	d26, v12[1]
10000af80: 1e7b2b5a    	fadd	d26, d26, d27
10000af84: 6e18074c    	mov.d	v12[1], v26[0]
10000af88: 3d808fec    	str	q12, [sp, #0x230]
10000af8c: 4eb31e6c    	mov.16b	v12, v19
10000af90: 5e18063a    	mov	d26, v17[1]
10000af94: 1e7b2b5a    	fadd	d26, d26, d27
10000af98: 1e7b283b    	fadd	d27, d1, d27
10000af9c: 6e080761    	mov.d	v1[0], v27[0]
10000afa0: 4ea11c2b    	mov.16b	v11, v1
10000afa4: 4eb71efb    	mov.16b	v27, v23
10000afa8: 6e180751    	mov.d	v17[1], v26[0]
10000afac: 4eb11e3a    	mov.16b	v26, v17
10000afb0: 3dc16bfc    	ldr	q28, [sp, #0x5a0]
10000afb4: 4e62d79c    	fadd.2d	v28, v28, v2
10000afb8: 3dc2e7f6    	ldr	q22, [sp, #0xb90]
10000afbc: 3dc30be0    	ldr	q0, [sp, #0xc20]
10000afc0: 3dc307e1    	ldr	q1, [sp, #0xc10]
10000afc4: 3dc303e3    	ldr	q3, [sp, #0xc00]
10000afc8: 3dc2ffe5    	ldr	q5, [sp, #0xbf0]
10000afcc: 3dc2fbe7    	ldr	q7, [sp, #0xbe0]
10000afd0: 3dc2f7f0    	ldr	q16, [sp, #0xbd0]
10000afd4: 3dc2f3f1    	ldr	q17, [sp, #0xbc0]
10000afd8: 3dc2ebf4    	ldr	q20, [sp, #0xba0]
10000afdc: 3dc2eff3    	ldr	q19, [sp, #0xbb0]
10000afe0: 3dc31fe2    	ldr	q2, [sp, #0xc70]
10000afe4: 3dc31be6    	ldr	q6, [sp, #0xc60]
10000afe8: 3d819fe6    	str	q6, [sp, #0x670]
10000afec: ad4a1be8    	ldp	q8, q6, [sp, #0x140]
10000aff0: 3dc317f5    	ldr	q21, [sp, #0xc50]
10000aff4: 3d8197f5    	str	q21, [sp, #0x650]
10000aff8: 3dc313f5    	ldr	q21, [sp, #0xc40]
10000affc: 3d81a3f5    	str	q21, [sp, #0x680]
10000b000: 3dc30ff7    	ldr	q23, [sp, #0xc30]
10000b004: 3d819bf7    	str	q23, [sp, #0x660]
10000b008: ad4c57f7    	ldp	q23, q21, [sp, #0x180]
10000b00c: 3d8193f8    	str	q24, [sp, #0x640]
10000b010: 3dc04ff8    	ldr	q24, [sp, #0x130]
10000b014: 3d818ff9    	str	q25, [sp, #0x630]
10000b018: 3dc05ff9    	ldr	q25, [sp, #0x170]
10000b01c: b0000088    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000b020: 91064108    	add	x8, x8, #0x190
10000b024: ad005504    	stp	q4, q21, [x8]
10000b028: 3dc243e4    	ldr	q4, [sp, #0x900]
10000b02c: ad014904    	stp	q4, q18, [x8, #0x20]
10000b030: 3dc08be4    	ldr	q4, [sp, #0x220]
10000b034: ad025904    	stp	q4, q22, [x8, #0x40]
10000b038: 3dc253e4    	ldr	q4, [sp, #0x940]
10000b03c: ad035d04    	stp	q4, q23, [x8, #0x60]
10000b040: ad046d19    	stp	q25, q27, [x8, #0x80]
10000b044: 3dc23fe4    	ldr	q4, [sp, #0x8f0]
10000b048: ad050104    	stp	q4, q0, [x8, #0xa0]
10000b04c: 3dc09be0    	ldr	q0, [sp, #0x260]
10000b050: ad067900    	stp	q0, q30, [x8, #0xc0]
10000b054: ad5993e0    	ldp	q0, q4, [sp, #0x330]
10000b058: ad070104    	stp	q4, q0, [x8, #0xe0]
10000b05c: ad080509    	stp	q9, q1, [x8, #0x100]
10000b060: ad093d06    	stp	q6, q15, [x8, #0x120]
10000b064: 3dc0c7e1    	ldr	q1, [sp, #0x310]
10000b068: 3dc0bfe0    	ldr	q0, [sp, #0x2f0]
10000b06c: ad0a0101    	stp	q1, q0, [x8, #0x140]
10000b070: ad0b0d1d    	stp	q29, q3, [x8, #0x160]
10000b074: ad0c6108    	stp	q8, q24, [x8, #0x180]
10000b078: 3dc087e0    	ldr	q0, [sp, #0x210]
10000b07c: ad0d010e    	stp	q14, q0, [x8, #0x1a0]
10000b080: 3dc0b3e0    	ldr	q0, [sp, #0x2c0]
10000b084: ad0e1500    	stp	q0, q5, [x8, #0x1c0]
10000b088: ad0f310a    	stp	q10, q12, [x8, #0x1e0]
10000b08c: ad4f87e0    	ldp	q0, q1, [sp, #0x1f0]
10000b090: ad10050d    	stp	q13, q1, [x8, #0x200]
10000b094: ad111d00    	stp	q0, q7, [x8, #0x220]
10000b098: 3dc0cbe1    	ldr	q1, [sp, #0x320]
10000b09c: 3dc0c3e0    	ldr	q0, [sp, #0x300]
10000b0a0: ad120101    	stp	q1, q0, [x8, #0x240]
10000b0a4: 3dc23be0    	ldr	q0, [sp, #0x8e0]
10000b0a8: ad137d00    	stp	q0, q31, [x8, #0x260]
10000b0ac: 3dc07be0    	ldr	q0, [sp, #0x1e0]
10000b0b0: ad144100    	stp	q0, q16, [x8, #0x280]
10000b0b4: ad5687e0    	ldp	q0, q1, [sp, #0x2d0]
10000b0b8: ad150101    	stp	q1, q0, [x8, #0x2a0]
10000b0bc: 3dc24fe1    	ldr	q1, [sp, #0x930]
10000b0c0: 3dc08fe0    	ldr	q0, [sp, #0x230]
10000b0c4: ad160101    	stp	q1, q0, [x8, #0x2c0]
10000b0c8: 3dc077e0    	ldr	q0, [sp, #0x1d0]
10000b0cc: ad174500    	stp	q0, q17, [x8, #0x2e0]
10000b0d0: ad5507e0    	ldp	q0, q1, [sp, #0x2a0]
10000b0d4: ad180101    	stp	q1, q0, [x8, #0x300]
10000b0d8: 3dc237e1    	ldr	q1, [sp, #0x8d0]
10000b0dc: 3dc24be0    	ldr	q0, [sp, #0x920]
10000b0e0: ad190101    	stp	q1, q0, [x8, #0x320]
10000b0e4: ad1a510b    	stp	q11, q20, [x8, #0x340]
10000b0e8: ad5407e0    	ldp	q0, q1, [sp, #0x280]
10000b0ec: ad1b0101    	stp	q1, q0, [x8, #0x360]
10000b0f0: 3dc09fe1    	ldr	q1, [sp, #0x270]
10000b0f4: 3dc247e0    	ldr	q0, [sp, #0x910]
10000b0f8: ad1c0101    	stp	q1, q0, [x8, #0x380]
10000b0fc: ad1d4d1a    	stp	q26, q19, [x8, #0x3a0]
10000b100: 3dc1afe0    	ldr	q0, [sp, #0x6b0]
10000b104: ad1e0900    	stp	q0, q2, [x8, #0x3c0]
10000b108: 3dc19fe1    	ldr	q1, [sp, #0x670]
10000b10c: 3dc197e0    	ldr	q0, [sp, #0x650]
10000b110: ad1f0101    	stp	q1, q0, [x8, #0x3e0]
10000b114: 3dc1b7e0    	ldr	q0, [sp, #0x6d0]
10000b118: 3d810100    	str	q0, [x8, #0x400]
10000b11c: 3dc1abe0    	ldr	q0, [sp, #0x6a0]
10000b120: 3d810500    	str	q0, [x8, #0x410]
10000b124: 3dc1a3e0    	ldr	q0, [sp, #0x680]
10000b128: 3d810900    	str	q0, [x8, #0x420]
10000b12c: 3dc19be0    	ldr	q0, [sp, #0x660]
10000b130: 3d810d00    	str	q0, [x8, #0x430]
10000b134: 3dc193e0    	ldr	q0, [sp, #0x640]
10000b138: 3d811100    	str	q0, [x8, #0x440]
10000b13c: 3dc18fe0    	ldr	q0, [sp, #0x630]
10000b140: 3d811500    	str	q0, [x8, #0x450]
10000b144: 3dc1a7e0    	ldr	q0, [sp, #0x690]
10000b148: 3d811900    	str	q0, [x8, #0x460]
10000b14c: 3d811d1c    	str	q28, [x8, #0x470]
10000b150: 914007ff    	add	sp, sp, #0x1, lsl #12   ; =0x1000
10000b154: 910d83ff    	add	sp, sp, #0x360
10000b158: a9497bfd    	ldp	x29, x30, [sp, #0x90]
10000b15c: a9484ff4    	ldp	x20, x19, [sp, #0x80]
10000b160: a94757f6    	ldp	x22, x21, [sp, #0x70]
10000b164: a9465ff8    	ldp	x24, x23, [sp, #0x60]
10000b168: a94567fa    	ldp	x26, x25, [sp, #0x50]
10000b16c: a9446ffc    	ldp	x28, x27, [sp, #0x40]
10000b170: 6d4323e9    	ldp	d9, d8, [sp, #0x30]
10000b174: 6d422beb    	ldp	d11, d10, [sp, #0x20]
10000b178: 6d4133ed    	ldp	d13, d12, [sp, #0x10]
10000b17c: 6cca3bef    	ldp	d15, d14, [sp], #0xa0
10000b180: d65f03c0    	ret
