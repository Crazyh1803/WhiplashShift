## CPU inputs pass through the same chassis physics as human inputs.
class_name CpuDriver
extends Node

signal recovered

# Pace scales the driver's requested speed, never the vehicle's power or grip.
const DIFFICULTIES := {
	"easy": {
		"label": "Easy", "pace": 0.70, "corner": 0.70,
		"braking": 0.40, "swap_speed": 18.0, "gap": 9.0,
		"pass_delay": 1.4, "pass_clearance": 1.6, "lane_rate": 1.5,
		"description": "Relaxed pace, early braking, extra room in traffic.",
	},
	"medium": {
		"label": "Medium", "pace": 0.85, "corner": 0.78,
		"braking": 0.48, "swap_speed": 20.0, "gap": 6.0,
		"pass_delay": 0.7, "pass_clearance": 1.1, "lane_rate": 1.8,
		"description": "Brisk pace, balanced cornering and traffic spacing.",
	},
	"hard": {
		"label": "Hard", "pace": 1.0, "corner": 0.98,
		"braking": 0.90, "swap_speed": 24.0, "gap": 5.0,
		"pass_delay": 0.25, "pass_clearance": 0.8, "lane_rate": 2.0,
		"description": "Fast pace, late braking, assertive passing.",
	},
}

var target: Vehicle
var course: CourseDefinition
var progress: TrackProgress
var lane_offset: float = 0.0
var skill: float = 0.8
var braking_preview: float = 2.8
var following_gap: float = 6.0
var corner_skill: float = 0.85
var braking_confidence: float = 0.48
var swap_entry_speed: float = 10.0
var swap_throttle: float = 0.65
var swap_lead: float = 0.0
var cruise_throttle: float = 0.4
var _racing_plan: bool = false
var _anticipated_end: String = ""
var enabled: bool = true
var recoveries: int = 0
var swaps: int = 0
var peers: Array[Vehicle] = []
var target_speed: float = 0.0
var racecraft := CpuRacecraft.new()
var _stuck_time: float = 0.0
var _off_time: float = 0.0
var _turn_time: float = 0.0
var _turning: bool = false
var _turn_sign: float = 1.0
var _settle_time: float = 0.0


func set_difficulty(difficulty: String, grid_slot: int = 0) -> void:
	var preset: Dictionary = DIFFICULTIES.get(difficulty, DIFFICULTIES["medium"])
	# A small, deterministic spread gives the two rivals individual pace.
	skill = float(preset["pace"]) + (-0.04 if grid_slot % 2 == 0 else 0.04)
	following_gap = float(preset["gap"])
	corner_skill = float(preset["corner"])
	braking_confidence = float(preset["braking"])
	swap_entry_speed = float(preset["swap_speed"])
	# All levels need a reliable swap; caution belongs in the speed plan.
	swap_throttle = 1.0
	swap_lead = 24.0
	cruise_throttle = lerpf(0.55, 0.90, clampf((corner_skill - 0.70) / 0.28, 0.0, 1.0))
	_racing_plan = true
	racecraft.decision_delay = float(preset["pass_delay"])
	racecraft.clearance = float(preset["pass_clearance"])
	racecraft.lane_change_rate = float(preset["lane_rate"])
	racecraft.allow_rough_passes = difficulty == "hard"


func setup(vehicle: Vehicle, p_course: CourseDefinition, start_index: int = 0) -> void:
	target = vehicle
	course = p_course
	progress = TrackProgress.new()
	progress.setup(course, start_index)
	racecraft.setup(target, course, progress)
	racecraft.reset(lane_offset, true)


