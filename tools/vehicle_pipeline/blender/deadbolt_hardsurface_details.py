"""Lamps, grilles, bumpers, guards, seams, trim, mirrors and wipers seated on the shell."""
import math

from mathutils import Matrix, Vector

import deadbolt_hardsurface_cuts as K
import deadbolt_hardsurface_prims as P
import deadbolt_hardsurface_trace as T

TRUCK_NOSE = -1  # front-cast sign
COUPE_NOSE = 1


def rect_yz(y0, y1, z0, z1, r=0.012, steps=2):
    """Rounded rectangle outline in the y/z plane (x left 0) for front-mode cutters."""
    w, h = y1 - y0, z1 - z0
    pts = P.rounded_rect(w, h, min(r, w / 2.2, h / 2.2), steps)
    return [Vector((0.0, (y0 + y1) / 2 + a, (z0 + z1) / 2 + b)) for a, b in pts]


def rect_xy(x0, x1, y0, y1, r=0.01):
    w, h = x1 - x0, y1 - y0
    pts = P.rounded_rect(w, h, min(r, w / 2.2, h / 2.2), 2)
    return [Vector(((x0 + x1) / 2 + a, (y0 + y1) / 2 + b, 0.0)) for a, b in pts]


# Front-face pockets: (name, mode, sign, y0, y1, z0, z1, depth)
TRUCK_POCKETS = [
    ("Grille", -0.575, 0.575, 0.675, 1.025, 0.075),
    ("HeadL", 0.625, 0.885, 0.805, 1.045, 0.045),
    ("HeadR", -0.885, -0.625, 0.805, 1.045, 0.045),
    ("SignalL", 0.625, 0.885, 0.680, 0.775, 0.040),
    ("SignalR", -0.885, -0.625, 0.680, 0.775, 0.040),
]
COUPE_POCKETS = [
    ("LampL", 0.36, 0.82, 0.715, 0.885, 0.040),
    ("LampR", -0.82, -0.36, 0.715, 0.885, 0.040),
    ("GrilleSlot", -0.27, 0.27, 0.700, 0.800, 0.050),
    ("Intake", -0.58, 0.58, 0.370, 0.470, 0.070),
]
HOOD_VENTS = [(-1, 0.18, 0.42), (1, 0.18, 0.42)]  # sign, y0, y1 magnitude


def detail_cutters(builder, surface):
    for name, y0, y1, z0, z1, depth in TRUCK_POCKETS:
        K.make_recess_cutter(builder, f"Cutter_Truck_{name}", rect_yz(y0, y1, z0, z1), "front",
                             surface, TRUCK_NOSE, depth)
    for name, y0, y1, z0, z1, depth in COUPE_POCKETS:
        K.make_recess_cutter(builder, f"Cutter_Coupe_{name}", rect_yz(y0, y1, z0, z1), "front",
                             surface, COUPE_NOSE, depth)
    x0, x1 = T.X(676), T.X(716)
    for sign, a, b in HOOD_VENTS:
        ys = sorted((sign * a, sign * b))
        K.make_recess_cutter(builder, f"Cutter_Coupe_HoodVent_{'L' if sign > 0 else 'R'}",
                             rect_xy(x0, x1, ys[0], ys[1]), "top", surface, 1, 0.022)


def _matrix(point, normal, up=(0, 0, 1)):
    return Matrix.Translation(point) @ P.frame(normal, up)


