// ============================================================================
// sdram_model_bl.v -- modelo de la SDRAM SDR embebida del GW2AR-18 (64 Mbit,
//                     2M x 32: 4 bancos x 2048 filas x 256 columnas).
//
// Copia de MoonTANG tools/sim/board/sdram_model.v (mismas comprobaciones y la
// misma ventana de dato valido) con dos cambios para el banco del UMA de
// V9990TANG:
//
//   1. Rafagas. El MRS programa la longitud (A[2:0]: 1, 2, 4 u 8) y el modo de
//      escritura (A9: 0 = rafaga, 1 = una palabra). sdram.sv de tnCart usa
//      BL = 2: el segundo beat sale en la columna col ^ 1 (orden secuencial
//      dentro del par, el mismo que el entrelazado para BL = 2). El modelo
//      original solo hacia una palabra por READ/WRITE.
//   2. Verilator es de dos estados: con `VERILATOR, fuera de la ventana el
//      bus lleva un valor envenenado (POISON) en lugar de X, y la ventana se
//      publica en `dq_mode` (2 = dato valido) para que el banco compruebe en
//      el flanco de captura del controlador que lee dentro de ella. La
//      comprobacion de dato X en escritura la hace el banco (el controlador
//      tiene que estar conduciendo el bus en el flanco del WRITE).
//
// VENTANA DE DATO VALIDO (igual que el original). El RTL no tiene retardos de
// E/S, asi que aqui se suman los del camino real, todos referidos al flanco
// de reloj que ve el RTL:
//     beat k valido  desde  flanco(N+CL-1+k) + T_VALID
//                    hasta  flanco(N+CL+k)   + T_HOLD
//   T_VALID = salida del reloj de la FPGA al chip + tAC + entrada a la FPGA
//   T_HOLD  = salida del reloj (min)             + tOH + entrada (min)
// Fuera de la ventana el bus va a X (Icarus) o a POISON (Verilator).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module sdram_model #(
    parameter real T_VALID = 10.5,      // 3.0 (reloj) + 6.0 (tAC, CL=2) + 1.5 (entrada)
    parameter real T_HOLD  = 5.5        // 2.0 (reloj) + 2.5 (tOH)       + 1.0 (entrada)
) (
    input  wire        clk,
    input  wire        cke,
    input  wire        cs_n, ras_n, cas_n, we_n,
    input  wire [10:0] addr,
    input  wire [1:0]  ba,
    input  wire [3:0]  dqm,
    inout  wire [31:0] dq
);
    reg [31:0] mem [0:2097151];

    reg [10:0] row [0:3];
    reg [3:0]  row_open = 4'b0000;
    reg [2:0]  cl = 3'd0;               // 0 = sin programar
    reg [3:0]  bl = 4'd1;               // longitud de rafaga
    reg        wr_single = 1'b0;        // A9 del MRS: escritura de una palabra
    reg        mrs_done = 1'b0;

    integer n_act = 0, n_rd = 0, n_wr = 0, n_ref = 0, n_mrs = 0, n_err = 0;
    integer n_ref_before_mrs = 0;       // AUTO REFRESH antes del primer MRS (inicializacion)
    realtime t_act [0:3];
    realtime t_last_ref_or_act = 0;

    wire [3:0] cmd = {cs_n, ras_n, cas_n, we_n};
    localparam [3:0] C_MRS = 4'b0000, C_REF = 4'b0001, C_PRE = 4'b0010, C_ACT = 4'b0011,
                     C_WR  = 4'b0100, C_RD  = 4'b0101, C_NOP = 4'b0111;

`ifdef VERILATOR
    localparam [31:0] POISON = 32'hDEAD_BEEF;
`else
    localparam [31:0] POISON = 32'hxxxxxxxx;
