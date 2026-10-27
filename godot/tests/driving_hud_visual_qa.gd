## Rendered QA: saves 1280x720 driving HUD samples to .ai/captures/driving-hud.
## Run with a rendering display (not --headless). Uses a scratch settings file.
extends Node

const QA_SETTINGS := "user://driving_hud_qa_settings.cfg"

var _pass := 0
var _fail := 0
var _hud: Hud
var output := ProjectSettings.globalize_path("res://../.ai/captures/driving-hud")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run driving_hud_visual_qa with a rendering display.")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(output)
	var saved_path := GameSession.settings_path
	var saved_unit := GameSession.speed_unit
	GameSession.settings_path = QA_SETTINGS
	GameSession.speed_unit = "kmh"

	var garage: Variant = load("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	await get_tree().process_frame
	garage._settings_button.pressed.emit()
	garage._speed_unit_buttons["mph"].pressed.emit()
	_check("garage settings stage mph", GameSession.speed_unit == "mph" and garage._settings_popup.visible)
	await get_tree().process_frame
	await _shot("settings-dialog")
	garage.queue_free()
	await get_tree().process_frame

	GameSession.configure("DRIVING HUD QA", "blackjack", ["ramjet", "boilerfang"])
	var scene: Node3D = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	scene.set_physics_process(false)
	scene.rig.set_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
	var items: RaceItems = scene.items
	var car: Vehicle = scene.car
	var hud: Hud = scene.hud
	_hud = hud
	hud.set_process(false)
	var race: RaceDirector = scene.race
	var course: CourseDefinition = scene.course
	car.freeze = true
	var foes: Array[Vehicle] = []
	for driver: CpuDriver in scene.cpu_drivers:
		driver.target.freeze = true
		foes.append(driver.target)

	GameSession.speed_unit = "kmh"
	hud._process(0.016)
	_check("countdown shows readout and key racers", hud.driving.visible and hud.driving.markers.size() == 3)
	await _shot("countdown-grid")

	race.tick(3.0)
	race.tick(1.0)
	hud._process(0.0)
	_place(course, car, 0.62)
	_place(course, foes[0], 0.69)
	_place(course, foes[1], 0.55)
	car.speed = 31.0
	car.damage = 0.4
	items.grant_item(0, "rockets")
	items._tick_mounts(0, 2.0)
	items.ammo[0] = 3
	items.active[0] = "shield"
	items.remaining[0] = 3.2
	foes[0].speed = 27.0
	foes[1].speed = 24.0
	var forward := -car.global_basis.z
	for spot: Array in [[forward * 30.0, false], [car.global_basis.x * 25.0, false]]:
		var saved := foes[0].global_position
		foes[0].global_position = car.global_position + Vector3(spot[0])
		items.protection[0] = 0.0
		items._apply_hit(0, 1, "rockets")
		foes[0].global_position = saved
	hud._process(0.016)
	_check("busy racing readout", hud.driving.speed_value == 112 and hud.driving.markers.size() == 3)
	await _shot("racing-kmh", "SAND IN 40m\nLIFT OFF THROTTLE\nHAIRPIN RIGHT · IN 120m\nBRAKE BEFORE TURN · ADVISORY 70 KM/H")

	GameSession.speed_unit = "mph"
	car.reversing = true
	car.speed = 6.0
	_place(course, car, 0.2)
	_place(course, foes[0], 0.25)
	_place(course, foes[1], 0.2)
	hud._process(0.016)
	_check("mph reverse readout", hud.driving.unit == "mph" and hud.driving.reversing and "MPH" in hud._cpu.text)
	await _shot("racing-mph-reverse", "TURN · IN 90m\nBRAKE BEFORE TURN · ADVISORY 45 MPH")

	_hud = null
	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if FileAccess.file_exists(QA_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(QA_SETTINGS))
	GameSession.settings_path = saved_path
	GameSession.speed_unit = saved_unit
	print("DRIVING HUD QA: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


## Put a racer on the course centreline at `fraction` of the way round.
func _place(course: CourseDefinition, racer: Vehicle, fraction: float) -> void:
	var point: Dictionary = course.points[clampi(int(course.points.size() * fraction), 0, course.points.size() - 1)]
	var pos: Vector3 = point["pos"]
	racer.global_position = Vector3(pos.x, racer.global_position.y, pos.z)


func _shot(label: String, advice := "") -> void:
	if _hud != null:
		_hud.get_parent().rig.reset_follow()
		_hud._process(0.0)
		if not advice.is_empty():
			_hud._upcoming.text = advice
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(label + " is 1280x720", image.get_width() == 1280 and image.get_height() == 720)
	_check(label + " screenshot saves", image.save_png(output.path_join(label + ".png")) == OK)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
