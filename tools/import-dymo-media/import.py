#!/usr/bin/env python3
"""Generate media.json (roll facts only) from a locally installed DYMO Connect.

Usage: python3 -I tools/import-dymo-media/import.py [--dll PATH] --out Sources/LabelMedia/Resources/media.json

The DYMO resources are read from the DLL and processed in memory only; nothing
from DYMO is written to disk except the derived facts in media.json.
"""
import argparse
import hashlib
import json
import math
import os
import re
import struct
import sys
import xml.etree.ElementTree as ET

DEFAULT_DLL = "/Applications/DYMO Connect.app/Contents/MonoBundle/DYMO.LabelAPI.dll"
KNOWN_SHA = {"Papers": "8e3baea1", "SKUs": "b617313d"}
ARTICLE_RE = re.compile(r"^\d{5}|^S\d{7}")
TWIPS_PER_DOT = 4.8


def rnd(x):
    return int(math.floor(x + 0.5))


def dots(twips):
    return rnd(float(twips) / TWIPS_PER_DOT)


def mm(twips):
    return round(float(twips) * 25.4 / 1440, 1)


def resources_blob(data):
    """Return the managed-resources region of a .NET PE file."""
    if data[:2] != b"MZ":
        raise ValueError("not a PE file")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("bad PE signature")
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    optsize = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    dd = opt + (112 if magic == 0x20B else 96)
    cli_rva = struct.unpack_from("<I", data, dd + 14 * 8)[0]
    sec = opt + optsize
    sections = []
    for i in range(nsec):
        o = sec + 40 * i
        vsize, va, rawsize, rawptr = struct.unpack_from("<IIII", data, o + 8)
        sections.append((va, max(vsize, rawsize), rawptr))

    def rva2off(rva):
        for va, size, raw in sections:
            if va <= rva < va + size:
                return rva - va + raw
        raise ValueError("RVA not in any section")

    cli = rva2off(cli_rva)
    res_rva, res_size = struct.unpack_from("<II", data, cli + 24)
    start = rva2off(res_rva)
    return data[start:start + res_size]


def find_resource(blob, root, label):
    tag = b"<" + root.encode() + b">"
    i = blob.find(tag)
    if i < 0:
        raise ValueError("resource %s not found" % label)
    x = blob.rfind(b"<?xml", 0, i)
    if x < 0:
        raise ValueError("no XML declaration before %s" % label)
    if blob[x - 3:x] == b"\xef\xbb\xbf":
        x -= 3
    length = struct.unpack_from("<I", blob, x - 4)[0]
    body = blob[x:x + length]
    if not body.rstrip().endswith(b"</" + root.encode() + b">"):
        raise ValueError("resource %s: length prefix does not match end tag" % label)
    sha = hashlib.sha256(body).hexdigest()
    if not sha.startswith(KNOWN_SHA[label]):
        print("warning: %s resource hash %s differs from the known one (other DYMO version?)"
              % (label, sha[:8]), file=sys.stderr)
    return body


def fnum(el, attr):
    return float(el.get(attr))


def parse_papers(xml):
    root = ET.fromstring(xml.lstrip(b"\xef\xbb\xbf"))
    group = None
    for g in root.iter("PaperGroup"):
        if g.get("Id") == "LabelWriter400":
            group = g
    if group is None:
        raise ValueError("PaperGroup LabelWriter400 not found")
    papers = []
    for el in group:
        name = el.get("Name") or ""
        if el.tag == "Paper":
            size = el.find("Size")
            ps = el.find("PrintableSize")
            po = el.find("PrintableOrigin")
            off = el.find("Offset")
            papers.append(dict(
                name=name, continuous=False,
                w=fnum(size, "Width"), h=fnum(size, "Height"),
                pw=fnum(ps, "Width"), ph=fnum(ps, "Height"),
                ox=fnum(po, "X"), oy=fnum(po, "Y"),
                offx=fnum(off, "X") if off is not None else 0.0))
        elif el.tag == "ContinuousPaper":
            w = float(el.findtext("Width"))
            pw = float(el.findtext("PrintableWidth"))
            off = el.find("Offset")
            papers.append(dict(
                name=name, continuous=True, w=w, h=None, pw=pw, ph=None,
                ox=(w - pw) / 2, oy=0.0,
                offx=fnum(off, "X") if off is not None else 0.0))
    return papers


def parse_skus(xml):
    root = ET.fromstring(xml.lstrip(b"\xef\xbb\xbf"))
    out = []
    for el in root:
        if el.tag not in ("DieCutSKU", "ContSKU"):
            continue
        out.append(dict(
            sku=el.get("SKU"), paper=el.get("PaperName"), cont=el.tag == "ContSKU",
            material=(el.get("Material") or "").lower(), region=el.get("Region"),
            corner=el.get("CornerRadius")))
    return out


def sku_key(s):
    return (0, s) if re.fullmatch(r"\d{5}", s) else (1, s)


