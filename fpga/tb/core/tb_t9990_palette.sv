// tb_t9990_palette.sv -- paleta del tiny9990 por el puerto P#1, con los enables
// y la VRAM de la WonderTANG (UMA real de tnCart a DIV = 30 + modelo de
// sdram.sv, tb_vram_uma.sv). Derivado de tb_t9990_palette.sv del MSXimus Z (mismo
// autor): solo cambian los enables y la VRAM.
// Display encendido en B1 (asi DCLK_EN = P_EN compite con la CPU por la DPB de la
// paleta, como en placa). Escribe R, G y B por P#1 y los lee de vuelta por P#1:
//   A) las 64 entradas seguidas con autoincremento (R#13 = 0: PLTAIH = 0)
//   B) puntero directo: R#14 = e*4 + PLTP (R/G/B), una lectura, R#14 avanza uno
//   C) PLTAIH = 1 (R#13 = 10h): dos lecturas seguidas de G sin mover el puntero
// Dato leido (t9990_port.sv): {R_DATA[5], 2'b00, R_DATA[4:0]} -> R = {YS,00,R},
// G/B = {000,v}. G != B en todas las entradas: con el bug de la lectura de G
// (devolvia B) fallan todas las G. Salida: PAL_OK / PAL_FAIL.
//
// Solo Verilator. V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause.
`timescale 1ns/1ps
module tb_t9990_palette;
    reg clk = 0; always #4.63 clk = ~clk;
    reg rst_n = 0;

    reg csr_n = 1, csw_n = 1; reg [3:0] mode = 0; reg [7:0] cd_in = 0;
    wire [7:0] cd_out; wire wait_n, int0_n, int1_n, dreq_n, vmreq_n;
    wire ram_oe_n, ram_we_n, ram_rfsh_n; wire [18:0] ram_addr; wire [31:0] ram_din; wire [2:0] ram_din_size;
    wire [31:0] ram_dout; wire ram_ack_n, ram_req;
    wire clk21_en, clk14_en, clk25_en;
    wire hs, vs, dclk_en, il, eo, ys, hscn, pal; wire [4:0] r, g, b; wire [2:0] reso;

    TB_VRAM_UMA u_vram (
        .RESET_n(rst_n), .CLK(clk), .CH0_LOAD(1'b0), .ACK_DELAY(0),
        .CLK21M_EN(clk21_en), .CLK14M_EN(clk14_en), .CLK25M_EN(clk25_en),
        .RAM_REQ(ram_req), .RAM_OE_n(ram_oe_n), .RAM_WE_n(ram_we_n), .RAM_RFSH_n(ram_rfsh_n),
        .RAM_ADDR(ram_addr), .RAM_DIN(ram_din), .RAM_DIN_SIZE(ram_din_size),
        .RAM_DOUT(ram_dout), .RAM_ACK_n(ram_ack_n));

    T9990 dut (
        .RESET_n(rst_n), .CLK(clk),
        .CLK_21M_EN(clk21_en), .CLK_14M_EN(clk14_en), .CLK_25M_EN(clk25_en),
        .CSR_n(csr_n), .CSW_n(csw_n), .MODE(mode), .CD_IN(cd_in), .CD_OUT(cd_out),
        .WAIT_n(wait_n), .INT0_n(int0_n), .INT1_n(int1_n), .DREQ_n(dreq_n), .VMREQ_n(vmreq_n),
        .RAM_REQ(ram_req), .RAM_ACK_n(ram_ack_n),
        .RAM_OE_n(ram_oe_n), .RAM_WE_n(ram_we_n), .RAM_RFSH_n(ram_rfsh_n),
        .RAM_ADDR(ram_addr), .RAM_DIN(ram_din), .RAM_DIN_SIZE(ram_din_size), .RAM_DOUT(ram_dout),
        .HS(hs), .VS(vs), .R(r), .G(g), .B(b), .Ys(ys), .DCLK_EN(dclk_en),
        .RESO(reso), .HSCN(hscn), .IL(il), .EO(eo), .PAL(pal));

    task wr_port(input [3:0] p, input [7:0] d);
        begin
            @(posedge clk); mode <= p; cd_in <= d; csw_n <= 1'b0;
            repeat (3) @(posedge clk);
            while (!wait_n) @(posedge clk);
            csw_n <= 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask
    task rd_port(input [3:0] p, output [7:0] d);
        begin
            @(posedge clk); mode <= p; csr_n <= 1'b0;
            repeat (3) @(posedge clk);
            while (!wait_n) @(posedge clk);
            @(posedge clk); d = cd_out;
            csr_n <= 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask
    task wreg(input [5:0] n, input [7:0] v); begin wr_port(4'd4, {2'b00, n}); wr_port(4'd3, v); end endtask
    task rreg(input [5:0] n, output [7:0] v); begin wr_port(4'd4, {2'b01, n}); rd_port(4'd3, v); end endtask   // bit 6: sin autoincremento

    function [7:0] vr(input integer e); vr = ((e & 1) ? 8'h80 : 8'h00) | ((e * 5 + 3) & 8'h1F); endfunction
    function [7:0] vg(input integer e); vg = (e * 7 + 11) & 8'h1F; endfunction
    function [7:0] vb(input integer e); vb = (e * 3 + 29 + ((((e * 7 + 11) & 31) == ((e * 3 + 29) & 31)) ? 1 : 0)) & 8'h1F; endfunction
    function [7:0] vc(input integer comp, input integer ent); vc = (comp == 0) ? vr(ent) : ((comp == 1) ? vg(ent) : vb(ent)); endfunction

    integer e, c, nrd = 0, err_r = 0, err_g = 0, err_b = 0, err_ptr = 0, ngb = 0, n_pen = 0;
    reg [7:0] d, exp, r14;
    always @(posedge clk) if (dclk_en) n_pen = n_pen + 1;
    task chk(input integer comp, input integer ent, input [7:0] got, input [7:0] want, input string what);
        begin
            nrd = nrd + 1;
            if (got !== want) begin
                if (comp == 0) err_r = err_r + 1; else if (comp == 1) err_g = err_g + 1; else err_b = err_b + 1;
                if (err_r + err_g + err_b <= 8)
                    $display("ERROR %s: entrada %0d %s leido %02h, esperado %02h (R=%02h G=%02h B=%02h)", what, ent,
                             comp == 0 ? "R" : (comp == 1 ? "G" : "B"), got, want, vr(ent), vg(ent), vb(ent));
            end
        end
    endtask

    initial begin
        $timeformat(-9, 1, " ns", 0);
        repeat (8) @(posedge clk); rst_n <= 1; repeat (80) @(posedge clk);
        for (e = 0; e < 64; e = e + 1) if (vg(e) == vb(e)) ngb = ngb + 1;
        wreg(6'd6, 8'h82); wreg(6'd7, 8'h00); wreg(6'd8, 8'hC0);
        wreg(6'd13, 8'h00);
        // A)
        wreg(6'd14, 8'h00);
        for (e = 0; e < 64; e = e + 1) begin wr_port(4'd1, vr(e)); wr_port(4'd1, vg(e)); wr_port(4'd1, vb(e)); end
        wreg(6'd14, 8'h00);
        for (e = 0; e < 64; e = e + 1) for (c = 0; c < 3; c = c + 1) begin rd_port(4'd1, d); chk(c, e, d, vc(c, e), "A"); end
        rreg(6'd14, r14);
        if (r14 !== 8'h00) begin err_ptr = err_ptr + 1; $display("ERROR A: R#14 tras 192 lecturas = %02h (esperado 00)", r14); end
        // B)
        for (e = 0; e < 64; e = e + 1) for (c = 2; c >= 0; c = c - 1) begin
            wreg(6'd14, {e[5:0], c[1:0]});
            rd_port(4'd1, d); chk(c, e, d, vc(c, e), "B");
            rreg(6'd14, r14);
            exp = (c == 2) ? {e[5:0] + 6'd1, 2'b00} : {e[5:0], c[1:0] + 2'd1};
            if (r14 !== exp) begin err_ptr = err_ptr + 1; if (err_ptr <= 4) $display("ERROR B: R#14 tras leer %0d/%0d = %02h (esperado %02h)", e, c, r14, exp); end
        end
        // C)
        wreg(6'd13, 8'h10);
        for (e = 0; e < 64; e = e + 7) begin
            wreg(6'd14, {e[5:0], 2'b01});
            rd_port(4'd1, d); chk(1, e, d, vg(e), "C1");
            rd_port(4'd1, d); chk(1, e, d, vg(e), "C2");
            rreg(6'd14, r14);
            if (r14 !== {e[5:0], 2'b01}) begin err_ptr = err_ptr + 1; $display("ERROR C: R#14 = %02h con PLTAIH=1 (esperado %02h)", r14, {e[5:0], 2'b01}); end
        end
        $display("paleta: %0d lecturas P#1 | malas R=%0d G=%0d B=%0d | puntero R#14 mal=%0d | entradas con G==B=%0d | ciclos con DCLK_EN=%0d | RESO=%0d | ranuras perdidas=%0d",
                 nrd, err_r, err_g, err_b, err_ptr, ngb, n_pen, reso, dut.u_ram.lost_slots);
        if (err_r + err_g + err_b + err_ptr == 0 && ngb == 0 && n_pen > 0 && dut.u_ram.lost_slots == 0) $display("PAL_OK");
        else $display("PAL_FAIL");
        $finish;
    end
    initial begin #400000000; $display("TB_TIMEOUT"); $finish; end
endmodule
