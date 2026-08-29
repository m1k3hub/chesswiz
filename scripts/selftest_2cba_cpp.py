#!/usr/bin/env python3
"""Cross-validate the C++ 2cbh annotation walker against the Python walker.

Builds a tiny C++ test binary (2cba_selftest) that parses .2cba records
for the sampled games via the production parser and dumps items in JSON;
then compares with the Python strict walker result.
"""
import sys, os, re, json, subprocess, struct

BASE = "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pgn_ground_truth import parse_items_at

# ------------------------------------------------------------------
# 1. generate the expected items file (python walker) for sampled games
# ------------------------------------------------------------------
CBH = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
CBA = open(os.path.join(BASE, ROOT + ".2cba"), "rb").read()
recordSize = int.from_bytes(CBH[0x0a:0x0c], "little")
N = len(CBH) // recordSize - 256

annot = []
for k in range(0, N, 32):   # ~27k sampled annotated games... too many; use 256
    cbaOff = int.from_bytes(CBH[(256 + k) * recordSize + 0x10:
                                (256 + k) * recordSize + 0x14], "little")
    ds = int.from_bytes(CBA[cbaOff + 8:cbaOff + 12], "little")
    if ds > 8:
        annot.append((k, cbaOff, ds))
step = max(1, len(annot) // 256)
sample = annot[::step][:256]

expected = {}
for k, cbaOff, ds in sample:
    items, complete = parse_items_at(CBA, cbaOff, ds)
    if not items:
        continue
    expected[k] = dict(complete=complete,
                       items=[dict(X=it["X"], ch=it["ch"], len=it["len"], text=it["text"])
                              for it in items])
print(f"{len(expected)} sampled records with items", flush=True)

# ------------------------------------------------------------------
# 2. write offsets+dataset to /tmp for the C++ helper and compile it
# ------------------------------------------------------------------
ids_txt = "\n".join(f"{k} {cbaOff} {ds}" for k, cbaOff, ds in sample)
open("/tmp/2cba_selftest_ids.txt", "w").write(ids_txt)

cpp = r"""
// 2cba_selftest.cpp -- parse sampled .2cba records with the production
// parser and emit the items for cross-validation against Python.
#include "2cbh_annotations.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>

static std::string g_cbag, g_cba;
static bool loadFile(char const* n, std::string& d) {
   FILE* f = fopen(n, "rb");
   if (!f) return false;
   fseek(f, 0, SEEK_END);
   long sz = ftell(f);
   fseek(f, 0, SEEK_SET);
   d.resize(sz);
   if (sz) fread(&d[0], 1, sz, f);
   fclose(f);
   return true;
}

int main(int argc, char** argv)
{
   if (argc < 4) { ::fprintf(stderr, "usage: 2cba_selftest <prefix> <ids> <out>\n"); return 1; }
   std::string prefix(argv[1]);
   if (!loadFile((prefix + ".2cbh").c_str(), g_cbag)) { ::fprintf(stderr, "no 2cbh\n"); return 1; }
   if (!loadFile((prefix + ".2cba").c_str(), g_cba)) { ::fprintf(stderr, "no 2cba\n"); return 1; }
   FILE* f = fopen(argv[2], "r");
   FILE* out = ::fopen(argv[3], "w");
   unsigned long k;
   unsigned long cbaOff;
   unsigned long ds;
   while (::fscanf(f, "%lu %lu %lu", &k, &cbaOff, &ds) == 3)
   {
      unsigned char const* arec = (unsigned char const*) g_cba.c_str() + cbaOff;
      mstl::vector<db::cb2::CbaItem> items;
      bool complete = db::cb2::parseCbaItems(arec + 0x1a, uint32_t(ds), items);
      ::fprintf(out, "G %lu %d %zu\n", k, complete ? 1 : 0, items.size());
      for (size_t i = 0; i < items.size(); ++i)
      {
         // replace newlines to keep the line format
         mstl::string t = items[i].text;
         ::fprintf(out, "I %u %u %u\n", items[i].position, items[i].nag, unsigned(t.size()));
         ::fprintf(out, "T ");
         for (unsigned j = 0; j < t.size(); ++j)
         {
            if (t[j] == '\n') ::fprintf(out, "\\n");
            else if (t[j] == '\r') ::fprintf(out, "\\r");
            else ::fputc(t[j], out);
         }
         ::fprintf(out, "\n");
      }
   }
   ::fclose(f);
   ::fclose(out);
   return 0;
}
"""
cpp_path = os.path.join(HERE, "..", "src", "db", "2cbh", "2cba_selftest.cpp")
open(cpp_path, "w").write(cpp)

print("compiling selftest...", flush=True)
cmd = ("g++ -O1 -o /tmp/2cba_selftest "
       "src/db/2cbh/2cba_selftest.cpp src/db/2cbh/2cbh_annotations.cpp "
       "src/db/2cbh/2cbh_move16.cpp src/db/2cbh/cb2_move16_table.cpp "
       "-Isrc/db -Isrc -Isrc/mstl src/mstl/libmstl.a")
rc = os.system(cmd)
print("compile rc:", rc, flush=True)
sup_bin = os.path.join(BASE, ROOT)
cmd2 = f"/tmp/2cba_selftest {sup_bin} /tmp/2cba_selftest_ids.txt /tmp/2cba_selftest_out.txt"
rc = os.system(cmd2)
print("run rc:", rc, flush=True)
if not os.path.exists("/tmp/2cba_selftest_out.txt"):
    print("selftest binary missing; inspect build")
    sys.exit(1)

# ------------------------------------------------------------------
# 3. parse the C++ output and compare
# ------------------------------------------------------------------
got = {}
cur = None
for line in open("/tmp/2cba_selftest_out.txt"):
    if line.startswith("G "):
        _, k, complete, n = line.split()
        cur = dict(complete=complete == "1", items=[])
        if int(n) > 0:
            got[int(k)] = cur
    elif line.startswith("I "):
        _, pos, nag, ln = line.split()
        cur["items"].append(dict(X=int(pos), ch=int(nag), len=int(ln), text=""))
    elif line.startswith("T "):
        # decode the escaped text
        raw = line[2:].rstrip("\n")
        txt = raw.replace("\\n", "\n").replace("\\r", "\r")
        # rebuild string list association: the T belongs to the LAST item
        if cur and cur["items"]:
            # text may contain embedded 'T ' lines? handle multi-text by joining
            item = cur["items"][-1]
            if item["text"]:
                item["text"] += "\n" + raw
            else:
                item["text"] = raw

match = 0
diffs = []
for k, exp in expected.items():
    g = got.get(k)
    if g is None:
        diffs.append((k, "missing-in-cxx"))
        continue
    if g["complete"] != exp["complete"]:
        diffs.append((k, f"complete {g['complete']} vs {exp['complete']}"))
        continue
    if len(g["items"]) != len(exp["items"]):
        diffs.append((k, f"nitems {len(g['items'])} vs {len(exp['items'])}"))
        continue
    for a, b in zip(g["items"], exp["items"]):
        if a["X"] != b["X"] or a["ch"] != b["ch"]:
            diffs.append((k, f"item {a['X']}/{a['ch']} vs {b['X']}/{b['ch']}"))
        elif a["text"] != b["text"]:
            diffs.append((k, f"text {a['text'][:30]!r} vs {b['text'][:30]!r}"))
            break
    else:
        match += 1

print(f"games compared: {len(expected)}, exact match: {match}, diffs: {len(diffs)}")
for d in diffs[:15]:
    print("  ", d)