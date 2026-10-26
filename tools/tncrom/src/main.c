//
// main.c
//
// BSD 3-Clause License
// 
// Copyright (c) 2024, Shinobu Hashimoto
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

// zcc +msx -subtype=msxdos -O3 -o../bin/TNCROM.COM main.c ..\..\lib\bdos.c ..\..\lib\tools.c ..\..\lib\rom_tools.c ..\..\lib\reboot.c rom_table.c config.c param.c
//
// V9990TANG: port a SDCC 4.5 (tools/tncrom/build.sh, crt0 propio de
// MSX-DOS en tools/tncrom/sdcc/) y extensiones: tipo PLAIN0, tamano maximo
// de la imagen por tipo y por ventana (3Eh), mascara de banco ampliada a la
// imagen (KONAMI de mas de 512 KB), aviso de MSX-DOS 2 y el banco 1 inicial
// de 32K. Las lineas tocadas llevan "V9990TANG".

#include <stdio.h>
#include <string.h>
#include "types.h"
#include "bdos.h"
#include "tools.h"
#include "rom_tools.h"
#include "reboot.h"
#include "rom_table.h"
#include "config.h"
#include "param.h"
#include "message.h"

#define VERSION (7)
#define V9990TANG_REVISION (2)      // V9990TANG (r2: mascara KONAMI > 512 KB)


static MAIN_PARAM_t main_param;     // パラメータ
static BDOS_FILE_t rom_file;        // ROM ファイルアクセス用
static uint8_t image_val_mask;      // V9990TANG: mascara de banco que se escribe en 0Dh

#define BUFFER_SIZE (8192)
#if 1
static uint8_t *buffer = (uint8_t*)(0x8000 - BUFFER_SIZE);
#else
static uint8_t buffer[BUFFER_SIZE];
#endif

//
// データ書き込み用の ROM 設定
//
static const ROM_ATTR_t ROM_ATTR_ASCII16_WO_WP = {
    (uint8_t)(FLAG_ENABLE | FLAG_BANK_SIZE),
    (uint8_t)0xFF,
    (uint16_t)0xF800,
    {
        { (uint16_t)0x6000, 0, 0 },
        { (uint16_t)0x7000, 0, 0 },
        { (uint16_t)0xFFFF, 0, 0 },
        { (uint16_t)0xFFFF, 0, 0 }
    },
    "---",
    4096
};

/***********************************************
 * ROM を有効にする
 *  引数
 *    sltnum    : スロット番号
 *    enable    : 有効/無効フラグ
 *    enable_continuous : ハードウェアリセットで enable フラグをクリアするかどうか
 ***********************************************/
static void set_rom_enable(uint8_t sltnum, int enable, int enable_continuous)
{
    unlock_megarom_configure(sltnum);
    uint8_t flags = rdslt(sltnum, 0x0C);
    flags &= ~(FLAG_ENABLE | FLAG_ENABLE_CONTINUOUS);
    if(enable) flags |= FLAG_ENABLE;
    if(enable_continuous) flags |= FLAG_ENABLE_CONTINUOUS;
    wrtslt(sltnum, 0x0C, flags);
    lock_megarom_configure(sltnum);
}

