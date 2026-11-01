"""Two detailed roadside skyscrapers. Building convention of the realism library: facade plane y=0 at the front, x centred, the lot extends to -y
(Blender Z-up; glTF front -Z). Every face is built in its own local frame with the realism helpers (P.window / P.wall / P.awning ...) and moved
onto the block with `on_face`, so podiums, shafts and rear faces share one detailed vocabulary. The lower floors carry full detail; repeated upper
floors use a cheaper window module; LOD1 is a separate massing with floor bands for distance only.

    tower_a  "Ledger Tower": brick and plaster, two-step setback shaft, arcaded shop podium, external fire stair, tank and mast crown (24 x 20 m, ~60 m)
    tower_b  "Brace Tower": corrugated steel twin shafts with X bracing and skybridges over a loading-bay podium, drum and mast crown (22 x 18 m, ~64 m)
"""
import math

import bmesh
from mathutils import Matrix, Vector

import city_roadside_common as R
import city_realism_parts as P

V = Vector
bx = P.bx
INSET = 0.18


def on_face(c, origin, yaw, fn):
    """Run fn() (builds in a local frame: plane y=0, outward +y, x along the face) and move the new geometry and bookkeeping onto the block."""
    bm = c.m.bm
    old = len(bm.verts)
    marks = (len(c.drips), len(c.dirty), len(c.polish), len(c.entrances), len(c.signs), len(c.anchors))
    fn()
    bm.verts.ensure_lookup_table()
    new = [bm.verts[i] for i in range(old, len(bm.verts))]
    M = Matrix.Translation(origin) @ Matrix.Rotation(yaw, 4, "Z")
    bmesh.ops.transform(bm, matrix=M, verts=new)

    def mp(x, y, z):
        q = M @ V((x, y, z))
        return q.x, q.y, q.z
    for i in range(marks[0], len(c.drips)):
        x, y, z, w, s = c.drips[i]
        qx, qy, qz = mp(x, y, z)
        c.drips[i] = (qx, qy, qz, w, s)
    for i in range(marks[1], len(c.dirty)):
        x, y, z, r, s = c.dirty[i]
        qx, qy, qz = mp(x, y, z)
        c.dirty[i] = (qx, qy, qz, r, s)
    for i in range(marks[2], len(c.polish)):
        x, y, z, r = c.polish[i]
        qx, qy, qz = mp(x, y, z)
        c.polish[i] = (qx, qy, qz, r)
    for i in range(marks[3], len(c.entrances)):
        e = c.entrances[i]
        e["p"] = mp(*e["p"])
    del c.anchors[marks[5]:]               # the city has a fixed light pool: fixtures here are geometry only


FACES = {"F": (lambda xa, xb, ya, yb: (((xa + xb) / 2, yb, 0.0), 0.0, xb - xa)),
         "L": (lambda xa, xb, ya, yb: ((xa, (ya + yb) / 2, 0.0), math.pi / 2, yb - ya)),
         "R": (lambda xa, xb, ya, yb: ((xb, (ya + yb) / 2, 0.0), -math.pi / 2, yb - ya)),
         "B": (lambda xa, xb, ya, yb: (((xa + xb) / 2, ya, 0.0), math.pi, xb - xa))}


def hull(c, xa, xb, ya, yb, z0, z1, mat):
    bx(c, xa + INSET, xb - INSET, ya + INSET, yb - INSET, z0, z1, mat)


MASONRY = ["brick", "concrete", "render_plaster"]


def podium_hull(c, xa, xb, ya, front, z1, mat):
    """Podium core set BEHIND the facade wall: its front plane is `front` (behind the wall's back face), so every wall opening is a real recess that
    ends in a dark interior panel instead of a solid masonry face."""
    bx(c, xa + INSET, xb - INSET, ya + INSET, front, 0.0, z1, mat)


def dark_interior(c, x0, x1, z0, z1, front):
    """Unlit interior backing for one wall opening, flush with the hull front."""
    bx(c, x0, x1, front, front + 0.04, z0, z1, "plastic_rubber")


def probe(kind, x, z, expect, min_depth):
    """Declared aperture probe (Godot coordinates, ray cast +Z from in front of the facade plane z=0): the FIRST surface hit at (x, z) must be one of
    `expect` (never masonry) and lie at least `min_depth` metres behind the facade plane."""
    return {"kind": kind, "position": [round(x, 3), round(z, 3), 0.0], "expect": expect, "min_depth": min_depth}


