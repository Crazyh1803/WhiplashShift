## M0 scene: the greybox circuit, a flat proving ground beside it, one car.
##
## Controls are deliberately identical to the web prototype so muscle memory
## transfers and a side-by-side comparison is honest rather than a confound.
## Raw key checks rather than an InputMap: this is a spike, and it keeps the
## bindings visible in one place.
extends Node3D

const SPAWN_LIFT := 1.4

var car: Vehicle
var rig: CameraRig
var hud: Hud
var overlay: DebugOverlay
var track: Array
var _spawn: Transform3D


func _ready() -> void:
	_build_world()
	_build_car()
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

	track = TrackData.author()
	TrackBuilder.build(self, track)
	TrackBuilder.build_proving_ground(self, Vector3(-620.0, 0.0, 0.0))


func _build_car() -> void:
	car = Vehicle.new()
	car.name = "Car"
	var tune: Resource = load("res://resources/default_tuning.tres")
	car.tuning = tune as TuningProfile if tune else TuningProfile.new()
	add_child(car)

	var p: Dictionary = track[0]
	var dir: Vector3 = p["dir"]
	_spawn = Transform3D.IDENTITY
	# yaw so the ACTIVE end (End A, body -Z) points down the track
	_spawn.basis = Basis(Vector3.UP, atan2(-dir.x, -dir.z))
	_spawn.origin = p["pos"] + Vector3(0.0, SPAWN_LIFT, 0.0)
	_respawn()


func _build_ui() -> void:
	rig = CameraRig.new()
	rig.target = car
	add_child(rig)
	hud = Hud.new()
	hud.target = car
	add_child(hud)
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
		KEY_C:
			rig.toggle_mode()
		KEY_F1:
			overlay.toggle()
		KEY_ESCAPE:
			get_tree().quit()


func _physics_process(_delta: float) -> void:
	var fwd := 1.0 if (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) else 0.0
	var back := 1.0 if (Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) else 0.0
	var right := 1.0 if (Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) else 0.0
	var left := 1.0 if (Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)) else 0.0
	car.throttle = fwd
	car.brake = back
	car.steer = right - left
	car.handbrake = Input.is_key_pressed(KEY_SHIFT)
