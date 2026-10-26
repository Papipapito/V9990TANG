//
// test_tncrom.c -- banco del host de tncrom (V9990TANG)
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito (V9990TANG).
//
// Corre el main() de tncrom (src/main.c compilado con -Dmain=tncrom_main y
// TNCROM_HOST_TEST) contra el modelo de host_mock.c y comprueba la salida,
// el codigo de retorno y el estado del cartucho. Tres casos dejan una traza
// de las operaciones de bus con la megaROM (tncrom_plain0.trc,
// tncrom_ascii16.trc, tncrom_scci.trc en la carpeta del primer argumento)
// que fpga/tb/megaram/run.sh (variante tncrom) reproduce contra el RTL.
//
// Uso: test_tncrom <carpeta de salida>
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include "host_mock.h"

int tncrom_main(int argc, char *argv[]);

static int n_fail = 0, n_check = 0;
static const char *out_dir = ".";
static char last_out[65536];

static void check(int cond, const char *fmt, ...)
{
    va_list ap;
    n_check++;
    if(cond) return;
    n_fail++;
    printf("  FALLO: ");
    va_start(ap, fmt); vprintf(fmt, ap); va_end(ap);
    printf("\n");
}

// corre tncrom con la linea de ordenes dada; guarda la salida en last_out
static int run(const char *cmdline)
{
    char buf[512], *argv[16];
    int argc = 0;
    snprintf(buf, sizeof(buf), "%s", cmdline);
    argv[argc++] = "TNCROM";
    for(char *p = strtok(buf, " "); p && argc < 15; p = strtok(NULL, " ")) argv[argc++] = p;
    argv[argc] = NULL;

    char tmp[512];
    snprintf(tmp, sizeof(tmp), "%s/tncrom_stdout.tmp", out_dir);
    fflush(stdout);
    int saved = dup(1);
    int fd = open(tmp, O_CREAT | O_TRUNC | O_WRONLY, 0644);
    dup2(fd, 1);
    close(fd);
    int rc = tncrom_main(argc, argv);
    fflush(stdout);
    dup2(saved, 1);
    close(saved);

    FILE *f = fopen(tmp, "rb");
    size_t n = f ? fread(last_out, 1, sizeof(last_out) - 1, f) : 0;
    if(f) fclose(f);
    last_out[n] = '\0';
    printf("$ TNCROM %s  -> %d\n", cmdline, rc);
    for(char *p = last_out; *p; ) {                 // salida sangrada, sin los \r del progreso
        char *e = strchr(p, '\n');
        size_t len = e ? (size_t)(e - p) : strlen(p);
        char line[1024];
        if(len >= sizeof(line)) len = sizeof(line) - 1;
        memcpy(line, p, len); line[len] = '\0';
        char *q = strrchr(line, '\r');
        printf("    %s\n", q ? q + 1 : line);
        if(!e) break;
        p = e + 1;
    }
    return rc;
}
static int out_has(const char *s) { return strstr(last_out, s) != NULL; }

/***************************************************************
 * imagenes
 ***************************************************************/
static uint8_t *img_make(uint32_t size, uint32_t seed)
{
    uint8_t *p = malloc(size ? size : 1);
    uint32_t x = seed * 2654435761u + 1;
    for(uint32_t i = 0; i < size; i++) {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        p[i] = (uint8_t)(x >> 7);
    }
    return p;
}

static uint8_t *demo48;     // demo plana: "AB" en 4000h, INIT 4010h, ISR en 0038h
static void make_files(void)
{
    host_files_clear();
    demo48 = img_make(49152, 1);
    demo48[0x0000] = 0xF3;                                   // DI
    demo48[0x0038] = 0xF5; demo48[0x0039] = 0xDB; demo48[0x003A] = 0x66;   // PUSH AF / IN A,(66h)
    demo48[0x4000] = 'A';  demo48[0x4001] = 'B';
    demo48[0x4002] = 0x10; demo48[0x4003] = 0x40;            // INIT = 4010h
    host_file_add("DEMO48.ROM", demo48, 49152);
    host_file_add("P49K.ROM", img_make(49153, 2), 49153);
    host_file_add("Z0.ROM", img_make(0, 3), 0);
    uint8_t *a40 = img_make(40960, 4); a40[0] = 'A'; a40[1] = 'B';
    host_file_add("A40K.ROM", a40, 40960);
    host_file_add("A4M.ROM", img_make(4u << 20, 5), 4u << 20);
    host_file_add("A4097.ROM", img_make((4u << 20) + 1024, 6), (4u << 20) + 1024);
    host_file_add("K512.ROM", img_make(512u << 10, 7), 512u << 10);
    host_file_add("K513.ROM", img_make(513u << 10, 8), 513u << 10);
    host_file_add("K2M.ROM", img_make(2u << 20, 9), 2u << 20);
    host_file_add("K2049.ROM", img_make((2u << 20) + 1024, 10), (2u << 20) + 1024);
    uint8_t *s32 = img_make(32768, 11); s32[0] = 'A'; s32[1] = 'B';
    host_file_add("S32K.ROM", s32, 32768);
    host_file_add("B32K.ROM", img_make(32768, 12), 32768);
}
static const uint8_t *file_data(const char *name);
static const uint8_t *k512, *k513, *k2m, *a40k, *a4m, *s32k, *b32k;

