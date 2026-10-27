// ============================================================================
// sdram_host_model.sv -- la VRAM de mentira del banco del bus: sustituye a
// sdram.sv (y a la SDRAM) por su comportamiento visto desde el UMA, ciclo a
// ciclo, para que el core vea la latencia real del UMA de tnCart:
//
//   flanco A (estado IDLE con OE_n/WE_n/RFSH_n a 0, disparo por nivel como
//   LEVEL_TRIG = 1): ACK_n <= 0 y se guardan ADDR/DIN/DIN_SIZE;
//   A+6 (STATE_FETCH_RDATA_1): DOUT <= primera palabra de la rafaga;
//   A+7 (STATE_FETCH_RDATA_2 = STATE_INACTIVE_ACK): segunda palabra en 32_E /
//        32_O, ACK_n <= 1;  A+8 (STATE_END) -> IDLE;  A+9: acepta otra.
//
// Datos como sdram.sv con DQ de 32 bits y rafaga de 2: palabra w = ADDR[18:2]
// (los bits altos, el 78_0000h de la VRAM, se ignoran), segunda palabra de la
// rafaga w ^ 1; escrituras de 8/16/32 bits por carril y 32_E/32_O en los bytes
// pares/impares de las dos palabras; el refresco no hace nada.
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
// ============================================================================
`default_nettype none
module TB_SDRAM_HOST #(
    parameter AW = 17                   // palabras de 32 bits: 512 KB
) (
    input   wire        CLK,
    input   wire        RESET_n,
    RAM_IF.DEVICE       Ram
);
    reg [31:0] mem [0:(1<<AW)-1];
    integer i;
    initial for(i = 0; i < (1<<AW); i = i + 1) mem[i] = 32'h0;

    reg [3:0]  st;                      // 0 = IDLE, 1..8 = IDLE+1..STATE_END
    reg        is_rd, is_wr;
    reg [23:0] sa;
    reg [31:0] sd;
    reg [2:0]  ss;
    wire [AW-1:0] w0 = sa[AW+1:2];
    wire [AW-1:0] w1 = { sa[AW+1:3], ~sa[2] };

    assign Ram.TIMING = (st == 4'd0);

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            st        <= 0;
            Ram.ACK_n <= 1;
            Ram.DOUT  <= 0;
            is_rd     <= 0;
            is_wr     <= 0;
        end
        else begin
            case (st)
                4'd0: begin
                    if(!Ram.OE_n || !Ram.WE_n || !Ram.RFSH_n) begin
                        Ram.ACK_n <= 0;
                        st        <= 4'd1;
                        is_wr     <= (!Ram.OE_n || !Ram.WE_n) && !Ram.WE_n;
                        is_rd     <= (!Ram.OE_n || !Ram.WE_n) &&  Ram.WE_n;
                        sa        <= Ram.ADDR;
                        sd        <= Ram.DIN;
                        ss        <= Ram.DIN_SIZE;
                    end
                end
                4'd3: begin                 // STATE_READ_WRITE: la escritura (dos beats)
                    st <= st + 4'd1;
                    if(is_wr) begin
                        case (ss)
                            RAM::DIN_SIZE_32_E: begin
                                mem[w0][ 7: 0] <= sd[ 7: 0];
                                mem[w0][23:16] <= sd[15: 8];
                                mem[w1][ 7: 0] <= sd[23:16];
                                mem[w1][23:16] <= sd[31:24];
                            end
                            RAM::DIN_SIZE_32_O: begin
                                mem[w0][15: 8] <= sd[ 7: 0];
                                mem[w0][31:24] <= sd[15: 8];
                                mem[w1][15: 8] <= sd[23:16];
                                mem[w1][31:24] <= sd[31:24];
                            end
                            RAM::DIN_SIZE_32: mem[w0] <= sd;
                            RAM::DIN_SIZE_16: begin
                                if(sa[1]) mem[w0][31:16] <= sd[15:0];
                                else      mem[w0][15: 0] <= sd[15:0];
                            end
                            default: begin
                                case (sa[1:0])
                                    2'd0: mem[w0][ 7: 0] <= sd[7:0];
                                    2'd1: mem[w0][15: 8] <= sd[7:0];
                                    2'd2: mem[w0][23:16] <= sd[7:0];
                                    2'd3: mem[w0][31:24] <= sd[7:0];
                                endcase
                            end
                        endcase
                    end
                end
                4'd6: begin                 // STATE_FETCH_RDATA_1
                    st <= st + 4'd1;
                    if(is_rd) begin
                        if(ss == RAM::DIN_SIZE_32_E)      Ram.DOUT <= { mem[w0][23:16], mem[w0][7:0], mem[w0][23:16], mem[w0][7:0] };
                        else if(ss == RAM::DIN_SIZE_32_O) Ram.DOUT <= { mem[w0][31:24], mem[w0][15:8], mem[w0][31:24], mem[w0][15:8] };
                        else case (sa[1:0])
                            2'd0: Ram.DOUT <= mem[w0];
                            2'd1: Ram.DOUT <= { 8'h00,      mem[w0][31: 8] };
                            2'd2: Ram.DOUT <= { 16'h0000,   mem[w0][31:16] };
                            2'd3: Ram.DOUT <= { 24'h000000, mem[w0][31:24] };
                        endcase
                    end
                end
                4'd7: begin                 // STATE_FETCH_RDATA_2 / STATE_INACTIVE_ACK
                    st        <= st + 4'd1;
                    Ram.ACK_n <= 1;
                    if(is_rd) begin
                        if(ss == RAM::DIN_SIZE_32_E)      Ram.DOUT <= { mem[w1][23:16], mem[w1][7:0], Ram.DOUT[15:0] };
                        else if(ss == RAM::DIN_SIZE_32_O) Ram.DOUT <= { mem[w1][31:24], mem[w1][15:8], Ram.DOUT[15:0] };
                    end
                end
                4'd8: st <= 4'd0;           // STATE_END
                default: st <= st + 4'd1;
            endcase
        end
    end
endmodule
`default_nettype wire
