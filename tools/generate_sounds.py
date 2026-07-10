#!/usr/bin/env python3
"""Pixel Pet Café SFX generator — synthesized chiptune sounds, stdlib only."""
import math
import os
import random
import struct
import wave

OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "PixelPetCafe", "Resources", "Sounds")
RATE = 22050
random.seed(7)


def write_wav(name, samples):
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples))


def tone(freq, dur, vol=0.5, shape="sine", decay=6.0, slide=0.0):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        f = freq + slide * t
        ph = 2 * math.pi * f * t
        if shape == "square":
            v = 1.0 if math.sin(ph) > 0 else -1.0
        elif shape == "tri":
            v = 2 / math.pi * math.asin(math.sin(ph))
        else:
            v = math.sin(ph)
        env = math.exp(-decay * t)
        out.append(v * vol * env)
    return out


def noise(dur, vol=0.4, decay=18.0, lowpass=0.4):
    n = int(RATE * dur)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / RATE
        raw = random.uniform(-1, 1)
        prev = prev * lowpass + raw * (1 - lowpass)
        out.append(prev * vol * math.exp(-decay * t))
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] if i < len(p) else 0 for p in parts) for i in range(n)]


def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out += p
        out += [0.0] * int(RATE * gap)
    return out


# coin: bright double ping
write_wav("coin.wav", mix(tone(1320, 0.10, 0.35, "tri", 22),
                          seq([0.0] * int(RATE * 0.04)) + tone(1760, 0.12, 0.3, "tri", 18)))
# golden tip: ascending sparkle arpeggio
write_wav("tip.wav", seq(tone(880, 0.07, 0.3, "square", 14), tone(1108, 0.07, 0.3, "square", 14),
                         tone(1318, 0.07, 0.3, "square", 14), tone(1760, 0.16, 0.32, "tri", 10)))
# angry: low descending buzz
write_wav("angry.wav", mix(tone(220, 0.22, 0.3, "square", 8, slide=-260), noise(0.14, 0.12, 22)))
# sad: two soft falling notes
write_wav("sad.wav", seq(tone(660, 0.12, 0.22, "tri", 10), tone(494, 0.2, 0.22, "tri", 8)))
# casino win: little fanfare
write_wav("win.wav", seq(tone(660, 0.09, 0.3, "square", 10), tone(880, 0.09, 0.3, "square", 10),
                         tone(1108, 0.09, 0.3, "square", 10),
                         mix(tone(1318, 0.3, 0.22, "tri", 5), tone(880, 0.3, 0.18, "tri", 5))))
# lose: descending womp
write_wav("lose.wav", seq(tone(392, 0.12, 0.25, "square", 9), tone(294, 0.22, 0.25, "square", 7)))
# mahjong tile clack
write_wav("clack.wav", mix(noise(0.05, 0.5, 60, 0.15), tone(2200, 0.03, 0.15, "sine", 60)))
# sweep: soft swish
write_wav("sweep.wav", noise(0.35, 0.28, 7, 0.75))
# event chime: attention two-note
write_wav("event.wav", seq(tone(988, 0.1, 0.28, "tri", 10), tone(1318, 0.22, 0.28, "tri", 7)))
# achievement: rising triumph
write_wav("achieve.wav", seq(tone(784, 0.08, 0.3, "square", 12), tone(988, 0.08, 0.3, "square", 12),
                             tone(1175, 0.08, 0.3, "square", 12),
                             mix(tone(1568, 0.35, 0.24, "tri", 4), tone(1175, 0.35, 0.18, "tri", 4))))
# purchase: satisfying pop-ding
write_wav("buy.wav", seq(mix(noise(0.03, 0.3, 50, 0.2), tone(520, 0.05, 0.25, "square", 25)),
                         tone(1040, 0.11, 0.28, "tri", 14)))
# big spender: cash register cha-ching
write_wav("chaching.wav", seq(mix(noise(0.04, 0.35, 45, 0.2), tone(1200, 0.04, 0.2, "square", 30)),
                              mix(tone(1568, 0.22, 0.3, "tri", 8), tone(1976, 0.22, 0.2, "tri", 8))))
# jackpot fanfare: triad arpeggios climbing an octave into a held chord
write_wav("fanfare.wav", seq(tone(523, 0.09, 0.28, "square", 10), tone(659, 0.09, 0.28, "square", 10),
                             tone(784, 0.09, 0.28, "square", 10),
                             tone(659, 0.09, 0.28, "square", 10), tone(784, 0.09, 0.28, "square", 10),
                             tone(988, 0.09, 0.28, "square", 10),
                             tone(1047, 0.08, 0.3, "square", 10), tone(1319, 0.08, 0.3, "square", 10),
                             mix(tone(1568, 0.5, 0.22, "tri", 3), tone(1319, 0.5, 0.18, "tri", 3),
                                 tone(1047, 0.5, 0.16, "tri", 3), tone(523, 0.5, 0.14, "tri", 3))))
