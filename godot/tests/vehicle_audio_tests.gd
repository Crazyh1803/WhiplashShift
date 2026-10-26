extends Node3D

var _pass := 0
var _fail := 0


func _ready() -> void:
	_test_pcm_assets()
	_test_routing()
	_test_cooldown_and_gating()
	_test_sound(VehicleAudio.make_rail_sound(), "rail", 0.34)
	_test_sound(VehicleAudio.make_car_sound(), "car", 0.44)
	_test_pickup()
	_test_stale_snapshots()
	await _test_physical_collision()
	await _test_physical_side_contact()
	print("VEHICLE AUDIO: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(1 if _fail else 0)


func _make_car() -> Vehicle:
	var car := Vehicle.new()
	car.freeze = true
	add_child(car)
	return car


func _test_routing() -> void:
	var car := _make_car()
	var audio := VehicleAudio.new()
	audio.target = car
	add_child(audio)
	var rail := StaticBody3D.new()
	rail.set_meta("guard_rail", true)
	var other := _make_car()
	var scenery := StaticBody3D.new()
	_check("rail contact is routed as rail", audio.contact_kind(rail) == "rail")
	_check("another vehicle is routed as car", audio.contact_kind(other) == "car")
	_check("scenery and self are ignored", audio.contact_kind(scenery) == "" and audio.contact_kind(car) == "")
	var heard: Array = []
	audio.contact_cue.connect(func(kind: String, intensity: float) -> void: heard.append([kind, intensity]))
	car.freeze = false
	car.gravity_scale = 0.0
	car.linear_velocity = Vector3(0, 0, 20)
	audio.snapshot_velocities()
	audio._on_body_entered(scenery)
	_check("unrelated body emits no cue", heard.is_empty())
	audio._on_body_entered(rail)
	audio._on_body_entered(other)
	_check("rail and car contacts each emit a cue", heard.size() == 2
		and heard[0][0] == "rail" and heard[1][0] == "car")
	_check("cue intensity stays within 0..1", heard.all(func(h: Array) -> bool: return h[1] > 0.0 and h[1] <= 1.0))
	car.queue_free()
	other.queue_free()
	audio.queue_free()
	rail.free()
	scenery.free()


func _test_pcm_assets() -> void:
	for wav: AudioStreamWAV in [VehicleAudio.CONTACT_HEAVY, ItemAudio.CONTACT_HEAVY, ItemAudio.CONTACT_SMALL]:
		_check("imported contact WAV is raw 16-bit PCM", wav.format == AudioStreamWAV.FORMAT_16_BITS)
	var heavy := VehicleAudio.CONTACT_HEAVY
	_check("heavy contact is mono 22050 Hz with 23146 frames", not heavy.stereo
		and heavy.mix_rate == 22050 and heavy.data.size() == 23146 * 2)
	var peak := 0.0
	for i in range(0, heavy.data.size() - 1, 2):
		peak = maxf(peak, absf(float(heavy.data.decode_s16(i)) / 32768.0))
	_check("heavy contact PCM carries real signal", peak > 0.1)
	var packed := AudioStreamWAV.new()
	packed.format = AudioStreamWAV.FORMAT_IMA_ADPCM
	packed.data = PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	_check("compressed WAV is never read as PCM", ItemAudio.contact_sample(packed, 0.0) == 0.0)
	var heard_recorded := false
	for i in 200:
		if ItemAudio.contact_sample(heavy, float(i) * 0.001) != 0.0:
			heard_recorded = true
	_check("PCM-safe reader returns recorded samples", heard_recorded)


func _test_stale_snapshots() -> void:
	var car := _make_car()
	var other := _make_car()
	var audio := VehicleAudio.new()
	audio.target = car
	add_child(audio)
	car.freeze = false
	car.gravity_scale = 0.0
	car.linear_velocity = Vector3(0, 0, 30)
	audio.snapshot_velocities()
	_check("snapshot sees a moving car against a parked one", audio.relative_speed_to(other) > 25.0)
	# The car is then frozen/teleported: a stale fast snapshot must not sound.
	car.freeze = true
	audio._pre_frame = Engine.get_physics_frames() - 50
	_check("stale snapshot falls back to live, still, velocities", audio.relative_speed_to(other) < 0.01)
	car.queue_free()
	other.queue_free()
	audio.queue_free()


## Two real cars on a collision course; the cue must come from the actual
## body_entered event, with intensity from the pre-impact closing speed.
func _test_physical_collision() -> void:
	var rig := await _physical_rig(Vector3(-6, 0, 0), Vector3(10, 0, 0), Vector3(6, 0, 0), Vector3(-10, 0, 0))
	var heard: Array = rig.heard
	var touched: Array = rig.touched
	for _i in 120:
		await get_tree().physics_frame
		if not heard.is_empty():
			break
	_check("real collision fired body_entered", not touched.is_empty())
	_check("real collision emitted one car cue", heard.size() == 1 and heard[0][0] == "car")
	if not heard.is_empty():
		var expected := 20.0 / VehicleAudio.FULL_INTENSITY_SPEED
		_check("cue intensity follows incoming relative velocity (%.2f vs %.2f)" % [heard[0][1], expected],
			absf(heard[0][1] - expected) < 0.2)
	_free_rig(rig)


## Cars travelling together and touching sideways stay quiet.
func _test_physical_side_contact() -> void:
	var rig := await _physical_rig(Vector3(0, 0, 0), Vector3(0, 0, 15), Vector3(1.6, 0, 0), Vector3(0, 0, 14.5))
	var heard: Array = rig.heard
	var touched: Array = rig.touched
	for _i in 60:
		await get_tree().physics_frame
	_check("side contact fired body_entered", not touched.is_empty())
	_check("near-equal velocity side contact stays quiet", heard.is_empty())
	_free_rig(rig)


func _physical_rig(pos_a: Vector3, vel_a: Vector3, pos_b: Vector3, vel_b: Vector3) -> Dictionary:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -30, 0)
	add_child(floor_body)
	var a := Vehicle.new()
	var b := Vehicle.new()
	for car: Vehicle in [a, b]:
		car.gravity_scale = 0.0
		add_child(car)
	a.global_position = pos_a
	b.global_position = pos_b
	a.linear_velocity = vel_a
	b.linear_velocity = vel_b
	var audio := VehicleAudio.new()
	audio.target = a
	add_child(audio)
	var heard: Array = []
	var touched: Array = []
	audio.contact_cue.connect(func(kind: String, intensity: float) -> void: heard.append([kind, intensity]))
	a.body_entered.connect(func(body: Node) -> void: touched.append(body))
	await get_tree().physics_frame
	return {"floor": floor_body, "a": a, "b": b, "audio": audio, "heard": heard, "touched": touched}


