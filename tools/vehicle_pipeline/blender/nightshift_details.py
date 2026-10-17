"""Lamps, grilles, bumpers, guards, seams, trim, mirrors and wipers seated on the shell."""
import math

from mathutils import Matrix, Vector

import nightshift_cuts as K
import nightshift_prims as P
import nightshift_trace as T

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
    ("Grille", -0.44, 0.44, 0.560, 0.900, 0.070),
    ("HeadUL", 0.48, 0.80, 0.780, 0.905, 0.045),
    ("HeadUR", -0.80, -0.48, 0.780, 0.905, 0.045),
    ("HeadLL", 0.48, 0.80, 0.640, 0.760, 0.045),
    ("HeadLR", -0.80, -0.48, 0.640, 0.760, 0.045),
    ("SignalL", 0.48, 0.80, 0.555, 0.620, 0.035),
    ("SignalR", -0.80, -0.48, 0.555, 0.620, 0.035),
]
COUPE_POCKETS = [
    ("LampOL", 0.52, 0.76, 0.555, 0.690, 0.040),
    ("LampOR", -0.76, -0.52, 0.555, 0.690, 0.040),
    ("LampIL", 0.28, 0.50, 0.555, 0.690, 0.040),
    ("LampIR", -0.50, -0.28, 0.555, 0.690, 0.040),
    ("GrilleSlot", -0.23, 0.23, 0.585, 0.665, 0.050),
    ("Intake", -0.40, 0.40, 0.350, 0.410, 0.060),
]
HOOD_VENTS = [(-1, 0.14, 0.44), (1, 0.14, 0.44)]  # sign, y0, y1 magnitude


def detail_cutters(builder, surface):
    seam_cutters(builder, surface)
    for name, y0, y1, z0, z1, depth in TRUCK_POCKETS:
        K.make_recess_cutter(builder, f"Cutter_Truck_{name}", rect_yz(y0, y1, z0, z1), "front",
                             surface, TRUCK_NOSE, depth)
    for name, y0, y1, z0, z1, depth in COUPE_POCKETS:
        K.make_recess_cutter(builder, f"Cutter_Coupe_{name}", rect_yz(y0, y1, z0, z1), "front",
                             surface, COUPE_NOSE, depth)
    x0, x1 = T.X(666), T.X(738)
    for sign, a, b in HOOD_VENTS:
        ys = sorted((sign * a, sign * b))
        K.make_recess_cutter(builder, f"Cutter_Coupe_HoodVent_{'L' if sign > 0 else 'R'}",
                             rect_xy(x0, x1, ys[0], ys[1]), "top", surface, 1, 0.022)


SEAM_W = 0.0045
HANDLES = (("Truck", 498, 150), ("Coupe", 560, 169))
# door shut lines: name -> (px, py bottom, py top)
DOOR_SEAMS = {"TruckFront": (414, 224, 134), "Pillar": (522, 224, 106), "CoupeFront": (628, 224, 161)}
COWL_VENTS = {"Truck": (T.X(392), T.X(402), 0.56), "Coupe": (T.X(638), T.X(648), 0.58)}


def _thin_rect(a0, a1, b0, b1):
    return [Vector((a0, 0.0, b0)), Vector((a1, 0.0, b0)), Vector((a1, 0.0, b1)), Vector((a0, 0.0, b1))]


