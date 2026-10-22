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
var course_cues: CourseCues
var track: Array
var cpu_drivers: Array[CpuDriver] = []
var cpu_cars: Array[Vehicle] = []
var _spawn: Transform3D
var race: RaceDirector
var items: RaceItems
var player_progress: TrackProgress
var _grid_indices: Array[int] = []
var _retired: Array[int] = []
var _collision_layers: Array[int] = []
var _collision_masks: Array[int] = []


func _ready() -> void:
	_build_world()
	_build_car()
	_build_cpu_drivers()
	_setup_race()
	items = RaceItems.new()
	items.name = "RaceItems"
	add_child(items)
	var racers: Array[Vehicle] = [car]
	racers.append_array(cpu_cars)
	items.setup(race, racers)
	for i in cpu_drivers.size():
		cpu_drivers[i].recovered.connect(items.reset_racer.bind(i + 1))
	_build_ui()
	# Drivers update their trackers first; race rules then sample the whole field.
	process_physics_priority = 100


func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = TrackMaterials.environment()
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
	gm.material_override = TrackMaterials.surface(Surfaces.Id.OFF)
	ground.add_child(gm)
	add_child(ground)

	course = TrackData.build_course()
	# Move the line along the opening straight, leaving room for a staggered grid.
	var race_points: Array = course.points.slice(16) + course.points.slice(0, 16)
	course.configure(course.course_id, course.display_name, course.theme_id, 3, race_points)
	track = course.points
	TrackBuilder.build(self, track)
	TrackBuilder.build_guard_rails(self, track)
	TrackScenery.build(self, course)
	TrackScenery.build_guidance(self, course)
	TrackScenery.build_deposits(self, course)
	course_cues = CourseCues.new()
	course_cues.setup(course)
	TrackBuilder.build_approach_boards(self, course_cues)
	TrackBuilder.build_proving_ground(self, Vector3(-620.0, 0.0, 0.0))
	_build_finish_line()


func _build_finish_line() -> void:
	var marker := MeshInstance3D.new()
	marker.name = "StartFinishLine"
	var box := BoxMesh.new()
	box.size = Vector3(float(track[0]["w"]), 0.02, 0.8)
	marker.mesh = box
	marker.transform = course.start_transform(0.05)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	marker.material_override = material
	add_child(marker)


func _build_car() -> void:
	car = preload("res://scripts/vehicle_factory.gd").create(GameSession.selected_vehicle())
	car.name = "Car"
	var tune: Resource = load("res://resources/default_tuning.tres")
	car.tuning = tune as TuningProfile if tune else TuningProfile.new()
	add_child(car)
	TrackMaterials.attach_driving_light(car)

	_grid_indices.assign([track.size() - 14, track.size() - 4, track.size() - 9])
	_spawn = _grid_transform(_grid_indices[0])
	_respawn()

	vehicle_audio = VEHICLE_AUDIO_SCRIPT.new()
	vehicle_audio.name = "VehicleAudio"
	vehicle_audio.target = car
	add_child(vehicle_audio)


func _build_cpu_drivers() -> void:
	var roster: Array[String] = GameSession.cpu_vehicle_ids.duplicate()
	if roster.size() < 2:
		roster = VehicleCatalog.random_cpu_roster(2, GameSession.selected_vehicle_id)
	GameSession.cpu_vehicle_ids = roster.duplicate()
	for i in 2:
		var spec := VehicleCatalog.get_vehicle(roster[i])
		var cpu := preload("res://scripts/vehicle_factory.gd").create(spec)
		cpu.name = "CPU_%d_%s" % [i + 1, String(spec["name"]).replace(" ", "_")]
		cpu.tuning = car.tuning
		add_child(cpu)
		var driver := CpuDriver.new()
		driver.name = "CpuDriver_%d" % (i + 1)
		driver.lane_offset = -4.0 if i == 0 else 4.0
		driver.set_difficulty(GameSession.cpu_difficulty, i)
		driver.setup(cpu, course, _grid_indices[i + 1])
		add_child(driver)
		driver.reset(_grid_indices[i + 1])
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
	hud.race = race
	hud.items = items
	hud.course_cues = course_cues
	add_child(hud)
	hud.main_menu_requested.connect(_return_to_menu)
	hud.retry_requested.connect(restart_race)
	overlay = DebugOverlay.new()
	overlay.target = car
	add_child(overlay)


func _setup_race() -> void:
	player_progress = TrackProgress.new()
	player_progress.setup(course, _grid_indices[0])
	race = RaceDirector.new()
	var names: Array[String] = [GameSession.callsign]
	var trackers: Array[TrackProgress] = [player_progress]
	for driver: CpuDriver in cpu_drivers:
		names.append(driver.target.vehicle_label)
		trackers.append(driver.progress)
	race.setup(course, names, trackers)
	for entrant: Vehicle in [car] + cpu_cars:
		_collision_layers.append(entrant.collision_layer)
		_collision_masks.append(entrant.collision_mask)
	_set_grid_controls()


func _grid_transform(index: int) -> Transform3D:
	var point: Dictionary = track[index]
	var direction: Vector3 = point["dir"]
	return Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)),
		point["pos"] + Vector3.UP * SPAWN_LIFT)


