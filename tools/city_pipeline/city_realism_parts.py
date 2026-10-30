"""Reusable construction details for the city realism families (Blender, Z-up, facade plane y=0, front = +Y, back = -Y; exports to glTF
Y-up with the front facing -Z). Everything is real geometry: supports with base plates and bolts, lintels, sills, reveals, hoods, guides,
service runs, repairs in a different material. Builders take a Ctx (mesh + seeded rng + measured anchors/entrances/wear spots)."""
import math
import random

import bmesh
from mathutils import Matrix, Vector

import city_realism_textures as T
import industrial_market_common as C

V = Vector
MATS = list(T.LIBRARY)


class Ctx:
    def __init__(self, name, seed, width, depth):
        self.name = name
        self.W, self.D = width, depth
        self.m = C.Mesh(MATS)
        self.rng = random.Random(seed)
        self.anchors = []        # light anchors (Blender coordinates)
        self.entrances = []
        self.drips = []          # (x, y, z_top, width, strength) rain streaks below joints / sills / outlets
        self.polish = []         # (x, y, z, radius): hand-worn spots that stay clean
        self.dirty = []          # (x, y, z, radius, strength): oil / exhaust / foot-traffic
        self.signs = []
        self.tints = []          # (x, y, z, radius, (r, g, b)): colour carried in COLOR_0 for living things (foliage) the library has no material for

    def r(self, a=0.0, b=1.0):
        return self.rng.uniform(a, b)

    def anchor(self, kind, p, d=(0, 1, 0), color=(1.0, 0.8, 0.5), rng_m=7.0, energy=1.0, shadow=False):
        self.anchors.append({"kind": kind, "p": tuple(p), "d": tuple(d), "color": color, "range_m": rng_m, "energy": energy, "shadow": shadow})

    def entrance(self, kind, x, y, w, h, z=0.0):
        self.entrances.append({"kind": kind, "p": (x, y, z), "width": w, "height": h})


def bx(c, x0, x1, y0, y1, z0, z1, mat, **kw):
    return c.m.box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)), mat, **kw)


def strut(c, p0, p1, w, mat, seg=4):
    return c.m.cyl(p0, p1, w, w, mat, seg=seg, caps=True, smooth=False)


def cylv(c, x, y, z0, z1, r, mat, seg=10):
    return c.m.cyl((x, y, z0), (x, y, z1), r, r, mat, seg=seg, smooth=False)


def cylx(c, x0, x1, y, z, r, mat, seg=10):
    return c.m.cyl((x0, y, z), (x1, y, z), r, r, mat, seg=seg, smooth=False)


def cyly(c, x, y0, y1, z, r, mat, seg=10):
    return c.m.cyl((x, y0, z), (x, y1, z), r, r, mat, seg=seg, smooth=False)


def set_uv_rect(c, faces, rect, normal=(0, 1, 0)):
    """Explicit atlas UV on the face whose normal matches (u0,v0,u1,v1 Blender v-up)."""
    for f in faces:
        n = f.normal
        if (n - V(normal)).length < 0.2:
            c.m.explicit.add(f)
            u0, v0, u1, v1 = rect
            pts = {}
            for lp in f.loops:
                p = lp.vert.co
                pts[lp] = p
            xs = sorted({round(p.x, 4) for p in pts.values()})
            zs = sorted({round(p.z, 4) for p in pts.values()})
            for lp, p in pts.items():
                sx = (p.x - xs[0]) / max(xs[-1] - xs[0], 1e-6) if len(xs) > 1 else 0.5
                sz = (p.z - zs[0]) / max(zs[-1] - zs[0], 1e-6) if len(zs) > 1 else 0.5
                if normal[1] > 0:                      # seen from +Y (front) the viewer's right is -X
                    sx = 1 - sx
                lp[c.m.uv].uv = (u0 + (u1 - u0) * sx, v0 + (v1 - v0) * sz)
            return f
    return None


# ------------------------------------------------------------------------------------------------ walls and openings
def wall(c, x0, x1, z0, z1, y, t, mat, openings=()):
    """Solid wall slab, front face at y, thickness t backwards, with rectangular openings (ox0, ox1, oz0, oz1) cut out as real reveals."""
    xs = sorted({x0, x1} | {max(x0, min(x1, v)) for o in openings for v in (o[0], o[1])})
    for a, b in zip(xs, xs[1:]):
        if b - a < 1e-3:
            continue
        ops = sorted((o for o in openings if o[0] <= a + 1e-6 and o[1] >= b - 1e-6), key=lambda o: o[2])
        cur = z0
        for o in ops:
            if o[2] > cur + 1e-3:
                bx(c, a, b, y - t, y, cur, o[2], mat)
            cur = max(cur, o[3])
        if z1 > cur + 1e-3:
            bx(c, a, b, y - t, y, cur, z1, mat)