def seam_cutters(builder, surface):
    """True shut-line grooves: door fronts/rear, rocker line and hood panels."""
    for sign, tag in ((1, "L"), (-1, "R")):
        for name, (px, py0, py1) in DOOR_SEAMS.items():
            x = T.X(px)
            K.make_recess_cutter(builder, f"Cutter_Seam_{name}_{tag}",
                                 _thin_rect(x - SEAM_W / 2, x + SEAM_W / 2, T.Z(py0), T.Z(py1)),
                                 "side", surface, sign, 0.0035, step=0.2, boundary_step=0.05)
        z = T.Z(222)
        K.make_recess_cutter(builder, f"Cutter_Seam_Rocker_{tag}",
                             _thin_rect(T.X(414), T.X(628), z - SEAM_W / 2, z + SEAM_W / 2),
                             "side", surface, sign, 0.0035, step=0.2, boundary_step=0.05)
        for hname, px, py in HANDLES:
            xc, zc = T.X(px), T.Z(py)
            K.make_recess_cutter(builder, f"Cutter_HandlePocket_{hname}_{tag}",
                                 _thin_rect(xc - 0.10, xc + 0.10, zc - 0.034, zc + 0.034),
                                 "side", surface, sign, 0.022, step=0.2, boundary_step=0.04)
    # hood panel gaps (top surface grooves)
    for name, (pa, pb, inset) in {"Truck": (291.0, 403.0, 0.05), "Coupe": (652.0, 772.0, 0.045)}.items():
        xa, xb = T.X(pa), T.X(pb)
        for sign, tag in ((1, "L"), (-1, "R")):
            ys = [sign * (T.top_half(pa) - inset), sign * (T.top_half(pb) - inset)]
            K.make_recess_cutter(builder, f"Cutter_Seam_{name}Hood_{tag}",
                                 [Vector((xa, ys[0] - SEAM_W / 2, 0)), Vector((xb, ys[1] - SEAM_W / 2, 0)),
                                  Vector((xb, ys[1] + SEAM_W / 2, 0)), Vector((xa, ys[0] + SEAM_W / 2, 0))],
                                 "top", surface, 1, 0.0035, step=0.2, boundary_step=0.05)
        yh = T.top_half(pa) - inset
        K.make_recess_cutter(builder, f"Cutter_Seam_{name}HoodEnd", _thin_rect_xy(xa, yh), "top",
                             surface, 1, 0.0035, step=0.2, boundary_step=0.05)
        yh = T.top_half(pb) - inset
        K.make_recess_cutter(builder, f"Cutter_Seam_{name}HoodBack", _thin_rect_xy(xb, yh), "top",
                             surface, 1, 0.0035, step=0.2, boundary_step=0.05)
    for name, (xa, xb, hy) in COWL_VENTS.items():
        K.make_recess_cutter(builder, f"Cutter_CowlVent_{name}", rect_xy(xa, xb, -hy, hy, 0.01), "top",
                             surface, 1, 0.020)


def _thin_rect_xy(x, half_y):
    return [Vector((x - SEAM_W / 2, -half_y, 0)), Vector((x + SEAM_W / 2, -half_y, 0)),
            Vector((x + SEAM_W / 2, half_y, 0)), Vector((x - SEAM_W / 2, half_y, 0))]


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


BUMPER_Z = 0.43


def surf_nose_x(sd, sign):
    hit, _ = sd.s.front(0.0, 0.34 if sign == COUPE_NOSE else 0.45, sign)
    return hit.x


BOWTIE = [(-0.060, 0.022), (-0.012, 0.010), (0.012, 0.010), (0.060, 0.022),
          (0.060, -0.022), (0.012, -0.010), (-0.012, -0.010), (-0.060, -0.022)]