def cheap_window(c, x0, x1, z0, z1, y, lit=False, blind=False):
    """Upper-floor window: glass (or a lit pane), head, sill and mullion proud of the wall, ~48 triangles."""
    bx(c, x0, x1, y - 0.2, y - 0.17, z0, z1, "lamp_glass" if lit else "glass_window")
    bx(c, x0 - 0.04, x1 + 0.04, y - 0.2, y + 0.05, z1, z1 + 0.07, "concrete")
    bx(c, x0 - 0.07, x1 + 0.07, y - 0.2, y + 0.13, z0 - 0.07, z0, "concrete")
    bx(c, (x0 + x1) / 2 - 0.02, (x0 + x1) / 2 + 0.02, y - 0.2, y - 0.05, z0, z1, "steel_structure")
    if blind and not lit:
        bx(c, x0 + 0.05, x1 - 0.05, y - 0.17, y - 0.15, z1 - (z1 - z0) * 0.45, z1 - 0.04, "fabric_awning")


def layered_face(c, width, z0, floors, fh, wall_mat, pier_mat, wh=1.55, sill=0.95, detailed_floors=2, pitch=3.1, ac_every=7, lit_every=9, mullion=True):
    """One face in its local frame: continuous spandrel and head bands (proud 0.14), full-height piers (proud 0.26), windows on the recessed plane."""
    cols = max(2, int(round(width / pitch)))
    pw = width / cols
    pier = 0.5
    x0 = -width / 2
    top = z0 + floors * fh
    for k in range(cols + 1):
        xk = x0 + k * pw
        bx(c, xk - pier / 2, xk + pier / 2, -INSET, 0.26, z0, top, pier_mat)
        bx(c, xk - pier / 2 - 0.05, xk + pier / 2 + 0.05, 0.22, 0.30, z0, z0 + 0.5, "concrete")        # pier foot
    for f in range(floors):
        zf = z0 + f * fh
        bx(c, x0, x0 + width, -INSET, 0.14, zf, zf + sill, wall_mat)                                    # spandrel under the window ribbon
        bx(c, x0, x0 + width, -INSET, 0.14, zf + sill + wh, zf + fh, wall_mat)                          # head band
        bx(c, x0, x0 + width, 0.1, 0.2, zf + fh - 0.12, zf + fh, "concrete")                           # floor-edge drip course
        for k in range(cols):
            wx0 = x0 + k * pw + pier / 2 + 0.07
            wx1 = x0 + (k + 1) * pw - pier / 2 - 0.07
            n = f * cols + k
            if f < detailed_floors:
                kind = ["bars", "plain", "blind", "plain", "ac", "shutter"][(n + int(c.r(0, 6))) % 6]
                P.window(c, wx0, wx1, zf + sill, zf + sill + wh, 0.0, kind, "steel_structure", 0.3)
            else:
                cheap_window(c, wx0, wx1, zf + sill, zf + sill + wh, 0.0, lit=(n * 7 + int(c.r(0, 9))) % lit_every == 0, blind=(n % 5 == 2))
                if ac_every and (n * 3 + f) % ac_every == 0:
                    P.ac_unit(c, (wx0 + wx1) / 2, 0.1, zf + sill - 0.58, 0.7)
    bx(c, x0, x0 + width, -INSET, 0.34, top, top + 0.22, "concrete")                                    # cornice
    bx(c, x0 - 0.05, x0 + width + 0.05, 0.1, 0.4, top + 0.22, top + 0.3, "steel_structure")


def block(c, xa, xb, ya, yb, z0, floors, fh, wall_mat, pier_mat, faces="FLRB", detailed=2, **kw):
    top = z0 + floors * fh
    hull(c, xa, xb, ya, yb, z0 - 0.4, top, wall_mat)
    for key in faces:
        origin, yaw, width = FACES[key](xa, xb, ya, yb)
        full = key in "FLR"
        on_face(c, (origin[0], origin[1], 0.0), yaw,
                lambda full=full, width=width: layered_face(c, width, z0, floors, fh, wall_mat, pier_mat,
                                                            detailed_floors=detailed if full else 0, ac_every=7 if full else 0, **kw))
    return top


def roof_kit(c, xa, xb, ya, yb, z, tanks=2, hvac=3, stacks=4, mast=True, ladder_face=True):
    P.parapet(c, xa, xb, yb, ya, z, 0.9, "concrete", 0.3, "roof_membrane", scuppers=((xa + xb) / 2 - 3, (xa + xb) / 2 + 3))
    w, d = xb - xa, yb - ya
    for i in range(hvac):
        P.hvac_box(c, xa + w * (0.2 + 0.26 * i), ya + d * 0.3, z, 1.8, 1.1, 1.0)
    for i in range(tanks):
        P.water_tank(c, xb - w * (0.25 + 0.22 * i), ya + d * 0.72, z, 1.1, 2.0)
    for i in range(stacks):
        P.vent_stack(c, xa + w * (0.15 + 0.2 * i), ya + d * 0.55, z, 1.4 + 0.2 * (i % 2))
    bx(c, xa + w * 0.4, xa + w * 0.62, ya + d * 0.14, ya + d * 0.46, z, z + 2.6, "brick")               # machine room
    bx(c, xa + w * 0.4 - 0.1, xa + w * 0.62 + 0.1, ya + d * 0.14 - 0.1, ya + d * 0.46 + 0.1, z + 2.6, z + 2.75, "concrete")
    P.personnel_door(c, xa + w * 0.51, z, ya + d * 0.46 + 0.1, 1.0, 2.0, lamp=False, canopy=False)
    for k in range(5):
        bx(c, xa + w * 0.42, xa + w * 0.6, ya + d * 0.14 - 0.11, ya + d * 0.14 - 0.06, z + 1.5 + k * 0.17, z + 1.6 + k * 0.17, "steel_structure")
    if mast:
        P.antenna(c, xb - w * 0.1, ya + d * 0.3, z, 7.0)
        P.antenna(c, xa + w * 0.12, ya + d * 0.4, z, 4.5)
    if ladder_face:
        P.ladder(c, xa + 1.0, yb - 0.32, z - 1.6, z + 0.9, 0.5)


