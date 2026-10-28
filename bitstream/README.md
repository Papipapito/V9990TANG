# V9990TANG 0.2beta for the WonderTANG 2.02b

V9990 (GFX9000) cartridge for MSX on the WonderTANG 2.02b (Tang Nano 20K),
with HDMI (DVI) output. **This is a test release: none of these bitstreams has
been loaded on a board yet.** The full guide, with the LED codes, the known
limits and the board test list, is in Spanish in [LEEME.md](LEEME.md).

| File | Contents | SHA-256 (first 12) | Gowin CheckSum |
|---|---|---|---|
| `v9990tang_wt202b_v9990_xtal_0.1beta.fs` | V9990 only, Tang crystal clock | `f668f7abbfc8` | `0x345D` |
| `v9990tang_wt202b_v9990_sync_0.1beta.fs` | V9990 only, slot clock | `5f5369227e3e` | `0x7B75` |
| `v9990tang_wt202b_megaram_xtal_0.1beta.fs` | V9990 + 4 MB SCC-I MegaRAM, crystal clock | `eca3b40eba33` | `0x95F1` |
| `v9990tang_wt202b_megaram_sync_0.1beta.fs` | V9990 + 4 MB SCC-I MegaRAM, slot clock | `3812094d40d5` | `0x4693` |
| `v9990tang_wt202b_megaram_nextor_xtal_0.2beta.fs` | **V9990 + 4 MB SCC-I MegaRAM + Nextor on the Tang microSD**, crystal clock | `47ed9b813c81` | `0x0BA7` |
| `v9990tang_wt202b_megaram_nextor_sync_0.2beta.fs` | same, slot clock | `3c52b74b0bdb` | `0x1D3F` |
| `v9990tang_nextor_pack_0.2beta.bin` | Nextor 2.1.2 MegaFlashSDSCC kernel, unchanged, for the flash at `0x100000` (only `megaram_nextor_*`; see `NEXTOR_LICENSE.md`) | `b2394dfca88e` | — |
| `TNCROM.COM` | ROM loader for the MegaRAM (r3), MSX-DOS 2 or Nextor | `5f40a90d4918` | — |

Full hashes are in `SHA256SUMS.txt`. The four 0.1beta bitstreams are unchanged.

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
