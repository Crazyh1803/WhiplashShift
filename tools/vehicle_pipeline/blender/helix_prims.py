"""Bevelled hard-surface primitives: boxes, prisms, sweeps, lathes."""
import math

import bmesh
from mathutils import Matrix, Vector

import helix_core as C


def frame(normal, up_hint=(0, 0, 1)):
    """Matrix whose Z axis is `normal` and X axis follows `up_hint` x normal."""
    z = Vector(normal).normalized()
    up = Vector(up_hint)
    if abs(z.dot(up.normalized())) > 0.98:
        up = Vector((1, 0, 0)) if abs(z.x) < 0.9 else Vector((0, 1, 0))
    x = up.cross(z).normalized()
    y = z.cross(x).normalized()
    return Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z))).to_4x4()


def finish(builder, name, bm, mats, location=(0, 0, 0), matrix=None, face_mat=0, smooth_angle=35,
           col="HELIX_SOURCE"):
    if isinstance(mats, str):
        mats = [mats]
    for face in bm.faces:
        if face.material_index == 0:
            face.material_index = face_mat
    obj = C.bm_to_object(builder, name, bm, mats, col=col, location=location)
    if matrix is not None:
        obj.matrix_world = matrix
    C.harden(obj, smooth_angle)
    return obj


def bevel_edges(bm, width, segments=2, angle=0.0):
    edges = [e for e in bm.edges if len(e.link_faces) != 2
             or e.calc_face_angle(0.0) > math.radians(angle if angle else 20)]
    if edges and width > 0:
        bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segments, affect="EDGES")


def rbox(builder, name, size, mat, bevel=0.008, segments=1, location=(0, 0, 0), matrix=None,
         offset=(0, 0, 0)):
    """Rounded box. `size` in local axes; `matrix` places it (default identity at location)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0] + offset[0], v.co.y * size[1] + offset[1],
                       v.co.z * size[2] + offset[2]))
    bevel_edges(bm, min(bevel, min(size) * 0.45), segments)
    return finish(builder, name, bm, mat, location=location, matrix=matrix)


def prism(builder, name, poly, mat, thickness, bevel=0.004, matrix=None, location=(0, 0, 0),
          z0=0.0):
    """Extrude a 2D polygon (x/y) along local +Z by `thickness`, starting at z0."""
    bm = bmesh.new()
    bottom = [bm.verts.new((p[0], p[1], z0)) for p in poly]
    top = [bm.verts.new((p[0], p[1], z0 + thickness)) for p in poly]
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bevel_edges(bm, min(bevel, thickness * 0.45), 1)
    return finish(builder, name, bm, mat, location=location, matrix=matrix)


def rounded_rect(w, h, r, steps=3):
    """Closed rounded rectangle polygon centred on the origin (counter-clockwise)."""
    pts = []
    hw, hh = w / 2 - r, h / 2 - r
    for cx, cy, a0 in ((hw, hh, 0), (-hw, hh, 90), (-hw, -hh, 180), (hw, -hh, 270)):
        for k in range(steps + 1):
            a = math.radians(a0 + 90 * k / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def ellipse(w, h, segments=24):
    return [(w / 2 * math.cos(math.tau * k / segments), h / 2 * math.sin(math.tau * k / segments))
            for k in range(segments)]


def sweep(builder, name, path, mat, radius=0.02, sides=8, cyclic=False, caps=True,
          profile=None, up=(0, 0, 1)):
    """Sweep a round (or custom closed `profile` of (a,b) pairs) section along a 3D path."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    prof = profile or [(radius * math.cos(math.tau * k / sides), radius * math.sin(math.tau * k / sides))
                       for k in range(sides)]
    m = len(prof)
    bm = bmesh.new()
    rings = []
    prev_normal = None
    for i, p in enumerate(pts):
        if cyclic:
            t = (pts[(i + 1) % n] - pts[(i - 1) % n]).normalized()
        elif i == 0:
            t = (pts[1] - pts[0]).normalized()
        elif i == n - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = (pts[i + 1] - pts[i - 1]).normalized()
        ref = Vector(up)
        if abs(t.dot(ref)) > 0.97:
            ref = Vector((1, 0, 0))
        a = ref.cross(t).normalized()
        b = t.cross(a).normalized()
        # miter scale at corners keeps the section thickness constant
        scale = 1.0
        if 0 < i < n - 1 or cyclic:
            d0 = (p - pts[i - 1]).normalized()
            d1 = (pts[(i + 1) % n] - p).normalized()
            cosang = max(-1.0, min(1.0, d0.dot(d1)))
            scale = 1.0 / max(0.5, math.sqrt((1 + cosang) / 2))
        ring = [bm.verts.new(p + a * (u * scale) + b * v) for u, v in prof]
        rings.append(ring)
    for i in range(n - 1 + (1 if cyclic else 0)):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for k in range(m):
            bm.faces.new((r0[k], r0[(k + 1) % m], r1[(k + 1) % m], r1[k]))
    if caps and not cyclic:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return finish(builder, name, bm, mat, smooth_angle=50)


