#!/usr/bin/env python3
"""Usage: wizard-gen.py <dir> (preview SVGs) | wizard-gen.py Wizard tcl/pieces/wizard.tcl
Generate the 'Wizard Staunton' piece set: lathe-turned silhouettes in a 45x45 box."""
import sys, os
CX = 22.5
OUT = os.path.dirname(os.path.abspath(__file__))

def f(v): return f"{v:.2f}".rstrip("0").rstrip(".")

def lathe(start, segs):
    """start=(dx,y) on the right side at the bottom; segs: ('L',(dx,y)) or ('C',c1,c2,p) in dx,y.
    Returns a closed symmetric path: right side bottom->top, then mirrored left side top->bottom."""
    pts = [start]
    d = [f"M {f(CX+start[0])},{f(start[1])}"]
    for s in segs:
        if s[0] == 'L':
            d.append(f"L {f(CX+s[1][0])},{f(s[1][1])}")
        else:
            _, c1, c2, p = s
            d.append(f"C {f(CX+c1[0])},{f(c1[1])} {f(CX+c2[0])},{f(c2[1])} {f(CX+p[0])},{f(p[1])}")
        pts.append(s[-1])
    # mirror back down
    prev = segs[-1][-1]
    for i in range(len(segs) - 1, -1, -1):
        s = segs[i]
        back = pts[i]
        if s[0] == 'L':
            d.append(f"L {f(CX-back[0])},{f(back[1])}")
        else:
            _, c1, c2, p = s
            d.append(f"C {f(CX-c2[0])},{f(c2[1])} {f(CX-c1[0])},{f(c1[1])} {f(CX-back[0])},{f(back[1])}")
    d.append("Z")
    return " ".join(d)

def hline(y, w, sag=0.6):
    return f"M {f(CX-w)},{f(y)} C {f(CX-w/2)},{f(y-sag)} {f(CX+w/2)},{f(y-sag)} {f(CX+w)},{f(y)}"

def circle(cx, cy, r):
    return f"M {f(cx+r)},{f(cy)} A {f(r)},{f(r)} 0 1 1 {f(cx-r)},{f(cy)} A {f(r)},{f(r)} 0 1 1 {f(cx+r)},{f(cy)} Z"

# A common Staunton plinth: wide base, bead, cove up to the stem.
def plinth(w=12.5, y0=39.5):
    return [
        ('L', (w, y0 - 1.6)),                                  # base edge
        ('C', (w, y0 - 2.6), (w - 1.2, y0 - 3.0), (w - 2.0, y0 - 3.0)),   # rounded top of base
        ('L', (w - 2.4, y0 - 3.0)),
        ('C', (w - 1.4, y0 - 3.4), (w - 1.4, y0 - 4.8), (w - 2.6, y0 - 5.0)),  # bead
    ]

def pawn():
    segs = plinth(11.0) + [
        ('C', (5.6, 33.4), (3.4, 31.5), (3.0, 27.6)),          # cove up to stem
        ('L', (3.0, 26.4)),
        ('C', (5.6, 26.3), (6.0, 25.2), (4.0, 24.6)),          # collar disc
        ('C', (3.2, 24.4), (3.0, 24.4), (2.6, 24.1)),
    ]
    body = lathe((11.0, 39.5), segs)
    head = circle(CX, 19.0, 5.2)
    details = [hline(36.5, 8.6, 0.4), hline(26.4, 3.0, 0.2)]
    return dict(bbox="11.5,13.8,33.5,39.5", fills=[body, head], details=details)

def rook():
    segs = plinth(12.5) + [
        ('C', (8.0, 33.0), (7.6, 31.5), (7.4, 30.0)),
        ('L', (7.6, 30.0)),
        ('C', (8.6, 29.6), (8.6, 28.6), (7.6, 28.4)),          # lower ring
        ('L', (7.0, 16.6)),                                    # tapering tower
        ('C', (9.2, 16.2), (9.8, 15.0), (9.8, 13.6)),          # flared top
        ('L', (9.8, 9.2)),
        ('L', (6.6, 9.2)), ('L', (6.6, 11.6)),                 # crenel right
        ('L', (1.6, 11.6)), ('L', (1.6, 9.2)), ('L', (0.0, 9.2)),
    ]
    body = lathe((12.5, 39.5), segs)
    details = [hline(36.5, 10.1, 0.4), hline(16.8, 7.1, 0.0), hline(28.4, 7.6, 0.0)]
    return dict(bbox="10,9.2,35,39.5", fills=[body], details=details)