func _free_rig(rig: Dictionary) -> void:
	for key in ["floor", "a", "b", "audio"]:
		(rig[key] as Node).queue_free()


func _test_cooldown_and_gating() -> void:
	var car := _make_car()
	var audio := VehicleAudio.new()
	audio.target = car
	add_child(audio)
	_check("slow rail scrape is silent", audio.accept_contact("rail", 0.5) < 0.0)
	_check("slow car touch is silent", audio.accept_contact("car", 1.0) < 0.0)
	var first := audio.accept_contact("car", 10.0)
	_check("fast car contact is accepted", first > 0.0)
	_check("cooldown blocks chatter", audio.accept_contact("car", 20.0) < 0.0)
	audio.advance(VehicleAudio.CAR_COOLDOWN + 0.01)
	var harder := audio.accept_contact("car", 24.0)
	_check("harder relative speed is louder after cooldown", harder > first)
	_check("rail cooldown is independent of car cooldown", audio.accept_contact("rail", 12.0) > 0.0)
	audio.advance(VehicleAudio.RAIL_COOLDOWN + 0.01)
	_check("intensity saturates at 1", audio.accept_contact("rail", 90.0) == 1.0)
	# Same closing speed as a parked car is quiet; the gate uses relative motion.
	var a := Vector3(0, 0, 20)
	var b := Vector3(0, 0, 19)
	audio.advance(1.0)
	_check("cars moving together make no noise", audio.accept_contact("car", (a - b).length()) < 0.0)
	car.queue_free()
	audio.queue_free()


