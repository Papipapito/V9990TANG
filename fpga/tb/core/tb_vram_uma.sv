// tb_vram_uma.sv -- la VRAM del V9990 tal como la ve el core en la WonderTANG:
// el UMA REAL de tnCart (fpga/src/peripheral/ram/uma.sv, DIV = 30, sin enganche
// al reloj del slot como en la variante xtal: SYNC_CLK_EN = 0) mas un modelo de
// sdram.sv ciclo a ciclo en su interfaz con el UMA (no el chip SDRAM):
//
//   - nivel en OE_n/WE_n/RFSH_n (LEVEL_TRIG = 1) en STATE_IDLE -> 9 estados
//     (IDLE = 32 ... END = 40) y vuelta a IDLE;
//   - ACK_n = 0 en el ciclo siguiente a la aceptacion, ACK_n = 1 al salir de
//     STATE_FETCH_RDATA_2 (IDLE + 7);
//   - DOUT se carga en STATE_FETCH_RDATA_1 (palabra desplazada por ADDR[1:0], o
//     los bytes pares/impares de la rafaga con DIN_SIZE_32_E/_O) y se completa en
//     STATE_FETCH_RDATA_2 (_E/_O);
//   - escrituras con las mascaras DQM de sdram.sv (8 bits por ADDR[1:0], 16 por
//     ADDR[1], 32 alineado, _E/_O en bytes pares/impares de la rafaga de 8);
//   - TIMING = (state == IDLE); la secuencia de inicializacion son 32 ciclos.
//
// La memoria (mem[]) es la ventana de 512 KB de la VRAM en la SDRAM (78_0000h):
// el indice es la direccion de la SDRAM menos 78_0000h, es decir, la VRAM en el
// orden fisico del tiny9990 (lineal en Bx; en P1 el byte A esta en 2*A[17:0]+A[18]).
//
// Canal 0 (la RAM del MSX): parado, o con CH0_LOAD = 1 una lectura en cada una de
// sus ranuras (para ver que no estorba al canal del V9990).
// ACK_DELAY > 0 retrasa ACK_n y DOUT del canal 1 hacia el core: sirve para
// comprobar que la asercion de ranura perdida de t9990_ram.sv salta.
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
`timescale 1ns/1ps
module TB_VRAM_UMA #(
    parameter [23:0] VRAM_BASE = 24'h78_0000
) (
    input  wire         RESET_n,
    input  wire         CLK,
    input  wire         CH0_LOAD,
    input  integer      ACK_DELAY,

    // enables del V9990 (UMA_IF.CLK)
    output wire         CLK21M_EN,
    output wire         CLK14M_EN,
    output wire         CLK25M_EN,

    // RAM_IF del V9990 (canal 1)
    output wire         RAM_REQ,            // TIMING
    input  wire         RAM_OE_n,
    input  wire         RAM_WE_n,
    input  wire         RAM_RFSH_n,
    input  wire [18:0]  RAM_ADDR,
    input  wire [31:0]  RAM_DIN,
    input  wire [2:0]   RAM_DIN_SIZE,
    output wire [31:0]  RAM_DOUT,
    output wire         RAM_ACK_n
);
    /***************************************************************
     * UMA real
     ***************************************************************/
    RAM_IF  Primary();
    RAM_IF  UmaRam[0:1]();
    UMA_IF  Uma();
    assign Uma.ADDR[0] = 24'h00_0000;
    assign Uma.ADDR[1] = VRAM_BASE;

    UMA #(
        .COUNT      (2),
        .SYNC_CLK_EN(0)
    ) u_uma (
        .RESET_n,
        .CLK,
        .CLK_EN     (1'b0),
        .Primary    (Primary),
        .Secondary  (UmaRam),
        .Uma        (Uma)
    );

    assign CLK21M_EN = Uma.CLK21M_EN;
    assign CLK14M_EN = Uma.CLK14M_EN;
    assign CLK25M_EN = Uma.CLK25M_EN;

    // canal 1: el V9990 (como cartridge_v9990.sv: Ram.ADDR = {5'b00000, addr})
    assign UmaRam[1].OE_n     = RAM_OE_n;
    assign UmaRam[1].WE_n     = RAM_WE_n;
    assign UmaRam[1].RFSH_n   = RAM_RFSH_n;
    assign UmaRam[1].ADDR     = {5'b00000, RAM_ADDR};
    assign UmaRam[1].DIN      = RAM_DIN;
    assign UmaRam[1].DIN_SIZE = RAM_DIN_SIZE;
    assign RAM_REQ            = UmaRam[1].TIMING;

    // ACK_n / DOUT hacia el core, con retardo opcional
    logic [31:0] dout_q [0:63];
    logic        ack_q  [0:63];
    integer k;
    always @(posedge CLK) begin
        dout_q[0] <= UmaRam[1].DOUT;
        ack_q[0]  <= UmaRam[1].ACK_n;
        for (k = 1; k < 64; k = k + 1) begin dout_q[k] <= dout_q[k-1]; ack_q[k] <= ack_q[k-1]; end
    end
    assign RAM_DOUT  = (ACK_DELAY > 0) ? dout_q[ACK_DELAY-1] : UmaRam[1].DOUT;
    assign RAM_ACK_n = (ACK_DELAY > 0) ? ack_q[ACK_DELAY-1]  : UmaRam[1].ACK_n;

    // canal 0: la RAM del MSX
    logic ch0_oe_n = 1'b1;
    logic [23:0] ch0_addr = 24'h0;
    integer ch0_reads = 0;
    always @(posedge CLK) begin
        if (!RESET_n || !CH0_LOAD) ch0_oe_n <= 1'b1;
        else if (ch0_oe_n && UmaRam[0].ACK_n) begin ch0_oe_n <= 1'b0; ch0_addr <= ch0_addr + 24'd4; end
        else if (!UmaRam[0].ACK_n) begin
            if (!ch0_oe_n) ch0_reads <= ch0_reads + 1;
            ch0_oe_n <= 1'b1;
        end
    end
    assign UmaRam[0].OE_n     = ch0_oe_n;
    assign UmaRam[0].WE_n     = 1'b1;
    assign UmaRam[0].RFSH_n   = 1'b1;
    assign UmaRam[0].ADDR     = ch0_addr & 24'h0F_FFFF;
    assign UmaRam[0].DIN      = 32'h0;
    assign UmaRam[0].DIN_SIZE = RAM::DIN_SIZE_32;

    /***************************************************************
     * modelo de sdram.sv (lado del UMA)
     ***************************************************************/
    localparam [6:0] ST_IDLE   = 7'd32;
    localparam [6:0] ST_RW     = ST_IDLE + 7'd3;    // STATE_READ_WRITE
    localparam [6:0] ST_FETCH1 = ST_IDLE + 7'd6;    // STATE_FETCH_RDATA_1
    localparam [6:0] ST_FETCH2 = ST_IDLE + 7'd7;    // STATE_FETCH_RDATA_2 = STATE_INACTIVE_ACK
    localparam [6:0] ST_END    = ST_IDLE + 7'd8;

    reg [7:0] mem [0:524287];
    integer i;
    initial for (i = 0; i < 524288; i = i + 1) mem[i] = 8'h00;

    logic [6:0]  state;
    logic        begin_rd, begin_wr, begin_rfsh;
    assign begin_rd   = !Primary.OE_n;
    assign begin_wr   = !Primary.WE_n;
    assign begin_rfsh = !Primary.RFSH_n;

    logic [23:0] save_addr;
    logic [31:0] save_din;
    logic [2:0]  save_size;
    logic        cmd_rd, cmd_wr, cmd_rf;
    integer n_rd = 0, n_wr = 0, n_rf = 0, n_out = 0;

    assign Primary.TIMING = (state == ST_IDLE);

    // desplazamiento dentro de la ventana de la VRAM (VRAM_BASE tiene los bits 18:0 a cero)
    wire [18:0] sa = save_addr[18:0];
    wire [31:0] sw = {mem[{sa[18:2], 2'd3}], mem[{sa[18:2], 2'd2}], mem[{sa[18:2], 2'd1}], mem[{sa[18:2], 2'd0}]};

    always_ff @(posedge CLK or negedge RESET_n) begin
        if (!RESET_n) begin
            state <= 7'd0;
            Primary.ACK_n <= 1'b1;
            Primary.DOUT <= 32'h0;
            cmd_rd <= 0; cmd_wr <= 0; cmd_rf <= 0;
        end
        else begin
            // estado
            if (state == ST_IDLE)     state <= (begin_rd || begin_wr || begin_rfsh) ? state + 7'd1 : state;
            else if (state == ST_END) state <= ST_IDLE;
            else                      state <= state + 7'd1;

            // ACK_n
            if (state == ST_IDLE) begin
                if (begin_rd || begin_wr || begin_rfsh) Primary.ACK_n <= 1'b0;
            end
            else if (state == ST_FETCH2) Primary.ACK_n <= 1'b1;

            // aceptacion (STATE_ACTIVE = STATE_IDLE)
            if (state == ST_IDLE) begin
                if (begin_rd || begin_wr) begin
                    save_addr <= Primary.ADDR; save_din <= Primary.DIN; save_size <= Primary.DIN_SIZE;
                    cmd_wr <= !Primary.WE_n; cmd_rd <= Primary.WE_n; cmd_rf <= 1'b0;
                    if ((Primary.ADDR & 24'hF8_0000) != VRAM_BASE && Primary.ADDR >= 24'h10_0000)
                        $display("AVISO tb_vram_uma: acceso fuera de la VRAM: %06h", Primary.ADDR);
                end
                else if (begin_rfsh) begin
                    cmd_wr <= 0; cmd_rd <= 0; cmd_rf <= 1'b1;
                end
            end

            // escritura (STATE_READ_WRITE): mascaras DQM de sdram.sv
            if (state == ST_RW && cmd_wr && (save_addr & 24'hF8_0000) == VRAM_BASE) begin
                n_wr <= n_wr + 1;
                case (save_size)
                    RAM::DIN_SIZE_32_E: begin
                        mem[{sa[18:3], 3'd0}] <= save_din[ 7: 0];
                        mem[{sa[18:3], 3'd2}] <= save_din[15: 8];
                        mem[{sa[18:3], 3'd4}] <= save_din[23:16];
                        mem[{sa[18:3], 3'd6}] <= save_din[31:24];
                    end
                    RAM::DIN_SIZE_32_O: begin
                        mem[{sa[18:3], 3'd1}] <= save_din[ 7: 0];
                        mem[{sa[18:3], 3'd3}] <= save_din[15: 8];
                        mem[{sa[18:3], 3'd5}] <= save_din[23:16];
                        mem[{sa[18:3], 3'd7}] <= save_din[31:24];
                    end
                    RAM::DIN_SIZE_32: begin
                        mem[{sa[18:2], 2'd0}] <= save_din[ 7: 0];
                        mem[{sa[18:2], 2'd1}] <= save_din[15: 8];
                        mem[{sa[18:2], 2'd2}] <= save_din[23:16];
                        mem[{sa[18:2], 2'd3}] <= save_din[31:24];
                    end
                    RAM::DIN_SIZE_16: begin
                        mem[{sa[18:1], 1'b0}] <= save_din[ 7: 0];
                        mem[{sa[18:1], 1'b1}] <= save_din[15: 8];
                    end
                    default:            mem[sa] <= save_din[7:0];
                endcase
            end
            if (state == ST_RW && cmd_rd) n_rd <= n_rd + 1;
            if (state == ST_RW && cmd_rf) n_rf <= n_rf + 1;

            // lectura
            if (state == ST_FETCH1 && cmd_rd) begin
                if (save_size == RAM::DIN_SIZE_32_E)
                    Primary.DOUT <= {mem[{sa[18:3], 3'd2}], mem[{sa[18:3], 3'd0}],
                                     mem[{sa[18:3], 3'd2}], mem[{sa[18:3], 3'd0}]};
                else if (save_size == RAM::DIN_SIZE_32_O)
                    Primary.DOUT <= {mem[{sa[18:3], 3'd3}], mem[{sa[18:3], 3'd1}],
                                     mem[{sa[18:3], 3'd3}], mem[{sa[18:3], 3'd1}]};
                else case (save_addr[1:0])
                    2'd0: Primary.DOUT <= sw;
                    2'd1: Primary.DOUT <= {8'h00,  sw[31: 8]};
                    2'd2: Primary.DOUT <= {16'h00, sw[31:16]};
                    2'd3: Primary.DOUT <= {24'h00, sw[31:24]};
                endcase
            end
            if (state == ST_FETCH2 && cmd_rd) begin
                if (save_size == RAM::DIN_SIZE_32_E)
                    Primary.DOUT <= {mem[{sa[18:3], 3'd6}], mem[{sa[18:3], 3'd4}], Primary.DOUT[15:0]};
                else if (save_size == RAM::DIN_SIZE_32_O)
                    Primary.DOUT <= {mem[{sa[18:3], 3'd7}], mem[{sa[18:3], 3'd5}], Primary.DOUT[15:0]};
            end
        end
    end

    /***************************************************************
     * medida de la latencia vista por el core: del EXEC (TIMING + 1) al ACK_n = 1
     ***************************************************************/
    // Solo cuentan los accesos que el core lanza en su ranura: OE_n/WE_n/RFSH_n bajan en el EXEC
    // (TIMING + 1). lat = ciclos desde TIMING hasta el primer ciclo con ACK_n = 1 otra vez; tiene que
    // ser menor que 20 (la siguiente ranura del canal 1). n_lat_odd cuenta los que no salen en 13.
    // Con RESET_n = 0 no se mide: antes del primer flanco con reset los registros del core salen a 0 en
    // el simulador (OE_n/WE_n/RFSH_n = 0 en el instante 0) y eso no es un acceso.
    logic req_q = 0, req_qq = 0, ack_prev = 1, req_prev = 1, inflight = 0;
    integer t_req = 0, t_now = 0, t_acc = 0, lat_min = 1 << 30, lat_max = -1, n_lat = 0, n_lat_odd = 0, n_acc_off = 0;
    wire req_any_n = RAM_OE_n && RAM_WE_n && RAM_RFSH_n;
    always @(posedge CLK) if (!RESET_n) begin
        t_now <= t_now + 1;
        req_q <= 0; req_qq <= 0; ack_prev <= 1; req_prev <= 1; inflight <= 0;
    end
    else begin
        t_now <= t_now + 1;
        req_q <= RAM_REQ; req_qq <= req_q;
        ack_prev <= RAM_ACK_n;
        req_prev <= req_any_n;
        if (RAM_REQ) t_req <= t_now;
        if (req_prev && !req_any_n) begin
            inflight <= 1; t_acc <= t_req;
            if (!req_qq) begin      // OE_n/WE_n/RFSH_n bajan dos ciclos despues de TIMING (EXEC = TIMING + 1)
                n_acc_off <= n_acc_off + 1;
                if (n_acc_off < 4) $display("AVISO tb_vram_uma: acceso del core fuera del EXEC en t=%0t", $time);
            end
        end
        if (inflight && !ack_prev && RAM_ACK_n) begin
            inflight <= 0;
            if (t_now - t_acc < lat_min) lat_min <= t_now - t_acc;
            if (t_now - t_acc > lat_max) lat_max <= t_now - t_acc;
            n_lat <= n_lat + 1;
            if (t_now - t_acc != 13) begin
                n_lat_odd <= n_lat_odd + 1;
                if (n_lat_odd < 4) $display("AVISO tb_vram_uma: latencia %0d en t=%0t", t_now - t_acc, $time);
            end
        end
    end
endmodule
