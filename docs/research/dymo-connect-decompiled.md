# DYMO Connect für macOS 1.6.3.9: Analyse des dekompilierten Codes für MacLabel

Stand: 23.10.2026, macOS 27.0 (Darwin 27.0.0), LabelWriter 450 per USB.

Ergänzt `lw450-protocol.md` (Bytes des CUPS-Filters) und `dymo-connect-features.md` (Feature-Inventar). Was dort steht, wird hier nicht wiederholt.

Kennzeichnung:
- **[B]** beobachtet: steht so im dekompilierten C#-Code (ILSpy), in der nativen Bibliothek `libdymoprintingsupport.dylib` (Hopper/REA, arm64, sha256 `ed3f0a71…eace76`), in eingebetteten XML-Daten oder im installierten PPD. Geprüft wurde auch lokal (siehe 1.4).
- **[I]** abgeleitet: Schlussfolgerung, nicht direkt verifiziert.

Rechtlicher Hinweis: Alles ist in eigenen Worten zusammengefasst. Klassen-, Methoden- und Enum-Namen dienen nur als Fundstellen. Es wurde kein DYMO-Quelltext übernommen. Schlüssel, Lizenzschlüssel, Zugangsdaten und Tracking-IDs, die im Code vorkommen, sind absichtlich weggelassen.

Pfadkürzel: `DC/` steht für das ILSpy-Projektverzeichnis `dymo-decompiled/` aus dem Scratchpad der Sitzung (nicht im Repo). Die Assembly `DYMO.CrossPlatform.Services` wurde zusätzlich dekompiliert (`dymo-decompiled-extra/`, Kürzel `DCX/`).

---

## 0. Kurzfassung

1. **Druckpfad (LW450, macOS):** Die App rendert jedes Etikett mit SkiaSharp als **RGBA-Bitmap mit 300 dpi**, ohne Antialiasing. Die Bitmaps gehen per P/Invoke an die native ObjC-Bibliothek `libdymoprintingsupport.dylib`. Diese druckt über die **Core-Printing-API (PMPrintSession, kein NSPrintOperation, ohne Dialog)** auf die normale CUPS-Queue: PDF-Spool, danach `raster2dymolw`. Papier, Ausrichtung (`PMSetOrientation`) und die PPD-Optionen `DymoPrintQuality`, `DymoPrintDensity`, `DymoPrintSpeed`, `DymoMediaType`, `InputSlot`, `DymoContinuousPaper`, `PageSize=Custom.WxH`, `DymoLockName` und `DymoChunkSize` werden gesetzt. **Die Drehung beim Druck übernimmt das macOS-Drucksystem über die Seitenausrichtung, nicht die App.**
2. **Ausrichtung:** Das Enum `ELabelOrientation` ist **absolut und an der Papiergeometrie festgemacht**: `Landscape` heißt, die x-Achse des Etiketts läuft in Vorschubrichtung. Dann wird mit kPMLandscape gedruckt. `Portrait` heißt, die x-Achse läuft quer über den Druckkopf (kPMPortrait). `DefaultOrientation` aus Papers.xml ist nur der Startwert. Bei **S0722540** wählt die App das Papier **30334** (Default `Portrait`), dargestellt als **breites 57×32-mm-Etikett**. Bei **11354**, physisch identisch, ist der Default `Landscape`, dargestellt als **hohes 32×57-mm-Etikett**. Vorschau und Druck nutzen dieselbe Geometrie und stimmen im Normalfall überein. Die wahrscheinlichste Ursache für „quer statt längs“ ist die **Mehrdeutigkeit von Portrait/Landscape**. Dazu kommen ein UI-Fehler, der bei Papieren mit Default `Portrait` die Ausrichtung umschaltet, und ein Papierwechsel, der den Enum-Wert relativ zum Default umrechnet. Details in Abschnitt 2.
3. **Text:** Der Auto-Fit (`AlwaysFit`) ist ein iterativer Schriftgrößen-Solver in Punkt-Einheiten. `ShrinkToFit` hat im Renderer keinen eigenen Zweig. Der Zeilenabstand ist Skias `FontSpacing`. Text wird mit Fill plus Hairline-Stroke und ohne Antialiasing gezeichnet. Halbtonrasterung macht erst der CUPS-Filter (PPD-Default: Error Diffusion).
4. **Barcodes:** Die Größenstufen sind Modulbreiten in Zoll pro Symbologie, für 1D auf ganze 300-dpi-Pixel gerundet. Bei 2D/QR wird **nicht** gerundet. QR wird **ohne Ruhezone** gezeichnet (die Bibliothek erzeugt den Rand, DYMO schneidet ihn ab), mit festem ECC-Level M.
5. **.dymo/.labelx:** XML mit Wurzel `DesktopLabel` (Version 1), darin `DYMOLabel` (Version 4). **Alle Koordinaten in Zoll** (verifiziert), Farben als Float 0…1, Datenfelder strukturell über `ColumnName`, die Datentabelle ist in der Datei eingebettet.
6. **Status LW450:** praktisch keiner. Die App liest beim 450 keinen Status, nur „online/offline“ aus dem CUPS-Queue-Zustand. Druckfehler aus der nativen Schicht werden nur geloggt und nie angezeigt.
7. **Datenzusammenführung:** eine Zeile ergibt ein Etikett. Es gibt keine Platzhalter-Syntax, Felder sind gebundene Spans. Kopien und Sortierung werden in C# (Bitmaps vervielfachen) oder nativ (Seitenschleife) umgesetzt.
8. **Vermeiden:** Telemetrie per Klartext-HTTP an Google Analytics mit Opt-out-Default, eingebettete Schlüssel (Lizenz, USPS-API), ein Druckjob pro Etikett bei nicht gruppierbaren Endlosetiketten, fehlendes Fehler-Feedback, fragile Namensabgleiche über Anzeigenamen.

---

## 1. Druckpfad für den LabelWriter 450 unter macOS

### 1.1 Objektkette [B]

