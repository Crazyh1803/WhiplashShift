"""Garment layers worn over the figure body: ray-draped apron / pockets / flaps, collars, hood, headband, ties.
Everything samples the already-built body mesh, so cloth rests on the real shoulders, belly and thighs."""
import math

from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import industrial_market_people as PP

V = Vector


class Skin:
    """Ray-cast front-surface sampler on the current body mesh (person-local, facing +Y)."""

    def __init__(self, m):
        m.bm.normal_update()
        self.tree = BVHTree.FromBMesh(m.bm)

    def y(self, x, z):
        hit = self.tree.ray_cast(V((x, 1.2, z)), V((0, -1, 0)), 3.0)
        return None if hit[0] is None else hit[0].y

    def ymax(self, z, x0, x1, n=9):
        ys = [self.y(x0 + (x1 - x0) * i / (n - 1), z) for i in range(n)]
        ys = [v for v in ys if v is not None]
        return max(ys) if ys else None

    def hit(self, x, z):
        h = self.tree.ray_cast(V((x, 1.2, z)), V((0, -1, 0)), 3.0)
        return None if h[0] is None else (h[0], h[1])


def apron(m, sk, H, mat, lx, strap_mat, ties=True, chest_z=0.742, hem_z=0.285, width_top=0.145, width_bot=0.23, sag=0.012):
    zt, zb = chest_z * H, hem_z * H
    hipz = 0.505 * H

    def wid(z):
        t = (z - zt) / (zb - zt)
        return width_top + (width_bot - width_top) * min(1.0, t * 1.6)

    def pt(i, j, nu=14, nv=24):
        u = i / nu * 2 - 1
        z = zt + (zb - zt) * j / nv
        x = u * wid(z) * H / 1.75
        yh = sk.y(x, z)
        ym = sk.ymax(z, -wid(z), wid(z))
        if ym is None:
            ym = 0.12
        if yh is None:
            yh = ym
        w = min(1.0, max(0.0, (hipz - z) / (hipz - 0.40 * H)))       # below the hips the apron hangs, no longer hugging the body
        y = yh * (1 - w) + (ym + 0.012 + 0.012 * (1 - u * u)) * w
        y += sag + 0.0045 * math.sin(u * 5 + j * 0.9) * (0.3 + w) + 0.012 * w * (j / nv)
        x += 0.01 * math.sin(j * 0.7 + u * 3) * w
        return V((x, y, z))
    PP.thick_sheet(m, lambda i, j: pt(i, j), 14, 24, 0.0045, mat, flip=False)
    # patch pocket (double layer, hem folded)
    def pk(i, j, nu=6, nv=5):
        u = (i / nu * 2 - 1) * 0.07
        z = 0.465 * H - 0.07 * j / nv
        p = pt(7 + int(round(u / wid(z) * 7)), int((0.742 * H - z) / (0.742 * H - 0.285 * H) * 24))
        return V((u, p.y + 0.0048, z))
    PP.thick_sheet(m, pk, 6, 5, 0.003, mat)
    # bib top / neck strap and waist ties
    top_l, top_r = pt(1, 0), pt(13, 0)
    for s, tp in ((-1, top_l), (1, top_r)):
        m.tube([tp, tp + V((0.0, -0.012, 0.045)), V((s * 0.075, 0.02, 0.843 * H)), V((s * 0.09, -0.04, 0.838 * H)), V((s * 0.03, -0.085, 0.80 * H))],
               [0.0085] * 5, strap_mat, seg=6, samples=14, ratio=0.36, up=V((0, 0, 1)), uv=("cloth", 3.0))
    if ties:
        wz = 0.585 * H
        pth = []
        for a in range(-20, 211, 12):
            ar = math.radians(a)
            pth.append(V((math.sin(ar) * 0.172 * H / 1.75 * 1.0 + lx * 0.2, 0.125 * math.cos(ar) + 0.006 - 0.0 * math.sin(ar), wz)))
        pth = [V((p.x, p.y, wz)) for p in pth]
        # tie round the waist: sampled on the front surface for the front half, then back
        front = []
        for k in range(9):
            x = -0.185 + 0.37 * k / 8
            yh = sk.y(x, wz)
            front.append(V((x, (yh if yh is not None else 0.1) + 0.012, wz)))
        back = [V((0.18, -0.03, wz)), V((0.11, -0.115, wz)), V((0.0, -0.135, wz)), V((-0.11, -0.115, wz)), V((-0.18, -0.03, wz))]
        m.tube(front + back, [0.0085] * (len(front) + len(back)), strap_mat, seg=6, samples=36, ratio=0.4, up=V((0, 0, 1)), uv=("cloth", 3.0))
        # bow tails behind
        for s in (-1, 1):
            m.tube([V((0.0, -0.135, wz)), V((s * 0.04, -0.15, wz - 0.07)), V((s * 0.055, -0.14, wz - 0.19))], [0.011, 0.012, 0.009], strap_mat, seg=6,
                   samples=9, ratio=0.3, up=V((1, 0, 0)), uv=("cloth", 3.0))


