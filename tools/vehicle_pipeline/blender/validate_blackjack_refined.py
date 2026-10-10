"""Independent Blender topology checks and paint-ID bake for the candidate."""
import json
from pathlib import Path
import bpy
import bmesh

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / 'godot/assets/vehicles/models/blackjack'
collection = bpy.data.collections['GAMEPLAY_EXPORT']
shell = next(obj for obj in collection.objects if obj.name.startswith('Body_TracedShell'))
report = {'asset_status': 'candidate_only', 'objects': {}, 'physics_changed': False}
for obj in collection.objects:
    if obj.type != 'MESH':
        continue
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    stats = {'vertices': len(bm.verts), 'faces': len(bm.faces),
             'boundary_edges': sum(edge.is_boundary for edge in bm.edges),
             'nonmanifold_nonboundary_edges': sum(not edge.is_manifold and not edge.is_boundary for edge in bm.edges),
             'zero_area_faces': sum(face.calc_area() < 1e-12 for face in bm.faces)}
    if obj == shell:
        stats['signed_volume'] = bm.calc_volume(signed=True)
        stats['unassigned_material_faces'] = sum(obj.data.materials[p.material_index] is None for p in obj.data.polygons)
        report['shell'] = stats
    report['objects'][obj.name] = stats
    bm.free()
assert report['shell']['boundary_edges'] == 0, 'Shell is open'
assert report['shell']['nonmanifold_nonboundary_edges'] == 0, 'Shell is non-manifold'
assert report['shell']['zero_area_faces'] == 0, 'Shell contains degenerate faces'
assert report['shell']['signed_volume'] > 0, 'Shell normals are reversed'
assert report['shell']['unassigned_material_faces'] == 0, 'Shell has unprotected default material'

# Export the closed shell for independent MeshLab inspection (not decorative disks).
bpy.ops.object.select_all(action='DESELECT')
shell.hide_set(False)
shell.hide_render = False
shell.select_set(True)
bpy.context.view_layer.objects.active = shell
bpy.ops.wm.ply_export(filepath=str(OUTPUT / 'blackjack_refined_shell.ply'),
                      export_selected_objects=True, export_triangulated_mesh=True,
                      export_uv=False, export_normals=False)

# Bake an editable UV channel-ID guide. It is not a final color or livery texture.
colors = {'Paint_Primary': (1,0,0,1), 'Paint_Secondary': (0,1,0,1),
          'Paint_Accent': (0,0,1,1)}
image = bpy.data.images.new('Blackjack_Refined_PaintID', width=1024, height=1024)
originals = list(shell.data.materials)
for index, source in enumerate(originals):
    if source is None:
        continue
    mat = bpy.data.materials.new('IDBake_' + source.name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    emission = nodes.new('ShaderNodeEmission')
    emission.inputs['Color'].default_value = colors.get(source.name, (0,0,0,1))
    output = nodes.new('ShaderNodeOutputMaterial')
    mat.node_tree.links.new(emission.outputs[0], output.inputs['Surface'])
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = image
    nodes.active = texture
    shell.data.materials[index] = mat
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 1
bpy.context.scene.render.bake.margin = 4
bpy.ops.object.bake(type='EMIT')
image.filepath_raw = str(OUTPUT / 'blackjack_refined_paint_id.png')
image.file_format = 'PNG'
image.save()
for index, source in enumerate(originals):
    if source is None:
        continue
    shell.data.materials[index] = source
(OUTPUT / 'blackjack_refined_topology.json').write_text(json.dumps(report, indent=2) + '\n')
print('REFINED_TOPOLOGY', json.dumps(report['shell']))
