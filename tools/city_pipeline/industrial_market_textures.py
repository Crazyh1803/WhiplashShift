"""Procedural PBR texture sources for the industrial market benchmark (numpy + stdlib; deterministic by seed).

Each recipe returns albedo (n,n,3), roughness, metallic (n,n) and height (n,n) in 0..1; `write_set` saves
<name>_albedo.png, <name>_orm.png (R=occlusion, G=roughness, B=metallic) and <name>_normal.png (OpenGL +Y).
Tileable by construction (wrapped value noise). The skin recipes also paint a face + swatch atlas (see ATLAS).
Usage from build_industrial_market.py; run standalone: python industrial_market_textures.py <outdir>
"""
import json
import os
import struct
import sys
import zlib

import numpy as np

# Skin atlas layout in Blender UV space (u, v from bottom-left), all rectangles (u0, v0, u1, v1).
ATLAS = {
    "tile": (0.0, 0.5, 0.5, 1.0),      # tiling skin pores, used by body / hands / ears
    "face": (0.5, 0.5, 1.0, 1.0),      # front-projected face paint
    "eye": (0.0, 0.25, 0.25, 0.5),     # eyeball: sclera + iris, front projected
    "lip": (0.25, 0.25, 0.5, 0.5),     # lip swatch
    "nail": (0.5, 0.25, 0.75, 0.5),    # fingernail swatch
    "brow": (0.75, 0.25, 1.0, 0.5),    # dark brow / lash swatch
    "dark": (0.0, 0.0, 1.0, 0.25),     # nostril / shadow swatch
}
# Head-local mapping shared by the face paint and the head UVs: eye line is z=0, x metres across.
FACE_HALF_W = 0.095
FACE_Z0, FACE_Z1 = -0.135, 0.125


def face_uv(x, z):
    u0, v0, u1, v1 = ATLAS["face"]
    return (u0 + (u1 - u0) * (0.5 + 0.5 * max(-1, min(1, x / FACE_HALF_W))),
            v0 + (v1 - v0) * max(0.0, min(1.0, (z - FACE_Z0) / (FACE_Z1 - FACE_Z0))))


def _vn(n, fy, fx, rng):
    g = rng.random((fy, fx))
    ys = np.linspace(0, fy, n, endpoint=False)
    xs = np.linspace(0, fx, n, endpoint=False)
    y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
    ty, tx = ys - y0, xs - x0
    ty, tx = ty * ty * (3 - 2 * ty), tx * tx * (3 - 2 * tx)
    y1, x1 = (y0 + 1) % fy, (x0 + 1) % fx
    a = g[np.ix_(y0, x0)] * (1 - tx) + g[np.ix_(y0, x1)] * tx
    b = g[np.ix_(y1, x0)] * (1 - tx) + g[np.ix_(y1, x1)] * tx
    return a * (1 - ty[:, None]) + b * ty[:, None]


def fbm(n, f, rng, octaves=5, aniso=(1, 1), gain=0.5):
    out, amp, tot = np.zeros((n, n)), 1.0, 0.0
    for o in range(octaves):
        fy, fx = max(1, int(f * aniso[0] * 2 ** o)), max(1, int(f * aniso[1] * 2 ** o))
        out += amp * _vn(n, fy, fx, rng)
        tot += amp
        amp *= gain
    return out / tot


def _grid(n):
    y, x = np.mgrid[0:n, 0:n] / n
    return y, x


def _lerp3(a, b, t):
    return a[None, None, :] * (1 - t[..., None]) + b[None, None, :] * t[..., None]


def _col(c):
    return np.array(c, dtype=float)


