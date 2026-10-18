"""Glazing, lamps, vents, door seams, mirrors, tail-plate hardware and roof light bar.

Surface-mounted parts are ray-cast onto the shell so they sit on (and a few mm into) the real surface.
"""
import math

import bmesh
from mathutils import Matrix, Vector

import knifeedge_forms as F
import knifeedge_prims as P
import knifeedge_trace as T
import knifeedge_cage as K

THICK = 0.006


def surf_matrix(loc, nor, along=(1, 0, 0)):
    n = Vector(nor).normalized()
    x = Vector(along) - n * Vector(along).dot(n)
    if x.length < 1e-4:
        x = Vector((0, 1, 0)) - n * n.y
    x.normalize()
    y = n.cross(x)
    m = Matrix(((x.x, y.x, n.x), (x.y, y.y, n.y), (x.z, y.z, n.z))).to_4x4()
    m.translation = Vector(loc)
    return m


def mount(builder, name, surf, origin, direction, size, mat, bevel=0.004, sink=0.004, along=(1, 0, 0),
          poly=None):
    """Box (or extruded polygon) lying on the surface hit by the ray; protrudes size[2]-sink."""
    hit = surf.hit(origin, direction)
    assert hit is not None, name
    loc, nor = hit
    base = loc - nor * sink
    m = surf_matrix(base, nor, along)
    if poly is not None:
        return P.prism(builder, name, poly, mat, size[2], bevel=bevel, matrix=m)
    m = m @ Matrix.Translation((0, 0, size[2] / 2))
    return P.rbox(builder, name, size, mat, bevel=bevel, matrix=m)


def quad_slab(builder, name, corners, thick, mat="glass"):
    """Closed thin slab through four coplanar corners (a, b, c, d in loop order)."""
    pts = [Vector(c) for c in corners]
    n = (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
    bm = bmesh.new()
    lo = [bm.verts.new(p - n * thick / 2) for p in pts]
    hi = [bm.verts.new(p + n * thick / 2) for p in pts]
    bm.faces.new(lo[::-1])
    bm.faces.new(hi)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, name, bm, mat, smooth_angle=60)


def windshield(builder):
    inset = 0.020
    top_c = Vector(K.pt(562, 66, 0))
    base_c = Vector(K.pt(615, T.BASE_PY, 0))
    down = (base_c - top_c).normalized()
    top = top_c + down * inset
    base = base_c - down * 0.035
    dy_top = K.Y_ROOF - inset
    dy_base = K.Y_BASE - inset
    # tilt of the side tubes shortens the glass width a bit; use the bilinear corners
    corners = [(top.x, -dy_top, top.z), (top.x, dy_top, top.z), (base.x, dy_base, base.z), (base.x, -dy_base, base.z)]
    return quad_slab(builder, "Glass_Windshield", corners[::-1], THICK)


def roof_glass(builder):
    z = T.Z(66) - 0.004
    x0, x1 = T.X(482.0), T.X(554.0)
    y0, y1 = 0.115, K.Y_ROOF - 0.020
    for s in (-1, 1):
        a, b = sorted((s * y0, s * y1))
        quad_slab(builder, f"Glass_Roof_{s:+d}", [(x0, a, z), (x1, a, z), (x1, b, z), (x0, b, z)], 0.006)
    P.rbox(builder, "Trim_RoofSpine", (x1 - T.X(455.0), 0.22, 0.034), "paint2", bevel=0.008,
           location=((x1 + T.X(455.0)) / 2, 0, z - 0.004))
    P.rbox(builder, "Trim_RoofRear", (T.X(482.0) - T.X(455.0) - 0.002, 2 * (K.Y_ROOF - 0.01), 0.026), "paint2", bevel=0.006,
           location=((T.X(482.0) + T.X(455.0) - 0.002) / 2, 0, z - 0.002))


