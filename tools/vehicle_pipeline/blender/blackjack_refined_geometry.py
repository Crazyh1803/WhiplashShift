"""Blueprint control stations and surface construction for Blackjack X-17.

Executed in the production export rig's namespace. Length X, up Y, width Z.
Blueprint side silhouette is constrained to the existing three axle stations.
"""
import bmesh
from mathutils.bvhtree import BVHTree

# Roof corners, cowl breaks and full-width end faces are explicitly supported.
# x, lower sill, width, belt/hood height, roof height, greenhouse width
TRACE = [
    (-1.035, -.215, .330, .075, .130, .308),
    (-1.030, -.215, .330, .075, .130, .308),
    (-.970, -.180, .347, .102, .148, .308),
    (-.938, -.080, .352, .112, .185, .310),
    (-.865, -.165, .358, .116, .357, .307),
    (-.830, -.165, .359, .116, .436, .307),
    (-.815, -.165, .359, .116, .451, .309),
    (-.790, -.165, .359, .116, .454, .309),
    (-.600, -.165, .359, .116, .454, .310),
    (-.430, -.165, .355, .116, .452, .310),
    (-.195, -.165, .350, .116, .450, .308),
    (-.180, -.165, .349, .116, .440, .304),
    (-.130, -.165, .345, .102, .393, .286),
    (-.040, -.180, .340, .074, .326, .254),
    (.060, -.232, .330, .045, .258, .226),
    (.079, -.232, .330, .045, .237, .226),
    (.085, -.232, .330, .045, .152, .216),
    (.105, -.232, .332, .045, .149, .217),
    (.150, -.232, .342, .048, .195, .230),
    (.198, -.232, .350, .050, .222, .248),
    (.245, -.232, .356, .055, .228, .253),
    (.375, -.232, .364, .064, .223, .252),
    (.410, -.232, .368, .072, .217, .249),
    (.440, -.232, .372, .082, .192, .247),
    (.550, -.232, .379, .095, .082, .261),
    (.580, -.232, .382, .097, .073, .269),
    (.665, -.232, .383, .098, .068, .270),
    (.790, -.240, .377, .086, .062, .269),
    (.910, -.250, .360, .056, .043, .265),
    (.980, -.255, .342, .031, .025, .257),
    (1.027, -.258, .330, .025, .018, .254),
    (1.035, -.258, .330, .021, .014, .254),
]


def profile_at(x):
    for a, b in zip(TRACE, TRACE[1:]):
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return tuple(aa + (bb - aa) * t for aa, bb in zip(a[1:], b[1:]))
    return TRACE[0][1:] if x < TRACE[0][0] else TRACE[-1][1:]


def section_half(x):
    bottom, width, belt, roof, roof_width = profile_at(x)
    is_hood = x >= .550 or x < -.938
    shoulder = belt + .006
    upper = max(shoulder + .004, roof - .014)
    if x >= .550:
        # Raised fenders flow down into the wedge nose; no folded roof/belt rings.
        return [
            (0.0, bottom), (.60*width, bottom),
            (width-.055, bottom), (width-.025, bottom+.010),
            (width-.008, bottom+.045), (width-.002, (bottom+belt)*.50),
            (width, belt-.016), (width-.012, belt),
            (width-.028, belt+.009), (roof_width+.030, roof+.010),
            (roof_width, roof+.001), (roof_width-.025, roof+.006),
            (.58*roof_width, roof+.010), (0.0, roof+.014),
        ]
    # Near-vertical armor, but a tucked sports sill and convex door surface.
    sport = max(0.0, min(1.0, (x-.08)/.09))
    return [
        (0.0, bottom), (.60 * width, bottom),
        (width - .025-.030*sport, bottom), (width - .010-.020*sport, bottom + .008),
        (width-.012*sport, bottom + .026), (width + .004*sport, (bottom + belt) * .52),
        (width, belt - .012), (width - .005, belt),
        (width - .018, shoulder),
        (roof_width + .012, upper), (roof_width, roof - .003),
        (roof_width - .012, roof + .002),
        (.58 * roof_width, roof + (.004 if is_hood else .006)),
        (0.0, roof + (.006 if is_hood else .008)),
    ]


