//
// tb_dpb_vs_gowin.sv -- compara sim/dpb_sim.sv con el DPB de Gowin (simlib/gw2a/prim_sim.v)
// en la configuracion de VIDEO_UPSCAN_BUFFER (4 y 8 bits, lectura en bypass por A,
// escritura por B, relojes distintos). Icarus: lo lanza run_dpb_check.sh.
//
`timescale 1ns/1ps
module tb_dpb_vs_gowin;
    reg clka = 0, clkb = 0;
    always #18.5 clka = ~clka;      // 27 MHz
    always #9.26 clkb = ~clkb;      // ~54 MHz (el DCLK real es mas lento; aqui solo importa el protocolo)

    reg  [11:0] ra4, wa4;  reg [3:0] wd4; reg we4;
    reg  [10:0] ra8, wa8;  reg [7:0] wd8; reg we8;
    wire [15:0] doa_m4, doa_g4, doa_m8, doa_g8, nc0, nc1, nc2, nc3;

    DPB #(.READ_MODE0(1'b0), .READ_MODE1(1'b0), .WRITE_MODE0(2'b00), .WRITE_MODE1(2'b00),
          .BIT_WIDTH_0(4), .BIT_WIDTH_1(4), .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC"))
      m4 (.DOA(doa_m4), .DOB(nc0), .DIA(16'h0), .DIB({12'h0, wd4}), .BLKSELA(3'b000), .BLKSELB(3'b000),
          .ADA({ra4, 2'b00}), .ADB({wa4, 2'b00}), .WREA(1'b0), .WREB(we4), .CLKA(clka), .CLKB(clkb),
          .CEA(1'b1), .CEB(1'b1), .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0));
    DPB_GOWIN #(.READ_MODE0(1'b0), .READ_MODE1(1'b0), .WRITE_MODE0(2'b00), .WRITE_MODE1(2'b00),
          .BIT_WIDTH_0(4), .BIT_WIDTH_1(4), .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC"))
      g4 (.DOA(doa_g4), .DOB(nc1), .DIA(16'h0), .DIB({12'h0, wd4}), .BLKSELA(3'b000), .BLKSELB(3'b000),
          .ADA({ra4, 2'b00}), .ADB({wa4, 2'b00}), .WREA(1'b0), .WREB(we4), .CLKA(clka), .CLKB(clkb),
          .CEA(1'b1), .CEB(1'b1), .OCEA(1'b1), .OCEB(1'b1), .RESETA(1'b0), .RESETB(1'b0));
    DPB #(.READ_MODE0(1'b0), .READ_MODE1(1'b0), .WRITE_MODE0(2'b00), .WRITE_MODE1(2'b00),
          .BIT_WIDTH_0(8), .BIT_WIDTH_1(8), .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC"))
      m8 (.DOA(doa_m8), .DOB(nc2), .DIA(16'h0), .DIB({8'h0, wd8}), .BLKSELA(3'b000), .BLKSELB(3'b000),
          .ADA({ra8, 3'b000}), .ADB({wa8, 3'b000}), .WREA(1'b0), .WREB(we8), .CLKA(clka), .CLKB(clkb),
          .CEA(1'b1), .CEB(1'b1), .OCEA(1'b0), .OCEB(1'b0), .RESETA(1'b0), .RESETB(1'b0));
    DPB_GOWIN #(.READ_MODE0(1'b0), .READ_MODE1(1'b0), .WRITE_MODE0(2'b00), .WRITE_MODE1(2'b00),
          .BIT_WIDTH_0(8), .BIT_WIDTH_1(8), .BLK_SEL_0(3'b000), .BLK_SEL_1(3'b000), .RESET_MODE("SYNC"))
      g8 (.DOA(doa_g8), .DOB(nc3), .DIA(16'h0), .DIB({8'h0, wd8}), .BLKSELA(3'b000), .BLKSELB(3'b000),
          .ADA({ra8, 3'b000}), .ADB({wa8, 3'b000}), .WREA(1'b0), .WREB(we8), .CLKA(clka), .CLKB(clkb),
          .CEA(1'b1), .CEB(1'b1), .OCEA(1'b0), .OCEB(1'b0), .RESETA(1'b0), .RESETB(1'b0));

    // escrituras aleatorias en la mitad alta de la direccion mientras se lee la baja y al reves
    // (como el buffer de lineas: nunca la misma direccion a la vez)
    integer seed = 1, phase = 0;
    always @(posedge clkb) begin
        we4 <= $random(seed); wd4 <= $random(seed); wa4 <= {phase[0] ^ 1'b1, 11'($random(seed))};
        we8 <= $random(seed); wd8 <= $random(seed); wa8 <= {phase[0] ^ 1'b1, 10'($random(seed))};
    end
    always @(posedge clka) begin
        ra4 <= {phase[0], 11'($random(seed))};
        ra8 <= {phase[0], 10'($random(seed))};
    end
    always #20000 phase = phase + 1;

    integer reads = 0, errs = 0, nz = 0;
    always @(negedge clka) begin
        if ($time > 100) begin
            reads = reads + 1;
            if (doa_g4[3:0] != 0 && doa_g8[7:0] != 0) nz = nz + 1;
            if (doa_m4[3:0] !== doa_g4[3:0] || doa_m8[7:0] !== doa_g8[7:0]) begin
                errs = errs + 1;
                if (errs < 10) $display("ERROR t=%0t 4b %h/%h 8b %h/%h", $time, doa_m4[3:0], doa_g4[3:0], doa_m8[7:0], doa_g8[7:0]);
            end
        end
    end
    initial begin
        we4 = 0; we8 = 0; wa4 = 0; wa8 = 0; ra4 = 0; ra8 = 0; wd4 = 0; wd8 = 0;
        #2000000;
        $display("DPB: %0d lecturas comparadas (%0d con dato distinto de 0 en los dos), %0d diferencias", reads, nz, errs);
        if (errs == 0 && reads > 1000 && nz > reads / 2) $display("RESULT PASS"); else $display("RESULT FAIL");
        $finish;
    end
endmodule