def build_truck_end(sd, surf):
    b = sd.b
    objs = []
    # grille: black recess already cut; chrome surround, 9x3 egg-crate, centre bar and bowtie
    y0, y1, z0, z1, d = -0.44, 0.44, 0.560, 0.900, 0.070
    zc = (z0 + z1) / 2
    objs.append(frame_ribbon(sd, "Truck_GrilleSurround", y0, y1, z0, z1, 0.014, "chrome", TRUCK_NOSE,
                             0.024, 0.010))
    for k in range(1, 9):
        yy = y0 + (y1 - y0) * k / 9
        p, n = sd.front_pt(yy, zc, TRUCK_NOSE)
        objs.append(sd.box(f"Truck_GrilleBarV_{k}", "grille", (0.011, z1 - z0 - 0.01, 0.034), p, n,
                           0.003, lift=0.0))
    for k in range(1, 4):
        zz = z0 + (z1 - z0) * k / 4
        p, n = sd.front_pt(0.0, zz, TRUCK_NOSE)
        h = "chrome" if k == 2 else "grille"
        objs.append(sd.box(f"Truck_GrilleBarH_{k}", h, (y1 - y0 - 0.01, 0.014 if k != 2 else 0.026, 0.036),
                           p, n, 0.003, lift=0.0))
    p, n = sd.front_pt(0.0, zc, TRUCK_NOSE)
    objs.append(P.prism(b, "Truck_Badge", BOWTIE, "chrome", 0.012, 0.003,
                        matrix=_matrix(p + n * 0.044, n)))
    # stacked rectangular sealed-beam lamps, parking lamps and chrome bezels
    for tag, ya, yb in (("L", 0.48, 0.80), ("R", -0.80, -0.48)):
        yc = (ya + yb) / 2
        for row, (za, zb) in (("U", (0.780, 0.905)), ("L", (0.640, 0.760))):
            p, n = sd.front_pt(yc, (za + zb) / 2, TRUCK_NOSE)
            objs.append(P.prism(b, f"Truck_Headlamp_{row}{tag}",
                                P.rounded_rect(yb - ya - 0.03, zb - za - 0.03, 0.012, 2),
                                "lamp", 0.016, 0.004, matrix=_matrix(p + n * 0.006, n)))
        pz, nz = sd.front_pt(yc, 0.5875, TRUCK_NOSE)
        objs.append(P.prism(b, f"Truck_Signal_{tag}", P.rounded_rect(yb - ya - 0.03, 0.035, 0.008, 2),
                            "amber", 0.014, 0.003, matrix=_matrix(pz + nz * 0.004, nz)))
        objs.append(frame_ribbon(sd, f"Truck_Bezel_{tag}", ya, yb, 0.555, 0.905, 0.010, "chrome",
                                 TRUCK_NOSE, 0.016, 0.008))
        objs.append(sd.ribbon(f"Truck_BezelMid_{tag}",
                              [(ya - 0.004, 0.770), (yb + 0.004, 0.770)],
                              "chrome", "front", width=0.014, height=0.008, lift=0.0, sign=TRUCK_NOSE))
    # chrome bumper swept in plan view, wrap-around ends, centre rubber strip
    nose_x = surf_nose_x(sd, TRUCK_NOSE)
    xb = nose_x - 0.075
    zb = BUMPER_Z
    path = [(xb + 0.13, -0.915, zb), (xb + 0.07, -0.93, zb), (xb + 0.025, -0.86, zb), (xb, -0.74, zb),
            (xb, 0.74, zb), (xb + 0.025, 0.86, zb), (xb + 0.07, 0.93, zb), (xb + 0.13, 0.915, zb)]
    prof = [(a, bz) for a, bz in P.rounded_rect(0.060, 0.20, 0.014, 3)]
    objs.append(P.sweep(b, "Truck_Bumper_Chrome", path, "chrome", profile=prof, up=(0, 0, 1)))
    for y in (-0.62, 0.62):
        objs.append(P.rbox(b, f"Truck_BumperBracket_{y:+.2f}", (0.09, 0.07, 0.07), "dark", 0.008,
                           matrix=Matrix.Translation((nose_x - 0.025, y, zb))))
    # twin vertical push guards with rubber caps and a tie bar
    for sgn in (-1, 1):
        y = sgn * 0.60
        objs.append(P.rbox(b, f"Truck_PushGuard_{sgn:+d}", (0.050, 0.060, 0.15), "chrome", 0.016,
                           matrix=Matrix.Translation((xb - 0.050, y, zb + 0.045))))
        objs.append(P.rbox(b, f"Truck_PushGuardPad_{sgn:+d}", (0.014, 0.040, 0.10), "rubber", 0.004,
                           matrix=Matrix.Translation((xb - 0.082, y, zb + 0.045))))
        objs.append(P.rbox(b, f"Truck_PushGuardBase_{sgn:+d}", (0.090, 0.090, 0.040), "dark", 0.008,
                           matrix=Matrix.Translation((xb - 0.010, y, zb - 0.005))))
    # chrome hood-edge trim and hood ornament
    pts = [(T.X(292.5), y / 20 * 0.62) for y in range(-20, 21)]
    objs.append(sd.ribbon("Truck_HoodEdgeTrim", pts, "chrome", "top", width=0.016, height=0.005))
    p, n = sd.top_pt(T.X(298.0), 0.0)
    objs.append(sd.box("Truck_HoodOrnament", "chrome", (0.12, 0.024, 0.014), p, n, 0.004, up=(0, 1, 0)))
    return objs


