extends "res://tests/blackjack_refined_visual_qa.gd"


func _ready() -> void:
	_build_studio()
	var qa_environment := find_children("*","WorldEnvironment",false,false)[0] as WorldEnvironment
	qa_environment.environment=preload("res://scripts/blackjack_studio_finish.gd").environment(Color("55616b"))
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20,.1,20)
	collision.shape = shape
	collision.position.y = -.05
	ground.add_child(collision)
	add_child(ground)
	var vehicle := preload("res://tests/blackjack_blueprint_preview_vehicle.gd").new()
	vehicle.tuning = TuningProfile.new()
	var spec := preload("res://tests/blackjack_blueprint_fixture.gd").spec()
	var paint: Dictionary = spec["customization"]
	paint["primary_color"] = "929ba3"
	paint["secondary_color"] = "42574d"
	paint["accent_color"] = "596269"
	vehicle.apply_vehicle_spec(spec)
	vehicle.position.y = .85
	add_child(vehicle)
	for i in range(180):
		await get_tree().physics_frame
	vehicle.freeze = true
	for wheel in vehicle.visual_wheels:
		print("BLUEPRINT_CONTACT ",wheel.name," clearance=",wheel.get_node("ModularWheelVisual").global_position.y-vehicle.DISPLAY_RADIUS[wheel.end])
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.7
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_side.png",Vector3(7,.8,0),Vector3(0,.8,0))
	camera.size = 4.2
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_three_quarter.png",Vector3(5,3.1,-5.2),Vector3(0,.9,0))
	camera.size=2.2
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_guard_front.png",Vector3(0,1.1,6),Vector3(0,1.1,1.65))
	camera.size=4.2
	var showcase:=paint.duplicate(true)
	showcase["primary_color"]="2558a4"
	showcase["secondary_color"]="101820"
	showcase["accent_color"]="c5a468"
	vehicle.apply_customization(showcase)
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_metallic_showcase.png",Vector3(5,3.1,-5.2),Vector3(0,.9,0))
	var red_finish:=showcase.duplicate(true)
	red_finish["primary_color"]="b51f32"
	red_finish["secondary_color"]="303943"
	red_finish["accent_color"]="9ca6ad"
	vehicle.apply_customization(red_finish)
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_metallic_red.png",Vector3(5,3.1,-5.2),Vector3(0,.9,0))
	vehicle.apply_customization(paint)
	camera.size=1.3
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_door_detail.png",Vector3(4,1.18,1.28),Vector3(0,1.18,1.28))
	camera.size=1.4
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_hood_detail.png",Vector3(2.8,2.1,-3.3),Vector3(0,.85,-1.85))
	camera.size=4.2
	var neutral := paint.duplicate(true)
	paint["primary_color"]="ce3849"
	paint["secondary_color"]="3a9857"
	paint["accent_color"]="3c61d6"
	vehicle.apply_customization(paint)
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	for x in range(64):
		for y in range(64):
			image.set_pixel(x,y,Color.WHITE if (int(x/8)+int(y/8))%2==0 else Color("25384c"))
	var placement := Transform3D(Basis(Vector3.FORWARD,PI/2),Vector3(.72,-.02,-.85))
	vehicle.add_livery_decal(ImageTexture.create_from_image(image),placement,Vector3(.6,.45,1.2))
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_paint_qa.png",Vector3(5,3.1,-5.2),Vector3(0,.9,0))
	vehicle.clear_livery_decals()
	var monochrome := neutral.duplicate(true)
	for channel: String in ["primary_color","secondary_color","accent_color"]:
		monochrome[channel]="df512a"
	vehicle.apply_customization(monochrome)
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_paint_coverage.png",Vector3(5,3.1,-5.2),Vector3(0,.9,0))
	neutral["parts"]["hood_engine"]="supercharger"
	vehicle.apply_customization(neutral)
	await _capture("res://assets/vehicles/models/blackjack/blackjack_blueprint_godot_engine_qa.png",Vector3(5,3.1,-5.2),Vector3(0,.9,0))
	neutral["parts"]["hood_engine"]="stock"
	vehicle.apply_customization(neutral)
	# Capture the actual disabled garage preview, not a physics-settled surrogate.
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	garage._preview_viewport.own_world_3d=true
	garage._customization_popup.popup_centered(Vector2i(920,850))
	garage._refresh_customization_preview("blackjack",neutral)
	var preview_camera: Camera3D = garage._preview_camera
	preview_camera.current=true
	preview_camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	preview_camera.size=3.7
	preview_camera.look_at_from_position(Vector3(7,.8,0),Vector3(0,.8,0))
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var garage_image: Image = garage._preview_viewport.get_texture().get_image()
	var visible_samples := 0
	for x in range(0,garage_image.get_width(),8):
		for y in range(0,garage_image.get_height(),8):
			if garage_image.get_pixel(x,y).get_luminance()>.15:
				visible_samples+=1
	if visible_samples<100:
		push_error("Garage QA capture contains no visible vehicle")
		get_tree().quit(1)
		return
	garage_image.save_png("res://assets/vehicles/models/blackjack/blackjack_blueprint_garage_side.png")
	preview_camera.size=4.2
	preview_camera.look_at_from_position(Vector3(5,3.1,-5.2),Vector3(0,.9,0))
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	garage._preview_viewport.get_texture().get_image().save_png("res://assets/vehicles/models/blackjack/blackjack_blueprint_garage_three_quarter.png")
	# UI evidence without choosing/saving a different user profile color.
	garage._customization_loading=true
	for pair: Array in [[garage._primary_picker,"primary_color"],[garage._secondary_picker,"secondary_color"],[garage._accent_picker,"accent_color"]]:
		pair[0].limit_to_palette(true)
		pair[0].color=Color(showcase[pair[1]])
	garage._refresh_customization_preview("blackjack",showcase)
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	garage._customization_popup.get_viewport().get_texture().get_image().save_png("res://assets/vehicles/models/blackjack/blackjack_blueprint_garage_metallic_ui.png")
	garage.free()
	if not "--inspect" in OS.get_cmdline_user_args():
		get_tree().quit()
