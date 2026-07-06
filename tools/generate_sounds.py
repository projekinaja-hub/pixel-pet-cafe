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
print("generated 10 sounds ->", os.path.abspath(OUT))