class Seat:
    """Convenience wrappers: seat primitives on the evaluated (cut) shell."""

    def __init__(self, builder, surface):
        self.b = builder
        self.s = surface

    def box(self, name, mat, size, point, normal, bevel=0.006, up=(0, 0, 1), lift=0.0,
            segments=1):
        m = _matrix(Vector(point) + Vector(normal).normalized() * lift, normal, up)
        return P.rbox(self.b, name, size, mat, bevel=bevel, segments=segments, matrix=m,
                      offset=(0, 0, size[2] / 2))

    def side_pt(self, px, py, sign, lift=0.0):
        hit, n = self.s.side(T.X(px), T.Z(py), sign)
        return hit + n * lift, n

    def top_pt(self, x, y, lift=0.0):
        hit, n = self.s.top(x, y)
        return hit + n * lift, n

    def front_pt(self, y, z, sign, lift=0.0):
        hit, n = self.s.front(y, z, sign)
        return hit + n * lift, n

    def ribbon(self, name, points, mat, mode, width=0.004, height=0.0025, lift=0.0006,
               sign=1, closed=False):
        """Thin raised strip following the shell through (a,b) points (x/z, x/y or y/z)."""
        path = []
        for a, b in points:
            if mode == "side":
                hit, n = self.s.side(a, b, sign)
            elif mode == "top":
                hit, n = self.s.top(a, b)
            else:
                hit, n = self.s.front(a, b, sign)
            path.append(hit + n * (lift + height * 0.5))
        up = (0, 1, 0) if mode == "top" else (0, 0, 1)
        prof = [(-height / 2, -width / 2), (height / 2, -width / 2), (height / 2, width / 2),
                (-height / 2, width / 2)]
        return P.sweep(self.b, name, path, mat, profile=prof, cyclic=closed, caps=True, up=up)

    

def frame_ribbon(sd, name, y0, y1, z0, z1, grow, mat, sign, width, height=0.006, radius=0.012):
    """Closed bezel loop that follows the nose surface around a rectangular pocket."""
    pts = [(y, z) for _, y, z in rect_yz(y0 - grow, y1 + grow, z0 - grow, z1 + grow, radius, 3)]
    return sd.ribbon(name, pts, mat, "front", width=width, height=height, lift=0.0, sign=sign,
                     closed=True)