def bishop():
    segs = plinth(12.0) + [
        ('C', (6.2, 33.2), (3.6, 30.8), (3.2, 26.6)),
        ('L', (3.2, 25.6)),
        ('C', (7.0, 25.4), (7.4, 24.0), (5.0, 23.4)),          # collar
        ('C', (4.2, 23.2), (3.8, 23.0), (3.6, 22.8)),
        ('C', (8.0, 19.6), (7.6, 14.6), (0.0, 9.6)),           # mitre (teardrop)
    ]
    body = lathe((12.0, 39.5), segs)
    finial = circle(CX, 7.4, 2.1)
    slit = f"M {f(CX+1.0)},{f(14.2)} L {f(CX+4.2)},{f(18.6)}"
    details = [hline(36.5, 9.6, 0.4), hline(25.6, 3.2, 0.2), slit]
    return dict(bbox="10.5,5.3,34.5,39.5", fills=[body, finial], details=details)

def queen():
    segs = plinth(13.0) + [
        ('C', (6.6, 33.4), (4.0, 30.0), (3.8, 25.4)),          # tall stem
        ('L', (3.8, 24.4)),
        ('C', (6.8, 24.2), (7.0, 22.8), (5.0, 22.2)),          # collar
        ('C', (4.0, 21.9), (3.7, 21.5), (3.9, 20.8)),
        ('C', (6.4, 18.0), (8.0, 15.6), (8.6, 12.0)),          # cup flaring to coronet
        ('L', (6.2, 14.4)), ('L', (5.6, 11.6)),                # coronet points
        ('L', (2.6, 13.6)),
        ('C', (1.8, 12.4), (1.2, 11.6), (0.0, 11.4)),
    ]
    body = lathe((13.0, 39.5), segs)
    balls = [circle(CX+8.6, 11.0, 1.1), circle(CX-8.6, 11.0, 1.1), circle(CX+5.6, 10.4, 1.0),
             circle(CX-5.6, 10.4, 1.0), circle(CX, 9.4, 1.7)]
    details = [hline(36.5, 10.6, 0.4), hline(24.4, 3.8, 0.2), hline(16.6, 6.4, 0.5)]
    return dict(bbox="8,7.7,37,39.5", fills=[body] + balls, details=details)

def king():
    segs = plinth(13.0) + [
        ('C', (6.6, 33.4), (4.0, 30.0), (3.8, 25.4)),
        ('L', (3.8, 24.4)),
        ('C', (6.8, 24.2), (7.0, 22.8), (5.0, 22.2)),
        ('C', (4.0, 21.9), (3.7, 21.5), (3.9, 20.8)),
        ('C', (6.4, 18.2), (7.6, 16.0), (7.8, 13.6)),          # cup
        ('C', (6.4, 13.0), (3.2, 12.4), (2.0, 12.4)),          # domed crown
        ('C', (1.4, 11.6), (1.2, 11.0), (1.2, 10.6)),
        ('L', (0.0, 10.6)),
    ]
    body = lathe((13.0, 39.5), segs)
    cross = (f"M {f(CX-1.1)},{f(10.8)} L {f(CX-1.1)},{f(7.9)} L {f(CX-3.4)},{f(7.9)} L {f(CX-3.4)},{f(5.7)} "
             f"L {f(CX-1.1)},{f(5.7)} L {f(CX-1.1)},{f(3.4)} L {f(CX+1.1)},{f(3.4)} L {f(CX+1.1)},{f(5.7)} "
             f"L {f(CX+3.4)},{f(5.7)} L {f(CX+3.4)},{f(7.9)} L {f(CX+1.1)},{f(7.9)} L {f(CX+1.1)},{f(10.8)} Z")
    details = [hline(36.5, 10.6, 0.4), hline(24.4, 3.8, 0.2), hline(16.6, 6.6, 0.5), hline(13.4, 7.4, 0.3)]
    return dict(bbox="9.5,3.4,35.5,39.5", fills=[body, cross], details=details)

def knight():
    # Base: same plinth as the other pieces, then a horse head facing left.
    base = lathe((12.5, 39.5), plinth(12.5) + [('C', (9.0, 33.6), (8.6, 33.0), (8.6, 32.6)), ('L', (0.0, 32.6))])
    head = ("M 31.2,32.8 "
            "C 32.6,26.0 33.2,19.0 30.8,14.2 "        # back of neck
            "C 29.4,11.0 27.0,9.0 24.6,8.4 "          # poll
            "L 25.0,5.4 L 22.4,7.8 "                  # ear
            "C 20.6,7.6 19.6,8.0 18.8,8.6 "
            "L 18.2,6.2 L 16.6,9.6 "                  # second ear
            "C 14.2,11.6 12.0,15.6 9.6,20.0 "         # forehead to nose
            "C 8.6,21.8 8.4,23.4 9.6,24.4 "           # muzzle
            "C 10.8,25.4 12.6,25.0 13.6,24.0 "        # mouth
            "C 15.0,23.0 16.8,22.6 18.4,22.0 "        # jaw
            "C 17.0,25.6 14.6,28.6 13.8,32.8 Z")      # throat to chest
    eye = "M 18.6,13.8 C 19.6,13.0 20.8,13.2 21.4,14.2 C 20.4,14.8 19.4,14.8 18.6,13.8 Z"
    nostril = "M 11.4,21.6 C 11.8,21.0 12.6,21.0 12.8,21.6"
    mane = "M 25.2,9.6 C 29.6,13.2 30.8,19.6 29.6,30.4"
    details = [hline(36.5, 10.1, 0.4), nostril, mane]
    return dict(bbox="8.4,5.4,35,39.5", fills=[base, head], details=details, solid=[eye])

