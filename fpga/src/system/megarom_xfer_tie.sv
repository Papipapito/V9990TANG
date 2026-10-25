//
// megarom_xfer_tie.sv -- V9990TANG
//
// BSD 3-Clause License
//
// Copyright (c) 2026, Papipapito
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

//
// Lado del dispositivo de un XFER_IF sin bootloader. La megaROM de tnCart
// (megarom_configure.sv) pide por XFER_IF las transferencias flash <-> SDRAM
// que servia el BOOTLOADER; sin el, ninguna orden esta nunca ocupada y las
// lecturas dan FFh, asi que las ordenes de flash de tncrom acaban al instante
// sin hacer nada.
//
// Va en un modulo aparte (y no como asignaciones a Xfer.* dentro del generate
// de main.sv) para que la configuracion v9990, que no compila bootloader.sv
// (donde viven XFER y XFER_IF), elabore tambien en Verilator: Verilator
// tolera instancias de modulos que no existen en una rama de generate muerta,
// pero no referencias con punto a una interfaz que no existe. Solo lo
// compilan las builds de MegaRAM (build_common.tcl).
//

`default_nettype none

module MEGAROM_XFER_TIE (
    XFER_IF.DEVICE          Xfer
);
    assign Xfer.Busy  = 1'b0;
    assign Xfer.RData = 8'hFF;
endmodule

`default_nettype wire