def collar(m, centre, rx, ry, z, h, thick, mat, a0=-150, a1=150, ratio=0.28, lean=0.0):
    pts = []
    for a in range(a0, a1 + 1, 15):
        ar = math.radians(a)
        pts.append(V((centre.x + rx * math.sin(ar), centre.y - ry * math.cos(ar) * -1 * -1 + 0.0, z)) if False else
                   V((centre.x + rx * math.sin(math.radians(a)), centre.y + ry * math.cos(math.radians(a)), z + lean * math.cos(math.radians(a)))))
    # a=0 is the front; sweep the back half only when a0..a1 spans 180
    return m.tube(pts, [h] * len(pts), mat, seg=8, samples=len(pts) * 3, ratio=thick / h, up=V((0, 0, 1)), uv=("cloth", 3.0), round_ends=(True, True))


def ring_loop(m, centre, rx, ry, z, r, mat, ratio=1.0, a0=0, a1=345, uvs=3.0, up=None, tilt=0.0):
    pts = [V((centre.x + rx * math.sin(math.radians(a)), centre.y + ry * math.cos(math.radians(a)), z + tilt * math.cos(math.radians(a))))
           for a in range(a0, a1 + 1, 15)]
    return m.tube(pts, [r] * len(pts), mat, seg=8, samples=len(pts) * 3, ratio=ratio, up=up, uv=("cloth", uvs))


def headband(m, head_c, tilt, mat):
    z = 0.073
    pts = []
    for a in range(200, 540, 14):
        ar = math.radians(a)
        pts.append(head_c + tilt @ V((0.0667 * math.sin(ar), 0.0845 * math.cos(ar) * (1.0 if math.cos(ar) > 0 else 0.97) - 0.002, z - 0.012 * (0.5 - 0.5 * math.cos(ar)))))
    m.tube(pts, [0.016] * len(pts), mat, seg=8, samples=len(pts) * 2, ratio=0.3, up=tilt @ V((0, 0, 1)), uv=("cloth", 3.0))
    knot = head_c + tilt @ V((0.012, -0.09, 0.05))
    m.sphere(knot, 0.021, mat, scale=(1.1, 0.8, 0.9), seg=10, rings=8, smooth=True)
    for s, dz in ((-1, 0.0), (1, 0.03)):
        m.tube([knot, knot + tilt @ V((s * 0.02, -0.03, -0.04)), knot + tilt @ V((s * 0.035, -0.045, -0.13 + dz)), knot + tilt @ V((s * 0.03, -0.035, -0.18 + dz))],
               [0.013, 0.014, 0.013, 0.012], mat, seg=6, samples=16, ratio=0.3, up=tilt @ V((1, 0, 0)), uv=("cloth", 3.0))