# quest complete: short bright 3-note chime
write_wav("goal_done.wav", seq(tone(1047, 0.09, 0.28, "tri", 12), tone(1319, 0.09, 0.28, "tri", 12),
                               tone(1760, 0.28, 0.3, "tri", 6)))
# holiday jingle: cheerful bell-like phrase
write_wav("holiday.wav", seq(tone(784, 0.11, 0.26, "tri", 10), tone(988, 0.11, 0.26, "tri", 10),
                             tone(784, 0.11, 0.26, "tri", 10), tone(1175, 0.11, 0.26, "tri", 10),
                             mix(tone(1568, 0.3, 0.26, "tri", 6), tone(988, 0.3, 0.16, "tri", 6))))


# ---- ambient loops -----------------------------------------------------------
# Every note uses a fully-contained attack/release envelope (zero at both
# ends) and is placed inside a fixed-length buffer, so the loop point is
# seamless: no decaying tail is ever cut off and there is no leading silence.

def pad(freq, dur, vol=0.1, shape="tri", attack=0.05, release=0.2):
    n = int(RATE * dur)
    a, r = int(RATE * attack), int(RATE * release)
    out = []
    for i in range(n):
        t = i / RATE
        ph = 2 * math.pi * freq * t
        if shape == "square":
            v = 1.0 if math.sin(ph) > 0 else -1.0
        elif shape == "tri":
            v = 2 / math.pi * math.asin(math.sin(ph))
        else:
            v = math.sin(ph)
        env = min(1.0, i / max(1, a), (n - 1 - i) / max(1, r))
        out.append(v * vol * max(0.0, env))
    return out


def place(buf, samples, at):
    i0 = int(RATE * at)
    for j, s in enumerate(samples):
        if 0 <= i0 + j < len(buf):
            buf[i0 + j] += s


def normalize(buf, peak):
    top = max(abs(s) for s in buf) or 1.0
    return [s * peak / top for s in buf]


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


# café ambience: warm lo-fi triangle pad, I-vi-IV-V in C, sparse melody
LOOP = 8.0
buf = [0.0] * int(RATE * LOOP)
progression = [  # (start, [chord midi notes]) — 2s per chord, release inside the bar
    (0.0, [48, 55, 60, 64]),   # C
    (2.0, [45, 52, 57, 60]),   # Am
    (4.0, [41, 48, 53, 57]),   # F
    (6.0, [43, 50, 55, 59]),   # G
]
for start, notes in progression:
    for k, n in enumerate(notes):
        place(buf, pad(midi(n), 1.9, 0.07 if k else 0.09, "tri", 0.25, 0.6), start)
for start, n, dur in [(0.8, 76, 0.5), (3.2, 72, 0.6), (4.6, 74, 0.5), (6.8, 71, 0.9)]:
    place(buf, pad(midi(n), dur, 0.05, "sine", 0.03, 0.25), start)
write_wav("ambient_cafe.wav", normalize(buf, 0.18))

# casino ambience: jazzy A-minor walking bass with swung square stabs
buf = [0.0] * int(RATE * LOOP)
walk = [45, 48, 50, 52, 53, 52, 50, 48,   # Am climb & back
        43, 47, 50, 52, 53, 55, 52, 47]   # G/E7 colour walk
for i, n in enumerate(walk):
    place(buf, pad(midi(n), 0.42, 0.11, "tri", 0.01, 0.18), i * 0.5)
stabs = [  # (start, chord) — swung off-beat square hits
    (0.75, [69, 72, 76]), (2.75, [69, 72, 76]),
    (4.75, [67, 71, 74]), (6.25, [68, 71, 76]), (7.25, [69, 72, 76]),
]
for start, notes in stabs:
    for n in notes:
        place(buf, pad(midi(n), 0.22, 0.035, "square", 0.01, 0.12), start)
for start, n in [(1.75, 81), (5.75, 79)]:   # sparse noodle notes
    place(buf, pad(midi(n), 0.4, 0.045, "sine", 0.02, 0.2), start)
write_wav("ambient_casino.wav", normalize(buf, 0.18))

print("generated 15 sounds ->", os.path.abspath(OUT))
