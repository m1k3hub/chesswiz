#!/usr/bin/env python3
"""Developer preview: every regenerated asset, labelled, in three contact sheets."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tests/tmp-app/assets'
OUT.mkdir(parents=True, exist_ok=True)
GROUPS = {
    'textures': sorted(p for p in (ROOT/'tcl/textures').rglob('*') if p.suffix.lower() in ('.png','.jpg','.jpeg','.gif')),
    'flags': sorted((ROOT/'tcl/flags').glob('*.png')),
    'motives': sorted((ROOT/'tcl/images').glob('Motive-*.png')),
}
for group, paths in GROUPS.items():
    cols, cw, ch = (8, 180, 124) if group == 'textures' else (12, 100, 100) if group == 'flags' else (6, 180, 180)
    sheet = Image.new('RGB', (cols*cw, ((len(paths)+cols-1)//cols)*ch), '#e0e0e0')
    draw = ImageDraw.Draw(sheet)
    for i,p in enumerate(paths):
        x,y=(i%cols)*cw,(i//cols)*ch
        im=Image.open(p).convert('RGBA')
        im.thumbnail((cw-12,ch-34))
        sheet.paste(im,(x+(cw-im.width)//2,y+4),im)
        label=str(p.relative_to(ROOT/'tcl/textures')) if group=='textures' else p.stem.removeprefix('Motive-')
        for j in range(0,len(label),28):
            draw.text((x+3,y+ch-30+(j//28)*10),label[j:j+28],fill='black')
    sheet.save(OUT/f'{group}-contact-sheet.png')
