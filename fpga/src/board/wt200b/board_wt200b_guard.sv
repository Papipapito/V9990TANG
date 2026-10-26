//
// board_wt200b_guard.sv -- V9990TANG
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
// POR, gestor del rPLL base y guardia de lock, todo en el dominio de CLK_27M
// (el cristal de la Tang: es el unico reloj que existe siempre, con PLL o sin
// el, con MSX o sin el).
//
//  - POR: al cargar la FPGA, el rPLL base queda en reset POR_CYCLES ciclos.
//  - Gestor del rPLL: suelta el reset (en sync, solo con el reloj del slot
//    presente y en frecuencia), espera LOCK seguido LOCK_STABLE ciclos y da
//    PLL_OK (2,43 ms: UG286-2.0.2E, nota a la tabla 5-2, avisa de que LOCK
//    puede dar glitches mientras engancha y pide vigilarlo al menos 2 ms; el
//    tiempo maximo de enganche no esta en las versiones del DS226 que se han
//    podido leer: LOCK_TIMEOUT lo da por perdido a los 19,4 ms); sin
//    enganche en LOCK_TIMEOUT, o si se pierde (LOCK bajo LOSS_CYCLES ciclos
//    seguidos, o en sync el reloj del slot ausente o fuera de frecuencia),
//    quita PLL_OK, resetea el rPLL PLL_RST_CYCLES ciclos y lo reintenta. No
//    hay lock pegajoso: PLL_OK sigue al PLL en todo momento.
//  - Guardia de lock: DRIVE_EN_27 = PLL_OK y el sistema listo (SYS_READY,
//    sincronizado con 2 FF); BOOT_HOLD_27 = PLL_OK y el sistema aun no listo,
//    con un tope de HOLD_CYCLES (50 ms) que solo se rearma cuando el sistema
//    llega a estar listo. Sin enganche, las dos a 0: el cartucho no saca nada
//    al slot y el MSX arranca. Las dos son flops; cuando el sistema queda
//    listo, DRIVE_EN_27 sube un ciclo antes de que baje BOOT_HOLD_27, asi que
//    /WAIT = BOOT_HOLD || (DRIVE_EN && wait) no tiene ningun hueco en el
//    relevo.
//
// Sincronizadores (dos FF en CLK_27M; en el .sdc los cruces los corta el
// set_clock_groups entre el grupo de 27 MHz y el de CLK_BASE):
//   lock_ff   <- PLL_LOCK (salida asincrona del rPLL)
//   sclk_ff   <- SLOT_CLK (pin CART_CLOCK, 3,58 MHz)
//   ready_ff  <- SYS_READY (SYS_RESET_n, CLK_BASE)
//   wto_ff    <- WAIT_TIMEOUT (CLK_BASE)
// Hacia CLK_BASE sale PLL_OK, que SYSTEM_RESET sincroniza (afirmacion
// asincrona, suelta sincrona). PLL_RESET va directo al RESET del rPLL.
//