def section_points(x):
    half = section_half(x)
    return ([(x, y, z) for z, y in half]
            + [(x, y, -z) for z, y in reversed(half[1:-1])])


def recalc(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def smooth(obj):
    if obj.type == 'MESH':
        for polygon in obj.data.polygons:
            polygon.use_smooth = len(polygon.vertices) <= 4
        obj.data.set_sharp_from_angle(angle=math.radians(42))


def smart_uv(obj):
    if obj.type != 'MESH' or not obj.data.polygons:
        return
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if obj.name.startswith('Body_TracedShell'):
        # Material boundaries separate roof, doors, rocker and protected armor.
        # Split the centerline and cowl so the hood is not joined to a side island.
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        for edge in bm.edges:
            a, b = [v.co for v in edge.verts]
            edge.seam = (len(edge.link_faces) != 2
                         or len({f.material_index for f in edge.link_faces}) > 1
                         or (abs(a.z) < .0001 and abs(b.z) < .0001)
                         or any(abs(a.x-x) < .003 and abs(b.x-x) < .003
                                for x in (-.815, -.443, -.195, .15, .41, .55)))
        bm.to_mesh(obj.data)
        bm.free()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    if obj.name.startswith('Body_TracedShell'):
        bpy.ops.uv.unwrap(method='ANGLE_BASED', margin=.018)
        bpy.ops.uv.pack_islands(rotate=True, margin=.018)
    else:
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.018)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)


def build_shell():
    stations = sorted({p[0] for p in TRACE} | {round(-1.02 + i * .038, 6) for i in range(54)})
    rings = [section_points(x) for x in stations if -1.035 <= x <= 1.035]
    n = len(rings[0])
    vertices = [v for ring in rings for v in ring]
    faces = [(r*n+i, r*n+(i+1)%n, (r+1)*n+(i+1)%n, (r+1)*n+i)
             for r in range(len(rings)-1) for i in range(n)]
    faces += [tuple(reversed(range(n))), tuple((len(rings)-1)*n+i for i in range(n))]
    obj = mesh_object('Body_TracedShell', vertices, faces, MAT['ArmorProtected'])
    for semantic in ('Paint_Primary', 'Paint_Secondary', 'Paint_Accent'):
        obj.data.materials.append(MAT[semantic])
    for polygon in obj.data.polygons:
        c = polygon.center
        points = [Vector(vertices[i]) for i in polygon.vertices]
        c = sum(points, Vector()) / len(points)
        x, y, z = c
        if x > .12 and y > -.28:
            polygon.material_index = 1
        elif -.815 < x < -.443 and .030 < y < .425:
            polygon.material_index = 1
        elif -.81 < x < -.19 and y > .435:
            polygon.material_index = 2
        elif -.03 < x < .10 and .03 < y < .08:
            polygon.material_index = 3
    recalc(obj)
    crease = obj.data.attributes.new('crease_edge', 'FLOAT', 'EDGE')
    for edge in obj.data.edges:
        a, b = [obj.data.vertices[i].co for i in edge.vertices]
        if abs(a.x-b.x) < .00001 and (a.x < -1.034 or a.x > 1.034):
            crease.data[edge.index].value = 1.0
    smooth(obj)
    mirror = obj.modifiers.new('BlueprintMirror', 'MIRROR')
    mirror.use_axis = (False, False, True)
    mirror.use_bisect_axis = (False, False, True)
    mirror.use_clip = True
    mirror.merge_threshold = .0001
    sub = obj.modifiers.new('SupportedCurvature', 'SUBSURF')
    sub.levels = 1
    sub.render_levels = 1
    return obj


shell = build_shell()


