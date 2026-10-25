## Bounded positional item audio with CC0 recorded contact layers and broadband transients.
class_name ItemAudio
extends Node3D

signal cue(sound_id: String)

const CONTACT_SMALL = preload("res://assets/audio/items/contact_small.wav")
const CONTACT_HEAVY = preload("res://assets/audio/items/contact_heavy.wav")

const RATE := 22050
const MAX_VOICES := 16
const DURATIONS := {"machine_guns": 0.13, "rockets": 0.48, "homing": 0.55,
	"grenades": 0.22, "explosion": 1.25, "impact": 0.55, "hit": 0.22,
	"pickup": 0.78, "oil": 0.28, "smoke": 0.35, "shield_on": 0.55,
	"shield_hit": 0.45, "shield_off": 0.35, "shield_hum": 1.0, "smoke_loop": 1.0, "oil_loop": 1.0}
var _cache: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _loops: Dictionary = {}
var _cursor := 0
var _pickup_voice: AudioStreamPlayer


func _ready() -> void:
	# Build the small sample bank during scene loading instead of stalling a first shot.
	if DisplayServer.get_name() != "headless":
		for id: String in DURATIONS:
			sound(id)


func play(id: String, pos: Vector3) -> void:
	cue.emit(id)
	if DisplayServer.get_name() == "headless":
		return
	# Local collection feedback preserves authored stereo instead of 3D downmix/panning.
	if id == "pickup":
		if not is_instance_valid(_pickup_voice):
			_ensure_bus()
			_pickup_voice = AudioStreamPlayer.new()
			_pickup_voice.bus = "ItemFX"
			_pickup_voice.volume_db = -6.0
			add_child(_pickup_voice)
		_pickup_voice.stream = sound(id)
		_pickup_voice.play()
		return
	var voice: AudioStreamPlayer3D
	for candidate in _voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		if _voices.size() >= MAX_VOICES:
			voice = _voices[_cursor % MAX_VOICES]
			_cursor += 1
		else:
			voice = _player()
			_voices.append(voice)
	voice.stop()
	voice.stream = sound(id)
	voice.pitch_scale = randf_range(0.92, 1.08) if id in ["impact", "explosion", "machine_guns", "grenades"] else 1.0
	voice.volume_db = -12.0 if id == "hit" else (-3.0 if id in ["explosion", "rockets", "homing"] else -6.0)
	voice.global_position = pos
	voice.play()


func sound(id: String) -> AudioStreamWAV:
	if not _cache.has(id):
		_cache[id] = make_sound(id)
	return _cache[id]


func sync(cars: Array[Vehicle], active: Array[String]) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for i in cars.size():
		var id := "shield_hum" if active[i] == "shield" else ("smoke_loop" if active[i] == "smoke" else ("oil_loop" if active[i] == "oil" else ""))
		if id.is_empty():
			if _loops.has(i):
				_loops[i].stop()
			continue
		if not _loops.has(i):
			_loops[i] = _player()
		var voice: AudioStreamPlayer3D = _loops[i]
		voice.global_position = cars[i].global_position
		var stream := sound(id)
		if voice.stream != stream or not voice.playing:
			voice.stream = stream
			voice.volume_db = -12.0
			voice.play()


func stop_all() -> void:
	if is_instance_valid(_pickup_voice):
		_pickup_voice.stop()
	for voice in _voices:
		voice.stop()
	for voice: AudioStreamPlayer3D in _loops.values():
		voice.stop()


func _ensure_bus() -> void:
	if AudioServer.get_bus_index("ItemFX") < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "ItemFX")
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -2.0
		limiter.threshold_db = -4.0
		AudioServer.add_bus_effect(index, limiter)


func _player() -> AudioStreamPlayer3D:
	_ensure_bus()
	var voice := AudioStreamPlayer3D.new()
	voice.bus = "ItemFX"
	voice.unit_size = 20.0
	voice.max_distance = 160.0
	voice.attenuation_filter_cutoff_hz = 12000.0
	voice.max_polyphony = 1
	add_child(voice)
	return voice


func _exit_tree() -> void:
	stop_all()
	for voice in _voices:
		voice.stream = null
	for voice: AudioStreamPlayer3D in _loops.values():
		voice.stream = null


