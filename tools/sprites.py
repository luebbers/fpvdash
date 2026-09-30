"""Generate the theme sprites: glyph sheets, word images and patterns, with their Lua metrics.

EdgeTX Lua widgets can only use the radio's built-in fonts, so the large numbers and display
words of the Glass Cockpit and Hi-Vis themes are pre-rendered here in the typefaces the designs
use and drawn on the radio as images.

A glyph sheet holds one font at one size: every character in a fixed-width cell, one horizontal
band per colour (images can't be tinted on the radio). The widget shows a character by placing
the sheet inside a clipping box the size of a cell, so a screen needs one image per font and
only a handful of files are ever open.

  python3 tools/sprites.py [--fonts DIR]

Writes src/WIDGETS/FPVDash/img/<theme>/<scale>/: <font>.png, w_<word>.png, patterns, and
fonts.lua with the metrics. Fonts are read from DIR (default tools/.fonts), and any that are
missing are downloaded from Google Fonts, which is what the designs load.
"""
import argparse
import io
import math
import os
import re
import urllib.request

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "src", "WIDGETS", "FPVDash", "img")
SD = "/WIDGETS/FPVDash/img"
MAX_W = 2000                      # LVGL 8 image headers hold at most 2047 px per side

FAMILIES = {
    "Barlow Semi Condensed": "BarlowSemiCondensed",
    "IBM Plex Mono": "IBMPlexMono",
    "Big Shoulders Display": "BigShouldersDisplay",
    "JetBrains Mono": "JetBrainsMono",
}
# families whose default digits are proportional but that carry tabular ones for 'tnum'
TNUM = {"Barlow Semi Condensed"}
# families with neither: besides their natural spacing ("adv"/"off"), the metrics carry a
# tabular one ("tadv"/"toff") with every digit centred on the width of "0"
PROPORTIONAL = {"Big Shoulders Display"}

DIGITS = "0123456789"
UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
TEXT = UPPER + DIGITS + " %.:-/+'!?#&()*,<>=_"
COORD = DIGITS + ".,- "

