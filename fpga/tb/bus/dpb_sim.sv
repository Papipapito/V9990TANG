// ============================================================================
// dpb_sim.sv -- modelo de simulacion de la primitiva DPB de Gowin (BSRAM de
// doble puerto de 16 kbit) para compilar el tiny9990 con Verilator.
//
// Solo lo que usa el core: BIT_WIDTH 8 o 16 (igual en los dos puertos),
// READ_MODE 0 (lectura sincrona de un ciclo, sin registro de salida), WRITE_MODE
// 00 (normal: DO no cambia en un ciclo de escritura), RESET_MODE "SYNC" (RESETx
// pone a 0 el registro de salida en el flanco), BLKSEL ignorado.
// Direccionamiento (Gowin UG285): x16 -> palabra AD[13:4], AD[1:0] habilitan
// los bytes en escritura; x8 -> byte AD[13:3].
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
// ============================================================================
`default_nettype none
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
    output reg  [15:0]  DOA,
    output reg  [15:0]  DOB,
    input  wire         CLKA,
    input  wire         OCEA,
    input  wire         CEA,
    input  wire         RESETA,
    input  wire         WREA,
    input  wire         CLKB,
    input  wire         OCEB,
    input  wire         CEB,
    input  wire         RESETB,
    input  wire         WREB,
    input  wire [2:0]   BLKSELA,
    input  wire [2:0]   BLKSELB,
    input  wire [13:0]  ADA,
    input  wire [15:0]  DIA,
    input  wire [13:0]  ADB,
    input  wire [15:0]  DIB
);
    reg [7:0] mem [0:2047];
    integer i;
    initial begin
        for(i = 0; i < 2048; i = i + 1) mem[i] = 8'h00;
        DOA = 16'h0000;
        DOB = 16'h0000;
    end

    function automatic [10:0] byte_addr(input [13:0] ad, input integer w, input integer hi);
        if(w == 16) byte_addr = { ad[13:4], hi[0] };
        else        byte_addr = ad[13:3];
    endfunction

    always @(posedge CLKA) begin
        if(RESETA) DOA <= 16'h0000;
        else if(CEA) begin
            if(WREA) begin
                if(BIT_WIDTH_0 == 16) begin
                    if(ADA[0]) mem[byte_addr(ADA, 16, 0)] <= DIA[7:0];
                    if(ADA[1]) mem[byte_addr(ADA, 16, 1)] <= DIA[15:8];
                end
                else mem[byte_addr(ADA, 8, 0)] <= DIA[7:0];
            end
            else begin
                if(BIT_WIDTH_0 == 16) DOA <= { mem[byte_addr(ADA, 16, 1)], mem[byte_addr(ADA, 16, 0)] };
                else                  DOA <= { 8'h00, mem[byte_addr(ADA, 8, 0)] };
            end
        end
    end

    always @(posedge CLKB) begin
        if(RESETB) DOB <= 16'h0000;
        else if(CEB) begin
            if(WREB) begin
                if(BIT_WIDTH_1 == 16) begin
                    if(ADB[0]) mem[byte_addr(ADB, 16, 0)] <= DIB[7:0];
                    if(ADB[1]) mem[byte_addr(ADB, 16, 1)] <= DIB[15:8];
                end
                else mem[byte_addr(ADB, 8, 0)] <= DIB[7:0];
            end
            else begin
                if(BIT_WIDTH_1 == 16) DOB <= { mem[byte_addr(ADB, 16, 1)], mem[byte_addr(ADB, 16, 0)] };
                else                  DOB <= { 8'h00, mem[byte_addr(ADB, 8, 0)] };
            end
        end
    end
endmodule
`default_nettype wire
