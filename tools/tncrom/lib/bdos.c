//
// bdos.c
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

#include <string.h>
#include "types.h"
#include "bdos.h"

#define BDOS_FOPEN  (0x0F)
#define BDOS_FMAKE  (0x16)
#define BDOS_FCLOSE (0x10)
#define BDOS_RDSEQ  (0x14)
#define BDOS_WRSEQ  (0x15)
#define BDOS_SETDTA (0x1A)
#define BDOS_OPEN   (0x43)
#define BDOS_CREATE (0x44)
#define BDOS_CLOSE  (0x45)
#define BDOS_READ   (0x48)
#define BDOS_WRITE  (0x49)
#define BDOS_DOSVER (0x6F)
#define BDOS_FFIRST (0x40)
#define BDOS_TERM   (0x62)
#define BDOS_DEFAB  (0x63)

static uint8_t bdos_a;
static uint8_t bdos_b;
static uint8_t bdos_c;
static uint16_t bdos_de;
static uint16_t bdos_hl;
static uint16_t bdos_ix;

/***********************************************
 * V9990TANG (port a SDCC): llamada al BDOS con los registros en las
 * variables bdos_*: entra A, B, C, DE, HL, IX y sale lo mismo. Sin
 * argumentos, asi no depende del convenio de llamada de SDCC; guarda IX
 * (puntero de marco de SDCC) e IY.
 ***********************************************/
static void bdos_raw(void) __naked
{
__asm
    push    ix
    push    iy
    ld      ix, (_bdos_ix)
    ld      hl, (_bdos_hl)
    ld      de, (_bdos_de)
    ld      a, (_bdos_c)
    ld      c, a
    ld      a, (_bdos_b)
    ld      b, a
    ld      a, (_bdos_a)
    call    0x0005
    ld      (_bdos_a), a
    ld      a, b
    ld      (_bdos_b), a
    ld      a, c
    ld      (_bdos_c), a
    ld      (_bdos_de), de
    ld      (_bdos_hl), hl
    ld      (_bdos_ix), ix
    pop     iy
    pop     ix
    ret
__endasm;
}

/***********************************************
 * BDOS コール
 *  引数
 *    c         : ファンクション番号
 *    de        : DE レジスタ値
 *  戻り値
 *    A レジスタ値
 ***********************************************/
static int bdos_call_de(uint8_t num, uint16_t de)
{
    bdos_c = num; bdos_de = de; bdos_b = 0; bdos_a = 0;
    bdos_raw();
    return bdos_a;
}

/***********************************************
 * BDOS コール
 *  引数
 *    c         : ファンクション番号
 *    b         : B レジスタ値
 *  戻り値
 *    A レジスタ値
 ***********************************************/
static int bdos_call_b(uint8_t num, uint8_t b)
{
    bdos_c = num; bdos_b = b; bdos_a = 0;
    bdos_raw();
    return bdos_a;
}

/***********************************************
 * BDOS コール
 *  引数
 *    c         : ファンクション番号
 *    b         : B レジスタ値
 *    de        : DE レジスタ値
 *    hl        : HL レジスタ値
 *  戻り値
 *    A レジスタ値
 ***********************************************/
static int bdos_call_b_de_hl(uint8_t num, uint8_t b, uint16_t de, uint16_t hl)
{
    bdos_c = num; bdos_b = b; bdos_de = de; bdos_hl = hl; bdos_a = 0;
    bdos_raw();
    return bdos_a;
}

/***********************************************
 * BDOS コール
 *  引数
 *    c         : ファンクション番号
 *    a         : A レジスタ値
 *    de        : DE レジスタ値
 *  戻り値
 *    A レジスタ値
 ***********************************************/
static int bdos_call_a_de(uint8_t num, uint8_t a, uint16_t de)
{
    bdos_c = num; bdos_a = a; bdos_de = de;
    bdos_raw();
    return bdos_a;
}

/***********************************************
 * BDOS コール
 *  引数
 *    c         : ファンクション番号
 *    a         : A レジスタ値
 *    b         : B レジスタ値
 *    de        : DE レジスタ値
 *  戻り値
 *    A レジスタ値
 ***********************************************/
static int bdos_call_a_b_de(uint8_t num, uint8_t a, uint8_t b, uint16_t de)
{
    bdos_c = num; bdos_a = a; bdos_b = b; bdos_de = de;
    bdos_raw();
    return bdos_a;
}

/***********************************************
 * BDOS コール
 *  引数
 *    c         : ファンクション番号
 *    b         : B レジスタ値
 *    de        : DE レジスタ値
 *    hl        : HL レジスタ値
 *    ix        : IX レジスタ値
 *  戻り値
 *    A レジスタ値
 ***********************************************/
static int bdos_call_b_de_hl_ix(uint8_t num, uint8_t b, uint16_t de, uint16_t hl, uint16_t ix)
{
    bdos_c = num; bdos_b = b; bdos_de = de; bdos_hl = hl; bdos_ix = ix; bdos_a = 0;
    bdos_raw();
    return bdos_a;
}