`default_nettype none

module BOARD_WT200B_GUARD #(
    parameter int   SYNC            = 0,            // CONFIG_BOARD::SYNC_CPU_CLK (1 = rPLL base desde el reloj del slot)
    parameter int   POR_CYCLES      = 32_768,       // 1,21 ms de reset del rPLL tras cargar la FPGA
    parameter int   PLL_RST_CYCLES  = 1_024,        // 38 us de reset del rPLL en cada reintento
    parameter int   LOCK_STABLE     = 65_536,       // 2,43 ms de LOCK seguido para dar el PLL por enganchado (UG286: >= 2 ms)
    parameter int   LOCK_TIMEOUT    = 524_288,      // 19,4 ms sin enganche estable: reintento
    parameter int   LOSS_CYCLES     = 4_096,        // 152 us de LOCK bajo seguido: enganche perdido
    parameter int   HOLD_CYCLES     = 1_350_000,    // 50,0 ms: tope de BOOT_HOLD_27
    parameter int   SLOT_GAP        = 32,           // 1,19 us sin flanco de subida del reloj del slot: ausente
    parameter int   SLOT_WINDOW     = 4_096,        // ventana de medida de la frecuencia del slot (151,7 us)
    parameter int   SLOT_MIN        = 535,          // flancos por ventana: 543,0 a 3,579545 MHz; -1,5 %
    parameter int   SLOT_MAX        = 551           //                                             +1,5 %
) (
    input  wire     CLK_27M,

    input  wire     PLL_LOCK,       // LOCK del rPLL base, crudo (asincrono)
    input  wire     SLOT_CLK,       // pin CART_CLOCK, crudo (asincrono)
    input  wire     SYS_READY,      // sistema listo: SYS_RESET_n de MAIN (CLK_BASE)
    input  wire     WAIT_TIMEOUT,   // error pegajoso del bus: timeout de /WAIT (CLK_BASE)

    output wire     PLL_RESET,      // al RESET del rPLL base
    output wire     PLL_OK,         // rPLL base enganchado (filtrado)
    output wire     DRIVE_EN_27,    // el cartucho puede sacar /WAIT, datos e /INT
    output wire     BOOT_HOLD_27,   // /WAIT de arranque (PLL enganchado, sistema aun no listo)

    // estado, para el LED y el banco
    output wire     POR_DONE,
    output wire     SLOT_OK,        // reloj del slot presente y en frecuencia
    output wire     SLOT_PRESENT,   // reloj del slot presente
    output wire     SYS_READY_27,   // SYS_READY sincronizado
    output wire     HOLD_EXPIRED,   // BOOT_HOLD_27 agoto su tope sin que el sistema quedara listo
    output wire     RELOCKED,       // pegajoso: se perdio el enganche y se recupero
    output wire     WAIT_TIMEOUT_27 // pegajoso: WAIT_TIMEOUT visto
);
    /***************************************************************
     * Sincronizadores
     ***************************************************************/
    reg [1:0] lock_ff  = 2'b00;
    reg [2:0] sclk_ff  = 3'b000;
    reg [2:0] ready_ff = 3'b000;
    reg [1:0] wto_ff   = 2'b00;
    always_ff @(posedge CLK_27M) begin
        lock_ff  <= { lock_ff[0],     PLL_LOCK     };
        sclk_ff  <= { sclk_ff[1:0],   SLOT_CLK     };
        ready_ff <= { ready_ff[1:0],  SYS_READY    };
        wto_ff   <= { wto_ff[0],      WAIT_TIMEOUT };
    end
    wire lock_s  = lock_ff[1];
    wire ready_s = ready_ff[1];     // sistema listo
    wire ready_d = ready_ff[2];     // un ciclo despues: BOOT_HOLD baja detras de DRIVE_EN
    assign SYS_READY_27 = ready_s;

    reg wto_seen = 1'b0;
    always_ff @(posedge CLK_27M) begin
        if(wto_ff[1]) wto_seen <= 1'b1;
    end
    assign WAIT_TIMEOUT_27 = wto_seen;

    /***************************************************************
     * Reloj del slot: presencia y frecuencia
     ***************************************************************/
    wire sclk_rise = sclk_ff[1] && !sclk_ff[2];

    localparam int GAP_W = $clog2(SLOT_GAP + 1);
    localparam logic [GAP_W-1:0] GAP_TOP = GAP_W'(SLOT_GAP);
    reg [GAP_W-1:0] gap_cnt = '0;
    always_ff @(posedge CLK_27M) begin
        if(sclk_rise)               gap_cnt <= '0;
        else if(gap_cnt != GAP_TOP) gap_cnt <= gap_cnt + 1'd1;
    end
    assign SLOT_PRESENT = (gap_cnt != GAP_TOP);

    localparam int EDGE_W = $clog2(SLOT_WINDOW / 2 + 2);
    localparam int WIN_W  = $clog2(SLOT_WINDOW);
    localparam logic [WIN_W-1:0]  WIN_LAST = WIN_W'(SLOT_WINDOW - 1);
    localparam logic [EDGE_W-1:0] EDGE_MIN = EDGE_W'(SLOT_MIN);
    localparam logic [EDGE_W-1:0] EDGE_MAX = EDGE_W'(SLOT_MAX);
    reg [WIN_W-1:0]  win_cnt = '0;
    reg [EDGE_W-1:0] edge_cnt = '0;
    reg              freq_ok = 1'b0;
    wire [EDGE_W-1:0] edge_next = edge_cnt + {{(EDGE_W-1){1'b0}}, sclk_rise};
    always_ff @(posedge CLK_27M) begin
        if(win_cnt == WIN_LAST) begin
            win_cnt  <= '0;
            edge_cnt <= '0;
            freq_ok  <= (edge_next >= EDGE_MIN) && (edge_next <= EDGE_MAX);
        end
        else begin
            win_cnt  <= win_cnt + 1'd1;
            edge_cnt <= edge_next;
        end
    end
    assign SLOT_OK = SLOT_PRESENT && freq_ok;

    // en xtal el rPLL base no depende del reloj del slot
    wire clk_in_ok = (SYNC != 0) ? SLOT_OK : 1'b1;

    /***************************************************************
     * POR y gestor del rPLL base
     ***************************************************************/
    localparam int T_MAX = (POR_CYCLES > LOCK_TIMEOUT) ? POR_CYCLES : LOCK_TIMEOUT;
    localparam int L_MAX = (LOCK_STABLE > LOSS_CYCLES) ? LOCK_STABLE : LOSS_CYCLES;

    typedef enum logic [2:0] {
        S_POR,          // reset del rPLL tras cargar la FPGA
        S_WAIT_CLK,     // reset del rPLL hasta que su reloj de entrada sea valido
        S_LOCKING,      // rPLL suelto: esperando LOCK estable
        S_LOCKED,       // PLL_OK
        S_RETRY         // reset del rPLL antes de reintentar
    } state_t;
    state_t state = S_POR;

    localparam int T_W = $clog2(T_MAX + 1);
    localparam int L_W = $clog2(L_MAX + 1);
    localparam logic [T_W-1:0] POR_LAST     = T_W'(POR_CYCLES - 1);
    localparam logic [T_W-1:0] TIMEOUT_LAST = T_W'(LOCK_TIMEOUT - 1);
    localparam logic [T_W-1:0] RST_LAST     = T_W'(PLL_RST_CYCLES - 1);
    localparam logic [L_W-1:0] STABLE_LAST  = L_W'(LOCK_STABLE - 1);
    localparam logic [L_W-1:0] LOSS_LAST    = L_W'(LOSS_CYCLES - 1);
    reg [T_W-1:0] t_cnt = '0;      // tiempo en el estado
    reg [L_W-1:0] l_cnt = '0;      // LOCK seguido (S_LOCKING) o sin LOCK seguido (S_LOCKED)
    reg                       lost  = 1'b0;    // hubo una perdida de enganche

    // valores de arranque: los carga el GSR al configurar la FPGA
    reg pll_reset = 1'b1;
    reg pll_ok    = 1'b0;
    reg por_done  = 1'b0;
    reg relocked  = 1'b0;
    assign PLL_RESET = pll_reset;
    assign PLL_OK    = pll_ok;
    assign POR_DONE  = por_done;
    assign RELOCKED  = relocked;

    always_ff @(posedge CLK_27M) begin
        case(state)
            S_POR: begin
                pll_reset <= 1'b1;
                pll_ok    <= 1'b0;
                l_cnt     <= '0;
                if(t_cnt == POR_LAST) begin
                    t_cnt    <= '0;
                    por_done <= 1'b1;
                    state    <= S_WAIT_CLK;
                end
                else begin
                    t_cnt <= t_cnt + 1'd1;
                end
            end

            S_WAIT_CLK: begin
                pll_reset <= 1'b1;
                pll_ok    <= 1'b0;
                t_cnt     <= '0;
                l_cnt     <= '0;
                if(clk_in_ok) state <= S_LOCKING;
            end

            S_LOCKING: begin
                pll_reset <= 1'b0;
                if(!clk_in_ok) begin
                    t_cnt <= '0;
                    state <= S_RETRY;
                end
                else if(lock_s && l_cnt == STABLE_LAST) begin
                    l_cnt  <= '0;
                    pll_ok <= 1'b1;
                    if(lost) relocked <= 1'b1;
                    state  <= S_LOCKED;
                end
                else if(t_cnt == TIMEOUT_LAST) begin
                    t_cnt <= '0;
                    state <= S_RETRY;
                end
                else begin
                    t_cnt <= t_cnt + 1'd1;
                    l_cnt <= lock_s ? l_cnt + 1'd1 : '0;
                end
            end

            S_LOCKED: begin
                pll_reset <= 1'b0;
                if(!clk_in_ok || (!lock_s && l_cnt == LOSS_LAST)) begin
                    pll_ok <= 1'b0;
                    lost   <= 1'b1;
                    t_cnt  <= '0;
                    l_cnt  <= '0;
                    state  <= S_RETRY;
                end
                else begin
                    l_cnt <= lock_s ? '0 : l_cnt + 1'd1;
                end
            end

            S_RETRY: begin
                pll_reset <= 1'b1;
                pll_ok    <= 1'b0;
                l_cnt     <= '0;
                if(t_cnt == RST_LAST) begin
                    t_cnt <= '0;
                    state <= S_WAIT_CLK;
                end
                else begin
                    t_cnt <= t_cnt + 1'd1;
                end
            end

            default: begin
                pll_reset <= 1'b1;
                pll_ok    <= 1'b0;
                t_cnt     <= '0;
                l_cnt     <= '0;
                state     <= S_POR;
            end
        endcase
    end

    /***************************************************************
     * Guardia de lock
     ***************************************************************/
    localparam int H_W = $clog2(HOLD_CYCLES + 1);
    localparam logic [H_W-1:0] HOLD_LAST = H_W'(HOLD_CYCLES - 1);
    reg [H_W-1:0] hold_cnt = '0;
    wire booting = pll_ok && !ready_d;

    reg drive_en     = 1'b0;
    reg boot_hold    = 1'b0;
    reg hold_expired = 1'b0;
    assign DRIVE_EN_27  = drive_en;
    assign BOOT_HOLD_27 = boot_hold;
    assign HOLD_EXPIRED = hold_expired;

    always_ff @(posedge CLK_27M) begin
        drive_en <= pll_ok && ready_s;

        if(pll_ok && ready_s) begin
            // sistema listo: el tope se rearma para el proximo arranque
            hold_cnt     <= '0;
            hold_expired <= 1'b0;
        end
        else if(booting && !hold_expired) begin
            if(hold_cnt == HOLD_LAST) hold_expired <= 1'b1;
            hold_cnt <= hold_cnt + 1'd1;
        end

        boot_hold <= booting && !hold_expired && !(hold_cnt == HOLD_LAST);
    end

endmodule

`default_nettype wire
