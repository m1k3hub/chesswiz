#!/usr/bin/env bash
# flag-icons v7.5.0 (MIT); originals drawn below are GPL-2.
# Requires curl, sha256sum, tar, Python 3, Pillow and CairoSVG.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl --fail --location --retry 3 -o "$tmp/flags.tar.gz" https://codeload.github.com/lipis/flag-icons/tar.gz/refs/tags/v7.5.0
printf '%s  %s\n' 5502d1bb0bda9f258d726d3c084a2d57a07cfdfa6d2ed18cbb5a1ee11b307778 "$tmp/flags.tar.gz" | sha256sum --check --status
tar -xzf "$tmp/flags.tar.gz" -C "$tmp"
python3 - "$root" "$tmp/flag-icons-7.5.0" <<'PYTHON'
from pathlib import Path
from PIL import Image, ImageDraw, PngImagePlugin
import cairosvg, io, sys, math
root, source = map(Path, sys.argv[1:])
MANIFEST = {'AFG': ['af', [72, 72]],
 'AHO': [None, [72, 72]],
 'AIA': ['ai', [72, 72]],
 'AIR': [None, [72, 72]],
 'ALA': ['ax', [72, 72]],
 'ALB': ['al', [72, 72]],
 'ALG': ['dz', [72, 72]],
 'AND': ['ad', [72, 72]],
 'ANG': ['ao', [72, 72]],
 'ANT': ['ag', [72, 72]],
 'ANY': [None, [72, 72]],
 'ANZ': ['au', [72, 72]],
 'ARG': ['ar', [72, 72]],
 'ARM': ['am', [72, 72]],
 'ARU': ['aw', [72, 72]],
 'ASA': ['as', [72, 72]],
 'ASE': ['asean', [72, 72]],
 'ATA': ['aq', [72, 72]],
 'ATF': ['tf', [72, 72]],
 'AUS': ['au', [72, 72]],
 'AUT': ['at', [72, 72]],
 'AZE': ['az', [72, 72]],
 'BAH': ['bs', [72, 72]],
 'BAN': ['bd', [72, 72]],
 'BAR': ['bb', [72, 72]],
 'BAS': ['es-pv', [72, 72]],
 'BDI': ['bi', [72, 72]],
 'BEL': ['be', [72, 72]],
 'BEN': ['bj', [72, 72]],
 'BER': ['bm', [72, 72]],
 'BES': ['bq', [72, 72]],
 'BHU': ['bt', [72, 72]],
 'BIH': ['ba', [72, 72]],
 'BIZ': ['bz', [72, 72]],
 'BLM': ['bl', [72, 72]],
 'BLR': ['by', [72, 72]],
 'BOL': ['bo', [72, 72]],
 'BOT': ['bw', [72, 72]],
 'BRA': ['br', [72, 72]],
 'BRN': ['bh', [72, 72]],
 'BRU': ['bn', [72, 72]],
 'BUL': ['bg', [72, 72]],
 'BUR': ['bf', [72, 72]],
 'BVT': ['bv', [72, 72]],
 'BWI': [None, [72, 72]],
 'CAF': ['cf', [72, 72]],
 'CAM': ['kh', [72, 72]],
 'CAN': ['ca', [72, 72]],
 'CAT': ['es-ct', [72, 72]],
 'CAY': ['ky', [72, 72]],
 'CCK': ['cc', [72, 72]],
 'CGO': ['cg', [72, 72]],
 'CHA': ['td', [72, 72]],
 'CHI': ['cl', [72, 72]],
 'CHN': ['cn', [72, 72]],
 'CIV': ['ci', [72, 72]],
 'CMR': ['cm', [72, 72]],
 'COD': ['cd', [72, 72]],
 'COK': ['ck', [72, 72]],
 'COL': ['co', [72, 72]],
 'COM': ['km', [72, 72]],
 'CPV': ['cv', [72, 72]],
 'CRC': ['cr', [72, 72]],
 'CRO': ['hr', [72, 72]],
 'CUB': ['cu', [72, 72]],
 'CUW': ['cw', [72, 72]],
 'CXR': ['cx', [72, 72]],
 'CYI': ['ic', [72, 72]],
 'CYP': ['cy', [72, 72]],
 'CZE': ['cz', [72, 72]],
 'DEN': ['dk', [72, 72]],
 'DJI': ['dj', [72, 72]],
 'DMA': ['dm', [72, 72]],
 'DOM': ['do', [72, 72]],
 'EAR': [None, [72, 72]],
 'EAZ': [None, [72, 72]],
 'ECU': ['ec', [72, 72]],
 'EGY': ['eg', [72, 72]],
 'ENG': ['gb-eng', [72, 72]],
 'ERI': ['er', [72, 72]],
 'ESA': ['sv', [72, 72]],
 'ESH': ['eh', [72, 72]],
 'ESP': ['es', [72, 72]],
 'EST': ['ee', [72, 72]],
 'ETH': ['et', [72, 72]],
 'EUR': ['eu', [72, 72]],
 'FAI': ['fo', [72, 72]],
 'FID': [None, [72, 72]],
 'FIJ': ['fj', [72, 72]],
 'FIN': ['fi', [72, 72]],
 'FLK': ['fk', [72, 72]],
 'FRA': ['fr', [72, 72]],
 'FRG': ['de', [72, 72]],
 'FSM': ['fm', [72, 72]],
 'GAB': ['ga', [72, 72]],
 'GAM': ['gm', [72, 72]],
 'GBR': ['gb', [72, 72]],
 'GBS': ['gw', [72, 72]],
 'GBZ': ['gi', [72, 72]],
 'GDR': [None, [72, 72]],
 'GEO': ['ge', [72, 72]],
 'GEQ': ['gq', [72, 72]],
 'GER': ['de', [72, 72]],
 'GGY': ['gg', [72, 72]],
 'GHA': ['gh', [72, 72]],
 'GLP': ['gp', [72, 72]],
 'GRE': ['gr', [72, 72]],
 'GRL': ['gl', [72, 72]],
 'GRN': ['gd', [72, 72]],
 'GUA': ['gt', [72, 72]],
 'GUF': ['gf', [72, 72]],
 'GUI': ['gn', [72, 72]],
 'GUM': ['gu', [72, 72]],
 'GUY': ['gy', [72, 72]],
 'HAI': ['ht', [72, 72]],
 'HKG': ['hk', [72, 72]],
 'HMD': ['hm', [72, 72]],
 'HON': ['hn', [72, 72]],
 'HUN': ['hu', [72, 72]],
 'IMN': ['im', [72, 72]],
 'INA': ['id', [72, 72]],
 'IND': ['in', [72, 72]],
 'IOT': ['io', [72, 72]],
 'IRI': ['ir', [72, 72]],
 'IRL': ['ie', [72, 72]],
 'IRQ': ['iq', [72, 72]],
 'ISL': ['is', [72, 72]],
 'ISR': ['il', [72, 72]],
 'ISV': ['vi', [72, 72]],
 'ITA': ['it', [72, 72]],
 'IVB': ['vg', [72, 72]],
 'JAM': ['jm', [72, 72]],
 'JEY': ['je', [72, 72]],
 'JMY': ['sj', [72, 72]],
 'JOR': ['jo', [72, 72]],
 'JPN': ['jp', [72, 72]],
 'KAZ': ['kz', [72, 72]],
 'KEN': ['ke', [72, 72]],
 'KGZ': ['kg', [72, 72]],
 'KIR': ['ki', [72, 72]],
 'KOR': ['kr', [72, 72]],
 'KOS': ['xk', [72, 72]],
 'KSA': ['sa', [72, 72]],
 'KUW': ['kw', [72, 72]],
 'LAO': ['la', [72, 72]],
 'LAT': ['lv', [72, 72]],
 'LBA': ['ly', [72, 72]],
 'LBR': ['lr', [72, 72]],
 'LCA': ['lc', [72, 72]],
 'LES': ['ls', [72, 72]],
 'LIB': ['lb', [72, 72]],
 'LIE': ['li', [72, 72]],
 'LTU': ['lt', [72, 72]],
 'LUX': ['lu', [72, 72]],
 'MAC': ['mo', [72, 72]],
 'MAD': ['mg', [72, 72]],
 'MAF': ['mf', [72, 72]],
 'MAR': ['ma', [72, 72]],
 'MAS': ['my', [72, 72]],
 'MAW': ['mw', [72, 72]],
 'MDA': ['md', [72, 72]],
 'MDV': ['mv', [72, 72]],
 'MEX': ['mx', [72, 72]],
 'MGL': ['mn', [72, 72]],
 'MHL': ['mh', [72, 72]],
 'MKD': ['mk', [72, 72]],
 'MLI': ['ml', [72, 72]],
 'MLT': ['mt', [72, 72]],
 'MNC': ['mc', [72, 72]],
 'MNE': ['me', [72, 72]],
 'MNP': ['mp', [72, 72]],
 'MON': ['mc', [72, 72]],
 'MOZ': ['mz', [72, 72]],
 'MRI': ['mu', [72, 72]],
 'MSR': ['ms', [72, 72]],
 'MTN': ['mr', [72, 72]],
 'MTQ': ['mq', [72, 72]],
 'MYA': ['mm', [72, 72]],
 'MYT': ['yt', [72, 72]],
 'NAM': ['na', [72, 72]],
 'NCA': ['ni', [72, 72]],
 'NCL': ['nc', [72, 72]],
 'NED': ['nl', [72, 72]],
 'NEP': ['np', [72, 72]],
 'NET': [None, [72, 72]],
 'NFK': ['nf', [72, 72]],
 'NGR': ['ng', [72, 72]],
 'NIG': ['ne', [72, 72]],
 'NIR': ['gb-nir', [72, 72]],
 'NIU': ['nu', [72, 72]],
 'NOR': ['no', [72, 72]],
 'NRD': [None, [72, 72]],
 'NRU': ['nr', [72, 72]],
 'NZL': ['nz', [72, 72]],
 'OMA': ['om', [72, 72]],
 'OMN': ['om', [72, 72]],
 'PAK': ['pk', [72, 72]],
 'PAN': ['pa', [72, 72]],
 'PAR': ['py', [72, 72]],
 'PCN': ['pn', [72, 72]],
 'PER': ['pe', [72, 72]],
 'PHI': ['ph', [72, 72]],
 'PLE': ['ps', [72, 72]],
 'PLW': ['pw', [72, 72]],
 'PNG': ['pg', [72, 72]],
 'POL': ['pl', [72, 72]],
 'POR': ['pt', [72, 72]],
 'PRK': ['kp', [72, 72]],
 'PUR': ['pr', [72, 72]],
 'PYF': ['pf', [72, 72]],
 'QAT': ['qa', [72, 72]],
 'REU': ['re', [72, 72]],
 'ROU': ['ro', [72, 72]],
 'RSA': ['za', [72, 72]],
 'RUS': ['ru', [72, 72]],
 'RWA': ['rw', [72, 72]],
 'SAM': ['ws', [72, 72]],
 'SCG': [None, [72, 72]],
 'SCO': ['gb-sct', [72, 72]],
 'SEA': [None, [72, 72]],
 'SEN': ['sn', [72, 72]],
 'SEY': ['sc', [72, 72]],
 'SGS': ['gs', [72, 72]],
 'SHN': ['sh', [72, 72]],
 'SIN': ['sg', [72, 72]],
 'SJM': ['sj', [72, 72]],
 'SKN': ['kn', [72, 72]],
 'SLE': ['sl', [72, 72]],
 'SLO': ['si', [72, 72]],
 'SMR': ['sm', [72, 72]],
 'SOL': ['sb', [72, 72]],
 'SOM': ['so', [72, 72]],
 'SPC': [None, [72, 72]],
 'SPM': ['pm', [72, 72]],
 'SRB': ['rs', [72, 72]],
 'SRI': ['lk', [72, 72]],
 'SSD': ['ss', [72, 72]],
 'STP': ['st', [72, 72]],
 'SUD': ['sd', [72, 72]],
 'SUI': ['ch', [72, 72]],
 'SUR': ['sr', [72, 72]],
 'SVB': ['sj', [72, 72]],
 'SVK': ['sk', [72, 72]],
 'SWE': ['se', [72, 72]],
 'SWZ': ['sz', [72, 72]],
 'SXM': ['sx', [72, 72]],
 'SYR': ['sy', [72, 72]],
 'TAN': ['tz', [72, 72]],
 'TCA': ['tc', [72, 72]],
 'TCH': ['cz', [72, 72]],
 'TGA': ['to', [72, 72]],
 'THA': ['th', [72, 72]],
 'TIB': [None, [72, 72]],
 'TJK': ['tj', [72, 72]],
 'TKL': ['tk', [72, 72]],
 'TKM': ['tm', [72, 72]],
 'TLS': ['tl', [72, 72]],
 'TOG': ['tg', [72, 72]],
 'TPE': ['tw', [72, 72]],
 'TRI': ['tt', [72, 72]],
 'TTO': ['tt', [72, 72]],
 'TUN': ['tn', [72, 72]],
 'TUR': ['tr', [72, 72]],
 'TUV': ['tv', [72, 72]],
 'UAE': ['ae', [72, 72]],
 'UGA': ['ug', [72, 72]],
 'UKR': ['ua', [72, 72]],
 'UMI': ['um', [72, 72]],
 'UNK': [None, [72, 72]],
 'URS': [None, [72, 72]],
 'URU': ['uy', [72, 72]],
 'USA': ['us', [72, 72]],
 'UZB': ['uz', [72, 72]],
 'VAN': ['vu', [72, 72]],
 'VAT': ['va', [72, 72]],
 'VEN': ['ve', [72, 72]],
 'VIE': ['vn', [72, 72]],
 'VIN': ['vc', [72, 72]],
 'VUS': ['vi', [72, 72]],
 'WLF': ['wf', [72, 72]],
 'WLS': ['gb-wls', [72, 72]],
 'YEM': ['ye', [72, 72]],
 'YUG': [None, [72, 72]],
 'ZAM': ['zm', [72, 72]],
 'ZAN': [None, [72, 72]],
 'ZIM': ['zw', [72, 72]],
 'ZZG': [None, [72, 72]],
 'ZZR': [None, [72, 72]],
 'ZZX': ['un', [72, 72]]}
