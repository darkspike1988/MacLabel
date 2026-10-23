# Checkliste für den ersten Testdruck

Ziel: Am echten Gerät (LabelWriter 450, Rolle 11354 / S0722540 „Vielzweck 57 × 32 mm“) prüfen, ob Ausrichtung, Spiegelung, Ränder und Mehrfachdruck stimmen. Bisher wurde nichts am Gerät gedruckt; alle Werte sind aus Tests und Datenblättern abgeleitet.

Vorbereitung: Drucker per USB anschließen, Rolle 11354 einlegen, im Repo-Verzeichnis arbeiten. Alle Befehle sind als `swift run maclabel …` angegeben; nach der Installation funktioniert `maclabel …` identisch. Verbrauche pro Schritt nur das angegebene Etikett.

## 1. Status (nur lesen)

```
swift run maclabel status
```

Erwartet: Modell „LabelWriter 450“, Firmware, „bereit“. Optional `swift run maclabel printers` zeigt die Seriennummer.
Wenn falsch: Drucker nicht gefunden oder nicht bereit → Kabel, Rolle und Deckel prüfen und Meldung zurückmelden. Hier wird nichts gedruckt.

## 2. Testdruck „MacLabel Test ↑“ auf 11354 (ein Etikett!)

```
swift run maclabel print --roll 11354 "MacLabel Test ↑"
```

Optional vorher ohne Druck: `swift run maclabel print --roll 11354 --dry-run preview.png "MacLabel Test ↑"`.

Rolle 11354 (57,1 mm quer × 31,8 mm Vorschub) wird ohne Drehung (`.upright`) gedruckt.

Prüfen:
- Ausrichtung: Der Text läuft entlang der langen 57-mm-Kante, der Pfeil ↑ zeigt zur Oberkante des Etiketts (Etikett so halten, dass die 57-mm-Kante unten liegt).
- Nicht gespiegelt: Buchstaben sind seitenrichtig.
- Ränder: Rundum gleichmäßig, nichts abgeschnitten, links und rechts gleich weit vom Etikettenrand.

Wenn falsch:
- Gespiegelt (links/rechts vertauscht) → Bitreihenfolge in `Sources/LabelProtocol/MonochromeBitmap.swift` (MSB = linkester Punkt, `0x80 >> (x % 8)`) bzw. x-Abbildung im `.upright`-Zweig von `LabelGeometry.headTransform()` (`Sources/LabelRender/LabelGeometry.swift`).
- Auf dem Kopf stehend oder Text kippt → `.upright`-Zweig von `headTransform()`.
- Seitlich versetzt oder auf einer Seite abgeschnitten → `offsetDots` (Rolle) bzw. die `printableRect.x`-Begrenzung in `LabelGeometry`.
- Oben/unten versetzt oder Text am Anfang abgeschnitten → `originFeedDots`.

## 3. Adressetikett auf 99010 (Drehung) – optional

Nur mit Rolle 99010 (27,7 mm quer × 88,9 mm Vorschub); sonst überspringen. Dies ist der einzige Schritt, der den `.clockwise90`-Zweig von `headTransform()` testet.

```
swift run maclabel print --roll 99010 "Max Mustermann\nMusterstraße 1\n12345 Musterstadt"
```

Erwartet: Der Text läuft entlang der langen 89-mm-Kante und ist bei längs gehaltenem Etikett aufrecht lesbar, nicht gespiegelt, mit gleichmäßigen Rändern.
Wenn falsch: Text steht auf dem Kopf oder liest sich von unten nach oben → Matrix im `.clockwise90`-Zweig von `LabelGeometry.headTransform()` prüfen (`.counterClockwise90` ist die Gegenrichtung). Gespiegelt → Bitreihenfolge bzw. x-Abbildung wie in Schritt 2. Versatz → `offsetDots` / `originFeedDots`.

## 4. QR-Code mit 600 lpi und Handy-Scan

```
swift run maclabel print --roll 11354 --layout qr --caption "MacLabel" "https://example.com/maclabel"
```

Erwartet: Scharfer, quadratischer QR-Code links, die Beschriftung „MacLabel“ rechts daneben (mit deutlichem Abstand zum Code). Mit dem Handy scannen; die URL wird erkannt.
Wenn falsch: Scan schlägt fehl oder Code verzerrt → Auflösung (600 lpi) und Skalierung in `LabelGeometry.headTransform()` (`Sources/LabelRender/LabelGeometry.swift`) prüfen. Bei Vertikalversatz `originFeedDots`. Bei zu blassem Druck `--density dark` testen.

## 5. EAN-13-Scan

```
swift run maclabel print --roll 11354 --layout barcode --symbology ean13 "4006381333931"
```

Erwartet: Balken stehen senkrecht (bei aufrecht gelesenem Etikett, 57-mm-Kante unten), Ziffern darunter lesbar. Mit Handy oder Scanner lesen: 4006381333931.
Wenn falsch: Nicht lesbar → zuerst Spiegelung/Drehung (Schritt 2), dann Dichte (`--density dark`) und `offsetDots`.

## 6. Zwei Kopien mit Zähler

```
swift run maclabel print --roll 11354 --copies 2 --counter 1 "Box {n}"
```