def cut_box(name, center, size):
    obj = box('Cutter_' + name, center, size, MAT['ArmorProtected'], collection=CUTTERS, bevel_width=.009)
    for modifier in list(obj.modifiers):
        apply_modifier(obj, modifier)
    obj.hide_render = True
    obj.display_type = 'WIRE'
    modifier = shell.modifiers.new('Recess_' + name, 'BOOLEAN')
    modifier.operation = 'DIFFERENCE'
    modifier.solver = 'EXACT'
    modifier.object = obj


# Seated to the measured, unchanged Godot suspension at static ride height.
AXLES = [(-.682303, -.298598, .221748), (-.281450, -.26235, .221748),
         (.682303, -.251530, .144989)]
for x, y, tire_radius in AXLES:
    radius = tire_radius + .017
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=radius, depth=1.10,
                                       location=(x, y, 0.0))
    cutter = relink(bpy.context.object, CUTTERS)
    cutter.name = f'Cutter_Arch_{x}'
    cutter.hide_render = True
    cutter.display_type = 'WIRE'
    mod = shell.modifiers.new(f'OpenArch_{x}', 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = cutter
for side in (-1, 1):
    cut_box(f'InterceptorLamp_{side}', (1.03, -.112, side * .218), (.13, .061, .16))
    cut_box(f'InterceptorWeapon_{side}', (1.04, -.038, side * .098), (.12, .038, .064))
cut_box('InterceptorAirDam', (1.035, -.209, 0), (.14, .045, .365))
cut_box('RuggedGrille', (-1.030, -.020, 0), (.14, .18, .365))
weighted = shell.modifiers.new('PanelWeightedNormals', 'WEIGHTED_NORMAL')
weighted.keep_sharp = True
weighted.weight = 35

# Ray projection seats every decal, seam and window against the evaluated shell.
bpy.context.view_layer.update()
shell_bvh = BVHTree.FromObject(shell, bpy.context.evaluated_depsgraph_get())


def side_point(x, y, side, offset=.002):
    p, normal, _, _ = shell_bvh.ray_cast(Vector((x, y, side*.8)), Vector((0, 0, -side)))
    if p is None:
        raise RuntimeError(f'panel outside traced body: {x}, {y}, {side}')
    return p + normal * offset


def top_point(x, z, offset=.002):
    p, normal, _, _ = shell_bvh.ray_cast(Vector((x, 1.0, z)), Vector((0, -1, 0)))
    if p is None:
        raise RuntimeError(f'top panel outside traced body: {x}, {z}')
    return p + normal * offset


def patch_polygon(name, outline, project, mat):
    # Subdivided triangles inside a traced polygon stay flush on compound surfaces.
    center = sum((Vector(p) for p in outline), Vector((0, 0))) / len(outline)
    vertices = [project(*center)] + [project(*p) for p in outline]
    faces = [(0, i+1, (i+1)%len(outline)+1) for i in range(len(outline))]
    obj = mesh_object(name, vertices, faces, mat)
    recalc(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=3, use_grid_fill=True)
    for vertex in bm.verts:
        if project.__name__ == 'project_top':
            vertex.co = project(vertex.co.x, vertex.co.z)
        else:
            vertex.co = project(vertex.co.x, vertex.co.y)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    smooth(obj)
    return obj


def seam_side(name, outline, side, width=.0017, mat=None):
    points = []
    for a, b in zip(outline, outline[1:] + outline[:1]):
        for i in range(5):
            t = i / 5
            points.append(side_point(a[0]*(1-t)+b[0]*t, a[1]*(1-t)+b[1]*t, side, .0025))
    return tube(name, points, width, mat or MAT['Rubber'], cyclic=True)


# Glass follows the roof slopes and clipped window outlines rather than flat stickers.
for side in (-1, 1):
    def project_side(x, y):
        return side_point(x, y, side)
    rugged_window = [(-.814,.188),(-.790,.379),(-.493,.379),(-.493,.245),(-.692,.184)]
    patch_polygon(f'Glass_ArmoredSide_{side}', rugged_window, project_side, MAT['Glass'])
    seam_side(f'Rubber_ArmoredWindowGasket_{side}', rugged_window, side, .003)
    sport_window = [(.201,.123),(.206,.192),(.371,.189),(.475,.112),(.474,.095),(.212,.105)]
    patch_polygon(f'Glass_InterceptorSide_{side}', sport_window, project_side, MAT['Glass'])
    seam_side(f'Rubber_InterceptorWindowGasket_{side}', sport_window, side, .003)
    door = [(-.815,.042),(-.815,.152),(-.810,.390),(-.459,.395),(-.443,.055),(-.470,.033)]
    seam_side(f'Door_ArmoredSeam_{side}', door, side)
    sport_door = [(.17,-.195),(.153,.092),(.479,.095),(.478,.040),(.443,-.183),(.420,-.202)]
    seam_side(f'Door_InterceptorSeam_{side}', sport_door, side)
    for xx in (-.434, -.208):
        for yy in (.05, .12, .19, .26, .33, .40):
            rivet(f'PlateRivet_{side}_{xx}_{yy}', side_point(xx, yy, side, .004))
    handle_point = side_point(-.513,.151,side,.010)
    box(f'Door_Handle_Rugged_{side}', handle_point, (.040,.012,.012), MAT['Gunmetal'], bevel_width=.004)
    box(f'Door_Handle_Interceptor_{side}', side_point(.292,-.025,side,.007), (.055,.011,.012), MAT['BrushedMetal'], bevel_width=.004)

def project_top(x, z):
    return top_point(x, z)

for side in (-1, 1):
    z0, z1 = (.014 * side, .266 * side)
    windshield = [(-.919,z0),(-.836,z0),(-.836,z1),(-.919,z1)]
    patch_polygon(f'Glass_ArmoredWindshield_{side}', windshield, project_top, MAT['Glass'])
    tube(f'Rubber_RuggedFrontGasket_{side}', [top_point(x,z,.004) for x,z in windshield], .003, MAT['Rubber'], cyclic=True)
sport_windshield = [(.429,-.220),(.535,-.249),(.535,.249),(.429,.220)]
patch_polygon('Glass_InterceptorWindshield', sport_windshield, project_top, MAT['Glass'])
tube('Rubber_InterceptorWindshieldSeal', [top_point(x,z,.004) for x,z in sport_windshield], .0035, MAT['Rubber'], cyclic=True)
for z in (-.228, .228):
    tube(f'Hood_PanelSeam_{z}', [top_point(.575+i*.040,z,.0015) for i in range(11)], .0013, MAT['Rubber'])

# Raised fender brows grow from the shoulder; low armored skirts expose the bogie.
for side in (-1, 1):
    tube(f'Armor_BogieFender_{side}', [(-.913,-.136,side*.361),(-.839,.025,side*.364),
         (-.141,.025,side*.358),(-.087,-.127,side*.345)], .014, MAT['ArmorProtected'])
    points = []
    for i in range(25):
        angle = math.radians(10+i*160/24)
        x = .682303+.165*math.cos(angle)
        y = -.251530+.165*math.sin(angle)
        p = side_point(x,y,side,.001)
        points.append(p)
    tube(f'Body_InterceptorArchEdge_{side}', points,.004,MAT['Paint_Primary'])
    box(f'Armor_CenterEquipment_{side}', (-.006,-.181,side*.266), (.205,.10,.13),MAT['ArmorProtected'],bevel_width=.009)
    for j in range(7):
        p = side_point(-.345,.265+j*.014,side,.004)
        box(f'Grille_ArmorVent_{side}_{j}',p,(.108,.007,.005),MAT['Grille'],bevel_width=.001)

# Recess backings and lamps lie inside the machined front apertures.
for side in (-1, 1):
    box(f'Grille_InterceptorLampPocket_{side}',(1.006,-.112,side*.218),(.016,.057,.153),MAT['Grille'],bevel_width=.009)
    for shift in (-.035,.035):
        box(f'Lights_Interceptor_{side}_{shift}',(1.016,-.112,side*.218+shift),(.013,.032,.056),MAT['Lights'],bevel_width=.009)
    box(f'Grille_WeaponPocket_{side}',(1.014,-.038,side*.098),(.016,.034,.058),MAT['Grille'],bevel_width=.005)
    for shift in (-.013,.013):
        cylinder_between(f'Gun_Barrel_{side}_{shift}',(.99,-.038,side*.098+shift),(1.075,-.038,side*.098+shift),.006,MAT['Gunmetal'],16)
    for yy in (.02,-.067):
        box(f'Lights_Rugged_{side}_{yy}',(-1.042,yy,side*.265),(.018,.055,.088),MAT['Lights'],bevel_width=.010)
    root = side_point(-.820,.270,side)
    cylinder_between(f'Mirror_RuggedMount_{side}',root,(-.825,.27,side*.420),.006,MAT['Gunmetal'])
    box(f'Mirror_RuggedHousing_{side}',(-.825,.28,side*.430),(.062,.102,.025),MAT['Gunmetal'],bevel_width=.009)
    box(f'Mirror_RuggedLens_{side}',(-.822,.28,side*.445),(.050,.085,.004),MAT['Mirror'],bevel_width=.003)
    root = side_point(.474,.106,side)
    cylinder_between(f'Mirror_SportMount_{side}',root,(.469,.111,side*.407),.006,MAT['Gunmetal'])
    box(f'Mirror_SportHousing_{side}',(.475,.12,side*.417),(.070,.033,.029),MAT['BrushedMetal'],bevel_width=.012)
    box(f'Mirror_SportLens_{side}',(.462,.12,side*.433),(.045,.023,.004),MAT['Mirror'],bevel_width=.003)
box('Grille_RuggedBacking',(-1.006,-.02,0),(.017,.17,.35),MAT['Grille'],bevel_width=.005)
for j in range(9):
    box(f'Grille_RuggedSlat_{j}',(-1.022,-.02,-.148+j*.037),(.013,.160,.009),MAT['BrushedMetal'],bevel_width=.001)
box('Grille_InterceptorBacking',(1.002,-.209,0),(.013,.040,.35),MAT['Grille'],bevel_width=.006)
for yy in (-.197,-.220):
    box(f'Grille_InterceptorSlat_{yy}',(1.019,yy,0),(.010,.005,.345),MAT['Gunmetal'],bevel_width=.001)
box('Armor_RuggedBumper',(-1.059,-.169,0),(.070,.072,.72),MAT['ArmorProtected'],bevel_width=.014)
box('Armor_InterceptorAirDam',(1.032,-.261,0),(.076,.017,.705),MAT['ArmorProtected'],bevel_width=.008)
for yy in (-.145,-.065,.093):
    tube(f'BrushGuardBar_{yy}',[(-1.05,yy,-.367),(-1.105,yy,-.29),(-1.105,yy,.29),(-1.05,yy,.367)],.011,MAT['BrushedMetal'])
for zz in (-.247,.247):
    cylinder_between(f'BrushGuardUpright_{zz}',(-1.105,-.23,zz),(-1.105,.14,zz),.013,MAT['Gunmetal'])
    cylinder_between(f'BrushGuardMount_{zz}',(-1.04,-.16,zz),(-1.11,-.16,zz),.017,MAT['Gunmetal'])
box('Grille_RuggedRoofVent',(-.505,.465,0),(.25,.022,.21),MAT['Grille'],bevel_width=.004)
for zz in (-.20,-.07,.07,.20):
    box(f'Lights_RoofMarker_{zz}',(-.783,.466,zz),(.025,.022,.029),MAT['Lights'],bevel_width=.005)
cylinder_between('Exhaust_Stack',(-.178,.107,.311),(-.178,.528,.311),.014,MAT['BrushedMetal'],20)
for yy in (.16,.35):
    cylinder_between(f'Exhaust_Seat_{yy}',(-.178,yy,.295),(-.178,yy,.321),.020,MAT['Gunmetal'])
cylinder_between('Exhaust_Tip',(-.178,.528,.311),(-.128,.555,.311),.014,MAT['BrushedMetal'],20)

# Neutral material values make profile/corner QA readable before garage paint.
for semantic, color in {'Paint_Primary':(.42,.45,.47),'Paint_Secondary':(.23,.26,.27),
                        'Paint_Accent':(.58,.60,.61),'ArmorProtected':(.12,.15,.14)}.items():
    MAT[semantic].node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*color,1)
