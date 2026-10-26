## Procedural vehicle audio. Nothing is loaded from disk: the continuous motor
## is streamed a frame at a time and the two impacts are short generated WAVs.
class_name VehicleAudio
extends Node

const MIX_RATE := 22050.0
const RAIL_MIN_SPEED := 1.5
const CAR_MIN_SPEED := 2.5
const RAIL_COOLDOWN := 0.18
const CAR_COOLDOWN := 0.25
const FULL_INTENSITY_SPEED := 28.0
const CONTACT_HEAVY = preload("res://assets/audio/items/contact_heavy.wav")

## Emitted for each contact allowed to sound, with or without audio hardware.
## kind is "rail" or "car"; intensity is 0..1.
signal contact_cue(kind: String, intensity: float)

var target: Vehicle
var _car_player: AudioStreamPlayer
var _car_cooldown := 0.0
var _pre_velocity := Vector3.ZERO

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
	_rail_player.stream = make_rail_sound()
	add_child(_rail_player)

	_car_player = AudioStreamPlayer.new()
	_car_player.name = "CarImpact"
	_car_player.stream = make_car_sound()
	add_child(_car_player)


func _process(delta: float) -> void:
	advance(delta)
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


func _exit_tree() -> void:
	if _engine_player != null:
		_engine_player.stop()
		_engine_player.stream = null
	_engine_playback = null


func _on_swapped(_record: Dictionary) -> void:
	if _swap_player != null:
		_swap_player.play()


func _physics_process(_delta: float) -> void:
	if target != null:
		_pre_velocity = target.linear_velocity


## Counts cooldowns down. _process calls it; tests may drive it by hand.
func advance(delta: float) -> void:
	_rail_cooldown = maxf(0.0, _rail_cooldown - delta)
	_car_cooldown = maxf(0.0, _car_cooldown - delta)


## Classifies a touched body: "rail" for guard rails, "car" for another Vehicle,
## "" for anything else (scenery, ground, the car itself).
func contact_kind(body: Node) -> String:
	if body == null or body == target:
		return ""
	if body.has_meta("guard_rail") and bool(body.get_meta("guard_rail")):
		return "rail"
	if body is Vehicle:
		return "car"
	return ""


## Applies speed gating and cooldown. Returns the accepted 0..1 intensity, or
## -1.0 when the contact stays silent. Cosmetic only; never touches physics.
func accept_contact(kind: String, relative_speed: float) -> float:
	var min_speed := RAIL_MIN_SPEED if kind == "rail" else CAR_MIN_SPEED
	if kind.is_empty() or relative_speed < min_speed:
		return -1.0
	if kind == "rail":
		if _rail_cooldown > 0.0:
			return -1.0
		_rail_cooldown = RAIL_COOLDOWN
	else:
		if _car_cooldown > 0.0:
			return -1.0
		_car_cooldown = CAR_COOLDOWN
	return clampf(relative_speed / FULL_INTENSITY_SPEED, 0.0, 1.0)


func _on_body_entered(body: Node) -> void:
	var kind := contact_kind(body)
	if kind.is_empty():
		return
	# The solver has usually reflected the velocity by the time this fires, so
	# judge the hit by the faster of the pre-step and current motion.
	var own := target.linear_velocity
	if _pre_velocity.length() > own.length():
		own = _pre_velocity
	var other := Vector3.ZERO
	if body is RigidBody3D:
		other = (body as RigidBody3D).linear_velocity
	var intensity := accept_contact(kind, (own - other).length())
	if intensity < 0.0:
		return
	contact_cue.emit(kind, intensity)
	var player := _car_player if kind == "car" else _rail_player
	if player != null:
		player.volume_db = lerpf(-13.0, -1.5, intensity)
		player.pitch_scale = lerpf(0.9, 1.05, intensity)
		player.play()


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


## Gritty industrial impacts: broadband crunch, low body thump, short scrape.
## Recorded heavy contact is lowpassed and layered underneath so nothing rings.
static func make_rail_sound() -> AudioStreamWAV:
	return _make_impact(0.30, 0xBA221E2, 52.0, 24.0, 0.45, 0.6, 15.0)


static func make_car_sound() -> AudioStreamWAV:
	return _make_impact(0.40, 0xCA2B0D7, 40.0, 17.0, 0.7, 0.9, 11.0)


static func _make_impact(duration: float, seed_value: int, thump_hz: float, thump_decay: float,
		scrape_gain: float, crunch_gain: float, tail_decay: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * duration)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var slow := 0.0
	var mid := 0.0
	var body := 0.0
	var phase := 0.0
	var gate := 0.0
	var gate_target := 0.0
	var heavy_rate := float(CONTACT_HEAVY.mix_rate)
	for i in count:
		var t := float(i) / MIX_RATE
		var n := rng.randf_range(-1.0, 1.0)
		slow = lerpf(slow, n, 0.04)
		mid = lerpf(mid, n, 0.3)
		# Irregular scrape: a random gate re-rolled every few milliseconds.
		if i % 110 == 0:
			gate_target = maxf(0.0, rng.randf_range(-0.4, 1.0))
		gate = lerpf(gate, gate_target, 0.02)
		var crack := (n - slow) * exp(-t * 140.0) * 0.8
		phase += TAU * (thump_hz + 60.0 * exp(-t * 40.0)) / MIX_RATE
		var thump := sin(phase) * exp(-t * thump_decay) * 0.85
		var scrape := (mid - slow) * gate * exp(-t * 7.0) * 2.0 * scrape_gain
		var offset := int(t * 1.8 * heavy_rate) * 2
		var recorded := 0.0
		if offset + 1 < CONTACT_HEAVY.data.size():
			recorded = float(CONTACT_HEAVY.data.decode_s16(offset)) / 32768.0
		body = lerpf(body, recorded, 0.35)
		var crunch := body * exp(-t * tail_decay) * crunch_gain
		var debris := maxf(0.0, n - 0.5) * rng.randf_range(-1.0, 1.0) * exp(-t * 18.0) * 0.9
		samples[i] = crack + thump + scrape + crunch + debris
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var fade := int(MIX_RATE * 0.02)
	for i in count:
		var edge := minf(float(i) / 12.0, float(count - 1 - i) / fade)
		samples[i] *= 0.8 / peak * clampf(edge, 0.0, 1.0)
	return _wav_from_samples(samples)


static func _wav_from_samples(samples: PackedFloat32Array) -> AudioStreamWAV:
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