def corrugated(c, x0, x1, z0, z1, y, mat="cladding_corrugated", pitch=0.2, depth=0.05, base_t=0.04):
    """Vertical trapezoid-rib sheet (real ribs) with a flat back; front crest at y."""
    n = max(1, int(round((x1 - x0) / pitch)))
    p = (x1 - x0) / n
    prof = []
    for i in range(n):
        a = x0 + i * p
        prof += [(a, y - depth), (a + p * 0.2, y), (a + p * 0.55, y), (a + p * 0.75, y - depth)]
    prof += [(x1, y - depth), (x1, y - depth - base_t), (x0, y - depth - base_t)]
    c.m.extrude_profile(prof, z0, z1, mat, plane="XY")


def lap_joint(c, x0, x1, z, y, mat="steel_structure"):
    bx(c, x0, x1, y - 0.01, y + 0.025, z - 0.04, z + 0.04, mat)


def rivets(c, x0, x1, z, y, step, mat="equipment_steel", r=0.016):
    x = x0
    while x <= x1 + 1e-6:
        cyly(c, x, y, y + 0.02, z, r, mat, seg=5)
        x += step


def patch(c, x0, x1, z0, z1, y, mat="cladding_patch", bolts=True):
    """Repair panel laid over the original wall with a bolted border (repair history)."""
    bx(c, x0, x1, y, y + 0.03, z0, z1, mat)
    if bolts:
        for xx in (x0 + 0.06, x1 - 0.06):
            for zz in (z0 + 0.06, z1 - 0.06, (z0 + z1) / 2):
                cyly(c, xx, y + 0.03, y + 0.05, zz, 0.014, "equipment_steel", seg=5)
    c.drips.append(((x0 + x1) / 2, y, z0, (x1 - x0) * 0.4, 0.3))


# ------------------------------------------------------------------------------------------------ supports
def column_h(c, x, y, z0, z1, size=0.3, plinth=0.25, mat="steel_structure", bolts=True, gussets=True):
    """H-column (web + flanges) on a grouted concrete plinth with base plate, anchor bolts with double nuts, gussets and a cap plate."""
    s = size
    f = 0.035
    bx(c, x - s * 0.9, x + s * 0.9, y - s * 0.9, y + s * 0.9, z0, z0 + plinth, "concrete")
    bx(c, x - s * 0.75, x + s * 0.75, y - s * 0.75, y + s * 0.75, z0 + plinth, z0 + plinth + 0.03, mat)          # base plate
    zb = z0 + plinth + 0.03
    bx(c, x - s / 2, x + s / 2, y - s / 2, y - s / 2 + f, zb, z1, mat)                                           # flanges
    bx(c, x - s / 2, x + s / 2, y + s / 2 - f, y + s / 2, zb, z1, mat)
    bx(c, x - 0.02, x + 0.02, y - s / 2, y + s / 2, zb, z1, mat)                                                  # web
    if bolts:
        for sx in (-1, 1):
            for sy in (-1, 1):
                bxp, byp = x + sx * s * 0.68, y + sy * s * 0.68
                cylv(c, bxp, byp, zb, zb + 0.09, 0.014, "equipment_steel", seg=6)
                cylv(c, bxp, byp, zb + 0.015, zb + 0.04, 0.026, "equipment_steel", seg=6)
                cylv(c, bxp, byp, zb + 0.04, zb + 0.062, 0.026, "equipment_steel", seg=6)
    if gussets:
        for sy in (-1, 1):
            bx(c, x - 0.015, x + 0.015, y + sy * s * 0.5, y + sy * s * 0.72, zb, zb + s * 0.55, mat)
    bx(c, x - s * 0.62, x + s * 0.62, y - s * 0.62, y + s * 0.62, z1, z1 + 0.025, mat)                           # cap plate
    c.dirty.append((x, y, z0, 0.9, 0.35))


def beam_i(c, x0, x1, y, z, h=0.3, mat="steel_structure", stiffeners=True, endplates=True):
    f = 0.035
    d = h * 0.7
    bx(c, x0, x1, y - d / 2, y + d / 2, z - h / 2, z - h / 2 + f, mat)
    bx(c, x0, x1, y - d / 2, y + d / 2, z + h / 2 - f, z + h / 2, mat)
    bx(c, x0, x1, y - 0.015, y + 0.015, z - h / 2, z + h / 2, mat)
    if endplates:
        for xe in (x0, x1):
            bx(c, xe - 0.012, xe + 0.012, y - d * 0.55, y + d * 0.55, z - h * 0.55, z + h * 0.55, mat)
    if stiffeners:
        n = max(1, int((x1 - x0) / 1.4))
        for i in range(1, n + 1):
            xs = x0 + (x1 - x0) * i / (n + 1)
            bx(c, xs - 0.01, xs + 0.01, y - d / 2 + 0.01, y + d / 2 - 0.01, z - h / 2 + f, z + h / 2 - f, mat)


def knee_brace(c, x, y, z, length, side=1, mat="steel_structure"):
    strut(c, (x, y, z - length), (x + side * length, y, z), 0.05, mat)