# ---------------------------------------------------------------------------------------------- recipes
def r_skin(n, rng, tone, ruddy=0.0, stubble=False, seed_tag=0):
    base = _col(tone)
    blot = fbm(n, 3, rng, 4)
    pores = fbm(n, 64, rng, 2)
    fine = fbm(n, 24, rng, 3)
    alb = _lerp3(base * 0.93, base * 1.06 + np.array([0.02, 0.0, 0.0]), blot)
    alb *= (0.96 + 0.06 * pores)[..., None]
    alb[..., 0] += 0.03 * ruddy * fbm(n, 5, rng, 2)
    rough = 0.52 + 0.14 * fine
    height = 0.5 + 0.35 * (pores - 0.5) + 0.25 * (fine - 0.5)
    return alb, rough, np.zeros((n, n)), height


def r_cloth(n, rng, color, weave=96, twill=True, wear=0.25, streak=0.0, stain=0.0, color2=None):
    y, x = _grid(n)
    base = _col(color)
    u, v = x * weave, y * weave
    t = (u + (v if twill else 0)) % 1.0
    thread = 0.5 + 0.5 * np.sin(2 * np.pi * (u if not twill else (u + v))) * np.sin(2 * np.pi * v * 0.5 + np.pi * (np.floor(u) % 2))
    fiber = fbm(n, weave, rng, 2)
    mott = fbm(n, 4, rng, 5)
    shade = 0.82 + 0.18 * thread + 0.08 * (fiber - 0.5)
    alb = base[None, None, :] * (shade * (0.85 + 0.3 * mott))[..., None]
    if color2 is not None:
        m = (fbm(n, 6, rng, 4) > 0.55).astype(float) * 0.7
        alb = alb * (1 - m[..., None]) + _col(color2)[None, None, :] * (shade * m)[..., None]
    if wear:
        wmask = np.clip((fbm(n, 5, rng, 5) - 0.55) * 4, 0, 1) * wear
        alb = alb * (1 - 0.35 * wmask[..., None]) + 0.35 * wmask[..., None] * np.array([0.5, 0.48, 0.44])
    if streak:
        s = fbm(n, 2, rng, 4, aniso=(0.25, 6))
        alb *= (1 - streak * np.clip((s - 0.45) * 3, 0, 1))[..., None]
    if stain:
        s = np.clip((fbm(n, 4, rng, 4) - 0.6) * 5, 0, 1) * stain
        alb *= (1 - 0.55 * s)[..., None] * np.array([1, 0.92, 0.8])[None, None, :] + (1 - 0.0) * 0
    height = 0.5 + 0.4 * (thread - 0.5) + 0.1 * (fiber - 0.5)
    rough = 0.82 + 0.12 * fiber
    return np.clip(alb, 0, 1), rough, np.zeros((n, n)), height


def r_hair(n, rng, color, sheen=0.2):
    y, x = _grid(n)
    strand = fbm(n, 6, rng, 3, aniso=(0.05, 40))
    clump = fbm(n, 5, rng, 3, aniso=(0.1, 10))
    base = _col(color)
    alb = base[None, None, :] * (0.55 + 0.7 * strand * clump)[..., None]
    rough = 0.45 + 0.3 * (1 - strand)
    height = 0.5 + 0.5 * (strand - 0.5)
    return np.clip(alb, 0, 1), rough, np.zeros((n, n)), height


def r_leather(n, rng, color, crease=0.5, scuff=0.4):
    base = _col(color)
    grain = fbm(n, 70, rng, 2)
    cr = fbm(n, 5, rng, 3, aniso=(2.5, 0.6))
    creases = np.clip(1 - np.abs(cr - 0.5) * 10, 0, 1) * crease
    sc = np.clip((fbm(n, 8, rng, 4) - 0.55) * 4, 0, 1) * scuff
    alb = base[None, None, :] * (0.78 + 0.28 * grain - 0.3 * creases)[..., None]
    alb = alb * (1 - sc[..., None]) + sc[..., None] * (base * 1.9 + 0.08)[None, None, :]
    rough = 0.5 + 0.2 * grain + 0.2 * sc - 0.1 * creases
    return np.clip(alb, 0, 1), rough, np.zeros((n, n)), 0.5 + 0.3 * (grain - 0.5) - 0.35 * creases


