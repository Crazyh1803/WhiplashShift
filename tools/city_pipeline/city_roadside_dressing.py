"""Street-level dressing for the roadside layer: open burning barrels and four small encampments. Foot-centred (footprint centre at xz 0, y=0 on the
ground), Blender Z-up with the street on +Y (glTF -Z). Library materials only; everything is real geometry with wear baked by city_roadside_common."""
import math

from mathutils import Vector

import city_roadside_common as R
import city_realism_parts as P

V = Vector
bx, cylv = P.bx, P.cylv


def tarp(c, a, b, d, e, sag, mat, cols=7, rows=5, edge=True):
    """Sagging two-sided sheet through corners a(0,0) b(1,0) d(0,1) e(1,1); grommets and a cord along the lower edge."""
    a, b, d, e = V(a), V(b), V(d), V(e)
    grid = []
    for i in range(rows):
        v = i / (rows - 1)
        row = []
        for j in range(cols):
            u = j / (cols - 1)
            p = (a * (1 - u) + b * u) * (1 - v) + (d * (1 - u) + e * u) * v
            p.z -= sag * math.sin(math.pi * u) * math.sin(math.pi * v) * 1.0
            row.append(p)
        grid.append(row)
    c.m.surface(grid, False, mat, smooth=False)
    c.m.surface(grid[::-1], False, mat, smooth=False)
    if edge:
        for j in range(0, cols, 2):
            p = grid[0][j]
            c.m.cyl(p + V((0, 0, 0.02)), p - V((0, 0, 0.1)), 0.012, 0.012, "plastic_rubber", seg=5, smooth=False)
        c.m.cyl(grid[0][0], grid[0][-1] + V((0, 0, 0.0)), 0.008, 0.008, "plastic_rubber", seg=4, smooth=False)
    return grid


def pole(c, x, y, z0, z1, lean=(0.0, 0.0), r=0.025, mat="steel_structure"):
    c.m.cyl((x, y, z0), (x + lean[0], y + lean[1], z1), r, r, mat, seg=6, smooth=False)
    c.m.cyl((x, y, z0), (x, y, z0 + 0.04), r * 2.2, r * 2.2, "concrete", seg=6, smooth=False)


def rope(c, p0, p1, sag=0.08, r=0.007, n=6):
    p0, p1 = V(p0), V(p1)
    prev = p0
    for i in range(1, n + 1):
        t = i / n
        p = p0 * (1 - t) + p1 * t
        p.z -= sag * math.sin(math.pi * t)
        c.m.cyl(prev, p, r, r, "plastic_rubber", seg=4, smooth=False)
        prev = p


def bedroll(c, x, y, ang, length=1.7, w=0.62, rolled=False, tint=(0.78, 0.62, 0.5)):
    """Sleeping mat + blanket (flat) or a tied roll."""
    ca, sa = math.cos(ang), math.sin(ang)
    if rolled:
        p0, p1 = V((x - ca * length / 2, y - sa * length / 2, 0.14)), V((x + ca * length / 2, y + sa * length / 2, 0.14))
        c.m.cyl(p0, p1, 0.14, 0.14, "render_plaster", seg=10, smooth=True)
        for t in (0.25, 0.75):
            q = p0 * (1 - t) + p1 * t
            c.m.cyl(q - V((ca, sa, 0)) * 0.02, q + V((ca, sa, 0)) * 0.02, 0.155, 0.155, "plastic_rubber", seg=10, smooth=False)
        c.tints.append((x, y, 0.14, length, tint, "render_plaster"))
        return
    c.m.box((x, y, 0.025), (length, w, 0.05), "plastic_rubber", rot=(0, 0, ang))                      # foam mat
    c.m.box((x + ca * 0.05, y + sa * 0.05, 0.07), (length * 0.86, w * 0.9, 0.06), "fabric_awning", rot=(0, 0, ang), bevel=0.02)
    px, py = x - ca * length * 0.38, y - sa * length * 0.38
    c.m.box((px, py, 0.12), (0.34, w * 0.62, 0.1), "render_plaster", rot=(0, 0, ang), bevel=0.03)     # pillow
    c.tints.append((px, py, 0.12, 0.4, tint, "render_plaster"))


