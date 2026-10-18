"""Blueprint-first candidate. Existing production and refined outputs stay intact."""
import ast
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
SCRIPT_DIR = ROOT / 'tools/vehicle_pipeline/blender'
MODEL_DIR = ROOT / 'godot/assets/vehicles/models/blackjack'
PREFIX = 'blackjack_blueprint'
ns = globals()
previous = SCRIPT_DIR / 'build_blackjack_production_v2.py'
tree = ast.parse(previous.read_text())
for node in tree.body:
    if isinstance(node, (ast.FunctionDef, ast.Import, ast.ImportFrom)) or (
        isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id in
        {'COL', 'BODY', 'PREVIEW', 'CUTTERS', 'MAT'} for t in node.targets)
    ):
        module = ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[]))
        exec(compile(module, str(previous), 'exec'), ns)

exec(compile((SCRIPT_DIR / 'blackjack_blueprint_trace.py').read_text(),
             str(SCRIPT_DIR / 'blackjack_blueprint_trace.py'), 'exec'), ns)
exec(compile((SCRIPT_DIR / 'blackjack_blueprint_geometry.py').read_text(),
             str(SCRIPT_DIR / 'blackjack_blueprint_geometry.py'), 'exec'), ns)

# Local cage coordinates remain level and pixel-traced; the object transform
# compensates the measured fixed chassis rake. Export baking makes it standalone.
for collection in (BODY, CUTTERS, PREVIEW):
    for obj in collection.all_objects:
        obj.matrix_world = INVERSE_POSE @ obj.matrix_world
bpy.context.view_layer.update()
for obj in BODY.all_objects:
    smart_uv(obj)
print('BLUEPRINT_STAGE source UV complete',flush=True)
bake_collection(BODY, COL['GAMEPLAY_EXPORT'])
print('BLUEPRINT_STAGE gameplay bake complete',flush=True)

# Budget the complete assembly, not only the shell. Keep high-detail source intact.
game = COL['GAMEPLAY_EXPORT']
raw_triangles = triangle_count(game)[1]
body_target = 17000
def is_glass_panel(obj):
    return len(obj.data.materials)==1 and obj.data.materials[0].name=='Glass'

def is_windshield_trim(obj):
    # Four-corner cyclic seals and slender wipers must not collapse into broad
    # triangles over the glass. Their complete native profiles are inexpensive.
    return obj.name.startswith(('Glass_TruckFrontSeal','Glass_CoupeWindshieldSeal','Wiper_Truck'))

def preserve_paint_borders(obj,modifier,window_collection=None):
    # Zero-weight vertices are excluded from native collapse (Blender BMesh).
    # Keeping a continuous mesh avoids cracks between separately reduced colors.
    import bmesh
    bm=bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.index_update()
    borders={v.index for edge in bm.edges if len({f.material_index for f in edge.link_faces})>1 for v in edge.verts}
    bm.free()
    if window_collection is not None:
        from mathutils.bvhtree import BVHTree
        inverse=obj.matrix_world.inverted()
        level=POSE @ obj.matrix_world
        shell_surface=BVHTree.FromPolygons([level @ v.co for v in obj.data.vertices],
                                          [p.vertices for p in obj.data.polygons])
        support=set()
        for window in window_collection.objects:
            if not is_glass_panel(window):
                continue
            # Pin complete supporting faces, not just nearby vertices: a large
            # triangle can span a window while its corners lie outside its edge.
            window_level=POSE @ window.matrix_world
            side_window=any(n in window.name for n in ('RuggedSide','CoupeSide','CoupeQuarter'))
            window.data.calc_loop_triangles()
            samples=[window_level @ v.co for v in window.data.vertices]
            for tri in window.data.loop_triangles:
                corners=[window_level @ window.data.vertices[i].co for i in tri.vertices]
                samples.append(sum(corners,Vector())/3)
                samples.extend((corners[i]+corners[(i+1)%3])*.5 for i in range(3))
            for sample in samples:
                if side_window:
                    side=-1 if sample.z<0 else 1
                    origin,direction=Vector((sample.x,sample.y,side*.8)),Vector((0,0,-side))
                else:
                    origin,direction=Vector((sample.x,1.5,sample.z)),Vector((0,-1,0))
                _,_,index,_=shell_surface.ray_cast(origin,direction)
                if index is not None:
                    support.update(obj.data.polygons[index].vertices)
            transform=inverse @ window.matrix_world
            surface=BVHTree.FromPolygons([transform @ v.co for v in window.data.vertices],
                                        [p.vertices for p in window.data.polygons])
            # Retain the skin supporting the windows: collapse must not pull a
            # small quarter-light beyond the reduced greenhouse silhouette.
            borders.update(v.index for v in obj.data.vertices
                           if surface.find_nearest(v.co,.014)[0] is not None)
        bm=bmesh.new()
        bm.from_mesh(obj.data)
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        for index in list(support):
            for face in bm.verts[index].link_faces:
                support.update(v.index for v in face.verts)
        bm.free()
        borders.update(support)
    group=obj.vertex_groups.get('CollapseAllowed') or obj.vertex_groups.new(name='CollapseAllowed')
    group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    if borders:
        group.add(sorted(borders),0,'REPLACE')
    modifier.vertex_group=group.name
    modifier.vertex_group_factor=1

