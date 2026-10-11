#!/usr/bin/env python3
"""Original GPL-2+ Chesswiz cursors. Requires Pillow==11.3.0.
Preserves names, dimensions and intended hotspots (from Xcursor/XBM).
Writes standards-compliant Windows CUR, Xcursor and monochrome XBM files.
  python scripts/generate-cursors.py --inventory-only  # before sheets
  python scripts/generate-cursors.py                   # regenerate
"""
import argparse
import io
import json
from pathlib import Path
import re
import struct
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
CUR=ROOT/'tcl/cursor'
OUT=ROOT/'tests/tmp-app/icons'
# name -> (width, height, x hotspot, y hotspot), matching existing Xcursor/XBM.
SPECS={'circle-orange-16x16':(16,16,8,8),'circle-orange-32x32':(32,32,16,16),
       'collapse-16x16':(16,16,7,7),'expand-16x16':(16,16,7,7)}
SPECS.update({f'drag-{obj}-{state}-32x32':(32,32,16,16)
              for obj in ('db','document','folder','image') for state in ('accept','deny')})
SPECS.update({f'igor-{side}{piece}-32x32':(32,32,16,16)
              for side in ('w','b') for piece in ('k','q','r','b','n','p')})


def draw(name):
    w,h,_,_=SPECS[name]; scale=4
    im=Image.new('RGBA',(w*scale,h*scale));d=ImageDraw.Draw(im)
    def line(points,fill='#334155',width=2):
        d.line([(int(x*scale),int(y*scale)) for x,y in points],fill=fill,width=width*scale,joint='curve')
    def rect(box,fill,outline=None,width=1):
        d.rectangle(tuple(int(x*scale) for x in box),fill,outline,width*scale)
    def oval(box,fill,outline=None,width=1):
        d.ellipse(tuple(int(x*scale) for x in box),fill,outline,width*scale)
    if name.startswith('circle'):
        oval((2,2,w-3,h-3),None,'#e87919',2)
    elif name.startswith(('expand','collapse')):
        rect((2,2,13,13),'#ffffff','#334155');line([(4,7),(11,7)],width=1)
        if name.startswith('expand'):line([(7,4),(7,11)],width=1)
    elif name.startswith('drag'):
        obj=name.split('-')[1]
        # Small origin arrow remains legible at the central preserved hotspot.
        if obj=='db':
            rect((3,7,22,23),'#e2e8f0','#334155');oval((3,3,22,11),'#e2e8f0','#334155');oval((3,19,22,25),'#e2e8f0','#334155')
        elif obj=='folder':
            rect((3,4,11,9),'#f4ca68','#334155');rect((3,8,24,24),'#f4ca68','#334155')
        elif obj=='document':
            rect((4,3,23,25),'#ffffff','#334155');line([(8,9),(19,9)]);line([(8,14),(19,14)]);line([(8,19),(17,19)])
        else:
            rect((3,4,24,25),'#ffffff','#334155');oval((7,7,11,11),'#dba629');line([(5,23),(12,14),(17,20),(21,14),(23,23)],'#32825a')
        line([(16,16),(16,22),(20,20),(16,16)],'#111827',1)
        accept='accept' in name; colour='#16803c' if accept else '#dc2626'
        oval((19,19,31,31),'#ffffff',colour,1)
        if accept:line([(22,25),(25,28),(29,22)],colour,2)
        else:line([(23,23),(28,28)],colour,2);line([(28,23),(23,28)],colour,2)
    else:
        side,piece=name.split('-')[1];fill,ink=('#ffffff','#111827') if side=='w' else ('#111827','#ffffff')
        def polygon(points):
            pts=[(x*scale,y*scale) for x,y in points];d.polygon(pts,fill=fill);d.line(pts+[pts[0]],fill=ink,width=scale,joint='curve')
        # Geometric silhouettes drawn afresh, independent of existing piece sets.
        rect((6,27,26,30),fill,ink);polygon([(9,26),(12,15),(20,15),(23,26)])
        if piece=='p':oval((11,5,21,15),fill,ink)
        elif piece=='k':
            polygon([(10,8),(22,8),(20,16),(12,16)]);line([(16,2),(16,8)],ink,2);line([(13,4),(19,4)],ink,2)
        elif piece=='q':
            polygon([(8,6),(12,10),(16,4),(20,10),(24,6),(21,16),(11,16)])
            for x,y in [(8,5),(16,3),(24,5)]:oval((x-1,y-1,x+1,y+1),ink)
        elif piece=='r':polygon([(8,4),(12,4),(12,8),(15,8),(15,4),(18,4),(18,8),(21,8),(21,4),(24,4),(22,15),(10,15)])
        elif piece=='b':
            polygon([(16,3),(10,10),(12,16),(20,16),(22,10)]);line([(18,6),(14,11)],ink,1)
        else:
            polygon([(10,17),(11,10),(16,3),(19,5),(24,9),(22,13),(17,11),(21,20),(10,20)]);oval((18,7,19,8),ink)
    return im.resize((w,h),Image.Resampling.LANCZOS)