def r_painted_metal(n, rng, color, rust=0.4, corrugation=0, edge_wear=0.5, grime=0.5, streak_dir=1.0, panel=1):
    """Weathered painted steel: orange-brown rust blooms eating through paint, vertical drip streaks, flaking."""
    y, x = _grid(n)
    base = _col(color)
    mott = fbm(n, 4, rng, 5)
    grain = fbm(n, 90, rng, 2)
    drip = fbm(n, 3, rng, 4, aniso=(0.12, 18))
    rustm = np.clip((fbm(n, 5, rng, 6) * 0.6 + drip * 0.4 - (1 - rust) * 0.7) * 3.2, 0, 1)
    seam = np.zeros((n, n))
    if panel:
        for k in range(panel):
            d = np.abs(((x * panel) % 1.0) - 0.0)
            seam = np.maximum(seam, np.clip(1 - np.minimum(d, 1 - d) * n / panel / 2.5, 0, 1))
    paint = base[None, None, :] * (0.78 + 0.34 * mott + 0.05 * grain)[..., None]
    rcol = np.array([0.30, 0.13, 0.055]) * (0.7 + 0.6 * fbm(n, 16, rng, 3))[..., None]
    alb = paint * (1 - rustm[..., None]) + rcol * rustm[..., None]
    alb *= (1 - grime * 0.45 * np.clip((drip - 0.42) * 4, 0, 1))[..., None]
    alb *= (1 - 0.55 * seam)[..., None]
    alb = np.clip(alb, 0, 1)
    height = 0.55 + 0.18 * (grain - 0.5) - 0.3 * rustm * (fbm(n, 30, rng, 2)) - 0.35 * seam
    if corrugation:
        height += 0.25 * np.sin(2 * np.pi * x * corrugation)
    rough = np.clip(0.42 + 0.35 * rustm + 0.12 * mott + 0.08 * grain, 0, 1)
    metal = np.clip(0.25 + 0.6 * rustm * 0.0 + 0.0 * mott, 0, 1) * (1 - rustm * 0.9)
    return alb, rough, metal, height


def r_steel(n, rng, color=(0.46, 0.47, 0.5), brushed=True, patina=0.35, wear=0.5):
    y, x = _grid(n)
    base = _col(color)
    br = fbm(n, 2, rng, 4, aniso=(80, 1.2)) if brushed else fbm(n, 40, rng, 2)
    mott = fbm(n, 4, rng, 5)
    pat = np.clip((fbm(n, 5, rng, 5) - (1 - patina)) * 3.5, 0, 1)
    scr = np.clip((fbm(n, 2, rng, 3, aniso=(60, 0.7)) - 0.72) * 6, 0, 1)
    alb = base[None, None, :] * (0.78 + 0.35 * br + 0.18 * (mott - 0.5))[..., None]
    alb = alb * (1 - 0.55 * pat[..., None]) + 0.55 * pat[..., None] * np.array([0.28, 0.22, 0.14])[None, None, :]
    alb += scr[..., None] * 0.1
    rough = np.clip(0.3 + 0.28 * (1 - br) + 0.4 * pat + 0.15 * mott, 0, 1)
    metal = np.clip(0.95 - 0.7 * pat, 0, 1)
    return np.clip(alb, 0, 1), rough, metal, 0.5 + 0.12 * (br - 0.5) - 0.2 * scr


