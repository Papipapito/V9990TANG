//
// uma.sv
//
// BSD 3-Clause License
// 
// Copyright (c) 2024, Shinobu Hashimoto
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

interface UMA_IF #(parameter COUNT = 2);
    logic [23:0]    ADDR[0:COUNT-1];    // アドレスオフセット
    logic CLK14M_EN;
    logic CLK21M_EN;
    logic CLK25M_EN;

    // ホスト側ポート
    modport HOST (
                    output ADDR
                );

    // ホスト側ポート
    modport CLK (
                    input CLK14M_EN, CLK21M_EN, CLK25M_EN
                );

    // メモリ側ポート
    modport DEVICE (
                    input  ADDR,
                    output CLK14M_EN, CLK21M_EN, CLK25M_EN
                );
endinterface

module UMA #(
    parameter COUNT         = 2,
    parameter DIV           = 30,       // 3.58MHz の分周値
    parameter DELAY         = 0,        // 3.58MHz クロックエッジからメモリアクセスまでのディレイ
    parameter SYNC_CLK_EN   = 1,        // CLK_EN で同期をとる
    // V9990TANG (hito 4): AUTO REFRESH propio de la SDRAM, en el canal 0
    parameter INT_REFRESH   = 1,                    // 1 = temporizador de refresco interno
    parameter REFRESH_CYCLES= 780,                  // ciclos de CLK sin ningun AUTO REFRESH tras los que se pide uno
                                                    // (7,22 us a 108 MHz, 7,26 a 107,386: REFRESH_CYCLES de wv_to_sdram.v del MoonTANG)
    parameter REFRESH_ESC   = 2 * REFRESH_CYCLES,   // ciclos sin AUTO REFRESH a partir de los que el interno gana a un R/W del canal 0
    parameter DBG_W         = 16                    // ancho de los contadores de depuracion
) (
    input   wire            RESET_n,
    input   wire            CLK,
    input   wire            CLK_EN,
    RAM_IF.HOST             Primary,
    RAM_IF.DEVICE           Secondary[0:COUNT-1],
    UMA_IF.DEVICE           Uma,

    // V9990TANG: depuracion del refresco (se pueden dejar sin conectar)
    output  reg [DBG_W-1:0] DBG_RF_INT,             // AUTO REFRESH emitidos por el temporizador interno
    output  reg [DBG_W-1:0] DBG_RF_CH0,             // AUTO REFRESH por el RFSH reenviado del canal 0
    output  reg [DBG_W-1:0] DBG_RF_CH1,             // AUTO REFRESH por el RAM_RF del canal 1
    output  reg [DBG_W-1:0] DBG_RF_ESC,             // escalaciones: R/W del canal 0 aplazado una ranura
    output  reg [11:0]      DBG_RF_MAXGAP,          // mayor intervalo entre dos AUTO REFRESH, en ciclos de CLK menos 1 (satura en 4095)
    output  reg             DBG_RF_STB              // un ciclo por cada AUTO REFRESH presentado a Primary
);
    localparam CLK_OFFSET = 7'd2;    // TIMING より 2clk 速く CLK_EN を出力
    localparam DIV14MHz = 15;
    localparam DIV21MHz = 5;
    localparam DIV25MHz = 13;

    localparam MRAM_EXEC_DELAY = 2;
    localparam VRAM_EXEC_DELAY = 2;

    /***************************************************************
     * 3.58MHz に同期して 10.74MHz 毎にメモリ切り替え
     ***************************************************************/
    localparam DIVCNT_TOP   = 0;//(DELAY);

    localparam DIVCNT_25M_0 = (DIVCNT_TOP + DIV * 0 / 7);
    localparam DIVCNT_25M_1 = (DIVCNT_TOP + DIV * 1 / 7);
    localparam DIVCNT_25M_2 = (DIVCNT_TOP + DIV * 2 / 7);
    localparam DIVCNT_25M_3 = (DIVCNT_TOP + DIV * 3 / 7);
    localparam DIVCNT_25M_4 = (DIVCNT_TOP + DIV * 4 / 7);
    localparam DIVCNT_25M_5 = (DIVCNT_TOP + DIV * 5 / 7);
    localparam DIVCNT_25M_6 = (DIVCNT_TOP + DIV * 6 / 7);

    localparam DIVCNT_21M_0 = (DIVCNT_TOP + DIV * 0 / 6);
    localparam DIVCNT_21M_1 = (DIVCNT_TOP + DIV * 1 / 6);
    localparam DIVCNT_21M_2 = (DIVCNT_TOP + DIV * 2 / 6);
    localparam DIVCNT_21M_3 = (DIVCNT_TOP + DIV * 3 / 6);
    localparam DIVCNT_21M_4 = (DIVCNT_TOP + DIV * 4 / 6);
    localparam DIVCNT_21M_5 = (DIVCNT_TOP + DIV * 5 / 6);

    localparam DIVCNT_14M_0 = (DIVCNT_TOP + DIV * 0 / 4);
    localparam DIVCNT_14M_1 = (DIVCNT_TOP + DIV * 1 / 4);
    localparam DIVCNT_14M_2 = (DIVCNT_TOP + DIV * 2 / 4);
    localparam DIVCNT_14M_3 = (DIVCNT_TOP + DIV * 3 / 4);

    localparam DIVCNT_10M_0 = (DIVCNT_TOP + DIV * 0 / 3);
    localparam DIVCNT_10M_1 = (DIVCNT_TOP + DIV * 1 / 3);
    localparam DIVCNT_10M_2 = (DIVCNT_TOP + DIV * 2 / 3);

    logic [$clog2(DIV)-1:0] mem_cnt;