PIECES = dict(k=king, q=queen, r=rook, b=bishop, n=knight, p=pawn)

# The shapes are drawn on a 45x45 grid; SCALE enlarges them about the centre so
# they fill the square like other Staunton sets.  The app redraws the vectors at
# every square size, so this sets the share of the square, not a pixel size.
SCALE = 1.12
import re

def _scale_path(d):
    out, cmd, i = [], None, 0
    toks = re.findall(r"[A-Za-z]|-?[0-9]*\.?[0-9]+", d)
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t; out.append(t); i += 1; continue
        if cmd == "A":  # rx ry rot large sweep x y
            rx, ry, rot, la, sw, x, y = toks[i:i+7]
            out.append(f"{f(float(rx)*SCALE)},{f(float(ry)*SCALE)} {rot} {la} {sw} "
                       f"{f(CX+(float(x)-CX)*SCALE)},{f(CX+(float(y)-CX)*SCALE)}")
            i += 7
        else:
            x, y = toks[i:i+2]
            out.append(f"{f(CX+(float(x)-CX)*SCALE)},{f(CX+(float(y)-CX)*SCALE)}")
            i += 2
    return " ".join(out)

def _scaled(fn):
    def g():
        spec = fn()
        for k in ("fills", "details", "solid"):
            if k in spec: spec[k] = [_scale_path(d) for d in spec[k]]
        b = [float(v) for v in spec["bbox"].split(",")]
        spec["bbox"] = ",".join(f(CX+(v-CX)*SCALE) for v in b)
        return spec
    return g

PIECES = {k: _scaled(v) for k, v in PIECES.items()}

STYLE_FILL = "fill:{fill};fill-opacity:1;fill-rule:nonzero;stroke:black;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round;stroke-opacity:1"
STYLE_LINE = "fill:none;stroke:{stroke};stroke-width:1.2;stroke-linecap:round;stroke-linejoin:round;stroke-opacity:1"
STYLE_DOT = "fill:{fill};stroke:{fill};stroke-width:0.6;stroke-opacity:1"

def group(p, color):
    spec = PIECES[p]()
    fill = "white" if color == "w" else "black"
    line = "black" if color == "w" else "white"
    out = [f'  <g\n    scidb:bbox="{spec["bbox"]}">']
    for d in spec["fills"]:
        out.append(f'    <path\n       style="{STYLE_FILL.format(fill=fill)}"\n       d="{d}" />')
    for d in spec["details"]:
        out.append(f'    <path\n       style="{STYLE_LINE.format(stroke=line)}"\n       d="{d}" />')
    for d in spec.get("solid", []):
        out.append(f'    <path\n       style="{STYLE_DOT.format(fill=line)}"\n       d="{d}" />')
    out.append("  </g>")
    return "\n".join(out)

def mask(p):
    """Solid silhouette of the piece, the shape the app uses for contour, shadow and texture."""
    spec = PIECES[p]()
    out = ["  <g>"]
    for d in spec["fills"]:
        out.append(f'    <path\n       style="{STYLE_FILL.format(fill="black")}"\n       d="{d}" />')
    out.append("  </g>")
    return "\n".join(out)

def svg_doc(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:scidb="http://scidb.sourceforge.net" '
            'width="45" height="45" viewBox="0 0 45 45">\n' + body + "\n</svg>\n")

if __name__ == "__main__":
    if len(sys.argv) == 2:  # preview: write one SVG per piece into the given directory
        for c in "wb":
            for p in "kqrbnp":
                open(os.path.join(sys.argv[1], f"{c}{p}.svg"), "w").write(svg_doc(group(p, c)))
    elif len(sys.argv) == 3:  # wizard-gen.py <set name> <output .tcl>
        name, path = sys.argv[1], sys.argv[2]
        var = name.replace(" ", "").replace("-", "_")
        hdr = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "wizard-header.txt")).read()
        parts = [hdr, f"lappend board_PieceSet {{ {{{name}}} svg {{contour 3.5}} {{sampling 150}} }}\n"]
        for c in "wb":
            for p in "kqrbnp":
                parts.append(f"set svg_{var}({c}{p}) {{\n{group(p, c)}}}\n")
        for p in "kqrbnp":
            parts.append(f"set svg_{var}(w{p},mask) {{\n{mask(p)}}}\n")
        for p in "kqrbnp":
            parts.append(f"set svg_{var}(b{p},mask) $svg_{var}(w{p},mask)")
        open(path, "w").write("\n".join(parts))
