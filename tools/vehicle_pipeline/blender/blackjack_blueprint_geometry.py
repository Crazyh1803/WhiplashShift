"""Supported, mirrored cage and modular detail authored from blueprint pixels."""
import bmesh
from mathutils.bvhtree import BVHTree


def recalc(obj):
    if obj.type != 'MESH':
        return
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def smooth(obj):
    if obj.type == 'MESH':
        for poly in obj.data.polygons:
            poly.use_smooth = len(poly.vertices) <= 4
        obj.data.set_sharp_from_angle(angle=math.radians(40))


def smart_uv(obj):
    if obj.type != 'MESH' or not obj.data.polygons:
        return
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if obj.name.startswith('Body_BlueprintShell'):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        for edge in bm.edges:
            a,b = (v.co for v in edge.verts)
            edge.seam = (len(edge.link_faces) != 2 or len({f.material_index for f in edge.link_faces}) > 1
                         or edge.calc_face_angle(0) > math.radians(50)
                         or (abs(a.z) < .0001 and abs(b.z) < .0001)
                         or any(abs(a.x-point(px,0).x) < .003 and abs(b.x-point(px,0).x) < .003
                                for px in (343,397,469,551,648,655)))
        bm.to_mesh(obj.data)
        bm.free()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    if obj.name.startswith('Body_BlueprintShell'):
        bpy.ops.uv.unwrap(method='ANGLE_BASED',margin=.014)
        bpy.ops.uv.pack_islands(rotate=True,margin=.014)
    else:
        bpy.ops.uv.smart_project(angle_limit=math.radians(65),island_margin=.012)
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.select_set(False)


def section(px):
    _,sill,belt,roof,width,greenhouse = profile(px)
    w,g = width*SCALE,greenhouse*SCALE
    bottom,shoulder,top = (point(px,y).y for y in (sill,belt,roof))
    hood = px > 652 or px < 332
    if hood:
        # Tight fender shoulder, shallow crowned hood and a tucked lower rocker.
        half = [(0,bottom),(.65*w,bottom),(w-.030,bottom),(w-.010,bottom+.009),
                (w-.002,bottom+.027),(w,(bottom+shoulder)*.5),
                (w,shoulder-.006),(w-.008,shoulder+.003),
                (g+.021,top-.002),(g+.008,top),
                (g,top+.001),(g-.018,top+.002),(.55*g,top+.003),(0,top+.003)]
    else:
        sport = px > 549
        half = [(0,bottom),(.65*w,bottom),(w-.024,bottom),(w-.010,bottom+.007),
                (w-.003,bottom+.018),(w,(bottom+shoulder)*.52),
                (w,shoulder-.006),(w-.004,shoulder),
                (w-.011,shoulder+.004),(g+.007,top-.006),
                (g,top-.002),(g-.007,top),(.58*g,top+.002),(0,top+.002)]
    def vertex(z,y):
        # A recessed central nose and swept fender tips create the blueprint's
        # compound front face without changing its side silhouette or width.
        t=max(0,min(1,(px-764)/24))
        recess=6*SCALE*t*t*(3-2*t)*(1-(abs(z)/w)**2)
        return (point(px,0).x-recess,y,z)
    return [vertex(z,y) for z,y in half]+[vertex(-z,y) for z,y in reversed(half[1:-1])]


def build_shell():
    stations = sorted({p[0] for p in STATIONS}|set(range(285,786,9)))
    rings = [section(px) for px in stations]
    n = len(rings[0])
    vertices = [v for ring in rings for v in ring]
    faces = [(r*n+i,r*n+(i+1)%n,(r+1)*n+(i+1)%n,(r+1)*n+i)
             for r in range(len(rings)-1) for i in range(n)]
    faces += [tuple(reversed(range(n)))]
    # A bowed face cannot be capped by one nonplanar ngon. An explicit fan is
    # closed and consistently oriented for exact wheel/recess Booleans.
    cap=len(vertices)
    vertices.append(tuple(sum((Vector(v) for v in rings[-1]),Vector())/n))
    end=(len(rings)-1)*n
    faces += [(end+i,end+(i+1)%n,cap) for i in range(n)]
    shell = mesh_object('Body_BlueprintShell',vertices,faces,MAT['ArmorProtected'])
    for semantic in ('Paint_Primary','Paint_Secondary','Paint_Accent'):
        shell.data.materials.append(MAT[semantic])
    for poly in shell.data.polygons:
        c = sum((Vector(vertices[i]) for i in poly.vertices),Vector())/len(poly.vertices)
        px = (c.x-X_OFFSET)/SCALE+527
        py = GROUND_PIXEL-(c.y-GROUND_Y)/SCALE
        if px > 550:
            poly.material_index = 3 if py > 209 else 1
            if 560 < px < 615 and poly.index % n in range(10,16):
                poly.material_index = 2
        elif 343 < px < 397 and py < 153:
            poly.material_index = 1
        elif 348 < px < 470 and py < 72:
            poly.material_index = 2
        elif 548 < px < 565 and py > 190:
            poly.material_index = 3
    recalc(shell)
    crease = shell.data.attributes.new('crease_edge','FLOAT','EDGE')
    for edge in shell.data.edges:
        a,b = (shell.data.vertices[i].co for i in edge.vertices)
        if (min(edge.vertices)>=end or
            (abs(a.x-b.x)<.00001 and a.x<point(282,0).x)):
            crease.data[edge.index].value = 1
        elif abs(a.x-b.x)>.00001 and max(a.x,b.x)<point(548,0).x:
            if edge.vertices[0]%n == edge.vertices[1]%n and edge.vertices[0]%n in (7,9,10,15,16,18):
                crease.data[edge.index].value = .45
    mirror = shell.modifiers.new('ManualCageMirror','MIRROR')
    mirror.use_axis = (False,False,True)
    mirror.use_bisect_axis = (False,False,True)
    mirror.use_clip = True
    sub = shell.modifiers.new('SupportedAutomotiveCurvature','SUBSURF')
    sub.levels = 1
    sub.render_levels = 2
    smooth(shell)
    return shell