def bolt_row(c, x0, x1, z, y, step=0.22, r=0.014, face_y=1):
    x = x0
    while x <= x1 + 1e-6:
        cyly(c, x, y, y + 0.02 * face_y, z, r, "equipment_steel", seg=5)
        x += step


# ------------------------------------------------------------------------------------------------ openings, doors, windows
def window(c, x0, x1, z0, z1, y, kind=None, frame="steel_structure", t=0.3):
    """Window with recessed glass, frame, mullion, projecting sill with drip edge and lintel; kinds add bars / shutter / AC unit / blind."""
    kind = kind or c.rng.choice(["plain", "plain", "bars", "blind", "shutter"])
    w, h = x1 - x0, z1 - z0
    bx(c, x0 + 0.03, x1 - 0.03, y - t * 0.55 - 0.02, y - t * 0.55, z0 + 0.03, z1 - 0.03, "glass_window")
    bx(c, x0, x1, y - 0.06, y - 0.02, z0, z0 + 0.04, frame)
    bx(c, x0, x1, y - 0.06, y - 0.02, z1 - 0.04, z1, frame)
    bx(c, x0, x0 + 0.04, y - 0.06, y - 0.02, z0, z1, frame)
    bx(c, x1 - 0.04, x1, y - 0.06, y - 0.02, z0, z1, frame)
    if w > 0.8:
        bx(c, (x0 + x1) / 2 - 0.02, (x0 + x1) / 2 + 0.02, y - 0.06, y - 0.02, z0, z1, frame)
    if h > 1.0:
        bx(c, x0, x1, y - 0.06, y - 0.02, z0 + h * 0.62, z0 + h * 0.62 + 0.035, frame)
    bx(c, x0 - 0.08, x1 + 0.08, y - 0.02, y + 0.10, z0 - 0.045, z0 - 0.0, "concrete")                           # sill
    bx(c, x0 - 0.06, x1 + 0.06, y - 0.02, y + 0.03, z1, z1 + 0.09, "steel_structure")                           # lintel angle
    c.drips.append(((x0 + x1) / 2, y, z0 - 0.04, w * 0.45, 0.35))
    if kind == "bars":
        for i in range(1, int(w / 0.13)):
            xx = x0 + i * 0.13
            cylv(c, xx, y + 0.05, z0, z1, 0.009, "steel_structure", seg=5)
        bx(c, x0, x1, y + 0.04, y + 0.06, z0 + h * 0.5 - 0.01, z0 + h * 0.5 + 0.01, "steel_structure")
    elif kind == "ac":
        ac_unit(c, (x0 + x1) / 2, y, z0 - 0.5 - 0.05, min(w * 0.7, 0.8))
    elif kind == "shutter":
        zc = z1 - h * 0.35
        for i in range(int((zc - z0) / 0.07)):
            bx(c, x0 - 0.02, x1 + 0.02, y + 0.03, y + 0.055, zc - (i + 1) * 0.07, zc - i * 0.07 - 0.01, "cladding_corrugated")
        bx(c, x0 - 0.03, x1 + 0.03, y + 0.02, y + 0.12, zc, z1 + 0.04, "cladding_corrugated")
    elif kind == "blind":
        bx(c, x0 + 0.05, x1 - 0.05, y - t * 0.55, y - t * 0.55 + 0.02, z0 + h * 0.4, z1 - 0.05, "fabric_awning")
    return kind


def ac_unit(c, x, y, z, w=0.8):
    bx(c, x - w / 2, x + w / 2, y, y + 0.28, z, z + 0.5, "equipment_steel")
    cyly(c, x, y + 0.28, y + 0.32, z + 0.27, w * 0.32, "steel_structure", seg=14)
    for i in range(5):
        bx(c, x - w / 2 + 0.05, x + w / 2 - 0.05, y + 0.28, y + 0.30, z + 0.07 + i * 0.07, z + 0.095 + i * 0.07, "equipment_steel")
    bx(c, x - w / 2 + 0.05, x - w / 2 + 0.1, y - 0.02, y + 0.02, z - 0.15, z, "steel_structure")
    c.drips.append((x, y, z, w * 0.35, 0.4))