| Schritt | Fundstelle | Was passiert |
|---|---|---|
| UI → Parameter | `DC/DYMO.DCDesktop/…ViewModels/PrintRegionViewModel.cs`, `PrintAsync`, `GetPrintQuality` | Baut `PrintParameters` (Kopien, Spiegeln, Collate, Qualität, Dichte, HighSpeed, Chain Marks). Erzeugt per `DataMappingHelper.GetMappedLabels` ein Etikett pro Datenzeile und filtert nach Bereich oder aktueller Zeile. |
| Service | `DCX/…ServiceImplementations/PrinterService.cs`, `PrintAsync` | Schätzt die Druckzeit, hängt Analytics-Daten an und ruft `Printer.Print` auf. |
| Drucker | `DC/DYMO.LabelAPI/DYMO.LabelAPI/Printer.cs`, `Print`, `SendAnalytics` | Sendet Analytics (wenn erlaubt), klont jedes Etikett, ersetzt Farben durch ein S/W-Äquivalent (`ColorUtility.GetBWEquivalentForPrinting`) und zählt Zählerobjekte hoch. Die Auflösung kommt aus dem Konstruktor `Printer(…, printerDPI)`. Default in `PrinterFactory.CreatePrinter`: **300 dpi**. |
| Modellzuordnung | `DC/DYMO.LabelAPI.PlatformSpecific/DYMO.LabelAPI.Mac/MacDeviceDiscovery.cs` | Bei Modellname „DYMO LabelWriter 450“, „450 Turbo“, „4XL“ oder „450 DUO Label“: `LabelWriterLegacyPrinterCommunication` mit `LabelWriterPrintDecorator`. Die Auswahl erfolgt per **Stringvergleich auf den CUPS-Modellnamen**. |
| Rendern + Übergabe | `…/DYMO.LabelAPI.Mac/LabelWriterPrintDecorator.cs`, `Print`, `GetLabelBitmap`, `GetMacPrintParameters` | Erzeugt pro Etikett eine Bitmap, füllt das Struct `MacPrintParameters` und ruft `PrintingSupportGateway.Print` auf. |
| P/Invoke | `…/DYMO.LabelAPI.Mac.Printers/PrintingSupportGateway.cs` | Die Bitmaps werden als `MacImage` (Bytes, Breite, Höhe) an `printingSupport_Print` der dylib übergeben. Der Rückgabewert ist **void**. |
| Nativ | `libdymoprintingsupport.dylib`: `_printingSupport_Print`, `-[PrinterManager print:printer:copies:…]`, `LabelPrintOperation` | Erzeugt `NSBitmapImageRep` (RGBA, 8 bit pro Kanal) und startet eine PMPrintSession ohne Dialog. Pro Seite wird `CGContextDrawImage` in den Seitenkontext aufgerufen. |

### 1.2 PDF oder Bitmap? [B]

- In C# entsteht eine Bitmap: `SkiaBitmapFactory.CreateWithOffsets` bei Die-Cut-Papier aus dem Treiber, sonst `CreateTrimmed`. Beides in `DC/DYMO.LabelAPI.Skia/…/SkiaBitmapFactory.cs`, immer mit `antiAlias: false` (`BaseLabelWriterPrintDecorator.GetLabelBitmap`).
- Nativ wird diese Bitmap per `CGContextDrawImage` in einen Core-Printing-Kontext gezeichnet (`-[LabelPrintOperation printLoop]`). macOS spoolt das als **PDF mit eingebettetem Rasterbild**. CUPS rastert es danach mit der PPD-Auflösung neu (`cgpdftoraster`, dann `raster2dymolw`). [I] Der Weg ist also Bitmap → PDF → Raster. Bei Qualität „Graphics“ (300×600 dpi) skaliert Quartz die 300-dpi-Bitmap in Vorschubrichtung um den Faktor 2. Die App setzt keine Interpolationsqualität. Kanten können dadurch leicht verschmieren und werden dann vom Filter per Error Diffusion gerastert.
- Die Bitmap hat **die Form des Etiketts in Editor-Orientierung**, nicht die des Papiers. Gedreht wird erst beim Zeichnen in die Seite (siehe 1.5).

### 1.3 Papier und Medienname [B]

