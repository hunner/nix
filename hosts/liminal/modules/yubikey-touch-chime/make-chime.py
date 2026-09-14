#!/usr/bin/env python3
"""Generate the YubiKey touch-request chime as a 16-bit stereo WAV.

Two struck tones a rising perfect fifth apart (A5 -> E6), each with a fast
attack and an exponential decay, the second overlapping the tail of the first.
Short (~0.5s) and bell-like rather than a beep, because this is the only
audible alert on the desktop and it has to be recognisable out of the corner
of the ear while a build is scrolling.

No third-party deps: stdlib `wave` + `math` only, so the Nix derivation needs
nothing but python3.

Usage: make-chime.py OUTPUT.wav
"""

import math
import struct
import sys
import wave

RATE = 48000
CHANNELS = 2
AMPLITUDE = 0.55  # headroom below full scale; pw-play does no limiting

# (start second, fundamental Hz, duration s, decay time-constant s)
NOTES = [
    (0.00, 880.00, 0.34, 0.085),  # A5
    (0.16, 1318.51, 0.38, 0.105),  # E6, a perfect fifth up
]

# Partial amplitudes relative to the fundamental. A touch of second and third
# harmonic gives it a struck-metal edge; a pure sine reads as a phone beep.
PARTIALS = [(1.0, 1.00), (2.0, 0.22), (3.0, 0.09)]

ATTACK = 0.004  # 4ms fade-in kills the click a hard start would make
TOTAL = max(start + dur for start, _f, dur, _t in NOTES)


def render():
    n = int(TOTAL * RATE)
    buf = [0.0] * n
    for start, freq, dur, tau in NOTES:
        i0 = int(start * RATE)
        for i in range(int(dur * RATE)):
            if i0 + i >= n:
                break
            t = i / RATE
            env = math.exp(-t / tau)
            if t < ATTACK:
                env *= t / ATTACK
            s = sum(a * math.sin(2 * math.pi * freq * m * t) for m, a in PARTIALS)
            buf[i0 + i] += s * env
    peak = max(abs(v) for v in buf) or 1.0
    return [v / peak * AMPLITUDE for v in buf]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make-chime.py OUTPUT.wav")
    samples = render()
    with wave.open(sys.argv[1], "wb") as w:
        w.setnchannels(CHANNELS)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for v in samples:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) * CHANNELS
        w.writeframes(bytes(frames))


if __name__ == "__main__":
    main()