def r_concrete(n, rng, color=(0.30, 0.30, 0.285), cracks=0.5, stain=0.6, joints=2):
    y, x = _grid(n)
    base = _col(color)
    agg = fbm(n, 60, rng, 3)
    mott = fbm(n, 3, rng, 6)
    ct = fbm(n, 6, rng, 3)
    crack = np.clip(1 - np.abs(ct - 0.5) * 24, 0, 1) * cracks * (fbm(n, 2, rng, 3) > 0.4)
    wet = np.clip((fbm(n, 3, rng, 5) - (1 - stain)) * 3, 0, 1)
    jx = np.abs(((x * joints) % 1.0) - 0.5)
    jy = np.abs(((y * joints) % 1.0) - 0.5)
    joint = np.clip(1 - np.minimum(0.5 - jx, 0.5 - jy) * n / joints / 3, 0, 1)
    alb = base[None, None, :] * (0.7 + 0.35 * mott + 0.14 * agg)[..., None]
    alb *= (1 - 0.5 * wet)[..., None] * np.array([1.0, 0.97, 0.9])[None, None, :]
    alb *= (1 - 0.7 * crack - 0.65 * joint)[..., None]
    rough = np.clip(0.8 + 0.12 * agg - 0.25 * wet, 0, 1)
    return np.clip(alb, 0, 1), rough, np.zeros((n, n)), 0.5 + 0.35 * (agg - 0.5) - 0.5 * crack - 0.4 * joint


def r_awning(n, rng, c1=(0.55, 0.07, 0.06), c2=(0.78, 0.7, 0.55), stripes=6, fade=0.5):
    y, x = _grid(n)
    s = (np.floor(x * stripes * 2) % 2).astype(float)
    base = _lerp3(_col(c1), _col(c2), s)
    weave = 0.5 + 0.5 * np.sin(2 * np.pi * x * 160) * np.sin(2 * np.pi * y * 160)
    mott = fbm(n, 4, rng, 5)
    sun = np.clip((fbm(n, 3, rng, 3) - 0.4) * 2.5, 0, 1) * fade
    alb = base * (0.8 + 0.25 * weave + 0.1 * mott)[..., None]
    alb = alb * (1 - sun[..., None]) + sun[..., None] * (alb * 0.4 + 0.45 * np.array([0.7, 0.62, 0.52]))
    drip = np.clip((fbm(n, 3, rng, 4, aniso=(0.1, 20)) - 0.5) * 4, 0, 1) * 0.45
    alb *= (1 - drip[..., None])
    return np.clip(alb, 0, 1), 0.8 + 0.12 * weave, np.zeros((n, n)), 0.5 + 0.3 * (weave - 0.5)


def r_rubber(n, rng, color=(0.035, 0.035, 0.04)):
    base = _col(color)
    g = fbm(n, 40, rng, 3)
    wear = np.clip((fbm(n, 4, rng, 4) - 0.55) * 3, 0, 1)
    alb = base[None, None, :] * (0.8 + 0.5 * g)[..., None] + wear[..., None] * 0.04
    return alb, 0.55 + 0.3 * wear + 0.1 * g, np.zeros((n, n)), 0.5 + 0.25 * (g - 0.5)


def r_ceramic(n, rng, color=(0.62, 0.6, 0.54), glaze=0.35):
    base = _col(color)
    crazing = fbm(n, 28, rng, 3)
    mott = fbm(n, 3, rng, 4)
    chip = np.clip((fbm(n, 10, rng, 4) - 0.78) * 8, 0, 1)
    alb = base[None, None, :] * (0.86 + 0.2 * mott)[..., None] * (1 - 0.1 * crazing[..., None])
    alb = alb * (1 - chip[..., None]) + chip[..., None] * np.array([0.35, 0.27, 0.2])
    rough = np.clip(glaze + 0.12 * crazing + 0.35 * chip, 0, 1)
    return np.clip(alb, 0, 1), rough, np.zeros((n, n)), 0.5 + 0.1 * (crazing - 0.5) - 0.3 * chip