MAT['Glass'].node_tree.nodes['Principled BSDF'].inputs['Transmission Weight'].default_value = 0.0
MAT['Lights'].node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = .25
for semantic, filename in {'BrushedMetal':'blackjack_brushed_metal',
                           'Rubber':'blackjack_rubber', 'Grille':'blackjack_grille',
                           'ArmorProtected':'blackjack_armor_wear'}.items():
    path = MODEL_DIR / 'refined_materials' / (filename + '_orm.png')
    if not path.exists():
        raise RuntimeError(f'Export the Material Maker graph first: {path}')
    nodes = MAT[semantic].node_tree.nodes
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = bpy.data.images.load(str(path), check_existing=True)
    texture.image.colorspace_settings.name = 'Non-Color'
    texture.image.pack()
    split = nodes.new('ShaderNodeSeparateColor')
    links = MAT[semantic].node_tree.links
    links.new(texture.outputs['Color'], split.inputs['Color'])
    links.new(split.outputs['Green'], nodes['Principled BSDF'].inputs['Roughness'])
    links.new(split.outputs['Blue'], nodes['Principled BSDF'].inputs['Metallic'])

for obj in list(BODY.objects):
    if obj.type == 'MESH':
        recalc(obj)
    elif obj.type == 'CURVE':
        obj.data.use_fill_caps = True

