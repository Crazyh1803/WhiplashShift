## Rendered QA for the tyre-mark and smoke-screen feedback. Real proving ground, the track's own dark
## environment and the real chase camera: no studio, no added lights. A real handbrake manoeuvre lays
## smoke and marks; the marks are then aged (emission frozen, never reset) until they are gone; a real
## smoke deployment is watched after the owner stops emitting, from the owner chase view and a rival's.
## Saved effect regions require manual inspection; the blank-frame check only validates rendering.
## Pass `-- --capture` to write PNGs to .ai/captures/vehicle-feedback.
extends Node3D

const DT := 1.0 / 60.0

var _pass := 0
var _fail := 0
var _capture := "--capture" in OS.get_cmdline_user_args()
var _output := ProjectSettings.globalize_path("res://../.ai/captures/vehicle-feedback")
var _helpers: GDScript
var _scene: Node3D
var _car: Vehicle
var _fx: VehicleEffects
var _observer: Camera3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("VEHICLE_FEEDBACK_QA: skipped, needs a rendering display")
		get_tree().quit(0)
		return
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(_output)
	_helpers = ResourceLoader.load("res://tests/vehicle_feedback_tests.gd", "GDScript")
	GameSession.configure("VEHICLE FEEDBACK QA", "blackjack", ["ramjet", "boilerfang"])
	_scene = ResourceLoader.load("res://scenes/proving_ground.tscn").instantiate()
	add_child(_scene)
	await get_tree().physics_frame
	_helpers.call("prepare_track", _scene)
	_car = _scene.car
	_fx = _car.get_node("VehicleEffects")
	_observer = Camera3D.new()
	_observer.fov = 60.0
	add_child(_observer)
	_check_environment()
	await _handbrake_and_marks()
	await _smoke_deployment()
	print("VEHICLE_FEEDBACK_QA: %d passed, %d failed" % [_pass, _fail])
	_scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)


func _check_environment() -> void:
	var worlds := _scene.find_children("*", "WorldEnvironment", true, false)
	var dark := false
	for node in worlds:
		var env := (node as WorldEnvironment).environment
		dark = dark or (env != null and env.background_mode == Environment.BG_COLOR and env.background_color.get_luminance() < 0.05
			and env.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED)
	_check("QA runs in the track's dark environment, not a studio", dark)
	var lights := get_children().filter(func(node: Node) -> bool: return node is Light3D or node is WorldEnvironment)
	_check("the QA scene adds no lights or environment of its own", lights.is_empty())
	_check("the player's real chase camera is the viewport camera", get_viewport().get_camera_3d() == _scene.rig.cam)


func _shot(name: String, frames := 3) -> void:
	for frame in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(name + " is not a blank frame", _brightest(image) > 0.06)
	if _capture:
		_check(name + " screenshot saves", image.save_png(_output.path_join(name + ".png")) == OK)


func _brightest(image: Image) -> float:
	var best := 0.0
	for y in range(0, image.get_height(), 6):
		for x in range(0, image.get_width(), 6):
			best = maxf(best, image.get_pixel(x, y).get_luminance())
	return best


func _use_chase() -> void:
	_scene.rig.cam.make_current()


func _use_observer(focus: Vector3, offset: Vector3) -> void:
	_observer.global_position = focus + offset
	_observer.look_at(focus)
	_observer.make_current()


# ------------------------------------------------------------------ handbrake, marks, fade
func _handbrake_and_marks() -> void:
	for frame in 90:
		await get_tree().physics_frame
	_fx.reset()
	var skid_start := _fx.skid_emitted
	var smoke_start := _fx.tyre_smoke_emitted
	_car.linear_velocity = _car.forward_vector().normalized() * 20.0
	_car.throttle = 1.0
	_car.handbrake = true
	_car.steer = 0.6
	for frame in 60:
		await get_tree().physics_frame
		if frame == 22:
			await _shot("handbrake-chase-smoke")
		elif frame == 50:
			await _shot("handbrake-chase-marks")
	_check("real handbrake manoeuvre emitted smoke", _fx.tyre_smoke_emitted > smoke_start)
	_check("real handbrake manoeuvre laid marks", _fx.skid_emitted > skid_start and _fx.skid_count() > 0)
	# Stop emission by freezing the body; marks must keep ageing and must not be reset.
	_car.throttle = 0.0
	_car.handbrake = false
	_car.steer = 0.0
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO
	_car.freeze = true
	_fx.set_physics_process(false)
	var emitted := _fx.skid_emitted
	var segments := _fx.skid_segments()
	if segments.is_empty():
		_check("fade QA requires real emitted strips", false)
		return
	var slot: int = segments[0]["slot"]
	var birth: float = segments[0]["birth"]
	var fresh_alpha := _slot_alpha(slot)
	await _shot("marks-fresh")
	var peak_alpha := fresh_alpha
	for stage: Array in [["marks-fading", 8.0], ["marks-nearly-gone", 11.5]]:
		_age_to(birth + float(stage[1]))
		await _shot(stage[0])
		var alpha := _slot_alpha(slot)
		_check("%s: the oldest mark is fainter than before" % stage[0], alpha < peak_alpha - 0.05 and alpha >= 0.0)
		peak_alpha = alpha
	_check("freezing never emitted more marks or reset the strips", _fx.skid_emitted == emitted and _fx.skid_count() > 0)
	_age_to(birth + 12.2)
	_check("marks have expired from the oldest strip", _slot_alpha(slot) == 0.0 or _fx.skid_count() < segments.size())
	_age_to(birth + 14.0)
	_check("all marks are gone once the oldest outlives 12 s", _fx.skid_count() == 0 or _fx.skid_segments().all(func(s: Dictionary) -> bool: return _fx._time - float(s["birth"]) < 12.0))
	await _shot("marks-gone")