def build_coupe_end(sd, surf):
    b = sd.b
    objs = []
    # recessed quad rectangular headlights: inner + outer lens per side, dark bezels
    for tag, sgn in (("L", 1), ("R", -1)):
        for name, a, c in (("O", 0.52, 0.76), ("I", 0.28, 0.50)):
            ya, yb = sorted((sgn * a, sgn * c))
            yc = (ya + yb) / 2
            p, n = sd.front_pt(yc, 0.6225, COUPE_NOSE)
            objs.append(P.prism(b, f"Coupe_Headlamp_{name}{tag}",
                                P.rounded_rect(yb - ya - 0.03, 0.105, 0.010, 2), "lamp", 0.008, 0.002,
                                matrix=_matrix(p + n * 0.001, n)))
    # narrow grille slot with slats and badge
    for k in range(3):
        zz = 0.585 + 0.080 * (k + 0.5) / 3
        p, n = sd.front_pt(0.0, zz, COUPE_NOSE)
        objs.append(sd.box(f"Coupe_GrilleSlat_{k}", "grille", (0.40, 0.009, 0.030), p, n, 0.002))
    p, n = sd.front_pt(0.0, 0.625, COUPE_NOSE)
    objs.append(P.prism(b, "Coupe_Badge", P.ellipse(0.075, 0.030, 20), "chrome", 0.010, 0.003,
                        matrix=_matrix(p + n * 0.022, n)))
    # lower air dam mesh and chin turn/fog lamps
    for k in range(3):
        zz = 0.350 + 0.060 * (k + 0.5) / 3
        p, n = sd.front_pt(0.0, zz, COUPE_NOSE)
        objs.append(sd.box(f"Coupe_IntakeSlat_{k}", "grille", (0.76, 0.008, 0.036), p, n, 0.002))
    for y in (-0.50, 0.50):
        p, n = sd.front_pt(y, 0.380, COUPE_NOSE)
        objs.append(sd.box(f"Coupe_ChinLamp_{y:+.2f}", "amber", (0.09, 0.050, 0.016), p, n, 0.008,
                           lift=0.0))
    # bumper cover seam
    # chin spoiler: lip, end plates, rubber edge
    nose = surf_nose_x(sd, COUPE_NOSE)
    zs = 0.285
    hw = lambda px: T.half_width(px) - 0.02
    pts = [(T.X(px), -hw(px), zs) for px in (752, 762, 770, 777)] + [(nose + 0.020, -0.46, zs), (nose + 0.022, 0.0, zs), (nose + 0.020, 0.46, zs)] \
        + [(T.X(px), hw(px), zs) for px in (777, 770, 762, 752)]
    prof = P.rounded_rect(0.070, 0.130, 0.016, 3)
    objs.append(P.sweep(b, "Coupe_Splitter", pts, "dark", profile=prof, up=(0, 0, 1)))
    objs.append(P.rbox(b, "Coupe_SplitterLip", (0.012, 0.92, 0.030), "rubber", 0.004,
                       matrix=Matrix.Translation((nose + 0.061, 0.0, zs - 0.012))))
    # louvered hood-scoop slats
    x0, x1 = T.X(666), T.X(738)
    for sign in (-1, 1):
        for k in range(6):
            x = x0 + (x1 - x0) * (k + 0.5) / 6
            hit, n = sd.s.top(x, sign * 0.29)
            objs.append(sd.box(f"Coupe_HoodSlat_{sign:+d}_{k}", "grille", (0.012, 0.25, 0.014),
                               hit - Vector((0, 0, 0.012)), (0, 0, 1), 0.002, up=(0, 1, 0)))
    # cab back window and trim on the vertical wall of the roof step (faces the Camaro end)
    zc = T.Z(106.5)
    outline = [Vector((0.0, y, z)) for y, z in ((-0.525, zc - 0.0615), (0.525, zc - 0.0615),
                                                (0.525, zc + 0.0615), (-0.525, zc + 0.0615))]
    objs.append(K.glass_panel(sd.b, "Glass_CabRear", outline, sd.s,
                              lambda q: ((4.0, q.y, q.z), (-1, 0, 0)),
                              0.003, step=0.05, axes=(1, 2)))
    objs.append(frame_ribbon(sd, "Cab_RearGlassTrim", -0.52, 0.52, zc - 0.0575, zc + 0.0575, 0.012,
                             "chrome", COUPE_NOSE, 0.014, 0.004, radius=0.012))
    return objs


