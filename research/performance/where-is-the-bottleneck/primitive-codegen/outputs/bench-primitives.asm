
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
100000704: 9119214a    	add	x10, x10, #0x648
100000708: a9002541    	stp	x1, x9, [x10]
10000070c: d1000508    	sub	x8, x8, #0x1
100000710: a9012142    	stp	x2, x8, [x10, #0x10]
100000714: b0000008    	adrp	x8, 0x100001000 <_main+0x938>
100000718: 913a4108    	add	x8, x8, #0xe90
10000071c: f9003be8    	str	x8, [sp, #0x70]
100000720: 9100c3e0    	add	x0, sp, #0x30
100000724: 94003ba2    	bl	0x10000f5ac <dyld_stub_binder+0x10000f5ac>
100000728: 3100041f    	cmn	w0, #0x1
10000072c: 54000041    	b.ne	0x100000734 <_main+0x6c>
100000730: 94003bab    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
100000734: b94033e8    	ldr	w8, [sp, #0x30]
100000738: 290f7fe8    	stp	w8, wzr, [sp, #0x78]
10000073c: 9101c3e1    	add	x1, sp, #0x70
100000740: 528001a0    	mov	w0, #0xd                ; =13
100000744: d2800002    	mov	x2, #0x0                ; =0
100000748: 94003b96    	bl	0x10000f5a0 <dyld_stub_binder+0x10000f5a0>
10000074c: 3100041f    	cmn	w0, #0x1
100000750: 54000041    	b.ne	0x100000758 <_main+0x90>
100000754: 94003ba2    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
100000758: f0000068    	adrp	x8, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000075c: 3dc1d100    	ldr	q0, [x8, #0x740]
100000760: f0000068    	adrp	x8, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000764: 3dc1d501    	ldr	q1, [x8, #0x750]
100000768: 900000e8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000076c: 9118c108    	add	x8, x8, #0x630
100000770: ad020500    	stp	q0, q1, [x8, #0x40]
100000774: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000778: 3dc1d920    	ldr	q0, [x9, #0x760]
10000077c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000780: 3dc1dd21    	ldr	q1, [x9, #0x770]
100000784: ad030500    	stp	q0, q1, [x8, #0x60]
100000788: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000078c: 3dc1e120    	ldr	q0, [x9, #0x780]
100000790: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000794: 3dc1e521    	ldr	q1, [x9, #0x790]
100000798: ad040500    	stp	q0, q1, [x8, #0x80]
10000079c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007a0: 3dc1e920    	ldr	q0, [x9, #0x7a0]
1000007a4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007a8: 3dc1ed21    	ldr	q1, [x9, #0x7b0]
1000007ac: ad050500    	stp	q0, q1, [x8, #0xa0]
1000007b0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007b4: 3dc1f120    	ldr	q0, [x9, #0x7c0]
1000007b8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007bc: 3dc1f521    	ldr	q1, [x9, #0x7d0]
1000007c0: ad060500    	stp	q0, q1, [x8, #0xc0]
1000007c4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007c8: 3dc1f920    	ldr	q0, [x9, #0x7e0]
1000007cc: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007d0: 3dc1fd21    	ldr	q1, [x9, #0x7f0]
1000007d4: ad070500    	stp	q0, q1, [x8, #0xe0]
1000007d8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007dc: 3dc20120    	ldr	q0, [x9, #0x800]
1000007e0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007e4: 3dc20521    	ldr	q1, [x9, #0x810]
1000007e8: ad080500    	stp	q0, q1, [x8, #0x100]
1000007ec: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007f0: 3dc20920    	ldr	q0, [x9, #0x820]
1000007f4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000007f8: 3dc20d21    	ldr	q1, [x9, #0x830]
1000007fc: ad090500    	stp	q0, q1, [x8, #0x120]
100000800: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000804: 3dc21120    	ldr	q0, [x9, #0x840]
100000808: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000080c: 3dc21521    	ldr	q1, [x9, #0x850]
100000810: ad0a0500    	stp	q0, q1, [x8, #0x140]
100000814: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000818: 3dc21920    	ldr	q0, [x9, #0x860]
10000081c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000820: 3dc21d21    	ldr	q1, [x9, #0x870]
100000824: ad0b0500    	stp	q0, q1, [x8, #0x160]
100000828: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000082c: 3dc22120    	ldr	q0, [x9, #0x880]
100000830: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000834: 3dc22521    	ldr	q1, [x9, #0x890]
100000838: ad0c0500    	stp	q0, q1, [x8, #0x180]
10000083c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000840: 3dc22920    	ldr	q0, [x9, #0x8a0]
100000844: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000848: 3dc22d21    	ldr	q1, [x9, #0x8b0]
10000084c: ad0d0500    	stp	q0, q1, [x8, #0x1a0]
100000850: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000854: 3dc23120    	ldr	q0, [x9, #0x8c0]
100000858: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000085c: 3dc23521    	ldr	q1, [x9, #0x8d0]
100000860: ad0e0500    	stp	q0, q1, [x8, #0x1c0]
100000864: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000868: 3dc23920    	ldr	q0, [x9, #0x8e0]
10000086c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000870: 3dc23d21    	ldr	q1, [x9, #0x8f0]
100000874: ad0f0500    	stp	q0, q1, [x8, #0x1e0]
100000878: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000087c: 3dc24120    	ldr	q0, [x9, #0x900]
100000880: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000884: 3dc24521    	ldr	q1, [x9, #0x910]
100000888: ad100500    	stp	q0, q1, [x8, #0x200]
10000088c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000890: 3dc24920    	ldr	q0, [x9, #0x920]
100000894: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000898: 3dc24d21    	ldr	q1, [x9, #0x930]
10000089c: ad110500    	stp	q0, q1, [x8, #0x220]
1000008a0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008a4: 3dc25120    	ldr	q0, [x9, #0x940]
1000008a8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008ac: 3dc25521    	ldr	q1, [x9, #0x950]
1000008b0: ad120500    	stp	q0, q1, [x8, #0x240]
1000008b4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008b8: 3dc25920    	ldr	q0, [x9, #0x960]
1000008bc: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008c0: 3dc25d21    	ldr	q1, [x9, #0x970]
1000008c4: ad130500    	stp	q0, q1, [x8, #0x260]
1000008c8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008cc: 3dc26120    	ldr	q0, [x9, #0x980]
1000008d0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008d4: 3dc26521    	ldr	q1, [x9, #0x990]
1000008d8: ad140500    	stp	q0, q1, [x8, #0x280]
1000008dc: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008e0: 3dc26920    	ldr	q0, [x9, #0x9a0]
1000008e4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008e8: 3dc26d21    	ldr	q1, [x9, #0x9b0]
1000008ec: ad150500    	stp	q0, q1, [x8, #0x2a0]
1000008f0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008f4: 3dc27120    	ldr	q0, [x9, #0x9c0]
1000008f8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000008fc: 3dc27521    	ldr	q1, [x9, #0x9d0]
100000900: ad160500    	stp	q0, q1, [x8, #0x2c0]
100000904: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000908: 3dc27920    	ldr	q0, [x9, #0x9e0]
10000090c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000910: 3dc27d21    	ldr	q1, [x9, #0x9f0]
100000914: ad170500    	stp	q0, q1, [x8, #0x2e0]
100000918: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000091c: 3dc28120    	ldr	q0, [x9, #0xa00]
100000920: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000924: 3dc28521    	ldr	q1, [x9, #0xa10]
100000928: ad180500    	stp	q0, q1, [x8, #0x300]
10000092c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000930: 3dc28920    	ldr	q0, [x9, #0xa20]
100000934: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000938: 3dc28d21    	ldr	q1, [x9, #0xa30]
10000093c: ad190500    	stp	q0, q1, [x8, #0x320]
100000940: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000944: 3dc29120    	ldr	q0, [x9, #0xa40]
100000948: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000094c: 3dc29521    	ldr	q1, [x9, #0xa50]
100000950: ad1a0500    	stp	q0, q1, [x8, #0x340]
100000954: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000958: 3dc29920    	ldr	q0, [x9, #0xa60]
10000095c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000960: 3dc29d21    	ldr	q1, [x9, #0xa70]
100000964: ad1b0500    	stp	q0, q1, [x8, #0x360]
100000968: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000096c: 3dc2a120    	ldr	q0, [x9, #0xa80]
100000970: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000974: 3dc2a521    	ldr	q1, [x9, #0xa90]
100000978: ad1c0500    	stp	q0, q1, [x8, #0x380]
10000097c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000980: 3dc2a920    	ldr	q0, [x9, #0xaa0]
100000984: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000988: 3dc2ad21    	ldr	q1, [x9, #0xab0]
10000098c: ad1d0500    	stp	q0, q1, [x8, #0x3a0]
100000990: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000994: 3dc2b120    	ldr	q0, [x9, #0xac0]
100000998: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000099c: 3dc2b521    	ldr	q1, [x9, #0xad0]
1000009a0: ad1e0500    	stp	q0, q1, [x8, #0x3c0]
1000009a4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000009a8: 3dc2b920    	ldr	q0, [x9, #0xae0]
1000009ac: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000009b0: 3dc2bd21    	ldr	q1, [x9, #0xaf0]
1000009b4: ad1f0500    	stp	q0, q1, [x8, #0x3e0]
1000009b8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000009bc: 3dc2c120    	ldr	q0, [x9, #0xb00]
1000009c0: 3d810100    	str	q0, [x8, #0x400]
1000009c4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000009c8: 3dc2c520    	ldr	q0, [x9, #0xb10]
1000009cc: 3d810500    	str	q0, [x8, #0x410]
1000009d0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000009d4: 3dc2c920    	ldr	q0, [x9, #0xb20]
1000009d8: 3d810900    	str	q0, [x8, #0x420]
1000009dc: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000009e0: 3dc2cd20    	ldr	q0, [x9, #0xb30]
1000009e4: 3d810d00    	str	q0, [x8, #0x430]
1000009e8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000009ec: 3dc2d120    	ldr	q0, [x9, #0xb40]
1000009f0: 3d811100    	str	q0, [x8, #0x440]
1000009f4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
1000009f8: 3dc2d520    	ldr	q0, [x9, #0xb50]
1000009fc: 3d811500    	str	q0, [x8, #0x450]
100000a00: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a04: 3dc2d920    	ldr	q0, [x9, #0xb60]
100000a08: 3d811900    	str	q0, [x8, #0x460]
100000a0c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a10: 3dc2dd20    	ldr	q0, [x9, #0xb70]
100000a14: 3d811d00    	str	q0, [x8, #0x470]
100000a18: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a1c: 3dc2e120    	ldr	q0, [x9, #0xb80]
100000a20: 3d812100    	str	q0, [x8, #0x480]
100000a24: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a28: 3dc2e520    	ldr	q0, [x9, #0xb90]
100000a2c: 3d812500    	str	q0, [x8, #0x490]
100000a30: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a34: 3dc2e920    	ldr	q0, [x9, #0xba0]
100000a38: 3d812900    	str	q0, [x8, #0x4a0]
100000a3c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a40: 3dc2ed20    	ldr	q0, [x9, #0xbb0]
100000a44: 3d812d00    	str	q0, [x8, #0x4b0]
100000a48: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a4c: 3dc2f120    	ldr	q0, [x9, #0xbc0]
100000a50: 3d813100    	str	q0, [x8, #0x4c0]
100000a54: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a58: 3dc2f520    	ldr	q0, [x9, #0xbd0]
100000a5c: 3d813500    	str	q0, [x8, #0x4d0]
100000a60: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a64: 3dc2f920    	ldr	q0, [x9, #0xbe0]
100000a68: 3d813900    	str	q0, [x8, #0x4e0]
100000a6c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a70: 3dc2fd20    	ldr	q0, [x9, #0xbf0]
100000a74: 3d813d00    	str	q0, [x8, #0x4f0]
100000a78: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a7c: 3dc30120    	ldr	q0, [x9, #0xc00]
100000a80: 3d814100    	str	q0, [x8, #0x500]
100000a84: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a88: 3dc30520    	ldr	q0, [x9, #0xc10]
100000a8c: 3d814500    	str	q0, [x8, #0x510]
100000a90: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000a94: 3dc30920    	ldr	q0, [x9, #0xc20]
100000a98: 3d814900    	str	q0, [x8, #0x520]
100000a9c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000aa0: 3dc30d20    	ldr	q0, [x9, #0xc30]
100000aa4: 3d814d00    	str	q0, [x8, #0x530]
100000aa8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000aac: 3dc31120    	ldr	q0, [x9, #0xc40]
100000ab0: 3d815100    	str	q0, [x8, #0x540]
100000ab4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000ab8: 3dc31520    	ldr	q0, [x9, #0xc50]
100000abc: 3d815500    	str	q0, [x8, #0x550]
100000ac0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000ac4: 3dc31920    	ldr	q0, [x9, #0xc60]
100000ac8: 3d815900    	str	q0, [x8, #0x560]
100000acc: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000ad0: 3dc31d20    	ldr	q0, [x9, #0xc70]
100000ad4: 3d815d00    	str	q0, [x8, #0x570]
100000ad8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000adc: 3dc32120    	ldr	q0, [x9, #0xc80]
100000ae0: 3d816100    	str	q0, [x8, #0x580]
100000ae4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000ae8: 3dc32520    	ldr	q0, [x9, #0xc90]
100000aec: 3d816500    	str	q0, [x8, #0x590]
100000af0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000af4: 3dc32920    	ldr	q0, [x9, #0xca0]
100000af8: 3d816900    	str	q0, [x8, #0x5a0]
100000afc: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b00: 3dc32d20    	ldr	q0, [x9, #0xcb0]
100000b04: 3d816d00    	str	q0, [x8, #0x5b0]
100000b08: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b0c: 3dc33120    	ldr	q0, [x9, #0xcc0]
100000b10: 3d817100    	str	q0, [x8, #0x5c0]
100000b14: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b18: 3dc33520    	ldr	q0, [x9, #0xcd0]
100000b1c: 3d817500    	str	q0, [x8, #0x5d0]
100000b20: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b24: 3dc33920    	ldr	q0, [x9, #0xce0]
100000b28: 3d817900    	str	q0, [x8, #0x5e0]
100000b2c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b30: 3dc33d20    	ldr	q0, [x9, #0xcf0]
100000b34: 3d817d00    	str	q0, [x8, #0x5f0]
100000b38: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b3c: 3dc34120    	ldr	q0, [x9, #0xd00]
100000b40: 3d818100    	str	q0, [x8, #0x600]
100000b44: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b48: 3dc34520    	ldr	q0, [x9, #0xd10]
100000b4c: 3d818500    	str	q0, [x8, #0x610]
100000b50: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b54: 3dc34920    	ldr	q0, [x9, #0xd20]
100000b58: 3d818900    	str	q0, [x8, #0x620]
100000b5c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b60: 3dc34d20    	ldr	q0, [x9, #0xd30]
100000b64: 3d818d00    	str	q0, [x8, #0x630]
100000b68: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b6c: 3dc35120    	ldr	q0, [x9, #0xd40]
100000b70: 3d819100    	str	q0, [x8, #0x640]
100000b74: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b78: 3dc35520    	ldr	q0, [x9, #0xd50]
100000b7c: 3d819500    	str	q0, [x8, #0x650]
100000b80: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b84: 3dc35920    	ldr	q0, [x9, #0xd60]
100000b88: 3d819900    	str	q0, [x8, #0x660]
100000b8c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b90: 3dc35d20    	ldr	q0, [x9, #0xd70]
100000b94: 3d819d00    	str	q0, [x8, #0x670]
100000b98: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000b9c: 3dc36120    	ldr	q0, [x9, #0xd80]
100000ba0: 3d81a100    	str	q0, [x8, #0x680]
100000ba4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000ba8: 3dc36520    	ldr	q0, [x9, #0xd90]
100000bac: 3d81a500    	str	q0, [x8, #0x690]
100000bb0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000bb4: 3dc36920    	ldr	q0, [x9, #0xda0]
100000bb8: 3d81a900    	str	q0, [x8, #0x6a0]
100000bbc: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000bc0: 3dc36d20    	ldr	q0, [x9, #0xdb0]
100000bc4: 3d81ad00    	str	q0, [x8, #0x6b0]
100000bc8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000bcc: 3dc37120    	ldr	q0, [x9, #0xdc0]
100000bd0: 3d81b100    	str	q0, [x8, #0x6c0]
100000bd4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000bd8: 3dc37520    	ldr	q0, [x9, #0xdd0]
100000bdc: 3d81b500    	str	q0, [x8, #0x6d0]
100000be0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000be4: 3dc37920    	ldr	q0, [x9, #0xde0]
100000be8: 3d81b900    	str	q0, [x8, #0x6e0]
100000bec: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000bf0: 3dc37d20    	ldr	q0, [x9, #0xdf0]
100000bf4: 3d81bd00    	str	q0, [x8, #0x6f0]
100000bf8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000bfc: 3dc38120    	ldr	q0, [x9, #0xe00]
100000c00: 3d81c100    	str	q0, [x8, #0x700]
100000c04: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c08: 3dc38520    	ldr	q0, [x9, #0xe10]
100000c0c: 3d81c500    	str	q0, [x8, #0x710]
100000c10: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c14: 3dc38920    	ldr	q0, [x9, #0xe20]
100000c18: 3d81c900    	str	q0, [x8, #0x720]
100000c1c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c20: 3dc38d20    	ldr	q0, [x9, #0xe30]
100000c24: 3d81cd00    	str	q0, [x8, #0x730]
100000c28: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c2c: 3dc39120    	ldr	q0, [x9, #0xe40]
100000c30: 3d81d100    	str	q0, [x8, #0x740]
100000c34: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c38: 3dc39520    	ldr	q0, [x9, #0xe50]
100000c3c: 3d81d500    	str	q0, [x8, #0x750]
100000c40: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c44: 3dc39920    	ldr	q0, [x9, #0xe60]
100000c48: 3d81d900    	str	q0, [x8, #0x760]
100000c4c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c50: 3dc39d20    	ldr	q0, [x9, #0xe70]
100000c54: 3d81dd00    	str	q0, [x8, #0x770]
100000c58: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c5c: 3dc3a120    	ldr	q0, [x9, #0xe80]
100000c60: 3d81e100    	str	q0, [x8, #0x780]
100000c64: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c68: 3dc3a520    	ldr	q0, [x9, #0xe90]
100000c6c: 3d81e500    	str	q0, [x8, #0x790]
100000c70: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c74: 3dc3a920    	ldr	q0, [x9, #0xea0]
100000c78: 3d81e900    	str	q0, [x8, #0x7a0]
100000c7c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c80: 3dc3ad20    	ldr	q0, [x9, #0xeb0]
100000c84: 3d81ed00    	str	q0, [x8, #0x7b0]
100000c88: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c8c: 3dc3b120    	ldr	q0, [x9, #0xec0]
100000c90: 3d81f100    	str	q0, [x8, #0x7c0]
100000c94: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000c98: 3dc3b520    	ldr	q0, [x9, #0xed0]
100000c9c: 3d81f500    	str	q0, [x8, #0x7d0]
100000ca0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000ca4: 3dc3b920    	ldr	q0, [x9, #0xee0]
100000ca8: 3d81f900    	str	q0, [x8, #0x7e0]
100000cac: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000cb0: 3dc3bd20    	ldr	q0, [x9, #0xef0]
100000cb4: 3d81fd00    	str	q0, [x8, #0x7f0]
100000cb8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000cbc: 3dc3c120    	ldr	q0, [x9, #0xf00]
100000cc0: 3d820100    	str	q0, [x8, #0x800]
100000cc4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000cc8: 3dc3c520    	ldr	q0, [x9, #0xf10]
100000ccc: 3d820500    	str	q0, [x8, #0x810]
100000cd0: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000cd4: 3dc3c920    	ldr	q0, [x9, #0xf20]
100000cd8: 3d820900    	str	q0, [x8, #0x820]
100000cdc: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000ce0: 3dc3cd20    	ldr	q0, [x9, #0xf30]
100000ce4: 3d820d00    	str	q0, [x8, #0x830]
100000ce8: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000cec: 3dc3d120    	ldr	q0, [x9, #0xf40]
100000cf0: 3d821100    	str	q0, [x8, #0x840]
100000cf4: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000cf8: 3dc3d520    	ldr	q0, [x9, #0xf50]
100000cfc: 3d821500    	str	q0, [x8, #0x850]
100000d00: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d04: 3dc3d920    	ldr	q0, [x9, #0xf60]
100000d08: 3d821900    	str	q0, [x8, #0x860]
100000d0c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d10: 3dc3dd20    	ldr	q0, [x9, #0xf70]
100000d14: 3d821d00    	str	q0, [x8, #0x870]
100000d18: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d1c: 3dc3e120    	ldr	q0, [x9, #0xf80]
100000d20: 3d822100    	str	q0, [x8, #0x880]
100000d24: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d28: 3dc3e520    	ldr	q0, [x9, #0xf90]
100000d2c: 3d822500    	str	q0, [x8, #0x890]
100000d30: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d34: 3dc3e920    	ldr	q0, [x9, #0xfa0]
100000d38: 3d822900    	str	q0, [x8, #0x8a0]
100000d3c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d40: 3dc3ed20    	ldr	q0, [x9, #0xfb0]
100000d44: 3d822d00    	str	q0, [x8, #0x8b0]
100000d48: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d4c: 3dc3f120    	ldr	q0, [x9, #0xfc0]
100000d50: 3d823100    	str	q0, [x8, #0x8c0]
100000d54: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d58: 3dc3f520    	ldr	q0, [x9, #0xfd0]
100000d5c: 3d823500    	str	q0, [x8, #0x8d0]
100000d60: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d64: 3dc3f920    	ldr	q0, [x9, #0xfe0]
100000d68: 3d823900    	str	q0, [x8, #0x8e0]
100000d6c: f0000069    	adrp	x9, 0x10000f000 <_fs.File.Writer.drain+0x170>
100000d70: 3dc3fd20    	ldr	q0, [x9, #0xff0]
100000d74: 3d823d00    	str	q0, [x8, #0x8f0]
100000d78: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000d7c: 3dc00120    	ldr	q0, [x9]
100000d80: 3d824100    	str	q0, [x8, #0x900]
100000d84: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000d88: 3dc00520    	ldr	q0, [x9, #0x10]
100000d8c: 3d824500    	str	q0, [x8, #0x910]
100000d90: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000d94: 3dc00920    	ldr	q0, [x9, #0x20]
100000d98: 3d824900    	str	q0, [x8, #0x920]
100000d9c: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000da0: 3dc00d20    	ldr	q0, [x9, #0x30]
100000da4: 3d824d00    	str	q0, [x8, #0x930]
100000da8: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000dac: 3dc01120    	ldr	q0, [x9, #0x40]
100000db0: 3d825100    	str	q0, [x8, #0x940]
100000db4: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000db8: 3dc01520    	ldr	q0, [x9, #0x50]
100000dbc: 3d825500    	str	q0, [x8, #0x950]
100000dc0: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000dc4: 3dc01920    	ldr	q0, [x9, #0x60]
100000dc8: 3d825900    	str	q0, [x8, #0x960]
100000dcc: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000dd0: 3dc01d20    	ldr	q0, [x9, #0x70]
100000dd4: 3d825d00    	str	q0, [x8, #0x970]
100000dd8: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000ddc: 3dc02120    	ldr	q0, [x9, #0x80]
100000de0: 3d826100    	str	q0, [x8, #0x980]
100000de4: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000de8: 3dc02520    	ldr	q0, [x9, #0x90]
100000dec: 3d826500    	str	q0, [x8, #0x990]
100000df0: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000df4: 3dc02920    	ldr	q0, [x9, #0xa0]
100000df8: 3d826900    	str	q0, [x8, #0x9a0]
100000dfc: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e00: 3dc02d20    	ldr	q0, [x9, #0xb0]
100000e04: 3d826d00    	str	q0, [x8, #0x9b0]
100000e08: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e0c: 3dc03120    	ldr	q0, [x9, #0xc0]
100000e10: 3d827100    	str	q0, [x8, #0x9c0]
100000e14: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e18: 3dc03520    	ldr	q0, [x9, #0xd0]
100000e1c: 3d827500    	str	q0, [x8, #0x9d0]
100000e20: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e24: 3dc03920    	ldr	q0, [x9, #0xe0]
100000e28: 3d827900    	str	q0, [x8, #0x9e0]
100000e2c: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e30: 3dc03d20    	ldr	q0, [x9, #0xf0]
100000e34: 3d827d00    	str	q0, [x8, #0x9f0]
100000e38: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e3c: 3dc04120    	ldr	q0, [x9, #0x100]
100000e40: 3d828100    	str	q0, [x8, #0xa00]
100000e44: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e48: 3dc04520    	ldr	q0, [x9, #0x110]
100000e4c: 3d828500    	str	q0, [x8, #0xa10]
100000e50: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e54: 3dc04920    	ldr	q0, [x9, #0x120]
100000e58: 3d828900    	str	q0, [x8, #0xa20]
100000e5c: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e60: 3dc04d20    	ldr	q0, [x9, #0x130]
100000e64: 3d828d00    	str	q0, [x8, #0xa30]
100000e68: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e6c: 3dc05120    	ldr	q0, [x9, #0x140]
100000e70: 3d829100    	str	q0, [x8, #0xa40]
100000e74: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e78: 3dc05520    	ldr	q0, [x9, #0x150]
100000e7c: 3d829500    	str	q0, [x8, #0xa50]
100000e80: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e84: 3dc05920    	ldr	q0, [x9, #0x160]
100000e88: 3d829900    	str	q0, [x8, #0xa60]
100000e8c: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e90: 3dc05d20    	ldr	q0, [x9, #0x170]
100000e94: 3d829d00    	str	q0, [x8, #0xa70]
100000e98: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000e9c: 3dc06120    	ldr	q0, [x9, #0x180]
100000ea0: 3d82a100    	str	q0, [x8, #0xa80]
100000ea4: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000ea8: 3dc06520    	ldr	q0, [x9, #0x190]
100000eac: 3d82a500    	str	q0, [x8, #0xa90]
100000eb0: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000eb4: 3dc06920    	ldr	q0, [x9, #0x1a0]
100000eb8: 3d82a900    	str	q0, [x8, #0xaa0]
100000ebc: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000ec0: 3dc06d20    	ldr	q0, [x9, #0x1b0]
100000ec4: 3d82ad00    	str	q0, [x8, #0xab0]
100000ec8: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000ecc: 3dc07120    	ldr	q0, [x9, #0x1c0]
100000ed0: 3d82b100    	str	q0, [x8, #0xac0]
100000ed4: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000ed8: 3dc07520    	ldr	q0, [x9, #0x1d0]
100000edc: 3d82b500    	str	q0, [x8, #0xad0]
100000ee0: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000ee4: 3dc07920    	ldr	q0, [x9, #0x1e0]
100000ee8: 3d82b900    	str	q0, [x8, #0xae0]
100000eec: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000ef0: 3dc07d20    	ldr	q0, [x9, #0x1f0]
100000ef4: 3d82bd00    	str	q0, [x8, #0xaf0]
100000ef8: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000efc: 3dc08120    	ldr	q0, [x9, #0x200]
100000f00: 3d82c100    	str	q0, [x8, #0xb00]
100000f04: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f08: 3dc08520    	ldr	q0, [x9, #0x210]
100000f0c: 3d82c500    	str	q0, [x8, #0xb10]
100000f10: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f14: 3dc08920    	ldr	q0, [x9, #0x220]
100000f18: 3d82c900    	str	q0, [x8, #0xb20]
100000f1c: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f20: 3dc08d20    	ldr	q0, [x9, #0x230]
100000f24: 3d82cd00    	str	q0, [x8, #0xb30]
100000f28: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f2c: 3dc09120    	ldr	q0, [x9, #0x240]
100000f30: 3d82d100    	str	q0, [x8, #0xb40]
100000f34: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f38: 3dc09520    	ldr	q0, [x9, #0x250]
100000f3c: 3d82d500    	str	q0, [x8, #0xb50]
100000f40: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f44: 3dc09920    	ldr	q0, [x9, #0x260]
100000f48: 3d82d900    	str	q0, [x8, #0xb60]
100000f4c: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f50: 3dc09d20    	ldr	q0, [x9, #0x270]
100000f54: 3d82dd00    	str	q0, [x8, #0xb70]
100000f58: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f5c: 3dc0a120    	ldr	q0, [x9, #0x280]
100000f60: 3d82e100    	str	q0, [x8, #0xb80]
100000f64: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f68: 3dc0a520    	ldr	q0, [x9, #0x290]
100000f6c: 3d82e500    	str	q0, [x8, #0xb90]
100000f70: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f74: 3dc0a920    	ldr	q0, [x9, #0x2a0]
100000f78: 3d82e900    	str	q0, [x8, #0xba0]
100000f7c: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f80: 3dc0ad20    	ldr	q0, [x9, #0x2b0]
100000f84: 3d82ed00    	str	q0, [x8, #0xbb0]
100000f88: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f8c: 3dc0b120    	ldr	q0, [x9, #0x2c0]
100000f90: 3d82f100    	str	q0, [x8, #0xbc0]
100000f94: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000f98: 3dc0b520    	ldr	q0, [x9, #0x2d0]
100000f9c: 3d82f500    	str	q0, [x8, #0xbd0]
100000fa0: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000fa4: 3dc0b920    	ldr	q0, [x9, #0x2e0]
100000fa8: 3d82f900    	str	q0, [x8, #0xbe0]
100000fac: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000fb0: 3dc0bd20    	ldr	q0, [x9, #0x2f0]
100000fb4: 3d82fd00    	str	q0, [x8, #0xbf0]
100000fb8: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000fbc: 3dc0c120    	ldr	q0, [x9, #0x300]
100000fc0: 3d830100    	str	q0, [x8, #0xc00]
100000fc4: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000fc8: 3dc0c520    	ldr	q0, [x9, #0x310]
100000fcc: 3d830500    	str	q0, [x8, #0xc10]
100000fd0: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000fd4: 3dc0c920    	ldr	q0, [x9, #0x320]
100000fd8: 3d830900    	str	q0, [x8, #0xc20]
100000fdc: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000fe0: 3dc0cd20    	ldr	q0, [x9, #0x330]
100000fe4: 3d830d00    	str	q0, [x8, #0xc30]
100000fe8: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000fec: 3dc0d120    	ldr	q0, [x9, #0x340]
100000ff0: 3d831100    	str	q0, [x8, #0xc40]
100000ff4: 90000089    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100000ff8: 3dc0d520    	ldr	q0, [x9, #0x350]
100000ffc: 3d831500    	str	q0, [x8, #0xc50]
100001000: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001004: 3dc0d920    	ldr	q0, [x9, #0x360]
100001008: 3d831900    	str	q0, [x8, #0xc60]
10000100c: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001010: 3dc0dd20    	ldr	q0, [x9, #0x370]
100001014: 3d831d00    	str	q0, [x8, #0xc70]
100001018: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000101c: 3dc0e120    	ldr	q0, [x9, #0x380]
100001020: 3d832100    	str	q0, [x8, #0xc80]
100001024: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001028: 3dc0e520    	ldr	q0, [x9, #0x390]
10000102c: 3d832500    	str	q0, [x8, #0xc90]
100001030: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001034: 3dc0e920    	ldr	q0, [x9, #0x3a0]
100001038: 3d832900    	str	q0, [x8, #0xca0]
10000103c: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001040: 3dc0ed20    	ldr	q0, [x9, #0x3b0]
100001044: 3d832d00    	str	q0, [x8, #0xcb0]
100001048: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000104c: 3dc0f120    	ldr	q0, [x9, #0x3c0]
100001050: 3d833100    	str	q0, [x8, #0xcc0]
100001054: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001058: 3dc0f520    	ldr	q0, [x9, #0x3d0]
10000105c: 3d833500    	str	q0, [x8, #0xcd0]
100001060: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001064: 3dc0f920    	ldr	q0, [x9, #0x3e0]
100001068: 3d833900    	str	q0, [x8, #0xce0]
10000106c: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001070: 3dc0fd20    	ldr	q0, [x9, #0x3f0]
100001074: 3d833d00    	str	q0, [x8, #0xcf0]
100001078: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000107c: 3dc10120    	ldr	q0, [x9, #0x400]
100001080: 3d834100    	str	q0, [x8, #0xd00]
100001084: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001088: 3dc10520    	ldr	q0, [x9, #0x410]
10000108c: 3d834500    	str	q0, [x8, #0xd10]
100001090: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001094: 3dc10920    	ldr	q0, [x9, #0x420]
100001098: 3d834900    	str	q0, [x8, #0xd20]
10000109c: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
1000010a0: 3dc10d20    	ldr	q0, [x9, #0x430]
1000010a4: 3d834d00    	str	q0, [x8, #0xd30]
1000010a8: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
1000010ac: 3dc11120    	ldr	q0, [x9, #0x440]
1000010b0: 3d835100    	str	q0, [x8, #0xd40]
1000010b4: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
1000010b8: 3dc11520    	ldr	q0, [x9, #0x450]
1000010bc: 3d835500    	str	q0, [x8, #0xd50]
1000010c0: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
1000010c4: 3dc11920    	ldr	q0, [x9, #0x460]
1000010c8: 3d835900    	str	q0, [x8, #0xd60]
1000010cc: fd44a100    	ldr	d0, [x8, #0x940]
1000010d0: fd44d501    	ldr	d1, [x8, #0x9a8]
1000010d4: 1e612800    	fadd	d0, d0, d1
1000010d8: fd450901    	ldr	d1, [x8, #0xa10]
1000010dc: 1e612800    	fadd	d0, d0, d1
1000010e0: fd453d01    	ldr	d1, [x8, #0xa78]
1000010e4: 1e612800    	fadd	d0, d0, d1
1000010e8: d28ee629    	mov	x9, #0x7731             ; =30513
1000010ec: f2a425a9    	movk	x9, #0x212d, lsl #16
1000010f0: f2de83e9    	movk	x9, #0xf41f, lsl #32
1000010f4: f2e7fb89    	movk	x9, #0x3fdc, lsl #48
1000010f8: 9e670121    	fmov	d1, x9
1000010fc: 1e612800    	fadd	d0, d0, d1
100001100: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001104: 3dc11d21    	ldr	q1, [x9, #0x470]
100001108: 3d835d01    	str	q1, [x8, #0xd70]
10000110c: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001110: 3dc12121    	ldr	q1, [x9, #0x480]
100001114: 3d836101    	str	q1, [x8, #0xd80]
100001118: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000111c: 3dc12521    	ldr	q1, [x9, #0x490]
100001120: d295dcc9    	mov	x9, #0xaee6             ; =44774
100001124: f2bc84a9    	movk	x9, #0xe425, lsl #16
100001128: f2d3d069    	movk	x9, #0x9e83, lsl #32
10000112c: f2e7fba9    	movk	x9, #0x3fdd, lsl #48
100001130: 3d836501    	str	q1, [x8, #0xd90]
100001134: 9e670121    	fmov	d1, x9
100001138: 1e612800    	fadd	d0, d0, d1
10000113c: d29cd349    	mov	x9, #0xe69a             ; =59034
100001140: f2b4e3a9    	movk	x9, #0xa71d, lsl #16
100001144: f2c91d09    	movk	x9, #0x48e8, lsl #32
100001148: f2e7fbc9    	movk	x9, #0x3fde, lsl #48
10000114c: 9e670121    	fmov	d1, x9
100001150: 1e612800    	fadd	d0, d0, d1
100001154: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100001158: 3dc12921    	ldr	q1, [x9, #0x4a0]
10000115c: 3d836901    	str	q1, [x8, #0xda0]
100001160: d283c9e9    	mov	x9, #0x1e4f             ; =7759
100001164: f2ad42c9    	movk	x9, #0x6a16, lsl #16
100001168: f2de69a9    	movk	x9, #0xf34d, lsl #32
10000116c: f2e7fbc9    	movk	x9, #0x3fde, lsl #48
100001170: 9e670121    	fmov	d1, x9
100001174: 1e612800    	fadd	d0, d0, d1
100001178: f0000069    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000117c: 3dc12d21    	ldr	q1, [x9, #0x4b0]
100001180: d28ac089    	mov	x9, #0x5604             ; =22020
100001184: f2a5a1c9    	movk	x9, #0x2d0e, lsl #16
100001188: f2d3b649    	movk	x9, #0x9db2, lsl #32
10000118c: f2e7fbe9    	movk	x9, #0x3fdf, lsl #48
100001190: 3d836d01    	str	q1, [x8, #0xdb0]
100001194: 9e670121    	fmov	d1, x9
100001198: 1e612800    	fadd	d0, d0, d1
10000119c: d288db89    	mov	x9, #0x46dc             ; =18140
1000011a0: f2af0069    	movk	x9, #0x7803, lsl #16
1000011a4: f2c48169    	movk	x9, #0x240b, lsl #32
1000011a8: f2e7fc09    	movk	x9, #0x3fe0, lsl #48
1000011ac: 9e670121    	fmov	d1, x9
1000011b0: 1e612800    	fadd	d0, d0, d1
1000011b4: fd000100    	str	d0, [x8]
1000011b8: 9101c3e0    	add	x0, sp, #0x70
1000011bc: 94000339    	bl	0x100001ea0 <_debug.lockStderrWriter>
1000011c0: d2800016    	mov	x22, #0x0               ; =0
1000011c4: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000011c8: f940ce68    	ldr	x8, [x19, #0x198]
1000011cc: f0000077    	adrp	x23, 0x100010000 <dyld_stub_binder+0x100010000>
1000011d0: 911c42f7    	add	x23, x23, #0x710
1000011d4: 528000d8    	mov	w24, #0x6               ; =6
1000011d8: f00000d5    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000011dc: f00000d9    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000011e0: 91060339    	add	x25, x25, #0x180
1000011e4: f00000da    	adrp	x26, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000011e8: 9106235a    	add	x26, x26, #0x188
1000011ec: 8b1602e1    	add	x1, x23, x22
1000011f0: cb160314    	sub	x20, x24, x22
1000011f4: 8b080289    	add	x9, x20, x8
1000011f8: f940caaa    	ldr	x10, [x21, #0x190]
1000011fc: eb0a013f    	cmp	x9, x10
100001200: 54000188    	b.hi	0x100001230 <_main+0xb68>
100001204: f9400349    	ldr	x9, [x26]
100001208: 8b080120    	add	x0, x9, x8
10000120c: aa1403e2    	mov	x2, x20
100001210: 940038ea    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
100001214: f9400b48    	ldr	x8, [x26, #0x10]
100001218: 8b140108    	add	x8, x8, x20
10000121c: f9000b48    	str	x8, [x26, #0x10]
100001220: 8b160296    	add	x22, x20, x22
100001224: f1001adf    	cmp	x22, #0x6
100001228: 54fffe23    	b.lo	0x1000011ec <_main+0xb24>
10000122c: 14000011    	b	0x100001270 <_main+0xba8>
100001230: f9400328    	ldr	x8, [x25]
100001234: f9400109    	ldr	x9, [x8]
100001238: a938d3a1    	stp	x1, x20, [x29, #-0x78]
10000123c: 9100c3e8    	add	x8, sp, #0x30
100001240: d101e3a1    	sub	x1, x29, #0x78
100001244: aa1903e0    	mov	x0, x25
100001248: 52800022    	mov	w2, #0x1                ; =1
10000124c: 52800023    	mov	w3, #0x1                ; =1
100001250: d63f0120    	blr	x9
100001254: 794073e8    	ldrh	w8, [sp, #0x38]
100001258: 35001b28    	cbnz	w8, 0x1000015bc <_main+0xef4>
10000125c: f9401bf4    	ldr	x20, [sp, #0x30]
100001260: f9400f28    	ldr	x8, [x25, #0x18]
100001264: 8b160296    	add	x22, x20, x22
100001268: f1001adf    	cmp	x22, #0x6
10000126c: 54fffc03    	b.lo	0x1000011ec <_main+0xb24>
100001270: d2800016    	mov	x22, #0x0               ; =0
100001274: d0000097    	adrp	x23, 0x100013000 <___anon_5016+0x2840>
100001278: 910862f7    	add	x23, x23, #0x218
10000127c: 528000d8    	mov	w24, #0x6               ; =6
100001280: 8b1602e1    	add	x1, x23, x22
100001284: cb160314    	sub	x20, x24, x22
100001288: 8b080289    	add	x9, x20, x8
10000128c: f940caaa    	ldr	x10, [x21, #0x190]
100001290: eb0a013f    	cmp	x9, x10
100001294: 54000188    	b.hi	0x1000012c4 <_main+0xbfc>
100001298: f9400349    	ldr	x9, [x26]
10000129c: 8b080120    	add	x0, x9, x8
1000012a0: aa1403e2    	mov	x2, x20
1000012a4: 940038c5    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
1000012a8: f9400b48    	ldr	x8, [x26, #0x10]
1000012ac: 8b140108    	add	x8, x8, x20
1000012b0: f9000b48    	str	x8, [x26, #0x10]
1000012b4: 8b160296    	add	x22, x20, x22
1000012b8: f1001adf    	cmp	x22, #0x6
1000012bc: 54fffe23    	b.lo	0x100001280 <_main+0xbb8>
1000012c0: 14000011    	b	0x100001304 <_main+0xc3c>
1000012c4: f9400328    	ldr	x8, [x25]
1000012c8: f9400109    	ldr	x9, [x8]
1000012cc: a938d3a1    	stp	x1, x20, [x29, #-0x78]
1000012d0: 9100c3e8    	add	x8, sp, #0x30
1000012d4: d101e3a1    	sub	x1, x29, #0x78
1000012d8: aa1903e0    	mov	x0, x25
1000012dc: 52800022    	mov	w2, #0x1                ; =1
1000012e0: 52800023    	mov	w3, #0x1                ; =1
1000012e4: d63f0120    	blr	x9
1000012e8: 794073e8    	ldrh	w8, [sp, #0x38]
1000012ec: 35001688    	cbnz	w8, 0x1000015bc <_main+0xef4>
1000012f0: f9401bf4    	ldr	x20, [sp, #0x30]
1000012f4: f9400f28    	ldr	x8, [x25, #0x18]
1000012f8: 8b160296    	add	x22, x20, x22
1000012fc: f1001adf    	cmp	x22, #0x6
100001300: 54fffc03    	b.lo	0x100001280 <_main+0xbb8>
100001304: d2800016    	mov	x22, #0x0               ; =0
100001308: f0000077    	adrp	x23, 0x100010000 <dyld_stub_binder+0x100010000>
10000130c: 911c5af7    	add	x23, x23, #0x716
100001310: 52800378    	mov	w24, #0x1b              ; =27
100001314: 8b1602e1    	add	x1, x23, x22
100001318: cb160314    	sub	x20, x24, x22
10000131c: 8b080289    	add	x9, x20, x8
100001320: f940caaa    	ldr	x10, [x21, #0x190]
100001324: eb0a013f    	cmp	x9, x10
100001328: 54000188    	b.hi	0x100001358 <_main+0xc90>
10000132c: f9400349    	ldr	x9, [x26]
100001330: 8b080120    	add	x0, x9, x8
100001334: aa1403e2    	mov	x2, x20
100001338: 940038a0    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
10000133c: f9400b48    	ldr	x8, [x26, #0x10]
100001340: 8b140108    	add	x8, x8, x20
100001344: f9000b48    	str	x8, [x26, #0x10]
100001348: 8b160296    	add	x22, x20, x22
10000134c: f1006edf    	cmp	x22, #0x1b
100001350: 54fffe23    	b.lo	0x100001314 <_main+0xc4c>
100001354: 14000011    	b	0x100001398 <_main+0xcd0>
100001358: f9400328    	ldr	x8, [x25]
10000135c: f9400109    	ldr	x9, [x8]
100001360: a938d3a1    	stp	x1, x20, [x29, #-0x78]
100001364: 9100c3e8    	add	x8, sp, #0x30
100001368: d101e3a1    	sub	x1, x29, #0x78
10000136c: aa1903e0    	mov	x0, x25
100001370: 52800022    	mov	w2, #0x1                ; =1
100001374: 52800023    	mov	w3, #0x1                ; =1
100001378: d63f0120    	blr	x9
10000137c: 794073e8    	ldrh	w8, [sp, #0x38]
100001380: 350011e8    	cbnz	w8, 0x1000015bc <_main+0xef4>
100001384: f9401bf4    	ldr	x20, [sp, #0x30]
100001388: f9400f28    	ldr	x8, [x25, #0x18]
10000138c: 8b160296    	add	x22, x20, x22
100001390: f1006edf    	cmp	x22, #0x1b
100001394: 54fffc03    	b.lo	0x100001314 <_main+0xc4c>
100001398: d2800016    	mov	x22, #0x0               ; =0
10000139c: d0000097    	adrp	x23, 0x100013000 <___anon_5016+0x2840>
1000013a0: 91087ef7    	add	x23, x23, #0x21f
1000013a4: 8b1602e1    	add	x1, x23, x22
1000013a8: d2400ad4    	eor	x20, x22, #0x7
1000013ac: f940caa9    	ldr	x9, [x21, #0x190]
1000013b0: 8b08028a    	add	x10, x20, x8
1000013b4: eb09015f    	cmp	x10, x9
1000013b8: 54000188    	b.hi	0x1000013e8 <_main+0xd20>
1000013bc: f9400349    	ldr	x9, [x26]
1000013c0: 8b080120    	add	x0, x9, x8
1000013c4: aa1403e2    	mov	x2, x20
1000013c8: 9400387c    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
1000013cc: f9400b48    	ldr	x8, [x26, #0x10]
1000013d0: 8b140108    	add	x8, x8, x20
1000013d4: f9000b48    	str	x8, [x26, #0x10]
1000013d8: 8b160296    	add	x22, x20, x22
1000013dc: f1001edf    	cmp	x22, #0x7
1000013e0: 54fffe23    	b.lo	0x1000013a4 <_main+0xcdc>
1000013e4: 14000011    	b	0x100001428 <_main+0xd60>
1000013e8: f9400328    	ldr	x8, [x25]
1000013ec: f9400109    	ldr	x9, [x8]
1000013f0: a938d3a1    	stp	x1, x20, [x29, #-0x78]
1000013f4: 9100c3e8    	add	x8, sp, #0x30
1000013f8: d101e3a1    	sub	x1, x29, #0x78
1000013fc: aa1903e0    	mov	x0, x25
100001400: 52800022    	mov	w2, #0x1                ; =1
100001404: 52800023    	mov	w3, #0x1                ; =1
100001408: d63f0120    	blr	x9
10000140c: 794073e8    	ldrh	w8, [sp, #0x38]
100001410: 35000d68    	cbnz	w8, 0x1000015bc <_main+0xef4>
100001414: f9401bf4    	ldr	x20, [sp, #0x30]
100001418: f9400f28    	ldr	x8, [x25, #0x18]
10000141c: 8b160296    	add	x22, x20, x22
100001420: f1001edf    	cmp	x22, #0x7
100001424: 54fffc03    	b.lo	0x1000013a4 <_main+0xcdc>
100001428: d2800016    	mov	x22, #0x0               ; =0
10000142c: f0000077    	adrp	x23, 0x100010000 <dyld_stub_binder+0x100010000>
100001430: 911cc6f7    	add	x23, x23, #0x731
100001434: 52800098    	mov	w24, #0x4               ; =4
100001438: 8b1602e1    	add	x1, x23, x22
10000143c: cb160314    	sub	x20, x24, x22
100001440: 8b080289    	add	x9, x20, x8
100001444: f940caaa    	ldr	x10, [x21, #0x190]
100001448: eb0a013f    	cmp	x9, x10
10000144c: 54000188    	b.hi	0x10000147c <_main+0xdb4>
100001450: f9400349    	ldr	x9, [x26]
100001454: 8b080120    	add	x0, x9, x8
100001458: aa1403e2    	mov	x2, x20
10000145c: 94003857    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
100001460: f9400b48    	ldr	x8, [x26, #0x10]
100001464: 8b140108    	add	x8, x8, x20
100001468: f9000b48    	str	x8, [x26, #0x10]
10000146c: 8b160296    	add	x22, x20, x22
100001470: f10012df    	cmp	x22, #0x4
100001474: 54fffe23    	b.lo	0x100001438 <_main+0xd70>
100001478: 14000011    	b	0x1000014bc <_main+0xdf4>
10000147c: f9400328    	ldr	x8, [x25]
100001480: f9400109    	ldr	x9, [x8]
100001484: a938d3a1    	stp	x1, x20, [x29, #-0x78]
100001488: 9100c3e8    	add	x8, sp, #0x30
10000148c: d101e3a1    	sub	x1, x29, #0x78
100001490: aa1903e0    	mov	x0, x25
100001494: 52800022    	mov	w2, #0x1                ; =1
100001498: 52800023    	mov	w3, #0x1                ; =1
10000149c: d63f0120    	blr	x9
1000014a0: 794073e8    	ldrh	w8, [sp, #0x38]
1000014a4: 350008c8    	cbnz	w8, 0x1000015bc <_main+0xef4>
1000014a8: f9401bf4    	ldr	x20, [sp, #0x30]
1000014ac: f9400f28    	ldr	x8, [x25, #0x18]
1000014b0: 8b160296    	add	x22, x20, x22
1000014b4: f10012df    	cmp	x22, #0x4
1000014b8: 54fffc03    	b.lo	0x100001438 <_main+0xd70>
1000014bc: d2800016    	mov	x22, #0x0               ; =0
1000014c0: d0000097    	adrp	x23, 0x100013000 <___anon_5016+0x2840>
1000014c4: 91089ef7    	add	x23, x23, #0x227
1000014c8: 528000b8    	mov	w24, #0x5               ; =5
1000014cc: 8b1602e1    	add	x1, x23, x22
1000014d0: cb160314    	sub	x20, x24, x22
1000014d4: 8b080289    	add	x9, x20, x8
1000014d8: f940caaa    	ldr	x10, [x21, #0x190]
1000014dc: eb0a013f    	cmp	x9, x10
1000014e0: 54000188    	b.hi	0x100001510 <_main+0xe48>
1000014e4: f9400349    	ldr	x9, [x26]
1000014e8: 8b080120    	add	x0, x9, x8
1000014ec: aa1403e2    	mov	x2, x20
1000014f0: 94003832    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
1000014f4: f9400b48    	ldr	x8, [x26, #0x10]
1000014f8: 8b140108    	add	x8, x8, x20
1000014fc: f9000b48    	str	x8, [x26, #0x10]
100001500: 8b160296    	add	x22, x20, x22
100001504: f10016df    	cmp	x22, #0x5
100001508: 54fffe23    	b.lo	0x1000014cc <_main+0xe04>
10000150c: 14000011    	b	0x100001550 <_main+0xe88>
100001510: f9400328    	ldr	x8, [x25]
100001514: f9400109    	ldr	x9, [x8]
100001518: a938d3a1    	stp	x1, x20, [x29, #-0x78]
10000151c: 9100c3e8    	add	x8, sp, #0x30
100001520: d101e3a1    	sub	x1, x29, #0x78
100001524: aa1903e0    	mov	x0, x25
100001528: 52800022    	mov	w2, #0x1                ; =1
10000152c: 52800023    	mov	w3, #0x1                ; =1
100001530: d63f0120    	blr	x9
100001534: 794073e8    	ldrh	w8, [sp, #0x38]
100001538: 35000428    	cbnz	w8, 0x1000015bc <_main+0xef4>
10000153c: f9401bf4    	ldr	x20, [sp, #0x30]
100001540: f9400f28    	ldr	x8, [x25, #0x18]
100001544: 8b160296    	add	x22, x20, x22
100001548: f10016df    	cmp	x22, #0x5
10000154c: 54fffc03    	b.lo	0x1000014cc <_main+0xe04>
100001550: f0000074    	adrp	x20, 0x100010000 <dyld_stub_binder+0x100010000>
100001554: 911cd694    	add	x20, x20, #0x735
100001558: 52800036    	mov	w22, #0x1               ; =1
10000155c: f940caa9    	ldr	x9, [x21, #0x190]
100001560: eb09011f    	cmp	x8, x9
100001564: 54000203    	b.lo	0x1000015a4 <_main+0xedc>
100001568: f9400328    	ldr	x8, [x25]
10000156c: f9400109    	ldr	x9, [x8]
100001570: a938dbb4    	stp	x20, x22, [x29, #-0x78]
100001574: 9100c3e8    	add	x8, sp, #0x30
100001578: d101e3a1    	sub	x1, x29, #0x78
10000157c: aa1903e0    	mov	x0, x25
100001580: 52800022    	mov	w2, #0x1                ; =1
100001584: 52800023    	mov	w3, #0x1                ; =1
100001588: d63f0120    	blr	x9
10000158c: 794073e8    	ldrh	w8, [sp, #0x38]
100001590: 35000168    	cbnz	w8, 0x1000015bc <_main+0xef4>
100001594: f9401be9    	ldr	x9, [sp, #0x30]
100001598: f940ce68    	ldr	x8, [x19, #0x198]
10000159c: b4fffe09    	cbz	x9, 0x10000155c <_main+0xe94>
1000015a0: 14000007    	b	0x1000015bc <_main+0xef4>
1000015a4: f9400349    	ldr	x9, [x26]
1000015a8: 5280014a    	mov	w10, #0xa               ; =10
1000015ac: 3828692a    	strb	w10, [x9, x8]
1000015b0: f9400b48    	ldr	x8, [x26, #0x10]
1000015b4: 91000508    	add	x8, x8, #0x1
1000015b8: f9000b48    	str	x8, [x26, #0x10]
1000015bc: f00000d4    	adrp	x20, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000015c0: 9105a294    	add	x20, x20, #0x168
1000015c4: aa1403e0    	mov	x0, x20
1000015c8: f8418c08    	ldr	x8, [x0, #0x18]!
1000015cc: f9400908    	ldr	x8, [x8, #0x10]
1000015d0: d63f0100    	blr	x8
1000015d4: b201f3e8    	mov	x8, #-0x5555555555555556 ; =-6148914691236517206
1000015d8: a902fe9f    	stp	xzr, xzr, [x20, #0x28]
1000015dc: f9001288    	str	x8, [x20, #0x20]
1000015e0: f9400288    	ldr	x8, [x20]
1000015e4: f1000508    	subs	x8, x8, #0x1
1000015e8: f9000288    	str	x8, [x20]
1000015ec: 540000e1    	b.ne	0x100001608 <_main+0xf40>
1000015f0: 92800008    	mov	x8, #-0x1               ; =-1
1000015f4: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000015f8: 91058129    	add	x9, x9, #0x160
1000015fc: f9000128    	str	x8, [x9]
100001600: 91004120    	add	x0, x9, #0x10
100001604: 9400380e    	bl	0x10000f63c <dyld_stub_binder+0x10000f63c>
100001608: 9101c3e0    	add	x0, sp, #0x70
10000160c: 94000225    	bl	0x100001ea0 <_debug.lockStderrWriter>
100001610: d2800016    	mov	x22, #0x0               ; =0
100001614: f940ce68    	ldr	x8, [x19, #0x198]
100001618: f0000073    	adrp	x19, 0x100010000 <dyld_stub_binder+0x100010000>
10000161c: 911cda73    	add	x19, x19, #0x736
100001620: 528006b7    	mov	w23, #0x35              ; =53
100001624: 8b160261    	add	x1, x19, x22
100001628: cb1602f4    	sub	x20, x23, x22
10000162c: 8b080289    	add	x9, x20, x8
100001630: f940caaa    	ldr	x10, [x21, #0x190]
100001634: eb0a013f    	cmp	x9, x10
100001638: 54000188    	b.hi	0x100001668 <_main+0xfa0>
10000163c: f9400349    	ldr	x9, [x26]
100001640: 8b080120    	add	x0, x9, x8
100001644: aa1403e2    	mov	x2, x20
100001648: 940037dc    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
10000164c: f9400b48    	ldr	x8, [x26, #0x10]
100001650: 8b140108    	add	x8, x8, x20
100001654: f9000b48    	str	x8, [x26, #0x10]
100001658: 8b160296    	add	x22, x20, x22
10000165c: f100d6df    	cmp	x22, #0x35
100001660: 54fffe23    	b.lo	0x100001624 <_main+0xf5c>
100001664: 14000011    	b	0x1000016a8 <_main+0xfe0>
100001668: f9400328    	ldr	x8, [x25]
10000166c: f9400109    	ldr	x9, [x8]
100001670: a938d3a1    	stp	x1, x20, [x29, #-0x78]
100001674: 9100c3e8    	add	x8, sp, #0x30
100001678: d101e3a1    	sub	x1, x29, #0x78
10000167c: aa1903e0    	mov	x0, x25
100001680: 52800022    	mov	w2, #0x1                ; =1
100001684: 52800023    	mov	w3, #0x1                ; =1
100001688: d63f0120    	blr	x9
10000168c: 794073e8    	ldrh	w8, [sp, #0x38]
100001690: 350000c8    	cbnz	w8, 0x1000016a8 <_main+0xfe0>
100001694: f9401bf4    	ldr	x20, [sp, #0x30]
100001698: f9400f28    	ldr	x8, [x25, #0x18]
10000169c: 8b160296    	add	x22, x20, x22
1000016a0: f100d6df    	cmp	x22, #0x35
1000016a4: 54fffc03    	b.lo	0x100001624 <_main+0xf5c>
1000016a8: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000016ac: 9105a273    	add	x19, x19, #0x168
1000016b0: aa1303e0    	mov	x0, x19
1000016b4: f8418c08    	ldr	x8, [x0, #0x18]!
1000016b8: f9400908    	ldr	x8, [x8, #0x10]
1000016bc: d63f0100    	blr	x8
1000016c0: b201f3e8    	mov	x8, #-0x5555555555555556 ; =-6148914691236517206
1000016c4: a902fe7f    	stp	xzr, xzr, [x19, #0x28]
1000016c8: f9001268    	str	x8, [x19, #0x20]
1000016cc: f9400268    	ldr	x8, [x19]
1000016d0: f1000508    	subs	x8, x8, #0x1
1000016d4: f9000268    	str	x8, [x19]
1000016d8: 540000e1    	b.ne	0x1000016f4 <_main+0x102c>
1000016dc: 92800008    	mov	x8, #-0x1               ; =-1
1000016e0: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000016e4: 91058129    	add	x9, x9, #0x160
1000016e8: f9000128    	str	x8, [x9]
1000016ec: 91004120    	add	x0, x9, #0x10
1000016f0: 940037d3    	bl	0x10000f63c <dyld_stub_binder+0x10000f63c>
1000016f4: d2800014    	mov	x20, #0x0               ; =0
1000016f8: f0000068    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
1000016fc: 395fa119    	ldrb	w25, [x8, #0x7e8]
100001700: 9101c3fc    	add	x28, sp, #0x70
100001704: d29eb87b    	mov	x27, #0xf5c3            ; =62915
100001708: f2ab851b    	movk	x27, #0x5c28, lsl #16
10000170c: f2d851fb    	movk	x27, #0xc28f, lsl #32
100001710: f2e51ebb    	movk	x27, #0x28f5, lsl #48
100001714: 52800c96    	mov	w22, #0x64              ; =100
100001718: d000009a    	adrp	x26, 0x100013000 <___anon_5016+0x2840>
10000171c: 9108db5a    	add	x26, x26, #0x236
100001720: b90007f9    	str	w25, [sp, #0x4]
100001724: 14000004    	b	0x100001734 <_main+0x106c>
100001728: 91000694    	add	x20, x20, #0x1
10000172c: f100169f    	cmp	x20, #0x5
100001730: 54002a60    	b.eq	0x100001c7c <_main+0x15b4>
100001734: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001738: 91036108    	add	x8, x8, #0xd8
10000173c: 8b141108    	add	x8, x8, x20, lsl #4
100001740: a9402115    	ldp	x21, x8, [x8]
100001744: f9000fe8    	str	x8, [sp, #0x18]
100001748: f0000068    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
10000174c: 911ba108    	add	x8, x8, #0x6e8
100001750: f8747918    	ldr	x24, [x8, x20, lsl #3]
100001754: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001758: 91022108    	add	x8, x8, #0x88
10000175c: f8747917    	ldr	x23, [x8, x20, lsl #3]
100001760: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001764: 9102c108    	add	x8, x8, #0xb0
100001768: f8747919    	ldr	x25, [x8, x20, lsl #3]
10000176c: 2f00e408    	movi	d8, #0000000000000000
100001770: 5280fa13    	mov	w19, #0x7d0             ; =2000
100001774: d63f02e0    	blr	x23
100001778: d63f0320    	blr	x25
10000177c: 1e602908    	fadd	d8, d8, d0
100001780: f1000673    	subs	x19, x19, #0x1
100001784: 54ffff81    	b.ne	0x100001774 <_main+0x10ac>
100001788: fd0017e8    	str	d8, [sp, #0x28]
10000178c: 9100a3e8    	add	x8, sp, #0x28
100001790: 9101c3e1    	add	x1, sp, #0x70
100001794: 52800100    	mov	w0, #0x8                ; =8
100001798: 9400377f    	bl	0x10000f594 <dyld_stub_binder+0x10000f594>
10000179c: 3100041f    	cmn	w0, #0x1
1000017a0: 54000081    	b.ne	0x1000017b0 <_main+0x10e8>
1000017a4: 9400378e    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
1000017a8: b9400008    	ldr	w8, [x0]
1000017ac: 350027c8    	cbnz	w8, 0x100001ca4 <_main+0x15dc>
1000017b0: a900d3f5    	stp	x21, x20, [sp, #0x8]
1000017b4: a94757f3    	ldp	x19, x21, [sp, #0x70]
1000017b8: 2f00e408    	movi	d8, #0000000000000000
1000017bc: aa1803f4    	mov	x20, x24
1000017c0: d63f02e0    	blr	x23
1000017c4: d63f0320    	blr	x25
1000017c8: 1e602908    	fadd	d8, d8, d0
1000017cc: f1000694    	subs	x20, x20, #0x1
1000017d0: 54ffff81    	b.ne	0x1000017c0 <_main+0x10f8>
1000017d4: 9101c3e1    	add	x1, sp, #0x70
1000017d8: 52800100    	mov	w0, #0x8                ; =8
1000017dc: 9400376e    	bl	0x10000f594 <dyld_stub_binder+0x10000f594>
1000017e0: 3100041f    	cmn	w0, #0x1
1000017e4: 54000041    	b.ne	0x1000017ec <_main+0x1124>
1000017e8: 9400377d    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
1000017ec: a94723e9    	ldp	x9, x8, [sp, #0x70]
1000017f0: eb130129    	subs	x9, x9, x19
1000017f4: 1a9fa7ea    	cset	w10, lt
1000017f8: 5280004b    	mov	w11, #0x2               ; =2
1000017fc: 1a8a016a    	csel	w10, w11, w10, eq
100001800: 3901c3ea    	strb	w10, [sp, #0x70]
100001804: 7100095f    	cmp	w10, #0x2
100001808: f9400bf4    	ldr	x20, [sp, #0x10]
10000180c: b94007f9    	ldr	w25, [sp, #0x4]
100001810: 540000a1    	b.ne	0x100001824 <_main+0x115c>
100001814: eb15011f    	cmp	x8, x21
100001818: 1a9fa7ea    	cset	w10, lt
10000181c: 1a8a016a    	csel	w10, w11, w10, eq
100001820: 3901c3ea    	strb	w10, [sp, #0x70]
100001824: 7100015f    	cmp	w10, #0x0
100001828: 9a950113    	csel	x19, x8, x21, eq
10000182c: 9a9f0137    	csel	x23, x9, xzr, eq
100001830: fd0013e8    	str	d8, [sp, #0x20]
100001834: 910083e8    	add	x8, sp, #0x20
100001838: 9100c3e0    	add	x0, sp, #0x30
10000183c: 94000199    	bl	0x100001ea0 <_debug.lockStderrWriter>
100001840: f94007e0    	ldr	x0, [sp, #0x8]
100001844: f9400fe1    	ldr	x1, [sp, #0x18]
100001848: aa0103e2    	mov	x2, x1
10000184c: aa1903e3    	mov	x3, x25
100001850: 52800404    	mov	w4, #0x20               ; =32
100001854: 94003186    	bl	0x10000de6c <_Io.Writer.alignBuffer>
100001858: 72003c1f    	tst	w0, #0xffff
10000185c: 54001e81    	b.ne	0x100001c2c <_main+0x1564>
100001860: cb150268    	sub	x8, x19, x21
100001864: 52994009    	mov	w9, #0xca00             ; =51712
100001868: 72a77349    	movk	w9, #0x3b9a, lsl #16
10000186c: 9b0922f7    	madd	x23, x23, x9, x8
100001870: 9e6302e0    	ucvtf	d0, x23
100001874: 9e630301    	ucvtf	d1, x24
100001878: 1e611809    	fdiv	d9, d0, d1
10000187c: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001880: 91064129    	add	x9, x9, #0x190
100001884: a9402129    	ldp	x9, x8, [x9]
100001888: eb09011f    	cmp	x8, x9
10000188c: 54000263    	b.lo	0x1000018d8 <_main+0x1210>
100001890: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001894: 91060000    	add	x0, x0, #0x180
100001898: f9400008    	ldr	x8, [x0]
10000189c: f9400109    	ldr	x9, [x8]
1000018a0: f0000068    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
1000018a4: 911dad0a    	add	x10, x8, #0x76b
1000018a8: 52800028    	mov	w8, #0x1                ; =1
1000018ac: a938a3aa    	stp	x10, x8, [x29, #-0x78]
1000018b0: 9101c3e8    	add	x8, sp, #0x70
1000018b4: d101e3a1    	sub	x1, x29, #0x78
1000018b8: 52800022    	mov	w2, #0x1                ; =1
1000018bc: 52800023    	mov	w3, #0x1                ; =1
1000018c0: d63f0120    	blr	x9
1000018c4: 7940f3e8    	ldrh	w8, [sp, #0x78]
1000018c8: 35001b28    	cbnz	w8, 0x100001c2c <_main+0x1564>
1000018cc: f9403be8    	ldr	x8, [sp, #0x70]
1000018d0: b4fffd68    	cbz	x8, 0x10000187c <_main+0x11b4>
1000018d4: 14000009    	b	0x1000018f8 <_main+0x1230>
1000018d8: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000018dc: 9106214a    	add	x10, x10, #0x188
1000018e0: f9400149    	ldr	x9, [x10]
1000018e4: 5280058b    	mov	w11, #0x2c              ; =44
1000018e8: 3828692b    	strb	w11, [x9, x8]
1000018ec: f9400948    	ldr	x8, [x10, #0x10]
1000018f0: 91000508    	add	x8, x8, #0x1
1000018f4: f9000948    	str	x8, [x10, #0x10]
1000018f8: d2800008    	mov	x8, #0x0                ; =0
1000018fc: aa1803e9    	mov	x9, x24
100001900: 8b08038a    	add	x10, x28, x8
100001904: d342ff0b    	lsr	x11, x24, #2
100001908: 9bdb7d6b    	umulh	x11, x11, x27
10000190c: d342fd78    	lsr	x24, x11, #2
100001910: 9b16a70b    	msub	x11, x24, x22, x9
100001914: 786b7b4b    	ldrh	w11, [x26, x11, lsl #1]
100001918: 7803f14b    	sturh	w11, [x10, #0x3f]
10000191c: d1000908    	sub	x8, x8, #0x2
100001920: d344fd2a    	lsr	x10, x9, #4
100001924: f109c15f    	cmp	x10, #0x270
100001928: 54fffea8    	b.hi	0x1000018fc <_main+0x1234>
10000192c: f10f9d3f    	cmp	x9, #0x3e7
100001930: 540000c8    	b.hi	0x100001948 <_main+0x1280>
100001934: 91010109    	add	x9, x8, #0x40
100001938: 8b080388    	add	x8, x28, x8
10000193c: 321c070a    	orr	w10, w24, #0x30
100001940: 3901010a    	strb	w10, [x8, #0x40]
100001944: 14000005    	b	0x100001958 <_main+0x1290>
100001948: 9100fd09    	add	x9, x8, #0x3f
10000194c: 8b080388    	add	x8, x28, x8
100001950: 78787b4a    	ldrh	w10, [x26, x24, lsl #1]
100001954: 7803f10a    	sturh	w10, [x8, #0x3f]
100001958: 52800828    	mov	w8, #0x41               ; =65
10000195c: cb090101    	sub	x1, x8, x9
100001960: 8b090380    	add	x0, x28, x9
100001964: aa0103e2    	mov	x2, x1
100001968: aa1903e3    	mov	x3, x25
10000196c: 52800404    	mov	w4, #0x20               ; =32
100001970: 9400313f    	bl	0x10000de6c <_Io.Writer.alignBuffer>
100001974: 72003c1f    	tst	w0, #0xffff
100001978: 540015a1    	b.ne	0x100001c2c <_main+0x1564>
10000197c: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001980: 91064129    	add	x9, x9, #0x190
100001984: a9402129    	ldp	x9, x8, [x9]
100001988: eb09011f    	cmp	x8, x9
10000198c: 54000263    	b.lo	0x1000019d8 <_main+0x1310>
100001990: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001994: 91060000    	add	x0, x0, #0x180
100001998: f9400008    	ldr	x8, [x0]
10000199c: f9400109    	ldr	x9, [x8]
1000019a0: f0000068    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
1000019a4: 911dad0a    	add	x10, x8, #0x76b
1000019a8: 52800028    	mov	w8, #0x1                ; =1
1000019ac: a938a3aa    	stp	x10, x8, [x29, #-0x78]
1000019b0: 9101c3e8    	add	x8, sp, #0x70
1000019b4: d101e3a1    	sub	x1, x29, #0x78
1000019b8: 52800022    	mov	w2, #0x1                ; =1
1000019bc: 52800023    	mov	w3, #0x1                ; =1
1000019c0: d63f0120    	blr	x9
1000019c4: 7940f3e8    	ldrh	w8, [sp, #0x78]
1000019c8: 35001328    	cbnz	w8, 0x100001c2c <_main+0x1564>
1000019cc: f9403be8    	ldr	x8, [sp, #0x70]
1000019d0: b4fffd68    	cbz	x8, 0x10000197c <_main+0x12b4>
1000019d4: 14000009    	b	0x1000019f8 <_main+0x1330>
1000019d8: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000019dc: 9106214a    	add	x10, x10, #0x188
1000019e0: f9400149    	ldr	x9, [x10]
1000019e4: 5280058b    	mov	w11, #0x2c              ; =44
1000019e8: 3828692b    	strb	w11, [x9, x8]
1000019ec: f9400948    	ldr	x8, [x10, #0x10]
1000019f0: 91000508    	add	x8, x8, #0x1
1000019f4: f9000948    	str	x8, [x10, #0x10]
1000019f8: f10192ff    	cmp	x23, #0x64
1000019fc: 54000283    	b.lo	0x100001a4c <_main+0x1384>
100001a00: 528007e8    	mov	w8, #0x3f               ; =63
100001a04: aa1703e9    	mov	x9, x23
100001a08: d342feea    	lsr	x10, x23, #2
100001a0c: 9bdb7d4a    	umulh	x10, x10, x27
100001a10: d342fd57    	lsr	x23, x10, #2
100001a14: 9b16a6ea    	msub	x10, x23, x22, x9
100001a18: 786a7b4a    	ldrh	w10, [x26, x10, lsl #1]
100001a1c: 78286b8a    	strh	w10, [x28, x8]
100001a20: d1000908    	sub	x8, x8, #0x2
100001a24: d344fd29    	lsr	x9, x9, #4
100001a28: f109c13f    	cmp	x9, #0x270
100001a2c: 54fffec8    	b.hi	0x100001a04 <_main+0x133c>
100001a30: 91000908    	add	x8, x8, #0x2
100001a34: f10026ff    	cmp	x23, #0x9
100001a38: 54000109    	b.ls	0x100001a58 <_main+0x1390>
100001a3c: d1000908    	sub	x8, x8, #0x2
100001a40: 78777b49    	ldrh	w9, [x26, x23, lsl #1]
100001a44: 78286b89    	strh	w9, [x28, x8]
100001a48: 14000007    	b	0x100001a64 <_main+0x139c>
100001a4c: 52800828    	mov	w8, #0x41               ; =65
100001a50: f10026ff    	cmp	x23, #0x9
100001a54: 54ffff48    	b.hi	0x100001a3c <_main+0x1374>
100001a58: d1000508    	sub	x8, x8, #0x1
100001a5c: 321c06e9    	orr	w9, w23, #0x30
100001a60: 38286b89    	strb	w9, [x28, x8]
100001a64: 52800829    	mov	w9, #0x41               ; =65
100001a68: cb080121    	sub	x1, x9, x8
100001a6c: 8b080380    	add	x0, x28, x8
100001a70: aa0103e2    	mov	x2, x1
100001a74: aa1903e3    	mov	x3, x25
100001a78: 52800404    	mov	w4, #0x20               ; =32
100001a7c: 940030fc    	bl	0x10000de6c <_Io.Writer.alignBuffer>
100001a80: 72003c1f    	tst	w0, #0xffff
100001a84: 54000d41    	b.ne	0x100001c2c <_main+0x1564>
100001a88: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001a8c: 91064129    	add	x9, x9, #0x190
100001a90: a9402129    	ldp	x9, x8, [x9]
100001a94: eb09011f    	cmp	x8, x9
100001a98: 54000263    	b.lo	0x100001ae4 <_main+0x141c>
100001a9c: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001aa0: 91060000    	add	x0, x0, #0x180
100001aa4: f9400008    	ldr	x8, [x0]
100001aa8: f9400109    	ldr	x9, [x8]
100001aac: f0000068    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
100001ab0: 911dad0a    	add	x10, x8, #0x76b
100001ab4: 52800028    	mov	w8, #0x1                ; =1
100001ab8: a938a3aa    	stp	x10, x8, [x29, #-0x78]
100001abc: 9101c3e8    	add	x8, sp, #0x70
100001ac0: d101e3a1    	sub	x1, x29, #0x78
100001ac4: 52800022    	mov	w2, #0x1                ; =1
100001ac8: 52800023    	mov	w3, #0x1                ; =1
100001acc: d63f0120    	blr	x9
100001ad0: 7940f3e8    	ldrh	w8, [sp, #0x78]
100001ad4: 35000ac8    	cbnz	w8, 0x100001c2c <_main+0x1564>
100001ad8: f9403be8    	ldr	x8, [sp, #0x70]
100001adc: b4fffd68    	cbz	x8, 0x100001a88 <_main+0x13c0>
100001ae0: 14000009    	b	0x100001b04 <_main+0x143c>
100001ae4: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001ae8: 9106214a    	add	x10, x10, #0x188
100001aec: f9400149    	ldr	x9, [x10]
100001af0: 5280058b    	mov	w11, #0x2c              ; =44
100001af4: 3828692b    	strb	w11, [x9, x8]
100001af8: f9400948    	ldr	x8, [x10, #0x10]
100001afc: 91000508    	add	x8, x8, #0x1
100001b00: f9000948    	str	x8, [x10, #0x10]
100001b04: f0000060    	adrp	x0, 0x100010000 <dyld_stub_binder+0x100010000>
100001b08: 911dc000    	add	x0, x0, #0x770
100001b0c: 1e604120    	fmov	d0, d9
100001b10: 94002b19    	bl	0x10000c774 <_Io.Writer.printValue__anon_4346>
100001b14: 72003c1f    	tst	w0, #0xffff
100001b18: 540008a1    	b.ne	0x100001c2c <_main+0x1564>
100001b1c: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001b20: 91064129    	add	x9, x9, #0x190
100001b24: a9402129    	ldp	x9, x8, [x9]
100001b28: eb09011f    	cmp	x8, x9
100001b2c: 54000263    	b.lo	0x100001b78 <_main+0x14b0>
100001b30: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001b34: 91060000    	add	x0, x0, #0x180
100001b38: f9400008    	ldr	x8, [x0]
100001b3c: f9400109    	ldr	x9, [x8]
100001b40: f0000068    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
100001b44: 911dad0a    	add	x10, x8, #0x76b
100001b48: 52800028    	mov	w8, #0x1                ; =1
100001b4c: a938a3aa    	stp	x10, x8, [x29, #-0x78]
100001b50: 9101c3e8    	add	x8, sp, #0x70
100001b54: d101e3a1    	sub	x1, x29, #0x78
100001b58: 52800022    	mov	w2, #0x1                ; =1
100001b5c: 52800023    	mov	w3, #0x1                ; =1
100001b60: d63f0120    	blr	x9
100001b64: 7940f3e8    	ldrh	w8, [sp, #0x78]
100001b68: 35000628    	cbnz	w8, 0x100001c2c <_main+0x1564>
100001b6c: f9403be8    	ldr	x8, [sp, #0x70]
100001b70: b4fffd68    	cbz	x8, 0x100001b1c <_main+0x1454>
100001b74: 14000009    	b	0x100001b98 <_main+0x14d0>
100001b78: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001b7c: 9106214a    	add	x10, x10, #0x188
100001b80: f9400149    	ldr	x9, [x10]
100001b84: 5280058b    	mov	w11, #0x2c              ; =44
100001b88: 3828692b    	strb	w11, [x9, x8]
100001b8c: f9400948    	ldr	x8, [x10, #0x10]
100001b90: 91000508    	add	x8, x8, #0x1
100001b94: f9000948    	str	x8, [x10, #0x10]
100001b98: f0000060    	adrp	x0, 0x100010000 <dyld_stub_binder+0x100010000>
100001b9c: 911e6000    	add	x0, x0, #0x798
100001ba0: 1e604100    	fmov	d0, d8
100001ba4: 94002af4    	bl	0x10000c774 <_Io.Writer.printValue__anon_4346>
100001ba8: 72003c1f    	tst	w0, #0xffff
100001bac: 54000401    	b.ne	0x100001c2c <_main+0x1564>
100001bb0: f00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001bb4: 91064129    	add	x9, x9, #0x190
100001bb8: a9402129    	ldp	x9, x8, [x9]
100001bbc: eb09011f    	cmp	x8, x9
100001bc0: 54000263    	b.lo	0x100001c0c <_main+0x1544>
100001bc4: f00000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001bc8: 91060000    	add	x0, x0, #0x180
100001bcc: f9400008    	ldr	x8, [x0]
100001bd0: f9400109    	ldr	x9, [x8]
100001bd4: f0000068    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
100001bd8: 911cd50a    	add	x10, x8, #0x735
100001bdc: 52800028    	mov	w8, #0x1                ; =1
100001be0: a938a3aa    	stp	x10, x8, [x29, #-0x78]
100001be4: 9101c3e8    	add	x8, sp, #0x70
100001be8: d101e3a1    	sub	x1, x29, #0x78
100001bec: 52800022    	mov	w2, #0x1                ; =1
100001bf0: 52800023    	mov	w3, #0x1                ; =1
100001bf4: d63f0120    	blr	x9
100001bf8: 7940f3e8    	ldrh	w8, [sp, #0x78]
100001bfc: 35000188    	cbnz	w8, 0x100001c2c <_main+0x1564>
100001c00: f9403be8    	ldr	x8, [sp, #0x70]
100001c04: b4fffd68    	cbz	x8, 0x100001bb0 <_main+0x14e8>
100001c08: 14000009    	b	0x100001c2c <_main+0x1564>
100001c0c: f00000ca    	adrp	x10, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001c10: 9106214a    	add	x10, x10, #0x188
100001c14: f9400149    	ldr	x9, [x10]
100001c18: 5280014b    	mov	w11, #0xa               ; =10
100001c1c: 3828692b    	strb	w11, [x9, x8]
100001c20: f9400948    	ldr	x8, [x10, #0x10]
100001c24: 91000508    	add	x8, x8, #0x1
100001c28: f9000948    	str	x8, [x10, #0x10]
100001c2c: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001c30: 9105a273    	add	x19, x19, #0x168
100001c34: aa1303e0    	mov	x0, x19
100001c38: f8418c08    	ldr	x8, [x0, #0x18]!
100001c3c: f9400908    	ldr	x8, [x8, #0x10]
100001c40: d63f0100    	blr	x8
100001c44: a902fe7f    	stp	xzr, xzr, [x19, #0x28]
100001c48: b201f3e8    	mov	x8, #-0x5555555555555556 ; =-6148914691236517206
100001c4c: f9001268    	str	x8, [x19, #0x20]
100001c50: f9400268    	ldr	x8, [x19]
100001c54: f1000508    	subs	x8, x8, #0x1
100001c58: f9000268    	str	x8, [x19]
100001c5c: 54ffd661    	b.ne	0x100001728 <_main+0x1060>
100001c60: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001c64: 91058108    	add	x8, x8, #0x160
100001c68: 92800009    	mov	x9, #-0x1               ; =-1
100001c6c: f9000109    	str	x9, [x8]
100001c70: 91004100    	add	x0, x8, #0x10
100001c74: 94003672    	bl	0x10000f63c <dyld_stub_binder+0x10000f63c>
100001c78: 17fffeac    	b	0x100001728 <_main+0x1060>
100001c7c: 52800000    	mov	w0, #0x0                ; =0
100001c80: a9537bfd    	ldp	x29, x30, [sp, #0x130]
100001c84: a9524ff4    	ldp	x20, x19, [sp, #0x120]
100001c88: a95157f6    	ldp	x22, x21, [sp, #0x110]
100001c8c: a9505ff8    	ldp	x24, x23, [sp, #0x100]
100001c90: a94f67fa    	ldp	x26, x25, [sp, #0xf0]
100001c94: a94e6ffc    	ldp	x28, x27, [sp, #0xe0]
100001c98: 6d4d23e9    	ldp	d9, d8, [sp, #0xd0]
100001c9c: 910503ff    	add	sp, sp, #0x140
100001ca0: d65f03c0    	ret
100001ca4: d0000080    	adrp	x0, 0x100013000 <___anon_5016+0x2840>
100001ca8: 910bfc00    	add	x0, x0, #0x2ff
100001cac: 52800201    	mov	w1, #0x10               ; =16
100001cb0: 94000003    	bl	0x100001cbc <_log.scoped(.default).err__anon_2527>
100001cb4: 52800020    	mov	w0, #0x1                ; =1
100001cb8: 17fffff2    	b	0x100001c80 <_main+0x15b8>

0000000100001cbc <_log.scoped(.default).err__anon_2527>:
100001cbc: d102c3ff    	sub	sp, sp, #0xb0
100001cc0: a90667fa    	stp	x26, x25, [sp, #0x60]
100001cc4: a9075ff8    	stp	x24, x23, [sp, #0x70]
100001cc8: a90857f6    	stp	x22, x21, [sp, #0x80]
100001ccc: a9094ff4    	stp	x20, x19, [sp, #0x90]
100001cd0: a90a7bfd    	stp	x29, x30, [sp, #0xa0]
100001cd4: 910283fd    	add	x29, sp, #0xa0
100001cd8: aa0103f4    	mov	x20, x1
100001cdc: aa0003f5    	mov	x21, x0
100001ce0: 910003e0    	mov	x0, sp
100001ce4: 9400006f    	bl	0x100001ea0 <_debug.lockStderrWriter>
100001ce8: d2800018    	mov	x24, #0x0               ; =0
100001cec: f0000079    	adrp	x25, 0x100010000 <dyld_stub_binder+0x100010000>
100001cf0: 911f0339    	add	x25, x25, #0x7c0
100001cf4: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001cf8: f940cd08    	ldr	x8, [x8, #0x198]
100001cfc: f00000da    	adrp	x26, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001d00: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001d04: 91060273    	add	x19, x19, #0x180
100001d08: f00000d7    	adrp	x23, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001d0c: 910622f7    	add	x23, x23, #0x188
100001d10: 8b180321    	add	x1, x25, x24
100001d14: d2400b16    	eor	x22, x24, #0x7
100001d18: f940cb49    	ldr	x9, [x26, #0x190]
100001d1c: 8b0802ca    	add	x10, x22, x8
100001d20: eb09015f    	cmp	x10, x9
100001d24: 54000188    	b.hi	0x100001d54 <_log.scoped(.default).err__anon_2527+0x98>
100001d28: f94002e9    	ldr	x9, [x23]
100001d2c: 8b080120    	add	x0, x9, x8
100001d30: aa1603e2    	mov	x2, x22
100001d34: 94003621    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
100001d38: f9400ae8    	ldr	x8, [x23, #0x10]
100001d3c: 8b160108    	add	x8, x8, x22
100001d40: f9000ae8    	str	x8, [x23, #0x10]
100001d44: 8b1802d8    	add	x24, x22, x24
100001d48: f1001f1f    	cmp	x24, #0x7
100001d4c: 54fffe23    	b.lo	0x100001d10 <_log.scoped(.default).err__anon_2527+0x54>
100001d50: 14000011    	b	0x100001d94 <_log.scoped(.default).err__anon_2527+0xd8>
100001d54: f9400268    	ldr	x8, [x19]
100001d58: f9400109    	ldr	x9, [x8]
100001d5c: a9045be1    	stp	x1, x22, [sp, #0x40]
100001d60: 910143e8    	add	x8, sp, #0x50
100001d64: 910103e1    	add	x1, sp, #0x40
100001d68: aa1303e0    	mov	x0, x19
100001d6c: 52800022    	mov	w2, #0x1                ; =1
100001d70: 52800023    	mov	w3, #0x1                ; =1
100001d74: d63f0120    	blr	x9
100001d78: 7940b3e8    	ldrh	w8, [sp, #0x58]
100001d7c: 35000568    	cbnz	w8, 0x100001e28 <_log.scoped(.default).err__anon_2527+0x16c>
100001d80: f9402bf6    	ldr	x22, [sp, #0x50]
100001d84: f9400e68    	ldr	x8, [x19, #0x18]
100001d88: 8b1802d8    	add	x24, x22, x24
100001d8c: f1001f1f    	cmp	x24, #0x7
100001d90: 54fffc03    	b.lo	0x100001d10 <_log.scoped(.default).err__anon_2527+0x54>
100001d94: f0000068    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
100001d98: 395fa103    	ldrb	w3, [x8, #0x7e8]
100001d9c: aa1503e0    	mov	x0, x21
100001da0: aa1403e1    	mov	x1, x20
100001da4: aa1403e2    	mov	x2, x20
100001da8: 52800404    	mov	w4, #0x20               ; =32
100001dac: 94003030    	bl	0x10000de6c <_Io.Writer.alignBuffer>
100001db0: 72003c1f    	tst	w0, #0xffff
100001db4: 540003a1    	b.ne	0x100001e28 <_log.scoped(.default).err__anon_2527+0x16c>
100001db8: f00000d4    	adrp	x20, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001dbc: 91064294    	add	x20, x20, #0x190
100001dc0: 52800035    	mov	w21, #0x1               ; =1
100001dc4: f0000076    	adrp	x22, 0x100010000 <dyld_stub_binder+0x100010000>
100001dc8: 911cd6d6    	add	x22, x22, #0x735
100001dcc: a9402289    	ldp	x9, x8, [x20]
100001dd0: eb09011f    	cmp	x8, x9
100001dd4: 540001e3    	b.lo	0x100001e10 <_log.scoped(.default).err__anon_2527+0x154>
100001dd8: f9400268    	ldr	x8, [x19]
100001ddc: f9400109    	ldr	x9, [x8]
100001de0: a90457f6    	stp	x22, x21, [sp, #0x40]
100001de4: 910143e8    	add	x8, sp, #0x50
100001de8: 910103e1    	add	x1, sp, #0x40
100001dec: aa1303e0    	mov	x0, x19
100001df0: 52800022    	mov	w2, #0x1                ; =1
100001df4: 52800023    	mov	w3, #0x1                ; =1
100001df8: d63f0120    	blr	x9
100001dfc: 7940b3e8    	ldrh	w8, [sp, #0x58]
100001e00: 35000148    	cbnz	w8, 0x100001e28 <_log.scoped(.default).err__anon_2527+0x16c>
100001e04: f9402be8    	ldr	x8, [sp, #0x50]
100001e08: b4fffe28    	cbz	x8, 0x100001dcc <_log.scoped(.default).err__anon_2527+0x110>
100001e0c: 14000007    	b	0x100001e28 <_log.scoped(.default).err__anon_2527+0x16c>
100001e10: f94002e9    	ldr	x9, [x23]
100001e14: 5280014a    	mov	w10, #0xa               ; =10
100001e18: 3828692a    	strb	w10, [x9, x8]
100001e1c: f9400ae8    	ldr	x8, [x23, #0x10]
100001e20: 91000508    	add	x8, x8, #0x1
100001e24: f9000ae8    	str	x8, [x23, #0x10]
100001e28: f00000d3    	adrp	x19, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001e2c: 9105a273    	add	x19, x19, #0x168
100001e30: aa1303e0    	mov	x0, x19
100001e34: f8418c08    	ldr	x8, [x0, #0x18]!
100001e38: f9400908    	ldr	x8, [x8, #0x10]
100001e3c: d63f0100    	blr	x8
100001e40: b201f3e8    	mov	x8, #-0x5555555555555556 ; =-6148914691236517206
100001e44: a902fe7f    	stp	xzr, xzr, [x19, #0x28]
100001e48: f9001268    	str	x8, [x19, #0x20]
100001e4c: f9400268    	ldr	x8, [x19]
100001e50: f1000508    	subs	x8, x8, #0x1
100001e54: f9000268    	str	x8, [x19]
100001e58: 540000e1    	b.ne	0x100001e74 <_log.scoped(.default).err__anon_2527+0x1b8>
100001e5c: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001e60: 91058108    	add	x8, x8, #0x160
100001e64: 92800009    	mov	x9, #-0x1               ; =-1
100001e68: f9000109    	str	x9, [x8]
100001e6c: 91004100    	add	x0, x8, #0x10
100001e70: 940035f3    	bl	0x10000f63c <dyld_stub_binder+0x10000f63c>
100001e74: a94a7bfd    	ldp	x29, x30, [sp, #0xa0]
100001e78: a9494ff4    	ldp	x20, x19, [sp, #0x90]
100001e7c: a94857f6    	ldp	x22, x21, [sp, #0x80]
100001e80: a9475ff8    	ldp	x24, x23, [sp, #0x70]
100001e84: a94667fa    	ldp	x26, x25, [sp, #0x60]
100001e88: 9102c3ff    	add	sp, sp, #0xb0
100001e8c: d65f03c0    	ret

0000000100001e90 <_start.noopSigHandler>:
100001e90: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100001e94: 910003fd    	mov	x29, sp
100001e98: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100001e9c: d65f03c0    	ret

0000000100001ea0 <_debug.lockStderrWriter>:
100001ea0: d10103ff    	sub	sp, sp, #0x40
100001ea4: a90157f6    	stp	x22, x21, [sp, #0x10]
100001ea8: a9024ff4    	stp	x20, x19, [sp, #0x20]
100001eac: a9037bfd    	stp	x29, x30, [sp, #0x30]
100001eb0: 9100c3fd    	add	x29, sp, #0x30
100001eb4: aa0003f3    	mov	x19, x0
100001eb8: 910023e1    	add	x1, sp, #0x8
100001ebc: d2800000    	mov	x0, #0x0                ; =0
100001ec0: 940035e2    	bl	0x10000f648 <dyld_stub_binder+0x10000f648>
100001ec4: f94007f4    	ldr	x20, [sp, #0x8]
100001ec8: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001ecc: f940b108    	ldr	x8, [x8, #0x160]
100001ed0: eb14011f    	cmp	x8, x20
100001ed4: 540000a1    	b.ne	0x100001ee8 <_debug.lockStderrWriter+0x48>
100001ed8: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001edc: f940b508    	ldr	x8, [x8, #0x168]
100001ee0: 91000508    	add	x8, x8, #0x1
100001ee4: 14000007    	b	0x100001f00 <_debug.lockStderrWriter+0x60>
100001ee8: f00000d5    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001eec: 910582b5    	add	x21, x21, #0x160
100001ef0: 910042a0    	add	x0, x21, #0x10
100001ef4: 940035cf    	bl	0x10000f630 <dyld_stub_binder+0x10000f630>
100001ef8: f90002b4    	str	x20, [x21]
100001efc: 52800028    	mov	w8, #0x1                ; =1
100001f00: f00000d4    	adrp	x20, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001f04: 9105a294    	add	x20, x20, #0x168
100001f08: f9000288    	str	x8, [x20]
100001f0c: aa1403e0    	mov	x0, x20
100001f10: f8418c08    	ldr	x8, [x0, #0x18]!
100001f14: f9400908    	ldr	x8, [x8, #0x10]
100001f18: d63f0100    	blr	x8
100001f1c: 52800808    	mov	w8, #0x40               ; =64
100001f20: a9022293    	stp	x19, x8, [x20, #0x20]
100001f24: a9437bfd    	ldp	x29, x30, [sp, #0x30]
100001f28: a9424ff4    	ldp	x20, x19, [sp, #0x20]
100001f2c: a94157f6    	ldp	x22, x21, [sp, #0x10]
100001f30: 910103ff    	add	sp, sp, #0x40
100001f34: d65f03c0    	ret

0000000100001f38 <_codegen_smul12x10>:
100001f38: 6dba3bef    	stp	d15, d14, [sp, #-0x60]!
100001f3c: 6d0133ed    	stp	d13, d12, [sp, #0x10]
100001f40: 6d022beb    	stp	d11, d10, [sp, #0x20]
100001f44: 6d0323e9    	stp	d9, d8, [sp, #0x30]
100001f48: a9046ffc    	stp	x28, x27, [sp, #0x40]
100001f4c: a9057bfd    	stp	x29, x30, [sp, #0x50]
100001f50: 910143fd    	add	x29, sp, #0x50
100001f54: d10f03ff    	sub	sp, sp, #0x3c0
100001f58: f00000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100001f5c: 9119c108    	add	x8, x8, #0x670
100001f60: 6d404107    	ldp	d7, d16, [x8]
100001f64: 3dc12119    	ldr	q25, [x8, #0x480]
100001f68: 4fc79320    	fmul.2d	v0, v25, v7[0]
100001f6c: 3dc1391a    	ldr	q26, [x8, #0x4e0]
100001f70: 4fd09341    	fmul.2d	v1, v26, v16[0]
100001f74: 4e61d400    	fadd.2d	v0, v0, v1
100001f78: 6d411504    	ldp	d4, d5, [x8, #0x10]
100001f7c: 3dc15101    	ldr	q1, [x8, #0x540]
100001f80: 3c9a03a1    	stur	q1, [x29, #-0x60]
100001f84: 4fc49021    	fmul.2d	v1, v1, v4[0]
100001f88: 4e61d400    	fadd.2d	v0, v0, v1
100001f8c: 3dc16909    	ldr	q9, [x8, #0x5a0]
100001f90: 4fc59121    	fmul.2d	v1, v9, v5[0]
100001f94: 3d8063e9    	str	q9, [sp, #0x180]
100001f98: 4e61d400    	fadd.2d	v0, v0, v1
100001f9c: 6d421903    	ldp	d3, d6, [x8, #0x20]
100001fa0: 3dc18101    	ldr	q1, [x8, #0x600]
100001fa4: 3d8033e1    	str	q1, [sp, #0xc0]
100001fa8: 4fc39021    	fmul.2d	v1, v1, v3[0]
100001fac: 4e61d400    	fadd.2d	v0, v0, v1
100001fb0: 3dc19901    	ldr	q1, [x8, #0x660]
100001fb4: 3d803fe1    	str	q1, [sp, #0xf0]
100001fb8: 4fc69021    	fmul.2d	v1, v1, v6[0]
100001fbc: 4e61d400    	fadd.2d	v0, v0, v1
100001fc0: 6d437102    	ldp	d2, d28, [x8, #0x30]
100001fc4: 3dc1b10e    	ldr	q14, [x8, #0x6c0]
100001fc8: 4fc291c1    	fmul.2d	v1, v14, v2[0]
100001fcc: 4e61d400    	fadd.2d	v0, v0, v1
100001fd0: 3dc1c901    	ldr	q1, [x8, #0x720]
100001fd4: 3d802fe1    	str	q1, [sp, #0xb0]
100001fd8: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100001fdc: 4e61d411    	fadd.2d	v17, v0, v1
100001fe0: 6d440500    	ldp	d0, d1, [x8, #0x40]
100001fe4: 3dc1e10f    	ldr	q15, [x8, #0x780]
100001fe8: 4fc091f2    	fmul.2d	v18, v15, v0[0]
100001fec: 3d8003ef    	str	q15, [sp]
100001ff0: 4e72d631    	fadd.2d	v17, v17, v18
100001ff4: 3dc1f912    	ldr	q18, [x8, #0x7e0]
100001ff8: 3d8017f2    	str	q18, [sp, #0x50]
100001ffc: 4fc19252    	fmul.2d	v18, v18, v1[0]
100002000: 4e72d631    	fadd.2d	v17, v17, v18
100002004: 3dc1251f    	ldr	q31, [x8, #0x490]
100002008: 4fc793f2    	fmul.2d	v18, v31, v7[0]
10000200c: 3dc13d13    	ldr	q19, [x8, #0x4f0]
100002010: ad0abbf3    	stp	q19, q14, [sp, #0x150]
100002014: 4fd09273    	fmul.2d	v19, v19, v16[0]
100002018: 4e73d652    	fadd.2d	v18, v18, v19
10000201c: 3dc1551e    	ldr	q30, [x8, #0x550]
100002020: 4fc493d3    	fmul.2d	v19, v30, v4[0]
100002024: ad01fffe    	stp	q30, q31, [sp, #0x30]
100002028: 4e73d652    	fadd.2d	v18, v18, v19
10000202c: 3dc16d1b    	ldr	q27, [x8, #0x5b0]
100002030: 4fc59373    	fmul.2d	v19, v27, v5[0]
100002034: 4e73d652    	fadd.2d	v18, v18, v19
100002038: 3dc18513    	ldr	q19, [x8, #0x610]
10000203c: 3d8087f3    	str	q19, [sp, #0x210]
100002040: 4fc39273    	fmul.2d	v19, v19, v3[0]
100002044: 4e73d652    	fadd.2d	v18, v18, v19
100002048: 3dc19d1d    	ldr	q29, [x8, #0x670]
10000204c: 4fc693b3    	fmul.2d	v19, v29, v6[0]
100002050: ad00effd    	stp	q29, q27, [sp, #0x10]
100002054: 4e73d652    	fadd.2d	v18, v18, v19
100002058: 3dc1b513    	ldr	q19, [x8, #0x6d0]
10000205c: 3d8083f3    	str	q19, [sp, #0x200]
100002060: 4fc29273    	fmul.2d	v19, v19, v2[0]
100002064: 4e73d652    	fadd.2d	v18, v18, v19
100002068: 3dc1cd13    	ldr	q19, [x8, #0x730]
10000206c: 3d804bf3    	str	q19, [sp, #0x120]
100002070: 4fdc9273    	fmul.2d	v19, v19, v28[0]
100002074: 4e73d652    	fadd.2d	v18, v18, v19
100002078: 3dc1e513    	ldr	q19, [x8, #0x790]
10000207c: 3d8047f3    	str	q19, [sp, #0x110]
100002080: 4fc09273    	fmul.2d	v19, v19, v0[0]
100002084: 4e73d652    	fadd.2d	v18, v18, v19
100002088: 3dc1fd13    	ldr	q19, [x8, #0x7f0]
10000208c: 3d8043f3    	str	q19, [sp, #0x100]
100002090: 4fc19273    	fmul.2d	v19, v19, v1[0]
100002094: 4e73d652    	fadd.2d	v18, v18, v19
100002098: 3dc12913    	ldr	q19, [x8, #0x4a0]
10000209c: 3d805ff3    	str	q19, [sp, #0x170]
1000020a0: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000020a4: 3dc14114    	ldr	q20, [x8, #0x500]
1000020a8: 3d807ff4    	str	q20, [sp, #0x1f0]
1000020ac: 4fd09294    	fmul.2d	v20, v20, v16[0]
1000020b0: 4e74d673    	fadd.2d	v19, v19, v20
1000020b4: 3dc15914    	ldr	q20, [x8, #0x560]
1000020b8: 3c9903b4    	stur	q20, [x29, #-0x70]
1000020bc: 4fc49294    	fmul.2d	v20, v20, v4[0]
1000020c0: 4e74d673    	fadd.2d	v19, v19, v20
1000020c4: 3dc17114    	ldr	q20, [x8, #0x5c0]
1000020c8: 3d807bf4    	str	q20, [sp, #0x1e0]
1000020cc: 4fc59294    	fmul.2d	v20, v20, v5[0]
1000020d0: 4e74d673    	fadd.2d	v19, v19, v20
1000020d4: 3dc18914    	ldr	q20, [x8, #0x620]
1000020d8: 3c9803b4    	stur	q20, [x29, #-0x80]
1000020dc: 4fc39294    	fmul.2d	v20, v20, v3[0]
1000020e0: 4e74d673    	fadd.2d	v19, v19, v20
1000020e4: 3dc1a114    	ldr	q20, [x8, #0x680]
1000020e8: 3d8077f4    	str	q20, [sp, #0x1d0]
1000020ec: 4fc69294    	fmul.2d	v20, v20, v6[0]
1000020f0: 4e74d673    	fadd.2d	v19, v19, v20
1000020f4: 3dc1b914    	ldr	q20, [x8, #0x6e0]
1000020f8: 3c9703b4    	stur	q20, [x29, #-0x90]
1000020fc: 4fc29294    	fmul.2d	v20, v20, v2[0]
100002100: 4e74d673    	fadd.2d	v19, v19, v20
100002104: 3dc1d114    	ldr	q20, [x8, #0x740]
100002108: 3d8073f4    	str	q20, [sp, #0x1c0]
10000210c: 4fdc9294    	fmul.2d	v20, v20, v28[0]
100002110: 4e74d673    	fadd.2d	v19, v19, v20
100002114: 3dc1e914    	ldr	q20, [x8, #0x7a0]
100002118: 3d803bf4    	str	q20, [sp, #0xe0]
10000211c: 4fc09294    	fmul.2d	v20, v20, v0[0]
100002120: 4e74d673    	fadd.2d	v19, v19, v20
100002124: 3dc20114    	ldr	q20, [x8, #0x800]
100002128: 3d806ff4    	str	q20, [sp, #0x1b0]
10000212c: 4fc19294    	fmul.2d	v20, v20, v1[0]
100002130: 4e74d673    	fadd.2d	v19, v19, v20
100002134: 3dc12d14    	ldr	q20, [x8, #0x4b0]
100002138: 3d8037f4    	str	q20, [sp, #0xd0]
10000213c: 4fc79294    	fmul.2d	v20, v20, v7[0]
100002140: 3dc14515    	ldr	q21, [x8, #0x510]
100002144: 3d806bf5    	str	q21, [sp, #0x1a0]
100002148: 4fd092b5    	fmul.2d	v21, v21, v16[0]
10000214c: 4e75d694    	fadd.2d	v20, v20, v21
100002150: 3dc15d0b    	ldr	q11, [x8, #0x570]
100002154: 4fc49175    	fmul.2d	v21, v11, v4[0]
100002158: 4e75d694    	fadd.2d	v20, v20, v21
10000215c: 3dc17515    	ldr	q21, [x8, #0x5d0]
100002160: 3d8053f5    	str	q21, [sp, #0x140]
100002164: 4fc592b5    	fmul.2d	v21, v21, v5[0]
100002168: 4e75d694    	fadd.2d	v20, v20, v21
10000216c: 3dc18d15    	ldr	q21, [x8, #0x630]
100002170: 3d8067f5    	str	q21, [sp, #0x190]
100002174: 4fc392b5    	fmul.2d	v21, v21, v3[0]
100002178: 4e75d694    	fadd.2d	v20, v20, v21
10000217c: 3dc1a50d    	ldr	q13, [x8, #0x690]
100002180: 4fc691b5    	fmul.2d	v21, v13, v6[0]
100002184: ad032fed    	stp	q13, q11, [sp, #0x60]
100002188: 4e75d694    	fadd.2d	v20, v20, v21
10000218c: 3dc1bd15    	ldr	q21, [x8, #0x6f0]
100002190: 3d804ff5    	str	q21, [sp, #0x130]
100002194: 4fc292b5    	fmul.2d	v21, v21, v2[0]
100002198: 4e75d694    	fadd.2d	v20, v20, v21
10000219c: 3dc1d515    	ldr	q21, [x8, #0x750]
1000021a0: 3d802bf5    	str	q21, [sp, #0xa0]
1000021a4: 4fdc92b5    	fmul.2d	v21, v21, v28[0]
1000021a8: 4e75d694    	fadd.2d	v20, v20, v21
1000021ac: 3dc1ed15    	ldr	q21, [x8, #0x7b0]
1000021b0: 3d8027f5    	str	q21, [sp, #0x90]
1000021b4: 4fc092b5    	fmul.2d	v21, v21, v0[0]
1000021b8: 4e75d694    	fadd.2d	v20, v20, v21
1000021bc: 3dc20515    	ldr	q21, [x8, #0x810]
1000021c0: 3d8023f5    	str	q21, [sp, #0x80]
1000021c4: 4fc192b5    	fmul.2d	v21, v21, v1[0]
1000021c8: 4e75d694    	fadd.2d	v20, v20, v21
1000021cc: 3dc13115    	ldr	q21, [x8, #0x4c0]
1000021d0: 3c9003b5    	stur	q21, [x29, #-0x100]
1000021d4: 4fc792b5    	fmul.2d	v21, v21, v7[0]
1000021d8: 3dc14916    	ldr	q22, [x8, #0x520]
1000021dc: 3d80c3f6    	str	q22, [sp, #0x300]
1000021e0: 4fd092d6    	fmul.2d	v22, v22, v16[0]
1000021e4: 4e76d6b5    	fadd.2d	v21, v21, v22
1000021e8: 3dc16116    	ldr	q22, [x8, #0x580]
1000021ec: 3d80bff6    	str	q22, [sp, #0x2f0]
1000021f0: 4fc492d6    	fmul.2d	v22, v22, v4[0]
1000021f4: 4e76d6b5    	fadd.2d	v21, v21, v22
1000021f8: 3dc17916    	ldr	q22, [x8, #0x5e0]
1000021fc: 3d80bbf6    	str	q22, [sp, #0x2e0]
100002200: 4fc592d6    	fmul.2d	v22, v22, v5[0]
100002204: 4e76d6b5    	fadd.2d	v21, v21, v22
100002208: 3dc19116    	ldr	q22, [x8, #0x640]
10000220c: 3d80b7f6    	str	q22, [sp, #0x2d0]
100002210: 4fc392d6    	fmul.2d	v22, v22, v3[0]
100002214: 4e76d6b5    	fadd.2d	v21, v21, v22
100002218: 3dc1a916    	ldr	q22, [x8, #0x6a0]
10000221c: 3d80b3f6    	str	q22, [sp, #0x2c0]
100002220: 4fc692d6    	fmul.2d	v22, v22, v6[0]
100002224: 4e76d6b5    	fadd.2d	v21, v21, v22
100002228: d00000c9    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000222c: 9106c129    	add	x9, x9, #0x1b0
100002230: ad004931    	stp	q17, q18, [x9]
100002234: 3dc1c111    	ldr	q17, [x8, #0x700]
100002238: 3c9603b1    	stur	q17, [x29, #-0xa0]
10000223c: 4fc29231    	fmul.2d	v17, v17, v2[0]
100002240: 4e71d6b1    	fadd.2d	v17, v21, v17
100002244: 3dc1d912    	ldr	q18, [x8, #0x760]
100002248: 3d80aff2    	str	q18, [sp, #0x2b0]
10000224c: 4fdc9252    	fmul.2d	v18, v18, v28[0]
100002250: 4e72d631    	fadd.2d	v17, v17, v18
100002254: 3dc1f112    	ldr	q18, [x8, #0x7c0]
100002258: 3d80abf2    	str	q18, [sp, #0x2a0]
10000225c: 4fc09252    	fmul.2d	v18, v18, v0[0]
100002260: 4e72d631    	fadd.2d	v17, v17, v18
100002264: 3dc20912    	ldr	q18, [x8, #0x820]
100002268: 3d80a7f2    	str	q18, [sp, #0x290]
10000226c: 4fc19252    	fmul.2d	v18, v18, v1[0]
100002270: 4e72d631    	fadd.2d	v17, v17, v18
100002274: 3dc13512    	ldr	q18, [x8, #0x4d0]
100002278: 3c9503b2    	stur	q18, [x29, #-0xb0]
10000227c: 4fc79247    	fmul.2d	v7, v18, v7[0]
100002280: 3dc14d12    	ldr	q18, [x8, #0x530]
100002284: 4fd09250    	fmul.2d	v16, v18, v16[0]
100002288: 4e70d4e7    	fadd.2d	v7, v7, v16
10000228c: 3dc16510    	ldr	q16, [x8, #0x590]
100002290: ad39cbb0    	stp	q16, q18, [x29, #-0xd0]
100002294: 4fc49204    	fmul.2d	v4, v16, v4[0]
100002298: 4e64d4e4    	fadd.2d	v4, v7, v4
10000229c: 3dc17d07    	ldr	q7, [x8, #0x5f0]
1000022a0: 4fc590e5    	fmul.2d	v5, v7, v5[0]
1000022a4: 4e65d484    	fadd.2d	v4, v4, v5
1000022a8: ad015133    	stp	q19, q20, [x9, #0x20]
1000022ac: 3dc19505    	ldr	q5, [x8, #0x650]
1000022b0: ad389fa5    	stp	q5, q7, [x29, #-0xf0]
1000022b4: 4fc390a3    	fmul.2d	v3, v5, v3[0]
1000022b8: 4e63d483    	fadd.2d	v3, v4, v3
1000022bc: 3dc1ad0c    	ldr	q12, [x8, #0x6b0]
1000022c0: 4fc69184    	fmul.2d	v4, v12, v6[0]
1000022c4: 4e64d463    	fadd.2d	v3, v3, v4
1000022c8: 3dc1c50a    	ldr	q10, [x8, #0x710]
1000022cc: 4fc29142    	fmul.2d	v2, v10, v2[0]
1000022d0: ad13b3ea    	stp	q10, q12, [sp, #0x270]
1000022d4: 4e62d462    	fadd.2d	v2, v3, v2
1000022d8: 3dc1dd08    	ldr	q8, [x8, #0x770]
1000022dc: 4fdc9103    	fmul.2d	v3, v8, v28[0]
1000022e0: ad12a3f9    	stp	q25, q8, [sp, #0x250]
1000022e4: 4e63d442    	fadd.2d	v2, v2, v3
1000022e8: 3dc1f518    	ldr	q24, [x8, #0x7d0]
1000022ec: 4fc09300    	fmul.2d	v0, v24, v0[0]
1000022f0: 4e60d440    	fadd.2d	v0, v2, v0
1000022f4: 3dc20d17    	ldr	q23, [x8, #0x830]
1000022f8: 4fc192e1    	fmul.2d	v1, v23, v1[0]
1000022fc: ad1163f7    	stp	q23, q24, [sp, #0x220]
100002300: 4e61d400    	fadd.2d	v0, v0, v1
100002304: 6d461d10    	ldp	d16, d7, [x8, #0x60]
100002308: 4fd09321    	fmul.2d	v1, v25, v16[0]
10000230c: 4fc79342    	fmul.2d	v2, v26, v7[0]
100002310: 3d8093fa    	str	q26, [sp, #0x240]
100002314: 4e62d421    	fadd.2d	v1, v1, v2
100002318: 6d477106    	ldp	d6, d28, [x8, #0x70]
10000231c: 3cda03b2    	ldur	q18, [x29, #-0x60]
100002320: 4fc69242    	fmul.2d	v2, v18, v6[0]
100002324: 4e62d421    	fadd.2d	v1, v1, v2
100002328: 4fdc9122    	fmul.2d	v2, v9, v28[0]
10000232c: 4e62d421    	fadd.2d	v1, v1, v2
100002330: 6d481504    	ldp	d4, d5, [x8, #0x80]
100002334: ad45dbf4    	ldp	q20, q22, [sp, #0xb0]
100002338: 4fc492c2    	fmul.2d	v2, v22, v4[0]
10000233c: 4e62d421    	fadd.2d	v1, v1, v2
100002340: ad020131    	stp	q17, q0, [x9, #0x40]
100002344: 3dc03ff3    	ldr	q19, [sp, #0xf0]
100002348: 4fc59260    	fmul.2d	v0, v19, v5[0]
10000234c: 4e60d420    	fadd.2d	v0, v1, v0
100002350: 6d490d02    	ldp	d2, d3, [x8, #0x90]
100002354: 4fc291c1    	fmul.2d	v1, v14, v2[0]
100002358: 4e61d400    	fadd.2d	v0, v0, v1
10000235c: 4fc39281    	fmul.2d	v1, v20, v3[0]
100002360: 4e61d411    	fadd.2d	v17, v0, v1
100002364: 6d4a0500    	ldp	d0, d1, [x8, #0xa0]
100002368: 4fc091ee    	fmul.2d	v14, v15, v0[0]
10000236c: 4e6ed631    	fadd.2d	v17, v17, v14
100002370: 3dc017f5    	ldr	q21, [sp, #0x50]
100002374: 4fc192ae    	fmul.2d	v14, v21, v1[0]
100002378: 4e6ed631    	fadd.2d	v17, v17, v14
10000237c: 4fd093ee    	fmul.2d	v14, v31, v16[0]
100002380: 3dc057e9    	ldr	q9, [sp, #0x150]
100002384: 4fc7912f    	fmul.2d	v15, v9, v7[0]
100002388: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000238c: 4fc693cf    	fmul.2d	v15, v30, v6[0]
100002390: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002394: 4fdc936f    	fmul.2d	v15, v27, v28[0]
100002398: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000239c: ad507bfb    	ldp	q27, q30, [sp, #0x200]
1000023a0: 4fc493cf    	fmul.2d	v15, v30, v4[0]
1000023a4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023a8: 4fc593af    	fmul.2d	v15, v29, v5[0]
1000023ac: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023b0: 4fc2936f    	fmul.2d	v15, v27, v2[0]
1000023b4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023b8: ad48fffd    	ldp	q29, q31, [sp, #0x110]
1000023bc: 4fc393ef    	fmul.2d	v15, v31, v3[0]
1000023c0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023c4: 4fc093af    	fmul.2d	v15, v29, v0[0]
1000023c8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023cc: 3dc043fe    	ldr	q30, [sp, #0x100]
1000023d0: 4fc193cf    	fmul.2d	v15, v30, v1[0]
1000023d4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000023d8: ad033931    	stp	q17, q14, [x9, #0x60]
1000023dc: 3dc05ffb    	ldr	q27, [sp, #0x170]
1000023e0: 4fd09371    	fmul.2d	v17, v27, v16[0]
1000023e4: 3dc07fee    	ldr	q14, [sp, #0x1f0]
1000023e8: 4fc791ce    	fmul.2d	v14, v14, v7[0]
1000023ec: 4e6ed631    	fadd.2d	v17, v17, v14
1000023f0: 3cd903ae    	ldur	q14, [x29, #-0x70]
1000023f4: 4fc691ce    	fmul.2d	v14, v14, v6[0]
1000023f8: 4e6ed631    	fadd.2d	v17, v17, v14
1000023fc: 3dc07bee    	ldr	q14, [sp, #0x1e0]
100002400: 4fdc91ce    	fmul.2d	v14, v14, v28[0]
100002404: 4e6ed631    	fadd.2d	v17, v17, v14
100002408: 3cd803ae    	ldur	q14, [x29, #-0x80]
10000240c: 4fc491ce    	fmul.2d	v14, v14, v4[0]
100002410: 4e6ed631    	fadd.2d	v17, v17, v14
100002414: 3dc077ee    	ldr	q14, [sp, #0x1d0]
100002418: 4fc591ce    	fmul.2d	v14, v14, v5[0]
10000241c: 4e6ed631    	fadd.2d	v17, v17, v14
100002420: 3cd703ae    	ldur	q14, [x29, #-0x90]
100002424: 4fc291ce    	fmul.2d	v14, v14, v2[0]
100002428: 4e6ed631    	fadd.2d	v17, v17, v14
10000242c: 3dc073ee    	ldr	q14, [sp, #0x1c0]
100002430: 4fc391ce    	fmul.2d	v14, v14, v3[0]
100002434: 4e6ed631    	fadd.2d	v17, v17, v14
100002438: 3dc03bee    	ldr	q14, [sp, #0xe0]
10000243c: 4fc091ce    	fmul.2d	v14, v14, v0[0]
100002440: 4e6ed631    	fadd.2d	v17, v17, v14
100002444: ad4d3bef    	ldp	q15, q14, [sp, #0x1a0]
100002448: 4fc191ce    	fmul.2d	v14, v14, v1[0]
10000244c: 4e6ed631    	fadd.2d	v17, v17, v14
100002450: 3dc037ee    	ldr	q14, [sp, #0xd0]
100002454: 4fd091ce    	fmul.2d	v14, v14, v16[0]
100002458: 4fc791ef    	fmul.2d	v15, v15, v7[0]
10000245c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002460: 4fc6916f    	fmul.2d	v15, v11, v6[0]
100002464: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002468: 3dc053eb    	ldr	q11, [sp, #0x140]
10000246c: 4fdc916f    	fmul.2d	v15, v11, v28[0]
100002470: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002474: 3dc067ef    	ldr	q15, [sp, #0x190]
100002478: 4fc491ef    	fmul.2d	v15, v15, v4[0]
10000247c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002480: 4fc591af    	fmul.2d	v15, v13, v5[0]
100002484: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002488: 3dc04fed    	ldr	q13, [sp, #0x130]
10000248c: 4fc291af    	fmul.2d	v15, v13, v2[0]
100002490: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002494: 3dc02bef    	ldr	q15, [sp, #0xa0]
100002498: 4fc391ef    	fmul.2d	v15, v15, v3[0]
10000249c: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000024a0: 3dc027ef    	ldr	q15, [sp, #0x90]
1000024a4: 4fc091ef    	fmul.2d	v15, v15, v0[0]
1000024a8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000024ac: 3dc023ef    	ldr	q15, [sp, #0x80]
1000024b0: 4fc191ef    	fmul.2d	v15, v15, v1[0]
1000024b4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000024b8: ad043931    	stp	q17, q14, [x9, #0x80]
1000024bc: 3cd003b1    	ldur	q17, [x29, #-0x100]
1000024c0: 4fd09231    	fmul.2d	v17, v17, v16[0]
1000024c4: 3dc0c3ee    	ldr	q14, [sp, #0x300]
1000024c8: 4fc791ce    	fmul.2d	v14, v14, v7[0]
1000024cc: 4e6ed631    	fadd.2d	v17, v17, v14
1000024d0: 3dc0bfee    	ldr	q14, [sp, #0x2f0]
1000024d4: 4fc691ce    	fmul.2d	v14, v14, v6[0]
1000024d8: 4e6ed631    	fadd.2d	v17, v17, v14
1000024dc: 3dc0bbee    	ldr	q14, [sp, #0x2e0]
1000024e0: 4fdc91ce    	fmul.2d	v14, v14, v28[0]
1000024e4: 4e6ed631    	fadd.2d	v17, v17, v14
1000024e8: 3dc0b7ee    	ldr	q14, [sp, #0x2d0]
1000024ec: 4fc491ce    	fmul.2d	v14, v14, v4[0]
1000024f0: 4e6ed631    	fadd.2d	v17, v17, v14
1000024f4: 3dc0b3ee    	ldr	q14, [sp, #0x2c0]
1000024f8: 4fc591ce    	fmul.2d	v14, v14, v5[0]
1000024fc: 4e6ed631    	fadd.2d	v17, v17, v14
100002500: 3cd603ae    	ldur	q14, [x29, #-0xa0]
100002504: 4fc291ce    	fmul.2d	v14, v14, v2[0]
100002508: 4e6ed631    	fadd.2d	v17, v17, v14
10000250c: 3dc0afee    	ldr	q14, [sp, #0x2b0]
100002510: 4fc391ce    	fmul.2d	v14, v14, v3[0]
100002514: 4e6ed631    	fadd.2d	v17, v17, v14
100002518: 3dc0abee    	ldr	q14, [sp, #0x2a0]
10000251c: 4fc091ce    	fmul.2d	v14, v14, v0[0]
100002520: 4e6ed631    	fadd.2d	v17, v17, v14
100002524: 3dc0a7ee    	ldr	q14, [sp, #0x290]
100002528: 4fc191ce    	fmul.2d	v14, v14, v1[0]
10000252c: 4e6ed631    	fadd.2d	v17, v17, v14
100002530: 3cd503ae    	ldur	q14, [x29, #-0xb0]
100002534: 4fd091d0    	fmul.2d	v16, v14, v16[0]
100002538: 3cd403ae    	ldur	q14, [x29, #-0xc0]
10000253c: 4fc791c7    	fmul.2d	v7, v14, v7[0]
100002540: 4e67d607    	fadd.2d	v7, v16, v7
100002544: 3cd303b0    	ldur	q16, [x29, #-0xd0]
100002548: 4fc69206    	fmul.2d	v6, v16, v6[0]
10000254c: 4e66d4e6    	fadd.2d	v6, v7, v6
100002550: 3cd203a7    	ldur	q7, [x29, #-0xe0]
100002554: 4fdc90e7    	fmul.2d	v7, v7, v28[0]
100002558: 4e67d4c6    	fadd.2d	v6, v6, v7
10000255c: 3cd103a7    	ldur	q7, [x29, #-0xf0]
100002560: 4fc490e4    	fmul.2d	v4, v7, v4[0]
100002564: 4e64d4c4    	fadd.2d	v4, v6, v4
100002568: 4fc59185    	fmul.2d	v5, v12, v5[0]
10000256c: 4e65d484    	fadd.2d	v4, v4, v5
100002570: 4fc29142    	fmul.2d	v2, v10, v2[0]
100002574: 4e62d482    	fadd.2d	v2, v4, v2
100002578: 4fc39103    	fmul.2d	v3, v8, v3[0]
10000257c: 4e63d442    	fadd.2d	v2, v2, v3
100002580: 4fc09300    	fmul.2d	v0, v24, v0[0]
100002584: 4e60d440    	fadd.2d	v0, v2, v0
100002588: 4fc192e1    	fmul.2d	v1, v23, v1[0]
10000258c: 4e61d400    	fadd.2d	v0, v0, v1
100002590: ad050131    	stp	q17, q0, [x9, #0xa0]
100002594: 6d4c1901    	ldp	d1, d6, [x8, #0xc0]
100002598: 4fc19320    	fmul.2d	v0, v25, v1[0]
10000259c: 4fc69342    	fmul.2d	v2, v26, v6[0]
1000025a0: 4e62d403    	fadd.2d	v3, v0, v2
1000025a4: 6d4d0102    	ldp	d2, d0, [x8, #0xd0]
1000025a8: 4fc29244    	fmul.2d	v4, v18, v2[0]
1000025ac: 4e64d463    	fadd.2d	v3, v3, v4
1000025b0: 3dc063f2    	ldr	q18, [sp, #0x180]
1000025b4: 4fc09244    	fmul.2d	v4, v18, v0[0]
1000025b8: 4e64d464    	fadd.2d	v4, v3, v4
1000025bc: 6d4e0d1c    	ldp	d28, d3, [x8, #0xe0]
1000025c0: 4fdc92c5    	fmul.2d	v5, v22, v28[0]
1000025c4: 4e65d484    	fadd.2d	v4, v4, v5
1000025c8: 4fc39265    	fmul.2d	v5, v19, v3[0]
1000025cc: 4e65d487    	fadd.2d	v7, v4, v5
1000025d0: 6d4f1105    	ldp	d5, d4, [x8, #0xf0]
1000025d4: 3dc05bf3    	ldr	q19, [sp, #0x160]
1000025d8: 4fc59270    	fmul.2d	v16, v19, v5[0]
1000025dc: 4e70d4e7    	fadd.2d	v7, v7, v16
1000025e0: 4fc49290    	fmul.2d	v16, v20, v4[0]
1000025e4: 4e70d4f1    	fadd.2d	v17, v7, v16
1000025e8: 6d501d10    	ldp	d16, d7, [x8, #0x100]
1000025ec: ad4067f4    	ldp	q20, q25, [sp]
1000025f0: 4fd0928e    	fmul.2d	v14, v20, v16[0]
1000025f4: 4e6ed631    	fadd.2d	v17, v17, v14
1000025f8: 4fc792ae    	fmul.2d	v14, v21, v7[0]
1000025fc: 4e6ed631    	fadd.2d	v17, v17, v14
100002600: ad41d7f6    	ldp	q22, q21, [sp, #0x30]
100002604: 4fc192ae    	fmul.2d	v14, v21, v1[0]
100002608: 4fc6912f    	fmul.2d	v15, v9, v6[0]
10000260c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002610: 4fc292cf    	fmul.2d	v15, v22, v2[0]
100002614: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002618: 3dc00bf7    	ldr	q23, [sp, #0x20]
10000261c: 4fc092ef    	fmul.2d	v15, v23, v0[0]
100002620: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002624: ad5063fa    	ldp	q26, q24, [sp, #0x200]
100002628: 4fdc930f    	fmul.2d	v15, v24, v28[0]
10000262c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002630: 4fc3932f    	fmul.2d	v15, v25, v3[0]
100002634: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002638: 4fc5934f    	fmul.2d	v15, v26, v5[0]
10000263c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002640: 4fc493ef    	fmul.2d	v15, v31, v4[0]
100002644: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002648: 4fd093af    	fmul.2d	v15, v29, v16[0]
10000264c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002650: 4fc793cf    	fmul.2d	v15, v30, v7[0]
100002654: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002658: ad063931    	stp	q17, q14, [x9, #0xc0]
10000265c: 4fc19371    	fmul.2d	v17, v27, v1[0]
100002660: 3dc07ffb    	ldr	q27, [sp, #0x1f0]
100002664: 4fc6936e    	fmul.2d	v14, v27, v6[0]
100002668: 4e6ed631    	fadd.2d	v17, v17, v14
10000266c: ad7c77be    	ldp	q30, q29, [x29, #-0x80]
100002670: 4fc293ae    	fmul.2d	v14, v29, v2[0]
100002674: 4e6ed631    	fadd.2d	v17, v17, v14
100002678: 3dc07bfd    	ldr	q29, [sp, #0x1e0]
10000267c: 4fc093ae    	fmul.2d	v14, v29, v0[0]
100002680: 4e6ed631    	fadd.2d	v17, v17, v14
100002684: 4fdc93ce    	fmul.2d	v14, v30, v28[0]
100002688: 4e6ed631    	fadd.2d	v17, v17, v14
10000268c: 3dc077fe    	ldr	q30, [sp, #0x1d0]
100002690: 4fc393ce    	fmul.2d	v14, v30, v3[0]
100002694: 4e6ed631    	fadd.2d	v17, v17, v14
100002698: 3cd703bf    	ldur	q31, [x29, #-0x90]
10000269c: 4fc593ee    	fmul.2d	v14, v31, v5[0]
1000026a0: 4e6ed631    	fadd.2d	v17, v17, v14
1000026a4: 3dc073ff    	ldr	q31, [sp, #0x1c0]
1000026a8: 4fc493ee    	fmul.2d	v14, v31, v4[0]
1000026ac: 4e6ed631    	fadd.2d	v17, v17, v14
1000026b0: ad46a3e9    	ldp	q9, q8, [sp, #0xd0]
1000026b4: 4fd0910e    	fmul.2d	v14, v8, v16[0]
1000026b8: 4e6ed631    	fadd.2d	v17, v17, v14
1000026bc: 3dc06fe8    	ldr	q8, [sp, #0x1b0]
1000026c0: 4fc7910e    	fmul.2d	v14, v8, v7[0]
1000026c4: 4e6ed631    	fadd.2d	v17, v17, v14
1000026c8: 4fc1912e    	fmul.2d	v14, v9, v1[0]
1000026cc: 3dc06be9    	ldr	q9, [sp, #0x1a0]
1000026d0: 4fc6912f    	fmul.2d	v15, v9, v6[0]
1000026d4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000026d8: 3dc01fea    	ldr	q10, [sp, #0x70]
1000026dc: 4fc2914f    	fmul.2d	v15, v10, v2[0]
1000026e0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000026e4: 4fc0916f    	fmul.2d	v15, v11, v0[0]
1000026e8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000026ec: 3dc067ea    	ldr	q10, [sp, #0x190]
1000026f0: 4fdc914f    	fmul.2d	v15, v10, v28[0]
1000026f4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000026f8: 3dc01beb    	ldr	q11, [sp, #0x60]
1000026fc: 4fc3916f    	fmul.2d	v15, v11, v3[0]
100002700: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002704: 4fc591af    	fmul.2d	v15, v13, v5[0]
100002708: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000270c: ad44afec    	ldp	q12, q11, [sp, #0x90]
100002710: 4fc4916f    	fmul.2d	v15, v11, v4[0]
100002714: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002718: 4fd0918f    	fmul.2d	v15, v12, v16[0]
10000271c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002720: 3dc023ed    	ldr	q13, [sp, #0x80]
100002724: 4fc791af    	fmul.2d	v15, v13, v7[0]
100002728: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000272c: ad073931    	stp	q17, q14, [x9, #0xe0]
100002730: 3cd003b1    	ldur	q17, [x29, #-0x100]
100002734: 4fc19231    	fmul.2d	v17, v17, v1[0]
100002738: 3dc0c3ee    	ldr	q14, [sp, #0x300]
10000273c: 4fc691ce    	fmul.2d	v14, v14, v6[0]
100002740: 4e6ed631    	fadd.2d	v17, v17, v14
100002744: 3dc0bfee    	ldr	q14, [sp, #0x2f0]
100002748: 4fc291ce    	fmul.2d	v14, v14, v2[0]
10000274c: 4e6ed631    	fadd.2d	v17, v17, v14
100002750: 3dc0bbee    	ldr	q14, [sp, #0x2e0]
100002754: 4fc091ce    	fmul.2d	v14, v14, v0[0]
100002758: 4e6ed631    	fadd.2d	v17, v17, v14
10000275c: 3dc0b7ee    	ldr	q14, [sp, #0x2d0]
100002760: 4fdc91ce    	fmul.2d	v14, v14, v28[0]
100002764: 4e6ed631    	fadd.2d	v17, v17, v14
100002768: 3dc0b3ee    	ldr	q14, [sp, #0x2c0]
10000276c: 4fc391ce    	fmul.2d	v14, v14, v3[0]
100002770: 4e6ed631    	fadd.2d	v17, v17, v14
100002774: 3cd603ae    	ldur	q14, [x29, #-0xa0]
100002778: 4fc591ce    	fmul.2d	v14, v14, v5[0]
10000277c: 4e6ed631    	fadd.2d	v17, v17, v14
100002780: 3dc0afee    	ldr	q14, [sp, #0x2b0]
100002784: 4fc491ce    	fmul.2d	v14, v14, v4[0]
100002788: 4e6ed631    	fadd.2d	v17, v17, v14
10000278c: 3dc0abee    	ldr	q14, [sp, #0x2a0]
100002790: 4fd091ce    	fmul.2d	v14, v14, v16[0]
100002794: 4e6ed631    	fadd.2d	v17, v17, v14
100002798: 3dc0a7ee    	ldr	q14, [sp, #0x290]
10000279c: 4fc791ce    	fmul.2d	v14, v14, v7[0]
1000027a0: 4e6ed631    	fadd.2d	v17, v17, v14
1000027a4: 3cd503ae    	ldur	q14, [x29, #-0xb0]
1000027a8: 4fc191c1    	fmul.2d	v1, v14, v1[0]
1000027ac: 3cd403ae    	ldur	q14, [x29, #-0xc0]
1000027b0: 4fc691c6    	fmul.2d	v6, v14, v6[0]
1000027b4: 4e66d421    	fadd.2d	v1, v1, v6
1000027b8: 3cd303a6    	ldur	q6, [x29, #-0xd0]
1000027bc: 4fc290c2    	fmul.2d	v2, v6, v2[0]
1000027c0: 4e62d421    	fadd.2d	v1, v1, v2
1000027c4: 3cd203a2    	ldur	q2, [x29, #-0xe0]
1000027c8: 4fc09040    	fmul.2d	v0, v2, v0[0]
1000027cc: 4e60d420    	fadd.2d	v0, v1, v0
1000027d0: 3cd103a1    	ldur	q1, [x29, #-0xf0]
1000027d4: 4fdc9021    	fmul.2d	v1, v1, v28[0]
1000027d8: 4e61d400    	fadd.2d	v0, v0, v1
1000027dc: 3dc0a3e1    	ldr	q1, [sp, #0x280]
1000027e0: 4fc39021    	fmul.2d	v1, v1, v3[0]
1000027e4: 4e61d400    	fadd.2d	v0, v0, v1
1000027e8: 3dc09fe1    	ldr	q1, [sp, #0x270]
1000027ec: 4fc59021    	fmul.2d	v1, v1, v5[0]
1000027f0: 4e61d400    	fadd.2d	v0, v0, v1
1000027f4: 3dc09be1    	ldr	q1, [sp, #0x260]
1000027f8: 4fc49021    	fmul.2d	v1, v1, v4[0]
1000027fc: 4e61d400    	fadd.2d	v0, v0, v1
100002800: ad518be1    	ldp	q1, q2, [sp, #0x230]
100002804: 4fd09021    	fmul.2d	v1, v1, v16[0]
100002808: 4e61d400    	fadd.2d	v0, v0, v1
10000280c: 3dc08be1    	ldr	q1, [sp, #0x220]
100002810: 4fc79021    	fmul.2d	v1, v1, v7[0]
100002814: 4e61d400    	fadd.2d	v0, v0, v1
100002818: ad080131    	stp	q17, q0, [x9, #0x100]
10000281c: 6d521901    	ldp	d1, d6, [x8, #0x120]
100002820: 3dc097e0    	ldr	q0, [sp, #0x250]
100002824: 4fc19000    	fmul.2d	v0, v0, v1[0]
100002828: 4fc69042    	fmul.2d	v2, v2, v6[0]
10000282c: 4e62d403    	fadd.2d	v3, v0, v2
100002830: 6d530102    	ldp	d2, d0, [x8, #0x130]
100002834: 3cda03a4    	ldur	q4, [x29, #-0x60]
100002838: 4fc29084    	fmul.2d	v4, v4, v2[0]
10000283c: 4e64d463    	fadd.2d	v3, v3, v4
100002840: 4fc09244    	fmul.2d	v4, v18, v0[0]
100002844: 4e64d464    	fadd.2d	v4, v3, v4
100002848: 6d540d1c    	ldp	d28, d3, [x8, #0x140]
10000284c: 3dc033f2    	ldr	q18, [sp, #0xc0]
100002850: 4fdc9245    	fmul.2d	v5, v18, v28[0]
100002854: 4e65d484    	fadd.2d	v4, v4, v5
100002858: 3dc03fe5    	ldr	q5, [sp, #0xf0]
10000285c: 4fc390a5    	fmul.2d	v5, v5, v3[0]
100002860: 4e65d487    	fadd.2d	v7, v4, v5
100002864: 6d551105    	ldp	d5, d4, [x8, #0x150]
100002868: 4fc59270    	fmul.2d	v16, v19, v5[0]
10000286c: 4e70d4e7    	fadd.2d	v7, v7, v16
100002870: 3dc02ff3    	ldr	q19, [sp, #0xb0]
100002874: 4fc49270    	fmul.2d	v16, v19, v4[0]
100002878: 4e70d4f1    	fadd.2d	v17, v7, v16
10000287c: 6d561d10    	ldp	d16, d7, [x8, #0x160]
100002880: 4fd0928e    	fmul.2d	v14, v20, v16[0]
100002884: 4e6ed631    	fadd.2d	v17, v17, v14
100002888: 3dc017f4    	ldr	q20, [sp, #0x50]
10000288c: 4fc7928e    	fmul.2d	v14, v20, v7[0]
100002890: 4e6ed631    	fadd.2d	v17, v17, v14
100002894: 4fc192ae    	fmul.2d	v14, v21, v1[0]
100002898: 3dc057f5    	ldr	q21, [sp, #0x150]
10000289c: 4fc692af    	fmul.2d	v15, v21, v6[0]
1000028a0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028a4: 4fc292cf    	fmul.2d	v15, v22, v2[0]
1000028a8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028ac: 4fc092ef    	fmul.2d	v15, v23, v0[0]
1000028b0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028b4: 4fdc930f    	fmul.2d	v15, v24, v28[0]
1000028b8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028bc: 4fc3932f    	fmul.2d	v15, v25, v3[0]
1000028c0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028c4: 4fc5934f    	fmul.2d	v15, v26, v5[0]
1000028c8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028cc: ad48dbf5    	ldp	q21, q22, [sp, #0x110]
1000028d0: 4fc492cf    	fmul.2d	v15, v22, v4[0]
1000028d4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028d8: 4fd092af    	fmul.2d	v15, v21, v16[0]
1000028dc: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028e0: 3dc043f5    	ldr	q21, [sp, #0x100]
1000028e4: 4fc792af    	fmul.2d	v15, v21, v7[0]
1000028e8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000028ec: ad093931    	stp	q17, q14, [x9, #0x120]
1000028f0: 3dc05ff1    	ldr	q17, [sp, #0x170]
1000028f4: 4fc19231    	fmul.2d	v17, v17, v1[0]
1000028f8: 4fc6936e    	fmul.2d	v14, v27, v6[0]
1000028fc: 4e6ed631    	fadd.2d	v17, v17, v14
100002900: ad7c5bb5    	ldp	q21, q22, [x29, #-0x80]
100002904: 4fc292ce    	fmul.2d	v14, v22, v2[0]
100002908: 4e6ed631    	fadd.2d	v17, v17, v14
10000290c: 4fc093ae    	fmul.2d	v14, v29, v0[0]
100002910: 4e6ed631    	fadd.2d	v17, v17, v14
100002914: 4fdc92ae    	fmul.2d	v14, v21, v28[0]
100002918: 4e6ed631    	fadd.2d	v17, v17, v14
10000291c: 4fc393ce    	fmul.2d	v14, v30, v3[0]
100002920: 4e6ed631    	fadd.2d	v17, v17, v14
100002924: 3cd703b5    	ldur	q21, [x29, #-0x90]
100002928: 4fc592ae    	fmul.2d	v14, v21, v5[0]
10000292c: 4e6ed631    	fadd.2d	v17, v17, v14
100002930: 4fc493ee    	fmul.2d	v14, v31, v4[0]
100002934: 4e6ed631    	fadd.2d	v17, v17, v14
100002938: 3dc03bff    	ldr	q31, [sp, #0xe0]
10000293c: 4fd093ee    	fmul.2d	v14, v31, v16[0]
100002940: 4e6ed631    	fadd.2d	v17, v17, v14
100002944: 4fc7910e    	fmul.2d	v14, v8, v7[0]
100002948: 4e6ed631    	fadd.2d	v17, v17, v14
10000294c: 3dc037e8    	ldr	q8, [sp, #0xd0]
100002950: 4fc1910e    	fmul.2d	v14, v8, v1[0]
100002954: 4fc6912f    	fmul.2d	v15, v9, v6[0]
100002958: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000295c: 3dc01fe9    	ldr	q9, [sp, #0x70]
100002960: 4fc2912f    	fmul.2d	v15, v9, v2[0]
100002964: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002968: ad49dbf5    	ldp	q21, q22, [sp, #0x130]
10000296c: 4fc092cf    	fmul.2d	v15, v22, v0[0]
100002970: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002974: 4fdc914f    	fmul.2d	v15, v10, v28[0]
100002978: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000297c: 3dc01bea    	ldr	q10, [sp, #0x60]
100002980: 4fc3914f    	fmul.2d	v15, v10, v3[0]
100002984: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002988: 4fc592af    	fmul.2d	v15, v21, v5[0]
10000298c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002990: 4fc4916f    	fmul.2d	v15, v11, v4[0]
100002994: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002998: 4fd0918f    	fmul.2d	v15, v12, v16[0]
10000299c: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000029a0: 4fc791af    	fmul.2d	v15, v13, v7[0]
1000029a4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000029a8: ad0a3931    	stp	q17, q14, [x9, #0x140]
1000029ac: 3cd003bd    	ldur	q29, [x29, #-0x100]
1000029b0: 4fc193b1    	fmul.2d	v17, v29, v1[0]
1000029b4: ad57fbf5    	ldp	q21, q30, [sp, #0x2f0]
1000029b8: 4fc693ce    	fmul.2d	v14, v30, v6[0]
1000029bc: 4e6ed631    	fadd.2d	v17, v17, v14
1000029c0: 4fc292ae    	fmul.2d	v14, v21, v2[0]
1000029c4: 4e6ed631    	fadd.2d	v17, v17, v14
1000029c8: ad56dbf7    	ldp	q23, q22, [sp, #0x2d0]
1000029cc: 4fc092ce    	fmul.2d	v14, v22, v0[0]
1000029d0: 4e6ed631    	fadd.2d	v17, v17, v14
1000029d4: 4fdc92ee    	fmul.2d	v14, v23, v28[0]
1000029d8: 4e6ed631    	fadd.2d	v17, v17, v14
1000029dc: 3dc0b3f8    	ldr	q24, [sp, #0x2c0]
1000029e0: 4fc3930e    	fmul.2d	v14, v24, v3[0]
1000029e4: 4e6ed631    	fadd.2d	v17, v17, v14
1000029e8: 3cd603b9    	ldur	q25, [x29, #-0xa0]
1000029ec: 4fc5932e    	fmul.2d	v14, v25, v5[0]
1000029f0: 4e6ed631    	fadd.2d	v17, v17, v14
1000029f4: ad5567fa    	ldp	q26, q25, [sp, #0x2a0]
1000029f8: 4fc4932e    	fmul.2d	v14, v25, v4[0]
1000029fc: 4e6ed631    	fadd.2d	v17, v17, v14
100002a00: 4fd0934e    	fmul.2d	v14, v26, v16[0]
100002a04: 4e6ed631    	fadd.2d	v17, v17, v14
100002a08: 3dc0a7fb    	ldr	q27, [sp, #0x290]
100002a0c: 4fc7936e    	fmul.2d	v14, v27, v7[0]
100002a10: 4e6ed631    	fadd.2d	v17, v17, v14
100002a14: 3cd503ae    	ldur	q14, [x29, #-0xb0]
100002a18: 4fc191c1    	fmul.2d	v1, v14, v1[0]
100002a1c: 3cd403ae    	ldur	q14, [x29, #-0xc0]
100002a20: 4fc691c6    	fmul.2d	v6, v14, v6[0]
100002a24: 4e66d421    	fadd.2d	v1, v1, v6
100002a28: 3cd303a6    	ldur	q6, [x29, #-0xd0]
100002a2c: 4fc290c2    	fmul.2d	v2, v6, v2[0]
100002a30: 4e62d421    	fadd.2d	v1, v1, v2
100002a34: 3cd203a2    	ldur	q2, [x29, #-0xe0]
100002a38: 4fc09040    	fmul.2d	v0, v2, v0[0]
100002a3c: 4e60d420    	fadd.2d	v0, v1, v0
100002a40: 3cd103a1    	ldur	q1, [x29, #-0xf0]
100002a44: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100002a48: 4e61d400    	fadd.2d	v0, v0, v1
100002a4c: 3dc0a3e1    	ldr	q1, [sp, #0x280]
100002a50: 4fc39021    	fmul.2d	v1, v1, v3[0]
100002a54: 4e61d400    	fadd.2d	v0, v0, v1
100002a58: 3dc09fe1    	ldr	q1, [sp, #0x270]
100002a5c: 4fc59021    	fmul.2d	v1, v1, v5[0]
100002a60: 4e61d400    	fadd.2d	v0, v0, v1
100002a64: 3dc09be1    	ldr	q1, [sp, #0x260]
100002a68: 4fc49021    	fmul.2d	v1, v1, v4[0]
100002a6c: 4e61d400    	fadd.2d	v0, v0, v1
100002a70: ad518be1    	ldp	q1, q2, [sp, #0x230]
100002a74: 4fd09021    	fmul.2d	v1, v1, v16[0]
100002a78: 4e61d400    	fadd.2d	v0, v0, v1
100002a7c: 3dc08be1    	ldr	q1, [sp, #0x220]
100002a80: 4fc79021    	fmul.2d	v1, v1, v7[0]
100002a84: 4e61d400    	fadd.2d	v0, v0, v1
100002a88: ad0b0131    	stp	q17, q0, [x9, #0x160]
100002a8c: 6d581901    	ldp	d1, d6, [x8, #0x180]
100002a90: 3dc097e0    	ldr	q0, [sp, #0x250]
100002a94: 4fc19000    	fmul.2d	v0, v0, v1[0]
100002a98: 4fc69042    	fmul.2d	v2, v2, v6[0]
100002a9c: 4e62d403    	fadd.2d	v3, v0, v2
100002aa0: 6d590102    	ldp	d2, d0, [x8, #0x190]
100002aa4: 3cda03a4    	ldur	q4, [x29, #-0x60]
100002aa8: 4fc29084    	fmul.2d	v4, v4, v2[0]
100002aac: 4e64d463    	fadd.2d	v3, v3, v4
100002ab0: 3dc063e4    	ldr	q4, [sp, #0x180]
100002ab4: 4fc09084    	fmul.2d	v4, v4, v0[0]
100002ab8: 4e64d464    	fadd.2d	v4, v3, v4
100002abc: 6d5a0d1c    	ldp	d28, d3, [x8, #0x1a0]
100002ac0: 4fdc9245    	fmul.2d	v5, v18, v28[0]
100002ac4: 4e65d484    	fadd.2d	v4, v4, v5
100002ac8: 3dc03ff2    	ldr	q18, [sp, #0xf0]
100002acc: 4fc39245    	fmul.2d	v5, v18, v3[0]
100002ad0: 4e65d487    	fadd.2d	v7, v4, v5
100002ad4: 6d5b1105    	ldp	d5, d4, [x8, #0x1b0]
100002ad8: ad4ac3ef    	ldp	q15, q16, [sp, #0x150]
100002adc: 4fc59210    	fmul.2d	v16, v16, v5[0]
100002ae0: 4e70d4e7    	fadd.2d	v7, v7, v16
100002ae4: 4fc49270    	fmul.2d	v16, v19, v4[0]
100002ae8: 4e70d4f1    	fadd.2d	v17, v7, v16
100002aec: 6d5c1d10    	ldp	d16, d7, [x8, #0x1c0]
100002af0: 3dc003f3    	ldr	q19, [sp]
100002af4: 4fd0926e    	fmul.2d	v14, v19, v16[0]
100002af8: 4e6ed631    	fadd.2d	v17, v17, v14
100002afc: 4fc7928e    	fmul.2d	v14, v20, v7[0]
100002b00: 4e6ed631    	fadd.2d	v17, v17, v14
100002b04: 3dc013ee    	ldr	q14, [sp, #0x40]
100002b08: 4fc191ce    	fmul.2d	v14, v14, v1[0]
100002b0c: 4fc691ef    	fmul.2d	v15, v15, v6[0]
100002b10: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b14: 3dc00fef    	ldr	q15, [sp, #0x30]
100002b18: 4fc291ef    	fmul.2d	v15, v15, v2[0]
100002b1c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b20: 3dc00bef    	ldr	q15, [sp, #0x20]
100002b24: 4fc091ef    	fmul.2d	v15, v15, v0[0]
100002b28: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b2c: 3dc087ef    	ldr	q15, [sp, #0x210]
100002b30: 4fdc91ef    	fmul.2d	v15, v15, v28[0]
100002b34: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b38: 3dc007ef    	ldr	q15, [sp, #0x10]
100002b3c: 4fc391ef    	fmul.2d	v15, v15, v3[0]
100002b40: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b44: 3dc083ef    	ldr	q15, [sp, #0x200]
100002b48: 4fc591ef    	fmul.2d	v15, v15, v5[0]
100002b4c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b50: 3dc04bef    	ldr	q15, [sp, #0x120]
100002b54: 4fc491ef    	fmul.2d	v15, v15, v4[0]
100002b58: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b5c: 3dc047ef    	ldr	q15, [sp, #0x110]
100002b60: 4fd091ef    	fmul.2d	v15, v15, v16[0]
100002b64: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b68: 3dc043ef    	ldr	q15, [sp, #0x100]
100002b6c: 4fc791ef    	fmul.2d	v15, v15, v7[0]
100002b70: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002b74: ad0c3931    	stp	q17, q14, [x9, #0x180]
100002b78: 3dc05ff1    	ldr	q17, [sp, #0x170]
100002b7c: 4fc19231    	fmul.2d	v17, v17, v1[0]
100002b80: 3dc07fee    	ldr	q14, [sp, #0x1f0]
100002b84: 4fc691ce    	fmul.2d	v14, v14, v6[0]
100002b88: 4e6ed631    	fadd.2d	v17, v17, v14
100002b8c: 3cd903ae    	ldur	q14, [x29, #-0x70]
100002b90: 4fc291ce    	fmul.2d	v14, v14, v2[0]
100002b94: 4e6ed631    	fadd.2d	v17, v17, v14
100002b98: 3dc07bee    	ldr	q14, [sp, #0x1e0]
100002b9c: 4fc091ce    	fmul.2d	v14, v14, v0[0]
100002ba0: 4e6ed631    	fadd.2d	v17, v17, v14
100002ba4: 3cd803ae    	ldur	q14, [x29, #-0x80]
100002ba8: 4fdc91ce    	fmul.2d	v14, v14, v28[0]
100002bac: 4e6ed631    	fadd.2d	v17, v17, v14
100002bb0: 3dc077ee    	ldr	q14, [sp, #0x1d0]
100002bb4: 4fc391ce    	fmul.2d	v14, v14, v3[0]
100002bb8: 4e6ed631    	fadd.2d	v17, v17, v14
100002bbc: 3cd703ae    	ldur	q14, [x29, #-0x90]
100002bc0: 4fc591ce    	fmul.2d	v14, v14, v5[0]
100002bc4: 4e6ed631    	fadd.2d	v17, v17, v14
100002bc8: 3dc073ee    	ldr	q14, [sp, #0x1c0]
100002bcc: 4fc491ce    	fmul.2d	v14, v14, v4[0]
100002bd0: 4e6ed631    	fadd.2d	v17, v17, v14
100002bd4: 4fd093ee    	fmul.2d	v14, v31, v16[0]
100002bd8: 4e6ed631    	fadd.2d	v17, v17, v14
100002bdc: 3dc06fff    	ldr	q31, [sp, #0x1b0]
100002be0: 4fc793ee    	fmul.2d	v14, v31, v7[0]
100002be4: 4e6ed631    	fadd.2d	v17, v17, v14
100002be8: 4fc1910e    	fmul.2d	v14, v8, v1[0]
100002bec: 3dc06bff    	ldr	q31, [sp, #0x1a0]
100002bf0: 4fc693ef    	fmul.2d	v15, v31, v6[0]
100002bf4: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002bf8: 4fc2912f    	fmul.2d	v15, v9, v2[0]
100002bfc: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002c00: 3dc053ff    	ldr	q31, [sp, #0x140]
100002c04: 4fc093ef    	fmul.2d	v15, v31, v0[0]
100002c08: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002c0c: 3dc067ff    	ldr	q31, [sp, #0x190]
100002c10: 4fdc93ef    	fmul.2d	v15, v31, v28[0]
100002c14: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002c18: 4fc3914f    	fmul.2d	v15, v10, v3[0]
100002c1c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002c20: 3dc04fff    	ldr	q31, [sp, #0x130]
100002c24: 4fc593ef    	fmul.2d	v15, v31, v5[0]
100002c28: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002c2c: 4fc4916f    	fmul.2d	v15, v11, v4[0]
100002c30: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002c34: 4fd0918f    	fmul.2d	v15, v12, v16[0]
100002c38: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002c3c: 4fc791af    	fmul.2d	v15, v13, v7[0]
100002c40: 4e6fd5ce    	fadd.2d	v14, v14, v15
100002c44: ad0d3931    	stp	q17, q14, [x9, #0x1a0]
100002c48: 4fc193b1    	fmul.2d	v17, v29, v1[0]
100002c4c: 4fc693cd    	fmul.2d	v13, v30, v6[0]
100002c50: 4e6dd631    	fadd.2d	v17, v17, v13
100002c54: 4fc292ac    	fmul.2d	v12, v21, v2[0]
100002c58: 4e6cd631    	fadd.2d	v17, v17, v12
100002c5c: 4fc092cb    	fmul.2d	v11, v22, v0[0]
100002c60: 4e6bd631    	fadd.2d	v17, v17, v11
100002c64: 4fdc92ea    	fmul.2d	v10, v23, v28[0]
100002c68: 4e6ad631    	fadd.2d	v17, v17, v10
100002c6c: 4fc39309    	fmul.2d	v9, v24, v3[0]
100002c70: 4e69d631    	fadd.2d	v17, v17, v9
100002c74: ad7adbb5    	ldp	q21, q22, [x29, #-0xb0]
100002c78: 4fc592c8    	fmul.2d	v8, v22, v5[0]
100002c7c: 4e68d631    	fadd.2d	v17, v17, v8
100002c80: 4fc4933f    	fmul.2d	v31, v25, v4[0]
100002c84: 4e7fd631    	fadd.2d	v17, v17, v31
100002c88: 4fd0935e    	fmul.2d	v30, v26, v16[0]
100002c8c: 4e7ed631    	fadd.2d	v17, v17, v30
100002c90: 4fc7937d    	fmul.2d	v29, v27, v7[0]
100002c94: 4e7dd631    	fadd.2d	v17, v17, v29
100002c98: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100002c9c: 3cd403b5    	ldur	q21, [x29, #-0xc0]
100002ca0: 4fc692a6    	fmul.2d	v6, v21, v6[0]
100002ca4: 4e66d421    	fadd.2d	v1, v1, v6
100002ca8: 3cd303a6    	ldur	q6, [x29, #-0xd0]
100002cac: 4fc290c2    	fmul.2d	v2, v6, v2[0]
100002cb0: 4e62d421    	fadd.2d	v1, v1, v2
100002cb4: 3cd203a2    	ldur	q2, [x29, #-0xe0]
100002cb8: 4fc09040    	fmul.2d	v0, v2, v0[0]
100002cbc: 4e60d420    	fadd.2d	v0, v1, v0
100002cc0: 3cd103a1    	ldur	q1, [x29, #-0xf0]
100002cc4: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100002cc8: 4e61d400    	fadd.2d	v0, v0, v1
100002ccc: 3dc0a3e1    	ldr	q1, [sp, #0x280]
100002cd0: 4fc39021    	fmul.2d	v1, v1, v3[0]
100002cd4: 4e61d400    	fadd.2d	v0, v0, v1
100002cd8: 3dc09fe1    	ldr	q1, [sp, #0x270]
100002cdc: 4fc59021    	fmul.2d	v1, v1, v5[0]
100002ce0: 4e61d400    	fadd.2d	v0, v0, v1
100002ce4: ad5287e2    	ldp	q2, q1, [sp, #0x250]
100002ce8: 4fc49021    	fmul.2d	v1, v1, v4[0]
100002cec: 4e61d400    	fadd.2d	v0, v0, v1
100002cf0: ad518fe1    	ldp	q1, q3, [sp, #0x230]
100002cf4: 4fd09021    	fmul.2d	v1, v1, v16[0]
100002cf8: 4e61d400    	fadd.2d	v0, v0, v1
100002cfc: 3dc08be1    	ldr	q1, [sp, #0x220]
100002d00: 4fc79021    	fmul.2d	v1, v1, v7[0]
100002d04: 4e61d400    	fadd.2d	v0, v0, v1
100002d08: ad0e0131    	stp	q17, q0, [x9, #0x1c0]
100002d0c: 6d5e0500    	ldp	d0, d1, [x8, #0x1e0]
100002d10: 4fc09042    	fmul.2d	v2, v2, v0[0]
100002d14: 4fc19063    	fmul.2d	v3, v3, v1[0]
100002d18: 4e63d442    	fadd.2d	v2, v2, v3
100002d1c: 6d5f1511    	ldp	d17, d5, [x8, #0x1f0]
100002d20: 3cda03a3    	ldur	q3, [x29, #-0x60]
100002d24: 4fd19063    	fmul.2d	v3, v3, v17[0]
100002d28: 4e63d442    	fadd.2d	v2, v2, v3
100002d2c: fd410106    	ldr	d6, [x8, #0x200]
100002d30: 3dc063e3    	ldr	q3, [sp, #0x180]
100002d34: 4fc59063    	fmul.2d	v3, v3, v5[0]
100002d38: 4e63d442    	fadd.2d	v2, v2, v3
100002d3c: fd410507    	ldr	d7, [x8, #0x208]
100002d40: 3dc033e3    	ldr	q3, [sp, #0xc0]
100002d44: 4fc69063    	fmul.2d	v3, v3, v6[0]
100002d48: 4e63d442    	fadd.2d	v2, v2, v3
100002d4c: fd410910    	ldr	d16, [x8, #0x210]
100002d50: 4fc79243    	fmul.2d	v3, v18, v7[0]
100002d54: 4e63d442    	fadd.2d	v2, v2, v3
100002d58: fd410d04    	ldr	d4, [x8, #0x218]
100002d5c: 3dc05be3    	ldr	q3, [sp, #0x160]
100002d60: 4fd09063    	fmul.2d	v3, v3, v16[0]
100002d64: 4e63d443    	fadd.2d	v3, v2, v3
100002d68: fd411102    	ldr	d2, [x8, #0x220]
100002d6c: 3dc02ff2    	ldr	q18, [sp, #0xb0]
100002d70: 4fc49252    	fmul.2d	v18, v18, v4[0]
100002d74: 4e72d472    	fadd.2d	v18, v3, v18
100002d78: fd411503    	ldr	d3, [x8, #0x228]
100002d7c: 4fc29273    	fmul.2d	v19, v19, v2[0]
100002d80: 4e73d652    	fadd.2d	v18, v18, v19
100002d84: 4fc39293    	fmul.2d	v19, v20, v3[0]
100002d88: 4e73d652    	fadd.2d	v18, v18, v19
100002d8c: 3dc12513    	ldr	q19, [x8, #0x490]
100002d90: 4fc09273    	fmul.2d	v19, v19, v0[0]
100002d94: 3dc13d14    	ldr	q20, [x8, #0x4f0]
100002d98: 4fc19294    	fmul.2d	v20, v20, v1[0]
100002d9c: 4e74d673    	fadd.2d	v19, v19, v20
100002da0: 3dc15514    	ldr	q20, [x8, #0x550]
100002da4: 4fd19294    	fmul.2d	v20, v20, v17[0]
100002da8: 4e74d673    	fadd.2d	v19, v19, v20
100002dac: 3dc16d14    	ldr	q20, [x8, #0x5b0]
100002db0: 4fc59294    	fmul.2d	v20, v20, v5[0]
100002db4: 4e74d673    	fadd.2d	v19, v19, v20
100002db8: 3dc18514    	ldr	q20, [x8, #0x610]
100002dbc: 4fc69294    	fmul.2d	v20, v20, v6[0]
100002dc0: 4e74d673    	fadd.2d	v19, v19, v20
100002dc4: 3dc19d14    	ldr	q20, [x8, #0x670]
100002dc8: 4fc79294    	fmul.2d	v20, v20, v7[0]
100002dcc: 4e74d673    	fadd.2d	v19, v19, v20
100002dd0: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100002dd4: 4fd09294    	fmul.2d	v20, v20, v16[0]
100002dd8: 4e74d673    	fadd.2d	v19, v19, v20
100002ddc: 3dc1cd14    	ldr	q20, [x8, #0x730]
100002de0: 4fc49294    	fmul.2d	v20, v20, v4[0]
100002de4: 4e74d673    	fadd.2d	v19, v19, v20
100002de8: 3dc1e514    	ldr	q20, [x8, #0x790]
100002dec: 4fc29294    	fmul.2d	v20, v20, v2[0]
100002df0: 4e74d673    	fadd.2d	v19, v19, v20
100002df4: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
100002df8: 4fc39294    	fmul.2d	v20, v20, v3[0]
100002dfc: 4e74d673    	fadd.2d	v19, v19, v20
100002e00: ad0f4d32    	stp	q18, q19, [x9, #0x1e0]
100002e04: 3dc12912    	ldr	q18, [x8, #0x4a0]
100002e08: 4fc09252    	fmul.2d	v18, v18, v0[0]
100002e0c: 3dc14113    	ldr	q19, [x8, #0x500]
100002e10: 4fc19273    	fmul.2d	v19, v19, v1[0]
100002e14: 4e73d652    	fadd.2d	v18, v18, v19
100002e18: 3dc15913    	ldr	q19, [x8, #0x560]
100002e1c: 4fd19273    	fmul.2d	v19, v19, v17[0]
100002e20: 4e73d652    	fadd.2d	v18, v18, v19
100002e24: 3dc17113    	ldr	q19, [x8, #0x5c0]
100002e28: 4fc59273    	fmul.2d	v19, v19, v5[0]
100002e2c: 4e73d652    	fadd.2d	v18, v18, v19
100002e30: 3dc18913    	ldr	q19, [x8, #0x620]
100002e34: 4fc69273    	fmul.2d	v19, v19, v6[0]
100002e38: 4e73d652    	fadd.2d	v18, v18, v19
100002e3c: 3dc1a113    	ldr	q19, [x8, #0x680]
100002e40: 4fc79273    	fmul.2d	v19, v19, v7[0]
100002e44: 4e73d652    	fadd.2d	v18, v18, v19
100002e48: 3dc1b913    	ldr	q19, [x8, #0x6e0]
100002e4c: 4fd09273    	fmul.2d	v19, v19, v16[0]
100002e50: 4e73d652    	fadd.2d	v18, v18, v19
100002e54: 3dc1d113    	ldr	q19, [x8, #0x740]
100002e58: 4fc49273    	fmul.2d	v19, v19, v4[0]
100002e5c: 4e73d652    	fadd.2d	v18, v18, v19
100002e60: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100002e64: 4fc29273    	fmul.2d	v19, v19, v2[0]
100002e68: 4e73d652    	fadd.2d	v18, v18, v19
100002e6c: 3dc20113    	ldr	q19, [x8, #0x800]
100002e70: 4fc39273    	fmul.2d	v19, v19, v3[0]
100002e74: 4e73d652    	fadd.2d	v18, v18, v19
100002e78: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100002e7c: 4fc09273    	fmul.2d	v19, v19, v0[0]
100002e80: 3dc14514    	ldr	q20, [x8, #0x510]
100002e84: 4fc19294    	fmul.2d	v20, v20, v1[0]
100002e88: 4e74d673    	fadd.2d	v19, v19, v20
100002e8c: 3dc15d14    	ldr	q20, [x8, #0x570]
100002e90: 4fd19294    	fmul.2d	v20, v20, v17[0]
100002e94: 4e74d673    	fadd.2d	v19, v19, v20
100002e98: 3dc17514    	ldr	q20, [x8, #0x5d0]
100002e9c: 4fc59294    	fmul.2d	v20, v20, v5[0]
100002ea0: 4e74d673    	fadd.2d	v19, v19, v20
100002ea4: 3dc18d14    	ldr	q20, [x8, #0x630]
100002ea8: 4fc69294    	fmul.2d	v20, v20, v6[0]
100002eac: 4e74d673    	fadd.2d	v19, v19, v20
100002eb0: 3dc1a514    	ldr	q20, [x8, #0x690]
100002eb4: 4fc79294    	fmul.2d	v20, v20, v7[0]
100002eb8: 4e74d673    	fadd.2d	v19, v19, v20
100002ebc: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
100002ec0: 4fd09294    	fmul.2d	v20, v20, v16[0]
100002ec4: 4e74d673    	fadd.2d	v19, v19, v20
100002ec8: 3dc1d514    	ldr	q20, [x8, #0x750]
100002ecc: 4fc49294    	fmul.2d	v20, v20, v4[0]
100002ed0: 4e74d673    	fadd.2d	v19, v19, v20
100002ed4: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
100002ed8: 4fc29294    	fmul.2d	v20, v20, v2[0]
100002edc: 4e74d673    	fadd.2d	v19, v19, v20
100002ee0: 3dc20514    	ldr	q20, [x8, #0x810]
100002ee4: 4fc39294    	fmul.2d	v20, v20, v3[0]
100002ee8: 4e74d673    	fadd.2d	v19, v19, v20
100002eec: ad104d32    	stp	q18, q19, [x9, #0x200]
100002ef0: 3dc13112    	ldr	q18, [x8, #0x4c0]
100002ef4: 4fc09252    	fmul.2d	v18, v18, v0[0]
100002ef8: 3dc14913    	ldr	q19, [x8, #0x520]
100002efc: 4fc19273    	fmul.2d	v19, v19, v1[0]
100002f00: 4e73d652    	fadd.2d	v18, v18, v19
100002f04: 3dc16113    	ldr	q19, [x8, #0x580]
100002f08: 4fd19273    	fmul.2d	v19, v19, v17[0]
100002f0c: 4e73d652    	fadd.2d	v18, v18, v19
100002f10: 3dc17913    	ldr	q19, [x8, #0x5e0]
100002f14: 4fc59273    	fmul.2d	v19, v19, v5[0]
100002f18: 4e73d652    	fadd.2d	v18, v18, v19
100002f1c: 3dc19113    	ldr	q19, [x8, #0x640]
100002f20: 4fc69273    	fmul.2d	v19, v19, v6[0]
100002f24: 4e73d652    	fadd.2d	v18, v18, v19
100002f28: 3dc1a913    	ldr	q19, [x8, #0x6a0]
100002f2c: 4fc79273    	fmul.2d	v19, v19, v7[0]
100002f30: 4e73d652    	fadd.2d	v18, v18, v19
100002f34: 3dc1c113    	ldr	q19, [x8, #0x700]
100002f38: 4fd09273    	fmul.2d	v19, v19, v16[0]
100002f3c: 4e73d652    	fadd.2d	v18, v18, v19
100002f40: 3dc1d913    	ldr	q19, [x8, #0x760]
100002f44: 4fc49273    	fmul.2d	v19, v19, v4[0]
100002f48: 4e73d652    	fadd.2d	v18, v18, v19
100002f4c: 3dc1f113    	ldr	q19, [x8, #0x7c0]
100002f50: 4fc29273    	fmul.2d	v19, v19, v2[0]
100002f54: 4e73d652    	fadd.2d	v18, v18, v19
100002f58: 3dc20913    	ldr	q19, [x8, #0x820]
100002f5c: 4fc39273    	fmul.2d	v19, v19, v3[0]
100002f60: 4e73d652    	fadd.2d	v18, v18, v19
100002f64: 3dc13513    	ldr	q19, [x8, #0x4d0]
100002f68: 4fc09260    	fmul.2d	v0, v19, v0[0]
100002f6c: 3dc14d13    	ldr	q19, [x8, #0x530]
100002f70: 4fc19261    	fmul.2d	v1, v19, v1[0]
100002f74: 4e61d400    	fadd.2d	v0, v0, v1
100002f78: 3dc16501    	ldr	q1, [x8, #0x590]
100002f7c: 4fd19021    	fmul.2d	v1, v1, v17[0]
100002f80: 4e61d400    	fadd.2d	v0, v0, v1
100002f84: 3dc17d01    	ldr	q1, [x8, #0x5f0]
100002f88: 4fc59021    	fmul.2d	v1, v1, v5[0]
100002f8c: 4e61d400    	fadd.2d	v0, v0, v1
100002f90: 3dc19501    	ldr	q1, [x8, #0x650]
100002f94: 4fc69021    	fmul.2d	v1, v1, v6[0]
100002f98: 4e61d400    	fadd.2d	v0, v0, v1
100002f9c: 3dc1ad01    	ldr	q1, [x8, #0x6b0]
100002fa0: 4fc79021    	fmul.2d	v1, v1, v7[0]
100002fa4: 4e61d400    	fadd.2d	v0, v0, v1
100002fa8: 3dc1c501    	ldr	q1, [x8, #0x710]
100002fac: 4fd09021    	fmul.2d	v1, v1, v16[0]
100002fb0: 3dc1dd05    	ldr	q5, [x8, #0x770]
100002fb4: 4e61d400    	fadd.2d	v0, v0, v1
100002fb8: 4fc490a1    	fmul.2d	v1, v5, v4[0]
100002fbc: 3dc1f504    	ldr	q4, [x8, #0x7d0]
100002fc0: 4e61d400    	fadd.2d	v0, v0, v1
100002fc4: 3dc20d01    	ldr	q1, [x8, #0x830]
100002fc8: 4fc29082    	fmul.2d	v2, v4, v2[0]
100002fcc: 4e62d400    	fadd.2d	v0, v0, v2
100002fd0: 4fc39021    	fmul.2d	v1, v1, v3[0]
100002fd4: 4e61d400    	fadd.2d	v0, v0, v1
100002fd8: ad110132    	stp	q18, q0, [x9, #0x220]
100002fdc: fd412110    	ldr	d16, [x8, #0x240]
100002fe0: fd412511    	ldr	d17, [x8, #0x248]
100002fe4: fd412907    	ldr	d7, [x8, #0x250]
100002fe8: fd412d06    	ldr	d6, [x8, #0x258]
100002fec: fd413105    	ldr	d5, [x8, #0x260]
100002ff0: fd413504    	ldr	d4, [x8, #0x268]
100002ff4: fd413903    	ldr	d3, [x8, #0x270]
100002ff8: fd413d02    	ldr	d2, [x8, #0x278]
100002ffc: fd414100    	ldr	d0, [x8, #0x280]
100003000: fd414501    	ldr	d1, [x8, #0x288]
100003004: 3dc12112    	ldr	q18, [x8, #0x480]
100003008: 4fd09252    	fmul.2d	v18, v18, v16[0]
10000300c: 3dc13913    	ldr	q19, [x8, #0x4e0]
100003010: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003014: 4e73d652    	fadd.2d	v18, v18, v19
100003018: 3dc15113    	ldr	q19, [x8, #0x540]
10000301c: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003020: 4e73d652    	fadd.2d	v18, v18, v19
100003024: 3dc16913    	ldr	q19, [x8, #0x5a0]
100003028: 4fc69273    	fmul.2d	v19, v19, v6[0]
10000302c: 4e73d652    	fadd.2d	v18, v18, v19
100003030: 3dc18113    	ldr	q19, [x8, #0x600]
100003034: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003038: 4e73d652    	fadd.2d	v18, v18, v19
10000303c: 3dc19913    	ldr	q19, [x8, #0x660]
100003040: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003044: 4e73d652    	fadd.2d	v18, v18, v19
100003048: 3dc1b113    	ldr	q19, [x8, #0x6c0]
10000304c: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003050: 4e73d652    	fadd.2d	v18, v18, v19
100003054: 3dc1c913    	ldr	q19, [x8, #0x720]
100003058: 4fc29273    	fmul.2d	v19, v19, v2[0]
10000305c: 4e73d652    	fadd.2d	v18, v18, v19
100003060: 3dc1e113    	ldr	q19, [x8, #0x780]
100003064: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003068: 4e73d652    	fadd.2d	v18, v18, v19
10000306c: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003070: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003074: 4e73d652    	fadd.2d	v18, v18, v19
100003078: 3dc12513    	ldr	q19, [x8, #0x490]
10000307c: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003080: 3dc13d14    	ldr	q20, [x8, #0x4f0]
100003084: 4fd19294    	fmul.2d	v20, v20, v17[0]
100003088: 4e74d673    	fadd.2d	v19, v19, v20
10000308c: 3dc15514    	ldr	q20, [x8, #0x550]
100003090: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003094: 4e74d673    	fadd.2d	v19, v19, v20
100003098: 3dc16d14    	ldr	q20, [x8, #0x5b0]
10000309c: 4fc69294    	fmul.2d	v20, v20, v6[0]
1000030a0: 4e74d673    	fadd.2d	v19, v19, v20
1000030a4: 3dc18514    	ldr	q20, [x8, #0x610]
1000030a8: 4fc59294    	fmul.2d	v20, v20, v5[0]
1000030ac: 4e74d673    	fadd.2d	v19, v19, v20
1000030b0: 3dc19d14    	ldr	q20, [x8, #0x670]
1000030b4: 4fc49294    	fmul.2d	v20, v20, v4[0]
1000030b8: 4e74d673    	fadd.2d	v19, v19, v20
1000030bc: 3dc1b514    	ldr	q20, [x8, #0x6d0]
1000030c0: 4fc39294    	fmul.2d	v20, v20, v3[0]
1000030c4: 4e74d673    	fadd.2d	v19, v19, v20
1000030c8: 3dc1cd14    	ldr	q20, [x8, #0x730]
1000030cc: 4fc29294    	fmul.2d	v20, v20, v2[0]
1000030d0: 4e74d673    	fadd.2d	v19, v19, v20
1000030d4: 3dc1e514    	ldr	q20, [x8, #0x790]
1000030d8: 4fc09294    	fmul.2d	v20, v20, v0[0]
1000030dc: 4e74d673    	fadd.2d	v19, v19, v20
1000030e0: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
1000030e4: 4fc19294    	fmul.2d	v20, v20, v1[0]
1000030e8: 4e74d673    	fadd.2d	v19, v19, v20
1000030ec: ad124d32    	stp	q18, q19, [x9, #0x240]
1000030f0: 3dc12912    	ldr	q18, [x8, #0x4a0]
1000030f4: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000030f8: 3dc14113    	ldr	q19, [x8, #0x500]
1000030fc: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003100: 4e73d652    	fadd.2d	v18, v18, v19
100003104: 3dc15913    	ldr	q19, [x8, #0x560]
100003108: 4fc79273    	fmul.2d	v19, v19, v7[0]
10000310c: 4e73d652    	fadd.2d	v18, v18, v19
100003110: 3dc17113    	ldr	q19, [x8, #0x5c0]
100003114: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003118: 4e73d652    	fadd.2d	v18, v18, v19
10000311c: 3dc18913    	ldr	q19, [x8, #0x620]
100003120: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003124: 4e73d652    	fadd.2d	v18, v18, v19
100003128: 3dc1a113    	ldr	q19, [x8, #0x680]
10000312c: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003130: 4e73d652    	fadd.2d	v18, v18, v19
100003134: 3dc1b913    	ldr	q19, [x8, #0x6e0]
100003138: 4fc39273    	fmul.2d	v19, v19, v3[0]
10000313c: 4e73d652    	fadd.2d	v18, v18, v19
100003140: 3dc1d113    	ldr	q19, [x8, #0x740]
100003144: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003148: 4e73d652    	fadd.2d	v18, v18, v19
10000314c: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003150: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003154: 4e73d652    	fadd.2d	v18, v18, v19
100003158: 3dc20113    	ldr	q19, [x8, #0x800]
10000315c: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003160: 4e73d652    	fadd.2d	v18, v18, v19
100003164: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003168: 4fd09273    	fmul.2d	v19, v19, v16[0]
10000316c: 3dc14514    	ldr	q20, [x8, #0x510]
100003170: 4fd19294    	fmul.2d	v20, v20, v17[0]
100003174: 4e74d673    	fadd.2d	v19, v19, v20
100003178: 3dc15d14    	ldr	q20, [x8, #0x570]
10000317c: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003180: 4e74d673    	fadd.2d	v19, v19, v20
100003184: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003188: 4fc69294    	fmul.2d	v20, v20, v6[0]
10000318c: 4e74d673    	fadd.2d	v19, v19, v20
100003190: 3dc18d14    	ldr	q20, [x8, #0x630]
100003194: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003198: 4e74d673    	fadd.2d	v19, v19, v20
10000319c: 3dc1a514    	ldr	q20, [x8, #0x690]
1000031a0: 4fc49294    	fmul.2d	v20, v20, v4[0]
1000031a4: 4e74d673    	fadd.2d	v19, v19, v20
1000031a8: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
1000031ac: 4fc39294    	fmul.2d	v20, v20, v3[0]
1000031b0: 4e74d673    	fadd.2d	v19, v19, v20
1000031b4: 3dc1d514    	ldr	q20, [x8, #0x750]
1000031b8: 4fc29294    	fmul.2d	v20, v20, v2[0]
1000031bc: 4e74d673    	fadd.2d	v19, v19, v20
1000031c0: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
1000031c4: 4fc09294    	fmul.2d	v20, v20, v0[0]
1000031c8: 4e74d673    	fadd.2d	v19, v19, v20
1000031cc: 3dc20514    	ldr	q20, [x8, #0x810]
1000031d0: 4fc19294    	fmul.2d	v20, v20, v1[0]
1000031d4: 4e74d673    	fadd.2d	v19, v19, v20
1000031d8: ad134d32    	stp	q18, q19, [x9, #0x260]
1000031dc: 3dc13112    	ldr	q18, [x8, #0x4c0]
1000031e0: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000031e4: 3dc14913    	ldr	q19, [x8, #0x520]
1000031e8: 4fd19273    	fmul.2d	v19, v19, v17[0]
1000031ec: 4e73d652    	fadd.2d	v18, v18, v19
1000031f0: 3dc16113    	ldr	q19, [x8, #0x580]
1000031f4: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000031f8: 4e73d652    	fadd.2d	v18, v18, v19
1000031fc: 3dc17913    	ldr	q19, [x8, #0x5e0]
100003200: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003204: 4e73d652    	fadd.2d	v18, v18, v19
100003208: 3dc19113    	ldr	q19, [x8, #0x640]
10000320c: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003210: 4e73d652    	fadd.2d	v18, v18, v19
100003214: 3dc1a913    	ldr	q19, [x8, #0x6a0]
100003218: 4fc49273    	fmul.2d	v19, v19, v4[0]
10000321c: 4e73d652    	fadd.2d	v18, v18, v19
100003220: 3dc1c113    	ldr	q19, [x8, #0x700]
100003224: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003228: 4e73d652    	fadd.2d	v18, v18, v19
10000322c: 3dc1d913    	ldr	q19, [x8, #0x760]
100003230: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003234: 4e73d652    	fadd.2d	v18, v18, v19
100003238: 3dc1f113    	ldr	q19, [x8, #0x7c0]
10000323c: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003240: 4e73d652    	fadd.2d	v18, v18, v19
100003244: 3dc20913    	ldr	q19, [x8, #0x820]
100003248: 4fc19273    	fmul.2d	v19, v19, v1[0]
10000324c: 4e73d652    	fadd.2d	v18, v18, v19
100003250: 3dc13513    	ldr	q19, [x8, #0x4d0]
100003254: 4fd09270    	fmul.2d	v16, v19, v16[0]
100003258: 3dc14d13    	ldr	q19, [x8, #0x530]
10000325c: 4fd19271    	fmul.2d	v17, v19, v17[0]
100003260: 4e71d610    	fadd.2d	v16, v16, v17
100003264: 3dc16511    	ldr	q17, [x8, #0x590]
100003268: 4fc79227    	fmul.2d	v7, v17, v7[0]
10000326c: 4e67d607    	fadd.2d	v7, v16, v7
100003270: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100003274: 4fc69206    	fmul.2d	v6, v16, v6[0]
100003278: 4e66d4e6    	fadd.2d	v6, v7, v6
10000327c: 3dc19507    	ldr	q7, [x8, #0x650]
100003280: 4fc590e5    	fmul.2d	v5, v7, v5[0]
100003284: 4e65d4c5    	fadd.2d	v5, v6, v5
100003288: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
10000328c: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100003290: 4e64d4a4    	fadd.2d	v4, v5, v4
100003294: 3dc1c505    	ldr	q5, [x8, #0x710]
100003298: 4fc390a3    	fmul.2d	v3, v5, v3[0]
10000329c: 3dc1dd05    	ldr	q5, [x8, #0x770]
1000032a0: 4e63d483    	fadd.2d	v3, v4, v3
1000032a4: 4fc290a2    	fmul.2d	v2, v5, v2[0]
1000032a8: 3dc1f504    	ldr	q4, [x8, #0x7d0]
1000032ac: 4e62d462    	fadd.2d	v2, v3, v2
1000032b0: 3dc20d03    	ldr	q3, [x8, #0x830]
1000032b4: 4fc09080    	fmul.2d	v0, v4, v0[0]
1000032b8: 4e60d440    	fadd.2d	v0, v2, v0
1000032bc: 4fc19061    	fmul.2d	v1, v3, v1[0]
1000032c0: 4e61d400    	fadd.2d	v0, v0, v1
1000032c4: ad140132    	stp	q18, q0, [x9, #0x280]
1000032c8: fd415110    	ldr	d16, [x8, #0x2a0]
1000032cc: fd415511    	ldr	d17, [x8, #0x2a8]
1000032d0: fd415907    	ldr	d7, [x8, #0x2b0]
1000032d4: fd415d06    	ldr	d6, [x8, #0x2b8]
1000032d8: fd416105    	ldr	d5, [x8, #0x2c0]
1000032dc: fd416504    	ldr	d4, [x8, #0x2c8]
1000032e0: fd416903    	ldr	d3, [x8, #0x2d0]
1000032e4: fd416d02    	ldr	d2, [x8, #0x2d8]
1000032e8: fd417100    	ldr	d0, [x8, #0x2e0]
1000032ec: fd417501    	ldr	d1, [x8, #0x2e8]
1000032f0: 3dc12112    	ldr	q18, [x8, #0x480]
1000032f4: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000032f8: 3dc13913    	ldr	q19, [x8, #0x4e0]
1000032fc: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003300: 4e73d652    	fadd.2d	v18, v18, v19
100003304: 3dc15113    	ldr	q19, [x8, #0x540]
100003308: 4fc79273    	fmul.2d	v19, v19, v7[0]
10000330c: 4e73d652    	fadd.2d	v18, v18, v19
100003310: 3dc16913    	ldr	q19, [x8, #0x5a0]
100003314: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003318: 4e73d652    	fadd.2d	v18, v18, v19
10000331c: 3dc18113    	ldr	q19, [x8, #0x600]
100003320: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003324: 4e73d652    	fadd.2d	v18, v18, v19
100003328: 3dc19913    	ldr	q19, [x8, #0x660]
10000332c: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003330: 4e73d652    	fadd.2d	v18, v18, v19
100003334: 3dc1b113    	ldr	q19, [x8, #0x6c0]
100003338: 4fc39273    	fmul.2d	v19, v19, v3[0]
10000333c: 4e73d652    	fadd.2d	v18, v18, v19
100003340: 3dc1c913    	ldr	q19, [x8, #0x720]
100003344: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003348: 4e73d652    	fadd.2d	v18, v18, v19
10000334c: 3dc1e113    	ldr	q19, [x8, #0x780]
100003350: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003354: 4e73d652    	fadd.2d	v18, v18, v19
100003358: 3dc1f913    	ldr	q19, [x8, #0x7e0]
10000335c: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003360: 4e73d652    	fadd.2d	v18, v18, v19
100003364: 3dc12513    	ldr	q19, [x8, #0x490]
100003368: 4fd09273    	fmul.2d	v19, v19, v16[0]
10000336c: 3dc13d14    	ldr	q20, [x8, #0x4f0]
100003370: 4fd19294    	fmul.2d	v20, v20, v17[0]
100003374: 4e74d673    	fadd.2d	v19, v19, v20
100003378: 3dc15514    	ldr	q20, [x8, #0x550]
10000337c: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003380: 4e74d673    	fadd.2d	v19, v19, v20
100003384: 3dc16d14    	ldr	q20, [x8, #0x5b0]
100003388: 4fc69294    	fmul.2d	v20, v20, v6[0]
10000338c: 4e74d673    	fadd.2d	v19, v19, v20
100003390: 3dc18514    	ldr	q20, [x8, #0x610]
100003394: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003398: 4e74d673    	fadd.2d	v19, v19, v20
10000339c: 3dc19d14    	ldr	q20, [x8, #0x670]
1000033a0: 4fc49294    	fmul.2d	v20, v20, v4[0]
1000033a4: 4e74d673    	fadd.2d	v19, v19, v20
1000033a8: 3dc1b514    	ldr	q20, [x8, #0x6d0]
1000033ac: 4fc39294    	fmul.2d	v20, v20, v3[0]
1000033b0: 4e74d673    	fadd.2d	v19, v19, v20
1000033b4: 3dc1cd14    	ldr	q20, [x8, #0x730]
1000033b8: 4fc29294    	fmul.2d	v20, v20, v2[0]
1000033bc: 4e74d673    	fadd.2d	v19, v19, v20
1000033c0: 3dc1e514    	ldr	q20, [x8, #0x790]
1000033c4: 4fc09294    	fmul.2d	v20, v20, v0[0]
1000033c8: 4e74d673    	fadd.2d	v19, v19, v20
1000033cc: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
1000033d0: 4fc19294    	fmul.2d	v20, v20, v1[0]
1000033d4: 4e74d673    	fadd.2d	v19, v19, v20
1000033d8: ad154d32    	stp	q18, q19, [x9, #0x2a0]
1000033dc: 3dc12912    	ldr	q18, [x8, #0x4a0]
1000033e0: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000033e4: 3dc14113    	ldr	q19, [x8, #0x500]
1000033e8: 4fd19273    	fmul.2d	v19, v19, v17[0]
1000033ec: 4e73d652    	fadd.2d	v18, v18, v19
1000033f0: 3dc15913    	ldr	q19, [x8, #0x560]
1000033f4: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000033f8: 4e73d652    	fadd.2d	v18, v18, v19
1000033fc: 3dc17113    	ldr	q19, [x8, #0x5c0]
100003400: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003404: 4e73d652    	fadd.2d	v18, v18, v19
100003408: 3dc18913    	ldr	q19, [x8, #0x620]
10000340c: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003410: 4e73d652    	fadd.2d	v18, v18, v19
100003414: 3dc1a113    	ldr	q19, [x8, #0x680]
100003418: 4fc49273    	fmul.2d	v19, v19, v4[0]
10000341c: 4e73d652    	fadd.2d	v18, v18, v19
100003420: 3dc1b913    	ldr	q19, [x8, #0x6e0]
100003424: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003428: 4e73d652    	fadd.2d	v18, v18, v19
10000342c: 3dc1d113    	ldr	q19, [x8, #0x740]
100003430: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003434: 4e73d652    	fadd.2d	v18, v18, v19
100003438: 3dc1e913    	ldr	q19, [x8, #0x7a0]
10000343c: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003440: 4e73d652    	fadd.2d	v18, v18, v19
100003444: 3dc20113    	ldr	q19, [x8, #0x800]
100003448: 4fc19273    	fmul.2d	v19, v19, v1[0]
10000344c: 4e73d652    	fadd.2d	v18, v18, v19
100003450: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003454: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003458: 3dc14514    	ldr	q20, [x8, #0x510]
10000345c: 4fd19294    	fmul.2d	v20, v20, v17[0]
100003460: 4e74d673    	fadd.2d	v19, v19, v20
100003464: 3dc15d14    	ldr	q20, [x8, #0x570]
100003468: 4fc79294    	fmul.2d	v20, v20, v7[0]
10000346c: 4e74d673    	fadd.2d	v19, v19, v20
100003470: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003474: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003478: 4e74d673    	fadd.2d	v19, v19, v20
10000347c: 3dc18d14    	ldr	q20, [x8, #0x630]
100003480: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003484: 4e74d673    	fadd.2d	v19, v19, v20
100003488: 3dc1a514    	ldr	q20, [x8, #0x690]
10000348c: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003490: 4e74d673    	fadd.2d	v19, v19, v20
100003494: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
100003498: 4fc39294    	fmul.2d	v20, v20, v3[0]
10000349c: 4e74d673    	fadd.2d	v19, v19, v20
1000034a0: 3dc1d514    	ldr	q20, [x8, #0x750]
1000034a4: 4fc29294    	fmul.2d	v20, v20, v2[0]
1000034a8: 4e74d673    	fadd.2d	v19, v19, v20
1000034ac: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
1000034b0: 4fc09294    	fmul.2d	v20, v20, v0[0]
1000034b4: 4e74d673    	fadd.2d	v19, v19, v20
1000034b8: 3dc20514    	ldr	q20, [x8, #0x810]
1000034bc: 4fc19294    	fmul.2d	v20, v20, v1[0]
1000034c0: 4e74d673    	fadd.2d	v19, v19, v20
1000034c4: ad164d32    	stp	q18, q19, [x9, #0x2c0]
1000034c8: 3dc13112    	ldr	q18, [x8, #0x4c0]
1000034cc: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000034d0: 3dc14913    	ldr	q19, [x8, #0x520]
1000034d4: 4fd19273    	fmul.2d	v19, v19, v17[0]
1000034d8: 4e73d652    	fadd.2d	v18, v18, v19
1000034dc: 3dc16113    	ldr	q19, [x8, #0x580]
1000034e0: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000034e4: 4e73d652    	fadd.2d	v18, v18, v19
1000034e8: 3dc17913    	ldr	q19, [x8, #0x5e0]
1000034ec: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000034f0: 4e73d652    	fadd.2d	v18, v18, v19
1000034f4: 3dc19113    	ldr	q19, [x8, #0x640]
1000034f8: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000034fc: 4e73d652    	fadd.2d	v18, v18, v19
100003500: 3dc1a913    	ldr	q19, [x8, #0x6a0]
100003504: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003508: 4e73d652    	fadd.2d	v18, v18, v19
10000350c: 3dc1c113    	ldr	q19, [x8, #0x700]
100003510: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003514: 4e73d652    	fadd.2d	v18, v18, v19
100003518: 3dc1d913    	ldr	q19, [x8, #0x760]
10000351c: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003520: 4e73d652    	fadd.2d	v18, v18, v19
100003524: 3dc1f113    	ldr	q19, [x8, #0x7c0]
100003528: 4fc09273    	fmul.2d	v19, v19, v0[0]
10000352c: 4e73d652    	fadd.2d	v18, v18, v19
100003530: 3dc20913    	ldr	q19, [x8, #0x820]
100003534: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003538: 4e73d652    	fadd.2d	v18, v18, v19
10000353c: 3dc13513    	ldr	q19, [x8, #0x4d0]
100003540: 4fd09270    	fmul.2d	v16, v19, v16[0]
100003544: 3dc14d13    	ldr	q19, [x8, #0x530]
100003548: 4fd19271    	fmul.2d	v17, v19, v17[0]
10000354c: 4e71d610    	fadd.2d	v16, v16, v17
100003550: 3dc16511    	ldr	q17, [x8, #0x590]
100003554: 4fc79227    	fmul.2d	v7, v17, v7[0]
100003558: 4e67d607    	fadd.2d	v7, v16, v7
10000355c: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100003560: 4fc69206    	fmul.2d	v6, v16, v6[0]
100003564: 4e66d4e6    	fadd.2d	v6, v7, v6
100003568: 3dc19507    	ldr	q7, [x8, #0x650]
10000356c: 4fc590e5    	fmul.2d	v5, v7, v5[0]
100003570: 4e65d4c5    	fadd.2d	v5, v6, v5
100003574: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
100003578: 4fc490c4    	fmul.2d	v4, v6, v4[0]
10000357c: 4e64d4a4    	fadd.2d	v4, v5, v4
100003580: 3dc1c505    	ldr	q5, [x8, #0x710]
100003584: 4fc390a3    	fmul.2d	v3, v5, v3[0]
100003588: 3dc1dd05    	ldr	q5, [x8, #0x770]
10000358c: 4e63d483    	fadd.2d	v3, v4, v3
100003590: 4fc290a2    	fmul.2d	v2, v5, v2[0]
100003594: 3dc1f504    	ldr	q4, [x8, #0x7d0]
100003598: 4e62d462    	fadd.2d	v2, v3, v2
10000359c: 3dc20d03    	ldr	q3, [x8, #0x830]
1000035a0: 4fc09080    	fmul.2d	v0, v4, v0[0]
1000035a4: 4e60d440    	fadd.2d	v0, v2, v0
1000035a8: 4fc19061    	fmul.2d	v1, v3, v1[0]
1000035ac: 4e61d400    	fadd.2d	v0, v0, v1
1000035b0: ad170132    	stp	q18, q0, [x9, #0x2e0]
1000035b4: fd418110    	ldr	d16, [x8, #0x300]
1000035b8: fd418511    	ldr	d17, [x8, #0x308]
1000035bc: fd418907    	ldr	d7, [x8, #0x310]
1000035c0: fd418d06    	ldr	d6, [x8, #0x318]
1000035c4: fd419105    	ldr	d5, [x8, #0x320]
1000035c8: fd419504    	ldr	d4, [x8, #0x328]
1000035cc: fd419903    	ldr	d3, [x8, #0x330]
1000035d0: fd419d02    	ldr	d2, [x8, #0x338]
1000035d4: fd41a100    	ldr	d0, [x8, #0x340]
1000035d8: fd41a501    	ldr	d1, [x8, #0x348]
1000035dc: 3dc12112    	ldr	q18, [x8, #0x480]
1000035e0: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000035e4: 3dc13913    	ldr	q19, [x8, #0x4e0]
1000035e8: 4fd19273    	fmul.2d	v19, v19, v17[0]
1000035ec: 4e73d652    	fadd.2d	v18, v18, v19
1000035f0: 3dc15113    	ldr	q19, [x8, #0x540]
1000035f4: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000035f8: 4e73d652    	fadd.2d	v18, v18, v19
1000035fc: 3dc16913    	ldr	q19, [x8, #0x5a0]
100003600: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003604: 4e73d652    	fadd.2d	v18, v18, v19
100003608: 3dc18113    	ldr	q19, [x8, #0x600]
10000360c: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003610: 4e73d652    	fadd.2d	v18, v18, v19
100003614: 3dc19913    	ldr	q19, [x8, #0x660]
100003618: 4fc49273    	fmul.2d	v19, v19, v4[0]
10000361c: 4e73d652    	fadd.2d	v18, v18, v19
100003620: 3dc1b113    	ldr	q19, [x8, #0x6c0]
100003624: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003628: 4e73d652    	fadd.2d	v18, v18, v19
10000362c: 3dc1c913    	ldr	q19, [x8, #0x720]
100003630: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003634: 4e73d652    	fadd.2d	v18, v18, v19
100003638: 3dc1e113    	ldr	q19, [x8, #0x780]
10000363c: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003640: 4e73d652    	fadd.2d	v18, v18, v19
100003644: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003648: 4fc19273    	fmul.2d	v19, v19, v1[0]
10000364c: 4e73d652    	fadd.2d	v18, v18, v19
100003650: 3dc12513    	ldr	q19, [x8, #0x490]
100003654: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003658: 3dc13d14    	ldr	q20, [x8, #0x4f0]
10000365c: 4fd19294    	fmul.2d	v20, v20, v17[0]
100003660: 4e74d673    	fadd.2d	v19, v19, v20
100003664: 3dc15514    	ldr	q20, [x8, #0x550]
100003668: 4fc79294    	fmul.2d	v20, v20, v7[0]
10000366c: 4e74d673    	fadd.2d	v19, v19, v20
100003670: 3dc16d14    	ldr	q20, [x8, #0x5b0]
100003674: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003678: 4e74d673    	fadd.2d	v19, v19, v20
10000367c: 3dc18514    	ldr	q20, [x8, #0x610]
100003680: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003684: 4e74d673    	fadd.2d	v19, v19, v20
100003688: 3dc19d14    	ldr	q20, [x8, #0x670]
10000368c: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003690: 4e74d673    	fadd.2d	v19, v19, v20
100003694: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100003698: 4fc39294    	fmul.2d	v20, v20, v3[0]
10000369c: 4e74d673    	fadd.2d	v19, v19, v20
1000036a0: 3dc1cd14    	ldr	q20, [x8, #0x730]
1000036a4: 4fc29294    	fmul.2d	v20, v20, v2[0]
1000036a8: 4e74d673    	fadd.2d	v19, v19, v20
1000036ac: 3dc1e514    	ldr	q20, [x8, #0x790]
1000036b0: 4fc09294    	fmul.2d	v20, v20, v0[0]
1000036b4: 4e74d673    	fadd.2d	v19, v19, v20
1000036b8: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
1000036bc: 4fc19294    	fmul.2d	v20, v20, v1[0]
1000036c0: 4e74d673    	fadd.2d	v19, v19, v20
1000036c4: ad184d32    	stp	q18, q19, [x9, #0x300]
1000036c8: 3dc12912    	ldr	q18, [x8, #0x4a0]
1000036cc: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000036d0: 3dc14113    	ldr	q19, [x8, #0x500]
1000036d4: 4fd19273    	fmul.2d	v19, v19, v17[0]
1000036d8: 4e73d652    	fadd.2d	v18, v18, v19
1000036dc: 3dc15913    	ldr	q19, [x8, #0x560]
1000036e0: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000036e4: 4e73d652    	fadd.2d	v18, v18, v19
1000036e8: 3dc17113    	ldr	q19, [x8, #0x5c0]
1000036ec: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000036f0: 4e73d652    	fadd.2d	v18, v18, v19
1000036f4: 3dc18913    	ldr	q19, [x8, #0x620]
1000036f8: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000036fc: 4e73d652    	fadd.2d	v18, v18, v19
100003700: 3dc1a113    	ldr	q19, [x8, #0x680]
100003704: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003708: 4e73d652    	fadd.2d	v18, v18, v19
10000370c: 3dc1b913    	ldr	q19, [x8, #0x6e0]
100003710: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003714: 4e73d652    	fadd.2d	v18, v18, v19
100003718: 3dc1d113    	ldr	q19, [x8, #0x740]
10000371c: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003720: 4e73d652    	fadd.2d	v18, v18, v19
100003724: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003728: 4fc09273    	fmul.2d	v19, v19, v0[0]
10000372c: 4e73d652    	fadd.2d	v18, v18, v19
100003730: 3dc20113    	ldr	q19, [x8, #0x800]
100003734: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003738: 4e73d652    	fadd.2d	v18, v18, v19
10000373c: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003740: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003744: 3dc14514    	ldr	q20, [x8, #0x510]
100003748: 4fd19294    	fmul.2d	v20, v20, v17[0]
10000374c: 4e74d673    	fadd.2d	v19, v19, v20
100003750: 3dc15d14    	ldr	q20, [x8, #0x570]
100003754: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003758: 4e74d673    	fadd.2d	v19, v19, v20
10000375c: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003760: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003764: 4e74d673    	fadd.2d	v19, v19, v20
100003768: 3dc18d14    	ldr	q20, [x8, #0x630]
10000376c: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003770: 4e74d673    	fadd.2d	v19, v19, v20
100003774: 3dc1a514    	ldr	q20, [x8, #0x690]
100003778: 4fc49294    	fmul.2d	v20, v20, v4[0]
10000377c: 4e74d673    	fadd.2d	v19, v19, v20
100003780: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
100003784: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003788: 4e74d673    	fadd.2d	v19, v19, v20
10000378c: 3dc1d514    	ldr	q20, [x8, #0x750]
100003790: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003794: 4e74d673    	fadd.2d	v19, v19, v20
100003798: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
10000379c: 4fc09294    	fmul.2d	v20, v20, v0[0]
1000037a0: 4e74d673    	fadd.2d	v19, v19, v20
1000037a4: 3dc20514    	ldr	q20, [x8, #0x810]
1000037a8: 4fc19294    	fmul.2d	v20, v20, v1[0]
1000037ac: 4e74d673    	fadd.2d	v19, v19, v20
1000037b0: ad194d32    	stp	q18, q19, [x9, #0x320]
1000037b4: 3dc13112    	ldr	q18, [x8, #0x4c0]
1000037b8: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000037bc: 3dc14913    	ldr	q19, [x8, #0x520]
1000037c0: 4fd19273    	fmul.2d	v19, v19, v17[0]
1000037c4: 4e73d652    	fadd.2d	v18, v18, v19
1000037c8: 3dc16113    	ldr	q19, [x8, #0x580]
1000037cc: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000037d0: 4e73d652    	fadd.2d	v18, v18, v19
1000037d4: 3dc17913    	ldr	q19, [x8, #0x5e0]
1000037d8: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000037dc: 4e73d652    	fadd.2d	v18, v18, v19
1000037e0: 3dc19113    	ldr	q19, [x8, #0x640]
1000037e4: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000037e8: 4e73d652    	fadd.2d	v18, v18, v19
1000037ec: 3dc1a913    	ldr	q19, [x8, #0x6a0]
1000037f0: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000037f4: 4e73d652    	fadd.2d	v18, v18, v19
1000037f8: 3dc1c113    	ldr	q19, [x8, #0x700]
1000037fc: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003800: 4e73d652    	fadd.2d	v18, v18, v19
100003804: 3dc1d913    	ldr	q19, [x8, #0x760]
100003808: 4fc29273    	fmul.2d	v19, v19, v2[0]
10000380c: 4e73d652    	fadd.2d	v18, v18, v19
100003810: 3dc1f113    	ldr	q19, [x8, #0x7c0]
100003814: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003818: 4e73d652    	fadd.2d	v18, v18, v19
10000381c: 3dc20913    	ldr	q19, [x8, #0x820]
100003820: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003824: 4e73d652    	fadd.2d	v18, v18, v19
100003828: 3dc13513    	ldr	q19, [x8, #0x4d0]
10000382c: 4fd09270    	fmul.2d	v16, v19, v16[0]
100003830: 3dc14d13    	ldr	q19, [x8, #0x530]
100003834: 4fd19271    	fmul.2d	v17, v19, v17[0]
100003838: 4e71d610    	fadd.2d	v16, v16, v17
10000383c: 3dc16511    	ldr	q17, [x8, #0x590]
100003840: 4fc79227    	fmul.2d	v7, v17, v7[0]
100003844: 4e67d607    	fadd.2d	v7, v16, v7
100003848: 3dc17d10    	ldr	q16, [x8, #0x5f0]
10000384c: 4fc69206    	fmul.2d	v6, v16, v6[0]
100003850: 4e66d4e6    	fadd.2d	v6, v7, v6
100003854: 3dc19507    	ldr	q7, [x8, #0x650]
100003858: 4fc590e5    	fmul.2d	v5, v7, v5[0]
10000385c: 4e65d4c5    	fadd.2d	v5, v6, v5
100003860: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
100003864: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100003868: 4e64d4a4    	fadd.2d	v4, v5, v4
10000386c: 3dc1c505    	ldr	q5, [x8, #0x710]
100003870: 4fc390a3    	fmul.2d	v3, v5, v3[0]
100003874: 3dc1dd05    	ldr	q5, [x8, #0x770]
100003878: 4e63d483    	fadd.2d	v3, v4, v3
10000387c: 4fc290a2    	fmul.2d	v2, v5, v2[0]
100003880: 3dc1f504    	ldr	q4, [x8, #0x7d0]
100003884: 4e62d462    	fadd.2d	v2, v3, v2
100003888: 3dc20d03    	ldr	q3, [x8, #0x830]
10000388c: 4fc09080    	fmul.2d	v0, v4, v0[0]
100003890: 4e60d440    	fadd.2d	v0, v2, v0
100003894: 4fc19061    	fmul.2d	v1, v3, v1[0]
100003898: 4e61d400    	fadd.2d	v0, v0, v1
10000389c: ad1a0132    	stp	q18, q0, [x9, #0x340]
1000038a0: fd41b110    	ldr	d16, [x8, #0x360]
1000038a4: fd41b511    	ldr	d17, [x8, #0x368]
1000038a8: fd41b907    	ldr	d7, [x8, #0x370]
1000038ac: fd41bd06    	ldr	d6, [x8, #0x378]
1000038b0: fd41c105    	ldr	d5, [x8, #0x380]
1000038b4: fd41c504    	ldr	d4, [x8, #0x388]
1000038b8: fd41c903    	ldr	d3, [x8, #0x390]
1000038bc: fd41cd02    	ldr	d2, [x8, #0x398]
1000038c0: fd41d100    	ldr	d0, [x8, #0x3a0]
1000038c4: fd41d501    	ldr	d1, [x8, #0x3a8]
1000038c8: 3dc12112    	ldr	q18, [x8, #0x480]
1000038cc: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000038d0: 3dc13913    	ldr	q19, [x8, #0x4e0]
1000038d4: 4fd19273    	fmul.2d	v19, v19, v17[0]
1000038d8: 4e73d652    	fadd.2d	v18, v18, v19
1000038dc: 3dc15113    	ldr	q19, [x8, #0x540]
1000038e0: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000038e4: 4e73d652    	fadd.2d	v18, v18, v19
1000038e8: 3dc16913    	ldr	q19, [x8, #0x5a0]
1000038ec: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000038f0: 4e73d652    	fadd.2d	v18, v18, v19
1000038f4: 3dc18113    	ldr	q19, [x8, #0x600]
1000038f8: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000038fc: 4e73d652    	fadd.2d	v18, v18, v19
100003900: 3dc19913    	ldr	q19, [x8, #0x660]
100003904: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003908: 4e73d652    	fadd.2d	v18, v18, v19
10000390c: 3dc1b113    	ldr	q19, [x8, #0x6c0]
100003910: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003914: 4e73d652    	fadd.2d	v18, v18, v19
100003918: 3dc1c913    	ldr	q19, [x8, #0x720]
10000391c: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003920: 4e73d652    	fadd.2d	v18, v18, v19
100003924: 3dc1e113    	ldr	q19, [x8, #0x780]
100003928: 4fc09273    	fmul.2d	v19, v19, v0[0]
10000392c: 4e73d652    	fadd.2d	v18, v18, v19
100003930: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003934: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003938: 4e73d652    	fadd.2d	v18, v18, v19
10000393c: 3dc12513    	ldr	q19, [x8, #0x490]
100003940: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003944: 3dc13d14    	ldr	q20, [x8, #0x4f0]
100003948: 4fd19294    	fmul.2d	v20, v20, v17[0]
10000394c: 4e74d673    	fadd.2d	v19, v19, v20
100003950: 3dc15514    	ldr	q20, [x8, #0x550]
100003954: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003958: 4e74d673    	fadd.2d	v19, v19, v20
10000395c: 3dc16d14    	ldr	q20, [x8, #0x5b0]
100003960: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003964: 4e74d673    	fadd.2d	v19, v19, v20
100003968: 3dc18514    	ldr	q20, [x8, #0x610]
10000396c: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003970: 4e74d673    	fadd.2d	v19, v19, v20
100003974: 3dc19d14    	ldr	q20, [x8, #0x670]
100003978: 4fc49294    	fmul.2d	v20, v20, v4[0]
10000397c: 4e74d673    	fadd.2d	v19, v19, v20
100003980: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100003984: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003988: 4e74d673    	fadd.2d	v19, v19, v20
10000398c: 3dc1cd14    	ldr	q20, [x8, #0x730]
100003990: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003994: 4e74d673    	fadd.2d	v19, v19, v20
100003998: 3dc1e514    	ldr	q20, [x8, #0x790]
10000399c: 4fc09294    	fmul.2d	v20, v20, v0[0]
1000039a0: 4e74d673    	fadd.2d	v19, v19, v20
1000039a4: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
1000039a8: 4fc19294    	fmul.2d	v20, v20, v1[0]
1000039ac: 4e74d673    	fadd.2d	v19, v19, v20
1000039b0: ad1b4d32    	stp	q18, q19, [x9, #0x360]
1000039b4: 3dc12912    	ldr	q18, [x8, #0x4a0]
1000039b8: 4fd09252    	fmul.2d	v18, v18, v16[0]
1000039bc: 3dc14113    	ldr	q19, [x8, #0x500]
1000039c0: 4fd19273    	fmul.2d	v19, v19, v17[0]
1000039c4: 4e73d652    	fadd.2d	v18, v18, v19
1000039c8: 3dc15913    	ldr	q19, [x8, #0x560]
1000039cc: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000039d0: 4e73d652    	fadd.2d	v18, v18, v19
1000039d4: 3dc17113    	ldr	q19, [x8, #0x5c0]
1000039d8: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000039dc: 4e73d652    	fadd.2d	v18, v18, v19
1000039e0: 3dc18913    	ldr	q19, [x8, #0x620]
1000039e4: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000039e8: 4e73d652    	fadd.2d	v18, v18, v19
1000039ec: 3dc1a113    	ldr	q19, [x8, #0x680]
1000039f0: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000039f4: 4e73d652    	fadd.2d	v18, v18, v19
1000039f8: 3dc1b913    	ldr	q19, [x8, #0x6e0]
1000039fc: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003a00: 4e73d652    	fadd.2d	v18, v18, v19
100003a04: 3dc1d113    	ldr	q19, [x8, #0x740]
100003a08: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003a0c: 4e73d652    	fadd.2d	v18, v18, v19
100003a10: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003a14: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003a18: 4e73d652    	fadd.2d	v18, v18, v19
100003a1c: 3dc20113    	ldr	q19, [x8, #0x800]
100003a20: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003a24: 4e73d652    	fadd.2d	v18, v18, v19
100003a28: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003a2c: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003a30: 3dc14514    	ldr	q20, [x8, #0x510]
100003a34: 4fd19294    	fmul.2d	v20, v20, v17[0]
100003a38: 4e74d673    	fadd.2d	v19, v19, v20
100003a3c: 3dc15d14    	ldr	q20, [x8, #0x570]
100003a40: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003a44: 4e74d673    	fadd.2d	v19, v19, v20
100003a48: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003a4c: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003a50: 4e74d673    	fadd.2d	v19, v19, v20
100003a54: 3dc18d14    	ldr	q20, [x8, #0x630]
100003a58: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003a5c: 4e74d673    	fadd.2d	v19, v19, v20
100003a60: 3dc1a514    	ldr	q20, [x8, #0x690]
100003a64: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003a68: 4e74d673    	fadd.2d	v19, v19, v20
100003a6c: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
100003a70: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003a74: 4e74d673    	fadd.2d	v19, v19, v20
100003a78: 3dc1d514    	ldr	q20, [x8, #0x750]
100003a7c: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003a80: 4e74d673    	fadd.2d	v19, v19, v20
100003a84: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
100003a88: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003a8c: 4e74d673    	fadd.2d	v19, v19, v20
100003a90: 3dc20514    	ldr	q20, [x8, #0x810]
100003a94: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003a98: 4e74d673    	fadd.2d	v19, v19, v20
100003a9c: ad1c4d32    	stp	q18, q19, [x9, #0x380]
100003aa0: 3dc13112    	ldr	q18, [x8, #0x4c0]
100003aa4: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003aa8: 3dc14913    	ldr	q19, [x8, #0x520]
100003aac: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003ab0: 4e73d652    	fadd.2d	v18, v18, v19
100003ab4: 3dc16113    	ldr	q19, [x8, #0x580]
100003ab8: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003abc: 4e73d652    	fadd.2d	v18, v18, v19
100003ac0: 3dc17913    	ldr	q19, [x8, #0x5e0]
100003ac4: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003ac8: 4e73d652    	fadd.2d	v18, v18, v19
100003acc: 3dc19113    	ldr	q19, [x8, #0x640]
100003ad0: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003ad4: 4e73d652    	fadd.2d	v18, v18, v19
100003ad8: 3dc1a913    	ldr	q19, [x8, #0x6a0]
100003adc: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003ae0: 4e73d652    	fadd.2d	v18, v18, v19
100003ae4: 3dc1c113    	ldr	q19, [x8, #0x700]
100003ae8: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003aec: 4e73d652    	fadd.2d	v18, v18, v19
100003af0: 3dc1d913    	ldr	q19, [x8, #0x760]
100003af4: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003af8: 4e73d652    	fadd.2d	v18, v18, v19
100003afc: 3dc1f113    	ldr	q19, [x8, #0x7c0]
100003b00: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003b04: 4e73d652    	fadd.2d	v18, v18, v19
100003b08: 3dc20913    	ldr	q19, [x8, #0x820]
100003b0c: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003b10: 4e73d652    	fadd.2d	v18, v18, v19
100003b14: 3dc13513    	ldr	q19, [x8, #0x4d0]
100003b18: 4fd09270    	fmul.2d	v16, v19, v16[0]
100003b1c: 3dc14d13    	ldr	q19, [x8, #0x530]
100003b20: 4fd19271    	fmul.2d	v17, v19, v17[0]
100003b24: 4e71d610    	fadd.2d	v16, v16, v17
100003b28: 3dc16511    	ldr	q17, [x8, #0x590]
100003b2c: 4fc79227    	fmul.2d	v7, v17, v7[0]
100003b30: 4e67d607    	fadd.2d	v7, v16, v7
100003b34: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100003b38: 4fc69206    	fmul.2d	v6, v16, v6[0]
100003b3c: 4e66d4e6    	fadd.2d	v6, v7, v6
100003b40: 3dc19507    	ldr	q7, [x8, #0x650]
100003b44: 4fc590e5    	fmul.2d	v5, v7, v5[0]
100003b48: 4e65d4c5    	fadd.2d	v5, v6, v5
100003b4c: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
100003b50: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100003b54: 4e64d4a4    	fadd.2d	v4, v5, v4
100003b58: 3dc1c505    	ldr	q5, [x8, #0x710]
100003b5c: 4fc390a3    	fmul.2d	v3, v5, v3[0]
100003b60: 3dc1dd05    	ldr	q5, [x8, #0x770]
100003b64: 4e63d483    	fadd.2d	v3, v4, v3
100003b68: 4fc290a2    	fmul.2d	v2, v5, v2[0]
100003b6c: 3dc1f504    	ldr	q4, [x8, #0x7d0]
100003b70: 4e62d462    	fadd.2d	v2, v3, v2
100003b74: 3dc20d03    	ldr	q3, [x8, #0x830]
100003b78: 4fc09080    	fmul.2d	v0, v4, v0[0]
100003b7c: 4e60d440    	fadd.2d	v0, v2, v0
100003b80: 4fc19061    	fmul.2d	v1, v3, v1[0]
100003b84: 4e61d400    	fadd.2d	v0, v0, v1
100003b88: ad1d0132    	stp	q18, q0, [x9, #0x3a0]
100003b8c: fd41e110    	ldr	d16, [x8, #0x3c0]
100003b90: fd41e511    	ldr	d17, [x8, #0x3c8]
100003b94: fd41e907    	ldr	d7, [x8, #0x3d0]
100003b98: fd41ed06    	ldr	d6, [x8, #0x3d8]
100003b9c: fd41f105    	ldr	d5, [x8, #0x3e0]
100003ba0: fd41f504    	ldr	d4, [x8, #0x3e8]
100003ba4: fd41f903    	ldr	d3, [x8, #0x3f0]
100003ba8: fd41fd02    	ldr	d2, [x8, #0x3f8]
100003bac: fd420101    	ldr	d1, [x8, #0x400]
100003bb0: fd420500    	ldr	d0, [x8, #0x408]
100003bb4: 3dc12112    	ldr	q18, [x8, #0x480]
100003bb8: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003bbc: 3dc13913    	ldr	q19, [x8, #0x4e0]
100003bc0: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003bc4: 4e73d652    	fadd.2d	v18, v18, v19
100003bc8: 3dc15113    	ldr	q19, [x8, #0x540]
100003bcc: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003bd0: 4e73d652    	fadd.2d	v18, v18, v19
100003bd4: 3dc16913    	ldr	q19, [x8, #0x5a0]
100003bd8: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003bdc: 4e73d652    	fadd.2d	v18, v18, v19
100003be0: 3dc18113    	ldr	q19, [x8, #0x600]
100003be4: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003be8: 4e73d652    	fadd.2d	v18, v18, v19
100003bec: 3dc19913    	ldr	q19, [x8, #0x660]
100003bf0: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003bf4: 4e73d652    	fadd.2d	v18, v18, v19
100003bf8: 3dc1b113    	ldr	q19, [x8, #0x6c0]
100003bfc: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003c00: 4e73d652    	fadd.2d	v18, v18, v19
100003c04: 3dc1c913    	ldr	q19, [x8, #0x720]
100003c08: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003c0c: 4e73d652    	fadd.2d	v18, v18, v19
100003c10: 3dc1e113    	ldr	q19, [x8, #0x780]
100003c14: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003c18: 4e73d652    	fadd.2d	v18, v18, v19
100003c1c: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003c20: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003c24: 4e73d652    	fadd.2d	v18, v18, v19
100003c28: 3dc12513    	ldr	q19, [x8, #0x490]
100003c2c: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003c30: 3dc13d14    	ldr	q20, [x8, #0x4f0]
100003c34: 4fd19294    	fmul.2d	v20, v20, v17[0]
100003c38: 4e74d673    	fadd.2d	v19, v19, v20
100003c3c: 3dc15514    	ldr	q20, [x8, #0x550]
100003c40: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003c44: 4e74d673    	fadd.2d	v19, v19, v20
100003c48: 3dc16d14    	ldr	q20, [x8, #0x5b0]
100003c4c: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003c50: 4e74d673    	fadd.2d	v19, v19, v20
100003c54: 3dc18514    	ldr	q20, [x8, #0x610]
100003c58: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003c5c: 4e74d673    	fadd.2d	v19, v19, v20
100003c60: 3dc19d14    	ldr	q20, [x8, #0x670]
100003c64: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003c68: 4e74d673    	fadd.2d	v19, v19, v20
100003c6c: 3dc1b514    	ldr	q20, [x8, #0x6d0]
100003c70: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003c74: 4e74d673    	fadd.2d	v19, v19, v20
100003c78: 3dc1cd14    	ldr	q20, [x8, #0x730]
100003c7c: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003c80: 4e74d673    	fadd.2d	v19, v19, v20
100003c84: 3dc1e514    	ldr	q20, [x8, #0x790]
100003c88: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003c8c: 4e74d673    	fadd.2d	v19, v19, v20
100003c90: 3dc1fd14    	ldr	q20, [x8, #0x7f0]
100003c94: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003c98: 4e74d673    	fadd.2d	v19, v19, v20
100003c9c: ad1e4d32    	stp	q18, q19, [x9, #0x3c0]
100003ca0: 3dc12912    	ldr	q18, [x8, #0x4a0]
100003ca4: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003ca8: 3dc14113    	ldr	q19, [x8, #0x500]
100003cac: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003cb0: 4e73d652    	fadd.2d	v18, v18, v19
100003cb4: 3dc15913    	ldr	q19, [x8, #0x560]
100003cb8: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003cbc: 4e73d652    	fadd.2d	v18, v18, v19
100003cc0: 3dc17113    	ldr	q19, [x8, #0x5c0]
100003cc4: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003cc8: 4e73d652    	fadd.2d	v18, v18, v19
100003ccc: 3dc18913    	ldr	q19, [x8, #0x620]
100003cd0: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003cd4: 4e73d652    	fadd.2d	v18, v18, v19
100003cd8: 3dc1a113    	ldr	q19, [x8, #0x680]
100003cdc: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003ce0: 4e73d652    	fadd.2d	v18, v18, v19
100003ce4: 3dc1b913    	ldr	q19, [x8, #0x6e0]
100003ce8: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003cec: 4e73d652    	fadd.2d	v18, v18, v19
100003cf0: 3dc1d113    	ldr	q19, [x8, #0x740]
100003cf4: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003cf8: 4e73d652    	fadd.2d	v18, v18, v19
100003cfc: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003d00: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003d04: 4e73d652    	fadd.2d	v18, v18, v19
100003d08: 3dc20113    	ldr	q19, [x8, #0x800]
100003d0c: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003d10: 4e73d652    	fadd.2d	v18, v18, v19
100003d14: 3dc12d13    	ldr	q19, [x8, #0x4b0]
100003d18: 4fd09273    	fmul.2d	v19, v19, v16[0]
100003d1c: 3dc14514    	ldr	q20, [x8, #0x510]
100003d20: 4fd19294    	fmul.2d	v20, v20, v17[0]
100003d24: 4e74d673    	fadd.2d	v19, v19, v20
100003d28: 3dc15d14    	ldr	q20, [x8, #0x570]
100003d2c: 4fc79294    	fmul.2d	v20, v20, v7[0]
100003d30: 4e74d673    	fadd.2d	v19, v19, v20
100003d34: 3dc17514    	ldr	q20, [x8, #0x5d0]
100003d38: 4fc69294    	fmul.2d	v20, v20, v6[0]
100003d3c: 4e74d673    	fadd.2d	v19, v19, v20
100003d40: 3dc18d14    	ldr	q20, [x8, #0x630]
100003d44: 4fc59294    	fmul.2d	v20, v20, v5[0]
100003d48: 4e74d673    	fadd.2d	v19, v19, v20
100003d4c: 3dc1a514    	ldr	q20, [x8, #0x690]
100003d50: 4fc49294    	fmul.2d	v20, v20, v4[0]
100003d54: 4e74d673    	fadd.2d	v19, v19, v20
100003d58: 3dc1bd14    	ldr	q20, [x8, #0x6f0]
100003d5c: 4fc39294    	fmul.2d	v20, v20, v3[0]
100003d60: 4e74d673    	fadd.2d	v19, v19, v20
100003d64: 3dc1d514    	ldr	q20, [x8, #0x750]
100003d68: 4fc29294    	fmul.2d	v20, v20, v2[0]
100003d6c: 4e74d673    	fadd.2d	v19, v19, v20
100003d70: 3dc1ed14    	ldr	q20, [x8, #0x7b0]
100003d74: 4fc19294    	fmul.2d	v20, v20, v1[0]
100003d78: 4e74d673    	fadd.2d	v19, v19, v20
100003d7c: 3dc20514    	ldr	q20, [x8, #0x810]
100003d80: 4fc09294    	fmul.2d	v20, v20, v0[0]
100003d84: 4e74d673    	fadd.2d	v19, v19, v20
100003d88: ad1f4d32    	stp	q18, q19, [x9, #0x3e0]
100003d8c: 3dc13112    	ldr	q18, [x8, #0x4c0]
100003d90: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003d94: 3dc14913    	ldr	q19, [x8, #0x520]
100003d98: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003d9c: 4e73d652    	fadd.2d	v18, v18, v19
100003da0: 3dc16113    	ldr	q19, [x8, #0x580]
100003da4: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003da8: 4e73d652    	fadd.2d	v18, v18, v19
100003dac: 3dc17913    	ldr	q19, [x8, #0x5e0]
100003db0: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003db4: 4e73d652    	fadd.2d	v18, v18, v19
100003db8: 3dc19113    	ldr	q19, [x8, #0x640]
100003dbc: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003dc0: 4e73d652    	fadd.2d	v18, v18, v19
100003dc4: 3dc1a913    	ldr	q19, [x8, #0x6a0]
100003dc8: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003dcc: 4e73d652    	fadd.2d	v18, v18, v19
100003dd0: 3dc1c113    	ldr	q19, [x8, #0x700]
100003dd4: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003dd8: 4e73d652    	fadd.2d	v18, v18, v19
100003ddc: 3dc1d913    	ldr	q19, [x8, #0x760]
100003de0: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003de4: 4e73d652    	fadd.2d	v18, v18, v19
100003de8: 3dc1f113    	ldr	q19, [x8, #0x7c0]
100003dec: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003df0: 4e73d652    	fadd.2d	v18, v18, v19
100003df4: 3dc20913    	ldr	q19, [x8, #0x820]
100003df8: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003dfc: 4e73d652    	fadd.2d	v18, v18, v19
100003e00: 3d810132    	str	q18, [x9, #0x400]
100003e04: 3dc13512    	ldr	q18, [x8, #0x4d0]
100003e08: 4fd09250    	fmul.2d	v16, v18, v16[0]
100003e0c: 3dc14d12    	ldr	q18, [x8, #0x530]
100003e10: 4fd19251    	fmul.2d	v17, v18, v17[0]
100003e14: 4e71d610    	fadd.2d	v16, v16, v17
100003e18: 3dc16511    	ldr	q17, [x8, #0x590]
100003e1c: 4fc79227    	fmul.2d	v7, v17, v7[0]
100003e20: 4e67d607    	fadd.2d	v7, v16, v7
100003e24: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100003e28: 4fc69206    	fmul.2d	v6, v16, v6[0]
100003e2c: 4e66d4e6    	fadd.2d	v6, v7, v6
100003e30: 3dc19507    	ldr	q7, [x8, #0x650]
100003e34: 4fc590e5    	fmul.2d	v5, v7, v5[0]
100003e38: 4e65d4c5    	fadd.2d	v5, v6, v5
100003e3c: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
100003e40: 4fc490c4    	fmul.2d	v4, v6, v4[0]
100003e44: 4e64d4a4    	fadd.2d	v4, v5, v4
100003e48: 3dc1c505    	ldr	q5, [x8, #0x710]
100003e4c: 4fc390a3    	fmul.2d	v3, v5, v3[0]
100003e50: 4e63d483    	fadd.2d	v3, v4, v3
100003e54: 3dc1dd04    	ldr	q4, [x8, #0x770]
100003e58: 4fc29082    	fmul.2d	v2, v4, v2[0]
100003e5c: 4e62d462    	fadd.2d	v2, v3, v2
100003e60: 3dc1f503    	ldr	q3, [x8, #0x7d0]
100003e64: 4fc19061    	fmul.2d	v1, v3, v1[0]
100003e68: 4e61d441    	fadd.2d	v1, v2, v1
100003e6c: 3dc20d02    	ldr	q2, [x8, #0x830]
100003e70: 4fc09040    	fmul.2d	v0, v2, v0[0]
100003e74: 4e60d420    	fadd.2d	v0, v1, v0
100003e78: 3d810520    	str	q0, [x9, #0x410]
100003e7c: fd421110    	ldr	d16, [x8, #0x420]
100003e80: fd421511    	ldr	d17, [x8, #0x428]
100003e84: fd421907    	ldr	d7, [x8, #0x430]
100003e88: fd421d06    	ldr	d6, [x8, #0x438]
100003e8c: fd422105    	ldr	d5, [x8, #0x440]
100003e90: fd422504    	ldr	d4, [x8, #0x448]
100003e94: fd422903    	ldr	d3, [x8, #0x450]
100003e98: fd422d02    	ldr	d2, [x8, #0x458]
100003e9c: fd423101    	ldr	d1, [x8, #0x460]
100003ea0: fd423500    	ldr	d0, [x8, #0x468]
100003ea4: 3dc12112    	ldr	q18, [x8, #0x480]
100003ea8: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003eac: 3dc13913    	ldr	q19, [x8, #0x4e0]
100003eb0: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003eb4: 4e73d652    	fadd.2d	v18, v18, v19
100003eb8: 3dc15113    	ldr	q19, [x8, #0x540]
100003ebc: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003ec0: 4e73d652    	fadd.2d	v18, v18, v19
100003ec4: 3dc16913    	ldr	q19, [x8, #0x5a0]
100003ec8: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003ecc: 4e73d652    	fadd.2d	v18, v18, v19
100003ed0: 3dc18113    	ldr	q19, [x8, #0x600]
100003ed4: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003ed8: 4e73d652    	fadd.2d	v18, v18, v19
100003edc: 3dc19913    	ldr	q19, [x8, #0x660]
100003ee0: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003ee4: 4e73d652    	fadd.2d	v18, v18, v19
100003ee8: 3dc1b113    	ldr	q19, [x8, #0x6c0]
100003eec: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003ef0: 4e73d652    	fadd.2d	v18, v18, v19
100003ef4: 3dc1c913    	ldr	q19, [x8, #0x720]
100003ef8: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003efc: 4e73d652    	fadd.2d	v18, v18, v19
100003f00: 3dc1e113    	ldr	q19, [x8, #0x780]
100003f04: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003f08: 4e73d652    	fadd.2d	v18, v18, v19
100003f0c: 3dc1f913    	ldr	q19, [x8, #0x7e0]
100003f10: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003f14: 4e73d652    	fadd.2d	v18, v18, v19
100003f18: 3d810932    	str	q18, [x9, #0x420]
100003f1c: 3dc12512    	ldr	q18, [x8, #0x490]
100003f20: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003f24: 3dc13d13    	ldr	q19, [x8, #0x4f0]
100003f28: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003f2c: 4e73d652    	fadd.2d	v18, v18, v19
100003f30: 3dc15513    	ldr	q19, [x8, #0x550]
100003f34: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003f38: 4e73d652    	fadd.2d	v18, v18, v19
100003f3c: 3dc16d13    	ldr	q19, [x8, #0x5b0]
100003f40: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003f44: 4e73d652    	fadd.2d	v18, v18, v19
100003f48: 3dc18513    	ldr	q19, [x8, #0x610]
100003f4c: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003f50: 4e73d652    	fadd.2d	v18, v18, v19
100003f54: 3dc19d13    	ldr	q19, [x8, #0x670]
100003f58: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003f5c: 4e73d652    	fadd.2d	v18, v18, v19
100003f60: 3dc1b513    	ldr	q19, [x8, #0x6d0]
100003f64: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003f68: 4e73d652    	fadd.2d	v18, v18, v19
100003f6c: 3dc1cd13    	ldr	q19, [x8, #0x730]
100003f70: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003f74: 4e73d652    	fadd.2d	v18, v18, v19
100003f78: 3dc1e513    	ldr	q19, [x8, #0x790]
100003f7c: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003f80: 4e73d652    	fadd.2d	v18, v18, v19
100003f84: 3dc1fd13    	ldr	q19, [x8, #0x7f0]
100003f88: 4fc09273    	fmul.2d	v19, v19, v0[0]
100003f8c: 4e73d652    	fadd.2d	v18, v18, v19
100003f90: 3d810d32    	str	q18, [x9, #0x430]
100003f94: 3dc12912    	ldr	q18, [x8, #0x4a0]
100003f98: 4fd09252    	fmul.2d	v18, v18, v16[0]
100003f9c: 3dc14113    	ldr	q19, [x8, #0x500]
100003fa0: 4fd19273    	fmul.2d	v19, v19, v17[0]
100003fa4: 4e73d652    	fadd.2d	v18, v18, v19
100003fa8: 3dc15913    	ldr	q19, [x8, #0x560]
100003fac: 4fc79273    	fmul.2d	v19, v19, v7[0]
100003fb0: 4e73d652    	fadd.2d	v18, v18, v19
100003fb4: 3dc17113    	ldr	q19, [x8, #0x5c0]
100003fb8: 4fc69273    	fmul.2d	v19, v19, v6[0]
100003fbc: 4e73d652    	fadd.2d	v18, v18, v19
100003fc0: 3dc18913    	ldr	q19, [x8, #0x620]
100003fc4: 4fc59273    	fmul.2d	v19, v19, v5[0]
100003fc8: 4e73d652    	fadd.2d	v18, v18, v19
100003fcc: 3dc1a113    	ldr	q19, [x8, #0x680]
100003fd0: 4fc49273    	fmul.2d	v19, v19, v4[0]
100003fd4: 4e73d652    	fadd.2d	v18, v18, v19
100003fd8: 3dc1b913    	ldr	q19, [x8, #0x6e0]
100003fdc: 4fc39273    	fmul.2d	v19, v19, v3[0]
100003fe0: 4e73d652    	fadd.2d	v18, v18, v19
100003fe4: 3dc1d113    	ldr	q19, [x8, #0x740]
100003fe8: 4fc29273    	fmul.2d	v19, v19, v2[0]
100003fec: 4e73d652    	fadd.2d	v18, v18, v19
100003ff0: 3dc1e913    	ldr	q19, [x8, #0x7a0]
100003ff4: 4fc19273    	fmul.2d	v19, v19, v1[0]
100003ff8: 4e73d652    	fadd.2d	v18, v18, v19
100003ffc: 3dc20113    	ldr	q19, [x8, #0x800]
100004000: 4fc09273    	fmul.2d	v19, v19, v0[0]
100004004: 4e73d652    	fadd.2d	v18, v18, v19
100004008: 3d811132    	str	q18, [x9, #0x440]
10000400c: 3dc12d12    	ldr	q18, [x8, #0x4b0]
100004010: 4fd09252    	fmul.2d	v18, v18, v16[0]
100004014: 3dc14513    	ldr	q19, [x8, #0x510]
100004018: 4fd19273    	fmul.2d	v19, v19, v17[0]
10000401c: 4e73d652    	fadd.2d	v18, v18, v19
100004020: 3dc15d13    	ldr	q19, [x8, #0x570]
100004024: 4fc79273    	fmul.2d	v19, v19, v7[0]
100004028: 4e73d652    	fadd.2d	v18, v18, v19
10000402c: 3dc17513    	ldr	q19, [x8, #0x5d0]
100004030: 4fc69273    	fmul.2d	v19, v19, v6[0]
100004034: 4e73d652    	fadd.2d	v18, v18, v19
100004038: 3dc18d13    	ldr	q19, [x8, #0x630]
10000403c: 4fc59273    	fmul.2d	v19, v19, v5[0]
100004040: 4e73d652    	fadd.2d	v18, v18, v19
100004044: 3dc1a513    	ldr	q19, [x8, #0x690]
100004048: 4fc49273    	fmul.2d	v19, v19, v4[0]
10000404c: 4e73d652    	fadd.2d	v18, v18, v19
100004050: 3dc1bd13    	ldr	q19, [x8, #0x6f0]
100004054: 4fc39273    	fmul.2d	v19, v19, v3[0]
100004058: 4e73d652    	fadd.2d	v18, v18, v19
10000405c: 3dc1d513    	ldr	q19, [x8, #0x750]
100004060: 4fc29273    	fmul.2d	v19, v19, v2[0]
100004064: 4e73d652    	fadd.2d	v18, v18, v19
100004068: 3dc1ed13    	ldr	q19, [x8, #0x7b0]
10000406c: 4fc19273    	fmul.2d	v19, v19, v1[0]
100004070: 4e73d652    	fadd.2d	v18, v18, v19
100004074: 3dc20513    	ldr	q19, [x8, #0x810]
100004078: 4fc09273    	fmul.2d	v19, v19, v0[0]
10000407c: 4e73d652    	fadd.2d	v18, v18, v19
100004080: 3d811532    	str	q18, [x9, #0x450]
100004084: 3dc13112    	ldr	q18, [x8, #0x4c0]
100004088: 4fd09252    	fmul.2d	v18, v18, v16[0]
10000408c: 3dc14913    	ldr	q19, [x8, #0x520]
100004090: 4fd19273    	fmul.2d	v19, v19, v17[0]
100004094: 4e73d652    	fadd.2d	v18, v18, v19
100004098: 3dc16113    	ldr	q19, [x8, #0x580]
10000409c: 4fc79273    	fmul.2d	v19, v19, v7[0]
1000040a0: 4e73d652    	fadd.2d	v18, v18, v19
1000040a4: 3dc17913    	ldr	q19, [x8, #0x5e0]
1000040a8: 4fc69273    	fmul.2d	v19, v19, v6[0]
1000040ac: 4e73d652    	fadd.2d	v18, v18, v19
1000040b0: 3dc19113    	ldr	q19, [x8, #0x640]
1000040b4: 4fc59273    	fmul.2d	v19, v19, v5[0]
1000040b8: 4e73d652    	fadd.2d	v18, v18, v19
1000040bc: 3dc1a913    	ldr	q19, [x8, #0x6a0]
1000040c0: 4fc49273    	fmul.2d	v19, v19, v4[0]
1000040c4: 4e73d652    	fadd.2d	v18, v18, v19
1000040c8: 3dc1c113    	ldr	q19, [x8, #0x700]
1000040cc: 4fc39273    	fmul.2d	v19, v19, v3[0]
1000040d0: 4e73d652    	fadd.2d	v18, v18, v19
1000040d4: 3dc1d913    	ldr	q19, [x8, #0x760]
1000040d8: 4fc29273    	fmul.2d	v19, v19, v2[0]
1000040dc: 4e73d652    	fadd.2d	v18, v18, v19
1000040e0: 3dc1f113    	ldr	q19, [x8, #0x7c0]
1000040e4: 4fc19273    	fmul.2d	v19, v19, v1[0]
1000040e8: 4e73d652    	fadd.2d	v18, v18, v19
1000040ec: 3dc20913    	ldr	q19, [x8, #0x820]
1000040f0: 4fc09273    	fmul.2d	v19, v19, v0[0]
1000040f4: 4e73d652    	fadd.2d	v18, v18, v19
1000040f8: 3d811932    	str	q18, [x9, #0x460]
1000040fc: 3dc13512    	ldr	q18, [x8, #0x4d0]
100004100: 4fd09250    	fmul.2d	v16, v18, v16[0]
100004104: 3dc14d12    	ldr	q18, [x8, #0x530]
100004108: 4fd19251    	fmul.2d	v17, v18, v17[0]
10000410c: 4e71d610    	fadd.2d	v16, v16, v17
100004110: 3dc16511    	ldr	q17, [x8, #0x590]
100004114: 4fc79227    	fmul.2d	v7, v17, v7[0]
100004118: 4e67d607    	fadd.2d	v7, v16, v7
10000411c: 3dc17d10    	ldr	q16, [x8, #0x5f0]
100004120: 4fc69206    	fmul.2d	v6, v16, v6[0]
100004124: 4e66d4e6    	fadd.2d	v6, v7, v6
100004128: 3dc19507    	ldr	q7, [x8, #0x650]
10000412c: 4fc590e5    	fmul.2d	v5, v7, v5[0]
100004130: 4e65d4c5    	fadd.2d	v5, v6, v5
100004134: 3dc1ad06    	ldr	q6, [x8, #0x6b0]
100004138: 4fc490c4    	fmul.2d	v4, v6, v4[0]
10000413c: 4e64d4a4    	fadd.2d	v4, v5, v4
100004140: 3dc1c505    	ldr	q5, [x8, #0x710]
100004144: 4fc390a3    	fmul.2d	v3, v5, v3[0]
100004148: 4e63d483    	fadd.2d	v3, v4, v3
10000414c: 3dc1dd04    	ldr	q4, [x8, #0x770]
100004150: 4fc29082    	fmul.2d	v2, v4, v2[0]
100004154: 4e62d462    	fadd.2d	v2, v3, v2
100004158: 3dc1f503    	ldr	q3, [x8, #0x7d0]
10000415c: 4fc19061    	fmul.2d	v1, v3, v1[0]
100004160: 4e61d441    	fadd.2d	v1, v2, v1
100004164: 3dc20d02    	ldr	q2, [x8, #0x830]
100004168: 4fc09040    	fmul.2d	v0, v2, v0[0]
10000416c: 4e60d420    	fadd.2d	v0, v1, v0
100004170: 3d811d20    	str	q0, [x9, #0x470]
100004174: 910f03ff    	add	sp, sp, #0x3c0
100004178: a9457bfd    	ldp	x29, x30, [sp, #0x50]
10000417c: a9446ffc    	ldp	x28, x27, [sp, #0x40]
100004180: 6d4323e9    	ldp	d9, d8, [sp, #0x30]
100004184: 6d422beb    	ldp	d11, d10, [sp, #0x20]
100004188: 6d4133ed    	ldp	d13, d12, [sp, #0x10]
10000418c: 6cc63bef    	ldp	d15, d14, [sp], #0x60
100004190: d65f03c0    	ret

0000000100004194 <_codegen_smul_add_semul3_12>:
100004194: a9be6ffc    	stp	x28, x27, [sp, #-0x20]!
100004198: a9017bfd    	stp	x29, x30, [sp, #0x10]
10000419c: 910043fd    	add	x29, sp, #0x10
1000041a0: d11203ff    	sub	sp, sp, #0x480
1000041a4: 900000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000041a8: 9119c108    	add	x8, x8, #0x670
1000041ac: fd400100    	ldr	d0, [x8]
1000041b0: fd403501    	ldr	d1, [x8, #0x68]
1000041b4: 1e612800    	fadd	d0, d0, d1
1000041b8: fd406901    	ldr	d1, [x8, #0xd0]
1000041bc: 1e612800    	fadd	d0, d0, d1
1000041c0: fd409d01    	ldr	d1, [x8, #0x138]
1000041c4: 1e612800    	fadd	d0, d0, d1
1000041c8: fd40d101    	ldr	d1, [x8, #0x1a0]
1000041cc: 1e612800    	fadd	d0, d0, d1
1000041d0: fd410501    	ldr	d1, [x8, #0x208]
1000041d4: 1e612800    	fadd	d0, d0, d1
1000041d8: fd413901    	ldr	d1, [x8, #0x270]
1000041dc: 1e612800    	fadd	d0, d0, d1
1000041e0: fd416d01    	ldr	d1, [x8, #0x2d8]
1000041e4: 1e612800    	fadd	d0, d0, d1
1000041e8: fd41a101    	ldr	d1, [x8, #0x340]
1000041ec: 1e612800    	fadd	d0, d0, d1
1000041f0: fd41d501    	ldr	d1, [x8, #0x3a8]
1000041f4: 1e612800    	fadd	d0, d0, d1
1000041f8: fd448101    	ldr	d1, [x8, #0x900]
1000041fc: fd44b502    	ldr	d2, [x8, #0x968]
100004200: 1e622821    	fadd	d1, d1, d2
100004204: fd44e902    	ldr	d2, [x8, #0x9d0]
100004208: 1e622821    	fadd	d1, d1, d2
10000420c: fd451d02    	ldr	d2, [x8, #0xa38]
100004210: 1e622821    	fadd	d1, d1, d2
100004214: fd455102    	ldr	d2, [x8, #0xaa0]
100004218: 1e622821    	fadd	d1, d1, d2
10000421c: fd458502    	ldr	d2, [x8, #0xb08]
100004220: 1e622821    	fadd	d1, d1, d2
100004224: fd45b902    	ldr	d2, [x8, #0xb70]
100004228: 1e622821    	fadd	d1, d1, d2
10000422c: fd45ed02    	ldr	d2, [x8, #0xbd8]
100004230: 1e622821    	fadd	d1, d1, d2
100004234: fd462102    	ldr	d2, [x8, #0xc40]
100004238: 1e622821    	fadd	d1, d1, d2
10000423c: fd465502    	ldr	d2, [x8, #0xca8]
100004240: 1e622821    	fadd	d1, d1, d2
100004244: 910003e0    	mov	x0, sp
100004248: 94001640    	bl	0x100009b48 <_bench_primitives.smulAddSemul3_12KnownTraces>
10000424c: 900000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
100004250: 9106c000    	add	x0, x0, #0x1b0
100004254: 910003e1    	mov	x1, sp
100004258: 52809002    	mov	w2, #0x480              ; =1152
10000425c: 94002cd7    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
100004260: 911203ff    	add	sp, sp, #0x480
100004264: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100004268: a8c26ffc    	ldp	x28, x27, [sp], #0x20
10000426c: d65f03c0    	ret

0000000100004270 <_codegen_smul_add_semul3_known_right_trace_12>:
100004270: a9be6ffc    	stp	x28, x27, [sp, #-0x20]!
100004274: a9017bfd    	stp	x29, x30, [sp, #0x10]
100004278: 910043fd    	add	x29, sp, #0x10
10000427c: d11203ff    	sub	sp, sp, #0x480
100004280: 900000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100004284: 9118c108    	add	x8, x8, #0x630
100004288: fd400101    	ldr	d1, [x8]
10000428c: fd402100    	ldr	d0, [x8, #0x40]
100004290: fd405502    	ldr	d2, [x8, #0xa8]
100004294: 1e622800    	fadd	d0, d0, d2
100004298: fd408902    	ldr	d2, [x8, #0x110]
10000429c: 1e622800    	fadd	d0, d0, d2
1000042a0: fd40bd02    	ldr	d2, [x8, #0x178]
1000042a4: 1e622800    	fadd	d0, d0, d2
1000042a8: fd40f102    	ldr	d2, [x8, #0x1e0]
1000042ac: 1e622800    	fadd	d0, d0, d2
1000042b0: fd412502    	ldr	d2, [x8, #0x248]
1000042b4: 1e622800    	fadd	d0, d0, d2
1000042b8: fd415902    	ldr	d2, [x8, #0x2b0]
1000042bc: 1e622800    	fadd	d0, d0, d2
1000042c0: fd418d02    	ldr	d2, [x8, #0x318]
1000042c4: 1e622800    	fadd	d0, d0, d2
1000042c8: fd41c102    	ldr	d2, [x8, #0x380]
1000042cc: 1e622800    	fadd	d0, d0, d2
1000042d0: fd41f502    	ldr	d2, [x8, #0x3e8]
1000042d4: 1e622800    	fadd	d0, d0, d2
1000042d8: 910003e0    	mov	x0, sp
1000042dc: 9400161b    	bl	0x100009b48 <_bench_primitives.smulAddSemul3_12KnownTraces>
1000042e0: 900000c0    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000042e4: 9106c000    	add	x0, x0, #0x1b0
1000042e8: 910003e1    	mov	x1, sp
1000042ec: 52809002    	mov	w2, #0x480              ; =1152
1000042f0: 94002cb2    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
1000042f4: 911203ff    	add	sp, sp, #0x480
1000042f8: a9417bfd    	ldp	x29, x30, [sp, #0x10]
1000042fc: a8c26ffc    	ldp	x28, x27, [sp], #0x20
100004300: d65f03c0    	ret

0000000100004304 <_codegen_qseries_nonzero_12x10>:
100004304: 6dba3bef    	stp	d15, d14, [sp, #-0x60]!
100004308: 6d0133ed    	stp	d13, d12, [sp, #0x10]
10000430c: 6d022beb    	stp	d11, d10, [sp, #0x20]
100004310: 6d0323e9    	stp	d9, d8, [sp, #0x30]
100004314: a9044ff4    	stp	x20, x19, [sp, #0x40]
100004318: a9057bfd    	stp	x29, x30, [sp, #0x50]
10000431c: 910143fd    	add	x29, sp, #0x50
100004320: d14007ff    	sub	sp, sp, #0x1, lsl #12   ; =0x1000
100004324: d10903ff    	sub	sp, sp, #0x240
100004328: 900000c8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000432c: 9119c108    	add	x8, x8, #0x670
100004330: 6d401100    	ldp	d0, d4, [x8]
100004334: 3d8287e0    	str	q0, [sp, #0xa10]
100004338: 3d82c3e4    	str	q4, [sp, #0xb00]
10000433c: 3dc12103    	ldr	q3, [x8, #0x480]
100004340: 4fc09060    	fmul.2d	v0, v3, v0[0]
100004344: 3d8207e3    	str	q3, [sp, #0x810]
100004348: 3dc13902    	ldr	q2, [x8, #0x4e0]
10000434c: 4fc49041    	fmul.2d	v1, v2, v4[0]
100004350: 4ea21c44    	mov.16b	v4, v2
100004354: 3d8203e2    	str	q2, [sp, #0x800]
100004358: 4e61d400    	fadd.2d	v0, v0, v1
10000435c: 6d411501    	ldp	d1, d5, [x8, #0x10]
100004360: 3d828be1    	str	q1, [sp, #0xa20]
100004364: 3d82b7e5    	str	q5, [sp, #0xad0]
100004368: 3dc15106    	ldr	q6, [x8, #0x540]
10000436c: 4fc190c1    	fmul.2d	v1, v6, v1[0]
100004370: 3d81fbe6    	str	q6, [sp, #0x7e0]
100004374: 4e61d400    	fadd.2d	v0, v0, v1
100004378: 3dc16907    	ldr	q7, [x8, #0x5a0]
10000437c: 4fc590e1    	fmul.2d	v1, v7, v5[0]
100004380: 3d81ffe7    	str	q7, [sp, #0x7f0]
100004384: 4e61d400    	fadd.2d	v0, v0, v1
100004388: 6d421501    	ldp	d1, d5, [x8, #0x20]
10000438c: 3d81afe1    	str	q1, [sp, #0x6b0]
100004390: 3d8283e5    	str	q5, [sp, #0xa00]
100004394: 3dc18110    	ldr	q16, [x8, #0x600]
100004398: 4fc19201    	fmul.2d	v1, v16, v1[0]
10000439c: 3d826ff0    	str	q16, [sp, #0x9b0]
1000043a0: 4e61d400    	fadd.2d	v0, v0, v1
1000043a4: 3dc19902    	ldr	q2, [x8, #0x660]
1000043a8: 4fc59041    	fmul.2d	v1, v2, v5[0]
1000043ac: 4ea21c45    	mov.16b	v5, v2
1000043b0: 3d8273e2    	str	q2, [sp, #0x9c0]
1000043b4: 4e61d400    	fadd.2d	v0, v0, v1
1000043b8: 6d434501    	ldp	d1, d17, [x8, #0x30]
1000043bc: 3d827fe1    	str	q1, [sp, #0x9f0]
1000043c0: 3d820bf1    	str	q17, [sp, #0x820]
1000043c4: 3dc1b113    	ldr	q19, [x8, #0x6c0]
1000043c8: 4fc19261    	fmul.2d	v1, v19, v1[0]
1000043cc: 3d82b3f3    	str	q19, [sp, #0xac0]
1000043d0: 4e61d400    	fadd.2d	v0, v0, v1
1000043d4: 3dc1c902    	ldr	q2, [x8, #0x720]
1000043d8: 4fd19041    	fmul.2d	v1, v2, v17[0]
1000043dc: 4ea21c51    	mov.16b	v17, v2
1000043e0: 3d81f7e2    	str	q2, [sp, #0x7d0]
1000043e4: 4e61d400    	fadd.2d	v0, v0, v1
1000043e8: 6d445101    	ldp	d1, d20, [x8, #0x40]
1000043ec: 3d81cfe1    	str	q1, [sp, #0x730]
1000043f0: 3d81b3f4    	str	q20, [sp, #0x6c0]
1000043f4: 3dc1e112    	ldr	q18, [x8, #0x780]
1000043f8: 4fc19241    	fmul.2d	v1, v18, v1[0]
1000043fc: 3d826bf2    	str	q18, [sp, #0x9a0]
100004400: 4e61d400    	fadd.2d	v0, v0, v1
100004404: 3dc1f902    	ldr	q2, [x8, #0x7e0]
100004408: 4fd49041    	fmul.2d	v1, v2, v20[0]
10000440c: 3d81f3e2    	str	q2, [sp, #0x7c0]
100004410: 4e61d400    	fadd.2d	v0, v0, v1
100004414: 3d81d3e0    	str	q0, [sp, #0x740]
100004418: 6d460500    	ldp	d0, d1, [x8, #0x60]
10000441c: 3d81c3e0    	str	q0, [sp, #0x700]
100004420: 3d81bfe1    	str	q1, [sp, #0x6f0]
100004424: 4fc09060    	fmul.2d	v0, v3, v0[0]
100004428: 4fc19081    	fmul.2d	v1, v4, v1[0]
10000442c: 4e61d400    	fadd.2d	v0, v0, v1
100004430: 6d470d01    	ldp	d1, d3, [x8, #0x70]
100004434: 3d81a3e1    	str	q1, [sp, #0x680]
100004438: 3d81a7e3    	str	q3, [sp, #0x690]
10000443c: 4fc190c1    	fmul.2d	v1, v6, v1[0]
100004440: 4e61d400    	fadd.2d	v0, v0, v1
100004444: 4fc390e1    	fmul.2d	v1, v7, v3[0]
100004448: 4e61d400    	fadd.2d	v0, v0, v1
10000444c: 6d480d01    	ldp	d1, d3, [x8, #0x80]
100004450: 3d819be1    	str	q1, [sp, #0x660]
100004454: 3d819fe3    	str	q3, [sp, #0x670]
100004458: 4fc19201    	fmul.2d	v1, v16, v1[0]
10000445c: 4e61d400    	fadd.2d	v0, v0, v1
100004460: 4fc390a1    	fmul.2d	v1, v5, v3[0]
100004464: 4e61d400    	fadd.2d	v0, v0, v1
100004468: 6d490d01    	ldp	d1, d3, [x8, #0x90]
10000446c: 3d8193e1    	str	q1, [sp, #0x640]
100004470: 3d8197e3    	str	q3, [sp, #0x650]
100004474: 4fc19261    	fmul.2d	v1, v19, v1[0]
100004478: 4e61d400    	fadd.2d	v0, v0, v1
10000447c: 4fc39221    	fmul.2d	v1, v17, v3[0]
100004480: 4e61d400    	fadd.2d	v0, v0, v1
100004484: 6d4a0d01    	ldp	d1, d3, [x8, #0xa0]
100004488: 3d818be1    	str	q1, [sp, #0x620]
10000448c: 3d818fe3    	str	q3, [sp, #0x630]
100004490: 4fc19241    	fmul.2d	v1, v18, v1[0]
100004494: 4e61d400    	fadd.2d	v0, v0, v1
100004498: 4fc39041    	fmul.2d	v1, v2, v3[0]
10000449c: 4e61d409    	fadd.2d	v9, v0, v1
1000044a0: 3dc1251a    	ldr	q26, [x8, #0x490]
1000044a4: 6d4c0500    	ldp	d0, d1, [x8, #0xc0]
1000044a8: 3d8177e0    	str	q0, [sp, #0x5d0]
1000044ac: 3d8173e1    	str	q1, [sp, #0x5c0]
1000044b0: 4fc09340    	fmul.2d	v0, v26, v0[0]
1000044b4: 3dc13d03    	ldr	q3, [x8, #0x4f0]
1000044b8: 4fc19061    	fmul.2d	v1, v3, v1[0]
1000044bc: 3d8263e3    	str	q3, [sp, #0x980]
1000044c0: 4e61d400    	fadd.2d	v0, v0, v1
1000044c4: 3dc15505    	ldr	q5, [x8, #0x550]
1000044c8: 6d4d0901    	ldp	d1, d2, [x8, #0xd0]
1000044cc: 3d816fe1    	str	q1, [sp, #0x5b0]
1000044d0: 3d816be2    	str	q2, [sp, #0x5a0]
1000044d4: 4fc190a1    	fmul.2d	v1, v5, v1[0]
1000044d8: 3d82bfe5    	str	q5, [sp, #0xaf0]
1000044dc: 4e61d400    	fadd.2d	v0, v0, v1
1000044e0: 3dc16d04    	ldr	q4, [x8, #0x5b0]
1000044e4: 4fc29081    	fmul.2d	v1, v4, v2[0]
1000044e8: 3d82abe4    	str	q4, [sp, #0xaa0]
1000044ec: 4e61d400    	fadd.2d	v0, v0, v1
1000044f0: 3dc1850e    	ldr	q14, [x8, #0x610]
1000044f4: 6d4e0901    	ldp	d1, d2, [x8, #0xe0]
1000044f8: 3d8167e1    	str	q1, [sp, #0x590]
1000044fc: 3d8163e2    	str	q2, [sp, #0x580]
100004500: 4fc191c1    	fmul.2d	v1, v14, v1[0]
100004504: 4e61d400    	fadd.2d	v0, v0, v1
100004508: 3dc19d06    	ldr	q6, [x8, #0x670]
10000450c: 4fc290c1    	fmul.2d	v1, v6, v2[0]
100004510: 3d823fe6    	str	q6, [sp, #0x8f0]
100004514: 4e61d400    	fadd.2d	v0, v0, v1
100004518: 3dc1b51e    	ldr	q30, [x8, #0x6d0]
10000451c: 6d4f0901    	ldp	d1, d2, [x8, #0xf0]
100004520: 3d815fe1    	str	q1, [sp, #0x570]
100004524: 3d815be2    	str	q2, [sp, #0x560]
100004528: 4fc193c1    	fmul.2d	v1, v30, v1[0]
10000452c: 4e61d400    	fadd.2d	v0, v0, v1
100004530: 3dc1cd1f    	ldr	q31, [x8, #0x730]
100004534: 4fc293e1    	fmul.2d	v1, v31, v2[0]
100004538: 4e61d400    	fadd.2d	v0, v0, v1
10000453c: 3dc1e508    	ldr	q8, [x8, #0x790]
100004540: 6d500901    	ldp	d1, d2, [x8, #0x100]
100004544: 3d8157e1    	str	q1, [sp, #0x550]
100004548: 3d8153e2    	str	q2, [sp, #0x540]
10000454c: 4fc19101    	fmul.2d	v1, v8, v1[0]
100004550: 4e61d400    	fadd.2d	v0, v0, v1
100004554: 3dc1fd13    	ldr	q19, [x8, #0x7f0]
100004558: 4fc29261    	fmul.2d	v1, v19, v2[0]
10000455c: 3d82aff3    	str	q19, [sp, #0xab0]
100004560: 4e61d41d    	fadd.2d	v29, v0, v1
100004564: 3d817ffd    	str	q29, [sp, #0x5f0]
100004568: 6d520900    	ldp	d0, d2, [x8, #0x120]
10000456c: 3d814be0    	str	q0, [sp, #0x520]
100004570: 3d814fe2    	str	q2, [sp, #0x530]
100004574: 4fc09340    	fmul.2d	v0, v26, v0[0]
100004578: 4fc29061    	fmul.2d	v1, v3, v2[0]
10000457c: 4e61d400    	fadd.2d	v0, v0, v1
100004580: 6d530901    	ldp	d1, d2, [x8, #0x130]
100004584: 3d8143e1    	str	q1, [sp, #0x500]
100004588: 3d8147e2    	str	q2, [sp, #0x510]
10000458c: 4fc190a1    	fmul.2d	v1, v5, v1[0]
100004590: 4e61d400    	fadd.2d	v0, v0, v1
100004594: 4fc29081    	fmul.2d	v1, v4, v2[0]
100004598: 4e61d400    	fadd.2d	v0, v0, v1
10000459c: 6d540901    	ldp	d1, d2, [x8, #0x140]
1000045a0: 3d813fe1    	str	q1, [sp, #0x4f0]
1000045a4: 3d813be2    	str	q2, [sp, #0x4e0]
1000045a8: 4fc191c1    	fmul.2d	v1, v14, v1[0]
1000045ac: 4e61d400    	fadd.2d	v0, v0, v1
1000045b0: 4fc290c1    	fmul.2d	v1, v6, v2[0]
1000045b4: 4e61d400    	fadd.2d	v0, v0, v1
1000045b8: 6d550901    	ldp	d1, d2, [x8, #0x150]
1000045bc: 3d8137e1    	str	q1, [sp, #0x4d0]
1000045c0: 3d8133e2    	str	q2, [sp, #0x4c0]
1000045c4: 4fc193c1    	fmul.2d	v1, v30, v1[0]
1000045c8: 4e61d400    	fadd.2d	v0, v0, v1
1000045cc: 4fc293e1    	fmul.2d	v1, v31, v2[0]
1000045d0: 4e61d400    	fadd.2d	v0, v0, v1
1000045d4: 6d560901    	ldp	d1, d2, [x8, #0x160]
1000045d8: 3d812fe1    	str	q1, [sp, #0x4b0]
1000045dc: 3d812be2    	str	q2, [sp, #0x4a0]
1000045e0: 4fc19101    	fmul.2d	v1, v8, v1[0]
1000045e4: 4e61d400    	fadd.2d	v0, v0, v1
1000045e8: 4fc29261    	fmul.2d	v1, v19, v2[0]
1000045ec: 4e61d419    	fadd.2d	v25, v0, v1
1000045f0: 3dc1290a    	ldr	q10, [x8, #0x4a0]
1000045f4: 6d580500    	ldp	d0, d1, [x8, #0x180]
1000045f8: 3d8127e0    	str	q0, [sp, #0x490]
1000045fc: 3d8123e1    	str	q1, [sp, #0x480]
100004600: 4fc09140    	fmul.2d	v0, v10, v0[0]
100004604: 3dc1410b    	ldr	q11, [x8, #0x500]
100004608: 4fc19161    	fmul.2d	v1, v11, v1[0]
10000460c: 4e61d400    	fadd.2d	v0, v0, v1
100004610: 3dc15906    	ldr	q6, [x8, #0x560]
100004614: 6d590d01    	ldp	d1, d3, [x8, #0x190]
100004618: 3d811fe1    	str	q1, [sp, #0x470]
10000461c: 3d811be3    	str	q3, [sp, #0x460]
100004620: 4fc190c1    	fmul.2d	v1, v6, v1[0]
100004624: 3d829fe6    	str	q6, [sp, #0xa70]
100004628: 4e61d400    	fadd.2d	v0, v0, v1
10000462c: 3dc17105    	ldr	q5, [x8, #0x5c0]
100004630: 4fc390a1    	fmul.2d	v1, v5, v3[0]
100004634: 3d82a7e5    	str	q5, [sp, #0xa90]
100004638: 4e61d400    	fadd.2d	v0, v0, v1
10000463c: 3dc1890d    	ldr	q13, [x8, #0x620]
100004640: 6d5a0d01    	ldp	d1, d3, [x8, #0x1a0]
100004644: 3d8117e1    	str	q1, [sp, #0x450]
100004648: 3d8113e3    	str	q3, [sp, #0x440]
10000464c: 4fc191a1    	fmul.2d	v1, v13, v1[0]
100004650: 4e61d400    	fadd.2d	v0, v0, v1
100004654: 3dc1a10c    	ldr	q12, [x8, #0x680]
100004658: 4fc39181    	fmul.2d	v1, v12, v3[0]
10000465c: 4e61d400    	fadd.2d	v0, v0, v1
100004660: 3dc1b91b    	ldr	q27, [x8, #0x6e0]
100004664: 6d5b0d01    	ldp	d1, d3, [x8, #0x1b0]
100004668: 3d810fe1    	str	q1, [sp, #0x430]
10000466c: 3d810be3    	str	q3, [sp, #0x420]
100004670: 4fc19361    	fmul.2d	v1, v27, v1[0]
100004674: 4e61d400    	fadd.2d	v0, v0, v1
100004678: 3dc1d107    	ldr	q7, [x8, #0x740]
10000467c: 4fc390e1    	fmul.2d	v1, v7, v3[0]
100004680: 3d82bbe7    	str	q7, [sp, #0xae0]
100004684: 4e61d400    	fadd.2d	v0, v0, v1
100004688: 3dc1e902    	ldr	q2, [x8, #0x7a0]
10000468c: 6d5c0d01    	ldp	d1, d3, [x8, #0x1c0]
100004690: 3d8107e1    	str	q1, [sp, #0x410]
100004694: 3d80f7e3    	str	q3, [sp, #0x3d0]
100004698: 4fc19041    	fmul.2d	v1, v2, v1[0]
10000469c: 3d81efe2    	str	q2, [sp, #0x7b0]
1000046a0: 4e61d400    	fadd.2d	v0, v0, v1
1000046a4: 3dc20104    	ldr	q4, [x8, #0x800]
1000046a8: 4fc39081    	fmul.2d	v1, v4, v3[0]
1000046ac: 3d8267e4    	str	q4, [sp, #0x990]
1000046b0: 4e61d418    	fadd.2d	v24, v0, v1
1000046b4: 3d8183f8    	str	q24, [sp, #0x600]
1000046b8: 6d5e0500    	ldp	d0, d1, [x8, #0x1e0]
1000046bc: ad1d03e1    	stp	q1, q0, [sp, #0x3a0]
1000046c0: 4fc09140    	fmul.2d	v0, v10, v0[0]
1000046c4: 4fc19161    	fmul.2d	v1, v11, v1[0]
1000046c8: 4e61d400    	fadd.2d	v0, v0, v1
1000046cc: 6d5f0d01    	ldp	d1, d3, [x8, #0x1f0]
1000046d0: 3d80dfe1    	str	q1, [sp, #0x370]
1000046d4: 3d80e7e3    	str	q3, [sp, #0x390]
1000046d8: 4fc190c1    	fmul.2d	v1, v6, v1[0]
1000046dc: 4e61d400    	fadd.2d	v0, v0, v1
1000046e0: 4fc390a1    	fmul.2d	v1, v5, v3[0]
1000046e4: 4e61d400    	fadd.2d	v0, v0, v1
1000046e8: fd410101    	ldr	d1, [x8, #0x200]
1000046ec: 3d80dbe1    	str	q1, [sp, #0x360]
1000046f0: 4fc191a1    	fmul.2d	v1, v13, v1[0]
1000046f4: 4e61d400    	fadd.2d	v0, v0, v1
1000046f8: fd410501    	ldr	d1, [x8, #0x208]
1000046fc: 3d80d7e1    	str	q1, [sp, #0x350]
100004700: 4fc19181    	fmul.2d	v1, v12, v1[0]
100004704: 4e61d400    	fadd.2d	v0, v0, v1
100004708: fd410901    	ldr	d1, [x8, #0x210]
10000470c: 3d80d3e1    	str	q1, [sp, #0x340]
100004710: 4fc19361    	fmul.2d	v1, v27, v1[0]
100004714: 4e61d400    	fadd.2d	v0, v0, v1
100004718: fd410d01    	ldr	d1, [x8, #0x218]
10000471c: 3d80cfe1    	str	q1, [sp, #0x330]
100004720: 4fc190e1    	fmul.2d	v1, v7, v1[0]
100004724: 4e61d400    	fadd.2d	v0, v0, v1
100004728: fd411101    	ldr	d1, [x8, #0x220]
10000472c: 3d80cbe1    	str	q1, [sp, #0x320]
100004730: 4fc19041    	fmul.2d	v1, v2, v1[0]
100004734: 4e61d400    	fadd.2d	v0, v0, v1
100004738: fd411501    	ldr	d1, [x8, #0x228]
10000473c: 3d80c7e1    	str	q1, [sp, #0x310]
100004740: 4fc19081    	fmul.2d	v1, v4, v1[0]
100004744: 4e61d416    	fadd.2d	v22, v0, v1
100004748: 3dc12d0f    	ldr	q15, [x8, #0x4b0]
10000474c: fd412100    	ldr	d0, [x8, #0x240]
100004750: 3d80c3e0    	str	q0, [sp, #0x300]
100004754: 4fc091e0    	fmul.2d	v0, v15, v0[0]
100004758: 3dc14511    	ldr	q17, [x8, #0x510]
10000475c: fd412501    	ldr	d1, [x8, #0x248]
100004760: 3d80bfe1    	str	q1, [sp, #0x2f0]
100004764: 4fc19221    	fmul.2d	v1, v17, v1[0]
100004768: 3d825bf1    	str	q17, [sp, #0x960]
10000476c: 4e61d400    	fadd.2d	v0, v0, v1
100004770: 3dc15d10    	ldr	q16, [x8, #0x570]
100004774: fd412901    	ldr	d1, [x8, #0x250]
100004778: 3d80a3e1    	str	q1, [sp, #0x280]
10000477c: 4fc19201    	fmul.2d	v1, v16, v1[0]
100004780: 3d8257f0    	str	q16, [sp, #0x950]
100004784: 4e61d400    	fadd.2d	v0, v0, v1
100004788: 3dc17507    	ldr	q7, [x8, #0x5d0]
10000478c: fd412d01    	ldr	d1, [x8, #0x258]
100004790: 3d809be1    	str	q1, [sp, #0x260]
100004794: 4fc190e1    	fmul.2d	v1, v7, v1[0]
100004798: 3d824be7    	str	q7, [sp, #0x920]
10000479c: 4e61d400    	fadd.2d	v0, v0, v1
1000047a0: 3dc18d1c    	ldr	q28, [x8, #0x630]
1000047a4: fd413101    	ldr	d1, [x8, #0x260]
1000047a8: 3d8097e1    	str	q1, [sp, #0x250]
1000047ac: 4fc19381    	fmul.2d	v1, v28, v1[0]
1000047b0: 4e61d400    	fadd.2d	v0, v0, v1
1000047b4: 3dc1a505    	ldr	q5, [x8, #0x690]
1000047b8: fd413501    	ldr	d1, [x8, #0x268]
1000047bc: 3d8093e1    	str	q1, [sp, #0x240]
1000047c0: 4fc190a1    	fmul.2d	v1, v5, v1[0]
1000047c4: 3d825fe5    	str	q5, [sp, #0x970]
1000047c8: 4e61d400    	fadd.2d	v0, v0, v1
1000047cc: 3dc1bd12    	ldr	q18, [x8, #0x6f0]
1000047d0: fd413901    	ldr	d1, [x8, #0x270]
1000047d4: 3d808fe1    	str	q1, [sp, #0x230]
1000047d8: 4fc19241    	fmul.2d	v1, v18, v1[0]
1000047dc: 3d8247f2    	str	q18, [sp, #0x910]
1000047e0: 4e61d400    	fadd.2d	v0, v0, v1
1000047e4: 3dc1d504    	ldr	q4, [x8, #0x750]
1000047e8: fd413d01    	ldr	d1, [x8, #0x278]
1000047ec: 3d8083e1    	str	q1, [sp, #0x200]
1000047f0: 4fc19081    	fmul.2d	v1, v4, v1[0]
1000047f4: 3d8253e4    	str	q4, [sp, #0x940]
1000047f8: 4e61d400    	fadd.2d	v0, v0, v1
1000047fc: 3dc1ed02    	ldr	q2, [x8, #0x7b0]
100004800: fd414101    	ldr	d1, [x8, #0x280]
100004804: 3d807fe1    	str	q1, [sp, #0x1f0]
100004808: 4fc19041    	fmul.2d	v1, v2, v1[0]
10000480c: 3d824fe2    	str	q2, [sp, #0x930]
100004810: 4e61d400    	fadd.2d	v0, v0, v1
100004814: 3dc20503    	ldr	q3, [x8, #0x810]
100004818: fd414501    	ldr	d1, [x8, #0x288]
10000481c: 3d807be1    	str	q1, [sp, #0x1e0]
100004820: 4fc19061    	fmul.2d	v1, v3, v1[0]
100004824: 3d82a3e3    	str	q3, [sp, #0xa80]
100004828: 4e61d417    	fadd.2d	v23, v0, v1
10000482c: 3d8187f7    	str	q23, [sp, #0x610]
100004830: fd415100    	ldr	d0, [x8, #0x2a0]
100004834: 3d8077e0    	str	q0, [sp, #0x1d0]
100004838: 4fc091e0    	fmul.2d	v0, v15, v0[0]
10000483c: 3d81dbef    	str	q15, [sp, #0x760]
100004840: fd415501    	ldr	d1, [x8, #0x2a8]
100004844: 3d8073e1    	str	q1, [sp, #0x1c0]
100004848: 4fc19221    	fmul.2d	v1, v17, v1[0]
10000484c: 4e61d400    	fadd.2d	v0, v0, v1
100004850: fd415901    	ldr	d1, [x8, #0x2b0]
100004854: 3d806fe1    	str	q1, [sp, #0x1b0]
100004858: 4fc19201    	fmul.2d	v1, v16, v1[0]
10000485c: 4e61d400    	fadd.2d	v0, v0, v1
100004860: fd415d01    	ldr	d1, [x8, #0x2b8]
100004864: 3d806be1    	str	q1, [sp, #0x1a0]
100004868: 4fc190e1    	fmul.2d	v1, v7, v1[0]
10000486c: 4e61d400    	fadd.2d	v0, v0, v1
100004870: fd416101    	ldr	d1, [x8, #0x2c0]
100004874: 3d8067e1    	str	q1, [sp, #0x190]
100004878: 4fc19381    	fmul.2d	v1, v28, v1[0]
10000487c: 3d821bfc    	str	q28, [sp, #0x860]
100004880: 4e61d400    	fadd.2d	v0, v0, v1
100004884: fd416501    	ldr	d1, [x8, #0x2c8]
100004888: 3d8063e1    	str	q1, [sp, #0x180]
10000488c: 4fc190a1    	fmul.2d	v1, v5, v1[0]
100004890: 4e61d400    	fadd.2d	v0, v0, v1
100004894: fd416901    	ldr	d1, [x8, #0x2d0]
100004898: 3d805fe1    	str	q1, [sp, #0x170]
10000489c: 4fc19241    	fmul.2d	v1, v18, v1[0]
1000048a0: 4e61d400    	fadd.2d	v0, v0, v1
1000048a4: fd416d01    	ldr	d1, [x8, #0x2d8]
1000048a8: 3d805be1    	str	q1, [sp, #0x160]
1000048ac: 4fc19081    	fmul.2d	v1, v4, v1[0]
1000048b0: 4e61d400    	fadd.2d	v0, v0, v1
1000048b4: fd417101    	ldr	d1, [x8, #0x2e0]
1000048b8: 3d8057e1    	str	q1, [sp, #0x150]
1000048bc: 4fc19041    	fmul.2d	v1, v2, v1[0]
1000048c0: 4e61d400    	fadd.2d	v0, v0, v1
1000048c4: fd417501    	ldr	d1, [x8, #0x2e8]
1000048c8: 3d8053e1    	str	q1, [sp, #0x140]
1000048cc: 4fc19061    	fmul.2d	v1, v3, v1[0]
1000048d0: 4e61d415    	fadd.2d	v21, v0, v1
1000048d4: 3dc13113    	ldr	q19, [x8, #0x4c0]
1000048d8: fd418100    	ldr	d0, [x8, #0x300]
1000048dc: 3d804fe0    	str	q0, [sp, #0x130]
1000048e0: 4fc09260    	fmul.2d	v0, v19, v0[0]
1000048e4: 3d8227f3    	str	q19, [sp, #0x890]
1000048e8: 3dc14911    	ldr	q17, [x8, #0x520]
1000048ec: fd418501    	ldr	d1, [x8, #0x308]
1000048f0: 3d804be1    	str	q1, [sp, #0x120]
1000048f4: 4fc19221    	fmul.2d	v1, v17, v1[0]
1000048f8: 3d8223f1    	str	q17, [sp, #0x880]
1000048fc: 4e61d400    	fadd.2d	v0, v0, v1
100004900: 3dc16103    	ldr	q3, [x8, #0x580]
100004904: fd418901    	ldr	d1, [x8, #0x310]
100004908: 3d8047e1    	str	q1, [sp, #0x110]
10000490c: 4fc19061    	fmul.2d	v1, v3, v1[0]
100004910: 3d823be3    	str	q3, [sp, #0x8e0]
100004914: 4e61d400    	fadd.2d	v0, v0, v1
100004918: 3dc17912    	ldr	q18, [x8, #0x5e0]
10000491c: fd418d01    	ldr	d1, [x8, #0x318]
100004920: 3d8043e1    	str	q1, [sp, #0x100]
100004924: 4fc19241    	fmul.2d	v1, v18, v1[0]
100004928: 3d828ff2    	str	q18, [sp, #0xa30]
10000492c: 4e61d400    	fadd.2d	v0, v0, v1
100004930: 3dc19102    	ldr	q2, [x8, #0x640]
100004934: fd419101    	ldr	d1, [x8, #0x320]
100004938: 3d803fe1    	str	q1, [sp, #0xf0]
10000493c: 4fc19041    	fmul.2d	v1, v2, v1[0]
100004940: 3d8237e2    	str	q2, [sp, #0x8d0]
100004944: 4e61d400    	fadd.2d	v0, v0, v1
100004948: 3dc1a904    	ldr	q4, [x8, #0x6a0]
10000494c: fd419501    	ldr	d1, [x8, #0x328]
100004950: 3d803be1    	str	q1, [sp, #0xe0]
100004954: 4fc19081    	fmul.2d	v1, v4, v1[0]
100004958: 3d821fe4    	str	q4, [sp, #0x870]
10000495c: 4e61d400    	fadd.2d	v0, v0, v1
100004960: 3dc1c106    	ldr	q6, [x8, #0x700]
100004964: fd419901    	ldr	d1, [x8, #0x330]
100004968: 3d8037e1    	str	q1, [sp, #0xd0]
10000496c: 4fc190c1    	fmul.2d	v1, v6, v1[0]
100004970: 3d829be6    	str	q6, [sp, #0xa60]
100004974: 4e61d400    	fadd.2d	v0, v0, v1
100004978: 3dc1d907    	ldr	q7, [x8, #0x760]
10000497c: fd419d01    	ldr	d1, [x8, #0x338]
100004980: 3d8033e1    	str	q1, [sp, #0xc0]
100004984: 4fc190e1    	fmul.2d	v1, v7, v1[0]
100004988: 3d8297e7    	str	q7, [sp, #0xa50]
10000498c: 4e61d400    	fadd.2d	v0, v0, v1
100004990: 3dc1f110    	ldr	q16, [x8, #0x7c0]
100004994: fd41a101    	ldr	d1, [x8, #0x340]
100004998: 3d802fe1    	str	q1, [sp, #0xb0]
10000499c: 4fc19201    	fmul.2d	v1, v16, v1[0]
1000049a0: 3d8233f0    	str	q16, [sp, #0x8c0]
1000049a4: 4e61d400    	fadd.2d	v0, v0, v1
1000049a8: 3dc20905    	ldr	q5, [x8, #0x820]
1000049ac: fd41a501    	ldr	d1, [x8, #0x348]
1000049b0: 3d802be1    	str	q1, [sp, #0xa0]
1000049b4: 4fc190a1    	fmul.2d	v1, v5, v1[0]
1000049b8: 3d8293e5    	str	q5, [sp, #0xa40]
1000049bc: 4e61d414    	fadd.2d	v20, v0, v1
1000049c0: 3d817bf4    	str	q20, [sp, #0x5e0]
1000049c4: fd41b100    	ldr	d0, [x8, #0x360]
1000049c8: 3d8027e0    	str	q0, [sp, #0x90]
1000049cc: 4fc09260    	fmul.2d	v0, v19, v0[0]
1000049d0: fd41b501    	ldr	d1, [x8, #0x368]
1000049d4: 3d8023e1    	str	q1, [sp, #0x80]
1000049d8: 4fc19221    	fmul.2d	v1, v17, v1[0]
1000049dc: 4e61d400    	fadd.2d	v0, v0, v1
1000049e0: fd41b901    	ldr	d1, [x8, #0x370]
1000049e4: 3d801fe1    	str	q1, [sp, #0x70]
1000049e8: 4fc19061    	fmul.2d	v1, v3, v1[0]
1000049ec: 4e61d400    	fadd.2d	v0, v0, v1
1000049f0: fd41bd01    	ldr	d1, [x8, #0x378]
1000049f4: 3d801be1    	str	q1, [sp, #0x60]
1000049f8: 4fc19241    	fmul.2d	v1, v18, v1[0]
1000049fc: 4e61d400    	fadd.2d	v0, v0, v1
100004a00: fd41c101    	ldr	d1, [x8, #0x380]
100004a04: 3d8017e1    	str	q1, [sp, #0x50]
100004a08: 4fc19041    	fmul.2d	v1, v2, v1[0]
100004a0c: 4e61d400    	fadd.2d	v0, v0, v1
100004a10: fd41c501    	ldr	d1, [x8, #0x388]
100004a14: 3d8013e1    	str	q1, [sp, #0x40]
100004a18: 4fc19081    	fmul.2d	v1, v4, v1[0]
100004a1c: 4e61d400    	fadd.2d	v0, v0, v1
100004a20: fd41c901    	ldr	d1, [x8, #0x390]
100004a24: 3d800fe1    	str	q1, [sp, #0x30]
100004a28: 4fc190c1    	fmul.2d	v1, v6, v1[0]
100004a2c: 4e61d400    	fadd.2d	v0, v0, v1
100004a30: fd41cd01    	ldr	d1, [x8, #0x398]
100004a34: 3d800be1    	str	q1, [sp, #0x20]
100004a38: 4fc190e1    	fmul.2d	v1, v7, v1[0]
100004a3c: 4e61d400    	fadd.2d	v0, v0, v1
100004a40: fd41d101    	ldr	d1, [x8, #0x3a0]
100004a44: 3d8007e1    	str	q1, [sp, #0x10]
100004a48: 4fc19201    	fmul.2d	v1, v16, v1[0]
100004a4c: 4e61d400    	fadd.2d	v0, v0, v1
100004a50: fd41d501    	ldr	d1, [x8, #0x3a8]
100004a54: 3d8003e1    	str	q1, [sp]
100004a58: 4fc190a1    	fmul.2d	v1, v5, v1[0]
100004a5c: 4e61d406    	fadd.2d	v6, v0, v1
100004a60: ad1f57e9    	stp	q9, q21, [sp, #0x3e0]
100004a64: 5e180520    	mov	d0, v9[1]
100004a68: fd013fe0    	str	d0, [sp, #0x278]
100004a6c: 3dc1d3e1    	ldr	q1, [sp, #0x740]
100004a70: 1e602820    	fadd	d0, d1, d0
100004a74: 1e7d2800    	fadd	d0, d0, d29
100004a78: 3d80f3f9    	str	q25, [sp, #0x3c0]
100004a7c: 5e180721    	mov	d1, v25[1]
100004a80: fd010be1    	str	d1, [sp, #0x210]
100004a84: 1e612800    	fadd	d0, d0, d1
100004a88: 1e782800    	fadd	d0, d0, d24
100004a8c: 3d8103f6    	str	q22, [sp, #0x400]
100004a90: 5e1806c1    	mov	d1, v22[1]
100004a94: fd010fe1    	str	d1, [sp, #0x218]
100004a98: 1e612800    	fadd	d0, d0, d1
100004a9c: 1e772800    	fadd	d0, d0, d23
100004aa0: 5e1806a1    	mov	d1, v21[1]
100004aa4: fd0113e1    	str	d1, [sp, #0x220]
100004aa8: 1e612800    	fadd	d0, d0, d1
100004aac: 1e742800    	fadd	d0, d0, d20
100004ab0: 3d80e3e6    	str	q6, [sp, #0x380]
100004ab4: 5e1804c1    	mov	d1, v6[1]
100004ab8: fd0117e1    	str	d1, [sp, #0x228]
100004abc: 1e612800    	fadd	d0, d0, d1
100004ac0: 1e60c000    	fabs	d0, d0
100004ac4: d2857369    	mov	x9, #0x2b9b             ; =11163
100004ac8: f2b0d429    	movk	x9, #0x86a1, lsl #16
100004acc: f2d09369    	movk	x9, #0x849b, lsl #32
100004ad0: f2e7a0c9    	movk	x9, #0x3d06, lsl #48
100004ad4: 9e670121    	fmov	d1, x9
100004ad8: 1e612000    	fcmp	d0, d1
100004adc: 3dc287f7    	ldr	q23, [sp, #0xa10]
100004ae0: 3d8213fa    	str	q26, [sp, #0x840]
100004ae4: 4fd79340    	fmul.2d	v0, v26, v23[0]
100004ae8: 3dc2c3e4    	ldr	q4, [sp, #0xb00]
100004aec: 3dc263f1    	ldr	q17, [sp, #0x980]
100004af0: 4fc49221    	fmul.2d	v1, v17, v4[0]
100004af4: 4e61d400    	fadd.2d	v0, v0, v1
100004af8: 3dc2bff9    	ldr	q25, [sp, #0xaf0]
100004afc: 3dc28be7    	ldr	q7, [sp, #0xa20]
100004b00: 4fc79321    	fmul.2d	v1, v25, v7[0]
100004b04: 4e61d400    	fadd.2d	v0, v0, v1
100004b08: 3dc2abf8    	ldr	q24, [sp, #0xaa0]
100004b0c: 3dc2b7f4    	ldr	q20, [sp, #0xad0]
100004b10: 4fd49301    	fmul.2d	v1, v24, v20[0]
100004b14: 4e61d400    	fadd.2d	v0, v0, v1
100004b18: 3d81dfee    	str	q14, [sp, #0x770]
100004b1c: 3dc1aff5    	ldr	q21, [sp, #0x6b0]
100004b20: 4fd591c1    	fmul.2d	v1, v14, v21[0]
100004b24: 4e61d400    	fadd.2d	v0, v0, v1
100004b28: 3dc23ffd    	ldr	q29, [sp, #0x8f0]
100004b2c: 3dc283e6    	ldr	q6, [sp, #0xa00]
100004b30: 4fc693a1    	fmul.2d	v1, v29, v6[0]
100004b34: 4e61d400    	fadd.2d	v0, v0, v1
100004b38: 3d81d7fe    	str	q30, [sp, #0x750]
100004b3c: 3dc27fe2    	ldr	q2, [sp, #0x9f0]
100004b40: 4fc293c1    	fmul.2d	v1, v30, v2[0]
100004b44: 4e61d400    	fadd.2d	v0, v0, v1
100004b48: 3d81e7ff    	str	q31, [sp, #0x790]
100004b4c: 3dc20be3    	ldr	q3, [sp, #0x820]
100004b50: 4fc393e1    	fmul.2d	v1, v31, v3[0]
100004b54: 4e61d400    	fadd.2d	v0, v0, v1
100004b58: 3d81e3e8    	str	q8, [sp, #0x780]
100004b5c: 3dc1cfe5    	ldr	q5, [sp, #0x730]
100004b60: 4fc59101    	fmul.2d	v1, v8, v5[0]
100004b64: 4e61d400    	fadd.2d	v0, v0, v1
100004b68: 3dc2afe9    	ldr	q9, [sp, #0xab0]
100004b6c: 3dc1b3f0    	ldr	q16, [sp, #0x6c0]
100004b70: 4fd09121    	fmul.2d	v1, v9, v16[0]
100004b74: 4e61d400    	fadd.2d	v0, v0, v1
100004b78: 3d81bbe0    	str	q0, [sp, #0x6e0]
100004b7c: 3d822bea    	str	q10, [sp, #0x8a0]
100004b80: 4fd79140    	fmul.2d	v0, v10, v23[0]
100004b84: 3d822feb    	str	q11, [sp, #0x8b0]
100004b88: 4fc49161    	fmul.2d	v1, v11, v4[0]
100004b8c: 4e61d400    	fadd.2d	v0, v0, v1
100004b90: 3dc29fe1    	ldr	q1, [sp, #0xa70]
100004b94: 4fc79021    	fmul.2d	v1, v1, v7[0]
100004b98: 4e61d400    	fadd.2d	v0, v0, v1
100004b9c: 3dc2a7f3    	ldr	q19, [sp, #0xa90]
100004ba0: 4fd49261    	fmul.2d	v1, v19, v20[0]
100004ba4: 4e61d400    	fadd.2d	v0, v0, v1
100004ba8: 3d8217ed    	str	q13, [sp, #0x850]
100004bac: 4fd591a1    	fmul.2d	v1, v13, v21[0]
100004bb0: 4e61d400    	fadd.2d	v0, v0, v1
100004bb4: 3d81ebec    	str	q12, [sp, #0x7a0]
100004bb8: 4fc69181    	fmul.2d	v1, v12, v6[0]
100004bbc: 4e61d400    	fadd.2d	v0, v0, v1
100004bc0: 3d8243fb    	str	q27, [sp, #0x900]
100004bc4: 4fc29361    	fmul.2d	v1, v27, v2[0]
100004bc8: 4e61d400    	fadd.2d	v0, v0, v1
100004bcc: 3dc2bbf6    	ldr	q22, [sp, #0xae0]
100004bd0: 4fc392c1    	fmul.2d	v1, v22, v3[0]
100004bd4: 4e61d400    	fadd.2d	v0, v0, v1
100004bd8: 3dc1efe1    	ldr	q1, [sp, #0x7b0]
100004bdc: 4fc59021    	fmul.2d	v1, v1, v5[0]
100004be0: 4e61d400    	fadd.2d	v0, v0, v1
100004be4: 3dc267e1    	ldr	q1, [sp, #0x990]
100004be8: 4fd09021    	fmul.2d	v1, v1, v16[0]
100004bec: 4e61d400    	fadd.2d	v0, v0, v1
100004bf0: 3d81b7e0    	str	q0, [sp, #0x6d0]
100004bf4: 4fd791e0    	fmul.2d	v0, v15, v23[0]
100004bf8: 3dc25be1    	ldr	q1, [sp, #0x960]
100004bfc: 4fc49021    	fmul.2d	v1, v1, v4[0]
100004c00: 4e61d400    	fadd.2d	v0, v0, v1
100004c04: 3dc257e1    	ldr	q1, [sp, #0x950]
100004c08: 4fc79021    	fmul.2d	v1, v1, v7[0]
100004c0c: 4e61d400    	fadd.2d	v0, v0, v1
100004c10: 3dc24bef    	ldr	q15, [sp, #0x920]
100004c14: 4fd491e1    	fmul.2d	v1, v15, v20[0]
100004c18: 4e61d400    	fadd.2d	v0, v0, v1
100004c1c: 4fd59381    	fmul.2d	v1, v28, v21[0]
100004c20: 4e61d400    	fadd.2d	v0, v0, v1
100004c24: 3dc25fe1    	ldr	q1, [sp, #0x970]
100004c28: 4fc69021    	fmul.2d	v1, v1, v6[0]
100004c2c: 4e61d400    	fadd.2d	v0, v0, v1
100004c30: 3dc247fc    	ldr	q28, [sp, #0x910]
100004c34: 4fc29381    	fmul.2d	v1, v28, v2[0]
100004c38: 4e61d400    	fadd.2d	v0, v0, v1
100004c3c: 3dc253e1    	ldr	q1, [sp, #0x940]
100004c40: 4fc39021    	fmul.2d	v1, v1, v3[0]
100004c44: 4e61d400    	fadd.2d	v0, v0, v1
100004c48: 3dc24fe1    	ldr	q1, [sp, #0x930]
100004c4c: 4fc59021    	fmul.2d	v1, v1, v5[0]
100004c50: 4e61d400    	fadd.2d	v0, v0, v1
100004c54: 3dc2a3e1    	ldr	q1, [sp, #0xa80]
100004c58: 4fd09021    	fmul.2d	v1, v1, v16[0]
100004c5c: 4e61d400    	fadd.2d	v0, v0, v1
100004c60: 3d81cbe0    	str	q0, [sp, #0x720]
100004c64: 3dc227e0    	ldr	q0, [sp, #0x890]
100004c68: 4fd79000    	fmul.2d	v0, v0, v23[0]
100004c6c: 3dc223e1    	ldr	q1, [sp, #0x880]
100004c70: 4fc49021    	fmul.2d	v1, v1, v4[0]
100004c74: 4e61d400    	fadd.2d	v0, v0, v1
100004c78: 3dc23be1    	ldr	q1, [sp, #0x8e0]
100004c7c: 4fc79021    	fmul.2d	v1, v1, v7[0]
100004c80: 4e61d400    	fadd.2d	v0, v0, v1
100004c84: 3dc28fe1    	ldr	q1, [sp, #0xa30]
100004c88: 4fd49021    	fmul.2d	v1, v1, v20[0]
100004c8c: 4e61d400    	fadd.2d	v0, v0, v1
100004c90: 3dc237e1    	ldr	q1, [sp, #0x8d0]
100004c94: 4fd59021    	fmul.2d	v1, v1, v21[0]
100004c98: 4e61d400    	fadd.2d	v0, v0, v1
100004c9c: 3dc21fe1    	ldr	q1, [sp, #0x870]
100004ca0: 4fc69021    	fmul.2d	v1, v1, v6[0]
100004ca4: 4e61d400    	fadd.2d	v0, v0, v1
100004ca8: 3dc29be1    	ldr	q1, [sp, #0xa60]
100004cac: 4fc29021    	fmul.2d	v1, v1, v2[0]
100004cb0: 4e61d400    	fadd.2d	v0, v0, v1
100004cb4: 3dc297e1    	ldr	q1, [sp, #0xa50]
100004cb8: 4fc39021    	fmul.2d	v1, v1, v3[0]
100004cbc: 4e61d400    	fadd.2d	v0, v0, v1
100004cc0: 3dc233e1    	ldr	q1, [sp, #0x8c0]
100004cc4: 4fc59021    	fmul.2d	v1, v1, v5[0]
100004cc8: 4e61d400    	fadd.2d	v0, v0, v1
100004ccc: 3dc293e1    	ldr	q1, [sp, #0xa40]
100004cd0: 4fd09021    	fmul.2d	v1, v1, v16[0]
100004cd4: 4e61d400    	fadd.2d	v0, v0, v1
100004cd8: 3d81c7e0    	str	q0, [sp, #0x710]
100004cdc: 3dc13500    	ldr	q0, [x8, #0x4d0]
100004ce0: 3d820fe0    	str	q0, [sp, #0x830]
100004ce4: 4fd79000    	fmul.2d	v0, v0, v23[0]
100004ce8: 3dc14d01    	ldr	q1, [x8, #0x530]
100004cec: 3d827be1    	str	q1, [sp, #0x9e0]
100004cf0: 4fc49021    	fmul.2d	v1, v1, v4[0]
100004cf4: 4e61d400    	fadd.2d	v0, v0, v1
100004cf8: 3dc16501    	ldr	q1, [x8, #0x590]
100004cfc: 3d82c3e1    	str	q1, [sp, #0xb00]
100004d00: 4fc79021    	fmul.2d	v1, v1, v7[0]
100004d04: 4e61d400    	fadd.2d	v0, v0, v1
100004d08: 3dc17d01    	ldr	q1, [x8, #0x5f0]
100004d0c: 3d8277e1    	str	q1, [sp, #0x9d0]
100004d10: 4fd49021    	fmul.2d	v1, v1, v20[0]
100004d14: 4e61d400    	fadd.2d	v0, v0, v1
100004d18: 3dc19501    	ldr	q1, [x8, #0x650]
100004d1c: 3d828be1    	str	q1, [sp, #0xa20]
100004d20: 4fd59021    	fmul.2d	v1, v1, v21[0]
100004d24: 4e61d400    	fadd.2d	v0, v0, v1
100004d28: 3dc1ad01    	ldr	q1, [x8, #0x6b0]
100004d2c: 3d8287e1    	str	q1, [sp, #0xa10]
100004d30: 4fc69021    	fmul.2d	v1, v1, v6[0]
100004d34: 4e61d400    	fadd.2d	v0, v0, v1
100004d38: 3dc1c501    	ldr	q1, [x8, #0x710]
100004d3c: 3d8283e1    	str	q1, [sp, #0xa00]
100004d40: 4fc29021    	fmul.2d	v1, v1, v2[0]
100004d44: 4e61d400    	fadd.2d	v0, v0, v1
100004d48: 3dc1dd01    	ldr	q1, [x8, #0x770]
100004d4c: 3d82b7e1    	str	q1, [sp, #0xad0]
100004d50: 4fc39021    	fmul.2d	v1, v1, v3[0]
100004d54: 4e61d400    	fadd.2d	v0, v0, v1
100004d58: 3dc1f501    	ldr	q1, [x8, #0x7d0]
100004d5c: 3d827fe1    	str	q1, [sp, #0x9f0]
100004d60: 4fc59021    	fmul.2d	v1, v1, v5[0]
100004d64: 4e61d400    	fadd.2d	v0, v0, v1
100004d68: 3dc20d01    	ldr	q1, [x8, #0x830]
100004d6c: 3d820be1    	str	q1, [sp, #0x820]
100004d70: 4fd09021    	fmul.2d	v1, v1, v16[0]
100004d74: 4e61d400    	fadd.2d	v0, v0, v1
100004d78: 3d80bbe0    	str	q0, [sp, #0x2e0]
100004d7c: 3dc1c3e7    	ldr	q7, [sp, #0x700]
100004d80: 4fc79340    	fmul.2d	v0, v26, v7[0]
100004d84: 3dc1bfe4    	ldr	q4, [sp, #0x6f0]
100004d88: 4fc49221    	fmul.2d	v1, v17, v4[0]
100004d8c: 4e61d400    	fadd.2d	v0, v0, v1
100004d90: 3dc1a3f1    	ldr	q17, [sp, #0x680]
100004d94: 4fd19321    	fmul.2d	v1, v25, v17[0]
100004d98: 4e61d400    	fadd.2d	v0, v0, v1
100004d9c: 3dc1a7f0    	ldr	q16, [sp, #0x690]
100004da0: 4fd09301    	fmul.2d	v1, v24, v16[0]
100004da4: 4e61d400    	fadd.2d	v0, v0, v1
100004da8: 3dc19bf5    	ldr	q21, [sp, #0x660]
100004dac: 4fd591c1    	fmul.2d	v1, v14, v21[0]
100004db0: 4e61d400    	fadd.2d	v0, v0, v1
100004db4: 3dc19ff4    	ldr	q20, [sp, #0x670]
100004db8: 4fd493a1    	fmul.2d	v1, v29, v20[0]
100004dbc: 4e61d400    	fadd.2d	v0, v0, v1
100004dc0: 3dc193e2    	ldr	q2, [sp, #0x640]
100004dc4: 4fc293c1    	fmul.2d	v1, v30, v2[0]
100004dc8: 4e61d400    	fadd.2d	v0, v0, v1
100004dcc: 3dc197f2    	ldr	q18, [sp, #0x650]
100004dd0: 4fd293e1    	fmul.2d	v1, v31, v18[0]
100004dd4: 4e61d400    	fadd.2d	v0, v0, v1
100004dd8: 3dc18be5    	ldr	q5, [sp, #0x620]
100004ddc: 4fc59101    	fmul.2d	v1, v8, v5[0]
100004de0: 4e61d400    	fadd.2d	v0, v0, v1
100004de4: 3dc18fe3    	ldr	q3, [sp, #0x630]
100004de8: 4fc39121    	fmul.2d	v1, v9, v3[0]
100004dec: 4e61d400    	fadd.2d	v0, v0, v1
100004df0: 3d81cfe0    	str	q0, [sp, #0x730]
100004df4: 4fc79140    	fmul.2d	v0, v10, v7[0]
100004df8: 4fc49161    	fmul.2d	v1, v11, v4[0]
100004dfc: 4e61d400    	fadd.2d	v0, v0, v1
100004e00: 3dc29fee    	ldr	q14, [sp, #0xa70]
100004e04: 4fd191c1    	fmul.2d	v1, v14, v17[0]
100004e08: 4e61d400    	fadd.2d	v0, v0, v1
100004e0c: 4fd09261    	fmul.2d	v1, v19, v16[0]
100004e10: 4e61d400    	fadd.2d	v0, v0, v1
100004e14: 4fd591a1    	fmul.2d	v1, v13, v21[0]
100004e18: 4e61d400    	fadd.2d	v0, v0, v1
100004e1c: 4fd49181    	fmul.2d	v1, v12, v20[0]
100004e20: 4e61d400    	fadd.2d	v0, v0, v1
100004e24: 4fc29361    	fmul.2d	v1, v27, v2[0]
100004e28: 4e61d400    	fadd.2d	v0, v0, v1
100004e2c: 4fd292c1    	fmul.2d	v1, v22, v18[0]
100004e30: 4e61d400    	fadd.2d	v0, v0, v1
100004e34: 3dc1efe8    	ldr	q8, [sp, #0x7b0]
100004e38: 4fc59101    	fmul.2d	v1, v8, v5[0]
100004e3c: 4e61d400    	fadd.2d	v0, v0, v1
100004e40: 3dc267e1    	ldr	q1, [sp, #0x990]
100004e44: 4fc39021    	fmul.2d	v1, v1, v3[0]
100004e48: 4e61d400    	fadd.2d	v0, v0, v1
100004e4c: 3d81b3e0    	str	q0, [sp, #0x6c0]
100004e50: 3dc1dbeb    	ldr	q11, [sp, #0x760]
100004e54: 4fc79160    	fmul.2d	v0, v11, v7[0]
100004e58: 3dc25bec    	ldr	q12, [sp, #0x960]
100004e5c: 4fc49181    	fmul.2d	v1, v12, v4[0]
100004e60: 4e61d400    	fadd.2d	v0, v0, v1
100004e64: 3dc257ea    	ldr	q10, [sp, #0x950]
100004e68: 4fd19141    	fmul.2d	v1, v10, v17[0]
100004e6c: 4e61d400    	fadd.2d	v0, v0, v1
100004e70: 4fd091e1    	fmul.2d	v1, v15, v16[0]
100004e74: 4e61d400    	fadd.2d	v0, v0, v1
100004e78: 3dc21be1    	ldr	q1, [sp, #0x860]
100004e7c: 4fd59021    	fmul.2d	v1, v1, v21[0]
100004e80: 4e61d400    	fadd.2d	v0, v0, v1
100004e84: 3dc25fe1    	ldr	q1, [sp, #0x970]
100004e88: 4fd49021    	fmul.2d	v1, v1, v20[0]
100004e8c: 4e61d400    	fadd.2d	v0, v0, v1
100004e90: 4fc29381    	fmul.2d	v1, v28, v2[0]
100004e94: 4e61d400    	fadd.2d	v0, v0, v1
100004e98: 3dc253e6    	ldr	q6, [sp, #0x940]
100004e9c: 4fd290c1    	fmul.2d	v1, v6, v18[0]
100004ea0: 4e61d400    	fadd.2d	v0, v0, v1
100004ea4: 3dc24ff7    	ldr	q23, [sp, #0x930]
100004ea8: 4fc592e1    	fmul.2d	v1, v23, v5[0]
100004eac: 4e61d400    	fadd.2d	v0, v0, v1
100004eb0: 3dc2a3e1    	ldr	q1, [sp, #0xa80]
100004eb4: 4fc39021    	fmul.2d	v1, v1, v3[0]
100004eb8: 4e61d400    	fadd.2d	v0, v0, v1
100004ebc: 3d81abe0    	str	q0, [sp, #0x6a0]
100004ec0: 3dc227ef    	ldr	q15, [sp, #0x890]
100004ec4: 4fc791e0    	fmul.2d	v0, v15, v7[0]
100004ec8: 3dc223fd    	ldr	q29, [sp, #0x880]
100004ecc: 4fc493a1    	fmul.2d	v1, v29, v4[0]
100004ed0: 4e61d400    	fadd.2d	v0, v0, v1
100004ed4: 3dc23be1    	ldr	q1, [sp, #0x8e0]
100004ed8: 4fd19021    	fmul.2d	v1, v1, v17[0]
100004edc: 4e61d400    	fadd.2d	v0, v0, v1
100004ee0: 3dc28fff    	ldr	q31, [sp, #0xa30]
100004ee4: 4fd093e1    	fmul.2d	v1, v31, v16[0]
100004ee8: 4e61d400    	fadd.2d	v0, v0, v1
100004eec: 3dc237e1    	ldr	q1, [sp, #0x8d0]
100004ef0: 4fd59021    	fmul.2d	v1, v1, v21[0]
100004ef4: 4e61d400    	fadd.2d	v0, v0, v1
100004ef8: 3dc21fe9    	ldr	q9, [sp, #0x870]
100004efc: 4fd49121    	fmul.2d	v1, v9, v20[0]
100004f00: 4e61d400    	fadd.2d	v0, v0, v1
100004f04: 3dc29be1    	ldr	q1, [sp, #0xa60]
100004f08: 4fc29021    	fmul.2d	v1, v1, v2[0]
100004f0c: 4e61d400    	fadd.2d	v0, v0, v1
100004f10: 3dc297e1    	ldr	q1, [sp, #0xa50]
100004f14: 4fd29021    	fmul.2d	v1, v1, v18[0]
100004f18: 4e61d400    	fadd.2d	v0, v0, v1
100004f1c: 3dc233e1    	ldr	q1, [sp, #0x8c0]
100004f20: 4fc59021    	fmul.2d	v1, v1, v5[0]
100004f24: 4e61d400    	fadd.2d	v0, v0, v1
100004f28: 3dc293e1    	ldr	q1, [sp, #0xa40]
100004f2c: 4fc39021    	fmul.2d	v1, v1, v3[0]
100004f30: 4e61d400    	fadd.2d	v0, v0, v1
100004f34: 3d81afe0    	str	q0, [sp, #0x6b0]
100004f38: 3dc20fe0    	ldr	q0, [sp, #0x830]
100004f3c: 4fc79000    	fmul.2d	v0, v0, v7[0]
100004f40: 3dc27be1    	ldr	q1, [sp, #0x9e0]
100004f44: 4fc49021    	fmul.2d	v1, v1, v4[0]
100004f48: 4e61d400    	fadd.2d	v0, v0, v1
100004f4c: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
100004f50: 4fd19021    	fmul.2d	v1, v1, v17[0]
100004f54: 4e61d400    	fadd.2d	v0, v0, v1
100004f58: 3dc277f1    	ldr	q17, [sp, #0x9d0]
100004f5c: 4fd09221    	fmul.2d	v1, v17, v16[0]
100004f60: 4e61d400    	fadd.2d	v0, v0, v1
100004f64: 3dc28be1    	ldr	q1, [sp, #0xa20]
100004f68: 4fd59021    	fmul.2d	v1, v1, v21[0]
100004f6c: 4e61d400    	fadd.2d	v0, v0, v1
100004f70: 3dc287e1    	ldr	q1, [sp, #0xa10]
100004f74: 4fd49021    	fmul.2d	v1, v1, v20[0]
100004f78: 4e61d400    	fadd.2d	v0, v0, v1
100004f7c: 3dc283e1    	ldr	q1, [sp, #0xa00]
100004f80: 4fc29021    	fmul.2d	v1, v1, v2[0]
100004f84: 4e61d400    	fadd.2d	v0, v0, v1
100004f88: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
100004f8c: 4fd29021    	fmul.2d	v1, v1, v18[0]
100004f90: 4e61d400    	fadd.2d	v0, v0, v1
100004f94: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
100004f98: 4fc59021    	fmul.2d	v1, v1, v5[0]
100004f9c: 4e61d400    	fadd.2d	v0, v0, v1
100004fa0: 3dc20bf0    	ldr	q16, [sp, #0x820]
100004fa4: 4fc39201    	fmul.2d	v1, v16, v3[0]
100004fa8: 4e61d400    	fadd.2d	v0, v0, v1
100004fac: 3d80b7e0    	str	q0, [sp, #0x2d0]
100004fb0: 3dc207e5    	ldr	q5, [sp, #0x810]
100004fb4: 3dc177f6    	ldr	q22, [sp, #0x5d0]
100004fb8: 4fd690a0    	fmul.2d	v0, v5, v22[0]
100004fbc: 3dc173fb    	ldr	q27, [sp, #0x5c0]
100004fc0: 3dc203e1    	ldr	q1, [sp, #0x800]
100004fc4: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100004fc8: 4e61d400    	fadd.2d	v0, v0, v1
100004fcc: 3dc1fbf2    	ldr	q18, [sp, #0x7e0]
100004fd0: 3dc16ffe    	ldr	q30, [sp, #0x5b0]
100004fd4: 4fde9241    	fmul.2d	v1, v18, v30[0]
100004fd8: 4e61d400    	fadd.2d	v0, v0, v1
100004fdc: 3dc1fff4    	ldr	q20, [sp, #0x7f0]
100004fe0: 3dc16bed    	ldr	q13, [sp, #0x5a0]
100004fe4: 4fcd9281    	fmul.2d	v1, v20, v13[0]
100004fe8: 4e61d400    	fadd.2d	v0, v0, v1
100004fec: 3dc167e2    	ldr	q2, [sp, #0x590]
100004ff0: 3dc26fe1    	ldr	q1, [sp, #0x9b0]
100004ff4: 4fc29021    	fmul.2d	v1, v1, v2[0]
100004ff8: 4e61d400    	fadd.2d	v0, v0, v1
100004ffc: 3dc273e7    	ldr	q7, [sp, #0x9c0]
100005000: 3dc163e3    	ldr	q3, [sp, #0x580]
100005004: 4fc390e1    	fmul.2d	v1, v7, v3[0]
100005008: 4e61d400    	fadd.2d	v0, v0, v1
10000500c: 3dc15ff8    	ldr	q24, [sp, #0x570]
100005010: 3dc2b3e1    	ldr	q1, [sp, #0xac0]
100005014: 4fd89021    	fmul.2d	v1, v1, v24[0]
100005018: 4e61d400    	fadd.2d	v0, v0, v1
10000501c: 3dc1f7f3    	ldr	q19, [sp, #0x7d0]
100005020: 3dc15bf9    	ldr	q25, [sp, #0x560]
100005024: 4fd99261    	fmul.2d	v1, v19, v25[0]
100005028: 4e61d400    	fadd.2d	v0, v0, v1
10000502c: 3dc157fa    	ldr	q26, [sp, #0x550]
100005030: 3dc26be1    	ldr	q1, [sp, #0x9a0]
100005034: 4fda9021    	fmul.2d	v1, v1, v26[0]
100005038: 4e61d400    	fadd.2d	v0, v0, v1
10000503c: 3dc1f3f5    	ldr	q21, [sp, #0x7c0]
100005040: 3dc153e4    	ldr	q4, [sp, #0x540]
100005044: 4fc492a1    	fmul.2d	v1, v21, v4[0]
100005048: 4e61d400    	fadd.2d	v0, v0, v1
10000504c: 3d819be0    	str	q0, [sp, #0x660]
100005050: 3dc22be0    	ldr	q0, [sp, #0x8a0]
100005054: 4fd69000    	fmul.2d	v0, v0, v22[0]
100005058: 3dc22fe1    	ldr	q1, [sp, #0x8b0]
10000505c: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005060: 4e61d400    	fadd.2d	v0, v0, v1
100005064: 4fde91c1    	fmul.2d	v1, v14, v30[0]
100005068: 4e61d400    	fadd.2d	v0, v0, v1
10000506c: 3dc2a7e1    	ldr	q1, [sp, #0xa90]
100005070: 4fcd9021    	fmul.2d	v1, v1, v13[0]
100005074: 4e61d400    	fadd.2d	v0, v0, v1
100005078: 3dc217e1    	ldr	q1, [sp, #0x850]
10000507c: 4fc29021    	fmul.2d	v1, v1, v2[0]
100005080: 4e61d400    	fadd.2d	v0, v0, v1
100005084: 3dc1ebe1    	ldr	q1, [sp, #0x7a0]
100005088: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000508c: 4e61d400    	fadd.2d	v0, v0, v1
100005090: 3dc243e1    	ldr	q1, [sp, #0x900]
100005094: 4fd89021    	fmul.2d	v1, v1, v24[0]
100005098: 4e61d400    	fadd.2d	v0, v0, v1
10000509c: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
1000050a0: 4fd99021    	fmul.2d	v1, v1, v25[0]
1000050a4: 4e61d400    	fadd.2d	v0, v0, v1
1000050a8: 4ea81d0e    	mov.16b	v14, v8
1000050ac: 4fda9101    	fmul.2d	v1, v8, v26[0]
1000050b0: 4e61d400    	fadd.2d	v0, v0, v1
1000050b4: 3dc267fc    	ldr	q28, [sp, #0x990]
1000050b8: 4fc49381    	fmul.2d	v1, v28, v4[0]
1000050bc: 4e61d400    	fadd.2d	v0, v0, v1
1000050c0: 3d8197e0    	str	q0, [sp, #0x650]
1000050c4: 4fd69160    	fmul.2d	v0, v11, v22[0]
1000050c8: 4fdb9181    	fmul.2d	v1, v12, v27[0]
1000050cc: 4e61d400    	fadd.2d	v0, v0, v1
1000050d0: 4fde9141    	fmul.2d	v1, v10, v30[0]
1000050d4: 4e61d400    	fadd.2d	v0, v0, v1
1000050d8: 3dc24be1    	ldr	q1, [sp, #0x920]
1000050dc: 4fcd9021    	fmul.2d	v1, v1, v13[0]
1000050e0: 4e61d400    	fadd.2d	v0, v0, v1
1000050e4: 3dc21be1    	ldr	q1, [sp, #0x860]
1000050e8: 4fc29021    	fmul.2d	v1, v1, v2[0]
1000050ec: 4e61d400    	fadd.2d	v0, v0, v1
1000050f0: 3dc25feb    	ldr	q11, [sp, #0x970]
1000050f4: 4fc39161    	fmul.2d	v1, v11, v3[0]
1000050f8: 4e61d400    	fadd.2d	v0, v0, v1
1000050fc: 3dc247e1    	ldr	q1, [sp, #0x910]
100005100: 4fd89021    	fmul.2d	v1, v1, v24[0]
100005104: 4e61d400    	fadd.2d	v0, v0, v1
100005108: 4fd990c1    	fmul.2d	v1, v6, v25[0]
10000510c: 4e61d400    	fadd.2d	v0, v0, v1
100005110: 4fda92e1    	fmul.2d	v1, v23, v26[0]
100005114: 4e61d400    	fadd.2d	v0, v0, v1
100005118: 3dc2a3e1    	ldr	q1, [sp, #0xa80]
10000511c: 4fc49021    	fmul.2d	v1, v1, v4[0]
100005120: 4e61d400    	fadd.2d	v0, v0, v1
100005124: 3d8193e0    	str	q0, [sp, #0x640]
100005128: 4fd691e0    	fmul.2d	v0, v15, v22[0]
10000512c: 4fdb93a1    	fmul.2d	v1, v29, v27[0]
100005130: 4e61d400    	fadd.2d	v0, v0, v1
100005134: 3dc23be8    	ldr	q8, [sp, #0x8e0]
100005138: 4fde9101    	fmul.2d	v1, v8, v30[0]
10000513c: 4e61d400    	fadd.2d	v0, v0, v1
100005140: 4fcd93e1    	fmul.2d	v1, v31, v13[0]
100005144: 4e61d400    	fadd.2d	v0, v0, v1
100005148: 3dc237e6    	ldr	q6, [sp, #0x8d0]
10000514c: 4fc290c1    	fmul.2d	v1, v6, v2[0]
100005150: 4e61d400    	fadd.2d	v0, v0, v1
100005154: 4fc39121    	fmul.2d	v1, v9, v3[0]
100005158: 4e61d400    	fadd.2d	v0, v0, v1
10000515c: 3dc29be1    	ldr	q1, [sp, #0xa60]
100005160: 4fd89021    	fmul.2d	v1, v1, v24[0]
100005164: 4e61d400    	fadd.2d	v0, v0, v1
100005168: 3dc297e1    	ldr	q1, [sp, #0xa50]
10000516c: 4fd99021    	fmul.2d	v1, v1, v25[0]
100005170: 4e61d400    	fadd.2d	v0, v0, v1
100005174: 3dc233e9    	ldr	q9, [sp, #0x8c0]
100005178: 4fda9121    	fmul.2d	v1, v9, v26[0]
10000517c: 4e61d400    	fadd.2d	v0, v0, v1
100005180: 3dc293e1    	ldr	q1, [sp, #0xa40]
100005184: 4fc49021    	fmul.2d	v1, v1, v4[0]
100005188: 4e61d400    	fadd.2d	v0, v0, v1
10000518c: 3d81bfe0    	str	q0, [sp, #0x6f0]
100005190: 3dc20fe0    	ldr	q0, [sp, #0x830]
100005194: 4fd69000    	fmul.2d	v0, v0, v22[0]
100005198: 3dc27bea    	ldr	q10, [sp, #0x9e0]
10000519c: 4fdb9141    	fmul.2d	v1, v10, v27[0]
1000051a0: 4e61d400    	fadd.2d	v0, v0, v1
1000051a4: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
1000051a8: 4fde9021    	fmul.2d	v1, v1, v30[0]
1000051ac: 4e61d400    	fadd.2d	v0, v0, v1
1000051b0: 4fcd9221    	fmul.2d	v1, v17, v13[0]
1000051b4: 4e61d400    	fadd.2d	v0, v0, v1
1000051b8: 3dc28be1    	ldr	q1, [sp, #0xa20]
1000051bc: 4fc29021    	fmul.2d	v1, v1, v2[0]
1000051c0: 4e61d400    	fadd.2d	v0, v0, v1
1000051c4: 3dc287e1    	ldr	q1, [sp, #0xa10]
1000051c8: 4fc39021    	fmul.2d	v1, v1, v3[0]
1000051cc: 4e61d400    	fadd.2d	v0, v0, v1
1000051d0: 3dc283e1    	ldr	q1, [sp, #0xa00]
1000051d4: 4fd89021    	fmul.2d	v1, v1, v24[0]
1000051d8: 4e61d400    	fadd.2d	v0, v0, v1
1000051dc: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
1000051e0: 4fd99021    	fmul.2d	v1, v1, v25[0]
1000051e4: 4e61d400    	fadd.2d	v0, v0, v1
1000051e8: 3dc27fec    	ldr	q12, [sp, #0x9f0]
1000051ec: 4fda9181    	fmul.2d	v1, v12, v26[0]
1000051f0: 4e61d400    	fadd.2d	v0, v0, v1
1000051f4: 4fc49201    	fmul.2d	v1, v16, v4[0]
1000051f8: 4e61d400    	fadd.2d	v0, v0, v1
1000051fc: 3d80b3e0    	str	q0, [sp, #0x2c0]
100005200: 3dc14be2    	ldr	q2, [sp, #0x520]
100005204: 4fc290a0    	fmul.2d	v0, v5, v2[0]
100005208: 3dc203e5    	ldr	q5, [sp, #0x800]
10000520c: 3dc14fe4    	ldr	q4, [sp, #0x530]
100005210: 4fc490a1    	fmul.2d	v1, v5, v4[0]
100005214: 4e61d400    	fadd.2d	v0, v0, v1
100005218: 3dc143fb    	ldr	q27, [sp, #0x500]
10000521c: 4fdb9241    	fmul.2d	v1, v18, v27[0]
100005220: 4e61d400    	fadd.2d	v0, v0, v1
100005224: 3dc147fa    	ldr	q26, [sp, #0x510]
100005228: 4fda9281    	fmul.2d	v1, v20, v26[0]
10000522c: 4e61d400    	fadd.2d	v0, v0, v1
100005230: 3dc26ff0    	ldr	q16, [sp, #0x9b0]
100005234: 3dc13ffe    	ldr	q30, [sp, #0x4f0]
100005238: 4fde9201    	fmul.2d	v1, v16, v30[0]
10000523c: 4e61d400    	fadd.2d	v0, v0, v1
100005240: 3dc13bfd    	ldr	q29, [sp, #0x4e0]
100005244: 4fdd90e1    	fmul.2d	v1, v7, v29[0]
100005248: 4e61d400    	fadd.2d	v0, v0, v1
10000524c: 3dc2b3f2    	ldr	q18, [sp, #0xac0]
100005250: 3dc137ed    	ldr	q13, [sp, #0x4d0]
100005254: 4fcd9241    	fmul.2d	v1, v18, v13[0]
100005258: 4e61d400    	fadd.2d	v0, v0, v1
10000525c: 3dc133e7    	ldr	q7, [sp, #0x4c0]
100005260: 4fc79261    	fmul.2d	v1, v19, v7[0]
100005264: 4eb31e74    	mov.16b	v20, v19
100005268: 4e61d400    	fadd.2d	v0, v0, v1
10000526c: 3dc26bf1    	ldr	q17, [sp, #0x9a0]
100005270: 3dc12fe3    	ldr	q3, [sp, #0x4b0]
100005274: 4fc39221    	fmul.2d	v1, v17, v3[0]
100005278: 4e61d400    	fadd.2d	v0, v0, v1
10000527c: 3dc12bef    	ldr	q15, [sp, #0x4a0]
100005280: 4fcf92a1    	fmul.2d	v1, v21, v15[0]
100005284: 4e61d400    	fadd.2d	v0, v0, v1
100005288: 3d819fe0    	str	q0, [sp, #0x670]
10000528c: 3dc22be0    	ldr	q0, [sp, #0x8a0]
100005290: 4fc29000    	fmul.2d	v0, v0, v2[0]
100005294: 3dc22fe1    	ldr	q1, [sp, #0x8b0]
100005298: 4fc49021    	fmul.2d	v1, v1, v4[0]
10000529c: 4e61d400    	fadd.2d	v0, v0, v1
1000052a0: 3dc29fe1    	ldr	q1, [sp, #0xa70]
1000052a4: 4fdb9021    	fmul.2d	v1, v1, v27[0]
1000052a8: 4e61d400    	fadd.2d	v0, v0, v1
1000052ac: 3dc2a7e1    	ldr	q1, [sp, #0xa90]
1000052b0: 4fda9021    	fmul.2d	v1, v1, v26[0]
1000052b4: 4e61d400    	fadd.2d	v0, v0, v1
1000052b8: 3dc217e1    	ldr	q1, [sp, #0x850]
1000052bc: 4fde9021    	fmul.2d	v1, v1, v30[0]
1000052c0: 4e61d400    	fadd.2d	v0, v0, v1
1000052c4: 3dc1ebe1    	ldr	q1, [sp, #0x7a0]
1000052c8: 4fdd9021    	fmul.2d	v1, v1, v29[0]
1000052cc: 4e61d400    	fadd.2d	v0, v0, v1
1000052d0: 3dc243e1    	ldr	q1, [sp, #0x900]
1000052d4: 4fcd9021    	fmul.2d	v1, v1, v13[0]
1000052d8: 4e61d400    	fadd.2d	v0, v0, v1
1000052dc: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
1000052e0: 4fc79021    	fmul.2d	v1, v1, v7[0]
1000052e4: 4ea71cff    	mov.16b	v31, v7
1000052e8: 4e61d400    	fadd.2d	v0, v0, v1
1000052ec: 4fc391c1    	fmul.2d	v1, v14, v3[0]
1000052f0: 4e61d400    	fadd.2d	v0, v0, v1
1000052f4: 4fcf9381    	fmul.2d	v1, v28, v15[0]
1000052f8: 4e61d400    	fadd.2d	v0, v0, v1
1000052fc: 3d81a7e0    	str	q0, [sp, #0x690]
100005300: 3dc1dbe0    	ldr	q0, [sp, #0x760]
100005304: 4fc29000    	fmul.2d	v0, v0, v2[0]
100005308: 3dc25be1    	ldr	q1, [sp, #0x960]
10000530c: 4fc49021    	fmul.2d	v1, v1, v4[0]
100005310: 4e61d400    	fadd.2d	v0, v0, v1
100005314: 3dc257e1    	ldr	q1, [sp, #0x950]
100005318: 4fdb9021    	fmul.2d	v1, v1, v27[0]
10000531c: 4e61d400    	fadd.2d	v0, v0, v1
100005320: 3dc24bf6    	ldr	q22, [sp, #0x920]
100005324: 4fda92c1    	fmul.2d	v1, v22, v26[0]
100005328: 4e61d400    	fadd.2d	v0, v0, v1
10000532c: 3dc21bf7    	ldr	q23, [sp, #0x860]
100005330: 4fde92e1    	fmul.2d	v1, v23, v30[0]
100005334: 4e61d400    	fadd.2d	v0, v0, v1
100005338: 4eab1d79    	mov.16b	v25, v11
10000533c: 4fdd9161    	fmul.2d	v1, v11, v29[0]
100005340: 4e61d400    	fadd.2d	v0, v0, v1
100005344: 3dc247f5    	ldr	q21, [sp, #0x910]
100005348: 4fcd92a1    	fmul.2d	v1, v21, v13[0]
10000534c: 4e61d400    	fadd.2d	v0, v0, v1
100005350: 3dc253e1    	ldr	q1, [sp, #0x940]
100005354: 4fc79021    	fmul.2d	v1, v1, v7[0]
100005358: 4e61d400    	fadd.2d	v0, v0, v1
10000535c: 3dc24ff8    	ldr	q24, [sp, #0x930]
100005360: 4fc39301    	fmul.2d	v1, v24, v3[0]
100005364: 4e61d400    	fadd.2d	v0, v0, v1
100005368: 3dc2a3e7    	ldr	q7, [sp, #0xa80]
10000536c: 4fcf90e1    	fmul.2d	v1, v7, v15[0]
100005370: 4e61d400    	fadd.2d	v0, v0, v1
100005374: 3d81c3e0    	str	q0, [sp, #0x700]
100005378: 3dc227e0    	ldr	q0, [sp, #0x890]
10000537c: 4fc29000    	fmul.2d	v0, v0, v2[0]
100005380: 3dc223e1    	ldr	q1, [sp, #0x880]
100005384: 4fc49021    	fmul.2d	v1, v1, v4[0]
100005388: 4e61d400    	fadd.2d	v0, v0, v1
10000538c: 4fdb9101    	fmul.2d	v1, v8, v27[0]
100005390: 4e61d400    	fadd.2d	v0, v0, v1
100005394: 3dc28fe1    	ldr	q1, [sp, #0xa30]
100005398: 4fda9021    	fmul.2d	v1, v1, v26[0]
10000539c: 4e61d400    	fadd.2d	v0, v0, v1
1000053a0: 4fde90c1    	fmul.2d	v1, v6, v30[0]
1000053a4: 4e61d400    	fadd.2d	v0, v0, v1
1000053a8: 3dc21fe1    	ldr	q1, [sp, #0x870]
1000053ac: 4fdd9021    	fmul.2d	v1, v1, v29[0]
1000053b0: 4e61d400    	fadd.2d	v0, v0, v1
1000053b4: 3dc29be1    	ldr	q1, [sp, #0xa60]
1000053b8: 4fcd9021    	fmul.2d	v1, v1, v13[0]
1000053bc: 4e61d400    	fadd.2d	v0, v0, v1
1000053c0: 3dc297e1    	ldr	q1, [sp, #0xa50]
1000053c4: 4fdf9021    	fmul.2d	v1, v1, v31[0]
1000053c8: 4e61d400    	fadd.2d	v0, v0, v1
1000053cc: 4fc39121    	fmul.2d	v1, v9, v3[0]
1000053d0: 4e61d400    	fadd.2d	v0, v0, v1
1000053d4: 3dc293eb    	ldr	q11, [sp, #0xa40]
1000053d8: 4fcf9161    	fmul.2d	v1, v11, v15[0]
1000053dc: 4e61d400    	fadd.2d	v0, v0, v1
1000053e0: 3d81a3e0    	str	q0, [sp, #0x680]
1000053e4: 3dc20fe0    	ldr	q0, [sp, #0x830]
1000053e8: 4fc29000    	fmul.2d	v0, v0, v2[0]
1000053ec: 4fc49141    	fmul.2d	v1, v10, v4[0]
1000053f0: 4e61d400    	fadd.2d	v0, v0, v1
1000053f4: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
1000053f8: 4fdb9021    	fmul.2d	v1, v1, v27[0]
1000053fc: 4e61d400    	fadd.2d	v0, v0, v1
100005400: 3dc277e1    	ldr	q1, [sp, #0x9d0]
100005404: 4fda9021    	fmul.2d	v1, v1, v26[0]
100005408: 4e61d400    	fadd.2d	v0, v0, v1
10000540c: 3dc28be1    	ldr	q1, [sp, #0xa20]
100005410: 4fde9021    	fmul.2d	v1, v1, v30[0]
100005414: 4e61d400    	fadd.2d	v0, v0, v1
100005418: 3dc287e1    	ldr	q1, [sp, #0xa10]
10000541c: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100005420: 4e61d400    	fadd.2d	v0, v0, v1
100005424: 3dc283ea    	ldr	q10, [sp, #0xa00]
100005428: 4fcd9141    	fmul.2d	v1, v10, v13[0]
10000542c: 4e61d400    	fadd.2d	v0, v0, v1
100005430: 3dc2b7ee    	ldr	q14, [sp, #0xad0]
100005434: 4fdf91c1    	fmul.2d	v1, v14, v31[0]
100005438: 4e61d400    	fadd.2d	v0, v0, v1
10000543c: 4fc39181    	fmul.2d	v1, v12, v3[0]
100005440: 4e61d400    	fadd.2d	v0, v0, v1
100005444: 3dc20be1    	ldr	q1, [sp, #0x820]
100005448: 4fcf9021    	fmul.2d	v1, v1, v15[0]
10000544c: 4e61d400    	fadd.2d	v0, v0, v1
100005450: 3d80afe0    	str	q0, [sp, #0x2b0]
100005454: 3dc127fa    	ldr	q26, [sp, #0x490]
100005458: 3dc207e0    	ldr	q0, [sp, #0x810]
10000545c: 4fda9000    	fmul.2d	v0, v0, v26[0]
100005460: 3dc123fb    	ldr	q27, [sp, #0x480]
100005464: 4fdb90a1    	fmul.2d	v1, v5, v27[0]
100005468: 4e61d400    	fadd.2d	v0, v0, v1
10000546c: 3dc1fbe6    	ldr	q6, [sp, #0x7e0]
100005470: 3dc11fe5    	ldr	q5, [sp, #0x470]
100005474: 4fc590c1    	fmul.2d	v1, v6, v5[0]
100005478: 4e61d400    	fadd.2d	v0, v0, v1
10000547c: 3dc11bfc    	ldr	q28, [sp, #0x460]
100005480: 3dc1ffe1    	ldr	q1, [sp, #0x7f0]
100005484: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100005488: 4e61d400    	fadd.2d	v0, v0, v1
10000548c: 3dc117e3    	ldr	q3, [sp, #0x450]
100005490: 4fc39201    	fmul.2d	v1, v16, v3[0]
100005494: 4e61d400    	fadd.2d	v0, v0, v1
100005498: 3dc113f0    	ldr	q16, [sp, #0x440]
10000549c: 3dc273e1    	ldr	q1, [sp, #0x9c0]
1000054a0: 4fd09021    	fmul.2d	v1, v1, v16[0]
1000054a4: 4e61d400    	fadd.2d	v0, v0, v1
1000054a8: 3dc10ffd    	ldr	q29, [sp, #0x430]
1000054ac: 4fdd9241    	fmul.2d	v1, v18, v29[0]
1000054b0: 4e61d400    	fadd.2d	v0, v0, v1
1000054b4: 3dc10bf3    	ldr	q19, [sp, #0x420]
1000054b8: 4fd39281    	fmul.2d	v1, v20, v19[0]
1000054bc: 4e61d400    	fadd.2d	v0, v0, v1
1000054c0: 3dc107f4    	ldr	q20, [sp, #0x410]
1000054c4: 4fd49221    	fmul.2d	v1, v17, v20[0]
1000054c8: 4e61d400    	fadd.2d	v0, v0, v1
1000054cc: 3dc0f7f1    	ldr	q17, [sp, #0x3d0]
1000054d0: 3dc1f3e1    	ldr	q1, [sp, #0x7c0]
1000054d4: 4fd19021    	fmul.2d	v1, v1, v17[0]
1000054d8: 4e61d400    	fadd.2d	v0, v0, v1
1000054dc: 3d8177e0    	str	q0, [sp, #0x5d0]
1000054e0: 3dc213e0    	ldr	q0, [sp, #0x840]
1000054e4: 4fda9000    	fmul.2d	v0, v0, v26[0]
1000054e8: 3dc263e1    	ldr	q1, [sp, #0x980]
1000054ec: 4fdb9021    	fmul.2d	v1, v1, v27[0]
1000054f0: 4e61d400    	fadd.2d	v0, v0, v1
1000054f4: 3dc2bfe1    	ldr	q1, [sp, #0xaf0]
1000054f8: 4fc59021    	fmul.2d	v1, v1, v5[0]
1000054fc: 4ea51cb2    	mov.16b	v18, v5
100005500: 4e61d400    	fadd.2d	v0, v0, v1
100005504: 3dc2abe1    	ldr	q1, [sp, #0xaa0]
100005508: 4fdc9021    	fmul.2d	v1, v1, v28[0]
10000550c: 4e61d400    	fadd.2d	v0, v0, v1
100005510: 3dc1dfe1    	ldr	q1, [sp, #0x770]
100005514: 4fc39021    	fmul.2d	v1, v1, v3[0]
100005518: 4e61d400    	fadd.2d	v0, v0, v1
10000551c: 3dc23fe2    	ldr	q2, [sp, #0x8f0]
100005520: 4fd09041    	fmul.2d	v1, v2, v16[0]
100005524: 4e61d400    	fadd.2d	v0, v0, v1
100005528: 3dc1d7e4    	ldr	q4, [sp, #0x750]
10000552c: 4fdd9081    	fmul.2d	v1, v4, v29[0]
100005530: 4e61d400    	fadd.2d	v0, v0, v1
100005534: 3dc1e7e1    	ldr	q1, [sp, #0x790]
100005538: 4fd39021    	fmul.2d	v1, v1, v19[0]
10000553c: 4e61d400    	fadd.2d	v0, v0, v1
100005540: 3dc1e3e1    	ldr	q1, [sp, #0x780]
100005544: 4fd49021    	fmul.2d	v1, v1, v20[0]
100005548: 4e61d400    	fadd.2d	v0, v0, v1
10000554c: 3dc2afe1    	ldr	q1, [sp, #0xab0]
100005550: 4fd19021    	fmul.2d	v1, v1, v17[0]
100005554: 4e61d400    	fadd.2d	v0, v0, v1
100005558: 3d814be0    	str	q0, [sp, #0x520]
10000555c: 3dc1dbe8    	ldr	q8, [sp, #0x760]
100005560: 4fda9100    	fmul.2d	v0, v8, v26[0]
100005564: 3dc25bec    	ldr	q12, [sp, #0x960]
100005568: 4fdb9181    	fmul.2d	v1, v12, v27[0]
10000556c: 4e61d400    	fadd.2d	v0, v0, v1
100005570: 3dc257e5    	ldr	q5, [sp, #0x950]
100005574: 4fd290a1    	fmul.2d	v1, v5, v18[0]
100005578: 4e61d400    	fadd.2d	v0, v0, v1
10000557c: 4fdc92c1    	fmul.2d	v1, v22, v28[0]
100005580: 4e61d400    	fadd.2d	v0, v0, v1
100005584: 4fc392e1    	fmul.2d	v1, v23, v3[0]
100005588: 4e61d400    	fadd.2d	v0, v0, v1
10000558c: 4fd09321    	fmul.2d	v1, v25, v16[0]
100005590: 4e61d400    	fadd.2d	v0, v0, v1
100005594: 4fdd92a1    	fmul.2d	v1, v21, v29[0]
100005598: 4e61d400    	fadd.2d	v0, v0, v1
10000559c: 3dc253e9    	ldr	q9, [sp, #0x940]
1000055a0: 4fd39121    	fmul.2d	v1, v9, v19[0]
1000055a4: 4e61d400    	fadd.2d	v0, v0, v1
1000055a8: 4fd49301    	fmul.2d	v1, v24, v20[0]
1000055ac: 4e61d400    	fadd.2d	v0, v0, v1
1000055b0: 4fd190e1    	fmul.2d	v1, v7, v17[0]
1000055b4: 4e61d400    	fadd.2d	v0, v0, v1
1000055b8: 3d818fe0    	str	q0, [sp, #0x630]
1000055bc: 3dc227e0    	ldr	q0, [sp, #0x890]
1000055c0: 4fda9000    	fmul.2d	v0, v0, v26[0]
1000055c4: 3dc223f7    	ldr	q23, [sp, #0x880]
1000055c8: 4fdb92e1    	fmul.2d	v1, v23, v27[0]
1000055cc: 4e61d400    	fadd.2d	v0, v0, v1
1000055d0: 3dc23bf9    	ldr	q25, [sp, #0x8e0]
1000055d4: 4fd29321    	fmul.2d	v1, v25, v18[0]
1000055d8: 4e61d400    	fadd.2d	v0, v0, v1
1000055dc: 3dc28ff6    	ldr	q22, [sp, #0xa30]
1000055e0: 4fdc92c1    	fmul.2d	v1, v22, v28[0]
1000055e4: 4e61d400    	fadd.2d	v0, v0, v1
1000055e8: 3dc237f5    	ldr	q21, [sp, #0x8d0]
1000055ec: 4fc392a1    	fmul.2d	v1, v21, v3[0]
1000055f0: 4e61d400    	fadd.2d	v0, v0, v1
1000055f4: 3dc21ffe    	ldr	q30, [sp, #0x870]
1000055f8: 4fd093c1    	fmul.2d	v1, v30, v16[0]
1000055fc: 4e61d400    	fadd.2d	v0, v0, v1
100005600: 3dc29bff    	ldr	q31, [sp, #0xa60]
100005604: 4fdd93e1    	fmul.2d	v1, v31, v29[0]
100005608: 4e61d400    	fadd.2d	v0, v0, v1
10000560c: 3dc297ed    	ldr	q13, [sp, #0xa50]
100005610: 4fd391a1    	fmul.2d	v1, v13, v19[0]
100005614: 4e61d400    	fadd.2d	v0, v0, v1
100005618: 3dc233ef    	ldr	q15, [sp, #0x8c0]
10000561c: 4fd491e1    	fmul.2d	v1, v15, v20[0]
100005620: 4e61d400    	fadd.2d	v0, v0, v1
100005624: 4fd19161    	fmul.2d	v1, v11, v17[0]
100005628: 4e61d400    	fadd.2d	v0, v0, v1
10000562c: 3d8173e0    	str	q0, [sp, #0x5c0]
100005630: 3dc20feb    	ldr	q11, [sp, #0x830]
100005634: 4fda9160    	fmul.2d	v0, v11, v26[0]
100005638: 3dc27be1    	ldr	q1, [sp, #0x9e0]
10000563c: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005640: 4e61d400    	fadd.2d	v0, v0, v1
100005644: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
100005648: 4fd29021    	fmul.2d	v1, v1, v18[0]
10000564c: 4e61d400    	fadd.2d	v0, v0, v1
100005650: 3dc277e1    	ldr	q1, [sp, #0x9d0]
100005654: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100005658: 4e61d400    	fadd.2d	v0, v0, v1
10000565c: 3dc28be1    	ldr	q1, [sp, #0xa20]
100005660: 4fc39021    	fmul.2d	v1, v1, v3[0]
100005664: 4e61d400    	fadd.2d	v0, v0, v1
100005668: 3dc287e1    	ldr	q1, [sp, #0xa10]
10000566c: 4fd09021    	fmul.2d	v1, v1, v16[0]
100005670: 4e61d400    	fadd.2d	v0, v0, v1
100005674: 4fdd9141    	fmul.2d	v1, v10, v29[0]
100005678: 4e61d400    	fadd.2d	v0, v0, v1
10000567c: 4fd391c1    	fmul.2d	v1, v14, v19[0]
100005680: 4e61d400    	fadd.2d	v0, v0, v1
100005684: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
100005688: 4fd49021    	fmul.2d	v1, v1, v20[0]
10000568c: 4e61d400    	fadd.2d	v0, v0, v1
100005690: 3dc20be1    	ldr	q1, [sp, #0x820]
100005694: 4fd19021    	fmul.2d	v1, v1, v17[0]
100005698: 4e61d400    	fadd.2d	v0, v0, v1
10000569c: 3d80abe0    	str	q0, [sp, #0x2a0]
1000056a0: ad5d4bfb    	ldp	q27, q18, [sp, #0x3a0]
1000056a4: 3dc207f8    	ldr	q24, [sp, #0x810]
1000056a8: 4fd29300    	fmul.2d	v0, v24, v18[0]
1000056ac: 3dc203ea    	ldr	q10, [sp, #0x800]
1000056b0: 4fdb9141    	fmul.2d	v1, v10, v27[0]
1000056b4: 4e61d400    	fadd.2d	v0, v0, v1
1000056b8: 3dc0dff0    	ldr	q16, [sp, #0x370]
1000056bc: 4fd090c1    	fmul.2d	v1, v6, v16[0]
1000056c0: 4e61d400    	fadd.2d	v0, v0, v1
1000056c4: 3dc1ffe7    	ldr	q7, [sp, #0x7f0]
1000056c8: 3dc0e7e3    	ldr	q3, [sp, #0x390]
1000056cc: 4fc390e1    	fmul.2d	v1, v7, v3[0]
1000056d0: 4e61d400    	fadd.2d	v0, v0, v1
1000056d4: ad5a9bf1    	ldp	q17, q6, [sp, #0x350]
1000056d8: 3dc26fe1    	ldr	q1, [sp, #0x9b0]
1000056dc: 4fc69021    	fmul.2d	v1, v1, v6[0]
1000056e0: 4e61d400    	fadd.2d	v0, v0, v1
1000056e4: 3dc273e1    	ldr	q1, [sp, #0x9c0]
1000056e8: 4fd19021    	fmul.2d	v1, v1, v17[0]
1000056ec: 4e61d400    	fadd.2d	v0, v0, v1
1000056f0: ad59cff4    	ldp	q20, q19, [sp, #0x330]
1000056f4: 3dc2b3e1    	ldr	q1, [sp, #0xac0]
1000056f8: 4fd39021    	fmul.2d	v1, v1, v19[0]
1000056fc: 4e61d400    	fadd.2d	v0, v0, v1
100005700: 3dc1f7e1    	ldr	q1, [sp, #0x7d0]
100005704: 4fd49021    	fmul.2d	v1, v1, v20[0]
100005708: 4e61d400    	fadd.2d	v0, v0, v1
10000570c: ad58f3fd    	ldp	q29, q28, [sp, #0x310]
100005710: 3dc26be1    	ldr	q1, [sp, #0x9a0]
100005714: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100005718: 4e61d400    	fadd.2d	v0, v0, v1
10000571c: 3dc1f3e1    	ldr	q1, [sp, #0x7c0]
100005720: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100005724: 4e61d400    	fadd.2d	v0, v0, v1
100005728: 3d818be0    	str	q0, [sp, #0x620]
10000572c: 3dc213fa    	ldr	q26, [sp, #0x840]
100005730: 4fd29340    	fmul.2d	v0, v26, v18[0]
100005734: 3dc263e1    	ldr	q1, [sp, #0x980]
100005738: 4fdb9021    	fmul.2d	v1, v1, v27[0]
10000573c: 4e61d400    	fadd.2d	v0, v0, v1
100005740: 3dc2bfe1    	ldr	q1, [sp, #0xaf0]
100005744: 4fd09021    	fmul.2d	v1, v1, v16[0]
100005748: 4e61d400    	fadd.2d	v0, v0, v1
10000574c: 3dc2abe1    	ldr	q1, [sp, #0xaa0]
100005750: 4fc39021    	fmul.2d	v1, v1, v3[0]
100005754: 4e61d400    	fadd.2d	v0, v0, v1
100005758: 3dc1dfee    	ldr	q14, [sp, #0x770]
10000575c: 4fc691c1    	fmul.2d	v1, v14, v6[0]
100005760: 4e61d400    	fadd.2d	v0, v0, v1
100005764: 4fd19041    	fmul.2d	v1, v2, v17[0]
100005768: 4e61d400    	fadd.2d	v0, v0, v1
10000576c: 4fd39081    	fmul.2d	v1, v4, v19[0]
100005770: 4e61d400    	fadd.2d	v0, v0, v1
100005774: 3dc1e7e1    	ldr	q1, [sp, #0x790]
100005778: 4fd49021    	fmul.2d	v1, v1, v20[0]
10000577c: 4e61d400    	fadd.2d	v0, v0, v1
100005780: 3dc1e3e1    	ldr	q1, [sp, #0x780]
100005784: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100005788: 4e61d400    	fadd.2d	v0, v0, v1
10000578c: 3dc2afe1    	ldr	q1, [sp, #0xab0]
100005790: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100005794: 4e61d400    	fadd.2d	v0, v0, v1
100005798: 3d816fe0    	str	q0, [sp, #0x5b0]
10000579c: 4fd29100    	fmul.2d	v0, v8, v18[0]
1000057a0: 4fdb9181    	fmul.2d	v1, v12, v27[0]
1000057a4: 4e61d400    	fadd.2d	v0, v0, v1
1000057a8: 4fd090a1    	fmul.2d	v1, v5, v16[0]
1000057ac: 4e61d400    	fadd.2d	v0, v0, v1
1000057b0: 3dc24be1    	ldr	q1, [sp, #0x920]
1000057b4: 4fc39021    	fmul.2d	v1, v1, v3[0]
1000057b8: 4e61d400    	fadd.2d	v0, v0, v1
1000057bc: 3dc21be1    	ldr	q1, [sp, #0x860]
1000057c0: 4fc69021    	fmul.2d	v1, v1, v6[0]
1000057c4: 4e61d400    	fadd.2d	v0, v0, v1
1000057c8: 3dc25fe1    	ldr	q1, [sp, #0x970]
1000057cc: 4fd19021    	fmul.2d	v1, v1, v17[0]
1000057d0: 4e61d400    	fadd.2d	v0, v0, v1
1000057d4: 3dc247e1    	ldr	q1, [sp, #0x910]
1000057d8: 4fd39021    	fmul.2d	v1, v1, v19[0]
1000057dc: 4e61d400    	fadd.2d	v0, v0, v1
1000057e0: 4fd49121    	fmul.2d	v1, v9, v20[0]
1000057e4: 4e61d400    	fadd.2d	v0, v0, v1
1000057e8: 3dc24fe1    	ldr	q1, [sp, #0x930]
1000057ec: 4fdc9021    	fmul.2d	v1, v1, v28[0]
1000057f0: 4e61d400    	fadd.2d	v0, v0, v1
1000057f4: 3dc2a3e1    	ldr	q1, [sp, #0xa80]
1000057f8: 4fdd9021    	fmul.2d	v1, v1, v29[0]
1000057fc: 4e61d400    	fadd.2d	v0, v0, v1
100005800: 3d816be0    	str	q0, [sp, #0x5a0]
100005804: 3dc227e8    	ldr	q8, [sp, #0x890]
100005808: 4fd29100    	fmul.2d	v0, v8, v18[0]
10000580c: 4fdb92e1    	fmul.2d	v1, v23, v27[0]
100005810: 4e61d400    	fadd.2d	v0, v0, v1
100005814: 4fd09321    	fmul.2d	v1, v25, v16[0]
100005818: 4e61d400    	fadd.2d	v0, v0, v1
10000581c: 4fc392c1    	fmul.2d	v1, v22, v3[0]
100005820: 4e61d400    	fadd.2d	v0, v0, v1
100005824: 4fc692a1    	fmul.2d	v1, v21, v6[0]
100005828: 4e61d400    	fadd.2d	v0, v0, v1
10000582c: 4fd193c1    	fmul.2d	v1, v30, v17[0]
100005830: 4e61d400    	fadd.2d	v0, v0, v1
100005834: 4fd393e1    	fmul.2d	v1, v31, v19[0]
100005838: 4e61d400    	fadd.2d	v0, v0, v1
10000583c: 4fd491a1    	fmul.2d	v1, v13, v20[0]
100005840: 4e61d400    	fadd.2d	v0, v0, v1
100005844: 4fdc91e1    	fmul.2d	v1, v15, v28[0]
100005848: 4e61d400    	fadd.2d	v0, v0, v1
10000584c: 3dc293f9    	ldr	q25, [sp, #0xa40]
100005850: 4fdd9321    	fmul.2d	v1, v25, v29[0]
100005854: 4e61d400    	fadd.2d	v0, v0, v1
100005858: 3d8167e0    	str	q0, [sp, #0x590]
10000585c: 4eab1d7f    	mov.16b	v31, v11
100005860: 4fd29160    	fmul.2d	v0, v11, v18[0]
100005864: 3dc27be9    	ldr	q9, [sp, #0x9e0]
100005868: 4fdb9121    	fmul.2d	v1, v9, v27[0]
10000586c: 4e61d400    	fadd.2d	v0, v0, v1
100005870: 3dc2c3eb    	ldr	q11, [sp, #0xb00]
100005874: 4fd09161    	fmul.2d	v1, v11, v16[0]
100005878: 4e61d400    	fadd.2d	v0, v0, v1
10000587c: 3dc277ec    	ldr	q12, [sp, #0x9d0]
100005880: 4fc39181    	fmul.2d	v1, v12, v3[0]
100005884: 4e61d400    	fadd.2d	v0, v0, v1
100005888: 3dc28bed    	ldr	q13, [sp, #0xa20]
10000588c: 4fc691a1    	fmul.2d	v1, v13, v6[0]
100005890: 4e61d400    	fadd.2d	v0, v0, v1
100005894: 3dc287ef    	ldr	q15, [sp, #0xa10]
100005898: 4fd191e1    	fmul.2d	v1, v15, v17[0]
10000589c: 4e61d400    	fadd.2d	v0, v0, v1
1000058a0: 3dc283e1    	ldr	q1, [sp, #0xa00]
1000058a4: 4fd39021    	fmul.2d	v1, v1, v19[0]
1000058a8: 4e61d400    	fadd.2d	v0, v0, v1
1000058ac: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
1000058b0: 4fd49021    	fmul.2d	v1, v1, v20[0]
1000058b4: 4e61d400    	fadd.2d	v0, v0, v1
1000058b8: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
1000058bc: 4fdc9021    	fmul.2d	v1, v1, v28[0]
1000058c0: 4e61d400    	fadd.2d	v0, v0, v1
1000058c4: 3dc20be1    	ldr	q1, [sp, #0x820]
1000058c8: 4fdd9021    	fmul.2d	v1, v1, v29[0]
1000058cc: 4e61d400    	fadd.2d	v0, v0, v1
1000058d0: 3d80a7e0    	str	q0, [sp, #0x290]
1000058d4: ad57c7e6    	ldp	q6, q17, [sp, #0x2f0]
1000058d8: 4fd19300    	fmul.2d	v0, v24, v17[0]
1000058dc: 4fc69141    	fmul.2d	v1, v10, v6[0]
1000058e0: 4e61d400    	fadd.2d	v0, v0, v1
1000058e4: 3dc0a3f3    	ldr	q19, [sp, #0x280]
1000058e8: 3dc1fbe1    	ldr	q1, [sp, #0x7e0]
1000058ec: 4fd39021    	fmul.2d	v1, v1, v19[0]
1000058f0: 4e61d400    	fadd.2d	v0, v0, v1
1000058f4: ad52d7f6    	ldp	q22, q21, [sp, #0x250]
1000058f8: 4fd590e1    	fmul.2d	v1, v7, v21[0]
1000058fc: 4e61d400    	fadd.2d	v0, v0, v1
100005900: 3dc26ff0    	ldr	q16, [sp, #0x9b0]
100005904: 4fd69201    	fmul.2d	v1, v16, v22[0]
100005908: 4e61d400    	fadd.2d	v0, v0, v1
10000590c: ad51effc    	ldp	q28, q27, [sp, #0x230]
100005910: 3dc273e1    	ldr	q1, [sp, #0x9c0]
100005914: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005918: 4e61d400    	fadd.2d	v0, v0, v1
10000591c: 3dc2b3e1    	ldr	q1, [sp, #0xac0]
100005920: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100005924: 4e61d400    	fadd.2d	v0, v0, v1
100005928: ad4ff7f8    	ldp	q24, q29, [sp, #0x1f0]
10000592c: 3dc1f7e1    	ldr	q1, [sp, #0x7d0]
100005930: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100005934: 4e61d400    	fadd.2d	v0, v0, v1
100005938: 3dc26be3    	ldr	q3, [sp, #0x9a0]
10000593c: 4fd89061    	fmul.2d	v1, v3, v24[0]
100005940: 4e61d400    	fadd.2d	v0, v0, v1
100005944: 3dc07bfe    	ldr	q30, [sp, #0x1e0]
100005948: 3dc1f3e1    	ldr	q1, [sp, #0x7c0]
10000594c: 4fde9021    	fmul.2d	v1, v1, v30[0]
100005950: 4e61d400    	fadd.2d	v0, v0, v1
100005954: 3d812fe0    	str	q0, [sp, #0x4b0]
100005958: 4fd19340    	fmul.2d	v0, v26, v17[0]
10000595c: 3dc263f7    	ldr	q23, [sp, #0x980]
100005960: 4fc692e1    	fmul.2d	v1, v23, v6[0]
100005964: 4e61d400    	fadd.2d	v0, v0, v1
100005968: 3dc2bfe1    	ldr	q1, [sp, #0xaf0]
10000596c: 4fd39021    	fmul.2d	v1, v1, v19[0]
100005970: 4e61d400    	fadd.2d	v0, v0, v1
100005974: 3dc2abe1    	ldr	q1, [sp, #0xaa0]
100005978: 4fd59021    	fmul.2d	v1, v1, v21[0]
10000597c: 4e61d400    	fadd.2d	v0, v0, v1
100005980: 4fd691c1    	fmul.2d	v1, v14, v22[0]
100005984: 4e61d400    	fadd.2d	v0, v0, v1
100005988: 3dc23fe1    	ldr	q1, [sp, #0x8f0]
10000598c: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005990: 4e61d400    	fadd.2d	v0, v0, v1
100005994: 3dc1d7e1    	ldr	q1, [sp, #0x750]
100005998: 4fdc9021    	fmul.2d	v1, v1, v28[0]
10000599c: 4e61d400    	fadd.2d	v0, v0, v1
1000059a0: 3dc1e7e7    	ldr	q7, [sp, #0x790]
1000059a4: 4fdd90e1    	fmul.2d	v1, v7, v29[0]
1000059a8: 4e61d400    	fadd.2d	v0, v0, v1
1000059ac: 3dc1e3e5    	ldr	q5, [sp, #0x780]
1000059b0: 4fd890a1    	fmul.2d	v1, v5, v24[0]
1000059b4: 4e61d400    	fadd.2d	v0, v0, v1
1000059b8: 3dc2afe1    	ldr	q1, [sp, #0xab0]
1000059bc: 4fde9021    	fmul.2d	v1, v1, v30[0]
1000059c0: 4e61d400    	fadd.2d	v0, v0, v1
1000059c4: 3d8163e0    	str	q0, [sp, #0x580]
1000059c8: 3dc22be0    	ldr	q0, [sp, #0x8a0]
1000059cc: 4fd19000    	fmul.2d	v0, v0, v17[0]
1000059d0: 3dc22fe1    	ldr	q1, [sp, #0x8b0]
1000059d4: 4fc69021    	fmul.2d	v1, v1, v6[0]
1000059d8: 4e61d400    	fadd.2d	v0, v0, v1
1000059dc: 3dc29ff4    	ldr	q20, [sp, #0xa70]
1000059e0: 4fd39281    	fmul.2d	v1, v20, v19[0]
1000059e4: 4e61d400    	fadd.2d	v0, v0, v1
1000059e8: 3dc2a7ea    	ldr	q10, [sp, #0xa90]
1000059ec: 4fd59141    	fmul.2d	v1, v10, v21[0]
1000059f0: 4e61d400    	fadd.2d	v0, v0, v1
1000059f4: 3dc217ee    	ldr	q14, [sp, #0x850]
1000059f8: 4fd691c1    	fmul.2d	v1, v14, v22[0]
1000059fc: 4e61d400    	fadd.2d	v0, v0, v1
100005a00: 3dc1ebe1    	ldr	q1, [sp, #0x7a0]
100005a04: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005a08: 4e61d400    	fadd.2d	v0, v0, v1
100005a0c: 3dc243e1    	ldr	q1, [sp, #0x900]
100005a10: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100005a14: 4e61d400    	fadd.2d	v0, v0, v1
100005a18: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
100005a1c: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100005a20: 4e61d400    	fadd.2d	v0, v0, v1
100005a24: 3dc1effa    	ldr	q26, [sp, #0x7b0]
100005a28: 4fd89341    	fmul.2d	v1, v26, v24[0]
100005a2c: 4e61d400    	fadd.2d	v0, v0, v1
100005a30: 3dc267e2    	ldr	q2, [sp, #0x990]
100005a34: 4fde9041    	fmul.2d	v1, v2, v30[0]
100005a38: 4e61d400    	fadd.2d	v0, v0, v1
100005a3c: 3d815fe0    	str	q0, [sp, #0x570]
100005a40: 4fd19100    	fmul.2d	v0, v8, v17[0]
100005a44: 3dc223e1    	ldr	q1, [sp, #0x880]
100005a48: 4fc69021    	fmul.2d	v1, v1, v6[0]
100005a4c: 4e61d400    	fadd.2d	v0, v0, v1
100005a50: 3dc23be1    	ldr	q1, [sp, #0x8e0]
100005a54: 4fd39021    	fmul.2d	v1, v1, v19[0]
100005a58: 4e61d400    	fadd.2d	v0, v0, v1
100005a5c: 3dc28fe1    	ldr	q1, [sp, #0xa30]
100005a60: 4fd59021    	fmul.2d	v1, v1, v21[0]
100005a64: 4e61d400    	fadd.2d	v0, v0, v1
100005a68: 3dc237e1    	ldr	q1, [sp, #0x8d0]
100005a6c: 4fd69021    	fmul.2d	v1, v1, v22[0]
100005a70: 4e61d400    	fadd.2d	v0, v0, v1
100005a74: 3dc21fe1    	ldr	q1, [sp, #0x870]
100005a78: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005a7c: 4e61d400    	fadd.2d	v0, v0, v1
100005a80: 3dc29be1    	ldr	q1, [sp, #0xa60]
100005a84: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100005a88: 4e61d400    	fadd.2d	v0, v0, v1
100005a8c: 3dc297e1    	ldr	q1, [sp, #0xa50]
100005a90: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100005a94: 4e61d400    	fadd.2d	v0, v0, v1
100005a98: 3dc233e1    	ldr	q1, [sp, #0x8c0]
100005a9c: 4fd89021    	fmul.2d	v1, v1, v24[0]
100005aa0: 4e61d400    	fadd.2d	v0, v0, v1
100005aa4: 4fde9321    	fmul.2d	v1, v25, v30[0]
100005aa8: 4e61d400    	fadd.2d	v0, v0, v1
100005aac: 3d815be0    	str	q0, [sp, #0x560]
100005ab0: 4fd193e0    	fmul.2d	v0, v31, v17[0]
100005ab4: 4fc69121    	fmul.2d	v1, v9, v6[0]
100005ab8: 4e61d400    	fadd.2d	v0, v0, v1
100005abc: 4fd39161    	fmul.2d	v1, v11, v19[0]
100005ac0: 4e61d400    	fadd.2d	v0, v0, v1
100005ac4: 4fd59181    	fmul.2d	v1, v12, v21[0]
100005ac8: 4e61d400    	fadd.2d	v0, v0, v1
100005acc: 4fd691a1    	fmul.2d	v1, v13, v22[0]
100005ad0: 4e61d400    	fadd.2d	v0, v0, v1
100005ad4: 4fdb91e1    	fmul.2d	v1, v15, v27[0]
100005ad8: 4e61d400    	fadd.2d	v0, v0, v1
100005adc: 3dc283ff    	ldr	q31, [sp, #0xa00]
100005ae0: 4fdc93e1    	fmul.2d	v1, v31, v28[0]
100005ae4: 4e61d400    	fadd.2d	v0, v0, v1
100005ae8: 3dc2b7e8    	ldr	q8, [sp, #0xad0]
100005aec: 4fdd9101    	fmul.2d	v1, v8, v29[0]
100005af0: 4e61d400    	fadd.2d	v0, v0, v1
100005af4: 3dc27fe9    	ldr	q9, [sp, #0x9f0]
100005af8: 4fd89121    	fmul.2d	v1, v9, v24[0]
100005afc: 4e61d400    	fadd.2d	v0, v0, v1
100005b00: 3dc20bf8    	ldr	q24, [sp, #0x820]
100005b04: 4fde9301    	fmul.2d	v1, v24, v30[0]
100005b08: 4e61d400    	fadd.2d	v0, v0, v1
100005b0c: 3d80f7e0    	str	q0, [sp, #0x3d0]
100005b10: ad4e4bf3    	ldp	q19, q18, [sp, #0x1c0]
100005b14: 3dc207e4    	ldr	q4, [sp, #0x810]
100005b18: 4fd29080    	fmul.2d	v0, v4, v18[0]
100005b1c: 3dc203e6    	ldr	q6, [sp, #0x800]
100005b20: 4fd390c1    	fmul.2d	v1, v6, v19[0]
100005b24: 4e61d400    	fadd.2d	v0, v0, v1
100005b28: ad4d57f6    	ldp	q22, q21, [sp, #0x1a0]
100005b2c: 3dc1fbec    	ldr	q12, [sp, #0x7e0]
100005b30: 4fd59181    	fmul.2d	v1, v12, v21[0]
100005b34: 4e61d400    	fadd.2d	v0, v0, v1
100005b38: 3dc1fff1    	ldr	q17, [sp, #0x7f0]
100005b3c: 4fd69221    	fmul.2d	v1, v17, v22[0]
100005b40: 4e61d400    	fadd.2d	v0, v0, v1
100005b44: 3dc067f9    	ldr	q25, [sp, #0x190]
100005b48: 4fd99201    	fmul.2d	v1, v16, v25[0]
100005b4c: 4e61d400    	fadd.2d	v0, v0, v1
100005b50: 3dc273eb    	ldr	q11, [sp, #0x9c0]
100005b54: ad4bc3fb    	ldp	q27, q16, [sp, #0x170]
100005b58: 4fd09161    	fmul.2d	v1, v11, v16[0]
100005b5c: 4e61d400    	fadd.2d	v0, v0, v1
100005b60: 3dc2b3e1    	ldr	q1, [sp, #0xac0]
100005b64: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005b68: 4e61d400    	fadd.2d	v0, v0, v1
100005b6c: ad4af3fd    	ldp	q29, q28, [sp, #0x150]
100005b70: 3dc1f7ef    	ldr	q15, [sp, #0x7d0]
100005b74: 4fdc91e1    	fmul.2d	v1, v15, v28[0]
100005b78: 4e61d400    	fadd.2d	v0, v0, v1
100005b7c: 4fdd9061    	fmul.2d	v1, v3, v29[0]
100005b80: 4e61d400    	fadd.2d	v0, v0, v1
100005b84: 3dc053fe    	ldr	q30, [sp, #0x140]
100005b88: 3dc1f3ed    	ldr	q13, [sp, #0x7c0]
100005b8c: 4fde91a1    	fmul.2d	v1, v13, v30[0]
100005b90: 4e61d400    	fadd.2d	v0, v0, v1
100005b94: 3d812be0    	str	q0, [sp, #0x4a0]
100005b98: 3dc213e0    	ldr	q0, [sp, #0x840]
100005b9c: 4fd29000    	fmul.2d	v0, v0, v18[0]
100005ba0: 4fd392e1    	fmul.2d	v1, v23, v19[0]
100005ba4: 4e61d400    	fadd.2d	v0, v0, v1
100005ba8: 3dc2bfe1    	ldr	q1, [sp, #0xaf0]
100005bac: 4fd59021    	fmul.2d	v1, v1, v21[0]
100005bb0: 4e61d400    	fadd.2d	v0, v0, v1
100005bb4: 3dc2abe1    	ldr	q1, [sp, #0xaa0]
100005bb8: 4fd69021    	fmul.2d	v1, v1, v22[0]
100005bbc: 4e61d400    	fadd.2d	v0, v0, v1
100005bc0: 3dc1dfe1    	ldr	q1, [sp, #0x770]
100005bc4: 4fd99021    	fmul.2d	v1, v1, v25[0]
100005bc8: 4e61d400    	fadd.2d	v0, v0, v1
100005bcc: 3dc23fe1    	ldr	q1, [sp, #0x8f0]
100005bd0: 4fd09021    	fmul.2d	v1, v1, v16[0]
100005bd4: 4eb01e03    	mov.16b	v3, v16
100005bd8: 4e61d400    	fadd.2d	v0, v0, v1
100005bdc: 3dc1d7e1    	ldr	q1, [sp, #0x750]
100005be0: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005be4: 4e61d400    	fadd.2d	v0, v0, v1
100005be8: 4fdc90e1    	fmul.2d	v1, v7, v28[0]
100005bec: 4e61d400    	fadd.2d	v0, v0, v1
100005bf0: 4fdd90a1    	fmul.2d	v1, v5, v29[0]
100005bf4: 4e61d400    	fadd.2d	v0, v0, v1
100005bf8: 3dc2afe1    	ldr	q1, [sp, #0xab0]
100005bfc: 4fde9021    	fmul.2d	v1, v1, v30[0]
100005c00: 4e61d400    	fadd.2d	v0, v0, v1
100005c04: 3d8127e0    	str	q0, [sp, #0x490]
100005c08: 3dc22be7    	ldr	q7, [sp, #0x8a0]
100005c0c: 4fd290e0    	fmul.2d	v0, v7, v18[0]
100005c10: 3dc22fe1    	ldr	q1, [sp, #0x8b0]
100005c14: 4fd39021    	fmul.2d	v1, v1, v19[0]
100005c18: 4e61d400    	fadd.2d	v0, v0, v1
100005c1c: 4fd59281    	fmul.2d	v1, v20, v21[0]
100005c20: 4e61d400    	fadd.2d	v0, v0, v1
100005c24: 4fd69141    	fmul.2d	v1, v10, v22[0]
100005c28: 4e61d400    	fadd.2d	v0, v0, v1
100005c2c: 4fd991c1    	fmul.2d	v1, v14, v25[0]
100005c30: 4e61d400    	fadd.2d	v0, v0, v1
100005c34: 3dc1ebf0    	ldr	q16, [sp, #0x7a0]
100005c38: 4fc39201    	fmul.2d	v1, v16, v3[0]
100005c3c: 4e61d400    	fadd.2d	v0, v0, v1
100005c40: 3dc243e1    	ldr	q1, [sp, #0x900]
100005c44: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005c48: 4e61d400    	fadd.2d	v0, v0, v1
100005c4c: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
100005c50: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100005c54: 4e61d400    	fadd.2d	v0, v0, v1
100005c58: 4fdd9341    	fmul.2d	v1, v26, v29[0]
100005c5c: 4e61d400    	fadd.2d	v0, v0, v1
100005c60: 4fde9041    	fmul.2d	v1, v2, v30[0]
100005c64: 4e61d400    	fadd.2d	v0, v0, v1
100005c68: 3d8157e0    	str	q0, [sp, #0x550]
100005c6c: 3dc227e0    	ldr	q0, [sp, #0x890]
100005c70: 4fd29000    	fmul.2d	v0, v0, v18[0]
100005c74: 3dc223e1    	ldr	q1, [sp, #0x880]
100005c78: 4fd39021    	fmul.2d	v1, v1, v19[0]
100005c7c: 4e61d400    	fadd.2d	v0, v0, v1
100005c80: 3dc23be1    	ldr	q1, [sp, #0x8e0]
100005c84: 4fd59021    	fmul.2d	v1, v1, v21[0]
100005c88: 4e61d400    	fadd.2d	v0, v0, v1
100005c8c: 3dc28fe1    	ldr	q1, [sp, #0xa30]
100005c90: 4fd69021    	fmul.2d	v1, v1, v22[0]
100005c94: 4e61d400    	fadd.2d	v0, v0, v1
100005c98: 3dc237e1    	ldr	q1, [sp, #0x8d0]
100005c9c: 4fd99021    	fmul.2d	v1, v1, v25[0]
100005ca0: 4e61d400    	fadd.2d	v0, v0, v1
100005ca4: 3dc21fe1    	ldr	q1, [sp, #0x870]
100005ca8: 4fc39021    	fmul.2d	v1, v1, v3[0]
100005cac: 4e61d400    	fadd.2d	v0, v0, v1
100005cb0: 3dc29be1    	ldr	q1, [sp, #0xa60]
100005cb4: 4fdb9021    	fmul.2d	v1, v1, v27[0]
100005cb8: 4e61d400    	fadd.2d	v0, v0, v1
100005cbc: 3dc297e1    	ldr	q1, [sp, #0xa50]
100005cc0: 4fdc9021    	fmul.2d	v1, v1, v28[0]
100005cc4: 4e61d400    	fadd.2d	v0, v0, v1
100005cc8: 3dc233e1    	ldr	q1, [sp, #0x8c0]
100005ccc: 4fdd9021    	fmul.2d	v1, v1, v29[0]
100005cd0: 4e61d400    	fadd.2d	v0, v0, v1
100005cd4: 3dc293e1    	ldr	q1, [sp, #0xa40]
100005cd8: 4fde9021    	fmul.2d	v1, v1, v30[0]
100005cdc: 4e61d400    	fadd.2d	v0, v0, v1
100005ce0: 3d8153e0    	str	q0, [sp, #0x540]
100005ce4: 3dc20fe5    	ldr	q5, [sp, #0x830]
100005ce8: 4fd290a0    	fmul.2d	v0, v5, v18[0]
100005cec: 3dc27be1    	ldr	q1, [sp, #0x9e0]
100005cf0: 4fd39021    	fmul.2d	v1, v1, v19[0]
100005cf4: 4e61d400    	fadd.2d	v0, v0, v1
100005cf8: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
100005cfc: 4fd59021    	fmul.2d	v1, v1, v21[0]
100005d00: 4e61d400    	fadd.2d	v0, v0, v1
100005d04: 3dc277e1    	ldr	q1, [sp, #0x9d0]
100005d08: 4fd69021    	fmul.2d	v1, v1, v22[0]
100005d0c: 4e61d400    	fadd.2d	v0, v0, v1
100005d10: 3dc28be1    	ldr	q1, [sp, #0xa20]
100005d14: 4fd99021    	fmul.2d	v1, v1, v25[0]
100005d18: 4e61d400    	fadd.2d	v0, v0, v1
100005d1c: 3dc287e1    	ldr	q1, [sp, #0xa10]
100005d20: 4fc39021    	fmul.2d	v1, v1, v3[0]
100005d24: 4e61d400    	fadd.2d	v0, v0, v1
100005d28: 4fdb93e1    	fmul.2d	v1, v31, v27[0]
100005d2c: 4e61d400    	fadd.2d	v0, v0, v1
100005d30: 4fdc9101    	fmul.2d	v1, v8, v28[0]
100005d34: 4e61d400    	fadd.2d	v0, v0, v1
100005d38: 4fdd9121    	fmul.2d	v1, v9, v29[0]
100005d3c: 4e61d400    	fadd.2d	v0, v0, v1
100005d40: 4fde9301    	fmul.2d	v1, v24, v30[0]
100005d44: 4e61d400    	fadd.2d	v0, v0, v1
100005d48: 3d80efe0    	str	q0, [sp, #0x3b0]
100005d4c: ad494bf4    	ldp	q20, q18, [sp, #0x120]
100005d50: 4fd29080    	fmul.2d	v0, v4, v18[0]
100005d54: 4fd490c1    	fmul.2d	v1, v6, v20[0]
100005d58: 4e61d400    	fadd.2d	v0, v0, v1
100005d5c: ad485bfa    	ldp	q26, q22, [sp, #0x100]
100005d60: 4eac1d83    	mov.16b	v3, v12
100005d64: 4fd69181    	fmul.2d	v1, v12, v22[0]
100005d68: 4e61d400    	fadd.2d	v0, v0, v1
100005d6c: 4fda9221    	fmul.2d	v1, v17, v26[0]
100005d70: 4e61d400    	fadd.2d	v0, v0, v1
100005d74: ad4777ec    	ldp	q12, q29, [sp, #0xe0]
100005d78: 3dc26fe6    	ldr	q6, [sp, #0x9b0]
100005d7c: 4fdd90c1    	fmul.2d	v1, v6, v29[0]
100005d80: 4e61d400    	fadd.2d	v0, v0, v1
100005d84: 4fcc9161    	fmul.2d	v1, v11, v12[0]
100005d88: 4e61d400    	fadd.2d	v0, v0, v1
100005d8c: 3dc2b3ee    	ldr	q14, [sp, #0xac0]
100005d90: ad4647f7    	ldp	q23, q17, [sp, #0xc0]
100005d94: 4fd191c1    	fmul.2d	v1, v14, v17[0]
100005d98: 4e61d400    	fadd.2d	v0, v0, v1
100005d9c: 4eaf1df3    	mov.16b	v19, v15
100005da0: 4fd791e1    	fmul.2d	v1, v15, v23[0]
100005da4: 4e61d400    	fadd.2d	v0, v0, v1
100005da8: 3dc26bef    	ldr	q15, [sp, #0x9a0]
100005dac: ad4563ea    	ldp	q10, q24, [sp, #0xa0]
100005db0: 4fd891e1    	fmul.2d	v1, v15, v24[0]
100005db4: 4e61d400    	fadd.2d	v0, v0, v1
100005db8: 4ead1db5    	mov.16b	v21, v13
100005dbc: 4fca91a1    	fmul.2d	v1, v13, v10[0]
100005dc0: 4e61d400    	fadd.2d	v0, v0, v1
100005dc4: 3d8113e0    	str	q0, [sp, #0x440]
100005dc8: 3dc213e0    	ldr	q0, [sp, #0x840]
100005dcc: 4fd29000    	fmul.2d	v0, v0, v18[0]
100005dd0: 3dc263f9    	ldr	q25, [sp, #0x980]
100005dd4: 4fd49321    	fmul.2d	v1, v25, v20[0]
100005dd8: 4e61d400    	fadd.2d	v0, v0, v1
100005ddc: 3dc2bfe1    	ldr	q1, [sp, #0xaf0]
100005de0: 4fd69021    	fmul.2d	v1, v1, v22[0]
100005de4: 4e61d400    	fadd.2d	v0, v0, v1
100005de8: 3dc2abfb    	ldr	q27, [sp, #0xaa0]
100005dec: 4fda9361    	fmul.2d	v1, v27, v26[0]
100005df0: 4e61d400    	fadd.2d	v0, v0, v1
100005df4: 3dc1dffc    	ldr	q28, [sp, #0x770]
100005df8: 4fdd9381    	fmul.2d	v1, v28, v29[0]
100005dfc: 4ebd1fab    	mov.16b	v11, v29
100005e00: 4e61d400    	fadd.2d	v0, v0, v1
100005e04: 3dc23ffd    	ldr	q29, [sp, #0x8f0]
100005e08: 4fcc93a1    	fmul.2d	v1, v29, v12[0]
100005e0c: 4e61d400    	fadd.2d	v0, v0, v1
100005e10: 3dc1d7fe    	ldr	q30, [sp, #0x750]
100005e14: 4fd193c1    	fmul.2d	v1, v30, v17[0]
100005e18: 4e61d400    	fadd.2d	v0, v0, v1
100005e1c: 3dc1e7ff    	ldr	q31, [sp, #0x790]
100005e20: 4fd793e1    	fmul.2d	v1, v31, v23[0]
100005e24: 4e61d400    	fadd.2d	v0, v0, v1
100005e28: 3dc1e3e8    	ldr	q8, [sp, #0x780]
100005e2c: 4fd89101    	fmul.2d	v1, v8, v24[0]
100005e30: 4e61d400    	fadd.2d	v0, v0, v1
100005e34: 3dc2afe9    	ldr	q9, [sp, #0xab0]
100005e38: 4fca9121    	fmul.2d	v1, v9, v10[0]
100005e3c: 4e61d400    	fadd.2d	v0, v0, v1
100005e40: 3d810fe0    	str	q0, [sp, #0x430]
100005e44: 4fd290e0    	fmul.2d	v0, v7, v18[0]
100005e48: 3dc22fed    	ldr	q13, [sp, #0x8b0]
100005e4c: 4fd491a1    	fmul.2d	v1, v13, v20[0]
100005e50: 4e61d400    	fadd.2d	v0, v0, v1
100005e54: 3dc29fe1    	ldr	q1, [sp, #0xa70]
100005e58: 4fd69021    	fmul.2d	v1, v1, v22[0]
100005e5c: 4e61d400    	fadd.2d	v0, v0, v1
100005e60: 3dc2a7e1    	ldr	q1, [sp, #0xa90]
100005e64: 4fda9021    	fmul.2d	v1, v1, v26[0]
100005e68: 4e61d400    	fadd.2d	v0, v0, v1
100005e6c: 3dc217e1    	ldr	q1, [sp, #0x850]
100005e70: 4fcb9021    	fmul.2d	v1, v1, v11[0]
100005e74: 4e61d400    	fadd.2d	v0, v0, v1
100005e78: 4eb01e07    	mov.16b	v7, v16
100005e7c: 4fcc9201    	fmul.2d	v1, v16, v12[0]
100005e80: 4e61d400    	fadd.2d	v0, v0, v1
100005e84: 3dc243f0    	ldr	q16, [sp, #0x900]
100005e88: 4fd19201    	fmul.2d	v1, v16, v17[0]
100005e8c: 4e61d400    	fadd.2d	v0, v0, v1
100005e90: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
100005e94: 4fd79021    	fmul.2d	v1, v1, v23[0]
100005e98: 4e61d400    	fadd.2d	v0, v0, v1
100005e9c: 3dc1efe1    	ldr	q1, [sp, #0x7b0]
100005ea0: 4fd89021    	fmul.2d	v1, v1, v24[0]
100005ea4: 4e61d400    	fadd.2d	v0, v0, v1
100005ea8: 3dc267e1    	ldr	q1, [sp, #0x990]
100005eac: 4fca9021    	fmul.2d	v1, v1, v10[0]
100005eb0: 4e61d400    	fadd.2d	v0, v0, v1
100005eb4: 3d8123e0    	str	q0, [sp, #0x480]
100005eb8: 3dc1dbe0    	ldr	q0, [sp, #0x760]
100005ebc: 4fd29000    	fmul.2d	v0, v0, v18[0]
100005ec0: 3dc25be1    	ldr	q1, [sp, #0x960]
100005ec4: 4fd49021    	fmul.2d	v1, v1, v20[0]
100005ec8: 4e61d400    	fadd.2d	v0, v0, v1
100005ecc: 3dc257e1    	ldr	q1, [sp, #0x950]
100005ed0: 4fd69021    	fmul.2d	v1, v1, v22[0]
100005ed4: 4e61d400    	fadd.2d	v0, v0, v1
100005ed8: 3dc24be1    	ldr	q1, [sp, #0x920]
100005edc: 4fda9021    	fmul.2d	v1, v1, v26[0]
100005ee0: 4e61d400    	fadd.2d	v0, v0, v1
100005ee4: 3dc21be1    	ldr	q1, [sp, #0x860]
100005ee8: 4fcb9021    	fmul.2d	v1, v1, v11[0]
100005eec: 4e61d400    	fadd.2d	v0, v0, v1
100005ef0: 3dc25fe1    	ldr	q1, [sp, #0x970]
100005ef4: 4fcc9021    	fmul.2d	v1, v1, v12[0]
100005ef8: 4e61d400    	fadd.2d	v0, v0, v1
100005efc: 3dc247e1    	ldr	q1, [sp, #0x910]
100005f00: 4fd19021    	fmul.2d	v1, v1, v17[0]
100005f04: 4e61d400    	fadd.2d	v0, v0, v1
100005f08: 3dc253e1    	ldr	q1, [sp, #0x940]
100005f0c: 4fd79021    	fmul.2d	v1, v1, v23[0]
100005f10: 4e61d400    	fadd.2d	v0, v0, v1
100005f14: 3dc24fe1    	ldr	q1, [sp, #0x930]
100005f18: 4fd89021    	fmul.2d	v1, v1, v24[0]
100005f1c: 4e61d400    	fadd.2d	v0, v0, v1
100005f20: 3dc2a3e1    	ldr	q1, [sp, #0xa80]
100005f24: 4fca9021    	fmul.2d	v1, v1, v10[0]
100005f28: 4e61d400    	fadd.2d	v0, v0, v1
100005f2c: 3d814fe0    	str	q0, [sp, #0x530]
100005f30: 4fd290a0    	fmul.2d	v0, v5, v18[0]
100005f34: 3dc27be1    	ldr	q1, [sp, #0x9e0]
100005f38: 4fd49021    	fmul.2d	v1, v1, v20[0]
100005f3c: 4e61d400    	fadd.2d	v0, v0, v1
100005f40: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
100005f44: 4fd69021    	fmul.2d	v1, v1, v22[0]
100005f48: 4e61d400    	fadd.2d	v0, v0, v1
100005f4c: 3dc277e1    	ldr	q1, [sp, #0x9d0]
100005f50: 4fda9021    	fmul.2d	v1, v1, v26[0]
100005f54: 4e61d400    	fadd.2d	v0, v0, v1
100005f58: 3dc28be1    	ldr	q1, [sp, #0xa20]
100005f5c: 4fcb9021    	fmul.2d	v1, v1, v11[0]
100005f60: 4e61d400    	fadd.2d	v0, v0, v1
100005f64: 3dc287eb    	ldr	q11, [sp, #0xa10]
100005f68: 4fcc9161    	fmul.2d	v1, v11, v12[0]
100005f6c: 4e61d400    	fadd.2d	v0, v0, v1
100005f70: 3dc283e1    	ldr	q1, [sp, #0xa00]
100005f74: 4fd19021    	fmul.2d	v1, v1, v17[0]
100005f78: 4e61d400    	fadd.2d	v0, v0, v1
100005f7c: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
100005f80: 4fd79021    	fmul.2d	v1, v1, v23[0]
100005f84: 4e61d400    	fadd.2d	v0, v0, v1
100005f88: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
100005f8c: 4fd89021    	fmul.2d	v1, v1, v24[0]
100005f90: 4e61d400    	fadd.2d	v0, v0, v1
100005f94: 3dc20bf2    	ldr	q18, [sp, #0x820]
100005f98: 4fca9241    	fmul.2d	v1, v18, v10[0]
100005f9c: 4e61d400    	fadd.2d	v0, v0, v1
100005fa0: 3d80dfe0    	str	q0, [sp, #0x370]
100005fa4: ad445bf1    	ldp	q17, q22, [sp, #0x80]
100005fa8: 3dc207f4    	ldr	q20, [sp, #0x810]
100005fac: 4fd69280    	fmul.2d	v0, v20, v22[0]
100005fb0: 3dc203fa    	ldr	q26, [sp, #0x800]
100005fb4: 4fd19341    	fmul.2d	v1, v26, v17[0]
100005fb8: 4e61d400    	fadd.2d	v0, v0, v1
100005fbc: ad435ff8    	ldp	q24, q23, [sp, #0x60]
100005fc0: 4fd79061    	fmul.2d	v1, v3, v23[0]
100005fc4: 4e61d400    	fadd.2d	v0, v0, v1
100005fc8: 3dc1ffec    	ldr	q12, [sp, #0x7f0]
100005fcc: 4fd89181    	fmul.2d	v1, v12, v24[0]
100005fd0: 4e61d400    	fadd.2d	v0, v0, v1
100005fd4: ad422be3    	ldp	q3, q10, [sp, #0x40]
100005fd8: 4fca90c1    	fmul.2d	v1, v6, v10[0]
100005fdc: 4e61d400    	fadd.2d	v0, v0, v1
100005fe0: 3dc273e1    	ldr	q1, [sp, #0x9c0]
100005fe4: 4fc39021    	fmul.2d	v1, v1, v3[0]
100005fe8: 4e61d400    	fadd.2d	v0, v0, v1
100005fec: ad411be2    	ldp	q2, q6, [sp, #0x20]
100005ff0: 4fc691c1    	fmul.2d	v1, v14, v6[0]
100005ff4: 4e61d400    	fadd.2d	v0, v0, v1
100005ff8: 4fc29261    	fmul.2d	v1, v19, v2[0]
100005ffc: 4e61d400    	fadd.2d	v0, v0, v1
100006000: ad4013e5    	ldp	q5, q4, [sp]
100006004: 4fc491e1    	fmul.2d	v1, v15, v4[0]
100006008: 4e61d400    	fadd.2d	v0, v0, v1
10000600c: 4fc592a1    	fmul.2d	v1, v21, v5[0]
100006010: 4e61d400    	fadd.2d	v0, v0, v1
100006014: 3d810be0    	str	q0, [sp, #0x420]
100006018: 3dc213e0    	ldr	q0, [sp, #0x840]
10000601c: 4fd69000    	fmul.2d	v0, v0, v22[0]
100006020: 4eb61ece    	mov.16b	v14, v22
100006024: 4fd19321    	fmul.2d	v1, v25, v17[0]
100006028: 4e61d400    	fadd.2d	v0, v0, v1
10000602c: 3dc2bfe1    	ldr	q1, [sp, #0xaf0]
100006030: 4fd79021    	fmul.2d	v1, v1, v23[0]
100006034: 4e61d400    	fadd.2d	v0, v0, v1
100006038: 4fd89361    	fmul.2d	v1, v27, v24[0]
10000603c: 4e61d400    	fadd.2d	v0, v0, v1
100006040: 4fca9381    	fmul.2d	v1, v28, v10[0]
100006044: 4eaa1d4f    	mov.16b	v15, v10
100006048: 4e61d400    	fadd.2d	v0, v0, v1
10000604c: 4fc393a1    	fmul.2d	v1, v29, v3[0]
100006050: 4e61d400    	fadd.2d	v0, v0, v1
100006054: 4fc693c1    	fmul.2d	v1, v30, v6[0]
100006058: 4e61d400    	fadd.2d	v0, v0, v1
10000605c: 4fc293e1    	fmul.2d	v1, v31, v2[0]
100006060: 4e61d400    	fadd.2d	v0, v0, v1
100006064: 4fc49101    	fmul.2d	v1, v8, v4[0]
100006068: 4e61d400    	fadd.2d	v0, v0, v1
10000606c: 4fc59121    	fmul.2d	v1, v9, v5[0]
100006070: 4e61d400    	fadd.2d	v0, v0, v1
100006074: 3d8107e0    	str	q0, [sp, #0x410]
100006078: 3dc22be0    	ldr	q0, [sp, #0x8a0]
10000607c: 4fd69000    	fmul.2d	v0, v0, v22[0]
100006080: 4fd191a1    	fmul.2d	v1, v13, v17[0]
100006084: 4e61d400    	fadd.2d	v0, v0, v1
100006088: 3dc29fe1    	ldr	q1, [sp, #0xa70]
10000608c: 4fd79021    	fmul.2d	v1, v1, v23[0]
100006090: 4e61d400    	fadd.2d	v0, v0, v1
100006094: 3dc2a7e1    	ldr	q1, [sp, #0xa90]
100006098: 4fd89021    	fmul.2d	v1, v1, v24[0]
10000609c: 4e61d400    	fadd.2d	v0, v0, v1
1000060a0: 3dc217e1    	ldr	q1, [sp, #0x850]
1000060a4: 4fca9021    	fmul.2d	v1, v1, v10[0]
1000060a8: 4e61d400    	fadd.2d	v0, v0, v1
1000060ac: 4fc390e1    	fmul.2d	v1, v7, v3[0]
1000060b0: 4e61d400    	fadd.2d	v0, v0, v1
1000060b4: 4fc69201    	fmul.2d	v1, v16, v6[0]
1000060b8: 4e61d400    	fadd.2d	v0, v0, v1
1000060bc: 3dc2bbe1    	ldr	q1, [sp, #0xae0]
1000060c0: 4fc29021    	fmul.2d	v1, v1, v2[0]
1000060c4: 4e61d400    	fadd.2d	v0, v0, v1
1000060c8: 3dc1eff3    	ldr	q19, [sp, #0x7b0]
1000060cc: 4fc49261    	fmul.2d	v1, v19, v4[0]
1000060d0: 4e61d400    	fadd.2d	v0, v0, v1
1000060d4: 3dc267ff    	ldr	q31, [sp, #0x990]
1000060d8: 4fc593e1    	fmul.2d	v1, v31, v5[0]
1000060dc: 4e61d400    	fadd.2d	v0, v0, v1
1000060e0: 3d811fe0    	str	q0, [sp, #0x470]
1000060e4: 3dc1dbfc    	ldr	q28, [sp, #0x760]
1000060e8: 4fd69380    	fmul.2d	v0, v28, v22[0]
1000060ec: 3dc25bfd    	ldr	q29, [sp, #0x960]
1000060f0: 4fd193a1    	fmul.2d	v1, v29, v17[0]
1000060f4: 4e61d400    	fadd.2d	v0, v0, v1
1000060f8: 3dc257fe    	ldr	q30, [sp, #0x950]
1000060fc: 4fd793c1    	fmul.2d	v1, v30, v23[0]
100006100: 4e61d400    	fadd.2d	v0, v0, v1
100006104: 3dc24bf6    	ldr	q22, [sp, #0x920]
100006108: 4fd892c1    	fmul.2d	v1, v22, v24[0]
10000610c: 4e61d400    	fadd.2d	v0, v0, v1
100006110: 3dc21bf9    	ldr	q25, [sp, #0x860]
100006114: 4fca9321    	fmul.2d	v1, v25, v10[0]
100006118: 4e61d400    	fadd.2d	v0, v0, v1
10000611c: 3dc25ffb    	ldr	q27, [sp, #0x970]
100006120: 4fc39361    	fmul.2d	v1, v27, v3[0]
100006124: 4e61d400    	fadd.2d	v0, v0, v1
100006128: 3dc247e8    	ldr	q8, [sp, #0x910]
10000612c: 4fc69101    	fmul.2d	v1, v8, v6[0]
100006130: 4e61d400    	fadd.2d	v0, v0, v1
100006134: 3dc253e1    	ldr	q1, [sp, #0x940]
100006138: 4fc29021    	fmul.2d	v1, v1, v2[0]
10000613c: 4e61d400    	fadd.2d	v0, v0, v1
100006140: 3dc24ff5    	ldr	q21, [sp, #0x930]
100006144: 4fc492a1    	fmul.2d	v1, v21, v4[0]
100006148: 4e61d400    	fadd.2d	v0, v0, v1
10000614c: 3dc2a3e1    	ldr	q1, [sp, #0xa80]
100006150: 4fc59021    	fmul.2d	v1, v1, v5[0]
100006154: 4e61d400    	fadd.2d	v0, v0, v1
100006158: 3d811be0    	str	q0, [sp, #0x460]
10000615c: 3dc20fea    	ldr	q10, [sp, #0x830]
100006160: 4fce9140    	fmul.2d	v0, v10, v14[0]
100006164: 3dc27bed    	ldr	q13, [sp, #0x9e0]
100006168: 4fd191a1    	fmul.2d	v1, v13, v17[0]
10000616c: 4e61d400    	fadd.2d	v0, v0, v1
100006170: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
100006174: 4fd79021    	fmul.2d	v1, v1, v23[0]
100006178: 4e61d400    	fadd.2d	v0, v0, v1
10000617c: 3dc277f7    	ldr	q23, [sp, #0x9d0]
100006180: 4fd892e1    	fmul.2d	v1, v23, v24[0]
100006184: 4e61d400    	fadd.2d	v0, v0, v1
100006188: 3dc28bf8    	ldr	q24, [sp, #0xa20]
10000618c: 4fcf9301    	fmul.2d	v1, v24, v15[0]
100006190: 4e61d400    	fadd.2d	v0, v0, v1
100006194: 4fc39161    	fmul.2d	v1, v11, v3[0]
100006198: 4e61d400    	fadd.2d	v0, v0, v1
10000619c: 3dc283eb    	ldr	q11, [sp, #0xa00]
1000061a0: 4fc69161    	fmul.2d	v1, v11, v6[0]
1000061a4: 4e61d400    	fadd.2d	v0, v0, v1
1000061a8: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
1000061ac: 4fc29021    	fmul.2d	v1, v1, v2[0]
1000061b0: 4e61d400    	fadd.2d	v0, v0, v1
1000061b4: 3dc27fe9    	ldr	q9, [sp, #0x9f0]
1000061b8: 4fc49121    	fmul.2d	v1, v9, v4[0]
1000061bc: 4e61d400    	fadd.2d	v0, v0, v1
1000061c0: 4fc59241    	fmul.2d	v1, v18, v5[0]
1000061c4: 4e61d400    	fadd.2d	v0, v0, v1
1000061c8: 3d80ebe0    	str	q0, [sp, #0x3a0]
1000061cc: fd41e110    	ldr	d16, [x8, #0x3c0]
1000061d0: fd41e511    	ldr	d17, [x8, #0x3c8]
1000061d4: 4fd09280    	fmul.2d	v0, v20, v16[0]
1000061d8: 4fd19341    	fmul.2d	v1, v26, v17[0]
1000061dc: 4e61d400    	fadd.2d	v0, v0, v1
1000061e0: fd41e907    	ldr	d7, [x8, #0x3d0]
1000061e4: 3dc1fbe1    	ldr	q1, [sp, #0x7e0]
1000061e8: 4fc79021    	fmul.2d	v1, v1, v7[0]
1000061ec: 4e61d400    	fadd.2d	v0, v0, v1
1000061f0: fd41ed06    	ldr	d6, [x8, #0x3d8]
1000061f4: 4fc69181    	fmul.2d	v1, v12, v6[0]
1000061f8: 4e61d400    	fadd.2d	v0, v0, v1
1000061fc: fd41f105    	ldr	d5, [x8, #0x3e0]
100006200: 3dc26fe1    	ldr	q1, [sp, #0x9b0]
100006204: 4fc59021    	fmul.2d	v1, v1, v5[0]
100006208: 4e61d400    	fadd.2d	v0, v0, v1
10000620c: fd41f504    	ldr	d4, [x8, #0x3e8]
100006210: 3dc273ec    	ldr	q12, [sp, #0x9c0]
100006214: 4fc49181    	fmul.2d	v1, v12, v4[0]
100006218: 4e61d400    	fadd.2d	v0, v0, v1
10000621c: fd41f903    	ldr	d3, [x8, #0x3f0]
100006220: 3dc2b3e1    	ldr	q1, [sp, #0xac0]
100006224: 4fc39021    	fmul.2d	v1, v1, v3[0]
100006228: 4e61d400    	fadd.2d	v0, v0, v1
10000622c: fd41fd02    	ldr	d2, [x8, #0x3f8]
100006230: 3dc1f7e1    	ldr	q1, [sp, #0x7d0]
100006234: 4fc29021    	fmul.2d	v1, v1, v2[0]
100006238: 4e61d400    	fadd.2d	v0, v0, v1
10000623c: fd420101    	ldr	d1, [x8, #0x400]
100006240: 3dc26bf2    	ldr	q18, [sp, #0x9a0]
100006244: 4fc1924f    	fmul.2d	v15, v18, v1[0]
100006248: 4e6fd40f    	fadd.2d	v15, v0, v15
10000624c: fd420500    	ldr	d0, [x8, #0x408]
100006250: 3dc1f3fa    	ldr	q26, [sp, #0x7c0]
100006254: 4fc0934e    	fmul.2d	v14, v26, v0[0]
100006258: 4e6ed5f2    	fadd.2d	v18, v15, v14
10000625c: 3d813ff2    	str	q18, [sp, #0x4f0]
100006260: 3dc213f2    	ldr	q18, [sp, #0x840]
100006264: 4fd0924e    	fmul.2d	v14, v18, v16[0]
100006268: 3dc263f2    	ldr	q18, [sp, #0x980]
10000626c: 4fd1924f    	fmul.2d	v15, v18, v17[0]
100006270: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006274: 3dc2bff2    	ldr	q18, [sp, #0xaf0]
100006278: 4fc7924f    	fmul.2d	v15, v18, v7[0]
10000627c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006280: 3dc2abf2    	ldr	q18, [sp, #0xaa0]
100006284: 4fc6924f    	fmul.2d	v15, v18, v6[0]
100006288: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000628c: 3dc1dff2    	ldr	q18, [sp, #0x770]
100006290: 4fc5924f    	fmul.2d	v15, v18, v5[0]
100006294: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006298: 3dc23ff2    	ldr	q18, [sp, #0x8f0]
10000629c: 4fc4924f    	fmul.2d	v15, v18, v4[0]
1000062a0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000062a4: 3dc1d7f2    	ldr	q18, [sp, #0x750]
1000062a8: 4fc3924f    	fmul.2d	v15, v18, v3[0]
1000062ac: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000062b0: 3dc1e7f2    	ldr	q18, [sp, #0x790]
1000062b4: 4fc2924f    	fmul.2d	v15, v18, v2[0]
1000062b8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000062bc: 3dc1e3f2    	ldr	q18, [sp, #0x780]
1000062c0: 4fc1924f    	fmul.2d	v15, v18, v1[0]
1000062c4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000062c8: 3dc2aff2    	ldr	q18, [sp, #0xab0]
1000062cc: 4fc0924f    	fmul.2d	v15, v18, v0[0]
1000062d0: 4e6fd5d2    	fadd.2d	v18, v14, v15
1000062d4: 3d813bf2    	str	q18, [sp, #0x4e0]
1000062d8: 3dc22bf2    	ldr	q18, [sp, #0x8a0]
1000062dc: 4fd0924e    	fmul.2d	v14, v18, v16[0]
1000062e0: 3dc22ff2    	ldr	q18, [sp, #0x8b0]
1000062e4: 4fd1924f    	fmul.2d	v15, v18, v17[0]
1000062e8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000062ec: 3dc29ff2    	ldr	q18, [sp, #0xa70]
1000062f0: 4fc7924f    	fmul.2d	v15, v18, v7[0]
1000062f4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000062f8: 3dc2a7f2    	ldr	q18, [sp, #0xa90]
1000062fc: 4fc6924f    	fmul.2d	v15, v18, v6[0]
100006300: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006304: 3dc217f2    	ldr	q18, [sp, #0x850]
100006308: 4fc5924f    	fmul.2d	v15, v18, v5[0]
10000630c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006310: 3dc1ebf2    	ldr	q18, [sp, #0x7a0]
100006314: 4fc4924f    	fmul.2d	v15, v18, v4[0]
100006318: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000631c: 3dc243f2    	ldr	q18, [sp, #0x900]
100006320: 4fc3924f    	fmul.2d	v15, v18, v3[0]
100006324: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006328: 3dc2bbf2    	ldr	q18, [sp, #0xae0]
10000632c: 4fc2924f    	fmul.2d	v15, v18, v2[0]
100006330: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006334: 4fc1926f    	fmul.2d	v15, v19, v1[0]
100006338: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000633c: 4fc093ef    	fmul.2d	v15, v31, v0[0]
100006340: 4e6fd5d2    	fadd.2d	v18, v14, v15
100006344: 3d8137f2    	str	q18, [sp, #0x4d0]
100006348: 4fd0938e    	fmul.2d	v14, v28, v16[0]
10000634c: 4fd193af    	fmul.2d	v15, v29, v17[0]
100006350: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006354: 4fc793cf    	fmul.2d	v15, v30, v7[0]
100006358: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000635c: 4fc692cf    	fmul.2d	v15, v22, v6[0]
100006360: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006364: 4fc5932f    	fmul.2d	v15, v25, v5[0]
100006368: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000636c: 4fc4936f    	fmul.2d	v15, v27, v4[0]
100006370: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006374: 4fc3910f    	fmul.2d	v15, v8, v3[0]
100006378: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000637c: 3dc253f6    	ldr	q22, [sp, #0x940]
100006380: 4fc292cf    	fmul.2d	v15, v22, v2[0]
100006384: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006388: 4fc192af    	fmul.2d	v15, v21, v1[0]
10000638c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006390: 3dc2a3ff    	ldr	q31, [sp, #0xa80]
100006394: 4fc093ef    	fmul.2d	v15, v31, v0[0]
100006398: 4e6fd5d2    	fadd.2d	v18, v14, v15
10000639c: 3d8133f2    	str	q18, [sp, #0x4c0]
1000063a0: 3dc227f4    	ldr	q20, [sp, #0x890]
1000063a4: 4fd0928e    	fmul.2d	v14, v20, v16[0]
1000063a8: 3dc223f2    	ldr	q18, [sp, #0x880]
1000063ac: 4fd1924f    	fmul.2d	v15, v18, v17[0]
1000063b0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000063b4: 3dc23bfe    	ldr	q30, [sp, #0x8e0]
1000063b8: 4fc793cf    	fmul.2d	v15, v30, v7[0]
1000063bc: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000063c0: 3dc28ff3    	ldr	q19, [sp, #0xa30]
1000063c4: 4fc6926f    	fmul.2d	v15, v19, v6[0]
1000063c8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000063cc: 3dc237f5    	ldr	q21, [sp, #0x8d0]
1000063d0: 4fc592af    	fmul.2d	v15, v21, v5[0]
1000063d4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000063d8: 3dc21ff9    	ldr	q25, [sp, #0x870]
1000063dc: 4fc4932f    	fmul.2d	v15, v25, v4[0]
1000063e0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000063e4: 3dc29bfb    	ldr	q27, [sp, #0xa60]
1000063e8: 4fc3936f    	fmul.2d	v15, v27, v3[0]
1000063ec: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000063f0: 3dc297fc    	ldr	q28, [sp, #0xa50]
1000063f4: 4fc2938f    	fmul.2d	v15, v28, v2[0]
1000063f8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000063fc: 3dc233fd    	ldr	q29, [sp, #0x8c0]
100006400: 4fc193af    	fmul.2d	v15, v29, v1[0]
100006404: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006408: 3dc293ef    	ldr	q15, [sp, #0xa40]
10000640c: 4fc091ef    	fmul.2d	v15, v15, v0[0]
100006410: 4e6fd5d3    	fadd.2d	v19, v14, v15
100006414: 3d8117f3    	str	q19, [sp, #0x450]
100006418: 4fd09150    	fmul.2d	v16, v10, v16[0]
10000641c: 4fd191b1    	fmul.2d	v17, v13, v17[0]
100006420: 4e71d610    	fadd.2d	v16, v16, v17
100006424: 3dc2c3f1    	ldr	q17, [sp, #0xb00]
100006428: 4fc79227    	fmul.2d	v7, v17, v7[0]
10000642c: 4e67d607    	fadd.2d	v7, v16, v7
100006430: 4fc692e6    	fmul.2d	v6, v23, v6[0]
100006434: 4e66d4e6    	fadd.2d	v6, v7, v6
100006438: 4fc59305    	fmul.2d	v5, v24, v5[0]
10000643c: 4e65d4c5    	fadd.2d	v5, v6, v5
100006440: 3dc287f7    	ldr	q23, [sp, #0xa10]
100006444: 4fc492e4    	fmul.2d	v4, v23, v4[0]
100006448: 4e64d4a4    	fadd.2d	v4, v5, v4
10000644c: 4fc39163    	fmul.2d	v3, v11, v3[0]
100006450: 4e63d483    	fadd.2d	v3, v4, v3
100006454: 3dc2b7e4    	ldr	q4, [sp, #0xad0]
100006458: 4fc29082    	fmul.2d	v2, v4, v2[0]
10000645c: 4e62d462    	fadd.2d	v2, v3, v2
100006460: 4fc19121    	fmul.2d	v1, v9, v1[0]
100006464: 4e61d441    	fadd.2d	v1, v2, v1
100006468: 3dc20bf3    	ldr	q19, [sp, #0x820]
10000646c: 4fc09260    	fmul.2d	v0, v19, v0[0]
100006470: 4e60d420    	fadd.2d	v0, v1, v0
100006474: 3d80dbe0    	str	q0, [sp, #0x360]
100006478: fd421100    	ldr	d0, [x8, #0x420]
10000647c: 3dc207e1    	ldr	q1, [sp, #0x810]
100006480: 4fc09022    	fmul.2d	v2, v1, v0[0]
100006484: fd421501    	ldr	d1, [x8, #0x428]
100006488: 3dc203e3    	ldr	q3, [sp, #0x800]
10000648c: 4fc19063    	fmul.2d	v3, v3, v1[0]
100006490: 4e63d443    	fadd.2d	v3, v2, v3
100006494: fd421902    	ldr	d2, [x8, #0x430]
100006498: 3dc1fbe4    	ldr	q4, [sp, #0x7e0]
10000649c: 4fc29084    	fmul.2d	v4, v4, v2[0]
1000064a0: 4e64d464    	fadd.2d	v4, v3, v4
1000064a4: fd421d03    	ldr	d3, [x8, #0x438]
1000064a8: 3dc1ffe5    	ldr	q5, [sp, #0x7f0]
1000064ac: 4fc390a5    	fmul.2d	v5, v5, v3[0]
1000064b0: 4e65d485    	fadd.2d	v5, v4, v5
1000064b4: fd422104    	ldr	d4, [x8, #0x440]
1000064b8: 3dc26fe6    	ldr	q6, [sp, #0x9b0]
1000064bc: 4fc490c6    	fmul.2d	v6, v6, v4[0]
1000064c0: 4e66d4a6    	fadd.2d	v6, v5, v6
1000064c4: fd422505    	ldr	d5, [x8, #0x448]
1000064c8: 4fc59187    	fmul.2d	v7, v12, v5[0]
1000064cc: 4e67d4c7    	fadd.2d	v7, v6, v7
1000064d0: fd422906    	ldr	d6, [x8, #0x450]
1000064d4: 3dc2b3f0    	ldr	q16, [sp, #0xac0]
1000064d8: 4fc69210    	fmul.2d	v16, v16, v6[0]
1000064dc: 4e70d4f0    	fadd.2d	v16, v7, v16
1000064e0: fd422d07    	ldr	d7, [x8, #0x458]
1000064e4: 3dc1f7f1    	ldr	q17, [sp, #0x7d0]
1000064e8: 4fc79231    	fmul.2d	v17, v17, v7[0]
1000064ec: 4e71d611    	fadd.2d	v17, v16, v17
1000064f0: fd423110    	ldr	d16, [x8, #0x460]
1000064f4: 3dc26be8    	ldr	q8, [sp, #0x9a0]
1000064f8: 4fd0910e    	fmul.2d	v14, v8, v16[0]
1000064fc: 4e6ed62e    	fadd.2d	v14, v17, v14
100006500: fd423511    	ldr	d17, [x8, #0x468]
100006504: 4fd1934f    	fmul.2d	v15, v26, v17[0]
100006508: 4e6fd5da    	fadd.2d	v26, v14, v15
10000650c: 3d8147fa    	str	q26, [sp, #0x510]
100006510: 3dc213fa    	ldr	q26, [sp, #0x840]
100006514: 4fc0934e    	fmul.2d	v14, v26, v0[0]
100006518: 3dc263fa    	ldr	q26, [sp, #0x980]
10000651c: 4fc1934f    	fmul.2d	v15, v26, v1[0]
100006520: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006524: 3dc2bffa    	ldr	q26, [sp, #0xaf0]
100006528: 4fc2934f    	fmul.2d	v15, v26, v2[0]
10000652c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006530: 3dc2abfa    	ldr	q26, [sp, #0xaa0]
100006534: 4fc3934f    	fmul.2d	v15, v26, v3[0]
100006538: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000653c: 3dc1dffa    	ldr	q26, [sp, #0x770]
100006540: 4fc4934f    	fmul.2d	v15, v26, v4[0]
100006544: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006548: 3dc23ffa    	ldr	q26, [sp, #0x8f0]
10000654c: 4fc5934f    	fmul.2d	v15, v26, v5[0]
100006550: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006554: 3dc1d7fa    	ldr	q26, [sp, #0x750]
100006558: 4fc6934f    	fmul.2d	v15, v26, v6[0]
10000655c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006560: 3dc1e7fa    	ldr	q26, [sp, #0x790]
100006564: 4fc7934f    	fmul.2d	v15, v26, v7[0]
100006568: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000656c: 3dc1e3fa    	ldr	q26, [sp, #0x780]
100006570: 4fd0934f    	fmul.2d	v15, v26, v16[0]
100006574: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006578: 3dc2affa    	ldr	q26, [sp, #0xab0]
10000657c: 4fd1934f    	fmul.2d	v15, v26, v17[0]
100006580: 4e6fd5da    	fadd.2d	v26, v14, v15
100006584: 3d8143fa    	str	q26, [sp, #0x500]
100006588: 3dc22bfa    	ldr	q26, [sp, #0x8a0]
10000658c: 4fc0934e    	fmul.2d	v14, v26, v0[0]
100006590: 3dc22ffa    	ldr	q26, [sp, #0x8b0]
100006594: 4fc1934f    	fmul.2d	v15, v26, v1[0]
100006598: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000659c: 3dc29ffa    	ldr	q26, [sp, #0xa70]
1000065a0: 4fc2934f    	fmul.2d	v15, v26, v2[0]
1000065a4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000065a8: 3dc2a7fa    	ldr	q26, [sp, #0xa90]
1000065ac: 4fc3934f    	fmul.2d	v15, v26, v3[0]
1000065b0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000065b4: 3dc217fa    	ldr	q26, [sp, #0x850]
1000065b8: 4fc4934f    	fmul.2d	v15, v26, v4[0]
1000065bc: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000065c0: 3dc1ebfa    	ldr	q26, [sp, #0x7a0]
1000065c4: 4fc5934f    	fmul.2d	v15, v26, v5[0]
1000065c8: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000065cc: 3dc243fa    	ldr	q26, [sp, #0x900]
1000065d0: 4fc6934f    	fmul.2d	v15, v26, v6[0]
1000065d4: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000065d8: 3dc2bbfa    	ldr	q26, [sp, #0xae0]
1000065dc: 4fc7934f    	fmul.2d	v15, v26, v7[0]
1000065e0: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000065e4: 3dc1effa    	ldr	q26, [sp, #0x7b0]
1000065e8: 4fd0934f    	fmul.2d	v15, v26, v16[0]
1000065ec: 4e6fd5ce    	fadd.2d	v14, v14, v15
1000065f0: 3dc267fa    	ldr	q26, [sp, #0x990]
1000065f4: 4fd1934f    	fmul.2d	v15, v26, v17[0]
1000065f8: 4e6fd5da    	fadd.2d	v26, v14, v15
1000065fc: 3dc1dbe8    	ldr	q8, [sp, #0x760]
100006600: 4fc0910e    	fmul.2d	v14, v8, v0[0]
100006604: 3dc25be8    	ldr	q8, [sp, #0x960]
100006608: 4fc1910f    	fmul.2d	v15, v8, v1[0]
10000660c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006610: 3dc257e8    	ldr	q8, [sp, #0x950]
100006614: 4fc2910f    	fmul.2d	v15, v8, v2[0]
100006618: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000661c: 3dc24be8    	ldr	q8, [sp, #0x920]
100006620: 4fc3910f    	fmul.2d	v15, v8, v3[0]
100006624: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006628: 3dc21be8    	ldr	q8, [sp, #0x860]
10000662c: 4fc4910f    	fmul.2d	v15, v8, v4[0]
100006630: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006634: 3dc25fe8    	ldr	q8, [sp, #0x970]
100006638: 4fc5910f    	fmul.2d	v15, v8, v5[0]
10000663c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006640: 3dc247e8    	ldr	q8, [sp, #0x910]
100006644: 4fc6910f    	fmul.2d	v15, v8, v6[0]
100006648: 4e6fd5ce    	fadd.2d	v14, v14, v15
10000664c: 4fc792cf    	fmul.2d	v15, v22, v7[0]
100006650: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006654: 3dc24ff6    	ldr	q22, [sp, #0x930]
100006658: 4fd092cf    	fmul.2d	v15, v22, v16[0]
10000665c: 4e6fd5ce    	fadd.2d	v14, v14, v15
100006660: 4fd193ef    	fmul.2d	v15, v31, v17[0]
100006664: 4e6fd5d6    	fadd.2d	v22, v14, v15
100006668: 4fc0928d    	fmul.2d	v13, v20, v0[0]
10000666c: 4fc1924c    	fmul.2d	v12, v18, v1[0]
100006670: 4e6cd5ac    	fadd.2d	v12, v13, v12
100006674: 4fc293cb    	fmul.2d	v11, v30, v2[0]
100006678: 4e6bd58b    	fadd.2d	v11, v12, v11
10000667c: 3dc28ff2    	ldr	q18, [sp, #0xa30]
100006680: 4fc3924a    	fmul.2d	v10, v18, v3[0]
100006684: 4e6ad56a    	fadd.2d	v10, v11, v10
100006688: 4fc492a9    	fmul.2d	v9, v21, v4[0]
10000668c: 3dc153f5    	ldr	q21, [sp, #0x540]
100006690: 4e69d549    	fadd.2d	v9, v10, v9
100006694: 4fc59328    	fmul.2d	v8, v25, v5[0]
100006698: 3dc113ef    	ldr	q15, [sp, #0x440]
10000669c: 4e68d528    	fadd.2d	v8, v9, v8
1000066a0: 4fc6937f    	fmul.2d	v31, v27, v6[0]
1000066a4: 4e7fd51f    	fadd.2d	v31, v8, v31
1000066a8: 3dc12fe8    	ldr	q8, [sp, #0x4b0]
1000066ac: 4fc7939e    	fmul.2d	v30, v28, v7[0]
1000066b0: 4e7ed7fe    	fadd.2d	v30, v31, v30
1000066b4: 4fd093bd    	fmul.2d	v29, v29, v16[0]
1000066b8: 4e7dd7dd    	fadd.2d	v29, v30, v29
1000066bc: 3dc293f2    	ldr	q18, [sp, #0xa40]
1000066c0: 4fd1925c    	fmul.2d	v28, v18, v17[0]
1000066c4: 4e7cd7a9    	fadd.2d	v9, v29, v28
1000066c8: 3dc20ff2    	ldr	q18, [sp, #0x830]
1000066cc: 4fc09240    	fmul.2d	v0, v18, v0[0]
1000066d0: 3dc27bf2    	ldr	q18, [sp, #0x9e0]
1000066d4: 4fc19241    	fmul.2d	v1, v18, v1[0]
1000066d8: 4e61d400    	fadd.2d	v0, v0, v1
1000066dc: 3dc2c3e1    	ldr	q1, [sp, #0xb00]
1000066e0: 4fc29021    	fmul.2d	v1, v1, v2[0]
1000066e4: 4e61d400    	fadd.2d	v0, v0, v1
1000066e8: 3dc277e1    	ldr	q1, [sp, #0x9d0]
1000066ec: 4fc39021    	fmul.2d	v1, v1, v3[0]
1000066f0: 4e61d400    	fadd.2d	v0, v0, v1
1000066f4: 4fc49301    	fmul.2d	v1, v24, v4[0]
1000066f8: 4e61d400    	fadd.2d	v0, v0, v1
1000066fc: 4fc592e1    	fmul.2d	v1, v23, v5[0]
100006700: 4e61d400    	fadd.2d	v0, v0, v1
100006704: 3dc283e1    	ldr	q1, [sp, #0xa00]
100006708: 4fc69021    	fmul.2d	v1, v1, v6[0]
10000670c: 3dc177e6    	ldr	q6, [sp, #0x5d0]
100006710: 4e61d400    	fadd.2d	v0, v0, v1
100006714: 3dc2b7e1    	ldr	q1, [sp, #0xad0]
100006718: 4fc79021    	fmul.2d	v1, v1, v7[0]
10000671c: 4e61d400    	fadd.2d	v0, v0, v1
100006720: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
100006724: 4fd09021    	fmul.2d	v1, v1, v16[0]
100006728: 4e61d400    	fadd.2d	v0, v0, v1
10000672c: 4fd19261    	fmul.2d	v1, v19, v17[0]
100006730: 4e61d400    	fadd.2d	v0, v0, v1
100006734: 3d80a3e0    	str	q0, [sp, #0x280]
100006738: 3dc1d3e0    	ldr	q0, [sp, #0x740]
10000673c: 5e180400    	mov	d0, v0[1]
100006740: 3d82c3e0    	str	q0, [sp, #0xb00]
100006744: 3dc1bbe0    	ldr	q0, [sp, #0x6e0]
100006748: 5e180400    	mov	d0, v0[1]
10000674c: 3d82bfe0    	str	q0, [sp, #0xaf0]
100006750: 3dc1b7e0    	ldr	q0, [sp, #0x6d0]
100006754: 5e180400    	mov	d0, v0[1]
100006758: 3d82bbe0    	str	q0, [sp, #0xae0]
10000675c: 3dc1cbe0    	ldr	q0, [sp, #0x720]
100006760: 5e180400    	mov	d0, v0[1]
100006764: 3d82b7e0    	str	q0, [sp, #0xad0]
100006768: 3dc1c7e0    	ldr	q0, [sp, #0x710]
10000676c: 5e180400    	mov	d0, v0[1]
100006770: 3d82b3e0    	str	q0, [sp, #0xac0]
100006774: 3dc1cfe0    	ldr	q0, [sp, #0x730]
100006778: 5e180400    	mov	d0, v0[1]
10000677c: 3d82afe0    	str	q0, [sp, #0xab0]
100006780: 3dc1b3e0    	ldr	q0, [sp, #0x6c0]
100006784: 5e180400    	mov	d0, v0[1]
100006788: 3d82abe0    	str	q0, [sp, #0xaa0]
10000678c: 3dc1abe0    	ldr	q0, [sp, #0x6a0]
100006790: 5e180400    	mov	d0, v0[1]
100006794: 3d82a7e0    	str	q0, [sp, #0xa90]
100006798: 3dc16ff8    	ldr	q24, [sp, #0x5b0]
10000679c: 3dc173e7    	ldr	q7, [sp, #0x5c0]
1000067a0: 3dc1afe0    	ldr	q0, [sp, #0x6b0]
1000067a4: 5e180400    	mov	d0, v0[1]
1000067a8: 3d82a3e0    	str	q0, [sp, #0xa80]
1000067ac: 3dc19be0    	ldr	q0, [sp, #0x660]
1000067b0: 5e180400    	mov	d0, v0[1]
1000067b4: 3d829fe0    	str	q0, [sp, #0xa70]
1000067b8: 3dc17fe0    	ldr	q0, [sp, #0x5f0]
1000067bc: 5e180400    	mov	d0, v0[1]
1000067c0: 3d829be0    	str	q0, [sp, #0xa60]
1000067c4: 3dc197e0    	ldr	q0, [sp, #0x650]
1000067c8: 5e180400    	mov	d0, v0[1]
1000067cc: 3d8297e0    	str	q0, [sp, #0xa50]
1000067d0: 3dc193e0    	ldr	q0, [sp, #0x640]
1000067d4: 5e180400    	mov	d0, v0[1]
1000067d8: 3d8293e0    	str	q0, [sp, #0xa40]
1000067dc: 3dc1bfe0    	ldr	q0, [sp, #0x6f0]
1000067e0: 5e180400    	mov	d0, v0[1]
1000067e4: 3d828fe0    	str	q0, [sp, #0xa30]
1000067e8: 3dc19fe0    	ldr	q0, [sp, #0x670]
1000067ec: 5e180400    	mov	d0, v0[1]
1000067f0: 3d828be0    	str	q0, [sp, #0xa20]
1000067f4: 3dc1a7e0    	ldr	q0, [sp, #0x690]
1000067f8: 5e180400    	mov	d0, v0[1]
1000067fc: 3d8287e0    	str	q0, [sp, #0xa10]
100006800: 3dc1c3e0    	ldr	q0, [sp, #0x700]
100006804: 5e180400    	mov	d0, v0[1]
100006808: 3d8283e0    	str	q0, [sp, #0xa00]
10000680c: 3dc1a3e0    	ldr	q0, [sp, #0x680]
100006810: 5e180400    	mov	d0, v0[1]
100006814: 3d827fe0    	str	q0, [sp, #0x9f0]
100006818: 5e1804c0    	mov	d0, v6[1]
10000681c: 3d827be0    	str	q0, [sp, #0x9e0]
100006820: 3dc14be0    	ldr	q0, [sp, #0x520]
100006824: 5e180400    	mov	d0, v0[1]
100006828: 3d8277e0    	str	q0, [sp, #0x9d0]
10000682c: 3dc183e0    	ldr	q0, [sp, #0x600]
100006830: 5e180400    	mov	d0, v0[1]
100006834: 3d8273e0    	str	q0, [sp, #0x9c0]
100006838: 3dc18fe0    	ldr	q0, [sp, #0x630]
10000683c: 5e180400    	mov	d0, v0[1]
100006840: 3d826fe0    	str	q0, [sp, #0x9b0]
100006844: 5e1804e0    	mov	d0, v7[1]
100006848: 3d826be0    	str	q0, [sp, #0x9a0]
10000684c: 3dc18be0    	ldr	q0, [sp, #0x620]
100006850: 5e180400    	mov	d0, v0[1]
100006854: 3d8267e0    	str	q0, [sp, #0x990]
100006858: 5e180700    	mov	d0, v24[1]
10000685c: 3d8263e0    	str	q0, [sp, #0x980]
100006860: 3dc16be2    	ldr	q2, [sp, #0x5a0]
100006864: 5e180440    	mov	d0, v2[1]
100006868: 3d825fe0    	str	q0, [sp, #0x970]
10000686c: 3dc167e4    	ldr	q4, [sp, #0x590]
100006870: 5e180480    	mov	d0, v4[1]
100006874: 3d825be0    	str	q0, [sp, #0x960]
100006878: 5e180500    	mov	d0, v8[1]
10000687c: 3d8257e0    	str	q0, [sp, #0x950]
100006880: 3dc163fe    	ldr	q30, [sp, #0x580]
100006884: 5e1807c0    	mov	d0, v30[1]
100006888: 3d8253e0    	str	q0, [sp, #0x940]
10000688c: 3dc15fed    	ldr	q13, [sp, #0x570]
100006890: 5e1805a0    	mov	d0, v13[1]
100006894: 3d824fe0    	str	q0, [sp, #0x930]
100006898: 3dc187e0    	ldr	q0, [sp, #0x610]
10000689c: 5e180400    	mov	d0, v0[1]
1000068a0: 3d824be0    	str	q0, [sp, #0x920]
1000068a4: 3dc15bfd    	ldr	q29, [sp, #0x560]
1000068a8: 5e1807a0    	mov	d0, v29[1]
1000068ac: 3d8247e0    	str	q0, [sp, #0x910]
1000068b0: 3dc12bf1    	ldr	q17, [sp, #0x4a0]
1000068b4: 5e180620    	mov	d0, v17[1]
1000068b8: 3d8223e0    	str	q0, [sp, #0x880]
1000068bc: 3dc127f0    	ldr	q16, [sp, #0x490]
1000068c0: 5e180600    	mov	d0, v16[1]
1000068c4: 3d821fe0    	str	q0, [sp, #0x870]
1000068c8: 3dc157eb    	ldr	q11, [sp, #0x550]
1000068cc: 5e180560    	mov	d0, v11[1]
1000068d0: 3d8243e0    	str	q0, [sp, #0x900]
1000068d4: 5e1806a0    	mov	d0, v21[1]
1000068d8: 3d823fe0    	str	q0, [sp, #0x8f0]
1000068dc: 5e1805e0    	mov	d0, v15[1]
1000068e0: 3d8233e0    	str	q0, [sp, #0x8c0]
1000068e4: 3dc10fff    	ldr	q31, [sp, #0x430]
1000068e8: 5e1807e0    	mov	d0, v31[1]
1000068ec: 3d821be0    	str	q0, [sp, #0x860]
1000068f0: 3dc123fc    	ldr	q28, [sp, #0x480]
1000068f4: 5e180780    	mov	d0, v28[1]
1000068f8: 3d822fe0    	str	q0, [sp, #0x8b0]
1000068fc: 3dc14fec    	ldr	q12, [sp, #0x530]
100006900: 5e180580    	mov	d0, v12[1]
100006904: 3d823be0    	str	q0, [sp, #0x8e0]
100006908: 3dc17be0    	ldr	q0, [sp, #0x5e0]
10000690c: 5e180400    	mov	d0, v0[1]
100006910: 3d8237e0    	str	q0, [sp, #0x8d0]
100006914: 3dc10bfb    	ldr	q27, [sp, #0x420]
100006918: 5e180760    	mov	d0, v27[1]
10000691c: 3d8217e0    	str	q0, [sp, #0x850]
100006920: 3dc107f7    	ldr	q23, [sp, #0x410]
100006924: 5e1806e0    	mov	d0, v23[1]
100006928: 3d822be0    	str	q0, [sp, #0x8a0]
10000692c: 3dc11ff4    	ldr	q20, [sp, #0x470]
100006930: 5e180680    	mov	d0, v20[1]
100006934: 3d8213e0    	str	q0, [sp, #0x840]
100006938: 3dc11be3    	ldr	q3, [sp, #0x460]
10000693c: 5e180460    	mov	d0, v3[1]
100006940: 3d8227e0    	str	q0, [sp, #0x890]
100006944: 3dc13fe0    	ldr	q0, [sp, #0x4f0]
100006948: 5e180400    	mov	d0, v0[1]
10000694c: fd017be0    	str	d0, [sp, #0x2f0]
100006950: 3dc13be0    	ldr	q0, [sp, #0x4e0]
100006954: 5e180400    	mov	d0, v0[1]
100006958: fd0183e0    	str	d0, [sp, #0x300]
10000695c: 3dc137e0    	ldr	q0, [sp, #0x4d0]
100006960: 5e180400    	mov	d0, v0[1]
100006964: fd018be0    	str	d0, [sp, #0x310]
100006968: 3dc133e0    	ldr	q0, [sp, #0x4c0]
10000696c: 5e180400    	mov	d0, v0[1]
100006970: fd0103e0    	str	d0, [sp, #0x200]
100006974: 3dc117e0    	ldr	q0, [sp, #0x450]
100006978: 5e180400    	mov	d0, v0[1]
10000697c: 3d80e7e0    	str	q0, [sp, #0x390]
100006980: 3dc147e0    	ldr	q0, [sp, #0x510]
100006984: 5e180400    	mov	d0, v0[1]
100006988: fd011be0    	str	d0, [sp, #0x230]
10000698c: 3dc143e0    	ldr	q0, [sp, #0x500]
100006990: 5e180400    	mov	d0, v0[1]
100006994: fd0123e0    	str	d0, [sp, #0x240]
100006998: ad19ebf6    	stp	q22, q26, [sp, #0x330]
10000699c: 5e180740    	mov	d0, v26[1]
1000069a0: fd012be0    	str	d0, [sp, #0x250]
1000069a4: 5e1806c0    	mov	d0, v22[1]
1000069a8: fd0133e0    	str	d0, [sp, #0x260]
1000069ac: 3d80cbe9    	str	q9, [sp, #0x320]
1000069b0: 5e180520    	mov	d0, v9[1]
1000069b4: 3d80d7e0    	str	q0, [sp, #0x350]
1000069b8: 54000265    	b.pl	0x100006a04 <_codegen_qseries_nonzero_12x10+0x2700>
1000069bc: ad5f6be6    	ldp	q6, q26, [sp, #0x3e0]
1000069c0: 3dc0f3f1    	ldr	q17, [sp, #0x3c0]
1000069c4: 3dc103f8    	ldr	q24, [sp, #0x400]
1000069c8: ad5683e1    	ldp	q1, q0, [sp, #0x2d0]
1000069cc: ad558be3    	ldp	q3, q2, [sp, #0x2b0]
1000069d0: ad5493e5    	ldp	q5, q4, [sp, #0x290]
1000069d4: 3dc0e3f2    	ldr	q18, [sp, #0x380]
1000069d8: 3dc14bf6    	ldr	q22, [sp, #0x520]
1000069dc: 3dc18fe9    	ldr	q9, [sp, #0x630]
1000069e0: 3dc18bea    	ldr	q10, [sp, #0x620]
1000069e4: fd4103ec    	ldr	d12, [sp, #0x200]
1000069e8: 3dc0a3f9    	ldr	q25, [sp, #0x280]
1000069ec: fd411bff    	ldr	d31, [sp, #0x230]
1000069f0: fd4123fb    	ldr	d27, [sp, #0x240]
1000069f4: fd4133f4    	ldr	d20, [sp, #0x260]
1000069f8: fd412bf7    	ldr	d23, [sp, #0x250]
1000069fc: 3dc117f5    	ldr	q21, [sp, #0x450]
100006a00: 140007bb    	b	0x1000088ec <_codegen_qseries_nonzero_12x10+0x45e8>
100006a04: 4ea41c9a    	mov.16b	v26, v4
100006a08: 4ea21c56    	mov.16b	v22, v2
100006a0c: d2800008    	mov	x8, #0x0                ; =0
100006a10: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006a14: 3dc13121    	ldr	q1, [x9, #0x4c0]
100006a18: 3dc1d3e0    	ldr	q0, [sp, #0x740]
100006a1c: 4ee0d422    	fsub.2d	v2, v1, v0
100006a20: 6f00e400    	movi.2d	v0, #0000000000000000
100006a24: 3dc1bbe4    	ldr	q4, [sp, #0x6e0]
100006a28: 4ee4d404    	fsub.2d	v4, v0, v4
100006a2c: 3d82c7e2    	str	q2, [sp, #0xb10]
100006a30: 3d82cbe4    	str	q4, [sp, #0xb20]
100006a34: 3dc1b7e2    	ldr	q2, [sp, #0x6d0]
100006a38: 4ee2d402    	fsub.2d	v2, v0, v2
100006a3c: 3dc1cbe4    	ldr	q4, [sp, #0x720]
100006a40: 4ee4d404    	fsub.2d	v4, v0, v4
100006a44: 3d82cfe2    	str	q2, [sp, #0xb30]
100006a48: 3d82d3e4    	str	q4, [sp, #0xb40]
100006a4c: 3dc1c7e2    	ldr	q2, [sp, #0x710]
100006a50: 4ee2d404    	fsub.2d	v4, v0, v2
100006a54: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006a58: 3dc13522    	ldr	q2, [x9, #0x4d0]
100006a5c: 3dc0fbf2    	ldr	q18, [sp, #0x3e0]
100006a60: 4ef2d445    	fsub.2d	v5, v2, v18
100006a64: 3d82d7e4    	str	q4, [sp, #0xb50]
100006a68: 3d82dbe5    	str	q5, [sp, #0xb60]
100006a6c: 3dc1cfe4    	ldr	q4, [sp, #0x730]
100006a70: 4ee4d404    	fsub.2d	v4, v0, v4
100006a74: 3dc1b3e5    	ldr	q5, [sp, #0x6c0]
100006a78: 4ee5d405    	fsub.2d	v5, v0, v5
100006a7c: 3d82dfe4    	str	q4, [sp, #0xb70]
100006a80: 3d82e3e5    	str	q5, [sp, #0xb80]
100006a84: 3dc1abe4    	ldr	q4, [sp, #0x6a0]
100006a88: 4ee4d404    	fsub.2d	v4, v0, v4
100006a8c: 3dc1afe5    	ldr	q5, [sp, #0x6b0]
100006a90: 4ee5d405    	fsub.2d	v5, v0, v5
100006a94: 3d82e7e4    	str	q4, [sp, #0xb90]
100006a98: 3d82ebe5    	str	q5, [sp, #0xba0]
100006a9c: 3dc19be4    	ldr	q4, [sp, #0x660]
100006aa0: 4ee4d404    	fsub.2d	v4, v0, v4
100006aa4: 3dc17fe5    	ldr	q5, [sp, #0x5f0]
100006aa8: 4ee5d425    	fsub.2d	v5, v1, v5
100006aac: 3d82efe4    	str	q4, [sp, #0xbb0]
100006ab0: 3d82f3e5    	str	q5, [sp, #0xbc0]
100006ab4: 3dc197e4    	ldr	q4, [sp, #0x650]
100006ab8: 4ee4d404    	fsub.2d	v4, v0, v4
100006abc: 3dc193e5    	ldr	q5, [sp, #0x640]
100006ac0: 4ee5d405    	fsub.2d	v5, v0, v5
100006ac4: 3d82f7e4    	str	q4, [sp, #0xbd0]
100006ac8: 3d82fbe5    	str	q5, [sp, #0xbe0]
100006acc: 3dc1bfe4    	ldr	q4, [sp, #0x6f0]
100006ad0: 4ee4d404    	fsub.2d	v4, v0, v4
100006ad4: 3dc19fe5    	ldr	q5, [sp, #0x670]
100006ad8: 4ee5d405    	fsub.2d	v5, v0, v5
100006adc: 3d82ffe4    	str	q4, [sp, #0xbf0]
100006ae0: 3d8303e5    	str	q5, [sp, #0xc00]
100006ae4: 3dc0f3f3    	ldr	q19, [sp, #0x3c0]
100006ae8: 4ef3d444    	fsub.2d	v4, v2, v19
100006aec: 3dc1a7e5    	ldr	q5, [sp, #0x690]
100006af0: 4ee5d405    	fsub.2d	v5, v0, v5
100006af4: 3d8307e4    	str	q4, [sp, #0xc10]
100006af8: 3d830be5    	str	q5, [sp, #0xc20]
100006afc: 3dc1c3e4    	ldr	q4, [sp, #0x700]
100006b00: 4ee4d404    	fsub.2d	v4, v0, v4
100006b04: 3dc1a3e5    	ldr	q5, [sp, #0x680]
100006b08: 4ee5d405    	fsub.2d	v5, v0, v5
100006b0c: 3d830fe4    	str	q4, [sp, #0xc30]
100006b10: 3d8313e5    	str	q5, [sp, #0xc40]
100006b14: 4ee6d404    	fsub.2d	v4, v0, v6
100006b18: 3dc14bea    	ldr	q10, [sp, #0x520]
100006b1c: 4eead405    	fsub.2d	v5, v0, v10
100006b20: 3d8317e4    	str	q4, [sp, #0xc50]
100006b24: 3d831be5    	str	q5, [sp, #0xc60]
100006b28: 3dc183e4    	ldr	q4, [sp, #0x600]
100006b2c: 4ee4d424    	fsub.2d	v4, v1, v4
100006b30: 3dc18fe9    	ldr	q9, [sp, #0x630]
100006b34: 4ee9d405    	fsub.2d	v5, v0, v9
100006b38: 3d831fe4    	str	q4, [sp, #0xc70]
100006b3c: 3d8323e5    	str	q5, [sp, #0xc80]
100006b40: 4ee7d404    	fsub.2d	v4, v0, v7
100006b44: 3dc18be7    	ldr	q7, [sp, #0x620]
100006b48: 4ee7d405    	fsub.2d	v5, v0, v7
100006b4c: 3d8327e4    	str	q4, [sp, #0xc90]
100006b50: 3d832be5    	str	q5, [sp, #0xca0]
100006b54: 4ef8d404    	fsub.2d	v4, v0, v24
100006b58: 3dc103f8    	ldr	q24, [sp, #0x400]
100006b5c: 4ef8d445    	fsub.2d	v5, v2, v24
100006b60: 3d832fe4    	str	q4, [sp, #0xcb0]
100006b64: 3d8333e5    	str	q5, [sp, #0xcc0]
100006b68: 4ef6d404    	fsub.2d	v4, v0, v22
100006b6c: 4efad405    	fsub.2d	v5, v0, v26
100006b70: 3d8337e4    	str	q4, [sp, #0xcd0]
100006b74: 3d833be5    	str	q5, [sp, #0xce0]
100006b78: 4ee8d404    	fsub.2d	v4, v0, v8
100006b7c: 4efed405    	fsub.2d	v5, v0, v30
100006b80: 3d833fe4    	str	q4, [sp, #0xcf0]
100006b84: 3d8343e5    	str	q5, [sp, #0xd00]
100006b88: 4eedd404    	fsub.2d	v4, v0, v13
100006b8c: 3dc187e5    	ldr	q5, [sp, #0x610]
100006b90: 4ee5d425    	fsub.2d	v5, v1, v5
100006b94: 3d8347e4    	str	q4, [sp, #0xd10]
100006b98: 3d834be5    	str	q5, [sp, #0xd20]
100006b9c: 4efdd404    	fsub.2d	v4, v0, v29
100006ba0: 4ef1d405    	fsub.2d	v5, v0, v17
100006ba4: 3d834fe4    	str	q4, [sp, #0xd30]
100006ba8: 3d8353e5    	str	q5, [sp, #0xd40]
100006bac: 4ef0d404    	fsub.2d	v4, v0, v16
100006bb0: 4eebd405    	fsub.2d	v5, v0, v11
100006bb4: 3d8357e4    	str	q4, [sp, #0xd50]
100006bb8: 3d835be5    	str	q5, [sp, #0xd60]
100006bbc: 3dc0fffa    	ldr	q26, [sp, #0x3f0]
100006bc0: 4efad444    	fsub.2d	v4, v2, v26
100006bc4: 4ef5d405    	fsub.2d	v5, v0, v21
100006bc8: 3d835fe4    	str	q4, [sp, #0xd70]
100006bcc: 3d8363e5    	str	q5, [sp, #0xd80]
100006bd0: 4eefd404    	fsub.2d	v4, v0, v15
100006bd4: 4effd405    	fsub.2d	v5, v0, v31
100006bd8: 3d8367e4    	str	q4, [sp, #0xd90]
100006bdc: 3d836be5    	str	q5, [sp, #0xda0]
100006be0: 4efcd404    	fsub.2d	v4, v0, v28
100006be4: 4eecd405    	fsub.2d	v5, v0, v12
100006be8: 3d836fe4    	str	q4, [sp, #0xdb0]
100006bec: 3d8373e5    	str	q5, [sp, #0xdc0]
100006bf0: 3dc17be4    	ldr	q4, [sp, #0x5e0]
100006bf4: 4ee4d421    	fsub.2d	v1, v1, v4
100006bf8: 4efbd404    	fsub.2d	v4, v0, v27
100006bfc: 3d8377e1    	str	q1, [sp, #0xdd0]
100006c00: 3d837be4    	str	q4, [sp, #0xde0]
100006c04: 4ef7d401    	fsub.2d	v1, v0, v23
100006c08: 4ef4d404    	fsub.2d	v4, v0, v20
100006c0c: 3d837fe1    	str	q1, [sp, #0xdf0]
100006c10: 3d8383e4    	str	q4, [sp, #0xe00]
100006c14: 4ee3d400    	fsub.2d	v0, v0, v3
100006c18: 3dc0e3e4    	ldr	q4, [sp, #0x380]
100006c1c: 4ee4d441    	fsub.2d	v1, v2, v4
100006c20: 3d8387e0    	str	q0, [sp, #0xe10]
100006c24: 3d838be1    	str	q1, [sp, #0xe20]
100006c28: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006c2c: 3dc13d20    	ldr	q0, [x9, #0x4f0]
100006c30: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006c34: 3dc14121    	ldr	q1, [x9, #0x500]
100006c38: 3d8393e1    	str	q1, [sp, #0xe40]
100006c3c: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006c40: 3dc14521    	ldr	q1, [x9, #0x510]
100006c44: 3d83a3e0    	str	q0, [sp, #0xe80]
100006c48: 3d83a7e1    	str	q1, [sp, #0xe90]
100006c4c: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006c50: 3dc14920    	ldr	q0, [x9, #0x520]
100006c54: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006c58: 3dc14d21    	ldr	q1, [x9, #0x530]
100006c5c: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006c60: 3dc15522    	ldr	q2, [x9, #0x550]
100006c64: 3d83abe1    	str	q1, [sp, #0xea0]
100006c68: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006c6c: 3dc15121    	ldr	q1, [x9, #0x540]
100006c70: 3d8397e0    	str	q0, [sp, #0xe50]
100006c74: 3d839be1    	str	q1, [sp, #0xe60]
100006c78: d0000049    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100006c7c: 3dc13925    	ldr	q5, [x9, #0x4e0]
100006c80: 3d838fe5    	str	q5, [sp, #0xe30]
100006c84: 913b43e9    	add	x9, sp, #0xed0
100006c88: 3d83afe2    	str	q2, [sp, #0xeb0]
100006c8c: d000004a    	adrp	x10, 0x100010000 <dyld_stub_binder+0x100010000>
100006c90: 3dc15940    	ldr	q0, [x10, #0x560]
100006c94: 52800130    	mov	w16, #0x9               ; =9
100006c98: 5280002a    	mov	w10, #0x1               ; =1
100006c9c: 3d839fe0    	str	q0, [sp, #0xe70]
100006ca0: 913a03eb    	add	x11, sp, #0xe80
100006ca4: d000004c    	adrp	x12, 0x100010000 <dyld_stub_binder+0x100010000>
100006ca8: 3dc15d80    	ldr	q0, [x12, #0x570]
100006cac: 912c43ec    	add	x12, sp, #0xb10
100006cb0: d298540d    	mov	x13, #0xc2a0            ; =49824
100006cb4: f2bfdd6d    	movk	x13, #0xfeeb, lsl #16
100006cb8: f2c9096d    	movk	x13, #0x484b, lsl #32
100006cbc: f2e7368d    	movk	x13, #0x39b4, lsl #48
100006cc0: 3d83b3e0    	str	q0, [sp, #0xec0]
100006cc4: 1e6e1000    	fmov	d0, #1.00000000
100006cc8: 9138c3ee    	add	x14, sp, #0xe30
100006ccc: 4eb21e46    	mov.16b	v6, v18
100006cd0: 4eb31e71    	mov.16b	v17, v19
100006cd4: 4ea41c92    	mov.16b	v18, v4
100006cd8: 4eaa1d56    	mov.16b	v22, v10
100006cdc: 4ea71cea    	mov.16b	v10, v7
100006ce0: 3dc0a3f9    	ldr	q25, [sp, #0x280]
100006ce4: fd411bff    	ldr	d31, [sp, #0x230]
100006ce8: fd4123fb    	ldr	d27, [sp, #0x240]
100006cec: fd4133f4    	ldr	d20, [sp, #0x260]
100006cf0: fd412bf7    	ldr	d23, [sp, #0x250]
100006cf4: 3dc117f5    	ldr	q21, [sp, #0x450]
100006cf8: f100060f    	subs	x15, x16, #0x1
100006cfc: f8687971    	ldr	x17, [x11, x8, lsl #3]
100006d00: 9a9f8610    	csinc	x16, x16, xzr, hi
100006d04: 8b080220    	add	x0, x17, x8
100006d08: fc607981    	ldr	d1, [x12, x0, lsl #3]
100006d0c: 1e60c022    	fabs	d2, d1
100006d10: f100251f    	cmp	x8, #0x9
100006d14: 54000061    	b.ne	0x100006d20 <_codegen_qseries_nonzero_12x10+0x2a1c>
100006d18: 52800120    	mov	w0, #0x9                ; =9
100006d1c: 1400000f    	b	0x100006d58 <_codegen_qseries_nonzero_12x10+0x2a54>
100006d20: aa0a03e1    	mov	x1, x10
100006d24: aa1003e2    	mov	x2, x16
100006d28: 1e604044    	fmov	d4, d2
100006d2c: aa0803e0    	mov	x0, x8
100006d30: f8617963    	ldr	x3, [x11, x1, lsl #3]
100006d34: 8b080063    	add	x3, x3, x8
100006d38: fc637987    	ldr	d7, [x12, x3, lsl #3]
100006d3c: 1e60c0e7    	fabs	d7, d7
100006d40: 1e6420e0    	fcmp	d7, d4
100006d44: 9a80c020    	csel	x0, x1, x0, gt
100006d48: 1e64cce4    	fcsel	d4, d7, d4, gt
100006d4c: 91000421    	add	x1, x1, #0x1
100006d50: f1000442    	subs	x2, x2, #0x1
100006d54: 54fffee1    	b.ne	0x100006d30 <_codegen_qseries_nonzero_12x10+0x2a2c>
100006d58: eb08001f    	cmp	x0, x8
100006d5c: 54000180    	b.eq	0x100006d8c <_codegen_qseries_nonzero_12x10+0x2a88>
100006d60: f86879c1    	ldr	x1, [x14, x8, lsl #3]
100006d64: f86079c2    	ldr	x2, [x14, x0, lsl #3]
100006d68: f82879c2    	str	x2, [x14, x8, lsl #3]
100006d6c: f82079c1    	str	x1, [x14, x0, lsl #3]
100006d70: f8607961    	ldr	x1, [x11, x0, lsl #3]
100006d74: f8287961    	str	x1, [x11, x8, lsl #3]
100006d78: f8207971    	str	x17, [x11, x0, lsl #3]
100006d7c: f8687971    	ldr	x17, [x11, x8, lsl #3]
100006d80: 8b080220    	add	x0, x17, x8
100006d84: fc607981    	ldr	d1, [x12, x0, lsl #3]
100006d88: 1e60c022    	fabs	d2, d1
100006d8c: 9e6701a4    	fmov	d4, x13
100006d90: 1e642040    	fcmp	d2, d4
100006d94: 54000424    	b.mi	0x100006e18 <_codegen_qseries_nonzero_12x10+0x2b14>
100006d98: 1e611801    	fdiv	d1, d0, d1
100006d9c: fc287921    	str	d1, [x9, x8, lsl #3]
100006da0: f100251f    	cmp	x8, #0x9
100006da4: 54000440    	b.eq	0x100006e2c <_codegen_qseries_nonzero_12x10+0x2b28>
100006da8: d2800001    	mov	x1, #0x0                ; =0
100006dac: 91000500    	add	x0, x8, #0x1
100006db0: 8b0a0231    	add	x17, x17, x10
100006db4: 8b110d91    	add	x17, x12, x17, lsl #3
100006db8: 8b000022    	add	x2, x1, x0
100006dbc: f8627962    	ldr	x2, [x11, x2, lsl #3]
100006dc0: 8b080043    	add	x3, x2, x8
100006dc4: fc637982    	ldr	d2, [x12, x3, lsl #3]
100006dc8: 1e620822    	fmul	d2, d1, d2
100006dcc: fc237982    	str	d2, [x12, x3, lsl #3]
100006dd0: 8b020142    	add	x2, x10, x2
100006dd4: 8b020d82    	add	x2, x12, x2, lsl #3
100006dd8: aa1103e3    	mov	x3, x17
100006ddc: aa1003e4    	mov	x4, x16
100006de0: fc408464    	ldr	d4, [x3], #0x8
100006de4: fd400047    	ldr	d7, [x2]
100006de8: 1e640844    	fmul	d4, d2, d4
100006dec: 1e6438e4    	fsub	d4, d7, d4
100006df0: fc008444    	str	d4, [x2], #0x8
100006df4: f1000484    	subs	x4, x4, #0x1
100006df8: 54ffff41    	b.ne	0x100006de0 <_codegen_qseries_nonzero_12x10+0x2adc>
100006dfc: 91000421    	add	x1, x1, #0x1
100006e00: eb10003f    	cmp	x1, x16
100006e04: 54fffda1    	b.ne	0x100006db8 <_codegen_qseries_nonzero_12x10+0x2ab4>
100006e08: 9100054a    	add	x10, x10, #0x1
100006e0c: aa0f03f0    	mov	x16, x15
100006e10: aa0003e8    	mov	x8, x0
100006e14: 17ffffb9    	b	0x100006cf8 <_codegen_qseries_nonzero_12x10+0x29f4>
100006e18: ad5683e1    	ldp	q1, q0, [sp, #0x2d0]
100006e1c: ad558be3    	ldp	q3, q2, [sp, #0x2b0]
100006e20: ad5493e5    	ldp	q5, q4, [sp, #0x290]
100006e24: fd4103ec    	ldr	d12, [sp, #0x200]
100006e28: 140006b1    	b	0x1000088ec <_codegen_qseries_nonzero_12x10+0x45e8>
100006e2c: d2800008    	mov	x8, #0x0                ; =0
100006e30: 912c43ea    	add	x10, sp, #0xb10
100006e34: f94743eb    	ldr	x11, [sp, #0xe80]
100006e38: f94747ec    	ldr	x12, [sp, #0xe88]
100006e3c: 8b0b0d4b    	add	x11, x10, x11, lsl #3
100006e40: 3cc08120    	ldur	q0, [x9, #0x8]
100006e44: 3d82c3e0    	str	q0, [sp, #0xb00]
100006e48: 3dc3b7e0    	ldr	q0, [sp, #0xed0]
100006e4c: 3d82bfe0    	str	q0, [sp, #0xaf0]
100006e50: 3dc3bbe0    	ldr	q0, [sp, #0xee0]
100006e54: 3d82bbe0    	str	q0, [sp, #0xae0]
100006e58: 3cc18120    	ldur	q0, [x9, #0x18]
100006e5c: 3d82b7e0    	str	q0, [sp, #0xad0]
100006e60: f9474bed    	ldr	x13, [sp, #0xe90]
100006e64: f9474fee    	ldr	x14, [sp, #0xe98]
100006e68: 3cc28120    	ldur	q0, [x9, #0x28]
100006e6c: 3d82b3e0    	str	q0, [sp, #0xac0]
100006e70: f94753ef    	ldr	x15, [sp, #0xea0]
100006e74: f94757f1    	ldr	x17, [sp, #0xea8]
100006e78: 3dc3bfe0    	ldr	q0, [sp, #0xef0]
100006e7c: 3d82afe0    	str	q0, [sp, #0xab0]
100006e80: 3dc3c3e0    	ldr	q0, [sp, #0xf00]
100006e84: 3d82abe0    	str	q0, [sp, #0xaa0]
100006e88: 3cc38120    	ldur	q0, [x9, #0x38]
100006e8c: 3d82a7e0    	str	q0, [sp, #0xa90]
100006e90: f9475be9    	ldr	x9, [sp, #0xeb0]
100006e94: f9475fe1    	ldr	x1, [sp, #0xeb8]
100006e98: 3dc3c7e0    	ldr	q0, [sp, #0xf10]
100006e9c: 3d82a3e0    	str	q0, [sp, #0xa80]
100006ea0: fd478fe0    	ldr	d0, [sp, #0xf18]
100006ea4: 3d829fe0    	str	q0, [sp, #0xa70]
100006ea8: f94763e0    	ldr	x0, [sp, #0xec0]
100006eac: f94767f0    	ldr	x16, [sp, #0xec8]
100006eb0: 8b100d50    	add	x16, x10, x16, lsl #3
100006eb4: fd473fe0    	ldr	d0, [sp, #0xe78]
100006eb8: 8b000d40    	add	x0, x10, x0, lsl #3
100006ebc: 9138c3e6    	add	x6, sp, #0xe30
100006ec0: 910100c3    	add	x3, x6, #0x40
100006ec4: 8b010d42    	add	x2, x10, x1, lsl #3
100006ec8: 9100e0c4    	add	x4, x6, #0x38
100006ecc: 8b090d41    	add	x1, x10, x9, lsl #3
100006ed0: 9100c0c5    	add	x5, x6, #0x30
100006ed4: 8b110d51    	add	x17, x10, x17, lsl #3
100006ed8: 9100a0c9    	add	x9, x6, #0x28
100006edc: 8b0f0d4f    	add	x15, x10, x15, lsl #3
100006ee0: 910080c7    	add	x7, x6, #0x20
100006ee4: 8b0e0d4e    	add	x14, x10, x14, lsl #3
100006ee8: 910060d3    	add	x19, x6, #0x18
100006eec: 8b0d0d4d    	add	x13, x10, x13, lsl #3
100006ef0: 8b0c0d4c    	add	x12, x10, x12, lsl #3
100006ef4: 910040ca    	add	x10, x6, #0x10
100006ef8: 4d40ccc1    	ld1r.2d	{ v1 }, [x6]
100006efc: 3d829be1    	str	q1, [sp, #0xa60]
100006f00: b27d00c6    	orr	x6, x6, #0x8
100006f04: 4d40ccc1    	ld1r.2d	{ v1 }, [x6]
100006f08: 3d8297e1    	str	q1, [sp, #0xa50]
100006f0c: fd400181    	ldr	d1, [x12]
100006f10: 3d8293e1    	str	q1, [sp, #0xa40]
100006f14: 4d40cd41    	ld1r.2d	{ v1 }, [x10]
100006f18: 3d828fe1    	str	q1, [sp, #0xa30]
100006f1c: 4d40ce61    	ld1r.2d	{ v1 }, [x19]
100006f20: 3d828be1    	str	q1, [sp, #0xa20]
100006f24: fd4001a1    	ldr	d1, [x13]
100006f28: 3d8287e1    	str	q1, [sp, #0xa10]
100006f2c: fd4005a1    	ldr	d1, [x13, #0x8]
100006f30: 3d8283e1    	str	q1, [sp, #0xa00]
100006f34: fd4001c1    	ldr	d1, [x14]
100006f38: 3d827fe1    	str	q1, [sp, #0x9f0]
100006f3c: fd4005c1    	ldr	d1, [x14, #0x8]
100006f40: 3d827be1    	str	q1, [sp, #0x9e0]
100006f44: fd4009c1    	ldr	d1, [x14, #0x10]
100006f48: 3d8277e1    	str	q1, [sp, #0x9d0]
100006f4c: 4d40cce1    	ld1r.2d	{ v1 }, [x7]
100006f50: 3d8273e1    	str	q1, [sp, #0x9c0]
100006f54: fd4001e1    	ldr	d1, [x15]
100006f58: 3d826fe1    	str	q1, [sp, #0x9b0]
100006f5c: fd4005e1    	ldr	d1, [x15, #0x8]
100006f60: 3d826be1    	str	q1, [sp, #0x9a0]
100006f64: fd4009e1    	ldr	d1, [x15, #0x10]
100006f68: 3d8267e1    	str	q1, [sp, #0x990]
100006f6c: fd400de1    	ldr	d1, [x15, #0x18]
100006f70: 3d8263e1    	str	q1, [sp, #0x980]
100006f74: 4d40cd21    	ld1r.2d	{ v1 }, [x9]
100006f78: 3d825fe1    	str	q1, [sp, #0x970]
100006f7c: fd400221    	ldr	d1, [x17]
100006f80: 3d825be1    	str	q1, [sp, #0x960]
100006f84: fd400621    	ldr	d1, [x17, #0x8]
100006f88: 3d8257e1    	str	q1, [sp, #0x950]
100006f8c: fd400a21    	ldr	d1, [x17, #0x10]
100006f90: 3d8253e1    	str	q1, [sp, #0x940]
100006f94: fd400e21    	ldr	d1, [x17, #0x18]
100006f98: 3d824fe1    	str	q1, [sp, #0x930]
100006f9c: 4e080400    	dup.2d	v0, v0[0]
100006fa0: 3d824be0    	str	q0, [sp, #0x920]
100006fa4: fd401220    	ldr	d0, [x17, #0x20]
100006fa8: 3d8247e0    	str	q0, [sp, #0x910]
100006fac: 913c83e9    	add	x9, sp, #0xf20
100006fb0: 5280004a    	mov	w10, #0x2               ; =2
100006fb4: 4d40cca0    	ld1r.2d	{ v0 }, [x5]
100006fb8: 3d8243e0    	str	q0, [sp, #0x900]
100006fbc: fd400020    	ldr	d0, [x1]
100006fc0: 3d823fe0    	str	q0, [sp, #0x8f0]
100006fc4: fd400420    	ldr	d0, [x1, #0x8]
100006fc8: 3d823be0    	str	q0, [sp, #0x8e0]
100006fcc: fd400820    	ldr	d0, [x1, #0x10]
100006fd0: 3d8237e0    	str	q0, [sp, #0x8d0]
100006fd4: fd400c20    	ldr	d0, [x1, #0x18]
100006fd8: 3d8233e0    	str	q0, [sp, #0x8c0]
100006fdc: 4d40cc80    	ld1r.2d	{ v0 }, [x4]
100006fe0: 3d822fe0    	str	q0, [sp, #0x8b0]
100006fe4: fd401020    	ldr	d0, [x1, #0x20]
100006fe8: 3d822be0    	str	q0, [sp, #0x8a0]
100006fec: fd401420    	ldr	d0, [x1, #0x28]
100006ff0: 3d8227e0    	str	q0, [sp, #0x890]
100006ff4: fd400040    	ldr	d0, [x2]
100006ff8: 3d8223e0    	str	q0, [sp, #0x880]
100006ffc: fd400440    	ldr	d0, [x2, #0x8]
100007000: 3d821fe0    	str	q0, [sp, #0x870]
100007004: fd400840    	ldr	d0, [x2, #0x10]
100007008: 3d821be0    	str	q0, [sp, #0x860]
10000700c: fd400c40    	ldr	d0, [x2, #0x18]
100007010: 3d8217e0    	str	q0, [sp, #0x850]
100007014: fd401040    	ldr	d0, [x2, #0x20]
100007018: 3d8213e0    	str	q0, [sp, #0x840]
10000701c: fd401440    	ldr	d0, [x2, #0x28]
100007020: 3d820fe0    	str	q0, [sp, #0x830]
100007024: fd401840    	ldr	d0, [x2, #0x30]
100007028: 3d820be0    	str	q0, [sp, #0x820]
10000702c: 4d40cc60    	ld1r.2d	{ v0 }, [x3]
100007030: 3d8207e0    	str	q0, [sp, #0x810]
100007034: fd400000    	ldr	d0, [x0]
100007038: 3d8203e0    	str	q0, [sp, #0x800]
10000703c: fd400400    	ldr	d0, [x0, #0x8]
100007040: 3d81ffe0    	str	q0, [sp, #0x7f0]
100007044: fd400800    	ldr	d0, [x0, #0x10]
100007048: 3d81fbe0    	str	q0, [sp, #0x7e0]
10000704c: fd400c00    	ldr	d0, [x0, #0x18]
100007050: 3d81f7e0    	str	q0, [sp, #0x7d0]
100007054: fd401000    	ldr	d0, [x0, #0x20]
100007058: 3d81f3e0    	str	q0, [sp, #0x7c0]
10000705c: fd401400    	ldr	d0, [x0, #0x28]
100007060: 3d81efe0    	str	q0, [sp, #0x7b0]
100007064: fd401800    	ldr	d0, [x0, #0x30]
100007068: 3d81ebe0    	str	q0, [sp, #0x7a0]
10000706c: fd401c00    	ldr	d0, [x0, #0x38]
100007070: 3d81e7e0    	str	q0, [sp, #0x790]
100007074: fd400200    	ldr	d0, [x16]
100007078: 3d81e3e0    	str	q0, [sp, #0x780]
10000707c: fd400600    	ldr	d0, [x16, #0x8]
100007080: 3d81dfe0    	str	q0, [sp, #0x770]
100007084: fd400a00    	ldr	d0, [x16, #0x10]
100007088: 3d81dbe0    	str	q0, [sp, #0x760]
10000708c: fd400e00    	ldr	d0, [x16, #0x18]
100007090: 3d81d7e0    	str	q0, [sp, #0x750]
100007094: fd401200    	ldr	d0, [x16, #0x20]
100007098: 3d81d3e0    	str	q0, [sp, #0x740]
10000709c: fd401600    	ldr	d0, [x16, #0x28]
1000070a0: 3d81cfe0    	str	q0, [sp, #0x730]
1000070a4: fd401a00    	ldr	d0, [x16, #0x30]
1000070a8: 3d81cbe0    	str	q0, [sp, #0x720]
1000070ac: fd401e00    	ldr	d0, [x16, #0x38]
1000070b0: 3d81c7e0    	str	q0, [sp, #0x710]
1000070b4: fd402200    	ldr	d0, [x16, #0x40]
1000070b8: 3d81c3e0    	str	q0, [sp, #0x700]
1000070bc: fd402400    	ldr	d0, [x0, #0x48]
1000070c0: 3d81bfe0    	str	q0, [sp, #0x6f0]
1000070c4: fd402040    	ldr	d0, [x2, #0x40]
1000070c8: 3d81bbe0    	str	q0, [sp, #0x6e0]
1000070cc: fd402440    	ldr	d0, [x2, #0x48]
1000070d0: 3d81b7e0    	str	q0, [sp, #0x6d0]
1000070d4: fd401c20    	ldr	d0, [x1, #0x38]
1000070d8: 3d81b3e0    	str	q0, [sp, #0x6c0]
1000070dc: fd402020    	ldr	d0, [x1, #0x40]
1000070e0: 3d81afe0    	str	q0, [sp, #0x6b0]
1000070e4: fd402420    	ldr	d0, [x1, #0x48]
1000070e8: 3d81abe0    	str	q0, [sp, #0x6a0]
1000070ec: fd401a20    	ldr	d0, [x17, #0x30]
1000070f0: 3d81a7e0    	str	q0, [sp, #0x690]
1000070f4: fd401e20    	ldr	d0, [x17, #0x38]
1000070f8: 3d81a3e0    	str	q0, [sp, #0x680]
1000070fc: fd402220    	ldr	d0, [x17, #0x40]
100007100: 3d819fe0    	str	q0, [sp, #0x670]
100007104: fd402620    	ldr	d0, [x17, #0x48]
100007108: 3d819be0    	str	q0, [sp, #0x660]
10000710c: fd4015e0    	ldr	d0, [x15, #0x28]
100007110: 3d8197e0    	str	q0, [sp, #0x650]
100007114: fd4019e0    	ldr	d0, [x15, #0x30]
100007118: 3d8193e0    	str	q0, [sp, #0x640]
10000711c: fd401de0    	ldr	d0, [x15, #0x38]
100007120: 3d818fe0    	str	q0, [sp, #0x630]
100007124: fd4021e0    	ldr	d0, [x15, #0x40]
100007128: 3d818be0    	str	q0, [sp, #0x620]
10000712c: fd4025e0    	ldr	d0, [x15, #0x48]
100007130: 3d8187e0    	str	q0, [sp, #0x610]
100007134: fd4011c0    	ldr	d0, [x14, #0x20]
100007138: 3d8183e0    	str	q0, [sp, #0x600]
10000713c: fd4015c0    	ldr	d0, [x14, #0x28]
100007140: 3d817fe0    	str	q0, [sp, #0x5f0]
100007144: fd4019c0    	ldr	d0, [x14, #0x30]
100007148: 3d817be0    	str	q0, [sp, #0x5e0]
10000714c: fd401dc0    	ldr	d0, [x14, #0x38]
100007150: 3d8177e0    	str	q0, [sp, #0x5d0]
100007154: fd4021c0    	ldr	d0, [x14, #0x40]
100007158: 3d8173e0    	str	q0, [sp, #0x5c0]
10000715c: fd4025c0    	ldr	d0, [x14, #0x48]
100007160: 3d816fe0    	str	q0, [sp, #0x5b0]
100007164: fd400da0    	ldr	d0, [x13, #0x18]
100007168: 3d816be0    	str	q0, [sp, #0x5a0]
10000716c: fd4011a0    	ldr	d0, [x13, #0x20]
100007170: 3d8167e0    	str	q0, [sp, #0x590]
100007174: fd4015a0    	ldr	d0, [x13, #0x28]
100007178: 3d8163e0    	str	q0, [sp, #0x580]
10000717c: 6d433da0    	ldp	d0, d15, [x13, #0x30]
100007180: 3d815fe0    	str	q0, [sp, #0x570]
100007184: 6d4421bc    	ldp	d28, d8, [x13, #0x40]
100007188: 6d411983    	ldp	d3, d6, [x12, #0x10]
10000718c: 6d424590    	ldp	d16, d17, [x12, #0x20]
100007190: 6d435593    	ldp	d19, d21, [x12, #0x30]
100007194: 6d445d96    	ldp	d22, d23, [x12, #0x40]
100007198: 6d40f57b    	ldp	d27, d29, [x11, #0x8]
10000719c: 6d41fd7e    	ldp	d30, d31, [x11, #0x18]
1000071a0: 6d42a969    	ldp	d9, d10, [x11, #0x28]
1000071a4: 6d43b16b    	ldp	d11, d12, [x11, #0x38]
1000071a8: fd40256d    	ldr	d13, [x11, #0x48]
1000071ac: 3dc29be0    	ldr	q0, [sp, #0xa60]
1000071b0: 6ee58c00    	cmeq.2d	v0, v0, v5
1000071b4: 6f03f619    	fmov.2d	v25, #1.00000000
1000071b8: 4e201f2e    	and.16b	v14, v25, v0
1000071bc: 3dc297e0    	ldr	q0, [sp, #0xa50]
1000071c0: 6ee58c00    	cmeq.2d	v0, v0, v5
1000071c4: 4e201f20    	and.16b	v0, v25, v0
1000071c8: 3dc293e1    	ldr	q1, [sp, #0xa40]
1000071cc: 4fc191c1    	fmul.2d	v1, v14, v1[0]
1000071d0: 4ee1d400    	fsub.2d	v0, v0, v1
1000071d4: 3dc28fe1    	ldr	q1, [sp, #0xa30]
1000071d8: 6ee58c21    	cmeq.2d	v1, v1, v5
1000071dc: 4e211f21    	and.16b	v1, v25, v1
1000071e0: 3dc287e2    	ldr	q2, [sp, #0xa10]
1000071e4: 4fc291c2    	fmul.2d	v2, v14, v2[0]
1000071e8: 4ee2d421    	fsub.2d	v1, v1, v2
1000071ec: 3dc283e2    	ldr	q2, [sp, #0xa00]
1000071f0: 4fc29002    	fmul.2d	v2, v0, v2[0]
1000071f4: 3dc28be4    	ldr	q4, [sp, #0xa20]
1000071f8: 6ee58c84    	cmeq.2d	v4, v4, v5
1000071fc: 4e241f24    	and.16b	v4, v25, v4
100007200: 3dc27fe7    	ldr	q7, [sp, #0x9f0]
100007204: 4fc791c7    	fmul.2d	v7, v14, v7[0]
100007208: 4ee7d484    	fsub.2d	v4, v4, v7
10000720c: 4ee2d422    	fsub.2d	v2, v1, v2
100007210: 3dc27be1    	ldr	q1, [sp, #0x9e0]
100007214: 4fc19001    	fmul.2d	v1, v0, v1[0]
100007218: 4ee1d481    	fsub.2d	v1, v4, v1
10000721c: 3dc277e4    	ldr	q4, [sp, #0x9d0]
100007220: 4fc49044    	fmul.2d	v4, v2, v4[0]
100007224: 3dc273e7    	ldr	q7, [sp, #0x9c0]
100007228: 6ee58ce7    	cmeq.2d	v7, v7, v5
10000722c: 4e271f27    	and.16b	v7, v25, v7
100007230: 4ee4d434    	fsub.2d	v20, v1, v4
100007234: 3dc26fe1    	ldr	q1, [sp, #0x9b0]
100007238: 4fc191c1    	fmul.2d	v1, v14, v1[0]
10000723c: 4ee1d4e1    	fsub.2d	v1, v7, v1
100007240: 3dc26be4    	ldr	q4, [sp, #0x9a0]
100007244: 4fc49004    	fmul.2d	v4, v0, v4[0]
100007248: 4ee4d421    	fsub.2d	v1, v1, v4
10000724c: 3dc267e4    	ldr	q4, [sp, #0x990]
100007250: 4fc49044    	fmul.2d	v4, v2, v4[0]
100007254: 4ee4d421    	fsub.2d	v1, v1, v4
100007258: 3dc263e4    	ldr	q4, [sp, #0x980]
10000725c: 4fc49284    	fmul.2d	v4, v20, v4[0]
100007260: 3dc25fe7    	ldr	q7, [sp, #0x970]
100007264: 6ee58ce7    	cmeq.2d	v7, v7, v5
100007268: 4e271f27    	and.16b	v7, v25, v7
10000726c: 3dc25bf2    	ldr	q18, [sp, #0x960]
100007270: 4fd291d8    	fmul.2d	v24, v14, v18[0]
100007274: 4ef8d4e7    	fsub.2d	v7, v7, v24
100007278: 4ee4d438    	fsub.2d	v24, v1, v4
10000727c: 3dc257e1    	ldr	q1, [sp, #0x950]
100007280: 4fc19001    	fmul.2d	v1, v0, v1[0]
100007284: 4ee1d4e1    	fsub.2d	v1, v7, v1
100007288: 3dc253e4    	ldr	q4, [sp, #0x940]
10000728c: 4fc49044    	fmul.2d	v4, v2, v4[0]
100007290: 4ee4d421    	fsub.2d	v1, v1, v4
100007294: 3dc24fe4    	ldr	q4, [sp, #0x930]
100007298: 4fc49284    	fmul.2d	v4, v20, v4[0]
10000729c: 4ee4d421    	fsub.2d	v1, v1, v4
1000072a0: 3dc243e4    	ldr	q4, [sp, #0x900]
1000072a4: 6ee58c84    	cmeq.2d	v4, v4, v5
1000072a8: 4e241f24    	and.16b	v4, v25, v4
1000072ac: 3dc23fe7    	ldr	q7, [sp, #0x8f0]
1000072b0: 4fc791c7    	fmul.2d	v7, v14, v7[0]
1000072b4: 4ee7d484    	fsub.2d	v4, v4, v7
1000072b8: 3dc23be7    	ldr	q7, [sp, #0x8e0]
1000072bc: 4fc79007    	fmul.2d	v7, v0, v7[0]
1000072c0: 3dc247f2    	ldr	q18, [sp, #0x910]
1000072c4: 4fd2931a    	fmul.2d	v26, v24, v18[0]
1000072c8: 4ee7d484    	fsub.2d	v4, v4, v7
1000072cc: 3dc237e7    	ldr	q7, [sp, #0x8d0]
1000072d0: 4fc79047    	fmul.2d	v7, v2, v7[0]
1000072d4: 4ee7d484    	fsub.2d	v4, v4, v7
1000072d8: 3dc233e7    	ldr	q7, [sp, #0x8c0]
1000072dc: 4fc79287    	fmul.2d	v7, v20, v7[0]
1000072e0: 4ee7d484    	fsub.2d	v4, v4, v7
1000072e4: 4efad427    	fsub.2d	v7, v1, v26
1000072e8: 3dc22fe1    	ldr	q1, [sp, #0x8b0]
1000072ec: 6ee58c21    	cmeq.2d	v1, v1, v5
1000072f0: 4e211f21    	and.16b	v1, v25, v1
1000072f4: 3dc223f2    	ldr	q18, [sp, #0x880]
1000072f8: 4fd291da    	fmul.2d	v26, v14, v18[0]
1000072fc: 4efad421    	fsub.2d	v1, v1, v26
100007300: 3dc21ff2    	ldr	q18, [sp, #0x870]
100007304: 4fd2901a    	fmul.2d	v26, v0, v18[0]
100007308: 3dc22bf2    	ldr	q18, [sp, #0x8a0]
10000730c: 4fd29312    	fmul.2d	v18, v24, v18[0]
100007310: 4efad421    	fsub.2d	v1, v1, v26
100007314: 3dc21bfa    	ldr	q26, [sp, #0x860]
100007318: 4fda905a    	fmul.2d	v26, v2, v26[0]
10000731c: 4efad421    	fsub.2d	v1, v1, v26
100007320: 3dc217fa    	ldr	q26, [sp, #0x850]
100007324: 4fda929a    	fmul.2d	v26, v20, v26[0]
100007328: 4efad421    	fsub.2d	v1, v1, v26
10000732c: 4ef2d484    	fsub.2d	v4, v4, v18
100007330: 3dc207f2    	ldr	q18, [sp, #0x810]
100007334: 6ee58e52    	cmeq.2d	v18, v18, v5
100007338: 4e321f32    	and.16b	v18, v25, v18
10000733c: 3dc203fa    	ldr	q26, [sp, #0x800]
100007340: 4fda91da    	fmul.2d	v26, v14, v26[0]
100007344: 4efad652    	fsub.2d	v18, v18, v26
100007348: 3dc213fa    	ldr	q26, [sp, #0x840]
10000734c: 4fda931a    	fmul.2d	v26, v24, v26[0]
100007350: 4efad421    	fsub.2d	v1, v1, v26
100007354: 3dc1fffa    	ldr	q26, [sp, #0x7f0]
100007358: 4fda901a    	fmul.2d	v26, v0, v26[0]
10000735c: 4efad652    	fsub.2d	v18, v18, v26
100007360: 3dc1fbfa    	ldr	q26, [sp, #0x7e0]
100007364: 4fda905a    	fmul.2d	v26, v2, v26[0]
100007368: 4efad652    	fsub.2d	v18, v18, v26
10000736c: 3dc227fa    	ldr	q26, [sp, #0x890]
100007370: 4fda90fa    	fmul.2d	v26, v7, v26[0]
100007374: 4efad484    	fsub.2d	v4, v4, v26
100007378: 3dc1f7fa    	ldr	q26, [sp, #0x7d0]
10000737c: 4fda929a    	fmul.2d	v26, v20, v26[0]
100007380: 4efad652    	fsub.2d	v18, v18, v26
100007384: 3dc1f3fa    	ldr	q26, [sp, #0x7c0]
100007388: 4fda931a    	fmul.2d	v26, v24, v26[0]
10000738c: 4efad652    	fsub.2d	v18, v18, v26
100007390: 3dc20ffa    	ldr	q26, [sp, #0x830]
100007394: 4fda90fa    	fmul.2d	v26, v7, v26[0]
100007398: 4efad421    	fsub.2d	v1, v1, v26
10000739c: 3dc24bfa    	ldr	q26, [sp, #0x920]
1000073a0: 6ee58f5a    	cmeq.2d	v26, v26, v5
1000073a4: 4e3a1f39    	and.16b	v25, v25, v26
1000073a8: 3dc1e3fa    	ldr	q26, [sp, #0x780]
1000073ac: 4fda91da    	fmul.2d	v26, v14, v26[0]
1000073b0: 4efad739    	fsub.2d	v25, v25, v26
1000073b4: 3dc1effa    	ldr	q26, [sp, #0x7b0]
1000073b8: 4fda90fa    	fmul.2d	v26, v7, v26[0]
1000073bc: 4efad652    	fsub.2d	v18, v18, v26
1000073c0: 3dc1dffa    	ldr	q26, [sp, #0x770]
1000073c4: 4fda901a    	fmul.2d	v26, v0, v26[0]
1000073c8: 4efad739    	fsub.2d	v25, v25, v26
1000073cc: 3dc1dbfa    	ldr	q26, [sp, #0x760]
1000073d0: 4fda905a    	fmul.2d	v26, v2, v26[0]
1000073d4: 4efad739    	fsub.2d	v25, v25, v26
1000073d8: 3dc20bfa    	ldr	q26, [sp, #0x820]
1000073dc: 4fda909a    	fmul.2d	v26, v4, v26[0]
1000073e0: 4efad421    	fsub.2d	v1, v1, v26
1000073e4: 3dc1d7fa    	ldr	q26, [sp, #0x750]
1000073e8: 4fda929a    	fmul.2d	v26, v20, v26[0]
1000073ec: 4efad739    	fsub.2d	v25, v25, v26
1000073f0: 3dc1d3fa    	ldr	q26, [sp, #0x740]
1000073f4: 4fda931a    	fmul.2d	v26, v24, v26[0]
1000073f8: 4efad739    	fsub.2d	v25, v25, v26
1000073fc: 3dc1ebfa    	ldr	q26, [sp, #0x7a0]
100007400: 4fda909a    	fmul.2d	v26, v4, v26[0]
100007404: 4efad652    	fsub.2d	v18, v18, v26
100007408: 3dc1cffa    	ldr	q26, [sp, #0x730]
10000740c: 4fda90fa    	fmul.2d	v26, v7, v26[0]
100007410: 4efad739    	fsub.2d	v25, v25, v26
100007414: 3dc1cbfa    	ldr	q26, [sp, #0x720]
100007418: 4fda909a    	fmul.2d	v26, v4, v26[0]
10000741c: 4efad739    	fsub.2d	v25, v25, v26
100007420: 3dc1e7fa    	ldr	q26, [sp, #0x790]
100007424: 4fda903a    	fmul.2d	v26, v1, v26[0]
100007428: 4efad652    	fsub.2d	v18, v18, v26
10000742c: 3dc1c7fa    	ldr	q26, [sp, #0x710]
100007430: 4fda903a    	fmul.2d	v26, v1, v26[0]
100007434: 4efad739    	fsub.2d	v25, v25, v26
100007438: 3dc1c3fa    	ldr	q26, [sp, #0x700]
10000743c: 4fda925a    	fmul.2d	v26, v18, v26[0]
100007440: 4efad739    	fsub.2d	v25, v25, v26
100007444: 3dc29ffa    	ldr	q26, [sp, #0xa70]
100007448: 4fda9339    	fmul.2d	v25, v25, v26[0]
10000744c: 3dc1bffa    	ldr	q26, [sp, #0x6f0]
100007450: 4fda933a    	fmul.2d	v26, v25, v26[0]
100007454: 4efad652    	fsub.2d	v18, v18, v26
100007458: 3dc2a3fa    	ldr	q26, [sp, #0xa80]
10000745c: 4fda925a    	fmul.2d	v26, v18, v26[0]
100007460: 3dc1bbf2    	ldr	q18, [sp, #0x6e0]
100007464: 4fd29352    	fmul.2d	v18, v26, v18[0]
100007468: 4ef2d421    	fsub.2d	v1, v1, v18
10000746c: 3dc1b7f2    	ldr	q18, [sp, #0x6d0]
100007470: 4fd29332    	fmul.2d	v18, v25, v18[0]
100007474: 4ef2d421    	fsub.2d	v1, v1, v18
100007478: 3dc2a7f2    	ldr	q18, [sp, #0xa90]
10000747c: 4fd29021    	fmul.2d	v1, v1, v18[0]
100007480: 3dc1b3f2    	ldr	q18, [sp, #0x6c0]
100007484: 4fd29032    	fmul.2d	v18, v1, v18[0]
100007488: 4ef2d484    	fsub.2d	v4, v4, v18
10000748c: 3dc1aff2    	ldr	q18, [sp, #0x6b0]
100007490: 4fd29352    	fmul.2d	v18, v26, v18[0]
100007494: 4ef2d484    	fsub.2d	v4, v4, v18
100007498: 3dc1abf2    	ldr	q18, [sp, #0x6a0]
10000749c: 4fd29332    	fmul.2d	v18, v25, v18[0]
1000074a0: 4ef2d484    	fsub.2d	v4, v4, v18
1000074a4: 3dc2abf2    	ldr	q18, [sp, #0xaa0]
1000074a8: 4fd29084    	fmul.2d	v4, v4, v18[0]
1000074ac: 3dc1a7f2    	ldr	q18, [sp, #0x690]
1000074b0: 4fd29092    	fmul.2d	v18, v4, v18[0]
1000074b4: 4ef2d4e7    	fsub.2d	v7, v7, v18
1000074b8: 3dc1a3f2    	ldr	q18, [sp, #0x680]
1000074bc: 4fd29032    	fmul.2d	v18, v1, v18[0]
1000074c0: 4ef2d4e7    	fsub.2d	v7, v7, v18
1000074c4: 3dc19ff2    	ldr	q18, [sp, #0x670]
1000074c8: 4fd29352    	fmul.2d	v18, v26, v18[0]
1000074cc: 4ef2d4e7    	fsub.2d	v7, v7, v18
1000074d0: 3dc19bf2    	ldr	q18, [sp, #0x660]
1000074d4: 4fd29332    	fmul.2d	v18, v25, v18[0]
1000074d8: 4ef2d4e7    	fsub.2d	v7, v7, v18
1000074dc: 3dc2b3f2    	ldr	q18, [sp, #0xac0]
1000074e0: 4fd290e7    	fmul.2d	v7, v7, v18[0]
1000074e4: 3dc197f2    	ldr	q18, [sp, #0x650]
1000074e8: 4fd290f2    	fmul.2d	v18, v7, v18[0]
1000074ec: 4ef2d712    	fsub.2d	v18, v24, v18
1000074f0: 3dc193f8    	ldr	q24, [sp, #0x640]
1000074f4: 4fd89098    	fmul.2d	v24, v4, v24[0]
1000074f8: 4ef8d652    	fsub.2d	v18, v18, v24
1000074fc: 3dc18ff8    	ldr	q24, [sp, #0x630]
100007500: 4fd89038    	fmul.2d	v24, v1, v24[0]
100007504: 4ef8d652    	fsub.2d	v18, v18, v24
100007508: 3dc18bf8    	ldr	q24, [sp, #0x620]
10000750c: 4fd89358    	fmul.2d	v24, v26, v24[0]
100007510: 4ef8d652    	fsub.2d	v18, v18, v24
100007514: 3dc187f8    	ldr	q24, [sp, #0x610]
100007518: 4fd89338    	fmul.2d	v24, v25, v24[0]
10000751c: 4ef8d652    	fsub.2d	v18, v18, v24
100007520: 3dc2aff8    	ldr	q24, [sp, #0xab0]
100007524: 4fd89258    	fmul.2d	v24, v18, v24[0]
100007528: 3dc183f2    	ldr	q18, [sp, #0x600]
10000752c: 4fd29312    	fmul.2d	v18, v24, v18[0]
100007530: 4ef2d692    	fsub.2d	v18, v20, v18
100007534: 3dc17ff4    	ldr	q20, [sp, #0x5f0]
100007538: 4fd490f4    	fmul.2d	v20, v7, v20[0]
10000753c: 4ef4d652    	fsub.2d	v18, v18, v20
100007540: 3dc17bf4    	ldr	q20, [sp, #0x5e0]
100007544: 4fd49094    	fmul.2d	v20, v4, v20[0]
100007548: 4ef4d652    	fsub.2d	v18, v18, v20
10000754c: 3dc177f4    	ldr	q20, [sp, #0x5d0]
100007550: 4fd49034    	fmul.2d	v20, v1, v20[0]
100007554: 4ef4d652    	fsub.2d	v18, v18, v20
100007558: 3dc173f4    	ldr	q20, [sp, #0x5c0]
10000755c: 4fd49354    	fmul.2d	v20, v26, v20[0]
100007560: 4ef4d652    	fsub.2d	v18, v18, v20
100007564: 3dc16ff4    	ldr	q20, [sp, #0x5b0]
100007568: 4fd49334    	fmul.2d	v20, v25, v20[0]
10000756c: 4ef4d652    	fsub.2d	v18, v18, v20
100007570: 3dc2b7f4    	ldr	q20, [sp, #0xad0]
100007574: 4fd49252    	fmul.2d	v18, v18, v20[0]
100007578: 3dc16bf4    	ldr	q20, [sp, #0x5a0]
10000757c: 4fd49254    	fmul.2d	v20, v18, v20[0]
100007580: 4ef4d442    	fsub.2d	v2, v2, v20
100007584: 3dc167f4    	ldr	q20, [sp, #0x590]
100007588: 4fd49314    	fmul.2d	v20, v24, v20[0]
10000758c: 4ef4d442    	fsub.2d	v2, v2, v20
100007590: 3dc163f4    	ldr	q20, [sp, #0x580]
100007594: 4fd490f4    	fmul.2d	v20, v7, v20[0]
100007598: 4ef4d442    	fsub.2d	v2, v2, v20
10000759c: 3dc15ff4    	ldr	q20, [sp, #0x570]
1000075a0: 4fd49094    	fmul.2d	v20, v4, v20[0]
1000075a4: 4ef4d442    	fsub.2d	v2, v2, v20
1000075a8: 4fcf9034    	fmul.2d	v20, v1, v15[0]
1000075ac: 4ef4d442    	fsub.2d	v2, v2, v20
1000075b0: 4fdc9354    	fmul.2d	v20, v26, v28[0]
1000075b4: 4ef4d442    	fsub.2d	v2, v2, v20
1000075b8: 4fc89334    	fmul.2d	v20, v25, v8[0]
1000075bc: 4ef4d442    	fsub.2d	v2, v2, v20
1000075c0: 3dc2bbf4    	ldr	q20, [sp, #0xae0]
1000075c4: 4fd49042    	fmul.2d	v2, v2, v20[0]
1000075c8: 4fc39054    	fmul.2d	v20, v2, v3[0]
1000075cc: 4ef4d400    	fsub.2d	v0, v0, v20
1000075d0: 4fc69254    	fmul.2d	v20, v18, v6[0]
1000075d4: 4ef4d400    	fsub.2d	v0, v0, v20
1000075d8: 4fd09314    	fmul.2d	v20, v24, v16[0]
1000075dc: 4ef4d400    	fsub.2d	v0, v0, v20
1000075e0: 4fd190f4    	fmul.2d	v20, v7, v17[0]
1000075e4: 4ef4d400    	fsub.2d	v0, v0, v20
1000075e8: 4fd39094    	fmul.2d	v20, v4, v19[0]
1000075ec: 4ef4d400    	fsub.2d	v0, v0, v20
1000075f0: 4fd59034    	fmul.2d	v20, v1, v21[0]
1000075f4: 4ef4d400    	fsub.2d	v0, v0, v20
1000075f8: 4fd69354    	fmul.2d	v20, v26, v22[0]
1000075fc: 4ef4d400    	fsub.2d	v0, v0, v20
100007600: 4fd79334    	fmul.2d	v20, v25, v23[0]
100007604: 4ef4d400    	fsub.2d	v0, v0, v20
100007608: 3dc2c3f4    	ldr	q20, [sp, #0xb00]
10000760c: 4fd49000    	fmul.2d	v0, v0, v20[0]
100007610: 4fdb9014    	fmul.2d	v20, v0, v27[0]
100007614: 4ef4d5d4    	fsub.2d	v20, v14, v20
100007618: 4fdd904e    	fmul.2d	v14, v2, v29[0]
10000761c: 4eeed694    	fsub.2d	v20, v20, v14
100007620: 4fde924e    	fmul.2d	v14, v18, v30[0]
100007624: 4eeed694    	fsub.2d	v20, v20, v14
100007628: 4fdf930e    	fmul.2d	v14, v24, v31[0]
10000762c: 4eeed694    	fsub.2d	v20, v20, v14
100007630: 4fc990ee    	fmul.2d	v14, v7, v9[0]
100007634: 4eeed694    	fsub.2d	v20, v20, v14
100007638: 4fca908e    	fmul.2d	v14, v4, v10[0]
10000763c: 4eeed694    	fsub.2d	v20, v20, v14
100007640: 4fcb902e    	fmul.2d	v14, v1, v11[0]
100007644: 4eeed694    	fsub.2d	v20, v20, v14
100007648: 4fcc934e    	fmul.2d	v14, v26, v12[0]
10000764c: 4eeed694    	fsub.2d	v20, v20, v14
100007650: 4fcd932e    	fmul.2d	v14, v25, v13[0]
100007654: 4eeed694    	fsub.2d	v20, v20, v14
100007658: 8b08012b    	add	x11, x9, x8
10000765c: 3d802962    	str	q2, [x11, #0xa0]
100007660: 3d803d72    	str	q18, [x11, #0xf0]
100007664: 3d805178    	str	q24, [x11, #0x140]
100007668: 3d801560    	str	q0, [x11, #0x50]
10000766c: 3d806567    	str	q7, [x11, #0x190]
100007670: 3d807964    	str	q4, [x11, #0x1e0]
100007674: 3d808d61    	str	q1, [x11, #0x230]
100007678: 3d80a17a    	str	q26, [x11, #0x280]
10000767c: 3dc2bfe0    	ldr	q0, [sp, #0xaf0]
100007680: 4fc09280    	fmul.2d	v0, v20, v0[0]
100007684: 3d800160    	str	q0, [x11]
100007688: 3d80b579    	str	q25, [x11, #0x2d0]
10000768c: 4e080d40    	dup.2d	v0, x10
100007690: 4ee084a5    	add.2d	v5, v5, v0
100007694: 91004108    	add	x8, x8, #0x10
100007698: f101411f    	cmp	x8, #0x50
10000769c: 54ffd881    	b.ne	0x1000071ac <_codegen_qseries_nonzero_12x10+0x2ea8>
1000076a0: fd4793e1    	ldr	d1, [sp, #0xf20]
1000076a4: fd4797e5    	ldr	d5, [sp, #0xf28]
1000076a8: 3d82c3e5    	str	q5, [sp, #0xb00]
1000076ac: ad568fe2    	ldp	q2, q3, [sp, #0x2d0]
1000076b0: 4fc19060    	fmul.2d	v0, v3, v1[0]
1000076b4: 4ea11c3c    	mov.16b	v28, v1
1000076b8: 3d81efe1    	str	q1, [sp, #0x7b0]
1000076bc: 6f00e401    	movi.2d	v1, #0000000000000000
1000076c0: 4e61d400    	fadd.2d	v0, v0, v1
1000076c4: 6f00e404    	movi.2d	v4, #0000000000000000
1000076c8: 4fc59041    	fmul.2d	v1, v2, v5[0]
1000076cc: 4ea21c45    	mov.16b	v5, v2
1000076d0: 4e61d400    	fadd.2d	v0, v0, v1
1000076d4: fd479be1    	ldr	d1, [sp, #0xf30]
1000076d8: 3d81bbe1    	str	q1, [sp, #0x6e0]
1000076dc: fd479fe7    	ldr	d7, [sp, #0xf38]
1000076e0: 3d82bfe7    	str	q7, [sp, #0xaf0]
1000076e4: ad55cfe2    	ldp	q2, q19, [sp, #0x2b0]
1000076e8: 4fc19261    	fmul.2d	v1, v19, v1[0]
1000076ec: 4e61d400    	fadd.2d	v0, v0, v1
1000076f0: 4fc79041    	fmul.2d	v1, v2, v7[0]
1000076f4: 4ea21c47    	mov.16b	v7, v2
1000076f8: 4e61d400    	fadd.2d	v0, v0, v1
1000076fc: fd47a3e1    	ldr	d1, [sp, #0xf40]
100007700: 3d81b7e1    	str	q1, [sp, #0x6d0]
100007704: fd47a7f0    	ldr	d16, [sp, #0xf48]
100007708: 3d82bbf0    	str	q16, [sp, #0xae0]
10000770c: ad54dbf5    	ldp	q21, q22, [sp, #0x290]
100007710: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100007714: 4e61d400    	fadd.2d	v0, v0, v1
100007718: 4fd092a1    	fmul.2d	v1, v21, v16[0]
10000771c: 4e61d400    	fadd.2d	v0, v0, v1
100007720: fd47abe1    	ldr	d1, [sp, #0xf50]
100007724: 3d81cbe1    	str	q1, [sp, #0x720]
100007728: fd47aff0    	ldr	d16, [sp, #0xf58]
10000772c: 3d82b7f0    	str	q16, [sp, #0xad0]
100007730: 3dc0f7f8    	ldr	q24, [sp, #0x3d0]
100007734: 4fc19301    	fmul.2d	v1, v24, v1[0]
100007738: 4e61d400    	fadd.2d	v0, v0, v1
10000773c: ad5d1bf2    	ldp	q18, q6, [sp, #0x3a0]
100007740: 4fd090c1    	fmul.2d	v1, v6, v16[0]
100007744: 4e61d400    	fadd.2d	v0, v0, v1
100007748: fd47b3e1    	ldr	d1, [sp, #0xf60]
10000774c: 3d81c7e1    	str	q1, [sp, #0x710]
100007750: fd47b7f0    	ldr	d16, [sp, #0xf68]
100007754: 3d82b3f0    	str	q16, [sp, #0xac0]
100007758: 3dc0dfee    	ldr	q14, [sp, #0x370]
10000775c: 4fc191c1    	fmul.2d	v1, v14, v1[0]
100007760: 4e61d400    	fadd.2d	v0, v0, v1
100007764: 4fd09241    	fmul.2d	v1, v18, v16[0]
100007768: 4e61d400    	fadd.2d	v0, v0, v1
10000776c: 3d81e7e0    	str	q0, [sp, #0x790]
100007770: fd47bbe0    	ldr	d0, [sp, #0xf70]
100007774: 3d80fbe0    	str	q0, [sp, #0x3e0]
100007778: fd47bfe2    	ldr	d2, [sp, #0xf78]
10000777c: 3d820fe2    	str	q2, [sp, #0x830]
100007780: 4fc09060    	fmul.2d	v0, v3, v0[0]
100007784: 4e64d400    	fadd.2d	v0, v0, v4
100007788: 4fc290a1    	fmul.2d	v1, v5, v2[0]
10000778c: 4e61d400    	fadd.2d	v0, v0, v1
100007790: fd47c3e1    	ldr	d1, [sp, #0xf80]
100007794: 3d81cfe1    	str	q1, [sp, #0x730]
100007798: fd47c7f0    	ldr	d16, [sp, #0xf88]
10000779c: 3d82aff0    	str	q16, [sp, #0xab0]
1000077a0: 4fc19261    	fmul.2d	v1, v19, v1[0]
1000077a4: 4e61d400    	fadd.2d	v0, v0, v1
1000077a8: 4fd090e1    	fmul.2d	v1, v7, v16[0]
1000077ac: 4e61d400    	fadd.2d	v0, v0, v1
1000077b0: fd47cbe1    	ldr	d1, [sp, #0xf90]
1000077b4: 3d81b3e1    	str	q1, [sp, #0x6c0]
1000077b8: fd47cff0    	ldr	d16, [sp, #0xf98]
1000077bc: 3d82abf0    	str	q16, [sp, #0xaa0]
1000077c0: 4fc192c1    	fmul.2d	v1, v22, v1[0]
1000077c4: 4e61d400    	fadd.2d	v0, v0, v1
1000077c8: 4fd092a1    	fmul.2d	v1, v21, v16[0]
1000077cc: 4e61d400    	fadd.2d	v0, v0, v1
1000077d0: fd47d3e1    	ldr	d1, [sp, #0xfa0]
1000077d4: 3d81abe1    	str	q1, [sp, #0x6a0]
1000077d8: fd47d7f0    	ldr	d16, [sp, #0xfa8]
1000077dc: 3d82a7f0    	str	q16, [sp, #0xa90]
1000077e0: 4fc19301    	fmul.2d	v1, v24, v1[0]
1000077e4: 4e61d400    	fadd.2d	v0, v0, v1
1000077e8: 4fd090c1    	fmul.2d	v1, v6, v16[0]
1000077ec: 4e61d400    	fadd.2d	v0, v0, v1
1000077f0: fd47dbe1    	ldr	d1, [sp, #0xfb0]
1000077f4: 3d81afe1    	str	q1, [sp, #0x6b0]
1000077f8: fd47dff0    	ldr	d16, [sp, #0xfb8]
1000077fc: 3d82a3f0    	str	q16, [sp, #0xa80]
100007800: 4fc191c1    	fmul.2d	v1, v14, v1[0]
100007804: 4e61d400    	fadd.2d	v0, v0, v1
100007808: 4fd09241    	fmul.2d	v1, v18, v16[0]
10000780c: 4e61d400    	fadd.2d	v0, v0, v1
100007810: 3d81e3e0    	str	q0, [sp, #0x780]
100007814: fd47e3e1    	ldr	d1, [sp, #0xfc0]
100007818: fd47e7e2    	ldr	d2, [sp, #0xfc8]
10000781c: 3d829fe2    	str	q2, [sp, #0xa70]
100007820: 4fc19060    	fmul.2d	v0, v3, v1[0]
100007824: 4ea11c30    	mov.16b	v16, v1
100007828: 3d819be1    	str	q1, [sp, #0x660]
10000782c: 4e64d400    	fadd.2d	v0, v0, v4
100007830: 4fc290a1    	fmul.2d	v1, v5, v2[0]
100007834: 4e61d400    	fadd.2d	v0, v0, v1
100007838: fd47ebe1    	ldr	d1, [sp, #0xfd0]
10000783c: 3d820be1    	str	q1, [sp, #0x820]
100007840: fd47efe4    	ldr	d4, [sp, #0xfd8]
100007844: 3d829be4    	str	q4, [sp, #0xa60]
100007848: 4fc19261    	fmul.2d	v1, v19, v1[0]
10000784c: 4e61d400    	fadd.2d	v0, v0, v1
100007850: 4fc490e1    	fmul.2d	v1, v7, v4[0]
100007854: 4e61d400    	fadd.2d	v0, v0, v1
100007858: fd47f3e1    	ldr	d1, [sp, #0xfe0]
10000785c: 3d8197e1    	str	q1, [sp, #0x650]
100007860: fd47f7e4    	ldr	d4, [sp, #0xfe8]
100007864: 3d8297e4    	str	q4, [sp, #0xa50]
100007868: 4fc192c1    	fmul.2d	v1, v22, v1[0]
10000786c: 4e61d400    	fadd.2d	v0, v0, v1
100007870: 4fc492a1    	fmul.2d	v1, v21, v4[0]
100007874: 4e61d400    	fadd.2d	v0, v0, v1
100007878: fd47fbe1    	ldr	d1, [sp, #0xff0]
10000787c: 3d8193e1    	str	q1, [sp, #0x640]
100007880: fd47ffe4    	ldr	d4, [sp, #0xff8]
100007884: 3d8293e4    	str	q4, [sp, #0xa40]
100007888: 4fc19301    	fmul.2d	v1, v24, v1[0]
10000788c: 4e61d400    	fadd.2d	v0, v0, v1
100007890: 4ea61cd1    	mov.16b	v17, v6
100007894: 4fc490c1    	fmul.2d	v1, v6, v4[0]
100007898: 4e61d400    	fadd.2d	v0, v0, v1
10000789c: fd4803e1    	ldr	d1, [sp, #0x1000]
1000078a0: 3d81bfe1    	str	q1, [sp, #0x6f0]
1000078a4: fd4807e2    	ldr	d2, [sp, #0x1008]
1000078a8: 3d828fe2    	str	q2, [sp, #0xa30]
1000078ac: 4fc191c1    	fmul.2d	v1, v14, v1[0]
1000078b0: 4e61d400    	fadd.2d	v0, v0, v1
1000078b4: 4eb21e54    	mov.16b	v20, v18
1000078b8: 4fc29241    	fmul.2d	v1, v18, v2[0]
1000078bc: 4e61d400    	fadd.2d	v0, v0, v1
1000078c0: 3d81dfe0    	str	q0, [sp, #0x770]
1000078c4: fd480be6    	ldr	d6, [sp, #0x1010]
1000078c8: 3d819fe6    	str	q6, [sp, #0x670]
1000078cc: fd480fe4    	ldr	d4, [sp, #0x1018]
1000078d0: 3d828be4    	str	q4, [sp, #0xa20]
1000078d4: 4fc69060    	fmul.2d	v0, v3, v6[0]
1000078d8: 6f00e402    	movi.2d	v2, #0000000000000000
1000078dc: 4e62d400    	fadd.2d	v0, v0, v2
1000078e0: 4fc490a1    	fmul.2d	v1, v5, v4[0]
1000078e4: 4e61d400    	fadd.2d	v0, v0, v1
1000078e8: fd4813e1    	ldr	d1, [sp, #0x1020]
1000078ec: 3d80f3e1    	str	q1, [sp, #0x3c0]
1000078f0: fd4817f2    	ldr	d18, [sp, #0x1028]
1000078f4: 3d8207f2    	str	q18, [sp, #0x810]
1000078f8: 4fc19261    	fmul.2d	v1, v19, v1[0]
1000078fc: 4e61d400    	fadd.2d	v0, v0, v1
100007900: 4fd290e1    	fmul.2d	v1, v7, v18[0]
100007904: 4e61d400    	fadd.2d	v0, v0, v1
100007908: fd481be1    	ldr	d1, [sp, #0x1030]
10000790c: 3d81a7e1    	str	q1, [sp, #0x690]
100007910: fd481ff2    	ldr	d18, [sp, #0x1038]
100007914: 3d8287f2    	str	q18, [sp, #0xa10]
100007918: 4fc192c1    	fmul.2d	v1, v22, v1[0]
10000791c: 4e61d400    	fadd.2d	v0, v0, v1
100007920: 4fd292a1    	fmul.2d	v1, v21, v18[0]
100007924: 4e61d400    	fadd.2d	v0, v0, v1
100007928: fd4823e1    	ldr	d1, [sp, #0x1040]
10000792c: 3d81c3e1    	str	q1, [sp, #0x700]
100007930: fd4827e4    	ldr	d4, [sp, #0x1048]
100007934: 3d8283e4    	str	q4, [sp, #0xa00]
100007938: 4fc19301    	fmul.2d	v1, v24, v1[0]
10000793c: 4e61d400    	fadd.2d	v0, v0, v1
100007940: 4fc49221    	fmul.2d	v1, v17, v4[0]
100007944: 4e61d400    	fadd.2d	v0, v0, v1
100007948: fd482be1    	ldr	d1, [sp, #0x1050]
10000794c: 3d81a3e1    	str	q1, [sp, #0x680]
100007950: fd482fe4    	ldr	d4, [sp, #0x1058]
100007954: 3d827fe4    	str	q4, [sp, #0x9f0]
100007958: 4fc191c1    	fmul.2d	v1, v14, v1[0]
10000795c: 4e61d400    	fadd.2d	v0, v0, v1
100007960: 4fc49281    	fmul.2d	v1, v20, v4[0]
100007964: 4e61d400    	fadd.2d	v0, v0, v1
100007968: 3d81dbe0    	str	q0, [sp, #0x760]
10000796c: fd4833e0    	ldr	d0, [sp, #0x1060]
100007970: 3d8177e0    	str	q0, [sp, #0x5d0]
100007974: fd4837e1    	ldr	d1, [sp, #0x1068]
100007978: 3d827be1    	str	q1, [sp, #0x9e0]
10000797c: 4fc09060    	fmul.2d	v0, v3, v0[0]
100007980: 4e62d400    	fadd.2d	v0, v0, v2
100007984: 6f00e404    	movi.2d	v4, #0000000000000000
100007988: 4fc190a1    	fmul.2d	v1, v5, v1[0]
10000798c: 4e61d400    	fadd.2d	v0, v0, v1
100007990: fd483be1    	ldr	d1, [sp, #0x1070]
100007994: 3d814be1    	str	q1, [sp, #0x520]
100007998: fd483ff2    	ldr	d18, [sp, #0x1078]
10000799c: 3d8277f2    	str	q18, [sp, #0x9d0]
1000079a0: 4fc19261    	fmul.2d	v1, v19, v1[0]
1000079a4: 4e61d400    	fadd.2d	v0, v0, v1
1000079a8: 4fd290e1    	fmul.2d	v1, v7, v18[0]
1000079ac: 4e61d400    	fadd.2d	v0, v0, v1
1000079b0: fd4843e1    	ldr	d1, [sp, #0x1080]
1000079b4: 3d8203e1    	str	q1, [sp, #0x800]
1000079b8: fd4847f2    	ldr	d18, [sp, #0x1088]
1000079bc: 3d8273f2    	str	q18, [sp, #0x9c0]
1000079c0: 4fc192c1    	fmul.2d	v1, v22, v1[0]
1000079c4: 4e61d400    	fadd.2d	v0, v0, v1
1000079c8: 4fd292a1    	fmul.2d	v1, v21, v18[0]
1000079cc: 4e61d400    	fadd.2d	v0, v0, v1
1000079d0: fd484be1    	ldr	d1, [sp, #0x1090]
1000079d4: 3d818fe1    	str	q1, [sp, #0x630]
1000079d8: fd484ff2    	ldr	d18, [sp, #0x1098]
1000079dc: 3d826ff2    	str	q18, [sp, #0x9b0]
1000079e0: 4fc19301    	fmul.2d	v1, v24, v1[0]
1000079e4: 4e61d400    	fadd.2d	v0, v0, v1
1000079e8: 4fd29221    	fmul.2d	v1, v17, v18[0]
1000079ec: 4e61d400    	fadd.2d	v0, v0, v1
1000079f0: fd4853e1    	ldr	d1, [sp, #0x10a0]
1000079f4: 3d8173e1    	str	q1, [sp, #0x5c0]
1000079f8: fd4857e2    	ldr	d2, [sp, #0x10a8]
1000079fc: 3d826be2    	str	q2, [sp, #0x9a0]
100007a00: 4fc191c1    	fmul.2d	v1, v14, v1[0]
100007a04: 4e61d400    	fadd.2d	v0, v0, v1
100007a08: 4fc29281    	fmul.2d	v1, v20, v2[0]
100007a0c: 4eb41e97    	mov.16b	v23, v20
100007a10: 4e61d400    	fadd.2d	v0, v0, v1
100007a14: 3d81d7e0    	str	q0, [sp, #0x750]
100007a18: fd485be0    	ldr	d0, [sp, #0x10b0]
100007a1c: 3d818be0    	str	q0, [sp, #0x620]
100007a20: fd485fe2    	ldr	d2, [sp, #0x10b8]
100007a24: 3d8267e2    	str	q2, [sp, #0x990]
100007a28: 4fc09060    	fmul.2d	v0, v3, v0[0]
100007a2c: 4e64d400    	fadd.2d	v0, v0, v4
100007a30: 4fc290a1    	fmul.2d	v1, v5, v2[0]
100007a34: 4e61d400    	fadd.2d	v0, v0, v1
100007a38: fd4863e1    	ldr	d1, [sp, #0x10c0]
100007a3c: 3d816fe1    	str	q1, [sp, #0x5b0]
100007a40: fd4867e2    	ldr	d2, [sp, #0x10c8]
100007a44: 3d8263e2    	str	q2, [sp, #0x980]
100007a48: 4fc19261    	fmul.2d	v1, v19, v1[0]
100007a4c: 4e61d400    	fadd.2d	v0, v0, v1
100007a50: 4fc290e1    	fmul.2d	v1, v7, v2[0]
100007a54: 4e61d400    	fadd.2d	v0, v0, v1
100007a58: fd486be1    	ldr	d1, [sp, #0x10d0]
100007a5c: 3d8103e1    	str	q1, [sp, #0x400]
100007a60: fd486ff2    	ldr	d18, [sp, #0x10d8]
100007a64: 3d81fff2    	str	q18, [sp, #0x7f0]
100007a68: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100007a6c: 4e61d400    	fadd.2d	v0, v0, v1
100007a70: 4fd292a1    	fmul.2d	v1, v21, v18[0]
100007a74: 4e61d400    	fadd.2d	v0, v0, v1
100007a78: fd4873e1    	ldr	d1, [sp, #0x10e0]
100007a7c: 3d816be1    	str	q1, [sp, #0x5a0]
100007a80: fd4877e2    	ldr	d2, [sp, #0x10e8]
100007a84: 3d825fe2    	str	q2, [sp, #0x970]
100007a88: 4fc19301    	fmul.2d	v1, v24, v1[0]
100007a8c: 4e61d400    	fadd.2d	v0, v0, v1
100007a90: 4fc29221    	fmul.2d	v1, v17, v2[0]
100007a94: 4eb11e34    	mov.16b	v20, v17
100007a98: 4e61d400    	fadd.2d	v0, v0, v1
100007a9c: fd487be1    	ldr	d1, [sp, #0x10f0]
100007aa0: 3d8167e1    	str	q1, [sp, #0x590]
100007aa4: fd487fe2    	ldr	d2, [sp, #0x10f8]
100007aa8: 3d825be2    	str	q2, [sp, #0x960]
100007aac: 4fc191c1    	fmul.2d	v1, v14, v1[0]
100007ab0: 4e61d400    	fadd.2d	v0, v0, v1
100007ab4: 4fc292e1    	fmul.2d	v1, v23, v2[0]
100007ab8: 4e61d400    	fadd.2d	v0, v0, v1
100007abc: 3d807fe0    	str	q0, [sp, #0x1f0]
100007ac0: fd4883f1    	ldr	d17, [sp, #0x1100]
100007ac4: fd4887e2    	ldr	d2, [sp, #0x1108]
100007ac8: 3d8257e2    	str	q2, [sp, #0x950]
100007acc: 4fd19060    	fmul.2d	v0, v3, v17[0]
100007ad0: 3d812ff1    	str	q17, [sp, #0x4b0]
100007ad4: 4e64d400    	fadd.2d	v0, v0, v4
100007ad8: 4fc290a1    	fmul.2d	v1, v5, v2[0]
100007adc: 4e61d400    	fadd.2d	v0, v0, v1
100007ae0: fd488be1    	ldr	d1, [sp, #0x1110]
100007ae4: 3d8163e1    	str	q1, [sp, #0x580]
100007ae8: fd488fe2    	ldr	d2, [sp, #0x1118]
100007aec: 3d8253e2    	str	q2, [sp, #0x940]
100007af0: 4fc19261    	fmul.2d	v1, v19, v1[0]
100007af4: 4e61d400    	fadd.2d	v0, v0, v1
100007af8: 4fc290e1    	fmul.2d	v1, v7, v2[0]
100007afc: 4e61d400    	fadd.2d	v0, v0, v1
100007b00: fd4893e1    	ldr	d1, [sp, #0x1120]
100007b04: 3d815fe1    	str	q1, [sp, #0x570]
100007b08: 4eb61ed2    	mov.16b	v18, v22
100007b0c: 4fc192c1    	fmul.2d	v1, v22, v1[0]
100007b10: 4e61d400    	fadd.2d	v0, v0, v1
100007b14: fd4897e1    	ldr	d1, [sp, #0x1128]
100007b18: 3d824fe1    	str	q1, [sp, #0x930]
100007b1c: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100007b20: 4e61d400    	fadd.2d	v0, v0, v1
100007b24: fd489be1    	ldr	d1, [sp, #0x1130]
100007b28: 3d81fbe1    	str	q1, [sp, #0x7e0]
100007b2c: 4fc19301    	fmul.2d	v1, v24, v1[0]
100007b30: 4e61d400    	fadd.2d	v0, v0, v1
100007b34: fd489fe1    	ldr	d1, [sp, #0x1138]
100007b38: 3d824be1    	str	q1, [sp, #0x920]
100007b3c: 4fc19281    	fmul.2d	v1, v20, v1[0]
100007b40: 4eb41e96    	mov.16b	v22, v20
100007b44: 4e61d400    	fadd.2d	v0, v0, v1
100007b48: fd48a3e1    	ldr	d1, [sp, #0x1140]
100007b4c: 3d815be1    	str	q1, [sp, #0x560]
100007b50: 4fc191c1    	fmul.2d	v1, v14, v1[0]
100007b54: 4e61d400    	fadd.2d	v0, v0, v1
100007b58: fd48a7e1    	ldr	d1, [sp, #0x1148]
100007b5c: 3d8247e1    	str	q1, [sp, #0x910]
100007b60: 4fc192e1    	fmul.2d	v1, v23, v1[0]
100007b64: 4e61d400    	fadd.2d	v0, v0, v1
100007b68: 3d807be0    	str	q0, [sp, #0x1e0]
100007b6c: fd48abf4    	ldr	d20, [sp, #0x1150]
100007b70: 4fd49060    	fmul.2d	v0, v3, v20[0]
100007b74: 3d812bf4    	str	q20, [sp, #0x4a0]
100007b78: 4e64d400    	fadd.2d	v0, v0, v4
100007b7c: fd48affd    	ldr	d29, [sp, #0x1158]
100007b80: 4fdd90a1    	fmul.2d	v1, v5, v29[0]
100007b84: 4e61d400    	fadd.2d	v0, v0, v1
100007b88: fd48b3ea    	ldr	d10, [sp, #0x1160]
100007b8c: 4fca9261    	fmul.2d	v1, v19, v10[0]
100007b90: 3d8127ea    	str	q10, [sp, #0x490]
100007b94: 4e61d400    	fadd.2d	v0, v0, v1
100007b98: fd48b7ed    	ldr	d13, [sp, #0x1168]
100007b9c: 4fcd90e1    	fmul.2d	v1, v7, v13[0]
100007ba0: 4e61d400    	fadd.2d	v0, v0, v1
100007ba4: fd48bbe1    	ldr	d1, [sp, #0x1170]
100007ba8: 3d8157e1    	str	q1, [sp, #0x550]
100007bac: 4fc19241    	fmul.2d	v1, v18, v1[0]
100007bb0: 4e61d400    	fadd.2d	v0, v0, v1
100007bb4: fd48bfe1    	ldr	d1, [sp, #0x1178]
100007bb8: 3d8243e1    	str	q1, [sp, #0x900]
100007bbc: 4fc192a1    	fmul.2d	v1, v21, v1[0]
100007bc0: 4e61d400    	fadd.2d	v0, v0, v1
100007bc4: fd48c3e1    	ldr	d1, [sp, #0x1180]
100007bc8: 3d80ffe1    	str	q1, [sp, #0x3f0]
100007bcc: 4fc19301    	fmul.2d	v1, v24, v1[0]
100007bd0: 4e61d400    	fadd.2d	v0, v0, v1
100007bd4: fd48c7e1    	ldr	d1, [sp, #0x1188]
100007bd8: 3d81f7e1    	str	q1, [sp, #0x7d0]
100007bdc: 4fc192c2    	fmul.2d	v2, v22, v1[0]
100007be0: 4eb61edb    	mov.16b	v27, v22
100007be4: 4e62d400    	fadd.2d	v0, v0, v2
100007be8: fd48cbe1    	ldr	d1, [sp, #0x1190]
100007bec: 3d8153e1    	str	q1, [sp, #0x540]
100007bf0: 4fc191c2    	fmul.2d	v2, v14, v1[0]
100007bf4: 4e62d400    	fadd.2d	v0, v0, v2
100007bf8: fd48cfe1    	ldr	d1, [sp, #0x1198]
100007bfc: 3d823fe1    	str	q1, [sp, #0x8f0]
100007c00: 4fc192e2    	fmul.2d	v2, v23, v1[0]
100007c04: 4eb71efe    	mov.16b	v30, v23
100007c08: 4e62d400    	fadd.2d	v0, v0, v2
100007c0c: 3d8077e0    	str	q0, [sp, #0x1d0]
100007c10: fd48d3ec    	ldr	d12, [sp, #0x11a0]
100007c14: 4fcc9060    	fmul.2d	v0, v3, v12[0]
100007c18: 4e64d400    	fadd.2d	v0, v0, v4
100007c1c: fd48d7f6    	ldr	d22, [sp, #0x11a8]
100007c20: 4ea51ca1    	mov.16b	v1, v5
100007c24: 4fd690a2    	fmul.2d	v2, v5, v22[0]
100007c28: 3d8233f6    	str	q22, [sp, #0x8c0]
100007c2c: 4e62d400    	fadd.2d	v0, v0, v2
100007c30: fd48dbf9    	ldr	d25, [sp, #0x11b0]
100007c34: 4fd99262    	fmul.2d	v2, v19, v25[0]
100007c38: 4e62d400    	fadd.2d	v0, v0, v2
100007c3c: fd48dffa    	ldr	d26, [sp, #0x11b8]
100007c40: 4fda90e2    	fmul.2d	v2, v7, v26[0]
100007c44: 4e62d400    	fadd.2d	v0, v0, v2
100007c48: fd48e3ff    	ldr	d31, [sp, #0x11c0]
100007c4c: 4fdf9242    	fmul.2d	v2, v18, v31[0]
100007c50: 4eb21e57    	mov.16b	v23, v18
100007c54: 3d8123ff    	str	q31, [sp, #0x480]
100007c58: 4e62d400    	fadd.2d	v0, v0, v2
100007c5c: fd48e7ef    	ldr	d15, [sp, #0x11c8]
100007c60: 4fcf92a2    	fmul.2d	v2, v21, v15[0]
100007c64: 3d822fef    	str	q15, [sp, #0x8b0]
100007c68: 4eb51eb2    	mov.16b	v18, v21
100007c6c: 4e62d400    	fadd.2d	v0, v0, v2
100007c70: fd48ebe2    	ldr	d2, [sp, #0x11d0]
100007c74: 3d814fe2    	str	q2, [sp, #0x530]
100007c78: 4eb81f05    	mov.16b	v5, v24
100007c7c: 4fc29302    	fmul.2d	v2, v24, v2[0]
100007c80: 4e62d400    	fadd.2d	v0, v0, v2
100007c84: fd48efe2    	ldr	d2, [sp, #0x11d8]
100007c88: 3d823be2    	str	q2, [sp, #0x8e0]
100007c8c: 4fc29362    	fmul.2d	v2, v27, v2[0]
100007c90: 4ebb1f69    	mov.16b	v9, v27
100007c94: 4e62d400    	fadd.2d	v0, v0, v2
100007c98: fd48f3e2    	ldr	d2, [sp, #0x11e0]
100007c9c: 3d81f3e2    	str	q2, [sp, #0x7c0]
100007ca0: 4fc291c2    	fmul.2d	v2, v14, v2[0]
100007ca4: 4e62d400    	fadd.2d	v0, v0, v2
100007ca8: fd48f7e2    	ldr	d2, [sp, #0x11e8]
100007cac: 3d8237e2    	str	q2, [sp, #0x8d0]
100007cb0: 4fc293c2    	fmul.2d	v2, v30, v2[0]
100007cb4: 4ebe1fcb    	mov.16b	v11, v30
100007cb8: 4e62d400    	fadd.2d	v0, v0, v2
100007cbc: 3d8073e0    	str	q0, [sp, #0x1c0]
100007cc0: fd48fbfb    	ldr	d27, [sp, #0x11f0]
100007cc4: 4fdb9060    	fmul.2d	v0, v3, v27[0]
100007cc8: 4e64d400    	fadd.2d	v0, v0, v4
100007ccc: fd48fffe    	ldr	d30, [sp, #0x11f8]
100007cd0: 4fde9022    	fmul.2d	v2, v1, v30[0]
100007cd4: 4e62d400    	fadd.2d	v0, v0, v2
100007cd8: fd4903e8    	ldr	d8, [sp, #0x1200]
100007cdc: 4fc89262    	fmul.2d	v2, v19, v8[0]
100007ce0: 4e62d400    	fadd.2d	v0, v0, v2
100007ce4: fd4907e1    	ldr	d1, [sp, #0x1208]
100007ce8: 4fc190e2    	fmul.2d	v2, v7, v1[0]
100007cec: 4ea11c27    	mov.16b	v7, v1
100007cf0: 3d822be1    	str	q1, [sp, #0x8a0]
100007cf4: 4e62d400    	fadd.2d	v0, v0, v2
100007cf8: fd490bf5    	ldr	d21, [sp, #0x1210]
100007cfc: 4fd592e2    	fmul.2d	v2, v23, v21[0]
100007d00: 3d811ff5    	str	q21, [sp, #0x470]
100007d04: 4e62d400    	fadd.2d	v0, v0, v2
100007d08: fd490ff8    	ldr	d24, [sp, #0x1218]
100007d0c: 4fd89242    	fmul.2d	v2, v18, v24[0]
100007d10: 4e62d400    	fadd.2d	v0, v0, v2
100007d14: fd4913f7    	ldr	d23, [sp, #0x1220]
100007d18: 4fd790a2    	fmul.2d	v2, v5, v23[0]
100007d1c: 3d811bf7    	str	q23, [sp, #0x460]
100007d20: 4e62d400    	fadd.2d	v0, v0, v2
100007d24: fd4917e1    	ldr	d1, [sp, #0x1228]
100007d28: 4fc19122    	fmul.2d	v2, v9, v1[0]
100007d2c: 4ea11c29    	mov.16b	v9, v1
100007d30: 3d8227e1    	str	q1, [sp, #0x890]
100007d34: 4e62d400    	fadd.2d	v0, v0, v2
100007d38: fd491be1    	ldr	d1, [sp, #0x1230]
100007d3c: 3d80e3e1    	str	q1, [sp, #0x380]
100007d40: 4fc191c2    	fmul.2d	v2, v14, v1[0]
100007d44: 4e62d400    	fadd.2d	v0, v0, v2
100007d48: fd491fe1    	ldr	d1, [sp, #0x1238]
100007d4c: 3d81ebe1    	str	q1, [sp, #0x7a0]
100007d50: 4fc19162    	fmul.2d	v2, v11, v1[0]
100007d54: 4e62d400    	fadd.2d	v0, v0, v2
100007d58: 3d806fe0    	str	q0, [sp, #0x1b0]
100007d5c: 3dc13fe1    	ldr	q1, [sp, #0x4f0]
100007d60: 1e7c0820    	fmul	d0, d1, d28
100007d64: 2f00e41c    	movi	d28, #0000000000000000
100007d68: 1e7c2800    	fadd	d0, d0, d28
100007d6c: fd417beb    	ldr	d11, [sp, #0x2f0]
100007d70: 3dc0fbe5    	ldr	q5, [sp, #0x3e0]
100007d74: 1e650962    	fmul	d2, d11, d5
100007d78: 1e622800    	fadd	d0, d0, d2
100007d7c: 3dc13be3    	ldr	q3, [sp, #0x4e0]
100007d80: 1e700862    	fmul	d2, d3, d16
100007d84: 1e622800    	fadd	d0, d0, d2
100007d88: fd4183f3    	ldr	d19, [sp, #0x300]
100007d8c: 1e660a62    	fmul	d2, d19, d6
100007d90: 1e622800    	fadd	d0, d0, d2
100007d94: 3dc137e6    	ldr	q6, [sp, #0x4d0]
100007d98: 3dc177e2    	ldr	q2, [sp, #0x5d0]
100007d9c: 1e6208c2    	fmul	d2, d6, d2
100007da0: 1e622800    	fadd	d0, d0, d2
100007da4: fd418bf2    	ldr	d18, [sp, #0x310]
100007da8: 3dc18be2    	ldr	q2, [sp, #0x620]
100007dac: 1e620a42    	fmul	d2, d18, d2
100007db0: 1e622800    	fadd	d0, d0, d2
100007db4: 3dc133f0    	ldr	q16, [sp, #0x4c0]
100007db8: 1e710a02    	fmul	d2, d16, d17
100007dbc: 1e622800    	fadd	d0, d0, d2
100007dc0: fd4103f1    	ldr	d17, [sp, #0x200]
100007dc4: 1e740a22    	fmul	d2, d17, d20
100007dc8: 1e622800    	fadd	d0, d0, d2
100007dcc: 3dc117f4    	ldr	q20, [sp, #0x450]
100007dd0: 1e6c0a82    	fmul	d2, d20, d12
100007dd4: 1e622800    	fadd	d0, d0, d2
100007dd8: 3dc0e7e4    	ldr	q4, [sp, #0x390]
100007ddc: 1e7b0882    	fmul	d2, d4, d27
100007de0: 1e622800    	fadd	d0, d0, d2
100007de4: 3d806be0    	str	q0, [sp, #0x1a0]
100007de8: 3dc2c3e0    	ldr	q0, [sp, #0xb00]
100007dec: 1e600820    	fmul	d0, d1, d0
100007df0: 1e7c2800    	fadd	d0, d0, d28
100007df4: 3dc20fe2    	ldr	q2, [sp, #0x830]
100007df8: 1e620962    	fmul	d2, d11, d2
100007dfc: 1e622800    	fadd	d0, d0, d2
100007e00: 3dc29fe2    	ldr	q2, [sp, #0xa70]
100007e04: 1e620862    	fmul	d2, d3, d2
100007e08: 1e622800    	fadd	d0, d0, d2
100007e0c: 3dc28be2    	ldr	q2, [sp, #0xa20]
100007e10: 1e620a62    	fmul	d2, d19, d2
100007e14: 1e622800    	fadd	d0, d0, d2
100007e18: 3dc27be2    	ldr	q2, [sp, #0x9e0]
100007e1c: 1e6208c2    	fmul	d2, d6, d2
100007e20: 1e622800    	fadd	d0, d0, d2
100007e24: 3dc267e2    	ldr	q2, [sp, #0x990]
100007e28: 1e620a42    	fmul	d2, d18, d2
100007e2c: 1e622800    	fadd	d0, d0, d2
100007e30: 3dc257e2    	ldr	q2, [sp, #0x950]
100007e34: 1e620a02    	fmul	d2, d16, d2
100007e38: 1e622800    	fadd	d0, d0, d2
100007e3c: 1e7d0a22    	fmul	d2, d17, d29
100007e40: 1e622800    	fadd	d0, d0, d2
100007e44: 1e760a82    	fmul	d2, d20, d22
100007e48: 1e622800    	fadd	d0, d0, d2
100007e4c: 1e7e0882    	fmul	d2, d4, d30
100007e50: 1e622800    	fadd	d0, d0, d2
100007e54: 3d8067e0    	str	q0, [sp, #0x190]
100007e58: 3dc1bbe0    	ldr	q0, [sp, #0x6e0]
100007e5c: 1e600820    	fmul	d0, d1, d0
100007e60: 1e7c2800    	fadd	d0, d0, d28
100007e64: 3dc1cfe2    	ldr	q2, [sp, #0x730]
100007e68: 1e620962    	fmul	d2, d11, d2
100007e6c: 1e622800    	fadd	d0, d0, d2
100007e70: 3dc20be2    	ldr	q2, [sp, #0x820]
100007e74: 1e620862    	fmul	d2, d3, d2
100007e78: 1e622800    	fadd	d0, d0, d2
100007e7c: 3dc0f3e2    	ldr	q2, [sp, #0x3c0]
100007e80: 1e620a62    	fmul	d2, d19, d2
100007e84: 1e622800    	fadd	d0, d0, d2
100007e88: 3dc14bf6    	ldr	q22, [sp, #0x520]
100007e8c: 1e7608c2    	fmul	d2, d6, d22
100007e90: 1e622800    	fadd	d0, d0, d2
100007e94: 3dc16fe2    	ldr	q2, [sp, #0x5b0]
100007e98: 1e620a42    	fmul	d2, d18, d2
100007e9c: 1e622800    	fadd	d0, d0, d2
100007ea0: 3dc163e2    	ldr	q2, [sp, #0x580]
100007ea4: 1e620a02    	fmul	d2, d16, d2
100007ea8: 1e622800    	fadd	d0, d0, d2
100007eac: 1e6a0a22    	fmul	d2, d17, d10
100007eb0: 1e622800    	fadd	d0, d0, d2
100007eb4: 1e790a82    	fmul	d2, d20, d25
100007eb8: 1e622800    	fadd	d0, d0, d2
100007ebc: 1e680882    	fmul	d2, d4, d8
100007ec0: 1e622800    	fadd	d0, d0, d2
100007ec4: 3d8063e0    	str	q0, [sp, #0x180]
100007ec8: 3dc2bfe0    	ldr	q0, [sp, #0xaf0]
100007ecc: 1e600820    	fmul	d0, d1, d0
100007ed0: 1e7c2800    	fadd	d0, d0, d28
100007ed4: 3dc2afe2    	ldr	q2, [sp, #0xab0]
100007ed8: 1e620962    	fmul	d2, d11, d2
100007edc: 1e622800    	fadd	d0, d0, d2
100007ee0: 3dc29be2    	ldr	q2, [sp, #0xa60]
100007ee4: 1e620862    	fmul	d2, d3, d2
100007ee8: 1e622800    	fadd	d0, d0, d2
100007eec: 3dc207e2    	ldr	q2, [sp, #0x810]
100007ef0: 1e620a62    	fmul	d2, d19, d2
100007ef4: 1e622800    	fadd	d0, d0, d2
100007ef8: 3dc277e2    	ldr	q2, [sp, #0x9d0]
100007efc: 1e6208c2    	fmul	d2, d6, d2
100007f00: 1e622800    	fadd	d0, d0, d2
100007f04: 3dc263e2    	ldr	q2, [sp, #0x980]
100007f08: 1e620a42    	fmul	d2, d18, d2
100007f0c: 1e622800    	fadd	d0, d0, d2
100007f10: 3dc253e2    	ldr	q2, [sp, #0x940]
100007f14: 1e620a02    	fmul	d2, d16, d2
100007f18: 1e622800    	fadd	d0, d0, d2
100007f1c: 1e6d0a22    	fmul	d2, d17, d13
100007f20: 4ead1daa    	mov.16b	v10, v13
100007f24: 1e622800    	fadd	d0, d0, d2
100007f28: 1e7a0a82    	fmul	d2, d20, d26
100007f2c: 1e622800    	fadd	d0, d0, d2
100007f30: 1e670882    	fmul	d2, d4, d7
100007f34: 1e622800    	fadd	d0, d0, d2
100007f38: 3d805fe0    	str	q0, [sp, #0x170]
100007f3c: 3dc1b7e0    	ldr	q0, [sp, #0x6d0]
100007f40: 1e600820    	fmul	d0, d1, d0
100007f44: 1e7c2800    	fadd	d0, d0, d28
100007f48: 3dc1b3e2    	ldr	q2, [sp, #0x6c0]
100007f4c: 1e620962    	fmul	d2, d11, d2
100007f50: 1e622800    	fadd	d0, d0, d2
100007f54: 3dc197ed    	ldr	q13, [sp, #0x650]
100007f58: 1e6d0862    	fmul	d2, d3, d13
100007f5c: 4ead1da7    	mov.16b	v7, v13
100007f60: 1e622800    	fadd	d0, d0, d2
100007f64: 3dc1a7e2    	ldr	q2, [sp, #0x690]
100007f68: 1e620a62    	fmul	d2, d19, d2
100007f6c: 1e622800    	fadd	d0, d0, d2
100007f70: 3dc203e2    	ldr	q2, [sp, #0x800]
100007f74: 1e6208c2    	fmul	d2, d6, d2
100007f78: 1e622800    	fadd	d0, d0, d2
100007f7c: 3dc103e2    	ldr	q2, [sp, #0x400]
100007f80: 1e620a42    	fmul	d2, d18, d2
100007f84: 1e622800    	fadd	d0, d0, d2
100007f88: 3dc15fe2    	ldr	q2, [sp, #0x570]
100007f8c: 1e620a02    	fmul	d2, d16, d2
100007f90: 1e622800    	fadd	d0, d0, d2
100007f94: 3dc157e2    	ldr	q2, [sp, #0x550]
100007f98: 1e620a22    	fmul	d2, d17, d2
100007f9c: 1e622800    	fadd	d0, d0, d2
100007fa0: 1e7f0a82    	fmul	d2, d20, d31
100007fa4: 1e622800    	fadd	d0, d0, d2
100007fa8: 1e750882    	fmul	d2, d4, d21
100007fac: 1e622800    	fadd	d0, d0, d2
100007fb0: 3d805be0    	str	q0, [sp, #0x160]
100007fb4: 3dc2bbe0    	ldr	q0, [sp, #0xae0]
100007fb8: 1e600820    	fmul	d0, d1, d0
100007fbc: 1e7c2800    	fadd	d0, d0, d28
100007fc0: 3dc2abe2    	ldr	q2, [sp, #0xaa0]
100007fc4: 1e620962    	fmul	d2, d11, d2
100007fc8: 1e622800    	fadd	d0, d0, d2
100007fcc: 3dc297e2    	ldr	q2, [sp, #0xa50]
100007fd0: 1e620862    	fmul	d2, d3, d2
100007fd4: 1e622800    	fadd	d0, d0, d2
100007fd8: 3dc287e2    	ldr	q2, [sp, #0xa10]
100007fdc: 1e620a62    	fmul	d2, d19, d2
100007fe0: 1e622800    	fadd	d0, d0, d2
100007fe4: 3dc273e2    	ldr	q2, [sp, #0x9c0]
100007fe8: 1e6208c2    	fmul	d2, d6, d2
100007fec: 1e622800    	fadd	d0, d0, d2
100007ff0: 3dc1ffe2    	ldr	q2, [sp, #0x7f0]
100007ff4: 1e620a42    	fmul	d2, d18, d2
100007ff8: 1e622800    	fadd	d0, d0, d2
100007ffc: 3dc24fe2    	ldr	q2, [sp, #0x930]
100008000: 1e620a02    	fmul	d2, d16, d2
100008004: 1e622800    	fadd	d0, d0, d2
100008008: 3dc243e2    	ldr	q2, [sp, #0x900]
10000800c: 1e620a22    	fmul	d2, d17, d2
100008010: 1e622800    	fadd	d0, d0, d2
100008014: 1e6f0a82    	fmul	d2, d20, d15
100008018: 1e622800    	fadd	d0, d0, d2
10000801c: 1e780882    	fmul	d2, d4, d24
100008020: 1e622800    	fadd	d0, d0, d2
100008024: 3d8057e0    	str	q0, [sp, #0x150]
100008028: 3dc1cbe0    	ldr	q0, [sp, #0x720]
10000802c: 1e600820    	fmul	d0, d1, d0
100008030: 1e7c2800    	fadd	d0, d0, d28
100008034: 3dc1abe2    	ldr	q2, [sp, #0x6a0]
100008038: 1e620962    	fmul	d2, d11, d2
10000803c: 1e622800    	fadd	d0, d0, d2
100008040: 3dc193ed    	ldr	q13, [sp, #0x640]
100008044: 1e6d0862    	fmul	d2, d3, d13
100008048: 4ead1db5    	mov.16b	v21, v13
10000804c: 1e622800    	fadd	d0, d0, d2
100008050: 3dc1c3e2    	ldr	q2, [sp, #0x700]
100008054: 1e620a62    	fmul	d2, d19, d2
100008058: 1e622800    	fadd	d0, d0, d2
10000805c: 3dc18fe2    	ldr	q2, [sp, #0x630]
100008060: 1e6208c2    	fmul	d2, d6, d2
100008064: 1e622800    	fadd	d0, d0, d2
100008068: 3dc16be2    	ldr	q2, [sp, #0x5a0]
10000806c: 1e620a42    	fmul	d2, d18, d2
100008070: 1e622800    	fadd	d0, d0, d2
100008074: 3dc1fbe2    	ldr	q2, [sp, #0x7e0]
100008078: 1e620a02    	fmul	d2, d16, d2
10000807c: 1e622800    	fadd	d0, d0, d2
100008080: 3dc0ffe2    	ldr	q2, [sp, #0x3f0]
100008084: 1e620a22    	fmul	d2, d17, d2
100008088: 1e622800    	fadd	d0, d0, d2
10000808c: 3dc14fe2    	ldr	q2, [sp, #0x530]
100008090: 1e620a82    	fmul	d2, d20, d2
100008094: 1e622800    	fadd	d0, d0, d2
100008098: 1e770882    	fmul	d2, d4, d23
10000809c: 1e622800    	fadd	d0, d0, d2
1000080a0: 3d8053e0    	str	q0, [sp, #0x140]
1000080a4: 3dc2b7e0    	ldr	q0, [sp, #0xad0]
1000080a8: 1e600820    	fmul	d0, d1, d0
1000080ac: 1e7c2800    	fadd	d0, d0, d28
1000080b0: 3dc2a7e2    	ldr	q2, [sp, #0xa90]
1000080b4: 1e620962    	fmul	d2, d11, d2
1000080b8: 1e622800    	fadd	d0, d0, d2
1000080bc: 3dc293e2    	ldr	q2, [sp, #0xa40]
1000080c0: 1e620862    	fmul	d2, d3, d2
1000080c4: 1e622800    	fadd	d0, d0, d2
1000080c8: 3dc283e2    	ldr	q2, [sp, #0xa00]
1000080cc: 1e620a62    	fmul	d2, d19, d2
1000080d0: 1e622800    	fadd	d0, d0, d2
1000080d4: 3dc26fe2    	ldr	q2, [sp, #0x9b0]
1000080d8: 1e6208c2    	fmul	d2, d6, d2
1000080dc: 1e622800    	fadd	d0, d0, d2
1000080e0: 3dc25fe2    	ldr	q2, [sp, #0x970]
1000080e4: 1e620a42    	fmul	d2, d18, d2
1000080e8: 1e622800    	fadd	d0, d0, d2
1000080ec: 3dc24be2    	ldr	q2, [sp, #0x920]
1000080f0: 1e620a02    	fmul	d2, d16, d2
1000080f4: 1e622800    	fadd	d0, d0, d2
1000080f8: 3dc1f7e2    	ldr	q2, [sp, #0x7d0]
1000080fc: 1e620a22    	fmul	d2, d17, d2
100008100: 1e622800    	fadd	d0, d0, d2
100008104: 3dc23be2    	ldr	q2, [sp, #0x8e0]
100008108: 1e620a82    	fmul	d2, d20, d2
10000810c: 1e622800    	fadd	d0, d0, d2
100008110: 1e690882    	fmul	d2, d4, d9
100008114: 1e622809    	fadd	d9, d0, d2
100008118: 3dc1c7e0    	ldr	q0, [sp, #0x710]
10000811c: 1e600820    	fmul	d0, d1, d0
100008120: 1e7c2800    	fadd	d0, d0, d28
100008124: 3dc1afe2    	ldr	q2, [sp, #0x6b0]
100008128: 1e620962    	fmul	d2, d11, d2
10000812c: 1e622800    	fadd	d0, d0, d2
100008130: 3dc1bfe2    	ldr	q2, [sp, #0x6f0]
100008134: 1e620862    	fmul	d2, d3, d2
100008138: 1e622800    	fadd	d0, d0, d2
10000813c: 3dc1a3e2    	ldr	q2, [sp, #0x680]
100008140: 1e620a62    	fmul	d2, d19, d2
100008144: 1e622800    	fadd	d0, d0, d2
100008148: 3dc173e2    	ldr	q2, [sp, #0x5c0]
10000814c: 1e6208c2    	fmul	d2, d6, d2
100008150: 1e622800    	fadd	d0, d0, d2
100008154: 3dc167e2    	ldr	q2, [sp, #0x590]
100008158: 1e620a42    	fmul	d2, d18, d2
10000815c: 1e622800    	fadd	d0, d0, d2
100008160: 3dc15be2    	ldr	q2, [sp, #0x560]
100008164: 1e620a02    	fmul	d2, d16, d2
100008168: 1e622800    	fadd	d0, d0, d2
10000816c: 3dc153e2    	ldr	q2, [sp, #0x540]
100008170: 1e620a22    	fmul	d2, d17, d2
100008174: 1e622800    	fadd	d0, d0, d2
100008178: 3dc1f3e2    	ldr	q2, [sp, #0x7c0]
10000817c: 1e620a82    	fmul	d2, d20, d2
100008180: 1e622800    	fadd	d0, d0, d2
100008184: 3dc0e3e2    	ldr	q2, [sp, #0x380]
100008188: 1e620882    	fmul	d2, d4, d2
10000818c: 1e622800    	fadd	d0, d0, d2
100008190: 3d804fe0    	str	q0, [sp, #0x130]
100008194: 3dc2b3e0    	ldr	q0, [sp, #0xac0]
100008198: 1e600820    	fmul	d0, d1, d0
10000819c: 3dc2a3e1    	ldr	q1, [sp, #0xa80]
1000081a0: 1e610962    	fmul	d2, d11, d1
1000081a4: 1e7c2800    	fadd	d0, d0, d28
1000081a8: 1e622800    	fadd	d0, d0, d2
1000081ac: 3dc28fe1    	ldr	q1, [sp, #0xa30]
1000081b0: 1e610862    	fmul	d2, d3, d1
1000081b4: 1e622800    	fadd	d0, d0, d2
1000081b8: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
1000081bc: 1e610a62    	fmul	d2, d19, d1
1000081c0: 1e622800    	fadd	d0, d0, d2
1000081c4: 3dc26be1    	ldr	q1, [sp, #0x9a0]
1000081c8: 1e6108c2    	fmul	d2, d6, d1
1000081cc: 1e622800    	fadd	d0, d0, d2
1000081d0: 3dc25be1    	ldr	q1, [sp, #0x960]
1000081d4: 1e610a42    	fmul	d2, d18, d1
1000081d8: 1e622800    	fadd	d0, d0, d2
1000081dc: 3dc247e1    	ldr	q1, [sp, #0x910]
1000081e0: 1e610a02    	fmul	d2, d16, d1
1000081e4: 1e622800    	fadd	d0, d0, d2
1000081e8: 3dc23fe1    	ldr	q1, [sp, #0x8f0]
1000081ec: 1e610a22    	fmul	d2, d17, d1
1000081f0: 1e622800    	fadd	d0, d0, d2
1000081f4: 3dc237e1    	ldr	q1, [sp, #0x8d0]
1000081f8: 1e610a82    	fmul	d2, d20, d1
1000081fc: 1e622800    	fadd	d0, d0, d2
100008200: 3dc1ebe1    	ldr	q1, [sp, #0x7a0]
100008204: 1e610882    	fmul	d2, d4, d1
100008208: 1e622800    	fadd	d0, d0, d2
10000820c: 3d80e7e0    	str	q0, [sp, #0x390]
100008210: 3dc147ed    	ldr	q13, [sp, #0x510]
100008214: 3dc1efe0    	ldr	q0, [sp, #0x7b0]
100008218: 1e6009a0    	fmul	d0, d13, d0
10000821c: 1e7c2800    	fadd	d0, d0, d28
100008220: fd411bf3    	ldr	d19, [sp, #0x230]
100008224: 1e650a62    	fmul	d2, d19, d5
100008228: 1e622800    	fadd	d0, d0, d2
10000822c: 3dc143e1    	ldr	q1, [sp, #0x500]
100008230: 3dc19be2    	ldr	q2, [sp, #0x660]
100008234: 1e620822    	fmul	d2, d1, d2
100008238: 1e622800    	fadd	d0, d0, d2
10000823c: fd4123f2    	ldr	d18, [sp, #0x240]
100008240: 3dc19fe2    	ldr	q2, [sp, #0x670]
100008244: 1e620a42    	fmul	d2, d18, d2
100008248: 1e622800    	fadd	d0, d0, d2
10000824c: ad598fe6    	ldp	q6, q3, [sp, #0x330]
100008250: 3dc177e2    	ldr	q2, [sp, #0x5d0]
100008254: 1e620862    	fmul	d2, d3, d2
100008258: 1e622800    	fadd	d0, d0, d2
10000825c: fd412bf1    	ldr	d17, [sp, #0x250]
100008260: 3dc18be2    	ldr	q2, [sp, #0x620]
100008264: 1e620a22    	fmul	d2, d17, d2
100008268: 1e622800    	fadd	d0, d0, d2
10000826c: 3dc12fe2    	ldr	q2, [sp, #0x4b0]
100008270: 1e6208c2    	fmul	d2, d6, d2
100008274: 1e622800    	fadd	d0, d0, d2
100008278: fd4133ef    	ldr	d15, [sp, #0x260]
10000827c: 3dc12be2    	ldr	q2, [sp, #0x4a0]
100008280: 1e6209e2    	fmul	d2, d15, d2
100008284: 1e622800    	fadd	d0, d0, d2
100008288: 3dc0cbf0    	ldr	q16, [sp, #0x320]
10000828c: 3d8113ec    	str	q12, [sp, #0x440]
100008290: 1e6c0a02    	fmul	d2, d16, d12
100008294: 1e622800    	fadd	d0, d0, d2
100008298: 3dc0d7ff    	ldr	q31, [sp, #0x350]
10000829c: 3d810bfb    	str	q27, [sp, #0x420]
1000082a0: 1e7b0be2    	fmul	d2, d31, d27
1000082a4: 1e622800    	fadd	d0, d0, d2
1000082a8: 3d8117e0    	str	q0, [sp, #0x450]
1000082ac: 3dc2c3e0    	ldr	q0, [sp, #0xb00]
1000082b0: 1e6009a0    	fmul	d0, d13, d0
1000082b4: 1e7c2800    	fadd	d0, d0, d28
1000082b8: 3dc20feb    	ldr	q11, [sp, #0x830]
1000082bc: 1e6b0a62    	fmul	d2, d19, d11
1000082c0: 1e622800    	fadd	d0, d0, d2
1000082c4: 3dc29fe2    	ldr	q2, [sp, #0xa70]
1000082c8: 1e620822    	fmul	d2, d1, d2
1000082cc: 1e622800    	fadd	d0, d0, d2
1000082d0: 3dc28be2    	ldr	q2, [sp, #0xa20]
1000082d4: 1e620a42    	fmul	d2, d18, d2
1000082d8: 1e622800    	fadd	d0, d0, d2
1000082dc: 3dc27be2    	ldr	q2, [sp, #0x9e0]
1000082e0: 1e620862    	fmul	d2, d3, d2
1000082e4: 1e622800    	fadd	d0, d0, d2
1000082e8: 3dc267e2    	ldr	q2, [sp, #0x990]
1000082ec: 1e620a22    	fmul	d2, d17, d2
1000082f0: 1e622800    	fadd	d0, d0, d2
1000082f4: 3dc257e2    	ldr	q2, [sp, #0x950]
1000082f8: 1e6208c2    	fmul	d2, d6, d2
1000082fc: 1e622800    	fadd	d0, d0, d2
100008300: 3d8223fd    	str	q29, [sp, #0x880]
100008304: 1e7d09e2    	fmul	d2, d15, d29
100008308: 1e622800    	fadd	d0, d0, d2
10000830c: 3dc233e2    	ldr	q2, [sp, #0x8c0]
100008310: 1e620a02    	fmul	d2, d16, d2
100008314: 1e622800    	fadd	d0, d0, d2
100008318: 3d8217fe    	str	q30, [sp, #0x850]
10000831c: 1e7e0be2    	fmul	d2, d31, d30
100008320: 1e622800    	fadd	d0, d0, d2
100008324: 3d8083e0    	str	q0, [sp, #0x200]
100008328: 3dc1bbe0    	ldr	q0, [sp, #0x6e0]
10000832c: 1e6009a0    	fmul	d0, d13, d0
100008330: 1e7c2800    	fadd	d0, d0, d28
100008334: 3dc1cfe2    	ldr	q2, [sp, #0x730]
100008338: 1e620a62    	fmul	d2, d19, d2
10000833c: 1e622800    	fadd	d0, d0, d2
100008340: 3dc20bfb    	ldr	q27, [sp, #0x820]
100008344: 1e7b0822    	fmul	d2, d1, d27
100008348: 1e622800    	fadd	d0, d0, d2
10000834c: 3dc0f3fd    	ldr	q29, [sp, #0x3c0]
100008350: 1e7d0a42    	fmul	d2, d18, d29
100008354: 1e622800    	fadd	d0, d0, d2
100008358: 1e760862    	fmul	d2, d3, d22
10000835c: 1e622800    	fadd	d0, d0, d2
100008360: 3dc16fe2    	ldr	q2, [sp, #0x5b0]
100008364: 1e620a22    	fmul	d2, d17, d2
100008368: 1e622800    	fadd	d0, d0, d2
10000836c: 3dc163e2    	ldr	q2, [sp, #0x580]
100008370: 1e6208c2    	fmul	d2, d6, d2
100008374: 1e622800    	fadd	d0, d0, d2
100008378: 3dc127e2    	ldr	q2, [sp, #0x490]
10000837c: 1e6209e2    	fmul	d2, d15, d2
100008380: 1e622800    	fadd	d0, d0, d2
100008384: 3d810ff9    	str	q25, [sp, #0x430]
100008388: 1e790a02    	fmul	d2, d16, d25
10000838c: 1e622800    	fadd	d0, d0, d2
100008390: 3d8107e8    	str	q8, [sp, #0x410]
100008394: 1e680be2    	fmul	d2, d31, d8
100008398: 1e622800    	fadd	d0, d0, d2
10000839c: 3d804be0    	str	q0, [sp, #0x120]
1000083a0: 3dc2bfe0    	ldr	q0, [sp, #0xaf0]
1000083a4: 1e6009a2    	fmul	d2, d13, d0
1000083a8: 1e7c2842    	fadd	d2, d2, d28
1000083ac: 3dc2afe0    	ldr	q0, [sp, #0xab0]
1000083b0: 1e600a64    	fmul	d4, d19, d0
1000083b4: 1e642842    	fadd	d2, d2, d4
1000083b8: 3dc29be0    	ldr	q0, [sp, #0xa60]
1000083bc: 1e600824    	fmul	d4, d1, d0
1000083c0: 1e642842    	fadd	d2, d2, d4
1000083c4: 3dc207f9    	ldr	q25, [sp, #0x810]
1000083c8: 1e790a44    	fmul	d4, d18, d25
1000083cc: 1e642842    	fadd	d2, d2, d4
1000083d0: 3dc277e0    	ldr	q0, [sp, #0x9d0]
1000083d4: 1e600864    	fmul	d4, d3, d0
1000083d8: 1e642842    	fadd	d2, d2, d4
1000083dc: 3dc263e0    	ldr	q0, [sp, #0x980]
1000083e0: 1e600a24    	fmul	d4, d17, d0
1000083e4: 1e642842    	fadd	d2, d2, d4
1000083e8: 3dc253e0    	ldr	q0, [sp, #0x940]
1000083ec: 1e6008c4    	fmul	d4, d6, d0
1000083f0: 1e642842    	fadd	d2, d2, d4
1000083f4: 4eaa1d40    	mov.16b	v0, v10
1000083f8: 3d821fea    	str	q10, [sp, #0x870]
1000083fc: 1e6009e4    	fmul	d4, d15, d0
100008400: 1e642842    	fadd	d2, d2, d4
100008404: 3d821bfa    	str	q26, [sp, #0x860]
100008408: 1e7a0a04    	fmul	d4, d16, d26
10000840c: 1e642842    	fadd	d2, d2, d4
100008410: 3dc22be0    	ldr	q0, [sp, #0x8a0]
100008414: 1e600be4    	fmul	d4, d31, d0
100008418: 1e642840    	fadd	d0, d2, d4
10000841c: 3d8047e0    	str	q0, [sp, #0x110]
100008420: 3dc1b7e0    	ldr	q0, [sp, #0x6d0]
100008424: 1e6009a2    	fmul	d2, d13, d0
100008428: 1e7c2842    	fadd	d2, d2, d28
10000842c: 3dc1b3e0    	ldr	q0, [sp, #0x6c0]
100008430: 1e600a64    	fmul	d4, d19, d0
100008434: 1e642842    	fadd	d2, d2, d4
100008438: 1e670824    	fmul	d4, d1, d7
10000843c: 1e642842    	fadd	d2, d2, d4
100008440: 3dc1a7e0    	ldr	q0, [sp, #0x690]
100008444: 1e600a44    	fmul	d4, d18, d0
100008448: 1e642842    	fadd	d2, d2, d4
10000844c: 3dc203fa    	ldr	q26, [sp, #0x800]
100008450: 1e7a0864    	fmul	d4, d3, d26
100008454: 1e642842    	fadd	d2, d2, d4
100008458: 3dc103e0    	ldr	q0, [sp, #0x400]
10000845c: 1e600a24    	fmul	d4, d17, d0
100008460: 1e642842    	fadd	d2, d2, d4
100008464: 3dc15fe0    	ldr	q0, [sp, #0x570]
100008468: 1e6008c4    	fmul	d4, d6, d0
10000846c: 1e642842    	fadd	d2, d2, d4
100008470: 3dc157e0    	ldr	q0, [sp, #0x550]
100008474: 1e6009e4    	fmul	d4, d15, d0
100008478: 1e642842    	fadd	d2, d2, d4
10000847c: 3dc123e0    	ldr	q0, [sp, #0x480]
100008480: 1e600a04    	fmul	d4, d16, d0
100008484: 1e642842    	fadd	d2, d2, d4
100008488: 3dc11fe0    	ldr	q0, [sp, #0x470]
10000848c: 1e600be4    	fmul	d4, d31, d0
100008490: 1e642840    	fadd	d0, d2, d4
100008494: 3d8043e0    	str	q0, [sp, #0x100]
100008498: 3dc2bbe0    	ldr	q0, [sp, #0xae0]
10000849c: 1e6009a4    	fmul	d4, d13, d0
1000084a0: 1e7c2884    	fadd	d4, d4, d28
1000084a4: 3dc2abe0    	ldr	q0, [sp, #0xaa0]
1000084a8: 1e600a67    	fmul	d7, d19, d0
1000084ac: 1e672884    	fadd	d4, d4, d7
1000084b0: 3dc297e0    	ldr	q0, [sp, #0xa50]
1000084b4: 1e600827    	fmul	d7, d1, d0
1000084b8: 1e672884    	fadd	d4, d4, d7
1000084bc: 3dc287e0    	ldr	q0, [sp, #0xa10]
1000084c0: 1e600a47    	fmul	d7, d18, d0
1000084c4: 1e672884    	fadd	d4, d4, d7
1000084c8: 3dc273e0    	ldr	q0, [sp, #0x9c0]
1000084cc: 1e600867    	fmul	d7, d3, d0
1000084d0: 1e672884    	fadd	d4, d4, d7
1000084d4: 3dc1fff7    	ldr	q23, [sp, #0x7f0]
1000084d8: 1e770a27    	fmul	d7, d17, d23
1000084dc: 1e672884    	fadd	d4, d4, d7
1000084e0: 3dc24fe0    	ldr	q0, [sp, #0x930]
1000084e4: 1e6008c7    	fmul	d7, d6, d0
1000084e8: 1e672884    	fadd	d4, d4, d7
1000084ec: 3dc243e0    	ldr	q0, [sp, #0x900]
1000084f0: 1e6009e7    	fmul	d7, d15, d0
1000084f4: 1e672884    	fadd	d4, d4, d7
1000084f8: 3dc22fe0    	ldr	q0, [sp, #0x8b0]
1000084fc: 1e600a07    	fmul	d7, d16, d0
100008500: 1e672884    	fadd	d4, d4, d7
100008504: 3d8213f8    	str	q24, [sp, #0x840]
100008508: 1e780be7    	fmul	d7, d31, d24
10000850c: 1e672880    	fadd	d0, d4, d7
100008510: 3d803fe0    	str	q0, [sp, #0xf0]
100008514: 3dc1cbe0    	ldr	q0, [sp, #0x720]
100008518: 1e6009a7    	fmul	d7, d13, d0
10000851c: 1e7c28e7    	fadd	d7, d7, d28
100008520: 3dc1abe0    	ldr	q0, [sp, #0x6a0]
100008524: 1e600a74    	fmul	d20, d19, d0
100008528: 1e7428e7    	fadd	d7, d7, d20
10000852c: 1e750834    	fmul	d20, d1, d21
100008530: 1e7428e7    	fadd	d7, d7, d20
100008534: 3dc1c3e0    	ldr	q0, [sp, #0x700]
100008538: 1e600a54    	fmul	d20, d18, d0
10000853c: 1e7428e7    	fadd	d7, d7, d20
100008540: 3dc18fe0    	ldr	q0, [sp, #0x630]
100008544: 1e600874    	fmul	d20, d3, d0
100008548: 1e7428e7    	fadd	d7, d7, d20
10000854c: 3dc16be0    	ldr	q0, [sp, #0x5a0]
100008550: 1e600a34    	fmul	d20, d17, d0
100008554: 1e7428e7    	fadd	d7, d7, d20
100008558: 3dc1fbe4    	ldr	q4, [sp, #0x7e0]
10000855c: 1e6408d4    	fmul	d20, d6, d4
100008560: 1e7428e7    	fadd	d7, d7, d20
100008564: 3dc0ffe0    	ldr	q0, [sp, #0x3f0]
100008568: 1e6009f4    	fmul	d20, d15, d0
10000856c: 1e7428e7    	fadd	d7, d7, d20
100008570: 3dc14fe0    	ldr	q0, [sp, #0x530]
100008574: 1e600a14    	fmul	d20, d16, d0
100008578: 1e7428e7    	fadd	d7, d7, d20
10000857c: 3dc11be0    	ldr	q0, [sp, #0x460]
100008580: 1e600bf4    	fmul	d20, d31, d0
100008584: 1e7428e0    	fadd	d0, d7, d20
100008588: 3d803be0    	str	q0, [sp, #0xe0]
10000858c: 3dc2b7e5    	ldr	q5, [sp, #0xad0]
100008590: 1e6509b4    	fmul	d20, d13, d5
100008594: 1e7c2a94    	fadd	d20, d20, d28
100008598: 3dc2a7e5    	ldr	q5, [sp, #0xa90]
10000859c: 1e650a78    	fmul	d24, d19, d5
1000085a0: 1e782a94    	fadd	d20, d20, d24
1000085a4: 3dc293e5    	ldr	q5, [sp, #0xa40]
1000085a8: 1e650838    	fmul	d24, d1, d5
1000085ac: 1e782a94    	fadd	d20, d20, d24
1000085b0: 3dc283e5    	ldr	q5, [sp, #0xa00]
1000085b4: 1e650a58    	fmul	d24, d18, d5
1000085b8: 1e782a94    	fadd	d20, d20, d24
1000085bc: 3dc26fe5    	ldr	q5, [sp, #0x9b0]
1000085c0: 1e650878    	fmul	d24, d3, d5
1000085c4: 1e782a94    	fadd	d20, d20, d24
1000085c8: 3dc25fe5    	ldr	q5, [sp, #0x970]
1000085cc: 1e650a38    	fmul	d24, d17, d5
1000085d0: 1e782a94    	fadd	d20, d20, d24
1000085d4: 3dc24be0    	ldr	q0, [sp, #0x920]
1000085d8: 1e6008d8    	fmul	d24, d6, d0
1000085dc: 1e782a94    	fadd	d20, d20, d24
1000085e0: 3dc1f7e2    	ldr	q2, [sp, #0x7d0]
1000085e4: 1e6209f8    	fmul	d24, d15, d2
1000085e8: 1e782a94    	fadd	d20, d20, d24
1000085ec: 3dc23be0    	ldr	q0, [sp, #0x8e0]
1000085f0: 1e600a18    	fmul	d24, d16, d0
1000085f4: 1e782a94    	fadd	d20, d20, d24
1000085f8: 3dc227e0    	ldr	q0, [sp, #0x890]
1000085fc: 1e600bf8    	fmul	d24, d31, d0
100008600: 1e782a94    	fadd	d20, d20, d24
100008604: 3dc1c7e5    	ldr	q5, [sp, #0x710]
100008608: 1e6509b8    	fmul	d24, d13, d5
10000860c: 1e7c2b18    	fadd	d24, d24, d28
100008610: 3dc1afe5    	ldr	q5, [sp, #0x6b0]
100008614: 1e650a65    	fmul	d5, d19, d5
100008618: 1e652b05    	fadd	d5, d24, d5
10000861c: 3dc1bfe7    	ldr	q7, [sp, #0x6f0]
100008620: 1e670838    	fmul	d24, d1, d7
100008624: 1e7828a5    	fadd	d5, d5, d24
100008628: 3dc1a3e7    	ldr	q7, [sp, #0x680]
10000862c: 1e670a58    	fmul	d24, d18, d7
100008630: 1e7828a5    	fadd	d5, d5, d24
100008634: 3dc173f6    	ldr	q22, [sp, #0x5c0]
100008638: 1e760878    	fmul	d24, d3, d22
10000863c: 1e7828a5    	fadd	d5, d5, d24
100008640: 3dc167f6    	ldr	q22, [sp, #0x590]
100008644: 1e760a38    	fmul	d24, d17, d22
100008648: 1e7828a5    	fadd	d5, d5, d24
10000864c: 3dc15bf6    	ldr	q22, [sp, #0x560]
100008650: 1e7608d8    	fmul	d24, d6, d22
100008654: 1e7828a5    	fadd	d5, d5, d24
100008658: 3dc153f6    	ldr	q22, [sp, #0x540]
10000865c: 1e7609f8    	fmul	d24, d15, d22
100008660: 1e7828a5    	fadd	d5, d5, d24
100008664: 3dc1f3e0    	ldr	q0, [sp, #0x7c0]
100008668: 1e600a18    	fmul	d24, d16, d0
10000866c: 1e7828a5    	fadd	d5, d5, d24
100008670: 3dc0e3e7    	ldr	q7, [sp, #0x380]
100008674: 1e670bf8    	fmul	d24, d31, d7
100008678: 1e7828b8    	fadd	d24, d5, d24
10000867c: 3dc2b3e5    	ldr	q5, [sp, #0xac0]
100008680: 1e6509a5    	fmul	d5, d13, d5
100008684: 1e7c28a5    	fadd	d5, d5, d28
100008688: 3dc2a3f6    	ldr	q22, [sp, #0xa80]
10000868c: 1e760a7c    	fmul	d28, d19, d22
100008690: 1e7c28a5    	fadd	d5, d5, d28
100008694: 3dc28ff3    	ldr	q19, [sp, #0xa30]
100008698: 1e73083c    	fmul	d28, d1, d19
10000869c: 1e7c28a5    	fadd	d5, d5, d28
1000086a0: 3dc27fe1    	ldr	q1, [sp, #0x9f0]
1000086a4: 1e610a5c    	fmul	d28, d18, d1
1000086a8: 1e7c28a5    	fadd	d5, d5, d28
1000086ac: 3dc26be1    	ldr	q1, [sp, #0x9a0]
1000086b0: 1e61087c    	fmul	d28, d3, d1
1000086b4: 1e7c28a5    	fadd	d5, d5, d28
1000086b8: 3dc25be1    	ldr	q1, [sp, #0x960]
1000086bc: 1e610a3c    	fmul	d28, d17, d1
1000086c0: 1e7c28a5    	fadd	d5, d5, d28
1000086c4: 3dc247e1    	ldr	q1, [sp, #0x910]
1000086c8: 1e6108dc    	fmul	d28, d6, d1
1000086cc: 1e7c28a5    	fadd	d5, d5, d28
1000086d0: 3dc23fe1    	ldr	q1, [sp, #0x8f0]
1000086d4: 1e6109fc    	fmul	d28, d15, d1
1000086d8: 1e7c28a5    	fadd	d5, d5, d28
1000086dc: 3dc237e1    	ldr	q1, [sp, #0x8d0]
1000086e0: 1e610a1c    	fmul	d28, d16, d1
1000086e4: 1e7c28a5    	fadd	d5, d5, d28
1000086e8: 1e7e101c    	fmov	d28, #-1.00000000
1000086ec: 3dc1efe1    	ldr	q1, [sp, #0x7b0]
1000086f0: 1e7c2821    	fadd	d1, d1, d28
1000086f4: 3d81d3e1    	str	q1, [sp, #0x740]
1000086f8: 1e7c296a    	fadd	d10, d11, d28
1000086fc: fd013fea    	str	d10, [sp, #0x278]
100008700: 1e7c2b61    	fadd	d1, d27, d28
100008704: 3d817fe1    	str	q1, [sp, #0x5f0]
100008708: 1e7c2b21    	fadd	d1, d25, d28
10000870c: fd010be1    	str	d1, [sp, #0x210]
100008710: 1e7c2b41    	fadd	d1, d26, d28
100008714: 3d8183e1    	str	q1, [sp, #0x600]
100008718: 4ebd1fb1    	mov.16b	v17, v29
10000871c: 1e7c2ae1    	fadd	d1, d23, d28
100008720: fd010fe1    	str	d1, [sp, #0x218]
100008724: 1e7c2881    	fadd	d1, d4, d28
100008728: 3d8187e1    	str	q1, [sp, #0x610]
10000872c: 1e7c2841    	fadd	d1, d2, d28
100008730: fd0113e1    	str	d1, [sp, #0x220]
100008734: 1e7c2801    	fadd	d1, d0, d28
100008738: 3d817be1    	str	q1, [sp, #0x5e0]
10000873c: 3dc0fbe6    	ldr	q6, [sp, #0x3e0]
100008740: 3dc1ebe0    	ldr	q0, [sp, #0x7a0]
100008744: 1e7c2801    	fadd	d1, d0, d28
100008748: fd0117e1    	str	d1, [sp, #0x228]
10000874c: 1e600be1    	fmul	d1, d31, d0
100008750: 1e6128bf    	fadd	d31, d5, d1
100008754: ad4ccff0    	ldp	q16, q19, [sp, #0x190]
100008758: ad568ff2    	ldp	q18, q3, [sp, #0x2d0]
10000875c: 4fd39061    	fmul.2d	v1, v3, v19[0]
100008760: 6f00e404    	movi.2d	v4, #0000000000000000
100008764: 4e64d421    	fadd.2d	v1, v1, v4
100008768: 4fd09245    	fmul.2d	v5, v18, v16[0]
10000876c: 4e61d4a1    	fadd.2d	v1, v5, v1
100008770: ad4bd7f7    	ldp	q23, q21, [sp, #0x170]
100008774: ad55dbe0    	ldp	q0, q22, [sp, #0x2b0]
100008778: 4fd592c5    	fmul.2d	v5, v22, v21[0]
10000877c: 4e61d4a1    	fadd.2d	v1, v5, v1
100008780: 4fd79005    	fmul.2d	v5, v0, v23[0]
100008784: 4e61d4a1    	fadd.2d	v1, v5, v1
100008788: ad4ae7fa    	ldp	q26, q25, [sp, #0x150]
10000878c: ad54fbfb    	ldp	q27, q30, [sp, #0x290]
100008790: 4fd993c5    	fmul.2d	v5, v30, v25[0]
100008794: 4e61d4a1    	fadd.2d	v1, v5, v1
100008798: 4fda9365    	fmul.2d	v5, v27, v26[0]
10000879c: 4e61d4a1    	fadd.2d	v1, v5, v1
1000087a0: ad49f3eb    	ldp	q11, q28, [sp, #0x130]
1000087a4: 3dc0f7e8    	ldr	q8, [sp, #0x3d0]
1000087a8: 4fdc9105    	fmul.2d	v5, v8, v28[0]
1000087ac: 4e61d4a1    	fadd.2d	v1, v5, v1
1000087b0: 4ea91d3d    	mov.16b	v29, v9
1000087b4: ad5d27ec    	ldp	q12, q9, [sp, #0x3a0]
1000087b8: 4fdd9125    	fmul.2d	v5, v9, v29[0]
1000087bc: 4e61d4a1    	fadd.2d	v1, v5, v1
1000087c0: 4fcb91c5    	fmul.2d	v5, v14, v11[0]
1000087c4: 4e61d4a1    	fadd.2d	v1, v5, v1
1000087c8: 3dc0e7e2    	ldr	q2, [sp, #0x390]
1000087cc: 4fc29185    	fmul.2d	v5, v12, v2[0]
1000087d0: 4e61d4a1    	fadd.2d	v1, v5, v1
1000087d4: 3dc0dbe5    	ldr	q5, [sp, #0x360]
1000087d8: 4e61d4a5    	fadd.2d	v5, v5, v1
1000087dc: 3d80dbe5    	str	q5, [sp, #0x360]
1000087e0: 3dc117ed    	ldr	q13, [sp, #0x450]
1000087e4: 4fcd9061    	fmul.2d	v1, v3, v13[0]
1000087e8: 4e64d421    	fadd.2d	v1, v1, v4
1000087ec: 3dc083e4    	ldr	q4, [sp, #0x200]
1000087f0: 4fc49245    	fmul.2d	v5, v18, v4[0]
1000087f4: 4e61d4a1    	fadd.2d	v1, v5, v1
1000087f8: ad48bff2    	ldp	q18, q15, [sp, #0x110]
1000087fc: 4fcf92c5    	fmul.2d	v5, v22, v15[0]
100008800: 3dc18bea    	ldr	q10, [sp, #0x620]
100008804: 4e61d4a1    	fadd.2d	v1, v5, v1
100008808: 4fd29005    	fmul.2d	v5, v0, v18[0]
10000880c: 4e61d4a1    	fadd.2d	v1, v5, v1
100008810: 3dc043e2    	ldr	q2, [sp, #0x100]
100008814: 4fc293c5    	fmul.2d	v5, v30, v2[0]
100008818: 4e61d4a1    	fadd.2d	v1, v5, v1
10000881c: ad477be0    	ldp	q0, q30, [sp, #0xe0]
100008820: 4fde9365    	fmul.2d	v5, v27, v30[0]
100008824: 4e61d4a1    	fadd.2d	v1, v5, v1
100008828: 4fc09105    	fmul.2d	v5, v8, v0[0]
10000882c: 4e61d4a1    	fadd.2d	v1, v5, v1
100008830: 4fd49125    	fmul.2d	v5, v9, v20[0]
100008834: 3dc14bf6    	ldr	q22, [sp, #0x520]
100008838: 4e61d4a1    	fadd.2d	v1, v5, v1
10000883c: 4fd891c5    	fmul.2d	v5, v14, v24[0]
100008840: 4e61d4a1    	fadd.2d	v1, v5, v1
100008844: 3d80d7ff    	str	q31, [sp, #0x350]
100008848: 4fdf9185    	fmul.2d	v5, v12, v31[0]
10000884c: 4e61d4a1    	fadd.2d	v1, v5, v1
100008850: 3dc0a3e3    	ldr	q3, [sp, #0x280]
100008854: 4e61d463    	fadd.2d	v3, v3, v1
100008858: 1e604261    	fmov	d1, d19
10000885c: 3dc18fe9    	ldr	q9, [sp, #0x630]
100008860: 3d813fe1    	str	q1, [sp, #0x4f0]
100008864: fd017bf0    	str	d16, [sp, #0x2f0]
100008868: 1e6042a1    	fmov	d1, d21
10000886c: 3d813be1    	str	q1, [sp, #0x4e0]
100008870: fd0183f7    	str	d23, [sp, #0x300]
100008874: 1e604321    	fmov	d1, d25
100008878: 3d8137e1    	str	q1, [sp, #0x4d0]
10000887c: fd018bfa    	str	d26, [sp, #0x310]
100008880: 1e604381    	fmov	d1, d28
100008884: 3d8133e1    	str	q1, [sp, #0x4c0]
100008888: 1e6043ac    	fmov	d12, d29
10000888c: 1e604175    	fmov	d21, d11
100008890: 1e6041a1    	fmov	d1, d13
100008894: 3d8147e1    	str	q1, [sp, #0x510]
100008898: 1e60409f    	fmov	d31, d4
10000889c: 4ea31c79    	mov.16b	v25, v3
1000088a0: 1e6041e1    	fmov	d1, d15
1000088a4: 3d8143e1    	str	q1, [sp, #0x500]
1000088a8: 1e60425b    	fmov	d27, d18
1000088ac: 4ea71cf2    	mov.16b	v18, v7
1000088b0: 1e6043d7    	fmov	d23, d30
1000088b4: ad198be0    	stp	q0, q2, [sp, #0x330]
1000088b8: 3d80cbf8    	str	q24, [sp, #0x320]
1000088bc: ad5fe3fa    	ldp	q26, q24, [sp, #0x3f0]
1000088c0: 3dc1e7e0    	ldr	q0, [sp, #0x790]
1000088c4: 3dc1e3e1    	ldr	q1, [sp, #0x780]
1000088c8: 3dc1dfe2    	ldr	q2, [sp, #0x770]
1000088cc: 3dc1dbe3    	ldr	q3, [sp, #0x760]
1000088d0: 3dc1d7e4    	ldr	q4, [sp, #0x750]
1000088d4: ad4f17fe    	ldp	q30, q5, [sp, #0x1e0]
1000088d8: 3d80f7fe    	str	q30, [sp, #0x3d0]
1000088dc: ad4e77f0    	ldp	q16, q29, [sp, #0x1c0]
1000088e0: 3d80dff0    	str	q16, [sp, #0x370]
1000088e4: 3dc06ff0    	ldr	q16, [sp, #0x1b0]
1000088e8: ad1d77f0    	stp	q16, q29, [sp, #0x3a0]
1000088ec: 900000a8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
1000088f0: 9106c108    	add	x8, x8, #0x1b0
1000088f4: 3dc1d3f0    	ldr	q16, [sp, #0x740]
1000088f8: 3dc2c3fc    	ldr	q28, [sp, #0xb00]
1000088fc: 6d007110    	stp	d16, d28, [x8]
100008900: 3dc1bbe7    	ldr	q7, [sp, #0x6e0]
100008904: 3dc2bff0    	ldr	q16, [sp, #0xaf0]
100008908: 6d014107    	stp	d7, d16, [x8, #0x10]
10000890c: 3dc1b7f3    	ldr	q19, [sp, #0x6d0]
100008910: 3dc2bbf0    	ldr	q16, [sp, #0xae0]
100008914: 6d024113    	stp	d19, d16, [x8, #0x20]
100008918: 3dc1cbfd    	ldr	q29, [sp, #0x720]
10000891c: 3dc2b7f0    	ldr	q16, [sp, #0xad0]
100008920: 6d03411d    	stp	d29, d16, [x8, #0x30]
100008924: 3dc1c7fe    	ldr	q30, [sp, #0x710]
100008928: 3dc2b3f0    	ldr	q16, [sp, #0xac0]
10000892c: 6d04411e    	stp	d30, d16, [x8, #0x40]
100008930: 3d801500    	str	q0, [x8, #0x50]
100008934: fd413fe0    	ldr	d0, [sp, #0x278]
100008938: 6d060106    	stp	d6, d0, [x8, #0x60]
10000893c: 3dc1cfe0    	ldr	q0, [sp, #0x730]
100008940: fd003900    	str	d0, [x8, #0x70]
100008944: 3dc2afe0    	ldr	q0, [sp, #0xab0]
100008948: fd003d00    	str	d0, [x8, #0x78]
10000894c: 3dc1b3e0    	ldr	q0, [sp, #0x6c0]
100008950: fd004100    	str	d0, [x8, #0x80]
100008954: 3dc2abe0    	ldr	q0, [sp, #0xaa0]
100008958: fd004500    	str	d0, [x8, #0x88]
10000895c: 3dc1abe0    	ldr	q0, [sp, #0x6a0]
100008960: fd004900    	str	d0, [x8, #0x90]
100008964: 3dc2a7e0    	ldr	q0, [sp, #0xa90]
100008968: fd004d00    	str	d0, [x8, #0x98]
10000896c: 3dc1afe0    	ldr	q0, [sp, #0x6b0]
100008970: fd005100    	str	d0, [x8, #0xa0]
100008974: 3dc2a3e0    	ldr	q0, [sp, #0xa80]
100008978: fd005500    	str	d0, [x8, #0xa8]
10000897c: 3d802d01    	str	q1, [x8, #0xb0]
100008980: 3dc19be1    	ldr	q1, [sp, #0x660]
100008984: 3dc29fe0    	ldr	q0, [sp, #0xa70]
100008988: 6d0c0101    	stp	d1, d0, [x8, #0xc0]
10000898c: 3dc17fe0    	ldr	q0, [sp, #0x5f0]
100008990: fd006900    	str	d0, [x8, #0xd0]
100008994: 3dc29be0    	ldr	q0, [sp, #0xa60]
100008998: fd006d00    	str	d0, [x8, #0xd8]
10000899c: 3dc197e0    	ldr	q0, [sp, #0x650]
1000089a0: fd007100    	str	d0, [x8, #0xe0]
1000089a4: 3dc297e0    	ldr	q0, [sp, #0xa50]
1000089a8: fd007500    	str	d0, [x8, #0xe8]
1000089ac: 3dc193e0    	ldr	q0, [sp, #0x640]
1000089b0: fd007900    	str	d0, [x8, #0xf0]
1000089b4: 3dc293e0    	ldr	q0, [sp, #0xa40]
1000089b8: fd007d00    	str	d0, [x8, #0xf8]
1000089bc: 3dc1bfe0    	ldr	q0, [sp, #0x6f0]
1000089c0: fd008100    	str	d0, [x8, #0x100]
1000089c4: 3dc28fe0    	ldr	q0, [sp, #0xa30]
1000089c8: fd008500    	str	d0, [x8, #0x108]
1000089cc: 3d804502    	str	q2, [x8, #0x110]
1000089d0: 3dc19fe2    	ldr	q2, [sp, #0x670]
1000089d4: 3dc28be0    	ldr	q0, [sp, #0xa20]
1000089d8: 6d120102    	stp	d2, d0, [x8, #0x120]
1000089dc: fd410be0    	ldr	d0, [sp, #0x210]
1000089e0: 6d130111    	stp	d17, d0, [x8, #0x130]
1000089e4: 3dc1a7e0    	ldr	q0, [sp, #0x690]
1000089e8: fd00a100    	str	d0, [x8, #0x140]
1000089ec: 3dc287e0    	ldr	q0, [sp, #0xa10]
1000089f0: fd00a500    	str	d0, [x8, #0x148]
1000089f4: 3dc1c3e0    	ldr	q0, [sp, #0x700]
1000089f8: fd00a900    	str	d0, [x8, #0x150]
1000089fc: 3dc283e0    	ldr	q0, [sp, #0xa00]
100008a00: fd00ad00    	str	d0, [x8, #0x158]
100008a04: 3dc1a3e0    	ldr	q0, [sp, #0x680]
100008a08: fd00b100    	str	d0, [x8, #0x160]
100008a0c: 3dc27fe0    	ldr	q0, [sp, #0x9f0]
100008a10: fd00b500    	str	d0, [x8, #0x168]
100008a14: 3d805d03    	str	q3, [x8, #0x170]
100008a18: 3dc177e3    	ldr	q3, [sp, #0x5d0]
100008a1c: 3dc27be0    	ldr	q0, [sp, #0x9e0]
100008a20: 6d180103    	stp	d3, d0, [x8, #0x180]
100008a24: 3dc277e0    	ldr	q0, [sp, #0x9d0]
100008a28: 6d190116    	stp	d22, d0, [x8, #0x190]
100008a2c: 3dc183e0    	ldr	q0, [sp, #0x600]
100008a30: fd00d100    	str	d0, [x8, #0x1a0]
100008a34: 3dc273e0    	ldr	q0, [sp, #0x9c0]
100008a38: 6d1aa500    	stp	d0, d9, [x8, #0x1a8]
100008a3c: 3dc26fe0    	ldr	q0, [sp, #0x9b0]
100008a40: fd00dd00    	str	d0, [x8, #0x1b8]
100008a44: 3dc173e0    	ldr	q0, [sp, #0x5c0]
100008a48: fd00e100    	str	d0, [x8, #0x1c0]
100008a4c: 3dc26be0    	ldr	q0, [sp, #0x9a0]
100008a50: fd00e500    	str	d0, [x8, #0x1c8]
100008a54: 3d807504    	str	q4, [x8, #0x1d0]
100008a58: 3dc267e0    	ldr	q0, [sp, #0x990]
100008a5c: 6d1e010a    	stp	d10, d0, [x8, #0x1e0]
100008a60: 3dc16fe4    	ldr	q4, [sp, #0x5b0]
100008a64: 3dc263e0    	ldr	q0, [sp, #0x980]
100008a68: 6d1f0104    	stp	d4, d0, [x8, #0x1f0]
100008a6c: fd010118    	str	d24, [x8, #0x200]
100008a70: fd410fe0    	ldr	d0, [sp, #0x218]
100008a74: fd010500    	str	d0, [x8, #0x208]
100008a78: 3dc16be0    	ldr	q0, [sp, #0x5a0]
100008a7c: fd010900    	str	d0, [x8, #0x210]
100008a80: 3dc25fe0    	ldr	q0, [sp, #0x970]
100008a84: fd010d00    	str	d0, [x8, #0x218]
100008a88: 3dc167e0    	ldr	q0, [sp, #0x590]
100008a8c: fd011100    	str	d0, [x8, #0x220]
100008a90: 3dc25be0    	ldr	q0, [sp, #0x960]
100008a94: fd011500    	str	d0, [x8, #0x228]
100008a98: 3d808d05    	str	q5, [x8, #0x230]
100008a9c: 3dc12fe0    	ldr	q0, [sp, #0x4b0]
100008aa0: fd012100    	str	d0, [x8, #0x240]
100008aa4: 3dc257e0    	ldr	q0, [sp, #0x950]
100008aa8: fd012500    	str	d0, [x8, #0x248]
100008aac: 3dc163e0    	ldr	q0, [sp, #0x580]
100008ab0: fd012900    	str	d0, [x8, #0x250]
100008ab4: 3dc253e0    	ldr	q0, [sp, #0x940]
100008ab8: fd012d00    	str	d0, [x8, #0x258]
100008abc: 3dc15fe0    	ldr	q0, [sp, #0x570]
100008ac0: fd013100    	str	d0, [x8, #0x260]
100008ac4: 3dc24fe0    	ldr	q0, [sp, #0x930]
100008ac8: fd013500    	str	d0, [x8, #0x268]
100008acc: 3dc187e0    	ldr	q0, [sp, #0x610]
100008ad0: fd013900    	str	d0, [x8, #0x270]
100008ad4: 3dc24be0    	ldr	q0, [sp, #0x920]
100008ad8: fd013d00    	str	d0, [x8, #0x278]
100008adc: 3dc15be0    	ldr	q0, [sp, #0x560]
100008ae0: fd014100    	str	d0, [x8, #0x280]
100008ae4: 3dc247e0    	ldr	q0, [sp, #0x910]
100008ae8: fd014500    	str	d0, [x8, #0x288]
100008aec: 3dc0f7e0    	ldr	q0, [sp, #0x3d0]
100008af0: 3d80a500    	str	q0, [x8, #0x290]
100008af4: 3dc12be0    	ldr	q0, [sp, #0x4a0]
100008af8: fd015100    	str	d0, [x8, #0x2a0]
100008afc: 3dc223e0    	ldr	q0, [sp, #0x880]
100008b00: fd015500    	str	d0, [x8, #0x2a8]
100008b04: 3dc127e0    	ldr	q0, [sp, #0x490]
100008b08: fd015900    	str	d0, [x8, #0x2b0]
100008b0c: 3dc21fe0    	ldr	q0, [sp, #0x870]
100008b10: fd015d00    	str	d0, [x8, #0x2b8]
100008b14: 3dc157e0    	ldr	q0, [sp, #0x550]
100008b18: fd016100    	str	d0, [x8, #0x2c0]
100008b1c: 3dc243e0    	ldr	q0, [sp, #0x900]
100008b20: fd016500    	str	d0, [x8, #0x2c8]
100008b24: fd01691a    	str	d26, [x8, #0x2d0]
100008b28: fd4113e0    	ldr	d0, [sp, #0x220]
100008b2c: fd016d00    	str	d0, [x8, #0x2d8]
100008b30: 3dc153e0    	ldr	q0, [sp, #0x540]
100008b34: fd017100    	str	d0, [x8, #0x2e0]
100008b38: 3dc23fe0    	ldr	q0, [sp, #0x8f0]
100008b3c: fd017500    	str	d0, [x8, #0x2e8]
100008b40: 3dc0efe0    	ldr	q0, [sp, #0x3b0]
100008b44: 3d80bd00    	str	q0, [x8, #0x2f0]
100008b48: 3dc113e0    	ldr	q0, [sp, #0x440]
100008b4c: fd018100    	str	d0, [x8, #0x300]
100008b50: 3dc233e0    	ldr	q0, [sp, #0x8c0]
100008b54: fd018500    	str	d0, [x8, #0x308]
100008b58: 3dc10fe0    	ldr	q0, [sp, #0x430]
100008b5c: fd018900    	str	d0, [x8, #0x310]
100008b60: 3dc21be0    	ldr	q0, [sp, #0x860]
100008b64: fd018d00    	str	d0, [x8, #0x318]
100008b68: 3dc123e0    	ldr	q0, [sp, #0x480]
100008b6c: fd019100    	str	d0, [x8, #0x320]
100008b70: 3dc22fe0    	ldr	q0, [sp, #0x8b0]
100008b74: fd019500    	str	d0, [x8, #0x328]
100008b78: 3dc14fe0    	ldr	q0, [sp, #0x530]
100008b7c: fd019900    	str	d0, [x8, #0x330]
100008b80: 3dc23be0    	ldr	q0, [sp, #0x8e0]
100008b84: fd019d00    	str	d0, [x8, #0x338]
100008b88: 3dc17be0    	ldr	q0, [sp, #0x5e0]
100008b8c: fd01a100    	str	d0, [x8, #0x340]
100008b90: 3dc237e0    	ldr	q0, [sp, #0x8d0]
100008b94: fd01a500    	str	d0, [x8, #0x348]
100008b98: 3dc0dfe0    	ldr	q0, [sp, #0x370]
100008b9c: 3d80d500    	str	q0, [x8, #0x350]
100008ba0: 3dc10be0    	ldr	q0, [sp, #0x420]
100008ba4: fd01b100    	str	d0, [x8, #0x360]
100008ba8: 3dc217e0    	ldr	q0, [sp, #0x850]
100008bac: fd01b500    	str	d0, [x8, #0x368]
100008bb0: 3dc107e0    	ldr	q0, [sp, #0x410]
100008bb4: fd01b900    	str	d0, [x8, #0x370]
100008bb8: 3dc22be0    	ldr	q0, [sp, #0x8a0]
100008bbc: fd01bd00    	str	d0, [x8, #0x378]
100008bc0: 3dc11fe0    	ldr	q0, [sp, #0x470]
100008bc4: fd01c100    	str	d0, [x8, #0x380]
100008bc8: 3dc213e0    	ldr	q0, [sp, #0x840]
100008bcc: fd01c500    	str	d0, [x8, #0x388]
100008bd0: 3dc11be0    	ldr	q0, [sp, #0x460]
100008bd4: fd01c900    	str	d0, [x8, #0x390]
100008bd8: 3dc227e0    	ldr	q0, [sp, #0x890]
100008bdc: fd01cd00    	str	d0, [x8, #0x398]
100008be0: fd01d112    	str	d18, [x8, #0x3a0]
100008be4: fd4117e0    	ldr	d0, [sp, #0x228]
100008be8: fd01d500    	str	d0, [x8, #0x3a8]
100008bec: 3dc0ebe0    	ldr	q0, [sp, #0x3a0]
100008bf0: 3d80ed00    	str	q0, [x8, #0x3b0]
100008bf4: 3dc13fe0    	ldr	q0, [sp, #0x4f0]
100008bf8: fd01e100    	str	d0, [x8, #0x3c0]
100008bfc: fd417be0    	ldr	d0, [sp, #0x2f0]
100008c00: fd01e500    	str	d0, [x8, #0x3c8]
100008c04: 3dc13be0    	ldr	q0, [sp, #0x4e0]
100008c08: fd01e900    	str	d0, [x8, #0x3d0]
100008c0c: fd4183e0    	ldr	d0, [sp, #0x300]
100008c10: fd01ed00    	str	d0, [x8, #0x3d8]
100008c14: 3dc137e0    	ldr	q0, [sp, #0x4d0]
100008c18: fd01f100    	str	d0, [x8, #0x3e0]
100008c1c: fd418be0    	ldr	d0, [sp, #0x310]
100008c20: fd01f500    	str	d0, [x8, #0x3e8]
100008c24: 3dc133e0    	ldr	q0, [sp, #0x4c0]
100008c28: fd01f900    	str	d0, [x8, #0x3f0]
100008c2c: fd01fd0c    	str	d12, [x8, #0x3f8]
100008c30: fd020115    	str	d21, [x8, #0x400]
100008c34: 3dc0e7e0    	ldr	q0, [sp, #0x390]
100008c38: fd020500    	str	d0, [x8, #0x408]
100008c3c: 3dc0dbe0    	ldr	q0, [sp, #0x360]
100008c40: 3d810500    	str	q0, [x8, #0x410]
100008c44: 3dc147e0    	ldr	q0, [sp, #0x510]
100008c48: fd021100    	str	d0, [x8, #0x420]
100008c4c: fd02151f    	str	d31, [x8, #0x428]
100008c50: 3dc143e0    	ldr	q0, [sp, #0x500]
100008c54: fd021900    	str	d0, [x8, #0x430]
100008c58: fd021d1b    	str	d27, [x8, #0x438]
100008c5c: ad5997e0    	ldp	q0, q5, [sp, #0x330]
100008c60: fd022105    	str	d5, [x8, #0x440]
100008c64: fd022517    	str	d23, [x8, #0x448]
100008c68: fd022900    	str	d0, [x8, #0x450]
100008c6c: fd022d14    	str	d20, [x8, #0x458]
100008c70: 3dc0cbe0    	ldr	q0, [sp, #0x320]
100008c74: fd023100    	str	d0, [x8, #0x460]
100008c78: 3dc0d7e0    	ldr	q0, [sp, #0x350]
100008c7c: fd023500    	str	d0, [x8, #0x468]
100008c80: 3d811d19    	str	q25, [x8, #0x470]
100008c84: 914007ff    	add	sp, sp, #0x1, lsl #12   ; =0x1000
100008c88: 910903ff    	add	sp, sp, #0x240
100008c8c: a9457bfd    	ldp	x29, x30, [sp, #0x50]
100008c90: a9444ff4    	ldp	x20, x19, [sp, #0x40]
100008c94: 6d4323e9    	ldp	d9, d8, [sp, #0x30]
100008c98: 6d422beb    	ldp	d11, d10, [sp, #0x20]
100008c9c: 6d4133ed    	ldp	d13, d12, [sp, #0x10]
100008ca0: 6cc63bef    	ldp	d15, d14, [sp], #0x60
100008ca4: d65f03c0    	ret

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

0000000100008f10 <_bench_primitives.checksumMatrix>:
100008f10: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100008f14: 910003fd    	mov	x29, sp
100008f18: 900000a8    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100008f1c: 9106c108    	add	x8, x8, #0x1b0
100008f20: 2f00e400    	movi	d0, #0000000000000000
100008f24: 6d400901    	ldp	d1, d2, [x8]
100008f28: 1e602820    	fadd	d0, d1, d0
100008f2c: 1e622841    	fadd	d1, d2, d2
100008f30: 1e612800    	fadd	d0, d0, d1
100008f34: 1e611001    	fmov	d1, #3.00000000
100008f38: 6d410d02    	ldp	d2, d3, [x8, #0x10]
100008f3c: 1e610841    	fmul	d1, d2, d1
100008f40: 1e612800    	fadd	d0, d0, d1
100008f44: 1e621001    	fmov	d1, #4.00000000
100008f48: 1e610861    	fmul	d1, d3, d1
100008f4c: 1e612800    	fadd	d0, d0, d1
100008f50: 1e629001    	fmov	d1, #5.00000000
100008f54: 6d420d02    	ldp	d2, d3, [x8, #0x20]
100008f58: 1e610841    	fmul	d1, d2, d1
100008f5c: 1e612800    	fadd	d0, d0, d1
100008f60: 1e631001    	fmov	d1, #6.00000000
100008f64: 1e610861    	fmul	d1, d3, d1
100008f68: 1e612800    	fadd	d0, d0, d1
100008f6c: 1e639001    	fmov	d1, #7.00000000
100008f70: 6d430d02    	ldp	d2, d3, [x8, #0x30]
100008f74: 1e610841    	fmul	d1, d2, d1
100008f78: 1e612800    	fadd	d0, d0, d1
100008f7c: 1e641001    	fmov	d1, #8.00000000
100008f80: 1e610861    	fmul	d1, d3, d1
100008f84: 1e612800    	fadd	d0, d0, d1
100008f88: 1e645001    	fmov	d1, #9.00000000
100008f8c: 6d440d02    	ldp	d2, d3, [x8, #0x40]
100008f90: 1e610841    	fmul	d1, d2, d1
100008f94: 1e612800    	fadd	d0, d0, d1
100008f98: 1e649001    	fmov	d1, #10.00000000
100008f9c: 1e610861    	fmul	d1, d3, d1
100008fa0: 1e612800    	fadd	d0, d0, d1
100008fa4: 1e64d001    	fmov	d1, #11.00000000
100008fa8: 6d450d02    	ldp	d2, d3, [x8, #0x50]
100008fac: 1e610841    	fmul	d1, d2, d1
100008fb0: 1e612800    	fadd	d0, d0, d1
100008fb4: 1e651001    	fmov	d1, #12.00000000
100008fb8: 1e610861    	fmul	d1, d3, d1
100008fbc: 1e612800    	fadd	d0, d0, d1
100008fc0: 1e655001    	fmov	d1, #13.00000000
100008fc4: 6d460d02    	ldp	d2, d3, [x8, #0x60]
100008fc8: 1e610841    	fmul	d1, d2, d1
100008fcc: 1e612800    	fadd	d0, d0, d1
100008fd0: 1e659001    	fmov	d1, #14.00000000
100008fd4: 1e610861    	fmul	d1, d3, d1
100008fd8: 1e612800    	fadd	d0, d0, d1
100008fdc: 1e65d001    	fmov	d1, #15.00000000
100008fe0: 6d470d02    	ldp	d2, d3, [x8, #0x70]
100008fe4: 1e610841    	fmul	d1, d2, d1
100008fe8: 1e612800    	fadd	d0, d0, d1
100008fec: 1e661001    	fmov	d1, #16.00000000
100008ff0: 1e610861    	fmul	d1, d3, d1
100008ff4: 1e612800    	fadd	d0, d0, d1
100008ff8: 1e663001    	fmov	d1, #17.00000000
100008ffc: 6d480d02    	ldp	d2, d3, [x8, #0x80]
100009000: 1e610841    	fmul	d1, d2, d1
100009004: 1e612800    	fadd	d0, d0, d1
100009008: 1e665001    	fmov	d1, #18.00000000
10000900c: 1e610861    	fmul	d1, d3, d1
100009010: 1e612800    	fadd	d0, d0, d1
100009014: 1e667001    	fmov	d1, #19.00000000
100009018: 6d490d02    	ldp	d2, d3, [x8, #0x90]
10000901c: 1e610841    	fmul	d1, d2, d1
100009020: 1e612800    	fadd	d0, d0, d1
100009024: 1e669001    	fmov	d1, #20.00000000
100009028: 1e610861    	fmul	d1, d3, d1
10000902c: 1e612800    	fadd	d0, d0, d1
100009030: 1e66b001    	fmov	d1, #21.00000000
100009034: 6d4a0d02    	ldp	d2, d3, [x8, #0xa0]
100009038: 1e610841    	fmul	d1, d2, d1
10000903c: 1e612800    	fadd	d0, d0, d1
100009040: 1e66d001    	fmov	d1, #22.00000000
100009044: 1e610861    	fmul	d1, d3, d1
100009048: 1e612800    	fadd	d0, d0, d1
10000904c: 1e66f001    	fmov	d1, #23.00000000
100009050: 6d4b0d02    	ldp	d2, d3, [x8, #0xb0]
100009054: 1e610841    	fmul	d1, d2, d1
100009058: 1e612800    	fadd	d0, d0, d1
10000905c: 1e671001    	fmov	d1, #24.00000000
100009060: 1e610861    	fmul	d1, d3, d1
100009064: 1e612800    	fadd	d0, d0, d1
100009068: 1e673001    	fmov	d1, #25.00000000
10000906c: 6d4c0d02    	ldp	d2, d3, [x8, #0xc0]
100009070: 1e610841    	fmul	d1, d2, d1
100009074: 1e612800    	fadd	d0, d0, d1
100009078: 1e675001    	fmov	d1, #26.00000000
10000907c: 1e610861    	fmul	d1, d3, d1
100009080: 1e612800    	fadd	d0, d0, d1
100009084: 1e677001    	fmov	d1, #27.00000000
100009088: 6d4d0d02    	ldp	d2, d3, [x8, #0xd0]
10000908c: 1e610841    	fmul	d1, d2, d1
100009090: 1e612800    	fadd	d0, d0, d1
100009094: 1e679001    	fmov	d1, #28.00000000
100009098: 1e610861    	fmul	d1, d3, d1
10000909c: 1e612800    	fadd	d0, d0, d1
1000090a0: 1e67b001    	fmov	d1, #29.00000000
1000090a4: 6d4e0d02    	ldp	d2, d3, [x8, #0xe0]
1000090a8: 1e610841    	fmul	d1, d2, d1
1000090ac: 1e612800    	fadd	d0, d0, d1
1000090b0: 1e67d001    	fmov	d1, #30.00000000
1000090b4: 1e610861    	fmul	d1, d3, d1
1000090b8: 1e612800    	fadd	d0, d0, d1
1000090bc: 1e67f001    	fmov	d1, #31.00000000
1000090c0: 6d4f0d02    	ldp	d2, d3, [x8, #0xf0]
1000090c4: 1e610841    	fmul	d1, d2, d1
1000090c8: 1e612800    	fadd	d0, d0, d1
1000090cc: d2e80809    	mov	x9, #0x4040000000000000 ; =4629700416936869888
1000090d0: 9e670121    	fmov	d1, x9
1000090d4: 1e610861    	fmul	d1, d3, d1
1000090d8: 1e612800    	fadd	d0, d0, d1
1000090dc: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000090e0: f2e80809    	movk	x9, #0x4040, lsl #48
1000090e4: 9e670121    	fmov	d1, x9
1000090e8: 6d500d02    	ldp	d2, d3, [x8, #0x100]
1000090ec: 1e610841    	fmul	d1, d2, d1
1000090f0: 1e612800    	fadd	d0, d0, d1
1000090f4: d2e80829    	mov	x9, #0x4041000000000000 ; =4629981891913580544
1000090f8: 9e670121    	fmov	d1, x9
1000090fc: 1e610861    	fmul	d1, d3, d1
100009100: 1e612800    	fadd	d0, d0, d1
100009104: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009108: f2e80829    	movk	x9, #0x4041, lsl #48
10000910c: 9e670121    	fmov	d1, x9
100009110: 6d510d02    	ldp	d2, d3, [x8, #0x110]
100009114: 1e610841    	fmul	d1, d2, d1
100009118: 1e612800    	fadd	d0, d0, d1
10000911c: d2e80849    	mov	x9, #0x4042000000000000 ; =4630263366890291200
100009120: 9e670121    	fmov	d1, x9
100009124: 1e610861    	fmul	d1, d3, d1
100009128: 1e612800    	fadd	d0, d0, d1
10000912c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009130: f2e80849    	movk	x9, #0x4042, lsl #48
100009134: 9e670121    	fmov	d1, x9
100009138: 6d520d02    	ldp	d2, d3, [x8, #0x120]
10000913c: 1e610841    	fmul	d1, d2, d1
100009140: 1e612800    	fadd	d0, d0, d1
100009144: d2e80869    	mov	x9, #0x4043000000000000 ; =4630544841867001856
100009148: 9e670121    	fmov	d1, x9
10000914c: 1e610861    	fmul	d1, d3, d1
100009150: 1e612800    	fadd	d0, d0, d1
100009154: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009158: f2e80869    	movk	x9, #0x4043, lsl #48
10000915c: 9e670121    	fmov	d1, x9
100009160: 6d530d02    	ldp	d2, d3, [x8, #0x130]
100009164: 1e610841    	fmul	d1, d2, d1
100009168: 1e612800    	fadd	d0, d0, d1
10000916c: d2e80889    	mov	x9, #0x4044000000000000 ; =4630826316843712512
100009170: 9e670121    	fmov	d1, x9
100009174: 1e610861    	fmul	d1, d3, d1
100009178: 1e612800    	fadd	d0, d0, d1
10000917c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009180: f2e80889    	movk	x9, #0x4044, lsl #48
100009184: 9e670121    	fmov	d1, x9
100009188: 6d540d02    	ldp	d2, d3, [x8, #0x140]
10000918c: 1e610841    	fmul	d1, d2, d1
100009190: 1e612800    	fadd	d0, d0, d1
100009194: d2e808a9    	mov	x9, #0x4045000000000000 ; =4631107791820423168
100009198: 9e670121    	fmov	d1, x9
10000919c: 1e610861    	fmul	d1, d3, d1
1000091a0: 1e612800    	fadd	d0, d0, d1
1000091a4: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000091a8: f2e808a9    	movk	x9, #0x4045, lsl #48
1000091ac: 9e670121    	fmov	d1, x9
1000091b0: 6d550d02    	ldp	d2, d3, [x8, #0x150]
1000091b4: 1e610841    	fmul	d1, d2, d1
1000091b8: 1e612800    	fadd	d0, d0, d1
1000091bc: d2e808c9    	mov	x9, #0x4046000000000000 ; =4631389266797133824
1000091c0: 9e670121    	fmov	d1, x9
1000091c4: 1e610861    	fmul	d1, d3, d1
1000091c8: 1e612800    	fadd	d0, d0, d1
1000091cc: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000091d0: f2e808c9    	movk	x9, #0x4046, lsl #48
1000091d4: 9e670121    	fmov	d1, x9
1000091d8: 6d560d02    	ldp	d2, d3, [x8, #0x160]
1000091dc: 1e610841    	fmul	d1, d2, d1
1000091e0: 1e612800    	fadd	d0, d0, d1
1000091e4: d2e808e9    	mov	x9, #0x4047000000000000 ; =4631670741773844480
1000091e8: 9e670121    	fmov	d1, x9
1000091ec: 1e610861    	fmul	d1, d3, d1
1000091f0: 1e612800    	fadd	d0, d0, d1
1000091f4: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000091f8: f2e808e9    	movk	x9, #0x4047, lsl #48
1000091fc: 9e670121    	fmov	d1, x9
100009200: 6d570d02    	ldp	d2, d3, [x8, #0x170]
100009204: 1e610841    	fmul	d1, d2, d1
100009208: 1e612800    	fadd	d0, d0, d1
10000920c: d2e80909    	mov	x9, #0x4048000000000000 ; =4631952216750555136
100009210: 9e670121    	fmov	d1, x9
100009214: 1e610861    	fmul	d1, d3, d1
100009218: 1e612800    	fadd	d0, d0, d1
10000921c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009220: f2e80909    	movk	x9, #0x4048, lsl #48
100009224: 9e670121    	fmov	d1, x9
100009228: 6d580d02    	ldp	d2, d3, [x8, #0x180]
10000922c: 1e610841    	fmul	d1, d2, d1
100009230: 1e612800    	fadd	d0, d0, d1
100009234: d2e80929    	mov	x9, #0x4049000000000000 ; =4632233691727265792
100009238: 9e670121    	fmov	d1, x9
10000923c: 1e610861    	fmul	d1, d3, d1
100009240: 1e612800    	fadd	d0, d0, d1
100009244: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009248: f2e80929    	movk	x9, #0x4049, lsl #48
10000924c: 9e670121    	fmov	d1, x9
100009250: 6d590d02    	ldp	d2, d3, [x8, #0x190]
100009254: 1e610841    	fmul	d1, d2, d1
100009258: 1e612800    	fadd	d0, d0, d1
10000925c: d2e80949    	mov	x9, #0x404a000000000000 ; =4632515166703976448
100009260: 9e670121    	fmov	d1, x9
100009264: 1e610861    	fmul	d1, d3, d1
100009268: 1e612800    	fadd	d0, d0, d1
10000926c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009270: f2e80949    	movk	x9, #0x404a, lsl #48
100009274: 9e670121    	fmov	d1, x9
100009278: 6d5a0d02    	ldp	d2, d3, [x8, #0x1a0]
10000927c: 1e610841    	fmul	d1, d2, d1
100009280: 1e612800    	fadd	d0, d0, d1
100009284: d2e80969    	mov	x9, #0x404b000000000000 ; =4632796641680687104
100009288: 9e670121    	fmov	d1, x9
10000928c: 1e610861    	fmul	d1, d3, d1
100009290: 1e612800    	fadd	d0, d0, d1
100009294: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009298: f2e80969    	movk	x9, #0x404b, lsl #48
10000929c: 9e670121    	fmov	d1, x9
1000092a0: 6d5b0d02    	ldp	d2, d3, [x8, #0x1b0]
1000092a4: 1e610841    	fmul	d1, d2, d1
1000092a8: 1e612800    	fadd	d0, d0, d1
1000092ac: d2e80989    	mov	x9, #0x404c000000000000 ; =4633078116657397760
1000092b0: 9e670121    	fmov	d1, x9
1000092b4: 1e610861    	fmul	d1, d3, d1
1000092b8: 1e612800    	fadd	d0, d0, d1
1000092bc: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000092c0: f2e80989    	movk	x9, #0x404c, lsl #48
1000092c4: 9e670121    	fmov	d1, x9
1000092c8: 6d5c0d02    	ldp	d2, d3, [x8, #0x1c0]
1000092cc: 1e610841    	fmul	d1, d2, d1
1000092d0: 1e612800    	fadd	d0, d0, d1
1000092d4: d2e809a9    	mov	x9, #0x404d000000000000 ; =4633359591634108416
1000092d8: 9e670121    	fmov	d1, x9
1000092dc: 1e610861    	fmul	d1, d3, d1
1000092e0: 1e612800    	fadd	d0, d0, d1
1000092e4: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000092e8: f2e809a9    	movk	x9, #0x404d, lsl #48
1000092ec: 9e670121    	fmov	d1, x9
1000092f0: 6d5d0d02    	ldp	d2, d3, [x8, #0x1d0]
1000092f4: 1e610841    	fmul	d1, d2, d1
1000092f8: 1e612800    	fadd	d0, d0, d1
1000092fc: d2e809c9    	mov	x9, #0x404e000000000000 ; =4633641066610819072
100009300: 9e670121    	fmov	d1, x9
100009304: 1e610861    	fmul	d1, d3, d1
100009308: 1e612800    	fadd	d0, d0, d1
10000930c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009310: f2e809c9    	movk	x9, #0x404e, lsl #48
100009314: 9e670121    	fmov	d1, x9
100009318: 6d5e0d02    	ldp	d2, d3, [x8, #0x1e0]
10000931c: 1e610841    	fmul	d1, d2, d1
100009320: 1e612800    	fadd	d0, d0, d1
100009324: d2e809e9    	mov	x9, #0x404f000000000000 ; =4633922541587529728
100009328: 9e670121    	fmov	d1, x9
10000932c: 1e610861    	fmul	d1, d3, d1
100009330: 1e612800    	fadd	d0, d0, d1
100009334: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009338: f2e809e9    	movk	x9, #0x404f, lsl #48
10000933c: 9e670121    	fmov	d1, x9
100009340: 6d5f0d02    	ldp	d2, d3, [x8, #0x1f0]
100009344: 1e610841    	fmul	d1, d2, d1
100009348: 1e612800    	fadd	d0, d0, d1
10000934c: d2e80a09    	mov	x9, #0x4050000000000000 ; =4634204016564240384
100009350: 9e670121    	fmov	d1, x9
100009354: 1e610861    	fmul	d1, d3, d1
100009358: 1e612800    	fadd	d0, d0, d1
10000935c: fd410101    	ldr	d1, [x8, #0x200]
100009360: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
100009364: f2e80a09    	movk	x9, #0x4050, lsl #48
100009368: 9e670122    	fmov	d2, x9
10000936c: 1e620821    	fmul	d1, d1, d2
100009370: 1e612800    	fadd	d0, d0, d1
100009374: fd410501    	ldr	d1, [x8, #0x208]
100009378: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000937c: f2e80a09    	movk	x9, #0x4050, lsl #48
100009380: 9e670122    	fmov	d2, x9
100009384: 1e620821    	fmul	d1, d1, d2
100009388: 1e612800    	fadd	d0, d0, d1
10000938c: fd410901    	ldr	d1, [x8, #0x210]
100009390: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
100009394: f2e80a09    	movk	x9, #0x4050, lsl #48
100009398: 9e670122    	fmov	d2, x9
10000939c: 1e620821    	fmul	d1, d1, d2
1000093a0: 1e612800    	fadd	d0, d0, d1
1000093a4: fd410d01    	ldr	d1, [x8, #0x218]
1000093a8: d2e80a29    	mov	x9, #0x4051000000000000 ; =4634485491540951040
1000093ac: 9e670122    	fmov	d2, x9
1000093b0: 1e620821    	fmul	d1, d1, d2
1000093b4: 1e612800    	fadd	d0, d0, d1
1000093b8: fd411101    	ldr	d1, [x8, #0x220]
1000093bc: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
1000093c0: f2e80a29    	movk	x9, #0x4051, lsl #48
1000093c4: 9e670122    	fmov	d2, x9
1000093c8: 1e620821    	fmul	d1, d1, d2
1000093cc: 1e612800    	fadd	d0, d0, d1
1000093d0: fd411501    	ldr	d1, [x8, #0x228]
1000093d4: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000093d8: f2e80a29    	movk	x9, #0x4051, lsl #48
1000093dc: 9e670122    	fmov	d2, x9
1000093e0: 1e620821    	fmul	d1, d1, d2
1000093e4: 1e612800    	fadd	d0, d0, d1
1000093e8: fd411901    	ldr	d1, [x8, #0x230]
1000093ec: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
1000093f0: f2e80a29    	movk	x9, #0x4051, lsl #48
1000093f4: 9e670122    	fmov	d2, x9
1000093f8: 1e620821    	fmul	d1, d1, d2
1000093fc: 1e612800    	fadd	d0, d0, d1
100009400: fd411d01    	ldr	d1, [x8, #0x238]
100009404: d2e80a49    	mov	x9, #0x4052000000000000 ; =4634766966517661696
100009408: 9e670122    	fmov	d2, x9
10000940c: 1e620821    	fmul	d1, d1, d2
100009410: 1e612800    	fadd	d0, d0, d1
100009414: fd412101    	ldr	d1, [x8, #0x240]
100009418: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000941c: f2e80a49    	movk	x9, #0x4052, lsl #48
100009420: 9e670122    	fmov	d2, x9
100009424: 1e620821    	fmul	d1, d1, d2
100009428: 1e612800    	fadd	d0, d0, d1
10000942c: fd412501    	ldr	d1, [x8, #0x248]
100009430: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009434: f2e80a49    	movk	x9, #0x4052, lsl #48
100009438: 9e670122    	fmov	d2, x9
10000943c: 1e620821    	fmul	d1, d1, d2
100009440: 1e612800    	fadd	d0, d0, d1
100009444: fd412901    	ldr	d1, [x8, #0x250]
100009448: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000944c: f2e80a49    	movk	x9, #0x4052, lsl #48
100009450: 9e670122    	fmov	d2, x9
100009454: 1e620821    	fmul	d1, d1, d2
100009458: 1e612800    	fadd	d0, d0, d1
10000945c: fd412d01    	ldr	d1, [x8, #0x258]
100009460: d2e80a69    	mov	x9, #0x4053000000000000 ; =4635048441494372352
100009464: 9e670122    	fmov	d2, x9
100009468: 1e620821    	fmul	d1, d1, d2
10000946c: 1e612800    	fadd	d0, d0, d1
100009470: fd413101    	ldr	d1, [x8, #0x260]
100009474: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
100009478: f2e80a69    	movk	x9, #0x4053, lsl #48
10000947c: 9e670122    	fmov	d2, x9
100009480: 1e620821    	fmul	d1, d1, d2
100009484: 1e612800    	fadd	d0, d0, d1
100009488: fd413501    	ldr	d1, [x8, #0x268]
10000948c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009490: f2e80a69    	movk	x9, #0x4053, lsl #48
100009494: 9e670122    	fmov	d2, x9
100009498: 1e620821    	fmul	d1, d1, d2
10000949c: 1e612800    	fadd	d0, d0, d1
1000094a0: fd413901    	ldr	d1, [x8, #0x270]
1000094a4: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
1000094a8: f2e80a69    	movk	x9, #0x4053, lsl #48
1000094ac: 9e670122    	fmov	d2, x9
1000094b0: 1e620821    	fmul	d1, d1, d2
1000094b4: 1e612800    	fadd	d0, d0, d1
1000094b8: fd413d01    	ldr	d1, [x8, #0x278]
1000094bc: d2e80a89    	mov	x9, #0x4054000000000000 ; =4635329916471083008
1000094c0: 9e670122    	fmov	d2, x9
1000094c4: 1e620821    	fmul	d1, d1, d2
1000094c8: 1e612800    	fadd	d0, d0, d1
1000094cc: fd414101    	ldr	d1, [x8, #0x280]
1000094d0: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
1000094d4: f2e80a89    	movk	x9, #0x4054, lsl #48
1000094d8: 9e670122    	fmov	d2, x9
1000094dc: 1e620821    	fmul	d1, d1, d2
1000094e0: 1e612800    	fadd	d0, d0, d1
1000094e4: fd414501    	ldr	d1, [x8, #0x288]
1000094e8: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000094ec: f2e80a89    	movk	x9, #0x4054, lsl #48
1000094f0: 9e670122    	fmov	d2, x9
1000094f4: 1e620821    	fmul	d1, d1, d2
1000094f8: 1e612800    	fadd	d0, d0, d1
1000094fc: fd414901    	ldr	d1, [x8, #0x290]
100009500: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
100009504: f2e80a89    	movk	x9, #0x4054, lsl #48
100009508: 9e670122    	fmov	d2, x9
10000950c: 1e620821    	fmul	d1, d1, d2
100009510: 1e612800    	fadd	d0, d0, d1
100009514: fd414d01    	ldr	d1, [x8, #0x298]
100009518: d2e80aa9    	mov	x9, #0x4055000000000000 ; =4635611391447793664
10000951c: 9e670122    	fmov	d2, x9
100009520: 1e620821    	fmul	d1, d1, d2
100009524: 1e612800    	fadd	d0, d0, d1
100009528: fd415101    	ldr	d1, [x8, #0x2a0]
10000952c: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
100009530: f2e80aa9    	movk	x9, #0x4055, lsl #48
100009534: 9e670122    	fmov	d2, x9
100009538: 1e620821    	fmul	d1, d1, d2
10000953c: 1e612800    	fadd	d0, d0, d1
100009540: fd415501    	ldr	d1, [x8, #0x2a8]
100009544: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009548: f2e80aa9    	movk	x9, #0x4055, lsl #48
10000954c: 9e670122    	fmov	d2, x9
100009550: 1e620821    	fmul	d1, d1, d2
100009554: 1e612800    	fadd	d0, d0, d1
100009558: fd415901    	ldr	d1, [x8, #0x2b0]
10000955c: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
100009560: f2e80aa9    	movk	x9, #0x4055, lsl #48
100009564: 9e670122    	fmov	d2, x9
100009568: 1e620821    	fmul	d1, d1, d2
10000956c: 1e612800    	fadd	d0, d0, d1
100009570: fd415d01    	ldr	d1, [x8, #0x2b8]
100009574: d2e80ac9    	mov	x9, #0x4056000000000000 ; =4635892866424504320
100009578: 9e670122    	fmov	d2, x9
10000957c: 1e620821    	fmul	d1, d1, d2
100009580: 1e612800    	fadd	d0, d0, d1
100009584: fd416101    	ldr	d1, [x8, #0x2c0]
100009588: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000958c: f2e80ac9    	movk	x9, #0x4056, lsl #48
100009590: 9e670122    	fmov	d2, x9
100009594: 1e620821    	fmul	d1, d1, d2
100009598: 1e612800    	fadd	d0, d0, d1
10000959c: fd416501    	ldr	d1, [x8, #0x2c8]
1000095a0: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000095a4: f2e80ac9    	movk	x9, #0x4056, lsl #48
1000095a8: 9e670122    	fmov	d2, x9
1000095ac: 1e620821    	fmul	d1, d1, d2
1000095b0: 1e612800    	fadd	d0, d0, d1
1000095b4: fd416901    	ldr	d1, [x8, #0x2d0]
1000095b8: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
1000095bc: f2e80ac9    	movk	x9, #0x4056, lsl #48
1000095c0: 9e670122    	fmov	d2, x9
1000095c4: 1e620821    	fmul	d1, d1, d2
1000095c8: 1e612800    	fadd	d0, d0, d1
1000095cc: fd416d01    	ldr	d1, [x8, #0x2d8]
1000095d0: d2e80ae9    	mov	x9, #0x4057000000000000 ; =4636174341401214976
1000095d4: 9e670122    	fmov	d2, x9
1000095d8: 1e620821    	fmul	d1, d1, d2
1000095dc: 1e612800    	fadd	d0, d0, d1
1000095e0: fd417101    	ldr	d1, [x8, #0x2e0]
1000095e4: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
1000095e8: f2e80ae9    	movk	x9, #0x4057, lsl #48
1000095ec: 9e670122    	fmov	d2, x9
1000095f0: 1e620821    	fmul	d1, d1, d2
1000095f4: 1e612800    	fadd	d0, d0, d1
1000095f8: fd417501    	ldr	d1, [x8, #0x2e8]
1000095fc: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009600: f2e80ae9    	movk	x9, #0x4057, lsl #48
100009604: 9e670122    	fmov	d2, x9
100009608: 1e620821    	fmul	d1, d1, d2
10000960c: 1e612800    	fadd	d0, d0, d1
100009610: fd417901    	ldr	d1, [x8, #0x2f0]
100009614: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
100009618: f2e80ae9    	movk	x9, #0x4057, lsl #48
10000961c: 9e670122    	fmov	d2, x9
100009620: 1e620821    	fmul	d1, d1, d2
100009624: 1e612800    	fadd	d0, d0, d1
100009628: fd417d01    	ldr	d1, [x8, #0x2f8]
10000962c: d2e80b09    	mov	x9, #0x4058000000000000 ; =4636455816377925632
100009630: 9e670122    	fmov	d2, x9
100009634: 1e620821    	fmul	d1, d1, d2
100009638: 1e612800    	fadd	d0, d0, d1
10000963c: fd418101    	ldr	d1, [x8, #0x300]
100009640: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
100009644: f2e80b09    	movk	x9, #0x4058, lsl #48
100009648: 9e670122    	fmov	d2, x9
10000964c: 1e620821    	fmul	d1, d1, d2
100009650: 1e612800    	fadd	d0, d0, d1
100009654: fd418501    	ldr	d1, [x8, #0x308]
100009658: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000965c: f2e80b09    	movk	x9, #0x4058, lsl #48
100009660: 9e670122    	fmov	d2, x9
100009664: 1e620821    	fmul	d1, d1, d2
100009668: 1e612800    	fadd	d0, d0, d1
10000966c: fd418901    	ldr	d1, [x8, #0x310]
100009670: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
100009674: f2e80b09    	movk	x9, #0x4058, lsl #48
100009678: 9e670122    	fmov	d2, x9
10000967c: 1e620821    	fmul	d1, d1, d2
100009680: 1e612800    	fadd	d0, d0, d1
100009684: fd418d01    	ldr	d1, [x8, #0x318]
100009688: d2e80b29    	mov	x9, #0x4059000000000000 ; =4636737291354636288
10000968c: 9e670122    	fmov	d2, x9
100009690: 1e620821    	fmul	d1, d1, d2
100009694: 1e612800    	fadd	d0, d0, d1
100009698: fd419101    	ldr	d1, [x8, #0x320]
10000969c: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
1000096a0: f2e80b29    	movk	x9, #0x4059, lsl #48
1000096a4: 9e670122    	fmov	d2, x9
1000096a8: 1e620821    	fmul	d1, d1, d2
1000096ac: 1e612800    	fadd	d0, d0, d1
1000096b0: fd419501    	ldr	d1, [x8, #0x328]
1000096b4: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000096b8: f2e80b29    	movk	x9, #0x4059, lsl #48
1000096bc: 9e670122    	fmov	d2, x9
1000096c0: 1e620821    	fmul	d1, d1, d2
1000096c4: 1e612800    	fadd	d0, d0, d1
1000096c8: fd419901    	ldr	d1, [x8, #0x330]
1000096cc: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
1000096d0: f2e80b29    	movk	x9, #0x4059, lsl #48
1000096d4: 9e670122    	fmov	d2, x9
1000096d8: 1e620821    	fmul	d1, d1, d2
1000096dc: 1e612800    	fadd	d0, d0, d1
1000096e0: fd419d01    	ldr	d1, [x8, #0x338]
1000096e4: d2e80b49    	mov	x9, #0x405a000000000000 ; =4637018766331346944
1000096e8: 9e670122    	fmov	d2, x9
1000096ec: 1e620821    	fmul	d1, d1, d2
1000096f0: 1e612800    	fadd	d0, d0, d1
1000096f4: fd41a101    	ldr	d1, [x8, #0x340]
1000096f8: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
1000096fc: f2e80b49    	movk	x9, #0x405a, lsl #48
100009700: 9e670122    	fmov	d2, x9
100009704: 1e620821    	fmul	d1, d1, d2
100009708: 1e612800    	fadd	d0, d0, d1
10000970c: fd41a501    	ldr	d1, [x8, #0x348]
100009710: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009714: f2e80b49    	movk	x9, #0x405a, lsl #48
100009718: 9e670122    	fmov	d2, x9
10000971c: 1e620821    	fmul	d1, d1, d2
100009720: 1e612800    	fadd	d0, d0, d1
100009724: fd41a901    	ldr	d1, [x8, #0x350]
100009728: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000972c: f2e80b49    	movk	x9, #0x405a, lsl #48
100009730: 9e670122    	fmov	d2, x9
100009734: 1e620821    	fmul	d1, d1, d2
100009738: 1e612800    	fadd	d0, d0, d1
10000973c: fd41ad01    	ldr	d1, [x8, #0x358]
100009740: d2e80b69    	mov	x9, #0x405b000000000000 ; =4637300241308057600
100009744: 9e670122    	fmov	d2, x9
100009748: 1e620821    	fmul	d1, d1, d2
10000974c: 1e612800    	fadd	d0, d0, d1
100009750: fd41b101    	ldr	d1, [x8, #0x360]
100009754: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
100009758: f2e80b69    	movk	x9, #0x405b, lsl #48
10000975c: 9e670122    	fmov	d2, x9
100009760: 1e620821    	fmul	d1, d1, d2
100009764: 1e612800    	fadd	d0, d0, d1
100009768: fd41b501    	ldr	d1, [x8, #0x368]
10000976c: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009770: f2e80b69    	movk	x9, #0x405b, lsl #48
100009774: 9e670122    	fmov	d2, x9
100009778: 1e620821    	fmul	d1, d1, d2
10000977c: 1e612800    	fadd	d0, d0, d1
100009780: fd41b901    	ldr	d1, [x8, #0x370]
100009784: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
100009788: f2e80b69    	movk	x9, #0x405b, lsl #48
10000978c: 9e670122    	fmov	d2, x9
100009790: 1e620821    	fmul	d1, d1, d2
100009794: 1e612800    	fadd	d0, d0, d1
100009798: fd41bd01    	ldr	d1, [x8, #0x378]
10000979c: d2e80b89    	mov	x9, #0x405c000000000000 ; =4637581716284768256
1000097a0: 9e670122    	fmov	d2, x9
1000097a4: 1e620821    	fmul	d1, d1, d2
1000097a8: 1e612800    	fadd	d0, d0, d1
1000097ac: fd41c101    	ldr	d1, [x8, #0x380]
1000097b0: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
1000097b4: f2e80b89    	movk	x9, #0x405c, lsl #48
1000097b8: 9e670122    	fmov	d2, x9
1000097bc: 1e620821    	fmul	d1, d1, d2
1000097c0: 1e612800    	fadd	d0, d0, d1
1000097c4: fd41c501    	ldr	d1, [x8, #0x388]
1000097c8: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000097cc: f2e80b89    	movk	x9, #0x405c, lsl #48
1000097d0: 9e670122    	fmov	d2, x9
1000097d4: 1e620821    	fmul	d1, d1, d2
1000097d8: 1e612800    	fadd	d0, d0, d1
1000097dc: fd41c901    	ldr	d1, [x8, #0x390]
1000097e0: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
1000097e4: f2e80b89    	movk	x9, #0x405c, lsl #48
1000097e8: 9e670122    	fmov	d2, x9
1000097ec: 1e620821    	fmul	d1, d1, d2
1000097f0: 1e612800    	fadd	d0, d0, d1
1000097f4: fd41cd01    	ldr	d1, [x8, #0x398]
1000097f8: d2e80ba9    	mov	x9, #0x405d000000000000 ; =4637863191261478912
1000097fc: 9e670122    	fmov	d2, x9
100009800: 1e620821    	fmul	d1, d1, d2
100009804: 1e612800    	fadd	d0, d0, d1
100009808: fd41d101    	ldr	d1, [x8, #0x3a0]
10000980c: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
100009810: f2e80ba9    	movk	x9, #0x405d, lsl #48
100009814: 9e670122    	fmov	d2, x9
100009818: 1e620821    	fmul	d1, d1, d2
10000981c: 1e612800    	fadd	d0, d0, d1
100009820: fd41d501    	ldr	d1, [x8, #0x3a8]
100009824: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009828: f2e80ba9    	movk	x9, #0x405d, lsl #48
10000982c: 9e670122    	fmov	d2, x9
100009830: 1e620821    	fmul	d1, d1, d2
100009834: 1e612800    	fadd	d0, d0, d1
100009838: fd41d901    	ldr	d1, [x8, #0x3b0]
10000983c: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
100009840: f2e80ba9    	movk	x9, #0x405d, lsl #48
100009844: 9e670122    	fmov	d2, x9
100009848: 1e620821    	fmul	d1, d1, d2
10000984c: 1e612800    	fadd	d0, d0, d1
100009850: fd41dd01    	ldr	d1, [x8, #0x3b8]
100009854: d2e80bc9    	mov	x9, #0x405e000000000000 ; =4638144666238189568
100009858: 9e670122    	fmov	d2, x9
10000985c: 1e620821    	fmul	d1, d1, d2
100009860: 1e612800    	fadd	d0, d0, d1
100009864: fd41e101    	ldr	d1, [x8, #0x3c0]
100009868: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000986c: f2e80bc9    	movk	x9, #0x405e, lsl #48
100009870: 9e670122    	fmov	d2, x9
100009874: 1e620821    	fmul	d1, d1, d2
100009878: 1e612800    	fadd	d0, d0, d1
10000987c: fd41e501    	ldr	d1, [x8, #0x3c8]
100009880: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
100009884: f2e80bc9    	movk	x9, #0x405e, lsl #48
100009888: 9e670122    	fmov	d2, x9
10000988c: 1e620821    	fmul	d1, d1, d2
100009890: 1e612800    	fadd	d0, d0, d1
100009894: fd41e901    	ldr	d1, [x8, #0x3d0]
100009898: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
10000989c: f2e80bc9    	movk	x9, #0x405e, lsl #48
1000098a0: 9e670122    	fmov	d2, x9
1000098a4: 1e620821    	fmul	d1, d1, d2
1000098a8: 1e612800    	fadd	d0, d0, d1
1000098ac: fd41ed01    	ldr	d1, [x8, #0x3d8]
1000098b0: d2e80be9    	mov	x9, #0x405f000000000000 ; =4638426141214900224
1000098b4: 9e670122    	fmov	d2, x9
1000098b8: 1e620821    	fmul	d1, d1, d2
1000098bc: 1e612800    	fadd	d0, d0, d1
1000098c0: fd41f101    	ldr	d1, [x8, #0x3e0]
1000098c4: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
1000098c8: f2e80be9    	movk	x9, #0x405f, lsl #48
1000098cc: 9e670122    	fmov	d2, x9
1000098d0: 1e620821    	fmul	d1, d1, d2
1000098d4: 1e612800    	fadd	d0, d0, d1
1000098d8: fd41f501    	ldr	d1, [x8, #0x3e8]
1000098dc: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
1000098e0: f2e80be9    	movk	x9, #0x405f, lsl #48
1000098e4: 9e670122    	fmov	d2, x9
1000098e8: 1e620821    	fmul	d1, d1, d2
1000098ec: 1e612800    	fadd	d0, d0, d1
1000098f0: fd41f901    	ldr	d1, [x8, #0x3f0]
1000098f4: d2d80009    	mov	x9, #0xc00000000000     ; =211106232532992
1000098f8: f2e80be9    	movk	x9, #0x405f, lsl #48
1000098fc: 9e670122    	fmov	d2, x9
100009900: 1e620821    	fmul	d1, d1, d2
100009904: 1e612800    	fadd	d0, d0, d1
100009908: fd41fd01    	ldr	d1, [x8, #0x3f8]
10000990c: d2e80c09    	mov	x9, #0x4060000000000000 ; =4638707616191610880
100009910: 9e670122    	fmov	d2, x9
100009914: 1e620821    	fmul	d1, d1, d2
100009918: 1e612800    	fadd	d0, d0, d1
10000991c: fd420101    	ldr	d1, [x8, #0x400]
100009920: d2c40009    	mov	x9, #0x200000000000     ; =35184372088832
100009924: f2e80c09    	movk	x9, #0x4060, lsl #48
100009928: 9e670122    	fmov	d2, x9
10000992c: 1e620821    	fmul	d1, d1, d2
100009930: 1e612800    	fadd	d0, d0, d1
100009934: fd420501    	ldr	d1, [x8, #0x408]
100009938: d2c80009    	mov	x9, #0x400000000000     ; =70368744177664
10000993c: f2e80c09    	movk	x9, #0x4060, lsl #48
100009940: 9e670122    	fmov	d2, x9
100009944: 1e620821    	fmul	d1, d1, d2
100009948: 1e612800    	fadd	d0, d0, d1
10000994c: fd420901    	ldr	d1, [x8, #0x410]
100009950: d2cc0009    	mov	x9, #0x600000000000     ; =105553116266496
100009954: f2e80c09    	movk	x9, #0x4060, lsl #48
100009958: 9e670122    	fmov	d2, x9
10000995c: 1e620821    	fmul	d1, d1, d2
100009960: 1e612800    	fadd	d0, d0, d1
100009964: fd420d01    	ldr	d1, [x8, #0x418]
100009968: d2d00009    	mov	x9, #0x800000000000     ; =140737488355328
10000996c: f2e80c09    	movk	x9, #0x4060, lsl #48
100009970: 9e670122    	fmov	d2, x9
100009974: 1e620821    	fmul	d1, d1, d2
100009978: 1e612800    	fadd	d0, d0, d1
10000997c: 3dc10901    	ldr	q1, [x8, #0x420]
100009980: f0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100009984: 3dc16122    	ldr	q2, [x9, #0x580]
100009988: 6e62dc21    	fmul.2d	v1, v1, v2
10000998c: 1e612800    	fadd	d0, d0, d1
100009990: 5e180421    	mov	d1, v1[1]
100009994: 1e612800    	fadd	d0, d0, d1
100009998: 3dc10d01    	ldr	q1, [x8, #0x430]
10000999c: f0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
1000099a0: 3dc16522    	ldr	q2, [x9, #0x590]
1000099a4: 6e62dc21    	fmul.2d	v1, v1, v2
1000099a8: 1e612800    	fadd	d0, d0, d1
1000099ac: 5e180421    	mov	d1, v1[1]
1000099b0: 1e612800    	fadd	d0, d0, d1
1000099b4: 3dc11101    	ldr	q1, [x8, #0x440]
1000099b8: f0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
1000099bc: 3dc16922    	ldr	q2, [x9, #0x5a0]
1000099c0: 6e62dc21    	fmul.2d	v1, v1, v2
1000099c4: 1e612800    	fadd	d0, d0, d1
1000099c8: 5e180421    	mov	d1, v1[1]
1000099cc: 1e612800    	fadd	d0, d0, d1
1000099d0: 3dc11501    	ldr	q1, [x8, #0x450]
1000099d4: f0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
1000099d8: 3dc16d22    	ldr	q2, [x9, #0x5b0]
1000099dc: 6e62dc21    	fmul.2d	v1, v1, v2
1000099e0: 1e612800    	fadd	d0, d0, d1
1000099e4: 5e180421    	mov	d1, v1[1]
1000099e8: 1e612800    	fadd	d0, d0, d1
1000099ec: 3dc11901    	ldr	q1, [x8, #0x460]
1000099f0: f0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
1000099f4: 3dc17122    	ldr	q2, [x9, #0x5c0]
1000099f8: 6e62dc21    	fmul.2d	v1, v1, v2
1000099fc: 1e612800    	fadd	d0, d0, d1
100009a00: 5e180421    	mov	d1, v1[1]
100009a04: 1e612800    	fadd	d0, d0, d1
100009a08: 3dc11d01    	ldr	q1, [x8, #0x470]
100009a0c: f0000028    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
100009a10: 3dc17502    	ldr	q2, [x8, #0x5d0]
100009a14: 6e62dc21    	fmul.2d	v1, v1, v2
100009a18: 1e612800    	fadd	d0, d0, d1
100009a1c: 5e180421    	mov	d1, v1[1]
100009a20: 1e612800    	fadd	d0, d0, d1
100009a24: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100009a28: d65f03c0    	ret

0000000100009a2c <_bench_primitives.checksumPair>:
100009a2c: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100009a30: 910003fd    	mov	x29, sp
100009a34: f0000088    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100009a38: 9118e108    	add	x8, x8, #0x638
100009a3c: 6d400500    	ldp	d0, d1, [x8]
100009a40: 1e655002    	fmov	d2, #13.00000000
100009a44: 1e620821    	fmul	d1, d1, d2
100009a48: 1e612800    	fadd	d0, d0, d1
100009a4c: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100009a50: d65f03c0    	ret

0000000100009a54 <_Io.Writer.writeAll>:
100009a54: b4000761    	cbz	x1, 0x100009b40 <_Io.Writer.writeAll+0xec>
100009a58: d101c3ff    	sub	sp, sp, #0x70
100009a5c: a90267fa    	stp	x26, x25, [sp, #0x20]
100009a60: a9035ff8    	stp	x24, x23, [sp, #0x30]
100009a64: a90457f6    	stp	x22, x21, [sp, #0x40]
100009a68: a9054ff4    	stp	x20, x19, [sp, #0x50]
100009a6c: a9067bfd    	stp	x29, x30, [sp, #0x60]
100009a70: 910183fd    	add	x29, sp, #0x60
100009a74: aa0103f3    	mov	x19, x1
100009a78: aa0003f4    	mov	x20, x0
100009a7c: d2800017    	mov	x23, #0x0               ; =0
100009a80: f0000088    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100009a84: f940cd08    	ldr	x8, [x8, #0x198]
100009a88: f0000098    	adrp	x24, 0x10001c000 <dyld_stub_binder+0x10001c000>
100009a8c: f0000095    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
100009a90: 910602b5    	add	x21, x21, #0x180
100009a94: f0000099    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
100009a98: 91062339    	add	x25, x25, #0x188
100009a9c: 8b170281    	add	x1, x20, x23
100009aa0: cb170276    	sub	x22, x19, x23
100009aa4: 8b160109    	add	x9, x8, x22
100009aa8: f940cb0a    	ldr	x10, [x24, #0x190]
100009aac: eb0a013f    	cmp	x9, x10
100009ab0: 54000188    	b.hi	0x100009ae0 <_Io.Writer.writeAll+0x8c>
100009ab4: f9400329    	ldr	x9, [x25]
100009ab8: 8b080120    	add	x0, x9, x8
100009abc: aa1603e2    	mov	x2, x22
100009ac0: 940016be    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
100009ac4: f9400b28    	ldr	x8, [x25, #0x10]
100009ac8: 8b160108    	add	x8, x8, x22
100009acc: f9000b28    	str	x8, [x25, #0x10]
100009ad0: 8b1702d7    	add	x23, x22, x23
100009ad4: eb1302ff    	cmp	x23, x19
100009ad8: 54fffe23    	b.lo	0x100009a9c <_Io.Writer.writeAll+0x48>
100009adc: 14000011    	b	0x100009b20 <_Io.Writer.writeAll+0xcc>
100009ae0: f94002a8    	ldr	x8, [x21]
100009ae4: f9400109    	ldr	x9, [x8]
100009ae8: a9005be1    	stp	x1, x22, [sp]
100009aec: 910043e8    	add	x8, sp, #0x10
100009af0: 910003e1    	mov	x1, sp
100009af4: aa1503e0    	mov	x0, x21
100009af8: 52800022    	mov	w2, #0x1                ; =1
100009afc: 52800023    	mov	w3, #0x1                ; =1
100009b00: d63f0120    	blr	x9
100009b04: 794033e0    	ldrh	w0, [sp, #0x18]
100009b08: 350000e0    	cbnz	w0, 0x100009b24 <_Io.Writer.writeAll+0xd0>
100009b0c: f9400bf6    	ldr	x22, [sp, #0x10]
100009b10: f9400ea8    	ldr	x8, [x21, #0x18]
100009b14: 8b1702d7    	add	x23, x22, x23
100009b18: eb1302ff    	cmp	x23, x19
100009b1c: 54fffc03    	b.lo	0x100009a9c <_Io.Writer.writeAll+0x48>
100009b20: 52800000    	mov	w0, #0x0                ; =0
100009b24: a9467bfd    	ldp	x29, x30, [sp, #0x60]
100009b28: a9454ff4    	ldp	x20, x19, [sp, #0x50]
100009b2c: a94457f6    	ldp	x22, x21, [sp, #0x40]
100009b30: a9435ff8    	ldp	x24, x23, [sp, #0x30]
100009b34: a94267fa    	ldp	x26, x25, [sp, #0x20]
100009b38: 9101c3ff    	add	sp, sp, #0x70
100009b3c: d65f03c0    	ret
100009b40: 52800000    	mov	w0, #0x0                ; =0
100009b44: d65f03c0    	ret

0000000100009b48 <_bench_primitives.smulAddSemul3_12KnownTraces>:
100009b48: 6dba3bef    	stp	d15, d14, [sp, #-0x60]!
100009b4c: 6d0133ed    	stp	d13, d12, [sp, #0x10]
100009b50: 6d022beb    	stp	d11, d10, [sp, #0x20]
100009b54: 6d0323e9    	stp	d9, d8, [sp, #0x30]
100009b58: a9046ffc    	stp	x28, x27, [sp, #0x40]
100009b5c: a9057bfd    	stp	x29, x30, [sp, #0x50]
100009b60: 910143fd    	add	x29, sp, #0x50
100009b64: d12103ff    	sub	sp, sp, #0x840
100009b68: 1e610800    	fmul	d0, d0, d1
100009b6c: 1e60c000    	fabs	d0, d0
100009b70: d29d4228    	mov	x8, #0xea11             ; =59921
100009b74: f2b025a8    	movk	x8, #0x812d, lsl #16
100009b78: f2d2f328    	movk	x8, #0x9799, lsl #32
100009b7c: f2e7ae28    	movk	x8, #0x3d71, lsl #48
100009b80: 9e670101    	fmov	d1, x8
100009b84: f0000088    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
100009b88: 9119c108    	add	x8, x8, #0x670
100009b8c: 1e612000    	fcmp	d0, d1
100009b90: 54012d29    	b.ls	0x10000c134 <_bench_primitives.smulAddSemul3_12KnownTraces+0x25ec>
100009b94: 3dc2411d    	ldr	q29, [x8, #0x900]
100009b98: ad407d05    	ldp	q5, q31, [x8]
100009b9c: 4fc593a4    	fmul.2d	v4, v29, v5[0]
100009ba0: f0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100009ba4: 3dc17920    	ldr	q0, [x9, #0x5e0]
100009ba8: 3d81e3e0    	str	q0, [sp, #0x780]
100009bac: 6e60dca0    	fmul.2d	v0, v5, v0
100009bb0: 4e60d7a3    	fadd.2d	v3, v29, v0
100009bb4: 3d81a7fd    	str	q29, [sp, #0x690]
100009bb8: 3dc27110    	ldr	q16, [x8, #0x9c0]
100009bbc: 4fdf9207    	fmul.2d	v7, v16, v31[0]
100009bc0: 3dc2890c    	ldr	q12, [x8, #0xa20]
100009bc4: 4fdf9986    	fmul.2d	v6, v12, v31[1]
100009bc8: 3d812bec    	str	q12, [sp, #0x4a0]
100009bcc: 3dc2451a    	ldr	q26, [x8, #0x910]
100009bd0: 4fc59340    	fmul.2d	v0, v26, v5[0]
100009bd4: 3dc27518    	ldr	q24, [x8, #0x9d0]
100009bd8: 4fdf9301    	fmul.2d	v1, v24, v31[0]
100009bdc: 3dc28d08    	ldr	q8, [x8, #0xa30]
100009be0: 4fdf9902    	fmul.2d	v2, v8, v31[1]
100009be4: 3d81bfe8    	str	q8, [sp, #0x6f0]
100009be8: 3dc2a109    	ldr	q9, [x8, #0xa80]
100009bec: ad413d1c    	ldp	q28, q15, [x8, #0x20]
100009bf0: 4fdc9134    	fmul.2d	v20, v9, v28[0]
100009bf4: 3d815fe9    	str	q9, [sp, #0x570]
100009bf8: 3dc2b91e    	ldr	q30, [x8, #0xae0]
100009bfc: 4fdc9bd3    	fmul.2d	v19, v30, v28[1]
100009c00: 3d8123fe    	str	q30, [sp, #0x480]
100009c04: 3dc2a50b    	ldr	q11, [x8, #0xa90]
100009c08: 4fdc9172    	fmul.2d	v18, v11, v28[0]
100009c0c: 3d81a3eb    	str	q11, [sp, #0x680]
100009c10: 3dc2d111    	ldr	q17, [x8, #0xb40]
100009c14: 3d8117f1    	str	q17, [sp, #0x450]
100009c18: 4fcf9235    	fmul.2d	v21, v17, v15[0]
100009c1c: 3dc2e911    	ldr	q17, [x8, #0xba0]
100009c20: 3d81dbf1    	str	q17, [sp, #0x760]
100009c24: 4fcf9a36    	fmul.2d	v22, v17, v15[1]
100009c28: 3dc2591b    	ldr	q27, [x8, #0x960]
100009c2c: 4fc59b77    	fmul.2d	v23, v27, v5[1]
100009c30: 4e77d484    	fadd.2d	v4, v4, v23
100009c34: 4e67d484    	fadd.2d	v4, v4, v7
100009c38: 3dc30107    	ldr	q7, [x8, #0xc00]
100009c3c: 3d8177e7    	str	q7, [sp, #0x5d0]
100009c40: ad42450e    	ldp	q14, q17, [x8, #0x40]
100009c44: 3d81aff1    	str	q17, [sp, #0x6b0]
100009c48: 4fce90e7    	fmul.2d	v7, v7, v14[0]
100009c4c: 4e66d484    	fadd.2d	v4, v4, v6
100009c50: 4e74d484    	fadd.2d	v4, v4, v20
100009c54: 3dc31906    	ldr	q6, [x8, #0xc60]
100009c58: 3c9003a6    	stur	q6, [x29, #-0x100]
100009c5c: 4fce98c6    	fmul.2d	v6, v6, v14[1]
100009c60: 4e73d484    	fadd.2d	v4, v4, v19
100009c64: 4e75d484    	fadd.2d	v4, v4, v21
100009c68: 4e76d484    	fadd.2d	v4, v4, v22
100009c6c: 4e67d484    	fadd.2d	v4, v4, v7
100009c70: 4e66d484    	fadd.2d	v4, v4, v6
100009c74: 4e63d483    	fadd.2d	v3, v4, v3
100009c78: 3d8103e3    	str	q3, [sp, #0x400]
100009c7c: ad435d19    	ldp	q25, q23, [x8, #0x60]
100009c80: 4fd993a6    	fmul.2d	v6, v29, v25[0]
100009c84: 4fd99b67    	fmul.2d	v7, v27, v25[1]
100009c88: 4ebb1f7d    	mov.16b	v29, v27
100009c8c: 4e67d4c6    	fadd.2d	v6, v6, v7
100009c90: 3dc25d03    	ldr	q3, [x8, #0x970]
100009c94: 4fc59867    	fmul.2d	v7, v3, v5[1]
100009c98: 3d816fe3    	str	q3, [sp, #0x5b0]
100009c9c: 4e67d400    	fadd.2d	v0, v0, v7
100009ca0: 3dc2bd16    	ldr	q22, [x8, #0xaf0]
100009ca4: 4fdc9ac7    	fmul.2d	v7, v22, v28[1]
100009ca8: 3d81d3f6    	str	q22, [sp, #0x740]
100009cac: 4e61d400    	fadd.2d	v0, v0, v1
100009cb0: 4e62d400    	fadd.2d	v0, v0, v2
100009cb4: 3dc2d50a    	ldr	q10, [x8, #0xb50]
100009cb8: 4fcf9141    	fmul.2d	v1, v10, v15[0]
100009cbc: 3d8137ea    	str	q10, [sp, #0x4d0]
100009cc0: 4e72d400    	fadd.2d	v0, v0, v18
100009cc4: 4e67d400    	fadd.2d	v0, v0, v7
100009cc8: 3dc2ed1b    	ldr	q27, [x8, #0xbb0]
100009ccc: 4fcf9b62    	fmul.2d	v2, v27, v15[1]
100009cd0: 3d8163fb    	str	q27, [sp, #0x580]
100009cd4: 4e61d400    	fadd.2d	v0, v0, v1
100009cd8: 4e62d400    	fadd.2d	v0, v0, v2
100009cdc: 3dc30501    	ldr	q1, [x8, #0xc10]
100009ce0: 3c9603a1    	stur	q1, [x29, #-0xa0]
100009ce4: 4fce9021    	fmul.2d	v1, v1, v14[0]
100009ce8: 4e61d400    	fadd.2d	v0, v0, v1
100009cec: 3dc31d01    	ldr	q1, [x8, #0xc70]
100009cf0: 3d81d7e1    	str	q1, [sp, #0x750]
100009cf4: 4fce9821    	fmul.2d	v1, v1, v14[1]
100009cf8: 4e61d400    	fadd.2d	v0, v0, v1
100009cfc: f0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100009d00: 3dc17d21    	ldr	q1, [x9, #0x5f0]
100009d04: 3d815be1    	str	q1, [sp, #0x560]
100009d08: 6e61dfe1    	fmul.2d	v1, v31, v1
100009d0c: 3d811bfa    	str	q26, [sp, #0x460]
100009d10: 4e61d741    	fadd.2d	v1, v26, v1
100009d14: 4e61d400    	fadd.2d	v0, v0, v1
100009d18: 3d8057e0    	str	q0, [sp, #0x150]
100009d1c: 91272109    	add	x9, x8, #0x9c8
100009d20: 4d408530    	ld1.d	{ v16 }[1], [x9]
100009d24: 3d814ff0    	str	q16, [sp, #0x530]
100009d28: 4fd79200    	fmul.2d	v0, v16, v23[0]
100009d2c: 4e60d4c0    	fadd.2d	v0, v6, v0
100009d30: 4fd79981    	fmul.2d	v1, v12, v23[1]
100009d34: 4e61d400    	fadd.2d	v0, v0, v1
100009d38: 4fd99341    	fmul.2d	v1, v26, v25[0]
100009d3c: 4fd99862    	fmul.2d	v2, v3, v25[1]
100009d40: 4e62d421    	fadd.2d	v1, v1, v2
100009d44: 91276109    	add	x9, x8, #0x9d8
100009d48: 4d408538    	ld1.d	{ v24 }[1], [x9]
100009d4c: 3d8173f8    	str	q24, [sp, #0x5c0]
100009d50: 4fd79302    	fmul.2d	v2, v24, v23[0]
100009d54: 4e62d421    	fadd.2d	v1, v1, v2
100009d58: 4fd79902    	fmul.2d	v2, v8, v23[1]
100009d5c: 4e62d426    	fadd.2d	v6, v1, v2
100009d60: 3dc24912    	ldr	q18, [x8, #0x920]
100009d64: 4fc59241    	fmul.2d	v1, v18, v5[0]
100009d68: 3dc26113    	ldr	q19, [x8, #0x980]
100009d6c: 4fc59a62    	fmul.2d	v2, v19, v5[1]
100009d70: 3d817bf3    	str	q19, [sp, #0x5e0]
100009d74: 4e62d421    	fadd.2d	v1, v1, v2
100009d78: 3dc27904    	ldr	q4, [x8, #0x9e0]
100009d7c: 4fdf9082    	fmul.2d	v2, v4, v31[0]
100009d80: 4e62d421    	fadd.2d	v1, v1, v2
100009d84: 3dc29114    	ldr	q20, [x8, #0xa40]
100009d88: 4fdf9a82    	fmul.2d	v2, v20, v31[1]
100009d8c: 3d81bbf4    	str	q20, [sp, #0x6e0]
100009d90: 4e62d421    	fadd.2d	v1, v1, v2
100009d94: 3dc2a915    	ldr	q21, [x8, #0xaa0]
100009d98: 4fdc92a2    	fmul.2d	v2, v21, v28[0]
100009d9c: 3d813ff5    	str	q21, [sp, #0x4f0]
100009da0: 4e62d421    	fadd.2d	v1, v1, v2
100009da4: 3dc2c103    	ldr	q3, [x8, #0xb00]
100009da8: 4fdc9862    	fmul.2d	v2, v3, v28[1]
100009dac: 3d81cfe3    	str	q3, [sp, #0x730]
100009db0: 4e62d421    	fadd.2d	v1, v1, v2
100009db4: 3dc2d91a    	ldr	q26, [x8, #0xb60]
100009db8: 4fcf9342    	fmul.2d	v2, v26, v15[0]
100009dbc: 3d8193fa    	str	q26, [sp, #0x640]
100009dc0: 4e62d421    	fadd.2d	v1, v1, v2
100009dc4: 3dc2f108    	ldr	q8, [x8, #0xbc0]
100009dc8: 4fcf9902    	fmul.2d	v2, v8, v15[1]
100009dcc: 3d81b7e8    	str	q8, [sp, #0x6d0]
100009dd0: 4e62d421    	fadd.2d	v1, v1, v2
100009dd4: 3dc30902    	ldr	q2, [x8, #0xc20]
100009dd8: 3c9403a2    	stur	q2, [x29, #-0xc0]
100009ddc: 4fce9042    	fmul.2d	v2, v2, v14[0]
100009de0: 4e62d421    	fadd.2d	v1, v1, v2
100009de4: 3dc32102    	ldr	q2, [x8, #0xc80]
100009de8: 3c9a03a2    	stur	q2, [x29, #-0x60]
100009dec: 4fce9842    	fmul.2d	v2, v2, v14[1]
100009df0: 4e62d421    	fadd.2d	v1, v1, v2
100009df4: f0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100009df8: 3dc18122    	ldr	q2, [x9, #0x600]
100009dfc: 3d819be2    	str	q2, [sp, #0x660]
100009e00: 6e62df82    	fmul.2d	v2, v28, v2
100009e04: 4e62d642    	fadd.2d	v2, v18, v2
100009e08: 3d818bf2    	str	q18, [sp, #0x620]
100009e0c: 4e62d421    	fadd.2d	v1, v1, v2
100009e10: 3d8053e1    	str	q1, [sp, #0x140]
100009e14: ad444111    	ldp	q17, q16, [x8, #0x80]
100009e18: 4fd19127    	fmul.2d	v7, v9, v17[0]
100009e1c: 4e67d400    	fadd.2d	v0, v0, v7
100009e20: 4fd19bc7    	fmul.2d	v7, v30, v17[1]
100009e24: 4e67d400    	fadd.2d	v0, v0, v7
100009e28: 4fd19167    	fmul.2d	v7, v11, v17[0]
100009e2c: 4e67d4c6    	fadd.2d	v6, v6, v7
100009e30: 4fd19ac7    	fmul.2d	v7, v22, v17[1]
100009e34: 4e67d4c6    	fadd.2d	v6, v6, v7
100009e38: 4fd99247    	fmul.2d	v7, v18, v25[0]
100009e3c: 4fd99a72    	fmul.2d	v18, v19, v25[1]
100009e40: 4e72d4e7    	fadd.2d	v7, v7, v18
100009e44: 9127a109    	add	x9, x8, #0x9e8
100009e48: 4d408524    	ld1.d	{ v4 }[1], [x9]
100009e4c: 3d813be4    	str	q4, [sp, #0x4e0]
100009e50: 4fd79092    	fmul.2d	v18, v4, v23[0]
100009e54: 4e72d4e7    	fadd.2d	v7, v7, v18
100009e58: 4fd79a92    	fmul.2d	v18, v20, v23[1]
100009e5c: 4e72d4e7    	fadd.2d	v7, v7, v18
100009e60: 4fd192b2    	fmul.2d	v18, v21, v17[0]
100009e64: 4e72d4e7    	fadd.2d	v7, v7, v18
100009e68: 4fd19872    	fmul.2d	v18, v3, v17[1]
100009e6c: 4e72d4e7    	fadd.2d	v7, v7, v18
100009e70: 3dc24d15    	ldr	q21, [x8, #0x930]
100009e74: 4fc592b2    	fmul.2d	v18, v21, v5[0]
100009e78: 3dc26514    	ldr	q20, [x8, #0x990]
100009e7c: 4fc59a93    	fmul.2d	v19, v20, v5[1]
100009e80: 3d8127f4    	str	q20, [sp, #0x490]
100009e84: 4e73d652    	fadd.2d	v18, v18, v19
100009e88: 3dc27d1e    	ldr	q30, [x8, #0x9f0]
100009e8c: 4fdf93d3    	fmul.2d	v19, v30, v31[0]
100009e90: 4e73d652    	fadd.2d	v18, v18, v19
100009e94: 3dc29504    	ldr	q4, [x8, #0xa50]
100009e98: 4fdf9893    	fmul.2d	v19, v4, v31[1]
100009e9c: 3d818fe4    	str	q4, [sp, #0x630]
100009ea0: 4e73d652    	fadd.2d	v18, v18, v19
100009ea4: 3dc2ad03    	ldr	q3, [x8, #0xab0]
100009ea8: 4fdc9073    	fmul.2d	v19, v3, v28[0]
100009eac: 3d819fe3    	str	q3, [sp, #0x670]
100009eb0: 4e73d652    	fadd.2d	v18, v18, v19
100009eb4: 3dc2c502    	ldr	q2, [x8, #0xb10]
100009eb8: 4fdc9853    	fmul.2d	v19, v2, v28[1]
100009ebc: 3c9503a2    	stur	q2, [x29, #-0xb0]
100009ec0: 4e73d652    	fadd.2d	v18, v18, v19
100009ec4: 3dc2dd01    	ldr	q1, [x8, #0xb70]
100009ec8: 4fcf9033    	fmul.2d	v19, v1, v15[0]
100009ecc: 3d8157e1    	str	q1, [sp, #0x550]
100009ed0: 4e73d652    	fadd.2d	v18, v18, v19
100009ed4: 3dc2f516    	ldr	q22, [x8, #0xbd0]
100009ed8: 4fcf9ad3    	fmul.2d	v19, v22, v15[1]
100009edc: 3d8187f6    	str	q22, [sp, #0x610]
100009ee0: 4e73d652    	fadd.2d	v18, v18, v19
100009ee4: 3dc30d0d    	ldr	q13, [x8, #0xc30]
100009ee8: 4fce91b3    	fmul.2d	v19, v13, v14[0]
100009eec: 3d816bed    	str	q13, [sp, #0x5a0]
100009ef0: 4e73d652    	fadd.2d	v18, v18, v19
100009ef4: 3dc3250c    	ldr	q12, [x8, #0xc90]
100009ef8: 4fce9993    	fmul.2d	v19, v12, v14[1]
100009efc: 3c9103ac    	stur	q12, [x29, #-0xf0]
100009f00: 4e73d652    	fadd.2d	v18, v18, v19
100009f04: f0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
100009f08: 3dc1852b    	ldr	q11, [x9, #0x610]
100009f0c: 6e6bddf3    	fmul.2d	v19, v15, v11
100009f10: 3d8147eb    	str	q11, [sp, #0x510]
100009f14: 3d810bf5    	str	q21, [sp, #0x420]
100009f18: 4e73d6b3    	fadd.2d	v19, v21, v19
100009f1c: 4e73d652    	fadd.2d	v18, v18, v19
100009f20: 3d804ff2    	str	q18, [sp, #0x130]
100009f24: 3dc117f2    	ldr	q18, [sp, #0x450]
100009f28: 4fd09252    	fmul.2d	v18, v18, v16[0]
100009f2c: 4e72d400    	fadd.2d	v0, v0, v18
100009f30: 3dc1dbf2    	ldr	q18, [sp, #0x760]
100009f34: 4fd09a52    	fmul.2d	v18, v18, v16[1]
100009f38: 4e72d412    	fadd.2d	v18, v0, v18
100009f3c: 4fd09140    	fmul.2d	v0, v10, v16[0]
100009f40: 4e60d4c0    	fadd.2d	v0, v6, v0
100009f44: 4fd09b66    	fmul.2d	v6, v27, v16[1]
100009f48: 4e66d413    	fadd.2d	v19, v0, v6
100009f4c: 4fd09340    	fmul.2d	v0, v26, v16[0]
100009f50: 4e60d4e0    	fadd.2d	v0, v7, v0
100009f54: 4fd09906    	fmul.2d	v6, v8, v16[1]
100009f58: 4e66d41a    	fadd.2d	v26, v0, v6
100009f5c: 4fd992a0    	fmul.2d	v0, v21, v25[0]
100009f60: 4fd99a86    	fmul.2d	v6, v20, v25[1]
100009f64: 4e66d400    	fadd.2d	v0, v0, v6
100009f68: 9127e109    	add	x9, x8, #0x9f8
100009f6c: 4d40853e    	ld1.d	{ v30 }[1], [x9]
100009f70: 3d8143fe    	str	q30, [sp, #0x500]
100009f74: 4fd793c6    	fmul.2d	v6, v30, v23[0]
100009f78: 4e66d400    	fadd.2d	v0, v0, v6
100009f7c: 4fd79886    	fmul.2d	v6, v4, v23[1]
100009f80: 4e66d400    	fadd.2d	v0, v0, v6
100009f84: 4fd19066    	fmul.2d	v6, v3, v17[0]
100009f88: 4e66d400    	fadd.2d	v0, v0, v6
100009f8c: 4fd19846    	fmul.2d	v6, v2, v17[1]
100009f90: 4e66d400    	fadd.2d	v0, v0, v6
100009f94: 4fd09026    	fmul.2d	v6, v1, v16[0]
100009f98: 4e66d400    	fadd.2d	v0, v0, v6
100009f9c: 4fd09ac6    	fmul.2d	v6, v22, v16[1]
100009fa0: 4e66d41b    	fadd.2d	v27, v0, v6
100009fa4: 3dc25101    	ldr	q1, [x8, #0x940]
100009fa8: 4fc59020    	fmul.2d	v0, v1, v5[0]
100009fac: 3dc26903    	ldr	q3, [x8, #0x9a0]
100009fb0: 4fc59866    	fmul.2d	v6, v3, v5[1]
100009fb4: 4e66d400    	fadd.2d	v0, v0, v6
100009fb8: 3dc28102    	ldr	q2, [x8, #0xa00]
100009fbc: 4fdf9046    	fmul.2d	v6, v2, v31[0]
100009fc0: 4e66d400    	fadd.2d	v0, v0, v6
100009fc4: 3dc2990a    	ldr	q10, [x8, #0xa60]
100009fc8: 4fdf9946    	fmul.2d	v6, v10, v31[1]
100009fcc: 3d817fea    	str	q10, [sp, #0x5f0]
100009fd0: 4e66d400    	fadd.2d	v0, v0, v6
100009fd4: 3dc2b109    	ldr	q9, [x8, #0xac0]
100009fd8: 4fdc9126    	fmul.2d	v6, v9, v28[0]
100009fdc: 3d8197e9    	str	q9, [sp, #0x650]
100009fe0: 4e66d400    	fadd.2d	v0, v0, v6
100009fe4: 3dc2c916    	ldr	q22, [x8, #0xb20]
100009fe8: 4fdc9ac6    	fmul.2d	v6, v22, v28[1]
100009fec: 4e66d400    	fadd.2d	v0, v0, v6
100009ff0: 3dc2e118    	ldr	q24, [x8, #0xb80]
100009ff4: 4fcf9306    	fmul.2d	v6, v24, v15[0]
100009ff8: 3c9903b8    	stur	q24, [x29, #-0x70]
100009ffc: 4e66d400    	fadd.2d	v0, v0, v6
10000a000: 3dc2f915    	ldr	q21, [x8, #0xbe0]
10000a004: 4fcf9aa6    	fmul.2d	v6, v21, v15[1]
10000a008: ad3957b6    	stp	q22, q21, [x29, #-0xe0]
10000a00c: 4e66d400    	fadd.2d	v0, v0, v6
10000a010: 3dc31108    	ldr	q8, [x8, #0xc40]
10000a014: 4fce9106    	fmul.2d	v6, v8, v14[0]
10000a018: 3d811fe8    	str	q8, [sp, #0x470]
10000a01c: 4e66d400    	fadd.2d	v0, v0, v6
10000a020: 3dc3291e    	ldr	q30, [x8, #0xca0]
10000a024: 4fce9bc6    	fmul.2d	v6, v30, v14[1]
10000a028: 4e66d400    	fadd.2d	v0, v0, v6
10000a02c: d0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000a030: 3dc18924    	ldr	q4, [x9, #0x620]
10000a034: 6e64ddc6    	fmul.2d	v6, v14, v4
10000a038: 3d814be4    	str	q4, [sp, #0x520]
10000a03c: 4e66d426    	fadd.2d	v6, v1, v6
10000a040: 3d81cbe1    	str	q1, [sp, #0x720]
10000a044: 4e66d400    	fadd.2d	v0, v0, v6
10000a048: 3d804be0    	str	q0, [sp, #0x120]
10000a04c: ad451900    	ldp	q0, q6, [x8, #0xa0]
10000a050: 3dc177e7    	ldr	q7, [sp, #0x5d0]
10000a054: 4fc090e7    	fmul.2d	v7, v7, v0[0]
10000a058: 4e67d647    	fadd.2d	v7, v18, v7
10000a05c: 3cd003b2    	ldur	q18, [x29, #-0x100]
10000a060: 4fc09a54    	fmul.2d	v20, v18, v0[1]
10000a064: 4e74d4e7    	fadd.2d	v7, v7, v20
10000a068: 3dc1e3f2    	ldr	q18, [sp, #0x780]
10000a06c: 6e72df34    	fmul.2d	v20, v25, v18
10000a070: 4e74d7b4    	fadd.2d	v20, v29, v20
10000a074: 4e67d687    	fadd.2d	v7, v20, v7
10000a078: 3d80efe7    	str	q7, [sp, #0x3b0]
10000a07c: 3cd603a7    	ldur	q7, [x29, #-0xa0]
10000a080: 4fc090e7    	fmul.2d	v7, v7, v0[0]
10000a084: 4e67d667    	fadd.2d	v7, v19, v7
10000a088: 3dc1d7f2    	ldr	q18, [sp, #0x750]
10000a08c: 4fc09a53    	fmul.2d	v19, v18, v0[1]
10000a090: 4e73d4e7    	fadd.2d	v7, v7, v19
10000a094: 3dc15bf2    	ldr	q18, [sp, #0x560]
10000a098: 6e72def3    	fmul.2d	v19, v23, v18
10000a09c: 3dc16ff4    	ldr	q20, [sp, #0x5b0]
10000a0a0: 4e73d693    	fadd.2d	v19, v20, v19
10000a0a4: 4e67d667    	fadd.2d	v7, v19, v7
10000a0a8: 3d8047e7    	str	q7, [sp, #0x110]
10000a0ac: 3cd403a7    	ldur	q7, [x29, #-0xc0]
10000a0b0: 4fc090e7    	fmul.2d	v7, v7, v0[0]
10000a0b4: 4e67d747    	fadd.2d	v7, v26, v7
10000a0b8: 3cda03b2    	ldur	q18, [x29, #-0x60]
10000a0bc: 4fc09a52    	fmul.2d	v18, v18, v0[1]
10000a0c0: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a0c4: 3dc19bf2    	ldr	q18, [sp, #0x660]
10000a0c8: 6e72de32    	fmul.2d	v18, v17, v18
10000a0cc: 3dc17bfa    	ldr	q26, [sp, #0x5e0]
10000a0d0: 4e72d752    	fadd.2d	v18, v26, v18
10000a0d4: 4e67d647    	fadd.2d	v7, v18, v7
10000a0d8: 3d8043e7    	str	q7, [sp, #0x100]
10000a0dc: 4fc091a7    	fmul.2d	v7, v13, v0[0]
10000a0e0: 4e67d767    	fadd.2d	v7, v27, v7
10000a0e4: 4fc09992    	fmul.2d	v18, v12, v0[1]
10000a0e8: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a0ec: 6e6bde12    	fmul.2d	v18, v16, v11
10000a0f0: 3dc127fb    	ldr	q27, [sp, #0x490]
10000a0f4: 4e72d772    	fadd.2d	v18, v27, v18
10000a0f8: 4e67d647    	fadd.2d	v7, v18, v7
10000a0fc: 3d80ffe7    	str	q7, [sp, #0x3f0]
10000a100: 4fd99027    	fmul.2d	v7, v1, v25[0]
10000a104: 4fd99872    	fmul.2d	v18, v3, v25[1]
10000a108: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a10c: 91282109    	add	x9, x8, #0xa08
10000a110: 4d408522    	ld1.d	{ v2 }[1], [x9]
10000a114: 3d81abe2    	str	q2, [sp, #0x6a0]
10000a118: 4fd79052    	fmul.2d	v18, v2, v23[0]
10000a11c: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a120: 4fd79952    	fmul.2d	v18, v10, v23[1]
10000a124: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a128: 4fd19132    	fmul.2d	v18, v9, v17[0]
10000a12c: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a130: 4fd19ad2    	fmul.2d	v18, v22, v17[1]
10000a134: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a138: 4fd09312    	fmul.2d	v18, v24, v16[0]
10000a13c: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a140: 4fd09ab2    	fmul.2d	v18, v21, v16[1]
10000a144: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a148: 4fc09112    	fmul.2d	v18, v8, v0[0]
10000a14c: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a150: 4fc09bd2    	fmul.2d	v18, v30, v0[1]
10000a154: 4ebe1fd5    	mov.16b	v21, v30
10000a158: 3d8153fe    	str	q30, [sp, #0x540]
10000a15c: 4e72d4e7    	fadd.2d	v7, v7, v18
10000a160: 6e64dc12    	fmul.2d	v18, v0, v4
10000a164: 4e72d472    	fadd.2d	v18, v3, v18
10000a168: 4ea31c76    	mov.16b	v22, v3
10000a16c: 4e67d641    	fadd.2d	v1, v18, v7
10000a170: 3d803fe1    	str	q1, [sp, #0xf0]
10000a174: 3dc25502    	ldr	q2, [x8, #0x950]
10000a178: 4fc59047    	fmul.2d	v7, v2, v5[0]
10000a17c: 3dc26d01    	ldr	q1, [x8, #0x9b0]
10000a180: 4fc59825    	fmul.2d	v5, v1, v5[1]
10000a184: 4e65d4e5    	fadd.2d	v5, v7, v5
10000a188: 3dc28512    	ldr	q18, [x8, #0xa10]
10000a18c: 4fdf9247    	fmul.2d	v7, v18, v31[0]
10000a190: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a194: 3dc29d0a    	ldr	q10, [x8, #0xa70]
10000a198: 4fdf9947    	fmul.2d	v7, v10, v31[1]
10000a19c: 3d812fea    	str	q10, [sp, #0x4b0]
10000a1a0: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a1a4: 3dc2b509    	ldr	q9, [x8, #0xad0]
10000a1a8: 4fdc9127    	fmul.2d	v7, v9, v28[0]
10000a1ac: 3d8183e9    	str	q9, [sp, #0x600]
10000a1b0: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a1b4: 3dc2cd08    	ldr	q8, [x8, #0xb30]
10000a1b8: 4fdc9907    	fmul.2d	v7, v8, v28[1]
10000a1bc: 3d81dfe8    	str	q8, [sp, #0x770]
10000a1c0: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a1c4: 3dc2e51e    	ldr	q30, [x8, #0xb90]
10000a1c8: 4fcf93c7    	fmul.2d	v7, v30, v15[0]
10000a1cc: 3c9703be    	stur	q30, [x29, #-0x90]
10000a1d0: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a1d4: 3dc2fd1f    	ldr	q31, [x8, #0xbf0]
10000a1d8: 4fcf9be7    	fmul.2d	v7, v31, v15[1]
10000a1dc: 3d81b3ff    	str	q31, [sp, #0x6c0]
10000a1e0: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a1e4: 3dc3151c    	ldr	q28, [x8, #0xc50]
10000a1e8: 4fce9387    	fmul.2d	v7, v28, v14[0]
10000a1ec: 3d81c3fc    	str	q28, [sp, #0x700]
10000a1f0: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a1f4: 3dc32d18    	ldr	q24, [x8, #0xcb0]
10000a1f8: 4fce9b07    	fmul.2d	v7, v24, v14[1]
10000a1fc: 3c9803b8    	stur	q24, [x29, #-0x80]
10000a200: 4e67d4a5    	fadd.2d	v5, v5, v7
10000a204: d0000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000a208: 3dc18d33    	ldr	q19, [x9, #0x630]
10000a20c: 3dc1afe4    	ldr	q4, [sp, #0x6b0]
10000a210: 6e73dc87    	fmul.2d	v7, v4, v19
10000a214: 3d8167f3    	str	q19, [sp, #0x590]
10000a218: 3d81c7e2    	str	q2, [sp, #0x710]
10000a21c: 4e67d447    	fadd.2d	v7, v2, v7
10000a220: 4e67d4a3    	fadd.2d	v3, v5, v7
10000a224: 3d803be3    	str	q3, [sp, #0xe0]
10000a228: 4fd99045    	fmul.2d	v5, v2, v25[0]
10000a22c: 4ea11c27    	mov.16b	v7, v1
10000a230: 4fd99824    	fmul.2d	v4, v1, v25[1]
10000a234: 4e64d4a4    	fadd.2d	v4, v5, v4
10000a238: 91286109    	add	x9, x8, #0xa18
10000a23c: 4d408532    	ld1.d	{ v18 }[1], [x9]
10000a240: 3d81aff2    	str	q18, [sp, #0x6b0]
10000a244: 4fd79245    	fmul.2d	v5, v18, v23[0]
10000a248: 4e65d484    	fadd.2d	v4, v4, v5
10000a24c: 4fd79943    	fmul.2d	v3, v10, v23[1]
10000a250: 4e63d483    	fadd.2d	v3, v4, v3
10000a254: 4fd19124    	fmul.2d	v4, v9, v17[0]
10000a258: 4e64d463    	fadd.2d	v3, v3, v4
10000a25c: 4fd19902    	fmul.2d	v2, v8, v17[1]
10000a260: 4e62d462    	fadd.2d	v2, v3, v2
10000a264: 4fd093c3    	fmul.2d	v3, v30, v16[0]
10000a268: 4e63d442    	fadd.2d	v2, v2, v3
10000a26c: 4fd09be1    	fmul.2d	v1, v31, v16[1]
10000a270: 4e61d441    	fadd.2d	v1, v2, v1
10000a274: 4fc09382    	fmul.2d	v2, v28, v0[0]
10000a278: 4e62d421    	fadd.2d	v1, v1, v2
10000a27c: 4fc09b00    	fmul.2d	v0, v24, v0[1]
10000a280: 4e60d420    	fadd.2d	v0, v1, v0
10000a284: 6e73dcc1    	fmul.2d	v1, v6, v19
10000a288: 4e61d4e1    	fadd.2d	v1, v7, v1
10000a28c: 4ea71cf9    	mov.16b	v25, v7
10000a290: 3d8133e7    	str	q7, [sp, #0x4c0]
10000a294: 4e61d400    	fadd.2d	v0, v0, v1
10000a298: 3d8037e0    	str	q0, [sp, #0xd0]
10000a29c: ad460500    	ldp	q0, q1, [x8, #0xc0]
10000a2a0: 3dc1a7e2    	ldr	q2, [sp, #0x690]
10000a2a4: 4fc09042    	fmul.2d	v2, v2, v0[0]
10000a2a8: 4fc09ba3    	fmul.2d	v3, v29, v0[1]
10000a2ac: 4ebd1fb3    	mov.16b	v19, v29
10000a2b0: 3d810ffd    	str	q29, [sp, #0x430]
10000a2b4: 4e63d442    	fadd.2d	v2, v2, v3
10000a2b8: 3dc14ff0    	ldr	q16, [sp, #0x530]
10000a2bc: 4fc19203    	fmul.2d	v3, v16, v1[0]
10000a2c0: 4e63d442    	fadd.2d	v2, v2, v3
10000a2c4: 3dc12be3    	ldr	q3, [sp, #0x4a0]
10000a2c8: 4fc19863    	fmul.2d	v3, v3, v1[1]
10000a2cc: 4e63d444    	fadd.2d	v4, v2, v3
10000a2d0: 3dc11bf1    	ldr	q17, [sp, #0x460]
10000a2d4: 4fc09222    	fmul.2d	v2, v17, v0[0]
10000a2d8: 4fc09a83    	fmul.2d	v3, v20, v0[1]
10000a2dc: 4eb41e92    	mov.16b	v18, v20
10000a2e0: 4e63d442    	fadd.2d	v2, v2, v3
10000a2e4: 3dc173f8    	ldr	q24, [sp, #0x5c0]
10000a2e8: 4fc19303    	fmul.2d	v3, v24, v1[0]
10000a2ec: 4e63d442    	fadd.2d	v2, v2, v3
10000a2f0: 3dc1bfe3    	ldr	q3, [sp, #0x6f0]
10000a2f4: 4fc19863    	fmul.2d	v3, v3, v1[1]
10000a2f8: 4e63d445    	fadd.2d	v5, v2, v3
10000a2fc: ad470d02    	ldp	q2, q3, [x8, #0xe0]
10000a300: 3dc15fe6    	ldr	q6, [sp, #0x570]
10000a304: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000a308: 4e66d484    	fadd.2d	v4, v4, v6
10000a30c: 3dc123e6    	ldr	q6, [sp, #0x480]
10000a310: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000a314: 4e66d484    	fadd.2d	v4, v4, v6
10000a318: 3dc1a3e6    	ldr	q6, [sp, #0x680]
10000a31c: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000a320: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a324: 3dc1d3e6    	ldr	q6, [sp, #0x740]
10000a328: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000a32c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a330: 3dc18be9    	ldr	q9, [sp, #0x620]
10000a334: 4fc09126    	fmul.2d	v6, v9, v0[0]
10000a338: 4fc09b47    	fmul.2d	v7, v26, v0[1]
10000a33c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a340: 3dc13bfa    	ldr	q26, [sp, #0x4e0]
10000a344: 4fc19347    	fmul.2d	v7, v26, v1[0]
10000a348: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a34c: 3dc1bbe7    	ldr	q7, [sp, #0x6e0]
10000a350: 4fc198e7    	fmul.2d	v7, v7, v1[1]
10000a354: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a358: 3dc13fe7    	ldr	q7, [sp, #0x4f0]
10000a35c: 4fc290e7    	fmul.2d	v7, v7, v2[0]
10000a360: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a364: 3dc1cfe7    	ldr	q7, [sp, #0x730]
10000a368: 4fc298e7    	fmul.2d	v7, v7, v2[1]
10000a36c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a370: 3dc117e7    	ldr	q7, [sp, #0x450]
10000a374: 4fc390e7    	fmul.2d	v7, v7, v3[0]
10000a378: 4e67d484    	fadd.2d	v4, v4, v7
10000a37c: 3dc1dbe7    	ldr	q7, [sp, #0x760]
10000a380: 4fc398e7    	fmul.2d	v7, v7, v3[1]
10000a384: 4e67d48e    	fadd.2d	v14, v4, v7
10000a388: 3dc137e8    	ldr	q8, [sp, #0x4d0]
10000a38c: 4fc39104    	fmul.2d	v4, v8, v3[0]
10000a390: 4e64d4a4    	fadd.2d	v4, v5, v4
10000a394: 3dc163f7    	ldr	q23, [sp, #0x580]
10000a398: 4fc39ae5    	fmul.2d	v5, v23, v3[1]
10000a39c: 4e65d48d    	fadd.2d	v13, v4, v5
10000a3a0: 3dc193e4    	ldr	q4, [sp, #0x640]
10000a3a4: 4fc39084    	fmul.2d	v4, v4, v3[0]
10000a3a8: 4e64d4c4    	fadd.2d	v4, v6, v4
10000a3ac: 3dc1b7fc    	ldr	q28, [sp, #0x6d0]
10000a3b0: 4fc39b85    	fmul.2d	v5, v28, v3[1]
10000a3b4: 4e65d487    	fadd.2d	v7, v4, v5
10000a3b8: 3dc10bea    	ldr	q10, [sp, #0x420]
10000a3bc: 4fc09144    	fmul.2d	v4, v10, v0[0]
10000a3c0: 4fc09b65    	fmul.2d	v5, v27, v0[1]
10000a3c4: 4e65d484    	fadd.2d	v4, v4, v5
10000a3c8: 3dc143eb    	ldr	q11, [sp, #0x500]
10000a3cc: 4fc19165    	fmul.2d	v5, v11, v1[0]
10000a3d0: 4e65d484    	fadd.2d	v4, v4, v5
10000a3d4: 3dc18fe5    	ldr	q5, [sp, #0x630]
10000a3d8: 4fc198a5    	fmul.2d	v5, v5, v1[1]
10000a3dc: 4e65d484    	fadd.2d	v4, v4, v5
10000a3e0: 3dc19fe5    	ldr	q5, [sp, #0x670]
10000a3e4: 4fc290a5    	fmul.2d	v5, v5, v2[0]
10000a3e8: 4e65d484    	fadd.2d	v4, v4, v5
10000a3ec: 3cd503a5    	ldur	q5, [x29, #-0xb0]
10000a3f0: 4fc298a5    	fmul.2d	v5, v5, v2[1]
10000a3f4: 4e65d484    	fadd.2d	v4, v4, v5
10000a3f8: 3dc157e5    	ldr	q5, [sp, #0x550]
10000a3fc: 4fc390a5    	fmul.2d	v5, v5, v3[0]
10000a400: 4e65d484    	fadd.2d	v4, v4, v5
10000a404: 3dc187fd    	ldr	q29, [sp, #0x610]
10000a408: 4fc39ba5    	fmul.2d	v5, v29, v3[1]
10000a40c: 4e65d486    	fadd.2d	v6, v4, v5
10000a410: ad481504    	ldp	q4, q5, [x8, #0x100]
10000a414: 3dc177fe    	ldr	q30, [sp, #0x5d0]
10000a418: 4fc493df    	fmul.2d	v31, v30, v4[0]
10000a41c: 4e7fd5df    	fadd.2d	v31, v14, v31
10000a420: 3cd003b4    	ldur	q20, [x29, #-0x100]
10000a424: 4fc49a8e    	fmul.2d	v14, v20, v4[1]
10000a428: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000a42c: 3dc1e3f4    	ldr	q20, [sp, #0x780]
10000a430: 6e74dc0e    	fmul.2d	v14, v0, v20
10000a434: 4eb01e1b    	mov.16b	v27, v16
10000a438: 4e6ed60e    	fadd.2d	v14, v16, v14
10000a43c: 4e7fd5d0    	fadd.2d	v16, v14, v31
10000a440: 3d8107f0    	str	q16, [sp, #0x410]
10000a444: 3cd603b0    	ldur	q16, [x29, #-0xa0]
10000a448: 4fc4921f    	fmul.2d	v31, v16, v4[0]
10000a44c: 4e7fd5bf    	fadd.2d	v31, v13, v31
10000a450: 3dc1d7ec    	ldr	q12, [sp, #0x750]
10000a454: 4fc4998d    	fmul.2d	v13, v12, v4[1]
10000a458: 4e6dd7ff    	fadd.2d	v31, v31, v13
10000a45c: 3dc15bf0    	ldr	q16, [sp, #0x560]
10000a460: 6e70dc2d    	fmul.2d	v13, v1, v16
10000a464: 4e6dd70d    	fadd.2d	v13, v24, v13
10000a468: 4e7fd5b0    	fadd.2d	v16, v13, v31
10000a46c: 3d8033f0    	str	q16, [sp, #0xc0]
10000a470: 3cd403b0    	ldur	q16, [x29, #-0xc0]
10000a474: 4fc4921f    	fmul.2d	v31, v16, v4[0]
10000a478: 4e7fd4e7    	fadd.2d	v7, v7, v31
10000a47c: 3cda03b0    	ldur	q16, [x29, #-0x60]
10000a480: 4fc49a1f    	fmul.2d	v31, v16, v4[1]
10000a484: 4e7fd4e7    	fadd.2d	v7, v7, v31
10000a488: 3dc19bf0    	ldr	q16, [sp, #0x660]
10000a48c: 6e70dc5f    	fmul.2d	v31, v2, v16
10000a490: 4eba1f50    	mov.16b	v16, v26
10000a494: 4e7fd75f    	fadd.2d	v31, v26, v31
10000a498: 4e67d7e7    	fadd.2d	v7, v31, v7
10000a49c: 3d80c7e7    	str	q7, [sp, #0x310]
10000a4a0: 3dc16be7    	ldr	q7, [sp, #0x5a0]
10000a4a4: 4fc490e7    	fmul.2d	v7, v7, v4[0]
10000a4a8: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a4ac: 3cd103af    	ldur	q15, [x29, #-0xf0]
10000a4b0: 4fc499e7    	fmul.2d	v7, v15, v4[1]
10000a4b4: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a4b8: 3dc147fa    	ldr	q26, [sp, #0x510]
10000a4bc: 6e7adc67    	fmul.2d	v7, v3, v26
10000a4c0: 4e67d567    	fadd.2d	v7, v11, v7
10000a4c4: 4e66d4e6    	fadd.2d	v6, v7, v6
10000a4c8: 3d80cbe6    	str	q6, [sp, #0x320]
10000a4cc: 3dc1cbe6    	ldr	q6, [sp, #0x720]
10000a4d0: 4fc090c6    	fmul.2d	v6, v6, v0[0]
10000a4d4: 3d8113f6    	str	q22, [sp, #0x440]
10000a4d8: 4fc09ac7    	fmul.2d	v7, v22, v0[1]
10000a4dc: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a4e0: 3dc1abf6    	ldr	q22, [sp, #0x6a0]
10000a4e4: 4fc192c7    	fmul.2d	v7, v22, v1[0]
10000a4e8: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a4ec: 3dc17fe7    	ldr	q7, [sp, #0x5f0]
10000a4f0: 4fc198e7    	fmul.2d	v7, v7, v1[1]
10000a4f4: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a4f8: 3dc197e7    	ldr	q7, [sp, #0x650]
10000a4fc: 4fc290e7    	fmul.2d	v7, v7, v2[0]
10000a500: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a504: 3cd203a7    	ldur	q7, [x29, #-0xe0]
10000a508: 4fc298e7    	fmul.2d	v7, v7, v2[1]
10000a50c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a510: 3cd903a7    	ldur	q7, [x29, #-0x70]
10000a514: 4fc390e7    	fmul.2d	v7, v7, v3[0]
10000a518: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a51c: 3cd303a7    	ldur	q7, [x29, #-0xd0]
10000a520: 4fc398e7    	fmul.2d	v7, v7, v3[1]
10000a524: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a528: 3dc11fe7    	ldr	q7, [sp, #0x470]
10000a52c: 4fc490e7    	fmul.2d	v7, v7, v4[0]
10000a530: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a534: 4fc49aa7    	fmul.2d	v7, v21, v4[1]
10000a538: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a53c: 3dc14bf5    	ldr	q21, [sp, #0x520]
10000a540: 6e75dc87    	fmul.2d	v7, v4, v21
10000a544: 4e67d6c7    	fadd.2d	v7, v22, v7
10000a548: 4e66d4e6    	fadd.2d	v6, v7, v6
10000a54c: 3d80f7e6    	str	q6, [sp, #0x3d0]
10000a550: 3dc1c7e6    	ldr	q6, [sp, #0x710]
10000a554: 4fc090c6    	fmul.2d	v6, v6, v0[0]
10000a558: 4fc09b20    	fmul.2d	v0, v25, v0[1]
10000a55c: 4e60d4c0    	fadd.2d	v0, v6, v0
10000a560: 3dc1afe7    	ldr	q7, [sp, #0x6b0]
10000a564: 4fc190e6    	fmul.2d	v6, v7, v1[0]
10000a568: 4e66d400    	fadd.2d	v0, v0, v6
10000a56c: 3dc12fe6    	ldr	q6, [sp, #0x4b0]
10000a570: 4fc198c1    	fmul.2d	v1, v6, v1[1]
10000a574: 4e61d400    	fadd.2d	v0, v0, v1
10000a578: 3dc183e1    	ldr	q1, [sp, #0x600]
10000a57c: 4fc29021    	fmul.2d	v1, v1, v2[0]
10000a580: 4e61d400    	fadd.2d	v0, v0, v1
10000a584: 3dc1dfe1    	ldr	q1, [sp, #0x770]
10000a588: 4fc29821    	fmul.2d	v1, v1, v2[1]
10000a58c: 4e61d400    	fadd.2d	v0, v0, v1
10000a590: 3cd703a1    	ldur	q1, [x29, #-0x90]
10000a594: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000a598: 4e61d400    	fadd.2d	v0, v0, v1
10000a59c: 3dc1b3e1    	ldr	q1, [sp, #0x6c0]
10000a5a0: 4fc39821    	fmul.2d	v1, v1, v3[1]
10000a5a4: 4e61d400    	fadd.2d	v0, v0, v1
10000a5a8: 3dc1c3e1    	ldr	q1, [sp, #0x700]
10000a5ac: 4fc49021    	fmul.2d	v1, v1, v4[0]
10000a5b0: 4e61d400    	fadd.2d	v0, v0, v1
10000a5b4: 3cd803a1    	ldur	q1, [x29, #-0x80]
10000a5b8: 4fc49821    	fmul.2d	v1, v1, v4[1]
10000a5bc: 4e61d400    	fadd.2d	v0, v0, v1
10000a5c0: 3dc167e1    	ldr	q1, [sp, #0x590]
10000a5c4: 6e61dca1    	fmul.2d	v1, v5, v1
10000a5c8: 4e61d4e1    	fadd.2d	v1, v7, v1
10000a5cc: 4e61d400    	fadd.2d	v0, v0, v1
10000a5d0: 3d80e7e0    	str	q0, [sp, #0x390]
10000a5d4: ad490500    	ldp	q0, q1, [x8, #0x120]
10000a5d8: 3dc1a7e2    	ldr	q2, [sp, #0x690]
10000a5dc: 4fc09042    	fmul.2d	v2, v2, v0[0]
10000a5e0: 4fc09a63    	fmul.2d	v3, v19, v0[1]
10000a5e4: 4e63d442    	fadd.2d	v2, v2, v3
10000a5e8: 4fc19363    	fmul.2d	v3, v27, v1[0]
10000a5ec: 4e63d442    	fadd.2d	v2, v2, v3
10000a5f0: 3dc12bf6    	ldr	q22, [sp, #0x4a0]
10000a5f4: 4fc19ac3    	fmul.2d	v3, v22, v1[1]
10000a5f8: 4e63d444    	fadd.2d	v4, v2, v3
10000a5fc: 4fc09222    	fmul.2d	v2, v17, v0[0]
10000a600: 4fc09a43    	fmul.2d	v3, v18, v0[1]
10000a604: 4e63d442    	fadd.2d	v2, v2, v3
10000a608: 4fc19303    	fmul.2d	v3, v24, v1[0]
10000a60c: 4e63d442    	fadd.2d	v2, v2, v3
10000a610: 3dc1bff2    	ldr	q18, [sp, #0x6f0]
10000a614: 4fc19a43    	fmul.2d	v3, v18, v1[1]
10000a618: 4e63d445    	fadd.2d	v5, v2, v3
10000a61c: ad4a0d02    	ldp	q2, q3, [x8, #0x140]
10000a620: 3dc15fe6    	ldr	q6, [sp, #0x570]
10000a624: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000a628: 4e66d484    	fadd.2d	v4, v4, v6
10000a62c: 3dc123f9    	ldr	q25, [sp, #0x480]
10000a630: 4fc29b26    	fmul.2d	v6, v25, v2[1]
10000a634: 4e66d484    	fadd.2d	v4, v4, v6
10000a638: 3dc1a3e6    	ldr	q6, [sp, #0x680]
10000a63c: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000a640: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a644: 3dc1d3e6    	ldr	q6, [sp, #0x740]
10000a648: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000a64c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a650: 4fc09126    	fmul.2d	v6, v9, v0[0]
10000a654: 3dc17bf8    	ldr	q24, [sp, #0x5e0]
10000a658: 4fc09b07    	fmul.2d	v7, v24, v0[1]
10000a65c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a660: 4fc19207    	fmul.2d	v7, v16, v1[0]
10000a664: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a668: 3dc1bbf3    	ldr	q19, [sp, #0x6e0]
10000a66c: 4fc19a67    	fmul.2d	v7, v19, v1[1]
10000a670: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a674: 3dc13fe9    	ldr	q9, [sp, #0x4f0]
10000a678: 4fc29127    	fmul.2d	v7, v9, v2[0]
10000a67c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a680: 3dc1cfe7    	ldr	q7, [sp, #0x730]
10000a684: 4fc298e7    	fmul.2d	v7, v7, v2[1]
10000a688: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a68c: 3dc117e7    	ldr	q7, [sp, #0x450]
10000a690: 4fc390e7    	fmul.2d	v7, v7, v3[0]
10000a694: 4e67d484    	fadd.2d	v4, v4, v7
10000a698: 3dc1dbe7    	ldr	q7, [sp, #0x760]
10000a69c: 4fc398e7    	fmul.2d	v7, v7, v3[1]
10000a6a0: 4e67d48e    	fadd.2d	v14, v4, v7
10000a6a4: 4fc39104    	fmul.2d	v4, v8, v3[0]
10000a6a8: 4e64d4a4    	fadd.2d	v4, v5, v4
10000a6ac: 4fc39ae5    	fmul.2d	v5, v23, v3[1]
10000a6b0: 4e65d48d    	fadd.2d	v13, v4, v5
10000a6b4: 3dc193e4    	ldr	q4, [sp, #0x640]
10000a6b8: 4fc39084    	fmul.2d	v4, v4, v3[0]
10000a6bc: 4e64d4c4    	fadd.2d	v4, v6, v4
10000a6c0: 4fc39b85    	fmul.2d	v5, v28, v3[1]
10000a6c4: 4e65d486    	fadd.2d	v6, v4, v5
10000a6c8: 4fc09144    	fmul.2d	v4, v10, v0[0]
10000a6cc: 3dc127f7    	ldr	q23, [sp, #0x490]
10000a6d0: 4fc09ae5    	fmul.2d	v5, v23, v0[1]
10000a6d4: 4e65d484    	fadd.2d	v4, v4, v5
10000a6d8: 4fc19165    	fmul.2d	v5, v11, v1[0]
10000a6dc: 4e65d484    	fadd.2d	v4, v4, v5
10000a6e0: 3dc18ff1    	ldr	q17, [sp, #0x630]
10000a6e4: 4fc19a25    	fmul.2d	v5, v17, v1[1]
10000a6e8: 4e65d484    	fadd.2d	v4, v4, v5
10000a6ec: 3dc19fe5    	ldr	q5, [sp, #0x670]
10000a6f0: 4fc290a5    	fmul.2d	v5, v5, v2[0]
10000a6f4: 4e65d484    	fadd.2d	v4, v4, v5
10000a6f8: 3cd503a5    	ldur	q5, [x29, #-0xb0]
10000a6fc: 4fc298a5    	fmul.2d	v5, v5, v2[1]
10000a700: 4e65d484    	fadd.2d	v4, v4, v5
10000a704: 3dc157fb    	ldr	q27, [sp, #0x550]
10000a708: 4fc39365    	fmul.2d	v5, v27, v3[0]
10000a70c: 4e65d484    	fadd.2d	v4, v4, v5
10000a710: 4fc39ba5    	fmul.2d	v5, v29, v3[1]
10000a714: 4e65d485    	fadd.2d	v5, v4, v5
10000a718: ad4b1d04    	ldp	q4, q7, [x8, #0x160]
10000a71c: 4fc493df    	fmul.2d	v31, v30, v4[0]
10000a720: 4e7fd5df    	fadd.2d	v31, v14, v31
10000a724: 3cd003b0    	ldur	q16, [x29, #-0x100]
10000a728: 4fc49a0e    	fmul.2d	v14, v16, v4[1]
10000a72c: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000a730: 6e74dc0e    	fmul.2d	v14, v0, v20
10000a734: 4e6ed6ce    	fadd.2d	v14, v22, v14
10000a738: 4e7fd5d0    	fadd.2d	v16, v14, v31
10000a73c: 3d80fbf0    	str	q16, [sp, #0x3e0]
10000a740: 3cd603b0    	ldur	q16, [x29, #-0xa0]
10000a744: 4fc4921f    	fmul.2d	v31, v16, v4[0]
10000a748: 4e7fd5bf    	fadd.2d	v31, v13, v31
10000a74c: 4fc4998d    	fmul.2d	v13, v12, v4[1]
10000a750: 4e6dd7ff    	fadd.2d	v31, v31, v13
10000a754: 3dc15bec    	ldr	q12, [sp, #0x560]
10000a758: 6e6cdc2d    	fmul.2d	v13, v1, v12
10000a75c: 4e6dd64d    	fadd.2d	v13, v18, v13
10000a760: 4e7fd5b0    	fadd.2d	v16, v13, v31
10000a764: 3d802ff0    	str	q16, [sp, #0xb0]
10000a768: 3cd403b0    	ldur	q16, [x29, #-0xc0]
10000a76c: 4fc4921f    	fmul.2d	v31, v16, v4[0]
10000a770: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000a774: 3cda03b0    	ldur	q16, [x29, #-0x60]
10000a778: 4fc49a1f    	fmul.2d	v31, v16, v4[1]
10000a77c: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000a780: 3dc19bfd    	ldr	q29, [sp, #0x660]
10000a784: 6e7ddc5f    	fmul.2d	v31, v2, v29
10000a788: 4eb31e70    	mov.16b	v16, v19
10000a78c: 4e7fd67f    	fadd.2d	v31, v19, v31
10000a790: 4e66d7e6    	fadd.2d	v6, v31, v6
10000a794: 3d80f3e6    	str	q6, [sp, #0x3c0]
10000a798: 3dc16be6    	ldr	q6, [sp, #0x5a0]
10000a79c: 4fc490c6    	fmul.2d	v6, v6, v4[0]
10000a7a0: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a7a4: 4fc499e6    	fmul.2d	v6, v15, v4[1]
10000a7a8: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a7ac: 6e7adc66    	fmul.2d	v6, v3, v26
10000a7b0: 4e66d626    	fadd.2d	v6, v17, v6
10000a7b4: 4e65d4c5    	fadd.2d	v5, v6, v5
10000a7b8: 3d802be5    	str	q5, [sp, #0xa0]
10000a7bc: 3dc1cbe5    	ldr	q5, [sp, #0x720]
10000a7c0: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000a7c4: 3dc113e6    	ldr	q6, [sp, #0x440]
10000a7c8: 4fc098c6    	fmul.2d	v6, v6, v0[1]
10000a7cc: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a7d0: 3dc1abe6    	ldr	q6, [sp, #0x6a0]
10000a7d4: 4fc190c6    	fmul.2d	v6, v6, v1[0]
10000a7d8: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a7dc: 3dc17ff3    	ldr	q19, [sp, #0x5f0]
10000a7e0: 4fc19a66    	fmul.2d	v6, v19, v1[1]
10000a7e4: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a7e8: 3dc197e6    	ldr	q6, [sp, #0x650]
10000a7ec: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000a7f0: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a7f4: 3cd203a6    	ldur	q6, [x29, #-0xe0]
10000a7f8: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000a7fc: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a800: 3cd903a6    	ldur	q6, [x29, #-0x70]
10000a804: 4fc390c6    	fmul.2d	v6, v6, v3[0]
10000a808: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a80c: 3cd303a6    	ldur	q6, [x29, #-0xd0]
10000a810: 4fc398c6    	fmul.2d	v6, v6, v3[1]
10000a814: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a818: 3dc11ffa    	ldr	q26, [sp, #0x470]
10000a81c: 4fc49346    	fmul.2d	v6, v26, v4[0]
10000a820: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a824: 3dc153ea    	ldr	q10, [sp, #0x540]
10000a828: 4fc49946    	fmul.2d	v6, v10, v4[1]
10000a82c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a830: 6e75dc86    	fmul.2d	v6, v4, v21
10000a834: 4e66d666    	fadd.2d	v6, v19, v6
10000a838: 4e65d4c5    	fadd.2d	v5, v6, v5
10000a83c: 3d80dfe5    	str	q5, [sp, #0x370]
10000a840: 3dc1c7e5    	ldr	q5, [sp, #0x710]
10000a844: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000a848: 3dc133e6    	ldr	q6, [sp, #0x4c0]
10000a84c: 4fc098c0    	fmul.2d	v0, v6, v0[1]
10000a850: 4e60d4a0    	fadd.2d	v0, v5, v0
10000a854: 3dc1afe5    	ldr	q5, [sp, #0x6b0]
10000a858: 4fc190a5    	fmul.2d	v5, v5, v1[0]
10000a85c: 4e65d400    	fadd.2d	v0, v0, v5
10000a860: 3dc12ffe    	ldr	q30, [sp, #0x4b0]
10000a864: 4fc19bc1    	fmul.2d	v1, v30, v1[1]
10000a868: 4e61d400    	fadd.2d	v0, v0, v1
10000a86c: 3dc183e1    	ldr	q1, [sp, #0x600]
10000a870: 4fc29021    	fmul.2d	v1, v1, v2[0]
10000a874: 4e61d400    	fadd.2d	v0, v0, v1
10000a878: 3dc1dfe1    	ldr	q1, [sp, #0x770]
10000a87c: 4fc29821    	fmul.2d	v1, v1, v2[1]
10000a880: 4e61d400    	fadd.2d	v0, v0, v1
10000a884: 3cd703a1    	ldur	q1, [x29, #-0x90]
10000a888: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000a88c: 4e61d400    	fadd.2d	v0, v0, v1
10000a890: 3dc1b3e1    	ldr	q1, [sp, #0x6c0]
10000a894: 4fc39821    	fmul.2d	v1, v1, v3[1]
10000a898: 4e61d400    	fadd.2d	v0, v0, v1
10000a89c: 3dc1c3ef    	ldr	q15, [sp, #0x700]
10000a8a0: 4fc491e1    	fmul.2d	v1, v15, v4[0]
10000a8a4: 4e61d400    	fadd.2d	v0, v0, v1
10000a8a8: 3cd803a1    	ldur	q1, [x29, #-0x80]
10000a8ac: 4fc49821    	fmul.2d	v1, v1, v4[1]
10000a8b0: 4e61d400    	fadd.2d	v0, v0, v1
10000a8b4: 3dc167e1    	ldr	q1, [sp, #0x590]
10000a8b8: 6e61dce1    	fmul.2d	v1, v7, v1
10000a8bc: 4e61d7c1    	fadd.2d	v1, v30, v1
10000a8c0: 4e61d400    	fadd.2d	v0, v0, v1
10000a8c4: 3d8027e0    	str	q0, [sp, #0x90]
10000a8c8: ad4c0500    	ldp	q0, q1, [x8, #0x180]
10000a8cc: 3dc1a7e2    	ldr	q2, [sp, #0x690]
10000a8d0: 4fc09042    	fmul.2d	v2, v2, v0[0]
10000a8d4: 3dc10fe3    	ldr	q3, [sp, #0x430]
10000a8d8: 4fc09863    	fmul.2d	v3, v3, v0[1]
10000a8dc: 4e63d442    	fadd.2d	v2, v2, v3
10000a8e0: 3dc14fe3    	ldr	q3, [sp, #0x530]
10000a8e4: 4fc19063    	fmul.2d	v3, v3, v1[0]
10000a8e8: 4e63d442    	fadd.2d	v2, v2, v3
10000a8ec: 4fc19ac3    	fmul.2d	v3, v22, v1[1]
10000a8f0: 4e63d444    	fadd.2d	v4, v2, v3
10000a8f4: 3dc11bf6    	ldr	q22, [sp, #0x460]
10000a8f8: 4fc092c2    	fmul.2d	v2, v22, v0[0]
10000a8fc: 3dc16fe3    	ldr	q3, [sp, #0x5b0]
10000a900: 4fc09863    	fmul.2d	v3, v3, v0[1]
10000a904: 4e63d442    	fadd.2d	v2, v2, v3
10000a908: 3dc173e3    	ldr	q3, [sp, #0x5c0]
10000a90c: 4fc19063    	fmul.2d	v3, v3, v1[0]
10000a910: 4e63d442    	fadd.2d	v2, v2, v3
10000a914: 4fc19a43    	fmul.2d	v3, v18, v1[1]
10000a918: 4e63d445    	fadd.2d	v5, v2, v3
10000a91c: ad4d0d02    	ldp	q2, q3, [x8, #0x1a0]
10000a920: 3dc15feb    	ldr	q11, [sp, #0x570]
10000a924: 4fc29166    	fmul.2d	v6, v11, v2[0]
10000a928: 4e66d484    	fadd.2d	v4, v4, v6
10000a92c: 4fc29b26    	fmul.2d	v6, v25, v2[1]
10000a930: 4e66d484    	fadd.2d	v4, v4, v6
10000a934: 3dc1a3f5    	ldr	q21, [sp, #0x680]
10000a938: 4fc292a6    	fmul.2d	v6, v21, v2[0]
10000a93c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a940: 3dc1d3e6    	ldr	q6, [sp, #0x740]
10000a944: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000a948: 4e66d4a5    	fadd.2d	v5, v5, v6
10000a94c: 3dc18be6    	ldr	q6, [sp, #0x620]
10000a950: 4fc090c6    	fmul.2d	v6, v6, v0[0]
10000a954: 4fc09b07    	fmul.2d	v7, v24, v0[1]
10000a958: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a95c: 3dc13bfc    	ldr	q28, [sp, #0x4e0]
10000a960: 4fc19387    	fmul.2d	v7, v28, v1[0]
10000a964: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a968: 4fc19a07    	fmul.2d	v7, v16, v1[1]
10000a96c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a970: 4ea91d32    	mov.16b	v18, v9
10000a974: 4fc29127    	fmul.2d	v7, v9, v2[0]
10000a978: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a97c: 3dc1cfe7    	ldr	q7, [sp, #0x730]
10000a980: 4fc298e7    	fmul.2d	v7, v7, v2[1]
10000a984: 4e67d4c6    	fadd.2d	v6, v6, v7
10000a988: 3dc117e9    	ldr	q9, [sp, #0x450]
10000a98c: 4fc39127    	fmul.2d	v7, v9, v3[0]
10000a990: 4e67d484    	fadd.2d	v4, v4, v7
10000a994: 3dc1dbe8    	ldr	q8, [sp, #0x760]
10000a998: 4fc39907    	fmul.2d	v7, v8, v3[1]
10000a99c: 4e67d48e    	fadd.2d	v14, v4, v7
10000a9a0: 3dc137e4    	ldr	q4, [sp, #0x4d0]
10000a9a4: 4fc39084    	fmul.2d	v4, v4, v3[0]
10000a9a8: 4e64d4a4    	fadd.2d	v4, v5, v4
10000a9ac: 3dc163e5    	ldr	q5, [sp, #0x580]
10000a9b0: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000a9b4: 4e65d48d    	fadd.2d	v13, v4, v5
10000a9b8: 3dc193e4    	ldr	q4, [sp, #0x640]
10000a9bc: 4fc39084    	fmul.2d	v4, v4, v3[0]
10000a9c0: 4e64d4c4    	fadd.2d	v4, v6, v4
10000a9c4: 3dc1b7e5    	ldr	q5, [sp, #0x6d0]
10000a9c8: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000a9cc: 4e65d486    	fadd.2d	v6, v4, v5
10000a9d0: 3dc10bf4    	ldr	q20, [sp, #0x420]
10000a9d4: 4fc09284    	fmul.2d	v4, v20, v0[0]
10000a9d8: 4fc09ae5    	fmul.2d	v5, v23, v0[1]
10000a9dc: 4e65d484    	fadd.2d	v4, v4, v5
10000a9e0: 3dc143f9    	ldr	q25, [sp, #0x500]
10000a9e4: 4fc19325    	fmul.2d	v5, v25, v1[0]
10000a9e8: 4e65d484    	fadd.2d	v4, v4, v5
10000a9ec: 4fc19a25    	fmul.2d	v5, v17, v1[1]
10000a9f0: 4e65d484    	fadd.2d	v4, v4, v5
10000a9f4: 3dc19ff1    	ldr	q17, [sp, #0x670]
10000a9f8: 4fc29225    	fmul.2d	v5, v17, v2[0]
10000a9fc: 4e65d484    	fadd.2d	v4, v4, v5
10000aa00: 3cd503a5    	ldur	q5, [x29, #-0xb0]
10000aa04: 4fc298a5    	fmul.2d	v5, v5, v2[1]
10000aa08: 4e65d484    	fadd.2d	v4, v4, v5
10000aa0c: 4fc39365    	fmul.2d	v5, v27, v3[0]
10000aa10: 4e65d484    	fadd.2d	v4, v4, v5
10000aa14: 3dc187e5    	ldr	q5, [sp, #0x610]
10000aa18: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000aa1c: 4e65d485    	fadd.2d	v5, v4, v5
10000aa20: ad4e1d04    	ldp	q4, q7, [x8, #0x1c0]
10000aa24: 3dc177f0    	ldr	q16, [sp, #0x5d0]
10000aa28: 4fc4921f    	fmul.2d	v31, v16, v4[0]
10000aa2c: 4e7fd5df    	fadd.2d	v31, v14, v31
10000aa30: 3cd003b0    	ldur	q16, [x29, #-0x100]
10000aa34: 4fc49a0e    	fmul.2d	v14, v16, v4[1]
10000aa38: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000aa3c: 3dc1e3f0    	ldr	q16, [sp, #0x780]
10000aa40: 6e70dc0e    	fmul.2d	v14, v0, v16
10000aa44: 4e6ed56e    	fadd.2d	v14, v11, v14
10000aa48: 4e7fd5d0    	fadd.2d	v16, v14, v31
10000aa4c: 3d80ebf0    	str	q16, [sp, #0x3a0]
10000aa50: 3cd603b3    	ldur	q19, [x29, #-0xa0]
10000aa54: 4fc4927f    	fmul.2d	v31, v19, v4[0]
10000aa58: 4e7fd5bf    	fadd.2d	v31, v13, v31
10000aa5c: 3dc1d7f0    	ldr	q16, [sp, #0x750]
10000aa60: 4fc49a0d    	fmul.2d	v13, v16, v4[1]
10000aa64: 4e6dd7ff    	fadd.2d	v31, v31, v13
10000aa68: 6e6cdc2d    	fmul.2d	v13, v1, v12
10000aa6c: 4eb51eb8    	mov.16b	v24, v21
10000aa70: 4e6dd6ad    	fadd.2d	v13, v21, v13
10000aa74: 4e7fd5b0    	fadd.2d	v16, v13, v31
10000aa78: 3d80e3f0    	str	q16, [sp, #0x380]
10000aa7c: 3cd403b5    	ldur	q21, [x29, #-0xc0]
10000aa80: 4fc492bf    	fmul.2d	v31, v21, v4[0]
10000aa84: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000aa88: 3cda03b0    	ldur	q16, [x29, #-0x60]
10000aa8c: 4fc49a1f    	fmul.2d	v31, v16, v4[1]
10000aa90: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000aa94: 6e7ddc5f    	fmul.2d	v31, v2, v29
10000aa98: 4eb21e50    	mov.16b	v16, v18
10000aa9c: 4e7fd65f    	fadd.2d	v31, v18, v31
10000aaa0: 4e66d7e6    	fadd.2d	v6, v31, v6
10000aaa4: 3d80dbe6    	str	q6, [sp, #0x360]
10000aaa8: 3dc16be6    	ldr	q6, [sp, #0x5a0]
10000aaac: 4fc490c6    	fmul.2d	v6, v6, v4[0]
10000aab0: 4e66d4a5    	fadd.2d	v5, v5, v6
10000aab4: 3cd103a6    	ldur	q6, [x29, #-0xf0]
10000aab8: 4fc498c6    	fmul.2d	v6, v6, v4[1]
10000aabc: 4e66d4a5    	fadd.2d	v5, v5, v6
10000aac0: 3dc147e6    	ldr	q6, [sp, #0x510]
10000aac4: 6e66dc66    	fmul.2d	v6, v3, v6
10000aac8: 4e66d626    	fadd.2d	v6, v17, v6
10000aacc: 4eb11e3f    	mov.16b	v31, v17
10000aad0: 4e65d4c5    	fadd.2d	v5, v6, v5
10000aad4: 3d80d3e5    	str	q5, [sp, #0x340]
10000aad8: 3dc1cbe5    	ldr	q5, [sp, #0x720]
10000aadc: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000aae0: 3dc113e6    	ldr	q6, [sp, #0x440]
10000aae4: 4fc098c6    	fmul.2d	v6, v6, v0[1]
10000aae8: 4e66d4a5    	fadd.2d	v5, v5, v6
10000aaec: 3dc1abf7    	ldr	q23, [sp, #0x6a0]
10000aaf0: 4fc192e6    	fmul.2d	v6, v23, v1[0]
10000aaf4: 4e66d4a5    	fadd.2d	v5, v5, v6
10000aaf8: 3dc17fe6    	ldr	q6, [sp, #0x5f0]
10000aafc: 4fc198c6    	fmul.2d	v6, v6, v1[1]
10000ab00: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ab04: 3dc197f1    	ldr	q17, [sp, #0x650]
10000ab08: 4fc29226    	fmul.2d	v6, v17, v2[0]
10000ab0c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ab10: 3cd203a6    	ldur	q6, [x29, #-0xe0]
10000ab14: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000ab18: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ab1c: 3cd903a6    	ldur	q6, [x29, #-0x70]
10000ab20: 4fc390c6    	fmul.2d	v6, v6, v3[0]
10000ab24: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ab28: 3cd303a6    	ldur	q6, [x29, #-0xd0]
10000ab2c: 4fc398c6    	fmul.2d	v6, v6, v3[1]
10000ab30: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ab34: 4fc49346    	fmul.2d	v6, v26, v4[0]
10000ab38: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ab3c: 4fc49946    	fmul.2d	v6, v10, v4[1]
10000ab40: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ab44: 3dc14be6    	ldr	q6, [sp, #0x520]
10000ab48: 6e66dc86    	fmul.2d	v6, v4, v6
10000ab4c: 4e66d626    	fadd.2d	v6, v17, v6
10000ab50: 4e65d4c5    	fadd.2d	v5, v6, v5
10000ab54: 3d80c3e5    	str	q5, [sp, #0x300]
10000ab58: 3dc1c7e5    	ldr	q5, [sp, #0x710]
10000ab5c: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000ab60: 3dc133e6    	ldr	q6, [sp, #0x4c0]
10000ab64: 4fc098c0    	fmul.2d	v0, v6, v0[1]
10000ab68: 4e60d4a0    	fadd.2d	v0, v5, v0
10000ab6c: 3dc1affb    	ldr	q27, [sp, #0x6b0]
10000ab70: 4fc19365    	fmul.2d	v5, v27, v1[0]
10000ab74: 4e65d400    	fadd.2d	v0, v0, v5
10000ab78: 4fc19bc1    	fmul.2d	v1, v30, v1[1]
10000ab7c: 4e61d400    	fadd.2d	v0, v0, v1
10000ab80: 3dc183e5    	ldr	q5, [sp, #0x600]
10000ab84: 4fc290a1    	fmul.2d	v1, v5, v2[0]
10000ab88: 4e61d400    	fadd.2d	v0, v0, v1
10000ab8c: 3dc1dfe1    	ldr	q1, [sp, #0x770]
10000ab90: 4fc29821    	fmul.2d	v1, v1, v2[1]
10000ab94: 4e61d400    	fadd.2d	v0, v0, v1
10000ab98: 3cd703a1    	ldur	q1, [x29, #-0x90]
10000ab9c: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000aba0: 4e61d400    	fadd.2d	v0, v0, v1
10000aba4: 3dc1b3e1    	ldr	q1, [sp, #0x6c0]
10000aba8: 4fc39821    	fmul.2d	v1, v1, v3[1]
10000abac: 4e61d400    	fadd.2d	v0, v0, v1
10000abb0: 4fc491e1    	fmul.2d	v1, v15, v4[0]
10000abb4: 4e61d400    	fadd.2d	v0, v0, v1
10000abb8: 3cd803a1    	ldur	q1, [x29, #-0x80]
10000abbc: 4fc49821    	fmul.2d	v1, v1, v4[1]
10000abc0: 4e61d400    	fadd.2d	v0, v0, v1
10000abc4: 3dc167e1    	ldr	q1, [sp, #0x590]
10000abc8: 6e61dce1    	fmul.2d	v1, v7, v1
10000abcc: 4e61d4a1    	fadd.2d	v1, v5, v1
10000abd0: 4e61d400    	fadd.2d	v0, v0, v1
10000abd4: 3d8093e0    	str	q0, [sp, #0x240]
10000abd8: ad4f0500    	ldp	q0, q1, [x8, #0x1e0]
10000abdc: 3dc1a7fe    	ldr	q30, [sp, #0x690]
10000abe0: 4fc093c2    	fmul.2d	v2, v30, v0[0]
10000abe4: 3dc10ffd    	ldr	q29, [sp, #0x430]
10000abe8: 4fc09ba3    	fmul.2d	v3, v29, v0[1]
10000abec: 4e63d442    	fadd.2d	v2, v2, v3
10000abf0: 3dc14fe3    	ldr	q3, [sp, #0x530]
10000abf4: 4fc19063    	fmul.2d	v3, v3, v1[0]
10000abf8: 4e63d442    	fadd.2d	v2, v2, v3
10000abfc: 3dc12be3    	ldr	q3, [sp, #0x4a0]
10000ac00: 4fc19863    	fmul.2d	v3, v3, v1[1]
10000ac04: 4e63d444    	fadd.2d	v4, v2, v3
10000ac08: 4fc092c2    	fmul.2d	v2, v22, v0[0]
10000ac0c: 3dc16fe3    	ldr	q3, [sp, #0x5b0]
10000ac10: 4fc09863    	fmul.2d	v3, v3, v0[1]
10000ac14: 4e63d442    	fadd.2d	v2, v2, v3
10000ac18: 3dc173e3    	ldr	q3, [sp, #0x5c0]
10000ac1c: 4fc19063    	fmul.2d	v3, v3, v1[0]
10000ac20: 4e63d442    	fadd.2d	v2, v2, v3
10000ac24: 3dc1bfe3    	ldr	q3, [sp, #0x6f0]
10000ac28: 4fc19863    	fmul.2d	v3, v3, v1[1]
10000ac2c: 4e63d445    	fadd.2d	v5, v2, v3
10000ac30: ad500d02    	ldp	q2, q3, [x8, #0x200]
10000ac34: 4fc29166    	fmul.2d	v6, v11, v2[0]
10000ac38: 4e66d484    	fadd.2d	v4, v4, v6
10000ac3c: 3dc123f2    	ldr	q18, [sp, #0x480]
10000ac40: 4fc29a46    	fmul.2d	v6, v18, v2[1]
10000ac44: 4e66d484    	fadd.2d	v4, v4, v6
10000ac48: 4fc29306    	fmul.2d	v6, v24, v2[0]
10000ac4c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ac50: 3dc1d3eb    	ldr	q11, [sp, #0x740]
10000ac54: 4fc29966    	fmul.2d	v6, v11, v2[1]
10000ac58: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ac5c: 3dc18bea    	ldr	q10, [sp, #0x620]
10000ac60: 4fc09146    	fmul.2d	v6, v10, v0[0]
10000ac64: 3dc17bf8    	ldr	q24, [sp, #0x5e0]
10000ac68: 4fc09b07    	fmul.2d	v7, v24, v0[1]
10000ac6c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000ac70: 4fc19387    	fmul.2d	v7, v28, v1[0]
10000ac74: 4e67d4c6    	fadd.2d	v6, v6, v7
10000ac78: 3dc1bbe7    	ldr	q7, [sp, #0x6e0]
10000ac7c: 4fc198e7    	fmul.2d	v7, v7, v1[1]
10000ac80: 4e67d4c6    	fadd.2d	v6, v6, v7
10000ac84: 4fc29207    	fmul.2d	v7, v16, v2[0]
10000ac88: 4e67d4c6    	fadd.2d	v6, v6, v7
10000ac8c: 3dc1cff0    	ldr	q16, [sp, #0x730]
10000ac90: 4fc29a07    	fmul.2d	v7, v16, v2[1]
10000ac94: 4e67d4c6    	fadd.2d	v6, v6, v7
10000ac98: 4fc39127    	fmul.2d	v7, v9, v3[0]
10000ac9c: 4e67d484    	fadd.2d	v4, v4, v7
10000aca0: 4fc39907    	fmul.2d	v7, v8, v3[1]
10000aca4: 4e67d48e    	fadd.2d	v14, v4, v7
10000aca8: 3dc137e4    	ldr	q4, [sp, #0x4d0]
10000acac: 4fc39084    	fmul.2d	v4, v4, v3[0]
10000acb0: 4e64d4a4    	fadd.2d	v4, v5, v4
10000acb4: 3dc163e5    	ldr	q5, [sp, #0x580]
10000acb8: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000acbc: 4e65d48d    	fadd.2d	v13, v4, v5
10000acc0: 3dc193e4    	ldr	q4, [sp, #0x640]
10000acc4: 4fc39084    	fmul.2d	v4, v4, v3[0]
10000acc8: 4e64d4c4    	fadd.2d	v4, v6, v4
10000accc: 3dc1b7e5    	ldr	q5, [sp, #0x6d0]
10000acd0: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000acd4: 4e65d486    	fadd.2d	v6, v4, v5
10000acd8: 4fc09284    	fmul.2d	v4, v20, v0[0]
10000acdc: 3dc127f6    	ldr	q22, [sp, #0x490]
10000ace0: 4fc09ac5    	fmul.2d	v5, v22, v0[1]
10000ace4: 4e65d484    	fadd.2d	v4, v4, v5
10000ace8: 4fc19325    	fmul.2d	v5, v25, v1[0]
10000acec: 4e65d484    	fadd.2d	v4, v4, v5
10000acf0: 3dc18fe5    	ldr	q5, [sp, #0x630]
10000acf4: 4fc198a5    	fmul.2d	v5, v5, v1[1]
10000acf8: 4e65d484    	fadd.2d	v4, v4, v5
10000acfc: 4fc293e5    	fmul.2d	v5, v31, v2[0]
10000ad00: 4e65d484    	fadd.2d	v4, v4, v5
10000ad04: 3cd503b1    	ldur	q17, [x29, #-0xb0]
10000ad08: 4fc29a25    	fmul.2d	v5, v17, v2[1]
10000ad0c: 4e65d484    	fadd.2d	v4, v4, v5
10000ad10: 3dc157e5    	ldr	q5, [sp, #0x550]
10000ad14: 4fc390a5    	fmul.2d	v5, v5, v3[0]
10000ad18: 4e65d484    	fadd.2d	v4, v4, v5
10000ad1c: 3dc187e5    	ldr	q5, [sp, #0x610]
10000ad20: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000ad24: 4e65d485    	fadd.2d	v5, v4, v5
10000ad28: ad511d04    	ldp	q4, q7, [x8, #0x220]
10000ad2c: 3dc177fa    	ldr	q26, [sp, #0x5d0]
10000ad30: 4fc4935f    	fmul.2d	v31, v26, v4[0]
10000ad34: 4e7fd5df    	fadd.2d	v31, v14, v31
10000ad38: 3cd003b4    	ldur	q20, [x29, #-0x100]
10000ad3c: 4fc49a8e    	fmul.2d	v14, v20, v4[1]
10000ad40: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000ad44: 3dc1e3f4    	ldr	q20, [sp, #0x780]
10000ad48: 6e74dc0e    	fmul.2d	v14, v0, v20
10000ad4c: 4e6ed64e    	fadd.2d	v14, v18, v14
10000ad50: 4e7fd5d4    	fadd.2d	v20, v14, v31
10000ad54: 3d80d7f4    	str	q20, [sp, #0x350]
10000ad58: 4fc4927f    	fmul.2d	v31, v19, v4[0]
10000ad5c: 4e7fd5bf    	fadd.2d	v31, v13, v31
10000ad60: 3dc1d7e8    	ldr	q8, [sp, #0x750]
10000ad64: 4fc4990d    	fmul.2d	v13, v8, v4[1]
10000ad68: 4e6dd7ff    	fadd.2d	v31, v31, v13
10000ad6c: 4eac1d89    	mov.16b	v9, v12
10000ad70: 6e6cdc2d    	fmul.2d	v13, v1, v12
10000ad74: 4eab1d7c    	mov.16b	v28, v11
10000ad78: 4e6dd56d    	fadd.2d	v13, v11, v13
10000ad7c: 4e7fd5b4    	fadd.2d	v20, v13, v31
10000ad80: 3d80cff4    	str	q20, [sp, #0x330]
10000ad84: 4fc492bf    	fmul.2d	v31, v21, v4[0]
10000ad88: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000ad8c: 3cda03ac    	ldur	q12, [x29, #-0x60]
10000ad90: 4fc4999f    	fmul.2d	v31, v12, v4[1]
10000ad94: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000ad98: 3dc19bf3    	ldr	q19, [sp, #0x660]
10000ad9c: 6e73dc5f    	fmul.2d	v31, v2, v19
10000ada0: 4e7fd61f    	fadd.2d	v31, v16, v31
10000ada4: 4eb01e0d    	mov.16b	v13, v16
10000ada8: 4e66d7e6    	fadd.2d	v6, v31, v6
10000adac: 3d80bfe6    	str	q6, [sp, #0x2f0]
10000adb0: 3dc16be6    	ldr	q6, [sp, #0x5a0]
10000adb4: 4fc490c6    	fmul.2d	v6, v6, v4[0]
10000adb8: 4e66d4a5    	fadd.2d	v5, v5, v6
10000adbc: 3cd103a6    	ldur	q6, [x29, #-0xf0]
10000adc0: 4fc498c6    	fmul.2d	v6, v6, v4[1]
10000adc4: 4e66d4a5    	fadd.2d	v5, v5, v6
10000adc8: 3dc147f3    	ldr	q19, [sp, #0x510]
10000adcc: 6e73dc66    	fmul.2d	v6, v3, v19
10000add0: 4e66d626    	fadd.2d	v6, v17, v6
10000add4: 4e65d4c5    	fadd.2d	v5, v6, v5
10000add8: 3d80b7e5    	str	q5, [sp, #0x2d0]
10000addc: 3dc1cbf9    	ldr	q25, [sp, #0x720]
10000ade0: 4fc09325    	fmul.2d	v5, v25, v0[0]
10000ade4: 3dc113e6    	ldr	q6, [sp, #0x440]
10000ade8: 4fc098c6    	fmul.2d	v6, v6, v0[1]
10000adec: 4e66d4a5    	fadd.2d	v5, v5, v6
10000adf0: 4fc192e6    	fmul.2d	v6, v23, v1[0]
10000adf4: 4e66d4a5    	fadd.2d	v5, v5, v6
10000adf8: 3dc17fe6    	ldr	q6, [sp, #0x5f0]
10000adfc: 4fc198c6    	fmul.2d	v6, v6, v1[1]
10000ae00: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ae04: 3dc197e6    	ldr	q6, [sp, #0x650]
10000ae08: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000ae0c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ae10: 3cd203b0    	ldur	q16, [x29, #-0xe0]
10000ae14: 4fc29a06    	fmul.2d	v6, v16, v2[1]
10000ae18: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ae1c: 3cd903a6    	ldur	q6, [x29, #-0x70]
10000ae20: 4fc390c6    	fmul.2d	v6, v6, v3[0]
10000ae24: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ae28: 3cd303a6    	ldur	q6, [x29, #-0xd0]
10000ae2c: 4fc398c6    	fmul.2d	v6, v6, v3[1]
10000ae30: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ae34: 3dc11fe6    	ldr	q6, [sp, #0x470]
10000ae38: 4fc490c6    	fmul.2d	v6, v6, v4[0]
10000ae3c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ae40: 3dc153eb    	ldr	q11, [sp, #0x540]
10000ae44: 4fc49966    	fmul.2d	v6, v11, v4[1]
10000ae48: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ae4c: 3dc14be6    	ldr	q6, [sp, #0x520]
10000ae50: 6e66dc86    	fmul.2d	v6, v4, v6
10000ae54: 4e66d606    	fadd.2d	v6, v16, v6
10000ae58: 4e65d4c5    	fadd.2d	v5, v6, v5
10000ae5c: 3d80afe5    	str	q5, [sp, #0x2b0]
10000ae60: 3dc1c7ef    	ldr	q15, [sp, #0x710]
10000ae64: 4fc091e5    	fmul.2d	v5, v15, v0[0]
10000ae68: 3dc133f4    	ldr	q20, [sp, #0x4c0]
10000ae6c: 4fc09a80    	fmul.2d	v0, v20, v0[1]
10000ae70: 4e60d4a0    	fadd.2d	v0, v5, v0
10000ae74: 4fc19365    	fmul.2d	v5, v27, v1[0]
10000ae78: 4e65d400    	fadd.2d	v0, v0, v5
10000ae7c: 3dc12fe5    	ldr	q5, [sp, #0x4b0]
10000ae80: 4fc198a1    	fmul.2d	v1, v5, v1[1]
10000ae84: 4e61d400    	fadd.2d	v0, v0, v1
10000ae88: 3dc183e1    	ldr	q1, [sp, #0x600]
10000ae8c: 4fc29021    	fmul.2d	v1, v1, v2[0]
10000ae90: 4e61d400    	fadd.2d	v0, v0, v1
10000ae94: 3dc1dfe5    	ldr	q5, [sp, #0x770]
10000ae98: 4fc298a1    	fmul.2d	v1, v5, v2[1]
10000ae9c: 4e61d400    	fadd.2d	v0, v0, v1
10000aea0: 3cd703a1    	ldur	q1, [x29, #-0x90]
10000aea4: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000aea8: 4e61d400    	fadd.2d	v0, v0, v1
10000aeac: 3dc1b3f5    	ldr	q21, [sp, #0x6c0]
10000aeb0: 4fc39aa1    	fmul.2d	v1, v21, v3[1]
10000aeb4: 4e61d400    	fadd.2d	v0, v0, v1
10000aeb8: 3dc1c3e1    	ldr	q1, [sp, #0x700]
10000aebc: 4fc49021    	fmul.2d	v1, v1, v4[0]
10000aec0: 4e61d400    	fadd.2d	v0, v0, v1
10000aec4: 3cd803a1    	ldur	q1, [x29, #-0x80]
10000aec8: 4fc49821    	fmul.2d	v1, v1, v4[1]
10000aecc: 4e61d400    	fadd.2d	v0, v0, v1
10000aed0: 3dc167f7    	ldr	q23, [sp, #0x590]
10000aed4: 6e77dce1    	fmul.2d	v1, v7, v23
10000aed8: 4e61d4a1    	fadd.2d	v1, v5, v1
10000aedc: 4e61d400    	fadd.2d	v0, v0, v1
10000aee0: 3d8023e0    	str	q0, [sp, #0x80]
10000aee4: ad520500    	ldp	q0, q1, [x8, #0x240]
10000aee8: 4fc093c2    	fmul.2d	v2, v30, v0[0]
10000aeec: 4fc09ba3    	fmul.2d	v3, v29, v0[1]
10000aef0: 4e63d442    	fadd.2d	v2, v2, v3
10000aef4: 3dc14ffb    	ldr	q27, [sp, #0x530]
10000aef8: 4fc19363    	fmul.2d	v3, v27, v1[0]
10000aefc: 4e63d442    	fadd.2d	v2, v2, v3
10000af00: 3dc12bfe    	ldr	q30, [sp, #0x4a0]
10000af04: 4fc19bc3    	fmul.2d	v3, v30, v1[1]
10000af08: 4e63d444    	fadd.2d	v4, v2, v3
10000af0c: 3dc11be2    	ldr	q2, [sp, #0x460]
10000af10: 4fc09042    	fmul.2d	v2, v2, v0[0]
10000af14: 3dc16fe3    	ldr	q3, [sp, #0x5b0]
10000af18: 4fc09863    	fmul.2d	v3, v3, v0[1]
10000af1c: 4e63d442    	fadd.2d	v2, v2, v3
10000af20: 3dc173e3    	ldr	q3, [sp, #0x5c0]
10000af24: 4fc19063    	fmul.2d	v3, v3, v1[0]
10000af28: 4e63d442    	fadd.2d	v2, v2, v3
10000af2c: 3dc1bfe3    	ldr	q3, [sp, #0x6f0]
10000af30: 4fc19863    	fmul.2d	v3, v3, v1[1]
10000af34: 4e63d445    	fadd.2d	v5, v2, v3
10000af38: ad530d02    	ldp	q2, q3, [x8, #0x260]
10000af3c: 3dc15fe6    	ldr	q6, [sp, #0x570]
10000af40: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000af44: 4e66d484    	fadd.2d	v4, v4, v6
10000af48: 4fc29a46    	fmul.2d	v6, v18, v2[1]
10000af4c: 4e66d484    	fadd.2d	v4, v4, v6
10000af50: 3dc1a3e6    	ldr	q6, [sp, #0x680]
10000af54: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000af58: 4e66d4a5    	fadd.2d	v5, v5, v6
10000af5c: 4fc29b86    	fmul.2d	v6, v28, v2[1]
10000af60: 4e66d4a5    	fadd.2d	v5, v5, v6
10000af64: 4fc09146    	fmul.2d	v6, v10, v0[0]
10000af68: 4fc09b07    	fmul.2d	v7, v24, v0[1]
10000af6c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000af70: 3dc13be7    	ldr	q7, [sp, #0x4e0]
10000af74: 4fc190e7    	fmul.2d	v7, v7, v1[0]
10000af78: 4e67d4c6    	fadd.2d	v6, v6, v7
10000af7c: 3dc1bbe7    	ldr	q7, [sp, #0x6e0]
10000af80: 4fc198e7    	fmul.2d	v7, v7, v1[1]
10000af84: 4e67d4c6    	fadd.2d	v6, v6, v7
10000af88: 3dc13fe7    	ldr	q7, [sp, #0x4f0]
10000af8c: 4fc290e7    	fmul.2d	v7, v7, v2[0]
10000af90: 4e67d4c6    	fadd.2d	v6, v6, v7
10000af94: 4fc299a7    	fmul.2d	v7, v13, v2[1]
10000af98: 4e67d4c6    	fadd.2d	v6, v6, v7
10000af9c: 3dc117ea    	ldr	q10, [sp, #0x450]
10000afa0: 4fc39147    	fmul.2d	v7, v10, v3[0]
10000afa4: 4e67d484    	fadd.2d	v4, v4, v7
10000afa8: 3dc1dbe7    	ldr	q7, [sp, #0x760]
10000afac: 4fc398e7    	fmul.2d	v7, v7, v3[1]
10000afb0: 4e67d48e    	fadd.2d	v14, v4, v7
10000afb4: 3dc137f8    	ldr	q24, [sp, #0x4d0]
10000afb8: 4fc39304    	fmul.2d	v4, v24, v3[0]
10000afbc: 4e64d4a4    	fadd.2d	v4, v5, v4
10000afc0: 3dc163e5    	ldr	q5, [sp, #0x580]
10000afc4: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000afc8: 4e65d48d    	fadd.2d	v13, v4, v5
10000afcc: 3dc193f0    	ldr	q16, [sp, #0x640]
10000afd0: 4fc39204    	fmul.2d	v4, v16, v3[0]
10000afd4: 4e64d4c4    	fadd.2d	v4, v6, v4
10000afd8: 3dc1b7e5    	ldr	q5, [sp, #0x6d0]
10000afdc: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000afe0: 4e65d486    	fadd.2d	v6, v4, v5
10000afe4: 3dc10be4    	ldr	q4, [sp, #0x420]
10000afe8: 4fc09084    	fmul.2d	v4, v4, v0[0]
10000afec: 4fc09ac5    	fmul.2d	v5, v22, v0[1]
10000aff0: 4e65d484    	fadd.2d	v4, v4, v5
10000aff4: 3dc143e5    	ldr	q5, [sp, #0x500]
10000aff8: 4fc190a5    	fmul.2d	v5, v5, v1[0]
10000affc: 4e65d484    	fadd.2d	v4, v4, v5
10000b000: 3dc18fe5    	ldr	q5, [sp, #0x630]
10000b004: 4fc198a5    	fmul.2d	v5, v5, v1[1]
10000b008: 4e65d484    	fadd.2d	v4, v4, v5
10000b00c: 3dc19fe5    	ldr	q5, [sp, #0x670]
10000b010: 4fc290a5    	fmul.2d	v5, v5, v2[0]
10000b014: 4e65d484    	fadd.2d	v4, v4, v5
10000b018: 4fc29a25    	fmul.2d	v5, v17, v2[1]
10000b01c: 4e65d484    	fadd.2d	v4, v4, v5
10000b020: 3dc157f1    	ldr	q17, [sp, #0x550]
10000b024: 4fc39225    	fmul.2d	v5, v17, v3[0]
10000b028: 4e65d484    	fadd.2d	v4, v4, v5
10000b02c: 3dc187e5    	ldr	q5, [sp, #0x610]
10000b030: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000b034: 4e65d485    	fadd.2d	v5, v4, v5
10000b038: ad541d04    	ldp	q4, q7, [x8, #0x280]
10000b03c: 4fc4935f    	fmul.2d	v31, v26, v4[0]
10000b040: 4e7fd5df    	fadd.2d	v31, v14, v31
10000b044: 3cd003b6    	ldur	q22, [x29, #-0x100]
10000b048: 4fc49ace    	fmul.2d	v14, v22, v4[1]
10000b04c: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000b050: 3dc1e3f6    	ldr	q22, [sp, #0x780]
10000b054: 6e76dc0e    	fmul.2d	v14, v0, v22
10000b058: 4e6ed54e    	fadd.2d	v14, v10, v14
10000b05c: 4e7fd5d6    	fadd.2d	v22, v14, v31
10000b060: 3d80bbf6    	str	q22, [sp, #0x2e0]
10000b064: 3cd603b6    	ldur	q22, [x29, #-0xa0]
10000b068: 4fc492df    	fmul.2d	v31, v22, v4[0]
10000b06c: 4e7fd5bf    	fadd.2d	v31, v13, v31
10000b070: 4fc4990d    	fmul.2d	v13, v8, v4[1]
10000b074: 4e6dd7ff    	fadd.2d	v31, v31, v13
10000b078: 6e69dc2d    	fmul.2d	v13, v1, v9
10000b07c: 4e6dd70d    	fadd.2d	v13, v24, v13
10000b080: 4eb81f08    	mov.16b	v8, v24
10000b084: 4e7fd5b8    	fadd.2d	v24, v13, v31
10000b088: 3d80b3f8    	str	q24, [sp, #0x2c0]
10000b08c: 3cd403b6    	ldur	q22, [x29, #-0xc0]
10000b090: 4fc492df    	fmul.2d	v31, v22, v4[0]
10000b094: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000b098: 4fc4999f    	fmul.2d	v31, v12, v4[1]
10000b09c: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000b0a0: 3dc19bf2    	ldr	q18, [sp, #0x660]
10000b0a4: 6e72dc5f    	fmul.2d	v31, v2, v18
10000b0a8: 4e7fd61f    	fadd.2d	v31, v16, v31
10000b0ac: 4eb01e16    	mov.16b	v22, v16
10000b0b0: 4e66d7e6    	fadd.2d	v6, v31, v6
10000b0b4: 3d80abe6    	str	q6, [sp, #0x2a0]
10000b0b8: 3dc16bf8    	ldr	q24, [sp, #0x5a0]
10000b0bc: 4fc49306    	fmul.2d	v6, v24, v4[0]
10000b0c0: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b0c4: 3cd103a6    	ldur	q6, [x29, #-0xf0]
10000b0c8: 4fc498c6    	fmul.2d	v6, v6, v4[1]
10000b0cc: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b0d0: 6e73dc66    	fmul.2d	v6, v3, v19
10000b0d4: 4e66d626    	fadd.2d	v6, v17, v6
10000b0d8: 4eb11e33    	mov.16b	v19, v17
10000b0dc: 4e65d4c5    	fadd.2d	v5, v6, v5
10000b0e0: 3d80a3e5    	str	q5, [sp, #0x280]
10000b0e4: 4fc09325    	fmul.2d	v5, v25, v0[0]
10000b0e8: 3dc113fa    	ldr	q26, [sp, #0x440]
10000b0ec: 4fc09b46    	fmul.2d	v6, v26, v0[1]
10000b0f0: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b0f4: 3dc1abe6    	ldr	q6, [sp, #0x6a0]
10000b0f8: 4fc190c6    	fmul.2d	v6, v6, v1[0]
10000b0fc: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b100: 3dc17ffc    	ldr	q28, [sp, #0x5f0]
10000b104: 4fc19b86    	fmul.2d	v6, v28, v1[1]
10000b108: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b10c: 3dc197ec    	ldr	q12, [sp, #0x650]
10000b110: 4fc29186    	fmul.2d	v6, v12, v2[0]
10000b114: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b118: 3cd203a6    	ldur	q6, [x29, #-0xe0]
10000b11c: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000b120: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b124: 3cd903b0    	ldur	q16, [x29, #-0x70]
10000b128: 4fc39206    	fmul.2d	v6, v16, v3[0]
10000b12c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b130: 3cd303a6    	ldur	q6, [x29, #-0xd0]
10000b134: 4fc398c6    	fmul.2d	v6, v6, v3[1]
10000b138: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b13c: 3dc11ffd    	ldr	q29, [sp, #0x470]
10000b140: 4fc493a6    	fmul.2d	v6, v29, v4[0]
10000b144: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b148: 4fc49966    	fmul.2d	v6, v11, v4[1]
10000b14c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b150: 3dc14bf1    	ldr	q17, [sp, #0x520]
10000b154: 6e71dc86    	fmul.2d	v6, v4, v17
10000b158: 4e66d606    	fadd.2d	v6, v16, v6
10000b15c: 4e65d4c5    	fadd.2d	v5, v6, v5
10000b160: 3d809be5    	str	q5, [sp, #0x260]
10000b164: 4fc091e5    	fmul.2d	v5, v15, v0[0]
10000b168: 4fc09a80    	fmul.2d	v0, v20, v0[1]
10000b16c: 4e60d4a0    	fadd.2d	v0, v5, v0
10000b170: 3dc1afe5    	ldr	q5, [sp, #0x6b0]
10000b174: 4fc190a5    	fmul.2d	v5, v5, v1[0]
10000b178: 4e65d400    	fadd.2d	v0, v0, v5
10000b17c: 3dc12ff4    	ldr	q20, [sp, #0x4b0]
10000b180: 4fc19a81    	fmul.2d	v1, v20, v1[1]
10000b184: 4e61d400    	fadd.2d	v0, v0, v1
10000b188: 3dc183e1    	ldr	q1, [sp, #0x600]
10000b18c: 4fc29021    	fmul.2d	v1, v1, v2[0]
10000b190: 4e61d400    	fadd.2d	v0, v0, v1
10000b194: 3dc1dfe1    	ldr	q1, [sp, #0x770]
10000b198: 4fc29821    	fmul.2d	v1, v1, v2[1]
10000b19c: 4e61d400    	fadd.2d	v0, v0, v1
10000b1a0: ad7be7a2    	ldp	q2, q25, [x29, #-0x90]
10000b1a4: 4fc39041    	fmul.2d	v1, v2, v3[0]
10000b1a8: 4e61d400    	fadd.2d	v0, v0, v1
10000b1ac: 4fc39aa1    	fmul.2d	v1, v21, v3[1]
10000b1b0: 4e61d400    	fadd.2d	v0, v0, v1
10000b1b4: 3dc1c3e1    	ldr	q1, [sp, #0x700]
10000b1b8: 4fc49021    	fmul.2d	v1, v1, v4[0]
10000b1bc: 4e61d400    	fadd.2d	v0, v0, v1
10000b1c0: 4fc49b21    	fmul.2d	v1, v25, v4[1]
10000b1c4: 4e61d400    	fadd.2d	v0, v0, v1
10000b1c8: 6e77dce1    	fmul.2d	v1, v7, v23
10000b1cc: 4e61d441    	fadd.2d	v1, v2, v1
10000b1d0: 4e61d400    	fadd.2d	v0, v0, v1
10000b1d4: 3d801fe0    	str	q0, [sp, #0x70]
10000b1d8: ad550500    	ldp	q0, q1, [x8, #0x2a0]
10000b1dc: 3dc1a7e2    	ldr	q2, [sp, #0x690]
10000b1e0: 4fc09042    	fmul.2d	v2, v2, v0[0]
10000b1e4: 3dc10fe3    	ldr	q3, [sp, #0x430]
10000b1e8: 4fc09863    	fmul.2d	v3, v3, v0[1]
10000b1ec: 4e63d442    	fadd.2d	v2, v2, v3
10000b1f0: 4fc19363    	fmul.2d	v3, v27, v1[0]
10000b1f4: 4e63d442    	fadd.2d	v2, v2, v3
10000b1f8: 4fc19bc3    	fmul.2d	v3, v30, v1[1]
10000b1fc: 4e63d444    	fadd.2d	v4, v2, v3
10000b200: 3dc11bf2    	ldr	q18, [sp, #0x460]
10000b204: 4fc09242    	fmul.2d	v2, v18, v0[0]
10000b208: 3dc16fe3    	ldr	q3, [sp, #0x5b0]
10000b20c: 4fc09863    	fmul.2d	v3, v3, v0[1]
10000b210: 4e63d442    	fadd.2d	v2, v2, v3
10000b214: 3dc173f5    	ldr	q21, [sp, #0x5c0]
10000b218: 4fc192a3    	fmul.2d	v3, v21, v1[0]
10000b21c: 4e63d442    	fadd.2d	v2, v2, v3
10000b220: 3dc1bfe3    	ldr	q3, [sp, #0x6f0]
10000b224: 4fc19863    	fmul.2d	v3, v3, v1[1]
10000b228: 4e63d445    	fadd.2d	v5, v2, v3
10000b22c: ad560d02    	ldp	q2, q3, [x8, #0x2c0]
10000b230: 3dc15ffe    	ldr	q30, [sp, #0x570]
10000b234: 4fc293c6    	fmul.2d	v6, v30, v2[0]
10000b238: 4e66d484    	fadd.2d	v4, v4, v6
10000b23c: 3dc123e6    	ldr	q6, [sp, #0x480]
10000b240: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000b244: 4e66d484    	fadd.2d	v4, v4, v6
10000b248: 3dc1a3e6    	ldr	q6, [sp, #0x680]
10000b24c: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000b250: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b254: 3dc1d3e9    	ldr	q9, [sp, #0x740]
10000b258: 4fc29926    	fmul.2d	v6, v9, v2[1]
10000b25c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b260: 3dc18be6    	ldr	q6, [sp, #0x620]
10000b264: 4fc090c6    	fmul.2d	v6, v6, v0[0]
10000b268: 3dc17be7    	ldr	q7, [sp, #0x5e0]
10000b26c: 4fc098e7    	fmul.2d	v7, v7, v0[1]
10000b270: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b274: 3dc13be7    	ldr	q7, [sp, #0x4e0]
10000b278: 4fc190e7    	fmul.2d	v7, v7, v1[0]
10000b27c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b280: 3dc1bbe7    	ldr	q7, [sp, #0x6e0]
10000b284: 4fc198e7    	fmul.2d	v7, v7, v1[1]
10000b288: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b28c: 3dc13fe7    	ldr	q7, [sp, #0x4f0]
10000b290: 4fc290e7    	fmul.2d	v7, v7, v2[0]
10000b294: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b298: 3dc1cfe7    	ldr	q7, [sp, #0x730]
10000b29c: 4fc298e7    	fmul.2d	v7, v7, v2[1]
10000b2a0: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b2a4: 4fc39147    	fmul.2d	v7, v10, v3[0]
10000b2a8: 4e67d484    	fadd.2d	v4, v4, v7
10000b2ac: 3dc1dbeb    	ldr	q11, [sp, #0x760]
10000b2b0: 4fc39967    	fmul.2d	v7, v11, v3[1]
10000b2b4: 4e67d48e    	fadd.2d	v14, v4, v7
10000b2b8: 4fc39104    	fmul.2d	v4, v8, v3[0]
10000b2bc: 4e64d4a4    	fadd.2d	v4, v5, v4
10000b2c0: 3dc163fb    	ldr	q27, [sp, #0x580]
10000b2c4: 4fc39b65    	fmul.2d	v5, v27, v3[1]
10000b2c8: 4e65d48d    	fadd.2d	v13, v4, v5
10000b2cc: 4fc392c4    	fmul.2d	v4, v22, v3[0]
10000b2d0: 4e64d4c4    	fadd.2d	v4, v6, v4
10000b2d4: 3dc1b7ef    	ldr	q15, [sp, #0x6d0]
10000b2d8: 4fc399e5    	fmul.2d	v5, v15, v3[1]
10000b2dc: 4e65d486    	fadd.2d	v6, v4, v5
10000b2e0: 3dc10bf6    	ldr	q22, [sp, #0x420]
10000b2e4: 4fc092c4    	fmul.2d	v4, v22, v0[0]
10000b2e8: 3dc127e8    	ldr	q8, [sp, #0x490]
10000b2ec: 4fc09905    	fmul.2d	v5, v8, v0[1]
10000b2f0: 4e65d484    	fadd.2d	v4, v4, v5
10000b2f4: 3dc143e5    	ldr	q5, [sp, #0x500]
10000b2f8: 4fc190a5    	fmul.2d	v5, v5, v1[0]
10000b2fc: 4e65d484    	fadd.2d	v4, v4, v5
10000b300: 3dc18fe5    	ldr	q5, [sp, #0x630]
10000b304: 4fc198a5    	fmul.2d	v5, v5, v1[1]
10000b308: 4e65d484    	fadd.2d	v4, v4, v5
10000b30c: 3dc19fe5    	ldr	q5, [sp, #0x670]
10000b310: 4fc290a5    	fmul.2d	v5, v5, v2[0]
10000b314: 4e65d484    	fadd.2d	v4, v4, v5
10000b318: 3cd503a5    	ldur	q5, [x29, #-0xb0]
10000b31c: 4fc298a5    	fmul.2d	v5, v5, v2[1]
10000b320: 4e65d484    	fadd.2d	v4, v4, v5
10000b324: 4fc39265    	fmul.2d	v5, v19, v3[0]
10000b328: 4e65d484    	fadd.2d	v4, v4, v5
10000b32c: 3dc187f0    	ldr	q16, [sp, #0x610]
10000b330: 4fc39a05    	fmul.2d	v5, v16, v3[1]
10000b334: 4e65d485    	fadd.2d	v5, v4, v5
10000b338: ad571d04    	ldp	q4, q7, [x8, #0x2e0]
10000b33c: 3dc177f3    	ldr	q19, [sp, #0x5d0]
10000b340: 4fc4927f    	fmul.2d	v31, v19, v4[0]
10000b344: 4e7fd5df    	fadd.2d	v31, v14, v31
10000b348: 3cd003b3    	ldur	q19, [x29, #-0x100]
10000b34c: 4fc49a6e    	fmul.2d	v14, v19, v4[1]
10000b350: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000b354: 3dc1e3f7    	ldr	q23, [sp, #0x780]
10000b358: 6e77dc0e    	fmul.2d	v14, v0, v23
10000b35c: 4e6ed56e    	fadd.2d	v14, v11, v14
10000b360: 4e7fd5d7    	fadd.2d	v23, v14, v31
10000b364: 3d80a7f7    	str	q23, [sp, #0x290]
10000b368: 3cd603b7    	ldur	q23, [x29, #-0xa0]
10000b36c: 4fc492ff    	fmul.2d	v31, v23, v4[0]
10000b370: 4e7fd5bf    	fadd.2d	v31, v13, v31
10000b374: 3dc1d7f7    	ldr	q23, [sp, #0x750]
10000b378: 4fc49aed    	fmul.2d	v13, v23, v4[1]
10000b37c: 4e6dd7ff    	fadd.2d	v31, v31, v13
10000b380: 3dc15bf7    	ldr	q23, [sp, #0x560]
10000b384: 6e77dc2d    	fmul.2d	v13, v1, v23
10000b388: 4e6dd76d    	fadd.2d	v13, v27, v13
10000b38c: 4e7fd5b7    	fadd.2d	v23, v13, v31
10000b390: 3d809ff7    	str	q23, [sp, #0x270]
10000b394: 3cd403b7    	ldur	q23, [x29, #-0xc0]
10000b398: 4fc492ff    	fmul.2d	v31, v23, v4[0]
10000b39c: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000b3a0: 3cda03b7    	ldur	q23, [x29, #-0x60]
10000b3a4: 4fc49aff    	fmul.2d	v31, v23, v4[1]
10000b3a8: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000b3ac: 3dc19bf7    	ldr	q23, [sp, #0x660]
10000b3b0: 6e77dc5f    	fmul.2d	v31, v2, v23
10000b3b4: 4e7fd5ff    	fadd.2d	v31, v15, v31
10000b3b8: 4e66d7e6    	fadd.2d	v6, v31, v6
10000b3bc: 3d8097e6    	str	q6, [sp, #0x250]
10000b3c0: 4fc49306    	fmul.2d	v6, v24, v4[0]
10000b3c4: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b3c8: 3cd103a6    	ldur	q6, [x29, #-0xf0]
10000b3cc: 4fc498c6    	fmul.2d	v6, v6, v4[1]
10000b3d0: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b3d4: 3dc147e6    	ldr	q6, [sp, #0x510]
10000b3d8: 6e66dc66    	fmul.2d	v6, v3, v6
10000b3dc: 4e66d606    	fadd.2d	v6, v16, v6
10000b3e0: 4eb01e1f    	mov.16b	v31, v16
10000b3e4: 4e65d4c5    	fadd.2d	v5, v6, v5
10000b3e8: 3d808be5    	str	q5, [sp, #0x220]
10000b3ec: 3dc1cbe5    	ldr	q5, [sp, #0x720]
10000b3f0: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000b3f4: 4fc09b46    	fmul.2d	v6, v26, v0[1]
10000b3f8: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b3fc: 3dc1abe6    	ldr	q6, [sp, #0x6a0]
10000b400: 4fc190c6    	fmul.2d	v6, v6, v1[0]
10000b404: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b408: 4fc19b86    	fmul.2d	v6, v28, v1[1]
10000b40c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b410: 4fc29186    	fmul.2d	v6, v12, v2[0]
10000b414: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b418: ad7943a6    	ldp	q6, q16, [x29, #-0xe0]
10000b41c: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000b420: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b424: 3cd903a6    	ldur	q6, [x29, #-0x70]
10000b428: 4fc390c6    	fmul.2d	v6, v6, v3[0]
10000b42c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b430: 4fc39a06    	fmul.2d	v6, v16, v3[1]
10000b434: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b438: 4fc493a6    	fmul.2d	v6, v29, v4[0]
10000b43c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b440: 3dc153e6    	ldr	q6, [sp, #0x540]
10000b444: 4fc498c6    	fmul.2d	v6, v6, v4[1]
10000b448: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b44c: 6e71dc86    	fmul.2d	v6, v4, v17
10000b450: 4e66d606    	fadd.2d	v6, v16, v6
10000b454: 4e65d4c5    	fadd.2d	v5, v6, v5
10000b458: 3d801be5    	str	q5, [sp, #0x60]
10000b45c: 3dc1c7e5    	ldr	q5, [sp, #0x710]
10000b460: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000b464: 3dc133e6    	ldr	q6, [sp, #0x4c0]
10000b468: 4fc098c0    	fmul.2d	v0, v6, v0[1]
10000b46c: 4e60d4a0    	fadd.2d	v0, v5, v0
10000b470: 3dc1afe5    	ldr	q5, [sp, #0x6b0]
10000b474: 4fc190a5    	fmul.2d	v5, v5, v1[0]
10000b478: 4e65d400    	fadd.2d	v0, v0, v5
10000b47c: 4fc19a81    	fmul.2d	v1, v20, v1[1]
10000b480: 4e61d400    	fadd.2d	v0, v0, v1
10000b484: 3dc183fc    	ldr	q28, [sp, #0x600]
10000b488: 4fc29381    	fmul.2d	v1, v28, v2[0]
10000b48c: 4e61d400    	fadd.2d	v0, v0, v1
10000b490: 3dc1dfe1    	ldr	q1, [sp, #0x770]
10000b494: 4fc29821    	fmul.2d	v1, v1, v2[1]
10000b498: 4e61d400    	fadd.2d	v0, v0, v1
10000b49c: 3cd703a1    	ldur	q1, [x29, #-0x90]
10000b4a0: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000b4a4: 4e61d400    	fadd.2d	v0, v0, v1
10000b4a8: 3dc1b3e2    	ldr	q2, [sp, #0x6c0]
10000b4ac: 4fc39841    	fmul.2d	v1, v2, v3[1]
10000b4b0: 4e61d400    	fadd.2d	v0, v0, v1
10000b4b4: 3dc1c3e1    	ldr	q1, [sp, #0x700]
10000b4b8: 4fc49021    	fmul.2d	v1, v1, v4[0]
10000b4bc: 4e61d400    	fadd.2d	v0, v0, v1
10000b4c0: 4fc49b21    	fmul.2d	v1, v25, v4[1]
10000b4c4: 4e61d400    	fadd.2d	v0, v0, v1
10000b4c8: 3dc167e1    	ldr	q1, [sp, #0x590]
10000b4cc: 6e61dce1    	fmul.2d	v1, v7, v1
10000b4d0: 4e61d441    	fadd.2d	v1, v2, v1
10000b4d4: 4e61d400    	fadd.2d	v0, v0, v1
10000b4d8: 3d8017e0    	str	q0, [sp, #0x50]
10000b4dc: ad580500    	ldp	q0, q1, [x8, #0x300]
10000b4e0: 3dc1a7f1    	ldr	q17, [sp, #0x690]
10000b4e4: 4fc09222    	fmul.2d	v2, v17, v0[0]
10000b4e8: 3dc10fe3    	ldr	q3, [sp, #0x430]
10000b4ec: 4fc09863    	fmul.2d	v3, v3, v0[1]
10000b4f0: 4e63d442    	fadd.2d	v2, v2, v3
10000b4f4: 3dc14fe3    	ldr	q3, [sp, #0x530]
10000b4f8: 4fc19063    	fmul.2d	v3, v3, v1[0]
10000b4fc: 4e63d442    	fadd.2d	v2, v2, v3
10000b500: 3dc12bfd    	ldr	q29, [sp, #0x4a0]
10000b504: 4fc19ba3    	fmul.2d	v3, v29, v1[1]
10000b508: 4e63d444    	fadd.2d	v4, v2, v3
10000b50c: 4fc09242    	fmul.2d	v2, v18, v0[0]
10000b510: 3dc16fe3    	ldr	q3, [sp, #0x5b0]
10000b514: 4fc09863    	fmul.2d	v3, v3, v0[1]
10000b518: 4e63d442    	fadd.2d	v2, v2, v3
10000b51c: 4fc192a3    	fmul.2d	v3, v21, v1[0]
10000b520: 4e63d442    	fadd.2d	v2, v2, v3
10000b524: 3dc1bffa    	ldr	q26, [sp, #0x6f0]
10000b528: 4fc19b43    	fmul.2d	v3, v26, v1[1]
10000b52c: 4e63d445    	fadd.2d	v5, v2, v3
10000b530: ad590d02    	ldp	q2, q3, [x8, #0x320]
10000b534: 4fc293c6    	fmul.2d	v6, v30, v2[0]
10000b538: 4e66d484    	fadd.2d	v4, v4, v6
10000b53c: 3dc123f0    	ldr	q16, [sp, #0x480]
10000b540: 4fc29a06    	fmul.2d	v6, v16, v2[1]
10000b544: 4e66d484    	fadd.2d	v4, v4, v6
10000b548: 3dc1a3e6    	ldr	q6, [sp, #0x680]
10000b54c: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000b550: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b554: 4fc29926    	fmul.2d	v6, v9, v2[1]
10000b558: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b55c: 3dc18be6    	ldr	q6, [sp, #0x620]
10000b560: 4fc090c6    	fmul.2d	v6, v6, v0[0]
10000b564: 3dc17be7    	ldr	q7, [sp, #0x5e0]
10000b568: 4fc098e7    	fmul.2d	v7, v7, v0[1]
10000b56c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b570: 3dc13bec    	ldr	q12, [sp, #0x4e0]
10000b574: 4fc19187    	fmul.2d	v7, v12, v1[0]
10000b578: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b57c: 3dc1bbf2    	ldr	q18, [sp, #0x6e0]
10000b580: 4fc19a47    	fmul.2d	v7, v18, v1[1]
10000b584: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b588: 3dc13ff9    	ldr	q25, [sp, #0x4f0]
10000b58c: 4fc29327    	fmul.2d	v7, v25, v2[0]
10000b590: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b594: 3dc1cfe7    	ldr	q7, [sp, #0x730]
10000b598: 4fc298e7    	fmul.2d	v7, v7, v2[1]
10000b59c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b5a0: 4fc39147    	fmul.2d	v7, v10, v3[0]
10000b5a4: 4e67d484    	fadd.2d	v4, v4, v7
10000b5a8: 4fc39967    	fmul.2d	v7, v11, v3[1]
10000b5ac: 4e67d48e    	fadd.2d	v14, v4, v7
10000b5b0: 3dc137f4    	ldr	q20, [sp, #0x4d0]
10000b5b4: 4fc39284    	fmul.2d	v4, v20, v3[0]
10000b5b8: 4e64d4a4    	fadd.2d	v4, v5, v4
10000b5bc: 4fc39b65    	fmul.2d	v5, v27, v3[1]
10000b5c0: 4e65d48d    	fadd.2d	v13, v4, v5
10000b5c4: 3dc193e4    	ldr	q4, [sp, #0x640]
10000b5c8: 4fc39084    	fmul.2d	v4, v4, v3[0]
10000b5cc: 4e64d4c4    	fadd.2d	v4, v6, v4
10000b5d0: 4fc399e5    	fmul.2d	v5, v15, v3[1]
10000b5d4: 4e65d486    	fadd.2d	v6, v4, v5
10000b5d8: 4fc092c4    	fmul.2d	v4, v22, v0[0]
10000b5dc: 4fc09905    	fmul.2d	v5, v8, v0[1]
10000b5e0: 4e65d484    	fadd.2d	v4, v4, v5
10000b5e4: 3dc143e8    	ldr	q8, [sp, #0x500]
10000b5e8: 4fc19105    	fmul.2d	v5, v8, v1[0]
10000b5ec: 4e65d484    	fadd.2d	v4, v4, v5
10000b5f0: 3dc18fe9    	ldr	q9, [sp, #0x630]
10000b5f4: 4fc19925    	fmul.2d	v5, v9, v1[1]
10000b5f8: 4e65d484    	fadd.2d	v4, v4, v5
10000b5fc: 3dc19ff8    	ldr	q24, [sp, #0x670]
10000b600: 4fc29305    	fmul.2d	v5, v24, v2[0]
10000b604: 4e65d484    	fadd.2d	v4, v4, v5
10000b608: 3cd503a5    	ldur	q5, [x29, #-0xb0]
10000b60c: 4fc298a5    	fmul.2d	v5, v5, v2[1]
10000b610: 4e65d484    	fadd.2d	v4, v4, v5
10000b614: 3dc157e5    	ldr	q5, [sp, #0x550]
10000b618: 4fc390a5    	fmul.2d	v5, v5, v3[0]
10000b61c: 4e65d484    	fadd.2d	v4, v4, v5
10000b620: 4fc39be5    	fmul.2d	v5, v31, v3[1]
10000b624: 4e65d485    	fadd.2d	v5, v4, v5
10000b628: ad5a1d04    	ldp	q4, q7, [x8, #0x340]
10000b62c: 3dc177f5    	ldr	q21, [sp, #0x5d0]
10000b630: 4fc492bf    	fmul.2d	v31, v21, v4[0]
10000b634: 4e7fd5df    	fadd.2d	v31, v14, v31
10000b638: 4fc49a6e    	fmul.2d	v14, v19, v4[1]
10000b63c: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000b640: 3dc1e3f3    	ldr	q19, [sp, #0x780]
10000b644: 6e73dc0e    	fmul.2d	v14, v0, v19
10000b648: 4e6ed6ae    	fadd.2d	v14, v21, v14
10000b64c: 4e7fd5d5    	fadd.2d	v21, v14, v31
10000b650: 3d808ff5    	str	q21, [sp, #0x230]
10000b654: 3cd603b3    	ldur	q19, [x29, #-0xa0]
10000b658: 4fc4927f    	fmul.2d	v31, v19, v4[0]
10000b65c: 4e7fd5bf    	fadd.2d	v31, v13, v31
10000b660: 3dc1d7f5    	ldr	q21, [sp, #0x750]
10000b664: 4fc49aad    	fmul.2d	v13, v21, v4[1]
10000b668: 4e6dd7ff    	fadd.2d	v31, v31, v13
10000b66c: 3dc15bf5    	ldr	q21, [sp, #0x560]
10000b670: 6e75dc2d    	fmul.2d	v13, v1, v21
10000b674: 4e6dd66d    	fadd.2d	v13, v19, v13
10000b678: 4e7fd5b5    	fadd.2d	v21, v13, v31
10000b67c: 3d8087f5    	str	q21, [sp, #0x210]
10000b680: 3cd403b3    	ldur	q19, [x29, #-0xc0]
10000b684: 4fc4927f    	fmul.2d	v31, v19, v4[0]
10000b688: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000b68c: 3cda03b5    	ldur	q21, [x29, #-0x60]
10000b690: 4fc49abf    	fmul.2d	v31, v21, v4[1]
10000b694: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000b698: 6e77dc5f    	fmul.2d	v31, v2, v23
10000b69c: 4e7fd67f    	fadd.2d	v31, v19, v31
10000b6a0: 4e66d7e6    	fadd.2d	v6, v31, v6
10000b6a4: 3d8013e6    	str	q6, [sp, #0x40]
10000b6a8: 3dc16bf7    	ldr	q23, [sp, #0x5a0]
10000b6ac: 4fc492e6    	fmul.2d	v6, v23, v4[0]
10000b6b0: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b6b4: 3cd103a6    	ldur	q6, [x29, #-0xf0]
10000b6b8: 4fc498c6    	fmul.2d	v6, v6, v4[1]
10000b6bc: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b6c0: 3dc147e6    	ldr	q6, [sp, #0x510]
10000b6c4: 6e66dc66    	fmul.2d	v6, v3, v6
10000b6c8: 4e66d6e6    	fadd.2d	v6, v23, v6
10000b6cc: 4e65d4c5    	fadd.2d	v5, v6, v5
10000b6d0: 3d8083e5    	str	q5, [sp, #0x200]
10000b6d4: 3dc1cbe5    	ldr	q5, [sp, #0x720]
10000b6d8: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000b6dc: 3dc113f3    	ldr	q19, [sp, #0x440]
10000b6e0: 4fc09a66    	fmul.2d	v6, v19, v0[1]
10000b6e4: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b6e8: 3dc1abe6    	ldr	q6, [sp, #0x6a0]
10000b6ec: 4fc190c6    	fmul.2d	v6, v6, v1[0]
10000b6f0: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b6f4: 3dc17fe6    	ldr	q6, [sp, #0x5f0]
10000b6f8: 4fc198c6    	fmul.2d	v6, v6, v1[1]
10000b6fc: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b700: 3dc197e6    	ldr	q6, [sp, #0x650]
10000b704: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000b708: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b70c: ad795ba6    	ldp	q6, q22, [x29, #-0xe0]
10000b710: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000b714: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b718: 3cd903b5    	ldur	q21, [x29, #-0x70]
10000b71c: 4fc392a6    	fmul.2d	v6, v21, v3[0]
10000b720: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b724: 4fc39ac6    	fmul.2d	v6, v22, v3[1]
10000b728: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b72c: 3dc11ffb    	ldr	q27, [sp, #0x470]
10000b730: 4fc49366    	fmul.2d	v6, v27, v4[0]
10000b734: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b738: 3dc153e6    	ldr	q6, [sp, #0x540]
10000b73c: 4fc498c6    	fmul.2d	v6, v6, v4[1]
10000b740: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b744: 3dc14be6    	ldr	q6, [sp, #0x520]
10000b748: 6e66dc86    	fmul.2d	v6, v4, v6
10000b74c: 4e66d766    	fadd.2d	v6, v27, v6
10000b750: 4e65d4c5    	fadd.2d	v5, v6, v5
10000b754: 3d807be5    	str	q5, [sp, #0x1e0]
10000b758: 3dc1c7e5    	ldr	q5, [sp, #0x710]
10000b75c: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000b760: 3dc133fb    	ldr	q27, [sp, #0x4c0]
10000b764: 4fc09b60    	fmul.2d	v0, v27, v0[1]
10000b768: 4e60d4a0    	fadd.2d	v0, v5, v0
10000b76c: 3dc1afe5    	ldr	q5, [sp, #0x6b0]
10000b770: 4fc190a5    	fmul.2d	v5, v5, v1[0]
10000b774: 4e65d400    	fadd.2d	v0, v0, v5
10000b778: 3dc12fe5    	ldr	q5, [sp, #0x4b0]
10000b77c: 4fc198a1    	fmul.2d	v1, v5, v1[1]
10000b780: 4e61d400    	fadd.2d	v0, v0, v1
10000b784: 4fc29381    	fmul.2d	v1, v28, v2[0]
10000b788: 4ebc1f8f    	mov.16b	v15, v28
10000b78c: 4e61d400    	fadd.2d	v0, v0, v1
10000b790: 3dc1dfe1    	ldr	q1, [sp, #0x770]
10000b794: 4fc29821    	fmul.2d	v1, v1, v2[1]
10000b798: 4e61d400    	fadd.2d	v0, v0, v1
10000b79c: 3cd703a1    	ldur	q1, [x29, #-0x90]
10000b7a0: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000b7a4: 4e61d400    	fadd.2d	v0, v0, v1
10000b7a8: 3dc1b3e1    	ldr	q1, [sp, #0x6c0]
10000b7ac: 4fc39821    	fmul.2d	v1, v1, v3[1]
10000b7b0: 4e61d400    	fadd.2d	v0, v0, v1
10000b7b4: 3dc1c3e2    	ldr	q2, [sp, #0x700]
10000b7b8: 4fc49041    	fmul.2d	v1, v2, v4[0]
10000b7bc: 4e61d400    	fadd.2d	v0, v0, v1
10000b7c0: 3cd803a1    	ldur	q1, [x29, #-0x80]
10000b7c4: 4fc49821    	fmul.2d	v1, v1, v4[1]
10000b7c8: 4e61d400    	fadd.2d	v0, v0, v1
10000b7cc: 3dc167fc    	ldr	q28, [sp, #0x590]
10000b7d0: 6e7cdce1    	fmul.2d	v1, v7, v28
10000b7d4: 4e61d441    	fadd.2d	v1, v2, v1
10000b7d8: 4e61d400    	fadd.2d	v0, v0, v1
10000b7dc: 3d800fe0    	str	q0, [sp, #0x30]
10000b7e0: ad5b0500    	ldp	q0, q1, [x8, #0x360]
10000b7e4: 4fc09222    	fmul.2d	v2, v17, v0[0]
10000b7e8: 3dc10feb    	ldr	q11, [sp, #0x430]
10000b7ec: 4fc09963    	fmul.2d	v3, v11, v0[1]
10000b7f0: 4e63d442    	fadd.2d	v2, v2, v3
10000b7f4: 3dc14ffe    	ldr	q30, [sp, #0x530]
10000b7f8: 4fc193c3    	fmul.2d	v3, v30, v1[0]
10000b7fc: 4e63d442    	fadd.2d	v2, v2, v3
10000b800: 4fc19ba3    	fmul.2d	v3, v29, v1[1]
10000b804: 4e63d444    	fadd.2d	v4, v2, v3
10000b808: 3dc11be2    	ldr	q2, [sp, #0x460]
10000b80c: 4fc09042    	fmul.2d	v2, v2, v0[0]
10000b810: 3dc16ffd    	ldr	q29, [sp, #0x5b0]
10000b814: 4fc09ba3    	fmul.2d	v3, v29, v0[1]
10000b818: 4e63d442    	fadd.2d	v2, v2, v3
10000b81c: 3dc173e3    	ldr	q3, [sp, #0x5c0]
10000b820: 4fc19063    	fmul.2d	v3, v3, v1[0]
10000b824: 4e63d442    	fadd.2d	v2, v2, v3
10000b828: 4fc19b43    	fmul.2d	v3, v26, v1[1]
10000b82c: 4e63d445    	fadd.2d	v5, v2, v3
10000b830: ad5c0d02    	ldp	q2, q3, [x8, #0x380]
10000b834: 3dc15fe6    	ldr	q6, [sp, #0x570]
10000b838: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000b83c: 4e66d484    	fadd.2d	v4, v4, v6
10000b840: 4fc29a06    	fmul.2d	v6, v16, v2[1]
10000b844: 4e66d484    	fadd.2d	v4, v4, v6
10000b848: 3dc1a3e6    	ldr	q6, [sp, #0x680]
10000b84c: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000b850: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b854: 3dc1d3e6    	ldr	q6, [sp, #0x740]
10000b858: 4fc298c6    	fmul.2d	v6, v6, v2[1]
10000b85c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b860: 3dc18be6    	ldr	q6, [sp, #0x620]
10000b864: 4fc090c6    	fmul.2d	v6, v6, v0[0]
10000b868: 3dc17be7    	ldr	q7, [sp, #0x5e0]
10000b86c: 4fc098e7    	fmul.2d	v7, v7, v0[1]
10000b870: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b874: 4fc19187    	fmul.2d	v7, v12, v1[0]
10000b878: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b87c: 4fc19a47    	fmul.2d	v7, v18, v1[1]
10000b880: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b884: 4fc29327    	fmul.2d	v7, v25, v2[0]
10000b888: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b88c: 3dc1cff9    	ldr	q25, [sp, #0x730]
10000b890: 4fc29b27    	fmul.2d	v7, v25, v2[1]
10000b894: 4e67d4c6    	fadd.2d	v6, v6, v7
10000b898: 4fc39147    	fmul.2d	v7, v10, v3[0]
10000b89c: 4e67d484    	fadd.2d	v4, v4, v7
10000b8a0: 3dc1dbe7    	ldr	q7, [sp, #0x760]
10000b8a4: 4fc398e7    	fmul.2d	v7, v7, v3[1]
10000b8a8: 4e67d48e    	fadd.2d	v14, v4, v7
10000b8ac: 4fc39284    	fmul.2d	v4, v20, v3[0]
10000b8b0: 4e64d4a4    	fadd.2d	v4, v5, v4
10000b8b4: 3dc163e5    	ldr	q5, [sp, #0x580]
10000b8b8: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000b8bc: 4e65d48d    	fadd.2d	v13, v4, v5
10000b8c0: 3dc193e4    	ldr	q4, [sp, #0x640]
10000b8c4: 4fc39084    	fmul.2d	v4, v4, v3[0]
10000b8c8: 4e64d4c4    	fadd.2d	v4, v6, v4
10000b8cc: 3dc1b7e5    	ldr	q5, [sp, #0x6d0]
10000b8d0: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000b8d4: 4e65d486    	fadd.2d	v6, v4, v5
10000b8d8: 3dc10be4    	ldr	q4, [sp, #0x420]
10000b8dc: 4fc09084    	fmul.2d	v4, v4, v0[0]
10000b8e0: 3dc127e5    	ldr	q5, [sp, #0x490]
10000b8e4: 4fc098a5    	fmul.2d	v5, v5, v0[1]
10000b8e8: 4e65d484    	fadd.2d	v4, v4, v5
10000b8ec: 4fc19105    	fmul.2d	v5, v8, v1[0]
10000b8f0: 4e65d484    	fadd.2d	v4, v4, v5
10000b8f4: 4fc19925    	fmul.2d	v5, v9, v1[1]
10000b8f8: 4e65d484    	fadd.2d	v4, v4, v5
10000b8fc: 4fc29305    	fmul.2d	v5, v24, v2[0]
10000b900: 4e65d484    	fadd.2d	v4, v4, v5
10000b904: 3cd503a5    	ldur	q5, [x29, #-0xb0]
10000b908: 4fc298a5    	fmul.2d	v5, v5, v2[1]
10000b90c: 4e65d484    	fadd.2d	v4, v4, v5
10000b910: 3dc157e5    	ldr	q5, [sp, #0x550]
10000b914: 4fc390a5    	fmul.2d	v5, v5, v3[0]
10000b918: 4e65d484    	fadd.2d	v4, v4, v5
10000b91c: 3dc187e5    	ldr	q5, [sp, #0x610]
10000b920: 4fc398a5    	fmul.2d	v5, v5, v3[1]
10000b924: 4e65d485    	fadd.2d	v5, v4, v5
10000b928: ad5d1d04    	ldp	q4, q7, [x8, #0x3a0]
10000b92c: 3dc177fa    	ldr	q26, [sp, #0x5d0]
10000b930: 4fc4935f    	fmul.2d	v31, v26, v4[0]
10000b934: 4e7fd5df    	fadd.2d	v31, v14, v31
10000b938: 3cd003b0    	ldur	q16, [x29, #-0x100]
10000b93c: 4fc49a0e    	fmul.2d	v14, v16, v4[1]
10000b940: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000b944: 3dc1e3e8    	ldr	q8, [sp, #0x780]
10000b948: 6e68dc0e    	fmul.2d	v14, v0, v8
10000b94c: 4e6ed60e    	fadd.2d	v14, v16, v14
10000b950: 4e7fd5d0    	fadd.2d	v16, v14, v31
10000b954: 3d800bf0    	str	q16, [sp, #0x20]
10000b958: 3cd603b0    	ldur	q16, [x29, #-0xa0]
10000b95c: 4fc4921f    	fmul.2d	v31, v16, v4[0]
10000b960: 4e7fd5bf    	fadd.2d	v31, v13, v31
10000b964: 3dc1d7f0    	ldr	q16, [sp, #0x750]
10000b968: 4fc49a0d    	fmul.2d	v13, v16, v4[1]
10000b96c: 4e6dd7ff    	fadd.2d	v31, v31, v13
10000b970: 3dc15bf4    	ldr	q20, [sp, #0x560]
10000b974: 6e74dc2d    	fmul.2d	v13, v1, v20
10000b978: 4e6dd60d    	fadd.2d	v13, v16, v13
10000b97c: 4e7fd5b0    	fadd.2d	v16, v13, v31
10000b980: 3d807ff0    	str	q16, [sp, #0x1f0]
10000b984: 3cd403b0    	ldur	q16, [x29, #-0xc0]
10000b988: 4fc4921f    	fmul.2d	v31, v16, v4[0]
10000b98c: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000b990: 3cda03b0    	ldur	q16, [x29, #-0x60]
10000b994: 4fc49a1f    	fmul.2d	v31, v16, v4[1]
10000b998: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000b99c: 3dc19be9    	ldr	q9, [sp, #0x660]
10000b9a0: 6e69dc5f    	fmul.2d	v31, v2, v9
10000b9a4: 4e7fd61f    	fadd.2d	v31, v16, v31
10000b9a8: 4e66d7e6    	fadd.2d	v6, v31, v6
10000b9ac: 3d8073e6    	str	q6, [sp, #0x1c0]
10000b9b0: 4eb71ef8    	mov.16b	v24, v23
10000b9b4: 4fc492e6    	fmul.2d	v6, v23, v4[0]
10000b9b8: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b9bc: 3cd103b0    	ldur	q16, [x29, #-0xf0]
10000b9c0: 4fc49a06    	fmul.2d	v6, v16, v4[1]
10000b9c4: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b9c8: 3dc147f1    	ldr	q17, [sp, #0x510]
10000b9cc: 6e71dc66    	fmul.2d	v6, v3, v17
10000b9d0: 4e66d606    	fadd.2d	v6, v16, v6
10000b9d4: 4e65d4c5    	fadd.2d	v5, v6, v5
10000b9d8: 3d806be5    	str	q5, [sp, #0x1a0]
10000b9dc: 3dc1cbe5    	ldr	q5, [sp, #0x720]
10000b9e0: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000b9e4: 4fc09a66    	fmul.2d	v6, v19, v0[1]
10000b9e8: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b9ec: 3dc1abf0    	ldr	q16, [sp, #0x6a0]
10000b9f0: 4fc19206    	fmul.2d	v6, v16, v1[0]
10000b9f4: 4e66d4a5    	fadd.2d	v5, v5, v6
10000b9f8: 3dc17fe6    	ldr	q6, [sp, #0x5f0]
10000b9fc: 4fc198c6    	fmul.2d	v6, v6, v1[1]
10000ba00: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ba04: 3dc197e6    	ldr	q6, [sp, #0x650]
10000ba08: 4fc290c6    	fmul.2d	v6, v6, v2[0]
10000ba0c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ba10: 3cd203b3    	ldur	q19, [x29, #-0xe0]
10000ba14: 4fc29a66    	fmul.2d	v6, v19, v2[1]
10000ba18: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ba1c: 4fc392a6    	fmul.2d	v6, v21, v3[0]
10000ba20: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ba24: 4fc39ac6    	fmul.2d	v6, v22, v3[1]
10000ba28: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ba2c: 3dc11ff5    	ldr	q21, [sp, #0x470]
10000ba30: 4fc492a6    	fmul.2d	v6, v21, v4[0]
10000ba34: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ba38: 3dc153f2    	ldr	q18, [sp, #0x540]
10000ba3c: 4fc49a46    	fmul.2d	v6, v18, v4[1]
10000ba40: 4e66d4a5    	fadd.2d	v5, v5, v6
10000ba44: 3dc14be6    	ldr	q6, [sp, #0x520]
10000ba48: 6e66dc86    	fmul.2d	v6, v4, v6
10000ba4c: 4e66d646    	fadd.2d	v6, v18, v6
10000ba50: 4e65d4c5    	fadd.2d	v5, v6, v5
10000ba54: 3d8063e5    	str	q5, [sp, #0x180]
10000ba58: 3dc1c7f7    	ldr	q23, [sp, #0x710]
10000ba5c: 4fc092e5    	fmul.2d	v5, v23, v0[0]
10000ba60: 4fc09b60    	fmul.2d	v0, v27, v0[1]
10000ba64: 4e60d4a0    	fadd.2d	v0, v5, v0
10000ba68: 3dc1aff2    	ldr	q18, [sp, #0x6b0]
10000ba6c: 4fc19245    	fmul.2d	v5, v18, v1[0]
10000ba70: 4e65d400    	fadd.2d	v0, v0, v5
10000ba74: 3dc12fe5    	ldr	q5, [sp, #0x4b0]
10000ba78: 4fc198a1    	fmul.2d	v1, v5, v1[1]
10000ba7c: 4e61d400    	fadd.2d	v0, v0, v1
10000ba80: 4fc291e1    	fmul.2d	v1, v15, v2[0]
10000ba84: 4e61d400    	fadd.2d	v0, v0, v1
10000ba88: 3dc1dfef    	ldr	q15, [sp, #0x770]
10000ba8c: 4fc299e1    	fmul.2d	v1, v15, v2[1]
10000ba90: 4e61d400    	fadd.2d	v0, v0, v1
10000ba94: 3cd703a2    	ldur	q2, [x29, #-0x90]
10000ba98: 4fc39041    	fmul.2d	v1, v2, v3[0]
10000ba9c: 4e61d400    	fadd.2d	v0, v0, v1
10000baa0: 3dc1b3f6    	ldr	q22, [sp, #0x6c0]
10000baa4: 4fc39ac1    	fmul.2d	v1, v22, v3[1]
10000baa8: 4e61d400    	fadd.2d	v0, v0, v1
10000baac: 3dc1c3e1    	ldr	q1, [sp, #0x700]
10000bab0: 4fc49021    	fmul.2d	v1, v1, v4[0]
10000bab4: 4e61d400    	fadd.2d	v0, v0, v1
10000bab8: 3cd803a3    	ldur	q3, [x29, #-0x80]
10000babc: 4fc49861    	fmul.2d	v1, v3, v4[1]
10000bac0: 4e61d400    	fadd.2d	v0, v0, v1
10000bac4: 6e7cdce1    	fmul.2d	v1, v7, v28
10000bac8: 4e61d461    	fadd.2d	v1, v3, v1
10000bacc: 4e61d400    	fadd.2d	v0, v0, v1
10000bad0: 3d8007e0    	str	q0, [sp, #0x10]
10000bad4: ad5e0500    	ldp	q0, q1, [x8, #0x3c0]
10000bad8: 3dc1a7e3    	ldr	q3, [sp, #0x690]
10000badc: 4fc09063    	fmul.2d	v3, v3, v0[0]
10000bae0: 4fc09964    	fmul.2d	v4, v11, v0[1]
10000bae4: 4e64d463    	fadd.2d	v3, v3, v4
10000bae8: 3dc33104    	ldr	q4, [x8, #0xcc0]
10000baec: 6e68dc05    	fmul.2d	v5, v0, v8
10000baf0: 4e64d4a6    	fadd.2d	v6, v5, v4
10000baf4: 4fc193c4    	fmul.2d	v4, v30, v1[0]
10000baf8: 4e64d463    	fadd.2d	v3, v3, v4
10000bafc: 3dc12be4    	ldr	q4, [sp, #0x4a0]
10000bb00: 4fc19884    	fmul.2d	v4, v4, v1[1]
10000bb04: 4e64d465    	fadd.2d	v5, v3, v4
10000bb08: 3dc11be3    	ldr	q3, [sp, #0x460]
10000bb0c: 4fc09063    	fmul.2d	v3, v3, v0[0]
10000bb10: 4fc09ba4    	fmul.2d	v4, v29, v0[1]
10000bb14: 4e64d463    	fadd.2d	v3, v3, v4
10000bb18: 3dc173e4    	ldr	q4, [sp, #0x5c0]
10000bb1c: 4fc19084    	fmul.2d	v4, v4, v1[0]
10000bb20: 4e64d463    	fadd.2d	v3, v3, v4
10000bb24: 3dc1bfe4    	ldr	q4, [sp, #0x6f0]
10000bb28: 4fc19884    	fmul.2d	v4, v4, v1[1]
10000bb2c: 4e64d467    	fadd.2d	v7, v3, v4
10000bb30: 3dc33503    	ldr	q3, [x8, #0xcd0]
10000bb34: 6e74dc24    	fmul.2d	v4, v1, v20
10000bb38: 4e63d48d    	fadd.2d	v13, v4, v3
10000bb3c: ad5f1103    	ldp	q3, q4, [x8, #0x3e0]
10000bb40: 3dc15fec    	ldr	q12, [sp, #0x570]
10000bb44: 4fc3919f    	fmul.2d	v31, v12, v3[0]
10000bb48: 4e7fd4a5    	fadd.2d	v5, v5, v31
10000bb4c: 3dc123f4    	ldr	q20, [sp, #0x480]
10000bb50: 4fc39a9f    	fmul.2d	v31, v20, v3[1]
10000bb54: 4e7fd4a5    	fadd.2d	v5, v5, v31
10000bb58: 3dc1a3fb    	ldr	q27, [sp, #0x680]
10000bb5c: 4fc3937f    	fmul.2d	v31, v27, v3[0]
10000bb60: 4e7fd4e7    	fadd.2d	v7, v7, v31
10000bb64: 3dc1d3f4    	ldr	q20, [sp, #0x740]
10000bb68: 4fc39a9f    	fmul.2d	v31, v20, v3[1]
10000bb6c: 4e7fd4e7    	fadd.2d	v7, v7, v31
10000bb70: 3dc18bf4    	ldr	q20, [sp, #0x620]
10000bb74: 4fc0929f    	fmul.2d	v31, v20, v0[0]
10000bb78: 3dc17bf4    	ldr	q20, [sp, #0x5e0]
10000bb7c: 4fc09a8e    	fmul.2d	v14, v20, v0[1]
10000bb80: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000bb84: 3dc13bf4    	ldr	q20, [sp, #0x4e0]
10000bb88: 4fc1928e    	fmul.2d	v14, v20, v1[0]
10000bb8c: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000bb90: 3dc1bbf4    	ldr	q20, [sp, #0x6e0]
10000bb94: 4fc19a8e    	fmul.2d	v14, v20, v1[1]
10000bb98: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000bb9c: 3dc13ff4    	ldr	q20, [sp, #0x4f0]
10000bba0: 4fc3928e    	fmul.2d	v14, v20, v3[0]
10000bba4: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000bba8: 4fc39b2e    	fmul.2d	v14, v25, v3[1]
10000bbac: 4e6ed7ff    	fadd.2d	v31, v31, v14
10000bbb0: 3dc3390e    	ldr	q14, [x8, #0xce0]
10000bbb4: 6e69dc6b    	fmul.2d	v11, v3, v9
10000bbb8: 4e6ed56b    	fadd.2d	v11, v11, v14
10000bbbc: 3dc117f4    	ldr	q20, [sp, #0x450]
10000bbc0: 4fc4928e    	fmul.2d	v14, v20, v4[0]
10000bbc4: 4e6ed4a5    	fadd.2d	v5, v5, v14
10000bbc8: 3dc1dbf4    	ldr	q20, [sp, #0x760]
10000bbcc: 4fc49a8e    	fmul.2d	v14, v20, v4[1]
10000bbd0: 4e6ed4ae    	fadd.2d	v14, v5, v14
10000bbd4: 3dc137e5    	ldr	q5, [sp, #0x4d0]
10000bbd8: 4fc490a5    	fmul.2d	v5, v5, v4[0]
10000bbdc: 4e65d4e5    	fadd.2d	v5, v7, v5
10000bbe0: 3dc163fc    	ldr	q28, [sp, #0x580]
10000bbe4: 4fc49b87    	fmul.2d	v7, v28, v4[1]
10000bbe8: 4e67d4a7    	fadd.2d	v7, v5, v7
10000bbec: 3dc193fe    	ldr	q30, [sp, #0x640]
10000bbf0: 4fc493c5    	fmul.2d	v5, v30, v4[0]
10000bbf4: 4e65d7e5    	fadd.2d	v5, v31, v5
10000bbf8: 3dc1b7f4    	ldr	q20, [sp, #0x6d0]
10000bbfc: 4fc49a9f    	fmul.2d	v31, v20, v4[1]
10000bc00: 4e7fd4bf    	fadd.2d	v31, v5, v31
10000bc04: 3dc10bfd    	ldr	q29, [sp, #0x420]
10000bc08: 4fc093a5    	fmul.2d	v5, v29, v0[0]
10000bc0c: 3dc127f4    	ldr	q20, [sp, #0x490]
10000bc10: 4fc09a8a    	fmul.2d	v10, v20, v0[1]
10000bc14: 4e6ad4a5    	fadd.2d	v5, v5, v10
10000bc18: 3dc143f4    	ldr	q20, [sp, #0x500]
10000bc1c: 4fc1928a    	fmul.2d	v10, v20, v1[0]
10000bc20: 4e6ad4a5    	fadd.2d	v5, v5, v10
10000bc24: 3dc18ff4    	ldr	q20, [sp, #0x630]
10000bc28: 4fc19a8a    	fmul.2d	v10, v20, v1[1]
10000bc2c: 4e6ad4a5    	fadd.2d	v5, v5, v10
10000bc30: 3dc19ff4    	ldr	q20, [sp, #0x670]
10000bc34: 4fc3928a    	fmul.2d	v10, v20, v3[0]
10000bc38: 4e6ad4a5    	fadd.2d	v5, v5, v10
10000bc3c: 3cd503b4    	ldur	q20, [x29, #-0xb0]
10000bc40: 4fc39a8a    	fmul.2d	v10, v20, v3[1]
10000bc44: 4e6ad4a5    	fadd.2d	v5, v5, v10
10000bc48: 3dc157f4    	ldr	q20, [sp, #0x550]
10000bc4c: 4fc4928a    	fmul.2d	v10, v20, v4[0]
10000bc50: 4e6ad4a5    	fadd.2d	v5, v5, v10
10000bc54: 3dc187f9    	ldr	q25, [sp, #0x610]
10000bc58: 4fc49b2a    	fmul.2d	v10, v25, v4[1]
10000bc5c: 4e6ad4aa    	fadd.2d	v10, v5, v10
10000bc60: 3dc33d05    	ldr	q5, [x8, #0xcf0]
10000bc64: 6e71dc89    	fmul.2d	v9, v4, v17
10000bc68: 4e65d529    	fadd.2d	v9, v9, v5
10000bc6c: 3dc10105    	ldr	q5, [x8, #0x400]
10000bc70: 4fc59348    	fmul.2d	v8, v26, v5[0]
10000bc74: 4e68d5c8    	fadd.2d	v8, v14, v8
10000bc78: 3cd003ba    	ldur	q26, [x29, #-0x100]
10000bc7c: 4fc59b4e    	fmul.2d	v14, v26, v5[1]
10000bc80: 4e6ed508    	fadd.2d	v8, v8, v14
10000bc84: 4e66d506    	fadd.2d	v6, v8, v6
10000bc88: 3d8077e6    	str	q6, [sp, #0x1d0]
10000bc8c: 3cd603b1    	ldur	q17, [x29, #-0xa0]
10000bc90: 4fc59226    	fmul.2d	v6, v17, v5[0]
10000bc94: 4e66d4e6    	fadd.2d	v6, v7, v6
10000bc98: 3dc1d7e7    	ldr	q7, [sp, #0x750]
10000bc9c: 4fc598e7    	fmul.2d	v7, v7, v5[1]
10000bca0: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bca4: 4e6dd4c6    	fadd.2d	v6, v6, v13
10000bca8: 3d806fe6    	str	q6, [sp, #0x1b0]
10000bcac: 3cd403ad    	ldur	q13, [x29, #-0xc0]
10000bcb0: 4fc591a6    	fmul.2d	v6, v13, v5[0]
10000bcb4: 4e66d7e6    	fadd.2d	v6, v31, v6
10000bcb8: 3cda03a7    	ldur	q7, [x29, #-0x60]
10000bcbc: 4fc598e7    	fmul.2d	v7, v7, v5[1]
10000bcc0: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bcc4: 4e6bd4c6    	fadd.2d	v6, v6, v11
10000bcc8: 3d8067e6    	str	q6, [sp, #0x190]
10000bccc: 4fc59306    	fmul.2d	v6, v24, v5[0]
10000bcd0: 4e66d546    	fadd.2d	v6, v10, v6
10000bcd4: 3cd103a7    	ldur	q7, [x29, #-0xf0]
10000bcd8: 4fc598e7    	fmul.2d	v7, v7, v5[1]
10000bcdc: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bce0: 4e69d4c6    	fadd.2d	v6, v6, v9
10000bce4: 3d805fe6    	str	q6, [sp, #0x170]
10000bce8: 3dc1cbeb    	ldr	q11, [sp, #0x720]
10000bcec: 4fc09166    	fmul.2d	v6, v11, v0[0]
10000bcf0: 3dc113ea    	ldr	q10, [sp, #0x440]
10000bcf4: 4fc09947    	fmul.2d	v7, v10, v0[1]
10000bcf8: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bcfc: 4fc19207    	fmul.2d	v7, v16, v1[0]
10000bd00: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bd04: 3dc17ff0    	ldr	q16, [sp, #0x5f0]
10000bd08: 4fc19a07    	fmul.2d	v7, v16, v1[1]
10000bd0c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bd10: 3dc197ee    	ldr	q14, [sp, #0x650]
10000bd14: 4fc391c7    	fmul.2d	v7, v14, v3[0]
10000bd18: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bd1c: 4fc39a67    	fmul.2d	v7, v19, v3[1]
10000bd20: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bd24: 3cd903a7    	ldur	q7, [x29, #-0x70]
10000bd28: 4fc490e7    	fmul.2d	v7, v7, v4[0]
10000bd2c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bd30: 3cd303a7    	ldur	q7, [x29, #-0xd0]
10000bd34: 4fc498e7    	fmul.2d	v7, v7, v4[1]
10000bd38: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bd3c: 4fc592a7    	fmul.2d	v7, v21, v5[0]
10000bd40: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bd44: 3dc153e7    	ldr	q7, [sp, #0x540]
10000bd48: 4fc598e7    	fmul.2d	v7, v7, v5[1]
10000bd4c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bd50: 3dc34107    	ldr	q7, [x8, #0xd00]
10000bd54: 3dc14bf3    	ldr	q19, [sp, #0x520]
10000bd58: 6e73dcbf    	fmul.2d	v31, v5, v19
10000bd5c: 4e67d7e7    	fadd.2d	v7, v31, v7
10000bd60: 4e67d4c6    	fadd.2d	v6, v6, v7
10000bd64: 3d805be6    	str	q6, [sp, #0x160]
10000bd68: 4fc092e6    	fmul.2d	v6, v23, v0[0]
10000bd6c: 3dc133e7    	ldr	q7, [sp, #0x4c0]
10000bd70: 4fc098e0    	fmul.2d	v0, v7, v0[1]
10000bd74: 4e60d4c0    	fadd.2d	v0, v6, v0
10000bd78: 4fc19246    	fmul.2d	v6, v18, v1[0]
10000bd7c: 4e66d400    	fadd.2d	v0, v0, v6
10000bd80: 3dc12ff5    	ldr	q21, [sp, #0x4b0]
10000bd84: 4fc19aa1    	fmul.2d	v1, v21, v1[1]
10000bd88: 4e61d400    	fadd.2d	v0, v0, v1
10000bd8c: 3dc183e1    	ldr	q1, [sp, #0x600]
10000bd90: 4fc39021    	fmul.2d	v1, v1, v3[0]
10000bd94: 4e61d400    	fadd.2d	v0, v0, v1
10000bd98: 4fc399e1    	fmul.2d	v1, v15, v3[1]
10000bd9c: 4e61d400    	fadd.2d	v0, v0, v1
10000bda0: 4fc49041    	fmul.2d	v1, v2, v4[0]
10000bda4: 4e61d400    	fadd.2d	v0, v0, v1
10000bda8: 4fc49ac1    	fmul.2d	v1, v22, v4[1]
10000bdac: 4e61d400    	fadd.2d	v0, v0, v1
10000bdb0: 3dc1c3ef    	ldr	q15, [sp, #0x700]
10000bdb4: 4fc591e1    	fmul.2d	v1, v15, v5[0]
10000bdb8: 4e61d400    	fadd.2d	v0, v0, v1
10000bdbc: 3cd803a1    	ldur	q1, [x29, #-0x80]
10000bdc0: 4fc59821    	fmul.2d	v1, v1, v5[1]
10000bdc4: 4e61d400    	fadd.2d	v0, v0, v1
10000bdc8: 3dc10501    	ldr	q1, [x8, #0x410]
10000bdcc: 3dc167e2    	ldr	q2, [sp, #0x590]
10000bdd0: 6e62dc21    	fmul.2d	v1, v1, v2
10000bdd4: 3dc34503    	ldr	q3, [x8, #0xd10]
10000bdd8: 4e61d461    	fadd.2d	v1, v3, v1
10000bddc: 4e61d400    	fadd.2d	v0, v0, v1
10000bde0: 3d8003e0    	str	q0, [sp]
10000bde4: 3dc10903    	ldr	q3, [x8, #0x420]
10000bde8: 3dc1a7e0    	ldr	q0, [sp, #0x690]
10000bdec: 4fc39000    	fmul.2d	v0, v0, v3[0]
10000bdf0: 3dc10fe1    	ldr	q1, [sp, #0x430]
10000bdf4: 4fc39821    	fmul.2d	v1, v1, v3[1]
10000bdf8: 4e61d404    	fadd.2d	v4, v0, v1
10000bdfc: 3dc1e3e0    	ldr	q0, [sp, #0x780]
10000be00: 6e60dc60    	fmul.2d	v0, v3, v0
10000be04: 3dc34901    	ldr	q1, [x8, #0xd20]
10000be08: 4e61d401    	fadd.2d	v1, v0, v1
10000be0c: 3dc10d00    	ldr	q0, [x8, #0x430]
10000be10: 3dc14fe5    	ldr	q5, [sp, #0x530]
10000be14: 4fc090a5    	fmul.2d	v5, v5, v0[0]
10000be18: 4e65d484    	fadd.2d	v4, v4, v5
10000be1c: 3dc12be5    	ldr	q5, [sp, #0x4a0]
10000be20: 4fc098a5    	fmul.2d	v5, v5, v0[1]
10000be24: 4e65d485    	fadd.2d	v5, v4, v5
10000be28: 3dc11be4    	ldr	q4, [sp, #0x460]
10000be2c: 4fc39084    	fmul.2d	v4, v4, v3[0]
10000be30: 3dc16fe6    	ldr	q6, [sp, #0x5b0]
10000be34: 4fc398c6    	fmul.2d	v6, v6, v3[1]
10000be38: 4e66d484    	fadd.2d	v4, v4, v6
10000be3c: 3dc173e6    	ldr	q6, [sp, #0x5c0]
10000be40: 4fc090c6    	fmul.2d	v6, v6, v0[0]
10000be44: 4e66d484    	fadd.2d	v4, v4, v6
10000be48: 3dc1bfe6    	ldr	q6, [sp, #0x6f0]
10000be4c: 4fc098c6    	fmul.2d	v6, v6, v0[1]
10000be50: 4e66d486    	fadd.2d	v6, v4, v6
10000be54: 3dc15be4    	ldr	q4, [sp, #0x560]
10000be58: 6e64dc04    	fmul.2d	v4, v0, v4
10000be5c: 3dc34d07    	ldr	q7, [x8, #0xd30]
10000be60: 4e67d484    	fadd.2d	v4, v4, v7
10000be64: 3dc11119    	ldr	q25, [x8, #0x440]
10000be68: 4fd99187    	fmul.2d	v7, v12, v25[0]
10000be6c: 4e67d4a5    	fadd.2d	v5, v5, v7
10000be70: 3dc123e7    	ldr	q7, [sp, #0x480]
10000be74: 4fd998e7    	fmul.2d	v7, v7, v25[1]
10000be78: 4e67d4a5    	fadd.2d	v5, v5, v7
10000be7c: 4fd99367    	fmul.2d	v7, v27, v25[0]
10000be80: 4e67d4c6    	fadd.2d	v6, v6, v7
10000be84: 3dc1d3e7    	ldr	q7, [sp, #0x740]
10000be88: 4fd998e7    	fmul.2d	v7, v7, v25[1]
10000be8c: 4e67d4c6    	fadd.2d	v6, v6, v7
10000be90: 3dc18be7    	ldr	q7, [sp, #0x620]
10000be94: 4fc390e7    	fmul.2d	v7, v7, v3[0]
10000be98: 3dc17bf2    	ldr	q18, [sp, #0x5e0]
10000be9c: 4fc39a58    	fmul.2d	v24, v18, v3[1]
10000bea0: 4e78d4e7    	fadd.2d	v7, v7, v24
10000bea4: 3dc13bf2    	ldr	q18, [sp, #0x4e0]
10000bea8: 4fc09258    	fmul.2d	v24, v18, v0[0]
10000beac: 4e78d4e7    	fadd.2d	v7, v7, v24
10000beb0: 3dc1bbf2    	ldr	q18, [sp, #0x6e0]
10000beb4: 4fc09a58    	fmul.2d	v24, v18, v0[1]
10000beb8: 4e78d4e7    	fadd.2d	v7, v7, v24
10000bebc: 3dc13ff2    	ldr	q18, [sp, #0x4f0]
10000bec0: 4fd99258    	fmul.2d	v24, v18, v25[0]
10000bec4: 4e78d4e7    	fadd.2d	v7, v7, v24
10000bec8: 3dc1cff2    	ldr	q18, [sp, #0x730]
10000becc: 4fd99a58    	fmul.2d	v24, v18, v25[1]
10000bed0: 4e78d4e7    	fadd.2d	v7, v7, v24
10000bed4: 3dc19bf2    	ldr	q18, [sp, #0x660]
10000bed8: 6e72df38    	fmul.2d	v24, v25, v18
10000bedc: 3dc3511f    	ldr	q31, [x8, #0xd40]
10000bee0: 4e7fd718    	fadd.2d	v24, v24, v31
10000bee4: 3dc1150c    	ldr	q12, [x8, #0x450]
10000bee8: 3dc117f2    	ldr	q18, [sp, #0x450]
10000beec: 4fcc925f    	fmul.2d	v31, v18, v12[0]
10000bef0: 4e7fd4a5    	fadd.2d	v5, v5, v31
10000bef4: 3dc1dbf2    	ldr	q18, [sp, #0x760]
10000bef8: 4fcc9a5f    	fmul.2d	v31, v18, v12[1]
10000befc: 4e7fd4bf    	fadd.2d	v31, v5, v31
10000bf00: 3dc137e5    	ldr	q5, [sp, #0x4d0]
10000bf04: 4fcc90a5    	fmul.2d	v5, v5, v12[0]
10000bf08: 4e65d4c5    	fadd.2d	v5, v6, v5
10000bf0c: 4fcc9b86    	fmul.2d	v6, v28, v12[1]
10000bf10: 4e66d4a8    	fadd.2d	v8, v5, v6
10000bf14: 4fcc93c5    	fmul.2d	v5, v30, v12[0]
10000bf18: 4e65d4e5    	fadd.2d	v5, v7, v5
10000bf1c: 3dc1b7e6    	ldr	q6, [sp, #0x6d0]
10000bf20: 4fcc98c6    	fmul.2d	v6, v6, v12[1]
10000bf24: 4e66d4a7    	fadd.2d	v7, v5, v6
10000bf28: 4fc393a5    	fmul.2d	v5, v29, v3[0]
10000bf2c: 3dc127e6    	ldr	q6, [sp, #0x490]
10000bf30: 4fc398c6    	fmul.2d	v6, v6, v3[1]
10000bf34: 4e66d4a5    	fadd.2d	v5, v5, v6
10000bf38: 3dc143e6    	ldr	q6, [sp, #0x500]
10000bf3c: 4fc090c6    	fmul.2d	v6, v6, v0[0]
10000bf40: 4e66d4a5    	fadd.2d	v5, v5, v6
10000bf44: 3dc18fe6    	ldr	q6, [sp, #0x630]
10000bf48: 4fc098c6    	fmul.2d	v6, v6, v0[1]
10000bf4c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000bf50: 3dc19fe6    	ldr	q6, [sp, #0x670]
10000bf54: 4fd990c6    	fmul.2d	v6, v6, v25[0]
10000bf58: 4e66d4a5    	fadd.2d	v5, v5, v6
10000bf5c: 3cd503a6    	ldur	q6, [x29, #-0xb0]
10000bf60: 4fd998c6    	fmul.2d	v6, v6, v25[1]
10000bf64: 4e66d4a5    	fadd.2d	v5, v5, v6
10000bf68: 4fcc9286    	fmul.2d	v6, v20, v12[0]
10000bf6c: 4e66d4a5    	fadd.2d	v5, v5, v6
10000bf70: 3dc187e6    	ldr	q6, [sp, #0x610]
10000bf74: 4fcc98c6    	fmul.2d	v6, v6, v12[1]
10000bf78: 4e66d4b7    	fadd.2d	v23, v5, v6
10000bf7c: 3dc147e5    	ldr	q5, [sp, #0x510]
10000bf80: 6e65dd85    	fmul.2d	v5, v12, v5
10000bf84: 3dc023fc    	ldr	q28, [sp, #0x80]
10000bf88: 3dc35506    	ldr	q6, [x8, #0xd50]
10000bf8c: 4e66d4a9    	fadd.2d	v9, v5, v6
10000bf90: 3dc11905    	ldr	q5, [x8, #0x460]
10000bf94: 3dc177e6    	ldr	q6, [sp, #0x5d0]
10000bf98: 4fc590c6    	fmul.2d	v6, v6, v5[0]
10000bf9c: 4e66d7e6    	fadd.2d	v6, v31, v6
10000bfa0: 4fc59b5f    	fmul.2d	v31, v26, v5[1]
10000bfa4: 4e7fd4c6    	fadd.2d	v6, v6, v31
10000bfa8: 4e61d4d4    	fadd.2d	v20, v6, v1
10000bfac: 4fc59221    	fmul.2d	v1, v17, v5[0]
10000bfb0: 4e61d501    	fadd.2d	v1, v8, v1
10000bfb4: 3dc04be8    	ldr	q8, [sp, #0x120]
10000bfb8: 3dc1d7e6    	ldr	q6, [sp, #0x750]
10000bfbc: 4fc598df    	fmul.2d	v31, v6, v5[1]
10000bfc0: 4e7fd421    	fadd.2d	v1, v1, v31
10000bfc4: 4e64d421    	fadd.2d	v1, v1, v4
10000bfc8: 3c9603a1    	stur	q1, [x29, #-0xa0]
10000bfcc: 4fc591a1    	fmul.2d	v1, v13, v5[0]
10000bfd0: 4e61d4e1    	fadd.2d	v1, v7, v1
10000bfd4: 3cda03a4    	ldur	q4, [x29, #-0x60]
10000bfd8: 4fc59887    	fmul.2d	v7, v4, v5[1]
10000bfdc: 4e67d421    	fadd.2d	v1, v1, v7
10000bfe0: 4e78d438    	fadd.2d	v24, v1, v24
10000bfe4: 3dc16be1    	ldr	q1, [sp, #0x5a0]
10000bfe8: 4fc59021    	fmul.2d	v1, v1, v5[0]
10000bfec: 4e61d6e1    	fadd.2d	v1, v23, v1
10000bff0: 3dc04ff7    	ldr	q23, [sp, #0x130]
10000bff4: 3cd103a4    	ldur	q4, [x29, #-0xf0]
10000bff8: 4fc59887    	fmul.2d	v7, v4, v5[1]
10000bffc: 4e67d421    	fadd.2d	v1, v1, v7
10000c000: 4e69d43f    	fadd.2d	v31, v1, v9
10000c004: 4fc39161    	fmul.2d	v1, v11, v3[0]
10000c008: 4fc39947    	fmul.2d	v7, v10, v3[1]
10000c00c: 4e67d421    	fadd.2d	v1, v1, v7
10000c010: 3dc1abe4    	ldr	q4, [sp, #0x6a0]
10000c014: 4fc09087    	fmul.2d	v7, v4, v0[0]
10000c018: 3dc017ea    	ldr	q10, [sp, #0x50]
10000c01c: 4e67d421    	fadd.2d	v1, v1, v7
10000c020: 4fc09a07    	fmul.2d	v7, v16, v0[1]
10000c024: 4e67d421    	fadd.2d	v1, v1, v7
10000c028: 4fd991c7    	fmul.2d	v7, v14, v25[0]
10000c02c: 4e67d421    	fadd.2d	v1, v1, v7
10000c030: 3cd203a4    	ldur	q4, [x29, #-0xe0]
10000c034: 4fd99887    	fmul.2d	v7, v4, v25[1]
10000c038: 3dc00ff0    	ldr	q16, [sp, #0x30]
10000c03c: 4e67d421    	fadd.2d	v1, v1, v7
10000c040: 3cd903a4    	ldur	q4, [x29, #-0x70]
10000c044: 4fcc9087    	fmul.2d	v7, v4, v12[0]
10000c048: 4e67d421    	fadd.2d	v1, v1, v7
10000c04c: 3cd303a4    	ldur	q4, [x29, #-0xd0]
10000c050: 4fcc9887    	fmul.2d	v7, v4, v12[1]
10000c054: 4e67d421    	fadd.2d	v1, v1, v7
10000c058: 3dc11fe4    	ldr	q4, [sp, #0x470]
10000c05c: 4fc59087    	fmul.2d	v7, v4, v5[0]
10000c060: ad482fe4    	ldp	q4, q11, [sp, #0x100]
10000c064: 4e67d421    	fadd.2d	v1, v1, v7
10000c068: 3dc153e6    	ldr	q6, [sp, #0x540]
10000c06c: 4fc598c7    	fmul.2d	v7, v6, v5[1]
10000c070: 3dc01ff2    	ldr	q18, [sp, #0x70]
10000c074: 4e67d421    	fadd.2d	v1, v1, v7
10000c078: 6e73dca7    	fmul.2d	v7, v5, v19
10000c07c: 3dc35916    	ldr	q22, [x8, #0xd60]
10000c080: 4e76d4e7    	fadd.2d	v7, v7, v22
10000c084: 3dc03bf6    	ldr	q22, [sp, #0xe0]
10000c088: 4e67d421    	fadd.2d	v1, v1, v7
10000c08c: 3dc1c7e6    	ldr	q6, [sp, #0x710]
10000c090: 4fc390c7    	fmul.2d	v7, v6, v3[0]
10000c094: 3dc133e6    	ldr	q6, [sp, #0x4c0]
10000c098: 4fc398c3    	fmul.2d	v3, v6, v3[1]
10000c09c: ad4a3bfb    	ldp	q27, q14, [sp, #0x140]
10000c0a0: 4e63d4e3    	fadd.2d	v3, v7, v3
10000c0a4: 3dc1afe6    	ldr	q6, [sp, #0x6b0]
10000c0a8: 4fc090c7    	fmul.2d	v7, v6, v0[0]
10000c0ac: ad459be9    	ldp	q9, q6, [sp, #0xb0]
10000c0b0: 4e67d463    	fadd.2d	v3, v3, v7
10000c0b4: ad44fbe7    	ldp	q7, q30, [sp, #0x90]
10000c0b8: 4fc09aa0    	fmul.2d	v0, v21, v0[1]
10000c0bc: 4e60d460    	fadd.2d	v0, v3, v0
10000c0c0: 3dc183e3    	ldr	q3, [sp, #0x600]
10000c0c4: 4fd99063    	fmul.2d	v3, v3, v25[0]
10000c0c8: 4e63d400    	fadd.2d	v0, v0, v3
10000c0cc: 3dc1dfe3    	ldr	q3, [sp, #0x770]
10000c0d0: 4fd99863    	fmul.2d	v3, v3, v25[1]
10000c0d4: 3dc013f9    	ldr	q25, [sp, #0x40]
10000c0d8: 4e63d400    	fadd.2d	v0, v0, v3
10000c0dc: 3cd703a3    	ldur	q3, [x29, #-0x90]
10000c0e0: 4fcc9063    	fmul.2d	v3, v3, v12[0]
10000c0e4: 4e63d400    	fadd.2d	v0, v0, v3
10000c0e8: 3dc1b3e3    	ldr	q3, [sp, #0x6c0]
10000c0ec: 4fcc9863    	fmul.2d	v3, v3, v12[1]
10000c0f0: 3dc037ec    	ldr	q12, [sp, #0xd0]
10000c0f4: 3dc03ffd    	ldr	q29, [sp, #0xf0]
10000c0f8: 4e63d400    	fadd.2d	v0, v0, v3
10000c0fc: 4fc591e3    	fmul.2d	v3, v15, v5[0]
10000c100: ad4047ef    	ldp	q15, q17, [sp]
10000c104: 4e63d400    	fadd.2d	v0, v0, v3
10000c108: 3cd803a3    	ldur	q3, [x29, #-0x80]
10000c10c: 4fc59863    	fmul.2d	v3, v3, v5[1]
10000c110: 3dc00bed    	ldr	q13, [sp, #0x20]
10000c114: 3dc01bfa    	ldr	q26, [sp, #0x60]
10000c118: 4e63d400    	fadd.2d	v0, v0, v3
10000c11c: 3dc11d03    	ldr	q3, [x8, #0x470]
10000c120: 6e62dc63    	fmul.2d	v3, v3, v2
10000c124: 3dc35d05    	ldr	q5, [x8, #0xd70]
10000c128: 4e63d4a3    	fadd.2d	v3, v5, v3
10000c12c: 4e63d403    	fadd.2d	v3, v0, v3
10000c130: 1400013c    	b	0x10000c620 <_bench_primitives.smulAddSemul3_12KnownTraces+0x2ad8>
10000c134: 3dc24102    	ldr	q2, [x8, #0x900]
10000c138: 90000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000c13c: 3dc17920    	ldr	q0, [x9, #0x5e0]
10000c140: ad400503    	ldp	q3, q1, [x8]
10000c144: 6e60dc63    	fmul.2d	v3, v3, v0
10000c148: 4e63d442    	fadd.2d	v2, v2, v3
10000c14c: 3d8103e2    	str	q2, [sp, #0x400]
10000c150: 3dc25903    	ldr	q3, [x8, #0x960]
10000c154: ad430904    	ldp	q4, q2, [x8, #0x60]
10000c158: 6e60dc84    	fmul.2d	v4, v4, v0
10000c15c: 4e64d463    	fadd.2d	v3, v3, v4
10000c160: 3d80efe3    	str	q3, [sp, #0x3b0]
10000c164: 3dc27104    	ldr	q4, [x8, #0x9c0]
10000c168: ad460d05    	ldp	q5, q3, [x8, #0xc0]
10000c16c: 6e60dca5    	fmul.2d	v5, v5, v0
10000c170: 4e65d484    	fadd.2d	v4, v4, v5
10000c174: 3d8107e4    	str	q4, [sp, #0x410]
10000c178: 3dc28905    	ldr	q5, [x8, #0xa20]
10000c17c: ad491106    	ldp	q6, q4, [x8, #0x120]
10000c180: 6e60dcc6    	fmul.2d	v6, v6, v0
10000c184: 4e66d4a5    	fadd.2d	v5, v5, v6
10000c188: 3d80fbe5    	str	q5, [sp, #0x3e0]
10000c18c: 3dc2a106    	ldr	q6, [x8, #0xa80]
10000c190: ad4c1507    	ldp	q7, q5, [x8, #0x180]
10000c194: 6e60dce7    	fmul.2d	v7, v7, v0
10000c198: 4e67d4c6    	fadd.2d	v6, v6, v7
10000c19c: 3d80ebe6    	str	q6, [sp, #0x3a0]
10000c1a0: 3dc2b906    	ldr	q6, [x8, #0xae0]
10000c1a4: ad4f1d10    	ldp	q16, q7, [x8, #0x1e0]
10000c1a8: 6e60de10    	fmul.2d	v16, v16, v0
10000c1ac: 4e70d4c6    	fadd.2d	v6, v6, v16
10000c1b0: 3d80d7e6    	str	q6, [sp, #0x350]
10000c1b4: 3dc2d106    	ldr	q6, [x8, #0xb40]
10000c1b8: ad524510    	ldp	q16, q17, [x8, #0x240]
10000c1bc: 6e60de10    	fmul.2d	v16, v16, v0
10000c1c0: 4e70d4c6    	fadd.2d	v6, v6, v16
10000c1c4: 3d80bbe6    	str	q6, [sp, #0x2e0]
10000c1c8: 3dc2e906    	ldr	q6, [x8, #0xba0]
10000c1cc: ad554910    	ldp	q16, q18, [x8, #0x2a0]
10000c1d0: 6e60de10    	fmul.2d	v16, v16, v0
10000c1d4: 4e70d4c6    	fadd.2d	v6, v6, v16
10000c1d8: 3d80a7e6    	str	q6, [sp, #0x290]
10000c1dc: 3dc30106    	ldr	q6, [x8, #0xc00]
10000c1e0: ad584d10    	ldp	q16, q19, [x8, #0x300]
10000c1e4: 6e60de10    	fmul.2d	v16, v16, v0
10000c1e8: 4e70d4c6    	fadd.2d	v6, v6, v16
10000c1ec: 3d808fe6    	str	q6, [sp, #0x230]
10000c1f0: 3dc31906    	ldr	q6, [x8, #0xc60]
10000c1f4: ad5b5110    	ldp	q16, q20, [x8, #0x360]
10000c1f8: 6e60de10    	fmul.2d	v16, v16, v0
10000c1fc: 4e70d4cd    	fadd.2d	v13, v6, v16
10000c200: 3dc33106    	ldr	q6, [x8, #0xcc0]
10000c204: ad5e5510    	ldp	q16, q21, [x8, #0x3c0]
10000c208: 6e60de10    	fmul.2d	v16, v16, v0
10000c20c: 4e70d4c6    	fadd.2d	v6, v6, v16
10000c210: 3d8077e6    	str	q6, [sp, #0x1d0]
10000c214: 3dc34906    	ldr	q6, [x8, #0xd20]
10000c218: 3dc10910    	ldr	q16, [x8, #0x420]
10000c21c: 6e60de00    	fmul.2d	v0, v16, v0
10000c220: 4e60d4c0    	fadd.2d	v0, v6, v0
10000c224: 3c9a03a0    	stur	q0, [x29, #-0x60]
10000c228: 3dc24500    	ldr	q0, [x8, #0x910]
10000c22c: 90000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000c230: 3dc17d30    	ldr	q16, [x9, #0x5f0]
10000c234: 6e70dc21    	fmul.2d	v1, v1, v16
10000c238: 4e61d40e    	fadd.2d	v14, v0, v1
10000c23c: 3dc25d00    	ldr	q0, [x8, #0x970]
10000c240: 6e70dc41    	fmul.2d	v1, v2, v16
10000c244: 4e61d40b    	fadd.2d	v11, v0, v1
10000c248: 3dc27500    	ldr	q0, [x8, #0x9d0]
10000c24c: 6e70dc61    	fmul.2d	v1, v3, v16
10000c250: 4e61d406    	fadd.2d	v6, v0, v1
10000c254: 3dc28d00    	ldr	q0, [x8, #0xa30]
10000c258: 6e70dc81    	fmul.2d	v1, v4, v16
10000c25c: 4e61d409    	fadd.2d	v9, v0, v1
10000c260: 3dc2a500    	ldr	q0, [x8, #0xa90]
10000c264: 6e70dca1    	fmul.2d	v1, v5, v16
10000c268: 4e61d400    	fadd.2d	v0, v0, v1
10000c26c: 3d80e3e0    	str	q0, [sp, #0x380]
10000c270: 3dc2bd00    	ldr	q0, [x8, #0xaf0]
10000c274: 6e70dce1    	fmul.2d	v1, v7, v16
10000c278: 4e61d400    	fadd.2d	v0, v0, v1
10000c27c: 3d80cfe0    	str	q0, [sp, #0x330]
10000c280: 3dc2d500    	ldr	q0, [x8, #0xb50]
10000c284: 6e70de21    	fmul.2d	v1, v17, v16
10000c288: 4e61d400    	fadd.2d	v0, v0, v1
10000c28c: 3d80b3e0    	str	q0, [sp, #0x2c0]
10000c290: 3dc2ed00    	ldr	q0, [x8, #0xbb0]
10000c294: 6e70de41    	fmul.2d	v1, v18, v16
10000c298: 4e61d400    	fadd.2d	v0, v0, v1
10000c29c: 3d809fe0    	str	q0, [sp, #0x270]
10000c2a0: 3dc30500    	ldr	q0, [x8, #0xc10]
10000c2a4: 6e70de61    	fmul.2d	v1, v19, v16
10000c2a8: 4e61d400    	fadd.2d	v0, v0, v1
10000c2ac: 3d8087e0    	str	q0, [sp, #0x210]
10000c2b0: 3dc31d00    	ldr	q0, [x8, #0xc70]
10000c2b4: 6e70de81    	fmul.2d	v1, v20, v16
10000c2b8: 4e61d400    	fadd.2d	v0, v0, v1
10000c2bc: 3d807fe0    	str	q0, [sp, #0x1f0]
10000c2c0: 3dc33500    	ldr	q0, [x8, #0xcd0]
10000c2c4: 6e70dea1    	fmul.2d	v1, v21, v16
10000c2c8: 4e61d400    	fadd.2d	v0, v0, v1
10000c2cc: 3d806fe0    	str	q0, [sp, #0x1b0]
10000c2d0: 3dc34d00    	ldr	q0, [x8, #0xd30]
10000c2d4: 3dc10d01    	ldr	q1, [x8, #0x430]
10000c2d8: 6e70dc21    	fmul.2d	v1, v1, v16
10000c2dc: 4e61d400    	fadd.2d	v0, v0, v1
10000c2e0: 3c9603a0    	stur	q0, [x29, #-0xa0]
10000c2e4: 3dc24902    	ldr	q2, [x8, #0x920]
10000c2e8: 90000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000c2ec: 3dc18120    	ldr	q0, [x9, #0x600]
10000c2f0: ad410503    	ldp	q3, q1, [x8, #0x20]
10000c2f4: 6e60dc63    	fmul.2d	v3, v3, v0
10000c2f8: 4e63d45b    	fadd.2d	v27, v2, v3
10000c2fc: 3dc26103    	ldr	q3, [x8, #0x980]
10000c300: ad440905    	ldp	q5, q2, [x8, #0x80]
10000c304: 6e60dca5    	fmul.2d	v5, v5, v0
10000c308: 4e65d464    	fadd.2d	v4, v3, v5
10000c30c: 3dc27905    	ldr	q5, [x8, #0x9e0]
10000c310: ad470d07    	ldp	q7, q3, [x8, #0xe0]
10000c314: 6e60dce7    	fmul.2d	v7, v7, v0
10000c318: 4e67d4a5    	fadd.2d	v5, v5, v7
10000c31c: 3d80c7e5    	str	q5, [sp, #0x310]
10000c320: ad4a1507    	ldp	q7, q5, [x8, #0x140]
10000c324: 6e60dce7    	fmul.2d	v7, v7, v0
10000c328: 3dc29110    	ldr	q16, [x8, #0xa40]
10000c32c: 4e67d607    	fadd.2d	v7, v16, v7
10000c330: 3d80f3e7    	str	q7, [sp, #0x3c0]
10000c334: ad4d1d10    	ldp	q16, q7, [x8, #0x1a0]
10000c338: 6e60de10    	fmul.2d	v16, v16, v0
10000c33c: 3dc2a911    	ldr	q17, [x8, #0xaa0]
10000c340: 4e70d630    	fadd.2d	v16, v17, v16
10000c344: 3d80dbf0    	str	q16, [sp, #0x360]
10000c348: ad504111    	ldp	q17, q16, [x8, #0x200]
10000c34c: 6e60de31    	fmul.2d	v17, v17, v0
10000c350: 3dc2c112    	ldr	q18, [x8, #0xb00]
10000c354: 4e71d651    	fadd.2d	v17, v18, v17
10000c358: 3d80bff1    	str	q17, [sp, #0x2f0]
10000c35c: ad534911    	ldp	q17, q18, [x8, #0x260]
10000c360: 6e60de31    	fmul.2d	v17, v17, v0
10000c364: 3dc2d913    	ldr	q19, [x8, #0xb60]
10000c368: 4e71d671    	fadd.2d	v17, v19, v17
10000c36c: 3d80abf1    	str	q17, [sp, #0x2a0]
10000c370: ad564d11    	ldp	q17, q19, [x8, #0x2c0]
10000c374: 6e60de31    	fmul.2d	v17, v17, v0
10000c378: 3dc2f114    	ldr	q20, [x8, #0xbc0]
10000c37c: 4e71d691    	fadd.2d	v17, v20, v17
10000c380: 3d8097f1    	str	q17, [sp, #0x250]
10000c384: ad595111    	ldp	q17, q20, [x8, #0x320]
10000c388: 6e60de31    	fmul.2d	v17, v17, v0
10000c38c: 3dc30915    	ldr	q21, [x8, #0xc20]
10000c390: 4e71d6b9    	fadd.2d	v25, v21, v17
10000c394: ad5c5511    	ldp	q17, q21, [x8, #0x380]
10000c398: 6e60de31    	fmul.2d	v17, v17, v0
10000c39c: 3dc32116    	ldr	q22, [x8, #0xc80]
10000c3a0: 4e71d6d1    	fadd.2d	v17, v22, v17
10000c3a4: 3d8073f1    	str	q17, [sp, #0x1c0]
10000c3a8: ad5f5911    	ldp	q17, q22, [x8, #0x3e0]
10000c3ac: 6e60de31    	fmul.2d	v17, v17, v0
10000c3b0: 3dc33917    	ldr	q23, [x8, #0xce0]
10000c3b4: 4e71d6f1    	fadd.2d	v17, v23, v17
10000c3b8: 3d8067f1    	str	q17, [sp, #0x190]
10000c3bc: 3dc11111    	ldr	q17, [x8, #0x440]
10000c3c0: 6e60de20    	fmul.2d	v0, v17, v0
10000c3c4: 3dc35111    	ldr	q17, [x8, #0xd40]
10000c3c8: 4e60d638    	fadd.2d	v24, v17, v0
10000c3cc: 90000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000c3d0: 3dc18520    	ldr	q0, [x9, #0x610]
10000c3d4: 6e60dc21    	fmul.2d	v1, v1, v0
10000c3d8: 3dc24d11    	ldr	q17, [x8, #0x930]
10000c3dc: 4e61d637    	fadd.2d	v23, v17, v1
10000c3e0: 6e60dc41    	fmul.2d	v1, v2, v0
10000c3e4: 3dc26502    	ldr	q2, [x8, #0x990]
10000c3e8: 4e61d441    	fadd.2d	v1, v2, v1
10000c3ec: 3d80ffe1    	str	q1, [sp, #0x3f0]
10000c3f0: 6e60dc61    	fmul.2d	v1, v3, v0
10000c3f4: 3dc27d02    	ldr	q2, [x8, #0x9f0]
10000c3f8: 4e61d441    	fadd.2d	v1, v2, v1
10000c3fc: 3d80cbe1    	str	q1, [sp, #0x320]
10000c400: 6e60dca1    	fmul.2d	v1, v5, v0
10000c404: 3dc29502    	ldr	q2, [x8, #0xa50]
10000c408: 4e61d45e    	fadd.2d	v30, v2, v1
10000c40c: 6e60dce1    	fmul.2d	v1, v7, v0
10000c410: 3dc2ad02    	ldr	q2, [x8, #0xab0]
10000c414: 4e61d441    	fadd.2d	v1, v2, v1
10000c418: 3d80d3e1    	str	q1, [sp, #0x340]
10000c41c: 6e60de01    	fmul.2d	v1, v16, v0
10000c420: 3dc2c502    	ldr	q2, [x8, #0xb10]
10000c424: 4e61d441    	fadd.2d	v1, v2, v1
10000c428: 3d80b7e1    	str	q1, [sp, #0x2d0]
10000c42c: 6e60de41    	fmul.2d	v1, v18, v0
10000c430: 3dc2dd02    	ldr	q2, [x8, #0xb70]
10000c434: 4e61d441    	fadd.2d	v1, v2, v1
10000c438: 3d80a3e1    	str	q1, [sp, #0x280]
10000c43c: 6e60de61    	fmul.2d	v1, v19, v0
10000c440: 3dc2f502    	ldr	q2, [x8, #0xbd0]
10000c444: 4e61d441    	fadd.2d	v1, v2, v1
10000c448: 3d808be1    	str	q1, [sp, #0x220]
10000c44c: 6e60de81    	fmul.2d	v1, v20, v0
10000c450: 3dc30d02    	ldr	q2, [x8, #0xc30]
10000c454: 4e61d441    	fadd.2d	v1, v2, v1
10000c458: 3d8083e1    	str	q1, [sp, #0x200]
10000c45c: 6e60dea1    	fmul.2d	v1, v21, v0
10000c460: 3dc32502    	ldr	q2, [x8, #0xc90]
10000c464: 4e61d441    	fadd.2d	v1, v2, v1
10000c468: 3d806be1    	str	q1, [sp, #0x1a0]
10000c46c: 6e60dec1    	fmul.2d	v1, v22, v0
10000c470: 3dc33d02    	ldr	q2, [x8, #0xcf0]
10000c474: 4e61d441    	fadd.2d	v1, v2, v1
10000c478: 3d805fe1    	str	q1, [sp, #0x170]
10000c47c: 3dc11501    	ldr	q1, [x8, #0x450]
10000c480: 6e60dc20    	fmul.2d	v0, v1, v0
10000c484: 3dc35501    	ldr	q1, [x8, #0xd50]
10000c488: 4e60d43f    	fadd.2d	v31, v1, v0
10000c48c: 90000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000c490: 3dc18920    	ldr	q0, [x9, #0x620]
10000c494: ad420901    	ldp	q1, q2, [x8, #0x40]
10000c498: 6e60dc21    	fmul.2d	v1, v1, v0
10000c49c: 3dc25103    	ldr	q3, [x8, #0x940]
10000c4a0: 4e61d468    	fadd.2d	v8, v3, v1
10000c4a4: ad450d01    	ldp	q1, q3, [x8, #0xa0]
10000c4a8: 6e60dc21    	fmul.2d	v1, v1, v0
10000c4ac: 3dc26905    	ldr	q5, [x8, #0x9a0]
10000c4b0: 4e61d4bd    	fadd.2d	v29, v5, v1
10000c4b4: ad481501    	ldp	q1, q5, [x8, #0x100]
10000c4b8: 6e60dc21    	fmul.2d	v1, v1, v0
10000c4bc: 3dc28107    	ldr	q7, [x8, #0xa00]
10000c4c0: 4e61d4e1    	fadd.2d	v1, v7, v1
10000c4c4: 3d80f7e1    	str	q1, [sp, #0x3d0]
10000c4c8: ad4b1d01    	ldp	q1, q7, [x8, #0x160]
10000c4cc: 6e60dc21    	fmul.2d	v1, v1, v0
10000c4d0: 3dc29910    	ldr	q16, [x8, #0xa60]
10000c4d4: 4e61d601    	fadd.2d	v1, v16, v1
10000c4d8: 3d80dfe1    	str	q1, [sp, #0x370]
10000c4dc: ad4e4101    	ldp	q1, q16, [x8, #0x1c0]
10000c4e0: 6e60dc21    	fmul.2d	v1, v1, v0
10000c4e4: 3dc2b111    	ldr	q17, [x8, #0xac0]
10000c4e8: 4e61d621    	fadd.2d	v1, v17, v1
10000c4ec: 3d80c3e1    	str	q1, [sp, #0x300]
10000c4f0: ad514501    	ldp	q1, q17, [x8, #0x220]
10000c4f4: 6e60dc21    	fmul.2d	v1, v1, v0
10000c4f8: 3dc2c912    	ldr	q18, [x8, #0xb20]
10000c4fc: 4e61d641    	fadd.2d	v1, v18, v1
10000c500: 3d80afe1    	str	q1, [sp, #0x2b0]
10000c504: ad544901    	ldp	q1, q18, [x8, #0x280]
10000c508: 6e60dc21    	fmul.2d	v1, v1, v0
10000c50c: 3dc2e113    	ldr	q19, [x8, #0xb80]
10000c510: 4e61d661    	fadd.2d	v1, v19, v1
10000c514: 3d809be1    	str	q1, [sp, #0x260]
10000c518: ad574d01    	ldp	q1, q19, [x8, #0x2e0]
10000c51c: 6e60dc21    	fmul.2d	v1, v1, v0
10000c520: 3dc2f914    	ldr	q20, [x8, #0xbe0]
10000c524: 4e61d69a    	fadd.2d	v26, v20, v1
10000c528: ad5a5101    	ldp	q1, q20, [x8, #0x340]
10000c52c: 6e60dc21    	fmul.2d	v1, v1, v0
10000c530: 3dc31115    	ldr	q21, [x8, #0xc40]
10000c534: 4e61d6a1    	fadd.2d	v1, v21, v1
10000c538: 3d807be1    	str	q1, [sp, #0x1e0]
10000c53c: ad5d5501    	ldp	q1, q21, [x8, #0x3a0]
10000c540: 6e60dc21    	fmul.2d	v1, v1, v0
10000c544: 3dc32916    	ldr	q22, [x8, #0xca0]
10000c548: 4e61d6c1    	fadd.2d	v1, v22, v1
10000c54c: 3d8063e1    	str	q1, [sp, #0x180]
10000c550: 3dc10101    	ldr	q1, [x8, #0x400]
10000c554: 6e60dc21    	fmul.2d	v1, v1, v0
10000c558: 3dc34116    	ldr	q22, [x8, #0xd00]
10000c55c: 4e61d6c1    	fadd.2d	v1, v22, v1
10000c560: 3d805be1    	str	q1, [sp, #0x160]
10000c564: 3dc11901    	ldr	q1, [x8, #0x460]
10000c568: 6e60dc20    	fmul.2d	v0, v1, v0
10000c56c: 3dc35901    	ldr	q1, [x8, #0xd60]
10000c570: 4e60d421    	fadd.2d	v1, v1, v0
10000c574: 90000029    	adrp	x9, 0x100010000 <dyld_stub_binder+0x100010000>
10000c578: 3dc18d20    	ldr	q0, [x9, #0x630]
10000c57c: 6e60dc42    	fmul.2d	v2, v2, v0
10000c580: 3dc25516    	ldr	q22, [x8, #0x950]
10000c584: 4e62d6d6    	fadd.2d	v22, v22, v2
10000c588: 6e60dc62    	fmul.2d	v2, v3, v0
10000c58c: 3dc26d03    	ldr	q3, [x8, #0x9b0]
10000c590: 4e62d46c    	fadd.2d	v12, v3, v2
10000c594: 6e60dca2    	fmul.2d	v2, v5, v0
10000c598: 3dc28503    	ldr	q3, [x8, #0xa10]
10000c59c: 4e62d462    	fadd.2d	v2, v3, v2
10000c5a0: 3d80e7e2    	str	q2, [sp, #0x390]
10000c5a4: 6e60dce2    	fmul.2d	v2, v7, v0
10000c5a8: 3dc29d03    	ldr	q3, [x8, #0xa70]
10000c5ac: 4e62d467    	fadd.2d	v7, v3, v2
10000c5b0: 6e60de02    	fmul.2d	v2, v16, v0
10000c5b4: 3dc2b503    	ldr	q3, [x8, #0xad0]
10000c5b8: 4e62d462    	fadd.2d	v2, v3, v2
10000c5bc: 3d8093e2    	str	q2, [sp, #0x240]
10000c5c0: 6e60de22    	fmul.2d	v2, v17, v0
10000c5c4: 3dc2cd03    	ldr	q3, [x8, #0xb30]
10000c5c8: 4e62d47c    	fadd.2d	v28, v3, v2
10000c5cc: 6e60de42    	fmul.2d	v2, v18, v0
10000c5d0: 3dc2e503    	ldr	q3, [x8, #0xb90]
10000c5d4: 4e62d472    	fadd.2d	v18, v3, v2
10000c5d8: 6e60de62    	fmul.2d	v2, v19, v0
10000c5dc: 3dc2fd03    	ldr	q3, [x8, #0xbf0]
10000c5e0: 4e62d46a    	fadd.2d	v10, v3, v2
10000c5e4: 6e60de82    	fmul.2d	v2, v20, v0
10000c5e8: 3cda03b4    	ldur	q20, [x29, #-0x60]
10000c5ec: 3dc31503    	ldr	q3, [x8, #0xc50]
10000c5f0: 4e62d470    	fadd.2d	v16, v3, v2
10000c5f4: 6e60dea2    	fmul.2d	v2, v21, v0
10000c5f8: 3dc32d03    	ldr	q3, [x8, #0xcb0]
10000c5fc: 4e62d471    	fadd.2d	v17, v3, v2
10000c600: 3dc10503    	ldr	q3, [x8, #0x410]
10000c604: 6e60dc63    	fmul.2d	v3, v3, v0
10000c608: 3dc34505    	ldr	q5, [x8, #0xd10]
10000c60c: 4e63d4af    	fadd.2d	v15, v5, v3
10000c610: 3dc11d03    	ldr	q3, [x8, #0x470]
10000c614: 6e60dc60    	fmul.2d	v0, v3, v0
10000c618: 3dc35d03    	ldr	q3, [x8, #0xd70]
10000c61c: 4e60d463    	fadd.2d	v3, v3, v0
10000c620: 3dc103e0    	ldr	q0, [sp, #0x400]
10000c624: ad003800    	stp	q0, q14, [x0]
10000c628: ad015c1b    	stp	q27, q23, [x0, #0x20]
10000c62c: ad025808    	stp	q8, q22, [x0, #0x40]
10000c630: 3dc0efe0    	ldr	q0, [sp, #0x3b0]
10000c634: ad032c00    	stp	q0, q11, [x0, #0x60]
10000c638: 3dc0ffe0    	ldr	q0, [sp, #0x3f0]
10000c63c: ad040004    	stp	q4, q0, [x0, #0x80]
10000c640: ad05301d    	stp	q29, q12, [x0, #0xa0]
10000c644: 3dc107e0    	ldr	q0, [sp, #0x410]
10000c648: ad061800    	stp	q0, q6, [x0, #0xc0]
10000c64c: ad5883e2    	ldp	q2, q0, [sp, #0x310]
10000c650: ad070002    	stp	q2, q0, [x0, #0xe0]
10000c654: 3dc0f7e2    	ldr	q2, [sp, #0x3d0]
10000c658: 3dc0e7e0    	ldr	q0, [sp, #0x390]
10000c65c: ad080002    	stp	q2, q0, [x0, #0x100]
10000c660: 3dc0fbe0    	ldr	q0, [sp, #0x3e0]
10000c664: ad092400    	stp	q0, q9, [x0, #0x120]
10000c668: 3dc0f3e0    	ldr	q0, [sp, #0x3c0]
10000c66c: ad0a7800    	stp	q0, q30, [x0, #0x140]
10000c670: ad5b83e4    	ldp	q4, q0, [sp, #0x370]
10000c674: ad0b1c04    	stp	q4, q7, [x0, #0x160]
10000c678: 3dc0ebe2    	ldr	q2, [sp, #0x3a0]
10000c67c: ad0c0002    	stp	q2, q0, [x0, #0x180]
10000c680: 3dc0dbe2    	ldr	q2, [sp, #0x360]
10000c684: 3dc0d3e0    	ldr	q0, [sp, #0x340]
10000c688: ad0d0002    	stp	q2, q0, [x0, #0x1a0]
10000c68c: 3dc0c3e2    	ldr	q2, [sp, #0x300]
10000c690: 3dc093e0    	ldr	q0, [sp, #0x240]
10000c694: ad0e0002    	stp	q2, q0, [x0, #0x1c0]
10000c698: 3dc0d7e2    	ldr	q2, [sp, #0x350]
10000c69c: 3dc0cfe0    	ldr	q0, [sp, #0x330]
10000c6a0: ad0f0002    	stp	q2, q0, [x0, #0x1e0]
10000c6a4: 3dc0bfe2    	ldr	q2, [sp, #0x2f0]
10000c6a8: 3dc0b7e0    	ldr	q0, [sp, #0x2d0]
10000c6ac: ad100002    	stp	q2, q0, [x0, #0x200]
10000c6b0: ad5583e4    	ldp	q4, q0, [sp, #0x2b0]
10000c6b4: ad117004    	stp	q4, q28, [x0, #0x220]
10000c6b8: 3dc0bbe2    	ldr	q2, [sp, #0x2e0]
10000c6bc: ad120002    	stp	q2, q0, [x0, #0x240]
10000c6c0: 3dc0abe2    	ldr	q2, [sp, #0x2a0]
10000c6c4: 3dc0a3e0    	ldr	q0, [sp, #0x280]
10000c6c8: ad130002    	stp	q2, q0, [x0, #0x260]
10000c6cc: ad5303e4    	ldp	q4, q0, [sp, #0x260]
10000c6d0: ad144804    	stp	q4, q18, [x0, #0x280]
10000c6d4: 3dc0a7e2    	ldr	q2, [sp, #0x290]
10000c6d8: ad150002    	stp	q2, q0, [x0, #0x2a0]
10000c6dc: 3dc097e2    	ldr	q2, [sp, #0x250]
10000c6e0: ad5117e4    	ldp	q4, q5, [sp, #0x220]
10000c6e4: ad161002    	stp	q2, q4, [x0, #0x2c0]
10000c6e8: ad17281a    	stp	q26, q10, [x0, #0x2e0]
10000c6ec: ad500be0    	ldp	q0, q2, [sp, #0x200]
10000c6f0: ad180805    	stp	q5, q2, [x0, #0x300]
10000c6f4: ad190019    	stp	q25, q0, [x0, #0x320]
10000c6f8: ad4f03e2    	ldp	q2, q0, [sp, #0x1e0]
10000c6fc: ad1a4002    	stp	q2, q16, [x0, #0x340]
10000c700: ad1b000d    	stp	q13, q0, [x0, #0x360]
10000c704: 3dc073e2    	ldr	q2, [sp, #0x1c0]
10000c708: 3dc06be0    	ldr	q0, [sp, #0x1a0]
10000c70c: ad1c0002    	stp	q2, q0, [x0, #0x380]
10000c710: 3dc063e0    	ldr	q0, [sp, #0x180]
10000c714: ad1d4400    	stp	q0, q17, [x0, #0x3a0]
10000c718: 3dc077e2    	ldr	q2, [sp, #0x1d0]
10000c71c: 3dc06fe0    	ldr	q0, [sp, #0x1b0]
10000c720: ad1e0002    	stp	q2, q0, [x0, #0x3c0]
10000c724: 3dc067e2    	ldr	q2, [sp, #0x190]
10000c728: ad4b13e0    	ldp	q0, q4, [sp, #0x160]
10000c72c: ad1f1002    	stp	q2, q4, [x0, #0x3e0]
10000c730: 3d810000    	str	q0, [x0, #0x400]
10000c734: 3d81040f    	str	q15, [x0, #0x410]
10000c738: 3d810814    	str	q20, [x0, #0x420]
10000c73c: 3cd603a0    	ldur	q0, [x29, #-0xa0]
10000c740: 3d810c00    	str	q0, [x0, #0x430]
10000c744: 3d811018    	str	q24, [x0, #0x440]
10000c748: 3d81141f    	str	q31, [x0, #0x450]
10000c74c: 3d811801    	str	q1, [x0, #0x460]
10000c750: 3d811c03    	str	q3, [x0, #0x470]
10000c754: 912103ff    	add	sp, sp, #0x840
10000c758: a9457bfd    	ldp	x29, x30, [sp, #0x50]
10000c75c: a9446ffc    	ldp	x28, x27, [sp, #0x40]
10000c760: 6d4323e9    	ldp	d9, d8, [sp, #0x30]
10000c764: 6d422beb    	ldp	d11, d10, [sp, #0x20]
10000c768: 6d4133ed    	ldp	d13, d12, [sp, #0x10]
10000c76c: 6cc63bef    	ldp	d15, d14, [sp], #0x60
10000c770: d65f03c0    	ret

000000010000c774 <_Io.Writer.printValue__anon_4346>:
10000c774: a9ba6ffc    	stp	x28, x27, [sp, #-0x60]!
10000c778: a90167fa    	stp	x26, x25, [sp, #0x10]
10000c77c: a9025ff8    	stp	x24, x23, [sp, #0x20]
10000c780: a90357f6    	stp	x22, x21, [sp, #0x30]
10000c784: a9044ff4    	stp	x20, x19, [sp, #0x40]
10000c788: a9057bfd    	stp	x29, x30, [sp, #0x50]
10000c78c: 910143fd    	add	x29, sp, #0x50
10000c790: d106c3ff    	sub	sp, sp, #0x1b0
10000c794: d10203b9    	sub	x25, x29, #0x80
10000c798: f9400014    	ldr	x20, [x0]
10000c79c: 39402018    	ldrb	w24, [x0, #0x8]
10000c7a0: f9400816    	ldr	x22, [x0, #0x10]
10000c7a4: 39406017    	ldrb	w23, [x0, #0x18]
10000c7a8: 39408008    	ldrb	w8, [x0, #0x20]
10000c7ac: 39408413    	ldrb	w19, [x0, #0x21]
10000c7b0: 390063ff    	strb	wzr, [sp, #0x18]
10000c7b4: 12000508    	and	w8, w8, #0x3
10000c7b8: 39005be8    	strb	w8, [sp, #0x16]
10000c7bc: 72000bff    	tst	wzr, #0x7
10000c7c0: 1a9f17e8    	cset	w8, eq
10000c7c4: 381783a8    	sturb	w8, [x29, #-0x88]
10000c7c8: 9e660008    	fmov	x8, d0
10000c7cc: d374f90c    	ubfx	x12, x8, #52, #11
10000c7d0: 910077e9    	add	x9, sp, #0x1d
10000c7d4: 91000535    	add	x21, x9, #0x1
10000c7d8: f240cd11    	ands	x17, x8, #0xfffffffffffff
10000c7dc: 540003a1    	b.ne	0x10000c850 <_Io.Writer.printValue__anon_4346+0xdc>
10000c7e0: 3500038c    	cbnz	w12, 0x10000c850 <_Io.Writer.printValue__anon_4346+0xdc>
10000c7e4: f900033f    	str	xzr, [x25]
10000c7e8: b9000b3f    	str	wzr, [x25, #0x8]
10000c7ec: f100011f    	cmp	x8, #0x0
10000c7f0: 1a9fa7e8    	cset	w8, lt
10000c7f4: 3818c3a8    	sturb	w8, [x29, #-0x74]
10000c7f8: 385783a8    	ldurb	w8, [x29, #-0x88]
10000c7fc: 360028e8    	tbz	w8, #0x0, 0x10000cd18 <_Io.Writer.printValue__anon_4346+0x5a4>
10000c800: 3dc00320    	ldr	q0, [x25]
10000c804: 3d800720    	str	q0, [x25, #0x10]
10000c808: b9401b28    	ldr	w8, [x25, #0x18]
10000c80c: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000c810: 6b09011f    	cmp	w8, w9
10000c814: 540028e0    	b.eq	0x10000cd30 <_Io.Writer.printValue__anon_4346+0x5bc>
10000c818: 340000d8    	cbz	w24, 0x10000c830 <_Io.Writer.printValue__anon_4346+0xbc>
10000c81c: d101c3a0    	sub	x0, x29, #0x70
10000c820: d10203a1    	sub	x1, x29, #0x80
10000c824: 52800002    	mov	w2, #0x0                ; =0
10000c828: aa1403e3    	mov	x3, x20
10000c82c: 9400077a    	bl	0x10000e614 <_fmt.float.round__anon_5325>
10000c830: f9400b3a    	ldr	x26, [x25, #0x10]
10000c834: 92b207e8    	mov	x8, #-0x903f0001        ; =-2420047873
10000c838: f2d0de48    	movk	x8, #0x86f2, lsl #32
10000c83c: f2e00468    	movk	x8, #0x23, lsl #48
10000c840: eb08035f    	cmp	x26, x8
10000c844: 54000ae9    	b.ls	0x10000c9a0 <_Io.Writer.printValue__anon_4346+0x22c>
10000c848: 5280023b    	mov	w27, #0x11              ; =17
10000c84c: 1400021d    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000c850: 711ffd9f    	cmp	w12, #0x7ff
10000c854: 54000141    	b.ne	0x10000c87c <_Io.Writer.printValue__anon_4346+0x108>
10000c858: f9000331    	str	x17, [x25]
10000c85c: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000c860: b9000b29    	str	w9, [x25, #0x8]
10000c864: f100011f    	cmp	x8, #0x0
10000c868: 1a9fa7e8    	cset	w8, lt
10000c86c: 3818c3a8    	sturb	w8, [x29, #-0x74]
10000c870: 385783a8    	ldurb	w8, [x29, #-0x88]
10000c874: 3707fc68    	tbnz	w8, #0x0, 0x10000c800 <_Io.Writer.printValue__anon_4346+0x8c>
10000c878: 14000128    	b	0x10000cd18 <_Io.Writer.printValue__anon_4346+0x5a4>
10000c87c: d299a36b    	mov	x11, #0xcd1b            ; =52507
10000c880: f2af096b    	movk	x11, #0x784b, lsl #16
10000c884: f2d2934b    	movk	x11, #0x949a, lsl #32
10000c888: d37ef630    	lsl	x16, x17, #2
10000c88c: 340009ac    	cbz	w12, 0x10000c9c0 <_Io.Writer.printValue__anon_4346+0x24c>
10000c890: 5110d589    	sub	w9, w12, #0x435
10000c894: f240011f    	tst	x8, #0x1
10000c898: 1a9f17ea    	cset	w10, eq
10000c89c: d2e0080f    	mov	x15, #0x40000000000000  ; =18014398509481984
10000c8a0: b37ece2f    	bfi	x15, x17, #2, #52
10000c8a4: f100023f    	cmp	x17, #0x0
10000c8a8: 1a9f07ee    	cset	w14, ne
10000c8ac: 7110d19f    	cmp	w12, #0x434
10000c8b0: 54000929    	b.ls	0x10000c9d4 <_Io.Writer.printValue__anon_4346+0x260>
10000c8b4: d280004e    	mov	x14, #0x2               ; =2
10000c8b8: f2e0080e    	movk	x14, #0x40, lsl #48
10000c8bc: d29f79ed    	mov	x13, #0xfbcf            ; =64463
10000c8c0: f2b3508d    	movk	x13, #0x9a84, lsl #16
10000c8c4: f2d3440d    	movk	x13, #0x9a20, lsl #32
10000c8c8: 9b0d7d2d    	mul	x13, x9, x13
10000c8cc: d371fdad    	lsr	x13, x13, #49
10000c8d0: 71000d3f    	cmp	w9, #0x3
10000c8d4: 1a9f97e9    	cset	w9, hi
10000c8d8: 4b0901a9    	sub	w9, w13, w9
10000c8dc: 4b0c012c    	sub	w12, w9, w12
10000c8e0: 9b0b7d2b    	mul	x11, x9, x11
10000c8e4: d36efd6b    	lsr	x11, x11, #46
10000c8e8: 0b0b018b    	add	w11, w12, w11
10000c8ec: 1112c96b    	add	w11, w11, #0x4b2
10000c8f0: 7102017f    	cmp	w11, #0x80
10000c8f4: 54001122    	b.hs	0x10000cb18 <_Io.Writer.printValue__anon_4346+0x3a4>
10000c8f8: 9000002c    	adrp	x12, 0x100010000 <dyld_stub_binder+0x100010000>
10000c8fc: 911fc18c    	add	x12, x12, #0x7f0
10000c900: 8b29518c    	add	x12, x12, w9, uxtw #4
10000c904: a9400580    	ldp	x0, x1, [x12]
10000c908: f100023f    	cmp	x17, #0x0
10000c90c: 1a9f07f1    	cset	w17, ne
10000c910: 9bcf7c2c    	umulh	x12, x1, x15
10000c914: 9b0f7c2d    	mul	x13, x1, x15
10000c918: 9bcf7c02    	umulh	x2, x0, x15
10000c91c: ab0d004d    	adds	x13, x2, x13
10000c920: 9a8c358c    	cinc	x12, x12, hs
10000c924: 9acb25ad    	lsr	x13, x13, x11
10000c928: d37ff98c    	lsl	x12, x12, #1
10000c92c: 92401562    	and	x2, x11, #0x3f
10000c930: d2401442    	eor	x2, x2, #0x3f
10000c934: 9ac2218c    	lsl	x12, x12, x2
10000c938: aa0d018c    	orr	x12, x12, x13
10000c93c: aa0e020e    	orr	x14, x16, x14
10000c940: 9bce7c2d    	umulh	x13, x1, x14
10000c944: 9b0e7c23    	mul	x3, x1, x14
10000c948: 9bce7c04    	umulh	x4, x0, x14
10000c94c: ab030083    	adds	x3, x4, x3
10000c950: 9a8d35ad    	cinc	x13, x13, hs
10000c954: 9acb2463    	lsr	x3, x3, x11
10000c958: d37ff9ad    	lsl	x13, x13, #1
10000c95c: 9ac221ad    	lsl	x13, x13, x2
10000c960: aa0301ad    	orr	x13, x13, x3
10000c964: 92fff803    	mov	x3, #0x3fffffffffffff   ; =18014398509481983
10000c968: cb110210    	sub	x16, x16, x17
10000c96c: 8b030210    	add	x16, x16, x3
10000c970: 9bd07c31    	umulh	x17, x1, x16
10000c974: 9b107c21    	mul	x1, x1, x16
10000c978: 9bd07c00    	umulh	x0, x0, x16
10000c97c: ab010000    	adds	x0, x0, x1
10000c980: 9a913631    	cinc	x17, x17, hs
10000c984: 9acb240b    	lsr	x11, x0, x11
10000c988: d37ffa31    	lsl	x17, x17, #1
10000c98c: 9ac22231    	lsl	x17, x17, x2
10000c990: aa0b022b    	orr	x11, x17, x11
10000c994: 7100593f    	cmp	w9, #0x16
10000c998: 54000d63    	b.lo	0x10000cb44 <_Io.Writer.printValue__anon_4346+0x3d0>
10000c99c: 14000083    	b	0x10000cba8 <_Io.Writer.printValue__anon_4346+0x434>
10000c9a0: d28fffe8    	mov	x8, #0x7fff             ; =32767
10000c9a4: f2b498c8    	movk	x8, #0xa4c6, lsl #16
10000c9a8: f2d1afc8    	movk	x8, #0x8d7e, lsl #32
10000c9ac: f2e00068    	movk	x8, #0x3, lsl #48
10000c9b0: eb08035f    	cmp	x26, x8
10000c9b4: 54000a49    	b.ls	0x10000cafc <_Io.Writer.printValue__anon_4346+0x388>
10000c9b8: 5280021b    	mov	w27, #0x10              ; =16
10000c9bc: 140001c1    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000c9c0: f240011f    	tst	x8, #0x1
10000c9c4: 1a9f17ea    	cset	w10, eq
10000c9c8: 12808669    	mov	w9, #-0x434             ; =-1076
10000c9cc: 5280002e    	mov	w14, #0x1               ; =1
10000c9d0: aa1003ef    	mov	x15, x16
10000c9d4: 4b0903ec    	neg	w12, w9
10000c9d8: d290430d    	mov	x13, #0x8218            ; =33304
10000c9dc: f2b657ad    	movk	x13, #0xb2bd, lsl #16
10000c9e0: f2d65ded    	movk	x13, #0xb2ef, lsl #32
10000c9e4: 9b0d7d8d    	mul	x13, x12, x13
10000c9e8: d370fdad    	lsr	x13, x13, #48
10000c9ec: 3100053f    	cmn	w9, #0x1
10000c9f0: 1a9f07f0    	cset	w16, ne
10000c9f4: 4b1001b0    	sub	w16, w13, w16
10000c9f8: 0b090209    	add	w9, w16, w9
10000c9fc: 4b10018c    	sub	w12, w12, w16
10000ca00: 9b0b7d8b    	mul	x11, x12, x11
10000ca04: d36efd6b    	lsr	x11, x11, #46
10000ca08: 4b0b020b    	sub	w11, w16, w11
10000ca0c: 1101f16b    	add	w11, w11, #0x7c
10000ca10: 7101fd7f    	cmp	w11, #0x7f
10000ca14: 54000608    	b.hi	0x10000cad4 <_Io.Writer.printValue__anon_4346+0x360>
10000ca18: b000002d    	adrp	x13, 0x100011000 <___anon_5016+0x840>
10000ca1c: 913541ad    	add	x13, x13, #0xd50
10000ca20: 8b2c51ac    	add	x12, x13, w12, uxtw #4
10000ca24: a9400191    	ldp	x17, x0, [x12]
10000ca28: 9bcf7c0c    	umulh	x12, x0, x15
10000ca2c: 9b0f7c0d    	mul	x13, x0, x15
10000ca30: 9bcf7e21    	umulh	x1, x17, x15
10000ca34: ab0d002d    	adds	x13, x1, x13
10000ca38: 9a8c358c    	cinc	x12, x12, hs
10000ca3c: 9acb25ad    	lsr	x13, x13, x11
10000ca40: d37ff98c    	lsl	x12, x12, #1
10000ca44: 92401561    	and	x1, x11, #0x3f
10000ca48: d2401421    	eor	x1, x1, #0x3f
10000ca4c: 9ac1218c    	lsl	x12, x12, x1
10000ca50: aa0d018c    	orr	x12, x12, x13
10000ca54: b27f01ed    	orr	x13, x15, #0x2
10000ca58: 9bcd7c02    	umulh	x2, x0, x13
10000ca5c: 9b0d7c03    	mul	x3, x0, x13
10000ca60: 9bcd7e2d    	umulh	x13, x17, x13
10000ca64: ab0301ad    	adds	x13, x13, x3
10000ca68: 9a823442    	cinc	x2, x2, hs
10000ca6c: 9acb25ad    	lsr	x13, x13, x11
10000ca70: d37ff842    	lsl	x2, x2, #1
10000ca74: 9ac12042    	lsl	x2, x2, x1
10000ca78: aa0d004d    	orr	x13, x2, x13
10000ca7c: 2a0e03e2    	mov	w2, w14
10000ca80: aa2203e2    	mvn	x2, x2
10000ca84: 8b0f0042    	add	x2, x2, x15
10000ca88: 9bc27c03    	umulh	x3, x0, x2
10000ca8c: 9b027c00    	mul	x0, x0, x2
10000ca90: 9bc27e31    	umulh	x17, x17, x2
10000ca94: ab000231    	adds	x17, x17, x0
10000ca98: 9a833460    	cinc	x0, x3, hs
10000ca9c: 9acb262b    	lsr	x11, x17, x11
10000caa0: d37ff811    	lsl	x17, x0, #1
10000caa4: 9ac12231    	lsl	x17, x17, x1
10000caa8: aa0b022b    	orr	x11, x17, x11
10000caac: 71000a1f    	cmp	w16, #0x2
10000cab0: 540001c3    	b.lo	0x10000cae8 <_Io.Writer.printValue__anon_4346+0x374>
10000cab4: 7100fa1f    	cmp	w16, #0x3e
10000cab8: 54000788    	b.hi	0x10000cba8 <_Io.Writer.printValue__anon_4346+0x434>
10000cabc: 5280000e    	mov	w14, #0x0               ; =0
10000cac0: 92800011    	mov	x17, #-0x1              ; =-1
10000cac4: 9ad02230    	lsl	x16, x17, x16
10000cac8: ea3001ff    	bics	xzr, x15, x16
10000cacc: 1a9f17ef    	cset	w15, eq
10000cad0: 14000038    	b	0x10000cbb0 <_Io.Writer.printValue__anon_4346+0x43c>
10000cad4: d280000d    	mov	x13, #0x0               ; =0
10000cad8: d280000c    	mov	x12, #0x0               ; =0
10000cadc: d280000b    	mov	x11, #0x0               ; =0
10000cae0: 71000a1f    	cmp	w16, #0x2
10000cae4: 54fffe82    	b.hs	0x10000cab4 <_Io.Writer.printValue__anon_4346+0x340>
10000cae8: 0a0a01ce    	and	w14, w14, w10
10000caec: 5200014f    	eor	w15, w10, #0x1
10000caf0: cb0f01ad    	sub	x13, x13, x15
10000caf4: 5280002f    	mov	w15, #0x1               ; =1
10000caf8: 1400002e    	b	0x10000cbb0 <_Io.Writer.printValue__anon_4346+0x43c>
10000cafc: d287ffe8    	mov	x8, #0x3fff             ; =16383
10000cb00: f2a20f48    	movk	x8, #0x107a, lsl #16
10000cb04: f2cb5e68    	movk	x8, #0x5af3, lsl #32
10000cb08: eb08035f    	cmp	x26, x8
10000cb0c: 54001769    	b.ls	0x10000cdf8 <_Io.Writer.printValue__anon_4346+0x684>
10000cb10: 528001fb    	mov	w27, #0xf               ; =15
10000cb14: 1400016b    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000cb18: d280000d    	mov	x13, #0x0               ; =0
10000cb1c: d280000c    	mov	x12, #0x0               ; =0
10000cb20: d280000b    	mov	x11, #0x0               ; =0
10000cb24: f100023f    	cmp	x17, #0x0
10000cb28: 1a9f07f1    	cset	w17, ne
10000cb2c: aa0e020e    	orr	x14, x16, x14
10000cb30: 92fff800    	mov	x0, #0x3fffffffffffff   ; =18014398509481983
10000cb34: cb110210    	sub	x16, x16, x17
10000cb38: 8b000210    	add	x16, x16, x0
10000cb3c: 7100593f    	cmp	w9, #0x16
10000cb40: 54000342    	b.hs	0x10000cba8 <_Io.Writer.printValue__anon_4346+0x434>
10000cb44: b202e7f1    	mov	x17, #-0x3333333333333334 ; =-3689348814741910324
10000cb48: f29999b1    	movk	x17, #0xcccd
10000cb4c: 9b117de0    	mul	x0, x15, x17
10000cb50: b200e7e1    	mov	x1, #0x3333333333333333 ; =3689348814741910323
10000cb54: eb01001f    	cmp	x0, x1
10000cb58: 54001889    	b.ls	0x10000ce68 <_Io.Writer.printValue__anon_4346+0x6f4>
10000cb5c: 37001a48    	tbnz	w8, #0x0, 0x10000cea4 <_Io.Writer.printValue__anon_4346+0x730>
10000cb60: 5280000a    	mov	w10, #0x0               ; =0
10000cb64: b202e7ee    	mov	x14, #-0x3333333333333334 ; =-3689348814741910324
10000cb68: f29999ae    	movk	x14, #0xcccd
10000cb6c: 9bce7e0f    	umulh	x15, x16, x14
10000cb70: d342fdef    	lsr	x15, x15, #2
10000cb74: 8b0f09f1    	add	x17, x15, x15, lsl #2
10000cb78: eb11021f    	cmp	x16, x17
10000cb7c: 540000c1    	b.ne	0x10000cb94 <_Io.Writer.printValue__anon_4346+0x420>
10000cb80: 1100054a    	add	w10, w10, #0x1
10000cb84: f100121f    	cmp	x16, #0x4
10000cb88: aa0f03f0    	mov	x16, x15
10000cb8c: 54ffff08    	b.hi	0x10000cb6c <_Io.Writer.printValue__anon_4346+0x3f8>
10000cb90: 5280000a    	mov	w10, #0x0               ; =0
10000cb94: 5280000f    	mov	w15, #0x0               ; =0
10000cb98: 6b09015f    	cmp	w10, w9
10000cb9c: 1a9f37ee    	cset	w14, hs
10000cba0: 5280002a    	mov	w10, #0x1               ; =1
10000cba4: 14000003    	b	0x10000cbb0 <_Io.Writer.printValue__anon_4346+0x43c>
10000cba8: 5280000f    	mov	w15, #0x0               ; =0
10000cbac: 5280000e    	mov	w14, #0x0               ; =0
10000cbb0: b202e7f1    	mov	x17, #-0x3333333333333334 ; =-3689348814741910324
10000cbb4: f29999b1    	movk	x17, #0xcccd
10000cbb8: 9bd17dad    	umulh	x13, x13, x17
10000cbbc: d343fda0    	lsr	x0, x13, #3
10000cbc0: 9bd17d6d    	umulh	x13, x11, x17
10000cbc4: d343fda3    	lsr	x3, x13, #3
10000cbc8: eb03001f    	cmp	x0, x3
10000cbcc: 540003c9    	b.ls	0x10000cc44 <_Io.Writer.printValue__anon_4346+0x4d0>
10000cbd0: 5280000d    	mov	w13, #0x0               ; =0
10000cbd4: 52800010    	mov	w16, #0x0               ; =0
10000cbd8: b201e7e1    	mov	x1, #-0x6666666666666667 ; =-7378697629483820647
10000cbdc: d2410821    	eor	x1, x1, #0x8000000000000003
10000cbe0: 52800142    	mov	w2, #0xa                ; =10
10000cbe4: aa0c03e4    	mov	x4, x12
10000cbe8: 9b117d6c    	mul	x12, x11, x17
10000cbec: 93cc058c    	ror	x12, x12, #0x1
10000cbf0: eb01019f    	cmp	x12, x1
10000cbf4: 1a9f27ec    	cset	w12, lo
10000cbf8: 720001df    	tst	w14, #0x1
10000cbfc: 1a9f118e    	csel	w14, w12, wzr, ne
10000cc00: aa0303eb    	mov	x11, x3
10000cc04: 72001e1f    	tst	w16, #0xff
10000cc08: 1a9f17ec    	cset	w12, eq
10000cc0c: 0a0c01ef    	and	w15, w15, w12
10000cc10: 9bd17c8c    	umulh	x12, x4, x17
10000cc14: d343fd8c    	lsr	x12, x12, #3
10000cc18: 1b029190    	msub	w16, w12, w2, w4
10000cc1c: 110005ad    	add	w13, w13, #0x1
10000cc20: 9bd17c00    	umulh	x0, x0, x17
10000cc24: d343fc00    	lsr	x0, x0, #3
10000cc28: 9bd17c63    	umulh	x3, x3, x17
10000cc2c: d343fc63    	lsr	x3, x3, #3
10000cc30: aa0c03e4    	mov	x4, x12
10000cc34: eb03001f    	cmp	x0, x3
10000cc38: 54fffd88    	b.hi	0x10000cbe8 <_Io.Writer.printValue__anon_4346+0x474>
10000cc3c: 350000ae    	cbnz	w14, 0x10000cc50 <_Io.Writer.printValue__anon_4346+0x4dc>
10000cc40: 1400001d    	b	0x10000ccb4 <_Io.Writer.printValue__anon_4346+0x540>
10000cc44: 52800010    	mov	w16, #0x0               ; =0
10000cc48: 5280000d    	mov	w13, #0x0               ; =0
10000cc4c: 3400034e    	cbz	w14, 0x10000ccb4 <_Io.Writer.printValue__anon_4346+0x540>
10000cc50: 9bd17d71    	umulh	x17, x11, x17
10000cc54: d343fe31    	lsr	x17, x17, #3
10000cc58: 52800140    	mov	w0, #0xa                ; =10
10000cc5c: 9b00ae31    	msub	x17, x17, x0, x11
10000cc60: b50002b1    	cbnz	x17, 0x10000ccb4 <_Io.Writer.printValue__anon_4346+0x540>
10000cc64: b202e7e0    	mov	x0, #-0x3333333333333334 ; =-3689348814741910324
10000cc68: f29999a0    	movk	x0, #0xcccd
10000cc6c: 52800141    	mov	w1, #0xa                ; =10
10000cc70: b201e7e2    	mov	x2, #-0x6666666666666667 ; =-7378697629483820647
10000cc74: d2410842    	eor	x2, x2, #0x8000000000000003
10000cc78: 72001e1f    	tst	w16, #0xff
10000cc7c: 1a9f17f0    	cset	w16, eq
10000cc80: 0a1001ef    	and	w15, w15, w16
10000cc84: 9bc07d90    	umulh	x16, x12, x0
10000cc88: d343fe11    	lsr	x17, x16, #3
10000cc8c: 1b01b230    	msub	w16, w17, w1, w12
10000cc90: 9bc07d6b    	umulh	x11, x11, x0
10000cc94: d343fd6b    	lsr	x11, x11, #3
10000cc98: 110005ad    	add	w13, w13, #0x1
10000cc9c: 9b007d6c    	mul	x12, x11, x0
10000cca0: 93cc0583    	ror	x3, x12, #0x1
10000cca4: aa1103ec    	mov	x12, x17
10000cca8: eb02007f    	cmp	x3, x2
10000ccac: 54fffe63    	b.lo	0x10000cc78 <_Io.Writer.printValue__anon_4346+0x504>
10000ccb0: 14000002    	b	0x10000ccb8 <_Io.Writer.printValue__anon_4346+0x544>
10000ccb4: aa0c03f1    	mov	x17, x12
10000ccb8: 12001e0c    	and	w12, w16, #0xff
10000ccbc: 7100159f    	cmp	w12, #0x5
10000ccc0: 1a9f17ec    	cset	w12, eq
10000ccc4: f240023f    	tst	x17, #0x1
10000ccc8: 52800080    	mov	w0, #0x4                ; =4
10000cccc: 1a800400    	cinc	w0, w0, ne
10000ccd0: 6a0c01ff    	tst	w15, w12
10000ccd4: 1a90100c    	csel	w12, w0, w16, ne
10000ccd8: 12001d8c    	and	w12, w12, #0xff
10000ccdc: eb0b023f    	cmp	x17, x11
10000cce0: 1a9f17eb    	cset	w11, eq
10000cce4: 0a0e014a    	and	w10, w10, w14
10000cce8: 7100119f    	cmp	w12, #0x4
10000ccec: 0a2a016a    	bic	w10, w11, w10
10000ccf0: 1a9f954a    	csinc	w10, w10, wzr, ls
10000ccf4: 8b0a022a    	add	x10, x17, x10
10000ccf8: f900032a    	str	x10, [x25]
10000ccfc: 0b0901a9    	add	w9, w13, w9
10000cd00: b9000b29    	str	w9, [x25, #0x8]
10000cd04: f100011f    	cmp	x8, #0x0
10000cd08: 1a9fa7e8    	cset	w8, lt
10000cd0c: 3818c3a8    	sturb	w8, [x29, #-0x74]
10000cd10: 385783a8    	ldurb	w8, [x29, #-0x88]
10000cd14: 3707d768    	tbnz	w8, #0x0, 0x10000c800 <_Io.Writer.printValue__anon_4346+0x8c>
10000cd18: 3dc00320    	ldr	q0, [x25]
10000cd1c: 3d800720    	str	q0, [x25, #0x10]
10000cd20: b9401b28    	ldr	w8, [x25, #0x18]
10000cd24: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000cd28: 6b09011f    	cmp	w8, w9
10000cd2c: 540001a1    	b.ne	0x10000cd60 <_Io.Writer.printValue__anon_4346+0x5ec>
10000cd30: 3859c3a8    	ldurb	w8, [x29, #-0x64]
10000cd34: 36000068    	tbz	w8, #0x0, 0x10000cd40 <_Io.Writer.printValue__anon_4346+0x5cc>
10000cd38: 528005a9    	mov	w9, #0x2d               ; =45
10000cd3c: 390077e9    	strb	w9, [sp, #0x1d]
10000cd40: f9400b2a    	ldr	x10, [x25, #0x10]
10000cd44: 910077e9    	add	x9, sp, #0x1d
10000cd48: 8b080129    	add	x9, x9, x8
10000cd4c: b400026a    	cbz	x10, 0x10000cd98 <_Io.Writer.printValue__anon_4346+0x624>
10000cd50: 52800dca    	mov	w10, #0x6e              ; =110
10000cd54: 3900092a    	strb	w10, [x9, #0x2]
10000cd58: 528c2dca    	mov	w10, #0x616e            ; =24942
10000cd5c: 14000012    	b	0x10000cda4 <_Io.Writer.printValue__anon_4346+0x630>
10000cd60: 340000d8    	cbz	w24, 0x10000cd78 <_Io.Writer.printValue__anon_4346+0x604>
10000cd64: d101c3a0    	sub	x0, x29, #0x70
10000cd68: d10203a1    	sub	x1, x29, #0x80
10000cd6c: 52800022    	mov	w2, #0x1                ; =1
10000cd70: aa1403e3    	mov	x3, x20
10000cd74: 94000628    	bl	0x10000e614 <_fmt.float.round__anon_5325>
10000cd78: f9400b28    	ldr	x8, [x25, #0x10]
10000cd7c: 92b207e9    	mov	x9, #-0x903f0001        ; =-2420047873
10000cd80: f2d0de49    	movk	x9, #0x86f2, lsl #32
10000cd84: f2e00469    	movk	x9, #0x23, lsl #48
10000cd88: eb09011f    	cmp	x8, x9
10000cd8c: 54000189    	b.ls	0x10000cdbc <_Io.Writer.printValue__anon_4346+0x648>
10000cd90: 5280023b    	mov	w27, #0x11              ; =17
10000cd94: 140002c9    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000cd98: 52800cca    	mov	w10, #0x66              ; =102
10000cd9c: 3900092a    	strb	w10, [x9, #0x2]
10000cda0: 528dcd2a    	mov	w10, #0x6e69            ; =28265
10000cda4: 7900012a    	strh	w10, [x9]
10000cda8: 52800009    	mov	w9, #0x0                ; =0
10000cdac: 7100011f    	cmp	w8, #0x0
10000cdb0: 52800068    	mov	w8, #0x3                ; =3
10000cdb4: 9a880508    	cinc	x8, x8, ne
10000cdb8: 140003a5    	b	0x10000dc4c <_Io.Writer.printValue__anon_4346+0x14d8>
10000cdbc: d28fffe9    	mov	x9, #0x7fff             ; =32767
10000cdc0: f2b498c9    	movk	x9, #0xa4c6, lsl #16
10000cdc4: f2d1afc9    	movk	x9, #0x8d7e, lsl #32
10000cdc8: f2e00069    	movk	x9, #0x3, lsl #48
10000cdcc: eb09011f    	cmp	x8, x9
10000cdd0: 54000069    	b.ls	0x10000cddc <_Io.Writer.printValue__anon_4346+0x668>
10000cdd4: 5280021b    	mov	w27, #0x10              ; =16
10000cdd8: 140002b8    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000cddc: d287ffe9    	mov	x9, #0x3fff             ; =16383
10000cde0: f2a20f49    	movk	x9, #0x107a, lsl #16
10000cde4: f2cb5e69    	movk	x9, #0x5af3, lsl #32
10000cde8: eb09011f    	cmp	x8, x9
10000cdec: 54000149    	b.ls	0x10000ce14 <_Io.Writer.printValue__anon_4346+0x6a0>
10000cdf0: 528001fb    	mov	w27, #0xf               ; =15
10000cdf4: 140002b1    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000cdf8: d293ffe8    	mov	x8, #0x9fff             ; =40959
10000cdfc: f2a9ce48    	movk	x8, #0x4e72, lsl #16
10000ce00: f2c12308    	movk	x8, #0x918, lsl #32
10000ce04: eb08035f    	cmp	x26, x8
10000ce08: 54000149    	b.ls	0x10000ce30 <_Io.Writer.printValue__anon_4346+0x6bc>
10000ce0c: 528001db    	mov	w27, #0xe               ; =14
10000ce10: 140000ac    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000ce14: d293ffe9    	mov	x9, #0x9fff             ; =40959
10000ce18: f2a9ce49    	movk	x9, #0x4e72, lsl #16
10000ce1c: f2c12309    	movk	x9, #0x918, lsl #32
10000ce20: eb09011f    	cmp	x8, x9
10000ce24: 54000149    	b.ls	0x10000ce4c <_Io.Writer.printValue__anon_4346+0x6d8>
10000ce28: 528001db    	mov	w27, #0xe               ; =14
10000ce2c: 140002a3    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000ce30: d281ffe8    	mov	x8, #0xfff              ; =4095
10000ce34: f2ba94a8    	movk	x8, #0xd4a5, lsl #16
10000ce38: f2c01d08    	movk	x8, #0xe8, lsl #32
10000ce3c: eb08035f    	cmp	x26, x8
10000ce40: 540005a9    	b.ls	0x10000cef4 <_Io.Writer.printValue__anon_4346+0x780>
10000ce44: 528001bb    	mov	w27, #0xd               ; =13
10000ce48: 1400009e    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000ce4c: d281ffe9    	mov	x9, #0xfff              ; =4095
10000ce50: f2ba94a9    	movk	x9, #0xd4a5, lsl #16
10000ce54: f2c01d09    	movk	x9, #0xe8, lsl #32
10000ce58: eb09011f    	cmp	x8, x9
10000ce5c: 540005a9    	b.ls	0x10000cf10 <_Io.Writer.printValue__anon_4346+0x79c>
10000ce60: 528001bb    	mov	w27, #0xd               ; =13
10000ce64: 14000295    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000ce68: 52800010    	mov	w16, #0x0               ; =0
10000ce6c: 9bd17dee    	umulh	x14, x15, x17
10000ce70: d342fdce    	lsr	x14, x14, #2
10000ce74: 8b0e09c0    	add	x0, x14, x14, lsl #2
10000ce78: eb0001ff    	cmp	x15, x0
10000ce7c: 540000c1    	b.ne	0x10000ce94 <_Io.Writer.printValue__anon_4346+0x720>
10000ce80: 11000610    	add	w16, w16, #0x1
10000ce84: f10011ff    	cmp	x15, #0x4
10000ce88: aa0e03ef    	mov	x15, x14
10000ce8c: 54ffff08    	b.hi	0x10000ce6c <_Io.Writer.printValue__anon_4346+0x6f8>
10000ce90: 52800010    	mov	w16, #0x0               ; =0
10000ce94: 5280000e    	mov	w14, #0x0               ; =0
10000ce98: 6b09021f    	cmp	w16, w9
10000ce9c: 1a9f37ef    	cset	w15, hs
10000cea0: 17ffff44    	b	0x10000cbb0 <_Io.Writer.printValue__anon_4346+0x43c>
10000cea4: 52800010    	mov	w16, #0x0               ; =0
10000cea8: b202e7ea    	mov	x10, #-0x3333333333333334 ; =-3689348814741910324
10000ceac: f29999aa    	movk	x10, #0xcccd
10000ceb0: 9bca7dcf    	umulh	x15, x14, x10
10000ceb4: d342fdef    	lsr	x15, x15, #2
10000ceb8: 8b0f09f1    	add	x17, x15, x15, lsl #2
10000cebc: eb1101df    	cmp	x14, x17
10000cec0: 540000c1    	b.ne	0x10000ced8 <_Io.Writer.printValue__anon_4346+0x764>
10000cec4: 11000610    	add	w16, w16, #0x1
10000cec8: f10011df    	cmp	x14, #0x4
10000cecc: aa0f03ee    	mov	x14, x15
10000ced0: 54ffff08    	b.hi	0x10000ceb0 <_Io.Writer.printValue__anon_4346+0x73c>
10000ced4: 52800010    	mov	w16, #0x0               ; =0
10000ced8: 5280000a    	mov	w10, #0x0               ; =0
10000cedc: 5280000f    	mov	w15, #0x0               ; =0
10000cee0: 5280000e    	mov	w14, #0x0               ; =0
10000cee4: 6b09021f    	cmp	w16, w9
10000cee8: 1a9f37f0    	cset	w16, hs
10000ceec: cb1001ad    	sub	x13, x13, x16
10000cef0: 17ffff30    	b	0x10000cbb0 <_Io.Writer.printValue__anon_4346+0x43c>
10000cef4: d29cffe8    	mov	x8, #0xe7ff             ; =59391
10000cef8: f2a90ec8    	movk	x8, #0x4876, lsl #16
10000cefc: f2c002e8    	movk	x8, #0x17, lsl #32
10000cf00: eb08035f    	cmp	x26, x8
10000cf04: 54000149    	b.ls	0x10000cf2c <_Io.Writer.printValue__anon_4346+0x7b8>
10000cf08: 5280019b    	mov	w27, #0xc               ; =12
10000cf0c: 1400006d    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000cf10: d29cffe9    	mov	x9, #0xe7ff             ; =59391
10000cf14: f2a90ec9    	movk	x9, #0x4876, lsl #16
10000cf18: f2c002e9    	movk	x9, #0x17, lsl #32
10000cf1c: eb09011f    	cmp	x8, x9
10000cf20: 54000149    	b.ls	0x10000cf48 <_Io.Writer.printValue__anon_4346+0x7d4>
10000cf24: 5280019b    	mov	w27, #0xc               ; =12
10000cf28: 14000264    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000cf2c: d29c7fe8    	mov	x8, #0xe3ff             ; =58367
10000cf30: f2aa8168    	movk	x8, #0x540b, lsl #16
10000cf34: f2c00048    	movk	x8, #0x2, lsl #32
10000cf38: eb08035f    	cmp	x26, x8
10000cf3c: 54000149    	b.ls	0x10000cf64 <_Io.Writer.printValue__anon_4346+0x7f0>
10000cf40: 5280017b    	mov	w27, #0xb               ; =11
10000cf44: 1400005f    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000cf48: d29c7fe9    	mov	x9, #0xe3ff             ; =58367
10000cf4c: f2aa8169    	movk	x9, #0x540b, lsl #16
10000cf50: f2c00049    	movk	x9, #0x2, lsl #32
10000cf54: eb09011f    	cmp	x8, x9
10000cf58: 54000129    	b.ls	0x10000cf7c <_Io.Writer.printValue__anon_4346+0x808>
10000cf5c: 5280017b    	mov	w27, #0xb               ; =11
10000cf60: 14000256    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000cf64: 52993fe8    	mov	w8, #0xc9ff             ; =51711
10000cf68: 72a77348    	movk	w8, #0x3b9a, lsl #16
10000cf6c: eb08035f    	cmp	x26, x8
10000cf70: 54000129    	b.ls	0x10000cf94 <_Io.Writer.printValue__anon_4346+0x820>
10000cf74: 5280015b    	mov	w27, #0xa               ; =10
10000cf78: 14000052    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000cf7c: 52993fe9    	mov	w9, #0xc9ff             ; =51711
10000cf80: 72a77349    	movk	w9, #0x3b9a, lsl #16
10000cf84: eb09011f    	cmp	x8, x9
10000cf88: 54000129    	b.ls	0x10000cfac <_Io.Writer.printValue__anon_4346+0x838>
10000cf8c: 5280015b    	mov	w27, #0xa               ; =10
10000cf90: 1400024a    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000cf94: 529c1fe8    	mov	w8, #0xe0ff             ; =57599
10000cf98: 72a0bea8    	movk	w8, #0x5f5, lsl #16
10000cf9c: eb08035f    	cmp	x26, x8
10000cfa0: 54000129    	b.ls	0x10000cfc4 <_Io.Writer.printValue__anon_4346+0x850>
10000cfa4: 5280013b    	mov	w27, #0x9               ; =9
10000cfa8: 14000046    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000cfac: 529c1fe9    	mov	w9, #0xe0ff             ; =57599
10000cfb0: 72a0bea9    	movk	w9, #0x5f5, lsl #16
10000cfb4: eb09011f    	cmp	x8, x9
10000cfb8: 54000129    	b.ls	0x10000cfdc <_Io.Writer.printValue__anon_4346+0x868>
10000cfbc: 5280013b    	mov	w27, #0x9               ; =9
10000cfc0: 1400023e    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000cfc4: 5292cfe8    	mov	w8, #0x967f             ; =38527
10000cfc8: 72a01308    	movk	w8, #0x98, lsl #16
10000cfcc: eb08035f    	cmp	x26, x8
10000cfd0: 54000129    	b.ls	0x10000cff4 <_Io.Writer.printValue__anon_4346+0x880>
10000cfd4: 5280011b    	mov	w27, #0x8               ; =8
10000cfd8: 1400003a    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000cfdc: 5292cfe9    	mov	w9, #0x967f             ; =38527
10000cfe0: 72a01309    	movk	w9, #0x98, lsl #16
10000cfe4: eb09011f    	cmp	x8, x9
10000cfe8: 54000129    	b.ls	0x10000d00c <_Io.Writer.printValue__anon_4346+0x898>
10000cfec: 5280011b    	mov	w27, #0x8               ; =8
10000cff0: 14000232    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000cff4: 528847e8    	mov	w8, #0x423f             ; =16959
10000cff8: 72a001e8    	movk	w8, #0xf, lsl #16
10000cffc: eb08035f    	cmp	x26, x8
10000d000: 54000129    	b.ls	0x10000d024 <_Io.Writer.printValue__anon_4346+0x8b0>
10000d004: 528000fb    	mov	w27, #0x7               ; =7
10000d008: 1400002e    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000d00c: 528847e9    	mov	w9, #0x423f             ; =16959
10000d010: 72a001e9    	movk	w9, #0xf, lsl #16
10000d014: eb09011f    	cmp	x8, x9
10000d018: 54000109    	b.ls	0x10000d038 <_Io.Writer.printValue__anon_4346+0x8c4>
10000d01c: 528000fb    	mov	w27, #0x7               ; =7
10000d020: 14000226    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000d024: d345ff48    	lsr	x8, x26, #5
10000d028: f130d11f    	cmp	x8, #0xc34
10000d02c: 54000109    	b.ls	0x10000d04c <_Io.Writer.printValue__anon_4346+0x8d8>
10000d030: 528000db    	mov	w27, #0x6               ; =6
10000d034: 14000023    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000d038: d345fd09    	lsr	x9, x8, #5
10000d03c: f130d13f    	cmp	x9, #0xc34
10000d040: 54000109    	b.ls	0x10000d060 <_Io.Writer.printValue__anon_4346+0x8ec>
10000d044: 528000db    	mov	w27, #0x6               ; =6
10000d048: 1400021c    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000d04c: d344ff48    	lsr	x8, x26, #4
10000d050: f109c11f    	cmp	x8, #0x270
10000d054: 54000109    	b.ls	0x10000d074 <_Io.Writer.printValue__anon_4346+0x900>
10000d058: 528000bb    	mov	w27, #0x5               ; =5
10000d05c: 14000019    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000d060: d344fd09    	lsr	x9, x8, #4
10000d064: f109c13f    	cmp	x9, #0x270
10000d068: 540000e9    	b.ls	0x10000d084 <_Io.Writer.printValue__anon_4346+0x910>
10000d06c: 528000bb    	mov	w27, #0x5               ; =5
10000d070: 14000212    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000d074: f10f9f5f    	cmp	x26, #0x3e7
10000d078: 540000e9    	b.ls	0x10000d094 <_Io.Writer.printValue__anon_4346+0x920>
10000d07c: 5280009b    	mov	w27, #0x4               ; =4
10000d080: 14000010    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000d084: f10f9d1f    	cmp	x8, #0x3e7
10000d088: 540000e9    	b.ls	0x10000d0a4 <_Io.Writer.printValue__anon_4346+0x930>
10000d08c: 5280009b    	mov	w27, #0x4               ; =4
10000d090: 1400020a    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000d094: f1018f5f    	cmp	x26, #0x63
10000d098: 540000e9    	b.ls	0x10000d0b4 <_Io.Writer.printValue__anon_4346+0x940>
10000d09c: 5280007b    	mov	w27, #0x3               ; =3
10000d0a0: 14000008    	b	0x10000d0c0 <_Io.Writer.printValue__anon_4346+0x94c>
10000d0a4: f1018d1f    	cmp	x8, #0x63
10000d0a8: 54004029    	b.ls	0x10000d8ac <_Io.Writer.printValue__anon_4346+0x1138>
10000d0ac: 5280007b    	mov	w27, #0x3               ; =3
10000d0b0: 14000202    	b	0x10000d8b8 <_Io.Writer.printValue__anon_4346+0x1144>
10000d0b4: f100275f    	cmp	x26, #0x9
10000d0b8: 52800028    	mov	w8, #0x1                ; =1
10000d0bc: 1a88951b    	cinc	w27, w8, hi
10000d0c0: b9401b28    	ldr	w8, [x25, #0x18]
10000d0c4: 37f80128    	tbnz	w8, #0x1f, 0x10000d0e8 <_Io.Writer.printValue__anon_4346+0x974>
10000d0c8: 7100031f    	cmp	w24, #0x0
10000d0cc: 9a9403e9    	csel	x9, xzr, x20, eq
10000d0d0: 8b3b4129    	add	x9, x9, w27, uxtw
10000d0d4: 8b090109    	add	x9, x8, x9
10000d0d8: 91000929    	add	x9, x9, #0x2
10000d0dc: f1056d3f    	cmp	x9, #0x15b
10000d0e0: 54000149    	b.ls	0x10000d108 <_Io.Writer.printValue__anon_4346+0x994>
10000d0e4: 140001f8    	b	0x10000d8c4 <_Io.Writer.printValue__anon_4346+0x1150>
10000d0e8: 4b080369    	sub	w9, w27, w8
10000d0ec: eb14013f    	cmp	x9, x20
10000d0f0: 9a94812a    	csel	x10, x9, x20, hi
10000d0f4: 7100031f    	cmp	w24, #0x0
10000d0f8: 9a8a0129    	csel	x9, x9, x10, eq
10000d0fc: 91000929    	add	x9, x9, #0x2
10000d100: f1056d3f    	cmp	x9, #0x15b
10000d104: 54003e08    	b.hi	0x10000d8c4 <_Io.Writer.printValue__anon_4346+0x1150>
10000d108: 3859c3a9    	ldurb	w9, [x29, #-0x64]
10000d10c: 36000509    	tbz	w9, #0x0, 0x10000d1ac <_Io.Writer.printValue__anon_4346+0xa38>
10000d110: 528005a9    	mov	w9, #0x2d               ; =45
10000d114: 390077e9    	strb	w9, [sp, #0x1d]
10000d118: 52800039    	mov	w25, #0x1               ; =1
10000d11c: 0b1b011c    	add	w28, w8, w27
10000d120: 7100079f    	cmp	w28, #0x1
10000d124: 540004eb    	b.lt	0x10000d1c0 <_Io.Writer.printValue__anon_4346+0xa4c>
10000d128: 2a1b03e8    	mov	w8, w27
10000d12c: 6b1b039f    	cmp	w28, w27
10000d130: 540015a2    	b.hs	0x10000d3e4 <_Io.Writer.printValue__anon_4346+0xc70>
10000d134: 8b1c0329    	add	x9, x25, x28
10000d138: cb1c010a    	sub	x10, x8, x28
10000d13c: f1000d5f    	cmp	x10, #0x3
10000d140: 54002483    	b.lo	0x10000d5d0 <_Io.Writer.printValue__anon_4346+0xe5c>
10000d144: d280000c    	mov	x12, #0x0               ; =0
10000d148: 910077eb    	add	x11, sp, #0x1d
10000d14c: 8b08032d    	add	x13, x25, x8
10000d150: 8b0d016b    	add	x11, x11, x13
10000d154: d29eb86d    	mov	x13, #0xf5c3            ; =62915
10000d158: f2ab850d    	movk	x13, #0x5c28, lsl #16
10000d15c: f2d851ed    	movk	x13, #0xc28f, lsl #32
10000d160: f2e51ead    	movk	x13, #0x28f5, lsl #48
10000d164: 52800c8e    	mov	w14, #0x64              ; =100
10000d168: aa1a03f1    	mov	x17, x26
10000d16c: d000002f    	adrp	x15, 0x100013000 <___anon_5016+0x2840>
10000d170: 9108d9ef    	add	x15, x15, #0x236
10000d174: d342fe30    	lsr	x16, x17, #2
10000d178: 9bcd7e10    	umulh	x16, x16, x13
10000d17c: d342fe1a    	lsr	x26, x16, #2
10000d180: 9b0ec750    	msub	x16, x26, x14, x17
10000d184: 787079f0    	ldrh	w16, [x15, x16, lsl #1]
10000d188: 781ff170    	sturh	w16, [x11, #-0x1]
10000d18c: 91000990    	add	x16, x12, #0x2
10000d190: d100096b    	sub	x11, x11, #0x2
10000d194: 91001180    	add	x0, x12, #0x4
10000d198: aa1003ec    	mov	x12, x16
10000d19c: aa1a03f1    	mov	x17, x26
10000d1a0: eb0a001f    	cmp	x0, x10
10000d1a4: 54fffe83    	b.lo	0x10000d174 <_Io.Writer.printValue__anon_4346+0xa00>
10000d1a8: 1400010b    	b	0x10000d5d4 <_Io.Writer.printValue__anon_4346+0xe60>
10000d1ac: d2800019    	mov	x25, #0x0               ; =0
10000d1b0: 910077f5    	add	x21, sp, #0x1d
10000d1b4: 0b1b011c    	add	w28, w8, w27
10000d1b8: 7100079f    	cmp	w28, #0x1
10000d1bc: 54fffb6a    	b.ge	0x10000d128 <_Io.Writer.printValue__anon_4346+0x9b4>
10000d1c0: 910077e9    	add	x9, sp, #0x1d
10000d1c4: 52800608    	mov	w8, #0x30               ; =48
10000d1c8: 38396928    	strb	w8, [x9, x25]
10000d1cc: 528005c8    	mov	w8, #0x2e               ; =46
10000d1d0: 390006a8    	strb	w8, [x21, #0x1]
10000d1d4: f90007f9    	str	x25, [sp, #0x8]
10000d1d8: b27f0339    	orr	x25, x25, #0x2
10000d1dc: 4b1c03f5    	neg	w21, w28
10000d1e0: 910077fc    	add	x28, sp, #0x1d
10000d1e4: 8b190380    	add	x0, x28, x25
10000d1e8: 52800601    	mov	w1, #0x30               ; =48
10000d1ec: aa1503e2    	mov	x2, x21
10000d1f0: 940008f8    	bl	0x10000f5d0 <dyld_stub_binder+0x10000f5d0>
10000d1f4: 8b150328    	add	x8, x25, x21
10000d1f8: 2a1b03e9    	mov	w9, w27
10000d1fc: 71000b7f    	cmp	w27, #0x2
10000d200: 54001e49    	b.ls	0x10000d5c8 <_Io.Writer.printValue__anon_4346+0xe54>
10000d204: d342ff4a    	lsr	x10, x26, #2
10000d208: d29eb86b    	mov	x11, #0xf5c3            ; =62915
10000d20c: f2ab850b    	movk	x11, #0x5c28, lsl #16
10000d210: f2d851eb    	movk	x11, #0xc28f, lsl #32
10000d214: f2e51eab    	movk	x11, #0x28f5, lsl #48
10000d218: 9bcb7d4a    	umulh	x10, x10, x11
10000d21c: d342fd4c    	lsr	x12, x10, #2
10000d220: 52800c8a    	mov	w10, #0x64              ; =100
10000d224: 9b0ae98b    	msub	x11, x12, x10, x26
10000d228: d000002a    	adrp	x10, 0x100013000 <___anon_5016+0x2840>
10000d22c: 9108d94a    	add	x10, x10, #0x236
10000d230: 786b794d    	ldrh	w13, [x10, x11, lsl #1]
10000d234: 8b08038b    	add	x11, x28, x8
10000d238: 8b09016e    	add	x14, x11, x9
10000d23c: 781fe1cd    	sturh	w13, [x14, #-0x2]
10000d240: 7100177f    	cmp	w27, #0x5
10000d244: 540026e3    	b.lo	0x10000d720 <_Io.Writer.printValue__anon_4346+0xfac>
10000d248: d283d72d    	mov	x13, #0x1eb9            ; =7865
10000d24c: f2bd70ad    	movk	x13, #0xeb85, lsl #16
10000d250: f2d70a2d    	movk	x13, #0xb851, lsl #32
10000d254: f2e0a3cd    	movk	x13, #0x51e, lsl #48
10000d258: 9bcd7d8d    	umulh	x13, x12, x13
10000d25c: d341fdad    	lsr	x13, x13, #1
10000d260: 52800c8f    	mov	w15, #0x64              ; =100
10000d264: 9b0fb1ac    	msub	x12, x13, x15, x12
10000d268: d28b296d    	mov	x13, #0x594b            ; =22859
10000d26c: f2a710cd    	movk	x13, #0x3886, lsl #16
10000d270: f2d8bacd    	movk	x13, #0xc5d6, lsl #32
10000d274: f2e68dad    	movk	x13, #0x346d, lsl #48
10000d278: 9bcd7f4d    	umulh	x13, x26, x13
10000d27c: d34bfdad    	lsr	x13, x13, #11
10000d280: 786c794c    	ldrh	w12, [x10, x12, lsl #1]
10000d284: 781fc1cc    	sturh	w12, [x14, #-0x4]
10000d288: 71001f7f    	cmp	w27, #0x7
10000d28c: 54002563    	b.lo	0x10000d738 <_Io.Writer.printValue__anon_4346+0xfc4>
10000d290: d291ebac    	mov	x12, #0x8f5d            ; =36701
10000d294: f2beb84c    	movk	x12, #0xf5c2, lsl #16
10000d298: f2cb850c    	movk	x12, #0x5c28, lsl #32
10000d29c: f2e051ec    	movk	x12, #0x28f, lsl #48
10000d2a0: 9bcc7dae    	umulh	x14, x13, x12
10000d2a4: 52800c8f    	mov	w15, #0x64              ; =100
10000d2a8: 9b0fb5ce    	msub	x14, x14, x15, x13
10000d2ac: d2869b6d    	mov	x13, #0x34db            ; =13531
10000d2b0: f2baf6cd    	movk	x13, #0xd7b6, lsl #16
10000d2b4: f2dbd04d    	movk	x13, #0xde82, lsl #32
10000d2b8: f2e8636d    	movk	x13, #0x431b, lsl #48
10000d2bc: 9bcd7f4d    	umulh	x13, x26, x13
10000d2c0: d352fdad    	lsr	x13, x13, #18
10000d2c4: 786e794f    	ldrh	w15, [x10, x14, lsl #1]
10000d2c8: 8b09016e    	add	x14, x11, x9
10000d2cc: 781fa1cf    	sturh	w15, [x14, #-0x6]
10000d2d0: 7100277f    	cmp	w27, #0x9
10000d2d4: 540023a3    	b.lo	0x10000d748 <_Io.Writer.printValue__anon_4346+0xfd4>
10000d2d8: 9bcc7daf    	umulh	x15, x13, x12
10000d2dc: 52800c90    	mov	w16, #0x64              ; =100
10000d2e0: 9b10b5ef    	msub	x15, x15, x16, x13
10000d2e4: d299dfad    	mov	x13, #0xcefd            ; =52989
10000d2e8: f2b08c2d    	movk	x13, #0x8461, lsl #16
10000d2ec: f2cee22d    	movk	x13, #0x7711, lsl #32
10000d2f0: f2f5798d    	movk	x13, #0xabcc, lsl #48
10000d2f4: 9bcd7f4d    	umulh	x13, x26, x13
10000d2f8: d35afdad    	lsr	x13, x13, #26
10000d2fc: 786f794f    	ldrh	w15, [x10, x15, lsl #1]
10000d300: 781f81cf    	sturh	w15, [x14, #-0x8]
10000d304: 71002f7f    	cmp	w27, #0xb
10000d308: 54002283    	b.lo	0x10000d758 <_Io.Writer.printValue__anon_4346+0xfe4>
10000d30c: 9bcc7dae    	umulh	x14, x13, x12
10000d310: 52800c8f    	mov	w15, #0x64              ; =100
10000d314: 9bafb5ce    	umsubl	x14, w14, w15, x13
10000d318: d29ab7ed    	mov	x13, #0xd5bf            ; =54719
10000d31c: f2b7bdad    	movk	x13, #0xbded, lsl #16
10000d320: f2dfd9cd    	movk	x13, #0xfece, lsl #32
10000d324: f2fb7ccd    	movk	x13, #0xdbe6, lsl #48
10000d328: 9bcd7f4d    	umulh	x13, x26, x13
10000d32c: d361fdad    	lsr	x13, x13, #33
10000d330: 786e794f    	ldrh	w15, [x10, x14, lsl #1]
10000d334: 8b09016e    	add	x14, x11, x9
10000d338: 781f61cf    	sturh	w15, [x14, #-0xa]
10000d33c: 7100377f    	cmp	w27, #0xd
10000d340: 54002143    	b.lo	0x10000d768 <_Io.Writer.printValue__anon_4346+0xff4>
10000d344: 9bcc7daf    	umulh	x15, x13, x12
10000d348: 52800c90    	mov	w16, #0x64              ; =100
10000d34c: 9bb0b5ef    	umsubl	x15, w15, w16, x13
10000d350: d284466d    	mov	x13, #0x2233            ; =8755
10000d354: f2ab7a8d    	movk	x13, #0x5bd4, lsl #16
10000d358: f2c6604d    	movk	x13, #0x3302, lsl #32
10000d35c: f2e465ed    	movk	x13, #0x232f, lsl #48
10000d360: 9bcd7f4d    	umulh	x13, x26, x13
10000d364: d365fdad    	lsr	x13, x13, #37
10000d368: 786f794f    	ldrh	w15, [x10, x15, lsl #1]
10000d36c: 781f41cf    	sturh	w15, [x14, #-0xc]
10000d370: 71003f7f    	cmp	w27, #0xf
10000d374: 54002023    	b.lo	0x10000d778 <_Io.Writer.printValue__anon_4346+0x1004>
10000d378: 9bcc7dae    	umulh	x14, x13, x12
10000d37c: 52800c8f    	mov	w15, #0x64              ; =100
10000d380: 9bafb5ce    	umsubl	x14, w14, w15, x13
10000d384: d299b02d    	mov	x13, #0xcd81            ; =52609
10000d388: f2aa12ad    	movk	x13, #0x5095, lsl #16
10000d38c: f2c9b86d    	movk	x13, #0x4dc3, lsl #32
10000d390: f2e1684d    	movk	x13, #0xb42, lsl #48
10000d394: 9bcd7f4d    	umulh	x13, x26, x13
10000d398: d36afdad    	lsr	x13, x13, #42
10000d39c: 786e794e    	ldrh	w14, [x10, x14, lsl #1]
10000d3a0: 8b09016b    	add	x11, x11, x9
10000d3a4: 781f216e    	sturh	w14, [x11, #-0xe]
10000d3a8: 7100477f    	cmp	w27, #0x11
10000d3ac: 54001ee3    	b.lo	0x10000d788 <_Io.Writer.printValue__anon_4346+0x1014>
10000d3b0: 9bcc7dac    	umulh	x12, x13, x12
10000d3b4: 52800c8e    	mov	w14, #0x64              ; =100
10000d3b8: 9baeb58c    	umsubl	x12, w12, w14, x13
10000d3bc: d28f0aed    	mov	x13, #0x7857            ; =30807
10000d3c0: f2b6226d    	movk	x13, #0xb113, lsl #16
10000d3c4: f2cca5ed    	movk	x13, #0x652f, lsl #32
10000d3c8: f2e734ad    	movk	x13, #0x39a5, lsl #48
10000d3cc: 9bcd7f4d    	umulh	x13, x26, x13
10000d3d0: d373fdba    	lsr	x26, x13, #51
10000d3d4: 786c794a    	ldrh	w10, [x10, x12, lsl #1]
10000d3d8: 781f016a    	sturh	w10, [x11, #-0x10]
10000d3dc: 5280020a    	mov	w10, #0x10              ; =16
10000d3e0: 140000ec    	b	0x10000d790 <_Io.Writer.printValue__anon_4346+0x101c>
10000d3e4: 71000b7f    	cmp	w27, #0x2
10000d3e8: 540011e9    	b.ls	0x10000d624 <_Io.Writer.printValue__anon_4346+0xeb0>
10000d3ec: d342ff49    	lsr	x9, x26, #2
10000d3f0: d29eb86a    	mov	x10, #0xf5c3            ; =62915
10000d3f4: f2ab850a    	movk	x10, #0x5c28, lsl #16
10000d3f8: f2d851ea    	movk	x10, #0xc28f, lsl #32
10000d3fc: f2e51eaa    	movk	x10, #0x28f5, lsl #48
10000d400: 9bca7d29    	umulh	x9, x9, x10
10000d404: d342fd2a    	lsr	x10, x9, #2
10000d408: 52800c8b    	mov	w11, #0x64              ; =100
10000d40c: d0000029    	adrp	x9, 0x100013000 <___anon_5016+0x2840>
10000d410: 9108d929    	add	x9, x9, #0x236
10000d414: 9b0be94b    	msub	x11, x10, x11, x26
10000d418: 786b792b    	ldrh	w11, [x9, x11, lsl #1]
10000d41c: 8b0802ac    	add	x12, x21, x8
10000d420: 781fe18b    	sturh	w11, [x12, #-0x2]
10000d424: 7100177f    	cmp	w27, #0x5
10000d428: 54001823    	b.lo	0x10000d72c <_Io.Writer.printValue__anon_4346+0xfb8>
10000d42c: d283d72b    	mov	x11, #0x1eb9            ; =7865
10000d430: f2bd70ab    	movk	x11, #0xeb85, lsl #16
10000d434: f2d70a2b    	movk	x11, #0xb851, lsl #32
10000d438: f2e0a3cb    	movk	x11, #0x51e, lsl #48
10000d43c: 9bcb7d4b    	umulh	x11, x10, x11
10000d440: d341fd6b    	lsr	x11, x11, #1
10000d444: 52800c8d    	mov	w13, #0x64              ; =100
10000d448: 9b0da96a    	msub	x10, x11, x13, x10
10000d44c: d28b296b    	mov	x11, #0x594b            ; =22859
10000d450: f2a710cb    	movk	x11, #0x3886, lsl #16
10000d454: f2d8bacb    	movk	x11, #0xc5d6, lsl #32
10000d458: f2e68dab    	movk	x11, #0x346d, lsl #48
10000d45c: 9bcb7f4b    	umulh	x11, x26, x11
10000d460: d34bfd6b    	lsr	x11, x11, #11
10000d464: 786a792a    	ldrh	w10, [x9, x10, lsl #1]
10000d468: 781fc18a    	sturh	w10, [x12, #-0x4]
10000d46c: 71001f7f    	cmp	w27, #0x7
10000d470: 54001683    	b.lo	0x10000d740 <_Io.Writer.printValue__anon_4346+0xfcc>
10000d474: d291ebaa    	mov	x10, #0x8f5d            ; =36701
10000d478: f2beb84a    	movk	x10, #0xf5c2, lsl #16
10000d47c: f2cb850a    	movk	x10, #0x5c28, lsl #32
10000d480: f2e051ea    	movk	x10, #0x28f, lsl #48
10000d484: 9bca7d6c    	umulh	x12, x11, x10
10000d488: 52800c8d    	mov	w13, #0x64              ; =100
10000d48c: 9b0dad8c    	msub	x12, x12, x13, x11
10000d490: d2869b6b    	mov	x11, #0x34db            ; =13531
10000d494: f2baf6cb    	movk	x11, #0xd7b6, lsl #16
10000d498: f2dbd04b    	movk	x11, #0xde82, lsl #32
10000d49c: f2e8636b    	movk	x11, #0x431b, lsl #48
10000d4a0: 9bcb7f4b    	umulh	x11, x26, x11
10000d4a4: d352fd6b    	lsr	x11, x11, #18
10000d4a8: 786c792d    	ldrh	w13, [x9, x12, lsl #1]
10000d4ac: 8b0802ac    	add	x12, x21, x8
10000d4b0: 781fa18d    	sturh	w13, [x12, #-0x6]
10000d4b4: 7100277f    	cmp	w27, #0x9
10000d4b8: 540014c3    	b.lo	0x10000d750 <_Io.Writer.printValue__anon_4346+0xfdc>
10000d4bc: 9bca7d6d    	umulh	x13, x11, x10
10000d4c0: 52800c8e    	mov	w14, #0x64              ; =100
10000d4c4: 9b0eadad    	msub	x13, x13, x14, x11
10000d4c8: d299dfab    	mov	x11, #0xcefd            ; =52989
10000d4cc: f2b08c2b    	movk	x11, #0x8461, lsl #16
10000d4d0: f2cee22b    	movk	x11, #0x7711, lsl #32
10000d4d4: f2f5798b    	movk	x11, #0xabcc, lsl #48
10000d4d8: 9bcb7f4b    	umulh	x11, x26, x11
10000d4dc: d35afd6b    	lsr	x11, x11, #26
10000d4e0: 786d792d    	ldrh	w13, [x9, x13, lsl #1]
10000d4e4: 781f818d    	sturh	w13, [x12, #-0x8]
10000d4e8: 71002f7f    	cmp	w27, #0xb
10000d4ec: 540013a3    	b.lo	0x10000d760 <_Io.Writer.printValue__anon_4346+0xfec>
10000d4f0: 9bca7d6c    	umulh	x12, x11, x10
10000d4f4: 52800c8d    	mov	w13, #0x64              ; =100
10000d4f8: 9badad8c    	umsubl	x12, w12, w13, x11
10000d4fc: d29ab7eb    	mov	x11, #0xd5bf            ; =54719
10000d500: f2b7bdab    	movk	x11, #0xbded, lsl #16
10000d504: f2dfd9cb    	movk	x11, #0xfece, lsl #32
10000d508: f2fb7ccb    	movk	x11, #0xdbe6, lsl #48
10000d50c: 9bcb7f4b    	umulh	x11, x26, x11
10000d510: d361fd6b    	lsr	x11, x11, #33
10000d514: 786c792d    	ldrh	w13, [x9, x12, lsl #1]
10000d518: 8b0802ac    	add	x12, x21, x8
10000d51c: 781f618d    	sturh	w13, [x12, #-0xa]
10000d520: 7100377f    	cmp	w27, #0xd
10000d524: 54001263    	b.lo	0x10000d770 <_Io.Writer.printValue__anon_4346+0xffc>
10000d528: 9bca7d6d    	umulh	x13, x11, x10
10000d52c: 52800c8e    	mov	w14, #0x64              ; =100
10000d530: 9baeadad    	umsubl	x13, w13, w14, x11
10000d534: d284466b    	mov	x11, #0x2233            ; =8755
10000d538: f2ab7a8b    	movk	x11, #0x5bd4, lsl #16
10000d53c: f2c6604b    	movk	x11, #0x3302, lsl #32
10000d540: f2e465eb    	movk	x11, #0x232f, lsl #48
10000d544: 9bcb7f4b    	umulh	x11, x26, x11
10000d548: d365fd6b    	lsr	x11, x11, #37
10000d54c: 786d792d    	ldrh	w13, [x9, x13, lsl #1]
10000d550: 781f418d    	sturh	w13, [x12, #-0xc]
10000d554: 71003f7f    	cmp	w27, #0xf
10000d558: 54001143    	b.lo	0x10000d780 <_Io.Writer.printValue__anon_4346+0x100c>
10000d55c: 9bca7d6c    	umulh	x12, x11, x10
10000d560: 52800c8d    	mov	w13, #0x64              ; =100
10000d564: 9badad8c    	umsubl	x12, w12, w13, x11
10000d568: d299b02b    	mov	x11, #0xcd81            ; =52609
10000d56c: f2aa12ab    	movk	x11, #0x5095, lsl #16
10000d570: f2c9b86b    	movk	x11, #0x4dc3, lsl #32
10000d574: f2e1684b    	movk	x11, #0xb42, lsl #48
10000d578: 9bcb7f4b    	umulh	x11, x26, x11
10000d57c: d36afd6b    	lsr	x11, x11, #42
10000d580: 786c792d    	ldrh	w13, [x9, x12, lsl #1]
10000d584: 8b0802ac    	add	x12, x21, x8
10000d588: 781f218d    	sturh	w13, [x12, #-0xe]
10000d58c: 7100477f    	cmp	w27, #0x11
10000d590: 54001463    	b.lo	0x10000d81c <_Io.Writer.printValue__anon_4346+0x10a8>
10000d594: 9bca7d6a    	umulh	x10, x11, x10
10000d598: 52800c8d    	mov	w13, #0x64              ; =100
10000d59c: 9badad4a    	umsubl	x10, w10, w13, x11
10000d5a0: d28f0aeb    	mov	x11, #0x7857            ; =30807
10000d5a4: f2b6226b    	movk	x11, #0xb113, lsl #16
10000d5a8: f2cca5eb    	movk	x11, #0x652f, lsl #32
10000d5ac: f2e734ab    	movk	x11, #0x39a5, lsl #48
10000d5b0: 9bcb7f4b    	umulh	x11, x26, x11
10000d5b4: d373fd7a    	lsr	x26, x11, #51
10000d5b8: 786a7929    	ldrh	w9, [x9, x10, lsl #1]
10000d5bc: 781f0189    	sturh	w9, [x12, #-0x10]
10000d5c0: 52800209    	mov	w9, #0x10               ; =16
10000d5c4: 14000098    	b	0x10000d824 <_Io.Writer.printValue__anon_4346+0x10b0>
10000d5c8: d280000a    	mov	x10, #0x0               ; =0
10000d5cc: 14000073    	b	0x10000d798 <_Io.Writer.printValue__anon_4346+0x1024>
10000d5d0: d2800010    	mov	x16, #0x0               ; =0
10000d5d4: eb0a021f    	cmp	x16, x10
10000d5d8: 540002a2    	b.hs	0x10000d62c <_Io.Writer.printValue__anon_4346+0xeb8>
10000d5dc: 8b1c020b    	add	x11, x16, x28
10000d5e0: cb08016b    	sub	x11, x11, x8
10000d5e4: 8b080328    	add	x8, x25, x8
10000d5e8: cb100108    	sub	x8, x8, x16
10000d5ec: 910077ec    	add	x12, sp, #0x1d
10000d5f0: 8b08018c    	add	x12, x12, x8
10000d5f4: b202e7ed    	mov	x13, #-0x3333333333333334 ; =-3689348814741910324
10000d5f8: f29999ad    	movk	x13, #0xcccd
10000d5fc: 5280014e    	mov	w14, #0xa               ; =10
10000d600: 9bcd7f48    	umulh	x8, x26, x13
10000d604: d343fd08    	lsr	x8, x8, #3
10000d608: 1b0ee90f    	msub	w15, w8, w14, w26
10000d60c: 321c05ef    	orr	w15, w15, #0x30
10000d610: 381ff58f    	strb	w15, [x12], #-0x1
10000d614: aa0803fa    	mov	x26, x8
10000d618: b100056b    	adds	x11, x11, #0x1
10000d61c: 54ffff23    	b.lo	0x10000d600 <_Io.Writer.printValue__anon_4346+0xe8c>
10000d620: 14000004    	b	0x10000d630 <_Io.Writer.printValue__anon_4346+0xebc>
10000d624: d2800009    	mov	x9, #0x0                ; =0
10000d628: 14000081    	b	0x10000d82c <_Io.Writer.printValue__anon_4346+0x10b8>
10000d62c: aa1a03e8    	mov	x8, x26
10000d630: 910077eb    	add	x11, sp, #0x1d
10000d634: 528005cc    	mov	w12, #0x2e              ; =46
10000d638: 3829696c    	strb	w12, [x11, x9]
10000d63c: 71000f9f    	cmp	w28, #0x3
10000d640: 54000343    	b.lo	0x10000d6a8 <_Io.Writer.printValue__anon_4346+0xf34>
10000d644: d280000c    	mov	x12, #0x0               ; =0
10000d648: 8b15038b    	add	x11, x28, x21
10000d64c: d100056b    	sub	x11, x11, #0x1
10000d650: d29eb86d    	mov	x13, #0xf5c3            ; =62915
10000d654: f2ab850d    	movk	x13, #0x5c28, lsl #16
10000d658: f2d851ed    	movk	x13, #0xc28f, lsl #32
10000d65c: f2e51ead    	movk	x13, #0x28f5, lsl #48
10000d660: 52800c8e    	mov	w14, #0x64              ; =100
10000d664: d000002f    	adrp	x15, 0x100013000 <___anon_5016+0x2840>
10000d668: 9108d9ef    	add	x15, x15, #0x236
10000d66c: aa0803f1    	mov	x17, x8
10000d670: d342fe28    	lsr	x8, x17, #2
10000d674: 9bcd7d08    	umulh	x8, x8, x13
10000d678: d342fd08    	lsr	x8, x8, #2
10000d67c: 9b0ec510    	msub	x16, x8, x14, x17
10000d680: 787079f0    	ldrh	w16, [x15, x16, lsl #1]
10000d684: 781ff170    	sturh	w16, [x11, #-0x1]
10000d688: 91000990    	add	x16, x12, #0x2
10000d68c: d100096b    	sub	x11, x11, #0x2
10000d690: 91001180    	add	x0, x12, #0x4
10000d694: aa1003ec    	mov	x12, x16
10000d698: aa0803f1    	mov	x17, x8
10000d69c: eb1c001f    	cmp	x0, x28
10000d6a0: 54fffe83    	b.lo	0x10000d670 <_Io.Writer.printValue__anon_4346+0xefc>
10000d6a4: 14000002    	b	0x10000d6ac <_Io.Writer.printValue__anon_4346+0xf38>
10000d6a8: d2800010    	mov	x16, #0x0               ; =0
10000d6ac: eb10038b    	subs	x11, x28, x16
10000d6b0: 540001a9    	b.ls	0x10000d6e4 <_Io.Writer.printValue__anon_4346+0xf70>
10000d6b4: d10006ac    	sub	x12, x21, #0x1
10000d6b8: b202e7ed    	mov	x13, #-0x3333333333333334 ; =-3689348814741910324
10000d6bc: f29999ad    	movk	x13, #0xcccd
10000d6c0: 5280014e    	mov	w14, #0xa               ; =10
10000d6c4: 9bcd7d0f    	umulh	x15, x8, x13
10000d6c8: d343fdef    	lsr	x15, x15, #3
10000d6cc: 1b0ea1e8    	msub	w8, w15, w14, w8
10000d6d0: 321c0508    	orr	w8, w8, #0x30
10000d6d4: 382b6988    	strb	w8, [x12, x11]
10000d6d8: aa0f03e8    	mov	x8, x15
10000d6dc: f100056b    	subs	x11, x11, #0x1
10000d6e0: 54ffff21    	b.ne	0x10000d6c4 <_Io.Writer.printValue__anon_4346+0xf50>
10000d6e4: 11000768    	add	w8, w27, #0x1
10000d6e8: 8b080328    	add	x8, x25, x8
10000d6ec: 34000958    	cbz	w24, 0x10000d814 <_Io.Writer.printValue__anon_4346+0x10a0>
10000d6f0: 91000535    	add	x21, x9, #0x1
10000d6f4: eb0a0282    	subs	x2, x20, x10
10000d6f8: 540000a9    	b.ls	0x10000d70c <_Io.Writer.printValue__anon_4346+0xf98>
10000d6fc: 910077e9    	add	x9, sp, #0x1d
10000d700: 8b080120    	add	x0, x9, x8
10000d704: 52800601    	mov	w1, #0x30               ; =48
10000d708: 940007b2    	bl	0x10000f5d0 <dyld_stub_binder+0x10000f5d0>
10000d70c: 52800009    	mov	w9, #0x0                ; =0
10000d710: f100029f    	cmp	x20, #0x0
10000d714: da9f1288    	csinv	x8, x20, xzr, ne
10000d718: 8b0802a8    	add	x8, x21, x8
10000d71c: 1400014c    	b	0x10000dc4c <_Io.Writer.printValue__anon_4346+0x14d8>
10000d720: 5280004a    	mov	w10, #0x2               ; =2
10000d724: aa0c03fa    	mov	x26, x12
10000d728: 1400001a    	b	0x10000d790 <_Io.Writer.printValue__anon_4346+0x101c>
10000d72c: 52800049    	mov	w9, #0x2                ; =2
10000d730: aa0a03fa    	mov	x26, x10
10000d734: 1400003c    	b	0x10000d824 <_Io.Writer.printValue__anon_4346+0x10b0>
10000d738: 5280008a    	mov	w10, #0x4               ; =4
10000d73c: 14000014    	b	0x10000d78c <_Io.Writer.printValue__anon_4346+0x1018>
10000d740: 52800089    	mov	w9, #0x4                ; =4
10000d744: 14000037    	b	0x10000d820 <_Io.Writer.printValue__anon_4346+0x10ac>
10000d748: 528000ca    	mov	w10, #0x6               ; =6
10000d74c: 14000010    	b	0x10000d78c <_Io.Writer.printValue__anon_4346+0x1018>
10000d750: 528000c9    	mov	w9, #0x6                ; =6
10000d754: 14000033    	b	0x10000d820 <_Io.Writer.printValue__anon_4346+0x10ac>
10000d758: 5280010a    	mov	w10, #0x8               ; =8
10000d75c: 1400000c    	b	0x10000d78c <_Io.Writer.printValue__anon_4346+0x1018>
10000d760: 52800109    	mov	w9, #0x8                ; =8
10000d764: 1400002f    	b	0x10000d820 <_Io.Writer.printValue__anon_4346+0x10ac>
10000d768: 5280014a    	mov	w10, #0xa               ; =10
10000d76c: 14000008    	b	0x10000d78c <_Io.Writer.printValue__anon_4346+0x1018>
10000d770: 52800149    	mov	w9, #0xa                ; =10
10000d774: 1400002b    	b	0x10000d820 <_Io.Writer.printValue__anon_4346+0x10ac>
10000d778: 5280018a    	mov	w10, #0xc               ; =12
10000d77c: 14000004    	b	0x10000d78c <_Io.Writer.printValue__anon_4346+0x1018>
10000d780: 52800189    	mov	w9, #0xc                ; =12
10000d784: 14000027    	b	0x10000d820 <_Io.Writer.printValue__anon_4346+0x10ac>
10000d788: 528001ca    	mov	w10, #0xe               ; =14
10000d78c: aa0d03fa    	mov	x26, x13
10000d790: eb09015f    	cmp	x10, x9
10000d794: 54000242    	b.hs	0x10000d7dc <_Io.Writer.printValue__anon_4346+0x1068>
10000d798: cb0a012a    	sub	x10, x9, x10
10000d79c: 9100054a    	add	x10, x10, #0x1
10000d7a0: f94007eb    	ldr	x11, [sp, #0x8]
10000d7a4: 8b15016b    	add	x11, x11, x21
10000d7a8: 8b0b038b    	add	x11, x28, x11
10000d7ac: b202e7ec    	mov	x12, #-0x3333333333333334 ; =-3689348814741910324
10000d7b0: f29999ac    	movk	x12, #0xcccd
10000d7b4: 5280014d    	mov	w13, #0xa               ; =10
10000d7b8: 9bcc7f4e    	umulh	x14, x26, x12
10000d7bc: d343fdce    	lsr	x14, x14, #3
10000d7c0: 1b0de9cf    	msub	w15, w14, w13, w26
10000d7c4: 321c05ef    	orr	w15, w15, #0x30
10000d7c8: 382a696f    	strb	w15, [x11, x10]
10000d7cc: d100054a    	sub	x10, x10, #0x1
10000d7d0: aa0e03fa    	mov	x26, x14
10000d7d4: f100055f    	cmp	x10, #0x1
10000d7d8: 54ffff01    	b.ne	0x10000d7b8 <_Io.Writer.printValue__anon_4346+0x1044>
10000d7dc: 8b090108    	add	x8, x8, x9
10000d7e0: 340001b8    	cbz	w24, 0x10000d814 <_Io.Writer.printValue__anon_4346+0x10a0>
10000d7e4: cb190109    	sub	x9, x8, x25
10000d7e8: eb090282    	subs	x2, x20, x9
10000d7ec: 540000a9    	b.ls	0x10000d800 <_Io.Writer.printValue__anon_4346+0x108c>
10000d7f0: 910077e9    	add	x9, sp, #0x1d
10000d7f4: 8b080120    	add	x0, x9, x8
10000d7f8: 52800601    	mov	w1, #0x30               ; =48
10000d7fc: 94000775    	bl	0x10000f5d0 <dyld_stub_binder+0x10000f5d0>
10000d800: 52800009    	mov	w9, #0x0                ; =0
10000d804: f100029f    	cmp	x20, #0x0
10000d808: da9f1288    	csinv	x8, x20, xzr, ne
10000d80c: 8b080328    	add	x8, x25, x8
10000d810: 1400010f    	b	0x10000dc4c <_Io.Writer.printValue__anon_4346+0x14d8>
10000d814: 52800009    	mov	w9, #0x0                ; =0
10000d818: 1400010d    	b	0x10000dc4c <_Io.Writer.printValue__anon_4346+0x14d8>
10000d81c: 528001c9    	mov	w9, #0xe                ; =14
10000d820: aa0b03fa    	mov	x26, x11
10000d824: eb08013f    	cmp	x9, x8
10000d828: 540001c2    	b.hs	0x10000d860 <_Io.Writer.printValue__anon_4346+0x10ec>
10000d82c: cb090109    	sub	x9, x8, x9
10000d830: d10006aa    	sub	x10, x21, #0x1
10000d834: b202e7eb    	mov	x11, #-0x3333333333333334 ; =-3689348814741910324
10000d838: f29999ab    	movk	x11, #0xcccd
10000d83c: 5280014c    	mov	w12, #0xa               ; =10
10000d840: 9bcb7f4d    	umulh	x13, x26, x11
10000d844: d343fdad    	lsr	x13, x13, #3
10000d848: 1b0ce9ae    	msub	w14, w13, w12, w26
10000d84c: 321c05ce    	orr	w14, w14, #0x30
10000d850: 3829694e    	strb	w14, [x10, x9]
10000d854: aa0d03fa    	mov	x26, x13
10000d858: f1000529    	subs	x9, x9, #0x1
10000d85c: 54ffff21    	b.ne	0x10000d840 <_Io.Writer.printValue__anon_4346+0x10cc>
10000d860: cb080382    	sub	x2, x28, x8
10000d864: 8b0802a0    	add	x0, x21, x8
10000d868: 52800601    	mov	w1, #0x30               ; =48
10000d86c: 94000759    	bl	0x10000f5d0 <dyld_stub_binder+0x10000f5d0>
10000d870: 52800009    	mov	w9, #0x0                ; =0
10000d874: 8b1c0328    	add	x8, x25, x28
10000d878: 34001eb8    	cbz	w24, 0x10000dc4c <_Io.Writer.printValue__anon_4346+0x14d8>
10000d87c: b4001e94    	cbz	x20, 0x10000dc4c <_Io.Writer.printValue__anon_4346+0x14d8>
10000d880: 910077e9    	add	x9, sp, #0x1d
10000d884: 528005ca    	mov	w10, #0x2e              ; =46
10000d888: 3828692a    	strb	w10, [x9, x8]
10000d88c: 91000515    	add	x21, x8, #0x1
10000d890: 8b150120    	add	x0, x9, x21
10000d894: 52800601    	mov	w1, #0x30               ; =48
10000d898: aa1403e2    	mov	x2, x20
10000d89c: 9400074d    	bl	0x10000f5d0 <dyld_stub_binder+0x10000f5d0>
10000d8a0: 52800009    	mov	w9, #0x0                ; =0
10000d8a4: 8b1402a8    	add	x8, x21, x20
10000d8a8: 140000e9    	b	0x10000dc4c <_Io.Writer.printValue__anon_4346+0x14d8>
10000d8ac: f100251f    	cmp	x8, #0x9
10000d8b0: 52800029    	mov	w9, #0x1                ; =1
10000d8b4: 1a89953b    	cinc	w27, w9, hi
10000d8b8: 340000b8    	cbz	w24, 0x10000d8cc <_Io.Writer.printValue__anon_4346+0x1158>
10000d8bc: f1054e9f    	cmp	x20, #0x153
10000d8c0: 54000069    	b.ls	0x10000d8cc <_Io.Writer.printValue__anon_4346+0x1158>
10000d8c4: 52800589    	mov	w9, #0x2c               ; =44
10000d8c8: 140000e1    	b	0x10000dc4c <_Io.Writer.printValue__anon_4346+0x14d8>
10000d8cc: 3859c3a9    	ldurb	w9, [x29, #-0x64]
10000d8d0: 36000169    	tbz	w9, #0x0, 0x10000d8fc <_Io.Writer.printValue__anon_4346+0x1188>
10000d8d4: 528005a9    	mov	w9, #0x2d               ; =45
10000d8d8: 390077e9    	strb	w9, [sp, #0x1d]
10000d8dc: 52800029    	mov	w9, #0x1                ; =1
10000d8e0: 5100076a    	sub	w10, w27, #0x1
10000d8e4: d000003a    	adrp	x26, 0x100013000 <___anon_5016+0x2840>
10000d8e8: 9108db5a    	add	x26, x26, #0x236
10000d8ec: 71000d5f    	cmp	w10, #0x3
10000d8f0: 54000142    	b.hs	0x10000d918 <_Io.Writer.printValue__anon_4346+0x11a4>
10000d8f4: d280000f    	mov	x15, #0x0               ; =0
10000d8f8: 14000020    	b	0x10000d978 <_Io.Writer.printValue__anon_4346+0x1204>
10000d8fc: d2800009    	mov	x9, #0x0                ; =0
10000d900: 910077f5    	add	x21, sp, #0x1d
10000d904: 5100076a    	sub	w10, w27, #0x1
10000d908: d000003a    	adrp	x26, 0x100013000 <___anon_5016+0x2840>
10000d90c: 9108db5a    	add	x26, x26, #0x236
10000d910: 71000d5f    	cmp	w10, #0x3
10000d914: 54ffff03    	b.lo	0x10000d8f4 <_Io.Writer.printValue__anon_4346+0x1180>
10000d918: d280000c    	mov	x12, #0x0               ; =0
10000d91c: 910077eb    	add	x11, sp, #0x1d
10000d920: 8b0a012d    	add	x13, x9, x10
10000d924: 8b0b01ab    	add	x11, x13, x11
10000d928: 9100056b    	add	x11, x11, #0x1
10000d92c: d29eb86d    	mov	x13, #0xf5c3            ; =62915
10000d930: f2ab850d    	movk	x13, #0x5c28, lsl #16
10000d934: f2d851ed    	movk	x13, #0xc28f, lsl #32
10000d938: f2e51ead    	movk	x13, #0x28f5, lsl #48
10000d93c: 52800c8e    	mov	w14, #0x64              ; =100
10000d940: aa0803f0    	mov	x16, x8
10000d944: d342fe08    	lsr	x8, x16, #2
10000d948: 9bcd7d08    	umulh	x8, x8, x13
10000d94c: d342fd08    	lsr	x8, x8, #2
10000d950: 9b0ec10f    	msub	x15, x8, x14, x16
10000d954: 786f7b4f    	ldrh	w15, [x26, x15, lsl #1]
10000d958: 781ff16f    	sturh	w15, [x11, #-0x1]
10000d95c: 9100098f    	add	x15, x12, #0x2
10000d960: d100096b    	sub	x11, x11, #0x2
10000d964: 91001191    	add	x17, x12, #0x4
10000d968: aa0f03ec    	mov	x12, x15
10000d96c: aa0803f0    	mov	x16, x8
10000d970: eb0a023f    	cmp	x17, x10
10000d974: 54fffe83    	b.lo	0x10000d944 <_Io.Writer.printValue__anon_4346+0x11d0>
10000d978: b27f012b    	orr	x11, x9, #0x2
10000d97c: eb0f014c    	subs	x12, x10, x15
10000d980: 54000209    	b.ls	0x10000d9c0 <_Io.Writer.printValue__anon_4346+0x124c>
10000d984: 910077ed    	add	x13, sp, #0x1d
10000d988: 8b0d012d    	add	x13, x9, x13
10000d98c: 910005ae    	add	x14, x13, #0x1
10000d990: b202e7ef    	mov	x15, #-0x3333333333333334 ; =-3689348814741910324
10000d994: f29999af    	movk	x15, #0xcccd
10000d998: 52800150    	mov	w16, #0xa               ; =10
10000d99c: 9bcf7d0d    	umulh	x13, x8, x15
10000d9a0: d343fdad    	lsr	x13, x13, #3
10000d9a4: 1b10a1a8    	msub	w8, w13, w16, w8
10000d9a8: 321c0508    	orr	w8, w8, #0x30
10000d9ac: 382c69c8    	strb	w8, [x14, x12]
10000d9b0: aa0d03e8    	mov	x8, x13
10000d9b4: f100058c    	subs	x12, x12, #0x1
10000d9b8: 54ffff21    	b.ne	0x10000d99c <_Io.Writer.printValue__anon_4346+0x1228>
10000d9bc: 14000002    	b	0x10000d9c4 <_Io.Writer.printValue__anon_4346+0x1250>
10000d9c0: aa0803ed    	mov	x13, x8
10000d9c4: b202e7e8    	mov	x8, #-0x3333333333333334 ; =-3689348814741910324
10000d9c8: f29999a8    	movk	x8, #0xcccd
10000d9cc: 9bc87da8    	umulh	x8, x13, x8
10000d9d0: 53037d08    	lsr	w8, w8, #3
10000d9d4: 5280014c    	mov	w12, #0xa               ; =10
10000d9d8: 1b0cb508    	msub	w8, w8, w12, w13
10000d9dc: 321c0508    	orr	w8, w8, #0x30
10000d9e0: 910077fc    	add	x28, sp, #0x1d
10000d9e4: 38296b88    	strb	w8, [x28, x9]
10000d9e8: 528005c8    	mov	w8, #0x2e               ; =46
10000d9ec: 390006a8    	strb	w8, [x21, #0x1]
10000d9f0: 8b0a0168    	add	x8, x11, x10
10000d9f4: 7100077f    	cmp	w27, #0x1
10000d9f8: 9a89850c    	csinc	x12, x8, x9, hi
10000d9fc: 340001f8    	cbz	w24, 0x10000da38 <_Io.Writer.printValue__anon_4346+0x12c4>
10000da00: eb0a0295    	subs	x21, x20, x10
10000da04: 54000149    	b.ls	0x10000da2c <_Io.Writer.printValue__anon_4346+0x12b8>
10000da08: 7100077f    	cmp	w27, #0x1
10000da0c: 9a8c1594    	cinc	x20, x12, eq
10000da10: 910077e8    	add	x8, sp, #0x1d
10000da14: 8b140100    	add	x0, x8, x20
10000da18: 52800601    	mov	w1, #0x30               ; =48
10000da1c: aa1503e2    	mov	x2, x21
10000da20: 940006ec    	bl	0x10000f5d0 <dyld_stub_binder+0x10000f5d0>
10000da24: 8b15028c    	add	x12, x20, x21
10000da28: 14000004    	b	0x10000da38 <_Io.Writer.printValue__anon_4346+0x12c4>
10000da2c: f100029f    	cmp	x20, #0x0
10000da30: da9f1288    	csinv	x8, x20, xzr, ne
10000da34: 8b08016c    	add	x12, x11, x8
10000da38: 52800ca8    	mov	w8, #0x65               ; =101
10000da3c: 382c6b88    	strb	w8, [x28, x12]
10000da40: 91000588    	add	x8, x12, #0x1
10000da44: b9401b29    	ldr	w9, [x25, #0x18]
10000da48: 0b1b012a    	add	w10, w9, w27
10000da4c: 71000549    	subs	w9, w10, #0x1
10000da50: 5400010b    	b.lt	0x10000da70 <_Io.Writer.printValue__anon_4346+0x12fc>
10000da54: 52993fea    	mov	w10, #0xc9ff            ; =51711
10000da58: 72a7734a    	movk	w10, #0x3b9a, lsl #16
10000da5c: 6b0a013f    	cmp	w9, w10
10000da60: 540001c9    	b.ls	0x10000da98 <_Io.Writer.printValue__anon_4346+0x1324>
10000da64: 5280002c    	mov	w12, #0x1               ; =1
10000da68: 5280014a    	mov	w10, #0xa               ; =10
10000da6c: 14000011    	b	0x10000dab0 <_Io.Writer.printValue__anon_4346+0x133c>
10000da70: 910077e9    	add	x9, sp, #0x1d
10000da74: 528005ab    	mov	w11, #0x2d              ; =45
10000da78: 3828692b    	strb	w11, [x9, x8]
10000da7c: 91000988    	add	x8, x12, #0x2
10000da80: 52800029    	mov	w9, #0x1                ; =1
10000da84: 4b0a0129    	sub	w9, w9, w10
10000da88: 52993fea    	mov	w10, #0xc9ff            ; =51711
10000da8c: 72a7734a    	movk	w10, #0x3b9a, lsl #16
10000da90: 6b0a013f    	cmp	w9, w10
10000da94: 54fffe88    	b.hi	0x10000da64 <_Io.Writer.printValue__anon_4346+0x12f0>
10000da98: 529c1fea    	mov	w10, #0xe0ff            ; =57599
10000da9c: 72a0beaa    	movk	w10, #0x5f5, lsl #16
10000daa0: 6b0a013f    	cmp	w9, w10
10000daa4: 540007c9    	b.ls	0x10000db9c <_Io.Writer.printValue__anon_4346+0x1428>
10000daa8: 5280002c    	mov	w12, #0x1               ; =1
10000daac: 5280012a    	mov	w10, #0x9               ; =9
10000dab0: 5280002d    	mov	w13, #0x1               ; =1
10000dab4: 5280002b    	mov	w11, #0x1               ; =1
10000dab8: 910077ef    	add	x15, sp, #0x1d
10000dabc: 5290a3ee    	mov	w14, #0x851f            ; =34079
10000dac0: 72aa3d6e    	movk	w14, #0x51eb, lsl #16
10000dac4: 9bae7d2e    	umull	x14, w9, w14
10000dac8: d365fdce    	lsr	x14, x14, #37
10000dacc: 52800c91    	mov	w17, #0x64              ; =100
10000dad0: 1b11a5d0    	msub	w16, w14, w17, w9
10000dad4: 78705b40    	ldrh	w0, [x26, w16, uxtw #1]
10000dad8: 8b0801ef    	add	x15, x15, x8
10000dadc: 8b0a01f0    	add	x16, x15, x10
10000dae0: 781fe200    	sturh	w0, [x16, #-0x2]
10000dae4: 3600052c    	tbz	w12, #0x0, 0x10000db88 <_Io.Writer.printValue__anon_4346+0x1414>
10000dae8: 528b852c    	mov	w12, #0x5c29            ; =23593
10000daec: 72a051ec    	movk	w12, #0x28f, lsl #16
10000daf0: 9bac7dc0    	umull	x0, w14, w12
10000daf4: d360fc00    	lsr	x0, x0, #32
10000daf8: 1b11b811    	msub	w17, w0, w17, w14
10000dafc: 5282eb2e    	mov	w14, #0x1759            ; =5977
10000db00: 72ba36ee    	movk	w14, #0xd1b7, lsl #16
10000db04: 9bae7d2e    	umull	x14, w9, w14
10000db08: d36dfdce    	lsr	x14, x14, #45
10000db0c: 78715b51    	ldrh	w17, [x26, w17, uxtw #1]
10000db10: 781fc211    	sturh	w17, [x16, #-0x4]
10000db14: 3400056d    	cbz	w13, 0x10000dbc0 <_Io.Writer.printValue__anon_4346+0x144c>
10000db18: 9bac7dcc    	umull	x12, w14, w12
10000db1c: d360fd8d    	lsr	x13, x12, #32
10000db20: 52800c8c    	mov	w12, #0x64              ; =100
10000db24: 1b0cb9ad    	msub	w13, w13, w12, w14
10000db28: 529bd06e    	mov	w14, #0xde83            ; =56963
10000db2c: 72a8636e    	movk	w14, #0x431b, lsl #16
10000db30: 9bae7d2e    	umull	x14, w9, w14
10000db34: d372fdce    	lsr	x14, x14, #50
10000db38: 786d5b50    	ldrh	w16, [x26, w13, uxtw #1]
10000db3c: 8b0a01ed    	add	x13, x15, x10
10000db40: 781fa1b0    	sturh	w16, [x13, #-0x6]
10000db44: 340005ab    	cbz	w11, 0x10000dbf8 <_Io.Writer.printValue__anon_4346+0x1484>
10000db48: 528b852b    	mov	w11, #0x5c29            ; =23593
10000db4c: 72a051eb    	movk	w11, #0x28f, lsl #16
10000db50: 9bab7dcb    	umull	x11, w14, w11
10000db54: d360fd6b    	lsr	x11, x11, #32
10000db58: 1b0cb96b    	msub	w11, w11, w12, w14
10000db5c: 5287712c    	mov	w12, #0x3b89            ; =15241
10000db60: 72aabccc    	movk	w12, #0x55e6, lsl #16
10000db64: 9bac7d29    	umull	x9, w9, w12
10000db68: d379fd2e    	lsr	x14, x9, #57
10000db6c: 786b5b49    	ldrh	w9, [x26, w11, uxtw #1]
10000db70: 781f81a9    	sturh	w9, [x13, #-0x8]
10000db74: 5280010b    	mov	w11, #0x8               ; =8
10000db78: aa0e03e9    	mov	x9, x14
10000db7c: eb0a017f    	cmp	x11, x10
10000db80: 54000443    	b.lo	0x10000dc08 <_Io.Writer.printValue__anon_4346+0x1494>
10000db84: 14000030    	b	0x10000dc44 <_Io.Writer.printValue__anon_4346+0x14d0>
10000db88: 5280004b    	mov	w11, #0x2               ; =2
10000db8c: aa0e03e9    	mov	x9, x14
10000db90: eb0a017f    	cmp	x11, x10
10000db94: 540003a3    	b.lo	0x10000dc08 <_Io.Writer.printValue__anon_4346+0x1494>
10000db98: 1400002b    	b	0x10000dc44 <_Io.Writer.printValue__anon_4346+0x14d0>
10000db9c: 5292cfea    	mov	w10, #0x967f            ; =38527
10000dba0: 72a0130a    	movk	w10, #0x98, lsl #16
10000dba4: 6b0a013f    	cmp	w9, w10
10000dba8: 54000169    	b.ls	0x10000dbd4 <_Io.Writer.printValue__anon_4346+0x1460>
10000dbac: 5280000b    	mov	w11, #0x0               ; =0
10000dbb0: 5280002c    	mov	w12, #0x1               ; =1
10000dbb4: 5280010a    	mov	w10, #0x8               ; =8
10000dbb8: 5280002d    	mov	w13, #0x1               ; =1
10000dbbc: 17ffffbf    	b	0x10000dab8 <_Io.Writer.printValue__anon_4346+0x1344>
10000dbc0: 5280008b    	mov	w11, #0x4               ; =4
10000dbc4: aa0e03e9    	mov	x9, x14
10000dbc8: eb0a017f    	cmp	x11, x10
10000dbcc: 540001e3    	b.lo	0x10000dc08 <_Io.Writer.printValue__anon_4346+0x1494>
10000dbd0: 1400001d    	b	0x10000dc44 <_Io.Writer.printValue__anon_4346+0x14d0>
10000dbd4: 528847ea    	mov	w10, #0x423f            ; =16959
10000dbd8: 72a001ea    	movk	w10, #0xf, lsl #16
10000dbdc: 6b0a013f    	cmp	w9, w10
10000dbe0: 540005e9    	b.ls	0x10000dc9c <_Io.Writer.printValue__anon_4346+0x1528>
10000dbe4: 5280000b    	mov	w11, #0x0               ; =0
10000dbe8: 5280002c    	mov	w12, #0x1               ; =1
10000dbec: 528000ea    	mov	w10, #0x7               ; =7
10000dbf0: 5280002d    	mov	w13, #0x1               ; =1
10000dbf4: 17ffffb1    	b	0x10000dab8 <_Io.Writer.printValue__anon_4346+0x1344>
10000dbf8: 528000cb    	mov	w11, #0x6               ; =6
10000dbfc: aa0e03e9    	mov	x9, x14
10000dc00: eb0a017f    	cmp	x11, x10
10000dc04: 54000202    	b.hs	0x10000dc44 <_Io.Writer.printValue__anon_4346+0x14d0>
10000dc08: cb0b014b    	sub	x11, x10, x11
10000dc0c: 910077ec    	add	x12, sp, #0x1d
10000dc10: 8b0c010c    	add	x12, x8, x12
10000dc14: d100058c    	sub	x12, x12, #0x1
10000dc18: 529999ad    	mov	w13, #0xcccd            ; =52429
10000dc1c: 72b9998d    	movk	w13, #0xcccc, lsl #16
10000dc20: 5280014e    	mov	w14, #0xa               ; =10
10000dc24: 9bad7d2f    	umull	x15, w9, w13
10000dc28: d363fdef    	lsr	x15, x15, #35
10000dc2c: 1b0ea5e9    	msub	w9, w15, w14, w9
10000dc30: 321c0529    	orr	w9, w9, #0x30
10000dc34: 382b6989    	strb	w9, [x12, x11]
10000dc38: aa0f03e9    	mov	x9, x15
10000dc3c: f100056b    	subs	x11, x11, #0x1
10000dc40: 54ffff21    	b.ne	0x10000dc24 <_Io.Writer.printValue__anon_4346+0x14b0>
10000dc44: 52800009    	mov	w9, #0x0                ; =0
10000dc48: 8b080148    	add	x8, x10, x8
10000dc4c: 7100013f    	cmp	w9, #0x0
10000dc50: 528000e9    	mov	w9, #0x7                ; =7
10000dc54: d000002a    	adrp	x10, 0x100013000 <___anon_5016+0x2840>
10000dc58: 9108b94a    	add	x10, x10, #0x22e
10000dc5c: 9a890101    	csel	x1, x8, x9, eq
10000dc60: 910077e8    	add	x8, sp, #0x1d
10000dc64: 9a8a0100    	csel	x0, x8, x10, eq
10000dc68: 710002ff    	cmp	w23, #0x0
10000dc6c: 9a960022    	csel	x2, x1, x22, eq
10000dc70: 39405be3    	ldrb	w3, [sp, #0x16]
10000dc74: aa1303e4    	mov	x4, x19
10000dc78: 9400007d    	bl	0x10000de6c <_Io.Writer.alignBuffer>
10000dc7c: 9106c3ff    	add	sp, sp, #0x1b0
10000dc80: a9457bfd    	ldp	x29, x30, [sp, #0x50]
10000dc84: a9444ff4    	ldp	x20, x19, [sp, #0x40]
10000dc88: a94357f6    	ldp	x22, x21, [sp, #0x30]
10000dc8c: a9425ff8    	ldp	x24, x23, [sp, #0x20]
10000dc90: a94167fa    	ldp	x26, x25, [sp, #0x10]
10000dc94: a8c66ffc    	ldp	x28, x27, [sp], #0x60
10000dc98: d65f03c0    	ret
10000dc9c: 53057d2a    	lsr	w10, w9, #5
10000dca0: 7130d15f    	cmp	w10, #0xc34
10000dca4: 540000c9    	b.ls	0x10000dcbc <_Io.Writer.printValue__anon_4346+0x1548>
10000dca8: 5280000d    	mov	w13, #0x0               ; =0
10000dcac: 5280000b    	mov	w11, #0x0               ; =0
10000dcb0: 5280002c    	mov	w12, #0x1               ; =1
10000dcb4: 528000ca    	mov	w10, #0x6               ; =6
10000dcb8: 17ffff80    	b	0x10000dab8 <_Io.Writer.printValue__anon_4346+0x1344>
10000dcbc: 53047d2a    	lsr	w10, w9, #4
10000dcc0: 7109c15f    	cmp	w10, #0x270
10000dcc4: 540000c9    	b.ls	0x10000dcdc <_Io.Writer.printValue__anon_4346+0x1568>
10000dcc8: 5280000d    	mov	w13, #0x0               ; =0
10000dccc: 5280000b    	mov	w11, #0x0               ; =0
10000dcd0: 5280002c    	mov	w12, #0x1               ; =1
10000dcd4: 528000aa    	mov	w10, #0x5               ; =5
10000dcd8: 17ffff78    	b	0x10000dab8 <_Io.Writer.printValue__anon_4346+0x1344>
10000dcdc: 710f9d3f    	cmp	w9, #0x3e7
10000dce0: 540000c9    	b.ls	0x10000dcf8 <_Io.Writer.printValue__anon_4346+0x1584>
10000dce4: 5280000c    	mov	w12, #0x0               ; =0
10000dce8: 5280000d    	mov	w13, #0x0               ; =0
10000dcec: 5280000b    	mov	w11, #0x0               ; =0
10000dcf0: 5280008a    	mov	w10, #0x4               ; =4
10000dcf4: 17ffff71    	b	0x10000dab8 <_Io.Writer.printValue__anon_4346+0x1344>
10000dcf8: 7101913f    	cmp	w9, #0x64
10000dcfc: 540000c3    	b.lo	0x10000dd14 <_Io.Writer.printValue__anon_4346+0x15a0>
10000dd00: 5280000c    	mov	w12, #0x0               ; =0
10000dd04: 5280000d    	mov	w13, #0x0               ; =0
10000dd08: 5280000b    	mov	w11, #0x0               ; =0
10000dd0c: 5280006a    	mov	w10, #0x3               ; =3
10000dd10: 17ffff6a    	b	0x10000dab8 <_Io.Writer.printValue__anon_4346+0x1344>
10000dd14: d280000b    	mov	x11, #0x0               ; =0
10000dd18: 7100253f    	cmp	w9, #0x9
10000dd1c: 5280002a    	mov	w10, #0x1               ; =1
10000dd20: 9a8a954a    	cinc	x10, x10, hi
10000dd24: 17ffffb9    	b	0x10000dc08 <_Io.Writer.printValue__anon_4346+0x1494>

000000010000dd28 <_Io.Writer.defaultFlush>:
10000dd28: d10103ff    	sub	sp, sp, #0x40
10000dd2c: a90157f6    	stp	x22, x21, [sp, #0x10]
10000dd30: a9024ff4    	stp	x20, x19, [sp, #0x20]
10000dd34: a9037bfd    	stp	x29, x30, [sp, #0x30]
10000dd38: 9100c3fd    	add	x29, sp, #0x30
10000dd3c: aa0003f3    	mov	x19, x0
10000dd40: f9400008    	ldr	x8, [x0]
10000dd44: f9400115    	ldr	x21, [x8]
10000dd48: f0000074    	adrp	x20, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000dd4c: 9104a294    	add	x20, x20, #0x128
10000dd50: f9400e68    	ldr	x8, [x19, #0x18]
10000dd54: b4000148    	cbz	x8, 0x10000dd7c <_Io.Writer.defaultFlush+0x54>
10000dd58: 910003e8    	mov	x8, sp
10000dd5c: aa1303e0    	mov	x0, x19
10000dd60: aa1403e1    	mov	x1, x20
10000dd64: 52800022    	mov	w2, #0x1                ; =1
10000dd68: 52800023    	mov	w3, #0x1                ; =1
10000dd6c: d63f02a0    	blr	x21
10000dd70: 794013e0    	ldrh	w0, [sp, #0x8]
10000dd74: 34fffee0    	cbz	w0, 0x10000dd50 <_Io.Writer.defaultFlush+0x28>
10000dd78: 14000002    	b	0x10000dd80 <_Io.Writer.defaultFlush+0x58>
10000dd7c: 52800000    	mov	w0, #0x0                ; =0
10000dd80: a9437bfd    	ldp	x29, x30, [sp, #0x30]
10000dd84: a9424ff4    	ldp	x20, x19, [sp, #0x20]
10000dd88: a94157f6    	ldp	x22, x21, [sp, #0x10]
10000dd8c: 910103ff    	add	sp, sp, #0x40
10000dd90: d65f03c0    	ret

000000010000dd94 <_Io.Writer.defaultRebase>:
10000dd94: a9412009    	ldp	x9, x8, [x0, #0x10]
10000dd98: cb080129    	sub	x9, x9, x8
10000dd9c: eb02013f    	cmp	x9, x2
10000dda0: 540005a2    	b.hs	0x10000de54 <_Io.Writer.defaultRebase+0xc0>
10000dda4: d10143ff    	sub	sp, sp, #0x50
10000dda8: a9015ff8    	stp	x24, x23, [sp, #0x10]
10000ddac: a90257f6    	stp	x22, x21, [sp, #0x20]
10000ddb0: a9034ff4    	stp	x20, x19, [sp, #0x30]
10000ddb4: a9047bfd    	stp	x29, x30, [sp, #0x40]
10000ddb8: 910103fd    	add	x29, sp, #0x40
10000ddbc: aa0203f4    	mov	x20, x2
10000ddc0: aa0103f5    	mov	x21, x1
10000ddc4: aa0003f3    	mov	x19, x0
10000ddc8: f0000076    	adrp	x22, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000ddcc: 9104a2d6    	add	x22, x22, #0x128
10000ddd0: eb150109    	subs	x9, x8, x21
10000ddd4: 9a8933f8    	csel	x24, xzr, x9, lo
10000ddd8: cb180117    	sub	x23, x8, x24
10000dddc: f9000e78    	str	x24, [x19, #0x18]
10000dde0: f9400268    	ldr	x8, [x19]
10000dde4: f9400109    	ldr	x9, [x8]
10000dde8: 910003e8    	mov	x8, sp
10000ddec: aa1303e0    	mov	x0, x19
10000ddf0: aa1603e1    	mov	x1, x22
10000ddf4: 52800022    	mov	w2, #0x1                ; =1
10000ddf8: 52800023    	mov	w3, #0x1                ; =1
10000ddfc: d63f0120    	blr	x9
10000de00: 794013e0    	ldrh	w0, [sp, #0x8]
10000de04: 350002c0    	cbnz	w0, 0x10000de5c <_Io.Writer.defaultRebase+0xc8>
10000de08: f9400e68    	ldr	x8, [x19, #0x18]
10000de0c: f9400669    	ldr	x9, [x19, #0x8]
10000de10: 8b080120    	add	x0, x9, x8
10000de14: 8b180121    	add	x1, x9, x24
10000de18: aa1703e2    	mov	x2, x23
10000de1c: 940005ea    	bl	0x10000f5c4 <dyld_stub_binder+0x10000f5c4>
10000de20: a9412269    	ldp	x9, x8, [x19, #0x10]
10000de24: 8b170108    	add	x8, x8, x23
10000de28: cb080129    	sub	x9, x9, x8
10000de2c: f9000e68    	str	x8, [x19, #0x18]
10000de30: eb14013f    	cmp	x9, x20
10000de34: 54fffce3    	b.lo	0x10000ddd0 <_Io.Writer.defaultRebase+0x3c>
10000de38: 52800000    	mov	w0, #0x0                ; =0
10000de3c: a9447bfd    	ldp	x29, x30, [sp, #0x40]
10000de40: a9434ff4    	ldp	x20, x19, [sp, #0x30]
10000de44: a94257f6    	ldp	x22, x21, [sp, #0x20]
10000de48: a9415ff8    	ldp	x24, x23, [sp, #0x10]
10000de4c: 910143ff    	add	sp, sp, #0x50
10000de50: d65f03c0    	ret
10000de54: 52800000    	mov	w0, #0x0                ; =0
10000de58: d65f03c0    	ret
10000de5c: f9400e68    	ldr	x8, [x19, #0x18]
10000de60: 8b170108    	add	x8, x8, x23
10000de64: f9000e68    	str	x8, [x19, #0x18]
10000de68: 17fffff5    	b	0x10000de3c <_Io.Writer.defaultRebase+0xa8>

000000010000de6c <_Io.Writer.alignBuffer>:
10000de6c: d101c3ff    	sub	sp, sp, #0x70
10000de70: a90267fa    	stp	x26, x25, [sp, #0x20]
10000de74: a9035ff8    	stp	x24, x23, [sp, #0x30]
10000de78: a90457f6    	stp	x22, x21, [sp, #0x40]
10000de7c: a9054ff4    	stp	x20, x19, [sp, #0x50]
10000de80: a9067bfd    	stp	x29, x30, [sp, #0x60]
10000de84: 910183fd    	add	x29, sp, #0x60
10000de88: aa0103f3    	mov	x19, x1
10000de8c: aa0003f4    	mov	x20, x0
10000de90: eb010048    	subs	x8, x2, x1
10000de94: 9a8833f5    	csel	x21, xzr, x8, lo
10000de98: 54000668    	b.hi	0x10000df64 <_Io.Writer.alignBuffer+0xf8>
10000de9c: b4000553    	cbz	x19, 0x10000df44 <_Io.Writer.alignBuffer+0xd8>
10000dea0: d2800017    	mov	x23, #0x0               ; =0
10000dea4: f0000068    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000dea8: f940cd08    	ldr	x8, [x8, #0x198]
10000deac: f0000078    	adrp	x24, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000deb0: f0000075    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000deb4: 910602b5    	add	x21, x21, #0x180
10000deb8: f0000079    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000debc: 91062339    	add	x25, x25, #0x188
10000dec0: 8b170281    	add	x1, x20, x23
10000dec4: cb170276    	sub	x22, x19, x23
10000dec8: 8b0802c9    	add	x9, x22, x8
10000decc: f940cb0a    	ldr	x10, [x24, #0x190]
10000ded0: eb0a013f    	cmp	x9, x10
10000ded4: 54000188    	b.hi	0x10000df04 <_Io.Writer.alignBuffer+0x98>
10000ded8: f9400329    	ldr	x9, [x25]
10000dedc: 8b080120    	add	x0, x9, x8
10000dee0: aa1603e2    	mov	x2, x22
10000dee4: 940005b5    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
10000dee8: f9400b28    	ldr	x8, [x25, #0x10]
10000deec: 8b160108    	add	x8, x8, x22
10000def0: f9000b28    	str	x8, [x25, #0x10]
10000def4: 8b1702d7    	add	x23, x22, x23
10000def8: eb1302ff    	cmp	x23, x19
10000defc: 54fffe23    	b.lo	0x10000dec0 <_Io.Writer.alignBuffer+0x54>
10000df00: 14000011    	b	0x10000df44 <_Io.Writer.alignBuffer+0xd8>
10000df04: f94002a8    	ldr	x8, [x21]
10000df08: f9400109    	ldr	x9, [x8]
10000df0c: a9005be1    	stp	x1, x22, [sp]
10000df10: 910043e8    	add	x8, sp, #0x10
10000df14: 910003e1    	mov	x1, sp
10000df18: aa1503e0    	mov	x0, x21
10000df1c: 52800022    	mov	w2, #0x1                ; =1
10000df20: 52800023    	mov	w3, #0x1                ; =1
10000df24: d63f0120    	blr	x9
10000df28: 794033e0    	ldrh	w0, [sp, #0x18]
10000df2c: 350000e0    	cbnz	w0, 0x10000df48 <_Io.Writer.alignBuffer+0xdc>
10000df30: f9400bf6    	ldr	x22, [sp, #0x10]
10000df34: f9400ea8    	ldr	x8, [x21, #0x18]
10000df38: 8b1702d7    	add	x23, x22, x23
10000df3c: eb1302ff    	cmp	x23, x19
10000df40: 54fffc03    	b.lo	0x10000dec0 <_Io.Writer.alignBuffer+0x54>
10000df44: 52800000    	mov	w0, #0x0                ; =0
10000df48: a9467bfd    	ldp	x29, x30, [sp, #0x60]
10000df4c: a9454ff4    	ldp	x20, x19, [sp, #0x50]
10000df50: a94457f6    	ldp	x22, x21, [sp, #0x40]
10000df54: a9435ff8    	ldp	x24, x23, [sp, #0x30]
10000df58: a94267fa    	ldp	x26, x25, [sp, #0x20]
10000df5c: 9101c3ff    	add	sp, sp, #0x70
10000df60: d65f03c0    	ret
10000df64: 12000468    	and	w8, w3, #0x3
10000df68: 7100091f    	cmp	w8, #0x2
10000df6c: 54000240    	b.eq	0x10000dfb4 <_Io.Writer.alignBuffer+0x148>
10000df70: 7100051f    	cmp	w8, #0x1
10000df74: 540003c1    	b.ne	0x10000dfec <_Io.Writer.alignBuffer+0x180>
10000df78: d341fea1    	lsr	x1, x21, #1
10000df7c: aa0403f6    	mov	x22, x4
10000df80: aa0403e0    	mov	x0, x4
10000df84: 9400016e    	bl	0x10000e53c <_Io.Writer.splatByteAll>
10000df88: 72003c1f    	tst	w0, #0xffff
10000df8c: 54fffde1    	b.ne	0x10000df48 <_Io.Writer.alignBuffer+0xdc>
10000df90: aa1403e0    	mov	x0, x20
10000df94: aa1303e1    	mov	x1, x19
10000df98: 97ffeeaf    	bl	0x100009a54 <_Io.Writer.writeAll>
10000df9c: 72003c1f    	tst	w0, #0xffff
10000dfa0: 54fffd41    	b.ne	0x10000df48 <_Io.Writer.alignBuffer+0xdc>
10000dfa4: 910006a8    	add	x8, x21, #0x1
10000dfa8: d341fd01    	lsr	x1, x8, #1
10000dfac: aa1603e0    	mov	x0, x22
10000dfb0: 14000017    	b	0x10000e00c <_Io.Writer.alignBuffer+0x1a0>
10000dfb4: aa0403e0    	mov	x0, x4
10000dfb8: aa1503e1    	mov	x1, x21
10000dfbc: 94000160    	bl	0x10000e53c <_Io.Writer.splatByteAll>
10000dfc0: 72003c1f    	tst	w0, #0xffff
10000dfc4: 54fffc21    	b.ne	0x10000df48 <_Io.Writer.alignBuffer+0xdc>
10000dfc8: aa1403e0    	mov	x0, x20
10000dfcc: aa1303e1    	mov	x1, x19
10000dfd0: a9467bfd    	ldp	x29, x30, [sp, #0x60]
10000dfd4: a9454ff4    	ldp	x20, x19, [sp, #0x50]
10000dfd8: a94457f6    	ldp	x22, x21, [sp, #0x40]
10000dfdc: a9435ff8    	ldp	x24, x23, [sp, #0x30]
10000dfe0: a94267fa    	ldp	x26, x25, [sp, #0x20]
10000dfe4: 9101c3ff    	add	sp, sp, #0x70
10000dfe8: 17ffee9b    	b	0x100009a54 <_Io.Writer.writeAll>
10000dfec: aa0403f6    	mov	x22, x4
10000dff0: aa1403e0    	mov	x0, x20
10000dff4: aa1303e1    	mov	x1, x19
10000dff8: 97ffee97    	bl	0x100009a54 <_Io.Writer.writeAll>
10000dffc: 72003c1f    	tst	w0, #0xffff
10000e000: 54fffa41    	b.ne	0x10000df48 <_Io.Writer.alignBuffer+0xdc>
10000e004: aa1603e0    	mov	x0, x22
10000e008: aa1503e1    	mov	x1, x21
10000e00c: a9467bfd    	ldp	x29, x30, [sp, #0x60]
10000e010: a9454ff4    	ldp	x20, x19, [sp, #0x50]
10000e014: a94457f6    	ldp	x22, x21, [sp, #0x40]
10000e018: a9435ff8    	ldp	x24, x23, [sp, #0x30]
10000e01c: a94267fa    	ldp	x26, x25, [sp, #0x20]
10000e020: 9101c3ff    	add	sp, sp, #0x70
10000e024: 14000146    	b	0x10000e53c <_Io.Writer.splatByteAll>

000000010000e028 <_fs.File.Reader.getSize>:
10000e028: d10303ff    	sub	sp, sp, #0xc0
10000e02c: a90a4ff4    	stp	x20, x19, [sp, #0xa0]
10000e030: a90b7bfd    	stp	x29, x30, [sp, #0xb0]
10000e034: 9102c3fd    	add	x29, sp, #0xb0
10000e038: 39404028    	ldrb	w8, [x1, #0x10]
10000e03c: 340000a8    	cbz	w8, 0x10000e050 <_fs.File.Reader.getSize+0x28>
10000e040: f9400428    	ldr	x8, [x1, #0x8]
10000e044: f9000008    	str	x8, [x0]
10000e048: 7900101f    	strh	wzr, [x0, #0x8]
10000e04c: 14000004    	b	0x10000e05c <_fs.File.Reader.getSize+0x34>
10000e050: 79408c28    	ldrh	w8, [x1, #0x46]
10000e054: 340000c8    	cbz	w8, 0x10000e06c <_fs.File.Reader.getSize+0x44>
10000e058: 79001008    	strh	w8, [x0, #0x8]
10000e05c: a94b7bfd    	ldp	x29, x30, [sp, #0xb0]
10000e060: a94a4ff4    	ldp	x20, x19, [sp, #0xa0]
10000e064: 910303ff    	add	sp, sp, #0xc0
10000e068: d65f03c0    	ret
10000e06c: aa0003f4    	mov	x20, x0
10000e070: aa0103f3    	mov	x19, x1
10000e074: b9404020    	ldr	w0, [x1, #0x40]
10000e078: 6f00e400    	movi.2d	v0, #0000000000000000
10000e07c: ad0403e0    	stp	q0, q0, [sp, #0x80]
10000e080: ad0303e0    	stp	q0, q0, [sp, #0x60]
10000e084: ad0203e0    	stp	q0, q0, [sp, #0x40]
10000e088: ad0103e0    	stp	q0, q0, [sp, #0x20]
10000e08c: 3d8007e0    	str	q0, [sp, #0x10]
10000e090: 910043e1    	add	x1, sp, #0x10
10000e094: 94000555    	bl	0x10000f5e8 <dyld_stub_binder+0x10000f5e8>
10000e098: 3100041f    	cmn	w0, #0x1
10000e09c: 54000300    	b.eq	0x10000e0fc <_fs.File.Reader.getSize+0xd4>
10000e0a0: 79402be9    	ldrh	w9, [sp, #0x14]
10000e0a4: f9403be8    	ldr	x8, [sp, #0x70]
10000e0a8: 530c7d29    	lsr	w9, w9, #12
10000e0ac: 531e752a    	lsl	w10, w9, #2
10000e0b0: 521b014a    	eor	w10, w10, #0x20
10000e0b4: d29494ab    	mov	x11, #0xa4a5            ; =42149
10000e0b8: f2b554cb    	movk	x11, #0xaaa6, lsl #16
10000e0bc: f2d4274b    	movk	x11, #0xa13a, lsl #32
10000e0c0: f2e0144b    	movk	x11, #0xa2, lsl #48
10000e0c4: 9aca256a    	lsr	x10, x11, x10
10000e0c8: 5280014b    	mov	w11, #0xa               ; =10
10000e0cc: 71001d3f    	cmp	w9, #0x7
10000e0d0: 1a8a0169    	csel	w9, w11, w10, eq
10000e0d4: 12000d29    	and	w9, w9, #0xf
10000e0d8: 39003be9    	strb	w9, [sp, #0xe]
10000e0dc: 7100153f    	cmp	w9, #0x5
10000e0e0: 540002a1    	b.ne	0x10000e134 <_fs.File.Reader.getSize+0x10c>
10000e0e4: f9000668    	str	x8, [x19, #0x8]
10000e0e8: 52800029    	mov	w9, #0x1                ; =1
10000e0ec: 39004269    	strb	w9, [x19, #0x10]
10000e0f0: 7900129f    	strh	wzr, [x20, #0x8]
10000e0f4: f9000288    	str	x8, [x20]
10000e0f8: 17ffffd9    	b	0x10000e05c <_fs.File.Reader.getSize+0x34>
10000e0fc: 94000538    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
10000e100: b9400008    	ldr	w8, [x0]
10000e104: 72003d1f    	tst	w8, #0xffff
10000e108: 54fffcc0    	b.eq	0x10000e0a0 <_fs.File.Reader.getSize+0x78>
10000e10c: 52800289    	mov	w9, #0x14               ; =20
10000e110: 5280022a    	mov	w10, #0x11              ; =17
10000e114: 528000eb    	mov	w11, #0x7               ; =7
10000e118: 7100311f    	cmp	w8, #0xc
10000e11c: 1a8b1129    	csel	w9, w9, w11, ne
10000e120: 7100351f    	cmp	w8, #0xd
10000e124: 1a890148    	csel	w8, w10, w9, eq
10000e128: 79008e68    	strh	w8, [x19, #0x46]
10000e12c: 79001288    	strh	w8, [x20, #0x8]
10000e130: 17ffffcb    	b	0x10000e05c <_fs.File.Reader.getSize+0x34>
10000e134: 39412a68    	ldrb	w8, [x19, #0x4a]
10000e138: 521e0108    	eor	w8, w8, #0x4
10000e13c: 12000908    	and	w8, w8, #0x7
10000e140: 0b080508    	add	w8, w8, w8, lsl #1
10000e144: 52800089    	mov	w9, #0x4                ; =4
10000e148: 72a00909    	movk	w9, #0x48, lsl #16
10000e14c: 1ac82528    	lsr	w8, w9, w8
10000e150: 12000908    	and	w8, w8, #0x7
10000e154: 39012a68    	strb	w8, [x19, #0x4a]
10000e158: 528002c8    	mov	w8, #0x16               ; =22
10000e15c: 79008e68    	strh	w8, [x19, #0x46]
10000e160: d0000008    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
10000e164: 91190108    	add	x8, x8, #0x640
10000e168: 3dc00100    	ldr	q0, [x8]
10000e16c: 3d800280    	str	q0, [x20]
10000e170: 17ffffbb    	b	0x10000e05c <_fs.File.Reader.getSize+0x34>

000000010000e174 <_fs.File.Reader.seekBy>:
10000e174: a9ba6ffc    	stp	x28, x27, [sp, #-0x60]!
10000e178: a90167fa    	stp	x26, x25, [sp, #0x10]
10000e17c: a9025ff8    	stp	x24, x23, [sp, #0x20]
10000e180: a90357f6    	stp	x22, x21, [sp, #0x30]
10000e184: a9044ff4    	stp	x20, x19, [sp, #0x40]
10000e188: a9057bfd    	stp	x29, x30, [sp, #0x50]
10000e18c: 910143fd    	add	x29, sp, #0x50
10000e190: d106c3ff    	sub	sp, sp, #0x1b0
10000e194: aa0103f4    	mov	x20, x1
10000e198: aa0003f3    	mov	x19, x0
10000e19c: 39412808    	ldrb	w8, [x0, #0x4a]
10000e1a0: 12000908    	and	w8, w8, #0x7
10000e1a4: 7100051f    	cmp	w8, #0x1
10000e1a8: 540000ed    	b.le	0x10000e1c4 <_fs.File.Reader.seekBy+0x50>
10000e1ac: 7100091f    	cmp	w8, #0x2
10000e1b0: 540000c0    	b.eq	0x10000e1c8 <_fs.File.Reader.seekBy+0x54>
10000e1b4: 71000d1f    	cmp	w8, #0x3
10000e1b8: 54001140    	b.eq	0x10000e3e0 <_fs.File.Reader.seekBy+0x26c>
10000e1bc: 79409260    	ldrh	w0, [x19, #0x48]
10000e1c0: 140000d2    	b	0x10000e508 <_fs.File.Reader.seekBy+0x394>
10000e1c4: 350010e8    	cbnz	w8, 0x10000e3e0 <_fs.File.Reader.seekBy+0x26c>
10000e1c8: 79409268    	ldrh	w8, [x19, #0x48]
10000e1cc: 34000fe8    	cbz	w8, 0x10000e3c8 <_fs.File.Reader.seekBy+0x254>
10000e1d0: b4001554    	cbz	x20, 0x10000e478 <_fs.File.Reader.seekBy+0x304>
10000e1d4: 910263e8    	add	x8, sp, #0x98
10000e1d8: 91002117    	add	x23, x8, #0x8
10000e1dc: 92f00018    	mov	x24, #0x7fffffffffffffff ; =9223372036854775807
10000e1e0: 910063f9    	add	x25, sp, #0x18
10000e1e4: 5280101a    	mov	w26, #0x80              ; =128
10000e1e8: 5280009b    	mov	w27, #0x4               ; =4
10000e1ec: 72a0091b    	movk	w27, #0x48, lsl #16
10000e1f0: b9404275    	ldr	w21, [x19, #0x40]
10000e1f4: f940027c    	ldr	x28, [x19]
10000e1f8: 39412a68    	ldrb	w8, [x19, #0x4a]
10000e1fc: 12000908    	and	w8, w8, #0x7
10000e200: 7100051f    	cmp	w8, #0x1
10000e204: 540000cd    	b.le	0x10000e21c <_fs.File.Reader.seekBy+0xa8>
10000e208: 7100091f    	cmp	w8, #0x2
10000e20c: 540000a0    	b.eq	0x10000e220 <_fs.File.Reader.seekBy+0xac>
10000e210: 71000d1f    	cmp	w8, #0x3
10000e214: 540003e0    	b.eq	0x10000e290 <_fs.File.Reader.seekBy+0x11c>
10000e218: 140000ba    	b	0x10000e500 <_fs.File.Reader.seekBy+0x38c>
10000e21c: 350003a8    	cbnz	w8, 0x10000e290 <_fs.File.Reader.seekBy+0x11c>
10000e220: 79408e68    	ldrh	w8, [x19, #0x46]
10000e224: 35000068    	cbnz	w8, 0x10000e230 <_fs.File.Reader.seekBy+0xbc>
10000e228: 79409268    	ldrh	w8, [x19, #0x48]
10000e22c: 34000608    	cbz	w8, 0x10000e2ec <_fs.File.Reader.seekBy+0x178>
10000e230: d2800016    	mov	x22, #0x0               ; =0
10000e234: aa1703e8    	mov	x8, x23
10000e238: aa1403e9    	mov	x9, x20
10000e23c: f102013f    	cmp	x9, #0x80
10000e240: 9a9a312a    	csel	x10, x9, x26, lo
10000e244: a93fa919    	stp	x25, x10, [x8, #-0x8]
10000e248: cb0a0129    	sub	x9, x9, x10
10000e24c: f100013f    	cmp	x9, #0x0
10000e250: fa4f1ac2    	ccmp	x22, #0xf, #0x2, ne
10000e254: 910006d6    	add	x22, x22, #0x1
10000e258: 91004108    	add	x8, x8, #0x10
10000e25c: 54ffff03    	b.lo	0x10000e23c <_fs.File.Reader.seekBy+0xc8>
10000e260: 910263e1    	add	x1, sp, #0x98
10000e264: aa1503e0    	mov	x0, x21
10000e268: aa1603e2    	mov	x2, x22
10000e26c: 940004e8    	bl	0x10000f60c <dyld_stub_binder+0x10000f60c>
10000e270: b100041f    	cmn	x0, #0x1
10000e274: 540004a1    	b.ne	0x10000e308 <_fs.File.Reader.seekBy+0x194>
10000e278: 940004d9    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
10000e27c: b9400008    	ldr	w8, [x0]
10000e280: 12003d09    	and	w9, w8, #0xffff
10000e284: 7100113f    	cmp	w9, #0x4
10000e288: 54fffec0    	b.eq	0x10000e260 <_fs.File.Reader.seekBy+0xec>
10000e28c: 14000043    	b	0x10000e398 <_fs.File.Reader.seekBy+0x224>
10000e290: 910023e0    	add	x0, sp, #0x8
10000e294: aa1303e1    	mov	x1, x19
10000e298: 97ffff64    	bl	0x10000e028 <_fs.File.Reader.getSize>
10000e29c: 794023e8    	ldrh	w8, [sp, #0x10]
10000e2a0: 34000148    	cbz	w8, 0x10000e2c8 <_fs.File.Reader.seekBy+0x154>
10000e2a4: d2800000    	mov	x0, #0x0                ; =0
10000e2a8: 39412a68    	ldrb	w8, [x19, #0x4a]
10000e2ac: 521e0108    	eor	w8, w8, #0x4
10000e2b0: 12000908    	and	w8, w8, #0x7
10000e2b4: 0b080508    	add	w8, w8, w8, lsl #1
10000e2b8: 1ac82768    	lsr	w8, w27, w8
10000e2bc: 12000908    	and	w8, w8, #0x7
10000e2c0: 39012a68    	strb	w8, [x19, #0x4a]
10000e2c4: 14000007    	b	0x10000e2e0 <_fs.File.Reader.seekBy+0x16c>
10000e2c8: f94007e8    	ldr	x8, [sp, #0x8]
10000e2cc: cb1c0108    	sub	x8, x8, x28
10000e2d0: eb08029f    	cmp	x20, x8
10000e2d4: 9a883280    	csel	x0, x20, x8, lo
10000e2d8: 8b1c0008    	add	x8, x0, x28
10000e2dc: f9000268    	str	x8, [x19]
10000e2e0: eb000294    	subs	x20, x20, x0
10000e2e4: 54fff861    	b.ne	0x10000e1f0 <_fs.File.Reader.seekBy+0x7c>
10000e2e8: 14000064    	b	0x10000e478 <_fs.File.Reader.seekBy+0x304>
10000e2ec: d101a3a0    	sub	x0, x29, #0x68
10000e2f0: aa1303e1    	mov	x1, x19
10000e2f4: 97ffff4d    	bl	0x10000e028 <_fs.File.Reader.getSize>
10000e2f8: 785a03a8    	ldurh	w8, [x29, #-0x60]
10000e2fc: 340000a8    	cbz	w8, 0x10000e310 <_fs.File.Reader.seekBy+0x19c>
10000e300: d2800000    	mov	x0, #0x0                ; =0
10000e304: 17fffff7    	b	0x10000e2e0 <_fs.File.Reader.seekBy+0x16c>
10000e308: b5fffe80    	cbnz	x0, 0x10000e2d8 <_fs.File.Reader.seekBy+0x164>
10000e30c: 14000087    	b	0x10000e528 <_fs.File.Reader.seekBy+0x3b4>
10000e310: f85983a8    	ldur	x8, [x29, #-0x68]
10000e314: cb1c0108    	sub	x8, x8, x28
10000e318: eb14011f    	cmp	x8, x20
10000e31c: 9a943108    	csel	x8, x8, x20, lo
10000e320: eb18011f    	cmp	x8, x24
10000e324: 9a983101    	csel	x1, x8, x24, lo
10000e328: aa1503e0    	mov	x0, x21
10000e32c: aa0103f5    	mov	x21, x1
10000e330: 52800022    	mov	w2, #0x1                ; =1
10000e334: 940004b0    	bl	0x10000f5f4 <dyld_stub_binder+0x10000f5f4>
10000e338: b100041f    	cmn	x0, #0x1
10000e33c: 54000080    	b.eq	0x10000e34c <_fs.File.Reader.seekBy+0x1d8>
10000e340: aa1503e0    	mov	x0, x21
10000e344: 8b1c02a8    	add	x8, x21, x28
10000e348: 17ffffe5    	b	0x10000e2dc <_fs.File.Reader.seekBy+0x168>
10000e34c: 940004a4    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
10000e350: b9400009    	ldr	w9, [x0]
10000e354: 528002e8    	mov	w8, #0x17               ; =23
10000e358: 7100553f    	cmp	w9, #0x15
10000e35c: 5400014d    	b.le	0x10000e384 <_fs.File.Reader.seekBy+0x210>
10000e360: 7100593f    	cmp	w9, #0x16
10000e364: 540000a0    	b.eq	0x10000e378 <_fs.File.Reader.seekBy+0x204>
10000e368: 7100753f    	cmp	w9, #0x1d
10000e36c: 54000060    	b.eq	0x10000e378 <_fs.File.Reader.seekBy+0x204>
10000e370: 7101513f    	cmp	w9, #0x54
10000e374: 540000e1    	b.ne	0x10000e390 <_fs.File.Reader.seekBy+0x21c>
10000e378: d2800000    	mov	x0, #0x0                ; =0
10000e37c: 79009268    	strh	w8, [x19, #0x48]
10000e380: 17ffffd8    	b	0x10000e2e0 <_fs.File.Reader.seekBy+0x16c>
10000e384: 34fffde9    	cbz	w9, 0x10000e340 <_fs.File.Reader.seekBy+0x1cc>
10000e388: 7100193f    	cmp	w9, #0x6
10000e38c: 54ffff60    	b.eq	0x10000e378 <_fs.File.Reader.seekBy+0x204>
10000e390: 52800288    	mov	w8, #0x14               ; =20
10000e394: 17fffff9    	b	0x10000e378 <_fs.File.Reader.seekBy+0x204>
10000e398: 7100891f    	cmp	w8, #0x22
10000e39c: 5400040c    	b.gt	0x10000e41c <_fs.File.Reader.seekBy+0x2a8>
10000e3a0: 7100211f    	cmp	w8, #0x8
10000e3a4: 5400070d    	b.le	0x10000e484 <_fs.File.Reader.seekBy+0x310>
10000e3a8: 7100251f    	cmp	w8, #0x9
10000e3ac: 540009e0    	b.eq	0x10000e4e8 <_fs.File.Reader.seekBy+0x374>
10000e3b0: 7100311f    	cmp	w8, #0xc
10000e3b4: 54000800    	b.eq	0x10000e4b4 <_fs.File.Reader.seekBy+0x340>
10000e3b8: 7100551f    	cmp	w8, #0x15
10000e3bc: 540009e1    	b.ne	0x10000e4f8 <_fs.File.Reader.seekBy+0x384>
10000e3c0: 52800108    	mov	w8, #0x8                ; =8
10000e3c4: 1400004e    	b	0x10000e4fc <_fs.File.Reader.seekBy+0x388>
10000e3c8: b9404260    	ldr	w0, [x19, #0x40]
10000e3cc: aa1403e1    	mov	x1, x20
10000e3d0: 52800022    	mov	w2, #0x1                ; =1
10000e3d4: 94000488    	bl	0x10000f5f4 <dyld_stub_binder+0x10000f5f4>
10000e3d8: b100041f    	cmn	x0, #0x1
10000e3dc: 54000340    	b.eq	0x10000e444 <_fs.File.Reader.seekBy+0x2d0>
10000e3e0: f940026a    	ldr	x10, [x19]
10000e3e4: a9432668    	ldp	x8, x9, [x19, #0x30]
10000e3e8: 8b0a010b    	add	x11, x8, x10
10000e3ec: cb090169    	sub	x9, x11, x9
10000e3f0: 8b140129    	add	x9, x9, x20
10000e3f4: eb0a013f    	cmp	x9, x10
10000e3f8: 54000062    	b.hs	0x10000e404 <_fs.File.Reader.seekBy+0x290>
10000e3fc: 8b140108    	add	x8, x8, x20
10000e400: 14000004    	b	0x10000e410 <_fs.File.Reader.seekBy+0x29c>
10000e404: d2800008    	mov	x8, #0x0                ; =0
10000e408: f9001e7f    	str	xzr, [x19, #0x38]
10000e40c: f9000269    	str	x9, [x19]
10000e410: 52800000    	mov	w0, #0x0                ; =0
10000e414: f9001a68    	str	x8, [x19, #0x30]
10000e418: 1400003c    	b	0x10000e508 <_fs.File.Reader.seekBy+0x394>
10000e41c: 7100d91f    	cmp	w8, #0x36
10000e420: 540003ed    	b.le	0x10000e49c <_fs.File.Reader.seekBy+0x328>
10000e424: 7100dd1f    	cmp	w8, #0x37
10000e428: 54000460    	b.eq	0x10000e4b4 <_fs.File.Reader.seekBy+0x340>
10000e42c: 7100e51f    	cmp	w8, #0x39
10000e430: 54000600    	b.eq	0x10000e4f0 <_fs.File.Reader.seekBy+0x37c>
10000e434: 7100f11f    	cmp	w8, #0x3c
10000e438: 54000601    	b.ne	0x10000e4f8 <_fs.File.Reader.seekBy+0x384>
10000e43c: 52800188    	mov	w8, #0xc                ; =12
10000e440: 1400002f    	b	0x10000e4fc <_fs.File.Reader.seekBy+0x388>
10000e444: 94000466    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
10000e448: b9400009    	ldr	w9, [x0]
10000e44c: 528002e8    	mov	w8, #0x17               ; =23
10000e450: 7100553f    	cmp	w9, #0x15
10000e454: 5400034d    	b.le	0x10000e4bc <_fs.File.Reader.seekBy+0x348>
10000e458: 7100593f    	cmp	w9, #0x16
10000e45c: 540000a0    	b.eq	0x10000e470 <_fs.File.Reader.seekBy+0x2fc>
10000e460: 7100753f    	cmp	w9, #0x1d
10000e464: 54000060    	b.eq	0x10000e470 <_fs.File.Reader.seekBy+0x2fc>
10000e468: 7101513f    	cmp	w9, #0x54
10000e46c: 540002e1    	b.ne	0x10000e4c8 <_fs.File.Reader.seekBy+0x354>
10000e470: 79009268    	strh	w8, [x19, #0x48]
10000e474: b5ffeb14    	cbnz	x20, 0x10000e1d4 <_fs.File.Reader.seekBy+0x60>
10000e478: 52800000    	mov	w0, #0x0                ; =0
10000e47c: a9037e7f    	stp	xzr, xzr, [x19, #0x30]
10000e480: 14000022    	b	0x10000e508 <_fs.File.Reader.seekBy+0x394>
10000e484: 71000d1f    	cmp	w8, #0x3
10000e488: 54000280    	b.eq	0x10000e4d8 <_fs.File.Reader.seekBy+0x364>
10000e48c: 7100151f    	cmp	w8, #0x5
10000e490: 54000341    	b.ne	0x10000e4f8 <_fs.File.Reader.seekBy+0x384>
10000e494: 528000c8    	mov	w8, #0x6                ; =6
10000e498: 14000019    	b	0x10000e4fc <_fs.File.Reader.seekBy+0x388>
10000e49c: 71008d1f    	cmp	w8, #0x23
10000e4a0: 54000200    	b.eq	0x10000e4e0 <_fs.File.Reader.seekBy+0x36c>
10000e4a4: 7100d91f    	cmp	w8, #0x36
10000e4a8: 54000281    	b.ne	0x10000e4f8 <_fs.File.Reader.seekBy+0x384>
10000e4ac: 52800168    	mov	w8, #0xb                ; =11
10000e4b0: 14000013    	b	0x10000e4fc <_fs.File.Reader.seekBy+0x388>
10000e4b4: 528000e8    	mov	w8, #0x7                ; =7
10000e4b8: 14000011    	b	0x10000e4fc <_fs.File.Reader.seekBy+0x388>
10000e4bc: 34fff929    	cbz	w9, 0x10000e3e0 <_fs.File.Reader.seekBy+0x26c>
10000e4c0: 7100193f    	cmp	w9, #0x6
10000e4c4: 54fffd60    	b.eq	0x10000e470 <_fs.File.Reader.seekBy+0x2fc>
10000e4c8: 52800288    	mov	w8, #0x14               ; =20
10000e4cc: 79009268    	strh	w8, [x19, #0x48]
10000e4d0: b5ffe834    	cbnz	x20, 0x10000e1d4 <_fs.File.Reader.seekBy+0x60>
10000e4d4: 17ffffe9    	b	0x10000e478 <_fs.File.Reader.seekBy+0x304>
10000e4d8: 52800248    	mov	w8, #0x12               ; =18
10000e4dc: 14000008    	b	0x10000e4fc <_fs.File.Reader.seekBy+0x388>
10000e4e0: 528001e8    	mov	w8, #0xf                ; =15
10000e4e4: 14000006    	b	0x10000e4fc <_fs.File.Reader.seekBy+0x388>
10000e4e8: 528001a8    	mov	w8, #0xd                ; =13
10000e4ec: 14000004    	b	0x10000e4fc <_fs.File.Reader.seekBy+0x388>
10000e4f0: 528001c8    	mov	w8, #0xe                ; =14
10000e4f4: 14000002    	b	0x10000e4fc <_fs.File.Reader.seekBy+0x388>
10000e4f8: 52800288    	mov	w8, #0x14               ; =20
10000e4fc: 79008a68    	strh	w8, [x19, #0x44]
10000e500: 52800060    	mov	w0, #0x3                ; =3
10000e504: 79009260    	strh	w0, [x19, #0x48]
10000e508: 9106c3ff    	add	sp, sp, #0x1b0
10000e50c: a9457bfd    	ldp	x29, x30, [sp, #0x50]
10000e510: a9444ff4    	ldp	x20, x19, [sp, #0x40]
10000e514: a94357f6    	ldp	x22, x21, [sp, #0x30]
10000e518: a9425ff8    	ldp	x24, x23, [sp, #0x20]
10000e51c: a94167fa    	ldp	x26, x25, [sp, #0x10]
10000e520: a8c66ffc    	ldp	x28, x27, [sp], #0x60
10000e524: d65f03c0    	ret
10000e528: f900067c    	str	x28, [x19, #0x8]
10000e52c: 52800028    	mov	w8, #0x1                ; =1
10000e530: 39004268    	strb	w8, [x19, #0x10]
10000e534: 52800080    	mov	w0, #0x4                ; =4
10000e538: 17fffff3    	b	0x10000e504 <_fs.File.Reader.seekBy+0x390>

000000010000e53c <_Io.Writer.splatByteAll>:
10000e53c: b4000681    	cbz	x1, 0x10000e60c <_Io.Writer.splatByteAll+0xd0>
10000e540: d10203ff    	sub	sp, sp, #0x80
10000e544: a90367fa    	stp	x26, x25, [sp, #0x30]
10000e548: a9045ff8    	stp	x24, x23, [sp, #0x40]
10000e54c: a90557f6    	stp	x22, x21, [sp, #0x50]
10000e550: a9064ff4    	stp	x20, x19, [sp, #0x60]
10000e554: a9077bfd    	stp	x29, x30, [sp, #0x70]
10000e558: 9101c3fd    	add	x29, sp, #0x70
10000e55c: aa0103f3    	mov	x19, x1
10000e560: aa0003f4    	mov	x20, x0
10000e564: d0000075    	adrp	x21, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e568: f940cea8    	ldr	x8, [x21, #0x198]
10000e56c: d0000076    	adrp	x22, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e570: 91003ff7    	add	x23, sp, #0xf
10000e574: 52800038    	mov	w24, #0x1               ; =1
10000e578: d0000079    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e57c: 91062339    	add	x25, x25, #0x188
10000e580: f940cac9    	ldr	x9, [x22, #0x190]
10000e584: 8b13010a    	add	x10, x8, x19
10000e588: eb09015f    	cmp	x10, x9
10000e58c: 54000188    	b.hi	0x10000e5bc <_Io.Writer.splatByteAll+0x80>
10000e590: f9400329    	ldr	x9, [x25]
10000e594: 8b080120    	add	x0, x9, x8
10000e598: aa1403e1    	mov	x1, x20
10000e59c: aa1303e2    	mov	x2, x19
10000e5a0: 9400040c    	bl	0x10000f5d0 <dyld_stub_binder+0x10000f5d0>
10000e5a4: f9400b28    	ldr	x8, [x25, #0x10]
10000e5a8: 8b130108    	add	x8, x8, x19
10000e5ac: f9000b28    	str	x8, [x25, #0x10]
10000e5b0: eb130273    	subs	x19, x19, x19
10000e5b4: 54fffe61    	b.ne	0x10000e580 <_Io.Writer.splatByteAll+0x44>
10000e5b8: 1400000d    	b	0x10000e5ec <_Io.Writer.splatByteAll+0xb0>
10000e5bc: 39003ff4    	strb	w20, [sp, #0xf]
10000e5c0: a90163f7    	stp	x23, x24, [sp, #0x10]
10000e5c4: 910083e0    	add	x0, sp, #0x20
10000e5c8: 910043e1    	add	x1, sp, #0x10
10000e5cc: aa1303e2    	mov	x2, x19
10000e5d0: 940000e0    	bl	0x10000e950 <_Io.Writer.writeSplat>
10000e5d4: 794053e0    	ldrh	w0, [sp, #0x28]
10000e5d8: 350000c0    	cbnz	w0, 0x10000e5f0 <_Io.Writer.splatByteAll+0xb4>
10000e5dc: f94013e9    	ldr	x9, [sp, #0x20]
10000e5e0: f940cea8    	ldr	x8, [x21, #0x198]
10000e5e4: eb090273    	subs	x19, x19, x9
10000e5e8: 54fffcc1    	b.ne	0x10000e580 <_Io.Writer.splatByteAll+0x44>
10000e5ec: 52800000    	mov	w0, #0x0                ; =0
10000e5f0: a9477bfd    	ldp	x29, x30, [sp, #0x70]
10000e5f4: a9464ff4    	ldp	x20, x19, [sp, #0x60]
10000e5f8: a94557f6    	ldp	x22, x21, [sp, #0x50]
10000e5fc: a9445ff8    	ldp	x24, x23, [sp, #0x40]
10000e600: a94367fa    	ldp	x26, x25, [sp, #0x30]
10000e604: 910203ff    	add	sp, sp, #0x80
10000e608: d65f03c0    	ret
10000e60c: 52800000    	mov	w0, #0x0                ; =0
10000e610: d65f03c0    	ret

000000010000e614 <_fmt.float.round__anon_5325>:
10000e614: f9400028    	ldr	x8, [x1]
10000e618: b9400829    	ldr	w9, [x1, #0x8]
10000e61c: 92b207ea    	mov	x10, #-0x903f0001       ; =-2420047873
10000e620: f2d0de4a    	movk	x10, #0x86f2, lsl #32
10000e624: f2e0046a    	movk	x10, #0x23, lsl #48
10000e628: eb0a011f    	cmp	x8, x10
10000e62c: 54000069    	b.ls	0x10000e638 <_fmt.float.round__anon_5325+0x24>
10000e630: 5280022a    	mov	w10, #0x11              ; =17
10000e634: 14000059    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e638: d28fffea    	mov	x10, #0x7fff            ; =32767
10000e63c: f2b498ca    	movk	x10, #0xa4c6, lsl #16
10000e640: f2d1afca    	movk	x10, #0x8d7e, lsl #32
10000e644: f2e0006a    	movk	x10, #0x3, lsl #48
10000e648: eb0a011f    	cmp	x8, x10
10000e64c: 54000069    	b.ls	0x10000e658 <_fmt.float.round__anon_5325+0x44>
10000e650: 5280020a    	mov	w10, #0x10              ; =16
10000e654: 14000051    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e658: d287ffea    	mov	x10, #0x3fff            ; =16383
10000e65c: f2a20f4a    	movk	x10, #0x107a, lsl #16
10000e660: f2cb5e6a    	movk	x10, #0x5af3, lsl #32
10000e664: eb0a011f    	cmp	x8, x10
10000e668: 54000069    	b.ls	0x10000e674 <_fmt.float.round__anon_5325+0x60>
10000e66c: 528001ea    	mov	w10, #0xf               ; =15
10000e670: 1400004a    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e674: d293ffea    	mov	x10, #0x9fff            ; =40959
10000e678: f2a9ce4a    	movk	x10, #0x4e72, lsl #16
10000e67c: f2c1230a    	movk	x10, #0x918, lsl #32
10000e680: eb0a011f    	cmp	x8, x10
10000e684: 54000069    	b.ls	0x10000e690 <_fmt.float.round__anon_5325+0x7c>
10000e688: 528001ca    	mov	w10, #0xe               ; =14
10000e68c: 14000043    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e690: d281ffea    	mov	x10, #0xfff             ; =4095
10000e694: f2ba94aa    	movk	x10, #0xd4a5, lsl #16
10000e698: f2c01d0a    	movk	x10, #0xe8, lsl #32
10000e69c: eb0a011f    	cmp	x8, x10
10000e6a0: 54000069    	b.ls	0x10000e6ac <_fmt.float.round__anon_5325+0x98>
10000e6a4: 528001aa    	mov	w10, #0xd               ; =13
10000e6a8: 1400003c    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e6ac: d29cffea    	mov	x10, #0xe7ff            ; =59391
10000e6b0: f2a90eca    	movk	x10, #0x4876, lsl #16
10000e6b4: f2c002ea    	movk	x10, #0x17, lsl #32
10000e6b8: eb0a011f    	cmp	x8, x10
10000e6bc: 54000069    	b.ls	0x10000e6c8 <_fmt.float.round__anon_5325+0xb4>
10000e6c0: 5280018a    	mov	w10, #0xc               ; =12
10000e6c4: 14000035    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e6c8: d29c7fea    	mov	x10, #0xe3ff            ; =58367
10000e6cc: f2aa816a    	movk	x10, #0x540b, lsl #16
10000e6d0: f2c0004a    	movk	x10, #0x2, lsl #32
10000e6d4: eb0a011f    	cmp	x8, x10
10000e6d8: 54000069    	b.ls	0x10000e6e4 <_fmt.float.round__anon_5325+0xd0>
10000e6dc: 5280016a    	mov	w10, #0xb               ; =11
10000e6e0: 1400002e    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e6e4: 52993fea    	mov	w10, #0xc9ff            ; =51711
10000e6e8: 72a7734a    	movk	w10, #0x3b9a, lsl #16
10000e6ec: eb0a011f    	cmp	x8, x10
10000e6f0: 54000069    	b.ls	0x10000e6fc <_fmt.float.round__anon_5325+0xe8>
10000e6f4: 5280014a    	mov	w10, #0xa               ; =10
10000e6f8: 14000028    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e6fc: 529c1fea    	mov	w10, #0xe0ff            ; =57599
10000e700: 72a0beaa    	movk	w10, #0x5f5, lsl #16
10000e704: eb0a011f    	cmp	x8, x10
10000e708: 54000069    	b.ls	0x10000e714 <_fmt.float.round__anon_5325+0x100>
10000e70c: 5280012a    	mov	w10, #0x9               ; =9
10000e710: 14000022    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e714: 5292cfea    	mov	w10, #0x967f            ; =38527
10000e718: 72a0130a    	movk	w10, #0x98, lsl #16
10000e71c: eb0a011f    	cmp	x8, x10
10000e720: 54000069    	b.ls	0x10000e72c <_fmt.float.round__anon_5325+0x118>
10000e724: 5280010a    	mov	w10, #0x8               ; =8
10000e728: 1400001c    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e72c: 528847ea    	mov	w10, #0x423f            ; =16959
10000e730: 72a001ea    	movk	w10, #0xf, lsl #16
10000e734: eb0a011f    	cmp	x8, x10
10000e738: 54000069    	b.ls	0x10000e744 <_fmt.float.round__anon_5325+0x130>
10000e73c: 528000ea    	mov	w10, #0x7               ; =7
10000e740: 14000016    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e744: d345fd0a    	lsr	x10, x8, #5
10000e748: f130d15f    	cmp	x10, #0xc34
10000e74c: 54000069    	b.ls	0x10000e758 <_fmt.float.round__anon_5325+0x144>
10000e750: 528000ca    	mov	w10, #0x6               ; =6
10000e754: 14000011    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e758: d344fd0a    	lsr	x10, x8, #4
10000e75c: f109c15f    	cmp	x10, #0x270
10000e760: 54000069    	b.ls	0x10000e76c <_fmt.float.round__anon_5325+0x158>
10000e764: 528000aa    	mov	w10, #0x5               ; =5
10000e768: 1400000c    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e76c: f10f9d1f    	cmp	x8, #0x3e7
10000e770: 54000069    	b.ls	0x10000e77c <_fmt.float.round__anon_5325+0x168>
10000e774: 5280008a    	mov	w10, #0x4               ; =4
10000e778: 14000008    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e77c: f1018d1f    	cmp	x8, #0x63
10000e780: 54000069    	b.ls	0x10000e78c <_fmt.float.round__anon_5325+0x178>
10000e784: 5280006a    	mov	w10, #0x3               ; =3
10000e788: 14000004    	b	0x10000e798 <_fmt.float.round__anon_5325+0x184>
10000e78c: f100251f    	cmp	x8, #0x9
10000e790: 5280002a    	mov	w10, #0x1               ; =1
10000e794: 1a8a954a    	cinc	w10, w10, hi
10000e798: 5100054b    	sub	w11, w10, #0x1
10000e79c: 8b09006c    	add	x12, x3, x9
10000e7a0: 8b0b018b    	add	x11, x12, x11
10000e7a4: 8b2a406c    	add	x12, x3, w10, uxtw
10000e7a8: 4b0903ed    	neg	w13, w9
10000e7ac: eb0d018c    	subs	x12, x12, x13
10000e7b0: 9a8c33ec    	csel	x12, xzr, x12, lo
10000e7b4: 7100013f    	cmp	w9, #0x0
10000e7b8: 9a8cc16b    	csel	x11, x11, x12, gt
10000e7bc: 7200005f    	tst	w2, #0x1
10000e7c0: 9a83056b    	csinc	x11, x11, x3, eq
10000e7c4: 2a0a03ec    	mov	w12, w10
10000e7c8: eb0c017f    	cmp	x11, x12
10000e7cc: 540003c2    	b.hs	0x10000e844 <_fmt.float.round__anon_5325+0x230>
10000e7d0: aa2b03ed    	mvn	x13, x11
10000e7d4: ab0c01ac    	adds	x12, x13, x12
10000e7d8: 54000140    	b.eq	0x10000e800 <_fmt.float.round__anon_5325+0x1ec>
10000e7dc: 0b090149    	add	w9, w10, w9
10000e7e0: b202e7ea    	mov	x10, #-0x3333333333333334 ; =-3689348814741910324
10000e7e4: f29999aa    	movk	x10, #0xcccd
10000e7e8: 9bca7d08    	umulh	x8, x8, x10
10000e7ec: d343fd08    	lsr	x8, x8, #3
10000e7f0: f100058c    	subs	x12, x12, #0x1
10000e7f4: 54ffffa1    	b.ne	0x10000e7e8 <_fmt.float.round__anon_5325+0x1d4>
10000e7f8: 2a2b03ea    	mvn	w10, w11
10000e7fc: 0b0a0129    	add	w9, w9, w10
10000e800: b202e7ea    	mov	x10, #-0x3333333333333334 ; =-3689348814741910324
10000e804: f29999aa    	movk	x10, #0xcccd
10000e808: 9bca7d0a    	umulh	x10, x8, x10
10000e80c: d343fd4a    	lsr	x10, x10, #3
10000e810: 5280014b    	mov	w11, #0xa               ; =10
10000e814: 9b0ba14b    	msub	x11, x10, x11, x8
10000e818: f100157f    	cmp	x11, #0x5
10000e81c: 54000143    	b.lo	0x10000e844 <_fmt.float.round__anon_5325+0x230>
10000e820: 91000548    	add	x8, x10, #0x1
10000e824: 1100052a    	add	w10, w9, #0x1
10000e828: b201e7eb    	mov	x11, #-0x6666666666666667 ; =-7378697629483820647
10000e82c: d241096b    	eor	x11, x11, #0x8000000000000003
10000e830: 9bcb7d0b    	umulh	x11, x8, x11
10000e834: 5280014c    	mov	w12, #0xa               ; =10
10000e838: 9b0ca16c    	msub	x12, x11, x12, x8
10000e83c: b40000ec    	cbz	x12, 0x10000e858 <_fmt.float.round__anon_5325+0x244>
10000e840: aa0a03e9    	mov	x9, x10
10000e844: f9000008    	str	x8, [x0]
10000e848: b9000809    	str	w9, [x0, #0x8]
10000e84c: 39403028    	ldrb	w8, [x1, #0xc]
10000e850: 39003008    	strb	w8, [x0, #0xc]
10000e854: d65f03c0    	ret
10000e858: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
10000e85c: a9017bfd    	stp	x29, x30, [sp, #0x10]
10000e860: 910043fd    	add	x29, sp, #0x10
10000e864: d2800004    	mov	x4, #0x0                ; =0
10000e868: b202e7ec    	mov	x12, #-0x3333333333333334 ; =-3689348814741910324
10000e86c: f29999ac    	movk	x12, #0xcccd
10000e870: b202e7ed    	mov	x13, #-0x3333333333333334 ; =-3689348814741910324
10000e874: d291eb8e    	mov	x14, #0x8f5c            ; =36700
10000e878: f2beb84e    	movk	x14, #0xf5c2, lsl #16
10000e87c: f2cb850e    	movk	x14, #0x5c28, lsl #32
10000e880: f2f851ee    	movk	x14, #0xc28f, lsl #48
10000e884: d28b852f    	mov	x15, #0x5c29            ; =23593
10000e888: f2b851ef    	movk	x15, #0xc28f, lsl #16
10000e88c: f2c51eaf    	movk	x15, #0x28f5, lsl #32
10000e890: f2f1eb8f    	movk	x15, #0x8f5c, lsl #48
10000e894: b201e7f0    	mov	x16, #-0x6666666666666667 ; =-7378697629483820647
10000e898: f2933350    	movk	x16, #0x999a
10000e89c: b201e7e2    	mov	x2, #-0x6666666666666667 ; =-7378697629483820647
10000e8a0: f2e33322    	movk	x2, #0x1999, lsl #48
10000e8a4: aa0803e5    	mov	x5, x8
10000e8a8: aa0403f1    	mov	x17, x4
10000e8ac: aa0503e3    	mov	x3, x5
10000e8b0: 93c50484    	extr	x4, x4, x5, #0x1
10000e8b4: d341fe25    	lsr	x5, x17, #1
10000e8b8: ab050086    	adds	x6, x4, x5
10000e8bc: 9a8634c6    	cinc	x6, x6, hs
10000e8c0: 9bcc7cc7    	umulh	x7, x6, x12
10000e8c4: d342fce7    	lsr	x7, x7, #2
10000e8c8: 8b0708e7    	add	x7, x7, x7, lsl #2
10000e8cc: cb0700c6    	sub	x6, x6, x7
10000e8d0: eb060086    	subs	x6, x4, x6
10000e8d4: 9bcc7cc4    	umulh	x4, x6, x12
10000e8d8: 9b0d10c4    	madd	x4, x6, x13, x4
10000e8dc: da1f00a5    	sbc	x5, x5, xzr
10000e8e0: 9b0c10a4    	madd	x4, x5, x12, x4
10000e8e4: 9b0c7cc5    	mul	x5, x6, x12
10000e8e8: f100287f    	cmp	x3, #0xa
10000e8ec: fa1f023f    	sbcs	xzr, x17, xzr
10000e8f0: 1a9f27e7    	cset	w7, lo
10000e8f4: 9bcc7cb3    	umulh	x19, x5, x12
10000e8f8: 9b0e4cd3    	madd	x19, x6, x14, x19
10000e8fc: 9b0c4c93    	madd	x19, x4, x12, x19
10000e900: 9b0f7cc6    	mul	x6, x6, x15
10000e904: 93d304d4    	extr	x20, x6, x19, #0x1
10000e908: 93c60666    	extr	x6, x19, x6, #0x1
10000e90c: eb1000df    	cmp	x6, x16
10000e910: fa02029f    	sbcs	xzr, x20, x2
10000e914: 1a9f27e6    	cset	w6, lo
10000e918: 6b0600ff    	cmp	w7, w6
10000e91c: 54fffc61    	b.ne	0x10000e8a8 <_fmt.float.round__anon_5325+0x294>
10000e920: 11000929    	add	w9, w9, #0x2
10000e924: f100287f    	cmp	x3, #0xa
10000e928: fa1f023f    	sbcs	xzr, x17, xzr
10000e92c: 1a8a3129    	csel	w9, w9, w10, lo
10000e930: 9a883168    	csel	x8, x11, x8, lo
10000e934: a9417bfd    	ldp	x29, x30, [sp, #0x10]
10000e938: a8c24ff4    	ldp	x20, x19, [sp], #0x20
10000e93c: f9000008    	str	x8, [x0]
10000e940: b9000809    	str	w9, [x0, #0x8]
10000e944: 39403028    	ldrb	w8, [x1, #0xc]
10000e948: 39003008    	strb	w8, [x0, #0xc]
10000e94c: d65f03c0    	ret

000000010000e950 <_Io.Writer.writeSplat>:
10000e950: d10183ff    	sub	sp, sp, #0x60
10000e954: a90167fa    	stp	x26, x25, [sp, #0x10]
10000e958: a9025ff8    	stp	x24, x23, [sp, #0x20]
10000e95c: a90357f6    	stp	x22, x21, [sp, #0x30]
10000e960: a9044ff4    	stp	x20, x19, [sp, #0x40]
10000e964: a9057bfd    	stp	x29, x30, [sp, #0x50]
10000e968: 910143fd    	add	x29, sp, #0x50
10000e96c: aa0203f4    	mov	x20, x2
10000e970: aa0003f3    	mov	x19, x0
10000e974: d0000069    	adrp	x9, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e978: 91062129    	add	x9, x9, #0x188
10000e97c: f9400435    	ldr	x21, [x1, #0x8]
10000e980: 9b027eb7    	mul	x23, x21, x2
10000e984: a940a12a    	ldp	x10, x8, [x9, #0x8]
10000e988: 8b17010b    	add	x11, x8, x23
10000e98c: eb0a017f    	cmp	x11, x10
10000e990: 54000189    	b.ls	0x10000e9c0 <_Io.Writer.writeSplat+0x70>
10000e994: d0000060    	adrp	x0, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e998: 91060000    	add	x0, x0, #0x180
10000e99c: f9400008    	ldr	x8, [x0]
10000e9a0: f9400109    	ldr	x9, [x8]
10000e9a4: 910003e8    	mov	x8, sp
10000e9a8: 52800022    	mov	w2, #0x1                ; =1
10000e9ac: aa1403e3    	mov	x3, x20
10000e9b0: d63f0120    	blr	x9
10000e9b4: 3dc003e0    	ldr	q0, [sp]
10000e9b8: 3d800260    	str	q0, [x19]
10000e9bc: 1400001b    	b	0x10000ea28 <_Io.Writer.writeSplat+0xd8>
10000e9c0: b4000315    	cbz	x21, 0x10000ea20 <_Io.Writer.writeSplat+0xd0>
10000e9c4: f9400138    	ldr	x24, [x9]
10000e9c8: f9400036    	ldr	x22, [x1]
10000e9cc: f10006bf    	cmp	x21, #0x1
10000e9d0: 54000141    	b.ne	0x10000e9f8 <_Io.Writer.writeSplat+0xa8>
10000e9d4: 394002c1    	ldrb	w1, [x22]
10000e9d8: 8b080300    	add	x0, x24, x8
10000e9dc: aa1403e2    	mov	x2, x20
10000e9e0: 940002fc    	bl	0x10000f5d0 <dyld_stub_binder+0x10000f5d0>
10000e9e4: d0000068    	adrp	x8, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e9e8: f940cd09    	ldr	x9, [x8, #0x198]
10000e9ec: 8b140129    	add	x9, x9, x20
10000e9f0: f900cd09    	str	x9, [x8, #0x198]
10000e9f4: 1400000b    	b	0x10000ea20 <_Io.Writer.writeSplat+0xd0>
10000e9f8: d0000079    	adrp	x25, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000e9fc: 8b080300    	add	x0, x24, x8
10000ea00: aa1603e1    	mov	x1, x22
10000ea04: aa1503e2    	mov	x2, x21
10000ea08: 940002ec    	bl	0x10000f5b8 <dyld_stub_binder+0x10000f5b8>
10000ea0c: f940cf28    	ldr	x8, [x25, #0x198]
10000ea10: 8b150108    	add	x8, x8, x21
10000ea14: f900cf28    	str	x8, [x25, #0x198]
10000ea18: f1000694    	subs	x20, x20, #0x1
10000ea1c: 54ffff01    	b.ne	0x10000e9fc <_Io.Writer.writeSplat+0xac>
10000ea20: 7900127f    	strh	wzr, [x19, #0x8]
10000ea24: f9000277    	str	x23, [x19]
10000ea28: a9457bfd    	ldp	x29, x30, [sp, #0x50]
10000ea2c: a9444ff4    	ldp	x20, x19, [sp, #0x40]
10000ea30: a94357f6    	ldp	x22, x21, [sp, #0x30]
10000ea34: a9425ff8    	ldp	x24, x23, [sp, #0x20]
10000ea38: a94167fa    	ldp	x26, x25, [sp, #0x10]
10000ea3c: 910183ff    	add	sp, sp, #0x60
10000ea40: d65f03c0    	ret

000000010000ea44 <_fs.File.Writer.sendFile>:
10000ea44: d10383ff    	sub	sp, sp, #0xe0
10000ea48: a90967fa    	stp	x26, x25, [sp, #0x90]
10000ea4c: a90a5ff8    	stp	x24, x23, [sp, #0xa0]
10000ea50: a90b57f6    	stp	x22, x21, [sp, #0xb0]
10000ea54: a90c4ff4    	stp	x20, x19, [sp, #0xc0]
10000ea58: a90d7bfd    	stp	x29, x30, [sp, #0xd0]
10000ea5c: 910343fd    	add	x29, sp, #0xd0
10000ea60: aa0103f4    	mov	x20, x1
10000ea64: aa0803f3    	mov	x19, x8
10000ea68: a9432829    	ldp	x9, x10, [x1, #0x30]
10000ea6c: f9401028    	ldr	x8, [x1, #0x20]
10000ea70: 8b090118    	add	x24, x8, x9
10000ea74: cb090157    	sub	x23, x10, x9
10000ea78: eb170048    	subs	x8, x2, x23
10000ea7c: 540001e9    	b.ls	0x10000eab8 <_fs.File.Writer.sendFile+0x74>
10000ea80: f940040b    	ldr	x11, [x0, #0x8]
10000ea84: f9400c1a    	ldr	x26, [x0, #0x18]
10000ea88: b9402015    	ldr	w21, [x0, #0x20]
10000ea8c: b9404296    	ldr	w22, [x20, #0x40]
10000ea90: 3940428c    	ldrb	w12, [x20, #0x10]
10000ea94: 340003ac    	cbz	w12, 0x10000eb08 <_fs.File.Writer.sendFile+0xc4>
10000ea98: a940328d    	ldp	x13, x12, [x20]
10000ea9c: eb0d019f    	cmp	x12, x13
10000eaa0: 54000341    	b.ne	0x10000eb08 <_fs.File.Writer.sendFile+0xc4>
10000eaa4: eb09015f    	cmp	x10, x9
10000eaa8: 540005a1    	b.ne	0x10000eb5c <_fs.File.Writer.sendFile+0x118>
10000eaac: d0000008    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
10000eab0: 91194108    	add	x8, x8, #0x650
10000eab4: 14000021    	b	0x10000eb38 <_fs.File.Writer.sendFile+0xf4>
10000eab8: a93a0bb8    	stp	x24, x2, [x29, #-0x60]
10000eabc: d10143a8    	sub	x8, x29, #0x50
10000eac0: d10183a1    	sub	x1, x29, #0x60
10000eac4: 52800022    	mov	w2, #0x1                ; =1
10000eac8: 52800023    	mov	w3, #0x1                ; =1
10000eacc: 940000f1    	bl	0x10000ee90 <_fs.File.Writer.drain>
10000ead0: 785b83a8    	ldurh	w8, [x29, #-0x48]
10000ead4: 35001928    	cbnz	w8, 0x10000edf8 <_fs.File.Writer.sendFile+0x3b4>
10000ead8: f85b03b5    	ldur	x21, [x29, #-0x50]
10000eadc: aa1403e0    	mov	x0, x20
10000eae0: aa1503e1    	mov	x1, x21
10000eae4: 97fffda4    	bl	0x10000e174 <_fs.File.Reader.seekBy>
10000eae8: 72003c1f    	tst	w0, #0xffff
10000eaec: 52800068    	mov	w8, #0x3                ; =3
10000eaf0: 1a8803e8    	csel	w8, wzr, w8, eq
10000eaf4: f9000275    	str	x21, [x19]
10000eaf8: 79001268    	strh	w8, [x19, #0x8]
10000eafc: b800a27f    	stur	wzr, [x19, #0xa]
10000eb00: 79001e7f    	strh	wzr, [x19, #0xe]
10000eb04: 1400000f    	b	0x10000eb40 <_fs.File.Writer.sendFile+0xfc>
10000eb08: aa0203ec    	mov	x12, x2
10000eb0c: 3940b80d    	ldrb	w13, [x0, #0x2e]
10000eb10: 720009bf    	tst	w13, #0x7
10000eb14: 54000061    	b.ne	0x10000eb20 <_fs.File.Writer.sendFile+0xdc>
10000eb18: 79404c0d    	ldrh	w13, [x0, #0x26]
10000eb1c: 3400024d    	cbz	w13, 0x10000eb64 <_fs.File.Writer.sendFile+0x120>
10000eb20: 79405408    	ldrh	w8, [x0, #0x2a]
10000eb24: 35000068    	cbnz	w8, 0x10000eb30 <_fs.File.Writer.sendFile+0xec>
10000eb28: f9400288    	ldr	x8, [x20]
10000eb2c: b40002c8    	cbz	x8, 0x10000eb84 <_fs.File.Writer.sendFile+0x140>
10000eb30: d0000008    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
10000eb34: 91198108    	add	x8, x8, #0x660
10000eb38: 3dc00100    	ldr	q0, [x8]
10000eb3c: 3d800260    	str	q0, [x19]
10000eb40: a94d7bfd    	ldp	x29, x30, [sp, #0xd0]
10000eb44: a94c4ff4    	ldp	x20, x19, [sp, #0xc0]
10000eb48: a94b57f6    	ldp	x22, x21, [sp, #0xb0]
10000eb4c: a94a5ff8    	ldp	x24, x23, [sp, #0xa0]
10000eb50: a94967fa    	ldp	x26, x25, [sp, #0x90]
10000eb54: 910383ff    	add	sp, sp, #0xe0
10000eb58: d65f03c0    	ret
10000eb5c: a93a5fb8    	stp	x24, x23, [x29, #-0x60]
10000eb60: 17ffffd7    	b	0x10000eabc <_fs.File.Writer.sendFile+0x78>
10000eb64: f9400282    	ldr	x2, [x20]
10000eb68: b7fffdc2    	tbnz	x2, #0x3f, 0x10000eb20 <_fs.File.Writer.sendFile+0xdc>
10000eb6c: b400037a    	cbz	x26, 0x10000ebd8 <_fs.File.Writer.sendFile+0x194>
10000eb70: a902ebeb    	stp	x11, x26, [sp, #0x28]
10000eb74: 5280002b    	mov	w11, #0x1               ; =1
10000eb78: eb09015f    	cmp	x10, x9
10000eb7c: 540003a1    	b.ne	0x10000ebf0 <_fs.File.Writer.sendFile+0x1ac>
10000eb80: 14000020    	b	0x10000ec00 <_fs.File.Writer.sendFile+0x1bc>
10000eb84: b100059f    	cmn	x12, #0x1
10000eb88: 54fffd41    	b.ne	0x10000eb30 <_fs.File.Writer.sendFile+0xec>
10000eb8c: f85f8008    	ldur	x8, [x0, #-0x8]
10000eb90: b5fffd08    	cbnz	x8, 0x10000eb30 <_fs.File.Writer.sendFile+0xec>
10000eb94: aa0003f9    	mov	x25, x0
10000eb98: 910143e0    	add	x0, sp, #0x50
10000eb9c: aa1403e1    	mov	x1, x20
10000eba0: 97fffd22    	bl	0x10000e028 <_fs.File.Reader.getSize>
10000eba4: 7940b3e8    	ldrh	w8, [sp, #0x58]
10000eba8: 35fffc48    	cbnz	w8, 0x10000eb30 <_fs.File.Writer.sendFile+0xec>
10000ebac: aa170348    	orr	x8, x26, x23
10000ebb0: b4000a48    	cbz	x8, 0x10000ecf8 <_fs.File.Writer.sendFile+0x2b4>
10000ebb4: 910183e0    	add	x0, sp, #0x60
10000ebb8: aa1903e1    	mov	x1, x25
10000ebbc: aa1403e2    	mov	x2, x20
10000ebc0: aa1803e3    	mov	x3, x24
10000ebc4: aa1703e4    	mov	x4, x23
10000ebc8: 9400008d    	bl	0x10000edfc <_fs.File.Writer.sendFileBuffered>
10000ebcc: 3dc01be0    	ldr	q0, [sp, #0x60]
10000ebd0: 3d800260    	str	q0, [x19]
10000ebd4: 1400007e    	b	0x10000edcc <_fs.File.Writer.sendFile+0x388>
10000ebd8: eb09015f    	cmp	x10, x9
10000ebdc: 54000081    	b.ne	0x10000ebec <_fs.File.Writer.sendFile+0x1a8>
10000ebe0: aa0003f7    	mov	x23, x0
10000ebe4: d2800004    	mov	x4, #0x0                ; =0
10000ebe8: 1400000d    	b	0x10000ec1c <_fs.File.Writer.sendFile+0x1d8>
10000ebec: 5280000b    	mov	w11, #0x0               ; =0
10000ebf0: 9100a3e9    	add	x9, sp, #0x28
10000ebf4: 8b2b5129    	add	x9, x9, w11, uxtw #4
10000ebf8: a9005d38    	stp	x24, x23, [x9]
10000ebfc: 1100056b    	add	w11, w11, #0x1
10000ec00: aa0003f7    	mov	x23, x0
10000ec04: 9100a3e9    	add	x9, sp, #0x28
10000ec08: f90007e9    	str	x9, [sp, #0x8]
10000ec0c: b90013eb    	str	w11, [sp, #0x10]
10000ec10: f9000fff    	str	xzr, [sp, #0x18]
10000ec14: b90023ff    	str	wzr, [sp, #0x20]
10000ec18: 910023e4    	add	x4, sp, #0x8
10000ec1c: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000ec20: eb09011f    	cmp	x8, x9
10000ec24: 9a893108    	csel	x8, x8, x9, lo
10000ec28: f90027e8    	str	x8, [sp, #0x48]
10000ec2c: 910123e3    	add	x3, sp, #0x48
10000ec30: aa1603e0    	mov	x0, x22
10000ec34: aa1503e1    	mov	x1, x21
10000ec38: 52800005    	mov	w5, #0x0                ; =0
10000ec3c: 94000277    	bl	0x10000f618 <dyld_stub_binder+0x10000f618>
10000ec40: 3100041f    	cmn	w0, #0x1
10000ec44: 540001e0    	b.eq	0x10000ec80 <_fs.File.Writer.sendFile+0x23c>
10000ec48: 79404ee8    	ldrh	w8, [x23, #0x26]
10000ec4c: 35000be8    	cbnz	w8, 0x10000edc8 <_fs.File.Writer.sendFile+0x384>
10000ec50: f94027e8    	ldr	x8, [sp, #0x48]
10000ec54: b40006c8    	cbz	x8, 0x10000ed2c <_fs.File.Writer.sendFile+0x2e8>
10000ec58: f9400ee9    	ldr	x9, [x23, #0x18]
10000ec5c: eb090115    	subs	x21, x8, x9
10000ec60: 54000742    	b.hs	0x10000ed48 <_fs.File.Writer.sendFile+0x304>
10000ec64: f94006e0    	ldr	x0, [x23, #0x8]
10000ec68: cb080136    	sub	x22, x9, x8
10000ec6c: 8b080001    	add	x1, x0, x8
10000ec70: aa1603e2    	mov	x2, x22
10000ec74: 94000254    	bl	0x10000f5c4 <dyld_stub_binder+0x10000f5c4>
10000ec78: d2800015    	mov	x21, #0x0               ; =0
10000ec7c: 14000034    	b	0x10000ed4c <_fs.File.Writer.sendFile+0x308>
10000ec80: 94000257    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
10000ec84: b9400008    	ldr	w8, [x0]
10000ec88: 71007d1f    	cmp	w8, #0x1f
10000ec8c: 5400024d    	b.le	0x10000ecd4 <_fs.File.Writer.sendFile+0x290>
10000ec90: 51008108    	sub	w8, w8, #0x20
10000ec94: 7100b91f    	cmp	w8, #0x2e
10000ec98: 54000948    	b.hi	0x10000edc0 <_fs.File.Writer.sendFile+0x37c>
10000ec9c: 52800029    	mov	w9, #0x1                ; =1
10000eca0: 9ac82129    	lsl	x9, x9, x8
10000eca4: d284080a    	mov	x10, #0x2040            ; =8256
10000eca8: f2c8000a    	movk	x10, #0x4000, lsl #32
10000ecac: ea0a013f    	tst	x9, x10
10000ecb0: 54000201    	b.ne	0x10000ecf0 <_fs.File.Writer.sendFile+0x2ac>
10000ecb4: 52800029    	mov	w9, #0x1                ; =1
10000ecb8: 9ac82129    	lsl	x9, x9, x8
10000ecbc: 5280002a    	mov	w10, #0x1               ; =1
10000ecc0: 72a0400a    	movk	w10, #0x200, lsl #16
10000ecc4: ea0a013f    	tst	x9, x10
10000ecc8: 540005e0    	b.eq	0x10000ed84 <_fs.File.Writer.sendFile+0x340>
10000eccc: 52800148    	mov	w8, #0xa                ; =10
10000ecd0: 1400003d    	b	0x10000edc4 <_fs.File.Writer.sendFile+0x380>
10000ecd4: 34fffba8    	cbz	w8, 0x10000ec48 <_fs.File.Writer.sendFile+0x204>
10000ecd8: 7100111f    	cmp	w8, #0x4
10000ecdc: 54fffb60    	b.eq	0x10000ec48 <_fs.File.Writer.sendFile+0x204>
10000ece0: 7100151f    	cmp	w8, #0x5
10000ece4: 540006e1    	b.ne	0x10000edc0 <_fs.File.Writer.sendFile+0x37c>
10000ece8: 528000c8    	mov	w8, #0x6                ; =6
10000ecec: 14000036    	b	0x10000edc4 <_fs.File.Writer.sendFile+0x380>
10000ecf0: 52800448    	mov	w8, #0x22               ; =34
10000ecf4: 14000034    	b	0x10000edc4 <_fs.File.Writer.sendFile+0x380>
10000ecf8: f9402bf7    	ldr	x23, [sp, #0x50]
10000ecfc: aa1603e0    	mov	x0, x22
10000ed00: aa1503e1    	mov	x1, x21
10000ed04: d2800002    	mov	x2, #0x0                ; =0
10000ed08: 52800103    	mov	w3, #0x8                ; =8
10000ed0c: 9400021f    	bl	0x10000f588 <dyld_stub_binder+0x10000f588>
10000ed10: 3100041f    	cmn	w0, #0x1
10000ed14: 54000440    	b.eq	0x10000ed9c <_fs.File.Writer.sendFile+0x358>
10000ed18: f9000297    	str	x23, [x20]
10000ed1c: f81f8337    	stur	x23, [x25, #-0x8]
10000ed20: 7900127f    	strh	wzr, [x19, #0x8]
10000ed24: f9000277    	str	x23, [x19]
10000ed28: 14000029    	b	0x10000edcc <_fs.File.Writer.sendFile+0x388>
10000ed2c: f9400288    	ldr	x8, [x20]
10000ed30: f9000688    	str	x8, [x20, #0x8]
10000ed34: 52800028    	mov	w8, #0x1                ; =1
10000ed38: 39004288    	strb	w8, [x20, #0x10]
10000ed3c: d0000008    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
10000ed40: 91194108    	add	x8, x8, #0x650
10000ed44: 1400000a    	b	0x10000ed6c <_fs.File.Writer.sendFile+0x328>
10000ed48: d2800016    	mov	x22, #0x0               ; =0
10000ed4c: f9000ef6    	str	x22, [x23, #0x18]
10000ed50: aa1403e0    	mov	x0, x20
10000ed54: aa1503e1    	mov	x1, x21
10000ed58: 97fffd07    	bl	0x10000e174 <_fs.File.Reader.seekBy>
10000ed5c: 72003c1f    	tst	w0, #0xffff
10000ed60: 540000c0    	b.eq	0x10000ed78 <_fs.File.Writer.sendFile+0x334>
10000ed64: d0000008    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
10000ed68: 911a0108    	add	x8, x8, #0x680
10000ed6c: 3dc00100    	ldr	q0, [x8]
10000ed70: 3d800260    	str	q0, [x19]
10000ed74: 14000016    	b	0x10000edcc <_fs.File.Writer.sendFile+0x388>
10000ed78: 7900127f    	strh	wzr, [x19, #0x8]
10000ed7c: f9000275    	str	x21, [x19]
10000ed80: 14000013    	b	0x10000edcc <_fs.File.Writer.sendFile+0x388>
10000ed84: f1000d1f    	cmp	x8, #0x3
10000ed88: 540001c1    	b.ne	0x10000edc0 <_fs.File.Writer.sendFile+0x37c>
10000ed8c: f94027e8    	ldr	x8, [sp, #0x48]
10000ed90: b5fff5c8    	cbnz	x8, 0x10000ec48 <_fs.File.Writer.sendFile+0x204>
10000ed94: 528001e8    	mov	w8, #0xf                ; =15
10000ed98: 1400000b    	b	0x10000edc4 <_fs.File.Writer.sendFile+0x380>
10000ed9c: 94000210    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
10000eda0: b9400008    	ldr	w8, [x0]
10000eda4: 7100551f    	cmp	w8, #0x15
10000eda8: 5400014c    	b.gt	0x10000edd0 <_fs.File.Writer.sendFile+0x38c>
10000edac: 34fffb68    	cbz	w8, 0x10000ed18 <_fs.File.Writer.sendFile+0x2d4>
10000edb0: 7100311f    	cmp	w8, #0xc
10000edb4: 540001a1    	b.ne	0x10000ede8 <_fs.File.Writer.sendFile+0x3a4>
10000edb8: 528004e8    	mov	w8, #0x27               ; =39
10000edbc: 1400000c    	b	0x10000edec <_fs.File.Writer.sendFile+0x3a8>
10000edc0: 52800288    	mov	w8, #0x14               ; =20
10000edc4: 79004ee8    	strh	w8, [x23, #0x26]
10000edc8: a9007e7f    	stp	xzr, xzr, [x19]
10000edcc: 17ffff5d    	b	0x10000eb40 <_fs.File.Writer.sendFile+0xfc>
10000edd0: 7100591f    	cmp	w8, #0x16
10000edd4: 540000a0    	b.eq	0x10000ede8 <_fs.File.Writer.sendFile+0x3a4>
10000edd8: 7100b51f    	cmp	w8, #0x2d
10000eddc: 54000061    	b.ne	0x10000ede8 <_fs.File.Writer.sendFile+0x3a4>
10000ede0: 52800508    	mov	w8, #0x28               ; =40
10000ede4: 14000002    	b	0x10000edec <_fs.File.Writer.sendFile+0x3a8>
10000ede8: 52800288    	mov	w8, #0x14               ; =20
10000edec: 79005728    	strh	w8, [x25, #0x2a]
10000edf0: a9007e7f    	stp	xzr, xzr, [x19]
10000edf4: 17ffff53    	b	0x10000eb40 <_fs.File.Writer.sendFile+0xfc>
10000edf8: 17ffff3f    	b	0x10000eaf4 <_fs.File.Writer.sendFile+0xb0>

000000010000edfc <_fs.File.Writer.sendFileBuffered>:
10000edfc: d10143ff    	sub	sp, sp, #0x50
10000ee00: a90257f6    	stp	x22, x21, [sp, #0x20]
10000ee04: a9034ff4    	stp	x20, x19, [sp, #0x30]
10000ee08: a9047bfd    	stp	x29, x30, [sp, #0x40]
10000ee0c: 910103fd    	add	x29, sp, #0x40
10000ee10: aa0203f4    	mov	x20, x2
10000ee14: aa0103e9    	mov	x9, x1
10000ee18: aa0003f3    	mov	x19, x0
10000ee1c: a90013e3    	stp	x3, x4, [sp]
10000ee20: 910043e8    	add	x8, sp, #0x10
10000ee24: 910003e1    	mov	x1, sp
10000ee28: aa0903e0    	mov	x0, x9
10000ee2c: 52800022    	mov	w2, #0x1                ; =1
10000ee30: 52800023    	mov	w3, #0x1                ; =1
10000ee34: 94000017    	bl	0x10000ee90 <_fs.File.Writer.drain>
10000ee38: 794033e8    	ldrh	w8, [sp, #0x18]
10000ee3c: 35000268    	cbnz	w8, 0x10000ee88 <_fs.File.Writer.sendFileBuffered+0x8c>
10000ee40: f9400bf5    	ldr	x21, [sp, #0x10]
10000ee44: aa1403e0    	mov	x0, x20
10000ee48: aa1503e1    	mov	x1, x21
10000ee4c: 97fffcca    	bl	0x10000e174 <_fs.File.Reader.seekBy>
10000ee50: 72003c1f    	tst	w0, #0xffff
10000ee54: 540000c0    	b.eq	0x10000ee6c <_fs.File.Writer.sendFileBuffered+0x70>
10000ee58: d0000008    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
10000ee5c: 911a0108    	add	x8, x8, #0x680
10000ee60: 3dc00100    	ldr	q0, [x8]
10000ee64: 3d800260    	str	q0, [x19]
10000ee68: 14000003    	b	0x10000ee74 <_fs.File.Writer.sendFileBuffered+0x78>
10000ee6c: 7900127f    	strh	wzr, [x19, #0x8]
10000ee70: f9000275    	str	x21, [x19]
10000ee74: a9447bfd    	ldp	x29, x30, [sp, #0x40]
10000ee78: a9434ff4    	ldp	x20, x19, [sp, #0x30]
10000ee7c: a94257f6    	ldp	x22, x21, [sp, #0x20]
10000ee80: 910143ff    	add	sp, sp, #0x50
10000ee84: d65f03c0    	ret
10000ee88: 79001268    	strh	w8, [x19, #0x8]
10000ee8c: 17fffffa    	b	0x10000ee74 <_fs.File.Writer.sendFileBuffered+0x78>

000000010000ee90 <_fs.File.Writer.drain>:
10000ee90: d10683ff    	sub	sp, sp, #0x1a0
10000ee94: a9146ffc    	stp	x28, x27, [sp, #0x140]
10000ee98: a91567fa    	stp	x26, x25, [sp, #0x150]
10000ee9c: a9165ff8    	stp	x24, x23, [sp, #0x160]
10000eea0: a91757f6    	stp	x22, x21, [sp, #0x170]
10000eea4: a9184ff4    	stp	x20, x19, [sp, #0x180]
10000eea8: a9197bfd    	stp	x29, x30, [sp, #0x190]
10000eeac: 910643fd    	add	x29, sp, #0x190
10000eeb0: aa0003f4    	mov	x20, x0
10000eeb4: aa0803f3    	mov	x19, x8
10000eeb8: f940040b    	ldr	x11, [x0, #0x8]
10000eebc: f9400c0c    	ldr	x12, [x0, #0x18]
10000eec0: b40000ec    	cbz	x12, 0x10000eedc <_fs.File.Writer.drain+0x4c>
10000eec4: a90033eb    	stp	x11, x12, [sp]
10000eec8: 52800038    	mov	w24, #0x1               ; =1
10000eecc: b9402295    	ldr	w21, [x20, #0x20]
10000eed0: f1000449    	subs	x9, x2, #0x1
10000eed4: 540000c1    	b.ne	0x10000eeec <_fs.File.Writer.drain+0x5c>
10000eed8: 1400001a    	b	0x10000ef40 <_fs.File.Writer.drain+0xb0>
10000eedc: d2800018    	mov	x24, #0x0               ; =0
10000eee0: b9402295    	ldr	w21, [x20, #0x20]
10000eee4: f1000449    	subs	x9, x2, #0x1
10000eee8: 540002c0    	b.eq	0x10000ef40 <_fs.File.Writer.drain+0xb0>
10000eeec: 9100202a    	add	x10, x1, #0x8
10000eef0: 910003ed    	mov	x13, sp
10000eef4: 52800208    	mov	w8, #0x10               ; =16
10000eef8: aa0903ee    	mov	x14, x9
10000eefc: 14000004    	b	0x10000ef0c <_fs.File.Writer.drain+0x7c>
10000ef00: 9100414a    	add	x10, x10, #0x10
10000ef04: f10005ce    	subs	x14, x14, #0x1
10000ef08: 54000140    	b.eq	0x10000ef30 <_fs.File.Writer.drain+0xa0>
10000ef0c: f940014f    	ldr	x15, [x10]
10000ef10: b4ffff8f    	cbz	x15, 0x10000ef00 <_fs.File.Writer.drain+0x70>
10000ef14: f85f8150    	ldur	x16, [x10, #-0x8]
10000ef18: 8b1811b1    	add	x17, x13, x24, lsl #4
10000ef1c: a9003e30    	stp	x16, x15, [x17]
10000ef20: f1003f1f    	cmp	x24, #0xf
10000ef24: 54000e00    	b.eq	0x10000f0e4 <_fs.File.Writer.drain+0x254>
10000ef28: 91000718    	add	x24, x24, #0x1
10000ef2c: 17fffff5    	b	0x10000ef00 <_fs.File.Writer.drain+0x70>
10000ef30: f100431f    	cmp	x24, #0x10
10000ef34: 54000061    	b.ne	0x10000ef40 <_fs.File.Writer.drain+0xb0>
10000ef38: 52800208    	mov	w8, #0x10               ; =16
10000ef3c: 1400006a    	b	0x10000f0e4 <_fs.File.Writer.drain+0x254>
10000ef40: b4000ce3    	cbz	x3, 0x10000f0dc <_fs.File.Writer.drain+0x24c>
10000ef44: 8b091028    	add	x8, x1, x9, lsl #4
10000ef48: a9402909    	ldp	x9, x10, [x8]
10000ef4c: f1000468    	subs	x8, x3, #0x1
10000ef50: 540000e1    	b.ne	0x10000ef6c <_fs.File.Writer.drain+0xdc>
10000ef54: b4000c4a    	cbz	x10, 0x10000f0dc <_fs.File.Writer.drain+0x24c>
10000ef58: 910003e8    	mov	x8, sp
10000ef5c: 8b181108    	add	x8, x8, x24, lsl #4
10000ef60: a9002909    	stp	x9, x10, [x8]
10000ef64: 91000708    	add	x8, x24, #0x1
10000ef68: 1400005f    	b	0x10000f0e4 <_fs.File.Writer.drain+0x254>
10000ef6c: b4000b8a    	cbz	x10, 0x10000f0dc <_fs.File.Writer.drain+0x24c>
10000ef70: f100055f    	cmp	x10, #0x1
10000ef74: 54000621    	b.ne	0x10000f038 <_fs.File.Writer.drain+0x1a8>
10000ef78: f9400a88    	ldr	x8, [x20, #0x10]
10000ef7c: 8b0c016a    	add	x10, x11, x12
10000ef80: cb0c0108    	sub	x8, x8, x12
10000ef84: d10243ab    	sub	x11, x29, #0x90
10000ef88: f100fd1f    	cmp	x8, #0x3f
10000ef8c: 9a8b8156    	csel	x22, x10, x11, hi
10000ef90: 5280080a    	mov	w10, #0x40              ; =64
10000ef94: 9a8a8119    	csel	x25, x8, x10, hi
10000ef98: eb03033f    	cmp	x25, x3
10000ef9c: 9a833337    	csel	x23, x25, x3, lo
10000efa0: 39400121    	ldrb	w1, [x9]
10000efa4: aa1603e0    	mov	x0, x22
10000efa8: aa1703e2    	mov	x2, x23
10000efac: aa0303fa    	mov	x26, x3
10000efb0: 94000188    	bl	0x10000f5d0 <dyld_stub_binder+0x10000f5d0>
10000efb4: 910003e8    	mov	x8, sp
10000efb8: 8b181108    	add	x8, x8, x24, lsl #4
10000efbc: a9005d16    	stp	x22, x23, [x8]
10000efc0: f1003f1f    	cmp	x24, #0xf
10000efc4: 1a9f07ea    	cset	w10, ne
10000efc8: cb170349    	sub	x9, x26, x23
10000efcc: eb19013f    	cmp	x9, x25
10000efd0: fa4f8b04    	ccmp	x24, #0xf, #0x4, hi
10000efd4: 54000220    	b.eq	0x10000f018 <_fs.File.Writer.drain+0x188>
10000efd8: 91006108    	add	x8, x8, #0x18
10000efdc: cb1903eb    	neg	x11, x25
10000efe0: aa1803ec    	mov	x12, x24
10000efe4: aa0903ed    	mov	x13, x9
10000efe8: a93fe516    	stp	x22, x25, [x8, #-0x8]
10000efec: cb190129    	sub	x9, x9, x25
10000eff0: f100399f    	cmp	x12, #0xe
10000eff4: 1a9f07ea    	cset	w10, ne
10000eff8: 91000598    	add	x24, x12, #0x1
10000effc: 8b0d016d    	add	x13, x11, x13
10000f000: eb1901bf    	cmp	x13, x25
10000f004: 540000a9    	b.ls	0x10000f018 <_fs.File.Writer.drain+0x188>
10000f008: 91004108    	add	x8, x8, #0x10
10000f00c: f100399f    	cmp	x12, #0xe
10000f010: aa1803ec    	mov	x12, x24
10000f014: 54fffe81    	b.ne	0x10000efe4 <_fs.File.Writer.drain+0x154>
10000f018: 91000708    	add	x8, x24, #0x1
10000f01c: b4000649    	cbz	x9, 0x10000f0e4 <_fs.File.Writer.drain+0x254>
10000f020: 3400062a    	cbz	w10, 0x10000f0e4 <_fs.File.Writer.drain+0x254>
10000f024: 910003ea    	mov	x10, sp
10000f028: 8b081148    	add	x8, x10, x8, lsl #4
10000f02c: a9002516    	stp	x22, x9, [x8]
10000f030: 91000b08    	add	x8, x24, #0x2
10000f034: 1400002c    	b	0x10000f0e4 <_fs.File.Writer.drain+0x254>
10000f038: 8b03030b    	add	x11, x24, x3
10000f03c: 528001ec    	mov	w12, #0xf               ; =15
10000f040: cb18018c    	sub	x12, x12, x24
10000f044: eb0c011f    	cmp	x8, x12
10000f048: 9a8c3108    	csel	x8, x8, x12, lo
10000f04c: 91000508    	add	x8, x8, #0x1
10000f050: f100211f    	cmp	x8, #0x8
10000f054: 540002a9    	b.ls	0x10000f0a8 <_fs.File.Writer.drain+0x218>
10000f058: f240090c    	ands	x12, x8, #0x7
10000f05c: 5280010d    	mov	w13, #0x8               ; =8
10000f060: 9a8c01ac    	csel	x12, x13, x12, eq
10000f064: cb0c0108    	sub	x8, x8, x12
10000f068: 8b08030c    	add	x12, x24, x8
10000f06c: 4e080d20    	dup.2d	v0, x9
10000f070: 9e670141    	fmov	d1, x10
10000f074: 6e014001    	ext.16b	v1, v0, v1, #0x8
10000f078: 4e181d40    	mov.d	v0[1], x10
10000f07c: 910003ed    	mov	x13, sp
10000f080: 8b1811ad    	add	x13, x13, x24, lsl #4
10000f084: 910101ad    	add	x13, x13, #0x40
10000f088: ad3e05a0    	stp	q0, q1, [x13, #-0x40]
10000f08c: ad3f05a0    	stp	q0, q1, [x13, #-0x20]
10000f090: ad0005a0    	stp	q0, q1, [x13]
10000f094: ad0105a0    	stp	q0, q1, [x13, #0x20]
10000f098: 910201ad    	add	x13, x13, #0x80
10000f09c: f1002108    	subs	x8, x8, #0x8
10000f0a0: 54ffff41    	b.ne	0x10000f088 <_fs.File.Writer.drain+0x1f8>
10000f0a4: aa0c03f8    	mov	x24, x12
10000f0a8: 910003e8    	mov	x8, sp
10000f0ac: 8b181108    	add	x8, x8, x24, lsl #4
10000f0b0: 9100210c    	add	x12, x8, #0x8
10000f0b4: cb18016d    	sub	x13, x11, x24
10000f0b8: d1003f0e    	sub	x14, x24, #0xf
10000f0bc: 52800208    	mov	w8, #0x10               ; =16
10000f0c0: a93fa989    	stp	x9, x10, [x12, #-0x8]
10000f0c4: b400010e    	cbz	x14, 0x10000f0e4 <_fs.File.Writer.drain+0x254>
10000f0c8: 9100418c    	add	x12, x12, #0x10
10000f0cc: 910005ce    	add	x14, x14, #0x1
10000f0d0: f10005ad    	subs	x13, x13, #0x1
10000f0d4: 54ffff61    	b.ne	0x10000f0c0 <_fs.File.Writer.drain+0x230>
10000f0d8: aa0b03f8    	mov	x24, x11
10000f0dc: aa1803e8    	mov	x8, x24
10000f0e0: b4000bf8    	cbz	x24, 0x10000f25c <_fs.File.Writer.drain+0x3cc>
10000f0e4: 3940ba89    	ldrb	w9, [x20, #0x2e]
10000f0e8: 12000929    	and	w9, w9, #0x7
10000f0ec: 7100053f    	cmp	w9, #0x1
10000f0f0: 540000cd    	b.le	0x10000f108 <_fs.File.Writer.drain+0x278>
10000f0f4: 7100093f    	cmp	w9, #0x2
10000f0f8: 540000a0    	b.eq	0x10000f10c <_fs.File.Writer.drain+0x27c>
10000f0fc: 71000d3f    	cmp	w9, #0x3
10000f100: 540003c0    	b.eq	0x10000f178 <_fs.File.Writer.drain+0x2e8>
10000f104: 140000dd    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f108: 35000389    	cbnz	w9, 0x10000f178 <_fs.File.Writer.drain+0x2e8>
10000f10c: 52800209    	mov	w9, #0x10               ; =16
10000f110: f100411f    	cmp	x8, #0x10
10000f114: 9a893116    	csel	x22, x8, x9, lo
10000f118: 910003e1    	mov	x1, sp
10000f11c: aa1503e0    	mov	x0, x21
10000f120: aa1603e2    	mov	x2, x22
10000f124: 94000140    	bl	0x10000f624 <dyld_stub_binder+0x10000f624>
10000f128: b100041f    	cmn	x0, #0x1
10000f12c: 54000da1    	b.ne	0x10000f2e0 <_fs.File.Writer.drain+0x450>
10000f130: 9400012b    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
10000f134: b9400008    	ldr	w8, [x0]
10000f138: 12003d09    	and	w9, w8, #0xffff
10000f13c: 7100113f    	cmp	w9, #0x4
10000f140: 54fffec0    	b.eq	0x10000f118 <_fs.File.Writer.drain+0x288>
10000f144: 7100691f    	cmp	w8, #0x1a
10000f148: 5400076c    	b.gt	0x10000f234 <_fs.File.Writer.drain+0x3a4>
10000f14c: 7100211f    	cmp	w8, #0x8
10000f150: 54000a4c    	b.gt	0x10000f298 <_fs.File.Writer.drain+0x408>
10000f154: 7100051f    	cmp	w8, #0x1
10000f158: 54000fc0    	b.eq	0x10000f350 <_fs.File.Writer.drain+0x4c0>
10000f15c: 71000d1f    	cmp	w8, #0x3
10000f160: 54000ec0    	b.eq	0x10000f338 <_fs.File.Writer.drain+0x4a8>
10000f164: 7100151f    	cmp	w8, #0x5
10000f168: 540010c1    	b.ne	0x10000f380 <_fs.File.Writer.drain+0x4f0>
10000f16c: 528000c8    	mov	w8, #0x6                ; =6
10000f170: 79004a88    	strh	w8, [x20, #0x24]
10000f174: 140000c1    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f178: f85f8296    	ldur	x22, [x20, #-0x8]
10000f17c: f94007e8    	ldr	x8, [sp, #0x8]
10000f180: b4000728    	cbz	x8, 0x10000f264 <_fs.File.Writer.drain+0x3d4>
10000f184: f94003f8    	ldr	x24, [sp]
10000f188: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10000f18c: eb09011f    	cmp	x8, x9
10000f190: 9a893119    	csel	x25, x8, x9, lo
10000f194: b000001a    	adrp	x26, 0x100010000 <dyld_stub_binder+0x100010000>
10000f198: 911a435a    	add	x26, x26, #0x690
10000f19c: aa1503e0    	mov	x0, x21
10000f1a0: aa1803e1    	mov	x1, x24
10000f1a4: aa1903e2    	mov	x2, x25
10000f1a8: aa1603e3    	mov	x3, x22
10000f1ac: 94000115    	bl	0x10000f600 <dyld_stub_binder+0x10000f600>
10000f1b0: aa0003f7    	mov	x23, x0
10000f1b4: b100041f    	cmn	x0, #0x1
10000f1b8: 54000aa1    	b.ne	0x10000f30c <_fs.File.Writer.drain+0x47c>
10000f1bc: 94000108    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
10000f1c0: b9400008    	ldr	w8, [x0]
10000f1c4: 12003d09    	and	w9, w8, #0xffff
10000f1c8: 7101513f    	cmp	w9, #0x54
10000f1cc: 54001168    	b.hi	0x10000f3f8 <_fs.File.Writer.drain+0x568>
10000f1d0: 10fffe69    	adr	x9, 0x10000f19c <_fs.File.Writer.drain+0x30c>
10000f1d4: 38686b4a    	ldrb	w10, [x26, x8]
10000f1d8: 8b0a0929    	add	x9, x9, x10, lsl #2
10000f1dc: d61f0120    	br	x9
10000f1e0: 3940ba88    	ldrb	w8, [x20, #0x2e]
10000f1e4: 521e0108    	eor	w8, w8, #0x4
10000f1e8: 12000908    	and	w8, w8, #0x7
10000f1ec: 0b080508    	add	w8, w8, w8, lsl #1
10000f1f0: 52800089    	mov	w9, #0x4                ; =4
10000f1f4: 72a00909    	movk	w9, #0x48, lsl #16
10000f1f8: 1ac82528    	lsr	w8, w9, w8
10000f1fc: 12000908    	and	w8, w8, #0x7
10000f200: 3900ba88    	strb	w8, [x20, #0x2e]
10000f204: f85f8295    	ldur	x21, [x20, #-0x8]
10000f208: b4001135    	cbz	x21, 0x10000f42c <_fs.File.Writer.drain+0x59c>
10000f20c: f81f829f    	stur	xzr, [x20, #-0x8]
10000f210: 3940ba88    	ldrb	w8, [x20, #0x2e]
10000f214: 12000908    	and	w8, w8, #0x7
10000f218: 7100051f    	cmp	w8, #0x1
10000f21c: 54000f4d    	b.le	0x10000f404 <_fs.File.Writer.drain+0x574>
10000f220: 7100111f    	cmp	w8, #0x4
10000f224: 54001080    	b.eq	0x10000f434 <_fs.File.Writer.drain+0x5a4>
10000f228: 71000d1f    	cmp	w8, #0x3
10000f22c: 54000ee1    	b.ne	0x10000f408 <_fs.File.Writer.drain+0x578>
10000f230: 1400007e    	b	0x10000f428 <_fs.File.Writer.drain+0x598>
10000f234: 7100891f    	cmp	w8, #0x22
10000f238: 5400042c    	b.gt	0x10000f2bc <_fs.File.Writer.drain+0x42c>
10000f23c: 51006d09    	sub	w9, w8, #0x1b
10000f240: 7100093f    	cmp	w9, #0x2
10000f244: 540004a3    	b.lo	0x10000f2d8 <_fs.File.Writer.drain+0x448>
10000f248: 7100811f    	cmp	w8, #0x20
10000f24c: 540009a1    	b.ne	0x10000f380 <_fs.File.Writer.drain+0x4f0>
10000f250: 52800148    	mov	w8, #0xa                ; =10
10000f254: 79004a88    	strh	w8, [x20, #0x24]
10000f258: 14000088    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f25c: a9007e7f    	stp	xzr, xzr, [x19]
10000f260: 1400008a    	b	0x10000f488 <_fs.File.Writer.drain+0x5f8>
10000f264: d2800017    	mov	x23, #0x0               ; =0
10000f268: 8b1702c8    	add	x8, x22, x23
10000f26c: f81f8288    	stur	x8, [x20, #-0x8]
10000f270: f9400e89    	ldr	x9, [x20, #0x18]
10000f274: eb0902e8    	subs	x8, x23, x9
10000f278: 54000562    	b.hs	0x10000f324 <_fs.File.Writer.drain+0x494>
10000f27c: f9400680    	ldr	x0, [x20, #0x8]
10000f280: cb170135    	sub	x21, x9, x23
10000f284: 8b170001    	add	x1, x0, x23
10000f288: aa1503e2    	mov	x2, x21
10000f28c: 940000ce    	bl	0x10000f5c4 <dyld_stub_binder+0x10000f5c4>
10000f290: d2800008    	mov	x8, #0x0                ; =0
10000f294: 14000025    	b	0x10000f328 <_fs.File.Writer.drain+0x498>
10000f298: 7100251f    	cmp	w8, #0x9
10000f29c: 54000600    	b.eq	0x10000f35c <_fs.File.Writer.drain+0x4cc>
10000f2a0: 7100411f    	cmp	w8, #0x10
10000f2a4: 54000500    	b.eq	0x10000f344 <_fs.File.Writer.drain+0x4b4>
10000f2a8: 7100591f    	cmp	w8, #0x16
10000f2ac: 540006a1    	b.ne	0x10000f380 <_fs.File.Writer.drain+0x4f0>
10000f2b0: 528003c8    	mov	w8, #0x1e               ; =30
10000f2b4: 79004a88    	strh	w8, [x20, #0x24]
10000f2b8: 14000070    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f2bc: 71008d1f    	cmp	w8, #0x23
10000f2c0: 540005a0    	b.eq	0x10000f374 <_fs.File.Writer.drain+0x4e4>
10000f2c4: 7100d91f    	cmp	w8, #0x36
10000f2c8: 54000500    	b.eq	0x10000f368 <_fs.File.Writer.drain+0x4d8>
10000f2cc: 7101151f    	cmp	w8, #0x45
10000f2d0: 54000581    	b.ne	0x10000f380 <_fs.File.Writer.drain+0x4f0>
10000f2d4: 52800348    	mov	w8, #0x1a               ; =26
10000f2d8: 79004a88    	strh	w8, [x20, #0x24]
10000f2dc: 14000067    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f2e0: f85f8288    	ldur	x8, [x20, #-0x8]
10000f2e4: 8b000108    	add	x8, x8, x0
10000f2e8: f81f8288    	stur	x8, [x20, #-0x8]
10000f2ec: f9400e89    	ldr	x9, [x20, #0x18]
10000f2f0: eb090008    	subs	x8, x0, x9
10000f2f4: 54000182    	b.hs	0x10000f324 <_fs.File.Writer.drain+0x494>
10000f2f8: f9400688    	ldr	x8, [x20, #0x8]
10000f2fc: cb000135    	sub	x21, x9, x0
10000f300: 8b000101    	add	x1, x8, x0
10000f304: aa0803e0    	mov	x0, x8
10000f308: 17ffffe0    	b	0x10000f288 <_fs.File.Writer.drain+0x3f8>
10000f30c: f85f8296    	ldur	x22, [x20, #-0x8]
10000f310: 8b1702c8    	add	x8, x22, x23
10000f314: f81f8288    	stur	x8, [x20, #-0x8]
10000f318: f9400e89    	ldr	x9, [x20, #0x18]
10000f31c: eb0902e8    	subs	x8, x23, x9
10000f320: 54fffae3    	b.lo	0x10000f27c <_fs.File.Writer.drain+0x3ec>
10000f324: d2800015    	mov	x21, #0x0               ; =0
10000f328: f9000e95    	str	x21, [x20, #0x18]
10000f32c: 7900127f    	strh	wzr, [x19, #0x8]
10000f330: f9000268    	str	x8, [x19]
10000f334: 14000055    	b	0x10000f488 <_fs.File.Writer.drain+0x5f8>
10000f338: 52800248    	mov	w8, #0x12               ; =18
10000f33c: 79004a88    	strh	w8, [x20, #0x24]
10000f340: 1400004e    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f344: 528003a8    	mov	w8, #0x1d               ; =29
10000f348: 79004a88    	strh	w8, [x20, #0x24]
10000f34c: 1400004b    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f350: 528002a8    	mov	w8, #0x15               ; =21
10000f354: 79004a88    	strh	w8, [x20, #0x24]
10000f358: 14000048    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f35c: 528003e8    	mov	w8, #0x1f               ; =31
10000f360: 79004a88    	strh	w8, [x20, #0x24]
10000f364: 14000045    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f368: 52800168    	mov	w8, #0xb                ; =11
10000f36c: 79004a88    	strh	w8, [x20, #0x24]
10000f370: 14000042    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f374: 528001e8    	mov	w8, #0xf                ; =15
10000f378: 79004a88    	strh	w8, [x20, #0x24]
10000f37c: 1400003f    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f380: 52800288    	mov	w8, #0x14               ; =20
10000f384: 79004a88    	strh	w8, [x20, #0x24]
10000f388: 1400003c    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f38c: 52800148    	mov	w8, #0xa                ; =10
10000f390: 79004a88    	strh	w8, [x20, #0x24]
10000f394: 14000039    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f398: 52800348    	mov	w8, #0x1a               ; =26
10000f39c: 79004a88    	strh	w8, [x20, #0x24]
10000f3a0: 14000036    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f3a4: 528002a8    	mov	w8, #0x15               ; =21
10000f3a8: 79004a88    	strh	w8, [x20, #0x24]
10000f3ac: 14000033    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f3b0: 528003c8    	mov	w8, #0x1e               ; =30
10000f3b4: 79004a88    	strh	w8, [x20, #0x24]
10000f3b8: 14000030    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f3bc: 528003e8    	mov	w8, #0x1f               ; =31
10000f3c0: 79004a88    	strh	w8, [x20, #0x24]
10000f3c4: 1400002d    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f3c8: 52800248    	mov	w8, #0x12               ; =18
10000f3cc: 79004a88    	strh	w8, [x20, #0x24]
10000f3d0: 1400002a    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f3d4: 528001e8    	mov	w8, #0xf                ; =15
10000f3d8: 79004a88    	strh	w8, [x20, #0x24]
10000f3dc: 14000027    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f3e0: 528000c8    	mov	w8, #0x6                ; =6
10000f3e4: 79004a88    	strh	w8, [x20, #0x24]
10000f3e8: 14000024    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f3ec: 528003a8    	mov	w8, #0x1d               ; =29
10000f3f0: 79004a88    	strh	w8, [x20, #0x24]
10000f3f4: 14000021    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f3f8: 52800288    	mov	w8, #0x14               ; =20
10000f3fc: 79004a88    	strh	w8, [x20, #0x24]
10000f400: 1400001e    	b	0x10000f478 <_fs.File.Writer.drain+0x5e8>
10000f404: 35000128    	cbnz	w8, 0x10000f428 <_fs.File.Writer.drain+0x598>
10000f408: 79405a88    	ldrh	w8, [x20, #0x2c]
10000f40c: 35000328    	cbnz	w8, 0x10000f470 <_fs.File.Writer.drain+0x5e0>
10000f410: b9402280    	ldr	w0, [x20, #0x20]
10000f414: aa1503e1    	mov	x1, x21
10000f418: 52800002    	mov	w2, #0x0                ; =0
10000f41c: 94000076    	bl	0x10000f5f4 <dyld_stub_binder+0x10000f5f4>
10000f420: b100041f    	cmn	x0, #0x1
10000f424: 540000e0    	b.eq	0x10000f440 <_fs.File.Writer.drain+0x5b0>
10000f428: f81f8295    	stur	x21, [x20, #-0x8]
10000f42c: a9007e7f    	stp	xzr, xzr, [x19]
10000f430: 14000016    	b	0x10000f488 <_fs.File.Writer.drain+0x5f8>
10000f434: 79405a88    	ldrh	w8, [x20, #0x2c]
10000f438: 350001c8    	cbnz	w8, 0x10000f470 <_fs.File.Writer.drain+0x5e0>
10000f43c: 17fffffc    	b	0x10000f42c <_fs.File.Writer.drain+0x59c>
10000f440: 94000067    	bl	0x10000f5dc <dyld_stub_binder+0x10000f5dc>
10000f444: b9400009    	ldr	w9, [x0]
10000f448: 528002e8    	mov	w8, #0x17               ; =23
10000f44c: 7100553f    	cmp	w9, #0x15
10000f450: 540002cd    	b.le	0x10000f4a8 <_fs.File.Writer.drain+0x618>
10000f454: 7100593f    	cmp	w9, #0x16
10000f458: 540000a0    	b.eq	0x10000f46c <_fs.File.Writer.drain+0x5dc>
10000f45c: 7100753f    	cmp	w9, #0x1d
10000f460: 54000060    	b.eq	0x10000f46c <_fs.File.Writer.drain+0x5dc>
10000f464: 7101513f    	cmp	w9, #0x54
10000f468: 54000261    	b.ne	0x10000f4b4 <_fs.File.Writer.drain+0x624>
10000f46c: 79005a88    	strh	w8, [x20, #0x2c]
10000f470: 52800088    	mov	w8, #0x4                ; =4
10000f474: 3900ba88    	strb	w8, [x20, #0x2e]
10000f478: b0000008    	adrp	x8, 0x100010000 <dyld_stub_binder+0x100010000>
10000f47c: 9119c108    	add	x8, x8, #0x670
10000f480: 3dc00100    	ldr	q0, [x8]
10000f484: 3d800260    	str	q0, [x19]
10000f488: a9597bfd    	ldp	x29, x30, [sp, #0x190]
10000f48c: a9584ff4    	ldp	x20, x19, [sp, #0x180]
10000f490: a95757f6    	ldp	x22, x21, [sp, #0x170]
10000f494: a9565ff8    	ldp	x24, x23, [sp, #0x160]
10000f498: a95567fa    	ldp	x26, x25, [sp, #0x150]
10000f49c: a9546ffc    	ldp	x28, x27, [sp, #0x140]
10000f4a0: 910683ff    	add	sp, sp, #0x1a0
10000f4a4: d65f03c0    	ret
10000f4a8: 34fffc09    	cbz	w9, 0x10000f428 <_fs.File.Writer.drain+0x598>
10000f4ac: 7100193f    	cmp	w9, #0x6
10000f4b0: 54fffde0    	b.eq	0x10000f46c <_fs.File.Writer.drain+0x5dc>
10000f4b4: 52800288    	mov	w8, #0x14               ; =20
10000f4b8: 17ffffed    	b	0x10000f46c <_fs.File.Writer.drain+0x5dc>

000000010000f4bc <_sigemptyset__thunk>:
10000f4bc: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f4c0: 9116b210    	add	x16, x16, #0x5ac
10000f4c4: d61f0200    	br	x16

000000010000f4c8 <___error__thunk>:
10000f4c8: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f4cc: 91177210    	add	x16, x16, #0x5dc
10000f4d0: d61f0200    	br	x16

000000010000f4d4 <_sigaction__thunk>:
10000f4d4: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f4d8: 91168210    	add	x16, x16, #0x5a0
10000f4dc: d61f0200    	br	x16

000000010000f4e0 <_memcpy__thunk>:
10000f4e0: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f4e4: 9116e210    	add	x16, x16, #0x5b8
10000f4e8: d61f0200    	br	x16

000000010000f4ec <_os_unfair_lock_unlock__thunk>:
10000f4ec: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f4f0: 9118f210    	add	x16, x16, #0x63c
10000f4f4: d61f0200    	br	x16

000000010000f4f8 <_clock_gettime__thunk>:
10000f4f8: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f4fc: 91165210    	add	x16, x16, #0x594
10000f500: d61f0200    	br	x16

000000010000f504 <_pthread_threadid_np__thunk>:
10000f504: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f508: 91192210    	add	x16, x16, #0x648
10000f50c: d61f0200    	br	x16

000000010000f510 <_os_unfair_lock_lock__thunk>:
10000f510: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f514: 9118c210    	add	x16, x16, #0x630
10000f518: d61f0200    	br	x16

000000010000f51c <_memset__thunk>:
10000f51c: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f520: 91174210    	add	x16, x16, #0x5d0
10000f524: d61f0200    	br	x16

000000010000f528 <_memmove__thunk>:
10000f528: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f52c: 91171210    	add	x16, x16, #0x5c4
10000f530: d61f0200    	br	x16

000000010000f534 <_fstat__thunk>:
10000f534: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f538: 9117a210    	add	x16, x16, #0x5e8
10000f53c: d61f0200    	br	x16

000000010000f540 <_readv__thunk>:
10000f540: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f544: 91183210    	add	x16, x16, #0x60c
10000f548: d61f0200    	br	x16

000000010000f54c <_lseek__thunk>:
10000f54c: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f550: 9117d210    	add	x16, x16, #0x5f4
10000f554: d61f0200    	br	x16

000000010000f558 <_sendfile__thunk>:
10000f558: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f55c: 91186210    	add	x16, x16, #0x618
10000f560: d61f0200    	br	x16

000000010000f564 <_fcopyfile__thunk>:
10000f564: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f568: 91162210    	add	x16, x16, #0x588
10000f56c: d61f0200    	br	x16

000000010000f570 <_writev__thunk>:
10000f570: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f574: 91189210    	add	x16, x16, #0x624
10000f578: d61f0200    	br	x16

000000010000f57c <_pwrite__thunk>:
10000f57c: 90000010    	adrp	x16, 0x10000f000 <_fs.File.Writer.drain+0x170>
10000f580: 91180210    	add	x16, x16, #0x600
10000f584: d61f0200    	br	x16

Disassembly of section __TEXT,__stubs:

000000010000f588 <__stubs>:
10000f588: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f58c: f9400210    	ldr	x16, [x16]
10000f590: d61f0200    	br	x16
10000f594: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f598: f9400610    	ldr	x16, [x16, #0x8]
10000f59c: d61f0200    	br	x16
10000f5a0: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f5a4: f9400a10    	ldr	x16, [x16, #0x10]
10000f5a8: d61f0200    	br	x16
10000f5ac: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f5b0: f9400e10    	ldr	x16, [x16, #0x18]
10000f5b4: d61f0200    	br	x16
10000f5b8: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f5bc: f9401210    	ldr	x16, [x16, #0x20]
10000f5c0: d61f0200    	br	x16
10000f5c4: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f5c8: f9401610    	ldr	x16, [x16, #0x28]
10000f5cc: d61f0200    	br	x16
10000f5d0: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f5d4: f9401a10    	ldr	x16, [x16, #0x30]
10000f5d8: d61f0200    	br	x16
10000f5dc: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f5e0: f9401e10    	ldr	x16, [x16, #0x38]
10000f5e4: d61f0200    	br	x16
10000f5e8: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f5ec: f9402210    	ldr	x16, [x16, #0x40]
10000f5f0: d61f0200    	br	x16
10000f5f4: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f5f8: f9402610    	ldr	x16, [x16, #0x48]
10000f5fc: d61f0200    	br	x16
10000f600: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f604: f9402a10    	ldr	x16, [x16, #0x50]
10000f608: d61f0200    	br	x16
10000f60c: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f610: f9402e10    	ldr	x16, [x16, #0x58]
10000f614: d61f0200    	br	x16
10000f618: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f61c: f9403210    	ldr	x16, [x16, #0x60]
10000f620: d61f0200    	br	x16
10000f624: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f628: f9403610    	ldr	x16, [x16, #0x68]
10000f62c: d61f0200    	br	x16
10000f630: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f634: f9403a10    	ldr	x16, [x16, #0x70]
10000f638: d61f0200    	br	x16
10000f63c: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f640: f9403e10    	ldr	x16, [x16, #0x78]
10000f644: d61f0200    	br	x16
10000f648: b0000070    	adrp	x16, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f64c: f9404210    	ldr	x16, [x16, #0x80]
10000f650: d61f0200    	br	x16

Disassembly of section __TEXT,__stub_helper:

000000010000f654 <__stub_helper>:
10000f654: b0000071    	adrp	x17, 0x10001c000 <dyld_stub_binder+0x10001c000>
10000f658: 91056231    	add	x17, x17, #0x158
10000f65c: a9bf47f0    	stp	x16, x17, [sp, #-0x10]!
10000f660: b0000050    	adrp	x16, 0x100018000 <dyld_stub_binder+0x100018000>
10000f664: f9400210    	ldr	x16, [x16]
10000f668: d61f0200    	br	x16
10000f66c: 18000050    	ldr	w16, 0x10000f674 <__stub_helper+0x20>
10000f670: 17fffff9    	b	0x10000f654 <__stub_helper>
10000f674: 00000000    	udf	#0x0
10000f678: 18000050    	ldr	w16, 0x10000f680 <__stub_helper+0x2c>
10000f67c: 17fffff6    	b	0x10000f654 <__stub_helper>
10000f680: 00000000    	udf	#0x0
10000f684: 18000050    	ldr	w16, 0x10000f68c <__stub_helper+0x38>
10000f688: 17fffff3    	b	0x10000f654 <__stub_helper>
10000f68c: 00000000    	udf	#0x0
10000f690: 18000050    	ldr	w16, 0x10000f698 <__stub_helper+0x44>
10000f694: 17fffff0    	b	0x10000f654 <__stub_helper>
10000f698: 00000000    	udf	#0x0
10000f69c: 18000050    	ldr	w16, 0x10000f6a4 <__stub_helper+0x50>
10000f6a0: 17ffffed    	b	0x10000f654 <__stub_helper>
10000f6a4: 00000000    	udf	#0x0
10000f6a8: 18000050    	ldr	w16, 0x10000f6b0 <__stub_helper+0x5c>
10000f6ac: 17ffffea    	b	0x10000f654 <__stub_helper>
10000f6b0: 00000000    	udf	#0x0
10000f6b4: 18000050    	ldr	w16, 0x10000f6bc <__stub_helper+0x68>
10000f6b8: 17ffffe7    	b	0x10000f654 <__stub_helper>
10000f6bc: 00000000    	udf	#0x0
10000f6c0: 18000050    	ldr	w16, 0x10000f6c8 <__stub_helper+0x74>
10000f6c4: 17ffffe4    	b	0x10000f654 <__stub_helper>
10000f6c8: 00000000    	udf	#0x0
10000f6cc: 18000050    	ldr	w16, 0x10000f6d4 <__stub_helper+0x80>
10000f6d0: 17ffffe1    	b	0x10000f654 <__stub_helper>
10000f6d4: 00000000    	udf	#0x0
10000f6d8: 18000050    	ldr	w16, 0x10000f6e0 <__stub_helper+0x8c>
10000f6dc: 17ffffde    	b	0x10000f654 <__stub_helper>
10000f6e0: 00000000    	udf	#0x0
10000f6e4: 18000050    	ldr	w16, 0x10000f6ec <__stub_helper+0x98>
10000f6e8: 17ffffdb    	b	0x10000f654 <__stub_helper>
10000f6ec: 00000000    	udf	#0x0
10000f6f0: 18000050    	ldr	w16, 0x10000f6f8 <__stub_helper+0xa4>
10000f6f4: 17ffffd8    	b	0x10000f654 <__stub_helper>
10000f6f8: 00000000    	udf	#0x0
10000f6fc: 18000050    	ldr	w16, 0x10000f704 <__stub_helper+0xb0>
10000f700: 17ffffd5    	b	0x10000f654 <__stub_helper>
10000f704: 00000000    	udf	#0x0
10000f708: 18000050    	ldr	w16, 0x10000f710 <__stub_helper+0xbc>
10000f70c: 17ffffd2    	b	0x10000f654 <__stub_helper>
10000f710: 00000000    	udf	#0x0
10000f714: 18000050    	ldr	w16, 0x10000f71c <__stub_helper+0xc8>
10000f718: 17ffffcf    	b	0x10000f654 <__stub_helper>
10000f71c: 00000000    	udf	#0x0
10000f720: 18000050    	ldr	w16, 0x10000f728 <__stub_helper+0xd4>
10000f724: 17ffffcc    	b	0x10000f654 <__stub_helper>
10000f728: 00000000    	udf	#0x0
10000f72c: 18000050    	ldr	w16, 0x10000f734 <__stub_helper+0xe0>
10000f730: 17ffffc9    	b	0x10000f654 <__stub_helper>
10000f734: 00000000    	udf	#0x0
