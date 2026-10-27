## Rendered QA: saves 1280x720 combat HUD samples to .ai/captures/combat-hud.
## Run with a rendering display (not --headless).
extends Node

var _pass := 0
var _fail := 0
var scene: Node3D
var output := ProjectSettings.globalize_path("res://../.ai/captures/combat-hud")


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run combat_hud_visual_qa with a rendering display.")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(output)
	GameSession.configure("COMBAT HUD QA", "blackjack", ["ramjet", "boilerfang"])
	scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	scene.set_physics_process(false)
	scene.rig.set_process(false)
	for driver: CpuDriver in scene.cpu_drivers:
		driver.set_physics_process(false)
	var items: RaceItems = scene.items
	var car: Vehicle = scene.car
	scene.race.tick(3.0)
	scene.race.tick(1.0)
	var hud: Hud = scene.hud
	hud.set_process(false)
	var foe: Vehicle = items.cars[1]
	car.freeze = true
	foe.freeze = true

	hud._process(0.016)
	_check("empty hands state", hud.combat.weapon["state"] == "EMPTY")
	await _shot(hud, "empty-collect-hint")

	items.grant_item(0, "machine_guns")
	items._tick_mounts(0, 2.0)
	items.ammo[0] = 21
	items.fire_cooldown[0] = 0.15
	hud._process(0.016)
	_check("machine guns cooling state", hud.combat.weapon["state"] == "COOLING")
	await _shot(hud, "machine-guns-cooling")

	items.grant_item(0, "rockets")
	items._tick_mounts(0, 2.0)
	items.ammo[0] = 2
	items.fire_cooldown[0] = 0.0
	car.damage = 0.45
	var forward := -car.global_basis.z
	var side := car.global_basis.x
	var camera := get_viewport().get_camera_3d()
	for spot: Array in [[forward * 30.0, false], [side * 25.0, false], [-forward * 20.0, true], [-side * 25.0, false]]:
		foe.global_position = car.global_position + Vector3(spot[0])
		items.protection[0] = 0.0
		items.active[0] = "shield" if bool(spot[1]) else ""
		items._apply_hit(0, 1, "rockets")
	items.active[0] = "shield"
	items.remaining[0] = 3.2
	car.damage = 0.45
	hud._process(0.016)
	_check("camera present for screenshot", camera != null)
	_check("hits are staged as indicators", hud.combat.indicators.size() == 4)
	_check("active utility blocks fire as WAIT", hud.combat.weapon["state"] == "WAIT" and hud.combat.utility["id"] == "shield")
	await _shot(hud, "held-active-hits", "HAIRPIN RIGHT · IN 120m\nBRAKE BEFORE TURN · ADVISORY 70 KM/H")
	_check("corner advice is shown under the indicators", hud._upcoming.text.begins_with("HAIRPIN"))

	# Last round: record it held, then spend it so the readout reports the gun used up.
	items.ammo[0] = 1
	items.fire_cooldown[0] = 0.0
	hud._process(0.016)
	items.held[0] = ""
	items.ammo[0] = 0
	items.fire_cooldown[0] = 0.4
	items.remaining[0] = 0.6
	car.damage = 0.9
	hud._process(0.5)
	_check("spent weapon reads EXHAUSTED", hud.combat.weapon["state"] == "EXHAUSTED" and hud.combat.utility["expiring"])
	_check("wrecked bodywork wording", hud.combat.damage_label == "BODYWORK WRECKED")
	await _shot(hud, "exhausted-expiring-wrecked")

	scene.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("COMBAT HUD QA: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _shot(hud: Hud, label: String, advice := "") -> void:
	hud._process(0.0)
	if not advice.is_empty():
		hud._upcoming.text = advice
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
