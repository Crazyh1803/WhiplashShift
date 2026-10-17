"""Station lofts, revolved parts, arch sweeps and rivets for the Boilerfang steam-punk build."""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

import boilerfang_core as C
import boilerfang_prims as P


def section_half(w, zb, zt, rb, rt, crown, steps=3, crown_steps=3, split=None):
    """Right half (y >= 0) of a flat-sided section, bottom centre to top centre.

    Returns (points, roles); role 3 = underside, 1 = lower side band, 0 = upper body."""
    h = zt - zb
    rb = max(1e-4, min(rb, w * 0.9, h * 0.4))
    rt = max(1e-4, min(rt, w * 0.9, h * 0.4))
    lo, hi = zb + rb, zt - rt
    zs = lo + 0.5 * (hi - lo) if split is None else min(max(split, lo + 1e-4), hi - 1e-4)
    pts = [(0.0, zb), (w - rb, zb)]
    for k in range(1, steps + 1):
        a = math.pi / 2 * k / steps
        pts.append((w - rb + rb * math.sin(a), zb + rb - rb * math.cos(a)))
    pts.append((w, zs))
    pts.append((w, hi))
    for k in range(1, steps + 1):
        a = math.pi / 2 * k / steps
        pts.append((w - rt + rt * math.cos(a), hi + rt * math.sin(a)))
    flat = w - rt
    for k in range(1, crown_steps + 1):
        t = k / crown_steps
        pts.append((flat * (1 - t), zt + crown * (1 - (1 - t) ** 2)))
    roles = [3] * (1 + steps) + [1] + [0] * (1 + steps + crown_steps)
    return pts, roles


def full_ring(half, roles=None):
    """Close a right half into a symmetric loop: bottom centre -> right -> top -> left."""
    left = [(-y, z) for y, z in reversed(half[1:-1])]
    ring = half + left
    return (ring, roles + list(reversed(roles))) if roles is not None else ring


def loft(builder, name, stations, mats, row_mats=None, cap=True, smooth_angle=38, location=(0, 0, 0)):
    """Closed lofted solid. stations = [(x, ring)], every ring the same length of (y, z)."""
    n = len(stations[0][1])
    bm = bmesh.new()
    rings = []
    for x, ring in stations:
        assert len(ring) == n, (name, len(ring), n)
        rings.append([bm.verts.new((x, y, z)) for y, z in ring])
    for s in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            f = bm.faces.new((rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]))
            if row_mats:
                f.material_index = row_mats[i]
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, name, bm, mats, location=location, smooth_angle=smooth_angle)


def revolve(builder, name, profile, mats, axis=0, center=(0, 0, 0), segments=24, smooth_angle=45,
            face_mats=None):
    """Revolve (radius, axial) points about X (axis 0), Y (1) or Z (2) through `center`.

    `profile` runs from one axis point (r=0) to another so the solid is closed. `face_mats` is an
    optional per-profile-segment material index list."""
    bm = bmesh.new()
    P.lathe(bm, profile, segments, axis=axis, center=center)
    if face_mats:
        ring_n = len(profile)
        # faces were created ring by ring, segment by segment, skipping axis-only quads
        faces = list(bm.faces)
        idx = 0
        for f in faces:
            ys = f.calc_center_median()
            c = Vector(center)
            axial = [ys.x - c.x, ys.y - c.y, ys.z - c.z][axis]
            best = min(range(len(profile) - 1), key=lambda i: abs((profile[i][1] + profile[i + 1][1]) / 2 - axial))
            f.material_index = face_mats[best]
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, name, bm, mats, smooth_angle=smooth_angle)


