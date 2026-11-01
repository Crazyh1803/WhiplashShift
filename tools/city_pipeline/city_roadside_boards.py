"""Boarded-up overlays, one per frontage family. Each overlay is built from the family GLB itself: every glass pane (>= 0.7 m both ways) is found by its
library material and gets a board set fitted to its real size and depth (plank, plywood, corrugated sheet or X-braced, chosen per window), and each
authored ground door gets a barricade with hasp, chain and padlock. The overlay uses the host's local frame, so one transform places it on the host
and it scales with scaled infill hosts. Overlays only sit over their own host (<= 0.12 m proud of window frames; doors <= 0.1 m).

Families skipped: redline_shop (actor pairs, counter and entrance stay intact)."""
import math
import os

import bmesh
import bpy
from mathutils import Vector

import city_roadside_common as R
import city_realism_parts as P

V = Vector
bx = P.bx
REALISM = R.REAL
FAMILIES = ["habitation_workshop", "market_habitat", "service_tenement", "freight_depot", "row_workshop", "utility_substation", "transit_depot"]
# (x centre, z0, width, height, wall plane y) of authored doors, from the family builders
DOORS = {
    "habitation_workshop": [(-1.15, 0.3, 1.0, 2.1, 0.0), (10.65, 0.3, 1.0, 2.1, 0.0)],
    "market_habitat": [(6.95, 0.0, 1.1, 2.2, -2.3)],
    "service_tenement": [(1.55, 0.0, 1.1, 2.3, 0.0)],
    "freight_depot": [],
    "row_workshop": [(-2.4, 0.0, 1.0, 2.3, 0.0), (-1.2, 0.0, 0.9, 2.3, 0.0), (10.1, 0.0, 1.0, 2.3, 0.0)],
    "utility_substation": [(-1.1, 0.0, 1.0, 2.3, 0.0)],
    "transit_depot": [(9.4, 0.0, 1.1, 2.3, 0.2)],
}
WOOD = (0.62, 0.5, 0.4)
PLY = (0.8, 0.66, 0.46)


