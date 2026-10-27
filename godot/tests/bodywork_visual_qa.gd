## Rendered QA for bodywork wear. Each car is staged clean / scuffed / heavy under one
## fixed camera and light, from a three-quarter and a side view, and the saved frames are
## compared numerically so the difference is asserted, not just eyeballed.
## PNGs go to .ai/captures/bodywork.
extends Node3D

const CARS: Array[String] = ["blackjack", "deadbolt"]
const STAGES: Array = [["clean", 0.0], ["scuffed", 0.35], ["heavy", 0.8]]
const VIEWS: Array = [
	["three-quarter", Vector3(-4.6, 2.0, 4.6)],
	["side", Vector3(0.0, 1.4, 6.4)],
]
const CHANNEL_DELTA := 0.04
const MIN_CHANGED_FRACTION := 0.004

var _pass := 0
var _fail := 0
var _output := ProjectSettings.globalize_path("res://../.ai/captures/bodywork")
var _camera: Camera3D
var _car: Vehicle


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("BODYWORK_QA: skipped, needs a rendering display")
		get_tree().quit(0)
		return
	get_window().size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(_output)
	_build_studio()
	for id: String in CARS:
		await _stage_car(id)
	print("BODYWORK_QA: %d passed, %d failed" % [_pass, _fail])
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
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("5a6066")
	floor_material.roughness = 0.9
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.6
	add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	add_child(_camera)
	_camera.current = true


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Fraction of pixels whose colour moved by more than CHANNEL_DELTA on any channel.
func _changed_fraction(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var changed := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) > CHANNEL_DELTA or absf(ca.g - cb.g) > CHANNEL_DELTA or absf(ca.b - cb.b) > CHANNEL_DELTA:
				changed += 1
	return float(changed) / float((a.get_width() / 2) * (a.get_height() / 2))


func _stage_car(id: String) -> void:
	_car = preload("res://scripts/vehicle_factory.gd").create(VehicleCatalog.get_vehicle(id))
	_car.freeze = true
	_car.position = Vector3(0.0, 0.85, 0.0)
	add_child(_car)
	await get_tree().process_frame
	var body := _car.get_node("VehicleBodywork") as VehicleBodywork
	var shots := {}
	for view: Array in VIEWS:
		_camera.global_position = _car.global_position + (view[1] as Vector3)
		_camera.look_at(_car.global_position + Vector3(0.0, 0.5, 0.0))
		for stage: Array in STAGES:
			_car.reset_effects_state()
			if float(stage[1]) > 0.0:
				_car.apply_cosmetic_damage(float(stage[1]))
			await get_tree().process_frame
			var image := await _grab()
			var label := "%s-%s-%s" % [id, view[0], stage[0]]
			_check(label + " saves", image.save_png(_output.path_join(label + ".png")) == OK)
			shots[label] = image
		var base := "%s-%s-" % [id, view[0]]
		var scuffed := _changed_fraction(shots[base + "clean"], shots[base + "scuffed"])
		var heavy := _changed_fraction(shots[base + "scuffed"], shots[base + "heavy"])
		print("BODYWORK_QA: %s%s clean->scuffed %.3f scuffed->heavy %.3f" % [base, "diff", scuffed, heavy])
		_check(base + "scuffed visibly differs from clean", scuffed >= MIN_CHANGED_FRACTION)
		_check(base + "heavy visibly differs from scuffed", heavy >= MIN_CHANGED_FRACTION)
	# Back to clean must reproduce the clean frame exactly.
	_car.reset_effects_state()
	await get_tree().process_frame
	var again := await _grab()
	var clean_again := _changed_fraction(shots["%s-side-clean" % id], again)
	_check(id + " clean is restored after wear", clean_again < 0.0005 and not body.is_attached())
	remove_child(_car)
	_car.free()
	_car = null
