"""Primitive winding check for the habitation Kit (run: ak-blender tools/city_pipeline/check_habitation_primitives.py).

Builds a hollow ring, solid cylinder, reversed-profile cylinder and cone under the mirrored root transform (plain
and rotated) and verifies each face normal against the expected radial/axial direction in the lathe-local frame.
"""
import os

from mathutils import Euler, Vector

_here = os.path.dirname(os.path.abspath(__file__))
_path = os.path.join(_here, "build_habitation_workshop.py")
with open(_path, encoding="utf-8") as fh:
    _src = fh.read().split("\ndef main():")[0]
ns = {"__name__": "habitation_kit", "__file__": _path}
exec(compile(_src, _path, "exec"), ns)
Kit = ns["Kit"]

bad = []


def check(name, prof, caps, rot, expect):
    k = Kit()
    with k.at(0, 0, 0, **rot):
        k.lathe(prof, "steel", 8, caps)
    k.bm.normal_update()
    mi = (k.stack[0] @ Euler((rot.get("rx", 0), rot.get("ry", 0), rot.get("rz", 0))).to_matrix().to_4x4()).inverted()
    for f in k.bm.faces:
        cl = mi @ f.calc_center_median()
        n = mi.to_3x3() @ f.normal
        radial = Vector((cl.x, cl.y, 0))
        radial = radial.normalized() if radial.length > 1e-6 else radial
        if n.dot(expect(cl, radial)) < 0.3:
            bad.append((name, tuple(round(v, 2) for v in cl), tuple(round(v, 2) for v in n)))


def ring_exp(cl, radial):
    r = (cl.x ** 2 + cl.y ** 2) ** 0.5
    if r > 0.9:
        return radial
    if r < 0.7:
        return -radial
    return Vector((0, 0, 1))


def solid_exp(cl, radial):
    if abs(cl.z) < 1e-6:
        return Vector((0, 0, -1))
    if abs(cl.z - 2.0) < 1e-6:
        return Vector((0, 0, 1))
    return radial


def cone_exp(cl, radial):
    if abs(cl.z) < 1e-6:
        return Vector((0, 0, -1))
    return Vector((radial.x, radial.y, 0.5)).normalized()


for rn, rot in (("plain", {}), ("rotated", {"rx": 1.1, "rz": 0.4}), ("flipy", {"ry": 3.14159})):
    check("ring/" + rn, [(1.0, 0.0), (1.0, 1.0), (0.6, 1.0), (0.6, 0.0)], False, rot, ring_exp)
    check("solid/" + rn, [(1.0, 0.0), (1.0, 2.0)], True, rot, solid_exp)
    check("reversed/" + rn, [(1.0, 2.0), (1.0, 0.0)], True, rot, solid_exp)
    check("cone/" + rn, [(0.0, 2.0), (1.0, 0.0)], True, rot, cone_exp)
ns["report"](primitive_normal_failures=len(bad), failures=[str(b) for b in bad[:10]])
if bad:
    raise RuntimeError("Habitation primitive winding checks failed")