def build_truck_end(sd, surf):
    b = sd.b
    objs = []
    # grille: black recess already cut; chrome surround + egg-crate bars + badge
    y0, y1, z0, z1, d = -0.575, 0.575, 0.675, 1.025, 0.075
    face, nrm = sd.front_pt(0.0, (z0 + z1) / 2, TRUCK_NOSE)
    floor = face
    objs.append(frame_ribbon(sd, "Truck_GrilleSurround", y0, y1, z0, z1, 0.014, "chrome", TRUCK_NOSE,
                             0.024, 0.010))
    # egg crate: 3 vertical dividers, 2 horizontal dividers inside the pocket
    for k in range(1, 4):
        yy = y0 + (y1 - y0) * k / 4
        p, n = sd.front_pt(yy, (z0 + z1) / 2, TRUCK_NOSE)
        objs.append(sd.box(f"Truck_GrilleBarV_{k}", "grille", (0.016, z1 - z0 - 0.01, 0.036), p, n,
                           0.003, lift=0.0))
    for k in range(1, 3):
        zz = z0 + (z1 - z0) * k / 3
        p, n = sd.front_pt(0.0, zz, TRUCK_NOSE)
        objs.append(sd.box(f"Truck_GrilleBarH_{k}", "grille", (y1 - y0 - 0.01, 0.016, 0.036), p, n,
                           0.003, lift=0.0))
    p, n = sd.front_pt(0.0, (z0 + z1) / 2, TRUCK_NOSE)
    plate_p, plate_n = sd.front_pt(0.0, (z0 + z1) / 2, TRUCK_NOSE)
    objs.append(sd.box("Truck_BadgePlate", "chrome", (0.17, 0.095, 0.020), plate_p, plate_n, 0.006,
                       lift=0.026))
    badge = P.prism(b, "Truck_Badge", P.ellipse(0.11, 0.06, 20), "chrome", 0.012, 0.003,
                    matrix=_matrix(p + n * 0.050, n), z0=0.0)
    objs.append(badge)
    # sealed beam lamps and turn signals
    for tag, ya, yb in (("L", 0.625, 0.885), ("R", -0.885, -0.625)):
        p, n = sd.front_pt((ya + yb) / 2, 0.925, TRUCK_NOSE)
        lens = P.prism(b, f"Truck_Headlamp_{tag}", P.rounded_rect(yb - ya - 0.03, 0.21, 0.014, 2),
                       "lamp", 0.016, 0.004, matrix=_matrix(p + n * 0.006, n))
        objs.append(lens)
        sx = 0.625 + (0.885 - 0.625) / 2
        pz, nz = sd.front_pt((ya + yb) / 2, 0.7275, TRUCK_NOSE)
        objs.append(P.prism(b, f"Truck_Signal_{tag}", P.rounded_rect(yb - ya - 0.03, 0.065, 0.01, 2),
                            "amber", 0.014, 0.003, matrix=_matrix(pz + nz * 0.004, nz)))
        objs.append(frame_ribbon(sd, f"Truck_Bezel_{tag}", ya, yb, 0.680, 1.045, 0.010, "chrome",
                                 TRUCK_NOSE, 0.016, 0.008))
    # chrome bumper swept in plan view
    nose_x = surf_nose_x(sd, TRUCK_NOSE)
    xb = nose_x - 0.075
    path = [(xb + 0.06, -1.00, 0.54), (xb + 0.03, -0.93, 0.54), (xb, -0.78, 0.54), (xb, 0.78, 0.54),
            (xb + 0.03, 0.93, 0.54), (xb + 0.06, 1.00, 0.54)]
    prof = []
    for a, bz in P.rounded_rect(0.060, 0.20, 0.014, 3):
        prof.append((a, bz))
    objs.append(P.sweep(b, "Truck_Bumper_Chrome", path, "chrome", profile=prof, up=(0, 0, 1)))
    # brackets from nose to bumper
    for y in (-0.62, 0.62):
        objs.append(P.rbox(b, f"Truck_BumperBracket_{y:+.2f}", (0.09, 0.07, 0.07), "dark", 0.008,
                           matrix=Matrix.Translation((nose_x - 0.025, y, 0.54))))
    # rubber step pad and plate
    objs.append(P.rbox(b, "Truck_BumperPad", (0.012, 0.50, 0.06), "rubber", 0.003,
                       matrix=Matrix.Translation((xb - 0.036, 0.0, 0.62))))
    # brush guard: hoop with uprights and two rails
    gx = xb - 0.085
    hoop = [(gx, -0.48, 0.58), (gx, -0.48, 0.84), (gx, 0.48, 0.84), (gx, 0.48, 0.58)]
    objs.append(P.sweep(b, "Truck_BrushGuard_Hoop", P.rounded_path(hoop, 0.07, 5), "chrome",
                        radius=0.021, sides=10))
    objs.append(P.sweep(b, "Truck_BrushGuard_Rail", [(gx, -0.48, 0.71), (gx, 0.48, 0.71)], "chrome",
                        radius=0.016, sides=8))
    for y in (-0.48, 0.48):
        objs.append(P.sweep(b, f"Truck_BrushGuard_Arm_{y:+.2f}",
                            [(gx, y, 0.60), (xb + 0.01, y, 0.60)], "chrome", radius=0.018, sides=8))
    # hood outline seams
    px_a, px_b = 291.0, 395.0
    xs = [T.X(px_a + (px_b - px_a) * k / 14) for k in range(15)]
    side_a = [(x, T.top_half(T.PX(x)) - 0.05) for x in xs]
    side_b = [(x, -(T.top_half(T.PX(x)) - 0.05)) for x in xs]
    objs.append(sd.ribbon("Seam_Hood_L", side_a, "dark", "top"))
    objs.append(sd.ribbon("Seam_Hood_R", side_b, "dark", "top"))
    objs.append(sd.ribbon("Seam_Hood_Front", [(xs[0], y / 20 * (T.top_half(px_a) - 0.05))
                                              for y in range(-20, 21)], "dark", "top"))
    objs.append(sd.ribbon("Seam_Hood_Cowl", [(xs[-1], y / 20 * (T.top_half(px_b) - 0.05))
                                             for y in range(-20, 21)], "dark", "top"))
    # hood latch / ornament
    p, n = sd.top_pt(xs[0] + 0.03, 0.0)
    objs.append(sd.box("Truck_HoodOrnament", "chrome", (0.16, 0.02, 0.012), p, n, 0.004))
    return objs


def surf_nose_x(sd, sign):
    hit, _ = sd.s.front(0.0, 0.50 if sign == COUPE_NOSE else 0.55, sign)
    return hit.x


