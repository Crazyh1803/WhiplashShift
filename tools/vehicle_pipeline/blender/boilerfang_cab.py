"""Cab and cockpit glazing, window frames, doors, stripes and roof skylights.

Glass is a thin closed slab seated 2..5 mm off the flat hull side (or flat windshield slope);
brass frame bars sit on top of it. All of it is mirrored by construction (left = right).
"""
import math

import bmesh
from mathutils import Vector

import boilerfang_body as B
import boilerfang_forms as F
import boilerfang_prims as P
import boilerfang_trace as T

SIDES = (-1, 1)
SEAT = 0.002  # glass inner face stand-off from the hull
THICK = 0.003


def tag(side):
    return f"{side:+d}"


def _cols(px0, px1):
    cols = [px0] + [p for p in B.HULL_PX if px0 < p < px1] + [px1]
    return cols


def slab(builder, name, grid_in, grid_out, mat="glass"):
    """Closed thin solid between two same-topology grids of points (rows x cols)."""
    bm = bmesh.new()
    rows, cols = len(grid_in), len(grid_in[0])
    vi = [[bm.verts.new(p) for p in row] for row in grid_in]
    vo = [[bm.verts.new(p) for p in row] for row in grid_out]
    for r in range(rows - 1):
        for c in range(cols - 1):
            bm.faces.new((vo[r][c], vo[r][c + 1], vo[r + 1][c + 1], vo[r + 1][c]))
            bm.faces.new((vi[r][c], vi[r + 1][c], vi[r + 1][c + 1], vi[r][c + 1]))
    for c in range(cols - 1):
        bm.faces.new((vi[0][c], vi[0][c + 1], vo[0][c + 1], vo[0][c]))
        bm.faces.new((vi[-1][c + 1], vi[-1][c], vo[-1][c], vo[-1][c + 1]))
    for r in range(rows - 1):
        bm.faces.new((vi[r + 1][0], vi[r][0], vo[r][0], vo[r + 1][0]))
        bm.faces.new((vi[r][-1], vi[r + 1][-1], vo[r + 1][-1], vo[r][-1]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, name, bm, mat, smooth_angle=60)


def side_window(builder, name, side, corners):
    """corners = [(px_a, zb_a), (px_b, zb_b), (px_b, zt_b), (px_a, zt_a)]; seated on the flat side."""
    (pa, zba), (pb, zbb), (_, ztb), (_, zta) = corners
    cols = _cols(pa, pb)
    grid_in, grid_out = [], []
    for row in (0, 1):
        gi, go = [], []
        for p in cols:
            t = (p - pa) / (pb - pa)
            z = (zba + (zbb - zba) * t) if row == 0 else (zta + (ztb - zta) * t)
            y = B.side_y(p)
            gi.append((T.X(p), side * (y + SEAT), z))
            go.append((T.X(p), side * (y + SEAT + THICK), z))
        grid_in.append(gi)
        grid_out.append(go)
    obj = slab(builder, name, grid_in, grid_out)
    return obj, cols, (grid_in, grid_out)


def frame_bars(builder, name, side, corners, bar=0.016, depth=0.012):
    """Brass frame around a side window: four sweeps hugging the hull side."""
    (pa, zba), (pb, zbb), (_, ztb), (_, zta) = corners
    cols = _cols(pa, pb)
    out = []
    off = SEAT + depth / 2 - 0.001

    def edge(row):
        pts = []
        for p in cols:
            t = (p - pa) / (pb - pa)
            z = (zba + (zbb - zba) * t) if row == 0 else (zta + (ztb - zta) * t)
            pts.append((T.X(p), side * (B.side_y(p) + off), z + (-bar / 2 if row == 0 else bar / 2)))
        return pts
    prof = [(-depth / 2, -bar / 2), (depth / 2, -bar / 2), (depth / 2, bar / 2), (-depth / 2, bar / 2)]
    out.append(P.sweep(builder, name + "_Bot", edge(0), "brass", profile=prof, up=(0, 0, 1)))
    out.append(P.sweep(builder, name + "_Top", edge(1), "brass", profile=prof, up=(0, 0, 1)))
    for k, (p, zb, zt) in enumerate(((pa, zba, zta), (pb, zbb, ztb))):
        xo = -bar / 2 if k == 0 else bar / 2
        y = side * (B.side_y(p) + off)
        out.append(P.sweep(builder, f"{name}_End{k}", [(T.X(p) + xo, y, zb - bar / 2),
                                                         (T.X(p) + xo, y, zt + bar / 2)], "brass",
                           profile=[(-depth / 2, -bar / 2), (depth / 2, -bar / 2), (depth / 2, bar / 2),
                                    (-depth / 2, bar / 2)], up=(1, 0, 0)))
    return out


def sloped_window(builder, name, px0, px1, ymax, ymid=0.012):
    """Windshield panes on the flat sloped top between px0 and px1 (two panes + centre mullion)."""
    cols = _cols(px0, px1)
    out = []
    for side in SIDES:
        y0, y1 = side * ymid, side * ymax
        gi, go = [], []
        for y in (y0, y1):
            ri, ro = [], []
            for p in cols:
                z = B.roof_z(p)
                ri.append((T.X(p), y, z + SEAT))
                ro.append((T.X(p), y, z + SEAT + THICK))
            gi.append(ri)
            go.append(ro)
        if side < 0:
            gi, go = gi[::-1], go[::-1]
        out.append(slab(builder, f"{name}_{tag(side)}", gi, go))
    return out


def sloped_frame(builder, name, px0, px1, ymax, bar=0.018, depth=0.012):
    cols = _cols(px0, px1)
    out = []
    prof = [(-bar / 2, -depth / 2), (bar / 2, -depth / 2), (bar / 2, depth / 2), (-bar / 2, depth / 2)]
    off = SEAT + depth / 2 - 0.001
    for k, y in enumerate((-ymax, 0.0, ymax)):
        pts = [(T.X(p), y, B.roof_z(p) + off) for p in cols]
        out.append(P.sweep(builder, f"{name}_Rail{k}", pts, "brass", profile=prof, up=(0, 1, 0)))
    for k, p in enumerate((px0, px1)):
        pts = [(T.X(p), -ymax, B.roof_z(p) + off), (T.X(p), ymax, B.roof_z(p) + off)]
        out.append(P.sweep(builder, f"{name}_Cross{k}", pts, "brass",
                           profile=[(-depth / 2, -bar / 2), (depth / 2, -bar / 2), (depth / 2, bar / 2),
                                    (-depth / 2, bar / 2)], up=(1, 0, 0)))
    return out


WINDOWS = {
    # name: corners (px, z) bottom-left, bottom-right, top-right, top-left
    "TruckDoor": [(468, 0.994), (510, 0.994), (510, 1.214), (468, 1.214)],
    "TruckQuarter": [(525, 0.994), (560, 0.994), (560, 1.19), (525, 1.19)],
    "SpeedsterSide": [(636, 0.655), (688, 0.655), (688, 0.775), (636, 0.80)],
}


def build_glazing(builder):
    out = {"glass": [], "frames": []}
    for name, corners in WINDOWS.items():
        for side in SIDES:
            g, cols, _ = side_window(builder, f"Glass_{name}_{tag(side)}", side, corners)
            out["glass"].append(g)
            out["frames"] += frame_bars(builder, f"Frame_{name}_{tag(side)}", side, corners)
    out["glass"] += sloped_window(builder, "Glass_TruckWindshield", 436.5, 452.0, 0.36)
    out["frames"] += sloped_frame(builder, "Frame_TruckWindshield", 436.5, 452.0, 0.36)
    out["glass"] += sloped_window(builder, "Glass_SpeedsterWindshield", 703.0, 720.0, 0.27)
    out["frames"] += sloped_frame(builder, "Frame_SpeedsterWindshield", 703.0, 720.0, 0.27)
    return out


SKYLIGHT_PX = (484, 516, 548)


def build_skylights(builder):
    """Raised brass hatches with glass panes seated below the rim (clerestory skylights)."""
    out = {"glass": [], "frames": []}
    for k, px in enumerate(SKYLIGHT_PX):
        x = T.X(px)
        zr = B.roof_z(px)
        crown = T.lerp_table(B.CROWN, px)
        lx, ly = 0.20, 0.42
        wall, h = 0.022, 0.15
        zc = zr + crown + 0.5 * h - 0.075
        zt = zc + h / 2
        out["frames"].append(P.rbox(builder, f"Frame_Skylight_{k}_L", (lx, wall, h), "brass", bevel=0.005,
                                    location=(x, -ly / 2 + wall / 2, zc)))
        out["frames"].append(P.rbox(builder, f"Frame_Skylight_{k}_R", (lx, wall, h), "brass", bevel=0.005,
                                    location=(x, ly / 2 - wall / 2, zc)))
        out["frames"].append(P.rbox(builder, f"Frame_Skylight_{k}_F", (wall, ly - 2 * wall + 0.002, h), "brass",
                                    bevel=0.005, location=(x - lx / 2 + wall / 2, 0.0, zc)))
        out["frames"].append(P.rbox(builder, f"Frame_Skylight_{k}_B", (wall, ly - 2 * wall + 0.002, h), "brass",
                                    bevel=0.005, location=(x + lx / 2 - wall / 2, 0.0, zc)))
        gx, gy = lx - 2 * wall + 0.012, ly - 2 * wall + 0.012
        zg = zt - 0.020
        gi = [[(x - gx / 2, -gy / 2, zg), (x + gx / 2, -gy / 2, zg)],
              [(x - gx / 2, gy / 2, zg), (x + gx / 2, gy / 2, zg)]]
        go = [[(a, b, c + THICK) for a, b, c in row] for row in gi]
        out["glass"].append(slab(builder, f"Glass_Skylight_{k}", gi, go))
    return out


def side_strip(builder, name, side, px_list, z, height, thick, mat, lift=0.0):
    """Thin band hugging the flat hull side (stripe, belt moulding, door outline)."""
    prof = [(-thick / 2, -height / 2), (thick / 2, -height / 2), (thick / 2, height / 2), (-thick / 2, height / 2)]
    pts = [(T.X(p), side * (B.side_y(p) + thick / 2 - 0.0005 + lift), z) for p in px_list]
    return P.sweep(builder, name, pts, mat, profile=prof, up=(0, 0, 1))


def vstrip(builder, name, side, px, z0, z1, width, thick, mat):
    y = side * (B.side_y(px) + thick / 2 - 0.0005)
    prof = [(-thick / 2, -width / 2), (thick / 2, -width / 2), (thick / 2, width / 2), (-thick / 2, width / 2)]
    return P.sweep(builder, name, [(T.X(px), y, z0), (T.X(px), y, z1)], mat, profile=prof, up=(1, 0, 0))


def build_doors_and_stripes(builder):
    out = []
    for side in SIDES:
        s = tag(side)
        # red body stripe and a brass belt moulding along the flat flank
        px_list = [p for p in B.HULL_PX if 440 <= p <= 702]
        out.append(side_strip(builder, f"Trim_Stripe_{s}", side, px_list, 0.545, 0.034, 0.004, "accent"))
        out.append(side_strip(builder, f"Trim_Belt_{s}", side, px_list, 0.585, 0.012, 0.007, "brass"))
        # truck door outline, hinges and handle
        da, db, za, zb = 463, 516, 0.60, 1.25
        cols = _cols(da, db)
        out.append(side_strip(builder, f"Trim_DoorBottom_{s}", side, cols, za, 0.012, 0.006, "iron"))
        out.append(side_strip(builder, f"Trim_DoorTop_{s}", side, cols, zb - 0.02, 0.012, 0.006, "iron"))
        out.append(vstrip(builder, f"Trim_DoorFront_{s}", side, da, za, zb - 0.02, 0.012, 0.006, "iron"))
        out.append(vstrip(builder, f"Trim_DoorRear_{s}", side, db, za, zb - 0.02, 0.012, 0.006, "iron"))
        for k, z in enumerate((0.70, 0.95, 1.18)):
            y = side * (B.side_y(da) + 0.012)
            out.append(F.revolve(builder, f"Fine_DoorHinge_{s}_{k}", [
                (0.0, z - 0.04), (0.011, z - 0.04), (0.011, z + 0.04), (0.0, z + 0.04)], ["brass"], axis=2,
                center=(T.X(da), y, 0), segments=10))
        y = side * (B.side_y(500) + 0.020)
        out.append(P.rbox(builder, f"Fine_DoorHandle_{s}", (0.085, 0.014, 0.020), "brass", bevel=0.004,
                          location=(T.X(505), y, 0.88)))
        for k, dx in enumerate((-0.03, 0.03)):
            out.append(P.sweep(builder, f"Fine_DoorHandlePost_{s}_{k}",
                                      [(T.X(505) + dx, side * B.side_y(500), 0.88),
                                       (T.X(505) + dx, y, 0.88)], "brass", radius=0.006, sides=6))
    return out


def build(builder, hull):
    glaze = build_glazing(builder)
    sky = build_skylights(builder)
    doors = build_doors_and_stripes(builder)
    return glaze, sky, doors
