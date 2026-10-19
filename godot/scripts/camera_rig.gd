## Chase camera. The 180 degree swing on a swap is not scripted — it falls out of
## interpolating the yaw to the ACTIVE end's heading by shortest angle. `snap`
## mode cuts instantly instead, so the two can be compared (C toggles).
class_name CameraRig
extends Node3D

@export var target: Vehicle
var mode: String = "swing"
var cam: Camera3D
var _yaw: float = 0.0


func _ready() -> void:
	# This branch follows the rendered car each frame, so do not interpolate
	# the camera again on top of its manually smoothed movement.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 4.2, 9.0)
	cam.rotation = Vector3(deg_to_rad(-13.0), 0.0, 0.0)
	cam.fov = 72.0
	cam.current = true
	add_child(cam)
	if target:
		reset_follow()


func reset_follow() -> void:
	if target == null or cam == null:
		return
	# Seed Godot's interpolation history before the first moving frame.
	target.get_global_transform_interpolated()
	var pose := target.global_transform
	global_position = pose.origin
	var f := pose.basis * Vector3.FORWARD * target.forward_sign()
	_yaw = atan2(-f.x, -f.z)
	rotation.y = _yaw
	cam.position = Vector3(0.0, 4.2, 9.0)
	cam.look_at(pose.origin + Vector3.UP * 0.75)


func toggle_mode() -> void:
	mode = "snap" if mode == "swing" else "swing"


func _process(delta: float) -> void:
	if target == null:
		return
	var pose := target.get_global_transform_interpolated()
	var f := pose.basis * Vector3.FORWARD * target.forward_sign()
	var want: float = atan2(-f.x, -f.z)
	if mode == "snap":
		_yaw = want
	else:
		var d: float = wrapf(want - _yaw, -PI, PI)
		# faster the further it has to travel, so a 180 sweeps rather than crawls
		var rate: float = (3.4 + absf(d) * 2.4) * delta
		_yaw += d if absf(d) < rate else signf(d) * rate
	rotation.y = _yaw

	var want_z: float = 8.0 + target.speed * 0.14
	cam.position.z = lerpf(cam.position.z, want_z, 1.0 - exp(-3.0 * delta))
	# Keep clearance behind the car as lookahead grows; always frame the chassis
	# while the orbit swings around to the newly active end.
	var lead: Vector3 = f * minf(target.speed * 0.4, maxf(0.0, cam.position.z - 7.0))
	global_position = global_position.lerp(
		pose.origin + lead, 1.0 - exp(-7.0 * delta))
	cam.look_at(pose.origin + Vector3.UP * 0.75)
