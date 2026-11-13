# V9990TANG 0.3beta for the WonderTANG 2.02b

V9990 (GFX9000) cartridge for MSX on the WonderTANG 2.02b (Tang Nano 20K),
with HDMI (DVI) output. **This is a test release: none of these bitstreams has
been loaded on a board yet.** The full guide, with the LED codes, the known
limits and the board test list, is in Spanish in [LEEME.md](LEEME.md).

| File | Contents | SHA-256 (first 12) | Gowin CheckSum |
|---|---|---|---|
| `v9990tang_wt202b_v9990_xtal_0.3beta.fs` | V9990 only, Tang crystal clock | `8bae0158b588` | `0x5A17` |
| `v9990tang_wt202b_v9990_sync_0.3beta.fs` | V9990 only, slot clock | `f569613443eb` | `0xF710` |
| `v9990tang_wt202b_megaram_xtal_0.3beta.fs` | V9990 + 4 MB SCC-I MegaRAM, crystal clock | `eab15aed5250` | `0x78D0` |
| `v9990tang_wt202b_megaram_sync_0.3beta.fs` | V9990 + 4 MB SCC-I MegaRAM, slot clock | `511b0136c667` | `0xC95B` |
| `v9990tang_wt202b_megaram_nextor_xtal_0.3beta.fs` | **V9990 + 4 MB SCC-I MegaRAM + Nextor on the Tang microSD**, crystal clock | `4dd1a79c26f2` | `0x7E29` |
| `v9990tang_wt202b_megaram_nextor_sync_0.3beta.fs` | same, slot clock | `cfcd960039aa` | `0x5105` |
| `v9990tang_nextor_pack_0.2beta.bin` | Nextor 2.1.2 MegaFlashSDSCC kernel, unchanged, for the flash at `0x100000` (only `megaram_nextor_*`; see `NEXTOR_LICENSE.md`) | `b2394dfca88e` | — |
| `TNCROM.COM` | ROM loader for the MegaRAM (r3), MSX-DOS 2 or Nextor | `5f40a90d4918` | — |

Full hashes are in `SHA256SUMS.txt`. **All six bitstreams are new in 0.3beta**;
the Nextor pack is unchanged (no need to rewrite `0x100000`).

0.3beta brings the V9990 fixes made to the same core in the MSXimus Z: CMMC
and CMMM at 2/4/8/16 bpp (Chase H.Q.), 16 bpp byte order in LMMV, PSET, LINE,
LMMC and SRCH, P#2 writes without polling TR held with /WAIT during LMMC/CMMC
(SymbOS G9K), YJK/YUV decoding, line counter restart on R#17/R#21 writes
(Xybots split screen), and horizontal alignment (bitmap pixel 0 on the first
visible dot in every mode, cursor on its X; Dream Puzzle right edge).

- **xtal** always boots and gives HDMI even with the MSX off; the V9990 runs
  0.57 % fast (60.27 Hz). Try this one first.
- **sync** runs the V9990 at the exact rate, locked to the MSX, but needs the
  MSX on for HDMI and may fail to lock on machines with an unusual slot clock
  (the LED then shows the error code and the MSX boots without the cartridge).
- **megaram** adds a 4 MB Konami SCC-I MegaRAM in subslot 0, loaded with
  `TNCROM.COM`. It only works at 3.58 MHz. Fit jumper J3 to hear the SCC.
- **megaram_nextor** adds Nextor in subslot 2 with the Tang's microSD as the
  disk (MegaFlashROM SCC+ SD SPI emulation, official Konamiman kernel). At
  boot the cartridge copies the kernel from the Tang flash at `0x100000` to
  SDRAM (~70 ms, boot hold raised to 200 ms, fail-open). Without the pack in
  flash it behaves like `megaram`. SD: FAT12/FAT16 with Nextor's `.SYS` files,
  `TNCROM.COM` and the ROMs.

Program to SRAM first (`openFPGALoader -b tangnano20k <file.fs>`), then to the
external flash at `0x000000` (`openFPGALoader -b tangnano20k -f <file.fs>`, or
Gowin Programmer "External Flash Mode"). For `megaram_nextor_*` also write the
pack at `0x100000` (`openFPGALoader -b tangnano20k -f -o 0x100000
v9990tang_nextor_pack_0.2beta.bin`, or Gowin Programmer "exFlash C Bin
Erase,Program thru GAO-Bridge" with start address `0x100000`). Erasing the
whole flash also erases the MoonTANG YRW801 sample ROM at `0x200000`.
