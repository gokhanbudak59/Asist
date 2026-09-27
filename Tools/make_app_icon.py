#!/usr/bin/env python3
"""Asist uygulama ikonu (1024x1024, RGB, alfa YOK). Yalnız standart kütüphane.
Kullanım (Windows): python Tools/make_app_icon.py
Çıktı: App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"""
import os, struct, sys, zlib

SIZE = 1024
TOP, BOTTOM, WHITE = (0x0B, 0x3D, 0x91), (0x00, 0x96, 0x88), (0xFF, 0xFF, 0xFF)

def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

def inside_capsule(x, y, cx, top, bottom, radius):
    if top <= y <= bottom:
        return abs(x - cx) <= radius
    cy = top if y < top else bottom
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2

def pixel(x, y):
    cx = SIZE / 2
    if inside_capsule(x, y, cx, 300, 520, 110):                      # mikrofon gövdesi
        return WHITE
    d2 = (x - cx) ** 2 + (y - 520) ** 2
    if y >= 520 and 150 ** 2 <= d2 <= 190 ** 2:                      # U çatal
        return WHITE
    if 460 <= y < 520 and (abs(x - (cx - 170)) <= 20 or abs(x - (cx + 170)) <= 20):
        return WHITE
    if 710 <= y <= 800 and abs(x - cx) <= 20:                        # ayak
        return WHITE
    if 780 <= y <= 820 and abs(x - cx) <= 120:
        return WHITE
    return mix(TOP, BOTTOM, y / (SIZE - 1))

def png_bytes():
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)
        for x in range(SIZE):
            raw.extend(pixel(x, y))
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)       # 8 bit RGB
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        "App", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "wb") as f:
        f.write(png_bytes())
    print("Yazildi:", out)