/***********************************************
 * 1バンク分(16KB)転送
 *  引数
 *    sltnum    : スロット番号
 *    bank      : バンク番号
 *    file      : 転送元のファイル
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
static int xfer_bank(uint8_t sltnum, uint8_t bank, BDOS_FILE_t *file, uint32_t pending)
{
    int res;
    uint16_t addr = (uint16_t)0x8000;
    uint16_t readed;

    // バンク切り替え
    set_bank1_reg(sltnum, bank);

    if(1)
    {
        uint16_t remain = pending > 16384 ? 16384 : pending;
        while(remain > 0)
        {
            uint16_t size = remain > BUFFER_SIZE ? BUFFER_SIZE : remain;
            while(size > 0)
            {
                // read
                res = bdos_fread_n(file, (uint16_t)buffer, size, &readed);
                if(0 != res) {
                    printf(MSG_ERR_FILEREAD);
                    return res;
                }

                // データを転送
                xfer_memory(sltnum, (VOID_PTR_t)addr, buffer, readed);

                // 次の準備
                addr += (uint16_t)readed;
                size -= readed;
                remain -= readed;
            }
        }
    }
    else for(uint8_t i = 0; i < (uint8_t)(16384 / 128); i++)
    {
        if (pending > 0) {
            // 128バイト読み出し
            if(0 != (res = bdos_fread(file, &readed))){
                printf(MSG_ERR_FILEREAD);
                return res;
            }

            // データを転送
            xfer_memory(sltnum, (VOID_PTR_t)addr, file->buffer, readed);

            // 次の準備
            addr += (uint16_t)readed;

            pending -= readed;
        } else
            break;
    }

    return 0;
}

/***********************************************
 * ファイル転送
 *  引数
 *    sltnum    : スロット番号
 *    file      : 転送元ファイルのファイル
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
static int xfer_file(uint8_t sltnum, BDOS_FILE_t *file)
{
    int res;
    uint8_t bank = 0;
    uint32_t size;

    // ファイルサイズを得る    
    if(0 != (res = bdos_file_size(file, &size)))
    {
        printf(MSG_ERR_GETFILESIZE);
        return res;
    }
    
    // バンク1のバンクレジスタを設定時にバンク0のデータが化けるので、Bank0を予め最終バンクに切り替え
    uint8_t last_bank = ((size - (uint32_t)1) >> 14) & 255;
    set_bank0_reg(sltnum, last_bank);

    while(size > (uint32_t)0)
    {
        printf(MSG_PROGRESS, bank);

        // 16KB 転送
        if(0 != (res = xfer_bank(sltnum, bank, file, size))) return res;

        // 次の準備
        bank++;

        // support less than 16K ROMs
        uint16_t remaining = (size >= 16384)? 16384 : size;
        size -= remaining;
    }    

    printf(MSG_PROGRESS_TERM);
    return 0;
}

/***********************************************
 * ヘッダー消去
 *  引数
 *    sltnum    : スロット番号
 *  戻り値
 *    なし
 ***********************************************/
static void disable_header(uint8_t sltnum)
{
    // 消去データ
    uint8_t buffer[16];
    memset(buffer, 0xFF, sizeof(buffer));

    // 先頭4バンクのヘッダを消去
    for(uint8_t bank = 0; bank < 4; bank++)
    {
        // バンク切り替え
        set_bank1_reg(sltnum, bank);

        // データを転送
        xfer_memory(sltnum, (VOID_PTR_t)0x8000, buffer, sizeof(buffer));
    }
}