# Each theme: colours, glyph sheets (family, weight, px, characters, colour bands) and word
# images (family, weight, px, tracking in em, text, colour). Sizes are for 800x480. "~" in a
# sheet is drawn as the theme's dash, the placeholder for a missing value (the widget's Lua
# indexes characters by byte, so the sheets stay ASCII).
THEMES = {
    "cockpit": {
        "dash": "\u2013",
        "colors": {"fg": "#F2F0EA", "red": "#FF3B30", "amber": "#FFB020", "mute": "#4F4C46", "cyan": "#4FD1E6",
                   "bg": "#0A0A09", "line": "#2A2925", "pipOff": "#3A3934", "tick": "#6A675F"},
        "fonts": {
            "hero":  ("IBM Plex Mono", 600, 118, DIGITS + ".-~", ["fg", "red", "mute"]),
            "dist":  ("IBM Plex Mono", 600, 96, DIGITS + ".-~", ["fg", "mute"]),
            "seen":  ("IBM Plex Mono", 600, 72, DIGITS, ["fg"]),
            "big":   ("IBM Plex Mono", 600, 64, DIGITS + ".:-~", ["fg", "amber", "mute"]),
            "count": ("IBM Plex Mono", 600, 56, DIGITS, ["fg"]),
            "timer": ("IBM Plex Mono", 600, 46, DIGITS + ":-~", ["fg", "red", "mute"]),
            "stat":  ("IBM Plex Mono", 600, 40, DIGITS + ".:-~", ["fg", "mute"]),
            "nav":   ("IBM Plex Mono", 600, 32, DIGITS + ".:-~", ["fg", "amber", "mute"]),
            "gps":   ("IBM Plex Mono", 600, 24, DIGITS + "-~", ["fg", "amber", "red", "mute"]),
            "c22":   ("IBM Plex Mono", 400, 22, COORD, ["fg"]),
            "c26":   ("IBM Plex Mono", 500, 26, COORD, ["fg"]),
            "c30":   ("IBM Plex Mono", 500, 30, COORD, ["fg"]),
            "sw":    ("Barlow Semi Condensed", 600, 23, TEXT, ["fg", "cyan", "red", "amber"]),
        },
        "words": {
            "wait":   ("Barlow Semi Condensed", 700, 54, -0.005, "Waiting for the quad", "fg"),
            "sim":    ("Barlow Semi Condensed", 700, 54, -0.005, "Simulator mode", "fg"),
            "nohome": ("IBM Plex Mono", 600, 30, -0.03, "NO HOME", "amber"),
        },
    },
    "hivis": {
        "dash": "\u2014",
        "colors": {"ink": "#121210", "y": "#E6F43A", "red": "#FF4B1F", "ink35": "#121210@0.35"},
        "fonts": {
            # 235, not the spec's 250: the digits stand on the LAND line, with its tag below
            "bat":    ("Big Shoulders Display", 900, 235, DIGITS + ".", ["ink"]),
            "huge":   ("Big Shoulders Display", 900, 230, DIGITS + ".?", ["ink"]),
            "flight": ("Big Shoulders Display", 900, 200, DIGITS + ":", ["ink"]),
            "seen":   ("Big Shoulders Display", 900, 150, DIGITS, ["ink"]),
            "count":  ("Big Shoulders Display", 900, 120, DIGITS, ["ink"]),
            "hero":   ("Big Shoulders Display", 900, 118, DIGITS + ":", ["ink"]),
            "cell":   ("Big Shoulders Display", 900, 96, DIGITS + ".", ["ink", "y"]),
            "sum":    ("Big Shoulders Display", 900, 72, DIGITS + ".", ["ink"]),
            "stat":   ("Big Shoulders Display", 900, 64, DIGITS + ".:~", ["ink", "ink35"]),
            "strip":  ("Big Shoulders Display", 900, 46, DIGITS + ".:", ["ink", "y", "red"]),
            "chip":   ("Big Shoulders Display", 900, 30, TEXT, ["ink", "y", "red"]),
            "sw":     ("Big Shoulders Display", 800, 24, TEXT, ["ink", "y"]),
            "title":  ("Big Shoulders Display", 900, 34, UPPER + " ", ["y"]),
            "ago":    ("Big Shoulders Display", 800, 48, UPPER + " ", ["ink"]),
            "j24":    ("JetBrains Mono", 800, 24, COORD, ["y"]),
            "j30":    ("JetBrains Mono", 800, 30, COORD, ["red"]),
            "j34":    ("JetBrains Mono", 800, 34, COORD, ["ink"]),
        },
        "words": {
            "wait":     ("Big Shoulders Display", 900, 210, -0.01, "WAITING", "ink"),
            "sim":      ("Big Shoulders Display", 900, 300, -0.01, "SIM", "y"),
            "nohome":   ("Big Shoulders Display", 900, 52, -0.01, "NO HOME", "y"),
            "nohome_r": ("Big Shoulders Display", 900, 52, -0.01, "NO HOME", "red"),
        },
        # px on the small screens, where EdgeTX's label fonts shrink less than the layout: at 60% the
        # battery digits would reach the labels above them
        "small": {"bat": 128},
    },
}
SCALES = {"100": 1.0, "60": 0.6}
MIN_PX = 10


def rgba(spec):
    hexpart, _, alpha = spec.partition("@")
    h = hexpart.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), int(round(255 * float(alpha or 1))))


# fonts ----------------------------------------------------------------------------------------

def fetch(family, weight, folder):
    """Download the Latin subset Google Fonts serves for a family and weight, as TTF."""
    from fontTools.ttLib import TTFont
    url = "https://fonts.googleapis.com/css2?family=%s:wght@%d" % (family.replace(" ", "+"), weight)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Macintosh) AppleWebKit/537.36 Chrome/120"})
    css = urllib.request.urlopen(req).read().decode()
    m = re.search(r"/\* latin \*/\s*@font-face\s*\{[^}]*?url\((https://[^)]+)\)", css)
    data = urllib.request.urlopen(m.group(1)).read()
    font = TTFont(io.BytesIO(data))
    font.flavor = None
    path = os.path.join(folder, "%s-%d.ttf" % (FAMILIES[family], weight))
    font.save(path)
    return path