def xcursor(im,spec):
    w,h,x,y=spec
    pixels=[]
    for r,g,b,a in im.getdata():pixels.append((a<<24)|((r*a//255)<<16)|((g*a//255)<<8)|(b*a//255))
    return struct.pack('<4I3I9I',0x72756358,16,0x10000,1,0xfffd0002,w,28,36,0xfffd0002,w,1,w,h,x,y,50)+struct.pack('<'+'I'*len(pixels),*pixels)


def windows_cur(im,spec):
    w,h,x,y=spec;stride=((w+31)//32)*4
    pixels=bytearray();mask=bytearray()
    for row in range(h-1,-1,-1):
        bits=bytearray(stride)
        for col in range(w):
            r,g,b,a=im.getpixel((col,row));pixels.extend((b,g,r,a))
            if a<128:bits[col//8]|=128>>(col%8)
        mask.extend(bits)
    dib=struct.pack('<IiiHHIIiiII',40,w,h*2,1,32,0,len(pixels)+len(mask),0,0,0,0)+pixels+mask
    return struct.pack('<HHHBBBBHHII',0,2,1,w,h,0,0,x,y,len(dib),22)+dib


def bitmap(im,name,is_mask=False):
    w,h,x,y=SPECS[name.removesuffix('_mask')]; ident=name.replace('-','_');data=[]
    for row in range(h):
        for chunk in range((w+7)//8):
            b=0
            for bit in range(8):
                col=chunk*8+bit
                if col>=w:continue
                r,g,bl,a=im.getpixel((col,row))
                # Tk's b-piece foreground is white; w-piece foreground is black.
                on=a>=128 and (is_mask or (r+g+bl>=384 if '-b' in name else r+g+bl<384))
                if on:b|=1<<bit
            data.append(b)
    header=f'/* Original Chesswiz artwork, 2026; GPL-2.0-or-later. */\n#define {ident}_width {w}\n#define {ident}_height {h}\n#define {ident}_x_hot {x}\n#define {ident}_y_hot {y}\nstatic unsigned char {ident}_bits[] = {{\n'
    return header+'\n'.join('  '+', '.join(f'0x{v:02x}' for v in data[i:i+12])+(',' if i+12<len(data) else '') for i in range(0,len(data),12))+' };\n'


def read_cursor(path):
    b=path.read_bytes()
    if path.suffix=='.xcur':
        off=struct.unpack_from('<I',b,24)[0];hdr,typ,sub,ver,w,h,x,y,delay=struct.unpack_from('<9I',b,off)
        im=Image.new('RGBA',(w,h));px=[]
        for argb in struct.unpack_from('<'+'I'*(w*h),b,off+hdr):
            a=argb>>24;r=(argb>>16)&255;g=(argb>>8)&255;bl=argb&255
            px.append((min(255,r*255//a) if a else 0,min(255,g*255//a) if a else 0,min(255,bl*255//a) if a else 0,a))
        im.putdata(px);return im,(w,h,x,y)
    if path.suffix=='.xbm':
        t=b.decode();vals={k:int(v) for k,v in re.findall(r'#define \w+_(width|height|x_hot|y_hot) (\d+)',t)}
        w,h=vals['width'],vals['height'];raw=bytes(int(v,16) for v in re.findall(r'0x([0-9a-f]+)',t));im=Image.new('RGBA',(w,h),'#ffffff')
        for y in range(h):
            for x in range(w):
                if raw[y*((w+7)//8)+x//8]&(1<<(x%8)):im.putpixel((x,y),(0,0,0,255))
        return im,(w,h,vals.get('x_hot',16),vals.get('y_hot',16))
    # Historical .cur files have malformed ICO-like headers; patch only in memory
    # for Pillow's decoder. Intended hotspots come from Xcursor / name's spec.
    if struct.unpack_from('<H',b,2)[0]==2:
        w,h,_,_,x,y,_,_=struct.unpack_from('<BBBBHHII',b,6)
        spec=(w or 256,h or 256,x,y)
    else:
        spec=SPECS[path.stem]
    fixed=bytearray(b);fixed[:6]=struct.pack('<HHH',0,1,1)
    im=Image.open(io.BytesIO(fixed)).convert('RGBA')
    if im.size!=spec[:2]: raise RuntimeError(f"{path}: decoded dimensions differ from header")
    return im,spec


def sheet(rows,label):
    canvas=Image.new('RGB',(1000,((len(rows)+7)//8)*95),'#ededed');d=ImageDraw.Draw(canvas)
    for i,(name,im) in enumerate(rows):
        x,y=(i%8)*125,(i//8)*95;d.rectangle((x+4,y+3,x+121,y+67),fill='#808080')
        canvas.paste(im,(x+(125-im.width)//2,y+7),im)
        d.text((x+3,y+70),name[:21],fill='black');d.text((x+3,y+82),name[21:42],fill='black')
    canvas.save(OUT/f'cursors-{label}.png')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--inventory-only',action='store_true');a=p.parse_args();OUT.mkdir(parents=True,exist_ok=True)
    files=sorted(p for p in CUR.iterdir() if p.suffix in ('.cur','.xcur','.xbm'))
    if a.inventory_only:
        rows=[];records=[]
        for path in files:
            im,spec=read_cursor(path);rows.append((path.name,im));records.append(dict(file=str(path.relative_to(ROOT)),size=spec[:2],hotspot=spec[2:],format=path.suffix))
        (OUT/'cursors-inventory.json').write_text(json.dumps(records,indent=2)+'\n');sheet(rows,'before');print(f'Inventoried {len(files)} cursor files.');return
    rows=[]
    for path in files:
        name=path.stem;mask=name.endswith('_mask');base=name.removesuffix('_mask');im=draw(base);spec=SPECS[base]
        if path.suffix=='.cur':path.write_bytes(windows_cur(im,spec))
        elif path.suffix=='.xcur':path.write_bytes(xcursor(im,spec))
        else:path.write_text(bitmap(im,name,mask))
        # Read back formats, rather than showing only the intermediate drawing.
        actual,got=read_cursor(path)
        if got!=spec:raise RuntimeError(f'{path}: dimensions/hotspot mismatch')
        rows.append((path.name,actual))
    sheet(rows,'after');print(f'Regenerated {len(files)} original cursor files.')
if __name__=='__main__':main()