// la ventana contiene la imagen (n bytes desde 0)
static int win_equals(const uint8_t *img, uint32_t n)
{
    for(uint32_t i = 0; i < n; i++) if(host_cart_ram[i] != img[i]) {
        printf("  (ventana %06Xh = %02X, imagen %02X)\n", i, host_cart_ram[i], img[i]);
        return 0;
    }
    return 1;
}
// el resto de la ventana sigue con el patron o el borrado. Salvo un byte:
// tncrom pone el banco 0 en el ultimo banco antes de cargar (main.c,
// xfer_file) y cada escritura al registro de banco 1 (7000h, pagina 1, sin
// proteccion) cae tambien en ese banco en +3000h; si la imagen acaba antes
// (ultimo banco incompleto) ahi queda el numero del ultimo banco. Fuera de
// la imagen: no molesta.
static int win_rest_intact(uint32_t from)
{
    uint32_t last = (from - 1) >> 14, hit = last * 16384 + 0x3000;
    for(uint32_t i = from; i < HOST_WIN_SIZE; i++) {
        uint8_t e = (i < HOST_CLEAR_SIZE) ? 0xFF : host_pat_byte(i);
        if(i == hit) e = (uint8_t)last;
        if(host_cart_ram[i] != e) { printf("  (ventana %06Xh = %02X, esperado %02X)\n", i, host_cart_ram[i], e); return 0; }
    }
    return 1;
}

#define FL_WP 0x01
#define FL_B16 0x02
#define FL_SCC 0x10
#define FL_SCCI 0x20
#define FL_CONT 0x40
#define FL_EN 0x80

static void trace_begin(const char *name)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", out_dir, name);
    if(!host_trace_open(path)) { printf("no puedo crear %s\n", path); exit(2); }
    cart_power_on();
    host_trace_comment(name);
}
static void trace_end(const char *name)
{
    printf("  traza %s: %u operaciones\n", name, host_trace_ops());
    host_trace_close();
}

/***************************************************************
 * casos
 ***************************************************************/
static void t_basic(void)
{
    printf("--- ayuda, errores de linea de ordenes y de tamano (el cartucho no se toca)\n");
    cart_power_on();
    uint32_t ops;
    check(run("") == 1 && out_has("USAGE:"), "sin argumentos: USAGE");
    check(out_has("V9990TANG r2"), "version r2");
    check(run("-H") == 0 && out_has("PLAIN0: PLAIN 0000h~BFFFh (max 48KB)"), "-H lista PLAIN0 con su maximo");
    check(out_has("ASCII16: ASCII 16KB (max 4096KB)") && out_has("KONAMI: KONAMI 8KB with SCC sound (max 2048KB)"), "-H: maximos de ASCII16 y KONAMI");
    ops = host_cart_ops;
    host_dos_version = 1;
    check(run("-T PLAIN0 DEMO48.ROM") == 1 && out_has("MSX-DOS 2 or Nextor required."), "MSX-DOS 1: aviso");
    host_dos_version = 2;
    check(run("-T PLAIN0 P49K.ROM") == 1 && out_has("rom image too large for PLAIN 0000h~BFFFh: 49KB, max 48KB."), "PLAIN0 de 48 KB + 1");
    check(run("-T PLAIN0 Z0.ROM") == 1 && out_has("empty rom image file(Z0.ROM)."), "fichero vacio");
    check(run("-T FOO DEMO48.ROM") == 1 && out_has("unknown rom type(FOO)."), "tipo desconocido");
    check(run("-T ASCII16 A4097.ROM") == 1 && out_has("rom image too large for ASCII 16KB: 4097KB, max 4096KB."), "ASCII16 de 4 MB + 1 KB");
    check(run("-T KONAMI K2049.ROM") == 1 && out_has("rom image too large for KONAMI 8KB with SCC sound: 2049KB, max 2048KB."), "KONAMI de 2 MB + 1 KB");
    check(run("-T ASCII8 K2049.ROM") == 1 && out_has("max 2048KB."), "ASCII8 de 2 MB + 1 KB");
    check(run("-T 32K P49K.ROM") == 1 && out_has("rom image too large for NO BANK 32KB: 49KB, max 32KB."), "32K de 49 KB");
    check(run("-T PLAIN0 NOFILE.ROM") == 1 && out_has("can not open rom image file(NOFILE.ROM)."), "fichero que no existe");
    check(host_cart_ops == ops, "ninguna operacion con el cartucho en los errores (%u)", host_cart_ops - ops);
    // ventana de 3 MB (3Eh = C0h, la de tnCart): la imagen de 4 MB no cabe
    host_win_reg = 0xC0;
    check(run("-T ASCII16 A4M.ROM") == 1 && out_has("rom image too large for the cartridge: 4096KB, window 3072KB."), "ventana de 3 MB (3Eh = C0h)");
    host_win_reg = 0x00;
    check(cart_plain_active() == 0 && (cart_ctrl(0x0C) & FL_EN), "la megaROM sigue como al encender");
}

