"""Hull, carapace plates, sponsons, wings, nacelles, pods, canopies of the Helix Wraith."""
import math

import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import helix_core as C
import helix_prims as P
import helix_trace as T

SIDES = (1, -1)
SN = {1: "+1", -1: "-1"}
MIN_H = 0.012


class Surface:
    """Ray-cast access to the finished hull for seating details exactly on the skin."""

    def __init__(self, obj):
        mesh = C.evaluated_mesh(obj)
        self.bvh = C.bvh_of(mesh)

    def side_y(self, x, z, s):
        hit = self.bvh.ray_cast(Vector((x, s * 3.0, z)), Vector((0, -s, 0)))
        return None if hit[0] is None else hit[0].y

    def top_z(self, x, y):
        hit = self.bvh.ray_cast(Vector((x, y, 3.0)), Vector((0, 0, -1)))
        return None if hit[0] is None else hit[0].z


def hull_stations():
    xs = sorted({k for k, _ in T.TOP} | {k for k, _ in T.HALF} | set(range(300, 850, 12)))
    out = []
    for px in xs:
        if px < 297 or px > 850:
            continue
        x = T.X(px)
        zt = T.hull_top_z(x)
        zb = T.bot_z(x)
        if zt - zb < MIN_H:
            zt = zb + MIN_H
        carapace = max(0.0, min(1.0, (500 - px) / 60))
        out.append(dict(x=x, hw=max(T.half_w(x), 0.004), zt=zt, zb=zb, n=2.9 - 0.7 * carapace, belly=1.0))
    return out


def build_hull(builder):
    hull = P.loft(builder, "Body_Hull", hull_stations(), ["paint", "accent"], sides=40)
    mesh = hull.data
    for poly in mesh.polygons:
        c = poly.center
        if T.X(540) < c.x < T.X(646) or T.X(776) < c.x < T.X(822):
            poly.material_index = 1 if (abs(c.y) < 0.034 and poly.normal.z > 0.6) else 0
    return hull


def _taper(st, f):
    out = dict(st)
    out["hw"] = st["hw"] * f
    mid = (st["zt"] + st["zb"]) / 2
    out["zt"] = mid + (st["zt"] - mid) * f
    out["zb"] = mid + (st["zb"] - mid) * f
    return out


def build_plates(builder):
    """Overlapping chitin shingle rings over the carapace spine (Secondary)."""
    n = 8
    for i in range(n):
        px0 = 322 + i * 17.5
        px1 = px0 + 19
        L = (px1 - px0) * T.SCALE
        stations = []
        for f, scale in ((0.0, 0.90), (0.25, 1.0), (0.75, 1.0), (1.0, 0.90)):
            x = T.X(px0) + L * f
            stations.append(dict(x=x, hw=T.half_w(x) + 0.020, zt=T.top_z(x) + 0.018,
                                 zb=T.bot_z(x) + 0.01, n=2.5, belly=0.9))
            stations[-1] = _taper(stations[-1], scale)
        P.loft(builder, f"Body_Plate_{i}", stations, "paint2", sides=36)


def build_collar(builder):
    stations = []
    for px, f in ((455, 0.90), (470, 1.0), (500, 1.0), (515, 0.92)):
        x = T.X(px)
        st = dict(x=x, hw=T.half_w(x) + 0.05, zt=T.top_z(x) + 0.03, zb=T.bot_z(x) - 0.03, n=2.5, belly=0.9)
        stations.append(_taper(st, f))
    P.loft(builder, "Body_Collar", stations, "paint2", sides=28)


def build_sponsons(builder):
    """Armoured track fenders and bulbous shoulder lobes over the bogies."""
    for s in SIDES:
        st = []
        for px, f in ((322, 0.70), (336, 1.0), (458, 1.0), (472, 0.72)):
            st.append(_taper(dict(x=T.X(px), y0=s * T.TRACK_Y, hw=0.165, zt=T.Z(215), zb=T.Z(248), n=3.2), f))
        P.loft(builder, f"Body_Fender_{SN[s]}", st, "paint2", sides=24)
        st = []
        for px, f in ((332, 0.45), (350, 0.85), (395, 1.0), (440, 0.9), (462, 0.5)):
            x = T.X(px)
            st.append(_taper(dict(x=x, y0=s * 0.50, hw=0.17, zt=T.top_z(x) + 0.05 - 0.17, zb=T.Z(222), n=2.3),
                             f))
        P.loft(builder, f"Body_Shoulder_{SN[s]}", st, "paint2", sides=24)


