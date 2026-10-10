"""MeshLab 2025.07 filters through pinned local Python bindings; read-only mesh QA.

Run AFTER blender/validate_blackjack_blueprint.py, in an isolated environment
with pymeshlab==2025.7.post1. No source mesh is
repaired or rewritten: topology/scale failures stop the validation.
"""
import json
from pathlib import Path
import pymeshlab
import subprocess

root=Path(__file__).resolve().parents[2]
output=root/'godot/assets/vehicles/models/blackjack'
blender_report=json.loads((output/'blackjack_blueprint_topology.json').read_text())
assert blender_report['validation_passed'], 'Blender validation failed; never inspect stale PLY'
for key,filename in [('glb_sha256','blackjack_blueprint.glb'),('shell_ply_sha256','blackjack_blueprint_shell.ply')]:
    actual=subprocess.check_output(['sha256sum',str(output/filename)],text=True).split()[0]
    assert actual==blender_report[key], 'Stale Blender validation: '+filename
meshset=pymeshlab.MeshSet()
meshset.load_new_mesh(str(output/'blackjack_blueprint_shell.ply'))
topology=meshset.get_topological_measures()
geometry=meshset.get_geometric_measures()
box=geometry['bbox']
assert topology['is_mesh_two_manifold'] and topology['boundary_edges']==0, topology
assert topology['number_holes']==0 and topology['connected_components_number']==1, topology
assert geometry['mesh_volume']>0, 'Reversed shell normals'
assert 4.7<box.dim_x()*2.345<5.1, 'Unexpected vehicle scale'
report={'engine':'MeshLab 2025.07 / PyMeshLab 2025.7.post1',
        'glb_sha256':blender_report['glb_sha256'],
        'filters':['get_topological_measures','get_geometric_measures'],
        'topology':topology,'source_shell_extents':[box.dim_x(),box.dim_y(),box.dim_z()],
        'game_scale':2.345,'source_shell_volume':geometry['mesh_volume']}
(output/'blackjack_blueprint_meshlab.json').write_text(json.dumps(report,indent=2)+'\n')
print('MESHLAB_BLUEPRINT',json.dumps(report))
