# DYMO LabelWriter 450: Fähigkeiten auf Protokoll- und Hardwareebene, Grundlage für MacLabel

Stand: 23.10.2026, macOS 27.0 (Darwin 27.0.0), MacBook Pro (J314s, Apple Silicon)

Kennzeichnung der Aussagen:
- **[B]** beobachtet: REA-Dekompilierung oder lokales Artefakt (PPD, ioreg, Info.plist). REA-Evidence-IDs sind angegeben.
- **[D]** dokumentiert: offizielles DYMO-Dokument oder DYMO-GPL-Quellcode, mit URL.
- **[I]** abgeleitet: Schlussfolgerung, nicht direkt verifiziert.

Quellen:
- [D1] LabelWriter 450 Series Technical Reference Manual (Sanford/DYMO, 2009, 59 S.). Kopie: https://orcascan.com/guides/files/dymo-labelwriter-450-datasheet-pMc0yVAY4lfZp+02FIvMg-2dcf12e5.pdf . Lokal: (lokal, nicht im Repo), Text: (lokal, nicht im Repo)
- [D2] DYMO-CUPS-Treiber 1.4 (GPL), also die Quelle von raster2dymolw v1: https://github.com/matthiasbock/dymo-cups-drivers (`src/lw/LabelWriterDriver.cpp`, `LabelWriterLanguageMonitor.{h,cpp}`, `raster2dymolw.cpp`)
- [D3] DYMO LW5xx-Linux-Treiber (GPL, offizielles DYMO-Repo): https://github.com/dymosoftware/Drivers (`LW5xx_Linux/src/lw/LabelWriterDriverV2.cpp`, `LabelWriterLanguageMonitorV2.cpp`)
- [D4] LWSE450 Technical Reference: https://download.dymo.com/dymo/user-guides/LabelWriter/LWSE450/LWSE450_TechnicalReference.pdf (nur zur Abgrenzung)
- [D5] LW550-NFC/DRM (Sekundärquellen): https://mjtsai.com/blog/2022/02/24/dymo-label-printer-rfid-drm , https://www.eevblog.com/forum/reviews/dymo-550-thermal-printer-drm-hacking/msg4053331/
- [D6] Drittprojekt mit Rohprotokoll: https://github.com/minlux/dymon (nicht im Detail geprüft)

Die REA-Sitzungen (raster2dymolw v1 sha256 `6e1c482a…28d5` und V2 `7170a845…c9cc9`, jeweils arm64-Slice) sind geschlossen.

---

## 1. Hardware des LW450 (dieses Gerät)

