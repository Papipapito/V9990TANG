//
// host_mock.c -- banco del host de tncrom: modelo del MSX y del cartucho
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito (V9990TANG).
//
// Ver host_mock.h. El modelo de la megaROM sigue el RTL de V9990TANG, con
// la referencia de cada regla:
//   megarom_configure.sv  llave (reg_protect), cs_reg_rd_n/cs_reg_wr_n,
//                         lectura de 00h-3Fh, rama !Bus.RESET_n, PLAIN0
//                         (plain_active), CS1/CS2_Mask con !ENABLE
//   megarom_controller.sv cs_mem_n (PLAIN0: 0000h-BFFFh), wr_mem_n,
//                         registros de banco (det_wr, BankRegAddrMask,
//                         BankEnable, !Plain), direccion addr_16/addr_8/
//                         addr_plain
//   cartridge_megarom.sv  registro de modo SCC-I (BFFEh/BFFFh) con
//                         BankEnable_SCC/WriteProtect_SCC
// Orden dentro de una escritura, como en el RTL: la RAM se escribe con los
// bancos y la proteccion de ANTES de la escritura (el UMA guarda ADDR al ver
// el flanco de WE_n, un ciclo despues de que el controlador lo calcule) y
// despues cambian los registros de banco y el modo SCC-I.
// No modela el sonido del SCC: una lectura de su ventana cuenta como error
// del modelo (tncrom no las hace).
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "host_mock.h"

// las funciones del DOS que se sustituyen (lib/bdos.h; su types.h no se lee:
// run.sh compila con -include host_types.h)
#include "../lib/bdos.h"

/***************************************************************
 * patron de la SDRAM (tb_megaram.sv: pat_word / pat_byte)
 ***************************************************************/
static uint32_t pat_word(uint32_t w)
{
    uint32_t x = w * 0x9E3779B1u;
    return x ^ (x >> 15) ^ 0x5A5A1234u;
}
uint8_t host_pat_byte(uint32_t a)
{
    return (uint8_t)(pat_word(a >> 2) >> ((a & 3) * 8));
}

/***************************************************************
 * megaROM
 ***************************************************************/
#define F_WP        0x01
#define F_BANK16    0x02
#define F_CS1M      0x04
#define F_CS2M      0x08
#define F_SCC       0x10
#define F_SCC_I     0x20
#define F_CONT      0x40
#define F_ENABLE    0x80

#define A_FLAGS     0x0C
#define A_MASKV     0x0D
#define A_MASKA_L   0x0E
#define A_MASKA_H   0x0F
#define A_MODE      0x1F
#define MODE_PLAIN0 0x01

static const uint8_t KEY[4] = { 0xAB, 0xCD, 0x98, 0x76 };

uint8_t  host_cart_ram[HOST_WIN_SIZE];
static uint8_t ctrl[32];
static uint8_t flash_reg[16];
static uint8_t bank_reg[4], bank_raw[4];
static uint8_t scc_bank_en[4], scc_wp[4];
static int     scc_mode_scci;
int      host_model_errors = 0;
uint8_t  host_win_reg = 0x00;
uint32_t host_cart_ops = 0;

static int reg_protect(void)
{
    return ctrl[0] != KEY[0] || ctrl[1] != KEY[1] || ctrl[2] != KEY[2] || ctrl[3] != KEY[3];
}
static int plain_flag(void)   { return (ctrl[A_MODE] & MODE_PLAIN0) != 0; }
static int plain_active(void) { return plain_flag() && reg_protect() && (ctrl[A_FLAGS] & F_ENABLE); }
int cart_plain_active(void)   { return plain_active(); }
uint8_t cart_ctrl(int index)  { return ctrl[index & 31]; }
uint8_t cart_bank(int index)  { return bank_reg[index & 3]; }
int cart_scc_wp(int index)    { return scc_wp[index & 3]; }

static uint16_t bank_addr(int i)  { return (uint16_t)(ctrl[0x10 + 4 * i] | (ctrl[0x11 + 4 * i] << 8)); }
static uint8_t  bank_init(int i)  { return ctrl[0x12 + 4 * i]; }
static uint16_t bank_amask(void)  { return (uint16_t)(ctrl[A_MASKA_L] | (ctrl[A_MASKA_H] << 8)); }

// cartridge_megarom.sv: con !SCC_I_ENA (o en reset) BankEnable = 1111, WP = 0000, modo SCC
static void scc_mode_reset(void)
{
    scc_mode_scci = 0;
    for(int i = 0; i < 4; i++) { scc_bank_en[i] = 1; scc_wp[i] = 0; }
}
static void scc_follow_flags(void)
{
    if(!(ctrl[A_FLAGS] & F_SCC_I)) scc_mode_reset();
}

