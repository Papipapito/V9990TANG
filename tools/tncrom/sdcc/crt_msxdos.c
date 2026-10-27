//
// crt_msxdos.c -- argc/argv, putchar y salida para los .COM de MSX-DOS con SDCC
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito (V9990TANG).
//
// crt_start() la llama crt0_msxdos.s: parte la cola de la orden de MSX-DOS
// (0080h: longitud, 0081h: texto) en argv[1..] por espacios y tabuladores,
// con argv[0] = "TNCROM", comprueba que la pila esta en la pagina 3 (tncrom
// pasa la pagina 2 al cartucho con la pila en uso) y termina con _TERM (62h)
// de MSX-DOS 2 con el valor de main(), o con un arranque en caliente (0000h)
// si _TERM no existe. putchar() saca por CONOUT (02h) y convierte \n en CR LF.
//

#include <stdio.h>
#include <string.h>
#include "types.h"
#include "bdos.h"

#define CRT_MAX_ARGS    16

int main(int argc, char *argv[]);

static char  crt_cmdline[128];
static char *crt_argv[CRT_MAX_ARGS + 1];
static uint16_t crt_sp;
int crt_exit_code;                  // lo que devolvio main() (para depurar)

int putchar(int c)
{
    if(c == '\n') bdos_conout('\r');
    bdos_conout((char)c);
    return c;
}

static void crt_exit(void) __naked
{
__asm
    ld      b, #0x00
    ld      c, #0x62
    call    0x0005
    rst     0x00
__endasm;
}

static void crt_get_sp(void) __naked
{
__asm
    ld      hl, #0
    add     hl, sp
    ld      (_crt_sp), hl
    ret
__endasm;
}

void crt_start(void)
{
    uint8_t len = *(uint8_t *)0x0080;
    int argc = 0;
    char *p;

    if(len > sizeof(crt_cmdline) - 1) len = sizeof(crt_cmdline) - 1;
    memcpy(crt_cmdline, (void *)0x0081, len);
    crt_cmdline[len] = '\0';

    crt_argv[argc++] = "TNCROM";
    p = crt_cmdline;
    while(*p != '\0' && argc < CRT_MAX_ARGS)
    {
        while(*p == ' ' || *p == '\t') *p++ = '\0';
        if(*p == '\0') break;
        crt_argv[argc++] = p;
        while(*p != '\0' && *p != ' ' && *p != '\t') p++;
    }
    crt_argv[argc] = NULL;

    crt_get_sp();
    if(crt_sp < 0xC000)
    {
        printf("TPA too small: stack at %04Xh, below C000h.\n", crt_sp);
        crt_exit_code = 1;
    }
    else
    {
        crt_exit_code = main(argc, crt_argv);
    }
    crt_exit();
}
