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
	cam = Camera3D.new()
	cam.position = Vector3(0.0, 4.2, 9.0)
	cam.rotation = Vector3(deg_to_rad(-13.0), 0.0, 0.0)
	cam.fov = 72.0
	cam.current = true
	add_child(cam)
	if target:
		global_position = target.global_position
		var f := target.forward_vector()
		_yaw = atan2(-f.x, -f.z)
		rotation.y = _yaw


func toggle_mode() -> void:
	mode = "snap" if mode == "swing" else "swing"


func _process(delta: float) -> void:
	if target == null:
		return
	var f: Vector3 = target.forward_vector()
	var want: float = atan2(-f.x, -f.z)
	if mode == "snap":
		_yaw = want
	else:
		var d: float = wrapf(want - _yaw, -PI, PI)
		# faster the further it has to travel, so a 180 sweeps rather than crawls
		var rate: float = (3.4 + absf(d) * 2.4) * delta
		_yaw += d if absf(d) < rate else signf(d) * rate
	rotation.y = _yaw

	var lead: Vector3 = f * minf(14.0, target.speed * 0.4)
	global_position = global_position.lerp(
		target.global_position + lead, 1.0 - exp(-7.0 * delta))
	var want_z: float = 8.0 + target.speed * 0.14
	cam.position.z = lerpf(cam.position.z, want_z, 1.0 - exp(-3.0 * delta))