def personnel_door(c, x, z0, y, w=1.0, h=2.1, mat="steel_structure", lamp=True, canopy=True, step=True, t=0.3, label=None):
    x0, x1 = x - w / 2, x + w / 2
    bx(c, x0, x1, y - t * 0.6 - 0.02, y - t * 0.6, z0, z0 + h, mat)                                                # recessed leaf
    bx(c, x0 - 0.06, x0, y - t * 0.6, y + 0.03, z0, z0 + h + 0.06, mat)                                            # frame
    bx(c, x1, x1 + 0.06, y - t * 0.6, y + 0.03, z0, z0 + h + 0.06, mat)
    bx(c, x0 - 0.06, x1 + 0.06, y - t * 0.6, y + 0.03, z0 + h, z0 + h + 0.06, mat)
    bx(c, x0 + 0.05, x1 - 0.05, y - t * 0.6, y - t * 0.6 + 0.012, z0 + 0.02, z0 + 0.3, "equipment_steel")          # kick plate
    bx(c, x1 - 0.14, x1 - 0.1, y - t * 0.6, y - t * 0.6 + 0.07, z0 + 0.95, z0 + 1.2, "equipment_steel")          # pull handle
    cylx(c, x0 + 0.1, x0 + 0.34, y - t * 0.6 + 0.06, z0 + h - 0.1, 0.012, "equipment_steel", seg=5)               # door closer arm
    bx(c, x0 + 0.08, x0 + 0.3, y - t * 0.6 + 0.0, y - t * 0.6 + 0.07, z0 + h - 0.16, z0 + h - 0.06, "steel_structure")
    bx(c, x0 + 0.12, x1 - 0.12, y - t * 0.6, y - t * 0.6 + 0.01, z0 + 1.55, z0 + 1.95, "glass_window")           # vision panel
    if step:
        bx(c, x0 - 0.15, x1 + 0.15, y, y + 0.42, z0 - 0.0, z0 + 0.1, "concrete")
    if canopy:
        bx(c, x0 - 0.25, x1 + 0.25, y, y + 0.55, z0 + h + 0.12, z0 + h + 0.15, "cladding_corrugated")
        for sx in (x0 - 0.2, x1 + 0.2):
            strut(c, (sx, y, z0 + h + 0.55), (sx, y + 0.55, z0 + h + 0.15), 0.014, "steel_structure")
    if lamp:
        lamp_fixture(c, x, y + 0.05, z0 + h + 0.35)
    c.polish.append((x1 - 0.12, y, z0 + 1.1, 0.25))
    c.entrance("personnel", x, y, w, h, z0)


def roller_shutter(c, x, z0, y, w=3.0, h=2.8, raised=0.0, mat="cladding_corrugated", t=0.3):
    """Roller shutter in a real opening: slats (lowered part), side guide rails, roll hood, bottom bar, hasp; raised = metres open from the top."""
    x0, x1 = x - w / 2, x + w / 2
    zt = z0 + h
    ys = y - t * 0.45
    drop = h - raised
    if raised > 0.05:
        bx(c, x0 + 0.05, x1 - 0.05, ys - 0.5, ys - 0.45, z0, zt - drop, "plastic_rubber")                           # dark interior
        bx(c, x0 + 0.1, x0 + 0.5, ys - 0.45, ys - 0.2, z0, z0 + 0.8, "plastic_rubber")
    n = int(drop / 0.09)
    for i in range(n):
        bx(c, x0 + 0.02, x1 - 0.02, ys - 0.02, ys + 0.02, zt - (i + 1) * 0.09, zt - i * 0.09 - 0.012, mat)
    bx(c, x0 + 0.02, x1 - 0.02, ys - 0.03, ys + 0.05, zt - drop - 0.0, zt - drop + 0.07, "steel_structure")         # bottom bar
    cyly(c, x, ys + 0.05, ys + 0.09, zt - drop + 0.035, 0.018, "equipment_steel", seg=6)                              # hasp
    for xx in (x0 - 0.07, x1 + 0.0):
        bx(c, xx, xx + 0.07, y - t * 0.6, y + 0.02, z0, zt + 0.05, "steel_structure")                                 # guide rails
    bx(c, x0 - 0.1, x1 + 0.1, y - 0.1, y + 0.2, zt, zt + 0.3, "steel_structure")                                      # roll hood
    cyly(c, x1 + 0.0, y + 0.2, y + 0.22, zt + 0.15, 0.04, "equipment_steel", seg=8)                                   # axle cap
    bx(c, x0 - 0.12, x1 + 0.12, y - 0.0, y + 0.08, z0 - 0.0, z0 + 0.06, "concrete")                                  # threshold
    c.dirty.append((x, y, z0, w * 0.6, 0.3))
    c.entrance("shutter", x, y, w, h, z0)


def lamp_fixture(c, x, y, z, reach=0.3, down=True, glass=True, anchor=True, color=(1.0, 0.78, 0.45), rng_m=7.0, shadow=False):
    bx(c, x - 0.05, x + 0.05, y - 0.04, y + 0.0, z - 0.08, z + 0.08, "steel_structure")
    strut(c, (x, y, z), (x, y + reach, z + 0.05), 0.012, "steel_structure")
    bx(c, x - 0.1, x + 0.1, y + reach - 0.06, y + reach + 0.12, z + 0.0, z + 0.07, "steel_structure")               # hood
    if glass:
        bx(c, x - 0.07, x + 0.07, y + reach - 0.03, y + reach + 0.09, z - 0.025, z, "lamp_glass")
    if anchor:
        c.anchor("fixture", (x, y + reach + 0.03, z - 0.05), (0, 0.4, -0.9), color, rng_m, 1.0, shadow)


