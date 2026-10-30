"""Shared Blender (bmesh) helpers for the industrial market benchmark: one combined mesh per asset, real UVs,
PBR texture materials, ray-cast ambient occlusion in COLOR_0 and a plain GLB export. Blender Z-up, front = +Y
(exports to glTF Y-up, front -Z)."""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

V = Vector


def catmull(pts, n):
    """Centripetal-ish Catmull-Rom through pts (sequence of floats-tuples/Vectors) -> n samples (uniform in index)."""
    m = len(pts)
    if m == 2 or n <= 2:
        return [pts[0] + (pts[-1] - pts[0]) * (i / (n - 1)) for i in range(n)]
    out = []
    for i in range(n):
        f = i / (n - 1) * (m - 1)
        k = min(int(f), m - 2)
        t = f - k
        p0, p1, p2, p3 = pts[max(k - 1, 0)], pts[k], pts[k + 1], pts[min(k + 2, m - 1)]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return out


def cat_scalar(vals, n):
    return [x[0] for x in catmull([V((v, 0, 0)) for v in vals], n)]


class Mesh:
    def __init__(self, mats):
        self.bm = bmesh.new()
        self.mats = list(mats)
        self.uv = self.bm.loops.layers.uv.get("UVMap") or self.bm.loops.layers.uv.new("UVMap")
        self.explicit = set()           # faces whose UVs a builder authored (box_uv skips them)

    def mi(self, name):
        return self.mats.index(name)

    # ---------------------------------------------------------------- low-level
    def surface(self, rows, closed, mat, smooth=True, uv_fn=None, flip=False):
        """Quad surface through a rows x cols grid of points. closed wraps the columns. uv_fn(row, col, total_rows, total_cols)->(u,v)."""
        bm = self.bm
        mi = self.mi(mat) if isinstance(mat, str) else mat
        vs = [[bm.verts.new(p) for p in r] for r in rows]
        nr, nc = len(rows), len(rows[0])
        faces = []
        for i in range(nr - 1):
            for j in range(nc if closed else nc - 1):
                j2 = (j + 1) % nc
                quad = [vs[i][j], vs[i][j2], vs[i + 1][j2], vs[i + 1][j]]
                if flip:
                    quad.reverse()
                try:
                    f = bm.faces.new(quad)
                except ValueError:
                    continue
                f.material_index = mi
                f.smooth = smooth
                if uv_fn:
                    self.explicit.add(f)
                    ju = [(i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)]
                    if flip:
                        ju.reverse()
                    for lp, (ri, cj) in zip(f.loops, ju):
                        lp[self.uv].uv = uv_fn(ri, cj, nr, nc)
                faces.append(f)
        return faces, vs

    def fan_cap(self, ring, center, mat, flip=False, smooth=False):
        bm = self.bm
        mi = self.mi(mat) if isinstance(mat, str) else mat
        c = bm.verts.new(center)
        n = len(ring)
        fs = []
        for j in range(n):
            tri = [ring[j], ring[(j + 1) % n], c]
            if flip:
                tri.reverse()
            try:
                f = bm.faces.new(tri)
            except ValueError:
                continue
            f.material_index = mi
            f.smooth = smooth
            fs.append(f)
        return fs

    def _xf(self, geom_verts, matrix):
        bmesh.ops.transform(self.bm, matrix=matrix, verts=geom_verts)

    def _set(self, faces, mi, smooth):
        for f in faces:
            f.material_index = mi
            f.smooth = smooth

    # ---------------------------------------------------------------- primitives
    def box(self, c, size, mat, rot=(0, 0, 0), bevel=0.0, smooth=False, seg=1):
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        vs = r["verts"]
        m = Matrix.Translation(V(c)) @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X") \
            @ Matrix.Diagonal(V((size[0], size[1], size[2], 1)))
        self._xf(vs, m)
        edges = {e for v in vs for e in v.link_edges}
        faces = {f for v in vs for f in v.link_faces}
        mi = self.mi(mat)
        self._set(faces, mi, smooth)
        if bevel > 0:
            res = bmesh.ops.bevel(self.bm, geom=list(edges) + vs, offset=bevel, segments=seg, affect="EDGES")
            faces = set(res["faces"])
            self._set(faces, mi, smooth)
        return faces

    def cyl(self, p0, p1, r0, r1=None, mat="steel", seg=12, caps=True, smooth=True):
        r1 = r0 if r1 is None else r1
        p0, p1 = V(p0), V(p1)
        d = p1 - p0
        L = d.length
        if L < 1e-6:
            return []
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=L)
        vs = res["verts"]
        rot = V((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        self._xf(vs, Matrix.Translation((p0 + p1) / 2) @ rot)
        faces = {f for v in vs for f in v.link_faces}
        self._set(faces, self.mi(mat), smooth)
        return faces

    def sphere(self, c, r, mat, scale=(1, 1, 1), seg=12, rings=8, smooth=True, rot=None):
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=r)
        vs = res["verts"]
        m = Matrix.Translation(V(c))
        if rot is not None:
            m = m @ rot
        m = m @ Matrix.Diagonal(V((scale[0], scale[1], scale[2], 1)))
        self._xf(vs, m)
        faces = {f for v in vs for f in v.link_faces}
        self._set(faces, self.mi(mat), smooth)
        return faces

    def lathe(self, profile, c, mat, axis=(0, 0, 1), seg=24, smooth=True, uv_scale=None):
        """profile: [(radius, height)] along local z; revolved about `axis` through c."""
        ax = V(axis).normalized()
        rot = V((0, 0, 1)).rotation_difference(ax).to_matrix().to_4x4()
        T = Matrix.Translation(V(c)) @ rot
        rows = []
        for (r, h) in profile:
            rows.append([T @ V((r * math.cos(2 * math.pi * j / seg), r * math.sin(2 * math.pi * j / seg), h)) for j in range(seg)])
        faces, _ = self.surface(rows, True, mat, smooth=smooth)
        return faces

    def text(self, body, size, loc, rot, mat, extrude=0.02, align="CENTER", spacing=1.0, bevel=0.0, font=None, width_fit=None):
        cu = bpy.data.curves.new("txt", "FONT")
        cu.body = body
        cu.size = size
        cu.extrude = extrude
        cu.bevel_depth = bevel
        cu.resolution_u = 2
        cu.align_x = align
        cu.align_y = "CENTER"
        cu.space_character = spacing
        if font:
            cu.font = font
        ob = bpy.data.objects.new("txt", cu)
        bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.objects.active = ob
        for o in bpy.context.selected_objects:
            o.select_set(False)
        ob.select_set(True)
        bpy.ops.object.convert(target="MESH")
        me = ob.data
        tmp = bmesh.new()
        tmp.from_mesh(me)
        if width_fit:
            xs = [v.co.x for v in tmp.verts]
            w = max(xs) - min(xs)
            bmesh.ops.scale(tmp, vec=(width_fit / w, 1.0, 1.0), verts=tmp.verts) if w > 1e-6 else None
        rotm = Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X")
        bmesh.ops.transform(tmp, matrix=Matrix.Translation(V(loc)) @ rotm, verts=tmp.verts)
        tmpme = bpy.data.meshes.new("t2")
        tmp.to_mesh(tmpme)
        tmp.free()
        mi = self.mi(mat)
        n0 = len(self.bm.faces)
        self.bm.from_mesh(tmpme)
        for f in list(self.bm.faces)[n0:]:
            f.material_index = mi
            f.smooth = False
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(tmpme)
        return list(self.bm.faces)[n0:]

    def tube(self, pts, radii, mat, seg=14, samples=None, ratio=1.0, up=None, disp=None, mat_fn=None, round_ends=(True, True),
             uv=None, smooth=True, closed_path=False, cap_len=None):
        """Swept elliptical tube through pts (Catmull-Rom) with per-point radii. ratio = second semi-axis / first.
        disp(t, ang, base_pos, rx) -> radial multiplier (1 = none). uv: ('tile', u_span, v_scale, v0) -> cylindrical UVs."""
        pts = [V(p) for p in pts]
        n = samples or max(6, len(pts) * 3)
        P = catmull(pts, n)
        R = cat_scalar(list(radii) if hasattr(radii, "__len__") else [radii] * len(pts), n)
        T = []
        for i in range(n):
            a, b = P[max(i - 1, 0)], P[min(i + 1, n - 1)]
            T.append((b - a).normalized())
        frames = []
        if up is not None:
            for t in T:
                u = V(up)
                if abs(t.dot(u.normalized())) > 0.97:
                    u = V((1, 0, 0)) if abs(t.x) < 0.9 else V((0, 1, 0))
                n1 = (u - t * t.dot(u)).normalized()
                frames.append((n1, t.cross(n1).normalized()))
        else:
            ref = V((0, 0, 1)) if abs(T[0].z) < 0.9 else V((1, 0, 0))
            n1 = (ref - T[0] * T[0].dot(ref)).normalized()
            for i, t in enumerate(T):
                n1 = (n1 - t * t.dot(n1)).normalized()
                frames.append((n1, t.cross(n1).normalized()))
        cap = cap_len if cap_len is not None else (R[0] * 0.6)
        rows, rowmeta = [], []

        def ring(Pi, Ri, fr, t, scale_t=1.0):
            row = []
            for j in range(seg):
                ang = 2 * math.pi * j / seg
                base = Pi
                m = disp(t, ang, base, Ri) if disp else 1.0
                row.append(Pi + (fr[0] * math.cos(ang) * Ri + fr[1] * math.sin(ang) * Ri * ratio) * m * scale_t)
            return row
        # start cap rings
        if round_ends[0]:
            for a in (20, 45, 70):                      # tip -> body
                s = math.sin(math.radians(a))
                row = ring(P[0] - T[0] * (cap * math.cos(math.radians(a))), R[0], frames[0], 0.0, s)
                rows.append(row)
                rowmeta.append((0.0, cap * (0.15 if a == 20 else 0.5 if a == 45 else 0.85)))
        base0 = cap * 1.2 if round_ends[0] else 0.0
        for i in range(n):
            t = i / (n - 1)
            rows.append(ring(P[i], R[i], frames[i], t))
            rowmeta.append((t, base0 if i == 0 else rowmeta[-1][1] + (P[i] - P[i - 1]).length))
        if round_ends[1]:
            for k, a in enumerate((70, 45, 20)):        # body -> tip
                s = math.sin(math.radians(a))
                rows.append(ring(P[-1] + T[-1] * (cap * math.cos(math.radians(a))), R[-1], frames[-1], 1.0, s))
                rowmeta.append((1.0, rowmeta[-1][1] + cap * 0.3))
        uvf = None
        if uv:
            total = max(rowmeta[-1][1], 1e-6)
            if uv[0] == "atlas":          # one wrap of the 0.5x0.5 skin tile region (tileable, so the seam is invisible)
                def uvf(ri, cj, nr, nc):
                    return (0.5 * cj / nc, 0.505 + 0.49 * rowmeta[ri][1] / total)
            else:                          # ("cloth", scale): tiling mapping around / along the tube
                circ = 2 * math.pi * sum(R) / len(R) * (1 + ratio) / 2
                k = uv[1]

                def uvf(ri, cj, nr, nc):
                    return (circ * k * cj / nc, k * rowmeta[ri][1])
        # build per-face material by t of the lower row
        faces, verts = [], []
        mi_default = self.mi(mat) if isinstance(mat, str) else mat
        fs, vs = self.surface(rows, True, mi_default, smooth=smooth, uv_fn=uvf)
        if mat_fn:
            nc = seg
            for idx, f in enumerate(fs):
                ri = idx // nc
                t = (rowmeta[ri][0] + rowmeta[min(ri + 1, len(rowmeta) - 1)][0]) / 2
                m = mat_fn(t)
                f.material_index = self.mi(m) if isinstance(m, str) else m
        if round_ends[0] is False:
            self.fan_cap(vs[0], P[0], mat if not mat_fn else mat_fn(0.0), flip=True)
        if round_ends[1] is False:
            self.fan_cap(vs[-1], P[-1], mat if not mat_fn else mat_fn(1.0))
        # close dome tips
        if round_ends[0]:
            self.fan_cap(vs[0], P[0] - T[0] * cap, mat if not mat_fn else mat_fn(0.0), flip=True, smooth=True)
        if round_ends[1]:
            self.fan_cap(vs[-1], P[-1] + T[-1] * cap, mat if not mat_fn else mat_fn(1.0), smooth=True)
        return fs, P, frames

    def loft(self, rings, mat, seg=28, samples=20, disp=None, mat_fn=None, uv=None, smooth=True, close_top=True, close_bot=True):
        """rings: list of dicts z,cx,cy,rx,ry,p (superellipse exponent). Resampled along z with Catmull-Rom."""
        def ring_pts(r):
            out = []
            for j in range(seg):
                a = 2 * math.pi * j / seg
                c, s = math.cos(a), math.sin(a)
                e = 2.0 / r.get("p", 2.0)
                out.append(V((r["cx"] + r["rx"] * math.copysign(abs(c) ** e, c), r["cy"] + r["ry"] * math.copysign(abs(s) ** e, s), r["z"])))
            return out
        base = [ring_pts(r) for r in rings]
        cols = []
        for j in range(seg):
            cols.append(catmull([base[i][j] for i in range(len(rings))], samples))
        rows = [[cols[j][i] for j in range(seg)] for i in range(samples)]
        if disp:
            rows = [[disp(i / (samples - 1), 2 * math.pi * j / seg, rows[i][j]) for j in range(seg)] for i in range(samples)]
        uvf = None
        if uv:
            uspan, vscale, v0 = uv
            uvf = lambda ri, cj, nr, nc: (uspan * cj / nc, v0 + vscale * rows[ri][0].z)
        fs, vs = self.surface(rows, True, self.mi(mat) if isinstance(mat, str) else mat, smooth=smooth, uv_fn=uvf)
        if mat_fn:
            for idx, f in enumerate(fs):
                ri = idx // seg
                m = mat_fn((ri + 0.5) / (samples - 1), rows[ri][0].z)
                f.material_index = self.mi(m) if isinstance(m, str) else m
        if close_top:
            ctr = sum((p for p in rows[-1]), V()) / seg
            self.fan_cap(vs[-1], ctr, mat if not mat_fn else mat_fn(1.0, rows[-1][0].z), smooth=smooth)
        if close_bot:
            ctr = sum((p for p in rows[0]), V()) / seg
            self.fan_cap(vs[0], ctr, mat if not mat_fn else mat_fn(0.0, rows[0][0].z), flip=True, smooth=smooth)
        return fs, rows

    def extrude_profile(self, profile2d, z0, z1, mat, plane="XZ", smooth=False, closed=True):
        """Extrude a closed 2D polygon [(a,b)...] along the third axis (z0..z1). plane XZ extrudes along Y, XY along Z, YZ along X."""
        def m3(a, b, c):
            return {"XZ": V((a, c, b)), "XY": V((a, b, c)), "YZ": V((c, a, b))}[plane]
        bm = self.bm
        mi = self.mi(mat)
        v0 = [bm.verts.new(m3(a, b, z0)) for a, b in profile2d]
        v1 = [bm.verts.new(m3(a, b, z1)) for a, b in profile2d]
        n = len(v0)
        fs = []
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            try:
                fs.append(bm.faces.new([v0[i], v0[j], v1[j], v1[i]]))
            except ValueError:
                pass
        try:
            fs.append(bm.faces.new(v0[::-1]))
            fs.append(bm.faces.new(v1))
        except ValueError:
            pass
        for f in fs:
            f.material_index = mi
            f.smooth = smooth
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        return fs

    # ---------------------------------------------------------------- finishing
    def tris(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def finish_normals(self):
        bmesh.ops.recalc_face_normals(self.bm, faces=list(self.bm.faces))


# ------------------------------------------------------------------------------------------------ UVs
def box_uv(mesh, scale_by_mat, skip=lambda f: False):
    bm = mesh.bm
    uv = mesh.uv
    for f in bm.faces:
        if skip(f) or f in mesh.explicit:
            continue
        name = mesh.mats[f.material_index]
        s = scale_by_mat.get(name, 1.0)
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for lp in f.loops:
            c = lp.vert.co
            if ax == 0:
                u, v = c.y, c.z
            elif ax == 1:
                u, v = c.x, c.z
            else:
                u, v = c.x, c.y
            lp[uv].uv = (u * s, v * s)


def ray_ao(mesh, exclude_mats=(), rays=14, dist=0.5, floor=0.5, bias=0.003, extra=None):
    """Per-corner colour = ambient-occlusion from BVH ray casts (honest geometry occlusion) * optional `extra(p, n, mat)->tint`."""
    bm = mesh.bm
    bm.normal_update()
    tree = BVHTree.FromBMesh(bm)
    layer = bm.loops.layers.color.get("Color") or bm.loops.layers.color.new("Color")
    dirs = []
    for i in range(rays):                     # fibonacci hemisphere, cosine weighted
        u = (i + 0.5) / rays
        phi = i * 2.399963
        r = math.sqrt(u)
        dirs.append((r * math.cos(phi), r * math.sin(phi), math.sqrt(1 - u)))
    cache = {}
    for f in bm.faces:
        mname = mesh.mats[f.material_index]
        for lp in f.loops:
            v = lp.vert
            key = (v.index, f.smooth and 0 or f.index)
            if mname in exclude_mats:
                lp[layer] = (1, 1, 1, 1)
                continue
            n = v.normal if f.smooth else f.normal
            k = (v.index, tuple(round(c, 2) for c in n))
            if k not in cache:
                t1 = V((1, 0, 0)) if abs(n.x) < 0.9 else V((0, 1, 0))
                t1 = (t1 - n * n.dot(t1)).normalized()
                t2 = n.cross(t1)
                occ = 0.0
                o = v.co + n * bias
                for a, b, c in dirs:
                    d = t1 * a + t2 * b + n * c
                    hit = tree.ray_cast(o, d, dist)
                    if hit[0] is not None:
                        occ += 1.0 - hit[3] / dist
                cache[k] = 1.0 - occ / rays
            ao = floor + (1 - floor) * cache[k]
            tint = extra(v.co, n, mname) if extra else (1, 1, 1)
            lp[layer] = (min(1, ao * tint[0]), min(1, ao * tint[1]), min(1, ao * tint[2]), 1.0)


# ------------------------------------------------------------------------------------------------ materials
def make_material(name, tex=None, base=(1, 1, 1), rough=0.7, metal=0.0, emit=None, emit_strength=1.0, normal_strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*base, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if tex:
        def img(path, nc):
            im = bpy.data.images.load(path, check_existing=True)
            im.colorspace_settings.name = "Non-Color" if nc else "sRGB"
            n = nt.nodes.new("ShaderNodeTexImage")
            n.image = im
            n.interpolation = "Linear"
            return n
        a = img(tex["albedo"], False)
        nt.links.new(a.outputs["Color"], bsdf.inputs["Base Color"])
        o = img(tex["orm"], True)
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(o.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        nn = img(tex["normal"], True)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(nn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    return m


def commit(mesh, name, mats):
    """bmesh -> evaluated object linked to the scene with `mats` slots."""
    me = bpy.data.meshes.new(name)
    mesh.bm.to_mesh(me)
    for m in mats:
        me.materials.append(m)
    # Exactly one UV map (TEXCOORD_0) and one colour attribute (COLOR_0 = baked AO x wear), both active and render.
    for extra in [u.name for u in me.uv_layers if u.name != "UVMap"]:
        me.uv_layers.remove(me.uv_layers[extra])
    me.uv_layers.active = me.uv_layers["UVMap"]
    me.uv_layers["UVMap"].active_render = True
    for extra in [c.name for c in me.color_attributes if c.name != "Color"]:
        me.color_attributes.remove(me.color_attributes[extra])
    me.color_attributes.active_color = me.color_attributes["Color"]
    me.color_attributes.render_color_index = me.color_attributes.find("Color")
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def export_glb(ob, path):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True, export_texcoords=True,
              export_normals=True, export_materials="EXPORT", export_cameras=False, export_lights=False, export_animations=False,
              export_image_format="AUTO", export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_colors=True)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    kw = {k: v for k, v in kw.items() if k in props}
    if "export_active_vertex_color_when_no_material" in props:
        kw["export_active_vertex_color_when_no_material"] = True
    bpy.ops.export_scene.gltf(**kw)
    return os.path.getsize(path)