/***********************************************
 * イメージファイル転送
 *  引数
 *    sltnum              : スロット番号
 *    rom_attr            : ROM 属性
 *    path                : 転送元ファイルのファイル
 *    disable_header_flag : ヘッダの無効化フラグ
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
static int load_rom_image(uint8_t sltnum, ROM_ATTR_PTR_t rom_attr, char *path, int disable_header_flag)
{
    int res = 0;

    if(disable_header_flag)
    {
        // ROM 書き込み許可
        rom_attr_xfer(sltnum, &ROM_ATTR_ASCII16_WO_WP);

        // ヘッダーデータ無効化
        disable_header(sltnum);
    }

    if(path != NULL)
    {
        // ファイルを開く
        if(0 != (res = bdos_fopen(&rom_file, path)))
        {
            printf(MSG_ERR_FILEOPEN, path);
            return res;
        }

        // ROM 書き込み許可
        rom_attr_xfer(sltnum, &ROM_ATTR_ASCII16_WO_WP);

        // ファイルを転送
        res = xfer_file(sltnum, &rom_file);

        // ファイルを閉じる
        bdos_fclose(&rom_file);
    }

    if(res != 0)
    {
        // 転送失敗時は誤動作防止のために ROM ヘッダを消去
        clear_rom(sltnum);

        // ROM 領域への書き込み禁止
        rom_attr = &ROM_ATTR_ASCII16;
        rom_attr_xfer(sltnum, rom_attr);
    }
    else
    {
        // バンク切り替えなし ROM で正しくデータが読めるようにバンク 0 を戻す
        rom_attr_xfer(sltnum, &ROM_ATTR_ASCII16);
        set_bank0_reg(sltnum, 0);

        // ROM 属性設定
        rom_attr_xfer(sltnum, rom_attr);

        // V9990TANG: mascara del valor de banco (0Dh) ampliada a la imagen
        // (KONAMI y KONAMI_WO_SCC de mas de 512 KB, ver image_val_mask)
        if(image_val_mask != rom_attr->val_mask)
        {
            unlock_megarom_configure(sltnum);
            wrtslt(sltnum, 0x000D, image_val_mask);
            lock_megarom_configure(sltnum);
        }

        // SCC-I モードレジスタ初期化
        if(rom_attr->flags & FLAG_SCC_I)
        {
            wrtslt(sltnum, 0xBFFE, 0x00);
        }
    }

    // バンクレジスタ初期設定
    init_bank_reg(sltnum, rom_attr);

    return res;
}

/***********************************************
 * カートリッジチェック
 *  引数
 *    sltnum    : チェックするスロット番号
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
int check_cartridge(uint8_t sltnum)
{
    int res = -1;
    uint8_t save[4];

__asm
    di
__endasm;

    // 元データを取得
    for(uint16_t addr = 0; addr < sizeof(save); addr++) save[addr] = rdslt(sltnum, addr);

    // RAM かどうかをチェックする
    wrtslt(sltnum, 0, 0xAA);
    if(rdslt(sltnum, 0) == 0xAA) goto err;
    wrtslt(sltnum, 0, 0x55);
    if(rdslt(sltnum, 0) == 0x55) goto err;

    // UNLOCK して読み出しデータが変化するかチェック
    wrtslt(sltnum, 0, 0xAB);
    wrtslt(sltnum, 1, 0xCD);
    wrtslt(sltnum, 2, 0x98);
    wrtslt(sltnum, 3, 0x76);
    if(rdslt(sltnum, 0) != 0xAB) goto err;
    if(rdslt(sltnum, 1) != 0xCD) goto err;
    if(rdslt(sltnum, 2) != 0x98) goto err;
    if(rdslt(sltnum, 3) != 0x76) goto err;

    // LOCK して読み出しデータが変化するかチェック
    wrtslt(sltnum, 0, 0x00);
    wrtslt(sltnum, 1, 0x00);
    wrtslt(sltnum, 2, 0x00);
    wrtslt(sltnum, 3, 0x00);
    if(rdslt(sltnum, 0) == 0xAB) goto err;
    if(rdslt(sltnum, 1) == 0xCD) goto err;
    if(rdslt(sltnum, 2) == 0x98) goto err;
    if(rdslt(sltnum, 3) == 0x76) goto err;

    //
    res = 0;

err:
    // 元データに戻す
    for(uint16_t addr = 0; addr < sizeof(save); addr++) wrtslt(sltnum, addr, save[addr]);

__asm
    ei
__endasm;

    return res;
}

/***********************************************
 * カートリッジを探す
 *  引数
 *    sltnum    : 見つかったスロット番号を格納する変数のポインタ
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
int search_cartridge(uint8_t *sltnum)
{
    for(uint8_t primary = 0; primary < 4; primary++)
    {
        if(*(uint8_t*)(0xFCC1 + primary) & 0x80)
        {
            for(uint8_t secondary = 0; secondary < 4; secondary++)
            {
                uint8_t slt = 0x80 | primary | (secondary << 2);
                if(check_cartridge(slt) == 0)
                {
                    if(sltnum != NULL) *sltnum = slt;
                    return 0;
                }
            }
        }
        else
        {
            if(check_cartridge(primary) == 0)
            {
                if(sltnum != NULL) *sltnum = primary;
                return 0;
            }
        }
    }
    return -1;
}

/***********************************************
 * バージョン情報出力
 ***********************************************/
