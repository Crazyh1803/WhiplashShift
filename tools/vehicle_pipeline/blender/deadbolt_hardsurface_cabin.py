"""Greenhouse: framed side glass and the two windshields, seated in real recesses."""
from mathutils import Vector

import deadbolt_hardsurface_cuts as K
import deadbolt_hardsurface_trace as T

RECESS_DEPTH = 0.016
GLASS_CLEARANCE = 0.0045
GLASS_MARGIN = 0.018


def _xz(poly_px):
    return [(T.X(px), T.Z(py)) for px, py in poly_px]


def windshield_outline(span, margin, samples=10):
    x0, x1 = span
    left, right = [], []
    for i in range(samples + 1):
        px = x0 + (x1 - x0) * i / samples
        hw = T.top_half(px) - margin
        left.append((T.X(px), hw))
        right.append((T.X(px), -hw))
    # counter-clockwise in x/y: along -y edge forward, then back along +y
    return right + list(reversed(left))


def glaze(builder, surface):
    """Create recess cutters; returns the glass specs to seat after the cut."""
    specs = []
    for name, poly in (("TruckSide", T.WINDOW_TRUCK_SIDE), ("CoupeSide", T.WINDOW_COUPE_SIDE)):
        outline = _xz(poly)
        for sign, tag in ((1, "L"), (-1, "R")):
            pts_xz = outline if sign == 1 else list(reversed(outline))
            flat = [Vector((x, 0.0, z)) for x, z in pts_xz]
            K.make_recess_cutter(builder, f"Cutter_Glass_{name}_{tag}", flat, "side", surface,
                                 sign, RECESS_DEPTH)
            specs.append({"name": f"Glass_{name}_{tag}", "kind": "side", "sign": sign,
                          "outline": inset_xz(outline, GLASS_MARGIN)})
    for name, span in (("TruckWindshield", T.WINDSHIELD_TRUCK),
                       ("CoupeWindshield", T.WINDSHIELD_COUPE)):
        outline = windshield_outline(span, 0.105)
        flat = [Vector((x, y, 0.0)) for x, y in outline]
        K.make_recess_cutter(builder, f"Cutter_Glass_{name}", flat, "top", surface, 1,
                             RECESS_DEPTH)
        specs.append({"name": f"Glass_{name}", "kind": "top", "sign": 1,
                      "outline": [tuple(p) for p in K.inset_polygon(
                          [Vector(p) for p in outline], GLASS_MARGIN)]})
    return specs


def inset_xz(outline, distance):
    return [tuple(p) for p in K.inset_polygon([Vector(p) for p in outline], distance)]


def seat_glass(builder, shell_surface, specs):
    """Create glass panels resting on the recess floors of the cut shell."""
    objs = []
    for spec in specs:
        if spec["kind"] == "side":
            sign = spec["sign"]
            outline = spec["outline"] if sign == 1 else list(reversed(spec["outline"]))
            pts = [Vector((x, sign * 0.5, z)) for x, z in outline]

            def caster(p, s=sign):
                return (p.x, s * 3.0, p.z), (0, -s, 0)
        else:
            pts = [Vector((x, y, 1.0)) for x, y in spec["outline"]]

            def caster(p):
                return (p.x, p.y, 3.0), (0, 0, -1)
        objs.append(K.glass_panel(builder, spec["name"], pts, shell_surface, caster,
                                  GLASS_CLEARANCE,
                                  axes=(0, 2) if spec["kind"] == "side" else (0, 1)))
    return objs