func _set_grid_controls() -> void:
	for driver: CpuDriver in cpu_drivers:
		driver.enabled = false
	for entrant: Vehicle in [car] + cpu_cars:
		entrant.throttle = 0.0
		entrant.brake = 1.0
		entrant.steer = 0.0
		entrant.handbrake = false


func restart_race() -> void:
	if race.state != RaceDirector.State.RESULTS:
		return
	var cars: Array = [car] + cpu_cars
	for i in cars.size():
		var entrant: Vehicle = cars[i]
		entrant.freeze = false
		entrant.visible = true
		entrant.collision_layer = _collision_layers[i]
		entrant.collision_mask = _collision_masks[i]
		entrant.speed = 0.0
		entrant.fwd_speed = 0.0
		entrant.last_swap = {}
		entrant.last_whiplash = {}
		entrant._pending = {}
		entrant._prev_lv = Vector3.ZERO
	_respawn()
	player_progress.reset(_grid_indices[0])
	for i in cpu_drivers.size():
		cpu_drivers[i].reset(_grid_indices[i + 1])
	_retired.clear()
	var names: Array[String] = []
	var trackers: Array[TrackProgress] = []
	for entry: Dictionary in race.entrants:
		names.append(entry["name"])
		trackers.append(entry["progress"])
	race.setup(course, names, trackers)
	for driver: CpuDriver in cpu_drivers:
		driver.peers.assign(cars)
	items.reset()
	_set_grid_controls()


func _retire(index: int) -> void:
	if _retired.has(index):
		return
	_retired.append(index)
	var entrant: Vehicle = ([car] + cpu_cars)[index]
	entrant.throttle = 0.0
	entrant.brake = 0.0
	entrant.steer = 0.0
	entrant.handbrake = false
	entrant.linear_velocity = Vector3.ZERO
	entrant.angular_velocity = Vector3.ZERO
	entrant.speed = 0.0
	entrant.fwd_speed = 0.0
	entrant.freeze = true
	entrant.collision_layer = 0
	entrant.collision_mask = 0
	if index > 0:
		cpu_drivers[index - 1].enabled = false
		entrant.visible = false
	for driver: CpuDriver in cpu_drivers:
		driver.peers.erase(entrant)


func _recover_player() -> void:
	var index := player_progress.checkpoint_index()
	player_progress.recover(index)
	var point: Dictionary = track[index]
	var end: String = Surfaces.PREFERRED[int(point["s"])]
	var recovery := _grid_transform(index)
	if end == "B":
		recovery.basis = recovery.basis.rotated(Vector3.UP, PI)
	_place_player(recovery, end)
	items.reset_racer(0)


func _respawn() -> void:
	_place_player(_spawn, "A")


func _place_player(transform: Transform3D, end: String) -> void:
	car.active_end = end
	car.engage = 1.0
	car.cooldown = 0.0
	car.power_cut = 0.0
	car.steer_angle = 0.0
	car.last_whiplash = {}
	car.last_swap = {}
	car._pending = {}
	car._prev_lv = Vector3.ZERO
	car.speed = 0.0
	car.fwd_speed = 0.0
	car.throttle = 0.0
	car.brake = 0.0
	car.steer = 0.0
	car.handbrake = false
	car.global_transform = transform
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	car.reset_terrain_response()
	car.reset_physics_interpolation()
	if is_instance_valid(rig):
		rig.reset_follow()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE:
			if race.state == RaceDirector.State.RACING and car.can_swap():
				car.swap_ends("manual")
		KEY_E:
			items.fire(0)
		KEY_R:
			if race.state == RaceDirector.State.RACING:
				_recover_player()
		KEY_ENTER:
			restart_race()
		KEY_C:
			rig.toggle_mode()
		KEY_F1:
			overlay.toggle()
		KEY_F2:
			if race.state != RaceDirector.State.RACING:
				return
			for driver: CpuDriver in cpu_drivers:
				if _retired.has(cpu_drivers.find(driver) + 1):
					continue
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


func _physics_process(delta: float) -> void:
	var previous_state := race.state
	if race.state == RaceDirector.State.RACING:
		player_progress.update(car.global_position)
	race.tick(delta)
	if previous_state == RaceDirector.State.COUNTDOWN and race.state == RaceDirector.State.RACING:
		for driver: CpuDriver in cpu_drivers:
			driver.enabled = true
			# The countdown already provided suspension settling time.
			driver._settle_time = 0.0
	items.tick(delta)
	for index: int in race.finish_order:
		_retire(index)
	if race.state == RaceDirector.State.RESULTS:
		for index in race.entrants.size():
			_retire(index)
		return
	if race.state == RaceDirector.State.COUNTDOWN:
		_set_grid_controls()
		return
	var fwd := 1.0 if (Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) else 0.0
	var back := 1.0 if (Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) else 0.0
	var right := 1.0 if (Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) else 0.0
	var left := 1.0 if (Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)) else 0.0
	car.throttle = fwd
	car.brake = back
	car.steer = right - left
	car.handbrake = Input.is_key_pressed(KEY_SHIFT)
