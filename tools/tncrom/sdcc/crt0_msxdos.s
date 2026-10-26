;
; crt0_msxdos.s -- arranque de un .COM de MSX-DOS para SDCC (sdasz80)
;
; BSD 3-Clause License. Copyright (c) 2026, Papipapito (V9990TANG).
;
; El .COM se carga en 0100h. Deja la pila donde la pone MSX-DOS (cima del
; TPA), borra _DATA y _BSS (SDCC no lo hace y C lo exige), copia los valores
; iniciales (_INITIALIZER -> _INITIALIZED) y llama a crt_start(), que
; prepara argc/argv, llama a main() y termina (crt_msxdos.c). Enlazar con
; --no-std-crt0 --code-loc 0x0110 --data-loc 0 y este .rel el primero.
;
	.module	crt0_msxdos
	.globl	_crt_start

	.area	_HEADER (ABS)
	.org	0x0100
	jp	init

	; orden de las areas (el enlazador las coloca en el orden en que aparecen)
	.area	_HOME
	.area	_CODE
	.area	_INITIALIZER
	.area	_GSINIT
	.area	_GSFINAL
	.area	_DATA
	.area	_INITIALIZED
	.area	_BSEG
	.area	_BSS
	.area	_HEAP

	.area	_CODE
init:
	call	gsinit
	call	_crt_start
	rst	0x00			; crt_start no vuelve

	.area	_GSINIT
gsinit::
	ld	hl, #s__DATA
	ld	bc, #l__DATA
	call	clear
	ld	hl, #s__BSS
	ld	bc, #l__BSS
	call	clear
	ld	bc, #l__INITIALIZER
	ld	a, b
	or	a, c
	jr	z, gsinit_next
	ld	de, #s__INITIALIZED
	ld	hl, #s__INITIALIZER
	ldir
gsinit_next:

	.area	_GSFINAL
	ret

	.area	_CODE
	; borra BC bytes desde HL
clear:
	ld	a, b
	or	a, c
	ret	z
	ld	(hl), #0
	dec	bc
	ld	a, b
	or	a, c
	ret	z
	ld	e, l
	ld	d, h
	inc	de
	ldir
	ret