static void output_version(void)
{
    printf(MSG_VERSION, VERSION / 100, VERSION % 100, V9990TANG_REVISION);
}

/***********************************************
 * usage 出力
 ***********************************************/
static void output_usage(void)
{
    printf(MSG_USAGE);
}

/***********************************************
 * help 出力
 ***********************************************/
static void output_help(void)
{
    printf(MSG_HELP);
    KEYWORD_PARAM_PTR_t p = rom_attr_table;
    while(p->keyword != NULL)
    {
        printf(MSG_HELP_TYPE, p->keyword, ((ROM_ATTR_PTR_t)p->param)->name, ((ROM_ATTR_PTR_t)p->param)->max_kb);
        p++;
    }
}

/***********************************************
 * V9990TANG: tamano de la imagen frente al maximo del tipo
 *  (antes de buscar el cartucho: se prueba sin hardware)
 *  引数
 *    path      : ROM イメージファイルのパス
 *    rom_attr  : ROM 属性
 *    kb        : tamano en KB (redondeado hacia arriba)
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
static int check_image_size(char *path, ROM_ATTR_PTR_t rom_attr, uint32_t *kb)
{
    int res;
    uint32_t size;

    if(0 != (res = bdos_fopen(&rom_file, path)))
    {
        printf(MSG_ERR_FILEOPEN, path);
        return res;
    }
    res = bdos_file_size(&rom_file, &size);
    bdos_fclose(&rom_file);
    if(res != 0)
    {
        printf(MSG_ERR_GETFILESIZE);
        return res;
    }
    if(size == 0)
    {
        printf(MSG_ERR_EMPTY, path);
        return 1;
    }

    *kb = (size + (uint32_t)1023) >> 10;
    if(*kb > (uint32_t)rom_attr->max_kb)
    {
        printf(MSG_ERR_TOO_LARGE, rom_attr->name, *kb, rom_attr->max_kb);
        return 1;
    }
    return 0;
}

/***********************************************
 * V9990TANG: mascara del valor de banco para una imagen de kb KB
 *  La de la tabla (3Fh en KONAMI y KONAMI_WO_SCC, como en upstream) solo
 *  alcanza 64 bancos de 8 KB = 512 KB; con una imagen mayor (GNG2M 2 MB,
 *  LIFEARTH 1 MB) se le anaden los bits que pide la imagen, redondeada a
 *  potencia de 2: openMSX (RomKonamiSCC / RomBlocks::setRom) usa el valor
 *  de 8 bits entero y da la vuelta al final de la imagen. Con 512 KB o
 *  menos, y en los tipos con mascara FFh, no cambia nada.
 *  戻り値
 *    mascara para 0Dh
 ***********************************************/
static uint8_t get_image_val_mask(ROM_ATTR_PTR_t rom_attr, uint32_t kb)
{
    // kb <= 4096 (check_image_size): cabe en 16 bits
    uint8_t shift = (rom_attr->flags & FLAG_BANK_SIZE) ? 4 : 3;
    uint16_t banks = ((uint16_t)kb + ((uint16_t)1 << shift) - 1) >> shift;
    uint16_t m = 1;
    while(m < banks) m <<= 1;
    return rom_attr->val_mask | (uint8_t)(m - 1);
}

/***********************************************
 * abort handler
 ***********************************************/
static void abort_handler(void)
{
    // 転送途中に中断した場合は ROM をクリアしてから終了
    rom_attr_xfer(main_param.sltnum, &ROM_ATTR_ASCII16_WO_WP);
    clear_rom(main_param.sltnum);
    rom_attr_xfer(main_param.sltnum, &ROM_ATTR_ASCII16);
    init_bank_reg(main_param.sltnum, &ROM_ATTR_ASCII16);
    bdos_term(BDOS_ERR_ABORT);
}

/***********************************************
 * main
 ***********************************************/