def sack(c, x, y, r=0.2, squash=0.7, tilt=0.0, mat="render_plaster", tint=None):
    c.m.sphere((x, y, r * squash), r, mat, scale=(1.0, 0.9, squash), seg=9, rings=6, smooth=True)
    c.m.cyl((x, y, r * squash * 1.9), (x, y, r * squash * 2.15), r * 0.22, r * 0.12, "plastic_rubber", seg=6, smooth=False)
    if tint:
        c.tints.append((x, y, r * squash, r * 1.4, tint, mat))


def backpack(c, x, y, ang, tint=(0.55, 0.5, 0.4)):
    c.m.box((x, y, 0.28), (0.34, 0.2, 0.52), "fabric_awning", rot=(0, 0, ang), bevel=0.04)
    ca, sa = math.cos(ang), math.sin(ang)
    c.m.box((x + sa * 0.12, y - ca * 0.12, 0.2), (0.26, 0.08, 0.22), "plastic_rubber", rot=(0, 0, ang), bevel=0.02)
    c.m.box((x - sa * 0.0, y + ca * 0.0, 0.5), (0.3, 0.2, 0.05), "plastic_rubber", rot=(0, 0, ang))
    c.tints.append((x, y, 0.3, 0.5, tint, "fabric_awning"))


def bucket(c, x, y, r=0.17, h=0.3):
    c.m.cyl((x, y, 0), (x, y, h), r * 0.8, r, "equipment_steel", seg=10, smooth=True)
    c.m.cyl((x, y, h - 0.01), (x, y, h + 0.02), r * 1.04, r * 1.04, "steel_structure", seg=10, smooth=False)
    c.m.cyl((x - r, y, h), (x + r, y, h), 0.008, 0.008, "steel_structure", seg=4, smooth=False)


def jug(c, x, y, h=0.38):
    c.m.box((x, y, h / 2), (0.2, 0.15, h), "plastic_rubber", bevel=0.04)
    c.m.cyl((x, y, h), (x, y, h + 0.06), 0.035, 0.035, "plastic_rubber", seg=6, smooth=False)


def stove_pot(c, x, y):
    cylv(c, x, y, 0, 0.3, 0.1, "equipment_steel", seg=10)                                  # gas bottle stand
    c.m.cyl((x, y, 0.3), (x, y, 0.36), 0.15, 0.15, "steel_structure", seg=10, smooth=False)
    c.m.cyl((x, y, 0.36), (x, y, 0.58), 0.14, 0.12, "equipment_steel", seg=10, smooth=True)
    c.m.cyl((x, y, 0.58), (x, y, 0.6), 0.14, 0.14, "steel_structure", seg=10, smooth=False)
    c.m.cyl((x + 0.14, y, 0.5), (x + 0.3, y, 0.55), 0.012, 0.012, "steel_structure", seg=4, smooth=False)
    c.dirty.append((x, y, 0.5, 0.5, 0.5))


