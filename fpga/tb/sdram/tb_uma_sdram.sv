// ============================================================================
// tb_uma_sdram.sv -- banco del UMA + sdram.sv de V9990TANG (hito 4) con el
// modelo de SDRAM del MoonTANG (sdram_model_bl.v) y el reloj de la SDRAM a 180
// grados (CLK_PS = ~CLK), como en la placa (CLK_MEM_P del rPLL base).
//
// Simulador: Verilator 5.020 (--binary --timing) en WSL; lo lanza run.sh.
// Icarus 12 no compila las interfaces con modport de tnCart (puertos
// RAM_IF.HOST: "syntax error ... Errors in port declarations").
//
// Clientes:
//   canal 1  patron del V9990 (copia del protocolo de T9990_RAM: la operacion
//            sale en EXEC = TIMING + 1, espera ACK_n = 0 y despues ACK_n = 1, y
//            si llega otro EXEC antes la ranura se pierde): todas las ranuras
//            ocupadas, un RAM_RF por linea de 1368 ciclos de 21,6 MHz (342
//            ranuras), o STANDBY sin ninguna operacion (t9990_timing.sv:
//            MEM.STATE = RAM_XX con DSPM = STANDBY).
//   canal 0  1 = Z80 sintetico por flanco, como la megaROM (megarom_controller.sv:
//            OE_n/WE_n/RFSH_n por nivel, ADDR = 0 en reposo, DIN_SIZE_8), con M1
//            de 5 T (con su espera), lectura y escritura de 3 T, a 3,58 o 7,16
//            MHz, y /RFSH tras cada M1 si +Z80RFSH=1. Las senales pasan por dos
//            flops y una linea de FE_DELAY ciclos (filtro y mux del bus).
//            2 = cliente al 100 %: R/W de 8/16/32 bits encadenados por ACK_n
//            (como el bootloader), uno en cada ranura del canal 0.
//            3 = R/W y RFSH pedidos en el mismo ciclo, o RFSH solo, con
//            handshake por ACK_n.
//            0 = nada.
//
// Plusargs: +MHZ=108000|107386 (kHz)  +CH0=0|1|2|3  +Z80KHZ=3580|7160
//           +Z80RFSH=0|1  +V99=0|1  +US=<us simulados>  +SEED=<n>
//           +PHASE0=1 (control: reloj de la SDRAM sin desfase)
//           +NEG=<comprobacion> (control negativo: se espera que falle esa
//           comprobacion, p. ej. gap, init, window, slot, rfsh o z80; el
//           resto se informa sin contar)
// Defines:  HITO1 = UMA y sdram.sv de main (hito 1), sin los puertos nuevos.
// Parametro: INT_REFRESH (-GINT_REFRESH=0 para el control sin temporizador).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_uma_sdram;
    parameter INT_REFRESH = 1;

    // ------------------------------------------------------------------
    // plusargs
    // ------------------------------------------------------------------
    int mhz_khz  = 108000;
    int ch0_mode = 0;
    int z80_khz  = 3580;
    int z80_rfsh = 1;
    int v99_mode = 0;
    int sim_us   = 2000;
    int seed     = 1;
    int phase0   = 0;
    string neg   = "";

    localparam int FE_DELAY = 8;                // retardo del filtro + mux del bus (ciclos)
    localparam real REF_MAX_NS = 15600.0;       // 4096 AUTO REFRESH / 64 ms = 15,625 us

    real t_clk, half, tz;
    logic clk = 1'b0;

    initial begin
        void'($value$plusargs("MHZ=%d", mhz_khz));
        void'($value$plusargs("CH0=%d", ch0_mode));
        void'($value$plusargs("Z80KHZ=%d", z80_khz));
        void'($value$plusargs("Z80RFSH=%d", z80_rfsh));
        void'($value$plusargs("V99=%d", v99_mode));
        void'($value$plusargs("US=%d", sim_us));
        void'($value$plusargs("SEED=%d", seed));
        void'($value$plusargs("PHASE0=%d", phase0));
        void'($value$plusargs("NEG=%s", neg));
        t_clk = 1.0e6 / real'(mhz_khz);         // ns
        half  = t_clk / 2.0;
        // Z80: a 107,386 MHz la base es exactamente 30 x 3,579545 MHz (variante sync)
        if (mhz_khz == 107386) tz = t_clk * ((z80_khz > 5000) ? 15.0 : 30.0);
        else                   tz = 1.0e6 / ((z80_khz > 5000) ? 7159.09 : 3579.545);
        forever #(half) clk = ~clk;
    end

    // contador de ciclos
    longint cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // ------------------------------------------------------------------
    // reset: rst_mem_n = lock del PLL (RESET_n de sdram.sv); sys_rst_n como el
    // reset_n del top (bajo hasta READY de la SDRAM)
    // ------------------------------------------------------------------
    logic rst_mem_n = 1'b0;
    initial begin
        #(100.3);
        rst_mem_n = 1'b1;
    end
    logic sdram_ready;
    logic sys_rst_n = 1'b0;
    always_ff @(posedge clk or negedge rst_mem_n or negedge sdram_ready) begin
        if(!rst_mem_n)        sys_rst_n <= 0;
        else if(!sdram_ready) sys_rst_n <= 0;
        else                  sys_rst_n <= 1;
    end

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    RAM_IF Ram();
    RAM_IF UmaRam[0:1]();
    UMA_IF Uma();
    assign Uma.ADDR[0] = 24'h00_0000;
    assign Uma.ADDR[1] = 24'h78_0000;           // CONFIG::RAM_ADDR_VRAM

    wire [15:0] dbg_int, dbg_ch0, dbg_ch1, dbg_esc;
    wire [11:0] dbg_maxgap;
    wire        dbg_stb;
`ifdef HITO1
    UMA #(.COUNT(2), .SYNC_CLK_EN(0), .DIV(30)) u_uma (
        .RESET_n(sys_rst_n), .CLK(clk), .CLK_EN(1'b0),
        .Primary(Ram), .Secondary(UmaRam), .Uma
    );
    assign dbg_int = 0; assign dbg_ch0 = 0; assign dbg_ch1 = 0; assign dbg_esc = 0;
    assign dbg_maxgap = 0; assign dbg_stb = 0;
`else
    UMA #(.COUNT(2), .SYNC_CLK_EN(0), .DIV(30), .INT_REFRESH(INT_REFRESH)) u_uma (
        .RESET_n(sys_rst_n), .CLK(clk), .CLK_EN(1'b0),
        .Primary(Ram), .Secondary(UmaRam), .Uma,
        .DBG_RF_INT(dbg_int), .DBG_RF_CH0(dbg_ch0), .DBG_RF_CH1(dbg_ch1),
        .DBG_RF_ESC(dbg_esc), .DBG_RF_MAXGAP(dbg_maxgap), .DBG_RF_STB(dbg_stb)
    );