def seat_glass(collection,clearance=.0035):
    from mathutils.bvhtree import BVHTree
    body = next(obj for obj in collection.objects if obj.name.startswith('Body_BlueprintShell'))
    surface = BVHTree.FromPolygons([POSE @ body.matrix_world @ v.co for v in body.data.vertices],
                                  [p.vertices for p in body.data.polygons])
    for obj in collection.objects:
        if not is_glass_panel(obj):
            continue
        transform = POSE @ obj.matrix_world
        inverse = transform.inverted()
        side_window = any(name in obj.name for name in ('RuggedSide','CoupeSide','CoupeQuarter'))
        for vertex in obj.data.vertices:
            level = transform @ vertex.co
            if side_window:
                side = -1 if level.z<0 else 1
                origin,direction = Vector((level.x,level.y,side*.8)),Vector((0,0,-side))
            else:
                origin,direction = Vector((level.x,1.5,level.z)),Vector((0,-1,0))
            hit,normal,_,_ = surface.ray_cast(origin,direction)
            assert hit is not None, 'Protected window misses optimized shell: '+obj.name
            vertex.co = inverse @ (hit+normal*clearance)
        recalc(obj)
        smooth(obj)
for obj in game.objects:
    if obj.name.startswith('Body_BlueprintShell'):
        obj.data.calc_loop_triangles()
        count = len(obj.data.loop_triangles)
        if count>4500:
            mod = obj.modifiers.new('ReservedShellBudget','DECIMATE')
            mod.ratio = 4500/count
            mod.use_collapse_triangulate = True
            preserve_paint_borders(obj,mod)
            apply_modifier(obj,mod)
        # Exact recess Booleans can leave subpixel needles that collapse into a
        # pinched edge during decimation. Weld only the non-manifold neighborhood
        # (under half a blueprint pixel), never an arbitrary large hole.
        import bmesh
        bm=bmesh.new()
        bm.from_mesh(obj.data)
        for distance in (.001,.002):
            bad={v for edge in bm.edges if not edge.is_manifold for v in edge.verts}
            if not bad:
                break
            bmesh.ops.remove_doubles(bm,verts=list(bad),dist=distance)
            bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00005)
            bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        assert all(edge.is_manifold for edge in bm.edges), 'Shell retopology requires manual repair'
        bm.to_mesh(obj.data)
        bm.free()
for budget_pass in range(3):
    eligible = []
    fixed_triangles = 0
    for obj in game.objects:
        obj.data.calc_loop_triangles()
        count = len(obj.data.loop_triangles)
        if count > 24 and not obj.name.startswith(('Body_BlueprintShell','Rivet_','Detail_')) and not is_glass_panel(obj) and not is_windshield_trim(obj):
            eligible.append((obj,count))
        else:
            fixed_triangles += count
    total = fixed_triangles+sum(count for _,count in eligible)
    print('BLUEPRINT_BUDGET',budget_pass,total,flush=True)
    if total <= body_target+150:
        break
    ratio = max(.10,(body_target-fixed_triangles)/sum(count for _,count in eligible))
    for obj,count in eligible:
        mod = obj.modifiers.new('GameplayBudget','DECIMATE')
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        apply_modifier(obj,mod)
        recalc(obj)
        smooth(obj)
seat_glass(game)
for obj in game.objects:
    smart_uv(obj,finalize=True)