def cart(c, x, y, ang, loaded=True):
    """Hand cart: plank bed on a frame, two spoked wheels, pushing handle, a lashed load."""
    ca, sa = math.cos(ang), math.sin(ang)

    def at(u, v, z):
        return V((x + ca * u - sa * v, y + sa * u + ca * v, z))
    c.m.box(at(0, 0, 0.42), (1.1, 0.7, 0.05), "plastic_rubber", rot=(0, 0, ang))
    for i in range(5):
        c.m.box(at(-0.45 + i * 0.225, 0, 0.455), (0.2, 0.68, 0.03), "plastic_rubber", rot=(0, 0, ang))
    for s in (-1, 1):
        c.m.box(at(0, s * 0.33, 0.55), (1.1, 0.04, 0.2), "cladding_patch", rot=(0, 0, ang))
        wp = at(0.1, s * 0.4, 0.28)
        c.m.cyl(wp - V((-sa, ca, 0)) * 0.03 * s * -1, wp + V((-sa, ca, 0)) * 0.03 * s * -1, 0.28, 0.28, "plastic_rubber", seg=14, smooth=False)
        hub = at(0.1, s * 0.4, 0.28)
        c.m.cyl(hub, hub + V((-sa, ca, 0)) * 0.07 * s, 0.05, 0.05, "equipment_steel", seg=6, smooth=False)
    c.m.cyl(at(0.1, -0.4, 0.28), at(0.1, 0.4, 0.28), 0.02, 0.02, "steel_structure", seg=6, smooth=False)
    c.m.cyl(at(0.55, -0.3, 0.45), at(1.45, -0.28, 0.95), 0.022, 0.022, "steel_structure", seg=6, smooth=False)
    c.m.cyl(at(0.55, 0.3, 0.45), at(1.45, 0.28, 0.95), 0.022, 0.022, "steel_structure", seg=6, smooth=False)
    c.m.cyl(at(1.45, -0.28, 0.95), at(1.45, 0.28, 0.95), 0.025, 0.025, "plastic_rubber", seg=6, smooth=False)
    if loaded:
        c.m.box(at(-0.15, 0.0, 0.72), (0.6, 0.5, 0.34), "cladding_patch", rot=(0, 0, ang), bevel=0.02)
        c.m.box(at(0.3, 0.1, 0.62), (0.4, 0.4, 0.16), "render_plaster", rot=(0, 0, ang + 0.2), bevel=0.04)
        c.tints.append((x, y, 0.6, 0.6, (0.6, 0.55, 0.45), "render_plaster"))


def crates(c, x, y, ang=0.0, nx=2, nz=2):
    ca, sa = math.cos(ang), math.sin(ang)
    for i in range(nx):
        for k in range(nz):
            off = c.r(-0.02, 0.02)
            px, py = x + ca * (i * 0.5) - sa * off, y + sa * (i * 0.5) + ca * off
            c.m.box((px, py, 0.15 + k * 0.3), (0.48, 0.4, 0.28), "plastic_rubber", rot=(0, 0, ang), bevel=0.012)
            c.m.box((px, py, 0.15 + k * 0.3), (0.34, 0.405, 0.12), "cladding_patch", rot=(0, 0, ang))


def rug(c, x, y, w, d, ang=0.0):
    c.m.box((x, y, 0.012), (w, d, 0.024), "fabric_awning", rot=(0, 0, ang))
    c.m.box((x, y, 0.014), (w * 0.94, d * 0.9, 0.024), "roof_membrane", rot=(0, 0, ang))


def clothesline(c, p0, p1, z=1.75):
    pole(c, p0[0], p0[1], 0, z + 0.1)
    pole(c, p1[0], p1[1], 0, z + 0.1)
    a, b = V((p0[0], p0[1], z)), V((p1[0], p1[1], z))
    rope(c, a, b, sag=0.12, n=8)
    n = 3
    for i in range(n):
        t = (i + 0.7) / (n + 0.6)
        q = a * (1 - t) + b * t
        q.z -= 0.12 * math.sin(math.pi * t)
        d = (b - a).normalized()
        nrm = V((-d.y, d.x, 0))
        w = c.r(0.28, 0.4)
        h = c.r(0.4, 0.7)
        corner = [q - d * w / 2, q + d * w / 2]
        rows = [[corner[0], corner[1]], [corner[0] - V((0, 0, h)) + nrm * 0.02, corner[1] - V((0, 0, h)) - nrm * 0.02]]
        c.m.surface(rows, False, "fabric_awning" if i % 2 else "render_plaster", smooth=False)
        c.m.surface(rows[::-1], False, "fabric_awning" if i % 2 else "render_plaster", smooth=False)