| Eigenschaft | Wert | Beleg |
|---|---|---|
| USB VID/PID | 0x0922 / 0x0020, bcdDevice 0x0112, bcdUSB 0x0200 | [B] ioreg; [D1] S. 14 |
| USB-Geschwindigkeit | Full Speed, 12 Mbit/s (`USBSpeed=1`, `UsbLinkSpeed=12000000`) | [B] ioreg; [D1] S. 7 |
| Interface | eine Konfiguration, Interface 0: Klasse 7 (Drucker), Subklasse 1, Protokoll 2 (bidirektional), 2 Endpoints (Bulk OUT und Bulk IN) | [B] ioreg. Die Endpoint-Adressen sind ohne Öffnen nicht sichtbar [I] |
| USB-Seriennummer | `<Geräte-Seriennummer>` | [B] ioreg |
| CUPS-URI-Seriennummer | `01010112345600` (weicht von der USB-Seriennummer ab) | [B] lpstat. Vermutlich stammt sie aus dem IEEE-1284-Device-ID-Feld `SN:` und ist ein Platzhalter [I]. **MacLabel sollte Geräte deshalb über die USB-Seriennummer und locationID zuordnen, nicht über die CUPS-URI.** |
| Druckkopf | 672 Dots, 300 dpi, 57 mm breit, Dots 0,085 mm; Papierweg 63 mm | [D1] S. 7 |
| Auflösung in Transportrichtung | 300 lpi (Text-Modus, ESC h) oder 600 lpi (Barcode/Grafik-Modus, ESC i: halbe Schrittweite, langsamer) | [D1] S. 7, 11, 18 |
| Maximale Zeilenbreite | 84 Byte = 672 Bit (Default von ESC D) | [D1] S. 8, 15; [B] Konstruktor `+0x30 = 0x54` (ev_8c1e487b…) |
| Etikettenerkennung | Infrarot-Lichtschranke auf das Top-of-Form-Loch zwischen den Etiketten. **Keine** Erkennung von Breite, Typ oder Restmenge | [D1] S. 9 |
| Default-Etikettenlänge | 3058 Zeilen (≈10,2") nach Power-on oder Reset | [D1] S. 9, 16 |
| Thermischer Schutz | Stopp bei >70 °C, weiter bei 56 °C; Spannungseinbruch <19,3 V pausiert | [D1] S. 7 |
| Stromsparmodus | nach 30 s Leerlauf, Wake-up durch Daten | [D1] S. 11 |
| Selbsttest | Feed-Taste ca. 10 s halten | [D1] S. 11 |
| Fonts | keine eingebauten; reiner Rasterdrucker | [D1] S. 7 |

## 2. Kommandosatz der LW 400/450-Familie (Protokollklasse „LW-Classic“), byte-genau

Alle Kommandos gehen über Bulk OUT. ESC = 0x1B. Mehrbyte-Werte sind bei ESC L und ESC Q **Big-Endian** (MSB zuerst).

| Kommando | Bytes | Bedeutung | Nutzt DYMO macOS? | Beleg |
|---|---|---|---|---|
| Resync | 156 × `1B` (Doku: mindestens 85) | beendet eine angefangene Rasterzeile. DYMO verwendet das als „Reset“ und nicht ESC @ | ja, StartDoc und ResetPrinter | [B] GetResetCommand `vector(0x9c, *0x1000088e8)`, Byte = 0x1B (ev_68a2c98a…, ev_fab8c294…); [D1] S. 9; [D2] |
| ESC @ | `1B 40` | Reset aller Parameter (Dot Tab, Line Tab, BPL …), TOF=true, **verwirft den Puffer sofort** | **nein** | [D1] S. 17 |
| ESC * | `1B 2A` | interne Parameter auf Default | **nein** | [D1] S. 17 |
| ESC A | `1B 41` → **1 Byte** Status über Bulk IN | Status, siehe §3 | ja, nur während eines Jobs und nur bei `usb://` | [B] GetRequestStatusCommand `0x411b` (ev_2dbd3424…); [D1] S. 17 |
| ESC V | `1B 56` → 10 ASCII-Zeichen, z. B. `93089v0K` (7 Ziffern Modellnummer, `v`, 2 Zeichen FW) | Modell und Firmware | **nein** | [D1] S. 18 |
| ESC B n | `1B 42 n` (0…83) | Dot Tab: Startbyte der Zeile (linker Rand in 8-Dot-Schritten) | ja: einmal `1B 42 00` in StartDoc, danach pro Zeile bei Änderung | [B] StartDoc-Asm (ev_f9077d24…); [D1] S. 15 |
| ESC D n | `1B 44 n` (1…84) | Bytes pro Zeile | ja, bei Änderung vor SYN/ETB | [B] SendBytesPerLine (ev_0568d7fa…); [D1] S. 15 |
| ESC Q hi lo | `1B 51 hi lo` | Line Tab. Im 450-Manual nicht dokumentiert, Erbe der LW300/400-Serie | ja: `1B 51 00 00` in StartDoc | [B] SendLineTab/StartDoc (ev_50d60c35…, ev_f9077d24…); [D2] |
| ESC L hi lo | `1B 4C hi lo` | Etikettenlänge in Zeilen (sense hole zu sense hole). 0x8000–0xFFFF = Endlosmodus | ja: die Länge pro Seite, `FF FF` bei Endlos | [B] StartPage/SendLabelLength (ev_acdb245b…, ev_d1f9c1eb…); [D1] S. 9, 16 |
| ESC E | `1B 45` | Form Feed bis Abreißkante. Danach Rückwärtsfahrt vor dem nächsten Etikett | ja, nur am Dokumentende (400er-Treiber) | [B] CLabelWriterDriver400::EndDoc (ev_2dbd3424…); [D1] S. 16 |
| ESC G | `1B 47` | Short Form Feed: nächstes Etikett in Druckposition, ohne Rückwärtsfahrt | ja, zwischen Seiten (400er-Treiber) und vor einem Reprint | [B] CLabelWriterDriver400::EndPage, ReprintLabel (ev_2dbd3424…, ev_1bf5cb3b…); [D1] S. 16 |
| ESC f 1 n | `1B 66 01 n` (n ≤ 255) | n Leerzeilen vorschieben (Zeilenhöhe hängt von ESC h/i ab) | ja: Leerzeilen werden in 255er-Blöcken zusammengefasst | [B] SendSkipLines (ev_65d15b1b…); [D1] S. 17 |
| SYN | `16 d0…d(BPL−1)` | eine Rasterzeile, unkomprimiert, MSB = linkes Pixel, 1 = schwarz | ja | [B]; [D1] S. 8, 18 |
| ETB | `17 r…` | eine Rasterzeile, RLE: Bit 7 = Farbe (1 = schwarz), Bits 0–6 = Lauflänge−1 (max. 128). Die Summe muss BPL×8 ergeben | ja, wenn kürzer | [B]; [D1] Anhang A |
| ESC h | `1B 68` | Text-Modus 300×300, schnell (Default) | ja (`DymoPrintQuality=Text`) | [B] SendPrintQuality: `0x68`, bei quality==1 `+1` (ev_e456e549…); [D1] S. 18 |
| ESC i | `1B 69` | Barcode/Grafik 300×600, langsamer, präzisere Dots | ja (`DymoPrintQuality=Graphics`) | wie oben |
| ESC c / d / e / g | `1B 63` / `1B 64` / `1B 65` / `1B 67` | Strobe-Zeit 75 % / 87,5 % / 100 % / 112,5 % (Light/Medium/Normal/Dark) | ja (`DymoPrintDensity`) | [B] SendPrintDensity: Tabelle `0x67656463 >> (8·d)`, d≥4 → `e` (ev_bd995b5d…); [D1] S. 19 |
| ESC q n | `1B 71 30/31/32` | nur Twin Turbo: Rolle Auto / links / rechts | ja (InputSlot), **nur einmal pro Dokument** | [B] GetRollSelectCommand (ev_2dbd3424…); [D1] S. 16 |
| ESC y / ESC z | `1B 79` / `1B 7A` | 204×204 bzw. 136×204 dpi, **nur SE450 und LW300-Serie** | für den 450 nie gesendet | [B] SendResolution: res 1 → `z`, 2 → `y`, 0 → nichts (ev_1c779a7f…); [D2] Enum `res136/res204 (SE450)` |

**Exakte Bytefolge eines Jobs von DYMO macOS für den LW450** [B]:
```
StartDoc:   1B×156 | (ESC y/z nur bei 203dpi-PPDs) | 1B 51 00 00 | 1B 42 00 | 1B 68|69 | 1B 63|64|65|67
            (Twin Turbo zusätzlich: 1B 71 3x; der LM sendet vorab nochmals 1B×156 und, wenn Roll-Sync aktiv, 1B 71 3x)
StartPage:  1B 4C hi lo   (hi lo = PageSize[1]pt × HWResolution[1] / 72; Endlos: FF FF)
pro Zeile:  [1B 44 n bei Änderung] [1B 42 t bei Änderung] 16 <n Byte> | 17 <RLE>   ;  Leerzeilen: 1B 66 01 k
EndPage:    1B 47   (Short Form Feed)
EndDoc:     1B 45   (Form Feed zur Abreißkante)
```
(Seitenhöhe: ProcessPageOptions-Asm `PageSize[1]@0x164 × HWResolution[1]@0x118 × 0x38E38E39 >> 36` = /72, ev_2995c5d4…; cupsInteger0 = SetPageOffset.)

## 3. Status-Byte (ESC A) beim LW450

| Bit | [D1] S. 10/17 | [D2] Header-Enum | Verwendung im ausgelieferten Filter [B] |
|---|---|---|---|
| 0 (0x01) | Ready (Papier drin, kein Stau), laut S. 10 „immer 1“ | – | – |
| 1 (0x02) | Top of Form | `TOF_BIT` | Erfolg = `(s & 0x0A) == 0x02`. Bei Endlospapier setzt der Filter Bit 1 künstlich |
| 3 (0x08) | „not used“ | `ROLL_CHANGED_BIT` | ist Bit 3 gesetzt, entfällt das ESC G vor einem Reprint |
| 5 (0x20) | No paper | `PAPER_OUT_BIT` | – |
| 6 (0x40) | Paper jam | `PAPER_FEED_BIT` | – |
| 7 (0x80) | Printer error (auch bei Papierende) | `ERROR_BIT` | PollUntilPaperIn wartet auf `(s & 0x82) == 0x02`. Job-Status = `(s>>6)&2` |

„Bereit“ = `0x03` [D1]. Ablauf im Filter [B] (CheckStatusAndReprint / PollUntilPaperIn / ReprintLabel, ev_1bf5cb3b…): Statusabfrage nach jeder Seite. Bei Fehler wird gepollt, bis Papier da ist (100-ms-Takt), dann `ESC G` und die gepufferte Seite erneut gesendet. Das geschieht **nur**, wenn `DEVICE_URI` mit `usb://` beginnt (IsLocal).

## 4. PPD-Optionen und ihre Wirkung (lw450, lw450t, lw450tt, lw450dl, lw4xl, lw400, lw550, lw550t, lw5xl)

[B] aus `/Library/Printers/PPDs/Contents/Resources/*.ppd.gz` und ProcessPPDOptions (ev_1bf5cb3b…):

| PPD-Option | Werte | Wirkung im Filter v1 |
|---|---|---|
| `Resolution` | `300dpi` = HWRes [300 300]; `300x600dpi` = [300 600] (nur 450/450T/450TT/450DL, **nicht** 400/4XL/550/5XL) | Der Filter vergleicht nur mit `203dpi` und `203x138dpi`. **Für 300-dpi-Modelle wird nie ein Auflösungskommando gesendet.** Weil `DymoPrintQuality` (OrderDependency 21) nach `Resolution` (20) läuft, überschreibt Quality die HWResolution. `Resolution` ist damit praktisch wirkungslos [I] |
| `DymoPrintQuality` | `Text` → [300 300] + ESC h; `Graphics` → [300 600] + ESC i | einzig wirksamer Weg zu 600 lpi |
| `DymoPrintDensity` | Light/Medium/Normal(Default)/Dark → ESC c/d/e/g | |
| `DymoHalftoning` | `Default` (1 bpp, CUPS-Raster K), `ErrorDiffusion` (Default, 8 bpp Graustufen, Filter rastert), `NLL` (Non-Linear-Laplacian-Dithering) | Rasterung im Filter |
| `DymoContinuousPaper` | 0/1 → `cupsMediaType` → ESC L FFFF | |
| `InputSlot` (nur TT) | Auto/Left/Right → ESC q 0/1/2 | |
| `DymoMediaType` (nur 550/550T) | Default/Durable → V2 ESC M | |
| PageSize | 61 Größen bei 400/450/550, 73 bei 4XL, 74 bei 5XL; `cupsInteger0 0` | breiteste PaperDimension 175,44 pt bei 450 und 550 (≈731 Dots, abgeschnitten auf 672), 307,68 pt bei 4XL/5XL |
| Max. Druckbreite im Filter | Default 84 Byte; 4XL 156 Byte (1248 Dots); LW300/310/315 58 Byte; SE450 56 Byte | [B] SetMaxPrintWidth 0x9c/0x3a, SE450 0x38 |
| `HWMargins` | 0 0 0 0 | |
| `Throughput` | "8" (lw450) | |

Filterzuordnung [B] (cupsFilter): 300er/400er/450er/4XL → `Filters/raster2dymolw` (v1). 550/550T/5XL → `Filters/V2/raster2dymolw`. 550/550T zusätzlich `application/vnd.cups-raw → zpl2dymolw`, d. h. **ZPL-Emulation** für den 550. 450 DUO Tape → `raster2dymolm` (180 dpi, 128 Dots).

Treiberklassen v1 nach ModelName [B] main (ev_bb80dac6…) / [D2]:
- Twin Turbo, 450 Twin Turbo → `CLabelWriterDriverTwinTurbo`
- 400, 400 Turbo, DUO Label, 4XL, **450**, 450 Turbo, 450 DUO Label → `CLabelWriterDriver400` (ESC G zwischen Labels, ESC E am Ende)
- alles andere (300er-Serie, SE450) → `CLabelWriterDriver` (ESC E nach jedem Label)

## 5. LW 550-Protokoll („LW-V2“), aus V2/raster2dymolw [B] und [D3]

Es ist ein anderes Protokoll: Jobs mit ID, ein Bitmap-Block pro Label statt SYN-Zeilen, langer Status, Lock.

| Kommando | Bytes | Bedeutung | Beleg |
|---|---|---|---|
| ESC s id | `1B 73 i0 i1 i2 i3` (32 Bit LE, rand()) | Start Print Job | [B] SetStartPrintJob (ev_4dd70c58…); [D3] |
| ESC e x | `1B 65 63/64/65/67` | Dichte | [B] ev_7ef100ed… |
| ESC h / ESC i | `1B 68` / `1B 69` | Qualität | [B] ev_b4faa304… |
| ESC T s | `1B 54 10` normal / `1B 54 20` high speed | nur LW5xx (Flag) | [B] ev_85d49b40… |
| ESC M m … | `1B 4D m 00×7` (10 Byte), m=0 Standard, 1 Durable | Medientyp | [B] ev_7e4a39c9… |
| ESC q n | `1B 71 30+n` (0 Auto, 1 links, 2 rechts, 3 AutoRight) | nur 550 Twin | [B] SelectRoll; ProcessCupsOptions (ev_1cf4b606…) |
| ESC L lo hi | `1B 4C …` (4 Byte). 0 bei Stanzetiketten, FFFF bei Endlos | Etikettenlänge | [B]; [D3] |
| ESC n idx | `1B 6E lo hi` | Label-Index (Seitennummer) | [B]; [D3] |
| ESC D | `1B 44 01 02 W0..W3 H0..H3` (12 Byte; 1 bpp, bottom-aligned; W = Anzahl Rasterzeilen, H = Kopf-Dots auf 8 aufgerundet, LE32), danach Rohbitmap | Bilddaten-Header | [B] ev_7a43e247…; [D3] |
| ESC Z (LZ4) | `1B 5A 03 L0..L3` + 10 Byte Header (`01 02 W H`) + LZ4-HC-Block | komprimierter Bildblock, **nur bei Firmware ≥ 1000** | [B] CompressData (ev_e8467bd9…) |
| ESC G / ESC E | `1B 47` / `1B 45` | Short-FF zwischen Labels, FF am Ende | [B]; [D3] |
| ESC Q | `1B 51` | End Print Job (auch Abbruch/Unlock) | [B]; [D3] |
| ESC A l | `1B 41 l` (l=0 nur lesen, 1 Lock anfordern, 2 asynchron) → **32 Byte**, beim Twin 6+64 Byte (die ersten 6 werden verworfen) | Status | [B] ReadStatus/ProcessStatus (ev_1cf4b606…); [D3] |
| ESC V | `1B 56` → 34 Byte. FW-Version = atoi(Bytes 24..27) | Version | [B] ReadVersion |

Auswertung des 550-Status [B]/[D3]: Byte 0 Bits 0–2 = Job/Lock-Zustand (3 = Abbruch durch Gerät). Lock frei, wenn `(b0&7)|dword(b1..b4)==0`. Byte 8 Bits 0–1: Kopf-Temperatur (1 = überhitzt). Byte 10 Bits 0–3: Hauptschacht (1 offen, 2 kein Medium, 3 falsch eingelegt, 5 leer, 9 Stau, 10 „counterfeit media“). Kopfspannung in Byte 30 (Bits 0–3, 4 = zu niedrig) laut ausgeliefertem Binary, in der GPL-Quelle noch Byte 21. Der Filter serialisiert per Named Lock (Boost-Semaphore, Name aus der USB-Seriennummer).

NFC: Der 550 akzeptiert nur DYMO-Etiketten mit NFC-Tag (Größe, Restmenge). Laut Sekundärquellen zählt das Tag über ein ungeschütztes NFC-Kommando hoch [D5]. Im Status sichtbar ist das als Code 10 „counterfeit“ [B]. Wo SKU und Restanzahl im 32-Byte-Status stehen, wurde hier nicht verifiziert [I].

## 6. Modellmatrix

USB-PIDs [B] aus `/Library/Printers/DYMO/Filters/DymoUsbPrinterClassDriver.kext/Contents/Info.plist` (VID 0x0922); für die 450er-Reihe bestätigt [D1].

| Modell | PID | Kopf (Dots/dpi) | Max. BPL | Protokoll | Besonderheiten |
|---|---|---|---|---|---|
| LabelWriter 300 / 310 / 315 / 320 / 330 / 330 Turbo | 0x06 / 0x09 / 0x12 / 0x10 / 0x07 / 0x08 | 300er-Serie: 464 @ 203 dpi (58 B) [B], 330: 300 dpi [I] | 58 (300/310/315) | LW-Classic, `CLabelWriterDriver` | ESC y/z (203/136 dpi) |
| LabelWriter 400 / 400 Turbo | 0x19 / 0x1A | 672 @ 300 | 84 | LW-Classic (400) | nur 300×300 in der PPD |
| LabelWriter Twin Turbo (400) | 0x18 | 672 @ 300 | 84 | LW-Classic + ESC q | |
| LabelWriter DUO (400) Label/Tape | 0x1D / 0x17 (laut Personalities vertauscht benannt) | 672 / Tape | 84 | LW-Classic + LM-Tape | Composite-Gerät |
| LabelWriter 4XL | 0x1F | 1248 @ 300 (≈104 mm) [I aus 156 B] | 156 | LW-Classic (400) | nur 300×300 in der PPD |
| **LabelWriter 450** | **0x20** | 672 @ 300, 300/600 lpi | 84 | LW-Classic (400) | dieses Gerät |
| LabelWriter 450 Turbo | 0x21 | wie 450 | 84 | LW-Classic (400) | schneller |
| LabelWriter 450 Twin Turbo | 0x22 | 2 × 672 | 84 | LW-Classic + ESC q | ein USB-Gerät, zwei Rollen |
| LabelWriter 450 DUO | 0x23 (zwei Interfaces: Label + Tape) | 672 + Tape 128 @ 180 | 84 / 16 | Label: LW-Classic; Tape: Anhang B (ESC C Bandtyp, ESC E Schnitt, ESC A 8 Byte) | Composite [D1] S. 14 |
| LabelWriter SE450 | 0x24 und 0x400 | 204 dpi, 56 B | 56 | LW-Classic + ESC y/z | auch RS-232 [D4] |
| LabelWriter Wireless | 0x27 | 672 @ 300 [I] | – | in diesem Paket kein Filter gefunden [I] | WLAN |
| LabelWriter 550 / 550 Turbo / 5XL | 0x28 / 0x29 / 0x2A | 672 @ 300 (5XL: breiter, PPD bis 307 pt) | – | **LW-V2** | NFC-Etiketten, Lock, LZ4, ESC T |
| LabelWriter 550 Twin Turbo, 550/5XL Connect | PID unbekannt (nicht in der Kext-Liste) | | | LW-V2 | Namen in V2-Strings [B] |

Für MacLabel heißt das: Zwei Treiber-Backends genügen, `LWClassic` (mit Varianten für BPL, ESC y/z, ESC q und Short-FF) und `LWV2`. Die Auswahl erfolgt über die PID.

## 7. Zugriff unter macOS (nur lesend geprüft)

- [B] Das Interface `IOUSBHostInterface@0` hat **keinen Kernel-Treiber als Kind**, der es belegt. Die Liste `UsbExclusiveOwner` enthält nichts Gerätebezogenes für DYMO.
- [B] `DymoUsbPrinterClassDriver.kext` ist ein **codeless Kext**: nur Info.plist, Personality `AppleUSBMergeNub`. Er hängt das Property `"USB Printing Class" = /Library/Printers/DYMO/Filters/UsbPrinterClassDriver.bundle` an das Interface (am Interface sichtbar). Damit lädt der CUPS-USB-Backend DYMOs Userspace-Plug-in (CFPlugIn, Typ `06047D16-…`). `kmutil showloaded`: kein DYMO-Kext geladen.
- [I] Folge: Ein Swift-Prozess kann das Interface per **IOUSBHost.framework** (`IOUSBHostDevice`/`IOUSBHostInterface`, Pipes für Bulk IN/OUT) oder per IOKit `IOUSBInterfaceInterface` öffnen, ohne Kext/DEXT. Die Öffnung ist exklusiv. Solange ein CUPS-Job läuft, hält das Backend das Interface, und MacLabel bekommt `kIOReturnExclusiveAccess`. Umgekehrt scheitert der CUPS-Job, solange MacLabel das Gerät offen hält. Im Leerlauf ist das Gerät frei (Queue-Zustand „inaktiv“).
- [I] Entitlements: ohne Sandbox keine nötig. In der App-Sandbox `com.apple.security.device.usb`, für den CUPS-Weg `com.apple.security.print`. Kein DriverKit nötig. Eine DEXT bräuchte das DriverKit-USB-Transport-Entitlement mit VID 0x0922 von Apple. Das lohnt sich nicht.
- [B] Der Backend `/Library/Printers/DYMO/Utilities/backend` nutzt `cupsSideChannelDoRequest`, d. h. CUPS-Side-Channel und Backchannel für den Status.

## 8. Ergebnisse

### (a) Fähigkeiten des LW450
Raster 672 Dots @ 300 dpi; 300 lpi (Text, schnell) oder 600 lpi (Grafik, präzise, langsamer). Vier Dichtestufen (75/87,5/100/112,5 % Strobe). SYN-Rohzeilen und ETB-RLE, frei mischbar. Dot Tab und Bytes/Zeile zur Datenreduktion. Skip-n-Lines (≤255). Etikettenlänge 1…32767 Zeilen oder Endlosmodus (≥0x8000). Form Feed oder Short Form Feed. 1-Byte-Status (Ready, TOF, kein Papier, Stau, Fehler). Versions-String (Modell + FW). Software-Reset (ESC @), Default-Restore (ESC *), Resync per ≥85 ESC. Parameter wirken sofort und lassen sich mitten im Job ändern [D1 S. 8]. Nicht vorhanden: Erkennung von Etikettengröße, -typ oder Restmenge, Schneidwerk, Fonts, Graustufen in Hardware.

### (b) Was MacLabel über DYMOs macOS-Pfad hinaus nutzen kann
1. **Status in Echtzeit außerhalb von Jobs** (ESC A): Papier leer, Stau, TOF, Bereitschaft, als Live-Anzeige und als Prüfung vor dem Druck. DYMO fragt nur während eines Jobs ab, und nur bei `usb://`. [D1]/[B]
2. **Modell- und Firmwareabfrage** (ESC V), von DYMO v1 nie verwendet. Damit lässt sich das Gerät sauber identifizieren, auch Klone und Turbo-Varianten. [D1]
3. **Sauberer Reset** mit ESC @ oder ESC * statt 156×ESC (beide Varianten einsetzen: erst Resync, dann ESC @). [D1]
4. **600 lpi gezielt pro Job oder sogar pro Label**: Grafik-Modus nur für Barcode-Labels, Text-Modus für Adressen. In der PPD hängt das an „Quality“; die Option „Resolution 300x600“ ist durch die OrderDependency de facto tot [B/I]. Mischjobs sind möglich, weil ESC h/i jederzeit wirkt [D1].
5. **Dichte pro Label** (z. B. Dark für Barcodes, Light für Durable-Folien), ohne neuen Job.
6. **Pixelgenaue 1-Bit-Ausgabe ohne Halftoning**: Text und Barcodes in Swift direkt auf 672-Dot-Raster rendern, Kantenpositionen auf 1/300" bzw. 1/600" exakt. Der CUPS-Pfad rastert per Default mit Error Diffusion, was Barcodes verschmieren kann [B PPD-Default].
7. **Freie Etikettenlängen und Endlosdruck** (ESC L FFFF + ESC E) ohne PPD-Größenliste. Banner sind auf Endlosrollen beliebig lang.
8. **Schnellere Übertragung**: optimales Mischen von SYN/ETB, Dot Tab und BPL schmal halten, ESC f für Weißbereiche. Bei 12 Mbit/s ist das kaum ein Engpass [D1 S. 18], spart aber Zeit beim 600-lpi-Modus.
9. **Etiketten sparen und schneller drucken**: Short Form Feed zwischen Labels, Form Feed nur am Ende (DYMO macht das bereits); zusätzlich „Vorschub sparen“: nach dem letzten Label kein ESC E, wenn direkt weitergedruckt wird.
10. **Twin Turbo: Rollenwahl pro Label** statt pro Dokument; Auto-Toggle bei leerer Rolle über ESC q 0.
11. **Eigene Reprint- und Wiederaufnahme-Logik** mit Benutzerdialog (Papier nachlegen → automatisch weiter), Job-Abbruch sauber per Resync.
12. **Kalibrierung/Feed-Funktionen in der UI**: Feed (ESC E), Short-Feed (ESC G), „n Zeilen vor“ (ESC f), Selbsttest-Hinweis.
13. Für **550**: LZ4-Kompression, High-Speed (ESC T 20), Medientyp Durable, Lock-Handling und Auswertung des 32-Byte-Status (Kopftemperatur, Spannung, Schachtstatus, NFC-Media).

### (c) Modellunterstützung
Siehe §6. Mit `LWClassic` werden PIDs 0x06–0x24 (außer Tape-Interfaces) und 0x400 abgedeckt; die Parameter sind maxBPL (58/56/84/156), `supportsShortFF` (400er+), `supports600lpi` (450er-Familie; ob 400/4XL ESC i kennen, ist ungeprüft [I]), `hasRollSelect` (0x18, 0x22) und `legacyResolution` (300er/SE450). Mit `LWV2` werden 0x28/0x29/0x2A (+ Twin/Connect) abgedeckt. Die DUO-Tape-Hälfte braucht den LabelManager-Befehlssatz (Anhang B, 128 Dots @ 180 dpi) als optionales drittes Backend.

### (d) Empfohlene Architektur für das Drucken aus Swift

| Variante | Vorteile | Nachteile |
|---|---|---|
| **A. Direkt USB (IOUSBHost)** | volle Kontrolle über alle Kommandos aus §2/§5; echter Status und ESC V; keine PPD- oder Treiberabhängigkeit (Apple will PPD-Treiber auslaufen lassen); funktioniert ohne installierte DYMO-Software | exklusiver Zugriff kollidiert mit laufenden CUPS-Jobs; Spooling, Warteschlange und Netzwerkfreigabe selbst bauen; Sandbox braucht `device.usb` |
| **B. CUPS-Raw auf die bestehende Queue** (`cupsCreateJob` + `CUPS_FORMAT_RAW` / `lp -o raw`) | Spooling und Mehrbenutzerbetrieb kommen von CUPS; MacLabel erzeugt den Bytestrom selbst (alle Druckfeatures wie in A); lw450.ppd hat keinen Raw-Filter, also gehen die Daten unverändert an den USB-Backend [I] | kein Status-Rückkanal für die App (Backchannel endet im Backend); Fehler kommen nur als grobe CUPS-Zustände; Raw-Queues gelten in CUPS als deprecated |
| **C. CUPS-Raster über den DYMO-Treiber** (PDF/Bild an die Queue) | minimaler Aufwand, Druckdialog-Integration | nur PPD-Optionen; Halftoning; kein Status; Abhängigkeit vom DYMO-Treiberpaket |

**Empfehlung [I]:** Hybrid mit A als Hauptpfad. MacLabel rendert selbst 1-bpp-Raster (CoreGraphics → 672-Dot-Bitmap, 300 bzw. 600 lpi), enthält einen Protokoll-Encoder pro Familie (`LWClassicEncoder`, `LWV2Encoder`) und einen Transport-Layer mit zwei Implementierungen:
1. `USBTransport` (IOUSBHost, Bulk OUT schreiben, Bulk IN mit Timeout für ESC A/ESC V). Exklusiv öffnen, nur für die Dauer eines Jobs oder einer Statusabfrage, danach sofort schließen, damit CUPS-Jobs anderer Apps weiterlaufen. Bei `kIOReturnExclusiveAccess` meldet die App „Drucker belegt“ und fällt auf B zurück.
2. `CUPSRawTransport` (identischer Bytestrom per CUPS-Raw-Job auf die vorhandene Queue) als Fallback, für Netzwerk- und Freigabeszenarien und für Nutzer, die keine USB-Berechtigung geben wollen.

Gerätesuche per IOKit-Matching (VID 0x0922 + PID-Tabelle, Interface-Klasse 7) und Zuordnung zu CUPS-Queues über das Modell. Die URI-Seriennummer ist unzuverlässig (§1). Kext oder DEXT sind nicht erforderlich. DYMOs codeless Kext stört nicht, sein Merge-Property betrifft nur den CUPS-Backend.

## 9. Offene Punkte und Risiken
- Bulk-Endpoint-Adressen und IEEE-1284-Device-ID sind nicht ausgelesen (würde das Öffnen des Geräts erfordern). In MacLabel zur Laufzeit ermitteln.
- Verhalten von ESC i bei LW400/4XL, Antwortzeit von ESC A, Antwort auf ESC V am eigenen Gerät: mit einem ersten Hardwaretest verifizieren (ein Testjob war hier ausdrücklich nicht erlaubt).
- Pixelpolarität und Zeilenorientierung bei LW-V2 (der Quellcode prüft 0xFF als „weiß“, die Daten sind bottom-aligned) vor der 550-Unterstützung am echten Gerät prüfen.
- Ob ESC @ direkt nach dem Öffnen bei laufendem Stromsparmodus sicher ist: laut [D1] wecken Daten das Gerät auf.

## 10. Hardware-Verifikation am echten LW450 (23.10.2026, ohne Papierbewegung)

Probe mit IOUSBHost.framework aus einem Swift-Kommandozeilenprogramm, ohne DYMO-Software im Pfad, ohne Entitlements, ohne Sandbox:

- Matching: `IOServiceMatching("IOUSBHostInterface")` + `IOPropertyMatch {idVendor: 0x0922, idProduct: 0x0020, bInterfaceClass: 7}`. (Top-Level-Keys ohne `IOPropertyMatch` matchen nicht.)
- `IOUSBHostInterface(__ioService:options:queue:interestHandler:)` öffnet das Interface ohne Fehler (CUPS-Queue im Leerlauf).
- Endpoints: **Bulk OUT 0x02**, **Bulk IN 0x82**, jeweils wMaxPacketSize 64. [B]
- `1B 41` (ESC A) → **1 Byte `0x03`** (Ready + Top of Form), wie im Manual beschrieben. [B]
- `1B 56` (ESC V) → **10 Byte ASCII `1750111f0J`**. Modellnummer 1750111, Firmware `f0J`. Das Trennzeichen ist hier `f` und nicht `v` wie im Manual-Beispiel. Parser: die ersten 7 Zeichen = Modell, der Rest = Firmware. [B]