static void t_plain0(void)
{
    const char *tr = "tncrom_plain0.trc";
    printf("--- PLAIN0 (traza %s)\n", tr);
    trace_begin(tr);
    check(run("-T PLAIN0 DEMO48.ROM") == 0 && out_has("complete.") && out_has("ROM TYPE : PLAIN 0000h~BFFFh"), "carga PLAIN0");
    check(out_has("note: a hardware reset clears PLAIN0, use -R to boot it."), "aviso del /RESET sin -R");
    check(cart_plain_active(), "PLAIN0 activo");
    check(cart_ctrl(0x0C) == (FL_WP | FL_B16 | FL_CONT | FL_EN), "flags = %02X", cart_ctrl(0x0C));
    check(cart_ctrl(0x1F) == 0x01, "1Fh = %02X", cart_ctrl(0x1F));
    check(win_equals(demo48, 49152), "ventana = imagen");
    check(win_rest_intact(49152), "resto de la ventana intacto");
    // lo que ve el Z80 (lecturas en la traza)
    int bad = 0;
    for(uint16_t a = 0x0000; a < 0x0040; a++) bad += cart_read(a) != demo48[a];
    for(uint16_t a = 0x4000; a < 0x4040; a++) bad += cart_read(a) != demo48[a];
    for(uint32_t a = 0; a < 0xC000; a += 97) bad += cart_read((uint16_t)a) != demo48[a];
    bad += cart_read(0xBFFF) != demo48[0xBFFF];
    check(bad == 0, "lectura lineal 0000h-BFFFh (%d mal)", bad);
    check(cart_read(0xC000) == 0xFF && cart_read(0xFFFE) == 0xFF, "C000h-FFFFh sin respuesta");
    // la llave y las escrituras no hacen nada
    cart_write(0x0000, 0xAB); cart_write(0x0001, 0xCD); cart_write(0x0002, 0x98); cart_write(0x0003, 0x76);
    check(cart_plain_active() && cart_read(0x0000) == demo48[0] && cart_read(0x000C) == demo48[0x0C], "la llave no abre con PLAIN0");
    cart_write(0x4000, 0x99); cart_write(0x0038, 0x99); cart_write(0x7000, 0x05); cart_write(0xBFFE, 0x30);
    check(cart_read(0x4000) == 'A' && cart_read(0x0038) == 0xF5 && cart_read(0x8000) == demo48[0x8000], "escritura protegida y bancos fijos");
    // otro tncrom con PLAIN0 activo no encuentra el cartucho
    check(run("-T PLAIN0 DEMO48.ROM") == 1 && out_has("cartridge not found (if PLAIN0 is active, reset the MSX first)."), "PLAIN0 oculta el cartucho a tncrom");
    check(cart_plain_active() && cart_read(0x4001) == 'B', "y sigue activo");
    // /RESET: fuera PLAIN0 y ENABLE (aunque hubiera ENABLE_CONTINUOUS)
    cart_msx_reset();
    check(!cart_plain_active() && !(cart_ctrl(0x0C) & FL_EN) && cart_ctrl(0x1F) == 0, "el /RESET borra PLAIN0 y ENABLE");
    check(cart_read(0x4000) == 0xFF && cart_read(0x0038) == 0xFF && cart_read(0x8000) == 0xFF, "tras /RESET el cartucho no contesta");
    // con -R: reinicio por software y sin aviso
    host_rebooted = 0;
    check(run("-T PLAIN0 -R DEMO48.ROM") == 0 && out_has("rebooting...") && !out_has("note: a hardware reset"), "PLAIN0 con -R");
    check(host_rebooted && cart_plain_active(), "reboot() llamado con PLAIN0 activo");
    check(cart_read(0x4000) == 'A' && cart_read(0x4002) == 0x10 && cart_read(0x0039) == 0xDB, "cabecera e ISR tras -R");
    // -O no cambia nada en PLAIN0 (el /RESET lo borra igual)
    cart_msx_reset();
    check(run("-T PLAIN0 -O DEMO48.ROM") == 0 && cart_plain_active() && cart_ctrl(0x0C) == (FL_WP | FL_B16 | FL_EN), "PLAIN0 con -O");
    cart_msx_reset();
    check(!cart_plain_active() && cart_read(0x4000) == 0xFF, "PLAIN0 -O tras /RESET");
    trace_end(tr);
}

