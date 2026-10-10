extends Node3D

const ART := preload("res://tests/blackjack_blueprint_preview_vehicle.gd")
const SPEC := preload("res://tests/blackjack_blueprint_fixture.gd")
const SEMANTICS := ["Paint_Primary","Paint_Secondary","Paint_Accent","Glass","Mirror","Rubber","Grille","Lights","Gunmetal","BrushedMetal","ArmorProtected"]
var passed := 0
var failed := 0


func _ready() -> void:
	var baseline := Vehicle.new()
	baseline.tuning = TuningProfile.new()
	baseline.freeze = true
	baseline.apply_vehicle_spec(VehicleCatalog.get_vehicle("blackjack"))
	add_child(baseline)
	var candidate := ART.new()
	candidate.tuning = TuningProfile.new()
	candidate.freeze = true
	candidate.apply_vehicle_spec(SPEC.spec())
	add_child(candidate)
	await get_tree().process_frame
	_check("only four physical wheels",candidate.wheels.size()==4)
	_check("unchanged mass and inertia",candidate.mass==baseline.mass and candidate.inertia==baseline.inertia)
	_check("unchanged collision boxes",_collisions(candidate)==_collisions(baseline))
	for i in range(4):
		_check("unchanged wheel radius/hardpoint",candidate.wheels[i].radius==baseline.wheels[i].radius and candidate.wheels[i].position==baseline.wheels[i].position)
	var model := candidate.get_node("VisualRoot/ProductionModel")
	var body_triangles := _triangles(model)
	var full_triangles := _triangles(candidate)
	_check("body allocation leaves room for six wheels",body_triangles>=15000 and body_triangles<=20000)
	_check("complete assembled budget",full_triangles>=20000 and full_triangles<=40000)
	var low := (load("res://assets/vehicles/models/blackjack/blackjack_blueprint_lod1.glb") as PackedScene).instantiate()
	_check("body LOD reduction",_triangles(low)<body_triangles*.60)
	low.free()
	var names := {}
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for i in range(mesh.mesh.get_surface_count()):
			var mat := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			_check("known semantic material",mat!=null and SEMANTICS.has(mat.resource_name))
			if mat!=null:
				names[mat.resource_name]=true
				_check("decal layers protect non-paint",(mesh.layers & 2)!=0 if mat.resource_name.begins_with("Paint_") else (mesh.layers & 2)==0)
			var arrays := mesh.mesh.surface_get_arrays(i)
			_check("UVs on every surface",(arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size()==(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	for name: String in SEMANTICS:
		_check("all material slots: "+name,names.has(name))
	var paint := VehicleCatalog.default_customization("blackjack")
	paint["primary_color"]="e32636"
	paint["secondary_color"]="25cf5c"
	paint["accent_color"]="375bea"
	paint["parts"]["hood_engine"]="stock"
	candidate.apply_customization(paint)
	var expected := {"Paint_Primary":Color("e32636"),"Paint_Secondary":Color("25cf5c"),"Paint_Accent":Color("375bea")}
	model = candidate.get_node("VisualRoot/ProductionModel")
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for i in range(mesh.mesh.get_surface_count()):
			var mat := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if mat==null:
				_check("material persists through paint",false)
				continue
			var override := mesh.get_surface_override_material(i) as StandardMaterial3D
			if expected.has(mat.resource_name):
				_check("paint channel isolated",override!=null and override.albedo_color.is_equal_approx(expected[mat.resource_name]))
			else:
				_check("protected surface untouched",override==null)
	for wheel: Wheel in candidate.visual_wheels:
		candidate._install_tire(wheel)
		candidate._install_tire(wheel)
		var assembly := wheel.get_node("ModularWheelVisual") as Node3D
		_check("idempotent authored tire",assembly.find_children("Tire_Blueprint*","",false,false).size()==1)
		var center: Vector3 = candidate._visual_config["arch_centers"][candidate._arch_key(wheel)]
		_check("no-tick refresh seats wheel in actual arch",candidate.to_local(assembly.global_position).distance_to(center)<.0001)
	var decal_image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	decal_image.fill(Color.WHITE)
	var decal := candidate.add_livery_decal(ImageTexture.create_from_image(decal_image),Transform3D.IDENTITY,Vector3.ONE)
	_check("real decal only targets paint layer",decal.cull_mask==2 and decal.texture_albedo!=null)
	candidate.clear_livery_decals()
	paint["parts"]["hood_engine"]="supercharger"
	candidate.apply_customization(paint)
	await get_tree().process_frame
	var engine_socket := candidate.get_part_socket("hood_engine")
	_check("optional supercharger installed",engine_socket!=null and engine_socket.get_child_count()==1)
	var lowest := INF
	for mesh: MeshInstance3D in engine_socket.find_children("*","MeshInstance3D",true,false):
		for vertex: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			lowest=minf(lowest,candidate.to_local(mesh.to_global(vertex)).y)
	# Calibrated mounting plane is the traced center hood at source pixel 696.
	_check("supercharger base seated on hood",absf(lowest-.110652)<.004)
	_check("budget includes optional supercharger",_triangles(candidate)<=40000)
	print("BLUEPRINT_OPTIONAL_ENGINE full triangles=",_triangles(candidate)," base=",lowest)
	paint["parts"]["hood_engine"]="stock"
	candidate.apply_customization(paint)
	await get_tree().process_frame
	await _garage_paths()
	await _physics_parity(baseline,candidate)
	print("BLACKJACK_BLUEPRINT_TESTS %d passed, %d failed; body %d; full %d" % [passed,failed,body_triangles,full_triangles])
	get_tree().quit(1 if failed else 0)


func _garage_paths() -> void:
	var factory := preload("res://scripts/vehicle_factory.gd")
	for catalog_spec: Dictionary in VehicleCatalog.VEHICLES:
		var id := String(catalog_spec["id"])
		var spec := SPEC.spec() if id=="blackjack" else VehicleCatalog.get_vehicle(id)
		var preview := factory.create(spec)
		preview.tuning=TuningProfile.new()
		preview.freeze=true
		preview.process_mode=Node.PROCESS_MODE_DISABLED
		preview.collision_layer=0
		preview.collision_mask=0
		if preview.has_method("configure_static_preview"):
			preview.configure_static_preview()
		add_child(preview)
		_check("factory preserves four-wheel model",preview.wheels.size()==4)
		if id=="blackjack":
			_check("frozen garage has all six support links",preview.supports.size()==6)
			for style: String in spec["visual"]["wheel_styles"]:
				var paint: Dictionary = spec["customization"].duplicate(true)
				paint["wheel_style"]=style
				preview.apply_customization(paint)
				_check("frozen wheel-style refresh preserves links",preview.supports.size()==6)
				for wheel: Wheel in preview.visual_wheels:
					var assembly := wheel.get_node("ModularWheelVisual") as Node3D
					_check("frozen wheel styles retain authored radius",is_equal_approx(assembly.scale.x,ART.DISPLAY_RADIUS[wheel.end]/wheel.radius))
					var center: Vector3 = preview._visual_config["arch_centers"][preview._arch_key(wheel)]
					_check("frozen styles remain centered in traced arches",preview.to_local(assembly.global_position).distance_to(center)<.0001)
					_check("frozen tires meet blueprint ground",absf(assembly.global_position.y-ART.DISPLAY_RADIUS[wheel.end])<.002)
			var image := Image.create(4,4,false,Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			preview.add_livery_decal(ImageTexture.create_from_image(image),Transform3D.IDENTITY,Vector3.ONE)
			preview.apply_customization(spec["customization"])
			_check("paint refresh retains decal",preview.get_node("VisualRoot").find_children("ProtectedLiveryDecal*","Decal",false,false).size()==1)
		else:
			_check("other vehicles have no blueprint overrides",preview.get_script()==Vehicle)
		preview.free()
	# Exercise the real garage hook, including replacing the disabled preview
	# when switching away from Blackjack and back; never write profile data.
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	for id: String in ["blackjack","boilerfang","blackjack"]:
		garage._refresh_customization_preview(id,VehicleCatalog.default_customization(id))
		var preview: Vehicle = garage._preview_vehicle
		_check("real garage retains frozen preview",preview.freeze and preview.process_mode==Node.PROCESS_MODE_DISABLED)
		_check("real garage selects production art rig",preview.get_script()==load("res://scripts/blackjack_blueprint_vehicle.gd") if id=="blackjack" else preview.get_script()==Vehicle)
		if id=="blackjack":
			for wheel: Wheel in preview.visual_wheels:
				var assembly := wheel.get_node("ModularWheelVisual") as Node3D
				var center: Vector3 = preview._visual_config["arch_centers"][preview._arch_key(wheel)]
				_check("real garage aligns arches",preview.to_local(assembly.global_position).distance_to(center)<.0001)
				_check("real garage seats tires",absf(assembly.global_position.y-ART.DISPLAY_RADIUS[wheel.end])<.002)
	garage.free()


func _physics_parity(baseline: Vehicle,candidate: Vehicle) -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(100,.1,100)
	collision.shape=box
	collision.position.y=-.05
	ground.add_child(collision)
	# Identical coordinates in independent worlds avoid translated raycast float
	# noise without relaxing the force-state assertions or allowing car collision.
	for vehicle: Vehicle in [baseline,candidate]:
		var world := SubViewport.new()
		world.own_world_3d = true
		add_child(world)
		world.add_child(ground.duplicate())
		vehicle.reparent(world)
		vehicle.position=Vector3(0,.85,0)
	ground.free()
	baseline.freeze=false
	candidate.freeze=false
	for i in range(180):
		await get_tree().physics_frame
	for wheel: Wheel in candidate.visual_wheels:
		var assembly := wheel.get_node("ModularWheelVisual") as Node3D
		_check("displayed tire contact within 5mm",absf(assembly.global_position.y-ART.DISPLAY_RADIUS[wheel.end])<.005)
	for end: String in ["A","B"]:
		var pair := candidate._wheel_pair(end)
		var mean: Vector3=(pair[0].get_node("ModularWheelVisual").global_position+pair[1].get_node("ModularWheelVisual").global_position)*.5
		_check("axle follows displayed centers",candidate._axle_visuals[end].global_position.distance_to(mean)<.001)
	var bogie := candidate.get_node("VisualMiddleBogie")
	var middle_y: float=(bogie.get_node("Bogie_L/ModularWheelVisual").global_position.y+bogie.get_node("Bogie_R/ModularWheelVisual").global_position.y)*.5
	_check("middle shaft is seated",absf(bogie.get_node("Shaft").global_position.y-middle_y)<.001)
	for frame in range(120):
		for vehicle: Vehicle in [baseline,candidate]:
			vehicle.throttle=.32 if frame<90 else 0
			vehicle.steer=.1 if frame>40 else 0
			vehicle.brake=.2 if frame>=90 else 0
			if frame==60:
				vehicle.swap_ends("blueprint_parity")
		await get_tree().physics_frame
		_check("art has identical body motion",baseline.position.distance_to(candidate.position)<.001 and baseline.basis.is_equal_approx(candidate.basis))
		_check("art has identical velocity",baseline.linear_velocity.distance_to(candidate.linear_velocity)<.001 and baseline.angular_velocity.distance_to(candidate.angular_velocity)<.001)
		for i in range(4):
			_check("art has identical wheel compression",absf(baseline.wheels[i].compression-candidate.wheels[i].compression)<.0001)
			_check("art has identical normal load",absf(baseline.wheels[i].normal_load-candidate.wheels[i].normal_load)<.001)
			_check("art has identical wheel contact",baseline.wheels[i].contact==candidate.wheels[i].contact)
	baseline.freeze=true
	candidate.freeze=true


func _triangles(root: Node) -> int:
	var count := 0
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			count+=int((indices.size() if not indices.is_empty() else vertices.size())/3.0)
	return count


func _collisions(vehicle: Vehicle) -> Array:
	var result := []
	for child: Node in vehicle.get_children():
		if child is CollisionShape3D:
			result.append([child.transform,(child.shape as BoxShape3D).size])
	return result


func _check(label: String,ok: bool) -> void:
	if ok:
		passed+=1
	else:
		failed+=1
		push_error("BLUEPRINT: "+label)
