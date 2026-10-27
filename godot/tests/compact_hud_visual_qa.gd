## Rendered QA: saves 1280x720 compact-dash captures to .ai/captures/compact-hud.
## Run with a rendering display (not --headless). Compares the band with and without the
## dashboard to prove scenery shows through, then stages a clustered named map and a busy
## combat/speed state.
extends Node

var _pass := 0
var _fail := 0
var output := ProjectSettings.globalize_path("res://../.ai/captures/compact-hud")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run compact_hud_visual_qa with a rendering display.")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(output)
	GameSession.configure("COMPACT QA", "blackjack", ["ramjet", "boilerfang"])
	var scene: Node3D = load("res://scenes/proving_ground.tscn").instantiate()
	scene.callsign_rng.seed = 2024
	add_child(scene)
	await get_tree().physics_frame
	scene.set_physics_process(false)
	scene.rig.set_process(false)
	var hud: Hud = scene.hud
	hud.set_process(false)
	hud.driving.set_process(false) # deterministic scanner pose
	var race: RaceDirector = scene.race
	var car: Vehicle = scene.car
	var items: RaceItems = scene.items
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
		driver.target.freeze = true
	car.freeze = true
	race.tick(3.0)
	race.tick(1.0)
	GameSession.speed_unit = "kmh"

	# Bright road under the band: with and without the dashboard.
	car.speed = 31.0
	hud._process(0.016)
	var with_dash := await _grab("clustered-map-grid")
	hud.driving.visible = false
	var without_dash := await _grab("no-dash-reference")
	hud.driving.visible = true
	var band: Rect2 = DashInstruments.layout(Vector2(1280, 720))["band"]
	var shown := _mean_luma(with_dash, band)
	var bare := _mean_luma(without_dash, band)
	_check("band region is darker than the bare road but still transmits it (%.2f vs %.2f)" % [shown, bare],
		shown < bare and shown > bare * 0.25)
	var diff := _mean_abs_diff(with_dash, without_dash, band)
	_check("translucent difference is visible but not total (%.3f)" % diff, diff > 0.01)
	_check("grid map shows three bounded, distinct names", hud.driving.labels.size() == 3)

	# Busy combat and speed.
	items.grant_item(0, "rockets")
	items._tick_mounts(0, 2.0)
	items.ammo[0] = 3
	items.active[0] = "shield"
	items.remaining[0] = 3.2
	car.damage = 0.4
	car.speed = 31.0
	var forward := -car.global_basis.z
	var foe: Vehicle = scene.cpu_cars[0]
	for offset: Vector3 in [forward * 30.0, car.global_basis.x * 25.0]:
		var saved := foe.global_position
		foe.global_position = car.global_position + offset
		items.protection[0] = 0.0
		items._apply_hit(0, 1, "rockets")
		foe.global_position = saved
	hud.driving.scanner_time = DrivingHud.SCAN_PERIOD * 0.37
	hud._process(0.016)
	hud._set_fitted(hud._upcoming, "HAIRPIN RIGHT · IN 120m\nBRAKE BEFORE TURN · ADVISORY 70 KM/H", 18)
	_check("busy state has ammo, a utility timer, hits and 112 km/h", hud.combat.weapon["ammo"] == 3 and hud.combat.utility["id"] == "shield"
		and not hud.combat.indicators.is_empty() and hud.driving.speed_value == 112)
	_check("no terrain forecast text staged", not hud._upcoming.text.contains("SAND") and not hud._upcoming.text.contains(" IN 40m"))
	await _grab("busy-combat-speed")

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("COMPACT HUD QA: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _grab(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(label + " is 1280x720", image.get_width() == 1280 and image.get_height() == 720)
	_check(label + " screenshot saves", image.save_png(output.path_join(label + ".png")) == OK)
	return image


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _mean_luma(image: Image, area: Rect2) -> float:
	var sum := 0.0
	var n := 0
	for y in range(int(area.position.y), int(area.end.y), 4):
		for x in range(int(area.position.x), int(area.end.x), 4):
			sum += _luma(image.get_pixel(x, y))
			n += 1
	return sum / maxf(float(n), 1.0)


func _mean_abs_diff(a: Image, b: Image, area: Rect2) -> float:
	var sum := 0.0
	var n := 0
	for y in range(int(area.position.y), int(area.end.y), 4):
		for x in range(int(area.position.x), int(area.end.x), 4):
			sum += absf(_luma(a.get_pixel(x, y)) - _luma(b.get_pixel(x, y)))
			n += 1
	return sum / maxf(float(n), 1.0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
