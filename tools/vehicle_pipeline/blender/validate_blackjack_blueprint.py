"""Independent shell/wheel manifold checks plus the native channel-ID bake."""
from pathlib import Path
import json
import bpy
import bmesh
import math
import subprocess

script_dir = Path(__file__).resolve().parent
previous = script_dir/'validate_blackjack_refined.py'
code = previous.read_text().replace('blackjack_refined','blackjack_blueprint').replace('Body_TracedShell','Body_BlueprintShell')
bpy.data.collections['GAMEPLAY_EXPORT'].hide_render = False
try:
    exec(compile(code,str(previous),'exec'),globals())
except Exception:
    report['validation_passed']=False
    (OUTPUT/'blackjack_blueprint_topology.json').write_text(json.dumps(report,indent=2)+'\n')
    raise
# Invalidate the receipt until all blueprint-specific checks finish as well.
report['validation_passed']=False
(OUTPUT/'blackjack_blueprint_topology.json').write_text(json.dumps(report,indent=2)+'\n')
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
pose = Matrix.Translation((0,.064,0)) @ Matrix.Rotation(-.0905,4,'Z')
# Independent exterior samples catch grey cage faces mislabeled as protected.
# The builder bakes INVERSE_POSE into exports. POSE below restores the level
# blueprint frame used by source_point; inverse-transforming rays would be wrong.
level_transform=pose @ shell.matrix_world
frame_error=max(abs(level_transform[row][column]-(1 if row==column else 0))
                for row in range(4) for column in range(4))
assert frame_error<1e-6, ('Blueprint landmark frame is misaligned',frame_error)
report['source_level_transform_identity_error']=frame_error
surface = BVHTree.FromPolygons([pose @ shell.matrix_world @ v.co for v in shell.data.vertices],
                              [p.vertices for p in shell.data.polygons])
def source_point(px,py,z=0):
    scale=1.364606/334
    return Vector(((px-527)*scale-.02485,(235-py)*scale-.395,z))
paint_landmarks={}
for name,px,py,expected in [('truck_door',382,135,'Paint_Primary'),
                            ('equipment_panel',432,135,'Paint_Secondary'),
                            ('transition_panel',511,120,'Paint_Primary'),
                            ('coupe_door',601,191,'Paint_Primary')]:
    for side in (-1,1):
        _,_,index,_=surface.ray_cast(source_point(px,py,side*.8),Vector((0,0,-side)))
        assert index is not None, ('Missing body sample',name,side)
        actual=shell.data.materials[shell.data.polygons[index].material_index].name
        paint_landmarks[name+str(side)]=actual
        assert actual==expected, ('Fixed grey body paint leak',name,side,actual,expected)
for name,px,expected in [('rugged_hood',305,'Paint_Primary'),
                        ('coupe_hood',733,'Paint_Primary'),
                        ('coupe_roof',588,'Paint_Primary')]:
    origin=source_point(px,0)
    origin.y=1.5
    _,_,index,_=surface.ray_cast(origin,Vector((0,-1,0)))
    assert index is not None, ('Missing roof sample',name)
    actual=shell.data.materials[shell.data.polygons[index].material_index].name
    paint_landmarks[name]=actual
    assert actual==expected, ('Fixed grey roof paint leak',name,actual,expected)
for px in (510,750):
    origin=source_point(px,235)
    origin.y=-1.5
    _,_,index,_=surface.ray_cast(origin,Vector((0,1,0)))
    assert index is not None and shell.data.materials[shell.data.polygons[index].material_index].name=='ArmorProtected', ('Underbody must remain protected',px)
    paint_landmarks['underside'+str(px)]='ArmorProtected'
report['paint_landmarks']=paint_landmarks
guard_report={}
for group_name in ('GAMEPLAY_EXPORT','LOD1_EXPORT'):
    count=0
    for obj in bpy.data.collections[group_name].objects:
        if not obj.name.startswith('Detail_BrushGuardRail_'):
            continue
        py=int(obj.name.split('_')[-1].split('.')[0])
        vertices=[pose @ obj.matrix_world @ v.co for v in obj.data.vertices]
        guard=BVHTree.FromPolygons(vertices,[p.vertices for p in obj.data.polygons])
        mirror_error=max(guard.find_nearest(Vector((v.x,v.y,-v.z)))[3] for v in vertices)
        assert mirror_error<.00005, ('Lopsided guard mesh',obj.name,mirror_error)
        heights=[]
        for z in (-.22,-.11,0,.11,.22):
            x=source_point(270,py).x
            top=guard.ray_cast(Vector((x,1.5,z)),Vector((0,-1,0)))[0]
            bottom=guard.ray_cast(Vector((x,-1.5,z)),Vector((0,1,0)))[0]
            assert top is not None and bottom is not None, ('Guard rail missing section',obj.name,z)
            heights.append((top.y+bottom.y)/2)
            # Native tube uses the fixed eight-sided bevel section: allow its
            # polygonal silhouette's sagitta, but reject collapsed flat rails.
            assert .0067<(top.y-bottom.y)/2<.0072, ('Crushed eight-sided guard section',obj.name,z)
            y=source_point(270,py).y
            front=guard.ray_cast(Vector((-1.5,y,z)),Vector((1,0,0)))[0]
            back=guard.ray_cast(Vector((1.5,y,z)),Vector((-1,0,0)))[0]
            assert front is not None and back is not None, ('Missing guard depth section',obj.name,z)
            assert .0067<(back.x-front.x)/2<.0072, ('Flattened guard depth section',obj.name,z)
        error=max(abs(height-source_point(270,py).y) for height in heights)
        assert error<.00005, ('Uneven guard rail',obj.name,error)
        guard_report[group_name+'/'+obj.name]={'mirror_error':mirror_error,'rail_level_error':error}
        count+=1
    assert count==3, ('Missing three preserved brush-guard rails',group_name)
