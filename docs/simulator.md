# LW450-Simulator (`LabelSimulator`)

Der Simulator führt die Bytestreams, die MacLabel an einen LabelWriter 450 schickt, byte-genau aus und zeichnet den Etikettenstreifen, der dabei physisch herauskäme. So lassen sich Positionsfehler untersuchen, ohne zu drucken. Er öffnet nie ein USB-Gerät.

## Was exakt modelliert ist

- **Kommandosatz** nach `docs/research/lw450-protocol.md` §2: Resync-Läufe (≥ 85 × ESC, kürzere Läufe sind ein Fehler), `ESC @`, `ESC *`, `ESC Q`, `ESC B`, `ESC D`, `ESC L`, `ESC h`/`ESC i`, `ESC c/d/e/g`, `ESC q`, `ESC f 1 n`, `SYN`, `ETB` (RLE; die Pixelsumme muss genau BPL × 8 ergeben), `ESC G`, `ESC E`, `ESC A` (Antwort `0x03`/`0x01`), `ESC V` (Antwort `1750111f0J`). `ESC y`/`ESC z` (nur SE450), unbekannte ESC-Kommandos, Bytes außerhalb eines Kommandos, abgeschnittene Kommandos und Werte außerhalb des Bereichs (z. B. Dot Tab + BPL > 84) lösen einen `SimulatorError` mit Offset aus. Der Simulator findet damit auch Protokollfehler.
- **Zeilenvorschub:** Jede Rasterzeile und jede `ESC f`-Leerzeile schiebt um eine Zeile des **aktuellen** Modus vor: 25,4/300 mm bei `ESC h`, 25,4/600 mm bei `ESC i`.
- **`ESC G`:** Vorschub bis zum nächsten Top-of-Form (Sensor), ohne Rückwärtsfahrt.
- **`ESC E`:** Vorschub bis zum nächsten Top-of-Form, dann um `headToTearBarMM` zur Abreißkante. Danach steht eine Rückwärtsfahrt aus. Sie wird bei der ersten Bewegung des nächsten Auftrags ausgeführt (Rasterzeile, `ESC f`, `ESC G` oder `ESC E`).
- **Messung pro Seite** (Seite = Etikett im Bytestrom, getrennt durch `ESC G`): Rand oben (Vorderkante bis erste Tinte), Rand unten (letzte Tinte bis Hinterkante), Inhaltshöhe, Soll-Rand oben (Zeilen vor der ersten Tinte), **Shift** = Ist − Soll (positiv = tiefer) und **clipped** (Tinte außerhalb des Etiketts, also auf dem Trägerpapier oder dem Nachbaretikett). Die Seite wird dem Etikett zugeordnet, dessen Top-of-Form ihrem Startpunkt am nächsten liegt.
- **Streifenbild:** 600 px pro Zoll in beiden Richtungen, also mit richtigem Seitenverhältnis. 600-lpi-Zeilen sind 1 px hoch, 300-lpi-Zeilen 2 px. Das Trägerpapier ist grau, die Etiketten sind weiß mit runden Ecken. Das Sensorloch ist schematisch als Rahmen am linken Rand eingezeichnet. Tinte auf dem Etikett erscheint schwarz. Tinte auf dem Trägerpapier erscheint hellgrau, weil sie dort unsichtbar bliebe. Striche im linken Rand markieren den Beginn jedes Auftrags.

## Was Hypothese ist

### Mechanik (`MechanicalModel`, alle Werte in mm, alle überschreibbar)

| Parameter | Default | Herkunft |
|---|---|---|
| `labelLengthMM` | 31,75 | Katalog 11354: 375 Dots bei 300 dpi |
| `gapMM` | **4,5** | **geschätzt**, siehe unten |
| `senseHoleOffsetMM` | 0 | Lage des Top-of-Form-Lochs relativ zur Vorderkante (unbekannt) |
| `headToSensorMM` | 0 | Abstand Sensor → Druckzeile (unbekannt). Die erste Zeile landet bei TOF `senseHoleOffsetMM − headToSensorMM` unter der Vorderkante |
| `headToTearBarMM` | 12 | Druckzeile → Abreißkante (geschätzt) |
| `stepMM(.text)` / `stepMM(.graphics)` | 25,4/300 bzw. 25,4/600 | Datenblatt |

