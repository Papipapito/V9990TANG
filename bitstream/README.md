# V9990TANG 0.1beta for the WonderTANG 2.02b

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
| `TNCROM.COM` | ROM loader for the MegaRAM (r3), MSX-DOS 2 or Nextor | `5f40a90d4918` | — |

Full hashes are in `SHA256SUMS.txt`.

- **xtal** always boots and gives HDMI even with the MSX off; the V9990 runs
  0.57 % fast (60.27 Hz). Try this one first.
- **sync** runs the V9990 at the exact rate, locked to the MSX, but needs the
  MSX on for HDMI and may fail to lock on machines with an unusual slot clock
  (the LED then shows the error code and the MSX boots without the cartridge).
- **megaram** adds a 4 MB Konami SCC-I MegaRAM in subslot 0, loaded with
  `TNCROM.COM`. It only works at 3.58 MHz. Fit jumper J3 to hear the SCC.

Program to SRAM first (`openFPGALoader -b tangnano20k <file.fs>`), then to the
external flash at `0x000000` (`openFPGALoader -b tangnano20k -f <file.fs>`, or
Gowin Programmer "External Flash Mode"). Erasing the whole flash also erases
the MoonTANG YRW801 sample ROM at `0x200000`.
