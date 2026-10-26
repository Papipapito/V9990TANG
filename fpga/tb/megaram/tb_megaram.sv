//
// tb_megaram.sv -- banco del camino megaROM de V9990TANG (hito 8)
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito.
//
// Cadena simulada (todo RTL del repo salvo los modelos marcados):
//
//   Z80 a nivel de pines (modelo)          -> BOARD_REV1_BUS de main (filtros,
//   mux de 9 estados, linea de 9 de RD/WR)  -> EXPANSION_SLOT (subslot 0)
//   -> CARTRIDGE_MEGAROM (configure + controller + SCC) -> EXPANSION_RAM
//   (canal 0, con MEGAROM_CLEAR en el puerto 1) -> UMA (DIV 30, libre) ->
//   SDRAM_IF_MODEL (modelo de ciclo del lado RAM_IF de sdram.sv); en el
//   canal 1 un cliente de VRAM (modelo) lee en todas sus ranuras como un
//   V9990 a plena carga y comprueba dato y plazo (ranura perdida = error).
//
// Parametros (Verilator -G):
//   MEM_WAIT  1/0  ENABLE_MEM_WAIT de la megaROM
//   PREWAIT   1/0  emula el pre-WAIT de memoria del area bus (modelo, ver
//                  abajo): /WAIT desde PW_DLY ciclos despues de la bajada del
//                  RD filtrado, en lecturas de memoria del slot, hasta que
//                  Bus.WAIT_n baja y vuelve a subir, o PW_K ciclos con el RD
//                  retrasado en Bus si no baja, o RD/WR filtrados en reposo 3
//                  ciclos
//   PW_DLY         retardo del disparo del pre-WAIT (4: /WAIT en el pin 8 ciclos
//                  despues del /RD del pin; el area bus confirma el
//                  ciclo en el grupo 2 del mux tras saltar a el: unos 5-6)
//   PW_K           ciclos del pre-WAIT sin respuesta (PREWAIT_MEM_K del bus: 7)
//   TURBO    0/1/2 Z80 a 3,58 MHz (T = 30/31 ciclos, media 30,17), 5,37 MHz
//                  (T = 20/21, media 20,11) o 7,16 MHz (T = 15/16, media 15,08)
//   INJ      0/1   1: barrido de lecturas con un refresco de otro cliente del
//                  canal 0 (puerto 2 del EXPANSION_RAM) que llega antes, a la
//                  vez o despues de la lectura (el ACK_n del canal ya esta
//                  bajo, o el refresco acaba despues que la lectura). Con el
//                  UMA de tnCart el DOUT del canal se copia tambien tras un
//                  RFSH: si el refresco acaba despues que la lectura, el ACK_n
//                  sube con el dato del refresco (la ultima lectura de la
//                  SDRAM, del canal 1) y el WAIT se suelta con el dato malo;
//                  con el del hito 4 (DOUT solo tras un R/W) tiene que salir
//                  bien (run.sh: inj_main, inj_hito4)
//   STRICT   1/0   1: un dato mal leido por el Z80, o una lectura que acaba
//                  con el WAIT aun bajo, es fallo; 0: se cuentan (medidas).
//                  Las comprobaciones del contrato del /WAIT (cuando baja,
//                  dato valido al subir, dato estable) fallan siempre, salvo
//                  en las lecturas con refresco inyectado con STRICT = 0, en
//                  las que se cuentan aparte (inj_main: control del defecto
//                  del UMA de tnCart).
//
//   D_ADDR, D_CTRL, D_WAIT, D_DATA: supuestos de pines del Z80 (abajo)
//   TRACE    0/1   1: en lugar del programa, reproduce la traza de tncrom de
//                  +TRACE=<fichero> (run.sh tncrom). Es un parametro y no solo
//                  el plusarg porque con las dos ramas vivas Verilator 5.020
//                  inlinea el programa entero y el C++ pasa de 0,5 a 24 MB
//
// Supuestos de pines del Z80 (Z80A, en ciclos de 108 MHz = 9,26 ns), los
// mismos que el banco del area bus (docs/notas/bus.md de hito/bus, apartado
// 7: retardos maximos fijos, estimados): direccion D_ADDR = 12 ciclos (110 ns)
// despues de la subida de T1; /MREQ, /RD, /WR y el resto de salidas D_CTRL =
// 8 ciclos (70/75 ns) despues de su flanco; /WAIT visto con D_WAIT = 13 ciclos
// (NPN 50 ns + setup 70 ns antes de la bajada de T2); dato visto con D_DATA
// = 6 ciclos (setup 50 ns + transceptor). Un cambio puesto a los n ciclos lo
// ven los filtros del bus en el flanco n+1, asi que D_CTRL = 8 cubre un /RD a
// 75 ns. Solo cuentan en lo que ve el Z80. Hasta el 26/10/2026 el banco usaba
// D_CTRL = 5 (46 ns), D_ADDR = D_CTRL y D_WAIT = 11 (NPN 30 ns): con ellos la
// cadena del /WAIT sola llegaba justo a la bajada de T2 (variante
// noprewait_opt de run.sh, margen 0) y con estos no llega (noprewait).
//

`timescale 1ns/1ps
`default_nettype none