func _test_sound(wav: AudioStreamWAV, label: String, max_seconds: float) -> void:
	var s := _samples(wav, 0)
	var seconds := float(s.size()) / wav.mix_rate
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	_check(label + " is mono 16-bit PCM and short", not wav.stereo and wav.mix_rate == 22050
		and wav.data.size() == s.size() * 2 and seconds <= max_seconds)
	_check(label + " audible and not clipping", peak > 0.3 and peak <= 0.9)
	var ring := _best_autocorrelation(_highpass(s), 6, 60)
	_check(label + " is broadband, not a ringing tone (%.2f)" % ring, ring < 0.5)
	_check(label + " has noisy high-frequency content", _diff_ratio(s) > 0.05)
	_check(label + " carries a low body thump", _lowpass_share(s, 0.03) > 0.15)
	_check(label + " has no sustained tail", _energy(s, int(s.size() * 0.75), s.size()) < _energy(s, 0, s.size()) * 0.03)


func _test_pickup() -> void:
	var wav := ItemAudio.make_sound("pickup")
	var mono := _samples(wav, 1)
	var rate := float(ItemAudio.RATE)
	_check("pickup is short", float(mono.size()) / rate <= 0.6
		and _energy(mono, int(0.42 * rate), mono.size()) < _energy(mono, 0, mono.size()) * 0.02)
	_check("pickup is dark", _lowpass_share(mono, 0.12) > 0.5)
	var early := _dominant_lag(mono, int(0.10 * rate), int(0.17 * rate))
	var late := _dominant_lag(mono, int(0.24 * rate), int(0.31 * rate))
	_check("pickup confirmation pitch descends", late > early)
	var peak := 0.0
	for v in mono:
		peak = maxf(peak, absf(v))
	_check("pickup does not clip", peak > 0.3 and peak <= 0.9)
	_check("pickup has no bright chime band", _lowpass_share(mono, 0.5) > 0.85)
	_check("pickup includes dirty static", _diff_ratio(mono) > 0.02)


## Decodes PCM to floats. channel 0 = first sample of each frame / mono stream;
## channel 1 = mono mixdown of a stereo stream.
func _samples(wav: AudioStreamWAV, mode: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var step := 4 if wav.stereo else 2
	for offset in range(0, wav.data.size() - step + 1, step):
		var v := float(wav.data.decode_s16(offset)) / 32768.0
		if wav.stereo and mode == 1:
			v = (v + float(wav.data.decode_s16(offset + 2)) / 32768.0) * 0.5
		out.append(v)
	return out


func _energy(s: PackedFloat32Array, from: int, to: int) -> float:
	var e := 0.0
	for i in range(from, mini(to, s.size())):
		e += s[i] * s[i]
	return e


## Share of energy that survives a one-pole lowpass (alpha ~ cutoff / rate * 2pi).
func _lowpass_share(s: PackedFloat32Array, alpha: float) -> float:
	var y := 0.0
	var low := 0.0
	for v in s:
		y = lerpf(y, v, alpha)
		low += y * y
	return low / maxf(_energy(s, 0, s.size()), 0.000001)


## Removes the low thump so tonal ringing above ~300 Hz is what is left to judge.
func _highpass(s: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(s.size())
	var y := 0.0
	for i in s.size():
		y = lerpf(y, s[i], 0.05)
		out[i] = s[i] - y
	return out


func _diff_ratio(s: PackedFloat32Array) -> float:
	var d := 0.0
	for i in range(1, s.size()):
		d += (s[i] - s[i - 1]) * (s[i] - s[i - 1])
	return d / maxf(_energy(s, 0, s.size()), 0.000001)


func _autocorr(s: PackedFloat32Array, from: int, to: int, lag: int) -> float:
	var num := 0.0
	var den := 0.0
	for i in range(from, to - lag):
		num += s[i] * s[i + lag]
		den += s[i] * s[i]
	return num / maxf(den, 0.000001)


func _best_autocorrelation(s: PackedFloat32Array, min_lag: int, max_lag: int) -> float:
	var best := 0.0
	for lag in range(min_lag, max_lag):
		best = maxf(best, _autocorr(s, 0, s.size(), lag))
	return best


func _dominant_lag(s: PackedFloat32Array, from: int, to: int) -> int:
	var best := 0.0
	var best_lag := 0
	for lag in range(30, 220):
		var c := _autocorr(s, from, to, lag)
		if c > best:
			best = c
			best_lag = lag
	return best_lag


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  [%s] %s" % ["pass" if ok else "FAIL", label])