if(SYNC_CLK_EN == 1) begin
    // MSX の 3.58MHz に同期
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                  mem_cnt <= 0;
        else if(CLK_EN)               mem_cnt <= 0;
        else if(mem_cnt != (DIV - 1)) mem_cnt <= mem_cnt + 1'd1;
    end
end
else if(SYNC_CLK_EN == 2) begin
    // 最初だけ MSX の 3.58MHz に同期
    reg sync_flag;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)    sync_flag <= 0;
        else if(CLK_EN) sync_flag <= 1;
    end

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                  mem_cnt <= 0;
        else if(mem_cnt == (DIV - 1)) mem_cnt <= 0;
        else if(sync_flag)            mem_cnt <= mem_cnt + 1'd1;
    end
end
else begin
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                  mem_cnt <= 0;
        else if(mem_cnt == (DIV - 1)) mem_cnt <= 0;
        else                          mem_cnt <= mem_cnt + 1'd1;
    end
end

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                       Uma.CLK25M_EN <= 0;
        else if(mem_cnt == (DIVCNT_25M_0)) Uma.CLK25M_EN <= 1;
        else if(mem_cnt == (DIVCNT_25M_1)) Uma.CLK25M_EN <= 1;
        else if(mem_cnt == (DIVCNT_25M_2)) Uma.CLK25M_EN <= 1;
        else if(mem_cnt == (DIVCNT_25M_3)) Uma.CLK25M_EN <= 1;
        else if(mem_cnt == (DIVCNT_25M_4)) Uma.CLK25M_EN <= 1;
        else if(mem_cnt == (DIVCNT_25M_5)) Uma.CLK25M_EN <= 1;
        else if(mem_cnt == (DIVCNT_25M_6)) Uma.CLK25M_EN <= 1;
        else                               Uma.CLK25M_EN <= 0;
    end

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                       Uma.CLK21M_EN <= 0;
        else if(mem_cnt == (DIVCNT_21M_0)) Uma.CLK21M_EN <= 1;
        else if(mem_cnt == (DIVCNT_21M_1)) Uma.CLK21M_EN <= 1;
        else if(mem_cnt == (DIVCNT_21M_2)) Uma.CLK21M_EN <= 1;
        else if(mem_cnt == (DIVCNT_21M_3)) Uma.CLK21M_EN <= 1;
        else if(mem_cnt == (DIVCNT_21M_4)) Uma.CLK21M_EN <= 1;
        else if(mem_cnt == (DIVCNT_21M_5)) Uma.CLK21M_EN <= 1;
        else                               Uma.CLK21M_EN <= 0;
    end

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                       Uma.CLK14M_EN <= 0;
        else if(mem_cnt == (DIVCNT_14M_0)) Uma.CLK14M_EN <= 1;
        else if(mem_cnt == (DIVCNT_14M_1)) Uma.CLK14M_EN <= 1;
        else if(mem_cnt == (DIVCNT_14M_2)) Uma.CLK14M_EN <= 1;
        else if(mem_cnt == (DIVCNT_14M_3)) Uma.CLK14M_EN <= 1;
        else                               Uma.CLK14M_EN <= 0;
    end

    logic timing_toggle;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            Secondary[0].TIMING <= 0;
            Secondary[1].TIMING <= 0;
            timing_toggle <= 0;
        end
        else if(mem_cnt == (DIVCNT_10M_0 + CLK_OFFSET) ||
                mem_cnt == (DIVCNT_10M_1 + CLK_OFFSET) ||
                mem_cnt == (DIVCNT_10M_2 + CLK_OFFSET) ) begin
            Secondary[0].TIMING <= ~timing_toggle;
            Secondary[1].TIMING <= timing_toggle;
            timing_toggle <= ~timing_toggle;
        end
        else begin
            Secondary[0].TIMING <= 0;
            Secondary[1].TIMING <= 0;
        end
    end

    /***************************************************************
     * 処理完了タイミング
     ***************************************************************/
    wire done = exec_timing[0] || exec_timing[1];

    /***************************************************************
     * 切り替えの 1クロック後に RAM へデータ送信
     ***************************************************************/
    wire                               exec_timing[0:COUNT-1];   // TIMING 1~2クロック遅延
    reg                                done_delay;               // done 1クロック遅延
    reg                                processing[0:COUNT-1];    // 処理中フラグ
    reg                                done_ch[0:COUNT-1];       // 処理完了フラグ
    reg                                prev_oe_n[0:COUNT-1];     // 1クロック前の OE_n
    reg                                prev_we_n[0:COUNT-1];     // 1クロック前の WE_n
    reg                                prev_rfsh_n[0:COUNT-1];   // 1クロック前の RFSH_n
    reg                                save_oe[0:COUNT-1];       // OE 要求の保持
    reg                                save_we[0:COUNT-1];       // WE 要求の保持
    reg                                save_rfsh[0:COUNT-1];     // RFSH 要求の保持
    reg [$bits(Primary.ADDR)-1:0]      save_addr[0:COUNT-1];     // OE_n, WE_n エッジ検出時の ADDR を保持
    reg [$bits(Primary.DIN)-1:0]       save_din[0:COUNT-1];      // WE_n エッジ検出時の DIN を保持
    reg [$bits(Primary.DIN_SIZE)-1:0]  save_din_size[0:COUNT-1]; // WE_n エッジ検出時の DIN_SIZE を保持
    wire                               det_oe[0:COUNT-1];        // OE_n の H->L 検出
    wire                               det_we[0:COUNT-1];        // WE_n の H->L 検出
    wire                               det_rfsh[0:COUNT-1];      // RFSH_n の H->L 検出
    wire                               det_any[0:COUNT-1];       // OE_n, WE_n, RFSH_n の H->L 検出
    wire                               req_oe[0:COUNT-1];
    wire                               req_we[0:COUNT-1];
    wire                               req_rfsh[0:COUNT-1];
    wire                               req_any[0:COUNT-1];
    wire [$bits(Primary.ADDR)-1:0]     req_addr[0:COUNT-1];      // Primary へ渡す ADDR 値
    wire [$bits(Primary.DIN)-1:0]      req_din[0:COUNT-1];       // Primary へ渡す DIN 値
    wire [$bits(Primary.DIN_SIZE)-1:0] req_din_size[0:COUNT-1];  // Primary へ渡す DIN_SIZE 値

    // V9990TANG (hito 4): que se emite en cada ranura. sdram.sv solo ejecuta
    // una operacion por ranura y, si ve R/W y RFSH a la vez, hace el R/W
    // (sdram.sv: STATE_ACTIVE); tnCart presentaba los dos y borraba save_rfsh
    // igualmente: el refresco se perdia. Ahora el R/W gana la ranura y el RFSH
    // sigue pendiente hasta una ranura sin R/W del mismo canal.
    wire                               rw_req[0:COUNT-1];        // OE o WE pendiente (o detectado ahora)
    wire                               defer_rw[0:COUNT-1];      // el R/W cede la ranura (escalacion del refresco interno, solo canal 0)
    wire                               grant_rw[0:COUNT-1];      // esta ranura emite el R/W del canal
    wire                               grant_rf[0:COUNT-1];      // esta ranura emite el RFSH del canal (sin R/W)
    wire                               grant_any[0:COUNT-1];     // esta ranura emite una operacion del cliente
    reg                                proc_rw[0:COUNT-1];       // la operacion en curso es un R/W (DOUT se captura solo entonces)

    reg [1:0]                          exec_timing_buff[0:COUNT-1];
    assign exec_timing[0] = exec_timing_buff[0][MRAM_EXEC_DELAY-1]; // MainRam は 1CLK 遅延
    assign exec_timing[1] = exec_timing_buff[1][VRAM_EXEC_DELAY-1]; // VideoRam は 2CLK 遅延

    /***************************************************************
     * V9990TANG (hito 4): refresco interno de la SDRAM
     *
     * La SDRAM pide 4096 AUTO REFRESH en 64 ms (uno cada 15,6 us). En
     * tnCart los traia el /RFSH del Z80 reenviado por la RAM o la
     * megaROM; el V9990 solo pide uno por linea y ninguno en standby
     * (t9990_timing.sv, MEM.STATE). Un cartucho solo V9990 se quedaria
     * sin refresco, asi que el UMA genera el suyo:
     *
     * - rf_age cuenta los ciclos desde el ultimo AUTO REFRESH que el UMA
     *   presento a Primary, venga de donde venga (interno, RFSH del
     *   canal 0 o RAM_RF del canal 1).
     * - Con REFRESH_CYCLES ciclos sin refresco se levanta int_req, que se
     *   sirve en la primera ranura exec_timing[0] sin R/W del canal 0.
     *   Nunca en exec_timing[1]: el canal 1 (V9990) no cambia.
     * - Con REFRESH_ESC ciclos (dos periodos) se levanta int_esc: el
     *   refresco interno gana tambien a un R/W del canal 0, que se queda
     *   en save_oe/save_we y sale en la siguiente ranura del canal 0
     *   (20 ciclos despues). Tras el refresco rf_age vuelve a 0, asi que
     *   cada refresco aplaza como mucho un R/W. Intervalo maximo entre
     *   refrescos: REFRESH_ESC + 20 ciclos = 1580 (14,63 us a 108 MHz,
     *   14,71 a 107,386); sin R/W que lo impida, REFRESH_CYCLES + 1 a
     *   REFRESH_CYCLES + 20 (781 a 800 ciclos).
     * - El refresco interno no pasa por processing, done_ch, proc_rw,
     *   Secondary[0].DOUT ni los ACK_n de los clientes: si pasara por
     *   done_ch, diez ciclos despues copiaria en Secondary[0].DOUT la
     *   lectura del canal 1 y la megaROM la pondria en el bus del Z80.
     *   Si coincide con un RFSH pendiente del canal 0 sale un solo AUTO
     *   REFRESH, que cuenta como del canal 0 y sirve a los dos.
     ***************************************************************/
    localparam AGE_MAX = 12'd4095;
    reg  [11:0]                        rf_age;                   // ciclos desde el ultimo AUTO REFRESH (satura)
    reg                                int_req;                  // refresco interno pedido (flag propio)
    reg                                int_esc;                  // refresco interno escalado: gana al R/W del canal 0
    wire                               int_issue;                // esta ranura emite el refresco interno
    wire                               ref_issue;                // esta ranura emite un AUTO REFRESH (de cualquier fuente)
    wire                               esc_issue;                // esta ranura aplaza un R/W del canal 0 por el refresco

    assign int_issue = exec_timing[0] && int_req && !grant_rw[0];
    assign esc_issue = exec_timing[0] && int_esc && rw_req[0];
    assign ref_issue = int_issue || grant_rf[0] || grant_rf[1];

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            rf_age  <= 0;
            int_req <= 0;
            int_esc <= 0;
        end
        else if(ref_issue) begin
            rf_age  <= 0;
            int_req <= 0;
            int_esc <= 0;
        end
        else begin
            if(rf_age != AGE_MAX)                                     rf_age  <= rf_age + 1'd1;
            if(INT_REFRESH != 0 && rf_age == (REFRESH_CYCLES - 1))    int_req <= 1;
            if(INT_REFRESH != 0 && rf_age == (REFRESH_ESC - 1))       int_esc <= 1;
        end
    end

    // contadores de depuracion
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            DBG_RF_INT    <= 0;
            DBG_RF_CH0    <= 0;
            DBG_RF_CH1    <= 0;
            DBG_RF_ESC    <= 0;
            DBG_RF_MAXGAP <= 0;
            DBG_RF_STB    <= 0;
        end
        else begin
            DBG_RF_STB <= ref_issue;
            if(grant_rf[0])             DBG_RF_CH0 <= DBG_RF_CH0 + 1'd1;
            else if(int_issue)          DBG_RF_INT <= DBG_RF_INT + 1'd1;
            if(grant_rf[1])             DBG_RF_CH1 <= DBG_RF_CH1 + 1'd1;
            if(esc_issue)               DBG_RF_ESC <= DBG_RF_ESC + 1'd1;
            if(ref_issue && rf_age > DBG_RF_MAXGAP) DBG_RF_MAXGAP <= rf_age;
        end
    end

    generate
        genvar process_ch;
        for(process_ch = 0; process_ch < COUNT; process_ch = process_ch + 1) begin: process
            // RAM 転送タイミング
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n) exec_timing_buff[process_ch] <= 0;
                else         exec_timing_buff[process_ch] <= {exec_timing_buff[process_ch][$bits(exec_timing_buff[process_ch])-2:0], Secondary[process_ch].TIMING};
            end

            // OE_n 遅延
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n) prev_oe_n[process_ch] <= 1;
                else         prev_oe_n[process_ch] <= Secondary[process_ch].OE_n;
            end

            // WE_n 遅延
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n) prev_we_n[process_ch] <= 1;
                else         prev_we_n[process_ch] <= Secondary[process_ch].WE_n;
            end

            // RFSH_n 遅延
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n) prev_rfsh_n[process_ch] <= 1;
                else         prev_rfsh_n[process_ch] <= Secondary[process_ch].RFSH_n;
            end

            // OE_n の H->L 検出
            assign det_oe[process_ch] = prev_oe_n[process_ch] && !Secondary[process_ch].OE_n;

            // WE_n の H->L 検出
            assign det_we[process_ch] = prev_we_n[process_ch] && !Secondary[process_ch].WE_n;

            // RFSH_n の H->L 検出
            assign det_rfsh[process_ch] = prev_rfsh_n[process_ch] && !Secondary[process_ch].RFSH_n;

            // OE_n, WE_n, RFSH_n のいずれかのエッジを検出
            assign det_any[process_ch] = det_we[process_ch] || det_oe[process_ch] || det_rfsh[process_ch];

            // OE 要求フラグ
            assign req_oe[process_ch] = det_oe[process_ch] || save_oe[process_ch];

            // WE 要求フラグ
            assign req_we[process_ch] = det_we[process_ch] || save_we[process_ch];

            // RFSH 要求フラグ
            assign req_rfsh[process_ch] = det_rfsh[process_ch] || save_rfsh[process_ch];

            // OE, WE, RFSH いずれかの要求フラグ
            assign req_any[process_ch] = req_we[process_ch] || req_oe[process_ch] || req_rfsh[process_ch];

            // V9990TANG: R/W o RFSH que emite esta ranura. El R/W tiene prioridad;
            // el RFSH solo sale en una ranura sin R/W (si no, se queda en save_rfsh).
            assign rw_req[process_ch]    = req_oe[process_ch] || req_we[process_ch];
            assign defer_rw[process_ch]  = (process_ch == 0) ? int_esc : 1'b0;
            assign grant_rw[process_ch]  = exec_timing[process_ch] && rw_req[process_ch] && !defer_rw[process_ch];
            assign grant_rf[process_ch]  = exec_timing[process_ch] && req_rfsh[process_ch] && !grant_rw[process_ch];
            assign grant_any[process_ch] = grant_rw[process_ch] || grant_rf[process_ch];

            // 各 ch の処理完了フラグ
            assign done_ch[process_ch] = done && processing[process_ch];

            // 処理中フラグ更新
            // V9990TANG: solo con una operacion emitida (tnCart: exec_timing && req_any)
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                    processing[process_ch] <= 0;
                else if(grant_any[process_ch])  processing[process_ch] <= 1;
                else if(done_ch[process_ch])    processing[process_ch] <= 0;
            end

            // V9990TANG: tipo de la operacion en curso
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                    proc_rw[process_ch] <= 0;
                else if(grant_any[process_ch])  proc_rw[process_ch] <= grant_rw[process_ch];
            end

            // DOUT 格納
            // V9990TANG: solo tras un R/W. Un RFSH no trae dato: tnCart copiaba aqui
            // Primary.DOUT igualmente, que tras un refresco es la ultima lectura del
            // otro canal. Con el RFSH aplazado (arriba) esa copia caeria en mitad
            // de la lectura siguiente del cliente (la megaROM pasa DOUT al bus del
            // Z80 mientras su /RD esta bajo, megarom_controller.sv).
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                                         Secondary[process_ch].DOUT <= 0;
                else if(done_ch[process_ch] && proc_rw[process_ch]) Secondary[process_ch].DOUT <= Primary.DOUT;
            end

            // ACK_n 更新
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                                         Secondary[process_ch].ACK_n <= 1;
                else if(det_any[process_ch])                         Secondary[process_ch].ACK_n <= 0;  // OE_n, WE_n, RFSH_n エッジ検出で ACK_n = 0
                else if(done_ch[process_ch] && !req_any[process_ch]) Secondary[process_ch].ACK_n <= 1;  // 処理完了で残りの処理がないなら ACK_n = 1
            end

            // OE_n の保持
            // V9990TANG: se borra cuando el R/W sale de verdad (grant_rw), no en
            // cualquier exec_timing con peticion
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                                        save_oe[process_ch] <= 0;
                else if(grant_rw[process_ch] && req_oe[process_ch]) save_oe[process_ch] <= 0;        // Primary.OE_n 更新のタイミングでクリア
                else if(det_oe[process_ch])                         save_oe[process_ch] <= 1;        // Secondary.OE_n の立下り検出でセット
            end

            // WE_n の保持
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                                        save_we[process_ch] <= 0;
                else if(grant_rw[process_ch] && req_we[process_ch]) save_we[process_ch] <= 0;        // Primary.WE_n 更新のタイミングでクリア
                else if(det_we[process_ch]                        ) save_we[process_ch] <= 1;        // Secondary.WE_n の立下り検出でセット
            end

            // RFSH_n の保持
            // V9990TANG: se borra solo si el RFSH se emitio (grant_rf); tnCart lo
            // borraba aunque la ranura la hubiera ocupado un R/W
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                    save_rfsh[process_ch] <= 0;
                else if(grant_rf[process_ch])   save_rfsh[process_ch] <= 0;    // Primary.RFSH_n 更新のタイミングでクリア
                else if(det_rfsh[process_ch])   save_rfsh[process_ch] <= 1;    // Secondary.RFSH_n の立下り検出でセット
            end

            // ADDR の保持
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                                      save_addr[process_ch] <= 0;
                else if(det_oe[process_ch] || det_we[process_ch]) save_addr[process_ch] <= Secondary[process_ch].ADDR;
            end

            // DIN の保持
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                save_din[process_ch] <= 0;
                else if(det_we[process_ch]) save_din[process_ch] <= Secondary[process_ch].DIN;
            end

            // DIN_SIZE の保持
            always_ff @(posedge CLK or negedge RESET_n) begin
                if(!RESET_n)                save_din_size[process_ch] <= 0;
                else if(det_oe[process_ch] || det_we[process_ch]) save_din_size[process_ch] <= Secondary[process_ch].DIN_SIZE;
            end

            // Primary へ渡すパラメータ
            assign req_addr[process_ch]     = (det_oe[process_ch] || det_we[process_ch]) ? Secondary[process_ch].ADDR     : save_addr[process_ch];
            assign req_din[process_ch]      =  det_we[process_ch]                        ? Secondary[process_ch].DIN      : save_din[process_ch];
            assign req_din_size[process_ch] = (det_oe[process_ch] || det_we[process_ch]) ? Secondary[process_ch].DIN_SIZE : save_din_size[process_ch];

        end
    endgenerate

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            Primary.ADDR <= 0;
            Primary.DIN <= 0;
            Primary.DIN_SIZE <= 0;
            Primary.OE_n <= 1;
            Primary.WE_n <= 1;
            Primary.RFSH_n <= 1;
        end
        else if(!Primary.ACK_n) begin
            Primary.OE_n     <= 1;
            Primary.WE_n     <= 1;
            Primary.RFSH_n   <= 1;
        end
        // V9990TANG: R/W o RFSH, nunca los dos (grant_rw / grant_rf); en el
        // canal 0 tambien el AUTO REFRESH interno (int_issue)
        else if(grant_any[0] || int_issue) begin
            Primary.ADDR     <= grant_rw[0] ? ((req_addr[0] + Uma.ADDR[0]) & 24'hFFFFFF) : 0;
            Primary.DIN      <= grant_rw[0] ? req_din[0] : 0;
            Primary.DIN_SIZE <= grant_rw[0] ? req_din_size[0] : 0;
            Primary.OE_n     <= !(grant_rw[0] && req_oe[0]);
            Primary.WE_n     <= !(grant_rw[0] && req_we[0]);
            Primary.RFSH_n   <= !(grant_rf[0] || int_issue);
        end
        else if(grant_any[1]) begin
            Primary.ADDR     <= grant_rw[1] ? ((req_addr[1] + Uma.ADDR[1]) & 24'hFFFFFF) : 0;
            Primary.DIN      <= grant_rw[1] ? req_din[1] : 0;
            Primary.DIN_SIZE <= grant_rw[1] ? req_din_size[1] : 0;
            Primary.OE_n     <= !(grant_rw[1] && req_oe[1]);
            Primary.WE_n     <= !(grant_rw[1] && req_we[1]);
            Primary.RFSH_n   <= !grant_rf[1];
        end
    end

endmodule

`default_nettype wire