func reset(start_index: int = 0) -> void:
	progress.reset(start_index)
	recoveries = 0
	swaps = 0
	racecraft.reset(lane_offset, true)
	_place(start_index)


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not enabled or not is_instance_valid(target) or progress == null:
		return
	if _settle_time > 0.0:
		_settle_time -= delta
		_controls(0.0, 0.0, 0.0, false)
		return
	progress.update(target.global_position)
	var point: Dictionary = course.points[progress.index]
	var width: float = point["w"]
	_stuck_time = _stuck_time + delta if target.speed < 1.0 else 0.0
	_off_time = _off_time + delta if progress.off_line > width * 0.65 else 0.0
	if _stuck_time > 6.0 or _off_time > 3.0 or target.global_transform.basis.y.y < 0.2 or target.global_position.y < -2.0:
		_recover()
		return

	var swap_point: Dictionary = course.points[progress.point_ahead(swap_lead)]
	var desired_end := _preferred(int(swap_point["s"]))
	if _anticipated_end == _preferred(int(point["s"])):
		_anticipated_end = ""
	if not _anticipated_end.is_empty():
		desired_end = _anticipated_end
	if not _turning and desired_end != target.active_end and target.can_swap():
		if swap_lead > 0.0 and desired_end != _preferred(int(point["s"])):
			_anticipated_end = desired_end
		target.swap_ends("cpu")
		swaps += 1
		_turning = true
		_turn_time = 0.0
		_turn_sign = 1.0

	# CPU braking targets assume normal drive; earned boost is reserved for player input.
	target_speed = _speed_limit()
	racecraft.tick(delta, peers, lane_offset, target_speed, not _turning and not progress.wrong_way and target.fwd_speed >= 0.0)
	var ahead: Dictionary = course.points[progress.point_ahead(10.0 + target.speed * 0.7)]
	var direction: Vector3 = ahead["dir"]
	var right := Vector3(-direction.z, 0.0, direction.x)
	var lane_bound := maxf(0.0, minf(width, float(ahead["w"])) * 0.5 - target.tuning.body_width * 0.5 - 1.0)
	var aim: Vector3 = ahead["pos"] + right * clampf(racecraft.lane, -lane_bound, lane_bound)
	var desired := aim - target.global_position
	desired.y = 0.0
	desired = desired.normalized()
	var forward := target.forward_vector()
	forward.y = 0.0
	forward = forward.normalized()
	var error := atan2(-forward.cross(desired).y, forward.dot(desired))
	var steering := clampf(error * 2.4, -1.0, 1.0)

	if _turning:
		if _racing_plan and _turn_time == 0.0:
			_turn_sign = signf(error) if absf(error) > 0.1 else 1.0
		_turn_time += delta
		var route: Vector3 = point["dir"]
		if forward.dot(route) > 0.8 and target.fwd_speed > -1.0:
			_turning = false
		elif _turn_time > 8.0:
			_recover()
			return
		else:
			# A swap inherits reverse motion relative to the newly active end.
			# Counter-steer while rolling backwards, then power through the turn.
			steering = _turn_sign if absf(error) > 2.0 else steering
			if target.fwd_speed < -1.0:
				steering = -steering
			_controls(swap_throttle, 0.0, steering, target.speed > 8.0)
			return

	var throttle := 1.0 if target.speed < target_speed - 1.0 else cruise_throttle
	var braking := clampf((target.speed - target_speed) / 4.0, 0.0, 1.0)
	if braking > 0.0:
		throttle = 0.0
	for candidate: Variant in peers:
		if not is_instance_valid(candidate) or candidate == target or candidate.collision_layer == 0:
			continue
		var peer: Vehicle = candidate
		var relative := peer.global_position - target.global_position
		var along := relative.dot(forward)
		var lateral := absf(relative.dot(Vector3(-forward.z, 0.0, forward.x)))
		var side_clearance := (target.tuning.body_width + peer.tuning.body_width) * 0.5 + 0.45
		if absf(relative.y) < 3.0 and along > 0.0 and along < maxf(following_gap + 9.0, target.speed * 1.2) and lateral < side_clearance:
			var safe_speed := maxf(0.0, peer.linear_velocity.dot(forward) + (along - following_gap) * 0.8)
			if target.speed > safe_speed:
				throttle = 0.0
				braking = maxf(braking, clampf((target.speed - safe_speed) / 4.0, 0.0, 1.0))
	if absf(error) > 0.7:
		throttle = minf(throttle, 0.55)
	_controls(throttle, braking, steering, false)


func _speed_limit() -> float:
	if _racing_plan:
		return _racing_speed_limit()
	var limit := INF
	var travelled := 0.0
	var span_start := 0.0
	var first_dir: Vector3 = course.points[progress.index]["dir"]
	var n := course.points.size()
	var index := progress.index
	var horizon := 40.0 + target.speed * braking_preview
	for _step in n:
		var point: Dictionary = course.points[index]
		var sid: int = point["s"]
		var surface_limit := target.tuning.top_speed(target.active_end) * target.top_speed_multiplier * Surfaces.mod_top(target.active_end, sid) * skill
		limit = minf(limit, surface_limit)
		var span := travelled - span_start
		if span >= 15.0:
			var direction: Vector3 = point["dir"]
			var angle := absf(atan2(first_dir.cross(direction).y, first_dir.dot(direction)))
			var curvature := angle / span
			if curvature > 0.0001:
				var mu := target.tuning.tire_grip(target.active_end) * target.grip_multiplier * Surfaces.GRIP[sid] * Surfaces.mod_grip(target.active_end, sid)
				limit = minf(limit, sqrt(mu * 9.81 / curvature) * skill)
			first_dir = direction
			span_start = travelled
		travelled += float(point["dist"])
		if travelled > horizon:
			break
		index = (index + 1) % n
	return maxf(5.0, limit)


