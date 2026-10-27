//
// led.sv
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

/***********************************************************************
 * LED インターフェース
 ***********************************************************************/
interface LED_IF;
    // LED 状態の定義
    typedef enum logic [1:0] {
        LED_STATE_OFF,  // 消灯
        LED_STATE_ON    // 点灯
    } LED_STATE_t;

    LED_STATE_t State;                  // LED の状態

    // ホスト側ポート
    modport HOST        (output State);

    // デバイス側ポート
    modport DEVICE      (input  State);

    // ダミー接続
    function automatic void connect_dummy();
        State = LED_STATE_OFF;
    endfunction
endinterface

/***********************************************************************
 * LED 制御モジュール
 ***********************************************************************/
module LED #(
    parameter       DELAY = 21_480_000, // 消灯までの遅延[clk]
    parameter       BLINK = 21_480_00   // 点滅周期[clk]
) (
    input   wire    CLK,                // 駆動クロック
    input   wire    RESET_n,            // リセット信号

    LED_IF.DEVICE   LedNextor,          // TF アクセス状態
    LED_IF.DEVICE   LedBoot,            // Boot アクセス状態

    output  reg     LedPort             // LED ポート
);

    /***************************************************************
     * ディレイカウンタ
     ***************************************************************/
    reg [$clog2(DELAY+1)-1:0] delay_count;

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            delay_count <= 0;
        end
        else begin
            if(LedNextor.State != LedNextor.LED_STATE_OFF) begin
                delay_count <= DELAY;
            end
            else if(delay_count != 0) begin
                delay_count <= delay_count - 1'd1;
            end
        end
    end

    /***************************************************************
     * 点滅カウンタ
     ***************************************************************/
    reg [$clog2(BLINK+1)-1:0] blink_count;

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            blink_count <= 0;
        end
        else begin
            if(LedBoot.State == LedNextor.LED_STATE_OFF) begin
                blink_count <= 0;
            end
            else if(blink_count == BLINK - 1) begin
                blink_count <= 0;
            end
            else begin
                blink_count <= blink_count + 1'd1;
            end
        end
    end

    /***************************************************************
     * LED ON/OFF
     ***************************************************************/
    always_ff @(posedge CLK) begin
        if(LedBoot.State != LedNextor.LED_STATE_OFF) begin
            LedPort <= (blink_count < (BLINK / 2)) ? 1'b1 : 1'b0;
        end
        else begin
            LedPort <= (delay_count != 0) ? 1'b1 : 1'b0;
        end
    end

endmodule

/***********************************************************************
 * V9990TANG: LED de estado (Copyright (c) 2026, Papipapito; misma licencia)
 *
 * Va en el dominio de CLK_27M (el cristal), asi que tambien parpadea con el
 * PLL sin enganchar. Codigos, de mas a menos prioritario (con BITS = 25 y
 * 27 MHz; LED = 1 encendido):
 *   CODE 0  error de reloj: rPLL base sin enganchar (en sync tambien el
 *           reloj del slot ausente o fuera de frecuencia) -> parpadeo rapido
 *           (6,4 Hz)
 *   CODE 2  solo xtal: sin reloj del slot (MSX apagado o cartucho mal
 *           metido) -> destello corto cada 1,24 s
 *   CODE 1  arrancando: rPLL enganchado, sistema aun no listo -> parpadeo
 *           lento (1,6 Hz). Normalmente no se ve (dura microsegundos, o
 *           milisegundos con el borrado de la megaROM); si se queda, el
 *           arranque fallo y el MSX ya corre sin el cartucho (tope de 50 ms).
 *           Desde la fusion con hito/bus el top pasa SYS_READY = sistema
 *           listo && BUS_OK (reloj del slot vivo y /RESET del slot suelto),
 *           asi que tambien se ve con el /RESET del MSX pulsado o con el bus
 *           del slot muerto (cartucho mudo). Por eso el codigo 2 va antes:
 *           en xtal sin MSX BUS_OK es 0 y, con el orden del hito 3, el LED
 *           diria "arrancando" en lugar de "sin reloj del slot"
 *   CODE 3  listo, con WAIT_TIMEOUT pegajoso -> doble destello cada 1,24 s
 *   CODE 4  listo, tras perder el enganche y recuperarlo (pegajoso) ->
 *           rafaga de cuatro destellos cada 1,24 s
 *   CODE 5  listo -> fijo
 * Apagado del todo: la FPGA no esta configurada (este modulo nunca lo saca).
 ***********************************************************************/
module STATUS_LED #(
    parameter int   SYNC = 0,           // CONFIG_BOARD::SYNC_CPU_CLK
    parameter int   BITS = 25           // ancho del divisor de parpadeo (25: 1,24 s a 27 MHz)
) (
    input   wire        CLK,            // CLK_27M
    input   wire        PLL_OK,
    input   wire        SYS_READY,      // sincronizado a CLK
    input   wire        SLOT_PRESENT,
    input   wire        WAIT_TIMEOUT,   // pegajoso
    input   wire        RELOCKED,       // pegajoso
    output  wire        LED,
    output  wire [2:0]  CODE
);
    reg [BITS-1:0] blink = '0;
    always_ff @(posedge CLK) blink <= blink + 1'd1;

    wire b0 = blink[BITS-1];    // 1,24 s
    wire b1 = blink[BITS-2];    // 621 ms
    wire b2 = blink[BITS-3];    // 311 ms
    wire b3 = blink[BITS-4];    // 155 ms

    wire [2:0] code = !PLL_OK                            ? 3'd0 :
                      ((SYNC == 0) && !SLOT_PRESENT)     ? 3'd2 :
                      !SYS_READY                         ? 3'd1 :
                      WAIT_TIMEOUT                       ? 3'd3 :
                      RELOCKED                           ? 3'd4 :
                                                           3'd5;

    reg       led_q  = 1'b0;
    reg [2:0] code_q = 3'd0;
    always_ff @(posedge CLK) begin
        code_q <= code;
        case(code)
            3'd0:    led_q <= b3;                   // rapido
            3'd1:    led_q <= b1;                   // lento
            3'd2:    led_q <= b0 & b1 & b2;         // destello corto
            3'd3:    led_q <= b0 & b2;              // doble destello
            3'd4:    led_q <= b0 & b3;              // cuatro destellos
            default: led_q <= 1'b1;                 // fijo
        endcase
    end
    assign LED  = led_q;
    assign CODE = code_q;
endmodule

`default_nettype wire