def build_wings(builder):
    t = 0.030
    z0 = T.Z(231) - t / 2
    for s in SIDES:
        poly = [(T.X(598), s * 0.20), (T.X(752), s * 0.20), (T.X(762), s * 0.62), (T.X(702), s * 0.62)]
        if s < 0:
            poly.reverse()
        wing = P.prism(builder, f"Body_Wing_{SN[s]}", poly, ["paint", "accent"], t, bevel=0.007, location=(0, 0, z0))
        for p in wing.data.polygons:
            if abs(p.center.y) > 0.50:
                p.material_index = 1


def build_nacelles(builder):
    for s in SIDES:
        st = []
        for px, f in ((690, 0.70), (710, 1.0), (760, 1.0), (790, 0.78)):
            zc = T.Z(222)
            st.append(_taper(dict(x=T.X(px), y0=s * 0.34, hw=0.10, zt=zc + 0.10, zb=zc - 0.10, n=2.1), f))
        P.loft(builder, f"Body_Nacelle_{SN[s]}", st, "paint", sides=24)


def build_pods(builder):
    zc = T.Z(T.POD_Z_PX)
    for s in SIDES:
        st = []
        for px, f in ((656, 0.60), (680, 0.95), (740, 1.0), (785, 0.72), (795, 0.52)):
            st.append(_taper(dict(x=T.X(px), y0=s * T.POD_Y, hw=T.POD_R, zt=zc + T.POD_R, zb=zc - T.POD_R, n=2.0), f))
        pod = P.loft(builder, f"Body_Pod_{SN[s]}", st, ["paint", "accent"], sides=24)
        for p in pod.data.polygons:
            if T.X(742) < p.center.x < T.X(772):
                p.material_index = 1


def build_canopies(builder, surf):
    for tag, (a, b, rise) in zip(("Aft", "Fwd"), T.DOMES):
        stations = []
        for k in range(9):
            px = a + (b - a) * k / 8
            x = T.X(px)
            zt = T.Z(P_top(px))
            zb = T.hull_top_z(x) - 0.06
            hw = max(T.half_w(x) * 0.60, 0.01)
            if zt - zb < 0.02:
                zt = zb + 0.02
            stations.append(dict(x=x, hw=hw, zt=zt, zb=zb, n=2.3, belly=0.5))
        P.loft(builder, f"Glass_Canopy{tag}", stations, "glass", sides=24)
        for i, f in enumerate((0.2, 0.5, 0.8)):
            px = a + (b - a) * f
            x = T.X(px)
            hw = T.half_w(x) * 0.60
            zt = T.Z(P_top(px))
            zb = T.hull_top_z(x) - 0.07
            st = [dict(x=x - 0.007, hw=hw + 0.008, zt=zt + 0.008, zb=zb, n=2.3, belly=0.5),
                  dict(x=x + 0.007, hw=hw + 0.008, zt=zt + 0.008, zb=zb, n=2.3, belly=0.5)]
            P.loft(builder, f"Frame_Canopy{tag}_{i}", st, "hardware", sides=24)


def P_top(px):
    return T.lerp_table(T.TOP, px)


def build_blister(builder):
    px0, px1 = 606.0, 642.0
    st = []
    for k, f in enumerate((0.3, 0.8, 1.0, 0.8, 0.3)):
        x = T.X(px0 + (px1 - px0) * k / 4)
        top = T.hull_top_z(x)
        st.append(dict(x=x, hw=0.05 * f + 0.004, zt=top + 0.045 * f, zb=top - 0.05, n=2.2, belly=0.5))
    P.loft(builder, "Glass_SensorBlister", st, "light", sides=16)


def build_maw(builder):
    """Domed forward carapace cap between the claws (Front B elevation)."""
    st = []
    for px, f in ((296, 0.55), (306, 0.95), (322, 1.0), (338, 0.9)):
        st.append(_taper(dict(x=T.X(px), hw=0.29, zt=T.Z(158), zb=T.Z(236), n=2.2, belly=0.9), f))
    P.loft(builder, "Body_Maw", st, "paint2", sides=28)