def light_bar(builder):
    """Five-pod roof light bar on the windshield header (side view x 556..572, top view y +/-46 px), lamps facing End B."""
    depth = T.W(16.0)
    xc = T.X(564.0)
    zc = T.Z(56.0)
    P.rbox(builder, "Trim_LightBar", (depth, 1.10, 0.21), "iron", bevel=0.012, location=(xc, 0, zc))
    P.rbox(builder, "Trim_LightBarFoot", (depth, 0.80, 0.04), "iron", bevel=0.006, location=(xc, 0, T.Z(66.0) + 0.01))
    for k, y in enumerate((-0.46, -0.23, 0.0, 0.23, 0.46)):
        P.sweep(builder, f"Fine_RoofLamp_{k}", [(xc - depth / 2 + 0.004, y, zc), (xc - depth / 2 - 0.030, y, zc)], "lamp",
                radius=0.050, sides=14)


def mirrors(builder):
    for s in (-1, 1):
        P.sweep(builder, f"Fine_MirrorStalk_{s:+d}", [K.pt(612, 111, s * 0.66), K.pt(600, 107, s * 0.74)], "iron",
                radius=0.012, sides=8)
        P.rbox(builder, f"Fine_Mirror_{s:+d}", (0.11, 0.17, 0.10), "paint", bevel=0.025, segments=2,
               location=(T.X(595.0), s * 0.79, T.Z(108.0)))


def front_detail(builder, surf):
    # twin triangular hood vents
    L = T.W(51.0)
    for s in (-1, 1):
        poly = [(-L / 2, -0.11), (-L / 2, 0.11), (L / 2, 0.0)]
        mount(builder, f"Fine_HoodVent_{s:+d}", surf, (T.X(681.5), s * 0.43, 2.0), (0, 0, -1), (L, 0.22, 0.012), "iron",
              bevel=0.003, sink=0.006, poly=poly)
        for k in range(3):
            mount(builder, f"Fine_HoodLouvre_{s:+d}_{k}", surf, (T.X(670.0 + 9.0 * k), s * 0.43, 2.0), (0, 0, -1),
                  (0.03, 0.13 - 0.034 * k, 0.012), "steel", bevel=0.002, sink=0.004)
    mount(builder, "Fine_Badge", surf, (T.X(738.0), 0, 2.0), (0, 0, -1), (0.07, 0.07, 0.012), "steel", bevel=0.003)
    for s in (-1, 1):
        # angled LED headlamp slit on the nose, three short segments following the curved nose
        for k, (y, ln) in enumerate(((0.36, 0.16), (0.50, 0.14), (0.63, 0.12))):
            mount(builder, f"Fine_LedStrip_{s:+d}_{k}", surf, (4.0, s * y, T.Z(166.0 - 3.0 * k)), (-1, 0, 0), (0.04, ln, 0.012),
                  "lamp", bevel=0.002, sink=0.006, along=(0, s, 0))
        mount(builder, f"Fine_NoseIntake_{s:+d}", surf, (T.X(729.0), s * 3.0, T.Z(176.0)), (0, -s, 0), (0.34, 0.26, 0.014),
              "iron", bevel=0.003, sink=0.012,
              poly=[(x, y * -s) for x, y in ((-0.17, -0.12), (0.17, -0.06), (0.17, 0.10), (-0.17, 0.13))])
        mount(builder, f"Fine_SkirtScoop_{s:+d}", surf, (T.X(522.0), s * 3.0, T.Z(179.0)), (0, -s, 0), (1.45, 0.07, 0.012),
              "iron", bevel=0.003, sink=0.006)
        mount(builder, f"Fine_DoorHandle_{s:+d}", surf, (T.X(511.0), s * 3.0, T.Z(125.0)), (0, -s, 0), (0.17, 0.035, 0.022),
              "steel", bevel=0.006, sink=0.004)
        seam = [(498, 120), (498, 130), (520, 164), (592, 167), (616, 133), (611, 120)]
        pts = []
        for px, py in seam:
            loc, nor = surf.hit((T.X(px), s * 3.0, T.Z(py)), (0, -s, 0))
            pts.append(loc - nor * 0.002)
        P.sweep(builder, f"Fine_DoorSeam_{s:+d}", pts, "iron", radius=0.0035, sides=4)
    mount(builder, "Fine_NoseGrille", surf, (4.0, 0, T.Z(179.0)), (-1, 0, 0), (0.62, 0.11, 0.014), "iron",
          bevel=0.004, sink=0.01, along=(0, 1, 0))


