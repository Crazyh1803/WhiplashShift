"""Detail overlays for the two confirmed landmarks (exchange_hall, pump_citadel). The original CityKit GLBs stay byte-identical: this builds a second,
library-textured mesh in the SAME local frame (Blender Z-up, front +Y) that is drawn with the same transform. Every fixture is snapped onto the real
surface with BVH ray casts against the imported original, so plates never hover or sink, and the whole overlay is clamped inside the original AABB
(no new protrusion: road clearance and reservations of the placed landmark stay valid).

Exchange hall: dock bumpers, levelling plates and wicket gates under the five bays, weld seams, access panels, louvres, cable trays and lamp cages on
the steel wall, silo ladders/platforms/manways/valves, chimney ladders and aviation bands, roof rails and plant, apron drainage and bollards.
Pump citadel: heavy double entrance doors with canopy and stair, shell seams with rivet lines, a caged access ladder to the catwalk, tank manways,
ladders and gauges, manifold valve wheels and gauges, conduit risers, bolt rings and a roof hatch.
"""
import math
import os

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import city_roadside_common as R
import city_realism_parts as P

V = Vector
bx = P.bx
KIT = os.path.join(R.ROOT, "godot", "assets", "city", "kit")


class Hull:
    """Original landmark geometry (read only) for ray snapping."""

    def __init__(self, name):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(KIT, name + ".glb"))
        verts, polys = [], []
        for o in [o for o in bpy.data.objects if o not in before]:
            if o.type == "MESH":
                o.data.calc_loop_triangles()
                base = len(verts)
                verts += [o.matrix_world @ v.co for v in o.data.vertices]
                polys += [tuple(base + i for i in t.vertices) for t in o.data.loop_triangles]
        for o in [o for o in bpy.data.objects if o not in before]:
            bpy.data.objects.remove(o)
        self.tree = BVHTree.FromPolygons(verts, polys)
        self.low = V((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
        self.high = V((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))

    def cast(self, origin, direction, dist=120.0):
        loc, nrm, _, _ = self.tree.ray_cast(V(origin), V(direction).normalized(), dist)
        return loc

    def front(self, x, z, y0=40.0):
        h = self.cast((x, y0, z), (0, -1, 0))
        return None if h is None else h.y

    def side(self, sign, y, z):
        h = self.cast((sign * 70.0, y, z), (-sign, 0, 0))
        return None if h is None else h.x

    def top(self, x, y, z0=80.0):
        h = self.cast((x, y, z0), (0, 0, -1))
        return None if h is None else h.z

    def radial(self, cx, cy, ang, z, far=40.0):
        h = self.cast((cx + math.cos(ang) * far, cy + math.sin(ang) * far, z), (-math.cos(ang), -math.sin(ang), 0))
        return None if h is None else h

    def clamp(self, c):
        for v in c.m.bm.verts:
            v.co.x = min(max(v.co.x, self.low.x), self.high.x)
            v.co.y = min(max(v.co.y, self.low.y), self.high.y)
            v.co.z = min(max(v.co.z, self.low.z), self.high.z)


# ------------------------------------------------------------------------------------------------ fixtures
def front_plate(c, H, x0, x1, z0, z1, t, mat, lift=0.0):
    """Thin plate on the front wall: y = highest wall hit over the plate + lift."""
    hits = [H.front(x, z) for x in (x0, (x0 + x1) / 2, x1) for z in (z0, (z0 + z1) / 2, z1)]
    hits = [h for h in hits if h is not None]
    if not hits:
        return None
    y = max(hits) + lift
    bx(c, x0, x1, y - 0.02, y + t, z0, z1, mat)
    return y


def bolts_front(c, y, x0, x1, z0, z1, step=0.4, r=0.025, t=0.05):
    x = x0 + 0.08
    while x < x1:
        for z in (z0 + 0.08, z1 - 0.08):
            P.cyly(c, x, y, y + t, z, r, "equipment_steel", seg=5)
        x += step


def valve_wheel(c, x, y, z, axis="y", r=0.22):
    """Gate valve: body, bonnet, stem and a spoked hand wheel."""
    if axis == "y":
        P.cyly(c, x, y - 0.12, y + 0.12, z, 0.11, "equipment_steel", seg=8)
        P.cyly(c, x, y + 0.12, y + 0.4, z, 0.03, "steel_structure", seg=5)
        P.cyly(c, x, y + 0.38, y + 0.42, z, r, "cladding_patch", seg=14)
        P.cyly(c, x, y + 0.36, y + 0.44, z, r * 0.2, "steel_structure", seg=6)
        P.cylx(c, x - r, x + r, y + 0.4, z, 0.014, "steel_structure", seg=4)
        P.cylv(c, x, y + 0.4, z - r, z + r, 0.014, "steel_structure", seg=4)
    else:
        P.cylx(c, x - 0.12, x + 0.12, y, z, 0.11, "equipment_steel", seg=8)
        P.cylv(c, x, y, z + 0.1, z + 0.4, 0.03, "steel_structure", seg=5)
        P.cylv(c, x, y, z + 0.38, z + 0.42, r, "cladding_patch", seg=14)


def gauge(c, x, y, z, r=0.13):
    P.cyly(c, x, y, y + 0.09, z, r, "equipment_steel", seg=12)
    P.cyly(c, x, y + 0.09, y + 0.1, z, r * 0.82, "lamp_glass", seg=12)
    P.cylv(c, x, y + 0.02, z - r - 0.2, z - r, 0.02, "steel_structure", seg=5)


def lamp_cage(c, x, y, z):
    bx(c, x - 0.12, x + 0.12, y, y + 0.05, z - 0.12, z + 0.12, "steel_structure")
    bx(c, x - 0.1, x + 0.1, y + 0.05, y + 0.28, z - 0.1, z + 0.1, "lamp_glass")
    for sx in (-0.11, 0.11):
        for sz in (-0.11, 0.11):
            P.cyly(c, x + sx, y + 0.04, y + 0.3, z + sz, 0.01, "steel_structure", seg=4)
    bx(c, x - 0.14, x + 0.14, y + 0.28, y + 0.32, z - 0.14, z + 0.14, "steel_structure")


def caged_ladder(c, x, y, z0, z1, face=1, cage_from=2.2):
    """Wall ladder in +y (face=1) or radial sign; rungs every 0.3 m, hoops with vertical bars above cage_from."""
    P.ladder(c, x, y, z0, z1, 0.5)
    z = z0 + cage_from
    while z < z1 - 0.4:
        for k in range(8):
            a = math.pi * (k / 7.0)
            px, py = x + 0.42 * math.cos(a) * 0.9, y + face * (0.05 + 0.42 * math.sin(a))
            P.cylv(c, px, py, z, z + 0.02, 0.012, "steel_structure", seg=4)
        z += 0.9
    for k in range(7):
        a = math.pi * (k / 6.0)
        P.cylv(c, x + 0.38 * math.cos(a), y + face * (0.05 + 0.38 * math.sin(a)), z0 + cage_from, z1 - 0.4, 0.008, "steel_structure", seg=4)


def manway(c, x, y, z, nx, ny, r=0.32):
    """Round manhole cover with bolt circle on a surface whose outward normal is (nx, ny)."""
    ang = math.atan2(ny, nx)
    p = V((x, y, z))
    n = V((nx, ny, 0))
    c.m.cyl(p, p + n * 0.1, r * 1.25, r * 1.25, "steel_structure", seg=14, smooth=False)
    c.m.cyl(p + n * 0.1, p + n * 0.14, r, r, "equipment_steel", seg=14, smooth=False)
    t = V((-ny, nx, 0))
    for k in range(10):
        a = 2 * math.pi * k / 10
        q = p + n * 0.12 + t * (math.cos(a) * r * 1.08) + V((0, 0, math.sin(a) * r * 1.08))
        c.m.cyl(q, q + n * 0.04, 0.02, 0.02, "equipment_steel", seg=5, smooth=False)
    c.m.cyl(p + n * 0.14 + V((0, 0, r * 0.1)), p + n * 0.3 + V((0, 0, r * 0.1)), 0.03, 0.03, "steel_structure", seg=5)
    c.dirty.append((x, y, z - r, 0.9, 0.35))


def bolt_ring(c, cx, cy, z, r, n, rb=0.035):
    for k in range(n):
        a = 2 * math.pi * k / n
        P.cylv(c, cx + r * math.cos(a), cy + r * math.sin(a), z, z + 0.12, rb, "equipment_steel", seg=6)
        P.cylv(c, cx + r * math.cos(a), cy + r * math.sin(a), z + 0.05, z + 0.09, rb * 1.7, "equipment_steel", seg=6)


def seam_ring(c, cx, cy, z, r, thick=0.06, seg=28, mat="steel_structure"):
    c.m.cyl((cx, cy, z), (cx, cy, z + 0.1), r + thick, r + thick, mat, seg=seg, smooth=False)


def conduit_run(c, pts, r=0.03):
    P.pipe_run(c, [V(p) for p in pts], r, "equipment_steel", seg=6)
    for a, b in zip(pts, pts[1:]):
        L = (V(b) - V(a)).length
        n = max(1, int(L / 1.4))
        for i in range(n + 1):
            q = V(a) + (V(b) - V(a)) * (i / n)
            c.m.cyl(q - V((0, 0.0, 0)) , q + V((0, 0.05, 0)), r * 1.8, r * 1.8, "steel_structure", seg=5, smooth=False)


# ================================================================================================ exchange hall
def exchange_hall():
    H = Hull("exchange_hall")
    c = R.new_ctx("exchange_hall_detail", 58.0, 28.0)
    rng = c.rng
    # --- dock front: five bays between 1.2 m piers (ox = -16.4 + i * 6.8, width 5.6) ----------------------------------------------------
    for i in range(5):
        ox = -17.6 + 1.2 + i * 6.8
        # dock levelling plate with hazard lip, bumpers, floor drain
        bx(c, ox + 0.5, ox + 5.1, 12.6, 13.9, 0.8, 0.88, "steel_structure")
        P.hazard_stripe(c, ox + 0.5, ox + 5.1, 13.9, 0.8, 0.88, 10) if False else None
        for k in range(10):
            bx(c, ox + 0.5 + k * 0.46, ox + 0.5 + k * 0.46 + 0.23, 13.88, 13.94, 0.8, 0.9, "cladding_patch")
        for bxp in (ox + 0.25, ox + 5.35):
            bx(c, bxp - 0.17, bxp + 0.17, 13.45, 13.95, 1.25, 2.05, "plastic_rubber")
            bx(c, bxp - 0.19, bxp + 0.19, 13.4, 13.45, 1.2, 2.1, "steel_structure")
            P.bollard(c, bxp, 13.65, 0.8, 1.0, 0.1)
        # control box with cable run and a light cage
        front_plate(c, H, ox - 1.05, ox - 0.65, 2.4, 3.2, 0.12, "equipment_steel")
        lamp_cage(c, ox + 2.8, front(H, ox + 2.8, 8.4, 13.0), 8.55)
        conduit_run(c, [(ox - 0.9, 13.0, 3.2), (ox - 0.9, 13.0, 8.8)], 0.025)
        if i in (1, 3):                                                   # wicket gate in the shutter
            fy = H.front(ox + 0.7, 1.5, 13.4) or 12.1
            wy = fy + 0.04
            bx(c, ox + 0.3, ox + 1.5, wy, wy + 0.05, 0.9, 2.9, "steel_structure")
            bx(c, ox + 0.38, ox + 1.42, wy + 0.05, wy + 0.07, 0.98, 2.82, "cladding_corrugated")
            bx(c, ox + 1.2, ox + 1.28, wy + 0.07, wy + 0.14, 1.7, 1.95, "equipment_steel")
            bx(c, ox + 0.38, ox + 1.42, wy + 0.05, wy + 0.07, 1.8, 2.3, "glass_window")
            c.entrance("wicket", ox + 0.9, wy, 1.0, 2.0, 0.9)
            bx(c, ox + 0.25, ox + 1.55, wy, wy + 0.5, 0.8, 0.95, "concrete")
        else:
            bx(c, ox + 0.1, ox + 0.5, 12.5, 12.8, 0.9, 6.2, "steel_structure")           # shutter guide reinforcement
        c.dirty.append((ox + 2.8, 13.5, 0.8, 2.6, 0.45))
    for i in range(6):                                                    # pier faces: id plates and downpipes
        px = -17.6 + i * 6.8 + 0.6
        y = front(H, px, 5.0, 13.5)
        P.cylv(c, px + (0.45 if i < 5 else -0.45), y + 0.07, 0.9, 9.3, 0.05, "equipment_steel", seg=8)
        P.junction_box(c, px, y + 0.02, 4.4, 0.34, 0.45, 0.12)
        c.drips.append((px, y, 9.3, 0.3, 0.55))
    # --- ceramic fascia and steel wall ----------------------------------------------------------------------------------------------------
    for k, x in enumerate((-12.0, 0.0, 12.0)):
        if front_plate(c, H, x - 1.5, x + 1.5, 9.8, 10.6, 0.06, "sign_atlas") is not None:
            set_sign(c, (3, 6, 12)[k])
    # steel wall x -19.6..19.6, z 11.6..16.5: seams, stiffeners, access panels, louvres, cable tray
    for zz in (12.1, 14.2, 16.0):
        y = H.front(0.0, zz + 0.1) or 12.0
        bx(c, -19.7, 19.7, y - 0.02, y + 0.07, zz, zz + 0.09, "steel_structure")
    for x in [-19.5 + 2.5 * k for k in range(17)]:
        for zc in (13.1, 15.2):
            y = H.front(x, zc)
            if y is None or y > 12.2:
                continue
            bx(c, x - 0.04, x + 0.04, y - 0.02, y + 0.08, zc - 1.0, zc + 1.0, "steel_structure")
            bolts_front(c, y + 0.08, x - 0.04, x + 0.04, zc - 1.0, zc + 1.0, 0.5, 0.02, 0.03)
    for (x, zc, w, h) in ((-9.0, 14.3, 1.5, 1.7), (3.0, 13.2, 1.3, 1.5), (14.0, 14.8, 1.8, 1.4)):
        y = H.front(x, zc) or 12.0
        if y > 12.2:
            continue
        bx(c, x - w / 2, x + w / 2, y - 0.02, y + 0.1, zc - h / 2, zc + h / 2, "cladding_patch")
        bolts_front(c, y + 0.1, x - w / 2, x + w / 2, zc - h / 2, zc + h / 2, 0.35, 0.022, 0.03)
        c.drips.append((x, y, zc - h / 2, w * 0.4, 0.5))
    for (x, zc) in ((-5.0, 15.7), (9.0, 12.7), (-15.0, 12.7)):
        y = H.front(x, zc) or 12.0
        if y > 12.2:
            continue
        bx(c, x - 0.6, x + 0.6, y - 0.02, y + 0.12, zc - 0.5, zc + 0.5, "steel_structure")
        for k in range(7):
            bx(c, x - 0.52, x + 0.52, y + 0.1, y + 0.2, zc - 0.44 + k * 0.145, zc - 0.36 + k * 0.145, "equipment_steel")
    conduit_run(c, [(-19.0, 12.12, 16.4), (19.0, 12.12, 16.4)], 0.03)
    conduit_run(c, [(-19.0, 12.12, 11.9), (19.0, 12.12, 11.9)], 0.04)
    # --- apron: drainage channel, expansion joints, kerbs, bollards, tyres and pallets ----------------------------------------------------
    bx(c, -26.0, 26.0, 13.55, 13.7, 0.8, 0.84, "plastic_rubber")
    for k in range(52):
        bx(c, -26.0 + k, -26.0 + k + 0.6, 13.56, 13.68, 0.84, 0.86, "steel_structure")
    for xx in (-27.0, -21.0, 21.0, 27.0):
        P.bollard(c, xx, 13.4, 0.8, 1.1, 0.12)
    P.tyre_stack(c, 28.0, 12.6, 0.8, 3)
    P.pallet(c, -24.5, 12.0, 0.8)
    P.crate_stack(c, -23.0, 11.2, 0.8, 2, 2)
    # --- silos (three at x=-24.6) -------------------------------------------------------------------------------------------------------
    for (y, r, h) in ((-8.0, 3.0, 15.5), (-1.0, 3.0, 12.5), (6.0, 3.0, 10.0)):
        x = -24.6
        z0 = 0.8
        bolt_ring(c, x, y, z0 + 0.9, r + 0.25, 12)
        for zz in (2.5, h * 0.35, h * 0.7):
            seam_ring(c, x, y, z0 + zz, r + 0.02, 0.035, 20)
        manway(c, x - (r + 0.0), y + 0.0, z0 + 1.9, -1.0, 0.0, 0.3)
        caged_ladder(c, x - 1.4, y + r + 0.12, z0, z0 + h + 0.6, 1, 2.4)
        # platform ring near the roof with toe board and rail
        zp = z0 + h - 0.8
        c.m.cyl((x, y, zp), (x, y, zp + 0.06), r + 0.65, r + 0.65, "steel_structure", seg=20, smooth=False)
        c.m.cyl((x, y, zp - 0.2), (x, y, zp), r + 0.02, r + 0.55, "steel_structure", seg=20, smooth=False)
        for k in range(14):
            a = 2 * math.pi * k / 14
            P.cylv(c, x + (r + 0.6) * math.cos(a), y + (r + 0.6) * math.sin(a), zp + 0.06, zp + 1.05, 0.02, "steel_structure", seg=5)
        R.tube_ring(c, x, y, zp + 1.07, r + 0.61, 0.02, 20, "steel_structure")
        R.tube_ring(c, x, y, zp + 0.565, r + 0.61, 0.02, 20, "steel_structure")
        # level gauge, flange valves on the outlet pipe at 0.4 h
        zv = z0 + h * 0.4
        for k in range(3):
            P.cylv(c, x + r + 0.06, y - 0.9 + k * 0.0, z0 + 1.2, z0 + h * 0.7, 0.025, "steel_structure", seg=5) if k == 0 else None
        gauge(c, x + r * 0.95, y - 1.2, z0 + 2.6)
        valve_wheel(c, -22.4, y, zv + 0.02, "x")
        P.cylx(c, -22.8, -22.0, y, zv, 0.36, "steel_structure", seg=10)
        c.dirty.append((x, y, zv, 1.2, 0.35))
    # --- chimney stacks at (24, 8.5) and (24, 12) -------------------------------------------------------------------------------------
    for sy in (8.5, 12.0):
        for zz in (3.5, 8.5):
            seam_ring(c, 24.0, sy, 0.8 + zz, 1.42 - zz * 0.02, 0.03, 18)
        for k in range(3):
            zb = 0.8 + 14.0 + k * 1.8
            seam_ring(c, 24.0, sy, zb, 1.04 - 0.0, 0.05, 18, "fabric_awning" if k % 2 == 0 else "render_plaster")
        caged_ladder(c, 24.0 + 0.4, sy - 1.05, 0.8, 18.0, -1, 2.4)
        bolt_ring(c, 24.0, sy, 0.8, 1.9, 10)
    # --- roof plant: handrail on the ceramic parapet, vents and hvac between trusses ---------------------------------------------------------
    P.railing(c, -20.0, 20.0, 13.3, 17.2, 0.9, 1.6)
    P.railing(c, -20.0, 20.0, -13.3, 17.2, 0.9, 1.6)
    for k, xx in enumerate((-13.0, -4.0, 6.0, 14.5)):
        P.vent_stack(c, xx, 12.2 if k % 2 == 0 else -11.8, 17.2, 0.9, 0.14)
    P.hvac_box(c, 8.0, -4.0, 17.2, 1.8, 1.1, 0.9)
    conduit_run(c, [(-18.0, -9.0, 17.3), (-18.0, 9.0, 17.3)], 0.04)
    # --- transformer wings: guard rail, hazard plate, valves ---------------------------------------------------------------------------
    for y in (-8.5, -2.5, 3.5):
        P.fence_panel(c, 21.0, 21.001, y - 1.9, 0.8, 1.2, 2.0) if False else None
        bx(c, 21.1, 25.4, y + 1.9, y + 2.0, 0.8, 1.2, "steel_structure")
        P.hazard_stripe(c, 21.1, 25.4, y + 2.0, 0.8, 1.0, 10)
        gauge(c, 22.0, y + 1.95, 3.4) if False else None
    H.clamp(c)
    return c, {"source_glb": "godot/assets/city/kit/exchange_hall.glb", "source_aabb": [[H.low.x, H.low.z, -H.high.y], [H.high.x, H.high.z, -H.low.y]]}


def front(H, x, z, default):
    y = H.front(x, z)
    return default if y is None else y


# ================================================================================================ pump citadel
def pump_citadel():
    H = Hull("pump_citadel")
    c = R.new_ctx("pump_citadel_detail", 36.0, 36.0)
    cx, cy, r0, zb = 0.0, -2.0, 10.5, 0.9
    # --- shell: vertical seams with rivet lines between the 14 buttresses, horizontal weld rings, stair-access ladder to the catwalk -------
    for k in range(28):
        a = 2 * math.pi * (k + 0.25) / 28
        hit = H.radial(cx, cy, a, 12.0)
        if hit is None:
            continue
        rr = V((hit.x - cx, hit.y - cy, 0)).length
        if rr < 10.3 or rr > 11.0:
            continue                                                # a buttress or fitting sits here
        p = V((hit.x, hit.y, 0))
        n = V((math.cos(a), math.sin(a), 0))
        tvec = V((-n.y, n.x, 0))
        for zc, h in ((9.5, 4.4), (13.7, 3.4), (18.6, 4.6)):
            q = p + n * 0.04
            c.m.box((q.x, q.y, zb + zc), (0.1, 0.16, h), "steel_structure", rot=(0, 0, a))
            for rz in range(int(h / 0.45)):
                for sgn in (-1, 1):
                    qq = q + n * 0.055 + tvec * (sgn * 0.12)
                    c.m.cyl(V((qq.x, qq.y, zb + zc - h / 2 + 0.2 + rz * 0.45)), V((qq.x, qq.y, zb + zc - h / 2 + 0.2 + rz * 0.45)) + n * 0.03, 0.022, 0.022, "equipment_steel", seg=5, smooth=False)
    for zz in (5.5, 11.2, 20.0):
        rr = H.radial(cx, cy, 0.3, zb + zz)
        if rr is not None:
            seam_ring(c, cx, cy, zb + zz, V((rr.x - cx, rr.y - cy, 0)).length, 0.04, 28)
    # access ladder with cage up to the catwalk ring (z 16) at angle 130 degrees, plus a gated landing
    a = math.radians(130)
    hit = H.radial(cx, cy, a, 12.0)
    if hit is not None:
        n = V((math.cos(a), math.sin(a), 0))
        base = V((hit.x, hit.y, 0)) + n * 0.5
        for sgn in (-1, 1):
            tvec = V((-n.y, n.x, 0))
            p0 = base + tvec * (sgn * 0.25)
            c.m.cyl(V((p0.x, p0.y, 0.0)), V((p0.x, p0.y, 16.2)), 0.03, 0.03, "steel_structure", seg=5, smooth=False)
        for k in range(int(15.8 / 0.3)):
            q = base + V((0, 0, 0.35 + k * 0.3))
            tvec = V((-n.y, n.x, 0))
            c.m.cyl(q - tvec * 0.25, q + tvec * 0.25, 0.012, 0.012, "steel_structure", seg=4, smooth=False)
        zc = 2.4
        while zc < 15.6:
            for kk in range(8):
                ang = math.pi * kk / 7.0
                tvec = V((-n.y, n.x, 0))
                q = base + n * (0.4 * math.sin(ang)) + tvec * (0.4 * math.cos(ang)) + V((0, 0, zc))
                c.m.cyl(q, q + V((0, 0, 0.02)), 0.012, 0.012, "steel_structure", seg=4, smooth=False)
            zc += 0.9
        for kk in range(7):
            ang = math.pi * kk / 6.0
            tvec = V((-n.y, n.x, 0))
            q = base + n * (0.38 * math.sin(ang)) + tvec * (0.38 * math.cos(ang))
            c.m.cyl(q + V((0, 0, 2.4)), q + V((0, 0, 15.6)), 0.008, 0.008, "steel_structure", seg=4, smooth=False)
    # --- roof: hatch, vents and a rod ------------------------------------------------------------------------------------------------------
    zt = H.top(2.2, -2.0) or 28.0
    manway(c, 2.0, -2.0, zt + 0.35, 0.0, 0.0, 0.5) if False else None
    c.m.cyl((2.4, -3.5, zt - 0.1), (2.4, -3.5, zt + 0.7), 0.7, 0.55, "equipment_steel", seg=10, smooth=False)
    c.m.cyl((2.4, -3.5, zt + 0.7), (2.4, -3.5, zt + 0.8), 0.78, 0.78, "steel_structure", seg=10, smooth=False)
    # --- six tanks ---------------------------------------------------------------------------------------------------------------------------
    tanks = [(-13.0, 8.0, 3.8, 14.0), (-7.2, 14.0, 3.4, 11.0), (7.2, 14.0, 3.4, 16.0), (13.0, 8.0, 3.8, 12.0), (-13.5, -10.0, 3.2, 9.5), (13.5, -10.0, 3.2, 10.5)]
    for k, (tx, ty, tr, th) in enumerate(tanks):
        bolt_ring(c, tx, ty, 0.9, tr + 0.2, 14)
        a = math.atan2(ty + 2.0, tx)
        n = V((math.cos(a), math.sin(a), 0))
        for zz in (th * 0.28, th * 0.62):
            seam_ring(c, tx, ty, 0.9 + zz, tr + 0.03, 0.04, 20)
        manway(c, tx + n.x * (tr - 0.02), ty + n.y * (tr - 0.02), 1.8, n.x, n.y, 0.34)
        # ladder with cage on the side facing away from the shell
        ang2 = a + math.pi * 0.62
        lx, ly = tx + (tr + 0.1) * math.cos(ang2), ty + (tr + 0.1) * math.sin(ang2)
        top = 0.9 + th
        base = V((lx, ly, 0.9))
        nrm = V((math.cos(ang2), math.sin(ang2), 0))
        tv = V((-nrm.y, nrm.x, 0))
        for sgn in (-1, 1):
            q = base + tv * (sgn * 0.22)
            c.m.cyl(q, q + V((0, 0, th + 0.8)), 0.025, 0.025, "steel_structure", seg=5, smooth=False)
        for j in range(int((th + 0.4) / 0.3)):
            q = base + V((0, 0, 0.3 + j * 0.3)) + nrm * 0.03
            c.m.cyl(q - tv * 0.22, q + tv * 0.22, 0.011, 0.011, "steel_structure", seg=4, smooth=False)
        for j in range(int((th - 1.5) / 1.0)):
            for kk in range(7):
                ang = math.pi * kk / 6.0
                q = base + nrm * (0.38 * math.sin(ang) + 0.05) + tv * (0.38 * math.cos(ang)) + V((0, 0, 2.4 + j * 1.0))
                c.m.cyl(q, q + V((0, 0, 0.02)), 0.011, 0.011, "steel_structure", seg=4, smooth=False)
        # rim rail on the roof, vent and gauge glass
        for kk in range(10):
            ang = 2 * math.pi * kk / 10
            P.cylv(c, tx + (tr - 0.35) * math.cos(ang), ty + (tr - 0.35) * math.sin(ang), top + 0.3, top + 1.2, 0.02, "steel_structure", seg=5)
        R.tube_ring(c, tx, ty, top + 1.22, tr - 0.33, 0.02, 14, "steel_structure")
        gauge(c, tx + n.x * (tr + 0.02), ty + n.y * (tr + 0.02), 3.4) if False else None
        P.cylv(c, tx + n.x * (tr + 0.08), ty + n.y * (tr + 0.08), 1.5, th * 0.55, 0.022, "lamp_glass", seg=5)
        c.dirty.append((tx, ty, 1.0, 2.8, 0.3))
    # --- manifold block (x -5..5, y 10..11.2, z 2.5..3.9): valve wheels, gauges, flange studs -----------------------------------------------
    for i, xx in enumerate((-4.2, -2.1, 0.0, 2.1, 4.2)):
        valve_wheel(c, xx, 11.2, 3.2, "y", 0.24)
        gauge(c, xx + 0.9, 11.25, 3.55)
        bolt_ring(c, xx, 10.6, 3.88, 0.4, 6, 0.02)
    P.junction_box(c, -4.8, 11.3, 2.6, 0.4, 0.5, 0.14)
    conduit_run(c, [(-4.8, 11.35, 3.1), (-4.8, 11.35, 5.5), (4.8, 11.35, 5.5)], 0.03)
    # --- entrance block (x -4..4, y 10.6..14.4): heavy double doors, canopy, stair, hazard apron, address plate ----------------------------
    yb = H.front(0.0, 2.5) or 12.3                              # cavity back wall
    dy = yb + 0.05
    for sgn in (-1, 1):
        x0, x1 = (-1.9, -0.03) if sgn < 0 else (0.03, 1.9)
        bx(c, x0, x1, dy, dy + 0.1, 0.95, 4.35, "steel_structure")
        bx(c, x0 + 0.12, x1 - 0.12, dy + 0.1, dy + 0.13, 1.05, 4.25, "cladding_corrugated")
        bx(c, x0 + 0.12, x1 - 0.12, dy + 0.13, dy + 0.15, 2.4, 3.4, "glass_window")
        bx(c, (x0 + x1) / 2 - 0.2, (x0 + x1) / 2 + 0.2, dy + 0.15, dy + 0.17, 1.05, 1.5, "cladding_patch")
        for hz in (1.8, 3.6):
            bx(c, x0, x1, dy + 0.1, dy + 0.18, hz, hz + 0.08, "steel_structure")
        bx(c, -0.34 * sgn - 0.04 - (0.0 if sgn > 0 else 0.0), -0.34 * sgn + 0.04, dy + 0.15, dy + 0.3, 1.9, 2.5, "equipment_steel")
    bx(c, -1.95, 1.95, dy, dy + 0.14, 4.35, 4.5, "steel_structure")
    c.entrance("double_door", 0.0, dy, 3.8, 3.4, 0.95)
    c.polish.append((0.34, dy, 2.1, 0.3))
    lp = front(H, -2.6, 3.4, 13.9)
    lamp_cage(c, -2.55, lp, 4.0)
    lamp_cage(c, 2.55, lp, 4.0)
    # threshold apron and stair in the pocket in front of the doors (all snapped to the cavity face)
    bx(c, -2.1, 2.1, dy + 0.1, dy + 1.5, 0.9, 1.0, "concrete")
    bx(c, -2.3, 2.3, dy + 1.5, dy + 2.0, 0.9, 1.0, "steel_structure")
    P.hazard_stripe(c, -2.1, 2.1, dy + 2.0, 0.9, 1.0, 12)
    P.railing(c, -3.4, -2.5, dy + 1.7, 0.9, 1.0, 0.9)
    P.railing(c, 2.5, 3.4, dy + 1.7, 0.9, 1.0, 0.9)
    P.bollard(c, -3.7, dy + 1.8, 0.9, 1.1, 0.12)
    P.bollard(c, 3.7, dy + 1.8, 0.9, 1.1, 0.12)
    y_s = H.front(0.0, 6.9) or 14.0
    bx(c, -1.4, 1.4, y_s, y_s + 0.1, 6.0, 6.7, "steel_structure")
    bx(c, -1.3, 1.3, y_s + 0.1, y_s + 0.12, 6.05, 6.65, "sign_atlas")
    set_sign(c, 5)
    gauge(c, 3.4, y_s, 5.8)
    conduit_run(c, [(-3.4, y_s + 0.05, 1.0), (-3.4, y_s + 0.05, 7.0)], 0.03)
    # --- pipe supports along the tank feeds -----------------------------------------------------------------------------------------------------------
    for (tx, ty, tr, th), z in zip(tanks[:4], (4.0, 5.4, 5.4, 4.0)):
        tgt = tx * 0.62
        for t in (0.25, 0.55, 0.85):
            xs = tx + (tgt - tx) * t
            c.m.cyl((xs, ty, 0.9), (xs, ty, z - 0.34), 0.07, 0.07, "steel_structure", seg=6, smooth=False)
            bx(c, xs - 0.3, xs + 0.3, ty - 0.1, ty + 0.1, z - 0.4, z - 0.34, "steel_structure")
    H.clamp(c)
    return c, {"source_glb": "godot/assets/city/kit/pump_citadel.glb", "source_aabb": [[H.low.x, H.low.z, -H.high.y], [H.high.x, H.high.z, -H.low.y]]}


def set_sign(c, tile):
    """Point the sign_atlas face just built at atlas tile `tile`."""
    import city_realism_textures as T
    for f in list(c.m.bm.faces)[-12:]:
        if c.m.mats[f.material_index] == "sign_atlas" and abs(f.normal.y - 1.0) < 0.2:
            c.m.explicit.add(f)
            u0, v0, u1, v1 = T.sign_tile_uv(tile)
            xs = sorted({round(l.vert.co.x, 4) for l in f.loops})
            zs = sorted({round(l.vert.co.z, 4) for l in f.loops})
            for lp in f.loops:
                sx = 1 - (lp.vert.co.x - xs[0]) / max(xs[-1] - xs[0], 1e-6)
                sz = (lp.vert.co.z - zs[0]) / max(zs[-1] - zs[0], 1e-6)
                lp[c.m.uv].uv = (u0 + (u1 - u0) * sx, v0 + (v1 - v0) * sz)


def landmark(name):
    return exchange_hall() if name == "exchange_hall" else pump_citadel()