def downspout(c, x, y, z0, z1, r=0.045):
    cylv(c, x, y, z0 + 0.35, z1, r, "equipment_steel", seg=8)
    cylv(c, x, y, z0, z0 + 0.35, r * 1.15, "equipment_steel", seg=8)
    bx(c, x - 0.1, x + 0.1, y + 0.06, y + 0.16, z0 - 0.0, z0 + 0.03, "concrete")                                       # splash block
    z = z0 + 0.6
    while z < z1:
        bx(c, x - r - 0.02, x + r + 0.02, y - r - 0.03, y - r, z, z + 0.03, "steel_structure")
        z += 1.1
    c.drips.append((x, y, z1, 0.15, 0.55))


def pipe_run(c, pts, r=0.04, mat="equipment_steel", bracket=1.2, seg=8):
    for a, b in zip(pts, pts[1:]):
        c.m.cyl(a, b, r, r, mat, seg=seg, smooth=False)
        cyls = c.m.sphere(b, r * 1.18, mat, seg=6, rings=4, smooth=False)
        L = (V(b) - V(a)).length
        k = int(L / bracket)
        for i in range(1, k + 1):
            p = V(a) + (V(b) - V(a)) * (i / (k + 1))
            bx(c, p.x - r * 1.4, p.x + r * 1.4, p.y - r * 1.4 - 0.02, p.y - r * 1.0, p.z - r * 1.4, p.z + r * 1.4, "steel_structure") if abs((V(b) - V(a)).y) < 1e-6 else None


def junction_box(c, x, y, z, w=0.3, h=0.4, d=0.14, mat="equipment_steel", label=True):
    bx(c, x - w / 2, x + w / 2, y, y + d, z, z + h, mat)
    bx(c, x - w / 2 + 0.02, x + w / 2 - 0.02, y + d, y + d + 0.012, z + 0.02, z + h - 0.02, "steel_structure")
    cyly(c, x + w / 2 - 0.05, y + d + 0.012, y + d + 0.03, z + h / 2, 0.012, "equipment_steel", seg=5)
    cylv(c, x - w * 0.25, y + d * 0.5, z + h, z + h + 0.18, 0.016, "steel_structure", seg=6)
    c.drips.append((x, y, z, w * 0.5, 0.25))


def meter_cluster(c, x, y, z, n=4):
    bx(c, x - 0.1 * n - 0.05, x + 0.1 * n + 0.05, y, y + 0.12, z, z + 0.55, "steel_structure")
    for i in range(n):
        xx = x + (i - (n - 1) / 2) * 0.2
        cyly(c, xx, y + 0.12, y + 0.17, z + 0.34, 0.075, "glass_window", seg=10)
        bx(c, xx - 0.07, xx + 0.07, y + 0.12, y + 0.15, z + 0.06, z + 0.17, "equipment_steel")
    c.anchor("service", (x, y + 0.3, z + 0.6), (0, 1, -0.3), (0.9, 0.95, 1.0), 3.5, 0.5)


def cable_sag(c, p0, p1, sag=0.25, r=0.012, mat="plastic_rubber"):
    mid = (V(p0) + V(p1)) / 2 - V((0, 0, sag))
    c.m.tube([p0, mid, p1], [r, r, r], mat, seg=5, samples=7, round_ends=(False, False))


# ------------------------------------------------------------------------------------------------ roofs
def parapet(c, x0, x1, y_f, y_b, z, h=0.55, mat_wall="concrete", t=0.25, roof_mat="roof_membrane", scuppers=(), fronts=True):
    """Flat roof: membrane slab with upturn, parapet walls with coping, scuppers with rain streaks."""
    bx(c, x0, x1, y_b, y_f, z - 0.2, z, roof_mat)
    bx(c, x0, x1, y_f - t, y_f, z, z + h, mat_wall)
    bx(c, x0, x1, y_b, y_b + t, z, z + h, mat_wall)
    bx(c, x0, x0 + t, y_b, y_f, z, z + h, mat_wall)
    bx(c, x1 - t, x1, y_b, y_f, z, z + h, mat_wall)
    bx(c, x0 - 0.04, x1 + 0.04, y_f - t - 0.04, y_f + 0.06, z + h, z + h + 0.06, "concrete")                          # coping
    bx(c, x0 - 0.04, x1 + 0.04, y_b - 0.06, y_b + t + 0.04, z + h, z + h + 0.06, "concrete")
    bx(c, x0 - 0.04, x0 + t + 0.04, y_b, y_f, z + h, z + h + 0.06, "concrete")
    bx(c, x1 - t - 0.04, x1 + 0.04, y_b, y_f, z + h, z + h + 0.06, "concrete")
    for sx in scuppers:
        bx(c, sx - 0.12, sx + 0.12, y_f - t - 0.02, y_f + 0.18, z + 0.01, z + 0.12, "equipment_steel")
        c.drips.append((sx, y_f, z + 0.1, 0.25, 0.6))


