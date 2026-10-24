# Checkliste für MacLabel.app

Ziel: Die App am echten Gerät (LabelWriter 450, Rolle 11354 / S0722540 „Vielzweck 57 × 32 mm“) durchprüfen. Bisher hat die App nichts gedruckt; in der Entwicklung wurden an den Drucker nur Status- und Versionsabfragen geschickt.

**Jeder Druckschritt in dieser Liste wird von dir selbst ausgelöst.** Weder die Tests noch die Entwicklungswerkzeuge drucken. Verbrauche pro Schritt nur die angegebene Anzahl Etiketten.

Vorbereitung:

1. Drucker per USB anschließen, Rolle 11354 einlegen.
2. Im Repo-Verzeichnis `scripts/build-app.sh --install` ausführen. Die App liegt danach in `~/Applications/MacLabel.app`, und das Dienste-Menü ist aktualisiert.
3. `scripts/verify-app.sh` muss „all checks passed“ melden.
4. MacLabel aus `~/Applications` starten.

Wenn etwas nicht stimmt: Schritt, erwartetes und tatsächliches Ergebnis notieren (am besten mit Bildschirmfoto) und zurückmelden.

## 1. Fenster und Erstdruck mit Rolle 11354 (ein Etikett)

1. Das Fenster öffnet sich. In der Symbolleiste steht „LabelWriter 450 · bereit“.
2. Beim ersten Start fragt ein Fenster nach der eingelegten Rolle. „11354“ suchen und wählen.
3. Layout „Text“ (⌘1), Text „MacLabel App ↑“ eingeben. Die Vorschau zeigt das Etikett.
4. Von dir: auf „Drucken“ klicken (oder *Ablage › Drucken…*, ⌘P).

Prüfen:
- Das Etikett entspricht der Vorschau: Text entlang der 57-mm-Kante, Pfeil zur Oberkante, nicht gespiegelt, Ränder gleichmäßig.
- Die Druckleiste zeigt „1 Etikett gedruckt.“, danach wieder „bereit“.
- Der Zeilenschalter (Return) im Textfeld fügt nur einen Zeilenumbruch ein und druckt nicht.

## 2. Menüs und Kurzbefehle (kein Druck)

- *Etikett*-Menü: Text, Adresse, Barcode, QR-Code, Bild mit ⌘1 … ⌘5; das aktive Layout hat ein Häkchen.
- *Etikett › Rolle wählen…* (⌘L) öffnet die Rollensuche an der Rollen-Schaltfläche.
- *Darstellung › Inspektor einblenden/ausblenden* (⌃⌘I) und der Knopf „Mehr“ öffnen und schließen dieselbe Seitenleiste; „Mehr“ erscheint dabei hervorgehoben.
- *Ablage › Drucken…* ist ausgegraut, wenn kein Drucker angeschlossen ist oder das Einstellungsfenster vorne liegt.
- Text so lang machen, dass er nicht passt: ⌘P fragt „Trotzdem drucken?“. Hier „Abbrechen“ wählen.

## 2a. Fenster schließen und wieder öffnen (kein Druck)

- Hauptfenster schließen (⌘W): MacLabel läuft weiter, das Drucker-Symbol bleibt in der Menüleiste.
- Auf das MacLabel-Symbol im Dock klicken: Das Hauptfenster erscheint wieder, mit dem bisherigen Inhalt.
- Fenster erneut schließen, dann *Fenster › MacLabel* wählen: Das Fenster erscheint wieder, es entsteht kein zweites.

## 3. Menüleisten-Druck (ein Etikett)

1. Auf das Drucker-Symbol in der Menüleiste klicken. Das Feld zeigt Druckerstatus und Rolle 11354.
2. „Menüleiste“ eingeben.
3. Von dir: auf „Drucken“ klicken (⌘↩).

Prüfen: Ein Etikett „Menüleiste“, der Text im Hauptfenster bleibt unverändert.

Zusätzlich ohne Druck: Sehr langen Text eingeben. Der Knopf heißt dann „Text zu lang – im Fenster öffnen“ und öffnet das Hauptfenster mit diesem Text. *Bearbeiten › Widerrufen* (⌘Z) stellt das vorherige Etikett im Fenster wieder her.

## 4. Dienst aus TextEdit (ein Etikett)

Voraussetzung: Die App liegt in `~/Applications` (`scripts/build-app.sh --install`). Erscheint der Dienst nicht, einmal ab- und anmelden.

1. In TextEdit „Dienst-Test“ schreiben und markieren.
2. *TextEdit › Dienste › Mit MacLabel drucken* wählen.
3. MacLabel kommt nach vorne, das Fenster zeigt den Text als Text-Etikett. Es wird noch nichts gedruckt.
4. Von dir: auf „Drucken“ klicken.

