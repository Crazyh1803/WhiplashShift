## Traffic decisions plus physical passing with the production CPU controller.
extends Node3D

var _pass := 0
var _fail := 0
var _cars: Array[Vehicle] = []
var _course: CourseDefinition
var _driver: CpuDriver
var _forward := Vector3.RIGHT
var _right := Vector3.BACK
var _origin := Vector3.ZERO


func _ready() -> void:
	_setup_decisions()
	_test_decisions()
	_test_anticipation()
	for car: Vehicle in _cars:
		car.free()
	_driver.free()
	for difficulty: String in ["easy", "medium", "hard"]:
		await _test_physical_pass(difficulty)
	await _test_physical_pass("hard", true)
	print("RACECRAFT: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _setup_decisions() -> void:
	_course = TrackData.build_course()
	_origin = _course.points[20]["pos"] + Vector3.UP * 1.4
	for i in 4:
		var car := Vehicle.new()
		car.freeze = true
		car.tuning = TuningProfile.new()
		add_child(car)
		_cars.append(car)
	_driver = CpuDriver.new()
	_driver.set_difficulty("hard")
	_driver.setup(_cars[0], _course, 20)


func _place_car(index: int, along: float, lateral: float, speed: float = 8.0) -> void:
	var car := _cars[index]
	car.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), _origin + _forward * along + _right * lateral)
	car.linear_velocity = _forward * speed
	car.speed = speed
	car.fwd_speed = speed


func _reset_decisions(difficulty: String = "hard") -> void:
	_driver.set_difficulty(difficulty)
	_driver.progress.reset(20)
	_driver._anticipated_end = ""
	_driver._turning = false
	_cars[0].active_end = "A"
	_cars[0].cooldown = 0.0
	_driver.racecraft.reset(0.0, true)
	_place_car(0, 0.0, 0.0, 18.0)
	_place_car(1, 22.0, 0.0)
	_place_car(2, -100.0, 0.0)
	_place_car(3, -100.0, 0.0)


func _decide(peers: Array[Vehicle], duration: float = 2.0, allowed: bool = true) -> void:
	_driver.racecraft.tick(duration, peers, 0.0, 30.0, allowed)


