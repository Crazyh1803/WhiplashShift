## Chooses traffic corridors; all movement still comes from normal driver inputs.
class_name CpuRacecraft
extends RefCounted

var lane: float = 0.0
var passes_completed: int = 0
var decision_delay: float = 0.7
var clearance: float = 1.1
var lane_change_rate: float = 1.8
var allow_rough_passes: bool = false
var _vehicle: Vehicle
var _course: CourseDefinition
var _progress: TrackProgress
var _opponent: Vehicle
var _pass_lane: float = 0.0
var _decision_time: float = 0.0
var _pass_time: float = 0.0
var _cooldown: float = 0.0


func setup(vehicle: Vehicle, course: CourseDefinition, progress: TrackProgress) -> void:
	_vehicle = vehicle
	_course = course
	_progress = progress


func reset(base_lane: float, clear_stats: bool = false) -> void:
	lane = base_lane
	_opponent = null
	_decision_time = 0.0
	_pass_time = 0.0
	_cooldown = 0.0
	if clear_stats:
		passes_completed = 0


func is_passing() -> bool:
	return is_instance_valid(_opponent)


func tick(delta: float, peers: Array[Vehicle], base_lane: float, cruise_speed: float, can_pass: bool) -> void:
	var point: Dictionary = _course.points[_progress.index]
	var forward: Vector3 = point["dir"]
	var right := Vector3(-forward.z, 0.0, forward.x)
	_cooldown = maxf(0.0, _cooldown - delta)
	if is_passing():
		_pass_time += delta
		if not can_pass or not peers.has(_opponent) or not _relevant(_opponent):
			_end_pass()
		else:
			var along := (_opponent.global_position - _vehicle.global_position).dot(forward)
			var clear_distance := (_vehicle.tuning.body_length + _opponent.tuning.body_length) * 0.5 + clearance
			if along < -clear_distance:
				passes_completed += 1
				_end_pass()
			elif _pass_time > 12.0 and along > clear_distance and _lane_clear(base_lane, peers, forward, right):
				# An unsuccessful pass can retreat only while fully behind.
				_end_pass()
		if is_passing():
			# Commit to the chosen side even when a third car blocks it. The
			# driver's normal traffic braking remains active throughout.
			lane = move_toward(lane, _pass_lane, lane_change_rate * delta)
			return

	# A car alongside or closing rapidly from behind keeps us in this lane.
	if _lane_clear(base_lane, peers, forward, right):
		lane = move_toward(lane, base_lane, lane_change_rate * delta)
	if not can_pass or _cooldown > 0.0:
		_decision_time = 0.0
		return
	var lead: Vehicle
	var nearest := maxf(32.0, _vehicle.speed * 2.0)
	for candidate: Variant in peers:
		if not _relevant(candidate):
			continue
		var peer: Vehicle = candidate
		var relative := peer.global_position - _vehicle.global_position
		var along := relative.dot(forward)
		var overlap := (_vehicle.tuning.body_width + peer.tuning.body_width) * 0.5 + 0.8
		if along > _vehicle.tuning.body_length and along < nearest and absf(relative.dot(right)) < overlap:
			if peer.linear_velocity.dot(forward) >= -1.0 and cruise_speed > maxf(0.0, peer.linear_velocity.dot(forward)) + 2.0:
				lead = peer
				nearest = along
	if lead == null:
		_decision_time = 0.0
		return
	var bound := _passing_bound(maxf(60.0, nearest + _vehicle.speed * 2.0))
	if bound <= 0.0:
		_decision_time = 0.0
		return
	_decision_time += delta
	if _decision_time < decision_delay:
		return
	var lead_lane := (lead.global_position - Vector3(point["pos"])).dot(right)
	var spacing := (_vehicle.tuning.body_width + lead.tuning.body_width) * 0.5 + clearance
	var options: Array[float] = [lead_lane - spacing, lead_lane + spacing]
	if absf(options[1] - lane) < absf(options[0] - lane):
		options.reverse()
	for option: float in options:
		if absf(option) <= bound and _lane_clear(option, peers, forward, right, lead):
			_opponent = lead
			_pass_lane = option
			_pass_time = 0.0
			_decision_time = 0.0
			return


func _end_pass() -> void:
	_opponent = null
	_decision_time = 0.0
	_cooldown = 2.0


# A freed Node may remain in a peer array; validate before typed access.
func _relevant(peer: Variant) -> bool:
	return is_instance_valid(peer) and peer != _vehicle and peer.collision_layer != 0 \
		and absf(peer.global_position.y - _vehicle.global_position.y) < 3.0


func _lane_clear(goal: float, peers: Array[Vehicle], forward: Vector3, right: Vector3, excluded: Vehicle = null) -> bool:
	var point: Dictionary = _course.points[_progress.index]
	var current := (_vehicle.global_position - Vector3(point["pos"])).dot(right)
	for candidate: Variant in peers:
		if not _relevant(candidate) or candidate == excluded:
			continue
		var peer: Vehicle = candidate
		var relative := peer.global_position - _vehicle.global_position
		var along := relative.dot(forward)
		var peer_speed := peer.linear_velocity.dot(forward)
		var body_gap := (_vehicle.tuning.body_length + peer.tuning.body_length) * 0.5 + clearance
		var rear_guard := body_gap + maxf(0.0, peer_speed - _vehicle.speed) * 2.0
		var front_guard := maxf(18.0, body_gap + maxf(0.0, _vehicle.speed - peer_speed) * 2.0)
		if along < -rear_guard or along > front_guard:
			continue
		var peer_lane := (peer.global_position - Vector3(point["pos"])).dot(right)
		var side_gap := (_vehicle.tuning.body_width + peer.tuning.body_width) * 0.5 + clearance
		var future_lane := peer_lane + peer.linear_velocity.dot(right) * 1.5
		if goal > minf(peer_lane, future_lane) - side_gap and goal < maxf(peer_lane, future_lane) + side_gap:
			return false
		# Do not sweep across a car that is already beside us.
		if absf(along) < body_gap and peer_lane > minf(current, goal) - side_gap and peer_lane < maxf(current, goal) + side_gap:
			return false
	return true


func _passing_bound(horizon: float) -> float:
	var initial: Vector3 = _course.points[_progress.index]["dir"]
	var bound := INF
	var travelled := 0.0
	var index := _progress.index
	for _step in _course.points.size():
		var point: Dictionary = _course.points[index]
		var surface: int = point["s"]
		var stable_surface := surface in [Surfaces.Id.TARMAC, Surfaces.Id.RUMBLE, Surfaces.Id.GRAVEL]
		if allow_rough_passes and surface in [Surfaces.Id.MUD, Surfaces.Id.WATER, Surfaces.Id.BOULDER]:
			stable_surface = true
		if not stable_surface or Surfaces.PREFERRED[surface] != _vehicle.active_end or initial.dot(point["dir"]) < 0.94:
			return 0.0
		bound = minf(bound, float(point["w"]) * 0.5 - _vehicle.tuning.body_width * 0.5 - 1.0)
		travelled += float(point["dist"])
		if travelled >= horizon:
			break
		index = (index + 1) % _course.points.size()
	return bound
