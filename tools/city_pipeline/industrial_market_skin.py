"""Skin / eye texture bake for the Human Base Meshes figures.

The skin atlas is painted by evaluating 3D functions of the rest-pose surface position at every UV texel (UV triangles are
rasterised to position/normal maps), so brows, lips, stubble, nails and pores follow the real mesh and never rely on a projected face.
Atlas (u, v from bottom-left): EYE tile (0,.75)-(.25,1) azimuthal-equidistant eyeball (front 75 deg); body islands elsewhere.
"""
import math

import numpy as np

import industrial_market_textures as TX

EYE_RECT = (0.0, 0.75, 0.25, 1.0)
EYE_THETA = math.radians(75.0)
IRIS_THETA = math.radians(35.0)


def eye_uv(d):
    """Unit direction(s) from the eye centre (front = +Y) -> atlas uv."""
    d = np.atleast_2d(d)
    th = np.arccos(np.clip(d[:, 1], -1, 1))
    ph = np.arctan2(d[:, 2], d[:, 0])
    rho = np.clip(th / EYE_THETA, 0, 1) * 0.5
    u0, v0, u1, v1 = EYE_RECT
    return np.stack([u0 + (u1 - u0) * (0.5 + rho * np.cos(ph)), v0 + (v1 - v0) * (0.5 + rho * np.sin(ph))], 1)


class Noise3:
    """Smooth 3D noise: sum of random plane waves (continuous across UV seams, no tiling needed)."""

    def __init__(self, seed, n=24):
        r = np.random.default_rng(seed)
        self.k = r.normal(size=(n, 3))
        self.k /= np.linalg.norm(self.k, axis=1, keepdims=True)
        self.ph = r.uniform(0, 2 * np.pi, n)
        self.a = r.uniform(0.6, 1.0, n)

    def __call__(self, p, freq):
        v = np.zeros(p.shape[:-1])
        for k, ph, a in zip(self.k, self.ph, self.a):
            v += a * np.sin(2 * np.pi * freq * (p @ k) + ph)
        return v / (self.a.sum() * 0.45)


def raster(faces, loop_uv, P, N, res):
    """Rasterise UV triangles -> position/normal maps and a coverage mask (v up; array row 0 = v 1)."""
    pos = np.zeros((res, res, 3), np.float32)
    nrm = np.zeros((res, res, 3), np.float32)
    mask = np.zeros((res, res), bool)
    for f, uvs in zip(faces, loop_uv):
        for i in range(1, len(f) - 1):
            idx = (0, i, i + 1)
            uv = np.array([uvs[j] for j in idx]) * res
            xy = np.stack([uv[:, 0], res - uv[:, 1]], 1)
            x0, y0 = np.floor(xy.min(0) - 1).astype(int).clip(0, res - 1)
            x1, y1 = np.ceil(xy.max(0) + 1).astype(int).clip(0, res - 1)
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            d1, d2 = xy[1] - xy[0], xy[2] - xy[0]
            det = d1[0] * d2[1] - d1[1] * d2[0]
            if abs(det) < 1e-9:
                continue
            rx, ry = gx - xy[0, 0], gy - xy[0, 1]
            u = (rx * d2[1] - ry * d2[0]) / det
            v = (d1[0] * ry - d1[1] * rx) / det
            m = (u >= -0.02) & (v >= -0.02) & (u + v <= 1.02)
            w0, w1, w2 = (1 - u - v)[m], u[m], v[m]
            p = [P[f[j]] for j in idx]
            n = [N[f[j]] for j in idx]
            ys, xs = gy[m].astype(int), gx[m].astype(int)
            pos[ys, xs] = w0[:, None] * p[0] + w1[:, None] * p[1] + w2[:, None] * p[2]
            nrm[ys, xs] = w0[:, None] * n[0] + w1[:, None] * n[1] + w2[:, None] * n[2]
            mask[ys, xs] = True
    return pos, nrm, mask