func _test_decisions() -> void:
	var lead: Vehicle = _cars[1]
	var beside: Vehicle = _cars[2]
	var other: Vehicle = _cars[3]
	_reset_decisions("easy")
	_decide([lead], 0.3)
	_check("Easy waits for a sustained opportunity", not _driver.racecraft.is_passing())
	_reset_decisions("medium")
	_decide([lead], 0.3)
	_check("Medium assesses traffic before passing", not _driver.racecraft.is_passing())
	_decide([lead], 0.5)
	_check("Medium commits to an available pass", _driver.racecraft.is_passing())
	_reset_decisions()
	_decide([lead], 0.3)
	_check("Hard commits sooner to an available pass", _driver.racecraft.is_passing())
	_decide([lead], 0.5)
	_check("passing line changes smoothly", _driver.racecraft.lane < 0.0 and absf(_driver.racecraft.lane) <= 1.01)
	var side := signf(_driver.racecraft.lane)
	# An obstruction appears after commitment: hold the chosen side and brake,
	# rather than darting across the opponent to the newly clear side.
	_place_car(2, 15.0, -3.0)
	_decide([lead, beside], 0.5)
	_check("new traffic cannot flip a committed passing side", _driver.racecraft.is_passing()
		and signf(_driver.racecraft.lane) == side)
	_place_car(0, 0.0, -2.8, 18.0)
	_place_car(1, -1.0, 0.0)
	_decide([lead], 0.5)
	_check("a nose ahead is insufficient to merge", _driver.racecraft.is_passing()
		and _driver.racecraft.lane < -2.0)
	_place_car(1, -12.0, 0.0)
	_place_car(2, -8.0, 0.0, 30.0)
	_decide([lead, beside], 0.5)
	_check("completed pass is recorded only after rear clearance", not _driver.racecraft.is_passing()
		and _driver.racecraft.passes_completed == 1)
	_check("fast rear traffic prevents merging", _driver.racecraft.lane < -2.0)
	_decide([lead], 0.5)
	_check("clear return lane allows a gradual merge", _driver.racecraft.lane > -2.8 and _driver.racecraft.lane < 0.0)

	_reset_decisions()
	_place_car(2, 0.0, -3.0)
	_decide([lead, beside])
	_decide([lead, beside], 0.5)
	_check("occupied left corridor chooses the clear right side", _driver.racecraft.lane > 0.0)
	_reset_decisions()
	_place_car(2, -12.0, -3.0, 32.0)
	_place_car(3, 0.0, 3.0)
	_decide([lead, beside, other])
	_check("boxed-in traffic and a closing rear car prevent passing", not _driver.racecraft.is_passing())
	_place_car(1, 8.0, 0.0)
	_driver.peers.assign([lead, beside, other])
	_driver.enabled = true
	_driver._settle_time = 0.0
	_driver.tick(1.0 / 120.0)
	_check("boxed-in driver follows with brakes instead of forcing a gap", _cars[0].throttle == 0.0 and _cars[0].brake > 0.0)

	_reset_decisions()
	_place_car(1, 22.0, 0.0, -8.0)
	_decide([lead])
	_check("oncoming traffic is not mistaken for a slow rival", not _driver.racecraft.is_passing())
	_reset_decisions()
	_place_car(2, 8.0, -6.0)
	beside.linear_velocity += _right * 3.0
	_place_car(3, 0.0, 3.0)
	_decide([lead, beside, other])
	_check("a car drifting into the passing corridor prevents commitment", not _driver.racecraft.is_passing())

	_reset_decisions()
	for point: Dictionary in _course.points:
		point["w"] = 7.0
	_decide([lead])
	_check("narrow road prevents an unsafe pass", not _driver.racecraft.is_passing())
	for point: Dictionary in _course.points:
		point["w"] = 26.0
	_course.points[30]["s"] = Surfaces.Id.MUD
	_decide([lead])
	_check("impending surface swap prevents committing to a pass", not _driver.racecraft.is_passing())
	_course.points[30]["s"] = Surfaces.Id.TARMAC
	_course.points[30]["dir"] = Vector3.BACK
	_decide([lead])
	_check("sharp bend ahead prevents committing to a pass", not _driver.racecraft.is_passing())
	_course.points[30]["dir"] = _forward
	_decide([lead])
	_decide([lead], 0.5, false)
	_check("swap or wrong-way driving cancels the maneuver", not _driver.racecraft.is_passing())

	_reset_decisions()
	lead.collision_layer = 0
	_decide([lead])
	_check("retired racers do not obstruct or trigger passing", not _driver.racecraft.is_passing())
	lead.collision_layer = 1
	_decide([lead])
	_decide([])
	_check("removed opponents cancel stale maneuvers", not _driver.racecraft.is_passing())
	_reset_decisions()
	var temporary := Vehicle.new()
	var stale_peers: Array[Vehicle] = [temporary, lead]
	temporary.free()
	_decide(stale_peers)
	_check("freed peer references cannot prevent assessing valid traffic", _driver.racecraft.is_passing())
	lead.collision_layer = 0
	_decide([lead])
	_check("a retired pass target cancels the maneuver", not _driver.racecraft.is_passing()
		and _driver.racecraft.passes_completed == 0)
	lead.collision_layer = 1
	var velocity := _cars[0].linear_velocity
	var transform := _cars[0].global_transform
	var distance := _driver.progress.total_distance
	_decide([lead])
	_check("planner cannot move vehicles or award progress", _cars[0].linear_velocity == velocity
		and _cars[0].global_transform == transform and _driver.progress.total_distance == distance)
	_driver.racecraft.reset(4.0, true)
	_check("retry clears passing state and returns the assigned grid lane", not _driver.racecraft.is_passing()
		and _driver.racecraft.lane == 4.0 and _driver.racecraft.passes_completed == 0)