def font_path(family, weight, folder):
    path = os.path.join(folder, "%s-%d.ttf" % (FAMILIES[family], weight))
    if not os.path.exists(path):
        os.makedirs(folder, exist_ok=True)
        print("downloading", family, weight)
        fetch(family, weight, folder)
    path = static(path, weight)
    if family in TNUM:
        path = tabular(path)
    return path


def static(path, weight):
    """Google Fonts serves some families as variable fonts; Pillow draws their default instance."""
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer
    font = TTFont(path)
    if "fvar" not in font:
        return path
    out = path[:-4] + "-static.ttf"
    if os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(path):
        return out
    instancer.instantiateVariableFont(font, {"wght": weight}, inplace=True)
    font.save(out)
    return out


def tabular(path):
    """A copy of the font whose digits map to its tabular figures."""
    from fontTools.ttLib import TTFont
    out = re.sub(r"(-static)?\.ttf$", "-tnum.ttf", path)
    if os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(path):
        return out
    font = TTFont(path)
    cmap = font.getBestCmap()
    gsub = font["GSUB"].table
    swap = {}
    for rec in gsub.FeatureList.FeatureRecord:
        if rec.FeatureTag != "tnum":
            continue
        for i in rec.Feature.LookupListIndex:
            for st in gsub.LookupList.Lookup[i].SubTable:
                st = getattr(st, "ExtSubTable", st)
                swap.update(getattr(st, "mapping", {}) or {})
    for table in font["cmap"].tables:
        for code in list(table.cmap):
            if chr(code) in DIGITS and table.cmap[code] in swap:
                table.cmap[code] = swap[table.cmap[code]]
    font.save(out)
    return out


# rendering ------------------------------------------------------------------------------------

