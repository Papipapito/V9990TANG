// tb_dpb_model.v -- modelo de simulacion de la primitiva DPB de Gowin (BSRAM de
// doble puerto, 16 Kbit) para los bancos del core en Verilator. Solo cubre lo que
// instancia el tiny9990 (19 instancias): BIT_WIDTH_0 = BIT_WIDTH_1 = 16 u 8,
// READ_MODE 0 (bypass: la direccion se registra en el flanco y el dato sale tras
// el, un ciclo de latencia), WRITE_MODE 00 (normal: DO no cambia en una
// escritura), RESET_MODE "SYNC", BLK_SEL 0.
// Direccionamiento (Gowin UG285): x16 -> palabra = AD[13:4], AD[1:0] = byte
// enables de escritura; x8 -> byte = AD[13:3].
// No es sintetizable a proposito: solo lo compilan los run_*.sh de fpga/tb/core.
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
`timescale 1ns/1ps
module DPB #(
    parameter READ_MODE0  = 1'b0,
    parameter READ_MODE1  = 1'b0,
    parameter WRITE_MODE0 = 2'b00,
    parameter WRITE_MODE1 = 2'b00,
    parameter BIT_WIDTH_0 = 16,
    parameter BIT_WIDTH_1 = 16,
    parameter BLK_SEL_0   = 3'b000,
    parameter BLK_SEL_1   = 3'b000,
    parameter RESET_MODE  = "SYNC"
) (
    output reg  [15:0] DOA,
    output reg  [15:0] DOB,
    input  wire        CLKA,
    input  wire        OCEA,
    input  wire        CEA,
    input  wire        RESETA,
    input  wire        WREA,
    input  wire        CLKB,
    input  wire        OCEB,
    input  wire        CEB,
    input  wire        RESETB,
    input  wire        WREB,
    input  wire [2:0]  BLKSELA,
    input  wire [2:0]  BLKSELB,
    input  wire [13:0] ADA,
    input  wire [15:0] DIA,
    input  wire [13:0] ADB,
    input  wire [15:0] DIB
);
    // la memoria se guarda por bytes: 2048 x 8 en los dos modos
    reg [7:0] mem [0:2047];
    integer i;
    initial begin
        for (i = 0; i < 2048; i = i + 1) mem[i] = 8'h00;
        DOA = 16'h0000;
        DOB = 16'h0000;
    end

    // x16: palabra w -> bytes 2w (bajo) y 2w+1 (alto); x8: byte = AD[13:3]
    wire [10:0] a16a = {ADA[13:4], 1'b0};
    wire [10:0] a16b = {ADB[13:4], 1'b0};
    wire [10:0] a8a  = ADA[13:3];
    wire [10:0] a8b  = ADB[13:3];

    // el reset sincrono solo borra el registro de salida; la escritura sigue
    always @(posedge CLKA) begin
        if (CEA && WREA) begin
            if (BIT_WIDTH_0 == 16) begin
                if (ADA[0]) mem[a16a]     <= DIA[7:0];
                if (ADA[1]) mem[a16a + 1] <= DIA[15:8];
            end
            else mem[a8a] <= DIA[7:0];
        end
        if (RESETA)            DOA <= 16'h0000;
        else if (CEA && !WREA) DOA <= (BIT_WIDTH_0 == 16) ? {mem[a16a + 1], mem[a16a]} : {8'h00, mem[a8a]};
    end

    always @(posedge CLKB) begin
        if (CEB && WREB) begin
            if (BIT_WIDTH_1 == 16) begin
                if (ADB[0]) mem[a16b]     <= DIB[7:0];
                if (ADB[1]) mem[a16b + 1] <= DIB[15:8];
            end
            else mem[a8b] <= DIB[7:0];
        end
        if (RESETB)            DOB <= 16'h0000;
        else if (CEB && !WREB) DOB <= (BIT_WIDTH_1 == 16) ? {mem[a16b + 1], mem[a16b]} : {8'h00, mem[a8b]};
    end
endmodule
