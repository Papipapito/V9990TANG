//
// megarom_clear.sv
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

`default_nettype none

/***************************************************************
 * V9990TANG: borrado de la ventana de la megaROM al arrancar
 *
 * Sustituye al paso STATE_CLEAR_MEGAROM del BOOTLOADER de tnCart
 * (MEGAROM_CLEAR_SIZE 32768, relleno FFh) en las configuraciones sin
 * bootloader. Con ENABLE_MEGA_SCC_I la megaROM arranca habilitada como
 * Konami SCC-I RAM en 4000h-BFFFh; sin este borrado la BIOS buscaria "AB"
 * en lo que haya en la SDRAM al encender.
 *
 * Funcionamiento: al soltarse RESET_n (el reset de la carcasa: PLL
 * enganchado y SDRAM lista) escribe CLEAR_DATA en CLEAR_SIZE bytes desde
 * CLEAR_ADDR, de cuatro en cuatro (DIN_SIZE_32: una palabra de la SDRAM
 * por acceso, DQM = 0000, como las escrituras de 32 bits del blitter), con
 * el protocolo de RAM_IF del UMA: WE_n = 0 con ADDR/DIN, espera ACK_n = 0,
 * WE_n = 1 y ADDR/DIN a 0 (EXPANSION_RAM hace OR de los clientes), espera
 * ACK_n = 1. Al terminar saca DONE = 1 y deja el puerto en reposo (todo a
 * 0, strobes a 1) hasta el siguiente RESET_n. El /RESET del MSX no lo
 * vuelve a lanzar (el bootloader tampoco lo hacia). CLEAR_ADDR y
 * CLEAR_SIZE tienen que ser multiplos de 4 (comprobado en simulacion).
 *
 * Contrato con la integracion (main.sv):
 *  - Ram va a un puerto propio de EXPANSION_RAM en el canal 0 del UMA
 *    (el de RAM_BOOTLOADER), cuyo Uma.ADDR[0] es 0.
 *  - El reset del sistema (SYS_RESET_n) se retiene hasta DONE, como hacia
 *    BOOT_n: asi la megaROM esta en reset y no usa el canal mientras tanto,
 *    y EXPANSION_SLOT saca WAIT_n = 0 al MSX (su valor de reset); su
 *    entrada WAIT_n (BOOT_WAIT_n) se conecta a DONE.
 *  - No emite refrescos: 8192 accesos, uno por ranura del canal 0 (20
 *    ciclos): 1,52 ms a 108 MHz medidos en el banco (tb/megaram), menos que
 *    los 64 ms de retencion, y al encender la SDRAM no tiene nada que
 *    conservar.
 *  - Necesita que el UMA saque TIMING en el canal 0: con SYNC_CPU_UMA = 0
 *    (wt200b, xtal) corre libre; con SYNC_CPU_UMA = 1 el contador del UMA
 *    se para sin CLK_EN, asi que en la variante sync no acaba sin el reloj
 *    del slot (que alli es tambien el de la FPGA).
 ***************************************************************/
module MEGAROM_CLEAR #(
    parameter [23:0]        CLEAR_ADDR = 24'h00_0000,
    parameter [23:0]        CLEAR_SIZE = 24'd32768,
    parameter [7:0]         CLEAR_DATA = 8'hFF
) (
    input   wire            RESET_n,
    input   wire            CLK,
    RAM_IF.HOST             Ram,
    output  reg             DONE
);

`ifndef SYNTHESIS
    // synthesis translate_off
    initial begin
        if(CLEAR_ADDR[1:0] != 2'd0 || CLEAR_SIZE[1:0] != 2'd0)
            $error("MEGAROM_CLEAR: CLEAR_ADDR (%h) y CLEAR_SIZE (%h) tienen que ser multiplos de 4", CLEAR_ADDR, CLEAR_SIZE);
    end
    // synthesis translate_on
`endif

    localparam [21:0] WORDS  = CLEAR_SIZE[23:2];
    localparam [21:0] LAST_W = CLEAR_ADDR[23:2] + WORDS - 22'd1;    // ultima palabra

    typedef enum logic [1:0] {
        ST_REQ,
        ST_WAIT_ACK,
        ST_WAIT_BUSY,
        ST_DONE
    } state_t;
    state_t state;

    logic [21:0] waddr;     // direccion de palabra (byte >> 2)

    // El puerto se decodifica del estado (sin flops propios): WE_n, ADDR, DIN
    // y DIN_SIZE valen la escritura solo en ST_WAIT_ACK y 0 / reposo en el
    // resto (EXPANSION_RAM hace OR de los clientes). El UMA toma ADDR, DIN y
    // DIN_SIZE en el flanco de bajada de WE_n (det_we), el primer ciclo de
    // ST_WAIT_ACK.
    wire writing = (state == ST_WAIT_ACK);
    assign Ram.ADDR     = writing ? {waddr, 2'b00} : 24'h00_0000;
    assign Ram.DIN      = writing ? {4{CLEAR_DATA}} : 32'h0000_0000;
    assign Ram.DIN_SIZE = writing ? RAM::DIN_SIZE_32 : RAM::DIN_SIZE_8;
    assign Ram.WE_n     = !writing;
    assign Ram.OE_n     = 1'b1;
    assign Ram.RFSH_n   = 1'b1;

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            state       <= (WORDS == 0) ? ST_DONE : ST_REQ;
            DONE        <= (WORDS == 0);
            waddr       <= CLEAR_ADDR[23:2];
        end
        else begin
            case (state)
                // siguiente palabra: WE_n baja en el flanco siguiente
                ST_REQ:
                    state <= ST_WAIT_ACK;

                // el UMA ha visto el flanco (ACK_n = 0): soltar el strobe y el bus
                ST_WAIT_ACK:
                    if(!Ram.ACK_n) state <= ST_WAIT_BUSY;

                // escritura hecha (ACK_n = 1): siguiente palabra o fin
                ST_WAIT_BUSY:
                    if(Ram.ACK_n) begin
                        waddr <= waddr + 22'd1;
                        if(waddr == LAST_W) begin
                            DONE  <= 1;
                            state <= ST_DONE;
                        end
                        else begin
                            state <= ST_REQ;
                        end
                    end

                default: ;
            endcase
        end
    end

endmodule

`default_nettype wire
