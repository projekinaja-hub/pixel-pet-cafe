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
    elif species == "panda":
        dark = (58, 56, 64, 255)
        for x0 in (2, 11):
            c.rect(x0, 2, 3, 2, dark)
            c.set(x0, 2, INK); c.set(x0 + 2, 2, INK); c.set(x0 + 1, 1, INK)
    elif species == "deer":
        antler = (150, 112, 70, 255)
        for x0 in (3, 11):
            c.vline(x0, 0, 3, antler)
            c.set(x0 + (1 if x0 == 3 else -1), 1, antler)
        c.set(2, 3, fur_d); c.set(13, 3, fur_d)   # side ears
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
    if species == "panda":    # eye patches
        c.rect(4, 5, 3, 3, (58, 56, 64, 255)); c.rect(9, 5, 3, 3, (58, 56, 64, 255))
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

# ------------------------------------------------------- Comet the astro-fox
# Hand-built rather than routed through character(): the bubble helmet has to
# be drawn BEHIND the face and re-rimmed in front of it, and the suit replaces
# the apron entirely. Both fight the parametric builder's fixed row layout, and
# bending it here would risk all eight existing species for one character.

SNOW    = (250, 250, 253, 255)   # suit + arctic fur
SNOW_D  = (203, 212, 226, 255)
# The glass is tinted well below the fur's value on purpose. At the first
# attempt it was nearly white, and a white fox inside a white bubble had no
# silhouette at all — the head simply dissolved into the helmet.
GLASS   = (176, 218, 238, 255)   # helmet interior
GLASS_D = (120, 178, 206, 255)   # helmet rim
MUZZLE  = (128, 106, 116, 255)   # softer than INK; 2px of pure black at this
                                 # size reads as a mouth, not a nose
ICEYE   = (54, 150, 208, 255)
EARPINK = (244, 172, 184, 255)
BLUSH   = (246, 186, 182, 255)
STRAP   = (146, 154, 168, 255)
STRAP_D = (106, 114, 128, 255)
AMBER   = (240, 148, 54, 255)
BADGE   = (74, 168, 226, 255)
RING    = (122, 216, 234, 255)

# (x, width) of the helmet dome on each row — an ellipse wide enough to sit
# clear of the ears without spilling off a 16px canvas.
_DOME = {0: (5, 6), 1: (3, 10), 2: (2, 12), 3: (1, 14),
         4: (1, 14), 5: (1, 14), 6: (1, 14), 7: (2, 12), 8: (3, 10)}


def astro_fox(frame=0):
    """Comet: an arctic fox barista in a bubble helmet. 16x20, like every
    other character, so it drops straight into the existing staff pipeline.

    frame 0 = open eyes, 1 = blink, 2 = waving paw raised."""
    c = Canvas(16, 20)

    for y, (x0, w) in _DOME.items():                 # glass, behind the fox
        c.hline(x0, y, w, GLASS)

    # ears — deliberately short and tucked, so the dome can arc over them
    # rather than the ears puncturing the glass
    # Set in one column from the dome's edge: at x3/x10 the ear tips landed on
    # the exact pixels the dome's shoulder needs, so the helmet's top rim read
    # as a detached bar floating above a gap.
    for ex in (4, 9):
        c.hline(ex, 2, 3, SNOW)
        c.set(ex + 1, 1, SNOW)                             # tip
        c.set(ex + 1, 2, EARPINK)

    c.hline(4, 3, 8, SNOW)                           # head
    c.rect(3, 4, 10, 3, SNOW)
    c.hline(4, 7, 8, SNOW)
    # Soft edge all the way round the head. Without it the white fur and the
    # helmet glass merge into one shape at 16px.
    c.set(3, 3, SNOW_D); c.set(12, 3, SNOW_D)
    c.set(3, 7, SNOW_D); c.set(12, 7, SNOW_D)

    if frame == 1:
        c.hline(4, 5, 2, MUZZLE); c.hline(10, 5, 2, MUZZLE)
    else:
        c.rect(4, 4, 2, 2, ICEYE); c.rect(10, 4, 2, 2, ICEYE)
        c.set(4, 4, WHITE); c.set(10, 4, WHITE)      # catchlights
    c.set(3, 6, BLUSH); c.set(12, 6, BLUSH)
    c.set(7, 6, MUZZLE); c.set(8, 6, MUZZLE)         # nose, and nothing else:
    # a nose plus smile-corners on a 10px-wide face merges into one dark band
    # that reads as a wide frown rather than a face.

    for y, (x0, w) in _DOME.items():                 # rim, in front of the fox
        if y in (0, 8):
            c.hline(x0, y, w, GLASS_D)
        else:
            c.set(x0, y, GLASS_D); c.set(x0 + w - 1, y, GLASS_D)
    c.set(4, 1, GLASS_D); c.set(11, 1, GLASS_D)   # shoulders, closing the dome
    c.set(4, 2, WHITE); c.set(3, 3, WHITE); c.set(2, 4, WHITE)   # glass streak

    c.hline(4, 9, 8, RING)                           # neck ring

    c.rect(4, 10, 8, 7, SNOW)                        # suit
    c.vline(3, 10, 7, SNOW_D); c.vline(12, 10, 7, SNOW_D)
    c.vline(5, 10, 5, STRAP); c.vline(10, 10, 5, STRAP)          # harness
    c.rect(6, 12, 4, 2, STRAP)                                   # chest panel
    c.set(6, 12, AMBER); c.set(9, 13, GLASS_D)
    c.set(4, 11, BADGE)                                          # shoulder badge
    c.hline(4, 15, 8, STRAP); c.hline(7, 15, 2, AMBER)           # belt + buckle

    c.set(3, 11, SNOW); c.set(3, 12, SNOW)                       # left arm
    # The waving paw sits BELOW the dome (which ends at row 8) and outside the
    # suit's outline. Tucked against the helmet it was invisible — white on
    # glass, exactly the problem the tinting above fixes for the head.
    paw = 10 if frame == 2 else 11
    c.set(13, paw + 1, SNOW_D)                                   # forearm
    c.rect(13, paw, 2, 1, SNOW)                                  # raised paw
    c.set(14, paw, SNOW_D)

    c.hline(4, 17, 3, SNOW); c.hline(9, 17, 3, SNOW)             # legs
    c.rect(4, 18, 3, 1, STRAP); c.rect(9, 18, 3, 1, STRAP)       # boots
    c.hline(4, 19, 3, STRAP_D); c.hline(9, 19, 3, STRAP_D)
    return c


STAFF = {
    #        fur                fur_dark           belly   apron   species accent
    "mocha":   ((150, 102, 66, 255), (112, 72, 46, 255), CREAM, (206, 106, 76, 255), "cat", None),
    "biscuit": ((222, 158, 90, 255), (176, 116, 60, 255), CREAM, (96, 129, 171, 255), "corgi", INK),
    "chip":    ((196, 168, 132, 255), (156, 130, 100, 255), WHITE, (140, 190, 200, 255), "deer", INK),
    "poppy":   ((228, 214, 202, 255), (186, 168, 155, 255), WHITE, PINK, "bunny", None),
    "juno":    ((212, 110, 58, 255), (160, 76, 38, 255), WHITE, (74, 110, 88, 255), "fox", INK),
    "bo":      ((122, 88, 62, 255), (88, 60, 42, 255), (168, 132, 100, 255), (150, 68, 60, 255), "bear", INK),
    "earl":    ((138, 120, 150, 255), (100, 84, 114, 255), WHITE, (46, 58, 92, 255), "owl", None),
    "marble":  ((172, 168, 178, 255), (120, 116, 130, 255), CREAM, (90, 74, 52, 255), "raccoon", INK),
    "comet":   (SNOW, SNOW_D, WHITE, STRAP, "arcticfox", MUZZLE),
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
    "moon":   {"walls": [(70, 66, 90, 255), (64, 60, 86, 255), (56, 52, 78, 255)],
               "floors": [(48, 44, 66, 255), (42, 40, 60, 255), (36, 34, 52, 255)],
               "sky": (18, 16, 36, 255), "accent": (150, 180, 230, 255)},
}

def _shade(col, f):
    return (min(255, int(col[0] * f)), min(255, int(col[1] * f)),
            min(255, int(col[2] * f)), 255)