def r_food(n, rng):
    """Painted food swatches in four horizontal bands: broth, noodle, egg/pork, greens/nori (u across)."""
    y, x = _grid(n)
    band = np.minimum((y * 4).astype(int), 3)
    mott = fbm(n, 6, rng, 5)
    fine = fbm(n, 60, rng, 3)
    strand = fbm(n, 4, rng, 3, aniso=(0.3, 80))
    alb = np.zeros((n, n, 3))
    cols = [(_col((0.36, 0.14, 0.04)), 0.4), (_col((0.78, 0.6, 0.28)), 0.3), (_col((0.82, 0.62, 0.34)), 0.3), (_col((0.06, 0.16, 0.05)), 0.2)]
    for i, (c, v) in enumerate(cols):
        m = band == i
        alb[m] = (c[None, :] * (0.8 + v * mott[m][:, None] + 0.15 * fine[m][:, None]))
    egg = np.exp(-(((x - 0.5) * 4) ** 2 + ((y - 0.5 - 0.0) * 14) ** 2)) * (band == 2)
    alb = alb * (1 - egg[..., None]) + egg[..., None] * np.array([0.9, 0.78, 0.42])
    nood = band == 1
    alb[nood] *= (0.85 + 0.3 * strand[nood])[:, None]
    rough = np.where(band == 0, 0.12 + 0.1 * fine, np.where(band == 1, 0.35, np.where(band == 2, 0.28, 0.5)))
    return np.clip(alb, 0, 1), rough, np.zeros((n, n)), 0.5 + 0.2 * (fine - 0.5)


def r_board(n, rng, color=(0.05, 0.055, 0.06)):
    base = _col(color)
    mott = fbm(n, 5, rng, 5)
    scuff = np.clip((fbm(n, 7, rng, 4) - 0.6) * 4, 0, 1)
    alb = base[None, None, :] * (0.8 + 0.5 * mott)[..., None] + scuff[..., None] * 0.07
    return np.clip(alb, 0, 1), 0.6 + 0.25 * scuff, np.zeros((n, n)), 0.5 + 0.1 * (mott - 0.5)