def water_tank(c, x, y, z, r=0.9, h=1.6, legs=4):
    for i in range(legs):
        a = math.pi / 4 + i * 2 * math.pi / legs
        px, py = x + math.cos(a) * r * 0.8, y + math.sin(a) * r * 0.8
        cylv(c, px, py, z, z + 1.0, 0.04, "steel_structure", seg=6)
    for zz in (z + 0.45, z + 0.8):
        bx(c, x - r * 0.85, x + r * 0.85, y - r * 0.85, y + r * 0.85, zz, zz + 0.04, "steel_structure")
    bx(c, x - r, x + r, y - r, y + r, z + 1.0, z + 1.08, "steel_structure")
    cylv(c, x, y, z + 1.08, z + 1.0 + h, r, "cladding_corrugated", seg=16)
    cylv(c, x, y, z + 1.0 + h, z + 1.06 + h, r * 1.03, "steel_structure", seg=16)
    cylv(c, x, y, z + 1.06 + h, z + 1.14 + h, r * 0.18, "equipment_steel", seg=8)
    for zz in (z + 1.3, z + 1.0 + h * 0.6, z + 1.0 + h * 0.9):
        cylv(c, x, y, zz, zz + 0.04, r * 1.035, "steel_structure", seg=16)
    c.drips.append((x, y, z + 1.0, r * 0.7, 0.5))


def vent_stack(c, x, y, z, h=1.2, r=0.12, cap=True):
    cylv(c, x, y, z, z + h, r, "equipment_steel", seg=10)
    cylv(c, x, y, z, z + 0.12, r * 1.4, "steel_structure", seg=10)
    if cap:
        c.m.cyl((x, y, z + h), (x, y, z + h + 0.16), r * 1.6, 0.0, "steel_structure", seg=10, smooth=False)
        for a in (0, 2.1, 4.2):
            strut(c, (x + math.cos(a) * r * 0.9, y + math.sin(a) * r * 0.9, z + h), (x + math.cos(a) * r * 0.2, y + math.sin(a) * r * 0.2, z + h + 0.14), 0.01, "steel_structure")


def hvac_box(c, x, y, z, w=1.6, d=1.0, h=0.9):
    bx(c, x - w / 2, x + w / 2, y - d / 2, y + d / 2, z, z + h, "equipment_steel")
    bx(c, x - w / 2 - 0.03, x + w / 2 + 0.03, y - d / 2 - 0.03, y + d / 2 + 0.03, z + h, z + h + 0.05, "steel_structure")
    cylv(c, x - w * 0.22, y, z + h + 0.05, z + h + 0.07, w * 0.22, "steel_structure", seg=16)
    for i in range(4):
        strut(c, (x - w * 0.22 - w * 0.22, y, z + h + 0.06), (x - w * 0.22 + w * 0.22, y, z + h + 0.06), 0.012, "steel_structure") if i == 0 else None
    for i in range(6):
        bx(c, x + w / 2, x + w / 2 + 0.02, y - d / 2 + 0.08, y + d / 2 - 0.08, z + 0.1 + i * 0.12, z + 0.14 + i * 0.12, "steel_structure")
    bx(c, x + w * 0.1, x + w * 0.5, y - d * 0.6, y - d * 0.5 - 0.0, z + 0.1, z + 0.4, "steel_structure")
    c.dirty.append((x, y, z + h, 0.8, 0.3))


def antenna(c, x, y, z, h=3.0):
    cylv(c, x, y, z, z + h, 0.025, "steel_structure", seg=6)
    for k in (0.5, 0.75, 0.95):
        bx(c, x - 0.5 * (1.15 - k), x + 0.5 * (1.15 - k), y - 0.01, y + 0.01, z + h * k, z + h * k + 0.015, "steel_structure")
    for a in (0.0, 2.1, 4.2):
        strut(c, (x, y, z + h * 0.6), (x + math.cos(a) * 0.9, y + math.sin(a) * 0.9, z), 0.006, "steel_structure", seg=4)


def ladder(c, x, y, z0, z1, w=0.45):
    for sx in (-w / 2, w / 2):
        bx(c, x + sx - 0.02, x + sx + 0.02, y, y + 0.05, z0, z1, "steel_structure")
    k = int((z1 - z0) / 0.3)
    for i in range(k):
        cylx(c, x - w / 2, x + w / 2, y + 0.025, z0 + 0.25 + i * 0.3, 0.012, "steel_structure", seg=5)
    for zz in (z0 + 0.3, z1 - 0.3):
        bx(c, x - w / 2, x + w / 2, y - 0.1, y, zz, zz + 0.03, "steel_structure")


def railing(c, x0, x1, y, z, h=1.0, post_step=1.2, mat="steel_structure", infill=False):
    n = max(1, int(round((x1 - x0) / post_step)))
    for i in range(n + 1):
        xx = x0 + (x1 - x0) * i / n
        cylv(c, xx, y, z, z + h, 0.02, mat, seg=5)
    for zz in (z + h, z + h * 0.55):
        cylx(c, x0, x1, y, zz, 0.018, mat, seg=5)
    if infill:
        k = int((x1 - x0) / 0.12)
        for i in range(k):
            cylv(c, x0 + (i + 0.5) * (x1 - x0) / k, y, z + 0.08, z + h * 0.55, 0.008, mat, seg=4)


