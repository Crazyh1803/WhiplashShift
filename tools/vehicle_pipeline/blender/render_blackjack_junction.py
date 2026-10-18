"""Focused central-junction renders from a saved Blackjack source (read-only QA).

Usage: blender -b <blackjack_blueprint.blend> --python render_blackjack_junction.py -- <out_dir> <prefix>
The saved source is in the canonical (un-raked) frame, so every camera is
carried through INVERSE_POSE to see the level blueprint view used by the main QA.
"""
import sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

POSE = Matrix.Translation((0, .064, 0)) @ Matrix.Rotation(-.0905, 4, 'Z')
out, prefix = Path(sys.argv[sys.argv.index('--')+1]), sys.argv[sys.argv.index('--')+2]
out.mkdir(parents=True, exist_ok=True)
scene = bpy.context.scene
camera = scene.camera
camera.data.type = 'ORTHO'
scene.render.resolution_x, scene.render.resolution_y = 1600, 900
views = {'junction_side': ((0, .02, 3), (0, .02, 0), (0, 1, 0), .95),
         'junction_top': ((0, 3, 0), (0, 0, 0), (0, 0, -1), .95),
         'junction_three_quarter': ((1.9, 1.1, 1.9), (0, -.02, 0), (0, 1, 0), 1.0)}
for name, (loc, target, up, scale) in views.items():
    loc, target, up = Vector(loc), Vector(target), Vector(up)
    forward = (target-loc).normalized()
    right = forward.cross(up).normalized()
    basis = Matrix((right, right.cross(forward), -forward)).transposed()
    camera.matrix_world = Matrix.Translation(loc) @ basis.to_4x4()
    camera.matrix_world = POSE.inverted() @ camera.matrix_world
    camera.data.ortho_scale = scale
    scene.render.filepath = str(out/f'{prefix}_{name}.png')
    bpy.ops.render.render(write_still=True)
print('JUNCTION_RENDERS', prefix)