`endif

    wire        SDRAM_CLK, SDRAM_CKE, SDRAM_CS_n, SDRAM_RAS_n, SDRAM_CAS_n, SDRAM_WE_n;
    wire [10:0] SDRAM_A;
    wire [1:0]  SDRAM_BA;
    wire [3:0]  SDRAM_DQM;
    wire [31:0] SDRAM_DQ;
    wire        clk_ps = phase0 ? clk : ~clk;   // CLK_MEM_P: 180 grados

    SDRAM #(
        .SDRAM_A_WIDTH(11), .SDRAM_BA_WIDTH(2), .SDRAM_COL_WIDTH(8),
        .SDRAM_ROW_WIDTH(11), .SDRAM_DQ_WIDTH(32)
    ) u_sdram (
        .CLK(clk), .CLK_PS(clk_ps), .RESET_n(rst_mem_n),
        .READY(sdram_ready), .Ram,
        .SDRAM_CLK, .SDRAM_CKE, .SDRAM_CS_n, .SDRAM_RAS_n, .SDRAM_CAS_n,
        .SDRAM_WE_n, .SDRAM_A, .SDRAM_BA, .SDRAM_DQM, .SDRAM_DQ
    );

    // El reloj llega al modelo desde el primer flanco de CLK con RESET_n alto.
    // Durante el reset SDRAM_CMD no tiene valor de reset en sdram.sv (en dos
    // estados vale 0000 = MRS con A = 0); eso se informa aparte (ver abajo).
    logic mem_run = 1'b0;
    always @(posedge clk) if (rst_mem_n) mem_run <= 1'b1;
    wire mem_clk = SDRAM_CLK & mem_run;

    sdram_model u_mem (
        .clk(mem_clk), .cke(SDRAM_CKE),
        .cs_n(SDRAM_CS_n), .ras_n(SDRAM_RAS_n), .cas_n(SDRAM_CAS_n), .we_n(SDRAM_WE_n),
        .addr(SDRAM_A), .ba(SDRAM_BA), .dqm(SDRAM_DQM), .dq(SDRAM_DQ)
    );

    // ------------------------------------------------------------------
    // memoria de referencia: patron precargado + bytes escritos
    // ------------------------------------------------------------------
    function automatic logic [31:0] pat(input int unsigned w);
        logic [31:0] x;
        x = w * 32'h9E37_79B1 + 32'h7F4A_7C15;
        x = x ^ (x >> 15);
        x = x * 32'h2C1B_3C6D;
        x = x ^ (x >> 12);
        return x;
    endfunction

    logic [7:0] shw [int unsigned];             // bytes escritos (direccion de byte de la SDRAM)

    function automatic logic [7:0] sbyte(input int unsigned a);
        if (shw.exists(a)) return shw[a];
        return 8'(pat(a >> 2) >> (8 * (a & 3)));
    endfunction

    function automatic logic [31:0] sword(input int unsigned wa);   // palabra de 32 bits (indice de palabra)
        return {sbyte(wa*4+3), sbyte(wa*4+2), sbyte(wa*4+1), sbyte(wa*4)};
    endfunction

    // dato que devuelve sdram.sv para una lectura (sdram.sv: STATE_FETCH_RDATA_1/2)
    function automatic logic [31:0] exp_read(input int unsigned a, input logic [2:0] sz);
        logic [31:0] w0, w1;
        w0 = sword(a >> 2);
        w1 = sword((a >> 2) ^ 1);               // segundo beat: columna col ^ 1
        case (sz)
            3'b011:  return {w1[23:16], w1[7:0], w0[23:16], w0[7:0]};      // DIN_SIZE_32_E
            3'b111:  return {w1[31:24], w1[15:8], w0[31:24], w0[15:8]};    // DIN_SIZE_32_O
            default: case (a & 3)
                         0: return w0;
                         1: return {8'h00,  w0[31:8]};
                         2: return {16'h00, w0[31:16]};
                         default: return {24'h00, w0[31:24]};
                     endcase
        endcase
    endfunction

    // escritura tal como la hace sdram.sv (DQM de STATE_SETUP_WDATA_1/2)
    task automatic do_write(input int unsigned a, input logic [2:0] sz, input logic [31:0] d);
        int unsigned w;
        w = a & ~32'd3;
        case (sz)
            3'b000: shw[a] = d[7:0];                                        // DIN_SIZE_8
            3'b001: begin shw[w + (a & 2)] = d[7:0]; shw[w + (a & 2) + 1] = d[15:8]; end   // DIN_SIZE_16
            3'b010: begin shw[w] = d[7:0]; shw[w+1] = d[15:8]; shw[w+2] = d[23:16]; shw[w+3] = d[31:24]; end
            3'b011: begin shw[w] = d[7:0]; shw[w+2] = d[15:8];             // DIN_SIZE_32_E
                          shw[(w ^ 4)] = d[23:16]; shw[(w ^ 4) + 2] = d[31:24]; end
            3'b111: begin shw[w+1] = d[7:0]; shw[w+3] = d[15:8];           // DIN_SIZE_32_O
                          shw[(w ^ 4) + 1] = d[23:16]; shw[(w ^ 4) + 3] = d[31:24]; end
            default: ;
        endcase
    endtask

    initial begin
        for (int w = 0; w < 2097152; w++) u_mem.mem[w] = pat(w);
    end

    // lecturas cuyo dato incluye algun byte escrito durante la simulacion
    // (integridad: escribir y releer, no solo leer el patron precargado)
    function automatic bit touches_written(input int unsigned a, input logic [2:0] sz);
        int unsigned w;
        w = a & ~32'd3;
        for (int i = 0; i < 4; i++) begin
            if (shw.exists(w + i)) return 1;
            if ((sz == 3'b011 || sz == 3'b111) && shw.exists((w ^ 4) + i)) return 1;
        end
        return 0;
    endfunction
    int n_rd_hit_v = 0, n_rd_hit_f = 0, n_rd_hit_c = 0, n_rd_hit_z = 0;

    // generador propio (xorshift32): mismas secuencias en todas las builds.
    // Funcion pura: el estado se actualiza en quien llama (un argumento inout
    // no se devolvia a la variable del modulo en los always de Verilator 5.020)
    function automatic logic [31:0] xsn(input logic [31:0] s);
        logic [31:0] t;
        t = s ^ (s << 13); t = t ^ (t >> 17); t = t ^ (t << 5);
        return t;
    endfunction

    // ------------------------------------------------------------------
    // canal 1: patron del V9990 (protocolo de T9990_RAM)
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {V_REQ, V_ACK, V_BUSY} vst_t;
    vst_t        vst = V_REQ;
    logic        v_exec = 1'b0;
    int          v_slot = 0;
    longint      v_t0 = 0;
    logic [31:0] v_rs = 32'h1234_5678;
    logic        v_isrd = 1'b0;
    logic [31:0] v_exp = 0;
    int unsigned v_a = 0;
    int          v_ops = 0, v_rds = 0, v_wrs = 0, v_rfs = 0, v_lost = 0, v_derr = 0;
    longint      v_lat_min = 1000, v_lat_max = 0;

    initial v_rs = 32'h1234_5678 ^ (seed * 32'h01000193);

    always @(posedge clk or negedge sys_rst_n) begin
        logic [31:0] r;
        logic [2:0]  sz;
        int unsigned va;
        if (!sys_rst_n) begin
            vst <= V_REQ; v_exec <= 1'b0; v_slot <= 0;
            UmaRam[1].OE_n <= 1'b1; UmaRam[1].WE_n <= 1'b1; UmaRam[1].RFSH_n <= 1'b1;
            UmaRam[1].ADDR <= 0; UmaRam[1].DIN <= 0; UmaRam[1].DIN_SIZE <= 0;
        end
        else begin
            v_exec <= UmaRam[1].TIMING;                     // t9990_timing.sv: MEM.EXEC <= MEM_REQ
            if (v_exec) v_slot <= (v_slot == 341) ? 0 : v_slot + 1;
            if (v_exec && vst != V_REQ) v_lost <= v_lost + 1;   // EXEC fuera de WAIT_REQ: ranura perdida
            case (vst)
            V_REQ: if (v_exec && v99_mode != 0) begin
                v_t0 <= cyc;
                v_ops <= v_ops + 1;
                if (v_slot == 0) begin
                    UmaRam[1].RFSH_n <= 1'b0;               // RAM_RF: una vez por linea
                    UmaRam[1].ADDR <= 0; UmaRam[1].DIN <= 0; UmaRam[1].DIN_SIZE <= 0;
                    v_isrd <= 1'b0; v_rfs <= v_rfs + 1;
                end
                else begin
                    v_rs = xsn(v_rs); r = v_rs;
                    v_rs = xsn(v_rs);
                    va = (r[31]) ? (v_rs & 32'h0000_0FFF) : (v_rs & 32'h0007_FFFF);
                    case (r % 100)
                        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,
                        20,21,22,23,24,25,26,27,28,29,30,31,32,33,34: sz = 3'b010;      // lectura 32 (BP)
                        35,36,37,38,39,40,41,42,43,44:                sz = 3'b011;      // lectura 32_E (P1)
                        45,46,47,48,49,50,51,52,53,54:                sz = 3'b111;      // lectura 32_O (P1)
                        default:                                       sz = 3'b000;
                    endcase
                    if ((r % 100) < 65) begin
                        if ((r % 100) >= 55) sz = 3'b000;                               // lectura 8 (CPU)
                        if (sz == 3'b010) va = va & ~32'd3;
                        if (sz == 3'b011 || sz == 3'b111) va = va & ~32'd7;
                        UmaRam[1].OE_n <= 1'b0; UmaRam[1].ADDR <= 24'(va);
                        UmaRam[1].DIN <= 0; UmaRam[1].DIN_SIZE <= sz;
                        v_isrd <= 1'b1;
                        v_exp <= exp_read(32'h0078_0000 + va, sz);
                        v_rds <= v_rds + 1;
                        if (touches_written(32'h0078_0000 + va, sz)) n_rd_hit_v <= n_rd_hit_v + 1;
                    end
                    else begin
                        logic [31:0] d;
                        v_rs = xsn(v_rs); d = v_rs;
                        if ((r % 100) < 77)      sz = 3'b000;                           // escritura 8 (CPU)
                        else if ((r % 100) < 90) sz = 3'b010;                           // escritura 32 (blitter)
                        else if ((r % 100) < 95) sz = 3'b011;                           // escritura 32_E
                        else                     sz = 3'b111;                           // escritura 32_O
                        if (sz == 3'b010) va = va & ~32'd3;
                        if (sz == 3'b011 || sz == 3'b111) va = va & ~32'd7;
                        UmaRam[1].WE_n <= 1'b0; UmaRam[1].ADDR <= 24'(va);
                        UmaRam[1].DIN <= d; UmaRam[1].DIN_SIZE <= sz;
                        v_isrd <= 1'b0;
                        do_write(32'h0078_0000 + va, sz, d);
                        v_wrs <= v_wrs + 1;
                    end
                end
                vst <= V_ACK;
            end
            V_ACK: if (!UmaRam[1].ACK_n) begin
                UmaRam[1].OE_n <= 1'b1; UmaRam[1].WE_n <= 1'b1; UmaRam[1].RFSH_n <= 1'b1;
                vst <= V_BUSY;
            end
            V_BUSY: if (UmaRam[1].ACK_n) begin
                longint lat;
                lat = cyc - v_t0;
                if (lat < v_lat_min) v_lat_min <= lat;
                if (lat > v_lat_max) v_lat_max <= lat;
                if (v_isrd && UmaRam[1].DOUT !== v_exp) begin
                    v_derr <= v_derr + 1;
                    if (v_derr < 5) $display("  [V99 %0t] dato %08h, esperado %08h", $time, UmaRam[1].DOUT, v_exp);
                end
                vst <= V_REQ;
            end
            default: vst <= V_REQ;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // canal 0, modo 1: Z80 sintetico (senales asincronas en tiempo real)
    // ------------------------------------------------------------------
    logic        z_rd_n = 1'b1, z_wr_n = 1'b1, z_rfsh_n = 1'b1;
    logic [15:0] z_addr = 16'h0;
    logic [7:0]  z_data = 8'h0;
    logic [31:0] z_rs = 32'h9ABC_DEF1;
    int          z_m1 = 0, z_mr = 0, z_mw = 0;

    initial begin : z80
        logic [31:0] r;
        z_rs = 32'h9ABC_DEF1 ^ (seed * 32'h0100_0193);
        wait (sys_rst_n === 1'b1);
        #(1000.0 + real'(seed % 97) * 3.1);                 // fase inicial distinta por semilla
        if (ch0_mode == 1) forever begin
            z_rs = xsn(z_rs); r = z_rs;
            z_addr = (r[30]) ? {8'h00, r[7:0]} : r[23:8];
            if (r[31:29] < 4) begin                         // M1 (5 T con la espera del MSX)
                z_m1 = z_m1 + 1;
                #(0.5 * tz) z_rd_n = 1'b0;
                #(2.5 * tz) begin z_rd_n = 1'b1; if (z80_rfsh != 0) z_rfsh_n = 1'b0; end
                #(2.0 * tz) z_rfsh_n = 1'b1;
            end
            else if (r[31:29] < 6) begin                    // lectura de memoria (3 T)
                z_mr = z_mr + 1;
                #(0.5 * tz) z_rd_n = 1'b0;
                #(2.0 * tz) z_rd_n = 1'b1;
                #(0.5 * tz);
            end
            else begin                                      // escritura de memoria (3 T)
                z_mw = z_mw + 1;
                z_rs = xsn(z_rs); z_data = z_rs[7:0];
                #(1.5 * tz) z_wr_n = 1'b0;
                #(1.0 * tz) z_wr_n = 1'b1;
                #(0.5 * tz);
            end
        end
    end

    // dos flops + linea de retardo (PIN_FILTER y mux del bus)
    typedef struct packed { logic rd_n, wr_n, rfsh_n; logic [15:0] addr; logic [7:0] data; } zsig_t;
    zsig_t zs1, zs2, zf;
    zsig_t zdl [0:FE_DELAY-1];
    always @(posedge clk) begin
        zs1 <= '{z_rd_n, z_wr_n, z_rfsh_n, z_addr, z_data};
        zs2 <= zs1;
        zdl[0] <= zs2;
        for (int i = 1; i < FE_DELAY; i++) zdl[i] <= zdl[i-1];
    end
    initial begin
        zs1 = '{1'b1, 1'b1, 1'b1, 16'h0, 8'h0}; zs2 = zs1;
        for (int i = 0; i < FE_DELAY; i++) zdl[i] = zs1;
    end
    assign zf = zdl[FE_DELAY-1];

    // ------------------------------------------------------------------
    // canal 0, modo 2: cliente al 100 % (encadenado por ACK_n)
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {F_IDLE, F_ACK, F_BUSY} fst_t;
    fst_t        fst = F_IDLE;
    logic        f_oe_n = 1'b1, f_we_n = 1'b1;
    logic [23:0] f_addr = 0;
    logic [31:0] f_din = 0;
    logic [2:0]  f_sz = 0;
    logic        f_isrd = 1'b0;
    logic [31:0] f_exp = 0;
    longint      f_t0 = 0;
    logic [31:0] f_rs = 32'h0BAD_F00D;
    int          f_ops = 0, f_derr = 0;
    longint      f_lat_min = 1000, f_lat_max = 0;
    int          f_lat_hist [longint];

    initial f_rs = 32'h0BAD_F00D ^ (seed * 32'h0100_0193);

    always @(posedge clk or negedge sys_rst_n) begin
        logic [31:0] r, d;
        int unsigned a;
        logic [2:0] sz;
        if (!sys_rst_n) begin
            fst <= F_IDLE; f_oe_n <= 1'b1; f_we_n <= 1'b1; f_addr <= 0; f_din <= 0; f_sz <= 0;
        end
        else if (ch0_mode == 2) begin
            case (fst)
            F_IDLE: begin
                f_rs = xsn(f_rs); r = f_rs;
                a = 32'h0041_0000 + (r[15:6] ^ {r[25:24], 8'h0});
                case (r[3:2])
                    2'd0, 2'd1: sz = 3'b000;
                    2'd2:       begin sz = 3'b001; a = a & ~32'd1; end
                    default:    begin sz = 3'b010; a = a & ~32'd3; end
                endcase
                f_addr <= 24'(a); f_sz <= sz; f_t0 <= cyc + 1;
                if (r[0]) begin
                    f_oe_n <= 1'b0; f_din <= 0; f_isrd <= 1'b1;
                    f_exp <= exp_read(a, sz);
                    if (touches_written(a, sz)) n_rd_hit_f <= n_rd_hit_f + 1;
                end
                else begin
                    f_rs = xsn(f_rs); d = f_rs;
                    f_we_n <= 1'b0; f_din <= d; f_isrd <= 1'b0;
                    do_write(a, sz, d);
                end
                f_ops <= f_ops + 1;
                fst <= F_ACK;
            end
            F_ACK: if (!UmaRam[0].ACK_n) begin
                f_oe_n <= 1'b1; f_we_n <= 1'b1; f_addr <= 0; f_din <= 0;
                fst <= F_BUSY;
            end
            F_BUSY: if (UmaRam[0].ACK_n) begin
                longint lat;
                lat = cyc - f_t0;
                if (lat < f_lat_min) f_lat_min <= lat;
                if (lat > f_lat_max) f_lat_max <= lat;
                if (f_lat_hist.exists(lat)) f_lat_hist[lat] = f_lat_hist[lat] + 1;
                else                        f_lat_hist[lat] = 1;
                if (f_isrd && UmaRam[0].DOUT !== f_exp) begin
                    f_derr <= f_derr + 1;
                    if (f_derr < 5) $display("  [CH0 %0t] dato %08h, esperado %08h", $time, UmaRam[0].DOUT, f_exp);
                end
                fst <= F_IDLE;
            end
            default: fst <= F_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // canal 0, modo 3: R/W y RFSH a la vez (dos clientes del EXPANSION_RAM,
    // p. ej. el RFSH reenviado de uno y la lectura de otro en el mismo ciclo).
    // Handshake por ACK_n como el bootloader, con una pausa aleatoria entre
    // operaciones. Cada RFSH pedido tiene que salir como un AUTO REFRESH.
    // ------------------------------------------------------------------
    fst_t        cst = F_IDLE;
    logic        c_oe_n = 1'b1, c_we_n = 1'b1, c_rfsh_n = 1'b1;
    logic [23:0] c_addr = 0;
    logic [31:0] c_din = 0;
    logic        c_isrd = 1'b0;
    logic [31:0] c_exp = 0;
    logic [31:0] c_rs = 32'h0C0F_FEE1;
    int          c_ops = 0, c_rfsh = 0, c_derr = 0, c_gap = 0, c_rfsh_only = 0;

    initial c_rs = 32'h0C0F_FEE1 ^ (seed * 32'h0100_0193);

    always @(posedge clk or negedge sys_rst_n) begin
        logic [31:0] r, d;
        int unsigned a;
        if (!sys_rst_n) begin
            cst <= F_IDLE; c_oe_n <= 1'b1; c_we_n <= 1'b1; c_rfsh_n <= 1'b1; c_addr <= 0; c_din <= 0; c_gap <= 0;
        end
        else if (ch0_mode == 3) begin
            case (cst)
            F_IDLE: if (c_gap > 0) c_gap <= c_gap - 1;
            else begin
                c_rs = xsn(c_rs); r = c_rs;
                a = 32'h0042_0000 + r[17:8];
                c_addr <= 24'(a);
                c_rfsh_n <= 1'b0;                           // RFSH en el mismo ciclo que el R/W
                c_rfsh <= c_rfsh + 1;
                if (r[2:1] == 2'b00) begin                  // solo RFSH, con ACK, como el bootloader
                    c_addr <= 0; c_din <= 0; c_isrd <= 1'b0;    // (bootloader.sv: SUB_STATE_*_RFSH_REQ)
                    c_rfsh_only <= c_rfsh_only + 1;
                end
                else if (r[0]) begin
                    c_oe_n <= 1'b0; c_din <= 0; c_isrd <= 1'b1;
                    c_exp <= exp_read(a, 3'b000);
                    if (touches_written(a, 3'b000)) n_rd_hit_c <= n_rd_hit_c + 1;
                end
                else begin
                    c_rs = xsn(c_rs); d = c_rs;
                    c_we_n <= 1'b0; c_din <= d; c_isrd <= 1'b0;
                    do_write(a, 3'b000, d);
                end
                c_ops <= c_ops + 1;
                cst <= F_ACK;
            end
            F_ACK: if (!UmaRam[0].ACK_n) begin
                c_oe_n <= 1'b1; c_we_n <= 1'b1; c_rfsh_n <= 1'b1; c_addr <= 0; c_din <= 0;
                cst <= F_BUSY;
            end
            F_BUSY: if (UmaRam[0].ACK_n) begin
                if (c_isrd && UmaRam[0].DOUT !== c_exp) begin
                    c_derr <= c_derr + 1;
                    if (c_derr < 5) $display("  [CH0c %0t] dato %08h, esperado %08h", $time, UmaRam[0].DOUT, c_exp);
                end
                c_rs = xsn(c_rs);
                c_gap <= c_rs % 41;
                cst <= F_IDLE;
            end
            default: cst <= F_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // multiplexor del canal 0 (un solo driver de UmaRam[0])
    // ------------------------------------------------------------------
    always_comb begin
        case (ch0_mode)
        3: begin
            UmaRam[0].OE_n     = c_oe_n;
            UmaRam[0].WE_n     = c_we_n;
            UmaRam[0].RFSH_n   = c_rfsh_n;
            UmaRam[0].ADDR     = c_addr;
            UmaRam[0].DIN      = c_din;
            UmaRam[0].DIN_SIZE = 3'b000;
        end
        1: begin                                            // como megarom_controller.sv (USE_FF = 0)
            UmaRam[0].OE_n     = zf.rd_n;
            UmaRam[0].WE_n     = zf.wr_n;
            UmaRam[0].RFSH_n   = (z80_rfsh != 0) ? zf.rfsh_n : 1'b1;
            UmaRam[0].ADDR     = (zf.rd_n && zf.wr_n) ? 24'h0 : (24'h40_0000 + {8'h0, zf.addr});
            UmaRam[0].DIN      = zf.wr_n ? 32'h0 : {24'h0, zf.data};
            UmaRam[0].DIN_SIZE = 3'b000;
        end
        2: begin
            UmaRam[0].OE_n     = f_oe_n;
            UmaRam[0].WE_n     = f_we_n;
            UmaRam[0].RFSH_n   = 1'b1;
            UmaRam[0].ADDR     = f_addr;
            UmaRam[0].DIN      = f_din;
            UmaRam[0].DIN_SIZE = f_sz;
        end
        default: begin
            UmaRam[0].OE_n     = 1'b1;
            UmaRam[0].WE_n     = 1'b1;
            UmaRam[0].RFSH_n   = 1'b1;
            UmaRam[0].ADDR     = 24'h0;
            UmaRam[0].DIN      = 32'h0;
            UmaRam[0].DIN_SIZE = 3'b000;
        end
        endcase
    end

    // ------------------------------------------------------------------
    // comprobaciones del Z80 en el dominio de CLK
    //   - el dato (32 bits de Secondary[0].DOUT) cambia como mucho una vez
    //     mientras OE_n esta bajo, y si cambia es al dato correcto;
    //   - con OE_n subiendo, DOUT es el dato correcto (si no, lectura "tarde":
    //     el Z80 habria leido el dato rancio);
    //   - ultima lectura: latencia desde el flanco de OE_n hasta el cambio.
    // ------------------------------------------------------------------
    logic        zc_prev_oe = 1'b1, zc_prev_we = 1'b1, zc_act = 1'b0;
    logic [31:0] zc_exp = 0, zc_dprev = 0;
    longint      zc_t0 = 0;
    int          zc_chg = 0;
    int          z_reads = 0, z_writes = 0, z_late = 0, z_unstable = 0, z_badchg = 0, z_derr = 0;
    longint      z_cap_max = 0;
    // cobertura: refrescos internos emitidos con una lectura del Z80 en curso y
    // ya capturada que sigue con /RD bajo 10 ciclos despues (cuando un refresco
    // que pasara por done_ch sobrescribiria Secondary[0].DOUT)
    int          zc_id = 0;
    logic        zc_cap = 1'b0;
    int          int_sr_id [0:10];
    int          z_int_cov = 0;
    initial for (int i = 0; i <= 10; i++) int_sr_id[i] = -1;
`ifndef HITO1
    always @(posedge clk) begin
        int_sr_id[0] <= (u_uma.int_issue && zc_act && zc_cap) ? zc_id : -1;
        for (int i = 1; i <= 10; i++) int_sr_id[i] <= int_sr_id[i-1];
        if (int_sr_id[10] >= 0 && int_sr_id[10] == zc_id && zc_act && !UmaRam[0].OE_n) z_int_cov <= z_int_cov + 1;
        if (zc_prev_oe && !UmaRam[0].OE_n)                                 zc_cap <= 1'b0;
        else if (zc_act && u_uma.done_ch[0] && u_uma.proc_rw[0])          zc_cap <= 1'b1;
    end
