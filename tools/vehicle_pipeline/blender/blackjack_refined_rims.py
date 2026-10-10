"""Symmetric open-spoke rims, authored on the runtime wheel's local X axle."""
RIM_COLLECTIONS = {}
TIRE_COLLECTIONS = {}


def merged_export(source, path):
    target = bpy.data.collections.new(source.name + '_EXPORT')
    bpy.context.scene.collection.children.link(target)
    bpy.ops.object.select_all(action='DESELECT')
    for original in source.objects:
        obj = original.copy()
        obj.data = original.data.copy()
        target.objects.link(obj)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    export_collection(target,path)
    for obj in target.objects:
        obj.hide_render = True
    return target


def radial_band(name, profile, collection, mat, segments=48):
    vertices = [(axial, radius*math.cos(2*math.pi*i/segments), radius*math.sin(2*math.pi*i/segments))
                for axial, radius in profile for i in range(segments)]
    faces = [(j*segments+i, j*segments+(i+1)%segments,
              ((j+1)%len(profile))*segments+(i+1)%segments,
              ((j+1)%len(profile))*segments+i)
             for j in range(len(profile)) for i in range(segments)]
    obj = mesh_object(name,vertices,faces,mat,collection)
    recalc(obj)
    smooth(obj)
    return obj


for style, spokes in (('aero', 8), ('rugged', 10)):
    collection = bpy.data.collections.new('MODULAR_RIM_' + style.upper())
    bpy.context.scene.collection.children.link(collection)
    RIM_COLLECTIONS[style] = collection
    profile = [(-.13,.80),(-.13,.94),(-.10,1.0),(.10,1.0),(.13,.94),(.13,.80)]
    vertices = [(axial, radius*math.cos(2*math.pi*i/64), radius*math.sin(2*math.pi*i/64))
                for axial, radius in profile for i in range(64)]
    faces = [(j*64+i, j*64+(i+1)%64, ((j+1)%len(profile))*64+(i+1)%64,
              ((j+1)%len(profile))*64+i) for j in range(len(profile)) for i in range(64)]
    rim = mesh_object('Rim_' + style + '_Barrel', vertices, faces, MAT['BrushedMetal'], collection)
    recalc(rim)
    smooth(rim)
    cylinder_between('Rim_' + style + '_Hub',(-.17,0,0),(.17,0,0),.25,MAT['Gunmetal'],32,collection)
    if style == 'rugged':
        plate = radial_band('Rim_Rugged_VentedPlate', [(-.09,.26),(-.09,.84),(.09,.84),(.09,.26)], collection, MAT['Gunmetal'])
        for i in range(8):
            angle = 2*math.pi*i/8
            y, z = .60*math.cos(angle), .60*math.sin(angle)
            cutter = cylinder_between('Cutter_RimVent',(-.3,y,z),(.3,y,z),.125,MAT['Gunmetal'],16,CUTTERS)
            mod = plate.modifiers.new('VentHole','BOOLEAN')
            mod.operation = 'DIFFERENCE'
            mod.solver = 'EXACT'
            mod.object = cutter
            apply_modifier(plate,mod)
            cutter.hide_render = True
        bevel(plate,.012,2)
        radial_band('Rim_Rugged_Beadlock', [(-.16,.84),(-.16,.98),(.16,.98),(.16,.84)],collection,MAT['BrushedMetal'])
        for i in range(16):
            angle = 2*math.pi*i/16
            y, z = .912*math.cos(angle), .912*math.sin(angle)
            for side in (-1,1):
                cylinder_between(f'Rim_Rugged_BeadBolt_{i}_{side}',(side*.16,y,z),(side*.197,y,z),.027,MAT['Gunmetal'],6,collection)
    for i in range(spokes if style == 'aero' else 0):
        angle = 2*math.pi*i/spokes
        vertices = [(axial, radius*math.cos(angle+offset), radius*math.sin(angle+offset))
                    for axial in (-.075,.075) for radius in (.22,.89) for offset in (-.080,.080)]
        faces = [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
        spoke = mesh_object(f'Rim_{style}_Spoke_{i}',vertices,faces,MAT['BrushedMetal'],collection)
        recalc(spoke)
        bevel(spoke,.016,2)
        for side in (-1,1):
            y, z = .34*math.cos(angle), .34*math.sin(angle)
            cylinder_between(f'Rim_{style}_Bolt_{i}_{side}',(side*.077,y,z),(side*.102,y,z),.034,MAT['Gunmetal'],8,collection)
    for obj in collection.objects:
        if obj.type == 'MESH':
            for modifier in list(obj.modifiers):
                apply_modifier(obj, modifier)
            smooth(obj)
            smart_uv(obj)
    RIM_COLLECTIONS[style] = merged_export(collection, MODEL_DIR / f'blackjack_refined_rim_{style}.glb')
    for obj in collection.objects:
        obj.hide_render = True

    tires = bpy.data.collections.new('MODULAR_TIRE_' + style.upper())
    bpy.context.scene.collection.children.link(tires)
    TIRE_COLLECTIONS[style] = tires
    half_width = .34 if style == 'rugged' else .29
    profile = [(-half_width,.64),(-half_width,.82),(-half_width*.96,.89),
               (-half_width*.80,.953),(-half_width*.62,.979),
               (half_width*.62,.979),(half_width*.80,.953),
               (half_width*.96,.89),(half_width,.82),(half_width,.64)]
    tire = radial_band('Tire_' + style + '_Carcass',profile,tires,MAT['Rubber'],64)
    for row in (-1,1):
        for i in range(40):
            angle = 2*math.pi*(i+.25*(row+1))/40
            tread = box(f'Tire_{style}_Tread_{row}_{i}',
                        (row*half_width*.32,.987*math.cos(angle),.987*math.sin(angle)),
                        (half_width*.58,.026,.110),MAT['Rubber'],collection=tires,bevel_width=0)
            tread.rotation_euler.x = angle
    for side in (-1,1):
        radial_band(f'Tire_{style}_SidewallRib_{side}',
                    [(side*half_width,.71),(side*(half_width+.005),.73),
                     (side*(half_width+.005),.75),(side*half_width,.77)],tires,MAT['Rubber'])
    for obj in tires.objects:
        for modifier in list(obj.modifiers):
            apply_modifier(obj,modifier)
        smooth(obj)
        smart_uv(obj)
    TIRE_COLLECTIONS[style] = merged_export(tires,MODEL_DIR / f'blackjack_refined_tire_{style}.glb')
    for obj in tires.objects:
        obj.hide_render = True
