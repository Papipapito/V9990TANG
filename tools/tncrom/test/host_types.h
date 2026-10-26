//
// host_types.h -- tipos de lib/types.h para compilar tncrom en el host
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito (V9990TANG).
//
// run.sh lo mete con -include delante de cada fuente de tncrom: define la
// guarda de lib/types.h (que asi no se lee) y da los mismos anchos que SDCC
// en el Z80 (uint32_t de 32 bits; en el host "unsigned long" mide 64 y
// choca con <stdint.h>).
//

#ifndef _INCLUDE_TYPES_H_
#define _INCLUDE_TYPES_H_

#include <stddef.h>
#include <stdint.h>

typedef void *VOID_PTR_t;

#endif
