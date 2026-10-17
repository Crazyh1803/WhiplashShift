"""Mirrored, support-looped station cage for the Boilerfang body shell."""

import boilerfang_trace as T

# Half-ring vertex roles (index): 0 floor centre .. 14 roof/hood centre.
RING_N = 15
# Face material per ring row: 0 paint, 1 secondary, 2 accent, 3 dark underside.
ROW_MATERIAL = [3, 3, 1, 1, 1, 1, 2] + [0] * 8
MATERIAL_KEYS = ["paint", "paint2", "accent", "dark", "rubber"]
NOSE_INSET = 0.022
ROCKER_HEIGHT = 0.14


def ring(px, inset=0.0):
    w = T.half_width(px) - inset
    g = min(T.top_half(px), w - 0.03) - inset * 0.5
    zs = T.sill_z(px) + inset * 0.7
    zt = T.top_z(px) - inset * 0.7 - 0.014
    zb = T.belt_z(px)
    height = zt - zs
    zr = zs + min(ROCKER_HEIGHT, 0.32 * height)
    stripe = min(0.032, 0.08 * height)
    zb = min(max(zb, zr + stripe + 0.036), zt - 0.03)
    crown = 0.016
    e5 = min(0.05, 0.4 * (zr - zs))  # keep the lower chamfer monotonic on short nose rings
    half = [
        (0.0, zs),
        (w * 0.62, zs),
        (w - 0.058, zs),
        (w - 0.024, zs + min(0.006, 0.3 * e5)),
        (w - 0.011, zs + min(0.024, 0.55 * e5)),
        (w - 0.008, zs + e5),
        (w - 0.008, zr),
        (w, zr + stripe),
        (w, zb - 0.03),
        (w - 0.010, zb),
        (g + 0.014, zt - 0.014),
        (g, zt),
        (g - 0.02, zt + crown * 0.4),
        (g * 0.5, zt + crown),
        (0.0, zt + crown * 1.1),
    ]
    return [(T.X(px), y, z) for y, z in half]


def cap_faces(verts, ring_start, n, flip):
    """Planar end cap as strips + two ngons so subdivision keeps the face flat."""
    ring_ids = list(range(ring_start, ring_start + n))
    centre = {}
    for i in range(5, 11):
        v = verts[ring_ids[i]]
        centre[i] = len(verts)
        verts.append((v[0], 0.0, v[2]))
    faces = []
    faces.append(ring_ids[0:6] + [centre[5]])
    for i in range(5, 10):
        faces.append((centre[i], ring_ids[i], ring_ids[i + 1], centre[i + 1]))
    faces.append((centre[10], ring_ids[10], ring_ids[11], ring_ids[12], ring_ids[13],
                  ring_ids[14]))
    # all faces above are wound with the cap normal toward +X; flip for the -X cap
    return [tuple(reversed(f)) for f in faces] if flip else faces


def build_shell(builder):
    rings = []
    for k, px in enumerate(T.STATIONS):
        inset = NOSE_INSET if k in (0, len(T.STATIONS) - 1) else 0.0
        rings.append(ring(px, inset))
    n = RING_N
    verts = [v for r in rings for v in r]
    faces, mats = [], []
    for k in range(len(rings) - 1):
        a, b = k * n, (k + 1) * n
        for i in range(n - 1):
            faces.append((a + i, a + i + 1, b + i + 1, b + i))
            mats.append(ROW_MATERIAL[i])
    last = (len(rings) - 1) * n
    for start, flip in ((0, True), (last, False)):
        cap = cap_faces(verts, start, n, flip)
        faces.extend(cap)
        mats.extend([0] * len(cap))
    obj = builder.mesh_object("Body_BoilerfangShell", verts, faces, MATERIAL_KEYS, mats, smooth=True)
    mesh = obj.data
    # End caps are planar; keep their normals independent of the smooth shell.
    side_face_count = (len(rings) - 1) * (n - 1)
    for poly in mesh.polygons:
        if poly.index >= side_face_count:
            poly.use_smooth = False
    crease = mesh.attributes.new("crease_edge", "FLOAT", "EDGE")
    last_station = len(rings) - 1
    step_rings = {T.STATIONS.index(T.STEP_PX[0]), T.STATIONS.index(T.STEP_PX[1])}
    for e in mesh.edges:
        a, b = e.vertices
        if a >= len(rings) * n or b >= len(rings) * n:
            continue  # cap centre-line helpers stay soft
        sa, ia = divmod(a, n)
        sb, ib = divmod(b, n)
        if sa == sb:  # transverse edge inside a ring
            if sa in (0, last_station):
                crease.data[e.index].value = 1.0
            elif sa in step_rings and min(ia, ib) >= 9:
                crease.data[e.index].value = 1.0  # sharp roof-step corners across the cab back
        elif ia == ib:  # longitudinal edge along ring vertex ia
            weight = {2: 0.8, 5: 0.45, 6: 0.8, 7: 0.85, 9: 0.9, 10: 0.2, 11: 0.9}.get(ia, 0.0)
            crease.data[e.index].value = weight
    mod = obj.modifiers.new("CageMirror", "MIRROR")
    mod.use_axis = (False, True, False)
    mod.use_clip = True
    mod.use_mirror_merge = True
    mod.merge_threshold = 0.0002
    sub = obj.modifiers.new("SupportedSurface", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    sub.quality = 3
    return obj