/***********************************************
 * V9990TANG: version del sistema (DOSVER, 6Fh)
 *  戻り値
 *    version principal del nucleo (B): 1 = MSX-DOS 1, >= 2 = MSX-DOS 2 / Nextor
 ***********************************************/
uint8_t bdos_get_version(void)
{
    int res = bdos_call_de(BDOS_DOSVER, 0);
    return (res != 0) ? 1 : (bdos_b < 2 ? 1 : bdos_b);
}

/***********************************************
 * V9990TANG: un caracter a la consola (CONOUT, 02h)
 ***********************************************/
void bdos_conout(char ch)
{
    bdos_c = 0x02; bdos_de = (uint8_t)ch;
    bdos_raw();
}

static void make_fcb(BDOS_FILE_t *file, char *path)
{
        // clear fcb
        memset(&file->dos1, 0, sizeof(file->dos1));

        // ファイル名
        int len = 0;
        char *p = path;
        for(;;)
        {
            if(*p == '\0') break;
            char c = *p++;
            if(c == '.') break;
            if(len < 8) file->dos1.file_name[len++] = c;
        }
        for(; len < 8; len++) file->dos1.file_name[len] = ' ';

        // 拡張子
        len = 0;
        for(;;)
        {
            if(*p == '\0') break;
            char c = *p++;
            if(len < 3) file->dos1.file_ext[len++] = c;
        }
        for(; len < 3; len++) file->dos1.file_ext[len] = ' ';
//printf("fcb="); for(int i = 0; i < 8+3; i++) printf("%c", file->dos1.file_name[len++]); printf("\n");
}

/***********************************************
 * ファイルオープン
 *  引数
 *    file      : ファイル構造体
 *    path      : ファイルのパス
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
int bdos_fopen(BDOS_FILE_t *file, char *path)
{
    int res;
    res = bdos_call_de(BDOS_DOSVER, 0);
    file->type = (res != 0 || bdos_b < 2) ? TYPE_DOS1 : TYPE_DOS2;

    file->current_pos = 0;

    if(file->type == TYPE_DOS1)
    {
        // FCB 作成
        make_fcb(file, path);

        // ファイルオープン
        res = bdos_call_de(BDOS_FOPEN, (uint16_t)&file->dos1);
        if(res) return res;

        //
        file->dos1.record_size = 128;
        file->dos1.current_block = 0;
        file->dos1.random_record = 0;
        return 0;
    }
    else
    {
        // ファイルサイズを得る
        if(0 != (res = bdos_call_b_de_hl_ix(BDOS_FFIRST, 0, (uint16_t)path, (uint16_t)path, (uint16_t)file->dos2.buffer))) return res;
        file->dos2.file_size = *(uint32_t*)(bdos_ix + 21);

        // ファイルオープン
        if(0 != (res = bdos_call_a_de(BDOS_OPEN, BDOS_OPEN_RDONLY, (uint16_t)path))) return res;
        file->dos2.handle = bdos_b;
        return 0;
    }
}

/***********************************************
 * ファイルオープン
 *  引数
 *    file      : ファイル構造体
 *    path      : ファイルのパス
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
int bdos_fcreate(BDOS_FILE_t *file, char *path)
{
    int res;
    res = bdos_call_de(BDOS_DOSVER, 0);
    file->type = (res != 0 || bdos_b < 2) ? TYPE_DOS1 : TYPE_DOS2;

    file->current_pos = 0;

    if(file->type == TYPE_DOS1)
    {
        // FCB 作成
        make_fcb(file, path);

        // ファイルオープン
        return bdos_call_de(BDOS_FMAKE, (uint16_t)&file->dos1);
    }
    else
    {
        file->dos2.file_size = 0;

        // ファイルオープン
        if(0 != (res = bdos_call_a_b_de(BDOS_CREATE, BDOS_OPEN_WRONLY, 0x80, (uint16_t)path))) return res;
        file->dos2.handle = bdos_b;
        return 0;
    }
}

/***********************************************
 * ファイルクローズ
 *  引数
 *    file      : 対象のファイル
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
int bdos_fclose(BDOS_FILE_t *file)
{
    if(file->type == TYPE_DOS1)
    {
        // ファイルクローズ
        return bdos_call_de(BDOS_FCLOSE, (uint16_t)&file->dos1);
    }
    else
    {
        // ファイルクローズ
        return bdos_call_b(BDOS_CLOSE, file->dos2.handle);
    }
}

/***********************************************
 * ファイルサイズ取得
 *  引数
 *    file      : 対象のファイル
 *    size      : ファイルサイズを格納する変数のポインタ
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
int bdos_file_size(BDOS_FILE_t *file, uint32_t *size)
{
    if(file->type == TYPE_DOS1)
    {
        if(size != NULL) *size = file->dos1.file_size;
        return 0;
    }
    else
    {
        if(size != NULL) *size = file->dos2.file_size;
        return 0;
    }
}

/***********************************************
 * EOF チェック
 *  引数
 *    file      : 対象のファイル
 *  戻り値
 *    0  : 終端ではない
 *    !0 : ファイルの終端
 ***********************************************/
