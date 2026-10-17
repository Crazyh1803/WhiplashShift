"""Booleans cutters (arches, window/lamp/grille recesses) and seated glass panels."""
import math

import bmesh
import bpy
from mathutils import Vector

import boilerfang_core as C
import boilerfang_trace as T

LINER_SLOT = 4  # shell material slot used for cutter faces (matte black)
ARCH_MARGIN = {"truck": 0.0753, "coupe": 0.0647}


class Surface:
    """Ray projector over the evaluated shell (world coordinates)."""

    def __init__(self, obj):
        mesh = C.evaluated_mesh(obj)
        self.bvh = C.bvh_of(mesh)
        bpy.data.meshes.remove(mesh)

    def cast(self, origin, direction):
        hit, normal, _, _ = self.bvh.ray_cast(Vector(origin), Vector(direction))
        return hit, normal

    def side(self, x, z, sign):
        hit, n = self.cast((x, sign * 3.0, z), (0, -sign, 0))
        assert hit is not None, ("side miss", x, z, sign)
        return hit, n

    def top(self, x, y):
        hit, n = self.cast((x, y, 3.0), (0, 0, -1))
        assert hit is not None, ("top miss", x, y)
        return hit, n

    def front(self, y, z, sign):
        hit, n = self.cast((sign * 4.0, y, z), (-sign, 0, 0))
        assert hit is not None, ("front miss", y, z, sign)
        return hit, n


def densify(points, step):
    """Insert points on a closed polygon so no edge is longer than step."""
    out = []
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        a, b = Vector(a), Vector(b)
        count = max(1, math.ceil((b - a).length / step))
        out.extend(a.lerp(b, k / count) for k in range(count))
    return out


def inset_polygon(points, distance):
    """Miter-offset a closed planar-ish 2D polygon (counter-clockwise) inward."""
    n = len(points)
    area = sum(points[i][0] * points[(i + 1) % n][1] - points[(i + 1) % n][0] * points[i][1]
               for i in range(n))
    if area < 0:
        points = list(reversed(points))
    out = []
    for i in range(n):
        p0, p1, p2 = (Vector(points[(i + k) % n]) for k in (-1, 0, 1))
        e0 = (p1 - p0).normalized()
        e1 = (p2 - p1).normalized()
        n0 = Vector((-e0.y, e0.x))
        n1 = Vector((-e1.y, e1.x))
        bis = (n0 + n1)
        if bis.length < 1e-6:
            out.append(p1 + n0 * distance)
            continue
        bis.normalize()
        scale = distance / max(0.35, bis.dot(n0))
        out.append(p1 + bis * scale)
    return out if area >= 0 else list(reversed(out))


def _inside(poly, x, y):
    inside = False
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            inside = not inside
    return inside


def _edge_distance(poly, x, y):
    best = 1e9
    n = len(poly)
    for i in range(n):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / max(dx * dx + dy * dy, 1e-12)))
        best = min(best, math.hypot(x - ax - t * dx, y - ay - t * dy))
    return best


def fill_polygon(bm, pts, step, axes=(0, 2)):
    """Constrained-Delaunay fill of a closed polygon with a regular interior point grid."""
    from mathutils.geometry import delaunay_2d_cdt
    i, j = axes
    flat = [(p[i], p[j]) for p in pts]
    plane = sum(p[3 - i - j] for p in pts) / len(pts)
    xs, ys = [q[0] for q in flat], [q[1] for q in flat]
    coords = [Vector(q) for q in flat]
    nx = int((max(xs) - min(xs)) / step) + 1
    ny = int((max(ys) - min(ys)) / step) + 1
    for a in range(1, nx):
        for b in range(1, ny):
            x, y = min(xs) + a * step, min(ys) + b * step
            if _inside(flat, x, y) and _edge_distance(flat, x, y) > step * 0.45:
                coords.append(Vector((x, y)))
    n = len(pts)
    edges = [(k, (k + 1) % n) for k in range(n)]
    verts, _, faces, _, _, _ = delaunay_2d_cdt(coords, edges, [], 1, 1e-5)
    created = []
    for v in verts:
        co = [0.0, 0.0, 0.0]
        co[i], co[j], co[3 - i - j] = v.x, v.y, plane
        created.append(bm.verts.new(co))
    for f in faces:
        if len(f) >= 3:
            bm.faces.new([created[k] for k in f])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return created