def rounded_path(corners, radius, steps=4):
    """Fillet the interior corners of a polyline path (3D)."""
    pts = [Vector(c) for c in corners]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        d0, d1 = (a - b), (c - b)
        r = min(radius, d0.length * 0.45, d1.length * 0.45)
        p0 = b + d0.normalized() * r
        p1 = b + d1.normalized() * r
        for k in range(steps + 1):
            t = k / steps
            q0, q1 = p0.lerp(b, t), b.lerp(p1, t)
            out.append(q0.lerp(q1, t))
    out.append(pts[-1])
    return out


def lathe(bm, profile, segments, axis=1, center=(0, 0, 0), start=0.0, turn=math.tau):
    """Revolve (radius, axial) points around `axis` (0=x,1=y,2=z); returns vertex rings."""
    rings = []
    cx, cy, cz = center
    full = abs(turn - math.tau) < 1e-6
    steps = segments if full else segments - 1  # partial sweeps keep both end rings
    for k in range(segments):
        ang = start + turn * k / steps
        ca, sa = math.cos(ang), math.sin(ang)
        ring = []
        for r, h in profile:
            if axis == 1:
                co = (cx + r * ca, cy + h, cz + r * sa)
            elif axis == 0:
                co = (cx + h, cy + r * ca, cz + r * sa)
            else:
                co = (cx + r * ca, cy + r * sa, cz + h)
            ring.append(bm.verts.new(co))
        rings.append(ring)
    m = len(profile)
    for k in range(segments if full else segments - 1):
        r0, r1 = rings[k], rings[(k + 1) % segments]
        for i in range(m - 1):
            if profile[i][0] == 0 and profile[i + 1][0] == 0:
                continue
            quad = (r0[i], r0[i + 1], r1[i + 1], r1[i])
            if len(set(quad)) == len(quad):
                bm.faces.new(quad)
            else:
                tri = [v for idx, v in enumerate(quad) if v not in quad[:idx]]
                if len(tri) >= 3:
                    bm.faces.new(tri)
    return rings


def _ring_point(spec, t):
    """Super-elliptic section point (y, z) at angle t for a loft station."""
    c, s = math.cos(t), math.sin(t)
    e = 2.0 / spec["n"]
    y = spec["y0"] + spec["hw"] * math.copysign(abs(c) ** e, c)
    zc = (spec["zt"] + spec["zb"]) / 2
    half = (spec["zt"] - spec["zb"]) / 2 if s >= 0 else (spec["zt"] - spec["zb"]) / 2 * spec.get("belly", 1.0)
    z = zc + half * math.copysign(abs(s) ** e, s)
    return y, z


def loft(builder, name, stations, mats, sides=28, cap_ends=True, smooth_angle=50, face_mat=0,
         col="HELIX_SOURCE"):
    """Loft closed super-elliptic sections along X. Station keys: x, y0, hw, zt, zb, n[, belly]."""
    bm = bmesh.new()
    rings = []
    for st in stations:
        spec = dict(y0=0.0, n=2.4)
        spec.update(st)
        ring = []
        for k in range(sides):
            y, z = _ring_point(spec, math.tau * k / sides)
            ring.append(bm.verts.new((spec["x"], y, z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides],
                          rings[i + 1][k]))
    if cap_ends:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return finish(builder, name, bm, mats, smooth_angle=smooth_angle, face_mat=face_mat, col=col)