def build_coupe_end(sd, surf):
    b = sd.b
    objs = []
    for tag, ya, yb in (("L", 0.36, 0.82), ("R", -0.82, -0.36)):
        sgn = 1 if tag == "L" else -1
        inner, outer = (ya, yb) if sgn > 0 else (yb, ya)
        # main lens occupies the inboard 72 % of the pocket, the wrap-around signal the rest
        lens_c = inner + sgn * 0.5 * 0.72 * abs(yb - ya)
        lens_w = 0.72 * abs(yb - ya) - 0.03
        p, n = sd.front_pt(lens_c, 0.80, COUPE_NOSE)
        objs.append(P.prism(b, f"Coupe_Headlamp_{tag}", P.rounded_rect(lens_w, 0.125, 0.012, 2),
                            "lamp", 0.014, 0.004, matrix=_matrix(p + n * 0.006, n)))
        sig_c = outer - sgn * 0.5 * (0.28 * abs(yb - ya) - 0.02)
        q, qn = sd.front_pt(sig_c, 0.80, COUPE_NOSE)
        objs.append(P.prism(b, f"Coupe_Signal_{tag}", P.rounded_rect(0.28 * abs(yb - ya) - 0.03, 0.115, 0.01, 2),
                            "amber", 0.012, 0.003, matrix=_matrix(q + qn * 0.004, qn)))
        objs.append(frame_ribbon(sd, f"Coupe_Bezel_{tag}", ya, yb, 0.715, 0.885, 0.008, "dark",
                                 COUPE_NOSE, 0.014, 0.006))
    # narrow grille slot with slats and badge
    for k in range(4):
        zz = 0.700 + 0.100 * (k + 0.5) / 4 + 0.0
        p, n = sd.front_pt(0.0, zz, COUPE_NOSE)
        objs.append(sd.box(f"Coupe_GrilleSlat_{k}", "grille", (0.52, 0.010, 0.030), p, n, 0.002))
    p, n = sd.front_pt(0.0, 0.75, COUPE_NOSE)
    objs.append(P.prism(b, "Coupe_Badge", P.ellipse(0.09, 0.045, 20), "chrome", 0.010, 0.003,
                        matrix=_matrix(p + n * 0.02, n)))
    # lower intake mesh
    for k in range(5):
        zz = 0.370 + 0.100 * (k + 0.5) / 5
        p, n = sd.front_pt(0.0, zz, COUPE_NOSE)
        objs.append(sd.box(f"Coupe_IntakeSlat_{k}", "grille", (1.12, 0.008, 0.040), p, n, 0.002))
    for y in (-0.58, 0.58):
        p, n = sd.front_pt(y, 0.42, COUPE_NOSE)
        objs.append(sd.box(f"Coupe_FogLamp_{y:+.2f}", "amber", (0.07, 0.07, 0.016), p, n, 0.008,
                           lift=0.0))
    # bumper cover seams
    for tag, z in (("Upper", 0.602), ("Lower", 0.490)):
        pts = [(y / 24 * 0.86, z) for y in range(-24, 25)]
        objs.append(sd.ribbon(f"Seam_Coupe_Bumper{tag}", pts, "dark", "front", sign=COUPE_NOSE))
    # chin splitter + end plates
    nose = surf_nose_x(sd, COUPE_NOSE)
    objs.append(P.rbox(b, "Coupe_Splitter", (0.30, 1.44, 0.030), "dark", 0.008,
                       matrix=Matrix.Translation((nose - 0.04, 0.0, 0.350))))
    for y in (-0.72, 0.72):
        objs.append(P.rbox(b, f"Coupe_SplitterPlate_{y:+.2f}", (0.30, 0.020, 0.090), "dark", 0.006,
                           matrix=Matrix.Translation((nose - 0.04, y, 0.318))))
    objs.append(P.rbox(b, "Coupe_SplitterLip", (0.012, 1.44, 0.030), "rubber", 0.004,
                       matrix=Matrix.Translation((nose + 0.115, 0.0, 0.350))))
    # hood vent slats
    x0, x1 = T.X(676), T.X(716)
    for sign in (-1, 1):
        for k in range(4):
            x = x0 + (x1 - x0) * (k + 0.5) / 4
            hit, n = sd.s.top(x, sign * 0.30)
            objs.append(sd.box(f"Coupe_HoodSlat_{sign:+d}_{k}", "grille", (0.012, 0.22, 0.014),
                               hit - Vector((0, 0, 0.012)), (0, 0, 1), 0.002, up=(0, 1, 0)))
    for tag, ys in (("A", -1), ("B", 1)):
        pass
    # hood seams
    px_a, px_b = 636.0, 759.0
    xs = [T.X(px_a + (px_b - px_a) * k / 14) for k in range(15)]
    objs.append(sd.ribbon("Seam_CoupeHood_L", [(x, T.top_half(T.PX(x)) - 0.045) for x in xs], "dark", "top"))
    objs.append(sd.ribbon("Seam_CoupeHood_R", [(x, -(T.top_half(T.PX(x)) - 0.045)) for x in xs], "dark", "top"))
    objs.append(sd.ribbon("Seam_CoupeHood_Cowl", [(xs[0], y / 20 * (T.top_half(px_a) - 0.045))
                                                  for y in range(-20, 21)], "dark", "top"))
    return objs