def fire_stair(c, x, y, z0, floors, fh, depth=1.0, run=3.6, width=1.0):
    """External steel stair on a side wall: landings at every floor, alternating flights with treads, stringers and rails. Runs along local +x."""
    for f in range(floors):
        zf = z0 + f * fh
        sgn = 1 if f % 2 == 0 else -1
        xs = x - sgn * run / 2
        bx(c, x - run / 2 - 0.3, x + run / 2 + 0.3, y, y + depth, zf - 0.05, zf + 0.02, "steel_structure")        # landing deck
        P.railing(c, x - run / 2 - 0.3, x + run / 2 + 0.3, y + depth, zf + 0.02, 1.0, 1.1)
        n = 10
        for i in range(n):
            xx = xs + sgn * run * (i + 0.5) / n
            bx(c, xx - 0.14, xx + 0.14, y, y + width, zf + fh * (i / n) - 0.02, zf + fh * (i / n) + 0.02, "steel_structure")
        for sy in (y + 0.02, y + width - 0.02):
            P.strut(c, (xs, sy, zf), (xs + sgn * run, sy, zf + fh), 0.035, "steel_structure")
        P.strut(c, (xs, y + width, zf + 1.0), (xs + sgn * run, y + width, zf + fh + 1.0), 0.018, "steel_structure")
        for xx in (x - run / 2, x + run / 2):
            P.strut(c, (xx, y + depth, zf - 0.05), (xx, y, zf - 0.7), 0.025, "steel_structure")
    c.dirty.append((x, y, z0, 2.0, 0.15))


