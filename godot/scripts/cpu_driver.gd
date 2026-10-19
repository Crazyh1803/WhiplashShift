## CPU inputs pass through the same chassis physics as human inputs.
class_name CpuDriver
extends Node

var target: Vehicle
var course: CourseDefinition
var progress: TrackProgress
var lane_offset: float = 0.0
var skill: float = 0.8
var enabled: bool = true
var recoveries: int = 0
var swaps: int = 0
var peers: Array[Vehicle] = []
var target_speed: float = 0.0
var _stuck_time: float = 0.0
var _off_time: float = 0.0
var _turn_time: float = 0.0
var _turning: bool = false
var _turn_sign: float = 1.0
var _settle_time: float = 0.0


func setup(vehicle: Vehicle, p_course: CourseDefinition, start_index: int = 0) -> void:
	target = vehicle
	course = p_course
	progress = TrackProgress.new()
	progress.setup(course, start_index)


func reset(start_index: int = 0) -> void:
	progress.reset(start_index)
	recoveries = 0
	swaps = 0
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

	var desired_end := _preferred(int(point["s"]))
	if not _turning and desired_end != target.active_end and target.can_swap():
		target.swap_ends("cpu")
		swaps += 1
		_turning = true
		_turn_time = 0.0
		_turn_sign = 1.0

	var ahead: Dictionary = course.points[progress.point_ahead(10.0 + target.speed * 0.7)]
	var direction: Vector3 = ahead["dir"]
	var right := Vector3(-direction.z, 0.0, direction.x)
	var aim: Vector3 = ahead["pos"] + right * clampf(lane_offset, -width * 0.22, width * 0.22)
	var desired := aim - target.global_position
	desired.y = 0.0
	desired = desired.normalized()
	var forward := target.forward_vector()
	forward.y = 0.0
	forward = forward.normalized()
	var error := atan2(-forward.cross(desired).y, forward.dot(desired))
	var steering := clampf(error * 2.4, -1.0, 1.0)

	if _turning:
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
			_controls(0.65, 0.0, steering, target.speed > 8.0)
			return

	target_speed = _speed_limit()
	var throttle := 1.0 if target.speed < target_speed - 1.0 else 0.4
	var braking := clampf((target.speed - target_speed) / 4.0, 0.0, 1.0)
	if braking > 0.0:
		throttle = 0.0
	for peer: Vehicle in peers:
		if not is_instance_valid(peer) or peer == target:
			continue
		var relative := peer.global_position - target.global_position
		var along := relative.dot(forward)
		var lateral := absf(relative.dot(Vector3(-forward.z, 0.0, forward.x)))
		if along > 0.0 and along < 15.0 and lateral < 3.0:
			var safe_speed := maxf(0.0, peer.linear_velocity.dot(forward) + (along - 6.0) * 0.8)
			if target.speed > safe_speed:
				throttle = 0.0
				braking = maxf(braking, clampf((target.speed - safe_speed) / 4.0, 0.0, 1.0))
	if absf(error) > 0.7:
		throttle = minf(throttle, 0.55)
	_controls(throttle, braking, steering, false)


func _speed_limit() -> float:
	var limit := INF
	var travelled := 0.0
	var span_start := 0.0
	var first_dir: Vector3 = course.points[progress.index]["dir"]
	var n := course.points.size()
	var index := progress.index
	var horizon := 40.0 + target.speed * 2.8
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
	target.reset_physics_interpolation()
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