// megarom_controller.sv: cs_mem_n (0 = la megaROM contesta en memoria)
static int cs_mem(uint16_t a)
{
    int page = a >> 14;
    if(plain_active()) return a < 0xC000;
    int enable = (ctrl[A_FLAGS] & F_ENABLE) != 0;
    int cs1_mask = (ctrl[A_FLAGS] & F_CS1M) || !enable;
    int cs2_mask = (ctrl[A_FLAGS] & F_CS2M) || !enable;
    return (page == 1 && !cs1_mask) || (page == 2 && !cs2_mask);
}

// offset en la ventana (MemoryTopAddr = RAM_ADDR_MEGAROM = 0)
static uint32_t win_addr(uint16_t a)
{
    if(plain_active()) return a;                                        // addr_plain
    int a15 = (a >> 15) & 1, a13 = (a >> 13) & 1;
    if(ctrl[A_FLAGS] & F_BANK16)
        return ((uint32_t)bank_reg[a15] << 14) | (a & 0x3FFF);          // addr_16
    return ((uint32_t)bank_reg[(a15 << 1) | a13] << 13) | (a & 0x1FFF); // addr_8
}

void cart_power_on(void)
{
    // SDRAM: patron del banco y borrado de 32 KB (MEGAROM_CLEAR)
    for(uint32_t a = 0; a < HOST_WIN_SIZE; a++) host_cart_ram[a] = host_pat_byte(a);
    memset(host_cart_ram, 0xFF, HOST_CLEAR_SIZE);
    // megarom_configure.sv, rama !RESET_n, con los DEFAULT_* de main.sv para
    // ENABLE_MEGA_SCC_I (los del banco de Verilator)
    memset(ctrl, 0, sizeof(ctrl));
    memset(flash_reg, 0, sizeof(flash_reg));
    for(int i = 0; i < 4; i++) ctrl[i] = (uint8_t)~KEY[i];
    ctrl[A_FLAGS]   = F_SCC | F_SCC_I | F_CONT | F_ENABLE;
    ctrl[A_MASKV]   = 0xFF;
    ctrl[A_MASKA_L] = 0x00; ctrl[A_MASKA_H] = 0xF8;
    static const uint16_t def_addr[4] = { 0x5000, 0x7000, 0x9000, 0xB000 };
    for(int i = 0; i < 4; i++) {
        ctrl[0x10 + 4 * i] = (uint8_t)def_addr[i];
        ctrl[0x11 + 4 * i] = (uint8_t)(def_addr[i] >> 8);
        ctrl[0x12 + 4 * i] = (uint8_t)i;
    }
    // EXPANSION_SLOT sale de reset con Secondary.RESET_n = 0 un ciclo: el
    // controlador pasa por !Bus.RESET_n y carga BankRegInit (0, 1, 2, 3)
    for(int i = 0; i < 4; i++) bank_reg[i] = bank_raw[i] = bank_init(i);
    scc_mode_reset();
}

void cart_msx_reset(void)
{
    host_trace_op('Z', 0, 0);
    // megarom_configure.sv, rama !Bus.RESET_n
    if(!(ctrl[A_FLAGS] & F_CONT) || plain_flag()) ctrl[A_FLAGS] &= (uint8_t)~F_ENABLE;
    ctrl[A_MODE] &= (uint8_t)~MODE_PLAIN0;
    for(int i = 0; i < 4; i++) ctrl[i] = (uint8_t)~KEY[i];
    memset(flash_reg, 0, sizeof(flash_reg));
    // megarom_controller.sv: bancos a su valor inicial
    for(int i = 0; i < 4; i++) bank_reg[i] = bank_raw[i] = bank_init(i);
    // cartridge_megarom.sv: modo SCC-I en reset
    scc_mode_reset();
}

// lectura de 30h-3Fh (megarom_configure.sv); -1 = no modelado
static int read_info(uint8_t idx)
{
    switch(idx) {
        case 0x1C: return 0x00;     // RAM_ADDR[15:8]
        case 0x1D: return 0x00;     // RAM_ADDR[23:16]
        case 0x1E: return host_win_reg; // RAM_SIZE[21:14]: 4 MB = 00h (256 bancos)
        case 0x1F: return 0x00;     // FLASH_STATUS: Xfer.Busy = 0
        default:   return -1;
    }
}

