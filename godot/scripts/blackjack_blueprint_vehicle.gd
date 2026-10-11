## Blueprint visual rig; physical integration is inherited unchanged.
extends Vehicle

const DISPLAY_RADIUS := {"A": .3065869288622755, "B": .3257486119161677}
const DISPLAY_TRACK := {"A": .804335, "B": .8442}
const TIRES := {
	"A": preload("res://assets/vehicles/models/blackjack/blackjack_blueprint_tire_aero.glb"),
	"B": preload("res://assets/vehicles/models/blackjack/blackjack_blueprint_tire_rugged.glb"),
}
var supports: Array[MeshInstance3D] = []
var visual_wheels: Array[Wheel] = []
var _decal_specs: Array[Dictionary] = []


func _enabled() -> bool:
	return _visual_config.get("rig","")=="blackjack_blueprint"


func _radius(end: String) -> float:
	return float(_visual_config.get("display_radius",DISPLAY_RADIUS).get(end,tuning.wheel_radius(end)))


func _track(end: String) -> float:
	return float(_visual_config.get("display_track",DISPLAY_TRACK).get(end,tuning.half_track))


func _arch_key(wheel: Wheel) -> String:
	return ("M" if wheel.name.begins_with("Bogie_") else wheel.end)+("_L" if wheel.side<0 else "_R")


func _place_frozen_wheel(wheel: Wheel) -> void:
	# Frozen previews have no raycasts: seat the rendered assembly in its
	# authored arch without changing radius, ride distance or any hardpoint.
	var assembly := wheel.get_node_or_null("ModularWheelVisual") as Node3D
	if assembly!=null and freeze:
		var center: Vector3 = _visual_config["arch_centers"][_arch_key(wheel)]
		assembly.position=wheel.to_local(to_global(center))


func configure_static_preview() -> void:
	if _enabled() and freeze:
		rotation.x=float(_visual_config["preview_pitch"])
		position.y=float(_visual_config["preview_height"])


func _build_wheels() -> void:
	super._build_wheels()
	if _enabled():
		for wheel: Wheel in wheels:
			_install_tire(wheel)


func _refresh_wheel_visuals_and_mounts() -> void:
	super._refresh_wheel_visuals_and_mounts()
	if _enabled():
		for wheel: Wheel in wheels:
			_install_tire(wheel)
		_update_axle_visuals()
		_pose_supports()


func _build_visual_bogie() -> void:
	super._build_visual_bogie()
	visual_wheels = wheels.duplicate()
	if _enabled() and _bogie_root!=null:
		for child: Node in _bogie_root.get_children():
			if child is Wheel:
				_install_tire(child)
				visual_wheels.append(child)
	_update_axle_visuals()
	_pose_supports()


func _wheel_visual_config(end: String,side: int) -> Dictionary:
	var config := super._wheel_visual_config(end,side)
	if _enabled():
		var offset: Vector3 = config.get("assembly_offset",Vector3.ZERO)
		offset.x+=side*(_track(end)-absf(_wheel_mount(end,side).x))
		offset.y+=_radius(end)-tuning.wheel_radius(end)
		var center: Vector3 = _visual_config["arch_centers"][end+("_L" if side<0 else "_R")]
		offset.z+=center.z-_wheel_mount(end,side).z
		config["assembly_offset"]=offset
	return config


func _install_tire(wheel: Wheel) -> void:
	var assembly := wheel.get_node_or_null("ModularWheelVisual") as Node3D
	if assembly==null or not _enabled():
		return
	for old_name: String in ["Tire","Tire_Blueprint"]:
		var old := assembly.get_node_or_null(old_name)
		if old!=null:
			assembly.remove_child(old)
			old.free()
	var tire := (TIRES[wheel.end] as PackedScene).instantiate() as Node3D
	tire.name="Tire_Blueprint"
	tire.scale=Vector3.ONE*wheel.radius
	assembly.add_child(tire)
	assembly.scale=Vector3.ONE*_radius(wheel.end)/wheel.radius
	wheel._place_visual(wheel.ride_distance)
	_place_frozen_wheel(wheel)
	var rim := assembly.get_node_or_null("SwappableRim")
	if rim!=null:
		for mesh: MeshInstance3D in rim.find_children("*","MeshInstance3D",true,false):
			mesh.material_override=null


func _update_axle_visuals() -> void:
	super._update_axle_visuals()
	if not _enabled():
		return
	for end: String in _axle_visuals:
		var pair := _wheel_pair(end)
		if pair.size()!=2:
			continue
		var a := pair[0].get_node_or_null("ModularWheelVisual") as Node3D
		var b := pair[1].get_node_or_null("ModularWheelVisual") as Node3D
		if a==null or b==null:
			continue
		var axle := _axle_visuals[end] as Node3D
		axle.position=to_local((a.global_position+b.global_position)*.5)
		(axle.get_node("Shaft").mesh as CylinderMesh).height=a.global_position.distance_to(b.global_position)-.08
	if not freeze and is_visible_in_tree():
		_pose_supports()