# Explicit historic/special flags; no unidentified downloaded imagery.
BANDS = {'AHO': ['white','blue','white'], 'BWI':['#204080','white','#204080'],
 'EAZ':['#202020','#ffe070','#c03030'], 'GDR':['black','#dd2020','#ffd030'],
 'NRD':['#204080','white','#d02030'], 'SCG':['#204080','white','#d02030'],
 'URS':['#c02020'], 'YUG':['#204080','white','#d02030'],
 'TIB':['#204080'], 'ZAN':['#2080c0','black','#209040'], 'ZZG':['#808080'], 'ZZR':['#c03030']}
def star(draw, cx, cy, radius, fill):
 points=[]
 for i in range(10):
  angle=-math.pi/2+i*math.pi/5
  rr=radius if i%2==0 else radius*.4
  points.append((cx+math.cos(angle)*rr,cy+math.sin(angle)*rr))
 draw.polygon(points,fill=fill)

ICONS = {'AIR':'air','EAR':'earth','FID':'pawn','NET':'net','SEA':'sea','SPC':'space','ANY':'*','UNK':'?'}
lines = ['flag-icons v7.5.0, Copyright (c) 2013 Panayiotis Lipiridis, MIT.',
 'Pinned archive SHA256: 5502d1bb0bda9f258d726d3c084a2d57a07cfdfa6d2ed18cbb5a1ee11b307778',
 'Original historic and special drawings: Chesswiz, GPL-2. All names/sizes preserved.']