# Real chassis contact points close the gap between the bogie and armored cabin.
for side in (-1,1):
    box(f'Chassis_RuggedRail_{side}',(-.49,-.178,side*.23),(.84,.06,.055),MAT['Gunmetal'],bevel_width=.006)
    for xx in (-.805,-.477,-.128):
        box(f'Chassis_BogieClevis_{side}_{xx}',(xx,-.202,side*.245),(.05,.11,.045),MAT['Gunmetal'],bevel_width=.005)
    for xx, yy, radius in AXLES:
        inside, outside = (.23,.366) if xx < 0 else (.24,.379)
        arc_radius = radius+.024
        vertices = [(xx+arc_radius*math.cos(math.radians(12+i*156/24)),
                     yy+arc_radius*math.sin(math.radians(12+i*156/24)),side*z)
                    for z in (inside,outside) for i in range(25)]
        faces = [(i,i+1,i+26,i+25) for i in range(24)]
        liner = mesh_object(f'InnerFender_Liner_{side}_{xx}',vertices,faces,MAT['ArmorProtected'])
        recalc(liner)
        solid = liner.modifiers.new('LinerThickness','SOLIDIFY')
        solid.thickness = .004
        smooth(liner)
    for yy in (.042,.345):
        box(f'Door_Hinge_Rugged_{side}_{yy}',side_point(-.812,yy,side,.008),(.018,.033,.016),MAT['Gunmetal'],bevel_width=.004)
    equipment_panel = [(-.115,.11),(-.113,.316),(.035,.234),(.045,.103)]
    seam_side(f'Armor_TransitionAccess_{side}',equipment_panel,side,.002,MAT['Gunmetal'])


