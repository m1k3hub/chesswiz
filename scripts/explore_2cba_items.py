#!/usr/bin/env python3
"""Parse .2cba records: framing, item TLVs, type histogram, hex dumps."""
import struct, sys, os

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
NGAME = int(sys.argv[2]) if len(sys.argv) > 2 else 40

cbh = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
cba = open(os.path.join(BASE, ROOT + ".2cba"), "rb").read()
recordSize = struct.unpack_from("<H", cbh, 0x0a)[0]
nGames = len(cbh) // recordSize - 256

def game_cba_off(k):
    return struct.unpack_from("<I", cbh, (256 + k) * recordSize + 0x10)[0]

def parse_record(off):
    magic = struct.unpack_from("<Q", cba, off)[0]
    assert magic == 0x1122334455667788, f"bad magic @{off:#x}"
    dataSize, extraSize = struct.unpack_from("<II", cba, off + 8)
    sub1 = struct.unpack_from("<I", cba, off + 0x10)[0]
    typ = struct.unpack_from("<H", cba, off + 0x18)[0]
    data = cba[off + 0x1a : off + 0x1a + dataSize]
    extra = cba[off + 0x1a + dataSize : off + 0x1a + dataSize + extraSize]
    return dict(magic=magic, dataSize=dataSize, extraSize=extraSize, sub1=sub1,
                typ=typ, data=data, extra=extra,
                raw=cba[off : off + 16 + dataSize + extraSize + 18])

def walk_items(data):
    """Yield (rel_pos, raw_bytes, parsed_dict) for repeating items."""
    items = []
    p = 0
    n = len(data)
    while p < n:
        if data[p:p+4] == b"\xff\xff\xff\x7f" or data[p:p+2] == b"\xff\xff":
            items.append((p, data[p:], {"kind": "END"}))
            break
        # try the documented text item: [u16 type][u32 len][payload]
        if p + 2 <= n:
            itype = struct.unpack_from("<H", data, p)[0]
            if itype == 7 and p + 6 <= n:
                ln = struct.unpack_from("<I", data, p + 2)[0]
                if p + 6 + ln <= n and ln < 4096:
                    payload = data[p+6:p+6+ln]
                    # try decode text
                    try:
                        txt = payload.decode("utf-8")
                        is_text = all(31 < ord(ch) or ch in "\r\n\t" for ch in txt)
                    except UnicodeDecodeError:
                        is_text = False
                    items.append((p, data[p:p+6+ln],
                                  {"kind": "text" if is_text else "type7raw",
                                   "len": ln, "payload": payload, "text": txt if is_text else None}))
                    p += 6 + ln
                    continue
        items.append((p, data[p:p+2], {"kind": "unknown16", "val": struct.unpack_from("<H", data, p)[0]}))
        p += 2
    return items

# type histogram over ALL games would be slow; sample: every 16th game
hist = {}
minspan = {}
samples_checked = 0
text_games = []
K = 16
for k in range(0, nGames, K):
    off = game_cba_off(k)
    r = parse_record(off)
    samples_checked += 1
    hist[("rec_type", r["typ"])] = hist.get(("rec_type", r["typ"]), 0) + 1
    spans = 16 + r["dataSize"] + r["extraSize"] + 18
    hist[("span_cls", "min" if spans == 232 else "bigger")] = hist.get(("span_cls", "bigger" if spans > 232 else "min"), 0) + 1
    if spans > 232 and len(text_games) < NGAME:
        text_games.append((k, off))

kind_hist = {}
for k, off in text_games[:40]:
    r = parse_record(off)
    d = r["data"]
    # skip data[0:2]? docs show record data starting with... let's see full dump
    texts = 0
    for ipos, raw, it in walk_items(d):
        kind_hist[it["kind"]] = kind_hist.get(it["kind"], 0) + 1
        if it["kind"] in ("text",):
            texts += 1

print("sample size:", samples_checked)
for key in sorted(hist, key=str):
    print(f"  {key}: {hist[key]}")
print("item-kind histogram (first 40 games with content):", kind_hist)

# full hex dumps of 3 interesting records
shown = 0
for k, off in text_games:
    r = parse_record(off)
    if r["dataSize"] > 100 and shown < 3:
        shown += 1
        print(f"\n===== game {k} cbgoff={off:#x} dataSize={r['dataSize']} extraSize={r['extraSize']} type={r['typ']} sub1={r['sub1']:#x}")
        d = r["data"]
        for base in range(0, min(len(d), 512), 16):
            chunk = d[base:base+16]
            hx = chunk.hex(" ")
            asc = "".join(chr(c) if 32 <= c < 127 else "." for c in chunk)
            print(f"  +{base:04x}: {hx:<47}  |{asc}|")
        print("  ...items:")
        for ipos, raw, it in walk_items(d):
            if it["kind"] == "text":
                print(f"    @{ipos:#x} TEXT len={it['len']}: {it['text'][:60]!r}")
            elif it["kind"] == "unknown16":
                pass
        trailer = r["raw"][-18:]
        print(f"  trailer: {trailer.hex(' ')}")