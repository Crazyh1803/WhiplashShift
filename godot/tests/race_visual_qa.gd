## Short rendered smoke test. Results use staged progress, not a physical race.
## The complete physical race and retry are covered by race_tests.tscn.
extends Node

var _output := ProjectSettings.globalize_path("res://").path_join("../.ai/captures/race-loop")
var _fail := 0
var _size := Vector2i(1600, 900)
var _scene: Node3D


func _ready() -> void:
	if "--small" in OS.get_cmdline_user_args():
		_size = Vector2i(1280, 720)
	# Let the window manager finish mapping the initial project window before
	# applying the requested capture size; an early resize can be overwritten.
	for frame in 3:
		await get_tree().process_frame
	get_window().size = _size
	DirAccess.make_dir_recursive_absolute(_output)
	GameSession.configure("ROADGHOST", "deadbolt", ["boilerfang", "ramjet"])
	_scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(_scene)
	await _capture("countdown")
	_check_layout("countdown")
	while _scene.race.state == RaceDirector.State.COUNTDOWN:
		await get_tree().physics_frame
	await _capture("go")
	_check_layout("go")
	var audio: VehicleAudio = _scene.vehicle_audio
	_check("rendered engine audio is streaming", audio._engine_player != null
		and audio._engine_player.playing and audio._engine_playback != null)
	var idle_frequency := audio._frequency
	_key(KEY_W, true)
	for frame in 240:
		await get_tree().physics_frame
	_key(KEY_W, false)
	_check("keyboard throttle moves the player", _scene.car.speed > 5.0)
	_check("engine pitch responds to acceleration", audio._frequency > idle_frequency)
	await _capture("driving")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await get_tree().process_frame
	_check("swap audio one-shot starts", audio._swap_player != null and audio._swap_player.playing)
	for frame in 60:
		await get_tree().physics_frame
	_check("keyboard swaps the active end", _scene.car.active_end == "B")
	await _capture("swap")
	_check_layout("swap")
	# Freeze motion while staging a player finish, leaving both rivals unfinished.
	_scene.set_physics_process(false)
	for driver: CpuDriver in _scene.cpu_drivers:
		driver.set_physics_process(false)
	for car: Vehicle in [_scene.car] + _scene.cpu_cars:
		car.freeze = true
	_scene.player_progress.lap = _scene.course.default_laps
	_scene.player_progress.route_distance = _scene.course.total_length * 4.0
	_scene._physics_process(0.01)
	await _capture("results")
	_check_layout("results")
	_check("results are visible", _scene.hud._results.visible)
	# Use the actual result button, then resume the production countdown.
	var retry: Button = _scene.hud._results.find_child("RetryButton", true, false)
	retry.pressed.emit()
	_scene.set_physics_process(true)
	for driver: CpuDriver in _scene.cpu_drivers:
		driver.set_physics_process(true)
	await _capture("retry")
	_check_layout("retry")
	_check("retry returns same vehicle to countdown", _scene.race.state == RaceDirector.State.COUNTDOWN
		and _scene.car.vehicle_id == "deadbolt" and not _scene.hud._results.visible)
	# Make the driving scene the current scene so its real garage action can
	# change scenes; this harness remains alive independently under the root.
	remove_child(_scene)
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	var menu: Button = _scene.hud.get_node("MainMenuButton")
	menu.pressed.emit()
	for frame in 6:
		await get_tree().process_frame
	await _capture("garage")
	_check("garage return retains vehicle and callsign", get_tree().current_scene.scene_file_path == "res://scenes/garage.tscn"
		and GameSession.selected_vehicle_id == "deadbolt" and GameSession.callsign == "ROADGHOST")
	print("RACE_VISUAL_QA failures=%d window=%s" % [_fail, _size])
	get_tree().quit(1 if _fail else 0)


func _check_layout(label: String) -> void:
	var hud: Hud = _scene.hud
	var viewport := get_viewport().get_visible_rect()
	if hud._results.visible:
		for control: Control in [hud._results_text, hud._results.find_child("RetryButton", true, false),
				hud._results.find_child("GarageButton", true, false)]:
			_check(label + " " + control.name + " fits viewport", viewport.encloses(control.get_global_rect()))
	else:
		for control: Control in [hud._main, hud._race_status, hud._banner, hud._cpu, hud._hint]:
			_check(label + " " + control.name + " fits viewport", viewport.encloses(control.get_global_rect()))
		if not hud._banner.text.is_empty():
			_check(label + " race clock and banner do not overlap",
				not hud._race_status.get_global_rect().intersects(hud._banner.get_global_rect()))


func _capture(label: String) -> void:
	for frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := _output.path_join("%dx%d_%s.png" % [_size.x, _size.y, label])
	var captured := get_viewport().get_texture().get_image()
	_check("capture dimensions " + label, captured.get_size() == _size)
	print("QA_SIZE window=", get_window().size, " viewport=", get_viewport().get_visible_rect(),
		" image=", captured.get_size())
	var result := captured.save_png(path)
	_check("capture " + label, result == OK)
	print("QA_CAPTURE ", path)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("QA_%s %s" % ["PASS" if ok else "FAIL", label])
