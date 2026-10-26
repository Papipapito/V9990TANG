//
// reboot.c
//
// BSD 3-Clause License
// 
// Copyright (c) 2024, Shinobu Hashimoto
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
// 
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
// 
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#include <string.h>
#include "types.h"
#include "rom_tools.h"

// V9990TANG (port a SDCC): mismas instrucciones en sintaxis de sdasz80
static void reboot_2(void)
{
__asm
    xor     a, a
    out     (0xF5), a

    ld      iy, (0xFCC1 - 1)
    ld      ix, #0x0000
    call    0x001C
__endasm;
}

static void reboot_2p(void)
{
__asm
    ld      iy, (0xFCC1 - 1)
    ld      ix, #0x017A
    call    0x001C

    or      a, #0x80

    ld      iy, (0xFCC1 - 1)
    ld      ix, #0x017D
    call    0x001C

    ld      iy, (0xFCC1 - 1)
    ld      ix, #0x0000
    call    0x001C
__endasm;
}

void reboot(void)
{
    if(rdslt(*(uint8_t*)0xFCC1, 0x002D) >= 2)
    {
        reboot_2p();
    }
    else
    {
        reboot_2();
    }
}