`endif
    always @(posedge clk) begin
        if (sys_rst_n && ch0_mode == 1) begin
            zc_prev_oe <= UmaRam[0].OE_n;
            zc_prev_we <= UmaRam[0].WE_n;
            if (zc_prev_oe && !UmaRam[0].OE_n) zc_id <= zc_id + 1;
            if (zc_prev_we && !UmaRam[0].WE_n) begin
                do_write(UmaRam[0].ADDR, 3'b000, UmaRam[0].DIN);
                z_writes <= z_writes + 1;
            end
            if (zc_prev_oe && !UmaRam[0].OE_n) begin
                zc_act <= 1'b1;
                zc_exp <= exp_read(UmaRam[0].ADDR, 3'b000);
                if (touches_written(UmaRam[0].ADDR, 3'b000)) n_rd_hit_z <= n_rd_hit_z + 1;
                zc_dprev <= UmaRam[0].DOUT;
                zc_chg <= 0;
                zc_t0 <= cyc;
                z_reads <= z_reads + 1;
            end
            else if (zc_act && UmaRam[0].OE_n) begin
                zc_act <= 1'b0;
                if (UmaRam[0].DOUT !== zc_exp) begin
                    if (zc_chg == 0) z_late <= z_late + 1;
                    else begin
                        z_derr <= z_derr + 1;
                        if (z_derr < 5) $display("  [Z80 %0t] dato %08h, esperado %08h", $time, UmaRam[0].DOUT, zc_exp);
                    end
                end
            end
            else if (zc_act && UmaRam[0].DOUT !== zc_dprev) begin
                zc_dprev <= UmaRam[0].DOUT;
                zc_chg <= zc_chg + 1;
                if (zc_chg >= 1) z_unstable <= z_unstable + 1;
                if (UmaRam[0].DOUT !== zc_exp) z_badchg <= z_badchg + 1;
                if (cyc - zc_t0 > z_cap_max) z_cap_max <= cyc - zc_t0;
            end
        end
    end

    // ------------------------------------------------------------------
    // monitores de la SDRAM y del Primary
    // ------------------------------------------------------------------
    wire [3:0] pin_cmd = {SDRAM_CS_n, SDRAM_RAS_n, SDRAM_CAS_n, SDRAM_WE_n};
    realtime t_last_ref = 0, max_gap = 0;
    longint  n_ref_rt = 0;
    int      n_win_err = 0, n_wdrv_err = 0, n_cont_err = 0, n_both = 0;
    logic    wr_beat2 = 1'b0;
    logic [3:0] rst_cmd = 4'hF;
    logic       rst_cmd_seen = 1'b0;

    // AUTO REFRESH vistos en los pines (flanco del reloj de la SDRAM). El
    // intervalo cuenta desde el REF anterior, sea de la inicializacion o no.
    int n_cont_err_m = 0;
    always @(posedge mem_clk) begin
        if (pin_cmd == 4'b0001) begin
            if (u_mem.mrs_done) begin
                if ($realtime - t_last_ref > max_gap) max_gap = $realtime - t_last_ref;
                n_ref_rt = n_ref_rt + 1;
            end
            t_last_ref = $realtime;
        end
        // escritura: el controlador conduce el bus en los dos beats
        if (pin_cmd == 4'b0100 || wr_beat2) begin
            if (u_sdram.sdram_DQ_OUT_ENA_n !== 1'b0) n_wdrv_err = n_wdrv_err + 1;
        end
        wr_beat2 <= (pin_cmd == 4'b0100);
        if (u_mem.dq_mode != 2'd0 && u_sdram.sdram_DQ_OUT_ENA_n == 1'b0) n_cont_err_m = n_cont_err_m + 1;
    end

    // captura de lectura de sdram.sv dentro de la ventana valida del modelo
    // (sdram.sv: STATE_FETCH_RDATA_1 = IDLE + 6 = 38, STATE_FETCH_RDATA_2 = 39)
    always @(posedge clk) begin
        if (u_sdram.cmd_is_read && u_sdram.state == 7'd38 && u_mem.dq_mode != 2'd2) n_win_err <= n_win_err + 1;
        if (u_sdram.cmd_is_read && u_sdram.state == 7'd39 &&
            (u_sdram.save_din_size == 3'b011 || u_sdram.save_din_size == 3'b111) && u_mem.dq_mode != 2'd2)
            n_win_err <= n_win_err + 1;
        if (u_mem.dq_mode != 2'd0 && u_sdram.sdram_DQ_OUT_ENA_n == 1'b0) n_cont_err <= n_cont_err + 1;
        // el UMA nunca presenta RFSH junto a OE/WE
        if (sys_rst_n && !Ram.RFSH_n && (!Ram.OE_n || !Ram.WE_n)) n_both <= n_both + 1;
        // que hay en los pines de comando antes del primer flanco tras el reset
        if (!rst_mem_n && !rst_cmd_seen) begin rst_cmd <= pin_cmd; rst_cmd_seen <= 1'b1; end
    end

    // cadencia: en cada exec_timing (de los dos canales) la operacion anterior
    // ha terminado: sdram.sv vuelve a estar en STATE_IDLE (= 32: los 9 estados
    // del acceso y la captura del dato en STATE_FETCH_RDATA_1/2 ya pasaron),
    // su ACK_n esta alto y el UMA ya no presenta OE/WE/RFSH. Es la regla del
    // estudio "ciclo del controlador + 1 <= ranura" (9 + 1 <= 10): sin ese
    // ciclo de holgura el sistema aun funciona (control slack0), con uno
    // menos el done_ch capturaria un dato a medias o el UMA perderia la
    // ranura, porque Primary.ACK_n bajo tiene prioridad en uma.sv (control slow).
    longint n_slot_chk = 0, n_slot_err = 0;
    always @(posedge clk) begin
        if (sys_rst_n && (u_uma.exec_timing[0] || u_uma.exec_timing[1])) begin
            n_slot_chk <= n_slot_chk + 1;
            if (u_sdram.state != 7'd32 || !Ram.ACK_n || !Ram.OE_n || !Ram.WE_n || !Ram.RFSH_n) begin
                n_slot_err <= n_slot_err + 1;
                if (n_slot_err < 5) $display("  [SLOT %0t] state=%0d ACK_n=%b OE_n=%b WE_n=%b RFSH_n=%b",
                                             $time, u_sdram.state, Ram.ACK_n, Ram.OE_n, Ram.WE_n, Ram.RFSH_n);
            end
        end
    end

    // el refresco interno solo sale en una ranura del canal 0, y sin cliente en
    // el canal 0 su ACK_n y su DOUT no se mueven aunque haya refrescos internos
    int   n_int_slot_err = 0, n_ch0_ack_low = 0, n_ch0_dout_chg = 0, n_int_issue = 0;
    logic [31:0] ch0_dout_q = 0;
    always @(posedge clk) begin
        ch0_dout_q <= UmaRam[0].DOUT;
`ifndef HITO1
        if (u_uma.int_issue) n_int_issue <= n_int_issue + 1;
        if (u_uma.int_issue && (!u_uma.exec_timing[0] || u_uma.exec_timing[1])) n_int_slot_err <= n_int_slot_err + 1;