`endif

    // tuberia de lectura: pv[j]/pd[j] = beat que se presenta j+1 flancos despues
    reg [15:0] pv = 16'd0;
    reg [31:0] pd [0:15];
    reg        pres_q = 1'b0;
    reg [31:0] dq_out = 32'd0;
    reg [1:0]  dq_mode = 2'd0;          // 0 = Z, 1 = X/POISON (transicion), 2 = dato
    assign dq = (dq_mode != 2'd0) ? ((dq_mode == 2'd2) ? dq_out : POISON) : 32'hzzzzzzzz;

    // rafaga de escritura en curso
    integer    wr_left = 0;
    reg [1:0]  wr_ba;
    reg [10:0] wr_row;
    reg [7:0]  wr_col;
    reg [7:0]  wr_k;

    integer b, i, k;
    reg [31:0] wtmp;
    reg        pres;
    reg [31:0] presd;
    reg [7:0]  col;

    task err(input [255:0] what);
        begin
            n_err = n_err + 1;
            $display("  [SDRAM %0t] ERROR: %0s", $time, what);
        end
    endtask

    // columna del beat k de una rafaga de longitud bl que empieza en c
    function [7:0] burst_col(input [7:0] c, input [7:0] kk, input [3:0] len);
        reg [7:0] m;
        begin
            m = len - 1;
            burst_col = (c & ~m) | ((c + kk) & m);
        end
    endfunction

    task write_word(input [1:0] wba, input [10:0] wrow, input [7:0] wcol);
        begin
            wtmp = mem[{wba, wrow, wcol}];
            for (b = 0; b < 4; b = b + 1)
                if (!dqm[b]) begin
`ifndef VERILATOR
                    if (^dq[b*8 +: 8] === 1'bx) err("WRITE con dato X/Z en el bus");
`endif
                    wtmp[b*8 +: 8] = dq[b*8 +: 8];
                end
            mem[{wba, wrow, wcol}] = wtmp;
        end
    endtask

    always @(posedge clk) if (cke) begin
        // beat que se presenta en este flanco, y avance de la tuberia
        pres  = pv[0];
        presd = pd[0];
        for (i = 0; i < 15; i = i + 1) begin
            pv[i] = pv[i + 1];
            pd[i] = pd[i + 1];
        end
        pv[15] = 1'b0;

        // beats 2.. de una rafaga de escritura
        if (wr_left > 0) begin
            write_word(wr_ba, wr_row, burst_col(wr_col, wr_k, bl));
            wr_k = wr_k + 1;
            wr_left = wr_left - 1;
        end

        case (cmd)
        C_MRS: begin
            n_mrs = n_mrs + 1;
            cl <= addr[6:4]; mrs_done <= 1'b1;
            case (addr[2:0])
                3'd0: bl <= 4'd1;
                3'd1: bl <= 4'd2;
                3'd2: bl <= 4'd4;
                3'd3: bl <= 4'd8;
                default: err("longitud de rafaga no soportada");
            endcase
            wr_single <= addr[9];
            if (addr[6:4] != 3'd2 && addr[6:4] != 3'd3) err("latencia CAS no soportada");
            if (row_open != 4'b0000) err("MRS con filas abiertas");
        end
        C_REF: begin
            n_ref = n_ref + 1;
            if (!mrs_done) n_ref_before_mrs = n_ref_before_mrs + 1;
            if (row_open != 4'b0000) err("REFRESH con filas abiertas");
            if ($realtime - t_last_ref_or_act < 55.0 && t_last_ref_or_act != 0) err("tRC violado antes de REF");
            t_last_ref_or_act = $realtime;
        end
        C_PRE: begin
            if (addr[10]) row_open <= 4'b0000;
            else          row_open[ba] <= 1'b0;
        end
        C_ACT: begin
            n_act = n_act + 1;
            if (row_open[ba]) err("ACT sobre un banco con fila abierta");
            if (!mrs_done) err("ACT antes del MRS");
            if ($realtime - t_last_ref_or_act < 55.0 && t_last_ref_or_act != 0) err("tRC violado antes de ACT");
            row[ba] <= addr; row_open[ba] <= 1'b1;
            t_act[ba] = $realtime; t_last_ref_or_act = $realtime;
        end
        C_RD: begin
            n_rd = n_rd + 1;
            if (!row_open[ba]) err("READ sin fila abierta");
            if ($realtime - t_act[ba] < 15.0) err("tRCD violado en READ");
            if (dqm != 4'b0000) err("READ con DQM activo");
            if (wr_left > 0) err("READ dentro de una rafaga de escritura");
            // beat k se presenta en el flanco N+CL-1+k: indice CL-2+k tras el avance
            for (k = 0; k < bl; k = k + 1) begin
                pv[cl - 2 + k] = 1'b1;
                pd[cl - 2 + k] = mem[{ba, row[ba], burst_col(addr[7:0], k[7:0], bl)}];
            end
            if (addr[10]) row_open[ba] <= 1'b0;         // auto-precarga
        end
        C_WR: begin
            n_wr = n_wr + 1;
            if (!row_open[ba]) err("WRITE sin fila abierta");
            if ($realtime - t_act[ba] < 15.0) err("tRCD violado en WRITE");
            write_word(ba, row[ba], addr[7:0]);
            if (!wr_single && bl > 1) begin
                wr_left = bl - 1; wr_k = 8'd1;
                wr_ba = ba; wr_row = row[ba]; wr_col = addr[7:0];
            end
            if (addr[10]) row_open[ba] <= 1'b0;
        end
        default: ;
        endcase

        // ---- conduccion del bus de datos con la ventana real ----
        if (pres) begin
            // el dato anterior (si lo hubo) se mantiene T_HOLD; despues X hasta T_VALID
            dq_mode <= #(T_HOLD) 2'd1;
            dq_out  <= #(T_VALID) presd;
            dq_mode <= #(T_VALID) 2'd2;
        end
        else if (pres_q) begin
            dq_mode <= #(T_HOLD) 2'd1;          // deja de ser valido
            dq_mode <= #(T_HOLD + 2.0) 2'd0;    // y suelta el bus
        end
        pres_q <= pres;
    end
endmodule

`default_nettype wire
