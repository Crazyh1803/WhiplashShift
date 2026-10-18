"""Main masses: supercar shell (End A) with wheel arches and cockpit well, rear floor pan, splitter,
rear deck and the End-B tail plate. Everything is mirrored about y=0."""
import math

import bmesh
from mathutils import Matrix, Vector

import knifeedge_core as C
import knifeedge_forms as F
import knifeedge_prims as P
import knifeedge_trace as T

SHELL_STATIONS = [452, 458, 466, 476, 488, 500, 514, 528, 542, 556, 570, 584, 598, 610, 620, 630, 640, 650, 660, 670, 680,
                  690, 700, 710, 720, 728, 736, 743, 749, 753, 756]
POCKET_PX = (492.0, 606.0)
POCKET_HALF = 0.62
POCKET_FLOOR_Z = 0.52
ARCH_CLEAR = 0.070


def shell_ring(px):
    top = T.shell_top_z(px)
    bot = T.shell_bot_z(px)
    w = T.shell_half(px)
    cabin = px < 625
    rt = 0.17 if cabin else min(0.06, w * 0.5)
    crown = 0.0 if cabin else 0.035
    # V-creased hood: a single linear crown segment; the cabin keeps a rounded shoulder
    half, roles = F.section_half(w, bot, top - crown, 0.05, rt, crown, steps=5, crown_steps=4,
                                 split=bot + 0.17, vee=not cabin)
    return F.full_ring(half, roles)


def cutter_object(builder, name, bm):
    """Cutter with guaranteed outward (positive-volume) winding: EXACT booleans ignore an inverted cutter."""
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bm.calc_volume(signed=True) < 0:
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
    return C.bm_to_object(builder, name, bm, ["iron"], col="CUTTERS")


def cutter_cylinder(builder, name, centre, radius, y0, y1, segments=48):
    bm = bmesh.new()
    geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius,
                                 depth=abs(y1 - y0))
    for v in geom["verts"]:
        x, y, z = v.co
        v.co = Vector((centre[0] + x, (y0 + y1) / 2 + z, centre[2] + y))
    return cutter_object(builder, name, bm)


def cutter_box(builder, name, lo, hi):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector(((hi[0] - lo[0]) * v.co.x + (hi[0] + lo[0]) / 2, (hi[1] - lo[1]) * v.co.y + (hi[1] + lo[1]) / 2,
                       (hi[2] - lo[2]) * v.co.z + (hi[2] + lo[2]) / 2))
    return cutter_object(builder, name, bm)


def cutter_poly_xz(builder, name, pts_px, y_half=2.0):
    """Prism through the whole car width over a side-view polygon given in sheet pixels (x, y)."""
    bm = bmesh.new()
    lo = [bm.verts.new((T.X(px), -y_half, T.Z(py))) for px, py in pts_px]
    hi = [bm.verts.new((T.X(px), y_half, T.Z(py))) for px, py in pts_px]
    n = len(pts_px)
    bm.faces.new(lo[::-1])
    bm.faces.new(hi)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    return cutter_object(builder, name, bm)


# rear quarter cutline from the sheet: shell top corner (459,113) rakes forward to (490,162), back to the sill at (452,186)
REAR_CUT_PX = [(430, 100), (459, 113), (490, 162), (452, 186), (430, 190)]


def build_shell(builder):
    stations = []
    rings, roles = None, None
    for px in SHELL_STATIONS:
        ring, roles = shell_ring(px)
        stations.append((T.X(px), ring))
    row_mats = [{3: 2, 1: 1, 0: 0}[r] for r in roles]
    shell = F.loft(builder, "Body_Shell", stations, ["paint", "paint2", "iron"], row_mats=row_mats)
    hub = (T.WHEEL_X["coupe"], T.TRACK_Y["coupe"], T.WHEEL_R["coupe"])
    for side in (-1, 1):
        y0, y1 = (0.60, 1.40) if side > 0 else (-1.40, -0.60)
        cutter = cutter_cylinder(builder, f"Cutter_Arch_{side:+d}", hub, T.WHEEL_R["coupe"] + ARCH_CLEAR, y0, y1)
        C.boolean_difference(shell, cutter)
    C.boolean_difference(shell, cutter_poly_xz(builder, "Cutter_RearQuarter", REAR_CUT_PX))
    well = cutter_box(builder, "Cutter_Well", (T.X(POCKET_PX[0]), -POCKET_HALF, POCKET_FLOOR_Z),
                      (T.X(POCKET_PX[1]), POCKET_HALF, 1.30))
    C.boolean_difference(shell, well)
    C.harden(shell, 35.0)
    return shell


def build_floor(builder):
    """Rear tub floor pan (End B): low rounded slab under the engine and seats."""
    stations = []
    for px in (318, 340, 360, 380, 400, 420, 440, 458):
        w = T.W(T.lerp_table(T.FLOOR_HALF, px))
        zb = T.Z(T.lerp_table(T.FLOOR_BOT, px))
        half, roles = F.section_half(w, zb, zb + T.FLOOR_THICK, 0.03, 0.03, 0.0, steps=2, crown_steps=1)
        stations.append((T.X(px), F.full_ring(half)))
    return F.loft(builder, "Body_Floor", stations, ["iron"])


def build_splitter(builder):
    x0, x1 = T.X(698), T.X(756)
    pts = [(x0, T.W(94)), (T.X(722), T.W(88)), (T.X(744), T.W(52)), (x1, T.W(20)),
           (x1, -T.W(20)), (T.X(744), -T.W(52)), (T.X(722), -T.W(88)), (x0, -T.W(94))]
    return P.prism(builder, "Body_Splitter", pts, "iron", 0.036, bevel=0.006, z0=T.Z(189.5))


def build_deck(builder):
    """Sloped rear deck panel over the engine bay, on the rear slope rail line (End B)."""
    p0, p1 = 322.0, 454.0
    x0, x1 = T.X(p0), T.X(p1)
    z0, z1 = T.Z(T.slope_py(p0)) - 0.028, T.Z(T.slope_py(p1)) - 0.028
    length = math.hypot(x1 - x0, z1 - z0)
    ang = math.atan2(z1 - z0, x1 - x0)
    centre = ((x0 + x1) / 2, 0.0, (z0 + z1) / 2)
    m = Matrix.Translation(centre) @ Matrix.Rotation(-ang, 4, "Y")
    return P.rbox(builder, "Body_Deck", (length, 2 * T.W(T.ROOF_HALF_PX + 1.0), 0.04), "paint2", bevel=0.008, matrix=m)


def build_tail_plate(builder):
    """Vertical End-B tail plate carrying the grille, lamps and bumper hoop (side view x 311.5..317.5)."""
    x = T.X(314.5)
    zb, zt = T.Z(159.0), T.Z(110.0)
    return P.rbox(builder, "Body_TailPlate", (T.W(6.0), 2 * T.W(49.0), zt - zb), "paint", bevel=0.01,
                  location=(x, 0, (zb + zt) / 2))


def build(builder):
    shell = build_shell(builder)
    floor = build_floor(builder)
    build_splitter(builder)
    build_deck(builder)
    build_tail_plate(builder)
    return shell, floor
