"""Redline Ramen shop geometry (bmesh, Blender Z-up, front/facade +Y at y=2.0, floor top z=0.15).

Load path: counter-wide front columns (H-section) -> base plate + anchor bolts -> grouted concrete footing; columns -> bolted end
plates / knee braces -> header I-beam -> roof/parapet + awning arms + sign hangers. Cladding is corrugated sheet on the frame with a
bolted replacement panel; services (conduit, gas, downspout, sign cable) are separate fittings on saddles."""
import math

from mathutils import Matrix, Vector

import industrial_market_people as PP

V = Vector
FLOOR = 0.15
FAC = 2.0
COUNTER_Z = 1.20

M_STEEL, M_CLAD, M_PATCH, M_CONC, M_EQ, M_AWN, M_SIGN, M_CER, M_RUB = ("steel_structure", "cladding_main", "cladding_patch", "concrete",
                                                                         "equipment_steel", "awning_fabric", "sign_emissive", "ceramic", "rubber")
SHOP_MATS = [M_STEEL, M_CLAD, M_PATCH, M_CONC, M_EQ, M_AWN, M_SIGN, M_CER, M_RUB]


def bolt(m, p, axis, r=0.011, L=0.022, mat=M_STEEL):
    """Hex-head bolt/nut standing out of a surface along `axis`."""
    ax = V(axis).normalized()
    m.cyl(V(p), V(p) + ax * L, r, r * 0.97, mat, seg=6, smooth=False)


def bolt_row(m, a, b, n, axis, r=0.01, L=0.02, mat=M_STEEL):
    a, b = V(a), V(b)
    for i in range(n):
        bolt(m, a + (b - a) * (i / max(n - 1, 1)), axis, r, L, mat)


def tri_plate(m, pts2, plane, off, thick, mat=M_STEEL):
    """Triangle gusset: pts2 in the plane's two axes; off = coordinate of the plane's normal axis (plate spans off..off+thick)."""
    m.extrude_profile(pts2, off, off + thick, mat, plane=plane, smooth=False)


def i_beam_x(m, x0, x1, y, z0, z1, fw=0.2, ft=0.018, wt=0.012, mat=M_STEEL):
    zc = (z0 + z1) / 2
    L = x1 - x0
    cx = (x0 + x1) / 2
    m.box((cx, y, z0 + ft / 2), (L, fw, ft), mat)
    m.box((cx, y, z1 - ft / 2), (L, fw, ft), mat)
    m.box((cx, y, zc), (L, wt, z1 - z0 - 2 * ft), mat)


def corrugated(m, x0, x1, y, z0, z1, mat=M_CLAD, pitch=0.1, depth=0.022, th=0.004, facing=1):
    """Corrugated sheet in the XZ plane at y (outer ridge faces `facing` along y), extruded along z."""
    n = max(1, int(round((x1 - x0) / pitch)))
    pitch = (x1 - x0) / n
    top, bot = [], []
    for i in range(n):
        xa = x0 + i * pitch
        for fx, fy in ((0.0, 0.0), (0.22, 1.0), (0.5, 1.0), (0.72, 0.0)):
            top.append((xa + fx * pitch, y + facing * depth * fy))
    top.append((x1, y))
    prof = top + [(px, py - facing * th) for px, py in reversed(top)]
    m.extrude_profile(prof, z0, z1, mat, plane="XY", smooth=False)