**Herleitung des Abstands:** DYMO veröffentlicht den Etikettenabstand (Pitch) der 11354 nicht. Eine Rolle hat 1000 Etiketten, einen Kern von 25 mm, höchstens 85 mm Rollendurchmesser und 0,13–0,15 mm Materialstärke. Die Bandlänge ist π·(R² − r²)/d = π·(42,5² − 12,5²)/0,13…0,15 ≈ 34,6–39,9 m. Daraus folgt ein Pitch von etwa 35–40 mm, also ein Abstand von etwa 3–8 mm. 85 mm ist nur der Höchstwert für den Durchmesser. Bei einer kleineren Rolle wird der Pitch kürzer, deshalb ist 3–6 mm die realistische Spanne. Als Default gilt 4,5 mm, die Sweeps decken 3–6 mm ab. **Bitte nachmessen** (siehe Kalibrierung).

Wichtig: Für die vorhergesagten Shifts und Clipped-Flags spielt der Abstand im Modell **keine Rolle**, weil alle Positionen relativ zum Sensorloch des jeweiligen Etiketts gerechnet werden. Er bestimmt nur das Bild und die Frage, wann ein Überlauf auf das nächste Etikett trifft.

### Rückwärtsfahrt (`ReverseFeedHypothesis`)

| Name (CLI) | Bedeutung |
|---|---|
| `exact` | fährt genau zum Top-of-Form zurück |
| `none` | fährt nicht zurück (Shift = Abreißweg) |
| `current-mode` | Abreißweg in 300-lpi-Zeilen gezählt, ausgeführt mit der Schrittweite des **aktuellen** Modus (bei 600 lpi nur der halbe Weg) |
| `mode-at-ff` | wie oben, aber mit der Schrittweite des Modus, der beim `ESC E` aktiv war |
| `ff-lines-current-mode` | Abreißweg in Zeilen des Modus beim `ESC E` gezählt, ausgeführt im aktuellen Modus |
| `constant:<mm>` | Rückwärtsfahrt um `<mm>` zu kurz (Shift +`<mm>`) |
| `auto-retract:<s>:<h>` | Der Drucker zieht nach `<s>` s Leerlauf selbst exakt zurück. Kommt ein Auftrag früher, gilt Hypothese `<h>` |
| `offset:<mm>:<h>` | Hypothese `<h>` plus konstanter Shift |
| `.custom(name:reverse:)` | nur per API: beliebige Funktion von `ReverseContext` (Abreißweg, Modus beim FF, aktueller Modus, Pause, Transport, Modell) |

Der Transport (`cli`/`raw`/`poll`) wird an jede Hypothese weitergereicht. Die eingebauten Hypothesen werten ihn nicht aus.

### Weitere Annahmen

- `ESC G`/`ESC E` fahren zum **nächsten** Loch *vor* der aktuellen Position. Wenn ein zu tief gedrucktes Etikett über das nächste Loch hinausläuft, bleibt im Modell ein leeres Etikett übrig. Ob die Firmware das ebenso macht, ist nicht belegt.
- `ESC L` wird nur protokolliert. Der Vorschub richtet sich nach dem Loch, was zur Beobachtung passt, dass ein um 25 % längeres `ESC L` nichts änderte. Endlosmodus (`ESC L ≥ 0x8000`) erzeugt eine Warnung. Der Streifen wird trotzdem als Stanzetiketten gezeichnet.
- `ESC Q ≠ 0` erzeugt eine Warnung (nicht modelliert).
- Druckzeit, Statuszeitverlauf (die ~1,3 s `0x01` nach einem Auftrag) und die Dichte werden nicht modelliert.

## Benutzung

```sh
# Bytestrom erzeugen, ohne zu drucken
maclabel print "Regal 4" --roll 11354 --dry-run job.bin
# simulieren: Pausen pro Datei (fehlende = 0 s)
maclabel simulate job.bin job.bin --pause 600 --pause 2 \
    --hypothesis auto-retract:60:current-mode --gap 4.5 --tear 10 --out strip.png
```