Prüfen:
- Ein Etikett „Dienst-Test“.
- Auch bei vorher beendeter MacLabel-App kommt der Text an (Schritt 1–3 mit beendeter App wiederholen, ohne zu drucken).
- Auch bei geschlossenem Hauptfenster (App läuft, Fenster mit ⌘W geschlossen) öffnet der Dienst das Fenster mit dem Text (ohne zu drucken).
- Widerrufen in der richtigen Reihenfolge (ohne zu drucken): Im Fenster „Alt“ tippen, dann in TextEdit „Neu“ markieren und den Dienst aufrufen. Im MacLabel-Fenster: ⌘Z zeigt wieder „Alt“, ein zweites ⌘Z nimmt das Tippen zurück, ⇧⌘Z stellt „Alt“ wieder her.

## 5. Kurzbefehl „Etikett drucken“ (ein Etikett)

1. In der Kurzbefehle-App einen Kurzbefehl mit der Aktion „Etikett drucken“ (MacLabel) anlegen, Text „Kurzbefehl“, Anzahl 1, Rolle leer lassen.
2. Von dir: den Kurzbefehl ausführen.

Prüfen:
- Ein Etikett „Kurzbefehl“, Rückmeldung „1 Etikett gedruckt.“; das MacLabel-Fenster öffnet sich dafür nicht.
- Ohne Druck: Mit Rolle „Adresse“ (passt zu mehreren Größen) meldet der Kurzbefehl in Klartext, dass die Rolle nicht eindeutig ist. Mit sehr langem Text meldet er, dass der Text nicht passt.
- Die Aktion „Druckerstatus“ liefert „LabelWriter 450 · bereit“.
- Mit beendeter App (MacLabel vorher mit ⌘Q beenden): Von dir den Kurzbefehl „Etikett drucken“ noch einmal ausführen (ein Etikett). Erwartet: Es wird gedruckt. Notieren, ob dabei das MacLabel-Fenster aufgeht; das ist derzeit möglich (beim Start durch einen Kurzbefehl kann die App das Fenster nicht zuverlässig unterdrücken) und kein Fehler, aber bitte zurückmelden.

## 6. Adresse aus Kontakte (ein Etikett)

1. Layout „Adresse“ (⌘2), über den Kontakte-Knopf einen Kontakt mit Postadresse wählen. Bei mehreren Adressen die gewünschte anklicken.
2. Vorschau prüfen: Name, Firma (falls vorhanden), Straße, PLZ und Ort, linksbündig.
3. Von dir: drucken.

Prüfen: Das Etikett entspricht der Vorschau. Falls macOS nach Kontakte-Zugriff fragt, erscheint der Hinweistext auf Deutsch.

## 7. CSV-Serie (drei Etiketten)

1. Eine CSV-Datei mit Kopfzeile `name;ort` und drei Zeilen anlegen.
2. Text-Layout, Text `{name}` Zeilenumbruch `{ort}`, im Inspektor („Mehr“) die CSV-Datei laden.
3. Mit den Pfeilen unter der Vorschau durch die drei Etiketten blättern.
4. Von dir: drucken.

Prüfen: Drei Etiketten in der Reihenfolge der Datei, die Druckleiste zählt „Drucke Etikett 1 von 3 …“ usw. hoch.

## 8. Abbrechen mitten im Druck (höchstens drei Etiketten)

1. Anzahl 3, Text „Abbruch“.
2. Von dir: drucken und nach dem ersten Etikett „Abbrechen“ klicken.

Prüfen: Die Leiste meldet „Abgebrochen nach N von 3 Etiketten. Ggf. Vorschubtaste drücken, um ein angefangenes Etikett auszugeben.“ Ein halb gedrucktes Etikett mit der Vorschubtaste ausgeben. Der nächste Druck beginnt wieder sauber am Etikettenanfang.

## 9. CLI über Symlink (kein Druck)

1. *MacLabel › Kommandozeilenwerkzeug installieren…* öffnet die Einstellungen mit dem Befehl. Den Befehl kopieren und im Terminal ausführen (`/usr/local/bin` fragt nach dem Administratorpasswort).
2. In einem neuen Terminalfenster:

```
maclabel status
maclabel rolls search 32x57
```

Prüfen: `status` zeigt den LabelWriter 450 als bereit, `rolls search` listet 11354. App und CLI merken sich die Rolle getrennt; das ist so gewollt. Auch die Druckpause teilen sie nicht: Nach einem Druck aus der App etwa 10 s warten, bevor du mit dem Kommandozeilenwerkzeug druckst (und umgekehrt).
