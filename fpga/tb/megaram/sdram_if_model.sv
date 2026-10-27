//
// sdram_if_model.sv -- modelo de ciclo del lado RAM_IF de sdram.sv (tnCart)
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito.
//
// Reproduce lo que el UMA ve de fpga/src/peripheral/ram/sdram.sv, ciclo a
// ciclo y sin el chip: TIMING = (estado == IDLE); con OE_n, WE_n o RFSH_n
// a nivel bajo en IDLE arranca una secuencia fija de 9 estados (IDLE..END),
// ACK_n baja en IDLE (STATE_ACTIVE_ACK) y sube en IDLE+7
// (STATE_INACTIVE_ACK); la lectura carga DOUT en IDLE+6
// (STATE_FETCH_RDATA_1) y, para DIN_SIZE_32_E/_O, otra vez en IDLE+7 con el
// segundo dato de la rafaga de 2; la escritura se hace en IDLE+3
// (STATE_READ_WRITE) con las mascaras DQM de sdram.sv. Lectura o escritura
// tienen prioridad sobre el refresco pedido en la misma secuencia (como en
// sdram.sv, que entonces no lo hace). READY sube tras INIT_CYCLES ciclos
// (los 32 estados de inicializacion de sdram.sv).
//
// La memoria son 8 MB (2 M palabras de 32 bits, direccion de byte
// ADDR[22:0]); el banco la lee y escribe por mem[] directamente.
//

`default_nettype none

module SDRAM_IF_MODEL #(
    parameter INIT_CYCLES = 32
) (
    input  wire     CLK,
    input  wire     RESET_n,
    output reg      READY,
    RAM_IF.DEVICE   Ram
);
    logic [31:0] mem [0:(1<<21)-1];

    // contadores para el informe del banco
    int unsigned n_read  = 0;
    int unsigned n_write = 0;
    int unsigned n_rfsh  = 0;
    int unsigned n_rfsh_dropped = 0;   // RFSH pedido junto a una lectura/escritura

    logic [3:0]  state;         // 0 = IDLE ... 8 = END
    logic [7:0]  init_cnt;
    logic        is_rd, is_wr;
    logic [23:0] sa;
    logic [31:0] sdin;
    logic [2:0]  ssize;

    wire begin_rd   = !Ram.OE_n;
    wire begin_wr   = !Ram.WE_n;
    wire begin_rfsh = !Ram.RFSH_n;

    assign Ram.TIMING = READY && (state == 0);

    wire [20:0] w0 = sa[22:2];
    wire [20:0] w1 = {sa[22:3], ~sa[2]};     // segundo dato de la rafaga de 2

    function automatic logic [31:0] put_bytes(input logic [31:0] old, input logic [31:0] dq, input logic [3:0] dqm);
        logic [31:0] r;
        for(int i = 0; i < 4; i++) r[i*8 +: 8] = dqm[i] ? old[i*8 +: 8] : dq[i*8 +: 8];
        return r;
    endfunction

    always @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            READY    <= 0;
            init_cnt <= 0;
            state    <= 0;
            Ram.ACK_n <= 1;
            Ram.DOUT <= 0;
            is_rd <= 0;
            is_wr <= 0;
        end
        else if(!READY) begin
            init_cnt <= init_cnt + 1'd1;
            if(init_cnt == INIT_CYCLES - 1) READY <= 1;
        end
        else begin
            case (state)
                0: begin
                    if(begin_rd || begin_wr || begin_rfsh) begin
                        state <= 1;
                        Ram.ACK_n <= 0;
                        sa    <= Ram.ADDR;
                        sdin  <= Ram.DIN;
                        ssize <= Ram.DIN_SIZE;
                        is_wr <= (begin_rd || begin_wr) && (Ram.WE_n == 0);
                        is_rd <= (begin_rd || begin_wr) && (Ram.WE_n != 0);
                        if(begin_rd || begin_wr) begin
                            if(Ram.WE_n == 0) n_write <= n_write + 1;
                            else              n_read  <= n_read + 1;
                            if(begin_rfsh)    n_rfsh_dropped <= n_rfsh_dropped + 1;
                        end
                        else n_rfsh <= n_rfsh + 1;
                    end
                end
                3: begin
                    state <= 4;
                    if(is_wr) begin
                        case (ssize)
                            RAM::DIN_SIZE_32_E: begin
                                mem[w0] <= put_bytes(mem[w0], {sdin[15:8], sdin[15:8], sdin[7:0], sdin[7:0]}, 4'b1010);
                                mem[w1] <= put_bytes(mem[w1], {sdin[31:24], sdin[31:24], sdin[23:16], sdin[23:16]}, 4'b1010);
                            end
                            RAM::DIN_SIZE_32_O: begin
                                mem[w0] <= put_bytes(mem[w0], {sdin[15:8], sdin[15:8], sdin[7:0], sdin[7:0]}, 4'b0101);
                                mem[w1] <= put_bytes(mem[w1], {sdin[31:24], sdin[31:24], sdin[23:16], sdin[23:16]}, 4'b0101);
                            end
                            RAM::DIN_SIZE_16:
                                mem[w0] <= put_bytes(mem[w0], {sdin[15:0], sdin[15:0]}, sa[1] ? 4'b0011 : 4'b1100);
                            RAM::DIN_SIZE_32:
                                mem[w0] <= sdin;
                            default:
                                mem[w0] <= put_bytes(mem[w0], {4{sdin[7:0]}},
                                                     (sa[1:0] == 2'd0) ? 4'b1110 :
                                                     (sa[1:0] == 2'd1) ? 4'b1101 :
                                                     (sa[1:0] == 2'd2) ? 4'b1011 : 4'b0111);
                        endcase
                    end
                end
                6: begin
                    state <= 7;
                    if(is_rd) begin
                        case (ssize)
                            RAM::DIN_SIZE_32_E: Ram.DOUT <= {mem[w0][23:16], mem[w0][7:0], mem[w0][23:16], mem[w0][7:0]};
                            RAM::DIN_SIZE_32_O: Ram.DOUT <= {mem[w0][31:24], mem[w0][15:8], mem[w0][31:24], mem[w0][15:8]};
                            default: case (sa[1:0])
                                2'd0: Ram.DOUT <= mem[w0];
                                2'd1: Ram.DOUT <= {8'h00,  mem[w0][31:8]};
                                2'd2: Ram.DOUT <= {16'h00, mem[w0][31:16]};
                                2'd3: Ram.DOUT <= {24'h00, mem[w0][31:24]};
                            endcase
                        endcase
                    end
                end
                7: begin
                    state <= 8;
                    Ram.ACK_n <= 1;
                    if(is_rd) begin
                        if(ssize == RAM::DIN_SIZE_32_E)      Ram.DOUT <= {mem[w1][23:16], mem[w1][7:0], Ram.DOUT[15:0]};
                        else if(ssize == RAM::DIN_SIZE_32_O) Ram.DOUT <= {mem[w1][31:24], mem[w1][15:8], Ram.DOUT[15:0]};
                    end
                end
                8: state <= 0;
                default: state <= state + 1'd1;
            endcase
        end
    end
endmodule

`default_nettype wire