report['brush_guard']=guard_report
glass_clearance = {}
for name in ('GAMEPLAY_EXPORT','LOD1_EXPORT'):
    group = bpy.data.collections[name]
    skin = next(obj for obj in group.objects if obj.name.startswith('Body_BlueprintShell'))
    bm=bmesh.new()
    bm.from_mesh(skin.data)
    assert all(edge.is_manifold for edge in bm.edges), ('Open/nonmanifold shell',name)
    assert all(face.calc_area()>1e-12 for face in bm.faces), ('Degenerate shell face',name)
    assert bm.calc_volume(signed=True)>0, ('Reversed shell normals',name)
    bm.free()
    surface = BVHTree.FromPolygons([pose @ skin.matrix_world @ v.co for v in skin.data.vertices],
                                  [p.vertices for p in skin.data.polygons])
    for obj in group.objects:
        if len(obj.data.materials)!=1 or obj.data.materials[0].name!='Glass':
            continue
        side_window = any(text in obj.name for text in ('RuggedSide','CoupeSide','CoupeQuarter'))
        obj.data.calc_loop_triangles()
        gaps = []
        for tri in obj.data.loop_triangles:
            corners = [pose @ obj.matrix_world @ obj.data.vertices[i].co for i in tri.vertices]
            samples = [sum(corners,Vector())/3]+[(corners[i]+corners[(i+1)%3])*.5 for i in range(3)]
            for sample in samples:
                if side_window:
                    side = -1 if sample.z<0 else 1
                    origin,direction = Vector((sample.x,sample.y,side*.8)),Vector((0,0,-side))
                else:
                    origin,direction = Vector((sample.x,1.5,sample.z)),Vector((0,-1,0))
                hit,normal,_,_ = surface.ray_cast(origin,direction)
                assert hit is not None, ('Missing window support',obj.name)
                gaps.append((sample-hit).dot(normal))
        stats = {'samples':len(gaps),'minimum_source_clearance':min(gaps),'maximum_source_clearance':max(gaps)}
        glass_clearance[name+'/'+obj.name] = stats
        assert min(gaps)>.0001, ('Glass intersects paintable shell',name,obj.name,stats)
        assert max(gaps)<.010, ('Glass floats above shell',name,obj.name,stats)
report['protected_glass_clearance'] = glass_clearance
modules = {}
for kind in ('RIM','TIRE'):
    for style in ('AERO','RUGGED'):
        collection = bpy.data.collections[f'BLUEPRINT_{kind}_{style}_EXPORT']
        obj = next(obj for obj in collection.objects if obj.type == 'MESH')
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        stats = {'boundary_edges':sum(e.is_boundary for e in bm.edges),
                 'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),
                 'zero_area_faces':sum(f.calc_area()<1e-12 for f in bm.faces),
                 'signed_volume':bm.calc_volume(signed=True)}
        assert stats['boundary_edges'] == 0 and stats['nonmanifold_edges'] == 0, (kind,style,stats)
        assert stats['zero_area_faces'] == 0 and stats['signed_volume'] > 0, (kind,style,stats)
        bm.free()
        modules[f'{kind}_{style}'] = stats
report['modules'] = modules
report['validation_passed']=True
for key,filename in [('glb_sha256','blackjack_blueprint.glb'),('shell_ply_sha256','blackjack_blueprint_shell.ply')]:
    report[key]=subprocess.check_output(['sha256sum',str(OUTPUT/filename)],text=True).split()[0]
# Independent angular distortion of both export UVs, not merely UV presence.
for collection_name,key in [('GAMEPLAY_EXPORT','paint_uv_anisotropy'),
                            ('LOD1_EXPORT','lod1_paint_uv_anisotropy')]:
    skin=next(obj for obj in bpy.data.collections[collection_name].objects
              if obj.name.startswith('Body_BlueprintShell'))
    stretch=[]
    skin.data.calc_loop_triangles()
    uv=skin.data.uv_layers.active.data
    for tri in skin.data.loop_triangles:
        if not skin.data.materials[tri.material_index].name.startswith('Paint_'):
            continue
        p0,p1,p2=[skin.data.vertices[i].co for i in tri.vertices]
        t0,t1,t2=[uv[i].uv for i in tri.loops]
        length=(p1-p0).length
        if length<1e-8:
            continue
        x=(p2-p0).dot(p1-p0)/length
        y=math.sqrt(max(0,(p2-p0).length_squared-x*x))
        if y<1e-8:
            continue
        a,c=(t1-t0)/length
        b,d=((t2-t0)-(t1-t0)*x/length)/y
        trace=a*a+b*b+c*c+d*d
        det=a*d-b*c
        root=math.sqrt(max(0,trace*trace-4*det*det))
        stretch.append(math.sqrt((trace+root)/max(1e-20,trace-root)))
    stretch.sort()
    report[key]={'triangles':len(stretch),'median':stretch[len(stretch)//2],
                 'p95':stretch[int(len(stretch)*.95)],'maximum':max(stretch)}
    assert all(math.isfinite(value) and value<4 for value in stretch), ('Collapsed paint UV island',collection_name)
    assert report[key]['p95']<2, ('Paint UV distortion exceeds the livery gate',collection_name)
(OUTPUT/'blackjack_blueprint_topology.json').write_text(json.dumps(report,indent=2)+'\n')
print('BLUEPRINT_MODULE_TOPOLOGY',json.dumps(modules))
