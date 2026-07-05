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
    elif species in ("corgi", "bear"):
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
    if species in ("fox", "corgi", "bunny", "cat"):
        c.rect(5, 8, 6, 4, belly)
    if species == "owl":
        c.rect(4, 5, 3, 4, WHITE); c.rect(9, 5, 3, 4, WHITE)
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

def background(tier):
    W, H = 180, 120
    wall = [(226, 204, 172, 255), (222, 192, 178, 255), (198, 176, 202, 255)][tier]
    wall_d = tuple(max(0, v - 24) for v in wall[:3]) + (255,)
    c = Canvas(W, H, wall)
    # wainscot
    c.rect(0, 58, W, 14, WOOD_D)
    c.rect(0, 58, W, 2, INK)
    for x in range(0, W, 12):
        c.vline(x, 60, 12, (100, 62, 36, 255))
    # floor
    floor_a = [(214, 168, 118, 255), (206, 158, 108, 255), (168, 128, 96, 255)][tier]
    floor_b = tuple(max(0, v - 22) for v in floor_a[:3]) + (255,)
    c.rect(0, 72, W, H - 72, floor_a)
    for y in range(72, H, 8):
        for x in range(0, W, 16):
            if ((x // 16) + (y // 8)) % 2 == 0:
                c.rect(x, y, 16, 8, floor_b)
        c.hline(0, y, W, (150, 108, 70, 255))
    # window (left-center)
    c.rect(30, 12, 34, 38, INK)
    c.rect(32, 14, 30, 34, SKY)
    c.vline(46, 14, 34, INK); c.hline(32, 30, 30, INK)
    c.set(38, 18, WHITE); c.set(39, 18, WHITE); c.set(40, 19, WHITE)   # cloud
    c.set(54, 24, WHITE); c.set(55, 24, WHITE)
    c.rect(28, 50, 38, 3, WOOD)                                       # sill
    # door (far left)
    c.rect(4, 22, 20, 50, WOOD)
    c.rect(4, 22, 20, 2, INK); c.vline(4, 22, 50, INK); c.vline(23, 22, 50, INK)
    c.rect(7, 26, 14, 18, SKY); c.rect(7, 26, 14, 1, INK); c.vline(7, 26, 18, INK); c.vline(20, 26, 18, INK); c.hline(7, 43, 14, INK)
    c.set(20, 50, GOLD)                                               # knob
    # counter (right)
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
    # tables (floor)
    for tx in (36, 66):
        c.rect(tx, 88, 22, 4, WOOD_L)
        c.hline(tx, 88, 22, INK)
        c.rect(tx + 9, 92, 4, 12, WOOD_D)
        c.rect(tx + 6, 104, 10, 2, WOOD_D)
    # tier 1+: rug, wall art
    if tier >= 1:
        c.rect(120, 96, 46, 16, (172, 96, 84, 255))
        c.rect(122, 98, 42, 12, (198, 120, 100, 255))
        c.rect(74, 30, 14, 12, WOOD_D); c.rect(76, 32, 10, 8, (140, 180, 190, 255))  # picture
    # tier 2: hanging lights, banner
    if tier >= 2:
        for x in range(20, W, 30):
            c.vline(x, 0, 5, INK)
            c.rect(x - 1, 5, 3, 3, GOLD)
            c.set(x, 6, (255, 230, 150, 255))
        c.rect(126, 38, 18, 8, (150, 68, 60, 255))                    # ★ banner
        c.set(134, 41, GOLD); c.set(135, 41, GOLD)
    return c

# ---------------------------------------------------------------- main

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
    print(f"generated {count} sprites -> {os.path.abspath(OUT)}")

if __name__ == "__main__":
    main()
