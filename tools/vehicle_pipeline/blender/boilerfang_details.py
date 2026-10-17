"""Lamps, grilles, bumpers, guards, seams, trim, mirrors and wipers seated on the Boilerfang shell.

Front-elevation coordinates come from the dodge.jpg sheet: Ram B is centred on px 137.5 and the
Conquest A on px 892.5 (ground y 237); `ty`/`cy` turn an elevation x into a lateral offset (m)
and `Z` turns an elevation/side y into height, with the same scale as the side elevation.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import boilerfang_cuts as K
import boilerfang_prims as P
import boilerfang_trace as T

TRUCK_NOSE = -1  # front-cast sign
COUPE_NOSE = 1
S = T.SCALE
Z = T.Z
CT, CC = 137.5, 892.5


def ty(px):
    return abs(px - CT) * S


def cy(px):
    return abs(px - CC) * S


def rect_yz(y0, y1, z0, z1, r=0.012, steps=2):
    """Rounded rectangle outline in the y/z plane (x left 0) for front-mode cutters."""
    w, h = y1 - y0, z1 - z0
    pts = P.rounded_rect(w, h, min(r, w / 2.2, h / 2.2), steps)
    return [Vector((0.0, (y0 + y1) / 2 + a, (z0 + z1) / 2 + b)) for a, b in pts]


def rect_xy(x0, x1, y0, y1, r=0.01):
    w, h = x1 - x0, y1 - y0
    pts = P.rounded_rect(w, h, min(r, w / 2.2, h / 2.2), 2)
    return [Vector(((x0 + x1) / 2 + a, (y0 + y1) / 2 + b, 0.0)) for a, b in pts]


# Front-face pockets: (name, y0, y1, z0, z1, depth). Elevation measurements, metres.
TRUCK_POCKETS = [
    ("Grille", -ty(192), ty(192), Z(166), Z(136), 0.070),
    ("HeadL", 0.65, 0.93, Z(174), Z(139.5), 0.040),
    ("HeadR", -0.93, -0.65, Z(174), Z(139.5), 0.040),
]
COUPE_POCKETS = [
    ("LampBezelL", 0.36, 0.79, Z(196), Z(185.5), 0.040),
    ("LampBezelR", -0.79, -0.36, Z(196), Z(185.5), 0.040),
    ("NoseGrille", -0.78, 0.78, Z(169), Z(163), 0.030),
]
# Pop-up headlamp doors on the hood nose: x range (px, side elevation) and |y| range (m).
POPUP_X = (T.X(711), T.X(738))
POPUP_Y = (cy(CC - 44.5), cy(CC - 73.5))
HOOD_BULGE = (T.X(630), T.X(706))


def detail_cutters(builder, surface):
    seam_cutters(builder, surface)
    for name, y0, y1, z0, z1, depth in TRUCK_POCKETS:
        K.make_recess_cutter(builder, f"Cutter_Truck_{name}", rect_yz(y0, y1, z0, z1), "front",
                             surface, TRUCK_NOSE, depth)
    for name, y0, y1, z0, z1, depth in COUPE_POCKETS:
        K.make_recess_cutter(builder, f"Cutter_Coupe_{name}", rect_yz(y0, y1, z0, z1), "front",
                             surface, COUPE_NOSE, depth)
    popup_seams(builder, surface)


SEAM_W = 0.0045
HANDLES = (("Truck", 513, 133.5), ("Coupe", 558, 150))
# door shut lines: name -> (px, py bottom, py top)
DOOR_SEAMS = {"TruckFront": (437, 194, 124), "TruckRear": (529, 194, 124),
              "CoupeFront": (600, 204, 142)}
COWL_VENTS = {"Truck": (T.X(406), T.X(415), 0.60), "Coupe": (T.X(613), T.X(622), 0.62)}


def _thin_rect(a0, a1, b0, b1):
    return [Vector((a0, 0.0, b0)), Vector((a1, 0.0, b0)), Vector((a1, 0.0, b1)), Vector((a0, 0.0, b1))]


def _thin_rect_xy(x, half_y):
    return [Vector((x - SEAM_W / 2, -half_y, 0)), Vector((x + SEAM_W / 2, -half_y, 0)),
            Vector((x + SEAM_W / 2, half_y, 0)), Vector((x - SEAM_W / 2, half_y, 0))]


def _groove_xy(builder, surface, name, x0, x1, y0, y1):
    y0, y1 = sorted((y0, y1))
    K.make_recess_cutter(builder, name,
                         [Vector((x0, y0, 0)), Vector((x1, y0, 0)), Vector((x1, y1, 0)),
                          Vector((x0, y1, 0))], "top", surface, 1, 0.0035, step=0.2,
                         boundary_step=0.05)


def popup_seams(builder, surface):
    """Shut lines that outline the closed pop-up headlamp doors on the Conquest nose."""
    x0, x1 = POPUP_X
    ya, yb = POPUP_Y
    w = SEAM_W
    for sign, tag in ((1, "L"), (-1, "R")):
        lo, hi = sorted((sign * ya, sign * yb))
        _groove_xy(builder, surface, f"Cutter_Seam_Popup_{tag}_Front", x1 - w, x1, lo, hi)
        _groove_xy(builder, surface, f"Cutter_Seam_Popup_{tag}_Back", x0, x0 + w, lo, hi)
        _groove_xy(builder, surface, f"Cutter_Seam_Popup_{tag}_In", x0, x1, sign * ya - w / 2 * sign,
                   sign * ya + w / 2 * sign)
        _groove_xy(builder, surface, f"Cutter_Seam_Popup_{tag}_Out", x0, x1,
                   sign * yb - w / 2 * sign, sign * yb + w / 2 * sign)


def seam_cutters(builder, surface):
    """True shut-line grooves: door fronts/rears, rocker line and hood panels."""
    for sign, tag in ((1, "L"), (-1, "R")):
        for name, (px, py0, py1) in DOOR_SEAMS.items():
            x = T.X(px)
            K.make_recess_cutter(builder, f"Cutter_Seam_{name}_{tag}",
                                 _thin_rect(x - SEAM_W / 2, x + SEAM_W / 2, T.Z(py0), T.Z(py1)),
                                 "side", surface, sign, 0.0035, step=0.2, boundary_step=0.05)
        z = T.Z(197)
        K.make_recess_cutter(builder, f"Cutter_Seam_Rocker_{tag}",
                             _thin_rect(T.X(437), T.X(600), z - SEAM_W / 2, z + SEAM_W / 2),
                             "side", surface, sign, 0.0035, step=0.2, boundary_step=0.05)
        for hname, px, py in HANDLES:
            xc, zc = T.X(px), T.Z(py)
            K.make_recess_cutter(builder, f"Cutter_HandlePocket_{hname}_{tag}",
                                 _thin_rect(xc - 0.10, xc + 0.10, zc - 0.034, zc + 0.034),
                                 "side", surface, sign, 0.022, step=0.2, boundary_step=0.04)
    # hood panel gaps (top surface grooves)
    for name, (pa, pb, inset) in {"Truck": (304.0, 410.0, 0.07), "Coupe": (622.0, 712.0, 0.07)}.items():
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


def _matrix(point, normal, up=(0, 0, 1)):
    return Matrix.Translation(point) @ P.frame(normal, up)


class Seat:
    """Convenience wrappers: seat primitives on the evaluated (cut) shell.

    Positions come from the cut shell; orientations come from `ref`, the uncut mirrored cage,
    so the Boolean's left/right retriangulation cannot tilt one side's hardware."""

    def __init__(self, builder, surface, ref=None):
        self.b = builder
        self.s = surface
        self.ref = ref or surface

    def box(self, name, mat, size, point, normal, bevel=0.006, up=(0, 0, 1), lift=0.0,
            segments=1):
        m = _matrix(Vector(point) + Vector(normal).normalized() * lift, normal, up)
        return P.rbox(self.b, name, size, mat, bevel=bevel, segments=segments, matrix=m,
                      offset=(0, 0, size[2] / 2))

    def side_pt(self, px, py, sign, lift=0.0):
        hit, _ = self.s.side(T.X(px), T.Z(py), sign)
        _, n = self.ref.side(T.X(px), T.Z(py), sign)
        return hit + n * lift, n

    def top_pt(self, x, y, lift=0.0):
        hit, _ = self.s.top(x, y)
        _, n = self.ref.top(x, y)
        return hit + n * lift, n

    def front_pt(self, y, z, sign, lift=0.0):
        hit, _ = self.s.front(y, z, sign)
        _, n = self.ref.front(y, z, sign)
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


def surf_nose_x(sd, sign):
    hit, _ = sd.s.front(0.0, Z(180) if sign == COUPE_NOSE else Z(190), sign)
    return hit.x


def lens(sd, name, mat, y, z, w, h, sign, thick=0.014, lift=0.004, r=0.008):
    p, n = sd.front_pt(y, z, sign)
    return P.prism(sd.b, name, P.rounded_rect(w, h, r, 2), mat, thick, 0.003,
                   matrix=_matrix(p + n * lift, n))


def bezel_bars(sd, name, y0, y1, z0, z1, mat, sign, t=0.016, depth=0.016, grow=0.010):
    """Four chrome bars framing a nose pocket; the nose cap is planar so bars are axis-aligned."""
    nose = surf_nose_x(sd, sign)
    xc = nose - sign * (depth / 2 - 0.004)
    y0, y1, z0, z1 = y0 - grow, y1 + grow, z0 - grow, z1 + grow
    yc, zc = (y0 + y1) / 2, (z0 + z1) / 2
    objs = []
    for k, (cy_, cz_, sy, sz) in enumerate(((yc, z1 + t / 2 - 0.002, y1 - y0 + 2 * t, t),
                                            (yc, z0 - t / 2 + 0.002, y1 - y0 + 2 * t, t),
                                            (y0 - t / 2 + 0.002, zc, t, z1 - z0),
                                            (y1 + t / 2 - 0.002, zc, t, z1 - z0))):
        objs.append(P.rbox(sd.b, f"{name}_{k}", (depth, sy, sz), mat, 0.004,
                           matrix=Matrix.Translation((xc, cy_, cz_))))
    return objs


def hood_bulge(sd):
    """Raised power bulge of the Conquest hood with a recessed scoop slot at its front end."""
    x0, x1 = HOOD_BULGE
    n_st, n_y = 12, 9
    bm = bmesh.new()
    rings = []
    for k in range(n_st + 1):
        t = k / n_st
        x = x0 + (x1 - x0) * t
        hw = 0.314 - 0.040 * t
        h = 0.004 + 0.032 * min(1.0, t * 3.0)
        top, bot = [], []
        for i in range(n_y):
            u = -1 + 2 * i / (n_y - 1)
            y = u * hw
            hit, _ = sd.s.top(x, y)
            top.append(bm.verts.new((x, y, hit.z + h * (1 - abs(u) ** 2.4) - 0.0006)))
            bot.append(bm.verts.new((x, y, hit.z - 0.012)))
        rings.append(top + list(reversed(bot)))
    m = len(rings[0])
    for k in range(n_st):
        a, b = rings[k], rings[k + 1]
        for i in range(m):
            bm.faces.new((a[i], a[(i + 1) % m], b[(i + 1) % m], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    front = bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    # scoop slot: inset the front wall and push the inner face back into the bulge (dark liner)
    inset = bmesh.ops.inset_region(bm, faces=[front], thickness=0.0085, depth=-0.022,
                                   use_even_offset=True)
    for f in inset["faces"]:
        f.material_index = 1
    front.material_index = 1
    bm.faces.ensure_lookup_table()
    return [P.finish(sd.b, "Coupe_HoodBulge", bm, ["paint", "grille"], smooth_angle=40)]


def build_truck_end(sd, surf):
    b = sd.b
    objs = []
    # crosshair grille: black recess already cut; chrome surround, centre cross and 3x2 egg-crate
    gy = ty(192)
    z0, z1 = Z(166), Z(136)
    zc = (z0 + z1) / 2
    objs.extend(bezel_bars(sd, "Truck_GrilleSurround", -gy, gy, z0, z1, "chrome", TRUCK_NOSE, t=0.024))
    for k, px in enumerate((102, 119, 156, 173)):
        y = (px - CT) * S
        p, n = sd.front_pt(y, zc, TRUCK_NOSE)
        objs.append(sd.box(f"Truck_GrilleBarV_{k}", "grille", (0.010, z1 - z0 - 0.01, 0.030), p, n,
                           0.002, lift=0.0))
    for k, py in enumerate((144, 158)):
        p, n = sd.front_pt(0.0, Z(py), TRUCK_NOSE)
        objs.append(sd.box(f"Truck_GrilleBarH_{k}", "grille", (2 * gy - 0.01, 0.010, 0.030), p, n,
                           0.002, lift=0.0))
    p, n = sd.front_pt(0.0, zc, TRUCK_NOSE)
    objs.append(sd.box("Truck_GrilleCrossV", "chrome", (0.050, z1 - z0 - 0.008, 0.042), p, n, 0.005,
                       lift=0.0))
    p, n = sd.front_pt(0.0, Z(151), TRUCK_NOSE)
    objs.append(sd.box("Truck_GrilleCrossH", "chrome", (2 * gy - 0.008, 0.044, 0.042), p, n, 0.005,
                       lift=0.0))
    for k, sgn in enumerate((-1, 1)):
        p, n = sd.front_pt(sgn * 0.245, Z(172), TRUCK_NOSE)
        objs.append(sd.box(f"Truck_ValanceSlot_{k}", "grille", (0.41, 0.036, 0.008), p, n, 0.002,
                           lift=-0.002))
    # single rectangular sealed-beam lamps and amber parking/turn lamps in chrome bezels
    for tag, sgn in (("L", 1), ("R", -1)):
        yc = sgn * 0.805
        objs.append(lens(sd, f"Truck_Headlamp_{tag}", "lamp", yc, Z(152), 0.215, 0.150, TRUCK_NOSE,
                         thick=0.014, lift=0.004))
        objs.append(lens(sd, f"Truck_Signal_{tag}", "amber", yc, Z(168.5), 0.235, 0.075, TRUCK_NOSE,
                         thick=0.012, lift=0.004, r=0.006))
        lo, hi = sorted((sgn * 0.65, sgn * 0.93))
        objs.extend(bezel_bars(sd, f"Truck_Bezel_{tag}", lo, hi, Z(174), Z(139.5), "chrome", TRUCK_NOSE,
                               t=0.014, grow=0.006))
        objs.append(P.rbox(b, f"Truck_BezelMid_{tag}", (0.014, hi - lo + 0.016, 0.012), "chrome", 0.003,
                           matrix=Matrix.Translation((surf_nose_x(sd, TRUCK_NOSE) - 0.003,
                                                      (lo + hi) / 2, Z(162)))))
    # chrome wrap bumper swept in plan, overriders (vertical guards), plate and valance
    nose_x = surf_nose_x(sd, TRUCK_NOSE)
    xb = nose_x - 0.14
    zb = Z(187.5)
    path = [(xb + 0.19, -0.985, zb), (xb + 0.09, -0.95, zb), (xb + 0.03, -0.88, zb), (xb, -0.78, zb),
            (xb, 0.78, zb), (xb + 0.03, 0.88, zb), (xb + 0.09, 0.95, zb), (xb + 0.19, 0.985, zb)]
    prof = P.rounded_rect(0.070, 0.262, 0.016, 3)
    objs.append(P.sweep(b, "Truck_Bumper_Chrome", path, "chrome", profile=prof, up=(0, 0, 1)))
    objs.append(P.rbox(b, "Truck_BumperCrease", (0.012, 1.46, 0.014), "dark", 0.003,
                       matrix=Matrix.Translation((xb - 0.036, 0.0, Z(185.5)))))
    for sgn in (-1, 1):
        y = sgn * 0.50
        objs.append(P.rbox(b, f"Truck_PushGuard_{sgn:+d}", (0.060, 0.090, 0.350), "chrome", 0.018,
                           matrix=Matrix.Translation((xb - 0.050, y, Z(185.5)))))
        objs.append(P.rbox(b, f"Truck_PushGuardPad_{sgn:+d}", (0.014, 0.050, 0.240), "rubber", 0.004,
                           matrix=Matrix.Translation((xb - 0.082, y, Z(185.5)))))
        objs.append(P.rbox(b, f"Truck_BumperBracket_{sgn:+d}", (0.090, 0.070, 0.070), "dark", 0.008,
                           matrix=Matrix.Translation((xb + 0.075, sgn * 0.74, zb - 0.150))))
    objs.append(P.rbox(b, "Truck_PlateFrame", (0.010, 0.370, 0.190), "dark", 0.004,
                       matrix=Matrix.Translation((xb - 0.040, 0.0, Z(190)))))
    objs.append(P.rbox(b, "Truck_Plate", (0.006, 0.330, 0.160), "chrome", 0.002,
                       matrix=Matrix.Translation((xb - 0.046, 0.0, Z(190)))))
    objs.append(P.rbox(b, "Truck_Valance", (0.070, 1.48, 0.050), "dark", 0.008,
                       matrix=Matrix.Translation((nose_x - 0.02, 0.0, Z(201.5)))))
    # hood ornament
    p, n = sd.top_pt(T.X(300.0), 0.0)
    orn = [(-0.060, 0.0), (0.050, 0.0), (0.056, 0.016), (0.030, 0.040), (-0.004, 0.052), (-0.040, 0.034)]
    om = Matrix.Translation(p + Vector((0, 0, -0.004))) @ Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    objs.append(P.prism(b, "Truck_HoodOrnament", orn, "chrome", 0.020, 0.003, matrix=om, z0=-0.010))
    pts = [(T.X(299.5), y / 20 * 0.80) for y in range(-20, 21)]
    objs.append(sd.ribbon("Truck_HoodEdgeTrim", pts, "chrome", "top", width=0.014, height=0.005))
    return objs


def build_coupe_end(sd, surf):
    b = sd.b
    objs = []
    nose_x = surf_nose_x(sd, COUPE_NOSE)
    # closed pop-up headlamp doors: lens strip on the leading edge, hinge bar on the rear edge
    x0, x1 = POPUP_X
    ya, yb = POPUP_Y
    for sgn, tag in ((1, "L"), (-1, "R")):
        yc = sgn * (ya + yb) / 2
        p, n = sd.top_pt(x1 + 0.016, yc)
        objs.append(sd.box(f"Coupe_PopupLens_{tag}", "lamp", (0.020, yb - ya - 0.06, 0.010), p, n,
                           0.003, up=(0, 1, 0), lift=-0.002))
    objs.extend(hood_bulge(sd))
    # bumper-cover lamp pockets: round fog lamp outboard, amber turn signal inboard
    for tag, sgn in (("L", 1), ("R", -1)):
        objs.append(lens(sd, f"Coupe_Fog_{tag}", "lamp", sgn * 0.71, Z(190.7), 0.105, 0.088, COUPE_NOSE,
                         thick=0.012, lift=0.004, r=0.020))
        objs.append(lens(sd, f"Coupe_Signal_{tag}", "amber", sgn * 0.505, Z(190.7), 0.215, 0.088,
                         COUPE_NOSE, thick=0.012, lift=0.004, r=0.008))
        lo, hi = sorted((sgn * 0.36, sgn * 0.79))
        objs.append(frame_ribbon(sd, f"Coupe_Bezel_{tag}", lo, hi, Z(196), Z(185.5), 0.008, "dark",
                                 COUPE_NOSE, 0.012, 0.006))
    # lower air dam: swept cover under the bumper, intake mouth, side ducts and chin lip
    zd = Z(206.5)
    x_dam = T.X(747.0)
    xs = [T.X(px) for px in (714, 726, 738)]
    path = [(xs[0], -0.90, zd), (xs[1], -0.88, zd), (xs[2], -0.80, zd), (x_dam - 0.03, -0.62, zd),
            (x_dam, -0.30, zd), (x_dam, 0.30, zd), (x_dam - 0.03, 0.62, zd), (xs[2], 0.80, zd),
            (xs[1], 0.88, zd), (xs[0], 0.90, zd)]
    prof = P.rounded_rect(0.080, 0.250, 0.016, 3)
    objs.append(P.sweep(b, "Coupe_AirDam", path, "paint2", profile=prof, up=(0, 0, 1)))
    xf = x_dam + 0.040
    objs.append(P.rbox(b, "Coupe_IntakeMouth", (0.014, 0.78, 0.180), "grille", 0.006,
                       matrix=Matrix.Translation((xf, 0.0, Z(202.5)))))
    for k in range(4):
        objs.append(P.rbox(b, f"Coupe_IntakeSlat_{k}", (0.020, 0.74, 0.012), "dark", 0.003,
                           matrix=Matrix.Translation((xf + 0.004, 0.0, Z(197 + 3.4 * k)))))
    objs.append(P.rbox(b, "Coupe_ChinLip", (0.090, 1.10, 0.026), "dark", 0.008,
                       matrix=Matrix.Translation((x_dam - 0.010, 0.0, Z(217)))))
    objs.append(P.rbox(b, "Coupe_BumperRub", (0.012, 1.45, 0.014), "dark", 0.003,
                       matrix=Matrix.Translation((nose_x + 0.001, 0.0, Z(196.5)))))
    # cab-back window and trim on the sloped wall of the roof step (faces the Conquest end)
    zc = T.Z(84.5)
    outline = [Vector((0.0, y, z)) for y, z in ((-0.48, zc - 0.056), (0.48, zc - 0.056),
                                                (0.48, zc + 0.056), (-0.48, zc + 0.056))]
    objs.append(K.glass_panel(sd.b, "Glass_CabRear", outline, sd.s,
                              lambda q: ((4.0, q.y, q.z), (-1, 0, 0)),
                              0.003, step=0.05, axes=(1, 2)))
    objs.append(frame_ribbon(sd, "Cab_RearGlassTrim", -0.49, 0.49, zc - 0.0575, zc + 0.0575, 0.012,
                             "chrome", COUPE_NOSE, 0.014, 0.004, radius=0.012))
    return objs


def build_sides(sd, surf):
    b = sd.b
    objs = []
    for sign, tag in ((1, "L"), (-1, "R")):
        for name, px, py in HANDLES:
            p, n = sd.side_pt(px, py, sign)
            objs.append(sd.box(f"Handle_{name}_{tag}", "chrome", (0.15, 0.026, 0.024), p, n, 0.008,
                               lift=0.007))
        # rocker moulding (dark body with a chrome edge) between the shut line and the sill
        mold_z = T.Z(T.lerp_table(T.SILL, 500)) + 0.075
        side_y = T.half_width(500) + 0.008
        x_a, x_b = T.X(437), T.X(600)
        objs.append(P.rbox(b, f"Molding_Rocker_{tag}", (x_b - x_a, 0.024, 0.085), "dark", 0.007,
                           matrix=Matrix.Translation(((x_a + x_b) / 2, sign * side_y, mold_z))))
        objs.append(P.rbox(b, f"Molding_RockerChrome_{tag}", (x_b - x_a, 0.006, 0.014), "chrome", 0.002,
                           matrix=Matrix.Translation(((x_a + x_b) / 2, sign * (side_y + 0.012),
                                                      mold_z + 0.052))))
        # flare lips around both arches
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
        # red reflectors (thin) and amber side markers (thin, seated flush)
        for name, px, py in (("A", 414, 188), ("B", 592, 186)):
            p, n = sd.side_pt(px, py, sign)
            objs.append(sd.box(f"Reflector_{name}_{tag}", "marker", (0.060, 0.022, 0.010), p, n, 0.003,
                               lift=-0.002))
        for name, px, py, length in (("Truck", 307, 184, 0.16),):
            p, n = sd.side_pt(px, py, sign)
            objs.append(sd.box(f"Marker_{name}_{tag}", "amber", (length, 0.034, 0.010), p, n, 0.003,
                               lift=-0.002))
        # RAM script block on the front fender and body-side crease mouldings
        p, n = sd.side_pt(415, 149, sign)
        objs.append(sd.box(f"Truck_Badge_{tag}", "chrome", (0.27, 0.036, 0.008), p, n, 0.003,
                           lift=-0.002))
        pts = [(T.X(404 + (529 - 404) * k / 12), T.Z(174)) for k in range(13)]
        objs.append(sd.ribbon(f"Molding_Flank_{tag}", pts, "dark", "side", width=0.030, height=0.007,
                              sign=sign, lift=0.0))
        pts = [(T.X(404 + (529 - 404) * k / 12), T.Z(174) + 0.019) for k in range(13)]
        objs.append(sd.ribbon(f"Molding_FlankChrome_{tag}", pts, "chrome", "side", width=0.006,
                              height=0.004, sign=sign, lift=0.007))
        pts = [(T.X(548 + (595 - 548) * k / 10), T.Z(176.5)) for k in range(11)]
        objs.append(sd.ribbon(f"Molding_Coupe_{tag}", pts, "dark", "side", width=0.034, height=0.007,
                              sign=sign, lift=0.0))
        # chrome belt moulding under the side glass
        for name, a, c, py0, py1 in (("Truck", 455, 525, 122.5, 122.5), ("Coupe", 553, 592, 138.5, 138.5)):
            pts = [(T.X(a + (c - a) * k / 10), T.Z(py0 + (py1 - py0) * k / 10)) for k in range(11)]
            objs.append(sd.ribbon(f"Molding_Belt_{name}_{tag}", pts, "chrome", "side", width=0.012,
                                  height=0.004, sign=sign, lift=0.0015))
        # cab running board with two brackets (silver step under the rear half of the Ram cab)
        xa, xz = T.X(486), T.X(545)
        objs.append(P.rbox(b, f"Truck_Step_{tag}", (xz - xa, 0.090, 0.034), "chrome", 0.008,
                           matrix=Matrix.Translation(((xa + xz) / 2, sign * (T.half_width(515) + 0.040),
                                                      T.Z(209)))))
        for k, px in enumerate((492, 538)):
            objs.append(P.rbox(b, f"Truck_StepBracket_{tag}_{k}", (0.050, 0.075, 0.040), "dark", 0.006,
                               matrix=Matrix.Translation((T.X(px), sign * (T.half_width(px) + 0.012),
                                                          T.Z(207)))))
    return objs


def build_mirrors(sd, surf):
    b = sd.b
    objs = []
    for sign, tag in ((1, "L"), (-1, "R")):
        # Ram: tall rectangular chrome mirror on a pedestal that rises from the door belt
        mx, my, mz = T.X(466), sign * 1.095, T.Z(116)
        pz = T.Z(131)
        objs.append(P.rbox(b, f"Mirror_Truck_Pedestal_{tag}", (0.065, 0.065, 0.120), "chrome", 0.008,
                           matrix=Matrix.Translation((mx, sign * 1.035, pz + 0.025))))
        objs.append(P.rbox(b, f"Mirror_Truck_Body_{tag}", (0.090, 0.170, 0.230), "chrome", 0.010,
                           matrix=Matrix.Translation((mx, my, mz))))
        objs.append(P.rbox(b, f"Mirror_Truck_Glass_{tag}", (0.006, 0.120, 0.170), "glass", 0.002,
                           matrix=Matrix.Translation((mx + 0.0465, my, mz))))
        # Conquest: wide body-colour aero mirror on a stem at the base of the A-pillar
        cxm, cym, czm = T.X(603), sign * 1.055, T.Z(131)
        objs.append(P.rbox(b, f"Mirror_Coupe_Gusset_{tag}", (0.140, 0.085, 0.100), "paint2", 0.015,
                           matrix=Matrix.Translation((T.X(606), sign * 1.020, 1.170))))
        objs.append(P.rbox(b, f"Mirror_Coupe_Body_{tag}", (0.200, 0.190, 0.110), "paint2", 0.012,
                           matrix=Matrix.Translation((cxm, cym, czm))))
        objs.append(P.rbox(b, f"Mirror_Coupe_Glass_{tag}", (0.006, 0.140, 0.070), "glass", 0.002,
                           matrix=Matrix.Translation((cxm - 0.1035, cym, czm))))
    return objs


def build_wipers_and_roof(sd, surf):
    b = sd.b
    objs = []
    # parked wipers at the base of each windshield, pivots on the cowl below the glass
    sets = (("Truck", 425.0, 418.0, ((-0.38, 0.48), (0.27, 0.46))),
            ("Coupe", 600.0, 609.0, ((-0.40, 0.52), (0.28, 0.50))))
    for name, blade_px, pivot_px, blades in sets:
        for k, (yc, length) in enumerate(blades):
            blade_p, n0 = sd.top_pt(T.X(blade_px), yc, 0.009)
            m = Matrix.Translation(blade_p) @ P.frame(n0, (0, 1, 0))
            objs.append(P.rbox(b, f"Wiper_{name}_Blade_{k}", (0.012, length, 0.010), "rubber", 0.003,
                               matrix=m, offset=(0, 0, 0.004)))
            sgn = -1 if yc < 0 else 1
            pivot_y = yc + sgn * length * 0.42
            piv, _ = sd.top_pt(T.X(pivot_px), pivot_y, 0.006)
            objs.append(P.sweep(b, f"Wiper_{name}_Arm_{k}",
                                [piv, blade_p + n0 * 0.008 + Vector((0, sgn * length * 0.40, 0))],
                                "dark", radius=0.0045, sides=6))
    # Ram roof drip rails
    for sign, tag in ((1, "L"), (-1, "R")):
        pts = [(T.X(px), sign * (T.top_half(px) - 0.045)) for px in range(484, 521, 4)]
        objs.append(sd.ribbon(f"Rail_Roof_{tag}", pts, "chrome", "top", width=0.012, height=0.006))
    return objs


def build_extras(sd, surf):
    """Slatted cowl vents and mounting plates that give the large surfaces a finished read."""
    b = sd.b
    objs = []
    for name, (xa, xz, hy) in COWL_VENTS.items():
        for k in range(5):
            x = xa + (xz - xa) * (k + 0.5) / 5
            hit, n = sd.s.top(x, 0.0)
            objs.append(P.rbox(b, f"{name}_CowlSlat_{k}", (0.0045, 2 * hy - 0.04, 0.010), "grille", 0.0015,
                               matrix=Matrix.Translation(hit + Vector((0, 0, 0.0035)))))
    return objs