shell = build_shell()
for px,py,radius,track in WHEELS:
    center = point(px,py)
    bpy.ops.mesh.primitive_cylinder_add(vertices=64,radius=(radius+2.7)*SCALE,depth=1.1,location=center)
    cutter = relink(bpy.context.object,CUTTERS)
    cutter.name = f'Cutter_BlueprintArch_{px}'
    cutter.hide_render = True
    cutter.display_type = 'WIRE'
    mod = shell.modifiers.new(f'GenuineArch_{px}','BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = cutter


def cut_box(name,px,py,z,size):
    cutter = box('Cutter_'+name,point(px,py,z),size,MAT['ArmorProtected'],collection=CUTTERS,bevel_width=.004)
    for mod in list(cutter.modifiers):
        apply_modifier(cutter,mod)
    cutter.hide_render = True
    cutter.display_type = 'WIRE'
    mod = shell.modifiers.new('Recess_'+name,'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = cutter


for side in (-1,1):
    cut_box('Coupe_Lamp_'+str(side),779,197,side*.223,(.105,.041,.126))
    cut_box('Coupe_Gun_'+str(side),779,194,side*.116,(.095,.065,.070))
cut_box('Coupe_AirDam',779,213,0,(.095,.030,.36))
cut_box('Truck_Grille',281,157,0,(.095,.115,.385))
weighted = shell.modifiers.new('ControlledPanelNormals','WEIGHTED_NORMAL')
weighted.keep_sharp = True

bpy.context.view_layer.update()
bvh = BVHTree.FromObject(shell,bpy.context.evaluated_depsgraph_get())


def side_point(px,py,side,offset=.0015):
    source = point(px,py,side*.8)
    hit,normal,_,_ = bvh.ray_cast(source,Vector((0,0,-side)))
    if hit is None:
        raise RuntimeError(f'Blueprint side detail misses cage: {px},{py},{side}')
    return hit+normal*offset


def top_point(px,z,offset=.0015):
    hit,normal,_,_ = bvh.ray_cast(Vector((point(px,0).x,1.5,z)),Vector((0,-1,0)))
    if hit is None:
        raise RuntimeError(f'Blueprint top detail misses cage: {px},{z}')
    return hit+normal*offset


def panel(name,outline,projection,mat):
    center = sum((Vector(p) for p in outline),Vector((0,0)))/len(outline)
    vertices = [projection(*center)]+[projection(*p) for p in outline]
    faces = [(0,i+1,(i+1)%len(outline)+1) for i in range(len(outline))]
    obj = mesh_object(name,vertices,faces,mat)
    recalc(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.subdivide_edges(bm,edges=list(bm.edges),cuts=4 if mat.name=='Glass' else 2,use_grid_fill=True)
    for vertex in bm.verts:
        if projection.__name__ == 'project_top':
            px = (vertex.co.x-X_OFFSET)/SCALE+527
            vertex.co = projection(px,vertex.co.z)
        else:
            px = (vertex.co.x-X_OFFSET)/SCALE+527
            py = GROUND_PIXEL-(vertex.co.y-GROUND_Y)/SCALE
            vertex.co = projection(px,py)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    smooth(obj)
    return obj


def side_seam(name,outline,side,radius=.0013,mat=None):
    vertices = []
    for a,b in zip(outline,outline[1:]+outline[:1]):
        for i in range(4):
            t = i/4
            vertices.append(side_point(a[0]*(1-t)+b[0]*t,a[1]*(1-t)+b[1]*t,side,.002))
    return tube(name,vertices,radius,mat or MAT['Rubber'],cyclic=True)


for side in (-1,1):
    def project_side(px,py):
        return side_point(px,py,side,.0035)
    window = [(350,96),(354,85),(389,85),(390,102),(359,113),(349,112)]
    panel(f'Glass_RuggedSide_{side}',window,project_side,MAT['Glass'])
    side_seam(f'Glass_RuggedGasket_{side}',window,side,.0022)
    coupe = [(558,144),(566,132),(592,133),(614,139),(638,153),(608,152),(562,147)]
    panel(f'Glass_CoupeSide_{side}',coupe,project_side,MAT['Glass'])
    side_seam(f'Glass_CoupeGasket_{side}',coupe,side,.0022)
    quarter = [(530,145),(539,135),(544,134),(542,146)]
    panel(f'Glass_CoupeQuarter_{side}',quarter,project_side,MAT['Glass'])
    side_seam(f'Glass_CoupeQuarterSeal_{side}',quarter,side,.0018)
    truck_door = [(345,150),(345,118),(349,84),(395,81),(398,148),(389,152)]
    side_seam(f'Door_Rugged_{side}',truck_door,side)
    equipment = [(403,80),(459,80),(461,148),(402,148)]
    side_seam(f'Armor_EquipmentPlate_{side}',equipment,side,.0015,MAT['Gunmetal'])
    transition = [(490,89),(528,115),(530,128),(490,140)]
    side_seam(f'Armor_TransitionInset_{side}',transition,side,.0017,MAT['Gunmetal'])
    door = [(555,150),(609,156),(647,163),(643,209),(580,209),(569,190)]
    side_seam(f'Door_Coupe_{side}',door,side)
    # The drawing's long shoulder crease and fastened lower door panel are
    # visually important; avoid a featureless slab below the greenhouse.
    tube(f'Body_CoupeShoulder_{side}',
         [side_point(px,py,side,.0018) for px,py in
          [(561,166),(584,168),(614,172),(644,176),(655,179)]],
         .00085,MAT['Gunmetal'])
    for px,py in [(582,205),(594,205),(608,205),(622,205),(637,205),
                  (645,186),(646,197),(567,179),(574,193)]:
        obj = rivet(f'Rivet_CoupePanel_{side}_{px}_{py}',side_point(px,py,side,.002))
        obj.scale = (.30,.30,.30)
    box(f'Handle_Truck_{side}',side_point(382,124,side,.004),(.035,.008,.010),MAT['Gunmetal'],bevel_width=.002)
    box(f'Handle_Coupe_{side}',side_point(569,161,side,.004),(.034,.008,.009),MAT['BrushedMetal'],bevel_width=.002)
    for px in (405,457):
        for py in (84,94,104,114,124,134,144):
            obj = rivet(f'Rivet_Armor_{side}_{px}_{py}',side_point(px,py,side,.003))
            obj.scale = (.42,.42,.42)
    for py in (89,144):
        box(f'Hinge_Truck_{side}_{py}',side_point(346,py,side,.004),(.010,.017,.010),MAT['Gunmetal'],bevel_width=.002)
    # Real folded wheel-bay overhang, with a thin seam instead of a trim ring.
    fender = [(322,187),(337,155),(462,155),(480,184),
              (477,188),(459,161),(340,161),(325,190)]
    verts = [point(px,py,side*(top_width(px)+.002)) for px,py in fender]
    fascia = mesh_object(f'Armor_FenderFold_{side}',verts,[tuple(range(len(verts)))],MAT['ArmorProtected'])
    recalc(fascia)
    solid = fascia.modifiers.new('FoldedFasciaThickness','SOLIDIFY')
    solid.thickness = .012
    bevel(fascia,.0015,2)
    for px,py,radius,track in WHEELS:
        r = (radius+3.1)*SCALE
        center = point(px,py)
        arc = [(center.x+r*math.cos(math.radians(15+i*150/20)),
                center.y+r*math.sin(math.radians(15+i*150/20)),side*z)
               for z in (.235,top_width(px)-.003) for i in range(21)]
        liner = mesh_object(f'InnerFender_{side}_{px}',arc,[(i,i+1,i+22,i+21) for i in range(20)],MAT['ArmorProtected'])
        recalc(liner)
        solid = liner.modifiers.new('WheelBayThickness','SOLIDIFY')
        solid.thickness = .003
    # Central exposed sill, tank and pipe are below the body, not a solid slab.
    box(f'Drivetrain_Tank_{side}',point(515,205,side*.208),(.18,.098,.111),MAT['BrushedMetal'],bevel_width=.013)
    for px in (502,525):
        box(f'Tank_Strap_{side}_{px}',point(px,205,side*.267),(.009,.101,.006),MAT['Gunmetal'],bevel_width=.001)
    points = [point(476,145,side*.31),point(479,162,side*.31),point(488,169,side*.30),
              point(539,170,side*.26),point(562,192,side*.30)]
    tube(f'Drivetrain_ExternalPipe_{side}',points,.009,MAT['BrushedMetal'])
    for j in range(5):
        box(f'Vent_Armor_{side}_{j}',side_point(433,90+j*2.4,side,.003),(.080,.003,.004),MAT['Grille'],bevel_width=.0008)
    box(f'Armor_AccessLatch_{side}',side_point(498,120,side,.004),(.009,.030,.008),MAT['Gunmetal'],bevel_width=.002)


def project_top(px,z):
    return top_point(px,z,.0035)


for side in (-1,1):
    glass = [(337,side*.010),(347,side*.010),(347,side*.235),(337,side*.244)]
    panel(f'Glass_TruckFront_{side}',glass,project_top,MAT['Glass'])
    tube(f'Glass_TruckFrontSeal_{side}',[top_point(px,z,.003) for px,z in glass],.002,MAT['Rubber'],cyclic=True)
    wiper = [top_point(338,side*.025,.004),top_point(341,side*.195,.004)]
    tube(f'Wiper_Truck_{side}',wiper,.0017,MAT['Gunmetal'])
glass = [(619,-.224),(646,-.265),(646,.265),(619,.224)]
panel('Glass_CoupeWindshield',glass,project_top,MAT['Glass'])
tube('Glass_CoupeWindshieldSeal',[top_point(px,z,.003) for px,z in glass],.0022,MAT['Rubber'],cyclic=True)
roof_hatch = [(354,-.200),(362,-.213),(452,-.213),(459,-.200),
              (459,.200),(452,.213),(362,.213),(354,.200)]
panel('Roof_ArmoredAccessHatch',roof_hatch,project_top,MAT['Paint_Secondary'])
tube('Roof_ArmoredHatchSeal',[top_point(px,z,.003) for px,z in roof_hatch],.002,MAT['Rubber'],cyclic=True)
transition_vent = [(498,-.099),(523,-.099),(523,.099),(498,.099)]
panel('Armor_TransitionServiceVent',transition_vent,project_top,MAT['Grille'])
tube('Armor_TransitionVentFrame',[top_point(px,z,.003) for px,z in transition_vent],
     .002,MAT['Gunmetal'],cyclic=True)
for px in range(500,523,3):
    tube(f'Armor_TransitionVentSlat_{px}',
         [top_point(px,z,.004) for z in (-.094,0,.094)],.0015,MAT['BrushedMetal'])
for z in (-.245,.245):
    tube(f'Roof_ArmoredSideRail_{z}',[top_point(px,z,.004) for px in (352,380,420,458)],.0027,MAT['BrushedMetal'])
for z in (-.221,.221):
    tube(f'Hood_CoupeSeam_{z}',[top_point(px,z,.002) for px in range(658,776,7)],.0012,MAT['Rubber'])
for z in (-.116,.116):
    # Low-profile retractable weapon covers drawn on the blueprint hood.
    cover = [(683,z-.025),(707,z-.028),(707,z+.028),(683,z+.025)]
    base=[top_point(px,width,.001) for px,width in cover]
    top=[v+Vector((0,.026 if i in (0,3) else .015,0)) for i,v in enumerate(base)]
    obj=mesh_object(f'Weapons_RetractableCover_{z}',base+top,
        [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],MAT['Gunmetal'])
    recalc(obj)
    bevel(obj,.003,2)
    for px in (686,699):
        for dz in (-.016,.016):
            obj = rivet(f'Weapons_CoverFastener_{z}_{px}_{dz}',top_point(px,z+dz,.003))
            obj.scale = (.28,.28,.28)
hood_outline = [(659,-.188),(757,-.188),(775,-.161),
                (775,.161),(757,.188),(659,.188)]
tube('Hood_CoupePanelPerimeter',[top_point(px,z,.002) for px,z in hood_outline],
     .0011,MAT['Rubber'],cyclic=True)
# Angular shoulder insets frame the windscreen without raising the shallow hood.
for side in (-1,1):
    outline = [(656,side*.244),(670,side*.251),(677,side*.278),(660,side*.276)]
    panel(f'Hood_ShoulderVent_{side}',outline,project_top,MAT['Grille'])
    for px in (660,664,668):
        tube(f'Hood_ShoulderVentSlat_{side}_{px}',
             [top_point(px,side*z,.0025) for z in (.252,.268)],.0008,MAT['BrushedMetal'])

for side in (-1,1):
    box(f'LampPocket_Coupe_{side}',point(777,197,side*.223),(.018,.037,.122),MAT['Grille'],bevel_width=.005)
    for offset in (-.028,.028):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,location=point(782,197,side*.223+offset))
        obj=relink(bpy.context.object,BODY)
        obj.name=f'Lights_CoupeOvalLens_{side}_{offset}'
        obj.scale=(.006,.014,.024)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        obj.data.materials.append(MAT['Lights'])
    box(f'WeaponFrame_Coupe_{side}',point(777,194,side*.116),(.017,.062,.067),MAT['Gunmetal'],bevel_width=.007)
    box(f'WeaponPocket_Coupe_{side}',point(779,194,side*.116),(.018,.054,.054),MAT['Grille'],bevel_width=.006)
    for py in (190,198):
        center=point(782,py,side*.116)
        verts=[center+Vector((x,r*math.cos(i*math.tau/16),r*math.sin(i*math.tau/16)))
               for x,r in [(-.009,.0055),(-.009,.010),(.004,.010),(.004,.0055)] for i in range(16)]
        faces=[(ring*16+i,ring*16+(i+1)%16,((ring+1)%4)*16+(i+1)%16,((ring+1)%4)*16+i)
               for ring in range(4) for i in range(16)]
        ring=mesh_object(f'Weapon_BoredMuzzle_{side}_{py}',verts,faces,MAT['BrushedMetal'])
        recalc(ring)
        cylinder_between(f'Weapon_DarkBore_{side}_{py}',center+Vector((-.008,0,0)),center+Vector((-.007,0,0)),.0054,MAT['Gunmetal'],16)
    # Recessed truck lamps with protected housing, not luminous blocks on paint.
    box(f'LampHousing_Rugged_{side}',point(281,157,side*.252),(.026,.118,.088),MAT['Gunmetal'],bevel_width=.007)
    for py in (151,167):
        box(f'Lights_Rugged_{side}_{py}',point(278,py,side*.252),(.012,.046,.070),MAT['Lights'],bevel_width=.006)
    root = side_point(345,112,side)
    cylinder_between(f'MirrorMount_Truck_{side}',root,point(342,105,side*.383),.004,MAT['Gunmetal'],12)
    box(f'MirrorHousing_Truck_{side}',point(342,105,side*.390),(.039,.075,.022),MAT['Gunmetal'],bevel_width=.006)
    box(f'MirrorLens_Truck_{side}',point(341,105,side*.403),(.034,.067,.003),MAT['Mirror'],bevel_width=.002)
    root = side_point(636,151,side)
    cylinder_between(f'MirrorMount_Coupe_{side}',root,point(638,148,side*.349),.004,MAT['Gunmetal'],12)
    box(f'MirrorHousing_Coupe_{side}',point(640,147,side*.359),(.053,.025,.024),MAT['BrushedMetal'],bevel_width=.006)
    box(f'MirrorLens_Coupe_{side}',point(638,147,side*.374),(.036,.018,.003),MAT['Mirror'],bevel_width=.002)
    # Mounted exhaust stacks; their tips follow the blueprint rather than growing
    # a second tall block above the coupe or transition.
    for px in (348,472):
        cylinder_between(f'Exhaust_Stack_{side}_{px}',point(px,127,side*.342),point(px,60,side*.342),.016,MAT['BrushedMetal'],16)
        tube(f'Exhaust_BentTip_{side}_{px}',
             [point(px,60,side*.342),point(px,57,side*.342),
              point(px+1,55,side*.344),point(px+2,54,side*.347),point(px+2,52,side*.347)],
             .016,MAT['BrushedMetal'])
        for py in (95,120):
            cylinder_between(f'Exhaust_Mount_{side}_{px}_{py}',point(px,py,side*.303),point(px,py,side*.358),.009,MAT['Gunmetal'],10)

box('Grille_TruckBacking',point(283,157),(.012,.108,.377),MAT['Grille'],bevel_width=.003)
for i in range(11):
    z = -.174+i*.0348
    box(f'Grille_TruckFin_{i}',point(279,157,z),(.013,.106,.006),MAT['BrushedMetal'],bevel_width=.001)
box('Grille_CoupeIntake',point(777,213),(.014,.028,.350),MAT['Grille'],bevel_width=.003)
# The pointed nose has a separate thin air dam returning rearward below it.
lip_profile = [(775,203,.275),(775,213,.300),(785,216,.300),
               (789,219,.304),(742,222,.330),(742,219,.328)]
lip_vertices = [point(px,py,side*w) for px,py,w in lip_profile for side in (-1,1)]
lip_faces = [(i*2,((i+1)%6)*2,((i+1)%6)*2+1,i*2+1) for i in range(6)]
lip_faces += [tuple(i*2 for i in reversed(range(6))),tuple(i*2+1 for i in range(6))]
lip = mesh_object('Armor_CoupeLayeredAirDam',lip_vertices,lip_faces,MAT['ArmorProtected'])
recalc(lip)
bevel(lip,.0025,2)
box('Armor_RuggedBumper',point(281,191),(.080,.065,.60),MAT['ArmorProtected'],bevel_width=.007)
skid_profile = [(288,190),(281,199),(263,211),(269,214),(292,204),(300,196)]
verts = [point(px,py,side*.252) for px,py in skid_profile for side in (-1,1)]
faces = [(i*2,((i+1)%6)*2,((i+1)%6)*2+1,i*2+1) for i in range(6)]
faces += [tuple(i*2 for i in reversed(range(6))),tuple(i*2+1 for i in range(6))]
skid = mesh_object('Armor_RuggedAngledSkid',verts,faces,MAT['ArmorProtected'])
recalc(skid)
bevel(skid,.0025,2)
for py in (139,165,183):
    tube(f'BrushGuard_{py}',[point(285,py,-.310),point(270,py,-.270),point(270,py,.270),point(285,py,.310)],.007,MAT['BrushedMetal'])
for z in (-.225,.225):
    cylinder_between(f'BrushGuardUpright_{z}',point(270,130,z),point(270,203,z),.009,MAT['Gunmetal'],12)
    cylinder_between(f'BrushGuardSeat_{z}',point(288,191,z),point(270,191,z),.011,MAT['Gunmetal'],12)
box('Roof_TruckProtectedVent',point(426,67),(.19,.014,.065),MAT['Grille'],bevel_width=.003)
for z in (-.222,-.074,.074,.222):
    box(f'Lights_RoofMarker_{z}',point(356,67,z),(.016,.014,.018),MAT['Lights'],bevel_width=.003)
for z in (-.232,.232):
    box(f'Chassis_Frame_{z}',point(431,185,z),(.67,.027,.032),MAT['Gunmetal'],bevel_width=.003)
    box(f'Chassis_CenterRail_{z}',point(515,200,z),(.35,.027,.025),MAT['Gunmetal'],bevel_width=.003)
model_transform = Matrix.Translation((0,.35,0)) @ Matrix.Rotation(math.pi/2,4,'Y') @ Matrix.Diagonal((2.345,2.345,2.345,1))
for end,(px,py,radius,track) in zip(('B','M','A'),WHEELS):
    wheel_z = (model_transform @ INVERSE_POSE @ point(px,py)).z
    upper_y = .10 if end=='A' else -.04
    for side in (-1,1):
        mount = POSE @ model_transform.inverted() @ Vector((side*.57,upper_y,wheel_z+.11))
        box(f'Chassis_VisibleClevis_{side}_{wheel_z}',mount,(.034,.020,.035),MAT['Gunmetal'],bevel_width=.002)

# Existing local native Material Maker graphs supply protected procedural PBR.
for semantic,color in {'Paint_Primary':(.46,.49,.52),'Paint_Secondary':(.18,.23,.22),
                       'Paint_Accent':(.56,.59,.62),'ArmorProtected':(.17,.22,.20)}.items():
    MAT[semantic].node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*color,1)
MAT['Glass'].node_tree.nodes['Principled BSDF'].inputs['Transmission Weight'].default_value = 0
MAT['Lights'].node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = .22
for semantic,filename in {'BrushedMetal':'blackjack_brushed_metal','Rubber':'blackjack_rubber',
                          'Grille':'blackjack_grille','ArmorProtected':'blackjack_armor_wear'}.items():
    image = bpy.data.images.load(str(MODEL_DIR/'refined_materials'/f'{filename}_orm.png'),check_existing=True)
    image.colorspace_settings.name = 'Non-Color'
    image.pack()
    nodes = MAT[semantic].node_tree.nodes
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = image
    split = nodes.new('ShaderNodeSeparateColor')
    links = MAT[semantic].node_tree.links
    links.new(texture.outputs['Color'],split.inputs['Color'])
    # Grain and wear are subtle micro-roughness, not broad polished streaks.
    rough = nodes.new('ShaderNodeMath')
    rough.operation = 'MULTIPLY_ADD'
    rough.inputs[1].default_value = .20 if semantic == 'ArmorProtected' else .35
    rough.inputs[2].default_value = .46 if semantic == 'ArmorProtected' else .36
    if semantic in {'Rubber','Grille'}:
        rough.inputs[1].default_value = .15
        rough.inputs[2].default_value = .72
    links.new(split.outputs['Green'],rough.inputs[0])
    links.new(rough.outputs[0],nodes['Principled BSDF'].inputs['Roughness'])
    links.new(split.outputs['Blue'],nodes['Principled BSDF'].inputs['Metallic'])

for obj in BODY.all_objects:
    recalc(obj)
    smooth(obj)
    if obj.type == 'CURVE':
        obj.data.use_fill_caps = True

# Manually connected vent topology avoids damaged Boolean/decimated disks.
exec(compile((SCRIPT_DIR/'blackjack_blueprint_wheels.py').read_text(),
             str(SCRIPT_DIR/'blackjack_blueprint_wheels.py'),'exec'),globals())
MODULE_COUNTS = {kind+'_'+style:triangle_count(collection)[1]
                 for kind,collections in [('rim',RIM_COLLECTIONS),('tire',TIRE_COLLECTIONS)]
                 for style,collection in collections.items()}
# Native hard-surface optional blower replaces the oversized legacy scan. Its
# origin is the mounting plane, so no guessed bounding-box compensation is used.
engine = bpy.data.collections.new('BLUEPRINT_SUPERCHARGER_EXPORT')
bpy.context.scene.collection.children.link(engine)
box('Blower_MountingPlate',(0,.025,0),(1,.05,.70),MAT['Gunmetal'],collection=engine,bevel_width=.014)
box('Blower_RibbedCase',(0,.19,0),(.85,.30,.58),MAT['BrushedMetal'],collection=engine,bevel_width=.035)
box('Blower_IntakePlenum',(.08,.38,0),(.66,.11,.70),MAT['Gunmetal'],collection=engine,bevel_width=.020)
for z in (-.23,0,.23):
    vertices = [(x,.395+.090*math.cos(i*math.tau/20),z+.090*math.sin(i*math.tau/20))
                for x in (.25,.49) for i in range(20)]
    faces = [(i,(i+1)%20,(i+1)%20+20,i+20) for i in range(20)]
    obj = mesh_object(f'Blower_IntakeTube_{z}',vertices,faces,MAT['BrushedMetal'],engine)
    solid = obj.modifiers.new('IntakeWall','SOLIDIFY')
    solid.thickness=.012
    cylinder_between(f'Blower_IntakeDark_{z}',(.26,.395,z),(.27,.395,z),.077,MAT['Grille'],20,engine)
for x in (-.34,-.22,-.10,.02,.14,.26,.34):
    for z in (-.30,.30):
        box(f'Blower_CaseFin_{x}_{z}',(x,.18,z),(.016,.24,.018),MAT['BrushedMetal'],collection=engine,bevel_width=.003)
for x in (-.43,.43):
    for z in (-.29,.29):
        cylinder_between(f'Blower_MountBolt_{x}_{z}',(x,.05,z),(x,.073,z),.022,MAT['Gunmetal'],6,engine)
for y,radius in ((.15,.095),(.29,.07)):
    cylinder_between(f'Blower_DrivePulley_{y}',(-.44,y,0),(-.50,y,0),radius,MAT['Gunmetal'],20,engine)
tube('Blower_DriveBelt',[(-.505,.07,-.07),(-.505,.36,-.05),(-.505,.36,.05),(-.505,.07,.07)],.012,MAT['Rubber'],engine,cyclic=True)
for obj in engine.objects:
    for mod in list(obj.modifiers):
        if mod.type=='BEVEL':
            mod.segments=1
        apply_modifier(obj,mod)
    recalc(obj)
    smooth(obj)
    smart_uv(obj)
export_collection(engine,MODEL_DIR/f'{PREFIX}_supercharger.glb')
MODULE_COUNTS['supercharger']=triangle_count(engine)[1]
engine.hide_render=True
for px,py,radius,track in WHEELS:
    style = 'aero' if px > 550 else 'rugged'
    for side in (-1,1):
        for kind,collection,factor in [('Tire',TIRE_COLLECTIONS[style],1),('Rim',RIM_COLLECTIONS[style],.78 if style == 'aero' else .69)]:
            for original in collection.objects:
                obj = original.copy()
                obj.data = original.data.copy()
                obj.name = f'Preview_{kind}_{px}_{side}'
                obj.hide_render = False
                PREVIEW.objects.link(obj)
                scale = radius*SCALE*factor
                obj.matrix_world = Matrix.Translation(point(px,py,side*track)) @ Matrix.Rotation(math.pi/2,4,'Y') @ Matrix.Diagonal((scale,scale,scale,1)) @ original.matrix_world
    cylinder_between(f'Preview_Axle_{px}',point(px,py,-track),point(px,py,track),.013,MAT['Gunmetal'],12,PREVIEW)

BLUEPRINT_IMAGE = bpy.data.images.load(str(ROOT/'tools/vehicle_pipeline/references/SpyHunter.jpg'),check_existing=True)
BLUEPRINT_IMAGE.pack()


def reference_plane(name,bounds,view):
    x0,y0,x1,y1 = bounds
    if view == 'side':
        vertices = [point(x0,y1,-.70),point(x1,y1,-.70),point(x1,y0,-.70),point(x0,y0,-.70)]
    elif view == 'top':
        vertices = [Vector((point(px,0).x,-.70,(py-414)*SCALE)) for px,py in [(x0,y1),(x1,y1),(x1,y0),(x0,y0)]]
    else:
        center = 133 if view == 'rugged_front' else 908
        behind = 1.5 if view == 'rugged_front' else -1.5
        sign = -1 if view == 'rugged_front' else 1
        vertices = [Vector((behind,point(527,py).y,sign*(px-center)*SCALE))
                    for px,py in [(x0,y1),(x1,y1),(x1,y0),(x0,y0)]]
    mat = bpy.data.materials.new(name+'_Image')
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    output = nodes.new('ShaderNodeOutputMaterial')
    emission = nodes.new('ShaderNodeEmission')
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = BLUEPRINT_IMAGE
    mat.node_tree.links.new(texture.outputs['Color'],emission.inputs['Color'])
    mat.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
    obj = mesh_object(name,vertices,[(0,1,2,3)],mat,COL['REFERENCES'])
    uv = obj.data.uv_layers.new(name='UndistortedBlueprint')
    iw,ih = BLUEPRINT_IMAGE.size
    for loop,coord in zip(uv.data,[(x0/iw,1-y1/ih),(x1/iw,1-y1/ih),(x1/iw,1-y0/ih),(x0/iw,1-y0/ih)]):
        loop.uv = coord
    obj['uniform_pixel_scale'] = SCALE
    obj['aspect_stretch'] = 1.0
    obj.hide_render = True
    return obj


SIDE_REFERENCE = reference_plane('Blueprint_UniformSide',(258,45,796,238),'side')
TOP_REFERENCE = reference_plane('Blueprint_UniformTop',(258,313,800,514),'top')
RUGGED_REFERENCE = reference_plane('Blueprint_UniformRuggedFront',(42,38,224,239),'rugged_front')
INTERCEPTOR_REFERENCE = reference_plane('Blueprint_UniformInterceptorFront',(822,116,996,239),'interceptor_front')


def camera_aim(camera,target,up=Vector((0,1,0))):
    forward = (Vector(target)-camera.location).normalized()
    right = forward.cross(up).normalized()
    camera.rotation_euler = Matrix((right,right.cross(forward),-forward)).transposed().to_euler()


def build_studio():
    objects = []
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.12,.15,.18,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value = .8
    scene.view_settings.view_transform = 'AgX'
    ground = box('Studio_Ground',(0,GROUND_Y-.012,0),(6,.02,6),MAT['ArmorProtected'],collection=PREVIEW,bevel_width=0)
    objects.append(ground)
    for name,location,energy,size in [('Key',(1.5,3.5,2.7),260,3.2),('Fill',(2.5,1.2,-2.5),175,2.6),('Rim',(-2.5,2.5,1.5),230,2.1)]:
        light = bpy.data.lights.new(name,'AREA')
        light.energy = energy
        light.shape = 'DISK'
        light.size = size
        obj = bpy.data.objects.new(name,light)
        PREVIEW.objects.link(obj)
        obj.location = location
        camera_aim(obj,(0,0,0))
        objects.append(obj)
    camera_data = bpy.data.cameras.new('Blueprint_QACamera')
    camera_data.type = 'ORTHO'
    camera = bpy.data.objects.new('Blueprint_QACamera',camera_data)
    PREVIEW.objects.link(camera)
    scene.camera = camera
    objects.append(camera)
    return set(objects)


def configure_camera(view,overlay=False):
    camera = bpy.context.scene.camera
    targets = {'side':((0,.02,3),(0,.02,0)), 'top':((0,3,0),(0,0,0)),
               'rugged_front':((-3,.02,0),(0,.02,0)), 'interceptor_front':((3,-.08,0),(0,-.08,0)),
               'three_quarter':((2.7,1.6,2.7),(0,-.04,0))}
    location,target = targets[view]
    camera.location = location
    camera_aim(camera,target,Vector((0,0,-1)) if view == 'top' else Vector((0,1,0)))
    camera.data.ortho_scale = 2.45 if view in ('side','top','three_quarter') else 1.35
    bpy.context.scene.render.resolution_x = 1600 if view in ('side','top','three_quarter') else 1024
    bpy.context.scene.render.resolution_y = 900 if view in ('side','top','three_quarter') else 1024


def render_blueprint(view,path):
    configure_camera(view)
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def render_overlay(view,path):
    # Native wire overlay, not a warped/repainted raster reference.
    configure_camera(view,True)
    refs = COL['REFERENCES']
    refs.hide_render = False
    reference = {'side':SIDE_REFERENCE,'top':TOP_REFERENCE,
                 'rugged_front':RUGGED_REFERENCE,'interceptor_front':INTERCEPTOR_REFERENCE}[view]
    reference.hide_render = False
    prior = {}
    wire = bpy.data.materials.new('QA_SilhouetteWire')
    wire.use_nodes = True
    wire.node_tree.nodes.clear()
    output = wire.node_tree.nodes.new('ShaderNodeOutputMaterial')
    emission = wire.node_tree.nodes.new('ShaderNodeEmission')
    emission.inputs['Color'].default_value = (1,.06,.025,1)
    wire.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
    for obj in list(BODY.all_objects)+list(PREVIEW.all_objects):
        if obj.type not in {'MESH','CURVE'}:
            continue
        prior[obj] = obj.hide_render
        obj.hide_render = True
    # Evaluated cage outline rather than its designed pixel coordinates.
    mesh = bpy.data.meshes.new_from_object(shell.evaluated_get(bpy.context.evaluated_depsgraph_get()),depsgraph=bpy.context.evaluated_depsgraph_get())
    mesh.transform(shell.matrix_world)
    if view in ('rugged_front','interceptor_front'):
        bm = bmesh.new()
        bm.from_mesh(mesh)
        threshold = point(474 if view == 'rugged_front' else 548,0).x
        remove = [v for v in bm.verts if
                  (v.co.x > threshold if view == 'rugged_front' else v.co.x < threshold)]
        bmesh.ops.delete(bm,geom=remove,context='VERTS')
        bm.to_mesh(mesh)
        bm.free()
    outline = bpy.data.objects.new('QA_EvaluatedCageWire',mesh)
    PREVIEW.objects.link(outline)
    mesh.materials.clear()
    mesh.materials.append(wire)
    mod = outline.modifiers.new('ThinWireOverlay','WIREFRAME')
    mod.thickness = .00045
    mod.use_replace = True
    bpy.context.scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(outline,do_unlink=True)
    for obj,visible in prior.items():
        obj.hide_render = visible
    reference.hide_render = True
    refs.hide_render = True
