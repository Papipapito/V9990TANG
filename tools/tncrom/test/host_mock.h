//
// host_mock.h -- banco del host de tncrom: modelo del MSX y del cartucho
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito (V9990TANG).
//
// host_mock.c sustituye lo que tncrom pide a la BIOS y al DOS (RDSLT, WRSLT,
// ENASLT + LDIR, EXPTBL, BDOS, reboot) por un modelo en C:
//   - slot 0 sin expandir: BIOS (ROM, las escrituras no hacen nada);
//   - slot 1 expandido: 1-0 la megaROM de V9990TANG (modelo de
//     megarom_configure.sv + megarom_controller.sv + el registro de modo
//     SCC-I de cartridge_megarom.sv con la configuracion v9990_megaram:
//     ventana de 4 MB en 0, ENABLE_MEGA_SCC_I), 1-1..1-3 vacios;
//   - slot 2 sin expandir: vacio;
//   - slot 3 expandido: 3-0 RAM, 3-1..3-3 vacios.
// Todas las operaciones de bus con la megaROM pueden ir a una traza de texto
// que el banco de Verilator (fpga/tb/megaram, variante tncrom) reproduce
// contra el RTL: "W aaaa dd" escritura, "R aaaa dd" lectura con el dato que
// dio el modelo, "Z 0000 00" /RESET del MSX.
//

#ifndef _INCLUDE_HOST_MOCK_H_
#define _INCLUDE_HOST_MOCK_H_

#include <stdint.h>

#define HOST_CART_SLOT  (0x81)          // 1-0
#define HOST_RAM_SLOT   (0x83)          // 3-0
#define HOST_WIN_SIZE   (4u << 20)      // ventana de la megaROM (config/v9990_megaram.sv)
#define HOST_CLEAR_SIZE (32768u)        // MEGAROM_CLEAR

// estado visible del modelo
extern uint8_t  host_cart_ram[HOST_WIN_SIZE];   // la ventana de la SDRAM (offset 0 = 00_0000h)
extern int      host_dos_version;               // lo que devuelve bdos_get_version()
extern int      host_rebooted;                  // reboot() llamado
extern int      host_model_errors;              // accesos que el modelo no sabe contestar

// contenido de la SDRAM al encender: el patron del banco de Verilator
// (tb_megaram.sv, pat_word) para que la traza valga contra el RTL
uint8_t  host_pat_byte(uint32_t a);

// cartucho
void     cart_power_on(void);                   // valores de fabrica, patron y borrado de 32 KB
void     cart_msx_reset(void);                  // /RESET del MSX
uint8_t  cart_read(uint16_t addr);              // lectura de memoria en el subslot 1-0
void     cart_write(uint16_t addr, uint8_t data);
int      cart_plain_active(void);
uint8_t  cart_ctrl(int index);                  // ctrl_reg[index] sin pasar por la llave
uint8_t  cart_bank(int index);                  // BankReg[index]
int      cart_scc_wp(int index);                // WriteProtect_SCC[index]

// ficheros del DOS (en memoria)
void     host_file_add(const char *name, const uint8_t *data, uint32_t size);
void     host_files_clear(void);
const uint8_t *host_file_data(const char *name);

// ventana que lee 3Eh (RAM_SIZE[21:14]): 00h = 4 MB (v9990_megaram), C0h = 3 MB (tnCart)
extern uint8_t  host_win_reg;
// operaciones de bus con la megaROM desde el encendido (con o sin traza)
extern uint32_t host_cart_ops;

// traza
void     host_trace_op(char op, uint16_t a, uint8_t d);
int      host_trace_open(const char *path);
void     host_trace_close(void);
void     host_trace_comment(const char *text);
uint32_t host_trace_ops(void);

#endif