static void t_ascii16(void)
{
    const char *tr = "tncrom_ascii16.trc";
    printf("--- ASCII16 de 40 KB (traza %s)\n", tr);
    trace_begin(tr);
    check(run("-T ASCII16 A40K.ROM") == 0 && out_has("complete."), "carga ASCII16");
    check(cart_ctrl(0x0C) == (FL_WP | FL_B16 | FL_CONT | FL_EN) && cart_ctrl(0x0D) == 0xFF && cart_ctrl(0x1F) == 0, "atributo final ASCII16 (flags %02X)", cart_ctrl(0x0C));
    check(win_equals(a40k, 40960), "ventana = imagen");
    check(win_rest_intact(40960), "resto de la ventana intacto");
    check(cart_bank(0) == 0 && cart_bank(1) == 0, "bancos 0/0 tras la carga");
    int bad = 0;
    for(int b = 0; b < 3; b++) {
        cart_write(0x6000, (uint8_t)b); cart_write(0x7000, (uint8_t)(2 - b));
        uint32_t n0 = (b == 2) ? 8192 : 16384, n1 = (b == 0) ? 8192 : 16384;
        for(uint32_t o = 0; o < n0; o += 211) bad += cart_read((uint16_t)(0x4000 + o)) != a40k[b * 16384 + o];
        for(uint32_t o = 0; o < n1; o += 223) bad += cart_read((uint16_t)(0x8000 + o)) != a40k[(2 - b) * 16384 + o];
    }
    check(bad == 0, "lecturas por las dos paginas (%d mal)", bad);
    cart_write(0x7000, 0x01); cart_write(0x8005, 0x5A);
    check(host_cart_ram[16384 + 5] == a40k[16384 + 5], "con proteccion no se escribe");
    cart_msx_reset();
    check((cart_ctrl(0x0C) & FL_EN) && cart_read(0x4000) == 'A' && cart_read(0x8001) == 'B', "tras /RESET sigue (ENABLE_CONTINUOUS), bancos 0/0");
    check(run("-T ASCII16 -O A40K.ROM") == 0 && !(cart_ctrl(0x0C) & FL_CONT), "-O: sin ENABLE_CONTINUOUS");
    cart_msx_reset();
    check(!(cart_ctrl(0x0C) & FL_EN) && cart_read(0x4000) == 0xFF, "-O: tras /RESET deshabilitado");
    trace_end(tr);
}

static void t_scci(void)
{
    const char *tr = "tncrom_scci.trc";
    printf("--- KONAMI_SCC_I de 32 KB (traza %s)\n", tr);
    trace_begin(tr);
    check(run("-T KONAMI_SCC_I S32K.ROM") == 0 && out_has("complete."), "carga KONAMI_SCC_I");
    check(cart_ctrl(0x0C) == (FL_SCC | FL_SCCI | FL_CONT | FL_EN) && cart_ctrl(0x0D) == 0xFF, "flags %02X", cart_ctrl(0x0C));
    check(cart_scc_wp(0) && cart_scc_wp(1) && cart_scc_wp(2) && cart_scc_wp(3), "BFFEh = 00h: los cuatro bancos protegidos");
    check(cart_bank(0) == 0 && cart_bank(1) == 1 && cart_bank(2) == 2 && cart_bank(3) == 3, "bancos 0,1,2,3");
    check(win_equals(s32k, 32768), "ventana = imagen");
    check(win_rest_intact(32768), "resto de la ventana intacto");
    int bad = 0;
    for(uint32_t o = 0; o < 0x8000; o += 101) bad += cart_read((uint16_t)(0x4000 + o)) != s32k[o];
    check(bad == 0, "lecturas de 4000h-BFFFh (%d mal)", bad);
    cart_write(0x9000, 0x00); cart_write(0xB000, 0x01);
    check(cart_read(0x8000) == s32k[0] && cart_read(0xA000) == s32k[0x2000], "registros de banco 9000h/B000h");
    cart_write(0x4000, 0x99);
    check(host_cart_ram[0] == s32k[0], "escritura protegida");
    // como SofaRun: BFFEh = 10h, todo RAM
    cart_write(0xBFFE, 0x10);
    cart_write(0x4000, 0x99);
    check(host_cart_ram[0] == 0x99 && cart_read(0x4000) == 0x99, "BFFEh = 10h: RAM escribible");
    trace_end(tr);
}

