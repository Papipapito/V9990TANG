// ============================================================================
// tb_bus.sv -- banco del bus de la WonderTANG con el V9990 (hito 5).
//
// Modelo del Z80 (ciclos M1, lectura y escritura de memoria y de E/S con los
// retardos del Z80A: direccion a 110 ns del flanco, /IORQ a 70 y /RD o /WR a 75
// del flanco de T2, /MREQ y /RD de memoria a 70/75 de la bajada de T1, /WAIT
// muestreado en la bajada de TW (T2 en memoria) con 70 ns de setup y el dato
// en la bajada de T3 con 50 ns) a 3,58 / 5,37 / 7,16 / 10,74 MHz, contra la
// placa: tres 74LVC245 multiplexados por CART_MUX_CS_n (4 ns de reloj a pad,
// 6 ns de habilitacion con basura mientras conmuta, 4 ns de propagacion, 1,5 de
// pad a registro), el transceptor de datos, /WAIT por un NPN (50 ns en entrar,
// 300 en soltar con el pull-up del MSX) y los pines directos RD/WR/SLTSL/CLOCK.
//
// DUT: BOARD_REV1_BUS + EXPANSION_SLOT (USE_FF = 1) + CARTRIDGE_V9990 + T9990
// (TOPO = 0) o BOARD_REV1_BUS + CARTRIDGE_V9990 + T9990 (TOPO = 1), con el UMA
// real (DIV 30, libre) y una SDRAM de mentira con la latencia de sdram.sv.
// V99_BASE = 70h deja 60h/61h sin nadie (liberacion del pre-WAIT por K);
// MEMPW = 1 activa PREWAIT_MEM_EN con una MegaRAM de mentira en la subranura 0.
// SCAN/PWIO/AHOLD/TAILG = 0 quitan una parte de BOARD_REV1_BUS (escaneo
// adaptativo, pre-WAIT, retencion de la direccion, guardia de cola): con las
// cuatro a 0 el bus es el de tnCart con las guardias de salida.
//
// Plusargs: +HZ=<frecuencia del Z80> +SEED=<n> +N=<accesos por fase>.
// Salida: tabla de resultados y BUS_OK / BUS_FAIL (criterio por velocidad en
// docs/notas/bus.md).
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_bus;
    parameter int       TOPO      = 0;
    parameter [7:0]     V99_BASE  = 8'h60;
    parameter int       MEMPW     = 0;
    // variantes de BOARD_REV1_BUS (1 = la del hito 5; 0 = sin esa parte, para
    // ver que el banco detecta lo que cada parte arregla)
    parameter int       SCAN      = 1;      // ADAPTIVE_SCAN
    parameter int       PWIO      = 1;      // PREWAIT_IO_EN
    parameter int       AHOLD     = 1;      // ADDR_HOLD
    parameter int       TAILG     = 1;      // DRIVE_TAIL_GUARD
    parameter int       PW_K      = 6;      // PREWAIT_K
    parameter int       PW_MEM_K  = 7;      // PREWAIT_MEM_K
    parameter real      T_FPGA_CO = 4.0;
    parameter real      T_BUF_EN  = 6.0;
    parameter real      T_BUF_PD  = 4.0;
    parameter real      T_FPGA_IN = 1.5;
    parameter real      T_NPN_ON  = 50.0;
    parameter real      T_NPN_OFF = 300.0;

    // retardos del Z80A (ns)
    localparam real T_AD   = 110.0;     // flanco de T1 -> direccion valida
    localparam real T_AGL  = 20.0;      // flanco de T1 -> direccion en transicion (basura)
    localparam real T_IORQ = 70.0;      // subida de T2 -> /IORQ
    localparam real T_STB  = 75.0;      // subida de T2 -> /RD, /WR (E/S); bajada de T1 -> /RD; bajada de T2 -> /WR (memoria)
    localparam real T_MREQ = 70.0;      // bajada de T1 -> /MREQ
    localparam real T_SLT  = 85.0;      // bajada de T1 -> /SLTSL (decodificador de ranuras del MSX)
    localparam real T_DOUT = 100.0;     // bajada de T1 -> dato de escritura
    localparam real T_OFF  = 80.0;      // bajada de T3 -> fin de /RD, /WR, /IORQ, /MREQ
    localparam real T_DHLD = 60.0;      // dato de escritura tras /WR
    localparam real T_SU_W = 70.0;      // setup de /WAIT
    localparam real T_SU_D = 50.0;      // setup del dato
    localparam real CLKP   = 1000.0 / 108.0;

    // ------------------------------------------------------------------
    //  Relojes y reset
    // ------------------------------------------------------------------
    reg clk = 1'b0;
    always #(CLKP / 2.0) clk = ~clk;
    reg rst_n = 1'b0;
    reg cart_clk = 1'b0;
    reg cart_clk_run = 1'b1;
    always #(1000.0 / 3.579545 / 2.0) if (cart_clk_run) cart_clk = ~cart_clk;

    // ------------------------------------------------------------------
    //  Senales del slot (lado MSX)
    // ------------------------------------------------------------------
    reg [15:0] s_a       = 16'hFFFF;
    reg        s_mreq_n  = 1'b1;
    reg        s_iorq_n  = 1'b1;
    reg        s_rd_n    = 1'b1;
    reg        s_wr_n    = 1'b1;
    reg        s_m1_n    = 1'b1;
    reg        s_rfsh_n  = 1'b1;
    reg        s_sltsl_n = 1'b1;
    reg        s_reset_n = 1'b0;
    reg        z_drv     = 1'b0;     // el Z80 conduce el dato (escrituras)
    reg [7:0]  z_val     = 8'h00;
    reg        m_drv     = 1'b0;     // la memoria del MSX conduce el dato
    reg [7:0]  m_val     = 8'h00;
    wire s_cs1_n  = !(!s_sltsl_n && !s_mreq_n && !s_rd_n && s_a[15:14] == 2'b01);
    wire s_cs2_n  = !(!s_sltsl_n && !s_mreq_n && !s_rd_n && s_a[15:14] == 2'b10);
    wire s_cs12_n = s_cs1_n && s_cs2_n;

    // ------------------------------------------------------------------
    //  DUT
    // ------------------------------------------------------------------
    reg  drive_en  = 1'b1;
    reg  boot_hold = 1'b0;
    wire wait_timeout, bus_ok_o;
    wire cart_busdir_n, cart_int_n, cart_wait_n, cart_data_dir;
    wire [2:0] cart_mux_cs_n;
    wire [7:0] cart_mux_sig;
    wire [7:0] cart_data;
    wire cart_sltsl_n, cart_rd_n, cart_wr_n, cart_clock;

    BUS_IF Bus();
    BOARD_REV1_BUS #(
        .ADAPTIVE_SCAN  (SCAN),
        .PREWAIT_IO_EN  (PWIO),
        .ADDR_HOLD      (AHOLD),
        .DRIVE_TAIL_GUARD (TAILG),
        .PREWAIT_K      (PW_K),
        .PREWAIT_MEM_K  (PW_MEM_K),
        .PREWAIT_MEM_EN (MEMPW)
    ) u_bus (
        .RESET_n        (rst_n),
        .CLK            (clk),
        .CLK_21M        (1'b0),
        .DRIVE_EN       (drive_en),
        .BOOT_HOLD      (boot_hold),
        .WAIT_TIMEOUT   (wait_timeout),
        .BUS_OK         (bus_ok_o),
        .CART_BUSDIR_n  (cart_busdir_n),
        .CART_INT_n     (cart_int_n),
        .CART_WAIT_n    (cart_wait_n),
        .CART_SLTSL_n   (cart_sltsl_n),
        .CART_RD_n      (cart_rd_n),
        .CART_WR_n      (cart_wr_n),
        .CART_CLOCK     (cart_clock),
        .CART_MUX_SIG   (cart_mux_sig),
        .CART_MUX_CS_n  (cart_mux_cs_n),
        .CART_DATA_SIG  (cart_data),
        .CART_DATA_DIR  (cart_data_dir),
        .Bus            (Bus)
    );

    // VRAM: UMA real + SDRAM de mentira
    RAM_IF Ram();
    UMA_IF Uma();
    RAM_IF UmaRam[0:1]();
    assign Uma.ADDR[0] = 24'h00_0000;
    assign Uma.ADDR[1] = 24'h78_0000;
    UMA #(
        .COUNT          (2),
        .SYNC_CLK_EN    (0),
        .DIV            (30)
    ) u_uma (
        .RESET_n        (rst_n),
        .CLK            (clk),
        .CLK_EN         (Bus.CLK_EN),
        .Primary        (Ram),
        .Secondary      (UmaRam),
        .Uma            (Uma)
    );
    always_comb UmaRam[0].connect_dummy();
    TB_SDRAM_HOST u_sdr (.CLK(clk), .RESET_n(rst_n), .Ram(Ram));
    VIDEO_IF Video();

    reg boot_wait_n = 1'b1;
    if (TOPO == 0) begin : g_top
        BUS_IF ExpBus[0:5]();
        EXPANSION_SLOT #(
            .COUNT      (6),
            .USE_FF     (1)
        ) u_sltexp (
            .RESET_n    (rst_n),
            .CLK        (clk),
            .Primary    (Bus),
            .Secondary  (ExpBus),
            .WAIT_n     (boot_wait_n)
        );
        wire [7:0] sltexp_probe = u_sltexp.sltexp;
        if (MEMPW != 0) begin : g_mr
            TB_MEGARAM_MOCK u_mr (.RESET_n(rst_n), .CLK(clk), .Bus(ExpBus[0]));
        end
        else begin : g_nomr
            TB_BUS_DUMMY u_d0 (.Bus(ExpBus[0]));
        end
        // connect_dummy() sobre ExpBus[n] dentro de un generate no lo resuelve Verilator 5.020
        TB_BUS_DUMMY u_d1 (.Bus(ExpBus[1]));
        TB_BUS_DUMMY u_d2 (.Bus(ExpBus[2]));
        TB_BUS_DUMMY u_d3 (.Bus(ExpBus[3]));
        TB_BUS_DUMMY u_d4 (.Bus(ExpBus[4]));
        CARTRIDGE_V9990 #(.IO_BASE_ADDR(V99_BASE)) u_cart (
            .RESET_n    (rst_n),
            .CLK        (clk),
            .Bus        (ExpBus[5]),
            .Ram        (UmaRam[1]),
            .UmaClock   (Uma),
            .Video      (Video)
        );
    end
    else begin : g_top
        wire [7:0] sltexp_probe = 8'h00;
        CARTRIDGE_V9990 #(.IO_BASE_ADDR(V99_BASE)) u_cart (
            .RESET_n    (rst_n),
            .CLK        (clk),
            .Bus        (Bus),
            .Ram        (UmaRam[1]),
            .UmaClock   (Uma),
            .Video      (Video)
        );
    end

    // ------------------------------------------------------------------
    //  Placa: pines directos, multiplexor (3 x 74LVC245), datos, NPN
    // ------------------------------------------------------------------
    // Retardos de transporte con "always @(x) y <= #d x": con "assign #d" Verilator
    // 5.020 lanza un proceso retrasado por cada evaluacion del bloque
    // combinacional (no por cada cambio) y la simulacion se arrastra.
    reg cart_rd_r = 1'b1, cart_wr_r = 1'b1, cart_sltsl_r = 1'b1, cart_clock_r = 1'b0;
    always @(s_rd_n)    cart_rd_r    <= #(T_FPGA_IN) s_rd_n;
    always @(s_wr_n)    cart_wr_r    <= #(T_FPGA_IN) s_wr_n;
    always @(s_sltsl_n) cart_sltsl_r <= #(T_FPGA_IN) s_sltsl_n;
    always @(cart_clk)  cart_clock_r <= #(T_FPGA_IN) cart_clk;
    assign cart_rd_n    = cart_rd_r;
    assign cart_wr_n    = cart_wr_r;
    assign cart_sltsl_n = cart_sltsl_r;
    assign cart_clock   = cart_clock_r;

    // multiplexor: CART_MUX_CS_n llega al 74LVC245 T_FPGA_CO despues del flanco,
    // su salida da basura T_BUF_EN y luego el grupo nuevo; las entradas del slot
    // cruzan el buffer en T_BUF_PD y el pad de la FPGA en T_FPGA_IN
    reg  [2:0]  msel_a = 3'b110, msel_b = 3'b110;
    always @(cart_mux_cs_n) msel_a <= #(T_FPGA_CO) cart_mux_cs_n;
    always @(msel_a)        msel_b <= #(T_BUF_EN)  msel_a;
    reg  [15:0] a_b   = 16'hFFFF;
    reg  [7:0]  ctl_b = 8'hFF;
    wire [7:0]  ctl_s = {s_m1_n, s_cs12_n, s_rfsh_n, s_reset_n, s_cs2_n, s_cs1_n, s_iorq_n, s_mreq_n};
    always @(s_a)   a_b   <= #(T_BUF_PD) s_a;
    always @(ctl_s) ctl_b <= #(T_BUF_PD) ctl_s;
    reg  [7:0]  mux_val = 8'hFF;
    always @(msel_a or msel_b or a_b or ctl_b) begin
        if (msel_a != msel_b) mux_val = 8'($urandom);            // el buffer conmuta: basura
        else case (msel_b)
            3'b110:  mux_val = a_b[15:8];
            3'b101:  mux_val = a_b[7:0];
            3'b011:  mux_val = ctl_b;
            default: mux_val = 8'($urandom);
        endcase
    end
    reg  [7:0]  mux_pin = 8'hFF;
    always @(mux_val) mux_pin <= #(T_FPGA_IN) mux_val;
    assign cart_mux_sig = mux_pin;

    // datos: el valor que saca la FPGA se toma de Bus.DOUT (es lo que pone en
    // CART_DATA_SIG con CART_DATA_DIR = 0) para no cerrar un lazo por el inout
    reg        dir_d = 1'b1;
    always @(cart_data_dir) dir_d <= #(T_FPGA_CO + T_BUF_EN) cart_data_dir;
    reg  [7:0] fpga_d = 8'h00;
    always @(Bus.DOUT) fpga_d <= #(T_FPGA_CO + T_BUF_PD) Bus.DOUT;
    wire buf_drv = !dir_d;                                      // la placa conduce D0-D7 del slot
    wire [7:0] s_d = buf_drv ? fpga_d : (z_drv ? z_val : (m_drv ? m_val : 8'hFF));
    reg  [7:0] s_d_in = 8'hFF;
    always @(s_d) s_d_in <= #(T_BUF_PD + T_FPGA_IN) s_d;
    assign cart_data = cart_data_dir ? s_d_in : 8'bzzzz_zzzz;

    // NPN de /WAIT (colector abierto): entra T_NPN_ON despues, suelta T_NPN_OFF despues
    reg w_on_d = 1'b0, w_off_d = 1'b0, npn_w = 1'b0;
    always @(cart_wait_n) begin
        w_on_d  <= #(T_FPGA_CO + T_NPN_ON)  cart_wait_n;
        w_off_d <= #(T_FPGA_CO + T_NPN_OFF) cart_wait_n;
    end
    always @(posedge w_on_d) npn_w = 1'b1;
    always @(negedge w_off_d) if (!w_on_d) npn_w = 1'b0;

    // ------------------------------------------------------------------
    //  Sondas del DUT
    // ------------------------------------------------------------------
    wire       cart_csr_n = g_top.u_cart.CSR_n;
    wire       cart_csw_n = g_top.u_cart.CSW_n;
    wire [3:0] cart_mode  = g_top.u_cart.MODE;
    wire [7:0] cart_cdin  = g_top.u_cart.CD_IN;
    wire [7:0] cart_dout  = g_top.u_cart.dout;

    // ------------------------------------------------------------------
    //  Contadores y estadisticas
    // ------------------------------------------------------------------
    localparam int NCAT = 14;
    // 0 P#0 lect, 1 P#0 escr (OUT seguidos), 2 P#1 lect, 3 P#1 escr (OUT seguidos),
    // 4 P#2-6 lect, 5 P#2-7 escr, 6 otro puerto lect, 7 otro puerto escr,
    // 8 mem FFFFh lect, 9 mem FFFFh escr, 10 mem MegaRAM lect, 11 mem no servida,
    // 12 P#0 escr por OTIR, 13 P#1 escr por OTIR
    string cat_name [0:NCAT-1];
    int    st_n     [0:NCAT-1];
    int    st_bad   [0:NCAT-1];     // dato mal (lecturas) o no escrito (escrituras)
    int    st_unst  [0:NCAT-1];     // dato inestable en la ventana de setup
    int    st_wbud  [0:NCAT-1];     // /WAIT fuera de presupuesto (o sin /WAIT donde hacia falta)
    int    st_sv    [0:NCAT-1];     // /WAIT activado dentro del setup del Z80
    int    st_bn    [0:NCAT-1];     // accesos con rebote
    real   st_wpin  [0:NCAT-1];     // peor latencia /RD|/WR -> pin CART_WAIT_n (pad)
    real   st_wslot [0:NCAT-1];     // peor latencia /RD|/WR -> /WAIT en el slot
    int    st_tw    [0:NCAT-1];     // maximo de TW extra

    int n_dup = 0, n_lost = 0, n_badmode = 0, n_badwd = 0;
    int n_io_chk = 0, n_io_addr_bad = 0, n_iorq_mis = 0;
    int n_mem_chk = 0, n_mem_addr_bad = 0, n_merq_mis = 0;
    int n_fmem_chk = 0, n_fmem_addr_bad = 0, n_fmerq_mis = 0;
    int n_bad_drive = 0, n_conflict = 0, n_late_drive = 0;
    int n_hang = 0, n_setup_amb = 0;
    int n_tmo_spur = 0;
    int n_jump = 0, n_trig_ign = 0;
    int jump_hist [0:8];
    int revisit_max [0:2];
    int n_bounce = 0;
    int pw_lat_max = 0;             // ciclos /RD|/WR del pin -> pw_hold (accesos P#0/P#1)
    int pw_fires = 0;
    int wait_run_max = 0;           // ciclos seguidos con /WAIT activo (uso normal)
    int glitch_events = 0, glitch_wait = 0, glitch_drive = 0;
    int nodev_wait_max = 0;         // ciclos de la mayor rafaga de /WAIT sin nadie que conteste
    int guard_fail = 0;
    int int_ok = 0;
    real TZ = 279.365;
    real zt = 0.0;
    int  seed = 1, NACC = 120;
    bit  phase_normal = 1'b1;       // fase de uso normal (cuenta para el timeout y las rafagas)
    bit  bounce_cyc = 1'b0;
    int  bounce_kind = 0;           // 1 rebote de /RD o /WR, 2 de /IORQ
    int  bounce_bn = 0;
    real bounce_off = 0.0;
    int  bb_bad [0:2];              // P#0 con rebote: dato mal, por tipo de rebote
    int  bb_sv  [0:2];              // ciclos con rebote: /WAIT activado dentro del setup del Z80, por tipo
    bit  iorq_bounce_cyc = 1'b0;    // ciclo con rebote de IORQ (Bus.IORQ_n puede estar a 1 al llegar el RD/WR)
    bit  tb_go = 1'b0;              // arranque hecho (bus_ok a 1): antes no se cuentan eventos
    bit  expect_drive = 1'b1;       // DRIVE_EN = 1 y bus vivo: se espera /WAIT en P#0/P#1
    bit  mon_on = 1'b0;             // monitores de las fases (sin disable: Verilator no lo admite)

    // ------------------------------------------------------------------
    //  Ventanas de eventos: un evento (bajada de CSR_n/CSW_n en el cartucho)
    //  por ciclo de E/S a nuestros puertos, ninguno en los demas
    // ------------------------------------------------------------------
    int        exp_n = 0, got_n = 0;
    bit        exp_valid = 1'b0, exp_wr = 1'b0;
    reg [3:0]  exp_mode = 4'h0;
    reg [7:0]  exp_wd = 8'h00;
    reg [7:0]  ref_dout = 8'h00;
    task automatic win_next(input int nexp, input bit wr, input [3:0] mode, input [7:0] wd);
        if (exp_valid) begin
            if (got_n > exp_n) begin
                n_dup = n_dup + (got_n - exp_n);
                if (n_dup <= 6) $display("  [FAIL %0t] %0d evento(s) de mas en el ciclo anterior", $time, got_n - exp_n);
            end
            if (got_n < exp_n) begin
                n_lost = n_lost + (exp_n - got_n);
                if (n_lost <= 6) $display("  [FAIL %0t] evento perdido en el ciclo anterior", $time);
            end
        end
        exp_valid = 1'b1; exp_n = nexp; exp_wr = wr; exp_mode = mode; exp_wd = wd; got_n = 0;
    endtask

    reg csr_q = 1'b1, csw_q = 1'b1;
    int ref_cap = 0;
    always @(posedge clk) begin
        csr_q <= cart_csr_n;
        csw_q <= cart_csw_n;
        if (ref_cap == 1) ref_dout <= cart_dout;
        if (ref_cap > 0) ref_cap <= ref_cap - 1;
        if (tb_go && csr_q && !cart_csr_n) begin
            got_n = got_n + 1;
            if (exp_wr || cart_mode != exp_mode) begin
                n_badmode = n_badmode + 1;
                if (n_badmode <= 6) $display("  [FAIL %0t] lectura presentada al core con MODE=%0d (esperado %s P#%0d)", $time, cart_mode, exp_wr ? "escritura" : "lectura", exp_mode);
            end
            ref_cap <= 1;
        end
        if (tb_go && csw_q && !cart_csw_n) begin
            got_n = got_n + 1;
            if (!exp_wr || cart_mode != exp_mode) begin
                n_badmode = n_badmode + 1;
                if (n_badmode <= 6) $display("  [FAIL %0t] escritura presentada al core con MODE=%0d (esperado %s P#%0d)", $time, cart_mode, exp_wr ? "escritura" : "lectura", exp_mode);
            end
            else if (cart_cdin != exp_wd) begin
                n_badwd = n_badwd + 1;
                if (n_badwd <= 6) $display("  [FAIL %0t] dato de escritura al core %02h, esperado %02h (P#%0d)", $time, cart_cdin, exp_wd, exp_mode);
            end
        end
    end

    // ------------------------------------------------------------------
    //  Direccion que ve el dispositivo al llegarle el RD_n/WR_n retrasado
    // ------------------------------------------------------------------
    // Cada ciclo del Z80 arma una comprobacion (exp_armed) con su direccion;
    // la consume el primer RD_n/WR_n retrasado que baja en Bus (el de un
    // rebote no cuenta). Tipos: 1 E/S, 2 memoria de nuestra ranura, 3 memoria
    // ajena (M1 y lecturas/escrituras de la memoria del MSX): la direccion
    // que veria cualquier dispositivo de memoria del slot (la MegaRAM).
    reg [15:0] cur_a = 16'h0000;
    int        cur_kind = 0;            // 0 nada, 1 E/S, 2 nuestra memoria, 3 memoria ajena
    bit        exp_armed = 1'b0;
    reg [15:0] chk_a = 16'h0000;       // copia de cur_a/cur_kind para la comprobacion del ciclo
    int        chk_k = 0;
    bit        chk_bn = 1'b0;           // el ciclo lleva rebote (bounce_cyc ya se ha borrado cuando llega el retrasado de una escritura)
    reg brd_q = 1'b1, bwr_q = 1'b1;
    bit io_pw_cyc = 1'b0;               // el ciclo es de E/S a P#0/P#1 (para la latencia de la cadena)
    int chain_cnt = -1, chain_max = -1, chain_mem_max = -1, chain_kind = 0;
    bit dbg_chain = 1'b0;               // +DBGCHAIN: cada nuevo maximo de la cadena
    initial dbg_chain = $test$plusargs("DBGCHAIN");
    always @(posedge clk) begin
        brd_q <= Bus.RD_n;
        bwr_q <= Bus.WR_n;
        // latencia de la cadena en BOARD_REV1_BUS: si el RD_n/WR_n retrasado baja en
        // Bus en el flanco D, Bus.WAIT_n baja en el flanco D + n (aqui n = chain_cnt + 1,
        // porque este bloque ve los dos cambios un ciclo despues). El pre-WAIT no se
        // suelta por K mientras n <= PREWAIT_K (PREWAIT_MEM_K en memoria).
        if (chain_cnt >= 0) begin
            if (!Bus.WAIT_n) begin
                if (chain_kind == 1 && chain_cnt + 1 > chain_max && dbg_chain)
                    $display("  [cadena %0t] Bus.WAIT_n en D+%0d (A=%04h)", $time, chain_cnt + 1, chk_a);
                if (chain_kind == 1 && chain_cnt + 1 > chain_max)     chain_max = chain_cnt + 1;
                if (chain_kind == 2 && chain_cnt + 1 > chain_mem_max) chain_mem_max = chain_cnt + 1;
                chain_cnt = -1;
            end
            else if (chain_cnt > 40) chain_cnt = -1;
            else chain_cnt = chain_cnt + 1;
        end
        if (tb_go && exp_armed && ((brd_q && !Bus.RD_n) || (bwr_q && !Bus.WR_n))) begin
            exp_armed = 1'b0;
            if (chk_k == 1) begin
                n_io_chk = n_io_chk + 1;
                if (Bus.ADDR !== chk_a) begin
                    n_io_addr_bad = n_io_addr_bad + 1;
                    if (n_io_addr_bad <= 6) $display("  [FAIL %0t] E/S: Bus.ADDR=%04h al llegar el RD/WR retrasado, esperada %04h", $time, Bus.ADDR, chk_a);
                end
                if (Bus.IORQ_n !== 1'b0 && !iorq_bounce_cyc) begin
                    n_iorq_mis = n_iorq_mis + 1;
                    if (n_iorq_mis <= 6) $display("  [FAIL %0t] E/S: Bus.IORQ_n = 1 al llegar el RD/WR retrasado (A=%04h)", $time, chk_a);
                end
                if (io_pw_cyc && expect_drive && !chk_bn) begin chain_cnt = 0; chain_kind = 1; end
            end
            else if (chk_k == 2) begin
                n_mem_chk = n_mem_chk + 1;
                if (Bus.ADDR !== chk_a) n_mem_addr_bad = n_mem_addr_bad + 1;
                if (Bus.MERQ_n !== 1'b0) n_merq_mis = n_merq_mis + 1;
                if (MEMPW != 0 && chk_a[15:14] != 2'b00 && chk_a[15:14] != 2'b11 && !Bus.RD_n) begin chain_cnt = 0; chain_kind = 2; end
            end
            else if (chk_k == 3) begin
                n_fmem_chk = n_fmem_chk + 1;
                if (Bus.ADDR !== chk_a) begin
                    n_fmem_addr_bad = n_fmem_addr_bad + 1;
                    if (n_fmem_addr_bad <= 3 && TZ > 166.0) $display("  [FAIL %0t] memoria ajena: Bus.ADDR=%04h al llegar el RD/WR retrasado, esperada %04h", $time, Bus.ADDR, chk_a);
                end
                if (Bus.MERQ_n !== 1'b0) n_fmerq_mis = n_fmerq_mis + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    //  Escaner: saltos y revisitas
    // ------------------------------------------------------------------
    int last_pair [0:2];
    int cyc = 0;
    initial begin
        for (int i = 0; i < 9; i++) jump_hist[i] = 0;
        for (int g = 0; g < 3; g++) begin revisit_max[g] = 0; last_pair[g] = -1; end
    end
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (rst_n) begin
            if (u_bus.trig_ok) begin
                n_jump = n_jump + 1;
                jump_hist[u_bus.grp * 3 + u_bus.ph] = jump_hist[u_bus.grp * 3 + u_bus.ph] + 1;
            end
            if (u_bus.trig && !u_bus.trig_ok) n_trig_ign = n_trig_ign + 1;
            if (u_bus.ph == 2'd2 && u_bus.grp <= 2'd2) begin
                if (last_pair[u_bus.grp] >= 0 && cyc - last_pair[u_bus.grp] > revisit_max[u_bus.grp])
                    revisit_max[u_bus.grp] = cyc - last_pair[u_bus.grp];
                last_pair[u_bus.grp] = cyc;
            end
        end
    end

    // /WAIT: rafagas seguidas y timeout espurio
    int wrun = 0;
    always @(posedge clk) begin
        if (u_bus.wait_drv) wrun <= wrun + 1; else wrun <= 0;
        if (phase_normal && wrun > wait_run_max) wait_run_max = wrun;
        if (phase_normal && u_bus.wtmo_hit) n_tmo_spur = n_tmo_spur + 1;
    end

    // conduccion del bus de datos
    always @(buf_drv or z_drv or m_drv) if (buf_drv && (z_drv || m_drv)) n_conflict = n_conflict + 1;
    function automatic bit is_ours(input [7:0] port);
        is_ours = (port[7:4] == V99_BASE[7:4]);
    endfunction
    // el transceptor obedece a CART_DATA_DIR T_FPGA_IN + T_FPGA_CO + T_BUF_EN
    // despues de lo que ve el slot: la legitimidad se juzga con el slot de entonces
    localparam real T_DRV = T_FPGA_IN + T_FPGA_CO + T_BUF_EN;
    reg [15:0] s_a_dv = 16'hFFFF;
    reg s_rd_dv = 1'b1, s_iorq_dv = 1'b1, s_m1_dv = 1'b1, s_mreq_dv = 1'b1, s_sltsl_dv = 1'b1;
    always @(s_a)       s_a_dv     <= #(T_DRV) s_a;
    always @(s_rd_n)    s_rd_dv    <= #(T_DRV) s_rd_n;
    always @(s_iorq_n)  s_iorq_dv  <= #(T_DRV) s_iorq_n;
    always @(s_m1_n)    s_m1_dv    <= #(T_DRV) s_m1_n;
    always @(s_mreq_n)  s_mreq_dv  <= #(T_DRV) s_mreq_n;
    always @(s_sltsl_n) s_sltsl_dv <= #(T_DRV) s_sltsl_n;
    bit rd_ours = 1'b0, rd_ours_dv = 1'b0;      // el Z80 esta en una lectura de E/S de nuestros puertos
    always @(rd_ours) rd_ours_dv <= #(T_DRV) rd_ours;
    always @(posedge buf_drv) begin
        if (!( !s_rd_dv && (rd_ours_dv || (!s_iorq_dv && s_m1_dv && is_ours(s_a_dv[7:0])) || (!s_sltsl_dv && !s_mreq_dv)) )) begin
            n_bad_drive = n_bad_drive + 1;
            if (n_bad_drive <= 6) $display("  [FAIL %0t] la placa conduce D0-D7 sin lectura legitima: A=%04h iorq=%b rd=%b mreq=%b sltsl=%b", $time, s_a_dv, s_iorq_dv, s_rd_dv, s_mreq_dv, s_sltsl_dv);
        end
    end
    // tarde: sigue conduciendo 30 ns despues de que /RD suba y se quede arriba
    real t_rd_chg = 0.0;
    always @(s_rd_n) t_rd_chg = $realtime;
    always @(posedge s_rd_n) fork begin
        #30.0;
        if (buf_drv && s_rd_n && ($realtime - t_rd_chg) >= 29.999) begin
            n_late_drive = n_late_drive + 1;
            if (n_late_drive <= 6) $display("  [FAIL %0t] la placa sigue conduciendo D0-D7 30 ns despues de subir /RD", $time);
        end
    end join_none

    // latencias de /WAIT: primera subida del pin y entrada del NPN tras cada /RD|/WR
    real t_wpin = 0.0, t_wslot = 0.0, t_pw = 0.0;
    bit  wpin_seen = 1'b0, wslot_seen = 1'b0, pw_seen_tb = 1'b0;
    always @(posedge cart_wait_n) if (!wpin_seen) begin wpin_seen = 1'b1; t_wpin = $realtime; end
    always @(posedge npn_w)       if (!wslot_seen) begin wslot_seen = 1'b1; t_wslot = $realtime; end
    always @(posedge clk)         if (u_bus.pw_hold && !pw_seen_tb) begin pw_seen_tb = 1'b1; t_pw = $realtime; end

    // ------------------------------------------------------------------
    //  Z80
    // ------------------------------------------------------------------
    task automatic at(input real t);
        if (t > $realtime) #(t - $realtime);
    endtask

    task automatic addr_phase(input real t1, input [15:0] a, input int kind);
        fork
            begin
                at(t1 + T_AGL);
                s_a = 16'($urandom);
                at(t1 + T_AD);
                s_a = a;
                cur_a = a;
                cur_kind = kind;
                chk_a = a;
                chk_k = kind;
                chk_bn = bounce_cyc;
                exp_armed = (kind != 0);
            end
        join_none
    endtask

    // /WAIT en la bajada de TW (o T2): camino pesimista si cambia dentro del setup
    bit cyc_sv = 1'b0;
    task automatic wait_loop(inout real tf, output int ntw);
        bit we, wn;
        ntw = 0;
        forever begin
            at(tf - T_SU_W); we = npn_w;
            at(tf);          wn = npn_w;
            if (we != wn) begin
                if (wn) begin cyc_sv = 1'b1; wn = 1'b0; end     // activado dentro de tS(WAIT): el Z80 puede no verlo
                else n_setup_amb = n_setup_amb + 1;              // suelto dentro: camino corto
            end
            if (!wn) break;
            tf = tf + TZ;
            ntw = ntw + 1;
            if (ntw > 3000) begin
                n_hang = n_hang + 1;
                $display("  [FAIL %0t] Z80 retenido mas de 3000 TW", $time);
                break;
            end
        end
    endtask

    // ciclo de E/S (4 T + esperas)
    real t_stb = 0.0;
    bit  w_pin0 = 1'b0, w_slot0 = 1'b0;
    task automatic io_cycle(input bit wr, input [15:0] a, input [7:0] wd, output [7:0] rv, output int ntw,
                            input int bk, input int bn, input real boff);
        real t1, t2, tf, t3f, ts;
        reg [7:0] de;
        t1 = zt;
        at(t1);
        win_next(is_ours(a[7:0]) ? 1 : 0, wr, a[3:0] - V99_BASE[3:0], wd);
        cyc_sv = 1'b0;
        io_pw_cyc = is_ours(a[7:0]) && (a[3:1] == 3'b000);
        addr_phase(t1, a, 1);
        if (wr) fork begin at(t1 + TZ / 2.0 + T_DOUT); z_val = wd; z_drv = 1'b1; end join_none
        t2 = t1 + TZ;
        fork begin at(t2 + T_IORQ); s_iorq_n = 1'b0; end join_none
        ts = t2 + T_STB;
        t_stb = ts;
        fork
            begin
                at(ts);
                w_pin0 = cart_wait_n; w_slot0 = npn_w;
                wpin_seen = 1'b0; wslot_seen = 1'b0; pw_seen_tb = u_bus.pw_hold;
                if (wr) s_wr_n = 1'b0; else s_rd_n = 1'b0;
                if (!wr && is_ours(a[7:0])) rd_ours = 1'b1;
            end
        join_none
        iorq_bounce_cyc = (bk == 2);
        if (bk != 0) bounce(bk, bn, ts + boff, wr);
        tf = t2 + 1.5 * TZ;                 // bajada de TW*
        wait_loop(tf, ntw);
        t3f = tf + TZ;                      // bajada de T3
        rv = 8'hFF;
        if (!wr) begin
            at(t3f - T_SU_D); de = s_d;
            at(t3f);          rv = s_d;
            if (de !== rv && is_ours(a[7:0])) n_unst_last = 1; else n_unst_last = 0;
        end
        fork begin at(t3f + T_OFF); s_rd_n = 1'b1; s_wr_n = 1'b1; s_iorq_n = 1'b1; rd_ours = 1'b0; end join_none
        if (wr) fork begin at(t3f + T_OFF + T_DHLD); z_drv = 1'b0; end join_none
        zt = t3f + TZ / 2.0;
    endtask
    int n_unst_last = 0;

    // rebotes: 1 = RD/WR a 1 durante bn muestras; 2 = IORQ a 1 en bn muestras del grupo 2
    task automatic bounce(input int kind, input int bn, input real t0, input bit wr);
        fork
            begin
                at(t0);
                if (kind == 1) begin
                    @(posedge clk);
                    #(CLKP - T_FPGA_IN - 2.0);
                    if (wr) s_wr_n = 1'b1; else s_rd_n = 1'b1;
                    #(4.0 + (bn - 1) * CLKP);
                    if (wr) s_wr_n = 1'b0; else s_rd_n = 1'b0;
                end
                else begin
                    @(posedge clk); #0.1;
                    while (!(u_bus.grp == 2'd2 && u_bus.ph == 2'd1)) begin @(posedge clk); #0.1; end
                    s_iorq_n = 1'b1;
                    for (int i = 0; i < bn; i++) @(posedge clk);
                    #0.1;
                    s_iorq_n = 1'b0;
                end
                n_bounce = n_bounce + 1;
            end
        join_none
    endtask

    // M1 desde la memoria del MSX (no es nuestra ranura) + refresco
    task automatic z_m1(input [15:0] pc, input [7:0] op, input int extra_t);
        real t1, tf, t3r;
        int  ntw;
        t1 = zt;
        at(t1);
        win_next(0, 1'b0, 4'h0, 8'h00);
        addr_phase(t1, pc, 3);
        fork begin at(t1 + 80.0); s_m1_n = 1'b0; end join_none
        fork begin at(t1 + TZ / 2.0 + T_MREQ); s_mreq_n = 1'b0; end join_none
        fork begin at(t1 + TZ / 2.0 + T_STB); s_rd_n = 1'b0; end join_none
        fork begin at(t1 + TZ / 2.0 + T_STB + 60.0); m_val = op; m_drv = 1'b1; end join_none
        tf = t1 + 1.5 * TZ;                 // bajada de T2
        wait_loop(tf, ntw);
        t3r = tf + TZ / 2.0;                // subida de T3: el Z80 lee el opcode
        fork
            begin
                at(t3r + 20.0);  s_a = 16'($urandom); cur_kind = 0;
                at(t3r + T_OFF); s_mreq_n = 1'b1; s_rd_n = 1'b1; s_m1_n = 1'b1; s_rfsh_n = 1'b0; s_a = {8'h3F, 8'($urandom)};
                at(t3r + T_OFF + 20.0); m_drv = 1'b0;
                at(t3r + TZ / 2.0 + T_MREQ); s_mreq_n = 1'b0;          // MREQ del refresco
                at(t3r + 1.5 * TZ + T_MREQ); s_mreq_n = 1'b1;
                at(t3r + 2.0 * TZ + 20.0); s_rfsh_n = 1'b1;
            end
        join_none
        zt = t3r + (2.0 + extra_t) * TZ;
    endtask

    // lectura de memoria (3 T): ours = SLTSL de nuestra ranura (nadie del MSX conduce)
    task automatic z_mrd(input [15:0] a, input bit ours, input [7:0] md, output [7:0] got, output int ntw);
        real t1, tf, t3f, ts;
        t1 = zt;
        at(t1);
        win_next(0, 1'b0, 4'h0, 8'h00);
        cyc_sv = 1'b0;
        addr_phase(t1, a, ours ? 2 : 3);
        fork begin at(t1 + TZ / 2.0 + T_MREQ); s_mreq_n = 1'b0; end join_none
        ts = t1 + TZ / 2.0 + T_STB;
        t_stb = ts;
        fork
            begin
                at(ts);
                w_pin0 = cart_wait_n; w_slot0 = npn_w; wpin_seen = 1'b0; wslot_seen = 1'b0; pw_seen_tb = u_bus.pw_hold;
                s_rd_n = 1'b0;
            end
        join_none
        if (ours) fork begin at(t1 + TZ / 2.0 + T_SLT); s_sltsl_n = 1'b0; end join_none
        else      fork begin at(ts + 60.0); m_val = md; m_drv = 1'b1; end join_none
        tf = t1 + 1.5 * TZ;                 // bajada de T2
        wait_loop(tf, ntw);
        t3f = tf + TZ;
        at(t3f - T_SU_D); n_unst_last = 0; got = s_d;
        at(t3f);          if (got !== s_d) n_unst_last = 1; got = s_d;
        fork
            begin
                at(t3f + T_OFF); s_mreq_n = 1'b1; s_rd_n = 1'b1;
                at(t3f + T_OFF + 10.0); s_sltsl_n = 1'b1;
                at(t3f + T_OFF + 20.0); m_drv = 1'b0;
            end
        join_none
        zt = t3f + TZ / 2.0;
    endtask

    // escritura de memoria (3 T)
    task automatic z_mwr(input [15:0] a, input [7:0] d, input bit ours);
        real t1, tf, t3f;
        int  ntw;
        t1 = zt;
        at(t1);
        win_next(0, 1'b0, 4'h0, 8'h00);
        addr_phase(t1, a, ours ? 2 : 3);
        fork begin at(t1 + TZ / 2.0 + T_MREQ); s_mreq_n = 1'b0; end join_none
        if (ours) fork begin at(t1 + TZ / 2.0 + T_SLT); s_sltsl_n = 1'b0; end join_none
        fork begin at(t1 + TZ / 2.0 + T_DOUT); z_val = d; z_drv = 1'b1; end join_none
        fork begin at(t1 + 1.5 * TZ + T_STB); s_wr_n = 1'b0; end join_none
        tf = t1 + 1.5 * TZ;
        wait_loop(tf, ntw);
        t3f = tf + TZ;
        fork
            begin
                at(t3f + T_OFF); s_mreq_n = 1'b1; s_wr_n = 1'b1;
                at(t3f + T_OFF + 10.0); s_sltsl_n = 1'b1;
                at(t3f + T_OFF + T_DHLD); z_drv = 1'b0;
            end
        join_none
        zt = t3f + TZ / 2.0;
    endtask

    task automatic idle(input int nt);
        zt = zt + nt * TZ;
    endtask

    // el siguiente ciclo del Z80 empieza ahora, pero nunca antes de que acabe el
    // anterior (z_out vuelve en la bajada de TW, antes del fin de su ciclo)
    task automatic zt_now();
        if ($realtime + 10.0 > zt) zt = $realtime + 10.0;
    endtask

    // ------------------------------------------------------------------
    //  Instrucciones
    // ------------------------------------------------------------------
    reg [7:0]  areg = 8'h00;
    reg [15:0] pc   = 16'h8000;
    function automatic [7:0] P(input int n);
        P = V99_BASE + n[7:0];
    endfunction
    function automatic int cat_of(input [7:0] port, input bit wr);
        if (!is_ours(port)) cat_of = wr ? 7 : 6;
        else if (port[3:0] == 4'h0) cat_of = wr ? 1 : 0;
        else if (port[3:0] == 4'h1) cat_of = wr ? 3 : 2;
        else cat_of = wr ? 5 : 4;
    endfunction

    // anota latencias de /WAIT del ultimo ciclo en la categoria c
    real budget_w;
    task automatic note_wait(input int c, input int ntw, input bit need_wait);
        real lp, ls;
        lp = w_pin0  ? 0.0 : (wpin_seen  ? (t_wpin  - t_stb) + T_FPGA_CO : -1.0);
        ls = w_slot0 ? 0.0 : (wslot_seen ? (t_wslot - t_stb) : -1.0);
        if (lp > st_wpin[c])  st_wpin[c]  = lp;
        if (ls > st_wslot[c]) st_wslot[c] = ls;
        if (ntw > st_tw[c]) st_tw[c] = ntw;
        if (cyc_sv) begin
            if (bounce_cyc) begin
                bb_sv[bounce_kind] = bb_sv[bounce_kind] + 1;
                if (bb_sv[1] + bb_sv[2] <= 6) $display("  [rebote %0t] /WAIT activado dentro del setup del Z80 en un ciclo con rebote %s de %0d muestra(s) a %0.1f ns del strobe: /WAIT en el pin a %0.1f ns, en el slot a %0.1f ns",
                                                        $time, bounce_kind == 1 ? "de /RD-/WR" : "de /IORQ", bounce_bn, bounce_off, lp, ls);
            end
            else            st_sv[c] = st_sv[c] + 1;
        end
        if (!expect_drive) need_wait = 1'b0;
        if (need_wait && (ls < 0.0 || ls > budget_w || cyc_sv)) st_wbud[c] = st_wbud[c] + 1;
        if (bounce_cyc) st_bn[c] = st_bn[c] + 1;
        if (need_wait && pw_seen_tb && t_pw >= t_stb) begin
            if ((t_pw - t_stb) / CLKP > pw_lat_max) pw_lat_max = int'((t_pw - t_stb) / CLKP);
            pw_fires = pw_fires + 1;
        end
    endtask

    task automatic z_out(input [7:0] port, input [7:0] v, input int bk, input int bn, input real boff);
        reg [7:0] dmy;
        int ntw, c;
        areg = v;
        z_m1(pc, 8'hD3, 0);
        z_mrd(pc + 16'd1, 1'b0, port, dmy, ntw);
        pc = pc + 16'd2;
        bounce_cyc = (bk != 0);
        bounce_kind = bk;
        bounce_bn = bn;
        bounce_off = boff;
        io_cycle(1'b1, {v, port}, v, dmy, ntw, bk, bn, boff);
        c = cat_of(port, 1'b1);
        st_n[c] = st_n[c] + 1;
        note_wait(c, ntw, is_ours(port) && port[3:1] == 3'b000 && V99_BASE == 8'h60 && !bounce_cyc);
        bounce_cyc = 1'b0;
    endtask

    task automatic z_in(input [7:0] port, output [7:0] rv, input int bk, input int bn, input real boff);
        reg [7:0] dmy;
        int ntw, c;
        z_m1(pc, 8'hDB, 0);
        z_mrd(pc + 16'd1, 1'b0, port, dmy, ntw);
        pc = pc + 16'd2;
        bounce_cyc = (bk != 0);
        bounce_kind = bk;
        bounce_bn = bn;
        bounce_off = boff;
        io_cycle(1'b0, {areg, port}, 8'h00, rv, ntw, bk, bn, boff);
        areg = rv;
        c = cat_of(port, 1'b0);
        st_n[c] = st_n[c] + 1;
        if (n_unst_last) st_unst[c] = st_unst[c] + 1;
        note_wait(c, ntw, is_ours(port) && port[3:1] == 3'b000 && V99_BASE == 8'h60 && !bounce_cyc);
        bounce_cyc = 1'b0;
    endtask

    // un paso de OTIR (21 T): ED, B3 (5 T), lectura de (HL), salida, 5 T de repeticion
    task automatic z_otir_byte(input [7:0] port, input [7:0] v);
        reg [7:0] dmy;
        int ntw, c;
        z_m1(pc, 8'hED, 0);
        z_m1(pc + 16'd1, 8'hB3, 1);
        z_mrd(16'hC000 + {8'h00, v}, 1'b0, v, dmy, ntw);
        io_cycle(1'b1, {8'h10, port}, v, dmy, ntw, 0, 0, 0.0);
        c = cat_of(port, 1'b1);
        if (c == 1) c = 12;
        if (c == 3) c = 13;
        st_n[c] = st_n[c] + 1;
        note_wait(c, ntw, is_ours(port) && port[3:1] == 3'b000 && V99_BASE == 8'h60);
        idle(5);
    endtask

    task automatic wreg(input [5:0] n, input [7:0] v);
        z_out(P(4), {2'b00, n}, 0, 0, 0.0);
        z_out(P(3), v, 0, 0, 0.0);
    endtask
    task automatic rreg(input [5:0] n, output [7:0] v);
        z_out(P(4), {2'b01, n}, 0, 0, 0.0);
        z_in(P(3), v, 0, 0, 0.0);
    endtask
    task automatic set_vram_w(input [18:0] a);
        z_out(P(4), 8'h00, 0, 0, 0.0);
        z_out(P(3), a[7:0], 0, 0, 0.0);
        z_out(P(3), a[15:8], 0, 0, 0.0);
        z_out(P(3), {5'b00000, a[18:16]}, 0, 0, 0.0);
    endtask
    task automatic set_vram_r(input [18:0] a);
        z_out(P(4), 8'h03, 0, 0, 0.0);
        z_out(P(3), a[7:0], 0, 0, 0.0);
        z_out(P(3), a[15:8], 0, 0, 0.0);
        z_out(P(3), {5'b00000, a[18:16]}, 0, 0, 0.0);
    endtask

    // byte de la VRAM en la SDRAM de mentira (modo P1: 2*A[17:0] + A[18])
    function automatic [7:0] vram_peek(input [18:0] a);
        reg [18:0] b;
        reg [31:0] w;
        b = {a[17:0], a[18]};
        w = u_sdr.mem[b[18:2]];
        vram_peek = w[8 * b[1:0] +: 8];
    endfunction

    // margen de rebote: termina antes de la ventana del dato (sin esperas)
    function automatic real boff_rand();
        real span;
        span = 2.5 * TZ - T_STB - 80.0 - 40.0;
        if (span < 20.0) span = 20.0;
        boff_rand = 10.0 + ($urandom % 1000) * span / 1000.0;
    endfunction

    // ------------------------------------------------------------------
    //  Fases
    // ------------------------------------------------------------------
    reg [7:0] sh_vram [0:255];
    reg [7:0] rv, v, x;
    int  k, e, bad;
    reg [18:0] va;

    task automatic phase_regs();
        $display("-- fase R#16 por P#3/P#4 y lecturas de P#2/P#5/P#6 (%0.3f ms)", $realtime / 1.0e6);
        for (k = 0; k < NACC; k++) begin
            v = 8'($urandom);
            wreg(6'd16, v);
            rreg(6'd16, rv);
            if (g_top.u_cart.u_vdp.u_port.vdp_reg[16] !== v) st_bad[5] = st_bad[5] + 1;
            if (rv !== v) begin
                st_bad[4] = st_bad[4] + 1;
                if (st_bad[4] <= 4) $display("  [dato %0t] R#16 leido %02h, escrito %02h", $time, rv, v);
            end
        end
        for (k = 0; k < NACC; k++) begin
            e = 2 + ($urandom % 3);
            if (e == 4) e = 5;
            if (e == 3) e = 6;
            z_in(P(e), rv, 0, 0, 0.0);
            idle(2);
            if (rv !== ref_dout) begin
                st_bad[4] = st_bad[4] + 1;
                if (st_bad[4] <= 4) $display("  [dato %0t] P#%0d leido %02h, el core dio %02h", $time, e, rv, ref_dout);
            end
        end
    endtask

    task automatic phase_vram(input int otir);
        int nb;
        nb = (NACC > 255) ? 255 : NACC;
        $display("-- fase VRAM por P#0 (%s) (%0.3f ms)", otir ? "OTIR, 21 T por byte" : "OUT (n),A seguidos, 11 T por byte", $realtime / 1.0e6);
        va = 19'($urandom) & 19'h7FF00;
        set_vram_w(va);
        for (k = 0; k < nb; k++) begin
            sh_vram[k] = 8'($urandom);
            if (otir) z_otir_byte(P(0), sh_vram[k]);
            else      z_out(P(0), sh_vram[k], 0, 0, 0.0);
        end
        idle(20); at(zt);                     // que pase el tiempo: idle() solo mueve zt
        bad = 0;
        for (k = 0; k < nb; k++) if (vram_peek(va + k) !== sh_vram[k]) begin
            if (bad < 4) $display("  [escritura %0t] VRAM[%05h] (byte %0d de %0d) = %02h, escrito %02h", $time, va + k, k, nb, vram_peek(va + k), sh_vram[k]);
            bad++;
        end
        st_bad[otir ? 12 : 1] = st_bad[otir ? 12 : 1] + bad;
        if (bad) $display("  [escritura %0t] %0d de %0d bytes no llegaron a la VRAM (%s)", $time, bad, nb, otir ? "OTIR" : "OUT seguidos");
        set_vram_r(va);
        for (k = 0; k < nb; k++) begin
            z_in(P(0), rv, 0, 0, 0.0);
            if (rv !== vram_peek(va + k)) begin
                st_bad[0] = st_bad[0] + 1;
                if (st_bad[0] <= 4) $display("  [dato %0t] P#0 leido %02h, VRAM %02h", $time, rv, vram_peek(va + k));
            end
        end
    endtask

    task automatic phase_palette();
        reg [7:0] pr [0:63];
        reg [7:0] pg [0:63];
        $display("-- fase paleta por P#1 (G = B: el tiny9990 sin parches devuelve B al leer G) (%0.3f ms)", $realtime / 1.0e6);
        for (e = 0; e < 64; e++) begin
            pr[e] = {1'($urandom), 2'b00, 5'($urandom)};
            pg[e] = {3'b000, 5'($urandom)};
        end
        for (int pass = 0; pass < 2; pass++) begin
            if (pass == 1) for (e = 0; e < 64; e++) begin
                pr[e] = {1'($urandom), 2'b00, 5'($urandom)};
                pg[e] = {3'b000, 5'($urandom)};
            end
            wreg(6'd14, 8'h00);
            for (e = 0; e < 64; e++) begin
                if (pass == 0) begin           // OUT (n),A seguidos: 11 T
                    z_out(P(1), pr[e], 0, 0, 0.0);
                    z_out(P(1), pg[e], 0, 0, 0.0);
                    z_out(P(1), pg[e], 0, 0, 0.0);
                end
                else begin                     // OTIR: 21 T
                    z_otir_byte(P(1), pr[e]);
                    z_otir_byte(P(1), pg[e]);
                    z_otir_byte(P(1), pg[e]);
                end
            end
            idle(10); at(zt);
            bad = 0;
            for (e = 0; e < 64; e++) begin
                if (g_top.u_cart.u_vdp.u_pal.u_reg.dpb_r.mem[e][5:0] !== {pr[e][7], pr[e][4:0]}) bad++;
                if (g_top.u_cart.u_vdp.u_pal.u_reg.dpb_b.mem[e][5:0] !== {1'b0, pg[e][4:0]}) bad++;
            end
            st_bad[pass ? 13 : 3] = st_bad[pass ? 13 : 3] + bad;
            if (bad) $display("  [escritura %0t] %0d componentes de paleta mal escritos (%s)", $time, bad, pass ? "OTIR" : "OUT seguidos");
        end
        wreg(6'd14, 8'h00);
        for (e = 0; e < 64; e++) begin
            z_in(P(1), rv, 0, 0, 0.0); if (rv !== pr[e]) st_bad[2] = st_bad[2] + 1;
            z_in(P(1), rv, 0, 0, 0.0); if (rv !== pg[e]) st_bad[2] = st_bad[2] + 1;
            z_in(P(1), rv, 0, 0, 0.0); if (rv !== pg[e]) st_bad[2] = st_bad[2] + 1;
        end
    endtask

    task automatic phase_other();
        reg [7:0] ports [0:5];
        ports[0] = 8'h5F; ports[1] = V99_BASE ^ 8'h10; ports[2] = V99_BASE ^ 8'h1F;
        ports[3] = 8'h98; ports[4] = 8'h40; ports[5] = 8'hFF;
        $display("-- fase puertos ajenos y memoria ajena (%0.3f ms)", $realtime / 1.0e6);
        for (k = 0; k < NACC; k++) begin
            x = ports[$urandom % 6];
            if ($urandom % 2) z_out(x, 8'($urandom), 0, 0, 0.0);
            else begin
                z_in(x, rv, 0, 0, 0.0);
                if (rv !== 8'hFF) st_bad[6] = st_bad[6] + 1;
            end
            begin
                reg [7:0] d; int t;
                z_mrd(16'($urandom), 1'b0, 8'($urandom), d, t);
                z_mwr(16'($urandom), 8'($urandom), 1'b0);
            end
        end
    endtask

    task automatic phase_slotreg();
        int t;
        $display("-- fase registro de subranuras FFFFh (memoria de nuestra ranura) (%0.3f ms)", $realtime / 1.0e6);
        for (k = 0; k <= NACC / 4; k++) begin
            v = (k == NACC / 4) ? 8'h00 : 8'($urandom);    // al final, todas las paginas en la subranura 0
            z_m1(pc, 8'h32, 0); idle(6);       // LD (nn),A
            z_mwr(16'hFFFF, v, 1'b1);
            st_n[9] = st_n[9] + 1;
            z_m1(pc, 8'h3A, 0); idle(6);       // LD A,(nn)
            if (g_top.sltexp_probe !== v) begin
                st_bad[9] = st_bad[9] + 1;
                if (st_bad[9] <= 4) $display("  [escritura %0t] FFFFh = %02h, escrito %02h", $time, g_top.sltexp_probe, v);
            end
            z_mrd(16'hFFFF, 1'b1, 8'h00, rv, t);
            st_n[8] = st_n[8] + 1;
            if (rv !== ~v) begin
                st_bad[8] = st_bad[8] + 1;
                if (st_bad[8] <= 4) $display("  [dato %0t] FFFFh leido %02h, esperado %02h", $time, rv, ~v);
            end
            if (n_unst_last) st_unst[8] = st_unst[8] + 1;
        end
    endtask

    task automatic phase_bounce();
        int kind, bn, op;
        $display("-- fase rebotes de 1 y 2 muestras en RD/WR/IORQ (%0.3f ms)", $realtime / 1.0e6);
        for (k = 0; k < NACC; k++) begin
            kind = 1 + ($urandom % 2);
            bn   = 1 + ($urandom % 2);
            op   = $urandom % 4;
            v = 8'($urandom);
            case (op)
                0: begin       // R#16: escritura con rebote, lectura limpia
                    z_out(P(4), 8'h10, 0, 0, 0.0);
                    z_out(P(3), v, kind, bn, boff_rand());
                    rreg(6'd16, rv); if (rv !== v) st_bad[4] = st_bad[4] + 1;
                    if (g_top.u_cart.u_vdp.u_port.vdp_reg[16] !== v) st_bad[5] = st_bad[5] + 1;
                end
                1: begin       // R#16: lectura con rebote
                    wreg(6'd16, v);
                    z_out(P(4), 8'h50, 0, 0, 0.0);
                    z_in(P(3), rv, kind, bn, boff_rand());
                    if (rv !== v) begin
                        st_bad[4] = st_bad[4] + 1;
                        if (st_bad[4] <= 4) $display("  [dato %0t] R#16 con rebote %0d/%0d leido %02h, escrito %02h", $time, kind, bn, rv, v);
                    end
                end
                2: begin       // P#0: escritura con rebote y lectura con rebote
                    va = 19'($urandom);
                    set_vram_w(va);
                    z_out(P(0), v, kind, bn, boff_rand());
                    idle(10); at(zt);
                    if (vram_peek(va) !== v) begin
                        bb_bad[kind] = bb_bad[kind] + 1;
                        if (bb_bad[1] + bb_bad[2] <= 6) $display("  [rebote %0t] P#0 escritura con rebote %s de %0d muestra(s): VRAM %02h, escrito %02h", $time, kind == 1 ? "de /WR" : "de /IORQ", bn, vram_peek(va), v);
                    end
                    set_vram_r(va);
                    z_in(P(0), rv, kind, bn, boff_rand());
                    if (rv !== v) begin
                        bb_bad[kind] = bb_bad[kind] + 1;
                        if (bb_bad[1] + bb_bad[2] <= 6) $display("  [rebote %0t] P#0 lectura con rebote %s de %0d muestra(s): leido %02h, VRAM %02h; /WAIT en el pin a %0.1f ns", $time, kind == 1 ? "de /RD" : "de /IORQ", bn, rv, v, wpin_seen ? (t_wpin - t_stb) + T_FPGA_CO : -1.0);
                    end
                end
                default: begin // P#5 con rebote
                    z_in(P(5), rv, kind, bn, boff_rand());
                    idle(2);
                    if (rv !== ref_dout) st_bad[4] = st_bad[4] + 1;
                end
            endcase
        end
    endtask

    // RD de 1 y 2 muestras sin ciclo de E/S (IORQ alto), con 60h en el bus de direcciones
    task automatic phase_rd_glitch();
        int ev0, w0;
        $display("-- fase RD de 1-2 muestras sin ciclo de E/S (%0.3f ms)", $realtime / 1.0e6);
        for (k = 0; k < NACC / 2; k++) begin
            at(zt);
            while (u_bus.wait_req || !Bus.WAIT_n) @(posedge clk);
            win_next(0, 1'b0, 4'h0, 8'h00);
            s_a = {8'($urandom), V99_BASE};
            cur_kind = 0;
            wpin_seen = 1'b0;
            #(100.0 + ($urandom % 100));
            @(posedge clk);
            #(CLKP - T_FPGA_IN - 2.0);
            if (k % 2) s_wr_n = 1'b0; else s_rd_n = 1'b0;
            #(4.0 + (k % 4 >= 2 ? CLKP : 0.0));
            s_rd_n = 1'b1; s_wr_n = 1'b1;
            #400.0;
            if (wpin_seen || cart_wait_n) glitch_wait = glitch_wait + 1;
            zt_now();
        end
        win_next(0, 1'b0, 4'h0, 8'h00);
        glitch_events = n_dup;
    endtask

    // nadie en 60h/61h (V99_BASE = 70h): el pre-WAIT se suelta por K o por RD/WR a 1
    task automatic phase_nodev();
        int c0, wmax, run;
        $display("-- fase pre-WAIT sin dispositivo en 60h/61h (%0.3f ms)", $realtime / 1.0e6);
        for (k = 0; k < NACC / 2; k++) begin
            run = 0;
            mon_on = 1'b1;
            fork
                while (mon_on) begin @(posedge clk); if (mon_on && cart_wait_n) run = run + 1; end
            join_none
            if (k % 2) z_out(8'h60 + (k % 4 == 1), 8'($urandom), 0, 0, 0.0);
            else begin z_in(8'h60 + (k % 4 == 2), rv, 0, 0, 0.0); if (rv !== 8'hFF) st_bad[6] = st_bad[6] + 1; end
            mon_on = 1'b0; @(posedge clk); @(posedge clk);
            if (run > nodev_wait_max) nodev_wait_max = run;
        end
        // ciclo cortado: /IORQ y /RD de 6 muestras en 60h -> se suelta por RD a 1
        for (k = 0; k < 8; k++) begin
            run = 0;
            at(zt);
            win_next(0, 1'b0, 4'h0, 8'h00);
            s_a = 16'h0060; cur_kind = 0;
            #120.0;
            s_iorq_n = 1'b0; s_rd_n = 1'b0;
            mon_on = 1'b1;
            fork
                while (mon_on) begin @(posedge clk); if (mon_on && cart_wait_n) run = run + 1; end
            join_none
            #(6.0 * CLKP);
            s_rd_n = 1'b1;
            #30.0; s_iorq_n = 1'b1;
            #600.0;
            mon_on = 1'b0; @(posedge clk); @(posedge clk);
            if (run > nodev_wait_max) nodev_wait_max = run;
            zt_now();
        end
        win_next(0, 1'b0, 4'h0, 8'h00);
    endtask

    // MegaRAM de mentira en la subranura 0 con PREWAIT_MEM_EN
    task automatic phase_megaram();
        int t;
        reg [15:0] a;
        $display("-- fase pre-WAIT de memoria (MegaRAM de mentira) (%0.3f ms)", $realtime / 1.0e6);
        for (k = 0; k < NACC; k++) begin
            a = 16'h4000 + (16'($urandom) & 16'h7FFF);
            cyc_sv = 1'b0;
            z_mrd(a, 1'b1, 8'h00, rv, t);
            st_n[10] = st_n[10] + 1;
            if (rv !== (a[7:0] ^ a[15:8] ^ 8'h5A)) st_bad[10] = st_bad[10] + 1;
            if (n_unst_last) st_unst[10] = st_unst[10] + 1;
            budget_w = TZ - T_STB - T_SU_W;      // memoria: /WAIT en la bajada de T2
            note_wait(10, t, 1'b1);
            budget_w = 1.5 * TZ - 145.0;
            idle(1);
            a = 16'($urandom) & 16'h3FFF;        // pagina 0: la MegaRAM no contesta
            z_mrd(a, 1'b1, 8'h00, rv, t);
            st_n[11] = st_n[11] + 1;
            note_wait(11, t, 1'b0);
            if (rv !== 8'hFF) st_bad[11] = st_bad[11] + 1;
            idle(1);
        end
    endtask

    // /INT del V9990 (linea) y guardias de salida
    task automatic phase_int_guards();
        int  ln, tmo;
        $display("-- fase /INT y guardias (DRIVE_EN, BOOT_HOLD, /RESET del slot, reloj del slot) (%0.3f ms)", $realtime / 1.0e6);
        phase_normal = 1'b0;
        ln = g_top.u_cart.u_vdp.u_tg.disp_line + 3;
        wreg(6'd10, 8'(ln));
        wreg(6'd11, {6'b000000, 2'(ln >> 8)});
        wreg(6'd12, 8'h00);
        wreg(6'd9, 8'h02);                       // IEH
        tmo = 0;
        while (Bus.INT_n !== 1'b0 && tmo < 400) begin #1000.0; tmo++; end
        zt_now();
        if (Bus.INT_n !== 1'b0) begin guard_fail++; $display("  [FAIL %0t] el V9990 no levanto /INT", $time); end
        else begin
            #50.0;
            if (cart_int_n !== 1'b1) begin guard_fail++; $display("  [FAIL] /INT no sale al slot"); end
            else int_ok++;
            drive_en = 1'b0; #1.0;
            if (cart_int_n !== 1'b0) begin guard_fail++; $display("  [FAIL] /INT sale con DRIVE_EN = 0"); end
            drive_en = 1'b1; #1.0;
            if (cart_int_n !== 1'b1) begin guard_fail++; $display("  [FAIL] /INT no vuelve con DRIVE_EN = 1"); end
            zt_now();
            z_out(P(6), 8'h02, 0, 0, 0.0);       // borra HI
            idle(4); at(zt);
            if (cart_int_n !== 1'b0) begin guard_fail++; $display("  [FAIL] /INT no se suelta al borrar HI"); end
            wreg(6'd9, 8'h00);
        end
        // DRIVE_EN = 0: ni datos ni /WAIT, pero los eventos siguen llegando al core
        drive_en = 1'b0;
        expect_drive = 1'b0;
        begin
            int d0, w0;
            d0 = 0; w0 = 0;
            mon_on = 1'b1;
            fork
                while (mon_on) begin @(posedge clk); if (mon_on && buf_drv) d0++; if (mon_on && (cart_wait_n || npn_w)) w0++; end
            join_none
            wreg(6'd16, 8'hA5);
            rreg(6'd16, rv);
            set_vram_r(19'h00100);
            z_in(P(0), x, 0, 0, 0.0);
            mon_on = 1'b0; @(posedge clk); @(posedge clk);
            if (d0 != 0 || w0 != 0 || rv !== 8'hFF || x !== 8'hFF) begin
                guard_fail++;
                $display("  [FAIL] con DRIVE_EN = 0: %0d ciclos conduciendo datos, %0d con /WAIT, R#16 leido %02h, P#0 %02h", d0, w0, rv, x);
            end
            if (g_top.u_cart.u_vdp.u_port.vdp_reg[16] !== 8'hA5) begin guard_fail++; $display("  [FAIL] con DRIVE_EN = 0 la escritura no llego al core"); end
        end
        expect_drive = 1'b1;
        // BOOT_HOLD retiene aunque DRIVE_EN = 0 (antes, que la cadena acabe el P#0 de arriba)
        while (u_bus.wait_req) @(posedge clk);
        #1.0;
        if (cart_wait_n !== 1'b0) begin guard_fail++; $display("  [FAIL] /WAIT con DRIVE_EN = 0"); end
        boot_hold = 1'b1; #1.0;
        if (cart_wait_n !== 1'b1) begin guard_fail++; $display("  [FAIL] BOOT_HOLD no activa /WAIT"); end
        boot_hold = 1'b0; drive_en = 1'b1; #1.0;
        if (cart_wait_n !== 1'b0) begin guard_fail++; $display("  [FAIL] /WAIT activo tras soltar BOOT_HOLD"); end
        // /RESET del slot: bus_ok cae
        #2000.0;
        s_reset_n = 1'b0;
        #3000.0;
        if (bus_ok_o !== 1'b0 || cart_data_dir !== 1'b1 || cart_busdir_n !== 1'b1 || cart_wait_n !== 1'b0 || cart_int_n !== 1'b0) begin
            guard_fail++; $display("  [FAIL] con /RESET del slot: bus_ok=%b dir=%b busdir=%b wait=%b int=%b", bus_ok_o, cart_data_dir, cart_busdir_n, cart_wait_n, cart_int_n);
        end
        s_reset_n = 1'b1;
        #3000.0;
        if (bus_ok_o !== 1'b1) begin guard_fail++; $display("  [FAIL] bus_ok no vuelve tras soltar /RESET"); end
        // reloj del slot parado: bus_ok cae en dos ventanas como mucho
        cart_clk_run = 1'b0;
        tmo = 0;
        while (bus_ok_o && tmo < 6000) begin #1000.0; tmo++; end
        if (bus_ok_o) begin guard_fail++; $display("  [FAIL] bus_ok no cae con el reloj del slot parado"); end
        else $display("   bus_ok cae %0d us despues de parar el reloj del slot", tmo);
        zt_now();
        z_in(P(3), rv, 0, 0, 0.0);
        if (rv !== 8'hFF) begin guard_fail++; $display("  [FAIL] lectura conducida con el reloj del slot parado"); end
        cart_clk_run = 1'b1;
        tmo = 0;
        while (!bus_ok_o && tmo < 6000) begin #1000.0; tmo++; end
        if (!bus_ok_o) begin guard_fail++; $display("  [FAIL] bus_ok no vuelve con el reloj"); end
        zt_now();
    endtask

    // timeout fail-open: la cadena retiene /WAIT. Primero 60 us con BOOT_HOLD a 1
    // (la retencion de arranque: /WAIT todo el rato y sin WAIT_TIMEOUT), despues
    // sin BOOT_HOLD: el pin se suelta a los 2^12 ciclos y WAIT_TIMEOUT sube.
    int tmo_ok = 0, boot_ok = 0;
    task automatic phase_timeout();
        real t0;
        int  drop;
        $display("-- fase timeout fail-open (%0.3f ms)", $realtime / 1.0e6);
        at(zt);
        if (wait_timeout !== 1'b0) begin $display("  [FAIL] WAIT_TIMEOUT ya estaba a 1 antes de la prueba"); n_tmo_spur++; end
        boot_hold = 1'b1;
        force Bus.WAIT_n = 1'b0;
        drop = 0;
        mon_on = 1'b1;
        fork
            while (mon_on) begin @(posedge clk); if (mon_on && !cart_wait_n) drop++; end
        join_none
        #60000.0;
        mon_on = 1'b0; @(posedge clk); @(posedge clk);
        $display("   con BOOT_HOLD y la cadena en espera 60 us: %0d ciclos sin /WAIT, WAIT_TIMEOUT = %b", drop, wait_timeout);
        if (drop == 0 && wait_timeout === 1'b0) boot_ok = 1;
        boot_hold = 1'b0;
        #100.0;
        t0 = $realtime;
        if (cart_wait_n !== 1'b1) $display("  [FAIL] /WAIT no sale con la cadena en espera");
        while (cart_wait_n && $realtime - t0 < 80000.0) #10.0;
        #(3.0 * CLKP);                       // WAIT_TIMEOUT es un registro: un ciclo despues del corte
        $display("   sin BOOT_HOLD: /WAIT suelto por timeout tras %0.1f us; WAIT_TIMEOUT = %b", ($realtime - t0 + 100.0) / 1000.0, wait_timeout);
        if (!cart_wait_n && wait_timeout && ($realtime - t0 + 100.0) < 39000.0 && ($realtime - t0 + 100.0) > 37000.0) tmo_ok = 1;
        release Bus.WAIT_n;
        #1000.0;
        zt_now();
    endtask

    // ------------------------------------------------------------------
    //  Programa
    // ------------------------------------------------------------------
    int hz = 3579545;
    real mhz;
    initial begin
        if (!$value$plusargs("HZ=%d", hz)) hz = 3579545;
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("N=%d", NACC)) NACC = 120;
        void'($urandom(seed));
        TZ = 1.0e9 / hz;
        mhz = hz / 1.0e6;
        budget_w = 1.5 * TZ - 145.0;
        cat_name[0] = "P#0 lectura"; cat_name[1] = "P#0 escritura"; cat_name[2] = "P#1 lectura"; cat_name[3] = "P#1 escritura";
        cat_name[4] = "P#2-6 lectura"; cat_name[5] = "P#2-7 escritura"; cat_name[6] = "ajeno lectura"; cat_name[7] = "ajeno escritura";
        cat_name[8] = "FFFFh lectura"; cat_name[9] = "FFFFh escritura"; cat_name[10] = "MegaRAM lectura"; cat_name[11] = "memoria sin servir";
        cat_name[12] = "P#0 escr. OTIR"; cat_name[13] = "P#1 escr. OTIR";
        for (int c = 0; c < NCAT; c++) begin
            st_n[c] = 0; st_bad[c] = 0; st_unst[c] = 0; st_wbud[c] = 0; st_sv[c] = 0; st_bn[c] = 0;
            st_wpin[c] = -1.0; st_wslot[c] = -1.0; st_tw[c] = 0;
        end
        for (int i = 0; i < 3; i++) begin bb_bad[i] = 0; bb_sv[i] = 0; end
        $display("== tb_bus: TOPO=%0d (%s) V99_BASE=%02h MEMPW=%0d Z80 a %0.3f MHz (T = %0.1f ns) SEED=%0d N=%0d",
                 TOPO, TOPO == 0 ? "con EXPANSION_SLOT" : "sin EXPANSION_SLOT", V99_BASE, MEMPW, mhz, TZ, seed, NACC);
        $display("   BOARD_REV1_BUS: ADAPTIVE_SCAN=%0d PREWAIT_IO_EN=%0d ADDR_HOLD=%0d DRIVE_TAIL_GUARD=%0d PREWAIT_K=%0d PREWAIT_MEM_K=%0d",
                 SCAN, PWIO, AHOLD, TAILG, PW_K, PW_MEM_K);
        $display("   presupuestos: /WAIT 1,5 T - 145 = %0.0f ns, dato de E/S 2,5 T - 125 = %0.0f ns", budget_w, 2.5 * TZ - 125.0);

        #50.0 rst_n = 1'b1;
        #2000.0 s_reset_n = 1'b1;
        while (!bus_ok_o) #1000.0;
        $display("   bus_ok a 1 en %0.3f ms", $realtime / 1.0e6);
        tb_go = 1'b1;
        zt = $realtime + 100.0;

        // V9990 en P1 con la pantalla encendida (la VRAM mas ocupada para la CPU)
        wreg(6'd6, 8'h00);
        wreg(6'd7, 8'h00);
        wreg(6'd8, 8'h80);

        if (V99_BASE == 8'h60) begin
            phase_regs();
            phase_vram(0);
            phase_vram(1);
            phase_palette();
            phase_other();
            if (TOPO == 0) phase_slotreg();
            phase_bounce();
            phase_rd_glitch();
            if (MEMPW != 0) phase_megaram();
        end
        else begin
            phase_nodev();
            phase_other();
        end
        win_next(0, 1'b0, 4'h0, 8'h00);
        if (V99_BASE == 8'h60) phase_int_guards();
        phase_normal = 1'b0;
        phase_timeout();
        win_next(0, 1'b0, 4'h0, 8'h00);
        report();
        $finish;
    end

    initial begin
        #400.0e6;
        $display("TB_TIMEOUT");
        $finish;
    end
    // latido para seguir el avance: +HB=<us>
    initial begin
        int hb;
        if ($value$plusargs("HB=%d", hb)) forever begin
            #(hb * 1000.0);
            $display("   [latido %0.1f us]", $realtime / 1000.0);
            $fflush;
        end
    end

    // ------------------------------------------------------------------
    //  Informe y veredicto
    // ------------------------------------------------------------------
    task automatic report();
        int fail, expd, slow;
        string s;
        fail = 0; expd = 0;
        slow = (hz > 6000000) ? ((hz > 9000000) ? 2 : 1) : 0;   // 0: 3,58/5,37; 1: 7,16; 2: 10,74
        $display("");
        $display("   categoria            accesos  dato_mal inestab  rebote  W>pres  W_setup  W_pin(ns) W_slot(ns) TW_max");
        for (int c = 0; c < NCAT; c++) if (st_n[c] > 0)
            $display("   %-18s %8d %9d %7d %7d %7d %8d %10.1f %10.1f %6d", cat_name[c], st_n[c], st_bad[c], st_unst[c], st_bn[c], st_wbud[c], st_sv[c], st_wpin[c], st_wslot[c], st_tw[c]);
        $display("   eventos: duplicados %0d, perdidos %0d, MODE/tipo mal %0d, dato de escritura mal %0d", n_dup, n_lost, n_badmode, n_badwd);
        $display("   direccion al llegar el RD/WR retrasado: E/S %0d comprobadas, %0d mal, IORQ sin alinear %0d; memoria %0d, %0d mal, MERQ sin alinear %0d",
                 n_io_chk, n_io_addr_bad, n_iorq_mis, n_mem_chk, n_mem_addr_bad, n_merq_mis);
        $display("   direccion en memoria ajena (M1 y memoria del MSX): %0d comprobadas, %0d mal, MERQ sin alinear %0d",
                 n_fmem_chk, n_fmem_addr_bad, n_fmerq_mis);
        $display("   cadena (RD/WR retrasado en Bus en el flanco D -> Bus.WAIT_n): E/S P#0/P#1 en D+%0d (PREWAIT_K = %0d), lectura de la MegaRAM en D+%0d (PREWAIT_MEM_K = %0d)",
                 chain_max, PW_K, chain_mem_max, PW_MEM_K);
        $display("   saltos %0d (ignorados por la retencion %0d); por estado (g,f): 0,0=%0d 0,1=%0d 0,2=%0d 1,0=%0d 1,1=%0d 1,2=%0d 2,0=%0d 2,1=%0d 2,2=%0d",
                 n_jump, n_trig_ign, jump_hist[0], jump_hist[1], jump_hist[2], jump_hist[3], jump_hist[4], jump_hist[5], jump_hist[6], jump_hist[7], jump_hist[8]);
        $display("   revisita maxima (ciclos entre parejas): g0 %0d, g1 %0d, g2 %0d", revisit_max[0], revisit_max[1], revisit_max[2]);
        $display("   pre-WAIT: %0d disparos en P#0/P#1, peor /RD|/WR -> pw_hold %0d ciclos; /WAIT seguido maximo en uso normal %0d ciclos",
                 pw_fires, pw_lat_max, wait_run_max);
        $display("   ciclos con rebote: P#0 con dato mal / /WAIT dentro del setup del Z80: rebote de /RD o /WR %0d / %0d, de /IORQ %0d / %0d",
                 bb_bad[1], bb_sv[1], bb_bad[2], bb_sv[2]);
        $display("   rebotes inyectados %0d; RD/WR sin E/S: %0d con /WAIT; sin dispositivo: rafaga maxima de /WAIT %0d ciclos",
                 n_bounce, glitch_wait, nodev_wait_max);
        $display("   conduccion: sin lectura legitima %0d, tarde %0d, choques %0d; Z80 colgado %0d; /WAIT soltado dentro del setup %0d (informativo)",
                 n_bad_drive, n_late_drive, n_conflict, n_hang, n_setup_amb);
        $display("   timeout espurio %0d; timeout forzado %s; BOOT_HOLD sin timeout %s; guardias %s; /INT %s",
                 n_tmo_spur, tmo_ok ? "ok" : "MAL", boot_ok ? "ok" : "MAL", guard_fail == 0 ? "ok" : "MAL", (V99_BASE != 8'h60) ? "-" : (int_ok ? "ok" : "MAL"));

        // siempre: eventos, direccion de E/S, conduccion, timeout
        if (n_dup || n_lost || n_badmode || n_badwd || n_io_addr_bad || n_iorq_mis) fail++;
        if (n_bad_drive || n_late_drive || n_conflict || n_hang || n_tmo_spur || !tmo_ok || !boot_ok || guard_fail) fail++;
        // la cadena tiene que bajar su WAIT_n antes de que el pre-WAIT se suelte por K
        if (V99_BASE == 8'h60 && (chain_max < 0 || chain_max > PW_K)) fail++;
        if (MEMPW != 0 && (chain_mem_max < 0 || chain_mem_max > PW_MEM_K)) fail++;
        if (glitch_wait) fail++;
        if (V99_BASE != 8'h60 && (nodev_wait_max == 0 || nodev_wait_max > 40)) fail++;
        if (V99_BASE == 8'h60 && !int_ok) fail++;
        // a cualquier velocidad: escrituras de registro (P#3/P#4/P#6), escrituras por
        // OTIR a P#0/P#1 (21 T entre bytes: mas de los 1,62 us de la espera mas
        // larga del V9990) y los puertos ajenos, que no se tocan
        if (st_bad[5] || st_bad[12] || st_bad[13] || st_bad[6] || st_bad[7]) fail++;
        if (slow == 0) begin
            // 3,58 y 5,37: todo lo de E/S y el registro FFFFh (la MegaRAM, abajo)
            for (int c = 0; c < 10; c++) if (st_bad[c] || st_unst[c] || st_wbud[c] || st_sv[c]) fail++;
            for (int c = 12; c < NCAT; c++) if (st_bad[c] || st_unst[c] || st_wbud[c] || st_sv[c]) fail++;
            if (n_mem_addr_bad || n_merq_mis || n_fmem_addr_bad || n_fmerq_mis) fail++;
            // rebotes de /RD o /WR: nada cambia; de /IORQ en la visita rapida: el
            // pre-WAIT espera una vuelta (9 ciclos): a 3,58 cabe, a 5,37 no
            if (bb_bad[1] || bb_sv[1]) fail++;
            if (hz < 4000000 && (bb_bad[2] || bb_sv[2])) fail++;
            if (hz >= 4000000 && (bb_bad[2] || bb_sv[2])) expd++;
        end
        else begin
            if (bb_bad[1] || bb_sv[1] || bb_bad[2] || bb_sv[2]) expd++;
            if (slow == 1) begin
                // 7,16: lecturas de P#2-6 dentro de los 224 ns de 2,5 T - 125
                if (st_bad[4] || st_unst[4]) fail++;
            end
            // fallos esperados: /WAIT fuera de presupuesto (65 ns a 7,16, -5 a 10,74),
            // y con el las lecturas de P#0/P#1 y las escrituras seguidas (< 1,62 us)
            if (st_bad[0] || st_wbud[0] || st_sv[0] || st_bad[1] || st_wbud[1] || st_sv[1]) expd++;
            if (st_bad[2] || st_wbud[2] || st_sv[2] || st_bad[3] || st_wbud[3] || st_sv[3]) expd++;
            // memoria de nuestra ranura a 7,16 o mas: la direccion de un ciclo de memoria
            // es valida solo T/2 + 75 - 110 ns antes de /RD (35 ns a 7,16)
            if (st_bad[8] || st_bad[9] || st_unst[8] || n_mem_addr_bad || n_fmem_addr_bad || n_fmerq_mis) expd++;
            if (slow == 2 && (st_bad[4] || st_unst[4])) expd++;
        end
        if (MEMPW != 0 && slow == 0 && hz < 4000000 && (st_bad[10] || st_wbud[10] || st_bad[11])) fail++;
        $display("");
        if (fail == 0) $display("BUS_OK%s", expd ? " (con los fallos esperados de esta velocidad, ver la tabla)" : "");
        else           $display("BUS_FAIL (%0d criterios)", fail);
    endtask
endmodule

// subranura vacia (lo que hace connect_dummy)
module TB_BUS_DUMMY (BUS_IF.CARTRIDGE Bus);
    assign Bus.DOUT     = 8'h00;
    assign Bus.BUSDIR_n = 1'b1;
    assign Bus.INT_n    = 1'b1;
    assign Bus.WAIT_n   = 1'b1;
endmodule
`default_nettype wire