def _disk(c, cx, cy, r, color):
    """small filled circle, for suns/moons/planets."""
    for yy in range(cy - r, cy + r + 1):
        for xx in range(cx - r, cx + r + 1):
            if (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r + r * 0.5:
                c.set(xx, yy, color)

def _line(c, x0, y0, x1, y1, color):
    steps = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(steps + 1):
        t = i / steps if steps else 0
        c.set(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), color)

def _dashed_line(c, x0, y0, x1, y1, color, phase=0):
    steps = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(steps + 1):
        if (i + phase) % 2 != 0:
            continue
        t = i / steps if steps else 0
        c.set(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), color)

def _triangle(c, cx, base_y, height, half_w, color):
    """upward triangle silhouette (mountain/volcano cone), base at base_y."""
    for i in range(height):
        yy = base_y - i
        ww = max(1, round(half_w * (1 - i / height)))
        c.rect(cx - ww, yy, ww * 2, 1, color)

def _umbrella(c, cx, base_y, height, half_w, color, color_d, pole_color, pole_len):
    """beach-umbrella silhouette: striped triangular canopy, scalloped rim,
    pole down to the table beneath. base_y is the rim row."""
    for i in range(height):
        yy = base_y - i
        ww = max(1, round(half_w * (1 - i / height)))
        band = color if (i // 2) % 2 == 0 else color_d
        c.rect(cx - ww, yy, ww * 2, 1, band)
    for k in range(-half_w, half_w + 1, 3):
        c.set(cx + k, base_y, color_d)
    c.set(cx, base_y - height - 1, WHITE)
    c.vline(cx, base_y + 1, pole_len, pole_color)

def _leaf_canopy(c, cx, base_y, r, leaf, leaf_d, pole_color, pole_len):
    """overhanging tree-shade silhouette: three overlapping leaf clusters
    plus a pole down to the table beneath."""
    _disk(c, cx - r + 2, base_y - r, r, leaf)
    _disk(c, cx + r - 2, base_y - r, r, leaf)
    _disk(c, cx, base_y - r - 2, r + 1, leaf_d)
    c.set(cx - 1, base_y - r - r, (255, 240, 190, 180))
    c.vline(cx, base_y + 1, pole_len, pole_color)

def _window_scene(c, theme):
    """distinct outdoor view per café theme, drawn inside the window pane
    (x 32-61, y 14-47), BEFORE the mullion cross-bars are redrawn on top."""
    if theme == "neon":  # moon + stars over a distant city skyline
        c.rect(38, 18, 4, 4, (240, 236, 210, 255))
        c.set(52, 20, WHITE); c.set(57, 26, WHITE); c.set(44, 28, WHITE)
        for tx, tw, th_ in ((34, 4, 10), (40, 3, 15), (45, 5, 8), (52, 4, 13), (57, 3, 9)):
            c.rect(tx, 47 - th_, tw, th_, (40, 36, 60, 255))
            for wy in range(47 - th_ + 2, 45, 3):
                c.set(tx + 1, wy, (94, 230, 224, 255))
    elif theme == "sakura":  # blossom branch
        c.rect(36, 20, 22, 2, (120, 82, 60, 255))
        for px, py in ((38, 18), (44, 17), (50, 19), (56, 18), (41, 22), (53, 23)):
            c.set(px, py, (244, 168, 186, 255)); c.set(px + 1, py, (238, 150, 170, 255))
    elif theme == "seaside":  # beach horizon, sun, sailboat, gull
        c.rect(32, 34, 30, 13, (90, 160, 200, 255))
        c.hline(32, 34, 30, (60, 130, 175, 255))
        _disk(c, 40, 20, 3, (255, 235, 150, 255))
        c.vline(54, 29, 6, (80, 60, 50, 255))
        for i, yy in enumerate(range(28, 33)):
            c.hline(54 - i, yy, i + 1, (250, 250, 245, 255))
        c.set(46, 22, INK); c.set(48, 22, INK)
    elif theme == "forest":  # treehouse view: canopy overhead, trunks below
        for x in range(32, 62, 3):
            c.rect(x, 14, 3, 6 + (2 if (x // 3) % 2 == 0 else 0), (90, 140, 80, 255))
        for tx in (36, 50, 58):
            c.vline(tx, 30, 17, (70, 50, 38, 255))
            c.vline(tx + 1, 30, 17, (60, 42, 32, 255))
        _disk(c, 46, 26, 3, (255, 240, 180, 255))
    elif theme == "desert":  # dunes, big sun, cactus silhouette
        _disk(c, 46, 20, 4, (255, 214, 120, 255))
        c.rect(32, 38, 30, 9, (214, 168, 110, 255))
        for x in range(32, 62):
            if (x // 5) % 2 == 0:
                c.vline(x, 36, 3, (190, 146, 92, 255))
        c.vline(40, 30, 10, (90, 110, 70, 255))
        c.hline(38, 34, 2, (90, 110, 70, 255)); c.hline(42, 32, 2, (90, 110, 70, 255))
    elif theme == "snowy":  # snow-capped mountains, falling snow
        _triangle(c, 40, 46, 16, 10, (205, 215, 230, 255))
        _triangle(c, 52, 46, 12, 8, (188, 200, 220, 255))
        c.set(40, 31, WHITE); c.set(39, 32, WHITE); c.set(41, 32, WHITE)
        for px, py in ((35, 18), (50, 22), (58, 16), (37, 26), (55, 30)):
            c.set(px, py, WHITE)
    elif theme == "sunset":  # low warm sun, band, birds
        c.rect(32, 30, 30, 17, (250, 180, 120, 255))
        _disk(c, 47, 32, 5, (255, 220, 140, 255))
        for bx, by in ((38, 20), (44, 18), (52, 21)):
            c.set(bx, by, INK); c.set(bx - 1, by + 1, INK); c.set(bx + 1, by + 1, INK)
    elif theme == "ember":  # volcano cone with glowing crater + rising sparks
        _triangle(c, 47, 46, 20, 12, (80, 50, 48, 255))
        c.rect(43, 17, 8, 3, (255, 140, 60, 255))
        for px, py in ((40, 24), (52, 20), (46, 16), (58, 28)):
            c.set(px, py, (255, 160, 70, 255))
    elif theme == "royal":  # castle towers with flags against a purple sky
        c.rect(34, 26, 6, 20, (80, 60, 110, 255)); c.rect(33, 22, 8, 4, (80, 60, 110, 255))
        c.rect(48, 20, 6, 26, (80, 60, 110, 255)); c.rect(47, 16, 8, 4, (80, 60, 110, 255))
        c.set(36, 20, (250, 210, 110, 255)); c.set(50, 14, (250, 210, 110, 255))
    elif theme == "cloud":  # sky-city view: bright sun above a sea of clouds
        _disk(c, 44, 18, 3, (255, 250, 220, 255))
        for cx, cy in ((38, 36), (50, 40), (44, 30), (56, 34)):
            c.rect(cx - 3, cy, 7, 3, WHITE); c.rect(cx - 1, cy - 2, 4, 2, WHITE)
    elif theme == "moon":  # starfield, earthrise
        for px, py in ((34, 18), (40, 22), (56, 16), (50, 28), (37, 30), (58, 24)):
            c.set(px, py, WHITE)
        _disk(c, 50, 34, 6, (90, 140, 200, 255))
        _disk(c, 49, 33, 2, (120, 170, 140, 255))
    else:  # home + default: soft clouds
        c.set(38, 18, WHITE); c.set(39, 18, WHITE); c.set(40, 19, WHITE)
        c.set(54, 24, WHITE); c.set(55, 24, WHITE)

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
    # wainscot (moon station swaps the wood for brushed-metal paneling)
    if theme == "moon":
        metal, metal_seam = (96, 102, 122, 255), (68, 74, 96, 255)
        c.rect(0, 58, W, 14, metal)
        c.rect(0, 58, W, 2, INK)
        c.hline(0, 60, W, (128, 136, 158, 255))            # brushed highlight
        for x in range(0, W, 12):
            c.vline(x, 60, 12, metal_seam)
            c.set(x + 1, 62, (140, 148, 168, 255))         # rivet
            c.set(x + 1, 68, (140, 148, 168, 255))
    else:
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
    if theme == "cloud":
        # panoramic glass wall: window + shelf wall replaced by one huge pane
        # looking out over a sea of clouds. Left pane edge/mullions align with
        # the classic window rect (x30-63) so the runtime glass tint still
        # reads as one pane of the wall.
        c.rect(26, 10, 72, 42, INK)                                   # frame
        pane_sky = th["sky"]
        for y in range(12, 50):                                       # pane sky gradient
            f = 1.12 - 0.26 * ((y - 12) / 38)
            row = _shade(pane_sky, f)
            for x in range(28, 96):
                c.px[y][x] = row
        _disk(c, 88, 17, 3, (255, 250, 220, 255))                     # high sun
        puff_hi, puff_lo = WHITE, (222, 228, 244, 255)
        for px, py, pw in ((33, 20, 8), (52, 27, 10), (44, 16, 6),    # drifting puffs
                           (70, 22, 9), (86, 30, 7), (36, 33, 7)):
            c.rect(px, py, pw, 2, puff_hi)
            c.rect(px + 1, py - 1, pw - 3, 1, puff_hi)
            c.rect(px + 1, py + 2, pw - 2, 1, puff_lo)
        # distant floating island drifting between the puffs
        isl_rock, isl_grass = (128, 116, 146, 255), (150, 196, 140, 255)
        c.rect(69, 37, 12, 2, isl_rock)
        c.rect(71, 39, 8, 2, _shade(isl_rock, 0.8))
        c.rect(73, 41, 4, 1, _shade(isl_rock, 0.62))                  # tapering underside
        c.hline(69, 36, 12, isl_grass)
        c.set(72, 35, isl_grass); c.set(76, 35, (110, 160, 110, 255)) # tiny tree tufts
        c.vline(74, 42, 2, (236, 244, 252, 255))                      # waterfall dribble
        c.set(66, 40, _shade(isl_rock, 0.85)); c.set(84, 38, _shade(isl_rock, 0.85))  # drift rocks
        # sea of clouds along the bottom of the pane
        for bx in range(28, 96, 7):
            _disk(c, bx + 3, 49, 4, WHITE)
        c.rect(28, 47, 68, 3, WHITE)
        for x in range(29, 95, 4):
            c.set(x, 47, (232, 238, 250, 255))                        # soft scallop shading
        for gx, gy in ((40, 24), (60, 20)):                           # distant birds
            c.set(gx, gy, INK); c.set(gx - 1, gy + 1, INK); c.set(gx + 1, gy + 1, INK)
        c.vline(63, 12, 38, INK); c.vline(80, 12, 38, INK)            # mullions
        c.rect(24, 52, 76, 3, WOOD)                                   # long sill
    elif theme == "moon":
        # dome porthole: black starfield, earthrise, regolith at the rim
        metal, metal_hi = (118, 124, 144, 255), (160, 168, 188, 255)
        _disk(c, 47, 30, 21, INK)
        _disk(c, 47, 30, 19, metal)
        for a_dx, a_dy in ((0, -20), (14, -14), (20, 0), (14, 14),    # rivets on the ring
                           (0, 20), (-14, 14), (-20, 0), (-14, -14)):
            c.set(47 + a_dx, 30 + a_dy, metal_hi)
        _disk(c, 47, 30, 17, (10, 10, 24, 255))                       # deep space
        for sx, sy in ((38, 18), (54, 15), (59, 27), (35, 30), (44, 24),
                       (52, 35), (33, 24), (57, 20), (41, 39), (49, 19)):
            c.set(sx, sy, WHITE)
        c.set(36, 36, (170, 180, 210, 255)); c.set(56, 39, (170, 180, 210, 255))  # faint stars
        _disk(c, 54, 22, 5, (86, 138, 200, 255))                      # the Earth
        _disk(c, 56, 24, 3, (66, 112, 176, 255))                      # night limb shading
        c.rect(52, 20, 3, 2, (110, 168, 130, 255))                    # continents
        c.set(55, 25, (110, 168, 130, 255)); c.set(52, 24, (110, 168, 130, 255))
        c.hline(51, 22, 3, WHITE); c.set(55, 20, WHITE)               # cloud swirls
        c.set(53, 26, (226, 238, 248, 255))
        rego, rego_d = (146, 144, 154, 255), (112, 110, 122, 255)     # regolith at the rim
        for x in range(31, 64):
            bump = (x // 5) % 2
            top = 42 - bump
            if (x - 47) ** 2 + (top - 30) ** 2 <= 17 * 17:
                c.rect(x, top, 1, 48 - top, rego)
                c.set(x, top, (176, 174, 184, 255))                   # sunlit rim
        for cx2, cy2 in ((39, 45), (50, 44), (58, 46)):               # small craters
            c.hline(cx2, cy2, 3, rego_d); c.set(cx2 + 1, cy2 - 1, rego_d)
        c.rect(36, 51, 23, 2, metal)                                  # metal ledge
        c.hline(36, 51, 23, metal_hi)
    else:
        c.rect(30, 12, 34, 38, INK)
        c.rect(32, 14, 30, 34, th["sky"])
        _window_scene(c, theme)
        c.vline(46, 14, 34, INK); c.hline(32, 30, 30, INK)            # mullion, crisp on top
        c.rect(28, 50, 38, 3, WOOD)                                   # sill
    # door (far left)
    c.rect(4, 22, 20, 50, WOOD)
    c.rect(4, 22, 20, 2, INK); c.vline(4, 22, 50, INK); c.vline(23, 22, 50, INK)
    door_pane = (10, 10, 24, 255) if theme == "moon" else SKY
    c.rect(7, 26, 14, 18, door_pane); c.rect(7, 26, 14, 1, INK); c.vline(7, 26, 18, INK); c.vline(20, 26, 18, INK); c.hline(7, 43, 14, INK)
    if theme == "moon":
        c.set(11, 30, WHITE); c.set(16, 36, WHITE); c.set(9, 39, (170, 180, 210, 255))
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
    # shelf with jars (between window and menu) — the cloud glass wall
    # occupies this stretch, so skip it there
    if theme != "cloud":
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
        if theme != "cloud":                                          # glass wall there
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

def outdoor_background(tier, theme):
    """Open-air patio layout: sky backdrop instead of walls, a deck/patio
    floor, an open entry path where the door used to be, and a thatched
    patio bar counter in the same footprint as the indoor counter (so the
    counter-front z-order trick in CafeScene.swift keeps working unmodified).
    Used for 'seaside' (beach patio), 'forest' (treehouse deck),
    'desert' (oasis terrace) and 'sunset' (harbor boardwalk)."""
    W, H = 180, 120
    th = THEMES[theme]
    sky = th["sky"]
    accent = th["accent"]
    horizon_y = 62
    floor_y = 72
    c = Canvas(W, H, sky)
    # sky gradient, brighter near the top
    for y in range(0, horizon_y):
        f = 1.16 - 0.30 * (y / horizon_y)
        for x in range(W):
            c.px[y][x] = _shade(sky, f)

    if theme == "seaside":
        _disk(c, 150, 16, 6, (255, 236, 170, 255))
        for gx, gy in ((30, 14), (40, 10), (120, 20)):
            c.set(gx, gy, INK); c.set(gx - 2, gy + 1, INK); c.set(gx + 2, gy + 1, INK)
        sea = (78, 148, 196, 255)
        c.rect(0, 40, W, horizon_y - 40, sea)
        for y in range(42, horizon_y, 4):
            c.hline(0, y, W, _shade(sea, 1.14))
        for y in range(44, horizon_y, 6):
            _dashed_line(c, 0, y, W - 1, y, (222, 240, 245, 200), phase=y)
        c.vline(100, 34, 8, (90, 60, 50, 255))
        for i, yy in enumerate(range(30, 36)):
            c.hline(100 - i, yy, i + 1, (250, 250, 245, 255))
    elif theme == "forest":
        _disk(c, 130, 14, 5, (255, 240, 190, 255))
        for cx in range(6, W, 22):
            _disk(c, cx, 20, 10, (94, 154, 84, 255))
            _disk(c, cx + 12, 15, 8, (108, 168, 94, 255))
        for px, py in ((26, 30), (64, 26), (98, 32), (140, 28), (160, 24)):
            c.set(px, py, (255, 240, 190, 180))
    elif theme == "desert":
        # blazing sun high in the open sky, left of the pergola
        _disk(c, 28, 13, 6, (255, 232, 150, 255))
        _disk(c, 28, 13, 4, (255, 244, 190, 255))
        for gx, gy in ((52, 16), (70, 10)):                # distant hawks
            c.set(gx, gy, INK); c.set(gx - 2, gy + 1, INK); c.set(gx + 2, gy + 1, INK)
        # rolling dunes on the horizon: rounded far humps, then a near ridge
        dune_far, dune_near = (232, 196, 134, 255), (218, 176, 114, 255)
        for cx2, peak in ((26, 42), (88, 39), (152, 43)):
            r = 62 - peak + 14
            _disk(c, cx2, 62 + (r - (62 - peak)), r, dune_far)
        c.rect(0, 56, W, horizon_y - 56, dune_far)
        for cx2, peak in ((0, 52), (58, 50), (120, 53), (176, 51)):
            r = 62 - peak + 10
            _disk(c, cx2, 62 + (r - (62 - peak)), r, dune_near)
        c.rect(0, 59, W, horizon_y - 59, dune_near)
        for x in range(0, W, 3):                            # windblown sand ripples
            if (x // 3) % 2 == 0:
                c.set(x, 57, (200, 158, 100, 255))
        # oasis pond glinting on the near dune, framed by two palms
        pond = (110, 178, 196, 255)
        c.rect(53, 50, 16, 4, pond)
        c.set(53, 50, dune_near); c.set(68, 50, dune_near)   # rounded ends
        c.set(53, 53, dune_near); c.set(68, 53, dune_near)
        c.hline(57, 51, 6, (196, 232, 238, 255))             # sun glint
        for px, lean in ((49, 1), (73, -1)):                 # palms leaning over it
            for i in range(9):
                c.set(px + (i // 3) * lean, 49 - i, (124, 90, 56, 255))
            topx, topy = px + 2 * lean, 40
            for dx, dy in ((-4, 0), (-3, -1), (-2, -1), (2, -1), (3, -1), (4, 0),
                           (-1, -2), (0, -2), (1, -2), (-2, 1), (2, 1)):
                c.set(topx + dx, topy + dy, (96, 150, 74, 255))
            c.set(topx, topy - 1, (70, 118, 58, 255))
        # saguaro cacti silhouetted on the dune crests
        for cx2, cy2, hh in ((12, 52, 9), (92, 52, 7)):
            cactus = (92, 128, 72, 255)
            c.rect(cx2, cy2 - hh, 2, hh, cactus)
            c.vline(cx2 - 2, cy2 - hh + 3, 3, cactus); c.hline(cx2 - 2, cy2 - hh + 3, 2, cactus)
            c.vline(cx2 + 3, cy2 - hh + 1, 3, cactus); c.hline(cx2 + 2, cy2 - hh + 3, 2, cactus)
            c.set(cx2, cy2 - hh, (70, 104, 58, 255))
    elif theme == "sunset":
        # deeper amber bands low in the sky
        for y in range(24, 40):
            band = _shade(sky, 0.98 - 0.012 * (y - 24))
            for x in range(W):
                if (x + y) % 2 == 0 or y > 32:
                    c.px[y][x] = band
        # harbor water
        water = (150, 96, 104, 255)
        c.rect(0, 40, W, horizon_y - 40, water)
        c.hline(0, 40, W, (196, 120, 104, 255))
        for y in range(43, horizon_y, 4):
            c.hline(0, y, W, _shade(water, 1.12))
        # low sun kissing the waterline + shimmering light path (kept clear of
        # the pergola and the equipment sprites that sit near the counter)
        _disk(c, 60, 38, 7, (255, 214, 120, 255))
        _disk(c, 60, 37, 4, (255, 238, 170, 255))
        c.rect(53, 40, 15, 1, (255, 226, 150, 255))          # melt into the horizon
        for y in range(41, horizon_y):
            wob = 1 if (y % 4) < 2 else -1
            ww = max(2, 7 - (y - 41) // 4)
            _dashed_line(c, 60 - ww + wob, y, 60 + ww + wob, y, (255, 210, 130, 230), phase=y)
        for y in range(44, horizon_y, 6):                    # faint cross-waves
            _dashed_line(c, 0, y, W - 1, y, (232, 160, 120, 190), phase=y + 1)
        # moored boat silhouettes, masts against the sky (one near, one far)
        for bx, my, hw in ((32, 22, 8), (12, 30, 5)):
            hull = (66, 44, 52, 255)
            c.rect(bx - hw, 41, hw * 2, 3 if hw > 5 else 2, hull)   # hull
            c.set(bx - hw - 1, 41, hull); c.set(bx + hw, 41, hull)
            c.vline(bx, my, 41 - my, hull)                   # mast
            c.hline(bx - hw // 2, my + 4, hw + 1, hull)      # spar
            _line(c, bx, my, bx + 5, 40, (86, 58, 64, 255))  # rigging
            c.hline(bx - hw, 44, hw * 2, (46, 32, 40, 255))  # waterline shadow
        c.rect(174, 42, 2, 3, (200, 90, 70, 255))            # harbor buoy far right
        c.set(174, 41, (255, 200, 110, 255))
        for gx, gy in ((76, 14), (106, 10)):                 # gulls heading home
            c.set(gx, gy, INK); c.set(gx - 2, gy + 1, INK); c.set(gx + 2, gy + 1, INK)

    # ridge band: transition between sky/horizon and the patio floor
    if theme == "seaside":
        sand = (230, 208, 160, 255)
        c.rect(0, horizon_y, W, floor_y - horizon_y, sand)
        c.hline(0, horizon_y, W, (250, 236, 202, 255))
        for x in range(0, W, 5):
            c.set(x, horizon_y + 2, (200, 180, 130, 255))
    elif theme == "desert":
        sand = (226, 188, 128, 255)
        c.rect(0, horizon_y, W, floor_y - horizon_y, sand)
        c.hline(0, horizon_y, W, (244, 210, 150, 255))
        for x in range(0, W, 5):
            c.set(x, horizon_y + 2, (198, 156, 102, 255))
        for x in range(2, W, 9):                             # scattered pebbles
            c.set(x, horizon_y + (x // 9) % 3, (206, 166, 110, 255))
    elif theme == "sunset":
        dock = (128, 84, 66, 255)                            # weathered dock edge
        c.rect(0, horizon_y, W, floor_y - horizon_y, dock)
        c.hline(0, horizon_y, W, (168, 116, 92, 255))
        for x in range(0, W, 8):                             # plank seams
            c.vline(x, horizon_y, floor_y - horizon_y, _shade(dock, 0.72))
        c.hline(0, floor_y - 1, W, _shade(dock, 0.8))
    else:
        grass = (120, 150, 90, 255)
        c.rect(0, horizon_y, W, floor_y - horizon_y, grass)
        c.hline(0, horizon_y, W, (152, 187, 112, 255))
        for x in range(0, W, 4):
            c.vline(x, horizon_y, 3, (100, 130, 75, 255))

    # patio deck floor (planks, horizontal boards)
    floor_a = th["floors"][tier]
    c.rect(0, floor_y, W, H - floor_y, floor_a)
    for y in range(floor_y, H, 4):
        c.hline(0, y, W, _shade(floor_a, 0.84))
    for i, x in enumerate(range(6, W, 24)):
        for y in range(floor_y + 2 + (i % 2) * 2, H, 4):
            c.set(x, y, _shade(floor_a, 0.62))
    c.rect(0, floor_y, W, 2, _shade(floor_a, 0.7))
    for y in range(floor_y, H):                        # soft side falloff
        for x in list(range(0, 6)) + list(range(W - 6, W)):
            if (x + y) % 2 == 0:
                c.px[y][x] = _shade(c.px[y][x], 0.85)

    # open entry: two posts + a strung rope/vine where the door used to be,
    # plus stepping planks leading a customer in (doorPoint sits at x~14).
    post_colors = {"seaside": (150, 110, 70, 255), "desert": (196, 150, 100, 255),
                   "sunset": (104, 68, 54, 255)}
    post_color = post_colors.get(theme, WOOD_D)
    c.rect(2, horizon_y - 10, 2, 20, post_color)
    c.rect(24, horizon_y - 10, 2, 20, post_color)
    tie_colors = {"seaside": (90, 70, 50, 255), "desert": (150, 110, 70, 255),
                  "sunset": (90, 70, 50, 255)}
    tie_color = tie_colors.get(theme, (70, 100, 55, 255))
    _dashed_line(c, 3, horizon_y - 9, 25, horizon_y - 9, tie_color)
    for i, x in enumerate(range(4, 24, 5)):
        c.rect(x, 76 + (i % 2) * 4, 3, 2, _shade(floor_a, 0.58))
    if theme == "seaside":
        c.vline(27, horizon_y - 14, 6, (90, 70, 40, 255))
        for dx, dy in ((-1, -15), (1, -15), (0, -17)):
            c.set(27 + dx, horizon_y + dy, (90, 150, 70, 255))
    elif theme == "desert":
        c.rect(26, horizon_y - 3, 5, 4, (188, 108, 74, 255))   # terracotta pot
        c.hline(26, horizon_y - 3, 5, (150, 84, 58, 255))
        c.rect(28, horizon_y - 8, 1, 5, (92, 128, 72, 255))    # potted cactus
        c.set(27, horizon_y - 6, (92, 128, 72, 255)); c.set(29, horizon_y - 7, (92, 128, 72, 255))
    elif theme == "sunset":
        c.rect(27, horizon_y - 4, 3, 5, (66, 44, 52, 255))     # mooring bollard
        c.hline(26, horizon_y - 4, 5, (86, 58, 64, 255))
        c.set(27, horizon_y - 2, (170, 130, 80, 255)); c.set(29, horizon_y - 1, (170, 130, 80, 255))  # coiled rope
        c.rect(12, horizon_y - 9, 2, 3, (255, 200, 110, 255))  # lantern glowing on the rope
    else:
        c.rect(12, horizon_y - 9, 2, 3, GOLD)             # small lantern on the rope

    # patio bar counter — same footprint as the indoor counter (cols 96-170,
    # rows 52-80) so CafeScene.swift's counterFront crop keeps working as-is.
    roof_colors = {"seaside": ((196, 160, 90, 255), (166, 130, 66, 255)),
                   "desert":  ((214, 162, 96, 255), (178, 128, 70, 255)),   # dried palm thatch
                   "sunset":  ((206, 116, 88, 255), (168, 90, 70, 255))}    # warm canvas awning
    roof_color, roof_d = roof_colors.get(theme, ((94, 154, 84, 255), (70, 120, 62, 255)))
    for i, y in enumerate(range(6, 24)):
        w = 4 + i
        c.rect(133 - w, y, w * 2, 1, roof_color if i % 2 == 0 else roof_d)
    c.rect(98, 24, 2, 28, post_color)
    c.rect(166, 24, 2, 28, post_color)
    c.rect(112, 27, 44, 18, (72, 84, 76, 255))            # hanging chalk menu
    c.rect(112, 27, 44, 2, WOOD_D); c.rect(112, 43, 44, 2, WOOD_D)
    c.vline(112, 27, 18, INK); c.vline(155, 27, 18, INK)
    for i, w in enumerate((22, 16, 20)):
        c.hline(118, 31 + i * 5, w, (214, 224, 210, 255))
    counter_tops = {"seaside": WOOD_L, "desert": (216, 178, 122, 255),
                    "sunset": (176, 122, 88, 255)}
    counter_top = counter_tops.get(theme, (150, 118, 78, 255))
    bodies = {"seaside": (196, 164, 110, 255), "desert": (192, 142, 94, 255),
              "sunset": (120, 78, 62, 255)}
    body = bodies.get(theme, (112, 84, 58, 255))
    c.rect(96, 52, 74, 6, counter_top)
    c.rect(96, 52, 74, 1, INK)
    c.rect(98, 58, 70, 22, body)
    c.rect(98, 78, 70, 2, _shade(body, 0.75))
    c.vline(98, 58, 22, INK); c.vline(167, 58, 22, INK)
    for x in range(102, 166, 6):
        c.vline(x, 58, 22, _shade(body, 0.85))
    for x in range(96, 170):                              # counter shadow
        for y in range(80, 86):
            if 0 <= y < H:
                c.px[y][x] = _shade(c.px[y][x], 0.8 if (x + y) % 2 else 0.86)

    # patio tables — same base footprint as the indoor tables, shaded by an
    # umbrella (seaside) or a low tree canopy (forest) instead of a ceiling.
    for tx in (36, 66):
        for x in range(tx - 2, tx + 24):
            for y in range(105, 109):
                if 0 <= x < W and 0 <= y < H and (x + y) % 2 == 0:
                    c.px[y][x] = _shade(c.px[y][x], 0.78)
        if theme == "forest":
            _leaf_canopy(c, tx + 11, 76, 9, (100, 162, 88, 255), (76, 128, 66, 255), (110, 78, 50, 255), 11)
        else:
            _umbrella(c, tx + 11, 70, 15, 15, accent, _shade(accent, 0.72), post_color, 17)
        c.rect(tx, 88, 22, 4, WOOD_L)
        c.hline(tx, 88, 22, INK)
        c.hline(tx, 91, 22, _shade(WOOD_L, 0.8))
        c.rect(tx + 9, 92, 4, 12, WOOD_D)
        c.rect(tx + 6, 104, 10, 2, WOOD_D)

    # tier 1+: patio mat + a leaning prop near the entry
    if tier >= 1:
        mat = _shade(accent, 0.9)
        c.rect(120, 96, 46, 16, _shade(accent, 0.65))
        c.rect(122, 98, 42, 12, mat)
        if theme == "seaside":
            c.rect(29, 46, 3, 22, (230, 120, 90, 255))    # surfboard leaning by the gate
            c.hline(29, 50, 3, WHITE)
            c.vline(30, 47, 20, (200, 90, 70, 255))
        elif theme == "desert":
            c.rect(29, 54, 4, 6, (188, 108, 74, 255))     # tall clay amphora by the gate
            c.rect(30, 51, 2, 3, (188, 108, 74, 255))
            c.hline(29, 54, 4, (150, 84, 58, 255))
            c.set(30, 50, (150, 84, 58, 255)); c.set(31, 50, (150, 84, 58, 255))
        elif theme == "sunset":
            c.vline(30, 40, 28, (86, 58, 64, 255))        # dockside lamp post
            c.rect(29, 37, 3, 3, (66, 44, 52, 255))
            c.set(30, 38, (255, 210, 130, 255))           # warm lamp
        else:
            c.set(12, horizon_y - 5, (255, 220, 140, 220))  # lantern glow

    # tier 2: string lights along the roofline + small pennant flags
    if tier >= 2:
        for x in range(100, 168, 14):
            c.vline(x, 24, 4, INK)
            c.rect(x - 1, 28, 3, 3, accent)
            c.set(x, 29, (255, 230, 150, 255))
        for i, x in enumerate(range(4, 24, 6)):
            flag = accent if i % 2 == 0 else WHITE
            c.rect(x, horizon_y - 8, 3, 3, flag)
    return c

def table_extra():
    """standalone café table + shadow, for tables bought beyond the baked-in pair."""
    c = Canvas(26, 20, CLEAR)
    for x in range(2, 26):
        for y in range(15, 19):
            if (x + y) % 2 == 0:
                c.set(x, y, (0, 0, 0, 60))
    c.rect(2, 2, 22, 4, WOOD_L)
    c.hline(2, 2, 22, INK)
    c.hline(2, 5, 22, _shade(WOOD_L, 0.8))
    c.rect(11, 6, 4, 10, WOOD_D)
    c.rect(8, 16, 10, 2, WOOD_D)
    return c

def bar_stool():
    """counter-side stool, for seating expanded past the floor tables."""
    c = Canvas(14, 18, CLEAR)
    for x in range(1, 14):
        for y in range(15, 17):
            if (x + y) % 2 == 0:
                c.set(x, y, (0, 0, 0, 55))
    c.rect(2, 2, 10, 3, WOOD_L)
    c.hline(2, 2, 10, INK)
    c.hline(2, 4, 10, _shade(WOOD_L, 0.8))
    c.vline(4, 5, 9, WOOD_D); c.vline(9, 5, 9, WOOD_D)
    c.hline(3, 10, 8, WOOD_D)                     # foot rail
    return c

# ---------------------------------------------------------------- main


# ---------------------------------------------------------------- v2: palettes

PALETTES = {
    "brown":  ((150, 102, 66, 255), (112, 72, 46, 255)),
    "cream":  ((228, 214, 202, 255), (186, 168, 155, 255)),
    "orange": ((212, 110, 58, 255), (160, 76, 38, 255)),
    "gray":   ((138, 130, 140, 255), (100, 92, 104, 255)),
}
SPECIES = ["cat", "corgi", "bunny", "fox", "bear", "owl", "raccoon", "panda", "deer"]
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
    """frames: 0 normal, 1 blink, 2 happy, 3 sleep, 4 sip, 5/6 brewing
    (5 and 6 alternate as a 2-frame 'making coffee' cycle: cup up with
    steam that wiggles between frames — shown while the player is
    actively typing, so the menu bar buddy visibly works the machine)"""
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
    elif species == "panda":
        for x0 in (2, 12):
            c.rect(x0, 1, 3, 2, (58, 56, 64, 255))
            c.set(x0, 1, INK); c.set(x0 + 2, 1, INK); c.set(x0 + 1, 0, INK)
    elif species == "deer":
        for x0 in (3, 13):
            c.vline(x0, 0, 3, (150, 112, 70, 255))
            c.set(x0 + (1 if x0 == 3 else -1), 0, (150, 112, 70, 255))
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
    if species == "panda":
        c.rect(4, 6, 3, 3, (58, 56, 64, 255)); c.rect(11, 6, 3, 3, (58, 56, 64, 255))
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
    elif frame in (5, 6):                             # brewing cycle
        # cup held up with crema + handle (like sip)...
        c.rect(6, 13, 6, 4, (206, 106, 76, 255))
        c.hline(6, 12, 6, WHITE)
        c.vline(5, 12, 5, INK); c.vline(12, 12, 5, INK)
        c.hline(6, 17, 6, INK)
        c.set(13, 13, INK); c.set(14, 14, INK); c.set(13, 15, INK)
        # ...plus rising steam that wiggles between the two frames
        steam = (235, 235, 240, 225)
        faint = (235, 235, 240, 150)
        if frame == 5:
            c.set(7, 11, steam); c.set(8, 10, steam); c.set(7, 9, faint)
            c.set(10, 11, faint); c.set(11, 10, steam)
        else:
            c.set(8, 11, steam); c.set(7, 10, steam); c.set(8, 9, faint)
            c.set(11, 11, steam); c.set(10, 10, faint); c.set(11, 9, faint)
        # focused open eyes stay (default), tiny effort blush
        c.set(4, 11, (240, 150, 150, 140)); c.set(13, 11, (240, 150, 150, 140))
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

def bubble_sad():
    c = Canvas(16, 15)
    bgc = (168, 178, 196, 255)
    c.rect(1, 1, 14, 11, bgc)
    c.hline(2, 0, 12, bgc)
    c.set(1, 1, CLEAR); c.set(14, 1, CLEAR)
    c.set(4, 12, bgc); c.set(5, 13, bgc)
    # sad face
    c.set(6, 4, INK); c.set(10, 4, INK)
    c.hline(6, 8, 5, INK)
    c.set(6, 9, INK); c.set(10, 7, INK)
    c.set(12, 3, (140, 190, 235, 255))  # tear
    return c

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
    """corner web: angled radial spokes (avoiding the bare edges, so rings
    read as diagonal web strands rather than a solid stair-step bracket) plus
    dashed concentric capture-spiral rings connecting them."""
    c = Canvas(18, 18, CLEAR)
    w = (225, 225, 232, 220)
    spokes = [(17, 3), (15, 9), (9, 15), (3, 17)]
    for ex, ey in spokes:
        _line(c, 0, 0, ex, ey, w)
    for idx, frac in enumerate((0.4, 0.7, 0.98)):
        pts = [(round(ex * frac), round(ey * frac)) for ex, ey in spokes]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            _dashed_line(c, x0, y0, x1, y1, w, phase=idx)
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

# ---------------------------------------------------------------- seasonal overlay sprites
# Small, reusable-across-all-cities decoration sprites for CafeScene's seasonal
# overlay: a drifting particle per season (snow/leaves/petals) plus one small
# door-topper prop for winter. Deliberately tiny — these are layered on top of
# existing per-city background art, not a redraw of it.

def snowflake():
    c = Canvas(3, 3, CLEAR)
    c.set(1, 0, (255, 255, 255, 220))
    c.set(0, 1, (255, 255, 255, 190)); c.set(1, 1, (255, 255, 255, 255)); c.set(2, 1, (255, 255, 255, 190))
    c.set(1, 2, (255, 255, 255, 220))
    return c

def leaf_particle():
    """small autumn leaf, warm amber."""
    c = Canvas(4, 4, CLEAR)
    col = (214, 122, 48, 255)
    col_d = (172, 88, 36, 255)
    c.set(1, 0, col); c.set(2, 0, col)
    c.set(0, 1, col); c.set(1, 1, col); c.set(2, 1, col_d); c.set(3, 1, col)
    c.set(1, 2, col_d); c.set(2, 2, col)
    c.set(2, 3, col_d)
    return c

def petal_particle():
    """small spring blossom petal, soft pink — same silhouette as leaf_particle
    so the two read as a matched pair of drifting-particle sprites."""
    c = Canvas(4, 4, CLEAR)
    col = (244, 168, 186, 255)
    col_d = (222, 138, 158, 255)
    c.set(1, 0, col); c.set(2, 0, col)
    c.set(0, 1, col); c.set(1, 1, col); c.set(2, 1, col_d); c.set(3, 1, col)
    c.set(1, 2, col_d); c.set(2, 2, col)
    c.set(2, 3, col_d)
    return c

def wreath():
    """small winter door-topper: a green ring with red berries + a bow,
    hung above the door on indoor cities only."""
    c = Canvas(12, 12, CLEAR)
    green = (76, 128, 66, 255)
    green_d = (56, 100, 50, 255)
    ring = [(3, 0), (4, 0), (5, 0), (6, 0), (7, 0), (8, 0),
            (1, 1), (2, 1), (9, 1), (10, 1),
            (0, 2), (1, 2), (10, 2), (11, 2),
            (0, 3), (11, 3), (0, 4), (11, 4),
            (0, 5), (11, 5), (0, 6), (11, 6),
            (0, 7), (11, 7),
            (0, 8), (1, 8), (10, 8), (11, 8),
            (1, 9), (2, 9), (9, 9), (10, 9),
            (3, 10), (4, 10), (5, 10), (6, 10), (7, 10), (8, 10)]
    for i, (x, y) in enumerate(ring):
        c.set(x, y, green if i % 2 == 0 else green_d)
    for bx, by in ((5, 1), (2, 5), (9, 5), (5, 9)):
        c.set(bx, by, (196, 60, 58, 255))
    c.set(5, 11, (196, 60, 58, 255)); c.set(6, 11, (150, 40, 40, 255))
    return c

def main_v6():
    count = 0
    snowflake().save("particle_snow.png"); count += 1
    leaf_particle().save("particle_leaf.png"); count += 1
    petal_particle().save("particle_petal.png"); count += 1
    wreath().save("prop_wreath.png"); count += 1
    print(f"v6: generated {count} seasonal overlay sprites")


STAFF_SPECIES = {"mocha": "cat", "biscuit": "corgi", "poppy": "bunny", "chip": "deer",
                 "juno": "fox", "bo": "bear", "earl": "owl", "marble": "raccoon",
                 # the roster icon reuses the fox face; the helmet only exists
                 # on the full-body sprite, where there are pixels to spend
                 "comet": "fox"}

def main_v2():
    count = 0
    for sp in SPECIES:
        for pal in PALETTES:
            f0 = owner(sp, pal)
            f0.save(f"owner_{sp}_{pal}_0.png"); f0.shifted_down().save(f"owner_{sp}_{pal}_1.png")
            count += 2
            fur, fur_d = PALETTES[pal]
            for f in range(7):
                face_icon(sp, fur, fur_d, f).save(f"bar_{sp}_{pal}_{f}.png"); count += 1
    for sid, args in STAFF.items():
        for f in range(7):
            face_icon(STAFF_SPECIES[sid], args[0], args[1], f).save(f"barstaff_{sid}_{f}.png"); count += 1
    for aid, fn in ACCESSORIES.items():
        fn().save(f"acc_{aid}.png"); count += 1
    for iid, draw in ING_ICONS.items():
        _icon(lambda c, d=draw: d(c)).save(f"ing_{iid}.png"); count += 1
    for iid, draw in ITEM_ICONS.items():
        _icon(lambda c, d=draw: d(c)).save(f"item_{iid}.png"); count += 1
    bubble(False).save("bubble.png"); bubble(True).save("bubble_angry.png")
    bubble_sad().save("bubble_sad.png"); count += 3
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

def barcup(level, frame):
    c = Canvas(18, 18)
    # saucer + cup
    c.rect(3, 15, 12, 1, (230, 230, 235, 255))
    c.hline(3, 16, 12, INK)
    c.rect(5, 8, 8, 7, (206, 106, 76, 255))
    c.hline(5, 7, 8, WHITE)                     # foam
    c.set(6, 7, (240, 220, 190, 255))
    c.vline(4, 7, 8, INK); c.vline(13, 7, 8, INK)
    c.hline(5, 15, 8, INK)
    c.set(14, 9, INK); c.set(15, 10, INK); c.set(15, 11, INK); c.set(14, 12, INK)  # handle
    c.set(7, 10, (230, 140, 110, 255))          # glaze glint
    # steam: more + taller with level, frame wiggles
    if level >= 1:
        base = [(7, 5), (10, 4)] if frame == 0 else [(8, 5), (11, 4)]
        for (x, y) in base:
            c.set(x, y, (240, 240, 245, 200))
            c.set(x + (1 if frame else -1), y - 1, (240, 240, 245, 150))
    if level >= 2:
        cols = [6, 9, 12] if frame == 0 else [7, 10, 11]
        for i, x in enumerate(cols):
            for dy in range(3 + (i % 2)):
                a = 220 - dy * 45
                c.set(x + (dy % 2 if frame else -(dy % 2)), 5 - dy, (250, 250, 255, max(60, a)))
        c.set(9, 0, (255, 255, 255, 120))
    return c

MAP_SPOTS = {  # image coords (y-down)
    "home": (28, 52), "sakura": (58, 32), "neon": (94, 22), "seaside": (22, 88),
    "forest": (58, 66), "desert": (94, 82), "snowy": (128, 42), "sunset": (124, 92),
    "ember": (152, 70), "royal": (104, 52), "cloud": (148, 18), "moon": (168, 8),
}

def worldmap():
    W, H = 180, 120
    sea = (62, 108, 148, 255)
    c = Canvas(W, H, sea)
    # gentle wave dots
    for y in range(0, H, 6):
        for x in ((y // 6) % 2 * 3, ):
            for xx in range(x, W, 9):
                c.set(xx, y, (78, 124, 162, 255))
    def blob(cx, cy, rx, ry, col, edge):
        for y in range(cy - ry, cy + ry + 1):
            for x in range(cx - rx, cx + rx + 1):
                if 0 <= x < W and 0 <= y < H:
                    d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                    if d <= 1:
                        c.px[y][x] = edge if d > 0.72 else col
    # landmasses per region (theme-tinted)
    blob(30, 55, 22, 18, (150, 176, 120, 255), (118, 146, 96, 255))     # home meadows
    blob(60, 34, 16, 12, (238, 188, 204, 255), (216, 158, 180, 255))    # sakura
    blob(96, 24, 18, 11, (96, 88, 128, 255), (72, 66, 100, 255))        # neon
    blob(24, 90, 15, 11, (232, 210, 160, 255), (204, 180, 132, 255))    # seaside sands
    blob(60, 68, 16, 12, (88, 134, 84, 255), (64, 106, 66, 255))        # forest
    blob(96, 84, 18, 12, (226, 196, 130, 255), (198, 166, 104, 255))    # desert
    blob(130, 44, 15, 11, (226, 232, 242, 255), (188, 200, 220, 255))   # snowy
    blob(126, 94, 16, 10, (236, 176, 130, 255), (206, 142, 104, 255))   # sunset
    blob(154, 72, 12, 10, (110, 70, 64, 255), (84, 52, 50, 255))        # ember
    blob(106, 54, 12, 9, (150, 128, 178, 255), (122, 100, 150, 255))    # royal
    # cloud island floats
    blob(150, 19, 13, 7, (240, 244, 252, 255), (210, 218, 236, 255))
    # moon corner (night sky patch)
    for y in range(0, 16):
        for x in range(158, W):
            c.px[y][x] = (28, 26, 52, 255)
    blob(170, 8, 5, 5, (232, 228, 204, 255), (200, 196, 176, 255))
    c.set(162, 4, WHITE); c.set(176, 13, WHITE); c.set(160, 12, WHITE)
    # landmarks
    c.rect(129, 36, 2, 5, (160, 170, 190, 255)); c.set(129, 35, WHITE)          # snowy peak
    c.set(153, 66, (250, 140, 60, 255)); c.set(154, 65, (250, 190, 60, 255))    # lava
    c.rect(104, 48, 5, 5, (196, 176, 220, 255)); c.set(105, 47, GOLD); c.set(107, 47, GOLD)  # castle
    for px, py in ((56, 30), (62, 28), (66, 34)):
        c.set(px, py, (244, 150, 172, 255))                                     # blossoms
    c.rect(93, 20, 6, 4, (140, 230, 220, 255))                                  # neon block
    # dotted routes between owned-ish chain (decorative)
    order = ["home", "sakura", "neon", "seaside", "forest", "desert", "snowy", "sunset", "ember", "royal", "cloud", "moon"]
    for a, b in zip(order, order[1:]):
        x1, y1 = MAP_SPOTS[a]; x2, y2 = MAP_SPOTS[b]
        steps = max(abs(x2 - x1), abs(y2 - y1)) // 4
        for i in range(1, steps):
            t = i / steps
            c.set(int(x1 + (x2 - x1) * t), int(y1 + (y2 - y1) * t), (255, 244, 214, 130))
    # parchment border
    for i in range(2):
        col = (120, 96, 60, 255) if i == 0 else (168, 138, 92, 255)
        c.hline(i, i, W - 2 * i, col); c.hline(i, H - 1 - i, W - 2 * i, col)
        c.vline(i, i, H - 2 * i, col); c.vline(W - 1 - i, i, H - 2 * i, col)
    return c

def map_pin(kind):
    c = Canvas(9, 12)
    col = {"own": GOLD, "buy": (120, 220, 130, 255), "lock": (150, 150, 158, 255)}[kind]
    c.rect(2, 1, 5, 5, col)
    c.set(1, 2, col); c.set(7, 2, col)
    c.set(1, 3, col); c.set(7, 3, col)
    c.set(3, 6, col); c.set(5, 6, col); c.set(4, 6, col)
    c.set(4, 7, col); c.set(4, 8, tuple(max(0, v - 50) for v in col[:3]) + (255,))
    c.set(4, 3, WHITE if kind != "lock" else (100, 100, 108, 255))
    c.hline(2, 0, 5, INK)
    return c


# ---------------------------------------------------------------- v5: mahjong tiles

PIXFONT = {
    "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["##.", "..#", ".#.", "#..", "###"],
    "3": ["##.", "..#", ".#.", "..#", "##."],
    "4": ["#.#", "#.#", "###", "..#", "..#"],
    "5": ["###", "#..", "##.", "..#", "##."],
    "6": [".##", "#..", "##.", "#.#", ".#."],
    "7": ["###", "..#", ".#.", "#..", "#.."],
    "8": [".#.", "#.#", ".#.", "#.#", ".#."],
    "9": [".#.", "#.#", ".##", "..#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"],
    "S": [".##", "#..", ".#.", "..#", "##."],
    "W": ["#.#", "#.#", "#.#", "###", "#.#"],
    "N": ["#..#", "##.#", "#.##", "#..#", "#..#"],
}

def draw_char(c, ch, ox, oy, color, scale=2):
    for ry, row in enumerate(PIXFONT[ch]):
        for rx, cell in enumerate(row):
            if cell == "#":
                c.rect(ox + rx * scale, oy + ry * scale, scale, scale, color)

def mahjong_tile(suit, rank):
    W, H = 18, 24
    c = Canvas(W, H)
    for y in range(H):
        f = 1.0 - 0.05 * (y / H)
        for x in range(W):
            c.px[y][x] = _shade((250, 248, 244), f) if 1 <= x < W - 1 and 1 <= y < H - 1 else CLEAR
    c.hline(1, 1, W - 2, INK); c.hline(1, H - 2, W - 2, INK)
    c.vline(1, 1, H - 2, INK); c.vline(W - 2, 1, H - 2, INK)
    c.hline(2, 2, W - 4, (255, 255, 255, 255))   # top glint

    if suit == 3:
        if rank <= 4:
            letter = "ENWS"[rank - 1] if rank != 3 else "W"
            letter = {1: "E", 2: "S", 3: "W", 4: "N"}[rank]
            draw_char(c, letter, 4, 8, (46, 62, 110, 255), scale=2)
        elif rank == 5:  # red dragon
            c.rect(6, 8, 6, 8, (196, 60, 54, 255))
            c.rect(8, 6, 2, 12, (196, 60, 54, 255))
        elif rank == 6:  # green dragon
            for i in range(4):
                c.rect(5 + i * 2, 7 + i, 3, 2, (70, 140, 82, 255))
        else:            # white dragon: blank tile, double blue frame
            c.hline(3, 4, W - 6, (74, 108, 168, 255)); c.hline(3, H - 5, W - 6, (74, 108, 168, 255))
            c.vline(3, 4, H - 8, (74, 108, 168, 255)); c.vline(W - 4, 4, H - 8, (74, 108, 168, 255))
        return c

    suit_color = [(180, 64, 56, 255), (58, 96, 168, 255), (64, 132, 78, 255)][suit]
    digit = str(rank)
    draw_char(c, digit, 5, 3, suit_color, scale=2)
    if suit == 0:      # characters: calligraphy strokes
        c.hline(5, 16, 8, suit_color); c.hline(6, 18, 6, suit_color)
    elif suit == 1:    # dots: pip cluster sized by rank
        pts = [(9, 17)] if rank <= 3 else [(6, 15), (12, 15), (9, 19)] if rank <= 6 else [(6, 14), (12, 14), (6, 19), (12, 19), (9, 16)]
        for (px, py) in pts[:min(len(pts), 5)]:
            c.rect(px - 1, py - 1, 2, 2, suit_color)
    else:              # bamboo: vertical stick count
        n = min(rank, 5)
        span = 12
        step = span // max(1, n - 1) if n > 1 else 0
        start = 9 - (step * (n - 1)) // 2 if n > 1 else 9
        for i in range(n):
            x = start + i * step if n > 1 else 9
            c.vline(x, 14, 6, suit_color)
    return c

def coin_icon(alert=False):
    c = Canvas(11, 11)
    fill = (224, 90, 70, 255) if alert else GOLD
    fill_d = (176, 58, 46, 255) if alert else GOLD_D
    c.rect(2, 1, 7, 9, fill)
    c.vline(1, 2, 7, fill); c.vline(9, 2, 7, fill)
    c.hline(2, 0, 7, fill_d); c.hline(2, 10, 7, fill_d)
    c.set(1, 2, fill_d); c.set(9, 2, fill_d); c.set(1, 8, fill_d); c.set(9, 8, fill_d)
    c.rect(4, 3, 3, 5, fill_d)
    c.set(3, 2, (255, 224, 140, 255) if not alert else (255, 180, 160, 255))
    c.set(4, 1, (255, 224, 140, 255) if not alert else (255, 180, 160, 255))
    return c

def warn_icon():
    c = Canvas(11, 11)
    pts = []
    for y in range(2, 10):
        half = (y - 2) // 2 + 1
        for x in range(5 - half, 6 + half):
            c.set(x, y, (232, 150, 40, 255))
    c.vline(5, 3, 3, (40, 26, 14, 255))
    c.set(5, 7, (40, 26, 14, 255))
    return c

def bolt_icon():
    c = Canvas(11, 11)
    col = (255, 214, 60, 255)
    pts = [(6,0),(5,1),(6,1),(4,2),(5,2),(3,3),(4,3),(5,4),(6,4),(4,5),
           (5,5),(6,5),(5,6),(6,7),(5,8),(4,9),(3,10)]
    for (x,y) in pts:
        c.set(x, y, col)
    return c

def main_v5():
    count = 0
    for suit in range(3):
        for rank in range(1, 10):
            mahjong_tile(suit, rank).save(f"mjtile_{suit}_{rank}.png"); count += 1
    for rank in range(1, 8):
        mahjong_tile(3, rank).save(f"mjtile_3_{rank}.png"); count += 1
    coin_icon().save("icon_coin.png")
    coin_icon(alert=True).save("icon_coin_alert.png")
    warn_icon().save("icon_warn.png")
    bolt_icon().save("icon_bolt.png")
    count += 4
    print(f"v5: generated {count} mahjong tile + menu bar icon sprites")

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
    worldmap().save("worldmap.png"); count += 1
    for k in ("own", "buy", "lock"):
        map_pin(k).save(f"pin_{k}.png"); count += 1
    for lvl in range(3):
        for f in range(2):
            barcup(lvl, f).save(f"barcup_{lvl}_{f}.png"); count += 1
    light_shaft().save("shaft.png"); count += 1
    print(f"v4: generated {count} more sprites")

def split_staff_layers(c, fur, fur_d, apron):
    """Split a rendered character canvas into recolorable layers for the staff
    color customization feature. `bodylight`/`bodydark` are opaque-white masks
    over the fur/fur_d pixels (tinted at runtime via colorBlendFactor=1, with
    bodydark meant to receive a programmatically-darkened version of whatever
    tint bodylight gets — so any custom color still gets believable shading);
    `clothes` is the same kind of mask over apron pixels; `detail` keeps every
    other pixel (outlines, eyes, ears, stitching...) at its original color,
    untouched and unrecolorable, so identity-defining features never wash out."""
    bodylight = Canvas(c.w, c.h)
    bodydark = Canvas(c.w, c.h)
    clothes = Canvas(c.w, c.h)
    detail = Canvas(c.w, c.h)
    mask = (255, 255, 255, 255)
    for y in range(c.h):
        for x in range(c.w):
            p = c.px[y][x]
            if p[3] == 0:
                continue
            if p == fur:
                bodylight.set(x, y, mask)
            elif p == fur_d:
                bodydark.set(x, y, mask)
            elif apron and p == apron:
                clothes.set(x, y, mask)
            else:
                detail.set(x, y, p)
    return bodylight, bodydark, clothes, detail

def main():
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for sid, args in STAFF.items():
        fur, fur_d, belly, apron, species, accent = args
        f0 = astro_fox() if sid == "comet" else character(*args)
        f1 = f0.shifted_down()
        f0.save(f"staff_{sid}_0.png"); f1.save(f"staff_{sid}_1.png")
        count += 2
        for fi, frame in enumerate((f0, f1)):
            bodylight, bodydark, clothes, detail = split_staff_layers(frame, fur, fur_d, apron)
            bodylight.save(f"staff_{sid}_bodylight_{fi}.png")
            bodydark.save(f"staff_{sid}_bodydark_{fi}.png")
            clothes.save(f"staff_{sid}_clothes_{fi}.png")
            detail.save(f"staff_{sid}_detail_{fi}.png")
            count += 4
    for i, args in enumerate(CUSTOMERS):
        f0 = character(*args)
        f0.save(f"customer_{i}_0.png"); f0.shifted_down().save(f"customer_{i}_1.png")
        count += 2
    for eid, fn in EQUIP.items():
        for t in range(3):
            fn(t).save(f"equip_{eid}_{t}.png"); count += 1
    tip_coin().save("tip.png"); recipe_bubble().save("recipe_bubble.png"); count += 2
    table_extra().save("table_extra.png"); count += 1
    bar_stool().save("bar_stool.png"); count += 1
    for f in range(4):
        baricon(f).save(f"baricon_{f}.png"); count += 1
    for t in range(3):
        background(t).save(f"bg_tier{t}.png"); count += 1
    OUTDOOR_THEMES = {"seaside", "forest", "desert", "sunset"}
    for theme in THEMES:
        for t in range(3):
            gen = outdoor_background if theme in OUTDOOR_THEMES else background
            gen(t, theme).save(f"bg_{theme}_tier{t}.png"); count += 1
    print(f"generated {count} sprites -> {os.path.abspath(OUT)}")
    main_v2()
    main_v4()
    main_v5()
    main_v6()

if __name__ == "__main__":
    main()
