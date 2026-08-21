"""Report any Font Awesome glyph the app uses that the built font subset lacks.

Icon tree-shaking rewrites the bundled .otf to hold only the code points the
compiler could prove are used. When it misses one, the app renders a tofu box
rather than failing the build, which is why this check exists at all.
"""
import glob
import io
import os
import re
import struct
import subprocess
import sys

def _package_source():
    """font_awesome_flutter's icon table, wherever pub put it."""
    root = os.environ.get('PUB_CACHE')
    if not root:
        for candidate in (
            os.path.join(os.path.expanduser('~'), 'AppData', 'Local', 'Pub', 'Cache'),
            os.path.join(os.path.expanduser('~'), '.pub-cache'),
        ):
            if os.path.isdir(candidate):
                root = candidate
                break
    hits = sorted(
        glob.glob(
            os.path.join(
                root or '',
                'hosted', '*', 'font_awesome_flutter-*',
                'lib', 'font_awesome_flutter.dart',
            )
        )
    )
    if not hits:
        sys.exit('font_awesome_flutter not found in the pub cache')
    return hits[-1]


FONTS = 'build/web/assets/packages/font_awesome_flutter/lib/fonts/'
FAMILY_FILE = {
    'FontAwesomeSolid': 'Font-Awesome-7-Free-Solid-900.otf',
    'FontAwesomeRegular': 'Font-Awesome-7-Free-Regular-400.otf',
    'FontAwesomeBrands': 'Font-Awesome-7-Brands-Regular-400.otf',
}


def cmap_of(path):
    d = open(path, 'rb').read()
    num = struct.unpack('>H', d[4:6])[0]
    tables = {}
    for i in range(num):
        off = 12 + i * 16
        tag = d[off:off + 4].decode('latin1')
        toff, tlen = struct.unpack('>II', d[off + 8:off + 16])
        tables[tag] = (toff, tlen)
    coff, _ = tables['cmap']
    n = struct.unpack('>H', d[coff + 2:coff + 4])[0]
    cps = set()
    for i in range(n):
        rec = coff + 4 + i * 8
        sub = coff + struct.unpack('>I', d[rec + 4:rec + 8])[0]
        fmt = struct.unpack('>H', d[sub:sub + 2])[0]
        if fmt == 4:
            segx2 = struct.unpack('>H', d[sub + 6:sub + 8])[0]
            seg = segx2 // 2
            ends = struct.unpack('>%dH' % seg, d[sub + 14:sub + 14 + segx2])
            ss = sub + 16 + segx2
            starts = struct.unpack('>%dH' % seg, d[ss:ss + segx2])
            for s, e in zip(starts, ends):
                if e == 0xFFFF:
                    continue
                cps.update(range(s, e + 1))
        elif fmt == 12:
            ng = struct.unpack('>I', d[sub + 12:sub + 16])[0]
            for g in range(ng):
                go = sub + 16 + g * 12
                s, e, _ = struct.unpack('>III', d[go:go + 12])
                cps.update(range(s, e + 1))
    return cps


src = io.open(_package_source(), encoding='utf-8').read()
meta = {}
for m in re.finditer(
    r"static const FaIconData (\w+) = FaIconData\(\s*IconData\(\s*"
    r"(0x[0-9a-fA-F]+),\s*fontFamily: '(\w+)'",
    src,
):
    meta[m.group(1)] = (int(m.group(2), 16), m.group(3))

used = subprocess.run(
    ['grep', '-rho', r'FontAwesomeIcons\.[A-Za-z0-9_]*', 'lib/', '--include=*.dart'],
    capture_output=True, text=True,
).stdout.split()
used = sorted({u.split('.', 1)[1] for u in used})

cmaps = {}
for fam, fname in FAMILY_FILE.items():
    path = os.path.join(FONTS, fname)
    if os.path.exists(path):
        cmaps[fam] = cmap_of(path)

missing = []
for name in used:
    if name not in meta:
        missing.append((name, '?', 'not declared in the package'))
        continue
    cp, fam = meta[name]
    if fam not in cmaps:
        missing.append((name, hex(cp), 'family %s not bundled' % fam))
    elif cp not in cmaps[fam]:
        missing.append((name, hex(cp), 'dropped from %s subset' % fam))

print('%d icons used' % len(used))
if not missing:
    print('every one is in its bundled subset')
    sys.exit(0)
print('MISSING (these render as tofu):')
for name, cp, why in missing:
    print('  %-22s %-9s %s' % (name, cp, why))
sys.exit(1)
