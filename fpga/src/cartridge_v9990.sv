//
// cartridge_v9990.sv
//
// BSD 3-Clause License
// 
// Copyright (c) 2024, Shinobu Hashimoto
// Modificaciones del V9990TANG (rearme de 3 muestras): Copyright (c) 2026, Papipapito
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

/***************************************************************
 * V9990 カートリッジ
 ***************************************************************/
module CARTRIDGE_V9990 #(
    parameter [7:0]         IO_BASE_ADDR = 8'h60,
    parameter               MIRROR = 0
) (
    input   wire            RESET_n,
    input   wire            CLK,
    BUS_IF.CARTRIDGE        Bus,
    RAM_IF.HOST             Ram,
    UMA_IF.CLK              UmaClock,
    VIDEO_IF.OUT            Video
);
    /***************************************************************
     * MSXバス
     ***************************************************************/
    logic wait_n;
    logic int0_n;
    logic int1_n;
    assign Bus.INT_n = MIRROR || (int0_n && int1_n);
    assign Bus.WAIT_n = MIRROR || wait_n;

    wire cs_n = Bus.IORQ_n || (Bus.ADDR[7:4] != IO_BASE_ADDR[7:4]);
    logic [7:0] dout;

    /***************************************************************
     * Rearme de 3 muestras (V9990TANG, hito 5; patron 'served' + idle_cnt
     * de v9990_cpu_glue.v de la MSXimus Z):
     *  - el ciclo de E/S a nuestros puertos se presenta al core UNA vez:
     *    CSR_n/CSW_n bajan en la primera muestra con el ciclo y 'served' pasa
     *    a 1;
     *  - CSR_n/CSW_n se sueltan en la primera muestra sin el ciclo (el core
     *    solo mira el flanco de bajada);
     *  - 'served' solo se borra con RD_n y WR_n en reposo 3 muestras seguidas.
     *    Un rebote de RD_n/WR_n que pase el PIN_FILTER (2 muestras: un pulso
     *    de 2 ciclos) o uno de IORQ (que con el mux dura una vuelta, 9 ciclos,
     *    con RD_n/WR_n quietos) no presenta otro flanco al core. Se mira solo
     *    RD_n/WR_n, no cs_n, justo por eso: entre dos ciclos del Z80 RD_n y WR_n
     *    siempre vuelven a 1 al menos 1 T (10 ciclos a 10,74 MHz).
     *  - el bus de datos se conduce mientras 'served' marque una lectura: ni
     *    un rebote de IORQ ni uno de 2 muestras de RD_n lo sueltan a mitad de
     *    la lectura (antes, un rebote de RD_n que pasara el filtro dejaba el
     *    bus sin dato 2 ciclos unos 130 ns despues, por el camino retrasado).
     *    La cola de 2 ciclos de mas que esto da a Bus.BUSDIR_n tras el fin
     *    del ciclo no llega al slot: BOARD_REV1_BUS solo conduce con el /RD
     *    del pin a 0 y en una lectura que empezo con BUSDIR_n en reposo.
     ***************************************************************/
    wire io_rd   = !cs_n && !Bus.RD_n;
    wire io_wr   = !cs_n && !Bus.WR_n;
    wire io_any  = io_rd || io_wr;
    wire rw_idle = Bus.RD_n && Bus.WR_n;

    logic served;           // ciclo de E/S ya presentado al core
    logic served_rd;        // ... y era una lectura
    logic [1:0] idle_cnt;   // muestras seguidas con RD_n y WR_n en reposo (satura en 3)
    logic CSR_n;
    logic CSW_n;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            served    <= 0;
            served_rd <= 0;
            idle_cnt  <= 0;
            CSR_n     <= 1;
            CSW_n     <= 1;
        end
        else begin
            if(io_any && !served) begin
                served    <= 1;
                served_rd <= io_rd && !io_wr;
                CSR_n     <= !(io_rd && !io_wr);
                CSW_n     <= !io_wr;
            end
            else if(!io_any) begin
                CSR_n     <= 1;
                CSW_n     <= 1;
            end

            if(!rw_idle)                idle_cnt <= 0;
            else if(idle_cnt != 2'd3)   idle_cnt <= idle_cnt + 2'd1;
            if(rw_idle && idle_cnt >= 2'd2) begin   // 3a muestra en reposo seguida
                served    <= 0;
                served_rd <= 0;
            end
        end
    end

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            Bus.BUSDIR_n <= 1;
            Bus.DOUT <= 0;
        end
        else if(!MIRROR && served && served_rd) begin
            Bus.BUSDIR_n <= 0;
            Bus.DOUT <= dout;
        end
        else begin
            Bus.BUSDIR_n <= 1;
            Bus.DOUT <= 0;
        end
    end

    logic reset;
    logic [3:0] MODE;
    logic [7:0] CD_IN;
    always_ff @(posedge CLK) begin
        reset <= Bus.RESET_n && RESET_n;
        MODE <= Bus.ADDR[3:0];
        CD_IN <= Bus.DIN;
    end

    /***************************************************************
     * VDP
     ***************************************************************/
    logic [4:0] r;
    logic [4:0] g;
    logic [4:0] b;
    logic hs;
    logic vs;
    logic dclk_en;
    logic [2:0] reso;
    logic [18:0] addr;
    assign Ram.ADDR = {5'b00000, addr};
    T9990 u_vdp (
        .RESET_n(RESET_n && Bus.RESET_n),
        .CLK,
        .CLK_21M_EN(UmaClock.CLK21M_EN),
        .CLK_14M_EN(UmaClock.CLK14M_EN),
        .CLK_25M_EN(UmaClock.CLK25M_EN),

        .CSR_n,
        .CSW_n,
        .MODE,
        .CD_IN,
        .CD_OUT(dout),
        .WAIT_n(wait_n),
        .INT0_n(int0_n),
        .INT1_n(int1_n),
        .DREQ_n(),
        .VMREQ_n(),

        .RAM_REQ(Ram.TIMING),
        .RAM_OE_n(Ram.OE_n),
        .RAM_WE_n(Ram.WE_n),
        .RAM_RFSH_n(Ram.RFSH_n),
        .RAM_ADDR(addr),
        .RAM_DIN(Ram.DIN),
        .RAM_DIN_SIZE(Ram.DIN_SIZE),
        .RAM_DOUT(Ram.DOUT),
        .RAM_ACK_n(Ram.ACK_n),

        .HS(hs),
        .VS(vs),
        .R(r),
        .G(g),
        .B(b),
        .Ys(),
        .DCLK_EN(dclk_en),
        .RESO(reso),
        .HSCN(Video.HSCAN),
        .IL(Video.INTERLACE),
        .EO(Video.FIELD)
    );

    /***************************************************************
     * ビデオ出力
     ***************************************************************/
    reg dclk_en_ff[0:1];
    always_ff @(posedge CLK) dclk_en_ff[1] <= dclk_en;
    always_ff @(posedge CLK) dclk_en_ff[0] <= dclk_en_ff[1];
    
    assign Video.DCLK = dclk_en_ff[1] | dclk_en_ff[0];
    
    assign Video.R  = video_r;
    assign Video.G  = video_g;
    assign Video.B  = video_b;
    assign Video.HS_n = video_hs_n;
    assign Video.VS_n = video_vs_n;
    assign Video.RESOLUTION = video_reso;

    reg [7:0] video_r;
    reg [7:0] video_g;
    reg [7:0] video_b;
    reg       video_hs_n;
    reg       video_vs_n;
    VIDEO::RESOLUTION_t video_reso;

    always_ff @(posedge Video.DCLK) begin
        video_r    <= {r,r[4:2]};
        video_g    <= {g,g[4:2]};
        video_b    <= {b,b[4:2]};
        video_hs_n <= !hs;
        video_vs_n <= !vs;
        video_reso <= (reso == T9990_RESO::B1) ? VIDEO::RESOLUTION_B1 :
                      (reso == T9990_RESO::B2) ? VIDEO::RESOLUTION_B2 :
                      (reso == T9990_RESO::B3) ? VIDEO::RESOLUTION_B3 :
                      (reso == T9990_RESO::B4) ? VIDEO::RESOLUTION_B4 :
                      (reso == T9990_RESO::B5) ? VIDEO::RESOLUTION_B5 :
                      (reso == T9990_RESO::B6) ? VIDEO::RESOLUTION_B6 : VIDEO::RESOLUTION_B1;
    end
        

endmodule

`default_nettype wire