# -------------------------------------------------------------------------------------------------------------- barrels
def barrel_fire(variant):
    """Battered open steel drum with a burnt-out interior, glowing coals and charred wood. Fire/smoke are shader effects added by the game."""
    c = R.new_ctx("barrel_fire_" + variant)
    rng = c.rng
    h = 0.92 if variant == "a" else 0.82
    r = 0.30 if variant == "a" else 0.285
    levels = [(0.0, 0.93), (0.035, 0.985), (0.16, 1.0), (0.4, 1.01), (h * 0.62, 1.0), (h * 0.85, 0.99), (h - 0.03, 0.985), (h, 0.95)]
    seg = 16
    dents = [(rng.uniform(0, 6.28), rng.uniform(0.25, h - 0.15), rng.uniform(0.018, 0.04), rng.uniform(0.18, 0.4)) for _ in range(5)]

    def radius(z, ang, base):
        rr = r * base
        for (da, dz, depth, spread) in dents:
            d = math.hypot(math.remainder(ang - da, 6.2832), (z - dz) * 2.4)
            if d < spread * 2:
                rr -= depth * math.exp(-(d / spread) ** 2 * 2.0)
        return rr
    outer, inner = [], []
    for (z, base) in levels:
        ro, ri = [], []
        for j in range(seg):
            a = 2 * math.pi * j / seg
            lip = 0.045 * math.sin(a * 2 + 0.7) * (1 if z >= h - 0.01 else 0) + (0.025 * math.sin(a * 3) if z >= h - 0.04 and z < h else 0)
            rr = radius(z, a, base)
            ro.append((rr * math.cos(a), rr * math.sin(a), z + lip))
            ri.append(((rr - 0.014) * math.cos(a), (rr - 0.014) * math.sin(a), z + lip))
        outer.append(ro)
        inner.append(ri)
    c.m.surface(outer, True, "cladding_patch", smooth=True)
    c.m.surface(inner[::-1], True, "plastic_rubber", smooth=True)                          # burnt, sooty interior
    ring = [c.m.bm.verts.new(p) for p in outer[0]]
    c.m.fan_cap(ring, (0, 0, 0), "steel_structure", flip=True)
    rimrows = [outer[-1], inner[-1]]
    c.m.surface(rimrows, True, "steel_structure", smooth=False)                             # rolled lip
    for z in (0.17, 0.44, h * 0.8):                                                         # rolling hoops: hollow annular bands, the drum interior stays open
        ring = lambda rad, zz: [(rad * math.cos(2 * math.pi * j / seg), rad * math.sin(2 * math.pi * j / seg), zz) for j in range(seg)]
        c.m.surface([ring(r * 1.045, z), ring(r * 1.045, z + 0.035), ring(r * 0.99, z + 0.035), ring(r * 0.99, z), ring(r * 1.045, z)], True, "steel_structure", smooth=False)
    c.m.cyl((0, 0, 0), (0, 0, 0.03), r * 0.99, r * 0.99, "steel_structure", seg=seg, smooth=False)
    for (aa, zz, ww) in ((0.9, 0.3, 0.07), (3.8, 0.12, 0.05)):                               # rust-through scorch holes
        P.bx(c, r * 0.97 * math.cos(aa) - ww, r * 0.97 * math.cos(aa) + ww, r * 0.97 * math.sin(aa) - ww, r * 0.97 * math.sin(aa) + ww, zz, zz + ww * 1.4, "plastic_rubber")
    # glowing coal bed and charred scraps burning inside the drum
    top = h * 0.62
    c.m.cyl((0, 0, top - 0.02), (0, 0, top + 0.02), r * 0.84, r * 0.84, "plastic_rubber", seg=14, smooth=False)
    c.m.cyl((0, 0, top + 0.02), (0, 0, top + 0.035), r * 0.7, r * 0.7, "lamp_glass", seg=12, smooth=False)
    for k in range(6):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0.02, r * 0.55)
        base = V((d * math.cos(a), d * math.sin(a), top + 0.03))
        tip = base + V((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), rng.uniform(0.12, 0.3)))
        c.m.cyl(base, tip, 0.022, 0.016, "plastic_rubber", seg=5, smooth=False)
        c.m.cyl(base + (tip - base) * 0.75, tip + V((0, 0, 0.0)), 0.019, 0.012, "lamp_glass", seg=4, smooth=False)
    c.dirty.append((0, 0, h, 0.7, 0.55))
    c.dirty.append((0, 0, 0.15, 0.45, 0.25))
    if variant == "b":                                                                       # propped lid and a brick wind-shield
        c.m.cyl((r * 1.2, 0.0, 0.5), (r * 0.72, 0.0, 0.5), 0.3, 0.3, "steel_structure", seg=14, smooth=False)
        for i in range(3):
            P.bx(c, -r * 1.7 + i * 0.01, -r * 1.7 + 0.2 + i * 0.01, -0.12, 0.12, i * 0.075, i * 0.075 + 0.07, "brick")
    return c, {"fire": {"base": [0.0, round(top + 0.04, 3), 0.0], "radius": round(r * 0.68, 3), "flame_height": 0.78, "smoke_height": 4.6, "smoke_radius": 0.9}}


