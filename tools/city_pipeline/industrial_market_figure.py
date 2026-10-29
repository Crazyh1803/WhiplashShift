"""Clothed, posed figure assembled on a Human Base Meshes body (numpy + bmesh; Blender Z-up, front +Y, feet z=0).

Everything (body skin, garment shells, boots, hair, eyes) is built in the REST pose, then one skinning pass poses all vertices
with the capsule rig, so clothing, boots and hair are fitted to the real anatomy and stay attached.
  * garments: shells offset from the body surface along vertex normals (ease + procedural folds), boundaries snapped to clean
    hem / cuff / neck planes, rim strips for cloth thickness; covered body faces are removed (a 3-ring margin stays under the edges)
  * boots/shoes: lofted rings measured from the foot/shin cross-sections, so soles are flat, heels/toes enclose the real foot
  * hair: scalp shell with a hairline curve, clumped relief; optional ponytail
  * skin UVs: Blender smart_project per group (head / hands / rest) packed into atlas squares, eyes in the atlas eye tile
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector

import industrial_market_humans as HU
import industrial_market_rig as RG
import industrial_market_skin as SK

V = Vector
unit = HU.unit


def g(x, s):
    return np.exp(-(x / s) ** 2)


# ------------------------------------------------------------------------------------------------ mesh helpers
def vertex_normals(P, faces):
    N = np.zeros_like(P)
    for f in faces:
        p = P[list(f)]
        n = np.cross(p[1] - p[0], p[2] - p[0]) + (np.cross(p[2] - p[0], p[3] - p[0]) if len(f) == 4 else 0)
        for i in f:
            N[i] += n
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


def adjacency(n, faces):
    adj = [set() for _ in range(n)]
    for f in faces:
        for i, a in enumerate(f):
            adj[a].add(f[(i + 1) % len(f)])
            adj[a].add(f[i - 1])
    return adj


def boundary_edges(faces):
    cnt = {}
    for f in faces:
        for i, a in enumerate(f):
            b = f[(i + 1) % len(f)]
            cnt.setdefault((min(a, b), max(a, b)), []).append((a, b))
    return [v[0] for v in cnt.values() if len(v) == 1]          # directed as in the owning face


def add_geom(m, P, faces, mat, smooth=True):
    """Append vertices/faces to the shared bmesh; returns (verts, faces)."""
    bm = m.bm
    vs = [bm.verts.new(tuple(float(c) for c in p)) for p in P]
    fl = []
    mi = m.mi(mat)
    for f in faces:
        try:
            fc = bm.faces.new([vs[i] for i in f])
        except ValueError:
            continue
        fc.material_index = mi
        fc.smooth = smooth
        fl.append(fc)
    return vs, fl


# ------------------------------------------------------------------------------------------------ the figure
class Figure:
    def __init__(self, m, key, H, seed):
        self.m = m
        self.key = key
        self.base = HU.Base(key, H)
        self.rig = RG.Rig(self.base)
        self.s = self.base.s
        self.H = H
        self.P = self.base.P
        self.N = vertex_normals(self.P, self.base.faces)
        self.W = self.rig.weights(self.P)
        self.dom = np.array(self.rig.names)[np.argmax(self.W, 1)]
        self.rng = np.random.default_rng(seed)
        self.noise = SK.Noise3(seed + 7)
        self.mine = set()                                   # faces whose orientation is already outward-consistent (not auto-recalculated)
        self.covered = np.zeros(len(self.P), bool)
        self.skin_faces = []                                # (bmesh face, source face index)
        L = self.base.L
        self.eye_mid = 0.5 * (self.base.eyes["R"].mean(0) + self.base.eyes["L"].mean(0))
        self.is_head = self.P[:, 2] > L["head_base"][2] - 0.01 * self.s       # geometric head (jaw and above); neck/trapezius lie below

    # ---------------------------------------------------------------- regions
    def forearm_t(self, side):
        L = self.base.L
        E, W = L[f"E{side}"], L[f"W{side}"]
        a = W - E
        return ((self.P - E) @ a) / (a @ a)

    def region_top(self, hem_z, neck_z, sleeve_t):
        P, dom = self.P, self.dom
        ok = np.zeros(len(P), bool)
        z = P[:, 2]
        trunk = np.isin(dom, ["chest", "pelvis"]) & (z > hem_z) & (z < neck_z)
        ok |= trunk
        for k, sd in (("R", 1), ("L", -1)):
            ok |= (dom == f"upper{k}") & (z < neck_z)
            ok |= (dom == f"fore{k}") & (self.forearm_t(sd) < sleeve_t)
        return ok

    def region_legs(self, top_z, cuff_z):
        P, dom = self.P, self.dom
        z = P[:, 2]
        legs = np.isin(dom, ["pelvis", "thighR", "thighL", "shinR", "shinL", "footR", "footL"])
        return legs & (z < top_z) & (z > cuff_z)

    # ---------------------------------------------------------------- shells
    def shell(self, vmask, mat, ease, folds=None, snaps=(), smooth_iter=2, rim=0.0, thick_in=0.0015, flip=False):
        """Garment shell over the selected body vertices. ease: float or f(P,N,idx)->array. snaps: list of (kind, a, b) boundary snappers."""
        P, N, faces = self.P, self.N, self.base.faces
        sel = [f for f in faces if all(vmask[i] for i in f)]
        used = np.array(sorted({i for f in sel for i in f}))
        remap = {int(v): i for i, v in enumerate(used)}
        bnd = boundary_edges(sel)
        bverts = {a for a, b in bnd} | {b for a, b in bnd}
        Q = P[used].copy()
        # snap boundary vertices onto their cut planes (hem / cuff / neck), choosing the nearest plane
        for v in bverts:
            i = remap[v]
            best = None
            for (pc, pn) in snaps:
                d = abs((Q[i] - pc) @ pn)
                if best is None or d < best[0]:
                    best = (d, pc, pn)
            if best is not None and best[0] < 0.06:
                Q[i] -= best[2] * ((Q[i] - best[1]) @ best[2])
        e = ease(P[used], N[used], used) if callable(ease) else np.full(len(used), float(ease))
        Qo = Q + N[used] * e[:, None]
        if folds is not None:
            Qo = Qo + N[used] * folds(Qo, N[used], used)[:, None]
        sf = [tuple(remap[i] for i in f) for f in sel]
        adj = adjacency(len(used), sf)
        isb = np.zeros(len(used), bool)
        for v in bverts:
            isb[remap[v]] = True
        for _ in range(smooth_iter):
            avg = np.array([Qo[list(a)].mean(0) if a else Qo[i] for i, a in enumerate(adj)])
            w = np.where(isb, 0.15, 0.45)[:, None]
            Qo = Qo * (1 - w) + avg * w
        vs, fl = add_geom(m=self.m, P=Qo, faces=sf if not flip else [f[::-1] for f in sf], mat=mat)
        self.mine.update(fl)
        # cloth thickness rim: boundary edges bridged to points just above the skin
        if rim > 0 or thick_in:
            inner = Q + N[used] * thick_in
            for a, b in bnd:
                ia, ib = remap[a], remap[b]
                quad = [vs[ib], vs[ia], None, None]
                iv = [self.m.bm.verts.new(tuple(float(c) for c in inner[ia])), self.m.bm.verts.new(tuple(float(c) for c in inner[ib]))]
                try:
                    fc = self.m.bm.faces.new([vs[ib], vs[ia], iv[0], iv[1]] if not flip else [iv[1], iv[0], vs[ia], vs[ib]])
                except ValueError:
                    continue
                fc.material_index = self.m.mi(mat)
                fc.smooth = True
                self.mine.add(fc)
        return used, Qo

    def hide_covered(self, region, margin=3):
        """Mark body vertices that sit at least `margin` rings inside the region (their faces are dropped from the skin)."""
        adj = adjacency(len(self.P), self.base.faces)
        depth = np.full(len(self.P), -1)
        frontier = [i for i in np.nonzero(region)[0] if any(not region[j] for j in adj[i])]
        for i in frontier:
            depth[i] = 0
        d = 0
        while frontier and d < margin:
            nxt = []
            for i in frontier:
                for j in adj[i]:
                    if region[j] and depth[j] < 0:
                        depth[j] = d + 1
                        nxt.append(j)
            frontier, d = nxt, d + 1
        self.covered |= region & ((depth < 0) | (depth >= margin))
        # interior verts never reached are also fully covered (depth -1 means no boundary neighbour path within margin)

    # ---------------------------------------------------------------- folds
    def folds_fn(self, hem_z=None, joints=(), amp=1.0):
        nz = self.noise
        s = self.s

        def fn(Pq, Nq, idx):
            out = 0.0035 * amp * nz(Pq, 26.0) * 0.5
            out = out + 0.0012 * amp * nz(Pq, 70.0)
            if hem_z is not None:
                out = out + 0.0045 * amp * g(Pq[:, 2] - (hem_z + 0.045 * s), 0.04 * s) * np.sin(np.arctan2(Pq[:, 0], Pq[:, 1]) * 11 + 3 * nz(Pq, 9.0))
            for (c, ax, wl, a_, rad, sgn) in joints:
                d = Pq - c
                t = d @ ax
                inner = np.clip(-(Nq @ sgn), 0, 1)               # crease on the side facing -sgn
                out = out + a_ * amp * s * g(t, rad) * (0.4 + 0.6 * inner) * np.sin(2 * np.pi * t / wl) * g(np.linalg.norm(d - np.outer(t, ax), axis=1), 0.12)
            return out
        return fn

    # ---------------------------------------------------------------- boots
    def boot(self, side, mat, shaft_top=0.0, ease=0.008, sole=0.02, shaft_ease=None):
        """Loft rings around the foot (y slices) and shin shaft (z slices) measured from the rest body; returns nothing (adds geometry)."""
        P, dom, s = self.P, self.dom, self.s
        k = "R" if side == 1 else "L"
        L = self.base.L
        heel, toe = L[f"heel{side}"], L[f"toe{side}"]
        foot = np.isin(dom, [f"foot{k}"]) | ((dom == f"shin{k}") & (P[:, 2] < 0.14 * s))
        Fv = P[foot]
        ys = np.linspace(heel[1] - 0.012 * s, toe[1] + 0.014 * s, 26)
        rows = []
        prof = []
        for y in ys:
            sel = Fv[np.abs(Fv[:, 1] - y) < 0.011 * s]
            if len(sel) < 3:
                prof.append(None)
                continue
            prof.append((sel[:, 0].min(), sel[:, 0].max(), sel[:, 2].max()))
        # fill gaps / taper the toe cap
        last = next(p for p in prof if p)
        for i, p in enumerate(prof):
            if p is None:
                prof[i] = last
            last = prof[i]
        n = 18
        z0 = 0.0
        for i, (xlo, xhi, zt) in enumerate(prof):
            t_end = i / (len(ys) - 1)
            cx, hw = 0.5 * (xlo + xhi), 0.5 * (xhi - xlo) + ease + 0.004
            ztop = max(zt + ease + 0.004, 0.034 * s)
            taper = 1.0
            if i == 0:
                taper = 0.62
            if i == len(ys) - 1:
                taper = 0.5
            ring = []
            for j in range(n):
                a = 2 * math.pi * j / n
                c_, s_ = math.cos(a), math.sin(a)
                x = cx + taper * hw * math.copysign(abs(c_) ** 0.7, c_)
                zf = 0.5 * (1 + math.copysign(abs(s_) ** 0.75, s_))
                z = z0 - sole + (ztop - (z0 - sole)) * zf * taper ** 0.5
                if z < z0 - sole + 0.012:                      # sole welt sticks out a few mm
                    x = cx + (x - cx) * 1.03
                ring.append((x, ys[i], z))
            rows.append(ring)
        rows = np.array(rows)
        faces = []
        nr = len(rows)
        for i in range(nr - 1):
            for j in range(n):
                j2 = (j + 1) % n
                faces.append((i * n + j, i * n + j2, (i + 1) * n + j2, (i + 1) * n + j)[::-1])
        pts = rows.reshape(-1, 3)
        c0 = len(pts)
        pts = np.vstack([pts, rows[0].mean(0), rows[-1].mean(0)])
        for j in range(n):
            j2 = (j + 1) % n
            faces.append((j, c0, j2))                           # heel cap
            faces.append(((nr - 1) * n + j2, c0 + 1, (nr - 1) * n + j))
        vs, fl = add_geom(self.m, pts, faces, mat)
        self.mine.update(fl)
        # recompute orientation: make sure the loft is outward (test with the ring normal)
        # shaft (z slices over the shin), customer boots only
        if shaft_top > 0:
            shin = P[(dom == f"shin{k}") | (dom == f"foot{k}")]
            zs = np.linspace(0.06 * s, shaft_top, 12)
            rrows = []
            for z in zs:
                sel = shin[(np.abs(shin[:, 2] - z) < 0.012 * s) & (shin[:, 1] > L[f"ankle{side}"][1] - 0.09 * s) & (np.abs(shin[:, 0] - L[f"ankle{side}"][0]) < 0.1 * s)]
                if len(sel) < 4:
                    sel = shin[np.abs(shin[:, 2] - z) < 0.03 * s]
                c = 0.5 * (sel.min(0) + sel.max(0))
                rx, ry = 0.5 * (sel[:, 0].max() - sel[:, 0].min()), 0.5 * (sel[:, 1].max() - sel[:, 1].min())
                e = (shaft_ease or ease) + 0.002 * (z / shaft_top)
                rrows.append([(c[0] + (rx + e) * math.cos(2 * math.pi * j / 20), c[1] + (ry + e) * math.sin(2 * math.pi * j / 20), z) for j in range(20)])
            rrows = np.array(rrows)
            f2 = []
            for i in range(len(rrows) - 1):
                for j in range(20):
                    j2 = (j + 1) % 20
                    f2.append(((i + 1) * 20 + j, (i + 1) * 20 + j2, i * 20 + j2, i * 20 + j))
            pt2 = rrows.reshape(-1, 3)
            # top rim (leather collar): thin quad strip inward
            ctop = pt2[-20:]
            inn = ctop.copy()
            inn[:, :2] = rrows[-1].mean(0)[:2] + (ctop[:, :2] - rrows[-1].mean(0)[:2]) * 0.86
            inn[:, 2] -= 0.012
            base_i = len(pt2)
            pt2 = np.vstack([pt2, inn])
            for j in range(20):
                j2 = (j + 1) % 20
                f2.append(((len(rrows) - 1) * 20 + j, (len(rrows) - 1) * 20 + j2, base_i + j2, base_i + j))
            vs2, fl2 = add_geom(self.m, pt2, f2, mat)
            self.mine.update(fl2)
        return rows

    # ---------------------------------------------------------------- hair
    def hair(self, mat, thick=0.008, ponytail=False, back_len=0.0, front=0.072, clump=0.0035):
        P, N, dom, s = self.P, self.N, self.dom, self.s
        em = self.eye_mid
        z_rel = (P[:, 2] - em[2]) / s
        az = np.arctan2(P[:, 0], P[:, 1] - (em[1] - 0.09 * s))               # 0 = front, around the head's vertical axis
        a = np.abs(az)

        def hairline(a):
            # forehead -> temple -> above the ear (0.032) -> behind the ear -> nape
            f = np.where(a <= math.radians(36), front,
                         np.where(a <= math.radians(88), front + (a - math.radians(36)) / math.radians(52) * (0.032 - front),
                                  np.where(a <= math.radians(116), 0.032 + (a - math.radians(88)) / math.radians(28) * (-0.035 - 0.032),
                                           -0.035 + (a - math.radians(116)) / math.radians(64) * (-0.06 - 0.035 - back_len))))
            return f
        in_head = self.is_head & (z_rel > -0.13)
        ok = in_head & (z_rel > hairline(a))
        sel = [f for f in self.base.faces if all(ok[i] for i in f)]
        used = np.array(sorted({i for f in sel for i in f}))
        remap = {int(v): i for i, v in enumerate(used)}
        sf = [tuple(remap[i] for i in f) for f in sel]
        Q = P[used]
        n3 = self.noise
        cl = clump * (n3(Q, 60.0) * 0.5 + 0.5) + 0.0018 * n3(Q, 150.0)
        h = (thick + cl) * (0.7 + 0.5 * np.clip((z_rel[used] - 0.0) / 0.12, 0, 1))
        Qo = Q + N[used] * h[:, None]
        # taper to the base at the hairline edge so the border sits on the scalp
        bnd = boundary_edges(sf)
        bv = {a_ for a_, b in bnd} | {b for a_, b in bnd}
        for v in bv:
            # snap the border onto the smooth hairline curve (z by azimuth), then sit just above the scalp
            zt = em[2] + hairline(np.abs(az[used][v])) * s
            dz = zt - Q[v, 2] if abs(zt - Q[v, 2]) < 0.02 * s else 0.0
            Qo[v] = Q[v] + np.array([0, 0, dz]) + N[used][v] * 0.0025
        vs, fl = add_geom(self.m, Qo, sf, mat)
        self.mine.update(fl)
        # hair UVs: azimuth/height wrap
        uvl = self.m.uv
        for f in fl:
            for lp in f.loops:
                p = lp.vert.co
                lp[uvl].uv = ((math.atan2(p.x, p.y - (em[1] - 0.09 * s)) / (2 * math.pi) + 0.5) * 3.0, (p.z - em[2]) / s * 5.0)
            self.m.explicit.add(f)
        self.covered |= ok & False
        if ponytail:
            c = np.array([0.0, em[1] - 0.095 * s, em[2] + 0.035 * s])
            pts = [V(c + np.array(o) * s) for o in ((0, 0.0, 0.0), (0, -0.034, -0.012), (0.004, -0.06, -0.08), (-0.004, -0.068, -0.19), (0.006, -0.06, -0.30))]
            self.m.tube(pts, [0.026 * s, 0.028 * s, 0.026 * s, 0.02 * s, 0.006 * s], mat, seg=10, samples=14, ratio=1.0, uv=("cloth", 3.0))
            self.m.tube([V(c + np.array(o) * s) for o in ((0, -0.004, 0.0), (0, -0.016, -0.002))], [0.02 * s, 0.02 * s], "leather", seg=10, samples=3, uv=("cloth", 3.0))
        return ok

    # ---------------------------------------------------------------- skin
    def skin(self, mat, drop_below=0.0):
        """Add the uncovered base body faces + eyes. Records faces for UV unwrap."""
        P, faces = self.P, self.base.faces
        keep = []
        for fi, f in enumerate(faces):
            if all(self.covered[i] for i in f):
                continue
            if drop_below and all(P[i, 2] < drop_below for i in f):
                continue
            keep.append(fi)
        used = sorted({i for fi in keep for i in faces[fi]})
        remap = {v: i for i, v in enumerate(used)}
        vs, fl = add_geom(self.m, P[used], [tuple(remap[i] for i in faces[fi]) for fi in keep], mat)
        self.skin_faces = list(zip(fl, keep))
        self.mine.update(fl)
        self.eye_faces = []
        for sd in ("R", "L"):
            e = self.base.eyes[sd]
            ec = e.mean(0)
            e = ec + (e - ec) * 0.97 + np.array([0.0, -0.0035 * self.s, 0.0015 * self.s])   # a little deeper / higher so the upper lid overlaps the iris top
            vs, fe = add_geom(self.m, e, self.base.eye_faces, mat)
            self.mine.update(fe)
            self.eye_faces.append((fe, e.mean(0)))
        return len(keep)

    def skin_uv(self, hand_names=("palm", "fing", "thumb")):
        """Unwrap the skin faces with smart_project per group and pack the groups into atlas squares; eyes into the eye tile."""
        m, dom = self.m, self.dom
        uvl = m.uv
        groups = {"head": [], "hands": [], "rest": []}
        for fc, fi in self.skin_faces:
            d = [dom[i] for i in self.base.faces[fi]]
            if self.is_head[list(self.base.faces[fi])].any() or any(x == "neck" for x in d):
                groups["head"].append((fc, fi))
            elif any(x.startswith(hand_names) for x in d):
                groups["hands"].append((fc, fi))
            else:
                groups["rest"].append((fc, fi))
        rects = {"head": (0.25, 0.0, 1.0, 0.75), "hands": (0.0, 0.0, 0.25, 0.25), "rest": (0.0, 0.25, 0.25, 0.5)}
        for name, items in groups.items():
            if not items:
                continue
            bmt = bmesh.new()
            vmap = {}
            ft = []
            for fc, fi in items:
                vl = []
                for v in fc.verts:
                    if v not in vmap:
                        vmap[v] = bmt.verts.new(v.co)
                    vl.append(vmap[v])
                ft.append(bmt.faces.new(vl))
            me = bpy.data.meshes.new("uvtmp")
            bmt.to_mesh(me)
            bmt.free()
            ob = bpy.data.objects.new("uvtmp", me)
            bpy.context.scene.collection.objects.link(ob)
            bpy.context.view_layer.objects.active = ob
            for o in bpy.context.scene.objects:
                o.select_set(o is ob)
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(angle_limit=math.radians(72), island_margin=0.012, area_weight=0.6)
            bpy.ops.uv.pack_islands(margin=0.012)
            bpy.ops.object.mode_set(mode="OBJECT")
            uvd = me.uv_layers.active.data
            allu = np.array([l.uv[:] for l in uvd])
            lo, hi = allu.min(0), allu.max(0)
            u0, v0, u1, v1 = rects[name]
            for pi, (fc, fi) in enumerate(items):
                poly = me.polygons[pi]
                for k, lp in enumerate(fc.loops):
                    uv = uvd[poly.loop_start + k].uv
                    lp[uvl].uv = (u0 + (uv[0] - lo[0]) / max(hi[0] - lo[0], 1e-9) * (u1 - u0), v0 + (uv[1] - lo[1]) / max(hi[1] - lo[1], 1e-9) * (v1 - v0))
                m.explicit.add(fc)
            bpy.data.objects.remove(ob)
            bpy.data.meshes.remove(me)
        for fe, c in self.eye_faces:
            for fc in fe:
                for lp in fc.loops:
                    d = unit(np.array(lp.vert.co) - c)
                    lp[uvl].uv = tuple(SK.eye_uv(d)[0])
                m.explicit.add(fc)

    # ---------------------------------------------------------------- finish
    def solve_pelvis(self, pose, weight, reach=0.985):
        """Pelvis height so the weight-bearing leg is nearly straight (reach * full leg length); sets pose['pelvis_shift']."""
        L = self.base.L
        sd = 1 if weight == "R" else -1
        leg = np.linalg.norm(L[f"knee{sd}"] - L[f"hip{sd}"]) + np.linalg.norm(L[f"ankle{sd}"] - L[f"knee{sd}"])
        sx, sy = pose["pelvis_shift"][:2]
        fx, fy, _ = pose["feet"][weight]
        hip = L[f"hip{sd}"]
        horiz = math.hypot(hip[0] + sx - fx, hip[1] + sy - fy)
        az = L[f"ankle{sd}"][2] + pose.get("ankle_lift", 0.0)
        dz = az + math.sqrt(max((reach * leg) ** 2 - horiz ** 2, 0.0)) - hip[2]
        pose["pelvis_shift"] = (sx, sy, dz)
        return dz

    def pose(self, pose, gaze=None, gaze_limit=math.radians(22)):
        """Skin every vertex of the shared mesh with the capsule rig (rest position -> weights) and apply the pose."""
        bm = self.m.bm
        pts = np.array([v.co[:] for v in bm.verts])
        W = self.rig.weights(pts)
        T = self.rig.transforms(pose)
        out = self.rig.apply(pts, W, T)
        for v, p in zip(bm.verts, out):
            v.co = tuple(float(c) for c in p)
        # eyes: turn the (already posed) eyeballs about their centres towards the gaze target
        if gaze is not None:
            for fe, c in self.eye_faces:
                vs = sorted({v for fc in fe for v in fc.verts}, key=lambda v: v.index)
                cc = np.mean([v.co[:] for v in vs], 0)
                hf = T["head"][0] @ np.array([0, 1.0, 0])
                want = unit(np.asarray(gaze) - cc)
                ang = math.acos(max(-1, min(1, float(hf @ want))))
                if ang > 1e-4:
                    R = HU.rot_between(hf, want) if ang <= gaze_limit else HU.rot_axis(np.cross(hf, want), gaze_limit)
                    for v in vs:
                        v.co = tuple(float(x) for x in (R @ (np.array(v.co[:]) - cc) + cc))
        self.T = T
        return self.rig.info
