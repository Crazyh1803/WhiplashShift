"""Shop detail pass: ramen food, the aging illuminated sign, practical menu, door, downspout and street clutter."""
import math

from mathutils import Matrix, Vector

from industrial_market_shop import (COUNTER_Z, FAC, FLOOR, M_CER, M_CLAD, M_CONC, M_EQ, M_PATCH, M_RUB, M_SIGN, M_STEEL, bolt, bolt_row)

V = Vector


def build_food(m, bowl_c, band_faces):
    """Ramen: broth, noodle mound, chashu, soft egg, scallion, nori. band_faces collects faces per food band for the UV pass."""
    c = V(bowl_c)
    add = lambda band, faces: band_faces.setdefault(band, []).extend(faces)
    add(0, m.lathe([(0.0, 0.058), (0.084, 0.060), (0.087, 0.058), (0.0, 0.056)], c, M_CER, seg=22))
    add(1, m.sphere(c + V((0.0, 0.0, 0.056)), 0.07, M_CER, scale=(1.0, 1.0, 0.45), seg=14, rings=7))
    add(2, m.sphere(c + V((0.036, 0.02, 0.074)), 0.034, M_CER, scale=(1.0, 0.18, 1.0), seg=12, rings=6,
                    rot=Matrix.Rotation(0.5, 4, "X") @ Matrix.Rotation(0.3, 4, "Z")))
    add(2, m.sphere(c + V((-0.012, 0.038, 0.074)), 0.034, M_CER, scale=(1.0, 0.18, 1.0), seg=12, rings=6,
                    rot=Matrix.Rotation(0.7, 4, "X") @ Matrix.Rotation(-0.6, 4, "Z")))
    add(2, m.sphere(c + V((-0.03, -0.02, 0.08)), 0.026, M_CER, scale=(0.85, 0.8, 1.05), seg=12, rings=8))
    add(3, m.box(c + V((0.0, -0.06, 0.1)), (0.085, 0.004, 0.075), M_CER, rot=(-0.15, 0, 0)))
    for k in range(9):
        a = k * 0.8
        p = c + V((0.04 * math.cos(a) * 0.9, 0.04 * math.sin(a), 0.082 + 0.004 * (k % 3)))
        add(3, m.cyl(p, p + V((0, 0, 0.005)), 0.006, 0.006, M_CER, seg=6))
    for s in (0, 1):                      # chopsticks resting across the rim
        m.cyl(c + V((-0.07, 0.02 + 0.014 * s, 0.1 + 0.002 * s)), c + V((0.16, 0.12 + 0.02 * s, 0.1 + 0.004 * s)), 0.0033, 0.0026, M_RUB, seg=5)


