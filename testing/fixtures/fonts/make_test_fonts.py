# Makes the small fonts FONT_FILE_NAMES is tested with. Every letter and digit is one plain
# block, so the files are tiny, and the family names are ones no system has installed.
#   python make_test_fonts.py <folder>
# Needs fontTools. The fonts are made for these tests and are public domain (CC0).
import os
import sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTCollection, TTFont


def box(x0, y0, x1, y1):
    pen = TTGlyphPen(None)
    pen.moveTo((x0, y0)); pen.lineTo((x0, y1)); pen.lineTo((x1, y1)); pen.lineTo((x1, y0)); pen.closePath()
    return pen.glyph()


def build(path, family, typographic=None, mac=False):
    chars = [chr(c) for c in range(0x30, 0x3A)] + [chr(c) for c in range(0x41, 0x5B)] + [chr(c) for c in range(0x61, 0x7B)]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder([".notdef", "space", "block"])
    cmap = {0x20: "space"}
    for ch in chars:
        cmap[ord(ch)] = "block"
    fb.setupCharacterMap(cmap)
    fb.setupGlyf({".notdef": box(100, 0, 500, 700), "space": TTGlyphPen(None).glyph(), "block": box(80, 0, 520, 700)})
    fb.setupHorizontalMetrics({".notdef": (600, 100), "space": (300, 0), "block": (600, 80)})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    names = {"familyName": family, "styleName": "Regular", "uniqueFontIdentifier": family + " 1.0",
             "fullName": family, "psName": family.replace(" ", "") + "-Regular", "version": "Version 1.0",
             "copyright": "Made for simple_shaping's tests. Public domain (CC0)."}
    if typographic:
        names["typographicFamily"] = typographic
        names["typographicSubfamily"] = "Light"
    fb.setupNameTable(names, windows=True, mac=mac)
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200, usWeightClass=400)
    fb.setupPost()
    fb.save(path)


out = sys.argv[1]
two = os.path.join(out, "two_names.ttf")
build(two, "Shaping Test Light", typographic="Shaping Test", mac=True)
one = os.path.join(out, "_one.ttf")
other = os.path.join(out, "_other.ttf")
build(one, "Shaping Test One")
build(other, "Shaping Test Two")
pair = TTCollection()
pair.fonts = [TTFont(one), TTFont(other)]
pair.save(os.path.join(out, "pair.ttc"))
os.remove(one)
os.remove(other)
with open(two, "rb") as f:
    head = f.read(40)
with open(os.path.join(out, "cut_short.ttf"), "wb") as f:
    f.write(head)