static func make_sound(id: String) -> AudioStreamWAV:
	if id == "pickup":
		return _make_pickup()
	var duration: float = DURATIONS.get(id, 0.2)
	var count := int(duration * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	var low := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.07)
		var sample := 0.0
		match id:
			"machine_guns":
				sample = noise * 0.8 * exp(-t * 80) + low * 1.5 * exp(-t * 22)
				sample += _contact(CONTACT_SMALL, t * 1.4) * 0.7 * exp(-t * 10)
			"rockets", "homing":
				sample = (low * 2.2 + noise * 0.16 + sin(TAU * 92 * t) * 0.1) * exp(-t * 4)
				if id == "homing":
					sample += sin(TAU * 900 * t) * 0.14 * exp(-t * 13)
			"grenades":
				sample = _contact(CONTACT_HEAVY, t * 1.7) * 0.8 + low * 0.8 * exp(-t * 20)
			"explosion":
				sample = _contact(CONTACT_HEAVY, t) * 0.9 + low * 2.0 * exp(-t * 3.5)
				sample += noise * 0.45 * exp(-t * 26)
			"impact", "hit":
				# Dry broadband crack, irregular recorded body and short debris tail.
				# Avoid a dominant ringing contact that reads as an electronic chirp.
				sample = (noise - low) * 0.72 * exp(-t * 110)
				sample += _contact(CONTACT_HEAVY, t * 2.2) * 0.68 * exp(-t * 13)
				sample += low * 1.7 * exp(-t * 28)
				var debris := maxf(0.0, noise - 0.35) * rng.randf_range(-1.0, 1.0)
				sample += debris * 0.32 * exp(-t * 17)
				if id == "hit":
					sample *= 0.65
			"oil":
				sample = (sin(TAU * 125 * t + sin(TAU * 32 * t) * 5) * 0.6 + low) * exp(-t * 9)
			"smoke":
				sample = (noise - low) * 0.5 * exp(-t * 7)
			"shield_on", "shield_off":
				var frequency := lerpf(170, 1050, t / duration) if id == "shield_on" else lerpf(800, 100, t / duration)
				phase += TAU * frequency / RATE
				sample = (sin(phase) * 0.4 + sin(phase * 1.5) * 0.16) * sin(PI * t / duration)
			"shield_hit":
				sample = _contact(CONTACT_SMALL, t * 1.2) * 0.8 + (noise - low) * 0.15 * exp(-t * 15)
			"shield_hum":
				sample = sin(TAU * 110 * t) * 0.14 + sin(TAU * 220 * t) * 0.06
			"smoke_loop":
				sample = (noise - low) * 0.12
			"oil_loop":
				sample = low * 0.45 + (noise - low) * 0.03
		var envelope := minf(1, t * 1000) * minf(1, (duration - t) * 100)
		bytes.encode_s16(i * 2, int(clampf(sample * envelope, -0.9, 0.9) * 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = bytes
	if id in ["shield_hum", "smoke_loop", "oil_loop"]:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = count
	return wav


static func _contact(wav: AudioStreamWAV, time: float) -> float:
	var offset := int(time * wav.mix_rate) * 2
	if offset + 1 >= wav.data.size():
		return 0.0
	return float(wav.data.decode_s16(offset)) / 32768.0


## Original arcade pickup: bright FM lift, moving dry image and crossed delay taps.
## Synthesized locally; no sampled audio from R-Type.
static func _make_pickup() -> AudioStreamWAV:
	var count := int(float(DURATIONS["pickup"]) * RATE)
	var dry := PackedFloat32Array()
	dry.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		if t >= 0.43:
			continue
		var rise := clampf(t / 0.36, 0.0, 1.0)
		var frequency := 380.0 * pow(3.7, rise)
		phase += TAU * frequency / RATE
		var attack := minf(t / 0.006, 1.0)
		var release := clampf((0.43 - t) / 0.12, 0.0, 1.0)
		var shimmer := sin(phase + sin(phase * 2.0) * (1.4 - rise))
		dry[i] = (shimmer * 0.34 + sin(phase * 1.5) * 0.12) * attack * release
	var bytes := PackedByteArray()
	bytes.resize(count * 4)
	for i in count:
		var t := float(i) / RATE
		var pan := lerpf(-0.65, 0.65, clampf(t / 0.43, 0.0, 1.0))
		var left := dry[i] * sqrt((1.0 - pan) * 0.5)
		var right := dry[i] * sqrt((1.0 + pan) * 0.5)
		for tap in range(1, 4):
			var delayed := i - int((0.085 * tap) * RATE)
			if delayed >= 0:
				var echo := dry[delayed] * pow(0.43, tap)
				left += echo * (0.9 if tap % 2 else 0.2)
				right += echo * (0.2 if tap % 2 else 0.9)
		var fade := minf(1.0, (float(DURATIONS["pickup"]) - t) * 100.0)
		bytes.encode_s16(i * 4, int(clampf(left * fade, -0.9, 0.9) * 32767))
		bytes.encode_s16(i * 4 + 2, int(clampf(right * fade, -0.9, 0.9) * 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = bytes
	return wav