def reference_plane(name, path, pixel_bounds, world_bounds, orientation):
    # Cropped UVs preserve the original reference image and allow orthographic QA.
    image = bpy.data.images.load(str(path), check_existing=True)
    image.pack()
    px0, py0, px1, py1 = pixel_bounds
    u0, u1 = px0/image.size[0], px1/image.size[0]
    v0, v1 = 1-py1/image.size[1], 1-py0/image.size[1]
    a0, b0, a1, b1 = world_bounds
    points = ([(a0,b0,-.70),(a1,b0,-.70),(a1,b1,-.70),(a0,b1,-.70)]
              if orientation == 'SIDE' else
              [(orientation,b0,a0),(orientation,b0,a1),(orientation,b1,a1),(orientation,b1,a0)])
    mat = bpy.data.materials.new(name + '_Image')
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    output = nodes.new('ShaderNodeOutputMaterial')
    emission = nodes.new('ShaderNodeEmission')
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = image
    mat.node_tree.links.new(texture.outputs['Color'], emission.inputs['Color'])
    mat.node_tree.links.new(emission.outputs[0], output.inputs['Surface'])
    obj = mesh_object(name,points,[(0,1,2,3)],mat,COL['REFERENCES'])
    layer = obj.data.uv_layers.new(name='ReferenceCrop')
    for loop, uv in zip(layer.data, [(u0,v0),(u1,v0),(u1,v1),(u0,v1)]):
        loop.uv = uv
    obj.hide_render = True
    obj['calibration'] = 'Side axle span 1.364606; front body width .72; dimensional blockout remains authoritative.'
    return obj