int bdos_eof(BDOS_FILE_t *file)
{
    uint32_t size = (file->type == TYPE_DOS1) ? file->dos1.file_size : file->dos2.file_size;
    return file->current_pos >= size ? 1 : 0;
}

/***********************************************
 * シーケンシャルリード
 *  引数
 *    file      : 対象のファイル構造体
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
int bdos_fread(BDOS_FILE_t *file, uint16_t *readed)
{
    uint32_t remain = (file->type == TYPE_DOS1 ? file->dos1.file_size : file->dos2.file_size) - file->current_pos;
    if(remain == 0)
    {
        if(readed != NULL) *readed = 0;
        return -1;
    }

    int res;
    uint16_t readed_size;
    if(file->type == TYPE_DOS1)
    {
        // DTA アドレス設定
        if(0 != (res = bdos_call_de(BDOS_SETDTA, (uint16_t)file->buffer))) return res;


        // 128バイトシーケンシャルリード
        if(0 != (res = bdos_call_de(BDOS_RDSEQ, (uint16_t)&file->dos1))) return res;

        //
        readed_size = 128;
    }
    else
    {
        // 128バイトリード
        if(0 != (res = bdos_call_b_de_hl(BDOS_READ, file->dos2.handle, (uint16_t)file->buffer, 128))) return res;

        //
        readed_size = bdos_hl;
    }

    //
    if(remain < (uint32_t)readed_size)
    {
        readed_size = remain & 0xFFFF;
    }

    file->current_pos += (uint32_t)readed_size;
    if(readed != NULL) *readed = readed_size;
    return 0;
}

/***********************************************
 * シーケンシャルリード
 *  引数
 *    file      : 対象のファイル構造体
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
int bdos_fread_n(BDOS_FILE_t *file, uint16_t addr, uint16_t size, uint16_t *readed)
{
    uint32_t remain = (file->type == TYPE_DOS1 ? file->dos1.file_size : file->dos2.file_size) - file->current_pos;
    if(remain == 0)
    {
        if(readed != NULL) *readed = 0;
        return -1;
    }

    int res;
    uint16_t readed_size;
    if(file->type == TYPE_DOS1)
    {
        // DTA アドレス設定
        if(0 != (res = bdos_call_de(BDOS_SETDTA, (uint16_t)file->buffer))) return res;


        // 128バイトシーケンシャルリード
        if(0 != (res = bdos_call_de(BDOS_RDSEQ, (uint16_t)&file->dos1))) return res;

        //
        readed_size = 128;
    }
    else
    {
        if(0 != (res = bdos_call_b_de_hl(BDOS_READ, file->dos2.handle, addr, size))) return res;

        //
        readed_size = bdos_hl;
    }

    //
    if(remain < (uint32_t)readed_size)
    {
        readed_size = remain & 0xFFFF;
    }

    file->current_pos += (uint32_t)readed_size;
    if(readed != NULL) *readed = readed_size;
    return 0;
}

/***********************************************
 * シーケンシャルライト
 *  引数
 *    file      : 対象のファイル構造体
 *  戻り値
 *    0  : 成功
 *    !0 : 失敗
 ***********************************************/
int bdos_fwrite(BDOS_FILE_t *file, uint16_t *written)
{
    int res;
    uint16_t write_size;
    if(file->type == TYPE_DOS1)
    {
        // DTA アドレス設定
        if(0 != (res = bdos_call_de(BDOS_SETDTA, (uint16_t)file->buffer))) return res;


        // 128バイトシーケンシャルライト
        if(0 != (res = bdos_call_de(BDOS_WRSEQ, (uint16_t)&file->dos1))) return res;

        //
        write_size = 128;
    }
    else
    {
        // 128バイトライト
        if(0 != (res = bdos_call_b_de_hl(BDOS_WRITE, file->dos2.handle, (uint16_t)file->buffer, 128))) return res;

        //
        write_size = bdos_hl;
    }

    //
    file->current_pos += (uint32_t)write_size;
    if(file->type == TYPE_DOS1)
    {
        if(file->current_pos > file->dos1.file_size) file->dos1.file_size = file->current_pos;
    }
    else
    {
        if(file->current_pos > file->dos2.file_size) file->dos2.file_size = file->current_pos;
    } 
    if(written != NULL) *written = write_size;
    return 0;
}

/***********************************************
 * アボートハンドラ設定
 *  引数
 *    addr          : ハンドラのアドレス
 *  戻り値
 *    0  : 終端ではない
 *    !0 : ファイルの終端
 ***********************************************/
int bdos_set_about_handler(uint16_t addr)
{
    return bdos_call_de(BDOS_DEFAB, addr);
}

/***********************************************
 * アボートハンドラ設定
 *  引数
 *    addr          : ハンドラのアドレス
 *  戻り値
 *    0  : 終端ではない
 *    !0 : ファイルの終端
 ***********************************************/
int bdos_term(uint8_t code)
{
    return bdos_call_b(BDOS_TERM, code);
}