# ------------------------------------------------------------------------------------------- face atlas
def paint_skin_atlas(alb, rough, height, tone, rng, stubble=0.0, lip=(0.55, 0.27, 0.25), iris=(0.18, 0.1, 0.05), brow=(0.07, 0.045, 0.03),
                     freckle=0.0):
    n = alb.shape[0]
    base = _col(tone)
    tile = ATLAS["tile"]
    # the top half is skin; fill the whole atlas with tiling skin first (already), then paint regions
    def px(r):
        return (int(r[0] * n), int(r[1] * n), int(r[2] * n), int(r[3] * n))
    # tile region: re-tile whole top-left from a down-sampled copy so it is itself tileable
    x0, y0, x1, y1 = px(ATLAS["tile"])
    h = y1 - y0
    # image rows are top-first: v in [0.5,1] occupies rows [0, n/2)
    def rows(r):
        return (n - int(r[3] * n), n - int(r[1] * n), int(r[0] * n), int(r[2] * n))
    ra, rb, ca, cb = rows(ATLAS["tile"])
    t_alb, t_rough, _, t_h = r_skin(cb - ca, rng, tone)
    alb[:] = base[None, None, :] * 0.92
    alb[ra:rb, ca:cb] = t_alb
    rough[ra:rb, ca:cb] = t_rough
    height[ra:rb, ca:cb] = t_h
    # face region
    fr0, fr1, fc0, fc1 = rows(ATLAS["face"])
    fh, fw = fr1 - fr0, fc1 - fc0
    yy, xx = np.mgrid[0:fh, 0:fw]
    X = ((xx + 0.5) / fw - 0.5) * 2 * FACE_HALF_W                     # head x (m), image-left = head-left in the frame (image u increases with x)
    Z = FACE_Z1 - (yy + 0.5) / fh * (FACE_Z1 - FACE_Z0)               # head z (m); row 0 is the top
    face = alb[fr0:fr1, fc0:fc1]
    face[:] = base[None, None, :] * (0.94 + 0.1 * fbm(fw, 4, rng, 3)[:fh, :fw])[..., None] if fbm(fw, 4, rng, 3).shape[0] >= fh else face
    # soft t-zone/cheek warmth, eye-socket shading, under-nose and jaw shadow
    def gauss(cx, cz, sx, sz):
        return np.exp(-(((X - cx) / sx) ** 2 + ((Z - cz) / sz) ** 2))
    warm = gauss(0.052, -0.045, 0.028, 0.03) + gauss(-0.052, -0.045, 0.028, 0.03)
    face *= 1.0
    face[..., 0] += 0.045 * warm
    face[..., 1] -= 0.02 * warm
    sock = gauss(0.032, -0.002, 0.026, 0.017) + gauss(-0.032, -0.002, 0.026, 0.017)
    face *= (1 - 0.25 * sock)[..., None] * np.array([1.0, 0.97, 1.02])[None, None, :] + 0 * sock[..., None]
    jaw = np.clip((-Z - 0.10) * 30, 0, 1)
    face *= (1 - 0.18 * jaw)[..., None]
    # brows: arched dark bands
    for sgn in (-1, 1):
        cx = sgn * 0.034
        arch = 0.031 + 0.006 * (1 - ((X - cx) / 0.025) ** 2)
        b = np.exp(-(((Z - arch) / 0.0042) ** 2)) * (np.abs(X - cx) < 0.027) * np.clip(1 - (np.abs(X - cx) / 0.027) ** 4, 0, 1)
        face[:] = face * (1 - 0.75 * b[..., None]) + 0.75 * b[..., None] * _col(brow)[None, None, :]
    # lips
    mouth = np.exp(-((X / 0.027) ** 4 + ((Z + 0.081) / 0.0105) ** 2))
    face[:] = face * (1 - 0.8 * mouth[..., None]) + 0.8 * mouth[..., None] * _col(lip)[None, None, :]
    line = np.exp(-(((Z + 0.0815) / 0.0012) ** 2)) * (np.abs(X) < 0.026)
    face *= (1 - 0.55 * line)[..., None]
    # nostrils
    for sgn in (-1, 1):
        nst = np.exp(-((((X - sgn * 0.0105) / 0.0045) ** 2) + ((Z + 0.049) / 0.0032) ** 2))
        face *= (1 - 0.8 * nst)[..., None]
    # stubble / freckles
    if stubble:
        sm = np.clip(((-Z - 0.045) * 14), 0, 1) * np.clip(1 - np.abs(X) / 0.075, 0, 1) * (np.abs(Z + 0.081) > 0.012)
        sm *= (fbm(fw, 90, rng, 2)[:fh, :fw] if fbm(fw, 90, rng, 2).shape[0] >= fh else 0.5)
        face *= (1 - stubble * 0.5 * sm)[..., None]
    if freckle:
        fk = (fbm(fw, 50, rng, 2)[:fh, :fw] > 0.8) * gauss(0, -0.03, 0.07, 0.04)
        face *= (1 - freckle * 0.25 * fk)[..., None]
    # border blend into base skin so the planar edge matches tiling skin
    edge = np.clip(np.minimum(np.minimum(xx, fw - 1 - xx), np.minimum(yy, fh - 1 - yy)) / 8.0, 0, 1)[..., None]
    face[:] = face * edge + base[None, None, :] * (1 - edge)
    # eye swatch: sclera + iris centred in its rect, 0..1 across
    er0, er1, ec0, ec1 = rows(ATLAS["eye"])
    eh, ew = er1 - er0, ec1 - ec0
    ey, ex = np.mgrid[0:eh, 0:ew]
    ex = (ex + 0.5) / ew - 0.5
    ey = (ey + 0.5) / eh - 0.5
    rr = np.sqrt(ex ** 2 + ey ** 2)
    eye = np.zeros((eh, ew, 3))
    scl = np.array([0.82, 0.8, 0.77]) * (0.9 + 0.1 * np.cos(rr * 8))[..., None] * (1 - 0.35 * np.clip((rr - 0.3) * 4, 0, 1))[..., None]
    eye[:] = scl
    ir = (rr < 0.27)
    ang = np.arctan2(ey, ex)
    irc = _col(iris)[None, None, :] * (0.8 + 0.5 * np.sin(ang * 14)[..., None] * 0.4)
    eye[ir] = irc[ir] * (1.4 - 4.0 * np.clip(rr[ir] - 0.1, 0, 1))[..., None]
    eye[rr < 0.11] = 0.012
    eye[(rr > 0.245) & (rr < 0.27)] *= 0.35
    alb[er0:er1, ec0:ec1] = eye
    rough[er0:er1, ec0:ec1] = 0.12
    # lip, nail, brow, dark swatches
    for key, col, rv in (("lip", lip, 0.38), ("nail", (0.72, 0.5, 0.46), 0.3), ("brow", brow, 0.7), ("dark", (0.022, 0.015, 0.014), 0.8)):
        r0, r1, c0, c1 = rows(ATLAS[key])
        alb[r0:r1, c0:c1] = _col(col)[None, None, :] * (0.95 + 0.05 * fbm(max(c1 - c0, r1 - r0), 6, rng, 2)[:r1 - r0, :c1 - c0, None] if False else 1.0)
        rough[r0:r1, c0:c1] = rv
        height[r0:r1, c0:c1] = 0.5
    # brow swatch: hair-like fine streaks via modulation
    alb[:] = np.clip(alb, 0, 1)
    return alb, rough, height