def build_sides(sd, surf):
    b = sd.b
    objs = []
    for sign, tag in ((1, "L"), (-1, "R")):
        # door seams: vertical lines from the rocker to the beltline / roof edge
        seams = {"TruckFront": (410, 128, 136), "Pillar": (512, 82, 140), "CoupeFront": (610, 150, 150)}
        for name, (px, top_py, _) in seams.items():
            pts = []
            steps = 10
            bottom_py = T.lerp_table(T.SILL, px) - 18
            for k in range(steps + 1):
                py = bottom_py + (top_py - bottom_py) * k / steps
                pts.append((T.X(px), T.Z(py)))
            objs.append(sd.ribbon(f"Seam_Door_{name}_{tag}", pts, "dark", "side", sign=sign))
        # rocker line along the bottom of both doors
        rocker = [(T.X(px), T.Z(T.lerp_table(SILL_UP, px))) for px in (410, 462, 512, 561, 610)]
        objs.append(sd.ribbon(f"Seam_Rocker_{tag}", rocker, "dark", "side", sign=sign))
        # handles
        for name, px, py in (("Truck", 497, 138), ("Coupe", 548, 162)):
            p, n = sd.side_pt(px, py, sign)
            objs.append(sd.box(f"Handle_{name}_{tag}", "chrome", (0.15, 0.026, 0.024), p, n, 0.008,
                               lift=-0.001))
        # rocker moulding and fender lip beads
        mold_z = T.Z(T.lerp_table(T.SILL, 500)) + 0.075
        side_y = T.half_width(500) + 0.008
        objs.append(P.rbox(b, f"Molding_Rocker_{tag}", (T.X(612) - T.X(410), 0.024, 0.085), "dark",
                           0.007, matrix=Matrix.Translation(((T.X(410) + T.X(612)) / 2, sign * side_y,
                                                              mold_z))))
        objs.append(P.rbox(b, f"Molding_RockerChrome_{tag}", (T.X(612) - T.X(410), 0.006, 0.014),
                           "chrome", 0.002, matrix=Matrix.Translation(
                               ((T.X(410) + T.X(612)) / 2, sign * (side_y + 0.012), mold_z + 0.052))))
        for end in ("truck", "coupe"):
            R = T.WHEEL_R[end] + K.ARCH_MARGIN[end] + 0.012
            cx, cz = T.WHEEL_X[end], T.WHEEL_R[end]
            path = []
            for k in range(25):
                ang = math.radians(8 + (164 * k / 24))
                x, z = cx + R * math.cos(ang), cz + R * math.sin(ang)
                hit, n = sd.s.side(x, z, sign)
                path.append(hit + n * 0.003)
            objs.append(P.sweep(b, f"FenderLip_{end.title()}_{tag}", path, "paint2", radius=0.0105,
                                sides=6, up=(0, sign, 0)))
        # side marker lights near both noses
        for name, px, py, mat in (("Truck", 299, 156, "amber"), ("Coupe", 742, 170, "amber")):
            p, n = sd.side_pt(px, py, sign)
            objs.append(sd.box(f"Marker_{name}_{tag}", mat, (0.10, 0.014, 0.034), p, n, 0.005,
                               lift=-0.002))
        # chrome belt moulding under the side glass
        for name, a, c, py0, py1 in (("Truck", 414, 506, 129, 129.5), ("Coupe", 519, 606, 142, 150)):
            pts = [(T.X(a + (c - a) * k / 10), T.Z(py0 + (py1 - py0) * k / 10)) for k in range(11)]
            objs.append(sd.ribbon(f"Molding_Belt_{name}_{tag}", pts, "chrome", "side", width=0.012,
                                  height=0.004, sign=sign, lift=0.0))
    return objs