blueprint = Path('/home/crazyh/Downloads/WhiplashShiftModels/SpyHunter.jpg')
if not blueprint.exists():
    raise FileNotFoundError(f'Required calibrated blueprint is missing: {blueprint}')
# Front and side sheets use different pixel scales, calibrated independently.
reference_plane('Blueprint_Side_Orthographic',blueprint,(262,60,788,237),
                (-1.082,-.495,1.088,.508),'SIDE')
reference_plane('Blueprint_Rugged_Orthographic',blueprint,(45,45,222,238),
                (-.41,-.48,.41,.53),-1.35)
reference_plane('Blueprint_Interceptor_Orthographic',blueprint,(819,119,997,239),
                (-.41,-.40,.41,.24),1.35)

add_reference('Reference_ApprovedSide',REF_SIDE,(0,.04,-.65),(0,0,0),2.20)
add_reference('Reference_RuggedFront',REF_RUGGED,(-1.35,.05,0),(0,math.pi/2,0),.78)
add_reference('Reference_InterceptorFront',REF_INTERCEPTOR,(1.35,.03,0),(0,-math.pi/2,0),.78)
rim_builder = SCRIPT_DIR / 'blackjack_refined_rims.py'
exec(compile(rim_builder.read_text(), str(rim_builder), 'exec'), globals())
for xx, yy, radius in AXLES:
    for ss in (-1, 1):
        style = 'aero' if xx > 0 else 'rugged'
        originals = [(obj,radius) for obj in TIRE_COLLECTIONS[style].objects]
        originals += [(obj,radius*.64) for obj in RIM_COLLECTIONS[style].objects]
        for original, rim_scale in originals:
            obj = original.copy()
            obj.data = original.data.copy()
            obj.hide_render = False
            PREVIEW.objects.link(obj)
            obj.location = Vector((xx, yy, ss*.384)) + Matrix.Rotation(math.pi/2, 3, 'Y') @ (original.location * rim_scale)
            obj.rotation_euler = (Matrix.Rotation(math.pi/2, 4, 'Y') @ original.rotation_euler.to_matrix().to_4x4()).to_euler()
            obj.scale = original.scale * rim_scale
    cylinder_between(f'Preview_Axle_{xx}',(xx,yy,-.39),(xx,yy,.39),.022,MAT['Gunmetal'],20,PREVIEW)
for obj in PREVIEW.all_objects:
    if obj.type == 'MESH':
        smooth(obj)

# Source geometry and export duplicates must not overlap in QA frames.
for obj in CUTTERS.all_objects:
    obj.hide_render = True
COL['REFERENCES'].hide_render = True
