#!/usr/bin/env python3
"""Asist notification sounds (04 §7.6, D37). Run locally: python Tools/make_sounds.py — commit the two WAVs."""
import math
import os
import struct
import wave

RATE = 44100
OUT = os.environ.get("ASIST_SOUNDS_OUT") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources", "Sounds")


def tone(freq, seconds, volume=0.8):
    n = int(RATE * seconds)
    fade = int(RATE * 0.01)
    frames = bytearray()
    for i in range(n):
        env = min(1.0, i / fade, (n - i) / fade)
        sample = int(32767 * volume * env * math.sin(2 * math.pi * freq * i / RATE))
        frames += struct.pack("<h", sample)
    return bytes(frames)


def silence(seconds):
    return b"\x00\x00" * int(RATE * seconds)


def write(name, pattern, total_seconds):
    target = int(RATE * total_seconds) * 2
    data = b""
    while len(data) < target:
        for freq, dur in pattern:
            data += tone(freq, dur) if freq > 0 else silence(dur)
    data = data[:target]
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(path, round(len(data) / 2 / RATE, 1), "s")


write("asist-onemli.wav", [(880, 0.18), (0, 0.06), (1320, 0.18), (0, 0.60)], 6)
write("asist-kritik.wav", [(988, 0.15), (0, 0.10), (1480, 0.15), (0, 0.10)], 12)
