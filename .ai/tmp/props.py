import bpy
props=bpy.ops.export_scene.gltf.get_rna_type().properties
print("AK: "+str([k for k in props.keys() if "tang" in k or "image" in k or "color" in k or "uv" in k.lower()]))
