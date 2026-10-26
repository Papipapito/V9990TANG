// tb_nl.v -- estimulo comun para el RTL (Verilator) y el netlist de Gowin (Icarus):
// en cada resolucion (B1..B6 y 720x480) escribe una linea (valor = funcion del
// indice) en una fila, la lee entera y vuelca OUT en cada ciclo. Dos vueltas con
// filas distintas.
`timescale 1ns/1ps
module tb_nl;
    reg        RESET_n = 0;
    reg  [2:0] RESO = 3'd0;
    reg        IN_CLK = 0, OUT_CLK = 0;
    reg        IN_EN = 0, IN_START = 0;
    reg  [1:0] IN_LINE = 0;
    reg  [7:0] IN = 0;
    reg        OUT_EN = 0, OUT_START = 0;
    reg  [1:0] OUT_LINE = 0;
    wire [7:0] OUT;

    NL_TOP dut (.RESET_n(RESET_n), .IN_RESOLUTION(RESO), .IN_CLK(IN_CLK), .IN_EN(IN_EN), .IN_START(IN_START),
                .IN_LINE(IN_LINE), .IN(IN), .OUT_CLK(OUT_CLK), .OUT_EN(OUT_EN), .OUT_START(OUT_START),
                .OUT_LINE(OUT_LINE), .OUT(OUT));

    always #5 IN_CLK = ~IN_CLK;
    always #7 OUT_CLK = ~OUT_CLK;

    integer i, r, rep;
    initial begin
        #103 RESET_n = 1;
        for (rep = 0; rep < 2; rep = rep + 1) begin
            for (r = 0; r < 7; r = r + 1) begin
                @(posedge IN_CLK) #1 RESO = r; IN_LINE = (r + rep) % 3; IN_START = 1;
                @(posedge IN_CLK) #1 IN_START = 0;
                for (i = 0; i < 800; i = i + 1) begin
                    @(posedge IN_CLK) #1 IN_EN = (i < 780); IN = (i * 37 + r * 11 + rep * 101) & 8'hFF;
                end
                @(posedge OUT_CLK) #1 OUT_LINE = (r + rep) % 3; OUT_START = 1;
                @(posedge OUT_CLK) #1 OUT_START = 0;
                for (i = 0; i < 740; i = i + 1) begin
                    @(posedge OUT_CLK) #1 OUT_EN = (i < 730);
                    $display("OUT %0d %0d %0d %0d", rep, r, i, OUT);
                end
            end
        end
        $finish;
    end
endmodule
