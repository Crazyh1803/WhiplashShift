## Rendered QA for VehicleEffects. Frozen production car, synthetic wheel contact: tyre smoke and
## skids, boost plume on each end, damage smoke, swap pulse both ways, and real viscera spray.
## Smoke silhouettes and alpha borders are judged by eye in the saved PNGs.
## Pass `-- --capture` to write PNGs to .ai/captures/vehicle-effects.
extends Node3D

const DT := 1.0 / 60.0

var _pass := 0
var _fail := 0
var _capture := "--capture" in OS.get_cmdline_user_args()
var _output := ProjectSettings.globalize_path("res://../.ai/captures/vehicle-effects")
var _camera: Camera3D
var _car: Vehicle
var _fx: VehicleEffects
var _floor: MeshInstance3D


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("VEHICLE_EFFECTS_QA: skipped, needs a rendering display")
		get_tree().quit(0)
		return
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(_output)
	_build_studio()
	_car = preload("res://scripts/vehicle_factory.gd").create(VehicleCatalog.get_vehicle("blackjack"))
	_car.freeze = true
	_car.position = Vector3(0.0, 0.85, 0.0)
	add_child(_car)
	await get_tree().process_frame
	_fx = _car.get_node("VehicleEffects")
	_fx.set_physics_process(false)
	_car.get_node("VisceraResponse").set_process(false)
	await _skid_and_smoke()
	await _boost()
	await _damage()
	await _swap()
	await _spray()
	print("VEHICLE_EFFECTS_QA: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", label)


func _build_studio() -> void:
	var environment := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = Color("3b434a")
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color("dfe8f0")
	world.ambient_light_energy = 1.0
	environment.environment = world
	add_child(environment)
	_floor = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	_floor.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("5a6066")
	material.roughness = 0.9
	_floor.material_override = material
	add_child(_floor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.6
	add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	_camera.current = true


func _ground(sid: int, slip: float = 1.0, spin: float = 0.0) -> void:
	for wheel: Wheel in _car.wheels:
		wheel.contact = true
		wheel.contact_point = _car.global_transform * (wheel.position - Vector3(0, 0.6, 0))
		wheel.contact_point.y = 0.0
		wheel.contact_normal = Vector3.UP
		wheel.surface_id = sid
		wheel.normal_load = 3400.0
		wheel.slip = slip
		wheel.spin = spin


func _view(offset: Vector3, look: Vector3 = Vector3(0, 0.8, 0)) -> void:
	_camera.global_position = _car.global_position + offset
	_camera.look_at(_car.global_position + look)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	if _capture:
		var image := get_viewport().get_texture().get_image()
		_check(name + " screenshot saves", image.save_png(_output.path_join(name + ".png")) == OK)


func _reset_car(end: String = "A") -> void:
	_car.active_end = end
	_car.rotation = Vector3.ZERO
	_car.position = Vector3(0.0, 0.85, 0.0)
	_fx.state_override = {}
	_fx.reset()


## Runs frames of effects, moving the frozen car along its active end's forward axis.
func _drive(frames: int, speed: float, side: float, sid: int, slip: float, spin: float, shots: Array, prefix: String) -> void:
	var forward := -1.0 if _car.active_end == "A" else 1.0
	for frame in frames:
		_car.global_position += Vector3(side, 0, forward * speed) * DT
		_ground(sid, slip, spin)
		_fx.advance(DT, true, {"lin_vel": Vector3(side, 0, forward * speed)})
		_view(Vector3(-6.0, 3.0, 6.0 * -forward))
		await get_tree().process_frame
		if frame in shots:
			await _shot("%s-%02d" % [prefix, frame])


func _skid_and_smoke() -> void:
	_reset_car()
	await _drive(90, 14.0, 5.0, Surfaces.Id.TARMAC, 1.0, 0.0, [45, 89], "tyre-skid")
	_check("sliding on tarmac lays strips and smoke", _fx.skid_count() > 0 and _fx.particle_counts().tyre > 0)


func _boost() -> void:
	for end: String in ["A", "B"]:
		_reset_car(end)
		_fx.state_override = {"boost_time": 0.9}
		await _drive(45, 22.0, 0.0, Surfaces.Id.TARMAC, 0.2, 0.0, [30], "boost-end-" + end)
		_check("boost plume on End " + end, _fx.particle_counts().plume > 10)


func _damage() -> void:
	_reset_car()
	_fx.state_override = {"damage": 0.9}
	await _drive(90, 6.0, 0.0, Surfaces.Id.TARMAC, 0.2, 0.0, [60], "damage-smoke")
	_check("damage smoke renders", _fx.particle_counts().damage > 10)


func _swap() -> void:
	for end: String in ["B", "A"]:
		_reset_car("A" if end == "B" else "B")
		await get_tree().process_frame
		_car.active_end = end
		_car.swapped.emit({"end": end, "reason": "qa"})
		_check("swap pulse shows for End " + end, _fx.pulse_visible())
		for frame in 12:
			_fx.advance(DT, true, {})
			_view(Vector3(-5.0, 3.0, 6.0))
			await get_tree().process_frame
		await _shot("swap-to-" + end)


func _spray() -> void:
	_reset_car()
	_car.get_node("VisceraResponse").set_process(false)
	var response := _car.get_node("VisceraResponse") as VisceraResponse
	var before := response.emitted_total
	var smoke_before := _fx.tyre_smoke_emitted
	for frame in 90:
		_car.global_position += Vector3(0, 0, -10.0 * DT)
		_ground(Surfaces.Id.MUD, 0.6, 0.4)
		response.advance(DT, _car.wheels, "A", Vector3(0, 0, -10), 0.8, _car.global_basis)
		_fx.advance(DT, true, {"lin_vel": Vector3(0, 0, -10)})
		_view(Vector3(-6.0, 3.0, 6.0))
		await get_tree().process_frame
		if frame == 60:
			await _shot("viscera-spray")
	_check("existing viscera spray still emits", response.emitted_total > before and response.active_count > 0)
	_check("effects add no tyre smoke on soft terrain", _fx.tyre_smoke_emitted == smoke_before)