def build_shop(m, tf=None):
    # ------------------------------------------------------------------ ground: shop floor + sidewalk + curb
    m.box((0, 1.25, 0.075), (9.6, 6.9, 0.15), M_CONC, bevel=0.025)
    # curb face lip + gutter channel line, drain grate
    m.box((0, 4.62, 0.12), (9.6, 0.16, 0.06), M_CONC, bevel=0.012)
    m.box((-3.4, 4.15, 0.152), (0.5, 0.36, 0.014), M_RUB)
    for i in range(7):
        m.box((-3.4 - 0.2 + i * 0.0667, 4.15, 0.161), (0.022, 0.32, 0.012), M_EQ)
    # threshold plate under the hatch / door
    m.box((-3.4, 2.12, 0.158), (1.0, 0.25, 0.012), M_EQ, bevel=0.003)
    # --------------------------------------------------------------- columns, footings, header beam
    colx = (-2.5, 2.5)
    for cx in colx:
        # grouted concrete plinth, grout pad, base plate, anchor bolts with double nuts
        m.box((cx, 1.94, FLOOR + 0.15), (0.62, 0.62, 0.30), M_CONC, bevel=0.03)
        m.box((cx, 1.94, FLOOR + 0.306), (0.5, 0.5, 0.012), M_CONC)
        m.box((cx, 1.94, FLOOR + 0.327), (0.44, 0.44, 0.03), M_STEEL, bevel=0.004)
        for sx in (-1, 1):
            for sy in (-1, 1):
                p = V((cx + sx * 0.17, 1.94 + sy * 0.17, FLOOR + 0.342))
                m.cyl(p - V((0, 0, 0.0)), p + V((0, 0, 0.075)), 0.0085, 0.0085, M_STEEL, seg=6)
                m.cyl(p, p + V((0, 0, 0.022)), 0.017, 0.017, M_STEEL, seg=6, smooth=False)
                m.cyl(p + V((0, 0, 0.03)), p + V((0, 0, 0.05)), 0.017, 0.017, M_STEEL, seg=6, smooth=False)
        z0, z1 = FLOOR + 0.357, 3.45
        zc = (z0 + z1) / 2
        for sy in (-1, 1):
            m.box((cx, 1.94 + sy * 0.122, zc), (0.26, 0.02, z1 - z0), M_STEEL)       # flanges
        m.box((cx, 1.94, zc), (0.013, 0.224, z1 - z0), M_STEEL)                       # web
        # stiffeners + base gussets (triangles in the web plane, both sides)
        for sy in (-1, 1):
            for sx in (-1, 1):
                tri_plate(m, [(0.0, 0.0), (0.14, 0.0), (0.0, 0.34)] if sx > 0 else [(0.0, 0.0), (-0.14, 0.0), (0.0, 0.34)], "XZ",
                          1.94 + sy * 0.122 + (0.01 if sy > 0 else -0.027), 0.017, M_STEEL) if False else None
            tri_plate(m, [(0.0, 0.0), (0.11, 0.0), (0.0, 0.30)], "YZ", cx + 0.0065, 0.014, M_STEEL) if False else None
        for sx in (-1, 1):
            # gusset plates on both sides of the web: triangles in the YZ plane
            pts = [(1.94 + 0.12, z0), (1.94 + 0.12 + 0.17, z0), (1.94 + 0.12, z0 + 0.4)]
            m.extrude_profile(pts, cx + sx * 0.0065 - (0.0 if sx > 0 else 0.014), cx + sx * 0.0065 + (0.014 if sx > 0 else 0.0), M_STEEL, plane="YZ")
            pts2 = [(1.94 - 0.12, z0), (1.94 - 0.12 - 0.17, z0), (1.94 - 0.12, z0 + 0.4)]
            m.extrude_profile(pts2, cx + sx * 0.0065 - (0.0 if sx > 0 else 0.014), cx + sx * 0.0065 + (0.014 if sx > 0 else 0.0), M_STEEL, plane="YZ")
        # mid-height bolted splice plates (older, repainted) and top end plate
        for sy in (-1, 1):
            m.box((cx, 1.94 + sy * 0.137, 1.85), (0.2, 0.012, 0.42), M_STEEL, bevel=0.002)
            for bx in (-0.075, 0.075):
                for bz in (1.70, 1.80, 1.90, 2.0):
                    bolt(m, (cx + bx, 1.94 + sy * 0.143, bz), (0, sy, 0), 0.011, 0.016)
        m.box((cx, 1.94, z1 + 0.012), (0.34, 0.3, 0.024), M_STEEL, bevel=0.003)
        for sx in (-1, 1):
            for sy in (-1, 1):
                bolt(m, (cx + sx * 0.13, 1.94 + sy * 0.11, z1 + 0.024), (0, 0, 1), 0.013, 0.018)
        # a cast-iron bumper collar at car height (a repair) with visible fixing bolts
        m.box((cx, 1.94, FLOOR + 0.78), (0.31, 0.30, 0.14), M_EQ, bevel=0.01)
        for sx in (-1, 1):
            bolt(m, (cx + sx * 0.12, 1.94 + 0.152, FLOOR + 0.78), (0, 1, 0), 0.012, 0.014)
    # header beam: I-section with end plates, knee braces and gusset triangles
    i_beam_x(m, -4.05, 4.05, 1.94, 3.46, 3.76, fw=0.22)
    for x in (-4.05, 4.05):
        m.box((x, 1.94, 3.61), (0.02, 0.26, 0.34), M_STEEL, bevel=0.003)
    for k in range(-12, 13):
        if abs(k) % 2 == 0 and abs(k * 0.32) < 4.0:
            m.box((k * 0.32, 1.94, 3.61), (0.012, 0.19, 0.265), M_STEEL)                # web stiffeners
    for cx in colx:
        for s in (-1, 1):
            a = V((cx + s * 0.13, 2.065, 3.46))
            b = V((cx + s * 0.9, 2.065, 3.46))
            c = V((cx + s * 0.13, 2.065, 2.6))
            m.extrude_profile([(a.x, a.z), (b.x, b.z), (c.x, c.z)], 2.065, 2.09, M_STEEL, plane="XZ")
            bolt(m, (cx + s * 0.5, 2.095, 3.455), (0, 1, 0), 0.012, 0.016)
            bolt(m, (cx + s * 0.13, 2.095, 2.78), (0, 1, 0), 0.012, 0.016)
            bolt(m, (cx + s * 0.13, 2.095, 3.3), (0, 1, 0), 0.012, 0.016)
    # ---------------------------------------------------------------- roof, parapet, flashings
    m.box((0, 0.0, 3.82), (8.6, 4.4, 0.13), M_CLAD, bevel=0.01)
    m.box((0, 2.08, 4.08), (8.6, 0.07, 0.4), M_CLAD, bevel=0.006)                            # front parapet / sign backing wall
    m.box((0, 2.1, 4.29), (8.7, 0.14, 0.022), M_EQ)                                          # coping
    for x in (-4.3, 4.3):
        m.box((x, 0.0, 3.95), (0.07, 4.3, 0.26), M_CLAD)
    # rooftop equipment: duct from the hood through the roof with rain cap
    m.box((-1.4, 0.7, 4.35), (0.42, 0.42, 0.7), M_EQ, bevel=0.004)
    m.cyl((-1.4, 0.7, 4.65), (-1.4, 0.7, 4.8), 0.28, 0.0, M_EQ, seg=12)
    for k in range(4):
        m.box((-1.4, 0.7, 4.1 + k * 0.2), (0.45, 0.45, 0.02), M_STEEL)
    # ---------------------------------------------------------------- walls
    # back wall + side walls: corrugated panels with vertical lap joints and rivet lines
    for i in range(8):
        corrugated(m, -4.0 + i, -3.0 + i + 0.04, -1.96, FLOOR, 3.76, M_CLAD, facing=1)
    for sx in (-1, 1):
        for i in range(4):
            y0 = -2.0 + i * 1.0
            m.extrude_profile([(sx * 4.0, y0), (sx * 4.0 + sx * 0.0, y0 + 1.04)], 0, 0, M_CLAD, plane="XY") if False else None
            # side wall corrugation runs along y: build as profile in YX extruded in z
            n = 10
            top = []
            for j in range(n):
                for fx, fy in ((0.0, 0.0), (0.22, 1.0), (0.5, 1.0), (0.72, 0.0)):
                    top.append((y0 + (j + fx) * 0.1, sx * (4.0 + 0.022 * fy)))
            top.append((y0 + 1.0, sx * 4.0))
            prof = top + [(a, b - sx * 0.004) for a, b in reversed(top)]
            m.extrude_profile([(b, a) for a, b in prof], FLOOR, 3.76, M_CLAD, plane="XY", smooth=False)
    # facade wall segments beside the hatch (outer face y=2.0)
    corrugated(m, -4.0, -2.62, FAC + 0.0, FLOOR, 3.46, M_CLAD)
    corrugated(m, 2.62, 4.0, FAC + 0.0, FLOOR, 3.46, M_CLAD)
    # lap-joint rivet lines along the facade segments + wall frame uprights behind (steel angle)
    for x in (-3.3, 3.3):
        bolt_row(m, (x, FAC + 0.03, 0.4), (x, FAC + 0.03, 3.3), 16, (0, 1, 0), 0.008, 0.012)
    # replacement panel (newer paint, different gauge) bolted over the old cladding + sealant bead
    m.box((3.5, FAC + 0.036, 1.45), (0.98, 0.012, 2.1), M_PATCH, bevel=0.003)
    for k in range(9):
        bolt(m, (3.0 + 0.0 + k * 0.0, FAC + 0.042, 0.52 + k * 0.23), (0, 1, 0), 0.0085, 0.01)
        bolt(m, (3.98, FAC + 0.042, 0.52 + k * 0.23), (0, 1, 0), 0.0085, 0.01)
    for k in range(5):
        bolt(m, (3.0 + k * 0.245, FAC + 0.042, 0.52), (0, 1, 0), 0.0085, 0.01)
        bolt(m, (3.0 + k * 0.245, FAC + 0.042, 2.4), (0, 1, 0), 0.0085, 0.01)
    # fascia / shutter housing above the hatch, with chain pull
    m.box((0, 1.98, 3.22), (4.74, 0.22, 0.4), M_CLAD, bevel=0.008)
    for k in range(-9, 10):
        m.box((k * 0.25, 2.1, 3.22), (0.012, 0.012, 0.38), M_STEEL)
    m.cyl((1.7, 2.1, 3.02), (1.7, 2.1, 2.7), 0.004, 0.004, M_EQ, seg=4)
    m.sphere((1.7, 2.1, 2.68), 0.012, M_EQ, seg=6, rings=4)
    # ---------------------------------------------------------------- service counter
    m.box((0, 1.78, COUNTER_Z - 0.02), (4.74, 0.58, 0.04), M_EQ, bevel=0.005)                # top plate
    m.cyl((-2.37, 2.075, COUNTER_Z + 0.0), (2.37, 2.075, COUNTER_Z + 0.0), 0.022, 0.022, M_EQ, seg=10)   # rolled worn lip
    m.box((0, 1.955, 0.68), (4.74, 0.04, 1.06), M_CLAD, bevel=0.004)                         # front skin
    for k in range(-4, 5):
        m.box((k * 0.52, 1.975, 0.68), (0.022, 0.014, 1.0), M_STEEL)                         # stiffener ribs
    m.box((0, 1.93, 0.205), (4.74, 0.07, 0.11), M_RUB)                                      # toe kick
    m.box((-1.25, 1.99, 0.7), (0.9, 0.012, 0.8), M_PATCH, bevel=0.003)                       # repaired lower panel (replacement)
    bolt_row(m, (-1.66, 1.998, 0.34), (-0.85, 1.998, 0.34), 6, (0, 1, 0), 0.008, 0.01)
    bolt_row(m, (-1.66, 1.998, 1.04), (-0.85, 1.998, 1.04), 6, (0, 1, 0), 0.008, 0.01)
    m.box((0, 1.5, 0.66), (4.74, 0.04, 1.0), M_STEEL)                                        # rear carcass
    m.box((-2.2, 1.7, 0.66), (0.04, 0.4, 1.0), M_STEEL)
    m.box((2.2, 1.7, 0.66), (0.04, 0.4, 1.0), M_STEEL)
    # splash-proof drip tray + vent grille in the front skin
    for k in range(9):
        m.box((1.35 + k * 0.028 - 0.11, 1.987, 0.5), (0.012, 0.014, 0.18), M_EQ)
    # ---------------------------------------------------------------- awning (arms + sagging canvas)
    arms = (-2.5, -1.25, 0.0, 1.25, 2.5)
    for ax in arms:
        m.cyl((ax, 2.07, 3.40), (ax, 3.40, 2.98), 0.016, 0.016, M_STEEL, seg=8)
        m.cyl((ax, 2.07, 3.18), (ax, 3.10, 2.98), 0.012, 0.012, M_STEEL, seg=6)
        bolt(m, (ax, 2.1, 3.36), (0, 1, 0), 0.016, 0.02)
        m.box((ax, 2.1, 3.38), (0.1, 0.02, 0.14), M_STEEL, bevel=0.003)
    m.cyl((-2.55, 3.40, 2.98), (2.55, 3.40, 2.98), 0.014, 0.014, M_STEEL, seg=8)
    W0, W1 = -2.65, 2.65

    def awn(i, j, nu=44, nv=12):
        x = W0 + (W1 - W0) * i / nu
        t = j / nv
        y = 2.1 + t * 1.38
        z = 3.40 - 0.44 * t
        # sag between arms and a worn, slightly slack front edge
        k = min(abs(x - a) for a in arms)
        sag = 0.045 * (1 - math.cos(min(k / 0.625, 1.0) * math.pi)) / 2 * (0.4 + 0.6 * math.sin(t * math.pi))
        z -= sag
        z += 0.012 * math.sin(i * 1.3 + j) * t
        return V((x, y, z))
    PP.thick_sheet(m, awn, 44, 12, 0.004, M_AWN, flip=True, uv_scale=2.0)
    def valance(i, j, nu=44, nv=4):
        x = W0 + (W1 - W0) * i / nu
        e = awn(i, 12)
        z = e.z - 0.26 * j / nv - 0.02 * math.sin(i * 1.7) * j / nv
        # scalloped lower edge
        scal = 0.045 * (0.5 - 0.5 * math.cos((x - W0) / 0.3 * 2 * math.pi)) * (j / nv)
        return V((x, e.y + 0.012 * j / nv, z + scal))
    PP.thick_sheet(m, valance, 44, 4, 0.004, M_AWN, flip=False, uv_scale=2.0)
    m.cyl((W0, 3.5, 3.0), (W1, 3.5, 3.0), 0.012, 0.012, M_AWN, seg=6)
    return None


