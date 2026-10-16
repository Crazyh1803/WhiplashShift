## Driving scene: the greybox circuit, proving ground, player and CPU drivers.
##
## Controls are deliberately identical to the web prototype so muscle memory
## transfers and a side-by-side comparison is honest rather than a confound.
## Raw key checks rather than an InputMap: this is a spike, and it keeps the
## bindings visible in one place.
extends Node3D

const SPAWN_LIFT := 1.4
const VEHICLE_AUDIO_SCRIPT := preload("res://scripts/vehicle_audio.gd")

var car: Vehicle
var rig: CameraRig
var hud: Hud
var overlay: DebugOverlay
var vehicle_audio: Node
var course: CourseDefinition
var track: Array
var cpu_drivers: Array[CpuDriver] = []
var cpu_cars: Array[Vehicle] = []
var _spawn: Transform3D


func _ready() -> void:
	_build_world()
	_build_car()
	_build_cpu_drivers()
	_build_ui()


func _build_world() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(38.0), 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	# everything off the ribbon is "off track": soft, draggy, survivable
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.set_meta("surface_type", "off")
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(4000.0, 2.0, 4000.0)
	gs.shape = gb
	gs.position = Vector3(0.0, -1.0, 0.0)
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	var gbm := BoxMesh.new()
	gbm.size = gb.size
	gm.mesh = gbm
	gm.position = gs.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Surfaces.COLORS[Surfaces.Id.OFF]
	mat.roughness = 1.0
	gm.material_override = mat
	ground.add_child(gm)
	add_child(ground)

	course = TrackData.build_course()
	track = course.points
	TrackBuilder.build(self, track)
	TrackBuilder.build_guard_rails(self, track)
	TrackBuilder.build_proving_ground(self, Vector3(-620.0, 0.0, 0.0))


func _build_car() -> void:
	car = preload("res://scripts/vehicle_factory.gd").create(GameSession.selected_vehicle())
	car.name = "Car"
	var tune: Resource = load("res://resources/default_tuning.tres")
	car.tuning = tune as TuningProfile if tune else TuningProfile.new()
	add_child(car)

	_spawn = course.start_transform(SPAWN_LIFT)
	_respawn()

	vehicle_audio = VEHICLE_AUDIO_SCRIPT.new()
	vehicle_audio.name = "VehicleAudio"
	vehicle_audio.target = car
	add_child(vehicle_audio)


func _build_cpu_drivers() -> void:
	var roster: Array[String] = GameSession.cpu_vehicle_ids.duplicate()
	if roster.size() < 2:
		roster = VehicleCatalog.random_cpu_roster(2, GameSession.selected_vehicle_id)
	for i in 2:
		var spec := VehicleCatalog.get_vehicle(roster[i])
		var cpu := preload("res://scripts/vehicle_factory.gd").create(spec)
		cpu.name = "CPU_%d_%s" % [i + 1, String(spec["name"]).replace(" ", "_")]
		cpu.tuning = car.tuning
		add_child(cpu)
		var driver := CpuDriver.new()
		driver.name = "CpuDriver_%d" % (i + 1)
		driver.lane_offset = -4.0 if i == 0 else 4.0
		driver.skill = 0.72 if i == 0 else 0.80
		driver.setup(cpu, course, 4 + i * 5)
		add_child(driver)
		driver.reset(4 + i * 5)
		cpu_cars.append(cpu)
		cpu_drivers.append(driver)
	for driver: CpuDriver in cpu_drivers:
		driver.peers.assign([car] + cpu_cars)


func _build_ui() -> void:
	rig = CameraRig.new()
	rig.target = car
	add_child(rig)
	hud = Hud.new()
	hud.target = car
	hud.pilot_callsign = GameSession.callsign
	hud.cpu_drivers = cpu_drivers
	add_child(hud)
	hud.main_menu_requested.connect(_return_to_menu)
	overlay = DebugOverlay.new()
	overlay.target = car
	add_child(overlay)


func _respawn() -> void:
	car.active_end = "A"
	car.engage = 1.0
	car.cooldown = 0.0
	car.power_cut = 0.0
	car.steer_angle = 0.0
	car.last_whiplash = {}
	car.global_transform = _spawn
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _spawn)
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			if car.can_swap():
				car.swap_ends("manual")
		KEY_R:
			_respawn()
			for i in cpu_drivers.size():
				cpu_drivers[i].reset(4 + i * 5)
		KEY_C:
			rig.toggle_mode()
		KEY_F1:
			overlay.toggle()
		KEY_F2:
			for driver: CpuDriver in cpu_drivers:
				driver.enabled = not driver.enabled
				if not driver.enabled:
					driver.target.throttle = 0.0
					driver.target.brake = 0.0
					driver.target.steer = 0.0
					driver.target.handbrake = false
					driver.target.freeze = true
				else:
					driver.target.freeze = false
		KEY_ESCAPE:
			_return_to_menu()


func _return_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/garage.tscn")


func _physics_process(_delta: float) -> void:
	var fwd := 1.0 if (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) else 0.0
	var back := 1.0 if (Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) else 0.0
	var right := 1.0 if (Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) else 0.0
	var left := 1.0 if (Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)) else 0.0
	car.throttle = fwd
	car.brake = back
	car.steer = right - left
	car.handbrake = Input.is_key_pressed(KEY_SHIFT)