# ================================================================================================ tower A
def tower_a():
    c = R.new_ctx("tower_a", 24.0, 20.0)
    W, D = 24.0, 20.0
    x0, x1 = -W / 2, W / 2
    PH = 8.6                                                                  # podium height: ground 5.0 + mezzanine 3.6
    t = 0.6
    HULL_A = -0.55                                                            # just inside the 0.6 m facade wall's back face
    podium_hull(c, x0, x1, -D, HULL_A, PH, "brick")
    P.plinth_band(c, x0, x1, 0.0, 0.5, 0.12)
    shops = [(-11.0, -7.0), (-6.2, -2.8), (2.8, 6.2), (7.0, 11.0)]
    ent = (-1.9, 1.9)
    openings = [(a, b, 0.55, 4.2) for a, b in shops] + [(ent[0], ent[1], 0.0, 4.4)]
    mez = [(-11.0 + i * 2.87, -11.0 + i * 2.87 + 1.9, 5.5, 7.5) for i in range(8)]
    P.wall(c, x0, x1, 0.0, PH, 0.0, t, "brick", openings=openings + mez)
    for (a, b, za, zb) in openings + mez:
        dark_interior(c, a, b, za, zb, HULL_A)
    apertures = []
    P.wall(c, x0 - 0.0, x1, 4.4, 5.0, 0.12, 0.12, "render_plaster")           # fascia band over the shop line
    # shopfronts
    kinds = ["plain", "bars", "plain", "bars"]
    for i, (a, b) in enumerate(shops):
        P.window(c, a, b, 0.55, 4.2, 0.0, "bars" if i in (1, 3) else "plain", "steel_structure", t)
        if i == 3:
            P.roller_shutter(c, (a + b) / 2, 0.55, 0.0, b - a - 0.4, 3.4, raised=0.0, t=t)
    for i, (a, b, za, zb) in enumerate(mez):
        P.window(c, a, b, za, zb, 0.0, ["plain", "bars", "plain", "blind", "plain", "bars", "plain", "shutter"][i], "steel_structure", t)
        apertures.append(probe("mezzanine_window", (a + b) / 2, 6.9, ["glass_window", "steel_structure", "fabric_awning", "cladding_corrugated"], -0.3))        # bars / shutter slats stand proud of the plane
    for i, (a, b) in enumerate(shops):
        deep = 0.2 if i in (0, 2) else 0.0
        if i == 3:
            apertures.append(probe("shop_shutter", (a + b) / 2 + 0.7, 1.4, ["cladding_corrugated", "steel_structure"], 0.0))
        else:
            for dx in (-0.3, 0.3):
                apertures.append(probe("shop_glass", (a + b) / 2 + dx * (b - a), 0.55 + 0.3 * 3.65, ["glass_window", "steel_structure"], deep))
    P.awning(c, shops[0][0] - 0.2, shops[0][1] + 0.2, 0.05, 4.1, proj=1.6, drop=0.6)
    P.awning(c, shops[2][0] - 0.2, shops[2][1] + 0.2, 0.05, 4.1, proj=1.6, drop=0.6)
    P.sign_board(c, 0, -9.0, 0.12, 5.0 - 0.05 + 0.4, 3.4, 0.8)
    P.sign_board(c, 8, 9.0, 0.12, 5.4, 3.4, 0.8)
    P.blade_sign(c, 3, -2.6, 0.12, 6.3, 0.9, 0.5, 1.1)
    # entrance portal: double steel doors in a recessed lobby, canopy on tie rods, steps, bollards and a lit address sign
    for xx in (ent[0] - 0.25, ent[1] + 0.25):
        P.column_h(c, xx, 0.15, 0.0, 4.6, 0.32)
    P.beam_i(c, ent[0] - 0.45, ent[1] + 0.45, 0.15, 4.75, 0.34)
    P.personnel_door(c, -0.8, 0.0, 0.0, 1.5, 3.1, lamp=False, canopy=False, step=False, t=t)
    P.personnel_door(c, 0.8, 0.0, 0.0, 1.5, 3.1, lamp=False, canopy=False, step=False, t=t)
    bx(c, ent[0] - 0.3, ent[1] + 0.3, 0.0, 1.9, 4.85, 4.95, "cladding_corrugated")
    for xx in (ent[0] - 0.2, ent[1] + 0.2):
        P.strut(c, (xx, 0.1, 5.7), (xx, 1.9, 4.9), 0.018, "steel_structure")
    for i in range(3):
        bx(c, ent[0] - 0.6 - i * 0.1, ent[1] + 0.6 + i * 0.1, 0.0, 1.0 + i * 0.35, 0.0, 0.14 + 0.0, "concrete") if False else None
        bx(c, ent[0] - 0.5 - i * 0.12, ent[1] + 0.5 + i * 0.12, 0.0, 0.5 + i * 0.4, 0.0, 0.18 * (3 - i), "concrete")
    P.lamp_fixture(c, ent[0] - 0.9, 0.1, 4.2, anchor=False)
    P.lamp_fixture(c, ent[1] + 0.9, 0.1, 4.2, anchor=False)
    for xx in (-2.6, -1.2, 1.2, 2.6):
        P.bollard(c, xx, 2.6, 0.0)
    P.sign_board(c, 11, 0.0, 0.14, 5.55, 3.2, 0.7)
    # services along the front
    P.meter_cluster(c, 11.6, 0.12, 1.1, 4)
    P.junction_box(c, -11.7, 0.12, 1.4, 0.4, 0.55)
    P.pipe_run(c, [(-11.8, 0.2, 0.4), (-11.8, 0.2, 7.9), (-8.0, 0.2, 7.9)], 0.04)
    P.downspout(c, -11.75, 0.2, 0.0, PH)
    P.downspout(c, 11.75, 0.2, 0.0, PH)
    for xx in (-6.6, 6.4):
        P.ac_unit(c, xx, 0.1, 4.6, 0.8)
    # podium cornice, terrace
    bx(c, x0 - 0.2, x1 + 0.2, -D, 0.45, PH, PH + 0.25, "concrete")
    bx(c, x0 - 0.1, x1 + 0.1, 0.05, 0.4, PH - 0.5, PH, "render_plaster")
    P.parapet(c, x0, x1, 0.0, -D, PH + 0.25, 0.9, "concrete", 0.3, "roof_membrane", scuppers=(-9.0, 9.0))
    # podium sides and rear (plain brick bays with services)
    for key in "LR":
        origin, yaw, width = FACES[key](x0, x1, -D, 0.0)
        on_face(c, origin, yaw, lambda width=width: [P.window(c, -width / 2 + 2.2 + i * 3.6, -width / 2 + 3.8 + i * 3.6, 5.5, 7.4, -INSET + INSET, ["bars", "plain", "blind", "plain", "shutter"][i % 5], "steel_structure", 0.3) for i in range(int(width / 3.6) - 1)])
    # shaft: two setback blocks above the podium
    z = PH + 0.25
    top1 = block(c, -9.6, 9.6, -17.6, -2.4, z, 8, 3.45, "render_plaster", "brick", detailed=2)
    P.parapet(c, -9.6, 9.6, -2.4, -17.6, z, 0.0001, "concrete", 0.01, "roof_membrane") if False else None
    bx(c, -9.9, 9.9, -17.9, -2.1, top1 + 0.3, top1 + 0.55, "concrete")
    P.railing(c, -9.9, 9.9, -2.1, top1 + 0.55, 1.0, 1.4)
    P.railing(c, -9.9, 9.9, -17.9, top1 + 0.55, 1.0, 1.4)
    top2 = block(c, -6.8, 6.8, -15.0, -5.0, top1 + 0.55, 6, 3.45, "render_plaster", "concrete", detailed=1)
    for k in range(3):
        P.water_tank(c, -8.0 + k * 3.2, -10.0, top1 + 0.55, 0.95, 1.7)
    # fire stair along the right side of the lower shaft
    on_face(c, (9.6, -10.0, 0.0), -math.pi / 2, lambda: fire_stair(c, 0.0, 0.35, z, 8, 3.45))
    # crown
    roof_kit(c, -6.8, 6.8, -15.0, -5.0, top2 + 0.3)
    bx(c, -3.6, 3.6, -11.2, -8.8, top2 + 0.3, top2 + 4.8, "brick")                               # crown drum base
    bx(c, -3.9, 3.9, -11.5, -8.5, top2 + 4.8, top2 + 5.1, "concrete")
    P.cylv(c, 0.0, -10.0, top2 + 5.1, top2 + 8.2, 2.2, "cladding_patch", seg=14)
    P.cylv(c, 0.0, -10.0, top2 + 8.2, top2 + 8.6, 2.45, "steel_structure", seg=14)
    c.m.cyl((0, -10.0, top2 + 8.6), (0, -10.0, top2 + 9.6), 2.2, 0.15, "steel_structure", seg=14, smooth=False)
    P.antenna(c, 0.0, -10.0, top2 + 9.6, 9.0)
    c.m.sphere((0.0, -10.0, top2 + 18.8), 0.22, "lamp_glass", seg=8, rings=5)
    P.sign_board(c, 8, 0.0, -4.7, top2 + 1.8, 5.0, 1.2, hanging=True)
    c.entrance("lobby", 0.0, 0.0, 3.8, 4.4, 0.0)
    for xx in (-0.8, 0.8):
        apertures.append(probe("entrance_door", xx, 1.75, ["glass_window", "steel_structure"], 0.2))
    for xx in (-1.72, 1.72):
        apertures.append(probe("entrance_reveal", xx, 2.0, ["plastic_rubber", "steel_structure"], 0.4))
    top = top2 + 18.8
    return c, {"floors": 8 + 6 + 2, "height_m": round(top, 2), "footprint": {"min": [x0, 0.0], "max": [x1, D]}, "apertures": apertures, "masonry": MASONRY}