def sheet(name, spec, colors, scale, folder, outdir, sdir, dash, px=None):
    family, weight, size, chars, bands = spec
    px = px or max(MIN_PX, int(round(size * scale)))
    font = ImageFont.truetype(font_path(family, weight, folder), px)
    chars = " " + chars                              # cell 1 is blank
    glyph = {c: (dash if c == "~" else c) for c in chars}
    boxes = {c: font.getbbox(glyph[c], anchor="ls") for c in chars}
    adv = {c: font.getlength(glyph[c]) for c in chars}
    tabular = family in PROPORTIONAL and any(c in DIGITS for c in chars)
    tab = font.getlength("0")
    tadv = {c: (tab if c in DIGITS else adv[c]) for c in chars}
    tshift = {c: ((tab - adv[c]) / 2 if c in DIGITS else 0.0) for c in chars}
    ink = [b for c, b in boxes.items() if c != " "]
    asc = max(-b[1] for b in ink)
    desc = max(max(b[3] for b in ink), 0)
    pad = max(2, px // 24)
    cw = int(math.ceil(max(b[2] - b[0] for b in ink))) + 2 * pad
    rh = int(math.ceil(asc + desc)) + 2 * pad
    base = pad + int(math.ceil(asc))
    cols = max(1, min(len(chars), MAX_W // cw))
    lines = int(math.ceil(len(chars) / cols))
    span = lines * rh                                  # one colour band
    img = Image.new("RGBA", (cols * cw, span * len(bands)), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    sx, sy, off, toff = [], [], [], []
    for k, c in enumerate(chars):
        col, line = k % cols, k // cols
        x0 = boxes[c][0] if c != " " else 0
        sx.append(col * cw)
        sy.append(line * rh)
        off.append(round(x0 - pad, 2))
        toff.append(round(x0 - pad + tshift[c], 2))
        if c == " ":
            continue
        for band, color in enumerate(bands):
            draw.text((col * cw + pad - x0, band * span + line * rh + base), glyph[c], font=font,
                      fill=rgba(colors[color]), anchor="ls")
    fname = name + ".png"
    img.save(os.path.join(outdir, fname), optimize=True)
    meta = {
        "f": "%s/%s" % (sdir, fname), "w": img.width, "h": img.height, "cw": cw, "rh": rh, "base": base,
        "span": span, "px": px, "chars": chars, "rows": {b: i for i, b in enumerate(bands)},
        "adv": [round(adv[c], 2) for c in chars], "off": off, "sx": sx, "sy": sy,
    }
    if tabular:
        meta["tadv"], meta["toff"] = [round(tadv[c], 2) for c in chars], toff
    return meta


def word(name, spec, colors, scale, folder, outdir, sdir):
    family, weight, px, track, text, color = spec
    px = max(MIN_PX, int(round(px * scale)))
    font = ImageFont.truetype(font_path(family, weight, folder), px)
    # advances with kerning, plus the design's letter-spacing
    pens, x = [], 0.0
    for i, c in enumerate(text):
        pens.append(x)
        nxt = text[i + 1] if i + 1 < len(text) else ""
        a = (font.getlength(c + nxt) - font.getlength(nxt)) if nxt else font.getlength(c)
        x += a + track * px
    width = x - track * px
    ink = [font.getbbox(c, anchor="ls") for c in text]
    x0 = min(p + b[0] for p, b in zip(pens, ink))
    x1 = max(p + b[2] for p, b in zip(pens, ink))
    asc = max(-b[1] for b in ink)
    desc = max(max(b[3] for b in ink), 0)
    pad = max(2, px // 24)
    w, h = int(math.ceil(x1 - x0)) + 2 * pad, int(math.ceil(asc + desc)) + 2 * pad
    base = pad + int(math.ceil(asc))
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for p, c in zip(pens, text):
        draw.text((pad - x0 + p, base), c, font=font, fill=rgba(colors[color]), anchor="ls")
    fname = "w_%s.png" % name
    img.save(os.path.join(outdir, fname), optimize=True)
    return {"f": "%s/%s" % (sdir, fname), "w": w, "h": h, "base": base, "off": round(x0 - pad, 2),
            "adv": round(width, 2)}


def gradient(w, h, angle, stops, period, ss=4):
    """CSS repeating-linear-gradient with hard stops, supersampled: stops are (start px, rgba)."""
    a = math.radians(angle)
    dx, dy = math.sin(a), -math.cos(a)
    length = abs(w * dx) + abs(h * dy)
    big = Image.new("RGBA", (w * ss, h * ss))
    px = big.load()
    cx, cy = w / 2, h / 2
    for yy in range(h * ss):
        y = (yy + 0.5) / ss
        for xx in range(w * ss):
            x = (xx + 0.5) / ss
            t = ((x - cx) * dx + (y - cy) * dy + length / 2) % period
            col = stops[0][1]
            for start, c in stops:
                if t >= start:
                    col = c
            px[xx, yy] = col
    return big.resize((w, h), Image.LANCZOS)


def plan(colors, scale, folder, outdir, sdir):
    """Glass Cockpit's plan view face: rings, 10 degree ticks and N, on the ground colour."""
    s = lambda n: n * scale
    size = max(1, int(round(312 * scale)))
    ss = 4
    img = Image.new("RGB", (size * ss, size * ss), rgba(colors["bg"])[:3])
    d = ImageDraw.Draw(img)
    c = size * ss / 2
    q = lambda n: s(n) * ss

    def ring(r, width, color, dash=None):
        box = [c - q(r), c - q(r), c + q(r), c + q(r)]
        if not dash:
            d.ellipse(box, outline=rgba(colors[color]), width=max(1, int(round(q(width)))))
            return
        on, off = dash
        steps = int(2 * math.pi * r / (on + off))
        for i in range(steps):
            a0 = i * 360 / steps
            d.arc(box, a0, a0 + 360 / steps * on / (on + off), fill=rgba(colors[color]),
                  width=max(1, int(round(q(width)))))

    ring(130, 1.5, "pipOff")
    ring(65, 1, "line", (3, 5))
    for deg in range(0, 360, 10):
        length = 12 if deg % 90 == 0 else 7 if deg % 30 == 0 else 3
        color = "fg" if deg == 0 else "tick" if deg % 30 == 0 else "pipOff"
        width = 2 if deg % 90 == 0 else 1.2
        a = math.radians(deg)
        p0 = (c + math.sin(a) * q(130), c - math.cos(a) * q(130))
        p1 = (c + math.sin(a) * q(130 + length), c - math.cos(a) * q(130 + length))
        d.line([p0, p1], fill=rgba(colors[color]), width=max(1, int(round(q(width)))))
    font = ImageFont.truetype(font_path("IBM Plex Mono", 600, folder), max(MIN_PX, int(round(13 * scale))) * ss)
    d.text((c, q(11)), "N", font=font, fill=rgba(colors["fg"]), anchor="ms")
    img = img.resize((size, size), Image.LANCZOS)
    img.save(os.path.join(outdir, "plan.png"), optimize=True)
    return {"plan": {"f": "%s/plan.png" % sdir, "w": size, "h": size}}


def patterns(colors, scale, outdir, sdir):
    s = lambda n: max(1, int(round(n * scale)))
    ink, y, red, clear = rgba(colors["ink"]), rgba(colors["y"]), rgba(colors["red"]), (0, 0, 0, 0)
    out = {}
    band_w, band_h = s(800), s(44)
    for name, a, b in (("haz_iy", ink, y), ("haz_ir", ink, red), ("haz_yi", y, ink)):
        img = gradient(band_w, band_h, -45, [(0, a), (s(18), b)], s(36))
        img.convert("RGB").save(os.path.join(outdir, name + ".png"), optimize=True)
        out[name] = {"f": "%s/%s.png" % (sdir, name), "w": band_w, "h": band_h}
    hw, hh = s(468), s(290)
    img = gradient(hw, hh, 45, [(0, ink), (s(2), clear)], s(9))
    img.save(os.path.join(outdir, "hatch.png"), optimize=True)
    out["hatch"] = {"f": "%s/hatch.png" % sdir, "w": hw, "h": hh}
    return out


# Lua ------------------------------------------------------------------------------------------

def lua(v, indent=""):
    if isinstance(v, dict):
        inner = indent + "  "
        items = []
        for k in sorted(v):
            key = k if re.match(r"^[A-Za-z_]\w*$", k) else "[%s]" % lua(k)
            items.append("%s%s = %s" % (inner, key, lua(v[k], inner)))
        return "{\n" + ",\n".join(items) + ",\n" + indent + "}"
    if isinstance(v, list):
        return "{ " + ", ".join(lua(x, indent) for x in v) + " }"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts", default=os.path.join(HERE, ".fonts"))
    args = ap.parse_args()
    for theme, t in THEMES.items():
        for tag, scale in SCALES.items():
            outdir = os.path.join(OUT, theme, tag)
            os.makedirs(outdir, exist_ok=True)
            for old in os.listdir(outdir):
                os.remove(os.path.join(outdir, old))
            sdir = "%s/%s/%s" % (SD, theme, tag)
            small = t.get("small", {}) if scale < 1 else {}
            meta = {name: sheet(name, spec, t["colors"], scale, args.fonts, outdir, sdir, t["dash"], small.get(name))
                    for name, spec in t["fonts"].items()}
            meta["words"] = {name: word(name, spec, t["colors"], scale, args.fonts, outdir, sdir)
                             for name, spec in t["words"].items()}
            if theme == "hivis":
                meta["patterns"] = patterns(t["colors"], scale, outdir, sdir)
            else:
                meta["patterns"] = plan(t["colors"], scale, args.fonts, outdir, sdir)
            with open(os.path.join(outdir, "fonts.lua"), "w") as f:
                f.write("-- generated by tools/sprites.py\nreturn %s\n" % lua(meta))
            size = sum(os.path.getsize(os.path.join(outdir, n)) for n in os.listdir(outdir))
            print("%-8s %-3s %2d files %7d bytes" % (theme, tag, len(os.listdir(outdir)), size))


if __name__ == "__main__":
    main()