func _update_visual_bogie() -> void:
	super._update_visual_bogie()
	if not _enabled() or _bogie_root==null or not _bogie_root.visible or wheels.size()!=4:
		return
	var shaft := _bogie_root.get_node_or_null("Shaft") as MeshInstance3D
	if freeze:
		_bogie_root.position.y=0
		for child: Node in _bogie_root.get_children():
			if child is Wheel:
				_place_frozen_wheel(child)
		if shaft!=null:
			shaft.position=(_visual_config["arch_centers"]["M_L"]+_visual_config["arch_centers"]["M_R"])*.5
			(shaft.mesh as CylinderMesh).height=_track("B")*2-.08
		return
	for child: Node in _bogie_root.get_children():
		if child is Wheel:
			child._place_visual(child.ride_distance)
	var front := _wheel_pair("A")
	var rear := _wheel_pair("B")
	var z_a: float=(front[0].position.z+front[1].position.z)*.5
	var z_b: float=(rear[0].position.z+rear[1].position.z)*.5
	if absf(z_b-z_a)<.0001:
		return
	var contact_a := 0.0
	var contact_b := 0.0
	for i in range(2):
		contact_a+=(front[i].position.y-front[i].ride_distance)*.5
		contact_b+=(rear[i].position.y-rear[i].ride_distance)*.5
	var middle_center: Vector3 = _visual_config["arch_centers"]["M_R"]
	var t := clampf((middle_center.z-z_a)/(z_b-z_a),0,1)
	_bogie_root.position.y=lerpf(contact_a,contact_b,t)+tuning.wheel_radius("B")
	if shaft!=null:
		shaft.position.y=_radius("B")-tuning.wheel_radius("B")
		shaft.position.z=middle_center.z
		(shaft.mesh as CylinderMesh).height=_track("B")*2-.08


func _pose_supports() -> void:
	if not _enabled():
		return
	if supports.size()!=visual_wheels.size():
		for mesh in supports:
			remove_child(mesh)
			mesh.free()
		supports.clear()
		for wheel in visual_wheels:
			var mesh := MeshInstance3D.new()
			mesh.name="VisualSuspensionLink_"+wheel.name
			var cylinder := CylinderMesh.new()
			cylinder.top_radius=.038
			cylinder.bottom_radius=.038
			cylinder.height=1
			cylinder.radial_segments=12
			mesh.mesh=cylinder
			var material := StandardMaterial3D.new()
			material.albedo_color=Color("2a3032")
			material.metallic=.82
			material.roughness=.45
			mesh.material_override=material
			add_child(mesh)
			supports.append(mesh)
	for i in range(visual_wheels.size()):
		var wheel := visual_wheels[i]
		var assembly := wheel.get_node_or_null("ModularWheelVisual") as Node3D
		supports[i].visible=assembly!=null and wheel.visible
		if assembly==null:
			continue
		var center := to_local(assembly.global_position)
		var upper := Vector3(wheel.side*.57,.10 if wheel.end=="A" else -.04,center.z+.11)
		var lower := Vector3(wheel.side*.68,center.y,center.z)
		var y := (lower-upper).normalized()
		var x := y.cross(Vector3.FORWARD)
		if x.length_squared()<.0001:
			x=y.cross(Vector3.RIGHT)
		x=x.normalized()
		supports[i].position=(upper+lower)*.5
		supports[i].basis=Basis(x,y*(lower-upper).length(),x.cross(y))


func _configure_imported_meshes(node: Node) -> void:
	super._configure_imported_meshes(node)
	if not _enabled() or not node is MeshInstance3D:
		return
	var mesh := node as MeshInstance3D
	var paintable := mesh.mesh.get_surface_count()>0
	for i in range(mesh.mesh.get_surface_count()):
		var material := mesh.mesh.surface_get_material(i)
		paintable=paintable and material!=null and material.resource_name.begins_with("Paint_")
	mesh.layers=3 if paintable else 1


func _configure_blackjack_semantic_surface(mesh: MeshInstance3D,surface: int,lower_name: String) -> void:
	# Apply the finish at the hook that creates each independent paint override,
	# on initial construction as well as every later customization rebuild.
	super._configure_blackjack_semantic_surface(mesh,surface,lower_name)
	if not _enabled():
		return
	var source := mesh.mesh.surface_get_material(surface)
	if source==null or not source.resource_name.begins_with("Paint_"):
		return
	var coating := mesh.get_surface_override_material(surface) as StandardMaterial3D
	if coating!=null:
		coating.metallic=.58
		coating.roughness=.24
		coating.clearcoat_enabled=true
		coating.clearcoat=.85
		coating.clearcoat_roughness=.12


func _rebuild_visuals() -> void:
	super._rebuild_visuals()
	if _enabled():
		for spec in _decal_specs:
			_create_decal(spec)


func _create_decal(spec: Dictionary) -> Decal:
	var decal := Decal.new()
	decal.name="ProtectedLiveryDecal"
	decal.texture_albedo=spec["texture"]
	decal.transform=spec["placement"]
	decal.size=spec["size"]
	decal.cull_mask=2
	_visual_root.add_child(decal)
	return decal


func add_livery_decal(texture: Texture2D,placement: Transform3D,size: Vector3) -> Decal:
	var spec := {"texture":texture,"placement":placement,"size":size}
	_decal_specs.append(spec)
	return _create_decal(spec)


func clear_livery_decals() -> void:
	_decal_specs.clear()
	for node in _visual_root.get_children():
		if node is Decal:
			node.free()