def torus(bm, major, minor, center, axis=1, seg=28, rseg=6):
    rings = []
    cx, cy, cz = center
    for i in range(seg):
        a = math.tau * i / seg
        ring = []
        for j in range(rseg):
            b = math.tau * j / rseg
            r = major + minor * math.cos(b)
            h = minor * math.sin(b)
            ca, sa = math.cos(a), math.sin(a)
            if axis == 1:
                co = (cx + r * ca, cy + h, cz + r * sa)
            elif axis == 0:
                co = (cx + h, cy + r * ca, cz + r * sa)
            else:
                co = (cx + r * ca, cy + r * sa, cz + h)
            ring.append(bm.verts.new(co))
        rings.append(ring)
    for i in range(seg):
        a, b = rings[i], rings[(i + 1) % seg]
        for j in range(rseg):
            k = (j + 1) % rseg
            bm.faces.new((a[j], a[k], b[k], b[j]))
    return rings


def arc_points(center, radius, a0, a1, steps, plane="xz"):
    pts = []
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        u, v = center[0] + radius * math.cos(a), center[1] + radius * math.sin(a)
        pts.append((u, v))
    return pts


def band_profile(width, thick, r=0.0015):
    """Rectangular profile (u inward, v across) centred on the path, for arch sweeps."""
    hw, ht = width / 2, thick / 2
    return [(-ht, -hw), (ht, -hw), (ht, hw), (-ht, hw)]


def sweep_band(builder, name, path_xz, y0, y1, thick, mat):
    """Thin curved plate following an X/Z path, spanning y0..y1 (a fender or guard)."""
    yc = (y0 + y1) / 2
    path = [(x, yc, z) for x, z in path_xz]
    prof = band_profile(abs(y1 - y0), thick)
    # sweep() takes (a, b) = (-z-ish normal, +y) for a path along X with up=(0,1,0)
    prof = [(u, v) for u, v in prof]
    return P.sweep(builder, name, path, mat, profile=prof, up=(0, 1, 0))


class Surface:
    """Ray-cast access to the union of the main body meshes (world space)."""

    def __init__(self, objs):
        verts, faces, off = [], [], 0
        deps = bpy.context.evaluated_depsgraph_get()
        for o in objs:
            me = bpy.data.meshes.new_from_object(o.evaluated_get(deps), depsgraph=deps)
            me.transform(o.matrix_world)
            verts += [v.co.copy() for v in me.vertices]
            faces += [tuple(i + off for i in p.vertices) for p in me.polygons]
            off += len(me.vertices)
            bpy.data.meshes.remove(me)
        self.tree = BVHTree.FromPolygons(verts, faces)

    def hit(self, origin, direction):
        loc, nor, idx, dist = self.tree.ray_cast(Vector(origin), Vector(direction).normalized())
        if loc is None:
            return None
        return loc, nor

    def side(self, x, z, sign=1, far=3.0):
        """Outer surface hit at (x, z) looking toward the centre from +/-Y."""
        return self.hit((x, sign * far, z), (0, -sign, 0))

    def top(self, x, y, far=4.0):
        return self.hit((x, y, far), (0, 0, -1))


def rivet_set(builder, name, spots, radius, mat, sink=0.0008):
    """One object of low hemispherical rivet heads; spots = [(position, outward normal)]."""
    bm = bmesh.new()
    for pos, nor in spots:
        n = Vector(nor).normalized()
        t = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
        u = n.cross(t).normalized()
        v = n.cross(u).normalized()
        base = Vector(pos) - n * sink
        ring = [bm.verts.new(base + (u * math.cos(k * math.tau / 6) + v * math.sin(k * math.tau / 6)) * radius)
                for k in range(6)]
        mid = [bm.verts.new(base + n * radius * 0.55 +
                            (u * math.cos(k * math.tau / 6) + v * math.sin(k * math.tau / 6)) * radius * 0.62)
               for k in range(6)]
        apex = bm.verts.new(base + n * radius * 0.8)
        for k in range(6):
            j = (k + 1) % 6
            bm.faces.new((ring[k], ring[j], mid[j], mid[k]))
            bm.faces.new((mid[k], mid[j], apex))
        bm.faces.new(list(reversed(ring)))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return P.finish(builder, name, bm, mat, smooth_angle=60)


def box(builder, name, size, mat, location, bevel=0.004, rot=None):
    m = Matrix.Translation(location)
    if rot:
        m = m @ rot
    return P.rbox(builder, name, size, mat, bevel=bevel, matrix=m)