# ================================================================================================ tower B
def x_brace(c, x0, x1, z0, z1, y=0.14, w=0.07):
    P.strut(c, (x0, y, z0), (x1, y, z1), w, "steel_structure", seg=4)
    P.strut(c, (x0, y, z1), (x1, y, z0), w, "steel_structure", seg=4)
    for xx, zz in ((x0, z0), (x1, z0), (x0, z1), (x1, z1), ((x0 + x1) / 2, (z0 + z1) / 2)):
        bx(c, xx - 0.12, xx + 0.12, y - 0.04, y + 0.06, zz - 0.12, zz + 0.12, "steel_structure")


def braced_face(c, width, z0, floors, fh, ribbon=1.45):
    """Corrugated cladding with a continuous ribbon window per floor, vertical fins, and X bracing every third floor."""
    x0 = -width / 2
    top = z0 + floors * fh
    P.corrugated(c, x0 + 0.2, x0 + width - 0.2, z0, top, 0.0, "cladding_corrugated", pitch=0.3, depth=0.07)
    for f in range(floors):
        zf = z0 + f * fh
        zw = zf + 0.95
        bx(c, x0 + 0.25, x0 + width - 0.25, -0.02, 0.16, zw - 0.1, zw + ribbon + 0.12, "steel_structure")
        n = max(2, int(width / 1.9))
        pw = (width - 0.5) / n
        for k in range(n):
            gx0 = x0 + 0.25 + k * pw + 0.07
            gx1 = x0 + 0.25 + (k + 1) * pw - 0.07
            lit = (f * n + k * 5) % 11 == 3
            bx(c, gx0, gx1, 0.14, 0.17, zw, zw + ribbon, "lamp_glass" if lit else "glass_window")
            bx(c, gx0 - 0.04, gx0 + 0.04, 0.14, 0.2, zw, zw + ribbon, "steel_structure")
        bx(c, x0 + 0.2, x0 + width - 0.2, 0.0, 0.22, zf + fh - 0.1, zf + fh, "steel_structure")
        if f % 4 == 2:
            P.ac_unit(c, x0 + 0.9 + (f * 1.7) % (width - 1.8), 0.14, zw - 0.6, 0.8)
    for xx in (x0 + 0.1, x0 + width - 0.1):
        P.column_h(c, xx, 0.05, z0, top, 0.34, plinth=0.1, bolts=False, gussets=False)
    for f in range(0, floors - 2, 3):
        x_brace(c, x0 + 0.5, x0 + width - 0.5, z0 + f * fh + 0.1, z0 + (f + 3) * fh - 0.1) if width < 12 else [
            x_brace(c, x0 + 0.5 + s * (width / 2 - 0.25), x0 + (width / 2 - 0.25) * (s + 1) + 0.25, z0 + f * fh + 0.1, z0 + (f + 3) * fh - 0.1) for s in (0, 1)]
    bx(c, x0 - 0.05, x0 + width + 0.05, -0.1, 0.4, top, top + 0.25, "concrete")