module tb_megaram #(
    parameter MEM_WAIT  = 1,
    parameter PREWAIT   = 1,
    parameter PW_DLY    = 4,
    parameter PW_K      = 7,
    parameter TURBO     = 0,
    parameter INJ       = 0,
    parameter STRICT    = 1,
    parameter D_ADDR    = 12,
    parameter D_CTRL    = 8,
    parameter D_WAIT    = 13,
    parameter D_DATA    = 6,
    parameter TRACE     = 0
) ();

    /***************************************************************
     * reloj de 108 MHz y resets
     ***************************************************************/
    logic clk = 0;
    always #4.6296 clk = ~clk;

    longint unsigned cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    logic pll_ready = 0;            // CLK_BASE_READY / CLK_MEM_READY
    logic sdram_ready;
    logic RESET_n = 0;              // reset de la carcasa (top)
    always @(posedge clk or negedge pll_ready or negedge sdram_ready) begin
        if(!pll_ready)        RESET_n <= 0;
        else if(!sdram_ready) RESET_n <= 0;
        else                  RESET_n <= 1;
    end

    logic clear_done;
    logic SYS_RESET_n;              // como main.sv con DONE en lugar de BOOT_n
    always @(posedge clk or negedge RESET_n) begin
        if(!RESET_n)         SYS_RESET_n <= 0;
        else if(!clear_done) SYS_RESET_n <= 0;
        else                 SYS_RESET_n <= 1;
    end

    /***************************************************************
     * pines del slot
     ***************************************************************/
    logic        CART_CLOCK = 0;
    logic        CART_SLTSL_n;
    logic        CART_RD_n;
    logic        CART_WR_n;
    logic [7:0]  CART_MUX_SIG;
    wire  [2:0]  CART_MUX_CS_n;
    wire  [7:0]  CART_DATA_SIG;
    wire         CART_DATA_DIR;
    wire         CART_BUSDIR_n;
    wire         CART_INT_n;
    wire         CART_WAIT_n;           // 1 = el transistor baja /WAIT

    // estado de los pines que saca el Z80
    logic [15:0] z_addr   = 16'h0000;
    logic        z_mreq_n = 1;
    logic        z_iorq_n = 1;
    logic        z_rd_n   = 1;
    logic        z_wr_n   = 1;
    logic        z_m1_n   = 1;
    logic        z_rfsh_n = 1;
    logic        z_reset_n= 0;
    logic [7:0]  z_dout   = 8'h00;
    logic        z_dout_en= 0;
    logic [7:0]  z_i      = 8'h00;      // registro I (parte alta de la direccion de refresco)
    logic [3:0]  slot_sel = 4'b0000;    // paginas cuyo slot primario es el cartucho

    wire [1:0] z_page = z_addr[15:14];
    assign CART_SLTSL_n = z_mreq_n || !slot_sel[z_page];
    assign CART_RD_n    = z_rd_n;
    assign CART_WR_n    = z_wr_n;
    wire z_cs1_n  = !(!z_mreq_n && !z_rd_n && z_page == 2'd1);
    wire z_cs2_n  = !(!z_mreq_n && !z_rd_n && z_page == 2'd2);
    wire z_cs12_n = z_cs1_n && z_cs2_n;
    always_comb begin
        case (CART_MUX_CS_n)
            3'b110:  CART_MUX_SIG = z_addr[15:8];
            3'b101:  CART_MUX_SIG = z_addr[7:0];
            3'b011:  CART_MUX_SIG = {z_m1_n, z_cs12_n, z_rfsh_n, z_reset_n, z_cs2_n, z_cs1_n, z_iorq_n, z_mreq_n};
            default: CART_MUX_SIG = 8'hFF;
        endcase
    end
    assign CART_DATA_SIG = z_dout_en ? z_dout : 8'bzzzz_zzzz;

    /***************************************************************
     * DUT
     ***************************************************************/
    BUS_IF  Bus();
    BOARD_REV1_BUS u_bus (
        .RESET_n,
        .CLK            (clk),
        .CLK_21M        (1'b0),
        .CART_BUSDIR_n,
        .CART_INT_n,
        .CART_WAIT_n,
        .CART_SLTSL_n,
        .CART_RD_n,
        .CART_WR_n,
        .CART_CLOCK,
        .CART_MUX_SIG,
        .CART_MUX_CS_n,
        .CART_DATA_SIG,
        .CART_DATA_DIR,
        .Bus
    );

    BUS_IF  ExpBus[0:1]();
    EXPANSION_SLOT #(
        .COUNT          (2),
        .USE_FF         (CONFIG::SLOT_EXPANSION_USES_FF)
    ) u_sltexp (
        .RESET_n        (SYS_RESET_n),
        .CLK            (clk),
        .Primary        (Bus),
        .Secondary      (ExpBus),
        .WAIT_n         (clear_done)
    );
    assign ExpBus[1].DOUT     = 8'h00;
    assign ExpBus[1].BUSDIR_n = 1'b1;
    assign ExpBus[1].INT_n    = 1'b1;
    assign ExpBus[1].WAIT_n   = 1'b1;

    RAM_IF  Ram();
    RAM_IF  UmaRam[0:1]();
    RAM_IF  ExpRam[0:2]();          // 0 megaROM, 1 borrado, 2 banco (inyecta accesos en el canal 0)
    UMA_IF  Uma();
    XFER_IF Xfer();
    SOUND_IF #(.BIT_WIDTH(CONFIG::SOUND_BIT_WIDTH)) Sound();

    assign Xfer.Busy  = 1'b0;
    assign Xfer.RData = 8'h00;

    // parametros de main.sv para ENABLE_MEGA_SCC_I
    CARTRIDGE_MEGAROM #(
        .ENABLE_MEM_WAIT        (MEM_WAIT),
        .FLASH_FS_ADDR          (0),
        .FLASH_FS_SIZE          (24'h10_0000),
        .FLASH_MEGAROM_ADDR     (CONFIG::FLASH_ADDR_MEGAROM),
        .FLASH_MEGAROM_SIZE     (CONFIG::FLASH_SIZE_MEGAROM),
        .FLASH_NEXTOR_ADDR      (CONFIG::FLASH_ADDR_BIOS),
        .FLASH_NEXTOR_SIZE      (CONFIG::FLASH_SIZE_BIOS_NEXTOR),
        .FLASH_FM_ADDR          (CONFIG::FLASH_ADDR_BIOS + CONFIG::FLASH_SIZE_BIOS_NEXTOR),
        .FLASH_FM_SIZE          (CONFIG::FLASH_SIZE_BIOS_FM),
        .FLASH_PAC_ADDR         (CONFIG::FLASH_ADDR_PAC),
        .FLASH_PAC_SIZE         (CONFIG::FLASH_SIZE_PAC),
        .RAM_ADDR               (CONFIG::RAM_ADDR_MEGAROM),
        .RAM_SIZE               (CONFIG::RAM_SIZE_MEGAROM),
        .DEFAULT_BANK_REG_INIT_0(0),
        .DEFAULT_BANK_REG_INIT_1(1),
        .DEFAULT_BANK_REG_INIT_2(2),
        .DEFAULT_BANK_REG_INIT_3(3),
        .DEFAULT_BANK_REG_ADDR_0(16'h5000),
        .DEFAULT_BANK_REG_ADDR_1(16'h7000),
        .DEFAULT_BANK_REG_ADDR_2(16'h9000),
        .DEFAULT_BANK_REG_ADDR_3(16'hB000),
        .DEFAULT_BANK_REG_ADDR_MASK(16'hF800),
        .DEFAULT_BANK_REG_MASK  (8'hFF),
        .DEFAULT_WRITE_PROTECT  (1'b0),
        .DEFAULT_IS_16K_BANK    (1'b0),
        .DEFAULT_CS1_MASK       (1'b0),
        .DEFAULT_CS2_MASK       (1'b0),
        .DEFAULT_SCC_ENA        (1'b1),
        .DEFAULT_SCC_I_ENA      (1'b1),
        .DEFAULT_ENABLE_CONTINUOUS(1'b1),
        .DEFAULT_ENABLE         (1'b1)
    ) u_megarom (
        .RESET_n        (SYS_RESET_n),
        .CLK            (clk),
        .Bus            (ExpBus[0]),
        .Ram            (ExpRam[0]),
        .Xfer           (Xfer),
        .Sound          (Sound)
    );

    MEGAROM_CLEAR #(
        .CLEAR_ADDR     (CONFIG::RAM_ADDR_MEGAROM),
        .CLEAR_SIZE     (24'd32768),
        .CLEAR_DATA     (8'hFF)
    ) u_clear (
        .RESET_n,
        .CLK            (clk),
        .Ram            (ExpRam[1]),
        .DONE           (clear_done)
    );

    EXPANSION_RAM #(
        .COUNT          (3),
        .USE_FF         (CONFIG::RAM_IF_EXPANSION_USES_FF)
    ) u_expram (
        .RESET_n,
        .CLK            (clk),
        .Primary        (UmaRam[0]),
        .Secondary      (ExpRam)
    );

    // puerto 2: refresco o escritura sueltos en el canal 0 (fuera de la ventana)
    logic tb_rfsh_n = 1, tb_we_n = 1;      // los conduce el proceso de inyeccion (abajo)
    assign ExpRam[2].ADDR     = tb_we_n ? 24'h00_0000 : 24'h50_0000;
    assign ExpRam[2].DIN      = tb_we_n ? 32'h0 : 32'hDEAD_BEEF;
    assign ExpRam[2].DIN_SIZE = tb_we_n ? RAM::DIN_SIZE_8 : RAM::DIN_SIZE_32;
    assign ExpRam[2].OE_n     = 1'b1;
    assign ExpRam[2].WE_n     = tb_we_n;
    assign ExpRam[2].RFSH_n   = tb_rfsh_n;

    assign Uma.ADDR[0] = 24'h00_0000;
    assign Uma.ADDR[1] = CONFIG::RAM_ADDR_VRAM;
    UMA #(
        .COUNT          (2),
        .SYNC_CLK_EN    (CONFIG_BOARD::SYNC_CPU_UMA),
        .DIV            (30)
    ) u_uma (
        .RESET_n,
        .CLK            (clk),
        .CLK_EN         (Bus.CLK_EN),
        .Primary        (Ram),
        .Secondary      (UmaRam),
        .Uma            (Uma)
    );

    SDRAM_IF_MODEL u_ram (
        .CLK            (clk),
        .RESET_n        (pll_ready),
        .READY          (sdram_ready),
        .Ram            (Ram)
    );

    /***************************************************************
     * memoria: patron inicial y acceso directo
     ***************************************************************/
    function automatic logic [31:0] pat_word(input int unsigned w);
        logic [31:0] x;
        x = w * 32'h9E37_79B1;
        return x ^ (x >> 15) ^ 32'h5A5A_1234;
    endfunction
    function automatic logic [7:0] pat_byte(input int unsigned a);
        logic [31:0] w;
        w = pat_word(a >> 2);
        return w[(a & 3) * 8 +: 8];
    endfunction
    function automatic logic [7:0] mem_byte(input int unsigned a);
        logic [31:0] w;
        w = u_ram.mem[a[22:2]];
        return w[(a & 3) * 8 +: 8];
    endfunction
    task automatic mem_put(input int unsigned a, input logic [7:0] d);
        logic [31:0] w;
        w = u_ram.mem[a[22:2]];
        w[(a & 3) * 8 +: 8] = d;
        u_ram.mem[a[22:2]] = w;
    endtask

    /***************************************************************
     * errores y medidas
     ***************************************************************/
    int unsigned errors = 0;
    int unsigned soft_errors = 0;
    task automatic fail(input string msg);
        errors++;
        $display("[%0d] ERROR: %s", cyc, msg);
    endtask
    // fallo del Z80 (dato mal leido, lectura sin esperar): duro solo con STRICT
    int unsigned n_rd_early = 0;
    task automatic zfail(input string msg);
        if(STRICT) fail(msg);
        else soft_errors++;
    endtask

    /***************************************************************
     * cliente de VRAM en el canal 1 (V9990 a plena carga)
     ***************************************************************/
    typedef enum logic [1:0] { V_IDLE, V_ACK, V_BUSY } vstate_t;
    vstate_t     vstate;
    logic [18:0] vaddr;
    int unsigned v_reads = 0, v_late = 0, v_bad = 0;
    always @(posedge clk or negedge RESET_n) begin
        if(!RESET_n) begin
            vstate <= V_IDLE;
            vaddr  <= 0;
            UmaRam[1].OE_n     <= 1;
            UmaRam[1].WE_n     <= 1;
            UmaRam[1].RFSH_n   <= 1;
            UmaRam[1].ADDR     <= 0;
            UmaRam[1].DIN      <= 0;
            UmaRam[1].DIN_SIZE <= RAM::DIN_SIZE_32;
        end
        else begin
            case (vstate)
                V_IDLE: if(UmaRam[1].TIMING) begin
                    UmaRam[1].OE_n <= 0;
                    UmaRam[1].ADDR <= {5'd0, vaddr[18:2], 2'b00};
                    vstate <= V_ACK;
                end
                V_ACK: begin
                    if(UmaRam[1].TIMING) v_late <= v_late + 1;
                    if(!UmaRam[1].ACK_n) begin
                        UmaRam[1].OE_n <= 1;
                        vstate <= V_BUSY;
                    end
                end
                V_BUSY: begin
                    if(UmaRam[1].TIMING) v_late <= v_late + 1;   // ranura perdida
                    if(UmaRam[1].ACK_n) begin
                        v_reads <= v_reads + 1;
                        if(UmaRam[1].DOUT != u_ram.mem[(CONFIG::RAM_ADDR_VRAM + {5'd0, vaddr[18:2], 2'b00}) >> 2]) v_bad <= v_bad + 1;
                        vaddr  <= vaddr + 19'd4 * 19'd37;
                        vstate <= V_IDLE;
                    end
                end
                default: vstate <= V_IDLE;
            endcase
        end
    end

    /***************************************************************
     * pre-WAIT de memoria del area bus (modelo, PREWAIT = 1)
     *  - dispara PW_DLY ciclos despues de ver el RD filtrado a 0 (u_bus.RD_n,
     *    antes de la linea de 9) si en ese momento el ciclo es de memoria del
     *    slot (SLTSL y MERQ en los pines: lo que el area bus confirma en el
     *    grupo 2 del mux tras su salto adaptativo);
     *  - se suelta cuando Bus.WAIT_n (la cadena) baja y vuelve a subir, o si
     *    no ha bajado tras PW_K ciclos con el RD retrasado en Bus, o con RD y
     *    WR filtrados en reposo 3 ciclos seguidos.
     ***************************************************************/
    logic prewait = 0;
    logic pw_seen = 0;
    int   pw_k = 0;
    int   pw_cnt = -1;
    int   rw_idle = 0;
    logic prev_frd_n = 1;
    int unsigned pw_fires = 0, pw_rel_k = 0;
    always @(posedge clk) begin
        prev_frd_n <= u_bus.RD_n;
        rw_idle <= (u_bus.RD_n && u_bus.WR_n) ? ((rw_idle < 3) ? rw_idle + 1 : 3) : 0;
        if(!PREWAIT) begin
            prewait <= 0;
            pw_cnt  <= -1;
        end
        else begin
            if(prev_frd_n && !u_bus.RD_n && !prewait) pw_cnt <= 0;
            else if(pw_cnt >= 0)                      pw_cnt <= pw_cnt + 1;
            if(!prewait && pw_cnt == PW_DLY) begin
                pw_cnt <= -1;
                if(!CART_SLTSL_n && !z_mreq_n && !u_bus.RD_n) begin
                    prewait <= 1;
                    pw_seen <= 0;
                    pw_k    <= 0;
                    pw_fires <= pw_fires + 1;
                end
            end
            if(prewait) begin
                if(!Bus.RD_n && !pw_seen) pw_k <= pw_k + 1;
                if(!Bus.WAIT_n) pw_seen <= 1;
                if((pw_seen && Bus.WAIT_n) || (!pw_seen && Bus.WAIT_n && pw_k >= PW_K) || rw_idle >= 3) begin
                    if(!pw_seen && pw_k >= PW_K) pw_rel_k <= pw_rel_k + 1;
                    prewait <= 0;
                    pw_seen <= 0;
                end
            end
        end
    end

    // lo que ve el Z80: /WAIT y dato con su retardo de entrada
    wire pin_wait = CART_WAIT_n || prewait;
    logic [31:0] wait_hist = 0;
    logic [7:0]  data_hist [0:31];
    logic [31:0] ddir_hist = 0;     // 1 = el cartucho conduce el bus
    always @(posedge clk) begin
        wait_hist <= {wait_hist[30:0], pin_wait};
        ddir_hist <= {ddir_hist[30:0], !CART_DATA_DIR};
        data_hist[0] <= CART_DATA_SIG;
        for(int i = 1; i < 32; i++) data_hist[i] <= data_hist[i-1];
    end
    wire       z_wait_seen = wait_hist[D_WAIT-1];
    wire [7:0] z_data_seen = data_hist[D_DATA-1];
    wire       z_ddir_seen = ddir_hist[D_DATA-1];

    // retardo /RD del pin -> /WAIT en el pin (pre-WAIT o cadena), por lectura
    logic prev_pin_rd_n = 1, prev_pin_wait = 0;
    longint unsigned t_pin_rd = 0;
    logic pin_rd_open = 0;
    int unsigned d_pinw_min = 999, d_pinw_max = 0;
    always @(posedge clk) begin
        prev_pin_rd_n <= z_rd_n;
        prev_pin_wait <= pin_wait;
        if(prev_pin_rd_n && !z_rd_n) begin t_pin_rd <= cyc; pin_rd_open <= 1; end
        if(z_rd_n) pin_rd_open <= 0;
        if(pin_rd_open && !prev_pin_wait && pin_wait && !z_mreq_n && !CART_SLTSL_n) begin
            pin_rd_open <= 0;
            if(cyc - t_pin_rd < d_pinw_min) d_pinw_min <= int'(cyc - t_pin_rd);
            if(cyc - t_pin_rd > d_pinw_max) d_pinw_max <= int'(cyc - t_pin_rd);
        end
    end

    /***************************************************************
     * monitor del contrato del /WAIT en Bus (top) y en el puerto
     ***************************************************************/
    logic [7:0]  exp_data = 8'h00;      // lo pone el Z80 antes de cada lectura
    logic [15:0] exp_addr = 16'h0000;   // y la direccion que quiere leer
    logic        exp_valid = 0;
    logic        exp_hard = 1;          // 0: el dato esperado no sale de la SDRAM (SCC): solo lo comprueba el Z80
    logic        prev_rdmem_n = 1, prev_twait_n = 1, prev_pwait_n = 1, prev_trd_n = 1, prev_ack_n = 1;
    longint unsigned t_trd_fall = 0, t_rdmem_fall = 0, t_twait_fall = 0;
    logic        in_read = 0, saw_twait = 0, released = 0, saw_ack_low = 0, got_ack = 0;
    logic [7:0]  cur_exp = 8'h00;       // lo esperado en la lectura en curso (se fija al empezar)
    logic        cur_exp_valid = 0;
    // lecturas con un refresco inyectado (INJ): con STRICT = 0 una violacion
    // del contrato en ellas no es fallo, se cuenta (una por lectura)
    logic        inj_active = 0;        // lo pone rd_chk_inj
    logic        cur_inj = 0, cur_viol = 0;
    int unsigned n_viol_inj = 0;
    int unsigned n_mread = 0, n_waited = 0, n_ack_low_start = 0;
    int unsigned d_fall_min = 999, d_fall_max = 0;      // Bus.RD_n -> Bus.WAIT_n (top)
    int unsigned d_pfall_min = 999, d_pfall_max = 0;    // rd_mem_n -> WAIT_n del puerto
    int unsigned d_rel_min = 999, d_rel_max = 0;        // Bus.RD_n -> Bus.WAIT_n sube
    int unsigned d_dat_min = 999, d_dat_max = 0;        // Bus.RD_n -> Bus.DOUT valido (por ACK)
    int unsigned d_low_min = 999;                        // duracion del pulso bajo
    int unsigned hist_rel [0:63];
    int unsigned n_rfsh_cand = 0;                        // refrescos que sin !RFSH_n serian lecturas
    // lecturas en las que el controlador ve otra direccion que la del Z80: es
    // el BOARD_REV1_BUS de main (sin el escaneo adaptativo de hito/bus) que no
    // ha capturado la direccion a tiempo, no el /WAIT de la megaROM. Con
    // STRICT es fallo; si no, se cuentan y la lectura no pasa por las
    // comprobaciones del dato del contrato (el Z80 la cuenta igual como mal)
    int unsigned n_addr_bad = 0;
    initial for(int i = 0; i < 64; i++) hist_rel[i] = 0;

    wire rdmem_n   = u_megarom.u_rom.rd_mem_n;
    wire port_wait = ExpBus[0].WAIT_n;
    wire ack0_n    = ExpRam[0].ACK_n;
    // lo que el controlador tomaria por lectura sin la condicion de RFSH_n
    wire rd_norfsh = !ExpBus[0].SLTSL_n && !ExpBus[0].MERQ_n && !ExpBus[0].RD_n && !u_megarom.u_rom.cs_mem_n;
    logic prev_rd_norfsh = 0;

    always @(posedge clk) begin
        prev_trd_n   <= Bus.RD_n;
        prev_rdmem_n <= rdmem_n;
        prev_twait_n <= Bus.WAIT_n;
        prev_pwait_n <= port_wait;
        prev_ack_n   <= ack0_n;
        prev_rd_norfsh <= rd_norfsh && !ExpBus[0].RFSH_n;

        if(prev_trd_n && !Bus.RD_n) t_trd_fall <= cyc;

        // un refresco (RFSH_n bajo) nunca es una lectura del controlador
        if(rd_norfsh && !ExpBus[0].RFSH_n && !prev_rd_norfsh && SYS_RESET_n) n_rfsh_cand <= n_rfsh_cand + 1;
        if(!rdmem_n && !ExpBus[0].RFSH_n) fail("rd_mem_n bajo durante un refresco");

        if(SYS_RESET_n && prev_rdmem_n && !rdmem_n) begin
            in_read <= 1; saw_twait <= 0; released <= 0; saw_ack_low <= 0; got_ack <= 0;
            t_rdmem_fall <= cyc;
            n_mread <= n_mread + 1;
            if(!ack0_n) n_ack_low_start <= n_ack_low_start + 1;
            cur_exp <= exp_data;
            cur_exp_valid <= exp_valid && exp_hard && (!exp_valid || ExpBus[0].ADDR == exp_addr || STRICT);
            if(exp_valid && ExpBus[0].ADDR != exp_addr) begin
                n_addr_bad <= n_addr_bad + 1;
                if(STRICT) fail($sformatf("el controlador lee %04xh y el Z80 %04xh (direccion del bus a destiempo)", ExpBus[0].ADDR, exp_addr));
            end
            cur_inj <= inj_active;
            cur_viol <= 0;
        end

        if(in_read) begin
            if(!ack0_n) saw_ack_low <= 1;
            if(saw_ack_low && !prev_ack_n && ack0_n && !got_ack) begin
                got_ack <= 1;
                // Bus.DOUT del puerto un ciclo despues, el del top dos
                if(cyc + 2 - t_trd_fall < d_dat_min) d_dat_min <= int'(cyc + 2 - t_trd_fall);
                if(cyc + 2 - t_trd_fall > d_dat_max) d_dat_max <= int'(cyc + 2 - t_trd_fall);
            end
            if(prev_pwait_n && !port_wait) begin
                if(cyc - t_rdmem_fall < d_pfall_min) d_pfall_min <= int'(cyc - t_rdmem_fall);
                if(cyc - t_rdmem_fall > d_pfall_max) d_pfall_max <= int'(cyc - t_rdmem_fall);
                if(MEM_WAIT && cyc - t_rdmem_fall > 3) fail($sformatf("WAIT_n del puerto bajo %0d ciclos despues de rd_mem_n", cyc - t_rdmem_fall));
            end
            if(prev_twait_n && !Bus.WAIT_n) begin
                saw_twait <= 1;
                t_twait_fall <= cyc;
                if(cyc - t_trd_fall < d_fall_min) d_fall_min <= int'(cyc - t_trd_fall);
                if(cyc - t_trd_fall > d_fall_max) d_fall_max <= int'(cyc - t_trd_fall);
                if(MEM_WAIT && cyc - t_trd_fall > 5) fail($sformatf("Bus.WAIT_n bajo %0d ciclos despues de Bus.RD_n", cyc - t_trd_fall));
            end
            if(saw_twait && !prev_twait_n && Bus.WAIT_n && !released) begin
                released <= 1;
                n_waited <= n_waited + 1;
                if(cyc - t_trd_fall < d_rel_min) d_rel_min <= int'(cyc - t_trd_fall);
                if(cyc - t_trd_fall > d_rel_max) d_rel_max <= int'(cyc - t_trd_fall);
                if(cyc - t_twait_fall < d_low_min) d_low_min <= int'(cyc - t_twait_fall);
                hist_rel[(cyc - t_trd_fall) > 63 ? 63 : (cyc - t_trd_fall)] <= hist_rel[(cyc - t_trd_fall) > 63 ? 63 : (cyc - t_trd_fall)] + 1;
                if(cur_exp_valid && (Bus.DOUT != cur_exp || Bus.BUSDIR_n)) begin
                    if(cur_inj && !STRICT) begin
                        if(!cur_viol) n_viol_inj <= n_viol_inj + 1;
                        cur_viol <= 1;
                    end
                    else fail($sformatf("WAIT suelto con Bus.DOUT=%02x BUSDIR_n=%0d (esperado %02x)", Bus.DOUT, Bus.BUSDIR_n, cur_exp));
                end
            end
            // del WAIT suelto al fin de la lectura el dato no cambia. Salvo con
            // el /RESET del MSX: msx_reset lo baja nada mas acabar la lectura en
            // el pin, cuando en el camino retrasado aun no ha acabado, y
            // EXPANSION_SLOT pone sus salidas en reposo (el Z80 ya tomo el dato;
            // lo encontro la traza de tncrom, que hace "R" y luego "Z")
            if(released && cur_exp_valid && Bus.RESET_n && (Bus.DOUT != cur_exp || Bus.BUSDIR_n)) begin
                if(cur_inj && !STRICT) begin
                    if(!cur_viol) n_viol_inj <= n_viol_inj + 1;
                    cur_viol <= 1;
                end
                else fail($sformatf("Bus.DOUT cambio tras soltar WAIT: %02x (esperado %02x)", Bus.DOUT, cur_exp));
            end
            if(!prev_rdmem_n && rdmem_n) begin
                in_read <= 0;
                if(MEM_WAIT && !saw_twait) fail("lectura de la megaROM sin WAIT");
                if(MEM_WAIT && saw_twait && !released) begin
                    n_rd_early <= n_rd_early + 1;
                    zfail("la lectura acabo con el WAIT aun bajo (el Z80 no espero)");
                end
            end
        end
        else begin
            if(MEM_WAIT && clear_done && SYS_RESET_n && !Bus.WAIT_n && Bus.RESET_n && prev_twait_n)
                fail("Bus.WAIT_n bajo fuera de una lectura de la megaROM");
        end
    end

    /***************************************************************
     * traza por ciclo (+DBG_FROM=<ciclo> +DBG_TO=<ciclo>)
     ***************************************************************/
    longint unsigned dbg_from = 0, dbg_to = 0;
    initial begin
        if(!$value$plusargs("DBG_FROM=%d", dbg_from)) dbg_from = 0;
        if(!$value$plusargs("DBG_TO=%d", dbg_to)) dbg_to = 0;
    end
    always @(posedge clk) if(cyc >= dbg_from && cyc <= dbg_to && dbg_to != 0)
        $display("[%0d] pin: A=%04x mreq=%b rd=%b wr=%b rfsh=%b wait=%b | port: A=%04x sltsl=%b merq=%b rd=%b rfsh=%b rd_mem_n=%b mw=%0d WAIT_n=%b | ack0=%b ramdout=%02x busdir=%b dout=%02x | top: rd=%b wait=%b dout=%02x busdir=%b",
                 cyc, z_addr, z_mreq_n, z_rd_n, z_wr_n, z_rfsh_n, pin_wait,
                 ExpBus[0].ADDR, ExpBus[0].SLTSL_n, ExpBus[0].MERQ_n, ExpBus[0].RD_n, ExpBus[0].RFSH_n, rdmem_n, u_megarom.u_rom.mw_state, port_wait,
                 ack0_n, ExpRam[0].DOUT[7:0], ExpBus[0].BUSDIR_n, ExpBus[0].DOUT,
                 Bus.RD_n, Bus.WAIT_n, Bus.DOUT, Bus.BUSDIR_n);

    /***************************************************************
     * modelo del Z80 a nivel de pines
     ***************************************************************/
    int tlen = 30;
    int tpos = 0;
    int tcount = 0;
    int unsigned z_reads = 0, z_waits = 0;
    function automatic int next_len();
        if(TURBO == 2) return ((tcount % 12) == 11) ? 16 : 15;   // media 15,08 = 108 / 7,159
        if(TURBO == 1) return ((tcount %  9) ==  8) ? 21 : 20;   // media 20,11 = 108 / 5,369
        return ((tcount % 6) == 5) ? 31 : 30;                    // media 30,17 = 108 / 3,5795
    endfunction

    // un ciclo de 108 MHz; el reloj del Z80 sube en tpos = 0 y baja en tlen/2
    task automatic step();
        @(posedge clk);
        tpos++;
        if(tpos == tlen / 2) CART_CLOCK = 0;
        if(tpos >= tlen) begin
            tpos = 0;
            tcount++;
            tlen = next_len();
            CART_CLOCK = 1;
        end
    endtask
    task automatic to_rise();   do step(); while(tpos != 0); endtask
    task automatic to_fall();   do step(); while(tpos != tlen / 2); endtask
    task automatic after(input int n); repeat(n) step(); endtask
    task automatic idle_T(input int n); repeat(n) to_rise(); endtask

    // TW: muestrea /WAIT en cada flanco de bajada desde T2
    task automatic wait_states();
        to_fall();                      // bajada de T2
        while(z_wait_seen) begin
            z_waits++;
            to_rise();                  // TW
            to_fall();
        end
    endtask

    // T1: direccion (y /M1) D_ADDR ciclos despues de la subida; si eso cae
    // despues de la bajada (turbos: semiperiodo de 10 o 7 ciclos) se pone
    // detras de la bajada, siempre antes que /MREQ. Vuelve D_CTRL ciclos
    // despues de la bajada de T1, cuando el que llama baja /MREQ (y /RD)
    task automatic t1_addr(input logic [15:0] a, input bit m1);
        int h, na;
        to_rise();                                                          // T1
        h = tlen / 2;
        if(D_ADDR < h) begin
            after(D_ADDR);  z_addr = a; if(m1) z_m1_n = 0;
            to_fall();      after(D_CTRL);
        end
        else begin
            to_fall();
            na = (D_ADDR - h < D_CTRL) ? D_ADDR - h : D_CTRL - 1;
            after(na);      z_addr = a; if(m1) z_m1_n = 0;
            after(D_CTRL - na);
        end
    endtask

    // M1 (opcode fetch) con refresco; devuelve el dato muestreado
    task automatic z_fetch(input logic [15:0] a, output logic [7:0] d);
        t1_addr(a, 1);              z_mreq_n = 0; z_rd_n = 0;
        to_rise();                                                          // T2
        wait_states();
        to_rise();                                                          // T3
        d = z_data_seen;
        if(!z_ddir_seen) d = 8'hFF;
        after(D_CTRL); z_mreq_n = 1; z_rd_n = 1; z_m1_n = 1; z_rfsh_n = 0; z_addr = {z_i, 1'b0, tcount[6:0]};
        to_fall();  after(D_CTRL);  z_mreq_n = 0;
        to_rise();                                                          // T4
        to_fall();  after(D_CTRL);  z_mreq_n = 1;
        while(tpos < tlen - 2) step();
        z_rfsh_n = 1;
    endtask

    // lectura de memoria normal
    task automatic z_read(input logic [15:0] a, output logic [7:0] d);
        t1_addr(a, 0);              z_mreq_n = 0; z_rd_n = 0;
        to_rise();                                                          // T2
        wait_states();
        to_rise();                                                          // T3
        to_fall();
        d = z_data_seen;
        if(!z_ddir_seen) d = 8'hFF;
        after(D_CTRL); z_mreq_n = 1; z_rd_n = 1;
    endtask

    // escritura de memoria
    task automatic z_write(input logic [15:0] a, input logic [7:0] d);
        t1_addr(a, 0);              z_mreq_n = 0; z_dout = d; z_dout_en = 1;
        to_rise();  after(D_CTRL);  z_wr_n = 0;                             // T2
        wait_states();
        to_rise();                                                          // T3
        to_fall();  after(D_CTRL);  z_wr_n = 1; z_mreq_n = 1;
        to_rise();  z_dout_en = 0;
    endtask

    // lectura con comprobacion: m1 = 1 usa un M1 (fetch), si no una lectura
    task automatic rd_chk(input logic [15:0] a, input logic [7:0] e, input string what, input bit m1 = 0);
        logic [7:0] d;
        exp_data = e; exp_addr = a; exp_valid = 1;
        if(m1) z_fetch(a, d); else z_read(a, d);
        exp_valid = 0;
        z_reads++;
        if(d !== e) zfail($sformatf("%s: lectura %04xh = %02x, esperado %02x", what, a, d, e));
    endtask

    // lectura con un refresco (kind 0) o una escritura (kind 1) inyectados en
    // el canal 0 dly ciclos despues de la bajada de /RD en el pin: el ACK_n
    // del canal ya esta bajo (o baja) cuando el controlador ve la lectura
    int unsigned n_inj = 0;
    int   inj_seq = 0;              // lo incrementa la tarea
    int   inj_ack = 0;              // lo iguala el proceso al tomar la peticion
    int   inj_kind_s = 0, inj_dly_s = 0, inj_cnt = -1;
    logic prev_zrd_inj = 1;
    always @(posedge clk) begin
        prev_zrd_inj <= z_rd_n;
        if(inj_ack != inj_seq && prev_zrd_inj && !z_rd_n) begin
            inj_ack <= inj_seq;
            inj_cnt <= 0;
        end
        else if(inj_cnt >= 0) inj_cnt <= inj_cnt + 1;
        if(inj_cnt == inj_dly_s) begin
            if(inj_kind_s == 0) tb_rfsh_n <= 0;
            else                tb_we_n   <= 0;
        end
        if(inj_cnt == inj_dly_s + 2) begin
            tb_rfsh_n <= 1;
            tb_we_n   <= 1;
            inj_cnt   <= -1;
            n_inj     <= n_inj + 1;
        end
    end
    task automatic rd_chk_inj(input logic [15:0] a, input logic [7:0] e, input int kind, input int dly);
        inj_kind_s = kind; inj_dly_s = dly; inj_seq++;
        inj_active = 1;
        rd_chk(a, e, $sformatf("lectura con %s inyectado a +%0d", kind ? "escritura" : "refresco", dly));
        inj_active = 0;
        if(inj_ack != inj_seq) fail("inyeccion no hecha");
    endtask

    // lectura sin respuesta del cartucho (BUSDIR_n alto)
    task automatic rd_none(input logic [15:0] a, input string what);
        logic [7:0] d;
        exp_valid = 0;
        z_read(a, d);
        if(d !== 8'hFF) fail($sformatf("%s: %04xh respondio %02x (esperado sin respuesta)", what, a, d));
    endtask

    task automatic msx_reset(input int t);
        z_reset_n = 0;
        idle_T(t);
        z_reset_n = 1;
        idle_T(20);
    endtask

    /***************************************************************
     * lo que hace tncrom (lib/rom_tools.c)
     ***************************************************************/
    task automatic unlock();
        z_write(16'h0000, 8'hAB); z_write(16'h0001, 8'hCD); z_write(16'h0002, 8'h98); z_write(16'h0003, 8'h76);
    endtask
    task automatic lock();
        z_write(16'h0000, 8'h00); z_write(16'h0001, 8'h00); z_write(16'h0002, 8'h00); z_write(16'h0003, 8'h00);
    endtask
    // atributo: flags, mascara de valor, mascara de direccion, 4 bancos (dir, inicial, reservado)
    task automatic attr_write(input logic [7:0] flags, input logic [7:0] vmask, input logic [15:0] amask,
                              input logic [15:0] b0, input logic [15:0] b1, input logic [15:0] b2, input logic [15:0] b3,
                              input logic [7:0] i0, input logic [7:0] i1, input logic [7:0] i2, input logic [7:0] i3,
                              input logic [7:0] mode);
        z_write(16'h000C, flags);
        z_write(16'h000D, vmask);
        z_write(16'h000E, amask[7:0]);  z_write(16'h000F, amask[15:8]);
        z_write(16'h0010, b0[7:0]); z_write(16'h0011, b0[15:8]); z_write(16'h0012, i0); z_write(16'h0013, 8'h00);
        z_write(16'h0014, b1[7:0]); z_write(16'h0015, b1[15:8]); z_write(16'h0016, i1); z_write(16'h0017, 8'h00);
        z_write(16'h0018, b2[7:0]); z_write(16'h0019, b2[15:8]); z_write(16'h001A, i2); z_write(16'h001B, 8'h00);
        z_write(16'h001C, b3[7:0]); z_write(16'h001D, b3[15:8]); z_write(16'h001E, i3); z_write(16'h001F, mode);
    endtask
    localparam [7:0] F_WP = 8'h01, F_BANK16 = 8'h02, F_SCC = 8'h10, F_SCC_I = 8'h20, F_CONT = 8'h40, F_ENABLE = 8'h80;
    task automatic attr_ascii16_wo_wp();
        unlock();
        attr_write(F_ENABLE | F_BANK16, 8'hFF, 16'hF800, 16'h6000, 16'h7000, 16'hFFFF, 16'hFFFF, 0, 0, 0, 0, 8'h00);
        lock();
    endtask
    task automatic attr_ascii16();
        unlock();
        attr_write(F_WP | F_BANK16, 8'hFF, 16'hF800, 16'h6000, 16'h7000, 16'hFFFF, 16'hFFFF, 0, 0, 0, 0, 8'h00);
        lock();
    endtask
    task automatic set_rom_enable(input bit cont);
        logic [7:0] f;
        unlock();
        z_read(16'h000C, f);
        f = (f & 8'h3F) | F_ENABLE | (cont ? F_CONT : 8'h00);
        z_write(16'h000C, f);
        lock();
    endtask

    function automatic logic [7:0] img(input int unsigned bank, input int unsigned off);
        return 8'((bank * 8'd37) ^ (off >> 8) ^ off ^ 8'hC3);
    endfunction

    /***************************************************************
     * traza de tncrom (+TRACE=<fichero>, run.sh tncrom)
     *  Las operaciones de bus que el tncrom real (compilado para el host,
     *  tools/tncrom/test) hizo con el modelo en C del cartucho, desde el
     *  encendido: "W aaaa dd" escritura, "R aaaa dd" lectura con el dato
     *  que dio el modelo (aqui tiene que dar lo mismo el RTL), "Z 0000 00"
     *  /RESET del MSX, "#" comentario. Las paginas 0-2 van al cartucho; una
     *  de cada ocho lecturas es un M1 (con su refresco).
     ***************************************************************/
    string trace_file = "";
    initial if(TRACE != 0 && !$value$plusargs("TRACE=%s", trace_file)) trace_file = "";
    task automatic replay_trace();
        int fd, r;
        string line;
        int unsigned n_line = 0, n_w = 0, n_r = 0, n_z = 0;
        logic [15:0] ta;
        logic [7:0]  td;
        fd = $fopen(trace_file, "r");
        if(trace_file == "" || fd == 0) begin fail({"TRACE = 1 sin +TRACE=<fichero> legible: '", trace_file, "'"}); return; end
        slot_sel = 4'b0111;
        while(!$feof(fd)) begin
            r = $fgets(line, fd);
            if(r <= 0) break;
            n_line++;
            if(line.len() < 9 || line[0] == "#") continue;
            ta = 16'(line.substr(2, 5).atohex());
            td = 8'(line.substr(7, 8).atohex());
            case (line[0])
                "W": begin z_write(ta, td); n_w++; end
                "R": begin rd_chk(ta, td, $sformatf("traza linea %0d", n_line), (n_r % 8) == 3); n_r++; end
                "Z": begin msx_reset(30); n_z++; end
                default: fail($sformatf("traza linea %0d: '%s'", n_line, line));
            endcase
        end
        $fclose(fd);
        $display("traza %s: %0d lineas, %0d escrituras, %0d lecturas comprobadas, %0d /RESET",
                 trace_file, n_line, n_w, n_r, n_z);
    endtask

    /***************************************************************
     * programa
     ***************************************************************/
    int unsigned banks16 [9] = '{8'h00, 8'h01, 8'h02, 8'h7F, 8'h80, 8'hBF, 8'hC0, 8'hFE, 8'hFF};
    int unsigned offs16  [5] = '{16'h0000, 16'h0001, 16'h1234, 16'h3FFE, 16'h3FFF};
    longint unsigned t_clear_start;
    logic [7:0] d;

    // instante de DONE
    longint unsigned u_clear_done_t = 0;
    logic prev_done = 0;
    always @(posedge clk) begin
        prev_done <= clear_done;
        if(!prev_done && clear_done) u_clear_done_t <= cyc;
    end

    initial begin
        int unsigned a;
        int unsigned rd0;

        $display("tb_megaram: MEM_WAIT=%0d PREWAIT=%0d PW_DLY=%0d PW_K=%0d TURBO=%0d STRICT=%0d",
                 MEM_WAIT, PREWAIT, PW_DLY, PW_K, TURBO, STRICT);
        $display("Z80: D_ADDR=%0d D_CTRL=%0d D_WAIT=%0d D_DATA=%0d ciclos de 108 MHz",
                 D_ADDR, D_CTRL, D_WAIT, D_DATA);

        // SDRAM con patron (contenido de encendido)
        for(int unsigned w = 0; w < (1 << 21); w++) u_ram.mem[w] = pat_word(w);

        // ---------------- arranque: borrado de 32 KB ----------------
        CART_CLOCK = 1;
        z_reset_n = 0;
        after(10);
        pll_ready = 1;
        while(!RESET_n) step();
        t_clear_start = cyc;
        // el MSX sale de reset antes de que acabe el borrado: su primer
        // ciclo (en otro slot) tiene que quedarse en WAIT hasta DONE
        idle_T(20);
        z_reset_n = 1;
        if(!clear_done && Bus.WAIT_n) fail("Bus.WAIT_n alto durante el borrado");
        z_fetch(16'h0000, d);
        if(!clear_done) fail("el primer ciclo del Z80 acabo antes de DONE");
        while(!clear_done) step();
        $display("borrado: DONE a los %0d ciclos de soltar RESET_n (%0.2f ms), %0d escrituras de 32 bits",
                 u_clear_done_t - t_clear_start, real'(u_clear_done_t - t_clear_start) / 108000.0, u_ram.n_write);
        if(u_ram.n_write != 8192) fail($sformatf("borrado: %0d escrituras (esperadas 8192)", u_ram.n_write));
        for(a = 0; a < 32768; a++) if(mem_byte(a) !== 8'hFF) begin fail($sformatf("borrado: %06xh = %02x", a, mem_byte(a))); break; end
        for(a = 32768; a < 32768 + 4096; a++) if(mem_byte(a) !== pat_byte(a)) begin fail($sformatf("borrado se paso: %06xh", a)); break; end
        for(a = CONFIG::RAM_ADDR_VRAM; a < CONFIG::RAM_ADDR_VRAM + 4096; a++) if(mem_byte(a) !== pat_byte(a)) begin fail($sformatf("VRAM tocada: %06xh", a)); break; end
        if(ExpRam[1].DIN_SIZE !== RAM::DIN_SIZE_8 || ExpRam[1].ADDR !== 0 || ExpRam[1].WE_n !== 1)
            fail("borrado: el puerto no queda en reposo tras DONE");
        idle_T(20);

        // ---------------- traza de tncrom (en lugar del programa) ----------------
        if(TRACE != 0) replay_trace();
        else begin

        // ---------------- Konami SCC-I RAM por defecto ----------------
        slot_sel = 4'b0110;     // paginas 1 y 2 en el slot del cartucho
        rd_chk(16'h4000, 8'hFF, "SCC-I: cabecera borrada (no hay AB)", 1);
        rd_chk(16'h4001, 8'hFF, "SCC-I: cabecera borrada (no hay AB)");
        rd_chk(16'h8000, 8'hFF, "SCC-I: 8000h");
        rd_chk(16'h7FFF, 8'hFF, "SCC-I: 7FFFh");
        rd_chk(16'hBFFF, 8'hFF, "SCC-I: BFFFh (banco 3 = 7FFFh, ultimo byte borrado)");
        // bancos de 8 KB con valor de 8 bits: 2 MB
        z_write(16'h5000, 8'hFF);  z_write(16'h4000, 8'h11);  z_write(16'h5FFF, 8'h12);
        z_write(16'h7000, 8'h80);  z_write(16'h6123, 8'h22);
        z_write(16'h9000, 8'h3E);  z_write(16'h8000, 8'h33);
        z_write(16'hB000, 8'hC1);  z_write(16'hA456, 8'h44);
        idle_T(4);
        if(mem_byte(32'h1FE000) !== 8'h11 || mem_byte(32'h1FFFFF) !== 8'h12) fail("SCC-I: escritura en el banco FFh (2 MB)");
        if(mem_byte(32'h100123) !== 8'h22) fail("SCC-I: escritura en el banco 80h");
        if(mem_byte(32'h07C000) !== 8'h33) fail("SCC-I: escritura en el banco 3Eh");
        if(mem_byte(32'h182456) !== 8'h44) fail("SCC-I: escritura en el banco C1h");
        rd_chk(16'h4000, 8'h11, "SCC-I: banco FFh", 1);
        rd_chk(16'h5FFF, 8'h12, "SCC-I: banco FFh");
        rd_chk(16'h6123, 8'h22, "SCC-I: banco 80h", 1);
        rd_chk(16'h8000, 8'h33, "SCC-I: banco 3Eh");
        rd_chk(16'hA456, 8'h44, "SCC-I: banco C1h", 1);
        for(int i = 0; i < 40; i++) begin
            a = 32'h1FE000 + i * 199;
            rd_chk(16'h4000 + 16'(i * 199), mem_byte(a), "SCC-I: barrido banco FFh", i[0]);
        end
        // refresco de otro cliente del canal 0 antes, durante o despues de la
        // lectura (con STRICT = 0 la comprobacion del dato es solo la del Z80)
        if(INJ) begin
            for(int dly = 0; dly <= 30; dly++)
                rd_chk_inj(16'h4000 + 16'(dly * 5), mem_byte(32'h1FE000 + dly * 5), 0, dly);
        end
        // SCC (modo compatible): banco 2 = 3Fh, onda del canal 1 en 9800h. La
        // escritura llega tambien a la RAM (sin proteccion); se cambia la RAM
        // por detras para ver que la lectura sale del SCC y no de la SDRAM
        z_write(16'h9000, 8'h3F);
        z_write(16'h9800, 8'h5A);  z_write(16'h9801, 8'hA5);
        idle_T(4);
        mem_put(32'h3F * 8192 + 16'h1800, 8'h00);  mem_put(32'h3F * 8192 + 16'h1801, 8'h00);
        exp_hard = 0;
        rd_chk(16'h9800, 8'h5A, "SCC: onda del canal 1 (byte 0)");
        rd_chk(16'h9801, 8'hA5, "SCC: onda del canal 1 (byte 1)");
        exp_hard = 1;
        rd_chk(16'h8000, mem_byte(32'h3F * 8192), "SCC: 8000h con banco 3Fh sigue siendo RAM");
        z_write(16'h9000, 8'h02);
        // registro I en la ventana: los refrescos de los M1 no son lecturas
        z_i = 8'h40;
        for(int i = 0; i < 16; i++) rd_chk(16'h4000 + 16'(i * 7), mem_byte(32'h1FE000 + i * 7), "SCC-I: M1 con I = 40h", 1);
        z_i = 8'h00;
        // /RESET con ENABLE_CONTINUOUS: sigue activa, bancos a 0,1,2,3
        msx_reset(30);
        rd_chk(16'h4000, 8'hFF, "SCC-I tras /RESET: banco 0", 1);
        rd_chk(16'hA000, 8'hFF, "SCC-I tras /RESET: banco 3 (6000h, borrado)");
        rd_chk(16'h8000 + 16'h1000, 8'h3E, "SCC-I tras /RESET: escritura a 9000h tambien fue a la RAM (como una ESE-SCC)");

        // ---------------- secuencia de tncrom ----------------
        slot_sel = 4'b0111;     // pagina 0 tambien (WRSLT/RDSLT a 0000h)
        // check_cartridge: 0000h no es RAM, la llave abre y cierra
        z_write(16'h0000, 8'hAA);
        rd_none(16'h0000, "llave cerrada");
        unlock();
        rd_chk(16'h0000, 8'hAB, "llave 0");  rd_chk(16'h0001, 8'hCD, "llave 1");
        rd_chk(16'h0002, 8'h98, "llave 2");  rd_chk(16'h0003, 8'h76, "llave 3");
        rd_chk(16'h003E, 8'h00, "3Eh: ventana de 4 MB = 256 bancos de 16 KB (00h)");
        rd_chk(16'h003C, 8'h00, "3Ch: direccion de la ventana [15:8]");
        rd_chk(16'h003D, 8'h00, "3Dh: direccion de la ventana [23:16]");
        rd_chk(16'h001F, 8'h00, "1Fh: modo al encender");
        lock();
        rd_none(16'h0003, "llave cerrada otra vez");
        // carga: ASCII16 sin proteccion, banco 0 al ultimo, datos por 8000h
        attr_ascii16_wo_wp();
        z_write(16'h6000, 8'hFF);
        foreach(banks16[i]) begin
            z_write(16'h7000, 8'(banks16[i]));
            foreach(offs16[j]) z_write(16'h8000 + 16'(offs16[j]), img(banks16[i], offs16[j]));
        end
        idle_T(4);
        foreach(banks16[i]) foreach(offs16[j])
            if(mem_byte(banks16[i] * 16384 + offs16[j]) !== img(banks16[i], offs16[j]))
                fail($sformatf("ASCII16: escritura banco %02xh +%04xh (SDRAM %06xh)", banks16[i], offs16[j], banks16[i] * 16384 + offs16[j]));
        // atributo final (ASCII16 protegido), banco 0 a 0, ENABLE + CONTINUOUS
        attr_ascii16();
        z_write(16'h6000, 8'h00);  z_write(16'h7000, 8'h00);
        set_rom_enable(1);
        foreach(banks16[i]) begin
            z_write(16'h7000, 8'(banks16[i]));
            z_write(16'h6000, 8'(banks16[i]));
            foreach(offs16[j]) begin
                rd_chk(16'h8000 + 16'(offs16[j]), img(banks16[i], offs16[j]), $sformatf("ASCII16 pag. 2 banco %02xh", banks16[i]), j[0]);
                rd_chk(16'h4000 + 16'(offs16[j]), img(banks16[i], offs16[j]), $sformatf("ASCII16 pag. 1 banco %02xh", banks16[i]));
            end
        end
        // con proteccion no se escribe
        z_write(16'h7000, 8'hFF);
        z_write(16'h8000, 8'h5A);
        idle_T(4);
        if(mem_byte(32'h3FC000) !== img(8'hFF, 0)) fail("ASCII16 protegido: la escritura llego a la SDRAM");
        // /RESET del MSX con lo que dejo tncrom. SYS_RESET_n ya no sigue al
        // /RESET (hito/integ; con el bootloader de tnCart si lo seguia y la
        // megaROM volvia a sus valores de fabrica): la megaROM pasa por la
        // rama !Bus.RESET_n de megarom_configure.sv, que conserva el
        // atributo, cierra la llave, pone los bancos a su valor inicial y
        // deja ENABLE segun ENABLE_CONTINUOUS.
        msx_reset(30);
        rd_chk(16'h4000, img(8'h00, 0), "ASCII16 tras /RESET con ENABLE_CONTINUOUS: pag. 1 = banco 0", 1);
        rd_chk(16'h8000 + 16'h3FFF, img(8'h00, 16'h3FFF), "ASCII16 tras /RESET con ENABLE_CONTINUOUS: pag. 2 = banco 0");
        rd_none(16'h0000, "llave cerrada tras /RESET");
        z_write(16'h7000, 8'hBF);
        rd_chk(16'h8000 + 16'h1234, img(8'hBF, 16'h1234), "ASCII16 tras /RESET: los registros de banco siguen en 6000h/7000h");
        set_rom_enable(0);      // tncrom -O: sin ENABLE_CONTINUOUS
        msx_reset(30);
        rd_none(16'h4000, "ASCII16 tras /RESET sin ENABLE_CONTINUOUS (tncrom -O)");
        rd_none(16'h8000, "ASCII16 tras /RESET sin ENABLE_CONTINUOUS (tncrom -O), 8000h");
        // 32K (tabla de tncrom de V9990TANG: banco 1 inicial = 1; con el 0 de
        // tnCart, tras /RESET 8000h-BFFFh repetiria 4000h-7FFFh)
        unlock();
        attr_write(F_WP | F_BANK16, 8'hFF, 16'h0000, 16'hFFFF, 16'hFFFF, 16'hFFFF, 16'hFFFF, 0, 1, 0, 0, 8'h00);
        lock();
        set_rom_enable(1);
        msx_reset(30);
        rd_chk(16'h4001, img(8'h00, 1), "32K tras /RESET: 4000h-7FFFh = primer bloque de 16 KB", 1);
        rd_chk(16'h8001, img(8'h01, 1), "32K tras /RESET: 8000h-BFFFh = segundo bloque de 16 KB");
        rd_chk(16'hBFFF, img(8'h01, 16'h3FFF), "32K tras /RESET: BFFFh");
        z_write(16'h7000, 8'h02);   // sin registros de banco
        rd_chk(16'h8001, img(8'h01, 1), "32K: escribir 7000h no cambia de banco");
        // 8 KB: 256 bancos = 2 MB (ASCII8, banco 3 en 7800h)
        unlock();
        attr_write(F_WP | F_ENABLE | F_CONT, 8'hFF, 16'hF800, 16'h6000, 16'h6800, 16'h7000, 16'h7800, 0, 0, 0, 0, 8'h00);
        lock();
        z_write(16'h7800, 8'hFF);   // A000h-BFFFh -> 1FE000h
        z_write(16'h7000, 8'h01);   // 8000h-9FFFh -> 002000h
        rd_chk(16'hBFFE, img(8'h7F, 16'h3FFE), "ASCII8 banco FFh (= 16K 7Fh +3FFEh)", 1);
        rd_chk(16'hBFFF, img(8'h7F, 16'h3FFF), "ASCII8 banco FFh (= 16K 7Fh +3FFFh)");
        rd_chk(16'hA000, mem_byte(32'h1FE000), "ASCII8 banco FFh +0");
        rd_chk(16'h8001, mem_byte(32'h002001), "ASCII8 banco 01h +1");
        // KONAMI de la tabla de tncrom (proteccion, SCC, mascara 3Fh): el
        // banco FFh se queda en 3Fh (512 KB); con la mascara FFh que tncrom r2
        // escribe en 0Dh para una imagen de 2 MB llega al banco FFh
        unlock();
        attr_write(F_WP | F_SCC | F_ENABLE | F_CONT, 8'h3F, 16'hF800, 16'h5000, 16'h7000, 16'h9000, 16'hB000, 0, 1, 2, 3, 8'h00);
        lock();
        d = mem_byte(32'hFF * 8192 + 16'h1000);     // B000h con el banco 3 = FFh (del ASCII8)
        z_write(16'hB000, 8'hFF);
        idle_T(4);
        if(mem_byte(32'hFF * 8192 + 16'h1000) !== d) fail("KONAMI protegido: el registro de banco B000h escribio la RAM");
        rd_chk(16'hA123, mem_byte(32'h3F * 8192 + 16'h0123), "KONAMI mascara 3Fh: banco FFh = 3Fh", 1);
        z_write(16'h5000, 8'h41);
        rd_chk(16'h4123, mem_byte(32'h01 * 8192 + 16'h0123), "KONAMI mascara 3Fh: banco 41h = 01h");
        unlock();
        z_write(16'h000D, 8'hFF);
        lock();
        z_write(16'hB000, 8'hFF);
        rd_chk(16'hA123, mem_byte(32'hFF * 8192 + 16'h0123), "KONAMI mascara FFh: banco FFh", 1);
        z_write(16'h5000, 8'h41);
        rd_chk(16'h4123, mem_byte(32'h41 * 8192 + 16'h0123), "KONAMI mascara FFh: banco 41h");

        // ---------------- modo plano en 0000h (PLAIN0) ----------------
        // imagen de 48 KB: "AB" en 4000h, ISR en 0038h
        attr_ascii16_wo_wp();
        z_write(16'h6000, 8'h02);
        for(int bk = 0; bk < 3; bk++) begin
            z_write(16'h7000, 8'(bk));
            z_write(16'h8000, (bk == 1) ? 8'h41 : img(bk, 0));
            z_write(16'h8001, (bk == 1) ? 8'h42 : img(bk, 1));
            z_write(16'h8038, img(bk, 16'h38));
            z_write(16'h800C, img(bk, 16'h0C));
            z_write(16'h803F, img(bk, 16'h3F));
            z_write(16'h9800, img(bk, 16'h1800));
            z_write(16'hBFFE, img(bk, 16'h3FFE));
            z_write(16'hBFFF, img(bk, 16'h3FFF));
        end
        attr_ascii16();
        z_write(16'h6000, 8'h00);
        // atributo PLAIN0 (lo que escribe tncrom -T PLAIN0, aqui con SCC y el
        // banco 2 en 9000h para comprobar que el SCC queda mudo): con la llave
        // abierta el flag se lee y el modo aun no esta activo
        unlock();
        // (con ENABLE_CONTINUOUS para comprobar que el /RESET lo ignora)
        attr_write(F_WP | F_BANK16 | F_SCC | F_ENABLE | F_CONT, 8'hFF, 16'hF800, 16'hFFFF, 16'hFFFF, 16'h9000, 16'hFFFF, 0, 0, 0, 0, 8'h01);
        rd_chk(16'h001F, 8'h01, "PLAIN0 con la llave abierta: 1Fh");
        rd_chk(16'h000C, F_WP | F_BANK16 | F_SCC | F_ENABLE | F_CONT, "PLAIN0 con la llave abierta: flags");
        if(u_megarom.u_conf.plain_active) fail("PLAIN0 activo con la llave abierta");
        z_write(16'h9000, 8'h3F);   // banco 2 = 3Fh: sin PLAIN0 el SCC contestaria en 9800h
        lock();
        if(!u_megarom.u_conf.plain_active) fail("PLAIN0 no se activo al cerrar la llave");
        slot_sel = 4'b1111;
        rd_chk(16'h0000, img(0, 0), "PLAIN0 0000h", 1);
        rd_chk(16'h0001, img(0, 1), "PLAIN0 0001h");
        rd_chk(16'h000C, img(0, 16'h0C), "PLAIN0 000Ch (registros ocultos)");
        rd_chk(16'h0038, img(0, 16'h38), "PLAIN0 0038h (ISR)", 1);
        rd_chk(16'h003F, img(0, 16'h3F), "PLAIN0 003Fh");
        rd_chk(16'h4000, 8'h41, "PLAIN0 4000h 'A'", 1);
        rd_chk(16'h4001, 8'h42, "PLAIN0 4001h 'B'");
        rd_chk(16'h4038, img(1, 16'h38), "PLAIN0 4038h");
        rd_chk(16'h7FFF, img(1, 16'h3FFF), "PLAIN0 7FFFh");
        rd_chk(16'h8000, img(2, 0), "PLAIN0 8000h", 1);
        rd_chk(16'h9800, img(2, 16'h1800), "PLAIN0 9800h (SCC mudo con banco 2 = 3Fh)");
        rd_chk(16'hBFFE, img(2, 16'h3FFE), "PLAIN0 BFFEh");
        rd_chk(16'hBFFF, img(2, 16'h3FFF), "PLAIN0 BFFFh");
        for(int i = 0; i < 32; i++) begin
            a = (i * 1531) % 49152;
            rd_chk(16'(a), mem_byte(a), "PLAIN0 barrido lineal", i[0]);
        end
        rd_none(16'hC000, "PLAIN0 C000h");
        // M1 en la pagina 0 con refresco en la pagina 0 (I = 00h): el refresco
        // cae en la ventana y no tiene que contar como lectura
        rd0 = n_mread;
        for(int i = 0; i < 16; i++) rd_chk(16'h0100 + 16'(i * 13), mem_byte(32'h0100 + i * 13), "PLAIN0 M1 en la pagina 0", 1);
        if(n_mread - rd0 != 16) fail($sformatf("PLAIN0: %0d lecturas del controlador para 16 M1", n_mread - rd0));
        // la llave y la configuracion no se pueden tocar
        unlock();
        rd_chk(16'h0000, img(0, 0), "PLAIN0 tras escribir la llave");
        if(!u_megarom.u_conf.reg_protect) fail("PLAIN0: la llave se abrio");
        z_write(16'h000C, 8'h00);
        z_write(16'h001F, 8'h00);
        if(!u_megarom.u_conf.plain_active) fail("PLAIN0: una escritura a la configuracion lo desactivo");
        // escritura protegida y bancos fijos (BFFEh, el modo del SCC-I, tampoco)
        z_write(16'h4000, 8'h99);
        z_write(16'h0038, 8'h99);
        z_write(16'h7000, 8'h05);
        z_write(16'h9000, 8'h05);
        z_write(16'hBFFE, 8'h30);
        idle_T(4);
        if(mem_byte(32'h4000) !== 8'h41 || mem_byte(32'h0038) !== img(0, 16'h38) || mem_byte(32'hBFFE) !== img(2, 16'h3FFE))
            fail("PLAIN0: escritura en la ROM");
        if(u_megarom.Megarom.BankRegRaw[2] !== 8'h3F) fail("PLAIN0: se escribio un registro de banco");
        rd_chk(16'h8000, img(2, 0), "PLAIN0 8000h tras escribir 7000h", 1);
        rd_chk(16'h4000, 8'h41, "PLAIN0 4000h tras escribir", 1);
        // /RESET: borra el flag y ENABLE aunque hubiera ENABLE_CONTINUOUS
        msx_reset(30);
        if(u_megarom.u_conf.plain_active) fail("PLAIN0 sigue tras /RESET");
        rd_none(16'h4000, "tras /RESET de PLAIN0 (ENABLE borrado)");
        rd_none(16'h0038, "tras /RESET de PLAIN0, 0038h");
        unlock();
        rd_chk(16'h001F, 8'h00, "1Fh tras /RESET");
        rd_chk(16'h000C, F_WP | F_BANK16 | F_SCC | F_CONT, "flags tras /RESET (ENABLE a 0 pese a ENABLE_CONTINUOUS)");
        lock();

        end     // programa (TRACE = 0)

        // ---------------- informe ----------------
        idle_T(10);
        $display("----------------------------------------------------------------");
        $display("lecturas de la megaROM: %0d (Z80: %0d con comprobacion), con WAIT: %0d, TW del Z80: %0d",
                 n_mread, z_reads, n_waited, z_waits);
        $display("lecturas que empiezan con Ram.ACK_n ya bajo (refresco/escritura en curso): %0d (accesos inyectados: %0d)", n_ack_low_start, n_inj);
        if(INJ) $display("lecturas con refresco inyectado que rompen el contrato del WAIT (dato malo al soltarlo o despues): %0d de %0d",
                         n_viol_inj, n_inj);
        $display("refrescos que sin !RFSH_n habrian sido lecturas: %0d", n_rfsh_cand);
        $display("lecturas con otra direccion en el camino retrasado (bus de main a destiempo): %0d", n_addr_bad);
        if(PREWAIT) $display("pre-WAIT (modelo): %0d disparos, %0d soltados por K; /RD del pin -> /WAIT del pin: %0d..%0d ciclos",
                             pw_fires, pw_rel_k, d_pinw_min, d_pinw_max);
        else        $display("/RD del pin -> /WAIT del pin (solo la cadena): %0d..%0d ciclos", d_pinw_min, d_pinw_max);
        if(n_waited > 0) begin
            $display("Bus.RD_n -> Bus.WAIT_n baja (top): %0d..%0d ciclos", d_fall_min, d_fall_max);
            $display("rd_mem_n -> WAIT_n del puerto baja: %0d..%0d ciclos", d_pfall_min, d_pfall_max);
            $display("Bus.RD_n -> Bus.WAIT_n sube (= Bus.DOUT valido): %0d..%0d ciclos (%0.0f..%0.0f ns); pulso bajo minimo %0d",
                     d_rel_min, d_rel_max, d_rel_min * 9.259, d_rel_max * 9.259, d_low_min);
            $write("histograma de la liberacion (ciclos:lecturas):");
            for(int i = 0; i < 64; i++) if(hist_rel[i] != 0) $write(" %0d:%0d", i, hist_rel[i]);
            $display("");
        end
        $display("Bus.RD_n -> Bus.DOUT con el dato (por ACK del UMA): %0d..%0d ciclos (%0.0f..%0.0f ns)",
                 d_dat_min, d_dat_max, d_dat_min * 9.259, d_dat_max * 9.259);
        $display("SDRAM: %0d lecturas, %0d escrituras, %0d refrescos, %0d refrescos absorbidos por un acceso",
                 u_ram.n_read, u_ram.n_write, u_ram.n_rfsh, u_ram.n_rfsh_dropped);
        $display("VRAM (canal 1): %0d lecturas, %0d con dato malo, %0d ranuras perdidas", v_reads, v_bad, v_late);
        if(v_bad != 0 || v_late != 0) fail("cliente de VRAM con errores");
        if(!STRICT) $display("fallos del Z80 contados (dato equivocado o lectura sin esperar): %0d; lecturas acabadas con el WAIT bajo: %0d",
                             soft_errors, n_rd_early);
        if(errors == 0) $display("RESULTADO: PASA");
        else            $display("RESULTADO: FALLA (%0d errores)", errors);
        $finish;
    end

    // guardia
    initial begin
        #(64'd400_000_000);
        $display("RESULTADO: FALLA (tiempo agotado)");
        $finish;
    end
endmodule

`default_nettype wire
