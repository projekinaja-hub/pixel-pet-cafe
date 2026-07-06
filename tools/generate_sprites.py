#!/usr/bin/env python3
"""Pixel Pet Café sprite generator.

Generates every game sprite as RGBA PNGs into Sources/PixelPetCafe/Resources/Sprites.
Pure stdlib (zlib + struct). Deterministic. Re-run after editing art.
"""
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "PixelPetCafe", "Resources", "Sprites")

# ---------------------------------------------------------------- PNG writer

def write_png(path, w, h, px):
    """px: list of rows, each row list of (r,g,b,a)."""
    raw = b"".join(b"\x00" + b"".join(struct.pack("4B", *p) for p in row) for row in px)
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)

# ---------------------------------------------------------------- canvas

CLEAR = (0, 0, 0, 0)

class Canvas:
    def __init__(self, w, h, bg=CLEAR):
        self.w, self.h = w, h
        self.px = [[bg] * w for _ in range(h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.px[y][x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def hline(self, x, y, w, c):
        self.rect(x, y, w, 1, c)

    def vline(self, x, y, h, c):
        self.rect(x, y, 1, h, c)

    def blit(self, other, ox, oy):
        for yy in range(other.h):
            for xx in range(other.w):
                p = other.px[yy][xx]
                if p[3] > 0:
                    self.set(ox + xx, oy + yy, p)

    def shifted_down(self):
        c = Canvas(self.w, self.h)
        for y in range(self.h - 1):
            c.px[y + 1] = list(self.px[y])
        return c

    def save(self, name):
        write_png(os.path.join(OUT, name), self.w, self.h, self.px)

# ---------------------------------------------------------------- palette

INK    = (52, 34, 41, 255)     # dark outline
CREAM  = (247, 233, 205, 255)
WHITE  = (252, 250, 244, 255)
GOLD   = (249, 185, 24, 255)
GOLD_D = (196, 138, 14, 255)
WOOD   = (166, 110, 62, 255)
WOOD_D = (124, 78, 44, 255)
WOOD_L = (198, 143, 89, 255)
RED    = (203, 82, 74, 255)
GREEN  = (96, 153, 92, 255)
GREEN_D= (62, 110, 66, 255)
BLUE   = (94, 129, 181, 255)
PINK   = (233, 158, 160, 255)
SKY    = (176, 213, 227, 255)

# ---------------------------------------------------------------- characters
# 16x20 chibi animals. Parametric builder keeps a consistent style.

def character(fur, fur_d, belly, apron, species, accent=None):
    c = Canvas(16, 20)
    # --- ears / head top by species
    if species in ("cat", "fox"):
        inner = PINK if species == "cat" else fur_d
        for x0 in (2, 11):
            c.set(x0 + 1, 0, INK)
            c.set(x0, 1, INK); c.set(x0 + 2, 1, INK); c.set(x0 + 1, 1, fur)
            c.set(x0, 2, INK); c.set(x0 + 2, 2, INK); c.set(x0 + 1, 2, inner)
    elif species == "bunny":
        for x0 in (4, 9):
            c.rect(x0, 0, 3, 4, fur); c.vline(x0, 0, 4, INK); c.vline(x0 + 2, 0, 4, INK)
            c.set(x0 + 1, 0, INK); c.set(x0 + 1, 1, PINK); c.set(x0 + 1, 2, PINK)
    elif species in ("corgi", "bear", "raccoon"):
        for x0 in (2, 11):
            c.rect(x0, 2, 3, 2, fur_d)
            c.set(x0, 2, INK); c.set(x0 + 2, 2, INK); c.set(x0 + 1, 1, INK)
    elif species == "owl":
        c.set(3, 2, INK); c.set(12, 2, INK)  # small tufts
        c.set(3, 3, fur_d); c.set(12, 3, fur_d)
    # --- head (rows 3..11)
    c.rect(3, 4, 10, 8, fur)
    c.hline(4, 3, 8, fur)
    c.set(3, 3, INK)
    # outline head
    c.hline(4, 2, 8, INK)
    c.vline(3, 3, 1, INK); c.vline(12, 3, 1, INK)
    c.vline(2, 4, 7, INK); c.vline(13, 4, 7, INK)
    c.rect(3, 4, 1, 7, fur_d); c.rect(12, 4, 1, 7, fur_d)
    c.set(3, 11, INK); c.set(12, 11, INK)
    c.hline(4, 12, 8, INK)
    # face plate
    if species in ("fox", "corgi", "bunny", "cat", "raccoon"):
        c.rect(5, 8, 6, 4, belly)
    if species == "owl":
        c.rect(4, 5, 3, 4, WHITE); c.rect(9, 5, 3, 4, WHITE)
    if species == "raccoon":  # bandit mask
        c.rect(4, 5, 8, 3, (72, 62, 78, 255))
    # eyes (with glint)
    ey = 6
    c.set(5, ey, INK); c.set(10, ey, INK)
    c.set(5, ey + 1, INK); c.set(10, ey + 1, INK)
    c.set(5, ey, (90, 74, 82, 255))
    # nose / beak / mouth
    if species == "owl":
        c.set(7, 7, GOLD_D); c.set(8, 7, GOLD_D)
    else:
        nose = accent or PINK
        c.set(7, 8, nose); c.set(8, 8, nose)
        c.set(7, 10, INK); c.set(8, 10, INK)
    # --- body (rows 13..18)
    c.rect(4, 13, 8, 5, fur)
    c.vline(3, 13, 5, INK); c.vline(12, 13, 5, INK)
    c.rect(4, 13, 1, 5, fur_d); c.rect(11, 13, 1, 5, fur_d)
    # apron / shirt
    if apron:
        c.rect(5, 13, 6, 5, apron)
        c.hline(5, 13, 6, WOOD_D)
        c.set(7, 15, GOLD); c.set(8, 15, GOLD)  # pocket stitch
    # arms
    c.set(3, 14, fur); c.set(12, 14, fur)
    # feet
    c.hline(4, 18, 3, INK); c.hline(9, 18, 3, INK)
    c.hline(4, 19, 3, fur_d); c.hline(9, 19, 3, fur_d)
    return c

STAFF = {
    #        fur                fur_dark           belly   apron   species accent
    "mocha":   ((150, 102, 66, 255), (112, 72, 46, 255), CREAM, (206, 106, 76, 255), "cat", None),
    "biscuit": ((222, 158, 90, 255), (176, 116, 60, 255), CREAM, (96, 129, 171, 255), "corgi", INK),
    "poppy":   ((228, 214, 202, 255), (186, 168, 155, 255), WHITE, PINK, "bunny", None),
    "juno":    ((212, 110, 58, 255), (160, 76, 38, 255), WHITE, (74, 110, 88, 255), "fox", INK),
    "bo":      ((122, 88, 62, 255), (88, 60, 42, 255), (168, 132, 100, 255), (150, 68, 60, 255), "bear", INK),
    "earl":    ((138, 120, 150, 255), (100, 84, 114, 255), WHITE, (46, 58, 92, 255), "owl", None),
    "marble":  ((172, 168, 178, 255), (120, 116, 130, 255), CREAM, (90, 74, 52, 255), "raccoon", INK),
}

CUSTOMERS = [
    ((196, 170, 140, 255), (150, 126, 100, 255), CREAM, (120, 144, 96, 255), "cat", None),
    ((170, 138, 108, 255), (128, 100, 76, 255), CREAM, (168, 120, 150, 255), "bear", INK),
    ((236, 226, 214, 255), (192, 180, 166, 255), WHITE, (98, 124, 160, 255), "bunny", None),
]

# ---------------------------------------------------------------- equipment

def espresso(tier):
    c = Canvas(20, 16)
    body = [(140, 140, 150, 255), (176, 60, 54, 255), (210, 168, 60, 255)][tier]
    body_d = tuple(max(0, v - 40) for v in body[:3]) + (255,)
    c.rect(2, 3, 16, 10, body)
    c.rect(2, 3, 16, 2, body_d)
    c.rect(1, 2, 18, 1, INK); c.rect(1, 13, 18, 1, INK)
    c.vline(1, 2, 12, INK); c.vline(18, 2, 12, INK)
    c.rect(5, 9, 2, 3, INK); c.rect(12, 9, 2, 3, INK)      # group heads
    c.rect(4, 13, 4, 2, (230, 230, 235, 255)); c.rect(11, 13, 4, 2, (230, 230, 235, 255))  # cups
    c.set(16, 5, WHITE); c.set(17, 4, WHITE)               # steam glint
    if tier >= 1:
        c.rect(8, 5, 4, 2, GOLD)                           # brand badge
    if tier >= 2:
        c.hline(2, 3, 16, GOLD_D)                          # gold trim
    return c

def oven(tier):
    c = Canvas(22, 18)
    body = [(112, 116, 124, 255), (96, 116, 140, 255), (66, 106, 96, 255)][tier]
    c.rect(1, 2, 20, 15, body)
    c.rect(1, 2, 20, 1, INK); c.rect(1, 16, 20, 1, INK)
    c.vline(1, 2, 15, INK); c.vline(20, 2, 15, INK)
    c.rect(4, 6, 14, 8, INK)
    glow = [(240, 170, 90, 255), (250, 190, 110, 255), (255, 210, 130, 255)][tier]
    c.rect(5, 7, 12, 6, glow)
    c.rect(7, 11, 8, 2, (196, 130, 62, 255))               # bread
    c.hline(4, 4, 6, INK)                                  # handle
    if tier >= 1:
        c.set(17, 4, RED)                                  # temp light
    if tier >= 2:
        c.rect(2, 3, 18, 1, GOLD_D)
    return c

def grinder(tier):
    c = Canvas(12, 16)
    body = [(150, 120, 96, 255), (120, 120, 132, 255), (60, 60, 70, 255)][tier]
    c.rect(3, 1, 6, 4, (210, 220, 228, 200))               # hopper
    c.rect(3, 1, 6, 1, INK)
    c.rect(2, 5, 8, 9, body)
    c.vline(2, 5, 9, INK); c.vline(9, 5, 9, INK)
    c.hline(2, 14, 8, INK)
    c.rect(4, 8, 4, 2, INK)                                # chute
    if tier >= 1:
        c.set(6, 11, GOLD)
    if tier >= 2:
        c.rect(3, 5, 6, 1, GOLD_D)
    return c

def decor(tier):
    c = Canvas(14, 18)
    pot = (188, 96, 64, 255)
    c.rect(4, 13, 6, 4, pot); c.hline(4, 13, 6, INK); c.hline(4, 16, 6, INK)
    c.vline(4, 13, 4, INK); c.vline(9, 13, 4, INK)
    leaves = [GREEN, GREEN, GREEN_D][tier]
    c.rect(5, 8, 4, 5, leaves)
    c.set(4, 10, leaves); c.set(9, 10, leaves)
    c.set(6, 7, GREEN_D); c.set(8, 7, GREEN_D)
    if tier >= 1:
        c.set(3, 8, leaves); c.set(10, 8, leaves); c.set(7, 5, GREEN_D); c.set(7, 6, GREEN)
    if tier >= 2:
        for x, y in ((4, 7), (9, 6), (6, 4)):
            c.set(x, y, PINK)                              # flowers
    return c

def sound(tier):
    c = Canvas(14, 16)
    if tier == 0:                                          # small radio
        c.rect(2, 6, 10, 8, WOOD)
        c.rect(2, 6, 10, 1, INK); c.rect(2, 13, 10, 1, INK)
        c.vline(2, 6, 8, INK); c.vline(11, 6, 8, INK)
        c.rect(4, 8, 3, 4, INK); c.set(9, 9, GOLD)
    else:                                                  # gramophone
        c.rect(4, 10, 6, 4, WOOD)
        c.hline(4, 14, 6, INK)
        horn = GOLD if tier >= 2 else (196, 168, 130, 255)
        c.set(7, 9, INK)
        c.rect(6, 4, 5, 4, horn)
        c.set(5, 3, horn); c.set(11, 3, horn)
        c.hline(5, 2, 7, INK)
    c.set(1, 5, (200, 200, 210, 180)); c.set(12, 3, (200, 200, 210, 180))  # notes
    return c

EQUIP = {"espresso": espresso, "oven": oven, "grinder": grinder, "decor": decor, "sound": sound}

# ---------------------------------------------------------------- small props

def tip_coin():
    c = Canvas(12, 12)
    c.rect(3, 2, 6, 8, GOLD)
    c.vline(2, 3, 6, GOLD); c.vline(9, 3, 6, GOLD)
    c.vline(2, 3, 6, GOLD_D)
    c.hline(3, 2, 6, (255, 224, 130, 255))
    c.rect(5, 4, 2, 4, GOLD_D)                             # ¢ mark
    c.set(0, 0, WHITE); c.set(11, 1, WHITE); c.set(1, 10, WHITE)  # sparkles
    return c

def recipe_bubble():
    c = Canvas(14, 12)
    c.rect(1, 1, 12, 8, WHITE)
    c.hline(2, 0, 10, WHITE)
    c.set(3, 9, WHITE); c.set(4, 10, WHITE)                # tail
    c.rect(4, 3, 6, 4, (222, 168, 92, 255))                # croissant-ish treat
    c.set(4, 3, CLEAR); c.set(9, 3, CLEAR)
    return c

# ---------------------------------------------------------------- bar icon (18x18 cat face)

def baricon(frame):
    c = Canvas(18, 18)
    fur, fur_d = STAFF["mocha"][0], STAFF["mocha"][1]
    # pointy cat ears
    for x0 in (2, 12):
        c.set(x0 + 1, 0, INK)
        c.set(x0, 1, INK); c.set(x0 + 2, 1, INK); c.set(x0 + 1, 1, fur)
        c.set(x0, 2, INK); c.set(x0 + 2, 2, INK); c.set(x0 + 1, 2, PINK)
    # head (rounded)
    c.rect(2, 4, 14, 11, fur)
    c.hline(3, 3, 12, fur)
    c.hline(4, 2, 10, INK)
    c.set(3, 3, INK); c.set(14, 3, INK)
    c.vline(2, 4, 1, INK); c.vline(15, 4, 1, INK)
    c.vline(1, 5, 9, INK); c.vline(16, 5, 9, INK)
    c.set(2, 14, INK); c.set(15, 14, INK)
    c.hline(3, 15, 12, INK)
    c.rect(2, 5, 1, 9, fur_d); c.rect(15, 5, 1, 9, fur_d)
    # muzzle
    c.rect(5, 9, 8, 5, CREAM)
    # eyes: frame 1 = blink
    if frame == 1:
        c.hline(5, 8, 2, INK); c.hline(11, 8, 2, INK)
    else:
        c.rect(5, 7, 2, 2, INK); c.rect(11, 7, 2, 2, INK)
    c.set(8, 10, PINK); c.set(9, 10, PINK)
    if frame == 3:                                         # sip: cup in front
        c.rect(6, 13, 6, 4, (206, 106, 76, 255))
        c.hline(6, 12, 6, WHITE)                           # foam
        c.vline(5, 12, 5, INK); c.vline(12, 12, 5, INK)
        c.hline(6, 17, 6, INK)
        c.set(13, 13, INK); c.set(14, 14, INK); c.set(13, 15, INK)  # handle
        c.set(8, 10, (230, 230, 235, 220)); c.set(10, 9, (230, 230, 235, 180))  # steam
    else:
        c.set(7, 12, INK); c.set(8, 13, INK); c.set(9, 13, INK); c.set(10, 12, INK)      # smile
    return c

# ---------------------------------------------------------------- backgrounds 180x120

THEMES = {
    "home":   {"walls": [(226, 204, 172, 255), (222, 192, 178, 255), (198, 176, 202, 255)],
               "floors": [(214, 168, 118, 255), (206, 158, 108, 255), (168, 128, 96, 255)],
               "sky": SKY, "accent": GOLD},
    "sakura": {"walls": [(244, 216, 224, 255), (240, 204, 216, 255), (232, 188, 208, 255)],
               "floors": [(222, 186, 160, 255), (216, 176, 150, 255), (196, 152, 130, 255)],
               "sky": (198, 226, 240, 255), "accent": (238, 150, 170, 255)},
    "neon":   {"walls": [(56, 50, 78, 255), (60, 52, 86, 255), (68, 56, 98, 255)],
               "floors": [(74, 62, 84, 255), (68, 58, 80, 255), (60, 50, 72, 255)],
               "sky": (24, 22, 48, 255), "accent": (94, 230, 224, 255)},
    "seaside": {"walls": [(210, 232, 236, 255), (196, 224, 232, 255), (180, 214, 228, 255)],
               "floors": [(226, 202, 156, 255), (218, 192, 146, 255), (198, 170, 126, 255)],
               "sky": (140, 200, 226, 255), "accent": (240, 150, 90, 255)},
    "forest": {"walls": [(196, 212, 178, 255), (184, 204, 166, 255), (168, 192, 150, 255)],
               "floors": [(150, 124, 92, 255), (142, 116, 86, 255), (122, 98, 72, 255)],
               "sky": (168, 214, 170, 255), "accent": (110, 160, 90, 255)},
    "desert": {"walls": [(238, 214, 168, 255), (232, 204, 154, 255), (222, 190, 138, 255)],
               "floors": [(206, 158, 104, 255), (198, 150, 96, 255), (178, 132, 84, 255)],
               "sky": (250, 214, 150, 255), "accent": (220, 130, 70, 255)},
    "snowy":  {"walls": [(222, 230, 242, 255), (210, 220, 236, 255), (196, 208, 230, 255)],
               "floors": [(170, 150, 132, 255), (160, 142, 124, 255), (142, 124, 108, 255)],
               "sky": (200, 216, 236, 255), "accent": (150, 190, 235, 255)},
    "sunset": {"walls": [(240, 198, 170, 255), (236, 186, 158, 255), (226, 168, 144, 255)],
               "floors": [(184, 128, 100, 255), (176, 120, 94, 255), (158, 104, 82, 255)],
               "sky": (248, 170, 110, 255), "accent": (240, 120, 90, 255)},
    "ember":  {"walls": [(94, 58, 60, 255), (100, 62, 62, 255), (110, 68, 66, 255)],
               "floors": [(70, 46, 48, 255), (64, 42, 44, 255), (56, 36, 40, 255)],
               "sky": (200, 90, 50, 255), "accent": (250, 140, 60, 255)},
    "royal":  {"walls": [(120, 100, 150, 255), (126, 104, 158, 255), (136, 112, 170, 255)],
               "floors": [(96, 76, 110, 255), (90, 70, 104, 255), (78, 60, 92, 255)],
               "sky": (150, 130, 190, 255), "accent": (250, 210, 110, 255)},
    "cloud":  {"walls": [(216, 226, 246, 255), (208, 218, 242, 255), (198, 208, 238, 255)],
               "floors": [(236, 240, 250, 255), (228, 232, 246, 255), (212, 218, 238, 255)],
               "sky": (176, 208, 248, 255), "accent": (255, 226, 150, 255)},
}

def _shade(col, f):
    return (min(255, int(col[0] * f)), min(255, int(col[1] * f)),
            min(255, int(col[2] * f)), 255)

def background(tier, theme="home"):
    W, H = 180, 120
    th = THEMES[theme]
    wall = th["walls"][tier]
    wall_d = tuple(max(0, v - 24) for v in wall[:3]) + (255,)
    c = Canvas(W, H, wall)
    # wall vertical gradient with dither (darker toward the floor)
    for y in range(0, 58):
        f = 1.09 - 0.24 * (y / 58)
        for x in range(W):
            if y > 34 and (x + y) % 2 == 0:
                c.px[y][x] = _shade(wall, f - 0.03)
            else:
                c.px[y][x] = _shade(wall, f)
    # wainscot
    c.rect(0, 58, W, 14, WOOD_D)
    c.rect(0, 58, W, 2, INK)
    for x in range(0, W, 12):
        c.vline(x, 60, 12, (100, 62, 36, 255))
    # floor
    floor_a = th["floors"][tier]
    floor_shadow = _shade(floor_a, 0.72)
    floor_b = tuple(max(0, v - 22) for v in floor_a[:3]) + (255,)
    c.rect(0, 72, W, H - 72, floor_a)
    for y in range(72, H, 8):
        for x in range(0, W, 16):
            if ((x // 16) + (y // 8)) % 2 == 0:
                c.rect(x, y, 16, 8, floor_b)
        c.hline(0, y, W, _shade(floor_a, 0.62))
    # floor shading: darker strip at the wall line + soft side falloff
    c.rect(0, 72, W, 2, floor_shadow)
    for y in range(72, H):
        for x in list(range(0, 6)) + list(range(W - 6, W)):
            if (x + y) % 2 == 0:
                c.px[y][x] = _shade(c.px[y][x], 0.85)
    # window (left-center)
    c.rect(30, 12, 34, 38, INK)
    c.rect(32, 14, 30, 34, th["sky"])
    c.vline(46, 14, 34, INK); c.hline(32, 30, 30, INK)
    if theme == "neon":  # moon + stars
        c.rect(38, 18, 4, 4, (240, 236, 210, 255))
        c.set(52, 20, WHITE); c.set(57, 26, WHITE); c.set(44, 28, WHITE)
    elif theme == "sakura":  # blossom branch
        c.rect(36, 20, 22, 2, (120, 82, 60, 255))
        for px, py in ((38, 18), (44, 17), (50, 19), (56, 18), (41, 22), (53, 23)):
            c.set(px, py, (244, 168, 186, 255)); c.set(px + 1, py, (238, 150, 170, 255))
    else:
        c.set(38, 18, WHITE); c.set(39, 18, WHITE); c.set(40, 19, WHITE)   # cloud
        c.set(54, 24, WHITE); c.set(55, 24, WHITE)
    c.rect(28, 50, 38, 3, WOOD)                                       # sill
    # door (far left)
    c.rect(4, 22, 20, 50, WOOD)
    c.rect(4, 22, 20, 2, INK); c.vline(4, 22, 50, INK); c.vline(23, 22, 50, INK)
    c.rect(7, 26, 14, 18, SKY); c.rect(7, 26, 14, 1, INK); c.vline(7, 26, 18, INK); c.vline(20, 26, 18, INK); c.hline(7, 43, 14, INK)
    c.set(20, 50, GOLD)                                               # knob
    # counter (right)
    c.rect(96, 82, 74, 3, None)
    for x in range(96, 170):                                          # counter shadow
        for y in range(80, 86):
            if 0 <= y < H:
                c.px[y][x] = _shade(c.px[y][x], 0.8 if (x + y) % 2 else 0.86)
    c.rect(96, 52, 74, 6, WOOD_L)                                     # countertop
    c.rect(96, 52, 74, 1, INK)
    c.rect(98, 58, 70, 22, WOOD)
    c.rect(98, 78, 70, 2, WOOD_D)
    c.vline(98, 58, 22, INK); c.vline(167, 58, 22, INK)
    for x in range(104, 166, 12):
        c.vline(x, 60, 18, WOOD_D)
    # menu board above counter
    c.rect(112, 10, 44, 24, (72, 84, 76, 255))
    c.rect(112, 10, 44, 2, WOOD_D); c.rect(112, 32, 44, 2, WOOD_D)
    c.vline(112, 10, 24, INK); c.vline(155, 10, 24, INK)
    for i, w in enumerate((22, 16, 20)):
        c.hline(118, 16 + i * 5, w, (214, 224, 210, 255))
    # shelf with jars (between window and menu)
    c.rect(70, 20, 34, 3, WOOD)
    jars = [CREAM, (222, 168, 92, 255), GREEN, PINK]
    for i, jc in enumerate(jars):
        c.rect(72 + i * 8, 14, 5, 6, jc)
        c.hline(72 + i * 8, 13, 5, INK)
    # tables (floor) with shadows
    for tx in (36, 66):
        for x in range(tx - 2, tx + 24):
            for y in range(105, 109):
                if 0 <= x < W and 0 <= y < H and (x + y) % 2 == 0:
                    c.px[y][x] = _shade(c.px[y][x], 0.78)
        c.rect(tx, 88, 22, 4, WOOD_L)
        c.hline(tx, 88, 22, INK)
        c.hline(tx, 91, 22, _shade(WOOD_L, 0.8))
        c.rect(tx + 9, 92, 4, 12, WOOD_D)
        c.rect(tx + 6, 104, 10, 2, WOOD_D)
    # window light pooling on the floor
    if theme != "neon":
        for y in range(74, 96):
            for x in range(26 + (y - 74), 62 + (y - 74)):
                if 0 <= x < W and (x + y) % 2 == 0:
                    c.px[y][x] = tuple(min(255, int(v * 1.22)) for v in c.px[y][x][:3]) + (255,)
    # tier 1+: rug, wall art
    if tier >= 1:
        c.rect(120, 96, 46, 16, (172, 96, 84, 255))
        c.rect(122, 98, 42, 12, (198, 120, 100, 255))
        c.rect(74, 30, 14, 12, WOOD_D); c.rect(76, 32, 10, 8, (140, 180, 190, 255))  # picture
    # theme extras
    if theme == "sakura":  # falling petals
        for px, py in ((20, 80), (60, 95), (110, 86), (150, 100), (86, 108), (36, 104)):
            c.set(px, py, (244, 168, 186, 255))
    if theme == "neon":    # neon sign over the counter
        c.rect(110, 36, 48, 10, (30, 26, 48, 255))
        c.hline(112, 38, 44, (255, 96, 180, 255))
        c.hline(112, 41, 44, (94, 230, 224, 255))
        c.set(110, 36, INK); c.set(157, 36, INK)
    # tier 2: hanging lights, banner
    if tier >= 2:
        for x in range(20, W, 30):
            c.vline(x, 0, 5, INK)
            c.rect(x - 1, 5, 3, 3, th["accent"])
            c.set(x, 6, (255, 230, 150, 255))
        c.rect(126, 38, 18, 8, (150, 68, 60, 255))                    # ★ banner
        c.set(134, 41, GOLD); c.set(135, 41, GOLD)
    return c

# ---------------------------------------------------------------- main


# ---------------------------------------------------------------- v2: palettes

PALETTES = {
    "brown":  ((150, 102, 66, 255), (112, 72, 46, 255)),
    "cream":  ((228, 214, 202, 255), (186, 168, 155, 255)),
    "orange": ((212, 110, 58, 255), (160, 76, 38, 255)),
    "gray":   ((138, 130, 140, 255), (100, 92, 104, 255)),
}
SPECIES = ["cat", "corgi", "bunny", "fox", "bear", "owl"]
OWNER_APRON = (44, 62, 100, 255)  # navy owner apron with gold pin

def owner(species, pal):
    fur, fur_d = PALETTES[pal]
    c = character(fur, fur_d, CREAM, OWNER_APRON, species)
    c.set(7, 14, GOLD); c.set(8, 14, GOLD)  # gold pin
    return c

# ---------------------------------------------------------------- v2: accessories (16x20 overlays)

def acc_bow():
    c = Canvas(16, 20)
    for x in (5, 9):
        c.rect(x, 1, 2, 2, PINK)
    c.set(7, 1, (200, 110, 120, 255)); c.set(8, 1, (200, 110, 120, 255))
    c.set(7, 2, INK); c.set(8, 2, INK)
    return c

def acc_cap():
    c = Canvas(16, 20)
    c.rect(4, 1, 8, 2, BLUE)
    c.rect(3, 3, 10, 1, BLUE)
    c.rect(11, 3, 4, 1, (70, 100, 150, 255))  # brim
    c.hline(4, 0, 8, INK)
    return c

def acc_glasses():
    c = Canvas(16, 20)
    for x in (4, 9):
        c.rect(x, 5, 3, 3, None)
        c.hline(x, 5, 3, INK); c.hline(x, 7, 3, INK)
        c.vline(x, 5, 3, INK); c.vline(x + 2, 5, 3, INK)
    c.set(7, 6, INK); c.set(8, 6, INK)
    return c

def acc_scarf():
    c = Canvas(16, 20)
    c.rect(4, 12, 8, 2, RED)
    c.rect(9, 14, 2, 3, RED)
    c.set(9, 17, (150, 55, 50, 255))
    return c

ACCESSORIES = {"bow": acc_bow, "cap": acc_cap, "glasses": acc_glasses, "scarf": acc_scarf}

# ---------------------------------------------------------------- v2: face icons (18x18, 5 frames)

def face_icon(species, fur, fur_d, frame):
    """frames: 0 normal, 1 blink, 2 happy, 3 sleep, 4 sip"""
    c = Canvas(18, 18)
    # ears by species
    if species in ("cat", "fox"):
        inner = PINK if species == "cat" else fur_d
        for x0 in (2, 12):
            c.set(x0 + 1, 0, INK)
            c.set(x0, 1, INK); c.set(x0 + 2, 1, INK); c.set(x0 + 1, 1, fur)
            c.set(x0, 2, INK); c.set(x0 + 2, 2, INK); c.set(x0 + 1, 2, inner)
    elif species == "bunny":
        for x0 in (5, 10):
            c.rect(x0, 0, 3, 3, fur)
            c.vline(x0, 0, 3, INK); c.vline(x0 + 2, 0, 3, INK)
            c.set(x0 + 1, 1, PINK)
    elif species in ("corgi", "bear", "raccoon"):
        for x0 in (2, 12):
            c.rect(x0, 1, 3, 2, fur_d)
            c.set(x0, 1, INK); c.set(x0 + 2, 1, INK); c.set(x0 + 1, 0, INK)
    elif species == "owl":
        c.set(3, 1, INK); c.set(14, 1, INK)
        c.set(3, 2, fur_d); c.set(14, 2, fur_d)
    # head, rounded
    c.rect(2, 4, 14, 11, fur)
    c.hline(3, 3, 12, fur)
    c.hline(4, 2, 10, INK)
    c.set(3, 3, INK); c.set(14, 3, INK)
    c.vline(2, 4, 1, INK); c.vline(15, 4, 1, INK)
    c.vline(1, 5, 9, INK); c.vline(16, 5, 9, INK)
    c.set(2, 14, INK); c.set(15, 14, INK)
    c.hline(3, 15, 12, INK)
    c.rect(2, 5, 1, 9, fur_d); c.rect(15, 5, 1, 9, fur_d)
    if species == "owl":
        c.rect(3, 6, 5, 4, WHITE); c.rect(10, 6, 5, 4, WHITE)
    else:
        c.rect(5, 9, 8, 5, CREAM)
    if species == "raccoon":
        c.rect(3, 6, 12, 3, (72, 62, 78, 255))
    # eyes
    if frame == 1 or frame == 3:                      # blink / sleep
        c.hline(5, 8, 2, INK); c.hline(11, 8, 2, INK)
    elif frame == 2:                                  # happy ^ ^
        for x0 in (5, 11):
            c.set(x0, 8, INK); c.set(x0 + 1, 7, INK); c.set(x0 - 1, 8, INK)
    else:
        c.rect(5, 7, 2, 2, INK); c.rect(11, 7, 2, 2, INK)
    # nose / beak
    if species == "owl":
        c.set(8, 10, GOLD_D); c.set(9, 10, GOLD_D)
    else:
        c.set(8, 10, PINK); c.set(9, 10, PINK)
    # mouth / extras
    if frame == 3:                                    # sleep: zzz
        c.set(15, 1, WHITE); c.set(16, 2, WHITE); c.set(15, 3, WHITE)
        c.set(13, 4, (255, 255, 255, 180))
    if frame == 4:                                    # sip cup
        c.rect(6, 13, 6, 4, (206, 106, 76, 255))
        c.hline(6, 12, 6, WHITE)
        c.vline(5, 12, 5, INK); c.vline(12, 12, 5, INK)
        c.hline(6, 17, 6, INK)
        c.set(13, 13, INK); c.set(14, 14, INK); c.set(13, 15, INK)
    elif frame == 2:
        c.set(7, 12, INK); c.set(8, 13, INK); c.set(9, 13, INK); c.set(10, 12, INK)
        c.set(4, 11, (240, 150, 150, 200)); c.set(13, 11, (240, 150, 150, 200))  # blush
        c.set(0, 0, GOLD); c.set(17, 5, GOLD)                                    # sparkle
    elif frame != 3:
        c.set(7, 12, INK); c.set(8, 13, INK); c.set(9, 13, INK); c.set(10, 12, INK)
    return c

# ---------------------------------------------------------------- v2: ingredient icons (10x10)

def _icon(draw):
    c = Canvas(10, 10)
    draw(c)
    return c

ING_ICONS = {
    "beans":  lambda c: [c.rect(2, 3, 3, 4, (120, 78, 48, 255)), c.rect(5, 4, 3, 4, (140, 92, 56, 255)),
                         c.vline(3, 4, 2, INK), c.vline(6, 5, 2, INK)],
    "milk":   lambda c: [c.rect(3, 2, 4, 6, WHITE), c.hline(3, 2, 4, BLUE), c.hline(3, 1, 4, INK),
                         c.vline(2, 2, 6, INK), c.vline(7, 2, 6, INK), c.hline(3, 8, 4, INK)],
    "flour":  lambda c: [c.rect(2, 3, 6, 5, (232, 222, 200, 255)), c.hline(2, 2, 6, INK),
                         c.vline(1, 3, 5, INK), c.vline(8, 3, 5, INK), c.hline(2, 8, 6, INK),
                         c.hline(3, 5, 4, (196, 180, 150, 255))],
    "sugar":  lambda c: [c.rect(2, 4, 3, 3, WHITE), c.rect(5, 3, 3, 3, (240, 240, 245, 255)),
                         c.vline(2, 4, 3, (210, 210, 220, 255))],
    "matcha": lambda c: [c.rect(2, 5, 6, 3, (96, 153, 92, 255)), c.hline(2, 4, 6, (120, 175, 110, 255)),
                         c.hline(2, 8, 6, INK), c.set(4, 2, GREEN_D), c.set(6, 3, GREEN_D)],
    "cocoa":  lambda c: [c.rect(2, 3, 6, 5, (94, 62, 44, 255)), c.hline(2, 3, 6, (118, 80, 56, 255)),
                         c.vline(4, 3, 5, INK), c.vline(6, 3, 5, INK)],
    "berry":  lambda c: [c.rect(3, 4, 4, 4, RED), c.set(2, 5, RED), c.set(7, 5, RED),
                         c.set(4, 3, GREEN), c.set(5, 2, GREEN_D), c.set(4, 5, WHITE), c.set(6, 6, WHITE)],
    "honey":  lambda c: [c.rect(3, 4, 5, 4, GOLD), c.hline(3, 3, 5, GOLD_D), c.hline(4, 2, 3, INK),
                         c.hline(3, 8, 5, INK), c.set(4, 5, (255, 224, 130, 255))],
}

ITEM_ICONS = {
    "espresso":  lambda c: [c.rect(2, 4, 5, 4, WHITE), c.hline(2, 8, 5, INK), c.set(7, 5, INK),
                            c.set(8, 5, INK), c.set(8, 6, INK), c.set(7, 7, INK),
                            c.rect(3, 5, 3, 1, (120, 78, 48, 255)), c.set(4, 2, (200,200,210,180))],
    "latte":     lambda c: [c.rect(3, 2, 4, 6, (222, 198, 168, 255)), c.hline(3, 2, 4, WHITE),
                            c.hline(3, 1, 4, WHITE), c.vline(2, 2, 6, INK), c.vline(7, 2, 6, INK),
                            c.hline(3, 8, 4, INK)],
    "croissant": lambda c: [c.rect(3, 4, 4, 3, (222, 168, 92, 255)), c.set(2, 5, (222, 168, 92, 255)),
                            c.set(7, 5, (222, 168, 92, 255)), c.set(1, 4, (196, 138, 70, 255)),
                            c.set(8, 4, (196, 138, 70, 255)), c.vline(4, 4, 3, (196, 138, 70, 255))],
    "matcha_latte": lambda c: [c.rect(3, 3, 4, 5, (140, 190, 120, 255)), c.hline(3, 3, 4, WHITE),
                            c.vline(2, 3, 5, INK), c.vline(7, 3, 5, INK), c.hline(3, 8, 4, INK)],
    "cocoa":     lambda c: [c.rect(3, 3, 5, 5, (118, 80, 56, 255)), c.set(4, 3, WHITE), c.set(6, 3, WHITE),
                            c.vline(2, 3, 5, INK), c.vline(8, 4, 3, INK), c.hline(3, 8, 5, INK)],
    "berry_tart": lambda c: [c.rect(2, 5, 6, 3, (222, 168, 92, 255)), c.rect(3, 4, 4, 2, RED),
                            c.set(4, 3, RED), c.set(6, 3, RED), c.set(5, 4, WHITE), c.hline(2, 8, 6, INK)],
    "honey_cake": lambda c: [c.rect(2, 4, 6, 4, (240, 214, 160, 255)), c.hline(2, 4, 6, GOLD),
                            c.hline(2, 6, 6, (222, 188, 130, 255)), c.hline(2, 8, 6, INK),
                            c.set(4, 3, GOLD), c.set(6, 3, GOLD)],
    "cookie":    lambda c: [c.rect(3, 3, 5, 5, (198, 148, 90, 255)), c.set(2, 4, (198, 148, 90, 255)),
                            c.set(8, 5, (198, 148, 90, 255)), c.set(4, 4, INK), c.set(6, 6, INK), c.set(5, 5, INK)],
}

# ---------------------------------------------------------------- v2: bubbles + dirt

def bubble(angry=False):
    c = Canvas(16, 15)
    bgc = (238, 120, 108, 255) if angry else WHITE
    c.rect(1, 1, 14, 11, bgc)
    c.hline(2, 0, 12, bgc)
    c.set(1, 1, CLEAR); c.set(14, 1, CLEAR)
    c.set(4, 12, bgc); c.set(5, 13, bgc)
    if angry:
        c.rect(7, 3, 2, 5, WHITE); c.rect(7, 9, 2, 2, WHITE)
    return c

def dirt_stain():
    c = Canvas(10, 6)
    col = (120, 92, 56, 190)
    c.rect(2, 2, 6, 3, col)
    c.set(1, 3, col); c.set(8, 3, col); c.set(3, 1, col); c.set(6, 5, col)
    return c

def dirt_cup():
    c = Canvas(8, 8)
    c.rect(2, 3, 4, 4, (200, 196, 188, 255))
    c.vline(1, 3, 4, INK); c.vline(6, 3, 4, INK); c.hline(2, 7, 4, INK)
    c.set(3, 2, (150, 120, 80, 255)); c.set(4, 1, (150, 120, 80, 200))
    return c

def cobweb():
    c = Canvas(14, 14)
    w = (230, 230, 235, 150)
    for i in range(14):
        c.set(i, 0, w) if i % 2 == 0 else None
        c.set(0, i, w) if i % 2 == 0 else None
    for i in range(0, 12, 2):
        c.set(i, 12 - i, w)
    for r in (4, 8):
        for i in range(0, r + 1, 2):
            c.set(i, r - i, w)
    return c

def closed_sign():
    c = Canvas(30, 20)
    c.rect(1, 1, 28, 18, (150, 68, 60, 255))
    c.rect(1, 1, 28, 2, (120, 50, 44, 255))
    for x in range(1, 29):
        c.set(x, 0, INK); c.set(x, 19, INK)
    c.vline(0, 1, 18, INK); c.vline(29, 1, 18, INK)
    # "CLOSED" as chunky pixels
    letters = ["XXX X  XX  XX XXX XX ",
               "X   X X X X   X   X X",
               "X   X X X  X  XX  X X",
               "X   X X X   X X   X X",
               "XXX XX XX XX  XXX XX "]
    for y, row in enumerate(letters):
        for x, ch in enumerate(row):
            if ch == "X":
                c.set(4 + x, 7 + y, CREAM)
    return c

STAFF_SPECIES = {"mocha": "cat", "biscuit": "corgi", "poppy": "bunny",
                 "juno": "fox", "bo": "bear", "earl": "owl", "marble": "raccoon"}

def main_v2():
    count = 0
    for sp in SPECIES:
        for pal in PALETTES:
            f0 = owner(sp, pal)
            f0.save(f"owner_{sp}_{pal}_0.png"); f0.shifted_down().save(f"owner_{sp}_{pal}_1.png")
            count += 2
            fur, fur_d = PALETTES[pal]
            for f in range(5):
                face_icon(sp, fur, fur_d, f).save(f"bar_{sp}_{pal}_{f}.png"); count += 1
    for sid, args in STAFF.items():
        for f in range(5):
            face_icon(STAFF_SPECIES[sid], args[0], args[1], f).save(f"barstaff_{sid}_{f}.png"); count += 1
    for aid, fn in ACCESSORIES.items():
        fn().save(f"acc_{aid}.png"); count += 1
    for iid, draw in ING_ICONS.items():
        _icon(lambda c, d=draw: d(c)).save(f"ing_{iid}.png"); count += 1
    for iid, draw in ITEM_ICONS.items():
        _icon(lambda c, d=draw: d(c)).save(f"item_{iid}.png"); count += 1
    bubble(False).save("bubble.png"); bubble(True).save("bubble_angry.png"); count += 2
    dirt_stain().save("dirt_stain.png"); dirt_cup().save("dirt_cup.png")
    cobweb().save("cobweb.png"); closed_sign().save("closed_sign.png"); count += 4
    print(f"v2: generated {count} more sprites")


# ---------------------------------------------------------------- v4: casino + lighting

import math

def glow(size=36, color=(255, 214, 140)):
    c = Canvas(size, size)
    r = size / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - r + 0.5, y - r + 0.5) / r
            if d < 1:
                a = int(90 * (1 - d) ** 2)
                if a > 2:
                    c.px[y][x] = (color[0], color[1], color[2], a)
    return c

def vignette(w=180, h=120):
    c = Canvas(w, h)
    cx, cy = w / 2, h / 2
    for y in range(h):
        for x in range(w):
            d = math.hypot((x - cx) / cx, (y - cy) / cy) / 1.42
            a = int(110 * max(0, d - 0.55) ** 1.6)
            if a > 2:
                c.px[y][x] = (14, 8, 20, min(90, a))
    return c

def slot_machine(variant):
    c = Canvas(16, 26)
    body = [(150, 60, 70, 255), (70, 90, 150, 255), (170, 130, 50, 255)][variant]
    body_d = tuple(max(0, v - 40) for v in body[:3]) + (255,)
    c.rect(2, 2, 12, 22, body)
    c.rect(2, 2, 12, 2, body_d)
    c.hline(2, 1, 12, INK); c.hline(2, 24, 12, INK)
    c.vline(1, 2, 22, INK); c.vline(14, 2, 22, INK)
    c.rect(4, 6, 8, 6, (20, 16, 24, 255))          # screen
    for i, col in enumerate([GOLD, RED, GREEN]):    # reels
        c.rect(5 + i * 2, 8, 1, 2, col)
    c.rect(4, 14, 8, 3, (240, 220, 170, 255))       # tray
    c.set(15, 6, (220, 220, 230, 255)); c.set(15, 5, INK)  # arm
    c.set(15, 4, RED)
    c.rect(6, 20, 4, 2, GOLD_D)                     # coin slot
    c.hline(2, 25, 12, (30, 22, 30, 255))
    return c

def bg_casino():
    W, H = 180, 120
    wall = (70, 34, 52, 255)
    c = Canvas(W, H, wall)
    # gold picture rail + paneling
    c.hline(0, 8, W, (140, 100, 40, 255))
    for x in range(0, W, 26):
        c.vline(x, 10, 46, (58, 28, 44, 255))
    # wainscot
    c.rect(0, 56, W, 12, (44, 22, 36, 255))
    c.hline(0, 56, W, GOLD_D)
    # carpet with diamond pattern
    c.rect(0, 68, W, H - 68, (110, 30, 44, 255))
    for y in range(70, H, 10):
        for x in range((y // 10) % 2 * 8, W, 16):
            c.set(x, y, (196, 150, 70, 255))
            c.set(x + 1, y + 1, (150, 60, 66, 255))
    # CASINO sign
    c.rect(60, 14, 60, 16, (30, 18, 30, 255))
    c.hline(60, 14, 60, GOLD); c.hline(60, 29, 60, GOLD)
    c.vline(60, 14, 16, GOLD); c.vline(119, 14, 16, GOLD)
    # suit pips: spade, heart, diamond, club
    gold_l = (255, 210, 120, 255)
    red_l = (240, 110, 110, 255)
    def pip(px, py, kind, col):
        if kind == "spade":
            c.set(px + 2, py, col)
            c.rect(px + 1, py + 1, 3, 2, col)
            c.rect(px, py + 2, 5, 1, col)
            c.set(px + 2, py + 4, col)
        elif kind == "heart":
            c.set(px + 1, py, col); c.set(px + 3, py, col)
            c.rect(px, py + 1, 5, 2, col)
            c.set(px + 1, py + 3, col); c.set(px + 2, py + 3, col); c.set(px + 3, py + 3, col)
            c.set(px + 2, py + 4, col)
        elif kind == "diamond":
            c.set(px + 2, py, col)
            c.rect(px + 1, py + 1, 3, 1, col)
            c.rect(px, py + 2, 5, 1, col)
            c.rect(px + 1, py + 3, 3, 1, col)
            c.set(px + 2, py + 4, col)
        else:  # club
            c.set(px + 2, py, col); c.set(px + 1, py + 1, col); c.set(px + 3, py + 1, col)
            c.rect(px, py + 2, 5, 2, col)
            c.set(px + 2, py + 4, col)
    pip(68, 17, "spade", gold_l)
    pip(81, 17, "heart", red_l)
    pip(94, 17, "diamond", red_l)
    pip(107, 17, "club", gold_l)
    # marquee dots around the frame
    for x in range(62, 119, 4):
        c.set(x, 16, gold_l); c.set(x, 27, gold_l)
    # chandelier
    c.vline(30, 0, 4, GOLD_D)
    c.rect(26, 4, 9, 3, GOLD)
    for dx in (25, 30, 35):
        c.set(dx, 8, (255, 240, 180, 255))
    # card table (green felt, wood rim) right side
    c.rect(102, 78, 62, 26, (32, 20, 16, 255))
    c.rect(104, 80, 58, 22, (36, 110, 70, 255))
    c.rect(106, 82, 54, 18, (44, 130, 84, 255))
    c.hline(112, 90, 42, (222, 200, 150, 120))      # card line
    for i in range(3):                               # cards on felt
        c.rect(118 + i * 12, 86, 7, 9, WHITE)
        c.set(121 + i * 12, 89, RED if i % 2 == 0 else INK)
    # velvet rope stubs at door zone
    c.rect(4, 46, 3, 22, (120, 96, 50, 255))
    c.rect(16, 46, 3, 22, (120, 96, 50, 255))
    c.hline(6, 50, 10, (170, 60, 70, 255))
    return c

def dealer_sprite():
    # sleek fox dealer in a black-and-red vest
    fur, fur_d = (212, 110, 58, 255), (160, 76, 38, 255)
    c = character(fur, fur_d, WHITE, (34, 26, 34, 255), "fox", INK)
    c.rect(7, 14, 2, 2, (170, 60, 70, 255))   # red bow tie
    return c

def roulette_wheel(size=30):
    c = Canvas(size, size)
    r = size / 2
    for y in range(size):
        for x in range(size):
            dx, dy = x - r + 0.5, y - r + 0.5
            d = math.hypot(dx, dy)
            if d > r - 0.5:
                continue
            if d > r - 2:
                c.px[y][x] = (150, 110, 40, 255)          # gold rim
            elif d > 4:
                ang = (math.atan2(dy, dx) + math.pi) / (2 * math.pi)
                seg = int(ang * 13) % 13
                if seg == 0:
                    c.px[y][x] = (40, 120, 70, 255)       # green zero
                else:
                    c.px[y][x] = (150, 45, 45, 255) if seg % 2 else (30, 26, 32, 255)
            elif d > 2:
                c.px[y][x] = (90, 60, 30, 255)
            else:
                c.px[y][x] = GOLD                          # hub
    c.set(int(r), 1, WHITE)                                # ball at top
    return c

def char_shadow():
    c = Canvas(14, 5)
    for y in range(5):
        for x in range(14):
            dx, dy = (x - 6.5) / 7, (y - 2) / 2.4
            d = dx * dx + dy * dy
            if d < 1:
                a = int(95 * (1 - d))
                if a > 4:
                    c.px[y][x] = (20, 10, 24, a)
    return c

def light_shaft():
    c = Canvas(60, 70)
    for y in range(70):
        for x in range(60):
            t = x - y * 0.45
            if 6 < t < 40:
                edge = min(t - 6, 40 - t) / 17
                a = int(80 * max(0, min(1, edge)) * (1 - y / 80))
                if a > 2:
                    c.px[y][x] = (255, 240, 200, a)
    return c

def main_v4():
    count = 0
    glow().save("glow.png"); count += 1
    glow(28, (150, 220, 255)).save("glow_cool.png"); count += 1
    vignette().save("vignette.png"); count += 1
    for v in range(3):
        slot_machine(v).save(f"slot_{v}.png"); count += 1
    bg_casino().save("bg_casino.png"); count += 1
    d = dealer_sprite()
    d.save("dealer_0.png"); d.shifted_down().save("dealer_1.png"); count += 2
    roulette_wheel().save("wheel.png"); count += 1
    char_shadow().save("shadow.png"); count += 1
    light_shaft().save("shaft.png"); count += 1
    print(f"v4: generated {count} more sprites")

def main():
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for sid, args in STAFF.items():
        f0 = character(*args)
        f0.save(f"staff_{sid}_0.png"); f0.shifted_down().save(f"staff_{sid}_1.png")
        count += 2
    for i, args in enumerate(CUSTOMERS):
        f0 = character(*args)
        f0.save(f"customer_{i}_0.png"); f0.shifted_down().save(f"customer_{i}_1.png")
        count += 2
    for eid, fn in EQUIP.items():
        for t in range(3):
            fn(t).save(f"equip_{eid}_{t}.png"); count += 1
    tip_coin().save("tip.png"); recipe_bubble().save("recipe_bubble.png"); count += 2
    for f in range(4):
        baricon(f).save(f"baricon_{f}.png"); count += 1
    for t in range(3):
        background(t).save(f"bg_tier{t}.png"); count += 1
    for theme in THEMES:
        for t in range(3):
            background(t, theme).save(f"bg_{theme}_tier{t}.png"); count += 1
    print(f"generated {count} sprites -> {os.path.abspath(OUT)}")
    main_v2()
    main_v4()

if __name__ == "__main__":
    main()
