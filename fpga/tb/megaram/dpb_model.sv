//
// dpb_model.sv -- modelo de simulacion minimo del bloque DPB de Gowin
// (BSRAM de doble puerto) para el scc.sv de tnCart en Verilator.
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito.
//
// Solo lo que usa scc.sv: anchura de 8 bits (BIT_WIDTH_0/1 = 8, direccion
// en AD[13:3]), lectura en modo bypass (READ_MODE = 0: el dato sale un
// flanco despues de la direccion), escritura en modo normal (WRITE_MODE =
// 00: en el ciclo de escritura la salida no cambia, como el prim_sim.v de
// Gowin 1.9.12) y reset sincrono de la salida. No se sintetiza: va solo en
// la lista de ficheros del banco.
//

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
    input  wire [15:0]  DIA,
    input  wire [15:0]  DIB,
    input  wire [2:0]   BLKSELA,
    input  wire [2:0]   BLKSELB,
    input  wire [13:0]  ADA,
    input  wire [13:0]  ADB,
    input  wire         WREA,
    input  wire         WREB,
    input  wire         CLKA,
    input  wire         CLKB,
    input  wire         CEA,
    input  wire         CEB,
    input  wire         OCEA,
    input  wire         OCEB,
    input  wire         RESETA,
    input  wire         RESETB
);
    reg [7:0] mem [0:2047];

    initial begin
        for(int i = 0; i < 2048; i++) mem[i] = 8'h00;
        DOA = 16'h0000;
        DOB = 16'h0000;
    end

    always @(posedge CLKA) begin
        if(RESETA)          DOA <= 16'h0000;
        else if(CEA) begin
            if(WREA)        mem[ADA[13:3]] <= DIA[7:0];
            else            DOA <= {8'h00, mem[ADA[13:3]]};
        end
    end

    always @(posedge CLKB) begin
        if(RESETB)          DOB <= 16'h0000;
        else if(CEB) begin
            if(WREB)        mem[ADB[13:3]] <= DIB[7:0];
            else            DOB <= {8'h00, mem[ADB[13:3]]};
        end
    end
endmodule

`default_nettype wire