# -------------------------------------------------------------------------------------------------------------- camps
def camp(variant):
    c = R.new_ctx("camp_" + variant, 6.0, 5.0)
    rng = c.rng
    if variant == "a":                                       # lean-to tarp from a pole line, two bedrolls, handcart, crates
        for sx in (-1.9, 1.9):
            pole(c, sx, -1.4, 0, 2.15, lean=(0, 0.0))
        pole(c, -1.9, 0.9, 0, 1.0)
        pole(c, 1.9, 0.9, 0, 1.0)
        tarp(c, (-2.1, -1.5, 2.1), (2.1, -1.5, 2.1), (-2.1, 1.2, 1.05), (2.1, 1.2, 1.05), 0.22, "roof_membrane")
        rope(c, (-2.1, 1.2, 1.05), (-2.1, 1.9, 0.0), sag=0.02)
        rope(c, (2.1, 1.2, 1.05), (2.1, 1.9, 0.0), sag=0.02)
        rug(c, -0.7, -0.3, 2.0, 2.4)
        bedroll(c, -1.0, -0.5, 0.15)
        bedroll(c, 0.2, -0.45, -0.1, rolled=False, tint=(0.62, 0.7, 0.8))
        bedroll(c, 1.5, -0.9, 1.4, rolled=True)
        cart(c, 1.9, 1.7, 0.4)
        crates(c, -1.9, -1.1, 0.0, 2, 2)
        sack(c, -1.5, 0.6, 0.22, tint=(0.62, 0.55, 0.45))
        bucket(c, 2.2, -0.3)
    elif variant == "b":                                     # A-frame tarp over pallets, bags, stove and water jugs
        pole(c, -2.0, 0.0, 0, 1.9)
        pole(c, 2.0, 0.0, 0, 1.9)
        c.m.cyl((-2.0, 0, 1.9), (2.0, 0, 1.9), 0.025, 0.025, "steel_structure", seg=6, smooth=False)
        tarp(c, (-2.1, 0.0, 1.9), (2.1, 0.0, 1.9), (-2.1, 1.7, 0.1), (2.1, 1.7, 0.1), 0.1, "fabric_awning")
        tarp(c, (-2.1, 0.0, 1.9), (2.1, 0.0, 1.9), (-2.1, -1.7, 0.1), (2.1, -1.7, 0.1), 0.1, "roof_membrane")
        P.pallet(c, -1.4, -1.0, 0.0, 1.2, 1.0)
        P.pallet(c, -0.1, -1.0, 0.0, 1.2, 1.0)
        c.m.box((-0.8, -0.5, 0.2), (2.3, 0.9, 0.1), "fabric_awning", bevel=0.03)
        bedroll(c, -0.8, -0.5, 0.0, length=2.0, w=0.7, tint=(0.7, 0.62, 0.55))
        stove_pot(c, 1.6, -0.9)
        jug(c, 1.6, -0.3)
        jug(c, 1.85, -0.4)
        backpack(c, -1.9, 0.9, 0.6)
        sack(c, -1.4, 1.1, 0.24, tint=(0.55, 0.5, 0.4))
        sack(c, -1.1, 1.3, 0.2, tint=(0.7, 0.6, 0.5))
        crates(c, 1.3, 1.3, 0.2, 2, 1)
        tyre = P.tyre_stack
        tyre(c, 2.4, 1.2, 0.0, 2)
    elif variant == "c":                                     # shade cloth on four poles, cot, clothesline, shopping trolley
        for (px, py) in ((-1.8, -1.4), (1.8, -1.4), (-1.8, 1.0), (1.8, 1.0)):
            pole(c, px, py, 0, 2.2 if py < 0 else 1.8)
        tarp(c, (-2.0, -1.5, 2.25), (2.0, -1.5, 2.25), (-2.0, 1.1, 1.85), (2.0, 1.1, 1.85), 0.3, "fabric_awning")
        rug(c, 0.0, -0.2, 3.0, 2.2, 0.05)
        for lx in (-1.4, -0.0):
            P.bx(c, lx - 0.04, lx + 0.04, -0.9, 0.5, 0.0, 0.34, "steel_structure")
        c.m.box((-0.7, -0.2, 0.4), (1.9, 0.75, 0.06), "fabric_awning", bevel=0.02)
        c.m.box((-0.7, -0.2, 0.46), (1.7, 0.65, 0.09), "render_plaster", bevel=0.03)
        c.tints.append((-0.7, -0.2, 0.46, 1.1, (0.62, 0.66, 0.78), "render_plaster"))
        backpack(c, 0.9, -0.6, 2.2)
        crates(c, 1.2, 0.2, 0.0, 1, 2)
        clothesline(c, (-2.2, 1.8), (2.2, 1.9))
        cart(c, 2.1, -2.1, -0.3)
        bucket(c, -2.3, 0.3)
    else:                                                    # d: lean-to against a stack of crates and a drum, bedroll, belongings
        crates(c, -2.2, -1.5, 0.0, 3, 3)
        cylv(c, 1.2, -1.6, 0, 0.9, 0.29, "cladding_patch", seg=12)
        cylv(c, 1.2, -1.6, 0.9, 0.92, 0.3, "steel_structure", seg=12)
        tarp(c, (-2.2, -1.5, 1.05), (1.5, -1.5, 1.4), (-2.2, 0.9, 0.3), (1.5, 0.9, 0.55), 0.15, "roof_membrane")
        pole(c, -2.3, 0.9, 0, 0.35)
        pole(c, 1.5, 0.9, 0, 0.6)
        rug(c, -0.4, -0.6, 2.2, 1.8, 0.1)
        bedroll(c, -0.5, -0.5, 0.05, length=1.8)
        bedroll(c, 0.7, -1.1, 1.0, rolled=True, tint=(0.7, 0.68, 0.6))
        backpack(c, 0.4, 0.45, 0.3)
        backpack(c, 0.9, 0.5, -0.6, tint=(0.6, 0.5, 0.4))
        sack(c, -1.5, 1.4, 0.2, tint=(0.6, 0.55, 0.5))
        bucket(c, 1.9, 0.9)
        jug(c, 2.15, 0.7)
        stove_pot(c, 1.9, -0.4)
    return c, {}
