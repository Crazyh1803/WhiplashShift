## Real-time rendered frame probe. Do not run with --fixed-fps.
extends Node

var _scene: Variant
var _label := "sample"
var _last_usec: int = 0
var _start_usec: int = 0
var _frames: Array[float] = []
var _raw_speeds: Array[float] = []
var _visual_speeds: Array[float] = []
var _raw_previous := Vector3.ZERO
var _visual_previous := Vector3.ZERO
var _process_times: Array[float] = []
var _physics_times: Array[float] = []


func _ready() -> void:
	if "--no-interpolation" in OS.get_cmdline_user_args():
		# Diagnostic control only; never change the project's saved setting.
		get_tree().physics_interpolation = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=").get_file()
	GameSession.configure("FRAME PROBE", "blackjack", ["boilerfang", "ramjet"])
	_scene = load("res://scenes/proving_ground.tscn").instantiate()
	add_child(_scene)
	while _scene.race.state == RaceDirector.State.COUNTDOWN:
		await get_tree().physics_frame
	_key(true)
	_start_usec = Time.get_ticks_usec()
	_last_usec = _start_usec
	_raw_previous = _scene.car.global_position
	_visual_previous = _scene.car.get_global_transform_interpolated().origin
	set_process(true)


func _process(_delta: float) -> void:
	if _start_usec == 0:
		return
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _start_usec) / 1000000.0
	var dt := float(now - _last_usec) / 1000000.0
	var raw: Vector3 = _scene.car.global_position
	var visual: Vector3 = _scene.car.get_global_transform_interpolated().origin
	if elapsed > 1.0 and dt > 0.0:
		_frames.append(dt * 1000.0)
		_raw_speeds.append(raw.distance_to(_raw_previous) / dt)
		_visual_speeds.append(visual.distance_to(_visual_previous) / dt)
		_process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_physics_times.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_raw_previous = raw
	_visual_previous = visual
	_last_usec = now
	if elapsed >= 7.0:
		set_process(false)
		_key(false)
		var result := {
			"label": _label, "renderer": RenderingServer.get_video_adapter_name(),
			"interpolation": get_tree().physics_interpolation,
			"frames": _frames.size(), "frame_ms": _stats(_frames),
			"raw_step_speed": _stats(_raw_speeds), "visual_step_speed": _stats(_visual_speeds),
			"process_ms": _stats(_process_times), "physics_ms": _stats(_physics_times),
		}
		var output := ProjectSettings.globalize_path("res://../.ai/captures/smooth-driving")
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join(_label + ".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
		print("FRAME_PROBE ", JSON.stringify(result))
		_scene.queue_free()
		await get_tree().process_frame
		get_tree().quit()


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var sum := 0.0
	var zeroes := 0
	for value: float in values:
		sum += value
		if absf(value) < 0.001:
			zeroes += 1
	var mean := sum / values.size()
	var variance := 0.0
	for value: float in values:
		variance += (value - mean) * (value - mean)
	return {"mean": mean, "stddev": sqrt(variance / values.size()), "zero_fraction": float(zeroes) / values.size(),
		"p50": sorted[int((sorted.size() - 1) * 0.50)],
		"p95": sorted[int((sorted.size() - 1) * 0.95)],
		"p99": sorted[int((sorted.size() - 1) * 0.99)], "max": sorted[-1]}


func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_W
	event.physical_keycode = KEY_W
	event.pressed = pressed
	Input.parse_input_event(event)