assert 15000<=triangle_count(game)[1]<=body_target+150, 'Gameplay body exceeded its allocation'
print('BLUEPRINT_STAGE gameplay budget and UV complete',flush=True)
bake_collection(game, COL['LOD1_EXPORT'])
for obj in list(COL['LOD1_EXPORT'].objects):
    # Subpixel fasteners are retained in gameplay, not paid for at distant LOD.
    if obj.name.startswith(('Rivet_','FastenerContact_')):
        data=obj.data
        bpy.data.objects.remove(obj,do_unlink=True)
        if data.users==0:
            bpy.data.meshes.remove(data)
        continue
    # A crooked guard is visible even at distance; preserve the entire assembly.
    if obj.name.startswith('Detail_BrushGuard') or is_windshield_trim(obj):
        continue
    if len(obj.data.polygons)>48 and not is_glass_panel(obj):
        mod = obj.modifiers.new('LOD_SurfaceReduction','DECIMATE')
        mod.ratio = .45
        mod.use_collapse_triangulate = True
        if obj.name.startswith('Body_BlueprintShell'):
            preserve_paint_borders(obj,mod,COL['LOD1_EXPORT'])
        apply_modifier(obj,mod)
    if len(obj.data.polygons)>20 and not is_glass_panel(obj):
        mod = obj.modifiers.new('LOD_DetailReduction','DECIMATE')
        mod.ratio = .72 if obj.name.startswith('Body_BlueprintShell') else .55
        mod.use_collapse_triangulate = True
        if obj.name.startswith('Body_BlueprintShell'):
            preserve_paint_borders(obj,mod,COL['LOD1_EXPORT'])
        apply_modifier(obj,mod)
seat_glass(COL['LOD1_EXPORT'])
smart_uv(next(obj for obj in COL['LOD1_EXPORT'].objects if obj.name.startswith('Body_BlueprintShell')),finalize=True)
# Partition only export copies. Godot's decal cull masks operate per instance,
# not per material; the editable cage and closed validation shell stay whole.
native_export_collection = export_collection
def export_semantic_collection(collection,path):
    import bmesh
    temporary = bpy.data.collections.new('SEMANTIC_EXPORT_TEMP')
    bpy.context.scene.collection.children.link(temporary)
    for original in collection.objects:
        for index,material in enumerate(original.data.materials):
            if not any(p.material_index == index for p in original.data.polygons):
                continue
            obj = original.copy()
            obj.data = original.data.copy()
            # Base Vehicle identifies embedded wheels by name substrings.
            # "Primary" contains "rim", so never put semantics in node names.
            obj.name = original.name+'__Channel'+str(index)
            temporary.objects.link(obj)
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.material_index != index],context='FACES')
            for face in bm.faces:
                face.material_index = 0
            bm.to_mesh(obj.data)
            bm.free()
            obj.data.materials.clear()
            obj.data.materials.append(material)
    native_export_collection(temporary,path)
    for obj in list(temporary.objects):
        data = obj.data
        bpy.data.objects.remove(obj,do_unlink=True)
        bpy.data.meshes.remove(data)
    bpy.data.collections.remove(temporary)
export_collection = export_semantic_collection

# Quantitative surface silhouette checks are run on evaluated gameplay geometry,
# not on the input station array. Measurements stay independent of render lighting.
from mathutils.bvhtree import BVHTree
shell_export = next(obj for obj in game.objects if obj.name.startswith('Body_BlueprintShell'))
bpy.context.view_layer.update()
projected = shell_export.copy()
projected.data = shell_export.data.copy()
PREVIEW.objects.link(projected)
projected.matrix_world = POSE @ projected.matrix_world
evaluated = projected.evaluated_get(bpy.context.evaluated_depsgraph_get())
mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=bpy.context.evaluated_depsgraph_get())
mesh.transform(projected.matrix_world)
bvh = BVHTree.FromPolygons([v.co for v in mesh.vertices], [p.vertices for p in mesh.polygons])
intake_depths = []
for side in (-1,1):
    origin=Vector((point(665,0).x,1.5,side*.260))
    before=hood_surface.ray_cast(origin,Vector((0,-1,0)))[0]
    after=bvh.ray_cast(origin,Vector((0,-1,0)))[0]
    assert before is not None and after is not None, 'Missing hood intake floor'
    depth=before.y-after.y
    assert .003<depth<.018, ('Hood intake recess lost during optimization',side,depth)
    intake_depths.append({'side':side,'gameplay_recess_depth_metres':depth*2.345})