def build_sign(m):
    """One aging physical illuminated sign: frame + dark acrylic face + channel letters (one dead), bowl icon, hanger brackets, cable gland,
    drip loop and cable run down the right-hand column to a junction box."""
    sx0, sx1, sz0, sz1, sy0, sy1 = -2.15, 2.15, 4.15, 4.97, 2.17, 2.40
    cz = (sz0 + sz1) / 2
    m.box((0, sy0 + 0.0075, cz), (4.3, 0.015, sz1 - sz0), M_STEEL)
    for z in (sz0 + 0.02, sz1 - 0.02):
        m.box((0, (sy0 + sy1) / 2, z), (4.3, sy1 - sy0, 0.04), M_STEEL, bevel=0.004)
    for x in (sx0 + 0.02, sx1 - 0.02):
        m.box((x, (sy0 + sy1) / 2, cz), (0.04, sy1 - sy0, sz1 - sz0), M_STEEL, bevel=0.004)
    m.box((0, sy1 - 0.02, cz), (4.22, 0.012, sz1 - sz0 - 0.08), M_RUB)
    for i in range(14):
        x = sx0 + 0.2 + i * 0.28
        bolt(m, (x, sy1, sz1 - 0.02), (0, 1, 0), 0.008 if i != 6 else 0.011, 0.008)
        if i not in (3, 9):
            bolt(m, (x, sy1, sz0 + 0.02), (0, 1, 0), 0.008, 0.008)
    txt = "REDLINERAMEN"
    pitch, x0 = 0.236, 1.58
    rot = (math.pi / 2, 0, math.pi)                      # reads left-to-right for a viewer standing at +Y (viewer-left = +X)
    for k, ch in enumerate(txt):
        gap = 0.18 if k >= 7 else 0.0
        mat = M_CER if k == 1 else M_SIGN                # the first E is a dead, yellowed tube
        m.text(ch, 0.36, (x0 - k * pitch - gap, sy1 - 0.014, cz - 0.02), rot, mat, extrude=0.035, align="CENTER")
    for z in (sz1 - 0.09, sz0 + 0.09):
        m.box((0, sy1 - 0.01, z), (4.0, 0.016, 0.014), M_SIGN)
    m.box((0, sy1 - 0.01, cz - 0.25), (2.9, 0.016, 0.012), M_SIGN)
    ic = V((1.92, sy1 - 0.012, cz + 0.12))
    arc = [(ic.x + 0.17 * math.cos(math.radians(a)), ic.z - 0.17 * math.sin(math.radians(a))) for a in range(0, 181, 15)]
    m.extrude_profile(arc, sy1 - 0.014, sy1 + 0.018, M_SIGN, plane="XZ", smooth=False)
    m.box((ic.x, sy1 + 0.002, ic.z - 0.19), (0.2, 0.03, 0.025), M_SIGN)
    for s in (-1, 1):
        m.box((ic.x + s * 0.07, sy1 + 0.002, ic.z + 0.12), (0.014, 0.02, 0.3), M_SIGN, rot=(0, s * 0.5, 0))
    for s in (-0.07, 0.0, 0.07):
        m.tube([V((ic.x + s, sy1 + 0.0, ic.z + 0.1)), V((ic.x + s + 0.03, sy1 + 0.0, ic.z + 0.18)), V((ic.x + s - 0.03, sy1 + 0.0, ic.z + 0.26))],
               [0.009] * 3, M_SIGN, seg=5, samples=9)
    for gi in range(3):                                  # invented glyphs (viewer-right)
        gx = -1.66 - gi * 0.17
        m.box((gx, sy1, cz + 0.12), (0.12, 0.016, 0.012), M_SIGN)
        m.box((gx + 0.03, sy1, cz + 0.02), (0.012, 0.016, 0.2), M_SIGN, rot=(0, 0.15 * (gi - 1), 0))
        m.box((gx - 0.03, sy1, cz - 0.03), (0.07, 0.016, 0.012), M_SIGN, rot=(0, 0.4, 0))
    for x in (-1.9, -0.65, 0.65, 1.9):                   # hanger brackets onto the parapet
        m.box((x, 2.14, 4.2), (0.07, 0.06, 0.07), M_STEEL, bevel=0.004)
        bolt(m, (x, 2.1, 4.2), (0, -1, 0), 0.011, 0.012)
    for x in (-1.9, 1.9):
        m.cyl((x, 2.12, 4.29), (x, 2.28, 4.17), 0.011, 0.011, M_STEEL, seg=6)
    gl = V((-1.7, 2.3, sz0))
    m.cyl(gl, gl - V((0, 0, 0.07)), 0.014, 0.014, M_EQ, seg=8)
    path = [gl - V((0, 0, 0.07)), gl + V((-0.01, 0.04, -0.2)), gl + V((-0.2, 0.08, -0.26)), V((-2.2, 2.2, 3.92)), V((-2.5, 2.145, 3.7)),
            V((-2.5, 2.125, 3.0)), V((-2.5, 2.115, 2.2))]
    m.tube(path, [0.011] * len(path), M_RUB, seg=8, samples=40, uv=("cloth", 2.0))
    jb = V((-2.5, 2.115, 2.1))
    m.box(jb, (0.17, 0.09, 0.22), M_STEEL, bevel=0.006)
    bolt_row(m, jb + V((-0.06, 0.047, 0.08)), jb + V((0.06, 0.047, -0.08)), 2, (0, 1, 0), 0.008, 0.01)
    m.cyl(jb - V((0, 0, 0.11)), jb - V((0, 0, 0.9)), 0.015, 0.015, M_EQ, seg=8)