def panes(name):
    """[(x0, x1, z0, z1, front_y)] for every window-sized glass_window component of the family mesh, in Blender (builder) coordinates."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(REALISM, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    out = []
    for o in new:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.transform(bm, matrix=o.matrix_world, verts=bm.verts)
        slots = [i for i, m in enumerate(o.data.materials) if m is not None and m.name.split(".")[0] == "glass_window"]
        faces = [f for f in bm.faces if f.material_index in slots]
        seen = set()
        for f in faces:
            if f in seen:
                continue
            comp, stack = [], [f]
            seen.add(f)
            while stack:
                g = stack.pop()
                comp.append(g)
                for e in g.edges:
                    for h in e.link_faces:
                        if h not in seen and h.material_index in slots:
                            seen.add(h)
                            stack.append(h)
            vs = [v.co for g in comp for v in g.verts]
            x0, x1 = min(v.x for v in vs), max(v.x for v in vs)
            z0, z1 = min(v.z for v in vs), max(v.z for v in vs)
            y1 = max(v.y for v in vs)
            if x1 - x0 >= 0.7 and z1 - z0 >= 0.7 and (max(v.y for v in vs) - min(v.y for v in vs)) < 0.2 and y1 > -3.0:     # street-facing wall only
                out.append((x0, x1, z0, z1, y1))
        bm.free()
    for o in new:
        bpy.data.objects.remove(o)
    return sorted(out, key=lambda p: (round(p[2], 1), p[0]))


def nail(c, x, y, z):
    P.cyly(c, x, y, y + 0.025, z, 0.013, "equipment_steel", seg=5)


def planks(c, x0, x1, z0, z1, y):
    h = z1 - z0
    n = max(3, int(round(h / 0.22)))
    ph = h / n
    for i in range(n):
        zl = z0 + i * ph + 0.008
        zh = zl + ph - 0.016
        a, b = x0 - 0.05 - c.r(0, 0.07), x1 + 0.05 + c.r(0, 0.07)
        off = c.r(0, 0.018)
        bx(c, a, b, y + off, y + off + 0.035, zl, zh, "cladding_patch")
        c.tints.append(((a + b) / 2, y, (zl + zh) / 2, 0.5, WOOD, "cladding_patch"))
    for xb in (x0 + 0.1, x1 - 0.1):
        bx(c, xb - 0.045, xb + 0.045, y + 0.035, y + 0.07, z0 - 0.05, z1 + 0.05, "cladding_patch")
        for i in range(n):
            nail(c, xb, y + 0.07, z0 + (i + 0.5) * ph)
    c.dirty.append(((x0 + x1) / 2, y, z0, (x1 - x0) * 0.6, 0.4))


def plywood(c, x0, x1, z0, z1, y):
    bx(c, x0 - 0.08, x1 + 0.08, y, y + 0.03, z0 - 0.08, z1 + 0.08, "render_plaster")
    c.tints.append(((x0 + x1) / 2, y, (z0 + z1) / 2, 2.5, PLY, "render_plaster"))
    for zb in (z0 + 0.15, z1 - 0.15):
        bx(c, x0 - 0.1, x1 + 0.1, y + 0.03, y + 0.065, zb - 0.045, zb + 0.045, "cladding_patch")
        for k in range(int((x1 - x0) / 0.4) + 1):
            nail(c, x0 + 0.05 + k * 0.4, y + 0.065, zb)
    L = math.hypot(x1 - x0, z1 - z0) * 0.9
    ang = math.atan2(z1 - z0, x1 - x0)
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    c.m.box((cx, y + 0.034, cz), (L, 0.006, 0.07), "cladding_patch", rot=(0, -ang, 0))               # painted slash
    bx(c, x1 - 0.3, x1 + 0.08, y, y + 0.035, z0 - 0.08, z0 + 0.08, "plastic_rubber")                  # torn corner
    c.drips.append(((x0 + x1) / 2, y, z0 - 0.08, (x1 - x0) * 0.4, 0.45))


def sheet(c, x0, x1, z0, z1, y):
    P.corrugated(c, x0 - 0.06, x1 + 0.06, z0 - 0.06, z1 + 0.06, y + 0.035, "cladding_corrugated", pitch=0.17, depth=0.035)
    for zb in (z0 - 0.04, z1 + 0.04):
        bx(c, x0 - 0.08, x1 + 0.08, y + 0.035, y + 0.075, zb - 0.04, zb + 0.04, "steel_structure")
        for k in range(int((x1 - x0) / 0.35) + 1):
            P.cyly(c, x0 + k * 0.35, y + 0.075, y + 0.1, zb, 0.016, "equipment_steel", seg=6)
    c.drips.append(((x0 + x1) / 2, y, z0, (x1 - x0) * 0.4, 0.5))


def braced(c, x0, x1, z0, z1, y):
    for i in range(4):
        zl = z0 + 0.05 + i * (z1 - z0 - 0.3) / 3
        bx(c, x0 - 0.04, x1 + 0.04, y, y + 0.03, zl, zl + 0.18, "cladding_patch")
        c.tints.append(((x0 + x1) / 2, y, zl, 0.5, WOOD, "cladding_patch"))
    L = math.hypot(x1 - x0, z1 - z0)
    ang = math.atan2(z1 - z0, x1 - x0)
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    for s in (-1, 1):
        c.m.box((cx, y + 0.055, cz), (L, 0.04, 0.16), "cladding_patch", rot=(0, -s * ang, 0))
    nail(c, cx, y + 0.075, cz)
    c.dirty.append((cx, y, z0, (x1 - x0) * 0.5, 0.35))


STYLES = [planks, plywood, sheet, braced, planks, plywood]


def barricade_door(c, x, z0, w, h, y):
    """Door closed with cross rails and boards, a hasp, chain and padlock; leaves the step and canopy alone."""
    x0, x1 = x - w / 2 - 0.04, x + w / 2 + 0.04
    zl, zh = z0 + 0.12, z0 + h
    yy = y + 0.05
    for i in range(int((zh - zl) / 0.2)):
        a = zl + i * 0.2
        bx(c, x0 - c.r(0, 0.05), x1 + c.r(0, 0.05), yy, yy + 0.04, a + 0.01, a + 0.19, "cladding_patch")
        c.tints.append((x, yy, a, 0.5, WOOD, "cladding_patch"))
    for zb in (zl + 0.3, zh - 0.3):
        bx(c, x0 - 0.1, x1 + 0.1, yy + 0.04, yy + 0.08, zb - 0.05, zb + 0.05, "steel_structure")
    bx(c, x1 - 0.12, x1 + 0.0, yy + 0.08, yy + 0.1, z0 + 1.0, z0 + 1.25, "equipment_steel")           # hasp
    c.m.box((x1 - 0.06, yy + 0.13, z0 + 0.93), (0.07, 0.04, 0.1), "equipment_steel", bevel=0.01)      # padlock
    for k in range(5):
        c.m.cyl((x1 - 0.06, yy + 0.1, z0 + 1.0 - k * 0.03), (x1 - 0.06, yy + 0.1, z0 + 0.98 - k * 0.03), 0.012, 0.012, "steel_structure", seg=4, smooth=False)
    c.dirty.append((x, y, z0, w * 0.9, 0.4))
    c.drips.append((x, y, zh, w * 0.5, 0.5))
    c.entrance("barricaded_door", x, y, w, h, z0)


def boards(name):
    c = R.new_ctx("boards_" + name, 12.0, 12.0)
    found = panes(name)
    count = 0
    for i, (x0, x1, z0, z1, gy) in enumerate(found):
        y = gy + 0.14
        style = STYLES[(i * 7 + int(x0 * 3)) % len(STYLES)]
        if z0 > 0.5 or (i % 3 != 2):
            style(c, x0 - 0.02, x1 + 0.02, z0 - 0.02, z1 + 0.02, y)
            count += 1
    doors = DOORS[name]
    for (x, z0, w, h, yw) in doors:
        barricade_door(c, x, z0, w, h, yw)
    return c, {"family": name, "windows_found": len(found), "windows_boarded": count, "doors_barricaded": len(doors)}