def make_recess_cutter(builder, name, outline, mode, surface, sign=1, depth=0.008, lift=0.03,
                       step=0.09, boundary_step=0.04):
    """Closed cutter whose floor follows the shell `depth` below its surface.

    `outline` is a flat closed polygon in world space (x/z for side, x/y for top, y/z for
    front); each vertex of the filled outline is ray-projected onto the shell.
    """
    pts = densify(outline, boundary_step)
    bm = bmesh.new()
    axes = {"side": (0, 2), "top": (0, 1), "front": (1, 2)}[mode]
    outward = Vector({"side": (0, sign, 0), "top": (0, 0, 1), "front": (sign, 0, 0)}[mode])
    fill_polygon(bm, pts, step, axes)
    top = bm.copy()
    for v, tv in zip(bm.verts, top.verts):
        p = v.co
        if mode == "side":
            hit, n = surface.side(p[0], p[2], sign)
        elif mode == "top":
            hit, n = surface.top(p[0], p[1])
        else:
            hit, n = surface.front(p[1], p[2], sign)
        v.co = hit - outward * depth
        tv.co = hit + outward * lift
    for f in top.faces:
        f.normal_flip()
    top_mesh = bpy.data.meshes.new("tmp_top")
    top.to_mesh(top_mesh)
    top.free()
    bm.from_mesh(top_mesh)
    bpy.data.meshes.remove(top_mesh)
    # side walls: boundary edges of the floor grid joined to the lifted grid
    bm.verts.index_update()
    bm.verts.ensure_lookup_table()
    half = len(bm.verts) // 2
    bm.edges.ensure_lookup_table()
    boundary = [e for e in bm.edges if e.is_boundary and e.verts[0].index < half]
    for e in boundary:
        a, b = e.verts
        bm.faces.new((a, b, bm.verts[b.index + half], bm.verts[a.index + half]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    for face in bm.faces:
        face.material_index = LINER_SLOT
    mesh = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(mesh)
    bm.free()
    for key in ("paint", "paint2", "accent", "dark", "rubber"):
        mesh.materials.append(builder.mats[key])
    obj = bpy.data.objects.new(name, mesh)
    obj.display_type = "WIRE"
    obj.hide_render = True
    builder.cols["CUTTERS"].objects.link(obj)
    return obj


def arch_cutters(builder):
    """Pairs of cylinders (one per side) centred on each physical axle."""
    objs = []
    for end in ("truck", "coupe"):
        radius = T.WHEEL_R[end] + ARCH_MARGIN[end]
        bm = bmesh.new()
        for side in (-1, 1):
            geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=64, radius1=radius,
                                         radius2=radius, depth=0.8)
            for v in geom["verts"]:
                # cone axis is Z: rotate onto Y, then move to the wheel centre
                x, y, z = v.co
                v.co = Vector((x + T.WHEEL_X[end], side * (0.60 + 0.4) + z * 1.0,
                               y + T.WHEEL_R[end]))
            # the axis swap mirrors the cone; make the shell outward-facing explicitly
            faces = list({f for v in geom["verts"] for f in v.link_faces})
            volume = sum(f.verts[0].co.dot(f.verts[i].co.cross(f.verts[i + 1].co)) / 6
                         for f in faces for i in range(1, len(f.verts) - 1))
            if volume < 0:
                for f in faces:
                    f.normal_flip()
        mesh = bpy.data.meshes.new(f"Cutter_Arch_{end}_mesh")
        bm.to_mesh(mesh)
        bm.free()
        for key in ("paint", "paint2", "accent", "dark", "rubber"):
            mesh.materials.append(builder.mats[key])
        for poly in mesh.polygons:
            poly.material_index = LINER_SLOT
        obj = bpy.data.objects.new(f"Cutter_Arch_{end}", mesh)
        obj.display_type = "WIRE"
        obj.hide_render = True
        builder.cols["CUTTERS"].objects.link(obj)
        objs.append(obj)
    return objs


def assert_cutters_outward(collection):
    """Every cutter island must have positive signed volume (outward normals)."""
    for obj in collection.objects:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        islands, seen = [], set()
        for face in bm.faces:
            if face in seen:
                continue
            stack, comp = [face], []
            while stack:
                g = stack.pop()
                if g in seen:
                    continue
                seen.add(g)
                comp.append(g)
                stack.extend(h for e in g.edges for h in e.link_faces if h not in seen)
            islands.append(comp)
        for comp in islands:
            vol = sum(f.verts[0].co.dot(f.verts[i].co.cross(f.verts[i + 1].co)) / 6
                      for f in comp for i in range(1, len(f.verts) - 1))
            assert vol > 0, f"cutter {obj.name} has an inward-facing island ({vol:.5f})"
            assert all(e.is_manifold for f in comp for e in f.edges), f"cutter {obj.name} not closed"
        bm.free()


def add_boolean(shell, collection):
    assert_cutters_outward(collection)
    mod = shell.modifiers.new("GenuineCuts", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.operand_type = "COLLECTION"
    mod.collection = collection
    mod.solver = "EXACT"
    return mod


def glass_panel(builder, name, outline_pts, surface, cast_dir_fn, clearance, step=0.11,
                mat="glass", axes=(0, 2)):
    """Planar fill of a (near planar) 3D outline, projected onto `surface`.

    `cast_dir_fn(point)` returns (origin, direction) for the ray that finds the recess
    floor under that point.
    """
    bm = bmesh.new()
    fill_polygon(bm, [Vector(p) for p in densify(outline_pts, 0.03)], step, axes)
    for v in bm.verts:
        origin, direction = cast_dir_fn(v.co)
        hit, normal = surface.cast(origin, direction)
        assert hit is not None, ("glass ray miss", name, tuple(v.co))
        v.co = hit - Vector(direction).normalized() * clearance
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    for face in bm.faces:
        _, direction = cast_dir_fn(face.calc_center_median())
        if face.normal.dot(-Vector(direction)) < 0:
            face.normal_flip()
    mesh = bpy.data.meshes.new(name + "_mesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(builder.mats[mat])
    obj = bpy.data.objects.new(name, mesh)
    builder.cols["BOILERFANG_SOURCE"].objects.link(obj)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj
