# DYMO Connect 1.6.3.9 (macOS) – Feature-Inventar als Grundlage für „MacLabel“

Stand: 2026-10-23. Rein statische Analyse (keine Ausführung). Ziel-Bundle: `/Applications/DYMO Connect.app` (Bundle-ID `com.dymo.dymo-connect`, .NET 8 / Microsoft.macOS, LSMinimumSystemVersion 10.15).

**Legende:** **[O]** = beobachtet im Artefakt, **[I]** = abgeleitet/inferiert, **[?]** = unbekannt/nicht verifiziert.

## 0. Evidenz und Methodik

| Evidenz | Inhalt |
|---|---|
| `ev_89102397288972102af6682b0d195cb7b0596931c0ef33ad8769a90223b84728` | inspect_managed_members DYMO.LabelAPI.dll (804 Typen, 6160 Methoden, 1859 #US-Strings) |
| `ev_7304803cc2c5fb945b7ef599340aa2002f9f448804891212a1a70c2a42efd504` | Typen-Seite LabelAPI (alle 804 Typen) |
| `ev_061b1134cc69983eb2e08f83ed38719e17a8db668be8aa26f8433bd590bc5f28` / Seite `ev_f182cb4eb875724124e0ee4eaff45661a84a1ba393acf68f70fc8458e0b0cd72` | 44 Enums (E*) mit allen Werten |
| `ev_c16c8fc01f1ba990754dfd3b8551aab68f84b46531709eae7b61e24d243baa39` / Methoden `ev_e38776bb4c0e23bb79f741f7645f26298a683c6289237502d90d97499e06d825` / Strings `ev_5702a6718eeda227d364250a53d176911b7c3cf0b9ab64b934f195956e33be5b` | Label-Objektklassen, Properties (get_*), Serialisierungsnamen |
| `ev_2b2f5aa17dbcfba7a985a43730b1f8e858e937ecacdfb0339127d32a893e08d6` / Typen `ev_9aef7664baaf0684873bdb1ec7b331e6446e8c8014011874b7089adb4130ecd5` / Strings `ev_a607925fcc731339f47bc161b2a48a9f4f9a3a1e7e0b881fc1b7521224c4f5ac` | DYMO.DCDesktop.dll (478 Typen, 1406 Strings) |
| `ev_01682ee9c0cbabef297335fb335e937bb135b786bc93042ae51eeb9a5809cc4c` / Ressourcen `ev_a07da8ec0bf18cb8e11f32f90a973dbd23be6165d61fa9fa8c2c3b5c02a9c6eb` | DCDesktop Manifest-Ressourcen (287: 257 ClipArt, 2 XSD, 28 .resources) |

Ergänzend (nicht-REA, eigene Parser mit `python3 -I`): `.resources`-Tabellen aller DYMO-Assemblies (Parser `scripts/res.py`, Ausgaben `labelapi_res.txt`, `res_*.txt`), UTF‑16-#US-Strings der Hilfs-Assemblies, XSDs (`dymo-data/DesktopLabel.xsd`, `dymo-data/SmartMobile.xsd` – aus DCDesktop extrahiert), Papers/SKUs-Auswertung (`scripts/papers.py`, `papers_analysis.txt`), Info.plist und DriverKit-dext-Info.plist. `decode_interface_builder` wurde **nicht** genutzt (benötigt geöffnetes Target; REA-Session wird parallel verwendet) – Storyboards nur per Namen/`strings` ausgewertet.

Alle Hilfsdateien liegen unter `<lokales Analyseverzeichnis>/`.

---

## 1. Label-Objekttypen und Eigenschaften

### 1.1 Objekttypen (10) [O]
Quelle: Klassen `DYMO.LabelAPI.{Text,Address,Barcode,QRCode,Image,Shape,Line,Counter,DateTime,CircularText}Object` + jeweilige `*ObjectFactory`; XSD `SmartMobile.xsd` Element `LabelObjects`; `LabelObjectNameLoc` (9 lokalisierte Namen: Text, Address, Barcode, QR Code, Image, Shape, Line, Date and Time, Counter).

| Objekt | Spezifische Eigenschaften [O] |
|---|---|
| **TextObject** | `FormattedText` (Zeilen → `LineTextSpan` → `TextSpan`/`DataMappingTextSpan`/`FixedTextSpan`, je Span eigene `FontInfo`), `FitMode` (None/ShrinkToFit/AlwaysFit), `HorizontalAlignment` (L/C/R), `VerticalAlignment` (Top/Middle/Bottom), `IsVertical` (vertikaler Text), `FillBrush`, `AddressBookMappedColumns` |
| **AddressObject** (erbt Text) | `BarcodePosition` (EIMBBarcodePosition None/Top/Bottom → Intelligent-Mail-Barcode ober/unterhalb), `ValidateUSAddress`, `ZipCodeRegex` (`\d{5}(?:[-\s]\d{4})?`), USPS-Adressprüfung (§2.4) |
| **CircularTextObject** | `CurveType` (ECurvedTextType: TopArc, BottomArc, FullCircle) – im UI-Hinweistext nicht erwähnt [I: evtl. nur für bestimmte Etiketten] |
| **BarcodeObject** | `BarcodeFormat`/`BarcodeType` (25 Typen, s.u.), `Data` (`DataString`/`MappableDataString`/`MultiDataString` → datenbindbar), `Size` (EBarcodeSize: Small„Extra small“, SmallMedium„Small“, Medium, Large, AutoFit), `TextPosition` (EHRTPosition None/Top/Bottom = Klartext ober-/unterhalb), `FontInfo`, H/V-Alignment, `BarcodeIsTooSmall`-Warnung, `BarcodeError` mit Validierungsregeln |
| **QRCodeObject** | `QRDataType` (EQRCodeType, 6 Typen), typisierte `DataHolder` (s. 1.3), Größe (`QRCodeSize`-String) |
| **ImageObject** | `Data` (Base64-Bitmap), `ScaleMode` (None/Fill„Stretch“/Uniform), H/V-Alignment, `ColorMatrix`; Quellen: Datei, Zwischenablage, Kamera, Bildschirmfoto („Screen grab“), PDF-Seite, ClipArt (§3.6) |
| **ShapeObject** | `ShapeType` (Ellipse, Rectangle, RoundedRectangle, Triangle, RightTriangle, Diamond), `StrokeWidth`, `DashPattern` (8 Muster), Fill-/Stroke-Brush |
| **LineObject** | `LineType` (Horizontal, Vertical, ForwardDiagonal, BackwardDiagonal), `StrokeWidth`, `DashPattern` |
| **CounterObject** | `StartAt`, `Increment`, `TextWidth` (Anzahl Stellen), `PrintLeadingZeros`, Prefix/Postfix („Text before/after“) über `BasePrePostTextObject` |
| **DateTimeObject** | `Format` (EDateFormat, 16 Formate), `TimeFormat` (ETimeFormat Date/Time/DateAndTime), `Use24HourTime`, `IsStatic` + `StaticDateTime` (fixes vs. Druckzeit-Datum), Prefix/Postfix |

### 1.2 Gemeinsame Eigenschaften (BaseLabelObject) [O]
`Name` (eindeutig, Pflicht – „Unique name is required.“), `Layout`/`ObjectLayout` (`DYMOPoint` + `DYMOSize`, `MinSize`), `Rotation` (ERotation 0/90/180/270 – nur 90°-Schritte), `RotationEnabled`, `Margin`, `ShowBorder`/`IsOutlined`, `BorderThickness`/`OutlineThickness`, `BorderStyle`, `BorderColor`, Brushes (`BackgroundBrush`, `BorderBrush`, `StrokeBrush`, `FillBrush`; jeweils `SolidColorBrush` ARGB oder `LinearGradientBrush` mit GradientStops). Objekt-Reihenfolge (Bring to front/forward, Send backward/to back), Ausrichten an Objekten und am Etikett (L/C/R/T/M/B), Layout sperren („Lock layout“).

**FontInfo** [O]: `FontName`, `FontSize`, `IsBold`, `IsItalic`, `IsUnderline`, `FontBrush` (Textfarbe), plus `CanBeBold/CanBeItalic/MustBeBold/MustBeItalic/IsCustomFont`. Mehrere Fonts pro Textobjekt möglich (span-basiert). Fontliste aus System (Strings in PlatformSpecific listen Mac-Systemfonts).

**Nicht vorhanden / nicht gefunden** [O/I]: freie Rotation (nur 0/90/180/270), Zeichen-/Zeilenabstand, Durchstreichen, Hoch-/Tiefstellung, Textschatten, Spiegeln pro Objekt (Spiegeln nur global beim Druck: `PrintParameters.Mirror`), Gruppierung von Objekten, Ebenen-Panel (nur „Select objects“-Dialog).

### 1.3 Barcodes – vollständige Liste (25) [O]
`EBarcodeType` + `BarcodeTypesLoc`:
Code 39, Code 39 CS, Code 128 Auto, Code 128 A, Code 128 B, Code 128 C, Code 128 EAN (GS1‑128), Code 2 of 5 (Interleaved), UPC‑A, UPC‑E, EAN‑8, EAN‑13, Codabar, POSTNET, PLANET, Intelligent Mail barcode (IMb), ITF‑14, PDF 417, QR Code, GS1 DataMatrix Square, GS1 DataMatrix Rectangle, sowie Bibliotheks-Varianten Code 3 of 9 Lib L/R und Codabar Lib L/R (13/14 Zeichen, „LibLength“).
Eigene Encoder [O]: DataMatrix (Port von libdmtx, `Dmtx*`), PDF417 (`Pdf417EncoderLibrary`), IMb (`IMb.ImbEncoder`), QR über **QRCoder.dll**.
Validierungsmeldungen (`BarcodeValidationLoc`, 18): Steuerzeichen, gerade Zeichenanzahl, nur Ziffern, nur Großbuchstaben, POSTNET 5/9/11, PLANET 11/13, IMb 20/25/29/31 Ziffern, Datenlänge, ungültige Start/Stop-Zeichen, EC-Level.

### 1.4 QR-Code-Inhaltstypen (6) [O]
Text (`Value`), Telefon (`PhoneNumber`), E-Mail (`To`, `Subject`, `Message`), SMS (`PhoneNumber`, `Message`), vCard (`FirstName`, `LastName`, `Company`, `Title`, `PhoneNumber`, `Address`, `Email`, `Webpage`), Webseite (`URL`). Jeder Typ hat ein eigenes Storyboard (`QRTextEntry`, `QRPhoneEntry`, `QREmailEntry`, `QRSMSEntry`, `QRVCardEntry`, `QRWebPageEntry`).

### 1.5 Datumsformate (16) [O] (`DateFormatsLoc`)
LongSystemDate, ShortSystemDate, Weekday+LongMonth+Day+LongYear, Weekday+Day+LongMonth+LongYear, AbbrWeekday-Varianten, LongMonth Day Year, Day LongMonth Year, Month Day LongYear, Day Month LongYear, M/D/Y, D/M/Y, AbbrMonth-Varianten (4). Uhrzeit 12/24 h.

### 1.6 Etikett-Ebene (DYMOLabel) [O]
`Orientation` (Portrait/Landscape; Wechsel löscht alle Objekte – „Changing the label orientation will delete everything on the label“), `LabelName` (Paper/SKU-Referenz), `Description`, `InitialLength`, `HasFixedLength`/`FixedLengthValue` (Endlosband: fixe oder variable Länge, Tooltip „1.6”–16” (40–400 mm)“), `LengthBehavior` (Fixed/Variable), `RotationBehavior` (ClearObjects/RotateObjects/DoNothing), Etikettrahmen (`Show_Border`, BorderStyle/Color/Thickness), Ränder (Margins, „Set margins (mm/in)“), Layout-Manager: `DynamicLayoutManager`, `GrowingDynamicLayoutManager` (wächst mit Inhalt, EGrowDirection), `ContinuousLayoutManager`. `ColorMatrix`/`BWEquivalent` (Farbetiketten → S/W-Druck).

---

## 2. Daten-Features

### 2.1 Datenimport / Serienetiketten [O]
- Formate: „MS Excel (*.xlsx; *.xlsb; *.xlsm; *.xls)“ via **IronXL.dll** (11 MB, kommerziell), „Text (csv, tab-delimited) (*.txt; *.csv)“ (`ImportFromTextFile`, `GetDataTableFromFile`) – Strings in DYMO.LabelAPI.PlatformSpecific.
- Workflow-Storyboards: `ImportData`, `ImportFromDataFile`, `OldImportFromDataFile`, `DataSelection`, `ViewData`. Optionen: Tabelle/Blatt wählen, Zeilen wählen („Select the sheet and rows to import“, „Select all“), „Use first row as column headers“, Warnung bei abweichendem Blatt („The selected sheet does not match the data previously imported“), „Recent files“.
- Mapping: Drag eines Datenfeldes auf Objekt (`DataMappingTextSpan` mit `ColumnName`; mehrere Felder pro Objekt + freier Text dazwischen). Mappable sind Text/Adresse/Barcode/QR (`IDataMappable`). „Clear data assignments“, „Remove all data“, „Show/Hide data table“.
- Persistenz: importierte Daten werden **in die .dymo-Datei eingebettet** (`DesktopLabel/DataTable/Columns|Rows`). [O]
- Druck: ein Etikett pro Datensatz; Druckbereich „All / Current / Custom Range (1-3, 5)“; Vorschau blättert durch Etiketten („Label {0}“, Next/Prev, Fehlerzähler „error(s)“, „Fix errors“). [O]
- Fehlend [I]: kein Live-Datenbank-Connector (ODBC/SQL), keine Filter/Sortierung im Import-UI außer Zeilenauswahl, keine Formeln/Bedingungen.

### 2.2 Adressbuch / Kontakte [O]
- Eigene „DYMO Lists“ (Kontaktlisten, `DYMO.AddressBook.dll`, SQLite über SQLite-net/e_sqlite3 [I: Speicherort nicht verifiziert]): Felder First/Last name, Company, Address1–3, City, State, Zip, Country, Phone, Email; Listen anlegen/umbenennen/löschen, Sortierung (Vor-/Nachname A‑Z/Z‑A), Suche, Mehrfachauswahl, „Fix addresses“ (USPS, Batch „Fixing {0} US addresses“).
- Import in Listen: aus Tabelle („Import from spreadsheet“), aus **DYMO Label (DLS) Adressbuch `.abx`** (`ReadAndImportABXFile`), Apple Kontakte (CNContactStore, `NSContactsUsageDescription`), **Google Contacts** (People API `people.googleapis.com/v1/people/me/connections`, OAuth `contacts.readonly`), **Outlook/Microsoft 365** (MS Graph `graph.microsoft.com/v1.0/me/contacts`, MSAL `Microsoft.Identity.Client`, Scopes Contacts.Read/ReadWrite).
- Einfügen in Etikett: „Insert contact“, Feld-Layout anpassbar („Arrange field into desired layout“, „Add spaces, text, or line feeds to format the contact“).

### 2.3 Zähler und Datum [O]
Counter (Start, Inkrement, Stellen, führende Nullen, Präfix/Suffix) – wird nach Druck aktualisiert (`IUpdateAfterPrint`, `UpdateValues`). [I] Bei Mehrfachkopien zählt der Zähler pro Etikett hoch (Rendering „MultiLabelPrint {0} labels“).

### 2.4 US-Adressvalidierung + IMb [O]
`https://apis.usps.com/oauth2/v3/token`, `https://apis.usps.com/addresses/v3/address?...`; US-Adress-Parser per Regex (CrossPlatform.Common). „Fix US Address“, IMb über/unter Adresse. Hinweis „Address verification may be temporarily unavailable due to updated USPS service limits“. Für EU-Nutzer irrelevant [I].

---

## 3. App-Features

### 3.1 Dateiformate [O]
- **Speichern**: `.dymo` (UTI `com.dymo.label`, exportiert in Info.plist). XML, Wurzel `DesktopLabel` (Version-Attribut) → `DYMOLabel` (Version) + `LabelApplication` (String) + `DataTable`. Schema: `DesktopLabel.xsd` inkludiert `SmartMobile.xsd` (24,8 KB) – XML-Elementnamen = Klassennamen (`TextObject`, `ObjectLayout/DYMOPoint/X,Y`, `Size/Width,Height`, `Brushes/.../Color A R G B`, Enums als Strings). Koordinaten in der .dymo-Datei: [?] Einheit nicht verifiziert (Papierdaten sind Twips, s. §4; Objektlayout wahrscheinlich Zoll als double [I]).
- **Öffnen**: Filter „(*.label, *.labelx, *.dlabel, *.dymo)“. `.label` = DYMO Label Software 8 (DLS) – Konverter `IDLSLabelConverter`, `DLSToCurrent`, `DLSLabelObjectNodeFactory`, `LabelFileUpgrade`/`UpgradeLabelFile`, `ConvertImagesToBW`; `.labelx` = ältere DC-Version (Templates liegen als .labelx vor); `.dlabel` [I: DYMO-Mobile-/Web-Format].
- **Custom-Etiketten**: Import per XML nach `CustomLabelSchema.xsd` („Import custom label“; DieCutLabel/ContinuousLabel mit Size, PrintableSize, PrintableOrigin, Offset, UISize, DefaultOrientation, DrawCommands: Rectangle, RoundRectangle, Path [Line/LineTo/Arc, FillMode], FoldLine, CutoutShape).
- Share-Funktionen `ShareLabelFile`, `ShareContact` (CrossPlatform.Common) [I: evtl. nur Mobile].

### 3.2 Vorlagen, Favoriten, Zuletzt verwendet [O]
- 67 Vorlagen (`DYMO.LabelTemplates.dll`, .labelx eingebettet) in 11 Kategorien: Address 3, Barcode 5 (Library Barcode, Manifest, QR, Simple Asset, Simple Barcode), Day-of-the-Week Storage 32 (8 Varianten × Portrait/„Lanscape“ × Storage/Shot), File Folder 3, Media 5 (Appointment, Business Card, Checklist, Fax Routing ×2), Medical 2, Name Badge 4, Price Tag 3 (EAN, UPC, Price), Shipping 2, Storage 6, Veterinary 2. „LabelApplication“ = Vorlagen-App-Typ (Storyboard `TemplateSelection`, `LabelApplicationCollectionViewItem`).
- Etikett-Auswahl (`PaperSelection`/`NewLabel`): Suche „Enter a name, SKU #, or size“, Filter nach Material/Farbe („COLOR/DESIGN“, „MATERIAL“), „Recent labels“, „Detected labels“ (aus Drucker erkannte Rolle), Favoriten (Etiketten, ClipArt, Dateien), „My Labels“, zuletzt geöffnete Dateien.

### 3.3 Druckerverwaltung [O]
- Unterstützte Familien (Papers.xml PrinterGroups, Strings, dext): LabelWriter 300/310/315/320/330(Turbo)/400(Turbo)/450 (Turbo/Twin Turbo/DUO Label/DUO Tape/s/v)/SE450/4XL/Wireless/550 (Turbo/Twin Turbo/Pro/Twin Pro)/5XL(Pro), LabelManager 280/420P/PnP(WiFi)/500TS/Executive 640CB/660CB, MobileLabeler (BLE), LabelPoint 350, LM PC II/400/450 (nur dext-Personalities).
- Transport: USB über eigene **DriverKit-Extension** `com.dymo.dymo-connect.usb.dext` (VID 0x0922, 39 Personalities) + privilegierter Helper `com.dymo.dymo-connect.helper` (SMJobBless) + `libdymoprintingsupport.dylib`; Bluetooth LE (LM640, MobileLabeler; `IBLE*`); Netzwerk (Zeroconf `_pdl-datastream._tcp`, `_http._tcp`; „Add network printer“ mit Umbenennen; CUPS-Treiberinstallation „Installing system files for the selected printer“).
- Statusanzeige: Verbindung, Batterie (% / lädt), Rollenstatus links/rechts (Twin Turbo), Restetiketten-Zähler (550er NFC-Rollenerkennung, `RollDetection`), Fehlercodes (`PrinterStatusLoc`, 46 Meldungen: Papierstau, Deckel offen, Cutter, Überhitzung, Akku …), „Authentic DYMO labels detected!“ bzw. „Unknown label detected“ (Fremd-Etiketten werden abgelehnt – „Please insert authentic DYMO labels“).
- Twin Turbo: Rollenwahl Auto/Left/Right (`ERollSelection`), „Use both rolls“ (automatischer Wechsel).
- Wi‑Fi-Setup (LabelWriter Wireless/550-LAN/LM): SSID-Liste, Open/WPA/WPA2/WPA3 Personal/Enterprise, WPS, EAP TLS/TTLS/PEAP, Phase-2 (PAP/CHAP/MSCHAP/MSCHAPV2/MD5), CA-/Client-Zertifikat + Key, statische/dynamische IP, Access-Point-Modus, „Disconnect from network“. LAN-Konfiguration (550 Pro). Bluetooth-Sichtbarkeit (General/Limited 2 min/Off). Cutter-Reinigung („Expose cutter blade“).
- **Firmware-Update**: LW 5xx und LM640 (`Lw5xxFirmwareUpdateProcessor`, `Lm640FirmwareUpdateProcessor`), 11 Zustands-Storyboards (HasUpdate, Downloading, ReadyToInstall, Installing, Success, Failed, Blocked [z.B. Akku < 25 %], NotApplicable, HasFirmwareProblem/Restore).
- **Custom Consumables**: Spezial-Etiketten werden bei Erkennung aus Cloudflare R2 nachgeladen (`DYMO.CloudflareAddin`, „You must download <{0}> to use it“).

### 3.4 Druckoptionen [O]
`PrintParameters`: `Copies`, `Collate`, `Mirror`, `PrintQuality` (UI: Auto/Text/„Barcode and graphics“), `PrintDensity` (Light/Medium/Normal/Dark), `EnableHighSpeedMode` („High speed“), `RollSelection`, `UseChainMarks`/`ECutOption` (Cut/ChainMarks/DoNothing → „Auto-cut“: an = schneiden, aus = Schnittmarken), `IsDurable`/`EMediaType`, `PrintAnalytics`. Druckbereich bei Datenimport (All/Current/Custom). „Print settings“ als Standardwerte in den Einstellungen. Fehler „Print job too large“.

### 3.5 Einstellungen [O] (`PreferencesLoc`, `Settings`-Storyboard)
Maßeinheit (English inches / Metric mm), Sprache (Neustart nötig), Display-Kalibrierung (Pixel pro Zoll, Neustart nötig), Lineale & Hilfslinien, Layout standardmäßig gesperrt, Standard-Druckeinstellungen, Auto-Update-Check, „Improve DYMO products“ (Analytics), Werkseinstellungen. Weitere Präferenzschlüssel: `EnableSnapping`, `EnableOldDesign`, `UseBlurEffect`, Fensterposition.

### 3.6 Weitere Editor-Funktionen [O]
Undo/Redo (`IUndoService`), Zoom (Zoombar, „Fit to design area“, 100 %), Lineale/Hilfslinien, Snapping, Ausrichten/Anordnen, Mehrfachauswahl, Copy/Paste, ClipArt-Bibliothek **257 Bilder** in 11 Kategorien (Miscellaneous 60, Veterinary 38, Weather & seasonal 28, Business 28, Warning & emergency 25, Electrical 19, Accordion Icons 19, Arrows 18, Shapes 8, Mailing 7, Health & Safety 7) mit Favoriten/Zuletzt; Bild aus Kamera (Continuity-Kamera-App), Bildschirmausschnitt, Zwischenablage, PDF-Seite (Seitenauswahl + Zuschnitt `PdfEditImage`); Kontext-Hilfe-Bubbles („Tip!“), Quick Tips, Benutzerhandbücher (PDF-Links je Drucker), „Buy labels“ (SkuLinks.xml → dymo.com-Shop je Land), Produktregistrierung, „Start DYMO Stamps“.

### 3.7 Updates, Analytics, Netzwerk [O]
- App-Update: `https://dymoreleasecontent.blob.core.windows.net/dymo-release/` + `Software/dymoconnect/updates/Mac/Updates.xml`; Dialoge Available/Download/Details, „Remind me later“, „Don’t show again“.
- Analytics: **Google Analytics Universal Measurement Protocol** über `http://www.google-analytics.com/collect` (unverschlüsseltes HTTP; UA wurde von Google eingestellt → [I] vermutlich wirkungslos), `DYMOPrintAnalytics`, Opt-in „Collect data“.

### 3.8 Sprachen [O]
26 `.lproj` + Base: ar, cs, da, de, es, es‑CO, fi, fr, fr‑CA, hi, hu, it, ja, ko, nl, no, pl, pt, pt‑BR, ru, sk, sv, th, tr, vi, zh‑Hans (+ en). SKU-Suchbegriffe sind mehrsprachig in `SearchTerms` gepflegt.

---

## 4. Papier-/Rollen-Datenmodell

### 4.1 Einheiten [O, verifiziert]
**Twips (1/1440 Zoll)**. Belege: SKU 1738541 „1 in x 2-1/8 in“ → DrawCommands `Width=1440 Height=3060` (2,125 × 1440 = 3060); D1 12 mm → `Width=688` (688/1440 in = 12,1 mm); 30252 Address 1569,6 × 5040 = 1,09 × 3,5 in. Werte teils mit Dezimalstellen (z.B. 806.4 = 0,56 in → Raster 1/300 in bzw. 4,8 Twips).

### 4.2 Struktur [O]
- **Papers.xml**: `PaperGroups` (8: LabelWriter400 110 Papiere, LabelWriterSE450 12, LM 640 5, LM 420P 4, LM PNP 3, LM 280 3, MobileLabeler 5, DUO Tape 5) und `PrinterGroups` (13; `PaperGroupId`, `DriverNames`, `ExcludedPapers`). Die 450er/550er/4XL/5XL/Wireless sind **alle** in Gruppe `LabelWriter400`, Unterschiede nur über `ExcludedPapers` (z.B. 550 schließt 14 Papiere aus, 5XL 4).
  - `Paper` (Die-cut, 120): `@Name`, `Size{Width,Height}`, `PrintableSize`, `PrintableOrigin{X,Y}`, `Offset{X,Y}` (147× – teilweise mehrfach), `DefaultOrientation`.
  - `ContinuousPaper` (27): `@Name`, `@TapeWidth` (tw6mm…tw24mm/Unknown), `Leader`, `Trailer`, `Width`, `PrintableWidth`, `Offset`. D1-Breiten: 6 mm=352, 9 mm=512, 12 mm=688, 19 mm=1088, 24 mm=1360; 30270 Continuous 56 mm = 3514. LM 280/PnP max. 12 mm, 420P max. 19 mm, 640/MLS/DUO 24 mm.
- **SKUs.xml** (193): `DieCutSKU` 106 + `ContSKU` 87 (85 D1 + 2× 30270). Attribute: `Name`, `PaperName` (FK → Papers), `SKU`, `ForegroundColor`/`BackgroundColor` (ARGB), `SearchTerms` (mehrsprachig), `EnglishName`/`MetricName`/`LongName`/`GroupName`/`GroupNameMetric` (Schlüssel in `SKUsLoc`/`TranslatedSKUsLoc`), `Material` (Standard 159, Durable 29, Nylon 2, Permanent 2, Poly 1), `Region` (EMEA 85, NorthAmerica 84, Global 24), `ColorMatrix` (IDENTITY, BLACK_ON_YELLOW_2, RED_ON_WHITE, …), `LastEditedUTC` (2021‑01‑12 … 2025‑08‑28), Die-cut: `CornerRadius` + `DrawCommands` (RoundRectangle/Path/Arc/LineTo/FoldLine – Etikettenkontur für die Vorschau); Cont: `D1Width` (Loc-Key) + `D1WidthMetric`.
- **SKUs pro Druckergruppe** (über PaperName, Papier kann in mehreren Gruppen liegen): LabelWriter400 108, LabelWriterSE450 10, LM 640 85, MobileLabeler 85, DUO Tape 85, LM 420P 71, LM PNP 50, LM 280 50 (vor `ExcludedPapers` und vor Region-Filter).
- **VirtualPapers.xml**: Papiergruppen LabelWriter300 (11), LabelWriter400 (24), LabelWriterSE450 (12), DZMax1Inch (17), DZMax2Inch (39) – „offset“-Varianten für ältere Drucker/virtuelle Drucker [I].
- **Labels.xml**: 83 DieCutLabel + 84 ContinuousLabel (Id, PaperName, DrawCommands, 27× `SmartSenseId` – Rollenerkennung älterer Geräte [I]).
- **SkuLinks.xml**: Shop-Links je Land/Locale.
- **Printers.xml**: Minimal (4XL USB/Classic, „Mobile Labeling System“ BLE/Modern).

### 4.3 Wichtige Felder für MacLabel
`Size` + `PrintableSize` + `PrintableOrigin` (Druckbereich), `Offset` (Kopfversatz), `DefaultOrientation`, `CornerRadius`/`DrawCommands` (Kontur-Vorschau), `Region` (Länderfilter), `Material`, `ColorMatrix`/Farben (Vorschau + S/W-Konvertierung), `SearchTerms` (Suche), `TapeWidth`/`Leader`/`Trailer` (Endlos), `ExcludedPapers` (Gerätekompatibilität).

### 4.4 Inkonsistenzen [O]
1. **Gleiche Größe, widersprüchliche DefaultOrientation** (innerhalb Gruppe LabelWriter400; 15 Größen-Duplikate, davon 3 mit Konflikt):
   - 3240 × 1800 (57 × 32 mm): `30334 2-1/4 in x 1-1/4 in` **Portrait**, `1933084 Drbl 2-1/4 x 1-1/4 in` **Portrait**, `11354 Multi-Purpose` **Landscape**. EMEA-SKU **S0722540** („multipurpose“, d.h. das EU-Pendant zu 11354) und Durable **2112289** (32 × 57 mm) zeigen auf Portrait-Papiere; das Papier `11354 Multi-Purpose` wird von **keiner** SKU referenziert.
   - 1440 × 1440 (25 × 25 mm): `30332 1 in x 1 in` **Portrait**, `LWCS-504` **Portrait**, aber `1933083 Drbl 1 x 1 in`, `11353 Multi-Purpose`, `30333 (2 up)` **Landscape**. SKUs 1933083, 2112286, S0929120 zeigen auf 30332 (Portrait), während das eigene Papier `1933083 Drbl 1 x 1 in` (Landscape) ungenutzt bleibt.
   - 3326,4 × 3744: `30854 CD Label` **Portrait** vs. `14681 CD/DVD Label` **Landscape**.
   [I] `DefaultOrientation` bezieht sich auf das Papier-Koordinatensystem (Width = quer zum Druckkopf): bei W<H ist „Landscape“ fast überall gesetzt (81 von 83), bei W>H meist „Portrait“ (14 von 20). Ergebnis: dasselbe physische Etikett öffnet je nach SKU-Zuordnung hochkant oder quer.
2. **52 Papiere werden von keiner SKU referenziert** (u.a. 11351/11353/11354/11355/11356, 14681, 99010–99016, 30320, 30364, 30857, CD-Labels, Banner) – tote Daten oder nur über Templates/.label-Import erreichbar [I].
3. **68 von 106 Die-cut-SKUs** zeigen auf Papiere mit fremder Artikelnummer (EMEA S07…/Durable 2112xxx → US‑303xx-Papiere). Mapping ist rein über `PaperName`-String.
4. `CornerRadius="75"` ist bei **allen** 106 Die-cut-SKUs konstant, während die DrawCommands Rx = 0/75/90/120/180/270 verwenden → Attribut redundant/falsch.
5. Druckergruppe LabelWriter400 schließt Papiere aus, die SKUs verwenden (z.B. 4×6 in `1744907` für 450/550 – korrekt, da nur 4XL/5XL; aber auch `2166659 DHL Labels`).
6. Kleinere Datenfehler: Papiername-Varianten nur in Groß-/Kleinschreibung (`11356 White Name badge` vs. `11356 White Name Badge - virtual`), SKU-Name „Address Clear176074“ für SKU 1760754, Templates „…Lanscape.labelx“, „Veterinary Sample 2.label.labelx“; dext-Personalities mit doppelten Product-IDs (29: DUO Label/DUO Tape 128; 35: 450 DUO Label/DUO Tape 128 - 2; 23: DUO Label - 2/DUO Tape).

---

## 5. UX-Schwächen (strukturell belegt)

- **Dialoglastig** [O/I]: 97 Storyboards + 31 Nibs; davon ~40 eigenständige Dialog-Szenen (3 generische MessageBoxen OK/OKCancel/YesNoCancel, 11 Firmware-Zustandsdialoge, 6 QR-Eingabedialoge, 4 Kontaktquellen, Wi‑Fi in 6 Storyboards, Import in 5). Jede QR-Variante = eigener modaler Editor statt Inline-Inspector [I].
- **Neustarts nötig** [O]: Sprache und Display-Kalibrierung („Restart DYMO Connect for the changes to take effect“).
- **Destruktive Orientierungsänderung** [O]: Wechsel löscht alle Objekte.
- **Manuelle Bildschirmkalibrierung** [O] („Select the display setting that shows the squares … closest to 1 inch“) – unnötig unter macOS (NSScreen liefert physische Größe).
- **Nur 90°-Rotation, keine Gruppierung, keine Objekt-Spiegelung** [O/I].
- **Eigenes Cross-Platform-UI** (WPF-artige ViewModels/Converter, „Hide Others“/„Minimize“-Strings, eigene Buttons `DYMOButton`) statt nativer macOS-Controls [O]; Hilfe-Links zeigen auf `/DCDesktop/win/…` (Windows-Hilfe) [O].
- **Systemerweiterung + privilegierter Helper** für USB-Druck [O] („System Extension Blocked“-Dialog) – hohe Einstiegshürde.
- **DRM-artige Etikettensperre** [O]: Fremd-/unbekannte Rollen werden auf 550ern abgelehnt.

---

## 6. Empfehlungen für MacLabel (kurz, [I])
1. Objektmodell 1:1 übernehmen (10 Typen, span-basierter Text, Datenbindung pro Span), aber freie Rotation, Gruppen, Ebenenliste ergänzen.
2. Barcodes: 25 Symbologien; CoreImage liefert Code128/QR/PDF417/Aztec nativ, Rest (EAN/UPC/ITF/Codabar/Code39/DataMatrix/IMb) selbst implementieren.
3. Papier-DB als bereinigtes JSON (Twips → mm/pt beim Import), Orientierung visuell definieren (z.B. `feedAxis` + `defaultTextDirection`) und Duplikate deduplizieren.
4. `.dymo`-Import/Export (XML, Schema vorhanden) + `.label`-(DLS)-Import als Kompatibilitätsfeature.
5. Datenimport via CSV/TSV nativ, XLSX über leichtgewichtige Bibliothek (z.B. CoreXLSX); Kontakte über Contacts.framework, Google/Graph optional.
6. Druck: USB über IOKit/IOUSBHost ohne dext prüfen (bzw. CUPS-Treiber nutzen), Netzwerk via Bonjour `_pdl-datastream._tcp`.
