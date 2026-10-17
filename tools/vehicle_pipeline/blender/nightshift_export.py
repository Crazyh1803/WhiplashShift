"""Scene finalisation, GLB/LOD export and QA renders for the Nightshift candidate."""

import bpy

import nightshift_core as C
import nightshift_qa as Q
import nightshift_trace as T

QA_DIR_NAME = "qa/nightshift_blueprint"
SEMANTIC = ("Nightshift_Paint", "Nightshift_Secondary", "Nightshift_Stripe")


def source_meshes(cols):
    return [o for o in cols["NIGHTSHIFT_SOURCE"].objects if o.type == "MESH"]


def finalize_scene(cols, shell, blueprint):
    for obj in source_meshes(cols):
        if not obj.data.uv_layers:
            C.smart_uv(obj)
    image = bpy.data.images.load(str(blueprint), check_existing=True)
    image.pack()
    ref = bpy.data.objects.new("Reference_80s_Blueprint", None)
    ref.empty_display_type = "IMAGE"
    ref.data = image
    ref.empty_display_size = 5.0
    ref.hide_render = True
    ref.hide_viewport = True
    cols["REFERENCE"].objects.link(ref)
    shell["vehicle_id"] = "nightshift"
    shell["design"] = "reversible 80s Chevy square-body truck / Camaro"
    shell["blueprint"] = "80s.jpg"
    shell["wheelbase"] = T.WHEELBASE
    shell["scale_m_per_px"] = T.SCALE
    for name in ("CUTTERS", "REFERENCE"):
        cols[name].hide_render = True
        cols[name].hide_viewport = True
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"


def _is_wheel(obj):
    return obj.name.startswith(("Wheel_Truck_", "Wheel_Coupe_"))


def _copy(obj, col):
    new = obj.copy()
    new.data = obj.data.copy()
    col.objects.link(new)
    return new


def _decimate(obj, ratio):
    if len(obj.data.polygons) < 24:
        return
    mod = obj.modifiers.new("lod", "DECIMATE")
    mod.ratio = ratio
    mod.use_collapse_triangulate = False
    C.apply_all_modifiers(obj)
    C.harden(obj, 35.0)


def _join(objs, name, col):
    if not objs:
        return None
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    spare = [o.data for o in objs[1:]]
    bpy.ops.object.join()
    for mesh in spare:
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name + "_mesh"
    return joined


def build_export_set(cols, level):
    """Copy source meshes into EXPORT_* with merged small details. level: 0, 1, 2."""
    col = cols[["EXPORT_GAMEPLAY", "EXPORT_LOD1", "EXPORT_LOD2"][level]]
    for o in list(col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    groups = {}
    out = []
    for src in source_meshes(cols):
        obj = _copy(src, col)
        for m in list(obj.modifiers):
            obj.modifiers.remove(m)
        name = src.name
        if name.startswith("Body_"):
            if level:
                _decimate(obj, (0.62, 0.34)[level - 1])
            out.append(obj)
        elif name.startswith("Glass_"):
            out.append(obj)
        elif _is_wheel(obj):
            if level and ("_Tire_" in name or "_Rim_" in name):
                _decimate(obj, (0.55, 0.30)[level - 1])
            if level == 2 and "_Spoke_" in name:
                _decimate(obj, 0.6)
            out.append(obj)
        else:
            small = name.startswith(("Seam_", "Handle_", "Roof_Marker", "Marker_", "Rail_", "Wiper_",
                                     "Molding_Belt", "Coupe_HoodSlat", "Coupe_IntakeSlat",
                                     "Truck_GrilleBar", "Coupe_GrilleSlat", "Truck_HeadlampRing",
                                     "Truck_BumperBracket", "Truck_TowHook", "Coupe_SplitterPlate",
                                     "Truck_PushGuardPad", "Molding_Flank", "Coupe_ChinLamp", "Truck_BezelMid"))
            if small and level == 2:
                bpy.data.objects.remove(obj, do_unlink=True)
                continue
            if small and level == 1 and name.startswith(("Seam_", "Roof_Marker", "Handle_")):
                bpy.data.objects.remove(obj, do_unlink=True)
                continue
            key = obj.data.materials[0].name
            groups.setdefault(key, []).append(obj)
    for key, objs in sorted(groups.items()):
        joined = _join(objs, "Detail_" + key.replace("Nightshift_", ""), col)
        if joined:
            out.append(joined)
    return col


def triangles_of(col):
    return C.triangle_count([o for o in col.objects if o.type == "MESH"])


def export_collection(col, path):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    objs = [o for o in col.objects if o.type == "MESH"]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
                              export_apply=True)
    return path.stat().st_size


def export_all(cols, model_dir, stem):
    result = {}
    sizes = {}
    for level, rel in ((0, f"{stem}.glb"), (1, f"lod/{stem}_LOD1.glb"), (2, f"lod/{stem}_LOD2.glb")):
        col = build_export_set(cols, level)
        tris = triangles_of(col)
        sizes[f"lod{level}"] = {"triangles": tris, "objects": len(col.objects),
                                "bytes": export_collection(col, model_dir / rel)}
        for o in list(col.objects):
            data = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if data.users == 0:
                bpy.data.meshes.remove(data)
        col.hide_render = True
    result["exports"] = sizes
    return result


def render_qa(cols, model_dir, stem, blueprint):
    out_dir = model_dir.parents[4] / "tools/vehicle_pipeline" / QA_DIR_NAME
    out_dir.mkdir(parents=True, exist_ok=True)
    studio = Q.build_studio(cols)
    for view in ("side", "top", "front_truck", "front_coupe", "three_quarter_truck",
                 "three_quarter_coupe", "far_side_three_quarter", "cabin", "truck_detail",
                 "coupe_detail", "wheel_truck", "wheel_coupe", "coupe_nose", "truck_nose", "cab_step", "coupe_window"):
        Q.configure(view, 1280, 720)
        Q.render(out_dir / f"{stem}_{view}.png")
    for view in ("side", "top", "front_truck", "front_coupe"):
        Q.overlay(view, blueprint, out_dir / f"{stem}_{view}_overlay.png")
    print("AK: rendered " + str(out_dir))