`endif
        if (sys_rst_n && ch0_mode == 0) begin
            if (!UmaRam[0].ACK_n)               n_ch0_ack_low  <= n_ch0_ack_low + 1;
            if (UmaRam[0].DOUT !== ch0_dout_q)  n_ch0_dout_chg <= n_ch0_dout_chg + 1;
        end
    end

    // ------------------------------------------------------------------
    // informe
    // ------------------------------------------------------------------
    int  n_fail = 0, n_neg_fail = 0;
    string fails = "";

    task automatic check(input string name, input bit ok, input string what);
        if (neg == name) begin
            $display("CHECK %-8s %s  (control negativo: se espera FALLA) %s", name, ok ? "PASA " : "FALLA", what);
            if (!ok) n_neg_fail++;
        end
        else if (neg != "" && neg != name) begin
            $display("CHECK %-8s %s  (informativo en el control) %s", name, ok ? "PASA " : "FALLA", what);
        end
        else begin
            $display("CHECK %-8s %s  %s", name, ok ? "PASA " : "FALLA", what);
            if (!ok) begin n_fail++; fails = {fails, " ", name}; end
        end
    endtask

    initial begin
        realtime t_end, tail;
        longint  lat_base, n_def;
        bit      lat_ok;
        #(real'(sim_us) * 1000.0);
        t_end = $realtime;
        tail = t_end - t_last_ref;                  // tramo final sin refresco tambien cuenta
        if (tail > max_gap) max_gap = tail;

        $display("== MHZ=%0d CH0=%0d Z80KHZ=%0d Z80RFSH=%0d V99=%0d US=%0d SEED=%0d PHASE0=%0d INT_REFRESH=%0d%s NEG=%s",
                 mhz_khz, ch0_mode, z80_khz, z80_rfsh, v99_mode, sim_us, seed, phase0, INT_REFRESH,
`ifdef HITO1
                 " HITO1",
