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
//    PLL_OK. DS226-2.7E (31/07/2026), tabla 3-20, GW2AR-18 C8/I7: TLOCKMAX
//    1 ms y RSTMINPULSE 10 ns (el reset del rPLL dura 1,21 ms en el POR y 38
//    us en cada reintento). UG286-2.0.2E, nota a la tabla 5-2: LOCK puede dar
//    glitches mientras engancha y hay que vigilarlo al menos 2 ms (de ahi los
//    2,43 ms de LOCK_STABLE). Sin enganche estable en LOCK_TIMEOUT (19,4 ms,
//    19 veces el TLOCKMAX), o si se pierde (LOCK bajo LOSS_CYCLES ciclos
//    seguidos, o en sync el reloj del slot ausente o fuera de frecuencia),
//    quita PLL_OK, resetea el rPLL PLL_RST_CYCLES ciclos y lo reintenta. No
//    hay lock pegajoso: PLL_OK sigue al PLL en todo momento. "En frecuencia"
//    son dos medidas: una ventana de 151,7 us (+-1,5 %) y un control rapido
//    del periodo de 4,47 us (salta seguro fuera de -4,2/+4,9 %, con tres
//    medidas seguidas), para un rPLL que siga al reloj del slot sin soltar
//    LOCK por encima de la Fmax de CLK_BASE.
//  - Guardia de lock:
//    DRIVE_EN_27 = PLL_OK, LOCK alto en este momento (lock_s, sin filtro) y
//      el sistema listo (SYS_READY, sincronizado con 2 FF). Si LOCK baja, los
//      pines se sueltan en 2-3 ciclos (unos 110 ns), aunque PLL_OK aguante
//      los 152 us del filtro de perdida antes de mandar el diseno a reset.
//      Contrapartida: un glitch de LOCK con el PLL enganchado corta un /WAIT
//      en curso (sin reset: DRIVE_EN_27 vuelve con LOCK).
//    BOOT_HOLD_27 = sistema aun no listo durante un arranque, con un tope de
//      HOLD_CYCLES (50 ms) por arranque. Arranque en frio: desde que acaba la
//      configuracion de la FPGA (xtal: el cristal esta siempre) o desde que
//      hay reloj del slot (sync: el MSX encendido) hasta que el sistema queda
//      listo por primera vez, con el PLL enganchado o no; asi el MSX no corre
//      mientras el cartucho arranca (POR, enganche y borrado de la megaROM),
//      como con el bootloader de tnCart, cuyo reset retenia /WAIT desde la
//      configuracion. En sync, si el reloj del slot desaparece (MSX apagado
//      con la Tang alimentada por USB), el siguiente arranque vuelve a ser en
//      frio. En xtal, si el reloj del slot vuelve tras faltar (MSX
//      apagado y encendido con la Tang alimentada por USB), el tope se
//      rearma en ese momento: BOOT_HOLD retiene al MSX hasta que BUS_OK da
//      por vivo el reloj del slot (hasta 2,43 ms). Tras perder el enganche
//      con el sistema ya listo: desde que vuelve PLL_OK. El tope se rearma
//      cuando el sistema queda listo; en sync, cuando desaparece el reloj
//      del slot; en xtal, cuando vuelve.
//    Sin enganche, DRIVE_EN_27 = 0 siempre y BOOT_HOLD_27 = 0 salvo en el
//    arranque en frio, como mucho 50 ms: el cartucho queda mudo y el MSX
//    arranca. Las dos son flops; cuando el sistema queda listo, DRIVE_EN_27
//    sube un ciclo antes de que baje BOOT_HOLD_27, asi que
//    /WAIT = BOOT_HOLD || (DRIVE_EN && wait) no tiene ningun hueco en el
//    relevo.
//
// Sincronizadores (dos FF en CLK_27M; en el .sdc los cruces los corta el
// set_clock_groups entre el grupo de 27 MHz y el de CLK_BASE):
//   lock_ff   <- PLL_LOCK (salida asincrona del rPLL)
//   sclk_ff   <- SLOT_CLK (pin CART_CLOCK, 3,58 MHz)
//   ready_ff  <- SYS_READY (flop de CLK_BASE: SYS_RESET_n && BUS_OK)
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
    parameter int   LOCK_TIMEOUT    = 524_288,      // 19,4 ms sin enganche estable: reintento (DS226-2.7E: TLOCKMAX 1 ms)
    parameter int   LOSS_CYCLES     = 4_096,        // 152 us de LOCK bajo seguido: enganche perdido (los pines se sueltan antes)
    parameter int   HOLD_CYCLES     = 1_350_000,    // 50,0 ms: tope de BOOT_HOLD_27 por arranque
    parameter int   SLOT_GAP        = 32,           // 1,19 us sin flanco de subida del reloj del slot: ausente
    parameter int   SLOT_WINDOW     = 4_096,        // ventana de medida de la frecuencia del slot (151,7 us)
    parameter int   SLOT_MIN        = 535,          // flancos por ventana: 543,0 a 3,579545 MHz; -1,5 %
    parameter int   SLOT_MAX        = 551,          //                                             +1,5 %
    parameter int   FAST_EDGES      = 16,           // control rapido del periodo: periodos del slot por medida (4,47 us)
    parameter int   FAST_MIN        = 117,          // ciclos de 27 MHz por medida (120,7 a 3,579545 MHz): pasa seguro
    parameter int   FAST_MAX        = 124           //   de -1,9 a +2,3 %, salta seguro por debajo de -4,2 % o encima de +4,9 %
) (
    input  wire     CLK_27M,

    input  wire     PLL_LOCK,       // LOCK del rPLL base, crudo (asincrono)
    input  wire     SLOT_CLK,       // pin CART_CLOCK, crudo (asincrono)
    input  wire     SYS_READY,      // sistema listo: flop de CLK_BASE (SYS_RESET_n de MAIN && BUS_OK)
    input  wire     WAIT_TIMEOUT,   // error pegajoso del bus: timeout de /WAIT (CLK_BASE)

    output wire     PLL_RESET,      // al RESET del rPLL base
    output wire     PLL_OK,         // rPLL base enganchado (filtrado)
    output wire     DRIVE_EN_27,    // el cartucho puede sacar /WAIT, datos e /INT
    output wire     BOOT_HOLD_27,   // /WAIT de arranque (sistema aun no listo, con tope)

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
    // arranca en "ausente": el reloj del slot cuenta como presente desde su
    // primer flanco de subida, no desde la configuracion
    reg [GAP_W-1:0] gap_cnt = GAP_TOP;
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
    // Control rapido del periodo, para lo que la ventana tarda en ver: un rPLL
    // que sigue al reloj del slot sin perder LOCK hasta una frecuencia por
    // encima de su Fmax (en sync, CLK_BASE = slot x30). Cuenta los ciclos de
    // 27 MHz entre un flanco de subida del reloj del slot y el FAST_EDGES-esimo
    // siguiente (16 periodos, 4,47 us; 120,7 ciclos a 3,579545 MHz). La
    // cuantificacion (+-1) y la metaestabilidad de los dos extremos (+-1)
    // dejan pasar seguro de -1,9 a +2,3 % (la ventana de +-1,5 % cabe dentro)
    // y saltan seguro por debajo de -4,2 % o por encima de +4,9 %. Hacen falta
    // tres medidas seguidas fuera de banda para quitar fast_ok: un flanco
    // espurio aislado (ruido en el CLOCK del slot) estropea como mucho dos, la
    // que lo contiene y, si la cierra el, la siguiente, que empieza a mitad de
    // un periodo (15 + x y 16 - x periodos: cerca de +1,5 % las dos pueden
    // quedar por debajo de FAST_MIN; con dos medidas, el banco resetea el
    // diseno con un solo espurio). Un cambio de frecuencia fuera de banda
    // quita SLOT_OK en tres o cuatro medidas, menos de 20 us, en lugar de los
    // 152-303 us de la ventana; en S_LOCKED eso baja PLL_OK y DRIVE_EN un
    // ciclo despues. En xtal SLOT_OK no se usa y la sintesis lo quita.
    localparam int FC_W = $clog2(FAST_MAX + 2);
    localparam logic [FC_W-1:0] FC_TOP  = FC_W'(FAST_MAX + 1);
    localparam logic [FC_W-1:0] FC_MIN  = FC_W'(FAST_MIN);
    localparam logic [FC_W-1:0] FC_MAX  = FC_W'(FAST_MAX);
    localparam int FE_W = $clog2(FAST_EDGES);
    localparam logic [FE_W-1:0] FE_LAST = FE_W'(FAST_EDGES - 1);
    reg [FE_W-1:0] fe_cnt   = '0;   // flancos de subida en la medida
    reg [FC_W-1:0] fc_cnt   = '0;   // ciclos desde el primer flanco (satura en FC_TOP)
    reg            fast_ok  = 1'b0;
    reg [1:0]      fast_bad = 2'd0; // medidas seguidas fuera de banda (hasta 2)
    wire [FC_W-1:0] fc_next = (fc_cnt == FC_TOP) ? FC_TOP : fc_cnt + 1'd1;
    wire            fc_band = (fc_next >= FC_MIN) && (fc_next <= FC_MAX);
    always_ff @(posedge CLK_27M) begin
        if(!SLOT_PRESENT) begin
            // sin reloj del slot: al volver, la primera medida empieza en su
            // primer flanco y hace falta una dentro de banda
            fast_ok  <= 1'b0;
            fast_bad <= 2'd0;
            fe_cnt   <= '0;
            fc_cnt   <= '0;
        end
        else if(sclk_rise && fe_cnt == FE_LAST) begin
            // fin de la medida: fc_next = ciclos entre el primer flanco y este,
            // que abre la siguiente
            if(fc_band) begin
                fast_ok  <= 1'b1;
                fast_bad <= 2'd0;
            end
            else if(fast_bad == 2'd2) fast_ok  <= 1'b0;     // la tercera seguida
            else                      fast_bad <= fast_bad + 2'd1;
            fe_cnt <= '0;
            fc_cnt <= '0;
        end
        else begin
            if(sclk_rise) fe_cnt <= fe_cnt + 1'd1;
            fc_cnt <= fc_next;
        end
    end
    assign SLOT_OK = SLOT_PRESENT && freq_ok && fast_ok;

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

    // arranque en frio: 1 al configurar la FPGA (GSR) hasta que el sistema
    // queda listo; en sync vuelve a 1 sin reloj del slot (MSX apagado)
    reg  cold    = 1'b1;
    wire msx_on  = (SYNC != 0) ? SLOT_PRESENT : 1'b1;
    wire msx_off = (SYNC != 0) && !SLOT_PRESENT;
    wire booting = !ready_d && (pll_ok || (cold && msx_on));
    // xtal: el reloj del slot vuelve tras faltar (MSX encendido otra vez con
    // la Tang alimentada por USB). En xtal el rPLL no depende de el, asi que
    // PLL_OK sigue a 1, el sistema espera a BUS_OK y el tope (agotado con el
    // MSX apagado) se rearma aqui para retener al MSX esa ventana
    reg  slot_present_d = 1'b0;
    always_ff @(posedge CLK_27M) slot_present_d <= SLOT_PRESENT;
    wire slot_back = (SYNC == 0) && SLOT_PRESENT && !slot_present_d;

    reg drive_en     = 1'b0;
    reg boot_hold    = 1'b0;
    reg hold_expired = 1'b0;
    assign DRIVE_EN_27  = drive_en;
    assign BOOT_HOLD_27 = boot_hold;
    assign HOLD_EXPIRED = hold_expired;

    always_ff @(posedge CLK_27M) begin
        // lock_s sin filtro: con LOCK bajo, el cartucho suelta el slot ya
        drive_en <= pll_ok && lock_s && ready_s;

        if(pll_ok && ready_s) begin
            // sistema listo: el tope se rearma para el proximo arranque
            cold         <= 1'b0;
            hold_cnt     <= '0;
            hold_expired <= 1'b0;
        end
        else if(msx_off) begin
            // sync sin reloj del slot: el proximo arranque es en frio, con
            // su tope entero
            cold         <= 1'b1;
            hold_cnt     <= '0;
            hold_expired <= 1'b0;
        end
        else if(slot_back) begin
            // xtal, vuelve el reloj del slot: tope entero desde ahora
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
