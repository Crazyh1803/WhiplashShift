"""Human Base Meshes (CC0, level-0 adult male/female bodies) -> posed, scaled person bodies for the industrial market benchmark.

Pipeline (all numpy, Blender Z-up, front +Y, +X = person's right, feet on z=0, origin between the feet):
  load_base()      orient/scale the retained base body, measure landmarks (joints, hand frames, finger chains)
  Rig              capsule-bone linear-blend skinning; weights are a pure function of the rest position, so clothing/boots/hair built in
                   the rest pose deform with the body. FK from 2-bone IK results and hand/finger specs, applied (baked) before export.
"""
import math
import os

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC_BLEND = os.path.join(ROOT, "assets", "generated", "industrial_market", "sources", "human_base_meshes_v141_used.blend")
V = Vector


def unit(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else np.array([0, 0, 1.0])


def rot_axis(axis, ang):
    a = unit(axis)
    c, s = math.cos(ang), math.sin(ang)
    x, y, z = a
    return np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                     [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                     [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])


def rot_between(a, b):
    a, b = unit(a), unit(b)
    c = float(a @ b)
    if c > 1 - 1e-9:
        return np.eye(3)
    if c < -1 + 1e-9:
        p = unit(np.cross(a, [1, 0, 0]) if abs(a[0]) < 0.9 else np.cross(a, [0, 1, 0]))
        return rot_axis(p, math.pi)
    return rot_axis(np.cross(a, b), math.acos(max(-1, min(1, c))))


def frame_rot(f, n):
    """Rotation matrix whose columns are (side, f, n) for an orthonormalised forward f and normal n."""
    f = unit(f)
    n = unit(np.asarray(n, float) - f * (np.asarray(n, float) @ f))
    return np.stack([np.cross(f, n), f, n], 1)


class Base:
    """One oriented/scaled base body (vertices, faces, UV loops) + eyes + landmarks."""

    def __init__(self, key, H):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        with bpy.data.libraries.load(SRC_BLEND) as (d, t):
            t.objects = [n for n in d.objects if n in (f"base_{key}", f"eye_{key}_L", f"eye_{key}_R")]
        objs = {o.name: o for o in t.objects}
        body = objs["base_" + key]
        me = body.data
        P = np.array([v.co[:] for v in me.vertices], float)
        P[:, 0] *= -1                                    # rotate 180 about Z: source front is -Y
        P[:, 1] *= -1
        zmin = P[:, 2].min()
        cx = 0.5 * (P[:, 0].min() + P[:, 0].max())
        self.s = H / (P[:, 2].max() - zmin)
        self.off = np.array([cx, 0.0, zmin])
        self.P = (P - self.off) * self.s
        self.H = H
        self.faces = [tuple(p.vertices) for p in me.polygons]
        self.loop_uv = [tuple(l.uv) for l in me.uv_layers["UVMap"].data]
        self.face_loops = [(p.loop_start, p.loop_total) for p in me.polygons]
        self.eyes = {}
        for o in t.objects:
            if o.name.startswith("eye_"):
                side = o.name[-1]
                mw = Matrix.LocRotScale(o.location, o.rotation_euler, o.scale)      # body-frame (location stored relative to the body)
                vs = np.array([(mw @ v.co)[:] for v in o.data.vertices], float)
                vs[:, 0] *= -1
                vs[:, 1] *= -1
                vs = (vs - self.off) * self.s
                self.eyes[side] = vs
                self.eye_faces = [tuple(p.vertices) for p in o.data.polygons]
        self.measure()

    # ------------------------------------------------------------------------------------ landmarks
    def march(self, c0, d0, steps=34, step=0.02, rad=0.11):
        s = self.s
        c = np.array(c0, float)
        d = unit(d0)
        out = []
        for _ in range(steps):
            rel = self.P - c
            t = rel @ d
            perp = rel - np.outer(t, d)
            m = (np.abs(t) < step * s * 0.6) & (np.linalg.norm(perp, axis=1) < rad * s)
            if m.sum() < 3:
                break
            cen = self.P[m].mean(0)
            out.append((cen, float(np.linalg.norm(perp[m], axis=1).max()), int(m.sum())))
            c = cen + d * step * s
        return out

    def measure(self):
        P, s, H = self.P, self.s, self.H
        L = {}
        mir = lambda v: v * np.array([-1, 1, 1])
        for side in (1, -1):
            # ---- arm: march from the shoulder along the A-pose arm (measured on +X, mirrored)
            if side == 1:
                seq = self.march(np.array([0.21 * s, 0.0, 1.2 * s]), np.array([0.5, 0.0, -0.87]))
                rs = [r for _, r, _ in seq]
                k_hand = next(k for k in range(10, len(seq)) if rs[k] - rs[k - 1] > 0.02 * s)
                wrist = seq[k_hand - 1][0]
                sh = np.array([abs(seq[0][0][0]) - 0.02 * s, seq[0][0][1], seq[0][0][2] + 0.1 * s])
                el = sh + (wrist - sh) * 0.52
                A = (sh, el, wrist, [c for c, _, _ in seq])
            L[f"S{side}"], L[f"E{side}"], L[f"W{side}"] = [A[i] if side == 1 else mir(A[i]) for i in range(3)]
            L[f"chain{side}"] = [c if side == 1 else mir(c) for c in A[3]]

            # ---- leg
            def cen(zf, xs):
                m = (np.abs(P[:, 2] - zf * H) < 0.02 * H) & (P[:, 0] * xs > 0.02 * s) & (np.abs(P[:, 0]) < 0.2 * s)
                return P[m].mean(0)
            L[f"hip{side}"] = cen(0.51, side) * np.array([1, 1, 0]) + np.array([0, 0, 0.51 * H])
            L[f"knee{side}"] = cen(0.278, side) * np.array([1, 1, 0]) + np.array([0, 0, 0.278 * H])
            L[f"ankle{side}"] = cen(0.052, side) * np.array([1, 1, 0]) + np.array([0, 0, 0.052 * H])
            toe = P[(P[:, 0] * side > 0.02 * s) & (P[:, 2] < 0.06 * H)]
            L[f"toe{side}"] = toe[np.argmax(toe[:, 1])]
            L[f"heel{side}"] = toe[np.argmin(toe[:, 1])]
        L["waist"] = np.array([0, P[(np.abs(P[:, 2] - 0.60 * H) < 0.01 * H) & (np.abs(P[:, 0]) < 0.12 * s)][:, 1].mean(), 0.60 * H])
        L["neck_base"] = np.array([0, P[(np.abs(P[:, 2] - 0.835 * H) < 0.01 * H) & (np.abs(P[:, 0]) < 0.06 * s)][:, 1].mean(), 0.835 * H])
        hd = P[(P[:, 2] > 0.905 * H)]
        L["head_base"] = np.array([0, hd[:, 1].mean() + 0.0, 0.862 * H])
        L["head_top"] = np.array([0, hd[:, 1].mean(), P[:, 2].max()])
        self.L = L