def tube(builder, name, path, radii, mat, sides=10, ribs=0, rib_depth=0.0, up=(0, 0, 1), caps=True):
    """Tapered sweep with optional transverse ribbing (radius modulated along the path)."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        t = ((pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])).normalized()
        ref = Vector(up)
        if abs(t.dot(ref)) > 0.97:
            ref = Vector((1, 0, 0))
        a = ref.cross(t).normalized()
        b = t.cross(a).normalized()
        r = radii[i] if isinstance(radii, (list, tuple)) else radii
        if ribs:
            r *= 1.0 + rib_depth * (1 if math.cos(math.pi * ribs * i / (n - 1)) > 0.25 else -0.4)
        ring = [bm.verts.new(p + a * (r * math.cos(math.tau * k / sides))
                             + b * (r * math.sin(math.tau * k / sides))) for k in range(sides)]
        rings.append(ring)
    for i in range(n - 1):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides],
                          rings[i + 1][k]))
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return finish(builder, name, bm, mat, smooth_angle=45)


def bezier(points, steps):
    """Sample a cubic (4 points) or quadratic (3 points) Bezier."""
    pts = [Vector(p) for p in points]
    out = []
    for k in range(steps + 1):
        t = k / steps
        q = pts
        while len(q) > 1:
            q = [q[i].lerp(q[i + 1], t) for i in range(len(q) - 1)]
        out.append(q[0])
    return out


def cylinder(builder, name, radius, length, mat, axis="y", sides=24, location=(0, 0, 0), r2=None,
             bevel=0.0):
    """Capped cylinder/cone centred on `location`, axis along local x/y/z."""
    bm = bmesh.new()
    top = [bm.verts.new((radius * math.cos(math.tau * k / sides), radius * math.sin(math.tau * k / sides),
                         length / 2)) for k in range(sides)]
    rb = radius if r2 is None else r2
    bot = [bm.verts.new((rb * math.cos(math.tau * k / sides), rb * math.sin(math.tau * k / sides),
                         -length / 2)) for k in range(sides)]
    for k in range(sides):
        bm.faces.new((bot[k], bot[(k + 1) % sides], top[(k + 1) % sides], top[k]))
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bevel:
        bevel_edges(bm, bevel, 1)
    rot = {"x": Matrix.Rotation(math.pi / 2, 4, "Y"), "y": Matrix.Rotation(-math.pi / 2, 4, "X"),
           "z": Matrix.Identity(4)}[axis]
    return finish(builder, name, bm, mat, matrix=Matrix.Translation(location) @ rot, smooth_angle=40)


def bm_box(bm, center, size, rot=None):
    """Append an unbevelled box (optionally rotated by a 3x3 matrix) to a bmesh."""
    ex = []
    for sx in (-0.5, 0.5):
        for sy in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                v = Vector((sx * size[0], sy * size[1], sz * size[2]))
                if rot is not None:
                    v = rot @ v
                ex.append(bm.verts.new(Vector(center) + v))
    idx = ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))
    for f in idx:
        bm.faces.new([ex[i] for i in f])


def bm_cone(bm, base, direction, radius, height, sides=6):
    d = Vector(direction).normalized()
    m = frame(d)
    ring = [bm.verts.new(Vector(base) + m @ Vector((radius * math.cos(math.tau * k / sides),
                                                    radius * math.sin(math.tau * k / sides), 0)))
            for k in range(sides)]
    apex = bm.verts.new(Vector(base) + d * height)
    for k in range(sides):
        bm.faces.new((ring[k], ring[(k + 1) % sides], apex))
    bm.faces.new(list(reversed(ring)))


def bm_cyl(bm, center, axis, radius, length, sides=8):
    d = Vector(axis).normalized()
    m = frame(d)
    top, bot = [], []
    for k in range(sides):
        off = m @ Vector((radius * math.cos(math.tau * k / sides), radius * math.sin(math.tau * k / sides), 0))
        top.append(bm.verts.new(Vector(center) + off + d * length / 2))
        bot.append(bm.verts.new(Vector(center) + off - d * length / 2))
    for k in range(sides):
        bm.faces.new((bot[k], bot[(k + 1) % sides], top[(k + 1) % sides], top[k]))
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)


def bm_object(builder, name, bm, mat, smooth_angle=40):
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return finish(builder, name, bm, mat, smooth_angle=smooth_angle)