# ------------------------------------------------------------------------------------------------ output
def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * h.shape[1]
    dy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) * 0.5 * h.shape[0]          # image rows go down; +Y up
    nz = np.ones_like(h)
    nrm = np.stack([-dx * strength / h.shape[1] * 4, -dy * strength / h.shape[0] * 4, nz], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    return nrm * 0.5 + 0.5


def resize(img, n):
    if img.shape[0] == n:
        return img
    f = img.shape[0] // n
    if img.ndim == 3:
        return img.reshape(n, f, n, f, img.shape[2]).mean((1, 3))
    return img.reshape(n, f, n, f).mean((1, 3))


def png_bytes(arr):
    a = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    if a.ndim == 2:
        a = a[..., None]
    h, w, c = a.shape
    ctype = {1: 0, 3: 2, 4: 6}[c]
    raw = b"".join(b"\x00" + a[i].tobytes() for i in range(h))

    def chunk(t, d):
        c_ = struct.pack(">I", len(d)) + t + d
        return c_ + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")


def write_set(outdir, name, alb, rough, metal, height, nstr=3.0, alb_n=512, orm_n=256, nrm_n=512, occ=None):
    os.makedirs(outdir, exist_ok=True)
    n0 = alb.shape[0]
    big = max(n0, 1)
    a = resize(alb, alb_n) if n0 >= alb_n else alb
    hh = resize(height, nrm_n) if n0 >= nrm_n else height
    nm = normal_from_height(hh, nstr)
    r = resize(rough, orm_n)
    m = resize(metal, orm_n)
    o = resize(occ if occ is not None else (0.8 + 0.2 * (resize(height, orm_n))), orm_n)
    orm = np.stack([np.clip(o, 0, 1), np.clip(r, 0, 1), np.clip(m, 0, 1)], -1)
    paths = {}
    for k, arr in (("albedo", a), ("orm", orm), ("normal", nm)):
        p = os.path.join(outdir, f"{name}_{k}.png")
        with open(p, "wb") as f:
            f.write(png_bytes(arr))
        paths[k] = p
    return paths, {"albedo": a.shape[0], "orm": orm.shape[0], "normal": nm.shape[0]}


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "tex_test"
    rng = np.random.default_rng(1)
    print(json.dumps(write_set(out, "test_steel", *r_steel(512, rng))[1]))
