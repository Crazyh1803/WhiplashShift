import sys,json
sys.path.insert(0,"tools/city_pipeline")
import validate_city_families as V
js,b=V.VIM.read_glb("godot/assets/city/realism/bollard.glb")
print("AK: "+json.dumps([p["attributes"] for p in js["meshes"][0]["primitives"]][:2]))
print("AK: "+json.dumps(js["materials"][0]))
print("AK: "+json.dumps(js["images"][:3]))