def build(papers, skus, names):
    by_name = {p["name"]: p for p in papers}
    skus_for = {}
    for s in skus:
        if s["paper"] in by_name:
            skus_for.setdefault(s["paper"], []).append(s)
    groups = {}
    for p in papers:
        n = p["name"]
        if "offset" in n.lower():
            continue
        if not (n in skus_for or ARTICLE_RE.match(n)):
            continue
        mats = [x["material"] for x in skus_for.get(n, []) if x["material"]]
        p["material"] = "standard" if (not mats or "standard" in mats) else mats[0]
        key = tuple(p[k] for k in ("w", "h", "pw", "ph", "ox", "oy", "material"))
        groups.setdefault(key, []).append(p)

    # SKU references are authoritative: an article number belongs to the paper
    # a SKU points to. Name-derived numbers only fill in what is still free.
    claimed = {}
    for key, ps in groups.items():
        for q in ps:
            for s in skus_for.get(q["name"], []):
                claimed.setdefault(s["sku"], key)
    order = sorted(groups, key=lambda k: not any(q["name"] in skus_for for q in groups[k]))
    group_ids = {}
    for key in order:
        ids = set(s["sku"] for q in groups[key] for s in skus_for.get(q["name"], []))
        for q in groups[key]:
            if ARTICLE_RE.match(q["name"]):
                num = re.match(r"\S+", q["name"]).group(0)
                if claimed.setdefault(num, key) == key:
                    ids.add(num)
                else:
                    print("note: article number %s of paper '%s' already belongs to another roll" % (num, q["name"]), file=sys.stderr)
        group_ids[key] = ids

    rolls = []
    for key, ps in groups.items():
        ids = group_ids[key]
        if not ids:
            print("note: dropped paper(s) without a usable article number: %s" % [q["name"] for q in ps], file=sys.stderr)
            continue
        p = ps[0]
        ss = [s for q in ps for s in skus_for.get(q["name"], [])]
        skulist = sorted(ids, key=sku_key)
        cont = p["continuous"] or any(s["cont"] for s in ss) or any("continuous" in q["name"].lower() for q in ps)
        across_dots = dots(p["w"])
        offset_dots = dots(min(q["offx"] for q in ps))
        origin_across = dots(p["ox"])
        width = dots(p["pw"])
        corner = next((s["corner"] for s in ss if s["corner"]), None)
        roll = {
            "id": skulist[0],
            "skus": skulist,
            "kind": "continuous" if cont else "dieCut",
            "acrossMM": mm(p["w"]),
            "feedMM": None if cont else mm(p["h"]),
            "acrossDots": across_dots,
            "feedDots": None if cont else dots(p["h"]),
            "printable": {
                "originAcrossDots": origin_across,
                "originFeedDots": dots(p["oy"]),
                "widthDots": width,
                "lengthDots": None if cont else dots(p["ph"]),
            },
            "offsetDots": offset_dots,
            "cornerRadiusMM": mm(corner) if corner else 0,
            "material": p["material"],
            "regions": sorted(set(s["region"] for s in ss if s["region"])),
            "minHeadDots": 672 if width <= 672 else 1248,
        }
        rolls.append(roll)

    rolls.sort(key=lambda r: r["id"])
    seen = {}
    for r in rolls:
        for s in r["skus"]:
            if s in seen:
                print("warning: article number %s appears in rolls %s and %s" % (s, seen[s], r["id"]), file=sys.stderr)
            seen[s] = r["id"]
    used = set()
    for r in rolls:
        hit = next((k for k in [r["id"]] + r["skus"] if k in names), None)
        if hit:
            used.add(hit)
            r["nameDE"], r["nameEN"] = names[hit]["de"], names[hit]["en"]
        else:
            a, f = r["acrossMM"], r["feedMM"]
            if r["kind"] == "continuous":
                r["nameDE"] = "Endlos %d mm" % rnd(a)
                r["nameEN"] = "Continuous %d mm" % rnd(a)
            else:
                lo, hi = sorted((rnd(a), rnd(f)))
                r["nameDE"] = "Etikett %d × %d mm" % (hi, lo)
                r["nameEN"] = "Label %d × %d mm" % (hi, lo)
        for k in r["skus"]:
            if k in names:
                used.add(k)
    for k in names:
        if k not in used:
            print("warning: names.json key %s matches no roll" % k, file=sys.stderr)
    return rolls


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dll", default=DEFAULT_DLL)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    if not os.path.exists(args.dll):
        print("DYMO Connect not found at %s.\nInstall DYMO Connect or pass --dll PATH to DYMO.LabelAPI.dll." % args.dll,
              file=sys.stderr)
        return 2
    with open(args.dll, "rb") as f:
        data = f.read()
    blob = resources_blob(data)
    papers = parse_papers(find_resource(blob, "Papers", "Papers"))
    skus = parse_skus(find_resource(blob, "SKUs", "SKUs"))
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "names.json"), encoding="utf-8") as f:
        names = json.load(f)
    rolls = build(papers, skus, names)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"version": 1, "rolls": rolls}, f, sort_keys=True, indent=1, ensure_ascii=False)
        f.write("\n")
    print("%d rolls written" % len(rolls))
    return 0


if __name__ == "__main__":
    sys.exit(main())