def build_interior(m):
    """Cooking line, hood, back-of-house, services."""
    # work table (stainless) with shelf, legs
    tx0, tx1, ty0, ty1, tz = -2.3, -0.3, 0.15, 1.25, 1.05
    m.box(((tx0 + tx1) / 2, (ty0 + ty1) / 2, tz - 0.02), (tx1 - tx0, ty1 - ty0, 0.04), M_EQ, bevel=0.006)
    m.box(((tx0 + tx1) / 2, (ty0 + ty1) / 2, 0.45), (tx1 - tx0 - 0.1, ty1 - ty0 - 0.1, 0.025), M_EQ)
    for x in (tx0 + 0.04, tx1 - 0.04):
        for y in (ty0 + 0.04, ty1 - 0.04):
            m.box((x, y, (FLOOR + tz) / 2), (0.05, 0.05, tz - FLOOR - 0.04), M_EQ)
    for x in (tx0 + 0.04, tx1 - 0.04):
        m.box((x, (ty0 + ty1) / 2, 0.45), (0.04, ty1 - ty0, 0.04), M_EQ)
    # stock pot on a burner ring, with lid, handles and a ladle across it
    pc = V((-1.75, 0.8, tz))
    for r in (0.2, 0.13, 0.065):
        m.lathe([(r, 0.0), (r, 0.03)], pc + V((0, 0, 0.0)), M_STEEL, seg=18)
    m.lathe([(0.0, 0.04), (0.21, 0.04), (0.225, 0.055), (0.225, 0.4), (0.232, 0.41), (0.225, 0.42), (0.0, 0.42)], pc + V((0, 0, 0.0)), M_EQ, seg=22)
    m.lathe([(0.0, 0.43), (0.23, 0.425), (0.215, 0.44), (0.03, 0.46), (0.03, 0.49), (0.0, 0.49)], pc, M_EQ, seg=22)
    for s in (-1, 1):
        m.cyl(pc + V((s * 0.22, 0, 0.3)), pc + V((s * 0.3, 0, 0.3)), 0.012, 0.012, M_RUB, seg=6)
        m.cyl(pc + V((s * 0.3, 0, 0.3)), pc + V((s * 0.3, 0, 0.26)), 0.012, 0.012, M_RUB, seg=6)
    m.cyl(pc + V((-0.12, -0.05, 0.62)), pc + V((0.28, 0.06, 0.4)), 0.007, 0.007, M_EQ, seg=6)          # ladle handle on the rim
    m.lathe([(0.0, 0.0), (0.05, 0.01), (0.055, 0.045), (0.0, 0.05)], pc + V((0.28, 0.06, 0.4)), M_EQ, seg=12)
    # noodle boiler: tank, two wire baskets, handles, side tap
    bc = V((-0.8, 0.75, tz))
    m.box(bc + V((0, 0, 0.17)), (0.52, 0.42, 0.34), M_EQ, bevel=0.01)
    m.box(bc + V((0, 0, 0.345)), (0.44, 0.34, 0.012), M_RUB)
    for s in (-1, 1):
        m.box(bc + V((s * 0.11, 0, 0.25)), (0.17, 0.26, 0.2), M_EQ)
        m.cyl(bc + V((s * 0.11, -0.12, 0.34)), bc + V((s * 0.11, -0.3, 0.4)), 0.009, 0.009, M_RUB, seg=6)
    m.cyl(bc + V((0.26, 0.0, 0.1)), bc + V((0.33, 0.0, 0.1)), 0.012, 0.012, M_EQ, seg=6)
    # extractor hood, duct, and filter slats
    m.extrude_profile([(-2.35, 0.1), (-0.25, 0.1), (-0.25, 1.3), (-2.35, 1.3)], 2.15, 2.6, M_EQ, plane="XY", smooth=False)
    m.box((-1.3, 0.7, 2.62), (1.1, 0.5, 0.45), M_EQ, bevel=0.008)
    m.box((-1.3, 0.7, 2.95), (0.45, 0.45, 0.95), M_EQ, bevel=0.004)
    for k in range(7):
        m.box((-2.2 + k * 0.3, 0.7, 2.14), (0.012, 1.1, 0.03), M_STEEL)
    # lamp under the hood (practical warm light)
    m.box((-1.3, 0.7, 2.1), (0.9, 0.08, 0.025), M_SIGN)
    # gas cylinder, regulator, hose
    gc = V((-3.4, -1.45, FLOOR))
    m.lathe([(0.0, 0.0), (0.14, 0.0), (0.155, 0.02), (0.155, 0.5), (0.1, 0.62), (0.03, 0.66), (0.0, 0.66)], gc, M_PATCH, seg=18)
    m.cyl(gc + V((0, 0, 0.66)), gc + V((0, 0, 0.7)), 0.03, 0.03, M_EQ, seg=8)
    m.box(gc + V((0.0, 0, 0.74)), (0.07, 0.07, 0.07), M_EQ, bevel=0.01)
    m.tube([gc + V((0, 0, 0.74)), gc + V((0.1, 0.1, 0.78)), gc + V((0.5, 0.5, 0.4)), gc + V((1.2, 0.9, 0.15)), gc + V((1.5, 2.1, 0.92)), V((-1.95, 0.8, tz + 0.05))],
           [0.014] * 6, M_RUB, seg=8, samples=40, uv=("cloth", 2.0))
    # fridge + shelves + electrics on the back wall
    m.box((2.6, -1.4, 0.95), (1.0, 0.7, 1.6), M_EQ, bevel=0.012)
    m.box((2.6, -1.04, 0.95), (0.96, 0.02, 1.54), M_PATCH, bevel=0.004)
    m.cyl((2.3, -1.0, 0.7), (2.3, -1.0, 1.3), 0.014, 0.014, M_STEEL, seg=8)
    for z in (1.3, 1.75, 2.2):
        m.box((0.7, -1.78, z), (2.6, 0.3, 0.03), M_EQ)
        for x in (-0.55, 0.7, 1.95):
            m.box((x, -1.9, z - 0.12), (0.03, 0.04, 0.24), M_STEEL)
    # stacked bowls on the shelf
    for k, x in enumerate((-0.3, 0.2, 0.7)):
        for h in range(5):
            bowl(m, V((x, -1.75, 1.315 + h * 0.03)), 0.095, 0.05, stack=True)
    for k, x in enumerate((1.3, 1.6, 1.9)):
        m.lathe([(0.0, 0.0), (0.07, 0.0), (0.075, 0.2), (0.0, 0.2)], V((x, -1.75, 1.315)), M_RUB, seg=12)
    # electrical panel with meter, conduit and breaker handles
    m.box((-3.6, -1.9, 1.7), (0.7, 0.12, 0.9), M_STEEL, bevel=0.006)
    m.box((-3.6, -1.83, 1.7), (0.6, 0.02, 0.8), M_PATCH, bevel=0.003)
    for k in range(4):
        m.box((-3.8 + k * 0.1, -1.81, 1.95), (0.04, 0.012, 0.07), M_RUB)
    m.cyl((-3.6, -1.9, 2.15), (-3.6, -1.9, 3.7), 0.022, 0.022, M_EQ, seg=8)
    for z in (2.4, 2.9, 3.4):
        m.box((-3.6, -1.9, z), (0.06, 0.04, 0.03), M_STEEL)
    m.cyl((-3.6, -1.9, 3.1), (-1.0, -1.9, 3.1), 0.02, 0.02, M_EQ, seg=8)
    m.cyl((-3.6, -1.9, 3.35), (3.0, -1.9, 3.35), 0.015, 0.015, M_RUB, seg=8)
    # ceiling lamp over the counter (shop practical)
    m.box((0.6, 1.2, 3.62), (0.9, 0.1, 0.03), M_EQ)
    m.box((0.6, 1.2, 3.595), (0.84, 0.07, 0.012), M_SIGN)