static uint8_t cart_read_raw(uint16_t a)
{
    int drv = 0;
    uint8_t d = 0xFF;
    // configuracion: cs_reg_rd_n = reg_protect || A[15:6] != 0
    if(!reg_protect() && a < 0x40) {
        if(!(a & 0x20))           { d = ctrl[a & 31]; drv = 1; }
        else if((a & 0x1F) == 0x0A) { d = 0x00; drv = 1; }             // FLASH_RDATA (Xfer.RData = 0)
        else if(!(a & 0x10))      { d = flash_reg[a & 15]; drv = 1; }
        else {
            int v = read_info(a & 0x1F);
            if(v < 0) { host_model_errors++; fprintf(stderr, "MODELO: lectura de %04Xh no modelada\n", a); }
            else      { d = (uint8_t)v; drv = 1; }
        }
    }
    // SCC (cartridge_megarom.sv): 9800h con banco 2 = 3Fh, o B800h con el bit 7 del banco 3 en SCC-I
    if(!plain_active() && (ctrl[A_FLAGS] & F_SCC)) {
        int bi = (((a >> 15) & 1) << 1) | ((a >> 13) & 1);
        int sel = scc_mode_scci ? ((a >> 8) == 0xB8 && (bank_raw[bi] & 0x80))
                                : ((a >> 8) == 0x98 && (bank_raw[bi] & 0x3F) == 0x3F);
        if(sel) { host_model_errors++; fprintf(stderr, "MODELO: lectura del SCC en %04Xh no modelada\n", a); }
    }
    if(!drv && cs_mem(a)) d = host_cart_ram[win_addr(a)];
    return d;
}

uint8_t cart_read(uint16_t a)
{
    uint8_t d = cart_read_raw(a);
    host_trace_op('R', a, d);
    return d;
}

void cart_write(uint16_t a, uint8_t d)
{
    host_trace_op('W', a, d);
    int pa = plain_active();

    // RAM (wr_mem_n), con el estado de antes de la escritura
    int bi = (((a >> 15) & 1) << 1) | ((a >> 13) & 1);
    if(cs_mem(a) && !(ctrl[A_FLAGS] & F_WP) && !scc_wp[bi] && !pa)
        host_cart_ram[win_addr(a)] = d;

    // registros de banco (det_wr en cualquier direccion del subslot)
    for(int i = 0; i < 4; i++) {
        if(((a & bank_amask()) == bank_addr(i)) && scc_bank_en[i] && !pa) {
            bank_reg[i] = d & ctrl[A_MASKV];
            bank_raw[i] = d;
        }
    }

    // registro de modo SCC-I (BFFEh/BFFFh, sin mirar ENABLE ni la proteccion)
    if((ctrl[A_FLAGS] & F_SCC_I) && (a & 0xFFFE) == 0xBFFE && !pa) {
        int d0 = d & 1, d1 = (d >> 1) & 1, d2 = (d >> 2) & 1, d4 = (d >> 4) & 1;
        scc_mode_scci = (d >> 5) & 1;
        scc_bank_en[0] = scc_wp[0] = !d4;
        scc_bank_en[1] = scc_wp[1] = !(d4 || d0);
        scc_bank_en[2] = scc_wp[2] = !(d4 || d1);
        scc_bank_en[3] = scc_wp[3] = !(d4 || d2);
    }

    // configuracion: cs_reg_wr_n
    int cs_wr = pa ? 0 : reg_protect() ? (a < 0x04) : (a < 0x40);
    if(cs_wr) {
        if(!(a & 0x20))             ctrl[a & 31] = d;
        else if((a & 0x30) == 0x20) flash_reg[a & 15] = d;
        // 3Fh: comando de la flash (Xfer), sin efecto en el modelo
    }
    scc_follow_flags();
}

/***************************************************************
 * slots del MSX
 ***************************************************************/
static uint8_t ram30[0x10000];
static uint8_t bios_byte(uint16_t a) { return a == 0 ? 0xF3 : (uint8_t)(a * 7 + 0x31); }

uint8_t host_exptbl(uint8_t primary)
{
    static const uint8_t exptbl[4] = { 0x00, 0x80, 0x00, 0x80 };
    return exptbl[primary & 3];
}

static int slot_norm(uint8_t slt)
{
    // codigo de slot de la BIOS: b7 expandido, b0-1 primario, b2-3 secundario
    int p = slt & 3;
    if(host_exptbl(p) & 0x80) return 0x80 | (slt & 0x0F);
    return p;
}

void host_enaslt(uint8_t slt, uint16_t addr) { (void)slt; (void)addr; }

void host_wrslt(uint8_t slt, uint16_t addr, uint8_t data)
{
    int s = slot_norm(slt);
    if(s == HOST_CART_SLOT)      cart_write(addr, data);
    else if(s == HOST_RAM_SLOT)  ram30[addr] = data;
}

uint8_t host_rdslt(uint8_t slt, uint16_t addr)
{
    int s = slot_norm(slt);
    if(s == HOST_CART_SLOT)      return cart_read(addr);
    if(s == HOST_RAM_SLOT)       return ram30[addr];
    if(s == 0)                   return bios_byte(addr);
    return 0xFF;
}

