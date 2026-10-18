"""Claws, ribbed conduits, radiator fins and vents: the biomechanical End B and the hull slots."""
import math

import bmesh
from mathutils import Matrix, Vector

import helix_core as C
import helix_prims as P
import helix_trace as T
from helix_body import SIDES, SN


def _taper_radii(n, r0, r1):
    return [r0 + (r1 - r0) * (i / (n - 1)) ** 0.8 for i in range(n)]


def build_claws(builder):
    for s in SIDES:
        teeth = bmesh.new()
        for jaw, (p0, p1, p2, p3) in {
            "Up": ((T.X(308), s * 0.42, T.Z(215)), (T.X(284), s * 0.54, T.Z(200)),
                   (T.X(250), s * 0.46, T.Z(182)), (T.X(230), s * 0.34, T.Z(180))),
            "Low": ((T.X(308), s * 0.42, T.Z(226)), (T.X(285), s * 0.55, T.Z(240)),
                    (T.X(250), s * 0.45, T.Z(262)), (T.X(236), s * 0.34, T.Z(244))),
        }.items():
            path = P.bezier((p0, p1, p2, p3), 40)
            radii = _taper_radii(len(path), 0.085, 0.018)
            P.tube(builder, f"Body_Claw{jaw}_{SN[s]}", path, radii, "paint2", sides=12, ribs=6, rib_depth=0.07)
            # serrated inner edge: cones pointing toward the claw's axis
            for k in range(10, 38, 4):
                p, q = path[k], path[k + 1]
                tang = (q - p).normalized()
                inward = Vector((0, -s, 0)) + tang * 0.35 + Vector((0, 0, 0.5 if jaw == "Low" else -0.5))
                r = radii[k]
                base = p + Vector((0, -s * r * 0.6, 0.0))
                P.bm_cone(teeth, base, inward, r * 0.55, 0.045 + 0.02 * (1 - k / 40), sides=6)
        P.bm_object(builder, f"Fine_ClawTeeth_{SN[s]}", teeth, "hardware")
        for (px, py, r), tag in zip(T.CLAW_PIVOT_PX[:1], ("A",)):
            P.cylinder(builder, f"Fine_ClawPivot{tag}_{SN[s]}", r * T.SCALE, 0.10 if tag == "A" else 0.08, "hardware",
                       axis="y", sides=20,
                       location=(T.X(px), s * (0.46 if tag == "A" else 0.43), T.Z(py)), bevel=0.004)


def build_hoses(builder):
    """Four ribbed S-curve conduits per flank from the carapace shoulders to the collar sockets."""
    for s in SIDES:
        sockets = bmesh.new()
        for i in range(4):
            z0 = 0.86 - 0.115 * i
            z3 = 0.70 - 0.10 * i
            p0 = (T.X(438 + 3 * i), s * 0.60, z0)
            p3 = (T.X(500), s * (T.half_w(T.X(500)) + 0.035 - 0.004 * i), z3)
            p1 = (p0[0] + 0.16, s * (0.70 + 0.02 * i), z0 + 0.06)
            p2 = (p3[0] - 0.14, s * (abs(p3[1]) + 0.10), z3 + 0.05)
            path = P.bezier((p0, p1, p2, p3), 40)
            P.tube(builder, f"Body_Hose{i}_{SN[s]}", path, 0.033, "rubber", sides=12, ribs=18, rib_depth=0.13)
            P.bm_cyl(sockets, (p3[0] - 0.004, p3[1], p3[2]), (1, 0, 0), 0.047, 0.026, sides=12)
            P.bm_cyl(sockets, (p0[0] - 0.01, p0[1], p0[2]), (1, 0, 0), 0.045, 0.024, sides=12)
        P.bm_object(builder, f"Fine_HoseFlanges_{SN[s]}", sockets, "hardware")


def build_fins(builder, surf):
    """Slatted radiator stacks rising from the upper-rear shoulders."""
    for s in SIDES:
        bm = bmesh.new()
        for stack, px in enumerate((352, 398)):
            x = T.X(px)
            base = T.top_z(x) - 0.155  # shoulder lobe crown, sunk into the shell
            for i in range(6):
                rot = Matrix.Rotation(math.radians(-24), 3, "Y")
                P.bm_box(bm, (x + 0.034 * i, s * 0.50, base + 0.045), (0.010, 0.17, 0.115), rot)
        P.bm_object(builder, f"Fine_Fins_{SN[s]}", bm, "hardware")


def build_vents(builder, surf):
    """Recessed spine slots, side gill slits and nose vents (dark inserts seated in the skin)."""
    spine = bmesh.new()
    for k in range(5):
        x = T.X(466 + 5 * k)
        z = surf.top_z(x, 0.0)
        for y in (-0.10, 0.10):
            P.bm_box(spine, (x, y, z - 0.002), (0.016, 0.07, 0.016))
    P.bm_object(builder, "Fine_SpineSlots", spine, "hardware")
    for s in SIDES:
        bm = bmesh.new()
        for k in range(5):
            x = T.X(480 + 5 * k)
            z = T.Z(185)
            y = surf.side_y(x, z, s)
            P.bm_box(bm, (x, s * (abs(y) - 0.002), z), (0.012, 0.014, 0.075))
        for k in range(4):
            x = T.X(755 + 7 * k)
            z = T.Z(218)
            y = surf.side_y(x, z, s)
            P.bm_box(bm, (x, s * (abs(y) - 0.002), z), (0.011, 0.014, 0.05))
        P.bm_object(builder, f"Fine_Gills_{SN[s]}", bm, "hardware")


def build_lenses(builder):
    for s in SIDES:
        zc = T.Z(222)
        P.cylinder(builder, f"Trim_NacelleHousing_{SN[s]}", 0.074, 0.03, "hardware", axis="x", sides=24,
                   location=(T.X(790) + 0.004, s * 0.34, zc), bevel=0.004)
        P.cylinder(builder, f"Fine_NacelleLens_{SN[s]}", 0.055, 0.02, "light", axis="x", sides=24,
                   location=(T.X(790) + 0.016, s * 0.34, zc))
        zp = T.Z(T.POD_Z_PX)
        P.cylinder(builder, f"Fine_PodLens_{SN[s]}", 0.022, 0.016, "light", axis="x", sides=18,
                   location=(T.X(795) + 0.002, s * T.POD_Y, zp))
        bm = bmesh.new()
        for dz in (-0.034, 0.034):
            P.bm_cyl(bm, (T.X(795) - 0.03 + 0.091, s * T.POD_Y, zp + dz), (1, 0, 0), 0.013, 0.182, sides=8)
        P.bm_object(builder, f"Fine_PodBarrels_{SN[s]}", bm, "hardware")