static void t_big(void)
{
    printf("--- imagenes grandes (sin traza)\n");
    cart_power_on();
    check(run("-T ASCII16 A4M.ROM") == 0 && win_equals(a4m, 4u << 20), "ASCII16 de 4 MB: los 256 bancos de 16 KB");
    cart_write(0x6000, 0xFF); cart_write(0x7000, 0x80);
    check(cart_read(0x7FFF) == a4m[0x3FFFFF] && cart_read(0x8000) == a4m[0x200000], "bancos FFh y 80h");
    check(run("-T KONAMI K512.ROM") == 0 && cart_ctrl(0x0D) == 0x3F, "KONAMI 512 KB: mascara 3Fh (%02X)", cart_ctrl(0x0D));
    check(win_equals(k512, 512u << 10), "KONAMI 512 KB en la ventana");
    check(run("-T KONAMI K513.ROM") == 0 && cart_ctrl(0x0D) == 0x7F, "KONAMI 513 KB: mascara 7Fh (%02X)", cart_ctrl(0x0D));
    check(run("-T KONAMI K2M.ROM") == 0 && cart_ctrl(0x0D) == 0xFF, "KONAMI 2 MB: mascara FFh (%02X)", cart_ctrl(0x0D));
    check(win_equals(k2m, 2u << 20), "KONAMI 2 MB en la ventana");
    cart_write(0x5000, 0xFF); cart_write(0xB000, 0x41);
    check(cart_read(0x4000) == k2m[0xFF * 8192] && cart_read(0xA123) == k2m[0x41 * 8192 + 0x123], "KONAMI 2 MB: bancos FFh y 41h");
    check(run("-T KONAMI_WO_SCC K2M.ROM") == 0 && cart_ctrl(0x0D) == 0xFF, "KONAMI_WO_SCC 2 MB: mascara FFh");
    check(run("-T ASCII8 K2M.ROM") == 0 && cart_ctrl(0x0D) == 0xFF, "ASCII8 2 MB: mascara FFh");
    cart_write(0x7800, 0xFF);
    check(cart_read(0xBFFF) == k2m[0x1FFFFF], "ASCII8: banco FFh");
    check(run("-T 32K B32K.ROM") == 0 && cart_ctrl(0x16) == 1, "32K: banco 1 inicial = 1");
    cart_msx_reset();
    check(cart_read(0x4001) == b32k[1] && cart_read(0x8001) == b32k[0x4001], "32K tras /RESET");
    check(run("-N -T KONAMI_SCC_I") == 0 && cart_ctrl(0x0C) == (FL_SCC | FL_SCCI | FL_CONT | FL_EN), "-N -T KONAMI_SCC_I (como el README)");
    check(win_equals(b32k, 32768), "-N no toca la ventana");
}

static const uint8_t *file_data(const char *name) { return host_file_data(name); }

int main(int argc, char *argv[])
{
    if(argc > 1) out_dir = argv[1];
    make_files();
    k512 = file_data("K512.ROM"); k513 = file_data("K513.ROM"); k2m = file_data("K2M.ROM");
    a40k = file_data("A40K.ROM"); a4m = file_data("A4M.ROM"); s32k = file_data("S32K.ROM"); b32k = file_data("B32K.ROM");
    (void)k513;

    t_basic();
    t_plain0();
    t_ascii16();
    t_scci();
    t_big();

    printf("----------------------------------------------------------------\n");
    printf("comprobaciones: %d, fallos: %d, accesos que el modelo no sabe contestar: %d\n", n_check, n_fail, host_model_errors);
    if(n_fail == 0 && host_model_errors == 0) { printf("RESULTADO: PASA\n"); return 0; }
    printf("RESULTADO: FALLA\n");
    return 1;
}