errors = []
width_errors = []
sill_errors = []
for px, sill, belt, roof, width, greenhouse in STATIONS[2:-2]:
    if in_junction(px):
        continue  # authored junction curves are gated separately below
    target = point(px,roof)
    hit = bvh.ray_cast(Vector((target.x,1.5,0)),Vector((0,-1,0)))[0]
    errors.append({'pixel_x':px,'roof_error_pixels':None if hit is None else abs(hit.y-target.y)/SCALE})
    extents = []
    for j in range(1,24):
        y = point(px,sill+(roof-sill)*j/24).y
        hit = bvh.ray_cast(Vector((target.x,y,.8)),Vector((0,0,-1)))[0]
        if hit is not None:
            extents.append(hit.z)
    width_errors.append({'pixel_x':px,'half_width_error_pixels':
                         None if not extents else abs(max(extents)-width*SCALE)/SCALE})
    if all(abs(px-wheel[0])>wheel[2]+4 for wheel in WHEELS):
        hit = bvh.ray_cast(Vector((target.x,-1,0)),Vector((0,1,0)))[0]
        sill_errors.append({'pixel_x':px,'sill_error_pixels':
                            None if hit is None else abs(hit.y-point(px,sill).y)/SCALE})
# Bounded junction region: continuity gates replace trace fidelity inside it.
junction = junction_measurements(bvh)
bpy.data.objects.remove(projected,do_unlink=True)
bpy.data.meshes.remove(mesh)
assert all(e['roof_error_pixels'] is not None and e['roof_error_pixels']<4
           for e in errors), 'Gameplay decimation damaged the traced roof silhouette'
assert all(e['half_width_error_pixels'] is not None and e['half_width_error_pixels']<2
           for e in width_errors), 'Gameplay decimation damaged the top-view width'
# At the very tip, the recessed center intake removes the shell's bottom; the
# separately seated layered air dam supplies that silhouette. Gate solid sills.
assert all(e['sill_error_pixels'] is not None and e['sill_error_pixels']<3
           for e in sill_errors if e['pixel_x']<770), 'Gameplay decimation damaged the body sill'
export_collection(game, MODEL_DIR / f'{PREFIX}.glb')
export_collection(COL['LOD1_EXPORT'], MODEL_DIR / f'{PREFIX}_lod1.glb')

report = {
    'asset_status':'candidate; blueprint visual QA required',
    'source':str((SCRIPT_DIR/f'{PREFIX}.blend').relative_to(ROOT)),
    'blueprint':'tools/vehicle_pipeline/references/SpyHunter.jpg',
    'uniform_side_scale':SCALE, 'reference_stretch':1.0,
    'body_triangles':triangle_count(game)[1],
    'lod1_body_triangles':triangle_count(COL['LOD1_EXPORT'])[1],
    'module_triangles':MODULE_COUNTS,
    'assembled_minimum_triangles':triangle_count(game)[1]+sum(
        count*(MODULE_COUNTS['rim_'+style]+MODULE_COUNTS['tire_'+style])
        for style,count in [('aero',2),('rugged',4)]),
    'semantic_materials':sorted(MAT), 'physics_changed':False,
    'hood_intake_recesses':intake_depths,
    'brush_guard_paths':{str(py):[list(p) for p in points] for py,points in GUARD_PATHS.items()},
    'visual_radius_metres':{'A':wheel_radius('A')*2.345,'B':wheel_radius('B')*2.345},
    'visual_track_metres':{'A':WHEELS[-1][3]*2.345,'B':WHEELS[0][3]*2.345},
    'roof_surface_measurements':errors,
    'width_surface_measurements':width_errors,
    'sill_surface_measurements':sill_errors,
    'junction_region':junction,
}
# Socket origins use the same authored surface and inverse pose as the shell.
# Native modular supercharger has its mounting base at local Y=0.
car_transform = Matrix.Translation((0,.35,0)) @ Matrix.Rotation(math.pi/2,4,'Y') @ Matrix.Diagonal((2.345,2.345,2.345,1))
report['arch_centers'] = {
    end+('_L' if side<0 else '_R'):list(car_transform @ INVERSE_POSE @ point(px,py,side*track))
    for end,(px,py,radius,track) in zip(('B','M','A'),WHEELS)
    for side in (-1,1)
}
report['preview_pitch'] = -.0905
report['preview_height'] = -(Matrix.Rotation(-.0905,4,'X') @ car_transform @ INVERSE_POSE @ point(527,235)).y
hood_mount = car_transform @ INVERSE_POSE @ top_point(696,0,.002)
report['part_socket_positions'] = {
    # Authored sockets are pinned to the pre-junction-rework receipt values: the
    # rig contract forbids moving them, and re-sampling a re-tessellated shell
    # would jitter them. 'left'/'right' were sampled on the old pinched waist,
    # which is now wider (see junction_region).
    'hood_engine':[2.3821411332392017e-07,0.11212596297264099,-1.5892200469970703],
    'roof':[3.0513285764754983e-06,0.7695949673652649,1.125878930091858],
    'front_a':[1.8895362074999866e-07,-0.205430269241333,-2.5027663707733154],
    'front_b':[-1.8183996530751756e-07,-0.46833789348602295,2.408543109893799],
    'left':[-0.6017946600914001,0.05659814924001694,0.12388912588357925],
    'right':[0.6017776727676392,0.05659298598766327,0.12388865649700165],
}
(MODEL_DIR/f'{PREFIX}_qa.json').write_text(json.dumps(report,indent=2)+'\n')
# ResourceLoader dependency ensures dimensions are included in exported games;
# FileAccess-only JSON would not be a reliably exported runtime dependency.
sockets = ',\n'.join(json.dumps(name)+': Vector3('+', '.join(format(v,'.9g') for v in xyz)+')'
                     for name,xyz in report['part_socket_positions'].items())