def bowl(m, c, r, h, stack=False, filled=False):
    prof = [(0.025, 0.0), (0.045, 0.0), (r * 0.62, h * 0.2), (r * 0.9, h * 0.62), (r, h), (r - 0.005, h + 0.002), (r * 0.88, h * 0.64), (r * 0.6, h * 0.24), (0.0, h * 0.12)]
    faces = m.lathe(prof, c, M_CER, seg=20)
    return faces


def build_props(m, bowl_xy, blue_bowl_xy):
    # served ramen bowl at the hand-off point
    c = V((bowl_xy[0], bowl_xy[1], COUNTER_Z))
    f1 = bowl(m, c, 0.098, 0.085)
    broth = m.lathe([(0.0, 0.062), (0.082, 0.064), (0.0, 0.066)], c, M_CER, seg=20)
    return {"bowl": c, "faces": f1, "broth": broth}


def build_counter_props(m):
    # chopstick caddy, condiments, napkins, ticket spike, tea set on the counter lip
    z = COUNTER_Z
    m.lathe([(0.0, 0.0), (0.045, 0.0), (0.05, 0.11), (0.0, 0.11)], V((1.45, 1.7, z)), M_EQ, seg=14)
    for k in range(10):
        a = k * 0.62
        m.cyl(V((1.45 + 0.02 * math.cos(a), 1.7 + 0.02 * math.sin(a), z + 0.02)), V((1.45 + 0.03 * math.cos(a) + 0.01 * k * 0.1 - 0.02, 1.7 + 0.03 * math.sin(a) + 0.01, z + 0.19)),
              0.0035, 0.0032, M_RUB, seg=5)
    for k, (dx, h, col) in enumerate(((0, 0.17, M_PATCH), (0.07, 0.14, M_RUB), (0.14, 0.15, M_CER))):
        m.lathe([(0.0, 0.0), (0.027, 0.0), (0.03, 0.09), (0.016, 0.12), (0.014, h), (0.0, h)], V((-1.5 + dx, 1.62, z)), col, seg=10)
    m.box((-1.15, 1.72, z + 0.06), (0.14, 0.1, 0.12), M_EQ, bevel=0.004)                      # napkin dispenser
    m.cyl((-0.85, 1.95, z), (-0.85, 1.95, z + 0.16), 0.003, 0.003, M_STEEL, seg=4)           # ticket spike
    m.lathe([(0.0, 0.0), (0.012, 0.0), (0.012, 0.02), (0.0, 0.02)], V((-0.85, 1.95, z)), M_EQ, seg=8)
    # tea pot + two cups
    m.lathe([(0.0, 0.0), (0.06, 0.0), (0.075, 0.06), (0.06, 0.12), (0.03, 0.14), (0.0, 0.14)], V((1.95, 1.65, z)), M_CER, seg=14)
    m.cyl((1.95, 1.65, z + 0.14), (1.95, 1.65, z + 0.16), 0.015, 0.012, M_CER, seg=8)
    m.tube([V((2.03, 1.65, z + 0.1)), V((2.12, 1.65, z + 0.14)), V((2.1, 1.65, z + 0.05)), V((2.03, 1.65, z + 0.03))], [0.006] * 4, M_CER, seg=6, samples=8)
    for k in (0, 1):
        m.lathe([(0.0, 0.0), (0.02, 0.0), (0.03, 0.06), (0.028, 0.065), (0.0, 0.01)], V((1.75 + k * 0.1, 1.9, z)), M_CER, seg=10)
    # waiting bowl with a lid (earlier order, next to the pot side)
    bowl(m, V((-0.45, 1.85, z)), 0.095, 0.08)
    m.lathe([(0.0, 0.0), (0.1, 0.0), (0.1, 0.006), (0.0, 0.006)], V((-0.45, 1.85, z + 0.079)), M_EQ, seg=16)
