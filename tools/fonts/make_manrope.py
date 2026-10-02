"""Static weight instances of the V5 UI font (Manrope, SIL OFL 1.1).

Godot draws a variable font at its default instance whatever weight is
requested (measured in V3 with game/src/dev/font_weights.tscn; Manrope's
default is ExtraLight 200), so the UI ships fixed instances:

    python3 -m venv tools/.cache/fontenv && tools/.cache/fontenv/bin/pip install fonttools==4.55.3
    tools/.cache/fontenv/bin/python tools/fonts/make_manrope.py

Source: art_src/fonts/Manrope-Variable.ttf (google/fonts ofl/manrope,
sha256 3ae11c49...d6ae6, upstream googlefonts/manrope 6f81ebe).
Writes game/assets/fonts/Manrope-{Medium,SemiBold,Bold,ExtraBold}.ttf.
The OFL allows modified versions; Manrope declares no Reserved Font Name.
"""
import os
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
SRC = os.path.join(ROOT, 'art_src', 'fonts', 'Manrope-Variable.ttf')
OUT = os.path.join(ROOT, 'game', 'assets', 'fonts')
WEIGHTS = {'Medium': 500, 'SemiBold': 600, 'Bold': 700, 'ExtraBold': 800}

for style, w in WEIGHTS.items():
    f = TTFont(SRC)
    inst = instantiateVariableFont(f, {'wght': w}, updateFontNames=False)
    name = inst['name']
    for rec in list(name.names):
        if rec.nameID in (2, 17):
            rec.string = style
        elif rec.nameID == 4:
            rec.string = 'Manrope %s' % style
        elif rec.nameID == 6:
            rec.string = 'Manrope-%s' % style
        elif rec.nameID in (1, 16):
            rec.string = 'Manrope'
    inst['OS/2'].usWeightClass = w
    path = os.path.join(OUT, 'Manrope-%s.ttf' % style)
    inst.save(path)
    print('wrote', path, os.path.getsize(path))
