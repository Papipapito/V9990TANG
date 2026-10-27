// ============================================================================
// megaram_mock.sv -- MegaRAM de mentira para probar la segunda fuente del
// pre-WAIT (PREWAIT_MEM_EN = 1). Cumple el contrato de docs/notas/bus.md:
// baja Bus.WAIT_n como mucho 3 ciclos despues de ver la lectura por el camino
// retrasado (en el flanco WAIT_DLY + 1 contando desde el primer ciclo en que
// la ve: con WAIT_DLY = 2, el valor por defecto, esta en el limite del
// contrato, y con el slot expandido la placa ve su WAIT_n en D+5) y lo
// mantiene hasta que Bus.DOUT tiene el dato (LAT ciclos despues), en el mismo
// flanco en que sube WAIT_n.
// Contesta lecturas de memoria de su subranura en 4000h-BFFFh con un dato que
// depende de la direccion (dato_mock); fuera de esa ventana no pide espera.
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
// ============================================================================
`default_nettype none
module TB_MEGARAM_MOCK #(
    parameter WAIT_DLY = 2,
    parameter LAT      = 30
) (
    input   wire        RESET_n,
    input   wire        CLK,
    BUS_IF.CARTRIDGE    Bus
);
    function automatic [7:0] dato_mock(input [15:0] a);
        dato_mock = a[7:0] ^ a[15:8] ^ 8'h5A;
    endfunction

    wire rd = !Bus.SLTSL_n && !Bus.MERQ_n && !Bus.RD_n && (Bus.ADDR[15:14] == 2'b01 || Bus.ADDR[15:14] == 2'b10);
    reg        busy, done;
    reg [7:0]  cnt;
    reg [15:0] a_lat;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            busy         <= 0;
            done         <= 0;
            cnt          <= 0;
            Bus.WAIT_n   <= 1;
            Bus.DOUT     <= 0;
            Bus.BUSDIR_n <= 1;
        end
        else begin
            if(!busy && !done && rd) begin
                busy  <= 1;
                cnt   <= 0;
                a_lat <= Bus.ADDR;
            end
            else if(busy) begin
                cnt <= cnt + 8'd1;
                if(cnt == WAIT_DLY - 1) Bus.WAIT_n <= 0;
                if(cnt == LAT - 1) begin
                    Bus.WAIT_n   <= 1;
                    Bus.DOUT     <= dato_mock(a_lat);
                    Bus.BUSDIR_n <= 0;
                    busy         <= 0;
                    done         <= 1;
                end
            end
            if(Bus.RD_n) begin
                done         <= 0;
                Bus.BUSDIR_n <= 1;
                Bus.DOUT     <= 0;
                if(!busy) Bus.WAIT_n <= 1;
            end
        end
    end
    assign Bus.INT_n = 1;
endmodule
`default_nettype wire
