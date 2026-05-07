
/Users/swadhinnanda/Projects/git/zdisamar-labos-bottleneck/research/performance/where-is-the-bottleneck/primitive-codegen/outputs/bench-primitives:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000001000006c8 <_main>:
1000006c8: d10503ff    	sub	sp, sp, #0x140
1000006cc: 6d0d23e9    	stp	d9, d8, [sp, #0xd0]
1000006d0: a90e6ffc    	stp	x28, x27, [sp, #0xe0]
1000006d4: a90f67fa    	stp	x26, x25, [sp, #0xf0]
1000006d8: a9105ff8    	stp	x24, x23, [sp, #0x100]
1000006dc: a91157f6    	stp	x22, x21, [sp, #0x110]
1000006e0: a9124ff4    	stp	x20, x19, [sp, #0x120]
1000006e4: a9137bfd    	stp	x29, x30, [sp, #0x130]
1000006e8: 9104c3fd    	add	x29, sp, #0x130
1000006ec: d2800008    	mov	x8, #0x0                ; =0
1000006f0: f8687849    	ldr	x9, [x2, x8, lsl #3]
1000006f4: 91000508    	add	x8, x8, #0x1
1000006f8: b5ffffc9    	cbnz	x9, 0x1000006f0 <_main+0x28>
1000006fc: 2a0003e9    	mov	w9, w0
100000700: 900000ea    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
100000704: 9118814a    	add	x10, x10, #0x620
100000708: a9002541    	stp	x1, x9, [x10]
10000070c: d1000508    	sub	x8, x8, #0x1
100000710: a9012142    	stp	x2, x8, [x10, #0x10]
100000714: b0000008    	adrp	x8, 0x100001000 <_main+0x938>
100000718: 91376108    	add	x8, x8, #0xdd8
10000071c: f9003be8    	str	x8, [sp, #0x70]
100000720: 9100c3e0    	add	x0, sp, #0x30
100000724: 940039ce    	bl	0x10000ee5c <dyld_stub_binder+0x10000ee5c>
100000728: 3100041f    	cmn	w0, #0x1
10000072c: 54000041    	b.ne	0x100000734 <_main+0x6c>
100000730: 940039d7    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
100000734: b94033e8    	ldr	w8, [sp, #0x30]
100000738: 290f7fe8    	stp	w8, wzr, [sp, #0x78]
10000073c: 9101c3e1    	add	x1, sp, #0x70
100000740: 528001a0    	mov	w0, #0xd                ; =13
100000744: d2800002    	mov	x2, #0x0                ; =0
100000748: 940039c2    	bl	0x10000ee50 <dyld_stub_binder+0x10000ee50>
10000074c: 3100041f    	cmn	w0, #0x1
100000750: 54000041    	b.ne	0x100000758 <_main+0x90>
100000754: 940039ce    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
100000758: d0000068    	adrp	x8, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000075c: 3dc3fd00    	ldr	q0, [x8, #0xff0]
100000760: f0000068    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000764: 3dc00101    	ldr	q1, [x8]
100000768: 900000e8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000076c: 91190108    	add	x8, x8, #0x640
100000770: ad000500    	stp	q0, q1, [x8]
100000774: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000778: 3dc00520    	ldr	q0, [x9, #0x10]
10000077c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000780: 3dc00921    	ldr	q1, [x9, #0x20]
100000784: ad010500    	stp	q0, q1, [x8, #0x20]
100000788: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000078c: 3dc00d20    	ldr	q0, [x9, #0x30]
100000790: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000794: 3dc01121    	ldr	q1, [x9, #0x40]
100000798: ad020500    	stp	q0, q1, [x8, #0x40]
10000079c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007a0: 3dc01520    	ldr	q0, [x9, #0x50]
1000007a4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007a8: 3dc01921    	ldr	q1, [x9, #0x60]
1000007ac: ad030500    	stp	q0, q1, [x8, #0x60]
1000007b0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007b4: 3dc01d20    	ldr	q0, [x9, #0x70]
1000007b8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007bc: 3dc02121    	ldr	q1, [x9, #0x80]
1000007c0: ad040500    	stp	q0, q1, [x8, #0x80]
1000007c4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007c8: 3dc02520    	ldr	q0, [x9, #0x90]
1000007cc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007d0: 3dc02921    	ldr	q1, [x9, #0xa0]
1000007d4: ad050500    	stp	q0, q1, [x8, #0xa0]
1000007d8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007dc: 3dc02d20    	ldr	q0, [x9, #0xb0]
1000007e0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007e4: 3dc03121    	ldr	q1, [x9, #0xc0]
1000007e8: ad060500    	stp	q0, q1, [x8, #0xc0]
1000007ec: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007f0: 3dc03520    	ldr	q0, [x9, #0xd0]
1000007f4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000007f8: 3dc03921    	ldr	q1, [x9, #0xe0]
1000007fc: ad070500    	stp	q0, q1, [x8, #0xe0]
100000800: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000804: 3dc03d20    	ldr	q0, [x9, #0xf0]
100000808: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000080c: 3dc04121    	ldr	q1, [x9, #0x100]
100000810: ad080500    	stp	q0, q1, [x8, #0x100]
100000814: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000818: 3dc04520    	ldr	q0, [x9, #0x110]
10000081c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000820: 3dc04921    	ldr	q1, [x9, #0x120]
100000824: ad090500    	stp	q0, q1, [x8, #0x120]
100000828: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000082c: 3dc04d20    	ldr	q0, [x9, #0x130]
100000830: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000834: 3dc05121    	ldr	q1, [x9, #0x140]
100000838: ad0a0500    	stp	q0, q1, [x8, #0x140]
10000083c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000840: 3dc05520    	ldr	q0, [x9, #0x150]
100000844: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000848: 3dc05921    	ldr	q1, [x9, #0x160]
10000084c: ad0b0500    	stp	q0, q1, [x8, #0x160]
100000850: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000854: 3dc05d20    	ldr	q0, [x9, #0x170]
100000858: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000085c: 3dc06121    	ldr	q1, [x9, #0x180]
100000860: ad0c0500    	stp	q0, q1, [x8, #0x180]
100000864: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000868: 3dc06520    	ldr	q0, [x9, #0x190]
10000086c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000870: 3dc06921    	ldr	q1, [x9, #0x1a0]
100000874: ad0d0500    	stp	q0, q1, [x8, #0x1a0]
100000878: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000087c: 3dc06d20    	ldr	q0, [x9, #0x1b0]
100000880: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000884: 3dc07121    	ldr	q1, [x9, #0x1c0]
100000888: ad0e0500    	stp	q0, q1, [x8, #0x1c0]
10000088c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000890: 3dc07520    	ldr	q0, [x9, #0x1d0]
100000894: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000898: 3dc07921    	ldr	q1, [x9, #0x1e0]
10000089c: ad0f0500    	stp	q0, q1, [x8, #0x1e0]
1000008a0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008a4: 3dc07d20    	ldr	q0, [x9, #0x1f0]
1000008a8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008ac: 3dc08121    	ldr	q1, [x9, #0x200]
1000008b0: ad100500    	stp	q0, q1, [x8, #0x200]
1000008b4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008b8: 3dc08520    	ldr	q0, [x9, #0x210]
1000008bc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008c0: 3dc08921    	ldr	q1, [x9, #0x220]
1000008c4: ad110500    	stp	q0, q1, [x8, #0x220]
1000008c8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008cc: 3dc08d20    	ldr	q0, [x9, #0x230]
1000008d0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008d4: 3dc09121    	ldr	q1, [x9, #0x240]
1000008d8: ad120500    	stp	q0, q1, [x8, #0x240]
1000008dc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008e0: 3dc09520    	ldr	q0, [x9, #0x250]
1000008e4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008e8: 3dc09921    	ldr	q1, [x9, #0x260]
1000008ec: ad130500    	stp	q0, q1, [x8, #0x260]
1000008f0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008f4: 3dc09d20    	ldr	q0, [x9, #0x270]
1000008f8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000008fc: 3dc0a121    	ldr	q1, [x9, #0x280]
100000900: ad140500    	stp	q0, q1, [x8, #0x280]
100000904: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000908: 3dc0a520    	ldr	q0, [x9, #0x290]
10000090c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000910: 3dc0a921    	ldr	q1, [x9, #0x2a0]
100000914: ad150500    	stp	q0, q1, [x8, #0x2a0]
100000918: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000091c: 3dc0ad20    	ldr	q0, [x9, #0x2b0]
100000920: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000924: 3dc0b121    	ldr	q1, [x9, #0x2c0]
100000928: ad160500    	stp	q0, q1, [x8, #0x2c0]
10000092c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000930: 3dc0b520    	ldr	q0, [x9, #0x2d0]
100000934: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000938: 3dc0b921    	ldr	q1, [x9, #0x2e0]
10000093c: ad170500    	stp	q0, q1, [x8, #0x2e0]
100000940: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000944: 3dc0bd20    	ldr	q0, [x9, #0x2f0]
100000948: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000094c: 3dc0c121    	ldr	q1, [x9, #0x300]
100000950: ad180500    	stp	q0, q1, [x8, #0x300]
100000954: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000958: 3dc0c520    	ldr	q0, [x9, #0x310]
10000095c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000960: 3dc0c921    	ldr	q1, [x9, #0x320]
100000964: ad190500    	stp	q0, q1, [x8, #0x320]
100000968: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000096c: 3dc0cd20    	ldr	q0, [x9, #0x330]
100000970: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000974: 3dc0d121    	ldr	q1, [x9, #0x340]
100000978: ad1a0500    	stp	q0, q1, [x8, #0x340]
10000097c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000980: 3dc0d520    	ldr	q0, [x9, #0x350]
100000984: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000988: 3dc0d921    	ldr	q1, [x9, #0x360]
10000098c: ad1b0500    	stp	q0, q1, [x8, #0x360]
100000990: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000994: 3dc0dd20    	ldr	q0, [x9, #0x370]
100000998: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000099c: 3dc0e121    	ldr	q1, [x9, #0x380]
1000009a0: ad1c0500    	stp	q0, q1, [x8, #0x380]
1000009a4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000009a8: 3dc0e520    	ldr	q0, [x9, #0x390]
1000009ac: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000009b0: 3dc0e921    	ldr	q1, [x9, #0x3a0]
1000009b4: ad1d0500    	stp	q0, q1, [x8, #0x3a0]
1000009b8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000009bc: 3dc0ed20    	ldr	q0, [x9, #0x3b0]
1000009c0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000009c4: 3dc0f121    	ldr	q1, [x9, #0x3c0]
1000009c8: ad1e0500    	stp	q0, q1, [x8, #0x3c0]
1000009cc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000009d0: 3dc0f520    	ldr	q0, [x9, #0x3d0]
1000009d4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000009d8: 3dc0f921    	ldr	q1, [x9, #0x3e0]
1000009dc: ad1f0500    	stp	q0, q1, [x8, #0x3e0]
1000009e0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000009e4: 3dc0fd20    	ldr	q0, [x9, #0x3f0]
1000009e8: 3d810100    	str	q0, [x8, #0x400]
1000009ec: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000009f0: 3dc10120    	ldr	q0, [x9, #0x400]
1000009f4: 3d810500    	str	q0, [x8, #0x410]
1000009f8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000009fc: 3dc10520    	ldr	q0, [x9, #0x410]
100000a00: 3d810900    	str	q0, [x8, #0x420]
100000a04: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a08: 3dc10920    	ldr	q0, [x9, #0x420]
100000a0c: 3d810d00    	str	q0, [x8, #0x430]
100000a10: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a14: 3dc10d20    	ldr	q0, [x9, #0x430]
100000a18: 3d811100    	str	q0, [x8, #0x440]
100000a1c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a20: 3dc11120    	ldr	q0, [x9, #0x440]
100000a24: 3d811500    	str	q0, [x8, #0x450]
100000a28: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a2c: 3dc11520    	ldr	q0, [x9, #0x450]
100000a30: 3d811900    	str	q0, [x8, #0x460]
100000a34: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a38: 3dc11920    	ldr	q0, [x9, #0x460]
100000a3c: 3d811d00    	str	q0, [x8, #0x470]
100000a40: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a44: 3dc11d20    	ldr	q0, [x9, #0x470]
100000a48: 3d812100    	str	q0, [x8, #0x480]
100000a4c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a50: 3dc12120    	ldr	q0, [x9, #0x480]
100000a54: 3d812500    	str	q0, [x8, #0x490]
100000a58: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a5c: 3dc12520    	ldr	q0, [x9, #0x490]
100000a60: 3d812900    	str	q0, [x8, #0x4a0]
100000a64: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a68: 3dc12920    	ldr	q0, [x9, #0x4a0]
100000a6c: 3d812d00    	str	q0, [x8, #0x4b0]
100000a70: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a74: 3dc12d20    	ldr	q0, [x9, #0x4b0]
100000a78: 3d813100    	str	q0, [x8, #0x4c0]
100000a7c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a80: 3dc13120    	ldr	q0, [x9, #0x4c0]
100000a84: 3d813500    	str	q0, [x8, #0x4d0]
100000a88: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a8c: 3dc13520    	ldr	q0, [x9, #0x4d0]
100000a90: 3d813900    	str	q0, [x8, #0x4e0]
100000a94: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000a98: 3dc13920    	ldr	q0, [x9, #0x4e0]
100000a9c: 3d813d00    	str	q0, [x8, #0x4f0]
100000aa0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000aa4: 3dc13d20    	ldr	q0, [x9, #0x4f0]
100000aa8: 3d814100    	str	q0, [x8, #0x500]
100000aac: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ab0: 3dc14120    	ldr	q0, [x9, #0x500]
100000ab4: 3d814500    	str	q0, [x8, #0x510]
100000ab8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000abc: 3dc14520    	ldr	q0, [x9, #0x510]
100000ac0: 3d814900    	str	q0, [x8, #0x520]
100000ac4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ac8: 3dc14920    	ldr	q0, [x9, #0x520]
100000acc: 3d814d00    	str	q0, [x8, #0x530]
100000ad0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ad4: 3dc14d20    	ldr	q0, [x9, #0x530]
100000ad8: 3d815100    	str	q0, [x8, #0x540]
100000adc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ae0: 3dc15120    	ldr	q0, [x9, #0x540]
100000ae4: 3d815500    	str	q0, [x8, #0x550]
100000ae8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000aec: 3dc15520    	ldr	q0, [x9, #0x550]
100000af0: 3d815900    	str	q0, [x8, #0x560]
100000af4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000af8: 3dc15920    	ldr	q0, [x9, #0x560]
100000afc: 3d815d00    	str	q0, [x8, #0x570]
100000b00: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b04: 3dc15d20    	ldr	q0, [x9, #0x570]
100000b08: 3d816100    	str	q0, [x8, #0x580]
100000b0c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b10: 3dc16120    	ldr	q0, [x9, #0x580]
100000b14: 3d816500    	str	q0, [x8, #0x590]
100000b18: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b1c: 3dc16520    	ldr	q0, [x9, #0x590]
100000b20: 3d816900    	str	q0, [x8, #0x5a0]
100000b24: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b28: 3dc16920    	ldr	q0, [x9, #0x5a0]
100000b2c: 3d816d00    	str	q0, [x8, #0x5b0]
100000b30: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b34: 3dc16d20    	ldr	q0, [x9, #0x5b0]
100000b38: 3d817100    	str	q0, [x8, #0x5c0]
100000b3c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b40: 3dc17120    	ldr	q0, [x9, #0x5c0]
100000b44: 3d817500    	str	q0, [x8, #0x5d0]
100000b48: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b4c: 3dc17520    	ldr	q0, [x9, #0x5d0]
100000b50: 3d817900    	str	q0, [x8, #0x5e0]
100000b54: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b58: 3dc17920    	ldr	q0, [x9, #0x5e0]
100000b5c: 3d817d00    	str	q0, [x8, #0x5f0]
100000b60: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b64: 3dc17d20    	ldr	q0, [x9, #0x5f0]
100000b68: 3d818100    	str	q0, [x8, #0x600]
100000b6c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b70: 3dc18120    	ldr	q0, [x9, #0x600]
100000b74: 3d818500    	str	q0, [x8, #0x610]
100000b78: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b7c: 3dc18520    	ldr	q0, [x9, #0x610]
100000b80: 3d818900    	str	q0, [x8, #0x620]
100000b84: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b88: 3dc18920    	ldr	q0, [x9, #0x620]
100000b8c: 3d818d00    	str	q0, [x8, #0x630]
100000b90: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000b94: 3dc18d20    	ldr	q0, [x9, #0x630]
100000b98: 3d819100    	str	q0, [x8, #0x640]
100000b9c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ba0: 3dc19120    	ldr	q0, [x9, #0x640]
100000ba4: 3d819500    	str	q0, [x8, #0x650]
100000ba8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000bac: 3dc19520    	ldr	q0, [x9, #0x650]
100000bb0: 3d819900    	str	q0, [x8, #0x660]
100000bb4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000bb8: 3dc19920    	ldr	q0, [x9, #0x660]
100000bbc: 3d819d00    	str	q0, [x8, #0x670]
100000bc0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000bc4: 3dc19d20    	ldr	q0, [x9, #0x670]
100000bc8: 3d81a100    	str	q0, [x8, #0x680]
100000bcc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000bd0: 3dc1a120    	ldr	q0, [x9, #0x680]
100000bd4: 3d81a500    	str	q0, [x8, #0x690]
100000bd8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000bdc: 3dc1a520    	ldr	q0, [x9, #0x690]
100000be0: 3d81a900    	str	q0, [x8, #0x6a0]
100000be4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000be8: 3dc1a920    	ldr	q0, [x9, #0x6a0]
100000bec: 3d81ad00    	str	q0, [x8, #0x6b0]
100000bf0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000bf4: 3dc1ad20    	ldr	q0, [x9, #0x6b0]
100000bf8: 3d81b100    	str	q0, [x8, #0x6c0]
100000bfc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c00: 3dc1b120    	ldr	q0, [x9, #0x6c0]
100000c04: 3d81b500    	str	q0, [x8, #0x6d0]
100000c08: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c0c: 3dc1b520    	ldr	q0, [x9, #0x6d0]
100000c10: 3d81b900    	str	q0, [x8, #0x6e0]
100000c14: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c18: 3dc1b920    	ldr	q0, [x9, #0x6e0]
100000c1c: 3d81bd00    	str	q0, [x8, #0x6f0]
100000c20: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c24: 3dc1bd20    	ldr	q0, [x9, #0x6f0]
100000c28: 3d81c100    	str	q0, [x8, #0x700]
100000c2c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c30: 3dc1c120    	ldr	q0, [x9, #0x700]
100000c34: 3d81c500    	str	q0, [x8, #0x710]
100000c38: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c3c: 3dc1c520    	ldr	q0, [x9, #0x710]
100000c40: 3d81c900    	str	q0, [x8, #0x720]
100000c44: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c48: 3dc1c920    	ldr	q0, [x9, #0x720]
100000c4c: 3d81cd00    	str	q0, [x8, #0x730]
100000c50: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c54: 3dc1cd20    	ldr	q0, [x9, #0x730]
100000c58: 3d81d100    	str	q0, [x8, #0x740]
100000c5c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c60: 3dc1d120    	ldr	q0, [x9, #0x740]
100000c64: 3d81d500    	str	q0, [x8, #0x750]
100000c68: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c6c: 3dc1d520    	ldr	q0, [x9, #0x750]
100000c70: 3d81d900    	str	q0, [x8, #0x760]
100000c74: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c78: 3dc1d920    	ldr	q0, [x9, #0x760]
100000c7c: 3d81dd00    	str	q0, [x8, #0x770]
100000c80: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c84: 3dc1dd20    	ldr	q0, [x9, #0x770]
100000c88: 3d81e100    	str	q0, [x8, #0x780]
100000c8c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c90: 3dc1e120    	ldr	q0, [x9, #0x780]
100000c94: 3d81e500    	str	q0, [x8, #0x790]
100000c98: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000c9c: 3dc1e520    	ldr	q0, [x9, #0x790]
100000ca0: 3d81e900    	str	q0, [x8, #0x7a0]
100000ca4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ca8: 3dc1e920    	ldr	q0, [x9, #0x7a0]
100000cac: 3d81ed00    	str	q0, [x8, #0x7b0]
100000cb0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000cb4: 3dc1ed20    	ldr	q0, [x9, #0x7b0]
100000cb8: 3d81f100    	str	q0, [x8, #0x7c0]
100000cbc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000cc0: 3dc1f120    	ldr	q0, [x9, #0x7c0]
100000cc4: 3d81f500    	str	q0, [x8, #0x7d0]
100000cc8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ccc: 3dc1f520    	ldr	q0, [x9, #0x7d0]
100000cd0: 3d81f900    	str	q0, [x8, #0x7e0]
100000cd4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000cd8: 3dc1f920    	ldr	q0, [x9, #0x7e0]
100000cdc: 3d81fd00    	str	q0, [x8, #0x7f0]
100000ce0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ce4: 3dc1fd20    	ldr	q0, [x9, #0x7f0]
100000ce8: 3d820100    	str	q0, [x8, #0x800]
100000cec: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000cf0: 3dc20120    	ldr	q0, [x9, #0x800]
100000cf4: 3d820500    	str	q0, [x8, #0x810]
100000cf8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000cfc: 3dc20520    	ldr	q0, [x9, #0x810]
100000d00: 3d820900    	str	q0, [x8, #0x820]
100000d04: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d08: 3dc20920    	ldr	q0, [x9, #0x820]
100000d0c: 3d820d00    	str	q0, [x8, #0x830]
100000d10: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d14: 3dc20d20    	ldr	q0, [x9, #0x830]
100000d18: 3d821100    	str	q0, [x8, #0x840]
100000d1c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d20: 3dc21120    	ldr	q0, [x9, #0x840]
100000d24: 3d821500    	str	q0, [x8, #0x850]
100000d28: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d2c: 3dc21520    	ldr	q0, [x9, #0x850]
100000d30: 3d821900    	str	q0, [x8, #0x860]
100000d34: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d38: 3dc21920    	ldr	q0, [x9, #0x860]
100000d3c: 3d821d00    	str	q0, [x8, #0x870]
100000d40: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d44: 3dc21d20    	ldr	q0, [x9, #0x870]
100000d48: 3d822100    	str	q0, [x8, #0x880]
100000d4c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d50: 3dc22120    	ldr	q0, [x9, #0x880]
100000d54: 3d822500    	str	q0, [x8, #0x890]
100000d58: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d5c: 3dc22520    	ldr	q0, [x9, #0x890]
100000d60: 3d822900    	str	q0, [x8, #0x8a0]
100000d64: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d68: 3dc22920    	ldr	q0, [x9, #0x8a0]
100000d6c: 3d822d00    	str	q0, [x8, #0x8b0]
100000d70: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d74: 3dc22d20    	ldr	q0, [x9, #0x8b0]
100000d78: 3d823100    	str	q0, [x8, #0x8c0]
100000d7c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d80: 3dc23120    	ldr	q0, [x9, #0x8c0]
100000d84: 3d823500    	str	q0, [x8, #0x8d0]
100000d88: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d8c: 3dc23520    	ldr	q0, [x9, #0x8d0]
100000d90: 3d823900    	str	q0, [x8, #0x8e0]
100000d94: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000d98: 3dc23920    	ldr	q0, [x9, #0x8e0]
100000d9c: 3d823d00    	str	q0, [x8, #0x8f0]
100000da0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000da4: 3dc23d20    	ldr	q0, [x9, #0x8f0]
100000da8: 3d824100    	str	q0, [x8, #0x900]
100000dac: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000db0: 3dc24120    	ldr	q0, [x9, #0x900]
100000db4: 3d824500    	str	q0, [x8, #0x910]
100000db8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000dbc: 3dc24520    	ldr	q0, [x9, #0x910]
100000dc0: 3d824900    	str	q0, [x8, #0x920]
100000dc4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000dc8: 3dc24920    	ldr	q0, [x9, #0x920]
100000dcc: 3d824d00    	str	q0, [x8, #0x930]
100000dd0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000dd4: 3dc24d20    	ldr	q0, [x9, #0x930]
100000dd8: 3d825100    	str	q0, [x8, #0x940]
100000ddc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000de0: 3dc25120    	ldr	q0, [x9, #0x940]
100000de4: 3d825500    	str	q0, [x8, #0x950]
100000de8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000dec: 3dc25520    	ldr	q0, [x9, #0x950]
100000df0: 3d825900    	str	q0, [x8, #0x960]
100000df4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000df8: 3dc25920    	ldr	q0, [x9, #0x960]
100000dfc: 3d825d00    	str	q0, [x8, #0x970]
100000e00: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e04: 3dc25d20    	ldr	q0, [x9, #0x970]
100000e08: 3d826100    	str	q0, [x8, #0x980]
100000e0c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e10: 3dc26120    	ldr	q0, [x9, #0x980]
100000e14: 3d826500    	str	q0, [x8, #0x990]
100000e18: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e1c: 3dc26520    	ldr	q0, [x9, #0x990]
100000e20: 3d826900    	str	q0, [x8, #0x9a0]
100000e24: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e28: 3dc26920    	ldr	q0, [x9, #0x9a0]
100000e2c: 3d826d00    	str	q0, [x8, #0x9b0]
100000e30: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e34: 3dc26d20    	ldr	q0, [x9, #0x9b0]
100000e38: 3d827100    	str	q0, [x8, #0x9c0]
100000e3c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e40: 3dc27120    	ldr	q0, [x9, #0x9c0]
100000e44: 3d827500    	str	q0, [x8, #0x9d0]
100000e48: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e4c: 3dc27520    	ldr	q0, [x9, #0x9d0]
100000e50: 3d827900    	str	q0, [x8, #0x9e0]
100000e54: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e58: 3dc27920    	ldr	q0, [x9, #0x9e0]
100000e5c: 3d827d00    	str	q0, [x8, #0x9f0]
100000e60: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e64: 3dc27d20    	ldr	q0, [x9, #0x9f0]
100000e68: 3d828100    	str	q0, [x8, #0xa00]
100000e6c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e70: 3dc28120    	ldr	q0, [x9, #0xa00]
100000e74: 3d828500    	str	q0, [x8, #0xa10]
100000e78: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e7c: 3dc28520    	ldr	q0, [x9, #0xa10]
100000e80: 3d828900    	str	q0, [x8, #0xa20]
100000e84: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e88: 3dc28920    	ldr	q0, [x9, #0xa20]
100000e8c: 3d828d00    	str	q0, [x8, #0xa30]
100000e90: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000e94: 3dc28d20    	ldr	q0, [x9, #0xa30]
100000e98: 3d829100    	str	q0, [x8, #0xa40]
100000e9c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ea0: 3dc29120    	ldr	q0, [x9, #0xa40]
100000ea4: 3d829500    	str	q0, [x8, #0xa50]
100000ea8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000eac: 3dc29520    	ldr	q0, [x9, #0xa50]
100000eb0: 3d829900    	str	q0, [x8, #0xa60]
100000eb4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000eb8: 3dc29920    	ldr	q0, [x9, #0xa60]
100000ebc: 3d829d00    	str	q0, [x8, #0xa70]
100000ec0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ec4: 3dc29d20    	ldr	q0, [x9, #0xa70]
100000ec8: 3d82a100    	str	q0, [x8, #0xa80]
100000ecc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ed0: 3dc2a120    	ldr	q0, [x9, #0xa80]
100000ed4: 3d82a500    	str	q0, [x8, #0xa90]
100000ed8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000edc: 3dc2a520    	ldr	q0, [x9, #0xa90]
100000ee0: 3d82a900    	str	q0, [x8, #0xaa0]
100000ee4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ee8: 3dc2a920    	ldr	q0, [x9, #0xaa0]
100000eec: 3d82ad00    	str	q0, [x8, #0xab0]
100000ef0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ef4: 3dc2ad20    	ldr	q0, [x9, #0xab0]
100000ef8: 3d82b100    	str	q0, [x8, #0xac0]
100000efc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f00: 3dc2b120    	ldr	q0, [x9, #0xac0]
100000f04: 3d82b500    	str	q0, [x8, #0xad0]
100000f08: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f0c: 3dc2b520    	ldr	q0, [x9, #0xad0]
100000f10: 3d82b900    	str	q0, [x8, #0xae0]
100000f14: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f18: 3dc2b920    	ldr	q0, [x9, #0xae0]
100000f1c: 3d82bd00    	str	q0, [x8, #0xaf0]
100000f20: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f24: 3dc2bd20    	ldr	q0, [x9, #0xaf0]
100000f28: 3d82c100    	str	q0, [x8, #0xb00]
100000f2c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f30: 3dc2c120    	ldr	q0, [x9, #0xb00]
100000f34: 3d82c500    	str	q0, [x8, #0xb10]
100000f38: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f3c: 3dc2c520    	ldr	q0, [x9, #0xb10]
100000f40: 3d82c900    	str	q0, [x8, #0xb20]
100000f44: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f48: 3dc2c920    	ldr	q0, [x9, #0xb20]
100000f4c: 3d82cd00    	str	q0, [x8, #0xb30]
100000f50: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f54: 3dc2cd20    	ldr	q0, [x9, #0xb30]
100000f58: 3d82d100    	str	q0, [x8, #0xb40]
100000f5c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f60: 3dc2d120    	ldr	q0, [x9, #0xb40]
100000f64: 3d82d500    	str	q0, [x8, #0xb50]
100000f68: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f6c: 3dc2d520    	ldr	q0, [x9, #0xb50]
100000f70: 3d82d900    	str	q0, [x8, #0xb60]
100000f74: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f78: 3dc2d920    	ldr	q0, [x9, #0xb60]
100000f7c: 3d82dd00    	str	q0, [x8, #0xb70]
100000f80: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f84: 3dc2dd20    	ldr	q0, [x9, #0xb70]
100000f88: 3d82e100    	str	q0, [x8, #0xb80]
100000f8c: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f90: 3dc2e120    	ldr	q0, [x9, #0xb80]
100000f94: 3d82e500    	str	q0, [x8, #0xb90]
100000f98: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000f9c: 3dc2e520    	ldr	q0, [x9, #0xb90]
100000fa0: 3d82e900    	str	q0, [x8, #0xba0]
100000fa4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000fa8: 3dc2e920    	ldr	q0, [x9, #0xba0]
100000fac: 3d82ed00    	str	q0, [x8, #0xbb0]
100000fb0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000fb4: 3dc2ed20    	ldr	q0, [x9, #0xbb0]
100000fb8: 3d82f100    	str	q0, [x8, #0xbc0]
100000fbc: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000fc0: 3dc2f120    	ldr	q0, [x9, #0xbc0]
100000fc4: 3d82f500    	str	q0, [x8, #0xbd0]
100000fc8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000fcc: 3dc2f520    	ldr	q0, [x9, #0xbd0]
100000fd0: 3d82f900    	str	q0, [x8, #0xbe0]
100000fd4: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000fd8: 3dc2f920    	ldr	q0, [x9, #0xbe0]
100000fdc: 3d82fd00    	str	q0, [x8, #0xbf0]
100000fe0: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000fe4: 3dc2fd20    	ldr	q0, [x9, #0xbf0]
100000fe8: 3d830100    	str	q0, [x8, #0xc00]
100000fec: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ff0: 3dc30120    	ldr	q0, [x9, #0xc00]
100000ff4: 3d830500    	str	q0, [x8, #0xc10]
100000ff8: f0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100000ffc: 3dc30520    	ldr	q0, [x9, #0xc10]
100001000: 3d830900    	str	q0, [x8, #0xc20]
100001004: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001008: 3dc30920    	ldr	q0, [x9, #0xc20]
10000100c: 3d830d00    	str	q0, [x8, #0xc30]
100001010: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001014: 3dc30d20    	ldr	q0, [x9, #0xc30]
100001018: 3d831100    	str	q0, [x8, #0xc40]
10000101c: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001020: 3dc31120    	ldr	q0, [x9, #0xc40]
100001024: 3d831500    	str	q0, [x8, #0xc50]
100001028: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000102c: 3dc31520    	ldr	q0, [x9, #0xc50]
100001030: 3d831900    	str	q0, [x8, #0xc60]
100001034: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001038: 3dc31920    	ldr	q0, [x9, #0xc60]
10000103c: 3d831d00    	str	q0, [x8, #0xc70]
100001040: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001044: 3dc31d20    	ldr	q0, [x9, #0xc70]
100001048: 3d832100    	str	q0, [x8, #0xc80]
10000104c: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001050: 3dc32120    	ldr	q0, [x9, #0xc80]
100001054: 3d832500    	str	q0, [x8, #0xc90]
100001058: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000105c: 3dc32520    	ldr	q0, [x9, #0xc90]
100001060: 3d832900    	str	q0, [x8, #0xca0]
100001064: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001068: 3dc32920    	ldr	q0, [x9, #0xca0]
10000106c: 3d832d00    	str	q0, [x8, #0xcb0]
100001070: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001074: 3dc32d20    	ldr	q0, [x9, #0xcb0]
100001078: 3d833100    	str	q0, [x8, #0xcc0]
10000107c: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001080: 3dc33120    	ldr	q0, [x9, #0xcc0]
100001084: 3d833500    	str	q0, [x8, #0xcd0]
100001088: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000108c: 3dc33520    	ldr	q0, [x9, #0xcd0]
100001090: 3d833900    	str	q0, [x8, #0xce0]
100001094: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001098: 3dc33920    	ldr	q0, [x9, #0xce0]
10000109c: 3d833d00    	str	q0, [x8, #0xcf0]
1000010a0: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000010a4: 3dc33d20    	ldr	q0, [x9, #0xcf0]
1000010a8: 3d834100    	str	q0, [x8, #0xd00]
1000010ac: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000010b0: 3dc34120    	ldr	q0, [x9, #0xd00]
1000010b4: 3d834500    	str	q0, [x8, #0xd10]
1000010b8: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000010bc: 3dc34520    	ldr	q0, [x9, #0xd10]
1000010c0: 3d834900    	str	q0, [x8, #0xd20]
1000010c4: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000010c8: 3dc34920    	ldr	q0, [x9, #0xd20]
1000010cc: 3d834d00    	str	q0, [x8, #0xd30]
1000010d0: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000010d4: 3dc34d20    	ldr	q0, [x9, #0xd30]
1000010d8: 3d835100    	str	q0, [x8, #0xd40]
1000010dc: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000010e0: 3dc35120    	ldr	q0, [x9, #0xd40]
1000010e4: 3d835500    	str	q0, [x8, #0xd50]
1000010e8: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000010ec: 3dc35520    	ldr	q0, [x9, #0xd50]
1000010f0: 3d835900    	str	q0, [x8, #0xd60]
1000010f4: d0000069    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000010f8: 3dc35920    	ldr	q0, [x9, #0xd60]
1000010fc: 3d835d00    	str	q0, [x8, #0xd70]
100001100: 9101c3e0    	add	x0, sp, #0x70
100001104: 94000339    	bl	0x100001de8 <_debug.lockStderrWriter>
100001108: d2800016    	mov	x22, #0x0               ; =0
10000110c: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001110: f940be68    	ldr	x8, [x19, #0x178]
100001114: d0000077    	adrp	x23, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001118: 913ee2f7    	add	x23, x23, #0xfb8
10000111c: 528000d8    	mov	w24, #0x6               ; =6
100001120: f00000d5    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001124: f00000d9    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001128: 91058339    	add	x25, x25, #0x160
10000112c: f00000da    	adrp	x26, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001130: 9105a35a    	add	x26, x26, #0x168
100001134: 8b1602e1    	add	x1, x23, x22
100001138: cb160314    	sub	x20, x24, x22
10000113c: 8b080289    	add	x9, x20, x8
100001140: f940baaa    	ldr	x10, [x21, #0x170]
100001144: eb0a013f    	cmp	x9, x10
100001148: 54000188    	b.hi	0x100001178 <_main+0xab0>
10000114c: f9400349    	ldr	x9, [x26]
100001150: 8b080120    	add	x0, x9, x8
100001154: aa1403e2    	mov	x2, x20
100001158: 94003744    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
10000115c: f9400b48    	ldr	x8, [x26, #0x10]
100001160: 8b140108    	add	x8, x8, x20
100001164: f9000b48    	str	x8, [x26, #0x10]
100001168: 8b160296    	add	x22, x20, x22
10000116c: f1001adf    	cmp	x22, #0x6
100001170: 54fffe23    	b.lo	0x100001134 <_main+0xa6c>
100001174: 14000011    	b	0x1000011b8 <_main+0xaf0>
100001178: f9400328    	ldr	x8, [x25]
10000117c: f9400109    	ldr	x9, [x8]
100001180: a938d3a1    	stp	x1, x20, [x29, #-0x78]
100001184: 9100c3e8    	add	x8, sp, #0x30
100001188: d101e3a1    	sub	x1, x29, #0x78
10000118c: aa1903e0    	mov	x0, x25
100001190: 52800022    	mov	w2, #0x1                ; =1
100001194: 52800023    	mov	w3, #0x1                ; =1
100001198: d63f0120    	blr	x9
10000119c: 794073e8    	ldrh	w8, [sp, #0x38]
1000011a0: 35001b28    	cbnz	w8, 0x100001504 <_main+0xe3c>
1000011a4: f9401bf4    	ldr	x20, [sp, #0x30]
1000011a8: f9400f28    	ldr	x8, [x25, #0x18]
1000011ac: 8b160296    	add	x22, x20, x22
1000011b0: f1001adf    	cmp	x22, #0x6
1000011b4: 54fffc03    	b.lo	0x100001134 <_main+0xa6c>
1000011b8: d2800016    	mov	x22, #0x0               ; =0
1000011bc: b0000097    	adrp	x23, 0x100012000 <___anon_4979+0x1f98>
1000011c0: 912a6ef7    	add	x23, x23, #0xa9b
1000011c4: 528000d8    	mov	w24, #0x6               ; =6
1000011c8: 8b1602e1    	add	x1, x23, x22
1000011cc: cb160314    	sub	x20, x24, x22
1000011d0: 8b080289    	add	x9, x20, x8
1000011d4: f940baaa    	ldr	x10, [x21, #0x170]
1000011d8: eb0a013f    	cmp	x9, x10
1000011dc: 54000188    	b.hi	0x10000120c <_main+0xb44>
1000011e0: f9400349    	ldr	x9, [x26]
1000011e4: 8b080120    	add	x0, x9, x8
1000011e8: aa1403e2    	mov	x2, x20
1000011ec: 9400371f    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
1000011f0: f9400b48    	ldr	x8, [x26, #0x10]
1000011f4: 8b140108    	add	x8, x8, x20
1000011f8: f9000b48    	str	x8, [x26, #0x10]
1000011fc: 8b160296    	add	x22, x20, x22
100001200: f1001adf    	cmp	x22, #0x6
100001204: 54fffe23    	b.lo	0x1000011c8 <_main+0xb00>
100001208: 14000011    	b	0x10000124c <_main+0xb84>
10000120c: f9400328    	ldr	x8, [x25]
100001210: f9400109    	ldr	x9, [x8]
100001214: a938d3a1    	stp	x1, x20, [x29, #-0x78]
100001218: 9100c3e8    	add	x8, sp, #0x30
10000121c: d101e3a1    	sub	x1, x29, #0x78
100001220: aa1903e0    	mov	x0, x25
100001224: 52800022    	mov	w2, #0x1                ; =1
100001228: 52800023    	mov	w3, #0x1                ; =1
10000122c: d63f0120    	blr	x9
100001230: 794073e8    	ldrh	w8, [sp, #0x38]
100001234: 35001688    	cbnz	w8, 0x100001504 <_main+0xe3c>
100001238: f9401bf4    	ldr	x20, [sp, #0x30]
10000123c: f9400f28    	ldr	x8, [x25, #0x18]
100001240: 8b160296    	add	x22, x20, x22
100001244: f1001adf    	cmp	x22, #0x6
100001248: 54fffc03    	b.lo	0x1000011c8 <_main+0xb00>
10000124c: d2800016    	mov	x22, #0x0               ; =0
100001250: d0000077    	adrp	x23, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001254: 913efaf7    	add	x23, x23, #0xfbe
100001258: 52800378    	mov	w24, #0x1b              ; =27
10000125c: 8b1602e1    	add	x1, x23, x22
100001260: cb160314    	sub	x20, x24, x22
100001264: 8b080289    	add	x9, x20, x8
100001268: f940baaa    	ldr	x10, [x21, #0x170]
10000126c: eb0a013f    	cmp	x9, x10
100001270: 54000188    	b.hi	0x1000012a0 <_main+0xbd8>
100001274: f9400349    	ldr	x9, [x26]
100001278: 8b080120    	add	x0, x9, x8
10000127c: aa1403e2    	mov	x2, x20
100001280: 940036fa    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
100001284: f9400b48    	ldr	x8, [x26, #0x10]
100001288: 8b140108    	add	x8, x8, x20
10000128c: f9000b48    	str	x8, [x26, #0x10]
100001290: 8b160296    	add	x22, x20, x22
100001294: f1006edf    	cmp	x22, #0x1b
100001298: 54fffe23    	b.lo	0x10000125c <_main+0xb94>
10000129c: 14000011    	b	0x1000012e0 <_main+0xc18>
1000012a0: f9400328    	ldr	x8, [x25]
1000012a4: f9400109    	ldr	x9, [x8]
1000012a8: a938d3a1    	stp	x1, x20, [x29, #-0x78]
1000012ac: 9100c3e8    	add	x8, sp, #0x30
1000012b0: d101e3a1    	sub	x1, x29, #0x78
1000012b4: aa1903e0    	mov	x0, x25
1000012b8: 52800022    	mov	w2, #0x1                ; =1
1000012bc: 52800023    	mov	w3, #0x1                ; =1
1000012c0: d63f0120    	blr	x9
1000012c4: 794073e8    	ldrh	w8, [sp, #0x38]
1000012c8: 350011e8    	cbnz	w8, 0x100001504 <_main+0xe3c>
1000012cc: f9401bf4    	ldr	x20, [sp, #0x30]
1000012d0: f9400f28    	ldr	x8, [x25, #0x18]
1000012d4: 8b160296    	add	x22, x20, x22
1000012d8: f1006edf    	cmp	x22, #0x1b
1000012dc: 54fffc03    	b.lo	0x10000125c <_main+0xb94>
1000012e0: d2800016    	mov	x22, #0x0               ; =0
1000012e4: b0000097    	adrp	x23, 0x100012000 <___anon_4979+0x1f98>
1000012e8: 912a8af7    	add	x23, x23, #0xaa2
1000012ec: 8b1602e1    	add	x1, x23, x22
1000012f0: d2400ad4    	eor	x20, x22, #0x7
1000012f4: f940baa9    	ldr	x9, [x21, #0x170]
1000012f8: 8b08028a    	add	x10, x20, x8
1000012fc: eb09015f    	cmp	x10, x9
100001300: 54000188    	b.hi	0x100001330 <_main+0xc68>
100001304: f9400349    	ldr	x9, [x26]
100001308: 8b080120    	add	x0, x9, x8
10000130c: aa1403e2    	mov	x2, x20
100001310: 940036d6    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
100001314: f9400b48    	ldr	x8, [x26, #0x10]
100001318: 8b140108    	add	x8, x8, x20
10000131c: f9000b48    	str	x8, [x26, #0x10]
100001320: 8b160296    	add	x22, x20, x22
100001324: f1001edf    	cmp	x22, #0x7
100001328: 54fffe23    	b.lo	0x1000012ec <_main+0xc24>
10000132c: 14000011    	b	0x100001370 <_main+0xca8>
100001330: f9400328    	ldr	x8, [x25]
100001334: f9400109    	ldr	x9, [x8]
100001338: a938d3a1    	stp	x1, x20, [x29, #-0x78]
10000133c: 9100c3e8    	add	x8, sp, #0x30
100001340: d101e3a1    	sub	x1, x29, #0x78
100001344: aa1903e0    	mov	x0, x25
100001348: 52800022    	mov	w2, #0x1                ; =1
10000134c: 52800023    	mov	w3, #0x1                ; =1
100001350: d63f0120    	blr	x9
100001354: 794073e8    	ldrh	w8, [sp, #0x38]
100001358: 35000d68    	cbnz	w8, 0x100001504 <_main+0xe3c>
10000135c: f9401bf4    	ldr	x20, [sp, #0x30]
100001360: f9400f28    	ldr	x8, [x25, #0x18]
100001364: 8b160296    	add	x22, x20, x22
100001368: f1001edf    	cmp	x22, #0x7
10000136c: 54fffc03    	b.lo	0x1000012ec <_main+0xc24>
100001370: d2800016    	mov	x22, #0x0               ; =0
100001374: d0000077    	adrp	x23, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001378: 913f66f7    	add	x23, x23, #0xfd9
10000137c: 52800098    	mov	w24, #0x4               ; =4
100001380: 8b1602e1    	add	x1, x23, x22
100001384: cb160314    	sub	x20, x24, x22
100001388: 8b080289    	add	x9, x20, x8
10000138c: f940baaa    	ldr	x10, [x21, #0x170]
100001390: eb0a013f    	cmp	x9, x10
100001394: 54000188    	b.hi	0x1000013c4 <_main+0xcfc>
100001398: f9400349    	ldr	x9, [x26]
10000139c: 8b080120    	add	x0, x9, x8
1000013a0: aa1403e2    	mov	x2, x20
1000013a4: 940036b1    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
1000013a8: f9400b48    	ldr	x8, [x26, #0x10]
1000013ac: 8b140108    	add	x8, x8, x20
1000013b0: f9000b48    	str	x8, [x26, #0x10]
1000013b4: 8b160296    	add	x22, x20, x22
1000013b8: f10012df    	cmp	x22, #0x4
1000013bc: 54fffe23    	b.lo	0x100001380 <_main+0xcb8>
1000013c0: 14000011    	b	0x100001404 <_main+0xd3c>
1000013c4: f9400328    	ldr	x8, [x25]
1000013c8: f9400109    	ldr	x9, [x8]
1000013cc: a938d3a1    	stp	x1, x20, [x29, #-0x78]
1000013d0: 9100c3e8    	add	x8, sp, #0x30
1000013d4: d101e3a1    	sub	x1, x29, #0x78
1000013d8: aa1903e0    	mov	x0, x25
1000013dc: 52800022    	mov	w2, #0x1                ; =1
1000013e0: 52800023    	mov	w3, #0x1                ; =1
1000013e4: d63f0120    	blr	x9
1000013e8: 794073e8    	ldrh	w8, [sp, #0x38]
1000013ec: 350008c8    	cbnz	w8, 0x100001504 <_main+0xe3c>
1000013f0: f9401bf4    	ldr	x20, [sp, #0x30]
1000013f4: f9400f28    	ldr	x8, [x25, #0x18]
1000013f8: 8b160296    	add	x22, x20, x22
1000013fc: f10012df    	cmp	x22, #0x4
100001400: 54fffc03    	b.lo	0x100001380 <_main+0xcb8>
100001404: d2800016    	mov	x22, #0x0               ; =0
100001408: b0000097    	adrp	x23, 0x100012000 <___anon_4979+0x1f98>
10000140c: 912aaaf7    	add	x23, x23, #0xaaa
100001410: 528000b8    	mov	w24, #0x5               ; =5
100001414: 8b1602e1    	add	x1, x23, x22
100001418: cb160314    	sub	x20, x24, x22
10000141c: 8b080289    	add	x9, x20, x8
100001420: f940baaa    	ldr	x10, [x21, #0x170]
100001424: eb0a013f    	cmp	x9, x10
100001428: 54000188    	b.hi	0x100001458 <_main+0xd90>
10000142c: f9400349    	ldr	x9, [x26]
100001430: 8b080120    	add	x0, x9, x8
100001434: aa1403e2    	mov	x2, x20
100001438: 9400368c    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
10000143c: f9400b48    	ldr	x8, [x26, #0x10]
100001440: 8b140108    	add	x8, x8, x20
100001444: f9000b48    	str	x8, [x26, #0x10]
100001448: 8b160296    	add	x22, x20, x22
10000144c: f10016df    	cmp	x22, #0x5
100001450: 54fffe23    	b.lo	0x100001414 <_main+0xd4c>
100001454: 14000011    	b	0x100001498 <_main+0xdd0>
100001458: f9400328    	ldr	x8, [x25]
10000145c: f9400109    	ldr	x9, [x8]
100001460: a938d3a1    	stp	x1, x20, [x29, #-0x78]
100001464: 9100c3e8    	add	x8, sp, #0x30
100001468: d101e3a1    	sub	x1, x29, #0x78
10000146c: aa1903e0    	mov	x0, x25
100001470: 52800022    	mov	w2, #0x1                ; =1
100001474: 52800023    	mov	w3, #0x1                ; =1
100001478: d63f0120    	blr	x9
10000147c: 794073e8    	ldrh	w8, [sp, #0x38]
100001480: 35000428    	cbnz	w8, 0x100001504 <_main+0xe3c>
100001484: f9401bf4    	ldr	x20, [sp, #0x30]
100001488: f9400f28    	ldr	x8, [x25, #0x18]
10000148c: 8b160296    	add	x22, x20, x22
100001490: f10016df    	cmp	x22, #0x5
100001494: 54fffc03    	b.lo	0x100001414 <_main+0xd4c>
100001498: d0000074    	adrp	x20, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000149c: 913f7694    	add	x20, x20, #0xfdd
1000014a0: 52800036    	mov	w22, #0x1               ; =1
1000014a4: f940baa9    	ldr	x9, [x21, #0x170]
1000014a8: eb09011f    	cmp	x8, x9
1000014ac: 54000203    	b.lo	0x1000014ec <_main+0xe24>
1000014b0: f9400328    	ldr	x8, [x25]
1000014b4: f9400109    	ldr	x9, [x8]
1000014b8: a938dbb4    	stp	x20, x22, [x29, #-0x78]
1000014bc: 9100c3e8    	add	x8, sp, #0x30
1000014c0: d101e3a1    	sub	x1, x29, #0x78
1000014c4: aa1903e0    	mov	x0, x25
1000014c8: 52800022    	mov	w2, #0x1                ; =1
1000014cc: 52800023    	mov	w3, #0x1                ; =1
1000014d0: d63f0120    	blr	x9
1000014d4: 794073e8    	ldrh	w8, [sp, #0x38]
1000014d8: 35000168    	cbnz	w8, 0x100001504 <_main+0xe3c>
1000014dc: f9401be9    	ldr	x9, [sp, #0x30]
1000014e0: f940be68    	ldr	x8, [x19, #0x178]
1000014e4: b4fffe09    	cbz	x9, 0x1000014a4 <_main+0xddc>
1000014e8: 14000007    	b	0x100001504 <_main+0xe3c>
1000014ec: f9400349    	ldr	x9, [x26]
1000014f0: 5280014a    	mov	w10, #0xa               ; =10
1000014f4: 3828692a    	strb	w10, [x9, x8]
1000014f8: f9400b48    	ldr	x8, [x26, #0x10]
1000014fc: 91000508    	add	x8, x8, #0x1
100001500: f9000b48    	str	x8, [x26, #0x10]
100001504: f00000d4    	adrp	x20, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001508: 91052294    	add	x20, x20, #0x148
10000150c: aa1403e0    	mov	x0, x20
100001510: f8418c08    	ldr	x8, [x0, #0x18]!
100001514: f9400908    	ldr	x8, [x8, #0x10]
100001518: d63f0100    	blr	x8
10000151c: b201f3e8    	mov	x8, #-0x5555555555555556 ; =-6148914691236517206
100001520: a902fe9f    	stp	xzr, xzr, [x20, #0x28]
100001524: f9001288    	str	x8, [x20, #0x20]
100001528: f9400288    	ldr	x8, [x20]
10000152c: f1000508    	subs	x8, x8, #0x1
100001530: f9000288    	str	x8, [x20]
100001534: 540000e1    	b.ne	0x100001550 <_main+0xe88>
100001538: 92800008    	mov	x8, #-0x1               ; =-1
10000153c: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001540: 91050129    	add	x9, x9, #0x140
100001544: f9000128    	str	x8, [x9]
100001548: 91004120    	add	x0, x9, #0x10
10000154c: 94003668    	bl	0x10000eeec <dyld_stub_binder+0x10000eeec>
100001550: 9101c3e0    	add	x0, sp, #0x70
100001554: 94000225    	bl	0x100001de8 <_debug.lockStderrWriter>
100001558: d2800016    	mov	x22, #0x0               ; =0
10000155c: f940be68    	ldr	x8, [x19, #0x178]
100001560: d0000073    	adrp	x19, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001564: 913f7a73    	add	x19, x19, #0xfde
100001568: 528006b7    	mov	w23, #0x35              ; =53
10000156c: 8b160261    	add	x1, x19, x22
100001570: cb1602f4    	sub	x20, x23, x22
100001574: 8b080289    	add	x9, x20, x8
100001578: f940baaa    	ldr	x10, [x21, #0x170]
10000157c: eb0a013f    	cmp	x9, x10
100001580: 54000188    	b.hi	0x1000015b0 <_main+0xee8>
100001584: f9400349    	ldr	x9, [x26]
100001588: 8b080120    	add	x0, x9, x8
10000158c: aa1403e2    	mov	x2, x20
100001590: 94003636    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
100001594: f9400b48    	ldr	x8, [x26, #0x10]
100001598: 8b140108    	add	x8, x8, x20
10000159c: f9000b48    	str	x8, [x26, #0x10]
1000015a0: 8b160296    	add	x22, x20, x22
1000015a4: f100d6df    	cmp	x22, #0x35
1000015a8: 54fffe23    	b.lo	0x10000156c <_main+0xea4>
1000015ac: 14000011    	b	0x1000015f0 <_main+0xf28>
1000015b0: f9400328    	ldr	x8, [x25]
1000015b4: f9400109    	ldr	x9, [x8]
1000015b8: a938d3a1    	stp	x1, x20, [x29, #-0x78]
1000015bc: 9100c3e8    	add	x8, sp, #0x30
1000015c0: d101e3a1    	sub	x1, x29, #0x78
1000015c4: aa1903e0    	mov	x0, x25
1000015c8: 52800022    	mov	w2, #0x1                ; =1
1000015cc: 52800023    	mov	w3, #0x1                ; =1
1000015d0: d63f0120    	blr	x9
1000015d4: 794073e8    	ldrh	w8, [sp, #0x38]
1000015d8: 350000c8    	cbnz	w8, 0x1000015f0 <_main+0xf28>
1000015dc: f9401bf4    	ldr	x20, [sp, #0x30]
1000015e0: f9400f28    	ldr	x8, [x25, #0x18]
1000015e4: 8b160296    	add	x22, x20, x22
1000015e8: f100d6df    	cmp	x22, #0x35
1000015ec: 54fffc03    	b.lo	0x10000156c <_main+0xea4>
1000015f0: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000015f4: 91052273    	add	x19, x19, #0x148
1000015f8: aa1303e0    	mov	x0, x19
1000015fc: f8418c08    	ldr	x8, [x0, #0x18]!
100001600: f9400908    	ldr	x8, [x8, #0x10]
100001604: d63f0100    	blr	x8
100001608: b201f3e8    	mov	x8, #-0x5555555555555556 ; =-6148914691236517206
10000160c: a902fe7f    	stp	xzr, xzr, [x19, #0x28]
100001610: f9001268    	str	x8, [x19, #0x20]
100001614: f9400268    	ldr	x8, [x19]
100001618: f1000508    	subs	x8, x8, #0x1
10000161c: f9000268    	str	x8, [x19]
100001620: 540000e1    	b.ne	0x10000163c <_main+0xf74>
100001624: 92800008    	mov	x8, #-0x1               ; =-1
100001628: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000162c: 91050129    	add	x9, x9, #0x140
100001630: f9000128    	str	x8, [x9]
100001634: 91004120    	add	x0, x9, #0x10
100001638: 9400362d    	bl	0x10000eeec <dyld_stub_binder+0x10000eeec>
10000163c: d2800014    	mov	x20, #0x0               ; =0
100001640: f0000068    	adrp	x8, 0x100010000 <___anon_4031+0x22>
100001644: 39424119    	ldrb	w25, [x8, #0x90]
100001648: 9101c3fc    	add	x28, sp, #0x70
10000164c: d29eb87b    	mov	x27, #0xf5c3            ; =62915
100001650: f2ab851b    	movk	x27, #0x5c28, lsl #16
100001654: f2d851fb    	movk	x27, #0xc28f, lsl #32
100001658: f2e51ebb    	movk	x27, #0x28f5, lsl #48
10000165c: 52800c96    	mov	w22, #0x64              ; =100
100001660: b000009a    	adrp	x26, 0x100012000 <___anon_4979+0x1f98>
100001664: 912ae75a    	add	x26, x26, #0xab9
100001668: b90007f9    	str	w25, [sp, #0x4]
10000166c: 14000004    	b	0x10000167c <_main+0xfb4>
100001670: 91000694    	add	x20, x20, #0x1
100001674: f100129f    	cmp	x20, #0x4
100001678: 54002a60    	b.eq	0x100001bc4 <_main+0x14fc>
10000167c: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001680: 91032108    	add	x8, x8, #0xc8
100001684: 8b141108    	add	x8, x8, x20, lsl #4
100001688: a9402115    	ldp	x21, x8, [x8]
10000168c: f9000fe8    	str	x8, [sp, #0x18]
100001690: d0000068    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001694: 913e6108    	add	x8, x8, #0xf98
100001698: f8747918    	ldr	x24, [x8, x20, lsl #3]
10000169c: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000016a0: 91022108    	add	x8, x8, #0x88
1000016a4: f8747917    	ldr	x23, [x8, x20, lsl #3]
1000016a8: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000016ac: 9102a108    	add	x8, x8, #0xa8
1000016b0: f8747919    	ldr	x25, [x8, x20, lsl #3]
1000016b4: 2f00e408    	movi	d8, #0000000000000000
1000016b8: 5280fa13    	mov	w19, #0x7d0             ; =2000
1000016bc: d63f02e0    	blr	x23
1000016c0: d63f0320    	blr	x25
1000016c4: 1e602908    	fadd	d8, d8, d0
1000016c8: f1000673    	subs	x19, x19, #0x1
1000016cc: 54ffff81    	b.ne	0x1000016bc <_main+0xff4>
1000016d0: fd0017e8    	str	d8, [sp, #0x28]
1000016d4: 9100a3e8    	add	x8, sp, #0x28
1000016d8: 9101c3e1    	add	x1, sp, #0x70
1000016dc: 52800100    	mov	w0, #0x8                ; =8
1000016e0: 940035d9    	bl	0x10000ee44 <dyld_stub_binder+0x10000ee44>
1000016e4: 3100041f    	cmn	w0, #0x1
1000016e8: 54000081    	b.ne	0x1000016f8 <_main+0x1030>
1000016ec: 940035e8    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
1000016f0: b9400008    	ldr	w8, [x0]
1000016f4: 350027c8    	cbnz	w8, 0x100001bec <_main+0x1524>
1000016f8: a900d3f5    	stp	x21, x20, [sp, #0x8]
1000016fc: a94757f3    	ldp	x19, x21, [sp, #0x70]
100001700: 2f00e408    	movi	d8, #0000000000000000
100001704: aa1803f4    	mov	x20, x24
100001708: d63f02e0    	blr	x23
10000170c: d63f0320    	blr	x25
100001710: 1e602908    	fadd	d8, d8, d0
100001714: f1000694    	subs	x20, x20, #0x1
100001718: 54ffff81    	b.ne	0x100001708 <_main+0x1040>
10000171c: 9101c3e1    	add	x1, sp, #0x70
100001720: 52800100    	mov	w0, #0x8                ; =8
100001724: 940035c8    	bl	0x10000ee44 <dyld_stub_binder+0x10000ee44>
100001728: 3100041f    	cmn	w0, #0x1
10000172c: 54000041    	b.ne	0x100001734 <_main+0x106c>
100001730: 940035d7    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
100001734: a94723e9    	ldp	x9, x8, [sp, #0x70]
100001738: eb130129    	subs	x9, x9, x19
10000173c: 1a9fa7ea    	cset	w10, lt
100001740: 5280004b    	mov	w11, #0x2               ; =2
100001744: 1a8a016a    	csel	w10, w11, w10, eq
100001748: 3901c3ea    	strb	w10, [sp, #0x70]
10000174c: 7100095f    	cmp	w10, #0x2
100001750: f9400bf4    	ldr	x20, [sp, #0x10]
100001754: b94007f9    	ldr	w25, [sp, #0x4]
100001758: 540000a1    	b.ne	0x10000176c <_main+0x10a4>
10000175c: eb15011f    	cmp	x8, x21
100001760: 1a9fa7ea    	cset	w10, lt
100001764: 1a8a016a    	csel	w10, w11, w10, eq
100001768: 3901c3ea    	strb	w10, [sp, #0x70]
10000176c: 7100015f    	cmp	w10, #0x0
100001770: 9a950113    	csel	x19, x8, x21, eq
100001774: 9a9f0137    	csel	x23, x9, xzr, eq
100001778: fd0013e8    	str	d8, [sp, #0x20]
10000177c: 910083e8    	add	x8, sp, #0x20
100001780: 9100c3e0    	add	x0, sp, #0x30
100001784: 94000199    	bl	0x100001de8 <_debug.lockStderrWriter>
100001788: f94007e0    	ldr	x0, [sp, #0x8]
10000178c: f9400fe1    	ldr	x1, [sp, #0x18]
100001790: aa0103e2    	mov	x2, x1
100001794: aa1903e3    	mov	x3, x25
100001798: 52800404    	mov	w4, #0x20               ; =32
10000179c: 94002fe0    	bl	0x10000d71c <_Io.Writer.alignBuffer>
1000017a0: 72003c1f    	tst	w0, #0xffff
1000017a4: 54001e81    	b.ne	0x100001b74 <_main+0x14ac>
1000017a8: cb150268    	sub	x8, x19, x21
1000017ac: 52994009    	mov	w9, #0xca00             ; =51712
1000017b0: 72a77349    	movk	w9, #0x3b9a, lsl #16
1000017b4: 9b0922f7    	madd	x23, x23, x9, x8
1000017b8: 9e6302e0    	ucvtf	d0, x23
1000017bc: 9e630301    	ucvtf	d1, x24
1000017c0: 1e611809    	fdiv	d9, d0, d1
1000017c4: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000017c8: 9105c129    	add	x9, x9, #0x170
1000017cc: a9402129    	ldp	x9, x8, [x9]
1000017d0: eb09011f    	cmp	x8, x9
1000017d4: 54000263    	b.lo	0x100001820 <_main+0x1158>
1000017d8: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000017dc: 91058000    	add	x0, x0, #0x160
1000017e0: f9400008    	ldr	x8, [x0]
1000017e4: f9400109    	ldr	x9, [x8]
1000017e8: f0000068    	adrp	x8, 0x100010000 <___anon_4031+0x22>
1000017ec: 91004d0a    	add	x10, x8, #0x13
1000017f0: 52800028    	mov	w8, #0x1                ; =1
1000017f4: a938a3aa    	stp	x10, x8, [x29, #-0x78]
1000017f8: 9101c3e8    	add	x8, sp, #0x70
1000017fc: d101e3a1    	sub	x1, x29, #0x78
100001800: 52800022    	mov	w2, #0x1                ; =1
100001804: 52800023    	mov	w3, #0x1                ; =1
100001808: d63f0120    	blr	x9
10000180c: 7940f3e8    	ldrh	w8, [sp, #0x78]
100001810: 35001b28    	cbnz	w8, 0x100001b74 <_main+0x14ac>
100001814: f9403be8    	ldr	x8, [sp, #0x70]
100001818: b4fffd68    	cbz	x8, 0x1000017c4 <_main+0x10fc>
10000181c: 14000009    	b	0x100001840 <_main+0x1178>
100001820: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001824: 9105a14a    	add	x10, x10, #0x168
100001828: f9400149    	ldr	x9, [x10]
10000182c: 5280058b    	mov	w11, #0x2c              ; =44
100001830: 3828692b    	strb	w11, [x9, x8]
100001834: f9400948    	ldr	x8, [x10, #0x10]
100001838: 91000508    	add	x8, x8, #0x1
10000183c: f9000948    	str	x8, [x10, #0x10]
100001840: d2800008    	mov	x8, #0x0                ; =0
100001844: aa1803e9    	mov	x9, x24
100001848: 8b08038a    	add	x10, x28, x8
10000184c: d342ff0b    	lsr	x11, x24, #2
100001850: 9bdb7d6b    	umulh	x11, x11, x27
100001854: d342fd78    	lsr	x24, x11, #2
100001858: 9b16a70b    	msub	x11, x24, x22, x9
10000185c: 786b7b4b    	ldrh	w11, [x26, x11, lsl #1]
100001860: 7803f14b    	sturh	w11, [x10, #0x3f]
100001864: d1000908    	sub	x8, x8, #0x2
100001868: d344fd2a    	lsr	x10, x9, #4
10000186c: f109c15f    	cmp	x10, #0x270
100001870: 54fffea8    	b.hi	0x100001844 <_main+0x117c>
100001874: f10f9d3f    	cmp	x9, #0x3e7
100001878: 540000c8    	b.hi	0x100001890 <_main+0x11c8>
10000187c: 91010109    	add	x9, x8, #0x40
100001880: 8b080388    	add	x8, x28, x8
100001884: 321c070a    	orr	w10, w24, #0x30
100001888: 3901010a    	strb	w10, [x8, #0x40]
10000188c: 14000005    	b	0x1000018a0 <_main+0x11d8>
100001890: 9100fd09    	add	x9, x8, #0x3f
100001894: 8b080388    	add	x8, x28, x8
100001898: 78787b4a    	ldrh	w10, [x26, x24, lsl #1]
10000189c: 7803f10a    	sturh	w10, [x8, #0x3f]
1000018a0: 52800828    	mov	w8, #0x41               ; =65
1000018a4: cb090101    	sub	x1, x8, x9
1000018a8: 8b090380    	add	x0, x28, x9
1000018ac: aa0103e2    	mov	x2, x1
1000018b0: aa1903e3    	mov	x3, x25
1000018b4: 52800404    	mov	w4, #0x20               ; =32
1000018b8: 94002f99    	bl	0x10000d71c <_Io.Writer.alignBuffer>
1000018bc: 72003c1f    	tst	w0, #0xffff
1000018c0: 540015a1    	b.ne	0x100001b74 <_main+0x14ac>
1000018c4: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000018c8: 9105c129    	add	x9, x9, #0x170
1000018cc: a9402129    	ldp	x9, x8, [x9]
1000018d0: eb09011f    	cmp	x8, x9
1000018d4: 54000263    	b.lo	0x100001920 <_main+0x1258>
1000018d8: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000018dc: 91058000    	add	x0, x0, #0x160
1000018e0: f9400008    	ldr	x8, [x0]
1000018e4: f9400109    	ldr	x9, [x8]
1000018e8: f0000068    	adrp	x8, 0x100010000 <___anon_4031+0x22>
1000018ec: 91004d0a    	add	x10, x8, #0x13
1000018f0: 52800028    	mov	w8, #0x1                ; =1
1000018f4: a938a3aa    	stp	x10, x8, [x29, #-0x78]
1000018f8: 9101c3e8    	add	x8, sp, #0x70
1000018fc: d101e3a1    	sub	x1, x29, #0x78
100001900: 52800022    	mov	w2, #0x1                ; =1
100001904: 52800023    	mov	w3, #0x1                ; =1
100001908: d63f0120    	blr	x9
10000190c: 7940f3e8    	ldrh	w8, [sp, #0x78]
100001910: 35001328    	cbnz	w8, 0x100001b74 <_main+0x14ac>
100001914: f9403be8    	ldr	x8, [sp, #0x70]
100001918: b4fffd68    	cbz	x8, 0x1000018c4 <_main+0x11fc>
10000191c: 14000009    	b	0x100001940 <_main+0x1278>
100001920: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001924: 9105a14a    	add	x10, x10, #0x168
100001928: f9400149    	ldr	x9, [x10]
10000192c: 5280058b    	mov	w11, #0x2c              ; =44
100001930: 3828692b    	strb	w11, [x9, x8]
100001934: f9400948    	ldr	x8, [x10, #0x10]
100001938: 91000508    	add	x8, x8, #0x1
10000193c: f9000948    	str	x8, [x10, #0x10]
100001940: f10192ff    	cmp	x23, #0x64
100001944: 54000283    	b.lo	0x100001994 <_main+0x12cc>
100001948: 528007e8    	mov	w8, #0x3f               ; =63
10000194c: aa1703e9    	mov	x9, x23
100001950: d342feea    	lsr	x10, x23, #2
100001954: 9bdb7d4a    	umulh	x10, x10, x27
100001958: d342fd57    	lsr	x23, x10, #2
10000195c: 9b16a6ea    	msub	x10, x23, x22, x9
100001960: 786a7b4a    	ldrh	w10, [x26, x10, lsl #1]
100001964: 78286b8a    	strh	w10, [x28, x8]
100001968: d1000908    	sub	x8, x8, #0x2
10000196c: d344fd29    	lsr	x9, x9, #4
100001970: f109c13f    	cmp	x9, #0x270
100001974: 54fffec8    	b.hi	0x10000194c <_main+0x1284>
100001978: 91000908    	add	x8, x8, #0x2
10000197c: f10026ff    	cmp	x23, #0x9
100001980: 54000109    	b.ls	0x1000019a0 <_main+0x12d8>
100001984: d1000908    	sub	x8, x8, #0x2
100001988: 78777b49    	ldrh	w9, [x26, x23, lsl #1]
10000198c: 78286b89    	strh	w9, [x28, x8]
100001990: 14000007    	b	0x1000019ac <_main+0x12e4>
100001994: 52800828    	mov	w8, #0x41               ; =65
100001998: f10026ff    	cmp	x23, #0x9
10000199c: 54ffff48    	b.hi	0x100001984 <_main+0x12bc>
1000019a0: d1000508    	sub	x8, x8, #0x1
1000019a4: 321c06e9    	orr	w9, w23, #0x30
1000019a8: 38286b89    	strb	w9, [x28, x8]
1000019ac: 52800829    	mov	w9, #0x41               ; =65
1000019b0: cb080121    	sub	x1, x9, x8
1000019b4: 8b080380    	add	x0, x28, x8
1000019b8: aa0103e2    	mov	x2, x1
1000019bc: aa1903e3    	mov	x3, x25
1000019c0: 52800404    	mov	w4, #0x20               ; =32
1000019c4: 94002f56    	bl	0x10000d71c <_Io.Writer.alignBuffer>
1000019c8: 72003c1f    	tst	w0, #0xffff
1000019cc: 54000d41    	b.ne	0x100001b74 <_main+0x14ac>
1000019d0: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000019d4: 9105c129    	add	x9, x9, #0x170
1000019d8: a9402129    	ldp	x9, x8, [x9]
1000019dc: eb09011f    	cmp	x8, x9
1000019e0: 54000263    	b.lo	0x100001a2c <_main+0x1364>
1000019e4: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000019e8: 91058000    	add	x0, x0, #0x160
1000019ec: f9400008    	ldr	x8, [x0]
1000019f0: f9400109    	ldr	x9, [x8]
1000019f4: f0000068    	adrp	x8, 0x100010000 <___anon_4031+0x22>
1000019f8: 91004d0a    	add	x10, x8, #0x13
1000019fc: 52800028    	mov	w8, #0x1                ; =1
100001a00: a938a3aa    	stp	x10, x8, [x29, #-0x78]
100001a04: 9101c3e8    	add	x8, sp, #0x70
100001a08: d101e3a1    	sub	x1, x29, #0x78
100001a0c: 52800022    	mov	w2, #0x1                ; =1
100001a10: 52800023    	mov	w3, #0x1                ; =1
100001a14: d63f0120    	blr	x9
100001a18: 7940f3e8    	ldrh	w8, [sp, #0x78]
100001a1c: 35000ac8    	cbnz	w8, 0x100001b74 <_main+0x14ac>
100001a20: f9403be8    	ldr	x8, [sp, #0x70]
100001a24: b4fffd68    	cbz	x8, 0x1000019d0 <_main+0x1308>
100001a28: 14000009    	b	0x100001a4c <_main+0x1384>
100001a2c: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001a30: 9105a14a    	add	x10, x10, #0x168
100001a34: f9400149    	ldr	x9, [x10]
100001a38: 5280058b    	mov	w11, #0x2c              ; =44
100001a3c: 3828692b    	strb	w11, [x9, x8]
100001a40: f9400948    	ldr	x8, [x10, #0x10]
100001a44: 91000508    	add	x8, x8, #0x1
100001a48: f9000948    	str	x8, [x10, #0x10]
100001a4c: f0000060    	adrp	x0, 0x100010000 <___anon_4031+0x22>
100001a50: 91006000    	add	x0, x0, #0x18
100001a54: 1e604120    	fmov	d0, d9
100001a58: 94002973    	bl	0x10000c024 <_Io.Writer.printValue__anon_4310>
100001a5c: 72003c1f    	tst	w0, #0xffff
100001a60: 540008a1    	b.ne	0x100001b74 <_main+0x14ac>
100001a64: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001a68: 9105c129    	add	x9, x9, #0x170
100001a6c: a9402129    	ldp	x9, x8, [x9]
100001a70: eb09011f    	cmp	x8, x9
100001a74: 54000263    	b.lo	0x100001ac0 <_main+0x13f8>
100001a78: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001a7c: 91058000    	add	x0, x0, #0x160
100001a80: f9400008    	ldr	x8, [x0]
100001a84: f9400109    	ldr	x9, [x8]
100001a88: f0000068    	adrp	x8, 0x100010000 <___anon_4031+0x22>
100001a8c: 91004d0a    	add	x10, x8, #0x13
100001a90: 52800028    	mov	w8, #0x1                ; =1
100001a94: a938a3aa    	stp	x10, x8, [x29, #-0x78]
100001a98: 9101c3e8    	add	x8, sp, #0x70
100001a9c: d101e3a1    	sub	x1, x29, #0x78
100001aa0: 52800022    	mov	w2, #0x1                ; =1
100001aa4: 52800023    	mov	w3, #0x1                ; =1
100001aa8: d63f0120    	blr	x9
100001aac: 7940f3e8    	ldrh	w8, [sp, #0x78]
100001ab0: 35000628    	cbnz	w8, 0x100001b74 <_main+0x14ac>
100001ab4: f9403be8    	ldr	x8, [sp, #0x70]
100001ab8: b4fffd68    	cbz	x8, 0x100001a64 <_main+0x139c>
100001abc: 14000009    	b	0x100001ae0 <_main+0x1418>
100001ac0: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001ac4: 9105a14a    	add	x10, x10, #0x168
100001ac8: f9400149    	ldr	x9, [x10]
100001acc: 5280058b    	mov	w11, #0x2c              ; =44
100001ad0: 3828692b    	strb	w11, [x9, x8]
100001ad4: f9400948    	ldr	x8, [x10, #0x10]
100001ad8: 91000508    	add	x8, x8, #0x1
100001adc: f9000948    	str	x8, [x10, #0x10]
100001ae0: f0000060    	adrp	x0, 0x100010000 <___anon_4031+0x22>
100001ae4: 91010000    	add	x0, x0, #0x40
100001ae8: 1e604100    	fmov	d0, d8
100001aec: 9400294e    	bl	0x10000c024 <_Io.Writer.printValue__anon_4310>
100001af0: 72003c1f    	tst	w0, #0xffff
100001af4: 54000401    	b.ne	0x100001b74 <_main+0x14ac>
100001af8: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001afc: 9105c129    	add	x9, x9, #0x170
100001b00: a9402129    	ldp	x9, x8, [x9]
100001b04: eb09011f    	cmp	x8, x9
100001b08: 54000263    	b.lo	0x100001b54 <_main+0x148c>
100001b0c: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001b10: 91058000    	add	x0, x0, #0x160
100001b14: f9400008    	ldr	x8, [x0]
100001b18: f9400109    	ldr	x9, [x8]
100001b1c: d0000068    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001b20: 913f750a    	add	x10, x8, #0xfdd
100001b24: 52800028    	mov	w8, #0x1                ; =1
100001b28: a938a3aa    	stp	x10, x8, [x29, #-0x78]
100001b2c: 9101c3e8    	add	x8, sp, #0x70
100001b30: d101e3a1    	sub	x1, x29, #0x78
100001b34: 52800022    	mov	w2, #0x1                ; =1
100001b38: 52800023    	mov	w3, #0x1                ; =1
100001b3c: d63f0120    	blr	x9
100001b40: 7940f3e8    	ldrh	w8, [sp, #0x78]
100001b44: 35000188    	cbnz	w8, 0x100001b74 <_main+0x14ac>
100001b48: f9403be8    	ldr	x8, [sp, #0x70]
100001b4c: b4fffd68    	cbz	x8, 0x100001af8 <_main+0x1430>
100001b50: 14000009    	b	0x100001b74 <_main+0x14ac>
100001b54: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001b58: 9105a14a    	add	x10, x10, #0x168
100001b5c: f9400149    	ldr	x9, [x10]
100001b60: 5280014b    	mov	w11, #0xa               ; =10
100001b64: 3828692b    	strb	w11, [x9, x8]
100001b68: f9400948    	ldr	x8, [x10, #0x10]
100001b6c: 91000508    	add	x8, x8, #0x1
100001b70: f9000948    	str	x8, [x10, #0x10]
100001b74: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001b78: 91052273    	add	x19, x19, #0x148
100001b7c: aa1303e0    	mov	x0, x19
100001b80: f8418c08    	ldr	x8, [x0, #0x18]!
100001b84: f9400908    	ldr	x8, [x8, #0x10]
100001b88: d63f0100    	blr	x8
100001b8c: a902fe7f    	stp	xzr, xzr, [x19, #0x28]
100001b90: b201f3e8    	mov	x8, #-0x5555555555555556 ; =-6148914691236517206
100001b94: f9001268    	str	x8, [x19, #0x20]
100001b98: f9400268    	ldr	x8, [x19]
100001b9c: f1000508    	subs	x8, x8, #0x1
100001ba0: f9000268    	str	x8, [x19]
100001ba4: 54ffd661    	b.ne	0x100001670 <_main+0xfa8>
100001ba8: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001bac: 91050108    	add	x8, x8, #0x140
100001bb0: 92800009    	mov	x9, #-0x1               ; =-1
100001bb4: f9000109    	str	x9, [x8]
100001bb8: 91004100    	add	x0, x8, #0x10
100001bbc: 940034cc    	bl	0x10000eeec <dyld_stub_binder+0x10000eeec>
100001bc0: 17fffeac    	b	0x100001670 <_main+0xfa8>
100001bc4: 52800000    	mov	w0, #0x0                ; =0
100001bc8: a9537bfd    	ldp	x29, x30, [sp, #0x130]
100001bcc: a9524ff4    	ldp	x20, x19, [sp, #0x120]
100001bd0: a95157f6    	ldp	x22, x21, [sp, #0x110]
100001bd4: a9505ff8    	ldp	x24, x23, [sp, #0x100]
100001bd8: a94f67fa    	ldp	x26, x25, [sp, #0xf0]
100001bdc: a94e6ffc    	ldp	x28, x27, [sp, #0xe0]
100001be0: 6d4d23e9    	ldp	d9, d8, [sp, #0xd0]
100001be4: 910503ff    	add	sp, sp, #0x140
100001be8: d65f03c0    	ret
100001bec: b0000080    	adrp	x0, 0x100012000 <___anon_4979+0x1f98>
100001bf0: 912e0800    	add	x0, x0, #0xb82
100001bf4: 52800201    	mov	w1, #0x10               ; =16
100001bf8: 94000003    	bl	0x100001c04 <_log.scoped(.default).err__anon_2520>
100001bfc: 52800020    	mov	w0, #0x1                ; =1
100001c00: 17fffff2    	b	0x100001bc8 <_main+0x1500>

0000000100001c04 <_log.scoped(.default).err__anon_2520>:
100001c04: d102c3ff    	sub	sp, sp, #0xb0
100001c08: a90667fa    	stp	x26, x25, [sp, #0x60]
100001c0c: a9075ff8    	stp	x24, x23, [sp, #0x70]
100001c10: a90857f6    	stp	x22, x21, [sp, #0x80]
100001c14: a9094ff4    	stp	x20, x19, [sp, #0x90]
100001c18: a90a7bfd    	stp	x29, x30, [sp, #0xa0]
100001c1c: 910283fd    	add	x29, sp, #0xa0
100001c20: aa0103f4    	mov	x20, x1
100001c24: aa0003f5    	mov	x21, x0
100001c28: 910003e0    	mov	x0, sp
100001c2c: 9400006f    	bl	0x100001de8 <_debug.lockStderrWriter>
100001c30: d2800018    	mov	x24, #0x0               ; =0
100001c34: f0000079    	adrp	x25, 0x100010000 <___anon_4031+0x22>
100001c38: 9101a339    	add	x25, x25, #0x68
100001c3c: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001c40: f940bd08    	ldr	x8, [x8, #0x178]
100001c44: f00000da    	adrp	x26, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001c48: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001c4c: 91058273    	add	x19, x19, #0x160
100001c50: f00000d7    	adrp	x23, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001c54: 9105a2f7    	add	x23, x23, #0x168
100001c58: 8b180321    	add	x1, x25, x24
100001c5c: d2400b16    	eor	x22, x24, #0x7
100001c60: f940bb49    	ldr	x9, [x26, #0x170]
100001c64: 8b0802ca    	add	x10, x22, x8
100001c68: eb09015f    	cmp	x10, x9
100001c6c: 54000188    	b.hi	0x100001c9c <_log.scoped(.default).err__anon_2520+0x98>
100001c70: f94002e9    	ldr	x9, [x23]
100001c74: 8b080120    	add	x0, x9, x8
100001c78: aa1603e2    	mov	x2, x22
100001c7c: 9400347b    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
100001c80: f9400ae8    	ldr	x8, [x23, #0x10]
100001c84: 8b160108    	add	x8, x8, x22
100001c88: f9000ae8    	str	x8, [x23, #0x10]
100001c8c: 8b1802d8    	add	x24, x22, x24
100001c90: f1001f1f    	cmp	x24, #0x7
100001c94: 54fffe23    	b.lo	0x100001c58 <_log.scoped(.default).err__anon_2520+0x54>
100001c98: 14000011    	b	0x100001cdc <_log.scoped(.default).err__anon_2520+0xd8>
100001c9c: f9400268    	ldr	x8, [x19]
100001ca0: f9400109    	ldr	x9, [x8]
100001ca4: a9045be1    	stp	x1, x22, [sp, #0x40]
100001ca8: 910143e8    	add	x8, sp, #0x50
100001cac: 910103e1    	add	x1, sp, #0x40
100001cb0: aa1303e0    	mov	x0, x19
100001cb4: 52800022    	mov	w2, #0x1                ; =1
100001cb8: 52800023    	mov	w3, #0x1                ; =1
100001cbc: d63f0120    	blr	x9
100001cc0: 7940b3e8    	ldrh	w8, [sp, #0x58]
100001cc4: 35000568    	cbnz	w8, 0x100001d70 <_log.scoped(.default).err__anon_2520+0x16c>
100001cc8: f9402bf6    	ldr	x22, [sp, #0x50]
100001ccc: f9400e68    	ldr	x8, [x19, #0x18]
100001cd0: 8b1802d8    	add	x24, x22, x24
100001cd4: f1001f1f    	cmp	x24, #0x7
100001cd8: 54fffc03    	b.lo	0x100001c58 <_log.scoped(.default).err__anon_2520+0x54>
100001cdc: f0000068    	adrp	x8, 0x100010000 <___anon_4031+0x22>
100001ce0: 39424103    	ldrb	w3, [x8, #0x90]
100001ce4: aa1503e0    	mov	x0, x21
100001ce8: aa1403e1    	mov	x1, x20
100001cec: aa1403e2    	mov	x2, x20
100001cf0: 52800404    	mov	w4, #0x20               ; =32
100001cf4: 94002e8a    	bl	0x10000d71c <_Io.Writer.alignBuffer>
100001cf8: 72003c1f    	tst	w0, #0xffff
100001cfc: 540003a1    	b.ne	0x100001d70 <_log.scoped(.default).err__anon_2520+0x16c>
100001d00: f00000d4    	adrp	x20, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001d04: 9105c294    	add	x20, x20, #0x170
100001d08: 52800035    	mov	w21, #0x1               ; =1
100001d0c: d0000076    	adrp	x22, 0x10000f000 <dyld_stub_binder+0x10000f000>
100001d10: 913f76d6    	add	x22, x22, #0xfdd
100001d14: a9402289    	ldp	x9, x8, [x20]
100001d18: eb09011f    	cmp	x8, x9
100001d1c: 540001e3    	b.lo	0x100001d58 <_log.scoped(.default).err__anon_2520+0x154>
100001d20: f9400268    	ldr	x8, [x19]
100001d24: f9400109    	ldr	x9, [x8]
100001d28: a90457f6    	stp	x22, x21, [sp, #0x40]
100001d2c: 910143e8    	add	x8, sp, #0x50
100001d30: 910103e1    	add	x1, sp, #0x40
100001d34: aa1303e0    	mov	x0, x19
100001d38: 52800022    	mov	w2, #0x1                ; =1
100001d3c: 52800023    	mov	w3, #0x1                ; =1
100001d40: d63f0120    	blr	x9
100001d44: 7940b3e8    	ldrh	w8, [sp, #0x58]
100001d48: 35000148    	cbnz	w8, 0x100001d70 <_log.scoped(.default).err__anon_2520+0x16c>
100001d4c: f9402be8    	ldr	x8, [sp, #0x50]
100001d50: b4fffe28    	cbz	x8, 0x100001d14 <_log.scoped(.default).err__anon_2520+0x110>
100001d54: 14000007    	b	0x100001d70 <_log.scoped(.default).err__anon_2520+0x16c>
100001d58: f94002e9    	ldr	x9, [x23]
100001d5c: 5280014a    	mov	w10, #0xa               ; =10
100001d60: 3828692a    	strb	w10, [x9, x8]
100001d64: f9400ae8    	ldr	x8, [x23, #0x10]
100001d68: 91000508    	add	x8, x8, #0x1
100001d6c: f9000ae8    	str	x8, [x23, #0x10]
100001d70: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001d74: 91052273    	add	x19, x19, #0x148
100001d78: aa1303e0    	mov	x0, x19
100001d7c: f8418c08    	ldr	x8, [x0, #0x18]!
100001d80: f9400908    	ldr	x8, [x8, #0x10]
100001d84: d63f0100    	blr	x8
100001d88: b201f3e8    	mov	x8, #-0x5555555555555556 ; =-6148914691236517206
100001d8c: a902fe7f    	stp	xzr, xzr, [x19, #0x28]
100001d90: f9001268    	str	x8, [x19, #0x20]
100001d94: f9400268    	ldr	x8, [x19]
100001d98: f1000508    	subs	x8, x8, #0x1
100001d9c: f9000268    	str	x8, [x19]
100001da0: 540000e1    	b.ne	0x100001dbc <_log.scoped(.default).err__anon_2520+0x1b8>
100001da4: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001da8: 91050108    	add	x8, x8, #0x140
100001dac: 92800009    	mov	x9, #-0x1               ; =-1
100001db0: f9000109    	str	x9, [x8]
100001db4: 91004100    	add	x0, x8, #0x10
100001db8: 9400344d    	bl	0x10000eeec <dyld_stub_binder+0x10000eeec>
100001dbc: a94a7bfd    	ldp	x29, x30, [sp, #0xa0]
100001dc0: a9494ff4    	ldp	x20, x19, [sp, #0x90]
100001dc4: a94857f6    	ldp	x22, x21, [sp, #0x80]
100001dc8: a9475ff8    	ldp	x24, x23, [sp, #0x70]
100001dcc: a94667fa    	ldp	x26, x25, [sp, #0x60]
100001dd0: 9102c3ff    	add	sp, sp, #0xb0
100001dd4: d65f03c0    	ret

0000000100001dd8 <_start.noopSigHandler>:
100001dd8: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100001ddc: 910003fd    	mov	x29, sp
100001de0: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100001de4: d65f03c0    	ret

0000000100001de8 <_debug.lockStderrWriter>:
100001de8: d10103ff    	sub	sp, sp, #0x40
100001dec: a90157f6    	stp	x22, x21, [sp, #0x10]
100001df0: a9024ff4    	stp	x20, x19, [sp, #0x20]
100001df4: a9037bfd    	stp	x29, x30, [sp, #0x30]
100001df8: 9100c3fd    	add	x29, sp, #0x30
100001dfc: aa0003f3    	mov	x19, x0
100001e00: 910023e1    	add	x1, sp, #0x8
100001e04: d2800000    	mov	x0, #0x0                ; =0
100001e08: 9400343c    	bl	0x10000eef8 <dyld_stub_binder+0x10000eef8>
100001e0c: f94007f4    	ldr	x20, [sp, #0x8]
100001e10: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001e14: f940a108    	ldr	x8, [x8, #0x140]
100001e18: eb14011f    	cmp	x8, x20
100001e1c: 540000a1    	b.ne	0x100001e30 <_debug.lockStderrWriter+0x48>
100001e20: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001e24: f940a508    	ldr	x8, [x8, #0x148]
100001e28: 91000508    	add	x8, x8, #0x1
100001e2c: 14000007    	b	0x100001e48 <_debug.lockStderrWriter+0x60>
100001e30: f00000d5    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001e34: 910502b5    	add	x21, x21, #0x140
100001e38: 910042a0    	add	x0, x21, #0x10
100001e3c: 94003429    	bl	0x10000eee0 <dyld_stub_binder+0x10000eee0>
100001e40: f90002b4    	str	x20, [x21]
100001e44: 52800028    	mov	w8, #0x1                ; =1
100001e48: f00000d4    	adrp	x20, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001e4c: 91052294    	add	x20, x20, #0x148
100001e50: f9000288    	str	x8, [x20]
100001e54: aa1403e0    	mov	x0, x20
100001e58: f8418c08    	ldr	x8, [x0, #0x18]!
100001e5c: f9400908    	ldr	x8, [x8, #0x10]
100001e60: d63f0100    	blr	x8
100001e64: 52800808    	mov	w8, #0x40               ; =64
100001e68: a9022293    	stp	x19, x8, [x20, #0x20]
100001e6c: a9437bfd    	ldp	x29, x30, [sp, #0x30]
100001e70: a9424ff4    	ldp	x20, x19, [sp, #0x20]
100001e74: a94157f6    	ldp	x22, x21, [sp, #0x10]
100001e78: 910103ff    	add	sp, sp, #0x40
100001e7c: d65f03c0    	ret

0000000100001e80 <_codegen_smul12x10>:
100001e80: 6dba3bef    	stp	d15, d14, [sp, #-0x60]!
100001e84: 6d0133ed    	stp	d13, d12, [sp, #0x10]
100001e88: 6d022beb    	stp	d11, d10, [sp, #0x20]
100001e8c: 6d0323e9    	stp	d9, d8, [sp, #0x30]
100001e90: a9046ffc    	stp	x28, x27, [sp, #0x40]
100001e94: a9057bfd    	stp	x29, x30, [sp, #0x50]
100001e98: 910143fd    	add	x29, sp, #0x50
100001e9c: d10f03ff    	sub	sp, sp, #0x3c0
100001ea0: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001ea4: 91190108    	add	x8, x8, #0x640
100001ea8: ad401507    	ldp	q7, q5, [x8]
100001eac: 3dc12119    	ldr	q25, [x8, #0x480]
100001eb0: 4fc79320    	fmul.2d	v0, v25, v7[0]
100001eb4: 3cc08110    	ldur	q16, [x8, #0x8]
100001eb8: 3dc1390c    	ldr	q12, [x8, #0x4e0]
100001ebc: 4fd09181    	fmul.2d	v1, v12, v16[0]
100001ec0: 3d8083ec    	str	q12, [sp, #0x200]
100001ec4: 4e61d400    	fadd.2d	v0, v0, v1
100001ec8: 3dc1510b    	ldr	q11, [x8, #0x540]
100001ecc: 4fc59161    	fmul.2d	v1, v11, v5[0]
100001ed0: 4e61d400    	fadd.2d	v0, v0, v1
100001ed4: 3cc18104    	ldur	q4, [x8, #0x18]
100001ed8: 3dc1690a    	ldr	q10, [x8, #0x5a0]
100001edc: 4fc49141    	fmul.2d	v1, v10, v4[0]
100001ee0: 3d8037ea    	str	q10, [sp, #0xd0]
100001ee4: 4e61d400    	fadd.2d	v0, v0, v1
100001ee8: ad410d1d    	ldp	q29, q3, [x8, #0x20]
100001eec: 3dc18101    	ldr	q1, [x8, #0x600]
100001ef0: 3c9303a1    	stur	q1, [x29, #-0xd0]
100001ef4: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100001ef8: 4e61d400    	fadd.2d	v0, v0, v1
100001efc: 3cc28106    	ldur	q6, [x8, #0x28]
100001f00: 3dc19908    	ldr	q8, [x8, #0x660]
100001f04: 4fc69101    	fmul.2d	v1, v8, v6[0]
100001f08: 4e61d400    	fadd.2d	v0, v0, v1
100001f0c: 3dc1b101    	ldr	q1, [x8, #0x6c0]
100001f10: 3d804be1    	str	q1, [sp, #0x120]
100001f14: 4fc39021    	fmul.2d	v1, v1, v3[0]
100001f18: 4e61d400    	fadd.2d	v0, v0, v1
100001f1c: 3cc38102    	ldur	q2, [x8, #0x38]
100001f20: 3dc1c909    	ldr	q9, [x8, #0x720]
100001f24: 4fc29121    	fmul.2d	v1, v9, v2[0]
100001f28: ad01a3e9    	stp	q9, q8, [sp, #0x30]
100001f2c: 4e61d400    	fadd.2d	v0, v0, v1
100001f30: 3dc01101    	ldr	q1, [x8, #0x40]
100001f34: 3dc1e10e    	ldr	q14, [x8, #0x780]
100001f38: 4fc191d1    	fmul.2d	v17, v14, v1[0]
100001f3c: 4e71d411    	fadd.2d	v17, v0, v17
100001f40: 3cc48100    	ldur	q0, [x8, #0x48]
100001f44: 3dc1f917    	ldr	q23, [x8, #0x7e0]
100001f48: 4fc092f2    	fmul.2d	v18, v23, v0[0]
100001f4c: 3d8017f7    	str	q23, [sp, #0x50]
100001f50: 4e72d631    	fadd.2d	v17, v17, v18
100001f54: 3dc1251f    	ldr	q31, [x8, #0x490]
100001f58: 4fc793f2    	fmul.2d	v18, v31, v7[0]
100001f5c: 3d800bff    	str	q31, [sp, #0x20]
100001f60: 3dc13d0f    	ldr	q15, [x8, #0x4f0]
100001f64: 4fd091f3    	fmul.2d	v19, v15, v16[0]
100001f68: 4e73d652    	fadd.2d	v18, v18, v19
100001f6c: 3dc15513    	ldr	q19, [x8, #0x550]
100001f70: 3d807ff3    	str	q19, [sp, #0x1f0]
100001f74: 4fc59273    	fmul.2d	v19, v19, v5[0]
100001f78: 4e73d652    	fadd.2d	v18, v18, v19
100001f7c: 3dc16d1e    	ldr	q30, [x8, #0x5b0]
100001f80: 4fc493d3    	fmul.2d	v19, v30, v4[0]
100001f84: 4e73d652    	fadd.2d	v18, v18, v19
100001f88: 3dc18513    	ldr	q19, [x8, #0x610]
100001f8c: 3d807bf3    	str	q19, [sp, #0x1e0]
100001f90: 4fdd9273    	fmul.2d	v19, v19, v29[0]
100001f94: 4e73d652    	fadd.2d	v18, v18, v19
100001f98: 3dc19d1c    	ldr	q28, [x8, #0x670]
100001f9c: 4fc69393    	fmul.2d	v19, v28, v6[0]
100001fa0: ad077bfc    	stp	q28, q30, [sp, #0xe0]
100001fa4: 4e73d652    	fadd.2d	v18, v18, v19
100001fa8: 3dc1b51b    	ldr	q27, [x8, #0x6d0]
100001fac: 4fc39373    	fmul.2d	v19, v27, v3[0]
100001fb0: 3d8007fb    	str	q27, [sp, #0x10]
100001fb4: 4e73d652    	fadd.2d	v18, v18, v19
100001fb8: 3dc1cd1a    	ldr	q26, [x8, #0x730]
100001fbc: 4fc29353    	fmul.2d	v19, v26, v2[0]
100001fc0: 3d809ffa    	str	q26, [sp, #0x270]
100001fc4: 4e73d652    	fadd.2d	v18, v18, v19
100001fc8: 3dc1e513    	ldr	q19, [x8, #0x790]
100001fcc: 3d8077f3    	str	q19, [sp, #0x1d0]
100001fd0: 4fc19273    	fmul.2d	v19, v19, v1[0]
100001fd4: 4e73d652    	fadd.2d	v18, v18, v19
100001fd8: 3dc1fd13    	ldr	q19, [x8, #0x7f0]
100001fdc: 3d8073f3    	str	q19, [sp, #0x1c0]
100001fe0: 4fc09273    	fmul.2d	v19, v19, v0[0]
100001fe4: 4e73d652    	fadd.2d	v18, v18, v19
100001fe8: 3dc12913    	ldr	q19, [x8, #0x4a0]
100001fec: 3d806ff3    	str	q19, [sp, #0x1b0]
100001ff0: 4fc79273    	fmul.2d	v19, v19, v7[0]
100001ff4: 3dc14114    	ldr	q20, [x8, #0x500]
100001ff8: 3d806bf4    	str	q20, [sp, #0x1a0]
100001ffc: 4fd09294    	fmul.2d	v20, v20, v16[0]
100002000: 4e74d673    	fadd.2d	v19, v19, v20
100002004: 3dc15914    	ldr	q20, [x8, #0x560]
100002008: 3d8067f4    	str	q20, [sp, #0x190]
10000200c: 4fc59294    	fmul.2d	v20, v20, v5[0]
100002010: 4e74d673    	fadd.2d	v19, v19, v20
100002014: 3dc17114    	ldr	q20, [x8, #0x5c0]
100002018: 3d8063f4    	str	q20, [sp, #0x180]
10000201c: 4fc49294    	fmul.2d	v20, v20, v4[0]
100002020: 4e74d673    	fadd.2d	v19, v19, v20
100002024: 3dc18914    	ldr	q20, [x8, #0x620]
100002028: 3d805ff4    	str	q20, [sp, #0x170]
10000202c: 4fdd9294    	fmul.2d	v20, v20, v29[0]
100002030: 4e74d673    	fadd.2d	v19, v19, v20
100002034: 3dc1a114    	ldr	q20, [x8, #0x680]
100002038: 3d805bf4    	str	q20, [sp, #0x160]
10000203c: 4fc69294    	fmul.2d	v20, v20, v6[0]
100002040: 4e74d673    	fadd.2d	v19, v19, v20
100002044: 3dc1b914    	ldr	q20, [x8, #0x6e0]
100002048: 3d8057f4    	str	q20, [sp, #0x150]
10000204c: 4fc39294    	fmul.2d	v20, v20, v3[0]
100002050: 4e74d673    	fadd.2d	v19, v19, v20
100002054: 3dc1d10d    	ldr	q13, [x8, #0x740]
100002058: 4fc291b4    	fmul.2d	v20, v13, v2[0]
10000205c: 4e74d673    	fadd.2d	v19, v19, v20
100002060: 3dc1e914    	ldr	q20, [x8, #0x7a0]
100002064: 3d8053f4    	str	q20, [sp, #0x140]
100002068: 4fc19294    	fmul.2d	v20, v20, v1[0]
10000206c: 4e74d673    	fadd.2d	v19, v19, v20
100002070: 3dc20114    	ldr	q20, [x8, #0x800]
100002074: 3c9103b4    	stur	q20, [x29, #-0xf0]
100002078: 4fc09294    	fmul.2d	v20, v20, v0[0]
10000207c: 4e74d673    	fadd.2d	v19, v19, v20
100002080: 3dc12d14    	ldr	q20, [x8, #0x4b0]
100002084: 3c9203b4    	stur	q20, [x29, #-0xe0]
100002088: 4fc79294    	fmul.2d	v20, v20, v7[0]
10000208c: 3dc14515    	ldr	q21, [x8, #0x510]
100002090: 3d8097f5    	str	q21, [sp, #0x250]
100002094: 4fd092b5    	fmul.2d	v21, v21, v16[0]
100002098: 4e75d694    	fadd.2d	v20, v20, v21
10000209c: 3dc15d15    	ldr	q21, [x8, #0x570]
1000020a0: 3d8093f5    	str	q21, [sp, #0x240]
1000020a4: 4fc592b5    	fmul.2d	v21, v21, v5[0]
1000020a8: 4e75d694    	fadd.2d	v20, v20, v21
1000020ac: 3dc17515    	ldr	q21, [x8, #0x5d0]
1000020b0: 3d808ff5    	str	q21, [sp, #0x230]
1000020b4: 4fc492b5    	fmul.2d	v21, v21, v4[0]
1000020b8: 4e75d694    	fadd.2d	v20, v20, v21
1000020bc: 3dc18d15    	ldr	q21, [x8, #0x630]
1000020c0: 3d808bf5    	str	q21, [sp, #0x220]
1000020c4: 4fdd92b5    	fmul.2d	v21, v21, v29[0]
1000020c8: 4e75d694    	fadd.2d	v20, v20, v21
1000020cc: 3dc1a515    	ldr	q21, [x8, #0x690]
1000020d0: 3d8087f5    	str	q21, [sp, #0x210]
1000020d4: 4fc692b5    	fmul.2d	v21, v21, v6[0]
1000020d8: 4e75d694    	fadd.2d	v20, v20, v21
1000020dc: 3dc1bd15    	ldr	q21, [x8, #0x6f0]
1000020e0: 3d8033f5    	str	q21, [sp, #0xc0]
1000020e4: 4fc392b5    	fmul.2d	v21, v21, v3[0]
1000020e8: 4e75d694    	fadd.2d	v20, v20, v21
1000020ec: 3dc1d515    	ldr	q21, [x8, #0x750]
1000020f0: 3d802ff5    	str	q21, [sp, #0xb0]
1000020f4: 4fc292b5    	fmul.2d	v21, v21, v2[0]
1000020f8: 4e75d694    	fadd.2d	v20, v20, v21
1000020fc: 3dc1ed15    	ldr	q21, [x8, #0x7b0]
100002100: 3d802bf5    	str	q21, [sp, #0xa0]
100002104: 4fc192b5    	fmul.2d	v21, v21, v1[0]
100002108: 4e75d694    	fadd.2d	v20, v20, v21
10000210c: 3dc20515    	ldr	q21, [x8, #0x810]
100002110: 3d8027f5    	str	q21, [sp, #0x90]
100002114: 4fc092b5    	fmul.2d	v21, v21, v0[0]
100002118: 4e75d694    	fadd.2d	v20, v20, v21
10000211c: 3dc13115    	ldr	q21, [x8, #0x4c0]
100002120: 3d8023f5    	str	q21, [sp, #0x80]
100002124: 4fc792b5    	fmul.2d	v21, v21, v7[0]
100002128: 3dc14916    	ldr	q22, [x8, #0x520]
10000212c: 3d801ff6    	str	q22, [sp, #0x70]
100002130: 4fd092d6    	fmul.2d	v22, v22, v16[0]
100002134: 4e76d6b5    	fadd.2d	v21, v21, v22
100002138: 3dc16116    	ldr	q22, [x8, #0x580]
10000213c: 3c9003b6    	stur	q22, [x29, #-0x100]
100002140: 4fc592d6    	fmul.2d	v22, v22, v5[0]
100002144: 4e76d6b5    	fadd.2d	v21, v21, v22
100002148: 3dc17916    	ldr	q22, [x8, #0x5e0]
10000214c: 3d80c3f6    	str	q22, [sp, #0x300]
100002150: 4fc492d6    	fmul.2d	v22, v22, v4[0]
100002154: 4e76d6b5    	fadd.2d	v21, v21, v22
100002158: 3dc19116    	ldr	q22, [x8, #0x640]
10000215c: 3d80bff6    	str	q22, [sp, #0x2f0]
100002160: 4fdd92d6    	fmul.2d	v22, v22, v29[0]
100002164: 4e76d6b5    	fadd.2d	v21, v21, v22
100002168: 3dc1a916    	ldr	q22, [x8, #0x6a0]
10000216c: 3d80bbf6    	str	q22, [sp, #0x2e0]
100002170: 4fc692d6    	fmul.2d	v22, v22, v6[0]
100002174: 4e76d6b5    	fadd.2d	v21, v21, v22
100002178: d00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000217c: 91064129    	add	x9, x9, #0x190
100002180: ad004931    	stp	q17, q18, [x9]
100002184: 3dc1c111    	ldr	q17, [x8, #0x700]
100002188: 3d80b7f1    	str	q17, [sp, #0x2d0]
10000218c: 4fc39231    	fmul.2d	v17, v17, v3[0]
100002190: 4e71d6b1    	fadd.2d	v17, v21, v17
100002194: 3dc1d912    	ldr	q18, [x8, #0x760]
100002198: 3d80aff2    	str	q18, [sp, #0x2b0]
10000219c: 4fc29252    	fmul.2d	v18, v18, v2[0]
1000021a0: 4e72d631    	fadd.2d	v17, v17, v18
1000021a4: 3dc1f118    	ldr	q24, [x8, #0x7c0]
1000021a8: 4fc19312    	fmul.2d	v18, v24, v1[0]
1000021ac: 3d809bf8    	str	q24, [sp, #0x260]
1000021b0: 4e72d631    	fadd.2d	v17, v17, v18
1000021b4: 3dc20912    	ldr	q18, [x8, #0x820]
1000021b8: 3d804ff2    	str	q18, [sp, #0x130]
1000021bc: 4fc09252    	fmul.2d	v18, v18, v0[0]
1000021c0: 4e72d631    	fadd.2d	v17, v17, v18
1000021c4: 3dc13512    	ldr	q18, [x8, #0x4d0]
1000021c8: 3d8047f2    	str	q18, [sp, #0x110]
1000021cc: 4fc79247    	fmul.2d	v7, v18, v7[0]
1000021d0: 3dc14d12    	ldr	q18, [x8, #0x530]
1000021d4: 4fd09250    	fmul.2d	v16, v18, v16[0]
1000021d8: 4e70d4e7    	fadd.2d	v7, v7, v16
1000021dc: 3dc16510    	ldr	q16, [x8, #0x590]
1000021e0: ad144bf0    	stp	q16, q18, [sp, #0x280]
1000021e4: 4fc59205    	fmul.2d	v5, v16, v5[0]
1000021e8: 4e65d4e5    	fadd.2d	v5, v7, v5
1000021ec: 3dc17d07    	ldr	q7, [x8, #0x5f0]
1000021f0: 4fc490e4    	fmul.2d	v4, v7, v4[0]
1000021f4: 4e64d4a4    	fadd.2d	v4, v5, v4
1000021f8: ad015133    	stp	q19, q20, [x9, #0x20]
1000021fc: 3dc19505    	ldr	q5, [x8, #0x650]
100002200: ad3c9fa5    	stp	q5, q7, [x29, #-0x70]
100002204: 4fdd90a5    	fmul.2d	v5, v5, v29[0]
100002208: 4e65d484    	fadd.2d	v4, v4, v5
10000220c: 3dc1ad05    	ldr	q5, [x8, #0x6b0]
100002210: 3c9803a5    	stur	q5, [x29, #-0x80]
100002214: 4fc690a5    	fmul.2d	v5, v5, v6[0]
100002218: 4e65d484    	fadd.2d	v4, v4, v5
10000221c: 3dc1c505    	ldr	q5, [x8, #0x710]
100002220: 4fc390a3    	fmul.2d	v3, v5, v3[0]
100002224: 4e63d483    	fadd.2d	v3, v4, v3
100002228: 3dc1dd04    	ldr	q4, [x8, #0x770]
10000222c: ad3b17a4    	stp	q4, q5, [x29, #-0xa0]
100002230: 4fc29082    	fmul.2d	v2, v4, v2[0]
100002234: 4e62d462    	fadd.2d	v2, v3, v2
100002238: 3dc1f503    	ldr	q3, [x8, #0x7d0]
10000223c: 4fc19061    	fmul.2d	v1, v3, v1[0]
100002240: 4e61d441    	fadd.2d	v1, v2, v1
100002244: 3dc20d02    	ldr	q2, [x8, #0x830]
100002248: ad3a0fa2    	stp	q2, q3, [x29, #-0xc0]
10000224c: 4fc09040    	fmul.2d	v0, v2, v0[0]
100002250: 4e60d420    	fadd.2d	v0, v1, v0
100002254: 3dc01910    	ldr	q16, [x8, #0x60]
100002258: 3cc68101    	ldur	q1, [x8, #0x68]
10000225c: 3d80abf9    	str	q25, [sp, #0x2a0]
100002260: 4fd09322    	fmul.2d	v2, v25, v16[0]
100002264: 4fc19183    	fmul.2d	v3, v12, v1[0]
100002268: 4e63d443    	fadd.2d	v3, v2, v3
10000226c: ad020131    	stp	q17, q0, [x9, #0x40]
100002270: 3dc01d02    	ldr	q2, [x8, #0x70]
100002274: 4eab1d72    	mov.16b	v18, v11
100002278: 3d80b3eb    	str	q11, [sp, #0x2c0]
10000227c: 4fc29160    	fmul.2d	v0, v11, v2[0]
100002280: 4e60d460    	fadd.2d	v0, v3, v0
100002284: 3cc78103    	ldur	q3, [x8, #0x78]
100002288: 4fc39144    	fmul.2d	v4, v10, v3[0]
10000228c: 4e64d400    	fadd.2d	v0, v0, v4
100002290: ad447504    	ldp	q4, q29, [x8, #0x80]
100002294: 3cd303b3    	ldur	q19, [x29, #-0xd0]
100002298: 4fc49265    	fmul.2d	v5, v19, v4[0]
10000229c: 4e65d400    	fadd.2d	v0, v0, v5
1000022a0: 3cc88105    	ldur	q5, [x8, #0x88]
1000022a4: 4fc59106    	fmul.2d	v6, v8, v5[0]
1000022a8: 4e66d400    	fadd.2d	v0, v0, v6
1000022ac: 3dc04bf4    	ldr	q20, [sp, #0x120]
1000022b0: 4fdd9286    	fmul.2d	v6, v20, v29[0]
1000022b4: 4e66d400    	fadd.2d	v0, v0, v6
1000022b8: 3cc98106    	ldur	q6, [x8, #0x98]
1000022bc: 4fc69127    	fmul.2d	v7, v9, v6[0]
1000022c0: 4e67d400    	fadd.2d	v0, v0, v7
1000022c4: 3dc02907    	ldr	q7, [x8, #0xa0]
1000022c8: 4eae1dd5    	mov.16b	v21, v14
1000022cc: 3d8003ee    	str	q14, [sp]
1000022d0: 4fc791d1    	fmul.2d	v17, v14, v7[0]
1000022d4: 4e71d411    	fadd.2d	v17, v0, v17
1000022d8: 3cca8100    	ldur	q0, [x8, #0xa8]
1000022dc: 4fc092ee    	fmul.2d	v14, v23, v0[0]
1000022e0: 4e6ed631    	fadd.2d	v17, v17, v14
1000022e4: 4fd093ee    	fmul.2d	v14, v31, v16[0]
1000022e8: 3d8043ef    	str	q15, [sp, #0x100]
1000022ec: 4fc191ef    	fmul.2d	v15, v15, v1[0]
1000022f0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000022f4: ad4f5bf7    	ldp	q23, q22, [sp, #0x1e0]
1000022f8: 4fc292cf    	fmul.2d	v15, v22, v2[0]
1000022fc: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002300: 4fc393cf    	fmul.2d	v15, v30, v3[0]
100002304: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002308: 4fc492ef    	fmul.2d	v15, v23, v4[0]
10000230c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002310: 4fc5938f    	fmul.2d	v15, v28, v5[0]
100002314: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002318: 4fdd936f    	fmul.2d	v15, v27, v29[0]
10000231c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002320: 4fc6934f    	fmul.2d	v15, v26, v6[0]
100002324: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002328: ad4e7bfb    	ldp	q27, q30, [sp, #0x1c0]
10000232c: 4fc793cf    	fmul.2d	v15, v30, v7[0]
100002330: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002334: 4fc0936f    	fmul.2d	v15, v27, v0[0]
100002338: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000233c: ad033931    	stp	q17, q14, [x9, #0x60]
100002340: ad4d73ff    	ldp	q31, q28, [sp, #0x1a0]
100002344: 4fd09391    	fmul.2d	v17, v28, v16[0]
100002348: 4fc193ee    	fmul.2d	v14, v31, v1[0]
10000234c: 4e6ed631    	fadd.2d	v17, v17, v14
100002350: ad4c23e9    	ldp	q9, q8, [sp, #0x180]
100002354: 4fc2910e    	fmul.2d	v14, v8, v2[0]
100002358: 4e6ed631    	fadd.2d	v17, v17, v14
10000235c: 4fc3912e    	fmul.2d	v14, v9, v3[0]
100002360: 4e6ed631    	fadd.2d	v17, v17, v14
100002364: ad4b2beb    	ldp	q11, q10, [sp, #0x160]
100002368: 4fc4914e    	fmul.2d	v14, v10, v4[0]
10000236c: 4e6ed631    	fadd.2d	v17, v17, v14
100002370: 4fc5916e    	fmul.2d	v14, v11, v5[0]
100002374: 4e6ed631    	fadd.2d	v17, v17, v14
100002378: ad4a33fa    	ldp	q26, q12, [sp, #0x140]
10000237c: 4fdd918e    	fmul.2d	v14, v12, v29[0]
100002380: 4e6ed631    	fadd.2d	v17, v17, v14
100002384: 3d801bed    	str	q13, [sp, #0x60]
100002388: 4fc691ae    	fmul.2d	v14, v13, v6[0]
10000238c: 4e6ed631    	fadd.2d	v17, v17, v14
100002390: 4fc7934e    	fmul.2d	v14, v26, v7[0]
100002394: 4e6ed631    	fadd.2d	v17, v17, v14
100002398: 3cd103ae    	ldur	q14, [x29, #-0xf0]
10000239c: 4fc091ce    	fmul.2d	v14, v14, v0[0]
1000023a0: 4e6ed631    	fadd.2d	v17, v17, v14
1000023a4: 3cd203ae    	ldur	q14, [x29, #-0xe0]
1000023a8: 4fd091ce    	fmul.2d	v14, v14, v16[0]
1000023ac: 3dc097ef    	ldr	q15, [sp, #0x250]
1000023b0: 4fc191ef    	fmul.2d	v15, v15, v1[0]
1000023b4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023b8: 3dc093ef    	ldr	q15, [sp, #0x240]
1000023bc: 4fc291ef    	fmul.2d	v15, v15, v2[0]
1000023c0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023c4: 3dc08fef    	ldr	q15, [sp, #0x230]
1000023c8: 4fc391ef    	fmul.2d	v15, v15, v3[0]
1000023cc: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023d0: 3dc08bef    	ldr	q15, [sp, #0x220]
1000023d4: 4fc491ef    	fmul.2d	v15, v15, v4[0]
1000023d8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023dc: 3dc087ef    	ldr	q15, [sp, #0x210]
1000023e0: 4fc591ef    	fmul.2d	v15, v15, v5[0]
1000023e4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023e8: 3dc033ef    	ldr	q15, [sp, #0xc0]
1000023ec: 4fdd91ef    	fmul.2d	v15, v15, v29[0]
1000023f0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023f4: 3dc02fef    	ldr	q15, [sp, #0xb0]
1000023f8: 4fc691ef    	fmul.2d	v15, v15, v6[0]
1000023fc: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002400: 3dc02bef    	ldr	q15, [sp, #0xa0]
100002404: 4fc791ef    	fmul.2d	v15, v15, v7[0]
100002408: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000240c: 3dc027ef    	ldr	q15, [sp, #0x90]
100002410: 4fc091ef    	fmul.2d	v15, v15, v0[0]
100002414: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002418: ad043931    	stp	q17, q14, [x9, #0x80]
10000241c: ad43c7ee    	ldp	q14, q17, [sp, #0x70]
100002420: 4fd09231    	fmul.2d	v17, v17, v16[0]
100002424: 4fc191ce    	fmul.2d	v14, v14, v1[0]
100002428: 4e6ed631    	fadd.2d	v17, v17, v14
10000242c: 3cd003ae    	ldur	q14, [x29, #-0x100]
100002430: 4fc291ce    	fmul.2d	v14, v14, v2[0]
100002434: 4e6ed631    	fadd.2d	v17, v17, v14
100002438: 3dc0c3ee    	ldr	q14, [sp, #0x300]
10000243c: 4fc391ce    	fmul.2d	v14, v14, v3[0]
100002440: 4e6ed631    	fadd.2d	v17, v17, v14
100002444: 3dc0bfee    	ldr	q14, [sp, #0x2f0]
100002448: 4fc491ce    	fmul.2d	v14, v14, v4[0]
10000244c: 4e6ed631    	fadd.2d	v17, v17, v14
100002450: 3dc0bbee    	ldr	q14, [sp, #0x2e0]
100002454: 4fc591ce    	fmul.2d	v14, v14, v5[0]
100002458: 4e6ed631    	fadd.2d	v17, v17, v14
10000245c: 3dc0b7ee    	ldr	q14, [sp, #0x2d0]
100002460: 4fdd91ce    	fmul.2d	v14, v14, v29[0]
100002464: 4e6ed631    	fadd.2d	v17, v17, v14
100002468: 3dc0afee    	ldr	q14, [sp, #0x2b0]
10000246c: 4fc691ce    	fmul.2d	v14, v14, v6[0]
100002470: 4e6ed631    	fadd.2d	v17, v17, v14
100002474: 4fc7930e    	fmul.2d	v14, v24, v7[0]
100002478: 4e6ed631    	fadd.2d	v17, v17, v14
10000247c: 3dc04ff8    	ldr	q24, [sp, #0x130]
100002480: 4fc0930e    	fmul.2d	v14, v24, v0[0]
100002484: 4e6ed631    	fadd.2d	v17, v17, v14
100002488: 3dc047ee    	ldr	q14, [sp, #0x110]
10000248c: 4fd091d0    	fmul.2d	v16, v14, v16[0]
100002490: 3dc0a7ee    	ldr	q14, [sp, #0x290]
100002494: 4fc191c1    	fmul.2d	v1, v14, v1[0]
100002498: 4e61d601    	fadd.2d	v1, v16, v1
10000249c: 3dc0a3f0    	ldr	q16, [sp, #0x280]
1000024a0: 4fc29202    	fmul.2d	v2, v16, v2[0]
1000024a4: 4e62d421    	fadd.2d	v1, v1, v2
1000024a8: 3cda03a2    	ldur	q2, [x29, #-0x60]
1000024ac: 4fc39042    	fmul.2d	v2, v2, v3[0]
1000024b0: 4e62d421    	fadd.2d	v1, v1, v2
1000024b4: 3cd903a2    	ldur	q2, [x29, #-0x70]
1000024b8: 4fc49042    	fmul.2d	v2, v2, v4[0]
1000024bc: 4e62d421    	fadd.2d	v1, v1, v2
1000024c0: 3cd803a2    	ldur	q2, [x29, #-0x80]
1000024c4: 4fc59042    	fmul.2d	v2, v2, v5[0]
1000024c8: 4e62d421    	fadd.2d	v1, v1, v2
1000024cc: 3cd703a2    	ldur	q2, [x29, #-0x90]
1000024d0: 4fdd9042    	fmul.2d	v2, v2, v29[0]
1000024d4: 4e62d421    	fadd.2d	v1, v1, v2
1000024d8: 3cd603a2    	ldur	q2, [x29, #-0xa0]
1000024dc: 4fc69042    	fmul.2d	v2, v2, v6[0]
1000024e0: 4e62d421    	fadd.2d	v1, v1, v2
1000024e4: 3cd503a2    	ldur	q2, [x29, #-0xb0]
1000024e8: 4fc79042    	fmul.2d	v2, v2, v7[0]
1000024ec: 4e62d421    	fadd.2d	v1, v1, v2
1000024f0: 3cd403a2    	ldur	q2, [x29, #-0xc0]
1000024f4: 4fc09040    	fmul.2d	v0, v2, v0[0]
1000024f8: 4e60d420    	fadd.2d	v0, v1, v0
1000024fc: ad050131    	stp	q17, q0, [x9, #0xa0]
100002500: ad460906    	ldp	q6, q2, [x8, #0xc0]
100002504: 3ccc8107    	ldur	q7, [x8, #0xc8]
100002508: 4fc69320    	fmul.2d	v0, v25, v6[0]
10000250c: 3dc083f9    	ldr	q25, [sp, #0x200]
100002510: 4fc79321    	fmul.2d	v1, v25, v7[0]
100002514: 4e61d400    	fadd.2d	v0, v0, v1
100002518: 4fc29241    	fmul.2d	v1, v18, v2[0]
10000251c: 4e61d400    	fadd.2d	v0, v0, v1
100002520: 3ccd8103    	ldur	q3, [x8, #0xd8]
100002524: 3dc037e1    	ldr	q1, [sp, #0xd0]
100002528: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000252c: 4e61d400    	fadd.2d	v0, v0, v1
100002530: ad471504    	ldp	q4, q5, [x8, #0xe0]
100002534: 4fc49261    	fmul.2d	v1, v19, v4[0]
100002538: 4e61d400    	fadd.2d	v0, v0, v1
10000253c: 3cce811d    	ldur	q29, [x8, #0xe8]
100002540: ad4187f0    	ldp	q16, q1, [sp, #0x30]
100002544: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100002548: 4e61d400    	fadd.2d	v0, v0, v1
10000254c: 4fc59281    	fmul.2d	v1, v20, v5[0]
100002550: 4e61d400    	fadd.2d	v0, v0, v1
100002554: 3ccf8101    	ldur	q1, [x8, #0xf8]
100002558: 4fc19210    	fmul.2d	v16, v16, v1[0]
10000255c: 4e70d410    	fadd.2d	v16, v0, v16
100002560: 3dc04100    	ldr	q0, [x8, #0x100]
100002564: 4fc092b1    	fmul.2d	v17, v21, v0[0]
100002568: 4e71d611    	fadd.2d	v17, v16, v17
10000256c: 9104210a    	add	x10, x8, #0x108
100002570: 3dc00150    	ldr	q16, [x10]
100002574: 3dc017f2    	ldr	q18, [sp, #0x50]
100002578: 4fd0924e    	fmul.2d	v14, v18, v16[0]
10000257c: 4e6ed631    	fadd.2d	v17, v17, v14
100002580: 3dc00bf2    	ldr	q18, [sp, #0x20]
100002584: 4fc6924e    	fmul.2d	v14, v18, v6[0]
100002588: ad47d3f3    	ldp	q19, q20, [sp, #0xf0]
10000258c: 4fc7928f    	fmul.2d	v15, v20, v7[0]
100002590: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002594: 4fc292cf    	fmul.2d	v15, v22, v2[0]
100002598: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000259c: 4fc3926f    	fmul.2d	v15, v19, v3[0]
1000025a0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000025a4: 4fc492ef    	fmul.2d	v15, v23, v4[0]
1000025a8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000025ac: 3dc03bf3    	ldr	q19, [sp, #0xe0]
1000025b0: 4fdd926f    	fmul.2d	v15, v19, v29[0]
1000025b4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000025b8: 3dc007f7    	ldr	q23, [sp, #0x10]
1000025bc: 4fc592ef    	fmul.2d	v15, v23, v5[0]
1000025c0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000025c4: 3dc09ff3    	ldr	q19, [sp, #0x270]
1000025c8: 4fc1926f    	fmul.2d	v15, v19, v1[0]
1000025cc: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000025d0: 4fc093cf    	fmul.2d	v15, v30, v0[0]
1000025d4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000025d8: 4fd0936f    	fmul.2d	v15, v27, v16[0]
1000025dc: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000025e0: ad063931    	stp	q17, q14, [x9, #0xc0]
1000025e4: 4fc69391    	fmul.2d	v17, v28, v6[0]
1000025e8: 4fc793ee    	fmul.2d	v14, v31, v7[0]
1000025ec: 4e6ed631    	fadd.2d	v17, v17, v14
1000025f0: 4fc2910e    	fmul.2d	v14, v8, v2[0]
1000025f4: 4e6ed631    	fadd.2d	v17, v17, v14
1000025f8: 4fc3912e    	fmul.2d	v14, v9, v3[0]
1000025fc: 4e6ed631    	fadd.2d	v17, v17, v14
100002600: 4fc4914e    	fmul.2d	v14, v10, v4[0]
100002604: 4e6ed631    	fadd.2d	v17, v17, v14
100002608: 4fdd916e    	fmul.2d	v14, v11, v29[0]
10000260c: 4e6ed631    	fadd.2d	v17, v17, v14
100002610: 4fc5918e    	fmul.2d	v14, v12, v5[0]
100002614: 4e6ed631    	fadd.2d	v17, v17, v14
100002618: 4fc191ae    	fmul.2d	v14, v13, v1[0]
10000261c: 4e6ed631    	fadd.2d	v17, v17, v14
100002620: 4fc0934e    	fmul.2d	v14, v26, v0[0]
100002624: 4e6ed631    	fadd.2d	v17, v17, v14
100002628: ad78cfb4    	ldp	q20, q19, [x29, #-0xf0]
10000262c: 4fd0928e    	fmul.2d	v14, v20, v16[0]
100002630: 4e6ed631    	fadd.2d	v17, v17, v14
100002634: 4fc6926e    	fmul.2d	v14, v19, v6[0]
100002638: ad526bfb    	ldp	q27, q26, [sp, #0x240]
10000263c: 4fc7934f    	fmul.2d	v15, v26, v7[0]
100002640: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002644: 4fc2936f    	fmul.2d	v15, v27, v2[0]
100002648: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000264c: ad5173fe    	ldp	q30, q28, [sp, #0x220]
100002650: 4fc3938f    	fmul.2d	v15, v28, v3[0]
100002654: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002658: 4fc493cf    	fmul.2d	v15, v30, v4[0]
10000265c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002660: 3dc087ff    	ldr	q31, [sp, #0x210]
100002664: 4fdd93ef    	fmul.2d	v15, v31, v29[0]
100002668: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000266c: ad45a3e9    	ldp	q9, q8, [sp, #0xb0]
100002670: 4fc5910f    	fmul.2d	v15, v8, v5[0]
100002674: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002678: 4fc1912f    	fmul.2d	v15, v9, v1[0]
10000267c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002680: ad44abeb    	ldp	q11, q10, [sp, #0x90]
100002684: 4fc0914f    	fmul.2d	v15, v10, v0[0]
100002688: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000268c: 4fd0916f    	fmul.2d	v15, v11, v16[0]
100002690: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002694: ad073931    	stp	q17, q14, [x9, #0xe0]
100002698: ad43b3ed    	ldp	q13, q12, [sp, #0x70]
10000269c: 4fc69191    	fmul.2d	v17, v12, v6[0]
1000026a0: 4fc791ae    	fmul.2d	v14, v13, v7[0]
1000026a4: 4e6ed631    	fadd.2d	v17, v17, v14
1000026a8: 3cd003b3    	ldur	q19, [x29, #-0x100]
1000026ac: 4fc2926e    	fmul.2d	v14, v19, v2[0]
1000026b0: 4e6ed631    	fadd.2d	v17, v17, v14
1000026b4: ad57d3f3    	ldp	q19, q20, [sp, #0x2f0]
1000026b8: 4fc3928e    	fmul.2d	v14, v20, v3[0]
1000026bc: 4e6ed631    	fadd.2d	v17, v17, v14
1000026c0: 4fc4926e    	fmul.2d	v14, v19, v4[0]
1000026c4: 4e6ed631    	fadd.2d	v17, v17, v14
1000026c8: ad56d3f3    	ldp	q19, q20, [sp, #0x2d0]
1000026cc: 4fdd928e    	fmul.2d	v14, v20, v29[0]
1000026d0: 4e6ed631    	fadd.2d	v17, v17, v14
1000026d4: 4fc5926e    	fmul.2d	v14, v19, v5[0]
1000026d8: 4e6ed631    	fadd.2d	v17, v17, v14
1000026dc: 3dc0aff3    	ldr	q19, [sp, #0x2b0]
1000026e0: 4fc1926e    	fmul.2d	v14, v19, v1[0]
1000026e4: 4e6ed631    	fadd.2d	v17, v17, v14
1000026e8: 3dc09bf3    	ldr	q19, [sp, #0x260]
1000026ec: 4fc0926e    	fmul.2d	v14, v19, v0[0]
1000026f0: 4e6ed631    	fadd.2d	v17, v17, v14
1000026f4: 4fd0930e    	fmul.2d	v14, v24, v16[0]
1000026f8: 4e6ed631    	fadd.2d	v17, v17, v14
1000026fc: 3dc047f8    	ldr	q24, [sp, #0x110]
100002700: 4fc69306    	fmul.2d	v6, v24, v6[0]
100002704: 3dc0a7f3    	ldr	q19, [sp, #0x290]
100002708: 4fc79267    	fmul.2d	v7, v19, v7[0]
10000270c: 4e67d4c6    	fadd.2d	v6, v6, v7
100002710: 3dc0a3e7    	ldr	q7, [sp, #0x280]
100002714: 4fc290e2    	fmul.2d	v2, v7, v2[0]
100002718: 4e62d4c2    	fadd.2d	v2, v6, v2
10000271c: 3cda03a6    	ldur	q6, [x29, #-0x60]
100002720: 4fc390c3    	fmul.2d	v3, v6, v3[0]
100002724: 4e63d442    	fadd.2d	v2, v2, v3
100002728: 3cd903a3    	ldur	q3, [x29, #-0x70]
10000272c: 4fc49063    	fmul.2d	v3, v3, v4[0]
100002730: 4e63d442    	fadd.2d	v2, v2, v3
100002734: 3cd803a3    	ldur	q3, [x29, #-0x80]
100002738: 4fdd9063    	fmul.2d	v3, v3, v29[0]
10000273c: 4e63d442    	fadd.2d	v2, v2, v3
100002740: 3cd703a3    	ldur	q3, [x29, #-0x90]
100002744: 4fc59063    	fmul.2d	v3, v3, v5[0]
100002748: 4e63d442    	fadd.2d	v2, v2, v3
10000274c: 3cd603a3    	ldur	q3, [x29, #-0xa0]
100002750: 4fc19061    	fmul.2d	v1, v3, v1[0]
100002754: 4e61d441    	fadd.2d	v1, v2, v1
100002758: 3cd503a2    	ldur	q2, [x29, #-0xb0]
10000275c: 4fc09040    	fmul.2d	v0, v2, v0[0]
100002760: 4e60d420    	fadd.2d	v0, v1, v0
100002764: ad7987a6    	ldp	q6, q1, [x29, #-0xd0]
100002768: 4fd09021    	fmul.2d	v1, v1, v16[0]
10000276c: 4e61d400    	fadd.2d	v0, v0, v1
100002770: ad080131    	stp	q17, q0, [x9, #0x100]
100002774: 9104a10a    	add	x10, x8, #0x128
100002778: 3dc00144    	ldr	q4, [x10]
10000277c: ad49151d    	ldp	q29, q5, [x8, #0x120]
100002780: 3dc0abe0    	ldr	q0, [sp, #0x2a0]
100002784: 4fdd9000    	fmul.2d	v0, v0, v29[0]
100002788: 4fc49321    	fmul.2d	v1, v25, v4[0]
10000278c: 4e61d400    	fadd.2d	v0, v0, v1
100002790: 3dc0b3e1    	ldr	q1, [sp, #0x2c0]
100002794: 4fc59021    	fmul.2d	v1, v1, v5[0]
100002798: 4e61d400    	fadd.2d	v0, v0, v1
10000279c: 9104e10a    	add	x10, x8, #0x138
1000027a0: 3dc00142    	ldr	q2, [x10]
1000027a4: 3dc037f3    	ldr	q19, [sp, #0xd0]
1000027a8: 4fc29261    	fmul.2d	v1, v19, v2[0]
1000027ac: 4e61d400    	fadd.2d	v0, v0, v1
1000027b0: ad4a0d01    	ldp	q1, q3, [x8, #0x140]
1000027b4: 4fc190c6    	fmul.2d	v6, v6, v1[0]
1000027b8: 4e66d406    	fadd.2d	v6, v0, v6
1000027bc: 9105210a    	add	x10, x8, #0x148
1000027c0: 3dc00140    	ldr	q0, [x10]
1000027c4: ad41d3f5    	ldp	q21, q20, [sp, #0x30]
1000027c8: 4fc09287    	fmul.2d	v7, v20, v0[0]
1000027cc: 4e67d4c6    	fadd.2d	v6, v6, v7
1000027d0: 3dc04be7    	ldr	q7, [sp, #0x120]
1000027d4: 4fc390e7    	fmul.2d	v7, v7, v3[0]
1000027d8: 4e67d4c7    	fadd.2d	v7, v6, v7
1000027dc: 9105610a    	add	x10, x8, #0x158
1000027e0: 3dc00146    	ldr	q6, [x10]
1000027e4: 4fc692b0    	fmul.2d	v16, v21, v6[0]
1000027e8: 4e70d4f0    	fadd.2d	v16, v7, v16
1000027ec: 3dc05907    	ldr	q7, [x8, #0x160]
1000027f0: 3dc003f9    	ldr	q25, [sp]
1000027f4: 4fc79331    	fmul.2d	v17, v25, v7[0]
1000027f8: 4e71d611    	fadd.2d	v17, v16, v17
1000027fc: 9105a10a    	add	x10, x8, #0x168
100002800: 3dc00150    	ldr	q16, [x10]
100002804: 3dc017f6    	ldr	q22, [sp, #0x50]
100002808: 4fd092ce    	fmul.2d	v14, v22, v16[0]
10000280c: 4e6ed631    	fadd.2d	v17, v17, v14
100002810: 4fdd924e    	fmul.2d	v14, v18, v29[0]
100002814: 3dc043f2    	ldr	q18, [sp, #0x100]
100002818: 4fc4924f    	fmul.2d	v15, v18, v4[0]
10000281c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002820: 3dc07ff2    	ldr	q18, [sp, #0x1f0]
100002824: 4fc5924f    	fmul.2d	v15, v18, v5[0]
100002828: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000282c: 3dc03ff2    	ldr	q18, [sp, #0xf0]
100002830: 4fc2924f    	fmul.2d	v15, v18, v2[0]
100002834: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002838: 3dc07bf2    	ldr	q18, [sp, #0x1e0]
10000283c: 4fc1924f    	fmul.2d	v15, v18, v1[0]
100002840: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002844: 3dc03bf2    	ldr	q18, [sp, #0xe0]
100002848: 4fc0924f    	fmul.2d	v15, v18, v0[0]
10000284c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002850: 4fc392ef    	fmul.2d	v15, v23, v3[0]
100002854: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002858: 3dc09ff2    	ldr	q18, [sp, #0x270]
10000285c: 4fc6924f    	fmul.2d	v15, v18, v6[0]
100002860: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002864: ad4e5ff2    	ldp	q18, q23, [sp, #0x1c0]
100002868: 4fc792ef    	fmul.2d	v15, v23, v7[0]
10000286c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002870: 4fd0924f    	fmul.2d	v15, v18, v16[0]
100002874: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002878: ad093931    	stp	q17, q14, [x9, #0x120]
10000287c: ad4d47f2    	ldp	q18, q17, [sp, #0x1a0]
100002880: 4fdd9231    	fmul.2d	v17, v17, v29[0]
100002884: 4fc4924e    	fmul.2d	v14, v18, v4[0]
100002888: 4e6ed631    	fadd.2d	v17, v17, v14
10000288c: ad4c5ff2    	ldp	q18, q23, [sp, #0x180]
100002890: 4fc592ee    	fmul.2d	v14, v23, v5[0]
100002894: 4e6ed631    	fadd.2d	v17, v17, v14
100002898: 4fc2924e    	fmul.2d	v14, v18, v2[0]
10000289c: 4e6ed631    	fadd.2d	v17, v17, v14
1000028a0: ad4b5ff2    	ldp	q18, q23, [sp, #0x160]
1000028a4: 4fc192ee    	fmul.2d	v14, v23, v1[0]
1000028a8: 4e6ed631    	fadd.2d	v17, v17, v14
1000028ac: 4fc0924e    	fmul.2d	v14, v18, v0[0]
1000028b0: 4e6ed631    	fadd.2d	v17, v17, v14
1000028b4: 3dc057f2    	ldr	q18, [sp, #0x150]
1000028b8: 4fc3924e    	fmul.2d	v14, v18, v3[0]
1000028bc: 4e6ed631    	fadd.2d	v17, v17, v14
1000028c0: 3dc01bf2    	ldr	q18, [sp, #0x60]
1000028c4: 4fc6924e    	fmul.2d	v14, v18, v6[0]
1000028c8: 4e6ed631    	fadd.2d	v17, v17, v14
1000028cc: 3dc053f2    	ldr	q18, [sp, #0x140]
1000028d0: 4fc7924e    	fmul.2d	v14, v18, v7[0]
1000028d4: 4e6ed631    	fadd.2d	v17, v17, v14
1000028d8: ad78cbb7    	ldp	q23, q18, [x29, #-0xf0]
1000028dc: 4fd092ee    	fmul.2d	v14, v23, v16[0]
1000028e0: 4e6ed631    	fadd.2d	v17, v17, v14
1000028e4: 4fdd924e    	fmul.2d	v14, v18, v29[0]
1000028e8: 4fc4934f    	fmul.2d	v15, v26, v4[0]
1000028ec: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028f0: 4fc5936f    	fmul.2d	v15, v27, v5[0]
1000028f4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028f8: 4fc2938f    	fmul.2d	v15, v28, v2[0]
1000028fc: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002900: 4fc193cf    	fmul.2d	v15, v30, v1[0]
100002904: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002908: 4fc093ef    	fmul.2d	v15, v31, v0[0]
10000290c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002910: 4fc3910f    	fmul.2d	v15, v8, v3[0]
100002914: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002918: 4fc6912f    	fmul.2d	v15, v9, v6[0]
10000291c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002920: 4fc7914f    	fmul.2d	v15, v10, v7[0]
100002924: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002928: 4fd0916f    	fmul.2d	v15, v11, v16[0]
10000292c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002930: ad0a3931    	stp	q17, q14, [x9, #0x140]
100002934: 4fdd9191    	fmul.2d	v17, v12, v29[0]
100002938: 4fc491ae    	fmul.2d	v14, v13, v4[0]
10000293c: 4e6ed631    	fadd.2d	v17, v17, v14
100002940: 3cd003b7    	ldur	q23, [x29, #-0x100]
100002944: 4fc592ee    	fmul.2d	v14, v23, v5[0]
100002948: 4e6ed631    	fadd.2d	v17, v17, v14
10000294c: ad57fffa    	ldp	q26, q31, [sp, #0x2f0]
100002950: 4fc293ee    	fmul.2d	v14, v31, v2[0]
100002954: 4e6ed631    	fadd.2d	v17, v17, v14
100002958: 4fc1934e    	fmul.2d	v14, v26, v1[0]
10000295c: 4e6ed631    	fadd.2d	v17, v17, v14
100002960: ad56effc    	ldp	q28, q27, [sp, #0x2d0]
100002964: 4fc0936e    	fmul.2d	v14, v27, v0[0]
100002968: 4e6ed631    	fadd.2d	v17, v17, v14
10000296c: 4fc3938e    	fmul.2d	v14, v28, v3[0]
100002970: 4e6ed631    	fadd.2d	v17, v17, v14
100002974: 3dc0affe    	ldr	q30, [sp, #0x2b0]
100002978: 4fc693ce    	fmul.2d	v14, v30, v6[0]
10000297c: 4e6ed631    	fadd.2d	v17, v17, v14
100002980: 3dc09bf2    	ldr	q18, [sp, #0x260]
100002984: 4fc7924e    	fmul.2d	v14, v18, v7[0]
100002988: 4e6ed631    	fadd.2d	v17, v17, v14
10000298c: 3dc04ff2    	ldr	q18, [sp, #0x130]
100002990: 4fd0924e    	fmul.2d	v14, v18, v16[0]
100002994: 4e6ed631    	fadd.2d	v17, v17, v14
100002998: 4fdd931d    	fmul.2d	v29, v24, v29[0]
10000299c: ad544bf8    	ldp	q24, q18, [sp, #0x280]
1000029a0: 4fc49244    	fmul.2d	v4, v18, v4[0]
1000029a4: 4e64d7a4    	fadd.2d	v4, v29, v4
1000029a8: 4fc59305    	fmul.2d	v5, v24, v5[0]
1000029ac: 4e65d484    	fadd.2d	v4, v4, v5
1000029b0: 3cda03a5    	ldur	q5, [x29, #-0x60]
1000029b4: 4fc290a2    	fmul.2d	v2, v5, v2[0]
1000029b8: 4e62d482    	fadd.2d	v2, v4, v2
1000029bc: 3cd903a4    	ldur	q4, [x29, #-0x70]
1000029c0: 4fc19081    	fmul.2d	v1, v4, v1[0]
1000029c4: 4e61d441    	fadd.2d	v1, v2, v1
1000029c8: 3cd803a2    	ldur	q2, [x29, #-0x80]
1000029cc: 4fc09040    	fmul.2d	v0, v2, v0[0]
1000029d0: 4e60d420    	fadd.2d	v0, v1, v0
1000029d4: 3cd703a1    	ldur	q1, [x29, #-0x90]
1000029d8: 4fc39021    	fmul.2d	v1, v1, v3[0]
1000029dc: 4e61d400    	fadd.2d	v0, v0, v1
1000029e0: 3cd603a1    	ldur	q1, [x29, #-0xa0]
1000029e4: 4fc69021    	fmul.2d	v1, v1, v6[0]
1000029e8: 4e61d400    	fadd.2d	v0, v0, v1
1000029ec: 3cd503a1    	ldur	q1, [x29, #-0xb0]
1000029f0: 4fc79021    	fmul.2d	v1, v1, v7[0]
1000029f4: 4e61d400    	fadd.2d	v0, v0, v1
1000029f8: ad7987a6    	ldp	q6, q1, [x29, #-0xd0]
1000029fc: 4fd09021    	fmul.2d	v1, v1, v16[0]
100002a00: 4e61d400    	fadd.2d	v0, v0, v1
100002a04: ad0b0131    	stp	q17, q0, [x9, #0x160]
100002a08: 9106210a    	add	x10, x8, #0x188
100002a0c: 3dc00140    	ldr	q0, [x10]
100002a10: ad4c051d    	ldp	q29, q1, [x8, #0x180]
100002a14: 3dc0abe2    	ldr	q2, [sp, #0x2a0]
100002a18: 4fdd9042    	fmul.2d	v2, v2, v29[0]
100002a1c: 3dc083e3    	ldr	q3, [sp, #0x200]
100002a20: 4fc09063    	fmul.2d	v3, v3, v0[0]
100002a24: 4e63d442    	fadd.2d	v2, v2, v3
100002a28: 3dc0b3e3    	ldr	q3, [sp, #0x2c0]
100002a2c: 4fc19063    	fmul.2d	v3, v3, v1[0]
100002a30: 4e63d442    	fadd.2d	v2, v2, v3
100002a34: 9106610a    	add	x10, x8, #0x198
100002a38: 3dc00143    	ldr	q3, [x10]
100002a3c: 4fc39264    	fmul.2d	v4, v19, v3[0]
100002a40: 4e64d445    	fadd.2d	v5, v2, v4
100002a44: ad4d0904    	ldp	q4, q2, [x8, #0x1a0]
100002a48: 4fc490c6    	fmul.2d	v6, v6, v4[0]
100002a4c: 4e66d4a6    	fadd.2d	v6, v5, v6
100002a50: 9106a10a    	add	x10, x8, #0x1a8
100002a54: 3dc00145    	ldr	q5, [x10]
100002a58: 4fc59287    	fmul.2d	v7, v20, v5[0]
100002a5c: 4e67d4c6    	fadd.2d	v6, v6, v7
100002a60: 3dc04bf3    	ldr	q19, [sp, #0x120]
100002a64: 4fc29267    	fmul.2d	v7, v19, v2[0]
100002a68: 4e67d4c7    	fadd.2d	v7, v6, v7
100002a6c: 9106e10a    	add	x10, x8, #0x1b8
100002a70: 3dc00146    	ldr	q6, [x10]
100002a74: 4fc692b0    	fmul.2d	v16, v21, v6[0]
100002a78: 4e70d4f0    	fadd.2d	v16, v7, v16
100002a7c: 3dc07107    	ldr	q7, [x8, #0x1c0]
100002a80: 4fc79331    	fmul.2d	v17, v25, v7[0]
100002a84: 4e71d611    	fadd.2d	v17, v16, v17
100002a88: 9107210a    	add	x10, x8, #0x1c8
100002a8c: 3dc00150    	ldr	q16, [x10]
100002a90: 4fd092ce    	fmul.2d	v14, v22, v16[0]
100002a94: 4e6ed631    	fadd.2d	v17, v17, v14
100002a98: 3dc00bee    	ldr	q14, [sp, #0x20]
100002a9c: 4fdd91ce    	fmul.2d	v14, v14, v29[0]
100002aa0: 3dc043ef    	ldr	q15, [sp, #0x100]
100002aa4: 4fc091ef    	fmul.2d	v15, v15, v0[0]
100002aa8: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002aac: 3dc07fef    	ldr	q15, [sp, #0x1f0]
100002ab0: 4fc191ef    	fmul.2d	v15, v15, v1[0]
100002ab4: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002ab8: 3dc03fef    	ldr	q15, [sp, #0xf0]
100002abc: 4fc391ef    	fmul.2d	v15, v15, v3[0]
100002ac0: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002ac4: 3dc07bef    	ldr	q15, [sp, #0x1e0]
100002ac8: 4fc491ef    	fmul.2d	v15, v15, v4[0]
100002acc: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002ad0: 3dc03bef    	ldr	q15, [sp, #0xe0]
100002ad4: 4fc591ef    	fmul.2d	v15, v15, v5[0]
100002ad8: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002adc: 3dc007ef    	ldr	q15, [sp, #0x10]
100002ae0: 4fc291ef    	fmul.2d	v15, v15, v2[0]
100002ae4: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002ae8: 3dc09fef    	ldr	q15, [sp, #0x270]
100002aec: 4fc691ef    	fmul.2d	v15, v15, v6[0]
100002af0: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002af4: 3dc077ef    	ldr	q15, [sp, #0x1d0]
100002af8: 4fc791ef    	fmul.2d	v15, v15, v7[0]
100002afc: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b00: 3dc073ef    	ldr	q15, [sp, #0x1c0]
100002b04: 4fd091ef    	fmul.2d	v15, v15, v16[0]
100002b08: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b0c: ad0c3931    	stp	q17, q14, [x9, #0x180]
100002b10: ad4d47ee    	ldp	q14, q17, [sp, #0x1a0]
100002b14: 4fdd9231    	fmul.2d	v17, v17, v29[0]
100002b18: 4fc091ce    	fmul.2d	v14, v14, v0[0]
100002b1c: 4e6ed631    	fadd.2d	v17, v17, v14
100002b20: 3dc067ee    	ldr	q14, [sp, #0x190]
100002b24: 4fc191ce    	fmul.2d	v14, v14, v1[0]
100002b28: 4e6ed631    	fadd.2d	v17, v17, v14
100002b2c: 3dc063ee    	ldr	q14, [sp, #0x180]
100002b30: 4fc391ce    	fmul.2d	v14, v14, v3[0]
100002b34: 4e6ed631    	fadd.2d	v17, v17, v14
100002b38: 3dc05fee    	ldr	q14, [sp, #0x170]
100002b3c: 4fc491ce    	fmul.2d	v14, v14, v4[0]
100002b40: 4e6ed631    	fadd.2d	v17, v17, v14
100002b44: 3dc05bee    	ldr	q14, [sp, #0x160]
100002b48: 4fc591ce    	fmul.2d	v14, v14, v5[0]
100002b4c: 4e6ed631    	fadd.2d	v17, v17, v14
100002b50: 3dc057ee    	ldr	q14, [sp, #0x150]
100002b54: 4fc291ce    	fmul.2d	v14, v14, v2[0]
100002b58: 4e6ed631    	fadd.2d	v17, v17, v14
100002b5c: 3dc01bee    	ldr	q14, [sp, #0x60]
100002b60: 4fc691ce    	fmul.2d	v14, v14, v6[0]
100002b64: 4e6ed631    	fadd.2d	v17, v17, v14
100002b68: 3dc053ee    	ldr	q14, [sp, #0x140]
100002b6c: 4fc791ce    	fmul.2d	v14, v14, v7[0]
100002b70: 4e6ed631    	fadd.2d	v17, v17, v14
100002b74: 3cd103ae    	ldur	q14, [x29, #-0xf0]
100002b78: 4fd091ce    	fmul.2d	v14, v14, v16[0]
100002b7c: 4e6ed631    	fadd.2d	v17, v17, v14
100002b80: 3cd203ae    	ldur	q14, [x29, #-0xe0]
100002b84: 4fdd91ce    	fmul.2d	v14, v14, v29[0]
100002b88: 3dc097ef    	ldr	q15, [sp, #0x250]
100002b8c: 4fc091ef    	fmul.2d	v15, v15, v0[0]
100002b90: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b94: 3dc093ef    	ldr	q15, [sp, #0x240]
100002b98: 4fc191ef    	fmul.2d	v15, v15, v1[0]
100002b9c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002ba0: 3dc08fef    	ldr	q15, [sp, #0x230]
100002ba4: 4fc391ef    	fmul.2d	v15, v15, v3[0]
100002ba8: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002bac: 3dc08bef    	ldr	q15, [sp, #0x220]
100002bb0: 4fc491ef    	fmul.2d	v15, v15, v4[0]
100002bb4: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002bb8: 3dc087ef    	ldr	q15, [sp, #0x210]
100002bbc: 4fc591ef    	fmul.2d	v15, v15, v5[0]
100002bc0: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002bc4: 4fc2910f    	fmul.2d	v15, v8, v2[0]
100002bc8: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002bcc: 4fc6912f    	fmul.2d	v15, v9, v6[0]
100002bd0: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002bd4: 4fc7914f    	fmul.2d	v15, v10, v7[0]
100002bd8: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002bdc: 4fd0916f    	fmul.2d	v15, v11, v16[0]
100002be0: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002be4: ad0d3931    	stp	q17, q14, [x9, #0x1a0]
100002be8: 4fdd9191    	fmul.2d	v17, v12, v29[0]
100002bec: 4fc091ad    	fmul.2d	v13, v13, v0[0]
100002bf0: 4e6dd631    	fadd.2d	v17, v17, v13
100002bf4: 4fc192ec    	fmul.2d	v12, v23, v1[0]
100002bf8: 4e6cd631    	fadd.2d	v17, v17, v12
100002bfc: 4fc393eb    	fmul.2d	v11, v31, v3[0]
100002c00: 4e6bd631    	fadd.2d	v17, v17, v11
100002c04: 4fc4934a    	fmul.2d	v10, v26, v4[0]
100002c08: 4e6ad631    	fadd.2d	v17, v17, v10
100002c0c: 4fc59369    	fmul.2d	v9, v27, v5[0]
100002c10: 4e69d631    	fadd.2d	v17, v17, v9
100002c14: 4fc29388    	fmul.2d	v8, v28, v2[0]
100002c18: 4e68d631    	fadd.2d	v17, v17, v8
100002c1c: 4fc693df    	fmul.2d	v31, v30, v6[0]
100002c20: 4e7fd631    	fadd.2d	v17, v17, v31
100002c24: 3dc09bf7    	ldr	q23, [sp, #0x260]
100002c28: 4fc792fe    	fmul.2d	v30, v23, v7[0]
100002c2c: 4e7ed631    	fadd.2d	v17, v17, v30
100002c30: 3dc04ff7    	ldr	q23, [sp, #0x130]
100002c34: 4fd092fc    	fmul.2d	v28, v23, v16[0]
100002c38: 4e7cd631    	fadd.2d	v17, v17, v28
100002c3c: 3dc047f7    	ldr	q23, [sp, #0x110]
100002c40: 4fdd92fb    	fmul.2d	v27, v23, v29[0]
100002c44: 4fc09240    	fmul.2d	v0, v18, v0[0]
100002c48: 4e60d760    	fadd.2d	v0, v27, v0
100002c4c: 4fc19301    	fmul.2d	v1, v24, v1[0]
100002c50: 4e61d400    	fadd.2d	v0, v0, v1
100002c54: 3cda03a1    	ldur	q1, [x29, #-0x60]
100002c58: 4fc39021    	fmul.2d	v1, v1, v3[0]
100002c5c: 4e61d400    	fadd.2d	v0, v0, v1
100002c60: 3cd903a1    	ldur	q1, [x29, #-0x70]
100002c64: 4fc49021    	fmul.2d	v1, v1, v4[0]
100002c68: 4e61d400    	fadd.2d	v0, v0, v1
100002c6c: 3cd803a1    	ldur	q1, [x29, #-0x80]
100002c70: 4fc59021    	fmul.2d	v1, v1, v5[0]
100002c74: 4e61d400    	fadd.2d	v0, v0, v1
100002c78: 3cd703a1    	ldur	q1, [x29, #-0x90]
100002c7c: 4fc29021    	fmul.2d	v1, v1, v2[0]
100002c80: 4e61d400    	fadd.2d	v0, v0, v1
100002c84: 3cd603a1    	ldur	q1, [x29, #-0xa0]
100002c88: 4fc69021    	fmul.2d	v1, v1, v6[0]
100002c8c: 4e61d400    	fadd.2d	v0, v0, v1
100002c90: 3cd503a1    	ldur	q1, [x29, #-0xb0]
100002c94: 4fc79021    	fmul.2d	v1, v1, v7[0]
100002c98: 4e61d400    	fadd.2d	v0, v0, v1
100002c9c: 3cd403a1    	ldur	q1, [x29, #-0xc0]
100002ca0: 4fd09021    	fmul.2d	v1, v1, v16[0]
100002ca4: 4e61d400    	fadd.2d	v0, v0, v1
100002ca8: ad0e0131    	stp	q17, q0, [x9, #0x1c0]
100002cac: 9107a10a    	add	x10, x8, #0x1e8
100002cb0: 3dc00141    	ldr	q1, [x10]
100002cb4: ad4f0102    	ldp	q2, q0, [x8, #0x1e0]
100002cb8: 9107e10a    	add	x10, x8, #0x1f8
100002cbc: 3dc0abe3    	ldr	q3, [sp, #0x2a0]
100002cc0: 4fc29063    	fmul.2d	v3, v3, v2[0]
100002cc4: 3dc083e4    	ldr	q4, [sp, #0x200]
100002cc8: 4fc19084    	fmul.2d	v4, v4, v1[0]
100002ccc: 4e64d463    	fadd.2d	v3, v3, v4
100002cd0: 3dc00146    	ldr	q6, [x10]
100002cd4: 9108210a    	add	x10, x8, #0x208
100002cd8: 3dc0b3e4    	ldr	q4, [sp, #0x2c0]
100002cdc: 4fc09084    	fmul.2d	v4, v4, v0[0]
100002ce0: 4e64d463    	fadd.2d	v3, v3, v4
100002ce4: 3dc037e4    	ldr	q4, [sp, #0xd0]
100002ce8: 4fc69084    	fmul.2d	v4, v4, v6[0]
100002cec: 4e64d463    	fadd.2d	v3, v3, v4
100002cf0: ad501110    	ldp	q16, q4, [x8, #0x200]
100002cf4: 3cd303a5    	ldur	q5, [x29, #-0xd0]
100002cf8: 4fd090a5    	fmul.2d	v5, v5, v16[0]
100002cfc: 4e65d463    	fadd.2d	v3, v3, v5
100002d00: 3dc00151    	ldr	q17, [x10]
100002d04: 9108610a    	add	x10, x8, #0x218
100002d08: 4fd19285    	fmul.2d	v5, v20, v17[0]
100002d0c: 4e65d463    	fadd.2d	v3, v3, v5
100002d10: 3dc00147    	ldr	q7, [x10]
100002d14: 4fc49265    	fmul.2d	v5, v19, v4[0]
100002d18: 4e65d465    	fadd.2d	v5, v3, v5
100002d1c: 3dc08903    	ldr	q3, [x8, #0x220]
100002d20: 9108a10a    	add	x10, x8, #0x228
100002d24: 4fc792b2    	fmul.2d	v18, v21, v7[0]
100002d28: 4e72d4b2    	fadd.2d	v18, v5, v18
100002d2c: 3dc00145    	ldr	q5, [x10]
100002d30: 4fc39333    	fmul.2d	v19, v25, v3[0]
100002d34: 4e73d652    	fadd.2d	v18, v18, v19
100002d38: 4fc592d3    	fmul.2d	v19, v22, v5[0]
100002d3c: 4e73d652    	fadd.2d	v18, v18, v19
100002d40: 3dc12513    	ldr	q19, [x8, #0x490]
100002d44: 4fc29273    	fmul.2d	v19, v19, v2[0]
100002d48: 3dc13d14    	ldr	q20, [x8, #0x4f0]
100002d4c: 4fc19294    	fmul.2d	v20, v20, v1[0]
100002d50: 4e74d673    	fadd.2d	v19, v19, v20
100002d54: 3dc15514    	ldr	q20, [x8, #0x550]
100002d58: 4fc09294    	fmul.2d	v20, v20, v0[0]
100002d5c: 4e74d673    	fadd.2d	v19, v19, v20
100002d60: 3dc16d14    	ldr	q20, [x8, #0x5b0]
100002d64: 4fc69294    	fmul.2d	v20, v20, v6[0]
100002d68: 4e74d673    	fadd.2d	v19, v19, v20
100002d6c: 3dc18514    	ldr	q20, [x8, #0x610]
100002d70: 4fd09294    	fmul.2d	v20, v20, v16[0]
100002d74: 4e74d673    	fadd.2d	v19, v19, v20
100002d78: 3dc19d14    	ldr	q20, [x8, #0x670]
100002d7c: 4fd19294    	fmul.2d	v20, v20, v17[0]
100002d80: 4e74d673    	fadd.2d	v19, v19, v20
100002d84: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100002d88: 4fc49294    	fmul.2d	v20, v20, v4[0]
100002d8c: 4e74d673    	fadd.2d	v19, v19, v20
100002d90: 3dc1cd14    	ldr	q20, [x8, #0x730]
100002d94: 4fc79294    	fmul.2d	v20, v20, v7[0]
100002d98: 4e74d673    	fadd.2d	v19, v19, v20
100002d9c: 3dc1e514    	ldr	q20, [x8, #0x790]
100002da0: 4fc39294    	fmul.2d	v20, v20, v3[0]
100002da4: 4e74d673    	fadd.2d	v19, v19, v20
100002da8: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
100002dac: 4fc59294    	fmul.2d	v20, v20, v5[0]
100002db0: 4e74d673    	fadd.2d	v19, v19, v20
100002db4: ad0f4d32    	stp	q18, q19, [x9, #0x1e0]
100002db8: 3dc12912    	ldr	q18, [x8, #0x4a0]
100002dbc: 4fc29252    	fmul.2d	v18, v18, v2[0]
100002dc0: 3dc14113    	ldr	q19, [x8, #0x500]
100002dc4: 4fc19273    	fmul.2d	v19, v19, v1[0]
100002dc8: 4e73d652    	fadd.2d	v18, v18, v19
100002dcc: 3dc15913    	ldr	q19, [x8, #0x560]
100002dd0: 4fc09273    	fmul.2d	v19, v19, v0[0]
100002dd4: 4e73d652    	fadd.2d	v18, v18, v19
100002dd8: 3dc17113    	ldr	q19, [x8, #0x5c0]
100002ddc: 4fc69273    	fmul.2d	v19, v19, v6[0]
100002de0: 4e73d652    	fadd.2d	v18, v18, v19
100002de4: 3dc18913    	ldr	q19, [x8, #0x620]
100002de8: 4fd09273    	fmul.2d	v19, v19, v16[0]
100002dec: 4e73d652    	fadd.2d	v18, v18, v19
100002df0: 3dc1a113    	ldr	q19, [x8, #0x680]
100002df4: 4fd19273    	fmul.2d	v19, v19, v17[0]
100002df8: 4e73d652    	fadd.2d	v18, v18, v19
100002dfc: 3dc1b913    	ldr	q19, [x8, #0x6e0]
100002e00: 4fc49273    	fmul.2d	v19, v19, v4[0]
100002e04: 4e73d652    	fadd.2d	v18, v18, v19
100002e08: 3dc1d113    	ldr	q19, [x8, #0x740]
100002e0c: 4fc79273    	fmul.2d	v19, v19, v7[0]
100002e10: 4e73d652    	fadd.2d	v18, v18, v19
100002e14: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100002e18: 4fc39273    	fmul.2d	v19, v19, v3[0]
100002e1c: 4e73d652    	fadd.2d	v18, v18, v19
100002e20: 3dc20113    	ldr	q19, [x8, #0x800]
100002e24: 4fc59273    	fmul.2d	v19, v19, v5[0]
100002e28: 4e73d652    	fadd.2d	v18, v18, v19
100002e2c: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100002e30: 4fc29273    	fmul.2d	v19, v19, v2[0]
100002e34: 3dc14514    	ldr	q20, [x8, #0x510]
100002e38: 4fc19294    	fmul.2d	v20, v20, v1[0]
100002e3c: 4e74d673    	fadd.2d	v19, v19, v20
100002e40: 3dc15d14    	ldr	q20, [x8, #0x570]
100002e44: 4fc09294    	fmul.2d	v20, v20, v0[0]
100002e48: 4e74d673    	fadd.2d	v19, v19, v20
100002e4c: 3dc17514    	ldr	q20, [x8, #0x5d0]
100002e50: 4fc69294    	fmul.2d	v20, v20, v6[0]
100002e54: 4e74d673    	fadd.2d	v19, v19, v20
100002e58: 3dc18d14    	ldr	q20, [x8, #0x630]
100002e5c: 4fd09294    	fmul.2d	v20, v20, v16[0]
100002e60: 4e74d673    	fadd.2d	v19, v19, v20
100002e64: 3dc1a514    	ldr	q20, [x8, #0x690]
100002e68: 4fd19294    	fmul.2d	v20, v20, v17[0]
100002e6c: 4e74d673    	fadd.2d	v19, v19, v20
100002e70: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
100002e74: 4fc49294    	fmul.2d	v20, v20, v4[0]
100002e78: 4e74d673    	fadd.2d	v19, v19, v20
100002e7c: 3dc1d514    	ldr	q20, [x8, #0x750]
100002e80: 4fc79294    	fmul.2d	v20, v20, v7[0]
100002e84: 4e74d673    	fadd.2d	v19, v19, v20
100002e88: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
100002e8c: 4fc39294    	fmul.2d	v20, v20, v3[0]
100002e90: 4e74d673    	fadd.2d	v19, v19, v20
100002e94: 3dc20514    	ldr	q20, [x8, #0x810]
100002e98: 4fc59294    	fmul.2d	v20, v20, v5[0]
100002e9c: 4e74d673    	fadd.2d	v19, v19, v20
100002ea0: ad104d32    	stp	q18, q19, [x9, #0x200]
100002ea4: 3dc13112    	ldr	q18, [x8, #0x4c0]
100002ea8: 4fc29252    	fmul.2d	v18, v18, v2[0]
100002eac: 3dc14913    	ldr	q19, [x8, #0x520]
100002eb0: 4fc19273    	fmul.2d	v19, v19, v1[0]
100002eb4: 4e73d652    	fadd.2d	v18, v18, v19
100002eb8: 3dc16113    	ldr	q19, [x8, #0x580]
100002ebc: 4fc09273    	fmul.2d	v19, v19, v0[0]
100002ec0: 4e73d652    	fadd.2d	v18, v18, v19
100002ec4: 3dc17913    	ldr	q19, [x8, #0x5e0]
100002ec8: 4fc69273    	fmul.2d	v19, v19, v6[0]
100002ecc: 4e73d652    	fadd.2d	v18, v18, v19
100002ed0: 3dc19113    	ldr	q19, [x8, #0x640]
100002ed4: 4fd09273    	fmul.2d	v19, v19, v16[0]
100002ed8: 4e73d652    	fadd.2d	v18, v18, v19
100002edc: 3dc1a913    	ldr	q19, [x8, #0x6a0]
100002ee0: 4fd19273    	fmul.2d	v19, v19, v17[0]
100002ee4: 4e73d652    	fadd.2d	v18, v18, v19
100002ee8: 3dc1c113    	ldr	q19, [x8, #0x700]
100002eec: 4fc49273    	fmul.2d	v19, v19, v4[0]
100002ef0: 4e73d652    	fadd.2d	v18, v18, v19
100002ef4: 3dc1d913    	ldr	q19, [x8, #0x760]
100002ef8: 4fc79273    	fmul.2d	v19, v19, v7[0]
100002efc: 4e73d652    	fadd.2d	v18, v18, v19
100002f00: 3dc1f113    	ldr	q19, [x8, #0x7c0]
100002f04: 4fc39273    	fmul.2d	v19, v19, v3[0]
100002f08: 4e73d652    	fadd.2d	v18, v18, v19
100002f0c: 3dc20913    	ldr	q19, [x8, #0x820]
100002f10: 4fc59273    	fmul.2d	v19, v19, v5[0]
100002f14: 4e73d652    	fadd.2d	v18, v18, v19
100002f18: 3dc13513    	ldr	q19, [x8, #0x4d0]
100002f1c: 4fc29262    	fmul.2d	v2, v19, v2[0]
100002f20: 3dc14d13    	ldr	q19, [x8, #0x530]
100002f24: 4fc19261    	fmul.2d	v1, v19, v1[0]
100002f28: 4e61d441    	fadd.2d	v1, v2, v1
100002f2c: 3dc16502    	ldr	q2, [x8, #0x590]
100002f30: 4fc09040    	fmul.2d	v0, v2, v0[0]
100002f34: 4e60d420    	fadd.2d	v0, v1, v0
100002f38: 3dc17d01    	ldr	q1, [x8, #0x5f0]
100002f3c: 4fc69021    	fmul.2d	v1, v1, v6[0]
100002f40: 4e61d400    	fadd.2d	v0, v0, v1
100002f44: 3dc19501    	ldr	q1, [x8, #0x650]
100002f48: 4fd09021    	fmul.2d	v1, v1, v16[0]
100002f4c: 4e61d400    	fadd.2d	v0, v0, v1
100002f50: 3dc1ad01    	ldr	q1, [x8, #0x6b0]
100002f54: 4fd19021    	fmul.2d	v1, v1, v17[0]
100002f58: 4e61d400    	fadd.2d	v0, v0, v1
100002f5c: 3dc1c501    	ldr	q1, [x8, #0x710]
100002f60: 4fc49021    	fmul.2d	v1, v1, v4[0]
100002f64: 3dc1dd02    	ldr	q2, [x8, #0x770]
100002f68: 4e61d400    	fadd.2d	v0, v0, v1
100002f6c: 4fc79041    	fmul.2d	v1, v2, v7[0]
100002f70: 3dc1f502    	ldr	q2, [x8, #0x7d0]
100002f74: 4e61d400    	fadd.2d	v0, v0, v1
100002f78: 3dc20d01    	ldr	q1, [x8, #0x830]
100002f7c: 4fc39042    	fmul.2d	v2, v2, v3[0]
100002f80: 4e62d400    	fadd.2d	v0, v0, v2
100002f84: 4fc59021    	fmul.2d	v1, v1, v5[0]
100002f88: 4e61d400    	fadd.2d	v0, v0, v1
100002f8c: ad110132    	stp	q18, q0, [x9, #0x220]
100002f90: 9109210a    	add	x10, x8, #0x248
100002f94: 3dc00150    	ldr	q16, [x10]
100002f98: ad521911    	ldp	q17, q6, [x8, #0x240]
100002f9c: 9109610a    	add	x10, x8, #0x258
100002fa0: 3dc00145    	ldr	q5, [x10]
100002fa4: 9109a10a    	add	x10, x8, #0x268
100002fa8: 3dc00144    	ldr	q4, [x10]
100002fac: ad530d07    	ldp	q7, q3, [x8, #0x260]
100002fb0: 9109e10a    	add	x10, x8, #0x278
100002fb4: 3dc00142    	ldr	q2, [x10]
100002fb8: 3dc0a100    	ldr	q0, [x8, #0x280]
100002fbc: 910a210a    	add	x10, x8, #0x288
100002fc0: 3dc00141    	ldr	q1, [x10]
100002fc4: 3dc12112    	ldr	q18, [x8, #0x480]
100002fc8: 4fd19252    	fmul.2d	v18, v18, v17[0]
100002fcc: 3dc13913    	ldr	q19, [x8, #0x4e0]
100002fd0: 4fd09273    	fmul.2d	v19, v19, v16[0]
100002fd4: 4e73d652    	fadd.2d	v18, v18, v19
100002fd8: 3dc15113    	ldr	q19, [x8, #0x540]
100002fdc: 4fc69273    	fmul.2d	v19, v19, v6[0]
100002fe0: 4e73d652    	fadd.2d	v18, v18, v19
100002fe4: 3dc16913    	ldr	q19, [x8, #0x5a0]
100002fe8: 4fc59273    	fmul.2d	v19, v19, v5[0]
100002fec: 4e73d652    	fadd.2d	v18, v18, v19
100002ff0: 3dc18113    	ldr	q19, [x8, #0x600]
100002ff4: 4fc79273    	fmul.2d	v19, v19, v7[0]
100002ff8: 4e73d652    	fadd.2d	v18, v18, v19
100002ffc: 3dc19913    	ldr	q19, [x8, #0x660]
100003000: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003004: 4e73d652    	fadd.2d	v18, v18, v19
100003008: 3dc1b113    	ldr	q19, [x8, #0x6c0]
10000300c: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003010: 4e73d652    	fadd.2d	v18, v18, v19
100003014: 3dc1c913    	ldr	q19, [x8, #0x720]
100003018: 4fc29273    	fmul.2d	v19, v19, v2[0]
10000301c: 4e73d652    	fadd.2d	v18, v18, v19
100003020: 3dc1e113    	ldr	q19, [x8, #0x780]
100003024: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003028: 4e73d652    	fadd.2d	v18, v18, v19
10000302c: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003030: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003034: 4e73d652    	fadd.2d	v18, v18, v19
100003038: 3dc12513    	ldr	q19, [x8, #0x490]
10000303c: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003040: 3dc13d14    	ldr	q20, [x8, #0x4f0]
100003044: 4fd09294    	fmul.2d	v20, v20, v16[0]
100003048: 4e74d673    	fadd.2d	v19, v19, v20
10000304c: 3dc15514    	ldr	q20, [x8, #0x550]
100003050: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003054: 4e74d673    	fadd.2d	v19, v19, v20
100003058: 3dc16d14    	ldr	q20, [x8, #0x5b0]
10000305c: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003060: 4e74d673    	fadd.2d	v19, v19, v20
100003064: 3dc18514    	ldr	q20, [x8, #0x610]
100003068: 4fc79294    	fmul.2d	v20, v20, v7[0]
10000306c: 4e74d673    	fadd.2d	v19, v19, v20
100003070: 3dc19d14    	ldr	q20, [x8, #0x670]
100003074: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003078: 4e74d673    	fadd.2d	v19, v19, v20
10000307c: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100003080: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003084: 4e74d673    	fadd.2d	v19, v19, v20
100003088: 3dc1cd14    	ldr	q20, [x8, #0x730]
10000308c: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003090: 4e74d673    	fadd.2d	v19, v19, v20
100003094: 3dc1e514    	ldr	q20, [x8, #0x790]
100003098: 4fc09294    	fmul.2d	v20, v20, v0[0]
10000309c: 4e74d673    	fadd.2d	v19, v19, v20
1000030a0: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
1000030a4: 4fc19294    	fmul.2d	v20, v20, v1[0]
1000030a8: 4e74d673    	fadd.2d	v19, v19, v20
1000030ac: ad124d32    	stp	q18, q19, [x9, #0x240]
1000030b0: 3dc12912    	ldr	q18, [x8, #0x4a0]
1000030b4: 4fd19252    	fmul.2d	v18, v18, v17[0]
1000030b8: 3dc14113    	ldr	q19, [x8, #0x500]
1000030bc: 4fd09273    	fmul.2d	v19, v19, v16[0]
1000030c0: 4e73d652    	fadd.2d	v18, v18, v19
1000030c4: 3dc15913    	ldr	q19, [x8, #0x560]
1000030c8: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000030cc: 4e73d652    	fadd.2d	v18, v18, v19
1000030d0: 3dc17113    	ldr	q19, [x8, #0x5c0]
1000030d4: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000030d8: 4e73d652    	fadd.2d	v18, v18, v19
1000030dc: 3dc18913    	ldr	q19, [x8, #0x620]
1000030e0: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000030e4: 4e73d652    	fadd.2d	v18, v18, v19
1000030e8: 3dc1a113    	ldr	q19, [x8, #0x680]
1000030ec: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000030f0: 4e73d652    	fadd.2d	v18, v18, v19
1000030f4: 3dc1b913    	ldr	q19, [x8, #0x6e0]
1000030f8: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000030fc: 4e73d652    	fadd.2d	v18, v18, v19
100003100: 3dc1d113    	ldr	q19, [x8, #0x740]
100003104: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003108: 4e73d652    	fadd.2d	v18, v18, v19
10000310c: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003110: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003114: 4e73d652    	fadd.2d	v18, v18, v19
100003118: 3dc20113    	ldr	q19, [x8, #0x800]
10000311c: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003120: 4e73d652    	fadd.2d	v18, v18, v19
100003124: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003128: 4fd19273    	fmul.2d	v19, v19, v17[0]
10000312c: 3dc14514    	ldr	q20, [x8, #0x510]
100003130: 4fd09294    	fmul.2d	v20, v20, v16[0]
100003134: 4e74d673    	fadd.2d	v19, v19, v20
100003138: 3dc15d14    	ldr	q20, [x8, #0x570]
10000313c: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003140: 4e74d673    	fadd.2d	v19, v19, v20
100003144: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003148: 4fc59294    	fmul.2d	v20, v20, v5[0]
10000314c: 4e74d673    	fadd.2d	v19, v19, v20
100003150: 3dc18d14    	ldr	q20, [x8, #0x630]
100003154: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003158: 4e74d673    	fadd.2d	v19, v19, v20
10000315c: 3dc1a514    	ldr	q20, [x8, #0x690]
100003160: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003164: 4e74d673    	fadd.2d	v19, v19, v20
100003168: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
10000316c: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003170: 4e74d673    	fadd.2d	v19, v19, v20
100003174: 3dc1d514    	ldr	q20, [x8, #0x750]
100003178: 4fc29294    	fmul.2d	v20, v20, v2[0]
10000317c: 4e74d673    	fadd.2d	v19, v19, v20
100003180: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
100003184: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003188: 4e74d673    	fadd.2d	v19, v19, v20
10000318c: 3dc20514    	ldr	q20, [x8, #0x810]
100003190: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003194: 4e74d673    	fadd.2d	v19, v19, v20
100003198: ad134d32    	stp	q18, q19, [x9, #0x260]
10000319c: 3dc13112    	ldr	q18, [x8, #0x4c0]
1000031a0: 4fd19252    	fmul.2d	v18, v18, v17[0]
1000031a4: 3dc14913    	ldr	q19, [x8, #0x520]
1000031a8: 4fd09273    	fmul.2d	v19, v19, v16[0]
1000031ac: 4e73d652    	fadd.2d	v18, v18, v19
1000031b0: 3dc16113    	ldr	q19, [x8, #0x580]
1000031b4: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000031b8: 4e73d652    	fadd.2d	v18, v18, v19
1000031bc: 3dc17913    	ldr	q19, [x8, #0x5e0]
1000031c0: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000031c4: 4e73d652    	fadd.2d	v18, v18, v19
1000031c8: 3dc19113    	ldr	q19, [x8, #0x640]
1000031cc: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000031d0: 4e73d652    	fadd.2d	v18, v18, v19
1000031d4: 3dc1a913    	ldr	q19, [x8, #0x6a0]
1000031d8: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000031dc: 4e73d652    	fadd.2d	v18, v18, v19
1000031e0: 3dc1c113    	ldr	q19, [x8, #0x700]
1000031e4: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000031e8: 4e73d652    	fadd.2d	v18, v18, v19
1000031ec: 3dc1d913    	ldr	q19, [x8, #0x760]
1000031f0: 4fc29273    	fmul.2d	v19, v19, v2[0]
1000031f4: 4e73d652    	fadd.2d	v18, v18, v19
1000031f8: 3dc1f113    	ldr	q19, [x8, #0x7c0]
1000031fc: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003200: 4e73d652    	fadd.2d	v18, v18, v19
100003204: 3dc20913    	ldr	q19, [x8, #0x820]
100003208: 4fc19273    	fmul.2d	v19, v19, v1[0]
10000320c: 4e73d652    	fadd.2d	v18, v18, v19
100003210: 3dc13513    	ldr	q19, [x8, #0x4d0]
100003214: 4fd19271    	fmul.2d	v17, v19, v17[0]
100003218: 3dc14d13    	ldr	q19, [x8, #0x530]
10000321c: 4fd09270    	fmul.2d	v16, v19, v16[0]
100003220: 4e70d630    	fadd.2d	v16, v17, v16
100003224: 3dc16511    	ldr	q17, [x8, #0x590]
100003228: 4fc69226    	fmul.2d	v6, v17, v6[0]
10000322c: 4e66d606    	fadd.2d	v6, v16, v6
100003230: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100003234: 4fc59205    	fmul.2d	v5, v16, v5[0]
100003238: 4e65d4c5    	fadd.2d	v5, v6, v5
10000323c: 3dc19506    	ldr	q6, [x8, #0x650]
100003240: 4fc790c6    	fmul.2d	v6, v6, v7[0]
100003244: 4e66d4a5    	fadd.2d	v5, v5, v6
100003248: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
10000324c: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100003250: 4e64d4a4    	fadd.2d	v4, v5, v4
100003254: 3dc1c505    	ldr	q5, [x8, #0x710]
100003258: 4fc390a3    	fmul.2d	v3, v5, v3[0]
10000325c: 3dc1dd05    	ldr	q5, [x8, #0x770]
100003260: 4e63d483    	fadd.2d	v3, v4, v3
100003264: 4fc290a2    	fmul.2d	v2, v5, v2[0]
100003268: 3dc1f504    	ldr	q4, [x8, #0x7d0]
10000326c: 4e62d462    	fadd.2d	v2, v3, v2
100003270: 3dc20d03    	ldr	q3, [x8, #0x830]
100003274: 4fc09080    	fmul.2d	v0, v4, v0[0]
100003278: 4e60d440    	fadd.2d	v0, v2, v0
10000327c: 4fc19061    	fmul.2d	v1, v3, v1[0]
100003280: 4e61d400    	fadd.2d	v0, v0, v1
100003284: ad140132    	stp	q18, q0, [x9, #0x280]
100003288: 910aa10a    	add	x10, x8, #0x2a8
10000328c: 3dc00150    	ldr	q16, [x10]
100003290: ad551911    	ldp	q17, q6, [x8, #0x2a0]
100003294: 910ae10a    	add	x10, x8, #0x2b8
100003298: 3dc00145    	ldr	q5, [x10]
10000329c: 910b210a    	add	x10, x8, #0x2c8
1000032a0: 3dc00144    	ldr	q4, [x10]
1000032a4: ad560d07    	ldp	q7, q3, [x8, #0x2c0]
1000032a8: 910b610a    	add	x10, x8, #0x2d8
1000032ac: 3dc00142    	ldr	q2, [x10]
1000032b0: 3dc0b900    	ldr	q0, [x8, #0x2e0]
1000032b4: 910ba10a    	add	x10, x8, #0x2e8
1000032b8: 3dc00141    	ldr	q1, [x10]
1000032bc: 3dc12112    	ldr	q18, [x8, #0x480]
1000032c0: 4fd19252    	fmul.2d	v18, v18, v17[0]
1000032c4: 3dc13913    	ldr	q19, [x8, #0x4e0]
1000032c8: 4fd09273    	fmul.2d	v19, v19, v16[0]
1000032cc: 4e73d652    	fadd.2d	v18, v18, v19
1000032d0: 3dc15113    	ldr	q19, [x8, #0x540]
1000032d4: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000032d8: 4e73d652    	fadd.2d	v18, v18, v19
1000032dc: 3dc16913    	ldr	q19, [x8, #0x5a0]
1000032e0: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000032e4: 4e73d652    	fadd.2d	v18, v18, v19
1000032e8: 3dc18113    	ldr	q19, [x8, #0x600]
1000032ec: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000032f0: 4e73d652    	fadd.2d	v18, v18, v19
1000032f4: 3dc19913    	ldr	q19, [x8, #0x660]
1000032f8: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000032fc: 4e73d652    	fadd.2d	v18, v18, v19
100003300: 3dc1b113    	ldr	q19, [x8, #0x6c0]
100003304: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003308: 4e73d652    	fadd.2d	v18, v18, v19
10000330c: 3dc1c913    	ldr	q19, [x8, #0x720]
100003310: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003314: 4e73d652    	fadd.2d	v18, v18, v19
100003318: 3dc1e113    	ldr	q19, [x8, #0x780]
10000331c: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003320: 4e73d652    	fadd.2d	v18, v18, v19
100003324: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003328: 4fc19273    	fmul.2d	v19, v19, v1[0]
10000332c: 4e73d652    	fadd.2d	v18, v18, v19
100003330: 3dc12513    	ldr	q19, [x8, #0x490]
100003334: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003338: 3dc13d14    	ldr	q20, [x8, #0x4f0]
10000333c: 4fd09294    	fmul.2d	v20, v20, v16[0]
100003340: 4e74d673    	fadd.2d	v19, v19, v20
100003344: 3dc15514    	ldr	q20, [x8, #0x550]
100003348: 4fc69294    	fmul.2d	v20, v20, v6[0]
10000334c: 4e74d673    	fadd.2d	v19, v19, v20
100003350: 3dc16d14    	ldr	q20, [x8, #0x5b0]
100003354: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003358: 4e74d673    	fadd.2d	v19, v19, v20
10000335c: 3dc18514    	ldr	q20, [x8, #0x610]
100003360: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003364: 4e74d673    	fadd.2d	v19, v19, v20
100003368: 3dc19d14    	ldr	q20, [x8, #0x670]
10000336c: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003370: 4e74d673    	fadd.2d	v19, v19, v20
100003374: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100003378: 4fc39294    	fmul.2d	v20, v20, v3[0]
10000337c: 4e74d673    	fadd.2d	v19, v19, v20
100003380: 3dc1cd14    	ldr	q20, [x8, #0x730]
100003384: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003388: 4e74d673    	fadd.2d	v19, v19, v20
10000338c: 3dc1e514    	ldr	q20, [x8, #0x790]
100003390: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003394: 4e74d673    	fadd.2d	v19, v19, v20
100003398: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
10000339c: 4fc19294    	fmul.2d	v20, v20, v1[0]
1000033a0: 4e74d673    	fadd.2d	v19, v19, v20
1000033a4: ad154d32    	stp	q18, q19, [x9, #0x2a0]
1000033a8: 3dc12912    	ldr	q18, [x8, #0x4a0]
1000033ac: 4fd19252    	fmul.2d	v18, v18, v17[0]
1000033b0: 3dc14113    	ldr	q19, [x8, #0x500]
1000033b4: 4fd09273    	fmul.2d	v19, v19, v16[0]
1000033b8: 4e73d652    	fadd.2d	v18, v18, v19
1000033bc: 3dc15913    	ldr	q19, [x8, #0x560]
1000033c0: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000033c4: 4e73d652    	fadd.2d	v18, v18, v19
1000033c8: 3dc17113    	ldr	q19, [x8, #0x5c0]
1000033cc: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000033d0: 4e73d652    	fadd.2d	v18, v18, v19
1000033d4: 3dc18913    	ldr	q19, [x8, #0x620]
1000033d8: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000033dc: 4e73d652    	fadd.2d	v18, v18, v19
1000033e0: 3dc1a113    	ldr	q19, [x8, #0x680]
1000033e4: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000033e8: 4e73d652    	fadd.2d	v18, v18, v19
1000033ec: 3dc1b913    	ldr	q19, [x8, #0x6e0]
1000033f0: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000033f4: 4e73d652    	fadd.2d	v18, v18, v19
1000033f8: 3dc1d113    	ldr	q19, [x8, #0x740]
1000033fc: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003400: 4e73d652    	fadd.2d	v18, v18, v19
100003404: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003408: 4fc09273    	fmul.2d	v19, v19, v0[0]
10000340c: 4e73d652    	fadd.2d	v18, v18, v19
100003410: 3dc20113    	ldr	q19, [x8, #0x800]
100003414: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003418: 4e73d652    	fadd.2d	v18, v18, v19
10000341c: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003420: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003424: 3dc14514    	ldr	q20, [x8, #0x510]
100003428: 4fd09294    	fmul.2d	v20, v20, v16[0]
10000342c: 4e74d673    	fadd.2d	v19, v19, v20
100003430: 3dc15d14    	ldr	q20, [x8, #0x570]
100003434: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003438: 4e74d673    	fadd.2d	v19, v19, v20
10000343c: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003440: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003444: 4e74d673    	fadd.2d	v19, v19, v20
100003448: 3dc18d14    	ldr	q20, [x8, #0x630]
10000344c: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003450: 4e74d673    	fadd.2d	v19, v19, v20
100003454: 3dc1a514    	ldr	q20, [x8, #0x690]
100003458: 4fc49294    	fmul.2d	v20, v20, v4[0]
10000345c: 4e74d673    	fadd.2d	v19, v19, v20
100003460: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
100003464: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003468: 4e74d673    	fadd.2d	v19, v19, v20
10000346c: 3dc1d514    	ldr	q20, [x8, #0x750]
100003470: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003474: 4e74d673    	fadd.2d	v19, v19, v20
100003478: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
10000347c: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003480: 4e74d673    	fadd.2d	v19, v19, v20
100003484: 3dc20514    	ldr	q20, [x8, #0x810]
100003488: 4fc19294    	fmul.2d	v20, v20, v1[0]
10000348c: 4e74d673    	fadd.2d	v19, v19, v20
100003490: ad164d32    	stp	q18, q19, [x9, #0x2c0]
100003494: 3dc13112    	ldr	q18, [x8, #0x4c0]
100003498: 4fd19252    	fmul.2d	v18, v18, v17[0]
10000349c: 3dc14913    	ldr	q19, [x8, #0x520]
1000034a0: 4fd09273    	fmul.2d	v19, v19, v16[0]
1000034a4: 4e73d652    	fadd.2d	v18, v18, v19
1000034a8: 3dc16113    	ldr	q19, [x8, #0x580]
1000034ac: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000034b0: 4e73d652    	fadd.2d	v18, v18, v19
1000034b4: 3dc17913    	ldr	q19, [x8, #0x5e0]
1000034b8: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000034bc: 4e73d652    	fadd.2d	v18, v18, v19
1000034c0: 3dc19113    	ldr	q19, [x8, #0x640]
1000034c4: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000034c8: 4e73d652    	fadd.2d	v18, v18, v19
1000034cc: 3dc1a913    	ldr	q19, [x8, #0x6a0]
1000034d0: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000034d4: 4e73d652    	fadd.2d	v18, v18, v19
1000034d8: 3dc1c113    	ldr	q19, [x8, #0x700]
1000034dc: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000034e0: 4e73d652    	fadd.2d	v18, v18, v19
1000034e4: 3dc1d913    	ldr	q19, [x8, #0x760]
1000034e8: 4fc29273    	fmul.2d	v19, v19, v2[0]
1000034ec: 4e73d652    	fadd.2d	v18, v18, v19
1000034f0: 3dc1f113    	ldr	q19, [x8, #0x7c0]
1000034f4: 4fc09273    	fmul.2d	v19, v19, v0[0]
1000034f8: 4e73d652    	fadd.2d	v18, v18, v19
1000034fc: 3dc20913    	ldr	q19, [x8, #0x820]
100003500: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003504: 4e73d652    	fadd.2d	v18, v18, v19
100003508: 3dc13513    	ldr	q19, [x8, #0x4d0]
10000350c: 4fd19271    	fmul.2d	v17, v19, v17[0]
100003510: 3dc14d13    	ldr	q19, [x8, #0x530]
100003514: 4fd09270    	fmul.2d	v16, v19, v16[0]
100003518: 4e70d630    	fadd.2d	v16, v17, v16
10000351c: 3dc16511    	ldr	q17, [x8, #0x590]
100003520: 4fc69226    	fmul.2d	v6, v17, v6[0]
100003524: 4e66d606    	fadd.2d	v6, v16, v6
100003528: 3dc17d10    	ldr	q16, [x8, #0x5f0]
10000352c: 4fc59205    	fmul.2d	v5, v16, v5[0]
100003530: 4e65d4c5    	fadd.2d	v5, v6, v5
100003534: 3dc19506    	ldr	q6, [x8, #0x650]
100003538: 4fc790c6    	fmul.2d	v6, v6, v7[0]
10000353c: 4e66d4a5    	fadd.2d	v5, v5, v6
100003540: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
100003544: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100003548: 4e64d4a4    	fadd.2d	v4, v5, v4
10000354c: 3dc1c505    	ldr	q5, [x8, #0x710]
100003550: 4fc390a3    	fmul.2d	v3, v5, v3[0]
100003554: 3dc1dd05    	ldr	q5, [x8, #0x770]
100003558: 4e63d483    	fadd.2d	v3, v4, v3
10000355c: 4fc290a2    	fmul.2d	v2, v5, v2[0]
100003560: 3dc1f504    	ldr	q4, [x8, #0x7d0]
100003564: 4e62d462    	fadd.2d	v2, v3, v2
100003568: 3dc20d03    	ldr	q3, [x8, #0x830]
10000356c: 4fc09080    	fmul.2d	v0, v4, v0[0]
100003570: 4e60d440    	fadd.2d	v0, v2, v0
100003574: 4fc19061    	fmul.2d	v1, v3, v1[0]
100003578: 4e61d400    	fadd.2d	v0, v0, v1
10000357c: ad170132    	stp	q18, q0, [x9, #0x2e0]
100003580: 910c210a    	add	x10, x8, #0x308
100003584: 3dc00150    	ldr	q16, [x10]
100003588: ad581911    	ldp	q17, q6, [x8, #0x300]
10000358c: 910c610a    	add	x10, x8, #0x318
100003590: 3dc00145    	ldr	q5, [x10]
100003594: 910ca10a    	add	x10, x8, #0x328
100003598: 3dc00144    	ldr	q4, [x10]
10000359c: ad590d07    	ldp	q7, q3, [x8, #0x320]
1000035a0: 910ce10a    	add	x10, x8, #0x338
1000035a4: 3dc00142    	ldr	q2, [x10]
1000035a8: 3dc0d100    	ldr	q0, [x8, #0x340]
1000035ac: 910d210a    	add	x10, x8, #0x348
1000035b0: 3dc00141    	ldr	q1, [x10]
1000035b4: 3dc12112    	ldr	q18, [x8, #0x480]
1000035b8: 4fd19252    	fmul.2d	v18, v18, v17[0]
1000035bc: 3dc13913    	ldr	q19, [x8, #0x4e0]
1000035c0: 4fd09273    	fmul.2d	v19, v19, v16[0]
1000035c4: 4e73d652    	fadd.2d	v18, v18, v19
1000035c8: 3dc15113    	ldr	q19, [x8, #0x540]
1000035cc: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000035d0: 4e73d652    	fadd.2d	v18, v18, v19
1000035d4: 3dc16913    	ldr	q19, [x8, #0x5a0]
1000035d8: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000035dc: 4e73d652    	fadd.2d	v18, v18, v19
1000035e0: 3dc18113    	ldr	q19, [x8, #0x600]
1000035e4: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000035e8: 4e73d652    	fadd.2d	v18, v18, v19
1000035ec: 3dc19913    	ldr	q19, [x8, #0x660]
1000035f0: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000035f4: 4e73d652    	fadd.2d	v18, v18, v19
1000035f8: 3dc1b113    	ldr	q19, [x8, #0x6c0]
1000035fc: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003600: 4e73d652    	fadd.2d	v18, v18, v19
100003604: 3dc1c913    	ldr	q19, [x8, #0x720]
100003608: 4fc29273    	fmul.2d	v19, v19, v2[0]
10000360c: 4e73d652    	fadd.2d	v18, v18, v19
100003610: 3dc1e113    	ldr	q19, [x8, #0x780]
100003614: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003618: 4e73d652    	fadd.2d	v18, v18, v19
10000361c: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003620: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003624: 4e73d652    	fadd.2d	v18, v18, v19
100003628: 3dc12513    	ldr	q19, [x8, #0x490]
10000362c: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003630: 3dc13d14    	ldr	q20, [x8, #0x4f0]
100003634: 4fd09294    	fmul.2d	v20, v20, v16[0]
100003638: 4e74d673    	fadd.2d	v19, v19, v20
10000363c: 3dc15514    	ldr	q20, [x8, #0x550]
100003640: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003644: 4e74d673    	fadd.2d	v19, v19, v20
100003648: 3dc16d14    	ldr	q20, [x8, #0x5b0]
10000364c: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003650: 4e74d673    	fadd.2d	v19, v19, v20
100003654: 3dc18514    	ldr	q20, [x8, #0x610]
100003658: 4fc79294    	fmul.2d	v20, v20, v7[0]
10000365c: 4e74d673    	fadd.2d	v19, v19, v20
100003660: 3dc19d14    	ldr	q20, [x8, #0x670]
100003664: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003668: 4e74d673    	fadd.2d	v19, v19, v20
10000366c: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100003670: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003674: 4e74d673    	fadd.2d	v19, v19, v20
100003678: 3dc1cd14    	ldr	q20, [x8, #0x730]
10000367c: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003680: 4e74d673    	fadd.2d	v19, v19, v20
100003684: 3dc1e514    	ldr	q20, [x8, #0x790]
100003688: 4fc09294    	fmul.2d	v20, v20, v0[0]
10000368c: 4e74d673    	fadd.2d	v19, v19, v20
100003690: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
100003694: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003698: 4e74d673    	fadd.2d	v19, v19, v20
10000369c: ad184d32    	stp	q18, q19, [x9, #0x300]
1000036a0: 3dc12912    	ldr	q18, [x8, #0x4a0]
1000036a4: 4fd19252    	fmul.2d	v18, v18, v17[0]
1000036a8: 3dc14113    	ldr	q19, [x8, #0x500]
1000036ac: 4fd09273    	fmul.2d	v19, v19, v16[0]
1000036b0: 4e73d652    	fadd.2d	v18, v18, v19
1000036b4: 3dc15913    	ldr	q19, [x8, #0x560]
1000036b8: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000036bc: 4e73d652    	fadd.2d	v18, v18, v19
1000036c0: 3dc17113    	ldr	q19, [x8, #0x5c0]
1000036c4: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000036c8: 4e73d652    	fadd.2d	v18, v18, v19
1000036cc: 3dc18913    	ldr	q19, [x8, #0x620]
1000036d0: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000036d4: 4e73d652    	fadd.2d	v18, v18, v19
1000036d8: 3dc1a113    	ldr	q19, [x8, #0x680]
1000036dc: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000036e0: 4e73d652    	fadd.2d	v18, v18, v19
1000036e4: 3dc1b913    	ldr	q19, [x8, #0x6e0]
1000036e8: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000036ec: 4e73d652    	fadd.2d	v18, v18, v19
1000036f0: 3dc1d113    	ldr	q19, [x8, #0x740]
1000036f4: 4fc29273    	fmul.2d	v19, v19, v2[0]
1000036f8: 4e73d652    	fadd.2d	v18, v18, v19
1000036fc: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003700: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003704: 4e73d652    	fadd.2d	v18, v18, v19
100003708: 3dc20113    	ldr	q19, [x8, #0x800]
10000370c: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003710: 4e73d652    	fadd.2d	v18, v18, v19
100003714: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003718: 4fd19273    	fmul.2d	v19, v19, v17[0]
10000371c: 3dc14514    	ldr	q20, [x8, #0x510]
100003720: 4fd09294    	fmul.2d	v20, v20, v16[0]
100003724: 4e74d673    	fadd.2d	v19, v19, v20
100003728: 3dc15d14    	ldr	q20, [x8, #0x570]
10000372c: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003730: 4e74d673    	fadd.2d	v19, v19, v20
100003734: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003738: 4fc59294    	fmul.2d	v20, v20, v5[0]
10000373c: 4e74d673    	fadd.2d	v19, v19, v20
100003740: 3dc18d14    	ldr	q20, [x8, #0x630]
100003744: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003748: 4e74d673    	fadd.2d	v19, v19, v20
10000374c: 3dc1a514    	ldr	q20, [x8, #0x690]
100003750: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003754: 4e74d673    	fadd.2d	v19, v19, v20
100003758: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
10000375c: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003760: 4e74d673    	fadd.2d	v19, v19, v20
100003764: 3dc1d514    	ldr	q20, [x8, #0x750]
100003768: 4fc29294    	fmul.2d	v20, v20, v2[0]
10000376c: 4e74d673    	fadd.2d	v19, v19, v20
100003770: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
100003774: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003778: 4e74d673    	fadd.2d	v19, v19, v20
10000377c: 3dc20514    	ldr	q20, [x8, #0x810]
100003780: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003784: 4e74d673    	fadd.2d	v19, v19, v20
100003788: ad194d32    	stp	q18, q19, [x9, #0x320]
10000378c: 3dc13112    	ldr	q18, [x8, #0x4c0]
100003790: 4fd19252    	fmul.2d	v18, v18, v17[0]
100003794: 3dc14913    	ldr	q19, [x8, #0x520]
100003798: 4fd09273    	fmul.2d	v19, v19, v16[0]
10000379c: 4e73d652    	fadd.2d	v18, v18, v19
1000037a0: 3dc16113    	ldr	q19, [x8, #0x580]
1000037a4: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000037a8: 4e73d652    	fadd.2d	v18, v18, v19
1000037ac: 3dc17913    	ldr	q19, [x8, #0x5e0]
1000037b0: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000037b4: 4e73d652    	fadd.2d	v18, v18, v19
1000037b8: 3dc19113    	ldr	q19, [x8, #0x640]
1000037bc: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000037c0: 4e73d652    	fadd.2d	v18, v18, v19
1000037c4: 3dc1a913    	ldr	q19, [x8, #0x6a0]
1000037c8: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000037cc: 4e73d652    	fadd.2d	v18, v18, v19
1000037d0: 3dc1c113    	ldr	q19, [x8, #0x700]
1000037d4: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000037d8: 4e73d652    	fadd.2d	v18, v18, v19
1000037dc: 3dc1d913    	ldr	q19, [x8, #0x760]
1000037e0: 4fc29273    	fmul.2d	v19, v19, v2[0]
1000037e4: 4e73d652    	fadd.2d	v18, v18, v19
1000037e8: 3dc1f113    	ldr	q19, [x8, #0x7c0]
1000037ec: 4fc09273    	fmul.2d	v19, v19, v0[0]
1000037f0: 4e73d652    	fadd.2d	v18, v18, v19
1000037f4: 3dc20913    	ldr	q19, [x8, #0x820]
1000037f8: 4fc19273    	fmul.2d	v19, v19, v1[0]
1000037fc: 4e73d652    	fadd.2d	v18, v18, v19
100003800: 3dc13513    	ldr	q19, [x8, #0x4d0]
100003804: 4fd19271    	fmul.2d	v17, v19, v17[0]
100003808: 3dc14d13    	ldr	q19, [x8, #0x530]
10000380c: 4fd09270    	fmul.2d	v16, v19, v16[0]
100003810: 4e70d630    	fadd.2d	v16, v17, v16
100003814: 3dc16511    	ldr	q17, [x8, #0x590]
100003818: 4fc69226    	fmul.2d	v6, v17, v6[0]
10000381c: 4e66d606    	fadd.2d	v6, v16, v6
100003820: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100003824: 4fc59205    	fmul.2d	v5, v16, v5[0]
100003828: 4e65d4c5    	fadd.2d	v5, v6, v5
10000382c: 3dc19506    	ldr	q6, [x8, #0x650]
100003830: 4fc790c6    	fmul.2d	v6, v6, v7[0]
100003834: 4e66d4a5    	fadd.2d	v5, v5, v6
100003838: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
10000383c: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100003840: 4e64d4a4    	fadd.2d	v4, v5, v4
100003844: 3dc1c505    	ldr	q5, [x8, #0x710]
100003848: 4fc390a3    	fmul.2d	v3, v5, v3[0]
10000384c: 3dc1dd05    	ldr	q5, [x8, #0x770]
100003850: 4e63d483    	fadd.2d	v3, v4, v3
100003854: 4fc290a2    	fmul.2d	v2, v5, v2[0]
100003858: 3dc1f504    	ldr	q4, [x8, #0x7d0]
10000385c: 4e62d462    	fadd.2d	v2, v3, v2
100003860: 3dc20d03    	ldr	q3, [x8, #0x830]
100003864: 4fc09080    	fmul.2d	v0, v4, v0[0]
100003868: 4e60d440    	fadd.2d	v0, v2, v0
10000386c: 4fc19061    	fmul.2d	v1, v3, v1[0]
100003870: 4e61d400    	fadd.2d	v0, v0, v1
100003874: ad1a0132    	stp	q18, q0, [x9, #0x340]
100003878: 910da10a    	add	x10, x8, #0x368
10000387c: 3dc00150    	ldr	q16, [x10]
100003880: ad5b1911    	ldp	q17, q6, [x8, #0x360]
100003884: 910de10a    	add	x10, x8, #0x378
100003888: 3dc00145    	ldr	q5, [x10]
10000388c: 910e210a    	add	x10, x8, #0x388
100003890: 3dc00144    	ldr	q4, [x10]
100003894: ad5c0d07    	ldp	q7, q3, [x8, #0x380]
100003898: 910e610a    	add	x10, x8, #0x398
10000389c: 3dc00142    	ldr	q2, [x10]
1000038a0: 3dc0e900    	ldr	q0, [x8, #0x3a0]
1000038a4: 910ea10a    	add	x10, x8, #0x3a8
1000038a8: 3dc00141    	ldr	q1, [x10]
1000038ac: 3dc12112    	ldr	q18, [x8, #0x480]
1000038b0: 4fd19252    	fmul.2d	v18, v18, v17[0]
1000038b4: 3dc13913    	ldr	q19, [x8, #0x4e0]
1000038b8: 4fd09273    	fmul.2d	v19, v19, v16[0]
1000038bc: 4e73d652    	fadd.2d	v18, v18, v19
1000038c0: 3dc15113    	ldr	q19, [x8, #0x540]
1000038c4: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000038c8: 4e73d652    	fadd.2d	v18, v18, v19
1000038cc: 3dc16913    	ldr	q19, [x8, #0x5a0]
1000038d0: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000038d4: 4e73d652    	fadd.2d	v18, v18, v19
1000038d8: 3dc18113    	ldr	q19, [x8, #0x600]
1000038dc: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000038e0: 4e73d652    	fadd.2d	v18, v18, v19
1000038e4: 3dc19913    	ldr	q19, [x8, #0x660]
1000038e8: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000038ec: 4e73d652    	fadd.2d	v18, v18, v19
1000038f0: 3dc1b113    	ldr	q19, [x8, #0x6c0]
1000038f4: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000038f8: 4e73d652    	fadd.2d	v18, v18, v19
1000038fc: 3dc1c913    	ldr	q19, [x8, #0x720]
100003900: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003904: 4e73d652    	fadd.2d	v18, v18, v19
100003908: 3dc1e113    	ldr	q19, [x8, #0x780]
10000390c: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003910: 4e73d652    	fadd.2d	v18, v18, v19
100003914: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003918: 4fc19273    	fmul.2d	v19, v19, v1[0]
10000391c: 4e73d652    	fadd.2d	v18, v18, v19
100003920: 3dc12513    	ldr	q19, [x8, #0x490]
100003924: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003928: 3dc13d14    	ldr	q20, [x8, #0x4f0]
10000392c: 4fd09294    	fmul.2d	v20, v20, v16[0]
100003930: 4e74d673    	fadd.2d	v19, v19, v20
100003934: 3dc15514    	ldr	q20, [x8, #0x550]
100003938: 4fc69294    	fmul.2d	v20, v20, v6[0]
10000393c: 4e74d673    	fadd.2d	v19, v19, v20
100003940: 3dc16d14    	ldr	q20, [x8, #0x5b0]
100003944: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003948: 4e74d673    	fadd.2d	v19, v19, v20
10000394c: 3dc18514    	ldr	q20, [x8, #0x610]
100003950: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003954: 4e74d673    	fadd.2d	v19, v19, v20
100003958: 3dc19d14    	ldr	q20, [x8, #0x670]
10000395c: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003960: 4e74d673    	fadd.2d	v19, v19, v20
100003964: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100003968: 4fc39294    	fmul.2d	v20, v20, v3[0]
10000396c: 4e74d673    	fadd.2d	v19, v19, v20
100003970: 3dc1cd14    	ldr	q20, [x8, #0x730]
100003974: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003978: 4e74d673    	fadd.2d	v19, v19, v20
10000397c: 3dc1e514    	ldr	q20, [x8, #0x790]
100003980: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003984: 4e74d673    	fadd.2d	v19, v19, v20
100003988: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
10000398c: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003990: 4e74d673    	fadd.2d	v19, v19, v20
100003994: ad1b4d32    	stp	q18, q19, [x9, #0x360]
100003998: 3dc12912    	ldr	q18, [x8, #0x4a0]
10000399c: 4fd19252    	fmul.2d	v18, v18, v17[0]
1000039a0: 3dc14113    	ldr	q19, [x8, #0x500]
1000039a4: 4fd09273    	fmul.2d	v19, v19, v16[0]
1000039a8: 4e73d652    	fadd.2d	v18, v18, v19
1000039ac: 3dc15913    	ldr	q19, [x8, #0x560]
1000039b0: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000039b4: 4e73d652    	fadd.2d	v18, v18, v19
1000039b8: 3dc17113    	ldr	q19, [x8, #0x5c0]
1000039bc: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000039c0: 4e73d652    	fadd.2d	v18, v18, v19
1000039c4: 3dc18913    	ldr	q19, [x8, #0x620]
1000039c8: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000039cc: 4e73d652    	fadd.2d	v18, v18, v19
1000039d0: 3dc1a113    	ldr	q19, [x8, #0x680]
1000039d4: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000039d8: 4e73d652    	fadd.2d	v18, v18, v19
1000039dc: 3dc1b913    	ldr	q19, [x8, #0x6e0]
1000039e0: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000039e4: 4e73d652    	fadd.2d	v18, v18, v19
1000039e8: 3dc1d113    	ldr	q19, [x8, #0x740]
1000039ec: 4fc29273    	fmul.2d	v19, v19, v2[0]
1000039f0: 4e73d652    	fadd.2d	v18, v18, v19
1000039f4: 3dc1e913    	ldr	q19, [x8, #0x7a0]
1000039f8: 4fc09273    	fmul.2d	v19, v19, v0[0]
1000039fc: 4e73d652    	fadd.2d	v18, v18, v19
100003a00: 3dc20113    	ldr	q19, [x8, #0x800]
100003a04: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003a08: 4e73d652    	fadd.2d	v18, v18, v19
100003a0c: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003a10: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003a14: 3dc14514    	ldr	q20, [x8, #0x510]
100003a18: 4fd09294    	fmul.2d	v20, v20, v16[0]
100003a1c: 4e74d673    	fadd.2d	v19, v19, v20
100003a20: 3dc15d14    	ldr	q20, [x8, #0x570]
100003a24: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003a28: 4e74d673    	fadd.2d	v19, v19, v20
100003a2c: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003a30: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003a34: 4e74d673    	fadd.2d	v19, v19, v20
100003a38: 3dc18d14    	ldr	q20, [x8, #0x630]
100003a3c: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003a40: 4e74d673    	fadd.2d	v19, v19, v20
100003a44: 3dc1a514    	ldr	q20, [x8, #0x690]
100003a48: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003a4c: 4e74d673    	fadd.2d	v19, v19, v20
100003a50: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
100003a54: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003a58: 4e74d673    	fadd.2d	v19, v19, v20
100003a5c: 3dc1d514    	ldr	q20, [x8, #0x750]
100003a60: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003a64: 4e74d673    	fadd.2d	v19, v19, v20
100003a68: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
100003a6c: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003a70: 4e74d673    	fadd.2d	v19, v19, v20
100003a74: 3dc20514    	ldr	q20, [x8, #0x810]
100003a78: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003a7c: 4e74d673    	fadd.2d	v19, v19, v20
100003a80: ad1c4d32    	stp	q18, q19, [x9, #0x380]
100003a84: 3dc13112    	ldr	q18, [x8, #0x4c0]
100003a88: 4fd19252    	fmul.2d	v18, v18, v17[0]
100003a8c: 3dc14913    	ldr	q19, [x8, #0x520]
100003a90: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003a94: 4e73d652    	fadd.2d	v18, v18, v19
100003a98: 3dc16113    	ldr	q19, [x8, #0x580]
100003a9c: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003aa0: 4e73d652    	fadd.2d	v18, v18, v19
100003aa4: 3dc17913    	ldr	q19, [x8, #0x5e0]
100003aa8: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003aac: 4e73d652    	fadd.2d	v18, v18, v19
100003ab0: 3dc19113    	ldr	q19, [x8, #0x640]
100003ab4: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003ab8: 4e73d652    	fadd.2d	v18, v18, v19
100003abc: 3dc1a913    	ldr	q19, [x8, #0x6a0]
100003ac0: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003ac4: 4e73d652    	fadd.2d	v18, v18, v19
100003ac8: 3dc1c113    	ldr	q19, [x8, #0x700]
100003acc: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003ad0: 4e73d652    	fadd.2d	v18, v18, v19
100003ad4: 3dc1d913    	ldr	q19, [x8, #0x760]
100003ad8: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003adc: 4e73d652    	fadd.2d	v18, v18, v19
100003ae0: 3dc1f113    	ldr	q19, [x8, #0x7c0]
100003ae4: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003ae8: 4e73d652    	fadd.2d	v18, v18, v19
100003aec: 3dc20913    	ldr	q19, [x8, #0x820]
100003af0: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003af4: 4e73d652    	fadd.2d	v18, v18, v19
100003af8: 3dc13513    	ldr	q19, [x8, #0x4d0]
100003afc: 4fd19271    	fmul.2d	v17, v19, v17[0]
100003b00: 3dc14d13    	ldr	q19, [x8, #0x530]
100003b04: 4fd09270    	fmul.2d	v16, v19, v16[0]
100003b08: 4e70d630    	fadd.2d	v16, v17, v16
100003b0c: 3dc16511    	ldr	q17, [x8, #0x590]
100003b10: 4fc69226    	fmul.2d	v6, v17, v6[0]
100003b14: 4e66d606    	fadd.2d	v6, v16, v6
100003b18: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100003b1c: 4fc59205    	fmul.2d	v5, v16, v5[0]
100003b20: 4e65d4c5    	fadd.2d	v5, v6, v5
100003b24: 3dc19506    	ldr	q6, [x8, #0x650]
100003b28: 4fc790c6    	fmul.2d	v6, v6, v7[0]
100003b2c: 4e66d4a5    	fadd.2d	v5, v5, v6
100003b30: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
100003b34: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100003b38: 4e64d4a4    	fadd.2d	v4, v5, v4
100003b3c: 3dc1c505    	ldr	q5, [x8, #0x710]
100003b40: 4fc390a3    	fmul.2d	v3, v5, v3[0]
100003b44: 3dc1dd05    	ldr	q5, [x8, #0x770]
100003b48: 4e63d483    	fadd.2d	v3, v4, v3
100003b4c: 4fc290a2    	fmul.2d	v2, v5, v2[0]
100003b50: 3dc1f504    	ldr	q4, [x8, #0x7d0]
100003b54: 4e62d462    	fadd.2d	v2, v3, v2
100003b58: 3dc20d03    	ldr	q3, [x8, #0x830]
100003b5c: 4fc09080    	fmul.2d	v0, v4, v0[0]
100003b60: 4e60d440    	fadd.2d	v0, v2, v0
100003b64: 4fc19061    	fmul.2d	v1, v3, v1[0]
100003b68: 4e61d400    	fadd.2d	v0, v0, v1
100003b6c: ad1d0132    	stp	q18, q0, [x9, #0x3a0]
100003b70: 910f210a    	add	x10, x8, #0x3c8
100003b74: 3dc00150    	ldr	q16, [x10]
100003b78: ad5e1911    	ldp	q17, q6, [x8, #0x3c0]
100003b7c: 910f610a    	add	x10, x8, #0x3d8
100003b80: 3dc00145    	ldr	q5, [x10]
100003b84: 910fa10a    	add	x10, x8, #0x3e8
100003b88: 3dc00144    	ldr	q4, [x10]
100003b8c: ad5f0d07    	ldp	q7, q3, [x8, #0x3e0]
100003b90: 910fe10a    	add	x10, x8, #0x3f8
100003b94: 3dc00142    	ldr	q2, [x10]
100003b98: 3dc10101    	ldr	q1, [x8, #0x400]
100003b9c: 9110210a    	add	x10, x8, #0x408
100003ba0: 3dc00140    	ldr	q0, [x10]
100003ba4: 3dc12112    	ldr	q18, [x8, #0x480]
100003ba8: 4fd19252    	fmul.2d	v18, v18, v17[0]
100003bac: 3dc13913    	ldr	q19, [x8, #0x4e0]
100003bb0: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003bb4: 4e73d652    	fadd.2d	v18, v18, v19
100003bb8: 3dc15113    	ldr	q19, [x8, #0x540]
100003bbc: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003bc0: 4e73d652    	fadd.2d	v18, v18, v19
100003bc4: 3dc16913    	ldr	q19, [x8, #0x5a0]
100003bc8: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003bcc: 4e73d652    	fadd.2d	v18, v18, v19
100003bd0: 3dc18113    	ldr	q19, [x8, #0x600]
100003bd4: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003bd8: 4e73d652    	fadd.2d	v18, v18, v19
100003bdc: 3dc19913    	ldr	q19, [x8, #0x660]
100003be0: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003be4: 4e73d652    	fadd.2d	v18, v18, v19
100003be8: 3dc1b113    	ldr	q19, [x8, #0x6c0]
100003bec: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003bf0: 4e73d652    	fadd.2d	v18, v18, v19
100003bf4: 3dc1c913    	ldr	q19, [x8, #0x720]
100003bf8: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003bfc: 4e73d652    	fadd.2d	v18, v18, v19
100003c00: 3dc1e113    	ldr	q19, [x8, #0x780]
100003c04: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003c08: 4e73d652    	fadd.2d	v18, v18, v19
100003c0c: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003c10: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003c14: 4e73d652    	fadd.2d	v18, v18, v19
100003c18: 3dc12513    	ldr	q19, [x8, #0x490]
100003c1c: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003c20: 3dc13d14    	ldr	q20, [x8, #0x4f0]
100003c24: 4fd09294    	fmul.2d	v20, v20, v16[0]
100003c28: 4e74d673    	fadd.2d	v19, v19, v20
100003c2c: 3dc15514    	ldr	q20, [x8, #0x550]
100003c30: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003c34: 4e74d673    	fadd.2d	v19, v19, v20
100003c38: 3dc16d14    	ldr	q20, [x8, #0x5b0]
100003c3c: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003c40: 4e74d673    	fadd.2d	v19, v19, v20
100003c44: 3dc18514    	ldr	q20, [x8, #0x610]
100003c48: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003c4c: 4e74d673    	fadd.2d	v19, v19, v20
100003c50: 3dc19d14    	ldr	q20, [x8, #0x670]
100003c54: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003c58: 4e74d673    	fadd.2d	v19, v19, v20
100003c5c: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100003c60: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003c64: 4e74d673    	fadd.2d	v19, v19, v20
100003c68: 3dc1cd14    	ldr	q20, [x8, #0x730]
100003c6c: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003c70: 4e74d673    	fadd.2d	v19, v19, v20
100003c74: 3dc1e514    	ldr	q20, [x8, #0x790]
100003c78: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003c7c: 4e74d673    	fadd.2d	v19, v19, v20
100003c80: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
100003c84: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003c88: 4e74d673    	fadd.2d	v19, v19, v20
100003c8c: ad1e4d32    	stp	q18, q19, [x9, #0x3c0]
100003c90: 3dc12912    	ldr	q18, [x8, #0x4a0]
100003c94: 4fd19252    	fmul.2d	v18, v18, v17[0]
100003c98: 3dc14113    	ldr	q19, [x8, #0x500]
100003c9c: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003ca0: 4e73d652    	fadd.2d	v18, v18, v19
100003ca4: 3dc15913    	ldr	q19, [x8, #0x560]
100003ca8: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003cac: 4e73d652    	fadd.2d	v18, v18, v19
100003cb0: 3dc17113    	ldr	q19, [x8, #0x5c0]
100003cb4: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003cb8: 4e73d652    	fadd.2d	v18, v18, v19
100003cbc: 3dc18913    	ldr	q19, [x8, #0x620]
100003cc0: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003cc4: 4e73d652    	fadd.2d	v18, v18, v19
100003cc8: 3dc1a113    	ldr	q19, [x8, #0x680]
100003ccc: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003cd0: 4e73d652    	fadd.2d	v18, v18, v19
100003cd4: 3dc1b913    	ldr	q19, [x8, #0x6e0]
100003cd8: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003cdc: 4e73d652    	fadd.2d	v18, v18, v19
100003ce0: 3dc1d113    	ldr	q19, [x8, #0x740]
100003ce4: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003ce8: 4e73d652    	fadd.2d	v18, v18, v19
100003cec: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003cf0: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003cf4: 4e73d652    	fadd.2d	v18, v18, v19
100003cf8: 3dc20113    	ldr	q19, [x8, #0x800]
100003cfc: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003d00: 4e73d652    	fadd.2d	v18, v18, v19
100003d04: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003d08: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003d0c: 3dc14514    	ldr	q20, [x8, #0x510]
100003d10: 4fd09294    	fmul.2d	v20, v20, v16[0]
100003d14: 4e74d673    	fadd.2d	v19, v19, v20
100003d18: 3dc15d14    	ldr	q20, [x8, #0x570]
100003d1c: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003d20: 4e74d673    	fadd.2d	v19, v19, v20
100003d24: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003d28: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003d2c: 4e74d673    	fadd.2d	v19, v19, v20
100003d30: 3dc18d14    	ldr	q20, [x8, #0x630]
100003d34: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003d38: 4e74d673    	fadd.2d	v19, v19, v20
100003d3c: 3dc1a514    	ldr	q20, [x8, #0x690]
100003d40: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003d44: 4e74d673    	fadd.2d	v19, v19, v20
100003d48: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
100003d4c: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003d50: 4e74d673    	fadd.2d	v19, v19, v20
100003d54: 3dc1d514    	ldr	q20, [x8, #0x750]
100003d58: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003d5c: 4e74d673    	fadd.2d	v19, v19, v20
100003d60: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
100003d64: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003d68: 4e74d673    	fadd.2d	v19, v19, v20
100003d6c: 3dc20514    	ldr	q20, [x8, #0x810]
100003d70: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003d74: 4e74d673    	fadd.2d	v19, v19, v20
100003d78: ad1f4d32    	stp	q18, q19, [x9, #0x3e0]
100003d7c: 3dc13112    	ldr	q18, [x8, #0x4c0]
100003d80: 4fd19252    	fmul.2d	v18, v18, v17[0]
100003d84: 3dc14913    	ldr	q19, [x8, #0x520]
100003d88: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003d8c: 4e73d652    	fadd.2d	v18, v18, v19
100003d90: 3dc16113    	ldr	q19, [x8, #0x580]
100003d94: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003d98: 4e73d652    	fadd.2d	v18, v18, v19
100003d9c: 3dc17913    	ldr	q19, [x8, #0x5e0]
100003da0: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003da4: 4e73d652    	fadd.2d	v18, v18, v19
100003da8: 3dc19113    	ldr	q19, [x8, #0x640]
100003dac: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003db0: 4e73d652    	fadd.2d	v18, v18, v19
100003db4: 3dc1a913    	ldr	q19, [x8, #0x6a0]
100003db8: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003dbc: 4e73d652    	fadd.2d	v18, v18, v19
100003dc0: 3dc1c113    	ldr	q19, [x8, #0x700]
100003dc4: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003dc8: 4e73d652    	fadd.2d	v18, v18, v19
100003dcc: 3dc1d913    	ldr	q19, [x8, #0x760]
100003dd0: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003dd4: 4e73d652    	fadd.2d	v18, v18, v19
100003dd8: 3dc1f113    	ldr	q19, [x8, #0x7c0]
100003ddc: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003de0: 4e73d652    	fadd.2d	v18, v18, v19
100003de4: 3dc20913    	ldr	q19, [x8, #0x820]
100003de8: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003dec: 4e73d652    	fadd.2d	v18, v18, v19
100003df0: 3d810132    	str	q18, [x9, #0x400]
100003df4: 3dc13512    	ldr	q18, [x8, #0x4d0]
100003df8: 4fd19251    	fmul.2d	v17, v18, v17[0]
100003dfc: 3dc14d12    	ldr	q18, [x8, #0x530]
100003e00: 4fd09250    	fmul.2d	v16, v18, v16[0]
100003e04: 4e70d630    	fadd.2d	v16, v17, v16
100003e08: 3dc16511    	ldr	q17, [x8, #0x590]
100003e0c: 4fc69226    	fmul.2d	v6, v17, v6[0]
100003e10: 4e66d606    	fadd.2d	v6, v16, v6
100003e14: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100003e18: 4fc59205    	fmul.2d	v5, v16, v5[0]
100003e1c: 4e65d4c5    	fadd.2d	v5, v6, v5
100003e20: 3dc19506    	ldr	q6, [x8, #0x650]
100003e24: 4fc790c6    	fmul.2d	v6, v6, v7[0]
100003e28: 4e66d4a5    	fadd.2d	v5, v5, v6
100003e2c: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
100003e30: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100003e34: 4e64d4a4    	fadd.2d	v4, v5, v4
100003e38: 3dc1c505    	ldr	q5, [x8, #0x710]
100003e3c: 4fc390a3    	fmul.2d	v3, v5, v3[0]
100003e40: 4e63d483    	fadd.2d	v3, v4, v3
100003e44: 3dc1dd04    	ldr	q4, [x8, #0x770]
100003e48: 4fc29082    	fmul.2d	v2, v4, v2[0]
100003e4c: 4e62d462    	fadd.2d	v2, v3, v2
100003e50: 3dc1f503    	ldr	q3, [x8, #0x7d0]
100003e54: 4fc19061    	fmul.2d	v1, v3, v1[0]
100003e58: 4e61d441    	fadd.2d	v1, v2, v1
100003e5c: 3dc20d02    	ldr	q2, [x8, #0x830]
100003e60: 4fc09040    	fmul.2d	v0, v2, v0[0]
100003e64: 4e60d420    	fadd.2d	v0, v1, v0
100003e68: 3d810520    	str	q0, [x9, #0x410]
100003e6c: 3dc10910    	ldr	q16, [x8, #0x420]
100003e70: 9110a10a    	add	x10, x8, #0x428
100003e74: 3dc00151    	ldr	q17, [x10]
100003e78: 3dc10d07    	ldr	q7, [x8, #0x430]
100003e7c: 9110e10a    	add	x10, x8, #0x438
100003e80: 3dc00146    	ldr	q6, [x10]
100003e84: 3dc11105    	ldr	q5, [x8, #0x440]
100003e88: 9111210a    	add	x10, x8, #0x448
100003e8c: 3dc00144    	ldr	q4, [x10]
100003e90: 3dc11503    	ldr	q3, [x8, #0x450]
100003e94: 9111610a    	add	x10, x8, #0x458
100003e98: 3dc00142    	ldr	q2, [x10]
100003e9c: 3dc11901    	ldr	q1, [x8, #0x460]
100003ea0: 9111a10a    	add	x10, x8, #0x468
100003ea4: 3dc00140    	ldr	q0, [x10]
100003ea8: 3dc12112    	ldr	q18, [x8, #0x480]
100003eac: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003eb0: 3dc13913    	ldr	q19, [x8, #0x4e0]
100003eb4: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003eb8: 4e73d652    	fadd.2d	v18, v18, v19
100003ebc: 3dc15113    	ldr	q19, [x8, #0x540]
100003ec0: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003ec4: 4e73d652    	fadd.2d	v18, v18, v19
100003ec8: 3dc16913    	ldr	q19, [x8, #0x5a0]
100003ecc: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003ed0: 4e73d652    	fadd.2d	v18, v18, v19
100003ed4: 3dc18113    	ldr	q19, [x8, #0x600]
100003ed8: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003edc: 4e73d652    	fadd.2d	v18, v18, v19
100003ee0: 3dc19913    	ldr	q19, [x8, #0x660]
100003ee4: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003ee8: 4e73d652    	fadd.2d	v18, v18, v19
100003eec: 3dc1b113    	ldr	q19, [x8, #0x6c0]
100003ef0: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003ef4: 4e73d652    	fadd.2d	v18, v18, v19
100003ef8: 3dc1c913    	ldr	q19, [x8, #0x720]
100003efc: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003f00: 4e73d652    	fadd.2d	v18, v18, v19
100003f04: 3dc1e113    	ldr	q19, [x8, #0x780]
100003f08: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003f0c: 4e73d652    	fadd.2d	v18, v18, v19
100003f10: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003f14: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003f18: 4e73d652    	fadd.2d	v18, v18, v19
100003f1c: 3d810932    	str	q18, [x9, #0x420]
100003f20: 3dc12512    	ldr	q18, [x8, #0x490]
100003f24: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003f28: 3dc13d13    	ldr	q19, [x8, #0x4f0]
100003f2c: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003f30: 4e73d652    	fadd.2d	v18, v18, v19
100003f34: 3dc15513    	ldr	q19, [x8, #0x550]
100003f38: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003f3c: 4e73d652    	fadd.2d	v18, v18, v19
100003f40: 3dc16d13    	ldr	q19, [x8, #0x5b0]
100003f44: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003f48: 4e73d652    	fadd.2d	v18, v18, v19
100003f4c: 3dc18513    	ldr	q19, [x8, #0x610]
100003f50: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003f54: 4e73d652    	fadd.2d	v18, v18, v19
100003f58: 3dc19d13    	ldr	q19, [x8, #0x670]
100003f5c: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003f60: 4e73d652    	fadd.2d	v18, v18, v19
100003f64: 3dc1b513    	ldr	q19, [x8, #0x6d0]
100003f68: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003f6c: 4e73d652    	fadd.2d	v18, v18, v19
100003f70: 3dc1cd13    	ldr	q19, [x8, #0x730]
100003f74: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003f78: 4e73d652    	fadd.2d	v18, v18, v19
100003f7c: 3dc1e513    	ldr	q19, [x8, #0x790]
100003f80: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003f84: 4e73d652    	fadd.2d	v18, v18, v19
100003f88: 3dc1fd13    	ldr	q19, [x8, #0x7f0]
100003f8c: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003f90: 4e73d652    	fadd.2d	v18, v18, v19
100003f94: 3d810d32    	str	q18, [x9, #0x430]
100003f98: 3dc12912    	ldr	q18, [x8, #0x4a0]
100003f9c: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003fa0: 3dc14113    	ldr	q19, [x8, #0x500]
100003fa4: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003fa8: 4e73d652    	fadd.2d	v18, v18, v19
100003fac: 3dc15913    	ldr	q19, [x8, #0x560]
100003fb0: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003fb4: 4e73d652    	fadd.2d	v18, v18, v19
100003fb8: 3dc17113    	ldr	q19, [x8, #0x5c0]
100003fbc: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003fc0: 4e73d652    	fadd.2d	v18, v18, v19
100003fc4: 3dc18913    	ldr	q19, [x8, #0x620]
100003fc8: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003fcc: 4e73d652    	fadd.2d	v18, v18, v19
100003fd0: 3dc1a113    	ldr	q19, [x8, #0x680]
100003fd4: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003fd8: 4e73d652    	fadd.2d	v18, v18, v19
100003fdc: 3dc1b913    	ldr	q19, [x8, #0x6e0]
100003fe0: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003fe4: 4e73d652    	fadd.2d	v18, v18, v19
100003fe8: 3dc1d113    	ldr	q19, [x8, #0x740]
100003fec: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003ff0: 4e73d652    	fadd.2d	v18, v18, v19
100003ff4: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003ff8: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003ffc: 4e73d652    	fadd.2d	v18, v18, v19
100004000: 3dc20113    	ldr	q19, [x8, #0x800]
100004004: 4fc09273    	fmul.2d	v19, v19, v0[0]
100004008: 4e73d652    	fadd.2d	v18, v18, v19
10000400c: 3d811132    	str	q18, [x9, #0x440]
100004010: 3dc12d12    	ldr	q18, [x8, #0x4b0]
100004014: 4fd09252    	fmul.2d	v18, v18, v16[0]
100004018: 3dc14513    	ldr	q19, [x8, #0x510]
10000401c: 4fd19273    	fmul.2d	v19, v19, v17[0]
100004020: 4e73d652    	fadd.2d	v18, v18, v19
100004024: 3dc15d13    	ldr	q19, [x8, #0x570]
100004028: 4fc79273    	fmul.2d	v19, v19, v7[0]
10000402c: 4e73d652    	fadd.2d	v18, v18, v19
100004030: 3dc17513    	ldr	q19, [x8, #0x5d0]
100004034: 4fc69273    	fmul.2d	v19, v19, v6[0]
100004038: 4e73d652    	fadd.2d	v18, v18, v19
10000403c: 3dc18d13    	ldr	q19, [x8, #0x630]
100004040: 4fc59273    	fmul.2d	v19, v19, v5[0]
100004044: 4e73d652    	fadd.2d	v18, v18, v19
100004048: 3dc1a513    	ldr	q19, [x8, #0x690]
10000404c: 4fc49273    	fmul.2d	v19, v19, v4[0]
100004050: 4e73d652    	fadd.2d	v18, v18, v19
100004054: 3dc1bd13    	ldr	q19, [x8, #0x6f0]
100004058: 4fc39273    	fmul.2d	v19, v19, v3[0]
10000405c: 4e73d652    	fadd.2d	v18, v18, v19
100004060: 3dc1d513    	ldr	q19, [x8, #0x750]
100004064: 4fc29273    	fmul.2d	v19, v19, v2[0]
100004068: 4e73d652    	fadd.2d	v18, v18, v19
10000406c: 3dc1ed13    	ldr	q19, [x8, #0x7b0]
100004070: 4fc19273    	fmul.2d	v19, v19, v1[0]
100004074: 4e73d652    	fadd.2d	v18, v18, v19
100004078: 3dc20513    	ldr	q19, [x8, #0x810]
10000407c: 4fc09273    	fmul.2d	v19, v19, v0[0]
100004080: 4e73d652    	fadd.2d	v18, v18, v19
100004084: 3d811532    	str	q18, [x9, #0x450]
100004088: 3dc13112    	ldr	q18, [x8, #0x4c0]
10000408c: 4fd09252    	fmul.2d	v18, v18, v16[0]
100004090: 3dc14913    	ldr	q19, [x8, #0x520]
100004094: 4fd19273    	fmul.2d	v19, v19, v17[0]
100004098: 4e73d652    	fadd.2d	v18, v18, v19
10000409c: 3dc16113    	ldr	q19, [x8, #0x580]
1000040a0: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000040a4: 4e73d652    	fadd.2d	v18, v18, v19
1000040a8: 3dc17913    	ldr	q19, [x8, #0x5e0]
1000040ac: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000040b0: 4e73d652    	fadd.2d	v18, v18, v19
1000040b4: 3dc19113    	ldr	q19, [x8, #0x640]
1000040b8: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000040bc: 4e73d652    	fadd.2d	v18, v18, v19
1000040c0: 3dc1a913    	ldr	q19, [x8, #0x6a0]
1000040c4: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000040c8: 4e73d652    	fadd.2d	v18, v18, v19
1000040cc: 3dc1c113    	ldr	q19, [x8, #0x700]
1000040d0: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000040d4: 4e73d652    	fadd.2d	v18, v18, v19
1000040d8: 3dc1d913    	ldr	q19, [x8, #0x760]
1000040dc: 4fc29273    	fmul.2d	v19, v19, v2[0]
1000040e0: 4e73d652    	fadd.2d	v18, v18, v19
1000040e4: 3dc1f113    	ldr	q19, [x8, #0x7c0]
1000040e8: 4fc19273    	fmul.2d	v19, v19, v1[0]
1000040ec: 4e73d652    	fadd.2d	v18, v18, v19
1000040f0: 3dc20913    	ldr	q19, [x8, #0x820]
1000040f4: 4fc09273    	fmul.2d	v19, v19, v0[0]
1000040f8: 4e73d652    	fadd.2d	v18, v18, v19
1000040fc: 3d811932    	str	q18, [x9, #0x460]
100004100: 3dc13512    	ldr	q18, [x8, #0x4d0]
100004104: 4fd09250    	fmul.2d	v16, v18, v16[0]
100004108: 3dc14d12    	ldr	q18, [x8, #0x530]
10000410c: 4fd19251    	fmul.2d	v17, v18, v17[0]
100004110: 4e71d610    	fadd.2d	v16, v16, v17
100004114: 3dc16511    	ldr	q17, [x8, #0x590]
100004118: 4fc79227    	fmul.2d	v7, v17, v7[0]
10000411c: 4e67d607    	fadd.2d	v7, v16, v7
100004120: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100004124: 4fc69206    	fmul.2d	v6, v16, v6[0]
100004128: 4e66d4e6    	fadd.2d	v6, v7, v6
10000412c: 3dc19507    	ldr	q7, [x8, #0x650]
100004130: 4fc590e5    	fmul.2d	v5, v7, v5[0]
100004134: 4e65d4c5    	fadd.2d	v5, v6, v5
100004138: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
10000413c: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100004140: 4e64d4a4    	fadd.2d	v4, v5, v4
100004144: 3dc1c505    	ldr	q5, [x8, #0x710]
100004148: 4fc390a3    	fmul.2d	v3, v5, v3[0]
10000414c: 4e63d483    	fadd.2d	v3, v4, v3
100004150: 3dc1dd04    	ldr	q4, [x8, #0x770]
100004154: 4fc29082    	fmul.2d	v2, v4, v2[0]
100004158: 4e62d462    	fadd.2d	v2, v3, v2
10000415c: 3dc1f503    	ldr	q3, [x8, #0x7d0]
100004160: 4fc19061    	fmul.2d	v1, v3, v1[0]
100004164: 4e61d441    	fadd.2d	v1, v2, v1
100004168: 3dc20d02    	ldr	q2, [x8, #0x830]
10000416c: 4fc09040    	fmul.2d	v0, v2, v0[0]
100004170: 4e60d420    	fadd.2d	v0, v1, v0
100004174: 3d811d20    	str	q0, [x9, #0x470]
100004178: 910f03ff    	add	sp, sp, #0x3c0
10000417c: a9457bfd    	ldp	x29, x30, [sp, #0x50]
100004180: a9446ffc    	ldp	x28, x27, [sp, #0x40]
100004184: 6d4323e9    	ldp	d9, d8, [sp, #0x30]
100004188: 6d422beb    	ldp	d11, d10, [sp, #0x20]
10000418c: 6d4133ed    	ldp	d13, d12, [sp, #0x10]
100004190: 6cc63bef    	ldp	d15, d14, [sp], #0x60
100004194: d65f03c0    	ret

0000000100004198 <_codegen_smul_add_semul3_12>:
100004198: a9be6ffc    	stp	x28, x27, [sp, #-0x20]!
10000419c: a9017bfd    	stp	x29, x30, [sp, #0x10]
1000041a0: 910043fd    	add	x29, sp, #0x10
1000041a4: d11203ff    	sub	sp, sp, #0x480
1000041a8: 910003e0    	mov	x0, sp
1000041ac: 9400000a    	bl	0x1000041d4 <_bench_primitives.smulAddSemul3_12>
1000041b0: 900000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000041b4: 91064000    	add	x0, x0, #0x190
1000041b8: 910003e1    	mov	x1, sp
1000041bc: 52809002    	mov	w2, #0x480              ; =1152
1000041c0: 94002b2a    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
1000041c4: 911203ff    	add	sp, sp, #0x480
1000041c8: a9417bfd    	ldp	x29, x30, [sp, #0x10]
1000041cc: a8c26ffc    	ldp	x28, x27, [sp], #0x20
1000041d0: d65f03c0    	ret

00000001000041d4 <_bench_primitives.smulAddSemul3_12>:
1000041d4: 6dba3bef    	stp	d15, d14, [sp, #-0x60]!
1000041d8: 6d0133ed    	stp	d13, d12, [sp, #0x10]
1000041dc: 6d022beb    	stp	d11, d10, [sp, #0x20]
1000041e0: 6d0323e9    	stp	d9, d8, [sp, #0x30]
1000041e4: a9046ffc    	stp	x28, x27, [sp, #0x40]
1000041e8: a9057bfd    	stp	x29, x30, [sp, #0x50]
1000041ec: 910143fd    	add	x29, sp, #0x50
1000041f0: d120c3ff    	sub	sp, sp, #0x830
1000041f4: 900000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000041f8: 91190108    	add	x8, x8, #0x640
1000041fc: fd40011e    	ldr	d30, [x8]
100004200: fd403519    	ldr	d25, [x8, #0x68]
100004204: 1e792bc0    	fadd	d0, d30, d25
100004208: fd40691d    	ldr	d29, [x8, #0xd0]
10000420c: 1e7d2800    	fadd	d0, d0, d29
100004210: fd409d1a    	ldr	d26, [x8, #0x138]
100004214: 1e7a2800    	fadd	d0, d0, d26
100004218: fd40d101    	ldr	d1, [x8, #0x1a0]
10000421c: 3d80a3e1    	str	q1, [sp, #0x280]
100004220: 1e612800    	fadd	d0, d0, d1
100004224: fd41051b    	ldr	d27, [x8, #0x208]
100004228: 1e7b2800    	fadd	d0, d0, d27
10000422c: fd413902    	ldr	d2, [x8, #0x270]
100004230: 3d80f3e2    	str	q2, [sp, #0x3c0]
100004234: 1e622800    	fadd	d0, d0, d2
100004238: fd416d0e    	ldr	d14, [x8, #0x2d8]
10000423c: 1e6e2800    	fadd	d0, d0, d14
100004240: fd41a102    	ldr	d2, [x8, #0x340]
100004244: 3d80cfe2    	str	q2, [sp, #0x330]
100004248: 1e622800    	fadd	d0, d0, d2
10000424c: fd41d502    	ldr	d2, [x8, #0x3a8]
100004250: 3d80d3e2    	str	q2, [sp, #0x340]
100004254: 1e622802    	fadd	d2, d0, d2
100004258: fd448112    	ldr	d18, [x8, #0x900]
10000425c: fd44b513    	ldr	d19, [x8, #0x968]
100004260: 1e732a40    	fadd	d0, d18, d19
100004264: fd44e905    	ldr	d5, [x8, #0x9d0]
100004268: 1e652800    	fadd	d0, d0, d5
10000426c: fd451d10    	ldr	d16, [x8, #0xa38]
100004270: 1e702800    	fadd	d0, d0, d16
100004274: fd455104    	ldr	d4, [x8, #0xaa0]
100004278: 4ea41c83    	mov.16b	v3, v4
10000427c: 1e642800    	fadd	d0, d0, d4
100004280: fd458506    	ldr	d6, [x8, #0xb08]
100004284: 1e662800    	fadd	d0, d0, d6
100004288: fd45b904    	ldr	d4, [x8, #0xb70]
10000428c: 3c9903a4    	stur	q4, [x29, #-0x70]
100004290: 1e642800    	fadd	d0, d0, d4
100004294: fd45ed04    	ldr	d4, [x8, #0xbd8]
100004298: 1e642800    	fadd	d0, d0, d4
10000429c: fd462107    	ldr	d7, [x8, #0xc40]
1000042a0: 3c9a03a7    	stur	q7, [x29, #-0x60]
1000042a4: 1e672807    	fadd	d7, d0, d7
1000042a8: fd465500    	ldr	d0, [x8, #0xca8]
1000042ac: 1e6028e7    	fadd	d7, d7, d0
1000042b0: 1e670842    	fmul	d2, d2, d7
1000042b4: 1e60c042    	fabs	d2, d2
1000042b8: d29d4228    	mov	x8, #0xea11             ; =59921
1000042bc: f2b025a8    	movk	x8, #0x812d, lsl #16
1000042c0: f2d2f328    	movk	x8, #0x9799, lsl #32
1000042c4: f2e7ae28    	movk	x8, #0x3d71, lsl #48
1000042c8: 9e670107    	fmov	d7, x8
1000042cc: 1e672040    	fcmp	d2, d7
1000042d0: 54013949    	b.ls	0x1000069f8 <_bench_primitives.smulAddSemul3_12+0x2824>
1000042d4: 1e720bc7    	fmul	d7, d30, d18
1000042d8: 900000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000042dc: 91192129    	add	x9, x9, #0x648
1000042e0: fd40012f    	ldr	d15, [x9]
1000042e4: fd44ad31    	ldr	d17, [x9, #0x958]
1000042e8: 4eb21e5c    	mov.16b	v28, v18
1000042ec: 3c9603b2    	stur	q18, [x29, #-0xa0]
1000042f0: 1e7109f2    	fmul	d18, d15, d17
1000042f4: fd448135    	ldr	d21, [x9, #0x900]
1000042f8: 1e750bd4    	fmul	d20, d30, d21
1000042fc: 4eb51ebf    	mov.16b	v31, v21
100004300: 1e6f0a75    	fmul	d21, d19, d15
100004304: 6e1806a7    	mov.d	v7[1], v21[0]
100004308: 6e180692    	mov.d	v18[1], v20[0]
10000430c: 4e72d4f2    	fadd.2d	v18, v7, v18
100004310: d100e128    	sub	x8, x9, #0x38
100004314: 3dc27d16    	ldr	q22, [x8, #0x9f0]
100004318: 3cc08127    	ldur	q7, [x9, #0x8]
10000431c: 4fc792d4    	fmul.2d	v20, v22, v7[0]
100004320: 4e74d652    	fadd.2d	v18, v18, v20
100004324: 3dc2950a    	ldr	q10, [x8, #0xa50]
100004328: 4fc79954    	fmul.2d	v20, v10, v7[1]
10000432c: 3d80ebf3    	str	q19, [sp, #0x3a0]
100004330: 3d81bfea    	str	q10, [sp, #0x6f0]
100004334: 3dc29915    	ldr	q21, [x8, #0xa60]
100004338: 6e180615    	mov.d	v21[1], v16[0]
10000433c: 4eb51eb7    	mov.16b	v23, v21
100004340: 4e74d650    	fadd.2d	v16, v18, v20
100004344: 3dc2ad01    	ldr	q1, [x8, #0xab0]
100004348: 3d8163e1    	str	q1, [sp, #0x580]
10000434c: 3cc18134    	ldur	q20, [x9, #0x18]
100004350: 4fd49032    	fmul.2d	v18, v1, v20[0]
100004354: 3dc2c515    	ldr	q21, [x8, #0xb10]
100004358: 3d812bf5    	str	q21, [sp, #0x4a0]
10000435c: 4fd49ab5    	fmul.2d	v21, v21, v20[1]
100004360: 4e72d610    	fadd.2d	v16, v16, v18
100004364: 4e75d610    	fadd.2d	v16, v16, v21
100004368: 3dc2cd12    	ldr	q18, [x8, #0xb30]
10000436c: 6e1804d2    	mov.d	v18[1], v6[0]
100004370: 4eb21e58    	mov.16b	v24, v18
100004374: 3dc2dd06    	ldr	q6, [x8, #0xb70]
100004378: 3c9003a6    	stur	q6, [x29, #-0x100]
10000437c: 3d8073ee    	str	q14, [sp, #0x1c0]
100004380: 3cc2812e    	ldur	q14, [x9, #0x28]
100004384: 4fce90c6    	fmul.2d	v6, v6, v14[0]
100004388: 4e66d606    	fadd.2d	v6, v16, v6
10000438c: 3dc2f502    	ldr	q2, [x8, #0xbd0]
100004390: 3d8117e2    	str	q2, [sp, #0x450]
100004394: 4fce9850    	fmul.2d	v16, v2, v14[1]
100004398: 4e70d4c6    	fadd.2d	v6, v6, v16
10000439c: 3dc30110    	ldr	q16, [x8, #0xc00]
1000043a0: 6e180490    	mov.d	v16[1], v4[0]
1000043a4: 3d809bfb    	str	q27, [sp, #0x260]
1000043a8: 4eb01e1b    	mov.16b	v27, v16
1000043ac: 3dc30d02    	ldr	q2, [x8, #0xc30]
1000043b0: 3d819fe2    	str	q2, [sp, #0x670]
1000043b4: 3cc38135    	ldur	q21, [x9, #0x38]
1000043b8: 4fd59044    	fmul.2d	v4, v2, v21[0]
1000043bc: 4e64d4c4    	fadd.2d	v4, v6, v4
1000043c0: 4ebe1fc6    	mov.16b	v6, v30
1000043c4: 6e1805e6    	mov.d	v6[1], v15[0]
1000043c8: 3dc32502    	ldr	q2, [x8, #0xc90]
1000043cc: 3c9703a2    	stur	q2, [x29, #-0x90]
1000043d0: 4fd59850    	fmul.2d	v16, v2, v21[1]
1000043d4: 4e70d490    	fadd.2d	v16, v4, v16
1000043d8: 4ebc1f84    	mov.16b	v4, v28
1000043dc: 6e1807e4    	mov.d	v4[1], v31[0]
1000043e0: f000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000043e4: 3dc35d52    	ldr	q18, [x10, #0xd70]
1000043e8: 6e72dcc6    	fmul.2d	v6, v6, v18
1000043ec: 3d815bf2    	str	q18, [sp, #0x560]
1000043f0: 4e66d486    	fadd.2d	v6, v4, v6
1000043f4: 4e66d606    	fadd.2d	v6, v16, v6
1000043f8: 3d80fbe6    	str	q6, [sp, #0x3e0]
1000043fc: 3dc33502    	ldr	q2, [x8, #0xcd0]
100004400: 6e180402    	mov.d	v2[1], v0[0]
100004404: 3d81dfe2    	str	q2, [sp, #0x770]
100004408: 6e18063f    	mov.d	v31[1], v17[0]
10000440c: 3d814fff    	str	q31, [sp, #0x530]
100004410: 6e180671    	mov.d	v17[1], v19[0]
100004414: 3cc58121    	ldur	q1, [x9, #0x58]
100004418: 4fc19080    	fmul.2d	v0, v4, v1[0]
10000441c: 4fd99224    	fmul.2d	v4, v17, v25[0]
100004420: 4e60d480    	fadd.2d	v0, v4, v0
100004424: 4ea11c24    	mov.16b	v4, v1
100004428: 4ea11c3f    	mov.16b	v31, v1
10000442c: 6e180724    	mov.d	v4[1], v25[0]
100004430: 6e72dc84    	fmul.2d	v4, v4, v18
100004434: 4e64d621    	fadd.2d	v1, v17, v4
100004438: 3c9803a1    	stur	q1, [x29, #-0x80]
10000443c: 3dc25112    	ldr	q18, [x8, #0x940]
100004440: 4fde9246    	fmul.2d	v6, v18, v30[0]
100004444: 3dc26904    	ldr	q4, [x8, #0x9a0]
100004448: 4fcf9090    	fmul.2d	v16, v4, v15[0]
10000444c: 3d80bffa    	str	q26, [sp, #0x2f0]
100004450: 3d81c3e4    	str	q4, [sp, #0x700]
100004454: 4e70d4c6    	fadd.2d	v6, v6, v16
100004458: 9127412a    	add	x10, x9, #0x9d0
10000445c: 4d408545    	ld1.d	{ v5 }[1], [x10]
100004460: 3d8137e5    	str	q5, [sp, #0x4d0]
100004464: 4fc790b0    	fmul.2d	v16, v5, v7[0]
100004468: 4e66d606    	fadd.2d	v6, v16, v6
10000446c: 3d811bf7    	str	q23, [sp, #0x460]
100004470: 4fc79af0    	fmul.2d	v16, v23, v7[1]
100004474: 4e66d606    	fadd.2d	v6, v16, v6
100004478: 3dc2b109    	ldr	q9, [x8, #0xac0]
10000447c: 4fd49130    	fmul.2d	v16, v9, v20[0]
100004480: 3d8107e9    	str	q9, [sp, #0x410]
100004484: 4e66d606    	fadd.2d	v6, v16, v6
100004488: 3dc2c90b    	ldr	q11, [x8, #0xb20]
10000448c: 4fd49970    	fmul.2d	v16, v11, v20[1]
100004490: 3d8147eb    	str	q11, [sp, #0x510]
100004494: 4e66d606    	fadd.2d	v6, v16, v6
100004498: 3dc2e108    	ldr	q8, [x8, #0xb80]
10000449c: 4fce9110    	fmul.2d	v16, v8, v14[0]
1000044a0: 3d81c7e8    	str	q8, [sp, #0x710]
1000044a4: 4e66d606    	fadd.2d	v6, v16, v6
1000044a8: 3dc2f911    	ldr	q17, [x8, #0xbe0]
1000044ac: 4fce9a30    	fmul.2d	v16, v17, v14[1]
1000044b0: 4eb91f3c    	mov.16b	v28, v25
1000044b4: 4eb11e39    	mov.16b	v25, v17
1000044b8: 3d81b7f1    	str	q17, [sp, #0x6d0]
1000044bc: 4e66d606    	fadd.2d	v6, v16, v6
1000044c0: 3dc31101    	ldr	q1, [x8, #0xc40]
1000044c4: 3d817fe1    	str	q1, [sp, #0x5f0]
1000044c8: 4eb51eb3    	mov.16b	v19, v21
1000044cc: 4fd59030    	fmul.2d	v16, v1, v21[0]
1000044d0: 4e66d606    	fadd.2d	v6, v16, v6
1000044d4: 3dc32901    	ldr	q1, [x8, #0xca0]
1000044d8: 3c9503a1    	stur	q1, [x29, #-0xb0]
1000044dc: 4fd59830    	fmul.2d	v16, v1, v21[1]
1000044e0: 4e66d606    	fadd.2d	v6, v16, v6
1000044e4: f000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000044e8: 3dc36150    	ldr	q16, [x10, #0xd80]
1000044ec: 3d8177f0    	str	q16, [sp, #0x5d0]
1000044f0: 6e70dcf0    	fmul.2d	v16, v7, v16
1000044f4: 3d813bf2    	str	q18, [sp, #0x4e0]
1000044f8: 4e70d650    	fadd.2d	v16, v18, v16
1000044fc: 4e66d606    	fadd.2d	v6, v16, v6
100004500: 3d804fe6    	str	q6, [sp, #0x130]
100004504: 9127012a    	add	x10, x9, #0x9c0
100004508: 4eb61ec6    	mov.16b	v6, v22
10000450c: 4d408546    	ld1.d	{ v6 }[1], [x10]
100004510: 3d810be6    	str	q6, [sp, #0x420]
100004514: 3cc68136    	ldur	q22, [x9, #0x68]
100004518: 4fd690c6    	fmul.2d	v6, v6, v22[0]
10000451c: 4e66d400    	fadd.2d	v0, v0, v6
100004520: 4fd69946    	fmul.2d	v6, v10, v22[1]
100004524: 4e66d400    	fadd.2d	v0, v0, v6
100004528: 4ebf1ff5    	mov.16b	v21, v31
10000452c: 4fdf9246    	fmul.2d	v6, v18, v31[0]
100004530: 4fdc9090    	fmul.2d	v16, v4, v28[0]
100004534: 4ebc1f81    	mov.16b	v1, v28
100004538: 4e66d606    	fadd.2d	v6, v16, v6
10000453c: 4fd690b0    	fmul.2d	v16, v5, v22[0]
100004540: 4e70d4c6    	fadd.2d	v6, v6, v16
100004544: 4fd69af0    	fmul.2d	v16, v23, v22[1]
100004548: 4e70d4c6    	fadd.2d	v6, v6, v16
10000454c: 3dc2551c    	ldr	q28, [x8, #0x950]
100004550: 4fde9390    	fmul.2d	v16, v28, v30[0]
100004554: 3dc26d04    	ldr	q4, [x8, #0x9b0]
100004558: 4fcf9091    	fmul.2d	v17, v4, v15[0]
10000455c: 3d812fe4    	str	q4, [sp, #0x4b0]
100004560: 4e71d610    	fadd.2d	v16, v16, v17
100004564: 3dc2850d    	ldr	q13, [x8, #0xa10]
100004568: 4fc791b1    	fmul.2d	v17, v13, v7[0]
10000456c: 4e71d610    	fadd.2d	v16, v16, v17
100004570: 3dc29d05    	ldr	q5, [x8, #0xa70]
100004574: 4fc798b1    	fmul.2d	v17, v5, v7[1]
100004578: 3d8193e5    	str	q5, [sp, #0x640]
10000457c: 4e71d610    	fadd.2d	v16, v16, v17
100004580: 912a812a    	add	x10, x9, #0xaa0
100004584: 4d408543    	ld1.d	{ v3 }[1], [x10]
100004588: 4fd49071    	fmul.2d	v17, v3, v20[0]
10000458c: 4ea31c7f    	mov.16b	v31, v3
100004590: 3d815fe3    	str	q3, [sp, #0x570]
100004594: 4e70d630    	fadd.2d	v16, v17, v16
100004598: 4eb81f12    	mov.16b	v18, v24
10000459c: 3d8143f8    	str	q24, [sp, #0x500]
1000045a0: 4fd49b11    	fmul.2d	v17, v24, v20[1]
1000045a4: 4e70d630    	fadd.2d	v16, v17, v16
1000045a8: 3dc2e50c    	ldr	q12, [x8, #0xb90]
1000045ac: 4fce9191    	fmul.2d	v17, v12, v14[0]
1000045b0: 3d8123ec    	str	q12, [sp, #0x480]
1000045b4: 4e70d630    	fadd.2d	v16, v17, v16
1000045b8: 3dc2fd17    	ldr	q23, [x8, #0xbf0]
1000045bc: 4fce9af1    	fmul.2d	v17, v23, v14[1]
1000045c0: 3d80e3fd    	str	q29, [sp, #0x380]
1000045c4: 4eb71efd    	mov.16b	v29, v23
1000045c8: 3d816bf7    	str	q23, [sp, #0x5a0]
1000045cc: 4e70d630    	fadd.2d	v16, v17, v16
1000045d0: 3dc31502    	ldr	q2, [x8, #0xc50]
1000045d4: 3d8187e2    	str	q2, [sp, #0x610]
1000045d8: 4fd39051    	fmul.2d	v17, v2, v19[0]
1000045dc: 4e70d630    	fadd.2d	v16, v17, v16
1000045e0: 3dc32d02    	ldr	q2, [x8, #0xcb0]
1000045e4: 3d81dbe2    	str	q2, [sp, #0x760]
1000045e8: 4fd39851    	fmul.2d	v17, v2, v19[1]
1000045ec: 4e70d630    	fadd.2d	v16, v17, v16
1000045f0: f000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
1000045f4: 3dc36542    	ldr	q2, [x10, #0xd90]
1000045f8: 3d8173e2    	str	q2, [sp, #0x5c0]
1000045fc: 6e62de91    	fmul.2d	v17, v20, v2
100004600: 3d810ffc    	str	q28, [sp, #0x430]
100004604: 4e71d791    	fadd.2d	v17, v28, v17
100004608: 4e70d630    	fadd.2d	v16, v17, v16
10000460c: 3d8103f0    	str	q16, [sp, #0x400]
100004610: 3cc78138    	ldur	q24, [x9, #0x78]
100004614: 3dc163e2    	ldr	q2, [sp, #0x580]
100004618: 4fd89050    	fmul.2d	v16, v2, v24[0]
10000461c: 4e70d400    	fadd.2d	v0, v0, v16
100004620: 3dc12be3    	ldr	q3, [sp, #0x4a0]
100004624: 4fd89870    	fmul.2d	v16, v3, v24[1]
100004628: 4e70d410    	fadd.2d	v16, v0, v16
10000462c: 4fd89120    	fmul.2d	v0, v9, v24[0]
100004630: 4e60d4c0    	fadd.2d	v0, v6, v0
100004634: 4fd89966    	fmul.2d	v6, v11, v24[1]
100004638: 4e66d406    	fadd.2d	v6, v0, v6
10000463c: 4fd59380    	fmul.2d	v0, v28, v21[0]
100004640: 3d80e7f5    	str	q21, [sp, #0x390]
100004644: 4ea11c3c    	mov.16b	v28, v1
100004648: 3d81afe1    	str	q1, [sp, #0x6b0]
10000464c: 4fc19091    	fmul.2d	v17, v4, v1[0]
100004650: 4e60d620    	fadd.2d	v0, v17, v0
100004654: 9127812a    	add	x10, x9, #0x9e0
100004658: 4d40854d    	ld1.d	{ v13 }[1], [x10]
10000465c: 3d8127ed    	str	q13, [sp, #0x490]
100004660: 4fd691b1    	fmul.2d	v17, v13, v22[0]
100004664: 4e71d400    	fadd.2d	v0, v0, v17
100004668: 4fd698b1    	fmul.2d	v17, v5, v22[1]
10000466c: 4e71d400    	fadd.2d	v0, v0, v17
100004670: 4fd893f1    	fmul.2d	v17, v31, v24[0]
100004674: 4e71d400    	fadd.2d	v0, v0, v17
100004678: 4fd89a51    	fmul.2d	v17, v18, v24[1]
10000467c: 4e71d411    	fadd.2d	v17, v0, v17
100004680: 3dc2590a    	ldr	q10, [x8, #0x960]
100004684: 4fde9140    	fmul.2d	v0, v10, v30[0]
100004688: 3dc27105    	ldr	q5, [x8, #0x9c0]
10000468c: 4fcf90b2    	fmul.2d	v18, v5, v15[0]
100004690: 4eaf1de4    	mov.16b	v4, v15
100004694: 4e72d412    	fadd.2d	v18, v0, v18
100004698: 3dc2891f    	ldr	q31, [x8, #0xa20]
10000469c: 4fc793f7    	fmul.2d	v23, v31, v7[0]
1000046a0: 4e77d652    	fadd.2d	v18, v18, v23
1000046a4: 3dc2a101    	ldr	q1, [x8, #0xa80]
1000046a8: 4fc79837    	fmul.2d	v23, v1, v7[1]
1000046ac: 3d81a3e1    	str	q1, [sp, #0x680]
1000046b0: 4e77d652    	fadd.2d	v18, v18, v23
1000046b4: 3dc2b90f    	ldr	q15, [x8, #0xae0]
1000046b8: 4eb41e9a    	mov.16b	v26, v20
1000046bc: 4fd491f7    	fmul.2d	v23, v15, v20[0]
1000046c0: 3d818fef    	str	q15, [sp, #0x630]
1000046c4: 4e77d652    	fadd.2d	v18, v18, v23
1000046c8: 3dc2d10d    	ldr	q13, [x8, #0xb40]
1000046cc: 4fd499b7    	fmul.2d	v23, v13, v20[1]
1000046d0: 3d81b3ed    	str	q13, [sp, #0x6c0]
1000046d4: 4e77d652    	fadd.2d	v18, v18, v23
1000046d8: 912dc12a    	add	x10, x9, #0xb70
1000046dc: 3cd903a0    	ldur	q0, [x29, #-0x70]
1000046e0: 4d408540    	ld1.d	{ v0 }[1], [x10]
1000046e4: 4fce9017    	fmul.2d	v23, v0, v14[0]
1000046e8: 4ea01c03    	mov.16b	v3, v0
1000046ec: 3c9903a0    	stur	q0, [x29, #-0x70]
1000046f0: 4e72d6f2    	fadd.2d	v18, v23, v18
1000046f4: 4ebb1f62    	mov.16b	v2, v27
1000046f8: 3d8113fb    	str	q27, [sp, #0x440]
1000046fc: 4fce9b77    	fmul.2d	v23, v27, v14[1]
100004700: 4e72d6f2    	fadd.2d	v18, v23, v18
100004704: 3dc3190b    	ldr	q11, [x8, #0xc60]
100004708: 4fd39177    	fmul.2d	v23, v11, v19[0]
10000470c: 3d8183eb    	str	q11, [sp, #0x600]
100004710: 4e72d6f2    	fadd.2d	v18, v23, v18
100004714: 3dc33109    	ldr	q9, [x8, #0xcc0]
100004718: 4fd39937    	fmul.2d	v23, v9, v19[1]
10000471c: 3c9403be    	stur	q30, [x29, #-0xc0]
100004720: 3c9103a9    	stur	q9, [x29, #-0xf0]
100004724: 4e72d6f2    	fadd.2d	v18, v23, v18
100004728: f000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000472c: 3dc36954    	ldr	q20, [x10, #0xda0]
100004730: 6e74ddd7    	fmul.2d	v23, v14, v20
100004734: 3c9203b4    	stur	q20, [x29, #-0xe0]
100004738: 3d8133ea    	str	q10, [sp, #0x4c0]
10000473c: 4e77d557    	fadd.2d	v23, v10, v23
100004740: 4e72d6e0    	fadd.2d	v0, v23, v18
100004744: 3d804be0    	str	q0, [sp, #0x120]
100004748: 3cc8813b    	ldur	q27, [x9, #0x88]
10000474c: 3cd003a0    	ldur	q0, [x29, #-0x100]
100004750: 4fdb9012    	fmul.2d	v18, v0, v27[0]
100004754: 4e72d610    	fadd.2d	v16, v16, v18
100004758: 3dc117e0    	ldr	q0, [sp, #0x450]
10000475c: 4fdb9812    	fmul.2d	v18, v0, v27[1]
100004760: 4e72d612    	fadd.2d	v18, v16, v18
100004764: 4fdb9110    	fmul.2d	v16, v8, v27[0]
100004768: 4e70d4c6    	fadd.2d	v6, v6, v16
10000476c: 4fdb9b30    	fmul.2d	v16, v25, v27[1]
100004770: 4e70d4d7    	fadd.2d	v23, v6, v16
100004774: 4fdb9186    	fmul.2d	v6, v12, v27[0]
100004778: 4e66d626    	fadd.2d	v6, v17, v6
10000477c: 4fdb9bb0    	fmul.2d	v16, v29, v27[1]
100004780: 4e70d4d1    	fadd.2d	v17, v6, v16
100004784: 4fd59146    	fmul.2d	v6, v10, v21[0]
100004788: 4fdc90b0    	fmul.2d	v16, v5, v28[0]
10000478c: 4e66d606    	fadd.2d	v6, v16, v6
100004790: 9127c12a    	add	x10, x9, #0x9f0
100004794: 4d40855f    	ld1.d	{ v31 }[1], [x10]
100004798: 3d8157ff    	str	q31, [sp, #0x550]
10000479c: 4fd693f0    	fmul.2d	v16, v31, v22[0]
1000047a0: 4e70d4c6    	fadd.2d	v6, v6, v16
1000047a4: 4fd69830    	fmul.2d	v16, v1, v22[1]
1000047a8: 4e70d4c6    	fadd.2d	v6, v6, v16
1000047ac: 4fd891f0    	fmul.2d	v16, v15, v24[0]
1000047b0: 4e70d4c6    	fadd.2d	v6, v6, v16
1000047b4: 4fd899b0    	fmul.2d	v16, v13, v24[1]
1000047b8: 4e70d4c6    	fadd.2d	v6, v6, v16
1000047bc: 4fdb9070    	fmul.2d	v16, v3, v27[0]
1000047c0: 4e70d4c6    	fadd.2d	v6, v6, v16
1000047c4: 4fdb9850    	fmul.2d	v16, v2, v27[1]
1000047c8: 4e70d4ca    	fadd.2d	v10, v6, v16
1000047cc: 3dc25d1c    	ldr	q28, [x8, #0x970]
1000047d0: 4fde9386    	fmul.2d	v6, v28, v30[0]
1000047d4: 3dc2751f    	ldr	q31, [x8, #0x9d0]
1000047d8: 4fc493f0    	fmul.2d	v16, v31, v4[0]
1000047dc: 4ea41c95    	mov.16b	v21, v4
1000047e0: 4e70d4c6    	fadd.2d	v6, v6, v16
1000047e4: 3dc28d00    	ldr	q0, [x8, #0xa30]
1000047e8: 4fc79010    	fmul.2d	v16, v0, v7[0]
1000047ec: 4e70d4c6    	fadd.2d	v6, v6, v16
1000047f0: 3dc2a502    	ldr	q2, [x8, #0xa90]
1000047f4: 4fc79850    	fmul.2d	v16, v2, v7[1]
1000047f8: 3d81cbe2    	str	q2, [sp, #0x720]
1000047fc: 4e70d4c6    	fadd.2d	v6, v6, v16
100004800: 3dc2bd01    	ldr	q1, [x8, #0xaf0]
100004804: 4fda9030    	fmul.2d	v16, v1, v26[0]
100004808: 3d81cfe1    	str	q1, [sp, #0x730]
10000480c: 4e70d4c6    	fadd.2d	v6, v6, v16
100004810: 3dc2d519    	ldr	q25, [x8, #0xb50]
100004814: 4fda9b30    	fmul.2d	v16, v25, v26[1]
100004818: 3d81abf9    	str	q25, [sp, #0x6a0]
10000481c: 4e70d4d0    	fadd.2d	v16, v6, v16
100004820: 3dc2ed08    	ldr	q8, [x8, #0xbb0]
100004824: 4fce911d    	fmul.2d	v29, v8, v14[0]
100004828: 3d818be8    	str	q8, [sp, #0x620]
10000482c: 4e7dd61d    	fadd.2d	v29, v16, v29
100004830: 3dc30510    	ldr	q16, [x8, #0xc10]
100004834: 4fce9a0c    	fmul.2d	v12, v16, v14[1]
100004838: 3c9303b0    	stur	q16, [x29, #-0xd0]
10000483c: 4e6cd7bd    	fadd.2d	v29, v29, v12
100004840: 9131012a    	add	x10, x9, #0xc40
100004844: 3cda03a3    	ldur	q3, [x29, #-0x60]
100004848: 4d408543    	ld1.d	{ v3 }[1], [x10]
10000484c: 4fd3906c    	fmul.2d	v12, v3, v19[0]
100004850: 4e7dd59d    	fadd.2d	v29, v12, v29
100004854: 3dc1dfe6    	ldr	q6, [sp, #0x770]
100004858: 4fd398cc    	fmul.2d	v12, v6, v19[1]
10000485c: 4e7dd59d    	fadd.2d	v29, v12, v29
100004860: f000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
100004864: 3dc36d4f    	ldr	q15, [x10, #0xdb0]
100004868: 6e6fde6c    	fmul.2d	v12, v19, v15
10000486c: 3d819bef    	str	q15, [sp, #0x660]
100004870: 3d813ffc    	str	q28, [sp, #0x4f0]
100004874: 4e6cd78c    	fadd.2d	v12, v28, v12
100004878: 4e7dd59d    	fadd.2d	v29, v12, v29
10000487c: 3d8043fd    	str	q29, [sp, #0x100]
100004880: 3cc9813d    	ldur	q29, [x9, #0x98]
100004884: 3dc19fe4    	ldr	q4, [sp, #0x670]
100004888: 4fdd908c    	fmul.2d	v12, v4, v29[0]
10000488c: 4e6cd652    	fadd.2d	v18, v18, v12
100004890: ad7b93ac    	ldp	q12, q4, [x29, #-0x90]
100004894: 4fdd998c    	fmul.2d	v12, v12, v29[1]
100004898: 4e6cd652    	fadd.2d	v18, v18, v12
10000489c: 4e72d484    	fadd.2d	v4, v4, v18
1000048a0: 3d80cbe4    	str	q4, [sp, #0x320]
1000048a4: 3dc17fec    	ldr	q12, [sp, #0x5f0]
1000048a8: 4fdd9184    	fmul.2d	v4, v12, v29[0]
1000048ac: 4e64d6e4    	fadd.2d	v4, v23, v4
1000048b0: 3cd503b2    	ldur	q18, [x29, #-0xb0]
1000048b4: 4fdd9a52    	fmul.2d	v18, v18, v29[1]
1000048b8: 4e72d484    	fadd.2d	v4, v4, v18
1000048bc: 3dc177f2    	ldr	q18, [sp, #0x5d0]
1000048c0: 6e72ded2    	fmul.2d	v18, v22, v18
1000048c4: 3dc1c3ed    	ldr	q13, [sp, #0x700]
1000048c8: 4e72d5b2    	fadd.2d	v18, v13, v18
1000048cc: 4e64d644    	fadd.2d	v4, v18, v4
1000048d0: 3d80ffe4    	str	q4, [sp, #0x3f0]
1000048d4: 3dc187e4    	ldr	q4, [sp, #0x610]
1000048d8: 4fdd9084    	fmul.2d	v4, v4, v29[0]
1000048dc: 4e64d624    	fadd.2d	v4, v17, v4
1000048e0: 3dc1dbf1    	ldr	q17, [sp, #0x760]
1000048e4: 4fdd9a31    	fmul.2d	v17, v17, v29[1]
1000048e8: 4e71d484    	fadd.2d	v4, v4, v17
1000048ec: 3dc173f1    	ldr	q17, [sp, #0x5c0]
1000048f0: 6e71df11    	fmul.2d	v17, v24, v17
1000048f4: 3dc12ff7    	ldr	q23, [sp, #0x4b0]
1000048f8: 4e71d6f1    	fadd.2d	v17, v23, v17
1000048fc: 4e64d624    	fadd.2d	v4, v17, v4
100004900: 3d8047e4    	str	q4, [sp, #0x110]
100004904: 4fdd9164    	fmul.2d	v4, v11, v29[0]
100004908: 4e64d544    	fadd.2d	v4, v10, v4
10000490c: 4fdd9931    	fmul.2d	v17, v9, v29[1]
100004910: 4e71d484    	fadd.2d	v4, v4, v17
100004914: 6e74df71    	fmul.2d	v17, v27, v20
100004918: 4e71d4b1    	fadd.2d	v17, v5, v17
10000491c: 4ea51caa    	mov.16b	v10, v5
100004920: 3d8153e5    	str	q5, [sp, #0x540]
100004924: 4e64d624    	fadd.2d	v4, v17, v4
100004928: 3d80f7e4    	str	q4, [sp, #0x3d0]
10000492c: 3dc0e7e9    	ldr	q9, [sp, #0x390]
100004930: 4fc99384    	fmul.2d	v4, v28, v9[0]
100004934: 3d8197ff    	str	q31, [sp, #0x650]
100004938: 3dc1affe    	ldr	q30, [sp, #0x6b0]
10000493c: 4fde93f1    	fmul.2d	v17, v31, v30[0]
100004940: 4e64d624    	fadd.2d	v4, v17, v4
100004944: 9128012a    	add	x10, x9, #0xa00
100004948: 4d408540    	ld1.d	{ v0 }[1], [x10]
10000494c: 3d8167e0    	str	q0, [sp, #0x590]
100004950: 4fd69011    	fmul.2d	v17, v0, v22[0]
100004954: 4e71d484    	fadd.2d	v4, v4, v17
100004958: 4fd69851    	fmul.2d	v17, v2, v22[1]
10000495c: 4e71d484    	fadd.2d	v4, v4, v17
100004960: 4fd89031    	fmul.2d	v17, v1, v24[0]
100004964: 4e71d484    	fadd.2d	v4, v4, v17
100004968: 4fd89b31    	fmul.2d	v17, v25, v24[1]
10000496c: 4e71d484    	fadd.2d	v4, v4, v17
100004970: 4fdb9111    	fmul.2d	v17, v8, v27[0]
100004974: 4e71d484    	fadd.2d	v4, v4, v17
100004978: 4fdb9a11    	fmul.2d	v17, v16, v27[1]
10000497c: 4e71d484    	fadd.2d	v4, v4, v17
100004980: 4fdd9071    	fmul.2d	v17, v3, v29[0]
100004984: 4e71d484    	fadd.2d	v4, v4, v17
100004988: 4fdd98d1    	fmul.2d	v17, v6, v29[1]
10000498c: 4e71d484    	fadd.2d	v4, v4, v17
100004990: 6e6fdfb1    	fmul.2d	v17, v29, v15
100004994: 4e71d7f1    	fadd.2d	v17, v31, v17
100004998: 4e64d620    	fadd.2d	v0, v17, v4
10000499c: 3d80efe0    	str	q0, [sp, #0x3b0]
1000049a0: 3dc2611f    	ldr	q31, [x8, #0x980]
1000049a4: 3cd403a1    	ldur	q1, [x29, #-0xc0]
1000049a8: 4fc193e1    	fmul.2d	v1, v31, v1[0]
1000049ac: 3dc27904    	ldr	q4, [x8, #0x9e0]
1000049b0: 4fd59082    	fmul.2d	v2, v4, v21[0]
1000049b4: 4e62d421    	fadd.2d	v1, v1, v2
1000049b8: 3dc2911c    	ldr	q28, [x8, #0xa40]
1000049bc: 4fc79382    	fmul.2d	v2, v28, v7[0]
1000049c0: 4e62d421    	fadd.2d	v1, v1, v2
1000049c4: 3dc2a914    	ldr	q20, [x8, #0xaa0]
1000049c8: 4fc79a82    	fmul.2d	v2, v20, v7[1]
1000049cc: 3d81d3f4    	str	q20, [sp, #0x740]
1000049d0: 4e62d421    	fadd.2d	v1, v1, v2
1000049d4: 3dc2c111    	ldr	q17, [x8, #0xb00]
1000049d8: 4fda9222    	fmul.2d	v2, v17, v26[0]
1000049dc: 3d81d7f1    	str	q17, [sp, #0x750]
1000049e0: 4e62d421    	fadd.2d	v1, v1, v2
1000049e4: 3dc2d910    	ldr	q16, [x8, #0xb60]
1000049e8: 4fda9a02    	fmul.2d	v2, v16, v26[1]
1000049ec: 4e62d421    	fadd.2d	v1, v1, v2
1000049f0: 3dc2f107    	ldr	q7, [x8, #0xbc0]
1000049f4: 4fce90e2    	fmul.2d	v2, v7, v14[0]
1000049f8: 3d81a7e7    	str	q7, [sp, #0x690]
1000049fc: 4e62d421    	fadd.2d	v1, v1, v2
100004a00: 3dc30912    	ldr	q18, [x8, #0xc20]
100004a04: 4fce9a42    	fmul.2d	v2, v18, v14[1]
100004a08: 3d816ff2    	str	q18, [sp, #0x5b0]
100004a0c: 4e62d422    	fadd.2d	v2, v1, v2
100004a10: 3dc32106    	ldr	q6, [x8, #0xc80]
100004a14: 4fd390ce    	fmul.2d	v14, v6, v19[0]
100004a18: 3c9403a6    	stur	q6, [x29, #-0xc0]
100004a1c: 4e6ed44e    	fadd.2d	v14, v2, v14
100004a20: 3dc33905    	ldr	q5, [x8, #0xce0]
100004a24: 4fd398b5    	fmul.2d	v21, v5, v19[1]
100004a28: 3c9803a5    	stur	q5, [x29, #-0x80]
100004a2c: 4e75d5d5    	fadd.2d	v21, v14, v21
100004a30: f000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
100004a34: 3cc4812e    	ldur	q14, [x9, #0x48]
100004a38: 3dc37141    	ldr	q1, [x10, #0xdc0]
100004a3c: 6e61ddce    	fmul.2d	v14, v14, v1
100004a40: 3d81bbe1    	str	q1, [sp, #0x6e0]
100004a44: 4e6ed7ee    	fadd.2d	v14, v31, v14
100004a48: 4e6ed6a2    	fadd.2d	v2, v21, v14
100004a4c: 3d803fe2    	str	q2, [sp, #0xf0]
100004a50: 4fc993f5    	fmul.2d	v21, v31, v9[0]
100004a54: 3d817bff    	str	q31, [sp, #0x5e0]
100004a58: 4fde9099    	fmul.2d	v25, v4, v30[0]
100004a5c: 4e75d735    	fadd.2d	v21, v25, v21
100004a60: 9128412a    	add	x10, x9, #0xa10
100004a64: 4d40855c    	ld1.d	{ v28 }[1], [x10]
100004a68: 3d81affc    	str	q28, [sp, #0x6b0]
100004a6c: 4fd69399    	fmul.2d	v25, v28, v22[0]
100004a70: 4e79d6b5    	fadd.2d	v21, v21, v25
100004a74: 4fd69a96    	fmul.2d	v22, v20, v22[1]
100004a78: 4e76d6b5    	fadd.2d	v21, v21, v22
100004a7c: 4fd89236    	fmul.2d	v22, v17, v24[0]
100004a80: 4e76d6b5    	fadd.2d	v21, v21, v22
100004a84: 4fd89a16    	fmul.2d	v22, v16, v24[1]
100004a88: 4eb01e14    	mov.16b	v20, v16
100004a8c: 3d811ff0    	str	q16, [sp, #0x470]
100004a90: 4e76d6b5    	fadd.2d	v21, v21, v22
100004a94: 4fdb90f6    	fmul.2d	v22, v7, v27[0]
100004a98: 4e76d6b5    	fadd.2d	v21, v21, v22
100004a9c: 4fdb9a56    	fmul.2d	v22, v18, v27[1]
100004aa0: 4e76d6b5    	fadd.2d	v21, v21, v22
100004aa4: 4fdd90d6    	fmul.2d	v22, v6, v29[0]
100004aa8: 4e76d6b5    	fadd.2d	v21, v21, v22
100004aac: 4fdd98b6    	fmul.2d	v22, v5, v29[1]
100004ab0: 4e76d6b5    	fadd.2d	v21, v21, v22
100004ab4: 3cca8136    	ldur	q22, [x9, #0xa8]
100004ab8: 6e61ded6    	fmul.2d	v22, v22, v1
100004abc: 4e76d496    	fadd.2d	v22, v4, v22
100004ac0: 4ea41c9c    	mov.16b	v28, v4
100004ac4: 3d814be4    	str	q4, [sp, #0x520]
100004ac8: 4e76d6a0    	fadd.2d	v0, v21, v22
100004acc: 3d803be0    	str	q0, [sp, #0xe0]
100004ad0: 3cd603a0    	ldur	q0, [x29, #-0xa0]
100004ad4: 3dc0ebe1    	ldr	q1, [sp, #0x3a0]
100004ad8: 6e180420    	mov.d	v0[1], v1[0]
100004adc: 3c9603a0    	stur	q0, [x29, #-0xa0]
100004ae0: 3ccb8135    	ldur	q21, [x9, #0xb8]
100004ae4: 3dc14fe4    	ldr	q4, [sp, #0x530]
100004ae8: 6e75dc96    	fmul.2d	v22, v4, v21
100004aec: 6e1642d6    	ext.16b	v22, v22, v22, #0x8
100004af0: 6e75dc18    	fmul.2d	v24, v0, v21
100004af4: 4e78d6d6    	fadd.2d	v22, v22, v24
100004af8: 3dc10be0    	ldr	q0, [sp, #0x420]
100004afc: 3dc0e3e2    	ldr	q2, [sp, #0x380]
100004b00: 4fc29018    	fmul.2d	v24, v0, v2[0]
100004b04: 4e76d718    	fadd.2d	v24, v24, v22
100004b08: fd406936    	ldr	d22, [x9, #0xd0]
100004b0c: 3dc1bfe1    	ldr	q1, [sp, #0x6f0]
100004b10: 4fd69039    	fmul.2d	v25, v1, v22[0]
100004b14: 4e78d739    	fadd.2d	v25, v25, v24
100004b18: 3dc13bf1    	ldr	q17, [sp, #0x4e0]
100004b1c: 4fd59238    	fmul.2d	v24, v17, v21[0]
100004b20: 4fd599bb    	fmul.2d	v27, v13, v21[1]
100004b24: 4e7bd718    	fadd.2d	v24, v24, v27
100004b28: 3dc137fa    	ldr	q26, [sp, #0x4d0]
100004b2c: 4fc2935b    	fmul.2d	v27, v26, v2[0]
100004b30: 4e78d778    	fadd.2d	v24, v27, v24
100004b34: 3dc11be1    	ldr	q1, [sp, #0x460]
100004b38: 4fd6903b    	fmul.2d	v27, v1, v22[0]
100004b3c: 4e78d77b    	fadd.2d	v27, v27, v24
100004b40: 3ccd8138    	ldur	q24, [x9, #0xd8]
100004b44: 3dc163e8    	ldr	q8, [sp, #0x580]
100004b48: 4fd8911d    	fmul.2d	v29, v8, v24[0]
100004b4c: 4e79d7b9    	fadd.2d	v25, v29, v25
100004b50: 3dc12be1    	ldr	q1, [sp, #0x4a0]
100004b54: 4fd8983d    	fmul.2d	v29, v1, v24[1]
100004b58: 4e79d7bd    	fadd.2d	v29, v29, v25
100004b5c: 3dc107e7    	ldr	q7, [sp, #0x410]
100004b60: 4fd890f9    	fmul.2d	v25, v7, v24[0]
100004b64: 4e7bd739    	fadd.2d	v25, v25, v27
100004b68: 3dc147e1    	ldr	q1, [sp, #0x510]
100004b6c: 4fd8983b    	fmul.2d	v27, v1, v24[1]
100004b70: 4e79d77b    	fadd.2d	v27, v27, v25
100004b74: 3dc10ff2    	ldr	q18, [sp, #0x430]
100004b78: 4fd59259    	fmul.2d	v25, v18, v21[0]
100004b7c: 4fd59ae9    	fmul.2d	v9, v23, v21[1]
100004b80: 4e69d739    	fadd.2d	v25, v25, v9
100004b84: 3dc127e1    	ldr	q1, [sp, #0x490]
100004b88: 4fc29029    	fmul.2d	v9, v1, v2[0]
100004b8c: 4e79d539    	fadd.2d	v25, v9, v25
100004b90: 3dc193e5    	ldr	q5, [sp, #0x640]
100004b94: 4fd690a9    	fmul.2d	v9, v5, v22[0]
100004b98: 4e79d539    	fadd.2d	v25, v9, v25
100004b9c: 3dc15fe5    	ldr	q5, [sp, #0x570]
100004ba0: 4fd890a9    	fmul.2d	v9, v5, v24[0]
100004ba4: 4e79d539    	fadd.2d	v25, v9, v25
100004ba8: 3dc143f0    	ldr	q16, [sp, #0x500]
100004bac: 4fd89a09    	fmul.2d	v9, v16, v24[1]
100004bb0: 4e79d529    	fadd.2d	v9, v9, v25
100004bb4: 3cce8139    	ldur	q25, [x9, #0xe8]
100004bb8: 3cd003a5    	ldur	q5, [x29, #-0x100]
100004bbc: 4fd990ab    	fmul.2d	v11, v5, v25[0]
100004bc0: 4e7dd57d    	fadd.2d	v29, v11, v29
100004bc4: 3dc117e5    	ldr	q5, [sp, #0x450]
100004bc8: 4fd998ab    	fmul.2d	v11, v5, v25[1]
100004bcc: 4e7dd57d    	fadd.2d	v29, v11, v29
100004bd0: 3dc1c7e5    	ldr	q5, [sp, #0x710]
100004bd4: 4fd990ab    	fmul.2d	v11, v5, v25[0]
100004bd8: 4e7bd57b    	fadd.2d	v27, v11, v27
100004bdc: 3dc1b7e5    	ldr	q5, [sp, #0x6d0]
100004be0: 4fd998ab    	fmul.2d	v11, v5, v25[1]
100004be4: 4e7bd56b    	fadd.2d	v11, v11, v27
100004be8: 3dc123f3    	ldr	q19, [sp, #0x480]
100004bec: 4fd9927b    	fmul.2d	v27, v19, v25[0]
100004bf0: 4e69d77b    	fadd.2d	v27, v27, v9
100004bf4: 3dc16be5    	ldr	q5, [sp, #0x5a0]
100004bf8: 4fd998a9    	fmul.2d	v9, v5, v25[1]
100004bfc: 4e7bd529    	fadd.2d	v9, v9, v27
100004c00: 3dc133fe    	ldr	q30, [sp, #0x4c0]
100004c04: 4fd593db    	fmul.2d	v27, v30, v21[0]
100004c08: 4fd5994e    	fmul.2d	v14, v10, v21[1]
100004c0c: 4e6ed77b    	fadd.2d	v27, v27, v14
100004c10: 3dc157e5    	ldr	q5, [sp, #0x550]
100004c14: 4fc290ae    	fmul.2d	v14, v5, v2[0]
100004c18: 4e7bd5db    	fadd.2d	v27, v14, v27
100004c1c: 3dc1a3e6    	ldr	q6, [sp, #0x680]
100004c20: 4fd690ce    	fmul.2d	v14, v6, v22[0]
100004c24: 4e7bd5db    	fadd.2d	v27, v14, v27
100004c28: 3dc18fe6    	ldr	q6, [sp, #0x630]
100004c2c: 4fd890ce    	fmul.2d	v14, v6, v24[0]
100004c30: 4e7bd5db    	fadd.2d	v27, v14, v27
100004c34: 3dc1b3e6    	ldr	q6, [sp, #0x6c0]
100004c38: 4fd898ce    	fmul.2d	v14, v6, v24[1]
100004c3c: 4e7bd5db    	fadd.2d	v27, v14, v27
100004c40: 3cd903a6    	ldur	q6, [x29, #-0x70]
100004c44: 4fd990ce    	fmul.2d	v14, v6, v25[0]
100004c48: 4e7bd5db    	fadd.2d	v27, v14, v27
100004c4c: 3dc113e6    	ldr	q6, [sp, #0x440]
100004c50: 4fd998ce    	fmul.2d	v14, v6, v25[1]
100004c54: 4e7bd5ce    	fadd.2d	v14, v14, v27
100004c58: 3ccf813b    	ldur	q27, [x9, #0xf8]
100004c5c: 4ea31c6a    	mov.16b	v10, v3
100004c60: 3c9a03a3    	stur	q3, [x29, #-0x60]
100004c64: 3dc19fe3    	ldr	q3, [sp, #0x670]
100004c68: 4fdb906f    	fmul.2d	v15, v3, v27[0]
100004c6c: 4e7dd5fd    	fadd.2d	v29, v15, v29
100004c70: 3cd703a3    	ldur	q3, [x29, #-0x90]
100004c74: 4fdb986f    	fmul.2d	v15, v3, v27[1]
100004c78: 4e7dd5fd    	fadd.2d	v29, v15, v29
100004c7c: 3dc15be3    	ldr	q3, [sp, #0x560]
100004c80: 6e63deaf    	fmul.2d	v15, v21, v3
100004c84: 4e6fd40f    	fadd.2d	v15, v0, v15
100004c88: 4ea01c03    	mov.16b	v3, v0
100004c8c: 4e7dd5e0    	fadd.2d	v0, v15, v29
100004c90: 3d80b7e0    	str	q0, [sp, #0x2d0]
100004c94: 4fdb919d    	fmul.2d	v29, v12, v27[0]
100004c98: 4e6bd7bd    	fadd.2d	v29, v29, v11
100004c9c: 3cd503a0    	ldur	q0, [x29, #-0xb0]
100004ca0: 4fdb980b    	fmul.2d	v11, v0, v27[1]
100004ca4: 4e7dd57d    	fadd.2d	v29, v11, v29
100004ca8: 4ea21c4b    	mov.16b	v11, v2
100004cac: 6e1806cb    	mov.d	v11[1], v22[0]
100004cb0: 3dc177e0    	ldr	q0, [sp, #0x5d0]
100004cb4: 6e60dd6b    	fmul.2d	v11, v11, v0
100004cb8: 4e6bd74b    	fadd.2d	v11, v26, v11
100004cbc: 4eba1f4c    	mov.16b	v12, v26
100004cc0: 4e7dd566    	fadd.2d	v6, v11, v29
100004cc4: 3dc187fa    	ldr	q26, [sp, #0x610]
100004cc8: 4fdb935d    	fmul.2d	v29, v26, v27[0]
100004ccc: 4e69d7bd    	fadd.2d	v29, v29, v9
100004cd0: 3dc1dbe0    	ldr	q0, [sp, #0x760]
100004cd4: 4fdb9809    	fmul.2d	v9, v0, v27[1]
100004cd8: 4e7dd53d    	fadd.2d	v29, v9, v29
100004cdc: 3dc173e0    	ldr	q0, [sp, #0x5c0]
100004ce0: 6e60df09    	fmul.2d	v9, v24, v0
100004ce4: 4e69d429    	fadd.2d	v9, v1, v9
100004ce8: 4ea11c2b    	mov.16b	v11, v1
100004cec: 4e7dd520    	fadd.2d	v0, v9, v29
100004cf0: ad1c9be0    	stp	q0, q6, [sp, #0x390]
100004cf4: 3dc183e6    	ldr	q6, [sp, #0x600]
100004cf8: 4fdb90dd    	fmul.2d	v29, v6, v27[0]
100004cfc: 4e6ed7bd    	fadd.2d	v29, v29, v14
100004d00: 3cd103a0    	ldur	q0, [x29, #-0xf0]
100004d04: 4fdb9809    	fmul.2d	v9, v0, v27[1]
100004d08: 4e7dd53d    	fadd.2d	v29, v9, v29
100004d0c: 3cd203a0    	ldur	q0, [x29, #-0xe0]
100004d10: 6e60df29    	fmul.2d	v9, v25, v0
100004d14: 4e69d4a9    	fadd.2d	v9, v5, v9
100004d18: 4e7dd520    	fadd.2d	v0, v9, v29
100004d1c: 3d80dfe0    	str	q0, [sp, #0x370]
100004d20: 3dc13fe0    	ldr	q0, [sp, #0x4f0]
100004d24: 4fd5901d    	fmul.2d	v29, v0, v21[0]
100004d28: 3dc197ef    	ldr	q15, [sp, #0x650]
100004d2c: 4fd599e9    	fmul.2d	v9, v15, v21[1]
100004d30: 4e69d7bd    	fadd.2d	v29, v29, v9
100004d34: 3dc167e1    	ldr	q1, [sp, #0x590]
100004d38: 4fc29029    	fmul.2d	v9, v1, v2[0]
100004d3c: 4e7dd53d    	fadd.2d	v29, v9, v29
100004d40: 3dc1cbe0    	ldr	q0, [sp, #0x720]
100004d44: 4fd69009    	fmul.2d	v9, v0, v22[0]
100004d48: 4e7dd53d    	fadd.2d	v29, v9, v29
100004d4c: 3dc1cfe0    	ldr	q0, [sp, #0x730]
100004d50: 4fd89009    	fmul.2d	v9, v0, v24[0]
100004d54: 4e7dd53d    	fadd.2d	v29, v9, v29
100004d58: 3dc1abe0    	ldr	q0, [sp, #0x6a0]
100004d5c: 4fd89809    	fmul.2d	v9, v0, v24[1]
100004d60: 4e7dd53d    	fadd.2d	v29, v9, v29
100004d64: 3dc18bed    	ldr	q13, [sp, #0x620]
100004d68: 4fd991a9    	fmul.2d	v9, v13, v25[0]
100004d6c: 4e7dd53d    	fadd.2d	v29, v9, v29
100004d70: 3cd303a0    	ldur	q0, [x29, #-0xd0]
100004d74: 4fd99809    	fmul.2d	v9, v0, v25[1]
100004d78: 4e7dd53d    	fadd.2d	v29, v9, v29
100004d7c: 4fdb9149    	fmul.2d	v9, v10, v27[0]
100004d80: 4e7dd53d    	fadd.2d	v29, v9, v29
100004d84: 3dc1dfe0    	ldr	q0, [sp, #0x770]
100004d88: 4fdb9809    	fmul.2d	v9, v0, v27[1]
100004d8c: 4e7dd53d    	fadd.2d	v29, v9, v29
100004d90: 3dc19bea    	ldr	q10, [sp, #0x660]
100004d94: 6e6adf69    	fmul.2d	v9, v27, v10
100004d98: 4e69d429    	fadd.2d	v9, v1, v9
100004d9c: 4e7dd520    	fadd.2d	v0, v9, v29
100004da0: 3d80dbe0    	str	q0, [sp, #0x360]
100004da4: 4fd593fd    	fmul.2d	v29, v31, v21[0]
100004da8: 4fd59b95    	fmul.2d	v21, v28, v21[1]
100004dac: 4e75d7b5    	fadd.2d	v21, v29, v21
100004db0: 3dc1afe1    	ldr	q1, [sp, #0x6b0]
100004db4: 4fc2903d    	fmul.2d	v29, v1, v2[0]
100004db8: 4e75d7b5    	fadd.2d	v21, v29, v21
100004dbc: 3dc1d3e0    	ldr	q0, [sp, #0x740]
100004dc0: 4fd69016    	fmul.2d	v22, v0, v22[0]
100004dc4: 4e75d6d5    	fadd.2d	v21, v22, v21
100004dc8: 3dc1d7e0    	ldr	q0, [sp, #0x750]
100004dcc: 4fd89016    	fmul.2d	v22, v0, v24[0]
100004dd0: 4e75d6d5    	fadd.2d	v21, v22, v21
100004dd4: 4fd89a96    	fmul.2d	v22, v20, v24[1]
100004dd8: 4e75d6d5    	fadd.2d	v21, v22, v21
100004ddc: 3dc1a7e0    	ldr	q0, [sp, #0x690]
100004de0: 4fd99016    	fmul.2d	v22, v0, v25[0]
100004de4: 4e75d6d5    	fadd.2d	v21, v22, v21
100004de8: 3dc16ff4    	ldr	q20, [sp, #0x5b0]
100004dec: 4fd99a96    	fmul.2d	v22, v20, v25[1]
100004df0: 4e75d6d5    	fadd.2d	v21, v22, v21
100004df4: 3cd403a0    	ldur	q0, [x29, #-0xc0]
100004df8: 4fdb9016    	fmul.2d	v22, v0, v27[0]
100004dfc: 4e75d6d5    	fadd.2d	v21, v22, v21
100004e00: 3cd803a0    	ldur	q0, [x29, #-0x80]
100004e04: 4fdb9816    	fmul.2d	v22, v0, v27[1]
100004e08: 4e75d6d6    	fadd.2d	v22, v22, v21
100004e0c: ad4a5518    	ldp	q24, q21, [x8, #0x140]
100004e10: 3dc1bbfc    	ldr	q28, [sp, #0x6e0]
100004e14: 6e7cdf18    	fmul.2d	v24, v24, v28
100004e18: 4e78d438    	fadd.2d	v24, v1, v24
100004e1c: 4e78d6c0    	fadd.2d	v0, v22, v24
100004e20: 3d8037e0    	str	q0, [sp, #0xd0]
100004e24: 6e75dc96    	fmul.2d	v22, v4, v21
100004e28: 6e1642d6    	ext.16b	v22, v22, v22, #0x8
100004e2c: 3cd603a0    	ldur	q0, [x29, #-0xa0]
100004e30: 6e75dc18    	fmul.2d	v24, v0, v21
100004e34: 4e78d6d9    	fadd.2d	v25, v22, v24
100004e38: ad4b6116    	ldp	q22, q24, [x8, #0x160]
100004e3c: 4fd6907b    	fmul.2d	v27, v3, v22[0]
100004e40: 4e7bd739    	fadd.2d	v25, v25, v27
100004e44: 3dc1bff7    	ldr	q23, [sp, #0x6f0]
100004e48: 3dc0bfe1    	ldr	q1, [sp, #0x2f0]
100004e4c: 4fc192fb    	fmul.2d	v27, v23, v1[0]
100004e50: 4e79d779    	fadd.2d	v25, v27, v25
100004e54: 4fd5923b    	fmul.2d	v27, v17, v21[0]
100004e58: 3dc1c3e0    	ldr	q0, [sp, #0x700]
100004e5c: 4fd5981d    	fmul.2d	v29, v0, v21[1]
100004e60: 4e7dd77b    	fadd.2d	v27, v27, v29
100004e64: 4fd6919d    	fmul.2d	v29, v12, v22[0]
100004e68: 4e7dd77b    	fadd.2d	v27, v27, v29
100004e6c: 3dc11be2    	ldr	q2, [sp, #0x460]
100004e70: 4fc1905d    	fmul.2d	v29, v2, v1[0]
100004e74: 4e7bd7bb    	fadd.2d	v27, v29, v27
100004e78: 4fd8911d    	fmul.2d	v29, v8, v24[0]
100004e7c: 4e79d7b9    	fadd.2d	v25, v29, v25
100004e80: 3dc12bff    	ldr	q31, [sp, #0x4a0]
100004e84: 4fd89bfd    	fmul.2d	v29, v31, v24[1]
100004e88: 4e79d7bd    	fadd.2d	v29, v29, v25
100004e8c: 4fd890f9    	fmul.2d	v25, v7, v24[0]
100004e90: 4e7bd739    	fadd.2d	v25, v25, v27
100004e94: 3dc147e5    	ldr	q5, [sp, #0x510]
100004e98: 4fd898bb    	fmul.2d	v27, v5, v24[1]
100004e9c: 4e79d768    	fadd.2d	v8, v27, v25
100004ea0: 4fd59259    	fmul.2d	v25, v18, v21[0]
100004ea4: 3dc12fe0    	ldr	q0, [sp, #0x4b0]
100004ea8: 4fd5981b    	fmul.2d	v27, v0, v21[1]
100004eac: 4e7bd739    	fadd.2d	v25, v25, v27
100004eb0: 4fd6917b    	fmul.2d	v27, v11, v22[0]
100004eb4: 4e7bd739    	fadd.2d	v25, v25, v27
100004eb8: 3dc193e4    	ldr	q4, [sp, #0x640]
100004ebc: 4fc1909b    	fmul.2d	v27, v4, v1[0]
100004ec0: 4e79d779    	fadd.2d	v25, v27, v25
100004ec4: 3dc15fe0    	ldr	q0, [sp, #0x570]
100004ec8: 4fd8901b    	fmul.2d	v27, v0, v24[0]
100004ecc: 4e79d779    	fadd.2d	v25, v27, v25
100004ed0: 4fd89a1b    	fmul.2d	v27, v16, v24[1]
100004ed4: 4e79d769    	fadd.2d	v9, v27, v25
100004ed8: ad4c6d19    	ldp	q25, q27, [x8, #0x180]
100004edc: 3cd003a0    	ldur	q0, [x29, #-0x100]
100004ee0: 4fd9900b    	fmul.2d	v11, v0, v25[0]
100004ee4: 4e7dd57d    	fadd.2d	v29, v11, v29
100004ee8: 3dc117ec    	ldr	q12, [sp, #0x450]
100004eec: 4fd9998b    	fmul.2d	v11, v12, v25[1]
100004ef0: 4e7dd57d    	fadd.2d	v29, v11, v29
100004ef4: 3dc1c7e0    	ldr	q0, [sp, #0x710]
100004ef8: 4fd9900b    	fmul.2d	v11, v0, v25[0]
100004efc: 4e68d568    	fadd.2d	v8, v11, v8
100004f00: 3dc1b7e0    	ldr	q0, [sp, #0x6d0]
100004f04: 4fd9980b    	fmul.2d	v11, v0, v25[1]
100004f08: 4e68d568    	fadd.2d	v8, v11, v8
100004f0c: 4fd9926b    	fmul.2d	v11, v19, v25[0]
100004f10: 4e69d569    	fadd.2d	v9, v11, v9
100004f14: 3dc16be0    	ldr	q0, [sp, #0x5a0]
100004f18: 4fd9980b    	fmul.2d	v11, v0, v25[1]
100004f1c: 4e69d569    	fadd.2d	v9, v11, v9
100004f20: 4fd593cb    	fmul.2d	v11, v30, v21[0]
100004f24: 3dc153e0    	ldr	q0, [sp, #0x540]
100004f28: 4fd5980e    	fmul.2d	v14, v0, v21[1]
100004f2c: 4e6ed56b    	fadd.2d	v11, v11, v14
100004f30: 3dc157e7    	ldr	q7, [sp, #0x550]
100004f34: 4fd690ee    	fmul.2d	v14, v7, v22[0]
100004f38: 4e6ed56b    	fadd.2d	v11, v11, v14
100004f3c: 3dc1a3fe    	ldr	q30, [sp, #0x680]
100004f40: 4fc193ce    	fmul.2d	v14, v30, v1[0]
100004f44: 4e6bd5cb    	fadd.2d	v11, v14, v11
100004f48: 3dc18fe0    	ldr	q0, [sp, #0x630]
100004f4c: 4fd8900e    	fmul.2d	v14, v0, v24[0]
100004f50: 4e6bd5cb    	fadd.2d	v11, v14, v11
100004f54: 3dc1b3e0    	ldr	q0, [sp, #0x6c0]
100004f58: 4fd8980e    	fmul.2d	v14, v0, v24[1]
100004f5c: 4e6bd5cb    	fadd.2d	v11, v14, v11
100004f60: 3cd903a0    	ldur	q0, [x29, #-0x70]
100004f64: 4fd9900e    	fmul.2d	v14, v0, v25[0]
100004f68: 4e6bd5cb    	fadd.2d	v11, v14, v11
100004f6c: 3dc113f1    	ldr	q17, [sp, #0x440]
100004f70: 4fd99a2e    	fmul.2d	v14, v17, v25[1]
100004f74: 4e6bd5cb    	fadd.2d	v11, v14, v11
100004f78: 3dc19ff3    	ldr	q19, [sp, #0x670]
100004f7c: 4fdb926e    	fmul.2d	v14, v19, v27[0]
100004f80: 4e7dd5dd    	fadd.2d	v29, v14, v29
100004f84: 3cd703a0    	ldur	q0, [x29, #-0x90]
100004f88: 4fdb980e    	fmul.2d	v14, v0, v27[1]
100004f8c: 4e7dd5dd    	fadd.2d	v29, v14, v29
100004f90: 3dc15be0    	ldr	q0, [sp, #0x560]
100004f94: 6e60deae    	fmul.2d	v14, v21, v0
100004f98: 4e6ed6ee    	fadd.2d	v14, v23, v14
100004f9c: 4eb71ef2    	mov.16b	v18, v23
100004fa0: 4e7dd5c0    	fadd.2d	v0, v14, v29
100004fa4: 3d80e3e0    	str	q0, [sp, #0x380]
100004fa8: 3dc17fe0    	ldr	q0, [sp, #0x5f0]
100004fac: 4fdb901d    	fmul.2d	v29, v0, v27[0]
100004fb0: 4e68d7bd    	fadd.2d	v29, v29, v8
100004fb4: 3cd503a0    	ldur	q0, [x29, #-0xb0]
100004fb8: 4fdb9808    	fmul.2d	v8, v0, v27[1]
100004fbc: 4e7dd51d    	fadd.2d	v29, v8, v29
100004fc0: 4eb61ec8    	mov.16b	v8, v22
100004fc4: 6e180428    	mov.d	v8[1], v1[0]
100004fc8: 3dc177f0    	ldr	q16, [sp, #0x5d0]
100004fcc: 6e70dd08    	fmul.2d	v8, v8, v16
100004fd0: 4e68d448    	fadd.2d	v8, v2, v8
100004fd4: 4e7dd500    	fadd.2d	v0, v8, v29
100004fd8: 3d80d7e0    	str	q0, [sp, #0x350]
100004fdc: 4fdb935d    	fmul.2d	v29, v26, v27[0]
100004fe0: 4e69d7bd    	fadd.2d	v29, v29, v9
100004fe4: 3dc1dbee    	ldr	q14, [sp, #0x760]
100004fe8: 4fdb99c8    	fmul.2d	v8, v14, v27[1]
100004fec: 4e7dd51d    	fadd.2d	v29, v8, v29
100004ff0: 3dc173f7    	ldr	q23, [sp, #0x5c0]
100004ff4: 6e77df08    	fmul.2d	v8, v24, v23
100004ff8: 4e68d488    	fadd.2d	v8, v4, v8
100004ffc: 4ea41c89    	mov.16b	v9, v4
100005000: 4e7dd500    	fadd.2d	v0, v8, v29
100005004: 3d8033e0    	str	q0, [sp, #0xc0]
100005008: 4fdb90dd    	fmul.2d	v29, v6, v27[0]
10000500c: 4e6bd7bd    	fadd.2d	v29, v29, v11
100005010: ad7883a6    	ldp	q6, q0, [x29, #-0xf0]
100005014: 4fdb98c8    	fmul.2d	v8, v6, v27[1]
100005018: 4e7dd51d    	fadd.2d	v29, v8, v29
10000501c: 6e60df28    	fmul.2d	v8, v25, v0
100005020: 4e68d7c8    	fadd.2d	v8, v30, v8
100005024: 4e7dd500    	fadd.2d	v0, v8, v29
100005028: 3d80c7e0    	str	q0, [sp, #0x310]
10000502c: 3dc13fe0    	ldr	q0, [sp, #0x4f0]
100005030: 4fd5901d    	fmul.2d	v29, v0, v21[0]
100005034: 4fd599e8    	fmul.2d	v8, v15, v21[1]
100005038: 4e68d7bd    	fadd.2d	v29, v29, v8
10000503c: 3dc167e0    	ldr	q0, [sp, #0x590]
100005040: 4fd69008    	fmul.2d	v8, v0, v22[0]
100005044: 4e68d7bd    	fadd.2d	v29, v29, v8
100005048: 3dc1cbe0    	ldr	q0, [sp, #0x720]
10000504c: 4fc19008    	fmul.2d	v8, v0, v1[0]
100005050: 4e7dd51d    	fadd.2d	v29, v8, v29
100005054: 3dc1cfe4    	ldr	q4, [sp, #0x730]
100005058: 4fd89088    	fmul.2d	v8, v4, v24[0]
10000505c: 4e7dd51d    	fadd.2d	v29, v8, v29
100005060: 3dc1abe4    	ldr	q4, [sp, #0x6a0]
100005064: 4fd89888    	fmul.2d	v8, v4, v24[1]
100005068: 4e7dd51d    	fadd.2d	v29, v8, v29
10000506c: 4fd991a8    	fmul.2d	v8, v13, v25[0]
100005070: 4e7dd51d    	fadd.2d	v29, v8, v29
100005074: 3cd303a4    	ldur	q4, [x29, #-0xd0]
100005078: 4fd99888    	fmul.2d	v8, v4, v25[1]
10000507c: 4e7dd51d    	fadd.2d	v29, v8, v29
100005080: 3cda03a4    	ldur	q4, [x29, #-0x60]
100005084: 4fdb9088    	fmul.2d	v8, v4, v27[0]
100005088: 4e7dd51d    	fadd.2d	v29, v8, v29
10000508c: 3dc1dffa    	ldr	q26, [sp, #0x770]
100005090: 4fdb9b48    	fmul.2d	v8, v26, v27[1]
100005094: 4e7dd51d    	fadd.2d	v29, v8, v29
100005098: 6e6adf68    	fmul.2d	v8, v27, v10
10000509c: 4e68d408    	fadd.2d	v8, v0, v8
1000050a0: 4e7dd500    	fadd.2d	v0, v8, v29
1000050a4: 3d80c3e0    	str	q0, [sp, #0x300]
1000050a8: 3dc17be0    	ldr	q0, [sp, #0x5e0]
1000050ac: 4fd5901d    	fmul.2d	v29, v0, v21[0]
1000050b0: 3dc14bed    	ldr	q13, [sp, #0x520]
1000050b4: 4fd599b5    	fmul.2d	v21, v13, v21[1]
1000050b8: 4e75d7b5    	fadd.2d	v21, v29, v21
1000050bc: 3dc1afe0    	ldr	q0, [sp, #0x6b0]
1000050c0: 4fd69016    	fmul.2d	v22, v0, v22[0]
1000050c4: 4e76d6b5    	fadd.2d	v21, v21, v22
1000050c8: 3dc1d3e0    	ldr	q0, [sp, #0x740]
1000050cc: 4fc19016    	fmul.2d	v22, v0, v1[0]
1000050d0: 4e75d6d5    	fadd.2d	v21, v22, v21
1000050d4: 3dc1d7e1    	ldr	q1, [sp, #0x750]
1000050d8: 4fd89036    	fmul.2d	v22, v1, v24[0]
1000050dc: 4e75d6d5    	fadd.2d	v21, v22, v21
1000050e0: 3dc11fea    	ldr	q10, [sp, #0x470]
1000050e4: 4fd89956    	fmul.2d	v22, v10, v24[1]
1000050e8: 4e75d6d5    	fadd.2d	v21, v22, v21
1000050ec: 3dc1a7e1    	ldr	q1, [sp, #0x690]
1000050f0: 4fd99036    	fmul.2d	v22, v1, v25[0]
1000050f4: 4e75d6d5    	fadd.2d	v21, v22, v21
1000050f8: 4fd99a96    	fmul.2d	v22, v20, v25[1]
1000050fc: 4e75d6d5    	fadd.2d	v21, v22, v21
100005100: 3cd403a1    	ldur	q1, [x29, #-0xc0]
100005104: 4fdb9036    	fmul.2d	v22, v1, v27[0]
100005108: 4e75d6d5    	fadd.2d	v21, v22, v21
10000510c: 3cd803a1    	ldur	q1, [x29, #-0x80]
100005110: 4fdb9836    	fmul.2d	v22, v1, v27[1]
100005114: 4e75d6d6    	fadd.2d	v22, v22, v21
100005118: ad4d5518    	ldp	q24, q21, [x8, #0x1a0]
10000511c: 6e7cdf18    	fmul.2d	v24, v24, v28
100005120: 4e78d418    	fadd.2d	v24, v0, v24
100005124: 4e78d6c0    	fadd.2d	v0, v22, v24
100005128: 3d802fe0    	str	q0, [sp, #0xb0]
10000512c: 3dc14ffe    	ldr	q30, [sp, #0x530]
100005130: 6e75dfd6    	fmul.2d	v22, v30, v21
100005134: 6e1642d6    	ext.16b	v22, v22, v22, #0x8
100005138: 3cd603a0    	ldur	q0, [x29, #-0xa0]
10000513c: 6e75dc18    	fmul.2d	v24, v0, v21
100005140: 4e78d6d8    	fadd.2d	v24, v22, v24
100005144: 3dc07116    	ldr	q22, [x8, #0x1c0]
100005148: 4fd69079    	fmul.2d	v25, v3, v22[0]
10000514c: 4e79d718    	fadd.2d	v24, v24, v25
100005150: 4fd69a59    	fmul.2d	v25, v18, v22[1]
100005154: 4e79d718    	fadd.2d	v24, v24, v25
100005158: 3dc163e1    	ldr	q1, [sp, #0x580]
10000515c: 3dc0a3e4    	ldr	q4, [sp, #0x280]
100005160: 4fc49039    	fmul.2d	v25, v1, v4[0]
100005164: 4e78d739    	fadd.2d	v25, v25, v24
100005168: fd40d138    	ldr	d24, [x9, #0x1a0]
10000516c: 4fd893fb    	fmul.2d	v27, v31, v24[0]
100005170: 4e79d77d    	fadd.2d	v29, v27, v25
100005174: 3dc13be0    	ldr	q0, [sp, #0x4e0]
100005178: 4fd59019    	fmul.2d	v25, v0, v21[0]
10000517c: 3dc1c3e6    	ldr	q6, [sp, #0x700]
100005180: 4fd598db    	fmul.2d	v27, v6, v21[1]
100005184: 4e7bd739    	fadd.2d	v25, v25, v27
100005188: 3dc137e0    	ldr	q0, [sp, #0x4d0]
10000518c: 4fd6901b    	fmul.2d	v27, v0, v22[0]
100005190: 4e7bd739    	fadd.2d	v25, v25, v27
100005194: 4fd6985b    	fmul.2d	v27, v2, v22[1]
100005198: 4e7bd739    	fadd.2d	v25, v25, v27
10000519c: 3dc107e0    	ldr	q0, [sp, #0x410]
1000051a0: 4fc4901b    	fmul.2d	v27, v0, v4[0]
1000051a4: 4e79d779    	fadd.2d	v25, v27, v25
1000051a8: 4fd890bb    	fmul.2d	v27, v5, v24[0]
1000051ac: 4e79d77f    	fadd.2d	v31, v27, v25
1000051b0: 3dc10ffc    	ldr	q28, [sp, #0x430]
1000051b4: 4fd59399    	fmul.2d	v25, v28, v21[0]
1000051b8: 3dc12ff2    	ldr	q18, [sp, #0x4b0]
1000051bc: 4fd59a5b    	fmul.2d	v27, v18, v21[1]
1000051c0: 4e7bd739    	fadd.2d	v25, v25, v27
1000051c4: 3dc127f4    	ldr	q20, [sp, #0x490]
1000051c8: 4fd6929b    	fmul.2d	v27, v20, v22[0]
1000051cc: 4e7bd739    	fadd.2d	v25, v25, v27
1000051d0: 4fd6993b    	fmul.2d	v27, v9, v22[1]
1000051d4: 4e7bd739    	fadd.2d	v25, v25, v27
1000051d8: 3dc15fef    	ldr	q15, [sp, #0x570]
1000051dc: 4fc491fb    	fmul.2d	v27, v15, v4[0]
1000051e0: 4e79d779    	fadd.2d	v25, v27, v25
1000051e4: 3dc143e2    	ldr	q2, [sp, #0x500]
1000051e8: 4fd8905b    	fmul.2d	v27, v2, v24[0]
1000051ec: 4e79d768    	fadd.2d	v8, v27, v25
1000051f0: ad4f6d19    	ldp	q25, q27, [x8, #0x1e0]
1000051f4: 3cd003a2    	ldur	q2, [x29, #-0x100]
1000051f8: 4fd99049    	fmul.2d	v9, v2, v25[0]
1000051fc: 4e7dd53d    	fadd.2d	v29, v9, v29
100005200: 4fd99989    	fmul.2d	v9, v12, v25[1]
100005204: 4e7dd53d    	fadd.2d	v29, v9, v29
100005208: 3dc1c7e2    	ldr	q2, [sp, #0x710]
10000520c: 4fd99049    	fmul.2d	v9, v2, v25[0]
100005210: 4e7fd53f    	fadd.2d	v31, v9, v31
100005214: 3dc1b7e2    	ldr	q2, [sp, #0x6d0]
100005218: 4fd99849    	fmul.2d	v9, v2, v25[1]
10000521c: 4e7fd53f    	fadd.2d	v31, v9, v31
100005220: 3dc123e2    	ldr	q2, [sp, #0x480]
100005224: 4fd99049    	fmul.2d	v9, v2, v25[0]
100005228: 4e68d528    	fadd.2d	v8, v9, v8
10000522c: 3dc16be2    	ldr	q2, [sp, #0x5a0]
100005230: 4fd99849    	fmul.2d	v9, v2, v25[1]
100005234: 4e68d528    	fadd.2d	v8, v9, v8
100005238: 3dc133e2    	ldr	q2, [sp, #0x4c0]
10000523c: 4fd59049    	fmul.2d	v9, v2, v21[0]
100005240: 3dc153ec    	ldr	q12, [sp, #0x540]
100005244: 4fd5998b    	fmul.2d	v11, v12, v21[1]
100005248: 4e6bd529    	fadd.2d	v9, v9, v11
10000524c: 4fd690eb    	fmul.2d	v11, v7, v22[0]
100005250: 4e6bd529    	fadd.2d	v9, v9, v11
100005254: 3dc1a3e2    	ldr	q2, [sp, #0x680]
100005258: 4fd6984b    	fmul.2d	v11, v2, v22[1]
10000525c: 4e6bd529    	fadd.2d	v9, v9, v11
100005260: 3dc18fe2    	ldr	q2, [sp, #0x630]
100005264: 4fc4904b    	fmul.2d	v11, v2, v4[0]
100005268: 4e69d569    	fadd.2d	v9, v11, v9
10000526c: 3dc1b3e3    	ldr	q3, [sp, #0x6c0]
100005270: 4fd8906b    	fmul.2d	v11, v3, v24[0]
100005274: 4e69d569    	fadd.2d	v9, v11, v9
100005278: 3cd903a3    	ldur	q3, [x29, #-0x70]
10000527c: 4fd9906b    	fmul.2d	v11, v3, v25[0]
100005280: 4e69d569    	fadd.2d	v9, v11, v9
100005284: 4fd99a2b    	fmul.2d	v11, v17, v25[1]
100005288: 4e69d569    	fadd.2d	v9, v11, v9
10000528c: 4fdb926b    	fmul.2d	v11, v19, v27[0]
100005290: 4e7dd57d    	fadd.2d	v29, v11, v29
100005294: 3cd703a3    	ldur	q3, [x29, #-0x90]
100005298: 4fdb986b    	fmul.2d	v11, v3, v27[1]
10000529c: 4e7dd57d    	fadd.2d	v29, v11, v29
1000052a0: 3dc15be7    	ldr	q7, [sp, #0x560]
1000052a4: 6e67deab    	fmul.2d	v11, v21, v7
1000052a8: 4e6bd42b    	fadd.2d	v11, v1, v11
1000052ac: 4ea11c25    	mov.16b	v5, v1
1000052b0: 4e7dd561    	fadd.2d	v1, v11, v29
1000052b4: 3d808be1    	str	q1, [sp, #0x220]
1000052b8: 3dc17fe1    	ldr	q1, [sp, #0x5f0]
1000052bc: 4fdb903d    	fmul.2d	v29, v1, v27[0]
1000052c0: 4e7fd7bd    	fadd.2d	v29, v29, v31
1000052c4: 3cd503a1    	ldur	q1, [x29, #-0xb0]
1000052c8: 4fdb983f    	fmul.2d	v31, v1, v27[1]
1000052cc: 4e7dd7fd    	fadd.2d	v29, v31, v29
1000052d0: 6e70dedf    	fmul.2d	v31, v22, v16
1000052d4: 4e7fd41f    	fadd.2d	v31, v0, v31
1000052d8: 4ea01c03    	mov.16b	v3, v0
1000052dc: 4e7dd7e1    	fadd.2d	v1, v31, v29
1000052e0: 3dc187e0    	ldr	q0, [sp, #0x610]
1000052e4: 4fdb901d    	fmul.2d	v29, v0, v27[0]
1000052e8: 4e68d7bd    	fadd.2d	v29, v29, v8
1000052ec: 4ea41c9f    	mov.16b	v31, v4
1000052f0: 6e18071f    	mov.d	v31[1], v24[0]
1000052f4: 4fdb99c8    	fmul.2d	v8, v14, v27[1]
1000052f8: 4e7dd51d    	fadd.2d	v29, v8, v29
1000052fc: 6e77dfff    	fmul.2d	v31, v31, v23
100005300: 4e7fd5ff    	fadd.2d	v31, v15, v31
100005304: 4eaf1df1    	mov.16b	v17, v15
100005308: 4e7dd7e0    	fadd.2d	v0, v31, v29
10000530c: ad1707e0    	stp	q0, q1, [sp, #0x2e0]
100005310: 3dc183e0    	ldr	q0, [sp, #0x600]
100005314: 4fdb901d    	fmul.2d	v29, v0, v27[0]
100005318: 4e69d7bd    	fadd.2d	v29, v29, v9
10000531c: ad7883ae    	ldp	q14, q0, [x29, #-0xf0]
100005320: 4fdb99df    	fmul.2d	v31, v14, v27[1]
100005324: 4e7dd7fd    	fadd.2d	v29, v31, v29
100005328: 6e60df3f    	fmul.2d	v31, v25, v0
10000532c: 4e7fd45f    	fadd.2d	v31, v2, v31
100005330: 4e7dd7e0    	fadd.2d	v0, v31, v29
100005334: 3d80afe0    	str	q0, [sp, #0x2b0]
100005338: 3dc13feb    	ldr	q11, [sp, #0x4f0]
10000533c: 4fd5917d    	fmul.2d	v29, v11, v21[0]
100005340: 3dc197e0    	ldr	q0, [sp, #0x650]
100005344: 4fd5981f    	fmul.2d	v31, v0, v21[1]
100005348: 4e7fd7bd    	fadd.2d	v29, v29, v31
10000534c: 3dc167e0    	ldr	q0, [sp, #0x590]
100005350: 4fd6901f    	fmul.2d	v31, v0, v22[0]
100005354: 4e7fd7bd    	fadd.2d	v29, v29, v31
100005358: 3dc1cbe0    	ldr	q0, [sp, #0x720]
10000535c: 4fd6981f    	fmul.2d	v31, v0, v22[1]
100005360: 4e7fd7bd    	fadd.2d	v29, v29, v31
100005364: 3dc1cfe0    	ldr	q0, [sp, #0x730]
100005368: 4fc4901f    	fmul.2d	v31, v0, v4[0]
10000536c: 4e7dd7fd    	fadd.2d	v29, v31, v29
100005370: 3dc1abe1    	ldr	q1, [sp, #0x6a0]
100005374: 4fd8903f    	fmul.2d	v31, v1, v24[0]
100005378: 4e7dd7fd    	fadd.2d	v29, v31, v29
10000537c: 3dc18be1    	ldr	q1, [sp, #0x620]
100005380: 4fd9903f    	fmul.2d	v31, v1, v25[0]
100005384: 4e7dd7fd    	fadd.2d	v29, v31, v29
100005388: 3cd303a1    	ldur	q1, [x29, #-0xd0]
10000538c: 4fd9983f    	fmul.2d	v31, v1, v25[1]
100005390: 4e7dd7fd    	fadd.2d	v29, v31, v29
100005394: 3cda03a1    	ldur	q1, [x29, #-0x60]
100005398: 4fdb903f    	fmul.2d	v31, v1, v27[0]
10000539c: 4e7dd7fd    	fadd.2d	v29, v31, v29
1000053a0: 4fdb9b5f    	fmul.2d	v31, v26, v27[1]
1000053a4: 4e7dd7fd    	fadd.2d	v29, v31, v29
1000053a8: 3dc19be1    	ldr	q1, [sp, #0x660]
1000053ac: 6e61df7f    	fmul.2d	v31, v27, v1
1000053b0: 4e7fd41f    	fadd.2d	v31, v0, v31
1000053b4: 4e7dd7e0    	fadd.2d	v0, v31, v29
1000053b8: 3d80abe0    	str	q0, [sp, #0x2a0]
1000053bc: 3dc17be0    	ldr	q0, [sp, #0x5e0]
1000053c0: 4fd5901d    	fmul.2d	v29, v0, v21[0]
1000053c4: 4fd599b5    	fmul.2d	v21, v13, v21[1]
1000053c8: 4e75d7b5    	fadd.2d	v21, v29, v21
1000053cc: 3dc1affa    	ldr	q26, [sp, #0x6b0]
1000053d0: 4fd6935d    	fmul.2d	v29, v26, v22[0]
1000053d4: 4e7dd6b5    	fadd.2d	v21, v21, v29
1000053d8: 3dc1d3e0    	ldr	q0, [sp, #0x740]
1000053dc: 4fd69816    	fmul.2d	v22, v0, v22[1]
1000053e0: 4e76d6b5    	fadd.2d	v21, v21, v22
1000053e4: 3dc1d7e1    	ldr	q1, [sp, #0x750]
1000053e8: 4fc49036    	fmul.2d	v22, v1, v4[0]
1000053ec: 4e75d6d5    	fadd.2d	v21, v22, v21
1000053f0: 4fd89156    	fmul.2d	v22, v10, v24[0]
1000053f4: 4e75d6d5    	fadd.2d	v21, v22, v21
1000053f8: 3dc1a7ea    	ldr	q10, [sp, #0x690]
1000053fc: 4fd99156    	fmul.2d	v22, v10, v25[0]
100005400: 4e75d6d5    	fadd.2d	v21, v22, v21
100005404: 3dc16fed    	ldr	q13, [sp, #0x5b0]
100005408: 4fd999b6    	fmul.2d	v22, v13, v25[1]
10000540c: 4e75d6d5    	fadd.2d	v21, v22, v21
100005410: 3cd403a0    	ldur	q0, [x29, #-0xc0]
100005414: 4fdb9016    	fmul.2d	v22, v0, v27[0]
100005418: 4e75d6d5    	fadd.2d	v21, v22, v21
10000541c: 3cd803a0    	ldur	q0, [x29, #-0x80]
100005420: 4fdb9816    	fmul.2d	v22, v0, v27[1]
100005424: 4e75d6d6    	fadd.2d	v22, v22, v21
100005428: ad505518    	ldp	q24, q21, [x8, #0x200]
10000542c: 3dc1bbe0    	ldr	q0, [sp, #0x6e0]
100005430: 6e60df18    	fmul.2d	v24, v24, v0
100005434: 4e78d438    	fadd.2d	v24, v1, v24
100005438: 4e78d6c0    	fadd.2d	v0, v22, v24
10000543c: 3d807be0    	str	q0, [sp, #0x1e0]
100005440: 6e75dfd6    	fmul.2d	v22, v30, v21
100005444: 6e1642d6    	ext.16b	v22, v22, v22, #0x8
100005448: 3cd603b0    	ldur	q16, [x29, #-0xa0]
10000544c: 6e75de18    	fmul.2d	v24, v16, v21
100005450: 4e78d6d8    	fadd.2d	v24, v22, v24
100005454: 3dc08916    	ldr	q22, [x8, #0x220]
100005458: 3dc10be0    	ldr	q0, [sp, #0x420]
10000545c: 4fd69019    	fmul.2d	v25, v0, v22[0]
100005460: 4e79d718    	fadd.2d	v24, v24, v25
100005464: 3dc1bfe0    	ldr	q0, [sp, #0x6f0]
100005468: 4fd69819    	fmul.2d	v25, v0, v22[1]
10000546c: 4e79d719    	fadd.2d	v25, v24, v25
100005470: 3dc08d18    	ldr	q24, [x8, #0x230]
100005474: 4fd890bb    	fmul.2d	v27, v5, v24[0]
100005478: 4e7bd739    	fadd.2d	v25, v25, v27
10000547c: 3dc12be1    	ldr	q1, [sp, #0x4a0]
100005480: 3dc09bef    	ldr	q15, [sp, #0x260]
100005484: 4fcf903b    	fmul.2d	v27, v1, v15[0]
100005488: 4e79d77d    	fadd.2d	v29, v27, v25
10000548c: 3dc13be0    	ldr	q0, [sp, #0x4e0]
100005490: 4fd59019    	fmul.2d	v25, v0, v21[0]
100005494: 4fd598db    	fmul.2d	v27, v6, v21[1]
100005498: 4e7bd739    	fadd.2d	v25, v25, v27
10000549c: 3dc137e0    	ldr	q0, [sp, #0x4d0]
1000054a0: 4fd6901b    	fmul.2d	v27, v0, v22[0]
1000054a4: 4e7bd739    	fadd.2d	v25, v25, v27
1000054a8: 3dc11be0    	ldr	q0, [sp, #0x460]
1000054ac: 4fd6981b    	fmul.2d	v27, v0, v22[1]
1000054b0: 4e7bd739    	fadd.2d	v25, v25, v27
1000054b4: 4fd8907b    	fmul.2d	v27, v3, v24[0]
1000054b8: 4e7bd739    	fadd.2d	v25, v25, v27
1000054bc: 3dc147e0    	ldr	q0, [sp, #0x510]
1000054c0: 4fcf901b    	fmul.2d	v27, v0, v15[0]
1000054c4: 4e79d77e    	fadd.2d	v30, v27, v25
1000054c8: 4fd59399    	fmul.2d	v25, v28, v21[0]
1000054cc: 4fd59a5b    	fmul.2d	v27, v18, v21[1]
1000054d0: 4e7bd739    	fadd.2d	v25, v25, v27
1000054d4: 4fd6929b    	fmul.2d	v27, v20, v22[0]
1000054d8: 4e7bd739    	fadd.2d	v25, v25, v27
1000054dc: 3dc193e3    	ldr	q3, [sp, #0x640]
1000054e0: 4fd6987b    	fmul.2d	v27, v3, v22[1]
1000054e4: 4e7bd739    	fadd.2d	v25, v25, v27
1000054e8: 4fd8923b    	fmul.2d	v27, v17, v24[0]
1000054ec: 4e7bd739    	fadd.2d	v25, v25, v27
1000054f0: 3dc143e4    	ldr	q4, [sp, #0x500]
1000054f4: 4fcf909b    	fmul.2d	v27, v4, v15[0]
1000054f8: 4e79d77f    	fadd.2d	v31, v27, v25
1000054fc: ad526d19    	ldp	q25, q27, [x8, #0x240]
100005500: 3cd003a3    	ldur	q3, [x29, #-0x100]
100005504: 4fd99068    	fmul.2d	v8, v3, v25[0]
100005508: 4e7dd51d    	fadd.2d	v29, v8, v29
10000550c: 3dc117f1    	ldr	q17, [sp, #0x450]
100005510: 4fd99a28    	fmul.2d	v8, v17, v25[1]
100005514: 4e7dd51d    	fadd.2d	v29, v8, v29
100005518: 3dc1c7e3    	ldr	q3, [sp, #0x710]
10000551c: 4fd99068    	fmul.2d	v8, v3, v25[0]
100005520: 4e7ed51e    	fadd.2d	v30, v8, v30
100005524: 3dc1b7e3    	ldr	q3, [sp, #0x6d0]
100005528: 4fd99868    	fmul.2d	v8, v3, v25[1]
10000552c: 4e7ed51e    	fadd.2d	v30, v8, v30
100005530: 3dc123e5    	ldr	q5, [sp, #0x480]
100005534: 4fd990a8    	fmul.2d	v8, v5, v25[0]
100005538: 4e7fd51f    	fadd.2d	v31, v8, v31
10000553c: 3dc16be6    	ldr	q6, [sp, #0x5a0]
100005540: 4fd998c8    	fmul.2d	v8, v6, v25[1]
100005544: 4e7fd51f    	fadd.2d	v31, v8, v31
100005548: 3dc133f3    	ldr	q19, [sp, #0x4c0]
10000554c: 4fd59268    	fmul.2d	v8, v19, v21[0]
100005550: 4fd59989    	fmul.2d	v9, v12, v21[1]
100005554: 4e69d508    	fadd.2d	v8, v8, v9
100005558: 3dc157f2    	ldr	q18, [sp, #0x550]
10000555c: 4fd69249    	fmul.2d	v9, v18, v22[0]
100005560: 4e69d508    	fadd.2d	v8, v8, v9
100005564: 3dc1a3fc    	ldr	q28, [sp, #0x680]
100005568: 4fd69b89    	fmul.2d	v9, v28, v22[1]
10000556c: 4e69d508    	fadd.2d	v8, v8, v9
100005570: 4fd89049    	fmul.2d	v9, v2, v24[0]
100005574: 4e69d508    	fadd.2d	v8, v8, v9
100005578: 3dc1b3e2    	ldr	q2, [sp, #0x6c0]
10000557c: 4fcf9049    	fmul.2d	v9, v2, v15[0]
100005580: 4e68d528    	fadd.2d	v8, v9, v8
100005584: 3cd903a5    	ldur	q5, [x29, #-0x70]
100005588: 4fd990a9    	fmul.2d	v9, v5, v25[0]
10000558c: 4e68d528    	fadd.2d	v8, v9, v8
100005590: 3dc113f7    	ldr	q23, [sp, #0x440]
100005594: 4fd99ae9    	fmul.2d	v9, v23, v25[1]
100005598: 4e68d528    	fadd.2d	v8, v9, v8
10000559c: 3dc19fe5    	ldr	q5, [sp, #0x670]
1000055a0: 4fdb90a9    	fmul.2d	v9, v5, v27[0]
1000055a4: 4e7dd53d    	fadd.2d	v29, v9, v29
1000055a8: 3cd703a5    	ldur	q5, [x29, #-0x90]
1000055ac: 4fdb98a9    	fmul.2d	v9, v5, v27[1]
1000055b0: 4e7dd53d    	fadd.2d	v29, v9, v29
1000055b4: 6e67dea9    	fmul.2d	v9, v21, v7
1000055b8: 4e69d429    	fadd.2d	v9, v1, v9
1000055bc: 4ea11c27    	mov.16b	v7, v1
1000055c0: 4e7dd521    	fadd.2d	v1, v9, v29
1000055c4: 3d80b3e1    	str	q1, [sp, #0x2c0]
1000055c8: 3dc17fe1    	ldr	q1, [sp, #0x5f0]
1000055cc: 4fdb903d    	fmul.2d	v29, v1, v27[0]
1000055d0: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000055d4: 3cd503a1    	ldur	q1, [x29, #-0xb0]
1000055d8: 4fdb983e    	fmul.2d	v30, v1, v27[1]
1000055dc: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000055e0: 3dc177e1    	ldr	q1, [sp, #0x5d0]
1000055e4: 6e61dede    	fmul.2d	v30, v22, v1
1000055e8: 4e7ed41e    	fadd.2d	v30, v0, v30
1000055ec: 4ea01c05    	mov.16b	v5, v0
1000055f0: 4e7dd7c1    	fadd.2d	v1, v30, v29
1000055f4: 3dc187e0    	ldr	q0, [sp, #0x610]
1000055f8: 4fdb901d    	fmul.2d	v29, v0, v27[0]
1000055fc: 4e7fd7bd    	fadd.2d	v29, v29, v31
100005600: 3dc1dbe0    	ldr	q0, [sp, #0x760]
100005604: 4fdb981e    	fmul.2d	v30, v0, v27[1]
100005608: 4e7dd7dd    	fadd.2d	v29, v30, v29
10000560c: 4eb81f1e    	mov.16b	v30, v24
100005610: 6e1805fe    	mov.d	v30[1], v15[0]
100005614: 3dc173e0    	ldr	q0, [sp, #0x5c0]
100005618: 6e60dfde    	fmul.2d	v30, v30, v0
10000561c: 4e7ed49e    	fadd.2d	v30, v4, v30
100005620: 4e7dd7c0    	fadd.2d	v0, v30, v29
100005624: ad1407e0    	stp	q0, q1, [sp, #0x280]
100005628: 3dc183e0    	ldr	q0, [sp, #0x600]
10000562c: 4fdb901d    	fmul.2d	v29, v0, v27[0]
100005630: 4e68d7bd    	fadd.2d	v29, v29, v8
100005634: 4fdb99de    	fmul.2d	v30, v14, v27[1]
100005638: 4e7dd7dd    	fadd.2d	v29, v30, v29
10000563c: 3cd203a0    	ldur	q0, [x29, #-0xe0]
100005640: 6e60df3e    	fmul.2d	v30, v25, v0
100005644: 4e7ed45e    	fadd.2d	v30, v2, v30
100005648: 4ea21c49    	mov.16b	v9, v2
10000564c: 4e7dd7c0    	fadd.2d	v0, v30, v29
100005650: 3d809fe0    	str	q0, [sp, #0x270]
100005654: 4fd5917d    	fmul.2d	v29, v11, v21[0]
100005658: 3dc197e0    	ldr	q0, [sp, #0x650]
10000565c: 4fd5981e    	fmul.2d	v30, v0, v21[1]
100005660: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005664: 3dc167e0    	ldr	q0, [sp, #0x590]
100005668: 4fd6901e    	fmul.2d	v30, v0, v22[0]
10000566c: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005670: 3dc1cbe0    	ldr	q0, [sp, #0x720]
100005674: 4fd6981e    	fmul.2d	v30, v0, v22[1]
100005678: 4e7ed7bd    	fadd.2d	v29, v29, v30
10000567c: 3dc1cfe0    	ldr	q0, [sp, #0x730]
100005680: 4fd8901e    	fmul.2d	v30, v0, v24[0]
100005684: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005688: 3dc1abe0    	ldr	q0, [sp, #0x6a0]
10000568c: 4fcf901e    	fmul.2d	v30, v0, v15[0]
100005690: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005694: 3dc18be1    	ldr	q1, [sp, #0x620]
100005698: 4fd9903e    	fmul.2d	v30, v1, v25[0]
10000569c: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000056a0: 3cd303a1    	ldur	q1, [x29, #-0xd0]
1000056a4: 4fd9983e    	fmul.2d	v30, v1, v25[1]
1000056a8: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000056ac: 3cda03a1    	ldur	q1, [x29, #-0x60]
1000056b0: 4fdb903e    	fmul.2d	v30, v1, v27[0]
1000056b4: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000056b8: 3dc1dfe1    	ldr	q1, [sp, #0x770]
1000056bc: 4fdb983e    	fmul.2d	v30, v1, v27[1]
1000056c0: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000056c4: 3dc19be1    	ldr	q1, [sp, #0x660]
1000056c8: 6e61df7e    	fmul.2d	v30, v27, v1
1000056cc: 4e7ed41e    	fadd.2d	v30, v0, v30
1000056d0: 4e7dd7c0    	fadd.2d	v0, v30, v29
1000056d4: 3d8097e0    	str	q0, [sp, #0x250]
1000056d8: 3dc17be0    	ldr	q0, [sp, #0x5e0]
1000056dc: 4fd5901d    	fmul.2d	v29, v0, v21[0]
1000056e0: 3dc14be0    	ldr	q0, [sp, #0x520]
1000056e4: 4fd59815    	fmul.2d	v21, v0, v21[1]
1000056e8: 4e75d7b5    	fadd.2d	v21, v29, v21
1000056ec: 4fd6935d    	fmul.2d	v29, v26, v22[0]
1000056f0: 4e7dd6b5    	fadd.2d	v21, v21, v29
1000056f4: 3dc1d3e0    	ldr	q0, [sp, #0x740]
1000056f8: 4fd69816    	fmul.2d	v22, v0, v22[1]
1000056fc: 4e76d6b5    	fadd.2d	v21, v21, v22
100005700: 3dc1d7e0    	ldr	q0, [sp, #0x750]
100005704: 4fd89016    	fmul.2d	v22, v0, v24[0]
100005708: 4e76d6b5    	fadd.2d	v21, v21, v22
10000570c: 3dc11fe1    	ldr	q1, [sp, #0x470]
100005710: 4fcf9036    	fmul.2d	v22, v1, v15[0]
100005714: 4e75d6d5    	fadd.2d	v21, v22, v21
100005718: 4fd99156    	fmul.2d	v22, v10, v25[0]
10000571c: 4e75d6d5    	fadd.2d	v21, v22, v21
100005720: 4fd999b6    	fmul.2d	v22, v13, v25[1]
100005724: 4e75d6d5    	fadd.2d	v21, v22, v21
100005728: 3cd403a0    	ldur	q0, [x29, #-0xc0]
10000572c: 4fdb9016    	fmul.2d	v22, v0, v27[0]
100005730: 4e75d6d5    	fadd.2d	v21, v22, v21
100005734: 3cd803a0    	ldur	q0, [x29, #-0x80]
100005738: 4fdb9816    	fmul.2d	v22, v0, v27[1]
10000573c: 4e75d6d6    	fadd.2d	v22, v22, v21
100005740: ad535518    	ldp	q24, q21, [x8, #0x260]
100005744: 3dc1bbe0    	ldr	q0, [sp, #0x6e0]
100005748: 6e60df18    	fmul.2d	v24, v24, v0
10000574c: 4e78d438    	fadd.2d	v24, v1, v24
100005750: 4e78d6c0    	fadd.2d	v0, v22, v24
100005754: 3d802be0    	str	q0, [sp, #0xa0]
100005758: 3dc14fe0    	ldr	q0, [sp, #0x530]
10000575c: 6e75dc16    	fmul.2d	v22, v0, v21
100005760: 6e1642d6    	ext.16b	v22, v22, v22, #0x8
100005764: 6e75de18    	fmul.2d	v24, v16, v21
100005768: 4e78d6d9    	fadd.2d	v25, v22, v24
10000576c: ad546116    	ldp	q22, q24, [x8, #0x280]
100005770: 3dc10bea    	ldr	q10, [sp, #0x420]
100005774: 4fd6915b    	fmul.2d	v27, v10, v22[0]
100005778: 4e7bd739    	fadd.2d	v25, v25, v27
10000577c: 3dc1bfe0    	ldr	q0, [sp, #0x6f0]
100005780: 4fd6981b    	fmul.2d	v27, v0, v22[1]
100005784: 4e7bd739    	fadd.2d	v25, v25, v27
100005788: 3dc13bfa    	ldr	q26, [sp, #0x4e0]
10000578c: 4fd5935b    	fmul.2d	v27, v26, v21[0]
100005790: 3dc1c3e0    	ldr	q0, [sp, #0x700]
100005794: 4fd5981d    	fmul.2d	v29, v0, v21[1]
100005798: 4e7dd77b    	fadd.2d	v27, v27, v29
10000579c: 3dc137ec    	ldr	q12, [sp, #0x4d0]
1000057a0: 4fd6919d    	fmul.2d	v29, v12, v22[0]
1000057a4: 4e7dd77b    	fadd.2d	v27, v27, v29
1000057a8: 3dc11bf4    	ldr	q20, [sp, #0x460]
1000057ac: 4fd69a9d    	fmul.2d	v29, v20, v22[1]
1000057b0: 4e7dd77b    	fadd.2d	v27, v27, v29
1000057b4: 3dc163e0    	ldr	q0, [sp, #0x580]
1000057b8: 4fd8901d    	fmul.2d	v29, v0, v24[0]
1000057bc: 4e7dd739    	fadd.2d	v25, v25, v29
1000057c0: 4fd898fd    	fmul.2d	v29, v7, v24[1]
1000057c4: 4e7dd739    	fadd.2d	v25, v25, v29
1000057c8: 3cd003a1    	ldur	q1, [x29, #-0x100]
1000057cc: 3dc0f3e0    	ldr	q0, [sp, #0x3c0]
1000057d0: 4fc0903d    	fmul.2d	v29, v1, v0[0]
1000057d4: 4e79d7bd    	fadd.2d	v29, v29, v25
1000057d8: fd413939    	ldr	d25, [x9, #0x270]
1000057dc: 4fd9923e    	fmul.2d	v30, v17, v25[0]
1000057e0: 4e7dd7de    	fadd.2d	v30, v30, v29
1000057e4: 3dc107f1    	ldr	q17, [sp, #0x410]
1000057e8: 4fd8923d    	fmul.2d	v29, v17, v24[0]
1000057ec: 4e7dd77b    	fadd.2d	v27, v27, v29
1000057f0: 4fd898bd    	fmul.2d	v29, v5, v24[1]
1000057f4: 4e7dd77b    	fadd.2d	v27, v27, v29
1000057f8: 3dc1c7f0    	ldr	q16, [sp, #0x710]
1000057fc: 4fc0921d    	fmul.2d	v29, v16, v0[0]
100005800: 4e7bd7bb    	fadd.2d	v27, v29, v27
100005804: 4fd9907d    	fmul.2d	v29, v3, v25[0]
100005808: 4e7bd7bf    	fadd.2d	v31, v29, v27
10000580c: 3dc10fe2    	ldr	q2, [sp, #0x430]
100005810: 4fd5905b    	fmul.2d	v27, v2, v21[0]
100005814: 3dc12fee    	ldr	q14, [sp, #0x4b0]
100005818: 4fd599dd    	fmul.2d	v29, v14, v21[1]
10000581c: 4e7dd77b    	fadd.2d	v27, v27, v29
100005820: 3dc127e2    	ldr	q2, [sp, #0x490]
100005824: 4fd6905d    	fmul.2d	v29, v2, v22[0]
100005828: 4e7dd77b    	fadd.2d	v27, v27, v29
10000582c: 3dc193e2    	ldr	q2, [sp, #0x640]
100005830: 4fd6985d    	fmul.2d	v29, v2, v22[1]
100005834: 4e7dd77b    	fadd.2d	v27, v27, v29
100005838: 3dc15fef    	ldr	q15, [sp, #0x570]
10000583c: 4fd891fd    	fmul.2d	v29, v15, v24[0]
100005840: 4e7dd77b    	fadd.2d	v27, v27, v29
100005844: 4fd8989d    	fmul.2d	v29, v4, v24[1]
100005848: 4e7dd77b    	fadd.2d	v27, v27, v29
10000584c: 3dc123e2    	ldr	q2, [sp, #0x480]
100005850: 4fc0905d    	fmul.2d	v29, v2, v0[0]
100005854: 4e7bd7bb    	fadd.2d	v27, v29, v27
100005858: 4fd990dd    	fmul.2d	v29, v6, v25[0]
10000585c: 4e7bd7bd    	fadd.2d	v29, v29, v27
100005860: 4fd5927b    	fmul.2d	v27, v19, v21[0]
100005864: 3dc153e3    	ldr	q3, [sp, #0x540]
100005868: 4fd59868    	fmul.2d	v8, v3, v21[1]
10000586c: 4e68d77b    	fadd.2d	v27, v27, v8
100005870: 4fd69248    	fmul.2d	v8, v18, v22[0]
100005874: 4e68d77b    	fadd.2d	v27, v27, v8
100005878: 4fd69b88    	fmul.2d	v8, v28, v22[1]
10000587c: 4e68d77b    	fadd.2d	v27, v27, v8
100005880: 3dc18fe6    	ldr	q6, [sp, #0x630]
100005884: 4fd890c8    	fmul.2d	v8, v6, v24[0]
100005888: 4e68d77b    	fadd.2d	v27, v27, v8
10000588c: 4fd89928    	fmul.2d	v8, v9, v24[1]
100005890: 4e68d77b    	fadd.2d	v27, v27, v8
100005894: 3cd903ad    	ldur	q13, [x29, #-0x70]
100005898: 4fc091a8    	fmul.2d	v8, v13, v0[0]
10000589c: 4e7bd51b    	fadd.2d	v27, v8, v27
1000058a0: 4fd992e8    	fmul.2d	v8, v23, v25[0]
1000058a4: 4e7bd508    	fadd.2d	v8, v8, v27
1000058a8: ad55a51b    	ldp	q27, q9, [x8, #0x2b0]
1000058ac: 3dc19fe3    	ldr	q3, [sp, #0x670]
1000058b0: 4fdb906b    	fmul.2d	v11, v3, v27[0]
1000058b4: 4e7ed57e    	fadd.2d	v30, v11, v30
1000058b8: 3cd703a3    	ldur	q3, [x29, #-0x90]
1000058bc: 4fdb986b    	fmul.2d	v11, v3, v27[1]
1000058c0: 4e7ed57e    	fadd.2d	v30, v11, v30
1000058c4: 3dc15be3    	ldr	q3, [sp, #0x560]
1000058c8: 6e63deab    	fmul.2d	v11, v21, v3
1000058cc: 4e6bd42b    	fadd.2d	v11, v1, v11
1000058d0: 4ea11c24    	mov.16b	v4, v1
1000058d4: 4e7ed561    	fadd.2d	v1, v11, v30
1000058d8: 3d809be1    	str	q1, [sp, #0x260]
1000058dc: 3dc17fe3    	ldr	q3, [sp, #0x5f0]
1000058e0: 4fdb907e    	fmul.2d	v30, v3, v27[0]
1000058e4: 4e7fd7de    	fadd.2d	v30, v30, v31
1000058e8: 3cd503a1    	ldur	q1, [x29, #-0xb0]
1000058ec: 4fdb983f    	fmul.2d	v31, v1, v27[1]
1000058f0: 4e7ed7fe    	fadd.2d	v30, v31, v30
1000058f4: 3dc177e1    	ldr	q1, [sp, #0x5d0]
1000058f8: 6e61dedf    	fmul.2d	v31, v22, v1
1000058fc: 4eb01e01    	mov.16b	v1, v16
100005900: 4e7fd61f    	fadd.2d	v31, v16, v31
100005904: 4e7ed7f0    	fadd.2d	v16, v31, v30
100005908: 3dc187f7    	ldr	q23, [sp, #0x610]
10000590c: 4fdb92fe    	fmul.2d	v30, v23, v27[0]
100005910: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005914: 3dc1dbe5    	ldr	q5, [sp, #0x760]
100005918: 4fdb98be    	fmul.2d	v30, v5, v27[1]
10000591c: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005920: 3dc173e5    	ldr	q5, [sp, #0x5c0]
100005924: 6e65df1e    	fmul.2d	v30, v24, v5
100005928: 4e7ed45e    	fadd.2d	v30, v2, v30
10000592c: 4ea21c4b    	mov.16b	v11, v2
100005930: 4e7dd7c2    	fadd.2d	v2, v30, v29
100005934: ad11c3e2    	stp	q2, q16, [sp, #0x230]
100005938: 3dc183f2    	ldr	q18, [sp, #0x600]
10000593c: 4fdb925d    	fmul.2d	v29, v18, v27[0]
100005940: 4e68d7bd    	fadd.2d	v29, v29, v8
100005944: ad78cfa2    	ldp	q2, q19, [x29, #-0xf0]
100005948: 4fdb985e    	fmul.2d	v30, v2, v27[1]
10000594c: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005950: 4ea01c1e    	mov.16b	v30, v0
100005954: 6e18073e    	mov.d	v30[1], v25[0]
100005958: 6e73dfde    	fmul.2d	v30, v30, v19
10000595c: 4e7ed5be    	fadd.2d	v30, v13, v30
100005960: 4ead1db0    	mov.16b	v16, v13
100005964: 4e7dd7c2    	fadd.2d	v2, v30, v29
100005968: 3d8087e2    	str	q2, [sp, #0x210]
10000596c: 3dc13fe2    	ldr	q2, [sp, #0x4f0]
100005970: 4fd5905d    	fmul.2d	v29, v2, v21[0]
100005974: 3dc197e2    	ldr	q2, [sp, #0x650]
100005978: 4fd5985e    	fmul.2d	v30, v2, v21[1]
10000597c: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005980: 3dc167e2    	ldr	q2, [sp, #0x590]
100005984: 4fd6905e    	fmul.2d	v30, v2, v22[0]
100005988: 4e7ed7bd    	fadd.2d	v29, v29, v30
10000598c: 3dc1cbe2    	ldr	q2, [sp, #0x720]
100005990: 4fd6985e    	fmul.2d	v30, v2, v22[1]
100005994: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005998: 3dc1cffc    	ldr	q28, [sp, #0x730]
10000599c: 4fd8939e    	fmul.2d	v30, v28, v24[0]
1000059a0: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000059a4: 3dc1abe2    	ldr	q2, [sp, #0x6a0]
1000059a8: 4fd8985e    	fmul.2d	v30, v2, v24[1]
1000059ac: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000059b0: 3dc18be2    	ldr	q2, [sp, #0x620]
1000059b4: 4fc0905e    	fmul.2d	v30, v2, v0[0]
1000059b8: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000059bc: 3cd303a5    	ldur	q5, [x29, #-0xd0]
1000059c0: 4fd990be    	fmul.2d	v30, v5, v25[0]
1000059c4: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000059c8: 3cda03a5    	ldur	q5, [x29, #-0x60]
1000059cc: 4fdb90be    	fmul.2d	v30, v5, v27[0]
1000059d0: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000059d4: 3dc1dfe5    	ldr	q5, [sp, #0x770]
1000059d8: 4fdb98be    	fmul.2d	v30, v5, v27[1]
1000059dc: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000059e0: 3dc19be5    	ldr	q5, [sp, #0x660]
1000059e4: 6e65df7e    	fmul.2d	v30, v27, v5
1000059e8: 4e7ed45e    	fadd.2d	v30, v2, v30
1000059ec: 4e7dd7c2    	fadd.2d	v2, v30, v29
1000059f0: 3d8027e2    	str	q2, [sp, #0x90]
1000059f4: 3dc17be2    	ldr	q2, [sp, #0x5e0]
1000059f8: 4fd5905d    	fmul.2d	v29, v2, v21[0]
1000059fc: 3dc14be2    	ldr	q2, [sp, #0x520]
100005a00: 4fd59855    	fmul.2d	v21, v2, v21[1]
100005a04: 4e75d7b5    	fadd.2d	v21, v29, v21
100005a08: 3dc1afe2    	ldr	q2, [sp, #0x6b0]
100005a0c: 4fd6905d    	fmul.2d	v29, v2, v22[0]
100005a10: 4e7dd6b5    	fadd.2d	v21, v21, v29
100005a14: 3dc1d3e2    	ldr	q2, [sp, #0x740]
100005a18: 4fd69856    	fmul.2d	v22, v2, v22[1]
100005a1c: 4e76d6b5    	fadd.2d	v21, v21, v22
100005a20: 3dc1d7e2    	ldr	q2, [sp, #0x750]
100005a24: 4fd89056    	fmul.2d	v22, v2, v24[0]
100005a28: 4e76d6b5    	fadd.2d	v21, v21, v22
100005a2c: 3dc11fed    	ldr	q13, [sp, #0x470]
100005a30: 4fd899b6    	fmul.2d	v22, v13, v24[1]
100005a34: 4e76d6b5    	fadd.2d	v21, v21, v22
100005a38: 3dc1a7e2    	ldr	q2, [sp, #0x690]
100005a3c: 4fc09056    	fmul.2d	v22, v2, v0[0]
100005a40: 4e75d6d5    	fadd.2d	v21, v22, v21
100005a44: 3dc16fe0    	ldr	q0, [sp, #0x5b0]
100005a48: 4fd99016    	fmul.2d	v22, v0, v25[0]
100005a4c: 4e75d6d5    	fadd.2d	v21, v22, v21
100005a50: 3cd403a0    	ldur	q0, [x29, #-0xc0]
100005a54: 4fdb9016    	fmul.2d	v22, v0, v27[0]
100005a58: 4e75d6d5    	fadd.2d	v21, v22, v21
100005a5c: 3cd803a0    	ldur	q0, [x29, #-0x80]
100005a60: 4fdb9816    	fmul.2d	v22, v0, v27[1]
100005a64: 4e75d6d5    	fadd.2d	v21, v22, v21
100005a68: 3dc1bbe0    	ldr	q0, [sp, #0x6e0]
100005a6c: 6e60dd36    	fmul.2d	v22, v9, v0
100005a70: 4e76d456    	fadd.2d	v22, v2, v22
100005a74: 4e76d6a0    	fadd.2d	v0, v21, v22
100005a78: 3d8023e0    	str	q0, [sp, #0x80]
100005a7c: ad56d915    	ldp	q21, q22, [x8, #0x2d0]
100005a80: 3dc14fe0    	ldr	q0, [sp, #0x530]
100005a84: 6e75dc18    	fmul.2d	v24, v0, v21
100005a88: 6e184318    	ext.16b	v24, v24, v24, #0x8
100005a8c: 3cd603a0    	ldur	q0, [x29, #-0xa0]
100005a90: 6e75dc19    	fmul.2d	v25, v0, v21
100005a94: 4e79d718    	fadd.2d	v24, v24, v25
100005a98: 4fd69159    	fmul.2d	v25, v10, v22[0]
100005a9c: 4e79d718    	fadd.2d	v24, v24, v25
100005aa0: 3dc1bfe0    	ldr	q0, [sp, #0x6f0]
100005aa4: 4fd69819    	fmul.2d	v25, v0, v22[1]
100005aa8: 4e79d719    	fadd.2d	v25, v24, v25
100005aac: 4fd59358    	fmul.2d	v24, v26, v21[0]
100005ab0: 3dc1c3e0    	ldr	q0, [sp, #0x700]
100005ab4: 4fd5981b    	fmul.2d	v27, v0, v21[1]
100005ab8: 4e7bd718    	fadd.2d	v24, v24, v27
100005abc: 4fd6919b    	fmul.2d	v27, v12, v22[0]
100005ac0: 4e7bd718    	fadd.2d	v24, v24, v27
100005ac4: 4fd69a9b    	fmul.2d	v27, v20, v22[1]
100005ac8: 4eb41e8a    	mov.16b	v10, v20
100005acc: 4e7bd71b    	fadd.2d	v27, v24, v27
100005ad0: 3dc0bd18    	ldr	q24, [x8, #0x2f0]
100005ad4: 3dc163e0    	ldr	q0, [sp, #0x580]
100005ad8: 4fd8901d    	fmul.2d	v29, v0, v24[0]
100005adc: 4e7dd739    	fadd.2d	v25, v25, v29
100005ae0: 4fd898fd    	fmul.2d	v29, v7, v24[1]
100005ae4: 4e7dd73d    	fadd.2d	v29, v25, v29
100005ae8: 3dc0c119    	ldr	q25, [x8, #0x300]
100005aec: 4fd9909e    	fmul.2d	v30, v4, v25[0]
100005af0: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005af4: 3dc117e7    	ldr	q7, [sp, #0x450]
100005af8: 3dc073e4    	ldr	q4, [sp, #0x1c0]
100005afc: 4fc490fe    	fmul.2d	v30, v7, v4[0]
100005b00: 4e7dd7de    	fadd.2d	v30, v30, v29
100005b04: 4fd8923d    	fmul.2d	v29, v17, v24[0]
100005b08: 4e7dd77b    	fadd.2d	v27, v27, v29
100005b0c: 3dc147e0    	ldr	q0, [sp, #0x510]
100005b10: 4fd8981d    	fmul.2d	v29, v0, v24[1]
100005b14: 4e7dd77b    	fadd.2d	v27, v27, v29
100005b18: 4fd9903d    	fmul.2d	v29, v1, v25[0]
100005b1c: 4e7dd77b    	fadd.2d	v27, v27, v29
100005b20: 3dc1b7f1    	ldr	q17, [sp, #0x6d0]
100005b24: 4fc4923d    	fmul.2d	v29, v17, v4[0]
100005b28: 4e7bd7bf    	fadd.2d	v31, v29, v27
100005b2c: 3dc10fe0    	ldr	q0, [sp, #0x430]
100005b30: 4fd5901b    	fmul.2d	v27, v0, v21[0]
100005b34: 4fd599dd    	fmul.2d	v29, v14, v21[1]
100005b38: 4e7dd77b    	fadd.2d	v27, v27, v29
100005b3c: 3dc127e0    	ldr	q0, [sp, #0x490]
100005b40: 4fd6901d    	fmul.2d	v29, v0, v22[0]
100005b44: 4e7dd77b    	fadd.2d	v27, v27, v29
100005b48: 3dc193e0    	ldr	q0, [sp, #0x640]
100005b4c: 4fd6981d    	fmul.2d	v29, v0, v22[1]
100005b50: 4e7dd77b    	fadd.2d	v27, v27, v29
100005b54: 4fd891fd    	fmul.2d	v29, v15, v24[0]
100005b58: 4e7dd77b    	fadd.2d	v27, v27, v29
100005b5c: 3dc143e0    	ldr	q0, [sp, #0x500]
100005b60: 4fd8981d    	fmul.2d	v29, v0, v24[1]
100005b64: 4e7dd77b    	fadd.2d	v27, v27, v29
100005b68: 4fd9917d    	fmul.2d	v29, v11, v25[0]
100005b6c: 4e7dd77b    	fadd.2d	v27, v27, v29
100005b70: 3dc16be2    	ldr	q2, [sp, #0x5a0]
100005b74: 4fc4905d    	fmul.2d	v29, v2, v4[0]
100005b78: 4e7bd7bd    	fadd.2d	v29, v29, v27
100005b7c: 3dc133e0    	ldr	q0, [sp, #0x4c0]
100005b80: 4fd5901b    	fmul.2d	v27, v0, v21[0]
100005b84: 3dc153e0    	ldr	q0, [sp, #0x540]
100005b88: 4fd59808    	fmul.2d	v8, v0, v21[1]
100005b8c: 4e68d77b    	fadd.2d	v27, v27, v8
100005b90: 3dc157e0    	ldr	q0, [sp, #0x550]
100005b94: 4fd69008    	fmul.2d	v8, v0, v22[0]
100005b98: 4e68d77b    	fadd.2d	v27, v27, v8
100005b9c: 3dc1a3e0    	ldr	q0, [sp, #0x680]
100005ba0: 4fd69808    	fmul.2d	v8, v0, v22[1]
100005ba4: 4e68d77b    	fadd.2d	v27, v27, v8
100005ba8: 4fd890c8    	fmul.2d	v8, v6, v24[0]
100005bac: 4e68d77b    	fadd.2d	v27, v27, v8
100005bb0: 3dc1b3e0    	ldr	q0, [sp, #0x6c0]
100005bb4: 4fd89808    	fmul.2d	v8, v0, v24[1]
100005bb8: 4e68d77b    	fadd.2d	v27, v27, v8
100005bbc: 4fd99208    	fmul.2d	v8, v16, v25[0]
100005bc0: 4e68d77b    	fadd.2d	v27, v27, v8
100005bc4: 3dc113ec    	ldr	q12, [sp, #0x440]
100005bc8: 4fc49188    	fmul.2d	v8, v12, v4[0]
100005bcc: 4e7bd508    	fadd.2d	v8, v8, v27
100005bd0: ad58a51b    	ldp	q27, q9, [x8, #0x310]
100005bd4: 3dc19fe5    	ldr	q5, [sp, #0x670]
100005bd8: 4fdb90ab    	fmul.2d	v11, v5, v27[0]
100005bdc: 4e7ed57e    	fadd.2d	v30, v11, v30
100005be0: 3cd703a0    	ldur	q0, [x29, #-0x90]
100005be4: 4fdb980b    	fmul.2d	v11, v0, v27[1]
100005be8: 4e7ed57e    	fadd.2d	v30, v11, v30
100005bec: 3dc15be1    	ldr	q1, [sp, #0x560]
100005bf0: 6e61deab    	fmul.2d	v11, v21, v1
100005bf4: 4e6bd4eb    	fadd.2d	v11, v7, v11
100005bf8: 4ea71cf0    	mov.16b	v16, v7
100005bfc: 4e7ed566    	fadd.2d	v6, v11, v30
100005c00: 3d8083e6    	str	q6, [sp, #0x200]
100005c04: 4fdb907e    	fmul.2d	v30, v3, v27[0]
100005c08: 4e7fd7de    	fadd.2d	v30, v30, v31
100005c0c: 3cd503b4    	ldur	q20, [x29, #-0xb0]
100005c10: 4fdb9a9f    	fmul.2d	v31, v20, v27[1]
100005c14: 4e7ed7fe    	fadd.2d	v30, v31, v30
100005c18: 3dc177eb    	ldr	q11, [sp, #0x5d0]
100005c1c: 6e6bdedf    	fmul.2d	v31, v22, v11
100005c20: 4e7fd63f    	fadd.2d	v31, v17, v31
100005c24: 4e7ed7e6    	fadd.2d	v6, v31, v30
100005c28: 3d807fe6    	str	q6, [sp, #0x1f0]
100005c2c: 4fdb92fe    	fmul.2d	v30, v23, v27[0]
100005c30: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005c34: 3dc1dbe3    	ldr	q3, [sp, #0x760]
100005c38: 4fdb987e    	fmul.2d	v30, v3, v27[1]
100005c3c: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005c40: 3dc173f1    	ldr	q17, [sp, #0x5c0]
100005c44: 6e71df1e    	fmul.2d	v30, v24, v17
100005c48: 4e7ed45e    	fadd.2d	v30, v2, v30
100005c4c: 4e7dd7c2    	fadd.2d	v2, v30, v29
100005c50: 3d8077e2    	str	q2, [sp, #0x1d0]
100005c54: 4fdb925d    	fmul.2d	v29, v18, v27[0]
100005c58: 4e68d7bd    	fadd.2d	v29, v29, v8
100005c5c: 3cd103a2    	ldur	q2, [x29, #-0xf0]
100005c60: 4fdb985e    	fmul.2d	v30, v2, v27[1]
100005c64: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005c68: 4eb91f3e    	mov.16b	v30, v25
100005c6c: 6e18049e    	mov.d	v30[1], v4[0]
100005c70: 6e73dfde    	fmul.2d	v30, v30, v19
100005c74: 4e7ed59e    	fadd.2d	v30, v12, v30
100005c78: 4e7dd7c2    	fadd.2d	v2, v30, v29
100005c7c: 3d801fe2    	str	q2, [sp, #0x70]
100005c80: 3dc13fe7    	ldr	q7, [sp, #0x4f0]
100005c84: 4fd590fd    	fmul.2d	v29, v7, v21[0]
100005c88: 3dc197e2    	ldr	q2, [sp, #0x650]
100005c8c: 4fd5985e    	fmul.2d	v30, v2, v21[1]
100005c90: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005c94: 3dc167f3    	ldr	q19, [sp, #0x590]
100005c98: 4fd6927e    	fmul.2d	v30, v19, v22[0]
100005c9c: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005ca0: 3dc1cbf7    	ldr	q23, [sp, #0x720]
100005ca4: 4fd69afe    	fmul.2d	v30, v23, v22[1]
100005ca8: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005cac: 4fd8939e    	fmul.2d	v30, v28, v24[0]
100005cb0: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005cb4: 3dc1abfa    	ldr	q26, [sp, #0x6a0]
100005cb8: 4fd89b5e    	fmul.2d	v30, v26, v24[1]
100005cbc: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005cc0: 3dc18be2    	ldr	q2, [sp, #0x620]
100005cc4: 4fd9905e    	fmul.2d	v30, v2, v25[0]
100005cc8: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005ccc: 3cd303a2    	ldur	q2, [x29, #-0xd0]
100005cd0: 4fc4905e    	fmul.2d	v30, v2, v4[0]
100005cd4: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005cd8: 3cda03a6    	ldur	q6, [x29, #-0x60]
100005cdc: 4fdb90de    	fmul.2d	v30, v6, v27[0]
100005ce0: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005ce4: 3dc1dffc    	ldr	q28, [sp, #0x770]
100005ce8: 4fdb9b9e    	fmul.2d	v30, v28, v27[1]
100005cec: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005cf0: 3dc19bef    	ldr	q15, [sp, #0x660]
100005cf4: 6e6fdf7e    	fmul.2d	v30, v27, v15
100005cf8: 4e7ed45e    	fadd.2d	v30, v2, v30
100005cfc: 4e7dd7c2    	fadd.2d	v2, v30, v29
100005d00: 3d80f3e2    	str	q2, [sp, #0x3c0]
100005d04: 3dc17be2    	ldr	q2, [sp, #0x5e0]
100005d08: 4fd5905d    	fmul.2d	v29, v2, v21[0]
100005d0c: 3dc14bee    	ldr	q14, [sp, #0x520]
100005d10: 4fd599d5    	fmul.2d	v21, v14, v21[1]
100005d14: 4e75d7b5    	fadd.2d	v21, v29, v21
100005d18: 3dc1afe2    	ldr	q2, [sp, #0x6b0]
100005d1c: 4fd6905d    	fmul.2d	v29, v2, v22[0]
100005d20: 4e7dd6b5    	fadd.2d	v21, v21, v29
100005d24: 3dc1d3e2    	ldr	q2, [sp, #0x740]
100005d28: 4fd69856    	fmul.2d	v22, v2, v22[1]
100005d2c: 4e76d6b5    	fadd.2d	v21, v21, v22
100005d30: 3dc1d7e2    	ldr	q2, [sp, #0x750]
100005d34: 4fd89056    	fmul.2d	v22, v2, v24[0]
100005d38: 4e76d6b5    	fadd.2d	v21, v21, v22
100005d3c: 4fd899b6    	fmul.2d	v22, v13, v24[1]
100005d40: 4e76d6b5    	fadd.2d	v21, v21, v22
100005d44: 3dc1a7e2    	ldr	q2, [sp, #0x690]
100005d48: 4fd99056    	fmul.2d	v22, v2, v25[0]
100005d4c: 4e76d6b5    	fadd.2d	v21, v21, v22
100005d50: 3dc16fe6    	ldr	q6, [sp, #0x5b0]
100005d54: 4fc490d6    	fmul.2d	v22, v6, v4[0]
100005d58: 4e75d6d5    	fadd.2d	v21, v22, v21
100005d5c: 3cd403a2    	ldur	q2, [x29, #-0xc0]
100005d60: 4fdb9056    	fmul.2d	v22, v2, v27[0]
100005d64: 4e75d6d5    	fadd.2d	v21, v22, v21
100005d68: 3cd803a2    	ldur	q2, [x29, #-0x80]
100005d6c: 4fdb9856    	fmul.2d	v22, v2, v27[1]
100005d70: 4e75d6d5    	fadd.2d	v21, v22, v21
100005d74: 3dc1bbe2    	ldr	q2, [sp, #0x6e0]
100005d78: 6e62dd36    	fmul.2d	v22, v9, v2
100005d7c: 4e76d4d6    	fadd.2d	v22, v6, v22
100005d80: 4e76d6a2    	fadd.2d	v2, v21, v22
100005d84: 3d801be2    	str	q2, [sp, #0x60]
100005d88: ad59d915    	ldp	q21, q22, [x8, #0x330]
100005d8c: 3dc14fed    	ldr	q13, [sp, #0x530]
100005d90: 6e75ddb8    	fmul.2d	v24, v13, v21
100005d94: 6e184318    	ext.16b	v24, v24, v24, #0x8
100005d98: 3cd603a2    	ldur	q2, [x29, #-0xa0]
100005d9c: 6e75dc59    	fmul.2d	v25, v2, v21
100005da0: 4e79d718    	fadd.2d	v24, v24, v25
100005da4: 3dc10be2    	ldr	q2, [sp, #0x420]
100005da8: 4fd69059    	fmul.2d	v25, v2, v22[0]
100005dac: 4e79d718    	fadd.2d	v24, v24, v25
100005db0: 3dc1bfe2    	ldr	q2, [sp, #0x6f0]
100005db4: 4fd69859    	fmul.2d	v25, v2, v22[1]
100005db8: 4e79d71b    	fadd.2d	v27, v24, v25
100005dbc: 3dc13be2    	ldr	q2, [sp, #0x4e0]
100005dc0: 4fd59058    	fmul.2d	v24, v2, v21[0]
100005dc4: 3dc1c3e2    	ldr	q2, [sp, #0x700]
100005dc8: 4fd59859    	fmul.2d	v25, v2, v21[1]
100005dcc: 4e79d718    	fadd.2d	v24, v24, v25
100005dd0: 3dc137e2    	ldr	q2, [sp, #0x4d0]
100005dd4: 4fd69059    	fmul.2d	v25, v2, v22[0]
100005dd8: 4e79d718    	fadd.2d	v24, v24, v25
100005ddc: 4fd69959    	fmul.2d	v25, v10, v22[1]
100005de0: 4e79d71d    	fadd.2d	v29, v24, v25
100005de4: ad5ae518    	ldp	q24, q25, [x8, #0x350]
100005de8: 3dc163e2    	ldr	q2, [sp, #0x580]
100005dec: 4fd8905e    	fmul.2d	v30, v2, v24[0]
100005df0: 4e7ed77b    	fadd.2d	v27, v27, v30
100005df4: 3dc12be6    	ldr	q6, [sp, #0x4a0]
100005df8: 4fd898de    	fmul.2d	v30, v6, v24[1]
100005dfc: 4e7ed77b    	fadd.2d	v27, v27, v30
100005e00: 3dc107e9    	ldr	q9, [sp, #0x410]
100005e04: 4fd8913e    	fmul.2d	v30, v9, v24[0]
100005e08: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005e0c: 3dc147e2    	ldr	q2, [sp, #0x510]
100005e10: 4fd8985e    	fmul.2d	v30, v2, v24[1]
100005e14: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005e18: 3dc10fe2    	ldr	q2, [sp, #0x430]
100005e1c: 4fd5905e    	fmul.2d	v30, v2, v21[0]
100005e20: 3dc12fe4    	ldr	q4, [sp, #0x4b0]
100005e24: 4fd5989f    	fmul.2d	v31, v4, v21[1]
100005e28: 4e7fd7de    	fadd.2d	v30, v30, v31
100005e2c: 3dc127ea    	ldr	q10, [sp, #0x490]
100005e30: 4fd6915f    	fmul.2d	v31, v10, v22[0]
100005e34: 4e7fd7de    	fadd.2d	v30, v30, v31
100005e38: 3dc193e4    	ldr	q4, [sp, #0x640]
100005e3c: 4fd6989f    	fmul.2d	v31, v4, v22[1]
100005e40: 4e7fd7de    	fadd.2d	v30, v30, v31
100005e44: 3dc15fe4    	ldr	q4, [sp, #0x570]
100005e48: 4fd8909f    	fmul.2d	v31, v4, v24[0]
100005e4c: 4e7fd7de    	fadd.2d	v30, v30, v31
100005e50: 3dc143e4    	ldr	q4, [sp, #0x500]
100005e54: 4fd8989f    	fmul.2d	v31, v4, v24[1]
100005e58: 4e7fd7de    	fadd.2d	v30, v30, v31
100005e5c: 3cd003a4    	ldur	q4, [x29, #-0x100]
100005e60: 4fd9909f    	fmul.2d	v31, v4, v25[0]
100005e64: 4e7fd77b    	fadd.2d	v27, v27, v31
100005e68: 4fd99a1f    	fmul.2d	v31, v16, v25[1]
100005e6c: 4e7fd77b    	fadd.2d	v27, v27, v31
100005e70: 4ea51ca4    	mov.16b	v4, v5
100005e74: 3dc0cfe5    	ldr	q5, [sp, #0x330]
100005e78: 4fc5909f    	fmul.2d	v31, v4, v5[0]
100005e7c: 4e7bd7ff    	fadd.2d	v31, v31, v27
100005e80: fd41a13b    	ldr	d27, [x9, #0x340]
100005e84: 4fdb9008    	fmul.2d	v8, v0, v27[0]
100005e88: 4e7fd51f    	fadd.2d	v31, v8, v31
100005e8c: 6e61dea8    	fmul.2d	v8, v21, v1
100005e90: 4e68d488    	fadd.2d	v8, v4, v8
100005e94: 4ea41c80    	mov.16b	v0, v4
100005e98: 4e7fd501    	fadd.2d	v1, v8, v31
100005e9c: 3d8017e1    	str	q1, [sp, #0x50]
100005ea0: 3dc1c7e1    	ldr	q1, [sp, #0x710]
100005ea4: 4fd9903f    	fmul.2d	v31, v1, v25[0]
100005ea8: 4e7fd7bd    	fadd.2d	v29, v29, v31
100005eac: 3dc1b7e1    	ldr	q1, [sp, #0x6d0]
100005eb0: 4fd9983f    	fmul.2d	v31, v1, v25[1]
100005eb4: 4e7fd7bd    	fadd.2d	v29, v29, v31
100005eb8: 3dc17fe1    	ldr	q1, [sp, #0x5f0]
100005ebc: 4ea51ca4    	mov.16b	v4, v5
100005ec0: 4fc5903f    	fmul.2d	v31, v1, v5[0]
100005ec4: 4e7dd7fd    	fadd.2d	v29, v31, v29
100005ec8: 4fdb929f    	fmul.2d	v31, v20, v27[0]
100005ecc: 4e7dd7fd    	fadd.2d	v29, v31, v29
100005ed0: 6e6bdedf    	fmul.2d	v31, v22, v11
100005ed4: 4e7fd43f    	fadd.2d	v31, v1, v31
100005ed8: 4e7dd7e1    	fadd.2d	v1, v31, v29
100005edc: 3d8073e1    	str	q1, [sp, #0x1c0]
100005ee0: 3dc123e5    	ldr	q5, [sp, #0x480]
100005ee4: 4fd990bd    	fmul.2d	v29, v5, v25[0]
100005ee8: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005eec: 3dc16be1    	ldr	q1, [sp, #0x5a0]
100005ef0: 4fd9983e    	fmul.2d	v30, v1, v25[1]
100005ef4: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005ef8: 3dc187e1    	ldr	q1, [sp, #0x610]
100005efc: 4fc4903e    	fmul.2d	v30, v1, v4[0]
100005f00: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005f04: 4fdb907e    	fmul.2d	v30, v3, v27[0]
100005f08: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005f0c: 6e71df1e    	fmul.2d	v30, v24, v17
100005f10: 4e7ed43e    	fadd.2d	v30, v1, v30
100005f14: 4e7dd7c1    	fadd.2d	v1, v30, v29
100005f18: 3d806fe1    	str	q1, [sp, #0x1b0]
100005f1c: 3dc133eb    	ldr	q11, [sp, #0x4c0]
100005f20: 4fd5917d    	fmul.2d	v29, v11, v21[0]
100005f24: 3dc153e1    	ldr	q1, [sp, #0x540]
100005f28: 4fd5983e    	fmul.2d	v30, v1, v21[1]
100005f2c: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005f30: 3dc157e1    	ldr	q1, [sp, #0x550]
100005f34: 4fd6903e    	fmul.2d	v30, v1, v22[0]
100005f38: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005f3c: 3dc1a3e1    	ldr	q1, [sp, #0x680]
100005f40: 4fd6983e    	fmul.2d	v30, v1, v22[1]
100005f44: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005f48: 3dc18fe1    	ldr	q1, [sp, #0x630]
100005f4c: 4fd8903e    	fmul.2d	v30, v1, v24[0]
100005f50: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005f54: 3dc1b3e1    	ldr	q1, [sp, #0x6c0]
100005f58: 4fd8983e    	fmul.2d	v30, v1, v24[1]
100005f5c: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005f60: 3cd903a1    	ldur	q1, [x29, #-0x70]
100005f64: 4fd9903e    	fmul.2d	v30, v1, v25[0]
100005f68: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005f6c: 4fd9999e    	fmul.2d	v30, v12, v25[1]
100005f70: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005f74: 3dc183e3    	ldr	q3, [sp, #0x600]
100005f78: 4fc4907e    	fmul.2d	v30, v3, v4[0]
100005f7c: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005f80: 3cd103a1    	ldur	q1, [x29, #-0xf0]
100005f84: 4fdb903e    	fmul.2d	v30, v1, v27[0]
100005f88: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005f8c: 3cd203a1    	ldur	q1, [x29, #-0xe0]
100005f90: 6e61df3e    	fmul.2d	v30, v25, v1
100005f94: 4e7ed47e    	fadd.2d	v30, v3, v30
100005f98: 4e7dd7c1    	fadd.2d	v1, v30, v29
100005f9c: 3d8067e1    	str	q1, [sp, #0x190]
100005fa0: 4fd590fd    	fmul.2d	v29, v7, v21[0]
100005fa4: 3dc197e1    	ldr	q1, [sp, #0x650]
100005fa8: 4fd5983e    	fmul.2d	v30, v1, v21[1]
100005fac: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005fb0: 4fd6927e    	fmul.2d	v30, v19, v22[0]
100005fb4: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005fb8: 4fd69afe    	fmul.2d	v30, v23, v22[1]
100005fbc: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005fc0: 3dc1cfe3    	ldr	q3, [sp, #0x730]
100005fc4: 4fd8907e    	fmul.2d	v30, v3, v24[0]
100005fc8: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005fcc: 4fd89b5e    	fmul.2d	v30, v26, v24[1]
100005fd0: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005fd4: 3dc18be3    	ldr	q3, [sp, #0x620]
100005fd8: 4fd9907e    	fmul.2d	v30, v3, v25[0]
100005fdc: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005fe0: 3cd303a3    	ldur	q3, [x29, #-0xd0]
100005fe4: 4fd9987e    	fmul.2d	v30, v3, v25[1]
100005fe8: 4e7ed7bd    	fadd.2d	v29, v29, v30
100005fec: 3cda03a3    	ldur	q3, [x29, #-0x60]
100005ff0: 4fc4907e    	fmul.2d	v30, v3, v4[0]
100005ff4: 4e7dd7dd    	fadd.2d	v29, v30, v29
100005ff8: 4fdb939e    	fmul.2d	v30, v28, v27[0]
100005ffc: 4e7dd7dd    	fadd.2d	v29, v30, v29
100006000: 4ea41c9e    	mov.16b	v30, v4
100006004: 6e18077e    	mov.d	v30[1], v27[0]
100006008: 6e6fdfde    	fmul.2d	v30, v30, v15
10000600c: 4e7ed47e    	fadd.2d	v30, v3, v30
100006010: 4e7dd7c3    	fadd.2d	v3, v30, v29
100006014: 3d8013e3    	str	q3, [sp, #0x40]
100006018: 3dc17bf3    	ldr	q19, [sp, #0x5e0]
10000601c: 4fd5927d    	fmul.2d	v29, v19, v21[0]
100006020: 4fd599d5    	fmul.2d	v21, v14, v21[1]
100006024: 4e75d7b5    	fadd.2d	v21, v29, v21
100006028: 3dc1afe3    	ldr	q3, [sp, #0x6b0]
10000602c: 4fd6907d    	fmul.2d	v29, v3, v22[0]
100006030: 4e7dd6b5    	fadd.2d	v21, v21, v29
100006034: 3dc1d3e3    	ldr	q3, [sp, #0x740]
100006038: 4fd69876    	fmul.2d	v22, v3, v22[1]
10000603c: 4e76d6b5    	fadd.2d	v21, v21, v22
100006040: 3dc1d7e3    	ldr	q3, [sp, #0x750]
100006044: 4fd89076    	fmul.2d	v22, v3, v24[0]
100006048: 4e76d6b5    	fadd.2d	v21, v21, v22
10000604c: 3dc11fe3    	ldr	q3, [sp, #0x470]
100006050: 4fd89876    	fmul.2d	v22, v3, v24[1]
100006054: 4e76d6b5    	fadd.2d	v21, v21, v22
100006058: 3dc1a7e3    	ldr	q3, [sp, #0x690]
10000605c: 4fd99076    	fmul.2d	v22, v3, v25[0]
100006060: 4e76d6b5    	fadd.2d	v21, v21, v22
100006064: 3dc16fe3    	ldr	q3, [sp, #0x5b0]
100006068: 4fd99876    	fmul.2d	v22, v3, v25[1]
10000606c: 4e76d6b5    	fadd.2d	v21, v21, v22
100006070: 3cd403a3    	ldur	q3, [x29, #-0xc0]
100006074: 4fc49076    	fmul.2d	v22, v3, v4[0]
100006078: 4e75d6d5    	fadd.2d	v21, v22, v21
10000607c: 3cd803a4    	ldur	q4, [x29, #-0x80]
100006080: 4fdb9096    	fmul.2d	v22, v4, v27[0]
100006084: 4e75d6d6    	fadd.2d	v22, v22, v21
100006088: ad5c5518    	ldp	q24, q21, [x8, #0x380]
10000608c: 3dc1bbe4    	ldr	q4, [sp, #0x6e0]
100006090: 6e64df18    	fmul.2d	v24, v24, v4
100006094: 4e78d478    	fadd.2d	v24, v3, v24
100006098: 4e78d6c3    	fadd.2d	v3, v22, v24
10000609c: 3d80cfe3    	str	q3, [sp, #0x330]
1000060a0: 6e75ddb6    	fmul.2d	v22, v13, v21
1000060a4: 6e1642d6    	ext.16b	v22, v22, v22, #0x8
1000060a8: 3cd603a3    	ldur	q3, [x29, #-0xa0]
1000060ac: 6e75dc78    	fmul.2d	v24, v3, v21
1000060b0: 4e78d6d9    	fadd.2d	v25, v22, v24
1000060b4: ad5d6116    	ldp	q22, q24, [x8, #0x3a0]
1000060b8: 3dc10bfa    	ldr	q26, [sp, #0x420]
1000060bc: 4fd6935b    	fmul.2d	v27, v26, v22[0]
1000060c0: 4e7bd739    	fadd.2d	v25, v25, v27
1000060c4: 3dc1bffc    	ldr	q28, [sp, #0x6f0]
1000060c8: 4fd69b9b    	fmul.2d	v27, v28, v22[1]
1000060cc: 4e7bd739    	fadd.2d	v25, v25, v27
1000060d0: 3dc13be3    	ldr	q3, [sp, #0x4e0]
1000060d4: 4fd5907b    	fmul.2d	v27, v3, v21[0]
1000060d8: 3dc1c3f1    	ldr	q17, [sp, #0x700]
1000060dc: 4fd59a3d    	fmul.2d	v29, v17, v21[1]
1000060e0: 4e7dd77b    	fadd.2d	v27, v27, v29
1000060e4: 3dc137e3    	ldr	q3, [sp, #0x4d0]
1000060e8: 4fd6907d    	fmul.2d	v29, v3, v22[0]
1000060ec: 4e7dd77b    	fadd.2d	v27, v27, v29
1000060f0: 3dc11bee    	ldr	q14, [sp, #0x460]
1000060f4: 4fd699dd    	fmul.2d	v29, v14, v22[1]
1000060f8: 4e7dd77b    	fadd.2d	v27, v27, v29
1000060fc: 3dc163ef    	ldr	q15, [sp, #0x580]
100006100: 4fd891fd    	fmul.2d	v29, v15, v24[0]
100006104: 4e7dd739    	fadd.2d	v25, v25, v29
100006108: 4fd898dd    	fmul.2d	v29, v6, v24[1]
10000610c: 4e7dd73d    	fadd.2d	v29, v25, v29
100006110: 4fd89139    	fmul.2d	v25, v9, v24[0]
100006114: 4e79d779    	fadd.2d	v25, v27, v25
100006118: 3dc147f4    	ldr	q20, [sp, #0x510]
10000611c: 4fd89a9b    	fmul.2d	v27, v20, v24[1]
100006120: 4e7bd73e    	fadd.2d	v30, v25, v27
100006124: 4fd59059    	fmul.2d	v25, v2, v21[0]
100006128: 3dc12ff2    	ldr	q18, [sp, #0x4b0]
10000612c: 4fd59a5b    	fmul.2d	v27, v18, v21[1]
100006130: 4e7bd739    	fadd.2d	v25, v25, v27
100006134: 4fd6915b    	fmul.2d	v27, v10, v22[0]
100006138: 4e7bd739    	fadd.2d	v25, v25, v27
10000613c: 3dc193f7    	ldr	q23, [sp, #0x640]
100006140: 4fd69afb    	fmul.2d	v27, v23, v22[1]
100006144: 4e7bd739    	fadd.2d	v25, v25, v27
100006148: 3dc15fe2    	ldr	q2, [sp, #0x570]
10000614c: 4fd8905b    	fmul.2d	v27, v2, v24[0]
100006150: 4e7bd739    	fadd.2d	v25, v25, v27
100006154: 3dc143ea    	ldr	q10, [sp, #0x500]
100006158: 4fd8995b    	fmul.2d	v27, v10, v24[1]
10000615c: 4e7bd73f    	fadd.2d	v31, v25, v27
100006160: 3dc0f119    	ldr	q25, [x8, #0x3c0]
100006164: 3cd003a2    	ldur	q2, [x29, #-0x100]
100006168: 4fd9905b    	fmul.2d	v27, v2, v25[0]
10000616c: 4e7bd7bb    	fadd.2d	v27, v29, v27
100006170: 4fd99a1d    	fmul.2d	v29, v16, v25[1]
100006174: 4e7dd77d    	fadd.2d	v29, v27, v29
100006178: 3dc0f51b    	ldr	q27, [x8, #0x3d0]
10000617c: 4fdb9008    	fmul.2d	v8, v0, v27[0]
100006180: 4e68d7bd    	fadd.2d	v29, v29, v8
100006184: 3cd703a0    	ldur	q0, [x29, #-0x90]
100006188: 3dc0d3e6    	ldr	q6, [sp, #0x340]
10000618c: 4fc69008    	fmul.2d	v8, v0, v6[0]
100006190: 4e7dd51d    	fadd.2d	v29, v8, v29
100006194: 3dc15be3    	ldr	q3, [sp, #0x560]
100006198: 6e63dea8    	fmul.2d	v8, v21, v3
10000619c: 4e68d408    	fadd.2d	v8, v0, v8
1000061a0: 4e7dd500    	fadd.2d	v0, v8, v29
1000061a4: 3d806be0    	str	q0, [sp, #0x1a0]
1000061a8: 3dc1c7f0    	ldr	q16, [sp, #0x710]
1000061ac: 4fd9921d    	fmul.2d	v29, v16, v25[0]
1000061b0: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000061b4: 3dc1b7e0    	ldr	q0, [sp, #0x6d0]
1000061b8: 4fd9981e    	fmul.2d	v30, v0, v25[1]
1000061bc: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000061c0: 3dc17fe0    	ldr	q0, [sp, #0x5f0]
1000061c4: 4fdb901e    	fmul.2d	v30, v0, v27[0]
1000061c8: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000061cc: 3cd503a2    	ldur	q2, [x29, #-0xb0]
1000061d0: 4fc6905e    	fmul.2d	v30, v2, v6[0]
1000061d4: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000061d8: 3dc177e0    	ldr	q0, [sp, #0x5d0]
1000061dc: 6e60dede    	fmul.2d	v30, v22, v0
1000061e0: 4e7ed45e    	fadd.2d	v30, v2, v30
1000061e4: 4e7dd7c4    	fadd.2d	v4, v30, v29
1000061e8: 4fd990bd    	fmul.2d	v29, v5, v25[0]
1000061ec: 4e7dd7fd    	fadd.2d	v29, v31, v29
1000061f0: 3dc16be2    	ldr	q2, [sp, #0x5a0]
1000061f4: 4fd9985e    	fmul.2d	v30, v2, v25[1]
1000061f8: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000061fc: 3dc187e2    	ldr	q2, [sp, #0x610]
100006200: 4fdb905e    	fmul.2d	v30, v2, v27[0]
100006204: 4e7ed7bd    	fadd.2d	v29, v29, v30
100006208: 3dc1dbe2    	ldr	q2, [sp, #0x760]
10000620c: 4fc6905e    	fmul.2d	v30, v2, v6[0]
100006210: 4e7dd7dd    	fadd.2d	v29, v30, v29
100006214: 3dc173e7    	ldr	q7, [sp, #0x5c0]
100006218: 6e67df1e    	fmul.2d	v30, v24, v7
10000621c: 4e7ed45e    	fadd.2d	v30, v2, v30
100006220: 4e7dd7c2    	fadd.2d	v2, v30, v29
100006224: ad0b93e2    	stp	q2, q4, [sp, #0x170]
100006228: 4fd5917d    	fmul.2d	v29, v11, v21[0]
10000622c: 3dc153ed    	ldr	q13, [sp, #0x540]
100006230: 4fd599be    	fmul.2d	v30, v13, v21[1]
100006234: 4e7ed7bd    	fadd.2d	v29, v29, v30
100006238: 3dc157eb    	ldr	q11, [sp, #0x550]
10000623c: 4fd6917e    	fmul.2d	v30, v11, v22[0]
100006240: 4e7ed7bd    	fadd.2d	v29, v29, v30
100006244: 3dc1a3ec    	ldr	q12, [sp, #0x680]
100006248: 4fd6999e    	fmul.2d	v30, v12, v22[1]
10000624c: 4e7ed7bd    	fadd.2d	v29, v29, v30
100006250: 3dc18fe2    	ldr	q2, [sp, #0x630]
100006254: 4fd8905e    	fmul.2d	v30, v2, v24[0]
100006258: 4e7ed7bd    	fadd.2d	v29, v29, v30
10000625c: 3dc1b3e2    	ldr	q2, [sp, #0x6c0]
100006260: 4fd8985e    	fmul.2d	v30, v2, v24[1]
100006264: 4e7ed7bd    	fadd.2d	v29, v29, v30
100006268: 3cd903a4    	ldur	q4, [x29, #-0x70]
10000626c: 4fd9909e    	fmul.2d	v30, v4, v25[0]
100006270: 4e7ed7bd    	fadd.2d	v29, v29, v30
100006274: 3dc113e4    	ldr	q4, [sp, #0x440]
100006278: 4fd9989e    	fmul.2d	v30, v4, v25[1]
10000627c: 4e7ed7bd    	fadd.2d	v29, v29, v30
100006280: 3dc183e4    	ldr	q4, [sp, #0x600]
100006284: 4fdb909e    	fmul.2d	v30, v4, v27[0]
100006288: 4e7ed7bd    	fadd.2d	v29, v29, v30
10000628c: ad7897a4    	ldp	q4, q5, [x29, #-0xf0]
100006290: 4fc6909e    	fmul.2d	v30, v4, v6[0]
100006294: 4e7dd7dd    	fadd.2d	v29, v30, v29
100006298: 6e65df3e    	fmul.2d	v30, v25, v5
10000629c: 4e7ed49e    	fadd.2d	v30, v4, v30
1000062a0: 4e7dd7c4    	fadd.2d	v4, v30, v29
1000062a4: 3d8057e4    	str	q4, [sp, #0x150]
1000062a8: 3dc13fe5    	ldr	q5, [sp, #0x4f0]
1000062ac: 4fd590bd    	fmul.2d	v29, v5, v21[0]
1000062b0: 4fd5983e    	fmul.2d	v30, v1, v21[1]
1000062b4: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000062b8: 3dc167e1    	ldr	q1, [sp, #0x590]
1000062bc: 4fd6903e    	fmul.2d	v30, v1, v22[0]
1000062c0: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000062c4: 3dc1cbe1    	ldr	q1, [sp, #0x720]
1000062c8: 4fd6983e    	fmul.2d	v30, v1, v22[1]
1000062cc: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000062d0: 3dc1cfe1    	ldr	q1, [sp, #0x730]
1000062d4: 4fd8903e    	fmul.2d	v30, v1, v24[0]
1000062d8: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000062dc: 3dc1abe1    	ldr	q1, [sp, #0x6a0]
1000062e0: 4fd8983e    	fmul.2d	v30, v1, v24[1]
1000062e4: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000062e8: 3dc18be4    	ldr	q4, [sp, #0x620]
1000062ec: 4fd9909e    	fmul.2d	v30, v4, v25[0]
1000062f0: 4e7ed7bd    	fadd.2d	v29, v29, v30
1000062f4: 3cd303a1    	ldur	q1, [x29, #-0xd0]
1000062f8: 4fd9983e    	fmul.2d	v30, v1, v25[1]
1000062fc: 4e7ed7bd    	fadd.2d	v29, v29, v30
100006300: 3cda03a1    	ldur	q1, [x29, #-0x60]
100006304: 4fdb903e    	fmul.2d	v30, v1, v27[0]
100006308: 4e7ed7bd    	fadd.2d	v29, v29, v30
10000630c: 3dc1dfe1    	ldr	q1, [sp, #0x770]
100006310: 4fc6903e    	fmul.2d	v30, v1, v6[0]
100006314: 4e7dd7dd    	fadd.2d	v29, v30, v29
100006318: 4ebb1f7e    	mov.16b	v30, v27
10000631c: 6e1804de    	mov.d	v30[1], v6[0]
100006320: 4ea61cdf    	mov.16b	v31, v6
100006324: 3dc19be6    	ldr	q6, [sp, #0x660]
100006328: 6e66dfde    	fmul.2d	v30, v30, v6
10000632c: 4e7ed43e    	fadd.2d	v30, v1, v30
100006330: 4e7dd7c1    	fadd.2d	v1, v30, v29
100006334: 3d800fe1    	str	q1, [sp, #0x30]
100006338: 4fd5927d    	fmul.2d	v29, v19, v21[0]
10000633c: 3dc14be1    	ldr	q1, [sp, #0x520]
100006340: 4fd59835    	fmul.2d	v21, v1, v21[1]
100006344: 4e75d7b5    	fadd.2d	v21, v29, v21
100006348: 3dc1aff3    	ldr	q19, [sp, #0x6b0]
10000634c: 4fd6927d    	fmul.2d	v29, v19, v22[0]
100006350: 4e7dd6b5    	fadd.2d	v21, v21, v29
100006354: 3dc1d3e1    	ldr	q1, [sp, #0x740]
100006358: 4fd69836    	fmul.2d	v22, v1, v22[1]
10000635c: 4e76d6b5    	fadd.2d	v21, v21, v22
100006360: 3dc1d7e1    	ldr	q1, [sp, #0x750]
100006364: 4fd89036    	fmul.2d	v22, v1, v24[0]
100006368: 4e76d6b5    	fadd.2d	v21, v21, v22
10000636c: 3dc11fe6    	ldr	q6, [sp, #0x470]
100006370: 4fd898d6    	fmul.2d	v22, v6, v24[1]
100006374: 4e76d6b5    	fadd.2d	v21, v21, v22
100006378: 3dc1a7e6    	ldr	q6, [sp, #0x690]
10000637c: 4fd990d6    	fmul.2d	v22, v6, v25[0]
100006380: 4e76d6b5    	fadd.2d	v21, v21, v22
100006384: 3dc16fe6    	ldr	q6, [sp, #0x5b0]
100006388: 4fd998d6    	fmul.2d	v22, v6, v25[1]
10000638c: 4e76d6b5    	fadd.2d	v21, v21, v22
100006390: 3cd403a6    	ldur	q6, [x29, #-0xc0]
100006394: 4fdb90d6    	fmul.2d	v22, v6, v27[0]
100006398: 4e76d6b5    	fadd.2d	v21, v21, v22
10000639c: 3cd803a6    	ldur	q6, [x29, #-0x80]
1000063a0: 4fdf90d6    	fmul.2d	v22, v6, v31[0]
1000063a4: 4e75d6d5    	fadd.2d	v21, v22, v21
1000063a8: ad5f5918    	ldp	q24, q22, [x8, #0x3e0]
1000063ac: 3dc1bbf9    	ldr	q25, [sp, #0x6e0]
1000063b0: 6e79df18    	fmul.2d	v24, v24, v25
1000063b4: 4e78d4d8    	fadd.2d	v24, v6, v24
1000063b8: 4e78d6a6    	fadd.2d	v6, v21, v24
1000063bc: 3d800be6    	str	q6, [sp, #0x20]
1000063c0: 3dc14fe6    	ldr	q6, [sp, #0x530]
1000063c4: 6e76dcd5    	fmul.2d	v21, v6, v22
1000063c8: 6e1542b5    	ext.16b	v21, v21, v21, #0x8
1000063cc: 3cd603a6    	ldur	q6, [x29, #-0xa0]
1000063d0: 6e76dcd8    	fmul.2d	v24, v6, v22
1000063d4: 4e78d6b9    	fadd.2d	v25, v21, v24
1000063d8: 3dc33d15    	ldr	q21, [x8, #0xcf0]
1000063dc: 6e63ded8    	fmul.2d	v24, v22, v3
1000063e0: 4e75d715    	fadd.2d	v21, v24, v21
1000063e4: 3dc10118    	ldr	q24, [x8, #0x400]
1000063e8: 4fd8935b    	fmul.2d	v27, v26, v24[0]
1000063ec: 4e7bd739    	fadd.2d	v25, v25, v27
1000063f0: 4fd89b9b    	fmul.2d	v27, v28, v24[1]
1000063f4: 4e7bd73d    	fadd.2d	v29, v25, v27
1000063f8: 3dc13be3    	ldr	q3, [sp, #0x4e0]
1000063fc: 4fd69079    	fmul.2d	v25, v3, v22[0]
100006400: 4fd69a3b    	fmul.2d	v27, v17, v22[1]
100006404: 4e7bd739    	fadd.2d	v25, v25, v27
100006408: 3dc137fc    	ldr	q28, [sp, #0x4d0]
10000640c: 4fd8939b    	fmul.2d	v27, v28, v24[0]
100006410: 4e7bd739    	fadd.2d	v25, v25, v27
100006414: 4fd899db    	fmul.2d	v27, v14, v24[1]
100006418: 4e7bd73f    	fadd.2d	v31, v25, v27
10000641c: 3dc34119    	ldr	q25, [x8, #0xd00]
100006420: 6e60df1b    	fmul.2d	v27, v24, v0
100006424: 4e79d779    	fadd.2d	v25, v27, v25
100006428: 3dc1051b    	ldr	q27, [x8, #0x410]
10000642c: 4fdb91e8    	fmul.2d	v8, v15, v27[0]
100006430: 4e68d7bd    	fadd.2d	v29, v29, v8
100006434: 3dc12be0    	ldr	q0, [sp, #0x4a0]
100006438: 4fdb9808    	fmul.2d	v8, v0, v27[1]
10000643c: 4e68d7a8    	fadd.2d	v8, v29, v8
100006440: 4fdb913d    	fmul.2d	v29, v9, v27[0]
100006444: 4e7dd7fd    	fadd.2d	v29, v31, v29
100006448: 4fdb9a9f    	fmul.2d	v31, v20, v27[1]
10000644c: 4e7fd7bf    	fadd.2d	v31, v29, v31
100006450: 3dc10ff1    	ldr	q17, [sp, #0x430]
100006454: 4fd6923d    	fmul.2d	v29, v17, v22[0]
100006458: 4fd69a49    	fmul.2d	v9, v18, v22[1]
10000645c: 4e69d7bd    	fadd.2d	v29, v29, v9
100006460: 3dc127f2    	ldr	q18, [sp, #0x490]
100006464: 4fd89249    	fmul.2d	v9, v18, v24[0]
100006468: 4e69d7bd    	fadd.2d	v29, v29, v9
10000646c: 4fd89ae9    	fmul.2d	v9, v23, v24[1]
100006470: 4e69d7bd    	fadd.2d	v29, v29, v9
100006474: 3dc15fe6    	ldr	q6, [sp, #0x570]
100006478: 4fdb90c9    	fmul.2d	v9, v6, v27[0]
10000647c: 4e69d7bd    	fadd.2d	v29, v29, v9
100006480: 4fdb9949    	fmul.2d	v9, v10, v27[1]
100006484: 4e69d7a9    	fadd.2d	v9, v29, v9
100006488: 3dc3451d    	ldr	q29, [x8, #0xd10]
10000648c: 6e67df6e    	fmul.2d	v14, v27, v7
100006490: 4e7dd5ce    	fadd.2d	v14, v14, v29
100006494: 3dc1091d    	ldr	q29, [x8, #0x420]
100006498: 3cd003b4    	ldur	q20, [x29, #-0x100]
10000649c: 4fdd928f    	fmul.2d	v15, v20, v29[0]
1000064a0: 4e6fd508    	fadd.2d	v8, v8, v15
1000064a4: 3dc117f7    	ldr	q23, [sp, #0x450]
1000064a8: 4fdd9aef    	fmul.2d	v15, v23, v29[1]
1000064ac: 4e6fd508    	fadd.2d	v8, v8, v15
1000064b0: 4fdd920f    	fmul.2d	v15, v16, v29[0]
1000064b4: 4e6fd7ff    	fadd.2d	v31, v31, v15
1000064b8: 3dc1b7f0    	ldr	q16, [sp, #0x6d0]
1000064bc: 4fdd9a0f    	fmul.2d	v15, v16, v29[1]
1000064c0: 4e6fd7ef    	fadd.2d	v15, v31, v15
1000064c4: 3dc123e7    	ldr	q7, [sp, #0x480]
1000064c8: 4fdd90ff    	fmul.2d	v31, v7, v29[0]
1000064cc: 4e7fd53f    	fadd.2d	v31, v9, v31
1000064d0: 3dc16bea    	ldr	q10, [sp, #0x5a0]
1000064d4: 4fdd9949    	fmul.2d	v9, v10, v29[1]
1000064d8: 4e69d7e9    	fadd.2d	v9, v31, v9
1000064dc: 3dc133e6    	ldr	q6, [sp, #0x4c0]
1000064e0: 4fd690df    	fmul.2d	v31, v6, v22[0]
1000064e4: 4fd699be    	fmul.2d	v30, v13, v22[1]
1000064e8: 4e7ed7fe    	fadd.2d	v30, v31, v30
1000064ec: 4fd8917f    	fmul.2d	v31, v11, v24[0]
1000064f0: 4e7fd7de    	fadd.2d	v30, v30, v31
1000064f4: 4fd8999f    	fmul.2d	v31, v12, v24[1]
1000064f8: 4e7fd7de    	fadd.2d	v30, v30, v31
1000064fc: 3dc18fe6    	ldr	q6, [sp, #0x630]
100006500: 4fdb90df    	fmul.2d	v31, v6, v27[0]
100006504: 4e7fd7de    	fadd.2d	v30, v30, v31
100006508: 4fdb985f    	fmul.2d	v31, v2, v27[1]
10000650c: 4e7fd7de    	fadd.2d	v30, v30, v31
100006510: 3cd903ad    	ldur	q13, [x29, #-0x70]
100006514: 4fdd91bf    	fmul.2d	v31, v13, v29[0]
100006518: 4e7fd7de    	fadd.2d	v30, v30, v31
10000651c: 3dc113ec    	ldr	q12, [sp, #0x440]
100006520: 4fdd999f    	fmul.2d	v31, v12, v29[1]
100006524: 4e7fd7de    	fadd.2d	v30, v30, v31
100006528: 3dc3491f    	ldr	q31, [x8, #0xd20]
10000652c: 3cd203a2    	ldur	q2, [x29, #-0xe0]
100006530: 6e62dfab    	fmul.2d	v11, v29, v2
100006534: 4e7fd56b    	fadd.2d	v11, v11, v31
100006538: 3dc10d1f    	ldr	q31, [x8, #0x430]
10000653c: 3dc19fe2    	ldr	q2, [sp, #0x670]
100006540: 4fdf9046    	fmul.2d	v6, v2, v31[0]
100006544: 4e66d506    	fadd.2d	v6, v8, v6
100006548: 3cd703a2    	ldur	q2, [x29, #-0x90]
10000654c: 4fdf9848    	fmul.2d	v8, v2, v31[1]
100006550: 4e68d4c6    	fadd.2d	v6, v6, v8
100006554: 4e75d4c2    	fadd.2d	v2, v6, v21
100006558: 3d805be2    	str	q2, [sp, #0x160]
10000655c: 3dc17fe8    	ldr	q8, [sp, #0x5f0]
100006560: 4fdf9106    	fmul.2d	v6, v8, v31[0]
100006564: 4e66d5e6    	fadd.2d	v6, v15, v6
100006568: 3cd503a2    	ldur	q2, [x29, #-0xb0]
10000656c: 4fdf9855    	fmul.2d	v21, v2, v31[1]
100006570: 4e75d4c6    	fadd.2d	v6, v6, v21
100006574: 4e79d4c2    	fadd.2d	v2, v6, v25
100006578: 3d8053e2    	str	q2, [sp, #0x140]
10000657c: 3dc187e2    	ldr	q2, [sp, #0x610]
100006580: 4fdf9046    	fmul.2d	v6, v2, v31[0]
100006584: 4e66d526    	fadd.2d	v6, v9, v6
100006588: 3dc1dbf5    	ldr	q21, [sp, #0x760]
10000658c: 4fdf9ab5    	fmul.2d	v21, v21, v31[1]
100006590: 4e75d4c6    	fadd.2d	v6, v6, v21
100006594: 4e6ed4c6    	fadd.2d	v6, v6, v14
100006598: 3d8007e6    	str	q6, [sp, #0x10]
10000659c: 3dc183e6    	ldr	q6, [sp, #0x600]
1000065a0: 4fdf90c6    	fmul.2d	v6, v6, v31[0]
1000065a4: 4e66d7c6    	fadd.2d	v6, v30, v6
1000065a8: 3cd103b5    	ldur	q21, [x29, #-0xf0]
1000065ac: 4fdf9ab5    	fmul.2d	v21, v21, v31[1]
1000065b0: 4e75d4c6    	fadd.2d	v6, v6, v21
1000065b4: 4e6bd4c6    	fadd.2d	v6, v6, v11
1000065b8: 3d8003e6    	str	q6, [sp]
1000065bc: 4fd690a6    	fmul.2d	v6, v5, v22[0]
1000065c0: 3dc197e5    	ldr	q5, [sp, #0x650]
1000065c4: 4fd698b5    	fmul.2d	v21, v5, v22[1]
1000065c8: 4e75d4c6    	fadd.2d	v6, v6, v21
1000065cc: 3dc167f9    	ldr	q25, [sp, #0x590]
1000065d0: 4fd89335    	fmul.2d	v21, v25, v24[0]
1000065d4: 4e75d4c6    	fadd.2d	v6, v6, v21
1000065d8: 3dc1cbe5    	ldr	q5, [sp, #0x720]
1000065dc: 4fd898b5    	fmul.2d	v21, v5, v24[1]
1000065e0: 4e75d4c6    	fadd.2d	v6, v6, v21
1000065e4: 3dc1cfe5    	ldr	q5, [sp, #0x730]
1000065e8: 4fdb90b5    	fmul.2d	v21, v5, v27[0]
1000065ec: 4e75d4c6    	fadd.2d	v6, v6, v21
1000065f0: 3dc1abee    	ldr	q14, [sp, #0x6a0]
1000065f4: 4fdb99d5    	fmul.2d	v21, v14, v27[1]
1000065f8: 4e75d4c6    	fadd.2d	v6, v6, v21
1000065fc: 4fdd9095    	fmul.2d	v21, v4, v29[0]
100006600: 4e75d4c6    	fadd.2d	v6, v6, v21
100006604: 3cd303a4    	ldur	q4, [x29, #-0xd0]
100006608: 4fdd9895    	fmul.2d	v21, v4, v29[1]
10000660c: 4e75d4c6    	fadd.2d	v6, v6, v21
100006610: 3cda03a5    	ldur	q5, [x29, #-0x60]
100006614: 4fdf90b5    	fmul.2d	v21, v5, v31[0]
100006618: 4e75d4c6    	fadd.2d	v6, v6, v21
10000661c: 3dc1dfe5    	ldr	q5, [sp, #0x770]
100006620: 4fdf98b5    	fmul.2d	v21, v5, v31[1]
100006624: 4e75d4c6    	fadd.2d	v6, v6, v21
100006628: 3dc34d15    	ldr	q21, [x8, #0xd30]
10000662c: 3dc19be5    	ldr	q5, [sp, #0x660]
100006630: 6e65dffe    	fmul.2d	v30, v31, v5
100006634: 4e75d7d5    	fadd.2d	v21, v30, v21
100006638: 4e75d4c5    	fadd.2d	v5, v6, v21
10000663c: 3d80d3e5    	str	q5, [sp, #0x340]
100006640: 3dc17be5    	ldr	q5, [sp, #0x5e0]
100006644: 4fd690a6    	fmul.2d	v6, v5, v22[0]
100006648: 3dc14be5    	ldr	q5, [sp, #0x520]
10000664c: 4fd698b6    	fmul.2d	v22, v5, v22[1]
100006650: 4e76d4c6    	fadd.2d	v6, v6, v22
100006654: 4fd89276    	fmul.2d	v22, v19, v24[0]
100006658: 4e76d4c6    	fadd.2d	v6, v6, v22
10000665c: 3dc1d3f5    	ldr	q21, [sp, #0x740]
100006660: 4fd89ab6    	fmul.2d	v22, v21, v24[1]
100006664: 4e76d4c6    	fadd.2d	v6, v6, v22
100006668: 4fdb9036    	fmul.2d	v22, v1, v27[0]
10000666c: 4e76d4c6    	fadd.2d	v6, v6, v22
100006670: 3dc11fe1    	ldr	q1, [sp, #0x470]
100006674: 4fdb9836    	fmul.2d	v22, v1, v27[1]
100006678: 4e76d4c6    	fadd.2d	v6, v6, v22
10000667c: 3dc1a7ef    	ldr	q15, [sp, #0x690]
100006680: 4fdd91f6    	fmul.2d	v22, v15, v29[0]
100006684: 4e76d4c6    	fadd.2d	v6, v6, v22
100006688: 3dc16fe5    	ldr	q5, [sp, #0x5b0]
10000668c: 4fdd98b6    	fmul.2d	v22, v5, v29[1]
100006690: 4e76d4c6    	fadd.2d	v6, v6, v22
100006694: 3cd403a5    	ldur	q5, [x29, #-0xc0]
100006698: 4fdf90b6    	fmul.2d	v22, v5, v31[0]
10000669c: 4e76d4c6    	fadd.2d	v6, v6, v22
1000066a0: 3cd803a5    	ldur	q5, [x29, #-0x80]
1000066a4: 4fdf98b6    	fmul.2d	v22, v5, v31[1]
1000066a8: 4e76d4c6    	fadd.2d	v6, v6, v22
1000066ac: 3dc11116    	ldr	q22, [x8, #0x440]
1000066b0: 3dc1bbff    	ldr	q31, [sp, #0x6e0]
1000066b4: 6e7fded6    	fmul.2d	v22, v22, v31
1000066b8: 3dc35118    	ldr	q24, [x8, #0xd40]
1000066bc: 4e76d716    	fadd.2d	v22, v24, v22
1000066c0: 4e76d4cb    	fadd.2d	v11, v6, v22
1000066c4: 3dc11518    	ldr	q24, [x8, #0x450]
1000066c8: 3dc14fe5    	ldr	q5, [sp, #0x530]
1000066cc: 6e78dca6    	fmul.2d	v6, v5, v24
1000066d0: 3cd603a5    	ldur	q5, [x29, #-0xa0]
1000066d4: 6e78dcb3    	fmul.2d	v19, v5, v24
1000066d8: 6e0640c6    	ext.16b	v6, v6, v6, #0x8
1000066dc: 4e73d4c6    	fadd.2d	v6, v6, v19
1000066e0: 3dc15be5    	ldr	q5, [sp, #0x560]
1000066e4: 6e65df13    	fmul.2d	v19, v24, v5
1000066e8: 3dc35516    	ldr	q22, [x8, #0xd50]
1000066ec: 4e76d673    	fadd.2d	v19, v19, v22
1000066f0: 3dc1191b    	ldr	q27, [x8, #0x460]
1000066f4: 4fdb9356    	fmul.2d	v22, v26, v27[0]
1000066f8: 4e76d4c6    	fadd.2d	v6, v6, v22
1000066fc: 3dc1bfe5    	ldr	q5, [sp, #0x6f0]
100006700: 4fdb98b6    	fmul.2d	v22, v5, v27[1]
100006704: 4e76d4c6    	fadd.2d	v6, v6, v22
100006708: 4fd89076    	fmul.2d	v22, v3, v24[0]
10000670c: 3dc1c3e3    	ldr	q3, [sp, #0x700]
100006710: 4fd8987d    	fmul.2d	v29, v3, v24[1]
100006714: 4e7dd6d6    	fadd.2d	v22, v22, v29
100006718: 4fdb9385    	fmul.2d	v5, v28, v27[0]
10000671c: 4e65d6c5    	fadd.2d	v5, v22, v5
100006720: 3dc11be3    	ldr	q3, [sp, #0x460]
100006724: 4fdb9876    	fmul.2d	v22, v3, v27[1]
100006728: 4e76d4b6    	fadd.2d	v22, v5, v22
10000672c: 3dc177e3    	ldr	q3, [sp, #0x5d0]
100006730: 6e63df65    	fmul.2d	v5, v27, v3
100006734: 3dc3591d    	ldr	q29, [x8, #0xd60]
100006738: 4e7dd4a5    	fadd.2d	v5, v5, v29
10000673c: 3dc11d09    	ldr	q9, [x8, #0x470]
100006740: 3dc163e3    	ldr	q3, [sp, #0x580]
100006744: 4fc9907d    	fmul.2d	v29, v3, v9[0]
100006748: 4e7dd4c6    	fadd.2d	v6, v6, v29
10000674c: 4fc9981d    	fmul.2d	v29, v0, v9[1]
100006750: 4e7dd4c6    	fadd.2d	v6, v6, v29
100006754: 3dc107e0    	ldr	q0, [sp, #0x410]
100006758: 4fc9901d    	fmul.2d	v29, v0, v9[0]
10000675c: 4e7dd6d6    	fadd.2d	v22, v22, v29
100006760: 3dc147e0    	ldr	q0, [sp, #0x510]
100006764: 4fc9981d    	fmul.2d	v29, v0, v9[1]
100006768: 4e7dd6d6    	fadd.2d	v22, v22, v29
10000676c: 4fd8923d    	fmul.2d	v29, v17, v24[0]
100006770: 3dc12fe0    	ldr	q0, [sp, #0x4b0]
100006774: 4fd8981e    	fmul.2d	v30, v0, v24[1]
100006778: 4e7ed7bd    	fadd.2d	v29, v29, v30
10000677c: 4fdb925a    	fmul.2d	v26, v18, v27[0]
100006780: 4e7ad7ba    	fadd.2d	v26, v29, v26
100006784: 3dc193e0    	ldr	q0, [sp, #0x640]
100006788: 4fdb981d    	fmul.2d	v29, v0, v27[1]
10000678c: 4e7dd75a    	fadd.2d	v26, v26, v29
100006790: 3dc15fe0    	ldr	q0, [sp, #0x570]
100006794: 4fc99003    	fmul.2d	v3, v0, v9[0]
100006798: 4e63d743    	fadd.2d	v3, v26, v3
10000679c: 3dc143e0    	ldr	q0, [sp, #0x500]
1000067a0: 4fc9981a    	fmul.2d	v26, v0, v9[1]
1000067a4: 4e7ad463    	fadd.2d	v3, v3, v26
1000067a8: 3dc173e0    	ldr	q0, [sp, #0x5c0]
1000067ac: 6e60dd3a    	fmul.2d	v26, v9, v0
1000067b0: 3dc35d1d    	ldr	q29, [x8, #0xd70]
1000067b4: 4e7dd75e    	fadd.2d	v30, v26, v29
1000067b8: 3dc1211a    	ldr	q26, [x8, #0x480]
1000067bc: 4fda929d    	fmul.2d	v29, v20, v26[0]
1000067c0: 4e7dd4c6    	fadd.2d	v6, v6, v29
1000067c4: 4fda9afd    	fmul.2d	v29, v23, v26[1]
1000067c8: 4eab1d77    	mov.16b	v23, v11
1000067cc: 4e7dd4c6    	fadd.2d	v6, v6, v29
1000067d0: 3dc1c7e0    	ldr	q0, [sp, #0x710]
1000067d4: 4fda901d    	fmul.2d	v29, v0, v26[0]
1000067d8: 4e7dd6d6    	fadd.2d	v22, v22, v29
1000067dc: 4fda9a1d    	fmul.2d	v29, v16, v26[1]
1000067e0: 4e7dd6d6    	fadd.2d	v22, v22, v29
1000067e4: 4fda90fd    	fmul.2d	v29, v7, v26[0]
1000067e8: 3dc00be7    	ldr	q7, [sp, #0x20]
1000067ec: 4e7dd463    	fadd.2d	v3, v3, v29
1000067f0: 4fda995d    	fmul.2d	v29, v10, v26[1]
1000067f4: 4e7dd463    	fadd.2d	v3, v3, v29
1000067f8: 3dc133e0    	ldr	q0, [sp, #0x4c0]
1000067fc: 4fd8901d    	fmul.2d	v29, v0, v24[0]
100006800: 3dc153e0    	ldr	q0, [sp, #0x540]
100006804: 4fd8980b    	fmul.2d	v11, v0, v24[1]
100006808: 4e6bd7bd    	fadd.2d	v29, v29, v11
10000680c: 3dc157e0    	ldr	q0, [sp, #0x550]
100006810: 4fdb9000    	fmul.2d	v0, v0, v27[0]
100006814: 4e60d7a0    	fadd.2d	v0, v29, v0
100006818: 3dc1a3f0    	ldr	q16, [sp, #0x680]
10000681c: 4fdb9a1d    	fmul.2d	v29, v16, v27[1]
100006820: 4e7dd400    	fadd.2d	v0, v0, v29
100006824: 3dc18ff0    	ldr	q16, [sp, #0x630]
100006828: 4fc9921d    	fmul.2d	v29, v16, v9[0]
10000682c: 4e7dd400    	fadd.2d	v0, v0, v29
100006830: 3dc1b3f0    	ldr	q16, [sp, #0x6c0]
100006834: 4fc99a1d    	fmul.2d	v29, v16, v9[1]
100006838: 4e7dd400    	fadd.2d	v0, v0, v29
10000683c: 4fda91bd    	fmul.2d	v29, v13, v26[0]
100006840: 4e7dd400    	fadd.2d	v0, v0, v29
100006844: 4fda999d    	fmul.2d	v29, v12, v26[1]
100006848: 4e7dd400    	fadd.2d	v0, v0, v29
10000684c: 3cd203b0    	ldur	q16, [x29, #-0xe0]
100006850: 6e70df5d    	fmul.2d	v29, v26, v16
100006854: 3dc3610b    	ldr	q11, [x8, #0xd80]
100006858: 4e6bd7ab    	fadd.2d	v11, v29, v11
10000685c: 3dc1251d    	ldr	q29, [x8, #0x490]
100006860: 3dc19ff0    	ldr	q16, [sp, #0x670]
100006864: 4fdd920d    	fmul.2d	v13, v16, v29[0]
100006868: 4e6dd4c6    	fadd.2d	v6, v6, v13
10000686c: 3cd703b0    	ldur	q16, [x29, #-0x90]
100006870: 4fdd9a0d    	fmul.2d	v13, v16, v29[1]
100006874: 4e6dd4c6    	fadd.2d	v6, v6, v13
100006878: 3dc043ed    	ldr	q13, [sp, #0x100]
10000687c: 4e73d4d4    	fadd.2d	v20, v6, v19
100006880: 4fdd9106    	fmul.2d	v6, v8, v29[0]
100006884: 4e66d6c6    	fadd.2d	v6, v22, v6
100006888: 3cd503b0    	ldur	q16, [x29, #-0xb0]
10000688c: 4fdd9a16    	fmul.2d	v22, v16, v29[1]
100006890: 4e76d4c6    	fadd.2d	v6, v6, v22
100006894: 4e65d4c5    	fadd.2d	v5, v6, v5
100006898: 4fdd9046    	fmul.2d	v6, v2, v29[0]
10000689c: 4e66d463    	fadd.2d	v3, v3, v6
1000068a0: 3dc1dbe2    	ldr	q2, [sp, #0x760]
1000068a4: 4fdd9846    	fmul.2d	v6, v2, v29[1]
1000068a8: 4e66d463    	fadd.2d	v3, v3, v6
1000068ac: 4e7ed463    	fadd.2d	v3, v3, v30
1000068b0: 3dc183e2    	ldr	q2, [sp, #0x600]
1000068b4: 4fdd9046    	fmul.2d	v6, v2, v29[0]
1000068b8: 4e66d400    	fadd.2d	v0, v0, v6
1000068bc: 3cd103a2    	ldur	q2, [x29, #-0xf0]
1000068c0: 4fdd9846    	fmul.2d	v6, v2, v29[1]
1000068c4: 3dc02bf2    	ldr	q18, [sp, #0xa0]
1000068c8: 4e66d400    	fadd.2d	v0, v0, v6
1000068cc: 4e6bd416    	fadd.2d	v22, v0, v11
1000068d0: ad492ffe    	ldp	q30, q11, [sp, #0x120]
1000068d4: 3dc13fe0    	ldr	q0, [sp, #0x4f0]
1000068d8: 4fd89000    	fmul.2d	v0, v0, v24[0]
1000068dc: 3dc013fc    	ldr	q28, [sp, #0x40]
1000068e0: 3dc197e2    	ldr	q2, [sp, #0x650]
1000068e4: 4fd89846    	fmul.2d	v6, v2, v24[1]
1000068e8: 4e66d400    	fadd.2d	v0, v0, v6
1000068ec: 4fdb9326    	fmul.2d	v6, v25, v27[0]
1000068f0: 4e66d400    	fadd.2d	v0, v0, v6
1000068f4: 3dc1cbe2    	ldr	q2, [sp, #0x720]
1000068f8: 4fdb9846    	fmul.2d	v6, v2, v27[1]
1000068fc: 4e66d400    	fadd.2d	v0, v0, v6
100006900: 3dc1cfe2    	ldr	q2, [sp, #0x730]
100006904: 4fc99046    	fmul.2d	v6, v2, v9[0]
100006908: 4e66d400    	fadd.2d	v0, v0, v6
10000690c: 4fc999c6    	fmul.2d	v6, v14, v9[1]
100006910: 4e66d400    	fadd.2d	v0, v0, v6
100006914: 3dc18be2    	ldr	q2, [sp, #0x620]
100006918: 4fda9046    	fmul.2d	v6, v2, v26[0]
10000691c: 4e66d400    	fadd.2d	v0, v0, v6
100006920: 4fda9886    	fmul.2d	v6, v4, v26[1]
100006924: 4e66d400    	fadd.2d	v0, v0, v6
100006928: 3cda03a2    	ldur	q2, [x29, #-0x60]
10000692c: 4fdd9046    	fmul.2d	v6, v2, v29[0]
100006930: 4e66d400    	fadd.2d	v0, v0, v6
100006934: 3dc1dfe2    	ldr	q2, [sp, #0x770]
100006938: 4fdd9846    	fmul.2d	v6, v2, v29[1]
10000693c: 4e66d400    	fadd.2d	v0, v0, v6
100006940: 3dc19be2    	ldr	q2, [sp, #0x660]
100006944: 6e62dfa6    	fmul.2d	v6, v29, v2
100006948: 3dc36510    	ldr	q16, [x8, #0xd90]
10000694c: 4e70d4c6    	fadd.2d	v6, v6, v16
100006950: 4e66d400    	fadd.2d	v0, v0, v6
100006954: 3dc17be2    	ldr	q2, [sp, #0x5e0]
100006958: 4fd89046    	fmul.2d	v6, v2, v24[0]
10000695c: 3dc14be2    	ldr	q2, [sp, #0x520]
100006960: 4fd89850    	fmul.2d	v16, v2, v24[1]
100006964: ad434ff8    	ldp	q24, q19, [sp, #0x60]
100006968: 4e70d4c6    	fadd.2d	v6, v6, v16
10000696c: 3dc1afe2    	ldr	q2, [sp, #0x6b0]
100006970: 4fdb9050    	fmul.2d	v16, v2, v27[0]
100006974: 4e70d4c6    	fadd.2d	v6, v6, v16
100006978: 4fdb9ab0    	fmul.2d	v16, v21, v27[1]
10000697c: 3dc00ff5    	ldr	q21, [sp, #0x30]
100006980: 4e70d4c6    	fadd.2d	v6, v6, v16
100006984: 3dc1d7e2    	ldr	q2, [sp, #0x750]
100006988: 4fc99050    	fmul.2d	v16, v2, v9[0]
10000698c: 4e70d4c6    	fadd.2d	v6, v6, v16
100006990: ad4423f0    	ldp	q16, q8, [sp, #0x80]
100006994: 4fc99824    	fmul.2d	v4, v1, v9[1]
100006998: 3dc047e9    	ldr	q9, [sp, #0x110]
10000699c: 4e64d4c4    	fadd.2d	v4, v6, v4
1000069a0: 4fda91e6    	fmul.2d	v6, v15, v26[0]
1000069a4: ad4067ee    	ldp	q14, q25, [sp]
1000069a8: 4e66d484    	fadd.2d	v4, v4, v6
1000069ac: 3dc16fe1    	ldr	q1, [sp, #0x5b0]
1000069b0: 4fda9826    	fmul.2d	v6, v1, v26[1]
1000069b4: ad476bfb    	ldp	q27, q26, [sp, #0xe0]
1000069b8: 4e66d484    	fadd.2d	v4, v4, v6
1000069bc: 3cd403a1    	ldur	q1, [x29, #-0xc0]
1000069c0: 4fdd9021    	fmul.2d	v1, v1, v29[0]
1000069c4: 4e61d481    	fadd.2d	v1, v4, v1
1000069c8: 3cd803a2    	ldur	q2, [x29, #-0x80]
1000069cc: 4fdd9842    	fmul.2d	v2, v2, v29[1]
1000069d0: 3dc017ea    	ldr	q10, [sp, #0x50]
1000069d4: 3dc02ff1    	ldr	q17, [sp, #0xb0]
1000069d8: ad461bfd    	ldp	q29, q6, [sp, #0xc0]
1000069dc: 4e62d421    	fadd.2d	v1, v1, v2
1000069e0: 3dc12902    	ldr	q2, [x8, #0x4a0]
1000069e4: 6e7fdc42    	fmul.2d	v2, v2, v31
1000069e8: 3dc36904    	ldr	q4, [x8, #0xda0]
1000069ec: 4e62d482    	fadd.2d	v2, v4, v2
1000069f0: 4e62d421    	fadd.2d	v1, v1, v2
1000069f4: 14000163    	b	0x100006f80 <_bench_primitives.smulAddSemul3_12+0x2dac>
1000069f8: d00000a9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000069fc: 91192129    	add	x9, x9, #0x648
100006a00: d100e128    	sub	x8, x9, #0x38
100006a04: 3dc26507    	ldr	q7, [x8, #0x990]
100006a08: 3cc58131    	ldur	q17, [x9, #0x58]
100006a0c: 9124012a    	add	x10, x9, #0x900
100006a10: 4d40853e    	ld1.d	{ v30 }[1], [x9]
100006a14: b000004b    	adrp	x11, 0x10000f000 <dyld_stub_binder+0x10000f000>
100006a18: 3dc35d62    	ldr	q2, [x11, #0xd70]
100006a1c: 4d408552    	ld1.d	{ v18 }[1], [x10]
100006a20: 6e62dfc1    	fmul.2d	v1, v30, v2
100006a24: 4e61d641    	fadd.2d	v1, v18, v1
100006a28: 3d80fbe1    	str	q1, [sp, #0x3e0]
100006a2c: 6e180731    	mov.d	v17[1], v25[0]
100006a30: 6e180667    	mov.d	v7[1], v19[0]
100006a34: 6e62de21    	fmul.2d	v1, v17, v2
100006a38: 4e61d4e1    	fadd.2d	v1, v7, v1
100006a3c: 3d80cbe1    	str	q1, [sp, #0x320]
100006a40: 3dc27d01    	ldr	q1, [x8, #0x9f0]
100006a44: 3ccb8127    	ldur	q7, [x9, #0xb8]
100006a48: 6e62dce7    	fmul.2d	v7, v7, v2
100006a4c: 4e67d421    	fadd.2d	v1, v1, v7
100006a50: 3d80b7e1    	str	q1, [sp, #0x2d0]
100006a54: 3dc29501    	ldr	q1, [x8, #0xa50]
100006a58: ad4a1d11    	ldp	q17, q7, [x8, #0x140]
100006a5c: 6e62dce7    	fmul.2d	v7, v7, v2
100006a60: 4e67d421    	fadd.2d	v1, v1, v7
100006a64: 3d80e3e1    	str	q1, [sp, #0x380]
100006a68: 3dc2ad07    	ldr	q7, [x8, #0xab0]
100006a6c: ad4d4901    	ldp	q1, q18, [x8, #0x1a0]
100006a70: 6e62de52    	fmul.2d	v18, v18, v2
100006a74: 4e72d4e7    	fadd.2d	v7, v7, v18
100006a78: 3d808be7    	str	q7, [sp, #0x220]
100006a7c: 3dc2c512    	ldr	q18, [x8, #0xb10]
100006a80: ad504d07    	ldp	q7, q19, [x8, #0x200]
100006a84: 6e62de73    	fmul.2d	v19, v19, v2
100006a88: 4e73d652    	fadd.2d	v18, v18, v19
100006a8c: 3d80b3f2    	str	q18, [sp, #0x2c0]
100006a90: 3dc2dd13    	ldr	q19, [x8, #0xb70]
100006a94: ad535112    	ldp	q18, q20, [x8, #0x260]
100006a98: 6e62de94    	fmul.2d	v20, v20, v2
100006a9c: 4e74d673    	fadd.2d	v19, v19, v20
100006aa0: 3d809bf3    	str	q19, [sp, #0x260]
100006aa4: 3dc2f513    	ldr	q19, [x8, #0xbd0]
100006aa8: ad56d514    	ldp	q20, q21, [x8, #0x2d0]
100006aac: 6e62de94    	fmul.2d	v20, v20, v2
100006ab0: 4e74d673    	fadd.2d	v19, v19, v20
100006ab4: 3d8083f3    	str	q19, [sp, #0x200]
100006ab8: ad59d913    	ldp	q19, q22, [x8, #0x330]
100006abc: 6e62de73    	fmul.2d	v19, v19, v2
100006ac0: 3dc30d14    	ldr	q20, [x8, #0xc30]
100006ac4: 4e73d68a    	fadd.2d	v10, v20, v19
100006ac8: ad5c4d14    	ldp	q20, q19, [x8, #0x380]
100006acc: 6e62de73    	fmul.2d	v19, v19, v2
100006ad0: 3dc32517    	ldr	q23, [x8, #0xc90]
100006ad4: 4e73d6f3    	fadd.2d	v19, v23, v19
100006ad8: 3d806bf3    	str	q19, [sp, #0x1a0]
100006adc: ad5f4d17    	ldp	q23, q19, [x8, #0x3e0]
100006ae0: 6e62de73    	fmul.2d	v19, v19, v2
100006ae4: 3dc33d18    	ldr	q24, [x8, #0xcf0]
100006ae8: 4e73d713    	fadd.2d	v19, v24, v19
100006aec: 3d805bf3    	str	q19, [sp, #0x160]
100006af0: 3dc11513    	ldr	q19, [x8, #0x450]
100006af4: 6e62de62    	fmul.2d	v2, v19, v2
100006af8: 3dc35513    	ldr	q19, [x8, #0xd50]
100006afc: 4e62d66c    	fadd.2d	v12, v19, v2
100006b00: b000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
100006b04: 3cc08122    	ldur	q2, [x9, #0x8]
100006b08: 3dc36158    	ldr	q24, [x10, #0xd80]
100006b0c: 6e78dc42    	fmul.2d	v2, v2, v24
100006b10: 3dc25119    	ldr	q25, [x8, #0x940]
100006b14: 4e62d72b    	fadd.2d	v11, v25, v2
100006b18: 3cc68122    	ldur	q2, [x9, #0x68]
100006b1c: 6e78dc42    	fmul.2d	v2, v2, v24
100006b20: 3dc26919    	ldr	q25, [x8, #0x9a0]
100006b24: 4e62d722    	fadd.2d	v2, v25, v2
100006b28: 3d80ffe2    	str	q2, [sp, #0x3f0]
100006b2c: 9127412a    	add	x10, x9, #0x9d0
100006b30: 9103412b    	add	x11, x9, #0xd0
100006b34: 4d40857d    	ld1.d	{ v29 }[1], [x11]
100006b38: 4d408545    	ld1.d	{ v5 }[1], [x10]
100006b3c: 6e78dfa2    	fmul.2d	v2, v29, v24
100006b40: 4e62d4a2    	fadd.2d	v2, v5, v2
100006b44: 3d80ebe2    	str	q2, [sp, #0x3a0]
100006b48: ad4b6502    	ldp	q2, q25, [x8, #0x160]
100006b4c: 6e180742    	mov.d	v2[1], v26[0]
100006b50: 3dc29905    	ldr	q5, [x8, #0xa60]
100006b54: 6e180605    	mov.d	v5[1], v16[0]
100006b58: 6e78dc42    	fmul.2d	v2, v2, v24
100006b5c: 4e62d4a2    	fadd.2d	v2, v5, v2
100006b60: 3d80d7e2    	str	q2, [sp, #0x350]
100006b64: 3dc07102    	ldr	q2, [x8, #0x1c0]
100006b68: 6e78dc42    	fmul.2d	v2, v2, v24
100006b6c: 3dc2b105    	ldr	q5, [x8, #0xac0]
100006b70: 4e62d4a2    	fadd.2d	v2, v5, v2
100006b74: 3d80bfe2    	str	q2, [sp, #0x2f0]
100006b78: ad514102    	ldp	q2, q16, [x8, #0x220]
100006b7c: 6e78dc42    	fmul.2d	v2, v2, v24
100006b80: 3dc2c905    	ldr	q5, [x8, #0xb20]
100006b84: 4e62d4a2    	fadd.2d	v2, v5, v2
100006b88: 3d80a7e2    	str	q2, [sp, #0x290]
100006b8c: ad546902    	ldp	q2, q26, [x8, #0x280]
100006b90: 6e78dc42    	fmul.2d	v2, v2, v24
100006b94: 3dc2e105    	ldr	q5, [x8, #0xb80]
100006b98: 4e62d4a2    	fadd.2d	v2, v5, v2
100006b9c: 3d8093e2    	str	q2, [sp, #0x240]
100006ba0: 6e78dea2    	fmul.2d	v2, v21, v24
100006ba4: 3dc2f905    	ldr	q5, [x8, #0xbe0]
100006ba8: 4e62d4a2    	fadd.2d	v2, v5, v2
100006bac: 3d807fe2    	str	q2, [sp, #0x1f0]
100006bb0: 6e78dec2    	fmul.2d	v2, v22, v24
100006bb4: 3dc31105    	ldr	q5, [x8, #0xc40]
100006bb8: 4e62d4a2    	fadd.2d	v2, v5, v2
100006bbc: 3d8073e2    	str	q2, [sp, #0x1c0]
100006bc0: ad5d5502    	ldp	q2, q21, [x8, #0x3a0]
100006bc4: 6e78dc42    	fmul.2d	v2, v2, v24
100006bc8: 3dc32905    	ldr	q5, [x8, #0xca0]
100006bcc: 4e62d4a2    	fadd.2d	v2, v5, v2
100006bd0: 3d8063e2    	str	q2, [sp, #0x180]
100006bd4: 3dc10102    	ldr	q2, [x8, #0x400]
100006bd8: 6e78dc42    	fmul.2d	v2, v2, v24
100006bdc: 3dc34105    	ldr	q5, [x8, #0xd00]
100006be0: 4e62d4a2    	fadd.2d	v2, v5, v2
100006be4: 3d8053e2    	str	q2, [sp, #0x140]
100006be8: 3dc11902    	ldr	q2, [x8, #0x460]
100006bec: 6e78dc42    	fmul.2d	v2, v2, v24
100006bf0: 3dc35905    	ldr	q5, [x8, #0xd60]
100006bf4: 4e62d4a5    	fadd.2d	v5, v5, v2
100006bf8: b000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
100006bfc: 3cc18122    	ldur	q2, [x9, #0x18]
100006c00: 3dc36556    	ldr	q22, [x10, #0xd90]
100006c04: 6e76dc42    	fmul.2d	v2, v2, v22
100006c08: 3dc25518    	ldr	q24, [x8, #0x950]
100006c0c: 4e62d702    	fadd.2d	v2, v24, v2
100006c10: 3d8103e2    	str	q2, [sp, #0x400]
100006c14: 3cc78122    	ldur	q2, [x9, #0x78]
100006c18: 6e76dc42    	fmul.2d	v2, v2, v22
100006c1c: 3dc26d18    	ldr	q24, [x8, #0x9b0]
100006c20: 4e62d709    	fadd.2d	v9, v24, v2
100006c24: 3ccd8122    	ldur	q2, [x9, #0xd8]
100006c28: 6e76dc42    	fmul.2d	v2, v2, v22
100006c2c: 3dc28518    	ldr	q24, [x8, #0xa10]
100006c30: 4e62d702    	fadd.2d	v2, v24, v2
100006c34: 3d80e7e2    	str	q2, [sp, #0x390]
100006c38: 6e76df22    	fmul.2d	v2, v25, v22
100006c3c: 3dc29d18    	ldr	q24, [x8, #0xa70]
100006c40: 4e62d71d    	fadd.2d	v29, v24, v2
100006c44: 912a812a    	add	x10, x9, #0xaa0
100006c48: 9106812b    	add	x11, x9, #0x1a0
100006c4c: 3dc0a3e2    	ldr	q2, [sp, #0x280]
100006c50: 4d408562    	ld1.d	{ v2 }[1], [x11]
100006c54: 6e76dc42    	fmul.2d	v2, v2, v22
100006c58: 4d408543    	ld1.d	{ v3 }[1], [x10]
100006c5c: 4e62d462    	fadd.2d	v2, v3, v2
100006c60: 3d80bbe2    	str	q2, [sp, #0x2e0]
100006c64: 6e180770    	mov.d	v16[1], v27[0]
100006c68: 3dc2cd02    	ldr	q2, [x8, #0xb30]
100006c6c: 6e1804c2    	mov.d	v2[1], v6[0]
100006c70: 6e76de03    	fmul.2d	v3, v16, v22
100006c74: 4e63d442    	fadd.2d	v2, v2, v3
100006c78: 3d80a3e2    	str	q2, [sp, #0x280]
100006c7c: 6e76df42    	fmul.2d	v2, v26, v22
100006c80: 3dc2e503    	ldr	q3, [x8, #0xb90]
100006c84: 4e62d462    	fadd.2d	v2, v3, v2
100006c88: 3d808fe2    	str	q2, [sp, #0x230]
100006c8c: ad579902    	ldp	q2, q6, [x8, #0x2f0]
100006c90: 6e76dc42    	fmul.2d	v2, v2, v22
100006c94: 3dc2fd03    	ldr	q3, [x8, #0xbf0]
100006c98: 4e62d462    	fadd.2d	v2, v3, v2
100006c9c: 3d8077e2    	str	q2, [sp, #0x1d0]
100006ca0: ad5ac102    	ldp	q2, q16, [x8, #0x350]
100006ca4: 6e76dc42    	fmul.2d	v2, v2, v22
100006ca8: 3dc31503    	ldr	q3, [x8, #0xc50]
100006cac: 4e62d462    	fadd.2d	v2, v3, v2
100006cb0: 3d806fe2    	str	q2, [sp, #0x1b0]
100006cb4: 6e76dea2    	fmul.2d	v2, v21, v22
100006cb8: 3dc32d03    	ldr	q3, [x8, #0xcb0]
100006cbc: 4e62d462    	fadd.2d	v2, v3, v2
100006cc0: 3d805fe2    	str	q2, [sp, #0x170]
100006cc4: 3dc10502    	ldr	q2, [x8, #0x410]
100006cc8: 6e76dc42    	fmul.2d	v2, v2, v22
100006ccc: 3dc34503    	ldr	q3, [x8, #0xd10]
100006cd0: 4e62d479    	fadd.2d	v25, v3, v2
100006cd4: 3dc11d02    	ldr	q2, [x8, #0x470]
100006cd8: 6e76dc42    	fmul.2d	v2, v2, v22
100006cdc: 3dc35d03    	ldr	q3, [x8, #0xd70]
100006ce0: 4e62d463    	fadd.2d	v3, v3, v2
100006ce4: b000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
100006ce8: 3cc28122    	ldur	q2, [x9, #0x28]
100006cec: 3dc36955    	ldr	q21, [x10, #0xda0]
100006cf0: 6e75dc42    	fmul.2d	v2, v2, v21
100006cf4: 3dc25916    	ldr	q22, [x8, #0x960]
100006cf8: 4e62d6de    	fadd.2d	v30, v22, v2
100006cfc: 3cc88122    	ldur	q2, [x9, #0x88]
100006d00: 6e75dc42    	fmul.2d	v2, v2, v21
100006d04: 3dc27116    	ldr	q22, [x8, #0x9c0]
100006d08: 4e62d6c2    	fadd.2d	v2, v22, v2
100006d0c: 3d80f7e2    	str	q2, [sp, #0x3d0]
100006d10: 3cce8122    	ldur	q2, [x9, #0xe8]
100006d14: 6e75dc42    	fmul.2d	v2, v2, v21
100006d18: 3dc28916    	ldr	q22, [x8, #0xa20]
100006d1c: 4e62d6c2    	fadd.2d	v2, v22, v2
100006d20: 3d80dfe2    	str	q2, [sp, #0x370]
100006d24: ad4c6102    	ldp	q2, q24, [x8, #0x180]
100006d28: 6e75dc42    	fmul.2d	v2, v2, v21
100006d2c: 3dc2a116    	ldr	q22, [x8, #0xa80]
100006d30: 4e62d6c2    	fadd.2d	v2, v22, v2
100006d34: 3d80c7e2    	str	q2, [sp, #0x310]
100006d38: ad4f6902    	ldp	q2, q26, [x8, #0x1e0]
100006d3c: 6e75dc42    	fmul.2d	v2, v2, v21
100006d40: 3dc2b916    	ldr	q22, [x8, #0xae0]
100006d44: 4e62d6c2    	fadd.2d	v2, v22, v2
100006d48: 3d80afe2    	str	q2, [sp, #0x2b0]
100006d4c: ad526d02    	ldp	q2, q27, [x8, #0x240]
100006d50: 6e75dc42    	fmul.2d	v2, v2, v21
100006d54: 3dc2d116    	ldr	q22, [x8, #0xb40]
100006d58: 4e62d6c2    	fadd.2d	v2, v22, v2
100006d5c: 3d809fe2    	str	q2, [sp, #0x270]
100006d60: 6e1805c6    	mov.d	v6[1], v14[0]
100006d64: 912dc12a    	add	x10, x9, #0xb70
100006d68: 9109c12b    	add	x11, x9, #0x270
100006d6c: 3dc0f3e2    	ldr	q2, [sp, #0x3c0]
100006d70: 4d408562    	ld1.d	{ v2 }[1], [x11]
100006d74: 6e75dc42    	fmul.2d	v2, v2, v21
100006d78: 3cd903b6    	ldur	q22, [x29, #-0x70]
100006d7c: 4d408556    	ld1.d	{ v22 }[1], [x10]
100006d80: 4e62d6c2    	fadd.2d	v2, v22, v2
100006d84: 3d8087e2    	str	q2, [sp, #0x210]
100006d88: 3dc30102    	ldr	q2, [x8, #0xc00]
100006d8c: 6e180482    	mov.d	v2[1], v4[0]
100006d90: 6e75dcc4    	fmul.2d	v4, v6, v21
100006d94: 4e64d453    	fadd.2d	v19, v2, v4
100006d98: 6e75de02    	fmul.2d	v2, v16, v21
100006d9c: 3dc31904    	ldr	q4, [x8, #0xc60]
100006da0: 4e62d482    	fadd.2d	v2, v4, v2
100006da4: 3d8067e2    	str	q2, [sp, #0x190]
100006da8: ad5e1102    	ldp	q2, q4, [x8, #0x3c0]
100006dac: 6e75dc42    	fmul.2d	v2, v2, v21
100006db0: 3dc33106    	ldr	q6, [x8, #0xcc0]
100006db4: 4e62d4c2    	fadd.2d	v2, v6, v2
100006db8: 3d8057e2    	str	q2, [sp, #0x150]
100006dbc: 3dc10902    	ldr	q2, [x8, #0x420]
100006dc0: 6e75dc42    	fmul.2d	v2, v2, v21
100006dc4: 3dc34906    	ldr	q6, [x8, #0xd20]
100006dc8: 4e62d4ce    	fadd.2d	v14, v6, v2
100006dcc: 3dc12102    	ldr	q2, [x8, #0x480]
100006dd0: 6e75dc42    	fmul.2d	v2, v2, v21
100006dd4: 3dc36106    	ldr	q6, [x8, #0xd80]
100006dd8: 4e62d4d6    	fadd.2d	v22, v6, v2
100006ddc: b000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
100006de0: 3cc38122    	ldur	q2, [x9, #0x38]
100006de4: 3dc36d46    	ldr	q6, [x10, #0xdb0]
100006de8: 6e66dc42    	fmul.2d	v2, v2, v6
100006dec: 3dc25d10    	ldr	q16, [x8, #0x970]
100006df0: 4e62d60d    	fadd.2d	v13, v16, v2
100006df4: 3cc98122    	ldur	q2, [x9, #0x98]
100006df8: 6e66dc42    	fmul.2d	v2, v2, v6
100006dfc: 3dc27510    	ldr	q16, [x8, #0x9d0]
100006e00: 4e62d602    	fadd.2d	v2, v16, v2
100006e04: 3d80efe2    	str	q2, [sp, #0x3b0]
100006e08: 3ccf8122    	ldur	q2, [x9, #0xf8]
100006e0c: 6e66dc42    	fmul.2d	v2, v2, v6
100006e10: 3dc28d10    	ldr	q16, [x8, #0xa30]
100006e14: 4e62d602    	fadd.2d	v2, v16, v2
100006e18: 3d80dbe2    	str	q2, [sp, #0x360]
100006e1c: 6e66df02    	fmul.2d	v2, v24, v6
100006e20: 3dc2a510    	ldr	q16, [x8, #0xa90]
100006e24: 4e62d602    	fadd.2d	v2, v16, v2
100006e28: 3d80c3e2    	str	q2, [sp, #0x300]
100006e2c: 6e66df42    	fmul.2d	v2, v26, v6
100006e30: 3dc2bd10    	ldr	q16, [x8, #0xaf0]
100006e34: 4e62d602    	fadd.2d	v2, v16, v2
100006e38: 3d80abe2    	str	q2, [sp, #0x2a0]
100006e3c: 6e66df62    	fmul.2d	v2, v27, v6
100006e40: 3dc2d510    	ldr	q16, [x8, #0xb50]
100006e44: 4e62d602    	fadd.2d	v2, v16, v2
100006e48: 3d8097e2    	str	q2, [sp, #0x250]
100006e4c: ad55c102    	ldp	q2, q16, [x8, #0x2b0]
100006e50: 6e66dc42    	fmul.2d	v2, v2, v6
100006e54: 3dc2ed15    	ldr	q21, [x8, #0xbb0]
100006e58: 4e62d6a8    	fadd.2d	v8, v21, v2
100006e5c: ad58e102    	ldp	q2, q24, [x8, #0x310]
100006e60: 6e66dc42    	fmul.2d	v2, v2, v6
100006e64: 3dc30515    	ldr	q21, [x8, #0xc10]
100006e68: 4e62d6a2    	fadd.2d	v2, v21, v2
100006e6c: 3d80f3e2    	str	q2, [sp, #0x3c0]
100006e70: 9131012a    	add	x10, x9, #0xc40
100006e74: 910d012b    	add	x11, x9, #0x340
100006e78: 3dc0cfe2    	ldr	q2, [sp, #0x330]
100006e7c: 4d408562    	ld1.d	{ v2 }[1], [x11]
100006e80: 6e66dc42    	fmul.2d	v2, v2, v6
100006e84: 3cda03af    	ldur	q15, [x29, #-0x60]
100006e88: 4d40854f    	ld1.d	{ v15 }[1], [x10]
100006e8c: 4e62d5fc    	fadd.2d	v28, v15, v2
100006e90: 3dc0d3e2    	ldr	q2, [sp, #0x340]
100006e94: 6e180444    	mov.d	v4[1], v2[0]
100006e98: 3dc33502    	ldr	q2, [x8, #0xcd0]
100006e9c: 6e180402    	mov.d	v2[1], v0[0]
100006ea0: 6e66dc80    	fmul.2d	v0, v4, v6
100006ea4: 4e60d455    	fadd.2d	v21, v2, v0
100006ea8: 3dc10d00    	ldr	q0, [x8, #0x430]
100006eac: 6e66dc00    	fmul.2d	v0, v0, v6
100006eb0: 3dc34d02    	ldr	q2, [x8, #0xd30]
100006eb4: 4e60d440    	fadd.2d	v0, v2, v0
100006eb8: 3d80d3e0    	str	q0, [sp, #0x340]
100006ebc: 3dc12500    	ldr	q0, [x8, #0x490]
100006ec0: 6e66dc00    	fmul.2d	v0, v0, v6
100006ec4: 3dc36502    	ldr	q2, [x8, #0xd90]
100006ec8: 4e60d440    	fadd.2d	v0, v2, v0
100006ecc: b000004a    	adrp	x10, 0x10000f000 <dyld_stub_binder+0x10000f000>
100006ed0: 3cc48122    	ldur	q2, [x9, #0x48]
100006ed4: 3dc37144    	ldr	q4, [x10, #0xdc0]
100006ed8: 6e64dc42    	fmul.2d	v2, v2, v4
100006edc: 3dc26106    	ldr	q6, [x8, #0x980]
100006ee0: 4e62d4da    	fadd.2d	v26, v6, v2
100006ee4: 3cca8122    	ldur	q2, [x9, #0xa8]
100006ee8: 6e64dc42    	fmul.2d	v2, v2, v4
100006eec: 3dc27906    	ldr	q6, [x8, #0x9e0]
100006ef0: 4e62d4db    	fadd.2d	v27, v6, v2
100006ef4: 6e64de22    	fmul.2d	v2, v17, v4
100006ef8: 3dc29106    	ldr	q6, [x8, #0xa40]
100006efc: 4e62d4c6    	fadd.2d	v6, v6, v2
100006f00: 6e64dc21    	fmul.2d	v1, v1, v4
100006f04: 3dc2a902    	ldr	q2, [x8, #0xaa0]
100006f08: 4e61d451    	fadd.2d	v17, v2, v1
100006f0c: 6e64dce1    	fmul.2d	v1, v7, v4
100006f10: 3dc2c102    	ldr	q2, [x8, #0xb00]
100006f14: 4e61d441    	fadd.2d	v1, v2, v1
100006f18: 3d807be1    	str	q1, [sp, #0x1e0]
100006f1c: 6e64de41    	fmul.2d	v1, v18, v4
100006f20: 3dc2d902    	ldr	q2, [x8, #0xb60]
100006f24: 4e61d452    	fadd.2d	v18, v2, v1
100006f28: 6e64de01    	fmul.2d	v1, v16, v4
100006f2c: 3dc2f102    	ldr	q2, [x8, #0xbc0]
100006f30: 4e61d450    	fadd.2d	v16, v2, v1
100006f34: 6e64df01    	fmul.2d	v1, v24, v4
100006f38: 3dc30902    	ldr	q2, [x8, #0xc20]
100006f3c: 4e61d458    	fadd.2d	v24, v2, v1
100006f40: 6e64de81    	fmul.2d	v1, v20, v4
100006f44: 4eac1d94    	mov.16b	v20, v12
100006f48: 3dc32102    	ldr	q2, [x8, #0xc80]
100006f4c: 4e61d441    	fadd.2d	v1, v2, v1
100006f50: 3d80cfe1    	str	q1, [sp, #0x330]
100006f54: 6e64dee1    	fmul.2d	v1, v23, v4
100006f58: 3dc33902    	ldr	q2, [x8, #0xce0]
100006f5c: 4e61d447    	fadd.2d	v7, v2, v1
100006f60: 3dc11101    	ldr	q1, [x8, #0x440]
100006f64: 6e64dc21    	fmul.2d	v1, v1, v4
100006f68: 3dc35102    	ldr	q2, [x8, #0xd40]
100006f6c: 4e61d457    	fadd.2d	v23, v2, v1
100006f70: 3dc12901    	ldr	q1, [x8, #0x4a0]
100006f74: 6e64dc21    	fmul.2d	v1, v1, v4
100006f78: 3dc36902    	ldr	q2, [x8, #0xda0]
100006f7c: 4e61d441    	fadd.2d	v1, v2, v1
100006f80: 3dc0fbe2    	ldr	q2, [sp, #0x3e0]
100006f84: ad002c02    	stp	q2, q11, [x0]
100006f88: 3dc103e2    	ldr	q2, [sp, #0x400]
100006f8c: ad017802    	stp	q2, q30, [x0, #0x20]
100006f90: ad02680d    	stp	q13, q26, [x0, #0x40]
100006f94: 3dc0cbe4    	ldr	q4, [sp, #0x320]
100006f98: 3dc0ffe2    	ldr	q2, [sp, #0x3f0]
100006f9c: ad030804    	stp	q4, q2, [x0, #0x60]
100006fa0: 3dc0f7e2    	ldr	q2, [sp, #0x3d0]
100006fa4: ad040809    	stp	q9, q2, [x0, #0x80]
100006fa8: 3dc0efe2    	ldr	q2, [sp, #0x3b0]
100006fac: ad056c02    	stp	q2, q27, [x0, #0xa0]
100006fb0: 3dc0b7e4    	ldr	q4, [sp, #0x2d0]
100006fb4: 3dc0ebe2    	ldr	q2, [sp, #0x3a0]
100006fb8: ad060804    	stp	q4, q2, [x0, #0xc0]
100006fbc: 3dc0e7e4    	ldr	q4, [sp, #0x390]
100006fc0: 3dc0dfe2    	ldr	q2, [sp, #0x370]
100006fc4: ad070804    	stp	q4, q2, [x0, #0xe0]
100006fc8: 3dc0dbe2    	ldr	q2, [sp, #0x360]
100006fcc: ad081802    	stp	q2, q6, [x0, #0x100]
100006fd0: 3dc0e3e4    	ldr	q4, [sp, #0x380]
100006fd4: 3dc0d7e2    	ldr	q2, [sp, #0x350]
100006fd8: ad090804    	stp	q4, q2, [x0, #0x120]
100006fdc: ad5813e2    	ldp	q2, q4, [sp, #0x300]
100006fe0: ad0a101d    	stp	q29, q4, [x0, #0x140]
100006fe4: ad0b4402    	stp	q2, q17, [x0, #0x160]
100006fe8: 3dc08be4    	ldr	q4, [sp, #0x220]
100006fec: ad571be2    	ldp	q2, q6, [sp, #0x2e0]
100006ff0: ad0c1804    	stp	q4, q6, [x0, #0x180]
100006ff4: 3d806802    	str	q2, [x0, #0x1a0]
100006ff8: ad5513e2    	ldp	q2, q4, [sp, #0x2a0]
100006ffc: ad0d8804    	stp	q4, q2, [x0, #0x1b0]
100007000: 3dc07be4    	ldr	q4, [sp, #0x1e0]
100007004: 3dc0b3e2    	ldr	q2, [sp, #0x2c0]
100007008: ad0e8804    	stp	q4, q2, [x0, #0x1d0]
10000700c: ad5413e2    	ldp	q2, q4, [sp, #0x280]
100007010: ad0f8804    	stp	q4, q2, [x0, #0x1f0]
100007014: 3dc09fe4    	ldr	q4, [sp, #0x270]
100007018: ad528be6    	ldp	q6, q2, [sp, #0x250]
10000701c: ad109804    	stp	q4, q6, [x0, #0x210]
100007020: ad118812    	stp	q18, q2, [x0, #0x230]
100007024: ad5193e2    	ldp	q2, q4, [sp, #0x230]
100007028: ad128804    	stp	q4, q2, [x0, #0x250]
10000702c: ad5013e2    	ldp	q2, q4, [sp, #0x200]
100007030: ad13a004    	stp	q4, q8, [x0, #0x270]
100007034: ad148810    	stp	q16, q2, [x0, #0x290]
100007038: 3dc07fe4    	ldr	q4, [sp, #0x1f0]
10000703c: 3dc077e2    	ldr	q2, [sp, #0x1d0]
100007040: ad158804    	stp	q4, q2, [x0, #0x2b0]
100007044: 3dc0f3e2    	ldr	q2, [sp, #0x3c0]
100007048: ad168813    	stp	q19, q2, [x0, #0x2d0]
10000704c: ad17a818    	stp	q24, q10, [x0, #0x2f0]
100007050: ad4d93e2    	ldp	q2, q4, [sp, #0x1b0]
100007054: ad188804    	stp	q4, q2, [x0, #0x310]
100007058: ad4c8be6    	ldp	q6, q2, [sp, #0x190]
10000705c: ad19f006    	stp	q6, q28, [x0, #0x330]
100007060: 3dc0cfe4    	ldr	q4, [sp, #0x330]
100007064: ad1a8804    	stp	q4, q2, [x0, #0x350]
100007068: ad4b93e2    	ldp	q2, q4, [sp, #0x170]
10000706c: ad1b8804    	stp	q4, q2, [x0, #0x370]
100007070: ad4a8be4    	ldp	q4, q2, [sp, #0x150]
100007074: ad1cd404    	stp	q4, q21, [x0, #0x390]
100007078: ad1d8807    	stp	q7, q2, [x0, #0x3b0]
10000707c: 3dc053e2    	ldr	q2, [sp, #0x140]
100007080: ad1ee402    	stp	q2, q25, [x0, #0x3d0]
100007084: 3dc0d3e2    	ldr	q2, [sp, #0x340]
100007088: ad1f880e    	stp	q14, q2, [x0, #0x3f0]
10000708c: 3d810417    	str	q23, [x0, #0x410]
100007090: 3d810814    	str	q20, [x0, #0x420]
100007094: 3d810c05    	str	q5, [x0, #0x430]
100007098: 3d811003    	str	q3, [x0, #0x440]
10000709c: 3d811416    	str	q22, [x0, #0x450]
1000070a0: 3d811800    	str	q0, [x0, #0x460]
1000070a4: 3d811c01    	str	q1, [x0, #0x470]
1000070a8: 9120c3ff    	add	sp, sp, #0x830
1000070ac: a9457bfd    	ldp	x29, x30, [sp, #0x50]
1000070b0: a9446ffc    	ldp	x28, x27, [sp, #0x40]
1000070b4: 6d4323e9    	ldp	d9, d8, [sp, #0x30]
1000070b8: 6d422beb    	ldp	d11, d10, [sp, #0x20]
1000070bc: 6d4133ed    	ldp	d13, d12, [sp, #0x10]
1000070c0: 6cc63bef    	ldp	d15, d14, [sp], #0x60
1000070c4: d65f03c0    	ret

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

000000010000b3ec <_bench_primitives.checksumMatrix>:
10000b3ec: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
10000b3f0: 910003fd    	mov	x29, sp
10000b3f4: b0000088    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000b3f8: 91064108    	add	x8, x8, #0x190
10000b3fc: 2f00e400    	movi	d0, #0000000000000000
10000b400: 6d400901    	ldp	d1, d2, [x8]
10000b404: 1e602820    	fadd	d0, d1, d0
10000b408: 1e622841    	fadd	d1, d2, d2
10000b40c: 1e612800    	fadd	d0, d0, d1
10000b410: 1e611001    	fmov	d1, #3.00000000
10000b414: 6d410d02    	ldp	d2, d3, [x8, #0x10]
10000b418: 1e610841    	fmul	d1, d2, d1
10000b41c: 1e612800    	fadd	d0, d0, d1
10000b420: 1e621001    	fmov	d1, #4.00000000
10000b424: 1e610861    	fmul	d1, d3, d1
10000b428: 1e612800    	fadd	d0, d0, d1
10000b42c: 1e629001    	fmov	d1, #5.00000000
10000b430: 6d420d02    	ldp	d2, d3, [x8, #0x20]
10000b434: 1e610841    	fmul	d1, d2, d1
10000b438: 1e612800    	fadd	d0, d0, d1
10000b43c: 1e631001    	fmov	d1, #6.00000000
10000b440: 1e610861    	fmul	d1, d3, d1
10000b444: 1e612800    	fadd	d0, d0, d1
10000b448: 1e639001    	fmov	d1, #7.00000000
10000b44c: 6d430d02    	ldp	d2, d3, [x8, #0x30]
10000b450: 1e610841    	fmul	d1, d2, d1
10000b454: 1e612800    	fadd	d0, d0, d1
10000b458: 1e641001    	fmov	d1, #8.00000000
10000b45c: 1e610861    	fmul	d1, d3, d1
10000b460: 1e612800    	fadd	d0, d0, d1
10000b464: 1e645001    	fmov	d1, #9.00000000
10000b468: 6d440d02    	ldp	d2, d3, [x8, #0x40]
10000b46c: 1e610841    	fmul	d1, d2, d1
10000b470: 1e612800    	fadd	d0, d0, d1
10000b474: 1e649001    	fmov	d1, #10.00000000
10000b478: 1e610861    	fmul	d1, d3, d1
10000b47c: 1e612800    	fadd	d0, d0, d1
10000b480: 1e64d001    	fmov	d1, #11.00000000
10000b484: 6d450d02    	ldp	d2, d3, [x8, #0x50]
10000b488: 1e610841    	fmul	d1, d2, d1
10000b48c: 1e612800    	fadd	d0, d0, d1
10000b490: 1e651001    	fmov	d1, #12.00000000
10000b494: 1e610861    	fmul	d1, d3, d1
10000b498: 1e612800    	fadd	d0, d0, d1
10000b49c: 1e655001    	fmov	d1, #13.00000000
10000b4a0: 6d460d02    	ldp	d2, d3, [x8, #0x60]
10000b4a4: 1e610841    	fmul	d1, d2, d1
10000b4a8: 1e612800    	fadd	d0, d0, d1
10000b4ac: 1e659001    	fmov	d1, #14.00000000
10000b4b0: 1e610861    	fmul	d1, d3, d1
10000b4b4: 1e612800    	fadd	d0, d0, d1
10000b4b8: 1e65d001    	fmov	d1, #15.00000000
10000b4bc: 6d470d02    	ldp	d2, d3, [x8, #0x70]
10000b4c0: 1e610841    	fmul	d1, d2, d1
10000b4c4: 1e612800    	fadd	d0, d0, d1
10000b4c8: 1e661001    	fmov	d1, #16.00000000
10000b4cc: 1e610861    	fmul	d1, d3, d1
10000b4d0: 1e612800    	fadd	d0, d0, d1
10000b4d4: 1e663001    	fmov	d1, #17.00000000
10000b4d8: 6d480d02    	ldp	d2, d3, [x8, #0x80]
10000b4dc: 1e610841    	fmul	d1, d2, d1
10000b4e0: 1e612800    	fadd	d0, d0, d1
10000b4e4: 1e665001    	fmov	d1, #18.00000000
10000b4e8: 1e610861    	fmul	d1, d3, d1
10000b4ec: 1e612800    	fadd	d0, d0, d1
10000b4f0: 1e667001    	fmov	d1, #19.00000000
10000b4f4: 6d490d02    	ldp	d2, d3, [x8, #0x90]
10000b4f8: 1e610841    	fmul	d1, d2, d1
10000b4fc: 1e612800    	fadd	d0, d0, d1
10000b500: 1e669001    	fmov	d1, #20.00000000
10000b504: 1e610861    	fmul	d1, d3, d1
10000b508: 1e612800    	fadd	d0, d0, d1
10000b50c: 1e66b001    	fmov	d1, #21.00000000
10000b510: 6d4a0d02    	ldp	d2, d3, [x8, #0xa0]
10000b514: 1e610841    	fmul	d1, d2, d1
10000b518: 1e612800    	fadd	d0, d0, d1
10000b51c: 1e66d001    	fmov	d1, #22.00000000
10000b520: 1e610861    	fmul	d1, d3, d1
10000b524: 1e612800    	fadd	d0, d0, d1
10000b528: 1e66f001    	fmov	d1, #23.00000000
10000b52c: 6d4b0d02    	ldp	d2, d3, [x8, #0xb0]
10000b530: 1e610841    	fmul	d1, d2, d1
10000b534: 1e612800    	fadd	d0, d0, d1
10000b538: 1e671001    	fmov	d1, #24.00000000
10000b53c: 1e610861    	fmul	d1, d3, d1
10000b540: 1e612800    	fadd	d0, d0, d1
10000b544: 1e673001    	fmov	d1, #25.00000000
10000b548: 6d4c0d02    	ldp	d2, d3, [x8, #0xc0]
10000b54c: 1e610841    	fmul	d1, d2, d1
10000b550: 1e612800    	fadd	d0, d0, d1
10000b554: 1e675001    	fmov	d1, #26.00000000
10000b558: 1e610861    	fmul	d1, d3, d1
10000b55c: 1e612800    	fadd	d0, d0, d1
10000b560: 1e677001    	fmov	d1, #27.00000000
10000b564: 6d4d0d02    	ldp	d2, d3, [x8, #0xd0]
10000b568: 1e610841    	fmul	d1, d2, d1
10000b56c: 1e612800    	fadd	d0, d0, d1
10000b570: 1e679001    	fmov	d1, #28.00000000
10000b574: 1e610861    	fmul	d1, d3, d1
10000b578: 1e612800    	fadd	d0, d0, d1
10000b57c: 1e67b001    	fmov	d1, #29.00000000
10000b580: 6d4e0d02    	ldp	d2, d3, [x8, #0xe0]
10000b584: 1e610841    	fmul	d1, d2, d1
10000b588: 1e612800    	fadd	d0, d0, d1
10000b58c: 1e67d001    	fmov	d1, #30.00000000
10000b590: 1e610861    	fmul	d1, d3, d1
10000b594: 1e612800    	fadd	d0, d0, d1
10000b598: 1e67f001    	fmov	d1, #31.00000000
10000b59c: 6d4f0d02    	ldp	d2, d3, [x8, #0xf0]
10000b5a0: 1e610841    	fmul	d1, d2, d1
10000b5a4: 1e612800    	fadd	d0, d0, d1
10000b5a8: d2e80809    	mov	x9, #0x4040000000000000 ; =4629700416936869888
10000b5ac: 9e670121    	fmov	d1, x9
10000b5b0: 1e610861    	fmul	d1, d3, d1
10000b5b4: 1e612800    	fadd	d0, d0, d1
10000b5b8: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b5bc: f2e80809    	movk	x9, #0x4040, lsl #48
10000b5c0: 9e670121    	fmov	d1, x9
10000b5c4: 6d500d02    	ldp	d2, d3, [x8, #0x100]
10000b5c8: 1e610841    	fmul	d1, d2, d1
10000b5cc: 1e612800    	fadd	d0, d0, d1
10000b5d0: d2e80829    	mov	x9, #0x4041000000000000 ; =4629981891913580544
10000b5d4: 9e670121    	fmov	d1, x9
10000b5d8: 1e610861    	fmul	d1, d3, d1
10000b5dc: 1e612800    	fadd	d0, d0, d1
10000b5e0: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b5e4: f2e80829    	movk	x9, #0x4041, lsl #48
10000b5e8: 9e670121    	fmov	d1, x9
10000b5ec: 6d510d02    	ldp	d2, d3, [x8, #0x110]
10000b5f0: 1e610841    	fmul	d1, d2, d1
10000b5f4: 1e612800    	fadd	d0, d0, d1
10000b5f8: d2e80849    	mov	x9, #0x4042000000000000 ; =4630263366890291200
10000b5fc: 9e670121    	fmov	d1, x9
10000b600: 1e610861    	fmul	d1, d3, d1
10000b604: 1e612800    	fadd	d0, d0, d1
10000b608: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b60c: f2e80849    	movk	x9, #0x4042, lsl #48
10000b610: 9e670121    	fmov	d1, x9
10000b614: 6d520d02    	ldp	d2, d3, [x8, #0x120]
10000b618: 1e610841    	fmul	d1, d2, d1
10000b61c: 1e612800    	fadd	d0, d0, d1
10000b620: d2e80869    	mov	x9, #0x4043000000000000 ; =4630544841867001856
10000b624: 9e670121    	fmov	d1, x9
10000b628: 1e610861    	fmul	d1, d3, d1
10000b62c: 1e612800    	fadd	d0, d0, d1
10000b630: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b634: f2e80869    	movk	x9, #0x4043, lsl #48
10000b638: 9e670121    	fmov	d1, x9
10000b63c: 6d530d02    	ldp	d2, d3, [x8, #0x130]
10000b640: 1e610841    	fmul	d1, d2, d1
10000b644: 1e612800    	fadd	d0, d0, d1
10000b648: d2e80889    	mov	x9, #0x4044000000000000 ; =4630826316843712512
10000b64c: 9e670121    	fmov	d1, x9
10000b650: 1e610861    	fmul	d1, d3, d1
10000b654: 1e612800    	fadd	d0, d0, d1
10000b658: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b65c: f2e80889    	movk	x9, #0x4044, lsl #48
10000b660: 9e670121    	fmov	d1, x9
10000b664: 6d540d02    	ldp	d2, d3, [x8, #0x140]
10000b668: 1e610841    	fmul	d1, d2, d1
10000b66c: 1e612800    	fadd	d0, d0, d1
10000b670: d2e808a9    	mov	x9, #0x4045000000000000 ; =4631107791820423168
10000b674: 9e670121    	fmov	d1, x9
10000b678: 1e610861    	fmul	d1, d3, d1
10000b67c: 1e612800    	fadd	d0, d0, d1
10000b680: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b684: f2e808a9    	movk	x9, #0x4045, lsl #48
10000b688: 9e670121    	fmov	d1, x9
10000b68c: 6d550d02    	ldp	d2, d3, [x8, #0x150]
10000b690: 1e610841    	fmul	d1, d2, d1
10000b694: 1e612800    	fadd	d0, d0, d1
10000b698: d2e808c9    	mov	x9, #0x4046000000000000 ; =4631389266797133824
10000b69c: 9e670121    	fmov	d1, x9
10000b6a0: 1e610861    	fmul	d1, d3, d1
10000b6a4: 1e612800    	fadd	d0, d0, d1
10000b6a8: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b6ac: f2e808c9    	movk	x9, #0x4046, lsl #48
10000b6b0: 9e670121    	fmov	d1, x9
10000b6b4: 6d560d02    	ldp	d2, d3, [x8, #0x160]
10000b6b8: 1e610841    	fmul	d1, d2, d1
10000b6bc: 1e612800    	fadd	d0, d0, d1
10000b6c0: d2e808e9    	mov	x9, #0x4047000000000000 ; =4631670741773844480
10000b6c4: 9e670121    	fmov	d1, x9
10000b6c8: 1e610861    	fmul	d1, d3, d1
10000b6cc: 1e612800    	fadd	d0, d0, d1
10000b6d0: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b6d4: f2e808e9    	movk	x9, #0x4047, lsl #48
10000b6d8: 9e670121    	fmov	d1, x9
10000b6dc: 6d570d02    	ldp	d2, d3, [x8, #0x170]
10000b6e0: 1e610841    	fmul	d1, d2, d1
10000b6e4: 1e612800    	fadd	d0, d0, d1
10000b6e8: d2e80909    	mov	x9, #0x4048000000000000 ; =4631952216750555136
10000b6ec: 9e670121    	fmov	d1, x9
10000b6f0: 1e610861    	fmul	d1, d3, d1
10000b6f4: 1e612800    	fadd	d0, d0, d1
10000b6f8: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b6fc: f2e80909    	movk	x9, #0x4048, lsl #48
10000b700: 9e670121    	fmov	d1, x9
10000b704: 6d580d02    	ldp	d2, d3, [x8, #0x180]
10000b708: 1e610841    	fmul	d1, d2, d1
10000b70c: 1e612800    	fadd	d0, d0, d1
10000b710: d2e80929    	mov	x9, #0x4049000000000000 ; =4632233691727265792
10000b714: 9e670121    	fmov	d1, x9
10000b718: 1e610861    	fmul	d1, d3, d1
10000b71c: 1e612800    	fadd	d0, d0, d1
10000b720: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b724: f2e80929    	movk	x9, #0x4049, lsl #48
10000b728: 9e670121    	fmov	d1, x9
10000b72c: 6d590d02    	ldp	d2, d3, [x8, #0x190]
10000b730: 1e610841    	fmul	d1, d2, d1
10000b734: 1e612800    	fadd	d0, d0, d1
10000b738: d2e80949    	mov	x9, #0x404a000000000000 ; =4632515166703976448
10000b73c: 9e670121    	fmov	d1, x9
10000b740: 1e610861    	fmul	d1, d3, d1
10000b744: 1e612800    	fadd	d0, d0, d1
10000b748: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b74c: f2e80949    	movk	x9, #0x404a, lsl #48
10000b750: 9e670121    	fmov	d1, x9
10000b754: 6d5a0d02    	ldp	d2, d3, [x8, #0x1a0]
10000b758: 1e610841    	fmul	d1, d2, d1
10000b75c: 1e612800    	fadd	d0, d0, d1
10000b760: d2e80969    	mov	x9, #0x404b000000000000 ; =4632796641680687104
10000b764: 9e670121    	fmov	d1, x9
10000b768: 1e610861    	fmul	d1, d3, d1
10000b76c: 1e612800    	fadd	d0, d0, d1
10000b770: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b774: f2e80969    	movk	x9, #0x404b, lsl #48
10000b778: 9e670121    	fmov	d1, x9
10000b77c: 6d5b0d02    	ldp	d2, d3, [x8, #0x1b0]
10000b780: 1e610841    	fmul	d1, d2, d1
10000b784: 1e612800    	fadd	d0, d0, d1
10000b788: d2e80989    	mov	x9, #0x404c000000000000 ; =4633078116657397760
10000b78c: 9e670121    	fmov	d1, x9
10000b790: 1e610861    	fmul	d1, d3, d1
10000b794: 1e612800    	fadd	d0, d0, d1
10000b798: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b79c: f2e80989    	movk	x9, #0x404c, lsl #48
10000b7a0: 9e670121    	fmov	d1, x9
10000b7a4: 6d5c0d02    	ldp	d2, d3, [x8, #0x1c0]
10000b7a8: 1e610841    	fmul	d1, d2, d1
10000b7ac: 1e612800    	fadd	d0, d0, d1
10000b7b0: d2e809a9    	mov	x9, #0x404d000000000000 ; =4633359591634108416
10000b7b4: 9e670121    	fmov	d1, x9
10000b7b8: 1e610861    	fmul	d1, d3, d1
10000b7bc: 1e612800    	fadd	d0, d0, d1
10000b7c0: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b7c4: f2e809a9    	movk	x9, #0x404d, lsl #48
10000b7c8: 9e670121    	fmov	d1, x9
10000b7cc: 6d5d0d02    	ldp	d2, d3, [x8, #0x1d0]
10000b7d0: 1e610841    	fmul	d1, d2, d1
10000b7d4: 1e612800    	fadd	d0, d0, d1
10000b7d8: d2e809c9    	mov	x9, #0x404e000000000000 ; =4633641066610819072
10000b7dc: 9e670121    	fmov	d1, x9
10000b7e0: 1e610861    	fmul	d1, d3, d1
10000b7e4: 1e612800    	fadd	d0, d0, d1
10000b7e8: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b7ec: f2e809c9    	movk	x9, #0x404e, lsl #48
10000b7f0: 9e670121    	fmov	d1, x9
10000b7f4: 6d5e0d02    	ldp	d2, d3, [x8, #0x1e0]
10000b7f8: 1e610841    	fmul	d1, d2, d1
10000b7fc: 1e612800    	fadd	d0, d0, d1
10000b800: d2e809e9    	mov	x9, #0x404f000000000000 ; =4633922541587529728
10000b804: 9e670121    	fmov	d1, x9
10000b808: 1e610861    	fmul	d1, d3, d1
10000b80c: 1e612800    	fadd	d0, d0, d1
10000b810: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b814: f2e809e9    	movk	x9, #0x404f, lsl #48
10000b818: 9e670121    	fmov	d1, x9
10000b81c: 6d5f0d02    	ldp	d2, d3, [x8, #0x1f0]
10000b820: 1e610841    	fmul	d1, d2, d1
10000b824: 1e612800    	fadd	d0, d0, d1
10000b828: d2e80a09    	mov	x9, #0x4050000000000000 ; =4634204016564240384
10000b82c: 9e670121    	fmov	d1, x9
10000b830: 1e610861    	fmul	d1, d3, d1
10000b834: 1e612800    	fadd	d0, d0, d1
10000b838: fd410101    	ldr	d1, [x8, #0x200]
10000b83c: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000b840: f2e80a09    	movk	x9, #0x4050, lsl #48
10000b844: 9e670122    	fmov	d2, x9
10000b848: 1e620821    	fmul	d1, d1, d2
10000b84c: 1e612800    	fadd	d0, d0, d1
10000b850: fd410501    	ldr	d1, [x8, #0x208]
10000b854: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b858: f2e80a09    	movk	x9, #0x4050, lsl #48
10000b85c: 9e670122    	fmov	d2, x9
10000b860: 1e620821    	fmul	d1, d1, d2
10000b864: 1e612800    	fadd	d0, d0, d1
10000b868: fd410901    	ldr	d1, [x8, #0x210]
10000b86c: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000b870: f2e80a09    	movk	x9, #0x4050, lsl #48
10000b874: 9e670122    	fmov	d2, x9
10000b878: 1e620821    	fmul	d1, d1, d2
10000b87c: 1e612800    	fadd	d0, d0, d1
10000b880: fd410d01    	ldr	d1, [x8, #0x218]
10000b884: d2e80a29    	mov	x9, #0x4051000000000000 ; =4634485491540951040
10000b888: 9e670122    	fmov	d2, x9
10000b88c: 1e620821    	fmul	d1, d1, d2
10000b890: 1e612800    	fadd	d0, d0, d1
10000b894: fd411101    	ldr	d1, [x8, #0x220]
10000b898: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000b89c: f2e80a29    	movk	x9, #0x4051, lsl #48
10000b8a0: 9e670122    	fmov	d2, x9
10000b8a4: 1e620821    	fmul	d1, d1, d2
10000b8a8: 1e612800    	fadd	d0, d0, d1
10000b8ac: fd411501    	ldr	d1, [x8, #0x228]
10000b8b0: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b8b4: f2e80a29    	movk	x9, #0x4051, lsl #48
10000b8b8: 9e670122    	fmov	d2, x9
10000b8bc: 1e620821    	fmul	d1, d1, d2
10000b8c0: 1e612800    	fadd	d0, d0, d1
10000b8c4: fd411901    	ldr	d1, [x8, #0x230]
10000b8c8: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000b8cc: f2e80a29    	movk	x9, #0x4051, lsl #48
10000b8d0: 9e670122    	fmov	d2, x9
10000b8d4: 1e620821    	fmul	d1, d1, d2
10000b8d8: 1e612800    	fadd	d0, d0, d1
10000b8dc: fd411d01    	ldr	d1, [x8, #0x238]
10000b8e0: d2e80a49    	mov	x9, #0x4052000000000000 ; =4634766966517661696
10000b8e4: 9e670122    	fmov	d2, x9
10000b8e8: 1e620821    	fmul	d1, d1, d2
10000b8ec: 1e612800    	fadd	d0, d0, d1
10000b8f0: fd412101    	ldr	d1, [x8, #0x240]
10000b8f4: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000b8f8: f2e80a49    	movk	x9, #0x4052, lsl #48
10000b8fc: 9e670122    	fmov	d2, x9
10000b900: 1e620821    	fmul	d1, d1, d2
10000b904: 1e612800    	fadd	d0, d0, d1
10000b908: fd412501    	ldr	d1, [x8, #0x248]
10000b90c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b910: f2e80a49    	movk	x9, #0x4052, lsl #48
10000b914: 9e670122    	fmov	d2, x9
10000b918: 1e620821    	fmul	d1, d1, d2
10000b91c: 1e612800    	fadd	d0, d0, d1
10000b920: fd412901    	ldr	d1, [x8, #0x250]
10000b924: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000b928: f2e80a49    	movk	x9, #0x4052, lsl #48
10000b92c: 9e670122    	fmov	d2, x9
10000b930: 1e620821    	fmul	d1, d1, d2
10000b934: 1e612800    	fadd	d0, d0, d1
10000b938: fd412d01    	ldr	d1, [x8, #0x258]
10000b93c: d2e80a69    	mov	x9, #0x4053000000000000 ; =4635048441494372352
10000b940: 9e670122    	fmov	d2, x9
10000b944: 1e620821    	fmul	d1, d1, d2
10000b948: 1e612800    	fadd	d0, d0, d1
10000b94c: fd413101    	ldr	d1, [x8, #0x260]
10000b950: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000b954: f2e80a69    	movk	x9, #0x4053, lsl #48
10000b958: 9e670122    	fmov	d2, x9
10000b95c: 1e620821    	fmul	d1, d1, d2
10000b960: 1e612800    	fadd	d0, d0, d1
10000b964: fd413501    	ldr	d1, [x8, #0x268]
10000b968: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b96c: f2e80a69    	movk	x9, #0x4053, lsl #48
10000b970: 9e670122    	fmov	d2, x9
10000b974: 1e620821    	fmul	d1, d1, d2
10000b978: 1e612800    	fadd	d0, d0, d1
10000b97c: fd413901    	ldr	d1, [x8, #0x270]
10000b980: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000b984: f2e80a69    	movk	x9, #0x4053, lsl #48
10000b988: 9e670122    	fmov	d2, x9
10000b98c: 1e620821    	fmul	d1, d1, d2
10000b990: 1e612800    	fadd	d0, d0, d1
10000b994: fd413d01    	ldr	d1, [x8, #0x278]
10000b998: d2e80a89    	mov	x9, #0x4054000000000000 ; =4635329916471083008
10000b99c: 9e670122    	fmov	d2, x9
10000b9a0: 1e620821    	fmul	d1, d1, d2
10000b9a4: 1e612800    	fadd	d0, d0, d1
10000b9a8: fd414101    	ldr	d1, [x8, #0x280]
10000b9ac: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000b9b0: f2e80a89    	movk	x9, #0x4054, lsl #48
10000b9b4: 9e670122    	fmov	d2, x9
10000b9b8: 1e620821    	fmul	d1, d1, d2
10000b9bc: 1e612800    	fadd	d0, d0, d1
10000b9c0: fd414501    	ldr	d1, [x8, #0x288]
10000b9c4: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000b9c8: f2e80a89    	movk	x9, #0x4054, lsl #48
10000b9cc: 9e670122    	fmov	d2, x9
10000b9d0: 1e620821    	fmul	d1, d1, d2
10000b9d4: 1e612800    	fadd	d0, d0, d1
10000b9d8: fd414901    	ldr	d1, [x8, #0x290]
10000b9dc: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000b9e0: f2e80a89    	movk	x9, #0x4054, lsl #48
10000b9e4: 9e670122    	fmov	d2, x9
10000b9e8: 1e620821    	fmul	d1, d1, d2
10000b9ec: 1e612800    	fadd	d0, d0, d1
10000b9f0: fd414d01    	ldr	d1, [x8, #0x298]
10000b9f4: d2e80aa9    	mov	x9, #0x4055000000000000 ; =4635611391447793664
10000b9f8: 9e670122    	fmov	d2, x9
10000b9fc: 1e620821    	fmul	d1, d1, d2
10000ba00: 1e612800    	fadd	d0, d0, d1
10000ba04: fd415101    	ldr	d1, [x8, #0x2a0]
10000ba08: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000ba0c: f2e80aa9    	movk	x9, #0x4055, lsl #48
10000ba10: 9e670122    	fmov	d2, x9
10000ba14: 1e620821    	fmul	d1, d1, d2
10000ba18: 1e612800    	fadd	d0, d0, d1
10000ba1c: fd415501    	ldr	d1, [x8, #0x2a8]
10000ba20: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000ba24: f2e80aa9    	movk	x9, #0x4055, lsl #48
10000ba28: 9e670122    	fmov	d2, x9
10000ba2c: 1e620821    	fmul	d1, d1, d2
10000ba30: 1e612800    	fadd	d0, d0, d1
10000ba34: fd415901    	ldr	d1, [x8, #0x2b0]
10000ba38: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000ba3c: f2e80aa9    	movk	x9, #0x4055, lsl #48
10000ba40: 9e670122    	fmov	d2, x9
10000ba44: 1e620821    	fmul	d1, d1, d2
10000ba48: 1e612800    	fadd	d0, d0, d1
10000ba4c: fd415d01    	ldr	d1, [x8, #0x2b8]
10000ba50: d2e80ac9    	mov	x9, #0x4056000000000000 ; =4635892866424504320
10000ba54: 9e670122    	fmov	d2, x9
10000ba58: 1e620821    	fmul	d1, d1, d2
10000ba5c: 1e612800    	fadd	d0, d0, d1
10000ba60: fd416101    	ldr	d1, [x8, #0x2c0]
10000ba64: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000ba68: f2e80ac9    	movk	x9, #0x4056, lsl #48
10000ba6c: 9e670122    	fmov	d2, x9
10000ba70: 1e620821    	fmul	d1, d1, d2
10000ba74: 1e612800    	fadd	d0, d0, d1
10000ba78: fd416501    	ldr	d1, [x8, #0x2c8]
10000ba7c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000ba80: f2e80ac9    	movk	x9, #0x4056, lsl #48
10000ba84: 9e670122    	fmov	d2, x9
10000ba88: 1e620821    	fmul	d1, d1, d2
10000ba8c: 1e612800    	fadd	d0, d0, d1
10000ba90: fd416901    	ldr	d1, [x8, #0x2d0]
10000ba94: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000ba98: f2e80ac9    	movk	x9, #0x4056, lsl #48
10000ba9c: 9e670122    	fmov	d2, x9
10000baa0: 1e620821    	fmul	d1, d1, d2
10000baa4: 1e612800    	fadd	d0, d0, d1
10000baa8: fd416d01    	ldr	d1, [x8, #0x2d8]
10000baac: d2e80ae9    	mov	x9, #0x4057000000000000 ; =4636174341401214976
10000bab0: 9e670122    	fmov	d2, x9
10000bab4: 1e620821    	fmul	d1, d1, d2
10000bab8: 1e612800    	fadd	d0, d0, d1
10000babc: fd417101    	ldr	d1, [x8, #0x2e0]
10000bac0: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000bac4: f2e80ae9    	movk	x9, #0x4057, lsl #48
10000bac8: 9e670122    	fmov	d2, x9
10000bacc: 1e620821    	fmul	d1, d1, d2
10000bad0: 1e612800    	fadd	d0, d0, d1
10000bad4: fd417501    	ldr	d1, [x8, #0x2e8]
10000bad8: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000badc: f2e80ae9    	movk	x9, #0x4057, lsl #48
10000bae0: 9e670122    	fmov	d2, x9
10000bae4: 1e620821    	fmul	d1, d1, d2
10000bae8: 1e612800    	fadd	d0, d0, d1
10000baec: fd417901    	ldr	d1, [x8, #0x2f0]
10000baf0: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000baf4: f2e80ae9    	movk	x9, #0x4057, lsl #48
10000baf8: 9e670122    	fmov	d2, x9
10000bafc: 1e620821    	fmul	d1, d1, d2
10000bb00: 1e612800    	fadd	d0, d0, d1
10000bb04: fd417d01    	ldr	d1, [x8, #0x2f8]
10000bb08: d2e80b09    	mov	x9, #0x4058000000000000 ; =4636455816377925632
10000bb0c: 9e670122    	fmov	d2, x9
10000bb10: 1e620821    	fmul	d1, d1, d2
10000bb14: 1e612800    	fadd	d0, d0, d1
10000bb18: fd418101    	ldr	d1, [x8, #0x300]
10000bb1c: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000bb20: f2e80b09    	movk	x9, #0x4058, lsl #48
10000bb24: 9e670122    	fmov	d2, x9
10000bb28: 1e620821    	fmul	d1, d1, d2
10000bb2c: 1e612800    	fadd	d0, d0, d1
10000bb30: fd418501    	ldr	d1, [x8, #0x308]
10000bb34: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000bb38: f2e80b09    	movk	x9, #0x4058, lsl #48
10000bb3c: 9e670122    	fmov	d2, x9
10000bb40: 1e620821    	fmul	d1, d1, d2
10000bb44: 1e612800    	fadd	d0, d0, d1
10000bb48: fd418901    	ldr	d1, [x8, #0x310]
10000bb4c: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000bb50: f2e80b09    	movk	x9, #0x4058, lsl #48
10000bb54: 9e670122    	fmov	d2, x9
10000bb58: 1e620821    	fmul	d1, d1, d2
10000bb5c: 1e612800    	fadd	d0, d0, d1
10000bb60: fd418d01    	ldr	d1, [x8, #0x318]
10000bb64: d2e80b29    	mov	x9, #0x4059000000000000 ; =4636737291354636288
10000bb68: 9e670122    	fmov	d2, x9
10000bb6c: 1e620821    	fmul	d1, d1, d2
10000bb70: 1e612800    	fadd	d0, d0, d1
10000bb74: fd419101    	ldr	d1, [x8, #0x320]
10000bb78: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000bb7c: f2e80b29    	movk	x9, #0x4059, lsl #48
10000bb80: 9e670122    	fmov	d2, x9
10000bb84: 1e620821    	fmul	d1, d1, d2
10000bb88: 1e612800    	fadd	d0, d0, d1
10000bb8c: fd419501    	ldr	d1, [x8, #0x328]
10000bb90: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000bb94: f2e80b29    	movk	x9, #0x4059, lsl #48
10000bb98: 9e670122    	fmov	d2, x9
10000bb9c: 1e620821    	fmul	d1, d1, d2
10000bba0: 1e612800    	fadd	d0, d0, d1
10000bba4: fd419901    	ldr	d1, [x8, #0x330]
10000bba8: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000bbac: f2e80b29    	movk	x9, #0x4059, lsl #48
10000bbb0: 9e670122    	fmov	d2, x9
10000bbb4: 1e620821    	fmul	d1, d1, d2
10000bbb8: 1e612800    	fadd	d0, d0, d1
10000bbbc: fd419d01    	ldr	d1, [x8, #0x338]
10000bbc0: d2e80b49    	mov	x9, #0x405a000000000000 ; =4637018766331346944
10000bbc4: 9e670122    	fmov	d2, x9
10000bbc8: 1e620821    	fmul	d1, d1, d2
10000bbcc: 1e612800    	fadd	d0, d0, d1
10000bbd0: fd41a101    	ldr	d1, [x8, #0x340]
10000bbd4: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000bbd8: f2e80b49    	movk	x9, #0x405a, lsl #48
10000bbdc: 9e670122    	fmov	d2, x9
10000bbe0: 1e620821    	fmul	d1, d1, d2
10000bbe4: 1e612800    	fadd	d0, d0, d1
10000bbe8: fd41a501    	ldr	d1, [x8, #0x348]
10000bbec: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000bbf0: f2e80b49    	movk	x9, #0x405a, lsl #48
10000bbf4: 9e670122    	fmov	d2, x9
10000bbf8: 1e620821    	fmul	d1, d1, d2
10000bbfc: 1e612800    	fadd	d0, d0, d1
10000bc00: fd41a901    	ldr	d1, [x8, #0x350]
10000bc04: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000bc08: f2e80b49    	movk	x9, #0x405a, lsl #48
10000bc0c: 9e670122    	fmov	d2, x9
10000bc10: 1e620821    	fmul	d1, d1, d2
10000bc14: 1e612800    	fadd	d0, d0, d1
10000bc18: fd41ad01    	ldr	d1, [x8, #0x358]
10000bc1c: d2e80b69    	mov	x9, #0x405b000000000000 ; =4637300241308057600
10000bc20: 9e670122    	fmov	d2, x9
10000bc24: 1e620821    	fmul	d1, d1, d2
10000bc28: 1e612800    	fadd	d0, d0, d1
10000bc2c: fd41b101    	ldr	d1, [x8, #0x360]
10000bc30: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000bc34: f2e80b69    	movk	x9, #0x405b, lsl #48
10000bc38: 9e670122    	fmov	d2, x9
10000bc3c: 1e620821    	fmul	d1, d1, d2
10000bc40: 1e612800    	fadd	d0, d0, d1
10000bc44: fd41b501    	ldr	d1, [x8, #0x368]
10000bc48: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000bc4c: f2e80b69    	movk	x9, #0x405b, lsl #48
10000bc50: 9e670122    	fmov	d2, x9
10000bc54: 1e620821    	fmul	d1, d1, d2
10000bc58: 1e612800    	fadd	d0, d0, d1
10000bc5c: fd41b901    	ldr	d1, [x8, #0x370]
10000bc60: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000bc64: f2e80b69    	movk	x9, #0x405b, lsl #48
10000bc68: 9e670122    	fmov	d2, x9
10000bc6c: 1e620821    	fmul	d1, d1, d2
10000bc70: 1e612800    	fadd	d0, d0, d1
10000bc74: fd41bd01    	ldr	d1, [x8, #0x378]
10000bc78: d2e80b89    	mov	x9, #0x405c000000000000 ; =4637581716284768256
10000bc7c: 9e670122    	fmov	d2, x9
10000bc80: 1e620821    	fmul	d1, d1, d2
10000bc84: 1e612800    	fadd	d0, d0, d1
10000bc88: fd41c101    	ldr	d1, [x8, #0x380]
10000bc8c: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000bc90: f2e80b89    	movk	x9, #0x405c, lsl #48
10000bc94: 9e670122    	fmov	d2, x9
10000bc98: 1e620821    	fmul	d1, d1, d2
10000bc9c: 1e612800    	fadd	d0, d0, d1
10000bca0: fd41c501    	ldr	d1, [x8, #0x388]
10000bca4: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000bca8: f2e80b89    	movk	x9, #0x405c, lsl #48
10000bcac: 9e670122    	fmov	d2, x9
10000bcb0: 1e620821    	fmul	d1, d1, d2
10000bcb4: 1e612800    	fadd	d0, d0, d1
10000bcb8: fd41c901    	ldr	d1, [x8, #0x390]
10000bcbc: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000bcc0: f2e80b89    	movk	x9, #0x405c, lsl #48
10000bcc4: 9e670122    	fmov	d2, x9
10000bcc8: 1e620821    	fmul	d1, d1, d2
10000bccc: 1e612800    	fadd	d0, d0, d1
10000bcd0: fd41cd01    	ldr	d1, [x8, #0x398]
10000bcd4: d2e80ba9    	mov	x9, #0x405d000000000000 ; =4637863191261478912
10000bcd8: 9e670122    	fmov	d2, x9
10000bcdc: 1e620821    	fmul	d1, d1, d2
10000bce0: 1e612800    	fadd	d0, d0, d1
10000bce4: fd41d101    	ldr	d1, [x8, #0x3a0]
10000bce8: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000bcec: f2e80ba9    	movk	x9, #0x405d, lsl #48
10000bcf0: 9e670122    	fmov	d2, x9
10000bcf4: 1e620821    	fmul	d1, d1, d2
10000bcf8: 1e612800    	fadd	d0, d0, d1
10000bcfc: fd41d501    	ldr	d1, [x8, #0x3a8]
10000bd00: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000bd04: f2e80ba9    	movk	x9, #0x405d, lsl #48
10000bd08: 9e670122    	fmov	d2, x9
10000bd0c: 1e620821    	fmul	d1, d1, d2
10000bd10: 1e612800    	fadd	d0, d0, d1
10000bd14: fd41d901    	ldr	d1, [x8, #0x3b0]
10000bd18: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000bd1c: f2e80ba9    	movk	x9, #0x405d, lsl #48
10000bd20: 9e670122    	fmov	d2, x9
10000bd24: 1e620821    	fmul	d1, d1, d2
10000bd28: 1e612800    	fadd	d0, d0, d1
10000bd2c: fd41dd01    	ldr	d1, [x8, #0x3b8]
10000bd30: d2e80bc9    	mov	x9, #0x405e000000000000 ; =4638144666238189568
10000bd34: 9e670122    	fmov	d2, x9
10000bd38: 1e620821    	fmul	d1, d1, d2
10000bd3c: 1e612800    	fadd	d0, d0, d1
10000bd40: fd41e101    	ldr	d1, [x8, #0x3c0]
10000bd44: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000bd48: f2e80bc9    	movk	x9, #0x405e, lsl #48
10000bd4c: 9e670122    	fmov	d2, x9
10000bd50: 1e620821    	fmul	d1, d1, d2
10000bd54: 1e612800    	fadd	d0, d0, d1
10000bd58: fd41e501    	ldr	d1, [x8, #0x3c8]
10000bd5c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000bd60: f2e80bc9    	movk	x9, #0x405e, lsl #48
10000bd64: 9e670122    	fmov	d2, x9
10000bd68: 1e620821    	fmul	d1, d1, d2
10000bd6c: 1e612800    	fadd	d0, d0, d1
10000bd70: fd41e901    	ldr	d1, [x8, #0x3d0]
10000bd74: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000bd78: f2e80bc9    	movk	x9, #0x405e, lsl #48
10000bd7c: 9e670122    	fmov	d2, x9
10000bd80: 1e620821    	fmul	d1, d1, d2
10000bd84: 1e612800    	fadd	d0, d0, d1
10000bd88: fd41ed01    	ldr	d1, [x8, #0x3d8]
10000bd8c: d2e80be9    	mov	x9, #0x405f000000000000 ; =4638426141214900224
10000bd90: 9e670122    	fmov	d2, x9
10000bd94: 1e620821    	fmul	d1, d1, d2
10000bd98: 1e612800    	fadd	d0, d0, d1
10000bd9c: fd41f101    	ldr	d1, [x8, #0x3e0]
10000bda0: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000bda4: f2e80be9    	movk	x9, #0x405f, lsl #48
10000bda8: 9e670122    	fmov	d2, x9
10000bdac: 1e620821    	fmul	d1, d1, d2
10000bdb0: 1e612800    	fadd	d0, d0, d1
10000bdb4: fd41f501    	ldr	d1, [x8, #0x3e8]
10000bdb8: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000bdbc: f2e80be9    	movk	x9, #0x405f, lsl #48
10000bdc0: 9e670122    	fmov	d2, x9
10000bdc4: 1e620821    	fmul	d1, d1, d2
10000bdc8: 1e612800    	fadd	d0, d0, d1
10000bdcc: fd41f901    	ldr	d1, [x8, #0x3f0]
10000bdd0: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000bdd4: f2e80be9    	movk	x9, #0x405f, lsl #48
10000bdd8: 9e670122    	fmov	d2, x9
10000bddc: 1e620821    	fmul	d1, d1, d2
10000bde0: 1e612800    	fadd	d0, d0, d1
10000bde4: fd41fd01    	ldr	d1, [x8, #0x3f8]
10000bde8: d2e80c09    	mov	x9, #0x4060000000000000 ; =4638707616191610880
10000bdec: 9e670122    	fmov	d2, x9
10000bdf0: 1e620821    	fmul	d1, d1, d2
10000bdf4: 1e612800    	fadd	d0, d0, d1
10000bdf8: fd420101    	ldr	d1, [x8, #0x400]
10000bdfc: d2c40009    	mov	x9, #0x200000000000     ; =35184372088832
10000be00: f2e80c09    	movk	x9, #0x4060, lsl #48
10000be04: 9e670122    	fmov	d2, x9
10000be08: 1e620821    	fmul	d1, d1, d2
10000be0c: 1e612800    	fadd	d0, d0, d1
10000be10: fd420501    	ldr	d1, [x8, #0x408]
10000be14: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000be18: f2e80c09    	movk	x9, #0x4060, lsl #48
10000be1c: 9e670122    	fmov	d2, x9
10000be20: 1e620821    	fmul	d1, d1, d2
10000be24: 1e612800    	fadd	d0, d0, d1
10000be28: fd420901    	ldr	d1, [x8, #0x410]
10000be2c: d2cc0009    	mov	x9, #0x600000000000     ; =105553116266496
10000be30: f2e80c09    	movk	x9, #0x4060, lsl #48
10000be34: 9e670122    	fmov	d2, x9
10000be38: 1e620821    	fmul	d1, d1, d2
10000be3c: 1e612800    	fadd	d0, d0, d1
10000be40: fd420d01    	ldr	d1, [x8, #0x418]
10000be44: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000be48: f2e80c09    	movk	x9, #0x4060, lsl #48
10000be4c: 9e670122    	fmov	d2, x9
10000be50: 1e620821    	fmul	d1, d1, d2
10000be54: 1e612800    	fadd	d0, d0, d1
10000be58: 3dc10901    	ldr	q1, [x8, #0x420]
10000be5c: 90000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000be60: 3dc3a522    	ldr	q2, [x9, #0xe90]
10000be64: 6e62dc21    	fmul.2d	v1, v1, v2
10000be68: 1e612800    	fadd	d0, d0, d1
10000be6c: 5e180421    	mov	d1, v1[1]
10000be70: 1e612800    	fadd	d0, d0, d1
10000be74: 3dc10d01    	ldr	q1, [x8, #0x430]
10000be78: 90000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000be7c: 3dc3a922    	ldr	q2, [x9, #0xea0]
10000be80: 6e62dc21    	fmul.2d	v1, v1, v2
10000be84: 1e612800    	fadd	d0, d0, d1
10000be88: 5e180421    	mov	d1, v1[1]
10000be8c: 1e612800    	fadd	d0, d0, d1
10000be90: 3dc11101    	ldr	q1, [x8, #0x440]
10000be94: 90000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000be98: 3dc3ad22    	ldr	q2, [x9, #0xeb0]
10000be9c: 6e62dc21    	fmul.2d	v1, v1, v2
10000bea0: 1e612800    	fadd	d0, d0, d1
10000bea4: 5e180421    	mov	d1, v1[1]
10000bea8: 1e612800    	fadd	d0, d0, d1
10000beac: 3dc11501    	ldr	q1, [x8, #0x450]
10000beb0: 90000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000beb4: 3dc3b122    	ldr	q2, [x9, #0xec0]
10000beb8: 6e62dc21    	fmul.2d	v1, v1, v2
10000bebc: 1e612800    	fadd	d0, d0, d1
10000bec0: 5e180421    	mov	d1, v1[1]
10000bec4: 1e612800    	fadd	d0, d0, d1
10000bec8: 3dc11901    	ldr	q1, [x8, #0x460]
10000becc: 90000029    	adrp	x9, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000bed0: 3dc3b522    	ldr	q2, [x9, #0xed0]
10000bed4: 6e62dc21    	fmul.2d	v1, v1, v2
10000bed8: 1e612800    	fadd	d0, d0, d1
10000bedc: 5e180421    	mov	d1, v1[1]
10000bee0: 1e612800    	fadd	d0, d0, d1
10000bee4: 3dc11d01    	ldr	q1, [x8, #0x470]
10000bee8: 90000028    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000beec: 3dc3b902    	ldr	q2, [x8, #0xee0]
10000bef0: 6e62dc21    	fmul.2d	v1, v1, v2
10000bef4: 1e612800    	fadd	d0, d0, d1
10000bef8: 5e180421    	mov	d1, v1[1]
10000befc: 1e612800    	fadd	d0, d0, d1
10000bf00: a8c17bfd    	ldp	x29, x30, [sp], #0x10
10000bf04: d65f03c0    	ret

000000010000bf08 <_bench_primitives.checksumPair>:
10000bf08: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
10000bf0c: 910003fd    	mov	x29, sp
10000bf10: b0000088    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000bf14: 91184108    	add	x8, x8, #0x610
10000bf18: 6d400500    	ldp	d0, d1, [x8]
10000bf1c: 1e655002    	fmov	d2, #13.00000000
10000bf20: 1e620821    	fmul	d1, d1, d2
10000bf24: 1e612800    	fadd	d0, d0, d1
10000bf28: a8c17bfd    	ldp	x29, x30, [sp], #0x10
10000bf2c: d65f03c0    	ret

000000010000bf30 <_Io.Writer.writeAll>:
10000bf30: b4000761    	cbz	x1, 0x10000c01c <_Io.Writer.writeAll+0xec>
10000bf34: d101c3ff    	sub	sp, sp, #0x70
10000bf38: a90267fa    	stp	x26, x25, [sp, #0x20]
10000bf3c: a9035ff8    	stp	x24, x23, [sp, #0x30]
10000bf40: a90457f6    	stp	x22, x21, [sp, #0x40]
10000bf44: a9054ff4    	stp	x20, x19, [sp, #0x50]
10000bf48: a9067bfd    	stp	x29, x30, [sp, #0x60]
10000bf4c: 910183fd    	add	x29, sp, #0x60
10000bf50: aa0103f3    	mov	x19, x1
10000bf54: aa0003f4    	mov	x20, x0
10000bf58: d2800017    	mov	x23, #0x0               ; =0
10000bf5c: b0000088    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000bf60: f940bd08    	ldr	x8, [x8, #0x178]
10000bf64: b0000098    	adrp	x24, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000bf68: b0000095    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000bf6c: 910582b5    	add	x21, x21, #0x160
10000bf70: b0000099    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000bf74: 9105a339    	add	x25, x25, #0x168
10000bf78: 8b170281    	add	x1, x20, x23
10000bf7c: cb170276    	sub	x22, x19, x23
10000bf80: 8b160109    	add	x9, x8, x22
10000bf84: f940bb0a    	ldr	x10, [x24, #0x170]
10000bf88: eb0a013f    	cmp	x9, x10
10000bf8c: 54000188    	b.hi	0x10000bfbc <_Io.Writer.writeAll+0x8c>
10000bf90: f9400329    	ldr	x9, [x25]
10000bf94: 8b080120    	add	x0, x9, x8
10000bf98: aa1603e2    	mov	x2, x22
10000bf9c: 94000bb3    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
10000bfa0: f9400b28    	ldr	x8, [x25, #0x10]
10000bfa4: 8b160108    	add	x8, x8, x22
10000bfa8: f9000b28    	str	x8, [x25, #0x10]
10000bfac: 8b1702d7    	add	x23, x22, x23
10000bfb0: eb1302ff    	cmp	x23, x19
10000bfb4: 54fffe23    	b.lo	0x10000bf78 <_Io.Writer.writeAll+0x48>
10000bfb8: 14000011    	b	0x10000bffc <_Io.Writer.writeAll+0xcc>
10000bfbc: f94002a8    	ldr	x8, [x21]
10000bfc0: f9400109    	ldr	x9, [x8]
10000bfc4: a9005be1    	stp	x1, x22, [sp]
10000bfc8: 910043e8    	add	x8, sp, #0x10
10000bfcc: 910003e1    	mov	x1, sp
10000bfd0: aa1503e0    	mov	x0, x21
10000bfd4: 52800022    	mov	w2, #0x1                ; =1
10000bfd8: 52800023    	mov	w3, #0x1                ; =1
10000bfdc: d63f0120    	blr	x9
10000bfe0: 794033e0    	ldrh	w0, [sp, #0x18]
10000bfe4: 350000e0    	cbnz	w0, 0x10000c000 <_Io.Writer.writeAll+0xd0>
10000bfe8: f9400bf6    	ldr	x22, [sp, #0x10]
10000bfec: f9400ea8    	ldr	x8, [x21, #0x18]
10000bff0: 8b1702d7    	add	x23, x22, x23
10000bff4: eb1302ff    	cmp	x23, x19
10000bff8: 54fffc03    	b.lo	0x10000bf78 <_Io.Writer.writeAll+0x48>
10000bffc: 52800000    	mov	w0, #0x0                ; =0
10000c000: a9467bfd    	ldp	x29, x30, [sp, #0x60]
10000c004: a9454ff4    	ldp	x20, x19, [sp, #0x50]
10000c008: a94457f6    	ldp	x22, x21, [sp, #0x40]
10000c00c: a9435ff8    	ldp	x24, x23, [sp, #0x30]
10000c010: a94267fa    	ldp	x26, x25, [sp, #0x20]
10000c014: 9101c3ff    	add	sp, sp, #0x70
10000c018: d65f03c0    	ret
10000c01c: 52800000    	mov	w0, #0x0                ; =0
10000c020: d65f03c0    	ret

000000010000c024 <_Io.Writer.printValue__anon_4310>:
10000c024: a9ba6ffc    	stp	x28, x27, [sp, #-0x60]!
10000c028: a90167fa    	stp	x26, x25, [sp, #0x10]
10000c02c: a9025ff8    	stp	x24, x23, [sp, #0x20]
10000c030: a90357f6    	stp	x22, x21, [sp, #0x30]
10000c034: a9044ff4    	stp	x20, x19, [sp, #0x40]
10000c038: a9057bfd    	stp	x29, x30, [sp, #0x50]
10000c03c: 910143fd    	add	x29, sp, #0x50
10000c040: d106c3ff    	sub	sp, sp, #0x1b0
10000c044: d10203b9    	sub	x25, x29, #0x80
10000c048: f9400014    	ldr	x20, [x0]
10000c04c: 39402018    	ldrb	w24, [x0, #0x8]
10000c050: f9400816    	ldr	x22, [x0, #0x10]
10000c054: 39406017    	ldrb	w23, [x0, #0x18]
10000c058: 39408008    	ldrb	w8, [x0, #0x20]
10000c05c: 39408413    	ldrb	w19, [x0, #0x21]
10000c060: 390063ff    	strb	wzr, [sp, #0x18]
10000c064: 12000508    	and	w8, w8, #0x3
10000c068: 39005be8    	strb	w8, [sp, #0x16]
10000c06c: 72000bff    	tst	wzr, #0x7
10000c070: 1a9f17e8    	cset	w8, eq
10000c074: 381783a8    	sturb	w8, [x29, #-0x88]
10000c078: 9e660008    	fmov	x8, d0
10000c07c: d374f90c    	ubfx	x12, x8, #52, #11
10000c080: 910077e9    	add	x9, sp, #0x1d
10000c084: 91000535    	add	x21, x9, #0x1
10000c088: f240cd11    	ands	x17, x8, #0xfffffffffffff
10000c08c: 540003a1    	b.ne	0x10000c100 <_Io.Writer.printValue__anon_4310+0xdc>
10000c090: 3500038c    	cbnz	w12, 0x10000c100 <_Io.Writer.printValue__anon_4310+0xdc>
10000c094: f900033f    	str	xzr, [x25]
10000c098: b9000b3f    	str	wzr, [x25, #0x8]
10000c09c: f100011f    	cmp	x8, #0x0
10000c0a0: 1a9fa7e8    	cset	w8, lt
10000c0a4: 3818c3a8    	sturb	w8, [x29, #-0x74]
10000c0a8: 385783a8    	ldurb	w8, [x29, #-0x88]
10000c0ac: 360028e8    	tbz	w8, #0x0, 0x10000c5c8 <_Io.Writer.printValue__anon_4310+0x5a4>
10000c0b0: 3dc00320    	ldr	q0, [x25]
10000c0b4: 3d800720    	str	q0, [x25, #0x10]
10000c0b8: b9401b28    	ldr	w8, [x25, #0x18]
10000c0bc: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000c0c0: 6b09011f    	cmp	w8, w9
10000c0c4: 540028e0    	b.eq	0x10000c5e0 <_Io.Writer.printValue__anon_4310+0x5bc>
10000c0c8: 340000d8    	cbz	w24, 0x10000c0e0 <_Io.Writer.printValue__anon_4310+0xbc>
10000c0cc: d101c3a0    	sub	x0, x29, #0x70
10000c0d0: d10203a1    	sub	x1, x29, #0x80
10000c0d4: 52800002    	mov	w2, #0x0                ; =0
10000c0d8: aa1403e3    	mov	x3, x20
10000c0dc: 9400077a    	bl	0x10000dec4 <_fmt.float.round__anon_5288>
10000c0e0: f9400b3a    	ldr	x26, [x25, #0x10]
10000c0e4: 92b207e8    	mov	x8, #-0x903f0001        ; =-2420047873
10000c0e8: f2d0de48    	movk	x8, #0x86f2, lsl #32
10000c0ec: f2e00468    	movk	x8, #0x23, lsl #48
10000c0f0: eb08035f    	cmp	x26, x8
10000c0f4: 54000ae9    	b.ls	0x10000c250 <_Io.Writer.printValue__anon_4310+0x22c>
10000c0f8: 5280023b    	mov	w27, #0x11              ; =17
10000c0fc: 1400021d    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c100: 711ffd9f    	cmp	w12, #0x7ff
10000c104: 54000141    	b.ne	0x10000c12c <_Io.Writer.printValue__anon_4310+0x108>
10000c108: f9000331    	str	x17, [x25]
10000c10c: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000c110: b9000b29    	str	w9, [x25, #0x8]
10000c114: f100011f    	cmp	x8, #0x0
10000c118: 1a9fa7e8    	cset	w8, lt
10000c11c: 3818c3a8    	sturb	w8, [x29, #-0x74]
10000c120: 385783a8    	ldurb	w8, [x29, #-0x88]
10000c124: 3707fc68    	tbnz	w8, #0x0, 0x10000c0b0 <_Io.Writer.printValue__anon_4310+0x8c>
10000c128: 14000128    	b	0x10000c5c8 <_Io.Writer.printValue__anon_4310+0x5a4>
10000c12c: d299a36b    	mov	x11, #0xcd1b            ; =52507
10000c130: f2af096b    	movk	x11, #0x784b, lsl #16
10000c134: f2d2934b    	movk	x11, #0x949a, lsl #32
10000c138: d37ef630    	lsl	x16, x17, #2
10000c13c: 340009ac    	cbz	w12, 0x10000c270 <_Io.Writer.printValue__anon_4310+0x24c>
10000c140: 5110d589    	sub	w9, w12, #0x435
10000c144: f240011f    	tst	x8, #0x1
10000c148: 1a9f17ea    	cset	w10, eq
10000c14c: d2e0080f    	mov	x15, #0x40000000000000  ; =18014398509481984
10000c150: b37ece2f    	bfi	x15, x17, #2, #52
10000c154: f100023f    	cmp	x17, #0x0
10000c158: 1a9f07ee    	cset	w14, ne
10000c15c: 7110d19f    	cmp	w12, #0x434
10000c160: 54000929    	b.ls	0x10000c284 <_Io.Writer.printValue__anon_4310+0x260>
10000c164: d280004e    	mov	x14, #0x2               ; =2
10000c168: f2e0080e    	movk	x14, #0x40, lsl #48
10000c16c: d29f79ed    	mov	x13, #0xfbcf            ; =64463
10000c170: f2b3508d    	movk	x13, #0x9a84, lsl #16
10000c174: f2d3440d    	movk	x13, #0x9a20, lsl #32
10000c178: 9b0d7d2d    	mul	x13, x9, x13
10000c17c: d371fdad    	lsr	x13, x13, #49
10000c180: 71000d3f    	cmp	w9, #0x3
10000c184: 1a9f97e9    	cset	w9, hi
10000c188: 4b0901a9    	sub	w9, w13, w9
10000c18c: 4b0c012c    	sub	w12, w9, w12
10000c190: 9b0b7d2b    	mul	x11, x9, x11
10000c194: d36efd6b    	lsr	x11, x11, #46
10000c198: 0b0b018b    	add	w11, w12, w11
10000c19c: 1112c96b    	add	w11, w11, #0x4b2
10000c1a0: 7102017f    	cmp	w11, #0x80
10000c1a4: 54001122    	b.hs	0x10000c3c8 <_Io.Writer.printValue__anon_4310+0x3a4>
10000c1a8: 9000002c    	adrp	x12, 0x100010000 <___anon_4031+0x22>
10000c1ac: 9102618c    	add	x12, x12, #0x98
10000c1b0: 8b29518c    	add	x12, x12, w9, uxtw #4
10000c1b4: a9400580    	ldp	x0, x1, [x12]
10000c1b8: f100023f    	cmp	x17, #0x0
10000c1bc: 1a9f07f1    	cset	w17, ne
10000c1c0: 9bcf7c2c    	umulh	x12, x1, x15
10000c1c4: 9b0f7c2d    	mul	x13, x1, x15
10000c1c8: 9bcf7c02    	umulh	x2, x0, x15
10000c1cc: ab0d004d    	adds	x13, x2, x13
10000c1d0: 9a8c358c    	cinc	x12, x12, hs
10000c1d4: 9acb25ad    	lsr	x13, x13, x11
10000c1d8: d37ff98c    	lsl	x12, x12, #1
10000c1dc: 92401562    	and	x2, x11, #0x3f
10000c1e0: d2401442    	eor	x2, x2, #0x3f
10000c1e4: 9ac2218c    	lsl	x12, x12, x2
10000c1e8: aa0d018c    	orr	x12, x12, x13
10000c1ec: aa0e020e    	orr	x14, x16, x14
10000c1f0: 9bce7c2d    	umulh	x13, x1, x14
10000c1f4: 9b0e7c23    	mul	x3, x1, x14
10000c1f8: 9bce7c04    	umulh	x4, x0, x14
10000c1fc: ab030083    	adds	x3, x4, x3
10000c200: 9a8d35ad    	cinc	x13, x13, hs
10000c204: 9acb2463    	lsr	x3, x3, x11
10000c208: d37ff9ad    	lsl	x13, x13, #1
10000c20c: 9ac221ad    	lsl	x13, x13, x2
10000c210: aa0301ad    	orr	x13, x13, x3
10000c214: 92fff803    	mov	x3, #0x3fffffffffffff   ; =18014398509481983
10000c218: cb110210    	sub	x16, x16, x17
10000c21c: 8b030210    	add	x16, x16, x3
10000c220: 9bd07c31    	umulh	x17, x1, x16
10000c224: 9b107c21    	mul	x1, x1, x16
10000c228: 9bd07c00    	umulh	x0, x0, x16
10000c22c: ab010000    	adds	x0, x0, x1
10000c230: 9a913631    	cinc	x17, x17, hs
10000c234: 9acb240b    	lsr	x11, x0, x11
10000c238: d37ffa31    	lsl	x17, x17, #1
10000c23c: 9ac22231    	lsl	x17, x17, x2
10000c240: aa0b022b    	orr	x11, x17, x11
10000c244: 7100593f    	cmp	w9, #0x16
10000c248: 54000d63    	b.lo	0x10000c3f4 <_Io.Writer.printValue__anon_4310+0x3d0>
10000c24c: 14000083    	b	0x10000c458 <_Io.Writer.printValue__anon_4310+0x434>
10000c250: d28fffe8    	mov	x8, #0x7fff             ; =32767
10000c254: f2b498c8    	movk	x8, #0xa4c6, lsl #16
10000c258: f2d1afc8    	movk	x8, #0x8d7e, lsl #32
10000c25c: f2e00068    	movk	x8, #0x3, lsl #48
10000c260: eb08035f    	cmp	x26, x8
10000c264: 54000a49    	b.ls	0x10000c3ac <_Io.Writer.printValue__anon_4310+0x388>
10000c268: 5280021b    	mov	w27, #0x10              ; =16
10000c26c: 140001c1    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c270: f240011f    	tst	x8, #0x1
10000c274: 1a9f17ea    	cset	w10, eq
10000c278: 12808669    	mov	w9, #-0x434             ; =-1076
10000c27c: 5280002e    	mov	w14, #0x1               ; =1
10000c280: aa1003ef    	mov	x15, x16
10000c284: 4b0903ec    	neg	w12, w9
10000c288: d290430d    	mov	x13, #0x8218            ; =33304
10000c28c: f2b657ad    	movk	x13, #0xb2bd, lsl #16
10000c290: f2d65ded    	movk	x13, #0xb2ef, lsl #32
10000c294: 9b0d7d8d    	mul	x13, x12, x13
10000c298: d370fdad    	lsr	x13, x13, #48
10000c29c: 3100053f    	cmn	w9, #0x1
10000c2a0: 1a9f07f0    	cset	w16, ne
10000c2a4: 4b1001b0    	sub	w16, w13, w16
10000c2a8: 0b090209    	add	w9, w16, w9
10000c2ac: 4b10018c    	sub	w12, w12, w16
10000c2b0: 9b0b7d8b    	mul	x11, x12, x11
10000c2b4: d36efd6b    	lsr	x11, x11, #46
10000c2b8: 4b0b020b    	sub	w11, w16, w11
10000c2bc: 1101f16b    	add	w11, w11, #0x7c
10000c2c0: 7101fd7f    	cmp	w11, #0x7f
10000c2c4: 54000608    	b.hi	0x10000c384 <_Io.Writer.printValue__anon_4310+0x360>
10000c2c8: b000002d    	adrp	x13, 0x100011000 <___anon_4979+0xf98>
10000c2cc: 9117e1ad    	add	x13, x13, #0x5f8
10000c2d0: 8b2c51ac    	add	x12, x13, w12, uxtw #4
10000c2d4: a9400191    	ldp	x17, x0, [x12]
10000c2d8: 9bcf7c0c    	umulh	x12, x0, x15
10000c2dc: 9b0f7c0d    	mul	x13, x0, x15
10000c2e0: 9bcf7e21    	umulh	x1, x17, x15
10000c2e4: ab0d002d    	adds	x13, x1, x13
10000c2e8: 9a8c358c    	cinc	x12, x12, hs
10000c2ec: 9acb25ad    	lsr	x13, x13, x11
10000c2f0: d37ff98c    	lsl	x12, x12, #1
10000c2f4: 92401561    	and	x1, x11, #0x3f
10000c2f8: d2401421    	eor	x1, x1, #0x3f
10000c2fc: 9ac1218c    	lsl	x12, x12, x1
10000c300: aa0d018c    	orr	x12, x12, x13
10000c304: b27f01ed    	orr	x13, x15, #0x2
10000c308: 9bcd7c02    	umulh	x2, x0, x13
10000c30c: 9b0d7c03    	mul	x3, x0, x13
10000c310: 9bcd7e2d    	umulh	x13, x17, x13
10000c314: ab0301ad    	adds	x13, x13, x3
10000c318: 9a823442    	cinc	x2, x2, hs
10000c31c: 9acb25ad    	lsr	x13, x13, x11
10000c320: d37ff842    	lsl	x2, x2, #1
10000c324: 9ac12042    	lsl	x2, x2, x1
10000c328: aa0d004d    	orr	x13, x2, x13
10000c32c: 2a0e03e2    	mov	w2, w14
10000c330: aa2203e2    	mvn	x2, x2
10000c334: 8b0f0042    	add	x2, x2, x15
10000c338: 9bc27c03    	umulh	x3, x0, x2
10000c33c: 9b027c00    	mul	x0, x0, x2
10000c340: 9bc27e31    	umulh	x17, x17, x2
10000c344: ab000231    	adds	x17, x17, x0
10000c348: 9a833460    	cinc	x0, x3, hs
10000c34c: 9acb262b    	lsr	x11, x17, x11
10000c350: d37ff811    	lsl	x17, x0, #1
10000c354: 9ac12231    	lsl	x17, x17, x1
10000c358: aa0b022b    	orr	x11, x17, x11
10000c35c: 71000a1f    	cmp	w16, #0x2
10000c360: 540001c3    	b.lo	0x10000c398 <_Io.Writer.printValue__anon_4310+0x374>
10000c364: 7100fa1f    	cmp	w16, #0x3e
10000c368: 54000788    	b.hi	0x10000c458 <_Io.Writer.printValue__anon_4310+0x434>
10000c36c: 5280000e    	mov	w14, #0x0               ; =0
10000c370: 92800011    	mov	x17, #-0x1              ; =-1
10000c374: 9ad02230    	lsl	x16, x17, x16
10000c378: ea3001ff    	bics	xzr, x15, x16
10000c37c: 1a9f17ef    	cset	w15, eq
10000c380: 14000038    	b	0x10000c460 <_Io.Writer.printValue__anon_4310+0x43c>
10000c384: d280000d    	mov	x13, #0x0               ; =0
10000c388: d280000c    	mov	x12, #0x0               ; =0
10000c38c: d280000b    	mov	x11, #0x0               ; =0
10000c390: 71000a1f    	cmp	w16, #0x2
10000c394: 54fffe82    	b.hs	0x10000c364 <_Io.Writer.printValue__anon_4310+0x340>
10000c398: 0a0a01ce    	and	w14, w14, w10
10000c39c: 5200014f    	eor	w15, w10, #0x1
10000c3a0: cb0f01ad    	sub	x13, x13, x15
10000c3a4: 5280002f    	mov	w15, #0x1               ; =1
10000c3a8: 1400002e    	b	0x10000c460 <_Io.Writer.printValue__anon_4310+0x43c>
10000c3ac: d287ffe8    	mov	x8, #0x3fff             ; =16383
10000c3b0: f2a20f48    	movk	x8, #0x107a, lsl #16
10000c3b4: f2cb5e68    	movk	x8, #0x5af3, lsl #32
10000c3b8: eb08035f    	cmp	x26, x8
10000c3bc: 54001769    	b.ls	0x10000c6a8 <_Io.Writer.printValue__anon_4310+0x684>
10000c3c0: 528001fb    	mov	w27, #0xf               ; =15
10000c3c4: 1400016b    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c3c8: d280000d    	mov	x13, #0x0               ; =0
10000c3cc: d280000c    	mov	x12, #0x0               ; =0
10000c3d0: d280000b    	mov	x11, #0x0               ; =0
10000c3d4: f100023f    	cmp	x17, #0x0
10000c3d8: 1a9f07f1    	cset	w17, ne
10000c3dc: aa0e020e    	orr	x14, x16, x14
10000c3e0: 92fff800    	mov	x0, #0x3fffffffffffff   ; =18014398509481983
10000c3e4: cb110210    	sub	x16, x16, x17
10000c3e8: 8b000210    	add	x16, x16, x0
10000c3ec: 7100593f    	cmp	w9, #0x16
10000c3f0: 54000342    	b.hs	0x10000c458 <_Io.Writer.printValue__anon_4310+0x434>
10000c3f4: b202e7f1    	mov	x17, #-0x3333333333333334 ; =-3689348814741910324
10000c3f8: f29999b1    	movk	x17, #0xcccd
10000c3fc: 9b117de0    	mul	x0, x15, x17
10000c400: b200e7e1    	mov	x1, #0x3333333333333333 ; =3689348814741910323
10000c404: eb01001f    	cmp	x0, x1
10000c408: 54001889    	b.ls	0x10000c718 <_Io.Writer.printValue__anon_4310+0x6f4>
10000c40c: 37001a48    	tbnz	w8, #0x0, 0x10000c754 <_Io.Writer.printValue__anon_4310+0x730>
10000c410: 5280000a    	mov	w10, #0x0               ; =0
10000c414: b202e7ee    	mov	x14, #-0x3333333333333334 ; =-3689348814741910324
10000c418: f29999ae    	movk	x14, #0xcccd
10000c41c: 9bce7e0f    	umulh	x15, x16, x14
10000c420: d342fdef    	lsr	x15, x15, #2
10000c424: 8b0f09f1    	add	x17, x15, x15, lsl #2
10000c428: eb11021f    	cmp	x16, x17
10000c42c: 540000c1    	b.ne	0x10000c444 <_Io.Writer.printValue__anon_4310+0x420>
10000c430: 1100054a    	add	w10, w10, #0x1
10000c434: f100121f    	cmp	x16, #0x4
10000c438: aa0f03f0    	mov	x16, x15
10000c43c: 54ffff08    	b.hi	0x10000c41c <_Io.Writer.printValue__anon_4310+0x3f8>
10000c440: 5280000a    	mov	w10, #0x0               ; =0
10000c444: 5280000f    	mov	w15, #0x0               ; =0
10000c448: 6b09015f    	cmp	w10, w9
10000c44c: 1a9f37ee    	cset	w14, hs
10000c450: 5280002a    	mov	w10, #0x1               ; =1
10000c454: 14000003    	b	0x10000c460 <_Io.Writer.printValue__anon_4310+0x43c>
10000c458: 5280000f    	mov	w15, #0x0               ; =0
10000c45c: 5280000e    	mov	w14, #0x0               ; =0
10000c460: b202e7f1    	mov	x17, #-0x3333333333333334 ; =-3689348814741910324
10000c464: f29999b1    	movk	x17, #0xcccd
10000c468: 9bd17dad    	umulh	x13, x13, x17
10000c46c: d343fda0    	lsr	x0, x13, #3
10000c470: 9bd17d6d    	umulh	x13, x11, x17
10000c474: d343fda3    	lsr	x3, x13, #3
10000c478: eb03001f    	cmp	x0, x3
10000c47c: 540003c9    	b.ls	0x10000c4f4 <_Io.Writer.printValue__anon_4310+0x4d0>
10000c480: 5280000d    	mov	w13, #0x0               ; =0
10000c484: 52800010    	mov	w16, #0x0               ; =0
10000c488: b201e7e1    	mov	x1, #-0x6666666666666667 ; =-7378697629483820647
10000c48c: d2410821    	eor	x1, x1, #0x8000000000000003
10000c490: 52800142    	mov	w2, #0xa                ; =10
10000c494: aa0c03e4    	mov	x4, x12
10000c498: 9b117d6c    	mul	x12, x11, x17
10000c49c: 93cc058c    	ror	x12, x12, #0x1
10000c4a0: eb01019f    	cmp	x12, x1
10000c4a4: 1a9f27ec    	cset	w12, lo
10000c4a8: 720001df    	tst	w14, #0x1
10000c4ac: 1a9f118e    	csel	w14, w12, wzr, ne
10000c4b0: aa0303eb    	mov	x11, x3
10000c4b4: 72001e1f    	tst	w16, #0xff
10000c4b8: 1a9f17ec    	cset	w12, eq
10000c4bc: 0a0c01ef    	and	w15, w15, w12
10000c4c0: 9bd17c8c    	umulh	x12, x4, x17
10000c4c4: d343fd8c    	lsr	x12, x12, #3
10000c4c8: 1b029190    	msub	w16, w12, w2, w4
10000c4cc: 110005ad    	add	w13, w13, #0x1
10000c4d0: 9bd17c00    	umulh	x0, x0, x17
10000c4d4: d343fc00    	lsr	x0, x0, #3
10000c4d8: 9bd17c63    	umulh	x3, x3, x17
10000c4dc: d343fc63    	lsr	x3, x3, #3
10000c4e0: aa0c03e4    	mov	x4, x12
10000c4e4: eb03001f    	cmp	x0, x3
10000c4e8: 54fffd88    	b.hi	0x10000c498 <_Io.Writer.printValue__anon_4310+0x474>
10000c4ec: 350000ae    	cbnz	w14, 0x10000c500 <_Io.Writer.printValue__anon_4310+0x4dc>
10000c4f0: 1400001d    	b	0x10000c564 <_Io.Writer.printValue__anon_4310+0x540>
10000c4f4: 52800010    	mov	w16, #0x0               ; =0
10000c4f8: 5280000d    	mov	w13, #0x0               ; =0
10000c4fc: 3400034e    	cbz	w14, 0x10000c564 <_Io.Writer.printValue__anon_4310+0x540>
10000c500: 9bd17d71    	umulh	x17, x11, x17
10000c504: d343fe31    	lsr	x17, x17, #3
10000c508: 52800140    	mov	w0, #0xa                ; =10
10000c50c: 9b00ae31    	msub	x17, x17, x0, x11
10000c510: b50002b1    	cbnz	x17, 0x10000c564 <_Io.Writer.printValue__anon_4310+0x540>
10000c514: b202e7e0    	mov	x0, #-0x3333333333333334 ; =-3689348814741910324
10000c518: f29999a0    	movk	x0, #0xcccd
10000c51c: 52800141    	mov	w1, #0xa                ; =10
10000c520: b201e7e2    	mov	x2, #-0x6666666666666667 ; =-7378697629483820647
10000c524: d2410842    	eor	x2, x2, #0x8000000000000003
10000c528: 72001e1f    	tst	w16, #0xff
10000c52c: 1a9f17f0    	cset	w16, eq
10000c530: 0a1001ef    	and	w15, w15, w16
10000c534: 9bc07d90    	umulh	x16, x12, x0
10000c538: d343fe11    	lsr	x17, x16, #3
10000c53c: 1b01b230    	msub	w16, w17, w1, w12
10000c540: 9bc07d6b    	umulh	x11, x11, x0
10000c544: d343fd6b    	lsr	x11, x11, #3
10000c548: 110005ad    	add	w13, w13, #0x1
10000c54c: 9b007d6c    	mul	x12, x11, x0
10000c550: 93cc0583    	ror	x3, x12, #0x1
10000c554: aa1103ec    	mov	x12, x17
10000c558: eb02007f    	cmp	x3, x2
10000c55c: 54fffe63    	b.lo	0x10000c528 <_Io.Writer.printValue__anon_4310+0x504>
10000c560: 14000002    	b	0x10000c568 <_Io.Writer.printValue__anon_4310+0x544>
10000c564: aa0c03f1    	mov	x17, x12
10000c568: 12001e0c    	and	w12, w16, #0xff
10000c56c: 7100159f    	cmp	w12, #0x5
10000c570: 1a9f17ec    	cset	w12, eq
10000c574: f240023f    	tst	x17, #0x1
10000c578: 52800080    	mov	w0, #0x4                ; =4
10000c57c: 1a800400    	cinc	w0, w0, ne
10000c580: 6a0c01ff    	tst	w15, w12
10000c584: 1a90100c    	csel	w12, w0, w16, ne
10000c588: 12001d8c    	and	w12, w12, #0xff
10000c58c: eb0b023f    	cmp	x17, x11
10000c590: 1a9f17eb    	cset	w11, eq
10000c594: 0a0e014a    	and	w10, w10, w14
10000c598: 7100119f    	cmp	w12, #0x4
10000c59c: 0a2a016a    	bic	w10, w11, w10
10000c5a0: 1a9f954a    	csinc	w10, w10, wzr, ls
10000c5a4: 8b0a022a    	add	x10, x17, x10
10000c5a8: f900032a    	str	x10, [x25]
10000c5ac: 0b0901a9    	add	w9, w13, w9
10000c5b0: b9000b29    	str	w9, [x25, #0x8]
10000c5b4: f100011f    	cmp	x8, #0x0
10000c5b8: 1a9fa7e8    	cset	w8, lt
10000c5bc: 3818c3a8    	sturb	w8, [x29, #-0x74]
10000c5c0: 385783a8    	ldurb	w8, [x29, #-0x88]
10000c5c4: 3707d768    	tbnz	w8, #0x0, 0x10000c0b0 <_Io.Writer.printValue__anon_4310+0x8c>
10000c5c8: 3dc00320    	ldr	q0, [x25]
10000c5cc: 3d800720    	str	q0, [x25, #0x10]
10000c5d0: b9401b28    	ldr	w8, [x25, #0x18]
10000c5d4: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000c5d8: 6b09011f    	cmp	w8, w9
10000c5dc: 540001a1    	b.ne	0x10000c610 <_Io.Writer.printValue__anon_4310+0x5ec>
10000c5e0: 3859c3a8    	ldurb	w8, [x29, #-0x64]
10000c5e4: 36000068    	tbz	w8, #0x0, 0x10000c5f0 <_Io.Writer.printValue__anon_4310+0x5cc>
10000c5e8: 528005a9    	mov	w9, #0x2d               ; =45
10000c5ec: 390077e9    	strb	w9, [sp, #0x1d]
10000c5f0: f9400b2a    	ldr	x10, [x25, #0x10]
10000c5f4: 910077e9    	add	x9, sp, #0x1d
10000c5f8: 8b080129    	add	x9, x9, x8
10000c5fc: b400026a    	cbz	x10, 0x10000c648 <_Io.Writer.printValue__anon_4310+0x624>
10000c600: 52800dca    	mov	w10, #0x6e              ; =110
10000c604: 3900092a    	strb	w10, [x9, #0x2]
10000c608: 528c2dca    	mov	w10, #0x616e            ; =24942
10000c60c: 14000012    	b	0x10000c654 <_Io.Writer.printValue__anon_4310+0x630>
10000c610: 340000d8    	cbz	w24, 0x10000c628 <_Io.Writer.printValue__anon_4310+0x604>
10000c614: d101c3a0    	sub	x0, x29, #0x70
10000c618: d10203a1    	sub	x1, x29, #0x80
10000c61c: 52800022    	mov	w2, #0x1                ; =1
10000c620: aa1403e3    	mov	x3, x20
10000c624: 94000628    	bl	0x10000dec4 <_fmt.float.round__anon_5288>
10000c628: f9400b28    	ldr	x8, [x25, #0x10]
10000c62c: 92b207e9    	mov	x9, #-0x903f0001        ; =-2420047873
10000c630: f2d0de49    	movk	x9, #0x86f2, lsl #32
10000c634: f2e00469    	movk	x9, #0x23, lsl #48
10000c638: eb09011f    	cmp	x8, x9
10000c63c: 54000189    	b.ls	0x10000c66c <_Io.Writer.printValue__anon_4310+0x648>
10000c640: 5280023b    	mov	w27, #0x11              ; =17
10000c644: 140002c9    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c648: 52800cca    	mov	w10, #0x66              ; =102
10000c64c: 3900092a    	strb	w10, [x9, #0x2]
10000c650: 528dcd2a    	mov	w10, #0x6e69            ; =28265
10000c654: 7900012a    	strh	w10, [x9]
10000c658: 52800009    	mov	w9, #0x0                ; =0
10000c65c: 7100011f    	cmp	w8, #0x0
10000c660: 52800068    	mov	w8, #0x3                ; =3
10000c664: 9a880508    	cinc	x8, x8, ne
10000c668: 140003a5    	b	0x10000d4fc <_Io.Writer.printValue__anon_4310+0x14d8>
10000c66c: d28fffe9    	mov	x9, #0x7fff             ; =32767
10000c670: f2b498c9    	movk	x9, #0xa4c6, lsl #16
10000c674: f2d1afc9    	movk	x9, #0x8d7e, lsl #32
10000c678: f2e00069    	movk	x9, #0x3, lsl #48
10000c67c: eb09011f    	cmp	x8, x9
10000c680: 54000069    	b.ls	0x10000c68c <_Io.Writer.printValue__anon_4310+0x668>
10000c684: 5280021b    	mov	w27, #0x10              ; =16
10000c688: 140002b8    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c68c: d287ffe9    	mov	x9, #0x3fff             ; =16383
10000c690: f2a20f49    	movk	x9, #0x107a, lsl #16
10000c694: f2cb5e69    	movk	x9, #0x5af3, lsl #32
10000c698: eb09011f    	cmp	x8, x9
10000c69c: 54000149    	b.ls	0x10000c6c4 <_Io.Writer.printValue__anon_4310+0x6a0>
10000c6a0: 528001fb    	mov	w27, #0xf               ; =15
10000c6a4: 140002b1    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c6a8: d293ffe8    	mov	x8, #0x9fff             ; =40959
10000c6ac: f2a9ce48    	movk	x8, #0x4e72, lsl #16
10000c6b0: f2c12308    	movk	x8, #0x918, lsl #32
10000c6b4: eb08035f    	cmp	x26, x8
10000c6b8: 54000149    	b.ls	0x10000c6e0 <_Io.Writer.printValue__anon_4310+0x6bc>
10000c6bc: 528001db    	mov	w27, #0xe               ; =14
10000c6c0: 140000ac    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c6c4: d293ffe9    	mov	x9, #0x9fff             ; =40959
10000c6c8: f2a9ce49    	movk	x9, #0x4e72, lsl #16
10000c6cc: f2c12309    	movk	x9, #0x918, lsl #32
10000c6d0: eb09011f    	cmp	x8, x9
10000c6d4: 54000149    	b.ls	0x10000c6fc <_Io.Writer.printValue__anon_4310+0x6d8>
10000c6d8: 528001db    	mov	w27, #0xe               ; =14
10000c6dc: 140002a3    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c6e0: d281ffe8    	mov	x8, #0xfff              ; =4095
10000c6e4: f2ba94a8    	movk	x8, #0xd4a5, lsl #16
10000c6e8: f2c01d08    	movk	x8, #0xe8, lsl #32
10000c6ec: eb08035f    	cmp	x26, x8
10000c6f0: 540005a9    	b.ls	0x10000c7a4 <_Io.Writer.printValue__anon_4310+0x780>
10000c6f4: 528001bb    	mov	w27, #0xd               ; =13
10000c6f8: 1400009e    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c6fc: d281ffe9    	mov	x9, #0xfff              ; =4095
10000c700: f2ba94a9    	movk	x9, #0xd4a5, lsl #16
10000c704: f2c01d09    	movk	x9, #0xe8, lsl #32
10000c708: eb09011f    	cmp	x8, x9
10000c70c: 540005a9    	b.ls	0x10000c7c0 <_Io.Writer.printValue__anon_4310+0x79c>
10000c710: 528001bb    	mov	w27, #0xd               ; =13
10000c714: 14000295    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c718: 52800010    	mov	w16, #0x0               ; =0
10000c71c: 9bd17dee    	umulh	x14, x15, x17
10000c720: d342fdce    	lsr	x14, x14, #2
10000c724: 8b0e09c0    	add	x0, x14, x14, lsl #2
10000c728: eb0001ff    	cmp	x15, x0
10000c72c: 540000c1    	b.ne	0x10000c744 <_Io.Writer.printValue__anon_4310+0x720>
10000c730: 11000610    	add	w16, w16, #0x1
10000c734: f10011ff    	cmp	x15, #0x4
10000c738: aa0e03ef    	mov	x15, x14
10000c73c: 54ffff08    	b.hi	0x10000c71c <_Io.Writer.printValue__anon_4310+0x6f8>
10000c740: 52800010    	mov	w16, #0x0               ; =0
10000c744: 5280000e    	mov	w14, #0x0               ; =0
10000c748: 6b09021f    	cmp	w16, w9
10000c74c: 1a9f37ef    	cset	w15, hs
10000c750: 17ffff44    	b	0x10000c460 <_Io.Writer.printValue__anon_4310+0x43c>
10000c754: 52800010    	mov	w16, #0x0               ; =0
10000c758: b202e7ea    	mov	x10, #-0x3333333333333334 ; =-3689348814741910324
10000c75c: f29999aa    	movk	x10, #0xcccd
10000c760: 9bca7dcf    	umulh	x15, x14, x10
10000c764: d342fdef    	lsr	x15, x15, #2
10000c768: 8b0f09f1    	add	x17, x15, x15, lsl #2
10000c76c: eb1101df    	cmp	x14, x17
10000c770: 540000c1    	b.ne	0x10000c788 <_Io.Writer.printValue__anon_4310+0x764>
10000c774: 11000610    	add	w16, w16, #0x1
10000c778: f10011df    	cmp	x14, #0x4
10000c77c: aa0f03ee    	mov	x14, x15
10000c780: 54ffff08    	b.hi	0x10000c760 <_Io.Writer.printValue__anon_4310+0x73c>
10000c784: 52800010    	mov	w16, #0x0               ; =0
10000c788: 5280000a    	mov	w10, #0x0               ; =0
10000c78c: 5280000f    	mov	w15, #0x0               ; =0
10000c790: 5280000e    	mov	w14, #0x0               ; =0
10000c794: 6b09021f    	cmp	w16, w9
10000c798: 1a9f37f0    	cset	w16, hs
10000c79c: cb1001ad    	sub	x13, x13, x16
10000c7a0: 17ffff30    	b	0x10000c460 <_Io.Writer.printValue__anon_4310+0x43c>
10000c7a4: d29cffe8    	mov	x8, #0xe7ff             ; =59391
10000c7a8: f2a90ec8    	movk	x8, #0x4876, lsl #16
10000c7ac: f2c002e8    	movk	x8, #0x17, lsl #32
10000c7b0: eb08035f    	cmp	x26, x8
10000c7b4: 54000149    	b.ls	0x10000c7dc <_Io.Writer.printValue__anon_4310+0x7b8>
10000c7b8: 5280019b    	mov	w27, #0xc               ; =12
10000c7bc: 1400006d    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c7c0: d29cffe9    	mov	x9, #0xe7ff             ; =59391
10000c7c4: f2a90ec9    	movk	x9, #0x4876, lsl #16
10000c7c8: f2c002e9    	movk	x9, #0x17, lsl #32
10000c7cc: eb09011f    	cmp	x8, x9
10000c7d0: 54000149    	b.ls	0x10000c7f8 <_Io.Writer.printValue__anon_4310+0x7d4>
10000c7d4: 5280019b    	mov	w27, #0xc               ; =12
10000c7d8: 14000264    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c7dc: d29c7fe8    	mov	x8, #0xe3ff             ; =58367
10000c7e0: f2aa8168    	movk	x8, #0x540b, lsl #16
10000c7e4: f2c00048    	movk	x8, #0x2, lsl #32
10000c7e8: eb08035f    	cmp	x26, x8
10000c7ec: 54000149    	b.ls	0x10000c814 <_Io.Writer.printValue__anon_4310+0x7f0>
10000c7f0: 5280017b    	mov	w27, #0xb               ; =11
10000c7f4: 1400005f    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c7f8: d29c7fe9    	mov	x9, #0xe3ff             ; =58367
10000c7fc: f2aa8169    	movk	x9, #0x540b, lsl #16
10000c800: f2c00049    	movk	x9, #0x2, lsl #32
10000c804: eb09011f    	cmp	x8, x9
10000c808: 54000129    	b.ls	0x10000c82c <_Io.Writer.printValue__anon_4310+0x808>
10000c80c: 5280017b    	mov	w27, #0xb               ; =11
10000c810: 14000256    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c814: 52993fe8    	mov	w8, #0xc9ff             ; =51711
10000c818: 72a77348    	movk	w8, #0x3b9a, lsl #16
10000c81c: eb08035f    	cmp	x26, x8
10000c820: 54000129    	b.ls	0x10000c844 <_Io.Writer.printValue__anon_4310+0x820>
10000c824: 5280015b    	mov	w27, #0xa               ; =10
10000c828: 14000052    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c82c: 52993fe9    	mov	w9, #0xc9ff             ; =51711
10000c830: 72a77349    	movk	w9, #0x3b9a, lsl #16
10000c834: eb09011f    	cmp	x8, x9
10000c838: 54000129    	b.ls	0x10000c85c <_Io.Writer.printValue__anon_4310+0x838>
10000c83c: 5280015b    	mov	w27, #0xa               ; =10
10000c840: 1400024a    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c844: 529c1fe8    	mov	w8, #0xe0ff             ; =57599
10000c848: 72a0bea8    	movk	w8, #0x5f5, lsl #16
10000c84c: eb08035f    	cmp	x26, x8
10000c850: 54000129    	b.ls	0x10000c874 <_Io.Writer.printValue__anon_4310+0x850>
10000c854: 5280013b    	mov	w27, #0x9               ; =9
10000c858: 14000046    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c85c: 529c1fe9    	mov	w9, #0xe0ff             ; =57599
10000c860: 72a0bea9    	movk	w9, #0x5f5, lsl #16
10000c864: eb09011f    	cmp	x8, x9
10000c868: 54000129    	b.ls	0x10000c88c <_Io.Writer.printValue__anon_4310+0x868>
10000c86c: 5280013b    	mov	w27, #0x9               ; =9
10000c870: 1400023e    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c874: 5292cfe8    	mov	w8, #0x967f             ; =38527
10000c878: 72a01308    	movk	w8, #0x98, lsl #16
10000c87c: eb08035f    	cmp	x26, x8
10000c880: 54000129    	b.ls	0x10000c8a4 <_Io.Writer.printValue__anon_4310+0x880>
10000c884: 5280011b    	mov	w27, #0x8               ; =8
10000c888: 1400003a    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c88c: 5292cfe9    	mov	w9, #0x967f             ; =38527
10000c890: 72a01309    	movk	w9, #0x98, lsl #16
10000c894: eb09011f    	cmp	x8, x9
10000c898: 54000129    	b.ls	0x10000c8bc <_Io.Writer.printValue__anon_4310+0x898>
10000c89c: 5280011b    	mov	w27, #0x8               ; =8
10000c8a0: 14000232    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c8a4: 528847e8    	mov	w8, #0x423f             ; =16959
10000c8a8: 72a001e8    	movk	w8, #0xf, lsl #16
10000c8ac: eb08035f    	cmp	x26, x8
10000c8b0: 54000129    	b.ls	0x10000c8d4 <_Io.Writer.printValue__anon_4310+0x8b0>
10000c8b4: 528000fb    	mov	w27, #0x7               ; =7
10000c8b8: 1400002e    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c8bc: 528847e9    	mov	w9, #0x423f             ; =16959
10000c8c0: 72a001e9    	movk	w9, #0xf, lsl #16
10000c8c4: eb09011f    	cmp	x8, x9
10000c8c8: 54000109    	b.ls	0x10000c8e8 <_Io.Writer.printValue__anon_4310+0x8c4>
10000c8cc: 528000fb    	mov	w27, #0x7               ; =7
10000c8d0: 14000226    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c8d4: d345ff48    	lsr	x8, x26, #5
10000c8d8: f130d11f    	cmp	x8, #0xc34
10000c8dc: 54000109    	b.ls	0x10000c8fc <_Io.Writer.printValue__anon_4310+0x8d8>
10000c8e0: 528000db    	mov	w27, #0x6               ; =6
10000c8e4: 14000023    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c8e8: d345fd09    	lsr	x9, x8, #5
10000c8ec: f130d13f    	cmp	x9, #0xc34
10000c8f0: 54000109    	b.ls	0x10000c910 <_Io.Writer.printValue__anon_4310+0x8ec>
10000c8f4: 528000db    	mov	w27, #0x6               ; =6
10000c8f8: 1400021c    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c8fc: d344ff48    	lsr	x8, x26, #4
10000c900: f109c11f    	cmp	x8, #0x270
10000c904: 54000109    	b.ls	0x10000c924 <_Io.Writer.printValue__anon_4310+0x900>
10000c908: 528000bb    	mov	w27, #0x5               ; =5
10000c90c: 14000019    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c910: d344fd09    	lsr	x9, x8, #4
10000c914: f109c13f    	cmp	x9, #0x270
10000c918: 540000e9    	b.ls	0x10000c934 <_Io.Writer.printValue__anon_4310+0x910>
10000c91c: 528000bb    	mov	w27, #0x5               ; =5
10000c920: 14000212    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c924: f10f9f5f    	cmp	x26, #0x3e7
10000c928: 540000e9    	b.ls	0x10000c944 <_Io.Writer.printValue__anon_4310+0x920>
10000c92c: 5280009b    	mov	w27, #0x4               ; =4
10000c930: 14000010    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c934: f10f9d1f    	cmp	x8, #0x3e7
10000c938: 540000e9    	b.ls	0x10000c954 <_Io.Writer.printValue__anon_4310+0x930>
10000c93c: 5280009b    	mov	w27, #0x4               ; =4
10000c940: 1400020a    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c944: f1018f5f    	cmp	x26, #0x63
10000c948: 540000e9    	b.ls	0x10000c964 <_Io.Writer.printValue__anon_4310+0x940>
10000c94c: 5280007b    	mov	w27, #0x3               ; =3
10000c950: 14000008    	b	0x10000c970 <_Io.Writer.printValue__anon_4310+0x94c>
10000c954: f1018d1f    	cmp	x8, #0x63
10000c958: 54004029    	b.ls	0x10000d15c <_Io.Writer.printValue__anon_4310+0x1138>
10000c95c: 5280007b    	mov	w27, #0x3               ; =3
10000c960: 14000202    	b	0x10000d168 <_Io.Writer.printValue__anon_4310+0x1144>
10000c964: f100275f    	cmp	x26, #0x9
10000c968: 52800028    	mov	w8, #0x1                ; =1
10000c96c: 1a88951b    	cinc	w27, w8, hi
10000c970: b9401b28    	ldr	w8, [x25, #0x18]
10000c974: 37f80128    	tbnz	w8, #0x1f, 0x10000c998 <_Io.Writer.printValue__anon_4310+0x974>
10000c978: 7100031f    	cmp	w24, #0x0
10000c97c: 9a9403e9    	csel	x9, xzr, x20, eq
10000c980: 8b3b4129    	add	x9, x9, w27, uxtw
10000c984: 8b090109    	add	x9, x8, x9
10000c988: 91000929    	add	x9, x9, #0x2
10000c98c: f1056d3f    	cmp	x9, #0x15b
10000c990: 54000149    	b.ls	0x10000c9b8 <_Io.Writer.printValue__anon_4310+0x994>
10000c994: 140001f8    	b	0x10000d174 <_Io.Writer.printValue__anon_4310+0x1150>
10000c998: 4b080369    	sub	w9, w27, w8
10000c99c: eb14013f    	cmp	x9, x20
10000c9a0: 9a94812a    	csel	x10, x9, x20, hi
10000c9a4: 7100031f    	cmp	w24, #0x0
10000c9a8: 9a8a0129    	csel	x9, x9, x10, eq
10000c9ac: 91000929    	add	x9, x9, #0x2
10000c9b0: f1056d3f    	cmp	x9, #0x15b
10000c9b4: 54003e08    	b.hi	0x10000d174 <_Io.Writer.printValue__anon_4310+0x1150>
10000c9b8: 3859c3a9    	ldurb	w9, [x29, #-0x64]
10000c9bc: 36000509    	tbz	w9, #0x0, 0x10000ca5c <_Io.Writer.printValue__anon_4310+0xa38>
10000c9c0: 528005a9    	mov	w9, #0x2d               ; =45
10000c9c4: 390077e9    	strb	w9, [sp, #0x1d]
10000c9c8: 52800039    	mov	w25, #0x1               ; =1
10000c9cc: 0b1b011c    	add	w28, w8, w27
10000c9d0: 7100079f    	cmp	w28, #0x1
10000c9d4: 540004eb    	b.lt	0x10000ca70 <_Io.Writer.printValue__anon_4310+0xa4c>
10000c9d8: 2a1b03e8    	mov	w8, w27
10000c9dc: 6b1b039f    	cmp	w28, w27
10000c9e0: 540015a2    	b.hs	0x10000cc94 <_Io.Writer.printValue__anon_4310+0xc70>
10000c9e4: 8b1c0329    	add	x9, x25, x28
10000c9e8: cb1c010a    	sub	x10, x8, x28
10000c9ec: f1000d5f    	cmp	x10, #0x3
10000c9f0: 54002483    	b.lo	0x10000ce80 <_Io.Writer.printValue__anon_4310+0xe5c>
10000c9f4: d280000c    	mov	x12, #0x0               ; =0
10000c9f8: 910077eb    	add	x11, sp, #0x1d
10000c9fc: 8b08032d    	add	x13, x25, x8
10000ca00: 8b0d016b    	add	x11, x11, x13
10000ca04: d29eb86d    	mov	x13, #0xf5c3            ; =62915
10000ca08: f2ab850d    	movk	x13, #0x5c28, lsl #16
10000ca0c: f2d851ed    	movk	x13, #0xc28f, lsl #32
10000ca10: f2e51ead    	movk	x13, #0x28f5, lsl #48
10000ca14: 52800c8e    	mov	w14, #0x64              ; =100
10000ca18: aa1a03f1    	mov	x17, x26
10000ca1c: d000002f    	adrp	x15, 0x100012000 <___anon_4979+0x1f98>
10000ca20: 912ae5ef    	add	x15, x15, #0xab9
10000ca24: d342fe30    	lsr	x16, x17, #2
10000ca28: 9bcd7e10    	umulh	x16, x16, x13
10000ca2c: d342fe1a    	lsr	x26, x16, #2
10000ca30: 9b0ec750    	msub	x16, x26, x14, x17
10000ca34: 787079f0    	ldrh	w16, [x15, x16, lsl #1]
10000ca38: 781ff170    	sturh	w16, [x11, #-0x1]
10000ca3c: 91000990    	add	x16, x12, #0x2
10000ca40: d100096b    	sub	x11, x11, #0x2
10000ca44: 91001180    	add	x0, x12, #0x4
10000ca48: aa1003ec    	mov	x12, x16
10000ca4c: aa1a03f1    	mov	x17, x26
10000ca50: eb0a001f    	cmp	x0, x10
10000ca54: 54fffe83    	b.lo	0x10000ca24 <_Io.Writer.printValue__anon_4310+0xa00>
10000ca58: 1400010b    	b	0x10000ce84 <_Io.Writer.printValue__anon_4310+0xe60>
10000ca5c: d2800019    	mov	x25, #0x0               ; =0
10000ca60: 910077f5    	add	x21, sp, #0x1d
10000ca64: 0b1b011c    	add	w28, w8, w27
10000ca68: 7100079f    	cmp	w28, #0x1
10000ca6c: 54fffb6a    	b.ge	0x10000c9d8 <_Io.Writer.printValue__anon_4310+0x9b4>
10000ca70: 910077e9    	add	x9, sp, #0x1d
10000ca74: 52800608    	mov	w8, #0x30               ; =48
10000ca78: 38396928    	strb	w8, [x9, x25]
10000ca7c: 528005c8    	mov	w8, #0x2e               ; =46
10000ca80: 390006a8    	strb	w8, [x21, #0x1]
10000ca84: f90007f9    	str	x25, [sp, #0x8]
10000ca88: b27f0339    	orr	x25, x25, #0x2
10000ca8c: 4b1c03f5    	neg	w21, w28
10000ca90: 910077fc    	add	x28, sp, #0x1d
10000ca94: 8b190380    	add	x0, x28, x25
10000ca98: 52800601    	mov	w1, #0x30               ; =48
10000ca9c: aa1503e2    	mov	x2, x21
10000caa0: 940008f8    	bl	0x10000ee80 <dyld_stub_binder+0x10000ee80>
10000caa4: 8b150328    	add	x8, x25, x21
10000caa8: 2a1b03e9    	mov	w9, w27
10000caac: 71000b7f    	cmp	w27, #0x2
10000cab0: 54001e49    	b.ls	0x10000ce78 <_Io.Writer.printValue__anon_4310+0xe54>
10000cab4: d342ff4a    	lsr	x10, x26, #2
10000cab8: d29eb86b    	mov	x11, #0xf5c3            ; =62915
10000cabc: f2ab850b    	movk	x11, #0x5c28, lsl #16
10000cac0: f2d851eb    	movk	x11, #0xc28f, lsl #32
10000cac4: f2e51eab    	movk	x11, #0x28f5, lsl #48
10000cac8: 9bcb7d4a    	umulh	x10, x10, x11
10000cacc: d342fd4c    	lsr	x12, x10, #2
10000cad0: 52800c8a    	mov	w10, #0x64              ; =100
10000cad4: 9b0ae98b    	msub	x11, x12, x10, x26
10000cad8: d000002a    	adrp	x10, 0x100012000 <___anon_4979+0x1f98>
10000cadc: 912ae54a    	add	x10, x10, #0xab9
10000cae0: 786b794d    	ldrh	w13, [x10, x11, lsl #1]
10000cae4: 8b08038b    	add	x11, x28, x8
10000cae8: 8b09016e    	add	x14, x11, x9
10000caec: 781fe1cd    	sturh	w13, [x14, #-0x2]
10000caf0: 7100177f    	cmp	w27, #0x5
10000caf4: 540026e3    	b.lo	0x10000cfd0 <_Io.Writer.printValue__anon_4310+0xfac>
10000caf8: d283d72d    	mov	x13, #0x1eb9            ; =7865
10000cafc: f2bd70ad    	movk	x13, #0xeb85, lsl #16
10000cb00: f2d70a2d    	movk	x13, #0xb851, lsl #32
10000cb04: f2e0a3cd    	movk	x13, #0x51e, lsl #48
10000cb08: 9bcd7d8d    	umulh	x13, x12, x13
10000cb0c: d341fdad    	lsr	x13, x13, #1
10000cb10: 52800c8f    	mov	w15, #0x64              ; =100
10000cb14: 9b0fb1ac    	msub	x12, x13, x15, x12
10000cb18: d28b296d    	mov	x13, #0x594b            ; =22859
10000cb1c: f2a710cd    	movk	x13, #0x3886, lsl #16
10000cb20: f2d8bacd    	movk	x13, #0xc5d6, lsl #32
10000cb24: f2e68dad    	movk	x13, #0x346d, lsl #48
10000cb28: 9bcd7f4d    	umulh	x13, x26, x13
10000cb2c: d34bfdad    	lsr	x13, x13, #11
10000cb30: 786c794c    	ldrh	w12, [x10, x12, lsl #1]
10000cb34: 781fc1cc    	sturh	w12, [x14, #-0x4]
10000cb38: 71001f7f    	cmp	w27, #0x7
10000cb3c: 54002563    	b.lo	0x10000cfe8 <_Io.Writer.printValue__anon_4310+0xfc4>
10000cb40: d291ebac    	mov	x12, #0x8f5d            ; =36701
10000cb44: f2beb84c    	movk	x12, #0xf5c2, lsl #16
10000cb48: f2cb850c    	movk	x12, #0x5c28, lsl #32
10000cb4c: f2e051ec    	movk	x12, #0x28f, lsl #48
10000cb50: 9bcc7dae    	umulh	x14, x13, x12
10000cb54: 52800c8f    	mov	w15, #0x64              ; =100
10000cb58: 9b0fb5ce    	msub	x14, x14, x15, x13
10000cb5c: d2869b6d    	mov	x13, #0x34db            ; =13531
10000cb60: f2baf6cd    	movk	x13, #0xd7b6, lsl #16
10000cb64: f2dbd04d    	movk	x13, #0xde82, lsl #32
10000cb68: f2e8636d    	movk	x13, #0x431b, lsl #48
10000cb6c: 9bcd7f4d    	umulh	x13, x26, x13
10000cb70: d352fdad    	lsr	x13, x13, #18
10000cb74: 786e794f    	ldrh	w15, [x10, x14, lsl #1]
10000cb78: 8b09016e    	add	x14, x11, x9
10000cb7c: 781fa1cf    	sturh	w15, [x14, #-0x6]
10000cb80: 7100277f    	cmp	w27, #0x9
10000cb84: 540023a3    	b.lo	0x10000cff8 <_Io.Writer.printValue__anon_4310+0xfd4>
10000cb88: 9bcc7daf    	umulh	x15, x13, x12
10000cb8c: 52800c90    	mov	w16, #0x64              ; =100
10000cb90: 9b10b5ef    	msub	x15, x15, x16, x13
10000cb94: d299dfad    	mov	x13, #0xcefd            ; =52989
10000cb98: f2b08c2d    	movk	x13, #0x8461, lsl #16
10000cb9c: f2cee22d    	movk	x13, #0x7711, lsl #32
10000cba0: f2f5798d    	movk	x13, #0xabcc, lsl #48
10000cba4: 9bcd7f4d    	umulh	x13, x26, x13
10000cba8: d35afdad    	lsr	x13, x13, #26
10000cbac: 786f794f    	ldrh	w15, [x10, x15, lsl #1]
10000cbb0: 781f81cf    	sturh	w15, [x14, #-0x8]
10000cbb4: 71002f7f    	cmp	w27, #0xb
10000cbb8: 54002283    	b.lo	0x10000d008 <_Io.Writer.printValue__anon_4310+0xfe4>
10000cbbc: 9bcc7dae    	umulh	x14, x13, x12
10000cbc0: 52800c8f    	mov	w15, #0x64              ; =100
10000cbc4: 9bafb5ce    	umsubl	x14, w14, w15, x13
10000cbc8: d29ab7ed    	mov	x13, #0xd5bf            ; =54719
10000cbcc: f2b7bdad    	movk	x13, #0xbded, lsl #16
10000cbd0: f2dfd9cd    	movk	x13, #0xfece, lsl #32
10000cbd4: f2fb7ccd    	movk	x13, #0xdbe6, lsl #48
10000cbd8: 9bcd7f4d    	umulh	x13, x26, x13
10000cbdc: d361fdad    	lsr	x13, x13, #33
10000cbe0: 786e794f    	ldrh	w15, [x10, x14, lsl #1]
10000cbe4: 8b09016e    	add	x14, x11, x9
10000cbe8: 781f61cf    	sturh	w15, [x14, #-0xa]
10000cbec: 7100377f    	cmp	w27, #0xd
10000cbf0: 54002143    	b.lo	0x10000d018 <_Io.Writer.printValue__anon_4310+0xff4>
10000cbf4: 9bcc7daf    	umulh	x15, x13, x12
10000cbf8: 52800c90    	mov	w16, #0x64              ; =100
10000cbfc: 9bb0b5ef    	umsubl	x15, w15, w16, x13
10000cc00: d284466d    	mov	x13, #0x2233            ; =8755
10000cc04: f2ab7a8d    	movk	x13, #0x5bd4, lsl #16
10000cc08: f2c6604d    	movk	x13, #0x3302, lsl #32
10000cc0c: f2e465ed    	movk	x13, #0x232f, lsl #48
10000cc10: 9bcd7f4d    	umulh	x13, x26, x13
10000cc14: d365fdad    	lsr	x13, x13, #37
10000cc18: 786f794f    	ldrh	w15, [x10, x15, lsl #1]
10000cc1c: 781f41cf    	sturh	w15, [x14, #-0xc]
10000cc20: 71003f7f    	cmp	w27, #0xf
10000cc24: 54002023    	b.lo	0x10000d028 <_Io.Writer.printValue__anon_4310+0x1004>
10000cc28: 9bcc7dae    	umulh	x14, x13, x12
10000cc2c: 52800c8f    	mov	w15, #0x64              ; =100
10000cc30: 9bafb5ce    	umsubl	x14, w14, w15, x13
10000cc34: d299b02d    	mov	x13, #0xcd81            ; =52609
10000cc38: f2aa12ad    	movk	x13, #0x5095, lsl #16
10000cc3c: f2c9b86d    	movk	x13, #0x4dc3, lsl #32
10000cc40: f2e1684d    	movk	x13, #0xb42, lsl #48
10000cc44: 9bcd7f4d    	umulh	x13, x26, x13
10000cc48: d36afdad    	lsr	x13, x13, #42
10000cc4c: 786e794e    	ldrh	w14, [x10, x14, lsl #1]
10000cc50: 8b09016b    	add	x11, x11, x9
10000cc54: 781f216e    	sturh	w14, [x11, #-0xe]
10000cc58: 7100477f    	cmp	w27, #0x11
10000cc5c: 54001ee3    	b.lo	0x10000d038 <_Io.Writer.printValue__anon_4310+0x1014>
10000cc60: 9bcc7dac    	umulh	x12, x13, x12
10000cc64: 52800c8e    	mov	w14, #0x64              ; =100
10000cc68: 9baeb58c    	umsubl	x12, w12, w14, x13
10000cc6c: d28f0aed    	mov	x13, #0x7857            ; =30807
10000cc70: f2b6226d    	movk	x13, #0xb113, lsl #16
10000cc74: f2cca5ed    	movk	x13, #0x652f, lsl #32
10000cc78: f2e734ad    	movk	x13, #0x39a5, lsl #48
10000cc7c: 9bcd7f4d    	umulh	x13, x26, x13
10000cc80: d373fdba    	lsr	x26, x13, #51
10000cc84: 786c794a    	ldrh	w10, [x10, x12, lsl #1]
10000cc88: 781f016a    	sturh	w10, [x11, #-0x10]
10000cc8c: 5280020a    	mov	w10, #0x10              ; =16
10000cc90: 140000ec    	b	0x10000d040 <_Io.Writer.printValue__anon_4310+0x101c>
10000cc94: 71000b7f    	cmp	w27, #0x2
10000cc98: 540011e9    	b.ls	0x10000ced4 <_Io.Writer.printValue__anon_4310+0xeb0>
10000cc9c: d342ff49    	lsr	x9, x26, #2
10000cca0: d29eb86a    	mov	x10, #0xf5c3            ; =62915
10000cca4: f2ab850a    	movk	x10, #0x5c28, lsl #16
10000cca8: f2d851ea    	movk	x10, #0xc28f, lsl #32
10000ccac: f2e51eaa    	movk	x10, #0x28f5, lsl #48
10000ccb0: 9bca7d29    	umulh	x9, x9, x10
10000ccb4: d342fd2a    	lsr	x10, x9, #2
10000ccb8: 52800c8b    	mov	w11, #0x64              ; =100
10000ccbc: d0000029    	adrp	x9, 0x100012000 <___anon_4979+0x1f98>
10000ccc0: 912ae529    	add	x9, x9, #0xab9
10000ccc4: 9b0be94b    	msub	x11, x10, x11, x26
10000ccc8: 786b792b    	ldrh	w11, [x9, x11, lsl #1]
10000cccc: 8b0802ac    	add	x12, x21, x8
10000ccd0: 781fe18b    	sturh	w11, [x12, #-0x2]
10000ccd4: 7100177f    	cmp	w27, #0x5
10000ccd8: 54001823    	b.lo	0x10000cfdc <_Io.Writer.printValue__anon_4310+0xfb8>
10000ccdc: d283d72b    	mov	x11, #0x1eb9            ; =7865
10000cce0: f2bd70ab    	movk	x11, #0xeb85, lsl #16
10000cce4: f2d70a2b    	movk	x11, #0xb851, lsl #32
10000cce8: f2e0a3cb    	movk	x11, #0x51e, lsl #48
10000ccec: 9bcb7d4b    	umulh	x11, x10, x11
10000ccf0: d341fd6b    	lsr	x11, x11, #1
10000ccf4: 52800c8d    	mov	w13, #0x64              ; =100
10000ccf8: 9b0da96a    	msub	x10, x11, x13, x10
10000ccfc: d28b296b    	mov	x11, #0x594b            ; =22859
10000cd00: f2a710cb    	movk	x11, #0x3886, lsl #16
10000cd04: f2d8bacb    	movk	x11, #0xc5d6, lsl #32
10000cd08: f2e68dab    	movk	x11, #0x346d, lsl #48
10000cd0c: 9bcb7f4b    	umulh	x11, x26, x11
10000cd10: d34bfd6b    	lsr	x11, x11, #11
10000cd14: 786a792a    	ldrh	w10, [x9, x10, lsl #1]
10000cd18: 781fc18a    	sturh	w10, [x12, #-0x4]
10000cd1c: 71001f7f    	cmp	w27, #0x7
10000cd20: 54001683    	b.lo	0x10000cff0 <_Io.Writer.printValue__anon_4310+0xfcc>
10000cd24: d291ebaa    	mov	x10, #0x8f5d            ; =36701
10000cd28: f2beb84a    	movk	x10, #0xf5c2, lsl #16
10000cd2c: f2cb850a    	movk	x10, #0x5c28, lsl #32
10000cd30: f2e051ea    	movk	x10, #0x28f, lsl #48
10000cd34: 9bca7d6c    	umulh	x12, x11, x10
10000cd38: 52800c8d    	mov	w13, #0x64              ; =100
10000cd3c: 9b0dad8c    	msub	x12, x12, x13, x11
10000cd40: d2869b6b    	mov	x11, #0x34db            ; =13531
10000cd44: f2baf6cb    	movk	x11, #0xd7b6, lsl #16
10000cd48: f2dbd04b    	movk	x11, #0xde82, lsl #32
10000cd4c: f2e8636b    	movk	x11, #0x431b, lsl #48
10000cd50: 9bcb7f4b    	umulh	x11, x26, x11
10000cd54: d352fd6b    	lsr	x11, x11, #18
10000cd58: 786c792d    	ldrh	w13, [x9, x12, lsl #1]
10000cd5c: 8b0802ac    	add	x12, x21, x8
10000cd60: 781fa18d    	sturh	w13, [x12, #-0x6]
10000cd64: 7100277f    	cmp	w27, #0x9
10000cd68: 540014c3    	b.lo	0x10000d000 <_Io.Writer.printValue__anon_4310+0xfdc>
10000cd6c: 9bca7d6d    	umulh	x13, x11, x10
10000cd70: 52800c8e    	mov	w14, #0x64              ; =100
10000cd74: 9b0eadad    	msub	x13, x13, x14, x11
10000cd78: d299dfab    	mov	x11, #0xcefd            ; =52989
10000cd7c: f2b08c2b    	movk	x11, #0x8461, lsl #16
10000cd80: f2cee22b    	movk	x11, #0x7711, lsl #32
10000cd84: f2f5798b    	movk	x11, #0xabcc, lsl #48
10000cd88: 9bcb7f4b    	umulh	x11, x26, x11
10000cd8c: d35afd6b    	lsr	x11, x11, #26
10000cd90: 786d792d    	ldrh	w13, [x9, x13, lsl #1]
10000cd94: 781f818d    	sturh	w13, [x12, #-0x8]
10000cd98: 71002f7f    	cmp	w27, #0xb
10000cd9c: 540013a3    	b.lo	0x10000d010 <_Io.Writer.printValue__anon_4310+0xfec>
10000cda0: 9bca7d6c    	umulh	x12, x11, x10
10000cda4: 52800c8d    	mov	w13, #0x64              ; =100
10000cda8: 9badad8c    	umsubl	x12, w12, w13, x11
10000cdac: d29ab7eb    	mov	x11, #0xd5bf            ; =54719
10000cdb0: f2b7bdab    	movk	x11, #0xbded, lsl #16
10000cdb4: f2dfd9cb    	movk	x11, #0xfece, lsl #32
10000cdb8: f2fb7ccb    	movk	x11, #0xdbe6, lsl #48
10000cdbc: 9bcb7f4b    	umulh	x11, x26, x11
10000cdc0: d361fd6b    	lsr	x11, x11, #33
10000cdc4: 786c792d    	ldrh	w13, [x9, x12, lsl #1]
10000cdc8: 8b0802ac    	add	x12, x21, x8
10000cdcc: 781f618d    	sturh	w13, [x12, #-0xa]
10000cdd0: 7100377f    	cmp	w27, #0xd
10000cdd4: 54001263    	b.lo	0x10000d020 <_Io.Writer.printValue__anon_4310+0xffc>
10000cdd8: 9bca7d6d    	umulh	x13, x11, x10
10000cddc: 52800c8e    	mov	w14, #0x64              ; =100
10000cde0: 9baeadad    	umsubl	x13, w13, w14, x11
10000cde4: d284466b    	mov	x11, #0x2233            ; =8755
10000cde8: f2ab7a8b    	movk	x11, #0x5bd4, lsl #16
10000cdec: f2c6604b    	movk	x11, #0x3302, lsl #32
10000cdf0: f2e465eb    	movk	x11, #0x232f, lsl #48
10000cdf4: 9bcb7f4b    	umulh	x11, x26, x11
10000cdf8: d365fd6b    	lsr	x11, x11, #37
10000cdfc: 786d792d    	ldrh	w13, [x9, x13, lsl #1]
10000ce00: 781f418d    	sturh	w13, [x12, #-0xc]
10000ce04: 71003f7f    	cmp	w27, #0xf
10000ce08: 54001143    	b.lo	0x10000d030 <_Io.Writer.printValue__anon_4310+0x100c>
10000ce0c: 9bca7d6c    	umulh	x12, x11, x10
10000ce10: 52800c8d    	mov	w13, #0x64              ; =100
10000ce14: 9badad8c    	umsubl	x12, w12, w13, x11
10000ce18: d299b02b    	mov	x11, #0xcd81            ; =52609
10000ce1c: f2aa12ab    	movk	x11, #0x5095, lsl #16
10000ce20: f2c9b86b    	movk	x11, #0x4dc3, lsl #32
10000ce24: f2e1684b    	movk	x11, #0xb42, lsl #48
10000ce28: 9bcb7f4b    	umulh	x11, x26, x11
10000ce2c: d36afd6b    	lsr	x11, x11, #42
10000ce30: 786c792d    	ldrh	w13, [x9, x12, lsl #1]
10000ce34: 8b0802ac    	add	x12, x21, x8
10000ce38: 781f218d    	sturh	w13, [x12, #-0xe]
10000ce3c: 7100477f    	cmp	w27, #0x11
10000ce40: 54001463    	b.lo	0x10000d0cc <_Io.Writer.printValue__anon_4310+0x10a8>
10000ce44: 9bca7d6a    	umulh	x10, x11, x10
10000ce48: 52800c8d    	mov	w13, #0x64              ; =100
10000ce4c: 9badad4a    	umsubl	x10, w10, w13, x11
10000ce50: d28f0aeb    	mov	x11, #0x7857            ; =30807
10000ce54: f2b6226b    	movk	x11, #0xb113, lsl #16
10000ce58: f2cca5eb    	movk	x11, #0x652f, lsl #32
10000ce5c: f2e734ab    	movk	x11, #0x39a5, lsl #48
10000ce60: 9bcb7f4b    	umulh	x11, x26, x11
10000ce64: d373fd7a    	lsr	x26, x11, #51
10000ce68: 786a7929    	ldrh	w9, [x9, x10, lsl #1]
10000ce6c: 781f0189    	sturh	w9, [x12, #-0x10]
10000ce70: 52800209    	mov	w9, #0x10               ; =16
10000ce74: 14000098    	b	0x10000d0d4 <_Io.Writer.printValue__anon_4310+0x10b0>
10000ce78: d280000a    	mov	x10, #0x0               ; =0
10000ce7c: 14000073    	b	0x10000d048 <_Io.Writer.printValue__anon_4310+0x1024>
10000ce80: d2800010    	mov	x16, #0x0               ; =0
10000ce84: eb0a021f    	cmp	x16, x10
10000ce88: 540002a2    	b.hs	0x10000cedc <_Io.Writer.printValue__anon_4310+0xeb8>
10000ce8c: 8b1c020b    	add	x11, x16, x28
10000ce90: cb08016b    	sub	x11, x11, x8
10000ce94: 8b080328    	add	x8, x25, x8
10000ce98: cb100108    	sub	x8, x8, x16
10000ce9c: 910077ec    	add	x12, sp, #0x1d
10000cea0: 8b08018c    	add	x12, x12, x8
10000cea4: b202e7ed    	mov	x13, #-0x3333333333333334 ; =-3689348814741910324
10000cea8: f29999ad    	movk	x13, #0xcccd
10000ceac: 5280014e    	mov	w14, #0xa               ; =10
10000ceb0: 9bcd7f48    	umulh	x8, x26, x13
10000ceb4: d343fd08    	lsr	x8, x8, #3
10000ceb8: 1b0ee90f    	msub	w15, w8, w14, w26
10000cebc: 321c05ef    	orr	w15, w15, #0x30
10000cec0: 381ff58f    	strb	w15, [x12], #-0x1
10000cec4: aa0803fa    	mov	x26, x8
10000cec8: b100056b    	adds	x11, x11, #0x1
10000cecc: 54ffff23    	b.lo	0x10000ceb0 <_Io.Writer.printValue__anon_4310+0xe8c>
10000ced0: 14000004    	b	0x10000cee0 <_Io.Writer.printValue__anon_4310+0xebc>
10000ced4: d2800009    	mov	x9, #0x0                ; =0
10000ced8: 14000081    	b	0x10000d0dc <_Io.Writer.printValue__anon_4310+0x10b8>
10000cedc: aa1a03e8    	mov	x8, x26
10000cee0: 910077eb    	add	x11, sp, #0x1d
10000cee4: 528005cc    	mov	w12, #0x2e              ; =46
10000cee8: 3829696c    	strb	w12, [x11, x9]
10000ceec: 71000f9f    	cmp	w28, #0x3
10000cef0: 54000343    	b.lo	0x10000cf58 <_Io.Writer.printValue__anon_4310+0xf34>
10000cef4: d280000c    	mov	x12, #0x0               ; =0
10000cef8: 8b15038b    	add	x11, x28, x21
10000cefc: d100056b    	sub	x11, x11, #0x1
10000cf00: d29eb86d    	mov	x13, #0xf5c3            ; =62915
10000cf04: f2ab850d    	movk	x13, #0x5c28, lsl #16
10000cf08: f2d851ed    	movk	x13, #0xc28f, lsl #32
10000cf0c: f2e51ead    	movk	x13, #0x28f5, lsl #48
10000cf10: 52800c8e    	mov	w14, #0x64              ; =100
10000cf14: d000002f    	adrp	x15, 0x100012000 <___anon_4979+0x1f98>
10000cf18: 912ae5ef    	add	x15, x15, #0xab9
10000cf1c: aa0803f1    	mov	x17, x8
10000cf20: d342fe28    	lsr	x8, x17, #2
10000cf24: 9bcd7d08    	umulh	x8, x8, x13
10000cf28: d342fd08    	lsr	x8, x8, #2
10000cf2c: 9b0ec510    	msub	x16, x8, x14, x17
10000cf30: 787079f0    	ldrh	w16, [x15, x16, lsl #1]
10000cf34: 781ff170    	sturh	w16, [x11, #-0x1]
10000cf38: 91000990    	add	x16, x12, #0x2
10000cf3c: d100096b    	sub	x11, x11, #0x2
10000cf40: 91001180    	add	x0, x12, #0x4
10000cf44: aa1003ec    	mov	x12, x16
10000cf48: aa0803f1    	mov	x17, x8
10000cf4c: eb1c001f    	cmp	x0, x28
10000cf50: 54fffe83    	b.lo	0x10000cf20 <_Io.Writer.printValue__anon_4310+0xefc>
10000cf54: 14000002    	b	0x10000cf5c <_Io.Writer.printValue__anon_4310+0xf38>
10000cf58: d2800010    	mov	x16, #0x0               ; =0
10000cf5c: eb10038b    	subs	x11, x28, x16
10000cf60: 540001a9    	b.ls	0x10000cf94 <_Io.Writer.printValue__anon_4310+0xf70>
10000cf64: d10006ac    	sub	x12, x21, #0x1
10000cf68: b202e7ed    	mov	x13, #-0x3333333333333334 ; =-3689348814741910324
10000cf6c: f29999ad    	movk	x13, #0xcccd
10000cf70: 5280014e    	mov	w14, #0xa               ; =10
10000cf74: 9bcd7d0f    	umulh	x15, x8, x13
10000cf78: d343fdef    	lsr	x15, x15, #3
10000cf7c: 1b0ea1e8    	msub	w8, w15, w14, w8
10000cf80: 321c0508    	orr	w8, w8, #0x30
10000cf84: 382b6988    	strb	w8, [x12, x11]
10000cf88: aa0f03e8    	mov	x8, x15
10000cf8c: f100056b    	subs	x11, x11, #0x1
10000cf90: 54ffff21    	b.ne	0x10000cf74 <_Io.Writer.printValue__anon_4310+0xf50>
10000cf94: 11000768    	add	w8, w27, #0x1
10000cf98: 8b080328    	add	x8, x25, x8
10000cf9c: 34000958    	cbz	w24, 0x10000d0c4 <_Io.Writer.printValue__anon_4310+0x10a0>
10000cfa0: 91000535    	add	x21, x9, #0x1
10000cfa4: eb0a0282    	subs	x2, x20, x10
10000cfa8: 540000a9    	b.ls	0x10000cfbc <_Io.Writer.printValue__anon_4310+0xf98>
10000cfac: 910077e9    	add	x9, sp, #0x1d
10000cfb0: 8b080120    	add	x0, x9, x8
10000cfb4: 52800601    	mov	w1, #0x30               ; =48
10000cfb8: 940007b2    	bl	0x10000ee80 <dyld_stub_binder+0x10000ee80>
10000cfbc: 52800009    	mov	w9, #0x0                ; =0
10000cfc0: f100029f    	cmp	x20, #0x0
10000cfc4: da9f1288    	csinv	x8, x20, xzr, ne
10000cfc8: 8b0802a8    	add	x8, x21, x8
10000cfcc: 1400014c    	b	0x10000d4fc <_Io.Writer.printValue__anon_4310+0x14d8>
10000cfd0: 5280004a    	mov	w10, #0x2               ; =2
10000cfd4: aa0c03fa    	mov	x26, x12
10000cfd8: 1400001a    	b	0x10000d040 <_Io.Writer.printValue__anon_4310+0x101c>
10000cfdc: 52800049    	mov	w9, #0x2                ; =2
10000cfe0: aa0a03fa    	mov	x26, x10
10000cfe4: 1400003c    	b	0x10000d0d4 <_Io.Writer.printValue__anon_4310+0x10b0>
10000cfe8: 5280008a    	mov	w10, #0x4               ; =4
10000cfec: 14000014    	b	0x10000d03c <_Io.Writer.printValue__anon_4310+0x1018>
10000cff0: 52800089    	mov	w9, #0x4                ; =4
10000cff4: 14000037    	b	0x10000d0d0 <_Io.Writer.printValue__anon_4310+0x10ac>
10000cff8: 528000ca    	mov	w10, #0x6               ; =6
10000cffc: 14000010    	b	0x10000d03c <_Io.Writer.printValue__anon_4310+0x1018>
10000d000: 528000c9    	mov	w9, #0x6                ; =6
10000d004: 14000033    	b	0x10000d0d0 <_Io.Writer.printValue__anon_4310+0x10ac>
10000d008: 5280010a    	mov	w10, #0x8               ; =8
10000d00c: 1400000c    	b	0x10000d03c <_Io.Writer.printValue__anon_4310+0x1018>
10000d010: 52800109    	mov	w9, #0x8                ; =8
10000d014: 1400002f    	b	0x10000d0d0 <_Io.Writer.printValue__anon_4310+0x10ac>
10000d018: 5280014a    	mov	w10, #0xa               ; =10
10000d01c: 14000008    	b	0x10000d03c <_Io.Writer.printValue__anon_4310+0x1018>
10000d020: 52800149    	mov	w9, #0xa                ; =10
10000d024: 1400002b    	b	0x10000d0d0 <_Io.Writer.printValue__anon_4310+0x10ac>
10000d028: 5280018a    	mov	w10, #0xc               ; =12
10000d02c: 14000004    	b	0x10000d03c <_Io.Writer.printValue__anon_4310+0x1018>
10000d030: 52800189    	mov	w9, #0xc                ; =12
10000d034: 14000027    	b	0x10000d0d0 <_Io.Writer.printValue__anon_4310+0x10ac>
10000d038: 528001ca    	mov	w10, #0xe               ; =14
10000d03c: aa0d03fa    	mov	x26, x13
10000d040: eb09015f    	cmp	x10, x9
10000d044: 54000242    	b.hs	0x10000d08c <_Io.Writer.printValue__anon_4310+0x1068>
10000d048: cb0a012a    	sub	x10, x9, x10
10000d04c: 9100054a    	add	x10, x10, #0x1
10000d050: f94007eb    	ldr	x11, [sp, #0x8]
10000d054: 8b15016b    	add	x11, x11, x21
10000d058: 8b0b038b    	add	x11, x28, x11
10000d05c: b202e7ec    	mov	x12, #-0x3333333333333334 ; =-3689348814741910324
10000d060: f29999ac    	movk	x12, #0xcccd
10000d064: 5280014d    	mov	w13, #0xa               ; =10
10000d068: 9bcc7f4e    	umulh	x14, x26, x12
10000d06c: d343fdce    	lsr	x14, x14, #3
10000d070: 1b0de9cf    	msub	w15, w14, w13, w26
10000d074: 321c05ef    	orr	w15, w15, #0x30
10000d078: 382a696f    	strb	w15, [x11, x10]
10000d07c: d100054a    	sub	x10, x10, #0x1
10000d080: aa0e03fa    	mov	x26, x14
10000d084: f100055f    	cmp	x10, #0x1
10000d088: 54ffff01    	b.ne	0x10000d068 <_Io.Writer.printValue__anon_4310+0x1044>
10000d08c: 8b090108    	add	x8, x8, x9
10000d090: 340001b8    	cbz	w24, 0x10000d0c4 <_Io.Writer.printValue__anon_4310+0x10a0>
10000d094: cb190109    	sub	x9, x8, x25
10000d098: eb090282    	subs	x2, x20, x9
10000d09c: 540000a9    	b.ls	0x10000d0b0 <_Io.Writer.printValue__anon_4310+0x108c>
10000d0a0: 910077e9    	add	x9, sp, #0x1d
10000d0a4: 8b080120    	add	x0, x9, x8
10000d0a8: 52800601    	mov	w1, #0x30               ; =48
10000d0ac: 94000775    	bl	0x10000ee80 <dyld_stub_binder+0x10000ee80>
10000d0b0: 52800009    	mov	w9, #0x0                ; =0
10000d0b4: f100029f    	cmp	x20, #0x0
10000d0b8: da9f1288    	csinv	x8, x20, xzr, ne
10000d0bc: 8b080328    	add	x8, x25, x8
10000d0c0: 1400010f    	b	0x10000d4fc <_Io.Writer.printValue__anon_4310+0x14d8>
10000d0c4: 52800009    	mov	w9, #0x0                ; =0
10000d0c8: 1400010d    	b	0x10000d4fc <_Io.Writer.printValue__anon_4310+0x14d8>
10000d0cc: 528001c9    	mov	w9, #0xe                ; =14
10000d0d0: aa0b03fa    	mov	x26, x11
10000d0d4: eb08013f    	cmp	x9, x8
10000d0d8: 540001c2    	b.hs	0x10000d110 <_Io.Writer.printValue__anon_4310+0x10ec>
10000d0dc: cb090109    	sub	x9, x8, x9
10000d0e0: d10006aa    	sub	x10, x21, #0x1
10000d0e4: b202e7eb    	mov	x11, #-0x3333333333333334 ; =-3689348814741910324
10000d0e8: f29999ab    	movk	x11, #0xcccd
10000d0ec: 5280014c    	mov	w12, #0xa               ; =10
10000d0f0: 9bcb7f4d    	umulh	x13, x26, x11
10000d0f4: d343fdad    	lsr	x13, x13, #3
10000d0f8: 1b0ce9ae    	msub	w14, w13, w12, w26
10000d0fc: 321c05ce    	orr	w14, w14, #0x30
10000d100: 3829694e    	strb	w14, [x10, x9]
10000d104: aa0d03fa    	mov	x26, x13
10000d108: f1000529    	subs	x9, x9, #0x1
10000d10c: 54ffff21    	b.ne	0x10000d0f0 <_Io.Writer.printValue__anon_4310+0x10cc>
10000d110: cb080382    	sub	x2, x28, x8
10000d114: 8b0802a0    	add	x0, x21, x8
10000d118: 52800601    	mov	w1, #0x30               ; =48
10000d11c: 94000759    	bl	0x10000ee80 <dyld_stub_binder+0x10000ee80>
10000d120: 52800009    	mov	w9, #0x0                ; =0
10000d124: 8b1c0328    	add	x8, x25, x28
10000d128: 34001eb8    	cbz	w24, 0x10000d4fc <_Io.Writer.printValue__anon_4310+0x14d8>
10000d12c: b4001e94    	cbz	x20, 0x10000d4fc <_Io.Writer.printValue__anon_4310+0x14d8>
10000d130: 910077e9    	add	x9, sp, #0x1d
10000d134: 528005ca    	mov	w10, #0x2e              ; =46
10000d138: 3828692a    	strb	w10, [x9, x8]
10000d13c: 91000515    	add	x21, x8, #0x1
10000d140: 8b150120    	add	x0, x9, x21
10000d144: 52800601    	mov	w1, #0x30               ; =48
10000d148: aa1403e2    	mov	x2, x20
10000d14c: 9400074d    	bl	0x10000ee80 <dyld_stub_binder+0x10000ee80>
10000d150: 52800009    	mov	w9, #0x0                ; =0
10000d154: 8b1402a8    	add	x8, x21, x20
10000d158: 140000e9    	b	0x10000d4fc <_Io.Writer.printValue__anon_4310+0x14d8>
10000d15c: f100251f    	cmp	x8, #0x9
10000d160: 52800029    	mov	w9, #0x1                ; =1
10000d164: 1a89953b    	cinc	w27, w9, hi
10000d168: 340000b8    	cbz	w24, 0x10000d17c <_Io.Writer.printValue__anon_4310+0x1158>
10000d16c: f1054e9f    	cmp	x20, #0x153
10000d170: 54000069    	b.ls	0x10000d17c <_Io.Writer.printValue__anon_4310+0x1158>
10000d174: 52800589    	mov	w9, #0x2c               ; =44
10000d178: 140000e1    	b	0x10000d4fc <_Io.Writer.printValue__anon_4310+0x14d8>
10000d17c: 3859c3a9    	ldurb	w9, [x29, #-0x64]
10000d180: 36000169    	tbz	w9, #0x0, 0x10000d1ac <_Io.Writer.printValue__anon_4310+0x1188>
10000d184: 528005a9    	mov	w9, #0x2d               ; =45
10000d188: 390077e9    	strb	w9, [sp, #0x1d]
10000d18c: 52800029    	mov	w9, #0x1                ; =1
10000d190: 5100076a    	sub	w10, w27, #0x1
10000d194: b000003a    	adrp	x26, 0x100012000 <___anon_4979+0x1f98>
10000d198: 912ae75a    	add	x26, x26, #0xab9
10000d19c: 71000d5f    	cmp	w10, #0x3
10000d1a0: 54000142    	b.hs	0x10000d1c8 <_Io.Writer.printValue__anon_4310+0x11a4>
10000d1a4: d280000f    	mov	x15, #0x0               ; =0
10000d1a8: 14000020    	b	0x10000d228 <_Io.Writer.printValue__anon_4310+0x1204>
10000d1ac: d2800009    	mov	x9, #0x0                ; =0
10000d1b0: 910077f5    	add	x21, sp, #0x1d
10000d1b4: 5100076a    	sub	w10, w27, #0x1
10000d1b8: b000003a    	adrp	x26, 0x100012000 <___anon_4979+0x1f98>
10000d1bc: 912ae75a    	add	x26, x26, #0xab9
10000d1c0: 71000d5f    	cmp	w10, #0x3
10000d1c4: 54ffff03    	b.lo	0x10000d1a4 <_Io.Writer.printValue__anon_4310+0x1180>
10000d1c8: d280000c    	mov	x12, #0x0               ; =0
10000d1cc: 910077eb    	add	x11, sp, #0x1d
10000d1d0: 8b0a012d    	add	x13, x9, x10
10000d1d4: 8b0b01ab    	add	x11, x13, x11
10000d1d8: 9100056b    	add	x11, x11, #0x1
10000d1dc: d29eb86d    	mov	x13, #0xf5c3            ; =62915
10000d1e0: f2ab850d    	movk	x13, #0x5c28, lsl #16
10000d1e4: f2d851ed    	movk	x13, #0xc28f, lsl #32
10000d1e8: f2e51ead    	movk	x13, #0x28f5, lsl #48
10000d1ec: 52800c8e    	mov	w14, #0x64              ; =100
10000d1f0: aa0803f0    	mov	x16, x8
10000d1f4: d342fe08    	lsr	x8, x16, #2
10000d1f8: 9bcd7d08    	umulh	x8, x8, x13
10000d1fc: d342fd08    	lsr	x8, x8, #2
10000d200: 9b0ec10f    	msub	x15, x8, x14, x16
10000d204: 786f7b4f    	ldrh	w15, [x26, x15, lsl #1]
10000d208: 781ff16f    	sturh	w15, [x11, #-0x1]
10000d20c: 9100098f    	add	x15, x12, #0x2
10000d210: d100096b    	sub	x11, x11, #0x2
10000d214: 91001191    	add	x17, x12, #0x4
10000d218: aa0f03ec    	mov	x12, x15
10000d21c: aa0803f0    	mov	x16, x8
10000d220: eb0a023f    	cmp	x17, x10
10000d224: 54fffe83    	b.lo	0x10000d1f4 <_Io.Writer.printValue__anon_4310+0x11d0>
10000d228: b27f012b    	orr	x11, x9, #0x2
10000d22c: eb0f014c    	subs	x12, x10, x15
10000d230: 54000209    	b.ls	0x10000d270 <_Io.Writer.printValue__anon_4310+0x124c>
10000d234: 910077ed    	add	x13, sp, #0x1d
10000d238: 8b0d012d    	add	x13, x9, x13
10000d23c: 910005ae    	add	x14, x13, #0x1
10000d240: b202e7ef    	mov	x15, #-0x3333333333333334 ; =-3689348814741910324
10000d244: f29999af    	movk	x15, #0xcccd
10000d248: 52800150    	mov	w16, #0xa               ; =10
10000d24c: 9bcf7d0d    	umulh	x13, x8, x15
10000d250: d343fdad    	lsr	x13, x13, #3
10000d254: 1b10a1a8    	msub	w8, w13, w16, w8
10000d258: 321c0508    	orr	w8, w8, #0x30
10000d25c: 382c69c8    	strb	w8, [x14, x12]
10000d260: aa0d03e8    	mov	x8, x13
10000d264: f100058c    	subs	x12, x12, #0x1
10000d268: 54ffff21    	b.ne	0x10000d24c <_Io.Writer.printValue__anon_4310+0x1228>
10000d26c: 14000002    	b	0x10000d274 <_Io.Writer.printValue__anon_4310+0x1250>
10000d270: aa0803ed    	mov	x13, x8
10000d274: b202e7e8    	mov	x8, #-0x3333333333333334 ; =-3689348814741910324
10000d278: f29999a8    	movk	x8, #0xcccd
10000d27c: 9bc87da8    	umulh	x8, x13, x8
10000d280: 53037d08    	lsr	w8, w8, #3
10000d284: 5280014c    	mov	w12, #0xa               ; =10
10000d288: 1b0cb508    	msub	w8, w8, w12, w13
10000d28c: 321c0508    	orr	w8, w8, #0x30
10000d290: 910077fc    	add	x28, sp, #0x1d
10000d294: 38296b88    	strb	w8, [x28, x9]
10000d298: 528005c8    	mov	w8, #0x2e               ; =46
10000d29c: 390006a8    	strb	w8, [x21, #0x1]
10000d2a0: 8b0a0168    	add	x8, x11, x10
10000d2a4: 7100077f    	cmp	w27, #0x1
10000d2a8: 9a89850c    	csinc	x12, x8, x9, hi
10000d2ac: 340001f8    	cbz	w24, 0x10000d2e8 <_Io.Writer.printValue__anon_4310+0x12c4>
10000d2b0: eb0a0295    	subs	x21, x20, x10
10000d2b4: 54000149    	b.ls	0x10000d2dc <_Io.Writer.printValue__anon_4310+0x12b8>
10000d2b8: 7100077f    	cmp	w27, #0x1
10000d2bc: 9a8c1594    	cinc	x20, x12, eq
10000d2c0: 910077e8    	add	x8, sp, #0x1d
10000d2c4: 8b140100    	add	x0, x8, x20
10000d2c8: 52800601    	mov	w1, #0x30               ; =48
10000d2cc: aa1503e2    	mov	x2, x21
10000d2d0: 940006ec    	bl	0x10000ee80 <dyld_stub_binder+0x10000ee80>
10000d2d4: 8b15028c    	add	x12, x20, x21
10000d2d8: 14000004    	b	0x10000d2e8 <_Io.Writer.printValue__anon_4310+0x12c4>
10000d2dc: f100029f    	cmp	x20, #0x0
10000d2e0: da9f1288    	csinv	x8, x20, xzr, ne
10000d2e4: 8b08016c    	add	x12, x11, x8
10000d2e8: 52800ca8    	mov	w8, #0x65               ; =101
10000d2ec: 382c6b88    	strb	w8, [x28, x12]
10000d2f0: 91000588    	add	x8, x12, #0x1
10000d2f4: b9401b29    	ldr	w9, [x25, #0x18]
10000d2f8: 0b1b012a    	add	w10, w9, w27
10000d2fc: 71000549    	subs	w9, w10, #0x1
10000d300: 5400010b    	b.lt	0x10000d320 <_Io.Writer.printValue__anon_4310+0x12fc>
10000d304: 52993fea    	mov	w10, #0xc9ff            ; =51711
10000d308: 72a7734a    	movk	w10, #0x3b9a, lsl #16
10000d30c: 6b0a013f    	cmp	w9, w10
10000d310: 540001c9    	b.ls	0x10000d348 <_Io.Writer.printValue__anon_4310+0x1324>
10000d314: 5280002c    	mov	w12, #0x1               ; =1
10000d318: 5280014a    	mov	w10, #0xa               ; =10
10000d31c: 14000011    	b	0x10000d360 <_Io.Writer.printValue__anon_4310+0x133c>
10000d320: 910077e9    	add	x9, sp, #0x1d
10000d324: 528005ab    	mov	w11, #0x2d              ; =45
10000d328: 3828692b    	strb	w11, [x9, x8]
10000d32c: 91000988    	add	x8, x12, #0x2
10000d330: 52800029    	mov	w9, #0x1                ; =1
10000d334: 4b0a0129    	sub	w9, w9, w10
10000d338: 52993fea    	mov	w10, #0xc9ff            ; =51711
10000d33c: 72a7734a    	movk	w10, #0x3b9a, lsl #16
10000d340: 6b0a013f    	cmp	w9, w10
10000d344: 54fffe88    	b.hi	0x10000d314 <_Io.Writer.printValue__anon_4310+0x12f0>
10000d348: 529c1fea    	mov	w10, #0xe0ff            ; =57599
10000d34c: 72a0beaa    	movk	w10, #0x5f5, lsl #16
10000d350: 6b0a013f    	cmp	w9, w10
10000d354: 540007c9    	b.ls	0x10000d44c <_Io.Writer.printValue__anon_4310+0x1428>
10000d358: 5280002c    	mov	w12, #0x1               ; =1
10000d35c: 5280012a    	mov	w10, #0x9               ; =9
10000d360: 5280002d    	mov	w13, #0x1               ; =1
10000d364: 5280002b    	mov	w11, #0x1               ; =1
10000d368: 910077ef    	add	x15, sp, #0x1d
10000d36c: 5290a3ee    	mov	w14, #0x851f            ; =34079
10000d370: 72aa3d6e    	movk	w14, #0x51eb, lsl #16
10000d374: 9bae7d2e    	umull	x14, w9, w14
10000d378: d365fdce    	lsr	x14, x14, #37
10000d37c: 52800c91    	mov	w17, #0x64              ; =100
10000d380: 1b11a5d0    	msub	w16, w14, w17, w9
10000d384: 78705b40    	ldrh	w0, [x26, w16, uxtw #1]
10000d388: 8b0801ef    	add	x15, x15, x8
10000d38c: 8b0a01f0    	add	x16, x15, x10
10000d390: 781fe200    	sturh	w0, [x16, #-0x2]
10000d394: 3600052c    	tbz	w12, #0x0, 0x10000d438 <_Io.Writer.printValue__anon_4310+0x1414>
10000d398: 528b852c    	mov	w12, #0x5c29            ; =23593
10000d39c: 72a051ec    	movk	w12, #0x28f, lsl #16
10000d3a0: 9bac7dc0    	umull	x0, w14, w12
10000d3a4: d360fc00    	lsr	x0, x0, #32
10000d3a8: 1b11b811    	msub	w17, w0, w17, w14
10000d3ac: 5282eb2e    	mov	w14, #0x1759            ; =5977
10000d3b0: 72ba36ee    	movk	w14, #0xd1b7, lsl #16
10000d3b4: 9bae7d2e    	umull	x14, w9, w14
10000d3b8: d36dfdce    	lsr	x14, x14, #45
10000d3bc: 78715b51    	ldrh	w17, [x26, w17, uxtw #1]
10000d3c0: 781fc211    	sturh	w17, [x16, #-0x4]
10000d3c4: 3400056d    	cbz	w13, 0x10000d470 <_Io.Writer.printValue__anon_4310+0x144c>
10000d3c8: 9bac7dcc    	umull	x12, w14, w12
10000d3cc: d360fd8d    	lsr	x13, x12, #32
10000d3d0: 52800c8c    	mov	w12, #0x64              ; =100
10000d3d4: 1b0cb9ad    	msub	w13, w13, w12, w14
10000d3d8: 529bd06e    	mov	w14, #0xde83            ; =56963
10000d3dc: 72a8636e    	movk	w14, #0x431b, lsl #16
10000d3e0: 9bae7d2e    	umull	x14, w9, w14
10000d3e4: d372fdce    	lsr	x14, x14, #50
10000d3e8: 786d5b50    	ldrh	w16, [x26, w13, uxtw #1]
10000d3ec: 8b0a01ed    	add	x13, x15, x10
10000d3f0: 781fa1b0    	sturh	w16, [x13, #-0x6]
10000d3f4: 340005ab    	cbz	w11, 0x10000d4a8 <_Io.Writer.printValue__anon_4310+0x1484>
10000d3f8: 528b852b    	mov	w11, #0x5c29            ; =23593
10000d3fc: 72a051eb    	movk	w11, #0x28f, lsl #16
10000d400: 9bab7dcb    	umull	x11, w14, w11
10000d404: d360fd6b    	lsr	x11, x11, #32
10000d408: 1b0cb96b    	msub	w11, w11, w12, w14
10000d40c: 5287712c    	mov	w12, #0x3b89            ; =15241
10000d410: 72aabccc    	movk	w12, #0x55e6, lsl #16
10000d414: 9bac7d29    	umull	x9, w9, w12
10000d418: d379fd2e    	lsr	x14, x9, #57
10000d41c: 786b5b49    	ldrh	w9, [x26, w11, uxtw #1]
10000d420: 781f81a9    	sturh	w9, [x13, #-0x8]
10000d424: 5280010b    	mov	w11, #0x8               ; =8
10000d428: aa0e03e9    	mov	x9, x14
10000d42c: eb0a017f    	cmp	x11, x10
10000d430: 54000443    	b.lo	0x10000d4b8 <_Io.Writer.printValue__anon_4310+0x1494>
10000d434: 14000030    	b	0x10000d4f4 <_Io.Writer.printValue__anon_4310+0x14d0>
10000d438: 5280004b    	mov	w11, #0x2               ; =2
10000d43c: aa0e03e9    	mov	x9, x14
10000d440: eb0a017f    	cmp	x11, x10
10000d444: 540003a3    	b.lo	0x10000d4b8 <_Io.Writer.printValue__anon_4310+0x1494>
10000d448: 1400002b    	b	0x10000d4f4 <_Io.Writer.printValue__anon_4310+0x14d0>
10000d44c: 5292cfea    	mov	w10, #0x967f            ; =38527
10000d450: 72a0130a    	movk	w10, #0x98, lsl #16
10000d454: 6b0a013f    	cmp	w9, w10
10000d458: 54000169    	b.ls	0x10000d484 <_Io.Writer.printValue__anon_4310+0x1460>
10000d45c: 5280000b    	mov	w11, #0x0               ; =0
10000d460: 5280002c    	mov	w12, #0x1               ; =1
10000d464: 5280010a    	mov	w10, #0x8               ; =8
10000d468: 5280002d    	mov	w13, #0x1               ; =1
10000d46c: 17ffffbf    	b	0x10000d368 <_Io.Writer.printValue__anon_4310+0x1344>
10000d470: 5280008b    	mov	w11, #0x4               ; =4
10000d474: aa0e03e9    	mov	x9, x14
10000d478: eb0a017f    	cmp	x11, x10
10000d47c: 540001e3    	b.lo	0x10000d4b8 <_Io.Writer.printValue__anon_4310+0x1494>
10000d480: 1400001d    	b	0x10000d4f4 <_Io.Writer.printValue__anon_4310+0x14d0>
10000d484: 528847ea    	mov	w10, #0x423f            ; =16959
10000d488: 72a001ea    	movk	w10, #0xf, lsl #16
10000d48c: 6b0a013f    	cmp	w9, w10
10000d490: 540005e9    	b.ls	0x10000d54c <_Io.Writer.printValue__anon_4310+0x1528>
10000d494: 5280000b    	mov	w11, #0x0               ; =0
10000d498: 5280002c    	mov	w12, #0x1               ; =1
10000d49c: 528000ea    	mov	w10, #0x7               ; =7
10000d4a0: 5280002d    	mov	w13, #0x1               ; =1
10000d4a4: 17ffffb1    	b	0x10000d368 <_Io.Writer.printValue__anon_4310+0x1344>
10000d4a8: 528000cb    	mov	w11, #0x6               ; =6
10000d4ac: aa0e03e9    	mov	x9, x14
10000d4b0: eb0a017f    	cmp	x11, x10
10000d4b4: 54000202    	b.hs	0x10000d4f4 <_Io.Writer.printValue__anon_4310+0x14d0>
10000d4b8: cb0b014b    	sub	x11, x10, x11
10000d4bc: 910077ec    	add	x12, sp, #0x1d
10000d4c0: 8b0c010c    	add	x12, x8, x12
10000d4c4: d100058c    	sub	x12, x12, #0x1
10000d4c8: 529999ad    	mov	w13, #0xcccd            ; =52429
10000d4cc: 72b9998d    	movk	w13, #0xcccc, lsl #16
10000d4d0: 5280014e    	mov	w14, #0xa               ; =10
10000d4d4: 9bad7d2f    	umull	x15, w9, w13
10000d4d8: d363fdef    	lsr	x15, x15, #35
10000d4dc: 1b0ea5e9    	msub	w9, w15, w14, w9
10000d4e0: 321c0529    	orr	w9, w9, #0x30
10000d4e4: 382b6989    	strb	w9, [x12, x11]
10000d4e8: aa0f03e9    	mov	x9, x15
10000d4ec: f100056b    	subs	x11, x11, #0x1
10000d4f0: 54ffff21    	b.ne	0x10000d4d4 <_Io.Writer.printValue__anon_4310+0x14b0>
10000d4f4: 52800009    	mov	w9, #0x0                ; =0
10000d4f8: 8b080148    	add	x8, x10, x8
10000d4fc: 7100013f    	cmp	w9, #0x0
10000d500: 528000e9    	mov	w9, #0x7                ; =7
10000d504: b000002a    	adrp	x10, 0x100012000 <___anon_4979+0x1f98>
10000d508: 912ac54a    	add	x10, x10, #0xab1
10000d50c: 9a890101    	csel	x1, x8, x9, eq
10000d510: 910077e8    	add	x8, sp, #0x1d
10000d514: 9a8a0100    	csel	x0, x8, x10, eq
10000d518: 710002ff    	cmp	w23, #0x0
10000d51c: 9a960022    	csel	x2, x1, x22, eq
10000d520: 39405be3    	ldrb	w3, [sp, #0x16]
10000d524: aa1303e4    	mov	x4, x19
10000d528: 9400007d    	bl	0x10000d71c <_Io.Writer.alignBuffer>
10000d52c: 9106c3ff    	add	sp, sp, #0x1b0
10000d530: a9457bfd    	ldp	x29, x30, [sp, #0x50]
10000d534: a9444ff4    	ldp	x20, x19, [sp, #0x40]
10000d538: a94357f6    	ldp	x22, x21, [sp, #0x30]
10000d53c: a9425ff8    	ldp	x24, x23, [sp, #0x20]
10000d540: a94167fa    	ldp	x26, x25, [sp, #0x10]
10000d544: a8c66ffc    	ldp	x28, x27, [sp], #0x60
10000d548: d65f03c0    	ret
10000d54c: 53057d2a    	lsr	w10, w9, #5
10000d550: 7130d15f    	cmp	w10, #0xc34
10000d554: 540000c9    	b.ls	0x10000d56c <_Io.Writer.printValue__anon_4310+0x1548>
10000d558: 5280000d    	mov	w13, #0x0               ; =0
10000d55c: 5280000b    	mov	w11, #0x0               ; =0
10000d560: 5280002c    	mov	w12, #0x1               ; =1
10000d564: 528000ca    	mov	w10, #0x6               ; =6
10000d568: 17ffff80    	b	0x10000d368 <_Io.Writer.printValue__anon_4310+0x1344>
10000d56c: 53047d2a    	lsr	w10, w9, #4
10000d570: 7109c15f    	cmp	w10, #0x270
10000d574: 540000c9    	b.ls	0x10000d58c <_Io.Writer.printValue__anon_4310+0x1568>
10000d578: 5280000d    	mov	w13, #0x0               ; =0
10000d57c: 5280000b    	mov	w11, #0x0               ; =0
10000d580: 5280002c    	mov	w12, #0x1               ; =1
10000d584: 528000aa    	mov	w10, #0x5               ; =5
10000d588: 17ffff78    	b	0x10000d368 <_Io.Writer.printValue__anon_4310+0x1344>
10000d58c: 710f9d3f    	cmp	w9, #0x3e7
10000d590: 540000c9    	b.ls	0x10000d5a8 <_Io.Writer.printValue__anon_4310+0x1584>
10000d594: 5280000c    	mov	w12, #0x0               ; =0
10000d598: 5280000d    	mov	w13, #0x0               ; =0
10000d59c: 5280000b    	mov	w11, #0x0               ; =0
10000d5a0: 5280008a    	mov	w10, #0x4               ; =4
10000d5a4: 17ffff71    	b	0x10000d368 <_Io.Writer.printValue__anon_4310+0x1344>
10000d5a8: 7101913f    	cmp	w9, #0x64
10000d5ac: 540000c3    	b.lo	0x10000d5c4 <_Io.Writer.printValue__anon_4310+0x15a0>
10000d5b0: 5280000c    	mov	w12, #0x0               ; =0
10000d5b4: 5280000d    	mov	w13, #0x0               ; =0
10000d5b8: 5280000b    	mov	w11, #0x0               ; =0
10000d5bc: 5280006a    	mov	w10, #0x3               ; =3
10000d5c0: 17ffff6a    	b	0x10000d368 <_Io.Writer.printValue__anon_4310+0x1344>
10000d5c4: d280000b    	mov	x11, #0x0               ; =0
10000d5c8: 7100253f    	cmp	w9, #0x9
10000d5cc: 5280002a    	mov	w10, #0x1               ; =1
10000d5d0: 9a8a954a    	cinc	x10, x10, hi
10000d5d4: 17ffffb9    	b	0x10000d4b8 <_Io.Writer.printValue__anon_4310+0x1494>

000000010000d5d8 <_Io.Writer.defaultFlush>:
10000d5d8: d10103ff    	sub	sp, sp, #0x40
10000d5dc: a90157f6    	stp	x22, x21, [sp, #0x10]
10000d5e0: a9024ff4    	stp	x20, x19, [sp, #0x20]
10000d5e4: a9037bfd    	stp	x29, x30, [sp, #0x30]
10000d5e8: 9100c3fd    	add	x29, sp, #0x30
10000d5ec: aa0003f3    	mov	x19, x0
10000d5f0: f9400008    	ldr	x8, [x0]
10000d5f4: f9400115    	ldr	x21, [x8]
10000d5f8: f0000074    	adrp	x20, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000d5fc: 91042294    	add	x20, x20, #0x108
10000d600: f9400e68    	ldr	x8, [x19, #0x18]
10000d604: b4000148    	cbz	x8, 0x10000d62c <_Io.Writer.defaultFlush+0x54>
10000d608: 910003e8    	mov	x8, sp
10000d60c: aa1303e0    	mov	x0, x19
10000d610: aa1403e1    	mov	x1, x20
10000d614: 52800022    	mov	w2, #0x1                ; =1
10000d618: 52800023    	mov	w3, #0x1                ; =1
10000d61c: d63f02a0    	blr	x21
10000d620: 794013e0    	ldrh	w0, [sp, #0x8]
10000d624: 34fffee0    	cbz	w0, 0x10000d600 <_Io.Writer.defaultFlush+0x28>
10000d628: 14000002    	b	0x10000d630 <_Io.Writer.defaultFlush+0x58>
10000d62c: 52800000    	mov	w0, #0x0                ; =0
10000d630: a9437bfd    	ldp	x29, x30, [sp, #0x30]
10000d634: a9424ff4    	ldp	x20, x19, [sp, #0x20]
10000d638: a94157f6    	ldp	x22, x21, [sp, #0x10]
10000d63c: 910103ff    	add	sp, sp, #0x40
10000d640: d65f03c0    	ret

000000010000d644 <_Io.Writer.defaultRebase>:
10000d644: a9412009    	ldp	x9, x8, [x0, #0x10]
10000d648: cb080129    	sub	x9, x9, x8
10000d64c: eb02013f    	cmp	x9, x2
10000d650: 540005a2    	b.hs	0x10000d704 <_Io.Writer.defaultRebase+0xc0>
10000d654: d10143ff    	sub	sp, sp, #0x50
10000d658: a9015ff8    	stp	x24, x23, [sp, #0x10]
10000d65c: a90257f6    	stp	x22, x21, [sp, #0x20]
10000d660: a9034ff4    	stp	x20, x19, [sp, #0x30]
10000d664: a9047bfd    	stp	x29, x30, [sp, #0x40]
10000d668: 910103fd    	add	x29, sp, #0x40
10000d66c: aa0203f4    	mov	x20, x2
10000d670: aa0103f5    	mov	x21, x1
10000d674: aa0003f3    	mov	x19, x0
10000d678: f0000076    	adrp	x22, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000d67c: 910422d6    	add	x22, x22, #0x108
10000d680: eb150109    	subs	x9, x8, x21
10000d684: 9a8933f8    	csel	x24, xzr, x9, lo
10000d688: cb180117    	sub	x23, x8, x24
10000d68c: f9000e78    	str	x24, [x19, #0x18]
10000d690: f9400268    	ldr	x8, [x19]
10000d694: f9400109    	ldr	x9, [x8]
10000d698: 910003e8    	mov	x8, sp
10000d69c: aa1303e0    	mov	x0, x19
10000d6a0: aa1603e1    	mov	x1, x22
10000d6a4: 52800022    	mov	w2, #0x1                ; =1
10000d6a8: 52800023    	mov	w3, #0x1                ; =1
10000d6ac: d63f0120    	blr	x9
10000d6b0: 794013e0    	ldrh	w0, [sp, #0x8]
10000d6b4: 350002c0    	cbnz	w0, 0x10000d70c <_Io.Writer.defaultRebase+0xc8>
10000d6b8: f9400e68    	ldr	x8, [x19, #0x18]
10000d6bc: f9400669    	ldr	x9, [x19, #0x8]
10000d6c0: 8b080120    	add	x0, x9, x8
10000d6c4: 8b180121    	add	x1, x9, x24
10000d6c8: aa1703e2    	mov	x2, x23
10000d6cc: 940005ea    	bl	0x10000ee74 <dyld_stub_binder+0x10000ee74>
10000d6d0: a9412269    	ldp	x9, x8, [x19, #0x10]
10000d6d4: 8b170108    	add	x8, x8, x23
10000d6d8: cb080129    	sub	x9, x9, x8
10000d6dc: f9000e68    	str	x8, [x19, #0x18]
10000d6e0: eb14013f    	cmp	x9, x20
10000d6e4: 54fffce3    	b.lo	0x10000d680 <_Io.Writer.defaultRebase+0x3c>
10000d6e8: 52800000    	mov	w0, #0x0                ; =0
10000d6ec: a9447bfd    	ldp	x29, x30, [sp, #0x40]
10000d6f0: a9434ff4    	ldp	x20, x19, [sp, #0x30]
10000d6f4: a94257f6    	ldp	x22, x21, [sp, #0x20]
10000d6f8: a9415ff8    	ldp	x24, x23, [sp, #0x10]
10000d6fc: 910143ff    	add	sp, sp, #0x50
10000d700: d65f03c0    	ret
10000d704: 52800000    	mov	w0, #0x0                ; =0
10000d708: d65f03c0    	ret
10000d70c: f9400e68    	ldr	x8, [x19, #0x18]
10000d710: 8b170108    	add	x8, x8, x23
10000d714: f9000e68    	str	x8, [x19, #0x18]
10000d718: 17fffff5    	b	0x10000d6ec <_Io.Writer.defaultRebase+0xa8>

000000010000d71c <_Io.Writer.alignBuffer>:
10000d71c: d101c3ff    	sub	sp, sp, #0x70
10000d720: a90267fa    	stp	x26, x25, [sp, #0x20]
10000d724: a9035ff8    	stp	x24, x23, [sp, #0x30]
10000d728: a90457f6    	stp	x22, x21, [sp, #0x40]
10000d72c: a9054ff4    	stp	x20, x19, [sp, #0x50]
10000d730: a9067bfd    	stp	x29, x30, [sp, #0x60]
10000d734: 910183fd    	add	x29, sp, #0x60
10000d738: aa0103f3    	mov	x19, x1
10000d73c: aa0003f4    	mov	x20, x0
10000d740: eb010048    	subs	x8, x2, x1
10000d744: 9a8833f5    	csel	x21, xzr, x8, lo
10000d748: 54000668    	b.hi	0x10000d814 <_Io.Writer.alignBuffer+0xf8>
10000d74c: b4000553    	cbz	x19, 0x10000d7f4 <_Io.Writer.alignBuffer+0xd8>
10000d750: d2800017    	mov	x23, #0x0               ; =0
10000d754: f0000068    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000d758: f940bd08    	ldr	x8, [x8, #0x178]
10000d75c: f0000078    	adrp	x24, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000d760: f0000075    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000d764: 910582b5    	add	x21, x21, #0x160
10000d768: f0000079    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000d76c: 9105a339    	add	x25, x25, #0x168
10000d770: 8b170281    	add	x1, x20, x23
10000d774: cb170276    	sub	x22, x19, x23
10000d778: 8b0802c9    	add	x9, x22, x8
10000d77c: f940bb0a    	ldr	x10, [x24, #0x170]
10000d780: eb0a013f    	cmp	x9, x10
10000d784: 54000188    	b.hi	0x10000d7b4 <_Io.Writer.alignBuffer+0x98>
10000d788: f9400329    	ldr	x9, [x25]
10000d78c: 8b080120    	add	x0, x9, x8
10000d790: aa1603e2    	mov	x2, x22
10000d794: 940005b5    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
10000d798: f9400b28    	ldr	x8, [x25, #0x10]
10000d79c: 8b160108    	add	x8, x8, x22
10000d7a0: f9000b28    	str	x8, [x25, #0x10]
10000d7a4: 8b1702d7    	add	x23, x22, x23
10000d7a8: eb1302ff    	cmp	x23, x19
10000d7ac: 54fffe23    	b.lo	0x10000d770 <_Io.Writer.alignBuffer+0x54>
10000d7b0: 14000011    	b	0x10000d7f4 <_Io.Writer.alignBuffer+0xd8>
10000d7b4: f94002a8    	ldr	x8, [x21]
10000d7b8: f9400109    	ldr	x9, [x8]
10000d7bc: a9005be1    	stp	x1, x22, [sp]
10000d7c0: 910043e8    	add	x8, sp, #0x10
10000d7c4: 910003e1    	mov	x1, sp
10000d7c8: aa1503e0    	mov	x0, x21
10000d7cc: 52800022    	mov	w2, #0x1                ; =1
10000d7d0: 52800023    	mov	w3, #0x1                ; =1
10000d7d4: d63f0120    	blr	x9
10000d7d8: 794033e0    	ldrh	w0, [sp, #0x18]
10000d7dc: 350000e0    	cbnz	w0, 0x10000d7f8 <_Io.Writer.alignBuffer+0xdc>
10000d7e0: f9400bf6    	ldr	x22, [sp, #0x10]
10000d7e4: f9400ea8    	ldr	x8, [x21, #0x18]
10000d7e8: 8b1702d7    	add	x23, x22, x23
10000d7ec: eb1302ff    	cmp	x23, x19
10000d7f0: 54fffc03    	b.lo	0x10000d770 <_Io.Writer.alignBuffer+0x54>
10000d7f4: 52800000    	mov	w0, #0x0                ; =0
10000d7f8: a9467bfd    	ldp	x29, x30, [sp, #0x60]
10000d7fc: a9454ff4    	ldp	x20, x19, [sp, #0x50]
10000d800: a94457f6    	ldp	x22, x21, [sp, #0x40]
10000d804: a9435ff8    	ldp	x24, x23, [sp, #0x30]
10000d808: a94267fa    	ldp	x26, x25, [sp, #0x20]
10000d80c: 9101c3ff    	add	sp, sp, #0x70
10000d810: d65f03c0    	ret
10000d814: 12000468    	and	w8, w3, #0x3
10000d818: 7100091f    	cmp	w8, #0x2
10000d81c: 54000240    	b.eq	0x10000d864 <_Io.Writer.alignBuffer+0x148>
10000d820: 7100051f    	cmp	w8, #0x1
10000d824: 540003c1    	b.ne	0x10000d89c <_Io.Writer.alignBuffer+0x180>
10000d828: d341fea1    	lsr	x1, x21, #1
10000d82c: aa0403f6    	mov	x22, x4
10000d830: aa0403e0    	mov	x0, x4
10000d834: 9400016e    	bl	0x10000ddec <_Io.Writer.splatByteAll>
10000d838: 72003c1f    	tst	w0, #0xffff
10000d83c: 54fffde1    	b.ne	0x10000d7f8 <_Io.Writer.alignBuffer+0xdc>
10000d840: aa1403e0    	mov	x0, x20
10000d844: aa1303e1    	mov	x1, x19
10000d848: 97fff9ba    	bl	0x10000bf30 <_Io.Writer.writeAll>
10000d84c: 72003c1f    	tst	w0, #0xffff
10000d850: 54fffd41    	b.ne	0x10000d7f8 <_Io.Writer.alignBuffer+0xdc>
10000d854: 910006a8    	add	x8, x21, #0x1
10000d858: d341fd01    	lsr	x1, x8, #1
10000d85c: aa1603e0    	mov	x0, x22
10000d860: 14000017    	b	0x10000d8bc <_Io.Writer.alignBuffer+0x1a0>
10000d864: aa0403e0    	mov	x0, x4
10000d868: aa1503e1    	mov	x1, x21
10000d86c: 94000160    	bl	0x10000ddec <_Io.Writer.splatByteAll>
10000d870: 72003c1f    	tst	w0, #0xffff
10000d874: 54fffc21    	b.ne	0x10000d7f8 <_Io.Writer.alignBuffer+0xdc>
10000d878: aa1403e0    	mov	x0, x20
10000d87c: aa1303e1    	mov	x1, x19
10000d880: a9467bfd    	ldp	x29, x30, [sp, #0x60]
10000d884: a9454ff4    	ldp	x20, x19, [sp, #0x50]
10000d888: a94457f6    	ldp	x22, x21, [sp, #0x40]
10000d88c: a9435ff8    	ldp	x24, x23, [sp, #0x30]
10000d890: a94267fa    	ldp	x26, x25, [sp, #0x20]
10000d894: 9101c3ff    	add	sp, sp, #0x70
10000d898: 17fff9a6    	b	0x10000bf30 <_Io.Writer.writeAll>
10000d89c: aa0403f6    	mov	x22, x4
10000d8a0: aa1403e0    	mov	x0, x20
10000d8a4: aa1303e1    	mov	x1, x19
10000d8a8: 97fff9a2    	bl	0x10000bf30 <_Io.Writer.writeAll>
10000d8ac: 72003c1f    	tst	w0, #0xffff
10000d8b0: 54fffa41    	b.ne	0x10000d7f8 <_Io.Writer.alignBuffer+0xdc>
10000d8b4: aa1603e0    	mov	x0, x22
10000d8b8: aa1503e1    	mov	x1, x21
10000d8bc: a9467bfd    	ldp	x29, x30, [sp, #0x60]
10000d8c0: a9454ff4    	ldp	x20, x19, [sp, #0x50]
10000d8c4: a94457f6    	ldp	x22, x21, [sp, #0x40]
10000d8c8: a9435ff8    	ldp	x24, x23, [sp, #0x30]
10000d8cc: a94267fa    	ldp	x26, x25, [sp, #0x20]
10000d8d0: 9101c3ff    	add	sp, sp, #0x70
10000d8d4: 14000146    	b	0x10000ddec <_Io.Writer.splatByteAll>

000000010000d8d8 <_fs.File.Reader.getSize>:
10000d8d8: d10303ff    	sub	sp, sp, #0xc0
10000d8dc: a90a4ff4    	stp	x20, x19, [sp, #0xa0]
10000d8e0: a90b7bfd    	stp	x29, x30, [sp, #0xb0]
10000d8e4: 9102c3fd    	add	x29, sp, #0xb0
10000d8e8: 39404028    	ldrb	w8, [x1, #0x10]
10000d8ec: 340000a8    	cbz	w8, 0x10000d900 <_fs.File.Reader.getSize+0x28>
10000d8f0: f9400428    	ldr	x8, [x1, #0x8]
10000d8f4: f9000008    	str	x8, [x0]
10000d8f8: 7900101f    	strh	wzr, [x0, #0x8]
10000d8fc: 14000004    	b	0x10000d90c <_fs.File.Reader.getSize+0x34>
10000d900: 79408c28    	ldrh	w8, [x1, #0x46]
10000d904: 340000c8    	cbz	w8, 0x10000d91c <_fs.File.Reader.getSize+0x44>
10000d908: 79001008    	strh	w8, [x0, #0x8]
10000d90c: a94b7bfd    	ldp	x29, x30, [sp, #0xb0]
10000d910: a94a4ff4    	ldp	x20, x19, [sp, #0xa0]
10000d914: 910303ff    	add	sp, sp, #0xc0
10000d918: d65f03c0    	ret
10000d91c: aa0003f4    	mov	x20, x0
10000d920: aa0103f3    	mov	x19, x1
10000d924: b9404020    	ldr	w0, [x1, #0x40]
10000d928: 6f00e400    	movi.2d	v0, #0000000000000000
10000d92c: ad0403e0    	stp	q0, q0, [sp, #0x80]
10000d930: ad0303e0    	stp	q0, q0, [sp, #0x60]
10000d934: ad0203e0    	stp	q0, q0, [sp, #0x40]
10000d938: ad0103e0    	stp	q0, q0, [sp, #0x20]
10000d93c: 3d8007e0    	str	q0, [sp, #0x10]
10000d940: 910043e1    	add	x1, sp, #0x10
10000d944: 94000555    	bl	0x10000ee98 <dyld_stub_binder+0x10000ee98>
10000d948: 3100041f    	cmn	w0, #0x1
10000d94c: 54000300    	b.eq	0x10000d9ac <_fs.File.Reader.getSize+0xd4>
10000d950: 79402be9    	ldrh	w9, [sp, #0x14]
10000d954: f9403be8    	ldr	x8, [sp, #0x70]
10000d958: 530c7d29    	lsr	w9, w9, #12
10000d95c: 531e752a    	lsl	w10, w9, #2
10000d960: 521b014a    	eor	w10, w10, #0x20
10000d964: d29494ab    	mov	x11, #0xa4a5            ; =42149
10000d968: f2b554cb    	movk	x11, #0xaaa6, lsl #16
10000d96c: f2d4274b    	movk	x11, #0xa13a, lsl #32
10000d970: f2e0144b    	movk	x11, #0xa2, lsl #48
10000d974: 9aca256a    	lsr	x10, x11, x10
10000d978: 5280014b    	mov	w11, #0xa               ; =10
10000d97c: 71001d3f    	cmp	w9, #0x7
10000d980: 1a8a0169    	csel	w9, w11, w10, eq
10000d984: 12000d29    	and	w9, w9, #0xf
10000d988: 39003be9    	strb	w9, [sp, #0xe]
10000d98c: 7100153f    	cmp	w9, #0x5
10000d990: 540002a1    	b.ne	0x10000d9e4 <_fs.File.Reader.getSize+0x10c>
10000d994: f9000668    	str	x8, [x19, #0x8]
10000d998: 52800029    	mov	w9, #0x1                ; =1
10000d99c: 39004269    	strb	w9, [x19, #0x10]
10000d9a0: 7900129f    	strh	wzr, [x20, #0x8]
10000d9a4: f9000288    	str	x8, [x20]
10000d9a8: 17ffffd9    	b	0x10000d90c <_fs.File.Reader.getSize+0x34>
10000d9ac: 94000538    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
10000d9b0: b9400008    	ldr	w8, [x0]
10000d9b4: 72003d1f    	tst	w8, #0xffff
10000d9b8: 54fffcc0    	b.eq	0x10000d950 <_fs.File.Reader.getSize+0x78>
10000d9bc: 52800289    	mov	w9, #0x14               ; =20
10000d9c0: 5280022a    	mov	w10, #0x11              ; =17
10000d9c4: 528000eb    	mov	w11, #0x7               ; =7
10000d9c8: 7100311f    	cmp	w8, #0xc
10000d9cc: 1a8b1129    	csel	w9, w9, w11, ne
10000d9d0: 7100351f    	cmp	w8, #0xd
10000d9d4: 1a890148    	csel	w8, w10, w9, eq
10000d9d8: 79008e68    	strh	w8, [x19, #0x46]
10000d9dc: 79001288    	strh	w8, [x20, #0x8]
10000d9e0: 17ffffcb    	b	0x10000d90c <_fs.File.Reader.getSize+0x34>
10000d9e4: 39412a68    	ldrb	w8, [x19, #0x4a]
10000d9e8: 521e0108    	eor	w8, w8, #0x4
10000d9ec: 12000908    	and	w8, w8, #0x7
10000d9f0: 0b080508    	add	w8, w8, w8, lsl #1
10000d9f4: 52800089    	mov	w9, #0x4                ; =4
10000d9f8: 72a00909    	movk	w9, #0x48, lsl #16
10000d9fc: 1ac82528    	lsr	w8, w9, w8
10000da00: 12000908    	and	w8, w8, #0x7
10000da04: 39012a68    	strb	w8, [x19, #0x4a]
10000da08: 528002c8    	mov	w8, #0x16               ; =22
10000da0c: 79008e68    	strh	w8, [x19, #0x46]
10000da10: d0000008    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000da14: 913bc108    	add	x8, x8, #0xef0
10000da18: 3dc00100    	ldr	q0, [x8]
10000da1c: 3d800280    	str	q0, [x20]
10000da20: 17ffffbb    	b	0x10000d90c <_fs.File.Reader.getSize+0x34>

000000010000da24 <_fs.File.Reader.seekBy>:
10000da24: a9ba6ffc    	stp	x28, x27, [sp, #-0x60]!
10000da28: a90167fa    	stp	x26, x25, [sp, #0x10]
10000da2c: a9025ff8    	stp	x24, x23, [sp, #0x20]
10000da30: a90357f6    	stp	x22, x21, [sp, #0x30]
10000da34: a9044ff4    	stp	x20, x19, [sp, #0x40]
10000da38: a9057bfd    	stp	x29, x30, [sp, #0x50]
10000da3c: 910143fd    	add	x29, sp, #0x50
10000da40: d106c3ff    	sub	sp, sp, #0x1b0
10000da44: aa0103f4    	mov	x20, x1
10000da48: aa0003f3    	mov	x19, x0
10000da4c: 39412808    	ldrb	w8, [x0, #0x4a]
10000da50: 12000908    	and	w8, w8, #0x7
10000da54: 7100051f    	cmp	w8, #0x1
10000da58: 540000ed    	b.le	0x10000da74 <_fs.File.Reader.seekBy+0x50>
10000da5c: 7100091f    	cmp	w8, #0x2
10000da60: 540000c0    	b.eq	0x10000da78 <_fs.File.Reader.seekBy+0x54>
10000da64: 71000d1f    	cmp	w8, #0x3
10000da68: 54001140    	b.eq	0x10000dc90 <_fs.File.Reader.seekBy+0x26c>
10000da6c: 79409260    	ldrh	w0, [x19, #0x48]
10000da70: 140000d2    	b	0x10000ddb8 <_fs.File.Reader.seekBy+0x394>
10000da74: 350010e8    	cbnz	w8, 0x10000dc90 <_fs.File.Reader.seekBy+0x26c>
10000da78: 79409268    	ldrh	w8, [x19, #0x48]
10000da7c: 34000fe8    	cbz	w8, 0x10000dc78 <_fs.File.Reader.seekBy+0x254>
10000da80: b4001554    	cbz	x20, 0x10000dd28 <_fs.File.Reader.seekBy+0x304>
10000da84: 910263e8    	add	x8, sp, #0x98
10000da88: 91002117    	add	x23, x8, #0x8
10000da8c: 92f00018    	mov	x24, #0x7fffffffffffffff ; =9223372036854775807
10000da90: 910063f9    	add	x25, sp, #0x18
10000da94: 5280101a    	mov	w26, #0x80              ; =128
10000da98: 5280009b    	mov	w27, #0x4               ; =4
10000da9c: 72a0091b    	movk	w27, #0x48, lsl #16
10000daa0: b9404275    	ldr	w21, [x19, #0x40]
10000daa4: f940027c    	ldr	x28, [x19]
10000daa8: 39412a68    	ldrb	w8, [x19, #0x4a]
10000daac: 12000908    	and	w8, w8, #0x7
10000dab0: 7100051f    	cmp	w8, #0x1
10000dab4: 540000cd    	b.le	0x10000dacc <_fs.File.Reader.seekBy+0xa8>
10000dab8: 7100091f    	cmp	w8, #0x2
10000dabc: 540000a0    	b.eq	0x10000dad0 <_fs.File.Reader.seekBy+0xac>
10000dac0: 71000d1f    	cmp	w8, #0x3
10000dac4: 540003e0    	b.eq	0x10000db40 <_fs.File.Reader.seekBy+0x11c>
10000dac8: 140000ba    	b	0x10000ddb0 <_fs.File.Reader.seekBy+0x38c>
10000dacc: 350003a8    	cbnz	w8, 0x10000db40 <_fs.File.Reader.seekBy+0x11c>
10000dad0: 79408e68    	ldrh	w8, [x19, #0x46]
10000dad4: 35000068    	cbnz	w8, 0x10000dae0 <_fs.File.Reader.seekBy+0xbc>
10000dad8: 79409268    	ldrh	w8, [x19, #0x48]
10000dadc: 34000608    	cbz	w8, 0x10000db9c <_fs.File.Reader.seekBy+0x178>
10000dae0: d2800016    	mov	x22, #0x0               ; =0
10000dae4: aa1703e8    	mov	x8, x23
10000dae8: aa1403e9    	mov	x9, x20
10000daec: f102013f    	cmp	x9, #0x80
10000daf0: 9a9a312a    	csel	x10, x9, x26, lo
10000daf4: a93fa919    	stp	x25, x10, [x8, #-0x8]
10000daf8: cb0a0129    	sub	x9, x9, x10
10000dafc: f100013f    	cmp	x9, #0x0
10000db00: fa4f1ac2    	ccmp	x22, #0xf, #0x2, ne
10000db04: 910006d6    	add	x22, x22, #0x1
10000db08: 91004108    	add	x8, x8, #0x10
10000db0c: 54ffff03    	b.lo	0x10000daec <_fs.File.Reader.seekBy+0xc8>
10000db10: 910263e1    	add	x1, sp, #0x98
10000db14: aa1503e0    	mov	x0, x21
10000db18: aa1603e2    	mov	x2, x22
10000db1c: 940004e8    	bl	0x10000eebc <dyld_stub_binder+0x10000eebc>
10000db20: b100041f    	cmn	x0, #0x1
10000db24: 540004a1    	b.ne	0x10000dbb8 <_fs.File.Reader.seekBy+0x194>
10000db28: 940004d9    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
10000db2c: b9400008    	ldr	w8, [x0]
10000db30: 12003d09    	and	w9, w8, #0xffff
10000db34: 7100113f    	cmp	w9, #0x4
10000db38: 54fffec0    	b.eq	0x10000db10 <_fs.File.Reader.seekBy+0xec>
10000db3c: 14000043    	b	0x10000dc48 <_fs.File.Reader.seekBy+0x224>
10000db40: 910023e0    	add	x0, sp, #0x8
10000db44: aa1303e1    	mov	x1, x19
10000db48: 97ffff64    	bl	0x10000d8d8 <_fs.File.Reader.getSize>
10000db4c: 794023e8    	ldrh	w8, [sp, #0x10]
10000db50: 34000148    	cbz	w8, 0x10000db78 <_fs.File.Reader.seekBy+0x154>
10000db54: d2800000    	mov	x0, #0x0                ; =0
10000db58: 39412a68    	ldrb	w8, [x19, #0x4a]
10000db5c: 521e0108    	eor	w8, w8, #0x4
10000db60: 12000908    	and	w8, w8, #0x7
10000db64: 0b080508    	add	w8, w8, w8, lsl #1
10000db68: 1ac82768    	lsr	w8, w27, w8
10000db6c: 12000908    	and	w8, w8, #0x7
10000db70: 39012a68    	strb	w8, [x19, #0x4a]
10000db74: 14000007    	b	0x10000db90 <_fs.File.Reader.seekBy+0x16c>
10000db78: f94007e8    	ldr	x8, [sp, #0x8]
10000db7c: cb1c0108    	sub	x8, x8, x28
10000db80: eb08029f    	cmp	x20, x8
10000db84: 9a883280    	csel	x0, x20, x8, lo
10000db88: 8b1c0008    	add	x8, x0, x28
10000db8c: f9000268    	str	x8, [x19]
10000db90: eb000294    	subs	x20, x20, x0
10000db94: 54fff861    	b.ne	0x10000daa0 <_fs.File.Reader.seekBy+0x7c>
10000db98: 14000064    	b	0x10000dd28 <_fs.File.Reader.seekBy+0x304>
10000db9c: d101a3a0    	sub	x0, x29, #0x68
10000dba0: aa1303e1    	mov	x1, x19
10000dba4: 97ffff4d    	bl	0x10000d8d8 <_fs.File.Reader.getSize>
10000dba8: 785a03a8    	ldurh	w8, [x29, #-0x60]
10000dbac: 340000a8    	cbz	w8, 0x10000dbc0 <_fs.File.Reader.seekBy+0x19c>
10000dbb0: d2800000    	mov	x0, #0x0                ; =0
10000dbb4: 17fffff7    	b	0x10000db90 <_fs.File.Reader.seekBy+0x16c>
10000dbb8: b5fffe80    	cbnz	x0, 0x10000db88 <_fs.File.Reader.seekBy+0x164>
10000dbbc: 14000087    	b	0x10000ddd8 <_fs.File.Reader.seekBy+0x3b4>
10000dbc0: f85983a8    	ldur	x8, [x29, #-0x68]
10000dbc4: cb1c0108    	sub	x8, x8, x28
10000dbc8: eb14011f    	cmp	x8, x20
10000dbcc: 9a943108    	csel	x8, x8, x20, lo
10000dbd0: eb18011f    	cmp	x8, x24
10000dbd4: 9a983101    	csel	x1, x8, x24, lo
10000dbd8: aa1503e0    	mov	x0, x21
10000dbdc: aa0103f5    	mov	x21, x1
10000dbe0: 52800022    	mov	w2, #0x1                ; =1
10000dbe4: 940004b0    	bl	0x10000eea4 <dyld_stub_binder+0x10000eea4>
10000dbe8: b100041f    	cmn	x0, #0x1
10000dbec: 54000080    	b.eq	0x10000dbfc <_fs.File.Reader.seekBy+0x1d8>
10000dbf0: aa1503e0    	mov	x0, x21
10000dbf4: 8b1c02a8    	add	x8, x21, x28
10000dbf8: 17ffffe5    	b	0x10000db8c <_fs.File.Reader.seekBy+0x168>
10000dbfc: 940004a4    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
10000dc00: b9400009    	ldr	w9, [x0]
10000dc04: 528002e8    	mov	w8, #0x17               ; =23
10000dc08: 7100553f    	cmp	w9, #0x15
10000dc0c: 5400014d    	b.le	0x10000dc34 <_fs.File.Reader.seekBy+0x210>
10000dc10: 7100593f    	cmp	w9, #0x16
10000dc14: 540000a0    	b.eq	0x10000dc28 <_fs.File.Reader.seekBy+0x204>
10000dc18: 7100753f    	cmp	w9, #0x1d
10000dc1c: 54000060    	b.eq	0x10000dc28 <_fs.File.Reader.seekBy+0x204>
10000dc20: 7101513f    	cmp	w9, #0x54
10000dc24: 540000e1    	b.ne	0x10000dc40 <_fs.File.Reader.seekBy+0x21c>
10000dc28: d2800000    	mov	x0, #0x0                ; =0
10000dc2c: 79009268    	strh	w8, [x19, #0x48]
10000dc30: 17ffffd8    	b	0x10000db90 <_fs.File.Reader.seekBy+0x16c>
10000dc34: 34fffde9    	cbz	w9, 0x10000dbf0 <_fs.File.Reader.seekBy+0x1cc>
10000dc38: 7100193f    	cmp	w9, #0x6
10000dc3c: 54ffff60    	b.eq	0x10000dc28 <_fs.File.Reader.seekBy+0x204>
10000dc40: 52800288    	mov	w8, #0x14               ; =20
10000dc44: 17fffff9    	b	0x10000dc28 <_fs.File.Reader.seekBy+0x204>
10000dc48: 7100891f    	cmp	w8, #0x22
10000dc4c: 5400040c    	b.gt	0x10000dccc <_fs.File.Reader.seekBy+0x2a8>
10000dc50: 7100211f    	cmp	w8, #0x8
10000dc54: 5400070d    	b.le	0x10000dd34 <_fs.File.Reader.seekBy+0x310>
10000dc58: 7100251f    	cmp	w8, #0x9
10000dc5c: 540009e0    	b.eq	0x10000dd98 <_fs.File.Reader.seekBy+0x374>
10000dc60: 7100311f    	cmp	w8, #0xc
10000dc64: 54000800    	b.eq	0x10000dd64 <_fs.File.Reader.seekBy+0x340>
10000dc68: 7100551f    	cmp	w8, #0x15
10000dc6c: 540009e1    	b.ne	0x10000dda8 <_fs.File.Reader.seekBy+0x384>
10000dc70: 52800108    	mov	w8, #0x8                ; =8
10000dc74: 1400004e    	b	0x10000ddac <_fs.File.Reader.seekBy+0x388>
10000dc78: b9404260    	ldr	w0, [x19, #0x40]
10000dc7c: aa1403e1    	mov	x1, x20
10000dc80: 52800022    	mov	w2, #0x1                ; =1
10000dc84: 94000488    	bl	0x10000eea4 <dyld_stub_binder+0x10000eea4>
10000dc88: b100041f    	cmn	x0, #0x1
10000dc8c: 54000340    	b.eq	0x10000dcf4 <_fs.File.Reader.seekBy+0x2d0>
10000dc90: f940026a    	ldr	x10, [x19]
10000dc94: a9432668    	ldp	x8, x9, [x19, #0x30]
10000dc98: 8b0a010b    	add	x11, x8, x10
10000dc9c: cb090169    	sub	x9, x11, x9
10000dca0: 8b140129    	add	x9, x9, x20
10000dca4: eb0a013f    	cmp	x9, x10
10000dca8: 54000062    	b.hs	0x10000dcb4 <_fs.File.Reader.seekBy+0x290>
10000dcac: 8b140108    	add	x8, x8, x20
10000dcb0: 14000004    	b	0x10000dcc0 <_fs.File.Reader.seekBy+0x29c>
10000dcb4: d2800008    	mov	x8, #0x0                ; =0
10000dcb8: f9001e7f    	str	xzr, [x19, #0x38]
10000dcbc: f9000269    	str	x9, [x19]
10000dcc0: 52800000    	mov	w0, #0x0                ; =0
10000dcc4: f9001a68    	str	x8, [x19, #0x30]
10000dcc8: 1400003c    	b	0x10000ddb8 <_fs.File.Reader.seekBy+0x394>
10000dccc: 7100d91f    	cmp	w8, #0x36
10000dcd0: 540003ed    	b.le	0x10000dd4c <_fs.File.Reader.seekBy+0x328>
10000dcd4: 7100dd1f    	cmp	w8, #0x37
10000dcd8: 54000460    	b.eq	0x10000dd64 <_fs.File.Reader.seekBy+0x340>
10000dcdc: 7100e51f    	cmp	w8, #0x39
10000dce0: 54000600    	b.eq	0x10000dda0 <_fs.File.Reader.seekBy+0x37c>
10000dce4: 7100f11f    	cmp	w8, #0x3c
10000dce8: 54000601    	b.ne	0x10000dda8 <_fs.File.Reader.seekBy+0x384>
10000dcec: 52800188    	mov	w8, #0xc                ; =12
10000dcf0: 1400002f    	b	0x10000ddac <_fs.File.Reader.seekBy+0x388>
10000dcf4: 94000466    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
10000dcf8: b9400009    	ldr	w9, [x0]
10000dcfc: 528002e8    	mov	w8, #0x17               ; =23
10000dd00: 7100553f    	cmp	w9, #0x15
10000dd04: 5400034d    	b.le	0x10000dd6c <_fs.File.Reader.seekBy+0x348>
10000dd08: 7100593f    	cmp	w9, #0x16
10000dd0c: 540000a0    	b.eq	0x10000dd20 <_fs.File.Reader.seekBy+0x2fc>
10000dd10: 7100753f    	cmp	w9, #0x1d
10000dd14: 54000060    	b.eq	0x10000dd20 <_fs.File.Reader.seekBy+0x2fc>
10000dd18: 7101513f    	cmp	w9, #0x54
10000dd1c: 540002e1    	b.ne	0x10000dd78 <_fs.File.Reader.seekBy+0x354>
10000dd20: 79009268    	strh	w8, [x19, #0x48]
10000dd24: b5ffeb14    	cbnz	x20, 0x10000da84 <_fs.File.Reader.seekBy+0x60>
10000dd28: 52800000    	mov	w0, #0x0                ; =0
10000dd2c: a9037e7f    	stp	xzr, xzr, [x19, #0x30]
10000dd30: 14000022    	b	0x10000ddb8 <_fs.File.Reader.seekBy+0x394>
10000dd34: 71000d1f    	cmp	w8, #0x3
10000dd38: 54000280    	b.eq	0x10000dd88 <_fs.File.Reader.seekBy+0x364>
10000dd3c: 7100151f    	cmp	w8, #0x5
10000dd40: 54000341    	b.ne	0x10000dda8 <_fs.File.Reader.seekBy+0x384>
10000dd44: 528000c8    	mov	w8, #0x6                ; =6
10000dd48: 14000019    	b	0x10000ddac <_fs.File.Reader.seekBy+0x388>
10000dd4c: 71008d1f    	cmp	w8, #0x23
10000dd50: 54000200    	b.eq	0x10000dd90 <_fs.File.Reader.seekBy+0x36c>
10000dd54: 7100d91f    	cmp	w8, #0x36
10000dd58: 54000281    	b.ne	0x10000dda8 <_fs.File.Reader.seekBy+0x384>
10000dd5c: 52800168    	mov	w8, #0xb                ; =11
10000dd60: 14000013    	b	0x10000ddac <_fs.File.Reader.seekBy+0x388>
10000dd64: 528000e8    	mov	w8, #0x7                ; =7
10000dd68: 14000011    	b	0x10000ddac <_fs.File.Reader.seekBy+0x388>
10000dd6c: 34fff929    	cbz	w9, 0x10000dc90 <_fs.File.Reader.seekBy+0x26c>
10000dd70: 7100193f    	cmp	w9, #0x6
10000dd74: 54fffd60    	b.eq	0x10000dd20 <_fs.File.Reader.seekBy+0x2fc>
10000dd78: 52800288    	mov	w8, #0x14               ; =20
10000dd7c: 79009268    	strh	w8, [x19, #0x48]
10000dd80: b5ffe834    	cbnz	x20, 0x10000da84 <_fs.File.Reader.seekBy+0x60>
10000dd84: 17ffffe9    	b	0x10000dd28 <_fs.File.Reader.seekBy+0x304>
10000dd88: 52800248    	mov	w8, #0x12               ; =18
10000dd8c: 14000008    	b	0x10000ddac <_fs.File.Reader.seekBy+0x388>
10000dd90: 528001e8    	mov	w8, #0xf                ; =15
10000dd94: 14000006    	b	0x10000ddac <_fs.File.Reader.seekBy+0x388>
10000dd98: 528001a8    	mov	w8, #0xd                ; =13
10000dd9c: 14000004    	b	0x10000ddac <_fs.File.Reader.seekBy+0x388>
10000dda0: 528001c8    	mov	w8, #0xe                ; =14
10000dda4: 14000002    	b	0x10000ddac <_fs.File.Reader.seekBy+0x388>
10000dda8: 52800288    	mov	w8, #0x14               ; =20
10000ddac: 79008a68    	strh	w8, [x19, #0x44]
10000ddb0: 52800060    	mov	w0, #0x3                ; =3
10000ddb4: 79009260    	strh	w0, [x19, #0x48]
10000ddb8: 9106c3ff    	add	sp, sp, #0x1b0
10000ddbc: a9457bfd    	ldp	x29, x30, [sp, #0x50]
10000ddc0: a9444ff4    	ldp	x20, x19, [sp, #0x40]
10000ddc4: a94357f6    	ldp	x22, x21, [sp, #0x30]
10000ddc8: a9425ff8    	ldp	x24, x23, [sp, #0x20]
10000ddcc: a94167fa    	ldp	x26, x25, [sp, #0x10]
10000ddd0: a8c66ffc    	ldp	x28, x27, [sp], #0x60
10000ddd4: d65f03c0    	ret
10000ddd8: f900067c    	str	x28, [x19, #0x8]
10000dddc: 52800028    	mov	w8, #0x1                ; =1
10000dde0: 39004268    	strb	w8, [x19, #0x10]
10000dde4: 52800080    	mov	w0, #0x4                ; =4
10000dde8: 17fffff3    	b	0x10000ddb4 <_fs.File.Reader.seekBy+0x390>

000000010000ddec <_Io.Writer.splatByteAll>:
10000ddec: b4000681    	cbz	x1, 0x10000debc <_Io.Writer.splatByteAll+0xd0>
10000ddf0: d10203ff    	sub	sp, sp, #0x80
10000ddf4: a90367fa    	stp	x26, x25, [sp, #0x30]
10000ddf8: a9045ff8    	stp	x24, x23, [sp, #0x40]
10000ddfc: a90557f6    	stp	x22, x21, [sp, #0x50]
10000de00: a9064ff4    	stp	x20, x19, [sp, #0x60]
10000de04: a9077bfd    	stp	x29, x30, [sp, #0x70]
10000de08: 9101c3fd    	add	x29, sp, #0x70
10000de0c: aa0103f3    	mov	x19, x1
10000de10: aa0003f4    	mov	x20, x0
10000de14: f0000075    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000de18: f940bea8    	ldr	x8, [x21, #0x178]
10000de1c: f0000076    	adrp	x22, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000de20: 91003ff7    	add	x23, sp, #0xf
10000de24: 52800038    	mov	w24, #0x1               ; =1
10000de28: f0000079    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000de2c: 9105a339    	add	x25, x25, #0x168
10000de30: f940bac9    	ldr	x9, [x22, #0x170]
10000de34: 8b13010a    	add	x10, x8, x19
10000de38: eb09015f    	cmp	x10, x9
10000de3c: 54000188    	b.hi	0x10000de6c <_Io.Writer.splatByteAll+0x80>
10000de40: f9400329    	ldr	x9, [x25]
10000de44: 8b080120    	add	x0, x9, x8
10000de48: aa1403e1    	mov	x1, x20
10000de4c: aa1303e2    	mov	x2, x19
10000de50: 9400040c    	bl	0x10000ee80 <dyld_stub_binder+0x10000ee80>
10000de54: f9400b28    	ldr	x8, [x25, #0x10]
10000de58: 8b130108    	add	x8, x8, x19
10000de5c: f9000b28    	str	x8, [x25, #0x10]
10000de60: eb130273    	subs	x19, x19, x19
10000de64: 54fffe61    	b.ne	0x10000de30 <_Io.Writer.splatByteAll+0x44>
10000de68: 1400000d    	b	0x10000de9c <_Io.Writer.splatByteAll+0xb0>
10000de6c: 39003ff4    	strb	w20, [sp, #0xf]
10000de70: a90163f7    	stp	x23, x24, [sp, #0x10]
10000de74: 910083e0    	add	x0, sp, #0x20
10000de78: 910043e1    	add	x1, sp, #0x10
10000de7c: aa1303e2    	mov	x2, x19
10000de80: 940000e0    	bl	0x10000e200 <_Io.Writer.writeSplat>
10000de84: 794053e0    	ldrh	w0, [sp, #0x28]
10000de88: 350000c0    	cbnz	w0, 0x10000dea0 <_Io.Writer.splatByteAll+0xb4>
10000de8c: f94013e9    	ldr	x9, [sp, #0x20]
10000de90: f940bea8    	ldr	x8, [x21, #0x178]
10000de94: eb090273    	subs	x19, x19, x9
10000de98: 54fffcc1    	b.ne	0x10000de30 <_Io.Writer.splatByteAll+0x44>
10000de9c: 52800000    	mov	w0, #0x0                ; =0
10000dea0: a9477bfd    	ldp	x29, x30, [sp, #0x70]
10000dea4: a9464ff4    	ldp	x20, x19, [sp, #0x60]
10000dea8: a94557f6    	ldp	x22, x21, [sp, #0x50]
10000deac: a9445ff8    	ldp	x24, x23, [sp, #0x40]
10000deb0: a94367fa    	ldp	x26, x25, [sp, #0x30]
10000deb4: 910203ff    	add	sp, sp, #0x80
10000deb8: d65f03c0    	ret
10000debc: 52800000    	mov	w0, #0x0                ; =0
10000dec0: d65f03c0    	ret

000000010000dec4 <_fmt.float.round__anon_5288>:
10000dec4: f9400028    	ldr	x8, [x1]
10000dec8: b9400829    	ldr	w9, [x1, #0x8]
10000decc: 92b207ea    	mov	x10, #-0x903f0001       ; =-2420047873
10000ded0: f2d0de4a    	movk	x10, #0x86f2, lsl #32
10000ded4: f2e0046a    	movk	x10, #0x23, lsl #48
10000ded8: eb0a011f    	cmp	x8, x10
10000dedc: 54000069    	b.ls	0x10000dee8 <_fmt.float.round__anon_5288+0x24>
10000dee0: 5280022a    	mov	w10, #0x11              ; =17
10000dee4: 14000059    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000dee8: d28fffea    	mov	x10, #0x7fff            ; =32767
10000deec: f2b498ca    	movk	x10, #0xa4c6, lsl #16
10000def0: f2d1afca    	movk	x10, #0x8d7e, lsl #32
10000def4: f2e0006a    	movk	x10, #0x3, lsl #48
10000def8: eb0a011f    	cmp	x8, x10
10000defc: 54000069    	b.ls	0x10000df08 <_fmt.float.round__anon_5288+0x44>
10000df00: 5280020a    	mov	w10, #0x10              ; =16
10000df04: 14000051    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000df08: d287ffea    	mov	x10, #0x3fff            ; =16383
10000df0c: f2a20f4a    	movk	x10, #0x107a, lsl #16
10000df10: f2cb5e6a    	movk	x10, #0x5af3, lsl #32
10000df14: eb0a011f    	cmp	x8, x10
10000df18: 54000069    	b.ls	0x10000df24 <_fmt.float.round__anon_5288+0x60>
10000df1c: 528001ea    	mov	w10, #0xf               ; =15
10000df20: 1400004a    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000df24: d293ffea    	mov	x10, #0x9fff            ; =40959
10000df28: f2a9ce4a    	movk	x10, #0x4e72, lsl #16
10000df2c: f2c1230a    	movk	x10, #0x918, lsl #32
10000df30: eb0a011f    	cmp	x8, x10
10000df34: 54000069    	b.ls	0x10000df40 <_fmt.float.round__anon_5288+0x7c>
10000df38: 528001ca    	mov	w10, #0xe               ; =14
10000df3c: 14000043    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000df40: d281ffea    	mov	x10, #0xfff             ; =4095
10000df44: f2ba94aa    	movk	x10, #0xd4a5, lsl #16
10000df48: f2c01d0a    	movk	x10, #0xe8, lsl #32
10000df4c: eb0a011f    	cmp	x8, x10
10000df50: 54000069    	b.ls	0x10000df5c <_fmt.float.round__anon_5288+0x98>
10000df54: 528001aa    	mov	w10, #0xd               ; =13
10000df58: 1400003c    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000df5c: d29cffea    	mov	x10, #0xe7ff            ; =59391
10000df60: f2a90eca    	movk	x10, #0x4876, lsl #16
10000df64: f2c002ea    	movk	x10, #0x17, lsl #32
10000df68: eb0a011f    	cmp	x8, x10
10000df6c: 54000069    	b.ls	0x10000df78 <_fmt.float.round__anon_5288+0xb4>
10000df70: 5280018a    	mov	w10, #0xc               ; =12
10000df74: 14000035    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000df78: d29c7fea    	mov	x10, #0xe3ff            ; =58367
10000df7c: f2aa816a    	movk	x10, #0x540b, lsl #16
10000df80: f2c0004a    	movk	x10, #0x2, lsl #32
10000df84: eb0a011f    	cmp	x8, x10
10000df88: 54000069    	b.ls	0x10000df94 <_fmt.float.round__anon_5288+0xd0>
10000df8c: 5280016a    	mov	w10, #0xb               ; =11
10000df90: 1400002e    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000df94: 52993fea    	mov	w10, #0xc9ff            ; =51711
10000df98: 72a7734a    	movk	w10, #0x3b9a, lsl #16
10000df9c: eb0a011f    	cmp	x8, x10
10000dfa0: 54000069    	b.ls	0x10000dfac <_fmt.float.round__anon_5288+0xe8>
10000dfa4: 5280014a    	mov	w10, #0xa               ; =10
10000dfa8: 14000028    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000dfac: 529c1fea    	mov	w10, #0xe0ff            ; =57599
10000dfb0: 72a0beaa    	movk	w10, #0x5f5, lsl #16
10000dfb4: eb0a011f    	cmp	x8, x10
10000dfb8: 54000069    	b.ls	0x10000dfc4 <_fmt.float.round__anon_5288+0x100>
10000dfbc: 5280012a    	mov	w10, #0x9               ; =9
10000dfc0: 14000022    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000dfc4: 5292cfea    	mov	w10, #0x967f            ; =38527
10000dfc8: 72a0130a    	movk	w10, #0x98, lsl #16
10000dfcc: eb0a011f    	cmp	x8, x10
10000dfd0: 54000069    	b.ls	0x10000dfdc <_fmt.float.round__anon_5288+0x118>
10000dfd4: 5280010a    	mov	w10, #0x8               ; =8
10000dfd8: 1400001c    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000dfdc: 528847ea    	mov	w10, #0x423f            ; =16959
10000dfe0: 72a001ea    	movk	w10, #0xf, lsl #16
10000dfe4: eb0a011f    	cmp	x8, x10
10000dfe8: 54000069    	b.ls	0x10000dff4 <_fmt.float.round__anon_5288+0x130>
10000dfec: 528000ea    	mov	w10, #0x7               ; =7
10000dff0: 14000016    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000dff4: d345fd0a    	lsr	x10, x8, #5
10000dff8: f130d15f    	cmp	x10, #0xc34
10000dffc: 54000069    	b.ls	0x10000e008 <_fmt.float.round__anon_5288+0x144>
10000e000: 528000ca    	mov	w10, #0x6               ; =6
10000e004: 14000011    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000e008: d344fd0a    	lsr	x10, x8, #4
10000e00c: f109c15f    	cmp	x10, #0x270
10000e010: 54000069    	b.ls	0x10000e01c <_fmt.float.round__anon_5288+0x158>
10000e014: 528000aa    	mov	w10, #0x5               ; =5
10000e018: 1400000c    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000e01c: f10f9d1f    	cmp	x8, #0x3e7
10000e020: 54000069    	b.ls	0x10000e02c <_fmt.float.round__anon_5288+0x168>
10000e024: 5280008a    	mov	w10, #0x4               ; =4
10000e028: 14000008    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000e02c: f1018d1f    	cmp	x8, #0x63
10000e030: 54000069    	b.ls	0x10000e03c <_fmt.float.round__anon_5288+0x178>
10000e034: 5280006a    	mov	w10, #0x3               ; =3
10000e038: 14000004    	b	0x10000e048 <_fmt.float.round__anon_5288+0x184>
10000e03c: f100251f    	cmp	x8, #0x9
10000e040: 5280002a    	mov	w10, #0x1               ; =1
10000e044: 1a8a954a    	cinc	w10, w10, hi
10000e048: 5100054b    	sub	w11, w10, #0x1
10000e04c: 8b09006c    	add	x12, x3, x9
10000e050: 8b0b018b    	add	x11, x12, x11
10000e054: 8b2a406c    	add	x12, x3, w10, uxtw
10000e058: 4b0903ed    	neg	w13, w9
10000e05c: eb0d018c    	subs	x12, x12, x13
10000e060: 9a8c33ec    	csel	x12, xzr, x12, lo
10000e064: 7100013f    	cmp	w9, #0x0
10000e068: 9a8cc16b    	csel	x11, x11, x12, gt
10000e06c: 7200005f    	tst	w2, #0x1
10000e070: 9a83056b    	csinc	x11, x11, x3, eq
10000e074: 2a0a03ec    	mov	w12, w10
10000e078: eb0c017f    	cmp	x11, x12
10000e07c: 540003c2    	b.hs	0x10000e0f4 <_fmt.float.round__anon_5288+0x230>
10000e080: aa2b03ed    	mvn	x13, x11
10000e084: ab0c01ac    	adds	x12, x13, x12
10000e088: 54000140    	b.eq	0x10000e0b0 <_fmt.float.round__anon_5288+0x1ec>
10000e08c: 0b090149    	add	w9, w10, w9
10000e090: b202e7ea    	mov	x10, #-0x3333333333333334 ; =-3689348814741910324
10000e094: f29999aa    	movk	x10, #0xcccd
10000e098: 9bca7d08    	umulh	x8, x8, x10
10000e09c: d343fd08    	lsr	x8, x8, #3
10000e0a0: f100058c    	subs	x12, x12, #0x1
10000e0a4: 54ffffa1    	b.ne	0x10000e098 <_fmt.float.round__anon_5288+0x1d4>
10000e0a8: 2a2b03ea    	mvn	w10, w11
10000e0ac: 0b0a0129    	add	w9, w9, w10
10000e0b0: b202e7ea    	mov	x10, #-0x3333333333333334 ; =-3689348814741910324
10000e0b4: f29999aa    	movk	x10, #0xcccd
10000e0b8: 9bca7d0a    	umulh	x10, x8, x10
10000e0bc: d343fd4a    	lsr	x10, x10, #3
10000e0c0: 5280014b    	mov	w11, #0xa               ; =10
10000e0c4: 9b0ba14b    	msub	x11, x10, x11, x8
10000e0c8: f100157f    	cmp	x11, #0x5
10000e0cc: 54000143    	b.lo	0x10000e0f4 <_fmt.float.round__anon_5288+0x230>
10000e0d0: 91000548    	add	x8, x10, #0x1
10000e0d4: 1100052a    	add	w10, w9, #0x1
10000e0d8: b201e7eb    	mov	x11, #-0x6666666666666667 ; =-7378697629483820647
10000e0dc: d241096b    	eor	x11, x11, #0x8000000000000003
10000e0e0: 9bcb7d0b    	umulh	x11, x8, x11
10000e0e4: 5280014c    	mov	w12, #0xa               ; =10
10000e0e8: 9b0ca16c    	msub	x12, x11, x12, x8
10000e0ec: b40000ec    	cbz	x12, 0x10000e108 <_fmt.float.round__anon_5288+0x244>
10000e0f0: aa0a03e9    	mov	x9, x10
10000e0f4: f9000008    	str	x8, [x0]
10000e0f8: b9000809    	str	w9, [x0, #0x8]
10000e0fc: 39403028    	ldrb	w8, [x1, #0xc]
10000e100: 39003008    	strb	w8, [x0, #0xc]
10000e104: d65f03c0    	ret
10000e108: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
10000e10c: a9017bfd    	stp	x29, x30, [sp, #0x10]
10000e110: 910043fd    	add	x29, sp, #0x10
10000e114: d2800004    	mov	x4, #0x0                ; =0
10000e118: b202e7ec    	mov	x12, #-0x3333333333333334 ; =-3689348814741910324
10000e11c: f29999ac    	movk	x12, #0xcccd
10000e120: b202e7ed    	mov	x13, #-0x3333333333333334 ; =-3689348814741910324
10000e124: d291eb8e    	mov	x14, #0x8f5c            ; =36700
10000e128: f2beb84e    	movk	x14, #0xf5c2, lsl #16
10000e12c: f2cb850e    	movk	x14, #0x5c28, lsl #32
10000e130: f2f851ee    	movk	x14, #0xc28f, lsl #48
10000e134: d28b852f    	mov	x15, #0x5c29            ; =23593
10000e138: f2b851ef    	movk	x15, #0xc28f, lsl #16
10000e13c: f2c51eaf    	movk	x15, #0x28f5, lsl #32
10000e140: f2f1eb8f    	movk	x15, #0x8f5c, lsl #48
10000e144: b201e7f0    	mov	x16, #-0x6666666666666667 ; =-7378697629483820647
10000e148: f2933350    	movk	x16, #0x999a
10000e14c: b201e7e2    	mov	x2, #-0x6666666666666667 ; =-7378697629483820647
10000e150: f2e33322    	movk	x2, #0x1999, lsl #48
10000e154: aa0803e5    	mov	x5, x8
10000e158: aa0403f1    	mov	x17, x4
10000e15c: aa0503e3    	mov	x3, x5
10000e160: 93c50484    	extr	x4, x4, x5, #0x1
10000e164: d341fe25    	lsr	x5, x17, #1
10000e168: ab050086    	adds	x6, x4, x5
10000e16c: 9a8634c6    	cinc	x6, x6, hs
10000e170: 9bcc7cc7    	umulh	x7, x6, x12
10000e174: d342fce7    	lsr	x7, x7, #2
10000e178: 8b0708e7    	add	x7, x7, x7, lsl #2
10000e17c: cb0700c6    	sub	x6, x6, x7
10000e180: eb060086    	subs	x6, x4, x6
10000e184: 9bcc7cc4    	umulh	x4, x6, x12
10000e188: 9b0d10c4    	madd	x4, x6, x13, x4
10000e18c: da1f00a5    	sbc	x5, x5, xzr
10000e190: 9b0c10a4    	madd	x4, x5, x12, x4
10000e194: 9b0c7cc5    	mul	x5, x6, x12
10000e198: f100287f    	cmp	x3, #0xa
10000e19c: fa1f023f    	sbcs	xzr, x17, xzr
10000e1a0: 1a9f27e7    	cset	w7, lo
10000e1a4: 9bcc7cb3    	umulh	x19, x5, x12
10000e1a8: 9b0e4cd3    	madd	x19, x6, x14, x19
10000e1ac: 9b0c4c93    	madd	x19, x4, x12, x19
10000e1b0: 9b0f7cc6    	mul	x6, x6, x15
10000e1b4: 93d304d4    	extr	x20, x6, x19, #0x1
10000e1b8: 93c60666    	extr	x6, x19, x6, #0x1
10000e1bc: eb1000df    	cmp	x6, x16
10000e1c0: fa02029f    	sbcs	xzr, x20, x2
10000e1c4: 1a9f27e6    	cset	w6, lo
10000e1c8: 6b0600ff    	cmp	w7, w6
10000e1cc: 54fffc61    	b.ne	0x10000e158 <_fmt.float.round__anon_5288+0x294>
10000e1d0: 11000929    	add	w9, w9, #0x2
10000e1d4: f100287f    	cmp	x3, #0xa
10000e1d8: fa1f023f    	sbcs	xzr, x17, xzr
10000e1dc: 1a8a3129    	csel	w9, w9, w10, lo
10000e1e0: 9a883168    	csel	x8, x11, x8, lo
10000e1e4: a9417bfd    	ldp	x29, x30, [sp, #0x10]
10000e1e8: a8c24ff4    	ldp	x20, x19, [sp], #0x20
10000e1ec: f9000008    	str	x8, [x0]
10000e1f0: b9000809    	str	w9, [x0, #0x8]
10000e1f4: 39403028    	ldrb	w8, [x1, #0xc]
10000e1f8: 39003008    	strb	w8, [x0, #0xc]
10000e1fc: d65f03c0    	ret

000000010000e200 <_Io.Writer.writeSplat>:
10000e200: d10183ff    	sub	sp, sp, #0x60
10000e204: a90167fa    	stp	x26, x25, [sp, #0x10]
10000e208: a9025ff8    	stp	x24, x23, [sp, #0x20]
10000e20c: a90357f6    	stp	x22, x21, [sp, #0x30]
10000e210: a9044ff4    	stp	x20, x19, [sp, #0x40]
10000e214: a9057bfd    	stp	x29, x30, [sp, #0x50]
10000e218: 910143fd    	add	x29, sp, #0x50
10000e21c: aa0203f4    	mov	x20, x2
10000e220: aa0003f3    	mov	x19, x0
10000e224: d0000069    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e228: 9105a129    	add	x9, x9, #0x168
10000e22c: f9400435    	ldr	x21, [x1, #0x8]
10000e230: 9b027eb7    	mul	x23, x21, x2
10000e234: a940a12a    	ldp	x10, x8, [x9, #0x8]
10000e238: 8b17010b    	add	x11, x8, x23
10000e23c: eb0a017f    	cmp	x11, x10
10000e240: 54000189    	b.ls	0x10000e270 <_Io.Writer.writeSplat+0x70>
10000e244: d0000060    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e248: 91058000    	add	x0, x0, #0x160
10000e24c: f9400008    	ldr	x8, [x0]
10000e250: f9400109    	ldr	x9, [x8]
10000e254: 910003e8    	mov	x8, sp
10000e258: 52800022    	mov	w2, #0x1                ; =1
10000e25c: aa1403e3    	mov	x3, x20
10000e260: d63f0120    	blr	x9
10000e264: 3dc003e0    	ldr	q0, [sp]
10000e268: 3d800260    	str	q0, [x19]
10000e26c: 1400001b    	b	0x10000e2d8 <_Io.Writer.writeSplat+0xd8>
10000e270: b4000315    	cbz	x21, 0x10000e2d0 <_Io.Writer.writeSplat+0xd0>
10000e274: f9400138    	ldr	x24, [x9]
10000e278: f9400036    	ldr	x22, [x1]
10000e27c: f10006bf    	cmp	x21, #0x1
10000e280: 54000141    	b.ne	0x10000e2a8 <_Io.Writer.writeSplat+0xa8>
10000e284: 394002c1    	ldrb	w1, [x22]
10000e288: 8b080300    	add	x0, x24, x8
10000e28c: aa1403e2    	mov	x2, x20
10000e290: 940002fc    	bl	0x10000ee80 <dyld_stub_binder+0x10000ee80>
10000e294: d0000068    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e298: f940bd09    	ldr	x9, [x8, #0x178]
10000e29c: 8b140129    	add	x9, x9, x20
10000e2a0: f900bd09    	str	x9, [x8, #0x178]
10000e2a4: 1400000b    	b	0x10000e2d0 <_Io.Writer.writeSplat+0xd0>
10000e2a8: d0000079    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e2ac: 8b080300    	add	x0, x24, x8
10000e2b0: aa1603e1    	mov	x1, x22
10000e2b4: aa1503e2    	mov	x2, x21
10000e2b8: 940002ec    	bl	0x10000ee68 <dyld_stub_binder+0x10000ee68>
10000e2bc: f940bf28    	ldr	x8, [x25, #0x178]
10000e2c0: 8b150108    	add	x8, x8, x21
10000e2c4: f900bf28    	str	x8, [x25, #0x178]
10000e2c8: f1000694    	subs	x20, x20, #0x1
10000e2cc: 54ffff01    	b.ne	0x10000e2ac <_Io.Writer.writeSplat+0xac>
10000e2d0: 7900127f    	strh	wzr, [x19, #0x8]
10000e2d4: f9000277    	str	x23, [x19]
10000e2d8: a9457bfd    	ldp	x29, x30, [sp, #0x50]
10000e2dc: a9444ff4    	ldp	x20, x19, [sp, #0x40]
10000e2e0: a94357f6    	ldp	x22, x21, [sp, #0x30]
10000e2e4: a9425ff8    	ldp	x24, x23, [sp, #0x20]
10000e2e8: a94167fa    	ldp	x26, x25, [sp, #0x10]
10000e2ec: 910183ff    	add	sp, sp, #0x60
10000e2f0: d65f03c0    	ret

000000010000e2f4 <_fs.File.Writer.sendFile>:
10000e2f4: d10383ff    	sub	sp, sp, #0xe0
10000e2f8: a90967fa    	stp	x26, x25, [sp, #0x90]
10000e2fc: a90a5ff8    	stp	x24, x23, [sp, #0xa0]
10000e300: a90b57f6    	stp	x22, x21, [sp, #0xb0]
10000e304: a90c4ff4    	stp	x20, x19, [sp, #0xc0]
10000e308: a90d7bfd    	stp	x29, x30, [sp, #0xd0]
10000e30c: 910343fd    	add	x29, sp, #0xd0
10000e310: aa0103f4    	mov	x20, x1
10000e314: aa0803f3    	mov	x19, x8
10000e318: a9432829    	ldp	x9, x10, [x1, #0x30]
10000e31c: f9401028    	ldr	x8, [x1, #0x20]
10000e320: 8b090118    	add	x24, x8, x9
10000e324: cb090157    	sub	x23, x10, x9
10000e328: eb170048    	subs	x8, x2, x23
10000e32c: 540001e9    	b.ls	0x10000e368 <_fs.File.Writer.sendFile+0x74>
10000e330: f940040b    	ldr	x11, [x0, #0x8]
10000e334: f9400c1a    	ldr	x26, [x0, #0x18]
10000e338: b9402015    	ldr	w21, [x0, #0x20]
10000e33c: b9404296    	ldr	w22, [x20, #0x40]
10000e340: 3940428c    	ldrb	w12, [x20, #0x10]
10000e344: 340003ac    	cbz	w12, 0x10000e3b8 <_fs.File.Writer.sendFile+0xc4>
10000e348: a940328d    	ldp	x13, x12, [x20]
10000e34c: eb0d019f    	cmp	x12, x13
10000e350: 54000341    	b.ne	0x10000e3b8 <_fs.File.Writer.sendFile+0xc4>
10000e354: eb09015f    	cmp	x10, x9
10000e358: 540005a1    	b.ne	0x10000e40c <_fs.File.Writer.sendFile+0x118>
10000e35c: b0000008    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000e360: 913c0108    	add	x8, x8, #0xf00
10000e364: 14000021    	b	0x10000e3e8 <_fs.File.Writer.sendFile+0xf4>
10000e368: a93a0bb8    	stp	x24, x2, [x29, #-0x60]
10000e36c: d10143a8    	sub	x8, x29, #0x50
10000e370: d10183a1    	sub	x1, x29, #0x60
10000e374: 52800022    	mov	w2, #0x1                ; =1
10000e378: 52800023    	mov	w3, #0x1                ; =1
10000e37c: 940000f1    	bl	0x10000e740 <_fs.File.Writer.drain>
10000e380: 785b83a8    	ldurh	w8, [x29, #-0x48]
10000e384: 35001928    	cbnz	w8, 0x10000e6a8 <_fs.File.Writer.sendFile+0x3b4>
10000e388: f85b03b5    	ldur	x21, [x29, #-0x50]
10000e38c: aa1403e0    	mov	x0, x20
10000e390: aa1503e1    	mov	x1, x21
10000e394: 97fffda4    	bl	0x10000da24 <_fs.File.Reader.seekBy>
10000e398: 72003c1f    	tst	w0, #0xffff
10000e39c: 52800068    	mov	w8, #0x3                ; =3
10000e3a0: 1a8803e8    	csel	w8, wzr, w8, eq
10000e3a4: f9000275    	str	x21, [x19]
10000e3a8: 79001268    	strh	w8, [x19, #0x8]
10000e3ac: b800a27f    	stur	wzr, [x19, #0xa]
10000e3b0: 79001e7f    	strh	wzr, [x19, #0xe]
10000e3b4: 1400000f    	b	0x10000e3f0 <_fs.File.Writer.sendFile+0xfc>
10000e3b8: aa0203ec    	mov	x12, x2
10000e3bc: 3940b80d    	ldrb	w13, [x0, #0x2e]
10000e3c0: 720009bf    	tst	w13, #0x7
10000e3c4: 54000061    	b.ne	0x10000e3d0 <_fs.File.Writer.sendFile+0xdc>
10000e3c8: 79404c0d    	ldrh	w13, [x0, #0x26]
10000e3cc: 3400024d    	cbz	w13, 0x10000e414 <_fs.File.Writer.sendFile+0x120>
10000e3d0: 79405408    	ldrh	w8, [x0, #0x2a]
10000e3d4: 35000068    	cbnz	w8, 0x10000e3e0 <_fs.File.Writer.sendFile+0xec>
10000e3d8: f9400288    	ldr	x8, [x20]
10000e3dc: b40002c8    	cbz	x8, 0x10000e434 <_fs.File.Writer.sendFile+0x140>
10000e3e0: b0000008    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000e3e4: 913c4108    	add	x8, x8, #0xf10
10000e3e8: 3dc00100    	ldr	q0, [x8]
10000e3ec: 3d800260    	str	q0, [x19]
10000e3f0: a94d7bfd    	ldp	x29, x30, [sp, #0xd0]
10000e3f4: a94c4ff4    	ldp	x20, x19, [sp, #0xc0]
10000e3f8: a94b57f6    	ldp	x22, x21, [sp, #0xb0]
10000e3fc: a94a5ff8    	ldp	x24, x23, [sp, #0xa0]
10000e400: a94967fa    	ldp	x26, x25, [sp, #0x90]
10000e404: 910383ff    	add	sp, sp, #0xe0
10000e408: d65f03c0    	ret
10000e40c: a93a5fb8    	stp	x24, x23, [x29, #-0x60]
10000e410: 17ffffd7    	b	0x10000e36c <_fs.File.Writer.sendFile+0x78>
10000e414: f9400282    	ldr	x2, [x20]
10000e418: b7fffdc2    	tbnz	x2, #0x3f, 0x10000e3d0 <_fs.File.Writer.sendFile+0xdc>
10000e41c: b400037a    	cbz	x26, 0x10000e488 <_fs.File.Writer.sendFile+0x194>
10000e420: a902ebeb    	stp	x11, x26, [sp, #0x28]
10000e424: 5280002b    	mov	w11, #0x1               ; =1
10000e428: eb09015f    	cmp	x10, x9
10000e42c: 540003a1    	b.ne	0x10000e4a0 <_fs.File.Writer.sendFile+0x1ac>
10000e430: 14000020    	b	0x10000e4b0 <_fs.File.Writer.sendFile+0x1bc>
10000e434: b100059f    	cmn	x12, #0x1
10000e438: 54fffd41    	b.ne	0x10000e3e0 <_fs.File.Writer.sendFile+0xec>
10000e43c: f85f8008    	ldur	x8, [x0, #-0x8]
10000e440: b5fffd08    	cbnz	x8, 0x10000e3e0 <_fs.File.Writer.sendFile+0xec>
10000e444: aa0003f9    	mov	x25, x0
10000e448: 910143e0    	add	x0, sp, #0x50
10000e44c: aa1403e1    	mov	x1, x20
10000e450: 97fffd22    	bl	0x10000d8d8 <_fs.File.Reader.getSize>
10000e454: 7940b3e8    	ldrh	w8, [sp, #0x58]
10000e458: 35fffc48    	cbnz	w8, 0x10000e3e0 <_fs.File.Writer.sendFile+0xec>
10000e45c: aa170348    	orr	x8, x26, x23
10000e460: b4000a48    	cbz	x8, 0x10000e5a8 <_fs.File.Writer.sendFile+0x2b4>
10000e464: 910183e0    	add	x0, sp, #0x60
10000e468: aa1903e1    	mov	x1, x25
10000e46c: aa1403e2    	mov	x2, x20
10000e470: aa1803e3    	mov	x3, x24
10000e474: aa1703e4    	mov	x4, x23
10000e478: 9400008d    	bl	0x10000e6ac <_fs.File.Writer.sendFileBuffered>
10000e47c: 3dc01be0    	ldr	q0, [sp, #0x60]
10000e480: 3d800260    	str	q0, [x19]
10000e484: 1400007e    	b	0x10000e67c <_fs.File.Writer.sendFile+0x388>
10000e488: eb09015f    	cmp	x10, x9
10000e48c: 54000081    	b.ne	0x10000e49c <_fs.File.Writer.sendFile+0x1a8>
10000e490: aa0003f7    	mov	x23, x0
10000e494: d2800004    	mov	x4, #0x0                ; =0
10000e498: 1400000d    	b	0x10000e4cc <_fs.File.Writer.sendFile+0x1d8>
10000e49c: 5280000b    	mov	w11, #0x0               ; =0
10000e4a0: 9100a3e9    	add	x9, sp, #0x28
10000e4a4: 8b2b5129    	add	x9, x9, w11, uxtw #4
10000e4a8: a9005d38    	stp	x24, x23, [x9]
10000e4ac: 1100056b    	add	w11, w11, #0x1
10000e4b0: aa0003f7    	mov	x23, x0
10000e4b4: 9100a3e9    	add	x9, sp, #0x28
10000e4b8: f90007e9    	str	x9, [sp, #0x8]
10000e4bc: b90013eb    	str	w11, [sp, #0x10]
10000e4c0: f9000fff    	str	xzr, [sp, #0x18]
10000e4c4: b90023ff    	str	wzr, [sp, #0x20]
10000e4c8: 910023e4    	add	x4, sp, #0x8
10000e4cc: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000e4d0: eb09011f    	cmp	x8, x9
10000e4d4: 9a893108    	csel	x8, x8, x9, lo
10000e4d8: f90027e8    	str	x8, [sp, #0x48]
10000e4dc: 910123e3    	add	x3, sp, #0x48
10000e4e0: aa1603e0    	mov	x0, x22
10000e4e4: aa1503e1    	mov	x1, x21
10000e4e8: 52800005    	mov	w5, #0x0                ; =0
10000e4ec: 94000277    	bl	0x10000eec8 <dyld_stub_binder+0x10000eec8>
10000e4f0: 3100041f    	cmn	w0, #0x1
10000e4f4: 540001e0    	b.eq	0x10000e530 <_fs.File.Writer.sendFile+0x23c>
10000e4f8: 79404ee8    	ldrh	w8, [x23, #0x26]
10000e4fc: 35000be8    	cbnz	w8, 0x10000e678 <_fs.File.Writer.sendFile+0x384>
10000e500: f94027e8    	ldr	x8, [sp, #0x48]
10000e504: b40006c8    	cbz	x8, 0x10000e5dc <_fs.File.Writer.sendFile+0x2e8>
10000e508: f9400ee9    	ldr	x9, [x23, #0x18]
10000e50c: eb090115    	subs	x21, x8, x9
10000e510: 54000742    	b.hs	0x10000e5f8 <_fs.File.Writer.sendFile+0x304>
10000e514: f94006e0    	ldr	x0, [x23, #0x8]
10000e518: cb080136    	sub	x22, x9, x8
10000e51c: 8b080001    	add	x1, x0, x8
10000e520: aa1603e2    	mov	x2, x22
10000e524: 94000254    	bl	0x10000ee74 <dyld_stub_binder+0x10000ee74>
10000e528: d2800015    	mov	x21, #0x0               ; =0
10000e52c: 14000034    	b	0x10000e5fc <_fs.File.Writer.sendFile+0x308>
10000e530: 94000257    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
10000e534: b9400008    	ldr	w8, [x0]
10000e538: 71007d1f    	cmp	w8, #0x1f
10000e53c: 5400024d    	b.le	0x10000e584 <_fs.File.Writer.sendFile+0x290>
10000e540: 51008108    	sub	w8, w8, #0x20
10000e544: 7100b91f    	cmp	w8, #0x2e
10000e548: 54000948    	b.hi	0x10000e670 <_fs.File.Writer.sendFile+0x37c>
10000e54c: 52800029    	mov	w9, #0x1                ; =1
10000e550: 9ac82129    	lsl	x9, x9, x8
10000e554: d284080a    	mov	x10, #0x2040            ; =8256
10000e558: f2c8000a    	movk	x10, #0x4000, lsl #32
10000e55c: ea0a013f    	tst	x9, x10
10000e560: 54000201    	b.ne	0x10000e5a0 <_fs.File.Writer.sendFile+0x2ac>
10000e564: 52800029    	mov	w9, #0x1                ; =1
10000e568: 9ac82129    	lsl	x9, x9, x8
10000e56c: 5280002a    	mov	w10, #0x1               ; =1
10000e570: 72a0400a    	movk	w10, #0x200, lsl #16
10000e574: ea0a013f    	tst	x9, x10
10000e578: 540005e0    	b.eq	0x10000e634 <_fs.File.Writer.sendFile+0x340>
10000e57c: 52800148    	mov	w8, #0xa                ; =10
10000e580: 1400003d    	b	0x10000e674 <_fs.File.Writer.sendFile+0x380>
10000e584: 34fffba8    	cbz	w8, 0x10000e4f8 <_fs.File.Writer.sendFile+0x204>
10000e588: 7100111f    	cmp	w8, #0x4
10000e58c: 54fffb60    	b.eq	0x10000e4f8 <_fs.File.Writer.sendFile+0x204>
10000e590: 7100151f    	cmp	w8, #0x5
10000e594: 540006e1    	b.ne	0x10000e670 <_fs.File.Writer.sendFile+0x37c>
10000e598: 528000c8    	mov	w8, #0x6                ; =6
10000e59c: 14000036    	b	0x10000e674 <_fs.File.Writer.sendFile+0x380>
10000e5a0: 52800448    	mov	w8, #0x22               ; =34
10000e5a4: 14000034    	b	0x10000e674 <_fs.File.Writer.sendFile+0x380>
10000e5a8: f9402bf7    	ldr	x23, [sp, #0x50]
10000e5ac: aa1603e0    	mov	x0, x22
10000e5b0: aa1503e1    	mov	x1, x21
10000e5b4: d2800002    	mov	x2, #0x0                ; =0
10000e5b8: 52800103    	mov	w3, #0x8                ; =8
10000e5bc: 9400021f    	bl	0x10000ee38 <dyld_stub_binder+0x10000ee38>
10000e5c0: 3100041f    	cmn	w0, #0x1
10000e5c4: 54000440    	b.eq	0x10000e64c <_fs.File.Writer.sendFile+0x358>
10000e5c8: f9000297    	str	x23, [x20]
10000e5cc: f81f8337    	stur	x23, [x25, #-0x8]
10000e5d0: 7900127f    	strh	wzr, [x19, #0x8]
10000e5d4: f9000277    	str	x23, [x19]
10000e5d8: 14000029    	b	0x10000e67c <_fs.File.Writer.sendFile+0x388>
10000e5dc: f9400288    	ldr	x8, [x20]
10000e5e0: f9000688    	str	x8, [x20, #0x8]
10000e5e4: 52800028    	mov	w8, #0x1                ; =1
10000e5e8: 39004288    	strb	w8, [x20, #0x10]
10000e5ec: b0000008    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000e5f0: 913c0108    	add	x8, x8, #0xf00
10000e5f4: 1400000a    	b	0x10000e61c <_fs.File.Writer.sendFile+0x328>
10000e5f8: d2800016    	mov	x22, #0x0               ; =0
10000e5fc: f9000ef6    	str	x22, [x23, #0x18]
10000e600: aa1403e0    	mov	x0, x20
10000e604: aa1503e1    	mov	x1, x21
10000e608: 97fffd07    	bl	0x10000da24 <_fs.File.Reader.seekBy>
10000e60c: 72003c1f    	tst	w0, #0xffff
10000e610: 540000c0    	b.eq	0x10000e628 <_fs.File.Writer.sendFile+0x334>
10000e614: b0000008    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000e618: 913cc108    	add	x8, x8, #0xf30
10000e61c: 3dc00100    	ldr	q0, [x8]
10000e620: 3d800260    	str	q0, [x19]
10000e624: 14000016    	b	0x10000e67c <_fs.File.Writer.sendFile+0x388>
10000e628: 7900127f    	strh	wzr, [x19, #0x8]
10000e62c: f9000275    	str	x21, [x19]
10000e630: 14000013    	b	0x10000e67c <_fs.File.Writer.sendFile+0x388>
10000e634: f1000d1f    	cmp	x8, #0x3
10000e638: 540001c1    	b.ne	0x10000e670 <_fs.File.Writer.sendFile+0x37c>
10000e63c: f94027e8    	ldr	x8, [sp, #0x48]
10000e640: b5fff5c8    	cbnz	x8, 0x10000e4f8 <_fs.File.Writer.sendFile+0x204>
10000e644: 528001e8    	mov	w8, #0xf                ; =15
10000e648: 1400000b    	b	0x10000e674 <_fs.File.Writer.sendFile+0x380>
10000e64c: 94000210    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
10000e650: b9400008    	ldr	w8, [x0]
10000e654: 7100551f    	cmp	w8, #0x15
10000e658: 5400014c    	b.gt	0x10000e680 <_fs.File.Writer.sendFile+0x38c>
10000e65c: 34fffb68    	cbz	w8, 0x10000e5c8 <_fs.File.Writer.sendFile+0x2d4>
10000e660: 7100311f    	cmp	w8, #0xc
10000e664: 540001a1    	b.ne	0x10000e698 <_fs.File.Writer.sendFile+0x3a4>
10000e668: 528004e8    	mov	w8, #0x27               ; =39
10000e66c: 1400000c    	b	0x10000e69c <_fs.File.Writer.sendFile+0x3a8>
10000e670: 52800288    	mov	w8, #0x14               ; =20
10000e674: 79004ee8    	strh	w8, [x23, #0x26]
10000e678: a9007e7f    	stp	xzr, xzr, [x19]
10000e67c: 17ffff5d    	b	0x10000e3f0 <_fs.File.Writer.sendFile+0xfc>
10000e680: 7100591f    	cmp	w8, #0x16
10000e684: 540000a0    	b.eq	0x10000e698 <_fs.File.Writer.sendFile+0x3a4>
10000e688: 7100b51f    	cmp	w8, #0x2d
10000e68c: 54000061    	b.ne	0x10000e698 <_fs.File.Writer.sendFile+0x3a4>
10000e690: 52800508    	mov	w8, #0x28               ; =40
10000e694: 14000002    	b	0x10000e69c <_fs.File.Writer.sendFile+0x3a8>
10000e698: 52800288    	mov	w8, #0x14               ; =20
10000e69c: 79005728    	strh	w8, [x25, #0x2a]
10000e6a0: a9007e7f    	stp	xzr, xzr, [x19]
10000e6a4: 17ffff53    	b	0x10000e3f0 <_fs.File.Writer.sendFile+0xfc>
10000e6a8: 17ffff3f    	b	0x10000e3a4 <_fs.File.Writer.sendFile+0xb0>

000000010000e6ac <_fs.File.Writer.sendFileBuffered>:
10000e6ac: d10143ff    	sub	sp, sp, #0x50
10000e6b0: a90257f6    	stp	x22, x21, [sp, #0x20]
10000e6b4: a9034ff4    	stp	x20, x19, [sp, #0x30]
10000e6b8: a9047bfd    	stp	x29, x30, [sp, #0x40]
10000e6bc: 910103fd    	add	x29, sp, #0x40
10000e6c0: aa0203f4    	mov	x20, x2
10000e6c4: aa0103e9    	mov	x9, x1
10000e6c8: aa0003f3    	mov	x19, x0
10000e6cc: a90013e3    	stp	x3, x4, [sp]
10000e6d0: 910043e8    	add	x8, sp, #0x10
10000e6d4: 910003e1    	mov	x1, sp
10000e6d8: aa0903e0    	mov	x0, x9
10000e6dc: 52800022    	mov	w2, #0x1                ; =1
10000e6e0: 52800023    	mov	w3, #0x1                ; =1
10000e6e4: 94000017    	bl	0x10000e740 <_fs.File.Writer.drain>
10000e6e8: 794033e8    	ldrh	w8, [sp, #0x18]
10000e6ec: 35000268    	cbnz	w8, 0x10000e738 <_fs.File.Writer.sendFileBuffered+0x8c>
10000e6f0: f9400bf5    	ldr	x21, [sp, #0x10]
10000e6f4: aa1403e0    	mov	x0, x20
10000e6f8: aa1503e1    	mov	x1, x21
10000e6fc: 97fffcca    	bl	0x10000da24 <_fs.File.Reader.seekBy>
10000e700: 72003c1f    	tst	w0, #0xffff
10000e704: 540000c0    	b.eq	0x10000e71c <_fs.File.Writer.sendFileBuffered+0x70>
10000e708: b0000008    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000e70c: 913cc108    	add	x8, x8, #0xf30
10000e710: 3dc00100    	ldr	q0, [x8]
10000e714: 3d800260    	str	q0, [x19]
10000e718: 14000003    	b	0x10000e724 <_fs.File.Writer.sendFileBuffered+0x78>
10000e71c: 7900127f    	strh	wzr, [x19, #0x8]
10000e720: f9000275    	str	x21, [x19]
10000e724: a9447bfd    	ldp	x29, x30, [sp, #0x40]
10000e728: a9434ff4    	ldp	x20, x19, [sp, #0x30]
10000e72c: a94257f6    	ldp	x22, x21, [sp, #0x20]
10000e730: 910143ff    	add	sp, sp, #0x50
10000e734: d65f03c0    	ret
10000e738: 79001268    	strh	w8, [x19, #0x8]
10000e73c: 17fffffa    	b	0x10000e724 <_fs.File.Writer.sendFileBuffered+0x78>

000000010000e740 <_fs.File.Writer.drain>:
10000e740: d10683ff    	sub	sp, sp, #0x1a0
10000e744: a9146ffc    	stp	x28, x27, [sp, #0x140]
10000e748: a91567fa    	stp	x26, x25, [sp, #0x150]
10000e74c: a9165ff8    	stp	x24, x23, [sp, #0x160]
10000e750: a91757f6    	stp	x22, x21, [sp, #0x170]
10000e754: a9184ff4    	stp	x20, x19, [sp, #0x180]
10000e758: a9197bfd    	stp	x29, x30, [sp, #0x190]
10000e75c: 910643fd    	add	x29, sp, #0x190
10000e760: aa0003f4    	mov	x20, x0
10000e764: aa0803f3    	mov	x19, x8
10000e768: f940040b    	ldr	x11, [x0, #0x8]
10000e76c: f9400c0c    	ldr	x12, [x0, #0x18]
10000e770: b40000ec    	cbz	x12, 0x10000e78c <_fs.File.Writer.drain+0x4c>
10000e774: a90033eb    	stp	x11, x12, [sp]
10000e778: 52800038    	mov	w24, #0x1               ; =1
10000e77c: b9402295    	ldr	w21, [x20, #0x20]
10000e780: f1000449    	subs	x9, x2, #0x1
10000e784: 540000c1    	b.ne	0x10000e79c <_fs.File.Writer.drain+0x5c>
10000e788: 1400001a    	b	0x10000e7f0 <_fs.File.Writer.drain+0xb0>
10000e78c: d2800018    	mov	x24, #0x0               ; =0
10000e790: b9402295    	ldr	w21, [x20, #0x20]
10000e794: f1000449    	subs	x9, x2, #0x1
10000e798: 540002c0    	b.eq	0x10000e7f0 <_fs.File.Writer.drain+0xb0>
10000e79c: 9100202a    	add	x10, x1, #0x8
10000e7a0: 910003ed    	mov	x13, sp
10000e7a4: 52800208    	mov	w8, #0x10               ; =16
10000e7a8: aa0903ee    	mov	x14, x9
10000e7ac: 14000004    	b	0x10000e7bc <_fs.File.Writer.drain+0x7c>
10000e7b0: 9100414a    	add	x10, x10, #0x10
10000e7b4: f10005ce    	subs	x14, x14, #0x1
10000e7b8: 54000140    	b.eq	0x10000e7e0 <_fs.File.Writer.drain+0xa0>
10000e7bc: f940014f    	ldr	x15, [x10]
10000e7c0: b4ffff8f    	cbz	x15, 0x10000e7b0 <_fs.File.Writer.drain+0x70>
10000e7c4: f85f8150    	ldur	x16, [x10, #-0x8]
10000e7c8: 8b1811b1    	add	x17, x13, x24, lsl #4
10000e7cc: a9003e30    	stp	x16, x15, [x17]
10000e7d0: f1003f1f    	cmp	x24, #0xf
10000e7d4: 54000e00    	b.eq	0x10000e994 <_fs.File.Writer.drain+0x254>
10000e7d8: 91000718    	add	x24, x24, #0x1
10000e7dc: 17fffff5    	b	0x10000e7b0 <_fs.File.Writer.drain+0x70>
10000e7e0: f100431f    	cmp	x24, #0x10
10000e7e4: 54000061    	b.ne	0x10000e7f0 <_fs.File.Writer.drain+0xb0>
10000e7e8: 52800208    	mov	w8, #0x10               ; =16
10000e7ec: 1400006a    	b	0x10000e994 <_fs.File.Writer.drain+0x254>
10000e7f0: b4000ce3    	cbz	x3, 0x10000e98c <_fs.File.Writer.drain+0x24c>
10000e7f4: 8b091028    	add	x8, x1, x9, lsl #4
10000e7f8: a9402909    	ldp	x9, x10, [x8]
10000e7fc: f1000468    	subs	x8, x3, #0x1
10000e800: 540000e1    	b.ne	0x10000e81c <_fs.File.Writer.drain+0xdc>
10000e804: b4000c4a    	cbz	x10, 0x10000e98c <_fs.File.Writer.drain+0x24c>
10000e808: 910003e8    	mov	x8, sp
10000e80c: 8b181108    	add	x8, x8, x24, lsl #4
10000e810: a9002909    	stp	x9, x10, [x8]
10000e814: 91000708    	add	x8, x24, #0x1
10000e818: 1400005f    	b	0x10000e994 <_fs.File.Writer.drain+0x254>
10000e81c: b4000b8a    	cbz	x10, 0x10000e98c <_fs.File.Writer.drain+0x24c>
10000e820: f100055f    	cmp	x10, #0x1
10000e824: 54000621    	b.ne	0x10000e8e8 <_fs.File.Writer.drain+0x1a8>
10000e828: f9400a88    	ldr	x8, [x20, #0x10]
10000e82c: 8b0c016a    	add	x10, x11, x12
10000e830: cb0c0108    	sub	x8, x8, x12
10000e834: d10243ab    	sub	x11, x29, #0x90
10000e838: f100fd1f    	cmp	x8, #0x3f
10000e83c: 9a8b8156    	csel	x22, x10, x11, hi
10000e840: 5280080a    	mov	w10, #0x40              ; =64
10000e844: 9a8a8119    	csel	x25, x8, x10, hi
10000e848: eb03033f    	cmp	x25, x3
10000e84c: 9a833337    	csel	x23, x25, x3, lo
10000e850: 39400121    	ldrb	w1, [x9]
10000e854: aa1603e0    	mov	x0, x22
10000e858: aa1703e2    	mov	x2, x23
10000e85c: aa0303fa    	mov	x26, x3
10000e860: 94000188    	bl	0x10000ee80 <dyld_stub_binder+0x10000ee80>
10000e864: 910003e8    	mov	x8, sp
10000e868: 8b181108    	add	x8, x8, x24, lsl #4
10000e86c: a9005d16    	stp	x22, x23, [x8]
10000e870: f1003f1f    	cmp	x24, #0xf
10000e874: 1a9f07ea    	cset	w10, ne
10000e878: cb170349    	sub	x9, x26, x23
10000e87c: eb19013f    	cmp	x9, x25
10000e880: fa4f8b04    	ccmp	x24, #0xf, #0x4, hi
10000e884: 54000220    	b.eq	0x10000e8c8 <_fs.File.Writer.drain+0x188>
10000e888: 91006108    	add	x8, x8, #0x18
10000e88c: cb1903eb    	neg	x11, x25
10000e890: aa1803ec    	mov	x12, x24
10000e894: aa0903ed    	mov	x13, x9
10000e898: a93fe516    	stp	x22, x25, [x8, #-0x8]
10000e89c: cb190129    	sub	x9, x9, x25
10000e8a0: f100399f    	cmp	x12, #0xe
10000e8a4: 1a9f07ea    	cset	w10, ne
10000e8a8: 91000598    	add	x24, x12, #0x1
10000e8ac: 8b0d016d    	add	x13, x11, x13
10000e8b0: eb1901bf    	cmp	x13, x25
10000e8b4: 540000a9    	b.ls	0x10000e8c8 <_fs.File.Writer.drain+0x188>
10000e8b8: 91004108    	add	x8, x8, #0x10
10000e8bc: f100399f    	cmp	x12, #0xe
10000e8c0: aa1803ec    	mov	x12, x24
10000e8c4: 54fffe81    	b.ne	0x10000e894 <_fs.File.Writer.drain+0x154>
10000e8c8: 91000708    	add	x8, x24, #0x1
10000e8cc: b4000649    	cbz	x9, 0x10000e994 <_fs.File.Writer.drain+0x254>
10000e8d0: 3400062a    	cbz	w10, 0x10000e994 <_fs.File.Writer.drain+0x254>
10000e8d4: 910003ea    	mov	x10, sp
10000e8d8: 8b081148    	add	x8, x10, x8, lsl #4
10000e8dc: a9002516    	stp	x22, x9, [x8]
10000e8e0: 91000b08    	add	x8, x24, #0x2
10000e8e4: 1400002c    	b	0x10000e994 <_fs.File.Writer.drain+0x254>
10000e8e8: 8b03030b    	add	x11, x24, x3
10000e8ec: 528001ec    	mov	w12, #0xf               ; =15
10000e8f0: cb18018c    	sub	x12, x12, x24
10000e8f4: eb0c011f    	cmp	x8, x12
10000e8f8: 9a8c3108    	csel	x8, x8, x12, lo
10000e8fc: 91000508    	add	x8, x8, #0x1
10000e900: f100211f    	cmp	x8, #0x8
10000e904: 540002a9    	b.ls	0x10000e958 <_fs.File.Writer.drain+0x218>
10000e908: f240090c    	ands	x12, x8, #0x7
10000e90c: 5280010d    	mov	w13, #0x8               ; =8
10000e910: 9a8c01ac    	csel	x12, x13, x12, eq
10000e914: cb0c0108    	sub	x8, x8, x12
10000e918: 8b08030c    	add	x12, x24, x8
10000e91c: 4e080d20    	dup.2d	v0, x9
10000e920: 9e670141    	fmov	d1, x10
10000e924: 6e014001    	ext.16b	v1, v0, v1, #0x8
10000e928: 4e181d40    	mov.d	v0[1], x10
10000e92c: 910003ed    	mov	x13, sp
10000e930: 8b1811ad    	add	x13, x13, x24, lsl #4
10000e934: 910101ad    	add	x13, x13, #0x40
10000e938: ad3e05a0    	stp	q0, q1, [x13, #-0x40]
10000e93c: ad3f05a0    	stp	q0, q1, [x13, #-0x20]
10000e940: ad0005a0    	stp	q0, q1, [x13]
10000e944: ad0105a0    	stp	q0, q1, [x13, #0x20]
10000e948: 910201ad    	add	x13, x13, #0x80
10000e94c: f1002108    	subs	x8, x8, #0x8
10000e950: 54ffff41    	b.ne	0x10000e938 <_fs.File.Writer.drain+0x1f8>
10000e954: aa0c03f8    	mov	x24, x12
10000e958: 910003e8    	mov	x8, sp
10000e95c: 8b181108    	add	x8, x8, x24, lsl #4
10000e960: 9100210c    	add	x12, x8, #0x8
10000e964: cb18016d    	sub	x13, x11, x24
10000e968: d1003f0e    	sub	x14, x24, #0xf
10000e96c: 52800208    	mov	w8, #0x10               ; =16
10000e970: a93fa989    	stp	x9, x10, [x12, #-0x8]
10000e974: b400010e    	cbz	x14, 0x10000e994 <_fs.File.Writer.drain+0x254>
10000e978: 9100418c    	add	x12, x12, #0x10
10000e97c: 910005ce    	add	x14, x14, #0x1
10000e980: f10005ad    	subs	x13, x13, #0x1
10000e984: 54ffff61    	b.ne	0x10000e970 <_fs.File.Writer.drain+0x230>
10000e988: aa0b03f8    	mov	x24, x11
10000e98c: aa1803e8    	mov	x8, x24
10000e990: b4000bf8    	cbz	x24, 0x10000eb0c <_fs.File.Writer.drain+0x3cc>
10000e994: 3940ba89    	ldrb	w9, [x20, #0x2e]
10000e998: 12000929    	and	w9, w9, #0x7
10000e99c: 7100053f    	cmp	w9, #0x1
10000e9a0: 540000cd    	b.le	0x10000e9b8 <_fs.File.Writer.drain+0x278>
10000e9a4: 7100093f    	cmp	w9, #0x2
10000e9a8: 540000a0    	b.eq	0x10000e9bc <_fs.File.Writer.drain+0x27c>
10000e9ac: 71000d3f    	cmp	w9, #0x3
10000e9b0: 540003c0    	b.eq	0x10000ea28 <_fs.File.Writer.drain+0x2e8>
10000e9b4: 140000dd    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000e9b8: 35000389    	cbnz	w9, 0x10000ea28 <_fs.File.Writer.drain+0x2e8>
10000e9bc: 52800209    	mov	w9, #0x10               ; =16
10000e9c0: f100411f    	cmp	x8, #0x10
10000e9c4: 9a893116    	csel	x22, x8, x9, lo
10000e9c8: 910003e1    	mov	x1, sp
10000e9cc: aa1503e0    	mov	x0, x21
10000e9d0: aa1603e2    	mov	x2, x22
10000e9d4: 94000140    	bl	0x10000eed4 <dyld_stub_binder+0x10000eed4>
10000e9d8: b100041f    	cmn	x0, #0x1
10000e9dc: 54000da1    	b.ne	0x10000eb90 <_fs.File.Writer.drain+0x450>
10000e9e0: 9400012b    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
10000e9e4: b9400008    	ldr	w8, [x0]
10000e9e8: 12003d09    	and	w9, w8, #0xffff
10000e9ec: 7100113f    	cmp	w9, #0x4
10000e9f0: 54fffec0    	b.eq	0x10000e9c8 <_fs.File.Writer.drain+0x288>
10000e9f4: 7100691f    	cmp	w8, #0x1a
10000e9f8: 5400076c    	b.gt	0x10000eae4 <_fs.File.Writer.drain+0x3a4>
10000e9fc: 7100211f    	cmp	w8, #0x8
10000ea00: 54000a4c    	b.gt	0x10000eb48 <_fs.File.Writer.drain+0x408>
10000ea04: 7100051f    	cmp	w8, #0x1
10000ea08: 54000fc0    	b.eq	0x10000ec00 <_fs.File.Writer.drain+0x4c0>
10000ea0c: 71000d1f    	cmp	w8, #0x3
10000ea10: 54000ec0    	b.eq	0x10000ebe8 <_fs.File.Writer.drain+0x4a8>
10000ea14: 7100151f    	cmp	w8, #0x5
10000ea18: 540010c1    	b.ne	0x10000ec30 <_fs.File.Writer.drain+0x4f0>
10000ea1c: 528000c8    	mov	w8, #0x6                ; =6
10000ea20: 79004a88    	strh	w8, [x20, #0x24]
10000ea24: 140000c1    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ea28: f85f8296    	ldur	x22, [x20, #-0x8]
10000ea2c: f94007e8    	ldr	x8, [sp, #0x8]
10000ea30: b4000728    	cbz	x8, 0x10000eb14 <_fs.File.Writer.drain+0x3d4>
10000ea34: f94003f8    	ldr	x24, [sp]
10000ea38: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000ea3c: eb09011f    	cmp	x8, x9
10000ea40: 9a893119    	csel	x25, x8, x9, lo
10000ea44: b000001a    	adrp	x26, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000ea48: 913d035a    	add	x26, x26, #0xf40
10000ea4c: aa1503e0    	mov	x0, x21
10000ea50: aa1803e1    	mov	x1, x24
10000ea54: aa1903e2    	mov	x2, x25
10000ea58: aa1603e3    	mov	x3, x22
10000ea5c: 94000115    	bl	0x10000eeb0 <dyld_stub_binder+0x10000eeb0>
10000ea60: aa0003f7    	mov	x23, x0
10000ea64: b100041f    	cmn	x0, #0x1
10000ea68: 54000aa1    	b.ne	0x10000ebbc <_fs.File.Writer.drain+0x47c>
10000ea6c: 94000108    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
10000ea70: b9400008    	ldr	w8, [x0]
10000ea74: 12003d09    	and	w9, w8, #0xffff
10000ea78: 7101513f    	cmp	w9, #0x54
10000ea7c: 54001168    	b.hi	0x10000eca8 <_fs.File.Writer.drain+0x568>
10000ea80: 10fffe69    	adr	x9, 0x10000ea4c <_fs.File.Writer.drain+0x30c>
10000ea84: 38686b4a    	ldrb	w10, [x26, x8]
10000ea88: 8b0a0929    	add	x9, x9, x10, lsl #2
10000ea8c: d61f0120    	br	x9
10000ea90: 3940ba88    	ldrb	w8, [x20, #0x2e]
10000ea94: 521e0108    	eor	w8, w8, #0x4
10000ea98: 12000908    	and	w8, w8, #0x7
10000ea9c: 0b080508    	add	w8, w8, w8, lsl #1
10000eaa0: 52800089    	mov	w9, #0x4                ; =4
10000eaa4: 72a00909    	movk	w9, #0x48, lsl #16
10000eaa8: 1ac82528    	lsr	w8, w9, w8
10000eaac: 12000908    	and	w8, w8, #0x7
10000eab0: 3900ba88    	strb	w8, [x20, #0x2e]
10000eab4: f85f8295    	ldur	x21, [x20, #-0x8]
10000eab8: b4001135    	cbz	x21, 0x10000ecdc <_fs.File.Writer.drain+0x59c>
10000eabc: f81f829f    	stur	xzr, [x20, #-0x8]
10000eac0: 3940ba88    	ldrb	w8, [x20, #0x2e]
10000eac4: 12000908    	and	w8, w8, #0x7
10000eac8: 7100051f    	cmp	w8, #0x1
10000eacc: 54000f4d    	b.le	0x10000ecb4 <_fs.File.Writer.drain+0x574>
10000ead0: 7100111f    	cmp	w8, #0x4
10000ead4: 54001080    	b.eq	0x10000ece4 <_fs.File.Writer.drain+0x5a4>
10000ead8: 71000d1f    	cmp	w8, #0x3
10000eadc: 54000ee1    	b.ne	0x10000ecb8 <_fs.File.Writer.drain+0x578>
10000eae0: 1400007e    	b	0x10000ecd8 <_fs.File.Writer.drain+0x598>
10000eae4: 7100891f    	cmp	w8, #0x22
10000eae8: 5400042c    	b.gt	0x10000eb6c <_fs.File.Writer.drain+0x42c>
10000eaec: 51006d09    	sub	w9, w8, #0x1b
10000eaf0: 7100093f    	cmp	w9, #0x2
10000eaf4: 540004a3    	b.lo	0x10000eb88 <_fs.File.Writer.drain+0x448>
10000eaf8: 7100811f    	cmp	w8, #0x20
10000eafc: 540009a1    	b.ne	0x10000ec30 <_fs.File.Writer.drain+0x4f0>
10000eb00: 52800148    	mov	w8, #0xa                ; =10
10000eb04: 79004a88    	strh	w8, [x20, #0x24]
10000eb08: 14000088    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000eb0c: a9007e7f    	stp	xzr, xzr, [x19]
10000eb10: 1400008a    	b	0x10000ed38 <_fs.File.Writer.drain+0x5f8>
10000eb14: d2800017    	mov	x23, #0x0               ; =0
10000eb18: 8b1702c8    	add	x8, x22, x23
10000eb1c: f81f8288    	stur	x8, [x20, #-0x8]
10000eb20: f9400e89    	ldr	x9, [x20, #0x18]
10000eb24: eb0902e8    	subs	x8, x23, x9
10000eb28: 54000562    	b.hs	0x10000ebd4 <_fs.File.Writer.drain+0x494>
10000eb2c: f9400680    	ldr	x0, [x20, #0x8]
10000eb30: cb170135    	sub	x21, x9, x23
10000eb34: 8b170001    	add	x1, x0, x23
10000eb38: aa1503e2    	mov	x2, x21
10000eb3c: 940000ce    	bl	0x10000ee74 <dyld_stub_binder+0x10000ee74>
10000eb40: d2800008    	mov	x8, #0x0                ; =0
10000eb44: 14000025    	b	0x10000ebd8 <_fs.File.Writer.drain+0x498>
10000eb48: 7100251f    	cmp	w8, #0x9
10000eb4c: 54000600    	b.eq	0x10000ec0c <_fs.File.Writer.drain+0x4cc>
10000eb50: 7100411f    	cmp	w8, #0x10
10000eb54: 54000500    	b.eq	0x10000ebf4 <_fs.File.Writer.drain+0x4b4>
10000eb58: 7100591f    	cmp	w8, #0x16
10000eb5c: 540006a1    	b.ne	0x10000ec30 <_fs.File.Writer.drain+0x4f0>
10000eb60: 528003c8    	mov	w8, #0x1e               ; =30
10000eb64: 79004a88    	strh	w8, [x20, #0x24]
10000eb68: 14000070    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000eb6c: 71008d1f    	cmp	w8, #0x23
10000eb70: 540005a0    	b.eq	0x10000ec24 <_fs.File.Writer.drain+0x4e4>
10000eb74: 7100d91f    	cmp	w8, #0x36
10000eb78: 54000500    	b.eq	0x10000ec18 <_fs.File.Writer.drain+0x4d8>
10000eb7c: 7101151f    	cmp	w8, #0x45
10000eb80: 54000581    	b.ne	0x10000ec30 <_fs.File.Writer.drain+0x4f0>
10000eb84: 52800348    	mov	w8, #0x1a               ; =26
10000eb88: 79004a88    	strh	w8, [x20, #0x24]
10000eb8c: 14000067    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000eb90: f85f8288    	ldur	x8, [x20, #-0x8]
10000eb94: 8b000108    	add	x8, x8, x0
10000eb98: f81f8288    	stur	x8, [x20, #-0x8]
10000eb9c: f9400e89    	ldr	x9, [x20, #0x18]
10000eba0: eb090008    	subs	x8, x0, x9
10000eba4: 54000182    	b.hs	0x10000ebd4 <_fs.File.Writer.drain+0x494>
10000eba8: f9400688    	ldr	x8, [x20, #0x8]
10000ebac: cb000135    	sub	x21, x9, x0
10000ebb0: 8b000101    	add	x1, x8, x0
10000ebb4: aa0803e0    	mov	x0, x8
10000ebb8: 17ffffe0    	b	0x10000eb38 <_fs.File.Writer.drain+0x3f8>
10000ebbc: f85f8296    	ldur	x22, [x20, #-0x8]
10000ebc0: 8b1702c8    	add	x8, x22, x23
10000ebc4: f81f8288    	stur	x8, [x20, #-0x8]
10000ebc8: f9400e89    	ldr	x9, [x20, #0x18]
10000ebcc: eb0902e8    	subs	x8, x23, x9
10000ebd0: 54fffae3    	b.lo	0x10000eb2c <_fs.File.Writer.drain+0x3ec>
10000ebd4: d2800015    	mov	x21, #0x0               ; =0
10000ebd8: f9000e95    	str	x21, [x20, #0x18]
10000ebdc: 7900127f    	strh	wzr, [x19, #0x8]
10000ebe0: f9000268    	str	x8, [x19]
10000ebe4: 14000055    	b	0x10000ed38 <_fs.File.Writer.drain+0x5f8>
10000ebe8: 52800248    	mov	w8, #0x12               ; =18
10000ebec: 79004a88    	strh	w8, [x20, #0x24]
10000ebf0: 1400004e    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ebf4: 528003a8    	mov	w8, #0x1d               ; =29
10000ebf8: 79004a88    	strh	w8, [x20, #0x24]
10000ebfc: 1400004b    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec00: 528002a8    	mov	w8, #0x15               ; =21
10000ec04: 79004a88    	strh	w8, [x20, #0x24]
10000ec08: 14000048    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec0c: 528003e8    	mov	w8, #0x1f               ; =31
10000ec10: 79004a88    	strh	w8, [x20, #0x24]
10000ec14: 14000045    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec18: 52800168    	mov	w8, #0xb                ; =11
10000ec1c: 79004a88    	strh	w8, [x20, #0x24]
10000ec20: 14000042    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec24: 528001e8    	mov	w8, #0xf                ; =15
10000ec28: 79004a88    	strh	w8, [x20, #0x24]
10000ec2c: 1400003f    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec30: 52800288    	mov	w8, #0x14               ; =20
10000ec34: 79004a88    	strh	w8, [x20, #0x24]
10000ec38: 1400003c    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec3c: 52800148    	mov	w8, #0xa                ; =10
10000ec40: 79004a88    	strh	w8, [x20, #0x24]
10000ec44: 14000039    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec48: 52800348    	mov	w8, #0x1a               ; =26
10000ec4c: 79004a88    	strh	w8, [x20, #0x24]
10000ec50: 14000036    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec54: 528002a8    	mov	w8, #0x15               ; =21
10000ec58: 79004a88    	strh	w8, [x20, #0x24]
10000ec5c: 14000033    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec60: 528003c8    	mov	w8, #0x1e               ; =30
10000ec64: 79004a88    	strh	w8, [x20, #0x24]
10000ec68: 14000030    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec6c: 528003e8    	mov	w8, #0x1f               ; =31
10000ec70: 79004a88    	strh	w8, [x20, #0x24]
10000ec74: 1400002d    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec78: 52800248    	mov	w8, #0x12               ; =18
10000ec7c: 79004a88    	strh	w8, [x20, #0x24]
10000ec80: 1400002a    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec84: 528001e8    	mov	w8, #0xf                ; =15
10000ec88: 79004a88    	strh	w8, [x20, #0x24]
10000ec8c: 14000027    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec90: 528000c8    	mov	w8, #0x6                ; =6
10000ec94: 79004a88    	strh	w8, [x20, #0x24]
10000ec98: 14000024    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ec9c: 528003a8    	mov	w8, #0x1d               ; =29
10000eca0: 79004a88    	strh	w8, [x20, #0x24]
10000eca4: 14000021    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000eca8: 52800288    	mov	w8, #0x14               ; =20
10000ecac: 79004a88    	strh	w8, [x20, #0x24]
10000ecb0: 1400001e    	b	0x10000ed28 <_fs.File.Writer.drain+0x5e8>
10000ecb4: 35000128    	cbnz	w8, 0x10000ecd8 <_fs.File.Writer.drain+0x598>
10000ecb8: 79405a88    	ldrh	w8, [x20, #0x2c]
10000ecbc: 35000328    	cbnz	w8, 0x10000ed20 <_fs.File.Writer.drain+0x5e0>
10000ecc0: b9402280    	ldr	w0, [x20, #0x20]
10000ecc4: aa1503e1    	mov	x1, x21
10000ecc8: 52800002    	mov	w2, #0x0                ; =0
10000eccc: 94000076    	bl	0x10000eea4 <dyld_stub_binder+0x10000eea4>
10000ecd0: b100041f    	cmn	x0, #0x1
10000ecd4: 540000e0    	b.eq	0x10000ecf0 <_fs.File.Writer.drain+0x5b0>
10000ecd8: f81f8295    	stur	x21, [x20, #-0x8]
10000ecdc: a9007e7f    	stp	xzr, xzr, [x19]
10000ece0: 14000016    	b	0x10000ed38 <_fs.File.Writer.drain+0x5f8>
10000ece4: 79405a88    	ldrh	w8, [x20, #0x2c]
10000ece8: 350001c8    	cbnz	w8, 0x10000ed20 <_fs.File.Writer.drain+0x5e0>
10000ecec: 17fffffc    	b	0x10000ecdc <_fs.File.Writer.drain+0x59c>
10000ecf0: 94000067    	bl	0x10000ee8c <dyld_stub_binder+0x10000ee8c>
10000ecf4: b9400009    	ldr	w9, [x0]
10000ecf8: 528002e8    	mov	w8, #0x17               ; =23
10000ecfc: 7100553f    	cmp	w9, #0x15
10000ed00: 540002cd    	b.le	0x10000ed58 <_fs.File.Writer.drain+0x618>
10000ed04: 7100593f    	cmp	w9, #0x16
10000ed08: 540000a0    	b.eq	0x10000ed1c <_fs.File.Writer.drain+0x5dc>
10000ed0c: 7100753f    	cmp	w9, #0x1d
10000ed10: 54000060    	b.eq	0x10000ed1c <_fs.File.Writer.drain+0x5dc>
10000ed14: 7101513f    	cmp	w9, #0x54
10000ed18: 54000261    	b.ne	0x10000ed64 <_fs.File.Writer.drain+0x624>
10000ed1c: 79005a88    	strh	w8, [x20, #0x2c]
10000ed20: 52800088    	mov	w8, #0x4                ; =4
10000ed24: 3900ba88    	strb	w8, [x20, #0x2e]
10000ed28: b0000008    	adrp	x8, 0x10000f000 <dyld_stub_binder+0x10000f000>
10000ed2c: 913c8108    	add	x8, x8, #0xf20
10000ed30: 3dc00100    	ldr	q0, [x8]
10000ed34: 3d800260    	str	q0, [x19]
10000ed38: a9597bfd    	ldp	x29, x30, [sp, #0x190]
10000ed3c: a9584ff4    	ldp	x20, x19, [sp, #0x180]
10000ed40: a95757f6    	ldp	x22, x21, [sp, #0x170]
10000ed44: a9565ff8    	ldp	x24, x23, [sp, #0x160]
10000ed48: a95567fa    	ldp	x26, x25, [sp, #0x150]
10000ed4c: a9546ffc    	ldp	x28, x27, [sp, #0x140]
10000ed50: 910683ff    	add	sp, sp, #0x1a0
10000ed54: d65f03c0    	ret
10000ed58: 34fffc09    	cbz	w9, 0x10000ecd8 <_fs.File.Writer.drain+0x598>
10000ed5c: 7100193f    	cmp	w9, #0x6
10000ed60: 54fffde0    	b.eq	0x10000ed1c <_fs.File.Writer.drain+0x5dc>
10000ed64: 52800288    	mov	w8, #0x14               ; =20
10000ed68: 17ffffed    	b	0x10000ed1c <_fs.File.Writer.drain+0x5dc>

000000010000ed6c <_sigemptyset__thunk>:
10000ed6c: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ed70: 91397210    	add	x16, x16, #0xe5c
10000ed74: d61f0200    	br	x16

000000010000ed78 <___error__thunk>:
10000ed78: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ed7c: 913a3210    	add	x16, x16, #0xe8c
10000ed80: d61f0200    	br	x16

000000010000ed84 <_sigaction__thunk>:
10000ed84: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ed88: 91394210    	add	x16, x16, #0xe50
10000ed8c: d61f0200    	br	x16

000000010000ed90 <_memcpy__thunk>:
10000ed90: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ed94: 9139a210    	add	x16, x16, #0xe68
10000ed98: d61f0200    	br	x16

000000010000ed9c <_os_unfair_lock_unlock__thunk>:
10000ed9c: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000eda0: 913bb210    	add	x16, x16, #0xeec
10000eda4: d61f0200    	br	x16

000000010000eda8 <_clock_gettime__thunk>:
10000eda8: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000edac: 91391210    	add	x16, x16, #0xe44
10000edb0: d61f0200    	br	x16

000000010000edb4 <_pthread_threadid_np__thunk>:
10000edb4: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000edb8: 913be210    	add	x16, x16, #0xef8
10000edbc: d61f0200    	br	x16

000000010000edc0 <_os_unfair_lock_lock__thunk>:
10000edc0: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000edc4: 913b8210    	add	x16, x16, #0xee0
10000edc8: d61f0200    	br	x16

000000010000edcc <_memset__thunk>:
10000edcc: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000edd0: 913a0210    	add	x16, x16, #0xe80
10000edd4: d61f0200    	br	x16

000000010000edd8 <_memmove__thunk>:
10000edd8: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000eddc: 9139d210    	add	x16, x16, #0xe74
10000ede0: d61f0200    	br	x16

000000010000ede4 <_fstat__thunk>:
10000ede4: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ede8: 913a6210    	add	x16, x16, #0xe98
10000edec: d61f0200    	br	x16

000000010000edf0 <_readv__thunk>:
10000edf0: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000edf4: 913af210    	add	x16, x16, #0xebc
10000edf8: d61f0200    	br	x16

000000010000edfc <_lseek__thunk>:
10000edfc: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ee00: 913a9210    	add	x16, x16, #0xea4
10000ee04: d61f0200    	br	x16

000000010000ee08 <_sendfile__thunk>:
10000ee08: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ee0c: 913b2210    	add	x16, x16, #0xec8
10000ee10: d61f0200    	br	x16

000000010000ee14 <_fcopyfile__thunk>:
10000ee14: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ee18: 9138e210    	add	x16, x16, #0xe38
10000ee1c: d61f0200    	br	x16

000000010000ee20 <_writev__thunk>:
10000ee20: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ee24: 913b5210    	add	x16, x16, #0xed4
10000ee28: d61f0200    	br	x16

000000010000ee2c <_pwrite__thunk>:
10000ee2c: 90000010    	adrp	x16, 0x10000e000 <_fmt.float.round__anon_5288+0x13c>
10000ee30: 913ac210    	add	x16, x16, #0xeb0
10000ee34: d61f0200    	br	x16

Disassembly of section __TEXT,__stubs:

000000010000ee38 <__stubs>:
10000ee38: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ee3c: f9400210    	ldr	x16, [x16]
10000ee40: d61f0200    	br	x16
10000ee44: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ee48: f9400610    	ldr	x16, [x16, #0x8]
10000ee4c: d61f0200    	br	x16
10000ee50: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ee54: f9400a10    	ldr	x16, [x16, #0x10]
10000ee58: d61f0200    	br	x16
10000ee5c: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ee60: f9400e10    	ldr	x16, [x16, #0x18]
10000ee64: d61f0200    	br	x16
10000ee68: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ee6c: f9401210    	ldr	x16, [x16, #0x20]
10000ee70: d61f0200    	br	x16
10000ee74: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ee78: f9401610    	ldr	x16, [x16, #0x28]
10000ee7c: d61f0200    	br	x16
10000ee80: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ee84: f9401a10    	ldr	x16, [x16, #0x30]
10000ee88: d61f0200    	br	x16
10000ee8c: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ee90: f9401e10    	ldr	x16, [x16, #0x38]
10000ee94: d61f0200    	br	x16
10000ee98: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ee9c: f9402210    	ldr	x16, [x16, #0x40]
10000eea0: d61f0200    	br	x16
10000eea4: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000eea8: f9402610    	ldr	x16, [x16, #0x48]
10000eeac: d61f0200    	br	x16
10000eeb0: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000eeb4: f9402a10    	ldr	x16, [x16, #0x50]
10000eeb8: d61f0200    	br	x16
10000eebc: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000eec0: f9402e10    	ldr	x16, [x16, #0x58]
10000eec4: d61f0200    	br	x16
10000eec8: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000eecc: f9403210    	ldr	x16, [x16, #0x60]
10000eed0: d61f0200    	br	x16
10000eed4: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000eed8: f9403610    	ldr	x16, [x16, #0x68]
10000eedc: d61f0200    	br	x16
10000eee0: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000eee4: f9403a10    	ldr	x16, [x16, #0x70]
10000eee8: d61f0200    	br	x16
10000eeec: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000eef0: f9403e10    	ldr	x16, [x16, #0x78]
10000eef4: d61f0200    	br	x16
10000eef8: d0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000eefc: f9404210    	ldr	x16, [x16, #0x80]
10000ef00: d61f0200    	br	x16

Disassembly of section __TEXT,__stub_helper:

000000010000ef04 <__stub_helper>:
10000ef04: d0000071    	adrp	x17, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ef08: 9104e231    	add	x17, x17, #0x138
10000ef0c: a9bf47f0    	stp	x16, x17, [sp, #-0x10]!
10000ef10: d0000050    	adrp	x16, 0x100018000 <dyld_stub_binder+0x100018000>
10000ef14: f9400210    	ldr	x16, [x16]
10000ef18: d61f0200    	br	x16
10000ef1c: 18000050    	ldr	w16, 0x10000ef24 <__stub_helper+0x20>
10000ef20: 17fffff9    	b	0x10000ef04 <__stub_helper>
10000ef24: 00000000    	udf	#0x0
10000ef28: 18000050    	ldr	w16, 0x10000ef30 <__stub_helper+0x2c>
10000ef2c: 17fffff6    	b	0x10000ef04 <__stub_helper>
10000ef30: 00000000    	udf	#0x0
10000ef34: 18000050    	ldr	w16, 0x10000ef3c <__stub_helper+0x38>
10000ef38: 17fffff3    	b	0x10000ef04 <__stub_helper>
10000ef3c: 00000000    	udf	#0x0
10000ef40: 18000050    	ldr	w16, 0x10000ef48 <__stub_helper+0x44>
10000ef44: 17fffff0    	b	0x10000ef04 <__stub_helper>
10000ef48: 00000000    	udf	#0x0
10000ef4c: 18000050    	ldr	w16, 0x10000ef54 <__stub_helper+0x50>
10000ef50: 17ffffed    	b	0x10000ef04 <__stub_helper>
10000ef54: 00000000    	udf	#0x0
10000ef58: 18000050    	ldr	w16, 0x10000ef60 <__stub_helper+0x5c>
10000ef5c: 17ffffea    	b	0x10000ef04 <__stub_helper>
10000ef60: 00000000    	udf	#0x0
10000ef64: 18000050    	ldr	w16, 0x10000ef6c <__stub_helper+0x68>
10000ef68: 17ffffe7    	b	0x10000ef04 <__stub_helper>
10000ef6c: 00000000    	udf	#0x0
10000ef70: 18000050    	ldr	w16, 0x10000ef78 <__stub_helper+0x74>
10000ef74: 17ffffe4    	b	0x10000ef04 <__stub_helper>
10000ef78: 00000000    	udf	#0x0
10000ef7c: 18000050    	ldr	w16, 0x10000ef84 <__stub_helper+0x80>
10000ef80: 17ffffe1    	b	0x10000ef04 <__stub_helper>
10000ef84: 00000000    	udf	#0x0
10000ef88: 18000050    	ldr	w16, 0x10000ef90 <__stub_helper+0x8c>
10000ef8c: 17ffffde    	b	0x10000ef04 <__stub_helper>
10000ef90: 00000000    	udf	#0x0
10000ef94: 18000050    	ldr	w16, 0x10000ef9c <__stub_helper+0x98>
10000ef98: 17ffffdb    	b	0x10000ef04 <__stub_helper>
10000ef9c: 00000000    	udf	#0x0
10000efa0: 18000050    	ldr	w16, 0x10000efa8 <__stub_helper+0xa4>
10000efa4: 17ffffd8    	b	0x10000ef04 <__stub_helper>
10000efa8: 00000000    	udf	#0x0
10000efac: 18000050    	ldr	w16, 0x10000efb4 <__stub_helper+0xb0>
10000efb0: 17ffffd5    	b	0x10000ef04 <__stub_helper>
10000efb4: 00000000    	udf	#0x0
10000efb8: 18000050    	ldr	w16, 0x10000efc0 <__stub_helper+0xbc>
10000efbc: 17ffffd2    	b	0x10000ef04 <__stub_helper>
10000efc0: 00000000    	udf	#0x0
10000efc4: 18000050    	ldr	w16, 0x10000efcc <__stub_helper+0xc8>
10000efc8: 17ffffcf    	b	0x10000ef04 <__stub_helper>
10000efcc: 00000000    	udf	#0x0
10000efd0: 18000050    	ldr	w16, 0x10000efd8 <__stub_helper+0xd4>
10000efd4: 17ffffcc    	b	0x10000ef04 <__stub_helper>
10000efd8: 00000000    	udf	#0x0
10000efdc: 18000050    	ldr	w16, 0x10000efe4 <__stub_helper+0xe0>
10000efe0: 17ffffc9    	b	0x10000ef04 <__stub_helper>
10000efe4: 00000000    	udf	#0x0
