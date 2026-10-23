# MacLabel

Eine schnelle, native macOS-App für DYMO-LabelWriter-Etikettendrucker – als moderne Alternative zu DYMO Connect.

> **Status:** frühe Entwicklung. Noch nicht für den Alltag gedacht.

**Ziel:** In unter 10 Sekunden das passende Etikett drucken – ohne Einstellungen zu suchen.

- Rolle per Packungsnummer finden (`S0722540`, `11354`, `99012`, „32x57“)
- Vorschau = exakt das, was gedruckt wird
- Direkter USB-Druck ohne DYMO-Treiber, echter Druckerstatus
- Menüleiste, macOS-Dienst, Kurzbefehle und CLI (`maclabel`)

## Status

Kern (`LabelKit`) und CLI sind fertig. Der Testdruck am Gerät steht noch aus (siehe [`docs/first-print-checklist.md`](docs/first-print-checklist.md)). Die App folgt.

## Datenschutz

MacLabel ist Open Source (MIT), gibt keine Daten an Dritte weiter und macht keine Netzwerkzugriffe. Gedruckt wird direkt per USB.

## Unterstützte Drucker

- v1: LabelWriter 400, 400 Turbo, Twin Turbo, 450, 450 Turbo, 450 Twin Turbo, 450 DUO (Etikettendrucker) und 4XL.
- Erkannt, aber noch nicht unterstützt: 550-Serie, SE450, 300er-Serie.

## Installation aus dem Quellcode

```
swift build -c release
```

Das Programm liegt danach unter `.build/release/maclabel`.

## CLI-Beispiele

```
maclabel status
maclabel rolls search 32x57
maclabel print --roll 11354 "Hallo\nWelt"
maclabel print --roll 11354 --dry-run preview.png "Vorschau"
maclabel print --roll 11354 --layout qr --caption "Wiki" "https://example.com"
maclabel print --roll 11354 --layout barcode --symbology ean13 "4006381333931"
maclabel print --roll 11354 --copies 2 --counter 1 "Box {n}"
maclabel print --roll 11354 --csv adressen.csv "{name}\n{ort}"
```

Vor dem echten Druck hilft `--dry-run` (PNG-Vorschau oder `.bin` mit den Druckerbytes).

## Rollen-Datenbank

Die Rollen-Datenbank enthält abgeleitete Fakten (Artikelnummern, Maße, Versätze). Sie wird mit `tools/import-dymo-media` erzeugt; es liegen keine DYMO-Dateien im Repository.

Design: [`docs/superpowers/specs/2026-10-23-maclabel-design.md`](docs/superpowers/specs/2026-10-23-maclabel-design.md)

MacLabel ist ein unabhängiges Projekt und steht in keiner Verbindung zu DYMO oder Newell Brands. „DYMO“ und „LabelWriter“ sind Marken ihrer jeweiligen Inhaber.

Lizenz: MIT
