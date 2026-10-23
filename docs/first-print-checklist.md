# Checkliste für den ersten Testdruck

Ziel: Am echten Gerät (LabelWriter 450, Rolle 11354 / S0722540 „Vielzweck 57 × 32 mm“) prüfen, ob Ausrichtung, Spiegelung, Ränder und Mehrfachdruck stimmen. Bisher wurde nichts am Gerät gedruckt; alle Werte sind aus Tests und Datenblättern abgeleitet.

Vorbereitung: Drucker per USB anschließen, Rolle 11354 einlegen, im Repo-Verzeichnis arbeiten. Nach der Installation lässt sich `swift run maclabel …` durch `maclabel …` ersetzen. Verbrauche pro Schritt nur das angegebene Etikett.

## 1. Status (nur lesen)

```
swift run maclabel status
maclabel status
```

Erwartet: Modell „LabelWriter 450“, Firmware, „bereit“. Optional `swift run maclabel printers` zeigt die Seriennummer.
Wenn falsch: Drucker nicht gefunden oder nicht bereit → Kabel, Rolle und Deckel prüfen und Meldung zurückmelden. Hier wird nichts gedruckt.

## 2. Testdruck „MacLabel Test ↑“ auf 11354 (ein Etikett!)

```
swift run maclabel print --roll 11354 "MacLabel Test ↑"
maclabel print --roll 11354 "MacLabel Test ↑"
```

Optional vorher ohne Druck: `swift run maclabel print --roll 11354 --dry-run preview.png "MacLabel Test ↑"`.

Prüfen:
- Ausrichtung: Der Text läuft entlang der langen 57-mm-Kante, der Pfeil zeigt zur Oberkante des Etiketts, wenn es quer gehalten wird.
- Nicht gespiegelt: Buchstaben sind seitenrichtig.
- Ränder: Rundum gleichmäßig, nichts abgeschnitten, links und rechts gleich weit vom Etikettenrand.

Wenn falsch:
- Gespiegelt (links/rechts vertauscht) → Bitreihenfolge in `Sources/LabelProtocol/MonochromeBitmap.swift` (MSB = linkester Punkt, `0x80 >> (x % 8)`) bzw. x-Abbildung in `LabelGeometry.headTransform()` (`Sources/LabelRender/LabelGeometry.swift`).
- Um 180° gedreht oder Text läuft in die falsche Richtung → `.clockwise90`-Abbildung in `LabelGeometry.headTransform()` (Gegenrichtung ist `.counterClockwise90`).
- Seitlich versetzt oder auf einer Seite abgeschnitten → `offsetDots` (Rolle) bzw. die `printableRect.x`-Begrenzung in `LabelGeometry`.
- Oben/unten versetzt oder Text am Anfang abgeschnitten → `originFeedDots`.

## 3. Adressetikett auf 99010 (Drehung) – optional

Nur mit Rolle 99010 (Adressetikett 89 × 28 mm); sonst überspringen.

```
swift run maclabel print --roll 99010 "Max Mustermann\nMusterstraße 1\n12345 Musterstadt"
maclabel print --roll 99010 "Max Mustermann\nMusterstraße 1\n12345 Musterstadt"
```

Erwartet: Text aufrecht lesbar, Etikett längs gehalten, nicht gespiegelt, gleichmäßige Ränder. Dieses Format wird ohne Drehung (`.upright`) gedruckt; 11354 dagegen mit Drehung.
Wenn falsch: Drehung/Versatz wie in Schritt 2 (`LabelGeometry`).

## 4. QR-Code mit 600 lpi und Handy-Scan

```
swift run maclabel print --roll 11354 --layout qr --caption "MacLabel" "https://example.com/maclabel"
maclabel print --roll 11354 --layout qr --caption "MacLabel" "https://example.com/maclabel"
```

Erwartet: Scharfer, quadratischer QR-Code mit Beschriftung darunter. Mit dem Handy scannen; die URL wird erkannt.
Wenn falsch: Scan schlägt fehl oder Code verzerrt → Zeilenabstand/Auflösung (600 lpi, `quality.linesPerInch`) und Skalierung in `LabelGeometry.headTransform()` (`sy`) prüfen. Bei Vertikalversatz `originFeedDots`. Bei zu blassem Druck `--density dark` testen.

## 5. EAN-13-Scan

```
swift run maclabel print --roll 11354 --layout barcode --symbology ean13 "4006381333931"
maclabel print --roll 11354 --layout barcode --symbology ean13 "4006381333931"
```

Erwartet: Balken senkrecht zur Etikettenkante, Ziffern lesbar. Mit Handy oder Scanner lesen: 4006381333931.
Wenn falsch: Nicht lesbar → zuerst Spiegelung/Drehung (Schritt 2), dann Dichte (`--density dark`) und `offsetDots`.

## 6. Zwei Kopien mit Zähler

```
swift run maclabel print --roll 11354 --copies 2 --counter 1 "Box {n}"
maclabel print --roll 11354 --copies 2 --counter 1 "Box {n}"
```

Erwartet: Zwei Etiketten, „Box 1“ und „Box 2“. Zwischen den Etiketten wird ESC G (Kurzvorschub) gesendet, es kommt kein leeres Etikett heraus und das Papier springt nicht verzogen vor.
Wenn falsch: Leeres Zusatzetikett, Versatz ab dem zweiten Etikett oder Zähler falsch → Meldung zurückmelden (Ablauf in `LabelKit`/`LWClassicEncoder`); Versatz ggf. `originFeedDots`.

## 7. Papier leer (optional)

Rolle entfernen bzw. Papier leer laufen lassen, dann:

```
swift run maclabel status
swift run maclabel print --roll 11354 "Leertest"
```

Erwartet: Klare Fehlermeldung „Papier leer“ (kein Hängen, kein Absturz). Nach dem Einlegen einer Rolle funktioniert der nächste Druck wieder.
Wenn falsch: Hängt der Aufruf oder fehlt die Meldung → Verhalten und Statusbyte zurückmelden.

## Ergebnis zurückmelden

Bitte dem Entwickler mitteilen:
- Pro Schritt: richtig / falsch, bei falsch kurze Beschreibung oder Foto (Etikett quer gehalten, Pfeilrichtung sichtbar).
- Bei Versatz: ungefähr wie viele Millimeter und in welche Richtung.
- Ausgabe von `maclabel status` und `maclabel printers`.
- Ob QR-Code und EAN-13 mit dem Handy gelesen wurden.
- Etwaige Fehlermeldungen im Wortlaut.