// xfer_memory: pagina 2 al slot y LDIR
void host_xfer(uint8_t slt, uint16_t dst, const uint8_t *src, uint16_t size)
{
    for(uint16_t i = 0; i < size; i++) host_wrslt(slt, (uint16_t)(dst + i), src[i]);
}

/***************************************************************
 * traza
 ***************************************************************/
static FILE    *trace_fp = NULL;
static uint32_t trace_n = 0;

int host_trace_open(const char *path)
{
    trace_fp = fopen(path, "w");
    trace_n = 0;
    return trace_fp != NULL;
}
void host_trace_close(void)
{
    if(trace_fp) fclose(trace_fp);
    trace_fp = NULL;
}
void host_trace_comment(const char *text)
{
    if(trace_fp) fprintf(trace_fp, "# %s\n", text);
}
void host_trace_op(char op, uint16_t a, uint8_t d)
{
    host_cart_ops++;
    if(!trace_fp) return;
    fprintf(trace_fp, "%c %04X %02X\n", op, a, d);
    trace_n++;
}
uint32_t host_trace_ops(void) { return trace_n; }

/***************************************************************
 * DOS (ficheros en memoria) y BIOS
 ***************************************************************/
int host_dos_version = 2;
int host_rebooted = 0;

#define HOST_MAX_FILES 32
static struct { char name[64]; const uint8_t *data; uint32_t size; } files[HOST_MAX_FILES];
static int n_files = 0;
extern uint8_t tncrom_host_buffer[];         // main.c (TNCROM_HOST_TEST)

void host_file_add(const char *name, const uint8_t *data, uint32_t size)
{
    if(n_files >= HOST_MAX_FILES) { fprintf(stderr, "host_file_add: demasiados ficheros\n"); exit(2); }
    snprintf(files[n_files].name, sizeof(files[n_files].name), "%s", name);
    files[n_files].data = data;
    files[n_files].size = size;
    n_files++;
}
void host_files_clear(void) { n_files = 0; }
const uint8_t *host_file_data(const char *name)
{
    for(int i = 0; i < n_files; i++) if(strcasecmp(files[i].name, name) == 0) return files[i].data;
    fprintf(stderr, "host_file_data: no hay %s\n", name);
    exit(2);
}

int bdos_fopen(BDOS_FILE_t *file, char *path)
{
    for(int i = 0; i < n_files; i++) {
        if(strcasecmp(files[i].name, path) == 0) {
            memset(file, 0, sizeof(*file));
            file->type = TYPE_DOS2;
            file->dos2.handle = (uint8_t)i;
            file->dos2.file_size = files[i].size;
            file->current_pos = 0;
            return 0;
        }
    }
    return 0xD7;                    // .NOFIL
}
int bdos_fcreate(BDOS_FILE_t *file, char *path) { (void)file; (void)path; return 0xD7; }
int bdos_fclose(BDOS_FILE_t *file) { (void)file; return 0; }
int bdos_file_size(BDOS_FILE_t *file, uint32_t *size) { *size = files[file->dos2.handle].size; return 0; }
int bdos_eof(BDOS_FILE_t *file) { return file->current_pos >= files[file->dos2.handle].size; }

static uint16_t file_read(BDOS_FILE_t *file, uint8_t *dst, uint16_t size)
{
    uint32_t remain = files[file->dos2.handle].size - file->current_pos;
    uint16_t n = (remain < size) ? (uint16_t)remain : size;
    memcpy(dst, files[file->dos2.handle].data + file->current_pos, n);
    file->current_pos += n;
    return n;
}
int bdos_fread(BDOS_FILE_t *file, uint16_t *readed)
{
    memset(file->buffer, 0x1A, sizeof(file->buffer));
    *readed = file_read(file, file->buffer, sizeof(file->buffer));
    return (*readed == 0) ? 0xC7 : 0;   // .EOF
}
int bdos_fread_n(BDOS_FILE_t *file, uint16_t addr, uint16_t size, uint16_t *readed)
{
    (void)addr;                     // main.c pasa el buffer de 6000h como entero de 16 bits
    *readed = file_read(file, tncrom_host_buffer, size);
    return (*readed == 0 && size != 0) ? 0xC7 : 0;
}
int bdos_fwrite(BDOS_FILE_t *file, uint16_t *written) { (void)file; *written = 0; return 0xC6; }
int bdos_set_about_handler(uint16_t addr) { (void)addr; return 0; }
int bdos_term(uint8_t code)
{
    fprintf(stderr, "bdos_term(%02Xh) llamado (abort_handler)\n", code);
    exit(3);
}
uint8_t bdos_get_version(void) { return (uint8_t)host_dos_version; }
void bdos_conout(char ch) { putchar(ch); }

// lib/reboot.c
void reboot(void) { host_rebooted = 1; }
