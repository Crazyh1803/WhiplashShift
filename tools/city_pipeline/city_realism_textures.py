"""Shared PBR material library for the city realism conversion (numpy + stdlib, deterministic).

14 library materials: 12 PBR sets (albedo 512 / ORM 512 / normal 512) + `sign_atlas` (albedo 1024, emissive 1024, ORM 512) + `lamp_glass`
(texture-free, emissive factor). 12*3 + 3 = 39 unique images. ORM channels: R occlusion, G roughness, B metallic; normals OpenGL (+Y).
Reuses the recipes of industrial_market_textures (the approved benchmark pipeline). Run standalone: python city_realism_textures.py <outdir>
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import industrial_market_textures as TX  # noqa: E402

fbm, _grid, _col = TX.fbm, TX._grid, TX._col

# material -> (recipe key, normal strength, uv tiles per metre, emission whitelist flag)
LIBRARY = [
    "steel_structure", "cladding_corrugated", "cladding_patch", "concrete", "brick", "render_plaster", "roof_membrane",
    "paving", "equipment_steel", "glass_window", "fabric_awning", "plastic_rubber", "sign_atlas", "lamp_glass",
]
UV_PER_M = {"steel_structure": 1.0, "cladding_corrugated": 0.6, "cladding_patch": 0.8, "concrete": 0.4, "brick": 0.5, "render_plaster": 0.35,
            "roof_membrane": 0.3, "paving": 0.35, "equipment_steel": 1.0, "glass_window": 0.7, "fabric_awning": 0.45, "plastic_rubber": 1.5}
# glTF factor fallbacks (baseColor, roughness, metallic) used by the texture-free library binding
FACTORS = {"steel_structure": ((0.15, 0.16, 0.18), 0.55, 0.7), "cladding_corrugated": ((0.28, 0.33, 0.32), 0.6, 0.45), "cladding_patch": ((0.5, 0.33, 0.12), 0.6, 0.4),
           "concrete": ((0.36, 0.35, 0.33), 0.85, 0.0), "brick": ((0.36, 0.17, 0.11), 0.9, 0.0), "render_plaster": ((0.5, 0.47, 0.4), 0.9, 0.0),
           "roof_membrane": ((0.09, 0.09, 0.09), 0.9, 0.0), "paving": ((0.24, 0.24, 0.24), 0.85, 0.0), "equipment_steel": ((0.5, 0.52, 0.55), 0.4, 0.85),
           "glass_window": ((0.05, 0.08, 0.1), 0.15, 0.1), "fabric_awning": ((0.45, 0.1, 0.08), 0.85, 0.0), "plastic_rubber": ((0.06, 0.07, 0.07), 0.6, 0.0),
           "sign_atlas": ((1, 1, 1), 0.4, 0.0), "lamp_glass": ((0.9, 0.85, 0.6), 0.2, 0.0)}
EMISSIVE = {"sign_atlas": 2.0, "lamp_glass": 3.0}      # whitelist: the only emitting materials (strength factor)


# ------------------------------------------------------------------------------------------------ extra recipes
def r_brick(n, rng, color=(0.36, 0.16, 0.1), courses=16):
    y, x = _grid(n)
    row = np.floor(y * courses).astype(int)
    off = (row % 2) * 0.5
    bx = (x * courses / 2 + off) % 1.0
    by = (y * courses) % 1.0
    mortar = ((bx < 0.04) | (by < 0.09)).astype(float)
    cellid = (np.floor(x * courses / 2 + off).astype(int) * 7 + row * 13) % 17 / 17.0
    mott = fbm(n, 4, rng, 5)
    grain = fbm(n, 90, rng, 2)
    tone = 0.75 + 0.5 * cellid + 0.25 * (mott - 0.5)
    base = _col(color)
    alb = base[None, None, :] * (tone * (0.9 + 0.2 * grain))[..., None]
    mort = np.array([0.30, 0.29, 0.27])[None, None, :] * (0.8 + 0.4 * fbm(n, 30, rng, 3))[..., None]
    alb = alb * (1 - mortar[..., None]) + mort * mortar[..., None]
    eff = np.clip((fbm(n, 4, rng, 4, aniso=(1, 2)) - 0.62) * 5, 0, 1)                   # efflorescence / soot patches
    alb = alb * (1 - 0.45 * eff[..., None]) + 0.25 * eff[..., None] * 0.7
    drip = np.clip((fbm(n, 3, rng, 4, aniso=(0.12, 18)) - 0.55) * 4, 0, 1) * 0.5
    alb *= (1 - drip[..., None])
    height = 0.62 - 0.4 * mortar + 0.1 * (grain - 0.5) + 0.08 * cellid
    rough = np.clip(0.8 + 0.1 * grain + 0.1 * mortar, 0, 1)
    return np.clip(alb, 0, 1), rough, np.zeros((n, n)), height


def r_plaster(n, rng, color=(0.52, 0.48, 0.4), cracks=0.22):
    base = _col(color)
    mott = fbm(n, 3, rng, 6)
    grain = fbm(n, 80, rng, 2)
    stain = np.clip((fbm(n, 3, rng, 5) - 0.5) * 3.5, 0, 1)
    drip = np.clip((fbm(n, 3, rng, 4, aniso=(0.1, 22)) - 0.5) * 4, 0, 1) * 0.55
    ct = fbm(n, 5, rng, 3)
    crack = np.clip(1 - np.abs(ct - 0.5) * 60, 0, 1) * cracks * (fbm(n, 2, rng, 3) > 0.45)
    spall = np.clip((fbm(n, 6, rng, 5) - 0.74) * 9, 0, 1)                                  # plaster fallen away, exposing brick
    alb = base[None, None, :] * (0.75 + 0.35 * mott + 0.1 * grain)[..., None]
    alb *= (1 - 0.4 * stain[..., None] - 0.5 * drip[..., None]) * np.array([1.0, 0.97, 0.9])[None, None, :]
    alb *= (1 - 0.6 * crack[..., None])
    alb = alb * (1 - spall[..., None]) + spall[..., None] * np.array([0.33, 0.17, 0.12])
    height = 0.55 + 0.15 * (grain - 0.5) - 0.4 * crack - 0.3 * spall
    return np.clip(alb, 0, 1), np.clip(0.88 + 0.1 * grain - 0.2 * spall, 0, 1), np.zeros((n, n)), height


def r_roof(n, rng, color=(0.075, 0.075, 0.08)):
    base = _col(color)
    grav = fbm(n, 110, rng, 2)
    mott = fbm(n, 4, rng, 5)
    pond = np.clip((fbm(n, 3, rng, 4) - 0.6) * 4, 0, 1)
    patch = (fbm(n, 5, rng, 3) > 0.7).astype(float)
    alb = base[None, None, :] * (0.7 + 0.9 * grav * (0.4 + mott) + 0.2 * (mott - 0.5))[..., None]
    alb = alb * (1 - patch[..., None]) + patch[..., None] * np.array([0.04, 0.04, 0.045]) * (0.8 + 0.4 * grav)[..., None]
    alb = alb * (1 - 0.3 * pond[..., None]) + pond[..., None] * 0.06 * np.array([0.8, 0.9, 1.0])
    return np.clip(alb, 0, 1), np.clip(0.9 - 0.45 * pond, 0, 1), np.zeros((n, n)), 0.5 + 0.35 * (grav - 0.5) - 0.1 * pond


def r_paving(n, rng, color=(0.23, 0.23, 0.225)):
    y, x = _grid(n)
    k = 4
    jx = np.abs(((x * k) % 1.0) - 0.5)
    jy = np.abs(((y * k) % 1.0) - 0.5)
    joint = np.clip(1 - np.minimum(0.5 - jx, 0.5 - jy) * n / k / 2.2, 0, 1)
    slab = (np.floor(x * k) * 3 + np.floor(y * k) * 5) % 7 / 7.0
    base = _col(color)
    agg = fbm(n, 70, rng, 3)
    mott = fbm(n, 3, rng, 6)
    oil = np.clip((fbm(n, 6, rng, 4) - 0.7) * 7, 0, 1)
    ct = fbm(n, 5, rng, 3)
    crack = np.clip(1 - np.abs(ct - 0.5) * 26, 0, 1) * (fbm(n, 2, rng, 3) > 0.5) * 0.7
    alb = base[None, None, :] * (0.72 + 0.4 * slab * 0.5 + 0.3 * mott + 0.15 * agg)[..., None]
    alb *= (1 - 0.65 * joint - 0.6 * crack - 0.5 * oil)[..., None]
    rough = np.clip(0.88 + 0.08 * agg - 0.5 * oil, 0, 1)
    return np.clip(alb, 0, 1), rough, np.zeros((n, n)), 0.5 + 0.3 * (agg - 0.5) - 0.45 * joint - 0.3 * crack


def r_glass(n, rng, color=(0.05, 0.08, 0.1)):
    base = _col(color)
    smudge = fbm(n, 4, rng, 5)
    drip = np.clip((fbm(n, 3, rng, 4, aniso=(0.1, 25)) - 0.5) * 4, 0, 1)
    dirt = np.clip((smudge - 0.45) * 2.5, 0, 1) * 0.5
    alb = base[None, None, :] * (0.7 + 0.8 * smudge)[..., None] + (dirt * 0.07 + drip * 0.03)[..., None] * np.array([1.0, 0.95, 0.85])
    return np.clip(alb, 0, 1), np.clip(0.1 + 0.55 * dirt + 0.2 * drip, 0, 1), np.full((n, n), 0.05), 0.5 + 0.05 * (smudge - 0.5)


# ------------------------------------------------------------------------------------------------ sign atlas
FONT = {  # 5x7 bitmap font, rows top->bottom
    "A": "01110/10001/10001/11111/10001/10001/10001", "B": "11110/10001/10001/11110/10001/10001/11110", "C": "01110/10001/10000/10000/10000/10001/01110",
    "D": "11110/10001/10001/10001/10001/10001/11110", "E": "11111/10000/10000/11110/10000/10000/11111", "F": "11111/10000/10000/11110/10000/10000/10000",
    "G": "01110/10001/10000/10111/10001/10001/01111", "H": "10001/10001/10001/11111/10001/10001/10001", "I": "01110/00100/00100/00100/00100/00100/01110",
    "J": "00111/00010/00010/00010/00010/10010/01100", "K": "10001/10010/10100/11000/10100/10010/10001", "L": "10000/10000/10000/10000/10000/10000/11111",
    "M": "10001/11011/10101/10101/10001/10001/10001", "N": "10001/11001/10101/10011/10001/10001/10001", "O": "01110/10001/10001/10001/10001/10001/01110",
    "P": "11110/10001/10001/11110/10000/10000/10000", "Q": "01110/10001/10001/10001/10101/10010/01101", "R": "11110/10001/10001/11110/10100/10010/10001",
    "S": "01111/10000/10000/01110/00001/00001/11110", "T": "11111/00100/00100/00100/00100/00100/00100", "U": "10001/10001/10001/10001/10001/10001/01110",
    "V": "10001/10001/10001/10001/10001/01010/00100", "W": "10001/10001/10001/10101/10101/11011/10001", "X": "10001/10001/01010/00100/01010/10001/10001",
    "Y": "10001/10001/01010/00100/00100/00100/00100", "Z": "11111/00001/00010/00100/01000/10000/11111", "0": "01110/10011/10101/10101/10101/11001/01110",
    "1": "00100/01100/00100/00100/00100/00100/01110", "2": "01110/10001/00001/00110/01000/10000/11111", "3": "11110/00001/00001/01110/00001/00001/11110",
    "4": "00010/00110/01010/10010/11111/00010/00010", "5": "11111/10000/11110/00001/00001/10001/01110", "6": "00110/01000/10000/11110/10001/10001/01110",
    "7": "11111/00001/00010/00100/01000/01000/01000", "8": "01110/10001/10001/01110/10001/10001/01110", "9": "01110/10001/10001/01111/00001/00010/01100",
    " ": "00000/00000/00000/00000/00000/00000/00000", "-": "00000/00000/00000/11111/00000/00000/00000",
}
SIGNS = [  # (text, icon, panel colour, text colour) — 16 tiles, 2 columns x 8 rows of 512x128 (index = row*2 + col)
    ("NOODLES", "bowl", (0.45, 0.05, 0.04), (1.0, 0.9, 0.75)), ("TOOL HIRE", "wrench", (0.08, 0.2, 0.3), (0.9, 0.95, 1.0)),
    ("LAUNDRY", "drop", (0.1, 0.28, 0.3), (0.85, 1.0, 1.0)), ("FREIGHT", "box", (0.55, 0.38, 0.05), (0.1, 0.08, 0.04)),
    ("ELECTRICITY", "bolt", (0.9, 0.75, 0.1), (0.05, 0.05, 0.05)), ("WATER", "drop", (0.05, 0.22, 0.4), (0.9, 0.97, 1.0)),
    ("TRANSIT", "arrow", (0.1, 0.1, 0.12), (1.0, 0.82, 0.3)), ("HOUSING", "key", (0.2, 0.22, 0.18), (0.95, 0.95, 0.8)),
    ("GARAGE", "gear", (0.12, 0.12, 0.14), (0.95, 0.5, 0.15)), ("PLUMBING", "drop", (0.25, 0.3, 0.32), (0.95, 1.0, 1.0)),
    ("MACHINERY", "gear", (0.3, 0.12, 0.05), (1.0, 0.85, 0.6)), ("CAR WASH", "drop", (0.05, 0.3, 0.2), (0.9, 1.0, 0.95)),
    ("POST OFFICE", "box", (0.35, 0.05, 0.05), (1.0, 0.9, 0.7)), ("HEATING", "bolt", (0.45, 0.14, 0.05), (1.0, 0.8, 0.5)),
    ("PARTS 24", "gear", (0.08, 0.22, 0.12), (0.9, 1.0, 0.85)), ("OPEN", "arrow", (0.1, 0.1, 0.1), (0.4, 1.0, 0.5)),
]
TILE_W, TILE_H = 512, 128


def sign_tile_uv(idx):
    """Blender-convention (v up) UV rectangle (u0, v0, u1, v1) of sign tile idx inside the 1024 atlas."""
    c, r = idx % 2, idx // 2
    return (c * 0.5 + 0.01, 1 - (r + 1) / 8 + 0.01, (c + 1) * 0.5 - 0.01, 1 - r / 8 - 0.01)


def _icon_mask(kind, w, h):
    y, x = np.mgrid[0:h, 0:w]
    u, v = (x - w / 2) / (h / 2), (y - h / 2) / (h / 2)
    r = np.hypot(u, v)
    if kind == "bowl":
        return ((v > -0.1) & (v < 0.55) & (r < 0.85) & (u * u + (v + 0.1) ** 2 < 0.7)) | ((v > 0.55) & (v < 0.7) & (abs(u) < 0.4))
    if kind == "wrench":
        return ((abs(u + v) < 0.2) & (r < 0.85)) | ((r < 0.38) & (abs(u - 0.3) > 0.12) & (u > 0.05))
    if kind == "drop":
        return (v > -0.2) & (u * u + (v - 0.2) ** 2 < 0.4) | ((v <= -0.2) & (v > -0.8) & (abs(u) < (v + 0.8) * 0.6 * 0.85))
    if kind == "box":
        return (abs(u) < 0.7) & (abs(v) < 0.55) & ~((abs(u) < 0.08)) & ~(abs(v + 0.25) < 0.05)
    if kind == "bolt":
        return ((abs(u + 0.3 * v) < 0.22) & (abs(v) < 0.8) & (v < 0.1)) | ((abs(u - 0.2 + 0.4 * v) < 0.22) & (v >= -0.1) & (v < 0.8))
    if kind == "arrow":
        return ((abs(v) < 0.18) & (u > -0.8) & (u < 0.2)) | ((u >= 0.1) & (u < 0.85) & (abs(v) < (0.85 - u) * 0.9))
    if kind == "key":
        return ((r < 0.35) & (r > 0.14) & (u < 0.0)) | ((abs(v) < 0.1) & (u > -0.2) & (u < 0.8)) | ((abs(u - 0.6) < 0.08) & (v > 0) & (v < 0.35))
    if kind == "gear":
        a = np.arctan2(v, u)
        return (r < 0.62 + 0.14 * (np.sin(a * 8) > 0)) & (r > 0.25)
    return np.zeros((h, w), bool)


def sign_atlas(rng):
    """Returns (albedo 1024x1024x3, emissive 1024x1024x3, rough, metal, height). Panel paint is albedo; glyphs + icon are painted
    light and are the only emissive texels (a few letters are 'dead' so the sign reads as maintained by someone)."""
    W = H = 1024
    alb = np.zeros((H, W, 3))
    emi = np.zeros((H, W, 3))
    rough = np.full((H, W), 0.5)
    height = np.full((H, W), 0.5)
    grime = fbm(1024, 6, rng, 5)
    for i, (text, icon, pc, tc) in enumerate(SIGNS):
        c, r = i % 2, i // 2
        x0, y0 = c * TILE_W, r * TILE_H
        panel = np.zeros((TILE_H, TILE_W, 3)) + np.array(pc)
        panel *= (0.75 + 0.4 * grime[y0:y0 + TILE_H, x0:x0 + TILE_W])[..., None]
        yy, xx = np.mgrid[0:TILE_H, 0:TILE_W]
        edge = (xx < 6) | (xx > TILE_W - 7) | (yy < 6) | (yy > TILE_H - 7)
        panel[edge] *= 0.35
        gl = np.zeros((TILE_H, TILE_W), bool)
        # icon block (left), text (rest)
        iw = TILE_H - 16
        icm = _icon_mask(icon, iw, iw)
        gl[8:8 + iw, 12:12 + iw] = icm
        cells = len(text)
        avail = TILE_W - iw - 48
        cw = min(avail // cells, 56)
        scale = max(cw // 6, 1)
        gw, gh = 5 * scale, 7 * scale
        total = cells * 6 * scale - scale
        sx = iw + 28 + (avail - total) // 2
        sy = (TILE_H - gh) // 2
        dead = (i % 5 == 3) and cells > 3                       # one dead letter on every fifth sign
        for k, chx in enumerate(text):
            g = FONT.get(chx, FONT[" "]).split("/")
            if dead and k == cells // 2:
                continue
            for ry, rowbits in enumerate(g):
                for rx, b in enumerate(rowbits):
                    if b == "1":
                        gl[sy + ry * scale:sy + (ry + 1) * scale, sx + (k * 6 + rx) * scale:sx + (k * 6 + rx + 1) * scale] = True
        col = np.array(tc)
        panel[gl] = col * (0.85 + 0.15 * grime[y0:y0 + TILE_H, x0:x0 + TILE_W][gl])[:, None]
        alb[y0:y0 + TILE_H, x0:x0 + TILE_W] = panel
        e = np.zeros((TILE_H, TILE_W, 3))
        e[gl] = col[None, :] * (0.55 + 0.45 * fbm(1024, 20, rng, 2)[y0:y0 + TILE_H, x0:x0 + TILE_W][gl])[:, None]
        emi[y0:y0 + TILE_H, x0:x0 + TILE_W] = e
        rough[y0:y0 + TILE_H, x0:x0 + TILE_W] = np.where(gl, 0.35, 0.62)
        height[y0:y0 + TILE_H, x0:x0 + TILE_W] = np.where(gl, 0.58, 0.45) - 0.2 * edge
    return np.clip(alb, 0, 1), np.clip(emi, 0, 1), rough, np.zeros((H, W)), height


# ------------------------------------------------------------------------------------------------ recipe table
def recipes():
    R = {
        "steel_structure": (lambda n, r: TX.r_painted_metal(n, r, (0.1, 0.12, 0.14), rust=0.2, panel=0, grime=0.6), 3.0),
        "cladding_corrugated": (lambda n, r: TX.r_painted_metal(n, r, (0.27, 0.34, 0.33), rust=0.3, panel=0, grime=0.6, corrugation=10), 4.0),
        "cladding_patch": (lambda n, r: TX.r_painted_metal(n, r, (0.46, 0.29, 0.09), rust=0.1, panel=3, grime=0.25), 3.0),
        "concrete": (lambda n, r: TX.r_concrete(n, r, joints=2), 4.0),
        "brick": (lambda n, r: r_brick(n, r), 4.0),
        "render_plaster": (lambda n, r: r_plaster(n, r), 3.0),
        "roof_membrane": (lambda n, r: r_roof(n, r), 4.0),
        "paving": (lambda n, r: r_paving(n, r), 4.0),
        "equipment_steel": (lambda n, r: TX.r_steel(n, r), 2.0),
        "glass_window": (lambda n, r: r_glass(n, r), 1.5),
        "fabric_awning": (lambda n, r: TX.r_awning(n, r, c1=(0.4, 0.07, 0.05), c2=(0.6, 0.55, 0.45), fade=0.25), 3.0),
        "plastic_rubber": (lambda n, r: TX.r_rubber(n, r, color=(0.07, 0.075, 0.08)), 2.0),
    }
    return R


def generate(outdir, only=None, size=512):
    """Write the library textures to outdir/<material>_{albedo,orm,normal}.png (+ sign_atlas_emissive.png). Returns {material: {slot: path}}."""
    out = {}
    for name, (fn, nstr) in recipes().items():
        if only and name not in only:
            continue
        rng = np.random.default_rng(sum(ord(c) * (i + 5) for i, c in enumerate(name)))
        alb, rough, metal, height = fn(size, rng)
        paths, _ = TX.write_set(outdir, name, alb, rough, metal, height, nstr=nstr, alb_n=size, orm_n=size, nrm_n=size)
        out[name] = paths
    if not only or "sign_atlas" in only:
        rng = np.random.default_rng(777)
        alb, emi, rough, metal, height = sign_atlas(rng)
        paths, _ = TX.write_set(outdir, "sign_atlas", alb, rough, metal, height, nstr=2.0, alb_n=1024, orm_n=512, nrm_n=512)
        paths.pop("normal")
        os.remove(os.path.join(outdir, "sign_atlas_normal.png"))     # atlas is flat: no normal map (saves an image)
        p = os.path.join(outdir, "sign_atlas_emissive.png")
        with open(p, "wb") as f:
            f.write(TX.png_bytes(emi))
        paths["emissive"] = p
        out["sign_atlas"] = paths
    return out


if __name__ == "__main__":
    o = sys.argv[1] if len(sys.argv) > 1 else "tex_city_test"
    print({k: list(v) for k, v in generate(o).items()})
