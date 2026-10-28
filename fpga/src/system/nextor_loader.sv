//
// nextor_loader.sv -- V9990TANG, configuracion v9990_megaram_nextor
//
// V9990TANG. Copyright (c) 2026, Papipapito. BSD 3-Clause (ver LICENSE).
//

`default_nettype none

/***************************************************************
 * V9990TANG: copia de la ROM de Nextor de la flash a la SDRAM
 *
 * Sustituye al paso STATE_LOAD_BIOS del BOOTLOADER de tnCart (que copiaba
 * 144 KB de la flash en 10_0000h a 70_0000h: Nextor y el FM-BIOS) en la
 * configuracion v9990_megaram_nextor. Del BOOTLOADER solo hace falta la
 * copia: el borrado de la megaROM ya lo hace MEGAROM_CLEAR (uno solo, sin
 * duplicar), el mapper y el FM-BIOS no existen, la PAC tampoco, y las
 * ordenes de flash de tncrom siguen sin servirse (MEGAROM_XFER_TIE). El
 * BOOTLOADER, ademas, bajaba READY (y con el SYS_RESET_n) en cada /RESET del
 * MSX, cosa que V9990TANG dejo de hacer en el hito 3 (cada cartucho mira
 * Bus.RESET_n). Usa el FLASH_SPI de tnCart sin cambios, siempre en modo
 * lectura (orden 03h): sus ramas de escritura y borrado quedan sin uso.
 *
 * Funcionamiento: tras RESET_n (PLL enganchado y SDRAM lista) espera a START
 * (el DONE de MEGAROM_CLEAR: los dos comparten el canal 0 del UMA por
 * EXPANSION_RAM, que hace OR de los clientes, y no pueden solaparse) y lee
 * SIZE bytes de la flash desde SRC_ADDR, de uno en uno con el protocolo de
 * FLASH_IF (Enable_n = 0, ACK_n 0 -> 1 tras la orden; por byte REQ_n = 0,
 * ACK_n = 0, REQ_n = 1, ACK_n = 1 con RData). Cada cuatro bytes escribe una
 * palabra de 32 bits en DST_ADDR (DIN_SIZE_32, el byte de la direccion
 * 4k + i en DIN[8i+7:8i], como MEGAROM_CLEAR) con el protocolo de RAM_IF
 * del UMA (WE_n = 0 con ADDR/DIN hasta ACK_n = 0; luego todo a 0 y espera a
 * ACK_n = 1). La escritura de una palabra se solapa con la lectura SPI de la
 * siguiente: la copia la marca el SPI (unos 58 ciclos de CLK_BASE por byte
 * con FLASH_CLK_DIV = 2: ~70 ms los 128 KB). Al acabar suelta la flash
 * (Enable_n = 1: /CS alto) y saca DONE = 1, con el puerto de la RAM en
 * reposo, hasta el siguiente RESET_n.
 *
 * Contrato con la integracion (main.sv):
 *  - DONE retiene SYS_RESET_n (SYSTEM_RESET_HOLD), y con el el SYS_READY de
 *    la guardia del top: BOOT_HOLD retiene al MSX durante la copia, con el
 *    tope de HOLD_CYCLES de esta configuracion (fail-open: si la copia no
 *    acaba, el MSX arranca con el cartucho mudo).
 *  - No emite refrescos: el UMA tiene su propio AUTO REFRESH.
 *  - SRC_ADDR, DST_ADDR y SIZE, multiplos de 4.
 ***************************************************************/
module NEXTOR_LOADER #(
    parameter [23:0]        SRC_ADDR = 24'h10_0000,     // flash
    parameter [23:0]        DST_ADDR = 24'h70_0000,     // SDRAM (canal 0 del UMA, base 0)
    parameter [23:0]        SIZE     = 24'h02_0000      // bytes
) (
    input   wire            RESET_n,
    input   wire            CLK,
    input   wire            START,
    FLASH_IF.HOST           Flash,
    RAM_IF.HOST             Ram,
    output  reg             DONE
);
`ifndef SYNTHESIS
    // synthesis translate_off
    initial begin
        if(SRC_ADDR[1:0] != 2'd0 || DST_ADDR[1:0] != 2'd0 || SIZE[1:0] != 2'd0 || SIZE == 0)
            $error("NEXTOR_LOADER: SRC_ADDR (%h), DST_ADDR (%h) y SIZE (%h) tienen que ser multiplos de 4 y SIZE > 0", SRC_ADDR, DST_ADDR, SIZE);
    end
    // synthesis translate_on
`endif

    localparam [21:0] LAST_W = DST_ADDR[23:2] + SIZE[23:2] - 22'd1;    // ultima palabra

    /***************************************************************
     * Lado de la flash
     ***************************************************************/
    typedef enum logic [2:0] {
        F_WAIT_START,   // esperando a START
        F_CMD_ACK,      // Enable_n = 0: espera ACK_n = 0 (orden aceptada)
        F_CMD_DONE,     // espera ACK_n = 1 (orden 03h + direccion enviadas)
        F_REQ,          // REQ_n = 0: espera ACK_n = 0
        F_DATA,         // REQ_n = 1: espera ACK_n = 1 (RData)
        F_PUSH,         // palabra completa: espera a que el escritor este libre
        F_END           // flash suelta
    } fstate_t;
    fstate_t fstate;

    logic [23:0] rcount;            // bytes leidos
    logic [31:0] word;              // palabra en curso
    logic [1:0]  bpos;              // byte de la palabra

    // escritor de la SDRAM
    logic        wpend;             // hay una palabra que escribir
    logic        wbusy;             // escritura en curso (WE_n bajo, o esperando ACK_n = 1)
    logic        wstrobe;           // WE_n = 0 (hasta ACK_n = 0)
    logic [31:0] wdata;
    logic [21:0] waddr;             // direccion de palabra de la siguiente escritura

    assign Flash.Address = SRC_ADDR;
    assign Flash.Mode    = FLASH::FLASH_MODE_READ;
    assign Flash.WData   = 8'h00;

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            fstate         <= F_WAIT_START;
            Flash.Enable_n <= 1'b1;
            Flash.REQ_n    <= 1'b1;
            rcount         <= 24'd0;
            word           <= 32'd0;
            bpos           <= 2'd0;
        end
        else begin
            case (fstate)
                F_WAIT_START:
                    if(START) begin
                        Flash.Enable_n <= 1'b0;
                        fstate <= F_CMD_ACK;
                    end
                F_CMD_ACK:
                    if(!Flash.ACK_n) fstate <= F_CMD_DONE;
                F_CMD_DONE:
                    if(Flash.ACK_n) begin
                        Flash.REQ_n <= 1'b0;
                        fstate <= F_REQ;
                    end
                F_REQ:
                    if(!Flash.ACK_n) begin
                        Flash.REQ_n <= 1'b1;
                        fstate <= F_DATA;
                    end
                F_DATA:
                    if(Flash.ACK_n) begin
                        word[8 * bpos +: 8] <= Flash.RData;
                        bpos   <= bpos + 2'd1;
                        rcount <= rcount + 24'd1;
                        if(bpos == 2'd3) fstate <= F_PUSH;
                        else begin
                            Flash.REQ_n <= 1'b0;
                            fstate <= F_REQ;
                        end
                    end
                F_PUSH:
                    if(!wpend) begin
                        if(rcount == SIZE) begin
                            Flash.Enable_n <= 1'b1;
                            fstate <= F_END;
                        end
                        else begin
                            Flash.REQ_n <= 1'b0;
                            fstate <= F_REQ;
                        end
                    end
                default: ;
            endcase
        end
    end

    /***************************************************************
     * Lado de la SDRAM
     * El puerto se decodifica de wstrobe (EXPANSION_RAM hace OR de los
     * clientes: fuera de la escritura, todo a 0 y strobes a 1). El UMA toma
     * ADDR, DIN y DIN_SIZE en el flanco de bajada de WE_n.
     ***************************************************************/
    assign Ram.ADDR     = wstrobe ? {waddr, 2'b00} : 24'h00_0000;
    assign Ram.DIN      = wstrobe ? wdata : 32'h0000_0000;
    assign Ram.DIN_SIZE = wstrobe ? RAM::DIN_SIZE_32 : RAM::DIN_SIZE_8;
    assign Ram.WE_n     = !wstrobe;
    assign Ram.OE_n     = 1'b1;
    assign Ram.RFSH_n   = 1'b1;

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            wpend   <= 1'b0;
            wbusy   <= 1'b0;
            wstrobe <= 1'b0;
            wdata   <= 32'd0;
            waddr   <= DST_ADDR[23:2];
            DONE    <= 1'b0;
        end
        else begin
            // palabra nueva del lado de la flash (F_PUSH con el escritor libre)
            if(fstate == F_PUSH && !wpend) begin
                wpend <= 1'b1;
                wdata <= word;
            end
            else if(wpend && !wbusy) begin
                wbusy   <= 1'b1;
                wstrobe <= 1'b1;
            end
            else if(wstrobe) begin
                if(!Ram.ACK_n) wstrobe <= 1'b0;
            end
            else if(wbusy) begin
                if(Ram.ACK_n) begin
                    wbusy <= 1'b0;
                    wpend <= 1'b0;
                    waddr <= waddr + 22'd1;
                    if(waddr == LAST_W) DONE <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
