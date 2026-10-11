#!/usr/bin/env python3
"""Render tip images from Noto Color Emoji (Apache-2.0), using Pillow.
Usage: generate-motives.py [path/to/NotoColorEmoji.ttf]
"""
from pathlib import Path
import sys, hashlib
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
MANIFEST = {'Motive-Bear.png': [[128, 128], '🐻'],
 'Motive-Bird-1.png': [[128, 128], '🐦'],
 'Motive-Bird-2.png': [[128, 128], '🐤'],
 'Motive-Bug.png': [[128, 128], '🐛'],
 'Motive-Butterfly-1.png': [[128, 128], '🦋'],
 'Motive-Cat.png': [[128, 128], '🐱'],
 'Motive-Chess.png': [[128, 128], '♟'],
 'Motive-Daisy.png': [[128, 128], '🌼'],
 'Motive-Dartboard.png': [[128, 128], '🎯'],
 'Motive-Dolphin.png': [[128, 128], '🐬'],
 'Motive-Dragon.png': [[128, 128], '🐉'],
 'Motive-Flower.png': [[128, 128], '🌸'],
 'Motive-Fox.png': [[128, 128], '🦊'],
 'Motive-Fruits-1.png': [[128, 128], '🍇'],
 'Motive-Fruits-2.png': [[128, 128], '🍓'],
 'Motive-Hedgehog.png': [[128, 128], '🦔'],
 'Motive-Hippo.png': [[128, 128], '🦛'],
 'Motive-Koala.png': [[128, 128], '🐨'],
 'Motive-Ladybird.png': [[128, 128], '🐞'],
 'Motive-Panda.png': [[128, 128], '🐼'],
 'Motive-Penguin.png': [[128, 128], '🐧'],
 'Motive-Pidgin.png': [[128, 128], '🕊'],
 'Motive-Rabbit.png': [[128, 128], '🐰'],
 'Motive-Snake.png': [[128, 128], '🐍'],
 'Motive-Squirrel.png': [[128, 128], '🐿'],
 'Motive-Sunflower.png': [[128, 128], '🌻'],
 'Motive-Tip-of-the-Day.png': [[128, 128], '💡'],
 'Motive-Tulip.png': [[128, 128], '🌷'],
 'Motive-Turtle.png': [[128, 128], '🐢']}
font_path=Path(sys.argv[1] if len(sys.argv)>1 else '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf')
# Debian fonts-noto-color-emoji; pin the rendering input for byte-for-byte rebuilds.
EXPECTED_SHA256='9fd0a3d0ce84d77e3185dfbae77bd1abf3926aa49a032e354d076c4f17151f10'
if hashlib.sha256(font_path.read_bytes()).hexdigest()!=EXPECTED_SHA256:
    raise SystemExit('Font SHA256 differs from the audited rendering input; see tcl/images/README')
font=ImageFont.truetype(str(font_path),109)
for name,(size,glyph) in MANIFEST.items():
    canvas=Image.new('RGBA',(180,180))
    draw=ImageDraw.Draw(canvas)
    box=draw.textbbox((0,0),glyph,font=font)
    draw.text(((180-box[2]+box[0])/2-box[0],(180-box[3]+box[1])/2-box[1]),glyph,font=font,embedded_color=True)
    canvas.resize(tuple(size),Image.Resampling.LANCZOS).save(ROOT/'tcl/images'/name)
