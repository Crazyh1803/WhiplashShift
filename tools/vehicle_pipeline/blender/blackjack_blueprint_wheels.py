"""Manually connected vented wheel topology, X-axis axle; no Boolean vent mesh."""
RIM_COLLECTIONS = {}
TIRE_COLLECTIONS = {}


def band(name,profile,collection,mat,segments=48):
    vertices = [(x,r*math.cos(i*2*math.pi/segments),r*math.sin(i*2*math.pi/segments))
                for x,r in profile for i in range(segments)]
    faces = [(j*segments+i,j*segments+(i+1)%segments,((j+1)%len(profile))*segments+(i+1)%segments,
              ((j+1)%len(profile))*segments+i) for j in range(len(profile)) for i in range(segments)]
    obj = mesh_object(name,vertices,faces,mat,collection)
    recalc(obj)
    smooth(obj)
    return obj


def vented_plate(collection):
    vertices,faces = [],[]
    # Each annular sector has an octagonal opening and explicit connecting quads.
    for sector in range(8):
        base = sector*math.pi/4
        boundary = [(r*math.cos(a),r*math.sin(a)) for r,a in
                    [(.84,-math.pi/8),(.84,0),(.84,math.pi/8),(.545,math.pi/8),
                     (.25,math.pi/8),(.25,0),(.25,-math.pi/8),(.545,-math.pi/8)]]
        hole = []
        for y,z in boundary:
            angle = math.atan2(z,y-.60)
            hole.append((.60+.125*math.cos(angle),.125*math.sin(angle)))
        offset = len(vertices)
        for x in (-.065,.065):
            for loop in (boundary,hole):
                vertices += [(x,y*math.cos(base)-z*math.sin(base),y*math.sin(base)+z*math.cos(base)) for y,z in loop]
        for i in range(8):
            j = (i+1)%8
            faces += [(offset+i,offset+j,offset+8+j,offset+8+i),
                      (offset+16+i,offset+24+i,offset+24+j,offset+16+j),
                      (offset+8+i,offset+8+j,offset+24+j,offset+24+i)]
            if i in (0,1,4,5):
                faces.append((offset+i,offset+16+i,offset+16+j,offset+j))
    obj = mesh_object('Rim_Rugged_ManualVentPlate',vertices,faces,MAT['Gunmetal'],collection)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
    # Sector seams share vertices, but never contain hidden internal wall faces.
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges), 'Manual rim plate is not closed'
    bm.to_mesh(obj.data)
    bm.free()
    bevel(obj,.004,1)
    return obj


def joined_export(collection,path,ratio):
    target = bpy.data.collections.new(collection.name+'_EXPORT')
    bpy.context.scene.collection.children.link(target)
    bpy.ops.object.select_all(action='DESELECT')
    for original in collection.objects:
        obj = original.copy()
        obj.data = original.data.copy()
        target.objects.link(obj)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    obj = bpy.context.object
    if ratio < 1:
        mod = obj.modifiers.new('GameplayWheelBudget','DECIMATE')
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        apply_modifier(obj,mod)
    recalc(obj)
    smooth(obj)
    smart_uv(obj)
    export_collection(target,path)
    obj.hide_render = True
    for original in collection.objects:
        original.hide_render = True
    return target


for style in ('aero','rugged'):
    collection = bpy.data.collections.new('BLUEPRINT_RIM_'+style.upper())
    bpy.context.scene.collection.children.link(collection)
    band('Rim_'+style+'_Barrel',[(-.12,.80),(-.12,.95),(-.09,1),(.09,1),(.12,.95),(.12,.80)],collection,MAT['BrushedMetal'])
    cylinder_between('Rim_'+style+'_Hub',(-.14,0,0),(.14,0,0),.22,MAT['Gunmetal'],16,collection)
    if style == 'rugged':
        vented_plate(collection)
        band('Rim_Rugged_Beadlock',[(-.14,.86),(-.14,.98),(.14,.98),(.14,.86)],collection,MAT['BrushedMetal'],32)
        count = 12
        bolt_radius = .916
    else:
        count = 5
        bolt_radius = .32
        for i in range(5):
            angle = i*math.tau/5
            vertices = [(x,r*math.cos(angle+a),r*math.sin(angle+a)) for x in (-.06,.06) for r in (.20,.90) for a in (-.105,.105)]
            obj = mesh_object(f'Rim_Aero_Spoke_{i}',vertices,[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)],MAT['BrushedMetal'],collection)
            recalc(obj)
            bevel(obj,.008,1)
    for i in range(count):
        angle = i*2*math.pi/count
        for side in (-1,1):
            y,z = bolt_radius*math.cos(angle),bolt_radius*math.sin(angle)
            cylinder_between(f'Rim_{style}_Lug_{i}_{side}',(side*.142,y,z),(side*.165,y,z),.026,MAT['Gunmetal'],6,collection)
    for obj in collection.objects:
        for mod in list(obj.modifiers):
            if mod.type == 'BEVEL' and ('Lug' in obj.name or 'Hub' in obj.name):
                obj.modifiers.remove(mod)
                continue
            apply_modifier(obj,mod)
        recalc(obj)
        smooth(obj)
        smart_uv(obj)
    RIM_COLLECTIONS[style] = joined_export(collection,MODEL_DIR/f'{PREFIX}_rim_{style}.glb',.55 if style == 'rugged' else .75)

    collection = bpy.data.collections.new('BLUEPRINT_TIRE_'+style.upper())
    bpy.context.scene.collection.children.link(collection)
    inner = .675 if style == 'rugged' else .765
    profile = [(-.20,inner),(-.20,.86),(-.185,.94),(-.135,.98),
               (.135,.98),(.185,.94),(.20,.86),(.20,inner)]
    band('Tire_'+style+'_Carcass',profile,collection,MAT['Rubber'])
    for row in (-1,1):
        for i in range(32):
            a = 2*math.pi*(i+.25*(row+1))/32
            obj = box(f'Tire_{style}_Tread_{row}_{i}',(row*.073,.987*math.cos(a),.987*math.sin(a)),
                      (.13,.026,.13),MAT['Rubber'],collection=collection,bevel_width=0)
            obj.rotation_euler.x = a
    for obj in collection.objects:
        recalc(obj)
        smooth(obj)
        smart_uv(obj)
    TIRE_COLLECTIONS[style] = joined_export(collection,MODEL_DIR/f'{PREFIX}_tire_{style}.glb',1)