def build_menu(m, rows):
    bx, bz = 3.45, 1.56
    m.box((bx, FAC + 0.056, bz), (0.86, 0.016, 1.12), M_RUB, bevel=0.003)
    for s in (-1, 1):
        m.box((bx + s * 0.44, FAC + 0.06, bz), (0.03, 0.03, 1.16), M_STEEL, bevel=0.002)
        m.box((bx, FAC + 0.06, bz + s * 0.58), (0.9, 0.03, 0.03), M_STEEL, bevel=0.002)
        for u in (-0.4, 0.4):
            bolt(m, (bx + u, FAC + 0.078, bz + s * 0.58), (0, 1, 0), 0.01, 0.01)
    rot = (math.pi / 2, 0, math.pi)
    y = FAC + 0.066
    m.text("MENU", 0.085, (bx, y, 2.0), rot, M_CER, extrude=0.004, align="CENTER")
    m.box((bx, y, 1.935), (0.64, 0.004, 0.006), M_CER)
    for i, (name, price) in enumerate(rows):
        z = 1.84 - i * 0.092
        m.text(name, 0.052, (bx + 0.37, y, z), rot, M_CER, extrude=0.004, align="LEFT")
        m.text(price, 0.052, (bx - 0.2, y, z), rot, M_CER, extrude=0.004, align="LEFT")
        m.box((bx - 0.05, y, z - 0.03), (0.78, 0.003, 0.003), M_CER)
    m.text("CASH ONLY", 0.04, (bx, y, 1.04), rot, M_CER, extrude=0.004, align="CENTER")
    m.tube([V((bx - 0.2, FAC + 0.09, 2.17)), V((bx - 0.2, FAC + 0.25, 2.25)), V((bx - 0.15, FAC + 0.33, 2.2))], [0.007] * 3, M_STEEL, seg=6, samples=12)
    m.cyl(V((bx - 0.15, FAC + 0.31, 2.22)), V((bx - 0.12, FAC + 0.39, 2.13)), 0.035, 0.05, M_STEEL, seg=10)
    m.sphere(V((bx - 0.12, FAC + 0.37, 2.15)), 0.026, M_SIGN, seg=8, rings=6)


def build_door_and_services(m):
    dx = -3.3
    m.box((dx, FAC + 0.05, 1.12), (0.98, 0.04, 1.96), M_CLAD, bevel=0.004)
    for s in (-1, 1):
        m.box((dx + s * 0.52, FAC + 0.04, 1.14), (0.06, 0.07, 2.04), M_STEEL, bevel=0.004)
    m.box((dx, FAC + 0.04, 2.16), (1.1, 0.07, 0.07), M_STEEL, bevel=0.004)
    m.box((dx, FAC + 0.04, 0.155), (1.1, 0.07, 0.03), M_STEEL)
    m.box((dx, FAC + 0.085, 0.42), (0.9, 0.012, 0.5), M_PATCH, bevel=0.003)
    m.box((dx + 0.12, FAC + 0.075, 1.55), (0.36, 0.012, 0.18), M_RUB)
    m.cyl((dx - 0.3, FAC + 0.1, 0.8), (dx - 0.3, FAC + 0.1, 1.3), 0.014, 0.014, M_EQ, seg=8)
    for z in (0.8, 1.3):
        m.cyl((dx - 0.3, FAC + 0.07, z), (dx - 0.3, FAC + 0.1, z), 0.01, 0.01, M_EQ, seg=6)
    m.cyl((dx - 0.56, FAC + 0.12, 2.1), (dx + 0.56, FAC + 0.12, 2.1), 0.014, 0.014, M_STEEL, seg=8)
    bolt_row(m, (dx - 0.5, FAC + 0.13, 2.1), (dx + 0.5, FAC + 0.13, 2.1), 5, (0, 1, 0), 0.01, 0.01)
    m.box((dx + 0.7, FAC + 0.1, 2.38), (0.2, 0.12, 0.12), M_STEEL, bevel=0.006)
    m.box((dx + 0.7, FAC + 0.17, 2.38), (0.14, 0.02, 0.08), M_SIGN)
    ds = V((4.12, 1.72, 0))
    m.cyl(ds + V((0, 0, 0.36)), ds + V((0, 0, 3.7)), 0.034, 0.034, M_EQ, seg=10)
    for z in (0.9, 1.8, 2.7, 3.5):
        m.box(ds + V((-0.02, 0, z)), (0.07, 0.016, 0.03), M_STEEL)
    m.tube([ds + V((0, 0, 0.4)), ds + V((0.0, 0.0, 0.3)), ds + V((0.05, 0.1, 0.22)), ds + V((0.0, 0.3, 0.2))], [0.034] * 4, M_EQ, seg=10, samples=12,
           round_ends=(False, False))
    m.box(ds + V((0, 0.35, FLOOR + 0.01)), (0.3, 0.3, 0.02), M_CONC)
    for k in range(3):
        m.box((-3.9, 2.55, FLOOR + 0.14 + k * 0.28), (0.5, 0.36, 0.26), M_RUB, rot=(0, 0, 0.05 * k), bevel=0.01)
    m.lathe([(0.0, 0.0), (0.11, 0.0), (0.14, 0.28), (0.145, 0.28), (0.0, 0.27)], V((-3.0, 2.9, FLOOR)), M_EQ, seg=14)
    m.tube([V((2.5, 2.12, 3.0)), V((2.9, 2.14, 2.55)), V((3.3, 2.1, 2.5)), V((3.45, 2.1, 2.2))], [0.008] * 4, M_RUB, seg=6, samples=20)