int main(int argc, char *argv[])
{
    char *rom_file = NULL;
    char *rom_type = NULL;
    ROM_ATTR_PTR_t rom_attr = NULL;

    // バージョン出力
    output_version();

    // V9990TANG: DEFAB/TERM y los handles son de MSX-DOS 2
    if(bdos_get_version() < 2)
    {
        printf(MSG_ERR_DOS2);
        return 1;
    }

    // コマンドラインをパース
    if(parse_param(&main_param, argc, argv)) return 1;

    // ヘルプ出力
    if(main_param.help_flag)
    {
        output_usage();
        output_help();
        return 0;
    }

    // ファイルが指定されていない場合
    if(!(main_param.nofile_flag || main_param.disable_header_flag) && main_param.rom_file[0] == '\0')
    {
        output_usage();
        return 1;
    }

    // コンフィグレーションファイルを指定している？
    if(main_param.use_conf_file)
    {
        // コンフィグレーションファイルから ROM ファイルパスを得る
        if(load_config_file(main_param.rom_file))
        {
            return 1;
        }

        // コンフィグレーションファイルで指定された ROM ファイルとタイプを使用
        rom_file = config.rom_file;
        rom_type = config.rom_type;
    }
    else
    {
        // コマンドラインから ROM ファイルを指定
        rom_file = main_param.rom_file;
    }

    // コマンドラインから ROM タイプを指定している場合
    if(main_param.rom_type[0] != '\0') rom_type = main_param.rom_type;

    // ROM タイプ名から属性を探す
    if(search_keyword((VOID_PTR_t*)&rom_attr, rom_attr_table, rom_type))
    {
        printf(MSG_UNKNOWN_ROM_TYPE, rom_type);
        return 1;
    }

    // V9990TANG: tamano de la imagen frente al tipo, antes de tocar el cartucho
    uint32_t image_kb = 0;
    int xfer_file_flag = !main_param.nofile_flag;
    if(xfer_file_flag && check_image_size(rom_file, rom_attr, &image_kb)) return 1;
    image_val_mask = xfer_file_flag ? get_image_val_mask(rom_attr, image_kb) : rom_attr->val_mask;

    // コマンドラインでカートリッジスロットが指定されていない場合はカートリッジを探す
    if(main_param.sltnum == (uint8_t)0xFF)
    {
        if(search_cartridge(&main_param.sltnum))
        {
            printf(MSG_CARTRIDGE_NOT_FOUND);
            return 1;
        }
    }

    // V9990TANG: y frente a la ventana de la SDRAM del cartucho (3Eh)
    if(xfer_file_flag)
    {
        uint16_t window_kb = get_window_kb(main_param.sltnum);
        if(image_kb > (uint32_t)window_kb)
        {
            printf(MSG_ERR_WINDOW, image_kb, window_kb);
            return 1;
        }
    }

    // ROM イメージファイルの転送
    char buff[8];
    printf(MSG_PROP_SLOT, slot_to_str(buff, sizeof(buff), main_param.sltnum));
    printf(MSG_PROP_ROM_FILE, rom_file);
    printf(MSG_PROP_ROM_TYPE, rom_attr->name);
    if(bdos_set_about_handler((uint16_t)abort_handler))
    {
        printf(MSG_HANDLER_ERROR);
        return 1;        
    }
    int res = load_rom_image(main_param.sltnum, rom_attr, main_param.nofile_flag ? NULL : rom_file, main_param.disable_header_flag);
    bdos_set_about_handler(0);

    if(res == 0)
    {
        set_rom_enable(main_param.sltnum, 1, !main_param.once_flag);
    }

    printf(MSG_COMPLETE);

    // V9990TANG: PLAIN0 no sobrevive a un /RESET
    if(res == 0 && (rom_attr->bank[3].reserved & MODE_PLAIN0) && !main_param.reset_flag)
    {
        printf(MSG_NOTE_PLAIN0);
    }

    if(res == 0 && main_param.reset_flag)
    {
        printf(MSG_REBOOT);
        reboot();
    }

    return res;
}