def tower_b():
    c = R.new_ctx("tower_b", 22.0, 18.0)
    W, D = 22.0, 18.0
    x0, x1 = -W / 2, W / 2
    PH = 10.2                                                                 # 5.4 m open frame ground + 4.8 m upper podium
    HULL_B = -0.96                                                            # behind the shutters' raised-interior panel (-0.925)
    podium_hull(c, x0, x1, -D, HULL_B, PH, "concrete")
    P.plinth_band(c, x0, x1, 0.0, 0.5, 0.12)
    apertures = []
    # ground floor: steel frame (columns on plinths + header beam) with glass lobby, two loading shutters and service doors
    cols = [-10.4, -5.0, 0.0, 5.0, 10.4]
    for xx in cols:
        P.column_h(c, xx, 0.0, 0.0, 5.0, 0.4)
    P.beam_i(c, x0 + 0.3, x1 - 0.3, 0.0, 5.2, 0.5)
    bx(c, x0, x1, -0.5, 0.05, 5.4, PH, "concrete")                              # upper podium slab front
    b_open = [(-9.8, -5.6, 0.0, 3.6), (-4.4, 4.4, 0.0, 4.5), (5.6, 9.8, 0.0, 3.6), (-10.6, -9.7, 0.0, 2.3)]
    P.wall(c, x0, x1, 0.0, 5.0, -0.2, 0.5, "concrete", openings=b_open)
    for (a, b, za, zb) in b_open:
        dark_interior(c, a, b, za, zb, HULL_B)
    apertures.append(probe("shutter_raised_gap", -7.0, 0.6, ["plastic_rubber"], 0.4))
    for xx, zz in ((-7.0, 2.4), (7.0, 0.6), (7.0, 2.4)):
        apertures.append(probe("shutter_slats", xx, zz, ["cladding_corrugated", "steel_structure"], 0.15))
    for xx in (-3.67, 3.67):
        for zz in (0.65, 3.9):
            apertures.append(probe("lobby_glass", xx, zz, ["glass_window"], 0.25))
    for xx in (-0.75, 0.75):
        apertures.append(probe("lobby_door", xx, 1.75, ["glass_window", "steel_structure"], 0.25))
    P.roller_shutter(c, -7.7, 0.0, -0.2, 4.0, 3.6, raised=1.2, t=0.5)
    P.roller_shutter(c, 7.7, 0.0, -0.2, 4.0, 3.6, raised=0.0, t=0.5)
    # glass lobby: curtain wall with mullions, double doors
    for k in range(7):
        xx = -4.4 + k * 8.8 / 6
        bx(c, xx - 0.04, xx + 0.04, -0.28, -0.1, 0.0, 4.5, "steel_structure")
    for zz in (1.1, 2.25, 3.4, 4.45):
        bx(c, -4.4, 4.4, -0.28, -0.1, zz, zz + 0.05, "steel_structure")
    for k in range(6):
        xx = -4.4 + (k + 0.5) * 8.8 / 6
        for zz0 in (0.15, 1.15, 2.3, 3.45):
            bx(c, xx - 0.62, xx + 0.62, -0.3, -0.27, zz0, zz0 + (1.0 if zz0 < 3 else 1.0), "glass_window")
    P.personnel_door(c, -0.75, 0.0, -0.18, 1.3, 2.7, lamp=False, canopy=False, step=False, t=0.5)
    P.personnel_door(c, 0.75, 0.0, -0.18, 1.3, 2.7, lamp=False, canopy=False, step=False, t=0.5)
    P.personnel_door(c, -10.15, 0.0, -0.2, 0.9, 2.2, lamp=False, canopy=False, t=0.5)
    # cantilever canopy over the lobby on knee braces
    bx(c, -5.6, 5.6, 0.0, 2.9, 5.3, 5.42, "cladding_corrugated")
    bx(c, -5.6, 5.6, 2.8, 2.95, 5.0, 5.42, "steel_structure")
    for xx in (-5.2, -2.6, 0.0, 2.6, 5.2):
        P.strut(c, (xx, 0.0, 4.4), (xx, 2.8, 5.3), 0.04, "steel_structure")
        P.strut(c, (xx, 0.0, 5.3), (xx, 2.8, 5.3), 0.03, "steel_structure")
    for xx in (-5.4, 5.4):
        P.cylv(c, xx, 2.7, 0.0, 5.3, 0.07, "steel_structure", seg=8)
    P.hazard_stripe(c, -4.4, 4.4, -0.1, 0.0, 0.18, 18)
    for xx in (-3.4, -1.7, 1.7, 3.4, -9.0, -6.4, 6.4, 9.0):
        P.bollard(c, xx, 3.6, 0.0)
    P.sign_board(c, 4, 0.0, 0.0, 6.3, 6.4, 1.2)
    P.sign_board(c, 3, -7.7, -0.2, 4.9, 3.2, 0.7)
    P.sign_board(c, 6, 7.7, -0.2, 4.9, 3.2, 0.7)
    P.fence_panel(c, -11.0, -8.0, 4.4, 0.0, 1.8)
    P.hvac_box(c, 10.2, 3.0, 0.0, 1.6, 1.1, 1.3)
    P.crate_stack(c, -10.9, 2.0, 0.0, 2, 2)
    P.pallet(c, -9.3, 2.4, 0.0)
    P.barrel(c, 8.6, 1.9, 0.0)
    P.junction_box(c, 0.0, -0.15, 5.0, 0.6, 0.5)
    P.pipe_run(c, [(10.9, 0.2, 0.2), (10.9, 0.2, 9.8), (6.0, 0.2, 9.8)], 0.05)
    # upper podium: repaired corrugated cladding with window ribbons
    P.corrugated(c, x0 + 0.1, x1 - 0.1, 5.5, PH, 0.05, "cladding_corrugated", pitch=0.3, depth=0.07)
    for i in range(7):
        xx = x0 + 1.5 + i * 3.0
        P.window(c, xx, xx + 1.9, 6.7, 8.5, 0.05, ["bars", "plain", "ac", "plain", "blind", "bars", "plain"][i], "steel_structure", 0.3)
    P.patch(c, -9.0, -6.2, 8.9, 9.8, 0.1)
    P.patch(c, 5.0, 8.2, 5.7, 6.5, 0.1)
    bx(c, x0 - 0.15, x1 + 0.15, -D, 0.45, PH, PH + 0.3, "concrete")
    for key in "LR":
        origin, yaw, width = FACES[key](x0, x1, -D, 0.0)
        on_face(c, origin, yaw, lambda width=width: [P.window(c, -width / 2 + 2.2 + i * 3.7, -width / 2 + 3.8 + i * 3.7, 6.6, 8.5, 0.0, ["bars", "plain", "shutter", "plain"][i % 4], "steel_structure", 0.3) for i in range(int(width / 3.7) - 1)])
    P.parapet(c, x0, x1, 0.0, -D, PH + 0.3, 0.9, "concrete", 0.3, "roof_membrane", scuppers=(-8.0, 8.0))
    # twin shafts with a skybridge: left tall, right shorter
    z = PH + 0.3
    fh = 3.3
    for (xa, xb, ya, yb, n) in ((-10.5, -1.2, -16.6, -2.4, 16), (1.3, 10.5, -15.6, -3.4, 11)):
        hull(c, xa, xb, ya, yb, z - 0.4, z + n * fh, "cladding_corrugated")
        for key in "FLRB":
            origin, yaw, width = FACES[key](xa, xb, ya, yb)
            on_face(c, (origin[0], origin[1], 0.0), yaw, lambda width=width, n=n: braced_face(c, width, z, n, fh))
    for zb in (z + 8 * fh, z + 12 * fh):                                                  # skybridges with glazed sides
        bx(c, -1.25, 1.35, -12.0, -7.0, zb, zb + 2.6, "steel_structure")
        for yy in (-11.4, -7.6):
            bx(c, -1.0, 1.1, yy, yy + 0.05, zb + 0.6, zb + 1.9, "glass_window")
        for xx in (-0.9, 0.9):
            P.strut(c, (xx, -9.5, zb), (xx * 3.0, -9.5, zb - 2.4), 0.06, "steel_structure")
    # crowns: left = mechanical drum + lattice mast with beacon, right = tanks + billboard frame
    ztl = z + 16 * fh
    P.parapet(c, -10.5, -1.2, -2.4, -16.6, ztl, 1.0, "concrete", 0.3, "roof_membrane", scuppers=(-8.0,))
    P.cylv(c, -5.8, -11.0, ztl, ztl + 3.6, 2.6, "cladding_corrugated", seg=18)
    for zz in (ztl + 0.6, ztl + 1.8, ztl + 3.0):
        P.cylv(c, -5.8, -11.0, zz, zz + 0.07, 2.68, "steel_structure", seg=18)
    c.m.cyl((-5.8, -11.0, ztl + 3.6), (-5.8, -11.0, ztl + 4.4), 2.6, 1.2, "steel_structure", seg=18, smooth=False)
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        P.strut(c, (-5.8 + math.cos(ang) * 1.0, -11.0 + math.sin(ang) * 1.0, ztl + 4.4), (-5.8 + math.cos(ang) * 0.12, -11.0 + math.sin(ang) * 0.12, ztl + 12.0), 0.07, "steel_structure", seg=4)
    for zz in (ztl + 6.0, ztl + 8.2, ztl + 10.2):
        for a in range(4):
            ang = a * math.pi / 2 + math.pi / 4
            r = 1.0 - (zz - ztl - 4.4) / 8.5
            P.strut(c, (-5.8 + math.cos(ang) * r, -11.0 + math.sin(ang) * r, zz), (-5.8 + math.cos(ang + math.pi / 2) * r, -11.0 + math.sin(ang + math.pi / 2) * r, zz), 0.03, "steel_structure", seg=4)
    P.antenna(c, -5.8, -11.0, ztl + 12.0, 6.0)
    c.m.sphere((-5.8, -11.0, ztl + 18.2), 0.24, "lamp_glass", seg=8, rings=5)
    for xx in (-9.0, -2.6):
        P.hvac_box(c, xx, -4.4, ztl, 1.8, 1.2, 1.1)
    ztr = z + 11 * fh
    roof_kit(c, 1.3, 10.5, -15.6, -3.4, ztr, tanks=3, hvac=2, stacks=3, mast=False)
    for xx in (2.4, 9.4):
        P.column_h(c, xx, -3.9, ztr, ztr + 5.2, 0.3, plinth=0.2, bolts=False)
    bx(c, 1.9, 9.9, -4.1, -3.7, ztr + 3.1, ztr + 5.3, "steel_structure")
    P.sign_board(c, 7, 5.9, -3.65, ztr + 4.2, 7.0, 1.7)
    c.entrance("lobby", 0.0, 0.0, 8.8, 4.5, 0.0)
    return c, {"floors": 16, "height_m": round(ztl + 18.4, 2), "footprint": {"min": [x0, 0.0], "max": [x1, D]}, "apertures": apertures, "masonry": MASONRY}