def build_sides(sd, surf):
    b = sd.b
    objs = []
    for sign, tag in ((1, "L"), (-1, "R")):
        # handles
        for name, px, py in HANDLES:
            p, n = sd.side_pt(px, py, sign)
            objs.append(sd.box(f"Handle_{name}_{tag}", "chrome", (0.15, 0.026, 0.024), p, n, 0.008,
                               lift=0.007))
        # rocker moulding and fender lip beads
        mold_z = T.Z(T.lerp_table(T.SILL, 500)) + 0.075
        side_y = T.half_width(500) + 0.008
        objs.append(P.rbox(b, f"Molding_Rocker_{tag}", (T.X(628) - T.X(414), 0.024, 0.085), "dark",
                           0.007, matrix=Matrix.Translation(((T.X(414) + T.X(628)) / 2, sign * side_y,
                                                              mold_z))))
        objs.append(P.rbox(b, f"Molding_RockerChrome_{tag}", (T.X(628) - T.X(414), 0.006, 0.014),
                           "chrome", 0.002, matrix=Matrix.Translation(
                               ((T.X(414) + T.X(628)) / 2, sign * (side_y + 0.012), mold_z + 0.052))))
        for end in ("truck", "coupe"):
            R = T.WHEEL_R[end] + K.ARCH_MARGIN[end] + 0.012
            cx, cz = T.WHEEL_X[end], T.WHEEL_R[end]
            path = []
            for k in range(25):
                ang = math.radians(8 + (164 * k / 24))
                x, z = cx + R * math.cos(ang), cz + R * math.sin(ang)
                hit, n = sd.s.side(x, z, sign)
                if abs(n.z) > 0.6:
                    break  # surface has rolled over into the shoulder: stop the lip there
                path.append(hit + n * 0.003)
            objs.append(P.sweep(b, f"FenderLip_{end.title()}_{tag}", path, "paint2", radius=0.0105,
                                sides=6, up=(0, sign, 0)))
        # red reflectors at both rocker ends (the car is reversible: they are the tail cue)
        for name, px in (("A", 424), ("B", 624)):
            p, n = sd.side_pt(px, 218, sign)
            objs.append(sd.box(f"Reflector_{name}_{tag}", "marker", (0.075, 0.012, 0.024), p, n, 0.004,
                               lift=-0.003))
        # side marker lights near both noses
        for name, px, py, mat in (("Truck", 301, 168, "amber"), ("Coupe", 730, 190, "amber")):
            p, n = sd.side_pt(px, py, sign)
            objs.append(sd.box(f"Marker_{name}_{tag}", mat, (0.05 if name == "Coupe" else 0.10, 0.014, 0.034), p, n,
                               0.005, lift=-0.004 if name == "Coupe" else -0.002))
        # truck mid-flank body-side moulding (reference: runs the truck half, ends at the pillar)
        pts = [(T.X(396 + (520 - 396) * k / 12), T.Z(188)) for k in range(13)]
        objs.append(sd.ribbon(f"Molding_Flank_{tag}", pts, "dark", "side", width=0.034, height=0.007,
                              sign=sign, lift=0.0))
        pts = [(T.X(396 + (520 - 396) * k / 12), T.Z(188) + 0.021) for k in range(13)]
        objs.append(sd.ribbon(f"Molding_FlankChrome_{tag}", pts, "chrome", "side", width=0.006,
                              height=0.004, sign=sign, lift=0.007))
        # chrome belt moulding under the side glass
        for name, a, c, py0, py1 in (("Truck", 414, 516, 138.5, 139), ("Coupe", 533, 626, 160, 160.5)):
            pts = [(T.X(a + (c - a) * k / 10), T.Z(py0 + (py1 - py0) * k / 10)) for k in range(11)]
            objs.append(sd.ribbon(f"Molding_Belt_{name}_{tag}", pts, "chrome", "side", width=0.012,
                                  height=0.004, sign=sign, lift=0.0015))
    return objs




def build_mirrors(sd, surf):
    b = sd.b
    objs = []
    for sign, tag in ((1, "L"), (-1, "R")):
        # truck: rectangular dual-arm mirror just forward of the door, beside the A-pillar base
        lo, _ = sd.side_pt(420, 150, sign, 0.004)
        hi, _ = sd.side_pt(420, 132, sign, 0.004)
        mx, my, mz = T.X(426), sign * 1.10, (lo.z + hi.z) / 2
        for k, anchor in enumerate((lo, hi)):
            objs.append(P.sweep(b, f"Mirror_Truck_Arm_{tag}_{k}",
                                [anchor, (mx + 0.01, my - sign * 0.010, anchor.z)], "dark",
                                radius=0.011, sides=8))
        objs.append(P.rbox(b, f"Mirror_Truck_Body_{tag}", (0.060, 0.034, 0.30), "dark", 0.012,
                           matrix=Matrix.Translation((mx, my, mz))))
        objs.append(P.rbox(b, f"Mirror_Truck_Glass_{tag}", (0.006, 0.026, 0.26), "glass", 0.002,
                           matrix=Matrix.Translation((mx + 0.033, my, mz))))
        # camaro: aerodynamic body-colour mirror at the front of the frameless door glass
        q, _ = sd.side_pt(617, 158, sign, 0.004)
        objs.append(P.sweep(b, f"Mirror_Coupe_Stem_{tag}", [q, (q.x + 0.045, sign * 1.015, q.z + 0.040)],
                            "dark", radius=0.016, sides=8))
        objs.append(P.rbox(b, f"Mirror_Coupe_Body_{tag}", (0.14, 0.060, 0.080), "paint2", 0.024,
                           matrix=Matrix.Translation((q.x + 0.07, sign * 1.04, q.z + 0.065))))
        objs.append(P.rbox(b, f"Mirror_Coupe_Glass_{tag}", (0.006, 0.050, 0.060), "glass", 0.002,
                           matrix=Matrix.Translation((q.x + 0.07 - 0.073, sign * 1.04, q.z + 0.065))))
    return objs


