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

Erwartet: Scharfer, quadratischer QR-Code mit Beschriftung darunter. Mit dem Handy scannen; die URL wird erkannt.
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