func _age_to(birth_plus: float) -> void:
	while _fx._time < birth_plus:
		_fx.advance(DT, false)


func _slot_alpha(slot: int) -> float:
	return (_fx.get_node("SkidStrips") as MultiMeshInstance3D).multimesh.get_instance_color(slot).a


# ------------------------------------------------------------------ smoke screen
func _smoke_deployment() -> void:
	_fx.reset()
	_car.freeze = false
	_scene._respawn()
	await get_tree().physics_frame
	for frame in 60:
		await get_tree().physics_frame
	var items: RaceItems = _scene.items
	_scene.race.state = RaceDirector.State.RACING
	items.reset()
	_scene.race.state = RaceDirector.State.RACING
	items.grant_item(0, "smoke")
	_car.throttle = 0.7
	_car.linear_velocity = _car.forward_vector().normalized() * 20.0
	_check("smoke deploys while driving", items.fire(0))
	for frame in 100:
		await get_tree().physics_frame
		items.tick(DT)
		if frame == 45:
			_car.steer = 0.15
		elif frame == 70:
			_car.steer = -0.15
	var deposits := items.hazards.filter(func(h: Dictionary) -> bool: return h["id"] == "smoke")
	_check("driving lays a trail of several smoke deposits", deposits.size() >= 3)
	# Stop emitting: the stream ends, existing deposits only age.
	items.remaining[0] = 0.0
	_car.throttle = 0.0
	_car.brake = 1.0
	items.tick(DT)
	_check("the owner's smoke stream has stopped", items.active[0].is_empty())
	var count_before := items.hazards.filter(func(h: Dictionary) -> bool: return h["id"] == "smoke").size()
	for frame in 40:
		await get_tree().physics_frame
		items.tick(DT)
	_check("no new deposits appear after emission stops", items.hazards.filter(func(h: Dictionary) -> bool: return h["id"] == "smoke").size() <= count_before)
	var centre := Vector3.ZERO
	for hazard: Dictionary in items.hazards:
		centre += Vector3(hazard["pos"])
	centre /= maxf(1.0, float(items.hazards.size()))
	var side := _car.global_transform.basis.x.normalized() * 14.0 + Vector3.UP * 5.0
	var stage := 0
	var late_spread := 0.0
	for tick in 24:
		items.tick(0.17)
		var smokes := items.hazards.filter(func(h: Dictionary) -> bool: return h["id"] == "smoke")
		if smokes.is_empty():
			break
		var life: float = smokes.map(func(h: Dictionary) -> float: return float(h["life"])).max()
		if stage == 0 and life <= 4.0 or stage == 1 and life <= 2.2 or stage == 2 and life <= 0.9:
			var label: String = ["smoke-fresh", "smoke-eroding", "smoke-thin"][stage]
			_use_chase()
			await _shot("%s-owner-chase" % label)
			_use_observer(centre + Vector3.UP * 1.5, side)
			await _shot("%s-rival-view" % label)
			_use_chase()
			if stage == 2:
				late_spread = _alpha_spread(smokes)
			stage += 1
	_check("the sequence reached its thin stage", stage == 3)
	_check("puff opacity erodes unevenly late in the life", late_spread > 0.03)
	for tick in 20:
		items.tick(0.25)
	_check("every deposit is gone after its five-second life", items.hazards.filter(func(h: Dictionary) -> bool: return h["id"] == "smoke").is_empty())


func _alpha_spread(smokes: Array) -> float:
	var low := 1.0
	var high := 0.0
	for hazard: Dictionary in smokes:
		for child in (hazard["visual"] as Node3D).get_children():
			var material := (child as MeshInstance3D).material_override as ShaderMaterial
			var alpha: float = (material.get_shader_parameter("tint") as Color).a
			low = minf(low, alpha)
			high = maxf(high, alpha)
	return high - low