def crate_stack(c, x, y, z, nx=2, nz=2, w=0.5, d=0.4, h=0.3, mat="plastic_rubber"):
    for i in range(nx):
        for k in range(nz):
            off = c.r(-0.02, 0.02)
            bx(c, x + i * w + off, x + (i + 1) * w - 0.015 + off, y, y + d, z + k * h, z + (k + 1) * h - 0.012, mat)
            bx(c, x + i * w + 0.05 + off, x + (i + 1) * w - 0.065 + off, y + d - 0.002, y + d + 0.004, z + k * h + 0.06, z + (k + 1) * h - 0.07, "cladding_patch")


def barrel(c, x, y, z, r=0.3, h=0.9, mat="cladding_patch"):
    cylv(c, x, y, z, z + h, r, mat, seg=12)
    for zz in (z + h * 0.15, z + h * 0.5, z + h * 0.85):
        cylv(c, x, y, zz, zz + 0.035, r * 1.03, "steel_structure", seg=12)
    cylv(c, x, y, z + h, z + h + 0.015, r * 0.97, "steel_structure", seg=12)


def gas_cylinder(c, x, y, z, r=0.11, h=1.2):
    cylv(c, x, y, z, z + h * 0.8, r, "equipment_steel", seg=10)
    c.m.sphere((x, y, z + h * 0.8), r, "equipment_steel", scale=(1, 1, 0.55), seg=10, rings=4, smooth=False)
    cylv(c, x, y, z + h * 0.9, z + h, 0.03, "steel_structure", seg=6)
    cylv(c, x, y, z + h * 0.78, z + h * 0.82, r * 1.04, "steel_structure", seg=10)


def pallet(c, x, y, z, w=1.2, d=1.0):
    for i in range(3):
        bx(c, x + i * (w - 0.12) / 2, x + i * (w - 0.12) / 2 + 0.12, y, y + d, z, z + 0.09, "plastic_rubber")
    for i in range(5):
        bx(c, x, x + w, y + i * (d - 0.1) / 4, y + i * (d - 0.1) / 4 + 0.1, z + 0.09, z + 0.12, "plastic_rubber")


def tyre_stack(c, x, y, z, n=3, r=0.32):
    for i in range(n):
        cylv(c, x, y, z + i * 0.2, z + i * 0.2 + 0.19, r, "plastic_rubber", seg=12)


def awning(c, x0, x1, y, z, proj=1.5, drop=0.55, mat="fabric_awning", rods=True, sag=0.04):
    """Canvas awning: sagging sloped panel (3x9 grid), scalloped valance, support rods and wall bracket."""
    cols = max(5, int((x1 - x0) / 0.35))
    rows = []
    for i in range(4):
        t = i / 3
        rows.append([V((x0 + (x1 - x0) * j / (cols - 1), y + proj * t, z - drop * t - sag * math.sin(math.pi * j / (cols - 1)) * (0.2 + t))) for j in range(cols)])
    c.m.surface(rows, False, mat, smooth=False)
    c.m.surface(rows[::-1], False, mat, smooth=False)
    for j in range(cols - 1):
        a = rows[-1][j]
        b = rows[-1][j + 1]
        mid = (a + b) / 2 + V((0, 0.0, -0.17))
        tri = [c.m.bm.verts.new(p) for p in (a, b, mid)]
        try:
            f = c.m.bm.faces.new(tri)
            f.material_index = c.m.mi(mat)
        except ValueError:
            pass
        try:
            f = c.m.bm.faces.new(tri[::-1])
            f.material_index = c.m.mi(mat)
        except ValueError:
            pass
    bx(c, x0, x1, y, y + 0.05, z - 0.04, z + 0.04, "steel_structure")
    if rods:
        for xx in (x0 + 0.1, x1 - 0.1, (x0 + x1) / 2):
            strut(c, (xx, y, z - 0.05), (xx, y + proj * 0.98, z - drop - 0.03), 0.014, "steel_structure")
        cylx(c, x0, x1, y + proj, z - drop - 0.02, 0.018, "steel_structure", seg=6)
    c.drips.append(((x0 + x1) / 2, y, z, (x1 - x0) * 0.3, 0.4))


def sign_board(c, tile, x, y, z, w=3.0, h=0.75, hanging=False, projecting=False, frame="steel_structure", lit=True):
    """Physical sign: steel frame, atlas face (explicit UV tile), brackets, cable gland and a junction box; emissive via sign_atlas only."""
    d = 0.14
    bx(c, x - w / 2 - 0.04, x + w / 2 + 0.04, y, y + d, z - h / 2 - 0.04, z + h / 2 + 0.04, frame)
    f = bx(c, x - w / 2, x + w / 2, y + d, y + d + 0.012, z - h / 2, z + h / 2, "sign_atlas")
    set_uv_rect(c, f, T.sign_tile_uv(tile))
    for sx in (x - w / 2 + 0.2, x + w / 2 - 0.2):
        bx(c, sx - 0.03, sx + 0.03, y - 0.08, y, z - h / 2 - 0.04, z + h / 2 + 0.04, frame) if not hanging else None
    junction_box(c, x + w / 2 - 0.3, y - 0.1, z - h / 2 - 0.45, 0.2, 0.28, 0.1)
    cable_sag(c, (x + w / 2 - 0.3, y - 0.05, z - h / 2 - 0.2), (x + w / 2 - 0.3, y + 0.05, z - h / 2 - 0.04), 0.02)
    if lit:
        c.anchor("sign", (x, y + d + 0.35, z - h / 2 - 0.1), (0, 1, -0.2), (1.0, 0.78, 0.55), 6.0, 0.8)
    c.signs.append({"tile": tile, "text": T.SIGNS[tile][0]})
    c.drips.append((x, y, z - h / 2, w * 0.3, 0.3))


