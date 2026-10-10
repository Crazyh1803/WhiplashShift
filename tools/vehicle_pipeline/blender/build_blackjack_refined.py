"""Reuse the verified export rig, replacing the v2 body with the traced cage.

The v2 asset is immutable here. All new artifacts use blackjack_refined names.
"""
import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT_DIR = ROOT / 'tools/vehicle_pipeline/blender'
MODEL_DIR = ROOT / 'godot/assets/vehicles/models/blackjack'
source_path = SCRIPT_DIR / 'build_blackjack_production_v2.py'
tree = ast.parse(source_path.read_text())
ns = dict(__name__='__main__', ROOT=ROOT, SCRIPT_DIR=SCRIPT_DIR, MODEL_DIR=MODEL_DIR)
ns.update({key: MODEL_DIR / filename for key, filename in {
    'GLB_PATH': 'blackjack_refined.glb',
    'LOD_PATH': 'blackjack_refined_lod1.glb',
    'QA_PATH': 'blackjack_refined_qa.json',
    'REF_SIDE': 'blackjack_realistic_candidate_v2.png',
    'REF_RUGGED': 'blackjack_rugged_front.png',
    'REF_INTERCEPTOR': 'blackjack_interceptor_front.png',
}.items()})
ns['BLEND_PATH'] = SCRIPT_DIR / 'blackjack_refined.blend'
ns['RENDERS'] = {view: MODEL_DIR / f'blackjack_refined_{view}.png'
                 for view in ('side', 'three_quarter', 'rugged_front', 'interceptor_front')}


def execute(nodes):
    module = ast.Module(body=nodes, type_ignores=[])
    ast.fix_missing_locations(module)
    exec(compile(module, str(source_path), 'exec'), ns)


for node in tree.body:
    if isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef)):
        execute([node])
    elif isinstance(node, ast.Assign) and any(
        isinstance(target, ast.Name) and target.id in {'COL', 'BODY', 'PREVIEW', 'CUTTERS', 'MAT'}
        for target in node.targets
    ):
        execute([node])

geometry_path = SCRIPT_DIR / 'blackjack_refined_geometry.py'
exec(compile(geometry_path.read_text(), str(geometry_path), 'exec'), ns)

original_render = ns['render']


def render_seated(*args):
    # Match the unchanged physics' static rake, only for the studio renders.
    # Transform Boolean operands with the shell; restore the editable cage after.
    pose = ns['Matrix'].Translation((0,.064,0)) @ ns['Matrix'].Rotation(-.0905,4,'Z')
    objects = list(ns['BODY'].all_objects) + list(ns['CUTTERS'].all_objects)
    objects += [obj for obj in ns['PREVIEW'].all_objects
                if obj.type in {'MESH','CURVE'} and obj.name != 'Preview_Ground']
    originals = {obj: obj.matrix_world.copy() for obj in objects}
    try:
        for obj in objects:
            obj.matrix_world = pose @ originals[obj]
        return original_render(*args)
    finally:
        for obj, matrix in originals.items():
            obj.matrix_world = matrix


ns['render'] = render_seated
tail_start = next(index for index, node in enumerate(tree.body)
                  if isinstance(node, ast.For) and isinstance(node.iter, ast.Attribute)
                  and isinstance(node.iter.value, ast.Name) and node.iter.value.id == 'BODY'
                  and node.iter.attr == 'all_objects')
for node in tree.body[tail_start:]:
    if isinstance(node, ast.FunctionDef):
        continue
    if isinstance(node, ast.Expr) and isinstance(node.value, ast.Call):
        call = node.value
        if isinstance(call.func, ast.Name) and call.func.id == 'render':
            for obj in ns['PREVIEW'].all_objects:
                if obj.type == 'LIGHT' and not obj.get('neutral_qa_energy'):
                    obj.data.energy *= .22
                    obj['neutral_qa_energy'] = True
        if isinstance(call.func, ast.Name) and call.func.id == 'box' and call.args:
            if isinstance(call.args[0], ast.Constant) and call.args[0].value == 'Preview_Ground':
                for collection_name in ('GAMEPLAY_EXPORT', 'LOD1_EXPORT'):
                    for obj in ns['COL'][collection_name].all_objects:
                        obj.hide_render = True
    execute([node])

report = ns['json'].loads(ns['QA_PATH'].read_text())
report['asset_status'] = 'candidate_only; visual acceptance pending'
report['material_source'] = 'tools/vehicle_pipeline/materials/blackjack_*.ptex (Material Maker 1.7)'
report['blueprint'] = '/home/crazyh/Downloads/WhiplashShiftModels/SpyHunter.jpg'
report['modular_rims'] = {style: str((MODEL_DIR / f'blackjack_refined_rim_{style}.glb').relative_to(ROOT))
                          for style in ('aero', 'rugged')}
report['modular_tires'] = {style: str((MODEL_DIR / f'blackjack_refined_tire_{style}.glb').relative_to(ROOT))
                           for style in ('aero', 'rugged')}
report['module_triangles'] = {kind + '_' + style: ns['triangle_count'](collection)[1]
                              for kind, collections in [('rim',ns['RIM_COLLECTIONS']),('tire',ns['TIRE_COLLECTIONS'])]
                              for style, collection in collections.items()}
modules = report['module_triangles']
report['triangle_budget_scope'] = 'body GLB only; modular wheels and runtime parts are additional'
report['assembled_minimum_triangles'] = report['gameplay']['triangles'] + sum(
    instances * (modules['rim_' + style] + modules['tire_' + style])
    for style, instances in [('aero', 2), ('rugged', 4)]
)
# A lower bound can prove failure, but cannot prove a complete runtime pass.
report['assembled_budget_passed'] = False if report['assembled_minimum_triangles'] > 40000 else None
report['source'] = str(Path(report['source']).relative_to(ROOT))
for key in ('gameplay', 'lod1'):
    report[key]['path'] = str(Path(report[key]['path']).relative_to(ROOT))
report['references'] = [str(Path(path).relative_to(ROOT)) for path in report['references']]
report['renders'] = {key: str(Path(path).relative_to(ROOT)) for key, path in report['renders'].items()}
ns['QA_PATH'].write_text(ns['json'].dumps(report, indent=2) + '\n')
print('REFINED_OUTPUT', ns['GLB_PATH'])