`else
                 "",
`endif
                 neg);
        $display("modelo: ACT=%0d RD=%0d WR=%0d REF=%0d MRS=%0d errores=%0d REF_antes_del_MRS=%0d",
                 u_mem.n_act, u_mem.n_rd, u_mem.n_wr, u_mem.n_ref, u_mem.n_mrs, u_mem.n_err, u_mem.n_ref_before_mrs);
        $display("pines de comando durante el reset (antes del primer flanco): %b%s", rst_cmd,
                 (rst_cmd == 4'b0000) ? " = MRS con A=0 (SDRAM_CMD sin reset en sdram.sv)" : "");
        $display("refresco: REF_tras_init=%0d intervalo_max=%.3f us (%0.0f ciclos) tasa=%.1f k/s",
                 n_ref_rt, max_gap / 1000.0, max_gap / t_clk, real'(n_ref_rt) / (t_end / 1.0e6));
        $display("UMA dbg: INT=%0d CH0=%0d CH1=%0d ESC=%0d MAXGAP=%0d (ciclos-1)",
                 dbg_int, dbg_ch0, dbg_ch1, dbg_esc, dbg_maxgap);
        $display("canal 1: ops=%0d rd=%0d wr=%0d rf=%0d perdidas=%0d err_dato=%0d latencia=%0d..%0d ciclos",
                 v_ops, v_rds, v_wrs, v_rfs, v_lost, v_derr, v_lat_min, v_lat_max);
        if (ch0_mode == 1)
            $display("canal 0 Z80: M1=%0d MR=%0d MW=%0d lecturas=%0d escrituras=%0d tarde=%0d inestables=%0d cambio_malo=%0d err_dato=%0d captura_max=%0d ciclos refrescos_internos_tras_captura=%0d",
                     z_m1, z_mr, z_mw, z_reads, z_writes, z_late, z_unstable, z_badchg, z_derr, z_cap_max, z_int_cov);
        if (ch0_mode == 3)
            $display("canal 0 R/W+RFSH: ops=%0d rfsh_pedidos=%0d (solo_rfsh=%0d) err_dato=%0d", c_ops, c_rfsh, c_rfsh_only, c_derr);
        if (ch0_mode == 2) begin
            $write("canal 0 100%%: ops=%0d err_dato=%0d latencias:", f_ops, f_derr);
            foreach (f_lat_hist[l]) $write(" %0d:%0d", l, f_lat_hist[l]);
            $display("");
        end
        $display("bus: fuera_de_ventana=%0d escritura_sin_conducir=%0d contienda=%0d RFSH_con_RW=%0d",
                 n_win_err, n_wdrv_err, n_cont_err + n_cont_err_m, n_both);
        $display("integridad: lecturas con bytes escritos antes canal0=%0d canal1=%0d; refresco interno: emitidos=%0d fuera_de_ranura0=%0d; canal 0 sin cliente: ACK_n_bajo=%0d cambios_DOUT=%0d",
                 n_rd_hit_f + n_rd_hit_c + n_rd_hit_z, n_rd_hit_v, n_int_issue, n_int_slot_err, n_ch0_ack_low, n_ch0_dout_chg);

        check("model",  u_mem.n_err == 0, "modelo sin errores (tRC, tRCD, filas, MRS)");
        check("init",   u_mem.n_ref_before_mrs >= 2, $sformatf("%0d AUTO REFRESH antes del MRS (JEDEC >= 2)", u_mem.n_ref_before_mrs));
        check("window", n_win_err == 0 && n_wdrv_err == 0 && n_cont_err == 0 && n_cont_err_m == 0, "capturas dentro de la ventana, escrituras conducidas, sin contienda");
        check("gap",    max_gap < REF_MAX_NS, $sformatf("intervalo maximo entre AUTO REFRESH %.3f us < 15,6 us", max_gap / 1000.0));
        check("ch1",    v_lost == 0 && v_derr == 0 && (v99_mode == 0 || (v_lat_min == v_lat_max && v_lat_max < 20)),
              $sformatf("canal 1 sin ranuras perdidas ni datos malos, latencia fija < 20 (%0d..%0d)", v_lat_min, v_lat_max));
        check("rfsh_rw", n_both == 0, "el UMA nunca presenta RFSH junto a OE/WE");
        check("slot",   n_slot_err == 0 && n_slot_chk > 1000,
              $sformatf("en cada exec_timing la SDRAM ha terminado el acceso anterior (%0d ranuras, %0d mal)", n_slot_chk, n_slot_err));
`ifndef HITO1
        check("dbg",    16'(dbg_int + dbg_ch0 + dbg_ch1) == 16'(n_ref_rt),
              $sformatf("contadores del UMA (%0d) = AUTO REFRESH en los pines (%0d)", dbg_int + dbg_ch0 + dbg_ch1, n_ref_rt));
        check("int_slot", n_int_slot_err == 0, "el refresco interno solo sale en exec_timing[0]");
`endif
        if (ch0_mode == 0)
            check("ch0_quiet", n_ch0_ack_low == 0 && n_ch0_dout_chg == 0,
                  "sin cliente en el canal 0, su ACK_n y su DOUT no se mueven con los refrescos internos");
        if (v99_mode != 0)
            check("integ1", n_rd_hit_v > 1000, $sformatf("el canal 1 relee datos escritos (%0d lecturas)", n_rd_hit_v));
        if (ch0_mode != 0)
            check("integ0", n_rd_hit_f + n_rd_hit_c + n_rd_hit_z > 100, $sformatf("el canal 0 relee datos escritos (%0d lecturas)", n_rd_hit_f + n_rd_hit_c + n_rd_hit_z));
        if (ch0_mode == 1) begin
            check("z80",  z_unstable == 0 && z_badchg == 0 && z_derr == 0 && (z80_khz > 5000 || z_late == 0),
                  $sformatf("DOUT estable y correcto en cada /RD (tarde=%0d)", z_late));
`ifndef HITO1
            check("esc0", dbg_esc == 0, $sformatf("cero escalaciones (%0d)", dbg_esc));
            if (z80_rfsh == 0 && INT_REFRESH != 0)
                check("cov", z_int_cov > 0, $sformatf("hay refrescos internos dentro de lecturas ya capturadas (%0d)", z_int_cov));
`endif
        end
        if (ch0_mode == 3) begin
            check("ch0", c_derr == 0 && c_ops > 1000, $sformatf("datos del canal 0 correctos y el handshake avanza (%0d ops)", c_ops));
`ifdef HITO1
            check("rfsh", n_ref_rt == c_rfsh || n_ref_rt + 1 == c_rfsh,
                  $sformatf("cada RFSH pedido junto a un R/W sale como AUTO REFRESH (%0d de %0d)", n_ref_rt, c_rfsh));
`else
            check("rfsh", (INT_REFRESH == 0) ? (n_ref_rt == c_rfsh || n_ref_rt + 1 == c_rfsh)
                                             : (dbg_ch0 == 16'(c_rfsh) || dbg_ch0 + 1 == 16'(c_rfsh)),
                  $sformatf("cada RFSH pedido junto a un R/W sale como AUTO REFRESH (%0d de %0d)",
                            (INT_REFRESH == 0) ? int'(n_ref_rt) : int'(dbg_ch0), c_rfsh));
`endif
        end
        if (ch0_mode == 2) begin
            // latencia base = la mas frecuente; un R/W aplazado tarda exactamente
            // 20 ciclos mas (una ranura del canal 0). Se descarta el primer acceso,
            // que sale con otra fase respecto a las ranuras.
            lat_base = 0; n_def = 0; lat_ok = 1;
            begin
                int best;
                best = 0;
                foreach (f_lat_hist[l]) if (f_lat_hist[l] > best) begin best = f_lat_hist[l]; lat_base = l; end
            end
            foreach (f_lat_hist[l]) begin
                if (l == lat_base + 20) n_def = f_lat_hist[l];
                else if (l != lat_base && !(f_lat_hist[l] == 1 && l < lat_base)) lat_ok = 0;
            end
            check("ch0",  f_derr == 0, "datos del canal 0 correctos");
`ifndef HITO1
            // con el canal 0 lleno no hay ranura libre: cada refresco interno es
            // una escalacion y aplaza exactamente un R/W
            check("esc",  lat_ok && n_def == longint'(dbg_esc) && (INT_REFRESH == 0 || (dbg_esc > 0 && dbg_esc == dbg_int)),
                  $sformatf("cada refresco interno aplaza un R/W exactamente una ranura (aplazados=%0d escalaciones=%0d internos=%0d)", n_def, dbg_esc, dbg_int));
`endif
        end
        if (neg != "") begin
            if (n_neg_fail > 0) $display("RESULT: PASA (el control negativo '%s' falla como se espera)", neg);
            else                $display("RESULT: FALLA (el control negativo '%s' no fallo)", neg);
        end
        else if (n_fail == 0) $display("RESULT: PASA");
        else                  $display("RESULT: FALLA:%s", fails);
        $finish;
    end
endmodule

`default_nettype wire
