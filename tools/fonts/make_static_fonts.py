"""Static weight instances of the UI font (Fredoka, SIL OFL 1.1).

Godot renders Fredoka-Variable.ttf at its default instance (Light, 300)
whatever FontVariation weight the UI asks for (measured with
game/src/dev/font_weights.tscn), so the UI ships fixed instances instead:

    python3 -m venv tools/.cache/fontenv && tools/.cache/fontenv/bin/pip install fonttools==4.55.3
    tools/.cache/fontenv/bin/python tools/fonts/make_static_fonts.py

Writes game/assets/fonts/Fredoka-{Medium,SemiBold,Bold}.ttf (width 100).
The OFL allows modified versions; Fredoka declares no Reserved Font Name.
"""
import os
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, '..', '..', 'game', 'assets', 'fonts')
SRC = os.path.join(FONTS, 'Fredoka-Variable.ttf')
WEIGHTS = {'Medium': 500, 'SemiBold': 600, 'Bold': 700}

for style, w in WEIGHTS.items():
    f = TTFont(SRC)
    inst = instantiateVariableFont(f, {'wght': w, 'wdth': 100}, updateFontNames=False)
    name = inst['name']
    for rec in list(name.names):
        if rec.nameID in (2, 17):
            rec.string = style
        elif rec.nameID in (4,):
            rec.string = 'Fredoka %s' % style
        elif rec.nameID == 6:
            rec.string = 'Fredoka-%s' % style
        elif rec.nameID in (1, 16):
            rec.string = 'Fredoka'
    inst['OS/2'].usWeightClass = w
    out = os.path.join(FONTS, 'Fredoka-%s.ttf' % style)
    inst.save(out)
    print('wrote', out, os.path.getsize(out))