- C# übergibt als `paperName` den **Papiernamen aus Papers.xml**, z. B. „30334 2-1/4 in x 1-1/4 in“ (`label.PaperInfo.Name`).
- Nativ ruft `-[PrintOperation getPaper]` `PMPrinterGetPaperList` auf und vergleicht jeden `PMPaperGetID` per exaktem Stringvergleich mit `paperName`. Bei einem Treffer gelten Papiergröße und Ränder des PPD.
- Ohne Treffer erzeugt `-[LabelPrintOperation getPageFormat]` ein **Custom-Papier** (`PMPaperCreateCustom`, ID „ContinuousPaperID“) aus `customPaperSize` und `customOffsets`. Zusätzlich wird `PageSize=Custom.<w>x<h>` (Punkte) gesetzt. Größe und Offset berechnet C# in `PrintHelper.GetCustomPaperSize`: Layout-Bounds, bei `Landscape` zurück in Papierachsen getauscht, umgerechnet mit 72 dpi (`macResolution`).
- `IsDriverPaperName` (C#) ruft `-[Printer isDriverPaperName:]` auf, also dieselbe Suche. Ist das Papier kein Treiberpapier, rendert C# nur den bedruckbaren Bereich (`CreateTrimmed`).
- Endlospapier: Endet der Papiername auf „Continuous“, setzt die dylib den Continuous-Modus und `DymoContinuousPaper=1`.

### 1.4 Lokale Gegenprobe der Papier-IDs [B]

Ein kleines Swift-Programm hat `PMPrinterGetPaperList`/`PMPaperGetID`/`PMPaperGetPPDPaperName` für die Queue `DYMO_LabelWriter_450` nur lesend abgefragt (Probe im Scratchpad, nicht im Repo):

- `PMPaperGetID` liefert den **Anzeigenamen aus dem PPD** („30334 2-1/4 in x 1-1/4 in“, „11354 Multi-Purpose“), nicht das PPD-Keyword („w162h90.1“).
- 30334 kommt im PPD **zweimal** vor (`w162h90.1` und `30334_2-1_4_in_x_1-1_4_in`), beide mit 162×90 pt. `getPaper` nimmt den ersten Treffer.
- **11354 und 30334 sind im PPD exakt gleich groß (162×90 pt, 2,25" quer zum Kopf, 1,25" in Vorschubrichtung).** Das passt zu Papers.xml: `Size Width` ist die Kopfrichtung, `Height` der Vorschub.

### 1.5 Ausrichtung beim Druck [B]

- `MacPrintParameters.paperOrientation` ist `label.Orientation`. Enum-Werte: `Landscape = 0`, `Portrait = 1` (`DC/DYMO.LabelAPI/DYMO.LabelAPI/ELabelOrientation.cs`).
- `-[PrintOperation setupPageFormat]`: Für den Wert 1 (Portrait) wird `PMSetOrientation(kPMPortrait)` gesetzt, sonst `kPMLandscape` (Assembly bei 0x38dc–0x38f4).
- `-[LabelPrintOperation printLoop]`: Bei Treiberpapier füllt die Bitmap die **ganze Papierfläche** (Ursprung 0,0). Bei Landscape vertauscht das Zielrechteck Breite und Höhe der Papiergröße, bei Portrait nicht. Bei Custom-Papier wird stattdessen der bedruckbare Bereich genutzt, mit vertauschtem Ursprung bei Landscape.
- Es gibt also **eine** Drehung im ganzen Pfad: Quartz bzw. das Drucksystem bei kPMLandscape. Die App dreht die Pixel nicht selbst. [I] Bei der Ausgabe des LW450 kommen noch zwei Faktoren hinzu: `*LandscapeOrientation` im PPD (Plus90 oder Minus90) und die Rotation, die CUPS aus dem Seitenformat ableitet.

### 1.6 Gesetzte PPD- und CUPS-Optionen [B]

`-[LabelPrintOperation setupPrintSettings]` setzt per `PMPrintSettingsSetValue`:

| Schlüssel | Werte | Quelle in C# |
|---|---|---|
| `DymoPrintQuality` | `Text` (EPrintQuality 104) / `Graphics` (105) | Auto-Wahl in `PrintRegionViewModel.GetPrintQuality`: Text, solange kein Bild, Barcode oder IMb-Adresse vorkommt. Bestimmte SKUs („Raptor“) und `Material == "Durable"` erzwingen Graphics. `PrepareForPrintingAsync` kann ebenfalls hochstufen. |
| `DymoPrintDensity` | `Light`/`Medium`/`Normal`/`Dark` (Enum 99/100/101/103) | UI-Default `Normal` |
| `DymoPrintSpeed` | `Normal`/`High` | `High` nur bei der UI-Qualität „HighSpeed“ (für den 450 bedeutungslos [I]) |
| `DymoMediaType` | `Default`/`Durable` | `Durable` nur, wenn der Drucker **keine** Rollenerkennung hat (450-Klasse) und das Material „Durable“ ist |
| `InputSlot` | `Auto`/`Left`/`Right`/`AutoRight` | Twin Turbo |
| `DymoContinuousPaper` | `1` | Endlosmodus |
| `PageSize` | `Custom.WxH` | nur bei Custom-Papier |
| `DymoLockName`, `DymoChunkSize` | Druckername bzw. Zahl | interne Werte für den DYMO-Backend-Helper |

Nicht gesetzt werden `DymoHalftoning` (der PPD-Default gilt: `ErrorDiffusion`) und `Resolution` (die Auflösung folgt aus `DymoPrintQuality`, das per PostScript-Snippet `HWResolution 300×300` bzw. `300×600` setzt). `UseChainMarks` aus `PrintParameters` steht nicht im Mac-Struct und **wird unter macOS für LabelWriter ignoriert**. Der String `DymoPrintChainMarksAtDocEnd` existiert in der dylib, [I] gehört aber zum Tape-Pfad.

### 1.7 Vorschau [B]

Editor und Vorschau rendern mit derselben `DYMOLabel`-Geometrie (`LayoutBounds(Orientation)`, `LabelSize`) über `SkiaDrawingContext`, mit Bildschirmauflösung und Antialiasing. In der Vorschau wird nichts gedreht, das Etikett erscheint so, wie es gestaltet wurde. Beim Druck kommt genau eine Drehung hinzu (kPMLandscape). Vorschau und Druck unterscheiden sich also **nur** durch das Mapping in 1.5.

---

## 2. Ausrichtung: Default, SKU und Papier

### 2.1 Datenmodell [B]

- Laden: `PaperInfoFactory.DieCutPaperInfoFromXElement` (`DC/DYMO.LabelAPI/DYMO.LabelAPI/PaperInfoFactory.cs`). `Size.Width` (Twips) wird zu `PaperInfo.Width` (Kopfrichtung), `Size.Height` zu `Length` (Vorschub). Die Ränder werden über Kreuz zugeordnet: oben/unten aus `PrintableOrigin.X` und der Breitendifferenz, links/rechts aus `PrintableOrigin.Y` und der Längendifferenz. `DefaultOrientation` ist „Portrait“ oder sonst `Landscape`.
- Geometrie: `DieCutPaperInfo.LayoutBounds(orientation)`. Bei **Landscape** ist das Layout **Länge × Breite** (x entlang des Vorschubs), bei **Portrait** **Breite × Länge** (x quer zum Kopf). Diese Rechnung ist absolut und unabhängig vom Default.
- Startwert: Der Konstruktor von `DYMOLabel` und `TemplateSelectionModel` setzen `Orientation = PaperInfo.DefaultOrientation`.
- SKU → Papier: Die SKU (`DieCutSKU@PaperName` in SKUs.xml) bestimmt das Papier, das Papier bestimmt Default und Geometrie. **S0722540 („S0722540 multipurpose“) verweist auf das Papier „30334 2-1/4 in x 1-1/4 in“.** 11354 ist ein eigener Papiereintrag mit identischer Geometrie.

### 2.2 Folge für die beiden Rollen [B]

| Auswahl | Papier | Default | Editor-Canvas | Druck |
|---|---|---|---|---|
| S0722540 (EMEA) / 30334 (NA) | 30334 | Portrait | **2,25" breit × 1,25" hoch** (Text entlang der 57-mm-Seite) | kPMPortrait, keine Drehung |
| 11354 | 11354 Multi-Purpose | Landscape | **1,25" breit × 2,25" hoch** (Text entlang der 32-mm-Seite) | kPMLandscape, 90° gedreht |

Über alle Papers.xml-Einträge gilt meist: Der Default ist so gewählt, dass die lange Seite im Editor waagrecht liegt. Dazu gehören 90 schmale Papiere mit Landscape und 15 breite mit Portrait. **Sechs breite Papiere weichen ab** und haben Landscape, also einen hohen Canvas: 11354, 11351, 30299 (die Offset-Variante von 30299 hat dagegen Portrait), High Capacity Address, High Capacity Large Shipping und 1933089. Zwei schmale Papiere haben Portrait. Das sind Dateninkonsistenzen bei gleicher Physik.

### 2.3 Kann Vorschau ≠ Druck sein?

- Im Standardpfad mit Treiberpapier sind Bitmap-Form, `PMSetOrientation` und Zielrechteck konsistent. [B] **Vorschau und Druck stimmen in der Drehung überein.**
- Kleine **Randverschiebungen** sind möglich [B]. `LabelOffsetsHelper.GetFlippedLabelOffsets` verschiebt den Inhalt beim Druck auf den gegenüberliegenden Rand (rechts statt links bzw. unten statt oben). `SkiaBitmapFactory.CreateWithOffsets` und `GetBitmapForRender` entscheiden über die **relative** Ausrichtung (`ExtensionMethods.RollOrientation`, das ist „Orientation ≠ Default“), die Offset-Helfer dagegen über die **absolute**. Bei Papieren mit Default Portrait laufen beide Logiken auseinander. Das kann den Inhalt um die Randdifferenz verschieben, aber nicht um 90° drehen. [I]
- Der Hintergrund bzw. die Etikettenkontur in `SkiaDrawingContext` (um Zeile 241) mischt ebenfalls relative und absolute Prüfung. Betroffen ist nur die Darstellung.

### 2.4 Wahrscheinlichste Ursache für „quer statt längs“

Hauptursache, Semantikfalle [B für Daten und Code, I für die Übertragung auf MacLabel]: `Portrait` und `Landscape` beschreiben bei DYMO **nicht die Form des Canvas**, sondern **die Lage der Etiketten-x-Achse zum Papiervorschub**. Für das 57×32-Papier 30334 ergibt `Portrait` einen **breiten** Canvas. Eine Implementierung, die `Portrait` als „höher als breit“ deutet oder `DefaultOrientation` mit einer selbst berechneten Canvas-Form kombiniert, liegt genau bei den 15+6 breiten Papieren um 90° daneben. Dass derselbe physische Etikettentyp je nach SKU-Weg (S0722540 → 30334 → Portrait, 11354 → Landscape) gegensätzliche Defaults bekommt, macht den Fehler rollenabhängig. Mit S0722540 erscheint die Ausrichtung anders als mit 11354, obwohl dieselbe Rolle eingelegt ist.

In DYMO Connect selbst verstärken drei Code-Fehler das:

1. **`PaperRegionViewModel.ChooseOrientation` [B]:** Hat das Papier Default `Portrait` (und ist kein „GA“-Etikett), **ignoriert** die Methode die gewählte Ausrichtung und **schaltet die aktuelle um**. `OnSetLabel` zeigt zusätzlich einen Hinweis zur Ausrichtungsänderung, wenn die Auswahl dem aktuellen Wert *entspricht* (Bedingung invertiert). Wer bei S0722540/30334 im Papierdialog nur bestätigt oder das Material wechselt, bekommt also ein **um 90° gedrehtes Layout**, nach einer Warnung, die man leicht wegklickt.
2. **Radio-Buttons zeigen den absoluten Enum-Wert [B]** (`DetailsPaperView.orientationRadioButton_Activated` → `MultipleLabelInfoWrapper.IsLandscape`/`IsPortrait`; `PaperRegionViewModel.CloneWithOrientationSet` übernimmt `CurrentLabel.Orientation`). Beim breiten Default-Layout von 30334 ist deshalb „vertikal“ angehakt. Klickt der Nutzer „horizontal“, weil das Etikett horizontal aussehen soll, dreht er es auf hoch.
3. **Papierwechsel rechnet relativ um [B]** (`LabelFactory.UpdateOrientation`): Haben altes und neues Papier verschiedene Defaults, wird der Enum-Wert invertiert. Der Wechsel 11354 → S0722540 macht aus einem hohen Layout ein breites und umgekehrt. Zusammen mit `RotationBehavior` des Layout-Managers (z. B. `ClearObjects` in Vorlagen) kann das Inhalte verschieben oder löschen [I].

Folgerung für MacLabel [I]:
- Intern nur eine absolute Größe speichern: „Inhalt um 0° oder 90° zum Papier gedreht“, wobei sich das Papier immer auf Kopfbreite × Vorschub bezieht.
- `DefaultOrientation` höchstens als Startwert nutzen und für Roll-Aliase (S0722540 ≙ 11354 ≙ 30334) **einen** kanonischen Default festlegen.
- Im UI nur die Canvas-Form zeigen (breit oder hoch), nie die Begriffe Portrait/Landscape.
- Die Drehung beim Rendern des Rasters selbst ausführen, statt sie dem Drucksystem zu überlassen. Das gilt besonders, wenn MacLabel direkt per USB druckt.

---

## 3. Textdarstellung

### 3.1 Einheiten [B]
- Layout: **Zoll** (`ObjectLayout`, `DYMORect`).
- Schriftgröße: **Punkt** (`FontInfo.FontSize`).
- Rendern: Pixel bei Druckerauflösung (`ToPixelFromInches`, `ToPixelFromPoint` mit `Resolution.DPI`).
- Papierdaten: Twips (1/1440").

### 3.2 Fit-Modi [B] (`ETextFitMode`: `None`, `ShrinkToFit`, `AlwaysFit`; Default für `TextObject` und Pre/Post-Objekte: `AlwaysFit`)
- `DYMOFormattedText.GetAutoFitFontSize(bounds)`:
  1. Die Bounds (Zoll) werden in Punkt umgerechnet.
  2. Der Startwert ist Boxhöhe ÷ Zeilenzahl × 1,1. Bei unbegrenzter Höhe wird die Breite genommen.
  3. `DoesTextFit` misst das Verhältnis aus Textbreite zu Boxbreite und Texthöhe zu Boxhöhe (das größere zählt). Daraus folgt der Schätzwert Startwert × 1,1 ÷ Verhältnis.
  4. Danach wird die Größe in **0,3-pt-Schritten** reduziert, bis der Text passt. Minimum ist 1 pt.
- Passt-Kriterium (`DoesTextFit`): Die Breite muss *strikt* größer sein als die breiteste Zeile plus eine mittlere Zeichenbreite (Zeilenbreite ÷ Zeichenzahl, abgeschnitten). Die Höhe muss strikt größer sein als die Summe der Zeilenhöhen. Die mittlere Zeichenbreite dient als eingebaute Sicherheitsmarge.
- `SetAutoFitSize` schreibt die berechnete Größe nur bei `AlwaysFit` in **alle** Spans, gemischte Größen gehen dabei verloren. Der Renderer (`SkiaDrawingContext.DrawTextInternal`) kennt nur `AlwaysFit` oder die Span-Größe. **`ShrinkToFit` hat keinen eigenen Zweig und wird wie `None` gerendert** [B]. Der Editor zeigt Überlauf nur über `TextObject` „DoesTextFit“ an [I].
- Das Ergebnis wird gecacht (`_lastCalculated`, `_lastBounds`). Neu gerechnet wird nur bei geänderten Bounds oder geändertem Text.

### 3.3 Zeilenlayout [B]
- Zeilenhöhe = `SKPaint.FontSpacing` (Ascent + Descent + Leading) des größten Spans der Zeile, bei `AlwaysFit` die des ersten Spans.
- Baseline je Zeile = kumulierte Höhe − Leading − Descent.
- Horizontal: Der Block wird nach der breitesten Zeile ausgerichtet, jede Zeile zusätzlich innerhalb dieser Breite (Links/Mitte/Rechts). Vertikal Oben/Mitte/Unten über die Blockhöhe. Bei arabischer UI-Kultur wird die Reihenfolge der Spans umgedreht.
- Gemessen wird mit `SKPaint.MeasureText` über die Glyphen-Bounds (Ink-Breite). Ein Hilfsstring berücksichtigt Leerzeichen bzw. leeren Text (`ExtensionMethods.MeasureTextExt`).
- Vertikaler Text: `MakeVertical`, ein Zeichen pro Zeile.

### 3.4 Rasterung [B]
- SkiaSharp-`SKBitmap`, der Hintergrund wird mit der Etikettenfarbe gefüllt. Text-Paint: `SKPaintStyle.StrokeAndFill` mit Strichbreite 0. [I] Skia zieht dabei zusätzlich eine 1-px-Haarlinie um die Glyphen, Text wird minimal fetter. Das ist auf Thermo eher hilfreich.
- **Druck ohne Antialiasing** (`antiAlias: false`), Bildschirm mit.
- Keine eigene Dither- oder Schwellwertlogik in der App. Bilder und Graustufen gehen als RGBA an CUPS, `raster2dymolw` rastert per PPD-Default **Error Diffusion**. Farben werden vorher auf S/W-Äquivalente gemappt (`ColorUtility.GetBWEquivalentForPrinting`).

Für MacLabel [I]: Text und Barcodes direkt binär rendern (kein AA, pixelgenau). Nur Fotos dithern, wahlweise mit Floyd-Steinberg oder Schwellwert. Das ersetzt den Umweg über PDF und CUPS.

---

## 4. Barcodes und QR

### 4.1 Größenstufen (1D) [B] (`Base1DBarcode.GetBaseUnit`)
- Die Modulbreite kommt aus `MinUnitWidthInches` und `MaxUnitWidthInches` je Symbologie: Small = Min, Medium = Mittelwert, Large = Max, SmallMedium = Mittelwert aus Min und Medium.
- Ab 300 dpi wird mit einem symbologie-spezifischen Faktor korrigiert (`GetSizeAdjustingCoefficient`), dann **auf ganze Pixel gerundet**.

| Symbologie | Min/Max (Zoll) | Faktor S/M/L | ≈ Pixel bei 300 dpi S/M/L [I gerechnet] |
|---|---|---|---|
| Code 128 | 0,015 / 0,025 | 0,75 / 0,9 / 0,8 | 3 / 5 / 6 |
| Code 39 | 0,011 / 0,022 | 0,9 / 0,95 / 0,9 | 3 / 5 / 6 |
| UPC-A | 0,017 / 0,024 | 0,6 / 0,75 / 0,9 | 3 / 5 / 6 |
| ITF | 0,025 / 0,05 | 0,75 / 0,8 / 0,75 | 6 / 9 / 11 |
| 2 of 5 | 0,0125 / 0,025 | 0,7 / 0,78 / 0,75 | 3 / 4 / 6 |
| Codabar | 0,01 / 0,02 | – | 3 / 5 / 6 |
| PDF417 | 0,02 / 0,036 | – (2D-Pfad) | 6 / 8,4 / 10,8 |
| QR, DataMatrix | 0,012 / 0,0215 | – (2D-Pfad) | 3,6 / 5,0 / 6,45 |
| POSTNET, IMb | 0,046 fest | – | 14 |

- **AutoFit (1D):** Modul = Objektbreite ÷ Anzahl Module, **ohne Rundung**. Das ergibt Bruchteil-Pixel und damit ungleiche Strichbreiten [B]; schlecht für Scanner [I].
- Platzierung: horizontal nach Ausrichtung (Mitte mit `floor`), Striche über die volle Objekthöhe.
- **Keine Ruhezone** wird hinzugefügt. Die Ruhezone hängt allein vom Objektrand bzw. -abstand ab (Default 0).

### 4.2 2D und QR [B] (`Base2DBarcode`, `QRCode`)
- Modulgröße wie oben, aber **ohne Rundung auf ganze Pixel**. AutoFit = min(Breite ÷ Spalten, Höhe ÷ Zeilen). Zentriert vertikal, horizontal nach Ausrichtung.
- QR wird mit **QRCoder** erzeugt, **ECC-Level fest M**. Der von QRCoder angelegte **4-Modul-Rand wird abgeschnitten**, die Ruhezone fehlt also im Symbol.
- QR-Inhaltstypen (Text, URL, E-Mail, SMS, Telefon, vCard) werden in `QRCodeObject.GenerateDataHolder` zu Strings zusammengesetzt.

### 4.3 Klartextzeile (HRT) [B] (`BaseBarcode.Draw`, `DrawText`)
- Positionen: `EHRTPosition` `None`/`Top`/`Bottom`.
- Zuerst werden die Striche über die **volle Höhe** gezeichnet. Danach legt der Code oben oder unten ein Band mit der Höhe der Schriftgröße (pt → px) und der Breite des Barcodes in Hintergrundfarbe darüber und schreibt den Text zentriert per `AlwaysFit` hinein. Das Band verdeckt also einen Teil der Striche.
- EAN-8, EAN-13, UPC-A, UPC-E, ITF, Code 3 of 9, Codabar und IMb haben eigene Textaufteilungen (`GetTextParts`-Overrides), z. B. die Ziffergruppen bei EAN/UPC.

Für MacLabel [I]: Module immer auf ganze Druckerpixel runden, auch bei AutoFit und 2D. Eine Ruhezone von mindestens 10 Modulen (1D) bzw. 4 Modulen (QR) erzwingen oder warnen. HRT unter die Striche setzen, statt sie zu überdecken. ECC wählbar machen.

---

## 5. Dateiformat `.dymo` (und `.labelx`-Vorlagen)

### 5.1 Struktur [B]
- Die Wurzel ist `DesktopLabel` mit Attribut `Version="1"` (`DC/DYMO.DCDesktop/DYMO.DCDesktop/DCDesktopLabel.cs`, `Serialize`). Kinder in fester Reihenfolge: `DYMOLabel`, `LabelApplication` (String, z. B. „Blank“, „Address“), `DataTable` (`Columns/DataColumn*`, `Rows/DataRow/Value*`). Schema: eingebettetes `DesktopLabel.xsd`, das `SmartMobile.xsd` einbindet.
- `DYMOLabel` mit Attribut `Version` (Schreiber: **4**; Vorlagen enthalten noch 3). Die Kinder werden **in fester Reihenfolge per Stream-Reader** gelesen (`DYMOLabel.Deserialize`), ohne Suche nach Elementnamen: `Description`, `Orientation` (`Landscape`/`Portrait`), `LabelName`, `InitialLength`, `BorderStyle`, `DYMORect` (die Layout-Bounds), `BorderColor`, `BorderThickness`, `Show_Border`, optional `HasFixedLength` und `FixedLengthValue`, danach das Layout-Manager-Element (`DynamicLayoutManager`, `GrowingDynamicLayoutManager` oder `ContinuousLayoutManager`) mit `RotationBehavior` und `LabelObjects`.
- `LabelName` ist der **SKU-Name** aus SKUs.xml (`DieCutSKU@Name`, z. B. „Address30251“, „Small30334“, „S0722540 multipurpose“), **nicht** der Papiername. Ist der Name unbekannt, bricht das Laden mit einer Serialisierungs-Exception ab (häufig bei Custom-Labels).
- Upgrades (`DC/DYMO.LabelAPI.PlatformSpecific/…/Upgrades/`): v1→v2 ist leer. v2→v3 baut `Data` von Barcode und QR in `DataString`-Elemente um, stellt den URL-Holder um und migriert BorderStyle und Adressobjekte. v3→v4 ergänzt bei `DateTimeObject` die Felder `IsStatic` und `StaticDateTime`. `DLSToCurrent` und `DLSLabelConverter` importieren das alte DLS-Format (`.label`).

### 5.2 Einheiten (verifiziert) [B]
- **Koordinaten und Größen in Zoll.** Beispiel „Simple-Barcode.labelx“ auf Papier 30251 (3,5" × 1,125"): Layout-Bounds `X=0.23, Y=0.06, W=3.21, H=0.997`, das Barcode-Objekt `W=3.05, H=0.5`. Die Werte passen nur zu Zoll. Code-Belege: `ToPixelFromInches` beim Rendern, `TwipsToInches` beim Laden des Papiers.
- `ObjectLayout` und `DYMORect` sind relativ zum Etikett im **Editor-Koordinatensystem** (also nach Ausrichtung) und schließen den Rand ein: Der Ursprung der Layout-Bounds ist der Rand.
- Schriftgrößen in pt. Farben als `Color A R G B` mit **Floats 0…1**. Ränder als `DYMOThickness Left/Top/Right/Bottom` in Zoll. Drehungen als `Rotation0/90/180/270`.

### 5.3 Objekttypen und Kerneigenschaften [B] (Elementnamen aus dem XSD bzw. der Serialisierung)
- Alle Objekte (`BaseLabelObject`): `Name`, `Brushes` (`BackgroundBrush`, `BorderBrush`, `StrokeBrush`, `FillBrush`; Solid oder LinearGradient), `Rotation`, `OutlineThickness`, `IsOutlined`, `BorderStyle`, `Margin`, `ObjectLayout` (`DYMOPoint` + `Size`).
- `TextObject`: `FormattedText` (`FitMode`, `HorizontalAlignment`, `VerticalAlignment`, `IsVertical`, `LineTextSpan*` mit `TextSpan`/`FixedTextSpan`/`DataMappingTextSpan`, jeweils `Text` und `FontInfo`).
- `AddressObject`: wie Text, plus IMb-Position und Barcode-Optionen.
- `CircularTextObject`: `TextCurveType` mit TopArc, BottomArc oder FullCircle.
- `BarcodeObject`: `BarcodeFormat`, `Data` (bzw. `DataString`/`MappableDataString`/`MultiDataString`), `HorizontalAlignment`, `VerticalAlignment`, `Size` (Small, SmallMedium, Medium, Large, AutoFit), `TextPosition`, `FontInfo`.
- `QRCodeObject`: `EQRCodeType` plus Data-Holder (Text, WebAddress, Email, SMS, Phone, VCard).
- `ImageObject` (Bild als Base64 [I], `ScaleMode`), `ShapeObject` (`ShapeType`, `StrokeWidth`, `DashPattern`), `LineObject` (`LineType`, Start/Ende), `CounterObject` (`Prefix`/`Postfix`, `StartAt`, `Increment`, `PrintLeadingZeros`, `TextWidth`), `DateTimeObject` (`DateFormat`, `TimeFormat`, `IsStatic`, `StaticDateTime`).

### 5.4 Datenfelder in der Datei [B]
- Seriendaten stehen als Spalten und Zeilen direkt im `DataTable` der `.dymo`-Datei. Auch beim erneuten Öffnen ist kein Zugriff auf die Quelldatei nötig.
- Bindung: In Texten ist ein `DataMappingTextSpan` mit `ColumnName` ein eigener Span (Formatierung pro Span möglich). Bei Barcode und QR bindet ein `MappableDataString` mit `ColumnName`. Ein `MultiDataString` verkettet mehrere feste oder gebundene Teile. Adressbuchspalten tragen das Präfix `AddressBook_`.

Importer-Hinweis [I]: Das Format hat eine feste Elementreihenfolge, ist aber einfach. MacLabel sollte tolerant und ohne Reihenfolgeannahmen parsen, `LabelName` über eine SKU-Alias-Tabelle auflösen und Version 3 und 4 akzeptieren.

---

## 6. Status und Fehlerbehandlung beim LW450

- **Kein Gerätestatus [B]:** `LabelWriterLegacyPrinterCommunication.UpdatePrinterStatus` nutzt `PrinterCommunicationDecorator.GetLegacyStatus`, und das liefert auf dem Mac **immer einen leeren String**. Die 450-Klasse implementiert weder `IPrinterError` noch `IRollStatus`: keine Papierende- oder Fehlermeldung, kein Rollenstatus.
- **Verbunden/getrennt [B]:** Ein Timer (`StartStatusTimer`) ruft `printingSupport_IsConnected` auf (`-[Printer updateState]`, `isOffline`). Nach den Strings der dylib (`printer-state`, `printer-state-reasons`, `offline`) stammt der Wert aus dem **Zustand der CUPS-Queue** [I], nicht aus ESC A.
- **Druckfehler [B]:** Die native Schicht prüft die PMSession-Fehlercodes nur intern und loggt per `NSLog`. `printingSupport_Print` liefert void, C# bekommt keinen Fehler. Die UI zeigt ein „Wird an Drucker gesendet“-Fenster, wartet **fest ca. 3 s** (plus Zuschlag bei großen Bereichen) und schließt es. Gemeldet wird nur `DYMOPrintJobTooBigException`. „Nicht verbunden“ erscheint nur, wenn die Kommunikation nicht `IPrint` ist.
- **Druckbutton:** aktiv, wenn der Bereich gültig ist, kein Fehlertext vorliegt und `IPrint` unterstützt wird. Beim 450 also immer, auch offline (dann landet der Job in der CUPS-Queue) [I].
- Die Warnung „Wenige Etiketten“ gibt es nur bei Druckern mit Rollenerkennung (550er) [B].

Für MacLabel [I]: Beim 450 per USB vor und während des Jobs ESC A lesen (siehe `lw450-protocol.md`, Abschnitt 3). Papierende, Stau und Fehler konkret anzeigen. Bei CUPS-Druck den Job-Status per `cupsGetJobs`/IPP verfolgen, statt nach einer festen Zeit zu raten.

---

## 7. Datenzusammenführung (CSV/Excel)

- **Import [B]** (`DC/DYMO.LabelAPI.PlatformSpecific/DYMO.LabelAPI.Mac.Data/DataImporter.cs`): xlsx, xlsb, xlsm, xls und **csv** über die kommerzielle Bibliothek **IronXL** (`WorkBook.Load`, Arbeitsblatt wählbar, optional erste Zeile als Kopf). **`.txt` wird nicht getrennt**: jede Zeile wird ein Wert in einer einzigen Spalte. Die Konstante `MAX_ROWS = 1000` ist deklariert, wird aber nicht benutzt. Für die Thai-Kultur wird die Kultur kurz auf „en“ umgestellt (Zahlen- und Datumsparsing).
- **Platzhalter [B]:** Es gibt keine Textsyntax wie `{{Feld}}`. Felder werden im Editor als gebundene Spans eingefügt (`DataMappingTextSpan`/`MappableDataString` mit Spaltenname). Fehlende Spalten oder Zeilen ergeben leeren Text, ohne Fehler.
- **Zeilen → Etiketten [B]** (`DataMappingHelper.GetMappedLabels`): Jede Datenzeile wird ein geklontes Etikett. Ohne Daten gibt es genau ein Etikett. Bereichsauswahl über `PrintRangeText` (Kommaliste, Bereiche mit „-“, 1-basiert) oder „aktuelle Zeile“.
- **Kopien und Sortierung [B]:**
  - Gruppierbare Etiketten (alle Die-Cut, oder Endlos mit gleicher Größe, Offset und Ausrichtung) mit Collate=aus: Jede Bitmap wird n-mal wiederholt, Kopien=1, ein Job. Mit Collate=an: Kopienzahl an die dylib, deren `printLoop` Kopien außen und Etiketten innen durchläuft, also sortiert, ein Job.
  - Nicht gruppierbar: **ein Druckjob pro Etikett** (bzw. pro Etikett und Kopie). Langsam, und Vorschübe und Abrisse summieren sich [I].
  - Mit Zählerobjekten (`IUpdateAfterPrint`) werden Kopien vorab in einzelne Etiketten aufgelöst (`PrintRegionViewModel.HandleUpdateAfterPrint`), damit jeder Ausdruck eine eigene Nummer bekommt. `Printer.Print` setzt den Zähler als Startwert + Index × Schrittweite und schreibt den Endstand ins Editor-Etikett zurück.

---

## 8. Übernehmen oder vermeiden

### Übernehmen [I, gestützt auf B]
- Ein **absolutes Papierkoordinatensystem** (Breite = Kopfrichtung, Länge = Vorschub) direkt aus Papers.xml-Twips. Die Daten sind gut und mit dem PPD konsistent (1.4).
- Pro Papier **Druckversatz und Durable-Korrekturen** als Tabelle (`LabelOffsetsHelper`: kleine Pixelversätze für einige Durable-SKUs und Sonderfälle wie DHL). Die Werte sollte MacLabel selbst messen.
- Automatische **Qualitätswahl**: Text bei reinem Text, sonst Barcode/Grafik, Durable erzwingt Grafik und Medientyp Durable.
- **Zähler über Kopien** konsistent hochzählen und den Endstand zurückschreiben.
- **Seriendaten in der Datei** einbetten (reproduzierbar ohne Quelldatei).
- Auto-Fit mit kleiner Sicherheitsmarge (mittlere Zeichenbreite) und Cache.
- Ganzzahlige Modulbreiten bei 1D-Presets.

### Vermeiden [B, wo angegeben]
- **Portrait/Landscape als Begriffe** und widersprüchliche `DefaultOrientation` je SKU-Alias (Abschnitt 2). Ebenso **`ChooseOrientation`-Toggle** und **invertierte Warnbedingung** [B].
- **Stummes Scheitern** beim Druck (void-Rückgabe, feste Wartezeit) [B]. **Kein Status beim 450**, obwohl das Gerät per ESC A antworten kann [B].
- **Namensabgleich über Anzeigenamen** (Papiername gegen `PMPaperGetID`, Modellname per Stringvergleich) [B]. Lokalisierte oder geänderte PPDs würden auf Custom-Papier zurückfallen [I].
- **Bruchteil-Pixel-Module** bei AutoFit und 2D, **QR ohne Ruhezone**, **HRT-Band über den Strichen** [B].
- **Ein Job pro Etikett** bei nicht gruppierbaren Etiketten [B].
- **`.txt`-Import ohne Trennzeichen**, kommerzielle Excel-Abhängigkeit mit im Code eingebettetem Lizenzschlüssel [B, Schlüssel nicht wiedergegeben].
- **Telemetrie beim Drucken** [B]: `Printer.SendAnalytics` → `AnalyticsHelper` → `GoogleAnalyticsApi` sendet bei *jedem* Druck per **unverschlüsseltem HTTP** an den Universal-Analytics-Endpunkt: Objektzählung, Papiername, Druckermodell, Anzahl, Batch-Flag und eine eindeutige Nutzer-ID. Die Einwilligung (`DataCollectionAgreement`) steht **standardmäßig auf „True“** (`PreferenceService`). Die Tracking-ID ist im Code eingebettet (nicht wiedergegeben).
- **Weitere Netzwerkzugriffe** [B]:
  - USPS-Adresskorrektur (`AddressFixer`) mit eingebetteten API-Zugangsdaten (nicht wiedergegeben), ausgelöst beim Formatieren von Adressobjekten
  - Firmware-Prüfung beim Aktivieren eines Druckers (`FirmwareService.CheckPrinterUpdates`)
  - App-Update-Prüfung (`UpdateHelper`), SKU-Online-Links und Benutzerhandbuch-Downloads
  - Google- und Outlook-Kontakte (OAuth)

  MacLabel sollte beim Drucken **keinerlei** Netzwerkzugriff haben.
- **Privilegierter Helper** [B]: Die dylib kann per `SMJobBless` ein Tool unter `/Library/PrivilegedHelperTools/` installieren und eine DriverKit-Systemerweiterung (`com.dymo.dymo-connect.usb`) aktivieren. Raw-Kommandos laufen dann über einen CFMessagePort-Helper. Für den 450 ist das unnötig, weil der Zugriff über CUPS bzw. IOKit im Nutzerkontext funktioniert (siehe `lw450-protocol.md`, Abschnitt 7) [I].

---

## 9. Fundstellen (Auswahl)

| Thema | Datei (relativ zu `DC/`) bzw. Symbol |
|---|---|
| Mac-Druck-Decorator | `DYMO.LabelAPI.PlatformSpecific/DYMO.LabelAPI.Mac/LabelWriterPrintDecorator.cs` |
| P/Invoke-Gateway | `DYMO.LabelAPI.PlatformSpecific/DYMO.LabelAPI.Mac.Printers/PrintingSupportGateway.cs`, `MacPrintParameters.cs` |
| Modellzuordnung | `DYMO.LabelAPI.PlatformSpecific/DYMO.LabelAPI.Mac/MacDeviceDiscovery.cs` |
| Native Druckoperation | dylib: `-[PrintOperation getPaper]`, `-[PrintOperation setupPageFormat]`, `-[LabelPrintOperation getPageFormat]`, `-[LabelPrintOperation setupPrintSettings]`, `-[LabelPrintOperation printLoop]` |
| Orientierungsmodell | `DYMO.LabelAPI/DYMO.LabelAPI/DieCutPaperInfo.cs` (`LayoutBounds`), `DYMOLabel.cs` (`LabelSize`, `Orientation`), `ExtensionMethods.cs` (`RollOrientation`), `LabelSize.cs`, `LabelRect.cs` |
| Papier-Laden | `DYMO.LabelAPI/DYMO.LabelAPI/PaperInfoFactory.cs` (`DieCutPaperInfoFromXElement`) |
| Ausrichtungs-UI | `DYMO.DCDesktop/…ViewModels/PaperRegionViewModel.cs` (`OnSetLabel`, `ChooseOrientation`, `CloneWithOrientationSet`), `DYMO_Connect/…MenuItems/DetailsPaperView.cs`, `DCX/…Wrappers/MultipleLabelInfoWrapper.cs` |
| Papierwechsel | `DYMO.LabelAPI/DYMO.LabelAPI/LabelFactory.cs` (`UpdateOrientation`) |
| Bitmaps | `DYMO.LabelAPI.Skia/DYMO.LabelAPI.Skia/SkiaBitmapFactory.cs`, `SkiaDrawingContext.cs`, `ExtensionMethods.cs` (`GetFontPaint`) |
| Offsets | `DYMO.LabelAPI/DYMO.LabelAPI.Papers/LabelOffsetsHelper.cs`, `DYMO.LabelAPI/DYMO.LabelAPI.Helpers/PrintHelper.cs` |
| Auto-Fit | `DYMO.LabelAPI/DYMO.LabelAPI/DYMOFormattedText.cs` (`GetAutoFitFontSize`, `DoesTextFit`, `SetAutoFitSize`) |
| Barcodes | `DYMO.LabelAPI/DYMO.LabelAPI.Barcode/Base1DBarcode.cs`, `Base2DBarcode.cs`, `BaseBarcode.cs`, `QRCode.cs` |
| Dateiformat | `DYMO.DCDesktop/DYMO.DCDesktop/DCDesktopLabel.cs`, `DYMO.LabelAPI/DYMO.LabelAPI/DYMOLabel.cs` (`Serialize`/`Deserialize`), Upgrades unter `DYMO.LabelAPI.PlatformSpecific/DYMO.LabelAPI.Shared.LabelStuff.Upgrades/`, Vorlagen unter `DYMO.LabelTemplates/` |
| Daten | `DYMO.LabelAPI/DYMO.LabelAPI/DataMappingHelper.cs`, `DataMappingTextSpan.cs`, `MappableDataString.cs`, `MultiDataString.cs`, `DYMO.LabelAPI.PlatformSpecific/DYMO.LabelAPI.Mac.Data/DataImporter.cs` |
| Druckablauf/UI | `DYMO.DCDesktop/…ViewModels/PrintRegionViewModel.cs`, `DCX/…ServiceImplementations/PrinterService.cs`, `DYMO.LabelAPI/DYMO.LabelAPI/Printer.cs` |
| Status 450 | `DYMO.LabelAPI/DYMO.LabelAPI.Printers/LabelWriterLegacyPrinterCommunication.cs`, `DYMO.LabelAPI.PlatformSpecific/DYMO.LabelAPI.Mac/PrinterCommunicationDecorator.cs` |
| Telemetrie | `DYMO.CrossPlatform.Common/DYMO.CrossPlatform.Common.Helpers/AnalyticsHelper.cs`, `GoogleAnalyticsApi.cs`, `DCX/…/PreferenceService.cs` |