metadata = '[gd_resource type="Resource" load_steps=2 format=3]\n\n'
metadata += '[ext_resource type="Script" path="res://scripts/blackjack_blueprint_dimensions.gd" id="1"]\n\n'
metadata += '[resource]\nscript = ExtResource("1")\n'
metadata += 'display_radius = '+json.dumps(report['visual_radius_metres'])+'\n'
metadata += 'display_track = '+json.dumps(report['visual_track_metres'])+'\n'
metadata += 'arch_centers = {\n'+',\n'.join(json.dumps(name)+': Vector3('+', '.join(format(v,'.9g') for v in xyz)+')' for name,xyz in report['arch_centers'].items())+'\n}\n'
metadata += 'preview_pitch = '+str(report['preview_pitch'])+'\n'
metadata += 'preview_height = '+str(report['preview_height'])+'\n'
metadata += 'part_socket_positions = {\n'+sockets+'\n}\n'
(MODEL_DIR/f'{PREFIX}_dimensions.tres').write_text(metadata)

# Export/source duplicates never contribute to the neutral QA render.
for collection in (game,COL['LOD1_EXPORT'],CUTTERS,COL['REFERENCES']):
    collection.hide_render = True
for obj in list(BODY.all_objects)+list(CUTTERS.all_objects)+list(PREVIEW.all_objects):
    obj.matrix_world = POSE @ obj.matrix_world
studio_objects = build_studio()
if '--no-renders' not in sys.argv:
    for view in ('side','top','rugged_front','interceptor_front','three_quarter'):
        render_blueprint(view, MODEL_DIR/f'{PREFIX}_{view}.png')
    for view in ('side','top','rugged_front','interceptor_front'):
        render_overlay(view, MODEL_DIR/f'{PREFIX}_{view}_overlay.png')
# Save canonical geometry with references in the same frame, so artists can
# actually trace/edit against the planes rather than a mismatched settled pose.
for obj in list(BODY.all_objects)+list(CUTTERS.all_objects)+list(PREVIEW.all_objects):
    if obj not in studio_objects:
        obj.matrix_world = INVERSE_POSE @ obj.matrix_world
for obj in COL['REFERENCES'].objects:
    obj.matrix_world = INVERSE_POSE @ obj.matrix_world
configure_camera('three_quarter')
bpy.context.scene.camera.matrix_world = INVERSE_POSE @ bpy.context.scene.camera.matrix_world
for obj in studio_objects:
    if obj.name=='Studio_Ground':
        obj.matrix_world = INVERSE_POSE @ obj.matrix_world
bpy.ops.wm.save_as_mainfile(filepath=str(SCRIPT_DIR/f'{PREFIX}.blend'))
print('BLUEPRINT_EXPORT', json.dumps({k:v for k,v in report.items() if not k.endswith('measurements')}))
