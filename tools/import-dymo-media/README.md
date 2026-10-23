# import-dymo-media

Regenerates `Sources/LabelMedia/Resources/media.json` from a locally installed DYMO Connect.

    python3 -I tools/import-dymo-media/import.py --out Sources/LabelMedia/Resources/media.json
    # optional: --dll "/path/to/DYMO.LabelAPI.dll"   (exit code 2 if the DLL is missing)

- Reads the embedded `Papers.xml` / `SKUs.xml` straight from the PE file, in memory only. Nothing from DYMO is written to disk or committed; `media.json` contains facts only (article numbers, dimensions, material, region).
- Only paper group `LabelWriter400`; "offset" papers are skipped; papers with identical geometry are merged into one roll.
- An article number belongs to exactly one roll: SKU references win over numbers in paper names. Conflicts are printed as `note:` lines.
- Printable origin of continuous rolls is assumed centered (the source has no origin for them).
- Roll names come from `names.json` (own wording; key = roll id or any of its SKUs), otherwise generated from the size.
- A hash mismatch of the extracted resources prints a warning (other DYMO version), it is not an error.
