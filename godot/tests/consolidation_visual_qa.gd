## Run with a display: captures the real garage and keyboard-driven race.
extends Node

var _output := ProjectSettings.globalize_path("res://").path_join("../.ai/captures")


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(_output)
	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	await _capture("garage_roster")
	print("QA_LAYOUT viewport=", get_viewport().get_visible_rect(), " garage=", garage.size,
		" last_vehicle=", garage._roster_buttons[-1].get_global_rect(),
		" next=", garage._next_button.get_global_rect(), " ignite=", garage._start_button.get_global_rect())
	garage._open_customization()
	await _capture("blackjack_garage")
	garage._customization_popup.hide()
	garage._select(5)
	await _capture("deadbolt_roster")
	garage._open_customization()
	await _capture("deadbolt_garage")
	garage.queue_free()
	await get_tree().process_frame
	GameSession.configure("ROADGHOST", "deadbolt", ["blackjack", "nightshift"])
	var race: Variant = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(race)
	for tick in 180:
		await get_tree().physics_frame
	await _capture("deadbolt_grid")
	# Use the long tarmac proving strip for repeatable keyboard driving without
	# needing a steering bot or depending on collisions with the CPU grid.
	race._spawn = Transform3D(Basis.IDENTITY, Vector3(-620, 1.4, 100))
	race._respawn()
	race.rig.global_position = race.car.global_position
	for tick in 180:
		await get_tree().physics_frame
	_key(KEY_W, true)
	for tick in 360:
		await get_tree().physics_frame
	_key(KEY_W, false)
	print("QA_DRIVE speed_kmh=", race.car.speed * 3.6)
	var driving_ok: bool = race.car.speed > 5.0
	await _capture("deadbolt_driving")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	for tick in 180:
		await get_tree().physics_frame
	print("QA_SWAP active_end=", race.car.active_end, " position_finite=", race.car.position.is_finite())
	await _capture("deadbolt_swapped")
	var swap_ok: bool = race.car.active_end == "B" and race.car.position.is_finite()
	race.queue_free()
	for frame in 3:
		await get_tree().process_frame
	get_tree().quit(0 if driving_ok and swap_ok else 1)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _capture(label: String) -> void:
	for frame in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := _output.path_join(label + ".png")
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("QA_CAPTURE ", label, " error=", error)