Die Ausgabe ist eine Tabelle pro Etikett (Auftrag, Seite, physisches Etikett, Rand oben/unten, Inhalt, Shift, clipped) und ein PNG des Streifens. Protokollfehler beenden das Programm mit Exit-Code 65 und nennen den Offset.

Aus Swift:

```swift
let sim = LW450Simulator(model: MechanicalModel(gapMM: 4.5, headToTearBarMM: 10),
                         hypothesis: .autoRetractAfter(seconds: 60, otherwise: .inLinesOfCurrentMode))
try sim.run(bytes, pauseBefore: 600, transport: .raw, name: "A")
sim.result.labels            // Messungen
try StripRenderer.writePNG(sim.result.renderStrip(), to: url)
```

Abgleich mit den Beobachtungen: `swift test --filter observationsReport`. Mit `SIM_REPORT_PATH=/pfad/report.md` wird die Tabelle zusätzlich in eine Datei geschrieben. Der Test spielt `Tests/LabelSimulatorTests/Fixtures/observations.json` in Druckreihenfolge ab („long“ = 600 s, fehlende Bytes werden durch `test1.bin` pro Etikett ersetzt). Er gibt pro Hypothese eine Tabelle aus und rankt alle Hypothesen über Abstand ∈ {3, 4, 5, 6} × Abreißweg ∈ {8, 10, 12, 14, 16}. Die Beobachtungstexte werden so in Bedingungen übersetzt (`ObservationConstraint.parse`):

- „ok/gut/passt“ → |Shift| ≤ 0,5 mm und nicht clipped
- „abgeschnitten/cut“ → clipped. „nicht abgeschnitten/vollständig“ → nicht clipped
- „(deutlich) zu tief“ → Shift ≥ 1 mm und nicht clipped
- „nicht mittig/passt nicht“ → |Shift| > 0,5 mm
- Foto-Messungen „→ ~+x mm“ → Shift = x ± 0,7 mm. Gibt es eine Messung, ersetzt sie ein „passt“. „letzter Strich ~a mm vor Unterkante (Soll b mm)“ → Shift = b − a
- Einträge mit „keine Aussage/unklar/nicht beurteilbar/vermutlich“ werden ignoriert. „Label n …“ gilt nur für Etikett n.

## Kalibrierung mit dem Lineal

Alles lässt sich an **bereits gedruckten** oder **unbedruckten** Etiketten messen. Dafür ist kein neuer Druck nötig.

1. **Abstand (`--gap`):** Auf dem Trägerpapier den Abstand Hinterkante → Vorderkante des nächsten Etiketts messen. Genauer: 10 Etiketten von Vorderkante zu Vorderkante messen, durch 10 teilen und 31,75 abziehen.
2. **Sensorloch (`senseHoleOffsetMM`):** Lage des Lochs bzw. der Markierung auf dem Trägerpapier relativ zur Vorderkante des folgenden Etiketts messen. Ein Loch in der Lücke vor dem Etikett ergibt einen negativen Wert.
3. **Abreißweg (`--tear`):** Nach einem normalen Druck (Etikett steht an der Abreißkante) die Strecke von der Hinterkante des gedruckten Etiketts bis zur Abreißkante bzw. bis zur Vorderkante des nächsten Etiketts messen. Ohne Gehäuseöffnung lässt sich das nur grob abschätzen. Im Ranking der Beobachtungen schneidet ein Wert um 10 mm am besten ab.
4. **Ränder gedruckter Etiketten:** Rand oben und unten mit dem Lineal messen und mit Spalte „Oben/Unten“ der Simulation vergleichen. Messwert minus Soll ergibt den Shift. Diese Werte als `observed`-Text (`→ ~+x mm`) in `observations.json` eintragen und `observationsReport` erneut laufen lassen.
5. Ergeben alle Aufträge nach langer Pause denselben Shift, gehört er in `headToSensorMM`/`senseHoleOffsetMM` und nicht in die Hypothese.