def dilate(img, mask, iters=6):
    img = img.copy()
    mask = mask.copy()
    for _ in range(iters):
        acc = np.zeros_like(img)
        cnt = np.zeros(mask.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            m2 = np.roll(mask, (dy, dx), (0, 1))
            i2 = np.roll(img, (dy, dx), (0, 1))
            acc += i2 * (m2 & ~mask)[..., None] if img.ndim == 3 else i2 * (m2 & ~mask)
            cnt += (m2 & ~mask)
        new = (cnt > 0)
        if img.ndim == 3:
            img[new] = acc[new] / cnt[new][:, None]
        else:
            img[new] = acc[new] / cnt[new]
        mask |= new
    return img


def gauss(x, s):
    return np.exp(-(x / s) ** 2)


def paint_eye(res_tile, iris, rng):
    n = res_tile
    yy, xx = np.mgrid[0:n, 0:n]
    x = ((xx + 0.5) / n - 0.5) * 2
    y = (0.5 - (yy + 0.5) / n) * 2
    rho = np.sqrt(x * x + y * y)
    ph = np.arctan2(y, x)
    th = np.clip(rho, 0, 1) * EYE_THETA
    ri = IRIS_THETA / EYE_THETA
    sclera = np.array([0.80, 0.76, 0.71])
    img = np.ones((n, n, 3)) * sclera
    img *= (1.0 - 0.22 * np.clip((th - 0.9) / 0.4, 0, 1))[..., None]               # shaded towards the lids
    veins = np.clip(np.sin(ph * 17 + 4 * rho) * np.sin(ph * 5 - 7 * rho), 0, 1) * np.clip((rho - ri) * 3, 0, 1) * 0.10
    img[..., 1] -= veins * 0.6
    img[..., 2] -= veins * 0.6
    ir = rho < ri
    ir_n = rho / ri
    streak = 0.75 + 0.35 * np.sin(ph * 23) * np.sin(ph * 7 + 5 * ir_n) + 0.1 * rng.random((n, n))
    col = np.array(iris)[None, None, :] * streak[..., None] * (1.25 - 0.55 * ir_n)[..., None]
    ring = np.clip((ir_n - 0.72) / 0.28, 0, 1)
    col = col * (1 - 0.65 * ring[..., None])
    col = col + np.array([0.12, 0.09, 0.05]) * gauss(ir_n - 0.5, 0.15)[..., None] * 0.6
    img[ir] = col[ir]
    pupil = ir_n < 0.36
    img[pupil] = 0.008
    edge = np.clip((rho - ri) / 0.02, 0, 1) < 1
    img[(rho > ri) & (rho < ri + 0.018)] *= 0.55                                   # limbal edge
    rough = np.full((n, n), 0.10)
    return np.clip(img, 0, 1), rough


def bake(res, pos, nrm, mask, lm, rng, tone, stubble=0.0, freckle=0.0, brow=(0.07, 0.05, 0.04), lip=(0.5, 0.25, 0.22), iris=(0.2, 0.11, 0.05), seed=1,
         nail_joints=None, dorsal=None, normal_strength=1.0):
    """lm: eye_mid (3,), s (scale), hands: list of fingertip (tip, axis, dorsal_normal) tuples. Returns albedo, rough, height, normal (RGB)."""
    nz = Noise3(seed)
    s = lm["s"]
    p = pos.astype(np.float64)
    ex, ey, ez = lm["eye_mid"]
    X = p[..., 0] / s
    Z = (p[..., 2] - ez) / s
    Y = (p[..., 1] - ey) / s
    AX = np.abs(X)
    base = np.array(tone)
    blot = nz(p, 6.0) * 0.5 + 0.5
    mott = nz(p, 22.0) * 0.5 + 0.5
    alb = base[None, None, :] * (0.93 + 0.12 * blot)[..., None]
    alb += np.array([0.035, -0.006, -0.012]) * (nz(p, 3.0) * 0.5 + 0.5)[..., None]
    alb *= (0.97 + 0.05 * mott)[..., None]
    front = np.clip((nrm[..., 1] / (np.linalg.norm(nrm, axis=-1) + 1e-9) - 0.1) * 3, 0, 1)
    ramp = lambda v: np.clip(v, 0, 1)
    face = front * ramp((0.11 - AX) / 0.03) * ramp((Z + 0.15) / 0.03) * ramp((0.13 - Z) / 0.03) * ramp((Y + 0.05) / 0.03)
    # cheek/nose/ear warmth
    warm = gauss(AX - 0.052, 0.03) * gauss(Z + 0.045, 0.03) + 0.7 * gauss(X, 0.016) * gauss(Z + 0.043, 0.022)
    alb[..., 0] += 0.05 * warm * face
    alb[..., 1] -= 0.018 * warm * face
    ear = ramp((AX - 0.066) / 0.015) * ramp(-(Y + 0.0) / 0.02) * ramp((Z + 0.075) / 0.02) * ramp((0.045 - Z) / 0.02)
    alb[..., 0] += 0.035 * ear
    # eye sockets / lid creases
    sock = gauss(AX - 0.033, 0.026) * gauss(Z - 0.001, 0.019)
    alb *= (1 - 0.16 * sock * face)[..., None] * np.array([1.0, 0.97, 1.0])
    crease = gauss(AX - 0.033, 0.022) * gauss(Z - 0.016, 0.0035)
    alb *= (1 - 0.18 * crease * face)[..., None]
    # lash lines: dark band hugging the lid margin
    for sg in (-1, 1):
        ex_ = sg * 0.0335
        r = np.sqrt(((X - ex_) / 0.0165) ** 2 + (((Z) - 0.001) / 0.0085) ** 2)
        lash = np.clip(1 - np.abs(r - 1.0) / 0.22, 0, 1) * face * (Z > -0.004)
        alb *= (1 - 0.55 * lash)[..., None]
    # brows: arched hair band
    for sg in (-1, 1):
        cx = sg * 0.0355
        t = np.clip((X - cx) / 0.027 * sg, -1.2, 1.2)           # +: outwards
        arch = 0.0285 + 0.007 * (1 - np.clip((t + 0.2) ** 2, 0, 1)) - 0.005 * np.clip(t - 0.4, 0, 1) ** 2
        thick = 0.0050 * (1.05 - 0.45 * np.clip(t, 0, 1)) + 0.0012
        b = gauss(Z - arch, thick) * (np.abs(X - cx) < 0.030) * np.clip(1 - (np.abs(X - cx) / 0.030) ** 4, 0, 1) * face
        b *= 0.75 + 0.25 * (nz(p, 260.0) * 0.5 + 0.5)
        alb = alb * (1 - 0.80 * b[..., None]) + 0.80 * b[..., None] * np.array(brow)[None, None, :]
    # lips and mouth line
    mouth_z = -0.0775
    lipm = gauss(X / 0.0275, 1.0) ** 2 * gauss((Z - mouth_z + 0.0 * X) / 0.0105, 1.0) * face
    lipm = np.clip(lipm * 1.15, 0, 1)
    lipc = np.array(lip)[None, None, :] * (0.92 + 0.12 * (nz(p, 140.0) * 0.5 + 0.5))[..., None]
    alb = alb * (1 - 0.7 * lipm[..., None]) + 0.7 * lipm[..., None] * lipc * 0.9
    line = gauss(Z - mouth_z, 0.0014) * (AX < 0.027) * face
    alb *= (1 - 0.5 * line)[..., None]
    # nostrils
    for sg in (-1, 1):
        nst = gauss((X - sg * 0.0105) / 0.0036, 1.0) * gauss((Z + 0.0465) / 0.0024, 1.0) * face
        alb *= (1 - 0.5 * nst)[..., None]
    # stubble / freckles
    if stubble:
        sm = np.clip((-Z - 0.045) * 14, 0, 1) * np.clip(1 - AX / 0.082, 0, 1) * ramp((np.abs(Z - mouth_z) - 0.009) / 0.009) * face
        sm += 0.7 * gauss(X, 0.035) * gauss(Z + 0.058, 0.012) * face * 0                                              # (philtrum left clean)
        grain = np.clip((nz(p, 420.0) + 0.1) * 1.4, 0, 1)
        alb *= (1 - stubble * 0.55 * np.clip(sm, 0, 1) * (0.5 + 0.5 * grain))[..., None]
    if freckle:
        fk = np.clip((nz(p, 170.0) - 0.55) * 4, 0, 1) * gauss(X, 0.06) * gauss(Z + 0.035, 0.035) * face
        alb *= (1 - freckle * 0.22 * fk)[..., None] * np.array([1, 0.96, 0.9])
    # knuckle / hand warmth + nails
    hand = lm.get("hand_mask_fn")
    rough = 0.56 + 0.10 * (nz(p, 18.0) * 0.5 + 0.5)
    rough -= 0.10 * (gauss(X, 0.02) * gauss(Z - 0.03, 0.05) + gauss(X, 0.012) * gauss(Z + 0.04, 0.02)) * face        # forehead / nose shine
    rough = np.where(lipm > 0.3, 0.38, rough)
    if nail_joints:
        for tip, ax, dors in nail_joints:
            d = p - tip
            t = d @ ax
            rad = np.linalg.norm(d - np.outer(t.ravel(), ax).reshape(d.shape), axis=-1)
            dd = d @ dors
            m = (t > -0.0155 * s) & (t < 0.0004) & (rad < 0.0074 * s) & (dd > 0.002 * s)
            tipw = np.clip((t + 0.0035 * s) / (0.0035 * s), 0, 1)
            nail = alb * 0.55 + np.array([0.60, 0.40, 0.37]) * 0.45
            nail = nail * (1 - 0.15 * tipw[..., None]) + np.array([0.80, 0.72, 0.66]) * 0.15 * tipw[..., None]
            alb = np.where(m[..., None], nail, alb)
            rough = np.where(m, 0.32, rough)
    # finger/knuckle redness: positions near the hands handled by caller through 'hand_tint' if given
    ht = lm.get("hand_tint")
    if ht is not None:
        alb *= (1 + ht(p))[..., None]
    h = 0.5 + 0.5 * (nz(p, 520.0) * 0.5 + 0.25 * nz(p, 1000.0)) + 0.22 * nz(p, 190.0) * (0.4 + 0.6 * face)
    h += 0.5 * (1 - face * 0) * 0
    alb = np.clip(alb, 0, 1)
    return alb, np.clip(rough, 0.2, 0.9), np.clip(h, 0, 1)


def normal_map(h, mask, amp=0.05):
    """Tangent-space normal (OpenGL) from a height texture, scaled so the typical slope is `amp` (subtle skin)."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, 1, 0) - np.roll(h, -1, 0)) * 0.5
    sd = np.std(np.hypot(gx, gy)[mask]) + 1e-9
    k = amp / sd
    n = np.stack([-gx * k, -gy * k, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5
