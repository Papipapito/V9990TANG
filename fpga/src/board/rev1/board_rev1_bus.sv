//
// board_rev1_bus.sv
//
// BSD 3-Clause License
// 
// Copyright (c) 2024, Shinobu Hashimoto
// Modificaciones del V9990TANG (escaneo adaptativo): Copyright (c) 2026, Papipapito
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
 *  - Bus.ADDR quieta mientras el RD_n/WR_n retrasado esta a 0 (ADDR_HOLD).
 ***************************************************************/
module BOARD_REV1_BUS #(
    parameter               ADAPTIVE_SCAN   = 1,        // 1 = salto al grupo 2 con RD_n/WR_n filtrados (0 = escaner fijo de tnCart)
    parameter               JUMP_HOLD       = 12,       // ciclos sin otro salto tras un salto (>= 11; con <= 6 el g1 puede no revisitarse nunca)
    parameter               ADDR_HOLD       = 1         // 1 = Bus.ADDR quieta mientras Bus.RD_n/WR_n (retrasados) estan a 0
) (
    input wire              RESET_n,
    input wire              CLK,
    input wire              CLK_21M,

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

    // synthesis translate_off
    initial begin
        if(JUMP_HOLD < 7 || JUMP_HOLD > 15)
            $error("BOARD_REV1_BUS: JUMP_HOLD = %0d fuera de 7..15 (con <= 6 el grupo 1 puede no revisitarse nunca; el contador es de 4 bits)", JUMP_HOLD);
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
     * データバス
     ***************************************************************/
    logic [7:0] DIN;
    wire dir = !(!CART_RD_n && !Bus.BUSDIR_n);
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
     * その他の信号の出力
     ***************************************************************/
    if(CONFIG_BOARD::BOARD_ID == BOARD_ID::WonderTANG_101c) begin
        assign  CART_INT_n = Bus.INT_n;
    end
    else begin
        assign  CART_INT_n = !Bus.INT_n;
    end
    assign  CART_WAIT_n = !Bus.WAIT_n;

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
