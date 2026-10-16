## Procedural vehicle audio. Nothing is loaded from disk: the continuous motor
## is streamed a frame at a time and the two impacts are short generated WAVs.
class_name VehicleAudio
extends Node

const MIX_RATE := 22050.0

var target: Vehicle

var _engine_player: AudioStreamPlayer
var _engine_playback: AudioStreamGeneratorPlayback
var _swap_player: AudioStreamPlayer
var _rail_player: AudioStreamPlayer
var _phase := 0.0
var _whine_phase := 0.0
var _frequency := 60.0
var _rail_cooldown := 0.0


func _ready() -> void:
	if target == null:
		push_warning("VehicleAudio needs a Vehicle target")
		set_process(false)
		return

	# RigidBody3D only emits body_entered while contact monitoring is enabled.
	target.contact_monitor = true
	target.max_contacts_reported = maxi(target.max_contacts_reported, 8)
	target.swapped.connect(_on_swapped)
	target.body_entered.connect(_on_body_entered)

	# AudioServer is deliberately skipped by headless test runs. The contact
	# wiring above still happens, so scene assembly remains testable.
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.25
	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "Engine"
	_engine_player.stream = generator
	_engine_player.volume_db = -10.0
	add_child(_engine_player)
	_engine_player.play()
	_engine_playback = _engine_player.get_stream_playback() as AudioStreamGeneratorPlayback

	_swap_player = AudioStreamPlayer.new()
	_swap_player.name = "DrivetrainSwap"
	_swap_player.stream = _make_swap_sound()
	_swap_player.volume_db = -3.0
	add_child(_swap_player)

	_rail_player = AudioStreamPlayer.new()
	_rail_player.name = "RailImpact"
	_rail_player.stream = _make_rail_sound()
	add_child(_rail_player)


func _process(delta: float) -> void:
	_rail_cooldown = maxf(0.0, _rail_cooldown - delta)
	if _engine_playback == null or target == null:
		return

	var top_speed := maxf(1.0, target.tuning.top_speed(target.active_end))
	var speed_ratio := clampf(target.speed / top_speed, 0.0, 1.15)
	var throttle := clampf(target.throttle, 0.0, 1.0)
	var brake := clampf(target.brake, 0.0, 1.0)
	var end_b := target.active_end == "B"
	var idle := 44.0 if end_b else 68.0
	var redline := 185.0 if end_b else 330.0
	var wanted := lerpf(idle, redline, clampf(speed_ratio + throttle * 0.09, 0.0, 1.0))
	_frequency = lerpf(_frequency, wanted, 1.0 - exp(-delta * 10.0))

	# With the throttle shut, a higher harmonic comes forward. Its falling pitch
	# follows road speed, which makes lift-off and braking read as deceleration
	# instead of merely a quieter acceleration loop.
	var coast := clampf((1.0 - throttle) * speed_ratio * 0.75 + brake * 0.7, 0.0, 1.0)
	var motor_gain := 0.055 + throttle * 0.11 + speed_ratio * 0.025
	var whine_gain := coast * 0.075
	var whine_hz := 430.0 + speed_ratio * (360.0 if end_b else 720.0)

	var frames := _engine_playback.get_frames_available()
	for _i in frames:
		_phase = fmod(_phase + TAU * _frequency / MIX_RATE, TAU)
		_whine_phase = fmod(_whine_phase + TAU * whine_hz / MIX_RATE, TAU)
		var motor := sin(_phase) + sin(_phase * 2.0) * (0.34 if end_b else 0.46)
		motor += sin(_phase * 3.0) * (0.22 if end_b else 0.12)
		var whine := sin(_whine_phase) * (0.75 + 0.25 * sin(_phase * 0.5))
		var sample := clampf(motor * motor_gain + whine * whine_gain, -0.86, 0.86)
		_engine_playback.push_frame(Vector2(sample, sample))


func _on_swapped(_record: Dictionary) -> void:
	if _swap_player != null:
		_swap_player.play()


func _on_body_entered(body: Node) -> void:
	if not body.has_meta("guard_rail") or not bool(body.get_meta("guard_rail")):
		return
	if _rail_cooldown > 0.0 or target.linear_velocity.length() < 1.5:
		return
	_rail_cooldown = 0.18
	if _rail_player != null:
		var impact := clampf(target.linear_velocity.length() / 28.0, 0.0, 1.0)
		_rail_player.volume_db = lerpf(-13.0, -1.5, impact)
		_rail_player.pitch_scale = lerpf(0.88, 1.08, impact)
		_rail_player.play()


func _make_swap_sound() -> AudioStreamWAV:
	var duration := 0.34
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51A9
	for i in count:
		var t := float(i) / MIX_RATE
		var fall := exp(-t * 12.0)
		var low := sin(TAU * (175.0 - t * 250.0) * t) * fall
		var second_t := maxf(0.0, t - 0.095)
		var second := sin(TAU * (92.0 - second_t * 80.0) * second_t) * exp(-second_t * 18.0)
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 75.0)
		samples[i] = clampf(low * 0.52 + second * 0.38 + click * 0.32, -1.0, 1.0)
	return _wav_from_samples(samples)


func _make_rail_sound() -> AudioStreamWAV:
	var duration := 0.28
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xBA221E2
	for i in count:
		var t := float(i) / MIX_RATE
		var ring := sin(TAU * 710.0 * t) * 0.38 + sin(TAU * 1127.0 * t) * 0.24
		ring += sin(TAU * 1643.0 * t) * 0.13
		var scrape := rng.randf_range(-1.0, 1.0) * 0.32
		samples[i] = clampf((ring + scrape) * exp(-t * 13.0), -1.0, 1.0)
	return _wav_from_samples(samples)


func _wav_from_samples(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = false
	wav.data = bytes
	return wav