for name, (code, size) in MANIFEST.items():
 w,h=size
 if code:
  svg=source/'flags/4x3'/f'{code}.svg'
  if not svg.exists(): raise RuntimeError(f'Missing mapped flag {name}: {code}')
  im=Image.open(io.BytesIO(cairosvg.svg2png(url=str(svg),output_width=w*4,output_height=h*4))).convert('RGBA')
  lines.append(f'{name}\tflag-icons {code} (MIT)')
 else:
  im=Image.new('RGBA',(w*4,h*4),'#203c68'); d=ImageDraw.Draw(im); W,H=im.size
  if name in BANDS:
   bands=BANDS[name]
   for i,col in enumerate(bands): d.rectangle((0,i*H/len(bands),W,(i+1)*H/len(bands)), fill=col)
   if name=='AHO':
    d.rectangle((W*.43,0,W*.57,H),fill='#cc2020')
    for k in range(6): star(d,W*(.31+(k%3)*.19),H*(.4+(k//3)*.2),H*.035,'white')
   elif name=='BWI': d.ellipse((W*.42,H*.15,W*.58,H*.3),fill='#e0b840')
   elif name=='GDR':
    d.ellipse((W*.4,H*.36,W*.6,H*.64),outline='#e8bd40',width=5)
    d.line((W*.45,H*.46,W*.55,H*.56),fill='#e8bd40',width=6)
   elif name=='URS':
    star(d,W*.22,H*.2,H*.09,'#ffd040')
    d.arc((W*.12,H*.22,W*.35,H*.5),20,250,fill='#ffd040',width=7)
    d.line((W*.16,H*.28,W*.3,H*.45),fill='#ffd040',width=6)
   elif name=='YUG': star(d,W*.5,H*.5,H*.27,'#ffd040'); star(d,W*.5,H*.5,H*.23,'#d02030')
   elif name=='NRD':
    d.rectangle((W*.27,0,W*.48,H),fill='white'); d.rectangle((0,H*.39,W,H*.61),fill='white')
    d.rectangle((W*.33,0,W*.42,H),fill='#d02030'); d.rectangle((0,H*.45,W,H*.55),fill='#d02030')
   elif name=='TIB':
    for k in range(6):
     a=math.pi+k*math.pi/6; b=a+math.pi/12
     d.polygon([(W*.5,H*.75),(W*.5+W*math.cos(a),H*.75+H*math.sin(a)),(W*.5+W*math.cos(b),H*.75+H*math.sin(b))],fill='#dd2020')
    d.polygon([(W*.2,H*.85),(W*.5,H*.45),(W*.8,H*.85)],fill='white')
    d.ellipse((W*.42,H*.36,W*.58,H*.52),fill='#ffda40')
    d.rectangle((0,H*.93,W,H),fill='#ffda40')
  else:
   icon=ICONS[name]
   if icon=='pawn':
    d.ellipse((W*.37,H*.16,W*.63,H*.42),fill='white'); d.polygon([(W*.45,H*.4),(W*.55,H*.4),(W*.7,H*.8),(W*.3,H*.8)],fill='white')
   elif icon=='earth':
    d.ellipse((W*.18,H*.18,W*.82,H*.82),fill='#40a0e0'); d.polygon([(W*.3,H*.25),(W*.65,H*.3),(W*.5,H*.65),(W*.3,H*.6)],fill='#60bc60')
   elif icon=='net':
    for k in range(1,5):
     d.line((W*k/5,H*.15,W*k/5,H*.85),fill='white',width=3); d.line((W*.15,H*k/5,W*.85,H*k/5),fill='white',width=3)
   elif icon=='sea':
    for k in range(3): d.arc((W*.1,H*(.25+k*.15),W*.9,H*(.55+k*.15)),0,180,fill='#80d8ff',width=8)
   elif icon=='air':
    d.polygon([(W*.1,H*.5),(W*.45,H*.43),(W*.55,H*.15),(W*.63,H*.43),(W*.9,H*.5),(W*.6,H*.57),(W*.55,H*.8),(W*.48,H*.57)],fill='white')
   elif icon=='space':
    d.ellipse((W*.25,H*.25,W*.75,H*.75),fill='#c0a0e0'); d.ellipse((W*.1,H*.4,W*.9,H*.6),outline='white',width=7)
   else:
    d.text((W*.35,H*.3),icon,fill='white',font_size=int(H*.4))
  lines.append(f'{name}\toriginal Chesswiz drawing (GPL-2)')
 metadata=PngImagePlugin.PngInfo()
 metadata.add_text('License', (source/'LICENSE').read_text() if code else 'Original Chesswiz artwork, GPL-2; see project COPYING.')
 metadata.add_text('Source', f'flag-icons v7.5.0: {code}' if code else 'Original drawing: scripts/generate-flags.sh')
 im.resize((w,h),Image.Resampling.LANCZOS).save(root/'tcl/flags'/f'{name}.png',pnginfo=metadata)
(root/'tcl/flags/LICENSE').write_bytes((source/'LICENSE').read_bytes())
(root/'tcl/flags/SOURCES.txt').write_text('\n'.join(lines)+'\n')
(root/'tcl/flags/readme').write_text('Rebuilt from flag-icons (MIT) and original Chesswiz drawings (GPL-2).\nSee LICENSE, SOURCES.txt and scripts/generate-flags.sh.\n')
PYTHON