func _test_anticipation() -> void:
	_reset_decisions()
	_driver.peers.clear()
	_driver._settle_time = 0.0
	for index in range(30, 51):
		_course.points[index]["s"] = Surfaces.Id.MUD
	_cars[0].global_position = _course.points[24]["pos"] + Vector3.UP * 1.4
	_driver.progress.reset(24)
	_driver.tick(1.0 / 120.0)
	_check("Hard begins the end swap on the approach", _cars[0].active_end == "B"
		and _driver._anticipated_end == "B" and _driver._turning)
	var swaps := _driver.swaps
	# A spin can carry the car behind the trigger point. It must not select
	# the old end again while finishing the same planned transition.
	_cars[0].global_position = _course.points[20]["pos"] + Vector3.UP * 1.4
	_cars[0].global_basis = Basis(Vector3.UP, PI * 0.5)
	_cars[0].cooldown = 0.0
	_driver._turning = false
	_driver.tick(1.0 / 120.0)
	_check("an anticipated swap stays committed until the boundary", _cars[0].active_end == "B"
		and _driver.swaps == swaps and _driver._anticipated_end == "B")
	_cars[0].global_position = _course.points[31]["pos"] + Vector3.UP * 1.4
	_driver.tick(1.0 / 120.0)
	_check("crossing the new surface releases swap commitment", _driver._anticipated_end.is_empty()
		and _cars[0].active_end == "B")
	_driver.reset(20)
	_check("recovery clears anticipated swap state", _driver._anticipated_end.is_empty()
		and not _driver._turning)
	for index in range(30, 51):
		_course.points[index]["s"] = Surfaces.Id.TARMAC


func _test_physical_pass(difficulty: String, rough: bool = false) -> void:
	GameSession.set_cpu_difficulty(difficulty)
	GameSession.configure("TRAFFIC TEST", "blackjack", ["boilerfang", "ramjet"])
	var scene: Node3D = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(scene)
	while scene.get("race").state == RaceDirector.State.COUNTDOWN:
		await get_tree().physics_frame
	scene.set_physics_process(false)
	var player: Vehicle = scene.get("car")
	player.freeze = true
	player.global_position = Vector3(-620.0, 2.0, 0.0)
	var drivers: Array[CpuDriver] = scene.get("cpu_drivers")
	var follower: CpuDriver = drivers[0]
	var leader: CpuDriver = drivers[1]
	for driver: CpuDriver in drivers:
		driver.lane_offset = 0.0
	var start := 10
	if rough:
		var course: CourseDefinition = scene.get("course")
		for index in range(course.points.size() - 20):
			var point: Dictionary = course.points[index]
			var ahead: Dictionary = course.points[index + 20]
			if int(point["s"]) == Surfaces.Id.MUD and Vector3(point["dir"]).dot(ahead["dir"]) > 0.9999:
				start = index
				break
		_check("rough pass fixture begins on mud", int(course.points[start]["s"]) == Surfaces.Id.MUD)
	follower.reset(start)
	leader.reset(start + 10)
	if rough:
		difficulty += " rough"
	# A slower moving rival, with unchanged power/grip and the same chassis model.
	leader.skill = 0.24
	var original_drive := follower.target.drive_multiplier
	var original_grip := follower.target.grip_multiplier
	var original_top := follower.target.top_speed_multiplier
	follower.target.contact_monitor = true
	follower.target.max_contacts_reported = 8
	var leader_start := leader.progress.route_distance
	var touched_leader := false
	var merged := false
	for _frame in 120 * 24:
		await get_tree().physics_frame
		touched_leader = touched_leader or follower.target.get_colliding_bodies().has(leader.target)
		if follower.racecraft.passes_completed > 0 and absf(follower.racecraft.lane) < 0.1:
			merged = true
			break
	_check("%s physically passes a slower moving rival and merges" % difficulty, merged,
		"passes=%d lane=%.2f gap=%.1f" % [follower.racecraft.passes_completed, follower.racecraft.lane,
		follower.progress.route_distance - leader.progress.route_distance])
	_check("%s pass avoids vehicle contact and recovery" % difficulty, not touched_leader
		and follower.recoveries == 0 and leader.recoveries == 0)
	_check("%s rival keeps moving during the pass" % difficulty,
		leader.progress.route_distance > leader_start + 15.0 and leader.target.speed > 3.0)
	_check("%s pass retains shared power and grip" % difficulty,
		follower.target.tuning == leader.target.tuning and follower.target.drive_multiplier == original_drive
		and follower.target.grip_multiplier == original_grip and follower.target.top_speed_multiplier == original_top)
	scene.queue_free()
	await get_tree().process_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s %s" % ["pass" if ok else "FAIL", label, detail])