def build_wipers_and_roof(sd, surf):
    b = sd.b
    objs = []
    # wipers parked along the lower windshield edges; pivots sit on the cowl, below the glass
    for name, blade_px, pivot_px in (("Truck", 415.0, 404.0), ("Coupe", 627.0, 638.0)):
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
        p, n = sd.top_pt(T.X(458), y)
        objs.append(sd.box(f"Roof_Marker_{k}", "amber", (0.050, 0.110, 0.034), p, n, 0.008,
                           up=(0, 1, 0), lift=-0.002))
    # roof drip rails
    for sign, tag in ((1, "L"), (-1, "R")):
        pts = [(T.X(px), sign * (T.top_half(px) - 0.015)) for px in range(454, 516, 4)]
        objs.append(sd.ribbon(f"Rail_Roof_{tag}", pts, "chrome", "top", width=0.012, height=0.006))
    return objs


def build_extras(sd, surf):
    """Fasteners, plates, vents and brackets that give the large surfaces a finished read."""
    b = sd.b
    objs = []
    nose = surf_nose_x(sd, TRUCK_NOSE)
    xb = nose - 0.075
    for sign, tag in ((1, "L"), (-1, "R")):
        objs.append(P.rbox(b, f"Truck_BumperEnd_{tag}", (0.085, 0.075, 0.225), "chrome", 0.016,
                           matrix=Matrix.Translation((xb + 0.095, sign * 0.935, BUMPER_Z))))
    for k, y in enumerate((-0.80, -0.30, 0.30, 0.80)):
        objs.append(P.rbox(b, f"Truck_BumperBolt_{k}", (0.010, 0.024, 0.024), "dark", 0.004,
                           matrix=Matrix.Translation((xb - 0.034, y, BUMPER_Z))))
    objs.append(P.rbox(b, "Truck_PlateFrame", (0.010, 0.33, 0.17), "dark", 0.004,
                       matrix=Matrix.Translation((xb - 0.036, 0.0, BUMPER_Z))))
    objs.append(P.rbox(b, "Truck_Plate", (0.006, 0.30, 0.14), "chrome", 0.002,
                       matrix=Matrix.Translation((xb - 0.044, 0.0, BUMPER_Z))))
    # cowl vents: slatted openings at the base of each hood
    for name, (xa, xz, hy) in COWL_VENTS.items():
        for k in range(5):
            x = xa + (xz - xa) * (k + 0.5) / 5
            hit, n = sd.s.top(x, 0.0)
            objs.append(P.rbox(b, f"{name}_CowlSlat_{k}", (0.0055, 2 * hy - 0.04, 0.010), "grille", 0.0015,
                               matrix=Matrix.Translation(hit + Vector((0, 0, 0.0035)))))
    # cab marker lamp bases
    for k, y in enumerate((-0.22, 0.0, 0.22)):
        p, n = sd.top_pt(T.X(458), y)
        objs.append(sd.box(f"Roof_MarkerBase_{k}", "chrome", (0.068, 0.134, 0.008), p, n, 0.002,
                           up=(0, 1, 0), lift=-0.002))
    for sign, tag in ((1, "L"), (-1, "R")):
        # mirror mounting plates
        for k, (px, py) in enumerate(((420, 150), (420, 132))):
            p, n = sd.side_pt(px, py, sign)
            objs.append(sd.box(f"Mirror_Truck_Plate_{tag}_{k}", "chrome", (0.050, 0.010, 0.050), p, n,
                               0.003, lift=-0.002))
        p, n = sd.side_pt(617, 158, sign)
        objs.append(sd.box(f"Mirror_Coupe_Plate_{tag}", "dark", (0.050, 0.010, 0.036), p, n, 0.003,
                           lift=-0.002))
    return objs
