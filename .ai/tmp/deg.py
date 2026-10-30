import sys,json
sys.path.insert(0,"tools/city_pipeline")
import validate_city_families as V
V.errors.clear()
import math
js,b=V.VIM.read_glb("godot/assets/city/realism/freight_depot_lod1.glb")
for m in js["meshes"][0]["primitives"]:
    if js["materials"][m["material"]]["name"]!="roof_membrane": continue
    pos=V.VIM.accessor(js,b,m["attributes"]["POSITION"]);idx=[r[0] for r in V.VIM.accessor(js,b,m["indices"])]
    n=0
    for t in range(0,len(idx),3):
        a,c,d=[pos[i] for i in idx[t:t+3]]
        u=[c[k]-a[k] for k in range(3)];v=[d[k]-a[k] for k in range(3)]
        cr=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        if sum(x*x for x in cr)<1e-14 and n<4:
            n+=1;print("AK: "+json.dumps([a,c,d]))
