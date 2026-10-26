//
// board_rev1_bus.sv
//
// BSD 3-Clause License
// 
// Copyright (c) 2024, Shinobu Hashimoto
// Modificaciones del V9990TANG (escaneo adaptativo, pre-WAIT, timeout y
// guardias de salida): Copyright (c) 2026, Papipapito
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
 * MSX バスの入力
 *
 * V9990TANG (hito 5, ver docs/notas/bus.md):
 *  - Escaneo ADAPTATIVO del multiplexor: al bajar RD_n o WR_n FILTRADOS (antes
 *    de la linea de 9) el escaner visita el grupo 2 (MERQ/IORQ/.../M1 y SLTSL)
 *    cuanto antes, con los 2 ciclos de asentamiento de siempre, y despues
 *    repasa el grupo que el salto dejo a medias y vuelve al grupo 2, de modo
 *    que la direccion que ve el dispositivo cuando le llega el RD_n/WR_n
 *    retrasado se latchea en el grupo 2 con los grupos 0/1 frescos.
 *  - Pre-WAIT: IORQ confirmado en esa muestra rapida y A[7:1] = 60h/61h
 *    (P#0/P#1 del V9990) -> /WAIT de NIVEL hasta que el WAIT_n de la cadena baje
 *    y vuelva a subir; se suelta tambien si no baja PREWAIT_K ciclos despues de
 *    que el evento llegue al dispositivo, o si RD_n/WR_n filtrados vuelven a 1
 *    (3 muestras). Segunda fuente opcional (PREWAIT_MEM_EN) para la MegaRAM.
 *  - Timeout fail-open de 2^WAIT_TMO_BITS ciclos con salida pegajosa.
 *  - Guardias: datos, BUSDIR, DATA_DIR e INT solo con bus_ok && DRIVE_EN;
 *    /WAIT = BOOT_HOLD || (bus_ok && DRIVE_EN && wait). bus_ok = reloj del
 *    slot vivo (>= 64 flancos en 2^18 ciclos) y /RESET del slot suelto.
 *    Ademas, D0-D7 no se conducen con la cola retrasada de Bus.BUSDIR_n de
 *    la lectura anterior (DRIVE_TAIL_GUARD).
 ***************************************************************/
module BOARD_REV1_BUS #(
    parameter               ADAPTIVE_SCAN   = 1,        // 1 = salto al grupo 2 con RD_n/WR_n filtrados (0 = escaner fijo de tnCart)
    parameter               PREWAIT_IO_EN   = 1,        // 1 = pre-WAIT en los puertos PREWAIT_IO_BASE/MASK
    parameter [7:0]         PREWAIT_IO_BASE = 8'h60,    // puertos que piden pre-WAIT (P#0/P#1 del V9990)
    parameter [7:0]         PREWAIT_IO_MASK = 8'hFE,    // bits de A[7:0] que se comparan
    parameter               PREWAIT_K       = 6,        // ciclos de espera al WAIT_n de la cadena tras el evento retrasado (E/S)
    parameter               PREWAIT_MEM_EN  = 0,        // 1 = pre-WAIT tambien en lecturas de memoria del slot (MegaRAM)
    parameter               PREWAIT_MEM_K   = 7,        // idem para lecturas de memoria
    parameter               WAIT_TMO_BITS   = 12,       // timeout fail-open del /WAIT: 2^12 ciclos (37,9 us a 108 MHz)
    parameter               ALIVE_WIN_BITS  = 18,       // ventana de la guardia de bus vivo: 2^18 ciclos (2,43 ms a 108 MHz)
    parameter               ALIVE_MIN_EDGES = 64,       // flancos de CLOCK pedidos por ventana (potencia de 2)
    parameter               ALIVE_CHECK     = 1,        // 1 = bus_ok pide el reloj del slot vivo; 0 = solo /RESET del slot suelto (hardware sin CLOCK en el pin 42)
    parameter               JUMP_HOLD       = 12,       // ciclos sin otro salto tras un salto (>= 11; con <= 6 el g1 puede no revisitarse nunca)
    parameter               DRIVE_TAIL_GUARD = 1,       // 1 = no conducir D0-D7 con la cola de Bus.BUSDIR_n de la lectura anterior
    parameter               ADDR_HOLD       = 1         // 1 = Bus.ADDR quieta mientras Bus.RD_n/WR_n (retrasados) estan a 0
) (
    input wire              RESET_n,
    input wire              CLK,
    input wire              CLK_21M,

    // Guardias (las calcula la integracion en el dominio de 27 MHz)
    input   wire            DRIVE_EN,       // 1 = se puede conducir el slot (guardia de lock)
    input   wire            BOOT_HOLD,      // 1 = retener al MSX con /WAIT (arranque del cartucho), sin timeout
    output  wire            WAIT_TIMEOUT,   // pegajosa: salto el timeout fail-open del /WAIT (para el LED)
    output  wire            BUS_OK,         // reloj del slot vivo y /RESET del slot suelto

    output  wire            CART_BUSDIR_n,
    output  wire            CART_INT_n,
    output  wire            CART_WAIT_n,
    input   wire            CART_SLTSL_n,
    input   wire            CART_RD_n,
    input   wire            CART_WR_n,
    input   wire            CART_CLOCK,
    input   wire    [7:0]   CART_MUX_SIG,
    output  wire    [2:0]   CART_MUX_CS_n,
    inout   wire    [7:0]   CART_DATA_SIG,
    output  wire            CART_DATA_DIR,

    BUS_IF.MSX              Bus
);
    /***************************************************************
     * バッファの切り替え
     ***************************************************************/
    localparam  CS_A8       = 0,    BIT_A8      = 0;
    localparam  CS_A9       = 0,    BIT_A9      = 1;
    localparam  CS_A10      = 0,    BIT_A10     = 2;
    localparam  CS_A11      = 0,    BIT_A11     = 3;
    localparam  CS_A12      = 0,    BIT_A12     = 4;
    localparam  CS_A13      = 0,    BIT_A13     = 5;
    localparam  CS_A14      = 0,    BIT_A14     = 6;
    localparam  CS_A15      = 0,    BIT_A15     = 7;
    localparam  CS_A0       = 1,    BIT_A0      = 0;
    localparam  CS_A1       = 1,    BIT_A1      = 1;
    localparam  CS_A2       = 1,    BIT_A2      = 2;
    localparam  CS_A3       = 1,    BIT_A3      = 3;
    localparam  CS_A4       = 1,    BIT_A4      = 4;
    localparam  CS_A5       = 1,    BIT_A5      = 5;
    localparam  CS_A6       = 1,    BIT_A6      = 6;
    localparam  CS_A7       = 1,    BIT_A7      = 7;
    localparam  CS_MERQ     = 2,    BIT_MERQ    = 0;
    localparam  CS_IORQ     = 2,    BIT_IORQ    = 1;
    localparam  CS_CS1      = 2,    BIT_CS1     = 2;
    localparam  CS_CS2      = 2,    BIT_CS2     = 3;
    localparam  CS_RESET    = 2,    BIT_RESET   = 4;
    localparam  CS_RFSH     = 2,    BIT_RFSH    = 5;
    localparam  CS_CS12     = 2,    BIT_CS12    = 6;
    localparam  CS_M1       = 2,    BIT_M1      = 7;

    // バッファの OE 信号
    reg [2:0]   mux_cs_ff;
    assign      CART_MUX_CS_n = mux_cs_ff;
    localparam  MUX_SEL_0   = 3'b110;
    localparam  MUX_SEL_1   = 3'b101;
    localparam  MUX_SEL_2   = 3'b011;

    /***************************************************************
     * Escaner del multiplexor
     *
     * Cada visita a un grupo dura 3 ciclos: fase 0 (CART_MUX_CS_n acaba de
     * cambiar: asentamiento), fases 1 y 2 (se muestrea al final de cada una;
     * al final de la 2 cambia CART_MUX_CS_n). Sin saltos es exactamente el
     * escaner de 9 estados de tnCart: estado 8 = (g0,f0), 0 = (g0,f1),
     * 1 = (g0,f2), 2 = (g1,f0), 3 = (g1,f1), 4 = (g1,f2), 5 = (g2,f0),
     * 6 = (g2,f1), 7 = (g2,f2); orden g0 -> g1 -> g2.
     *
     * Salto (trig_ok: flanco de bajada de RD_n o WR_n filtrados, visto en el
     * ciclo c y aplicado en el flanco E0 que lo cierra):
     *   g0 (f0, f1, f2) y g1 (f0, f1) -> visita rapida al g2 (f0 en E0..E0+1,
     *     muestras en E0+2 y E0+3), y despues:
     *       desde g0 f0/f1: g0 -> g2 -> g1 -> normal (g0 se habia quedado viejo)
     *       desde g0 f2, g1 f0/f1: g1 -> g2 -> normal
     *   g1 f2, g2 f0, g2 f1: nada (el g2 ya viene en el sitio).
     *   g2 f2: se alarga la f2 un ciclo (sin cambiar el CS: muestras en E0 y
     *     E0+1) y despues g0 -> g2 -> g1 -> normal.
     * En todos los casos hay un latch de ff_addr en el g2 entre E0+1 y E0+8
     * (E0+8 es el flanco en que el RD_n/WR_n retrasado, filtro + 9, llega a
     * Bus), y en ese latch la primera muestra de la ultima pareja de los
     * grupos 0 y 1 es como pronto de E0-6 (3-4 ciclos antes del /RD del pin).
     * Revisita en el peor caso (ciclos entre parejas): con un salto aislado
     * g0 14, g1 17, g2 9; con saltos encadenados (uno cada 13 ciclos como
     * mucho, por JUMP_HOLD) g0 17, g1 17, g2 9. Con JUMP_HOLD <= 6 la
     * revisita del g1 no esta acotada. Tabla y modelo: docs/notas/bus.md y
     * fpga/tb/bus/scan_model.py.
     ***************************************************************/
    localparam [1:0] G0 = 2'd0, G1 = 2'd1, G2 = 2'd2;
    localparam [3:0] JHOLD4  = JUMP_HOLD;
    localparam [3:0] PWK4    = PREWAIT_K;
    localparam [3:0] PWKMEM4 = PREWAIT_MEM_K;

    // synthesis translate_off
    initial begin
        if(JUMP_HOLD < 7 || JUMP_HOLD > 15)
            $error("BOARD_REV1_BUS: JUMP_HOLD = %0d fuera de 7..15 (con <= 6 el grupo 1 puede no revisitarse nunca; el contador es de 4 bits)", JUMP_HOLD);
        if(PREWAIT_K < 1 || PREWAIT_K > 14 || PREWAIT_MEM_K < 1 || PREWAIT_MEM_K > 14)
            $error("BOARD_REV1_BUS: PREWAIT_K/PREWAIT_MEM_K = %0d/%0d fuera de 1..14 (contador de 4 bits)", PREWAIT_K, PREWAIT_MEM_K);
    end
    // synthesis translate_on

    logic [1:0] grp;            // grupo que se esta visitando
    logic [1:0] ph;             // fase de la visita (0, 1, 2)
    logic       ret_pend;       // al acabar el g2 actual, ir a ret_grp
    logic [1:0] ret_grp;
    logic       force2;         // al acabar el g0 actual, ir al g2 (y luego al g1)
    logic       nx2;            // al acabar el g2 actual, ir al g1 en vez de al g0
    logic [3:0] jhold;          // ciclos sin aceptar otro salto

    logic       RD_n;
    logic       WR_n;
    logic       rd_q;
    logic       wr_q;
    wire        trig    = (rd_q && !RD_n) || (wr_q && !WR_n);   // flanco de bajada de RD_n/WR_n filtrados
    wire        trig_ok = (ADAPTIVE_SCAN != 0) && trig && (jhold == 4'd0);

    logic [1:0] grp_n, ph_n, ret_grp_n;
    logic       ret_pend_n, force2_n, nx2_n;
    always_comb begin
        grp_n      = grp;
        ph_n       = ph + 2'd1;
        ret_pend_n = ret_pend;
        ret_grp_n  = ret_grp;
        force2_n   = force2;
        nx2_n      = nx2;

        // fin de visita: siguiente grupo
        if(ph == 2'd2) begin
            ph_n = 2'd0;
            case (grp)
                G0: begin
                    if(force2) begin
                        grp_n    = G2;
                        nx2_n    = 1'b1;
                        force2_n = 1'b0;
                    end
                    else begin
                        grp_n    = G1;
                    end
                end
                G1: begin
                    grp_n = G2;
                end
                default: begin
                    if(ret_pend) begin
                        grp_n      = ret_grp;
                        force2_n   = (ret_grp == G0);
                        ret_pend_n = 1'b0;
                    end
                    else begin
                        grp_n      = nx2 ? G1 : G0;
                    end
                    nx2_n = 1'b0;
                end
            endcase
        end

        // salto al grupo 2
        if(trig_ok) begin
            if(grp == G0 || (grp == G1 && ph != 2'd2)) begin
                grp_n      = G2;
                ph_n       = 2'd0;
                ret_pend_n = 1'b1;
                ret_grp_n  = (grp == G0 && ph != 2'd2) ? G0 : G1;
                force2_n   = 1'b0;
                nx2_n      = 1'b0;
            end
            else if(grp == G2 && ph == 2'd2) begin
                grp_n      = G2;            // se alarga la fase 2 un ciclo
                ph_n       = 2'd2;
                ret_pend_n = 1'b1;
                ret_grp_n  = G0;
                force2_n   = 1'b0;
                nx2_n      = 1'b0;
            end
        end
    end

    function automatic [2:0] mux_sel(input [1:0] g);
        mux_sel = (g == G0) ? MUX_SEL_0 : (g == G1) ? MUX_SEL_1 : MUX_SEL_2;
    endfunction

    always_ff @(posedge CLK or negedge RESET_n)
    begin
        if(!RESET_n)
        begin
            grp       <= G0;            // = estado 0 del escaner original
            ph        <= 2'd1;
            ret_pend  <= 1'b0;
            ret_grp   <= G0;
            force2    <= 1'b0;
            nx2       <= 1'b0;
            mux_cs_ff <= MUX_SEL_0;
        end else begin
            grp       <= grp_n;
            ph        <= ph_n;
            ret_pend  <= ret_pend_n;
            ret_grp   <= ret_grp_n;
            force2    <= force2_n;
            nx2       <= nx2_n;
            mux_cs_ff <= mux_sel(grp_n);    // el CS solo cambia cuando cambia el grupo
        end
    end

    always_ff @(posedge CLK or negedge RESET_n)
    begin
        if(!RESET_n)            jhold <= 4'd0;
        else if(trig_ok)        jhold <= JHOLD4;
        else if(jhold != 4'd0)  jhold <= jhold - 4'd1;
    end

    wire [2:0]  mux_active;
    assign      mux_active[0] = (grp == G0) && (ph != 2'd0);
    assign      mux_active[1] = (grp == G1) && (ph != 2'd0);
    assign      mux_active[2] = (grp == G2) && (ph != 2'd0);

    /***************************************************************
     * アドレスバスの取得
     ***************************************************************/
    logic [15:0] ADDR;
    PIN_FILTER u_a0    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A0 ]), .IN(CART_MUX_SIG[BIT_A0 ]), .OUT(ADDR[ 0]));
    PIN_FILTER u_a1    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A1 ]), .IN(CART_MUX_SIG[BIT_A1 ]), .OUT(ADDR[ 1]));
    PIN_FILTER u_a2    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A2 ]), .IN(CART_MUX_SIG[BIT_A2 ]), .OUT(ADDR[ 2]));
    PIN_FILTER u_a3    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A3 ]), .IN(CART_MUX_SIG[BIT_A3 ]), .OUT(ADDR[ 3]));
    PIN_FILTER u_a4    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A4 ]), .IN(CART_MUX_SIG[BIT_A4 ]), .OUT(ADDR[ 4]));
    PIN_FILTER u_a5    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A5 ]), .IN(CART_MUX_SIG[BIT_A5 ]), .OUT(ADDR[ 5]));
    PIN_FILTER u_a6    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A6 ]), .IN(CART_MUX_SIG[BIT_A6 ]), .OUT(ADDR[ 6]));
    PIN_FILTER u_a7    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A7 ]), .IN(CART_MUX_SIG[BIT_A7 ]), .OUT(ADDR[ 7]));
    PIN_FILTER u_a8    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A8 ]), .IN(CART_MUX_SIG[BIT_A8 ]), .OUT(ADDR[ 8]));
    PIN_FILTER u_a9    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A9 ]), .IN(CART_MUX_SIG[BIT_A9 ]), .OUT(ADDR[ 9]));
    PIN_FILTER u_a10   (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A10]), .IN(CART_MUX_SIG[BIT_A10]), .OUT(ADDR[10]));
    PIN_FILTER u_a11   (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A11]), .IN(CART_MUX_SIG[BIT_A11]), .OUT(ADDR[11]));
    PIN_FILTER u_a12   (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A12]), .IN(CART_MUX_SIG[BIT_A12]), .OUT(ADDR[12]));
    PIN_FILTER u_a13   (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A13]), .IN(CART_MUX_SIG[BIT_A13]), .OUT(ADDR[13]));
    PIN_FILTER u_a14   (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A14]), .IN(CART_MUX_SIG[BIT_A14]), .OUT(ADDR[14]));
    PIN_FILTER u_a15   (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_A15]), .IN(CART_MUX_SIG[BIT_A15]), .OUT(ADDR[15]));

    /***************************************************************
     * その他の信号の取得
     ***************************************************************/
    logic SLTSL_n;
    logic MERQ_n;
    logic IORQ_n;
    logic CS1_n;
    logic CS2_n;
    logic CS12_n;
    logic M1_n;
    logic CLOCK;
    logic RFSH_n;
    logic SLOT_RESET_n;
    PIN_FILTER u_nsltsl (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_MERQ ]), .IN(CART_SLTSL_n           ), .OUT(SLTSL_n    ));
    PIN_FILTER u_nrd    (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1                ), .IN(CART_RD_n              ), .OUT(RD_n       ));
    PIN_FILTER u_nwr    (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1                ), .IN(CART_WR_n              ), .OUT(WR_n       ));
    PIN_FILTER u_clock  (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1                ), .IN(CART_CLOCK             ), .OUT(CLOCK      ));
    PIN_FILTER u_nmerq  (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_MERQ ]), .IN(CART_MUX_SIG[BIT_MERQ ]), .OUT(MERQ_n     ));
    PIN_FILTER u_niorq  (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_IORQ ]), .IN(CART_MUX_SIG[BIT_IORQ ]), .OUT(IORQ_n     ));
    PIN_FILTER u_ncs1   (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_CS1  ]), .IN(CART_MUX_SIG[BIT_CS1  ]), .OUT(CS1_n      ));
    PIN_FILTER u_ncs2   (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_CS2  ]), .IN(CART_MUX_SIG[BIT_CS2  ]), .OUT(CS2_n      ));
    PIN_FILTER u_nreset (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_RESET]), .IN(CART_MUX_SIG[BIT_RESET]), .OUT(SLOT_RESET_n));
    PIN_FILTER u_nrfsh  (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_RFSH ]), .IN(CART_MUX_SIG[BIT_RFSH ]), .OUT(RFSH_n ));
    PIN_FILTER u_ncs12  (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_CS12 ]), .IN(CART_MUX_SIG[BIT_CS12 ]), .OUT(CS12_n ));
    PIN_FILTER u_nm1    (.CLK(CLK), .RESET_n(RESET_n), .ENA(mux_active[CS_M1   ]), .IN(CART_MUX_SIG[BIT_M1   ]), .OUT(M1_n   ));
    assign Bus.RESET_n = SLOT_RESET_n;

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            rd_q <= 1;
            wr_q <= 1;
        end
        else begin
            rd_q <= RD_n;
            wr_q <= WR_n;
        end
    end

    /***************************************************************
     * Muestras frescas del grupo 2: cuantas muestras del g2 se han tomado
     * desde el ultimo flanco de bajada de RD_n/WR_n filtrados (la del propio
     * flanco E0 cuenta). Con 2, IORQ/MERQ/SLTSL y ff_addr son de este ciclo.
     * Un flanco dentro de la retencion de JUMP_HOLD no vuelve a empezar la
     * cuenta: dos flancos de bajada de RD_n/WR_n de ciclos distintos del Z80
     * estan a >= 2 T (escritura de memoria seguida de lectura: 20 ciclos a
     * 10,74 MHz, mas que JUMP_HOLD + 1), asi que ese es un rebote del
     * mismo ciclo y las muestras ya tomadas siguen valiendo (si no, el rebote
     * retrasaria el pre-WAIT hasta la siguiente visita al g2).
     * En el ciclo del flanco (trig visto, cuenta aun sin poner a 0) la cuenta
     * es la del ciclo ANTERIOR del Z80: fresh vale 0 ahi. Si no, el /RD de un
     * M1 que sigue a un IN/OUT a 60h/61h decidia con el IORQ_n filtrado y el
     * ff_addr de ese IN/OUT (el filtro de IORQ ve subir /IORQ hasta ~10
     * ciclos tarde) y metia un pre-WAIT en el M1 que solo soltaba K
     * (fpga/tb/bus/tb_m1spur.sv; docs/notas/bus.md, seccion 2).
     ***************************************************************/
    logic [1:0] fresh_cnt;
    wire        fresh_rst = trig && (jhold == 4'd0);    // flanco de un ciclo nuevo del Z80
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                    fresh_cnt <= 2'd0;
        else if(fresh_rst)                              fresh_cnt <= mux_active[2] ? 2'd1 : 2'd0;
        else if(mux_active[2] && fresh_cnt != 2'd2)     fresh_cnt <= fresh_cnt + 2'd1;
    end
    wire fresh = (fresh_cnt == 2'd2) && !fresh_rst;

    /***************************************************************
     * Guardia de bus vivo (como el MoonTANG): flancos del CLOCK filtrado en
     * una ventana de 2^ALIVE_WIN_BITS ciclos; con >= ALIVE_MIN_EDGES el reloj
     * del slot esta presente. bus_ok ademas exige /RESET del slot suelto.
     * Con ALIVE_CHECK = 0 solo cuenta el /RESET (para un slot o un expansor que
     * no lleve CLOCK al cartucho; se pierde la proteccion sin MSX encendido).
     ***************************************************************/
    localparam ALIVE_CNT_BITS = $clog2(ALIVE_MIN_EDGES) + 1;
    logic [ALIVE_WIN_BITS-1:0]  ck_win;
    logic [ALIVE_CNT_BITS-1:0]  ck_edges;
    logic                       ck_alive;
    logic                       clock_q;
    logic                       bus_ok;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            ck_win   <= 0;
            ck_edges <= 0;
            ck_alive <= 0;
            clock_q  <= 0;
            bus_ok   <= 0;
        end
        else begin
            clock_q <= CLOCK;
            ck_win  <= ck_win + 1'd1;
            if(ck_win == 0) begin
                ck_alive <= ck_edges[ALIVE_CNT_BITS-1];
                ck_edges <= 0;
            end
            else if((CLOCK != clock_q) && !ck_edges[ALIVE_CNT_BITS-1]) begin
                ck_edges <= ck_edges + 1'd1;
            end
            bus_ok <= ((ALIVE_CHECK == 0) || ck_alive) && SLOT_RESET_n;
        end
    end
    assign BUS_OK = bus_ok;

    // DRIVE_EN y BOOT_HOLD llegan de otro dominio: sincronizados solo para el
    // contador del timeout (en los pines van directos, combinacionales)
    logic [1:0] drive_en_s;
    logic [1:0] boot_hold_s;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            drive_en_s  <= 2'b00;
            boot_hold_s <= 2'b00;
        end
        else begin
            drive_en_s  <= { drive_en_s[0], DRIVE_EN };
            boot_hold_s <= { boot_hold_s[0], BOOT_HOLD };
        end
    end

    /***************************************************************
     * Guardia de cola del bus de datos: Bus.BUSDIR_n llega por el camino
     * retrasado (filtro + 9 + slot + registro del cartucho: ~14 ciclos
     * despues del /RD del pin) y sigue a 0 ese tiempo tras el fin de la
     * lectura. Si el siguiente /RD del Z80 baja antes (el M1 que sigue a un
     * IN cae T - 5 ns despues con cifras de Z80A: 9,5 ciclos a 10,74 MHz,
     * 14,5 a 7,16), la placa conduciria el dato viejo contra la memoria del
     * MSX. drv_arm solo deja conducir en una lectura que empezo con el
     * dispositivo en reposo: se arma con Bus.BUSDIR_n = 1 y se desarma con
     * /RD del pin en reposo 3 muestras CRUDAS seguidas (rd_tail; un rebote de
     * 2 no lo desarma). Con las muestras crudas, sin el PIN_FILTER, la guardia
     * corta 2-3 ciclos (19-29 ns) despues de subir /RD, en vez de 4-5 con
     * RD_n filtrado: el /RD de un M1 que baje 30-45 ns despues del fin del IN
     * (Zilog no da minimos; el banco con +M1RD=30 a 10,74 MHz) ya no se
     * encuentra la placa conduciendo. rd_tail corta tambien en el mismo ciclo
     * (combinacional), no solo al desarmar en el flanco siguiente.
     ***************************************************************/
    logic       rd_raw_q;       // CART_RD_n muestreado, sin filtro
    logic [1:0] rd_raw_hi;      // muestras crudas seguidas con /RD en reposo, antes de la ultima
    logic       drv_arm;
    wire        rd_tail = rd_raw_q && (rd_raw_hi >= 2'd2);  // 3 muestras crudas seguidas con /RD en reposo
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            rd_raw_q  <= 1'b1;
            rd_raw_hi <= 2'd0;
            drv_arm   <= 1'b0;
        end
        else begin
            rd_raw_q <= CART_RD_n;
            if(!rd_raw_q)               rd_raw_hi <= 2'd0;
            else if(rd_raw_hi != 2'd3)  rd_raw_hi <= rd_raw_hi + 2'd1;
            if(Bus.BUSDIR_n)            drv_arm <= 1'b1;
            else if(rd_tail)            drv_arm <= 1'b0;
        end
    end
    wire drv_ok  = (DRIVE_TAIL_GUARD == 0) || (drv_arm && !rd_tail);

    /***************************************************************
     * データバス
     ***************************************************************/
    logic [7:0] DIN;
    wire drive = bus_ok && DRIVE_EN && drv_ok && !CART_RD_n && !Bus.BUSDIR_n;  // guardias de salida (combinacional)
    wire dir = !drive;
    assign  CART_DATA_DIR = dir;
    assign  CART_BUSDIR_n = dir;
    assign  CART_DATA_SIG = dir ? 8'bZZZZ_ZZZZ : Bus.DOUT;
    PIN_FILTER u_d0_in (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1), .IN(CART_DATA_SIG[0]), .OUT(DIN[0]));
    PIN_FILTER u_d1_in (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1), .IN(CART_DATA_SIG[1]), .OUT(DIN[1]));
    PIN_FILTER u_d2_in (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1), .IN(CART_DATA_SIG[2]), .OUT(DIN[2]));
    PIN_FILTER u_d3_in (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1), .IN(CART_DATA_SIG[3]), .OUT(DIN[3]));
    PIN_FILTER u_d4_in (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1), .IN(CART_DATA_SIG[4]), .OUT(DIN[4]));
    PIN_FILTER u_d5_in (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1), .IN(CART_DATA_SIG[5]), .OUT(DIN[5]));
    PIN_FILTER u_d6_in (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1), .IN(CART_DATA_SIG[6]), .OUT(DIN[6]));
    PIN_FILTER u_d7_in (.CLK(CLK), .RESET_n(RESET_n), .ENA(1'b1), .IN(CART_DATA_SIG[7]), .OUT(DIN[7]));

    /***************************************************************
     * RD_n, WR_n, CLOCK の遅延
     ***************************************************************/
    logic [9-1:0] delay_rd_n;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)    delay_rd_n <= -1;
        else            delay_rd_n <= { RD_n, delay_rd_n[$bits(delay_rd_n)-1:1] };
    end

    logic [9-1:0] delay_wr_n;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)    delay_wr_n <= -1;
        else            delay_wr_n <= { WR_n, delay_wr_n[$bits(delay_wr_n)-1:1] };
    end

    logic [9-1:0] delay_clk;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)    delay_clk <= -1;
        else            delay_clk <= { CLOCK, delay_clk[$bits(delay_clk)-1:1] };
    end

    logic delay_clk2/* synthesis syn_maxfan=15 */;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)    delay_clk2 <= 0;
        else            delay_clk2 <= delay_clk[1];
    end

    /***************************************************************
     * アドレスバスの更新タイミングを MERQ や IORQ 等と合わせる
     ***************************************************************/
    // V9990TANG: con ADDR_HOLD, ff_addr no se actualiza mientras el RD_n/WR_n
    // retrasado (el que ve Bus) esta a 0. IORQ_n filtrado sube hasta ~10 ciclos
    // despues del pin (una vuelta y una muestra) y el RD_n/WR_n retrasado 11:
    // sin la retencion, la direccion del ciclo siguiente (que el Z80 pone
    // desde T1, T/2 despues del fin del ciclo de E/S: 93 ns a 5,37 MHz) puede
    // latchearse con IORQ_n aun a 0 y el RD_n/WR_n aun a 0, y si cae en
    // 60h-6Fh el cartucho ve un segundo ciclo de E/S que no existe (el banco
    // lo ve a 5,37 MHz). Como la direccion en la llegada del evento ya es la
    // buena, retenerla hasta el fin del ciclo retrasado no cambia nada mas.
    wire addr_hold = (ADDR_HOLD != 0) && (!delay_rd_n[0] || !delay_wr_n[0]);
    reg [15:0] ff_addr;
    always_ff @(posedge CLK) if(mux_active[2] && !addr_hold) ff_addr <= ADDR;

    /***************************************************************
     * Pre-WAIT
     *
     * Dispara cuando, con las dos muestras del g2 frescas (de despues del
     * flanco de RD_n/WR_n filtrados), IORQ esta confirmado y A[7:1] es 60h/61h
     * con RD_n o WR_n filtrados a 0 o dentro de la retencion del salto (o, con
     * PREWAIT_MEM_EN, SLTSL y MERQ con RD_n). Mantiene /WAIT de nivel hasta
     * que el WAIT_n de la cadena (Bus.WAIT_n)
     * baje y vuelva a subir. Liberacion sin esperar al timeout:
     *  - el WAIT_n de la cadena no ha bajado PREWAIT_K (PREWAIT_MEM_K) ciclos
     *    con el RD_n/WR_n retrasado ya en Bus (el evento llego al dispositivo y
     *    este no pidio espera: puerto de otro, core en reset...);
     *  - RD_n y WR_n filtrados en reposo 3 muestras seguidas (fin del ciclo o
     *    falso disparo; un rebote de 2 muestras no lo suelta).
     * Un disparo por ciclo: se rearma con esas mismas 3 muestras en reposo.
     * La A7-A0 que ve la decision es la del ff_addr latcheado en la 2a
     * muestra fresca, antes de revisitar el g1: con un salto desde g1 f0/f1
     * sale de la pareja del g1 de E0-8 (5-6 ciclos antes del /RD del pin),
     * que con Z80A vale hasta 7,16 MHz; a 10,74 puede ser la del ciclo
     * anterior (docs/notas/bus.md, seccion 1).
     ***************************************************************/
    logic [1:0] rw_idle_cnt;
    wire        rw_idle_now = RD_n && WR_n;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                    rw_idle_cnt <= 2'd0;
        else if(!rw_idle_now)           rw_idle_cnt <= 2'd0;
        else if(rw_idle_cnt != 2'd3)    rw_idle_cnt <= rw_idle_cnt + 2'd1;
    end
    wire rw_idle3 = rw_idle_now && (rw_idle_cnt >= 2'd2);    // 3a muestra en reposo seguida

    // Strobe activo para el disparo: RD_n/WR_n filtrados a 0, o dentro de la
    // retencion de JUMP_HOLD tras el salto (un rebote de 2 muestras justo
    // despues del flanco deja RD_n filtrado a 1 dos ciclos y, sin esto,
    // retrasaria el disparo 2 ciclos: 87 ns en vez de 70 en el pin, fuera del
    // presupuesto a 5,37 MHz). Los strobes que piden pre-WAIT duran mas que el
    // salto mas la retencion (el mas corto, el /RD de un M1 o el /RD o /WR de
    // E/S, es 1,5 T + 5 ns: 15,6 ciclos a 10,74 MHz, frente a 2-3 + 12), asi
    // que la retencion no da por activo un strobe que ya ha acabado; trig_rd
    // recuerda si el salto vino de RD_n (la fuente de memoria es solo de
    // lecturas: el /WR de memoria, T + 5 ns, si puede acabar antes).
    logic trig_rd;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)        trig_rd <= 1'b0;
        else if(trig_ok)    trig_rd <= rd_q && !RD_n;
    end
    wire in_hold  = (jhold != 4'd0);
    wire stb_any  = !RD_n || !WR_n || in_hold;
    wire stb_rd   = !RD_n || (in_hold && trig_rd);

    wire io_match = (((ff_addr[7:0] ^ PREWAIT_IO_BASE) & PREWAIT_IO_MASK) == 8'h00);
    wire io_hit   = (PREWAIT_IO_EN != 0) && fresh && !IORQ_n && io_match && stb_any;
    wire mem_hit  = (PREWAIT_MEM_EN != 0) && fresh && !SLTSL_n && !MERQ_n && IORQ_n && stb_rd;
    wire dly_act  = !delay_rd_n[0] || !delay_wr_n[0];           // el evento ya esta en Bus

    logic       pw_armed;
    logic       pw_hold;
    logic       pw_mem;
    logic       pw_seen;
    logic [3:0] pw_k;
    wire  [3:0] pw_kmax = pw_mem ? PWKMEM4 : PWK4;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            pw_armed <= 0;
            pw_hold  <= 0;
            pw_mem   <= 0;
            pw_seen  <= 0;
            pw_k     <= 0;
        end
        else begin
            if(rw_idle3) pw_armed <= 1;
            if(!pw_hold) begin
                if(pw_armed && (io_hit || mem_hit)) begin
                    pw_hold  <= 1;
                    pw_armed <= 0;
                    pw_mem   <= !io_hit;
                    pw_seen  <= 0;
                    pw_k     <= 0;
                end
            end
            else begin
                if(!Bus.WAIT_n) pw_seen <= 1;
                if(dly_act && !pw_seen && pw_k != 4'hF) pw_k <= pw_k + 4'd1;
                if((pw_seen && Bus.WAIT_n) ||                       // la cadena bajo y subio
                   (!pw_seen && Bus.WAIT_n && pw_k >= pw_kmax) ||   // la cadena no lo pidio a tiempo
                   rw_idle3) begin                                  // RD_n/WR_n filtrados en reposo
                    pw_hold <= 0;
                    pw_seen <= 0;
                end
            end
        end
    end

    /***************************************************************
     * /WAIT al slot con timeout fail-open
     *
     * El contador corre mientras la espera logica es la que sujeta el pin:
     * con BOOT_HOLD a 1 no cuenta (la retencion de arranque no tiene
     * timeout y no debe encender WAIT_TIMEOUT), y con bus_ok o DRIVE_EN a 0
     * tampoco (el pin no sale). Se pone a 0 en cuanto la espera logica cae,
     * asi que el siguiente acceso vuelve a tener /WAIT.
     ***************************************************************/
    wire wait_req = pw_hold || !Bus.WAIT_n;
    wire wait_drv = wait_req && bus_ok && drive_en_s[1] && !boot_hold_s[1];
    logic [WAIT_TMO_BITS:0] wtmo;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                    wtmo <= 0;
        else if(!wait_drv)              wtmo <= 0;
        else if(!wtmo[WAIT_TMO_BITS])   wtmo <= wtmo + 1'd1;
    end
    wire wtmo_hit = wtmo[WAIT_TMO_BITS];

    logic wait_timeout_ff;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)        wait_timeout_ff <= 0;
        else if(wtmo_hit)   wait_timeout_ff <= 1;
    end
    assign WAIT_TIMEOUT = wait_timeout_ff;

    /***************************************************************
     * その他の信号の出力 (con las guardias; el pin a 1 activa el NPN)
     ***************************************************************/
    wire int_act = bus_ok && DRIVE_EN && !Bus.INT_n;
    if(CONFIG_BOARD::BOARD_ID == BOARD_ID::WonderTANG_101c) begin
        assign  CART_INT_n = !int_act;
    end
    else begin
        assign  CART_INT_n = int_act;
    end
    assign  CART_WAIT_n = BOOT_HOLD || (bus_ok && DRIVE_EN && wait_req && !wtmo_hit);

    /***************************************************************
     * 信号を Bus I/F に出力
     ***************************************************************/
    assign Bus.ADDR = ff_addr;
    assign Bus.DIN = DIN;
    assign Bus.SLTSL_n = SLTSL_n;
    assign Bus.MERQ_n = MERQ_n;
    assign Bus.IORQ_n = IORQ_n;
    assign Bus.CS1_n = CS1_n;
    assign Bus.CS2_n = CS2_n;
    assign Bus.CS12_n = CS12_n;
    assign Bus.M1_n = M1_n;
    assign Bus.WR_n = delay_wr_n[0];
    assign Bus.RD_n = delay_rd_n[0];
    assign Bus.RFSH_n = RFSH_n;

    /***************************************************************
     * CLK_EN
     ***************************************************************/
    wire curr_clk = delay_clk[0];
    logic prev_clk;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)    prev_clk <= 0;
        else            prev_clk <= curr_clk;
    end

    assign Bus.CLK = curr_clk;
    assign Bus.CLK_EN = curr_clk && !prev_clk;

    /***************************************************************
     * CLK_EN(21.6MHzドメイン)
     ***************************************************************/
    assign Bus.CLK_21M = CLK_21M;   // 21.6MHz

    // 3.58MHz エッジ
    logic curr_clk_d21m;
    if(CONFIG::ENABLE_SCC == CONFIG::ENABLE_IKASCC) begin
        always_ff @(posedge CLK_21M) curr_clk_d21m <= delay_clk2;
    end
    else begin
        always_ff @(posedge CLK_21M) curr_clk_d21m <= delay_clk[0];
    end
    logic prev_clk_d21m;
    always_ff @(posedge CLK_21M or negedge RESET_n) begin
        if(!RESET_n)    prev_clk_d21m <= 0;
        else            prev_clk_d21m <= curr_clk_d21m;
    end

    // 3.58MHz CLK_EN
    assign Bus.CLK_EN_21M = curr_clk_d21m && !prev_clk_d21m;
endmodule

/***************************************************************
 * input filter
 ***************************************************************/
module PIN_FILTER #(
    parameter   DEFAULT = 1    
) (
    input   wire        CLK,
    input   wire        RESET_n,
    input   wire        ENA,
    input   wire        IN,
    output  reg         OUT
) /* synthesis syn_preserve=1 */;
    logic prev;

    always_ff @(posedge CLK or negedge RESET_n)
    begin
        if(!RESET_n) begin
            OUT <= DEFAULT;
            prev <= DEFAULT;
        end
        else if(ENA) begin
            OUT <= (prev == IN) ? prev : OUT;
            prev <= IN;
        end
    end
endmodule

`default_nettype wire