SILL_UP = [(400, 198), (640, 198)]


def build_mirrors(sd, surf):
    b = sd.b
    objs = []
    for sign, tag in ((1, "L"), (-1, "R")):
        # truck: dual-arm tow mirror hung off the door frame ahead of the glass
        lo, _ = sd.side_pt(414, 121, sign, 0.004)
        hi, _ = sd.side_pt(424, 103, sign, 0.004)
        mx, my, mz = min(lo.x, hi.x) - 0.045, sign * 1.10, (lo.z + hi.z) / 2 + 0.01
        for k, anchor in enumerate((lo, hi)):
            objs.append(P.sweep(b, f"Mirror_Truck_Arm_{tag}_{k}",
                                [anchor, (mx + 0.01, my - sign * 0.02, anchor.z)], "dark",
                                radius=0.011, sides=8))
        objs.append(P.rbox(b, f"Mirror_Truck_Body_{tag}", (0.060, 0.034, 0.34), "dark", 0.012,
                           matrix=Matrix.Translation((mx, my, mz))))
        objs.append(P.rbox(b, f"Mirror_Truck_Glass_{tag}", (0.006, 0.026, 0.30), "glass", 0.002,
                           matrix=Matrix.Translation((mx + 0.033, my, mz))))
        # coupe: compact body-colour door mirror ahead of the glass
        q, _ = sd.side_pt(613, 150, sign, 0.004)
        objs.append(P.sweep(b, f"Mirror_Coupe_Stem_{tag}", [q, (q.x + 0.045, sign * 1.075, q.z + 0.045)],
                            "dark", radius=0.012, sides=8))
        objs.append(P.rbox(b, f"Mirror_Coupe_Body_{tag}", (0.12, 0.060, 0.085), "paint2", 0.022,
                           matrix=Matrix.Translation((q.x + 0.06, sign * 1.10, q.z + 0.07))))
        objs.append(P.rbox(b, f"Mirror_Coupe_Glass_{tag}", (0.006, 0.050, 0.065), "glass", 0.002,
                           matrix=Matrix.Translation((q.x + 0.06 - 0.063, sign * 1.10, q.z + 0.07))))
    return objs


def build_wipers_and_roof(sd, surf):
    b = sd.b
    objs = []
    # wipers parked along the lower windshield edges; pivots sit on the cowl, below the glass
    for name, blade_px, pivot_px in (("Truck", 410.0, 399.0), ("Coupe", 606.0, 621.0)):
        for k, y in enumerate((-0.40, 0.14)):
            p0, n0 = sd.top_pt(T.X(blade_px), y + 0.20, 0.014)
            p1, _ = sd.top_pt(T.X(blade_px), y - 0.20, 0.014)
            blade = Vector(p0).lerp(Vector(p1), 0.5)
            m = Matrix.Translation(blade) @ P.frame(n0, (0, 1, 0))
            objs.append(P.rbox(b, f"Wiper_{name}_Blade_{k}", (0.012, 0.44, 0.010), "rubber", 0.003,
                               matrix=m, offset=(0, 0, 0.004)))
            piv, _ = sd.top_pt(T.X(pivot_px), y + 0.22, 0.006)
            objs.append(P.sweep(b, f"Wiper_{name}_Arm_{k}",
                                [piv, blade + n0 * 0.008 + Vector((0, 0.20, 0))], "dark",
                                radius=0.0045, sides=6))
    # cab clearance lamps on the truck roof
    for k, y in enumerate((-0.22, 0.0, 0.22)):
        p, n = sd.top_pt(T.X(449), y)
        objs.append(sd.box(f"Roof_Marker_{k}", "amber", (0.050, 0.110, 0.034), p, n, 0.008,
                           up=(0, 1, 0), lift=-0.002))
    # roof drip rails
    for sign, tag in ((1, "L"), (-1, "R")):
        pts = [(T.X(px), sign * (T.top_half(px) - 0.015)) for px in range(450, 512, 4)]
        objs.append(sd.ribbon(f"Rail_Roof_{tag}", pts, "chrome", "top", width=0.012, height=0.006))
    return objs