def deck_detail(builder):
    """Recessed inset panel (top view trapezium x 327..384) and louver slats on the rear deck slope."""
    ang = math.atan2(T.Z(T.slope_py(454.0)) - T.Z(T.slope_py(322.0)), T.X(454.0) - T.X(322.0))
    top_off = 0.028 + 0.02 - 0.004  # deck centre line sits 28 mm under the slope line; panel top is 20 mm above it

    def on_deck(px, lift):
        x = T.X(px)
        z = T.Z(T.slope_py(px)) - 0.028
        return Matrix.Translation((x, 0, z + lift)) @ Matrix.Rotation(-ang, 4, "Y")

    del top_off
    P.rbox(builder, "Trim_DeckInset", (T.W(57.0), 2 * T.W(35.0), 0.012), "iron", bevel=0.004, matrix=on_deck(355.5, 0.020))
    for k in range(7):
        P.rbox(builder, f"Fine_DeckLouver_{k}", (0.035, 2 * T.W(44.0), 0.014), "accent", bevel=0.004,
               matrix=on_deck(394.0 + 8.0 * k, 0.026))


def tail_detail(builder):
    plate_rear = T.X(311.5)
    # mesh grille with slats
    P.rbox(builder, "Fine_TailGrille", (0.02, 0.54, 0.22), "iron", bevel=0.004, location=(plate_rear - 0.008, 0, T.Z(131.0)))
    for k in range(5):
        P.rbox(builder, f"Fine_TailSlat_{k}", (0.012, 0.52, 0.012), "steel", bevel=0.002,
               location=(plate_rear - 0.022, 0, T.Z(131.0) - 0.085 + k * 0.042))
    for s in (-1, 1):
        P.rbox(builder, f"Fine_TailBezel_{s:+d}", (0.02, 0.35, 0.22), "iron", bevel=0.01, segments=2,
               location=(plate_rear - 0.008, s * 0.365, 0.92))
        for y, r in ((0.30, 0.065), (0.43, 0.055)):
            P.sweep(builder, f"Fine_TailLamp_{s:+d}_{int(y * 100)}", [(plate_rear - 0.016, s * y, 0.92),
                                                                      (plate_rear - 0.044, s * y, 0.92)], "lamp", radius=r, sides=16)
        # winch bracket
        P.rbox(builder, f"Fine_WinchBracket_{s:+d}", (T.W(10.0), 0.025, 0.20), "iron", bevel=0.004,
               location=(plate_rear - T.W(2.0), s * 0.245, T.Z(154.0)))
    P.sweep(builder, "Fine_WinchDrum", [(T.X(306.0), -0.23, T.Z(154.0)), (T.X(306.0), 0.23, T.Z(154.0))], "steel", radius=0.075,
            sides=18)
    for s in (-1, 1):
        P.sweep(builder, f"Fine_WinchFlange_{s:+d}", [(T.X(306.0), s * 0.20, T.Z(154.0)), (T.X(306.0), s * 0.23, T.Z(154.0))],
                "iron", radius=0.095, sides=18)
    # skid plate under the tail
    ang = math.atan2(T.W(12.0), T.W(18.0))
    m = Matrix.Translation((T.X(308.0), 0, T.Z(166.0))) @ Matrix.Rotation(ang, 4, "Y")
    P.rbox(builder, "Fine_SkidPlate", (T.W(22.0), 0.84, 0.024), "iron", bevel=0.006, matrix=m)


def build(builder, shell):
    surf = F.Surface([shell])
    windshield(builder)
    roof_glass(builder)
    light_bar(builder)
    mirrors(builder)
    front_detail(builder, surf)
    tail_detail(builder)
    deck_detail(builder)