def blade_sign(c, tile, x, y, z, w=0.9, h=0.45, stub=1.0):
    """Projecting blade sign hung on a bracket (double-faced): the face normal is +/-X."""
    bx(c, x - 0.04, x + 0.04, y, y + stub, z + h / 2 + 0.05, z + h / 2 + 0.09, "steel_structure")
    for sy in (y + 0.15, y + stub - 0.15):
        cylv(c, x, sy, z + h / 2, z + h / 2 + 0.07, 0.01, "steel_structure", seg=4)
    ya, yb = y + (stub - w) / 2 + 0.0, y + (stub + w) / 2
    bx(c, x - 0.05, x + 0.05, ya, yb, z - h / 2, z + h / 2, "steel_structure")
    for side, nx in ((1, 1), (-1, -1)):
        f = bx(c, x + side * 0.05, x + side * 0.062, ya + 0.03, yb - 0.03, z - h / 2 + 0.03, z + h / 2 - 0.03, "sign_atlas")
        # face normal along +/-X; map y -> u, z -> v
        for fc in f:
            if (fc.normal - V((nx, 0, 0))).length < 0.2:
                c.m.explicit.add(fc)
                u0, v0, u1, v1 = T.sign_tile_uv(tile)
                for lp in fc.loops:
                    p = lp.vert.co
                    su = (p.y - ya) / (yb - ya)
                    if nx < 0:
                        su = 1 - su
                    lp[c.m.uv].uv = (u0 + (u1 - u0) * max(0, min(1, su)), v0 + (v1 - v0) * (p.z - (z - h / 2)) / h)
    c.signs.append({"tile": tile, "text": T.SIGNS[tile][0], "blade": True})
    c.anchor("sign", (x + 0.4, y + stub * 0.5, z - 0.3), (0.5, 0.3, -0.4), (1.0, 0.8, 0.6), 4.5, 0.6)


def bollard(c, x, y, z0, h=0.9, r=0.1, stripe=True):
    cylv(c, x, y, z0, z0 + h, r, "concrete", seg=10)
    cylv(c, x, y, z0 + h * 0.55, z0 + h * 0.7, r * 1.04, "cladding_patch", seg=10)
    cylv(c, x, y, z0 + h, z0 + h + 0.02, r * 0.8, "steel_structure", seg=10)


def hazard_stripe(c, x0, x1, y, z0, z1, n=8):
    """Warning chevrons as thin alternating strips on the wall (paint, real raised geometry kept minimal)."""
    w = (x1 - x0) / n
    for i in range(0, n, 2):
        bx(c, x0 + i * w, x0 + (i + 1) * w, y, y + 0.006, z0, z1, "cladding_patch")


def plinth_band(c, x0, x1, y, h=0.45, t=0.08):
    bx(c, x0, x1, y - 0.0, y + t, 0.0, h, "concrete")
    c.dirty.append(((x0 + x1) / 2, y, 0.0, (x1 - x0) * 0.4, 0.2))


def fence_panel(c, x0, x1, y, z0=0.0, h=2.0, post_step=2.0):
    """Chain-link panel: posts, top/bottom rails, diagonal tension wires and a barbed top (cheap geometry, reads as mesh)."""
    n = max(1, int(round((x1 - x0) / post_step)))
    for i in range(n + 1):
        cylv(c, x0 + (x1 - x0) * i / n, y, z0, z0 + h + 0.2, 0.03, "steel_structure", seg=6)
    cylx(c, x0, x1, y, z0 + h, 0.02, "steel_structure", seg=5)
    cylx(c, x0, x1, y, z0 + 0.1, 0.02, "steel_structure", seg=5)
    cylx(c, x0, x1, y, z0 + h + 0.2, 0.012, "steel_structure", seg=4)
    k = int((x1 - x0) / 0.45)
    for i in range(k):
        xa = x0 + i * (x1 - x0) / k
        xb = x0 + (i + 1) * (x1 - x0) / k
        strut(c, (xa, y, z0 + 0.1), (xb, y, z0 + h), 0.005, "steel_structure", seg=3)
        strut(c, (xa, y, z0 + h), (xb, y, z0 + 0.1), 0.005, "steel_structure", seg=3)