Erwartet: Zwei Etiketten, „Box 1“ und „Box 2“. Zwischen den Etiketten wird ESC G (Kurzvorschub) gesendet, es kommt kein leeres Etikett heraus und das Papier springt nicht verzogen vor.
Wenn falsch: Leeres Zusatzetikett, Versatz ab dem zweiten Etikett oder Zähler falsch → Meldung zurückmelden (Ablauf in `LabelKit`/`LWClassicEncoder`); Versatz ggf. `originFeedDots`.

## 7. Zwei Kopien als QR-Code (Grafikmodus, 600 lpi)

```
swift run maclabel print --roll 11354 --layout qr --caption "Kopie" --copies 2 "https://example.com/maclabel"
```

Erwartet: Zwei gleiche Etiketten; das zweite sitzt genauso auf dem Etikett wie das erste (kein Versatz nach oben/unten, kein angeschnittener Code). Beide Codes lassen sich scannen.
Wenn falsch: Versatz nur beim zweiten Etikett → Längenangabe `ESC L` im Grafikmodus bzw. `ESC G` zwischen den Etiketten (`LWClassicEncoder`); Foto beider Etiketten zurückmelden.

## 8. Zwei Aufträge direkt hintereinander

```
swift run maclabel print --roll 11354 "Auftrag 1" && swift run maclabel print --roll 11354 "Auftrag 2"
```

Erwartet: Genau zwei Etiketten, kein leeres Etikett dazwischen. Der Rückvorschub nach dem Ende des ersten Auftrags (`ESC E`) ist in Ordnung; „Auftrag 2“ sitzt richtig auf seinem Etikett.
Wenn falsch: Leeres Etikett oder Versatz beim zweiten Auftrag → Meldung mit Foto zurückmelden (Kopf `jobHeader` bzw. `endOfJob` in `LWClassicEncoder`).

## 9. Endlosrolle (nur falls Endlosrolle vorhanden)

Nur mit einer Endlosrolle (z. B. 30270); sonst überspringen.

```
swift run maclabel print --roll 30270 --length 50 "Endlos 50 mm"
```

Erwartet: Ein etwa 50 mm langer Abschnitt mit dem Text, kein Suchen nach einer Etikettenlücke, kein langer Leervorschub.
Wenn falsch: Drucker sucht eine Lücke oder schiebt lange Papier nach → Länge `ESC L FF FF` für Endlosrollen (`PrintService`) prüfen; gemessene Länge zurückmelden.

## 10. Drucker belegt

DYMO Connect öffnen, dort einen Druck starten und sofort danach:

```
swift run maclabel status
echo $?
```

Erwartet: Meldung „Drucker wird gerade von einer anderen App benutzt.“ und Exit-Code 75. Kein Hängen, kein Absturz.
Wenn falsch: Anderer Exit-Code, andere Meldung oder Hängen → Ausgabe im Wortlaut zurückmelden (`USBPrinterConnection.mapOpenError`).

## 11. Abgebrochener Auftrag

```
swift run maclabel print --roll 11354 --copies 3 --counter 1 "Abbruch {n}"
```

Während des Drucks (nach dem ersten Etikett) Ctrl-C drücken. Danach:

```
swift run maclabel print --roll 11354 "Nach Abbruch"
```

Erwartet: Der zweite Befehl druckt „Nach Abbruch“ richtig ausgerichtet auf ein eigenes Etikett (der nächste Auftrag beginnt mit einer Resynchronisierung).
Wenn falsch: Versatz, Datenmüll oder halbes Etikett → Foto und Ausgabe zurückmelden.

## 12. Langer Code128 (~30 Zeichen)

```
swift run maclabel print --roll 11354 --layout barcode "MACLABEL-TEST-0123456789-ABCDE"
```

Erwartet: Entweder wird der Barcode gedruckt und lässt sich mit Handy oder Scanner lesen, oder der Druck wird mit „passt nicht“ (Exit-Code 65) abgelehnt. Ein gedruckter, aber nicht lesbarer Barcode ist ein Fehler.
Wenn falsch: Gedruckt, aber nicht lesbar → Mindest-Modulbreite in `BarcodeLayout` und Dichte (`--density dark`) zurückmelden.

## 13. Papier leer (optional)

Rolle entfernen bzw. Papier leer laufen lassen, dann:

```
swift run maclabel status
swift run maclabel print --roll 11354 "Leertest"
```

Erwartet: Klare Fehlermeldung „Papier leer“ (kein Hängen, kein Absturz). Nach dem Einlegen einer Rolle funktioniert der nächste Druck wieder.
Wenn falsch: Hängt der Aufruf oder fehlt die Meldung → Verhalten und Statusbyte zurückmelden.

## Ergebnis zurückmelden

Bitte dem Entwickler mitteilen:
- Pro Schritt: richtig / falsch, bei falsch kurze Beschreibung oder Foto (Etikett so gehalten, dass die 57-mm-Kante unten liegt, Pfeilrichtung sichtbar).
- Bei jedem Fehldruck: denselben Befehl zusätzlich mit `--dry-run fehldruck.bin` ausführen und die `.bin`-Datei mitschicken (die Druckerbytes zur Diagnose; es wird dabei nichts gedruckt).
- Bei Versatz: ungefähr wie viele Millimeter und in welche Richtung.
- Ausgabe von `maclabel status` und `maclabel printers`.
- Ob QR-Code und EAN-13 mit dem Handy gelesen wurden.
- Etwaige Fehlermeldungen im Wortlaut.