# ================================================================================================ LOD1 (distance massing, floor-banded)
def tower_lod1(variant):
    if variant == "a":
        c = R.new_ctx("tower_a_lod1", 24.0, 20.0)
        PH = 8.85
        bx(c, -12, 12, -20, 0, 0, PH, "brick")
        bx(c, -12.2, 12.2, -20.2, 0.4, PH, PH + 0.25, "concrete")
        for (xa, xb, ya, yb, z0, n) in ((-9.6, 9.6, -17.6, -2.4, PH + 0.25, 8), (-6.8, 6.8, -15.0, -5.0, PH + 0.25 + 8 * 3.45 + 0.55, 6)):
            bx(c, xa, xb, ya, yb, z0, z0 + n * 3.45, "render_plaster")
            for k in range(int(round((xb - xa) / 3.1)) + 1):
                xx = xa + k * (xb - xa) / int(round((xb - xa) / 3.1))
                bx(c, xx - 0.25, xx + 0.25, yb, yb + 0.26, z0, z0 + n * 3.45, "brick")
            for f in range(n):
                bx(c, xa, xb, yb, yb + 0.14, z0 + f * 3.45 + 0.9, z0 + f * 3.45 + 2.5, "glass_window")
        bx(c, -3.6, 3.6, -11.2, -8.8, 8.85 + 8 * 3.45 + 0.55 + 6 * 3.45 + 0.3, 8.85 + 8 * 3.45 + 0.55 + 6 * 3.45 + 5.1, "brick")
        top = 8.85 + 8 * 3.45 + 0.55 + 6 * 3.45
        P.antenna(c, 0.0, -10.0, top + 5.1, 9.0)
    else:
        c = R.new_ctx("tower_b_lod1", 22.0, 18.0)
        PH = 10.5
        bx(c, -11, 11, -18, 0, 0, PH, "concrete")
        bx(c, -5, 5, -0.4, 0.1, 0, 5.0, "glass_window")
        for (xa, xb, ya, yb, n) in ((-10.5, -1.2, -16.6, -2.4, 16), (1.3, 10.5, -15.6, -3.4, 11)):
            bx(c, xa, xb, ya, yb, PH, PH + n * 3.3, "cladding_corrugated")
            for f in range(n):
                bx(c, xa + 0.25, xb - 0.25, yb, yb + 0.16, PH + f * 3.3 + 0.95, PH + f * 3.3 + 2.4, "glass_window")
        bx(c, -1.25, 1.35, -12.0, -7.0, PH + 8 * 3.3, PH + 8 * 3.3 + 2.6, "steel_structure")
        bx(c, -1.25, 1.35, -12.0, -7.0, PH + 12 * 3.3, PH + 12 * 3.3 + 2.6, "steel_structure")
        P.cylv(c, -5.8, -11.0, PH + 52.8, PH + 56.4, 2.6, "cladding_corrugated", seg=12)
        P.antenna(c, -5.8, -11.0, PH + 56.4, 12.0)
    return c, {}


def tower(variant, lod):
    return tower_lod1(variant) if lod else (tower_a() if variant == "a" else tower_b())