func _racing_speed_limit() -> float:
	var current: Dictionary = course.points[progress.index]
	var current_mu := _combined_grip(int(current["s"]))
	var brake_force := target.tuning.brake_force(target.active_end) * target.brake_multiplier / target.mass
	var braking := maxf(0.5, minf(brake_force, current_mu * 9.81) * braking_confidence)
	var horizon := maxf(120.0, target.speed * target.speed / (2.0 * braking) + target.speed)
	var limit := INF
	var travelled := 0.0
	var n := course.points.size()
	var index := progress.index
	for _step in n:
		var point: Dictionary = course.points[index]
		var sid: int = point["s"]
		var mu := _combined_grip(sid)
		var end := _preferred(sid)
		var speed := target.tuning.top_speed(end) * target.top_speed_multiplier * Surfaces.mod_top(end, sid) * skill
		if end != target.active_end:
			speed = minf(speed, swap_entry_speed)
		var before: Dictionary = course.points[posmod(index - 2, n)]
		var after: Dictionary = course.points[(index + 2) % n]
		var a: Vector3 = before["dir"]
		var b: Vector3 = after["dir"]
		var span: float = Vector3(before["pos"]).distance_to(after["pos"])
		var angle := absf(atan2(a.cross(b).y, a.dot(b)))
		if span > 0.1 and angle > 0.0001:
			# Both ends share cornering work; the inactive pair can have much
			# less grip. Reserve traction for steering while accelerating.
			speed = minf(speed, sqrt(mu * 9.81 * 0.90 * span / angle) * corner_skill)
		var lead := swap_lead if end != target.active_end else 0.0
		var available := maxf(0.0, travelled - lead - target.tuning.body_length - target.speed * 0.35)
		var decel := minf(braking, mu * 9.81 * braking_confidence)
		limit = minf(limit, sqrt(speed * speed + 2.0 * decel * available))
		travelled += float(point["dist"])
		if travelled >= horizon:
			break
		index = (index + 1) % n
	return maxf(5.0, limit)


func _combined_grip(sid: int) -> float:
	var grip_a := target.tuning.tire_grip("A") * Surfaces.mod_grip("A", sid)
	var grip_b := target.tuning.tire_grip("B") * Surfaces.mod_grip("B", sid)
	return (grip_a + grip_b) * 0.5 * target.grip_multiplier * Surfaces.GRIP[sid]


func _preferred(sid: int) -> String:
	# Keeping the current end over ice prevents two needless 180-degree turns
	# across the short ice patch; speed planning still uses its low grip.
	if sid == Surfaces.Id.ICE or sid == Surfaces.Id.OIL:
		return target.active_end
	return Surfaces.PREFERRED[sid]


func _recover() -> void:
	recoveries += 1
	var index := progress.checkpoint_index()
	progress.recover(index)
	_place(index)
	recovered.emit()


func _place(index: int) -> void:
	var point: Dictionary = course.points[index]
	var direction: Vector3 = point["dir"]
	var end: String = Surfaces.PREFERRED[int(point["s"])]
	var transform := Transform3D.IDENTITY
	transform.basis = Basis(Vector3.UP, atan2(-direction.x, -direction.z) + (PI if end == "B" else 0.0))
	transform.origin = point["pos"] + Vector3(-direction.z, 0.0, direction.x) * lane_offset + Vector3.UP * 1.4
	target.active_end = end
	target.engage = 1.0
	target.cooldown = 0.0
	target.power_cut = 0.0
	target.steer_angle = 0.0
	target.global_transform = transform
	target.linear_velocity = Vector3.ZERO
	target.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(target.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
	PhysicsServer3D.body_set_state(target.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(target.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	target.reset_effects_state()
	target.reset_physics_interpolation()
	racecraft.reset(lane_offset)
	_anticipated_end = ""
	_stuck_time = 0.0
	_off_time = 0.0
	_turn_time = 0.0
	_turning = false
	_settle_time = 0.5
	_controls(0.0, 0.0, 0.0, false)


func _controls(throttle: float, brake: float, steer: float, handbrake: bool) -> void:
	target.throttle = throttle
	target.brake = brake
	target.steer = steer
	target.handbrake = handbrake
