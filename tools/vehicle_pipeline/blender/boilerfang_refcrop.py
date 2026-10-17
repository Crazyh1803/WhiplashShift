"""Crop the steam-punk reference with a labelled pixel grid for measurement via ak-look.

ak-blender boilerfang_refcrop.py -- x0 y0 x1 y1 scale out.png [step]
Coordinates are pixels of the 1024x572 sheet (x right, y down). Grid lines every `step`
(default 25) px; lines at multiples of 4*step are brighter and labelled with their sheet
coordinate.
"""
import sys

import bpy
import numpy as np

DIG = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111",
    "3": "111001111001111", "4": "101101111001001", "5": "111100111001111",
    "6": "111100111101111", "7": "111001001001001", "8": "111101111101111",
    "9": "111101111001111",
}


def text(img, x, y, s, color, k=2):
    for ci, ch in enumerate(s):
        bits = DIG[ch]
        for r in range(5):
            for c in range(3):
                if bits[r * 3 + c] == "1":
                    px, py = x + (ci * 4 + c) * k, y + r * k
                    if 0 <= py < img.shape[0] - k and 0 <= px < img.shape[1] - k:
                        img[py:py + k, px:px + k] = color


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    x0, y0, x1, y1, sc = (int(v) for v in a[:5])
    out = a[5]
    step = int(a[6]) if len(a) > 6 else 25
    src = bpy.data.images.load("tools/vehicle_pipeline/references/steam-punk.jpg")
    w, h = src.size
    px = np.array(src.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]  # top-down rows
    crop = px[y0:y1, x0:x1]
    crop = np.repeat(np.repeat(crop, sc, axis=0), sc, axis=1)
    H, W = crop.shape[:2]
    for gx in range((x0 // step) * step, x1 + 1, step):
        if gx < x0:
            continue
        sx = (gx - x0) * sc
        major = gx % (step * 4) == 0
        if sx < W:
            crop[:, sx] = (1, 0.1, 0.1, 1) if major else crop[:, sx] * 0.6 + np.array([0.4, 0.4, 0, 0.4])
    for gy in range((y0 // step) * step, y1 + 1, step):
        if gy < y0:
            continue
        sy = (gy - y0) * sc
        major = gy % (step * 4) == 0
        if sy < H:
            crop[sy, :] = (0.1, 0.4, 1, 1) if major else crop[sy, :] * 0.6 + np.array([0, 0.4, 0.4, 0.4])
    for gx in range((x0 // (step * 4)) * step * 4, x1 + 1, step * 4):
        if gx >= x0:
            text(crop, (gx - x0) * sc + 3, 3, str(gx), (1, 1, 0, 1))
    for gy in range((y0 // (step * 4)) * step * 4, y1 + 1, step * 4):
        if gy >= y0:
            text(crop, 3, (gy - y0) * sc + 3, str(gy), (0, 1, 1, 1))
    img = bpy.data.images.new("crop", W, H, alpha=True)
    img.pixels = crop[::-1].reshape(-1)
    img.filepath_raw = out
    img.file_format = "PNG"
    img.save()
    print("AK: crop", out, W, H)


main()
