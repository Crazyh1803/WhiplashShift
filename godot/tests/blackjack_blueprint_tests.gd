extends Node3D

const ART := preload("res://tests/blackjack_blueprint_preview_vehicle.gd")
const SPEC := preload("res://tests/blackjack_blueprint_fixture.gd")
const SEMANTICS := ["Paint_Primary","Paint_Secondary","Paint_Accent","Glass","Mirror","Rubber","Grille","Lights","Gunmetal","BrushedMetal","ArmorProtected"]
var passed := 0
var failed := 0


func _ready() -> void:
	_palette_checks()
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
	for root: Node in [model,low]:
		var trim_count:=0
		for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
			if mesh.name.begins_with("Glass_TruckFrontSeal") or mesh.name.begins_with("Glass_CoupeWindshieldSeal"):
				trim_count+=1
				_check("windshield seals retain complete profile",_mesh_triangles(mesh)==64)
			elif mesh.name.begins_with("Wiper_Truck"):
				trim_count+=1
				_check("wiper profiles never collapse over glass",_mesh_triangles(mesh)==28)
		_check("complete preserved windshield trim assembly",trim_count==5)
	low.free()
	var names := {}
	var fastener_count := 0
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if mesh.name.begins_with("Rivet_"):
			fastener_count+=1
			_check("gameplay preserves fastener topology",_mesh_triangles(mesh)>=28)
		for i in range(mesh.mesh.get_surface_count()):
			var mat := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			_check("known semantic material",mat!=null and SEMANTICS.has(mat.resource_name))
			if mat!=null:
				names[mat.resource_name]=true
				if mat.resource_name.begins_with("Paint_"):
					_check("initial build has complete automotive coating",_has_automotive_coating(mesh.get_surface_override_material(i) as StandardMaterial3D))
				_check("decal layers protect non-paint",(mesh.layers & 2)!=0 if mat.resource_name.begins_with("Paint_") else (mesh.layers & 2)==0)
			var arrays := mesh.mesh.surface_get_arrays(i)
			_check("UVs on every surface",(arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size()==(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	for name: String in SEMANTICS:
		_check("all material slots: "+name,names.has(name))
	_check("blueprint perimeter fasteners present",fastener_count>=90)
	_check("four seated door handles",model.find_children("Detail_HandleBridge*","MeshInstance3D",true,false).size()==4)
	_check("four protected lamp bezels",model.find_children("Detail_LampBezel*","MeshInstance3D",true,false).size()==4)
	_check("three preserved guard rails",model.find_children("Detail_BrushGuardRail*","MeshInstance3D",true,false).size()==3)
	_check("two guard uprights and seated mounts",model.find_children("Detail_BrushGuardUpright*","MeshInstance3D",true,false).size()==2 and model.find_children("Detail_BrushGuardSeat*","MeshInstance3D",true,false).size()==2)
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
				_check("automotive paint retains color and clearcoat",_has_automotive_coating(override))
				_check("no primer texture or whole-mesh override masks paint",override!=null and override.albedo_texture==null and mesh.material_override==null)
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
		elif id == "deadbolt":
			_check("Deadbolt uses its own saved-art adapter", preview.get_script() == preload("res://scripts/deadbolt_blueprint_vehicle.gd"))
		elif id == "nightshift":
			_check("Nightshift uses its own saved-art adapter", preview.get_script() == preload("res://scripts/nightshift_blueprint_vehicle.gd"))
		elif id == "ramjet":
			_check("Ramjet uses its own saved-art adapter", preview.get_script() == preload("res://scripts/ramjet_blueprint_vehicle.gd"))
		else:
			_check("other vehicles have no blueprint overrides",preview.get_script()==Vehicle)
		preview.free()
	# Exercise the real garage hook, including replacing the disabled preview
	# when switching away from Blackjack and back; never write profile data.
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	for id: String in ["blackjack","boilerfang","blackjack"]:
		for index in range(VehicleCatalog.VEHICLES.size()):
			if VehicleCatalog.VEHICLES[index]["id"]==id:
				garage._index=index
		garage._load_customization_controls()
		_check("real garage gates preset controls by vehicle",garage._primary_picker.preset.visible==(id=="blackjack") and garage._primary_picker.unrestricted.visible==(id!="blackjack"))
		garage._refresh_customization_preview(id,VehicleCatalog.default_customization(id))
		var environment: Environment=garage._preview_environment.environment
		_check("studio reflections are Blackjack-only",environment.sky!=null if id=="blackjack" else environment.sky==null and environment.ambient_light_source==Environment.AMBIENT_SOURCE_COLOR and is_equal_approx(environment.ambient_light_energy,.72))
		var preview: Vehicle = garage._preview_vehicle
		_check("real garage retains frozen preview",preview.freeze and preview.process_mode==Node.PROCESS_MODE_DISABLED)
		_check("real garage selects production art rig",preview.get_script()==load("res://scripts/blackjack_blueprint_vehicle.gd") if id=="blackjack" else preview.get_script()==Vehicle)
		if id=="blackjack":
			for wheel: Wheel in preview.visual_wheels:
				var assembly := wheel.get_node("ModularWheelVisual") as Node3D
				var center: Vector3 = preview._visual_config["arch_centers"][preview._arch_key(wheel)]
				_check("real garage aligns arches",preview.to_local(assembly.global_position).distance_to(center)<.0001)
				_check("real garage seats tires",absf(assembly.global_position.y-ART.DISPLAY_RADIUS[wheel.end])<.002)
	var saved_cache: Dictionary=GameSession.vehicle_customizations.duplicate(true)
	var legacy: Dictionary=GameSession.customization_for("blackjack")
	legacy["primary_color"]="123456"
	legacy["secondary_color"]="101820" # Ensure the loading test actually emits a change.
	GameSession.vehicle_customizations["blackjack"]=legacy
	garage._index=0
	garage._load_customization_controls()
	garage._customization_loading=true # Prevent the UI signal from saving profile data.
	var loading_cache: Dictionary=GameSession.vehicle_customizations.duplicate(true)
	garage._secondary_picker.choose_palette(2)
	_check("loading swatch cannot commit customization",GameSession.vehicle_customizations==loading_cache)
	_check("changing another channel retains saved custom primary",garage._primary_picker.color.to_html(false)=="123456")
	legacy["secondary_color"]=garage._secondary_picker.color.to_html(false)
	GameSession.vehicle_customizations["blackjack"]=GameSession._sanitize_customization("blackjack",legacy)
	garage._load_customization_controls()
	_check("legacy primary survives serialization and reload",garage._primary_picker.color.to_html(false)=="123456")
	GameSession.vehicle_customizations=saved_cache
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


func _palette_checks() -> void:
	var palette:=preload("res://scripts/blackjack_paint_palette.gd")
	var factory:=VehicleCatalog.default_customization("blackjack")
	for channel: String in ["primary_color","secondary_color","accent_color"]:
		_check("factory paint belongs to metallic palette",palette.label_for(Color(factory[channel]))!="SAVED CUSTOM")
	var picker:=preload("res://scripts/vehicle_paint_picker.gd").new()
	var names: Dictionary={}
	var colors: Dictionary={}
	_check("exactly twelve metallic swatches",palette.SWATCHES.size()==12 and picker.preset.get_popup().item_count==12)
	for i in range(palette.SWATCHES.size()):
		var swatch: Dictionary=palette.SWATCHES[i]
		names[swatch["name"]]=true
		colors[swatch["hex"]]=true
		picker.choose_palette(i)
		_check("swatch selects exact saved hex",picker.color.to_html(false)==swatch["hex"])
	_check("palette colors and names are unique",names.size()==12 and colors.size()==12)
	picker.color=Color("123456")
	picker.limit_to_palette(true)
	_check("legacy color is not quantized on load",picker.color.to_html(false)=="123456" and picker.preset.text=="SAVED CUSTOM")
	_check("Blackjack only exposes twelve presets",picker.preset.visible and not picker.unrestricted.visible)
	picker.limit_to_palette(false)
	_check("other vehicles retain unrestricted picker",picker.unrestricted.visible and not picker.preset.visible and picker.color.to_html(false)=="123456")
	picker.choose_palette(-1)
	_check("invalid palette selection preserves color",picker.color.to_html(false)=="123456")
	var emissions: Array[Color]=[]
	picker.color_changed.connect(func(value: Color) -> void: emissions.append(value))
	picker.choose_palette(0)
	picker.choose_palette(0)
	_check("reselecting current finish avoids another save signal",emissions.size()==1)
	picker.free()
	var studio:=preload("res://scripts/blackjack_studio_finish.gd")
	var first:=studio.environment(Color.BLACK)
	var second:=studio.environment(Color.WHITE)
	_check("independent studio environments with shared reflection sky",first!=second and first.sky==second.sky and first.reflected_light_source==Environment.REFLECTION_SOURCE_SKY)
	_check("neutral HDR sky retains bright softboxes",((first.sky.sky_material as PanoramaSkyMaterial).panorama as ImageTexture).get_image().get_pixel(61,21).r>1)


func _has_automotive_coating(material: StandardMaterial3D) -> bool:
	return material!=null and is_equal_approx(material.metallic,.58) and is_equal_approx(material.roughness,.24) and material.clearcoat_enabled and is_equal_approx(material.clearcoat,.85) and is_equal_approx(material.clearcoat_roughness,.12)


func _mesh_triangles(mesh: MeshInstance3D) -> int:
	var result := 0
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		result+=int((indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())/3.0)
	return result


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
